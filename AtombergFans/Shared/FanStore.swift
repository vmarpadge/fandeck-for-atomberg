// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Vineethkumar Marpadge

import Foundation

/// Fan list, last known state and quota bookkeeping, shared between the app
/// and the widget extension through the app group's UserDefaults.
final class FanStore: @unchecked Sendable {
    static let shared = FanStore()

    struct Cache: Codable {
        var fans: [Fan] = []
        var fansFetchedAt: Date?
        var states: [String: FanState] = [:]
        var statesFetchedAt: Date?
        /// Fans whose state was set optimistically and still needs confirming.
        var pending: Set<String> = []
        var verifyAt: Date?
        var blockedUntil: Date?
        var lastError: String?
        var callsDay = ""
        var callsCount = 0

        var callsToday: Int { callsDay == FanStore.dayKey(Date()) ? callsCount : 0 }
    }

    private let defaults: UserDefaults
    private let cacheKey = "fanCache.v1"
    private let lock = NSLock()
    private var inFlight: Task<Cache, Never>?
    private var inFlightID: UUID?

    init() {
        // The menu bar build has no app group, so it uses its own defaults.
        defaults = AppConfig.appGroupID.isEmpty ? .standard : UserDefaults(suiteName: AppConfig.appGroupID) ?? .standard
    }

    var cache: Cache {
        guard let data = defaults.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return Cache() }
        return cache
    }

    func update(_ body: (inout Cache) -> Void) {
        lock.withLock {
            var current = cache
            body(&current)
            if let data = try? JSONEncoder().encode(current) {
                defaults.set(data, forKey: cacheKey)
            }
        }
    }

    func recordCall() {
        update { cache in
            let today = Self.dayKey(Date())
            if cache.callsDay != today {
                cache.callsDay = today
                cache.callsCount = 0
            }
            cache.callsCount += 1
        }
    }

    func recordError(_ error: Error) {
        update { $0.lastError = error.localizedDescription }
    }

    /// Fetches from the cloud only when the cache is stale, a toggle needs
    /// verifying, or `force` is set. Concurrent non-forced callers share one request.
    func refresh(force: Bool = false) async -> Cache {
        let task: Task<Cache, Never> = lock.withLock {
            if !force, let inFlight { return inFlight }
            let id = UUID()
            let task = Task {
                let result = await self.performRefresh(force: force)
                // The lock is held until `inFlightID` is assigned below, so this can't run first.
                self.lock.withLock { if self.inFlightID == id { self.inFlight = nil } }
                return result
            }
            inFlight = task
            inFlightID = id
            return task
        }
        return await task.value
    }

    func setPower(_ on: Bool, fanID: String) async throws {
        try await AtombergAPI.shared.setPower(on, fanID: fanID)
        applyOptimistic(fanID: fanID) { $0.power = on }
    }

    func setSpeed(_ speed: Int, fanID: String) async throws {
        try await AtombergAPI.shared.setSpeed(speed, fanID: fanID)
        applyOptimistic(fanID: fanID) { $0.power = true; $0.speed = speed }
    }

    func setLight(_ on: Bool, fanID: String) async throws {
        try await AtombergAPI.shared.setLight(on, fanID: fanID)
        applyOptimistic(fanID: fanID) { $0.light = on }
    }

    /// Shows the commanded state right away and schedules a read to confirm it.
    private func applyOptimistic(fanID: String, _ change: (inout FanState) -> Void) {
        update { cache in
            var state = cache.states[fanID] ?? FanState(power: false, speed: nil, light: nil, isOnline: true, reportedAt: nil)
            change(&state)
            cache.states[fanID] = state
            cache.pending.insert(fanID)
            cache.verifyAt = Date().addingTimeInterval(AppConfig.verifyDelay)
            cache.lastError = nil
        }
    }

    func nextReload(for cache: Cache) -> Date {
        let now = Date()
        var candidates = [cache.statesFetchedAt.map { $0.addingTimeInterval(AppConfig.stateRefreshInterval) } ?? now.addingTimeInterval(AppConfig.stateRefreshInterval)]
        if let verifyAt = cache.verifyAt { candidates.append(verifyAt) }
        if let blockedUntil = cache.blockedUntil, blockedUntil > now { candidates = [blockedUntil] }
        return max(candidates.min() ?? now, now.addingTimeInterval(5))
    }

    private func performRefresh(force: Bool) async -> Cache {
        let current = cache
        let now = Date()
        if let blockedUntil = current.blockedUntil, blockedUntil > now, !force { return current }
        guard CredentialStore.isConfigured else {
            update { $0.lastError = AtombergError.notConfigured.errorDescription }
            return cache
        }

        let needDevices = current.fans.isEmpty
            || current.fansFetchedAt.map { now.timeIntervalSince($0) > AppConfig.deviceListRefreshInterval } ?? true
        let verifyDue = current.verifyAt.map { $0 <= now } ?? false
        let statesStale = current.statesFetchedAt.map { now.timeIntervalSince($0) >= AppConfig.stateRefreshInterval - 60 } ?? true
        let lowBudget = current.callsToday >= AppConfig.dailyQuota - AppConfig.reservedForCommands
        guard force || verifyDue || needDevices || (statesStale && !lowBudget) else { return current }

        do {
            if needDevices {
                let fans = try await AtombergAPI.shared.devices()
                update { $0.fans = fans; $0.fansFetchedAt = Date() }
            }
            let states = try await AtombergAPI.shared.states()
            update { cache in
                var merged = states
                // A command sent while this fetch was in flight is newer than what we
                // just read: keep its optimistic state and its pending verification.
                let commandedDuringFetch = cache.verifyAt.map { $0.addingTimeInterval(-AppConfig.verifyDelay) > now } ?? false
                if commandedDuringFetch {
                    for id in cache.pending { merged[id] = cache.states[id] ?? merged[id] }
                } else {
                    cache.pending = []
                    cache.verifyAt = nil
                }
                cache.states = merged
                cache.statesFetchedAt = Date()
                cache.blockedUntil = nil
                cache.lastError = nil
            }
        } catch AtombergError.quotaExceeded {
            update { cache in
                cache.blockedUntil = Date().addingTimeInterval(AppConfig.quotaBackoff)
                cache.verifyAt = nil
                cache.lastError = AtombergError.quotaExceeded.errorDescription
            }
        } catch {
            update { cache in
                cache.verifyAt = nil
                cache.lastError = error.localizedDescription
            }
        }
        return cache
    }

    static func dayKey(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}

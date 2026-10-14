// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Vineethkumar Marpadge

import ServiceManagement
import SwiftUI

@main
struct AtombergMenuBarApp: App {
    @StateObject private var model = MenuBarModel()

    var body: some Scene {
        MenuBarExtra {
            FanMenu(model: model)
        } label: {
            Image(systemName: model.anyOn ? "fan.ceiling.fill" : "fan.ceiling")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class MenuBarModel: ObservableObject {
    @Published var cache = FanStore.shared.cache
    @Published var busy = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var message: String?
    @Published var draftSpeeds: [String: Double] = [:]

    // Credential entry (so no Terminal is needed).
    @Published var configured = CredentialStore.isConfigured
    @Published var draftAPIKey = ""
    @Published var draftRefreshToken = ""

    var anyOn: Bool {
        cache.fans.contains { cache.states[$0.id]?.power == true && cache.states[$0.id]?.isOnline == true }
    }

    init() {
        // FanStore skips the network unless state is stale, so waking often is free.
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(force: false)
                try? await Task.sleep(for: .seconds(5 * 60))
            }
        }
    }

    func refresh(force: Bool) async {
        busy = true
        cache = await FanStore.shared.refresh(force: force)
        message = cache.lastError
        busy = false
    }

    func setPower(_ on: Bool, fan: Fan) async {
        await run { try await FanStore.shared.setPower(on, fanID: fan.id) }
    }

    func setSpeed(_ speed: Int, fan: Fan) async {
        await run { try await FanStore.shared.setSpeed(speed, fanID: fan.id) }
    }

    func setLight(_ on: Bool, fan: Fan) async {
        await run { try await FanStore.shared.setLight(on, fanID: fan.id) }
    }

    private func run(_ command: () async throws -> Void) async {
        do {
            try await command()
            message = nil
        } catch {
            message = error.localizedDescription
        }
        cache = FanStore.shared.cache
        try? await Task.sleep(for: .seconds(AppConfig.verifyDelay))
        await refresh(force: false)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            message = "Login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func saveCredentials() {
        let key = draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = draftRefreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !refreshToken.isEmpty else {
            message = "Both the API key and refresh token are required."
            return
        }
        do {
            try CredentialStore.set(key, for: .apiKey)
            try CredentialStore.set(refreshToken, for: .refreshToken)
            CredentialStore.delete(.accessToken)
            draftAPIKey = ""
            draftRefreshToken = ""
            configured = true
            message = nil
            Task { await refresh(force: true) }
        } catch {
            message = error.localizedDescription
        }
    }

    func removeCredentials() {
        CredentialStore.delete(.apiKey)
        CredentialStore.delete(.refreshToken)
        CredentialStore.delete(.accessToken)
        configured = false
        cache = FanStore.shared.cache
        message = nil
    }
}

struct FanMenu: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("FanDeck").font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { Task { await model.refresh(force: true) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now (uses 1 API call)")
            }

            if !model.configured {
                CredentialEntry(model: model)
            } else if model.cache.fans.isEmpty {
                Text(model.message ?? "Loading…").font(.callout).foregroundStyle(.secondary)
            }

            ForEach(model.cache.fans) { fan in
                FanMenuRow(fan: fan,
                           state: model.cache.states[fan.id],
                           pending: model.cache.pending.contains(fan.id),
                           onToggle: { on in Task { await model.setPower(on, fan: fan) } },
                           onSpeed: { speed in Task { await model.setSpeed(speed, fan: fan) } },
                           onLight: { on in Task { await model.setLight(on, fan: fan) } },
                           draftSpeed: model.draftSpeeds[fan.id],
                           setDraftSpeed: { model.draftSpeeds[fan.id] = $0 })
            }

            if let message = model.message, !model.cache.fans.isEmpty {
                Text(message).font(.caption).foregroundStyle(.orange)
            }

            Divider()

            HStack {
                if let updated = model.cache.statesFetchedAt {
                    Text("Updated \(updated, style: .time)")
                }
                Spacer()
                Text("\(model.cache.callsToday)/\(AppConfig.dailyQuota) calls today")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                if model.configured {
                    Button("Remove credentials", role: .destructive) { model.removeCredentials() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 300)
        .task { await model.refresh(force: false) }
    }
}

struct CredentialEntry: View {
    @ObservedObject var model: MenuBarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Enter your Atomberg developer credentials from the Atomberg Home app → Profile → Developer Options.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("API key", text: $model.draftAPIKey)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            SecureField("Refresh token", text: $model.draftRefreshToken)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)

            Button("Save") { model.saveCredentials() }
                .controlSize(.small)
                .disabled(model.draftAPIKey.isEmpty || model.draftRefreshToken.isEmpty)

            if let message = model.message {
                Text(message).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FanMenuRow: View {
    let fan: Fan
    let state: FanState?
    let pending: Bool
    let onToggle: (Bool) -> Void
    let onSpeed: (Int) -> Void
    let onLight: (Bool) -> Void

    /// Value while dragging; nil means follow the fan's reported speed. Held by the
    /// model because Command Line Tools lack the SwiftUI macro plugin `@State` needs.
    let draftSpeed: Double?
    let setDraftSpeed: (Double?) -> Void

    private var isOn: Bool { state?.power ?? false }
    private var online: Bool { state?.isOnline ?? false }
    private var reportedSpeed: Double { Double(state?.speed ?? 1) }

    var body: some View {
        VStack(spacing: 4) {
            powerRow
            if online {
                speedRow
                if state?.light != nil {
                    lightRow
                }
            }
        }
        .opacity(online ? 1 : 0.5)
    }

    private var lightRow: some View {
        HStack(spacing: 8) {
            Image(systemName: (state?.light ?? false) ? "lightbulb.fill" : "lightbulb")
                .font(.caption)
                .foregroundStyle((state?.light ?? false) ? Color.yellow : .secondary)
                .frame(width: 24)
            Text("Light")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: Binding(get: { state?.light ?? false }, set: onLight))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
        }
    }

    private var speedRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            // Sends one command on release, not while dragging, to save quota.
            Slider(value: Binding(get: { draftSpeed ?? reportedSpeed }, set: { setDraftSpeed($0) }),
                   in: 1...6, step: 1) { editing in
                guard !editing, let speed = draftSpeed else { return }
                if Int(speed) != state?.speed || !isOn { onSpeed(Int(speed)) }
                setDraftSpeed(nil)
            }
            .controlSize(.small)
            Text("\(Int(draftSpeed ?? reportedSpeed))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 12)
        }
    }

    private var powerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: isOn ? "fan.ceiling.fill" : "fan.ceiling")
                .font(.title3)
                .foregroundStyle(isOn && online ? Color.teal : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(fan.name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: onToggle))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .disabled(!online)
        }
    }

    private var detail: String {
        guard let state else { return "Unknown" }
        if !state.isOnline { return "Offline" }
        if pending { return isOn ? "Turning on…" : "Turning off…" }
        return isOn ? "On · Speed \(state.speed ?? 0)" : "Off"
    }
}

// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Vineethkumar Marpadge

import Foundation

enum AtombergError: LocalizedError {
    case notConfigured
    case quotaExceeded
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your API key and refresh token in the FanDeck app."
        case .quotaExceeded: return "Atomberg API quota reached (100 calls/day)."
        case let .http(code, message): return "Atomberg API error \(code): \(message)"
        case .badResponse: return "Unexpected response from the Atomberg API."
        }
    }
}

/// Client for https://developer.atomberg-iot.com (v2).
actor AtombergAPI {
    static let shared = AtombergAPI()

    private let base = URL(string: "https://api.developer.atomberg-iot.com/v2")!
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()

    func devices() async throws -> [Fan] {
        guard let message = try await call("GET", "get_list_of_devices")["message"] as? [String: Any],
              let list = message["devices_list"] as? [[String: Any]] else { throw AtombergError.badResponse }
        return list.compactMap { device in
            guard let id = device["device_id"] as? String,
                  let series = device["series"] as? String,
                  let first = series.first, "RKIMS".contains(first) else { return nil }
            return Fan(id: id, name: device["name"] as? String ?? id, series: series)
        }
    }

    /// `device_id=all` returns every device for a single call of quota.
    func states() async throws -> [String: FanState] {
        guard let message = try await call("GET", "get_device_state", query: ["device_id": "all"])["message"] as? [String: Any],
              let list = message["device_state"] as? [[String: Any]] else { throw AtombergError.badResponse }
        var states: [String: FanState] = [:]
        for item in list {
            guard let id = item["device_id"] as? String else { continue }
            states[id] = FanState(
                power: item["power"] as? Bool ?? false,
                speed: item["last_recorded_speed"] as? Int,
                light: (item["led"] ?? item["light"]) as? Bool,
                isOnline: item["is_online"] as? Bool ?? false,
                reportedAt: (item["ts_epoch_seconds"] as? Double).map { Date(timeIntervalSince1970: $0) }
            )
        }
        return states
    }

    /// A 200 means the command was accepted, not that the fan has applied it.
    func setPower(_ on: Bool, fanID: String) async throws {
        try await sendCommand(["power": on], fanID: fanID)
    }

    /// Speed is 1-6. Including `power: true` lets one call start a fan that is off.
    func setSpeed(_ speed: Int, fanID: String) async throws {
        try await sendCommand(["power": true, "speed": speed], fanID: fanID)
    }

    /// Toggles the fan's LED/light. The public API exposes light as on/off only (no dimming).
    func setLight(_ on: Bool, fanID: String) async throws {
        try await sendCommand(["led": on], fanID: fanID)
    }

    private func sendCommand(_ command: [String: Any], fanID: String) async throws {
        _ = try await call("POST", "send_command", body: ["device_id": fanID, "command": command])
    }

    private func call(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil) async throws -> [String: Any] {
        // Fetched outside the `do` so a failing token request isn't retried as well.
        let token = try await accessToken()
        do {
            return try await send(method, path, query: query, body: body, bearer: token)
        } catch AtombergError.http(401, _) {
            return try await send(method, path, query: query, body: body, bearer: try await accessToken(forceRefresh: true))
        }
    }

    /// Access tokens last 24h and each new one costs a call, so reuse the cached one.
    private func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh,
           let raw = CredentialStore.read(.accessToken),
           let cached = try? JSONDecoder().decode(CachedToken.self, from: Data(raw.utf8)),
           cached.expiresAt > Date().addingTimeInterval(60 * 60) {
            return cached.token
        }
        guard let refreshToken = CredentialStore.read(.refreshToken) else { throw AtombergError.notConfigured }
        guard let message = try await send("GET", "get_access_token", bearer: refreshToken)["message"] as? [String: Any],
              let token = message["access_token"] as? String else { throw AtombergError.badResponse }
        let cached = CachedToken(token: token, expiresAt: Date().addingTimeInterval(24 * 60 * 60))
        if let data = try? JSONEncoder().encode(cached) {
            try? CredentialStore.set(String(decoding: data, as: UTF8.self), for: .accessToken)
        }
        return token
    }

    private func send(_ method: String, _ path: String, query: [String: String] = [:], body: [String: Any]? = nil, bearer: String) async throws -> [String: Any] {
        guard let apiKey = CredentialStore.read(.apiKey) else { throw AtombergError.notConfigured }
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await session.data(for: request)
        FanStore.shared.recordCall()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            if status == 429 { throw AtombergError.quotaExceeded }
            let message = json["message"].map { "\($0)" } ?? HTTPURLResponse.localizedString(forStatusCode: status)
            throw AtombergError.http(status, message)
        }
        return json
    }
}

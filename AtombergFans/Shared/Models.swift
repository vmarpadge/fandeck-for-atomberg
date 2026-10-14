// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Vineethkumar Marpadge

import Foundation

enum AppConfig {
    /// Team-prefixed app group, injected into both Info.plists at build time.
    static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? ""

    /// Atomberg default quota: 100 calls/day, 5 calls/second.
    static let dailyQuota = 100
    /// Calls kept in reserve for power commands; background polling stops at this point.
    static let reservedForCommands = 15

    static let stateRefreshInterval: TimeInterval = 60 * 60
    static let deviceListRefreshInterval: TimeInterval = 24 * 60 * 60
    /// The API acknowledges a command before the fan applies it, so re-read state after this delay.
    static let verifyDelay: TimeInterval = 8
    static let quotaBackoff: TimeInterval = 60 * 60
}

struct Fan: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let series: String
}

struct FanState: Codable, Hashable {
    var power: Bool
    var speed: Int?
    /// Light (LED) on/off. nil when the API doesn't report it for this fan.
    var light: Bool?
    var isOnline: Bool
    var reportedAt: Date?
}

struct CachedToken: Codable {
    let token: String
    let expiresAt: Date
}

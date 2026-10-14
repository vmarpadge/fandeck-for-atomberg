// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Vineethkumar Marpadge

import Foundation
import Security

/// Menu bar build's CredentialStore. The long-lived secrets (api_key /
/// refresh_token) live in the login Keychain as generic-password items under
/// service "atomberg", read and written in-process via the Security framework
/// (no shelling out to `security`, so secrets never appear in process arguments).
/// Compiled instead of Shared/CredentialStore.swift; needs no entitlement.
enum CredentialStore {
    enum Key: String {
        case apiKey = "api_key"
        case refreshToken = "refresh_token"
        case accessToken = "access_token"
    }

    private static let service = "atomberg"
    private static let lock = NSLock()
    private static var memo: [Key: String] = [:]
    private static let tokenFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/atomberg/menubar-token.json")

    static var isConfigured: Bool { read(.apiKey) != nil && read(.refreshToken) != nil }

    static func read(_ key: Key) -> String? {
        if key == .accessToken {
            return try? String(contentsOf: tokenFile, encoding: .utf8)
        }
        if let cached = lock.withLock({ memo[key] }) { return cached }
        guard let value = keychainRead(account: key.rawValue) else { return nil }
        lock.withLock { memo[key] = value }
        return value
    }

    /// The access token is cached to a 0600 file; the long-lived secrets go into
    /// the login Keychain via SecItemAdd / SecItemUpdate.
    static func set(_ value: String, for key: Key) throws {
        if key == .accessToken {
            let dir = tokenFile.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: tokenFile.path, contents: Data(value.utf8),
                                           attributes: [.posixPermissions: 0o600])
            return
        }
        try keychainWrite(account: key.rawValue, value: value)
        lock.withLock { memo[key] = value }
    }

    static func delete(_ key: Key) {
        if key == .accessToken {
            try? FileManager.default.removeItem(at: tokenFile)
        } else {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key.rawValue,
            ]
            SecItemDelete(query as CFDictionary)
            lock.withLock { memo[key] = nil }
        }
    }

    // MARK: - Security framework helpers

    private static func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    /// Adds the item, or updates it in place if it already exists.
    private static func keychainWrite(account: String, value: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)

        let updateStatus = SecItemUpdate(base as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            // Readable after first unlock; stays on this device only.
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AtombergError.http(0, "Could not save atomberg/\(account) to the Keychain (OSStatus \(addStatus)).")
            }
            return
        }

        throw AtombergError.http(0, "Could not update atomberg/\(account) in the Keychain (OSStatus \(updateStatus)).")
    }
}

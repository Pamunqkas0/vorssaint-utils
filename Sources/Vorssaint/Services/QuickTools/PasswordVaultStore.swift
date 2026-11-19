// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CryptoKit
import Security

struct PasswordVaultItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var username: String
    var password: String
    var website: String = ""
    var category: String = "Login"
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

struct PasswordVaultDocument: Codable, Equatable {
    var version: Int = 1
    var items: [PasswordVaultItem] = []
}

struct PasswordVaultStore {
    private static let keychainService = "com.vorssaint.utils.passwordvault"
    private static let keychainAccount = "vault-aes-key"

    static var fileURL: URL? {
        guard let container = PrivateFileStore.containerURL else { return nil }
        return container.appendingPathComponent("PasswordVault.enc")
    }

    private static func getOrCreateKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }

        // Generate a new 256-bit symmetric key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(addQuery as CFDictionary, nil)
        return newKey
    }

    static func load() -> PasswordVaultDocument {
        guard let url = fileURL, FileManager.default.fileExists(atPath: url.path) else {
            return PasswordVaultDocument()
        }

        do {
            let encryptedData = try Data(contentsOf: url)
            guard !encryptedData.isEmpty else { return PasswordVaultDocument() }
            let key = try getOrCreateKey()
            let box = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(box, using: key)
            return try JSONDecoder().decode(PasswordVaultDocument.self, from: decryptedData)
        } catch {
            return PasswordVaultDocument()
        }
    }

    @discardableResult
    static func save(_ document: PasswordVaultDocument) -> Bool {
        guard let container = PrivateFileStore.containerURL,
              let url = fileURL else { return false }

        do {
            let key = try getOrCreateKey()
            let jsonData = try JSONEncoder().encode(document)
            let sealed = try AES.GCM.seal(jsonData, using: key)
            guard let combined = sealed.combined else { return false }

            PrivateFileStore.createDirectory(at: container)
            return PrivateFileStore.write(combined, to: url)
        } catch {
            return false
        }
    }
}

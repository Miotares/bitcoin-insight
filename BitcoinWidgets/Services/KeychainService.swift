//
//  KeychainService.swift
//  BitcoinWidgets
//

import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let walletsKey = "com.bitcoinwidgets.wallets"

    // MARK: - Wallet Persistence

    func saveWallets(_ wallets: [Wallet]) {
        guard let data = try? JSONEncoder().encode(wallets) else { return }
        save(key: walletsKey, data: data)
    }

    func loadWallets() -> [Wallet] {
        guard let data = load(key: walletsKey),
              let wallets = try? JSONDecoder().decode([Wallet].self, from: data) else {
            return []
        }
        return wallets
    }

    // MARK: - Generic Keychain Operations

    func save(key: String, data: Data) {
        delete(key: key)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func load(key: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

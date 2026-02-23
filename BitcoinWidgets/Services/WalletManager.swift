//
//  WalletManager.swift
//  BitcoinWidgets
//

import Foundation
import Combine
import SwiftUI

final class WalletManager: ObservableObject {
    static let shared = WalletManager()

    @Published private(set) var wallets: [Wallet] = []

    private init() {
        wallets = KeychainService.shared.loadWallets()
    }

    // MARK: - CRUD

    func addWallet(_ wallet: Wallet) {
        wallets.append(wallet)
        persist()
    }

    func removeWallet(_ wallet: Wallet) {
        wallets.removeAll { $0.id == wallet.id }
        persist()
    }

    func updateWallet(_ wallet: Wallet) {
        if let idx = wallets.firstIndex(where: { $0.id == wallet.id }) {
            wallets[idx] = wallet
            persist()
        }
    }

    func moveWallet(from source: IndexSet, to destination: Int) {
        wallets.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        KeychainService.shared.saveWallets(wallets)
    }
}

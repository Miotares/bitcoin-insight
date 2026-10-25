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
        persist(debounce: false)
    }

    func removeWallet(_ wallet: Wallet) {
        wallets.removeAll { $0.id == wallet.id }
        persist(debounce: false)
    }

    /// Sync progress lands here many times per scan, so the write is coalesced.
    func updateWallet(_ wallet: Wallet) {
        if let idx = wallets.firstIndex(where: { $0.id == wallet.id }) {
            wallets[idx] = wallet
            persist(debounce: true)
        }
    }

    func moveWallet(from source: IndexSet, to destination: Int) {
        wallets.move(fromOffsets: source, toOffset: destination)
        persist(debounce: false)
    }

    // MARK: - Persistence

    /// JSON-encoding every wallet + a Keychain round-trip used to run synchronously
    /// on the main thread for EVERY sync step (incl. each isSyncing toggle). Writes
    /// now run on a serial background queue, and sync updates are coalesced so a
    /// burst of progress saves costs one write. Losing the last ≤ 0.5 s of progress
    /// on a kill is harmless: the scan resumes from what was saved.
    private let persistQueue = DispatchQueue(label: "miotares.BitcoinWidgets.walletPersist", qos: .utility)
    private var pendingPersist: DispatchWorkItem?

    private func persist(debounce: Bool) {
        pendingPersist?.cancel()
        let snapshot = wallets
        let work = DispatchWorkItem { KeychainService.shared.saveWallets(snapshot) }
        pendingPersist = work
        persistQueue.asyncAfter(deadline: .now() + (debounce ? 0.5 : 0), execute: work)
    }

    /// Writes any coalesced update now — called when the app leaves the foreground.
    func flushPendingWrites() {
        guard let pending = pendingPersist, !pending.isCancelled else { return }
        pending.cancel()
        let snapshot = wallets
        persistQueue.async { KeychainService.shared.saveWallets(snapshot) }
    }
}

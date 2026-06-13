//
//  WalletViewModel.swift
//  BitcoinWidgets
//

import Foundation
import SwiftUI
import Combine

enum WalletError: LocalizedError {
    case duplicate
    var errorDescription: String? {
        switch self {
        case .duplicate: return "This wallet has already been added."
        }
    }
}

@MainActor
class WalletViewModel: ObservableObject {

    // MARK: - Published

    @Published var wallets: [Wallet] = []
    @Published var totalBalanceSats: Int = 0
    @Published var totalBalanceFiat: Double = 0
    @Published var errorMessage: String? = nil

    private var gapLimit: Int { settings.gapLimit }
    /// Max simultaneous address lookups. Kept modest so bursts stay within
    /// mempool.space limits; the 429 back-off in WalletAPIService is the safety net.
    private let maxConcurrentRequests = 5
    private var settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    // Serial sync queue — prevents concurrent syncs from triggering rate limits
    private var syncQueue: [UUID] = []
    private var isSyncQueueRunning = false

    // MARK: - Init

    init() {
        wallets = WalletManager.shared.wallets
        WalletManager.shared.$wallets
            .receive(on: DispatchQueue.main)
            .assign(to: &$wallets)
        updateTotals()

        // Recompute fiat whenever the shared price store or currency preference changes
        settings.$btcPrices
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeFiat() }
            .store(in: &cancellables)

        settings.$preferredCurrency
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeFiat() }
            .store(in: &cancellables)

        $totalBalanceSats
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeFiat() }
            .store(in: &cancellables)

        resumePendingSyncs()
    }

    // MARK: - Resume pending syncs on app launch

    /// Wallets that never completed their initial scan (lastScanned == nil) are
    /// restarted automatically when the app opens.
    private func resumePendingSyncs() {
        for wallet in wallets where wallet.lastScanned == nil {
            var syncing = wallet
            syncing.isSyncing = true
            WalletManager.shared.updateWallet(syncing)
            enqueueSyncAndRun(walletID: wallet.id)
        }
    }

    // MARK: - Serial Sync Queue

    private func enqueueSyncAndRun(walletID: UUID) {
        guard !syncQueue.contains(walletID) else { return }
        syncQueue.append(walletID)
        guard !isSyncQueueRunning else { return }
        isSyncQueueRunning = true
        Task { @MainActor [weak self] in await self?.drainSyncQueue() }
    }

    private func drainSyncQueue() async {
        while !syncQueue.isEmpty {
            let walletID = syncQueue.removeFirst()
            await backgroundSync(walletID: walletID)
        }
        isSyncQueueRunning = false
    }

    // MARK: - Add Wallet

    /// Validates locally (no API, instant), saves wallet immediately,
    /// then starts a slow background scan. Throws on invalid key or duplicate.
    func addWallet(name: String, publicKey: String) async throws {
        let trimmedKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = detectWalletType(trimmedKey)
        errorMessage = nil

        // Duplicate check — same public key already tracked
        if WalletManager.shared.wallets.contains(where: { $0.publicKey == trimmedKey }) {
            throw WalletError.duplicate
        }

        // Pure local validation — derive the first address to catch bad keys.
        // No network, completes in milliseconds.
        if type.isHDWallet {
            _ = try AddressDeriver.deriveAddress(from: trimmedKey, chain: 0, index: 0, type: type)
        }

        let wallet = Wallet(
            id: UUID(),
            name: name,
            publicKey: trimmedKey,
            type: type,
            colorHex: defaultColor(),
            addresses: [],
            transactions: [],
            lastScanned: nil,
            isSyncing: true
        )
        WalletManager.shared.addWallet(wallet)
        updateTotals()                          // show 0 BTC in total right away

        enqueueSyncAndRun(walletID: wallet.id)
    }

    // MARK: - Remove / Rename

    func removeWallet(_ wallet: Wallet) {
        WalletManager.shared.removeWallet(wallet)
        updateTotals()
    }

    func renameWallet(_ wallet: Wallet, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = wallet
        updated.name = trimmed
        WalletManager.shared.updateWallet(updated)
    }

    // MARK: - Refresh (pull-to-refresh — blocking, user expects to wait)

    func refreshAll() async {
        Haptics.trigger(.medium)
        // Return immediately so the pull-to-refresh indicator disappears at once.
        // The actual sync runs in an independent unstructured Task — not a child
        // of SwiftUI's refreshable task — so URLSession calls are never cancelled
        // by the re-renders that fire when isSyncing changes via Combine.
        Task { @MainActor [weak self] in
            guard let self else { return }
            for wallet in wallets {
                await refreshWallet(wallet)
            }
        }
    }

    /// Fire-and-forget wrapper for detail-view pull-to-refresh.
    /// Returns immediately for the same reason as refreshAll().
    func refreshSingle(_ wallet: Wallet) async {
        Haptics.trigger(.light)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshWallet(wallet)
        }
    }

    func refreshWallet(_ wallet: Wallet) async {
        errorMessage = nil
        // Read directly from WalletManager to avoid Combine-lag race conditions
        let live = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        guard !live.isSyncing else { return }

        var syncing = live
        syncing.isSyncing = true
        WalletManager.shared.updateWallet(syncing)

        do {
            var updated: Wallet
            if live.type.isHDWallet {
                // Incremental if we already have data; full scan if first time
                updated = live.addresses.isEmpty
                    ? try await scanHDWallet(live)
                    : try await incrementalRefreshHDWallet(live)
            } else {
                updated = try await syncSingleAddress(live)
            }
            updated.lastScanned = Date()
            updated.isSyncing = false
            WalletManager.shared.updateWallet(updated)
            updateTotals()
            recomputeFiat()
        } catch {
            // Preserve current WalletManager state — don't overwrite with the pre-refresh snapshot
            let stateAtError = WalletManager.shared.wallets.first(where: { $0.id == live.id }) ?? live
            var failed = stateAtError
            failed.isSyncing = false
            WalletManager.shared.updateWallet(failed)
            updateTotals()
            recomputeFiat()
            if !isCancellation(error) { errorMessage = friendlyErrorMessage(error) }
        }
    }

    // MARK: - Background Sync

    private func backgroundSync(walletID: UUID) async {
        guard let wallet = WalletManager.shared.wallets.first(where: { $0.id == walletID }) else { return }

        do {
            var updated: Wallet
            if wallet.type.isHDWallet {
                // Resume from the last saved address if the scan was interrupted;
                // only do a full scan if nothing was saved yet.
                updated = wallet.addresses.isEmpty
                    ? try await scanHDWallet(wallet)
                    : try await resumeHDWalletScan(wallet)
            } else {
                // syncSingleAddress handles both fresh starts and mid-fetch resumes:
                // it seeds mergedTxs from whatever is already persisted, then
                // continues pagination from the oldest confirmed txid on hand.
                updated = try await syncSingleAddress(wallet)
            }
            updated.lastScanned = Date()
            updated.isSyncing = false
            WalletManager.shared.updateWallet(updated)
            updateTotals()
            recomputeFiat()
        } catch {
            // Use current WalletManager state to preserve any partial progress from progressive saves
            let current = WalletManager.shared.wallets.first(where: { $0.id == walletID }) ?? wallet
            var failed = current
            failed.isSyncing = false
            WalletManager.shared.updateWallet(failed)
            updateTotals()
            recomputeFiat()
            if !isCancellation(error) { errorMessage = friendlyErrorMessage(error) }
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError
            || (error as? URLError)?.code == .cancelled
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "Connection timed out. Pull to refresh to try again."
            case .notConnectedToInternet, .networkConnectionLost:
                return "No internet connection."
            default:
                return "Network error. Pull to refresh to try again."
            }
        }
        if let apiError = error as? WalletAPIError {
            switch apiError {
            case .httpError(429, _):
                return "Rate limited by server. Wait a moment and try again."
            case .httpError(let code, _):
                return "Server error \(code). Try again later."
            default:
                return apiError.localizedDescription ?? error.localizedDescription
            }
        }
        // NSError from WalletScan domain — strip "[address] " prefix for cleaner display
        let msg = error.localizedDescription
        if msg.hasPrefix("["), let range = msg.range(of: "] ") {
            return String(msg[range.upperBound...])
        }
        return msg
    }

    // MARK: - Batched Gap-Limit Chain Scan

    /// Scans one chain (0 = external, 1 = change) for used addresses starting at
    /// `startIndex`, using bounded-parallel batches instead of one-at-a-time.
    ///
    /// Each batch probes exactly the number of addresses still needed to close the
    /// gap (`gapLimit - consecutiveEmpty`) in parallel, then processes the results
    /// **in index order** — so the gap logic and the stored state are identical to
    /// the old serial scan, just far faster. Newly found addresses/txs are appended
    /// to the inout accumulators, and the wallet is progressively saved after every
    /// batch that yields a hit (so progress survives an interruption).
    private func scanChain(
        _ wallet: Wallet,
        chain: Int,
        startIndex: Int,
        allAddresses: inout [WalletAddress],
        allTransactions: inout [WalletTransaction]
    ) async throws {
        var consecutiveEmpty = 0
        var index = startIndex

        while consecutiveEmpty < gapLimit {
            // Derive just enough addresses to (potentially) close the remaining gap.
            let batchSize = gapLimit - consecutiveEmpty
            let derived: [(index: Int, address: String)] = try (index..<index + batchSize).map {
                (index: $0, address: try AddressDeriver.deriveAddress(
                    from: wallet.publicKey, chain: chain, index: $0, type: wallet.type))
            }

            // Fetch the whole batch in parallel.
            let infos: [String: AddressAPIResponse]
            do {
                infos = try await WalletAPIService.fetchAddressDataConcurrently(
                    derived.map(\.address), maxConcurrent: maxConcurrentRequests
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let e as URLError {
                throw e  // pass through unwrapped so isCancellation() / friendlyErrorMessage() work
            } catch {
                throw NSError(
                    domain: "WalletScan", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "[chain \(chain)] \(error.localizedDescription)"]
                )
            }

            var foundInBatch = false

            // Process strictly in index order to mirror the serial gap algorithm.
            for item in derived {
                guard let info = infos[item.address] else { continue }
                if info.txCount == 0 {
                    consecutiveEmpty += 1
                    if consecutiveEmpty >= gapLimit { break }   // gap closed — ignore rest of batch
                } else {
                    consecutiveEmpty = 0
                    let txs = try await fetchAllTransactions(for: item.address)
                    allAddresses.append(WalletAddress(
                        id: UUID(), address: item.address,
                        derivationIndex: item.index, chain: chain,
                        balanceSats: info.balanceSats, txCount: info.txCount
                    ))
                    allTransactions.append(contentsOf: txs)
                    foundInBatch = true
                }
            }

            // Progressive save after each batch that found new addresses.
            if foundInBatch {
                var partial = wallet
                partial.addresses = allAddresses
                partial.transactions = deduped(allTransactions)
                partial.isSyncing = true
                WalletManager.shared.updateWallet(partial)
                totalBalanceSats = WalletManager.shared.wallets.reduce(0) { $0 + $1.totalBalanceSats }
            }

            index += batchSize
        }
    }

    // MARK: - Full HD Wallet Gap-Limit Scan

    private func scanHDWallet(_ wallet: Wallet) async throws -> Wallet {
        var allAddresses: [WalletAddress] = []
        var allTransactions: [WalletTransaction] = []

        for chain in 0..<2 {
            try await scanChain(
                wallet, chain: chain, startIndex: 0,
                allAddresses: &allAddresses, allTransactions: &allTransactions
            )
        }

        var updated = wallet
        updated.addresses = allAddresses
        updated.transactions = deduped(allTransactions)
        return updated
    }

    // MARK: - Resume Interrupted HD Wallet Scan

    /// Called when a background scan was interrupted (app closed mid-scan).
    /// Keeps all already-found addresses intact and continues the gap-limit scan
    /// from the index after the last known address per chain.
    private func resumeHDWalletScan(_ wallet: Wallet) async throws -> Wallet {
        var allAddresses = wallet.addresses
        var allTransactions = wallet.transactions

        for chain in 0..<2 {
            let maxKnown = wallet.addresses
                .filter { $0.chain == chain }
                .compactMap { $0.derivationIndex }
                .max() ?? -1

            try await scanChain(
                wallet, chain: chain, startIndex: maxKnown + 1,
                allAddresses: &allAddresses, allTransactions: &allTransactions
            )
        }

        var updated = wallet
        updated.addresses = allAddresses
        updated.transactions = deduped(allTransactions)
        return updated
    }

    // MARK: - Incremental HD Wallet Refresh

    /// Smart refresh: re-checks existing (used) addresses in parallel and scans
    /// beyond the last known index per chain. Does NOT re-derive from index 0.
    private func incrementalRefreshHDWallet(_ wallet: Wallet) async throws -> Wallet {
        var updatedAddresses = wallet.addresses
        var mergedTransactions = wallet.transactions

        // Step 1: Re-check all known addresses in parallel (no per-address delay).
        let infos = try await WalletAPIService.fetchAddressDataConcurrently(
            updatedAddresses.map(\.address), maxConcurrent: maxConcurrentRequests
        )

        var addressesWithNewTxs: [String] = []
        for i in updatedAddresses.indices {
            guard let info = infos[updatedAddresses[i].address] else { continue }
            let oldCount = updatedAddresses[i].txCount
            updatedAddresses[i].balanceSats = info.balanceSats
            updatedAddresses[i].txCount = info.txCount
            if info.txCount > oldCount {
                addressesWithNewTxs.append(updatedAddresses[i].address)
            }
        }

        // Fetch & merge transactions only for addresses whose tx count grew.
        for address in addressesWithNewTxs {
            let freshTxs = try await fetchAllTransactions(for: address)
            mergeTxs(&mergedTransactions, from: freshTxs)
        }

        // Step 2: Scan for new addresses beyond the last known index per chain.
        for chain in 0..<2 {
            let maxKnown = wallet.addresses
                .filter { $0.chain == chain }
                .compactMap { $0.derivationIndex }
                .max() ?? -1

            try await scanChain(
                wallet, chain: chain, startIndex: maxKnown + 1,
                allAddresses: &updatedAddresses, allTransactions: &mergedTransactions
            )
        }

        var updated = wallet
        updated.addresses = updatedAddresses
        updated.transactions = deduped(mergedTransactions)
        return updated
    }

    // MARK: - Transaction Helpers

    /// Fetches ALL pages of transactions for `address`, paginating automatically.
    /// Used by HD-wallet scan functions where per-page progressive saves
    /// are not needed (each address has few txs in practice).
    private func fetchAllTransactions(for address: String) async throws -> [WalletTransaction] {
        var all: [WalletTransaction] = []

        // First page: mempool + most recent confirmed, ≤ 50.
        let firstPage = try await WalletAPIService.fetchTransactions(address: address)
        all.append(contentsOf: firstPage)

        // Chain pages: ≤ 25 confirmed txs older than the last cursor, until empty.
        var cursor = firstPage.last(where: { $0.confirmed })?.txid
        while let c = cursor {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let page = try await WalletAPIService.fetchTransactions(address: address, startAfterTxID: c)
            if page.isEmpty { break }
            all.append(contentsOf: page)
            if page.count < 25 { break }
            cursor = page.last(where: { $0.confirmed })?.txid
        }
        return all
    }

    /// Merges `incoming` into `existing`, updating confirmation status for known txids.
    private func mergeTxs(_ existing: inout [WalletTransaction], from incoming: [WalletTransaction]) {
        for tx in incoming {
            if let idx = existing.firstIndex(where: { $0.txid == tx.txid }) {
                existing[idx] = tx
            } else {
                existing.append(tx)
            }
        }
    }

    // MARK: - Single Address Sync

    /// Full sync for a single-address wallet.
    ///
    /// Works for both initial scans (`wallet.transactions` empty) and resuming
    /// interrupted syncs. Saves the balance immediately after the first API
    /// call, then saves progressively after every transaction page — so a
    /// restart can continue exactly where it left off.
    private func syncSingleAddress(_ wallet: Wallet) async throws -> Wallet {
        let address = wallet.publicKey

        // --- Step 1: fetch & immediately persist the current balance ---
        let info = try await WalletAPIService.fetchAddressData(address: address)
        let addrEntry = WalletAddress(
            id: wallet.addresses.first?.id ?? UUID(),
            address: address, derivationIndex: nil, chain: nil,
            balanceSats: info.balanceSats, txCount: info.txCount
        )
        var partial = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        partial.addresses = [addrEntry]
        partial.isSyncing = true
        WalletManager.shared.updateWallet(partial)
        updateTotals()
        recomputeFiat()

        // --- Step 2: start with any previously saved transactions ---
        // On a fresh scan this is empty; on resume it contains partial progress.
        var mergedTxs = partial.transactions

        // --- Step 3: first page (newest txs + mempool) ---
        let firstPage = try await WalletAPIService.fetchTransactions(address: address)
        mergeTxs(&mergedTxs, from: firstPage)

        partial = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        partial.addresses = [addrEntry]
        partial.transactions = mergedTxs
        partial.isSyncing = true
        WalletManager.shared.updateWallet(partial)

        // --- Step 4: chain pages (older confirmed txs) ---
        // Use the oldest confirmed txid we now have as cursor so a resume picks
        // up exactly from the last saved position.
        let confirmedFetched = mergedTxs.filter { $0.confirmed }.count
        var cursor: String? = confirmedFetched < info.txCount
            ? mergedTxs.filter { $0.confirmed }
                       .min(by: { ($0.blockTime ?? Int.max) < ($1.blockTime ?? Int.max) })?.txid
            : nil

        while let c = cursor {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let page = try await WalletAPIService.fetchTransactions(address: address, startAfterTxID: c)
            if page.isEmpty { break }
            mergeTxs(&mergedTxs, from: page)

            // Persist after every page — this is the resume checkpoint.
            partial = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
            partial.addresses = [addrEntry]
            partial.transactions = mergedTxs
            partial.isSyncing = true
            WalletManager.shared.updateWallet(partial)

            let totalConfirmed = mergedTxs.filter { $0.confirmed }.count
            if totalConfirmed >= info.txCount { break }
            if page.count < 25 { break }
            cursor = page.last(where: { $0.confirmed })?.txid
        }

        var updated = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        updated.addresses = [addrEntry]
        updated.transactions = mergedTxs
        return updated
    }

    // MARK: - Helpers

    private func deduped(_ txs: [WalletTransaction]) -> [WalletTransaction] {
        var seen = Set<String>()
        return txs.filter { seen.insert($0.txid).inserted }
    }

    private func updateTotals() {
        // Read directly from WalletManager — self.wallets updates via Combine
        // asynchronously, so it may still be stale at the point of this call.
        totalBalanceSats = WalletManager.shared.wallets.reduce(0) { $0 + $1.totalBalanceSats }
    }

    private func recomputeFiat() {
        let currency = settings.preferredCurrency.uppercased()
        let price = settings.btcPrices[currency] ?? 0
        totalBalanceFiat = (Double(totalBalanceSats) / 100_000_000.0) * price
    }

    func detectWalletType(_ key: String) -> WalletType {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("xpub") { return .xpub }
        if trimmed.hasPrefix("ypub") { return .ypub }
        if trimmed.hasPrefix("zpub") { return .zpub }
        return .singleAddress
    }

    func isValidInput(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isPrivateKey(trimmed) else { return false }
        if trimmed.hasPrefix("xpub") || trimmed.hasPrefix("ypub") || trimmed.hasPrefix("zpub") {
            return trimmed.count > 100
        }
        return (trimmed.hasPrefix("1") || trimmed.hasPrefix("3") || trimmed.hasPrefix("bc1"))
            && trimmed.count >= 26
            && trimmed.count <= 62
    }

    /// Returns true if the input matches any known Bitcoin private key format.
    /// Covers WIF (mainnet/testnet, compressed/uncompressed), BIP32 extended
    /// private keys (xprv/yprv/zprv/tprv), raw 32-byte hex, and BIP39 mnemonics.
    /// Never makes a network call — pure local pattern matching.
    func isPrivateKey(_ key: String) -> Bool {
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }

        // BIP32 extended private keys
        for prefix in ["xprv", "yprv", "zprv", "tprv", "uprv", "vprv"] {
            if t.hasPrefix(prefix) { return true }
        }

        // WIF mainnet uncompressed — '5' + 51 chars
        if t.first == "5" && t.count == 51 { return true }

        // WIF mainnet compressed — 'K' or 'L' + 52 chars
        if (t.first == "K" || t.first == "L") && t.count == 52 { return true }

        // WIF testnet uncompressed — '9' + 51 chars
        if t.first == "9" && t.count == 51 { return true }

        // WIF testnet compressed — 'c' + 52 chars
        if t.first == "c" && t.count == 52 { return true }

        // Raw 32-byte hex private key — exactly 64 hex characters
        if t.count == 64 {
            let isHex = t.unicodeScalars.allSatisfy {
                ($0.value >= 0x30 && $0.value <= 0x39) ||   // 0–9
                ($0.value >= 0x41 && $0.value <= 0x46) ||   // A–F
                ($0.value >= 0x61 && $0.value <= 0x66)      // a–f
            }
            if isHex { return true }
        }

        // BIP39 mnemonic — 12/15/18/21/24 space-separated alphabetic words
        let words = t.lowercased().components(separatedBy: " ").filter { !$0.isEmpty }
        if [12, 15, 18, 21, 24].contains(words.count) &&
           words.allSatisfy({ $0.unicodeScalars.allSatisfy({ $0.value >= 0x61 && $0.value <= 0x7A }) }) {
            return true
        }

        return false
    }

    // MARK: - Color (retained only for stored-wallet compatibility)

    /// Default colour written to new wallets. The colour UI was removed, but the
    /// `colorHex` field stays in the model so existing saved wallets still decode.
    static let neutralColorHex = "#8E8E93"

    // MARK: - Order

    func moveWallet(from source: IndexSet, to destination: Int) {
        WalletManager.shared.moveWallet(from: source, to: destination)
    }

    private func defaultColor() -> String { WalletViewModel.neutralColorHex }
}

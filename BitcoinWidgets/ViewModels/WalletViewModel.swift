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
    /// Task-group window for parallel lookups. The process-wide RequestGate in
    /// WalletAPIService decides how many requests are actually in flight (adaptive,
    /// shared by all syncs), so this only needs to be large enough to keep it fed.
    private let maxConcurrentRequests = 8

    /// Wallet IDs with a sync in flight. Static so it survives the VM being torn down
    /// and rebuilt (wallet lock → unlock): the old VM's task keeps running, and the new
    /// VM must not start a second, competing scan of the same wallet.
    private static var activeSyncs = Set<UUID>()
    /// When each wallet last re-checked ALL of its used addresses (see incremental refresh).
    private static var lastFullSweep: [UUID: Date] = [:]
    /// Automatic refreshes re-check the long tail of emptied addresses at most this often.
    private let fullSweepInterval: TimeInterval = 30 * 60
    private var settings = SettingsManager.shared
    private var cancellables = Set<AnyCancellable>()

    // Serial sync queue — prevents concurrent syncs from triggering rate limits
    private var syncQueue: [UUID] = []
    private var isSyncQueueRunning = false

    // Auto-refresh on new block
    private var lastSeenBlockHeight = 0
    private var isAutoRefreshing = false

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

        // Seed the new-block baseline from the shared tip so a re-created VM (e.g. after
        // a wallet-lock unlock tears down and rebuilds the Wallet tab) doesn't reset to
        // 0 and miss the block edge that arrives right after unlock.
        lastSeenBlockHeight = settings.observedBlockHeight

        // Auto-refresh balances when a new block arrives. The tip height is published
        // by DashboardViewModel's 10 s poll, which only runs while the app is in the
        // foreground — so this naturally never fires in the background.
        settings.$observedBlockHeight
            .receive(on: DispatchQueue.main)
            .sink { [weak self] height in self?.handleObservedBlockHeight(height) }
            .store(in: &cancellables)

        resumePendingSyncs()
    }

    // MARK: - Resume pending syncs on app launch

    /// Wallets that never completed their initial scan (lastScanned == nil) are
    /// restarted automatically when the app opens.
    private func resumePendingSyncs() {
        for wallet in wallets where wallet.lastScanned == nil && !Self.activeSyncs.contains(wallet.id) {
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

    // MARK: - Auto-refresh on new block

    /// Reacts to the shared tip height advancing. Ignores the initial 0→N launch
    /// baseline and only fires on a genuinely new block.
    private func handleObservedBlockHeight(_ height: Int) {
        guard height > 0 else { return }
        let previous = lastSeenBlockHeight
        lastSeenBlockHeight = height
        guard previous > 0, height > previous else { return }   // new block only
        autoRefreshOnNewBlock()
    }

    /// Triggers a lightweight incremental refresh of each idle, already-scanned wallet.
    /// Wallets run in parallel — the shared RequestGate keeps the total request rate
    /// bounded. Wallets still doing their first scan, already syncing, or refreshed in
    /// the last 45 s are skipped (the latter debounces against a just-completed pull).
    private func autoRefreshOnNewBlock() {
        guard !isAutoRefreshing else { return }
        let now = Date()
        let due = WalletManager.shared.wallets.filter { wallet in
            !wallet.isSyncing
                && wallet.lastScanned != nil
                && now.timeIntervalSince(wallet.lastScanned!) > 45
        }
        guard !due.isEmpty else { return }

        isAutoRefreshing = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                for wallet in due {
                    let sweepDue = now.timeIntervalSince(Self.lastFullSweep[wallet.id] ?? .distantPast)
                        > self.fullSweepInterval
                    group.addTask { await self.refreshWallet(wallet, fullSweep: sweepDue) }
                }
            }
            self.isAutoRefreshing = false
        }
    }

    // MARK: - Full Rescan

    /// Forces a complete gap-limit rescan from index 0 — for the rare case where a user
    /// believes funds are missing (or changed the gap limit). Clears derived state and
    /// re-runs the full scan via the serial sync queue. The sync banner then shows the
    /// honest first-scan copy because `addresses` is empty again.
    func rescanWallet(_ wallet: Wallet) {
        let live = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        guard !live.isSyncing, !Self.activeSyncs.contains(live.id) else { return }
        Haptics.trigger(.medium)
        var reset = live
        reset.addresses = []
        reset.transactions = []
        reset.lastScanned = nil
        reset.isSyncing = true
        WalletManager.shared.updateWallet(reset)
        updateTotals()
        enqueueSyncAndRun(walletID: reset.id)
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
        // Wallets refresh in parallel; the shared RequestGate bounds the total rate.
        Task { @MainActor [weak self] in
            guard let self else { return }
            await withTaskGroup(of: Void.self) { group in
                for wallet in self.wallets {
                    group.addTask { await self.refreshWallet(wallet) }
                }
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

    /// `fullSweep: false` (automatic new-block refresh) skips re-checking emptied,
    /// inactive addresses — see incrementalRefreshHDWallet.
    func refreshWallet(_ wallet: Wallet, fullSweep: Bool = true) async {
        errorMessage = nil
        // Read directly from WalletManager to avoid Combine-lag race conditions
        let live = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        guard !live.isSyncing, Self.activeSyncs.insert(live.id).inserted else { return }
        defer { Self.activeSyncs.remove(live.id) }

        var syncing = live
        syncing.isSyncing = true
        WalletManager.shared.updateWallet(syncing)

        do {
            var updated: Wallet
            if live.type.isHDWallet {
                // Incremental if we already have data; full scan if first time
                updated = live.addresses.isEmpty
                    ? try await scanHDWallet(live)
                    : try await incrementalRefreshHDWallet(live, fullSweep: fullSweep)
            } else {
                updated = try await syncSingleAddress(live)
            }
            updated.lastScanned = Date()
            updated.isSyncing = false
            WalletManager.shared.updateWallet(updated)
            updateTotals()
            recomputeFiat()
        } catch {
            // Preserve current WalletManager state (incl. any partial save made during
            // the refresh) — don't overwrite with the pre-refresh snapshot.
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

    /// First scan (or resumed / forced rescan) of a wallet that has never completed one.
    private func backgroundSync(walletID: UUID) async {
        guard let wallet = WalletManager.shared.wallets.first(where: { $0.id == walletID }),
              wallet.lastScanned == nil,                       // finished meanwhile (other VM)
              Self.activeSyncs.insert(walletID).inserted        // already running (other VM)
        else { return }
        defer { Self.activeSyncs.remove(walletID) }

        do {
            var updated: Wallet
            if wallet.type.isHDWallet {
                // Continues after the last saved address per chain if the scan was
                // interrupted; starts at index 0 if nothing was saved yet.
                updated = try await scanHDWallet(wallet)
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
        return error.localizedDescription
    }

    // MARK: - Batched Gap-Limit Chain Scan

    /// Newly found used addresses of one chain plus their full histories.
    private struct ChainScanResult {
        var addresses: [WalletAddress] = []
        var histories: [String: [WalletTransaction]] = [:]
    }

    /// Latest per-chain results of a running first scan, so the two concurrently
    /// scanned chains can save their combined progress.
    private final class ScanProgress {
        let base: Wallet
        var chains: [Int: ChainScanResult] = [:]
        init(base: Wallet) { self.base = base }
    }

    /// Scans one chain (0 = external, 1 = change) for used addresses starting at
    /// `startIndex`, using bounded-parallel batches instead of one-at-a-time.
    ///
    /// Each batch probes exactly the number of addresses still needed to close the
    /// gap (`gapLimit - consecutiveEmpty`) in parallel and evaluates the results
    /// **in index order**, so the gap logic is identical to a serial scan. The
    /// histories of all hits in a batch are then fetched in parallel too (they used
    /// to be fetched one address at a time — the main cost of a first scan).
    /// With `progress`, the wallet is saved after every batch that yields a hit, so
    /// an interrupted scan resumes from there.
    private func scanChain(
        _ wallet: Wallet,
        chain: Int,
        startIndex: Int,
        progress: ScanProgress? = nil
    ) async throws -> ChainScanResult {
        var result = ChainScanResult()
        var consecutiveEmpty = 0
        var index = startIndex

        while consecutiveEmpty < gapLimit {
            // Derive just enough addresses to (potentially) close the remaining gap.
            let batchSize = gapLimit - consecutiveEmpty
            let derived: [(index: Int, address: String)] = try (index..<index + batchSize).map {
                (index: $0, address: try AddressDeriver.deriveAddress(
                    from: wallet.publicKey, chain: chain, index: $0, type: wallet.type))
            }

            let infos = try await WalletAPIService.fetchAddressDataConcurrently(
                derived.map(\.address), maxConcurrent: maxConcurrentRequests
            )

            var hits: [(index: Int, address: String, info: AddressAPIResponse)] = []
            for item in derived {
                guard let info = infos[item.address] else { continue }
                if info.txCount == 0 {
                    consecutiveEmpty += 1
                    if consecutiveEmpty >= gapLimit { break }   // gap closed — ignore rest of batch
                } else {
                    consecutiveEmpty = 0
                    hits.append((item.index, item.address, info))
                }
            }

            if !hits.isEmpty {
                let histories = try await WalletAPIService.fetchHistoriesConcurrently(
                    hits.map { ($0.address, $0.info.confirmedTxCount) },
                    maxConcurrent: maxConcurrentRequests
                )
                for hit in hits {
                    result.addresses.append(WalletAddress(
                        id: UUID(), address: hit.address,
                        derivationIndex: hit.index, chain: chain,
                        balanceSats: hit.info.balanceSats, txCount: hit.info.txCount,
                        mempoolTxCount: hit.info.mempoolTxCount
                    ))
                    result.histories[hit.address] = histories[hit.address] ?? []
                }
                if let progress {
                    progress.chains[chain] = result
                    saveScanProgress(progress)
                }
            }

            index += batchSize
        }
        return result
    }

    private func saveScanProgress(_ progress: ScanProgress) {
        let found = [0, 1].compactMap { progress.chains[$0] }
        var partial = progress.base
        partial.addresses = progress.base.addresses + found.flatMap(\.addresses)
        partial.transactions = applyHistories(
            found.reduce(into: [String: [WalletTransaction]]()) { $0.merge($1.histories) { _, new in new } },
            to: progress.base.transactions)
        partial.isSyncing = true
        WalletManager.shared.updateWallet(partial)
        updateTotals()
    }

    private func nextIndex(_ wallet: Wallet, chain: Int) -> Int {
        (wallet.addresses.filter { $0.chain == chain }.compactMap(\.derivationIndex).max() ?? -1) + 1
    }

    // MARK: - Full HD Wallet Gap-Limit Scan

    /// Gap-limit scan of both chains — run concurrently — starting after the highest
    /// index already saved per chain: index 0 on a fresh scan, so the same path also
    /// resumes a scan that was interrupted (app closed mid-scan).
    private func scanHDWallet(_ wallet: Wallet) async throws -> Wallet {
        let progress = ScanProgress(base: wallet)
        async let external = scanChain(
            wallet, chain: 0, startIndex: nextIndex(wallet, chain: 0), progress: progress)
        async let change = scanChain(
            wallet, chain: 1, startIndex: nextIndex(wallet, chain: 1), progress: progress)
        let found = try await [external, change]

        var updated = wallet
        updated.addresses = wallet.addresses + found.flatMap(\.addresses)
        updated.transactions = applyHistories(
            found.reduce(into: [String: [WalletTransaction]]()) { $0.merge($1.histories) { _, new in new } },
            to: wallet.transactions)
        return updated
    }

    // MARK: - Incremental HD Wallet Refresh

    /// Re-checks known addresses and returns their fresh stats plus the histories of
    /// those that changed. A history is re-fetched when:
    ///  • the effective (confirmed+mempool) count changed, OR
    ///  • there is pending activity now (a fresh unconfirmed tx), OR
    ///  • there WAS pending activity last time — a mempool→confirmed flip leaves the
    ///    effective count identical, so without this clause the tx would stay
    ///    "Unconfirmed" forever (and a dropped / replaced one would never disappear), OR
    ///  • `refetchAll` (one-time rebuild of legacy tx lists).
    private func recheck(
        _ addresses: [WalletAddress],
        knownConfirmedTxids: Set<String>,
        refetchAll: Bool
    ) async throws -> (addresses: [WalletAddress], histories: [String: [WalletTransaction]]) {
        guard !addresses.isEmpty else { return ([], [:]) }
        let infos = try await WalletAPIService.fetchAddressDataConcurrently(
            addresses.map(\.address), maxConcurrent: maxConcurrentRequests
        )

        var updated = addresses
        var toRefetch: [(address: String, expectedConfirmedCount: Int?)] = []
        for i in updated.indices {
            guard let info = infos[updated[i].address] else { continue }
            let oldEffective = updated[i].txCount
            let oldMempool = updated[i].mempoolTxCount ?? 0
            updated[i].balanceSats = info.balanceSats
            updated[i].txCount = info.txCount
            updated[i].mempoolTxCount = info.mempoolTxCount
            if info.txCount != oldEffective || info.mempoolTxCount > 0 || oldMempool > 0
                || (refetchAll && info.txCount > 0) {
                toRefetch.append((updated[i].address, info.confirmedTxCount))
            }
        }

        let histories = try await WalletAPIService.fetchHistoriesConcurrently(
            toRefetch, knownConfirmedTxids: knownConfirmedTxids, maxConcurrent: maxConcurrentRequests
        )
        return (updated, histories)
    }

    /// Smart refresh in two phases:
    ///
    /// 1. "Hot" addresses — funded, pending, or among the newest few per chain (just
    ///    handed out, so the likeliest to be paid) — are re-checked concurrently with
    ///    the gap scan beyond the last known index of both chains. The result is saved
    ///    right away, so the headline balance updates before phase 2 runs.
    /// 2. The long tail of emptied, inactive addresses is re-checked only on a full
    ///    sweep (manual refresh, or at most every 30 min automatically). Funds landing
    ///    on a reused old address are therefore still found, without paying for
    ///    hundreds of empty-address lookups on every new block.
    ///
    /// Histories are fetched incrementally: pagination stops at the first already
    /// known confirmed tx, so a busy address costs one request instead of its whole
    /// history. Tx lists saved before per-address shares existed are rebuilt once
    /// from full histories (which also corrects their net amounts).
    private func incrementalRefreshHDWallet(_ wallet: Wallet, fullSweep: Bool) async throws -> Wallet {
        let rebuild = wallet.transactions.contains { $0.addressDeltas == nil }
        let known: Set<String> = rebuild
            ? []
            : Set(wallet.transactions.lazy.filter(\.confirmed).map(\.txid))

        let newestPerChain: Set<String> = Set([0, 1].flatMap { chain in
            wallet.addresses.filter { $0.chain == chain }
                .sorted { ($0.derivationIndex ?? 0) > ($1.derivationIndex ?? 0) }
                .prefix(5).map(\.address)
        })
        let isHot: (WalletAddress) -> Bool = {
            rebuild || $0.balanceSats != 0 || ($0.mempoolTxCount ?? 0) > 0
                || newestPerChain.contains($0.address)
        }
        let hot = wallet.addresses.filter(isHot)
        let cold = wallet.addresses.filter { !isHot($0) }

        // Phase 1 — hot re-check and both frontier scans, all concurrently.
        async let hotResult = recheck(hot, knownConfirmedTxids: known, refetchAll: rebuild)
        async let external = scanChain(wallet, chain: 0, startIndex: nextIndex(wallet, chain: 0))
        async let change = scanChain(wallet, chain: 1, startIndex: nextIndex(wallet, chain: 1))
        let (rechecked, frontier) = try await (hotResult, [external, change])

        var updated = wallet
        updated.addresses = replacing(wallet.addresses, with: rechecked.addresses)
            + frontier.flatMap(\.addresses)
        var histories = rechecked.histories
        for chain in frontier { histories.merge(chain.histories) { _, new in new } }
        updated.transactions = applyHistories(histories, to: rebuild ? [] : wallet.transactions)

        if rebuild { Self.lastFullSweep[wallet.id] = Date() }
        guard fullSweep, !rebuild, !cold.isEmpty else { return updated }

        // Show phase-1 results now; the cold sweep below only rarely changes anything.
        var partial = updated
        partial.isSyncing = true
        WalletManager.shared.updateWallet(partial)
        updateTotals()
        recomputeFiat()

        // Phase 2 — cold sweep.
        let swept = try await recheck(cold, knownConfirmedTxids: known, refetchAll: false)
        updated.addresses = replacing(updated.addresses, with: swept.addresses)
        updated.transactions = applyHistories(swept.histories, to: updated.transactions)
        Self.lastFullSweep[wallet.id] = Date()
        return updated
    }

    /// `addresses` with each entry replaced by its fresh counterpart from `fresh`.
    private func replacing(_ addresses: [WalletAddress], with fresh: [WalletAddress]) -> [WalletAddress] {
        let byAddress = Dictionary(fresh.map { ($0.address, $0) }, uniquingKeysWith: { _, new in new })
        return addresses.map { byAddress[$0.address] ?? $0 }
    }

    // MARK: - Transaction Merging

    /// Folds freshly fetched per-address histories into a wallet's tx list (by txid,
    /// summing each address's share — see WalletTransaction.merging). For every
    /// address in `histories`, an unconfirmed tx it no longer reports (RBF-replaced
    /// or dropped from the mempool) loses that address's share and disappears once
    /// no share is left; such phantom "pending" txs used to stay forever.
    private func applyHistories(
        _ histories: [String: [WalletTransaction]],
        to transactions: [WalletTransaction]
    ) -> [WalletTransaction] {
        var list = transactions
        for (address, fresh) in histories {
            mergeTxs(&list, from: fresh)
            let freshIDs = Set(fresh.map(\.txid))
            for i in list.indices where !list[i].confirmed && !freshIDs.contains(list[i].txid) {
                guard var deltas = list[i].addressDeltas, deltas[address] != nil else { continue }
                deltas[address] = nil
                list[i].addressDeltas = deltas
                list[i].valueSats = deltas.values.reduce(0, +)
            }
        }
        return list.filter { $0.addressDeltas?.isEmpty != true }
    }

    /// Merges `incoming` into `existing` by txid without pruning anything.
    private func mergeTxs(_ existing: inout [WalletTransaction], from incoming: [WalletTransaction]) {
        var position: [String: Int] = [:]
        for (i, tx) in existing.enumerated() { position[tx.txid] = i }
        for tx in incoming {
            if let i = position[tx.txid] {
                existing[i] = existing[i].merging(tx)
            } else {
                position[tx.txid] = existing.count
                existing.append(tx)
            }
        }
    }

    // MARK: - Single Address Sync

    /// Sync for a single-address wallet. A wallet that completed a sync before takes
    /// the cheap incremental path; otherwise this is a full (or resumed) initial sync.
    private func syncSingleAddress(_ wallet: Wallet) async throws -> Wallet {
        if wallet.lastScanned != nil, !wallet.transactions.isEmpty {
            return try await refreshSingleAddress(wallet)
        }
        return try await initialSyncSingleAddress(wallet)
    }

    /// Incremental refresh: only the pages newer than the newest known confirmed tx.
    private func refreshSingleAddress(_ wallet: Wallet) async throws -> Wallet {
        let address = wallet.publicKey
        let info = try await WalletAPIService.fetchAddressData(address: address)

        // Single-address values are already per-address, so legacy entries can be
        // given their share in place (no rebuild needed).
        let stored = wallet.transactions.map { tx -> WalletTransaction in
            var t = tx
            if t.addressDeltas == nil { t.addressDeltas = [address: t.valueSats] }
            return t
        }
        let known = Set(stored.lazy.filter(\.confirmed).map(\.txid))
        let fresh = try await WalletAPIService.fetchFullHistory(
            address: address, expectedConfirmedCount: info.confirmedTxCount, knownConfirmedTxids: known)
        var merged = applyHistories([address: fresh], to: stored)

        // Self-heal: if the stored history has a hole (e.g. an older sync stopped
        // short), fetch it in full once instead of staying incomplete forever.
        if merged.lazy.filter(\.confirmed).count < info.confirmedTxCount {
            let full = try await WalletAPIService.fetchFullHistory(
                address: address, expectedConfirmedCount: info.confirmedTxCount)
            merged = applyHistories([address: full], to: merged)
        }

        var updated = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        updated.addresses = [WalletAddress(
            id: wallet.addresses.first?.id ?? UUID(),
            address: address, derivationIndex: nil, chain: nil,
            balanceSats: info.balanceSats, txCount: info.txCount,
            mempoolTxCount: info.mempoolTxCount
        )]
        updated.transactions = merged
        return updated
    }

    /// Full sync for a single-address wallet.
    ///
    /// Works for both initial scans (`wallet.transactions` empty) and resuming
    /// interrupted syncs. Saves the balance immediately after the first API
    /// call, then saves progressively after every transaction page — so a
    /// restart can continue exactly where it left off.
    private func initialSyncSingleAddress(_ wallet: Wallet) async throws -> Wallet {
        let address = wallet.publicKey

        // --- Step 1: fetch & immediately persist the current balance ---
        let info = try await WalletAPIService.fetchAddressData(address: address)
        let addrEntry = WalletAddress(
            id: wallet.addresses.first?.id ?? UUID(),
            address: address, derivationIndex: nil, chain: nil,
            balanceSats: info.balanceSats, txCount: info.txCount,
            mempoolTxCount: info.mempoolTxCount
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
        mergedTxs = applyHistories([address: firstPage], to: mergedTxs)

        partial = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        partial.addresses = [addrEntry]
        partial.transactions = mergedTxs
        partial.isSyncing = true
        WalletManager.shared.updateWallet(partial)

        // --- Step 4: chain pages (older confirmed txs) ---
        // Use the oldest confirmed txid we now have as cursor so a resume picks
        // up exactly from the last saved position.
        // Pagination math compares confirmed-against-confirmed; mempool txs from the
        // effective count must not leak in here or it would over-paginate.
        let confirmedFetched = mergedTxs.filter { $0.confirmed }.count
        var cursor: String? = confirmedFetched < info.confirmedTxCount
            ? mergedTxs.filter { $0.confirmed }
                       .min(by: { ($0.blockTime ?? Int.max) < ($1.blockTime ?? Int.max) })?.txid
            : nil

        while let c = cursor {
            let page = try await WalletAPIService.fetchTransactions(address: address, startAfterTxID: c)
            if page.isEmpty { break }
            // Plain merge, no stale-pending pruning: a chain page holds no mempool txs.
            mergeTxs(&mergedTxs, from: page)

            // Persist after every page — this is the resume checkpoint.
            partial = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
            partial.addresses = [addrEntry]
            partial.transactions = mergedTxs
            partial.isSyncing = true
            WalletManager.shared.updateWallet(partial)

            let totalConfirmed = mergedTxs.filter { $0.confirmed }.count
            if totalConfirmed >= info.confirmedTxCount { break }
            if page.count < 25 { break }
            cursor = page.last(where: { $0.confirmed })?.txid
        }

        var updated = WalletManager.shared.wallets.first(where: { $0.id == wallet.id }) ?? wallet
        updated.addresses = [addrEntry]
        updated.transactions = mergedTxs
        return updated
    }

    // MARK: - Helpers

    private func updateTotals() {
        // Read directly from WalletManager — self.wallets updates via Combine
        // asynchronously, so it may still be stale at the point of this call.
        totalBalanceSats = WalletManager.shared.wallets.reduce(0) { $0 + $1.totalBalanceSats }
    }

    private func recomputeFiat() {
        let price = settings.displayPrice(for: settings.preferredCurrency)
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

//
//  ExploreViewModel.swift
//  BitcoinWidgets
//
//  Owns the Explore tab's live block feed and search resolution.
//
//  Request-sparing by design:
//  • The feed is SEEDED with a single REST call (`/api/v1/blocks`) the first
//    time the tab opens, then kept live over ONE websocket connection
//    (`wss://mempool.space/api/v1/ws`, subscribed to `blocks`). New blocks are
//    PUSHED (~every 10 min) — no polling timer.
//  • The socket only runs while the tab is visible and the app is foregrounded
//    (started in onAppear / scenePhase .active, torn down otherwise).
//  • Search and detail lookups are user-initiated, never background work.
//

import SwiftUI
import Combine
import os

@MainActor
final class ExploreViewModel: ObservableObject {

    @Published var blocks: [RecentBlock] = []
    @Published var isSeeding = false
    @Published var isSearching = false
    @Published var searchError: String?
    /// Set when the REST seed failed and we have nothing to show yet, so the feed
    /// can offer a retry instead of a dead "No blocks yet."
    @Published var feedError: String?

    private static let log = Logger(subsystem: "miotares.BitcoinWidgets", category: "ExploreWS")

    private let wsURL = URL(string: "wss://mempool.space/api/v1/ws")!
    private var wsTask: URLSessionWebSocketTask?
    private var liveTask: Task<Void, Never>?
    private var isLiveActive = false
    private let maxBlocks = 20

    // MARK: - Lifecycle

    func onAppear() {
        if blocks.isEmpty {
            Task { await seed() }
        }
        startLive()
    }

    func onDisappear() {
        stopLive()
    }

    /// One-shot REST seed so the feed has content instantly, independent of the
    /// websocket handshake.
    func seed() async {
        isSeeding = true
        defer { isSeeding = false }
        do {
            let fetched = try await ExploreService.fetchRecentBlocks()
            feedError = nil
            ingest(fetched, signalNewTip: false)
        } catch {
            // Only surface the error if we still have nothing to show; a websocket
            // block that already landed makes the failed seed invisible.
            if blocks.isEmpty { feedError = "Couldn't load the latest blocks." }
        }
    }

    // MARK: - Live feed (websocket)

    func startLive() {
        guard liveTask == nil else { return }
        isLiveActive = true
        liveTask = Task { @MainActor [weak self] in
            while let self, self.isLiveActive, !Task.isCancelled {
                await self.runSocketSession()
                // Reconnect with a fixed back-off if the socket dropped while
                // we still want to be live.
                guard self.isLiveActive, !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func stopLive() {
        isLiveActive = false
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        liveTask?.cancel()
        liveTask = nil
    }

    /// Runs a single websocket connection until it closes or we ask it to stop.
    private func runSocketSession() async {
        let task = URLSession.shared.webSocketTask(with: wsURL)
        wsTask = task
        task.resume()
        // Subscribe to block events only.
        task.send(.string(#"{"action":"want","data":["blocks"]}"#)) { _ in }

        receiveLoop: while isLiveActive, !Task.isCancelled {
            switch await Self.receive(task) {
            case .closed:
                break receiveLoop
            case .ignore:
                continue
            case .payload(let data):
                handle(data)
            }
        }

        task.cancel(with: .goingAway, reason: nil)
        if wsTask === task { wsTask = nil }
    }

    private func handle(_ data: Data) {
        let env: WSEnvelope
        do {
            env = try JSONDecoder().decode(WSEnvelope.self, from: data)
        } catch {
            // Don't silently drop a shape change — a stale feed under a green
            // "live" dot is otherwise impossible to diagnose.
            Self.log.error("WS frame decode failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        if let blocks = env.blocks, !blocks.isEmpty {
            ingest(blocks, signalNewTip: false)
        }
        if let block = env.block {
            ingest([block], signalNewTip: true)
        }
    }

    /// Merge new blocks in by height (one entry per height), keep newest-first,
    /// cap the list, and pulse a haptic when a genuinely new tip arrives.
    private func ingest(_ incoming: [RecentBlock], signalNewTip: Bool) {
        let previousTip = blocks.first?.height ?? 0
        var byHeight = Dictionary(blocks.map { ($0.height, $0) }, uniquingKeysWith: { _, new in new })
        for block in incoming { byHeight[block.height] = block }
        blocks = byHeight.values
            .sorted { $0.height > $1.height }
            .prefix(maxBlocks)
            .map { $0 }
        if !blocks.isEmpty { feedError = nil }
        if signalNewTip, let newTip = blocks.first?.height, newTip > previousTip {
            Haptics.trigger()
        }
    }

    // MARK: - Websocket receive (Sendable bridge)

    private enum WSReceive: Sendable {
        case payload(Data)
        case ignore
        case closed
    }

    /// Bridges the completion-handler `receive` into async, returning only a
    /// `Sendable` payload so nothing non-Sendable crosses back to the actor.
    private nonisolated static func receive(_ task: URLSessionWebSocketTask) async -> WSReceive {
        await withCheckedContinuation { continuation in
            task.receive { result in
                switch result {
                case .failure:
                    continuation.resume(returning: .closed)
                case .success(.string(let string)):
                    continuation.resume(returning: string.data(using: .utf8).map(WSReceive.payload) ?? .ignore)
                case .success(.data(let data)):
                    continuation.resume(returning: .payload(data))
                case .success:
                    continuation.resume(returning: .ignore)
                }
            }
        }
    }

    // MARK: - Search

    /// Classifies the query client-side and resolves it to a route, doing the
    /// minimum number of lookups. Sets `searchError` and returns nil on a miss.
    func resolve(_ raw: String) async -> ExploreRoute? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }

        searchError = nil
        isSearching = true
        defer { isSearching = false }

        // Block height — all digits.
        if query.allSatisfy(\.isNumber) {
            guard query.count <= 9, let height = Int(query) else {
                searchError = "That block height is out of range."
                return nil
            }
            do {
                return .block(hash: try await ExploreService.fetchBlockHash(height: height))
            } catch {
                searchError = "No block at height \(query)."
                return nil
            }
        }

        // 64-hex — a transaction id or a block hash. A block hash carries many
        // leading zeros (proof of work); a txid effectively never does — so we
        // route DIRECTLY by that signature, with no probe request. (The old code
        // probed with try?, which silently turned a transient network error into
        // a false "not found" — the exact bug where a valid txid wouldn't open.)
        // The detail screen then distinguishes a real miss from a network hiccup.
        if query.count == 64, query.allSatisfy(\.isHexDigit) {
            let lower = query.lowercased()
            return lower.hasPrefix("00000000") ? .block(hash: lower) : .tx(txid: lower)
        }

        // Address — shape check only (the detail screen surfaces a real miss).
        if Self.looksLikeAddress(query) {
            // bech32 is case-insensitive but mempool.space expects lowercase
            // (a pasted/QR-scanned BC1Q… would otherwise 404). base58 (1.../3...)
            // is genuinely case-sensitive, so leave it untouched.
            let lower = query.lowercased()
            let isBech32 = lower.hasPrefix("bc1") || lower.hasPrefix("tb1") || lower.hasPrefix("bcrt1")
            return .address(isBech32 ? lower : query)
        }

        searchError = "Enter a block height, transaction ID, or address."
        return nil
    }

    private nonisolated static func looksLikeAddress(_ string: String) -> Bool {
        let lower = string.lowercased()
        if lower.hasPrefix("bc1") || lower.hasPrefix("tb1") || lower.hasPrefix("bcrt1") {
            return string.count >= 14
        }
        if string.hasPrefix("1") || string.hasPrefix("3") {
            return (26...35).contains(string.count)
        }
        return false
    }
}

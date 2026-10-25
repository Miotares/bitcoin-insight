//
//  WalletAPIService.swift
//  BitcoinWidgets
//

import Foundation
import os

enum WalletAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int, String)   // status code + body
    case decodingError(String)    // raw response for debugging
    case serverUnreachable        // no backend answers at all (down / blocked network)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        case .httpError(let code, let body):
            return "API error \(code): \(body.prefix(200))"
        case .decodingError(let body):
            return "Unexpected API response: \(body.prefix(200))"
        case .serverUnreachable:
            return "The Bitcoin servers (mempool.space, Blockstream) aren't reachable from this network right now. Try again later or switch networks (e.g. Wi-Fi ↔ mobile data)."
        }
    }
}

struct AddressAPIResponse {
    let address: String
    /// Effective balance = confirmed + mempool (funded − spent). Reflects pending
    /// incoming AND pending outgoing spends, so the headline is never stale.
    let balanceSats: Int
    /// Effective tx count = confirmed + mempool. Used for used/empty gap detection
    /// and change detection so a brand-new mempool-only tx is noticed immediately.
    let txCount: Int
    /// Confirmed-only tx count (chain_stats). Used for chain-pagination math, which
    /// must compare confirmed-against-confirmed.
    let confirmedTxCount: Int
    /// Unconfirmed tx count currently in the mempool for this address.
    let mempoolTxCount: Int
}

struct WalletAPIService {

    // MARK: - Address Stats

    static func fetchAddressData(address: String) async throws -> AddressAPIResponse {

        struct Response: Decodable {
            struct Stats: Decodable {
                let funded_txo_sum: Int
                let spent_txo_sum: Int
                let tx_count: Int
            }
            let chain_stats: Stats
            let mempool_stats: Stats   // always present on /api/address/{address}
        }

        let data = try await fetchWalletEndpoint("/address/\(address)")
        let body = String(data: data, encoding: .utf8) ?? "<binary>"

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw WalletAPIError.decodingError(body)
        }

        let confirmedBalance = decoded.chain_stats.funded_txo_sum - decoded.chain_stats.spent_txo_sum
        let mempoolBalance = decoded.mempool_stats.funded_txo_sum - decoded.mempool_stats.spent_txo_sum
        return AddressAPIResponse(
            address: address,
            balanceSats: confirmedBalance + mempoolBalance,
            txCount: decoded.chain_stats.tx_count + decoded.mempool_stats.tx_count,
            confirmedTxCount: decoded.chain_stats.tx_count,
            mempoolTxCount: decoded.mempool_stats.tx_count
        )
    }

    // MARK: - Transactions

    /// Fetches one page of transactions for `address`.
    ///
    /// - `startAfterTxID: nil`  → first page via `/txs`: mempool + most recent
    ///     confirmed (mempool.space: ≤ 50 in total; Esplora/Blockstream: ≤ 50 mempool
    ///     + 25 confirmed).
    /// - `startAfterTxID: txid` → chain page via `/txs/chain/{txid}`:
    ///     confirmed txs older than `txid`, ≤ 25 entries.
    ///
    /// Callers are responsible for looping until an empty (or short) page
    /// is returned. This lets each caller decide when and what to save
    /// between pages (progressive persistence, cancellation points, etc.).
    static func fetchTransactions(
        address: String,
        startAfterTxID: String? = nil
    ) async throws -> [WalletTransaction] {
        struct TxResponse: Decodable {
            struct Status: Decodable {
                let confirmed: Bool
                let block_time: Int?
            }
            struct Vin: Decodable {
                let prevout: Vout?
            }
            struct Vout: Decodable {
                let scriptpubkey_address: String?
                let value: Int
            }
            let txid: String
            let status: Status
            let fee: Int?
            let vin: [Vin]
            let vout: [Vout]
        }

        let path = startAfterTxID.map { "/address/\(address)/txs/chain/\($0)" }
            ?? "/address/\(address)/txs"
        let data = try await fetchWalletEndpoint(path)
        guard let txList = try? JSONDecoder().decode([TxResponse].self, from: data) else {
            throw WalletAPIError.decodingError(String(data: data, encoding: .utf8) ?? "<binary>")
        }

        return txList.map { tx in
            let received = tx.vout
                .filter { $0.scriptpubkey_address == address }
                .map(\.value).reduce(0, +)
            let spent = tx.vin.compactMap { $0.prevout }
                .filter { $0.scriptpubkey_address == address }
                .map(\.value).reduce(0, +)
            return WalletTransaction(
                txid: tx.txid,
                confirmed: tx.status.confirmed,
                blockTime: tx.status.block_time,
                valueSats: received - spent,
                fee: tx.fee,
                sourceAddress: tx.vin.first?.prevout?.scriptpubkey_address ?? address,
                addressDeltas: [address: received - spent]
            )
        }
    }

    // MARK: - Concurrent Address Stats

    /// Fetches address stats for many addresses with bounded concurrency
    /// (sliding window of at most `maxConcurrent` in-flight requests).
    ///
    /// Each request goes through `fetchAddressData`, which already retries
    /// HTTP 429 with exponential back-off — so a short burst that trips the
    /// rate limit self-heals instead of failing. Results are keyed by address.
    /// `URLError` and `CancellationError` propagate unchanged so callers can
    /// detect cancellation and produce friendly messages.
    static func fetchAddressDataConcurrently(
        _ addresses: [String],
        maxConcurrent: Int = 8
    ) async throws -> [String: AddressAPIResponse] {
        guard !addresses.isEmpty else { return [:] }
        let limit = max(1, maxConcurrent)

        var results: [String: AddressAPIResponse] = [:]
        results.reserveCapacity(addresses.count)

        try await withThrowingTaskGroup(of: AddressAPIResponse.self) { group in
            var iterator = addresses.makeIterator()

            // Prime the window with up to `limit` concurrent tasks.
            for _ in 0..<limit {
                guard let address = iterator.next() else { break }
                group.addTask { try await fetchAddressData(address: address) }
            }

            // As each finishes, record it and enqueue the next address.
            while let response = try await group.next() {
                results[response.address] = response
                if let address = iterator.next() {
                    group.addTask { try await fetchAddressData(address: address) }
                }
            }
        }
        return results
    }

    // MARK: - Full Transaction History

    /// Fetches the transaction history for `address`, paginating internally.
    ///
    /// Stops as early as it safely can:
    /// - the first `/txs` page is short: fewer than 25 confirmed AND fewer than 50 in
    ///   total means the history is exhausted on both backends (mempool.space caps the
    ///   page at 50 in total, Esplora/Blockstream at 25 confirmed — both verified);
    /// - `expectedConfirmedCount` (from address stats) is reached;
    /// - a page contains a confirmed txid from `knownConfirmedTxids`. Pages run newest
    ///   → oldest, so everything older is already stored from a previous sync. This
    ///   turns a refresh of a heavily-reused address from "re-download the whole
    ///   history" into one request. Pass an empty set for addresses never synced.
    /// No artificial inter-page delay; RequestGate is the only throttle (chain pages
    /// are serial anyway, each cursor depending on the previous page).
    static func fetchFullHistory(
        address: String,
        expectedConfirmedCount: Int? = nil,
        knownConfirmedTxids: Set<String> = []
    ) async throws -> [WalletTransaction] {
        var all = try await fetchTransactions(address: address)   // mempool + newest confirmed, ≤ 50

        func reachesKnown(_ page: [WalletTransaction]) -> Bool {
            !knownConfirmedTxids.isEmpty
                && page.contains { $0.confirmed && knownConfirmedTxids.contains($0.txid) }
        }
        func confirmedCount() -> Int { all.lazy.filter { $0.confirmed }.count }

        if reachesKnown(all) || (confirmedCount() < 25 && all.count < 50) { return all }
        if let expected = expectedConfirmedCount, confirmedCount() >= expected { return all }

        var cursor = all.last(where: { $0.confirmed })?.txid
        while let c = cursor {
            let page = try await fetchTransactions(address: address, startAfterTxID: c)
            if page.isEmpty { break }
            all.append(contentsOf: page)
            if page.count < 25 || reachesKnown(page) { break }
            if let expected = expectedConfirmedCount, confirmedCount() >= expected { break }
            cursor = page.last(where: { $0.confirmed })?.txid
        }
        return all
    }

    /// Fetches histories for several addresses with bounded concurrency.
    /// Each address is paginated internally (serial, cursor-dependent); only the
    /// fan-out ACROSS addresses is parallel. Returns address → transactions.
    static func fetchHistoriesConcurrently(
        _ addresses: [(address: String, expectedConfirmedCount: Int?)],
        knownConfirmedTxids: Set<String> = [],
        maxConcurrent: Int = 8
    ) async throws -> [String: [WalletTransaction]] {
        guard !addresses.isEmpty else { return [:] }
        let limit = max(1, maxConcurrent)

        var results: [String: [WalletTransaction]] = [:]
        results.reserveCapacity(addresses.count)

        try await withThrowingTaskGroup(of: (String, [WalletTransaction]).self) { group in
            var iterator = addresses.makeIterator()

            func enqueue(_ item: (address: String, expectedConfirmedCount: Int?)) {
                group.addTask {
                    (item.address, try await fetchFullHistory(
                        address: item.address,
                        expectedConfirmedCount: item.expectedConfirmedCount,
                        knownConfirmedTxids: knownConfirmedTxids))
                }
            }

            for _ in 0..<limit {
                guard let item = iterator.next() else { break }
                enqueue(item)
            }

            while let (addr, txs) = try await group.next() {
                results[addr] = txs
                if let item = iterator.next() { enqueue(item) }
            }
        }
        return results
    }

    // MARK: - Networking

    /// Dedicated session: short per-request timeout so a stalled connection is noticed
    /// quickly instead of hanging a whole sync for URLSession.shared's 60 s default
    /// (a timeout is followed by a reachability probe, so a merely slow server still
    /// gets its retries), and no URL cache (balances must never come from a stale
    /// cached response).
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 90
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 8
        return URLSession(configuration: config)
    }()

    /// Esplora-compatible backends for the wallet endpoints, in order of preference.
    /// mempool.space is primary; Blockstream serves the same `/address` API and is
    /// only used while mempool.space doesn't answer (outage, or a network it blocks).
    static let walletBackends = ["https://mempool.space/api", "https://blockstream.info/api"]

    /// Fetches a wallet endpoint (`/address/...`) from the first backend that answers.
    /// A backend found unreachable is skipped for a few minutes, so a fallback sync
    /// doesn't pay the detection timeout again on every request. If every backend is
    /// marked, they're all tried again (the network may simply have recovered).
    static func fetchWalletEndpoint(_ path: String) async throws -> Data {
        let gate = RequestGate.shared
        var candidates: [String] = []
        for base in walletBackends where !(await gate.isUnreachable(host(of: base))) {
            candidates.append(base)
        }
        let retryingMarked = candidates.isEmpty
        if retryingMarked { candidates = walletBackends }

        for base in candidates {
            guard let url = URL(string: base + path) else { throw WalletAPIError.invalidURL }
            do {
                return try await fetchWithRetry(url: url, ignoreUnreachableMark: retryingMarked).0
            } catch WalletAPIError.serverUnreachable {
                log.error("\(host(of: base), privacy: .public) unreachable — trying next backend")
                continue
            }
        }
        throw WalletAPIError.serverUnreachable
    }

    private static func host(of base: String) -> String { URL(string: base)?.host ?? base }

    /// Fetches `url` through the shared RequestGate, retrying up to `maxRetries` times:
    /// - HTTP 429: pauses ALL wallet/explore requests (Retry-After or exponential
    ///   back-off) and lowers the shared concurrency, then retries
    /// - HTTP 500/502/503/504 and transient URLErrors (timeout, connection lost,
    ///   host unreachable): exponential back-off with jitter — but a connection-level
    ///   failure first probes the server; if it doesn't answer either, every request
    ///   fails fast with `.serverUnreachable` for a short while. Without this, a dead
    ///   or blocked server meant 5 × timeout per request: "loading" for many minutes.
    /// All other errors (incl. cancellation and "offline") propagate immediately.
    ///
    /// Internal (not private) so the Explore feature reuses the exact same
    /// back-off and shares the same request budget.
    static func fetchWithRetry(
        url: URL,
        maxRetries: Int = 4,
        ignoreUnreachableMark: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        let gate = RequestGate.shared
        let host = url.host ?? ""
        var attempt = 0

        while true {
            try Task.checkCancellation()
            if !ignoreUnreachableMark, await gate.isUnreachable(host) {
                throw WalletAPIError.serverUnreachable
            }

            await gate.acquire()
            let outcome: Result<(Data, URLResponse), Error>
            do {
                let wait = await gate.coolDownRemaining
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                outcome = .success(try await session.data(from: url))
            } catch {
                outcome = .failure(error)
            }
            await gate.release()

            switch outcome {
            case .failure(let error):
                guard let urlError = error as? URLError,
                      transientURLErrors.contains(urlError.code) else { throw error }
                if connectionLevelURLErrors.contains(urlError.code), !(await serverResponds(url)) {
                    log.error("\(host, privacy: .public) unreachable (\(urlError.code.rawValue)) — failing fast")
                    await gate.markUnreachable(host, for: 180)
                    throw WalletAPIError.serverUnreachable
                }
                guard attempt < maxRetries else { throw error }
                log.info("Retrying after URLError \(urlError.code.rawValue), attempt \(attempt + 1)")
                try await Task.sleep(for: .seconds(backoff(attempt)))
                attempt += 1
                continue

            case .success(let (data, response)):
                guard let http = response as? HTTPURLResponse else {
                    throw WalletAPIError.networkError(
                        NSError(domain: "WalletAPI", code: 0,
                                userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
                    )
                }

                switch http.statusCode {
                case 200:
                    await gate.recordSuccess()
                    return (data, http)
                case 429 where attempt < maxRetries:
                    log.info("HTTP 429, attempt \(attempt + 1)")
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                    await gate.recordRateLimit(pause: retryAfter ?? backoff(attempt, base: 2))
                    attempt += 1
                    continue   // the next acquire waits out the shared cool-down
                case let code where [500, 502, 503, 504].contains(code) && attempt < maxRetries:
                    try await Task.sleep(for: .seconds(backoff(attempt)))
                    attempt += 1
                    continue
                default:
                    let body = String(data: data, encoding: .utf8) ?? "<binary>"
                    throw WalletAPIError.httpError(http.statusCode, body)
                }
            }
        }
    }

    private static let transientURLErrors: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .badServerResponse
    ]

    /// Failures that can mean "the server doesn't answer at all" (vs. a bad response).
    private static let connectionLevelURLErrors: Set<URLError.Code> = [
        .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed
    ]

    private static let log = Logger(subsystem: "miotares.BitcoinWidgets", category: "WalletSync")

    /// Cheap reachability check after a connection-level failure: tells a slow
    /// response for one heavy address (retry is worthwhile) apart from a server that
    /// is down or blocks this network (retrying only burns minutes).
    private static func serverResponds(_ url: URL) async -> Bool {
        guard let scheme = url.scheme, let host = url.host,
              let probe = URL(string: "\(scheme)://\(host)/api/blocks/tip/height") else { return false }
        var request = URLRequest(url: probe)
        request.timeoutInterval = 6
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// Exponential back-off (base · 2^attempt, capped at 16 s) with ±25 % jitter so
    /// parallel retries don't re-synchronise into another burst.
    private static func backoff(_ attempt: Int, base: Double = 0.75) -> Double {
        let raw = min(16, base * pow(2, Double(attempt)))
        return raw * Double.random(in: 0.75...1.25)
    }
}

// MARK: - Shared request budget

/// Process-wide throttle for wallet/explore backend requests. Every wallet sync and the
/// Explore tab share one budget, so parallel syncs can't multiply the request rate,
/// and a single 429 pauses everyone instead of each task hammering on alone.
/// The in-flight limit adapts: it halves on a 429 and creeps back up after a run
/// of successes, settling near whatever the server currently tolerates.
actor RequestGate {
    static let shared = RequestGate()

    private let minLimit = 2
    private let maxLimit = 8
    private var limit = 6
    private var inFlight = 0
    private var successStreak = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var coolDownUntil = Date.distantPast

    private var unreachableUntil: [String: Date] = [:]

    var coolDownRemaining: TimeInterval { max(0, coolDownUntil.timeIntervalSinceNow) }
    func isUnreachable(_ host: String) -> Bool { (unreachableUntil[host] ?? .distantPast) > Date() }

    func markUnreachable(_ host: String, for seconds: TimeInterval) {
        unreachableUntil[host] = Date().addingTimeInterval(seconds)
    }

    func acquire() async {
        if inFlight < limit {
            inFlight += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if inFlight <= limit, !waiters.isEmpty {
            waiters.removeFirst().resume()   // hand the slot straight to the next waiter
        } else {
            inFlight -= 1
        }
    }

    func recordSuccess() {
        successStreak += 1
        guard successStreak >= 20, limit < maxLimit else { return }
        successStreak = 0
        limit += 1
        while inFlight < limit, !waiters.isEmpty {
            inFlight += 1
            waiters.removeFirst().resume()
        }
    }

    func recordRateLimit(pause: TimeInterval) {
        successStreak = 0
        // Simultaneous 429s from one burst should shrink the limit once, not N times.
        if coolDownRemaining == 0 { limit = max(minLimit, limit / 2) }
        coolDownUntil = max(coolDownUntil, Date().addingTimeInterval(pause))
    }
}

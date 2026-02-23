//
//  WalletAPIService.swift
//  BitcoinWidgets
//

import Foundation

enum WalletAPIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case httpError(Int, String)   // status code + body
    case decodingError(String)    // raw response for debugging

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
        }
    }
}

struct AddressAPIResponse {
    let address: String
    let balanceSats: Int     // funded - spent
    let txCount: Int
}

struct WalletAPIService {

    // MARK: - Address Stats

    static func fetchAddressData(address: String) async throws -> AddressAPIResponse {
        guard let url = URL(string: "https://mempool.space/api/address/\(address)") else {
            throw WalletAPIError.invalidURL
        }

        struct Response: Decodable {
            struct Stats: Decodable {
                let funded_txo_sum: Int
                let spent_txo_sum: Int
                let tx_count: Int
            }
            let chain_stats: Stats
        }

        let (data, _) = try await fetchWithRetry(url: url)
        let body = String(data: data, encoding: .utf8) ?? "<binary>"

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw WalletAPIError.decodingError(body)
        }

        let balance = decoded.chain_stats.funded_txo_sum - decoded.chain_stats.spent_txo_sum
        return AddressAPIResponse(
            address: address,
            balanceSats: balance,
            txCount: decoded.chain_stats.tx_count
        )
    }

    // MARK: - Transactions

    /// Fetches one page of transactions for `address`.
    ///
    /// - `startAfterTxID: nil`  → first page via `/txs`:
    ///     mempool + most recent confirmed, ≤ 50 entries.
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

        let urlString: String
        if let cursor = startAfterTxID {
            urlString = "https://mempool.space/api/address/\(address)/txs/chain/\(cursor)"
        } else {
            urlString = "https://mempool.space/api/address/\(address)/txs"
        }
        guard let url = URL(string: urlString) else { throw WalletAPIError.invalidURL }

        let (data, _) = try await fetchWithRetry(url: url)
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
                sourceAddress: tx.vin.first?.prevout?.scriptpubkey_address ?? address
            )
        }
    }

    // MARK: - Retry helper (handles 429 with exponential back-off)

    /// Fetches `url`, retrying up to `maxRetries` times:
    /// - HTTP 429: exponential back-off (respects Retry-After header)
    /// - URLError.timedOut: 3 s flat delay
    /// All other errors propagate immediately.
    private static func fetchWithRetry(url: URL, maxRetries: Int = 3) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        var delayNs: UInt64 = 2_000_000_000  // start: 2 s (for 429 back-off)

        while true {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw WalletAPIError.networkError(
                        NSError(domain: "WalletAPI", code: 0,
                                userInfo: [NSLocalizedDescriptionKey: "Non-HTTP response"])
                    )
                }

                if http.statusCode == 429 && attempt < maxRetries {
                    // Respect Retry-After header if present, otherwise exponential back-off
                    let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(Double.init).map { UInt64($0 * 1_000_000_000) }
                    try await Task.sleep(nanoseconds: retryAfter ?? delayNs)
                    delayNs *= 2
                    attempt += 1
                    continue
                }

                if http.statusCode != 200 {
                    let body = String(data: data, encoding: .utf8) ?? "<binary>"
                    throw WalletAPIError.httpError(http.statusCode, body)
                }

                return (data, http)
            } catch let e {
                // Retry on timeout; all other errors (including cancellation) propagate immediately
                if let urlError = e as? URLError, urlError.code == .timedOut, attempt < maxRetries {
                    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 s flat delay
                    attempt += 1
                    continue
                }
                throw e
            }
        }
    }
}

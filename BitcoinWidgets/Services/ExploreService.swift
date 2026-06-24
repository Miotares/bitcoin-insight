//
//  ExploreService.swift
//  BitcoinWidgets
//
//  Read-only REST lookups for the Explore tab, all against mempool.space's
//  no-auth API. Reuses WalletAPIService.fetchWithRetry (shared 429 back-off)
//  and the existing BlockData decoder, so no new networking or models are
//  duplicated. Every call here is user-initiated (search / opening a detail),
//  never polled.
//

import Foundation

enum ExploreServiceError: Error {
    case notFound
}

struct ExploreService {

    private static let base = "https://mempool.space"

    /// Recent blocks for the live feed's initial seed (one request on first open).
    /// Returns ~15 enriched blocks, newest first.
    static func fetchRecentBlocks() async throws -> [RecentBlock] {
        guard let url = URL(string: "\(base)/api/v1/blocks") else { throw WalletAPIError.invalidURL }
        let (data, _) = try await WalletAPIService.fetchWithRetry(url: url)
        return try JSONDecoder().decode([RecentBlock].self, from: data)
    }

    /// Resolves a block height to its hash (`GET /api/block-height/{height}`,
    /// plain-text body). Throws `.notFound` if the height is beyond the tip.
    static func fetchBlockHash(height: Int) async throws -> String {
        guard let url = URL(string: "\(base)/api/block-height/\(height)") else { throw WalletAPIError.invalidURL }
        let (data, _) = try await WalletAPIService.fetchWithRetry(url: url)
        guard
            let hash = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            hash.count == 64
        else { throw ExploreServiceError.notFound }
        return hash
    }

    /// Enriched block detail (`GET /api/v1/block/{hash}`) — reuses the existing
    /// `BlockData` decoder used by the Dashboard's block screen.
    static func fetchBlock(hash: String) async throws -> BlockData {
        guard let url = URL(string: "\(base)/api/v1/block/\(hash)") else { throw WalletAPIError.invalidURL }
        let (data, _) = try await WalletAPIService.fetchWithRetry(url: url)
        return try JSONDecoder().decode(BlockData.self, from: data)
    }

    /// Full transaction (`GET /api/tx/{txid}`) including status, fee, in/outputs.
    static func fetchTx(txid: String) async throws -> TxDetail {
        guard let url = URL(string: "\(base)/api/tx/\(txid)") else { throw WalletAPIError.invalidURL }
        let (data, _) = try await WalletAPIService.fetchWithRetry(url: url)
        return try JSONDecoder().decode(TxDetail.self, from: data)
    }

    /// One page (≤25) of full transactions in a block
    /// (`GET /api/block/{hash}/txs[/{startIndex}]`). `startIndex` must be a
    /// multiple of 25; the first page (index 0) includes the coinbase tx. Loaded
    /// on demand so opening a block costs nothing extra.
    static func fetchBlockTxs(hash: String, startIndex: Int = 0) async throws -> [TxDetail] {
        let suffix = startIndex > 0 ? "/\(startIndex)" : ""
        guard let url = URL(string: "\(base)/api/block/\(hash)/txs\(suffix)") else { throw WalletAPIError.invalidURL }
        let (data, _) = try await WalletAPIService.fetchWithRetry(url: url)
        return try JSONDecoder().decode([TxDetail].self, from: data)
    }

    /// True only for a definitive HTTP 404 (the thing genuinely doesn't exist) —
    /// as opposed to a timeout / connectivity / rate-limit error, which should be
    /// surfaced as "try again", not "not found".
    static func isNotFound(_ error: Error) -> Bool {
        if case WalletAPIError.httpError(404, _) = error { return true }
        if case ExploreServiceError.notFound = error { return true }
        return false
    }
}

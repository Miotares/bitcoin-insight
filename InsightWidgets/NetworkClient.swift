//
//  NetworkClient.swift
//  InsightWidgets
//
//  Reads the single cached stats row from the Supabase backend.
//  ONLY the widgets use this; the main app talks to mempool.space directly.
//

import Foundation

enum NetworkClient {
    private static let endpoint = URL(string:
        "https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/network_stats?select=payload&id=eq.1")!
    private static let sparklineEndpoint = URL(string:
        "https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/rpc/network_stats_sparklines")!
    private static let apiKey = "sb_publishable_FEEoI6sfC_EZ1oLP2E0IJQ_Yftfzrk9"

    private struct Row: Decodable {
        let payload: Payload
        struct Payload: Decodable {
            // Optional values so a single null currency (e.g. a partial mempool
            // response upstream) can't make the whole payload fail to decode and
            // freeze every widget stat — the null key is dropped, the rest stay live.
            let prices: [String: Double?]
            let blockHeight: Int
            let fees: Fees
            let mempoolCount: Int?
            let hashrate: Double?
            let difficulty: Double?
            let difficultyAdjustment: Adjustment?
            let lightning: Lightning?

            struct Fees: Decodable { let fast: Int; let halfHour: Int; let hour: Int }
            struct Adjustment: Decodable {
                let progressPercent: Double?
                let remainingBlocks: Int?
                let estimatedRetargetPercentage: Double?
            }
            struct Lightning: Decodable {
                let channels: Int?
                let nodes: Int?
                let capacity: Int?
            }
        }
    }

    static func fetchSnapshot() async throws -> NetworkSnapshot {
        var request = URLRequest(url: endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let p = try JSONDecoder().decode([Row].self, from: data).first?.payload else {
            throw URLError(.cannotParseResponse)
        }

        var snapshot = NetworkSnapshot(
            prices: p.prices.compactMapValues { $0 },
            blockHeight: p.blockHeight,
            feeFast: p.fees.fast,
            feeHalfHour: p.fees.halfHour,
            feeHour: p.fees.hour,
            mempoolCount: p.mempoolCount ?? 0,
            hashrate: p.hashrate ?? 0,
            difficulty: p.difficulty ?? 0,
            adjustmentProgress: p.difficultyAdjustment?.progressPercent ?? 0,
            adjustmentRemainingBlocks: p.difficultyAdjustment?.remainingBlocks ?? 0,
            adjustmentRetargetPercent: p.difficultyAdjustment?.estimatedRetargetPercentage ?? 0,
            lnChannels: p.lightning?.channels ?? 0,
            lnNodes: p.lightning?.nodes ?? 0,
            lnCapacitySats: p.lightning?.capacity ?? 0,
            updatedAt: Date()
        )

        // Best-effort sparkline series — a failure just leaves the lines hidden,
        // never blocks the headline stats.
        if let spark = await fetchSparklines() {
            snapshot.mempoolSeries = spark.mempool.count >= 2 ? spark.mempool : nil
            snapshot.hashrateSeries = spark.hashrate.count >= 2 ? spark.hashrate : nil
            // RPC price is a FALLBACK only — it comes from network_stats_history, which
            // is still filling, so it can be sparse for the first 24h after deploy.
            snapshot.priceUsdSeries = spark.priceUsd.count >= 2 ? spark.priceUsd : nil
        }

        // Price line: use the SAME dense 24h source as the in-app Dashboard sparkline
        // (CoinGecko market_chart days=1, ~5-min granularity) so it is full-resolution
        // immediately instead of waiting for network_stats_history to accumulate.
        // Overrides the sparse RPC price above; falls back to it if CoinGecko fails.
        if let dense = await fetch24hPriceSeriesUSD() {
            snapshot.priceUsdSeries = dense
        }

        return snapshot
    }

    // MARK: - Sparkline series

    private struct Sparklines: Decodable {
        let mempool: [Double]
        let priceUsd: [Double]
        let hashrate: [Double]
    }

    /// Fetches the downsampled trend arrays from the `network_stats_sparklines` RPC.
    /// Returns nil on any failure (the widget then just omits the lines).
    private static func fetchSparklines() async -> Sparklines? {
        var request = URLRequest(url: sparklineEndpoint)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(Sparklines.self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Dense 24h price series (matches the Dashboard sparkline)

    /// Fetches the trailing-24h USD price at ~5-min granularity from CoinGecko — the
    /// same source the in-app Dashboard sparkline uses — and downsamples it to keep
    /// the widget entry small. Returns nil on any failure.
    private static func fetch24hPriceSeriesUSD() async -> [Double]? {
        guard let url = URL(string:
            "https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=usd&days=1") else { return nil }
        struct Response: Decodable { let prices: [[Double]] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let values = decoded.prices.compactMap { $0.count == 2 && $0[1] > 0 ? $0[1] : nil }
            guard values.count >= 2 else { return nil }
            return downsample(values, to: 48)
        } catch {
            return nil
        }
    }

    /// Evenly-spaced downsample to at most `target` points, always keeping the first
    /// and last sample so the line's endpoints (and thus its up/down color) stay true.
    private static func downsample(_ values: [Double], to target: Int) -> [Double] {
        guard values.count > target, target > 1 else { return values }
        let step = Double(values.count - 1) / Double(target - 1)
        return (0..<target).map { values[Int((Double($0) * step).rounded())] }
    }
}

//
//  NetworkSnapshot.swift
//  InsightWidgets
//
//  The bundle of global Bitcoin stats the widgets display.
//  Fetched from the backend, cached in the App Group.
//

import Foundation

struct NetworkSnapshot: Codable {
    var prices: [String: Double]
    var blockHeight: Int
    var feeFast: Int
    var feeHalfHour: Int
    var feeHour: Int
    var mempoolCount: Int
    var hashrate: Double            // H/s
    var difficulty: Double
    var adjustmentProgress: Double          // % through the current epoch
    var adjustmentRemainingBlocks: Int
    var adjustmentRetargetPercent: Double   // estimated difficulty change %
    var lnChannels: Int
    var lnNodes: Int
    var lnCapacitySats: Int
    var updatedAt: Date

    // Tiny trend series for the home-widget sparklines (baked into the entry — a
    // widget can't fetch on render). Optional so a pre-sparkline cache still decodes
    // and a missing/short series just hides the line. Oldest -> newest.
    var mempoolSeries: [Double]? = nil       // unconfirmed tx count, last 24h
    var priceUsdSeries: [Double]? = nil      // USD price, last 24h
    var hashrateSeries: [Double]? = nil      // network hashrate, last 30d

    /// Price in the given currency, falling back to USD.
    func price(for currency: String) -> Double {
        prices[currency.uppercased()] ?? prices["USD"] ?? 0
    }

    /// Moscow Time (sats per fiat) trend, derived from the USD price series. The
    /// curve is axis-less, so the USD-derived shape is correct for every currency
    /// (intraday FX is ~flat). nil when there's no usable price series.
    var moscowSeries: [Double]? {
        guard let p = priceUsdSeries, p.count >= 2 else { return nil }
        return p.map { $0 > 0 ? 100_000_000 / $0 : 0 }
    }

    static let preview = NetworkSnapshot(
        prices: ["USD": 63922, "EUR": 55260, "GBP": 47695],
        blockHeight: 953_510,
        feeFast: 4, feeHalfHour: 3, feeHour: 1,
        mempoolCount: 111_767,
        hashrate: 8.897e20,
        difficulty: 1.389e14,
        adjustmentProgress: 97.1, adjustmentRemainingBlocks: 58, adjustmentRetargetPercent: 1.2,
        lnChannels: 41_337, lnNodes: 17_363, lnCapacitySats: 549_744_023_772,
        updatedAt: Date(),
        mempoolSeries: [82_000, 95_000, 120_000, 138_000, 117_000, 104_000, 111_767],
        priceUsdSeries: [
            61_900, 62_050, 61_700, 61_500, 61_800, 62_300, 62_600, 62_400, 62_900, 63_400,
            63_100, 62_800, 63_000, 63_600, 64_050, 63_800, 63_300, 63_500, 63_900, 64_100,
            63_700, 63_200, 62_900, 63_100, 63_500, 63_800, 64_000, 63_600, 63_750, 63_922
        ],
        hashrateSeries: [7.9e20, 8.1e20, 8.0e20, 8.4e20, 8.6e20, 8.7e20, 8.897e20]
    )
}

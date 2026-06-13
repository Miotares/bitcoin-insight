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

    /// Price in the given currency, falling back to USD.
    func price(for currency: String) -> Double {
        prices[currency.uppercased()] ?? prices["USD"] ?? 0
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
        updatedAt: Date()
    )
}

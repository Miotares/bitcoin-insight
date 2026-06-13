//
//  NetworkSnapshot.swift
//  InsightWidgets
//
//  The small bundle of global Bitcoin stats the widgets display.
//  Fetched from the backend, cached in the App Group.
//

import Foundation

struct NetworkSnapshot: Codable {
    var prices: [String: Double]   // currency code → price
    var blockHeight: Int
    var feeFast: Int
    var feeHalfHour: Int
    var feeHour: Int
    var updatedAt: Date            // when the widget last fetched this

    /// Price in the given currency, falling back to USD.
    func price(for currency: String) -> Double {
        prices[currency.uppercased()] ?? prices["USD"] ?? 0
    }

    /// Placeholder for the widget gallery / previews.
    static let preview = NetworkSnapshot(
        prices: ["USD": 63873, "EUR": 55249, "GBP": 47661],
        blockHeight: 953_507,
        feeFast: 8, feeHalfHour: 5, feeHour: 3,
        updatedAt: Date()
    )
}

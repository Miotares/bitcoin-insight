//
//  DummyDataService.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//


import Foundation

class DummyDataService {
    static func getSampleData() -> BitcoinStats {
        BitcoinStats(
            priceUSD: 61000.32,
            priceEUR: 57500.11,
            blockHeight: 863421,
            lastBlockTime: Date().addingTimeInterval(-600),
            mempoolTransactions: 4312,
            difficulty: 89_334_112_332_221
        )
    }
}
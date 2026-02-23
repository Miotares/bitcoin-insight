//
//  BitcoinStats.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//


import Foundation

struct BitcoinStats: Identifiable {
    let id = UUID()
    let priceUSD: Double
    let priceEUR: Double
    let blockHeight: Int
    let lastBlockTime: Date
    let mempoolTransactions: Int
    let difficulty: Double
}

struct FeeData {
    let low: Int
    let medium: Int
    let high: Int
}

struct DifficultyAdjustment {
    let progressPercent: Double
    let estimatedRetargetPercentage: Double
    let remainingBlocks: Int
}

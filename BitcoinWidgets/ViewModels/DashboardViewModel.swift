//
//  DashboardViewModel.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//
//

import Foundation
import SwiftUI
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var blockHeight: Int = 0
    @Published var mempoolTransactions: Int = 0
    @Published var difficulty: Double = 0.0
    @Published var lastBlockTime: Date = Date()
    @Published var fees: FeeData = FeeData(low: 0, medium: 0, high: 0)
    @Published var feePercentiles: [Double] = []
    @Published var moscowTime: Int = 0
    @Published var circulatingSupply: Double = 0.0
    @Published var circulatingSupplyPercent: Double = 0.0
    @Published var difficultyAdjustment: DifficultyAdjustment = DifficultyAdjustment(progressPercent: 0, estimatedRetargetPercentage: 0, remainingBlocks: 0)
    @Published var livePrice: Double = 0.0
    @Published var priceChangeColor: Color = .primary
    @Published var hashrate: Double = 0.0
    @Published var halvingProgress: Double = 0.0
    @Published var blocksRemainingToHalving: Int = 0
    @Published var lightningChannelCount: Int = 0
    @Published var lightningNodeCount: Int = 0
    @Published var lightningCapacity: Double = 0.0
    
    // MARK: - Private Properties
    private var settings = SettingsManager.shared
    
    // MARK: - Initialization
    init() {
        Task {
            await loadData()
        }
        startTimer()
    }
    
    private func startTimer() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                guard let self = self else { return }
                await self.refreshData()
            }
        }
    }
    
    // MARK: - Public Methods
    func refreshData() async {
        Haptics.trigger(.light)
        await loadData()
    }
    
    func loadData() async {
        await fetchLivePrice()
        await fetchMempoolStats() // Fetches block height
        calculateCirculatingSupply() // Calculate supply based on block height
        await fetchFees()
        await fetchFeePercentiles()
        await fetchDifficultyAdjustment()
        await fetchMiningStats() // Consolidated difficulty and hashrate
        await fetchLightningStats()
        updateHalvingProgress()
    }
    
    // MARK: - Data Fetching Logic
    
    private func fetchLivePrice() async {
        do {
            try await fetchPriceFromMempool()
        } catch {
            await fetchPriceFromCoinGecko()
        }
    }
    
    private func fetchPriceFromMempool() async throws {
        guard let url = URL(string: "https://mempool.space/api/v1/prices") else { return }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        let currencyKey = settings.preferredCurrency.uppercased()
        var parsedPrice: Double? = nil
        var usdPrice: Double? = nil
        
        // Try typed struct first
        struct MempoolPriceResponse: Codable {
            let USD: Double?
            let EUR: Double?
            let GBP: Double?
            let CAD: Double?
            let CHF: Double?
            let AUD: Double?
            let JPY: Double?
        }
        
        if let typed = try? JSONDecoder().decode(MempoolPriceResponse.self, from: data) {
            usdPrice = typed.USD
            switch currencyKey {
            case "USD": parsedPrice = typed.USD
            case "EUR": parsedPrice = typed.EUR
            case "GBP": parsedPrice = typed.GBP
            case "CAD": parsedPrice = typed.CAD
            case "CHF": parsedPrice = typed.CHF
            case "AUD": parsedPrice = typed.AUD
            case "JPY": parsedPrice = typed.JPY
            default: parsedPrice = typed.USD
            }

            // Write all prices to the shared store so the Wallet tab can use them live
            var allPrices = [String: Double]()
            if let v = typed.USD { allPrices["USD"] = v }
            if let v = typed.EUR { allPrices["EUR"] = v }
            if let v = typed.GBP { allPrices["GBP"] = v }
            if let v = typed.CAD { allPrices["CAD"] = v }
            if let v = typed.CHF { allPrices["CHF"] = v }
            if let v = typed.AUD { allPrices["AUD"] = v }
            if let v = typed.JPY { allPrices["JPY"] = v }
            if !allPrices.isEmpty { SettingsManager.shared.btcPrices = allPrices }
        }

        // Fallback parsing
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if parsedPrice == nil, let d = json[currencyKey] as? Double { parsedPrice = d }
            if usdPrice == nil, let d = json["USD"] as? Double { usdPrice = d }
        }

        guard let price = parsedPrice else { throw URLError(.badServerResponse) }
        await updatePriceUI(price, usdPrice: usdPrice)
    }
    
    private func fetchPriceFromCoinGecko() async {
        let currency = settings.preferredCurrency.lowercased()
        // Always fetch USD as well for Moscow Time
        let urlString = "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=\(currency),usd"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let decoded = try? JSONDecoder().decode([String: [String: Double]].self, from: data),
               let btcData = decoded["bitcoin"] {
                let price = btcData[currency]
                let usdPrice = btcData["usd"]
                
                if let price = price {
                    await updatePriceUI(price, usdPrice: usdPrice)
                }
            }
        } catch { }
    }
    
    private func updatePriceUI(_ price: Double, usdPrice: Double? = nil) {
        // User requested multiplier for more precision/variation
        let adjustedPrice = price * 1.00025
        
        let oldPrice = self.livePrice
        if adjustedPrice > oldPrice {
            self.priceChangeColor = .green
        } else if adjustedPrice < oldPrice {
            self.priceChangeColor = .red
        } else {
            self.priceChangeColor = .primary
        }
        
        withAnimation(.easeOut(duration: 0.3)) {
            self.livePrice = adjustedPrice
            // Calculate Moscow Time (sats per USD)
            // Use explicit USD price if available, otherwise fallback to adjustedPrice ONLY if currency is USD
            if let usd = usdPrice, usd > 0 {
                self.moscowTime = Int(100_000_000 / usd)
            } else if settings.preferredCurrency.uppercased() == "USD", adjustedPrice > 0 {
                self.moscowTime = Int(100_000_000 / adjustedPrice)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation(.easeIn(duration: 0.4)) {
                self.priceChangeColor = .primary
            }
        }
    }
    
    private func fetchMempoolStats() async {
        // Block Height
        if let heightURL = URL(string: "https://mempool.space/api/blocks/tip/height") {
            if let (data, _) = try? await URLSession.shared.data(from: heightURL),
               let str = String(data: data, encoding: .utf8),
               let height = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.blockHeight = height
            }
        }
        
        // Last Block Time
        if let blocksURL = URL(string: "https://mempool.space/api/blocks") {
            struct Block: Decodable { let timestamp: Int }
            if let (data, _) = try? await URLSession.shared.data(from: blocksURL),
               let blocks = try? JSONDecoder().decode([Block].self, from: data),
               let latest = blocks.first {
                self.lastBlockTime = Date(timeIntervalSince1970: TimeInterval(latest.timestamp))
            }
        }
        
        // Mempool Count
        if let mempoolURL = URL(string: "https://mempool.space/api/mempool") {
            struct Mempool: Decodable { let count: Int }
            if let (data, _) = try? await URLSession.shared.data(from: mempoolURL),
               let decoded = try? JSONDecoder().decode(Mempool.self, from: data) {
                self.mempoolTransactions = decoded.count
            }
        }
    }
    
    private func calculateCirculatingSupply() {
        let currentHeight = self.blockHeight
        if currentHeight == 0 { return }
        
        let halvingInterval = 210_000
        var subsidy = 50.0
        var supply = 0.0
        var height = currentHeight
        var era = 0
        
        // Calculate fully completed eras
        while height >= halvingInterval {
            supply += Double(halvingInterval) * subsidy
            height -= halvingInterval
            subsidy /= 2.0
            era += 1
        }
        
        // Add remaining blocks in current era
        supply += Double(height) * subsidy
        
        self.circulatingSupply = supply
        self.circulatingSupplyPercent = (supply / 21_000_000.0) * 100.0
    }
    
    private func fetchFees() async {
        guard let url = URL(string: "https://mempool.space/api/v1/fees/recommended") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url) {
            struct FeeResp: Decodable {
                let fastestFee: Int
                let halfHourFee: Int
                let hourFee: Int
            }
            if let decoded = try? JSONDecoder().decode(FeeResp.self, from: data) {
                self.fees = FeeData(low: decoded.hourFee, medium: decoded.halfHourFee, high: decoded.fastestFee)
            }
        }
    }
    
    private func fetchFeePercentiles() async {
        guard let url = URL(string: "https://mempool.space/api/v1/fees/mempool-blocks") else { return }
        
        struct MempoolBlock: Decodable {
            let feeRange: [Double]
        }
        
        if let (data, _) = try? await URLSession.shared.data(from: url),
           let blocks = try? JSONDecoder().decode([MempoolBlock].self, from: data),
           let firstBlock = blocks.first,
           firstBlock.feeRange.count >= 7 {
            
            // Indices: 0=min, 1=10th, 2=25th, 3=50th, 4=75th, 5=90th, 6=max
            let indices = [1, 2, 3, 4, 5]
            let values = indices.map { firstBlock.feeRange[$0] }
            self.feePercentiles = values
        }
    }
    
    private func fetchDifficultyAdjustment() async {
        guard let url = URL(string: "https://mempool.space/api/v1/difficulty-adjustment") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url) {
            struct DiffResp: Decodable {
                let progressPercent: Double
                let estimatedRetargetPercentage: Double?
                let remainingBlocks: Int
            }
            if let decoded = try? JSONDecoder().decode(DiffResp.self, from: data) {
                self.difficultyAdjustment = DifficultyAdjustment(
                    progressPercent: decoded.progressPercent,
                    estimatedRetargetPercentage: decoded.estimatedRetargetPercentage ?? 0,
                    remainingBlocks: decoded.remainingBlocks
                )
            }
        }
    }
    
    private func fetchMiningStats() async {
        guard let url = URL(string: "https://mempool.space/api/v1/mining/hashrate/3d") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url) {
            struct MiningResponse: Decodable {
                let currentDifficulty: Double
                let currentHashrate: Double
            }
            if let decoded = try? JSONDecoder().decode(MiningResponse.self, from: data) {
                self.difficulty = decoded.currentDifficulty
                self.hashrate = decoded.currentHashrate
            }
        }
    }
    
    private func fetchLightningStats() async {
        guard let url = URL(string: "https://mempool.space/api/v1/lightning/statistics/latest") else { return }
        if let (data, _) = try? await URLSession.shared.data(from: url) {
            // The API returns { "latest": { ... } }
            struct LNResponse: Decodable {
                let latest: LNStats
            }
            struct LNStats: Decodable {
                let channel_count: Int
                let node_count: Int
                let total_capacity: Int // in sats
            }
            
            if let decoded = try? JSONDecoder().decode(LNResponse.self, from: data) {
                self.lightningChannelCount = decoded.latest.channel_count
                self.lightningNodeCount = decoded.latest.node_count
                self.lightningCapacity = Double(decoded.latest.total_capacity)
            }
        }
    }
    
    private func updateHalvingProgress() {
        let halvingInterval = 210_000
        let currentBlock = blockHeight
        if currentBlock == 0 { return }
        let nextHalvingHeight = ((currentBlock / halvingInterval) + 1) * halvingInterval
        let blocksRemaining = nextHalvingHeight - currentBlock
        let progress = Double(halvingInterval - blocksRemaining) / Double(halvingInterval)
        
        self.blocksRemainingToHalving = blocksRemaining
        self.halvingProgress = progress
    }
}

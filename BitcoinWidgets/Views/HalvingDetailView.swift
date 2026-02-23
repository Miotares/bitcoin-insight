//
//  HalvingDetailView.swift
//  BitcoinWidgets
//
//  Reworked to display halving details based on current block height
//

import SwiftUI
import Combine

struct HalvingDetailView: View {
    @State private var blockHeight: Int?
    
    private var halvingInterval: Int { 210_000 }
    
    private var nextHalvingHeight: Int {
        guard let height = blockHeight else { return 0 }
        return ((height / halvingInterval) + 1) * halvingInterval
    }
    
    private var blocksRemaining: Int {
        guard let height = blockHeight else { return 0 }
        return max(0, nextHalvingHeight - height)
    }
    
    private var currentReward: Double {
        guard let height = blockHeight else { return 0 }
        return 50.0 / pow(2.0, Double(height / halvingInterval))
    }
    
    private var nextReward: Double { currentReward / 2 }
    
    private var estimatedDate: Date {
        Date().addingTimeInterval(Double(blocksRemaining * 10 * 60))
    }
    
    private var estimatedDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: estimatedDate)
    }
    
    private var daysRemaining: Int {
        let diff = estimatedDate.timeIntervalSinceNow
        return max(0, Int(diff / 86400))
    }
    
    private var currentInflationRate: Double {
        guard let height = blockHeight else { return 0 }
        // Calculate Circulating Supply
        var supply = 0.0
        var subsidy = 50.0
        var h = height
        let interval = 210_000
        
        // Full eras
        var tempHeight = height
        var currentSubsidy = 50.0
        
        // 1. Calculate supply from full previous eras
        let eras = height / interval
        for _ in 0..<eras {
            supply += Double(interval) * currentSubsidy
            currentSubsidy /= 2
        }
        
        // 2. Calculate supply from current era
        let blocksInCurrentEra = height % interval
        supply += Double(blocksInCurrentEra) * currentSubsidy
        
        let annualIssuance = (currentReward * 144) * 365
        return (annualIssuance / supply) * 100
    }
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(accentColor: .orange)
            
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Hero Section
                    VStack(spacing: 8) {
                        Text("BLOCKS REMAINING")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(2)
                        
                        Text(Formatters.formatAmount(blocksRemaining))
                            .font(.system(size: 52, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: blocksRemaining)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)
                    
                    // MARK: - Technical Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        DetailStatCard(
                            title: "Estimated Date",
                            value: estimatedDateString
                        )
                        
                        DetailStatCard(
                            title: "Days Remaining",
                            value: Formatters.formatAmount(daysRemaining)
                        )
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Details List
                    VStack(spacing: 0) {
                        HStack {
                            Text("Current Block Height")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(blockHeight.map { Formatters.formatAmount($0) } ?? "Loading...")
                                .fontWeight(.bold)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: blockHeight)
                        }
                        .padding()
                        Divider()
                        
                        HStack {
                            Text("Next Halving Height")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Formatters.formatAmount(nextHalvingHeight))
                                .fontWeight(.bold)
                        }
                        .padding()
                        Divider()
                        
                        HStack {
                            Text("Current Reward")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Formatters.formatBTC(currentReward))
                                .fontWeight(.bold)
                        }
                        .padding()
                        Divider()
                        
                        HStack {
                            Text("Daily Issuance")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Formatters.formatBTC(currentReward * 144))
                                .fontWeight(.bold)
                        }
                        .padding()
                        Divider()
                        
                        HStack {
                            Text("Inflation Rate")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f%%", currentInflationRate))
                                .fontWeight(.bold)
                        }
                        .padding()
                        Divider()
                        
                        HStack {
                            Text("Next Reward")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(Formatters.formatBTC(nextReward))
                                .fontWeight(.bold)
                        }
                        .padding()
    
                    }
                    .background(Material.ultraThin)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal)
                    
                    // MARK: - Reward Chart
                    if let height = blockHeight {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Block Reward Schedule")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            HalvingRewardChart(currentBlockHeight: height)
                        }
                        .padding()
                        .background(Material.ultraThin)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Halving")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await fetchBlockHeight()
                }
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    await fetchBlockHeight()
                }
            }
        }
    }
    
    // MARK: - Row & Explanation (shared look with Block view)
    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 14)
    }
    
    private func explanationRow(key: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.body.weight(.semibold))
            Text("– \(text)")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    // MARK: - Formatting helpers (match Block view style)
    private func formatInt(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
    
    private func formatBTC(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = Locale.current
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 8
        let formatted = nf.string(from: NSNumber(value: value)) ?? String(format: "%.8f", value)
        // Trim trailing zeros and decimal point
        let trimmed = formatted.replacingOccurrences(of: "(\\.?0+)$", with: "", options: .regularExpression)
        return "\(trimmed) BTC"
    }
    
    // MARK: - API
    func fetchBlockHeight() async {
        let urlString = "https://mempool.space/api/blocks/tip/height"
        guard let url = URL(string: urlString) else {
            return
        }
        print("🚀 Starting API call: GET \(urlString)")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                print("📦 Received data for /blocks/tip/height (\(data.count) bytes), status: \(http.statusCode)")
            }
            if let heightString = String(data: data, encoding: .utf8),
               let height = Int(heightString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                await MainActor.run {
                    self.blockHeight = height
                }
            }
        } catch {
            print("❌ Failed to load block height: \(error)")
        }
    }
}

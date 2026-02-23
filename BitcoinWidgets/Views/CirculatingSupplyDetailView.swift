//
//  CirculatingSupplyDetailView.swift
//  BitcoinWidgets
//
//  Created by User on 2025-12-15.
//

import SwiftUI
import Combine

struct CirculatingSupplyDetailView: View {
    @State private var blockHeight: Int?
    @State private var circulatingSupply: Double = 0
    @State private var percentMined: Double = 0
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(accentColor: .blue)
            
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Hero Section
                    VStack(spacing: 8) {
                        Text("CIRCULATING SUPPLY")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(2)
                        
                        Text(Formatters.formatAmount(Int(circulatingSupply)))
                            .font(.system(size: 52, weight: .heavy, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: circulatingSupply)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.horizontal)
                        
                        Text("Bitcoin")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)
                    
                    // MARK: - Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        
                        DetailStatCard(
                            title: "Percentage Mined",
                            value: String(format: "%.4f%%", percentMined)
                        )
                        
                        DetailStatCard(
                            title: "Left to Mine",
                            value: Formatters.formatAmount(Int(21_000_000 - circulatingSupply))
                        )
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Emission Chart
                    if let height = blockHeight {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Emission Schedule")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            
                            HalvingChart(currentBlockHeight: height)
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
            .navigationTitle("Supply")
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
    
    // MARK: - API & Logic
    
    private func fetchBlockHeight() async {
        let urlString = "https://mempool.space/api/blocks/tip/height"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let heightString = String(data: data, encoding: .utf8),
               let height = Int(heightString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                await MainActor.run {
                    self.blockHeight = height
                    self.calculateSupply(height: height)
                }
            }
        } catch { }
    }
    
    private func calculateSupply(height: Int) {
        let halvingInterval = 210_000
        var subsidy = 50.0
        var supply = 0.0
        var remainingHeight = height
        
        // Calculate fully completed eras
        while remainingHeight >= halvingInterval {
            supply += Double(halvingInterval) * subsidy
            remainingHeight -= halvingInterval
            subsidy /= 2.0
        }
        
        // Add remaining blocks in current era
        supply += Double(remainingHeight) * subsidy
        
        self.circulatingSupply = supply
        self.percentMined = (supply / 21_000_000.0) * 100.0
    }
}

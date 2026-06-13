//
//  LightningDetailView.swift
//  BitcoinWidgets
//
//  Reworked to mirror BlockHeightDetailView styling
//

import SwiftUI
import Combine

struct LightningStats: Decodable {
    struct Latest: Decodable {
        let channel_count: Int
        let node_count: Int
        let total_capacity: Int64
        let avg_fee_rate: Int
        let avg_capacity: Int
    }
    let latest: Latest
}

struct LightningDetailView: View {
    @State private var lightningStats: LightningStats?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AnimatedBackgroundView(accentColor: .yellow)
            
            ScrollView {
                VStack(spacing: 24) {
                    if let stats = lightningStats {
                        // MARK: - Hero Section
                        VStack(spacing: 8) {
                            Text("TOTAL CAPACITY")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(2)
                            
                            Text(Formatters.formatLightningBTC(Double(stats.latest.total_capacity) / 100_000_000.0))
                                .font(.system(size: 42, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: stats.latest.total_capacity)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .padding(.horizontal)
                        }
                        .padding(.top, 40)
                        
                        // MARK: - Technical Stats Grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            DetailStatCard(
                                title: "Channel Count",
                                value: Formatters.formatAmount(stats.latest.channel_count)
                            )
                            
                            DetailStatCard(
                                title: "Node Count",
                                value: Formatters.formatAmount(stats.latest.node_count)
                            )
                        }
                        .padding(.horizontal)
                        
                        // MARK: - Details List
                        VStack(spacing: 0) {
                            HStack {
                                Text("Avg Capacity")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatAmount(stats.latest.avg_capacity) + " sats")
                                    .fontWeight(.bold)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: stats.latest.avg_capacity)
                            }
                            .padding()
                            Divider()
                            
                            HStack {
                                Text("Avg Fee Rate")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatAmount(stats.latest.avg_fee_rate) + " ppm")
                                    .fontWeight(.bold)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: stats.latest.avg_fee_rate)
                            }
                            .padding()
                        }
                        .cardSurface()
                        .padding(.horizontal)

                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") { Task { await fetchLightningData() } }
                                .foregroundStyle(Color.bitcoinOrange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                        .padding(.horizontal)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Lightning")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await fetchLightningData()
                }
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    await fetchLightningData()
                }
            }
        }
    }



    func fetchLightningData() async {
        let urlString = "https://mempool.space/api/v1/lightning/statistics/latest"
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(LightningStats.self, from: data)
            await MainActor.run {
                self.lightningStats = decoded
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
}

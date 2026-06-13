//
//  HashrateDetailView.swift
//  BitcoinWidgets
//
//  Reworked to mirror BlockHeightDetailView styling
//

import SwiftUI
import Combine

struct HashrateData: Decodable {
    struct Entry: Decodable {
        let timestamp: Double
        let avgHashrate: Double
    }
    let hashrates: [Entry]
    let currentHashrate: Double
    let currentDifficulty: Double
}

struct HashrateDetailView: View {
    @State private var hashrateData: HashrateData?
    @State private var errorMessage: String?
    @State private var hashratePeriods: [String: Double] = [:]

    var body: some View {
        ZStack {
            AnimatedBackgroundView(accentColor: .cyan)
            
            ScrollView {
                VStack(spacing: 24) {
                    if let hashrate = hashrateData {
                        // MARK: - Hero Section
                        VStack(spacing: 8) {
                            Text("CURRENT HASHRATE")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(2)
                            
                            Text(Formatters.formatHashrate(hashrate.currentHashrate))
                                .font(.system(size: 42, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: hashrate.currentHashrate)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .padding(.horizontal)
                        }
                        .padding(.top, 40)
                        
                        // MARK: - Technical Stats Grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            DetailStatCard(
                                title: "Difficulty",
                                value: Formatters.formatDifficulty(hashrate.currentDifficulty)
                            )
                            
                            DetailStatCard(
                                title: "3 Month Avg",
                                value: Formatters.formatHashrate(hashratePeriods["3m"] ?? 0)
                            )
                        }
                        .padding(.horizontal)
                        
                        // MARK: - Historical Averages List
                        VStack(spacing: 0) {
                            HStack {
                                Text("6 Months Avg")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatHashrate(hashratePeriods["6m"] ?? 0))
                                    .fontWeight(.bold)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: hashratePeriods["6m"])
                            }
                            .padding()
                            Divider()
                            
                            HStack {
                                Text("1 Year Avg")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatHashrate(hashratePeriods["1y"] ?? 0))
                                    .fontWeight(.bold)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: hashratePeriods["1y"])
                            }
                            .padding()
                            Divider()
                            
                            HStack {
                                Text("2 Years Avg")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatHashrate(hashratePeriods["2y"] ?? 0))
                                    .fontWeight(.bold)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: hashratePeriods["2y"])
                            }
                            .padding()
                            Divider()
                            
                            HStack {
                                Text("3 Years Avg")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatHashrate(hashratePeriods["3y"] ?? 0))
                                    .fontWeight(.bold)
                                    .contentTransition(.numericText())
                                    .animation(.snappy, value: hashratePeriods["3y"])
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
                            Button("Retry") { Task { await fetchHashrateData() } }
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
            .navigationTitle("Hashrate")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await fetchHashrateData()
                }
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    await fetchHashrateData()
                }
            }
        }
    }

    // MARK: - API
    func fetchHashrateData() async {
        let baseUrl = "https://mempool.space/api/v1/mining/hashrate/"
        let periods = ["7d", "3m", "6m", "1y", "2y", "3y"]
        var periodAverages: [String: Double] = [:]

        for period in periods {
            let urlString = baseUrl + period
            guard let url = URL(string: urlString) else {
                self.errorMessage = "Invalid URL"
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(HashrateData.self, from: data)
                let avgHashrate = decoded.hashrates.map { $0.avgHashrate }.reduce(0, +) / Double(decoded.hashrates.count)
                periodAverages[period] = avgHashrate
                if period == "7d" {
                    await MainActor.run {
                        self.hashrateData = decoded
                    }
                }
            } catch {
                await MainActor.run { self.errorMessage = error.localizedDescription }
                return
            }
        }
        await MainActor.run {
            self.hashratePeriods = periodAverages
            self.errorMessage = nil
        }
    }
}

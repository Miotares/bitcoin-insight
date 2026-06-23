//
//  FeesDetailView.swift
//  BitcoinWidgets
//
//  Opened by tapping the Network Fees card on the Dashboard. Shows the current
//  recommended fees (from mempool.space) and the historical 3-line fee chart
//  (from the Supabase fees_history backend) under the boxes.
//

import SwiftUI
import Combine

struct FeesDetailView: View {
    @State private var fees: Recommended?
    @State private var isScrubbingChart = false

    private struct Recommended: Decodable {
        let fastestFee: Int
        let halfHourFee: Int
        let hourFee: Int
        let economyFee: Int?
        let minimumFee: Int
    }

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Hero Section
                    VStack(spacing: 8) {
                        Text("FASTEST FEE")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(2)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(fees.map { "\($0.fastestFee)" } ?? "-")
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: fees?.fastestFee)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            Text("sat/vB")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 40)

                    // MARK: - Technical Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        DetailStatCard(title: "30 Min", value: fees.map { "\($0.halfHourFee) sat/vB" } ?? "-")
                        DetailStatCard(title: "1 Hour", value: fees.map { "\($0.hourFee) sat/vB" } ?? "-")
                        DetailStatCard(title: "Economy", value: fees.flatMap { $0.economyFee }.map { "\($0) sat/vB" } ?? "-")
                        DetailStatCard(title: "Minimum", value: fees.map { "\($0.minimumFee) sat/vB" } ?? "-")
                    }
                    .padding(.horizontal)

                    // MARK: - Historical Chart (under the boxes)
                    FeesChart(isScrubbing: $isScrubbingChart)
                        .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(isScrubbingChart)
            .navigationTitle("Network Fees")
            .navigationBarTitleDisplayMode(.inline)
            .task { await fetchFees() }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                Task { await fetchFees() }
            }
        }
    }

    private func fetchFees() async {
        guard let url = URL(string: "https://mempool.space/api/v1/fees/recommended") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Recommended.self, from: data)
            await MainActor.run { self.fees = decoded }
        } catch {
            // Keep the previous values on a transient failure.
        }
    }
}

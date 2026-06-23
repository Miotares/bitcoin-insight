//
//  MoscowTimeDetailView.swift
//  BitcoinWidgets
//
//  Opened by tapping the Moscow Time widget on the Dashboard. Shows the current
//  Moscow Time (sats per 1 unit of the preferred fiat), the same for a few other
//  currencies, and the historical Moscow-Time chart under the boxes.
//

import SwiftUI
import Combine

struct MoscowTimeDetailView: View {
    @ObservedObject private var settings = SettingsManager.shared
    @State private var prices: [String: Double] = SettingsManager.shared.btcPrices
    @State private var isScrubbingChart = false

    private let referenceOrder = ["USD", "EUR", "GBP", "CHF", "JPY", "CAD", "AUD"]

    private var gridCurrencies: [String] {
        Array(referenceOrder.filter { $0 != settings.preferredCurrency }.prefix(4))
    }

    /// Sats per 1 unit of `code` (Moscow Time), or nil if the price is missing.
    private func moscow(_ code: String) -> Double? {
        guard let p = prices[code], p > 0 else { return nil }
        return 100_000_000.0 / p
    }

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Hero Section
                    VStack(spacing: 8) {
                        Text("MOSCOW TIME")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(2)

                        Text(moscow(settings.preferredCurrency).map { Formatters.formatAmount(Int($0.rounded())) } ?? "-")
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: prices[settings.preferredCurrency])
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.horizontal)

                        Text("sats / 1 \(settings.preferredCurrency.uppercased())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    // MARK: - Other currencies
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(gridCurrencies, id: \.self) { code in
                            DetailStatCard(
                                title: "sats / \(code)",
                                value: moscow(code).map { Formatters.formatAmount(Int($0.rounded())) } ?? "-"
                            )
                        }
                    }
                    .padding(.horizontal)

                    // MARK: - Historical Chart (under the boxes)
                    MoscowTimeChart(currency: settings.preferredCurrency, isScrubbing: $isScrubbingChart)
                        .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(isScrubbingChart)
            .navigationTitle("Moscow Time")
            .navigationBarTitleDisplayMode(.inline)
            .task { await fetchPrices() }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                Task { await fetchPrices() }
            }
        }
    }

    private func fetchPrices() async {
        guard let url = URL(string: "https://mempool.space/api/v1/prices") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([String: Double].self, from: data)
            await MainActor.run { self.prices = decoded }
        } catch {
            // Keep the seeded values on a transient failure.
        }
    }
}

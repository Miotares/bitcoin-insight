//
//  PriceDetailView.swift
//  BitcoinWidgets
//
//  Opened by tapping the price hero on the Dashboard. Shows the current price in
//  the preferred currency, a quick multi-currency reference grid, and the
//  historical price chart (with a Price / Moscow-Time toggle) under the boxes.
//

import SwiftUI
import Combine

struct PriceDetailView: View {
    @ObservedObject private var settings = SettingsManager.shared
    /// Current prices per currency from /api/v1/prices. Seeded from the live
    /// values the Dashboard already fetched so the hero shows instantly.
    @State private var prices: [String: Double] = SettingsManager.shared.btcPrices
    @State private var isScrubbingChart = false

    /// Reference currencies for the grid. The liquid majors lead so prefix(4)
    /// always picks ones with a live price; the Tier-1 additions follow.
    private let referenceOrder = ["USD", "EUR", "GBP", "CHF", "JPY", "CAD", "AUD",
                                  "BRL", "INR", "MXN", "KRW", "THB", "IDR", "TRY", "CZK", "PLN"]

    private var gridCurrencies: [String] {
        Array(referenceOrder.filter { $0 != settings.preferredCurrency }.prefix(4))
    }

    // Same tiny multiplier the Dashboard hero applies, so this price isn't a flat
    // mempool integer (always .00) and matches the Dashboard exactly.
    private var heroPrice: Double {
        (prices[settings.preferredCurrency] ?? 0) * SettingsManager.priceDisplayMultiplier
    }

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Hero Section
                    VStack(spacing: 8) {
                        Text("BTC / \(settings.preferredCurrency.uppercased())")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                            .tracking(2)

                        Text(Formatters.formatCurrency(value: heroPrice, currencyCode: settings.preferredCurrency))
                            .font(.system(size: 46, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: heroPrice)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.horizontal)
                    }
                    .padding(.top, 40)

                    // MARK: - Other currencies
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                        ForEach(gridCurrencies, id: \.self) { code in
                            DetailStatCard(
                                title: code,
                                value: prices[code].map { Formatters.formatCurrency(value: $0 * SettingsManager.priceDisplayMultiplier, currencyCode: code) } ?? "-"
                            )
                        }
                    }
                    .padding(.horizontal)

                    // MARK: - Historical Chart (under the boxes)
                    PriceChart(currency: settings.preferredCurrency, isScrubbing: $isScrubbingChart)
                        .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .scrollDisabled(isScrubbingChart)
            .navigationTitle("Price")
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
            await MainActor.run {
                // mempool serves only 7 currencies (+ a non-currency `time` field).
                // MERGE them over the existing values rather than REPLACING, so a
                // non-mempool preferred currency (BRL/INR/CNY/THB/…) keeps the live
                // value the Dashboard derived instead of being wiped to 0 (which made
                // the hero show "Rp 0" for the 12 currencies mempool doesn't serve).
                var merged = self.prices
                for (code, value) in decoded where code.count == 3 { merged[code] = value }
                // The preferred currency drives the hero. If mempool doesn't serve it,
                // pull the Dashboard's freshly-derived value (USD x FX, refreshed every
                // 10s) from the shared store so the hero stays live, not frozen/zero.
                let pref = settings.preferredCurrency.uppercased()
                if decoded[pref] == nil {
                    merged[pref] = SettingsManager.shared.btcPrices[pref] ?? merged[pref]
                }
                self.prices = merged
            }
        } catch {
            // Keep the seeded values on a transient failure.
        }
    }
}

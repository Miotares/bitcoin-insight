//
//  MoscowTimeChart.swift
//  BitcoinWidgets
//
//  Historical "Moscow Time" chart = how many sats equal 1 unit of the preferred
//  fiat currency (1e8 / price). Derived from the same price history as PriceChart
//  (/api/v1/historical-price?currency=CUR), which returns the FULL history in one
//  response. So we fetch ONCE per currency and FILTER client-side per range.
//
//  Mirrors the other charts and reuses ScrubbableLineChart. `points` is kept in
//  @State (rebuilt on data/range change only) so a scrub tick never re-filters.
//

import SwiftUI

private struct MoscowPriceResponse: Decodable {
    let prices: [[String: Double]]
}

struct MoscowTimeChart: View {
    /// Preferred currency code. A change re-fetches.
    let currency: String
    /// Bound to the enclosing screen so it can `.scrollDisabled(_:)` its
    /// ScrollView while scrubbing. Optional — defaults to a throwaway binding.
    @Binding var isScrubbing: Bool

    init(currency: String, isScrubbing: Binding<Bool> = .constant(false)) {
        self.currency = currency
        self._isScrubbing = isScrubbing
    }

    /// Lookback windows. The endpoint returns the whole history, so these only
    /// filter the cached series.
    enum Range: String, CaseIterable, Identifiable {
        case w1 = "1W"
        case m1 = "1M"
        case y1 = "1Y"
        case all = "All"

        var id: String { rawValue }

        var seconds: TimeInterval? {
            switch self {
            case .w1:  return 7 * 86_400
            case .m1:  return 30 * 86_400
            case .y1:  return 365 * 86_400
            case .all: return nil
            }
        }
    }

    /// A sample's date and its Moscow-time value (sats per 1 unit of fiat).
    private struct MoscowPoint {
        let date: Date
        let sats: Double
    }

    @State private var range: Range = .y1
    /// Full fetched Moscow-time history for `currency` (ascending by date).
    @State private var series: [MoscowPoint] = []
    @State private var points: [ScrubPoint] = []
    @State private var isLoading = false
    @State private var failed = false
    @State private var selected: ScrubPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            chart
                .frame(height: 200)

            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .card()
        .onChange(of: range) { _, _ in
            selected = nil
            isScrubbing = false
            rebuildPoints()
        }
        .onChange(of: currency) { _, _ in
            selected = nil
            isScrubbing = false
            Task { await load() }
        }
        .task { await load() }
    }

    // MARK: - Header (doubles as the live scrub readout)

    private var header: some View {
        ZStack(alignment: .leading) {
            Text("MOSCOW TIME · \(currency.uppercased())")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(selected == nil ? 1 : 0)

            if let selected {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(format(selected.value))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(selected.date, format: readoutFormat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .transition(.opacity)
            }
        }
        .frame(height: 24, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: selected)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            ZStack {
                if isLoading {
                    ProgressView()
                } else if failed {
                    VStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                        Text("Couldn't load chart")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrubbableLineChart(
                points: points,
                accent: .bitcoinOrange,
                xAxisFormat: xFormat,
                valueFormat: { format($0) },
                onSelectionChange: { point in
                    selected = point
                },
                onScrubbingChange: { scrubbing in
                    isScrubbing = scrubbing
                }
            )
        }
    }

    private func format(_ v: Double) -> String {
        Formatters.formatAmount(Int(v.rounded())) + " sats"
    }

    private var xFormat: Date.FormatStyle {
        switch range {
        case .w1:  return Date.FormatStyle.dateTime.month(.abbreviated).day()
        case .m1:  return Date.FormatStyle.dateTime.month(.abbreviated).day()
        case .y1:  return Date.FormatStyle.dateTime.month(.abbreviated)
        case .all: return Date.FormatStyle.dateTime.year()
        }
    }

    private var readoutFormat: Date.FormatStyle {
        switch range {
        case .w1:  return Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        default:   return Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        }
    }

    // MARK: - Data

    private func rebuildPoints() {
        guard let latest = series.last?.date else {
            points = []
            return
        }
        let filtered: [MoscowPoint]
        if let window = range.seconds {
            let cutoff = latest.addingTimeInterval(-window)
            filtered = series.filter { $0.date >= cutoff }
        } else {
            filtered = series
        }
        points = filtered.enumerated().map { index, p in
            ScrubPoint(id: index, date: p.date, value: p.sats)
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            failed = false
        }

        guard let url = URL(string: "https://mempool.space/api/v1/historical-price?currency=\(currency)") else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let resp = try JSONDecoder().decode(MoscowPriceResponse.self, from: data)
            let parsed = resp.prices
                .compactMap { dict -> MoscowPoint? in
                    guard let t = dict["time"], let p = dict[currency], p > 0 else { return nil }
                    return MoscowPoint(date: Date(timeIntervalSince1970: t), sats: 100_000_000.0 / p)
                }
                .sorted { $0.date < $1.date }
            await MainActor.run {
                self.series = parsed
                rebuildPoints()
                self.selected = nil
                self.isScrubbing = false
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.failed = true
                self.isLoading = false
            }
        }
    }
}

//
//  PriceChart.swift
//  BitcoinWidgets
//
//  Historical BTC price chart in the user's preferred currency. The full history
//  comes from mempool.space (/api/v1/historical-price?currency=CUR — ~31k points,
//  hourly recent → weekly far back) via the shared `HistoricalPriceStore`, so it
//  is fetched ONCE per currency and shared with the Dashboard's 24h sparkline (no
//  duplicate download). We then FILTER client-side per range (no re-fetch on range
//  change).
//
//  Mirrors the other charts and reuses ScrubbableLineChart (which downsamples the
//  large series to ~500 points for smooth scrubbing). `points` is kept in @State
//  (rebuilt on data/range change only) so a scrub tick never re-filters.
//
//  Moscow Time has its own chart/detail view (MoscowTimeChart) — this one is
//  price only.
//

import SwiftUI

struct PriceChart: View {
    /// Preferred currency code (USD/EUR/GBP/CHF/CAD/AUD/JPY). A change re-fetches.
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

        /// Lookback in seconds; nil = entire history.
        var seconds: TimeInterval? {
            switch self {
            case .w1:  return 7 * 86_400
            case .m1:  return 30 * 86_400
            case .y1:  return 365 * 86_400
            case .all: return nil
            }
        }
    }

    private struct PricePoint {
        let date: Date
        let price: Double
    }

    @State private var range: Range = .m1
    /// Full fetched price history for `currency` (ascending by date).
    @State private var series: [PricePoint] = []
    /// Points for the current range — kept in @State (rebuilt on data/range
    /// change only) so a scrub tick never re-filters/re-maps.
    @State private var points: [ScrubPoint] = []
    @State private var isLoading = false
    @State private var failed = false
    /// The point currently under the finger; nil when not scrubbing.
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
            Text("BTC PRICE · \(currency.uppercased())")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(selected == nil ? 1 : 0)

            if let selected {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(Formatters.formatCurrency(value: selected.value, currencyCode: currency, fractionDigits: 0))
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
                // "All" spans ~15 years; render it dense (uniform daily, so the
                // far past follows real price moves like mempool's recent data and
                // the DB→mempool source switch is invisible). Other ranges keep 500.
                renderTarget: range == .all ? 1500 : 500,
                valueFormat: { Formatters.formatCurrency(value: $0, currencyCode: currency, fractionDigits: 0) },
                onSelectionChange: { point in
                    selected = point
                },
                onScrubbingChange: { scrubbing in
                    isScrubbing = scrubbing
                }
            )
        }
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

    /// Re-derive `points` from the cached `series` for the current range.
    private func rebuildPoints() {
        guard let latest = series.last?.date else {
            points = []
            return
        }
        let filtered: [PricePoint]
        if let window = range.seconds {
            let cutoff = latest.addingTimeInterval(-window)
            filtered = series.filter { $0.date >= cutoff }
        } else {
            filtered = series
        }
        // For the wide "All" range the series mixes mempool's HOURLY recent data
        // with dense DAILY far-past points. The downsampler (LTTB) buckets by array
        // index, so the thousands of hourly-recent indices would hog the samples and
        // starve the far past (e.g. zero points for Sept 2011). Collapse to one point
        // per UTC day first so the input is time-uniform and every era renders at the
        // same daily density. Zoomed ranges (1W/1M/1Y) keep their hourly resolution.
        let prepared = (range == .all) ? Self.collapseToDaily(filtered) : filtered
        points = prepared.enumerated().map { index, p in
            ScrubPoint(id: index, date: p.date, value: p.price)
        }
    }

    /// One point per UTC day (the latest sample of each day), ascending. Makes a
    /// mixed hourly+daily series time-uniform before downsampling.
    private static func collapseToDaily(_ pts: [PricePoint]) -> [PricePoint] {
        guard !pts.isEmpty else { return pts }
        var byDay: [Int: PricePoint] = [:]
        for p in pts {
            byDay[Int(p.date.timeIntervalSince1970 / 86_400)] = p  // pts ascending ⇒ keeps the day's last
        }
        return byDay.keys.sorted().map { byDay[$0]! }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            failed = false
        }

        // Read from the shared mempool cache — the Dashboard sparkline reads the
        // SAME series, so when it already fetched this currency this is a cache hit
        // (no second ~1.4 MB download). Returns empty only if mempool was down.
        let points = await HistoricalPriceStore.shared.series(for: currency)

        await MainActor.run {
            if points.isEmpty {
                self.failed = true
                self.isLoading = false
            } else {
                self.series = points.map { PricePoint(date: $0.date, price: $0.price) }
                rebuildPoints()
                self.selected = nil
                self.isScrubbing = false
                self.isLoading = false
            }
        }
    }
}

//
//  PriceSparkline.swift
//  BitcoinWidgets
//
//  A tiny, non-interactive 24-hour price sparkline shown beside the Dashboard
//  hero price. It is deliberately minimal: no axes, no labels, no scrubbing —
//  just a single line whose color is GREEN when the last 24h closed up and RED
//  when it closed down.
//
//  Data — granular, lightweight
//  -----------------------------
//  Primary source is CoinGecko's `market_chart?days=1`: a tiny (~10 KB) trailing-
//  24h series at ~5-min granularity — the best fit for a chart this small, smoother
//  and lighter than mempool's hourly history. If CoinGecko is unavailable (rate
//  limit / offline) it falls back to mempool.space's `historical-price` via the
//  shared `HistoricalPriceStore` (sliced to 24h) — the SAME cached series the
//  PriceDetailView chart reads, so the fallback reuses that download instead of
//  adding one.
//
//  The color is derived from the sparkline's OWN endpoints (first vs last sample),
//  independent of the Dashboard's per-tick price-flash color.
//
//  Self-contained like PriceChart: it owns its fetch via `.task(id: currency)` and
//  re-loads on a currency change. A slow 5-minute refresh keeps it fresh while the
//  Dashboard stays open without hammering either API (the 24h shape barely moves
//  minute-to-minute). Hit-testing is disabled so a tap passes straight through to
//  the enclosing hero NavigationLink.
//
//  iOS 16+ Charts API only (LineMark/AreaMark/chartYScale/chartXAxis(.hidden)) —
//  a strict subset of what ScrubbableLineChart already relies on.
//

import SwiftUI
import Charts
import OSLog

struct PriceSparkline: View {
    /// Preferred currency code (USD/EUR/GBP/CHF/CAD/AUD/JPY). A change re-fetches.
    let currency: String

    /// Drives a re-fetch when the app returns to the foreground, so the sparkline
    /// is never left stale after the device was locked / the app backgrounded
    /// (the periodic `.task` loop alone wouldn't refresh until its next tick).
    @Environment(\.scenePhase) private var scenePhase

    /// How often the 24h sparkline re-fetches while the Dashboard stays open.
    /// CoinGecko's `days=1` series is bucketed at ~5 min, so this cadence matches
    /// when a genuinely new data point can appear — refreshing faster would just
    /// re-download the same series. (The live price number above updates every
    /// 10s on its own; this is the 24h trend, which moves slowly.)
    private static let refreshInterval: UInt64 = 5 * 60 * 1_000_000_000

    private static let log = Logger(subsystem: "miotares.BitcoinWidgets", category: "Sparkline")

    private struct Sample: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    @State private var samples: [Sample] = []
    /// Fitted y-extent of the current series, stored so the AreaMark baseline and
    /// the y-scale stay stable across re-renders (computed once per load).
    @State private var yLo: Double = 0
    @State private var yHi: Double = 1

    /// Up over the 24h window ⇒ green, down ⇒ red. Flat/empty defaults to up.
    private var isUp: Bool {
        guard let first = samples.first?.value, let last = samples.last?.value else { return true }
        return last >= first
    }

    private var lineColor: Color { isUp ? Theme.Accent.up : Theme.Accent.down }

    var body: some View {
        Group {
            if samples.count >= 2 {
                Chart {
                    ForEach(samples) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("Price", sample.value)
                        )
                        .foregroundStyle(lineColor)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: yLo...yHi)
                .chartLegend(.hidden)
                // No scrub / selection — a tap falls through to the hero link.
                .allowsHitTesting(false)
                .transition(.opacity)
            } else {
                // Reserve the same footprint while loading so the hero doesn't jump.
                Color.clear
            }
        }
        .task(id: currency) {
            await load()
            // Keep the sparkline fresh while the Dashboard stays open, cheaply.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.refreshInterval)
                if Task.isCancelled { break }
                // Force a fresh pull so the shared cache actually updates.
                await load(forceRefresh: true)
            }
        }
        // Refresh immediately when the app comes back to the foreground — the
        // periodic loop above is suspended while backgrounded, so without this the
        // chart could show a stale 24h window right after unlocking.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await load() }
            }
        }
    }

    // MARK: - Data

    private func load(forceRefresh: Bool = false) async {
        // Primary: CoinGecko's trailing-24h chart — ~5-min granularity in a tiny
        // payload, the best fit for this small 24h sparkline.
        if let pts = await fetchCoinGecko(), pts.count >= 2 {
            await apply(pts)
            return
        }
        // Fallback: the shared mempool history (24h slice) — the same cached series
        // the price-detail chart reads — if CoinGecko was unavailable.
        let series = forceRefresh
            ? await HistoricalPriceStore.shared.refreshedSeries(for: currency)
            : await HistoricalPriceStore.shared.series(for: currency)
        if let pts = last24h(from: series), pts.count >= 2 {
            await apply(pts)
        }
    }

    /// Slice the full ascending history to the trailing 24h and re-index it into
    /// `Sample`s. Returns nil if there isn't enough data for a line.
    private func last24h(from series: [HistoricalPriceStore.Point]) -> [Sample]? {
        guard let latest = series.last?.date else { return nil }
        let cutoff = latest.addingTimeInterval(-24 * 3_600)
        let windowed = series.filter { $0.date >= cutoff }
        guard windowed.count >= 2 else { return nil }
        return windowed.enumerated().map { index, point in
            Sample(id: index, date: point.date, value: point.price)
        }
    }

    /// Apply a fresh series on the main actor, memoizing the fitted y-extent.
    private func apply(_ pts: [Sample]) async {
        let values = pts.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return }
        let (lower, upper): (Double, Double)
        if lo == hi {
            let pad = lo == 0 ? 1 : abs(lo) * 0.05
            (lower, upper) = (lo - pad, hi + pad)
        } else {
            let range = hi - lo
            // A little headroom so the line never touches the top/bottom edge.
            (lower, upper) = (lo - range * 0.15, hi + range * 0.15)
        }
        await MainActor.run {
            if samples.isEmpty {
                // First appearance: the y-domain is set instantly and the chart
                // fades in via `.transition(.opacity)`. Nothing morphs, so the
                // line is drawn at the correct positions from the very first frame.
                self.yLo = lower
                self.yHi = upper
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.samples = pts
                }
            } else {
                // Refresh or currency switch: update the y-domain AND the data in
                // ONE non-animated transaction. If the domain snapped to the new
                // currency while the line animated from the old currency's values,
                // those old values fall outside the new domain and the line shoots
                // up out of frame before settling — the "jump". Swapping both
                // together with animations disabled keeps domain and data
                // consistent on every frame, so the chart updates cleanly.
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    self.yLo = lower
                    self.yHi = upper
                    self.samples = pts
                }
            }
        }
        // Heartbeat so a refresh is observable in Console (Logger category
        // "Sparkline"). `.debug` ⇒ no noise in release builds.
        Self.log.debug("Sparkline refreshed [\(currency, privacy: .public)] points=\(pts.count) last=\(pts.last?.value ?? 0)")
    }

    /// Primary: CoinGecko trailing-24h chart (small payload, ~5-min granularity).
    private func fetchCoinGecko() async -> [Sample]? {
        let cur = currency.lowercased()
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/bitcoin/market_chart?vs_currency=\(cur)&days=1") else {
            return nil
        }
        struct Response: Decodable { let prices: [[Double]] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let pts = decoded.prices.enumerated().compactMap { index, pair -> Sample? in
                guard pair.count == 2, pair[1] > 0 else { return nil }
                // CoinGecko timestamps are milliseconds since epoch.
                return Sample(id: index, date: Date(timeIntervalSince1970: pair[0] / 1000), value: pair[1])
            }
            return pts
        } catch {
            return nil
        }
    }
}

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
    /// Currency the currently-shown `samples` belong to. Lets `apply` tell a
    /// same-currency REFRESH (domain barely moves ⇒ animate the line smoothly to
    /// the new 24h shape) apart from a currency SWITCH (domain jumps to a whole
    /// new price scale ⇒ swap without animation, or the old-currency line shoots
    /// out of frame before settling).
    @State private var samplesCurrency: String = ""

    init(currency: String) {
        self.currency = currency
        // Seed from the last persisted 24h series so the chart renders INSTANTLY
        // on launch (no waiting on the network) and appears together with the rest
        // of the Dashboard instead of popping in a moment later. The `.task` below
        // then refreshes it in place.
        let seeded = Self.loadSnapshot(for: currency)
        _samples = State(initialValue: seeded)
        // The seeded snapshot is this currency's series, so the FIRST live fetch
        // after launch counts as a same-currency refresh and morphs smoothly into
        // place (the "open the app and watch it update" moment) rather than snapping.
        _samplesCurrency = State(initialValue: seeded.isEmpty ? "" : currency)
        if let bounds = Self.bounds(for: seeded.map(\.value)) {
            _yLo = State(initialValue: bounds.lo)
            _yHi = State(initialValue: bounds.hi)
        } else {
            _yLo = State(initialValue: 0)
            _yHi = State(initialValue: 1)
        }
    }

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
            return
        }
        // Final fallback for currencies mempool doesn't serve (BRL/INR/…), whose
        // series is DB-daily (too sparse for a 24h slice): derive the 24h shape from
        // the USD history scaled by today's FX ratio. BTC's 24h move is global, so
        // USD x FX reproduces the correct shape and up/down color.
        if let pts = await fetchDerived24h(forceRefresh: forceRefresh), pts.count >= 2 {
            await apply(pts)
        }
    }

    /// USD-24h x FX fallback for non-mempool currencies (see `load`).
    private func fetchDerived24h(forceRefresh: Bool) async -> [Sample]? {
        guard currency.uppercased() != "USD" else { return nil }
        let usdSeries = forceRefresh
            ? await HistoricalPriceStore.shared.refreshedSeries(for: "USD")
            : await HistoricalPriceStore.shared.series(for: "USD")
        guard let fx = await HistoricalPriceStore.latestFXRatio(currency: currency), fx > 0,
              let usd24 = last24h(from: usdSeries), usd24.count >= 2 else { return nil }
        return usd24.map { Sample(id: $0.id, date: $0.date, value: $0.value * fx) }
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
        guard let (lower, upper) = Self.bounds(for: pts.map(\.value)) else { return }
        // Persist so the next launch can render this instantly (see `init`).
        saveSnapshot(pts)
        await MainActor.run {
            let isCurrencySwitch = samplesCurrency != currency
            if samples.isEmpty {
                // First appearance: the y-domain is set instantly and the chart
                // fades in via `.transition(.opacity)`. Nothing morphs, so the
                // line is drawn at the correct positions from the very first frame.
                self.yLo = lower
                self.yHi = upper
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.samples = pts
                }
            } else if isCurrencySwitch {
                // Currency switch: the domain jumps to a whole new price scale, so
                // swap the y-domain AND data in ONE non-animated transaction. If the
                // domain snapped to the new currency while the line animated from the
                // old currency's values, those old values fall outside the new domain
                // and the line shoots out of frame before settling — the "jump".
                // Disabling animations keeps domain and data consistent every frame.
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    self.yLo = lower
                    self.yHi = upper
                    self.samples = pts
                }
            } else {
                // Same-currency refresh (periodic tick / foreground return): the 24h
                // shape barely moves and the domain only inches, so morph the line
                // smoothly to the new state instead of hard-replacing it. The marks
                // are matched by `id`, so Charts interpolates each point's position;
                // the y-domain animates in the SAME transaction so domain and line
                // stay consistent and the line never leaves the frame. This is the
                // pleasant little "settle into the new value" animation on refresh.
                withAnimation(.easeInOut(duration: 0.6)) {
                    self.yLo = lower
                    self.yHi = upper
                    self.samples = pts
                }
            }
            self.samplesCurrency = currency
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

    // MARK: - Fitted y-extent

    /// Fitted lower/upper y-bounds (with headroom) for a set of values, so the
    /// line uses the full height without touching the edges. Shared by `init`
    /// (seeding) and `apply` (refresh). Returns nil for an empty set.
    private static func bounds(for values: [Double]) -> (lo: Double, hi: Double)? {
        guard let lo = values.min(), let hi = values.max() else { return nil }
        if lo == hi {
            let pad = lo == 0 ? 1 : abs(lo) * 0.05
            return (lo - pad, hi + pad)
        }
        let range = hi - lo
        return (lo - range * 0.15, hi + range * 0.15)
    }

    // MARK: - Snapshot persistence (instant render on launch)

    private struct StoredPoint: Codable { let t: Double; let v: Double }
    private static let snapshotKey = "priceSparkline.snapshots.v1"

    /// Last persisted 24h series for `currency`, re-indexed into `Sample`s. Empty
    /// if nothing has been stored yet (first launch) or the snapshot is clearly
    /// stale (newest point older than 36h — e.g. the app sat unused for days), in
    /// which case we'd rather wait for the fetch than seed a misleading shape.
    private static func loadSnapshot(for currency: String) -> [Sample] {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey),
              let all = try? JSONDecoder().decode([String: [StoredPoint]].self, from: data),
              let stored = all[currency.uppercased()], stored.count >= 2,
              let newest = stored.last?.t,
              Date().timeIntervalSince1970 - newest < 36 * 3_600 else { return [] }
        return stored.enumerated().map { index, point in
            Sample(id: index, date: Date(timeIntervalSince1970: point.t), value: point.v)
        }
    }

    /// Persist the current 24h series for `currency` so the next launch renders it
    /// immediately. Keyed per currency so a switch-then-relaunch is still instant.
    private func saveSnapshot(_ pts: [Sample]) {
        var all: [String: [StoredPoint]] = {
            guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
                  let decoded = try? JSONDecoder().decode([String: [StoredPoint]].self, from: data) else { return [:] }
            return decoded
        }()
        all[currency.uppercased()] = pts.map { StoredPoint(t: $0.date.timeIntervalSince1970, v: $0.value) }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        }
    }
}

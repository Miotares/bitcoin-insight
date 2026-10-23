//
//  FeesChart.swift
//  BitcoinWidgets
//
//  Historical recommended-fees chart — three lines (Fast / Medium / Slow) over
//  time. This is the ONLY history chart NOT served by mempool.space: it has no
//  historical recommended-fees endpoint, so we accumulate fees server-side in
//  Supabase (`fees_history`, one row every 10 min) and read them here.
//
//  Raw fee snapshots are low, integer and very noisy (they flip 1 ↔ 3 sat/vB
//  between consecutive blocks), so plotting them directly gives a jagged
//  sawtooth that gets worse the longer the range. Instead every range is
//  re-binned into time buckets (30 min … 1 day) whose MEAN is plotted, then
//  lightly smoothed with a small triangular moving average. The lines show the
//  fee trend; the spikes the smoothing hides are surfaced as the range "Peak"
//  in the header, and the legend shows each tier's range average.
//
//  Uses the reusable MultiScrubChart (N aligned lines + a Slow…Fast band,
//  smooth scrubbing). `rows` is kept in @State so a scrub tick never re-bins.
//

import SwiftUI

struct FeesChart: View {
    @Binding var isScrubbing: Bool

    init(isScrubbing: Binding<Bool> = .constant(false)) {
        self._isScrubbing = isScrubbing
    }

    enum Range: String, CaseIterable, Identifiable {
        case h24 = "24H"
        case w1 = "1W"
        case m1 = "1M"
        case m3 = "3M"
        case all = "All"

        var id: String { rawValue }

        var seconds: TimeInterval? {
            switch self {
            case .h24: return 86_400
            case .w1:  return 7 * 86_400
            case .m1:  return 30 * 86_400
            case .m3:  return 90 * 86_400
            case .all: return nil
            }
        }

        /// Width of one averaged bucket. Chosen so each range plots ~50–125
        /// points, each the mean of roughly 3–15 raw snapshots.
        func binSeconds(span: TimeInterval) -> TimeInterval {
            switch self {
            case .h24: return 30 * 60
            case .w1:  return 2 * 3_600
            case .m1:  return 8 * 3_600
            case .m3:  return 86_400
            case .all: return max(86_400, span / 150)
            }
        }

        /// Half-width (in buckets) of the triangular smoothing kernel.
        var smoothingRadius: Int {
            switch self {
            case .h24: return 1
            case .w1, .m1: return 2
            case .m3: return 3
            case .all: return 4
            }
        }
    }

    private struct FeeEntry: Decodable {
        let recorded_at: String
        let fast: Int
        let half_hour: Int
        let hour: Int
    }

    private struct Sample {
        let date: Date
        let fast: Double
        let halfHour: Double
        let hour: Double
    }

    /// Range summary shown around the chart: per-tier averages (legend) and the
    /// highest raw Fast fee (header) — the spike the smoothing flattens.
    private struct Summary {
        let avgFast: Double
        let avgMedium: Double
        let avgSlow: Double
        let peak: Double
    }

    // Supabase read contract (read-only RLS, publishable key — same as the widget).
    // Server-side downsampling RPC: returns ≤`buckets` time-uniform points for the
    // requested window in ONE request, so long ranges aren't silently truncated at
    // PostgREST's 1000-row page cap. Re-fetched per range with that range's `since`.
    // We ask for the RPC's maximum so the client-side bucket means average enough
    // raw snapshots to be steady.
    private static let rpcEndpoint =
        "https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/rpc/fees_history_series"
    private static let apiKey = "sb_publishable_FEEoI6sfC_EZ1oLP2E0IJQ_Yftfzrk9"
    private static let buckets = 1000

    // values order = [fast, halfHour, hour] → [High/red, Medium/orange, Low/green].
    private static let series: [MultiScrubSeries] = [
        MultiScrubSeries(label: "Fast", color: Theme.Accent.feeHigh),
        MultiScrubSeries(label: "Medium", color: Theme.Accent.feeMid),
        MultiScrubSeries(label: "Slow", color: Theme.Accent.feeLow),
    ]

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    @State private var range: Range = .all
    /// Raw fetched samples per range (ascending by date), so switching back to a
    /// range shows it instantly while it refreshes.
    @State private var cache: [Range: [Sample]] = [:]
    /// Smoothed rows for the current range — kept in @State (rebuilt on data/range
    /// change only) so a scrub tick never re-bins.
    @State private var rows: [MultiScrubRow] = []
    @State private var summary: Summary?
    /// Selected ROW index reported by MultiScrubChart (indexes `rows`).
    @State private var selectedIndex: Int?
    @State private var isLoading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header

            chart
                .frame(height: 200)

            legend

            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .card()
        .onChange(of: range) { _, _ in
            selectedIndex = nil
            isScrubbing = false
            // Show a cached series at once; otherwise keep the current chart up
            // until the new range arrives instead of flashing a spinner.
            if cache[range] != nil { rebuildRows() }
            Task { await load() }   // re-fetch: each range pulls its own window
        }
        .task { await load() }
    }

    private var selectedRow: MultiScrubRow? {
        guard let i = selectedIndex, rows.indices.contains(i) else { return nil }
        return rows[i]
    }

    // MARK: - Header (doubles as the live scrub readout: all three values)

    private var header: some View {
        ZStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Text("NETWORK FEES")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(2)
                    .foregroundStyle(.secondary)

                Spacer(minLength: Theme.Spacing.sm)

                if let summary {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text("Peak")
                            .foregroundStyle(.secondary)
                        Text("\(Int(summary.peak.rounded())) sat/vB")
                            .foregroundStyle(Theme.Accent.feeHigh)
                            .contentTransition(.numericText())
                    }
                    .font(.caption.weight(.semibold))
                    .animation(.snappy, value: summary.peak)
                }
            }
            .opacity(selectedRow == nil ? 1 : 0)

            if let r = selectedRow, r.values.count >= 3 {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(Self.format(r.values[0]))
                        .foregroundStyle(Theme.Accent.feeHigh)
                    Text(Self.format(r.values[1]))
                        .foregroundStyle(Theme.Accent.feeMid)
                    Text(Self.format(r.values[2]))
                        .foregroundStyle(Theme.Accent.feeLow)
                    Text("sat/vB")
                        .foregroundStyle(.secondary)
                    Text(r.date, format: readoutFormat)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.bold))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .transition(.opacity)
            }
        }
        .frame(height: 24, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: selectedIndex)
    }

    // MARK: - Legend (swatch + label + range average per tier)

    private var legend: some View {
        let averages = summary.map { [$0.avgFast, $0.avgMedium, $0.avgSlow] }
        return HStack(spacing: Theme.Spacing.lg) {
            ForEach(Array(Self.series.enumerated()), id: \.offset) { index, s in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(s.color)
                        .frame(width: 10, height: 10)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    Text(s.label)
                        .foregroundStyle(.secondary)
                    if let averages {
                        Text("Ø \(Self.format(averages[index]))")
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .font(.caption2)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy, value: summary?.avgMedium)
    }

    // MARK: - Chart

    @ViewBuilder
    private var chart: some View {
        if rows.isEmpty {
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
                } else {
                    Text("Collecting data…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            MultiScrubChart(
                rows: rows,
                series: Self.series,
                xAxisFormat: xFormat,
                valueFormat: Self.format,
                showsLegend: false,
                band: (lower: 2, upper: 0),
                emphasizedSeries: 1,
                onSelectionChange: { idx in
                    selectedIndex = idx
                },
                onScrubbingChange: { scrubbing in
                    isScrubbing = scrubbing
                }
            )
        }
    }

    private var xFormat: Date.FormatStyle {
        switch range {
        case .h24: return Date.FormatStyle.dateTime.hour()
        case .w1:  return Date.FormatStyle.dateTime.weekday(.abbreviated)
        case .m1, .m3: return Date.FormatStyle.dateTime.month(.abbreviated).day()
        case .all: return Date.FormatStyle.dateTime.month(.abbreviated)
        }
    }

    /// Readout date at the resolution of one bucket (a daily mean has no time).
    private var readoutFormat: Date.FormatStyle {
        switch range {
        case .h24: return Date.FormatStyle.dateTime.hour().minute()
        case .w1:  return Date.FormatStyle.dateTime.weekday(.abbreviated).hour()
        case .m1:  return Date.FormatStyle.dateTime.month(.abbreviated).day().hour()
        case .m3, .all: return Date.FormatStyle.dateTime.month(.abbreviated).day()
        }
    }

    /// Averages are fractional: one decimal below 10 sat/vB, whole numbers above.
    private static func format(_ v: Double) -> String {
        v < 10 ? String(format: "%.1f", v) : "\(Int(v.rounded()))"
    }

    // MARK: - Data

    /// Bin + smooth the current range's samples into chart rows and recompute
    /// the range summary.
    private func rebuildRows() {
        let samples = cache[range] ?? []
        guard let first = samples.first, let last = samples.last else {
            rows = []
            summary = nil
            return
        }

        let span = last.date.timeIntervalSince(first.date)
        let smoothed = Self.smooth(
            Self.bin(samples, width: range.binSeconds(span: span)),
            radius: range.smoothingRadius
        )
        rows = smoothed.enumerated().map { index, s in
            MultiScrubRow(id: index, date: s.date, values: [s.fast, s.halfHour, s.hour])
        }

        let n = Double(samples.count)
        summary = Summary(
            avgFast: samples.reduce(0) { $0 + $1.fast } / n,
            avgMedium: samples.reduce(0) { $0 + $1.halfHour } / n,
            avgSlow: samples.reduce(0) { $0 + $1.hour } / n,
            peak: samples.map(\.fast).max() ?? 0
        )
    }

    /// Mean of every sample that falls into the same fixed-width time bucket.
    /// The bucket's date is the mean of its samples' dates, so the newest point
    /// sits at the latest data rather than at a future bucket edge.
    private static func bin(_ samples: [Sample], width: TimeInterval) -> [Sample] {
        var out: [Sample] = []
        var key: Int?
        var t = 0.0, f = 0.0, h = 0.0, o = 0.0, c = 0.0

        func flush() {
            guard c > 0 else { return }
            out.append(Sample(date: Date(timeIntervalSince1970: t / c), fast: f / c, halfHour: h / c, hour: o / c))
        }

        for s in samples {
            let ts = s.date.timeIntervalSince1970
            let k = Int((ts / width).rounded(.down))
            if k != key {
                flush()
                key = k
                t = 0; f = 0; h = 0; o = 0; c = 0
            }
            t += ts; f += s.fast; h += s.halfHour; o += s.hour; c += 1
        }
        flush()
        return out
    }

    /// Centered triangular moving average (weights 1…radius+1…1), truncated at
    /// the ends. Dates are untouched so every series stays on one x grid.
    private static func smooth(_ samples: [Sample], radius: Int) -> [Sample] {
        guard radius > 0, samples.count > 2 else { return samples }
        return samples.indices.map { i in
            var f = 0.0, h = 0.0, o = 0.0, w = 0.0
            for j in max(0, i - radius)...min(samples.count - 1, i + radius) {
                let weight = Double(radius + 1 - abs(i - j))
                f += samples[j].fast * weight
                h += samples[j].halfHour * weight
                o += samples[j].hour * weight
                w += weight
            }
            return Sample(date: samples[i].date, fast: f / w, halfHour: h / w, hour: o / w)
        }
    }

    /// `since` for the selected range; "All" reaches before any row exists.
    private func since(for range: Range) -> Date {
        if let window = range.seconds {
            return Date().addingTimeInterval(-window)
        }
        return Date(timeIntervalSince1970: 1_230_768_000)  // 2009-01-01
    }

    private func load() async {
        let requested = range
        await MainActor.run {
            isLoading = true
            failed = false
        }

        guard let url = URL(string: Self.rpcEndpoint) else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        let iso = ISO8601DateFormatter().string(from: since(for: requested))
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["since": iso, "buckets": Self.buckets])

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let decoded = try JSONDecoder().decode([FeeEntry].self, from: data)
            let parsed: [Sample] = decoded
                .compactMap { e in
                    guard let d = Self.parseDate(e.recorded_at) else { return nil }
                    return Sample(date: d, fast: Double(e.fast), halfHour: Double(e.half_hour), hour: Double(e.hour))
                }
                .sorted { $0.date < $1.date }
            await MainActor.run {
                self.cache[requested] = parsed
                // A slower response for a range the user already left must not
                // overwrite the chart they are now looking at.
                guard requested == self.range else { return }
                rebuildRows()
                self.selectedIndex = nil
                self.isScrubbing = false
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                guard requested == self.range else { return }
                self.failed = true
                self.isLoading = false
            }
        }
    }

    /// Robustly parse Supabase timestamptz strings ("…:00.058818+00:00") by
    /// dropping the fractional seconds (second precision is plenty for a chart),
    /// which sidesteps ISO8601DateFormatter's 3-digit fractional limitation.
    private static func parseDate(_ s: String) -> Date? {
        let cleaned = s.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        return isoParser.date(from: cleaned)
    }
}

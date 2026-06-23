//
//  FeesChart.swift
//  BitcoinWidgets
//
//  Historical recommended-fees chart — three lines (Fast / Medium / Slow) over
//  time. This is the ONLY history chart NOT served by mempool.space: it has no
//  historical recommended-fees endpoint, so we accumulate fees server-side in
//  Supabase (`fees_history`, one row every 10 min) and read them here. The chart
//  is sparse at first and fills in as the backend keeps collecting.
//
//  Uses the reusable MultiScrubChart (N aligned lines, row-level downsampling,
//  smooth scrubbing). One fetch, client-side range filter; `rows` is kept in
//  @State so a scrub tick never re-filters.
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
        case all = "All"

        var id: String { rawValue }

        var seconds: TimeInterval? {
            switch self {
            case .h24: return 86_400
            case .w1:  return 7 * 86_400
            case .m1:  return 30 * 86_400
            case .all: return nil
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

    // Supabase read contract (read-only RLS, publishable key — same as the widget).
    // desc + high limit so we always get the most RECENT rows (PostgREST caps page size).
    private static let endpoint =
        "https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/fees_history?select=recorded_at,fast,half_hour,hour&order=recorded_at.desc&limit=50000"
    private static let apiKey = "sb_publishable_FEEoI6sfC_EZ1oLP2E0IJQ_Yftfzrk9"

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
    /// Full fetched series (ascending by date).
    @State private var samples: [Sample] = []
    /// Rows for the current range — kept in @State (rebuilt on data/range change
    /// only) so a scrub tick never re-filters.
    @State private var rows: [MultiScrubRow] = []
    /// Selected ROW index reported by MultiScrubChart (indexes `rows`).
    @State private var selectedIndex: Int?
    @State private var isLoading = false
    @State private var failed = false

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
            selectedIndex = nil
            isScrubbing = false
            rebuildRows()
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
            Text("NETWORK FEES")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(selectedRow == nil ? 1 : 0)

            if let r = selectedRow, r.values.count >= 3 {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text("\(Int(r.values[0].rounded()))")
                        .foregroundStyle(Theme.Accent.feeHigh)
                    Text("\(Int(r.values[1].rounded()))")
                        .foregroundStyle(Theme.Accent.feeMid)
                    Text("\(Int(r.values[2].rounded()))")
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
                valueFormat: { "\(Int($0.rounded()))" },
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
        case .m1:  return Date.FormatStyle.dateTime.month(.abbreviated).day()
        case .all: return Date.FormatStyle.dateTime.month(.abbreviated).day()
        }
    }

    private var readoutFormat: Date.FormatStyle {
        Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
    }

    // MARK: - Data

    private func rebuildRows() {
        guard let latest = samples.last?.date else {
            rows = []
            return
        }
        let filtered: [Sample]
        if let window = range.seconds {
            let cutoff = latest.addingTimeInterval(-window)
            filtered = samples.filter { $0.date >= cutoff }
        } else {
            filtered = samples
        }
        rows = filtered.enumerated().map { index, s in
            MultiScrubRow(id: index, date: s.date, values: [s.fast, s.halfHour, s.hour])
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            failed = false
        }

        guard let url = URL(string: Self.endpoint) else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }
        var request = URLRequest(url: url)
        request.setValue(Self.apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(Self.apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

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
                self.samples = parsed
                rebuildRows()
                self.selectedIndex = nil
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

    /// Robustly parse Supabase timestamptz strings ("…:00.058818+00:00") by
    /// dropping the fractional seconds (second precision is plenty for a chart),
    /// which sidesteps ISO8601DateFormatter's 3-digit fractional limitation.
    private static func parseDate(_ s: String) -> Date? {
        let cleaned = s.replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        return isoParser.date(from: cleaned)
    }
}

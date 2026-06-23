//
//  HashrateChart.swift
//  BitcoinWidgets
//
//  Historical network hashrate chart. Data is served natively by mempool.space
//  (/api/v1/mining/hashrate/{period}), so no backend storage is needed — the
//  endpoint already returns a full daily-resolution time series.
//
//  This view owns its range state and fetch, maps the series into ScrubPoints,
//  and delegates ALL rendering + finger-scrubbing to the reusable
//  `ScrubbableLineChart`. The card header doubles as the live scrub readout:
//  while scrubbing it swaps in the touched value + date, and clears on lift.
//
//  Scroll coexistence safeguard
//  ----------------------------
//  `ScrubbableLineChart` uses `.chartXSelection`, which coexists with the host
//  ScrollView under SwiftUI's DEFAULT gesture arbitration (no documented
//  directional hand-off — see that file's header). To make a torn drag
//  impossible regardless of OS-version arbitration quirks, this view exposes its
//  live scrubbing state through `isScrubbing`; the enclosing screen
//  (`HashrateDetailView`) binds it and applies `.scrollDisabled(_:)` to its
//  ScrollView for the duration of a scrub. While the finger is down on the chart
//  the page cannot scroll; on lift, scrolling resumes immediately.
//

import SwiftUI

struct HashrateChart: View {
    /// Bound to the enclosing screen so it can `.scrollDisabled(_:)` its
    /// ScrollView while the user is scrubbing this chart. Optional — defaults to
    /// a throwaway binding so the chart still works when embedded without a
    /// surrounding ScrollView to gate.
    @Binding var isScrubbing: Bool

    init(isScrubbing: Binding<Bool> = .constant(false)) {
        self._isScrubbing = isScrubbing
    }

    /// Selectable ranges → mempool.space period strings (daily-resolution series).
    /// Note: "7d" is NOT a valid period (it falls back to all-time), so the
    /// shortest clean window we expose is 1 month.
    enum Range: String, CaseIterable, Identifiable {
        case m1 = "1M"
        case m3 = "3M"
        case y1 = "1Y"
        case y3 = "3Y"

        var id: String { rawValue }

        var apiPeriod: String {
            switch self {
            case .m1: return "1m"
            case .m3: return "3m"
            case .y1: return "1y"
            case .y3: return "3y"
            }
        }
    }

    @State private var range: Range = .y1
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
            Task { await load() }
        }
        .task { await load() }
    }

    // MARK: - Header (doubles as the live scrub readout)
    //
    // Fixed-height, single-line crossfade so swapping the title for the scrub
    // readout NEVER reflows the layout. The idle caption and the scrub readout
    // are overlaid in a ZStack of constant height; only their opacity animates.

    private var header: some View {
        ZStack(alignment: .leading) {
            // Idle — the chart title.
            Text("HASHRATE HISTORY")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(selected == nil ? 1 : 0)

            // Scrubbing — the touched value + its date, on a single line so it
            // occupies the same height as the title.
            if let selected {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(Formatters.formatHashrate(selected.value))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(selected.date, format: Date.FormatStyle.dateTime.year().month(.abbreviated).day())
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
                valueFormat: Formatters.formatHashrate,
                onSelectionChange: { point in
                    selected = point
                },
                onScrubbingChange: { scrubbing in
                    // Gate the enclosing ScrollView so a drag started on the
                    // chart never tears between scroll and selection.
                    isScrubbing = scrubbing
                }
            )
        }
    }

    private var xFormat: Date.FormatStyle {
        switch range {
        case .m1, .m3: return Date.FormatStyle.dateTime.month(.abbreviated).day()
        case .y1:      return Date.FormatStyle.dateTime.month(.abbreviated)
        case .y3:      return Date.FormatStyle.dateTime.year()
        }
    }

    // MARK: - Fetch

    private func load() async {
        await MainActor.run {
            isLoading = true
            failed = false
        }

        guard let url = URL(string: "https://mempool.space/api/v1/mining/hashrate/\(range.apiPeriod)") else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(HashrateData.self, from: data)
            let parsed = decoded.hashrates
                .map { (date: Date(timeIntervalSince1970: $0.timestamp), value: $0.avgHashrate) }
                .sorted { $0.date < $1.date }
                .enumerated()
                .map { ScrubPoint(id: $0.offset, date: $0.element.date, value: $0.element.value) }
            await MainActor.run {
                self.points = parsed
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

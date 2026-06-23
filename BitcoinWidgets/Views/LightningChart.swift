//
//  LightningChart.swift
//  BitcoinWidgets
//
//  Historical Lightning Network chart with a metric toggle (Capacity / Channels
//  / Nodes). Served natively by mempool.space
//  (/api/v1/lightning/statistics/{period} → daily snapshots), so no backend
//  storage is needed.
//
//  Mirrors HashrateChart/MempoolChart and reuses ScrubbableLineChart, but adds a
//  metric Picker. One fetch returns ALL fields per snapshot, so switching metric
//  only re-maps the cached entries — no re-fetch. `points` is kept in @State
//  (rebuilt only on data/metric change, never per scrub tick) so the chart's
//  performance optimizations are preserved.
//
//  Node count: the history endpoint has NO node_count field (unlike /latest), but
//  the node categories are DISJOINT, so the total is simply
//  clearnet + tor + clearnet_tor + unannounced — which matches the /latest
//  node_count exactly (verified), so this line agrees with the detail view's box.
//

import SwiftUI

/// One daily snapshot from /api/v1/lightning/statistics/{period}.
private struct LightningStatEntry: Decodable {
    let added: Double            // Unix seconds
    let channel_count: Int
    let total_capacity: Double   // sats
    let tor_nodes: Int
    let clearnet_nodes: Int
    let unannounced_nodes: Int
    let clearnet_tor_nodes: Int
}

struct LightningChart: View {
    /// Bound to the enclosing screen so it can `.scrollDisabled(_:)` its
    /// ScrollView while scrubbing. Optional — defaults to a throwaway binding.
    @Binding var isScrubbing: Bool

    init(isScrubbing: Binding<Bool> = .constant(false)) {
        self._isScrubbing = isScrubbing
    }

    /// Which series to plot. One fetch carries all three, so switching is a
    /// cheap re-map (no network).
    enum Metric: String, CaseIterable, Identifiable {
        case capacity = "Capacity"
        case channels = "Channels"
        case nodes = "Nodes"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .capacity: return "LIGHTNING CAPACITY"
            case .channels: return "CHANNEL COUNT"
            case .nodes:    return "NODE COUNT"
            }
        }

        fileprivate func value(_ e: LightningStatEntry) -> Double {
            switch self {
            case .capacity: return e.total_capacity / 100_000_000.0   // sats → BTC
            case .channels: return Double(e.channel_count)
            // Disjoint node categories → simple sum equals /latest node_count.
            case .nodes:    return Double(e.clearnet_nodes + e.tor_nodes + e.clearnet_tor_nodes + e.unannounced_nodes)
            }
        }

        func format(_ v: Double) -> String {
            switch self {
            case .capacity:           return Formatters.formatLightningBTC(v)
            case .channels, .nodes:   return Formatters.formatAmount(Int(v.rounded()))
            }
        }
    }

    /// Selectable ranges → mempool.space lightning period strings. The endpoint
    /// only has daily snapshots, so 24h/1w return nothing — 1M is the shortest.
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

    @State private var metric: Metric = .capacity
    @State private var range: Range = .y1
    /// Cached raw snapshots for the current range (carry all metrics).
    @State private var entries: [LightningStatEntry] = []
    /// Points for the current metric — kept in @State (rebuilt on data/metric
    /// change only) so a scrub tick never re-maps/re-sorts the series.
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

            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .card()
        .onChange(of: metric) { _, _ in
            // Same data, different series — re-map only, no fetch.
            selected = nil
            isScrubbing = false
            rebuildPoints()
        }
        .onChange(of: range) { _, _ in
            selected = nil
            isScrubbing = false
            Task { await load() }
        }
        .task { await load() }
    }

    // MARK: - Header (doubles as the live scrub readout)

    private var header: some View {
        ZStack(alignment: .leading) {
            Text(metric.title)
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(selected == nil ? 1 : 0)

            if let selected {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(metric.format(selected.value))
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
                valueFormat: { metric.format($0) },
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
        case .m1, .m3: return Date.FormatStyle.dateTime.month(.abbreviated).day()
        case .y1:      return Date.FormatStyle.dateTime.month(.abbreviated)
        case .y3:      return Date.FormatStyle.dateTime.year()
        }
    }

    // MARK: - Data

    /// Re-derive `points` from the cached `entries` for the current metric.
    private func rebuildPoints() {
        points = entries
            .map { (date: Date(timeIntervalSince1970: $0.added), value: metric.value($0)) }
            .sorted { $0.date < $1.date }
            .enumerated()
            .map { ScrubPoint(id: $0.offset, date: $0.element.date, value: $0.element.value) }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            failed = false
        }

        guard let url = URL(string: "https://mempool.space/api/v1/lightning/statistics/\(range.apiPeriod)") else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([LightningStatEntry].self, from: data)
            await MainActor.run {
                self.entries = decoded
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

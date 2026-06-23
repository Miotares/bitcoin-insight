//
//  MempoolChart.swift
//  BitcoinWidgets
//
//  Historical mempool transaction-count chart. Served natively by mempool.space
//  (/api/v1/statistics/{period} → array of { added, count, ... }), so no backend
//  storage is needed.
//
//  Mirrors HashrateChart: owns its range state + fetch, maps the series into
//  ScrubPoints, and delegates ALL rendering + finger-scrubbing to the reusable
//  `ScrubbableLineChart`. The card header doubles as the live scrub readout.
//  See HashrateChart for the scroll-coexistence rationale behind `isScrubbing`.
//

import SwiftUI

/// One sample from /api/v1/statistics/{period}. `count` is averaged for longer
/// periods, so it is decoded as a Double.
private struct MempoolStatEntry: Decodable {
    let added: Double      // Unix seconds
    let count: Double      // mempool transaction count
}

struct MempoolChart: View {
    /// Bound to the enclosing screen so it can `.scrollDisabled(_:)` its
    /// ScrollView while the user is scrubbing. Optional — defaults to a throwaway
    /// binding so the chart still works when embedded without a ScrollView to gate.
    @Binding var isScrubbing: Bool

    init(isScrubbing: Binding<Bool> = .constant(false)) {
        self._isScrubbing = isScrubbing
    }

    /// Selectable ranges → mempool.space statistics period strings.
    enum Range: String, CaseIterable, Identifiable {
        case h24 = "24H"
        case w1 = "1W"
        case m1 = "1M"
        case y1 = "1Y"

        var id: String { rawValue }

        var apiPeriod: String {
            switch self {
            case .h24: return "24h"
            case .w1:  return "1w"
            case .m1:  return "1m"
            case .y1:  return "1y"
            }
        }
    }

    @State private var range: Range = .w1
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

    private var header: some View {
        ZStack(alignment: .leading) {
            Text("MEMPOOL TRANSACTIONS")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(selected == nil ? 1 : 0)

            if let selected {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(formatCount(selected.value))
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
                valueFormat: { formatCount($0) },
                onSelectionChange: { point in
                    selected = point
                },
                onScrubbingChange: { scrubbing in
                    isScrubbing = scrubbing
                }
            )
        }
    }

    private func formatCount(_ value: Double) -> String {
        Formatters.formatAmount(Int(value.rounded()))
    }

    private var xFormat: Date.FormatStyle {
        switch range {
        case .h24: return Date.FormatStyle.dateTime.hour()
        case .w1:  return Date.FormatStyle.dateTime.weekday(.abbreviated)
        case .m1:  return Date.FormatStyle.dateTime.month(.abbreviated).day()
        case .y1:  return Date.FormatStyle.dateTime.month(.abbreviated)
        }
    }

    /// Scrub readout date format — short ranges include the time of day.
    private var readoutFormat: Date.FormatStyle {
        switch range {
        case .h24, .w1: return Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        case .m1, .y1:  return Date.FormatStyle.dateTime.year().month(.abbreviated).day()
        }
    }

    // MARK: - Fetch

    private func load() async {
        await MainActor.run {
            isLoading = true
            failed = false
        }

        guard let url = URL(string: "https://mempool.space/api/v1/statistics/\(range.apiPeriod)") else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode([MempoolStatEntry].self, from: data)
            let parsed = decoded
                .map { (date: Date(timeIntervalSince1970: $0.added), value: $0.count) }
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

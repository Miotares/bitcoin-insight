//
//  DifficultyChart.swift
//  BitcoinWidgets
//
//  Historical mining-difficulty chart. Served natively by mempool.space
//  (/api/v1/mining/difficulty-adjustments/{period}), so no backend storage is
//  needed. Difficulty only changes every retarget (~2 weeks), so the series is
//  one point per adjustment — sparse on short ranges, hence 6M is the shortest.
//
//  Mirrors HashrateChart/MempoolChart and reuses ScrubbableLineChart.
//
//  The endpoint returns positional arrays: [timestamp, height, difficulty,
//  adjustmentRatio]. We take index 0 (Unix seconds) and index 2 (difficulty).
//

import SwiftUI

struct DifficultyChart: View {
    /// Bound to the enclosing screen so it can `.scrollDisabled(_:)` its
    /// ScrollView while scrubbing. Optional — defaults to a throwaway binding.
    @Binding var isScrubbing: Bool

    init(isScrubbing: Binding<Bool> = .constant(false)) {
        self._isScrubbing = isScrubbing
    }

    /// Difficulty retargets are ~2 weeks apart, so short windows have very few
    /// points (1M = 2). 6M (~13 points) is the shortest that reads as a trend.
    enum Range: String, CaseIterable, Identifiable {
        case m6 = "6M"
        case y1 = "1Y"
        case y2 = "2Y"
        case y3 = "3Y"

        var id: String { rawValue }

        var apiPeriod: String {
            switch self {
            case .m6: return "6m"
            case .y1: return "1y"
            case .y2: return "2y"
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

    private var header: some View {
        ZStack(alignment: .leading) {
            Text("DIFFICULTY HISTORY")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(.secondary)
                .opacity(selected == nil ? 1 : 0)

            if let selected {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(Formatters.formatDifficulty(selected.value))
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
                valueFormat: Formatters.formatDifficulty,
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
        case .m6, .y1: return Date.FormatStyle.dateTime.month(.abbreviated)
        case .y2, .y3: return Date.FormatStyle.dateTime.year()
        }
    }

    // MARK: - Fetch

    private func load() async {
        await MainActor.run {
            isLoading = true
            failed = false
        }

        guard let url = URL(string: "https://mempool.space/api/v1/mining/difficulty-adjustments/\(range.apiPeriod)") else {
            await MainActor.run { isLoading = false; failed = true }
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Positional rows: [timestamp, height, difficulty, adjustment].
            let decoded = try JSONDecoder().decode([[Double]].self, from: data)
            let parsed = decoded
                .compactMap { row -> (date: Date, value: Double)? in
                    guard row.count >= 3 else { return nil }
                    return (date: Date(timeIntervalSince1970: row[0]), value: row[2])
                }
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

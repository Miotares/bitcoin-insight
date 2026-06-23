//
//  MultiScrubChart.swift
//  BitcoinWidgets
//
//  A reusable MULTI-SERIES (N lines, no area fill) time-series chart with
//  finger-scrubbing. The multi-line sibling of `ScrubbableLineChart`, built to the
//  SAME scrub feel + performance contract; it backs the Network-Fees chart (Fast /
//  Medium / Slow) but is generic over any N series that share ONE x-axis.
//
//  Why a SEPARATE component (vs. extending ScrubbableLineChart)
//  -----------------------------------------------------------
//  Every series here comes from the SAME rows (one fee snapshot per timestamp), so
//  they share a single common x-axis and a single nearest-row lookup. The caller's
//  header readout shows ALL series values at the touched timestamp, so the scrub
//  reports a ROW INDEX (Int?), not one point. Modelling each line as an independent
//  `[ScrubPoint]` would (a) need N parallel charts or N decimations and (b) risk the
//  series drifting to DIFFERENT x positions after downsampling, so a dot could not
//  land on every line at the same date. Rows keep all series locked to one x grid.
//
//  Scrubbing strategy — identical to ScrubbableLineChart
//  -----------------------------------------------------
//  Native `.chartXSelection(value:)` (iOS 17) binds a `Date?` in the data domain.
//  It coexists with an enclosing ScrollView under SwiftUI's DEFAULT gesture
//  arbitration (the scroll's pan wins a mostly-vertical drag; a horizontal drag
//  drives the selection). As a belt-and-braces safeguard the component reports its
//  scrubbing state via `onScrubbingChange(_:)` so a caller MAY gate its ScrollView
//  for the duration of a scrub. A selection haptic fires ONLY when the snapped ROW
//  index changes; the selection clears on finger-lift AND on a data swap.
//
//  Performance — O(log n) per scrub tick (mirrors ScrubbableLineChart)
//  ------------------------------------------------------------------
//  Rows can grow to thousands over time. Four changes keep a scrub at 60fps:
//
//    1. ROW-LEVEL DOWNSAMPLING. We decimate by selecting WHOLE ROWS so every
//       series keeps the SAME x positions (a dot must land on every line at the
//       same date). LTTB is run on ONE representative scalar per row (the max of
//       the row's values) to choose which row INDICES to keep, then those FULL rows
//       are kept for all series. First/last always kept. Target ~500 rows. Memoized
//       once per data change (NOT per scrub tick). We deliberately do NOT decimate
//       each series independently — that would misalign x across series.
//
//    2. BINARY-SEARCH nearest ROW by date. `displayRows` is ascending by date, so
//       the lookup is O(log n) per tick instead of O(n).
//
//    3. DECOUPLED LAYERS. The heavy static N-line curve is an `Equatable` sub-view
//       (`StaticCurves`) keyed ONLY on the data + look, so a selection change
//       leaves its inputs identical and SwiftUI SKIPS rebuilding it (the hundreds of
//       LineMarks across N series are not re-laid-out per tick). The moving RuleMark
//       + per-series dots live in a SEPARATE lightweight Chart overlaid in a ZStack.
//       Both layers are pinned to the SAME explicit x/y domain, so the indicator
//       lands pixel-for-pixel on every line. `.chartXSelection` is installed on the
//       INDICATOR chart (a plain ZStack has no plot context → dead selection).
//
//    4. MEMOIZED Y-EXTENT. The fitted y-domain is the min/max ACROSS ALL SERIES of
//       the decimated rows, computed ONCE per data change (a single pass in
//       `syncDisplayRows()`) and stored as scalars — so a scrub tick reads cached
//       `Double`s instead of re-scanning every row × series, with no transient
//       `[Double]` allocations. The per-tick data-sized cost is then purely the
//       O(log n) binary search.
//
//  Colour is applied DIRECTLY per series (`.foregroundStyle(series.color)` on each
//  line, and on each dot) rather than through a label-keyed `chartForegroundStyle
//  Scale`. That keeps each line/dot exactly its series colour and is immune to a
//  caller passing two series with the same label (which would collapse a label-keyed
//  scale's domain). The series-grouping key for `LineMark(series:)` is the series'
//  positional id, so N distinct lines are always produced.
//
//  iOS 17.6 compatible — `.chartXSelection`, RuleMark, PointMark, `.chartXScale`,
//  `.chartYScale`, EquatableView and `ForEach` over series are all iOS 17 API.
//  No iOS 18+ Charts additions are used.
//

import SwiftUI
import Charts

// MARK: - Public API

/// One plotted series: a label for the legend and a line color. The series'
/// values live at the matching index inside every `MultiScrubRow.values`.
struct MultiScrubSeries: Identifiable, Equatable {
    /// Stable identity for `ForEach`. Defaults to the series' position, assigned by
    /// `MultiScrubChart` when not supplied, so callers can pass plain label+color.
    let id: Int
    let label: String
    let color: Color

    init(id: Int = 0, label: String, color: Color) {
        self.id = id
        self.label = label
        self.color = color
    }
}

/// One row of the multi-series chart: a single timestamp with one value per series.
///
/// `values[i]` belongs to `series[i]`. `id` is the row's index in the ordered
/// (ascending-by-date) series, which makes row-index-change detection (for the
/// scrub haptic) trivial and stable, and keeps `ForEach` identity unique even when
/// two rows share a timestamp.
struct MultiScrubRow: Identifiable, Equatable {
    let id: Int
    let date: Date
    let values: [Double]

    init(id: Int, date: Date, values: [Double]) {
        self.id = id
        self.date = date
        self.values = values
    }
}

struct MultiScrubChart: View {
    /// Ordered (ascending by date) rows. May be empty or single.
    let rows: [MultiScrubRow]
    /// One entry per value column. `values[i]` is drawn with `series[i].color`.
    let series: [MultiScrubSeries]
    /// Date style for the x-axis tick labels.
    let xAxisFormat: Date.FormatStyle
    /// Formats a y value (used only by the optional legend / future readout).
    let valueFormat: (Double) -> String
    /// When false the x-axis is omitted entirely (same look as ScrubbableLineChart).
    let showsXAxis: Bool
    /// When true, a compact [swatch + label] legend is drawn under the chart.
    let showsLegend: Bool
    /// Called whenever the selected ROW index changes (including to `nil` on lift).
    /// The caller reads `rows[index].values` to drive its own multi-series readout.
    let onSelectionChange: (Int?) -> Void
    /// Called when scrubbing starts (`true`) and ends (`false`). A caller MAY use
    /// this to disable an enclosing ScrollView for the duration of the scrub.
    let onScrubbingChange: (Bool) -> Void

    init(
        rows: [MultiScrubRow],
        series: [MultiScrubSeries],
        xAxisFormat: Date.FormatStyle,
        valueFormat: @escaping (Double) -> String,
        showsXAxis: Bool = true,
        showsLegend: Bool = true,
        onSelectionChange: @escaping (Int?) -> Void = { _ in },
        onScrubbingChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.rows = rows
        // Normalize series identity to their position so `ForEach` ids are unique
        // and stable regardless of what the caller passed for `id`.
        self.series = series.enumerated().map { offset, s in
            MultiScrubSeries(id: offset, label: s.label, color: s.color)
        }
        self.xAxisFormat = xAxisFormat
        self.valueFormat = valueFormat
        self.showsXAxis = showsXAxis
        self.showsLegend = showsLegend
        self.onSelectionChange = onSelectionChange
        self.onScrubbingChange = onScrubbingChange
    }

    /// Target ROW count for rendering + lookup. A ~350pt-wide chart resolves well
    /// under this many distinct x positions, so ~500 is a generous ceiling that
    /// keeps the curves visually lossless while capping the per-frame mark count.
    /// Row sets at or below this are used as-is.
    private static let renderTarget = 500

    /// Raw x location under the finger, in the data (Date) domain. Driven and
    /// cleared by Charts via `.chartXSelection`.
    @State private var selectedDate: Date?
    /// Index of the ROW currently snapped-to (nil when not scrubbing). Indexes into
    /// `displayRows`. Tracked separately so the haptic fires ONLY on an index change.
    @State private var selectedDisplayIndex: Int?

    /// Memoized decimated rows used for BOTH rendering and the nearest lookup.
    /// Recomputed by `syncDisplayRows()` only when the source changes (keyed on
    /// `displaySourceKey`), NOT on every body evaluation — so a scrub tick never
    /// re-runs LTTB.
    @State private var displayRows: [MultiScrubRow] = []
    /// Identity of the data `displayRows` was computed from — cheap to compare
    /// (count + endpoints) and stable across the unchanged re-renders a scrub
    /// produces.
    @State private var displaySourceKey: MultiSourceKey?

    /// Memoized y-extent across ALL series of `displayRows`, computed ONCE per data
    /// change (single pass in `syncDisplayRows()`), never per scrub tick. The
    /// `yDomain` reads these stored scalars instead of re-scanning every row ×
    /// series on every body evaluation.
    @State private var displayValueLo: Double = 0
    @State private var displayValueHi: Double = 0
    /// False until `syncDisplayRows()` has populated the extent from non-empty data,
    /// so `yDomain` falls back to its empty default before the first sync.
    @State private var hasMemoizedExtent: Bool = false

    /// Scrubbing is only meaningful with at least two rows. With 0 or 1 rows the
    /// chart is purely static — we never attach a live selection binding, so there
    /// is no path that could index a degenerate set or fire a phantom haptic.
    private var isScrubbable: Bool { displayRows.count >= 2 }

    /// The row under the finger, resolved from `selectedDisplayIndex`. Index-checked
    /// so there is no out-of-bounds even if `displayRows` shrinks. Resolved against
    /// the SAME array the curves are drawn from, so each dot sits on its line.
    private var selectedRow: MultiScrubRow? {
        guard let i = selectedDisplayIndex, displayRows.indices.contains(i) else { return nil }
        return displayRows[i]
    }

    // MARK: - Domains (shared by both layers so they register pixel-perfect)

    /// X domain spanning the (decimated) rows. Pinned explicitly on BOTH the static
    /// curves layer and the indicator layer so the two stacked charts map
    /// time → x identically and the RuleMark/dots land exactly on the curves.
    private var xDomain: ClosedRange<Date> {
        guard let first = displayRows.first?.date,
              let last = displayRows.last?.date else {
            let now = Date()
            return now...now.addingTimeInterval(1)
        }
        guard first < last else { return first...first.addingTimeInterval(1) }
        return first...last
    }

    /// Y range fitted to the min..max ACROSS ALL series (with small symmetric
    /// padding) rather than anchoring at zero, so the lines use the full height.
    /// Reads the MEMOIZED `displayValueLo/Hi`, so this is pure scalar math with NO
    /// per-tick scan and no transient `[Double]` allocation. Shared by both layers.
    private var yDomain: ClosedRange<Double> {
        guard hasMemoizedExtent else { return 0...1 }
        let lo = displayValueLo
        let hi = displayValueHi
        guard lo != hi else {
            // Flat data — pad symmetrically so it doesn't collapse to a line.
            let pad = lo == 0 ? 1 : abs(lo) * 0.08
            return (lo - pad)...(hi + pad)
        }
        let range = hi - lo
        // Small headroom on each side (~8%), so the lines breathe without zooming.
        return (lo - range * 0.08)...(hi + range * 0.08)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ZStack {
                // LAYER 1 — the heavy static N-line curves. Equatable + keyed ONLY
                // on the data and look, so a selection change (which leaves all of
                // these inputs identical) makes SwiftUI SKIP rebuilding it. This is
                // what keeps a scrub tick from re-laying-out N×~500 marks.
                StaticCurves(
                    rows: displayRows,
                    series: series,
                    xDomain: xDomain,
                    yDomain: yDomain,
                    showsXAxis: showsXAxis,
                    xAxisFormat: xAxisFormat
                )
                .equatable()

                // LAYER 2 — the lightweight moving indicator (RuleMark + one dot per
                // series). Pinned to the SAME x/y domain as the curves so it overlays
                // pixel-for-pixel. The native `.chartXSelection` is installed on THIS
                // layer (a real Chart with plot context) and it sits on top, so it
                // owns the touch; the static curves below are inert.
                indicatorLayer
            }
            // Map the raw x location to the nearest row, fire the per-index haptic,
            // and notify the caller.
            .onChange(of: selectedDate) { _, newDate in
                handleSelectionChange(to: newDate)
            }
            // Keep `displayRows` in sync with the source data. Runs on first
            // appearance and whenever the source changes; the guard inside makes the
            // repeated unchanged re-renders of a scrub a no-op (no LTTB, no churn).
            .onAppear { syncDisplayRows() }
            .onChange(of: MultiSourceKey(rows)) { _, _ in
                syncDisplayRows()
            }

            if showsLegend && !series.isEmpty {
                legend
            }
        }
    }

    // MARK: - Indicator layer (lightweight, rebuilt per scrub tick)

    @ViewBuilder
    private var indicatorLayer: some View {
        Chart {
            if let row = selectedRow {
                RuleMark(x: .value("Selected", row.date))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                // One enlarged dot per series, each painted DIRECTLY in its series
                // color via `.foregroundStyle(s.color)` (no label-keyed style scale),
                // all at the SAME row date — so a dot lands on every line at the
                // touched x. The overlay annotation also fills in the series color,
                // so the visible dot is correct regardless of how Charts styles the
                // underlying PointMark.
                ForEach(series) { s in
                    if let v = value(of: row, at: s.id) {
                        PointMark(
                            x: .value("Selected", row.date),
                            y: .value("Value", v)
                        )
                        .foregroundStyle(s.color)
                        .symbolSize(140)
                        .annotation(position: .overlay, spacing: 0) {
                            Circle()
                                .fill(s.color)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.background, lineWidth: 2))
                        }
                    }
                }
            }
        }
        // No `chartForegroundStyleScale`: each dot carries its own colour above, so
        // there is no label-domain to collapse. Hide any built-in legend.
        .chartLegend(.hidden)
        // Pin to EXACTLY the same domains as the static curves so the indicator maps
        // onto the lines pixel-for-pixel.
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        // CRITICAL for alignment: when the curves layer shows an x-axis, its labels
        // shrink its PLOT area upward. If this overlay simply hid its x-axis it would
        // keep a TALLER plot, so `position(forY:)` would map differently and the
        // dots/rule would sit off the lines. So we mirror the curves' x-axis cadence
        // here but render every mark INVISIBLE (an empty label in the SAME caption2
        // font, no gridline), reserving an identical bottom band so both plot rects
        // coincide pixel-for-pixel. When the caller hides the x-axis, neither layer
        // reserves the band — still aligned.
        .chartXAxis {
            if showsXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel {
                        Text(" ")
                            .font(.caption2)
                            .foregroundStyle(.clear)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        // Native selection lives HERE — on a real Chart with plot context, not on
        // the enclosing ZStack (which has none). This layer is on top of the static
        // curves, so it owns the scrub touch. Only attached when the data is
        // actually scrubbable — for a 0/1-row set the binding is a constant nil, so a
        // tap cannot drive `selectedDate`, reach `handleSelectionChange`, or fire a
        // phantom haptic.
        .chartXSelection(value: isScrubbable ? $selectedDate : .constant(nil))
    }

    // MARK: - Legend

    private var legend: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ForEach(series) { s in
                HStack(spacing: Theme.Spacing.xs) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(s.color)
                        .frame(width: 10, height: 10)
                    Text(s.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Series helpers

    /// Safe value lookup: `series[i]` corresponds to `row.values[i]`, but a row may
    /// (defensively) carry fewer columns than there are series.
    private func value(of row: MultiScrubRow, at seriesIndex: Int) -> Double? {
        row.values.indices.contains(seriesIndex) ? row.values[seriesIndex] : nil
    }

    // MARK: - Display-rows memoization

    /// Recompute `displayRows` from the current `rows`, but ONLY when the source
    /// actually changed. Called from `.onAppear` and the source-key `onChange`; the
    /// key comparison makes the many identical re-renders during a scrub a cheap
    /// no-op (LTTB never runs on a tick).
    private func syncDisplayRows() {
        let key = MultiSourceKey(rows)
        guard key != displaySourceKey else { return }
        displaySourceKey = key

        let decimated = MultiScrubChart.downsampleRows(rows, target: Self.renderTarget)
        displayRows = decimated

        // Compute the y-extent ACROSS ALL SERIES ONCE here (single pass over the
        // decimated rows × columns) and memoize it, so `yDomain` never re-scans on a
        // scrub tick. This is the only place the extent is derived.
        var lo = Double.greatestFiniteMagnitude
        var hi = -Double.greatestFiniteMagnitude
        var sawValue = false
        for row in decimated {
            for v in row.values {
                if v < lo { lo = v }
                if v > hi { hi = v }
                sawValue = true
            }
        }
        if sawValue {
            displayValueLo = lo
            displayValueHi = hi
            hasMemoizedExtent = true
        } else {
            displayValueLo = 0
            displayValueHi = 0
            hasMemoizedExtent = false
        }

        // The data set changed — any prior selection refers to a stale array.
        clearSelection()
    }

    // MARK: - Selection plumbing

    /// Resolves the raw selected x into a snapped ROW index, fires the haptic only
    /// on an index change, and notifies the caller with the index into the ORIGINAL
    /// `rows` (so `rows[index].values` is valid for the caller's readout). A nil
    /// `date` (finger lifted) clears the selection.
    private func handleSelectionChange(to date: Date?) {
        guard let date, isScrubbable else {
            clearSelection()
            return
        }
        guard let displayIndex = nearestDisplayIndex(to: date) else {
            clearSelection()
            return
        }
        if selectedDisplayIndex == nil {
            // First snap of this scrub — tell the caller scrubbing began.
            onScrubbingChange(true)
        }
        if displayIndex != selectedDisplayIndex {
            selectedDisplayIndex = displayIndex
            Haptics.selection()                 // tick ONLY on an index change
            onSelectionChange(displayRows[displayIndex].id)
        }
    }

    /// Clears the selection (finger lift / data swap) and notifies the caller. Also
    /// resets the bound `selectedDate` so no stale domain value lingers, and signals
    /// the end of scrubbing.
    private func clearSelection() {
        if selectedDate != nil { selectedDate = nil }
        guard selectedDisplayIndex != nil else { return }
        selectedDisplayIndex = nil
        onSelectionChange(nil)
        onScrubbingChange(false)
    }

    // MARK: - Nearest-row lookup

    /// Nearest row index to `date` by absolute x-distance in the time domain, via
    /// BINARY SEARCH over the ascending `displayRows` — O(log n) per scrub tick
    /// instead of an O(n) scan. Clamps to the nearest end when the finger is before
    /// the first / after the last row. Returns nil only for an empty set. The
    /// returned index is into `displayRows`; the caller is handed the row's `.id`
    /// (its index in the ORIGINAL `rows`).
    private func nearestDisplayIndex(to date: Date) -> Int? {
        let rs = displayRows
        guard let first = rs.first, let last = rs.last else { return nil }
        if rs.count == 1 { return 0 }

        if date <= first.date { return 0 }
        if date >= last.date { return rs.count - 1 }

        let target = date.timeIntervalSince1970

        // Find the first index whose date is >= target (lower_bound).
        var lo = 0
        var hi = rs.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if rs[mid].date.timeIntervalSince1970 < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let hiIdx = lo
        let loIdx = lo - 1
        let dHi = abs(rs[hiIdx].date.timeIntervalSince1970 - target)
        let dLo = abs(rs[loIdx].date.timeIntervalSince1970 - target)
        return dLo <= dHi ? loIdx : hiIdx
    }

    // MARK: - Row-level downsampling

    /// Decimate `rows` (assumed ascending by date) to at most `target` rows by
    /// running LTTB on ONE representative scalar per row (the MAX across the row's
    /// values) to choose which row INDICES to keep, then keeping those FULL rows for
    /// all series. This is the crux of the multi-series perf contract: by selecting
    /// WHOLE ROWS we guarantee every series keeps the SAME x positions, so a scrub
    /// dot can land on every line at the same date. Decimating each series
    /// independently (the wrong approach) would misalign x across series.
    ///
    /// The representative scalar drives WHICH rows survive, not what is drawn — the
    /// full multi-value row is always kept. Max-of-row is a good representative
    /// because it tends to track the most visually salient envelope (spikes), so the
    /// preserved shape stays faithful for the busiest line; the others ride along on
    /// the same x grid. First/last rows are always kept. O(n), runs only on a data
    /// change (memoized by `syncDisplayRows()`), never per scrub tick.
    static func downsampleRows(_ rows: [MultiScrubRow], target: Int) -> [MultiScrubRow] {
        let n = rows.count
        guard target >= 3, n > target else { return rows }

        // Representative scalar per row: the max across its series values (0 if the
        // row is empty). Precomputed once so the inner LTTB loop is allocation-free.
        var rep = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var m = -Double.greatestFiniteMagnitude
            var any = false
            for v in rows[i].values {
                if v > m { m = v }
                any = true
            }
            rep[i] = any ? m : 0
        }

        var keptIndices: [Int] = []
        keptIndices.reserveCapacity(target)

        // Always keep the first row.
        keptIndices.append(0)

        // `target - 2` interior buckets between the forced first and last rows.
        let bucketSize = Double(n - 2) / Double(target - 2)

        // Index of the previously selected row (anchor of the triangle).
        var a = 0

        for i in 0..<(target - 2) {
            let rangeStart = Int(Double(i) * bucketSize) + 1
            var rangeEnd = Int(Double(i + 1) * bucketSize) + 1
            if rangeEnd > n - 1 { rangeEnd = n - 1 }   // never reach the forced last row

            // Average point of the NEXT bucket — third vertex of the triangle.
            let avgStart = rangeEnd
            var avgEnd = Int(Double(i + 2) * bucketSize) + 1
            if avgEnd > n { avgEnd = n }

            var avgX = 0.0
            var avgY = 0.0
            let avgCount = max(avgEnd - avgStart, 1)
            if avgEnd > avgStart {
                for j in avgStart..<avgEnd {
                    avgX += rows[j].date.timeIntervalSince1970
                    avgY += rep[j]
                }
            } else {
                avgX = rows[n - 1].date.timeIntervalSince1970
                avgY = rep[n - 1]
            }
            avgX /= Double(avgCount)
            avgY /= Double(avgCount)

            let aX = rows[a].date.timeIntervalSince1970
            let aY = rep[a]

            // Pick the candidate row in this bucket with the largest triangle area
            // against (anchor, next-bucket-average) on the representative scalar.
            var maxArea = -1.0
            var chosen = rangeStart
            if rangeStart < rangeEnd {
                for j in rangeStart..<rangeEnd {
                    let pX = rows[j].date.timeIntervalSince1970
                    let pY = rep[j]
                    let area = abs((aX - avgX) * (pY - aY) - (aX - pX) * (avgY - aY))
                    if area > maxArea {
                        maxArea = area
                        chosen = j
                    }
                }
            } else {
                chosen = min(max(rangeStart, 1), n - 2)
            }

            keptIndices.append(chosen)
            a = chosen
        }

        // Always keep the last row.
        keptIndices.append(n - 1)

        // Materialize the kept FULL rows in order. Keep each row's ORIGINAL `id`
        // (its index in the source array) so the caller's `onSelectionChange(id)`
        // maps back into its own `rows`.
        var out: [MultiScrubRow] = []
        out.reserveCapacity(keptIndices.count)
        for idx in keptIndices {
            out.append(rows[idx])
        }
        return out
    }
}

// MARK: - Source identity key

/// A cheap, stable fingerprint of a `[MultiScrubRow]` source array, used to decide
/// whether the decimated `displayRows` must be recomputed. We deliberately do NOT
/// compare every element (that would be O(n) on every body pass during a scrub) —
/// count plus the first/last id, endpoints and value-column count uniquely
/// identifies every distinct row set the callers produce (they rebuild the whole
/// array, with fresh ids, on a range change or reload).
private struct MultiSourceKey: Equatable {
    let count: Int
    let firstID: Int
    let lastID: Int
    let firstDate: Date
    let lastDate: Date
    let columns: Int
    let firstFirstValue: Double
    let lastLastValue: Double

    init(_ rows: [MultiScrubRow]) {
        count = rows.count
        firstID = rows.first?.id ?? -1
        lastID = rows.last?.id ?? -1
        firstDate = rows.first?.date ?? .distantPast
        lastDate = rows.last?.date ?? .distantPast
        columns = rows.first?.values.count ?? 0
        firstFirstValue = rows.first?.values.first ?? 0
        lastLastValue = rows.last?.values.last ?? 0
    }
}

// MARK: - Static curves layer (Equatable — skipped on selection changes)

/// The expensive, unchanging part of the chart: one LineMark series per column, the
/// fitted scales and the x-axis. It is `Equatable` and keyed ONLY on the data and
/// look parameters, so when only the scrub selection changes SwiftUI compares equal
/// and SKIPS re-evaluating this view's body entirely — the hundreds of decimated
/// marks across N series are not rebuilt or re-laid-out per tick. The moving
/// indicator is drawn by a separate sibling layer over the top.
private struct StaticCurves: View, Equatable {
    let rows: [MultiScrubRow]
    let series: [MultiScrubSeries]
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let showsXAxis: Bool
    let xAxisFormat: Date.FormatStyle

    /// Equality drives SwiftUI's diffing: identical data + look ⇒ no rebuild.
    /// `Date.FormatStyle` is not reliably Equatable here, but it only changes when
    /// the caller / data set changes (never during a scrub), and `rows`/`series`/
    /// domains already capture every data change — so comparing those is sufficient
    /// and correct for the scrub fast-path.
    static func == (lhs: StaticCurves, rhs: StaticCurves) -> Bool {
        lhs.rows == rhs.rows
            && lhs.series == rhs.series
            && lhs.xDomain == rhs.xDomain
            && lhs.yDomain == rhs.yDomain
            && lhs.showsXAxis == rhs.showsXAxis
    }

    var body: some View {
        // One LineMark series per column. Each row contributes one point per series,
        // drawn DIRECTLY in the series color via `.foregroundStyle(s.color)` (NOT a
        // label-keyed `chartForegroundStyleScale`), NO area fill, catmull-rom,
        // lineWidth 1.6 — over the decimated rows, at a fraction of the layout cost
        // of the raw set. The `series:` grouping key is the series' POSITIONAL `id`,
        // not its label, so two series that happen to share a label still stroke as
        // N distinct lines (a label-keyed scale would collapse their domain and merge
        // them into one mis-colored line). Because every row carries a value for
        // every series at one shared date, the lines share an identical x grid, which
        // is what lets the indicator dots align.
        Chart {
            ForEach(series) { s in
                ForEach(rows) { row in
                    if row.values.indices.contains(s.id) {
                        LineMark(
                            x: .value("Date", row.date),
                            y: .value("Value", row.values[s.id]),
                            series: .value("Series", s.id)
                        )
                        .foregroundStyle(s.color)
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                }
            }
        }
        // No `chartForegroundStyleScale` / built-in legend: colour is applied per
        // mark above, and the component draws its own optional legend outside the
        // Chart. Hide Charts' built-in legend so nothing is auto-generated.
        .chartLegend(.hidden)
        // Pin the scales explicitly (instead of letting Charts auto-fit) so this
        // layer and the indicator layer map data → pixels identically.
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        // Y axis intentionally hidden (no labels, no gridlines) — keep the chart as
        // minimal as possible.
        .chartYAxis(.hidden)
        .chartXAxis {
            if showsXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.04))
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: xAxisFormat)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

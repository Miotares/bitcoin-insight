//
//  ScrubbableLineChart.swift
//  BitcoinWidgets
//
//  A reusable area+line time-series chart with finger-scrubbing.
//
//  Designed to be shared by every history chart in the app (hashrate, price,
//  mempool, lightning, fees, difficulty). It is placement-agnostic — it draws
//  ONLY the chart plus the scrubbing interaction; callers own the surrounding
//  card, caption header, range picker and data fetching.
//
//  Scrubbing strategy — why `.chartXSelection`, not a raw DragGesture
//  ------------------------------------------------------------------
//  The chart lives inside a vertical ScrollView (NavigationStack). We use
//  SwiftUI Charts' native `.chartXSelection(value:)` (iOS 17) rather than a raw
//  `.chartOverlay` + `DragGesture`. A raw drag gesture captures the touch the
//  moment it begins and fights the scroll view; `.chartXSelection` installs a
//  lighter selection gesture that, in practice, coexists with an enclosing
//  ScrollView under SwiftUI's DEFAULT gesture arbitration — the ScrollView's own
//  pan generally wins a mostly-vertical drag (its minimum-distance threshold),
//  while a horizontal drag drives the selection.
//
//  IMPORTANT: this is DEFAULT arbitration, NOT a documented directional hand-off.
//  Apple's Charts API does not promise that a vertical drag started on the chart
//  is handed to the scroll view, so we do not claim a hard "cannot hijack scroll"
//  guarantee. As a belt-and-braces safeguard the component reports its scrubbing
//  state via `onScrubbingChange(_:)`, so a caller MAY disable the surrounding
//  ScrollView for the duration of a scrub (see HashrateChart, which gates its
//  enclosing scroll). Callers that don't wire it up still get the default
//  behaviour, which is acceptable in practice but unverified per-OS-version.
//
//  The selection binds a `Date?` in the data domain, so the nearest-sample
//  lookup is a clean x-distance search and the selection clears automatically on
//  finger-up (the binding goes back to nil).
//
//  While the finger is down:
//    • a vertical RuleMark marks the touched x,
//    • the nearest data point is enlarged in the accent color,
//    • the caller is told which point is selected (via `onSelectionChange`) so it
//      can swap a live readout into its header (never clips), and OPTIONALLY an
//      edge-safe in-chart annotation is shown (`showsInlineReadout`).
//  A selection haptic fires ONLY when the selected data-point INDEX changes, and
//  the selection clears when the finger lifts.
//
//  Performance — why this scrolls/scrubs at 60fps with thousands of samples
//  ------------------------------------------------------------------------
//  Production series reach ~2185 points (3Y mempool). The old implementation drew
//  an AreaMark + LineMark PER point and, on EVERY scrub tick, did an O(n) linear
//  nearest scan and rebuilt the ENTIRE Chart (all ~2000 marks) plus the indicator.
//  That is the lag. Four changes fix it without touching the look or feel:
//
//    1. DOWNSAMPLE-FIRST. The series is decimated once (Largest-Triangle-Three-
//       Buckets, see `ChartDownsampling`) to a screen-appropriate target whenever
//       the data identity or the target changes — never per scrub tick. A ~350pt
//       chart cannot resolve thousands of points; LTTB preserves the visual shape
//       (peaks/troughs/slopes) so the catmull-rom line looks identical. The SAME
//       decimated array (`displayPoints`) drives BOTH the marks AND the nearest
//       lookup, so the dot snaps to a real rendered sample on the drawn line.
//
//    2. BINARY-SEARCH nearest index. `displayPoints` is ascending by date, so the
//       lookup is O(log n) per tick instead of O(n).
//
//    3. DECOUPLED LAYERS. The heavy static line+area is an Equatable sub-view
//       (`StaticCurve`) keyed ONLY on the data + look — when the selection changes
//       SwiftUI sees identical inputs and SKIPS rebuilding/redrawing the curve.
//       The moving RuleMark + dot live in a SEPARATE lightweight Chart overlaid in
//       a ZStack. Both layers are pinned to the SAME explicit x- and y-domain, so
//       they register pixel-for-pixel and the indicator lands exactly on the line.
//       A scrub tick now rebuilds only the tiny 2-mark indicator, not the curve.
//
//    4. MEMOIZED Y-EXTENT. The fitted y-domain and the area fill floor are the
//       min/max of the decimated values. Those are computed ONCE per data change
//       (a single pass inside `syncDisplayPoints()`) and stored as scalars, so a
//       scrub tick reads cached `Double`s instead of re-running
//       `displayPoints.map(\.value).min()/.max()` (which allocated a transient
//       `[Double]` every body evaluation). The per-tick data-sized cost is then
//       just the O(log n) binary search.
//
//  iOS 17.6 compatible — `.chartXSelection`, RuleMark, PointMark, `.chartXScale`,
//  `.chartYScale`, `.chartPlotStyle`, EquatableView and
//  `.annotation(position:overflowResolution:)` are all iOS 17 API. No iOS 18+
//  Charts additions are used.
//

import SwiftUI
import Charts

/// One plottable sample: an x position in time and a y value.
///
/// `id` is the point's index in the ordered series, which makes index-change
/// detection (for the scrub haptic) trivial and stable. Using the post-sort
/// enumerated offset as the id also keeps `ForEach` identity unique even if the
/// source data contains duplicate timestamps.
struct ScrubPoint: Identifiable, Equatable {
    let id: Int
    let date: Date
    let value: Double
}

struct ScrubbableLineChart: View {
    /// Ordered (ascending by date) samples to plot. May be empty or single.
    let points: [ScrubPoint]
    /// Accent used for the line, fill gradient and the highlighted dot.
    let accent: Color
    /// Formats a y value for the readout (e.g. `Formatters.formatHashrate`).
    let valueFormat: (Double) -> String
    /// Date style for the x-axis tick labels.
    let xAxisFormat: Date.FormatStyle
    /// Date style for the selected-point readout.
    let readoutDateFormat: Date.FormatStyle
    /// When true, the chart draws its own edge-safe readout bubble above the
    /// RuleMark. Leave false when the caller renders the readout in a header
    /// (the hashrate chart does) to avoid showing it twice.
    let showsInlineReadout: Bool
    /// When false the x-axis is omitted entirely. Use this when the caller
    /// overlaps a control (e.g. the timeframe switch) over the chart's bottom
    /// and wants the fill to bleed behind it without an axis in the way.
    let showsXAxis: Bool
    /// Called whenever the selected point changes (including to `nil` on lift).
    /// The caller uses this to drive a live readout in its own header.
    let onSelectionChange: (ScrubPoint?) -> Void
    /// Called when scrubbing starts (`true`) and ends (`false`). A caller MAY use
    /// this to disable an enclosing ScrollView for the duration of the scrub so a
    /// drag can never get torn between scroll and selection. Optional.
    let onScrubbingChange: (Bool) -> Void

    init(
        points: [ScrubPoint],
        accent: Color = .bitcoinOrange,
        xAxisFormat: Date.FormatStyle,
        readoutDateFormat: Date.FormatStyle = Date.FormatStyle.dateTime.year().month(.abbreviated).day(),
        showsInlineReadout: Bool = false,
        showsXAxis: Bool = true,
        renderTarget: Int = 500,
        valueFormat: @escaping (Double) -> String,
        onSelectionChange: @escaping (ScrubPoint?) -> Void = { _ in },
        onScrubbingChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.points = points
        self.accent = accent
        self.xAxisFormat = xAxisFormat
        self.readoutDateFormat = readoutDateFormat
        self.showsInlineReadout = showsInlineReadout
        self.showsXAxis = showsXAxis
        self.renderTarget = renderTarget
        self.valueFormat = valueFormat
        self.onSelectionChange = onSelectionChange
        self.onScrubbingChange = onScrubbingChange
    }

    /// Target sample count for rendering + lookup. A ~350pt-wide chart at ~3×
    /// scale resolves well under this many distinct x positions, so ~500 is a
    /// generous default that keeps the curve visually lossless while capping the
    /// per-frame mark count. Callers may raise it (e.g. the price "All" range) to
    /// render a denser, uniform line. Series at or below this are used as-is.
    let renderTarget: Int

    /// The raw x location reported under the finger, in the data (Date) domain.
    /// Driven and cleared by Charts via `.chartXSelection`.
    @State private var selectedDate: Date?
    /// Index of the data point currently snapped-to (nil when not scrubbing).
    /// Indexes into `displayPoints`. Tracked separately so the haptic fires ONLY
    /// on an index change.
    @State private var selectedIndex: Int?

    /// Memoized decimated series used for BOTH rendering and the nearest lookup.
    /// Recomputed by `syncDisplayPoints()` only when the source data changes
    /// (keyed on `displaySourceKey`), NOT on every body evaluation — so a scrub
    /// tick never re-runs LTTB.
    @State private var displayPoints: [ScrubPoint] = []
    /// Identity of the data that `displayPoints` was computed from. Cheap to
    /// compare (count + first/last id + endpoints) and stable across the unchanged
    /// re-renders that a scrub produces.
    @State private var displaySourceKey: SourceKey?

    /// Memoized y-extent + fill floor of `displayPoints`, computed ONCE per data
    /// change in `syncDisplayPoints()` (single pass), never per scrub tick. The
    /// `yDomain` and `fillFloor` computed properties read these stored scalars
    /// instead of re-running `displayPoints.map(\.value).min()/.max()` on every
    /// body evaluation — so a scrub tick's only data-sized work is the O(log n)
    /// binary search, with no transient `[Double]` allocations.
    ///
    /// `displayValueLo` / `displayValueHi` are the raw min / max of the decimated
    /// values; `displayFillFloor` mirrors `displayValueLo` (the area fill descends
    /// to the data minimum). Defaults describe an empty series (handled by the
    /// `hasMemoizedExtent` guard in the computed properties).
    @State private var displayValueLo: Double = 0
    @State private var displayValueHi: Double = 0
    @State private var displayFillFloor: Double = 0
    /// False until `syncDisplayPoints()` has populated the extent from a non-empty
    /// series, so `yDomain`/`fillFloor` fall back to their empty-series defaults
    /// before the first sync (matching the old `values.min()` == nil behaviour).
    @State private var hasMemoizedExtent: Bool = false

    /// Scrubbing is only meaningful with at least two samples. With 0 or 1
    /// points the chart is purely static — we never attach a live selection
    /// binding (see `body`), so there is no path that could index a degenerate
    /// series or fire a phantom haptic on a tap.
    private var isScrubbable: Bool { displayPoints.count >= 2 }

    /// Top headroom (in points) reserved inside the plot so the optional inline
    /// readout bubble — drawn at `position: .top` of the RuleMark — has room to
    /// sit above a high-value point without clipping the chart's top edge.
    /// Only meaningful when `showsInlineReadout` is true.
    private var readoutHeadroom: CGFloat { showsInlineReadout ? 44 : 0 }

    /// The point under the finger, resolved from `selectedIndex`. Index-checked,
    /// so there is no force-unwrap and no out-of-bounds even if `displayPoints`
    /// shrinks. Resolved against the SAME array the curve is drawn from, so the
    /// dot always sits on the rendered line.
    private var selectedPoint: ScrubPoint? {
        guard let i = selectedIndex, displayPoints.indices.contains(i) else { return nil }
        return displayPoints[i]
    }

    // MARK: - Domains (shared by both layers so they register pixel-perfect)

    /// X domain spanning the (decimated) series. Pinned explicitly on BOTH the
    /// static curve layer and the indicator layer so the two stacked charts map
    /// time → x identically and the RuleMark/dot land exactly on the curve.
    private var xDomain: ClosedRange<Date> {
        guard let first = displayPoints.first?.date,
              let last = displayPoints.last?.date else {
            let now = Date()
            return now...now.addingTimeInterval(1)
        }
        guard first < last else { return first...first.addingTimeInterval(1) }
        return first...last
    }

    /// Y range fitted to the data (with a little headroom) instead of anchoring
    /// at zero, so the line uses the full height and day-to-day variation is not
    /// visually squeezed. The AreaMark fill simply starts at this fitted lower
    /// bound (the bottom of the plot) rather than at 0, so the filled gradient
    /// still reads cleanly. Derived from the MEMOIZED `displayValueLo/Hi` (computed
    /// once per data change in `syncDisplayPoints()`), so this is pure scalar math
    /// with NO per-tick array map/min/max and no transient `[Double]` allocation.
    /// Shared by both layers.
    private var yDomain: ClosedRange<Double> {
        guard hasMemoizedExtent else { return 0...1 }
        let lo = displayValueLo
        let hi = displayValueHi
        guard lo != hi else {
            // Flat series — pad symmetrically so it doesn't collapse to a line.
            let pad = lo == 0 ? 1 : abs(lo) * 0.1
            return (lo - pad)...(hi + pad)
        }
        let range = hi - lo
        // Small headroom on each side. The fill fades to a flush baseline AT the
        // data minimum, so a large bottom margin is no longer needed for the
        // dissolve — keeping it small lets the line use more of the height while
        // leaving a touch of space below the flush fade.
        return (lo - range * 0.12)...(hi + range * 0.08)
    }

    /// The flush baseline the area fill descends to: the data minimum, so the
    /// fade bottom is one flat horizontal level across the whole width. Reads the
    /// MEMOIZED scalar (computed once per data change), NOT a per-tick
    /// `displayPoints.map(\.value).min()`.
    private var fillFloor: Double {
        hasMemoizedExtent ? displayFillFloor : 0
    }

    var body: some View {
        ZStack {
            // LAYER 1 — the heavy static curve (area + line). Equatable + keyed
            // ONLY on the data and look, so a selection change (which leaves all
            // of these inputs identical) makes SwiftUI SKIP rebuilding it. This is
            // what keeps a scrub tick from re-laying-out hundreds of marks.
            StaticCurve(
                points: displayPoints,
                accent: accent,
                fillFloor: fillFloor,
                xDomain: xDomain,
                yDomain: yDomain,
                topHeadroom: readoutHeadroom,
                showsXAxis: showsXAxis,
                xAxisFormat: xAxisFormat
            )
            .equatable()

            // LAYER 2 — the lightweight moving indicator (RuleMark + dot + optional
            // readout). Only 2 marks; rebuilding this per tick is cheap. Pinned to
            // the SAME x/y domain and the SAME plot headroom as the curve so it
            // overlays pixel-for-pixel. Transparent everything else (no axes, no
            // fill) so only the curve shows through. The native `.chartXSelection`
            // is installed on THIS layer (a real Chart with plot context) — Charts'
            // selection requires a Chart, not a ZStack — and this layer sits on top
            // so it owns the touch. The static curve below is non-interactive.
            indicatorLayer
        }
        // Map the raw x location to the nearest sample, fire the per-index haptic,
        // and notify the caller.
        .onChange(of: selectedDate) { _, newDate in
            handleSelectionChange(to: newDate)
        }
        // Keep `displayPoints` in sync with the source data. Runs on first
        // appearance and whenever the source changes; the guard inside makes the
        // repeated unchanged re-renders of a scrub a no-op (no LTTB, no churn).
        .onAppear { syncDisplayPoints() }
        .onChange(of: SourceKey(points)) { _, _ in
            syncDisplayPoints()
        }
    }

    // MARK: - Indicator layer (lightweight, rebuilt per scrub tick)

    @ViewBuilder
    private var indicatorLayer: some View {
        Chart {
            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .annotation(
                        position: .top,
                        spacing: 4,
                        // iOS 17 overflow resolution. x:.fit keeps the bubble
                        // inside the chart's x-bounds (no left/right clip).
                        // y:.fit keeps it inside the PLOT vertically so a
                        // high-value point near the top does not clip the bubble
                        // off the top edge — combined with the reserved top
                        // headroom below, the inline readout is fully edge-safe.
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .plot))
                    ) {
                        if showsInlineReadout {
                            readout(for: selected)
                        }
                    }

                PointMark(
                    x: .value("Selected", selected.date),
                    y: .value("Value", selected.value)
                )
                .foregroundStyle(accent)
                .symbolSize(160)
                // A ring so the enlarged dot reads on top of the line stroke.
                .annotation(position: .overlay, spacing: 0) {
                    Circle()
                        .fill(accent)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
            }
        }
        // Pin to EXACTLY the same domains + plot headroom as the static curve so
        // the indicator maps onto the line pixel-for-pixel.
        .chartPlotStyle { plot in
            plot.padding(.top, readoutHeadroom)
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        // CRITICAL for alignment: when the curve layer shows an x-axis, its labels
        // shrink its PLOT area upward. If this overlay simply hid its x-axis it
        // would keep a TALLER plot, so `position(forY:)` would map differently and
        // the dot/rule would sit off the line and bleed into the axis band. So we
        // mirror the curve's x-axis cadence here but render every mark INVISIBLE
        // (clear gridline + an empty label in the SAME caption2 font), reserving an
        // identical bottom band so both plot rects coincide pixel-for-pixel. When
        // the caller hides the x-axis, neither layer reserves the band — still
        // aligned.
        .chartXAxis {
            if showsXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    // No AxisGridLine → nothing drawn, but the label below still
                    // reserves the same vertical space as the curve's axis.
                    AxisValueLabel {
                        // Empty text in the matching font reserves identical height
                        // without painting anything.
                        Text(" ")
                            .font(.caption2)
                            .foregroundStyle(.clear)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        // Native selection lives HERE — on a real Chart with plot context, not on
        // the enclosing ZStack (which has none). This layer is on top of the
        // static curve, so it owns the scrub touch; the curve below is inert.
        // Only attached when the series is actually scrubbable — for a 0/1-point
        // series the binding is a constant nil, so a tap cannot drive
        // `selectedDate`, cannot reach `handleSelectionChange`, and cannot fire a
        // phantom haptic or report a selection on a degenerate chart.
        .chartXSelection(value: isScrubbable ? $selectedDate : .constant(nil))
    }

    // MARK: - Display-points memoization

    /// Recompute `displayPoints` from the current source `points`, but ONLY when
    /// the source actually changed. Called from `.onAppear` and the source-key
    /// `onChange`; the key comparison makes the many identical re-renders during a
    /// scrub a cheap no-op (LTTB never runs on a tick).
    private func syncDisplayPoints() {
        let key = SourceKey(points)
        guard key != displaySourceKey else { return }
        displaySourceKey = key
        let decimated = ChartDownsampling.lttb(points, target: renderTarget)
        displayPoints = decimated
        // Compute the y-extent + fill floor ONCE here (single pass over the
        // decimated values) and memoize it, so `yDomain`/`fillFloor` never re-scan
        // the array on a scrub tick. This is the only place the extent is derived.
        if let first = decimated.first?.value {
            var lo = first
            var hi = first
            for p in decimated {
                let v = p.value
                if v < lo { lo = v }
                if v > hi { hi = v }
            }
            displayValueLo = lo
            displayValueHi = hi
            displayFillFloor = lo
            hasMemoizedExtent = true
        } else {
            // Empty series — fall back to the empty-series defaults in the readers.
            displayValueLo = 0
            displayValueHi = 0
            displayFillFloor = 0
            hasMemoizedExtent = false
        }
        // The data set changed — any prior selection refers to a stale array.
        clearSelection()
    }

    // MARK: - Selection plumbing

    /// Resolves the raw selected x into a snapped sample index, fires the haptic
    /// only on an index change, and notifies the caller. A nil `date` (finger
    /// lifted) clears the selection. This is only ever reached when the series is
    /// scrubbable (the binding is a constant nil otherwise), but it still guards
    /// the degenerate cases defensively. Resolves against `displayPoints` so the
    /// reported sample is exactly the one drawn under the finger.
    private func handleSelectionChange(to date: Date?) {
        guard let date, isScrubbable else {
            clearSelection()
            return
        }
        guard let index = nearestIndex(to: date) else {
            clearSelection()
            return
        }
        if selectedIndex == nil {
            // First snap of this scrub — tell the caller scrubbing began.
            onScrubbingChange(true)
        }
        if index != selectedIndex {
            selectedIndex = index
            Haptics.selection()                 // tick ONLY on an index change
            onSelectionChange(displayPoints[index])
        }
    }

    /// Clears the selection (finger lift / data swap) and notifies the caller.
    /// Also resets the bound `selectedDate` so no stale domain value lingers,
    /// and signals the end of scrubbing.
    private func clearSelection() {
        if selectedDate != nil { selectedDate = nil }
        guard selectedIndex != nil else { return }
        selectedIndex = nil
        onSelectionChange(nil)
        onScrubbingChange(false)
    }

    // MARK: - Nearest-point lookup

    /// Nearest sample index to `date` by absolute x-distance in the time domain,
    /// via BINARY SEARCH over the ascending `displayPoints` — O(log n) per scrub
    /// tick instead of the old O(n) scan. Clamps to the nearest end when the
    /// finger is before the first / after the last point. Returns nil only for an
    /// empty series.
    private func nearestIndex(to date: Date) -> Int? {
        let pts = displayPoints
        guard let first = pts.first, let last = pts.last else { return nil }
        if pts.count == 1 { return 0 }

        // Series is ascending by date — clamp outside the domain.
        if date <= first.date { return 0 }
        if date >= last.date { return pts.count - 1 }

        let target = date.timeIntervalSince1970

        // Find the first index whose date is >= target (lower_bound).
        var lo = 0
        var hi = pts.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if pts[mid].date.timeIntervalSince1970 < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // `lo` is the first sample at/after target. The nearest is either it or
        // its predecessor — compare the two straddling samples.
        let hiIdx = lo
        let loIdx = lo - 1
        let dHi = abs(pts[hiIdx].date.timeIntervalSince1970 - target)
        let dLo = abs(pts[loIdx].date.timeIntervalSince1970 - target)
        return dLo <= dHi ? loIdx : hiIdx
    }

    // MARK: - Readout bubble (optional, edge-safe)

    @ViewBuilder
    private func readout(for point: ScrubPoint) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(valueFormat(point.value))
                .font(.footnote.weight(.bold))
                .foregroundStyle(.primary)
            Text(point.date, format: readoutDateFormat)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        // Material first (back), then the subtle fill tint on top, so the bubble
        // reads as a tinted glass chip rather than the fill being hidden behind.
        .background(.ultraThinMaterial)
        .background(Theme.Surface.fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
    }
}

// MARK: - Source identity key

/// A cheap, stable fingerprint of a `[ScrubPoint]` source array, used to decide
/// whether the decimated `displayPoints` must be recomputed. We deliberately do
/// NOT compare every element (that would be O(n) on every body pass during a
/// scrub) — count plus the first/last id and endpoint values uniquely identifies
/// every distinct series the callers produce (they rebuild the whole array, with
/// fresh ids, on a range change or reload).
private struct SourceKey: Equatable {
    let count: Int
    let firstID: Int
    let lastID: Int
    let firstDate: Date
    let lastDate: Date
    let firstValue: Double
    let lastValue: Double

    init(_ points: [ScrubPoint]) {
        count = points.count
        firstID = points.first?.id ?? -1
        lastID = points.last?.id ?? -1
        firstDate = points.first?.date ?? .distantPast
        lastDate = points.last?.date ?? .distantPast
        firstValue = points.first?.value ?? 0
        lastValue = points.last?.value ?? 0
    }
}

// MARK: - Static curve layer (Equatable — skipped on selection changes)

/// The expensive, unchanging part of the chart: the filled area + the line, the
/// fitted scales, the plot headroom and the x-axis. It is `Equatable` and keyed
/// ONLY on the data and look parameters, so when only the scrub selection changes
/// SwiftUI compares equal and SKIPS re-evaluating this view's body entirely — the
/// hundreds of decimated marks are not rebuilt or re-laid-out per tick. The moving
/// indicator is drawn by a separate sibling layer over the top.
private struct StaticCurve: View, Equatable {
    let points: [ScrubPoint]
    let accent: Color
    let fillFloor: Double
    let xDomain: ClosedRange<Date>
    let yDomain: ClosedRange<Double>
    let topHeadroom: CGFloat
    let showsXAxis: Bool
    let xAxisFormat: Date.FormatStyle

    /// Equality drives SwiftUI's diffing: identical data + look ⇒ no rebuild.
    /// `Date.FormatStyle` and `Color` are not Equatable in a way we can rely on
    /// here, but they only change when the data set / caller changes (never during
    /// a scrub), and `points`/domains already capture every data change — so
    /// comparing those is sufficient and correct for the scrub fast-path.
    static func == (lhs: StaticCurve, rhs: StaticCurve) -> Bool {
        lhs.points == rhs.points
            && lhs.fillFloor == rhs.fillFloor
            && lhs.xDomain == rhs.xDomain
            && lhs.yDomain == rhs.yDomain
            && lhs.topHeadroom == rhs.topHeadroom
            && lhs.showsXAxis == rhs.showsXAxis
    }

    var body: some View {
        // The fill spans from the line down to ONE flat baseline (the data
        // minimum) and fades to transparent toward it. Because that baseline is
        // the same level for every x, the fade bottom is flush / horizontal — it
        // does NOT rise and fall with the line — while the gradient still gives
        // the soft line-hugging dissolve. The data-fitted y-scale keeps the
        // baseline a constant fraction of the plot height on every timeframe, so
        // the dissolve looks the same on 1M as on 3Y.
        //
        // One AreaMark + one LineMark per point (driven by the decimated array)
        // render the SAME continuous catmull-rom curve as before, but over far
        // fewer points, at a fraction of the layout cost.
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Floor", fillFloor),
                    yEnd: .value("Value", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        // Fades from the line down to transparent at the flush
                        // baseline, so the fill dissolves to nothing at one common
                        // level across the whole width.
                        colors: [accent.opacity(0.26), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value)
                )
                .foregroundStyle(accent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
        }
        // Reserve top headroom inside the plot so the inline readout bubble has
        // somewhere to sit above a high-value point without clipping. Zero when
        // no inline readout is shown, so the default (header-readout) caller is
        // visually unchanged. Mirrors the indicator layer's headroom so the two
        // plots align.
        .chartPlotStyle { plot in
            plot.padding(.top, topHeadroom)
        }
        // Pin the scales explicitly (instead of letting Charts auto-fit) so this
        // layer and the indicator layer map data → pixels identically.
        .chartXScale(domain: xDomain)
        .chartYScale(domain: yDomain)
        // Y axis intentionally hidden (no labels, no gridlines) — keep the chart
        // as minimal as possible. `valueFormat` is still used for the readout.
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

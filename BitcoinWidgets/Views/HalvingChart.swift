//
//  HalvingChart.swift
//  BitcoinWidgets
//
//  Created by User on 2025-12-15.
//

import SwiftUI
import Charts

struct HalvingChart: View {
    let currentBlockHeight: Int

    /// Bound to the enclosing screen so it can `.scrollDisabled(_:)` its ScrollView
    /// while the user is scrubbing this chart, so a drag started on the chart is
    /// never torn between scrolling and scrubbing. Optional — defaults to a
    /// throwaway binding so the chart still works when embedded without one.
    @Binding var isScrubbing: Bool

    init(currentBlockHeight: Int, isScrubbing: Binding<Bool> = .constant(false)) {
        self.currentBlockHeight = currentBlockHeight
        self._isScrubbing = isScrubbing
    }

    // Halving interval is 210,000 blocks
    private let halvingInterval = 210_000

    /// Block height currently under the finger (data domain). Driven and cleared by
    /// Charts via `.chartXSelection`; nil when not scrubbing.
    @State private var selectedHeight: Int?
    /// Halving era of the last selection, so the scrub haptic ticks once per halving
    /// crossed (a meaningful, sparse cue) rather than on every pixel of movement.
    @State private var lastEra: Int?
    /// The current scrub readout, shown in the card header (NOT an in-chart bubble) to
    /// match the time-series charts. Internal @State so per-tick updates re-render only
    /// this chart, never the host screen — and the plot layout is never touched.
    @State private var sample: BlockScrubSample?

    private struct SupplyPoint: Identifiable {
        let id: Int
        let blockHeight: Int
        let supply: Double
    }

    private var halvingHeights: [Int] {
        // Generate significant halving heights for the axis and vertical lines (cover full range)
        (1...34).map { $0 * halvingInterval }
    }

    /// The emission curve, sampled at 3 points per 210k era (so era boundaries land
    /// exactly) from the closed-form `supply(at:)`. That is dense enough to keep the
    /// catmull-rom line visually smooth AND make the scrub dot — placed at the exact
    /// computed supply for the touched height — sit flush on the rendered line, while
    /// staying a modest mark count (~110) so the single Chart rebuilds cheaply on each
    /// scrub tick. The plot-space gradient on the line is unaffected by the point
    /// count, so the look is unchanged from the old sparse version.
    private static let supplyPoints: [SupplyPoint] = {
        var points: [SupplyPoint] = []
        let step = 70_000
        var height = 0
        var index = 0
        while height <= BlockChartScrub.domainMax {
            points.append(SupplyPoint(id: index, blockHeight: height, supply: HalvingChart.supply(at: height)))
            height += step
            index += 1
        }
        if points.last?.blockHeight != BlockChartScrub.domainMax {
            points.append(SupplyPoint(id: index, blockHeight: BlockChartScrub.domainMax, supply: HalvingChart.supply(at: BlockChartScrub.domainMax)))
        }
        return points
    }()

    /// Block height under the finger, clamped to the drawn X domain. nil when idle.
    private var clampedSelectedHeight: Int? {
        guard let h = selectedHeight else { return nil }
        return min(max(h, 0), BlockChartScrub.domainMax)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BlockScrubHeader(title: "Emission Schedule", sample: sample)
            chartCanvas
        }
    }

    private var chartCanvas: some View {
        Chart {
            // Vertical Lines for Halvings
            ForEach(halvingHeights, id: \.self) { height in
                // Show line only for every 4th halving to prevent clutter
                if height % (halvingInterval * 4) == 0 {
                    RuleMark(x: .value("Halving", height))
                        .foregroundStyle(.white.opacity(0.1))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }

            // Emission Curve
            ForEach(Self.supplyPoints) { point in
                LineMark(
                    x: .value("Block Height", point.blockHeight),
                    y: .value("Total Supply", point.supply)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange.opacity(0), .orange],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            // Current Position — the pulsing "Now" dot. ALWAYS drawn (even while
            // scrubbing) so the reference point for "where we are today" is never lost.
            PointMark(
                x: .value("Current", currentBlockHeight),
                y: .value("Supply", Self.supply(at: currentBlockHeight))
            )
            .symbol {
                PulsingDotView()
            }

            // Scrub cursor — a rule + a flush dot at the touched height (the value
            // readout is surfaced in the header, not in-chart). Continuous: the value
            // is computed exactly for the height under the finger, so scrubbing left
            // reveals past supply and right the projected future. Drawn last, on top.
            if let h = clampedSelectedHeight {
                let supplyHere = Self.supply(at: h)

                RuleMark(x: .value("Selected", h))
                    .foregroundStyle(Color.bitcoinOrange.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))

                PointMark(
                    x: .value("Selected", h),
                    y: .value("Supply", supplyHere)
                )
                .foregroundStyle(Color.bitcoinOrange)
                .symbolSize(160)
                .annotation(position: .overlay, spacing: 0) {
                    Circle()
                        .fill(Color.bitcoinOrange)
                        .frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                }
            }
        }
        .chartXSelection(value: $selectedHeight)
        .onChange(of: selectedHeight) { _, newValue in
            updateScrub(to: newValue)
        }
        .chartYScale(domain: 0...21_000_000)
        .chartXAxis {
            let values = [0, 2_000_000, 4_000_000, 6_000_000, 7_140_000] // Steps: 0, 2M, 4M, 6M, Infinity
            AxisMarks(values: values) { value in
                if let intValue = value.as(Int.self) {
                    AxisTick(stroke: StrokeStyle(lineWidth: 0))
                    
                    AxisValueLabel(centered: false) {
                        if intValue >= 7_000_000 {
                            Text("∞")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(intValue == 0 ? "0" : "\(intValue / 1_000_000)M")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartXScale(domain: 0...7_600_000) // Extend slightly for padding
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.05))
                
                if let doubleValue = value.as(Double.self) {
                     AxisValueLabel {
                        Text("\(Int(doubleValue / 1_000_000))M")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.7))
                     }
                }
            }
        }
        .frame(height: 200)
    }

    /// Closed-form circulating supply at a block height: sum each era's full reward
    /// until the current era, then the partial blocks in it. Used for the rendered
    /// curve, the "Now" dot and the scrub dot, so all three agree exactly.
    static func supply(at height: Int) -> Double {
        var supply: Double = 0
        var reward: Double = 50.0
        var remainingHeight = max(0, height)

        while remainingHeight > 0 {
            let blocksInThisEra = min(remainingHeight, 210_000)
            supply += Double(blocksInThisEra) * reward
            remainingHeight -= blocksInThisEra
            reward /= 2
            if reward < 0.00000001 { break } // dust
        }

        return supply
    }

    /// Reacts to a new `.chartXSelection` value: drives the `isScrubbing` gate and
    /// fires a selection haptic once per halving era crossed (including the first
    /// touch). A nil value (finger lifted) ends the scrub and resets the era tracker.
    private func updateScrub(to newValue: Int?) {
        guard let raw = newValue else {
            sample = nil
            if isScrubbing { isScrubbing = false }
            lastEra = nil
            return
        }
        let clamped = min(max(raw, 0), BlockChartScrub.domainMax)
        let era = clamped / BlockChartScrub.halvingInterval
        if era != lastEra {
            Haptics.selection()
            lastEra = era
        }
        sample = BlockScrubSample(
            value: Formatters.formatAmount(Int(Self.supply(at: clamped).rounded())) + " BTC",
            context: BlockChartScrub.context(forHeight: clamped, currentHeight: currentBlockHeight)
        )
        if !isScrubbing { isScrubbing = true }
    }
    
    // Helper not needed for automatic axis but keeping if useful later
    private func formatHalvingLabel(_ height: Int) -> String {
        let kValue = height / 1000
        return "\(kValue)k"
    }
}

private struct PulsingDotView: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Signal Ring (expanding and fading)
            Circle()
                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                .frame(width: 10, height: 10) // Start size matches core
                .scaleEffect(isPulsing ? 3.0 : 1.0) // Expands outwards
                .opacity(isPulsing ? 0.0 : 1.0) // Fades to invisible
            
            // Core dot (stable)
            Circle()
                .fill(.orange)
                .frame(width: 10, height: 10)
                .shadow(color: .orange, radius: 4, x: 0, y: 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

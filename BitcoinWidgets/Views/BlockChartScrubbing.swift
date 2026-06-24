//
//  BlockChartScrubbing.swift
//  BitcoinWidgets
//
//  Shared finger-scrubbing helpers for the two block-height charts — the emission
//  curve (`HalvingChart`) and the block-reward schedule (`HalvingRewardChart`).
//
//  Both differ from the time-series charts (`ScrubbableLineChart`): their X axis is
//  block HEIGHT (Int), not a Date, and their Y value is a deterministic function of
//  height, so scrubbing computes the EXACT value at the touched height (smooth,
//  continuous) instead of snapping to a sampled point. Each chart keeps its pulsing
//  "Now" dot at the current tip; the scrub cursor (rule + dot) is an additional,
//  transient in-chart overlay that never replaces it.
//
//  Like the time-series charts, the scrub READOUT is surfaced in the card header
//  (the section title swaps to the live value), NOT in an in-chart bubble — so the
//  plot layout is never altered. Scrubbing uses Charts' native `.chartXSelection`
//  (Int domain); each chart exposes an `isScrubbing` binding so the enclosing detail
//  screen can `.scrollDisabled(_:)` for the duration of a drag.
//

import SwiftUI

/// Constants + projections shared by the block-height charts.
enum BlockChartScrub {
    /// Right edge of the X domain both charts draw (matches their `.chartXScale`).
    /// ~7.6M blocks reaches past the final halving, where emission ends.
    static let domainMax = 7_600_000

    /// Bitcoin's halving interval, in blocks.
    static let halvingInterval = 210_000

    /// Approximate calendar date a block height is / was reached, projected from the
    /// current tip at the 10-minute target spacing. Works in BOTH directions: a
    /// height below the tip yields a past date (scrub left → history), a height above
    /// yields a future date (scrub right → the future). It is an estimate — real
    /// block times vary — which the readout signals with a "≈".
    static func estimatedDate(forHeight height: Int, currentHeight: Int) -> Date {
        Date().addingTimeInterval(Double(height - currentHeight) * 600)
    }

    /// The header's secondary context line for a scrubbed height: the block number
    /// and its projected month/year — "Block 1.234.567 · ≈ Mai 2150".
    static func context(forHeight height: Int, currentHeight: Int) -> String {
        let date = estimatedDate(forHeight: height, currentHeight: currentHeight)
        return "Block \(Formatters.formatAmount(height)) · ≈ \(date.formatted(.dateTime.month(.abbreviated).year()))"
    }
}

/// A scrubbed sample a block-height chart shows in its header while the finger is
/// down. `value` is the formatted metric (circulating supply or block reward);
/// `context` is the block number + projected date.
struct BlockScrubSample: Equatable {
    let value: String
    let context: String
}

/// Section header for a block-height chart card: shows `title` when idle and swaps to
/// the live scrubbed sample while the user drags. A fixed-height, single-line
/// crossfade — only opacity animates — so swapping the title for the readout never
/// reflows the card. Mirrors the header pattern in HashrateChart / MempoolChart.
struct BlockScrubHeader: View {
    let title: String
    let sample: BlockScrubSample?

    var body: some View {
        ZStack(alignment: .leading) {
            // Idle — the section title (unchanged style from before).
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
                .opacity(sample == nil ? 1 : 0)

            // Scrubbing — the touched value + its context, on one line so it occupies
            // the same height as the title.
            if let sample {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(sample.value)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(sample.context)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.18), value: sample)
    }
}

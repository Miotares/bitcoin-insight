//
//  InsightWidgets.swift
//  InsightWidgets
//
//  Widget bundle members + shared support (formatting, timeline provider).
//  Views live in WidgetViews.swift.
//

import WidgetKit
import SwiftUI

// MARK: - Brand

extension Color {
    static let btcOrange = Color(red: 247 / 255, green: 147 / 255, blue: 26 / 255)
}

// MARK: - Formatting helpers

enum WidgetFormat {
    static func price(_ value: Double, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
    }

    /// "BTC/USD $150,000"
    static func pair(_ value: Double, currency: String) -> String {
        "BTC/\(currency.uppercased()) \(price(value, currency: currency))"
    }

    /// Compact price for tiny surfaces, e.g. 63873 → "63.9K".
    static func priceCompact(_ value: Double) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...:     return String(format: "%.0fK", value / 1_000)
        default:           return String(Int(value))
        }
    }

    static func number(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Derived data (halving + fees)

extension NetworkSnapshot {
    static let halvingInterval = 210_000

    var blocksIntoEra: Int { blockHeight % Self.halvingInterval }
    var blocksUntilHalving: Int { Self.halvingInterval - blocksIntoEra }
    var halvingProgress: Double { Double(blocksIntoEra) / Double(Self.halvingInterval) }

    /// Rough ETA assuming 10 min/block.
    var halvingETA: Date {
        Date().addingTimeInterval(Double(blocksUntilHalving) * 10 * 60)
    }

    /// The fee tiers as mempool presents them (priority): low = 1h, high = next block.
    var feeLow: Int { feeHour }
    var feeMedium: Int { feeHalfHour }
    var feeHigh: Int { feeFast }

    /// "L 1 · M 3 · H 4"
    var feeSummary: String {
        "L \(feeLow) · M \(feeMedium) · H \(feeHigh)"
    }
}

// MARK: - Timeline

struct StatsEntry: TimelineEntry {
    let date: Date
    let snapshot: NetworkSnapshot?
    let currency: String
    let isPremium: Bool
    let isStale: Bool
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), snapshot: .preview, currency: "USD", isPremium: true, isStale: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        let cached = AppGroupStore.loadCachedSnapshot()
        completion(StatsEntry(
            date: Date(),
            snapshot: cached ?? .preview,
            currency: AppGroupStore.preferredCurrency,
            isPremium: context.isPreview ? true : AppGroupStore.isPremium,
            isStale: false
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        Task {
            let currency = AppGroupStore.preferredCurrency

            guard AppGroupStore.isPremium else {
                let entry = StatsEntry(date: Date(), snapshot: nil, currency: currency,
                                       isPremium: false, isStale: false)
                completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600))))
                return
            }

            var snapshot = AppGroupStore.loadCachedSnapshot()
            var isStale = (snapshot != nil)
            do {
                let fresh = try await NetworkClient.fetchSnapshot()
                AppGroupStore.saveCachedSnapshot(fresh)
                snapshot = fresh
                isStale = false
            } catch {
                // keep last good snapshot (stale) — never blank
            }

            let entry = StatsEntry(date: Date(), snapshot: snapshot, currency: currency,
                                   isPremium: true, isStale: isStale)
            // Request a tight cadence; WidgetKit still throttles to ~15-60 min.
            let next = Date().addingTimeInterval(snapshot == nil ? 2 * 60 : 5 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Widgets

/// Price-focused widget (kept kind "InsightWidgets" so existing placements survive).
struct InsightWidgets: Widget {
    let kind = "InsightWidgets"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            PriceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bitcoin Price")
        .description("Live BTC price, with block height and fees.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

/// No-price network widget: block height, fees, halving %.
struct NetworkWidget: Widget {
    let kind = "InsightNetwork"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            NetworkWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Network")
        .description("Block height, fees and halving progress.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

/// Halving countdown.
struct HalvingWidget: Widget {
    let kind = "InsightHalving"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HalvingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Halving Countdown")
        .description("Progress toward the next halving.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

/// Block height.
struct BlockHeightWidget: Widget {
    let kind = "InsightBlock"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            BlockWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Block Height")
        .description("The current Bitcoin block height.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Previews

#Preview("Price", as: .systemSmall) {
    InsightWidgets()
} timeline: {
    StatsEntry(date: .now, snapshot: .preview, currency: "USD", isPremium: true, isStale: false)
}

#Preview("Network", as: .systemMedium) {
    NetworkWidget()
} timeline: {
    StatsEntry(date: .now, snapshot: .preview, currency: "USD", isPremium: true, isStale: false)
}

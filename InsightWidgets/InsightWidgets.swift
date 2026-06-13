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

    static func compact(_ value: Int) -> String { priceCompact(Double(value)) }

    static func hashrate(_ hps: Double) -> String {
        let units = ["H/s", "KH/s", "MH/s", "GH/s", "TH/s", "PH/s", "EH/s", "ZH/s"]
        var v = hps, i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        return String(format: "%.0f %@", v, units[i])
    }

    static func difficulty(_ d: Double) -> String {
        if d >= 1e12 { return String(format: "%.1f T", d / 1e12) }
        if d >= 1e9  { return String(format: "%.1f G", d / 1e9) }
        return number(Int(d))
    }

    static func btc(_ sats: Int) -> String {
        String(format: "%.0f BTC", Double(sats) / 100_000_000)
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

// MARK: - Derived (market + supply)

extension NetworkSnapshot {
    /// Sats per 1 USD.
    var moscowTime: Int {
        let usd = prices["USD"] ?? 0
        return usd > 0 ? Int(100_000_000 / usd) : 0
    }

    /// Circulating supply in BTC, computed from the block height.
    var circulatingSupply: Double {
        let interval = 210_000
        var subsidy = 50.0, supply = 0.0, h = blockHeight
        while h >= interval { supply += Double(interval) * subsidy; h -= interval; subsidy /= 2 }
        supply += Double(h) * subsidy
        return supply
    }

    var supplyPercent: Double { circulatingSupply / 21_000_000 * 100 }
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

// MARK: - More single-metric widgets

struct MoscowWidget: Widget {
    let kind = "InsightMoscow"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MoscowWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Moscow Time")
        .description("Sats per unit of fiat.")
        .supportedFamilies([.systemSmall, .accessoryInline, .accessoryRectangular])
    }
}

struct FeesWidget: Widget {
    let kind = "InsightFees"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            FeesWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fees")
        .description("Recommended fees (low / medium / high).")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct HashrateWidget: Widget {
    let kind = "InsightHashrate"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HashrateWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Hashrate")
        .description("Network hashrate.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct MempoolWidget: Widget {
    let kind = "InsightMempool"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MempoolWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mempool")
        .description("Unconfirmed transactions.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct SupplyWidget: Widget {
    let kind = "InsightSupply"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SupplyWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Circulating Supply")
        .description("Mined supply toward 21M.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct LightningWidget: Widget {
    let kind = "InsightLightning"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LightningWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Lightning")
        .description("Lightning Network capacity, nodes and channels.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Themed bundles

struct MiningWidget: Widget {
    let kind = "InsightMining"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MiningWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Mining")
        .description("Hashrate, difficulty and the next adjustment.")
        .supportedFamilies([.systemMedium])
    }
}

struct MarketWidget: Widget {
    let kind = "InsightMarket"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            MarketWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Market")
        .description("Price, Moscow time and supply.")
        .supportedFamilies([.systemMedium])
    }
}

struct OverviewWidget: Widget {
    let kind = "InsightOverview"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            OverviewWidgetView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Overview")
        .description("The key Bitcoin stats at a glance.")
        .supportedFamilies([.systemLarge])
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

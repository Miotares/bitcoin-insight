//
//  WidgetCatalog.swift
//  InsightWidgets
//
//  Entry views for the extended widget catalog (single metrics + themed bundles).
//  Reuses HomeLabel / BigValue / StatBlock / WidgetGate from WidgetViews.swift.
//

import WidgetKit
import SwiftUI

// Small gate wrapper to keep each view tidy.
private struct Gate<Content: View>: View {
    let family: WidgetFamily
    let entry: StatsEntry
    @ViewBuilder var content: (NetworkSnapshot) -> Content
    var body: some View {
        if !entry.isPremium { LockedView(family: family) }
        else if let s = entry.snapshot { content(s) }
        else { ProgressView() }
    }
}

// MARK: - Moscow Time

struct MoscowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            switch family {
            case .accessoryInline:
                Text("\(WidgetFormat.number(s.moscowTime(for: entry.currency))) sats/\(entry.currency.uppercased())")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Moscow Time").fontWeight(.semibold)
                    Text("\(WidgetFormat.number(s.moscowTime(for: entry.currency))) sats/\(entry.currency.uppercased())")
                }.font(.caption)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Moscow Time")
                    Spacer(minLength: 6)
                    BigValue(text: WidgetFormat.number(s.moscowTime(for: entry.currency)), size: 30)
                    Text("sats / \(entry.currency.uppercased())").font(.caption2).foregroundStyle(.secondary)
                    if let series = s.moscowSeries {
                        Spacer(minLength: 8)
                        WidgetSparkline(values: series)
                    }
                }
            }
        }
    }
}

// MARK: - Fees

private struct FeeLine: View {
    let name: String, value: Int, color: Color
    var body: some View {
        HStack {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)").fontWeight(.semibold).foregroundStyle(color)
            Text("sat/vB").font(.caption2).foregroundStyle(.tertiary)
        }.font(.caption)
    }
}

struct FeesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fees · sat/vB").fontWeight(.semibold)
                    Text("H \(s.feeHigh) · M \(s.feeMedium) · L \(s.feeLow)")
                }.font(.caption)
            default:
                VStack(alignment: .leading, spacing: 8) {
                    HomeLabel("Fees")
                    FeeLine(name: "High", value: s.feeHigh, color: .red)
                    FeeLine(name: "Medium", value: s.feeMedium, color: .orange)
                    FeeLine(name: "Low", value: s.feeLow, color: .green)
                }
            }
        }
    }
}

// MARK: - Hashrate

struct HashrateWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hashrate").fontWeight(.semibold)
                    Text(WidgetFormat.hashrate(s.hashrate))
                }.font(.caption)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Hashrate")
                    Spacer(minLength: 6)
                    BigValue(text: WidgetFormat.hashrate(s.hashrate), size: 26)
                    Text(s.hashrateSeries == nil ? "network hashrate" : "30-day trend")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let series = s.hashrateSeries {
                        Spacer(minLength: 8)
                        WidgetSparkline(values: series)
                    }
                }
            }
        }
    }
}

// MARK: - Mempool

struct MempoolWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mempool").fontWeight(.semibold)
                    Text("\(WidgetFormat.number(s.mempoolCount)) txs")
                }.font(.caption)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Mempool")
                    Spacer(minLength: 6)
                    BigValue(text: WidgetFormat.number(s.mempoolCount), size: 28)
                    Text("unconfirmed txs").font(.caption2).foregroundStyle(.secondary)
                    if let series = s.mempoolSeries {
                        Spacer(minLength: 8)
                        WidgetSparkline(values: series)
                    }
                }
            }
        }
    }
}

// MARK: - Circulating Supply

struct SupplyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            let pct = String(format: "%.2f", s.supplyPercent)
            let mined = String(format: "%.1fM", s.circulatingSupply / 1_000_000)
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Circulating supply").fontWeight(.semibold)
                    Text("\(pct)% · \(mined) BTC")
                }.font(.caption)
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Supply")
                    Spacer(minLength: 6)
                    BigValue(text: "\(pct)%", size: 30)
                    Spacer(minLength: 6)
                    ProgressView(value: s.supplyPercent, total: 100).tint(Color.btcOrange)
                    Text("\(mined) / 21M BTC").font(.caption2).foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Lightning

struct LightningWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            switch family {
            case .systemMedium:
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Lightning")
                    Spacer(minLength: 10)
                    HStack(alignment: .top, spacing: 0) {
                        StatBlock(label: "Capacity", value: WidgetFormat.btc(s.lnCapacitySats))
                        Spacer()
                        StatBlock(label: "Nodes", value: WidgetFormat.number(s.lnNodes))
                        Spacer()
                        StatBlock(label: "Channels", value: WidgetFormat.number(s.lnChannels))
                    }
                    Spacer(minLength: 0)
                }
            default:
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Lightning")
                    Spacer(minLength: 6)
                    BigValue(text: WidgetFormat.btc(s.lnCapacitySats), size: 24)
                    Text("capacity").font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 6)
                    Text("\(WidgetFormat.number(s.lnNodes)) nodes")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Mining (bundle)

struct MiningWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            VStack(alignment: .leading, spacing: 0) {
                HomeLabel("Mining")
                Spacer(minLength: 10)
                HStack(alignment: .top, spacing: 0) {
                    StatBlock(label: "Hashrate", value: WidgetFormat.hashrate(s.hashrate))
                    Spacer()
                    StatBlock(label: "Difficulty", value: WidgetFormat.difficulty(s.difficulty))
                    Spacer()
                    StatBlock(label: "Next adj.", value: "\(Int(s.adjustmentProgress))%",
                              sub: "\(WidgetFormat.number(s.adjustmentRemainingBlocks)) blocks")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Market (bundle)

struct MarketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            let pct = String(format: "%.1f", s.supplyPercent)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) { BrandLogo(size: 18); HomeLabel("Market") }
                Spacer(minLength: 10)
                HStack(alignment: .top, spacing: 0) {
                    StatBlock(label: "Price", value: WidgetFormat.price(s.price(for: entry.currency), currency: entry.currency))
                    Spacer()
                    StatBlock(label: "Moscow", value: WidgetFormat.number(s.moscowTime(for: entry.currency)), sub: "sats/\(entry.currency.uppercased())")
                    Spacer()
                    StatBlock(label: "Supply", value: "\(pct)%")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Overview (systemLarge)

struct OverviewWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry
    var body: some View {
        Gate(family: family, entry: entry) { s in
            let halvingPct = Int(s.halvingProgress * 100)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    BrandLogo(size: 22)
                    HomeLabel("Bitcoin Insight")
                    Spacer()
                }
                BigValue(text: WidgetFormat.price(s.price(for: entry.currency), currency: entry.currency), size: 40)

                Divider()

                HStack(alignment: .top, spacing: 0) {
                    StatBlock(label: "Block", value: WidgetFormat.number(s.blockHeight))
                    Spacer()
                    StatBlock(label: "Fee", value: "\(s.feeHigh) sat/vB", sub: s.feeCongestion)
                    Spacer()
                    StatBlock(label: "Halving", value: "\(halvingPct)%")
                }
                HStack(alignment: .top, spacing: 0) {
                    StatBlock(label: "Hashrate", value: WidgetFormat.hashrate(s.hashrate))
                    Spacer()
                    StatBlock(label: "Mempool", value: "\(WidgetFormat.compact(s.mempoolCount)) txs")
                    Spacer()
                    StatBlock(label: "Moscow", value: WidgetFormat.number(s.moscowTime(for: entry.currency)), sub: "sats/\(entry.currency.uppercased())")
                }
                Spacer(minLength: 0)
            }
        }
    }
}

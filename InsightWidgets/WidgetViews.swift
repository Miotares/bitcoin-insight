//
//  WidgetViews.swift
//  InsightWidgets
//
//  Entry views for each widget + shared building blocks.
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - Shared building blocks

extension NetworkSnapshot {
    /// Congestion label for the next-block fee.
    var feeCongestion: String {
        switch feeHigh {
        case ..<6:  return "Low"
        case ..<25: return "Medium"
        default:    return "High"
        }
    }
}

/// The real Bitcoin logo PNG if present in the asset catalog, otherwise nothing
/// (we never fall back to the SF "bitcoinsign" glyph). Add a transparent
/// `BitcoinLogo` image set to InsightWidgets/Assets.xcassets to enable it.
struct BrandLogo: View {
    var size: CGFloat = 20
    var body: some View {
        if UIImage(named: "BitcoinLogo") != nil {
            Image("BitcoinLogo").resizable().scaledToFit().frame(width: size, height: size)
        } else {
            EmptyView()
        }
    }
}

private struct StaleDot: View {
    let stale: Bool
    var body: some View {
        if stale { Image(systemName: "wifi.slash").font(.caption2).foregroundStyle(.secondary) }
    }
}

/// Icon + value (+ optional caption) row used in the home widgets.
private struct MetricRow: View {
    let icon: String
    let value: String
    var caption: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
                if let caption { Text(caption).font(.caption2).foregroundStyle(.tertiary).lineLimit(1) }
            }
        }
    }
}

struct LockedView: View {
    let family: WidgetFamily
    var body: some View {
        switch family {
        case .accessoryInline:      Label("Premium", systemImage: "lock.fill")
        case .accessoryCircular:    Image(systemName: "lock.fill")
        case .accessoryRectangular: Label("Unlock in app", systemImage: "lock.fill")
        default:
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.title2).foregroundStyle(Color.btcOrange)
                Text("Premium").font(.headline)
                Text("Unlock in the app").font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

/// Small helper to gate every widget on premium + data.
private struct WidgetGate<Content: View>: View {
    let family: WidgetFamily
    let entry: StatsEntry
    @ViewBuilder var content: (NetworkSnapshot) -> Content
    var body: some View {
        if !entry.isPremium {
            LockedView(family: family)
        } else if let snap = entry.snapshot {
            content(snap)
        } else {
            ProgressView()
        }
    }
}

// MARK: - Price widget

struct PriceWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry

    var body: some View {
        WidgetGate(family: family, entry: entry) { snap in
            let price = snap.price(for: entry.currency)
            switch family {
            case .accessoryInline:
                Text(WidgetFormat.pair(price, currency: entry.currency))
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text("BTC").font(.system(size: 9, weight: .medium))
                    Text(WidgetFormat.priceCompact(price))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetFormat.pair(price, currency: entry.currency)).fontWeight(.semibold)
                    Text("\(snap.feeHigh) sat/vB · \(snap.feeCongestion)")
                    Text("Block \(WidgetFormat.number(snap.blockHeight))")
                }
                .font(.caption).lineLimit(1)
            case .systemMedium:
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            BrandLogo(size: 20)
                            Text("BTC/\(entry.currency.uppercased())").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(WidgetFormat.price(price, currency: entry.currency))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .minimumScaleFactor(0.5).lineLimit(1)
                        HStack(spacing: 4) {
                            StaleDot(stale: entry.isStale)
                            Text(snap.updatedAt, style: .relative)
                        }
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        MetricRow(icon: "cube.fill", value: WidgetFormat.number(snap.blockHeight), caption: "block")
                        MetricRow(icon: "banknote.fill", value: "\(snap.feeHigh) sat/vB", caption: snap.feeCongestion)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            default: // systemSmall
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        BrandLogo(size: 18)
                        Text("BTC/\(entry.currency.uppercased())").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        StaleDot(stale: entry.isStale)
                    }
                    Text(WidgetFormat.price(price, currency: entry.currency))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Spacer(minLength: 0)
                    Label(WidgetFormat.number(snap.blockHeight), systemImage: "cube.fill")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Label("\(snap.feeHigh) sat/vB · \(snap.feeCongestion)", systemImage: "banknote.fill")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Network widget (no price)

struct NetworkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry

    var body: some View {
        WidgetGate(family: family, entry: entry) { snap in
            let pct = Int(snap.halvingProgress * 100)
            switch family {
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block \(WidgetFormat.number(snap.blockHeight))").fontWeight(.semibold)
                    Text("\(snap.feeHigh) sat/vB · \(snap.feeCongestion)")
                    Text("Halving \(pct)%")
                }
                .font(.caption).lineLimit(1)
            case .systemMedium:
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        BrandLogo(size: 18)
                        Text("Network").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        StaleDot(stale: entry.isStale)
                    }
                    HStack(spacing: 16) {
                        MetricRow(icon: "cube.fill", value: WidgetFormat.number(snap.blockHeight), caption: "block height")
                        MetricRow(icon: "banknote.fill", value: snap.feeSummary, caption: "sat/vB")
                    }
                    MetricRow(icon: "hourglass", value: "Halving \(pct)%", caption: "\(WidgetFormat.number(snap.blocksUntilHalving)) blocks left")
                }
            default: // systemSmall
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("Network").font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        StaleDot(stale: entry.isStale)
                    }
                    MetricRow(icon: "cube.fill", value: WidgetFormat.number(snap.blockHeight), caption: "block")
                    MetricRow(icon: "banknote.fill", value: "\(snap.feeHigh) sat/vB", caption: snap.feeCongestion)
                    MetricRow(icon: "hourglass", value: "\(pct)%", caption: "to halving")
                }
            }
        }
    }
}

// MARK: - Halving widget

struct HalvingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry

    var body: some View {
        WidgetGate(family: family, entry: entry) { snap in
            let pct = Int(snap.halvingProgress * 100)
            let left = WidgetFormat.number(snap.blocksUntilHalving)
            switch family {
            case .accessoryInline:
                Text("Halving \(pct)% · \(left) blocks")
            case .accessoryCircular:
                Gauge(value: snap.halvingProgress) {
                    Image(systemName: "hourglass")
                } currentValueLabel: {
                    Text("\(pct)%").font(.system(.caption, design: .rounded))
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Halving countdown").fontWeight(.semibold)
                    Text("\(pct)% · \(left) blocks left")
                    Gauge(value: snap.halvingProgress) { EmptyView() }.gaugeStyle(.accessoryLinear)
                }
                .font(.caption)
            default: // systemSmall
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "hourglass").foregroundStyle(Color.btcOrange)
                        Text("Halving").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        StaleDot(stale: entry.isStale)
                    }
                    Text("\(pct)%")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    ProgressView(value: snap.halvingProgress).tint(Color.btcOrange)
                    Text("\(left) blocks left").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    Text(snap.halvingETA, style: .date).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Block height widget

struct BlockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry

    var body: some View {
        WidgetGate(family: family, entry: entry) { snap in
            switch family {
            case .accessoryInline:
                Text("Block \(WidgetFormat.number(snap.blockHeight))")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: "cube.fill").font(.caption2)
                    Text(WidgetFormat.priceCompact(Double(snap.blockHeight)))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("Block height").fontWeight(.semibold)
                    Text(WidgetFormat.number(snap.blockHeight))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("\(WidgetFormat.number(snap.blocksUntilHalving)) to halving")
                }
                .font(.caption).lineLimit(1)
            default: // systemSmall
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "cube.fill").foregroundStyle(Color.btcOrange)
                        Text("Block height").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        StaleDot(stale: entry.isStale)
                    }
                    Spacer(minLength: 0)
                    Text(WidgetFormat.number(snap.blockHeight))
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.4).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(WidgetFormat.number(snap.blocksUntilHalving)) blocks to halving")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

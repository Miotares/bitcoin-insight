//
//  WidgetViews.swift
//  InsightWidgets
//
//  Entry views for each widget + shared building blocks.
//  Home layouts are deliberately typographic — no decorative SF icons.
//

import WidgetKit
import SwiftUI
import UIKit

// MARK: - Derived

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

// MARK: - Shared building blocks

/// The real Bitcoin logo PNG if present, otherwise nothing (never the SF glyph).
/// Add a transparent `BitcoinLogo` image set to InsightWidgets/Assets.xcassets.
struct BrandLogo: View {
    var size: CGFloat = 18
    var body: some View {
        if UIImage(named: "BitcoinLogo") != nil {
            Image("BitcoinLogo").resizable().scaledToFit().frame(width: size, height: size)
        } else {
            EmptyView()
        }
    }
}

/// Small, tracked, uppercase caption used as the header on home widgets.
struct HomeLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption).fontWeight(.semibold)
            .tracking(0.8)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// Stacked label → value (→ optional sub) block. The home widgets' only unit.
struct StatBlock: View {
    let label: String
    let value: String
    var sub: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.caption2).tracking(0.5).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.6).lineLimit(1)
            if let sub {
                Text(sub).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

/// Big rounded value, the focal number on a home widget.
struct BigValue: View {
    let text: String
    var size: CGFloat = 30
    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.4).lineLimit(1)
    }
}

struct StaleDot: View {
    let stale: Bool
    var body: some View {
        if stale { Image(systemName: "wifi.slash").font(.caption2).foregroundStyle(.secondary) }
    }
}

struct LockedView: View {
    let family: WidgetFamily
    var body: some View {
        // Tapping a locked widget opens the app's paywall.
        content.widgetURL(URL(string: "bitcoininsight://paywall"))
    }

    @ViewBuilder private var content: some View {
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

/// Gates every widget on premium + data.
struct WidgetGate<Content: View>: View {
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

            // Lock screen (unchanged look)
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

            // Home (clean, minimal, no icons, no timer)
            case .systemMedium:
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) { BrandLogo(size: 18); HomeLabel("BTC/\(entry.currency.uppercased())") }
                        Spacer(minLength: 8)
                        BigValue(text: WidgetFormat.price(price, currency: entry.currency), size: 38)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 12) {
                        StatBlock(label: "Fee", value: "\(snap.feeHigh) sat/vB", sub: snap.feeCongestion)
                        StatBlock(label: "Block", value: WidgetFormat.number(snap.blockHeight))
                    }
                }
            default: // systemSmall
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) { BrandLogo(size: 16); HomeLabel("BTC/\(entry.currency.uppercased())") }
                    Spacer(minLength: 6)
                    BigValue(text: WidgetFormat.price(price, currency: entry.currency), size: 30)
                    Spacer(minLength: 6)
                    StatBlock(label: "Fee", value: "\(snap.feeHigh) sat/vB", sub: snap.feeCongestion)
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
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Network")
                    Spacer(minLength: 10)
                    HStack(alignment: .top, spacing: 0) {
                        StatBlock(label: "Block", value: WidgetFormat.number(snap.blockHeight))
                        Spacer()
                        StatBlock(label: "Fee", value: "\(snap.feeHigh) sat/vB", sub: snap.feeCongestion)
                        Spacer()
                        StatBlock(label: "Halving", value: "\(pct)%")
                    }
                    Spacer(minLength: 0)
                }
            default: // systemSmall
                VStack(alignment: .leading, spacing: 12) {
                    HomeLabel("Network")
                    StatBlock(label: "Block", value: WidgetFormat.number(snap.blockHeight))
                    StatBlock(label: "Fee", value: "\(snap.feeHigh) sat/vB", sub: snap.feeCongestion)
                    StatBlock(label: "Halving", value: "\(pct)%")
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

            default: // systemSmall (home)
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Halving")
                    Spacer(minLength: 8)
                    BigValue(text: "\(pct)%", size: 34)
                    Spacer(minLength: 8)
                    ProgressView(value: snap.halvingProgress).tint(Color.btcOrange)
                    Text("\(left) blocks left")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .padding(.top, 4)
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
                    Text("BLOCK").font(.system(size: 9, weight: .medium))
                    Text(WidgetFormat.priceCompact(Double(snap.blockHeight)))
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("Block height").font(.caption2).foregroundStyle(.secondary)
                    Text(WidgetFormat.number(snap.blockHeight))
                        .font(.system(.headline, design: .rounded))
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("\(WidgetFormat.number(snap.blocksUntilHalving)) to halving")
                        .font(.caption2)
                }

            default: // systemSmall (home)
                VStack(alignment: .leading, spacing: 0) {
                    HomeLabel("Block height")
                    Spacer(minLength: 8)
                    BigValue(text: WidgetFormat.number(snap.blockHeight), size: 30)
                    Spacer(minLength: 8)
                    Text("\(WidgetFormat.number(snap.blocksUntilHalving)) to halving")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

//
//  InsightWidgets.swift
//  InsightWidgets
//
//  Home- and Lock-screen widgets for Bitcoin Insight.
//  Premium-gated; reads the backend cache, falls back to the last good
//  snapshot from the App Group when the backend is unreachable.
//

import WidgetKit
import SwiftUI

// MARK: - Brand + formatting (widget-local)

private extension Color {
    static let btcOrange = Color(red: 247 / 255, green: 147 / 255, blue: 26 / 255)
}

enum WidgetFormat {
    static func price(_ value: Double, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(Int(value))"
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

// MARK: - Timeline

struct StatsEntry: TimelineEntry {
    let date: Date
    let snapshot: NetworkSnapshot?   // nil → never cached yet
    let currency: String
    let isPremium: Bool
    let isStale: Bool                // showing cached data, fetch failed
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

            // Locked: no network, single entry, slow re-check.
            guard AppGroupStore.isPremium else {
                let entry = StatsEntry(date: Date(), snapshot: nil, currency: currency,
                                       isPremium: false, isStale: false)
                completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(6 * 3600))))
                return
            }

            var snapshot = AppGroupStore.loadCachedSnapshot()
            var isStale = (snapshot != nil)   // assume stale until a fresh fetch succeeds
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
            // Request a tight cadence so WidgetKit refreshes as often as its budget
            // allows (it still throttles to ~15-60 min in practice). Sooner if we
            // have nothing cached yet.
            let next = Date().addingTimeInterval(snapshot == nil ? 2 * 60 : 5 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Entry view (routes by family + state)

struct InsightWidgetsEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: StatsEntry

    var body: some View {
        if !entry.isPremium {
            LockedView(family: family)
        } else if let snap = entry.snapshot {
            switch family {
            case .accessoryInline:      InlineView(snap: snap, currency: entry.currency)
            case .accessoryCircular:    CircularView(snap: snap)
            case .accessoryRectangular: RectangularView(snap: snap, currency: entry.currency, stale: entry.isStale)
            case .systemMedium:         MediumView(snap: snap, currency: entry.currency, stale: entry.isStale)
            default:                    SmallView(snap: snap, currency: entry.currency, stale: entry.isStale)
            }
        } else {
            // Premium but nothing cached and fetch failed.
            ProgressView()
        }
    }
}

// MARK: - Home screen

private struct SmallView: View {
    let snap: NetworkSnapshot
    let currency: String
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(Color.btcOrange)
                Text("Bitcoin").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if stale { Image(systemName: "wifi.slash").font(.caption2).foregroundStyle(.secondary) }
            }
            Text(WidgetFormat.price(snap.price(for: currency), currency: currency))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 0)
            Label(WidgetFormat.number(snap.blockHeight), systemImage: "cube.fill")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Label("\(snap.feeFast) sat/vB", systemImage: "banknote.fill")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct MediumView: View {
    let snap: NetworkSnapshot
    let currency: String
    let stale: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "bitcoinsign.circle.fill").foregroundStyle(Color.btcOrange)
                    Text("Bitcoin").font(.caption).foregroundStyle(.secondary)
                }
                Text(WidgetFormat.price(snap.price(for: currency), currency: currency))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.6).lineLimit(1)
                HStack(spacing: 4) {
                    if stale { Image(systemName: "wifi.slash") }
                    Text(snap.updatedAt, style: .relative)
                }
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                metric(icon: "cube.fill", title: "Block", value: WidgetFormat.number(snap.blockHeight))
                metric(icon: "banknote.fill", title: "Fee", value: "\(snap.feeFast) sat/vB")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.subheadline, design: .rounded).weight(.semibold)).lineLimit(1)
        }
    }
}

// MARK: - Lock screen

private struct InlineView: View {
    let snap: NetworkSnapshot
    let currency: String
    var body: some View {
        Label("\(WidgetFormat.price(snap.price(for: currency), currency: currency)) · \(snap.feeFast) sat/vB",
              systemImage: "bitcoinsign")
    }
}

private struct CircularView: View {
    let snap: NetworkSnapshot
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "bitcoinsign").font(.caption2)
            Text(WidgetFormat.priceCompact(snap.price(for: "USD")))
                .font(.system(.caption, design: .rounded).weight(.bold))
                .minimumScaleFactor(0.5).lineLimit(1)
        }
    }
}

private struct RectangularView: View {
    let snap: NetworkSnapshot
    let currency: String
    let stale: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "bitcoinsign")
                Text(WidgetFormat.price(snap.price(for: currency), currency: currency))
                    .fontWeight(.bold)
                if stale { Image(systemName: "wifi.slash").font(.caption2) }
            }
            Text("Block \(WidgetFormat.number(snap.blockHeight))")
            Text("\(snap.feeFast) sat/vB")
        }
        .font(.caption)
        .lineLimit(1)
    }
}

// MARK: - Locked state

private struct LockedView: View {
    let family: WidgetFamily
    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Premium", systemImage: "lock.fill")
        case .accessoryCircular:
            Image(systemName: "lock.fill")
        case .accessoryRectangular:
            Label("Unlock in app", systemImage: "lock.fill")
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

// MARK: - Widget

struct InsightWidgets: Widget {
    let kind = "InsightWidgets"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            InsightWidgetsEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bitcoin Insight")
        .description("Live price, block height and fees.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryCircular, .accessoryRectangular
        ])
    }
}

#Preview(as: .systemSmall) {
    InsightWidgets()
} timeline: {
    StatsEntry(date: .now, snapshot: .preview, currency: "USD", isPremium: true, isStale: false)
}

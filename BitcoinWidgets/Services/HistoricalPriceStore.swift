//
//  HistoricalPriceStore.swift
//  BitcoinWidgets
//
//  Shared, cached source for mempool.space's full historical BTC price series,
//  reused by BOTH the Dashboard's 24h sparkline and the PriceDetailView chart so
//  the (large) `historical-price` response is fetched ONCE per currency and
//  shared. Opening the price detail right after the Dashboard has loaded is then
//  a cache hit instead of a second ~1.4 MB download.
//
//  mempool.space returns the WHOLE history in one response (~31k points, hourly
//  for the recent window → weekly far back). We parse + sort it once, cache it per
//  currency with a short TTL, and coalesce concurrent requests so the sparkline
//  and the chart asking at the same moment still trigger only one network call.
//
//  This is the app's primary price-history source — consistent with every other
//  chart, which all read mempool. CoinGecko stays a per-view fallback (the
//  sparkline uses it for the 24h window only if mempool is unavailable).
//
//  Far-past enrichment: mempool's history coarsens to ~weekly far back, so we ALSO
//  read our Supabase `price_history` table (dense daily back to 2011) and MERGE —
//  DB daily for the deep past, mempool for the recent window. This is purely
//  additive: if the Supabase read fails, the chart still works from mempool alone.
//

import Foundation
import OSLog

actor HistoricalPriceStore {
    static let shared = HistoricalPriceStore()

    private static let log = Logger(subsystem: "miotares.BitcoinWidgets", category: "PriceStore")

    /// One historical sample: a timestamp and the price in the requested currency.
    struct Point: Sendable {
        let date: Date
        let price: Double
    }

    private struct Entry {
        let points: [Point]
        let fetchedAt: Date
    }

    /// How long a cached series is served before a re-fetch. Matches the
    /// sparkline's periodic cadence, so navigating around within a few minutes
    /// reuses the same download.
    private let ttl: TimeInterval = 5 * 60

    private var cache: [String: Entry] = [:]
    private var inFlight: [String: Task<[Point], Never>] = [:]

    private init() {}

    /// Full ascending price history for `currency`. Returns a cached copy when one
    /// exists and is younger than the TTL, otherwise fetches from mempool.
    /// Concurrent callers for the same currency share a single network request.
    /// Returns an empty array if mempool is unreachable / returns nothing.
    func series(for currency: String) async -> [Point] {
        await fetchCoalesced(currency.uppercased(), ignoreCache: false)
    }

    /// Force a re-fetch ignoring the TTL (used by the sparkline's periodic refresh
    /// so it actually pulls fresh data), updating the shared cache for everyone.
    func refreshedSeries(for currency: String) async -> [Point] {
        await fetchCoalesced(currency.uppercased(), ignoreCache: true)
    }

    private func fetchCoalesced(_ key: String, ignoreCache: Bool) async -> [Point] {
        if !ignoreCache, let entry = cache[key], Date().timeIntervalSince(entry.fetchedAt) < ttl {
            return entry.points
        }
        // A fetch is already running for this currency — join it instead of
        // starting a second one (covers sparkline + chart racing on first appear).
        if let existing = inFlight[key] {
            return await existing.value
        }
        let task = Task<[Point], Never> {
            // mempool (gap-free, hourly-recent) + our Supabase price_history (dense
            // daily, deep past) fetched concurrently, then merged. Additive: if the
            // DB read fails the chart still works from mempool alone.
            async let mempool = Self.fetchMempool(currency: key)
            async let db = Self.fetchPriceHistoryDB(currency: key)
            return Self.merge(mempool: await mempool, db: await db)
        }
        inFlight[key] = task
        let points = await task.value
        inFlight[key] = nil
        Self.log.debug("series [\(key, privacy: .public)] merged points=\(points.count) first=\(points.first.map { ISO8601DateFormatter().string(from: $0.date) } ?? "-", privacy: .public)")
        if !points.isEmpty {
            cache[key] = Entry(points: points, fetchedAt: Date())
        }
        return points
    }

    /// Decode mempool's `historical-price` (the whole history) into sorted points.
    private static func fetchMempool(currency: String) async -> [Point] {
        guard let url = URL(string: "https://mempool.space/api/v1/historical-price?currency=\(currency)") else {
            return []
        }
        struct Response: Decodable { let prices: [[String: Double]] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            log.debug("mempool historical fetch [\(currency, privacy: .public)] points=\(decoded.prices.count) bytes=\(data.count)")
            return decoded.prices
                .compactMap { dict -> Point? in
                    guard let t = dict["time"], let p = dict[currency], p > 0 else { return nil }
                    return Point(date: Date(timeIntervalSince1970: t), price: p)
                }
                .sorted { $0.date < $1.date }
        } catch {
            return []
        }
    }

    // MARK: - Supabase price_history (dense daily, deep past)

    private static let supabaseURL = "https://hyyagnnsjbpsehriyafn.supabase.co"
    private static let supabaseKey = "sb_publishable_FEEoI6sfC_EZ1oLP2E0IJQ_Yftfzrk9"

    /// Parses the table's `day` column ("yyyy-MM-dd", UTC).
    private static let dbDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Read our backfilled daily series for `currency` from Supabase (read-only,
    /// anon). The column is the lowercased currency code. Empty on any failure —
    /// the caller then just uses mempool (the chart degrades gracefully).
    private static func fetchPriceHistoryDB(currency: String) async -> [Point] {
        let cur = currency.lowercased()
        var pts: [Point] = []
        let pageSize = 1000          // PostgREST caps a response at 1000 rows
        var offset = 0
        while offset <= 50_000 {     // safety cap (~50k rows max)
            guard let url = URL(string: "\(supabaseURL)/rest/v1/price_history?select=day,\(cur)&order=day.asc&limit=\(pageSize)&offset=\(offset)") else { break }
            var req = URLRequest(url: url)
            req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
            do {
                let (data, _) = try await URLSession.shared.data(for: req)
                guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], !rows.isEmpty else { break }
                for row in rows {
                    guard let dayStr = row["day"] as? String,
                          let date = dbDayFormatter.date(from: dayStr),
                          let price = (row[cur] as? NSNumber)?.doubleValue, price > 0 else { continue }
                    pts.append(Point(date: date, price: price))
                }
                if rows.count < pageSize { break }   // last page
                offset += pageSize
            } catch {
                break
            }
        }
        log.debug("price_history DB fetch [\(currency, privacy: .public)] rows=\(pts.count)")
        return pts
    }

    /// USD→`currency` FX rate from the most recent price_history row (db.cur / db.usd,
    /// two BTC prices on the same day → their ratio is the FX rate). Lets the live
    /// fiat price be derived as liveUSD × ratio for currencies mempool doesn't serve
    /// (BRL/INR/…), instead of depending on the flaky/blocked CoinGecko endpoint.
    /// Returns nil for USD or on any failure.
    static func latestFXRatio(currency: String) async -> Double? {
        let cur = currency.lowercased()
        guard cur != "usd",
              let url = URL(string: "\(supabaseURL)/rest/v1/price_history?select=usd,\(cur)&order=day.desc&limit=1") else { return nil }
        var req = URLRequest(url: url)
        req.setValue(supabaseKey, forHTTPHeaderField: "apikey")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let row = rows.first,
                  let usd = (row["usd"] as? NSNumber)?.doubleValue, usd > 0,
                  let cv = (row[cur] as? NSNumber)?.doubleValue, cv > 0 else { return nil }
            return cv / usd
        } catch {
            return nil
        }
    }

    /// Gap-fill the (sparse far-past) mempool series with our dense daily DB series:
    /// add a DB point ONLY for UTC days mempool doesn't already cover. This fills
    /// mempool's weekly far-past gaps with daily points while leaving its dense,
    /// hourly recent window untouched (no resolution downgrade), and never creates
    /// a hole. mempool stays the backbone, so a missing/partial DB just means fewer
    /// filled days, never a broken chart.
    private static func merge(mempool: [Point], db: [Point]) -> [Point] {
        guard !db.isEmpty else { return mempool }
        guard !mempool.isEmpty else { return db }
        func dayKey(_ d: Date) -> Int { Int(d.timeIntervalSince1970 / 86_400) }
        var covered = Set<Int>(minimumCapacity: mempool.count)
        for p in mempool { covered.insert(dayKey(p.date)) }
        let extra = db.filter { !covered.contains(dayKey($0.date)) }
        guard !extra.isEmpty else { return mempool }
        return (mempool + extra).sorted { $0.date < $1.date }
    }
}

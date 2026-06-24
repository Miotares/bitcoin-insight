//
//  ExploreModels.swift
//  BitcoinWidgets
//
//  Data types for the Explore tab — a privacy-respecting, request-sparing
//  block explorer. Nothing here is persisted: searched txids/addresses are
//  held in memory for the lifetime of the screen and never written to the
//  Wallet's Keychain store.
//

import Foundation

// MARK: - Recent block (feed + websocket)

/// One block as it appears in the live feed. Decodes BOTH from the REST seed
/// (`GET /api/v1/blocks`) and from the websocket `block`/`blocks` payloads —
/// they share the same enriched shape (top-level fields + `extras`).
struct RecentBlock: Identifiable, Decodable, Equatable {
    let id: String          // block hash
    let height: Int
    let timestamp: TimeInterval
    let txCount: Int
    let size: Int
    let poolName: String?
    let medianFee: Double?
    let totalFees: Int?

    private enum Keys: String, CodingKey {
        case id, height, timestamp, tx_count, size, extras
    }
    private enum ExtrasKeys: String, CodingKey {
        case medianFee, totalFees, pool
    }
    private enum PoolKeys: String, CodingKey {
        case name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id)
        height = try c.decode(Int.self, forKey: .height)
        timestamp = try c.decodeIfPresent(TimeInterval.self, forKey: .timestamp) ?? 0
        txCount = try c.decodeIfPresent(Int.self, forKey: .tx_count) ?? 0
        size = try c.decodeIfPresent(Int.self, forKey: .size) ?? 0

        if let extras = try? c.nestedContainer(keyedBy: ExtrasKeys.self, forKey: .extras) {
            medianFee = try extras.decodeIfPresent(Double.self, forKey: .medianFee)
            totalFees = try extras.decodeIfPresent(Int.self, forKey: .totalFees)
            if let pool = try? extras.nestedContainer(keyedBy: PoolKeys.self, forKey: .pool) {
                poolName = try pool.decodeIfPresent(String.self, forKey: .name)
            } else {
                poolName = nil
            }
        } else {
            medianFee = nil
            totalFees = nil
            poolName = nil
        }
    }
}

/// Tolerant envelope for websocket frames. We only subscribed to `blocks`, so
/// every other key the server pushes is simply ignored.
struct WSEnvelope: Decodable {
    let block: RecentBlock?
    let blocks: [RecentBlock]?
}

// MARK: - Transaction detail (`GET /api/tx/{txid}`)

struct TxDetail: Decodable {
    struct Prevout: Decodable {
        let scriptpubkey_address: String?
        let value: Int?
    }
    struct Vin: Decodable {
        let prevout: Prevout?
        let is_coinbase: Bool?
    }
    struct Vout: Decodable {
        let scriptpubkey_address: String?
        let value: Int
    }
    struct Status: Decodable {
        let confirmed: Bool
        let block_height: Int?
        let block_time: Int?
    }

    let txid: String
    let fee: Int?
    let size: Int
    let weight: Int
    let vin: [Vin]
    let vout: [Vout]
    let status: Status

    /// Virtual size in vBytes (weight / 4, rounded up).
    var vsize: Int { Int((Double(weight) / 4.0).rounded(.up)) }
    var feeRate: Double { vsize > 0 ? Double(fee ?? 0) / Double(vsize) : 0 }
    var isCoinbase: Bool { vin.contains { $0.is_coinbase == true } }
    var outputTotal: Int { vout.map { $0.value }.reduce(0, +) }
}

// MARK: - Navigation

/// Where a search result or a tapped row navigates to. Hashable so it can drive
/// a `NavigationStack` path.
enum ExploreRoute: Hashable {
    case block(hash: String)
    case tx(txid: String)
    case address(String)
}

// MARK: - Formatting helpers

enum ExploreFormat {

    /// Compact relative age of a block, e.g. "just now", "12 min ago", "3 h ago".
    static func age(_ timestamp: TimeInterval) -> String {
        let seconds = max(0, Date().timeIntervalSince1970 - timestamp)
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        return "\(hours / 24) d ago"
    }

    /// Fiat value of a sats amount in the user's preferred currency, or nil
    /// until the first live price has landed. Uses the same in-memory price
    /// store the Dashboard fills — no network call.
    static func fiat(sats: Int, settings: SettingsManager) -> String? {
        let currency = settings.preferredCurrency
        let price = settings.displayPrice(for: currency)
        guard price > 0 else { return nil }
        let value = Double(sats) / 100_000_000.0 * price
        return Formatters.formatCurrency(value: value, currencyCode: currency)
    }

    /// Middle-truncated hash/address for compact display.
    static func middleTruncate(_ string: String, lead: Int = 10, tail: Int = 10) -> String {
        guard string.count > lead + tail + 1 else { return string }
        return "\(string.prefix(lead))…\(string.suffix(tail))"
    }

    /// BTC value of a sats amount, trimmed to 8 dp (no trailing-zero padding beyond 2).
    static func btc(sats: Int) -> String {
        Formatters.formatBTC(Double(sats) / 100_000_000.0)
    }
}

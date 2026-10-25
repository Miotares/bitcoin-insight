//
//  WalletModels.swift
//  BitcoinWidgets
//

import Foundation

enum WalletType: String, Codable {
    case xpub
    case ypub
    case zpub
    case singleAddress

    var displayName: String {
        switch self {
        case .xpub: return "xpub (Legacy P2PKH)"
        case .ypub: return "ypub (Nested SegWit)"
        case .zpub: return "zpub (Native SegWit)"
        case .singleAddress: return "Single Address"
        }
    }

    var isHDWallet: Bool { self != .singleAddress }
}

struct WalletAddress: Identifiable, Codable {
    let id: UUID
    let address: String
    let derivationIndex: Int?   // nil for single addresses
    let chain: Int?              // 0=external, 1=change
    var balanceSats: Int        // effective (confirmed + mempool)
    var txCount: Int            // effective (confirmed + mempool)
    /// Unconfirmed tx count from the last refresh. Optional so wallets persisted
    /// before this field decode cleanly (nil is treated as 0). Lets the incremental
    /// refresh re-check an address that had pending activity so a mempool→confirmed
    /// flip — which doesn't change the effective count — is still picked up.
    var mempoolTxCount: Int? = nil
}

struct WalletTransaction: Identifiable, Codable {
    var id: String { txid }
    let txid: String
    var confirmed: Bool
    var blockTime: Int?
    var valueSats: Int          // positive=received, negative=sent (net across the wallet)
    var fee: Int?
    let sourceAddress: String
    /// Net effect of this tx on each wallet address (address → sats). An HD tx often
    /// touches several wallet addresses (spend + change); each address history only
    /// sees its own share, so the wallet-level `valueSats` is the sum of all shares.
    /// nil on transactions persisted before this field existed.
    var addressDeltas: [String: Int]? = nil

    /// Combines a stored view of this tx with a fresher one: confirmation status
    /// comes from `newer`, per-address shares are unioned and re-summed. Legacy
    /// entries without shares are simply replaced.
    func merging(_ newer: WalletTransaction) -> WalletTransaction {
        guard let old = addressDeltas, let new = newer.addressDeltas else { return newer }
        var merged = newer
        merged.addressDeltas = old.merging(new) { _, fresh in fresh }
        merged.valueSats = merged.addressDeltas!.values.reduce(0, +)
        return merged
    }
}

struct Wallet: Identifiable, Codable {
    let id: UUID
    var name: String
    var publicKey: String       // xpub, ypub, zpub, or address
    var type: WalletType
    var colorHex: String        // e.g. "#F79326"
    var addresses: [WalletAddress]
    var transactions: [WalletTransaction]
    var lastScanned: Date?

    /// Transient — never persisted. Always false after app restart.
    var isSyncing: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, publicKey, type, colorHex, addresses, transactions, lastScanned
    }

    var totalBalanceSats: Int {
        addresses.reduce(0) { $0 + $1.balanceSats }
    }

    var sortedTransactions: [WalletTransaction] {
        transactions.sorted {
            // Unconfirmed (nil blockTime) first, then newest confirmed
            if $0.blockTime == nil { return true }
            if $1.blockTime == nil { return false }
            return $0.blockTime! > $1.blockTime!
        }
    }
}

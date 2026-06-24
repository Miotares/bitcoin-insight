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
    let confirmed: Bool
    let blockTime: Int?
    let valueSats: Int          // positive=received, negative=sent
    let fee: Int?
    let sourceAddress: String
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

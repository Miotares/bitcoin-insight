//
//  ExploreAddressDetailView.swift
//  BitcoinWidgets
//
//  Address detail for the Explore tab. Reuses the Wallet's existing
//  `WalletAPIService` (address stats + first transaction page) — but, unlike the
//  Wallet tab, this is a pure read: the address is NEVER added to the on-device
//  wallet or written to the Keychain. It lives only in this view's state.
//

import SwiftUI

struct ExploreAddressDetailView: View {
    let address: String

    @EnvironmentObject var settings: SettingsManager
    @State private var stats: AddressAPIResponse?
    @State private var txs: [WalletTransaction] = []
    @State private var error: String?

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                if let stats {
                    content(stats)
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    ProgressView()
                        .scaleEffect(1.4)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Address")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            // Stats are the hard requirement; the tx page is best-effort, so a
            // tx-only failure still renders the balance instead of dropping the
            // whole screen to an error.
            async let statsResult = WalletAPIService.fetchAddressData(address: address)
            async let txResult = WalletAPIService.fetchTransactions(address: address)
            stats = try await statsResult
            txs = (try? await txResult) ?? []
            error = nil
        } catch {
            self.error = "Couldn't load this address."
        }
    }

    @ViewBuilder
    private func content(_ stats: AddressAPIResponse) -> some View {
        VStack(spacing: Theme.Spacing.xxl) {
            // Balance hero
            VStack(spacing: Theme.Spacing.sm) {
                Text("BALANCE")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(.secondary).tracking(2)
                Text(ExploreFormat.btc(sats: stats.balanceSats))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let fiat = ExploreFormat.fiat(sats: stats.balanceSats, settings: settings) {
                    Text(fiat).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 32)
            .padding(.horizontal, Theme.Spacing.xl)

            // Address
            Text(address)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: Theme.Spacing.lg)
                .padding(.horizontal, Theme.Spacing.xl)

            // Stats
            VStack(spacing: 0) {
                KeyValueRow(title: "Transactions", value: Formatters.formatAmount(stats.txCount))
                if stats.mempoolTxCount > 0 {
                    Divider()
                    KeyValueRow(title: "Pending", value: Formatters.formatAmount(stats.mempoolTxCount), valueColor: .orange)
                }
            }
            // padding: 0 so the row labels line up flush-left with the cards above.
            .card(padding: 0)
            .padding(.horizontal, Theme.Spacing.xl)

            // Transactions
            if !txs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("RECENT TRANSACTIONS")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(.secondary).tracking(1.5)
                        .padding(.horizontal, Theme.Spacing.xl)

                    VStack(spacing: 0) {
                        ForEach(Array(txs.enumerated()), id: \.element.txid) { index, tx in
                            if index > 0 { Divider() }
                            NavigationLink(value: ExploreRoute.tx(txid: tx.txid)) {
                                AddressTxRow(tx: tx, settings: settings)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .card(padding: 0)
                    .padding(.horizontal, Theme.Spacing.xl)

                    if stats.txCount > txs.count {
                        Text("Showing the latest \(txs.count) of \(Formatters.formatAmount(stats.txCount)).")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.horizontal, Theme.Spacing.xl)
                    }
                }
            }
        }
        .padding(.bottom, 40)
    }
}

// MARK: - Transaction row

private struct AddressTxRow: View {
    let tx: WalletTransaction
    let settings: SettingsManager

    private enum Direction { case received, sent, neutral }

    /// Net delta to this address. Exactly zero (e.g. a CoinJoin / batched tx whose
    /// fee is paid from foreign inputs) is its own neutral case — never a green
    /// "Received 0.00".
    private var direction: Direction {
        if tx.valueSats > 0 { return .received }
        if tx.valueSats < 0 { return .sent }
        return .neutral
    }
    private var tint: Color {
        switch direction {
        case .received: return Theme.Accent.up
        case .sent: return Theme.Accent.down
        case .neutral: return .secondary
        }
    }
    private var icon: String {
        switch direction {
        case .received: return "arrow.down.left"
        case .sent: return "arrow.up.right"
        case .neutral: return "arrow.left.arrow.right"
        }
    }
    private var label: String {
        switch direction {
        case .received: return "Received"
        case .sent: return "Sent"
        case .neutral: return "Self-transfer"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout).fontWeight(.medium)
                Text(tx.confirmed ? confirmedDate : "Pending")
                    .font(.caption2)
                    .foregroundStyle(tx.confirmed ? .secondary : Color.orange)
            }

            Spacer(minLength: Theme.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ExploreFormat.btc(sats: abs(tx.valueSats)))
                    .font(.system(.callout, design: .rounded)).fontWeight(.semibold)
                    .monospacedDigit()
                if let fiat = ExploreFormat.fiat(sats: abs(tx.valueSats), settings: settings) {
                    Text(fiat).font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
        .contentShape(Rectangle())
    }

    private var confirmedDate: String {
        guard let time = tx.blockTime else { return "Confirmed" }
        return Date(timeIntervalSince1970: TimeInterval(time)).formatted(date: .abbreviated, time: .omitted)
    }
}

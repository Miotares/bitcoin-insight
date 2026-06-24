//
//  ExploreTxDetailView.swift
//  BitcoinWidgets
//
//  Transaction detail for the Explore tab. One fetch on appear; confirmation
//  depth uses the tip height the Dashboard already polls. Inputs and outputs
//  link onward to their addresses (in-memory only — nothing is saved).
//

import SwiftUI

struct ExploreTxDetailView: View {
    let txid: String

    @EnvironmentObject var settings: SettingsManager
    @State private var tx: TxDetail?
    @State private var error: String?

    private let ioLimit = 12

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                if let tx {
                    content(tx)
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
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            tx = try await ExploreService.fetchTx(txid: txid)
            error = nil
        } catch let e where ExploreService.isNotFound(e) {
            self.error = "No transaction found with this ID."
        } catch {
            self.error = "Couldn't load — check your connection and try again."
        }
    }

    private func confirmations(_ tx: TxDetail) -> Int? {
        let tip = settings.observedBlockHeight
        guard tx.status.confirmed, tip > 0, let height = tx.status.block_height, tip >= height else { return nil }
        return tip - height + 1
    }

    @ViewBuilder
    private func content(_ tx: TxDetail) -> some View {
        VStack(spacing: Theme.Spacing.xxl) {
            statusHeader(tx)
            statsCard(tx)
            ioSection(title: "INPUTS", count: tx.vin.count, rows: inputRows(tx))
            ioSection(title: "OUTPUTS", count: tx.vout.count, rows: outputRows(tx))

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("TRANSACTION ID")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(.secondary).tracking(1.5)
                Text(txid)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Theme.Spacing.lg)
            .padding(.horizontal, Theme.Spacing.xl)
        }
        .padding(.bottom, 40)
    }

    private func statusHeader(_ tx: TxDetail) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            if tx.isCoinbase {
                GlowBadge(title: "Coinbase · newly minted bitcoin", systemImage: "hammer.fill")
                    .padding(.bottom, Theme.Spacing.xs)
            }
            if let confirmations = confirmations(tx) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.green)
                Text(confirmations == 1 ? "1 confirmation" : "\(Formatters.formatAmount(confirmations)) confirmations")
                    .font(.headline)
                if let time = tx.status.block_time {
                    Text(Date(timeIntervalSince1970: TimeInterval(time)).formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if tx.status.confirmed {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.green)
                Text("Confirmed").font(.headline)
            } else {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.orange)
                Text("In mempool").font(.headline)
                Text("Waiting for confirmation")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 32)
    }

    private func statsCard(_ tx: TxDetail) -> some View {
        VStack(spacing: 0) {
            KeyValueRow(title: "Amount", value: ExploreFormat.btc(sats: tx.outputTotal))
            if let fiat = ExploreFormat.fiat(sats: tx.outputTotal, settings: settings) {
                KeyValueRow(title: "Value", value: fiat, valueColor: .secondary)
            }
            Divider()
            if let fee = tx.fee {
                KeyValueRow(title: "Fee", value: Formatters.formatSats(fee))
                KeyValueRow(title: "Fee rate", value: String(format: "%.1f sat/vB", tx.feeRate), valueColor: feeColor(tx.feeRate))
                Divider()
            }
            KeyValueRow(title: "Size", value: "\(Formatters.formatAmount(tx.size)) B")
            KeyValueRow(title: "Virtual size", value: "\(Formatters.formatAmount(tx.vsize)) vB")
        }
        // padding: 0 so the row labels line up flush-left with the section headers / I-O rows.
        .card(padding: 0)
        .padding(.horizontal, Theme.Spacing.xl)
    }

    // MARK: - Inputs / outputs

    private func inputRows(_ tx: TxDetail) -> [IORowData] {
        if tx.isCoinbase {
            return [IORowData(address: nil, valueSats: 0, isCoinbase: true)]
        }
        return tx.vin.prefix(ioLimit).map {
            IORowData(address: $0.prevout?.scriptpubkey_address, valueSats: $0.prevout?.value ?? 0, isCoinbase: false)
        }
    }

    private func outputRows(_ tx: TxDetail) -> [IORowData] {
        tx.vout.prefix(ioLimit).map {
            IORowData(address: $0.scriptpubkey_address, valueSats: $0.value, isCoinbase: false)
        }
    }

    @ViewBuilder
    private func ioSection(title: String, count: Int, rows: [IORowData]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("\(title) · \(count)")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.secondary).tracking(1.5)
                .padding(.horizontal, Theme.Spacing.xl)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider() }
                    TxIORow(row: row, settings: settings)
                }
                if count > rows.count {
                    Divider()
                    Text("+ \(count - rows.count) more")
                        .font(.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.md)
                        .padding(.horizontal, Theme.Spacing.lg)
                }
            }
            .card(padding: 0)
            .padding(.horizontal, Theme.Spacing.xl)
        }
    }

    private func feeColor(_ rate: Double) -> Color {
        switch rate {
        case ..<10: return Theme.Accent.feeLow
        case ..<50: return Theme.Accent.feeMid
        default: return Theme.Accent.feeHigh
        }
    }
}

// MARK: - Single input/output row

/// One input or output line. Top-level `private` (file-scoped) so the row view
/// below can reference it.
private struct IORowData: Identifiable {
    let id = UUID()
    let address: String?
    let valueSats: Int
    let isCoinbase: Bool
}

private struct TxIORow: View {
    let row: IORowData
    let settings: SettingsManager

    var body: some View {
        if let address = row.address {
            NavigationLink(value: ExploreRoute.address(address)) {
                rowBody(address: address)
            }
            .buttonStyle(.plain)
        } else {
            rowBody(address: nil)
        }
    }

    @ViewBuilder
    private func rowBody(address: String?) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                if row.isCoinbase {
                    Text("Newly generated coins")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Coinbase")
                        .font(.caption2).foregroundStyle(.tertiary)
                } else if let address {
                    Text(ExploreFormat.middleTruncate(address))
                        .font(.system(.callout, design: .monospaced))
                        .lineLimit(1)
                    if let fiat = ExploreFormat.fiat(sats: row.valueSats, settings: settings) {
                        Text(fiat).font(.caption2).foregroundStyle(.tertiary)
                    }
                } else {
                    Text("Unparsed script")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Theme.Spacing.sm)
            if !row.isCoinbase {
                Text(ExploreFormat.btc(sats: row.valueSats))
                    .font(.system(.callout, design: .rounded)).fontWeight(.semibold)
                    .monospacedDigit()
            }
            if row.address != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
        .contentShape(Rectangle())
    }
}

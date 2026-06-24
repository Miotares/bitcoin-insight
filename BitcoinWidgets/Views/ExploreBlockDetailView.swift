//
//  ExploreBlockDetailView.swift
//  BitcoinWidgets
//
//  Block detail for the Explore tab. Fetches one enriched block on appear
//  (reusing the shared `BlockData` decoder and `BlockStatCard`), and reads the
//  confirmation depth from the tip height the Dashboard already polls — so no
//  extra request just to show "N confirmations".
//

import SwiftUI

struct ExploreBlockDetailView: View {
    let hash: String

    @EnvironmentObject var settings: SettingsManager
    @State private var block: BlockData?
    @State private var error: String?

    // On-demand transaction list (loaded only when the user expands it).
    @State private var txs: [TxDetail] = []
    @State private var txExpanded = false
    @State private var txLoading = false
    @State private var txExhausted = false
    @State private var txLoadError = false

    // Drives the golden glow behind a special block's height.
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                if let block {
                    content(block)
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
        .navigationTitle("Block")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            block = try await ExploreService.fetchBlock(hash: hash)
            error = nil
        } catch let e where ExploreService.isNotFound(e) {
            self.error = "No block found with this hash."
        } catch {
            self.error = "Couldn't load — check your connection and try again."
        }
    }

    private func loadMoreTxs() async {
        guard !txLoading, !txExhausted else { return }
        txLoading = true
        txLoadError = false
        defer { txLoading = false }
        do {
            let page = try await ExploreService.fetchBlockTxs(hash: hash, startIndex: txs.count)
            if page.isEmpty {
                txExhausted = true
            } else {
                txs.append(contentsOf: page)
                if page.count < 25 { txExhausted = true }
            }
        } catch {
            // Transient (timeout / 429 / connectivity) — keep txExhausted false so
            // the user can retry instead of silently losing the rest of the block.
            txLoadError = true
        }
    }

    private static let goldGradient = LinearGradient(
        colors: [
            Color(red: 1.00, green: 0.88, blue: 0.45),
            Color(red: 0.97, green: 0.74, blue: 0.22),
            Color(red: 0.85, green: 0.55, blue: 0.12)
        ],
        startPoint: .top, endPoint: .bottom
    )

    private var confirmations: Int? {
        let tip = settings.observedBlockHeight
        guard tip > 0, let height = block?.height, tip >= height else { return nil }
        return tip - height + 1
    }

    @ViewBuilder
    private func content(_ block: BlockData) -> some View {
        VStack(spacing: Theme.Spacing.xxl) {
            // Hero
            let special = SpecialBlock.for(height: block.height)
            VStack(spacing: Theme.Spacing.sm) {
                Text("BLOCK HEIGHT")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(.secondary).tracking(2)
                Text("\(block.height)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(special?.gold == true ? AnyShapeStyle(Self.goldGradient) : AnyShapeStyle(Color.primary))
                    .background {
                        if let special {
                            Circle()
                                .fill(special.tint)
                                .frame(width: 180, height: 180)
                                .blur(radius: 70)
                                .opacity(glowPulse ? 0.55 : 0.28)
                                .animation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true), value: glowPulse)
                        }
                    }
                Text(Date(timeIntervalSince1970: block.timestamp).formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let confirmations {
                    Text(confirmations == 1 ? "1 confirmation" : "\(Formatters.formatAmount(confirmations)) confirmations")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(Color.bitcoinOrange)
                        .padding(.top, 2)
                }
                if let special {
                    SpecialBlockBadge(special: special)
                        .padding(.top, Theme.Spacing.sm)
                }
            }
            .padding(.top, 32)
            .onAppear { glowPulse = true }

            // Stats grid (reuses BlockStatCard from the Dashboard block screen)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Spacing.lg),
                                GridItem(.flexible(), spacing: Theme.Spacing.lg)],
                      spacing: Theme.Spacing.lg) {
                BlockStatCard(title: "Transactions", value: Formatters.formatAmount(block.tx_count))
                BlockStatCard(title: "Size", value: Formatters.formatBytesToMB(block.size) + " MB")
                BlockStatCard(title: "Weight", value: Formatters.formatBytesToMB(block.weight) + " MWU")
                BlockStatCard(title: "Difficulty", value: Formatters.formatDifficulty(block.difficulty))
            }
            .padding(.horizontal, Theme.Spacing.xl)

            // Mining & financials
            VStack(spacing: 0) {
                if let pool = block.pool {
                    KeyValueRow(title: "Mined by", value: pool)
                    Divider()
                }
                KeyValueRow(title: "Block Reward", value: Formatters.formatBTC(Double(block.reward) / 100_000_000.0))
                Divider()
                KeyValueRow(title: "Total Volume", value: String(format: "%.2f BTC", Double(block.total_out) / 100_000_000.0))
                Divider()
                KeyValueRow(title: "Total Fees", value: Formatters.formatBTC(Double(block.totalFees) / 100_000_000.0))
                if let median = block.medianFee {
                    Divider()
                    KeyValueRow(title: "Median Fee", value: "\(Int(median.rounded())) sat/vB")
                }
            }
            // padding: 0 so the row labels line up flush-left with the stat grid above.
            .card(padding: 0)
            .padding(.horizontal, Theme.Spacing.xl)

            // Transactions (on-demand)
            transactionsSection(block)

            // Hash
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("BLOCK HASH")
                    .font(.caption2).fontWeight(.bold)
                    .foregroundStyle(.secondary).tracking(1.5)
                Text(hash)
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

    @ViewBuilder
    private func transactionsSection(_ block: BlockData) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("TRANSACTIONS · \(Formatters.formatAmount(block.tx_count))")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.secondary).tracking(1.5)
                .padding(.horizontal, Theme.Spacing.xl)

            if !txExpanded {
                Button {
                    txExpanded = true
                    Task { await loadMoreTxs() }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet.rectangle")
                        Text("View transactions")
                        Spacer()
                        Image(systemName: "chevron.down").font(.caption)
                    }
                    .font(.callout).fontWeight(.medium)
                    .foregroundStyle(Color.bitcoinOrange)
                    .padding(.vertical, Theme.Spacing.md)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .card(padding: 0)
                .padding(.horizontal, Theme.Spacing.xl)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(txs.enumerated()), id: \.element.txid) { index, tx in
                        if index > 0 { Divider() }
                        NavigationLink(value: ExploreRoute.tx(txid: tx.txid)) {
                            BlockTxRow(tx: tx)
                        }
                        .buttonStyle(.plain)
                    }
                    if txLoading && txs.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.lg)
                    } else if txLoadError {
                        if !txs.isEmpty { Divider() }
                        Button {
                            Task { await loadMoreTxs() }
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "arrow.clockwise")
                                Text("Couldn't load — Retry")
                                Spacer()
                            }
                            .font(.callout)
                            .foregroundStyle(Color.bitcoinOrange)
                            .padding(.vertical, Theme.Spacing.md)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(txLoading)
                    } else if !txExhausted && txs.count < block.tx_count {
                        Divider()
                        Button {
                            Task { await loadMoreTxs() }
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                if txLoading { ProgressView() } else { Image(systemName: "plus.circle") }
                                Text(txLoading ? "Loading…" : "Load 25 more")
                                Spacer()
                            }
                            .font(.callout)
                            .foregroundStyle(Color.bitcoinOrange)
                            .padding(.vertical, Theme.Spacing.md)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(txLoading)
                    }
                }
                .card(padding: 0)
                .padding(.horizontal, Theme.Spacing.xl)
            }
        }
    }
}

// MARK: - Block transaction row

private struct BlockTxRow: View {
    let tx: TxDetail

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: tx.isCoinbase ? "hammer.fill" : "arrow.left.arrow.right")
                .font(.caption2)
                .foregroundStyle(tx.isCoinbase ? Color.bitcoinOrange : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.isCoinbase ? "Coinbase" : ExploreFormat.middleTruncate(tx.txid, lead: 8, tail: 8))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(tx.isCoinbase ? Color.bitcoinOrange : .primary)
                    .lineLimit(1)
                if !tx.isCoinbase, tx.fee != nil {
                    Text(String(format: "%.1f sat/vB", tx.feeRate))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(ExploreFormat.btc(sats: tx.outputTotal))
                .font(.system(.caption, design: .rounded)).fontWeight(.semibold)
                .monospacedDigit()

            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
        .contentShape(Rectangle())
    }
}

//
//  WalletTabView.swift
//  BitcoinWidgets
//

import SwiftUI

struct WalletTabView: View {
    @StateObject private var viewModel = WalletViewModel()
    @EnvironmentObject var settings: SettingsManager
    @State private var showAddWallet = false
    @State private var isReordering = false

    private var totalBTC: Double { Double(viewModel.totalBalanceSats) / 100_000_000.0 }
    /// True whenever at least one wallet is actively syncing.
    private var isAnySyncing: Bool { viewModel.wallets.contains(where: \.isSyncing) }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                if isReordering {
                    reorderList
                } else {
                    normalContent
                }
            }
            .navigationTitle("Wallet")
            .toolbar {
                if isReordering {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            Haptics.selection()
                            withAnimation { isReordering = false }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.bitcoinOrange)
                    }
                } else {
                    // Reorder only available when 2+ wallets AND no active sync.
                    // A sync pushes Combine updates into the List's ForEach which
                    // corrupts SwiftUI's editMode diff and causes the stuck-reorder bug.
                    if viewModel.wallets.count > 1 && !isAnySyncing {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                Haptics.selection()
                                isReordering = true
                            } label: {
                                Image(systemName: "arrow.up.arrow.down.circle")
                                    .font(.title3)
                                    .foregroundStyle(Color.bitcoinOrange)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Haptics.selection()
                            showAddWallet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Color.bitcoinOrange)
                        }
                    }
                }
            }
            // Auto-exit reorder mode if a sync starts mid-reorder.
            // Combine updates to a List in editMode cause SwiftUI to get stuck.
            .onChange(of: isAnySyncing) { _, syncing in
                if syncing && isReordering {
                    withAnimation { isReordering = false }
                }
            }
            // Auto-exit if wallet count drops to 1 or 0 (edge case: concurrent removal).
            .onChange(of: viewModel.wallets.count) { _, count in
                if count <= 1 && isReordering {
                    withAnimation { isReordering = false }
                }
            }
            .sheet(isPresented: $showAddWallet) {
                AddWalletView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Normal Content

    private var normalContent: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                if viewModel.wallets.isEmpty {
                    emptyState
                } else {
                    balanceHeroCard

                    if let error = viewModel.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    viewModel.errorMessage = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                        }
                        .padding(14)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 20)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    ForEach(viewModel.wallets) { wallet in
                        NavigationLink(destination: WalletDetailView(wallet: wallet, viewModel: viewModel)) {
                            WalletCard(wallet: wallet, viewModel: viewModel, currency: settings.preferredCurrency)
                        }
                        .buttonStyle(CardButtonStyle())
                        .padding(.horizontal, 20)
                    }
                }

                Spacer(minLength: 20)
            }
        }
        .scrollContentBackground(.hidden)
        .refreshable {
            await viewModel.refreshAll()
        }
    }

    // MARK: - Reorder List

    private var reorderList: some View {
        VStack(spacing: 0) {
            // Balance card lives OUTSIDE the List — identical size to normal mode,
            // never affected by editMode, numbers can't be selected.
            balanceHeroCard
                .padding(.top, 8)
                .textSelection(.disabled)

            HStack {
                Spacer()
                Label("Hold & drag to reorder", systemImage: "arrow.up.arrow.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 2)

            List {
                ForEach(viewModel.wallets) { wallet in
                    WalletCard(wallet: wallet, viewModel: viewModel, currency: settings.preferredCurrency)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .textSelection(.disabled)
                }
                .onMove { from, to in
                    // Last-resort guard: discard moves if a sync slipped through
                    // (e.g. a background task started between the button check and now).
                    guard !isAnySyncing else { return }
                    Haptics.trigger(.light)
                    viewModel.moveWallet(from: from, to: to)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
    }

    // MARK: - Balance Hero Card

    private var balanceHeroCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel("Total Balance")

            Text(Formatters.formatBTC(totalBTC))
                .font(.heroValue)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: totalBTC)

            if viewModel.totalBalanceFiat > 0 {
                Text(Formatters.formatCurrency(
                    value: viewModel.totalBalanceFiat,
                    currencyCode: settings.preferredCurrency
                ))
                .font(.title3)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: viewModel.totalBalanceFiat)
            }

            if viewModel.wallets.contains(where: \.isSyncing) {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Syncing wallets…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Keep the app open.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 120)

            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.bitcoinOrange.opacity(0.7))

            VStack(spacing: 8) {
                Text("No Wallets Yet")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("Add an xpub, ypub, zpub, or a single Bitcoin address to track your balance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                Haptics.selection()
                showAddWallet = true
            } label: {
                Label("Add Wallet", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(Color.bitcoinOrange)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Wallet Card

struct WalletCard: View {
    let wallet: Wallet
    @ObservedObject var viewModel: WalletViewModel
    let currency: String

    private var btcBalance: Double { Double(wallet.totalBalanceSats) / 100_000_000.0 }
    private var fiatValue: Double {
        btcBalance * SettingsManager.shared.displayPrice(for: currency)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Text(wallet.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                if wallet.isSyncing {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Syncing")
                            .font(.caption2)
                            .foregroundStyle(Color.bitcoinOrange)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(wallet.type.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Divider()

            // Balance
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Formatters.formatBTC(btcBalance))
                        .font(.system(.title3, design: .rounded))
                        .fontWeight(.bold)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: btcBalance)

                    Text(Formatters.formatCurrency(value: fiatValue, currencyCode: currency))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: fiatValue)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(wallet.addresses.count) addr")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(wallet.transactions.count) tx")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background(Theme.Surface.fill)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

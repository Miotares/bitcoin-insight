//
//  WalletDetailView.swift
//  BitcoinWidgets
//

import SwiftUI

struct WalletDetailView: View {
    let wallet: Wallet                  // initial value — use currentWallet for live data
    @ObservedObject var viewModel: WalletViewModel
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0
    @State private var showDeleteAlert = false
    @State private var showRenameAlert = false
    @State private var renameText = ""
    @State private var copiedTxID: String? = nil
    @State private var copiedAddress: String? = nil
    @State private var txCopyTask: Task<Void, Never>? = nil
    @State private var addrCopyTask: Task<Void, Never>? = nil
    @State private var txDisplayLimit: Int = 25
    @State private var addrDisplayLimit: Int = 25

    /// Always reflects the latest state from the view model.
    private var currentWallet: Wallet {
        viewModel.wallets.first { $0.id == wallet.id } ?? wallet
    }

    private var btcBalance: Double { Double(currentWallet.totalBalanceSats) / 100_000_000.0 }

    private var fiatValue: Double {
        btcBalance * settings.displayPrice(for: settings.preferredCurrency)
    }

    var body: some View {
        ZStack {
            AnimatedBackgroundView()

            ScrollView {
                VStack(spacing: 20) {

                    // MARK: - Sync Banner
                    if currentWallet.isSyncing {
                        let isFirstScan = currentWallet.addresses.isEmpty
                        HStack(spacing: 10) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(Color.bitcoinOrange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isFirstScan ? "Scanning wallet…" : "Checking for new activity…")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(isFirstScan
                                     ? "First scan — this can take a while. Keep the app open."
                                     : "Updating balance and transactions.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(14)
                        .background(Color.bitcoinOrange.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.bitcoinOrange.opacity(0.3), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                    }

                    // MARK: - Balance Card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(currentWallet.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if settings.hideBalances {
                                Image(systemName: settings.balancesHidden ? "eye.slash.fill" : "eye.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            if let scanned = currentWallet.lastScanned {
                                Text("Updated \(scanned, format: .relative(presentation: .named))")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        Text(Formatters.formatBTC(btcBalance))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .balanceBlur(hidden: settings.balancesHidden)

                        Text(Formatters.formatCurrency(value: fiatValue, currencyCode: settings.preferredCurrency))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                            .balanceBlur(hidden: settings.balancesHidden)

                        Divider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Addresses")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(currentWallet.addresses.count)")
                                    .font(.headline)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Transactions")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(currentWallet.transactions.count)")
                                    .font(.headline)
                            }
                            Spacer()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sats")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(Formatters.formatSats(currentWallet.totalBalanceSats))
                                    .font(.headline)
                                    .balanceBlur(hidden: settings.balancesHidden)
                            }
                        }
                    }
                    .card(padding: Theme.Spacing.xl)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard settings.hideBalances else { return }
                        Haptics.selection()
                        settings.balancesRevealed.toggle()
                    }
                    .padding(.horizontal)

                    // MARK: - Tab Selector
                    HStack(spacing: 0) {
                        ForEach(["Transactions", "Addresses"], id: \.self) { tab in
                            let idx = tab == "Transactions" ? 0 : 1
                            Button {
                                withAnimation(.spring(response: 0.3)) { selectedTab = idx }
                            } label: {
                                Text(tab)
                                    .font(.subheadline)
                                    .fontWeight(selectedTab == idx ? .semibold : .regular)
                                    .foregroundStyle(selectedTab == idx ? .primary : .secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        selectedTab == idx
                                            ? Color.secondary.opacity(0.2)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .background(Theme.Surface.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal)

                    // MARK: - Content
                    if selectedTab == 0 {
                        transactionsSection
                    } else {
                        addressesSection
                    }

                    Spacer(minLength: 20)
                }
                .padding(.top, 8)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(currentWallet.name)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await viewModel.refreshSingle(currentWallet)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if currentWallet.isSyncing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(Color.bitcoinOrange)
                    }
                    if settings.hideBalances {
                        Button {
                            Haptics.selection()
                            settings.balancesRevealed.toggle()
                        } label: {
                            Image(systemName: settings.balancesHidden ? "eye.slash" : "eye")
                                .font(.title3)
                                .foregroundStyle(Color.bitcoinOrange)
                        }
                    }
                    Menu {
                        Button {
                            renameText = currentWallet.name
                            showRenameAlert = true
                        } label: {
                            Label("Rename Wallet", systemImage: "pencil")
                        }

                        Button {
                            viewModel.rescanWallet(currentWallet)
                        } label: {
                            Label("Full Rescan", systemImage: "arrow.clockwise")
                        }
                        .disabled(currentWallet.isSyncing)

                        Divider()

                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            Label("Delete Wallet", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(Color.bitcoinOrange)
                    }
                }
            }
        }
        .alert("Delete \"\(currentWallet.name)\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                viewModel.removeWallet(currentWallet)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All locally stored data for this wallet will be removed. Your Bitcoin is not affected.")
        }
        .alert("Rename Wallet", isPresented: $showRenameAlert) {
            TextField("Wallet name", text: $renameText)
            Button("Save") {
                viewModel.renameWallet(currentWallet, newName: renameText)
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Transactions Section

    @ViewBuilder
    private var transactionsSection: some View {
        let sorted = currentWallet.sortedTransactions
        if sorted.isEmpty {
            ContentUnavailableView(
                "No Transactions",
                systemImage: "list.bullet.rectangle",
                description: Text(currentWallet.isSyncing ? "Syncing…" : "Pull to refresh to scan for transactions")
            )
            .padding(.top, 40)
        } else {
            let visible = Array(sorted.prefix(txDisplayLimit))
            let remaining = sorted.count - visible.count

            LazyVStack(spacing: 0) {
                ForEach(visible) { tx in
                    TransactionRowView(
                        tx: tx,
                        currency: settings.preferredCurrency,
                        btcPrice: pricePerBtc,
                        showCopied: copiedTxID == tx.txid,
                        hidden: settings.balancesHidden
                    )
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = tx.txid
                        Haptics.notification(.success)
                        txCopyTask?.cancel()
                        copiedTxID = tx.txid
                        txCopyTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            guard !Task.isCancelled else { return }
                            copiedTxID = nil
                        }
                    }

                    // Divider between rows, and between last row and the "Show more" button
                    if tx.txid != visible.last?.txid || remaining > 0 {
                        Divider()
                            .padding(.leading, 74)
                            .padding(.horizontal, 20)
                    }
                }

                if remaining > 0 {
                    Button {
                        Haptics.selection()
                        txDisplayLimit += 25
                    } label: {
                        HStack {
                            Label("Show \(min(remaining, 25)) more", systemImage: "chevron.down.circle")
                            Spacer()
                            Text("\(remaining) remaining")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardSurface()
            .padding(.horizontal)
        }
    }

    // MARK: - Addresses Section

    @ViewBuilder
    private var addressesSection: some View {
        let allAddresses = currentWallet.addresses
        if allAddresses.isEmpty {
            ContentUnavailableView(
                "No Addresses Found",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text(currentWallet.isSyncing ? "Syncing…" : "Pull to refresh to scan for addresses")
            )
            .padding(.top, 40)
        } else {
            let visible = Array(allAddresses.prefix(addrDisplayLimit))
            let remaining = allAddresses.count - visible.count

            LazyVStack(spacing: 0) {
                ForEach(visible) { addr in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if let chain = addr.chain {
                                    Text(chain == 0 ? "External" : "Change")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(chain == 0 ? Color.blue.opacity(0.15) : Color.purple.opacity(0.15))
                                        .foregroundStyle(chain == 0 ? .blue : .purple)
                                        .clipShape(Capsule())
                                }
                                if let idx = addr.derivationIndex {
                                    Text("m/\(addr.chain ?? 0)/\(idx)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            ZStack(alignment: .leading) {
                                Text("Copied to clipboard")
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                                    .opacity(copiedAddress == addr.address ? 1 : 0)
                                Text(addr.address)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundStyle(.secondary)
                                    .opacity(copiedAddress == addr.address ? 0 : 1)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .animation(.easeInOut(duration: 0.2), value: copiedAddress)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(Formatters.formatSats(addr.balanceSats))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .balanceBlur(hidden: settings.balancesHidden)
                            Text("\(addr.txCount) tx")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .opacity(addr.balanceSats > 0 ? 1.0 : 0.45)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIPasteboard.general.string = addr.address
                        Haptics.notification(.success)
                        addrCopyTask?.cancel()
                        copiedAddress = addr.address
                        addrCopyTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            guard !Task.isCancelled else { return }
                            copiedAddress = nil
                        }
                    }

                    if addr.id != visible.last?.id || remaining > 0 {
                        Divider()
                            .padding(.horizontal, 20)
                    }
                }

                if remaining > 0 {
                    Button {
                        Haptics.selection()
                        addrDisplayLimit += 25
                    } label: {
                        HStack {
                            Label("Show \(min(remaining, 25)) more", systemImage: "chevron.down.circle")
                            Spacer()
                            Text("\(remaining) remaining")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardSurface()
            .padding(.horizontal)
        }
    }

    private var pricePerBtc: Double {
        settings.displayPrice(for: settings.preferredCurrency)
    }
}

//
//  ExploreView.swift
//  BitcoinWidgets
//
//  The Explore tab: a calm, native, tracking-free block explorer. Search any
//  block / transaction / address, and watch the chain advance live. The live
//  feed is push-based (websocket) and only runs while this tab is on screen.
//

import SwiftUI

struct ExploreView: View {
    @StateObject private var vm = ExploreViewModel()
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [ExploreRoute] = []
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    /// The live feed should only run while Explore is the selected tab AND the app
    /// is foregrounded. TabView builds the view eagerly and does NOT fire
    /// .onDisappear on a tab switch, so we can't rely on appear/disappear alone.
    private var isExploreActive: Bool {
        router.selectedTab == AppRouter.exploreTab && scenePhase == .active
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(spacing: Theme.Spacing.xxl) {
                        searchBar
                        blockFeed
                    }
                    .padding(.vertical, Theme.Spacing.lg)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                // Tap anywhere outside the field dismisses the keyboard. Row
                // NavigationLinks keep priority, so block taps still navigate.
                .onTapGesture { searchFocused = false }
            }
            .navigationTitle("Explore")
            .navigationDestination(for: ExploreRoute.self) { route in
                switch route {
                case .block(let hash): ExploreBlockDetailView(hash: hash)
                case .tx(let txid): ExploreTxDetailView(txid: txid)
                case .address(let address): ExploreAddressDetailView(address: address)
                }
            }
        }
        .onAppear {
            if isExploreActive { vm.onAppear() }
            consumePendingRoute()
        }
        .onDisappear { vm.onDisappear() }
        .onChange(of: router.selectedTab) { _, _ in syncLiveness() }
        .onChange(of: scenePhase) { _, _ in syncLiveness() }
        .onChange(of: router.pendingExploreRoute) { _, _ in
            consumePendingRoute()
        }
    }

    /// Push a deep-link route handed over from another tab (e.g. the Dashboard's
    /// "See in Explorer"), then clear it. Replaces the stack rather than appending,
    /// so the deep-link lands on a clean detail whose Back returns to the Explore
    /// root — and repeated jumps don't pile up.
    private func consumePendingRoute() {
        guard let route = router.pendingExploreRoute else { return }
        router.pendingExploreRoute = nil
        path = [route]
    }

    /// Start the live feed only while Explore is selected and foregrounded; tear it
    /// down the moment either stops being true, so no block is ingested off-screen
    /// (and no phantom haptic fires on another tab). Both VM calls are idempotent.
    private func syncLiveness() {
        if isExploreActive { vm.onAppear() } else { vm.onDisappear() }
    }

    // MARK: - Search

    private var searchBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Block, transaction, or address", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit(runSearch)
                    .foregroundStyle(.primary)

                // Fixed-size trailing slot so the pill never changes height when
                // the icon swaps (paste ↔ clear ↔ spinner) as you type.
                Group {
                    if vm.isSearching {
                        ProgressView()
                    } else if !query.isEmpty {
                        Button {
                            query = ""
                            vm.searchError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Paste & search: drop the clipboard in and look it up in one tap.
                        Button(action: pasteAndSearch) {
                            Image(systemName: "doc.on.clipboard")
                                .foregroundStyle(Color.bitcoinOrange)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 24, height: 24)
            }
            .frame(minHeight: 24)
            .card(padding: Theme.Spacing.lg)
            // Whole pill is the tap target → easier to focus / paste, not just the glyphs.
            .contentShape(Rectangle())
            .onTapGesture { searchFocused = true }

            if let error = vm.searchError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        // Editing the query dismisses a stale error so it doesn't read as if the
        // new, unsubmitted input is already wrong.
        .onChange(of: query) { _, _ in
            if vm.searchError != nil { vm.searchError = nil }
        }
    }

    private func runSearch() {
        let q = query
        // Cancel any in-flight search so the last submission wins (a slow height
        // lookup can't push a stale screen after a newer query superseded it).
        searchTask?.cancel()
        searchTask = Task {
            let route = await vm.resolve(q)
            guard !Task.isCancelled else { return }
            if let route {
                searchFocused = false
                path.append(route)
            }
        }
    }

    private func pasteAndSearch() {
        guard let raw = UIPasteboard.general.string?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        // Bound a pathological clipboard; the longest valid query (a bech32 address)
        // is well under 100 chars, so this never truncates a real lookup.
        query = String(raw.prefix(200))
        runSearch()
    }

    // MARK: - Live block feed

    private var blockFeed: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("LATEST BLOCKS")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                liveDot
                Spacer()
                if vm.isSeeding && vm.blocks.isEmpty {
                    ProgressView()
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)

            if vm.blocks.isEmpty && !vm.isSeeding {
                if vm.feedError != nil {
                    ErrorState(message: vm.feedError ?? "Couldn't load the latest blocks.") {
                        Task { await vm.seed() }
                    }
                } else {
                    Text("No blocks yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            } else {
                LazyVStack(spacing: Theme.Spacing.md) {
                    ForEach(vm.blocks) { block in
                        NavigationLink(value: ExploreRoute.block(hash: block.id)) {
                            RecentBlockRow(block: block)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .animation(.snappy, value: vm.blocks)
            }
        }
    }

    private var liveDot: some View {
        Circle()
            .fill(Color.green)
            .frame(width: 7, height: 7)
            .opacity(0.9)
    }
}

// MARK: - Block row

struct RecentBlockRow: View {
    let block: RecentBlock

    var body: some View {
        let special = SpecialBlock.for(height: block.height)
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill((special?.tint ?? Color.bitcoinOrange).opacity(0.15))
                Image(systemName: special?.icon ?? "cube.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(special?.tint ?? Color.bitcoinOrange)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(block.height)")
                    .font(.system(.headline, design: .rounded))
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
                Text("\(Formatters.formatAmount(block.txCount)) txs · \(Formatters.formatBytesToMB(block.size)) MB")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let pool = block.poolName {
                    Text(pool)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Theme.Spacing.sm)

            // Chevron on top (tap affordance), time + fee pushed to the bottom.
            VStack(alignment: .trailing, spacing: 3) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: Theme.Spacing.sm)
                Text(ExploreFormat.age(block.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let median = block.medianFee {
                    Text("~\(Int(median.rounded())) sat/vB")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .cardSurface()
    }
}

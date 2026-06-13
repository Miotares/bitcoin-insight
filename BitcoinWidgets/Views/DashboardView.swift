import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(spacing: Theme.Spacing.xxl) {
                        Text("Dashboard")
                            .font(.largeTitle).fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)

                        // Hero Price (box-less, typographic)
                        PriceHeroCard(
                            price: viewModel.livePrice,
                            currency: settings.preferredCurrency,
                            changeColor: viewModel.priceChangeColor
                        )
                        .padding(.horizontal)

                        // Main Stats Grid
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: Theme.Spacing.md),
                                GridItem(.flexible(), spacing: Theme.Spacing.md)
                            ],
                            spacing: Theme.Spacing.md
                        ) {
                            BlockHeightStatCard(
                                value: viewModel.blockHeight,
                                destination: BlockHeightDetailView()
                            )

                            StatCard(
                                title: "Mempool",
                                value: Formatters.formatAmount(viewModel.mempoolTransactions),
                                subtitle: "txs"
                            ) { MempoolDetailView() }

                            StatCard(
                                title: "Difficulty",
                                value: Formatters.formatDifficulty(viewModel.difficulty)
                            ) { DifficultyDetailView() }

                            StatCard(
                                title: "Hashrate",
                                value: Formatters.formatHashrate(viewModel.hashrate)
                            ) { HashrateDetailView() }
                        }
                        .padding(.horizontal)

                        FeeRowView(fees: viewModel.fees)
                            .padding(.horizontal)

                        if viewModel.moscowTime > 0 {
                            MoscowTimeWidget(moscowTime: viewModel.moscowTime)
                                .padding(.horizontal)
                        }

                        if viewModel.circulatingSupply > 0 {
                            NavigationLink(destination: CirculatingSupplyDetailView()) {
                                CirculatingSupplyWidget(
                                    supply: viewModel.circulatingSupply,
                                    percent: viewModel.circulatingSupplyPercent
                                )
                                .padding(.horizontal)
                            }
                            .buttonStyle(CardButtonStyle())
                        }

                        HalvingCard(
                            blocksRemaining: viewModel.blocksRemainingToHalving,
                            progress: viewModel.halvingProgress
                        )
                        .padding(.horizontal)

                        LightningCard(
                            channels: viewModel.lightningChannelCount,
                            nodes: viewModel.lightningNodeCount,
                            capacity: viewModel.lightningCapacity
                        )
                        .padding(.horizontal)

                        if !viewModel.feePercentiles.isEmpty {
                            FeeDistributionWidget(fees: viewModel.feePercentiles, feeThresholds: viewModel.fees)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: Theme.Spacing.xl)
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .scrollContentBackground(.hidden)
                .toolbar(.hidden, for: .navigationBar)
                .refreshable { await viewModel.refreshData() }
            }
            .onChange(of: settings.preferredCurrency) { _ in
                Task { await viewModel.refreshData() }
            }
        }
    }
}

// MARK: - Shared

/// Small uppercase, tracked section label (the app's only "header" treatment).
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.caption).fontWeight(.semibold).tracking(0.8)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct CardChevron: View {
    var body: some View {
        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
    }
}

// MARK: - Hero

struct PriceHeroCard: View {
    let price: Double
    let currency: String
    let changeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BTC / \(currency.uppercased())")
                .font(.caption).fontWeight(.semibold).tracking(0.8)
                .foregroundStyle(.secondary)

            Text(Formatters.formatCurrency(value: price, currencyCode: currency))
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .foregroundStyle(changeColor)
                .minimumScaleFactor(0.5).lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: price)
                .onChange(of: price) { _, _ in Haptics.trigger(.medium) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Stat tiles (flat)

struct StatCard<Destination: View>: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    SectionLabel(title)
                    Spacer()
                    CardChevron()
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.cardValue)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: value)
                        .onChange(of: value) { _, _ in Haptics.trigger() }
                    if let subtitle {
                        Text(subtitle).font(.unit).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(height: 96)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct BlockHeightStatCard<Destination: View>: View {
    let value: Int
    let destination: () -> Destination
    @State private var showPlusOne = false
    @State private var previousValue: Int

    init(value: Int, destination: @autoclosure @escaping () -> Destination) {
        self.value = value
        self.destination = destination
        self._previousValue = State(initialValue: value)
    }

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    SectionLabel("Block Height")
                    Spacer()
                    CardChevron()
                }
                Spacer(minLength: 0)
                ZStack(alignment: .leading) {
                    Text(Formatters.formatAmount(value))
                        .font(.cardValue)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                        .onChange(of: value) { _, _ in Haptics.notification(.success) }

                    if showPlusOne {
                        Text("+1")
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(Theme.Accent.up)
                            .offset(x: 80, y: -15)
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                removal: .opacity.combined(with: .move(edge: .top))
                            ))
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(height: 96)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(CardButtonStyle())
        .onChange(of: value) { newValue, oldValue in
            if newValue > oldValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { showPlusOne = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showPlusOne = false }
                }
            }
            previousValue = newValue
        }
    }
}

// MARK: - Fees

struct FeeRowView: View {
    let fees: FeeData
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionLabel("Network Fees")
            HStack(spacing: Theme.Spacing.lg) {
                FeeItem(title: "Low", value: fees.low, color: Theme.Accent.feeLow)
                FeeItem(title: "Medium", value: fees.medium, color: Theme.Accent.feeMid)
                FeeItem(title: "High", value: fees.high, color: Theme.Accent.feeHigh)
            }
        }
        .card()
    }
}

struct FeeItem: View {
    let title: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            AnimatedFeeText(value: value, color: color)
            Text("sat/vB").font(.unit).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AnimatedFeeText: View {
    let value: Int
    let color: Color
    @State private var direction: Int = 0

    var body: some View {
        Text("\(value)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(color)
            .id(value)
            .transition(.asymmetric(
                insertion: .move(edge: direction > 0 ? .bottom : .top).combined(with: .opacity),
                removal: .move(edge: direction > 0 ? .top : .bottom).combined(with: .opacity)
            ))
            .onChange(of: value) { newValue, oldValue in
                direction = newValue > oldValue ? 1 : -1
                Haptics.trigger()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
    }
}

// MARK: - Moscow Time

struct MoscowTimeWidget: View {
    let moscowTime: Int
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                SectionLabel("Moscow Time")
                Text("\(moscowTime)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: moscowTime)
                    .onChange(of: moscowTime) { _, _ in Haptics.trigger() }
            }
            Spacer()
            Text("sats / $").font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }
}

// MARK: - Circulating Supply

struct CirculatingSupplyWidget: View {
    let supply: Double
    let percent: Double
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack { SectionLabel("Circulating Supply"); Spacer(); CardChevron() }
            ProgressView(value: percent, total: 100)
                .tint(Theme.Accent.brand)
                .animation(.linear(duration: 1.0), value: percent)
            HStack {
                Text(Formatters.formatAmount(Int(supply)) + " BTC")
                    .font(.caption).fontWeight(.bold).contentTransition(.numericText())
                Spacer()
                Text(String(format: "%.2f%%", percent))
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(Theme.Accent.brand).contentTransition(.numericText())
            }
        }
        .card()
    }
}

// MARK: - Halving

struct HalvingCard: View {
    let blocksRemaining: Int
    let progress: Double
    var body: some View {
        NavigationLink(destination: HalvingDetailView()) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack { SectionLabel("Halving Countdown"); Spacer(); CardChevron() }
                ProgressView(value: progress)
                    .tint(Theme.Accent.brand)
                    .animation(.linear(duration: 1.0), value: progress)
                HStack {
                    Text("\(Formatters.formatAmount(blocksRemaining)) blocks left")
                        .font(.caption).fontWeight(.bold).contentTransition(.numericText())
                    Spacer()
                    Text(String(format: "%.2f%%", progress * 100))
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(Theme.Accent.brand).contentTransition(.numericText())
                }
            }
            .card()
        }
        .buttonStyle(CardButtonStyle())
    }
}

// MARK: - Lightning

struct LightningCard: View {
    let channels: Int
    let nodes: Int
    let capacity: Double
    var body: some View {
        NavigationLink(destination: LightningDetailView()) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack { SectionLabel("Lightning Network"); Spacer(); CardChevron() }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: Theme.Spacing.lg) {
                    LNStat(title: "Capacity", value: Formatters.formatLightningBTC(capacity / 100_000_000))
                    LNStat(title: "Nodes", value: Formatters.formatAmount(nodes))
                    LNStat(title: "Channels", value: Formatters.formatAmount(channels))
                }
            }
            .card()
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct LNStat: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.subheadline, design: .rounded).weight(.semibold))
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Fee Distribution

struct FeeDistributionWidget: View {
    let fees: [Double]
    let feeThresholds: FeeData

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                SectionLabel("Fee Distribution")
                Spacer()
                Text("Next Block").font(.caption).foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                let labels = ["10%", "25%", "50%", "75%", "90%"]
                let maxFee = fees.last ?? 1.0
                ForEach(0..<fees.count, id: \.self) { index in
                    let fee = fees[index]
                    let barHeight = CGFloat(fee / maxFee) * 80.0
                    VStack(spacing: 6) {
                        Text("<\(Int(fee))")
                            .font(.system(.caption, design: .monospaced)).fontWeight(.bold)
                            .contentTransition(.numericText())
                        RoundedRectangle(cornerRadius: 4)
                            .fill(barColor(for: fee).opacity(0.25))
                            .frame(height: max(10, barHeight))
                            .animation(.spring, value: barHeight)
                        Text(labels[index]).font(.unit).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Theme.Spacing.sm)

            Text("sat/vB").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .card()
    }

    private func barColor(for fee: Double) -> Color {
        let f = Int(fee)
        if f <= feeThresholds.low { return Theme.Accent.feeLow }
        if f <= feeThresholds.medium { return Theme.Accent.feeMid }
        return Theme.Accent.feeHigh
    }
}

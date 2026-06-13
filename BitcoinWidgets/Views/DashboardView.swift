import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(spacing: Theme.Spacing.xl) {
                        // Hero Price Card
                        PriceHeroCard(
                            price: viewModel.livePrice,
                            currency: settings.preferredCurrency,
                            changeColor: viewModel.priceChangeColor
                        )
                        .padding(.horizontal)

                        // Main Stats Grid
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: Theme.Spacing.lg),
                                GridItem(.flexible(), spacing: Theme.Spacing.lg)
                            ],
                            spacing: Theme.Spacing.lg
                        ) {
                            // Block Height with +1 Animation
                            BlockHeightStatCard(
                                value: viewModel.blockHeight,
                                destination: BlockHeightDetailView()
                            )

                            StatCard(
                                title: "Mempool",
                                value: Formatters.formatAmount(viewModel.mempoolTransactions),
                                subtitle: "txs",
                                icon: "list.bullet.rectangle.fill"
                            ) {
                                MempoolDetailView()
                            }

                            StatCard(
                                title: "Difficulty",
                                value: Formatters.formatDifficulty(viewModel.difficulty),
                                icon: "chart.line.uptrend.xyaxis"
                            ) {
                                DifficultyDetailView()
                            }

                            StatCard(
                                title: "Hashrate",
                                value: Formatters.formatHashrate(viewModel.hashrate),
                                icon: "cpu"
                            ) {
                                HashrateDetailView()
                            }
                        }
                        .padding(.horizontal)

                        // Fee Rates with Directional Animation
                        FeeRowView(fees: viewModel.fees)
                            .padding(.horizontal)

                        // Moscow Time Widget
                        if viewModel.moscowTime > 0 {
                            MoscowTimeWidget(moscowTime: viewModel.moscowTime)
                                .padding(.horizontal)
                        }

                        // Circulating Supply Widget
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

                        // Halving Countdown
                        HalvingCard(
                            blocksRemaining: viewModel.blocksRemainingToHalving,
                            progress: viewModel.halvingProgress
                        )
                        .padding(.horizontal)

                        // Lightning Network Stats
                        LightningCard(
                            channels: viewModel.lightningChannelCount,
                            nodes: viewModel.lightningNodeCount,
                            capacity: viewModel.lightningCapacity
                        )
                        .padding(.horizontal)

                        // Fee Distribution Widget
                        if !viewModel.feePercentiles.isEmpty {
                            FeeDistributionWidget(fees: viewModel.feePercentiles, feeThresholds: viewModel.fees)
                                .padding(.horizontal)
                        }

                        Spacer(minLength: Theme.Spacing.xl)
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Dashboard")
                .refreshable {
                    await viewModel.refreshData()
                }
            }
            .onChange(of: settings.preferredCurrency) { _ in
                Task {
                    await viewModel.refreshData()
                }
            }
        }
    }
}


// MARK: - Subviews

struct PriceHeroCard: View {
    let price: Double
    let currency: String
    let changeColor: Color
    @State private var flashColor: Color = .clear

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.title)
                    .foregroundStyle(Theme.Accent.brand)

                Text("Bitcoin")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(Formatters.formatCurrency(value: price, currencyCode: currency))
                .font(.heroValue)
                .foregroundStyle(changeColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: price)
                .onChange(of: price) { _, _ in
                    Haptics.trigger(.medium)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xxl)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Material.ultraThin)
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(flashColor)
                    .opacity(0.3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Stroke.hairline, lineWidth: 0.5)
        )
        .shadow(color: Theme.Shadow.cardColor, radius: Theme.Shadow.cardRadius, x: 0, y: Theme.Shadow.cardY)
        .onChange(of: price) { _, _ in
            if changeColor == Theme.Accent.up {
                flash(color: Theme.Accent.up)
            } else if changeColor == Theme.Accent.down {
                flash(color: Theme.Accent.down)
            }
        }
    }

    private func flash(color: Color) {
        withAnimation(.easeIn(duration: 0.2)) {
            flashColor = color
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.5)) {
                flashColor = .clear
            }
        }
    }
}

struct StatCard<Destination: View>: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(Theme.Accent.icon)
                        .font(.title3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(.cardLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                        Text(value)
                            .font(.cardValue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: value)
                            .onChange(of: value) { _, _ in
                                Haptics.trigger()
                            }

                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.unit)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(height: 110)
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
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(Theme.Accent.icon)
                        .font(.title3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Block Height")
                        .font(.cardLabel)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ZStack(alignment: .leading) {
                        Text(Formatters.formatAmount(value))
                            .font(.cardValue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                            .onChange(of: value) { _, _ in
                                Haptics.notification(.success)
                            }

                        if showPlusOne {
                            Text("+1")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.Accent.up)
                                .offset(x: 80, y: -15)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                        }
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(height: 110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(CardButtonStyle())
        .onChange(of: value) { newValue, oldValue in
            if newValue > oldValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showPlusOne = true
                }

                // Reset after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        showPlusOne = false
                    }
                }
            }
            previousValue = newValue
        }
    }
}

struct FeeRowView: View {
    let fees: FeeData
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Image(systemName: "banknote.fill")
                    .foregroundStyle(Theme.Accent.icon)
                Text("Network Fees")
                    .font(.sectionHeader)
            }

            HStack(spacing: Theme.Spacing.md) {
                FeeItem(title: "Low", value: fees.low, color: Theme.Accent.feeLow, icon: "tortoise.fill")
                FeeItem(title: "Medium", value: fees.medium, color: Theme.Accent.feeMid, icon: "hare.fill")
                FeeItem(title: "High", value: fees.high, color: Theme.Accent.feeHigh, icon: "flame.fill")
            }
        }
        .card()
    }
}

struct FeeItem: View {
    let title: String
    let value: Int
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundStyle(color)

            AnimatedFeeText(value: value, color: .primary)

            Text("sat/vB")
                .font(.unit)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct AnimatedFeeText: View {
    let value: Int
    let color: Color
    @State private var previousValue: Int
    @State private var direction: Int = 0 // 1 = up (increase), -1 = down (decrease)

    init(value: Int, color: Color) {
        self.value = value
        self.color = color
        self._previousValue = State(initialValue: value)
    }

    var body: some View {
        Text("\(value)")
            .font(.headline)
            .fontWeight(.bold)
            .foregroundStyle(color)
            .id(value) // Important for transition to trigger
            .transition(
                .asymmetric(
                    insertion: .move(edge: direction > 0 ? .bottom : .top).combined(with: .opacity),
                    removal: .move(edge: direction > 0 ? .top : .bottom).combined(with: .opacity)
                )
            )
            .onChange(of: value) { newValue, oldValue in
                // If new value is higher, it comes from bottom (pushing old up)
                // If new value is lower, it comes from top (pushing old down)
                direction = newValue > oldValue ? 1 : -1
                previousValue = newValue
                Haptics.trigger()
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: value)
    }
}

struct FeeDistributionWidget: View {
    let fees: [Double]
    let feeThresholds: FeeData

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Theme.Accent.icon)
                Text("Fee Distribution")
                    .font(.sectionHeader)
                    .foregroundStyle(.primary)
                Spacer()
                Text("Next Block")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                let labels = ["10%", "25%", "50%", "75%", "90%"]
                let maxFee = fees.last ?? 1.0

                ForEach(0..<fees.count, id: \.self) { index in
                    let fee = fees[index]
                    let barHeight = CGFloat(fee / maxFee) * 80.0

                    VStack(spacing: Theme.Spacing.xs + 2) {
                        Text("<\(Int(fee))")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())

                        let color = barColor(for: fee)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(color.opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(color, lineWidth: 0.5)
                            )
                            .frame(height: max(10, barHeight))
                            .animation(.spring, value: barHeight)

                        Text(labels[index])
                            .font(.unit)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, Theme.Spacing.sm)

            Text("sat/vB")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .card()
    }

    private func barColor(for fee: Double) -> Color {
        let feeInt = Int(fee)
        if feeInt <= feeThresholds.low {
            return Theme.Accent.feeLow
        } else if feeInt <= feeThresholds.medium {
            return Theme.Accent.feeMid
        } else if feeInt < feeThresholds.high {
            return Theme.Accent.feeMid
        } else {
            return Theme.Accent.feeHigh
        }
    }
}

struct MoscowTimeWidget: View {
    let moscowTime: Int

    var body: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(Theme.Accent.icon)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Moscow Time")
                    .font(.cardLabel)
                    .foregroundStyle(.secondary)
                Text("\(moscowTime)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: moscowTime)
                    .onChange(of: moscowTime) { _, _ in
                        Haptics.trigger()
                    }
            }

            Spacer()

            Text("sats/$")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .card(padding: Theme.Spacing.lg)
    }
}

struct CirculatingSupplyWidget: View {
    let supply: Double
    let percent: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(Theme.Accent.icon)
                Text("Circulating Supply")
                    .font(.sectionHeader)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ProgressView(value: percent, total: 100)
                    .tint(Theme.Accent.brand)
                    .animation(.linear(duration: 1.0), value: percent)

                HStack {
                    Text(Formatters.formatAmount(Int(supply)) + " BTC")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Spacer()
                    Text(String(format: "%.2f%%", percent))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Accent.brand)
                        .contentTransition(.numericText())
                }
            }
        }
        .card()
    }
}

struct HalvingCard: View {
    let blocksRemaining: Int
    let progress: Double

    var body: some View {
        NavigationLink(destination: HalvingDetailView()) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack {
                    Image(systemName: "hourglass")
                        .foregroundStyle(Theme.Accent.brand)
                    Text("Halving Countdown")
                        .font(.sectionHeader)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: Theme.Spacing.sm) {
                    ProgressView(value: progress)
                        .tint(Theme.Accent.brand)
                        .animation(.linear(duration: 1.0), value: progress)

                    HStack {
                        Text("\(Formatters.formatAmount(blocksRemaining)) blocks left")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Spacer()
                        Text(String(format: "%.2f%%", progress * 100))
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Accent.brand)
                            .contentTransition(.numericText())
                    }
                }
            }
            .card()
        }
        .buttonStyle(CardButtonStyle())
    }
}

struct LightningCard: View {
    let channels: Int
    let nodes: Int
    let capacity: Double

    var body: some View {
        NavigationLink(destination: LightningDetailView()) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(Theme.Accent.icon)
                    Text("Lightning Network")
                        .font(.sectionHeader)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: Theme.Spacing.xl) {
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
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

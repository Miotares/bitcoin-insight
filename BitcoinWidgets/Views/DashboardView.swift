import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(spacing: 20) {
                        // Hero Price Card
                        PriceHeroCard(
                            price: viewModel.livePrice,
                            currency: settings.preferredCurrency,
                            changeColor: viewModel.priceChangeColor
                        )
                        .padding(.horizontal)
                        
                        // Main Stats Grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            
                            // Block Height with +1 Animation
                            BlockHeightStatCard(
                                value: viewModel.blockHeight,
                                destination: BlockHeightDetailView()
                            )
                            
                            StatCard(
                                title: "Mempool",
                                value: Formatters.formatAmount(viewModel.mempoolTransactions),
                                subtitle: "txs",
                                icon: "list.bullet.rectangle.fill",
                                color: .purple
                            ) {
                                MempoolDetailView()
                            }
                            
                            StatCard(
                                title: "Difficulty",
                                value: Formatters.formatDifficulty(viewModel.difficulty),
                                icon: "chart.line.uptrend.xyaxis",
                                color: .green
                            ) {
                                DifficultyDetailView()
                            }
                            
                            StatCard(
                                title: "Hashrate",
                                value: Formatters.formatHashrate(viewModel.hashrate),
                                icon: "cpu",
                                color: .cyan
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
                            .buttonStyle(.plain)
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
                        
                        Spacer(minLength: 20)
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
    @Environment(\.colorScheme) var colorScheme
    @State private var flashColor: Color = .clear
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "bitcoinsign.circle.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(0))
                
                Text("Bitcoin")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            
            Text(Formatters.formatCurrency(value: price, currencyCode: currency))
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(changeColor)
                .contentTransition(.numericText())
                .animation(.snappy, value: price)
                .onChange(of: price) { _, _ in
                    Haptics.trigger(.medium)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardBackground)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(flashColor)
                    .opacity(0.3)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        .onChange(of: price) { _, _ in
            if changeColor == .green {
                flash(color: .green)
            } else if changeColor == .red {
                flash(color: .red)
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
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
    }
}

struct StatCard<Destination: View>: View {
    let title: String
    let value: String
    var subtitle: String? = nil
    let icon: String
    let color: Color
    let destination: () -> Destination
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.title3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: value)
                            .onChange(of: value) { _, _ in
                                Haptics.trigger()
                            }
                        
                        if let subtitle = subtitle {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(16)
            .frame(height: 110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Block Height")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    ZStack(alignment: .leading) {
                        Text(Formatters.formatAmount(value))
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .minimumScaleFactor(0.8)
                            .contentTransition(.numericText())
                            .onChange(of: value) { _, _ in
                                Haptics.notification(.success)
                            }
                        
                        if showPlusOne {
                            Text("+1")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                                .offset(x: 80, y: -15)
                                .transition(.asymmetric(
                                    insertion: .scale.combined(with: .opacity).combined(with: .move(edge: .bottom)),
                                    removal: .opacity.combined(with: .move(edge: .top))
                                ))
                        }
                    }
                }
            }
            .padding(16)
            .frame(height: 110)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Material.ultraThin)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "banknote.fill")
                    .foregroundStyle(.green)
                Text("Network Fees")
                    .font(.headline)
            }
            
            HStack(spacing: 12) {
                FeeItem(title: "Low", value: fees.low, color: .green, icon: "tortoise.fill")
                FeeItem(title: "Medium", value: fees.medium, color: .orange, icon: "hare.fill")
                FeeItem(title: "High", value: fees.high, color: .red, icon: "flame.fill")
            }
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
    }
}

struct FeeItem: View {
    let title: String
    let value: Int
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
                    .fontWeight(.bold)
            }
            .foregroundStyle(color)
            
            AnimatedFeeText(value: value, color: .primary)
            
            Text("sat/vB")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.purple)
                Text("Fee Distribution")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text("Next Block")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(alignment: .bottom, spacing: 8) {
                let labels = ["10%", "25%", "50%", "75%", "90%"]
                let maxFee = fees.last ?? 1.0
                
                ForEach(0..<fees.count, id: \.self) { index in
                    let fee = fees[index]
                    let barHeight = CGFloat(fee / maxFee) * 80.0
                    
                    VStack(spacing: 6) {
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
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 8)
            
            Text("sat/vB")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
    }
    
    private func barColor(for fee: Double) -> Color {
        let feeInt = Int(fee)
        if feeInt <= feeThresholds.low {
            return .green
        } else if feeInt <= feeThresholds.medium {
            return .orange
        } else if feeInt < feeThresholds.high {
            return .orange
        } else {
            return .red
        }
    }
}

struct MoscowTimeWidget: View {
    let moscowTime: Int
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        HStack {
            Image(systemName: "clock.fill")
                .foregroundStyle(.red)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Moscow Time")
                    .font(.caption)
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
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
    }
}

struct CirculatingSupplyWidget: View {
    let supply: Double
    let percent: Double
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .foregroundStyle(.blue)
                Text("Circulating Supply")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 8) {
                ProgressView(value: percent, total: 100)
                    .tint(.blue)
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
                        .foregroundStyle(.blue)
                        .contentTransition(.numericText())
                }
            }
        }
        .padding(20)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
    }
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
    }
}

struct HalvingCard: View {
    let blocksRemaining: Int
    let progress: Double
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationLink(destination: HalvingDetailView()) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.orange)
                    Text("Halving Countdown")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(.orange)
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
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                    }
                }
            }
            .padding(20)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
    }
}

struct LightningCard: View {
    let channels: Int
    let nodes: Int
    let capacity: Double
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationLink(destination: LightningDetailView()) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(.yellow)
                    Text("Lightning Network")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 20) {
                    LNStat(title: "Capacity", value: Formatters.formatLightningBTC(capacity / 100_000_000))
                    LNStat(title: "Nodes", value: Formatters.formatAmount(nodes))
                    LNStat(title: "Channels", value: Formatters.formatAmount(channels))
                }
            }
            .padding(20)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }
    
    private var cardBackground: some ShapeStyle {
        Material.ultraThin
    }
}

struct LNStat: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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

// MARK: - Extensions

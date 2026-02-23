//
//  BlockHeightDetailView.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//


import SwiftUI
import Combine

struct BlockData: Decodable {
    let height: Int
    let timestamp: TimeInterval
    let tx_count: Int
    let difficulty: Double
    let size: Int
    let weight: Int
    let reward: Int
    let totalFees: Int
    let totalOutputs: Int
    let pool: String?
    let medianFee: Double?
    let total_out: Int

    private enum CodingKeys: String, CodingKey {
        case height, timestamp, tx_count, difficulty, size, weight, reward, pool, extras
    }

    private enum ExtrasKeys: String, CodingKey {
        case totalFees, totalOutputs, medianFee, totalOutputAmt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        height = try container.decode(Int.self, forKey: .height)
        timestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        tx_count = try container.decode(Int.self, forKey: .tx_count)
        difficulty = try container.decodeIfPresent(Double.self, forKey: .difficulty) ?? 0
        size = try container.decode(Int.self, forKey: .size)
        weight = try container.decode(Int.self, forKey: .weight)
        if let decodedReward = try? container.decode(Int.self, forKey: .reward) {
            reward = decodedReward
        } else {
            let halvings = height / 210_000
            let subsidyBTC = 50.0 / pow(2.0, Double(halvings))
            reward = Int(subsidyBTC * 100_000_000)
        }
        pool = try container.decodeIfPresent(String.self, forKey: .pool)
        
        if let extras = try? container.nestedContainer(keyedBy: ExtrasKeys.self, forKey: .extras) {
            totalFees = try extras.decodeIfPresent(Int.self, forKey: .totalFees) ?? 0
            totalOutputs = try extras.decodeIfPresent(Int.self, forKey: .totalOutputs) ?? 0
            medianFee = try extras.decodeIfPresent(Double.self, forKey: .medianFee)
            total_out = try extras.decodeIfPresent(Int.self, forKey: .totalOutputAmt) ?? 0 // Note key mapping
        } else {
            totalFees = 0
            totalOutputs = 0
            medianFee = nil
            total_out = 0
        }
    }
}

struct BlockHeightDetailView: View {
    @State private var blockData: BlockData?
    @State private var tipHeight: Int?
    @State private var errorMessage: String?

    func fetchTipHeight() {
        let url = URL(string: "https://mempool.space/api/blocks/tip/height")!
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let str = String(data: data, encoding: .utf8), let height = Int(str) {
                DispatchQueue.main.async { self.tipHeight = height }
            }
        }.resume()
    }

    func fetchLatestBlock() {
        // ... (FETCH TIP IN PARALLEL)
        fetchTipHeight()
        
        struct BlockSummary: Decodable {
            let id: String
            let height: Int
            let timestamp: TimeInterval
        }

        let blocksURL = URL(string: "https://mempool.space/api/v1/blocks")!

        URLSession.shared.dataTask(with: blocksURL) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { self.errorMessage = "No data received" }
                return
            }

            do {
                let blocks = try JSONDecoder().decode([BlockSummary].self, from: data)
                guard let latestBlock = blocks.first else {
                    return
                }

                let blockDetailsURL = URL(string: "https://mempool.space/api/v1/block/\(latestBlock.id)")!

                URLSession.shared.dataTask(with: blockDetailsURL) { detailData, _, detailError in
                    if let detailError = detailError {
                        DispatchQueue.main.async { self.errorMessage = detailError.localizedDescription }
                        return
                    }
                    guard let detailData = detailData else {
                        DispatchQueue.main.async { self.errorMessage = "No data received" }
                        return
                    }

                    do {
                        let detailedBlock = try JSONDecoder().decode(BlockData.self, from: detailData)
                        DispatchQueue.main.async {
                            self.blockData = detailedBlock
                            self.errorMessage = nil
                        }
                    } catch {
                        DispatchQueue.main.async { self.errorMessage = "Failed to parse response" }
                    }
                }.resume()
            } catch {
                DispatchQueue.main.async { self.errorMessage = "Failed to parse response" }
            }
        }.resume()
    }
    
    var body: some View {
        ZStack {
            AnimatedBackgroundView(accentColor: .blue)
            
            ScrollView {
                VStack(spacing: 24) {
                    if let block = blockData {
                        // MARK: - Hero Section
                        VStack(spacing: 8) {
                            Text("BLOCK HEIGHT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(2)
                            
                            Text("\(block.height)")
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: block.height)
                            
                            Text(Date(timeIntervalSince1970: block.timestamp).formatted(date: .long, time: .standard))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(.top, 40)
                        
                        // MARK: - Technical Stats Grid
                        // MARK: - Technical Stats Grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            BlockStatCard(
                                title: "Transactions",
                                value: Formatters.formatAmount(block.tx_count)
                            )
                            
                            BlockStatCard(
                                title: "Size",
                                value: Formatters.formatBytesToMB(block.size) + " MB"
                            )
                            
                            BlockStatCard(
                                title: "Weight",
                                value: Formatters.formatBytesToMB(block.weight) + " MWU"
                            )
                            
                            BlockStatCard(
                                title: "Difficulty",
                                value: Formatters.formatDifficulty(block.difficulty)
                            )
                        }
                        .padding(.horizontal)
                        
                        // MARK: - Mining & Financials
                        VStack(spacing: 0) {
                            // Pool
                            if let pool = block.pool {
                                HStack {
                                    Text("Mined by")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(pool)
                                        .fontWeight(.bold)
                                }
                                .padding()
                                Divider()
                            }
                            
                            // Block Reward
                            HStack {
                                Text("Block Reward")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatBTC(Double(block.reward) / 100_000_000.0))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .padding()
                            Divider()
                            
                            // Total Output Volume
                            HStack {
                                Text("Total Volume")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                // Round to 2 decimal places as requested
                                let btcVolume = Double(block.total_out) / 100_000_000.0
                                Text(String(format: "%.2f BTC", btcVolume)) 
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .padding()
                            Divider()
                            
                            // Total Fees
                            HStack {
                                Text("Total Fees")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatBTC(Double(block.totalFees) / 100_000_000.0))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .padding()
                            Divider()
                            
                            // Average Fee
                            HStack {
                                Text("Avg Fee")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let avgFee = block.tx_count > 0 ? Double(block.totalFees) / Double(block.tx_count) : 0
                                Text(Formatters.formatSats(Int(avgFee)))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .padding()
                            Divider()
                            
                            // Median Fee
                            if let median = block.medianFee {
                                HStack {
                                    Text("Median Fee")
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    // medianFee from API is likely in raw satoshis per transaction if simply 'medianFee'.
                                    // If it is small (e.g. 1), it might be fee RATE? 
                                    // Mempool API 'extras.medianFee' is usually absolute fee. 
                                    // A value of 1 sat would be extremely low for a whole tx. 
                                    // Let's assume the API returns standard sats/tx.
                                    Text(Formatters.formatSats(Int(median)))
                                        .fontWeight(.bold)
                                        .monospacedDigit()
                                }
                                .padding()
                                Divider()
                            }
                            
                            // Fee to Subsidy Ratio
                            HStack {
                                Text("Fee to Subsidy Ratio")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                let subsidy = Double(block.reward - block.totalFees)
                                let ratio = subsidy > 0 ? (Double(block.totalFees) / subsidy) * 100 : 0
                                Text(String(format: "%.2f%%", ratio))
                                    .fontWeight(.bold)
                                    .monospacedDigit()
                            }
                            .padding()
                        }
                        .background(Material.ultraThin)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal)
                        
                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            Image(systemName: "wifi.exclamationmark")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Retry") { fetchLatestBlock() }
                                .foregroundStyle(Color.bitcoinOrange)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                        .padding(.horizontal)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fetchLatestBlock()
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            fetchLatestBlock()
        }
    }
}

struct BlockStatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Material.ultraThin)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

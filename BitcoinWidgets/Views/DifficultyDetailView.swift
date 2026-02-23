import Foundation
import SwiftUI
import Combine

struct CorrectDifficultyAdjustment: Decodable {
    let progressPercent: Double
    let difficultyChange: Double
    let estimatedRetargetDate: Double
    let remainingBlocks: Int
    let remainingTime: Double
    let previousRetarget: Double
}

struct DifficultyDetailView: View {
    @State private var adjustmentData: CorrectDifficultyAdjustment?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AnimatedBackgroundView(accentColor: .green)
            
            ScrollView {
                VStack(spacing: 24) {
                    if let data = adjustmentData {
                        // MARK: - Hero Section
                        VStack(spacing: 8) {
                            Text("ESTIMATED ADJUSTMENT")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(2)
                            
                            // Estimated Change
                            Text(Formatters.formatPercent(data.difficultyChange))
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
                                .foregroundStyle(data.difficultyChange >= 0 ? .green : .red)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: data.difficultyChange)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .padding(.horizontal)
                        }
                        .padding(.top, 40)
                        
                        // MARK: - Technical Stats Grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            
                            DetailStatCard(
                                title: "Remaining Blocks",
                                value: Formatters.formatAmount(data.remainingBlocks)
                            )
                            
                            DetailStatCard(
                                title: "Period Progress",
                                value: String(format: "%.1f%%", data.progressPercent)
                            )
                        }
                        .padding(.horizontal)
                        
                        // MARK: - Details List
                        VStack(spacing: 0) {
                            HStack {
                                Text("Estimated Date")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(Formatters.formatDate(data.estimatedRetargetDate / 1000.0)) // API uses ms
                                    .fontWeight(.bold)
                            }
                            .padding()
                            Divider()
                            
                            HStack {
                                Text("Previous Retarget")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.2f%%", data.previousRetarget))
                                     .fontWeight(.bold)
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
                            Button("Retry") { Task { await fetchDifficultyData() } }
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
            .navigationTitle("Difficulty")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await fetchDifficultyData()
                }
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    await fetchDifficultyData()
                }
            }
        }
    }
    
    // MARK: - API
    func fetchDifficultyData() async {
        let urlString = "https://mempool.space/api/v1/difficulty-adjustment"
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(CorrectDifficultyAdjustment.self, from: data)
            await MainActor.run {
                self.adjustmentData = decoded
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
}

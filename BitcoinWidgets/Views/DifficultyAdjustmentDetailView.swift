//
//  DifficultyAdjustmentDetailView.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//


import SwiftUI
import Combine

struct DifficultyAdjustmentDetailView: View {
    @State private var adjustments: [DifficultyAdjustmentEntry] = []
    @State private var isLoading = true
    
    struct DifficultyAdjustmentEntry: Decodable {
        let timestamp: Double
        let height: Int
        let difficulty: Double
        let change: Double
    }
    
var body: some View {
    return ScrollView {
        VStack(spacing: 24) {
            Text("Difficulty Adjustment")
                .font(.title.bold())
                .padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    Group {
                        HStack {
                            Text("Last Adjustment Height")
                                .font(.body)
                            Spacer()
                            Text("\(adjustments.first?.height ?? 0)")
                                .font(.headline)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        Text("The block height at which the last difficulty adjustment occurred.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        Divider()
                        HStack {
                            Text("Last Difficulty")
                                .font(.body)
                            Spacer()
                            Text(formatDifficulty(adjustments.first?.difficulty ?? 0))
                                .font(.headline)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        Text("The network mining difficulty level after the last adjustment.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        Divider()
                        HStack {
                            Text("Change")
                                .font(.body)
                            Spacer()
                            Text(String(format: "%.2f %%", (adjustments.first?.change ?? 0) * 100))
                                .font(.headline)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        Text("The percentage by which the difficulty changed compared to the previous period.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                        Divider()
                        HStack {
                            Text("Next Estimated Adjustment")
                                .font(.body)
                            Spacer()
                            Text("\(adjustments.first.map { $0.height + 2016 } ?? 0)")
                                .font(.headline)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal)
                        Text("The block height where the next adjustment will likely occur (every 2016 blocks).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                }
                .background(Color(UIColor.secondarySystemGroupedBackground))
                .cornerRadius(10)
                .padding(.horizontal)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Difficulty Adjustment")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task {
                await fetchDifficultyAdjustments()
            }
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await fetchDifficultyAdjustments()
            }
        }
    }
        
        func fetchDifficultyAdjustments() async {
            guard let url = URL(string: "https://mempool.space/api/v1/mining/difficulty-adjustments/1m") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let raw = try JSONSerialization.jsonObject(with: data) as? [[Any]]
                let parsed = raw?.compactMap { arr -> DifficultyAdjustmentEntry? in
                    guard arr.count == 4,
                          let timestamp = arr[0] as? Double,
                          let height = arr[1] as? Int,
                          let difficulty = arr[2] as? Double,
                          let change = arr[3] as? Double
                    else { return nil }
                    return DifficultyAdjustmentEntry(timestamp: timestamp, height: height, difficulty: difficulty, change: change)
                } ?? []
                await MainActor.run {
                    self.adjustments = parsed.sorted(by: { $0.timestamp > $1.timestamp })
                    self.isLoading = false
                }
            } catch { }
        }
        
        func formatDifficulty(_ difficulty: Double) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter.string(from: NSNumber(value: difficulty)) ?? "\(difficulty)"
        }
    }
}

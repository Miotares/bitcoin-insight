//
//  MempoolDetailView.swift
//  BitcoinWidgets
//
//  Reworked to mirror BlockHeightDetailView styling
//

import SwiftUI
import Combine

struct MempoolData: Decodable {
    let count: Int
    let vsize: Int          // virtual size in vbytes
    let total_fee: Int64    // sats
    let fee_histogram: [[Double]] // [[fee_rate, vsize], ...]
}

struct MempoolDetailView: View {
    @State private var mempoolData: MempoolData?
    @State private var minFee: Int?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AnimatedBackgroundView()
            
            ScrollView {
                VStack(spacing: 24) {
                    if let mempool = mempoolData {
                        // MARK: - Hero Section
                        VStack(spacing: 8) {
                            Text("MEMPOOL TRANSACTIONS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(.secondary)
                                .tracking(2)
                            
                            Text(Formatters.formatAmount(mempool.count))
                                .font(.system(size: 52, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                                .animation(.snappy, value: mempool.count)
                        }
                        .padding(.top, 40)
                        
                        // MARK: - Technical Stats Grid
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)], spacing: 16) {
                            DetailStatCard(
                                title: "Virtual Size",
                                value: Formatters.formatVMB(mempool.vsize) + " vMB"
                            )
                            
                            DetailStatCard(
                                title: "Total Fees",
                                value: Formatters.formatBTC(Double(mempool.total_fee) / 100_000_000.0)
                            )
                            
                            DetailStatCard(
                                title: "Blocks to Clear",
                                value: String(format: "%.1f", Double(mempool.vsize) / 1_000_000.0)
                            )
                            
                            DetailStatCard(
                                title: "Min Fee",
                                value: minFee != nil ? "\(minFee!) sat/vB" : "-"
                            )
                        }
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
                            Button("Retry") { Task { await fetchMempoolData(); await fetchFees() } }
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
            .navigationTitle("Mempool")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                Task {
                    await fetchMempoolData()
                    await fetchFees()
                }
            }
            .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
                Task {
                    await fetchMempoolData()
                    await fetchFees()
                }
            }
        }
    }

    // MARK: - API
    func fetchMempoolData() async {
        let urlString = "https://mempool.space/api/mempool"
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(MempoolData.self, from: data)
            await MainActor.run {
                self.mempoolData = decoded
                self.errorMessage = nil
            }
        } catch {
            await MainActor.run { self.errorMessage = error.localizedDescription }
        }
    }
    
    func fetchFees() async {
        let urlString = "https://mempool.space/api/v1/fees/recommended"
        guard let url = URL(string: urlString) else { return }
        
        struct FeeResp: Decodable {
            let fastestFee: Int
            let halfHourFee: Int
            let hourFee: Int
            let minimumFee: Int
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let fees = try JSONDecoder().decode(FeeResp.self, from: data)
            await MainActor.run {
                self.minFee = fees.minimumFee
            }
        } catch { }
    }
}

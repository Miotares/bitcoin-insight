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
            AnimatedBackgroundView(accentColor: .purple)
            
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
                                .font(.system(size: 52, weight: .heavy, design: .rounded))
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

    // MARK: - Row & Explanation (shared look with Block view)
    private func row(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func explanationRow(key: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if !key.isEmpty {
                Text(key)
                    .font(.body.weight(.semibold))
            }
            Text("– \(text)")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Formatting helpers (match Block view style)
    private func formatInt(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func formatVMB(_ vsize: Int) -> String {
        let vmb = Double(vsize) / 1_000_000.0
        return vmb.formatted(.number.precision(.fractionLength(2)).grouping(.automatic))
    }

    private func formatBTC(_ sats: Int64) -> String {
        let btc = Double(sats) / 100_000_000.0
        let nf = NumberFormatter()
        nf.locale = Locale.current
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 8
        nf.maximumFractionDigits = 8
        let s = nf.string(from: NSNumber(value: btc)) ?? String(format: "%.8f", btc)
        return "\(s) BTC"
    }

    // MARK: - API
    func fetchMempoolData() async {
        let urlString = "https://mempool.space/api/mempool"
        guard let url = URL(string: urlString) else {
            self.errorMessage = "Invalid URL"
            return
        }
        print("🚀 Starting API call: GET \(urlString)")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                print("📦 Received data for /mempool (\(data.count) bytes), status: \(http.statusCode)")
            }
            let decoded = try JSONDecoder().decode(MempoolData.self, from: data)
            await MainActor.run {
                self.mempoolData = decoded
                self.errorMessage = nil
            }
        } catch {
            print("❌ Failed to load mempool data: \(error)")
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
        } catch {
            print("❌ Error fetching fees: \(error)")
        }
    }
}

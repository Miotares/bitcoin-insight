//
//  NetworkClient.swift
//  InsightWidgets
//
//  Reads the single cached stats row from the Supabase backend.
//  ONLY the widgets use this; the main app talks to mempool.space directly.
//

import Foundation

enum NetworkClient {
    private static let endpoint = URL(string:
        "https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/network_stats?select=payload&id=eq.1")!
    private static let apiKey = "sb_publishable_FEEoI6sfC_EZ1oLP2E0IJQ_Yftfzrk9"

    private struct Row: Decodable {
        let payload: Payload
        struct Payload: Decodable {
            let prices: [String: Double]
            let blockHeight: Int
            let fees: Fees
            let mempoolCount: Int?
            let hashrate: Double?
            let difficulty: Double?
            let difficultyAdjustment: Adjustment?
            let lightning: Lightning?

            struct Fees: Decodable { let fast: Int; let halfHour: Int; let hour: Int }
            struct Adjustment: Decodable {
                let progressPercent: Double?
                let remainingBlocks: Int?
                let estimatedRetargetPercentage: Double?
            }
            struct Lightning: Decodable {
                let channels: Int?
                let nodes: Int?
                let capacity: Int?
            }
        }
    }

    static func fetchSnapshot() async throws -> NetworkSnapshot {
        var request = URLRequest(url: endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let p = try JSONDecoder().decode([Row].self, from: data).first?.payload else {
            throw URLError(.cannotParseResponse)
        }

        return NetworkSnapshot(
            prices: p.prices,
            blockHeight: p.blockHeight,
            feeFast: p.fees.fast,
            feeHalfHour: p.fees.halfHour,
            feeHour: p.fees.hour,
            mempoolCount: p.mempoolCount ?? 0,
            hashrate: p.hashrate ?? 0,
            difficulty: p.difficulty ?? 0,
            adjustmentProgress: p.difficultyAdjustment?.progressPercent ?? 0,
            adjustmentRemainingBlocks: p.difficultyAdjustment?.remainingBlocks ?? 0,
            adjustmentRetargetPercent: p.difficultyAdjustment?.estimatedRetargetPercentage ?? 0,
            lnChannels: p.lightning?.channels ?? 0,
            lnNodes: p.lightning?.nodes ?? 0,
            lnCapacitySats: p.lightning?.capacity ?? 0,
            updatedAt: Date()
        )
    }
}

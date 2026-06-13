//
//  NetworkClient.swift
//  InsightWidgets
//
//  Reads the single cached stats row from the Supabase backend.
//  ONLY the widgets use this; the main app talks to mempool.space directly.
//

import Foundation

enum NetworkClient {
    // Read-only endpoint: one row, RLS-protected, anon key is publishable.
    private static let endpoint = URL(string:
        "https://hyyagnnsjbpsehriyafn.supabase.co/rest/v1/network_stats?select=payload&id=eq.1")!
    private static let apiKey = "sb_publishable_FEEoI6sfC_EZ1oLP2E0IJQ_Yftfzrk9"

    private struct Row: Decodable {
        let payload: Payload
        struct Payload: Decodable {
            let prices: [String: Double]
            let blockHeight: Int
            let fees: Fees
            struct Fees: Decodable {
                let fast: Int
                let halfHour: Int
                let hour: Int
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

        guard let row = try JSONDecoder().decode([Row].self, from: data).first else {
            throw URLError(.cannotParseResponse)
        }

        return NetworkSnapshot(
            prices: row.payload.prices,
            blockHeight: row.payload.blockHeight,
            feeFast: row.payload.fees.fast,
            feeHalfHour: row.payload.fees.halfHour,
            feeHour: row.payload.fees.hour,
            updatedAt: Date()   // when we fetched it
        )
    }
}

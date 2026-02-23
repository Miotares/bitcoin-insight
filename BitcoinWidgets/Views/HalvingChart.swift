//
//  HalvingChart.swift
//  BitcoinWidgets
//
//  Created by User on 2025-12-15.
//

import SwiftUI
import Charts

struct HalvingChart: View {
    let currentBlockHeight: Int

    // Halving interval is 210,000 blocks
    private let halvingInterval = 210_000
    
    private struct SupplyPoint: Identifiable {
        let id = UUID()
        let blockHeight: Int
        let supply: Double
    }

    private var halvingHeights: [Int] {
        // Generate significant halving heights for the axis and vertical lines (cover full range)
        (1...34).map { $0 * halvingInterval }
    }

    private let supplyPoints: [SupplyPoint] = {
        var points: [SupplyPoint] = []
        var currentSupply: Double = 0
        var reward: Double = 50.0
        
        // Add genesis point
        points.append(SupplyPoint(blockHeight: 0, supply: 0))
        
        // Calculate supply for full emission schedule (34 eras)
        for i in 0...34 {
            let blocksInEra = 210_000
            let mountedInEra = Double(blocksInEra) * reward
            currentSupply += mountedInEra
            let height = (i + 1) * 210_000
            points.append(SupplyPoint(blockHeight: height, supply: currentSupply))
            reward /= 2
        }
        return points
    }()

    var body: some View {
        Chart {
            // Vertical Lines for Halvings
            ForEach(halvingHeights, id: \.self) { height in
                // Show line only for every 4th halving to prevent clutter
                if height % (halvingInterval * 4) == 0 {
                    RuleMark(x: .value("Halving", height))
                        .foregroundStyle(.white.opacity(0.1))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }

            // Emission Curve
            ForEach(supplyPoints) { point in
                LineMark(
                    x: .value("Block Height", point.blockHeight),
                    y: .value("Total Supply", point.supply)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange.opacity(0), .orange],
                        startPoint: .bottomLeading,
                        endPoint: .topTrailing
                    )
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            // Current Position
            if let currentSupply = calculateSupply(at: currentBlockHeight) {
                PointMark(
                    x: .value("Current", currentBlockHeight),
                    y: .value("Supply", currentSupply)
                )
                .symbol {
                    PulsingDotView()
                }
            }
        }
        .chartYScale(domain: 0...21_000_000)
        .chartXAxis {
            let values = [0, 2_000_000, 4_000_000, 6_000_000, 7_140_000] // Steps: 0, 2M, 4M, 6M, Infinity
            AxisMarks(values: values) { value in
                if let intValue = value.as(Int.self) {
                    AxisTick(stroke: StrokeStyle(lineWidth: 0))
                    
                    AxisValueLabel(centered: false) {
                        if intValue >= 7_000_000 {
                            Text("∞")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(intValue == 0 ? "0" : "\(intValue / 1_000_000)M")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .chartXScale(domain: 0...7_600_000) // Extend slightly for padding
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.05))
                
                if let doubleValue = value.as(Double.self) {
                     AxisValueLabel {
                        Text("\(Int(doubleValue / 1_000_000))M")
                            .font(.caption2)
                            .foregroundStyle(.secondary.opacity(0.7))
                     }
                }
            }
        }
        .frame(height: 200)
    }

    private func calculateSupply(at height: Int) -> Double? {
        // Approximate grid calculation logic
        var supply: Double = 0
        var reward: Double = 50.0
        var remainingHeight = height
        
        while remainingHeight > 0 {
            let blocksInThisEra = min(remainingHeight, 210_000)
            supply += Double(blocksInThisEra) * reward
            remainingHeight -= blocksInThisEra
            reward /= 2
            if reward < 0.00000001 { break } // dust
        }
        
        return supply
    }
    
    // Helper not needed for automatic axis but keeping if useful later
    private func formatHalvingLabel(_ height: Int) -> String {
        let kValue = height / 1000
        return "\(kValue)k"
    }
}

private struct PulsingDotView: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Signal Ring (expanding and fading)
            Circle()
                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                .frame(width: 10, height: 10) // Start size matches core
                .scaleEffect(isPulsing ? 3.0 : 1.0) // Expands outwards
                .opacity(isPulsing ? 0.0 : 1.0) // Fades to invisible
            
            // Core dot (stable)
            Circle()
                .fill(.orange)
                .frame(width: 10, height: 10)
                .shadow(color: .orange, radius: 4, x: 0, y: 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

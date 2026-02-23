//
//  HalvingRewardChart.swift
//  BitcoinWidgets
//
//  Display the Block Reward halving steps over time.
//

import SwiftUI
import Charts

struct HalvingRewardChart: View {
    let currentBlockHeight: Int
    
    // Halving interval is 210,000 blocks
    private let halvingInterval = 210_000
    
    private struct RewardPoint: Identifiable {
        let id = UUID()
        let blockHeight: Int
        let reward: Double
    }
    
    private var halvingHeights: [Int] {
        // All 33 halvings (approx end of emission)
        (1...33).map { $0 * halvingInterval }
    }
    
    private let rewardPoints: [RewardPoint] = {
        var points: [RewardPoint] = []
        var reward: Double = 50.0
        
        // Show all 33 halvings + initial era
        for i in 0...33 {
            let startHeight = i * 210_000
            let endHeight = (i + 1) * 210_000
            
            // Start of era
            points.append(RewardPoint(blockHeight: startHeight, reward: reward))
            // End of era (Cliff edge)
            points.append(RewardPoint(blockHeight: endHeight, reward: reward))
            
            reward /= 2
        }
        
        // Extend the final line to the chart's edge to show "no more changes"
        // 7_600_000 is the X-scale domain max
        if let last = points.last {
            points.append(RewardPoint(blockHeight: 7_600_000, reward: last.reward))
        }
        
        return points
    }()
    
    var body: some View {
        Chart {
            // Vertical Lines for Halvings
            // Filter to show fewer lines to avoid crowding
            ForEach(halvingHeights, id: \.self) { height in
                if height % (210_000 * 4) == 0 { // Every 4th halving line
                    RuleMark(x: .value("Halving", height))
                        .foregroundStyle(.white.opacity(0.03))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                }
            }
            
            // Reward Steps (Square Wave)
            ForEach(rewardPoints) { point in
                LineMark(
                    x: .value("Block Height", point.blockHeight),
                    y: .value("Block Reward", point.reward)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .orange.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)) // Slightly thinner for more steps
            }
            
            // Current Position - Dashed Line
            RuleMark(x: .value("Current", currentBlockHeight))
                .foregroundStyle(.orange.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            
            // Pulsing Dot
            if let currentReward = calculateReward(at: currentBlockHeight) {
                PointMark(
                    x: .value("Current", currentBlockHeight),
                    y: .value("Reward", currentReward)
                )
                .symbol {
                    PulsingDotView()
                }
            }
        }
        // Custom X Axis
        .chartXAxis {
            // Simplified steps: 0, 2M, 4M, 6M
            let values = [0, 2_000_000, 4_000_000, 6_000_000]
            AxisMarks(values: values) { value in
                if let intValue = value.as(Int.self) {
                     // Remove ticks
                     AxisTick(stroke: StrokeStyle(lineWidth: 0))
                    
                     AxisValueLabel {
                         Text(intValue == 0 ? "0" : "\(intValue / 1_000_000)M")
                             .font(.system(size: 9))
                             .foregroundStyle(.secondary)
                     }
                }
            }
        }
        .chartXScale(domain: 0...7_600_000)
        // Custom Y Axis
        .chartYAxis {
            // Log steps
            let values = [50.0, 0.1, 0.001, 0.00001, 0.00000001]
            AxisMarks(position: .leading, values: values) { value in
                 AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                     .foregroundStyle(.white.opacity(0.05))
                 
                 if let doubleValue = value.as(Double.self) {
                     AxisValueLabel {
                         Text(formatRewardLabel(doubleValue))
                             .font(.system(size: 8, weight: .medium, design: .monospaced))
                             .foregroundStyle(.secondary.opacity(0.8))
                     }
                 }
            }
        }
        .chartYScale(domain: 0.000000001...100, type: .log)
        .frame(height: 220)
    }
    
    private func calculateReward(at height: Int) -> Double? {
        let era = height / halvingInterval
        return 50.0 / pow(2.0, Double(era))
    }
    
    private func formatRewardLabel(_ value: Double) -> String {
        if value < 0.0000001 {
            return "1 sat"
        }
        if value < 0.001 {
            // Use more decimals for small numbers to avoid "0"
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 8
            return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
        }
        // Standard concise formatting for larger numbers
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// Reuse the pulsing dot for consistency
private struct PulsingDotView: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Signal Ring
            Circle()
                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 2.5 : 1.0)
                .opacity(isPulsing ? 0.0 : 1.0)
            
            // Core
            Circle()
                .fill(.orange)
                .frame(width: 6, height: 6) // Slightly smaller dot
                .shadow(color: .orange, radius: 4, x: 0, y: 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

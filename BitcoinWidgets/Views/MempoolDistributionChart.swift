//
//  MempoolDistributionChart.swift
//  BitcoinWidgets
//
//  Created by User on 2025-12-15.
//

import SwiftUI
import Charts

struct MempoolDistributionChart: View {
    // raw format: [[fee_rate, vsize], ...]
    let histogramData: [[Double]]

    // A simplified model for the chart
    struct ChartBucket: Identifiable {
        var id: String { label } // Stable ID
        let label: String
        let minFee: Double
        let maxFee: Double
        var totalVSize: Double
    }

    // 1. Define distinct ranges covering the whole spectrum securely.
    // Overlapping edges handled by `<` logic.
    private var computedBuckets: [ChartBucket] {
        // Prepare empty buckets
        var buckets = [
            ChartBucket(label: "1",     minFee: 0,   maxFee: 2,   totalVSize: 0),
            ChartBucket(label: "2",     minFee: 2,   maxFee: 3,   totalVSize: 0),
            ChartBucket(label: "3",     minFee: 3,   maxFee: 4,   totalVSize: 0),
            ChartBucket(label: "4",     minFee: 4,   maxFee: 5,   totalVSize: 0),
            ChartBucket(label: "5",     minFee: 5,   maxFee: 6,   totalVSize: 0),
            ChartBucket(label: "6-8",   minFee: 6,   maxFee: 8,   totalVSize: 0),
            ChartBucket(label: "8-10",  minFee: 8,   maxFee: 10,  totalVSize: 0),
            ChartBucket(label: "10-12", minFee: 10,  maxFee: 12,  totalVSize: 0),
            ChartBucket(label: "12-15", minFee: 12,  maxFee: 15,  totalVSize: 0),
            ChartBucket(label: "15-20", minFee: 15,  maxFee: 20,  totalVSize: 0),
            ChartBucket(label: "20-30", minFee: 20,  maxFee: 30,  totalVSize: 0),
            ChartBucket(label: "30-40", minFee: 30,  maxFee: 40,  totalVSize: 0),
            ChartBucket(label: "40-50", minFee: 40,  maxFee: 50,  totalVSize: 0),
            ChartBucket(label: "50-60", minFee: 50,  maxFee: 60,  totalVSize: 0),
            ChartBucket(label: "60-70", minFee: 60,  maxFee: 70,  totalVSize: 0),
            ChartBucket(label: "70-80", minFee: 70,  maxFee: 80,  totalVSize: 0),
            ChartBucket(label: "80-100",minFee: 80,  maxFee: 100, totalVSize: 0),
            ChartBucket(label: "100+",  minFee: 100, maxFee: 99999, totalVSize: 0)
        ]
        
        // 2. Aggregate Data
        for entry in histogramData {
            // Safety check
            guard entry.count >= 2 else { continue }
            let rate = entry[0]
            let vsize = entry[1]
            
            // Skip empty data points
            if vsize <= 0 { continue }
            
            // Logic: Find the first bucket where rate < maxFee
            // e.g. rate 1.5 -> min 0, max 2 -> matches
            // rate 100 -> min 100, max 99999 -> matches
            // rate 1000 -> matches via firstIndex logic or manual clamp
            
            if let index = buckets.firstIndex(where: { rate < $0.maxFee }) {
                buckets[index].totalVSize += vsize
            } else {
                // If it's huge (>= 100), it falls into the last one?
                // Our last bucket is max 99999, so it should be caught.
                // Just in case, add to last:
                if var last = buckets.last {
                    buckets[buckets.count - 1].totalVSize += vsize
                }
            }
        }
        
        // 3. Return ALL buckets to ensure X-axis stability and show "empty" areas
        // Filtering hid the "potential" high fee areas. showing them proves they are empty/small.
        return buckets
    }

    var body: some View {
        let data = computedBuckets
        
        Chart(data) { bucket in
            let color = bucketColor(for: bucket.minFee)
            let vSizeMB = bucket.totalVSize / 1_000_000
            
            BarMark(
                x: .value("Fee Rate", bucket.label),
                y: .value("Size", vSizeMB)
            )
            .foregroundStyle(.clear)
            .annotation(position: .overlay) {
                ZStack {
                    DistributionBarShape(radius: 4)
                        .fill(color.opacity(0.3))
                    
                    DistributionBarShape(radius: 4)
                        .stroke(color, lineWidth: 1)
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(.white.opacity(0.05))
                
                if let d = value.as(Double.self) {
                     AxisValueLabel {
                         Text("\(String(format: "%.1f", d)) M")
                             .font(.caption2)
                     }
                }
            }
        }
        .frame(height: 220)
    }
    
    // Color Logic: Spectrum
    // < 5 Green
    // 5-20 Yellow/Orange
    // > 20 Red
    func bucketColor(for minFee: Double) -> Color {
        if minFee < 5 { return .green }
        if minFee < 15 { return .yellow }
        if minFee < 30 { return .orange }
        return .red
    }
}

// Re-defining the clean shape to be sure
struct DistributionBarShape: Shape {
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Start Bottom Left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Up to start of arc
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        // Top Left Arc
        path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
                    radius: radius,
                    startAngle: .degrees(180),
                    endAngle: .degrees(270),
                    clockwise: false)
        // Top Edge
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        // Top Right Arc
        path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
                    radius: radius,
                    startAngle: .degrees(270),
                    endAngle: .degrees(0),
                    clockwise: false)
        // Down to Bottom Right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Close bottom (optional if using Stroke, but good for Fill)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        
        return path
    }
}

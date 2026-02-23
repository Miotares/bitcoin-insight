//
//  TransactionRowView.swift
//  BitcoinWidgets
//

import SwiftUI

struct TransactionRowView: View {
    let tx: WalletTransaction
    let currency: String
    let btcPrice: Double
    var showCopied: Bool = false

    private var isReceived: Bool { tx.valueSats >= 0 }
    private var btcValue: Double { Double(abs(tx.valueSats)) / 100_000_000.0 }
    private var fiatValue: Double { btcValue * btcPrice }

    var body: some View {
        HStack(spacing: 14) {
            // Direction icon
            ZStack {
                Circle()
                    .fill(isReceived ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: isReceived ? "arrow.down.right" : "arrow.up.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isReceived ? .green : .red)
            }

            // Details
            VStack(alignment: .leading, spacing: 3) {
                Text(isReceived ? "Received" : "Sent")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 6) {
                    Circle()
                        .fill(tx.confirmed ? (isReceived ? Color.green : Color.red) : Color.orange)
                        .frame(width: 6, height: 6)
                    ZStack(alignment: .leading) {
                        Text("Copied to clipboard")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                            .opacity(showCopied ? 1 : 0)
                        Text(tx.confirmed ? relativeDate : "Unconfirmed")
                            .foregroundStyle(.secondary)
                            .opacity(showCopied ? 0 : 1)
                    }
                    .font(.caption)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(isReceived ? "+" : "-")\(Formatters.formatBTC(btcValue))")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(isReceived ? .green : .red)

                Text(Formatters.formatCurrency(value: fiatValue, currencyCode: currency))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var relativeDate: String {
        guard let blockTime = tx.blockTime else { return "Pending" }
        let date = Date(timeIntervalSince1970: TimeInterval(blockTime))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

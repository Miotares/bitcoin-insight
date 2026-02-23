//
//  Formatters.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import Foundation

struct Formatters {
    
    static func formatCurrency(value: Double, currencyCode: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        
        // Custom symbol logic based on user requirements
        switch currencyCode {
        case "USD":
            formatter.currencySymbol = "$"
        case "EUR":
            formatter.currencySymbol = "€"
        case "GBP":
            formatter.currencySymbol = "£"
        case "JPY":
            formatter.currencySymbol = "JPY" // Ambiguous ¥
        case "CNY":
            formatter.currencySymbol = "CNY" // Ambiguous ¥
        case "SEK":
            formatter.currencySymbol = "SEK" // Ambiguous kr
        case "CAD":
            formatter.currencySymbol = "CAD" // Ambiguous $
        case "AUD":
            formatter.currencySymbol = "AUD" // Ambiguous $
        case "HKD":
            formatter.currencySymbol = "HKD" // Ambiguous $
        case "CHF":
            formatter.currencySymbol = "CHF" // Standard
        default:
            // Fallback to ticker if not explicitly handled but potentially ambiguous,
            // or let system decide. For now, let's default to the ticker for safety 
            // if it's one of the other dollar/crown variants, but for unknown ones
            // we might want to stick to the code or symbol.
            // Given the limited list in Settings, the above covers all.
            // But to be safe for "Bei doppelten, dann der jeweilige Ticker":
            formatter.currencySymbol = currencyCode
        }
        
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    static func formatAmount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    static func formatSats(_ value: Int) -> String {
        return formatAmount(value) + " sats"
    }
    
    static func formatBTC(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " BTC"
    }
    
    static func formatLightningBTC(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return (formatter.string(from: NSNumber(value: value)) ?? "\(value)") + " BTC"
    }
    
    static func formatHashrate(_ hashrate: Double) -> String {
        let units = ["H/s", "KH/s", "MH/s", "GH/s", "TH/s", "PH/s", "EH/s", "ZH/s"]
        var value = hashrate
        var unitIndex = 0
        while value >= 1000 && unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        return "\(String(format: "%.2f", value)) \(units[unitIndex])"
    }
    
    static func formatDifficulty(_ difficulty: Double) -> String {
        if difficulty >= 1_000_000_000_000 {
            return String(format: "%.2f T", difficulty / 1_000_000_000_000)
        } else if difficulty >= 1_000_000_000 {
            return String(format: "%.2f G", difficulty / 1_000_000_000)
        } else if difficulty >= 1_000_000 {
            return String(format: "%.2f M", difficulty / 1_000_000)
        } else {
            return formatAmount(Int(difficulty))
        }
    }
    
    static func formatBytesToMB(_ bytes: Int) -> String {
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.2f", mb)
    }
    
    static func formatVMB(_ vbytes: Int) -> String {
        let vmb = Double(vbytes) / 1_000_000.0
        return String(format: "%.2f", vmb)
    }
    
    static func formatPercent(_ value: Double) -> String {
        return String(format: "%.2f%%", value)
    }
    
    static func formatDate(_ timestamp: Double) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

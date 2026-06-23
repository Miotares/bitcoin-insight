//
//  SettingsManager.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI
import Combine

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var preferredCurrency: String {
        didSet {
            UserDefaults.standard.set(preferredCurrency, forKey: "preferredCurrency")
            WidgetBridge.setCurrency(preferredCurrency)
        }
    }

    @Published var hapticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled")
        }
    }

    @Published var showWalletTab: Bool {
        didSet {
            UserDefaults.standard.set(showWalletTab, forKey: "showWalletTab")
        }
    }

    @Published var gapLimit: Int {
        didSet {
            UserDefaults.standard.set(gapLimit, forKey: "gapLimit")
        }
    }

    /// Live BTC prices per currency code, written by DashboardViewModel after every fetch.
    /// Never persisted — starts empty, populates within seconds of app launch.
    @Published var btcPrices: [String: Double] = [:]

    /// Tiny multiplier applied to displayed BTC prices so the value isn't a flat
    /// integer (mempool returns whole numbers, so an unadjusted price always ends
    /// in .00). Shared by the Dashboard hero and the Price detail view so both show
    /// the exact same adjusted price.
    static let priceDisplayMultiplier: Double = 1.00025

    private init() {
        self.preferredCurrency = UserDefaults.standard.string(forKey: "preferredCurrency") ?? "USD"
        self.hapticsEnabled = UserDefaults.standard.bool(forKey: "hapticsEnabled")
        self.showWalletTab = UserDefaults.standard.object(forKey: "showWalletTab") as? Bool ?? true
        self.gapLimit = UserDefaults.standard.object(forKey: "gapLimit") as? Int ?? 20
        WidgetBridge.setCurrency(preferredCurrency)   // mirror currency to widgets at launch
    }
}

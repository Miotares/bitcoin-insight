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
            syncWidgets()
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

    /// DEV ONLY: simulates the premium unlock so the widgets can be tested
    /// before the real StoreKit purchase exists. Mirrored to the App Group.
    @Published var widgetsPremiumDev: Bool {
        didSet {
            UserDefaults.standard.set(widgetsPremiumDev, forKey: "widgetsPremiumDev")
            syncWidgets()
        }
    }

    /// Live BTC prices per currency code, written by DashboardViewModel after every fetch.
    /// Never persisted — starts empty, populates within seconds of app launch.
    @Published var btcPrices: [String: Double] = [:]

    private init() {
        self.preferredCurrency = UserDefaults.standard.string(forKey: "preferredCurrency") ?? "USD"
        self.hapticsEnabled = UserDefaults.standard.bool(forKey: "hapticsEnabled")
        self.showWalletTab = UserDefaults.standard.object(forKey: "showWalletTab") as? Bool ?? true
        self.gapLimit = UserDefaults.standard.object(forKey: "gapLimit") as? Int ?? 20
        #if DEBUG
        self.widgetsPremiumDev = UserDefaults.standard.object(forKey: "widgetsPremiumDev") as? Bool ?? true
        #else
        self.widgetsPremiumDev = UserDefaults.standard.object(forKey: "widgetsPremiumDev") as? Bool ?? false
        #endif
        syncWidgets()
    }

    /// Pushes currency + premium state into the widgets' shared App Group container.
    private func syncWidgets() {
        WidgetBridge.sync(currency: preferredCurrency, isPremium: widgetsPremiumDev)
    }
}

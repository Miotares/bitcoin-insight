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

    @Published var showExploreTab: Bool {
        didSet {
            UserDefaults.standard.set(showExploreTab, forKey: "showExploreTab")
        }
    }

    @Published var gapLimit: Int {
        didSet {
            UserDefaults.standard.set(gapLimit, forKey: "gapLimit")
        }
    }

    /// Privacy: when on, private wallet amounts (BTC + fiat) are blurred and start
    /// hidden on every app launch. The user taps a balance to reveal them.
    @Published var hideBalances: Bool {
        didSet {
            UserDefaults.standard.set(hideBalances, forKey: "hideBalances")
            // Re-hide immediately when the user turns the setting on.
            if hideBalances { balancesRevealed = false }
        }
    }

    /// Session-only reveal flag. Never persisted: starts hidden on every launch and
    /// is reset to hidden whenever the app leaves the foreground (so the app-switcher
    /// snapshot and the next open both start blurred). Tapping a balance toggles it.
    @Published var balancesRevealed: Bool = false

    /// True when private wallet amounts should be visually blurred right now.
    var balancesHidden: Bool { hideBalances && !balancesRevealed }

    /// Privacy: when on, the Wallet tab is gated behind biometric / passcode auth.
    /// Only the Wallet tab is protected — every other tab stays open.
    @Published var requireWalletAuth: Bool {
        didSet {
            UserDefaults.standard.set(requireWalletAuth, forKey: "requireWalletAuth")
            // Turning the lock on re-locks immediately (the user re-auths on entry).
            if requireWalletAuth { isWalletUnlocked = false }
        }
    }

    /// Session-only: true once the owner has authenticated this foreground session.
    /// Never persisted — starts locked on every launch and is reset to locked when
    /// the app is backgrounded (see `BitcoinWidgetsApp`).
    @Published var isWalletUnlocked: Bool = false

    /// True when the Wallet tab should currently show its lock screen.
    var walletLocked: Bool { requireWalletAuth && !isWalletUnlocked }

    /// Live BTC prices per currency code, written by DashboardViewModel after every fetch.
    /// Never persisted — starts empty, populates within seconds of app launch.
    @Published var btcPrices: [String: Double] = [:]

    /// Latest Bitcoin tip height seen by DashboardViewModel's 10 s poll. The Wallet
    /// tab observes this to auto-refresh balances when a new block arrives (foreground
    /// only — the poll is suspended while backgrounded). Never persisted; starts at 0.
    @Published var observedBlockHeight: Int = 0

    /// Tiny multiplier applied to displayed BTC prices so the value isn't a flat
    /// integer (mempool returns whole numbers, so an unadjusted price always ends
    /// in .00). Shared by the Dashboard hero and the Price detail view so both show
    /// the exact same adjusted price.
    static let priceDisplayMultiplier: Double = 1.00025

    /// BTC price for `currencyCode` including the cosmetic display multiplier, so
    /// every surface (Dashboard hero, Price detail, Wallet valuations) shows the
    /// exact same adjusted price. Returns 0 until the first price fetch lands.
    func displayPrice(for currencyCode: String) -> Double {
        (btcPrices[currencyCode.uppercased()] ?? 0) * SettingsManager.priceDisplayMultiplier
    }

    private init() {
        self.preferredCurrency = UserDefaults.standard.string(forKey: "preferredCurrency") ?? "USD"
        self.hapticsEnabled = UserDefaults.standard.bool(forKey: "hapticsEnabled")
        self.showWalletTab = UserDefaults.standard.object(forKey: "showWalletTab") as? Bool ?? true
        self.showExploreTab = UserDefaults.standard.object(forKey: "showExploreTab") as? Bool ?? true
        self.gapLimit = UserDefaults.standard.object(forKey: "gapLimit") as? Int ?? 20
        self.hideBalances = UserDefaults.standard.bool(forKey: "hideBalances")
        self.requireWalletAuth = UserDefaults.standard.bool(forKey: "requireWalletAuth")
        WidgetBridge.setCurrency(preferredCurrency)   // mirror currency to widgets at launch
    }
}

//
//  BitcoinWidgetsApp.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI

@main
struct BitcoinWidgetsApp: App {
    @StateObject private var settings = SettingsManager.shared
    @StateObject private var store = StoreManager()
    @StateObject private var router = AppRouter()
    @State private var showPaywall = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(router)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $showPaywall) {
                    PaywallView().environmentObject(store)
                }
                .onOpenURL { url in
                    guard url.scheme == "bitcoininsight" else { return }
                    if url.host == "paywall" {
                        // Deep-link from a locked widget.
                        if !store.hasPremium { showPaywall = true }
                    } else if let route = DashboardRoute(host: url.host) {
                        // Deep-link from a single-metric widget to its detail view.
                        router.openDashboard(route)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // Reconcile any late / sandbox / Ask-to-Buy transaction that
                    // landed while backgrounded — unlocks without a cold relaunch
                    // and re-asserts the App Group flag for the widgets on every
                    // foreground.
                    if phase == .active {
                        Task {
                            // Retry a failed product load so the paywall recovers
                            // if the IAP became available since launch.
                            if store.product == nil { await store.loadProduct() }
                            await store.refreshEntitlements()
                        }
                    } else {
                        // Re-hide private wallet balances whenever the app leaves the
                        // foreground, so the app-switcher snapshot and the next open
                        // both start blurred (only relevant when the setting is on).
                        settings.balancesRevealed = false
                    }
                }
        }
    }
}

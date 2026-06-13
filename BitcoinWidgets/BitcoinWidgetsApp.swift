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
    @State private var showPaywall = false

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(settings)
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .sheet(isPresented: $showPaywall) {
                    PaywallView().environmentObject(store)
                }
                .onOpenURL { url in
                    // Deep-link from a locked widget: bitcoininsight://paywall
                    if url.scheme == "bitcoininsight", url.host == "paywall", !store.hasPremium {
                        showPaywall = true
                    }
                }
        }
    }
}

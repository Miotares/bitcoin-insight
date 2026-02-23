//
//  MainTabView.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//


import SwiftUI
import StoreKit

struct MainTabView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "bitcoinsign.circle.fill")
                }
                .tag(0)

            if settings.showWalletTab {
                WalletTabView()
                    .tabItem {
                        Label("Wallet", systemImage: "wallet.pass.fill")
                    }
                    .tag(1)
            }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(Color.bitcoinOrange)
        .onChange(of: settings.showWalletTab) { _, isShown in
            if !isShown && selectedTab == 1 {
                selectedTab = 0
            }
        }
        .onAppear {
            ReviewManager.shared.trackAppLaunch()
            if ReviewManager.shared.shouldRequest {
                ReviewManager.shared.markRequested()
                // Small delay so the user sees the app before the prompt
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    requestReview()
                }
            }
        }
    }
}

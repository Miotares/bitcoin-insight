//
//  MainTabView.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//


import SwiftUI
import StoreKit

struct MainTabView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var router: AppRouter
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                }
                .tag(0)

            if settings.showExploreTab {
                ExploreView()
                    .tabItem {
                        Label("Explore", systemImage: "magnifyingglass")
                    }
                    .tag(3)
            }

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
            if !isShown && router.selectedTab == 1 {
                router.selectedTab = 0
            }
        }
        .onChange(of: settings.showExploreTab) { _, isShown in
            if !isShown {
                // Drop any queued deep-link so re-enabling Explore later can't
                // replay a stale route, and leave the now-missing tab.
                router.pendingExploreRoute = nil
                if router.selectedTab == AppRouter.exploreTab {
                    router.selectedTab = 0
                }
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

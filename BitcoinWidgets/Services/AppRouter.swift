//
//  AppRouter.swift
//  BitcoinWidgets
//
//  Tiny app-wide router so any screen can jump into the Explore tab and deep-link
//  to a block / transaction / address (e.g. the Dashboard's "See in Explorer").
//  Injected once at the app root.
//

import SwiftUI
import Combine

@MainActor
final class AppRouter: ObservableObject {
    /// Mirrors the TabView selection. Explore is tag 3.
    @Published var selectedTab: Int = 0

    /// A route the Explore tab should push as soon as it's shown. Explore consumes
    /// and clears it.
    @Published var pendingExploreRoute: ExploreRoute?

    static let exploreTab = 3

    /// Switch to the Explore tab and (optionally) deep-link to a detail route.
    func openInExplorer(_ route: ExploreRoute? = nil) {
        pendingExploreRoute = route
        selectedTab = AppRouter.exploreTab
    }
}

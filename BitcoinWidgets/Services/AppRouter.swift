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

/// A Dashboard detail screen a widget (or another entry point) can deep-link to.
/// Only the metrics that have BOTH a single-metric widget and a dedicated detail
/// view — a clean 1:1 mapping. Multi-metric bundle widgets have no route.
enum DashboardRoute: Hashable {
    case price, block, mempool, difficulty, hashrate, fees, moscow, supply, halving, lightning

    /// Maps a `bitcoininsight://<host>` deep-link host to a route (nil if unknown).
    init?(host: String?) {
        switch host {
        case "price":      self = .price
        case "block":      self = .block
        case "mempool":    self = .mempool
        case "difficulty": self = .difficulty
        case "hashrate":   self = .hashrate
        case "fees":       self = .fees
        case "moscow":     self = .moscow
        case "supply":     self = .supply
        case "halving":    self = .halving
        case "lightning":  self = .lightning
        default:           return nil
        }
    }
}

@MainActor
final class AppRouter: ObservableObject {
    /// Mirrors the TabView selection. Explore is tag 3.
    @Published var selectedTab: Int = 0

    /// A route the Explore tab should push as soon as it's shown. Explore consumes
    /// and clears it.
    @Published var pendingExploreRoute: ExploreRoute?

    /// A route the Dashboard should push as soon as it's shown (widget deep-links).
    /// The Dashboard consumes and clears it.
    @Published var pendingDashboardRoute: DashboardRoute?

    static let dashboardTab = 0
    static let exploreTab = 3

    /// Switch to the Explore tab and (optionally) deep-link to a detail route.
    func openInExplorer(_ route: ExploreRoute? = nil) {
        pendingExploreRoute = route
        selectedTab = AppRouter.exploreTab
    }

    /// Switch to the Dashboard tab and deep-link to one of its detail screens.
    func openDashboard(_ route: DashboardRoute) {
        pendingDashboardRoute = route
        selectedTab = AppRouter.dashboardTab
    }
}

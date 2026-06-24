//
//  InsightWidgetsBundle.swift
//  InsightWidgets
//

import WidgetKit
import SwiftUI

@main
struct InsightWidgetsBundle: WidgetBundle {
    var body: some Widget {
        // Single metrics
        InsightWidgets()        // price
        PriceChartWidget()      // price + 24h chart
        BlockHeightWidget()
        HalvingWidget()
        MoscowWidget()
        FeesWidget()
        HashrateWidget()
        MempoolWidget()
        SupplyWidget()
        LightningWidget()
        // Themed bundles
        NetworkWidget()         // block + fees + halving
        MiningWidget()          // hashrate + difficulty + adjustment
        MarketWidget()          // price + moscow + supply
        OverviewWidget()        // systemLarge — everything
    }
}

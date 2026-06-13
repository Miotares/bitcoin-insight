//
//  InsightWidgetsBundle.swift
//  InsightWidgets
//

import WidgetKit
import SwiftUI

@main
struct InsightWidgetsBundle: WidgetBundle {
    var body: some Widget {
        InsightWidgets()        // price
        NetworkWidget()         // block height + fees + halving %
        HalvingWidget()         // halving countdown
        BlockHeightWidget()     // block height
    }
}

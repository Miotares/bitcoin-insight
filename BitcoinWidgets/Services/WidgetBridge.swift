//
//  WidgetBridge.swift
//  BitcoinWidgets
//
//  App-side writer for the App Group that the widgets read. Mirrors the
//  preferred currency and the premium flag, then asks WidgetKit to reload.
//
//  NOTE: suiteName + keys must stay identical to AppGroupStore in the
//  InsightWidgets target.
//

import Foundation
import WidgetKit

enum WidgetBridge {
    static let suiteName = "group.miotares.BitcoinWidgets"

    enum Key {
        static let isPremium = "widget.isPremium"
        static let preferredCurrency = "widget.preferredCurrency"
    }

    /// Writes the current state into the shared container and reloads widgets.
    static func sync(currency: String, isPremium: Bool) {
        let defaults = UserDefaults(suiteName: suiteName)
        defaults?.set(currency, forKey: Key.preferredCurrency)
        defaults?.set(isPremium, forKey: Key.isPremium)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

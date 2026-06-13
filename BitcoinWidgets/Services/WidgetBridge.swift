//
//  WidgetBridge.swift
//  BitcoinWidgets
//
//  App-side writer for the App Group the widgets read. Currency is mirrored by
//  SettingsManager; the premium flag by StoreManager. Each write reloads widgets.
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

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func setCurrency(_ currency: String) {
        defaults?.set(currency, forKey: Key.preferredCurrency)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func setPremium(_ isPremium: Bool) {
        defaults?.set(isPremium, forKey: Key.isPremium)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

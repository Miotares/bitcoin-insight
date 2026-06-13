//
//  AppGroupStore.swift
//  InsightWidgets
//
//  Shared container between the app and the widget. The app writes the
//  premium flag + preferred currency here (see WidgetBridge in the app target);
//  the widget reads them and caches its last good snapshot here.
//
//  NOTE: the suite name + keys must stay identical to WidgetBridge in the app.
//

import Foundation

enum AppGroupStore {
    static let suiteName = "group.miotares.BitcoinWidgets"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    enum Key {
        static let isPremium = "widget.isPremium"
        static let preferredCurrency = "widget.preferredCurrency"
        static let cachedSnapshot = "widget.cachedSnapshot"
    }

    static var isPremium: Bool {
        defaults?.bool(forKey: Key.isPremium) ?? false
    }

    static var preferredCurrency: String {
        defaults?.string(forKey: Key.preferredCurrency) ?? "USD"
    }

    static func loadCachedSnapshot() -> NetworkSnapshot? {
        guard let data = defaults?.data(forKey: Key.cachedSnapshot) else { return nil }
        return try? JSONDecoder().decode(NetworkSnapshot.self, from: data)
    }

    static func saveCachedSnapshot(_ snapshot: NetworkSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Key.cachedSnapshot)
    }
}

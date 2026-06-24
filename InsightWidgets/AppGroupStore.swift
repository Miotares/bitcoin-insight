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
        guard let data = defaults?.data(forKey: Key.cachedSnapshot),
              let snapshot = try? JSONDecoder().decode(NetworkSnapshot.self, from: data) else { return nil }
        // Discard a pre-expansion cache (saved when the backend served only the 7
        // mempool currencies). Without this, after an app upgrade a widget set to one
        // of the 12 newer currencies would fall back to the USD value (price(for:))
        // and render it under the wrong code (e.g. "R$63,922") until the first fresh
        // fetch. A non-mempool key like THB is present only in the full 19-key payload.
        guard snapshot.prices["THB"] != nil else { return nil }
        return snapshot
    }

    static func saveCachedSnapshot(_ snapshot: NetworkSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Key.cachedSnapshot)
    }
}

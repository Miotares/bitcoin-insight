//
//  BitcoinWidgetsApp.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI

@main
struct BitcoinWidgetsApp: App {
    @StateObject private var settings = SettingsManager.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(settings)
                .preferredColorScheme(.dark)
        }
    }
}

//
//  Haptics.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 02.12.25.
//

import SwiftUI

struct Haptics {
    static func trigger(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard SettingsManager.shared.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
    
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard SettingsManager.shared.hapticsEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
    }
    
    static func selection() {
        guard SettingsManager.shared.hapticsEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }
}

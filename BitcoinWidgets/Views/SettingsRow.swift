//
//  SettingsRow.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI

struct SettingsRow<Content: View>: View {
    let icon: String?
    let iconColor: Color?
    let title: String
    let content: Content
    
    init(icon: String? = nil, iconColor: Color? = nil, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.iconColor = iconColor
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        HStack(spacing: 16) {
            if let icon = icon, let iconColor = iconColor {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.15))
                    .clipShape(Circle())
            }
            
            Text(title)
                .font(.system(.body, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            
            Spacer()
            
            content
        }
        .padding(.vertical, 8)
    }
}

// Convenience init for simple text values or navigation indicators
extension SettingsRow where Content == AnyView {
    init(icon: String? = nil, iconColor: Color? = nil, title: String, value: String? = nil, showChevron: Bool = false) {
        self.init(icon: icon, iconColor: iconColor, title: title) {
            AnyView(
                HStack(spacing: 8) {
                    if let value = value {
                        Text(value)
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .rounded))
                    }
                    if showChevron {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            )
        }
    }
}

//
//  DetailRow.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI

struct DetailRow: View {
    let title: String
    let value: String
    var helpText: String? = nil
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                Spacer()
                Text(value)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                    .onChange(of: value) { _, _ in
                        Haptics.trigger()
                    }
            }
            
            if let help = helpText {
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Divider()
                .padding(.top, 4)
        }
    }
}

//
//  DetailStatCard.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 02.12.25.
//

import SwiftUI

struct DetailStatCard: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.cardLabel)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .onChange(of: value) { _, _ in
                    Haptics.trigger()
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Spacing.lg)
    }
}

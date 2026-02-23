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
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
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
        .padding()
        .background(Material.ultraThin)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

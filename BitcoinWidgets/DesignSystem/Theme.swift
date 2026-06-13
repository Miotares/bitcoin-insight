//
//  Theme.swift
//  BitcoinWidgets
//
//  Central design tokens — single source of truth for spacing, radii,
//  accent colors and typography. Keeps the existing simple Material-glass
//  style; just makes it consistent across the app.
//

import SwiftUI

enum Theme {

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
    }

    // MARK: - Corner Radius

    enum Radius {
        static let card: CGFloat = 24
        static let inner: CGFloat = 16
        static let chip: CGFloat = 12
    }

    // MARK: - Accent Colors (hybrid strategy)
    //
    // Color is used only where it carries meaning. Icons default to a muted
    // tone; semantic green/red are reserved for direction and fee tiers;
    // bitcoinOrange is the single brand accent.

    enum Accent {
        static let brand = Color.bitcoinOrange
        static let icon = Color.secondary       // muted icon tint (unused by default)
        static let up = Color.green
        static let down = Color.red
        static let feeLow = Color.green
        static let feeMid = Color.orange
        static let feeHigh = Color.red

        // Per-stat icon hues (colorful icon style)
        static let blockHeight = Color.blue
        static let mempool = Color.purple
        static let difficulty = Color.green
        static let hashrate = Color.cyan
        static let networkFees = Color.green
        static let feeDistribution = Color.purple
        static let moscowTime = Color.red
        static let circulatingSupply = Color.blue
        static let lightning = Color.yellow
    }

    // MARK: - Strokes / Borders

    enum Stroke {
        /// Subtle hairline that crisps up the glass card edge in dark mode.
        static let hairline = Color.white.opacity(0.08)
    }

    // MARK: - Card Shadow

    enum Shadow {
        static let cardColor = Color.black.opacity(0.03)
        static let cardRadius: CGFloat = 10
        static let cardY: CGFloat = 4
    }
}

// MARK: - Typography Roles

extension Font {
    /// Big hero number (e.g. the live price).
    static let heroValue = Font.system(size: 40, weight: .bold, design: .rounded)
    /// Primary value inside a stat card.
    static let cardValue = Font.system(.title3, design: .rounded).weight(.bold)
    /// Small muted label above a card value.
    static let cardLabel = Font.caption
    /// Section header inside wide cards.
    static let sectionHeader = Font.headline
    /// Unit suffix (sat/vB, txs, …).
    static let unit = Font.caption2
}

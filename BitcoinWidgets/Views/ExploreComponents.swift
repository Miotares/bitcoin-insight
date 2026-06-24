//
//  ExploreComponents.swift
//  BitcoinWidgets
//
//  Small shared building blocks for the Explore detail screens.
//

import SwiftUI

/// A simple "label … value" row used inside grouped cards. Distinct from
/// `DetailRow` (which carries its own divider + haptic); here the caller places
/// dividers between rows so the card reads as one grouped surface.
struct KeyValueRow: View {
    let title: String
    let value: String
    var valueColor: Color = .primary
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: Theme.Spacing.md)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .modifier(MonospacedIf(active: monospaced))
        }
        .padding(.vertical, Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
    }
}

private struct MonospacedIf: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.font(.system(.callout, design: .monospaced)) }
        else { content }
    }
}

/// A small brand-tinted capsule that gently breathes a glow — used to mark
/// something special (a coinbase tx, the genesis / halving / milestone block).
/// Calm, not flashy: a slow soft pulse, not a strobe.
struct GlowBadge: View {
    let title: String
    let systemImage: String
    @State private var glow = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).fontWeight(.semibold)
        }
        .font(.caption)
        .foregroundStyle(Color.bitcoinOrange)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Capsule().fill(Color.bitcoinOrange.opacity(0.15)))
        .overlay(Capsule().strokeBorder(Color.bitcoinOrange.opacity(glow ? 0.55 : 0.2), lineWidth: 1))
        .shadow(color: Color.bitcoinOrange.opacity(glow ? 0.45 : 0.12), radius: glow ? 14 : 5)
        .animation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = true }
    }
}

/// A milestone block worth marking prominently: the genesis block, a halving
/// block, or a round-number height.
struct SpecialBlock: Equatable {
    let title: String
    let icon: String
    /// Genesis glows full gold; halvings / milestones use the brand orange.
    let gold: Bool

    var tint: Color {
        gold ? Color(red: 0.97, green: 0.74, blue: 0.22) : Color.bitcoinOrange
    }

    /// The genesis block, a halving block, or a round-number milestone — or nil
    /// for an ordinary block. Shared by the block detail hero and the feed row.
    static func `for`(height: Int) -> SpecialBlock? {
        if height == 0 {
            return SpecialBlock(title: "Genesis Block", icon: "crown.fill", gold: true)
        }
        if height % 210_000 == 0 {
            return SpecialBlock(title: "Halving Block · Epoch \(height / 210_000)", icon: "scissors", gold: false)
        }
        if height % 100_000 == 0 {
            return SpecialBlock(title: "Milestone · Block \(Formatters.formatAmount(height))", icon: "flag.checkered", gold: false)
        }
        return nil
    }
}

/// Prominent, gently breathing badge for a special block — bigger and warmer
/// than `GlowBadge`, with a soft scale pulse so it clearly stands out.
struct SpecialBlockBadge: View {
    let special: SpecialBlock
    @State private var glow = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: special.icon)
            Text(special.title).fontWeight(.bold)
        }
        .font(.subheadline)
        .foregroundStyle(special.tint)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Capsule().fill(special.tint.opacity(0.18)))
        .overlay(Capsule().strokeBorder(special.tint.opacity(glow ? 0.7 : 0.3), lineWidth: 1.2))
        .shadow(color: special.tint.opacity(glow ? 0.6 : 0.2), radius: glow ? 18 : 6)
        .scaleEffect(glow ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true), value: glow)
        .onAppear { glow = true }
    }
}

/// Inline error state with a retry affordance, matching the calm dark style.
struct ErrorState: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let retry {
                Button("Retry", action: retry)
                    .foregroundStyle(Color.bitcoinOrange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 100)
        .padding(.horizontal, Theme.Spacing.xl)
    }
}

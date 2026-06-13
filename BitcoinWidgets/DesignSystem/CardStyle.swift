//
//  CardStyle.swift
//  BitcoinWidgets
//
//  Reusable card surface + tactile press feedback. Replaces the ~25 copies
//  of `Material.ultraThin` + `RoundedRectangle` + shadow that were scattered
//  across the views. Change the look here once → it updates everywhere.
//

import SwiftUI

/// The translucent card surface only — background, rounded clip, hairline
/// edge and the subtle shadow. No padding, so callers that manage their own
/// padding / fixed height (e.g. the grid stat cards) can apply this directly.
struct CardSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Material.ultraThin)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Stroke.hairline, lineWidth: 0.5)
            )
            .shadow(
                color: Theme.Shadow.cardColor,
                radius: Theme.Shadow.cardRadius,
                x: 0,
                y: Theme.Shadow.cardY
            )
    }
}

extension View {
    /// Standard card surface without padding (caller controls insets).
    func cardSurface() -> some View {
        modifier(CardSurfaceModifier())
    }

    /// Pads the content and wraps it in the standard card surface.
    func card(padding: CGFloat = Theme.Spacing.xl) -> some View {
        self.padding(padding).cardSurface()
    }
}

/// Tactile press feedback for tappable cards (NavigationLink / Button).
/// Replaces a bare `.buttonStyle(.plain)` where a press cue is desired.
struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

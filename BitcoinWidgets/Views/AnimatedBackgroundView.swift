//
//  AnimatedBackgroundView.swift
//  BitcoinWidgets
//
//  Calm, curated backdrop: a flat dark base with one soft, slowly drifting
//  brand-tinted glow. `accentColor` lets a screen personalise the tint
//  (e.g. the wallet detail uses the wallet's colour).
//

import SwiftUI

struct AnimatedBackgroundView: View {
    var accentColor: Color? = nil
    @State private var animate = false

    private var tint: Color { accentColor ?? Theme.Accent.brand }

    var body: some View {
        ZStack {
            // Pure black everywhere — incl. modal sheets, which otherwise use
            // iOS's lighter "elevated" system background (grayish) in dark mode.
            Color.black
                .ignoresSafeArea()

            // Primary soft glow
            Circle()
                .fill(tint.opacity(0.12))
                .frame(width: 420, height: 420)
                .blur(radius: 100)
                .offset(x: animate ? -90 : 90, y: animate ? -160 : -120)
                .animation(.easeInOut(duration: 34).repeatForever(autoreverses: true), value: animate)

            // Faint secondary glow for subtle depth
            Circle()
                .fill(tint.opacity(0.05))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: animate ? 110 : -110, y: animate ? 200 : 160)
                .animation(.easeInOut(duration: 42).repeatForever(autoreverses: true), value: animate)
        }
        .ignoresSafeArea()
        .onAppear { animate.toggle() }
    }
}

#Preview {
    AnimatedBackgroundView()
}

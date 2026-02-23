//
//  AnimatedBackgroundView.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI

struct AnimatedBackgroundView: View {
    var accentColor: Color? = nil
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Base background color
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            // Blob 1: Accent or Bitcoin Orange
            Circle()
                .fill((accentColor ?? .bitcoinOrange).opacity(0.2))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animate ? -100 : 100, y: animate ? -100 : 100)
                .animation(.easeInOut(duration: 30).repeatForever(autoreverses: true), value: animate)
            
            // Blob 2: Blue
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 350, height: 350)
                .blur(radius: 60)
                .offset(x: animate ? 150 : -150, y: animate ? 100 : -100)
                .animation(.easeInOut(duration: 35).repeatForever(autoreverses: true), value: animate)
            
            // Blob 3: Purple
            Circle()
                .fill(Color.purple.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 60)
                .offset(x: animate ? -50 : 50, y: animate ? 200 : -200)
                .animation(.easeInOut(duration: 40).repeatForever(autoreverses: true), value: animate)
        }
        .ignoresSafeArea()
        .onAppear {
            animate.toggle()
        }
    }
}

#Preview {
    AnimatedBackgroundView()
}

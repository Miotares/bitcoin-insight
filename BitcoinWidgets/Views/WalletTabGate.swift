//
//  WalletTabGate.swift
//  BitcoinWidgets
//
//  Wraps the Wallet tab in an optional biometric lock. When `requireWalletAuth`
//  is on, the wallet content is replaced by a lock screen until the owner passes
//  Face ID / Touch ID / passcode. The gate ONLY protects the Wallet tab — every
//  other tab stays open. The actual wallet view (and its data) is not even built
//  while locked.
//

import SwiftUI

struct WalletTabGate: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isAuthenticating = false
    @State private var didFail = false

    var body: some View {
        // The branch is driven ONLY by `walletLocked` (a real lock), so a transient
        // `.inactive` does NOT swap branches and therefore never tears down
        // WalletTabView / its WalletViewModel mid-scan. The snapshot privacy cover is
        // an OVERLAY on top — see `privacyCover`.
        Group {
            if settings.walletLocked {
                WalletLockView(
                    isAuthenticating: isAuthenticating,
                    didFail: didFail,
                    onUnlock: { authenticate() }
                )
                .transition(.opacity)
            } else {
                WalletTabView()
                    .transition(.opacity)
            }
        }
        .overlay { privacyCover }
        // NOTE: authentication is NOT triggered automatically. Opening the Wallet
        // tab (cold launch, tab switch, or resuming from background) just presents
        // WalletLockView with its explicit "Unlock with Face ID" button; the Face ID
        // / passcode prompt fires only when the owner taps that button. This avoids a
        // surprise system prompt the moment the tab is selected.
    }

    /// Opaque cover shown while the lock is enabled and the app is NOT active, so the
    /// app-switcher snapshot (captured during `.inactive`, before `.background`) never
    /// contains wallet content. Driven directly off the scenePhase environment value
    /// (not via async state) and not wrapped in any animation, so it engages instantly.
    /// It is an overlay, not a branch swap, so WalletTabView stays mounted across a
    /// transient `.inactive` and is only torn down by a real lock.
    @ViewBuilder
    private var privacyCover: some View {
        if settings.requireWalletAuth && scenePhase != .active {
            WalletPrivacyCover()
        }
    }

    /// Runs Face ID / Touch ID / passcode auth. Called only from the lock screen's
    /// Unlock button — never automatically — and guarded so a second tap while a
    /// prompt is already in flight is ignored.
    private func authenticate() {
        guard settings.walletLocked, !isAuthenticating else { return }
        isAuthenticating = true
        didFail = false
        Task { @MainActor in
            let success = await BiometricAuthService.authenticate(reason: "Unlock your wallet")
            isAuthenticating = false
            if success {
                withAnimation(.easeOut(duration: 0.25)) { settings.isWalletUnlocked = true }
            } else {
                didFail = true
            }
        }
    }
}

// MARK: - Privacy Cover (app-switcher snapshot)

/// A neutral, fully opaque cover with no controls — it only ever appears while the
/// app is inactive/backgrounded, so the user never interacts with it; it just keeps
/// the wallet out of the multitasking snapshot.
private struct WalletPrivacyCover: View {
    var body: some View {
        ZStack {
            Color.black
            AnimatedBackgroundView()
            Image(systemName: "lock.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(Color.bitcoinOrange)
                .symbolRenderingMode(.hierarchical)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Lock Screen

struct WalletLockView: View {
    var isAuthenticating: Bool
    var didFail: Bool
    var onUnlock: () -> Void

    private static func iconName(for kind: BiometricAuthService.BiometryKind) -> String {
        switch kind {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        case .none:    return "lock.fill"
        }
    }

    private static func unlockLabel(for kind: BiometricAuthService.BiometryKind) -> String {
        switch kind {
        case .faceID:  return "Unlock with Face ID"
        case .touchID: return "Unlock with Touch ID"
        case .opticID: return "Unlock with Optic ID"
        case .none:    return "Unlock"
        }
    }

    var body: some View {
        // Resolve biometry once per render rather than allocating an LAContext per
        // derived value.
        let kind = BiometricAuthService.biometryKind()
        let iconName = Self.iconName(for: kind)
        let unlockLabel = Self.unlockLabel(for: kind)

        return ZStack {
            AnimatedBackgroundView()

            VStack(spacing: 28) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(Color.bitcoinOrange)
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Wallet Locked")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Authenticate to view your balances and transactions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                if didFail {
                    // Covers both a real biometric failure and a deliberate cancel —
                    // the owner taps the button below to retry either way.
                    Text("Not unlocked. Tap to try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button(action: onUnlock) {
                    HStack(spacing: 8) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: iconName == "lock.fill" ? "lock.open.fill" : iconName)
                        }
                        Text(unlockLabel)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.bitcoinOrange)
                    .clipShape(Capsule())
                }
                .disabled(isAuthenticating)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
}

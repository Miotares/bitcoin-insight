//
//  BiometricAuthService.swift
//  BitcoinWidgets
//
//  Thin wrapper around LocalAuthentication for the Wallet-tab lock. Uses
//  `.deviceOwnerAuthentication` so the device passcode is always a fallback —
//  Face ID / Touch ID first, passcode if biometry is unavailable or fails.
//  Wallet data never leaves the device; this is a purely local gate.
//

import Foundation
import LocalAuthentication

enum BiometricAuthService {

    /// The biometry hardware available on this device, for labelling the UI.
    enum BiometryKind {
        case faceID, touchID, opticID, none
    }

    /// Whether the device can authenticate its owner at all (biometry OR passcode).
    /// False only on a device with no passcode set — in which case we cannot gate.
    static func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// The biometry kind for labelling. `canEvaluatePolicy` must be called before
    /// reading `biometryType`, otherwise it reports `.none`.
    static func biometryKind() -> BiometryKind {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
        switch context.biometryType {
        case .faceID:  return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default:       return .none
        }
    }

    /// Prompts the owner to authenticate (biometry, falling back to passcode).
    /// Never throws: any failure — user cancel, biometry lockout, no match —
    /// resolves to `false` so callers stay locked. Returns `true` immediately on a
    /// device that cannot authenticate at all (no passcode), so the owner is never
    /// permanently locked out of their own wallet.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var canEvalError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &canEvalError) else {
            return true
        }
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}

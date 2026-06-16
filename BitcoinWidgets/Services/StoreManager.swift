//
//  StoreManager.swift
//  BitcoinWidgets
//
//  StoreKit 2 — the single source of truth for the lifetime "Premium" unlock
//  (a non-consumable). On any entitlement change it mirrors the flag into the
//  App Group so the widgets unlock, and reloads them.
//
//  Guiding rule: a user whose payment SUCCEEDED must never be left locked.
//  Therefore we (1) honor .success regardless of StoreKit's on-device JWS
//  verification, (2) always finish the transaction so it can't loop or feel
//  re-buyable, (3) unlock optimistically the moment the payment succeeds, and
//  (4) only ever RE-LOCK on an explicit revocation (refund / chargeback). A
//  transient or empty currentEntitlements result never clobbers a granted
//  unlock. On-device verification adds no real protection for a 4.99 €
//  client-only flag — the user has already paid Apple — and refunds still
//  revoke via revocationDate.
//

import Foundation
import StoreKit
import Combine
import os

@MainActor
final class StoreManager: ObservableObject {
    nonisolated static let productID = "miotares.BitcoinWidgets.widgets.lifetime"

    @Published private(set) var product: Product?
    @Published private(set) var isPremium = false
    @Published var purchaseError: String?        // genuine errors → shown in red
    @Published var infoMessage: String?          // neutral status (restore result, pending) → shown muted
    @Published var isRestoring = false

    /// Whether the premium feature (the widgets) is unlocked.
    var hasPremium: Bool { isPremium }

    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: "miotares.BitcoinWidgets", category: "StoreKit")

    init() {
        // Durable seed: the App Group flag is written on every entitlement change
        // and persists across app restarts, so a previously-unlocked user starts
        // UNLOCKED even when Transaction.currentEntitlements comes back empty at
        // launch (offline, a StoreKit hiccup, or sandbox not surfacing the
        // non-consumable). This is the fix for "premium resets after an app
        // restart". refreshEntitlements() only ever RE-LOCKS on an explicit
        // revocation, so seeding here can never unlock a user who never paid
        // (the flag starts false and is only set true after a real purchase).
        isPremium = WidgetBridge.isPremium
        updatesTask = listenForTransactions()
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Catalog

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if products.isEmpty {
                // Empty here means an App Store Connect problem (product not
                // Approved, not attached to the version, ID mismatch, or the
                // Paid Apps agreement inactive). No code can fix that — but
                // surface it so the paywall is never a silent dead-end (the
                // user can pull-to-retry instead of staring at a disabled button).
                log.error("No product returned for \(Self.productID, privacy: .public) — check App Store Connect (state/attachment/ID, Paid Apps agreement).")
                purchaseError = "The store is unavailable right now. Pull down to retry."
            } else {
                purchaseError = nil
                log.info("Loaded product \(Self.productID, privacy: .public) price=\(self.product?.displayPrice ?? "?", privacy: .public)")
            }
        } catch {
            log.error("Product load failed: \(error.localizedDescription, privacy: .public)")
            purchaseError = "The store is unavailable right now. Pull down to retry."
        }
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var foundActive = false
        var foundRevoked = false
        var seen = 0
        for await result in Transaction.currentEntitlements {
            let tx = transaction(from: result)
            seen += 1
            guard tx.productID == Self.productID else { continue }
            if tx.revocationDate == nil { foundActive = true } else { foundRevoked = true }
        }
        log.info("refreshEntitlements: entitlements=\(seen) active=\(foundActive) revoked=\(foundRevoked) current=\(self.isPremium)")

        if foundActive {
            updatePremium(true)
        } else if foundRevoked {
            // Definitive revoke (refund / chargeback) → re-lock.
            updatePremium(false)
        } else {
            // No information (empty or unrelated). Do NOT clobber a unlock that
            // was already granted optimistically — only re-assert the flag so
            // the widgets' App Group stays in sync.
            pushEntitlement()
        }
    }

    // MARK: - Purchase / Restore

    @discardableResult
    func purchase() async -> Bool {
        guard let product else {
            // product == nil is the App Store Connect / load-failure path.
            log.error("purchase() aborted: product is nil (not loaded from the store).")
            purchaseError = "The store is unavailable right now. Please try again later."
            return false
        }
        purchaseError = nil
        infoMessage = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                // The payment went through — honor it regardless of verified vs
                // unverified, never leave a paid user locked. Finish so the
                // transaction can't loop or appear re-buyable.
                let tx = transaction(from: verification)
                await tx.finish()
                updatePremium(true)          // immediate optimistic unlock + mirror
                await refreshEntitlements()  // reconcile (sticky — won't re-lock)
                log.info("purchase() success: premium granted for \(Self.productID, privacy: .public)")
                return true

            case .userCancelled:
                log.info("purchase() userCancelled")
                return false

            case .pending:
                // Ask-to-Buy / SCA: the transaction may arrive later via
                // Transaction.updates or the next foreground refresh. This is a
                // normal state, not an error — show it muted, not in red.
                log.info("purchase() pending (awaiting approval)")
                infoMessage = "Your purchase is pending approval. It will unlock once approved."
                return false

            @unknown default:
                log.error("purchase() unknown PurchaseResult")
                return false
            }
        } catch {
            log.error("purchase() threw: \(error.localizedDescription, privacy: .public)")
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        isRestoring = true
        infoMessage = nil
        purchaseError = nil          // clear any stale error before restoring
        defer { isRestoring = false }
        log.info("restore() syncing with the App Store…")
        do {
            try await AppStore.sync()
        } catch {
            log.error("restore() AppStore.sync failed: \(error.localizedDescription, privacy: .public)")
            purchaseError = error.localizedDescription
            return
        }
        await refreshEntitlements()
        // Always give explicit feedback — App Review taps Restore on a fresh
        // Apple ID that owns nothing, and a silent button reads as broken.
        infoMessage = isPremium
            ? "Purchases restored."
            : "No previous purchase found on this Apple ID."
        log.info("restore() done: isPremium=\(self.isPremium)")
    }

    // MARK: - Internals

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { continue }
                // Honor + finish EVERY incoming transaction (verified or not),
                // otherwise an unfinished one keeps looping and never unlocks.
                let tx = await self.transaction(from: result)
                await tx.finish()
                if tx.productID == Self.productID, tx.revocationDate == nil {
                    await self.updatePremium(true)
                }
                await self.refreshEntitlements()
            }
        }
    }

    /// Extract the transaction from either verification case. We deliberately
    /// honor `.unverified` for this 4.99 € client-only unlock (verification adds
    /// no real protection; the user has already paid Apple) and log the error so
    /// the unverified path is visible in Console rather than silently dropped.
    private func transaction(from result: VerificationResult<Transaction>) -> Transaction {
        switch result {
        case .verified(let tx):
            return tx
        case .unverified(let tx, let error):
            log.error("Honoring UNVERIFIED transaction for \(tx.productID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return tx
        }
    }

    /// Single funnel for flipping the flag so the App Group mirror + widget
    /// reload happen on every state change.
    private func updatePremium(_ newValue: Bool) {
        if isPremium != newValue { isPremium = newValue }
        pushEntitlement()
    }

    /// Mirror the effective entitlement to the widgets' App Group.
    private func pushEntitlement() {
        WidgetBridge.setPremium(hasPremium)
    }
}

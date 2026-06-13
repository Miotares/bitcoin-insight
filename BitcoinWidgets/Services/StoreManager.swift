//
//  StoreManager.swift
//  BitcoinWidgets
//
//  StoreKit 2 — the single source of truth for the lifetime "Premium" unlock
//  (a non-consumable). On any entitlement change it mirrors the flag into the
//  App Group so the widgets unlock, and reloads them.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class StoreManager: ObservableObject {
    static let productID = "miotares.BitcoinWidgets.widgets.lifetime"

    @Published private(set) var product: Product?
    @Published private(set) var isPremium = false
    @Published var purchaseError: String?

    #if DEBUG
    /// Dev-only override so the unlocked state can be tested without a purchase.
    @Published var debugForceUnlock: Bool = UserDefaults.standard.bool(forKey: "debugForceUnlock") {
        didSet {
            UserDefaults.standard.set(debugForceUnlock, forKey: "debugForceUnlock")
            pushEntitlement()
        }
    }
    #endif

    /// Effective premium that gates the feature and drives the widgets.
    var hasPremium: Bool {
        #if DEBUG
        return isPremium || debugForceUnlock
        #else
        return isPremium
        #endif
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Catalog

    func loadProduct() async {
        product = try? await Product.products(for: [Self.productID]).first
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == Self.productID,
               tx.revocationDate == nil {
                owned = true
            }
        }
        isPremium = owned
        pushEntitlement()
    }

    // MARK: - Purchase / Restore

    @discardableResult
    func purchase() async -> Bool {
        guard let product else { return false }
        purchaseError = nil
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    await refreshEntitlements()
                    return true
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: - Internals

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
    }

    /// Mirror the effective entitlement to the widgets' App Group.
    private func pushEntitlement() {
        WidgetBridge.setPremium(hasPremium)
    }
}

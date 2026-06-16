//
//  PaywallView.swift
//  BitcoinWidgets
//
//  The premium unlock sheet (lifetime, one-time). Flat design language.
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    private var priceTitle: String {
        if let price = store.product?.displayPrice { return "Unlock for \(price)" }
        return "Unlock"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel("Premium")
                            Text("Unlock all widgets")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text("Home and Lock screen widgets for live price, fees, block height, halving and more.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                            benefit("13 widgets", "Price, fees, mempool, hashrate, halving, Lightning…")
                            benefit("Home & Lock screen", "Small, medium and large, plus accessory sizes.")
                            benefit("One-time purchase", "Pay once, yours forever. No subscription.")
                        }
                        .card()
                    }
                    .padding()
                }
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: Theme.Spacing.sm) {
                        Button {
                            Task {
                                working = true
                                let ok = await store.purchase()
                                working = false
                                if ok { dismiss() }
                            }
                        } label: {
                            Group {
                                if working {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(priceTitle)
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Theme.Accent.brand)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                        }
                        .disabled(working || store.product == nil)

                        Button("Restore Purchases") {
                            Task {
                                await store.restore()
                                if store.hasPremium { dismiss() }
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if let error = store.purchaseError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(Theme.Accent.down)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: store.hasPremium) { _, unlocked in
                if unlocked { dismiss() }
            }
        }
    }

    private func benefit(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

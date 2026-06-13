//
//  SettingsView.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI
import StoreKit

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @EnvironmentObject var store: StoreManager
    @Environment(\.openURL) private var openURL
    @State private var showPaywall = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    // MARK: - Premium promo

    private var premiumPromoBanner: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Text("PREMIUM")
                        .font(.caption).fontWeight(.semibold).tracking(0.8)
                        .foregroundStyle(Theme.Accent.brand)
                    Spacer()
                    if let price = store.product?.displayPrice {
                        Text("\(price) · one-time").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Unlock all widgets")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("13 Home and Lock screen widgets for live price, fees, block height, halving and more.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text("Unlock Premium").fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .font(.subheadline)
                .foregroundStyle(Theme.Accent.brand)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xl)
            .background(Theme.Accent.brand.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.Accent.brand.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(CardButtonStyle())
        .padding(.horizontal, 20)
    }

    private var premiumUnlockedCard: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Theme.Accent.brand)
            VStack(alignment: .leading, spacing: 2) {
                Text("Premium unlocked").font(.subheadline).fontWeight(.semibold)
                Text("Thanks for your support.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Restore") { Task { await store.restore() } }
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .padding(.horizontal, 20)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(spacing: 28) {

                        // MARK: - Premium
                        if store.hasPremium {
                            premiumUnlockedCard
                        } else {
                            premiumPromoBanner
                        }

                        // MARK: - Preferences
                        SettingsSection(title: "Preferences") {
                            SettingsRow(title: "Currency") {
                                Picker("", selection: $settings.preferredCurrency) {
                                    Text("USD ($)").tag("USD")
                                    Text("EUR (€)").tag("EUR")
                                    Text("GBP (£)").tag("GBP")
                                    Text("JPY (¥)").tag("JPY")
                                    Text("CHF (Fr)").tag("CHF")
                                    Text("AUD ($)").tag("AUD")
                                    Text("CAD ($)").tag("CAD")
                                    Text("CNY (¥)").tag("CNY")
                                    Text("HKD ($)").tag("HKD")
                                    Text("SEK (kr)").tag("SEK")
                                }
                                .tint(.secondary)
                            }

                            Divider().padding(.leading, 16)

                            SettingsRow(title: "Wallet Tab") {
                                Toggle("", isOn: $settings.showWalletTab)
                                    .labelsHidden()
                                    .tint(Color.bitcoinOrange)
                            }

                            if settings.showWalletTab {
                                Divider().padding(.leading, 16)

                                SettingsRow(title: "Gap Limit") {
                                    Picker("", selection: $settings.gapLimit) {
                                        Text("20 – Standard").tag(20)
                                        Text("50 – Extended").tag(50)
                                        Text("100 – Full Scan").tag(100)
                                    }
                                    .tint(.secondary)
                                }
                            }

                            Divider().padding(.leading, 16)

                            SettingsRow(title: "Haptics") {
                                Toggle("", isOn: $settings.hapticsEnabled)
                                    .labelsHidden()
                                    .tint(Color.bitcoinOrange)
                            }
                        }

                        // MARK: - Support
                        SettingsSection(title: "Support") {
                            Button {
                                if let url = URL(string: "mailto:miotares@proton.me?subject=Bitcoin%20Insight%20Feedback") {
                                    openURL(url)
                                }
                            } label: {
                                SettingsRow(
                                    title: "Send Feedback",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        // MARK: - About
                        SettingsSection(title: "About") {
                            SettingsRow(title: "Version", value: appVersion)

                            Divider().padding(.leading, 16)

                            SettingsRow(title: "Open Source", value: "100%")

                            Divider().padding(.leading, 16)

                            SettingsRow(title: "Made for Bitcoiners", value: "⚡️")
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollContentBackground(.hidden)
                .navigationTitle("Settings")
                .sheet(isPresented: $showPaywall) {
                    PaywallView()
                }
            }
        }
    }
}

// MARK: - Section Container

struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.leading, 20)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, 6)
            .cardSurface()
            .padding(.horizontal, 20)
        }
    }
}

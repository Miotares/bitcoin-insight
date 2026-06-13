//
//  SettingsView.swift
//  BitcoinWidgets
//
//  Created by Merlin Kreuzkam on 04.10.25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(spacing: 28) {

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

                        #if DEBUG
                        // MARK: - Developer (dev builds only)
                        SettingsSection(title: "Developer") {
                            SettingsRow(title: "Widgets Premium (Dev)") {
                                Toggle("", isOn: $settings.widgetsPremiumDev)
                                    .labelsHidden()
                                    .tint(Color.bitcoinOrange)
                            }
                        }
                        #endif

                        // MARK: - Node
                        SettingsSection(title: "Node") {
                            NavigationLink {
                                ZStack {
                                    AnimatedBackgroundView()
                                    VStack(spacing: 12) {
                                        Image(systemName: "server.rack")
                                            .font(.system(size: 44))
                                            .foregroundStyle(.secondary)
                                        Text("Custom Node coming soon")
                                            .font(.headline)
                                        Text("Connect your own mempool instance\nfor full privacy.")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding()
                                }
                                .navigationTitle("Node Connection")
                            } label: {
                                SettingsRow(
                                    title: "Connect your Node",
                                    value: "Coming Soon",
                                    showChevron: true
                                )
                            }
                            .buttonStyle(.plain)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Material.ultraThin)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
            .padding(.horizontal)
        }
    }
}

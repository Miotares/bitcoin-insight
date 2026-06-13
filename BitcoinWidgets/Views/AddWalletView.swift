//
//  AddWalletView.swift
//  BitcoinWidgets
//

import SwiftUI

struct AddWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: WalletViewModel

    @State private var name: String = ""
    @State private var publicKey: String = ""
    @State private var isAdding = false
    @State private var showError = false
    @State private var errorText = ""

    private var detectedType: WalletType { viewModel.detectWalletType(publicKey) }
    private var privateKeyDetected: Bool { viewModel.isPrivateKey(publicKey) }
    private var isValid: Bool { !name.isEmpty && viewModel.isValidInput(publicKey) && !privateKeyDetected }

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackgroundView()

                ScrollView {
                    VStack(spacing: Theme.Spacing.xxl) {

                        // MARK: - Watch-only note (flat, editorial)
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            Text("WATCH-ONLY")
                                .font(.caption).fontWeight(.semibold).tracking(0.8)
                                .foregroundStyle(Theme.Accent.brand)

                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                Text("Enter your **xpub, ypub, zpub** or a **Bitcoin address** — never your private key.")
                                Text("Read-only: you can track balance and transactions, but cannot send Bitcoin.")
                                Text("Balances are fetched via **mempool.space** — your addresses are visible to it.")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                        .padding(.horizontal)

                        // MARK: - Input
                        VStack(spacing: 0) {

                            // Name
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                SectionLabel("Wallet Name")
                                TextField("e.g. My Bitcoin Wallet", text: $name)
                                    .font(.body)
                                    .submitLabel(.next)
                            }
                            .padding(.horizontal, Theme.Spacing.xl)
                            .padding(.vertical, Theme.Spacing.lg)

                            Divider().padding(.leading, Theme.Spacing.xl)

                            // Public key
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                HStack {
                                    SectionLabel("Public Key")
                                    Spacer()
                                    Button {
                                        if let str = UIPasteboard.general.string {
                                            publicKey = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                        }
                                    } label: {
                                        Text("Paste")
                                            .font(.caption).fontWeight(.semibold)
                                            .foregroundStyle(Theme.Accent.brand)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Theme.Accent.brand.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }

                                TextEditor(text: $publicKey)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .frame(minHeight: 72, maxHeight: 100)
                                    .scrollContentBackground(.hidden)

                                if !publicKey.isEmpty {
                                    if privateKeyDetected {
                                        Text("Private key detected — never enter your private key here.")
                                            .font(.caption).foregroundStyle(Theme.Accent.down)
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else {
                                        Text(viewModel.isValidInput(publicKey) ? detectedType.displayName : "Invalid format")
                                            .font(.caption)
                                            .foregroundStyle(viewModel.isValidInput(publicKey) ? Theme.Accent.up : Theme.Accent.down)
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.xl)
                            .padding(.vertical, Theme.Spacing.lg)
                        }
                        .cardSurface()
                        .padding(.horizontal)

                        // MARK: - Error
                        if showError {
                            Text(errorText)
                                .font(.caption).foregroundStyle(Theme.Accent.down)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Spacing.lg)
                                .background(Theme.Accent.down.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                                .padding(.horizontal)
                        }

                        // MARK: - Add
                        Button {
                            Task { await addWallet() }
                        } label: {
                            Group {
                                if isAdding {
                                    HStack(spacing: 8) { ProgressView().tint(.white); Text("Validating…") }
                                } else {
                                    Text("Add Wallet")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isValid && !isAdding ? Theme.Accent.brand : Color.gray.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                        }
                        .disabled(!isValid || isAdding)
                        .padding(.horizontal)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                    .padding(.top, Theme.Spacing.sm)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Add Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func addWallet() async {
        isAdding = true
        showError = false
        Haptics.trigger(.medium)

        do {
            try await viewModel.addWallet(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                publicKey: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            Haptics.notification(.success)
            isAdding = false
            dismiss()
        } catch {
            errorText = error.localizedDescription
            showError = true
            isAdding = false
        }
    }
}

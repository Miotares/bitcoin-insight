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
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {

                        // Watch-only note — box-less, editorial
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Text("WATCH-ONLY")
                                .font(.caption).fontWeight(.semibold).tracking(0.8)
                                .foregroundStyle(Theme.Accent.brand)
                            Text("Enter your **xpub, ypub, zpub** or a **Bitcoin address** — never a private key. It stays read-only; balances come from **mempool.space**, so your addresses are visible to it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Wallet name
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            SectionLabel("Wallet Name")
                            TextField("e.g. My Bitcoin Wallet", text: $name)
                                .font(.body)
                                .submitLabel(.next)
                                .padding(Theme.Spacing.md)
                                .background(Theme.Surface.fill)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                        }

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
                                }
                            }

                            TextEditor(text: $publicKey)
                                .font(.system(.subheadline, design: .monospaced))
                                .frame(minHeight: 92)
                                .scrollContentBackground(.hidden)
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Surface.fill)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))

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

                        if showError {
                            Text(errorText)
                                .font(.caption).foregroundStyle(Theme.Accent.down)
                                .fixedSize(horizontal: false, vertical: true)
                        }

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
                        .padding(.top, Theme.Spacing.sm)
                    }
                    .padding()
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

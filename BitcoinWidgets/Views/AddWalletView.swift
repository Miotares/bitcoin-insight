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
                    VStack(spacing: 24) {

                        // MARK: - Privacy Warning
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                                Text("Watch-Only Wallet")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.orange)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Label {
                                    Text("Enter your **xpub, ypub, zpub** or a **Bitcoin address** — never your private key.")
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "eye.slash.fill")
                                        .foregroundStyle(.secondary)
                                }

                                Label {
                                    Text("This wallet is **read-only**. You can track your balance and transactions, but cannot send Bitcoin.")
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "arrow.up.circle")
                                        .foregroundStyle(.secondary)
                                }

                                Label {
                                    Text("Balances are fetched via **mempool.space**. Your addresses will be visible to this service.")
                                        .fixedSize(horizontal: false, vertical: true)
                                } icon: {
                                    Image(systemName: "network")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.horizontal)

                        // MARK: - Input Card
                        VStack(spacing: 0) {

                            // Name row
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Wallet Name")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .tracking(0.3)
                                TextField("e.g. My Bitcoin Wallet", text: $name)
                                    .font(.body)
                                    .submitLabel(.next)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)

                            Divider().padding(.leading, 20)

                            // Public key row
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Public Key")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .textCase(.uppercase)
                                        .tracking(0.3)
                                    Spacer()
                                    Button {
                                        if let str = UIPasteboard.general.string {
                                            publicKey = str.trimmingCharacters(in: .whitespacesAndNewlines)
                                        }
                                    } label: {
                                        Label("Paste", systemImage: "doc.on.clipboard")
                                            .font(.caption)
                                            .foregroundStyle(Color.bitcoinOrange)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.bitcoinOrange.opacity(0.12))
                                            .clipShape(Capsule())
                                    }
                                }

                                TextEditor(text: $publicKey)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .frame(minHeight: 72, maxHeight: 100)
                                    .scrollContentBackground(.hidden)

                                if !publicKey.isEmpty {
                                    if privateKeyDetected {
                                        HStack(spacing: 5) {
                                            Image(systemName: "exclamationmark.shield.fill")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                            Text("Private key detected — never enter your private key here!")
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                        .padding(.bottom, 2)
                                    } else {
                                        HStack(spacing: 5) {
                                            Image(systemName: viewModel.isValidInput(publicKey)
                                                  ? "checkmark.circle.fill" : "xmark.circle.fill")
                                                .font(.caption)
                                                .foregroundStyle(viewModel.isValidInput(publicKey) ? .green : .red)
                                            Text(viewModel.isValidInput(publicKey)
                                                 ? detectedType.displayName : "Invalid format")
                                                .font(.caption)
                                                .foregroundStyle(viewModel.isValidInput(publicKey) ? .green : .red)
                                        }
                                        .padding(.bottom, 2)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                        }
                        .background(Material.ultraThin)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
                        .padding(.horizontal)

                        // MARK: - Error
                        if showError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(errorText)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(14)
                            .background(Color.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal)
                        }

                        // MARK: - Add Button
                        Button {
                            Task { await addWallet() }
                        } label: {
                            HStack(spacing: 10) {
                                if isAdding {
                                    ProgressView().tint(.white)
                                    Text("Validating…")
                                } else {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add Wallet")
                                }
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(16)
                            .background(
                                isValid && !isAdding
                                    ? Color.bitcoinOrange
                                    : Color.gray.opacity(0.4)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(!isValid || isAdding)
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                    .padding(.top, 8)
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

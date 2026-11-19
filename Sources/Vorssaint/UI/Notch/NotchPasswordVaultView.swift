// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchPasswordVaultView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var vault = PasswordVaultService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var copiedItemId: UUID?
    @State private var copiedUsernameId: UUID?
    @State private var searchText = ""

    private var strings: PasswordVaultFeatureStrings {
        FeatureStrings.passwordVault(l10n.language)
    }

    private var filteredItems: [PasswordVaultItem] {
        vault.document.items.filter { item in
            let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if q.isEmpty { return true }
            return item.title.lowercased().contains(q)
                || item.username.lowercased().contains(q)
                || item.website.lowercased().contains(q)
                || item.notes.lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if !vault.isUnlocked {
                lockedView
            } else {
                unlockedView
            }
        }
        .onAppear {
            if !vault.isUnlocked && !vault.isAuthenticating {
                vault.requestUnlock()
            }
        }
    }

    // MARK: - Locked View
    private var lockedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.indigo)

            VStack(spacing: 4) {
                Text(strings.lockedTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(strings.lockedDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            if let error = vault.authError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                vault.requestUnlock()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: PasswordVaultAuth.isBiometricsAvailable ? "touchid" : "key.fill")
                    Text(strings.unlockButton)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(vault.isAuthenticating)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }

    // MARK: - Unlocked View
    private var unlockedView: some View {
        VStack(spacing: 8) {
            // Top Toolbar in Island
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField(strings.searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Popout to floating window button
                Button {
                    service.collapse()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        vault.show(allowsIsland: false)
                    }
                } label: {
                    Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Open in Window")

                // Lock button
                Button {
                    vault.lock()
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(6)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(strings.lockButton)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Items List
            if filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "key.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(strings.noEntriesTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredItems) { item in
                            itemRow(item)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Item Row
    private func itemRow(_ item: PasswordVaultItem) -> some View {
        let isPasswordVisible = vault.isPasswordVisible(for: item.id)
        let isUsernameCopied = copiedUsernameId == item.id
        let isPasswordCopied = copiedItemId == item.id

        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.category)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Capsule())
                }

                if !item.username.isEmpty {
                    Text(item.username)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                if !item.password.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                        if isPasswordVisible {
                            Text(item.password)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(Color.yellow)
                                .lineLimit(1)
                        } else {
                            Text(String(repeating: "•", count: min(max(item.password.count, 6), 14)))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer()

            // Username Copy Button
            if !item.username.isEmpty {
                Button {
                    vault.copyToClipboard(text: item.username)
                    copiedUsernameId = item.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedUsernameId == item.id { copiedUsernameId = nil }
                    }
                } label: {
                    Image(systemName: isUsernameCopied ? "checkmark" : "person.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isUsernameCopied ? Color.green : Color.white.opacity(0.7))
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(strings.copyUsername)
            }

            // Password Controls
            if !item.password.isEmpty {
                Button {
                    vault.togglePasswordVisibility(for: item.id)
                } label: {
                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye")
                        .font(.system(size: 10))
                        .foregroundStyle(isPasswordVisible ? Color.yellow : Color.white.opacity(0.7))
                        .padding(5)
                        .background(isPasswordVisible ? Color.yellow.opacity(0.2) : Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Button {
                    vault.copyToClipboard(text: item.password)
                    copiedItemId = item.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        if copiedItemId == item.id { copiedItemId = nil }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isPasswordCopied ? "checkmark" : "key.horizontal")
                            .font(.system(size: 10))
                        if isPasswordCopied {
                            Text(strings.copied)
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .foregroundStyle(isPasswordCopied ? Color.green : Color.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(strings.copyPassword)
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

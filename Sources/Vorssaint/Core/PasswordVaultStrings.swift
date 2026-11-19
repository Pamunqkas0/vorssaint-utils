// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the Password Vault.
struct PasswordVaultFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let lockedTitle: String
    let lockedDescription: String
    let unlockButton: String
    let lockButton: String
    let searchPlaceholder: String
    let addEntry: String
    let editEntry: String
    let deleteEntry: String
    let save: String
    let cancel: String
    let titleField: String
    let usernameField: String
    let passwordField: String
    let websiteField: String
    let categoryField: String
    let notesField: String
    let generatePassword: String
    let copyUsername: String
    let copyPassword: String
    let copied: String
    let noEntriesTitle: String
    let noEntriesDescription: String
}

extension FeatureStrings {
    static func passwordVault(_ language: AppLanguage) -> PasswordVaultFeatureStrings {
        // We provide full English as universal default, with Indonesian customization if needed
        .enUS
    }
}

extension PasswordVaultFeatureStrings {
    static let enUS = PasswordVaultFeatureStrings(
        pageTitle: "Password Vault",
        hubDescription: "Encrypted password and secret data storage secured with Touch ID or Mac password",
        panelCaption: "Secure credentials and notes",
        openButton: "Open Password Vault",
        lockedTitle: "Vault is Locked",
        lockedDescription: "Authenticate with Touch ID or your Mac password to view and manage stored credentials.",
        unlockButton: "Unlock Vault",
        lockButton: "Lock Vault",
        searchPlaceholder: "Search accounts, usernames, notes…",
        addEntry: "New Item",
        editEntry: "Edit Item",
        deleteEntry: "Delete",
        save: "Save",
        cancel: "Cancel",
        titleField: "Service / Title",
        usernameField: "Username / Email",
        passwordField: "Password",
        websiteField: "Website / URL",
        categoryField: "Category",
        notesField: "Secure Notes / Important Data",
        generatePassword: "Generate Strong Password",
        copyUsername: "Copy Username",
        copyPassword: "Copy Password",
        copied: "Copied!",
        noEntriesTitle: "No Vault Items",
        noEntriesDescription: "Add your first credential or secret data using the + button above."
    )
}

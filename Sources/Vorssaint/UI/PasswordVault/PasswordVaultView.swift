// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct PasswordVaultView: View {
    @ObservedObject private var service = PasswordVaultService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var showingEditSheet = false
    @State private var editingItem: PasswordVaultItem?
    @State private var copiedItemId: UUID?
    @State private var copiedUsernameId: UUID?
    @State private var hoveredCardId: UUID?

    private var strings: PasswordVaultFeatureStrings {
        FeatureStrings.passwordVault(l10n.language)
    }

    private let categories = ["All", "Login", "Note", "Card", "Server"]

    var filteredItems: [PasswordVaultItem] {
        service.document.items.filter { item in
            let matchesCategory = (service.selectedCategory == "All") || (item.category == service.selectedCategory)
            let q = service.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if q.isEmpty { return matchesCategory }
            let matchesQuery = item.title.lowercased().contains(q)
                || item.username.lowercased().contains(q)
                || item.website.lowercased().contains(q)
                || item.notes.lowercased().contains(q)
            return matchesCategory && matchesQuery
        }
    }

    var body: some View {
        ZStack {
            if !service.isUnlocked {
                lockedView
            } else {
                unlockedView
            }
        }
        .frame(minWidth: 440, minHeight: 520)
        .background(VisualEffectBackground())
        .sheet(isPresented: $showingEditSheet) {
            PasswordVaultEditSheet(itemToEdit: editingItem) { savedItem in
                service.saveItem(savedItem)
                showingEditSheet = false
                editingItem = nil
            } onCancel: {
                showingEditSheet = false
                editingItem = nil
            }
        }
    }

    // MARK: - Locked View
    private var lockedView: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                    .overlay(
                        Circle()
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                    )

                Image(systemName: "lock.shield.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 6) {
                Text(strings.lockedTitle)
                    .font(.title2.weight(.bold))
                Text(strings.lockedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }

            if let error = service.authError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error)
                }
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            }

            Button {
                service.requestUnlock()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: PasswordVaultAuth.isBiometricsAvailable ? "touchid" : "key.fill")
                    Text(strings.unlockButton)
                }
                .font(.headline)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(service.isAuthenticating)

            Spacer()
        }
        .padding()
    }

    // MARK: - Unlocked View
    private var unlockedView: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.accentColor)
                    Text(strings.pageTitle)
                        .font(.headline.weight(.semibold))
                }

                Spacer()

                Button {
                    editingItem = nil
                    showingEditSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text(strings.addEntry)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    service.lock()
                } label: {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .medium))
                        .padding(5)
                }
                .help(strings.lockButton)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Search & Category Filters
            VStack(spacing: 10) {
                // Search Field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField(strings.searchPlaceholder, text: $service.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !service.searchText.isEmpty {
                        Button {
                            service.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Categories Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(categories, id: \.self) { category in
                            let isSelected = service.selectedCategory == category
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    service.selectedCategory = category
                                }
                            } label: {
                                Text(category)
                                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor).opacity(0.6))
                                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)

            Divider()

            // List Area
            if filteredItems.isEmpty {
                VStack(spacing: 14) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.04))
                            .frame(width: 72, height: 72)
                        Image(systemName: "key.slash")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                    Text(strings.noEntriesTitle)
                        .font(.headline)
                    Text(strings.noEntriesDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredItems) { item in
                            itemCard(item)
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    // MARK: - Item Card
    private func itemCard(_ item: PasswordVaultItem) -> some View {
        let isPasswordVisible = service.isPasswordVisible(for: item.id)
        let isUsernameCopied = copiedUsernameId == item.id
        let isPasswordCopied = copiedItemId == item.id
        let isHovered = hoveredCardId == item.id

        return VStack(alignment: .leading, spacing: 10) {
            // Card Top: Icon, Title, Category & Menu
            HStack(alignment: .center, spacing: 10) {
                // Service Icon Avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(categoryColor(item.category).opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: categoryIcon(item.category))
                        .font(.system(size: 15))
                        .foregroundStyle(categoryColor(item.category))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title.isEmpty ? "Untitled" : item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)

                    if !item.website.isEmpty {
                        Text(item.website)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text(item.category)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(categoryColor(item.category).opacity(0.12))
                    .foregroundStyle(categoryColor(item.category))
                    .clipShape(Capsule())

                Menu {
                    Button {
                        editingItem = item
                        showingEditSheet = true
                    } label: {
                        Label(strings.editEntry, systemImage: "pencil")
                    }

                    Button {
                        service.copyToClipboard(text: item.password)
                    } label: {
                        Label(strings.copyPassword, systemImage: "key.horizontal")
                    }

                    if !item.username.isEmpty {
                        Button {
                            service.copyToClipboard(text: item.username)
                        } label: {
                            Label(strings.copyUsername, systemImage: "person.fill")
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        service.deleteItem(id: item.id)
                    } label: {
                        Label(strings.deleteEntry, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12))
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }

            // Username Box (if present)
            if !item.username.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text(item.username)
                        .font(.system(size: 12, design: .default))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Button {
                        service.copyToClipboard(text: item.username)
                        copiedUsernameId = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedUsernameId == item.id { copiedUsernameId = nil }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isUsernameCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            if isUsernameCopied {
                                Text(strings.copied)
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .foregroundStyle(isUsernameCopied ? Color.green : Color.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(isUsernameCopied ? 0.08 : 0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(strings.copyUsername)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Password Box (if present)
            if !item.password.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Group {
                        if isPasswordVisible {
                            Text(item.password)
                                .font(.system(size: 12, design: .monospaced).weight(.medium))
                                .foregroundStyle(Color.accentColor)
                                .textSelection(.enabled)
                        } else {
                            Text(String(repeating: "•", count: min(max(item.password.count, 8), 16)))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                    .truncationMode(.middle)

                    Spacer(minLength: 8)

                    // Eye Toggle Button
                    Button {
                        service.togglePasswordVisibility(for: item.id)
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye")
                            .font(.system(size: 11))
                            .foregroundStyle(isPasswordVisible ? Color.accentColor : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(isPasswordVisible ? 0.08 : 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(isPasswordVisible ? "Hide password" : "Show password")

                    // Copy Password Button
                    Button {
                        service.copyToClipboard(text: item.password)
                        copiedItemId = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedItemId == item.id { copiedItemId = nil }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isPasswordCopied ? "checkmark" : "key.horizontal")
                                .font(.system(size: 10))
                            if isPasswordCopied {
                                Text(strings.copied)
                                    .font(.system(size: 10, weight: .medium))
                            }
                        }
                        .foregroundStyle(isPasswordCopied ? Color.green : Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(isPasswordCopied ? Color.green.opacity(0.12) : Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .help(strings.copyPassword)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Notes Box (if present)
            if !item.notes.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                        .padding(.top, 2)
                    Text(item.notes)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.3) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onHover { hovering in
            hoveredCardId = hovering ? item.id : nil
        }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category.lowercased() {
        case "server": return "server.rack"
        case "card": return "creditcard.fill"
        case "note": return "note.text"
        default: return "key.fill"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "server": return .cyan
        case "card": return .purple
        case "note": return .orange
        default: return .accentColor
        }
    }
}

// MARK: - Edit Sheet
private struct PasswordVaultEditSheet: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var title: String
    @State private var username: String
    @State private var password: String
    @State private var website: String
    @State private var category: String
    @State private var notes: String
    @State private var showPasswordGenerator = false
    @State private var generatedLength: Double = 16
    @State private var includeSymbols = true
    @State private var includeNumbers = true

    let existingId: UUID?
    let createdAt: Date
    let onSave: (PasswordVaultItem) -> Void
    let onCancel: () -> Void

    private var strings: PasswordVaultFeatureStrings {
        FeatureStrings.passwordVault(l10n.language)
    }

    private let categories = ["Login", "Note", "Card", "Server", "Other"]

    init(itemToEdit: PasswordVaultItem?, onSave: @escaping (PasswordVaultItem) -> Void, onCancel: @escaping () -> Void) {
        self.existingId = itemToEdit?.id
        self.createdAt = itemToEdit?.createdAt ?? Date()
        self.onSave = onSave
        self.onCancel = onCancel
        _title = State(initialValue: itemToEdit?.title ?? "")
        _username = State(initialValue: itemToEdit?.username ?? "")
        _password = State(initialValue: itemToEdit?.password ?? "")
        _website = State(initialValue: itemToEdit?.website ?? "")
        _category = State(initialValue: itemToEdit?.category ?? "Login")
        _notes = State(initialValue: itemToEdit?.notes ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingId == nil ? strings.addEntry : strings.editEntry)
                    .font(.headline.weight(.semibold))
                Spacer()
                Button(strings.cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button(strings.save) {
                    let item = PasswordVaultItem(
                        id: existingId ?? UUID(),
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        website: website.trimmingCharacters(in: .whitespacesAndNewlines),
                        category: category,
                        notes: notes,
                        createdAt: createdAt,
                        updatedAt: Date()
                    )
                    onSave(item)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    formField(title: strings.titleField) {
                        TextField(strings.titleField, text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    formField(title: strings.categoryField) {
                        Picker("", selection: $category) {
                            ForEach(categories, id: \.self) { cat in
                                Text(cat).tag(cat)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    formField(title: strings.usernameField) {
                        TextField(strings.usernameField, text: $username)
                            .textFieldStyle(.roundedBorder)
                    }

                    formField(title: strings.passwordField) {
                        VStack(spacing: 6) {
                            HStack {
                                TextField(strings.passwordField, text: $password)
                                    .textFieldStyle(.roundedBorder)

                                Button {
                                    password = generateRandomPassword(length: Int(generatedLength), symbols: includeSymbols, numbers: includeNumbers)
                                } label: {
                                    Image(systemName: "dice.fill")
                                }
                                .help(strings.generatePassword)
                            }

                            DisclosureGroup(strings.generatePassword, isExpanded: $showPasswordGenerator) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Length: \(Int(generatedLength))")
                                            .font(.caption)
                                        Slider(value: $generatedLength, in: 8...32, step: 1)
                                    }
                                    HStack {
                                        Toggle("Numbers (0-9)", isOn: $includeNumbers)
                                        Toggle("Symbols (!@#$)", isOn: $includeSymbols)
                                    }
                                    .font(.caption)

                                    Button("Generate & Apply") {
                                        password = generateRandomPassword(length: Int(generatedLength), symbols: includeSymbols, numbers: includeNumbers)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding(.top, 4)
                            }
                            .font(.caption)
                        }
                    }

                    formField(title: strings.websiteField) {
                        TextField("https://...", text: $website)
                            .textFieldStyle(.roundedBorder)
                    }

                    formField(title: strings.notesField) {
                        TextEditor(text: $notes)
                            .font(.callout)
                            .frame(height: 90)
                            .padding(4)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                            )
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 440, height: 490)
    }

    private func formField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func generateRandomPassword(length: Int, symbols: Bool, numbers: Bool) -> String {
        var characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        if numbers { characters += "0123456789" }
        if symbols { characters += "!@#$%^&*()-_=+[]{}<>?" }
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
}

// Visual Effect View for native macOS window background vibrancy
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .sidebar
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

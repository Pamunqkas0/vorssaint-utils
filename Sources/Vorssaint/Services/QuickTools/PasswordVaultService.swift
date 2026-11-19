// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

private final class KeyablePasswordVaultPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PasswordVaultService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PasswordVaultService()

    @Published var isUnlocked: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?
    @Published var document: PasswordVaultDocument = PasswordVaultDocument()
    @Published var searchText: String = ""
    @Published var selectedCategory: String = "All"
    @Published var visiblePasswordIds: Set<UUID> = []

    private var panel: NSPanel?
    private var lockTimer: Timer?
    private var sleepObserver: Any?

    override private init() {
        super.init()
        setupSleepObserver()
    }

    private func setupSleepObserver() {
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lock()
        }
    }

    deinit {
        if let observer = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func syncWithPreferences() {
        if !AppFeature.passwordVault.isAvailable {
            hide()
            lock()
        }
    }

    func show(allowsIsland: Bool = true) {
        guard AppFeature.passwordVault.isAvailable else { return }

        if allowsIsland, NotchService.shared.showPasswordVault() {
            if isVisible { hide() }
            return
        }

        let panel = ensurePanel()
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !isUnlocked && !isAuthenticating {
            requestUnlock()
        } else {
            resetLockTimer()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    func lock() {
        isUnlocked = false
        authError = nil
        visiblePasswordIds.removeAll()
        lockTimer?.invalidate()
        lockTimer = nil
    }

    func togglePasswordVisibility(for id: UUID) {
        if visiblePasswordIds.contains(id) {
            visiblePasswordIds.remove(id)
        } else {
            visiblePasswordIds.insert(id)
        }
        resetLockTimer()
    }

    func isPasswordVisible(for id: UUID) -> Bool {
        visiblePasswordIds.contains(id)
    }

    func requestUnlock() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil

        PasswordVaultAuth.authenticate(reason: "Unlock Vorssaint Password Vault") { [weak self] success, error in
            guard let self else { return }
            self.isAuthenticating = false
            if success {
                self.document = PasswordVaultStore.load()
                self.isUnlocked = true
                self.resetLockTimer()
            } else {
                self.authError = error
            }
        }
    }

    func resetLockTimer() {
        lockTimer?.invalidate()
        let minutes = UserDefaults.standard.integer(forKey: DefaultsKey.passwordVaultAutoLockMinutes)
        let interval = (minutes > 0 ? TimeInterval(minutes * 60) : 300)
        lockTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.lock()
        }
    }

    func saveItem(_ item: PasswordVaultItem) {
        if let index = document.items.firstIndex(where: { $0.id == item.id }) {
            document.items[index] = item
        } else {
            document.items.insert(item, at: 0)
        }
        PasswordVaultStore.save(document)
        resetLockTimer()
    }

    func deleteItem(id: UUID) {
        document.items.removeAll(where: { $0.id == id })
        PasswordVaultStore.save(document)
        resetLockTimer()
    }

    func copyToClipboard(text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        resetLockTimer()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = KeyablePasswordVaultPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Password Vault"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 380, height: 420)
        panel.minSize = NSSize(width: 380, height: 420)
        panel.delegate = self

        let host = NSHostingController(rootView: PasswordVaultView())
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 460, height: 560))

        center(panel)
        self.panel = panel
        return panel
    }

    private func center(_ panel: NSPanel) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let screenRect = screen.visibleFrame
        let x = screenRect.midX - (panel.frame.width / 2)
        let y = screenRect.midY - (panel.frame.height / 2)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    func windowWillClose(_ notification: Notification) {
        lockTimer?.invalidate()
        lockTimer = nil
    }
}

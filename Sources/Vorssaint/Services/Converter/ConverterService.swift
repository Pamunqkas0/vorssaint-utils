// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation
import SwiftUI

private final class KeyableConverterPanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ConverterService: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ConverterService()

    @Published var items: [ConverterQueueItem] = []
    @Published var selectedItemID: UUID?
    @Published var isConverting: Bool = false
    @Published var isNotchDropTargeted: Bool = false
    @Published var capabilities: ConverterCapabilities = ConverterCapabilities.detect()
    @Published var outputDestination: ConverterOutputDestination = ConverterOutputDestination.current()

    // Live image preview state for the selected item
    @Published var previewOriginalImage: NSImage?
    @Published var previewConvertedImage: NSImage?
    @Published var previewEstimatedSize: Int64?
    @Published var isGeneratingPreview: Bool = false

    private var panel: NSPanel?
    private var previewTask: Task<Void, Never>?

    override private init() {
        super.init()
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    var selectedItem: ConverterQueueItem? {
        guard let selectedItemID else { return items.first }
        return items.first { $0.id == selectedItemID } ?? items.first
    }

    var hasQueuedItems: Bool {
        items.contains { item in
            if case .queued = item.status { return true }
            if case .failed = item.status { return true }
            return false
        }
    }

    var completedItems: [ConverterQueueItem] {
        items.filter { $0.status.isFinished }
    }

    // MARK: - Window Management

    func syncWithPreferences() {
        outputDestination = ConverterOutputDestination.current()
        if !AppFeature.fileConverter.isAvailable {
            hide()
        }
    }

    func show() {
        guard AppFeature.fileConverter.isAvailable else { return }
        outputDestination = ConverterOutputDestination.current()
        let panel = ensurePanel()
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            center(panel)
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func open(with urls: [URL]) {
        show()
        addFiles(urls)
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

    // MARK: - Queue Management

    func addFiles(_ urls: [URL]) {
        let defaultQuality = UserDefaults.standard.object(forKey: DefaultsKey.converterDefaultQuality) as? Double ?? 0.85
        let defaultMetadata = UserDefaults.standard.object(forKey: DefaultsKey.converterPreserveMetadata) as? Bool ?? true

        var addedIDs: [UUID] = []
        for url in urls {
            guard url.isFileURL,
                  let sourceFormat = ConverterFormat.detect(from: url) else { continue }
            if items.contains(where: { $0.sourceURL.standardizedFileURL == url.standardizedFileURL }) {
                continue
            }

            let target = sourceFormat.compatibleTargets(capabilities: capabilities).first ?? sourceFormat.defaultTarget
            let initialSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            let item = ConverterQueueItem(
                sourceURL: url,
                sourceFormat: sourceFormat,
                targetFormat: target,
                sourceSize: initialSize,
                imageOptions: ConverterImageOptions(
                    quality: defaultQuality,
                    preserveMetadata: defaultMetadata,
                    resizeMode: .original
                )
            )
            items.append(item)
            addedIDs.append(item.id)
        }

        if selectedItemID == nil, let first = addedIDs.first ?? items.first?.id {
            selectedItemID = first
            refreshLivePreview()
        } else if let last = addedIDs.last {
            selectedItemID = last
            refreshLivePreview()
        }

        // Inspect metadata asynchronously off the main thread
        for id in addedIDs {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            let url = item.sourceURL
            let format = item.sourceFormat
            Task.detached(priority: .userInitiated) {
                let meta = ConverterEngine.inspectFile(at: url, format: format)
                await MainActor.run { [weak self] in
                    guard let self,
                          let idx = self.items.firstIndex(where: { $0.id == id }) else { return }
                    self.items[idx].sourceSize = meta.fileSize
                    self.items[idx].imageDimensions = meta.imageDimensions
                    self.items[idx].documentPageCount = meta.documentPageCount
                    self.items[idx].documentPreviewSnippet = meta.documentPreviewSnippet
                }
            }
        }
    }

    func openFilePicker(completion: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ConverterFormat.allCases.map(\.utType)
        panel.message = "Select images or documents to convert"
        panel.begin { [weak self] response in
            if response == .OK {
                self?.addFiles(panel.urls)
            }
            completion?()
        }
    }

    func pasteFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], !urls.isEmpty {
            addFiles(urls)
            return
        }

        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("VorssaintConverterPaste", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let fileURL = tempDir.appendingPathComponent("Clipboard-\(formatter.string(from: Date())).png")
            if (try? pngData.write(to: fileURL)) != nil {
                addFiles([fileURL])
            }
        }
    }

    func selectItem(_ id: UUID) {
        selectedItemID = id
        refreshLivePreview()
    }

    func setTargetFormat(_ format: ConverterFormat, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].targetFormat = format
        if items[idx].status.isFinished {
            items[idx].status = .queued
        }
        if selectedItemID == id {
            refreshLivePreview()
        }
    }

    func updateImageOptions(_ options: ConverterImageOptions, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].imageOptions = options
        if items[idx].status.isFinished {
            items[idx].status = .queued
        }
        if selectedItemID == id {
            refreshLivePreview()
        }
    }

    func updateDocumentOptions(_ options: ConverterDocumentOptions, for id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].documentOptions = options
        if items[idx].status.isFinished {
            items[idx].status = .queued
        }
    }

    func setAllCompatibleTargets(to format: ConverterFormat) {
        for idx in items.indices {
            if items[idx].sourceFormat.compatibleTargets(capabilities: capabilities).contains(format) {
                items[idx].targetFormat = format
                if items[idx].status.isFinished {
                    items[idx].status = .queued
                }
            }
        }
        refreshLivePreview()
    }

    func removeItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = items.first?.id
            refreshLivePreview()
        }
    }

    func clearCompleted() {
        items.removeAll { $0.status.isFinished }
        if let selectedItemID, !items.contains(where: { $0.id == selectedItemID }) {
            self.selectedItemID = items.first?.id
            refreshLivePreview()
        }
    }

    func clearAll() {
        items.removeAll()
        selectedItemID = nil
        previewOriginalImage = nil
        previewConvertedImage = nil
        previewEstimatedSize = nil
    }

    // MARK: - Batch & Single Conversion (TaskGroup)

    func convertAll() {
        let pending = items.filter { item in
            switch item.status {
            case .queued, .failed: return true
            default: return false
            }
        }
        guard !pending.isEmpty, !isConverting else { return }
        runBatchConversion(for: pending)
    }

    func convertSingle(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), !isConverting else { return }
        runBatchConversion(for: [item])
    }

    private func runBatchConversion(for targets: [ConverterQueueItem]) {
        isConverting = true
        NotchService.shared.refreshPresentation()
        let destination = outputDestination
        let caps = capabilities

        for target in targets {
            if let idx = items.firstIndex(where: { $0.id == target.id }) {
                items[idx].status = .converting(progress: 0.25)
            }
        }

        Task { @MainActor in
            await withTaskGroup(of: (UUID, ConverterStatus).self) { group in
                for item in targets {
                    group.addTask {
                        do {
                            let outURL = ConverterEngine.uniqueOutputURL(
                                for: item.sourceURL,
                                targetFormat: item.targetFormat,
                                destination: destination
                            )
                            let outSize: Int64
                            if item.sourceFormat.category == .image {
                                outSize = try ConverterEngine.convertImage(
                                    sourceURL: item.sourceURL,
                                    to: item.targetFormat,
                                    outputURL: outURL,
                                    options: item.imageOptions,
                                    capabilities: caps
                                )
                            } else {
                                outSize = try ConverterEngine.convertDocument(
                                    sourceURL: item.sourceURL,
                                    from: item.sourceFormat,
                                    to: item.targetFormat,
                                    outputURL: outURL,
                                    options: item.documentOptions,
                                    capabilities: caps
                                )
                            }
                            return (item.id, .completed(outputURL: outURL, outputSize: outSize))
                        } catch {
                            return (item.id, .failed(message: error.localizedDescription))
                        }
                    }
                }

                for await (id, status) in group {
                    if let idx = self.items.firstIndex(where: { $0.id == id }) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            self.items[idx].status = status
                        }
                        NotchService.shared.refreshPresentation()
                    }
                }
            }
            self.isConverting = false
            NotchService.shared.refreshPresentation()
        }
    }

    // MARK: - Notch Drag-and-Drop Helpers

    static func canAcceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL], urls.contains(where: { ConverterFormat.detect(from: $0) != nil }) {
            return true
        }
        return NSImage(pasteboard: pasteboard) != nil
    }

    @discardableResult
    func acceptDrop(pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] {
            let supported = urls.filter { ConverterFormat.detect(from: $0) != nil }
            if !supported.isEmpty {
                addFiles(supported)
                return true
            }
        }
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("VorssaintConverterDrop", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent("NotchDrop-\(UUID().uuidString.prefix(6)).png")
            if (try? pngData.write(to: fileURL)) != nil {
                addFiles([fileURL])
                return true
            }
        }
        return false
    }

    // MARK: - Live Before/After Preview

    func refreshLivePreview() {
        previewTask?.cancel()
        guard let item = selectedItem, item.sourceFormat.category == .image else {
            previewOriginalImage = nil
            previewConvertedImage = nil
            previewEstimatedSize = nil
            isGeneratingPreview = false
            return
        }

        let sourceURL = item.sourceURL
        let targetFormat = item.targetFormat
        let options = item.imageOptions
        let caps = capabilities

        isGeneratingPreview = true
        previewTask = Task { @MainActor in
            // Brief debounce while user drags sliders
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }

            let result: (NSImage?, NSImage?, Int64?) = await Task.detached(priority: .userInitiated) {
                let original = NSImage(contentsOf: sourceURL)
                do {
                    let encoded = try ConverterEngine.encodeImageData(
                        sourceURL: sourceURL,
                        to: targetFormat,
                        options: options,
                        capabilities: caps
                    )
                    let converted = NSImage(data: encoded)
                    return (original, converted, Int64(encoded.count))
                } catch {
                    return (original, nil, nil)
                }
            }.value

            guard !Task.isCancelled else { return }
            self.previewOriginalImage = result.0
            self.previewConvertedImage = result.1
            self.previewEstimatedSize = result.2
            self.isGeneratingPreview = false
        }
    }

    // MARK: - Quick Actions (Finder, Clipboard, Save)

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyOutputToClipboard(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              case .completed(let outputURL, _) = item.status else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        if item.targetFormat.category == .image, let img = NSImage(contentsOf: outputURL) {
            pb.writeObjects([img, outputURL as NSURL])
        } else {
            pb.writeObjects([outputURL as NSURL])
        }
    }

    func saveItemAs(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }),
              case .completed(let outputURL, _) = item.status else { return }

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = outputURL.lastPathComponent
        savePanel.allowedContentTypes = [item.targetFormat.utType]
        if savePanel.runModal() == .OK, let dest = savePanel.url {
            if FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.removeItem(at: dest)
            }
            try? FileManager.default.copyItem(at: outputURL, to: dest)
            revealInFinder(dest)
        }
    }

    func saveAllToFolder() {
        let finished = completedItems
        guard !finished.isEmpty else { return }

        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = "Save Here"
        if openPanel.runModal() == .OK, let folder = openPanel.url {
            for item in finished {
                if case .completed(let outputURL, _) = item.status {
                    let dest = folder.appendingPathComponent(outputURL.lastPathComponent)
                    if dest.standardizedFileURL != outputURL.standardizedFileURL {
                        if FileManager.default.fileExists(atPath: dest.path) {
                            try? FileManager.default.removeItem(at: dest)
                        }
                        try? FileManager.default.copyItem(at: outputURL, to: dest)
                    }
                }
            }
            NSWorkspace.shared.open(folder)
        }
    }

    func setOutputDestination(_ destination: ConverterOutputDestination) {
        outputDestination = destination
        let defaults = UserDefaults.standard
        switch destination {
        case .sameAsSource:
            defaults.set("sameAsSource", forKey: DefaultsKey.converterOutputMode)
        case .downloads:
            defaults.set("downloads", forKey: DefaultsKey.converterOutputMode)
        case .customFolder(let url):
            defaults.set("custom", forKey: DefaultsKey.converterOutputMode)
            defaults.set(url.path, forKey: DefaultsKey.converterCustomOutputFolder)
        }
    }

    // MARK: - Panel Hosting

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = KeyableConverterPanel(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Document & Image Converter"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: 720, height: 480)
        panel.minSize = NSSize(width: 720, height: 480)
        panel.delegate = self

        let host = NSHostingController(rootView: ConverterView())
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setContentSize(NSSize(width: 860, height: 580))

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
}

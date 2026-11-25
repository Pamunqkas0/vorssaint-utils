// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchConverterView: View {
    @ObservedObject var service: NotchService
    var size: CGSize = .zero

    @ObservedObject private var converter = ConverterService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isDropTargeted = false
    @State private var copiedItemID: UUID?
    @State private var showingQuickOptions = false

    private var strings: ConverterFeatureStrings {
        FeatureStrings.converter(l10n.language)
    }

    private var activeDropHighlight: Bool {
        isDropTargeted || converter.isNotchDropTargeted
    }

    var body: some View {
        VStack(spacing: 8) {
            if converter.items.isEmpty {
                compactEmptyDropZone
            } else {
                compactBatchBar
                compactQueueList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .notchBand(leading: {
            headerLeading
        }, trailing: {
            headerTrailing
        })
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: activeDropHighlight)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: converter.items.count)
    }

    // MARK: - Notch Band Header

    private var headerLeading: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(strings.pageTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            if !converter.items.isEmpty {
                let done = converter.completedItems.count
                Text("\(done)/\(converter.items.count)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(done == converter.items.count ? .green : .cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
    }

    private var headerTrailing: some View {
        HStack(spacing: 5) {
            // Add Files
            Button {
                service.keepFileInteractionOpen(true)
                converter.openFilePicker {
                    service.keepFileInteractionOpen(false)
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(strings.addFiles)

            // Paste from Clipboard (Cmd+V)
            Button {
                converter.pasteFromClipboard()
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("v", modifiers: .command)
            .help("Paste image or files (⌘V)")

            // Quality / Options Popover
            if !converter.items.isEmpty {
                Button {
                    showingQuickOptions.toggle()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(showingQuickOptions ? .cyan : .white.opacity(0.85))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingQuickOptions, arrowEdge: .bottom) {
                    quickOptionsPopover
                }
                .help("Compression & metadata options")
            }

            // Expand to Full Window (for Split Comparison)
            Button {
                service.collapse()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    converter.show()
                }
            } label: {
                Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Open Full Window (Before/After Comparison)")

            // Primary Convert All Pill
            if converter.hasQueuedItems || converter.isConverting {
                Button {
                    converter.convertAll()
                } label: {
                    HStack(spacing: 4) {
                        if converter.isConverting {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9.5, weight: .bold))
                        }
                        Text(converter.isConverting ? "Working" : "Convert")
                            .font(.system(size: 10.5, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Color.cyan, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(converter.isConverting)
            }
        }
    }

    // MARK: - Empty Drop Zone

    private var compactEmptyDropZone: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)

            Image(systemName: activeDropHighlight ? "arrow.down.doc.fill" : "square.and.arrow.down.on.square")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(activeDropHighlight ? Color.cyan : .white.opacity(0.7))
                .scaleEffect(activeDropHighlight ? 1.12 : 1.0)

            VStack(spacing: 3) {
                Text(activeDropHighlight ? strings.dropRelease : strings.dropTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                Text("WebP, PNG, JPEG, HEIC, PDF, DOCX, RTF, TXT")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 8) {
                Button {
                    service.keepFileInteractionOpen(true)
                    converter.openFilePicker {
                        service.keepFileInteractionOpen(false)
                    }
                } label: {
                    Label(strings.browseFiles, systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    converter.pasteFromClipboard()
                } label: {
                    Label("Paste (⌘V)", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    activeDropHighlight ? Color.cyan : Color.white.opacity(0.18),
                    style: StrokeStyle(lineWidth: activeDropHighlight ? 1.8 : 1, dash: [5, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(activeDropHighlight ? Color.cyan.opacity(0.12) : Color.white.opacity(0.03))
                )
        )
        .padding(.bottom, 4)
    }

    // MARK: - Batch Format Pill Bar

    private var compactBatchBar: some View {
        HStack(spacing: 6) {
            Text(activeDropHighlight ? "Drop to add" : "All to:")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(activeDropHighlight ? .cyan : .white.opacity(0.5))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    let quickTargets: [ConverterFormat] = [.png, .jpeg, .heic, .pdf, .txt, .docx]
                    ForEach(quickTargets) { fmt in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                converter.setAllCompatibleTargets(to: fmt)
                            }
                        } label: {
                            Text(fmt.displayName)
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(fmt.badgeColor.opacity(0.24), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !converter.completedItems.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        converter.clearCompleted()
                    }
                } label: {
                    Text(strings.clearCompleted)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(activeDropHighlight ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
        )
    }

    // MARK: - Compact Queue List

    private var compactQueueList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(converter.items) { item in
                    compactItemCard(item)
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.automatic)
        .notchScrollEdgeFade()
    }

    private func compactItemCard(_ item: ConverterQueueItem) -> some View {
        let targets = item.sourceFormat.compatibleTargets(capabilities: converter.capabilities)

        return HStack(spacing: 8) {
            // Source Icon
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(item.sourceFormat.badgeColor.opacity(0.2))
                    .frame(width: 28, height: 28)
                Image(systemName: item.sourceFormat.category == .image ? "photo" : "doc.text")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(item.sourceFormat.badgeColor)
            }

            // Name & Size/Status
            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)

                statusSubtitle(for: item)
            }

            Spacer(minLength: 4)

            // Format Flow Pill: [SRC] -> [TGT v]
            HStack(spacing: 3) {
                Text(item.sourceFormat.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(item.sourceFormat.badgeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.sourceFormat.badgeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))

                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))

                Menu {
                    ForEach(targets) { target in
                        Button {
                            converter.setTargetFormat(target, for: item.id)
                        } label: {
                            if target == item.targetFormat {
                                Label(target.displayName, systemImage: "checkmark")
                            } else {
                                Text(target.displayName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(item.targetFormat.displayName)
                            .font(.system(size: 9, weight: .bold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(item.targetFormat.badgeColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.targetFormat.badgeColor.opacity(0.22), in: RoundedRectangle(cornerRadius: 4))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Quick Actions (Completed vs Queued)
            if case .completed(let outURL, _) = item.status {
                HStack(spacing: 4) {
                    Button {
                        converter.copyOutputToClipboard(item.id)
                        copiedItemID = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                            if copiedItemID == item.id { copiedItemID = nil }
                        }
                    } label: {
                        Image(systemName: copiedItemID == item.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(copiedItemID == item.id ? .green : .white.opacity(0.8))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(strings.copyOutput)

                    Button {
                        converter.revealInFinder(outURL)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(strings.revealInFinder)
                }
                // Drag converted result directly out of the Notch!
                .onDrag {
                    service.fileDragChanged(true, internalDrag: true)
                    return NSItemProvider(object: outURL as NSURL)
                }
            } else if item.status.isConverting {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 22, height: 22)
            } else {
                Button {
                    converter.convertSingle(item.id)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.black)
                        .frame(width: 22, height: 22)
                        .background(Color.cyan, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(converter.isConverting)
                .help(strings.convertOne)
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    converter.removeItem(item.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
        .onTapGesture {
            converter.selectItem(item.id)
        }
        // Allow dragging completed file directly from the whole card too!
        .modifier(CompletedFileDragModifier(item: item, service: service))
    }

    @ViewBuilder
    private func statusSubtitle(for item: ConverterQueueItem) -> some View {
        switch item.status {
        case .queued:
            Text(ConverterFormatting.byteSize(item.sourceSize))
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.5))
        case .converting:
            ProgressView()
                .progressViewStyle(.linear)
                .tint(.cyan)
                .frame(maxWidth: 110)
        case .completed(_, let outSize):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.green)
                Text(ConverterFormatting.sizeDeltaSummary(source: item.sourceSize, output: outSize))
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.green)
            }
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 9.5))
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Quick Options Popover

    private var quickOptionsPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item = converter.selectedItem, item.sourceFormat.category == .image {
                if item.targetFormat.supportsQuality {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(strings.quality)
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text("\(Int((item.imageOptions.quality * 100).rounded()))%")
                                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { item.imageOptions.quality },
                                set: { val in
                                    var opts = item.imageOptions
                                    opts.quality = val
                                    converter.updateImageOptions(opts, for: item.id)
                                }
                            ),
                            in: 0.1...1.0,
                            step: 0.05
                        )
                    }
                }

                if item.targetFormat.supportsMetadata {
                    Toggle(strings.preserveMetadata, isOn: Binding(
                        get: { item.imageOptions.preserveMetadata },
                        set: { val in
                            var opts = item.imageOptions
                            opts.preserveMetadata = val
                            converter.updateImageOptions(opts, for: item.id)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11))
                }
            } else {
                Text("Select an image in the queue to adjust compression quality and EXIF metadata.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button {
                service.collapse()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    converter.show()
                }
            } label: {
                Label("Open Full Window (Before/After)", systemImage: "macwindow")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: 240)
    }

    // MARK: - Drop Helper

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let direct = item as? URL {
                        url = direct
                    } else {
                        url = nil
                    }
                    if let url {
                        Task { @MainActor in
                            ConverterService.shared.addFiles([url])
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                handled = true
                provider.loadObject(ofClass: NSImage.self) { object, _ in
                    guard let img = object as? NSImage,
                          let tiff = img.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { return }
                    let tempDir = FileManager.default.temporaryDirectory
                        .appendingPathComponent("VorssaintConverterDrop", isDirectory: true)
                    try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                    let fileURL = tempDir.appendingPathComponent("Dropped-\(UUID().uuidString.prefix(6)).png")
                    if (try? png.write(to: fileURL)) != nil {
                        Task { @MainActor in
                            ConverterService.shared.addFiles([fileURL])
                        }
                    }
                }
            }
        }
        return handled
    }
}

private struct CompletedFileDragModifier: ViewModifier {
    let item: ConverterQueueItem
    let service: NotchService

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .completed(let outURL, _) = item.status {
            content.onDrag {
                service.fileDragChanged(true, internalDrag: true)
                return NSItemProvider(object: outURL as NSURL)
            }
        } else {
            content
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ConverterView: View {
    @ObservedObject private var service = ConverterService.shared
    @ObservedObject private var l10n = L10n.shared

    @State private var isDropTargeted: Bool = false
    @State private var customWidthText: String = "1280"
    @State private var customHeightText: String = "720"
    @State private var copiedItemID: UUID?

    private var strings: ConverterFeatureStrings {
        FeatureStrings.converter(l10n.language)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerToolbar

            Divider()
                .opacity(0.4)

            if service.items.isEmpty {
                emptyDropZone
            } else {
                HSplitView {
                    queuePane
                        .frame(minWidth: 360, idealWidth: 440)
                    inspectorPane
                        .frame(minWidth: 300, idealWidth: 380)
                }
            }

            if !service.items.isEmpty {
                Divider()
                    .opacity(0.4)
                bottomActionBar
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isDropTargeted ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.14),
                    lineWidth: isDropTargeted ? 2.5 : 1
                )
        )
        .onDrop(of: [UTType.fileURL, UTType.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: isDropTargeted)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: service.items.count)
    }

    // MARK: - Header Toolbar

    private var headerToolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(strings.windowTitle)
                        .font(.system(size: 13.5, weight: .bold))
                    Text(strings.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                service.openFilePicker()
            } label: {
                Label(strings.addFiles, systemImage: "plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                service.pasteFromClipboard()
            } label: {
                Label(strings.paste, systemImage: "doc.on.clipboard")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("v", modifiers: .command)
            .help("Paste image or files from Clipboard (⌘V)")

            if !service.items.isEmpty {
                convertAllMenu
            }

            outputDestinationMenu

            Button {
                service.hide()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var convertAllMenu: some View {
        Menu {
            Section("Images") {
                ForEach(ConverterFormat.imageFormats) { fmt in
                    if fmt != .webp || service.capabilities.canEncodeWebP {
                        Button(fmt.displayName) {
                            service.setAllCompatibleTargets(to: fmt)
                        }
                    }
                }
            }
            Section("Documents") {
                ForEach(ConverterFormat.documentFormats) { fmt in
                    Button(fmt.displayName) {
                        service.setAllCompatibleTargets(to: fmt)
                    }
                }
            }
        } label: {
            Label(strings.convertAllTo, systemImage: "wand.and.stars")
                .font(.system(size: 11.5, weight: .medium))
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
    }

    private var outputDestinationMenu: some View {
        Menu {
            Button {
                service.setOutputDestination(.sameAsSource)
            } label: {
                if case .sameAsSource = service.outputDestination {
                    Label(strings.sameFolder, systemImage: "checkmark")
                } else {
                    Text(strings.sameFolder)
                }
            }

            Button {
                service.setOutputDestination(.downloads)
            } label: {
                if case .downloads = service.outputDestination {
                    Label(strings.downloadsFolder, systemImage: "checkmark")
                } else {
                    Text(strings.downloadsFolder)
                }
            }

            Divider()

            Button(strings.chooseFolder) {
                let open = NSOpenPanel()
                open.canChooseFiles = false
                open.canChooseDirectories = true
                open.canCreateDirectories = true
                if open.runModal() == .OK, let url = open.url {
                    service.setOutputDestination(.customFolder(url))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                Text(destinationLabel)
                    .lineLimit(1)
            }
            .font(.system(size: 11.5, weight: .medium))
        }
        .menuStyle(.borderedButton)
        .controlSize(.small)
        .help("Output folder")
    }

    private var destinationLabel: String {
        switch service.outputDestination {
        case .sameAsSource: return strings.sameFolder
        case .downloads: return strings.downloadsFolder
        case .customFolder(let url): return url.lastPathComponent
        }
    }

    // MARK: - Smart Drop Zone (Empty State)

    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.accentColor.opacity(isDropTargeted ? 0.35 : 0.16),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: 68
                        )
                    )
                    .frame(width: 136, height: 136)
                    .scaleEffect(isDropTargeted ? 1.12 : 1.0)

                Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "square.and.arrow.down.on.square")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .primary.opacity(0.75))
                    .scaleEffect(isDropTargeted ? 1.1 : 1.0)
            }

            VStack(spacing: 6) {
                Text(isDropTargeted ? strings.dropRelease : strings.dropTitle)
                    .font(.system(size: 17, weight: .semibold))
                Text(strings.dropSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 10) {
                formatPillGroup(title: "Images", formats: ["WebP", "PNG", "JPEG", "HEIC", "TIFF", "BMP", "GIF"], color: .blue)
                formatPillGroup(title: "Documents", formats: ["PDF", "DOCX", "RTF", "HTML", "TXT"], color: .orange)
            }
            .padding(.top, 4)

            HStack(spacing: 10) {
                Button {
                    service.openFilePicker()
                } label: {
                    Label(strings.browseFiles, systemImage: "folder.badge.plus")
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    service.pasteFromClipboard()
                } label: {
                    Label("\(strings.paste) (⌘V)", systemImage: "doc.on.clipboard")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.primary.opacity(0.16),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.2, dash: [7, 5])
                )
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.025))
                )
        )
        .padding(20)
    }

    private func formatPillGroup(title: String, formats: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                ForEach(formats, id: \.self) { fmt in
                    Text(fmt)
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(color)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Queue Pane (Left)

    private var queuePane: some View {
        VStack(spacing: 0) {
            // Compact drop strip at top of queue
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.dashed")
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                Text(isDropTargeted ? strings.dropRelease : strings.dropMoreHint)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isDropTargeted ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03))

            Divider().opacity(0.3)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(service.items) { item in
                        queueCard(item)
                    }
                }
                .padding(12)
            }
        }
    }

    private func queueCard(_ item: ConverterQueueItem) -> some View {
        let isSelected = service.selectedItem?.id == item.id
        let targets = item.sourceFormat.compatibleTargets(capabilities: service.capabilities)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // Format badge icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.sourceFormat.badgeColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: item.sourceFormat.category == .image ? "photo" : "doc.text")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(item.sourceFormat.badgeColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.fileName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    HStack(spacing: 6) {
                        Text(ConverterFormatting.byteSize(item.sourceSize))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)

                        if let dims = item.imageDimensions {
                            Text("• \(Int(dims.width))×\(Int(dims.height))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        } else if let pages = item.documentPageCount {
                            Text("• \(pages) \(pages == 1 ? "page" : "pages")")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 4)

                // Visual Conversion Flow Pill: [WEBP] -> [PNG v]
                HStack(spacing: 4) {
                    Text(item.sourceFormat.displayName)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.sourceFormat.badgeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(item.sourceFormat.badgeColor)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)

                    Menu {
                        ForEach(targets) { target in
                            Button {
                                service.setTargetFormat(target, for: item.id)
                            } label: {
                                if target == item.targetFormat {
                                    Label(target.displayName, systemImage: "checkmark")
                                } else {
                                    Text(target.displayName)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(item.targetFormat.displayName)
                                .font(.system(size: 10, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 7.5, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(item.targetFormat.badgeColor.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(item.targetFormat.badgeColor)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            // Status & Quick Actions Row
            HStack(spacing: 8) {
                statusBadge(for: item)

                Spacer()

                if case .completed(let outURL, _) = item.status {
                    Button {
                        service.revealInFinder(outURL)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help(strings.revealInFinder)

                    Button {
                        service.copyOutputToClipboard(item.id)
                        copiedItemID = item.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if copiedItemID == item.id { copiedItemID = nil }
                        }
                    } label: {
                        Image(systemName: copiedItemID == item.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(copiedItemID == item.id ? .green : .primary)
                    }
                    .buttonStyle(.borderless)
                    .help(strings.copyOutput)

                    Button {
                        service.saveItemAs(item.id)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help(strings.saveAs)
                } else if !item.status.isConverting {
                    Button {
                        service.convertSingle(item.id)
                    } label: {
                        Text(strings.convertOne)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(service.isConverting)
                }

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        service.removeItem(item.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Remove from queue")
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.8)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            service.selectItem(item.id)
        }
    }

    @ViewBuilder
    private func statusBadge(for item: ConverterQueueItem) -> some View {
        switch item.status {
        case .queued:
            Label(strings.statusQueued, systemImage: "clock")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        case .converting:
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.mini)
                Text(strings.statusConverting)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        case .completed(_, let outSize):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
                Text(ConverterFormatting.sizeDeltaSummary(source: item.sourceSize, output: outSize))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.green)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.red)
                .lineLimit(1)
                .help(message)
        }
    }

    // MARK: - Live Inspector Pane (Right)

    @ViewBuilder
    private var inspectorPane: some View {
        if let item = service.selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if item.sourceFormat.category == .image {
                        imageInspector(item)
                    } else {
                        documentInspector(item)
                    }
                }
                .padding(14)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Select a file to inspect options")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func imageInspector(_ item: ConverterQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(strings.inspectorPreview)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if let est = service.previewEstimatedSize {
                    Text(ConverterFormatting.sizeDeltaSummary(source: item.sourceSize, output: est))
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.14), in: Capsule())
                        .foregroundStyle(.green)
                }
            }

            ConverterSplitComparisonView(
                originalImage: service.previewOriginalImage,
                convertedImage: service.previewConvertedImage,
                sourceLabel: item.sourceFormat.displayName,
                targetLabel: item.targetFormat.displayName,
                isLoading: service.isGeneratingPreview
            )
            .frame(height: 210)

            // Quality Slider
            if item.targetFormat.supportsQuality {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(strings.quality)
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        Text("\(Int((item.imageOptions.quality * 100).rounded()))%")
                            .font(.system(size: 11.5, weight: .bold)).monospacedDigit()
                            .foregroundStyle(Color.accentColor)
                    }

                    Slider(
                        value: Binding(
                            get: { item.imageOptions.quality },
                            set: { newVal in
                                var opts = item.imageOptions
                                opts.quality = newVal
                                service.updateImageOptions(opts, for: item.id)
                            }
                        ),
                        in: 0.1...1.0,
                        step: 0.05
                    )
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            // Preserve EXIF Metadata
            if item.targetFormat.supportsMetadata {
                Toggle(isOn: Binding(
                    get: { item.imageOptions.preserveMetadata },
                    set: { newVal in
                        var opts = item.imageOptions
                        opts.preserveMetadata = newVal
                        service.updateImageOptions(opts, for: item.id)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strings.preserveMetadata)
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("Keep EXIF, camera, and color profile tags")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            // Resize Dimensions
            VStack(alignment: .leading, spacing: 8) {
                Text(strings.resize)
                    .font(.system(size: 11.5, weight: .semibold))

                let presets: [ConverterResizeMode] = [
                    .original,
                    .percentage(75),
                    .percentage(50),
                    .maxDimension(1920),
                    .maxDimension(1080)
                ]

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 6)], spacing: 6) {
                    ForEach(presets, id: \.self) { mode in
                        let selected = item.imageOptions.resizeMode == mode
                        Button {
                            var opts = item.imageOptions
                            opts.resizeMode = mode
                            service.updateImageOptions(opts, for: item.id)
                        } label: {
                            Text(mode.label)
                                .font(.system(size: 10.5, weight: selected ? .bold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .background(
                                    selected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                                .foregroundStyle(selected ? Color.accentColor : .primary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        let w = max(16, Int(customWidthText) ?? 1280)
                        let h = max(16, Int(customHeightText) ?? 720)
                        var opts = item.imageOptions
                        opts.resizeMode = .custom(width: w, height: h)
                        service.updateImageOptions(opts, for: item.id)
                    } label: {
                        let isCustom: Bool = {
                            if case .custom = item.imageOptions.resizeMode { return true }
                            return false
                        }()
                        Text("Custom")
                            .font(.system(size: 10.5, weight: isCustom ? .bold : .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                isCustom ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .foregroundStyle(isCustom ? Color.accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }

                if case .custom = item.imageOptions.resizeMode {
                    HStack(spacing: 6) {
                        TextField("W", text: $customWidthText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("×")
                            .foregroundStyle(.secondary)
                        TextField("H", text: $customHeightText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Button("Apply") {
                            let w = max(16, Int(customWidthText) ?? 1280)
                            let h = max(16, Int(customHeightText) ?? 720)
                            var opts = item.imageOptions
                            opts.resizeMode = .custom(width: w, height: h)
                            service.updateImageOptions(opts, for: item.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func documentInspector(_ item: ConverterQueueItem) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(strings.documentInfo)
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text(documentEngineLabel(for: item))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)
            }

            if item.sourceFormat == .pdf {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(strings.pdfPageRange)
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer()
                        if let pages = item.documentPageCount {
                            Text("Total: \(pages) pages")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    TextField("All pages (or e.g. 1-3, 5)", text: Binding(
                        get: { item.documentOptions.pageRangeText },
                        set: { newVal in
                            var opts = item.documentOptions
                            opts.pageRangeText = newVal
                            service.updateDocumentOptions(opts, for: item.id)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                }
                .padding(10)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Content Snippet")
                    .font(.system(size: 11.5, weight: .semibold))
                ScrollView {
                    Text(item.documentPreviewSnippet?.isEmpty == false
                         ? item.documentPreviewSnippet!
                         : "No plain-text preview available for this document.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(8)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
            }
            .padding(10)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func documentEngineLabel(for item: ConverterQueueItem) -> String {
        if (item.sourceFormat == .pdf && item.targetFormat == .docx)
            || (item.sourceFormat == .docx && item.targetFormat == .pdf) {
            return service.capabilities.pdfToDocxBridgeLabel
        }
        if item.sourceFormat == .pdf || item.targetFormat == .pdf {
            return "Native PDFKit"
        }
        return "macOS textutil"
    }

    // MARK: - Bottom Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 10) {
            let totalBytes = service.items.reduce(Int64(0)) { $0 + $1.sourceSize }
            Text("\(service.items.count) \(service.items.count == 1 ? "file" : "files") • \(ConverterFormatting.byteSize(totalBytes))")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            if !service.completedItems.isEmpty {
                Button(strings.clearCompleted) {
                    withAnimation { service.clearCompleted() }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 11.5))
            }

            Button(strings.clearAll) {
                withAnimation { service.clearAll() }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)

            Spacer()

            if !service.completedItems.isEmpty {
                Button {
                    service.saveAllToFolder()
                } label: {
                    Label(strings.saveAll, systemImage: "folder.badge.checkmark")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }

            Button {
                service.convertAll()
            } label: {
                HStack(spacing: 6) {
                    if service.isConverting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(service.isConverting ? strings.statusConverting : strings.convertAll)
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!service.hasQueuedItems || service.isConverting)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Drag & Drop Handler

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let resolvedURL: URL?
                    if let data = item as? Data {
                        resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let url = item as? URL {
                        resolvedURL = url
                    } else {
                        resolvedURL = nil
                    }
                    if let url = resolvedURL {
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

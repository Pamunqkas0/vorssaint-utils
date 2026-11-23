// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the Document & Image Converter.
struct ConverterFeatureStrings {
    let pageTitle: String
    let windowTitle: String
    let subtitle: String
    let hubDescription: String
    let panelCaption: String
    let openButton: String
    let addFiles: String
    let paste: String
    let convertAllTo: String
    let sameFolder: String
    let downloadsFolder: String
    let chooseFolder: String
    let dropTitle: String
    let dropRelease: String
    let dropSubtitle: String
    let dropMoreHint: String
    let browseFiles: String
    let statusQueued: String
    let statusConverting: String
    let revealInFinder: String
    let copyOutput: String
    let saveAs: String
    let convertOne: String
    let inspectorPreview: String
    let quality: String
    let preserveMetadata: String
    let resize: String
    let documentInfo: String
    let pdfPageRange: String
    let clearCompleted: String
    let clearAll: String
    let saveAll: String
    let convertAll: String
    let outputFolderSetting: String
    let defaultQualitySetting: String
}

extension FeatureStrings {
    static func converter(_ language: AppLanguage) -> ConverterFeatureStrings {
        .enUS
    }
}

extension ConverterFeatureStrings {
    static let enUS = ConverterFeatureStrings(
        pageTitle: "File Converter",
        windowTitle: "Document & Image Converter",
        subtitle: "Native offline conversion for images, PDFs, and documents",
        hubDescription: "Convert images (WebP, PNG, JPEG, HEIC, TIFF, BMP, GIF) and documents (PDF, DOCX, RTF, HTML, TXT) offline with live comparison.",
        panelCaption: "Convert images & documents",
        openButton: "Open Converter",
        addFiles: "Add Files",
        paste: "Paste",
        convertAllTo: "Convert All to…",
        sameFolder: "Same Folder",
        downloadsFolder: "Downloads",
        chooseFolder: "Choose Folder…",
        dropTitle: "Drop Images or Documents Here",
        dropRelease: "Release to Add to Queue",
        dropSubtitle: "Drag files from Finder or Shelf, browse from disk, or paste an image with ⌘V.",
        dropMoreHint: "Drop more files here or press ⌘V to paste",
        browseFiles: "Browse Files…",
        statusQueued: "Queued",
        statusConverting: "Converting…",
        revealInFinder: "Reveal in Finder",
        copyOutput: "Copy to Clipboard",
        saveAs: "Save As…",
        convertOne: "Convert",
        inspectorPreview: "Before / After Comparison",
        quality: "Compression Quality",
        preserveMetadata: "Preserve Metadata (EXIF)",
        resize: "Resize Dimensions",
        documentInfo: "Document Inspector",
        pdfPageRange: "PDF Page Range",
        clearCompleted: "Clear Done",
        clearAll: "Clear All",
        saveAll: "Save All…",
        convertAll: "Convert All",
        outputFolderSetting: "Converter output folder",
        defaultQualitySetting: "Default image quality"
    )
}

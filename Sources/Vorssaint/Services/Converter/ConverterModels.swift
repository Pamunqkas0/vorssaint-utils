// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum ConverterCategory: String, Codable, Equatable, Sendable {
    case image
    case document
}

enum ConverterFormat: String, Codable, CaseIterable, Identifiable, Equatable, Hashable, Sendable {
    // Images
    case png
    case jpeg
    case heic
    case tiff
    case bmp
    case gif
    case webp

    // Documents
    case pdf
    case txt
    case rtf
    case html
    case docx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        case .bmp: return "BMP"
        case .gif: return "GIF"
        case .webp: return "WebP"
        case .pdf: return "PDF"
        case .txt: return "TXT"
        case .rtf: return "RTF"
        case .html: return "HTML"
        case .docx: return "DOCX"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        default: return rawValue
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .bmp: return .bmp
        case .gif: return .gif
        case .webp: return .webP
        case .pdf: return .pdf
        case .txt: return .plainText
        case .rtf: return .rtf
        case .html: return .html
        case .docx:
            return UTType(filenameExtension: "docx")
                ?? UTType("org.openxmlformats.wordprocessingml.document")
                ?? .data
        }
    }

    var category: ConverterCategory {
        switch self {
        case .png, .jpeg, .heic, .tiff, .bmp, .gif, .webp:
            return .image
        case .pdf, .txt, .rtf, .html, .docx:
            return .document
        }
    }

    var supportsQuality: Bool {
        switch self {
        case .jpeg, .heic, .webp:
            return true
        default:
            return false
        }
    }

    var supportsMetadata: Bool {
        switch self {
        case .png, .jpeg, .heic, .tiff:
            return true
        default:
            return false
        }
    }

    var badgeColor: Color {
        switch self {
        case .png: return .blue
        case .jpeg: return .orange
        case .heic: return .purple
        case .tiff: return .indigo
        case .bmp: return .teal
        case .gif: return .pink
        case .webp: return .green
        case .pdf: return .red
        case .txt: return .gray
        case .rtf: return .cyan
        case .html: return .mint
        case .docx: return .blue
        }
    }

    static var imageFormats: [ConverterFormat] {
        [.png, .jpeg, .heic, .tiff, .bmp, .gif, .webp]
    }

    static var documentFormats: [ConverterFormat] {
        [.pdf, .txt, .rtf, .html, .docx]
    }

    func compatibleTargets(capabilities: ConverterCapabilities = .detect()) -> [ConverterFormat] {
        switch category {
        case .image:
            return Self.imageFormats.filter { target in
                guard target != self else { return false }
                if target == .webp {
                    return capabilities.canEncodeWebP
                }
                return true
            }
        case .document:
            return Self.documentFormats.filter { $0 != self }
        }
    }

    var defaultTarget: ConverterFormat {
        switch self {
        case .webp, .heic, .tiff, .bmp, .gif:
            return .png
        case .png:
            return .jpeg
        case .jpeg:
            return .png
        case .pdf:
            return .txt
        case .txt, .rtf, .html, .docx:
            return .pdf
        }
    }

    static func detect(from url: URL) -> ConverterFormat? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png": return .png
        case "jpg", "jpeg": return .jpeg
        case "heic", "heif": return .heic
        case "tif", "tiff": return .tiff
        case "bmp": return .bmp
        case "gif": return .gif
        case "webp": return .webp
        case "pdf": return .pdf
        case "txt", "md", "log", "csv": return .txt
        case "rtf": return .rtf
        case "html", "htm": return .html
        case "docx": return .docx
        default:
            if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
               let type = values.contentType {
                if type.conforms(to: .png) { return .png }
                if type.conforms(to: .jpeg) { return .jpeg }
                if type.conforms(to: .heic) { return .heic }
                if type.conforms(to: .tiff) { return .tiff }
                if type.conforms(to: .bmp) { return .bmp }
                if type.conforms(to: .gif) { return .gif }
                if type.conforms(to: .webP) { return .webp }
                if type.conforms(to: .pdf) { return .pdf }
                if type.conforms(to: .rtf) { return .rtf }
                if type.conforms(to: .html) { return .html }
                if type.conforms(to: .plainText) { return .txt }
            }
            return nil
        }
    }
}

enum ConverterResizeMode: Codable, Equatable, Hashable, Sendable {
    case original
    case percentage(Int)
    case maxDimension(Int)
    case custom(width: Int, height: Int)

    var label: String {
        switch self {
        case .original: return "Original"
        case .percentage(let pct): return "\(pct)%"
        case .maxDimension(let px): return "Max \(px)px"
        case .custom(let w, let h): return "\(w)×\(h)"
        }
    }
}

struct ConverterImageOptions: Codable, Equatable, Sendable {
    var quality: Double = 0.85
    var preserveMetadata: Bool = true
    var resizeMode: ConverterResizeMode = .original
}

struct ConverterDocumentOptions: Codable, Equatable, Sendable {
    var pageRangeText: String = ""

    /// Parses 1-based page ranges like "1-3, 5" into sorted 0-based page indices.
    /// Returns `nil` if the range string is empty (meaning all pages).
    static func parsePageIndices(_ text: String, totalPages: Int) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, totalPages > 0 else { return nil }

        var indices = Set<Int>()
        let parts = trimmed.split(separator: ",")
        for rawPart in parts {
            let part = rawPart.trimmingCharacters(in: .whitespaces)
            if part.isEmpty { continue }
            if part.contains("-") {
                let bounds = part.split(separator: "-", maxSplits: 1).map {
                    Int($0.trimmingCharacters(in: .whitespaces))
                }
                guard bounds.count == 2, let start = bounds[0], let end = bounds[1] else {
                    continue
                }
                let low = max(1, min(start, end))
                let high = min(totalPages, max(start, end))
                if low <= high {
                    for p in low...high { indices.insert(p - 1) }
                }
            } else if let page = Int(part), page >= 1, page <= totalPages {
                indices.insert(page - 1)
            }
        }
        return indices.isEmpty ? nil : indices.sorted()
    }
}

enum ConverterStatus: Equatable, Sendable {
    case queued
    case converting(progress: Double)
    case completed(outputURL: URL, outputSize: Int64)
    case failed(message: String)

    var isFinished: Bool {
        if case .completed = self { return true }
        return false
    }

    var isConverting: Bool {
        if case .converting = self { return true }
        return false
    }
}

struct ConverterQueueItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceURL: URL
    let sourceFormat: ConverterFormat
    var targetFormat: ConverterFormat
    var sourceSize: Int64
    var imageDimensions: CGSize?
    var documentPageCount: Int?
    var documentPreviewSnippet: String?
    var status: ConverterStatus = .queued
    var imageOptions: ConverterImageOptions
    var documentOptions: ConverterDocumentOptions

    init(
        id: UUID = UUID(),
        sourceURL: URL,
        sourceFormat: ConverterFormat,
        targetFormat: ConverterFormat,
        sourceSize: Int64,
        imageDimensions: CGSize? = nil,
        documentPageCount: Int? = nil,
        documentPreviewSnippet: String? = nil,
        status: ConverterStatus = .queued,
        imageOptions: ConverterImageOptions = ConverterImageOptions(),
        documentOptions: ConverterDocumentOptions = ConverterDocumentOptions()
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.sourceFormat = sourceFormat
        self.targetFormat = targetFormat
        self.sourceSize = sourceSize
        self.imageDimensions = imageDimensions
        self.documentPageCount = documentPageCount
        self.documentPreviewSnippet = documentPreviewSnippet
        self.status = status
        self.imageOptions = imageOptions
        self.documentOptions = documentOptions
    }

    var fileName: String {
        sourceURL.lastPathComponent
    }
}

enum ConverterOutputDestination: Equatable, Sendable {
    case sameAsSource
    case downloads
    case customFolder(URL)

    static func current(in defaults: UserDefaults = .standard) -> ConverterOutputDestination {
        let mode = defaults.string(forKey: DefaultsKey.converterOutputMode) ?? "sameAsSource"
        switch mode {
        case "downloads":
            return .downloads
        case "custom":
            if let path = defaults.string(forKey: DefaultsKey.converterCustomOutputFolder), !path.isEmpty {
                return .customFolder(URL(fileURLWithPath: path, isDirectory: true))
            }
            return .downloads
        default:
            return .sameAsSource
        }
    }
}

struct ConverterCapabilities: Equatable, Sendable {
    let imageIOWebPEncode: Bool
    let cwebpPath: String?
    let sofficePath: String?
    let pandocPath: String?

    var canEncodeWebP: Bool {
        imageIOWebPEncode || cwebpPath != nil
    }

    var pdfToDocxBridgeLabel: String {
        if sofficePath != nil { return "LibreOffice" }
        if pandocPath != nil { return "PDFKit + Pandoc" }
        return "Native PDFKit + textutil"
    }

    static func detect() -> ConverterCapabilities {
        let destTypes = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        let imageIOWebP = destTypes.contains(UTType.webP.identifier)
        return ConverterCapabilities(
            imageIOWebPEncode: imageIOWebP,
            cwebpPath: findExecutable(named: "cwebp", candidates: [
                "/opt/homebrew/bin/cwebp",
                "/usr/local/bin/cwebp"
            ]),
            sofficePath: findExecutable(named: "soffice", candidates: [
                "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                "/opt/homebrew/bin/soffice",
                "/usr/local/bin/soffice"
            ]),
            pandocPath: findExecutable(named: "pandoc", candidates: [
                "/opt/homebrew/bin/pandoc",
                "/usr/local/bin/pandoc"
            ])
        )
    }

    private static func findExecutable(named name: String, candidates: [String]) -> String? {
        let fm = FileManager.default
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}

enum ConverterFormatting {
    static func byteSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func sizeDeltaSummary(source: Int64, output: Int64) -> String {
        guard source > 0 else { return byteSize(output) }
        let diff = Double(output - source) / Double(source) * 100.0
        let pct = Int(diff.rounded())
        let sign = pct > 0 ? "+" : ""
        return "\(byteSize(source)) → \(byteSize(output)) (\(sign)\(pct)%)"
    }
}

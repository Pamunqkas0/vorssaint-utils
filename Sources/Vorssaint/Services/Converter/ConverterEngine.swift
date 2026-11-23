// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ConverterError: LocalizedError {
    case unreadableSource
    case unsupportedConversion(String)
    case encodingFailed(String)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .unreadableSource:
            return "Could not read the source file."
        case .unsupportedConversion(let detail):
            return detail
        case .encodingFailed(let detail):
            return detail
        case .processFailed(let detail):
            return detail
        }
    }
}

struct ConverterFileMetadata: Equatable, Sendable {
    var fileSize: Int64 = 0
    var imageDimensions: CGSize?
    var documentPageCount: Int?
    var documentPreviewSnippet: String?
}

enum ConverterEngine {
    // MARK: - File Inspection

    static func inspectFile(at url: URL, format: ConverterFormat) -> ConverterFileMetadata {
        var meta = ConverterFileMetadata()
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
           let size = values.fileSize {
            meta.fileSize = Int64(size)
        }

        if format.category == .image {
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
               let height = props[kCGImagePropertyPixelHeight] as? CGFloat {
                meta.imageDimensions = CGSize(width: width, height: height)
            }
        } else {
            switch format {
            case .pdf:
                if let doc = PDFDocument(url: url) {
                    meta.documentPageCount = doc.pageCount
                    if let firstPage = doc.page(at: 0)?.string {
                        meta.documentPreviewSnippet = String(firstPage.prefix(600))
                    }
                }
            case .txt, .html, .rtf:
                if let attr = try? loadAttributedString(from: url, format: format) {
                    meta.documentPreviewSnippet = String(attr.string.prefix(600))
                } else if let text = try? String(contentsOf: url, encoding: .utf8) {
                    meta.documentPreviewSnippet = String(text.prefix(600))
                }
            case .docx:
                if let text = try? extractPlainTextWithTextUtil(from: url) {
                    meta.documentPreviewSnippet = String(text.prefix(600))
                }
            default:
                break
            }
        }
        return meta
    }

    // MARK: - Output URL Resolution

    static func uniqueOutputURL(
        for sourceURL: URL,
        targetFormat: ConverterFormat,
        destination: ConverterOutputDestination
    ) -> URL {
        let directory: URL
        switch destination {
        case .sameAsSource:
            directory = sourceURL.deletingLastPathComponent()
        case .downloads:
            directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? sourceURL.deletingLastPathComponent()
        case .customFolder(let customURL):
            directory = customURL
        }

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = targetFormat.fileExtension
        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        let fm = FileManager.default
        if candidate.standardizedFileURL == sourceURL.standardizedFileURL || fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName)-converted.\(ext)")
            var counter = 2
            while fm.fileExists(atPath: candidate.path) {
                candidate = directory.appendingPathComponent("\(baseName)-converted \(counter).\(ext)")
                counter += 1
            }
        }
        return candidate
    }

    // MARK: - Image Conversion

    static func encodeImageData(
        sourceURL: URL,
        to targetFormat: ConverterFormat,
        options: ConverterImageOptions,
        capabilities: ConverterCapabilities = .detect()
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ConverterError.unreadableSource
        }

        let processedImage = try resizeImageIfNeeded(
            cgImage,
            mode: options.resizeMode,
            flattenAlpha: targetFormat == .jpeg || targetFormat == .bmp
        )

        if targetFormat == .webp && !capabilities.imageIOWebPEncode {
            return try encodeWebPViaCLI(cgImage: processedImage, quality: options.quality, capabilities: capabilities)
        }

        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            targetFormat.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw ConverterError.encodingFailed("macOS ImageIO cannot encode \(targetFormat.displayName).")
        }

        var properties: [CFString: Any] = [:]
        if options.preserveMetadata,
           let sourceProps = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            properties = sourceProps
            // Update pixel dimensions if resized
            properties[kCGImagePropertyPixelWidth] = processedImage.width
            properties[kCGImagePropertyPixelHeight] = processedImage.height
        }
        if targetFormat.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = min(1.0, max(0.1, options.quality))
        }

        CGImageDestinationAddImage(destination, processedImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ConverterError.encodingFailed("Failed to finalize \(targetFormat.displayName) image.")
        }
        return mutableData as Data
    }

    @discardableResult
    static func convertImage(
        sourceURL: URL,
        to targetFormat: ConverterFormat,
        outputURL: URL,
        options: ConverterImageOptions,
        capabilities: ConverterCapabilities = .detect()
    ) throws -> Int64 {
        let data = try encodeImageData(
            sourceURL: sourceURL,
            to: targetFormat,
            options: options,
            capabilities: capabilities
        )
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
        return Int64(data.count)
    }

    private static func resizeImageIfNeeded(
        _ image: CGImage,
        mode: ConverterResizeMode,
        flattenAlpha: Bool
    ) throws -> CGImage {
        let origW = image.width
        let origH = image.height
        guard origW > 0, origH > 0 else { return image }

        let targetSize: (Int, Int)
        switch mode {
        case .original:
            if !flattenAlpha { return image }
            targetSize = (origW, origH)
        case .percentage(let pct):
            let scale = max(0.05, min(2.0, Double(pct) / 100.0))
            targetSize = (max(1, Int((Double(origW) * scale).rounded())),
                          max(1, Int((Double(origH) * scale).rounded())))
        case .maxDimension(let maxDim):
            let clamped = max(16, maxDim)
            let longest = max(origW, origH)
            if longest <= clamped {
                if !flattenAlpha { return image }
                targetSize = (origW, origH)
            } else {
                let scale = Double(clamped) / Double(longest)
                targetSize = (max(1, Int((Double(origW) * scale).rounded())),
                              max(1, Int((Double(origH) * scale).rounded())))
            }
        case .custom(let width, let height):
            targetSize = (max(1, width), max(1, height))
        }

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = flattenAlpha
            ? CGImageAlphaInfo.noneSkipLast.rawValue
            : CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: targetSize.0,
            height: targetSize.1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace.model == .rgb ? colorSpace : CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.interpolationQuality = .high
        if flattenAlpha {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: targetSize.0, height: targetSize.1))
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetSize.0, height: targetSize.1))
        return context.makeImage() ?? image
    }

    private static func encodeWebPViaCLI(
        cgImage: CGImage,
        quality: Double,
        capabilities: ConverterCapabilities
    ) throws -> Data {
        guard let cwebp = capabilities.cwebpPath else {
            throw ConverterError.unsupportedConversion(
                "WebP encoding requires cwebp (install via: brew install webp). Decoding WebP is supported natively."
            )
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let tempPNG = tempDir.appendingPathComponent("input.png")
        let tempWebP = tempDir.appendingPathComponent("output.webp")

        guard let dest = CGImageDestinationCreateWithURL(tempPNG as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ConverterError.encodingFailed("Failed to stage temporary PNG for WebP.")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ConverterError.encodingFailed("Failed to write temporary PNG for WebP.")
        }

        let q = Int((min(1.0, max(0.1, quality)) * 100.0).rounded())
        try runProcess(executable: cwebp, arguments: ["-q", "\(q)", tempPNG.path, "-o", tempWebP.path])
        return try Data(contentsOf: tempWebP)
    }

    // MARK: - Document Conversion

    @discardableResult
    static func convertDocument(
        sourceURL: URL,
        from sourceFormat: ConverterFormat,
        to targetFormat: ConverterFormat,
        outputURL: URL,
        options: ConverterDocumentOptions,
        capabilities: ConverterCapabilities = .detect()
    ) throws -> Int64 {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if sourceFormat == .pdf {
            return try convertFromPDF(
                sourceURL: sourceURL,
                to: targetFormat,
                outputURL: outputURL,
                options: options,
                capabilities: capabilities
            )
        }

        if targetFormat == .pdf {
            return try convertToPDF(
                sourceURL: sourceURL,
                from: sourceFormat,
                outputURL: outputURL,
                capabilities: capabilities
            )
        }

        // DOCX <-> RTF <-> HTML <-> TXT via macOS /usr/bin/textutil
        let textutilFormat = textutilArg(for: targetFormat)
        try runProcess(
            executable: "/usr/bin/textutil",
            arguments: ["-convert", textutilFormat, "-output", outputURL.path, sourceURL.path]
        )

        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func convertFromPDF(
        sourceURL: URL,
        to targetFormat: ConverterFormat,
        outputURL: URL,
        options: ConverterDocumentOptions,
        capabilities: ConverterCapabilities
    ) throws -> Int64 {
        if targetFormat == .docx, let soffice = capabilities.sofficePath {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try runProcess(
                executable: soffice,
                arguments: ["--headless", "--convert-to", "docx", "--outdir", tempDir.path, sourceURL.path]
            )
            let produced = tempDir.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + ".docx")
            if FileManager.default.fileExists(atPath: produced.path) {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: produced, to: outputURL)
                let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                return (attrs[.size] as? NSNumber)?.int64Value ?? 0
            }
        }

        guard let pdf = PDFDocument(url: sourceURL) else {
            throw ConverterError.unreadableSource
        }

        let totalPages = pdf.pageCount
        let pageIndices = ConverterDocumentOptions.parsePageIndices(options.pageRangeText, totalPages: totalPages)
            ?? Array(0..<max(0, totalPages))

        if targetFormat == .txt {
            var chunks: [String] = []
            for idx in pageIndices {
                if let pageText = pdf.page(at: idx)?.string, !pageText.isEmpty {
                    chunks.append(pageText)
                }
            }
            let combined = chunks.joined(separator: "\n\n")
            guard let data = combined.data(using: .utf8) else {
                throw ConverterError.encodingFailed("Failed to encode extracted text as UTF-8.")
            }
            try data.write(to: outputURL, options: .atomic)
            return Int64(data.count)
        }

        // Rich extraction for RTF, HTML, or native DOCX bridge
        let combinedAttr = NSMutableAttributedString()
        for (offset, idx) in pageIndices.enumerated() {
            guard let page = pdf.page(at: idx) else { continue }
            if let attr = page.attributedString {
                combinedAttr.append(attr)
            } else if let text = page.string {
                combinedAttr.append(NSAttributedString(string: text))
            }
            if offset < pageIndices.count - 1 {
                combinedAttr.append(NSAttributedString(string: "\n\n"))
            }
        }

        if targetFormat == .rtf || targetFormat == .html {
            let docType: NSAttributedString.DocumentType = (targetFormat == .rtf) ? .rtf : .html
            let data = try combinedAttr.data(
                from: NSRange(location: 0, length: combinedAttr.length),
                documentAttributes: [.documentType: docType]
            )
            try data.write(to: outputURL, options: .atomic)
            return Int64(data.count)
        }

        if targetFormat == .docx {
            // Native fallback: PDFKit -> RTF -> textutil -> DOCX
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let tempRTF = tempDir.appendingPathComponent("bridge.rtf")
            let rtfData = try combinedAttr.data(
                from: NSRange(location: 0, length: combinedAttr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            try rtfData.write(to: tempRTF, options: .atomic)
            try runProcess(
                executable: "/usr/bin/textutil",
                arguments: ["-convert", "docx", "-output", outputURL.path, tempRTF.path]
            )
            let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            return (attrs[.size] as? NSNumber)?.int64Value ?? 0
        }

        throw ConverterError.unsupportedConversion("Unsupported target format \(targetFormat.displayName) from PDF.")
    }

    private static func convertToPDF(
        sourceURL: URL,
        from sourceFormat: ConverterFormat,
        outputURL: URL,
        capabilities: ConverterCapabilities
    ) throws -> Int64 {
        if sourceFormat == .docx, let soffice = capabilities.sofficePath {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            try runProcess(
                executable: soffice,
                arguments: ["--headless", "--convert-to", "pdf", "--outdir", tempDir.path, sourceURL.path]
            )
            let produced = tempDir.appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent + ".pdf")
            if FileManager.default.fileExists(atPath: produced.path) {
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.removeItem(at: outputURL)
                }
                try FileManager.default.moveItem(at: produced, to: outputURL)
                let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                return (attrs[.size] as? NSNumber)?.int64Value ?? 0
            }
        }

        let attrString: NSAttributedString
        if sourceFormat == .docx {
            // Convert DOCX -> RTF via textutil first
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let tempRTF = tempDir.appendingPathComponent("intermediate.rtf")
            try runProcess(
                executable: "/usr/bin/textutil",
                arguments: ["-convert", "rtf", "-output", tempRTF.path, sourceURL.path]
            )
            attrString = try loadAttributedString(from: tempRTF, format: .rtf)
        } else {
            attrString = try loadAttributedString(from: sourceURL, format: sourceFormat)
        }

        try renderAttributedStringToPDF(attrString, outputURL: outputURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func loadAttributedString(from url: URL, format: ConverterFormat) throws -> NSAttributedString {
        let data = try Data(contentsOf: url)
        switch format {
        case .rtf:
            return try NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        case .html:
            return try NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )
        case .txt:
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return NSAttributedString(
                string: text,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5),
                    .foregroundColor: NSColor.black
                ]
            )
        default:
            throw ConverterError.unsupportedConversion("Cannot load \(format.displayName) as attributed text.")
        }
    }

    /// Thread-safe multi-page PDF rendering using CoreText (`CTFramesetter`).
    private static func renderAttributedStringToPDF(_ attributedString: NSAttributedString, outputURL: URL) throws {
        var pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let margin: CGFloat = 54
        let printableRect = pageRect.insetBy(dx: margin, dy: margin)

        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let pdfContext = CGContext(consumer: consumer, mediaBox: &pageRect, nil) else {
            throw ConverterError.encodingFailed("Could not create PDF context.")
        }

        let mutableAttr = NSMutableAttributedString(attributedString: attributedString)
        if mutableAttr.length == 0 {
            mutableAttr.append(NSAttributedString(string: " "))
        }
        // Ensure legible dark ink if source had no explicit color
        mutableAttr.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: mutableAttr.length)) { value, range, _ in
            if value == nil {
                mutableAttr.addAttribute(.foregroundColor, value: NSColor.black, range: range)
            }
        }

        let framesetter = CTFramesetterCreateWithAttributedString(mutableAttr as CFAttributedString)
        var currentRange = CFRange(location: 0, length: 0)

        repeat {
            pdfContext.beginPage(mediaBox: &pageRect)
            let path = CGMutablePath()
            path.addRect(printableRect)
            let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
            CTFrameDraw(frame, pdfContext)
            let visibleRange = CTFrameGetVisibleStringRange(frame)
            currentRange.location += max(1, visibleRange.length)
            pdfContext.endPage()
        } while currentRange.location < mutableAttr.length

        pdfContext.closePDF()
    }

    private static func extractPlainTextWithTextUtil(from url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func textutilArg(for format: ConverterFormat) -> String {
        switch format {
        case .txt: return "txt"
        case .rtf: return "rtf"
        case .html: return "html"
        case .docx: return "docx"
        default: return format.rawValue
        }
    }

    private static func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ConverterError.processFailed(
                errStr.isEmpty ? "Conversion tool exited with status \(process.terminationStatus)." : errStr
            )
        }
    }
}

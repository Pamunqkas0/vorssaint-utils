// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum PDFToDocxConverter {
    private enum PageElement {
        case paragraph(TextParagraph, topY: CGFloat)
        case image(ImageBlock, topY: CGFloat)

        var sortY: CGFloat {
            switch self {
            case .paragraph(_, let y), .image(_, let y):
                return y
            }
        }
    }

    private struct TextLine {
        let text: String
        let bounds: CGRect
        let fontSize: CGFloat
        let isBold: Bool
        let isItalic: Bool
        let hexColor: String
    }

    private struct TextParagraph {
        var text: String
        var bounds: CGRect
        var fontSize: CGFloat
        var isBold: Bool
        var isItalic: Bool
        var hexColor: String
        var isCentered: Bool
        var isListItem: Bool
    }

    private struct ImageBlock {
        let pngData: Data
        let widthPoints: CGFloat
        let heightPoints: CGFloat
    }

    static func convert(
        pdfURL: URL,
        pageIndices: [Int]?,
        outputURL: URL
    ) throws -> Int64 {
        guard let pdf = PDFDocument(url: pdfURL) else {
            throw ConverterError.unreadableSource
        }

        let totalPages = pdf.pageCount
        let indices = pageIndices ?? Array(0..<max(0, totalPages))
        guard !indices.isEmpty else {
            throw ConverterError.unreadableSource
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintPDF2DOCX-\(UUID().uuidString)", isDirectory: true)
        let relsDir = tempDir.appendingPathComponent("_rels", isDirectory: true)
        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        let wordRelsDir = wordDir.appendingPathComponent("_rels", isDirectory: true)
        let mediaDir = wordDir.appendingPathComponent("media", isDirectory: true)

        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var bodyXML = ""
        var mediaRelsXML = ""
        var imageCounter = 0

        // Use first page dimensions for Word section page size (default US Letter)
        let firstBounds = pdf.page(at: indices[0])?.bounds(for: .mediaBox)
            ?? CGRect(x: 0, y: 0, width: 612, height: 792)
        let pageWidthTwips = max(7200, Int((firstBounds.width * 20).rounded()))
        let pageHeightTwips = max(7200, Int((firstBounds.height * 20).rounded()))
        let marginTwips = 1080 // 0.75 inch margins
        let maxContentWidthPoints = max(240, firstBounds.width - 108) // 54pt * 2 = 108pt margins

        for (pageOffset, pageIndex) in indices.enumerated() {
            guard let page = pdf.page(at: pageIndex) else { continue }
            let elements = extractPageElements(from: page)

            for element in elements {
                switch element {
                case .paragraph(let para, _):
                    bodyXML += paragraphXML(for: para)
                case .image(let img, _):
                    imageCounter += 1
                    let fileName = "image\(imageCounter).png"
                    let relId = "rIdImg\(imageCounter)"
                    let imgURL = mediaDir.appendingPathComponent(fileName)
                    try img.pngData.write(to: imgURL, options: .atomic)
                    mediaRelsXML += """
                      <Relationship Id="\(relId)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/\(fileName)"/>\n
                    """
                    bodyXML += imageParagraphXML(
                        relId: relId,
                        docPrId: imageCounter,
                        widthPoints: img.widthPoints,
                        heightPoints: img.heightPoints,
                        maxWidthPoints: maxContentWidthPoints
                    )
                }
            }

            if pageOffset < indices.count - 1 {
                bodyXML += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>\n"
            }
        }

        let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Default Extension="png" ContentType="image/png"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let rootRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        let documentRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        \(mediaRelsXML)</Relationships>
        """

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
                    xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
                    xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
                    xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
                    xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">
          <w:body>
        \(bodyXML)    <w:sectPr>
              <w:pgSz w:w="\(pageWidthTwips)" w:h="\(pageHeightTwips)"/>
              <w:pgMar w:top="\(marginTwips)" w:right="\(marginTwips)" w:bottom="\(marginTwips)" w:left="\(marginTwips)"/>
            </w:sectPr>
          </w:body>
        </w:document>
        """

        try contentTypesXML.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)
        try rootRelsXML.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)
        try documentRelsXML.write(to: wordRelsDir.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)
        try documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintOut-\(UUID().uuidString).docx")
        defer { try? FileManager.default.removeItem(at: tempZip) }

        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.currentDirectoryURL = tempDir
        zipProcess.arguments = ["-r", "-q", tempZip.path, "."]
        zipProcess.standardOutput = Pipe()
        let errPipe = Pipe()
        zipProcess.standardError = errPipe
        try zipProcess.run()
        zipProcess.waitUntilExit()

        guard zipProcess.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ConverterError.processFailed(err.isEmpty ? "Failed to package DOCX archive." : err)
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        try FileManager.default.moveItem(at: tempZip, to: outputURL)
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        return (attrs[.size] as? NSNumber)?.int64Value ?? 0
    }

    // MARK: - Page Element Extraction (Text + Cropped Figures)

    private static func extractPageElements(from page: PDFPage) -> [PageElement] {
        let pageBounds = page.bounds(for: .mediaBox)
        let rawImageRects = detectImageRects(on: page, pageBounds: pageBounds)
        let mergedImageRects = mergeNearbyRects(rawImageRects, tolerance: 16, within: pageBounds)

        // Extract text lines and filter out lines whose center sits inside a figure rect
        let rawLines = extractTextLines(from: page, pageBounds: pageBounds)
        let textLines = rawLines.filter { line in
            let center = CGPoint(x: line.bounds.midX, y: line.bounds.midY)
            return !mergedImageRects.contains { $0.insetBy(dx: -2, dy: -2).contains(center) }
        }

        // Expand figure rects slightly (10pt) to include arrows/borders, without overlapping text lines
        let paddedImageRects = mergedImageRects.map { rect -> CGRect in
            var expanded = rect.insetBy(dx: -10, dy: -10).intersection(pageBounds)
            for line in textLines {
                if expanded.intersects(line.bounds) {
                    // Trim top or bottom if it touches a text line
                    if line.bounds.minY >= rect.maxY {
                        expanded.size.height = max(rect.height, line.bounds.minY - 2 - expanded.minY)
                    } else if line.bounds.maxY <= rect.minY {
                        let newMinY = min(rect.minY, line.bounds.maxY + 2)
                        expanded.size.height = max(rect.height, expanded.maxY - newMinY)
                        expanded.origin.y = newMinY
                    }
                }
            }
            return expanded.intersection(pageBounds)
        }

        var elements: [PageElement] = []

        // Group text lines into paragraphs, splitting whenever an image sits vertically between lines
        let paragraphs = groupLinesIntoParagraphs(textLines, pageBounds: pageBounds, imageRects: paddedImageRects)
        for para in paragraphs {
            elements.append(.paragraph(para, topY: para.bounds.maxY))
        }

        for rect in paddedImageRects {
            if let png = renderPageCropToPNG(page: page, cropRect: rect, scale: 2.5) {
                let block = ImageBlock(
                    pngData: png,
                    widthPoints: rect.width,
                    heightPoints: rect.height
                )
                elements.append(.image(block, topY: rect.maxY))
            }
        }

        // Sort top-to-bottom (highest maxY first in PDF coordinates)
        elements.sort { $0.sortY > $1.sortY }
        return elements
    }

    private static func extractTextLines(from page: PDFPage, pageBounds: CGRect) -> [TextLine] {
        guard let fullSelection = page.selection(for: pageBounds) else { return [] }
        let lineSelections = fullSelection.selectionsByLine()
        var result: [TextLine] = []

        for sel in lineSelections {
            let rawText = (sel.string ?? "")
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { continue }

            let bounds = sel.bounds(for: page)
            guard !bounds.isEmpty else { continue }

            var fontSize: CGFloat = 11
            var isBold = false
            var isItalic = false
            var hexColor = "1F2937"

            if let attr = sel.attributedString, attr.length > 0 {
                let attrs = attr.attributes(at: 0, effectiveRange: nil)
                if let font = attrs[.font] as? NSFont {
                    fontSize = max(8, min(32, font.pointSize))
                    let traits = font.fontDescriptor.symbolicTraits
                    isBold = traits.contains(.bold)
                    isItalic = traits.contains(.italic)
                }
                if let color = attrs[.foregroundColor] as? NSColor,
                   let rgb = color.usingColorSpace(.sRGB) {
                    let r = Int((rgb.redComponent * 255).rounded())
                    let g = Int((rgb.greenComponent * 255).rounded())
                    let b = Int((rgb.blueComponent * 255).rounded())
                    hexColor = String(format: "%02X%02X%02X", r, g, b)
                }
            }

            result.append(TextLine(
                text: rawText,
                bounds: bounds,
                fontSize: fontSize,
                isBold: isBold,
                isItalic: isItalic,
                hexColor: hexColor
            ))
        }

        // Sort top-to-bottom, then left-to-right
        result.sort {
            if abs($0.bounds.maxY - $1.bounds.maxY) > 4 {
                return $0.bounds.maxY > $1.bounds.maxY
            }
            return $0.bounds.minX < $1.bounds.minX
        }
        return result
    }

    private static func groupLinesIntoParagraphs(
        _ lines: [TextLine],
        pageBounds: CGRect,
        imageRects: [CGRect]
    ) -> [TextParagraph] {
        guard !lines.isEmpty else { return [] }
        var paragraphs: [TextParagraph] = []

        func makeParagraph(from line: TextLine) -> TextParagraph {
            let centered = abs(line.bounds.midX - pageBounds.midX) < 28
                && line.bounds.width < pageBounds.width * 0.72
                && !startsListItem(line.text)
            return TextParagraph(
                text: line.text,
                bounds: line.bounds,
                fontSize: line.fontSize,
                isBold: line.isBold,
                isItalic: line.isItalic,
                hexColor: line.hexColor,
                isCentered: centered,
                isListItem: startsListItem(line.text)
            )
        }

        var current = makeParagraph(from: lines[0])

        for line in lines.dropFirst() {
            let verticalGap = current.bounds.minY - line.bounds.maxY
            let sameStyle = abs(current.fontSize - line.fontSize) <= 1.5 && current.isBold == line.isBold
            let newListItem = startsListItem(line.text)
            let imageInBetween = imageRects.contains { rect in
                rect.maxY <= current.bounds.minY + 4 && rect.minY >= line.bounds.maxY - 4
            }

            let shouldJoin = !newListItem
                && !imageInBetween
                && sameStyle
                && !current.isCentered
                && verticalGap >= -4
                && verticalGap <= max(8, current.fontSize * 0.85)

            if shouldJoin {
                current.text += " " + line.text
                current.bounds = current.bounds.union(line.bounds)
            } else {
                paragraphs.append(current)
                current = makeParagraph(from: line)
            }
        }
        paragraphs.append(current)
        return paragraphs
    }

    private static func startsListItem(_ text: String) -> Bool {
        if text.hasPrefix("• ") || text.hasPrefix("- ") || text.hasPrefix("* ") {
            return true
        }
        // Match "1. ", "12. ", "A. ", "B. "
        if let dotIndex = text.firstIndex(of: "."),
           dotIndex > text.startIndex {
            let prefix = text[..<dotIndex]
            let afterDot = text.index(after: dotIndex)
            if afterDot < text.endIndex && text[afterDot] == " " {
                if prefix.count <= 3 && prefix.allSatisfy(\.isNumber) {
                    return true
                }
                if prefix.count == 1 && prefix.allSatisfy({ $0.isLetter && $0.isUppercase }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - CGPDFScanner Image Region Detection

    private final class ScannerState {
        var ctmStack: [CGAffineTransform] = [.identity]
        var xObjectDict: CGPDFDictionaryRef?
        var imageRects: [CGRect] = []

        var currentCTM: CGAffineTransform {
            get { ctmStack.last ?? .identity }
            set {
                if ctmStack.isEmpty {
                    ctmStack.append(newValue)
                } else {
                    ctmStack[ctmStack.count - 1] = newValue
                }
            }
        }
    }

    private static func detectImageRects(on page: PDFPage, pageBounds: CGRect) -> [CGRect] {
        guard let cgPage = page.pageRef else {
            return []
        }
        let stream = CGPDFContentStreamCreateWithPage(cgPage)
        defer { CGPDFContentStreamRelease(stream) }

        guard let operatorTable = CGPDFOperatorTableCreate() else {
            return []
        }
        defer { CGPDFOperatorTableRelease(operatorTable) }

        CGPDFOperatorTableSetCallback(operatorTable, "q") { _, info in
            guard let info else { return }
            let state = Unmanaged<ScannerState>.fromOpaque(info).takeUnretainedValue()
            state.ctmStack.append(state.currentCTM)
        }

        CGPDFOperatorTableSetCallback(operatorTable, "Q") { _, info in
            guard let info else { return }
            let state = Unmanaged<ScannerState>.fromOpaque(info).takeUnretainedValue()
            if state.ctmStack.count > 1 {
                state.ctmStack.removeLast()
            }
        }

        CGPDFOperatorTableSetCallback(operatorTable, "cm") { scanner, info in
            guard let info else { return }
            let state = Unmanaged<ScannerState>.fromOpaque(info).takeUnretainedValue()
            var f: CGPDFReal = 0
            var e: CGPDFReal = 0
            var d: CGPDFReal = 0
            var c: CGPDFReal = 0
            var b: CGPDFReal = 0
            var a: CGPDFReal = 0
            guard CGPDFScannerPopNumber(scanner, &f),
                  CGPDFScannerPopNumber(scanner, &e),
                  CGPDFScannerPopNumber(scanner, &d),
                  CGPDFScannerPopNumber(scanner, &c),
                  CGPDFScannerPopNumber(scanner, &b),
                  CGPDFScannerPopNumber(scanner, &a) else { return }
            let matrix = CGAffineTransform(a: a, b: b, c: c, d: d, tx: e, ty: f)
            state.currentCTM = matrix.concatenating(state.currentCTM)
        }

        CGPDFOperatorTableSetCallback(operatorTable, "Do") { scanner, info in
            guard let info else { return }
            let state = Unmanaged<ScannerState>.fromOpaque(info).takeUnretainedValue()
            var namePtr: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &namePtr), let namePtr else { return }
            guard let xObjects = state.xObjectDict else { return }
            var streamObj: CGPDFStreamRef?
            guard CGPDFDictionaryGetStream(xObjects, namePtr, &streamObj),
                  let streamObj,
                  let dict = CGPDFStreamGetDictionary(streamObj) else { return }

            var subtypePtr: UnsafePointer<Int8>?
            guard CGPDFDictionaryGetName(dict, "Subtype", &subtypePtr),
                  let subtypePtr else { return }
            let subtype = String(cString: subtypePtr)
            if subtype == "Image" {
                let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
                let transformed = unitRect.applying(state.currentCTM)
                if transformed.width >= 24, transformed.height >= 24 {
                    state.imageRects.append(transformed)
                }
            }
        }

        let state = ScannerState()
        if let pageDict = cgPage.dictionary {
            var resourcesDict: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(pageDict, "Resources", &resourcesDict),
               let resourcesDict {
                var xObjDict: CGPDFDictionaryRef?
                if CGPDFDictionaryGetDictionary(resourcesDict, "XObject", &xObjDict) {
                    state.xObjectDict = xObjDict
                }
            }
        }

        let infoPtr = Unmanaged.passUnretained(state).toOpaque()
        let scanner = CGPDFScannerCreate(stream, operatorTable, infoPtr)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)

        return state.imageRects
            .map { $0.intersection(pageBounds) }
            .filter { $0.width >= 24 && $0.height >= 24 }
    }

    private static func mergeNearbyRects(_ rects: [CGRect], tolerance: CGFloat, within bounds: CGRect) -> [CGRect] {
        var remaining = rects
        var merged: [CGRect] = []

        while !remaining.isEmpty {
            var current = remaining.removeFirst()
            var didMerge = true
            while didMerge {
                didMerge = false
                var nextRemaining: [CGRect] = []
                for candidate in remaining {
                    if current.insetBy(dx: -tolerance, dy: -tolerance).intersects(candidate) {
                        current = current.union(candidate)
                        didMerge = true
                    } else {
                        nextRemaining.append(candidate)
                    }
                }
                remaining = nextRemaining
            }
            merged.append(current.intersection(bounds))
        }
        return merged
    }

    private static func renderPageCropToPNG(page: PDFPage, cropRect: CGRect, scale: CGFloat) -> Data? {
        let pixelW = max(1, Int((cropRect.width * scale).rounded()))
        let pixelH = max(1, Int((cropRect.height * scale).rounded()))
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -cropRect.origin.x, y: -cropRect.origin.y)
        page.draw(with: .mediaBox, to: ctx)

        guard let cgImage = ctx.makeImage() else { return nil }
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutableData as Data
    }

    // MARK: - OpenXML Helpers

    private static func paragraphXML(for para: TextParagraph) -> String {
        let escaped = escapeXML(para.text)
        let szHalfPoints = Int((para.fontSize * 2).rounded())
        let indentAttr = para.isListItem ? " w:left=\"360\" w:hanging=\"240\"" : ""
        let jcXML = para.isCentered ? "<w:jc w:val=\"center\"/>" : ""
        let boldXML = para.isBold ? "<w:b/>" : ""
        let italicXML = para.isItalic ? "<w:i/>" : ""

        return """
            <w:p>
              <w:pPr>
                \(jcXML)<w:spacing w:before="40" w:after="100" w:line="276" w:lineRule="auto"/>\(indentAttr.isEmpty ? "" : "<w:ind\(indentAttr)/>")
              </w:pPr>
              <w:r>
                <w:rPr>
                  <w:rFonts w:ascii="Calibri" w:hAnsi="Calibri"/>
                  \(boldXML)\(italicXML)<w:color w:val="\(para.hexColor)"/>
                  <w:sz w:val="\(szHalfPoints)"/><w:szCs w:val="\(szHalfPoints)"/>
                </w:rPr>
                <w:t xml:space="preserve">\(escaped)</w:t>
              </w:r>
            </w:p>\n
        """
    }

    private static func imageParagraphXML(
        relId: String,
        docPrId: Int,
        widthPoints: CGFloat,
        heightPoints: CGFloat,
        maxWidthPoints: CGFloat
    ) -> String {
        let scale = widthPoints > maxWidthPoints ? (maxWidthPoints / widthPoints) : 1.0
        let emuWidth = max(12700, Int((widthPoints * scale * 12700).rounded()))
        let emuHeight = max(12700, Int((heightPoints * scale * 12700).rounded()))

        return """
            <w:p>
              <w:pPr>
                <w:jc w:val="center"/>
                <w:spacing w:before="80" w:after="160"/>
              </w:pPr>
              <w:r>
                <w:drawing>
                  <wp:inline distT="0" distB="0" distL="0" distR="0">
                    <wp:extent cx="\(emuWidth)" cy="\(emuHeight)"/>
                    <wp:docPr id="\(docPrId)" name="Figure \(docPrId)"/>
                    <a:graphic>
                      <a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">
                        <pic:pic>
                          <pic:nvPicPr>
                            <pic:cNvPr id="\(docPrId)" name="Figure \(docPrId)"/>
                            <pic:cNvPicPr/>
                          </pic:nvPicPr>
                          <pic:blipFill>
                            <a:blip r:embed="\(relId)"/>
                            <a:stretch><a:fillRect/></a:stretch>
                          </pic:blipFill>
                          <pic:spPr>
                            <a:xfrm>
                              <a:off x="0" y="0"/>
                              <a:ext cx="\(emuWidth)" cy="\(emuHeight)"/>
                            </a:xfrm>
                            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom>
                          </pic:spPr>
                        </pic:pic>
                      </a:graphicData>
                    </a:graphic>
                  </wp:inline>
                </w:drawing>
              </w:r>
            </w:p>\n
        """
    }

    private static func escapeXML(_ string: String) -> String {
        var out = ""
        out.reserveCapacity(string.count)
        for scalar in string.unicodeScalars {
            let v = scalar.value
            // Strip illegal XML 1.0 control characters
            if v < 0x20 && v != 0x09 && v != 0x0A && v != 0x0D { continue }
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}

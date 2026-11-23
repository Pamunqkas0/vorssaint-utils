// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ConverterTests {
    static func run(_ suite: TestSuite) {
        suite.run("ConverterTests.formatDetection") {
            let cases: [(String, ConverterFormat?)] = [
                ("photo.png", .png),
                ("photo.JPG", .jpeg),
                ("photo.jpeg", .jpeg),
                ("image.heic", .heic),
                ("scan.tiff", .tiff),
                ("icon.bmp", .bmp),
                ("anim.gif", .gif),
                ("hero.webp", .webp),
                ("report.pdf", .pdf),
                ("notes.txt", .txt),
                ("doc.rtf", .rtf),
                ("index.html", .html),
                ("proposal.docx", .docx),
                ("archive.zip", nil)
            ]
            for (name, expected) in cases {
                let url = URL(fileURLWithPath: "/tmp/\(name)")
                suite.expect(ConverterFormat.detect(from: url) == expected,
                             "detect(\(name)) == \(String(describing: expected))")
            }
        }

        suite.run("ConverterTests.pageRangeParsing") {
            suite.expect(ConverterDocumentOptions.parsePageIndices("", totalPages: 5) == nil,
                         "empty page range returns nil (all pages)")
            suite.expect(ConverterDocumentOptions.parsePageIndices("1-3, 5", totalPages: 6) == [0, 1, 2, 4],
                         "parses 1-based ranges and single pages into sorted 0-based indices")
            suite.expect(ConverterDocumentOptions.parsePageIndices("4-2, 99", totalPages: 5) == [1, 2, 3],
                         "handles reversed bounds and ignores out-of-range pages")
        }

        suite.run("ConverterTests.imageConversionAndResize") {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("VorssaintConverterTests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourcePNG = tempDir.appendingPathComponent("sample.png")
            let created = writeSamplePNG(to: sourcePNG, width: 120, height: 80)
            suite.expect(created, "created sample PNG fixture")

            let meta = ConverterEngine.inspectFile(at: sourcePNG, format: .png)
            suite.expect(meta.imageDimensions == CGSize(width: 120, height: 80),
                         "inspectFile reads pixel dimensions")

            let outJPEG = ConverterEngine.uniqueOutputURL(
                for: sourcePNG,
                targetFormat: .jpeg,
                destination: .customFolder(tempDir)
            )
            do {
                let jpegSize = try ConverterEngine.convertImage(
                    sourceURL: sourcePNG,
                    to: .jpeg,
                    outputURL: outJPEG,
                    options: ConverterImageOptions(quality: 0.7, preserveMetadata: false, resizeMode: .percentage(50))
                )
                suite.expect(jpegSize > 0 && FileManager.default.fileExists(atPath: outJPEG.path),
                             "converted PNG -> JPEG with size \(jpegSize)")
                let outMeta = ConverterEngine.inspectFile(at: outJPEG, format: .jpeg)
                suite.expect(outMeta.imageDimensions == CGSize(width: 60, height: 40),
                             "50% resize produced 60x40 JPEG")
            } catch {
                suite.expect(false, "PNG -> JPEG conversion threw: \(error)")
            }

            let outHEIC = tempDir.appendingPathComponent("sample.heic")
            do {
                let heicSize = try ConverterEngine.convertImage(
                    sourceURL: sourcePNG,
                    to: .heic,
                    outputURL: outHEIC,
                    options: ConverterImageOptions(quality: 0.8, preserveMetadata: true, resizeMode: .original)
                )
                suite.expect(heicSize > 0 && FileManager.default.fileExists(atPath: outHEIC.path),
                             "converted PNG -> HEIC natively")
            } catch {
                suite.expect(false, "PNG -> HEIC conversion threw: \(error)")
            }
        }

        suite.run("ConverterTests.documentConversions") {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("VorssaintDocTests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tempDir) }

            let sourceTXT = tempDir.appendingPathComponent("hello.txt")
            let sampleText = "Vorssaint Document Converter\nLine two for PDF and DOCX verification."
            try? sampleText.write(to: sourceTXT, atomically: true, encoding: .utf8)

            // TXT -> PDF
            let outPDF = tempDir.appendingPathComponent("hello.pdf")
            do {
                let pdfSize = try ConverterEngine.convertDocument(
                    sourceURL: sourceTXT,
                    from: .txt,
                    to: .pdf,
                    outputURL: outPDF,
                    options: ConverterDocumentOptions()
                )
                suite.expect(pdfSize > 0 && FileManager.default.fileExists(atPath: outPDF.path),
                             "TXT -> PDF created valid file")
                let pdfMeta = ConverterEngine.inspectFile(at: outPDF, format: .pdf)
                suite.expect((pdfMeta.documentPageCount ?? 0) >= 1, "PDF has at least 1 page")

                // PDF -> TXT roundtrip
                let roundtripTXT = tempDir.appendingPathComponent("roundtrip.txt")
                let txtSize = try ConverterEngine.convertDocument(
                    sourceURL: outPDF,
                    from: .pdf,
                    to: .txt,
                    outputURL: roundtripTXT,
                    options: ConverterDocumentOptions(pageRangeText: "1")
                )
                let extracted = (try? String(contentsOf: roundtripTXT, encoding: .utf8)) ?? ""
                suite.expect(txtSize > 0 && extracted.contains("Vorssaint"),
                             "PDF -> TXT extracted text content")
            } catch {
                suite.expect(false, "TXT <-> PDF conversion threw: \(error)")
            }

            // TXT -> DOCX via native textutil
            let outDOCX = tempDir.appendingPathComponent("hello.docx")
            do {
                let docxSize = try ConverterEngine.convertDocument(
                    sourceURL: sourceTXT,
                    from: .txt,
                    to: .docx,
                    outputURL: outDOCX,
                    options: ConverterDocumentOptions()
                )
                suite.expect(docxSize > 0 && FileManager.default.fileExists(atPath: outDOCX.path),
                             "TXT -> DOCX via native textutil succeeded")
            } catch {
                suite.expect(false, "TXT -> DOCX conversion threw: \(error)")
            }
        }
    }

    private static func writeSamplePNG(to url: URL, width: Int, height: Int) -> Bool {
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.55, blue: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}

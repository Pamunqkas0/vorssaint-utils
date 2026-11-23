// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct ConverterSplitComparisonView: View {
    let originalImage: NSImage?
    let convertedImage: NSImage?
    let sourceLabel: String
    let targetLabel: String
    let isLoading: Bool

    @State private var splitPosition: CGFloat = 0.5
    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = max(1, geo.size.height)
            let dividerX = min(max(12, width * splitPosition), width - 12)

            ZStack {
                // Subtle checkerboard for transparent images
                CheckerboardBackground()
                    .opacity(0.35)

                // Right / Bottom layer: Converted preview
                if let converted = convertedImage ?? originalImage {
                    Image(nsImage: converted)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width, height: height)
                }

                // Left / Top layer: Original clipped to dividerX
                if let original = originalImage {
                    Image(nsImage: original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width, height: height)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle()
                                    .frame(width: dividerX, height: height)
                                Spacer(minLength: 0)
                            }
                        )
                }

                // Corner badges
                VStack {
                    HStack {
                        labelPill(sourceLabel, color: .secondary)
                        Spacer()
                        labelPill(targetLabel, color: .accentColor)
                    }
                    .padding(8)
                    Spacer()
                }
                .allowsHitTesting(false)

                // Draggable vertical divider
                ZStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.9))
                        .frame(width: isDragging ? 2.5 : 1.5, height: height)
                        .shadow(color: .black.opacity(0.45), radius: 3)

                    Circle()
                        .fill(.ultraThickMaterial)
                        .frame(width: 26, height: 26)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.7), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "arrow.left.and.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.primary)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 5, y: 2)
                        .scaleEffect(isDragging ? 1.12 : 1.0)
                }
                .position(x: dividerX, y: height / 2)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            splitPosition = min(0.95, max(0.05, value.location.x / width))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                isDragging = false
                            }
                        }
                )

                if isLoading {
                    VStack {
                        Spacer()
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating preview…")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func labelPill(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.45), lineWidth: 0.8)
            )
    }
}

private struct CheckerboardBackground: View {
    private let squareSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for col in 0..<cols where (row + col).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(Color.gray.opacity(0.28)))
                }
            }
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Live Activity strip in the closed Dynamic Island while files are converting in the background.
struct NotchConverterStrip: View {
    @ObservedObject var service: NotchService
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var converter = ConverterService.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var iconSize: CGFloat { NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight) }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }

    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
    }

    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    private var completedCount: Int {
        converter.items.filter { $0.status.isFinished }.count
    }

    private var totalCount: Int {
        max(1, converter.items.count)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                service.openActivity(.fileConverter)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.cyan.opacity(0.28), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.15, CGFloat(completedCount) / CGFloat(totalCount)))
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: max(8, iconSize * 0.48), weight: .bold))
                        .foregroundStyle(.cyan)
                }
                .frame(width: iconSize, height: iconSize)
                .padding(.leading, iconInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }

            Color.clear.frame(width: geometry.compactActivityCameraGap)

            Button {
                service.openActivity(.fileConverter)
            } label: {
                Text("\(completedCount)/\(totalCount)")
                    .font(.system(size: textSize, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.cyan)
                    .lineLimit(1)
                    .padding(.trailing, textInset)
                    .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                           alignment: .trailing)
                    .contentShape(Rectangle())
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: completedCount)
    }
}

struct NotchCapsuleConverterStrip: View {
    @ObservedObject var service: NotchService
    let size: CGSize
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var converter = ConverterService.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var completedCount: Int { converter.items.filter { $0.status.isFinished }.count }
    private var totalCount: Int { max(1, converter.items.count) }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.cyan)
            Text("\(completedCount)/\(totalCount)")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(.cyan)
        }
        .padding(.horizontal, 12)
        .frame(width: size.width, height: size.height)
        .contentShape(Capsule())
        .onTapGesture {
            service.openActivity(.fileConverter)
        }
    }
}

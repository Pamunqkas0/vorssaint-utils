// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The clock keeps the right of the camera. The left shows the timer's mark,
/// or its explicitly chosen companion: a download, working agents, the next
/// event's clock or the music playing, each opening its own page. The wings
/// are as wide as the wider side needs, and both sit at the ends, where the
/// island shows.
struct NotchTimerStrip: View {
    @ObservedObject var service: NotchService
    /// Where the island draws it: its own strip as of the last update, or
    /// another display's when the island shows on every display.
    var displayGeometry: NotchGeometry? = nil
    @ObservedObject private var timer = NotchTimerService.shared
    // The companion's label reads these.
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared
    @ObservedObject private var l10n = L10n.shared

    private var geometry: NotchGeometry { displayGeometry ?? service.compactActivityGeometry }
    private var companion: NotchCompactActivity? { service.compactCompanion }
    private var iconSize: CGFloat { NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight) }
    private var textSize: CGFloat { NotchTimerSupport.stripTextSize(height: geometry.compactActivityContentHeight) }
    private var pomodoroReading: Bool {
        timer.session.mode == .pomodoro && NotchTimerSupport.isPomodoroFullPrecisionEnabled()
    }
    private var iconInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        if let companion { return NotchCompanionMark.inset(companion, geometry: geometry) }
        return geometry.compactActivityEdgeInset(boxHeight: iconSize, radius: iconSize / 2)
    }
    private var textInset: CGFloat {
        guard !geometry.compactActivityUsesFooter else { return 0 }
        // Digits carry no descenders, so their ink is about the cap height.
        return geometry.compactActivityEdgeInset(boxHeight: textSize * 0.72, radius: 0)
    }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if companion == .calendar { service.openCountdownEvent() }
                else { service.openActivity(companion?.module ?? .timer) }
            } label: {
                Group {
                    if geometry.compactActivityWingWidth >= 28 {
                        if let companion {
                            NotchCompanionMark(companion: companion, geometry: geometry)
                        } else {
                            NotchTimerPulseMark(size: iconSize,
                                                progress: timer.session.duration > 0
                                                    ? 1 - timer.session.reading(at: timer.now) / timer.session.duration : 0,
                                                running: timer.session.isRunning,
                                                completed: timer.session.completed,
                                                countsUp: timer.session.countsUp)
                        }
                    }
                }
                .padding(.leading, iconInset)
                .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                       alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(companion.map { NotchCompanionMark.label($0, language: l10n.language) }
                                ?? FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
            Color.clear.frame(width: geometry.compactActivityCameraGap)
            if timer.session.isRunning {
                TimelineView(.periodic(from: NotchTimerSupport.tickScheduleDate(for: timer.session, at: timer.now),
                                       by: NotchTimerSupport.tickInterval(for: timer.session))) { _ in reading }
            } else {
                reading
            }
        }
        .frame(height: geometry.compactActivityContentHeight)
        .padding(.horizontal, geometry.compactActivityHorizontalPadding)
        .padding(.top, geometry.compactActivityTopPadding)
        .buttonStyle(.plain)
        .accessibilityHint(FeatureStrings.notch(l10n.language).open)
    }

    private var reading: some View {
        let now = timer.now
        let text = NotchTimerSupport.compactText(for: timer.session, at: now,
                                                 locale: Locale(identifier: l10n.language.rawValue))
        let pomodoroParts: (whole: String, fraction: String)? = {
            guard pomodoroReading, let separator = text.lastIndex(of: ".") else { return nil }
            return (String(text[..<separator]), String(text[separator...]))
        }()
        return Button { service.openActivity(.timer) } label: {
            Group {
                if geometry.compactActivityWingWidth >= 42 {
                    if let pomodoroParts {
                        HStack(spacing: 0) {
                            Text(pomodoroParts.whole)
                                .foregroundStyle(Color(red: 1, green: 0.624, blue: 0.039))
                            Text(pomodoroParts.fraction)
                                .foregroundStyle(Color(red: 1, green: 0.624, blue: 0.039).opacity(0.72))
                        }
                        .font(.system(size: textSize, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .modifier(NotchRollingDigits(value: String(text.prefix(8)), countsDown: true,
                                                     everySecond: true))
                    } else {
                        Text(text)
                            .font(.system(size: textSize, weight: .medium)).monospacedDigit()
                            .foregroundStyle(Color(red: 1, green: 0.624, blue: 0.039))
                            .lineLimit(1).minimumScaleFactor(0.65)
                            .modifier(NotchRollingDigits(value: text, countsDown: !timer.session.countsUp, everySecond: false))
                    }
                }
            }
            // A reading that gains or loses a character resizes the wings;
            // the service measures the same reading.
            .onChange(of: NotchAgentSupport.readingShape(text)) { _, _ in
                DispatchQueue.main.async { service.refreshPresentation() }
            }
            .padding(.trailing, textInset)
            .frame(width: geometry.compactActivityWingWidth, height: geometry.compactActivityContentHeight,
                   alignment: .trailing)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(FeatureStrings.notchActivities(l10n.language).phase(timer.session.phase))
        .accessibilityValue(NotchTimerSupport.clockText(for: timer.session, at: now))
    }
}

/// A tiny progress mark gives the closed island a live cue without adding a
/// separate animation timer: it follows the same 50 ms Pomodoro updates as
/// the clock and settles into a check when a session completes.
private struct NotchTimerPulseMark: View {
    let size: CGFloat
    let progress: Double
    let running: Bool
    let completed: Bool
    let countsUp: Bool
    @State private var celebration = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color { Color(red: 1, green: 0.624, blue: 0.039) }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.24), lineWidth: 1.6)
            Circle().trim(from: 0, to: CGFloat(min(1, max(0, countsUp ? 1 - progress : progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: completed ? "checkmark" : running ? "flame.fill" : "timer")
                .font(.system(size: max(7, size * 0.52), weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .animation(reduceMotion ? nil : .linear(duration: 0.05), value: progress)
        .shadow(color: tint.opacity(celebration ? 0.75 : 0), radius: celebration ? 5 : 0)
        .scaleEffect(celebration ? 1.12 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.55), value: celebration)
        .onChange(of: completed) { _, done in
            guard done else { return }
            celebration = true
            guard !reduceMotion else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { celebration = false }
        }
        .accessibilityHidden(true)
    }
}

/// What shares a strip with a timer or an event, drawn at the strip's left
/// end: a download's progress, the working agents' marks, the event's dot
/// and clock or the playing track's cover.
struct NotchCompanionMark: View {
    let companion: NotchCompactActivity
    let geometry: NotchGeometry
    @ObservedObject private var downloads = NotchDownloadService.shared
    @ObservedObject private var music = NotchMusicService.shared
    @ObservedObject private var usage = AgentUsageService.shared
    @ObservedObject private var calendar = NotchCalendarService.shared

    var body: some View {
        switch companion {
        case .downloads:
            downloadIndicator
        case .agents:
            let working = Self.working
            HStack(spacing: 1) {
                ForEach(working) { NotchAgentGlyph(provider: $0, size: Self.agentMarkSize(working.count, geometry)) }
            }
        case .calendar:
            if let countdown = calendar.countdown {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    NotchCalendarStrip.clockMark(countdown, remaining: NotchCalendarSupport.countdownText(
                        until: countdown.target, now: context.date))
                }
            }
        case .music:
            NotchMusicCover(artwork: music.artwork, side: geometry.compactMusicArtworkSide,
                            radius: geometry.compactMusicArtworkRadius, source: music.playback?.track)
        case .timer, .keepAwake, .watch, .fileConverter:
            EmptyView()
        }
    }

    private var downloadIndicator: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 13))
            if geometry.compactActivityWingWidth >= 80,
               let fraction = downloads.items.first(where: { $0.active && !$0.completed })?.fraction {
                Text(fraction, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
        }
        .lineLimit(1)
        .clipped()
    }

    private static var working: [AgentProvider] {
        let live = AgentUsageService.shared.snapshot.live
        return AgentProvider.allCases.filter { provider in live.contains { $0.provider == provider } }
    }

    private static func agentMarkSize(_ working: Int, _ geometry: NotchGeometry) -> CGFloat {
        NotchTimerSupport.stripAgentMarkSize(height: geometry.compactActivityContentHeight, working: working)
    }

    /// The mark's distance from the strip's end, as far from the curve as
    /// from the strip's top and bottom.
    static func inset(_ companion: NotchCompactActivity, geometry: NotchGeometry) -> CGFloat {
        switch companion {
        case .agents:
            let side = agentMarkSize(working.count, geometry)
            return geometry.compactActivityEdgeInset(boxHeight: side + 4, radius: (side + 4) / 2)
        case .music:
            return geometry.compactMusicArtworkInset
        case .calendar:
            return geometry.compactActivityEdgeInset(boxHeight: 9, radius: 0)
        case .downloads, .timer, .keepAwake, .watch, .fileConverter:
            let side = min(13, NotchTimerSupport.stripIconSize(height: geometry.compactActivityContentHeight))
            return geometry.compactActivityEdgeInset(boxHeight: side, radius: side / 2)
        }
    }

    static func label(_ companion: NotchCompactActivity, language: AppLanguage) -> String {
        switch companion {
        case .downloads:
            return FeatureStrings.notchFiles(language).downloadsTitle
        case .agents:
            return working.map(\.displayName).joined(separator: ", ")
        case .calendar:
            let text = FeatureStrings.notchCalendar(language)
            guard let countdown = NotchCalendarService.shared.countdown else { return text.title }
            return "\(countdown.ongoing ? text.ongoing : text.next): "
                + NotchCalendarStrip.displayTitle(countdown.event, untitled: text.untitled)
        case .music:
            let playback = NotchMusicService.shared.playback
            let title = playback?.track.title ?? FeatureStrings.radialMenu(language).mediaNowPlaying
            return [title, playback?.track.artist].compactMap { $0 }.joined(separator: ", ")
        case .timer, .keepAwake, .watch, .fileConverter:
            return companion.title(language)
        }
    }
}

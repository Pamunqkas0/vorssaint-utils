// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchMeetingNotesView: View {
    @ObservedObject var service: NotchService
    var size: CGSize = .zero
    @ObservedObject private var notesService = MeetingNotesService.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var timerService = NotchTimerService.shared
    @ObservedObject private var calendarService = NotchCalendarService.shared
    @ObservedObject private var permissions = Permissions.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(DefaultsKey.notchPomodoroFocusMinutes) private var focusMinutes = 25
    @AppStorage(DefaultsKey.notchTimerSoundEnabled) private var timerSoundEnabled = true
    @AppStorage("notch.meetingNotes.panelWidth.tasks.points.v2") private var taskPanelWidthPreference = 0.0
    @AppStorage("notch.meetingNotes.panelWidth.focus.points.v2") private var focusPanelWidthPreference = 0.0
    @AppStorage("notch.meetingNotes.panelWidth.notepad.points.v2") private var notepadPanelWidthPreference = 0.0
    @AppStorage("notch.meetingNotes.panelWidth.agenda.points.v2") private var agendaPanelWidthPreference = 0.0
    
    @State private var inputText: String = ""
    @FocusState private var inputHasFocus: Bool
    @State private var isEditingTitle: Bool = false
    @State private var titleEditBuffer: String = ""
    @State private var copiedFeedback: Bool = false
    @State private var hoveredItemId: UUID? = nil
    @State private var hoveredMeetingId: UUID? = nil
    @State private var showingCompletedTasks = false
    @State private var selectedNoteID: UUID?
    @State private var noteDraftTitle = ""
    @State private var noteDraftText = ""
    @State private var savedNoteTitle = ""
    @State private var savedNoteText = ""
    @State private var agendaDay = Calendar.current.startOfDay(for: Date())
    @State private var selectedFocusTaskID: UUID?
    @State private var activeWorkspaceTab = "Workspace"
    @State private var hoveredResizeBoundary: Int?
    @State private var activeResizeCard: Int?
    @State private var resizingLeadingEdge = false
    @State private var resizeStartWidth: CGFloat?
    @State private var resizeTranslation: CGFloat = 0
    @FocusState private var noteEditorFocused: Bool
    
    // Drag & Drop Column Target States
    @State private var targetedColumn: MeetingKanbanColumn? = nil
    
    // Card Detail & Edit View State
    @State private var editingItem: MeetingItem? = nil
    @State private var editCardTitle: String = ""
    @State private var editCardDetails: String = ""
    @State private var editCardType: MeetingItemType = .actionItem
    @State private var editCardCompleted: Bool = false
    
    // Boards & Meetings Manager State
    @State private var showingBoardsManager: Bool = false
    
    private var strings: MeetingNotesStrings {
        FeatureStrings.meetingNotes(l10n.language)
    }
    
    private var activeSession: MeetingSession {
        notesService.document.activeMeeting
    }

    private var selectedNote: MeetingItem? {
        activeSession.notesList.first { $0.id == selectedNoteID } ?? activeSession.notesList.first
    }

    private var noteWordCount: Int {
        noteDraftText.split(whereSeparator: \.isWhitespace).count
    }

    private var noteHasChanges: Bool {
        noteDraftTitle != savedNoteTitle || noteDraftText != savedNoteText
    }

    private var panelInk: Color { Color(red: 0.12, green: 0.15, blue: 0.18) }

    private func panelTint(_ column: MeetingKanbanColumn) -> Color {
        switch column {
        case .todo: return Color(red: 0.72, green: 0.88, blue: 0.79)
        case .notes: return Color(red: 0.94, green: 0.87, blue: 0.62)
        case .done: return Color(red: 0.72, green: 0.84, blue: 0.94)
        }
    }
    
    var body: some View {
        Group {
            if let editing = editingItem {
                cardDetailView(item: editing)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else if showingBoardsManager {
                boardsManagerView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                boardView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .notchBand(leading: {
            if editingItem != nil {
                detailHeaderLeading
            } else if showingBoardsManager {
                boardsManagerHeaderLeading
            } else {
                headerLeading
            }
        }, trailing: {
            if editingItem != nil {
                detailHeaderTrailing
            } else if showingBoardsManager {
                boardsManagerHeaderTrailing
            } else {
                HStack(spacing: 6) {
                    workspaceTabs
                    headerTrailing
                    Button(action: closeToFeatureList) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 25, height: 25)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(FeatureStrings.notch(l10n.language).sectionsTitle)
                    Button(action: closeToFeatureList) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                            .frame(width: 25, height: 25)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Close to Feature List")
                }
            }
        })
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: editingItem != nil)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: showingBoardsManager)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: activeSession.items)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.8), value: notesService.allMeetings.count)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82), value: activeWorkspaceTab)
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil }
        }
        .onAppear(perform: loadSelectedNote)
        .onAppear(perform: migrateLegacyPanelWidths)
        .onAppear { service.setMeetingNotesDetailVisible(editingItem != nil) }
        .onChange(of: editingItem?.id) { _, id in
            service.setMeetingNotesDetailVisible(id != nil)
        }
        .onAppear {
            if selectedFocusTaskID == nil { selectedFocusTaskID = activeSession.pendingToDos.first?.id }
        }
        .onChange(of: activeSession.id) { _, _ in loadSelectedNote() }
        .onChange(of: activeSession.notesList.map(\.id)) { _, noteIDs in
            if let selectedNoteID {
                if !noteIDs.contains(selectedNoteID) { loadSelectedNote() }
            } else {
                loadSelectedNote()
            }
        }
        .onDisappear {
            saveNotepadDraft()
            service.setMeetingNotesDetailVisible(false)
        }
    }
    
    // MARK: - Board View (Kanban)
    
    private var boardView: some View {
        VStack(spacing: 8) {
            if activeWorkspaceTab == "Workspace" {
                trelloBoard
            } else if activeWorkspaceTab == "Week" {
                weekDashboard
            } else {
                insightsDashboard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .onExitCommand {
            if isEditingTitle {
                isEditingTitle = false
            } else if inputHasFocus || noteEditorFocused {
                inputHasFocus = false
                noteEditorFocused = false
            } else {
                closeToFeatureList()
            }
        }
    }
    
    // MARK: - Board Header (Top Row)
    
    private var headerLeading: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.grid.2x2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
            
            if isEditingTitle {
                TextField(strings.meetingTitlePlaceholder, text: $titleEditBuffer, onCommit: {
                    commitTitleEdit()
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: 160)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            } else {
                // Interactive Meeting / Board Switcher Dropdown
                Menu {
                    Section("Switch Board (\(notesService.allMeetings.count))") {
                        ForEach(notesService.allMeetings) { session in
                            Button {
                                saveNotepadDraft()
                                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                    notesService.switchToMeeting(id: session.id)
                                }
                            } label: {
                                if session.id == activeSession.id {
                                    Label(session.title, systemImage: "checkmark")
                                } else {
                                    Text(session.title)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        saveNotepadDraft()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            notesService.startNewMeeting(title: "New Meeting")
                        }
                    } label: {
                        Label("New Board / Meeting", systemImage: "plus.circle")
                    }
                    
                    Button {
                        titleEditBuffer = activeSession.title
                        isEditingTitle = true
                    } label: {
                        Label("Rename Current Board", systemImage: "pencil")
                    }
                    
                    Button {
                        saveNotepadDraft()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            showingBoardsManager = true
                        }
                    } label: {
                        Label("Manage All Boards...", systemImage: "square.grid.2x2")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(activeSession.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .menuStyle(.borderlessButton)
            }
            
            // Overall Progress Badge
            if activeSession.hasTasks {
                HStack(spacing: 4) {
                    Circle()
                        .fill(activeSession.completedCount == activeSession.totalActionItems ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text("\(activeSession.completedCount)/\(activeSession.totalActionItems) Done")
                        .font(.system(size: 10, weight: .medium)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: Capsule())
            }

            headerIconButton("paperclip", title: "Clips") {
                service.select(.clipboard)
            }
            headerIconButton("viewfinder", title: "Capture") {
                ScreenCaptureService.shared.capture(initial: .screenshot)
            }
            headerIconButton("moon", title: "Open Focus settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                    NSWorkspace.shared.open(url)
                }
            }
            headerIconButton(service.pinned ? "pin.fill" : "pin", title: service.pinned ? "Unpin" : "Pin") {
                service.pinned.toggle()
            }
            headerIconButton("ladybug", title: "Send bug report") {
                (NSApp.delegate as? AppDelegate)?.openFeedbackWindow(kind: .bug)
            }
        }
    }

    private func headerIconButton(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 23, height: 23)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
    
    private var headerTrailing: some View {
        HStack(spacing: 6) {
            // Copy Notes Button
            Button {
                saveNotepadDraft()
                if notesService.copyNotesToClipboard() {
                    copiedFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        copiedFeedback = false
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                    if copiedFeedback {
                        Text(strings.copied)
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(copiedFeedback ? .green : .white.opacity(0.85))
                .padding(.horizontal, copiedFeedback ? 8 : 6)
                .frame(height: 26)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(strings.copyNotes)
            
            // More Menu Button
            Menu {
                Menu("Switch Board ▸") {
                    ForEach(notesService.allMeetings) { session in
                        Button {
                            saveNotepadDraft()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                notesService.switchToMeeting(id: session.id)
                            }
                        } label: {
                            if session.id == activeSession.id {
                                Label(session.title, systemImage: "checkmark")
                            } else {
                                Text(session.title)
                            }
                        }
                    }
                }
                
                Button {
                    saveNotepadDraft()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        notesService.startNewMeeting(title: "New Meeting")
                    }
                } label: {
                    Label(strings.newMeeting, systemImage: "plus.circle")
                }
                
                Button {
                    saveNotepadDraft()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        notesService.duplicateCurrentMeeting()
                    }
                } label: {
                    Label("Duplicate Current Board", systemImage: "plus.square.on.square")
                }
                
                Button {
                    saveNotepadDraft()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showingBoardsManager = true
                    }
                } label: {
                    Label("Manage All Boards...", systemImage: "square.grid.2x2")
                }

                Button(action: resetWorkspacePanelWidths) {
                    Label("Reset Card Sizes", systemImage: "arrow.counterclockwise")
                }

                Button(action: closeToFeatureList) {
                    Label("All Features / Switch Feature...", systemImage: "square.grid.2x2")
                }
                
                Divider()
                
                if activeSession.completedCount > 0 {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            notesService.clearCompleted()
                        }
                    } label: {
                        Label(strings.clearCompleted, systemImage: "checkmark.circle.badge.xmark")
                    }
                }
                
                if notesService.allMeetings.count > 1 {
                    Button(role: .destructive) {
                        saveNotepadDraft()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            notesService.deleteMeeting(id: activeSession.id)
                        }
                    } label: {
                        Label("Delete Current Board", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var workspaceTabs: some View {
        HStack(spacing: 2) {
            ForEach(["Workspace", "Week", "Insights", "Settings"], id: \.self) { tab in
                Button {
                    if tab == "Settings" {
                        service.openSettings(showing: .meetingNotes)
                    } else {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
                            activeWorkspaceTab = tab
                        }
                    }
                } label: {
                    Text(tab)
                        .font(.system(size: 9, weight: activeWorkspaceTab == tab ? .semibold : .medium))
                        .foregroundStyle(.white.opacity(activeWorkspaceTab == tab ? 0.92 : 0.52))
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(activeWorkspaceTab == tab ? Color.white.opacity(0.14) : .clear,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.055), in: Capsule())
    }
    
    // MARK: - Boards Manager Header
    
    private var boardsManagerHeaderLeading: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                showingBoardsManager = false
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text("Board")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private var boardsManagerHeaderTrailing: some View {
        Button {
            saveNotepadDraft()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                notesService.startNewMeeting(title: "New Meeting")
                showingBoardsManager = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                Text("New Board")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                LinearGradient(
                    colors: [.cyan, .teal],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Boards Manager View
    
    private var boardsManagerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header title
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.cyan)
                Text("All Saved Boards & Meetings")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                Text("\(notesService.allMeetings.count)")
                    .font(.system(size: 9.5, weight: .bold)).monospacedDigit()
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Color.cyan.opacity(0.18), in: Capsule())
                
                Spacer()
                
                Text("Click to switch board")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            
            // Horizontal list of board cards
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(notesService.allMeetings) { session in
                        let isActive = session.id == activeSession.id
                        let isHovered = hoveredMeetingId == session.id
                        
                        Button {
                            saveNotepadDraft()
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                notesService.switchToMeeting(id: session.id)
                                showingBoardsManager = false
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                // Top row: Active indicator / Delete button
                                HStack {
                                    if isActive {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color.green)
                                                .frame(width: 5, height: 5)
                                            Text("Active")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Color(red: 0.12, green: 0.48, blue: 0.28))
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.2), in: Capsule())
                                    } else {
                                        Text(session.formattedDate)
                                            .font(.system(size: 8.5)).monospacedDigit()
                                            .foregroundStyle(panelInk.opacity(0.56))
                                    }
                                    
                                    Spacer()
                                    
                                    if notesService.allMeetings.count > 1 {
                                        Button {
                                            saveNotepadDraft()
                                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                                notesService.deleteMeeting(id: session.id)
                                            }
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 9))
                                                .foregroundStyle(.red.opacity(0.7))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Delete board")
                                    }
                                }
                                
                                // Board Title
                                Text(session.title)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(panelInk)
                                    .lineLimit(1)
                                
                                // Stats
                                HStack(spacing: 8) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checklist")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.orange)
                                        Text("\(session.completedCount)/\(session.totalActionItems)")
                                            .font(.system(size: 10)).monospacedDigit()
                                            .foregroundStyle(panelInk.opacity(0.72))
                                    }
                                    
                                    HStack(spacing: 3) {
                                        Image(systemName: "note.text")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.cyan)
                                        Text("\(session.totalNotes)")
                                            .font(.system(size: 10)).monospacedDigit()
                                            .foregroundStyle(panelInk.opacity(0.72))
                                    }
                                }
                                
                                Spacer(minLength: 0)
                                
                                // Progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(panelInk.opacity(0.12))
                                            .frame(height: 3)
                                        Capsule()
                                            .fill(LinearGradient(colors: [.orange, .green], startPoint: .leading, endPoint: .trailing))
                                            .frame(width: max(0, geo.size.width * CGFloat(session.progressFraction)), height: 3)
                                    }
                                }
                                .frame(height: 3)
                            }
                            .padding(10)
                            .frame(width: 175, height: 105)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(panelTint(isActive ? .todo : .notes).opacity(isHovered ? 0.98 : 0.86))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(isActive ? Color.cyan.opacity(0.65) : Color.white.opacity(0.55), lineWidth: isActive ? 1.5 : 0.8)
                                    )
                            )
                        }
                        .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 11))
                        .onHover { hoveredMeetingId = $0 ? session.id : nil }
                    }
                    
                    // Add new board card
                    Button {
                        saveNotepadDraft()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            notesService.startNewMeeting(title: "New Meeting")
                            showingBoardsManager = false
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(Color(red: 0.08, green: 0.42, blue: 0.6))
                            Text("New Board")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(panelInk)
                        }
                        .frame(width: 120, height: 105)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(panelInk.opacity(0.24), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .background(panelTint(.done).opacity(0.55), in: RoundedRectangle(cornerRadius: 11))
                        )
                    }
                    .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 11))
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                showingBoardsManager = false
            }
        }
    }
    
    // MARK: - Detail Header (When Editing Card)
    
    private var detailHeaderLeading: some View {
        Button {
            saveAndDismissEdit()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                Text("Board")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Color.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private var detailHeaderTrailing: some View {
        HStack(spacing: 6) {
            // Delete button
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    if let editing = editingItem {
                        notesService.deleteItem(editing.id)
                    }
                    editingItem = nil
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red.opacity(0.85))
                    .frame(width: 26, height: 26)
                    .background(Color.red.opacity(0.12), in: Circle())
            }
            .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 11))
            .help("Delete note")
            
            // Done button
            Button {
                saveAndDismissEdit()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Done")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(panelInk)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(panelTint(.todo), in: Capsule())
            }
            .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 13))
        }
    }
    
    // MARK: - Quick Input Bar
    
    private var inputBar: some View {
        HStack(spacing: 6) {
            // Target Column Selector
            HStack(spacing: 2) {
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                        notesService.quickInputType = .actionItem
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10.5))
                        Text("To-Do")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(notesService.quickInputType == .actionItem ? panelInk : .white.opacity(0.52))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(notesService.quickInputType == .actionItem ? panelTint(.todo).opacity(0.95) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.75)) {
                        notesService.quickInputType = .note
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 10.5))
                        Text("Note")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(notesService.quickInputType == .note ? panelInk : .white.opacity(0.52))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(notesService.quickInputType == .note ? panelTint(.notes).opacity(0.95) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            
            // Input TextField
            TextField(notesService.quickInputType == .actionItem ? "Quick add task to To-Do (Press ↵)..." : "Quick add note to Notes (Press ↵)...", text: $inputText, onCommit: {
                submitItem()
            })
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(panelInk)
            .focused($inputHasFocus)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(inputHasFocus
                            ? panelInk.opacity(0.42)
                            : panelInk.opacity(0.12), lineWidth: inputHasFocus ? 1.2 : 0.8)
            )
            
            // Submit Button
            Button {
                submitItem()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? panelInk.opacity(0.28) : panelInk.opacity(0.76))
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Trello Horizontal Kanban Board
    
    private var trelloBoard: some View {
        ScrollView(.horizontal, showsIndicators: customPanelsOverflow) {
            HStack(alignment: .top, spacing: 8) {
                taskWidget
                    .overlay(alignment: .leading) { panelResizeHandle(card: 0, leading: true) }
                    .overlay(alignment: .trailing) { panelResizeHandle(card: 0, leading: false) }
                pomodoroWidget
                    .overlay(alignment: .trailing) { panelResizeHandle(card: 1, leading: false) }
                notepadWidget
                    .overlay(alignment: .trailing) { panelResizeHandle(card: 2, leading: false) }
                calendarWidget
                    .overlay(alignment: .trailing) { panelResizeHandle(card: 3, leading: false) }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            .animation(reduceMotion ? nil : .interactiveSpring(response: 0.26, dampingFraction: 0.9),
                       value: currentPanelWidths)
        }
        .scrollIndicators(customPanelsOverflow ? .visible : .hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var weekDashboard: some View {
        HStack(alignment: .top, spacing: 8) {
            taskWidget
            calendarWidget
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private var insightsDashboard: some View {
        let total = activeSession.totalActionItems
        let completed = activeSession.completedCount
        return HStack(spacing: 10) {
            insightTile(title: "Tasks completed", value: "\(completed) / \(total)",
                        detail: total == 0 ? "Add tasks to track progress" : "\(Int(activeSession.progressFraction * 100))% complete",
                        symbol: "checkmark.circle", tint: panelTint(.todo))
            insightTile(title: "Meeting notes", value: "\(activeSession.totalNotes)",
                        detail: "Saved in \(activeSession.title)", symbol: "note.text",
                        tint: panelTint(.notes))
            insightTile(title: "Focus sessions", value: "\(timerService.session.completedFocuses)",
                        detail: timerService.session.hasSession ? "A session is in progress" : "Ready for a focus session",
                        symbol: "timer", tint: Color(red: 0.81, green: 0.77, blue: 0.92))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private func insightTile(title: String, value: String, detail: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(panelInk.opacity(0.68))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(panelInk.opacity(0.72))
            Text(value)
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(panelInk)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(panelInk.opacity(0.58))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(tint))
    }

    private var taskWidget: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.orange.opacity(0.95))
                Text("Tasks")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(panelInk)
                Spacer(minLength: 0)
                Text("\(activeSession.completedCount)/\(activeSession.totalActionItems)")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(panelInk.opacity(0.7))
            }

            HStack(spacing: 4) {
                taskFilterButton("To-Do", count: activeSession.pendingToDos.count, completed: false)
                taskFilterButton("Completed", count: activeSession.completedToDos.count, completed: true)
            }
            .padding(3)
            .background(panelInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            inputBar

            kanbanColumn(
                column: showingCompletedTasks ? .done : .todo,
                title: showingCompletedTasks ? "Completed" : "To-Do",
                icon: showingCompletedTasks ? "checkmark.circle.fill" : "checklist",
                accentColor: showingCompletedTasks ? .green : .orange,
                count: showingCompletedTasks ? activeSession.completedToDos.count : activeSession.pendingToDos.count,
                items: showingCompletedTasks ? activeSession.completedToDos : activeSession.pendingToDos,
                emptyMessage: showingCompletedTasks ? "Completed tasks will appear here." : "All caught up. Add a task above.",
                showsClearButton: showingCompletedTasks,
                showsSurface: false,
                width: max(0, taskCardWidth - 16)
            )
            .frame(maxHeight: .infinity)
        }
        .padding(.top, 9)
        .padding(.horizontal, 8)
        .frame(width: taskCardWidth)
        .background(panelBackground(.todo))
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: showingCompletedTasks)
    }

    private func taskFilterButton(_ title: String, count: Int, completed: Bool) -> some View {
        let selected = showingCompletedTasks == completed
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                showingCompletedTasks = completed
            }
        } label: {
            HStack(spacing: 5) {
                Text(title).lineLimit(1)
                Text("\(count)").monospacedDigit().opacity(0.78)
            }
            .font(.system(size: 10, weight: selected ? .semibold : .medium))
            .foregroundStyle(panelInk.opacity(selected ? 0.92 : 0.62))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 25)
            .background(selected ? Color.white.opacity(0.66) : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func panelBackground(_ column: MeetingKanbanColumn) -> some View {
        panelBackground(panelTint(column))
    }

    private func panelBackground(_ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(tint.opacity(0.9))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.38), lineWidth: 1)
            }
    }

    private var pomodoroWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.43, green: 0.36, blue: 0.68))
                Text("Focus timer")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(panelInk)
                Spacer(minLength: 0)
            }

            Menu {
                ForEach(activeSession.pendingToDos) { task in
                    Button {
                        selectedFocusTaskID = task.id
                    } label: {
                        if selectedFocusTaskID == task.id {
                            Label(task.title, systemImage: "checkmark")
                        } else {
                            Text(task.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Text(activeSession.pendingToDos.first(where: { $0.id == selectedFocusTaskID })?.title
                         ?? "Choose a task")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(panelInk.opacity(0.72))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color.white.opacity(0.4), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .disabled(activeSession.pendingToDos.isEmpty)

            if !NotchTimerSupport.isEnabled() {
                Spacer(minLength: 4)
                Image(systemName: "timer")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(panelInk.opacity(0.45))
                    .frame(maxWidth: .infinity)
                Text("Turn on the Timer module to use focus sessions here.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(panelInk.opacity(0.68))
                    .multilineTextAlignment(.center)
                Button("Timer settings") { service.openSettings(showing: .timer) }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(panelInk)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.55), in: Capsule())
                Spacer(minLength: 0)
            } else {
                focusTimerContent
            }
        }
        .padding(12)
        .frame(width: focusCardWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(Color(red: 0.81, green: 0.77, blue: 0.92)))
    }

    private var focusTimerContent: some View {
        VStack(spacing: 8) {
            if timerService.session.isRunning {
                TimelineView(.periodic(from: NotchTimerSupport.tickScheduleDate(for: timerService.session,
                                                                               at: timerService.now),
                                       by: NotchTimerSupport.tickInterval(for: timerService.session))) { _ in
                    focusTimerReadout
                }
            } else {
                focusTimerReadout
            }

            Text(focusTimerStatus)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(panelInk.opacity(0.58))

            GeometryReader { geometry in
                let progress = focusTimerProgress
                ZStack(alignment: .leading) {
                    Capsule().fill(panelInk.opacity(0.1))
                    Capsule().fill(Color(red: 0.49, green: 0.42, blue: 0.7))
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, 8)

            Spacer(minLength: 4)

            HStack(spacing: 7) {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
                        if timerService.session.isRunning || timerService.session.isPaused {
                            timerService.pauseOrResume()
                        } else if timerService.session.canStartNext {
                            timerService.startNext()
                        } else if timerService.session.completed {
                            timerService.cancel()
                            timerService.start(mode: .pomodoro, minutes: focusMinutes)
                        } else if !timerService.session.hasSession {
                            timerService.start(mode: .pomodoro, minutes: focusMinutes)
                        }
                    }
                } label: {
                    Label(focusPrimaryTitle, systemImage: focusPrimarySymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 31)
                        .background(Color(red: 0.43, green: 0.36, blue: 0.68), in: Capsule())
                }
                .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 16))

                Button(action: completeSelectedFocusTask) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(panelInk.opacity(0.78))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.42), in: Circle())
                }
                .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 17))
                .help("Complete selected task")
            }

            HStack(spacing: 10) {
                Menu {
                    Button("Decrease by 5 minutes") { focusMinutes = max(1, focusMinutes - 5) }
                    Button("Increase by 5 minutes") { focusMinutes = min(180, focusMinutes + 5) }
                    Divider()
                    ForEach([15, 20, 25, 30, 45, 60], id: \.self) { minutes in
                        Button("\(minutes) minutes") { focusMinutes = minutes }
                    }
                } label: {
                    Label("Set time", systemImage: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(panelInk.opacity(0.68))
                }
                .menuStyle(.borderlessButton)
                .disabled(timerService.session.hasSession)

                Button { timerSoundEnabled.toggle() } label: {
                    Image(systemName: timerSoundEnabled ? "speaker.wave.2" : "speaker.slash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(panelInk.opacity(0.62))
                }
                .buttonStyle(.plain)
                .help(timerSoundEnabled ? "Mute timer sound" : "Enable timer sound")
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82), value: timerService.session)
    }

    private var focusTimerStatus: String {
        let session = timerService.session
        guard session.hasSession else { return "Ready" }
        if session.completed { return session.canStartNext ? "Session complete" : "Complete" }
        if session.isPaused { return "Paused" }
        return session.mode == .pomodoro && session.phase != .focus ? session.phase.rawValue : "Focusing"
    }

    private var focusTimerProgress: CGFloat {
        let session = timerService.session
        guard session.hasSession, session.duration > 0 else { return 0 }
        let elapsed = session.duration - session.reading(at: timerService.now)
        return min(1, max(0, elapsed / session.duration))
    }

    private var focusPrimaryTitle: String {
        if timerService.session.isRunning { return "Pause" }
        if timerService.session.isPaused { return "Resume" }
        if timerService.session.canStartNext { return "Start next" }
        if timerService.session.completed { return "Start again" }
        return "Start"
    }

    private var focusPrimarySymbol: String {
        timerService.session.isRunning ? "pause.fill" : "play.fill"
    }

    private func completeSelectedFocusTask() {
        if let task = activeSession.pendingToDos.first(where: { $0.id == selectedFocusTaskID }) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.76)) {
                notesService.toggleItem(task.id)
            }
        }
        if timerService.session.mode == .pomodoro && timerService.session.hasSession {
            timerService.cancel()
        }
    }

    private var focusTimerReadout: some View {
        let session = timerService.session
        let text = session.hasSession
            ? NotchTimerSupport.clockText(session.reading(at: timerService.now))
            : NotchTimerSupport.clockText(TimeInterval(focusMinutes * 60))
        return FocusDotMatrixClock(value: text)
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText(countsDown: true))
    }

    private var notepadWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.54, green: 0.43, blue: 0.17))
                Text("Notepad")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(panelInk)
                Spacer(minLength: 0)
                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(panelInk.opacity(0.7))
                        .frame(width: 25, height: 25)
                        .background(Color.white.opacity(0.46), in: Circle())
                }
                .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 13))
                .help("New note")
                Button {
                    saveNotepadDraft()
                } label: {
                    Image(systemName: noteHasChanges ? "square.and.arrow.down.fill" : "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(noteHasChanges ? Color(red: 0.24, green: 0.5, blue: 0.32) : panelInk.opacity(0.5))
                        .frame(width: 25, height: 25)
                        .background(Color.white.opacity(0.46), in: Circle())
                }
                .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 13))
                .disabled(!noteHasChanges)
                .help("Save note")
            }

            if !activeSession.notesList.isEmpty {
                Menu {
                    ForEach(activeSession.notesList) { note in
                        Button {
                            selectNote(note)
                        } label: {
                            if note.id == selectedNote?.id {
                                Label(note.title.isEmpty ? "Untitled Note" : note.title, systemImage: "checkmark")
                            } else {
                                Text(note.title.isEmpty ? "Untitled Note" : note.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(selectedNote?.title.isEmpty == false ? selectedNote!.title : "Untitled Note")
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(panelInk.opacity(0.72))
                    .padding(.horizontal, 8)
                    .frame(height: 23, alignment: .leading)
                    .background(Color.white.opacity(0.38), in: Capsule())
                }
                .menuStyle(.borderlessButton)
            }

            if selectedNote != nil {
                TextField("Note title", text: $noteDraftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(panelInk)
                    .padding(.horizontal, 9)
                    .frame(height: 29)
                    .background(Color.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                ZStack(alignment: .topLeading) {
                    if noteDraftText.isEmpty {
                        Text("Capture a decision, link, or follow-up…")
                            .font(.system(size: 10.5))
                            .foregroundStyle(panelInk.opacity(0.42))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $noteDraftText)
                        .focused($noteEditorFocused)
                        .font(.system(size: 11))
                        .foregroundStyle(panelInk)
                        .lineSpacing(2)
                        .padding(4)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.32), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .frame(maxHeight: .infinity)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(noteEditorFocused ? panelInk.opacity(0.3) : .clear, lineWidth: 1)
                        .allowsHitTesting(false)
                }

                HStack {
                    Text("\(noteWordCount) words")
                    Spacer()
                    Text(noteHasChanges ? "Unsaved" : selectedNote?.formattedTime ?? "")
                }
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(panelInk.opacity(0.58))
            } else {
                Spacer(minLength: 0)
                Image(systemName: "note.text")
                    .font(.system(size: 23, weight: .light))
                    .foregroundStyle(panelInk.opacity(0.4))
                    .frame(maxWidth: .infinity)
                Text("Your meeting notes will appear here.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(panelInk.opacity(0.62))
                    .multilineTextAlignment(.center)
                Button("Create a note") { createNote() }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(panelInk)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.white.opacity(0.55), in: Capsule())
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(width: notepadCardWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(panelTint(.notes)))
    }

    private var calendarWidget: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.42, blue: 0.66))
                Text("Agenda")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(panelInk)
                Spacer(minLength: 0)
                Button { calendarService.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(panelInk.opacity(0.66))
                        .frame(width: 25, height: 25)
                        .background(Color.white.opacity(0.44), in: Circle())
                }
                .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 13))
                .help("Refresh calendar")
            }

            HStack(spacing: 2) {
                ForEach(calendarWeekDays, id: \.self) { day in
                    let selected = Calendar.current.isDate(day, inSameDayAs: agendaDay)
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) {
                            agendaDay = day
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(panelInk.opacity(0.52))
                            Text(day.formatted(.dateTime.day()))
                                .font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(selected ? .white : panelInk.opacity(0.82))
                                .frame(width: 23, height: 23)
                                .background(selected ? panelInk : .clear, in: Circle())
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if !NotchCalendarSupport.isEnabled() {
                calendarEmptyState(icon: "calendar.badge.exclamationmark", message: "Turn on Calendar in Dynamic Island settings.",
                                   actionTitle: "Calendar settings") {
                    service.openSettings(showing: .calendar)
                }
            } else if permissions.calendarAccess != .fullAccess {
                calendarEmptyState(icon: "lock.fill", message: "Allow local calendar access to see your upcoming meetings.",
                                   actionTitle: permissions.requestingCalendar ? "Requesting…" : "Allow calendar") {
                    permissions.requestCalendar()
                }
                .disabled(permissions.requestingCalendar)
            } else if upcomingCalendarEvents.isEmpty {
                calendarEmptyState(icon: "calendar", message: "No upcoming events found.",
                                   actionTitle: "Open Calendar") {
                    openCalendarApp()
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 7) {
                        ForEach(upcomingCalendarEvents) { event in
                            calendarEventCard(event)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
        .padding(12)
        .frame(width: agendaCardWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(Color(red: 0.7, green: 0.82, blue: 0.93)))
    }

    private var upcomingCalendarEvents: [NotchCalendarEvent] {
        let now = Date()
        return Array(calendarService.events
            .filter { $0.end > now && Calendar.current.isDate($0.start, inSameDayAs: agendaDay) }
            .sorted { $0.start < $1.start }.prefix(4))
    }

    private var calendarWeekDays: [Date] {
        let today = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    private func calendarEmptyState(icon: String, message: String, actionTitle: String,
                                    action: @escaping () -> Void) -> some View {
        VStack(spacing: 9) {
            Spacer(minLength: 0)
            Image(systemName: icon)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(panelInk.opacity(0.42))
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(panelInk.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .font(.system(size: 10, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(panelInk)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(Color.white.opacity(0.55), in: Capsule())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func calendarEventCard(_ event: NotchCalendarEvent) -> some View {
        let isPrimary = upcomingCalendarEvents.first?.id == event.id
        return VStack(alignment: .leading, spacing: 5) {
            Button { openCalendar(event) } label: {
                HStack(alignment: .top, spacing: 7) {
                    Text(event.start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 9.5, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(isPrimary ? .white.opacity(0.66) : Color(red: 0.18, green: 0.42, blue: 0.66))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(event.title.isEmpty ? "Untitled event" : event.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(isPrimary ? .white : panelInk)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !event.location.isEmpty {
                            Text(event.location)
                                .font(.system(size: 9))
                                .foregroundStyle(isPrimary ? .white.opacity(0.68) : panelInk.opacity(0.62))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let url = meetingURL(in: event.location) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Join Meet", systemImage: "video.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isPrimary ? panelInk : panelInk.opacity(0.82))
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(isPrimary ? Color.white.opacity(0.92) : Color.white.opacity(0.45), in: Capsule())
                }
                .buttonStyle(MeetingNotesHoverButtonStyle(cornerRadius: 12))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isPrimary ? Color(red: 0.11, green: 0.12, blue: 0.14)
                    : Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(isPrimary ? 0.08 : 0.38), lineWidth: 0.8)
        }
    }

    private func meetingURL(in location: String) -> URL? {
        for candidate in location.split(whereSeparator: \.isWhitespace) {
            guard let url = URL(string: String(candidate)),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { continue }
            return url
        }
        return nil
    }

    private func openCalendar(_ event: NotchCalendarEvent) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        if let url = NotchCalendarSupport.eventURL(event) {
            NSWorkspace.shared.open([url], withApplicationAt: application, configuration: configuration)
        } else {
            NSWorkspace.shared.openApplication(at: application, configuration: configuration)
        }
    }

    private func openCalendarApp() {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration())
    }

    private func loadSelectedNote() {
        guard let note = activeSession.notesList.first(where: { $0.id == selectedNoteID })
                ?? activeSession.notesList.first else {
            selectedNoteID = nil
            noteDraftTitle = ""
            noteDraftText = ""
            savedNoteTitle = ""
            savedNoteText = ""
            return
        }
        selectedNoteID = note.id
        noteDraftTitle = note.title
        noteDraftText = note.details
        savedNoteTitle = note.title
        savedNoteText = note.details
    }

    private func selectNote(_ note: MeetingItem) {
        saveNotepadDraft()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
            selectedNoteID = note.id
            noteDraftTitle = note.title
            noteDraftText = note.details
            savedNoteTitle = note.title
            savedNoteText = note.details
        }
    }

    private func createNote() {
        saveNotepadDraft()
        notesService.addItem(text: "Untitled Note", type: .note)
        guard let note = activeSession.notesList.first else { return }
        selectedNoteID = note.id
        noteDraftTitle = "Untitled Note"
        savedNoteTitle = "Untitled Note"
        noteDraftText = ""
        savedNoteText = ""
        noteEditorFocused = true
    }

    private func saveNotepadDraft() {
        guard noteHasChanges, let note = activeSession.notesList.first(where: { $0.id == selectedNoteID }) else { return }
        let cleanTitle = noteDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = cleanTitle.isEmpty ? "Untitled Note" : cleanTitle
        notesService.updateItem(id: note.id, title: title, details: noteDraftText,
                               type: .note, isCompleted: false)
        noteDraftTitle = title
        savedNoteTitle = title
        savedNoteText = noteDraftText
    }

    /// Default widths fill the workspace; custom widths may grow past it and scroll.
    private var panelWidthBudget: CGFloat {
        let available = size.width.isFinite && size.width > 0 ? size.width : 900
        return max(0, available - 40)
    }

    private var defaultPanelWidths: [CGFloat] {
        let weights: [CGFloat] = [1.15, 0.86, 1.05, 1.15]
        let total = weights.reduce(0, +)
        return weights.map { (panelWidthBudget * $0 / total).rounded(.down) }
    }

    private var storedPanelWidthPreferences: [CGFloat] {
        [CGFloat(taskPanelWidthPreference), CGFloat(focusPanelWidthPreference),
         CGFloat(notepadPanelWidthPreference), CGFloat(agendaPanelWidthPreference)]
    }

    private var panelWidthsForLayout: [CGFloat] {
        var widths = storedPanelWidthPreferences.enumerated().map { index, saved in
            saved > 0 ? saved : defaultPanelWidths[index]
        }
        if let card = activeResizeCard, let start = resizeStartWidth, widths.indices.contains(card) {
            let directedDelta = resizingLeadingEdge ? -resizeTranslation : resizeTranslation
            widths[card] = min(panelMaximumWidth(card), max(panelMinimumWidth(card), start + directedDelta))
        }
        return widths
    }

    private var customPanelsOverflow: Bool {
        panelWidthsForLayout.reduce(0, +) > panelWidthBudget
    }

    private var currentPanelWidths: [CGFloat] { panelWidthsForLayout }
    private var taskCardWidth: CGFloat { currentPanelWidths[0] }
    private var focusCardWidth: CGFloat { currentPanelWidths[1] }
    private var notepadCardWidth: CGFloat { currentPanelWidths[2] }
    private var agendaCardWidth: CGFloat { currentPanelWidths[3] }

    private func panelMinimumWidth(_ index: Int) -> CGFloat {
        let defaults: [CGFloat] = [164, 128, 144, 144]
        return min(defaults[index], max(72, panelWidthBudget / 4))
    }

    private func panelMaximumWidth(_ index: Int) -> CGFloat {
        [420, 360, 420, 400][index]
    }

    private func panelResizeHandle(card: Int, leading: Bool) -> some View {
        let isActive = activeResizeCard == card && resizingLeadingEdge == leading
        let handleID = card * 2 + (leading ? 0 : 1)
        let isHovered = hoveredResizeBoundary == handleID
        let offset: CGFloat = {
            if card == 0 && leading { return 7 }
            if card == 3 && !leading { return -7 }
            return leading ? -11 : 11
        }()
        return Capsule()
            .fill(Color.black.opacity(isActive ? 0.4 : 0.25))
            .frame(width: isActive || isHovered ? 4 : 3, height: isActive || isHovered ? 42 : 30)
            .overlay {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.white.opacity(isActive || isHovered ? 0.92 : 0.64))
                            .frame(width: 1.5, height: 1.5)
                    }
                }
            }
            .frame(width: 14, height: 58)
            .contentShape(Rectangle())
            .offset(x: offset)
            .zIndex(5)
            .onHover { hovering in
                hoveredResizeBoundary = hovering ? handleID : (hoveredResizeBoundary == handleID ? nil : hoveredResizeBoundary)
                (hovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if activeResizeCard != card || resizingLeadingEdge != leading {
                            activeResizeCard = card
                            resizingLeadingEdge = leading
                            resizeStartWidth = panelWidthsForLayout[card]
                        }
                        resizeTranslation = value.translation.width
                    }
                    .onEnded { value in
                        guard let start = resizeStartWidth else {
                            activeResizeCard = nil
                            resizeTranslation = 0
                            return
                        }
                        let directedDelta = leading ? -value.translation.width : value.translation.width
                        let width = min(panelMaximumWidth(card), max(panelMinimumWidth(card), start + directedDelta))
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
                            storePanelWidth(width, for: card)
                            activeResizeCard = nil
                            resizeStartWidth = nil
                            resizeTranslation = 0
                        }
                    }
            )
            .onTapGesture(count: 2) { resetPanelWidth(card) }
            .accessibilityElement()
            .accessibilityLabel("Resize \(panelName(card)) card")
            .accessibilityHint("Drag left or right to change this card's width. Double-click to restore its default size.")
            .help("Drag to resize \(panelName(card)). Double-click to reset this card.")
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.8), value: isHovered || isActive)
    }

    private func panelName(_ index: Int) -> String {
        ["Tasks", "Focus timer", "Notepad", "Agenda"][index]
    }

    private func storePanelWidth(_ width: CGFloat, for index: Int) {
        switch index {
        case 0: taskPanelWidthPreference = Double(width)
        case 1: focusPanelWidthPreference = Double(width)
        case 2: notepadPanelWidthPreference = Double(width)
        case 3: agendaPanelWidthPreference = Double(width)
        default: break
        }
    }

    private func migrateLegacyPanelWidths() {
        guard storedPanelWidthPreferences.allSatisfy({ $0 <= 0 }) else { return }
        let defaults = UserDefaults.standard
        let legacyKeys = [
            "notch.meetingNotes.panelWidth.tasks.v1",
            "notch.meetingNotes.panelWidth.focus.v1",
            "notch.meetingNotes.panelWidth.notepad.v1",
            "notch.meetingNotes.panelWidth.agenda.v1"
        ]
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return }
        let fallback: [Double] = [1.15, 0.86, 1.05, 1.15]
        let weights = legacyKeys.enumerated().map { index, key in
            defaults.object(forKey: key) as? Double ?? fallback[index]
        }
        let total = max(0.01, weights.reduce(0, +))
        let migrated = weights.map { (panelWidthBudget * CGFloat($0 / total)).rounded(.down) }
        for index in migrated.indices { storePanelWidth(migrated[index], for: index) }
    }

    private func resetPanelWidth(_ index: Int) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
            storePanelWidth(0, for: index)
        }
    }

    private func resetWorkspacePanelWidths() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)) {
            for index in 0..<4 { storePanelWidth(0, for: index) }
        }
    }
    
    // MARK: - Kanban Column Component with Drop Support
    
    private func kanbanColumn(
        column: MeetingKanbanColumn,
        title: String,
        icon: String,
        accentColor: Color,
        count: Int,
        items: [MeetingItem],
        emptyMessage: String,
        showsClearButton: Bool = false,
        showsSurface: Bool = true,
        width: CGFloat
    ) -> some View {
        let isTargeted = targetedColumn == column
        
        return VStack(spacing: 6) {
            // Column Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.95))
                
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(panelInk.opacity(0.9))
                
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold)).monospacedDigit()
                    .foregroundStyle(panelInk)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.34), in: Capsule())
                
                Spacer()
                
                if showsClearButton && count > 0 {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            notesService.clearCompleted()
                        }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(panelInk.opacity(0.56))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.3), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
            
            // Column Cards ScrollView
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 6) {
                    if items.isEmpty {
                        VStack(spacing: 4) {
                            Text(emptyMessage)
                                .font(.system(size: 10.5))
                                .foregroundStyle(panelInk.opacity(0.58))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        ForEach(items) { item in
                            trelloCard(item)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background {
            if showsSurface {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTargeted ? panelTint(column).opacity(0.98) : panelTint(column).opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isTargeted ? accentColor.opacity(0.8) : Color.white.opacity(0.32), lineWidth: isTargeted ? 1.5 : 1)
                    )
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: isTargeted)
        // Drag and Drop destination onto column
        .onDrop(of: [UTType.text.identifier, UTType.plainText.identifier], isTargeted: Binding(
            get: { targetedColumn == column },
            set: { isTarget in
                targetedColumn = isTarget ? column : (targetedColumn == column ? nil : targetedColumn)
            }
        )) { providers in
            handleDrop(providers: providers, targetColumn: column)
        }
    }
    
    // MARK: - Trello Card Component with onDrag and onClick
    
    private func trelloCard(_ item: MeetingItem) -> some View {
        let isHovered = hoveredItemId == item.id
        let isDragging = notesService.draggingItemId == item.id
        
        return HStack(alignment: .top, spacing: 8) {
            // Interactive Checkbox / Note Dot
            if item.type == .actionItem {
                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.65)) {
                        notesService.toggleItem(item.id)
                    }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(item.isCompleted ? Color.green : panelInk.opacity(0.08))
                            .frame(width: 17, height: 17)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(item.isCompleted ? Color.green : panelInk.opacity(0.36), lineWidth: 1.2)
                            )
                        
                        if item.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(panelInk)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.isCompleted ? "Mark incomplete" : "Mark completed")
            } else {
                Circle()
                    .fill(Color(red: 0.03, green: 0.58, blue: 0.72))
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                    .padding(.leading, 6)
            }
            
            // Content & Footer (Click to open edit view)
            VStack(alignment: .leading, spacing: 3) {
                // Card Title
                HStack(alignment: .top, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .strikethrough(item.isCompleted, color: panelInk.opacity(0.38))
                        .foregroundStyle(item.isCompleted ? panelInk.opacity(0.48) : panelInk)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.type == .actionItem {
                        Button { focusTask(item) } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(panelInk.opacity(0.72))
                                .frame(width: 17, height: 19)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Focus on this task")
                        .disabled(item.isCompleted)
                    }
                    Button { openEditView(for: item) } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(panelInk.opacity(0.64))
                            .frame(width: 18, height: 19)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Edit item")
                }
                
                // Description Excerpt if present
                if !item.details.isEmpty {
                    Text(item.details)
                        .font(.system(size: 10))
                        .foregroundStyle(panelInk.opacity(0.7))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Meta row: time, note indicator, and hover action buttons
                HStack(spacing: 5) {
                    if !item.details.isEmpty {
                        Image(systemName: "doc.text")
                            .font(.system(size: 8.5))
                            .foregroundStyle(panelInk.opacity(0.45))
                    }
                    
                    Text(item.formattedTime)
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(panelInk.opacity(0.52))
                    
                    Spacer()
                    
                    if isHovered {
                        // Pencil edit hint icon
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(panelInk.opacity(0.48))
                        
                        // Delete Button
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                                notesService.deleteItem(item.id)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .padding(.top, 1)
            }
        }
        .padding(8)
        .background(Color.white.opacity(isHovered ? 0.16 : 0.035))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(panelInk.opacity(0.12))
                .frame(height: 1)
                .mask { Rectangle().stroke(style: StrokeStyle(lineWidth: 1, dash: [1.5, 3])) }
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .opacity(isDragging ? 0.35 : 1.0)
        .scaleEffect(isHovered && !reduceMotion ? 1.012 : 1)
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.025), radius: isHovered ? 7 : 2, y: 2)
        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78), value: isDragging)
        .onHover { isHovered in
            hoveredItemId = isHovered ? item.id : nil
        }
        // Click to view & edit details
        .onTapGesture {
            openEditView(for: item)
        }
        // Native Drag Support
        .onDrag {
            notesService.draggingItemId = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
    }

    private func focusTask(_ item: MeetingItem) {
        guard item.type == .actionItem, !item.isCompleted else { return }
        selectedFocusTaskID = item.id
        guard !timerService.session.hasSession else { return }
        timerService.start(mode: .pomodoro, minutes: focusMinutes)
    }
    
    // MARK: - Card Detail & Edit View (Smooth Slide-In)
    
    private func cardDetailView(item: MeetingItem) -> some View {
        let column = currentColumn(for: editCardType, isCompleted: editCardCompleted)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(editCardType == .actionItem ? "Edit task" : "Edit note")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(panelInk)
                Spacer()
                Label(item.formattedTime, systemImage: "clock")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(panelInk.opacity(0.58))
                    .padding(.horizontal, 9)
                    .frame(height: 25)
                    .background(Color.white.opacity(0.36), in: Capsule())
            }

            HStack(spacing: 4) {
                ForEach(MeetingKanbanColumn.allCases) { destination in
                    let selected = column == destination
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78)) {
                            selectColumn(destination)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: destination.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(destination.rawValue)
                                .font(.system(size: 10, weight: selected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(selected ? Color.white : panelInk.opacity(0.66))
                        .frame(maxWidth: .infinity, minHeight: 29)
                        .background(selected ? panelInk.opacity(0.84) : Color.white.opacity(0.23),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(panelInk.opacity(0.055), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 9) {
                if editCardType == .actionItem {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.7)) {
                            editCardCompleted.toggle()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(editCardCompleted ? panelInk : Color.white.opacity(0.42))
                                .frame(width: 21, height: 21)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(panelInk.opacity(0.32), lineWidth: 1)
                                }
                            if editCardCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 28, height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(editCardCompleted ? "Mark incomplete" : "Mark completed")
                }

                TextField("Task or note title", text: $editCardTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(panelInk)
                    .padding(.horizontal, 11)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("Notes and details", systemImage: "text.alignleft")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(panelInk.opacity(0.68))
                ZStack(alignment: .topLeading) {
                    if editCardDetails.isEmpty {
                        Text("Add meeting notes, agenda details, links, or action items…")
                            .font(.system(size: 11))
                            .foregroundStyle(panelInk.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $editCardDetails)
                        .font(.system(size: 11))
                        .lineSpacing(3)
                        .foregroundStyle(panelInk.opacity(0.92))
                        .padding(5)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .frame(height: 80)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.38), lineWidth: 0.8)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(panelBackground(panelTint(column)))
        .onExitCommand {
            saveAndDismissEdit()
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func currentColumn(for type: MeetingItemType, isCompleted: Bool) -> MeetingKanbanColumn {
        if type == .actionItem && isCompleted {
            return .done
        } else if type == .note {
            return .notes
        } else {
            return .todo
        }
    }
    
    private func selectColumn(_ column: MeetingKanbanColumn) {
        switch column {
        case .todo:
            editCardType = .actionItem
            editCardCompleted = false
        case .notes:
            editCardType = .note
            editCardCompleted = false
        case .done:
            editCardType = .actionItem
            editCardCompleted = true
        }
    }
    
    private func handleDrop(providers: [NSItemProvider], targetColumn: MeetingKanbanColumn) -> Bool {
        let draggedId = notesService.draggingItemId
        if let draggedId {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                notesService.moveItem(draggedId, to: targetColumn)
                notesService.draggingItemId = nil
                targetedColumn = nil
            }
            return true
        }
        
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: String.self) { string, _ in
            guard let uuidString = string, let uuid = UUID(uuidString: uuidString) else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                    notesService.moveItem(uuid, to: targetColumn)
                    targetedColumn = nil
                }
            }
        }
        return true
    }
    
    private func openEditView(for item: MeetingItem) {
        saveNotepadDraft()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            editCardTitle = item.title
            editCardDetails = item.details
            editCardType = item.type
            editCardCompleted = item.isCompleted
            editingItem = item
        }
    }
    
    private func saveAndDismissEdit() {
        guard let item = editingItem else { return }
        var title = editCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            title = item.title.isEmpty ? "Untitled Note" : item.title
        }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            notesService.updateItem(
                id: item.id,
                title: title,
                details: editCardDetails,
                type: editCardType,
                isCompleted: editCardCompleted
            )
            editingItem = nil
        }
    }
    
    private func submitItem() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
            notesService.addItem(text: text)
            inputText = ""
        }
    }
    
    private func commitTitleEdit() {
        let clean = titleEditBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty {
            notesService.renameMeeting(to: clean)
        }
        isEditingTitle = false
    }

    private func closeToFeatureList() {
        saveNotepadDraft()
        if !service.showingSections {
            service.toggleSections()
        }
    }
}

private struct FocusDotMatrixClock: View {
    let value: String
    private let ink = Color(red: 0.3, green: 0.27, blue: 0.48)
    private let digitWidth: CGFloat = 29
    private let colonWidth: CGFloat = 10
    private let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            let naturalWidth = value.reduce(CGFloat.zero) { $0 + ($1 == ":" ? colonWidth : digitWidth) }
                + CGFloat(max(0, value.count - 1)) * spacing
            HStack(spacing: spacing) {
                ForEach(Array(value.enumerated()), id: \.offset) { _, character in
                    let rows = Self.pattern(for: character)
                    Canvas { context, size in
                        let cellWidth = size.width / 5
                        let cellHeight = size.height / 7
                        let diameter = min(cellWidth, cellHeight) * 0.62
                        for (rowIndex, row) in rows.enumerated() {
                            for (columnIndex, pixel) in row.enumerated() where pixel == "1" {
                                let rect = CGRect(x: CGFloat(columnIndex) * cellWidth + (cellWidth - diameter) / 2,
                                                  y: CGFloat(rowIndex) * cellHeight + (cellHeight - diameter) / 2,
                                                  width: diameter, height: diameter)
                                context.fill(Path(ellipseIn: rect), with: .color(ink))
                            }
                        }
                    }
                    .frame(width: character == ":" ? colonWidth : digitWidth, height: 43)
                    .accessibilityHidden(true)
                }
            }
            .frame(width: naturalWidth, height: geometry.size.height, alignment: .center)
            .scaleEffect(min(1, geometry.size.width / max(1, naturalWidth)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 43)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value)
        .animation(.easeInOut(duration: 0.12), value: value)
    }

    private static func pattern(for character: Character) -> [String] {
        switch character {
        case "0": return ["01110", "10001", "10011", "10101", "11001", "10001", "01110"]
        case "1": return ["00100", "01100", "00100", "00100", "00100", "00100", "01110"]
        case "2": return ["01110", "10001", "00001", "00010", "00100", "01000", "11111"]
        case "3": return ["11110", "00001", "00001", "01110", "00001", "00001", "11110"]
        case "4": return ["00010", "00110", "01010", "10010", "11111", "00010", "00010"]
        case "5": return ["11111", "10000", "10000", "11110", "00001", "00001", "11110"]
        case "6": return ["01110", "10000", "10000", "11110", "10001", "10001", "01110"]
        case "7": return ["11111", "00001", "00010", "00100", "01000", "01000", "01000"]
        case "8": return ["01110", "10001", "10001", "01110", "10001", "10001", "01110"]
        case "9": return ["01110", "10001", "10001", "01111", "00001", "00001", "01110"]
        case ":": return ["00000", "00000", "00100", "00000", "00000", "00100", "00000"]
        default: return Array(repeating: "00000", count: 7)
        }
    }
}

private struct MeetingNotesHoverButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.48 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.86 : 1) : 0.48)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : isHovered ? 1.015 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.76),
                       value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

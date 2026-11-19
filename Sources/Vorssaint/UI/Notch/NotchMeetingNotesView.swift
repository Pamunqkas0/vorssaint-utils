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
    
    @State private var inputText: String = ""
    @State private var isEditingTitle: Bool = false
    @State private var titleEditBuffer: String = ""
    @State private var copiedFeedback: Bool = false
    @State private var hoveredItemId: UUID? = nil
    
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
                headerTrailing
            }
        })
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: editingItem != nil)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: showingBoardsManager)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: activeSession.items)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: notesService.allMeetings.count)
    }
    
    // MARK: - Board View (Kanban)
    
    private var boardView: some View {
        VStack(spacing: 8) {
            // Quick Add Input Bar
            inputBar
            
            // Trello-style Horizontal Kanban Board with Drag & Drop
            trelloBoard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
    
    // MARK: - Board Header (Top Row)
    
    private var headerLeading: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .teal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
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
        }
    }
    
    private var headerTrailing: some View {
        HStack(spacing: 6) {
            // Copy Notes Button
            Button {
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
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        notesService.startNewMeeting(title: "New Meeting")
                    }
                } label: {
                    Label(strings.newMeeting, systemImage: "plus.circle")
                }
                
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        notesService.duplicateCurrentMeeting()
                    }
                } label: {
                    Label("Duplicate Current Board", systemImage: "plus.square.on.square")
                }
                
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        showingBoardsManager = true
                    }
                } label: {
                    Label("Manage All Boards...", systemImage: "square.grid.2x2")
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
                        
                        Button {
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
                                                .foregroundStyle(.green)
                                        }
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15), in: Capsule())
                                    } else {
                                        Text(session.formattedDate)
                                            .font(.system(size: 8.5)).monospacedDigit()
                                            .foregroundStyle(.white.opacity(0.35))
                                    }
                                    
                                    Spacer()
                                    
                                    if notesService.allMeetings.count > 1 {
                                        Button {
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
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                
                                // Stats
                                HStack(spacing: 8) {
                                    HStack(spacing: 3) {
                                        Image(systemName: "checklist")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.orange)
                                        Text("\(session.completedCount)/\(session.totalActionItems)")
                                            .font(.system(size: 10)).monospacedDigit()
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                    
                                    HStack(spacing: 3) {
                                        Image(systemName: "note.text")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.cyan)
                                        Text("\(session.totalNotes)")
                                            .font(.system(size: 10)).monospacedDigit()
                                            .foregroundStyle(.white.opacity(0.7))
                                    }
                                }
                                
                                Spacer(minLength: 0)
                                
                                // Progress bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(Color.white.opacity(0.08))
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
                                    .fill(isActive ? Color.white.opacity(0.09) : Color.white.opacity(0.04))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(isActive ? Color.cyan.opacity(0.6) : Color.white.opacity(0.08), lineWidth: isActive ? 1.5 : 0.8)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Add new board card
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            notesService.startNewMeeting(title: "New Meeting")
                            showingBoardsManager = false
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.cyan)
                            Text("New Board")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .frame(width: 120, height: 105)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 11))
                        )
                    }
                    .buttonStyle(.plain)
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
            .buttonStyle(.plain)
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
                    .foregroundStyle(notesService.quickInputType == .actionItem ? .orange : .white.opacity(0.4))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(notesService.quickInputType == .actionItem ? Color.orange.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
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
                    .foregroundStyle(notesService.quickInputType == .note ? .cyan : .white.opacity(0.4))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(notesService.quickInputType == .note ? Color.cyan.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
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
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(notesService.quickInputType == .actionItem ? Color.orange.opacity(0.3) : Color.cyan.opacity(0.3), lineWidth: 0.8)
            )
            
            // Submit Button
            Button {
                submitItem()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.2) : (notesService.quickInputType == .actionItem ? Color.orange : Color.cyan))
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Trello Horizontal Kanban Board
    
    private var trelloBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                // Column 1: To-Do (Pending Action Items)
                kanbanColumn(
                    column: .todo,
                    title: "To-Do",
                    icon: "checklist",
                    accentColor: .orange,
                    count: activeSession.pendingToDos.count,
                    items: activeSession.pendingToDos,
                    emptyMessage: "All caught up! Drag cards here or add a new task."
                )
                
                // Column 2: Meeting Notes (Notes & Decisions)
                kanbanColumn(
                    column: .notes,
                    title: "Notes & Decisions",
                    icon: "note.text",
                    accentColor: .cyan,
                    count: activeSession.notesList.count,
                    items: activeSession.notesList,
                    emptyMessage: "No meeting notes recorded yet."
                )
                
                // Column 3: Completed (Finished Tasks)
                kanbanColumn(
                    column: .done,
                    title: "Done",
                    icon: "checkmark.circle.fill",
                    accentColor: .green,
                    count: activeSession.completedToDos.count,
                    items: activeSession.completedToDos,
                    emptyMessage: "Drop finished tasks here or check them off.",
                    showsClearButton: true
                )
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
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
        showsClearButton: Bool = false
    ) -> some View {
        let isTargeted = targetedColumn == column
        
        return VStack(spacing: 6) {
            // Column Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor)
                
                Text(title)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                
                Text("\(count)")
                    .font(.system(size: 9.5, weight: .bold)).monospacedDigit()
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(accentColor.opacity(0.18), in: Capsule())
                
                Spacer()
                
                if showsClearButton && count > 0 {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            notesService.clearCompleted()
                        }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06), in: Capsule())
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
                                .foregroundStyle(.white.opacity(0.35))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 16)
                        }
                        .frame(maxWidth: .infinity)
                        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
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
        .frame(width: 235)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? accentColor.opacity(0.12) : Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isTargeted ? accentColor : Color.white.opacity(0.08), lineWidth: isTargeted ? 1.5 : 1)
                )
        )
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isTargeted)
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
                            .fill(item.isCompleted ? Color.green : Color.white.opacity(0.08))
                            .frame(width: 17, height: 17)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(item.isCompleted ? Color.green : Color.white.opacity(0.4), lineWidth: 1.2)
                            )
                        
                        if item.isCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.isCompleted ? "Mark incomplete" : "Mark completed")
            } else {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 6, height: 6)
                    .padding(.top, 6)
                    .padding(.leading, 6)
            }
            
            // Content & Footer (Click to open edit view)
            VStack(alignment: .leading, spacing: 3) {
                // Card Title
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .strikethrough(item.isCompleted, color: .white.opacity(0.4))
                    .foregroundStyle(item.isCompleted ? .white.opacity(0.4) : .white.opacity(0.95))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Description Excerpt if present
                if !item.details.isEmpty {
                    Text(item.details)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // Meta row: time, note indicator, and hover action buttons
                HStack(spacing: 5) {
                    if !item.details.isEmpty {
                        Image(systemName: "doc.text")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    
                    Text(item.formattedTime)
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Spacer()
                    
                    if isHovered {
                        // Pencil edit hint icon
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                        
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
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.09 : 0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(isHovered ? 0.18 : 0.08), lineWidth: 0.8)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .opacity(isDragging ? 0.35 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
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
    
    // MARK: - Card Detail & Edit View (Smooth Slide-In)
    
    private func cardDetailView(item: MeetingItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Column Selector & Status Row
            HStack(spacing: 8) {
                // Segmented Column Switcher
                HStack(spacing: 2) {
                    ForEach(MeetingKanbanColumn.allCases) { col in
                        let isSelected = currentColumn(for: editCardType, isCompleted: editCardCompleted) == col
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectColumn(col)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: col.icon)
                                    .font(.system(size: 9.5))
                                Text(col.rawValue)
                                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium))
                            }
                            .foregroundStyle(isSelected ? col.accentColor : .white.opacity(0.4))
                            .padding(.horizontal, 7)
                            .frame(height: 24)
                            .background(isSelected ? col.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                
                Spacer()
                
                // Timestamp
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 9))
                    Text(item.formattedTime)
                        .font(.system(size: 9.5)).monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.35))
            }
            
            // Title Input Row (with interactive checkbox if actionItem)
            HStack(spacing: 8) {
                if editCardType == .actionItem {
                    Button {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
                            editCardCompleted.toggle()
                        }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(editCardCompleted ? Color.green : Color.white.opacity(0.08))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(editCardCompleted ? Color.green : Color.white.opacity(0.35), lineWidth: 1.2)
                                )
                            if editCardCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10.5, weight: .black))
                                    .foregroundStyle(.black)
                            }
                        }
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(editCardCompleted ? "Mark incomplete" : "Mark completed")
                }
                
                TextField("Task or Note title...", text: $editCardTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            }
            
            // Multiline Description Editor
            ZStack(alignment: .topLeading) {
                if editCardDetails.isEmpty {
                    Text("Add meeting notes, agenda details, links, or action items...")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $editCardDetails)
                    .font(.system(size: 11.5))
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(6)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                    )
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

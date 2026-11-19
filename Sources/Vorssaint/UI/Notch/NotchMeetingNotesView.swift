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
    
    // Card Detail & Edit Modal State
    @State private var editingItem: MeetingItem? = nil
    @State private var editCardTitle: String = ""
    @State private var editCardDetails: String = ""
    @State private var editCardType: MeetingItemType = .actionItem
    @State private var editCardCompleted: Bool = false
    
    private var strings: MeetingNotesStrings {
        FeatureStrings.meetingNotes(l10n.language)
    }
    
    private var activeSession: MeetingSession {
        notesService.document.activeMeeting
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                // Quick Add Input Bar
                inputBar
                
                // Trello-style Horizontal Kanban Board with Drag & Drop
                trelloBoard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .notchBand(leading: {
                headerLeading
            }, trailing: {
                headerTrailing
            })
            
            // Detail & Edit Modal Overlay
            if let editing = editingItem {
                cardEditModal(item: editing)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeSession.items)
        .animation(.smooth(duration: 0.22), value: editingItem != nil)
    }
    
    // MARK: - Header (Top Bar)
    
    private var headerLeading: some View {
        HStack(spacing: 8) {
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
                .frame(maxWidth: 180)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Button {
                    titleEditBuffer = activeSession.title
                    isEditingTitle = true
                } label: {
                    HStack(spacing: 4) {
                        Text(activeSession.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .buttonStyle(.plain)
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
                Button {
                    notesService.startNewMeeting(title: "New Meeting")
                } label: {
                    Label(strings.newMeeting, systemImage: "plus.circle")
                }
                
                if activeSession.completedCount > 0 {
                    Button {
                        withAnimation { notesService.clearCompleted() }
                    } label: {
                        Label(strings.clearCompleted, systemImage: "checkmark.circle.badge.xmark")
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
    
    // MARK: - Quick Input Bar
    
    private var inputBar: some View {
        HStack(spacing: 6) {
            // Target Column Selector
            HStack(spacing: 2) {
                Button {
                    notesService.quickInputType = .actionItem
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("To-Do")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(notesService.quickInputType == .actionItem ? .orange : .white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(notesService.quickInputType == .actionItem ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                
                Button {
                    notesService.quickInputType = .note
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 11))
                        Text("Note")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(notesService.quickInputType == .note ? .cyan : .white.opacity(0.4))
                    .padding(.horizontal, 6)
                    .frame(height: 24)
                    .background(notesService.quickInputType == .note ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(2)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            
            // Input TextField
            TextField(notesService.quickInputType == .actionItem ? "Add task to To-Do board (Press ↵)..." : "Add note to Notes board (Press ↵)...", text: $inputText, onCommit: {
                submitItem()
            })
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(notesService.quickInputType == .actionItem ? Color.orange.opacity(0.35) : Color.cyan.opacity(0.35), lineWidth: 0.8)
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
            HStack(alignment: .top, spacing: 12) {
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
                        withAnimation { notesService.clearCompleted() }
                    } label: {
                        Text("Clear")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
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
                .fill(isTargeted ? accentColor.opacity(0.12) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isTargeted ? accentColor : Color.white.opacity(0.08), lineWidth: isTargeted ? 1.5 : 1)
                )
        )
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
        HStack(alignment: .top, spacing: 8) {
            // Interactive Checkbox / Note Dot
            if item.type == .actionItem {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
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
            
            // Content & Footer (Click to open edit modal)
            VStack(alignment: .leading, spacing: 4) {
                // Card Title
                Text(item.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .strikethrough(item.isCompleted, color: .white.opacity(0.4))
                    .foregroundStyle(item.isCompleted ? .white.opacity(0.4) : .white.opacity(0.95))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Description Excerpt if present
                if !item.details.isEmpty {
                    Text(item.details)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                HStack(spacing: 6) {
                    if !item.details.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    
                    Text(item.formattedTime)
                        .font(.system(size: 9)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.3))
                    
                    Spacer()
                    
                    // Delete Button on Hover
                    if hoveredItemId == item.id {
                        Button {
                            withAnimation(.smooth(duration: 0.2)) {
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
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(hoveredItemId == item.id ? 0.09 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(hoveredItemId == item.id ? 0.18 : 0.1), lineWidth: 0.8)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 9))
        .onHover { isHovered in
            hoveredItemId = isHovered ? item.id : nil
        }
        // Click to view & edit details
        .onTapGesture {
            openEditModal(for: item)
        }
        // Native Drag Support
        .onDrag {
            notesService.draggingItemId = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
    }
    
    // MARK: - Card Detail & Edit Modal
    
    private func cardEditModal(item: MeetingItem) -> some View {
        ZStack {
            // Semi-transparent Backdrop
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissEditModal()
                }
            
            // Modal Card Container
            VStack(alignment: .leading, spacing: 12) {
                // Modal Header
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: editCardType == .actionItem ? "checklist" : "note.text")
                            .foregroundStyle(editCardType == .actionItem ? Color.orange : Color.cyan)
                        Text(editCardType == .actionItem ? "Edit Task" : "Edit Note")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    
                    Spacer()
                    
                    // Column Type Switcher
                    HStack(spacing: 2) {
                        Button {
                            editCardType = .actionItem
                        } label: {
                            Text("To-Do")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(editCardType == .actionItem ? .orange : .white.opacity(0.4))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(editCardType == .actionItem ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        
                        Button {
                            editCardType = .note
                        } label: {
                            Text("Note")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(editCardType == .note ? .cyan : .white.opacity(0.4))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(editCardType == .note ? Color.white.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    
                    Button {
                        dismissEditModal()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                
                // Title Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("TITLE")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                    
                    TextField("Card title...", text: $editCardTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                }
                
                // Description Field
                VStack(alignment: .leading, spacing: 4) {
                    Text("DESCRIPTION & NOTES")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                    
                    TextEditor(text: $editCardDetails)
                        .font(.system(size: 11.5))
                        .lineSpacing(2)
                        .foregroundStyle(.white)
                        .padding(6)
                        .frame(minHeight: 80, maxHeight: 110)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                }
                
                // Modal Footer Actions
                HStack {
                    if editCardType == .actionItem {
                        Button {
                            editCardCompleted.toggle()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: editCardCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(editCardCompleted ? .green : .white.opacity(0.5))
                                Text(editCardCompleted ? "Completed" : "Mark as Done")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    Button {
                        withAnimation {
                            notesService.deleteItem(item.id)
                            dismissEditModal()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        saveCardEdit(for: item)
                    } label: {
                        Text("Save Changes")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Color.cyan, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(editCardTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
            .padding(14)
            .frame(width: 380)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 20, x: 0, y: 10)
            )
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func handleDrop(providers: [NSItemProvider], targetColumn: MeetingKanbanColumn) -> Bool {
        let draggedId = notesService.draggingItemId
        if let draggedId {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    notesService.moveItem(uuid, to: targetColumn)
                    targetedColumn = nil
                }
            }
        }
        return true
    }
    
    private func openEditModal(for item: MeetingItem) {
        editCardTitle = item.title
        editCardDetails = item.details
        editCardType = item.type
        editCardCompleted = item.isCompleted
        editingItem = item
    }
    
    private func dismissEditModal() {
        editingItem = nil
    }
    
    private func saveCardEdit(for item: MeetingItem) {
        let title = editCardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        withAnimation(.smooth(duration: 0.2)) {
            notesService.updateItem(
                id: item.id,
                title: title,
                details: editCardDetails,
                type: editCardType,
                isCompleted: editCardCompleted
            )
            dismissEditModal()
        }
    }
    
    private func submitItem() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.smooth(duration: 0.2)) {
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

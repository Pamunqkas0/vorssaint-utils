// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

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
    
    private var strings: MeetingNotesStrings {
        FeatureStrings.meetingNotes(l10n.language)
    }
    
    private var activeSession: MeetingSession {
        notesService.document.activeMeeting
    }
    
    private var filteredItems: [MeetingItem] {
        let items = activeSession.items
        switch notesService.selectedFilter {
        case .all:
            return items
        case .todos:
            return items.filter { $0.type == .actionItem }
        case .notes:
            return items.filter { $0.type == .note }
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Quick Add Input Bar
            inputBar
            
            // Meeting Items List
            if filteredItems.isEmpty {
                emptyStateView
            } else {
                itemsScrollView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 2)
        .padding(.top, 4)
        .notchBand(leading: {
            headerLeading
        }, trailing: {
            headerTrailing
        })
        .animation(.smooth(duration: 0.28), value: notesService.isCompactMode)
        .animation(.smooth(duration: 0.22), value: notesService.selectedFilter)
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
            
            // Progress Badge
            if activeSession.hasTasks {
                HStack(spacing: 4) {
                    Circle()
                        .fill(activeSession.completedCount == activeSession.totalActionItems ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text("\(activeSession.completedCount)/\(activeSession.totalActionItems)")
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
            // Compact / Expand Toggle
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    notesService.isCompactMode.toggle()
                }
            } label: {
                Image(systemName: notesService.isCompactMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(notesService.isCompactMode ? 0.15 : 0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(notesService.isCompactMode ? strings.expandMode : strings.compactMode)
            
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
            // Type Toggle: [✓ To-Do] [• Note]
            HStack(spacing: 2) {
                Button {
                    notesService.quickInputType = .actionItem
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(notesService.quickInputType == .actionItem ? .orange : .white.opacity(0.4))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(strings.todo)
                
                Button {
                    notesService.quickInputType = .note
                } label: {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 11))
                        .foregroundStyle(notesService.quickInputType == .note ? .cyan : .white.opacity(0.4))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(strings.note)
            }
            .padding(.horizontal, 4)
            .frame(height: 28)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            
            // Input TextField
            TextField(notesService.quickInputType == .actionItem ? "Add to-do task (↵)..." : "Add meeting note (↵)...", text: $inputText, onCommit: {
                submitItem()
            })
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(notesService.quickInputType == .actionItem ? Color.orange.opacity(0.3) : Color.cyan.opacity(0.3), lineWidth: 0.8)
            )
            
            // Submit Button
            Button {
                submitItem()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.2) : (notesService.quickInputType == .actionItem ? Color.orange : Color.cyan))
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Items List
    
    private var itemsScrollView: some View {
        VStack(spacing: 4) {
            // Filter Selector (In expanded mode)
            if !notesService.isCompactMode {
                HStack(spacing: 8) {
                    ForEach(MeetingItemFilter.allCases) { filter in
                        Button {
                            notesService.selectedFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.system(size: 10, weight: notesService.selectedFilter == filter ? .semibold : .regular))
                                .foregroundStyle(notesService.selectedFilter == filter ? .white : .white.opacity(0.5))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(notesService.selectedFilter == filter ? Color.white.opacity(0.16) : Color.clear, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }
            
            ScrollView(.vertical) {
                LazyVStack(spacing: 4) {
                    ForEach(filteredItems) { item in
                        itemRow(item)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.automatic)
        }
    }
    
    private func itemRow(_ item: MeetingItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Checkbox for action items or Bullet for notes
            if item.type == .actionItem {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        notesService.toggleItem(item.id)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(item.isCompleted ? Color.green : Color.white.opacity(0.35), lineWidth: 1.4)
                            .frame(width: 15, height: 15)
                        if item.isCompleted {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 15, height: 15)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                Circle()
                    .fill(Color.cyan)
                    .frame(width: 5, height: 5)
                    .padding(.top, 6)
                    .padding(.horizontal, 5)
            }
            
            // Item text
            Text(item.text)
                .font(.system(size: 12))
                .strikethrough(item.isCompleted, color: .white.opacity(0.4))
                .foregroundStyle(item.isCompleted ? .white.opacity(0.4) : .white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Timestamp
            Text(item.formattedTime)
                .font(.system(size: 9.5)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.3))
                .padding(.top, 2)
            
            // Delete button (visible on hover)
            if hoveredItemId == item.id {
                Button {
                    withAnimation(.smooth(duration: 0.2)) {
                        notesService.deleteItem(item.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredItemId == item.id ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
        )
        .onHover { isHovered in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredItemId = isHovered ? item.id : nil
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 6) {
            Spacer()
            Image(systemName: "pencil.and.list.clipboard")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.25))
            Text(strings.emptyTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Text(strings.emptySubtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    
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

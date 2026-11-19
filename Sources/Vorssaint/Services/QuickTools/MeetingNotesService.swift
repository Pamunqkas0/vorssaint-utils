// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

final class MeetingNotesService: ObservableObject {
    static let shared = MeetingNotesService()
    
    @Published private(set) var document: MeetingNotesDocument
    @Published var isCompactMode: Bool {
        didSet {
            UserDefaults.standard.set(isCompactMode, forKey: DefaultsKey.meetingNotesCompact)
        }
    }
    @Published var selectedFilter: MeetingItemFilter = .all
    @Published var quickInputType: MeetingItemType = .actionItem
    
    private let store: MeetingNotesStore
    
    private init() {
        let store = MeetingNotesStore()
        self.store = store
        self.document = store.load()
        self.isCompactMode = UserDefaults.standard.bool(forKey: DefaultsKey.meetingNotesCompact)
    }
    
    // MARK: - Items Management
    
    func addItem(text: String, type: MeetingItemType? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let itemType = type ?? quickInputType
        let newItem = MeetingItem(text: trimmed, type: itemType)
        
        // Insert at beginning of items
        document.activeMeeting.items.insert(newItem, at: 0)
        persist()
    }
    
    func toggleItem(_ id: UUID) {
        guard let index = document.activeMeeting.items.firstIndex(where: { $0.id == id }) else { return }
        document.activeMeeting.items[index].isCompleted.toggle()
        persist()
    }
    
    func deleteItem(_ id: UUID) {
        document.activeMeeting.items.removeAll { $0.id == id }
        persist()
    }
    
    func updateItemText(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = document.activeMeeting.items.firstIndex(where: { $0.id == id }) else { return }
        document.activeMeeting.items[index].text = trimmed
        persist()
    }
    
    func clearCompleted() {
        document.activeMeeting.items.removeAll { $0.type == .actionItem && $0.isCompleted }
        persist()
    }
    
    // MARK: - Meeting Session Management
    
    func startNewMeeting(title: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? "New Meeting" : cleanTitle
        
        // Archive current meeting if it has content
        if !document.activeMeeting.items.isEmpty {
            document.pastMeetings.insert(document.activeMeeting, at: 0)
        }
        
        document.activeMeeting = MeetingSession(title: finalTitle)
        persist()
    }
    
    func renameMeeting(to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        document.activeMeeting.title = clean
        persist()
    }
    
    // MARK: - Export & Clipboard
    
    @discardableResult
    func copyNotesToClipboard() -> Bool {
        let session = document.activeMeeting
        var markdown = "# \(session.title)\n"
        markdown += "*Date: \(session.formattedDate)*\n\n"
        
        let todos = session.items.filter { $0.type == .actionItem }
        if !todos.isEmpty {
            markdown += "## Action Items / Tasks:\n"
            for item in todos {
                let box = item.isCompleted ? "[x]" : "[ ]"
                markdown += "- \(box) \(item.text)\n"
            }
            markdown += "\n"
        }
        
        let notes = session.items.filter { $0.type == .note }
        if !notes.isEmpty {
            markdown += "## Key Notes & Takeaways:\n"
            for item in notes {
                markdown += "- \(item.text)\n"
            }
        }
        
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(markdown, forType: .string)
    }
    
    private func persist() {
        store.save(document)
    }
}

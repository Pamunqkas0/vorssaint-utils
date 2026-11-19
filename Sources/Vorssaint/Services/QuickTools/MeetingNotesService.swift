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
    @Published var draggingItemId: UUID? = nil
    
    private let store: MeetingNotesStore
    
    private init() {
        let store = MeetingNotesStore()
        self.store = store
        self.document = store.load()
        self.isCompactMode = UserDefaults.standard.bool(forKey: DefaultsKey.meetingNotesCompact)
    }
    
    // MARK: - Items Management
    
    func addItem(text: String, details: String = "", type: MeetingItemType? = nil) {
        let trimmedTitle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        
        objectWillChange.send()
        let itemType = type ?? quickInputType
        let newItem = MeetingItem(title: trimmedTitle, details: details.trimmingCharacters(in: .whitespacesAndNewlines), type: itemType)
        
        // Insert at beginning of items
        document.activeMeeting.items.insert(newItem, at: 0)
        persist()
    }
    
    func toggleItem(_ id: UUID) {
        objectWillChange.send()
        guard let index = document.activeMeeting.items.firstIndex(where: { $0.id == id }) else { return }
        document.activeMeeting.items[index].isCompleted.toggle()
        persist()
    }
    
    func moveItem(_ id: UUID, to column: MeetingKanbanColumn) {
        objectWillChange.send()
        guard let index = document.activeMeeting.items.firstIndex(where: { $0.id == id }) else { return }
        switch column {
        case .todo:
            document.activeMeeting.items[index].type = .actionItem
            document.activeMeeting.items[index].isCompleted = false
        case .notes:
            document.activeMeeting.items[index].type = .note
            document.activeMeeting.items[index].isCompleted = false
        case .done:
            document.activeMeeting.items[index].type = .actionItem
            document.activeMeeting.items[index].isCompleted = true
        }
        persist()
    }
    
    func updateItem(id: UUID, title: String, details: String, type: MeetingItemType, isCompleted: Bool) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty,
              let index = document.activeMeeting.items.firstIndex(where: { $0.id == id }) else { return }
        objectWillChange.send()
        document.activeMeeting.items[index].title = cleanTitle
        document.activeMeeting.items[index].details = details.trimmingCharacters(in: .whitespacesAndNewlines)
        document.activeMeeting.items[index].type = type
        document.activeMeeting.items[index].isCompleted = isCompleted
        persist()
    }
    
    func deleteItem(_ id: UUID) {
        objectWillChange.send()
        document.activeMeeting.items.removeAll { $0.id == id }
        persist()
    }
    
    func clearCompleted() {
        objectWillChange.send()
        document.activeMeeting.items.removeAll { $0.type == .actionItem && $0.isCompleted }
        persist()
    }
    
    // MARK: - Meeting Session Management
    
    var allMeetings: [MeetingSession] {
        var list = [document.activeMeeting]
        list.append(contentsOf: document.pastMeetings)
        return list
    }
    
    func startNewMeeting(title: String = "New Meeting") {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? "New Meeting" : cleanTitle
        
        objectWillChange.send()
        // Safely save current active meeting into pastMeetings
        if let existingIdx = document.pastMeetings.firstIndex(where: { $0.id == document.activeMeeting.id }) {
            document.pastMeetings[existingIdx] = document.activeMeeting
        } else {
            document.pastMeetings.insert(document.activeMeeting, at: 0)
        }
        
        document.activeMeeting = MeetingSession(title: finalTitle)
        persist()
    }
    
    func switchToMeeting(id: UUID) {
        guard id != document.activeMeeting.id else { return }
        objectWillChange.send()
        
        // Save current active meeting into pastMeetings
        if let existingIdx = document.pastMeetings.firstIndex(where: { $0.id == document.activeMeeting.id }) {
            document.pastMeetings[existingIdx] = document.activeMeeting
        } else {
            document.pastMeetings.insert(document.activeMeeting, at: 0)
        }
        
        // Make the selected past meeting active
        if let targetIdx = document.pastMeetings.firstIndex(where: { $0.id == id }) {
            let target = document.pastMeetings.remove(at: targetIdx)
            document.activeMeeting = target
        }
        persist()
    }
    
    func deleteMeeting(id: UUID) {
        objectWillChange.send()
        if document.activeMeeting.id == id {
            if !document.pastMeetings.isEmpty {
                document.activeMeeting = document.pastMeetings.removeFirst()
            } else {
                document.activeMeeting = MeetingSession(title: "New Meeting")
            }
        } else {
            document.pastMeetings.removeAll { $0.id == id }
        }
        persist()
    }
    
    func duplicateCurrentMeeting() {
        objectWillChange.send()
        if let idx = document.pastMeetings.firstIndex(where: { $0.id == document.activeMeeting.id }) {
            document.pastMeetings[idx] = document.activeMeeting
        } else {
            document.pastMeetings.insert(document.activeMeeting, at: 0)
        }
        
        var dup = document.activeMeeting
        dup.id = UUID()
        dup.title = "\(document.activeMeeting.title) (Copy)"
        dup.createdAt = Date()
        dup.items = document.activeMeeting.items.map { item in
            var copy = item
            copy.id = UUID()
            return copy
        }
        document.activeMeeting = dup
        persist()
    }
    
    func renameMeeting(to title: String) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        objectWillChange.send()
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
                markdown += "- \(box) **\(item.title)**\n"
                if !item.details.isEmpty {
                    markdown += "  \(item.details.replacingOccurrences(of: "\n", with: "\n  "))\n"
                }
            }
            markdown += "\n"
        }
        
        let notes = session.items.filter { $0.type == .note }
        if !notes.isEmpty {
            markdown += "## Key Notes & Takeaways:\n"
            for item in notes {
                markdown += "- **\(item.title)**\n"
                if !item.details.isEmpty {
                    markdown += "  \(item.details.replacingOccurrences(of: "\n", with: "\n  "))\n"
                }
            }
        }
        
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(markdown, forType: .string)
    }
    
    private func persist() {
        store.save(document)
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MeetingItemType: String, Codable, CaseIterable {
    case actionItem = "actionItem"
    case note = "note"
    
    var symbol: String {
        switch self {
        case .actionItem: return "checkmark.circle"
        case .note: return "text.alignleft"
        }
    }
}

enum MeetingItemFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case todos = "To-Dos"
    case notes = "Notes"
    
    var id: String { rawValue }
}

struct MeetingItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var text: String
    var type: MeetingItemType
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: createdAt)
    }
}

struct MeetingSession: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String = "Meeting Notes"
    var createdAt: Date = Date()
    var items: [MeetingItem] = []
    
    var completedCount: Int {
        items.filter { $0.type == .actionItem && $0.isCompleted }.count
    }
    
    var totalActionItems: Int {
        items.filter { $0.type == .actionItem }.count
    }
    
    var totalNotes: Int {
        items.filter { $0.type == .note }.count
    }
    
    var hasTasks: Bool {
        totalActionItems > 0
    }
    
    var pendingToDos: [MeetingItem] {
        items.filter { $0.type == .actionItem && !$0.isCompleted }
    }
    
    var completedToDos: [MeetingItem] {
        items.filter { $0.type == .actionItem && $0.isCompleted }
    }
    
    var notesList: [MeetingItem] {
        items.filter { $0.type == .note }
    }
    
    var progressFraction: Double {
        totalActionItems == 0 ? 0 : Double(completedCount) / Double(totalActionItems)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    static func defaultSession() -> MeetingSession {
        var session = MeetingSession(title: "Sprint Sync")
        session.items = [
            MeetingItem(text: "Review sprint deliverables and milestones", type: .note),
            MeetingItem(text: "Finalize pull request reviews by 4 PM", type: .actionItem, isCompleted: true),
            MeetingItem(text: "Deploy v3.5 patch to staging environment", type: .actionItem, isCompleted: false),
            MeetingItem(text: "Sync with UX team regarding Dynamic Island animations", type: .actionItem, isCompleted: false)
        ]
        return session
    }
}

struct MeetingNotesDocument: Codable, Equatable {
    var activeMeeting: MeetingSession = MeetingSession.defaultSession()
    var pastMeetings: [MeetingSession] = []
}

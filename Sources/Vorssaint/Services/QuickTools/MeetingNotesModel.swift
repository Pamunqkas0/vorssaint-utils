// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

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

enum MeetingKanbanColumn: String, CaseIterable, Identifiable {
    case todo = "To-Do"
    case notes = "Notes & Decisions"
    case done = "Done"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .todo: return "checklist"
        case .notes: return "note.text"
        case .done: return "checkmark.circle.fill"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .todo: return .orange
        case .notes: return .cyan
        case .done: return .green
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
    var title: String
    var details: String = ""
    var type: MeetingItemType
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    
    // Compatibility accessor
    var text: String {
        get { title }
        set { title = newValue }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, text, details, type, isCompleted, createdAt
    }
    
    init(id: UUID = UUID(), title: String, details: String = "", type: MeetingItemType, isCompleted: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.details = details
        self.type = type
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }
    
    // Convenience init accepting text
    init(text: String, details: String = "", type: MeetingItemType, isCompleted: Bool = false) {
        self.init(id: UUID(), title: text, details: details, type: type, isCompleted: isCompleted, createdAt: Date())
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        if let t = try container.decodeIfPresent(String.self, forKey: .title) {
            self.title = t
        } else if let txt = try container.decodeIfPresent(String.self, forKey: .text) {
            self.title = txt
        } else {
            self.title = ""
        }
        self.details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        self.type = try container.decodeIfPresent(MeetingItemType.self, forKey: .type) ?? .actionItem
        self.isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        self.createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(title, forKey: .text)
        try container.encode(details, forKey: .details)
        try container.encode(type, forKey: .type)
        try container.encode(isCompleted, forKey: .isCompleted)
        try container.encode(createdAt, forKey: .createdAt)
    }
    
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
            MeetingItem(title: "Review sprint deliverables and milestones", details: "Check off all Q4 frontend requirements with the engineering team.", type: .note),
            MeetingItem(title: "Finalize pull request reviews by 4 PM", details: "Review core changes in Notch and Dynamic Island modules.", type: .actionItem, isCompleted: true),
            MeetingItem(title: "Deploy v3.5 patch to staging environment", details: "Run automated build scripts and verify signing keys.", type: .actionItem, isCompleted: false),
            MeetingItem(title: "Sync with UX team regarding Dynamic Island animations", details: "Review spring damping parameters and responsive layouts.", type: .actionItem, isCompleted: false)
        ]
        return session
    }
}

struct MeetingNotesDocument: Codable, Equatable {
    var activeMeeting: MeetingSession = MeetingSession.defaultSession()
    var pastMeetings: [MeetingSession] = []
}

// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MeetingNotesStrings {
    let title: String
    let pageTitle: String
    let hubDescription: String
    let subtitle: String
    let newMeeting: String
    let meetingTitlePlaceholder: String
    let addItemPlaceholder: String
    let todo: String
    let note: String
    let all: String
    let todos: String
    let notes: String
    let clearCompleted: String
    let copyNotes: String
    let copied: String
    let emptyTitle: String
    let emptySubtitle: String
    let progressFormat: String
    let allCompleted: String
    let compactMode: String
    let expandMode: String
    let delete: String
}

extension FeatureStrings {
    static func meetingNotes(_ language: AppLanguage) -> MeetingNotesStrings {
        switch language {
        default:
            return MeetingNotesStrings(
                title: "Meeting Notes",
                pageTitle: "Meeting Notes",
                hubDescription: "Interactive meeting notes, instant bullet points and actionable to-do list in the Dynamic Island.",
                subtitle: "Capture key points, takeaways and to-dos directly from the notch during meetings.",
                newMeeting: "New Meeting",
                meetingTitlePlaceholder: "Meeting Title (e.g. Sprint Sync)...",
                addItemPlaceholder: "Add note or action item (Press ↵)...",
                todo: "To-Do",
                note: "Note",
                all: "All",
                todos: "To-Dos",
                notes: "Notes",
                clearCompleted: "Clear Completed",
                copyNotes: "Copy Notes",
                copied: "Copied!",
                emptyTitle: "No Meeting Items Yet",
                emptySubtitle: "Type a note or to-do above and press Return to add it instantly without leaving your meeting.",
                progressFormat: "%d of %d tasks completed",
                allCompleted: "All tasks completed! 🎉",
                compactMode: "Compact Mode",
                expandMode: "Expanded Mode",
                delete: "Delete"
            )
        }
    }
}

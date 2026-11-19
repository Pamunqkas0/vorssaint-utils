// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MeetingNotesStore {
    let directoryURL: URL?
    let defaults: UserDefaults
    private static let fileName = "MeetingNotes.json"
    
    init(directoryURL: URL? = PrivateFileStore.containerURL, defaults: UserDefaults = .standard) {
        self.directoryURL = directoryURL
        self.defaults = defaults
    }
    
    func load() -> MeetingNotesDocument {
        // 1. Try loading from file
        if let directoryURL {
            let fileURL = directoryURL.appendingPathComponent(Self.fileName)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let data = try? Data(contentsOf: fileURL),
               let decoded = try? JSONDecoder().decode(MeetingNotesDocument.self, from: data) {
                return decoded
            }
        }
        
        // 2. Fallback to UserDefaults
        if let storedData = defaults.data(forKey: DefaultsKey.meetingNotesDocument),
           let decoded = try? JSONDecoder().decode(MeetingNotesDocument.self, from: storedData) {
            return decoded
        }
        
        // 3. Fresh default document
        return MeetingNotesDocument()
    }
    
    @discardableResult
    func save(_ document: MeetingNotesDocument) -> Bool {
        var fileSaved = false
        guard let data = try? JSONEncoder().encode(document) else { return false }
        
        // Save to file
        if let directoryURL {
            _ = PrivateFileStore.createDirectory(at: directoryURL)
            let fileURL = directoryURL.appendingPathComponent(Self.fileName)
            fileSaved = PrivateFileStore.write(data, to: fileURL)
        }
        
        // Keep synced in UserDefaults
        defaults.set(data, forKey: DefaultsKey.meetingNotesDocument)
        return fileSaved
    }
}

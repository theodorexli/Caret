import Foundation
import SwiftUI

struct CaretNote: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let updatedAt: Date
    let apps: [String]
    let body: String
}

struct ActionSkillItem: Identifiable, Equatable {
    let action: CaretAction
    let note: CaretNote?

    var id: String { action.id }
}

enum NoteKind {
    case skill
    case memory
}

enum NoteRepositoryError: Error {
    case invalidTitle
    case writeFailed
}

struct NoteRepository {
    func listSkillNotes() -> [CaretNote] {
        listMarkdownNotes(in: CaretPaths.skillsNotesDir)
    }

    func listMemoryNotes() -> [CaretNote] {
        listMarkdownNotes(in: CaretPaths.memoriesNotesDir)
    }

    func skillNote(for actionID: String) -> CaretNote? {
        let url = CaretPaths.skillsNotesDir.appendingPathComponent("\(actionID).md")
        return loadNote(at: url)
    }

    func skillIcon(actionID: String) -> String {
        if let note = skillNote(for: actionID) { return note.icon }
        return CaretActionIcons.icon(for: actionID)
    }

    @discardableResult
    func ensureSkillNotes(for actions: [CaretAction]) throws -> [String] {
        var created: [String] = []
        for action in actions {
            let url = CaretPaths.skillsNotesDir.appendingPathComponent("\(action.id).md")
            if FileManager.default.fileExists(atPath: url.path) { continue }
            try saveSkillNote(
                actionID: action.id,
                title: action.title,
                icon: CaretActionIcons.icon(for: action.id),
                body: "Instructions for the **\(action.title)** action.\n"
            )
            created.append(action.id)
        }
        return created
    }

    @discardableResult
    func saveSkillNote(
        actionID: String,
        title: String,
        icon: String,
        body: String,
        apps: [String] = []
    ) throws -> CaretNote {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw NoteRepositoryError.invalidTitle }
        let url = CaretPaths.skillsNotesDir.appendingPathComponent("\(actionID).md")
        try writeNote(
            to: url,
            title: trimmedTitle,
            icon: icon.isEmpty ? CaretActionIcons.icon(for: actionID) : icon,
            body: body,
            apps: apps
        )
        guard let note = loadNote(at: url) else { throw NoteRepositoryError.writeFailed }
        return note
    }

    @discardableResult
    func saveMemoryNote(
        noteID: String,
        title: String,
        icon: String,
        body: String,
        apps: [String]
    ) throws -> CaretNote {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw NoteRepositoryError.invalidTitle }
        let slug = NoteRepository.slugify(noteID.isEmpty ? trimmedTitle : noteID)
        let url = CaretPaths.memoriesNotesDir.appendingPathComponent("\(slug).md")
        try writeNote(
            to: url,
            title: trimmedTitle,
            icon: icon.isEmpty ? "tray.full" : icon,
            body: body,
            apps: apps
        )
        guard let note = loadNote(at: url) else { throw NoteRepositoryError.writeFailed }
        return note
    }

    func deleteMemoryNote(id: String) throws {
        let url = CaretPaths.memoriesNotesDir.appendingPathComponent("\(id).md")
        try FileManager.default.removeItem(at: url)
    }

    func deleteSkillNote(actionID: String) throws {
        let url = CaretPaths.skillsNotesDir.appendingPathComponent("\(actionID).md")
        try FileManager.default.removeItem(at: url)
    }

    func makeUniqueSkillActionID(title: String, reservedIDs: Set<String>) -> String {
        var base = Self.slugify(title)
        if base.isEmpty { base = "skill" }
        var candidate = base
        var counter = 2
        while reservedIDs.contains(candidate) || skillNoteExists(actionID: candidate) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }

    private func skillNoteExists(actionID: String) -> Bool {
        FileManager.default.fileExists(
            atPath: CaretPaths.skillsNotesDir.appendingPathComponent("\(actionID).md").path
        )
    }

    func memoryContextItems() -> [MemoryItem] {
        listMemoryNotes().flatMap { note in
            let chunks = note.body
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if chunks.isEmpty {
                return [MemoryItem(id: note.id, text: note.title, sourceApp: note.apps.first)]
            }
            return chunks.enumerated().map { index, line in
                MemoryItem(
                    id: "\(note.id)-\(index)",
                    text: line,
                    sourceApp: note.apps.first
                )
            }
        }
    }

    static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "memory" : collapsed
    }

    private func writeNote(to url: URL, title: String, icon: String, body: String, apps: [String]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let updated = ISO8601DateFormatter.caret.string(from: Date())
        var lines = [
            "---",
            "title: \(title)",
            "icon: \(icon)",
            "updated: \(updated)",
        ]
        if !apps.isEmpty {
            lines.append("apps:")
            lines.append(contentsOf: apps.map { "  - \($0)" })
        }
        lines.append("---")
        lines.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
        lines.append("")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func listMarkdownNotes(in directory: URL) -> [CaretNote] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { loadNote(at: $0) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func loadNote(at url: URL) -> CaretNote? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = Self.parseFrontmatter(text)
        let stem = url.deletingPathExtension().lastPathComponent
        let title = parsed.meta["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false ? title! : Self.titleFromStem(stem))
        let icon = parsed.meta["icon"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedIcon = (icon?.isEmpty == false ? icon! : "doc.text")
        let apps = Self.parseApps(parsed.meta["apps"])
        let updated = Self.parseUpdated(parsed.meta["updated"], fileURL: url)
        return CaretNote(
            id: stem,
            title: resolvedTitle,
            icon: resolvedIcon,
            updatedAt: updated,
            apps: apps,
            body: parsed.body.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func titleFromStem(_ stem: String) -> String {
        stem.split(separator: "-").map { part in
            part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    private static func parseApps(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        if raw.contains("\n") {
            return raw
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        if raw.hasPrefix("[") && raw.hasSuffix("]") {
            let inner = raw.dropFirst().dropLast()
            return inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }.filter { !$0.isEmpty }
        }
        return [raw]
    }

    private static func parseUpdated(_ raw: String?, fileURL: URL) -> Date {
        if let raw, !raw.isEmpty {
            if let date = ISO8601DateFormatter.caret.date(from: raw) { return date }
        }
        if let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
           let modified = values.contentModificationDate {
            return modified
        }
        return .now
    }

    private static func parseFrontmatter(_ text: String) -> (meta: [String: String], body: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---" else { return ([:], text) }
        var meta: [String: String] = [:]
        var index = 1
        var listKey: String?
        while index < lines.count {
            let line = lines[index]
            if line == "---" {
                index += 1
                break
            }
            if line.hasPrefix("  - "), let listKey {
                var items = meta[listKey]?.split(separator: "\n").map(String.init) ?? []
                items.append(String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces))
                meta[listKey] = items.joined(separator: "\n")
                index += 1
                continue
            }
            listKey = nil
            guard let colon = line.firstIndex(of: ":") else {
                index += 1
                continue
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if value.isEmpty {
                listKey = key
                meta[key] = ""
            } else {
                meta[key] = value
            }
            index += 1
        }
        let body = lines.dropFirst(index).joined(separator: "\n")
        return (meta, body)
    }
}

enum CaretActionIcons {
    static let fallback = "sparkle"

    static func icon(for actionID: String) -> String {
        switch actionID {
        case "book-flight": return "airplane"
        case "book-calendar-link": return "calendar"
        case "follow-up": return "envelope"
        case "revise": return "pencil"
        case "summarize": return "list.bullet"
        case "translate": return "character.book.closed"
        case "extract-tasks": return "checklist"
        case "tone-polite": return "hand.wave"
        default: return fallback
        }
    }
}

enum CaretNotePalette {
    static func accent(for key: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.26, green: 0.52, blue: 0.98),
            Color(red: 0.95, green: 0.45, blue: 0.28),
            Color(red: 0.35, green: 0.78, blue: 0.55),
            Color(red: 0.72, green: 0.42, blue: 0.92),
            Color(red: 0.98, green: 0.62, blue: 0.18),
            Color(red: 0.42, green: 0.68, blue: 0.82),
        ]
        let index = abs(key.hashValue) % palette.count
        return palette[index]
    }
}

enum CaretSymbolChoices {
    static let skillIcons = [
        "airplane", "calendar", "envelope", "pencil", "list.bullet",
        "character.book.closed", "checklist", "hand.wave", "sparkles", "wand.and.stars",
    ]
    static let memoryIcons = [
        "tray.full", "person.crop.circle", "macwindow.on.rectangle", "heart.text.square",
        "brain.head.profile", "clock.arrow.circlepath",
    ]
}

private extension ISO8601DateFormatter {
    static let caret: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

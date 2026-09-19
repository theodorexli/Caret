import Foundation

struct CaretNote: Identifiable, Equatable {
    let id: String
    let title: String
    let icon: String
    let updatedAt: Date
    let apps: [String]
    let body: String
}

struct NoteRepository {
    static var notesRoot: URL? {
        CaretPaths.projectRoot?.appendingPathComponent("caret/notes", isDirectory: true)
    }

    static var skillsNotesDir: URL? {
        notesRoot?.appendingPathComponent("skills", isDirectory: true)
    }

    static var memoriesNotesDir: URL? {
        notesRoot?.appendingPathComponent("memories", isDirectory: true)
    }

    func listSkillNotes() -> [CaretNote] {
        listMarkdownNotes(in: Self.skillsNotesDir)
    }

    func listMemoryNotes() -> [CaretNote] {
        listMarkdownNotes(in: Self.memoriesNotesDir)
    }

    func skillIcon(actionID: String) -> String {
        guard let dir = Self.skillsNotesDir else { return CaretActionIcons.fallback }
        let url = dir.appendingPathComponent("\(actionID).md")
        guard let note = loadNote(at: url) else { return CaretActionIcons.icon(for: actionID) }
        return note.icon
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

    private func listMarkdownNotes(in directory: URL?) -> [CaretNote] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

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
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: raw) { return date }
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

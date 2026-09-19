import Foundation

struct CaretSkill: Identifiable, Equatable, Codable {
    let id: String
    let actionID: String
    let name: String
    let description: String

    enum CodingKeys: String, CodingKey {
        case id
        case actionID = "action_id"
        case name
        case description
    }
}

struct SkillRepository {
    func listActionIDs() -> [String] {
        guard let root = CaretPaths.skillsRoot,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else { return [] }

        return entries
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map(\.lastPathComponent)
            .sorted()
    }

    static func displayTitle(actionID: String) -> String {
        actionID
            .split(separator: "-")
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
    }

    func list(actionID: String) -> [CaretSkill] {
        guard let actionDir = CaretPaths.skillsRoot?.appendingPathComponent(actionID, isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(
                  at: actionDir,
                  includingPropertiesForKeys: nil
              )
        else { return [] }

        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.deletingPathExtension().lastPathComponent < $1.deletingPathExtension().lastPathComponent }
            .compactMap { loadSkill(at: $0, actionID: actionID) }
    }

    func filter(actionID: String, query: String) -> [CaretSkill] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let skills = list(actionID: actionID)
        guard !needle.isEmpty else { return skills }
        return skills.filter {
            $0.name.lowercased().contains(needle) || $0.description.lowercased().contains(needle)
        }
    }

    @discardableResult
    func create(actionID: String, name: String, description: String = "") throws -> CaretSkill {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw SkillRepositoryError.emptyName }
        guard let root = CaretPaths.skillsRoot else { throw SkillRepositoryError.missingSkillsRoot }

        let actionDir = root.appendingPathComponent(actionID, isDirectory: true)
        try FileManager.default.createDirectory(at: actionDir, withIntermediateDirectories: true)

        var slug = SkillRepository.slugify(title)
        var destination = actionDir.appendingPathComponent("\(slug).json")
        var counter = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            slug = "\(SkillRepository.slugify(title))-\(counter)"
            destination = actionDir.appendingPathComponent("\(slug).json")
            counter += 1
        }

        let payload: [String: String] = [
            "name": title,
            "description": description.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: destination)
        guard let skill = loadSkill(at: destination, actionID: actionID) else {
            throw SkillRepositoryError.invalidPayload
        }
        return skill
    }

    private func loadSkill(at url: URL, actionID: String) -> CaretSkill? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = object["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let description = (object["description"] as? String) ?? ""
        return CaretSkill(
            id: url.deletingPathExtension().lastPathComponent,
            actionID: actionID,
            name: name,
            description: description
        )
    }

    static func slugify(_ text: String) -> String {
        let lowered = text.lowercased()
        let allowed = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "skill" : collapsed
    }
}

enum SkillRepositoryError: Error {
    case emptyName
    case missingSkillsRoot
    case invalidPayload
}

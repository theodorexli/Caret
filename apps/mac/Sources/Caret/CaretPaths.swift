import Foundation

enum CaretPaths {
    private static let supportFolderName = "Caret"

    /// Writable notes store (Application Support). Used by the shipped app.
    static var applicationSupportRoot: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(supportFolderName, isDirectory: true)
    }

    static var notesRoot: URL {
        applicationSupportRoot.appendingPathComponent("notes", isDirectory: true)
    }

    static var skillsNotesDir: URL {
        notesRoot.appendingPathComponent("skills", isDirectory: true)
    }

    static var memoriesNotesDir: URL {
        notesRoot.appendingPathComponent("memories", isDirectory: true)
    }

    /// Dev checkout when present (repo `caret/notes` or plist path).
    static var projectRoot: URL? {
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CaretProjectRoot") as? String,
           !plist.isEmpty,
           plist != "$(SRCROOT)",
           FileManager.default.fileExists(atPath: plist) {
            return URL(fileURLWithPath: plist, isDirectory: true)
        }
        if let env = ProcessInfo.processInfo.environment["CARET_PROJECT_ROOT"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    static var repoNotesRoot: URL? {
        projectRoot?.appendingPathComponent("caret/notes", isDirectory: true)
    }

    static var skillsRoot: URL? {
        projectRoot?.appendingPathComponent("caret/skills", isDirectory: true)
    }

    static var memoriesJSONRoot: URL? {
        projectRoot?.appendingPathComponent("caret/memories", isDirectory: true)
            ?? applicationSupportRoot.appendingPathComponent("memories", isDirectory: true)
    }

    /// Ensures Application Support notes exist and seeds from bundle or repo when empty.
    static func bootstrapNotesStore() {
        let fm = FileManager.default
        try? fm.createDirectory(at: skillsNotesDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: memoriesNotesDir, withIntermediateDirectories: true)

        if directoryIsEmpty(skillsNotesDir) {
            if let seed = bundleSeedNotesRoot {
                copyMarkdown(from: seed.appendingPathComponent("skills"), to: skillsNotesDir)
            }
            if directoryIsEmpty(skillsNotesDir), let repo = repoNotesRoot {
                copyMarkdown(from: repo.appendingPathComponent("skills"), to: skillsNotesDir)
            }
        }
        migrateFollowUpSkillToAutoExpand()
    }

    /// One-time rename: seeded `follow-up` skill → `auto-expand`.
    private static func migrateFollowUpSkillToAutoExpand() {
        let fm = FileManager.default
        let legacy = skillsNotesDir.appendingPathComponent("follow-up.md")
        let renamed = skillsNotesDir.appendingPathComponent("auto-expand.md")
        guard fm.fileExists(atPath: legacy.path) else { return }

        if !fm.fileExists(atPath: renamed.path) {
            if let seed = bundleSeedNotesRoot?.appendingPathComponent("skills/auto-expand.md"),
               fm.fileExists(atPath: seed.path) {
                try? fm.copyItem(at: seed, to: renamed)
            } else if let repo = repoNotesRoot?.appendingPathComponent("skills/auto-expand.md"),
                      fm.fileExists(atPath: repo.path) {
                try? fm.copyItem(at: repo, to: renamed)
            } else {
                try? fm.moveItem(at: legacy, to: renamed)
                return
            }
        }
        try? fm.removeItem(at: legacy)
    }

    private static var bundleSeedNotesRoot: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("NotesSeed", isDirectory: true)
    }

    private static func directoryIsEmpty(_ url: URL) -> Bool {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return true }
        return items.filter { !$0.hasPrefix(".") }.isEmpty
    }

    private static func copyMarkdown(from source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path),
              let files = try? FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension.lowercased() == "md" {
            let target = destination.appendingPathComponent(file.lastPathComponent)
            if !FileManager.default.fileExists(atPath: target.path) {
                try? FileManager.default.copyItem(at: file, to: target)
            }
        }
    }
}

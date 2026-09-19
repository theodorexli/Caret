import AppKit
import Foundation

struct InstalledAppReference: Identifiable, Hashable {
    let name: String
    let bundleURL: URL

    var id: String { bundleURL.path }
}

enum InstalledApps {
    static func applicationDirectories() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
    }

    static func installedReferences() -> [InstalledAppReference] {
        var seen = Set<String>()
        var references: [InstalledAppReference] = []
        let manager = FileManager.default

        for directory in applicationDirectories() {
            guard let entries = try? manager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for entry in entries where entry.pathExtension == "app" {
                let raw = displayName(for: entry) ?? entry.deletingPathExtension().lastPathComponent
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                if seen.insert(name).inserted {
                    references.append(InstalledAppReference(name: name, bundleURL: entry))
                }
            }
        }

        return references.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func installedNames() -> [String] {
        installedReferences().map(\.name)
    }

    static func reference(named name: String, in catalog: [InstalledAppReference]) -> InstalledAppReference? {
        catalog.first { $0.name == name }
    }

    static func icon(for bundleURL: URL) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: bundleURL.path)
        image.size = NSSize(width: 32, height: 32)
        return image
    }

    static func displayName(for appURL: URL) -> String? {
        let bundle = Bundle(url: appURL)
        let info = bundle?.infoDictionary
        let candidates = [
            info?["CFBundleDisplayName"] as? String,
            info?["CFBundleName"] as? String,
            appURL.deletingPathExtension().lastPathComponent,
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

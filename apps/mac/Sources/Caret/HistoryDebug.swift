import Foundation

enum HistoryDebug {
    static let missingRootMessage = "Caret has no project root, so last-N history is unavailable."

    static func command(projectRoot: URL) -> [String] {
        [
            "python3",
            "-m",
            "caret",
            "history-debug",
            "--lease",
            ScreenpipeSupervisor.leaseURL(projectRoot: projectRoot).path,
        ]
    }

    static func format(_ payload: [String: Any]) -> String {
        let headings = [("windows", "Windows"), ("minutes", "Minutes"), ("clipboard", "Clipboard")]
        var lines: [String] = []
        for (key, heading) in headings {
            lines.append(heading)
            let section = payload[key] as? [String: Any] ?? [:]
            if section["ok"] as? Bool == true {
                let items = section["items"] as? [[String: Any]] ?? []
                if items.isEmpty {
                    lines.append("(none)")
                }
                for item in items.prefix(2) {
                    let app = item["app"] as? String ?? ""
                    let title = item["title"] as? String ?? ""
                    let timestamp = item["timestamp"] as? String ?? ""
                    let text = item["text"] as? String ?? ""
                    lines.append("\(app) — \(title) @ \(timestamp)")
                    if !text.isEmpty {
                        lines.append("  \(text)")
                    }
                }
            } else {
                lines.append(section["error"] as? String ?? "unavailable")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func load(projectRoot: URL?) -> String {
        guard let projectRoot else { return missingRootMessage }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command(projectRoot: projectRoot)
        process.currentDirectoryURL = projectRoot
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return "Could not run history-debug: \(error.localizedDescription)"
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return format(object)
        }
        let err = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let text = String(data: data, encoding: .utf8) ?? ""
        let combined = [text, err].filter { !$0.isEmpty }.joined(separator: "\n")
        return combined.isEmpty ? "history-debug failed" : combined
    }
}

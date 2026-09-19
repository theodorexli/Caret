import Foundation

enum CaretCLI {
    enum Error: Swift.Error {
        case missingProjectRoot
        case launchFailed(Swift.Error)
        case nonZeroExit(Int32, String)
        case emptyResponse
    }

    static func autoExpand(prefix: String, instructions: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runAutoExpand(prefix: prefix, instructions: instructions)
        }.value
    }

    private static func runAutoExpand(prefix: String, instructions: String) throws -> String {
        guard let root = CaretPaths.projectRoot else {
            throw Error.missingProjectRoot
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.currentDirectoryURL = root
        var environment = ProcessInfo.processInfo.environment
        environment["CARET_PROJECT_ROOT"] = root.path
        process.environment = environment

        var arguments = ["-m", "caret", "auto-expand", "--prefix", prefix]
        if !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments.append(contentsOf: ["--instructions", instructions])
        }
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw Error.launchFailed(error)
        }
        process.waitUntilExit()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: outData, encoding: .utf8) ?? ""
        let err = String(data: errData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw Error.nonZeroExit(process.terminationStatus, err.isEmpty ? out : err)
        }
        return out.trimmingCharacters(in: .newlines)
    }
}

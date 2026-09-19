import Foundation

enum TabCompletionsPatterns {
    private static let patternLine = try! NSRegularExpression(
        pattern: #"^\s*(?:\d+\.|[-*])\s+(.+)$"#,
        options: []
    )

    static func instructionPatterns(from instructions: String) -> [String] {
        var patterns: [String] = []
        for line in instructions.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased().hasPrefix("when ") {
                continue
            }
            let ns = String(line) as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = patternLine.firstMatch(in: String(line), range: range),
                  match.numberOfRanges > 1
            else { continue }
            let captured = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty {
                patterns.append(captured)
            }
        }
        return patterns
    }

    static func completionSuffix(prefix: String, instructions: String) -> String {
        guard !prefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }

        var bestSuffix = ""
        var bestPatternLength = -1
        for pattern in instructionPatterns(from: instructions) {
            let shared = sharedPrefixLength(typed: prefix, pattern: pattern)
            guard shared == prefix.count, shared < pattern.count else { continue }
            let start = pattern.index(pattern.startIndex, offsetBy: shared)
            let suffix = String(pattern[start...])
            if pattern.count > bestPatternLength {
                bestSuffix = suffix
                bestPatternLength = pattern.count
            }
        }
        return bestSuffix
    }

    private static func sharedPrefixLength(typed: String, pattern: String) -> Int {
        let typedScalars = Array(typed)
        let patternScalars = Array(pattern)
        let limit = min(typedScalars.count, patternScalars.count)
        var index = 0
        while index < limit {
            if typedScalars[index].lowercased() != patternScalars[index].lowercased() {
                break
            }
            index += 1
        }
        return index
    }
}

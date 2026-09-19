import Foundation

enum TypingPrefixLogic {
    /// Chooses the best prefix for pattern matching when AX and keystroke capture disagree.
    static func effectivePrefix(axPrefix: String?, capturedPrefix: String) -> String {
        let ax = axPrefix?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let captured = capturedPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if ax.isEmpty { return captured }
        if captured.isEmpty { return ax }
        if ax.count >= captured.count { return ax }
        if captured.hasPrefix(ax) { return captured }
        if ax.hasPrefix(captured) { return ax }
        return captured.count > ax.count ? captured : ax
    }
}

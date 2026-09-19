import Foundation

/// Built-in inline Tab completion skill (not deletable, listed above Actions).
enum TabCompletions {
    static let actionID = "tab-completions"
    static let defaultTitle = "Tab completions"
    static let defaultIcon = "arrow.up.left.and.arrow.down.right"
    /// Minimum characters before the caret before Tab completions activate.
    static let minimumTypedCharacters = 5

    static let legacyActionIDs: Set<String> = ["follow-up", "auto-expand"]

    static func isTabCompletionsAction(_ actionID: String) -> Bool {
        actionID == self.actionID || legacyActionIDs.contains(actionID)
    }
}

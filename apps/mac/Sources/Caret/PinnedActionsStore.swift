import Foundation

/// Persists up to three action ids; slot index maps to ⌘⌥1 … ⌘⌥3.
struct PinnedActionsStore: Equatable {
    static let maxPinned = 3
    static let storageKey = "caret.pinnedActionIDs"

    private(set) var orderedActionIDs: [String]

    init(orderedActionIDs: [String] = []) {
        self.orderedActionIDs = Array(orderedActionIDs.prefix(Self.maxPinned))
    }

    func isPinned(_ actionID: String) -> Bool {
        orderedActionIDs.contains(actionID)
    }

    /// 1-based slot for keyboard shortcuts, or nil when not pinned.
    func slot(for actionID: String) -> Int? {
        guard let index = orderedActionIDs.firstIndex(of: actionID) else { return nil }
        return index + 1
    }

    func actionID(forSlot slot: Int) -> String? {
        guard slot >= 1, slot <= Self.maxPinned else { return nil }
        let index = slot - 1
        guard orderedActionIDs.indices.contains(index) else { return nil }
        return orderedActionIDs[index]
    }

    mutating func pin(actionID: String) -> Bool {
        if isPinned(actionID) { return true }
        guard orderedActionIDs.count < Self.maxPinned else { return false }
        orderedActionIDs.append(actionID)
        return true
    }

    mutating func unpin(actionID: String) {
        orderedActionIDs.removeAll { $0 == actionID }
    }

    /// Returns false when pinning would exceed `maxPinned`.
    mutating func togglePin(actionID: String) -> Bool {
        if isPinned(actionID) {
            unpin(actionID: actionID)
            return true
        }
        return pin(actionID: actionID)
    }

    static func load(from defaults: UserDefaults = .standard) -> PinnedActionsStore {
        let raw = defaults.stringArray(forKey: storageKey) ?? []
        let ids = raw.compactMap { id -> String? in
            if TabCompletions.isTabCompletionsAction(id) { return nil }
            return id
        }
        let store = PinnedActionsStore(orderedActionIDs: ids)
        if ids != raw {
            store.save(to: defaults)
        }
        return store
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(orderedActionIDs, forKey: Self.storageKey)
    }
}

enum PinnedShortcutFormatting {
    static func menuLabel(slot: Int) -> String {
        "⌘⌥\(slot)"
    }
}

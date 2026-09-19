import AppKit
import ApplicationServices
import SwiftUI

struct MemoryItem: Identifiable {
    let id: String
    let text: String
    let sourceApp: String?
}

struct CaretAction: Identifiable, Equatable {
    let id: String
    let title: String
}

@MainActor
final class Model: ObservableObject {
    @Published var selectedText = ""
    @Published var sourceApp: String?
    @Published private(set) var pinStore: PinnedActionsStore
    @Published var panelQuery = ""
    @Published var scopedActionID: String?
    @Published private(set) var skillsVersion = 0
    @Published private(set) var customActions: [CaretAction] = []
    @Published private(set) var storedMemories: [StoredMemory] = []
    var memories: [MemoryItem] = []
    var onRun: ((CaretAction) -> Void)?
    var onPinsChanged: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onReconnectAccessibility: (() -> Void)?
    var onOpenSettingsWindow: (() -> Void)?

    let skillRepository = SkillRepository()
    let memoryRepository = MemoryRepository()
    let noteRepository = NoteRepository()

    @Published private(set) var skillNotes: [CaretNote] = []
    @Published private(set) var memoryNotes: [CaretNote] = []

    init(pinStore: PinnedActionsStore = .load()) {
        self.pinStore = pinStore
        reloadCustomActions()
        reloadNotes()
    }

    var actionSkillItems: [ActionSkillItem] {
        allActions.map { action in
            ActionSkillItem(action: action, note: skillNotes.first { $0.id == action.id })
        }
    }

    func reloadNotes() {
        CaretPaths.bootstrapNotesStore()
        skillNotes = noteRepository.listSkillNotes()
        memoryNotes = noteRepository.listMemoryNotes()
        storedMemories = memoryRepository.load()
        memories = noteRepository.memoryContextItems()
        if memories.isEmpty {
            memories = storedMemories.map { MemoryItem(id: $0.id, text: $0.text, sourceApp: $0.sourceApp) }
        }
        onPinsChanged?()
    }

    func saveSkillNote(actionID: String, title: String, icon: String, body: String, apps: [String] = []) {
        do {
            _ = try noteRepository.saveSkillNote(
                actionID: actionID,
                title: title,
                icon: icon,
                body: body,
                apps: apps
            )
            reloadNotes()
            onPinsChanged?()
        } catch {
            NSLog("[Caret] save skill note failed: %@", String(describing: error))
        }
    }

    func saveMemoryNote(noteID: String, title: String, icon: String, body: String, apps: [String]) {
        do {
            _ = try noteRepository.saveMemoryNote(
                noteID: noteID,
                title: title,
                icon: icon,
                body: body,
                apps: apps
            )
            reloadNotes()
        } catch {
            NSLog("[Caret] save memory note failed: %@", String(describing: error))
        }
    }

    func deleteMemoryNote(id: String) {
        do {
            try noteRepository.deleteMemoryNote(id: id)
            reloadNotes()
        } catch {
            NSLog("[Caret] delete memory note failed: %@", String(describing: error))
        }
    }

    func reloadMemories() {
        reloadNotes()
    }

    func addMemory(text: String) {
        do {
            _ = try memoryRepository.add(text: text)
            reloadMemories()
        } catch {
            NSLog("[Caret] add memory failed: %@", String(describing: error))
        }
    }

    func deleteMemory(id: String) {
        do {
            try memoryRepository.delete(id: id)
            reloadMemories()
        } catch {
            NSLog("[Caret] delete memory failed: %@", String(describing: error))
        }
    }

    var skillGroups: [(action: CaretAction, skills: [CaretSkill])] {
        allActions.compactMap { action in
            let skills = skillRepository.list(actionID: action.id)
            guard !skills.isEmpty else { return nil }
            return (action, skills)
        }
    }

    var allActions: [CaretAction] {
        var byID: [String: CaretAction] = [:]
        for note in skillNotes {
            byID[note.id] = CaretAction(id: note.id, title: note.title)
        }
        for action in customActions where byID[action.id] == nil {
            byID[action.id] = action
        }
        return byID.values.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    func deleteSkill(actionID: String) {
        do {
            try noteRepository.deleteSkillNote(actionID: actionID)
            try skillRepository.deleteActionDirectory(actionID: actionID)
            if pinStore.isPinned(actionID), let action = action(id: actionID) {
                togglePin(action)
            }
            reloadCustomActions()
            reloadNotes()
        } catch {
            NSLog("[Caret] delete skill failed: %@", String(describing: error))
        }
    }

    @discardableResult
    func createSkill(named title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let reserved = Set(allActions.map(\.id))
        let actionID = noteRepository.makeUniqueSkillActionID(title: trimmed, reservedIDs: reserved)
        do {
            _ = try noteRepository.saveSkillNote(
                actionID: actionID,
                title: trimmed,
                icon: "sparkle",
                body: "Describe what this skill should do.\n"
            )
            reloadCustomActions()
            reloadNotes()
            return actionID
        } catch {
            NSLog("[Caret] create skill failed: %@", String(describing: error))
            return nil
        }
    }

    var trimmedPanelQuery: String {
        panelQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func action(id: String) -> CaretAction? {
        allActions.first { $0.id == id }
    }

    func reloadCustomActions() {
        customActions = skillRepository.listActionIDs()
            .map { CaretAction(id: $0, title: SkillRepository.displayTitle(actionID: $0)) }
    }

    var pinnedActions: [CaretAction] {
        pinStore.orderedActionIDs.compactMap { action(id: $0) }
    }

    var pinnedChips: [PinnedActionChip] {
        pinnedActions.compactMap { action in
            guard let slot = pinStore.slot(for: action.id) else { return nil }
            let note = skillNotes.first(where: { $0.id == action.id })
            return PinnedActionChip(
                id: action.id,
                title: note?.title ?? action.title,
                icon: note?.icon ?? CaretActionIcons.icon(for: action.id),
                slot: slot
            )
        }
    }

    func shortcutLabel(for action: CaretAction) -> String? {
        guard let slot = pinStore.slot(for: action.id) else { return nil }
        return PinnedShortcutFormatting.menuLabel(slot: slot)
    }

    func canPin(_ action: CaretAction) -> Bool {
        pinStore.isPinned(action.id) || pinStore.orderedActionIDs.count < PinnedActionsStore.maxPinned
    }

    func togglePin(_ action: CaretAction) {
        let changed = pinStore.togglePin(actionID: action.id)
        if changed || pinStore.isPinned(action.id) {
            pinStore.save()
            objectWillChange.send()
            onPinsChanged?()
        }
    }

    func preparePanel(scopedActionID: String?) {
        reloadCustomActions()
        self.scopedActionID = scopedActionID
        panelQuery = ""
    }

    func clearPanelScope() {
        scopedActionID = nil
        panelQuery = ""
    }

    func openSettings() {
        onOpenSettingsWindow?()
    }

    var settingsMatchesSearch: Bool {
        let query = trimmedPanelQuery.lowercased()
        guard !query.isEmpty else { return false }
        return "settings".contains(query) || query.contains("setting")
    }

    var accessibilityConnected: Bool {
        AXHelpers.isTrusted()
    }

    var scopedAction: CaretAction? {
        guard let scopedActionID else { return nil }
        return action(id: scopedActionID)
    }

    var filteredActions: [CaretAction] {
        let needle = trimmedPanelQuery.lowercased()
        guard !needle.isEmpty else { return allActions }
        return allActions.filter { $0.title.lowercased().contains(needle) || $0.id.lowercased().contains(needle) }
    }

    var filteredSkills: [CaretSkill] {
        guard let scopedActionID else { return [] }
        return skillRepository.filter(actionID: scopedActionID, query: panelQuery)
    }

    var canCreateSkill: Bool {
        guard let scopedActionID else { return false }
        let query = trimmedPanelQuery
        guard !query.isEmpty else { return false }
        let existing = skillRepository.filter(actionID: scopedActionID, query: query)
        return !existing.contains { $0.name.compare(query, options: .caseInsensitive) == .orderedSame }
    }

    var showCreateRow: Bool {
        let query = trimmedPanelQuery
        guard !query.isEmpty else { return false }
        if scopedActionID != nil {
            return canCreateSkill
        }
        let exactAction = allActions.contains { $0.title.compare(query, options: .caseInsensitive) == .orderedSame }
        return !exactAction
    }

    var createRowTitle: String {
        "Create \"\(trimmedPanelQuery)\""
    }

    var createRowSubtitle: String {
        if scopedActionID != nil {
            return "New skill for this action"
        }
        if filteredActions.isEmpty {
            return "New action and skill"
        }
        return "New action when nothing matches"
    }

    func selectActionForSkills(_ action: CaretAction) {
        scopedActionID = action.id
        panelQuery = ""
    }

    func submitCreateFromQuery() {
        let name = trimmedPanelQuery
        guard !name.isEmpty else { return }

        if let scopedActionID {
            do {
                _ = try skillRepository.create(actionID: scopedActionID, name: name)
                skillsVersion += 1
            } catch {
                NSLog("[Caret] create skill failed: %@", String(describing: error))
            }
            return
        }

        let actionID = SkillRepository.slugify(name)
        do {
            _ = try skillRepository.create(actionID: actionID, name: name)
            reloadCustomActions()
            self.scopedActionID = actionID
            skillsVersion += 1
        } catch {
            NSLog("[Caret] create action failed: %@", String(describing: error))
        }
    }

    func run(_ action: CaretAction, skill: CaretSkill? = nil) {
        NSLog(
            "[Caret] action=%@ skill=%@ memories=%d selection=%@ app=%@",
            action.id,
            skill?.id ?? "-",
            memories.count,
            selectedText.replacingOccurrences(of: "\n", with: " "),
            sourceApp ?? "-"
        )
        onRun?(action)
    }

    func run(skill: CaretSkill) {
        guard let action = action(id: skill.actionID) else { return }
        run(action, skill: skill)
    }

    func runPinnedSlot(_ slot: Int) {
        guard let id = pinStore.actionID(forSlot: slot), let action = action(id: id) else { return }
        let skills = skillRepository.list(actionID: id)
        if let first = skills.first {
            run(action, skill: first)
        } else {
            run(action)
        }
    }
}

enum ActionsMenuMetrics {
    static let rowHeight: CGFloat = 32
    static let rowHeightWithSubtitle: CGFloat = 46
    static let maxVisibleRows: CGFloat = 8
    static let width: CGFloat = 300

    static var maxScrollHeight: CGFloat {
        rowHeightWithSubtitle * maxVisibleRows + 8
    }
}

struct SkillPickerView: View {
    @ObservedObject var model: Model
    @FocusState private var searchFocused: Bool

    private var searchPlaceholder: String {
        if model.scopedAction != nil {
            return "Filter skills or create one"
        }
        return "Search actions or create"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let action = model.scopedAction {
                    Button {
                        model.clearPanelScope()
                        searchFocused = true
                    } label: {
                        Label(action.title, systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }

                PanelSearchField(
                    text: $model.panelQuery,
                    placeholder: searchPlaceholder,
                    isFocused: $searchFocused,
                    onSettings: { model.openSettings() }
                )
                .onSubmit {
                    if model.settingsMatchesSearch {
                        model.openSettings()
                    } else if model.showCreateRow {
                        model.submitCreateFromQuery()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().opacity(0.35)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if model.scopedAction == nil {
                        if model.settingsMatchesSearch {
                            SkillRow(title: "Settings", subtitle: "Accessibility and Caret", accent: false) {
                                model.openSettings()
                            }
                        }
                        if model.filteredActions.isEmpty, !model.trimmedPanelQuery.isEmpty, !model.settingsMatchesSearch {
                            EmptyResultsHint(text: "No matching actions")
                        }
                        ForEach(model.filteredActions) { action in
                            ActionRow(
                                title: action.title,
                                shortcut: model.shortcutLabel(for: action),
                                isPinned: model.pinStore.isPinned(action.id),
                                canPin: model.canPin(action),
                                onPin: { model.togglePin(action) },
                                onSelect: { model.selectActionForSkills(action) }
                            )
                        }
                        if model.showCreateRow {
                            CreateRow(model: model)
                        }
                    } else {
                        let _ = model.skillsVersion
                        if model.filteredSkills.isEmpty, !model.trimmedPanelQuery.isEmpty {
                            EmptyResultsHint(text: "No matching skills")
                        }
                        ForEach(model.filteredSkills) { skill in
                            SkillRow(title: skill.name, subtitle: skill.description) {
                                model.run(skill: skill)
                            }
                        }
                        if model.showCreateRow {
                            CreateRow(model: model)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: ActionsMenuMetrics.maxScrollHeight)
        }
        .frame(width: ActionsMenuMetrics.width)
        .onAppear {
            searchFocused = true
        }
        .onChange(of: model.scopedActionID) { _, _ in
            searchFocused = true
        }
    }
}

private struct PanelSearchField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState.Binding var isFocused: Bool
    var showsSettingsButton: Bool = true
    var onSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
            if showsSettingsButton, let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct EmptyResultsHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CreateRow: View {
    @ObservedObject var model: Model

    var body: some View {
        SkillRow(
            title: model.createRowTitle,
            subtitle: model.createRowSubtitle,
            accent: true
        ) {
            model.submitCreateFromQuery()
        }
    }
}

private struct ActionRow: View {
    let title: String
    let shortcut: String?
    let isPinned: Bool
    let canPin: Bool
    let onPin: () -> Void
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onSelect) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let shortcut {
                        Text(shortcut)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPinned || canPin {
                Button(action: onPin) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isPinned ? Color.accentColor : .secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Unpin" : "Pin next to Caret icon")
                .padding(.trailing, 6)
            }
        }
        .padding(.trailing, isPinned || canPin ? 0 : 6)
        .frame(height: ActionsMenuMetrics.rowHeight)
        .padding(.horizontal, 6)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            }
        }
        .onHover { isHovered = $0 }
    }
}

private struct SkillRow: View {
    let title: String
    let subtitle: String
    var accent: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if accent {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: accent ? .medium : .regular))
                        .foregroundStyle(accent ? Color.accentColor : .primary)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, accent ? 10 : 12)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: subtitle.isEmpty ? ActionsMenuMetrics.rowHeight : ActionsMenuMetrics.rowHeightWithSubtitle)
        .padding(.horizontal, 6)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(accent ? 0.12 : 0.08))
            }
        }
        .onHover { isHovered = $0 }
    }
}

final class CaretPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present(at point: CGPoint) {
        setFrame(frame(near: point), display: true)
        orderFrontRegardless()
        makeKey()
    }

    private func frame(near point: CGPoint) -> NSRect {
        let size = frame.size.width > 1 ? frame.size : CGSize(width: ActionsMenuMetrics.width, height: 200)
        let screen = AXHelpers.screen(containing: point)
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        let margin: CGFloat = 12
        var origin = CGPoint(x: point.x + 16, y: point.y - size.height / 2)
        if origin.x + size.width > visible.maxX - margin {
            origin.x = point.x - size.width - 16
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        return NSRect(origin: origin, size: size)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var panel: CaretPanel?
    private var permissionPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var model: Model?
    private var trustTimer: Timer?
    private var lastTarget: SelectionTarget?
    private var clickMonitor: Any?
    private var escapeMonitor: Any?
    private let chordState = ModifierChordState()
    private let hotKey = HotKeyManager()
    private var trigger: TriggerButtonController!
    private let monitor = SelectionMonitor()
    private let statusBar = StatusBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        trigger = TriggerButtonController(chordState: chordState)
        let model = Model()
        self.model = model

        let panel = CaretPanel(
            contentRect: NSRect(x: 0, y: 0, width: ActionsMenuMetrics.width, height: 200),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        model.onRun = { [weak self] _ in
            self?.hidePanel()
        }
        model.onPinsChanged = { [weak self] in
            self?.syncPinnedTriggerUI()
        }
        model.onOpenAccessibility = {
            AXHelpers.openAccessibilitySettings()
        }
        model.onReconnectAccessibility = { [weak self] in
            self?.showPermissionWindow()
        }
        model.onOpenSettingsWindow = { [weak self] in
            self?.showSettingsWindow()
        }
        let hosting = NSHostingView(
            rootView: SkillPickerView(model: model)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        self.panel = panel

        statusBar.onOpen = { [weak self] in
            self?.togglePanel(at: NSEvent.mouseLocation)
        }
        statusBar.onSettings = { [weak self] in
            self?.showSettingsWindow()
        }
        statusBar.onFixAccessibility = { [weak self] in
            self?.showPermissionWindow()
        }
        statusBar.install()

        hotKey.onHotKey = { [weak self] point in
            Task { @MainActor in
                self?.togglePanel(at: point)
            }
        }
        hotKey.onPinnedHotKey = { [weak self] slot in
            Task { @MainActor in
                self?.runPinnedAction(slot: slot)
            }
        }
        hotKey.onCommandOptionHeld = { [weak self] held in
            Task { @MainActor in
                self?.chordState.setCommandOptionHeld(held)
            }
        }
        hotKey.register()

        trigger.onClick = { [weak self] in
            guard let self else { return }
            self.showPanel(
                at: CGPoint(x: self.trigger.buttonFrame.maxX, y: self.trigger.buttonFrame.midY),
                scopedActionID: nil
            )
        }
        trigger.onPinnedAction = { [weak self] chip in
            Task { @MainActor in
                guard let self else { return }
                self.showPanel(
                    at: CGPoint(x: self.trigger.buttonFrame.maxX, y: self.trigger.buttonFrame.midY),
                    scopedActionID: chip.id
                )
            }
        }

        syncPinnedTriggerUI()

        monitor.onChange = { [weak self] target in
            Task { @MainActor in
                guard let self, let model = self.model else { return }
                self.lastTarget = target
                model.selectedText = target?.selectedText ?? ""
                model.sourceApp = target?.sourceApp
                if self.panel?.isVisible == true {
                    self.trigger.hide()
                } else {
                    self.trigger.update(target: target)
                }
            }
        }

        requestAccessibilityAndStart()
        ScreenpipeSupervisor.start(projectRoot: CaretPaths.projectRoot)
    }

    private func syncPinnedTriggerUI() {
        trigger.setPinnedActions(model?.pinnedChips ?? [])
        if panel?.isVisible != true {
            trigger.update(target: lastTarget)
        }
    }

    private func runPinnedAction(slot: Int) {
        guard let model else { return }
        model.runPinnedSlot(slot)
    }

    func togglePanel(at point: CGPoint) {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel(at: point, scopedActionID: nil)
        }
    }

    private func showPanel(at point: CGPoint, scopedActionID: String?) {
        model?.preparePanel(scopedActionID: scopedActionID)
        trigger.hide()
        panel?.present(at: point)
        installClickOutside()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        removeClickOutside()
        model?.clearPanelScope()
        trigger.update(target: lastTarget)
    }

    private func installClickOutside() {
        removeClickOutside()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.hidePanel()
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
                Task { @MainActor in
                    self?.hidePanel()
                }
                return nil
            }
            return event
        }
    }

    private func removeClickOutside() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === settingsWindow else { return }
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        monitor.stop()
        trustTimer?.invalidate()
        removeClickOutside()
        ScreenpipeSupervisor.stop()
    }

    private func requestAccessibilityAndStart() {
        if AXHelpers.isTrusted() {
            AccessibilityTrust.noteTrustedIfNeeded()
            monitor.start()
            return
        }

        if AccessibilityTrust.needsRepairPrompt() {
            showPermissionWindow()
        }

        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard AXHelpers.isTrusted() else { return }
            timer.invalidate()
            Task { @MainActor in
                AccessibilityTrust.noteTrustedIfNeeded()
                self?.trustTimer = nil
                self?.permissionPanel?.orderOut(nil)
                self?.permissionPanel = nil
                self?.monitor.start()
            }
        }
    }

    func showSettingsWindow() {
        guard let model else { return }
        hidePanel()

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Caret Settings"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.toolbarStyle = .unified
            window.center()
            settingsWindow = window
        }

        settingsWindow?.toolbarStyle = .unified
        settingsWindow?.contentView = NSHostingView(rootView: CaretSettingsView(model: model))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showPermissionWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Caret"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: PermissionView(
            executablePath: AccessibilityTrust.executablePath,
            onOpenSettings: { AXHelpers.openAccessibilitySettings() },
            onDismiss: { [weak self] in
                AccessibilityTrust.dismissRepairPromptForCurrentBuild()
                self?.permissionPanel?.orderOut(nil)
                self?.permissionPanel = nil
            }
        ))
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        permissionPanel = panel
    }
}

@main
struct CaretMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

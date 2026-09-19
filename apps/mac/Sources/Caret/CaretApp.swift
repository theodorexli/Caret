import AppKit
import ApplicationServices
import CaretCore
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
    /// Live action offers and what happened to them. B-01: selecting an action
    /// used to close the panel with no result at all.
    @Published private(set) var actionOffers: [CaretActionOffer] = []
    /// Why actions are unavailable right now, shown verbatim. Empty when the
    /// backend is healthy.
    @Published var backendStatus: String = ""
    var onRunAction: ((String) -> Void)?
    var memories: [MemoryItem] = []
    var onRun: ((CaretAction, CaretSkill?) -> Void)?
    var onPinsChanged: (() -> Void)?
    var onOpenAccessibility: (() -> Void)?
    var onReconnectAccessibility: (() -> Void)?
    var onOpenSettingsWindow: (() -> Void)?

    let skillRepository = SkillRepository()
    let memoryRepository = MemoryRepository()
    let noteRepository = NoteRepository()
    let noteEditor = NoteEditorSession()

    @Published private(set) var skillNotes: [CaretNote] = []
    @Published private(set) var memoryNotes: [CaretNote] = []
    @Published private(set) var skillPreviewByActionID: [String: String] = [:]
    @Published var skillPreviewRunningActionID: String?

    private var liveSkillInstructionsByActionID: [String: String] = [:]

    init(pinStore: PinnedActionsStore = .load()) {
        self.pinStore = pinStore
        reloadCustomActions()
        reloadNotes()
    }

    var actionSkillItems: [ActionSkillItem] {
        allActions
            .filter { !TabCompletions.legacyActionIDs.contains($0.id) }
            .map { action in
                ActionSkillItem(action: action, note: skillNotes.first { $0.id == action.id })
            }
    }

    var tabCompletionsItem: ActionSkillItem {
        if let note = skillNotes.first(where: { $0.id == TabCompletions.actionID }) {
            return ActionSkillItem(
                action: CaretAction(id: note.id, title: note.title),
                note: note
            )
        }
        return ActionSkillItem(
            action: CaretAction(id: TabCompletions.actionID, title: TabCompletions.defaultTitle),
            note: nil
        )
    }

    var regularActionSkillItems: [ActionSkillItem] {
        actionSkillItems.filter { $0.action.id != TabCompletions.actionID }
    }

    func tabCompletionsConfiguration() -> (instructions: String, excludedApps: [String]) {
        let note = skillNotes.first(where: { $0.id == TabCompletions.actionID })
        return (note?.body ?? "", note?.excludedApps ?? [])
    }

    func setLiveSkillInstructions(actionID: String, body: String) {
        liveSkillInstructionsByActionID[actionID] = body
    }

    func resolvedSkillInstructions(actionID: String) -> String? {
        if let live = liveSkillInstructionsByActionID[actionID]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !live.isEmpty {
            return live
        }
        return skillNotes.first(where: { $0.id == actionID })?.body
    }

    func skillPreviewText(actionID: String) -> String {
        skillPreviewByActionID[actionID] ?? ""
    }

    func beginSkillPreview(actionID: String) {
        skillPreviewByActionID[actionID] = ""
        skillPreviewRunningActionID = actionID
        objectWillChange.send()
    }

    func finishSkillPreview(actionID: String, output: String) {
        skillPreviewByActionID[actionID] = output
        skillPreviewRunningActionID = nil
        objectWillChange.send()
    }

    func failSkillPreview(actionID: String, message: String) {
        skillPreviewByActionID[actionID] = message
        skillPreviewRunningActionID = nil
        objectWillChange.send()
    }

    func reloadNotes() {
        CaretPaths.bootstrapNotesStore()
        try? noteRepository.ensureTabCompletionsNote()
        skillNotes = noteRepository.listSkillNotes()
        memoryNotes = noteRepository.listMemoryNotes()
        storedMemories = memoryRepository.load()
        memories = noteRepository.memoryContextItems()
        if memories.isEmpty {
            memories = storedMemories.map { MemoryItem(id: $0.id, text: $0.text, sourceApp: $0.sourceApp) }
        }
        onPinsChanged?()
    }

    @discardableResult
    func saveSkillNote(
        actionID: String,
        title: String,
        icon: String,
        body: String,
        apps: [String] = [],
        excludedApps: [String] = []
    ) -> Bool {
        do {
            _ = try noteRepository.saveSkillNote(
                actionID: actionID,
                title: title,
                icon: icon,
                body: body,
                apps: apps,
                excludedApps: excludedApps
            )
            reloadNotes()
            onPinsChanged?()
            return true
        } catch {
            NSLog("[Caret] save skill note failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func saveMemoryNote(noteID: String, title: String, icon: String, body: String, apps: [String]) -> String? {
        do {
            let note = try noteRepository.saveMemoryNote(
                noteID: noteID,
                title: title,
                icon: icon,
                body: body,
                apps: apps
            )
            reloadNotes()
            return note.id
        } catch {
            NSLog("[Caret] save memory note failed: %@", String(describing: error))
            return nil
        }
    }

    @discardableResult
    func deleteMemoryNote(id: String) -> Bool {
        do {
            try noteRepository.deleteMemoryNote(id: id)
            reloadNotes()
            return true
        } catch {
            NSLog("[Caret] delete memory note failed: %@", String(describing: error))
            return false
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

    @discardableResult
    func deleteSkill(actionID: String) -> Bool {
        guard !TabCompletions.isTabCompletionsAction(actionID) else { return false }
        do {
            try noteRepository.deleteSkillNote(actionID: actionID)
            try skillRepository.deleteActionDirectory(actionID: actionID)
            if pinStore.isPinned(actionID), let action = action(id: actionID) {
                togglePin(action)
            }
            reloadCustomActions()
            reloadNotes()
            return true
        } catch {
            NSLog("[Caret] delete skill failed: %@", String(describing: error))
            return false
        }
    }

    @discardableResult
    func createBlankSkill() -> String? {
        createSkill(named: uniqueDraftTitle(base: "Untitled skill", existing: skillNotes.map(\.title)))
    }

    @discardableResult
    func createBlankMemory() -> String? {
        let title = uniqueDraftTitle(base: "Untitled", existing: memoryNotes.map(\.title))
        return saveMemoryNote(noteID: title, title: title, icon: "tray.full", body: "", apps: [])
    }

    @discardableResult
    func createSkill(named title: String, body: String = "", icon: String = "sparkle") -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let reserved = Set(allActions.map(\.id))
        let actionID = noteRepository.makeUniqueSkillActionID(title: trimmed, reservedIDs: reserved)
        do {
            _ = try noteRepository.saveSkillNote(
                actionID: actionID,
                title: trimmed,
                icon: icon,
                body: body
            )
            reloadCustomActions()
            reloadNotes()
            return actionID
        } catch {
            NSLog("[Caret] create skill failed: %@", String(describing: error))
            return nil
        }
    }

    private func uniqueDraftTitle(base: String, existing: [String]) -> String {
        let existingSet = Set(existing)
        if !existingSet.contains(base) { return base }
        var counter = 2
        while existingSet.contains("\(base) \(counter)") {
            counter += 1
        }
        return "\(base) \(counter)"
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
        if TabCompletions.isTabCompletionsAction(action.id) { return false }
        return pinStore.isPinned(action.id) || pinStore.orderedActionIDs.count < PinnedActionsStore.maxPinned
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

    var onPanelLayoutChanged: (() -> Void)?

    func clearPanelScope() {
        scopedActionID = nil
        panelQuery = ""
        onPanelLayoutChanged?()
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
        if GatewaySkillActions.contains(action.id) {
            scopedActionID = action.id
            panelQuery = ""
            run(action, skill: nil)
            return
        }
        scopedActionID = action.id
        panelQuery = ""
    }

    /// Gateway actions use the skill note in Settings (`caret/notes/skills/*.md`), not JSON variants.
    func selectActionFromPanel(_ action: CaretAction) {
        if GatewaySkillActions.contains(action.id) {
            run(action, skill: nil)
            return
        }
        selectActionForSkills(action)
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
        onRun?(action, skill)
    }

    /// Runs a prepared offer. An action with no prepared offer is reported as
    /// needing one rather than silently doing nothing, and no fixture is
    /// substituted for a real result.
    func runOfferedAction(_ offer: CaretActionOffer) {
        guard offer.isExecutable else {
            updateActionState(offer.proposalID, .unavailable(
                reason: offer.unavailabilityText ?? "This action has no executor."
            ))
            return
        }
        onRunAction?(offer.proposalID)
    }

    /// What to say when the user picked an action for which the core has not
    /// produced a runnable offer. Names the gap instead of inventing output.
    func unavailabilityText(for action: CaretAction) -> String {
        if !backendStatus.isEmpty { return backendStatus }
        if let offer = actionOffers.first(where: { $0.workflowID == action.id }),
           let text = offer.unavailabilityText {
            return text
        }
        return "No prepared offer for \(action.title) yet. Put the caret in a text field so Caret can read the context it needs."
    }

    func run(skill: CaretSkill) {
        guard let action = action(id: skill.actionID) else { return }
        if GatewaySkillActions.contains(action.id) {
            run(action, skill: nil)
            return
        }
        run(action, skill: skill)
    }

    func setActionOffers(_ offers: [CaretActionOffer]) { actionOffers = offers }

    func updateActionState(_ proposalID: String, _ state: CaretActionOffer.State) {
        guard let index = actionOffers.firstIndex(where: { $0.proposalID == proposalID }) else { return }
        actionOffers[index].state = state
    }

    /// The offers the user can actually run, in the order Cmd-1..3 address
    /// them. A catalog entry with no executor is not in this list.
    var runnableOffers: [CaretActionOffer] {
        actionOffers.filter { $0.isExecutable }
    }

    func ensureGatewayRun(_ action: CaretAction) {
        guard GatewaySkillActions.contains(action.id) else { return }
        if skillPreviewRunningActionID == action.id { return }
        if !(skillPreviewByActionID[action.id] ?? "").isEmpty { return }
        run(action, skill: nil)
    }

    func runPinnedSlot(_ slot: Int) {
        guard let id = pinStore.actionID(forSlot: slot), let action = action(id: id) else { return }
        if GatewaySkillActions.contains(action.id) {
            run(action, skill: nil)
            return
        }
        let skills = skillRepository.list(actionID: id)
        if let first = skills.first {
            run(action, skill: first)
        } else {
            run(action)
        }
    }
}

enum ActionsMenuMetrics {
    static let panelCornerRadius: CGFloat = 12
    static let rowCornerRadius: CGFloat = 8
    static let panelInset: CGFloat = 12
    static let rowHeight: CGFloat = 34
    static let rowHeightWithSubtitle: CGFloat = 48
    static let rowSpacing: CGFloat = 2
    static let width: CGFloat = 300
    static let gatewayWidth: CGFloat = 400
    static let gatewayMinHeight: CGFloat = 300
    /// Fixed floating-panel height for gateway skills (header + scroll body).
    static let gatewayPanelHeight: CGFloat = gatewayMinHeight + 24
    /// Browse palette: search header + scrollable list (must match NSPanel frame).
    static let browsePanelHeight: CGFloat = 340
    static let browseSearchBlockHeight: CGFloat = 52
    static let gatewayHeaderHeight: CGFloat = 50
    static let gatewayBodyPadding: CGFloat = 14
    static var gatewayBodyHeight: CGFloat {
        gatewayPanelHeight - gatewayHeaderHeight - (gatewayBodyPadding * 2)
    }

    static var browseListHeight: CGFloat {
        browsePanelHeight - browseSearchBlockHeight - 1
    }
}

struct SkillPickerView: View {
    @ObservedObject var model: Model
    @FocusState private var searchFocused: Bool

    private var gatewayScopedAction: CaretAction? {
        guard let id = model.scopedActionID, GatewaySkillActions.contains(id) else { return nil }
        return model.action(id: id)
    }

    private var searchPlaceholder: String {
        if gatewayScopedAction != nil {
            return ""
        }
        if model.scopedAction != nil {
            return "Filter skills or create one"
        }
        return "Search actions or create"
    }

    private var panelWidth: CGFloat {
        gatewayScopedAction != nil ? ActionsMenuMetrics.gatewayWidth : ActionsMenuMetrics.width
    }

    var body: some View {
        Group {
            if let action = gatewayScopedAction {
                GatewayActionPanel(model: model, action: action) {
                    model.clearPanelScope()
                    searchFocused = true
                }
            } else {
                browsePanel
            }
        }
        .frame(width: panelWidth, alignment: .topLeading)
        .modifier(GatewayPanelSizing(isGateway: gatewayScopedAction != nil))
        .clipShape(RoundedRectangle(cornerRadius: ActionsMenuMetrics.panelCornerRadius, style: .continuous))
    }

    private var browsePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
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

                // B-01: offered / running / succeeded / failed, with the
                // core's own summary and evidence. Never synthesized.
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

                if !model.actionOffers.isEmpty {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.actionOffers) { offer in
                                CaretActionOfferRow(offer: offer) {
                                    model.runOfferedAction(offer)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }
            .padding(.horizontal, ActionsMenuMetrics.panelInset)
            .padding(.top, ActionsMenuMetrics.panelInset)
            .padding(.bottom, 10)

            Divider().opacity(0.35)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: ActionsMenuMetrics.rowSpacing) {
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
                                onSelect: { model.selectActionFromPanel(action) }
                            )
                        }
                        if model.showCreateRow {
                            CreateRow(model: model)
                        }
                    } else {
                        let _ = model.skillsVersion
                        // B-05: a scope with no skills used to render nothing
                        // at all, leaving no next step. Say what is actually
                        // available before offering to create anything.
                        if model.filteredSkills.isEmpty, model.trimmedPanelQuery.isEmpty {
                            CaretActionStatusRow(
                                title: "Nothing ready to run here",
                                detail: model.scopedAction.map { model.unavailabilityText(for: $0) }
                                    ?? "Type a name to create a skill for this action.",
                                tone: .unavailable
                            )
                        }
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
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }
            .frame(height: ActionsMenuMetrics.browseListHeight, alignment: .topLeading)
        }
        .frame(width: ActionsMenuMetrics.width, height: ActionsMenuMetrics.browsePanelHeight, alignment: .topLeading)
        .onAppear {
            searchFocused = true
        }
        .onChange(of: model.scopedActionID) { _, _ in
            searchFocused = true
        }
    }
}

/// Gateway panels use a fixed height so the header never compresses when the body scrolls.
private struct GatewayPanelSizing: ViewModifier {
    let isGateway: Bool

    func body(content: Content) -> some View {
        if isGateway {
            content
                .frame(height: ActionsMenuMetrics.gatewayPanelHeight, alignment: .topLeading)
        } else {
            content
                .frame(height: ActionsMenuMetrics.browsePanelHeight, alignment: .topLeading)
        }
    }
}

private struct GatewayActionPanel: View {
    @ObservedObject var model: Model
    let action: CaretAction
    var onBack: () -> Void

    private var isRunning: Bool {
        model.skillPreviewRunningActionID == action.id
    }

    private var resultText: String {
        model.skillPreviewText(actionID: action.id)
    }

    private var hasResult: Bool {
        !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var idleHint: String {
        "Select text in another app, or copy it to the clipboard, then run \(action.title) again."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.25)
            resultCard
                .padding(ActionsMenuMetrics.gatewayBodyPadding)
                .frame(height: ActionsMenuMetrics.gatewayBodyHeight, alignment: .topLeading)
        }
        .frame(
            width: ActionsMenuMetrics.gatewayWidth,
            height: ActionsMenuMetrics.gatewayPanelHeight,
            alignment: .topLeading
        )
        .clipShape(RoundedRectangle(cornerRadius: ActionsMenuMetrics.panelCornerRadius, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to actions")

            Text(action.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: ActionsMenuMetrics.gatewayHeaderHeight, alignment: .leading)
    }

    @ViewBuilder
    private var resultCard: some View {
        Group {
            if isRunning {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Running with your skill instructions…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hasResult {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(resultText)
                        .font(.system(size: 14))
                        .lineSpacing(5)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(idleHint)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: ActionsMenuMetrics.rowCornerRadius, style: .continuous))
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
                .padding(.leading, 10)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, minHeight: ActionsMenuMetrics.rowHeight - 6, alignment: .leading)
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
        .padding(.trailing, isPinned || canPin ? 2 : 4)
        .frame(height: ActionsMenuMetrics.rowHeight)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: ActionsMenuMetrics.rowCornerRadius, style: .continuous)
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
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: ActionsMenuMetrics.rowHeight - 6, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: subtitle.isEmpty ? ActionsMenuMetrics.rowHeight : ActionsMenuMetrics.rowHeightWithSubtitle)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: ActionsMenuMetrics.rowCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(accent ? 0.12 : 0.08))
            }
        }
        .onHover { isHovered = $0 }
    }
}

final class CaretPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func present(
        at point: CGPoint,
        width: CGFloat = ActionsMenuMetrics.width,
        height: CGFloat = ActionsMenuMetrics.browsePanelHeight,
        makeKey: Bool = true
    ) {
        setFrame(near: point, width: width, height: height)
        orderFrontRegardless()
        if makeKey {
            self.makeKey()
        }
    }

    /// Resize an already-visible panel without re-keying Caret (keeps host focus for Tab completions).
    func setFrame(near point: CGPoint, width: CGFloat, height: CGFloat) {
        setFrame(frame(near: point, width: width, height: height), display: true)
    }

    private func frame(near point: CGPoint, width: CGFloat, height: CGFloat) -> NSRect {
        let size = CGSize(width: width, height: height)
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
    private var debugWindow: NSWindow?
    private var model: Model?
    private var trustTimer: Timer?
    private var lastTarget: SelectionTarget?
    /// Selection or input captured when the panel opens, before Caret becomes frontmost.
    private var panelContextTarget: SelectionTarget?
    /// Last non-empty selection. Kept when the monitor publishes nil because Caret is frontmost.
    private var rememberedSelection: SelectionTarget?
    private var lastPanelPoint: CGPoint = NSEvent.mouseLocation
    private var clickMonitor: Any?
    private var escapeMonitor: Any?
    private let chordState = ModifierChordState()
    private let hotKey = HotKeyManager()
    private var trigger: TriggerButtonController!
    private let monitor = SelectionMonitor()
    /// Teddy's controller is the sole owner of inline completion and the Tab
    /// key. It runs its own CGEvent tap on keyCode 48, so nothing else in the
    /// app may claim Tab -- two taps on the same key is a race, not a
    /// fallback.
    private let tabCompletions = TabCompletionsController()
    /// Drives actions only: context capture, the core bridge, and Caret's own
    /// Cmd-1..3 choices. It does not touch Tab.
    private var inlineCompletion: InlineCompletionCoordinator?
    /// One capture and one bridge for the whole app: the capture mints the AX
    /// tokens the insertion guard compares, so a second one would make every
    /// acceptance fail as a moved target.
    private let capture = FocusedTargetCapture()
    private var bridge: CoreBridgeProvider?
    private let skillActionRunner = SkillActionRunner()
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
        model.onPanelLayoutChanged = { [weak self] in
            self?.resyncVisiblePanelFrame()
        }
        model.onRun = { [weak self] action, skill in
            guard let self, let model = self.model else { return }
            let target = self.freshTargetForGatewayAction(actionID: action.id)
            if GatewaySkillActions.contains(action.id) {
                model.scopedActionID = action.id
                model.panelQuery = ""
                if self.panel?.isVisible == true {
                    self.resyncVisiblePanelFrame()
                } else {
                    self.showPanel(at: self.lastPanelPoint, scopedActionID: action.id)
                }
            } else {
                self.hidePanel()
            }
            self.skillActionRunner.run(
                action: action,
                skill: skill,
                target: target,
                model: model
            )
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
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ActionsMenuMetrics.panelCornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ActionsMenuMetrics.panelCornerRadius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: ActionsMenuMetrics.panelCornerRadius, style: .continuous))
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        self.panel = panel

        statusBar.onOpen = { [weak self] in
            self?.togglePanel(at: NSEvent.mouseLocation)
        }
        statusBar.onSettings = { [weak self] in
            self?.showSettingsWindow()
        }
        statusBar.onDebug = { [weak self] in
            self?.showDebugWindow()
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
                if GatewaySkillActions.contains(chip.id) {
                    self.showPanel(
                        at: CGPoint(x: self.trigger.buttonFrame.maxX, y: self.trigger.buttonFrame.midY),
                        scopedActionID: chip.id
                    )
                    return
                }
                self.showPanel(
                    at: CGPoint(x: self.trigger.buttonFrame.maxX, y: self.trigger.buttonFrame.midY),
                    scopedActionID: chip.id
                )
            }
        }

        syncPinnedTriggerUI()

        tabCompletions.configuration = { [weak model] in
            model?.tabCompletionsConfiguration() ?? ("", [])
        }

        monitor.onChange = { [weak self] target in
            guard let self, let model = self.model else { return }
            self.lastTarget = target
            if let target {
                if target.selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.rememberedSelection = nil
                } else {
                    self.rememberedSelection = target
                }
            }
            model.selectedText = target?.selectedText ?? ""
            model.sourceApp = target?.sourceApp
            if self.panel?.isVisible == true {
                self.tabCompletions.clearOffer()
                self.trigger.hide()
            } else {
                self.tabCompletions.update(target: target)
                self.trigger.update(target: target)
            }
        }

        requestAccessibilityAndStart()
        ScreenpipeSupervisor.start(projectRoot: CaretPaths.projectRoot)
        startInlineCompletion(model: model)
    }

    /// Starts the one bridge process and points both inline completion and
    /// actions at it. A launch failure is surfaced, never replaced by a mock.
    private func startInlineCompletion(model: Model) {
        let provider = CoreBridgeProvider(capture: capture)
        provider.onActionOffer = { [weak self] _ in
            Task { @MainActor in self?.syncActionOffers() }
        }
        provider.onActionsChanged = { [weak self] in
            Task { @MainActor in self?.syncActionOffers() }
        }
        provider.onActionStateChange = { [weak self] proposalID, state in
            Task { @MainActor in
                self?.model?.updateActionState(proposalID, state)
            }
        }
        bridge = provider

        model.onRunAction = { [weak self] proposalID in
            self?.bridge?.runAction(proposalID: proposalID)
        }

        let coordinator = InlineCompletionCoordinator(provider: provider, capture: capture)
        coordinator.onStatusChange = { [weak self] (reason: InlineDisabledReason?) in
            guard let self else { return }
            let text = self.bridge?.unavailableText ?? reason?.statusText
            self.statusBar.setInlineStatus(text)
            self.model?.backendStatus = text ?? ""
        }
        coordinator.onContextInvalidated = { [weak self] in
            // The field these offers were prepared against is gone.
            self?.bridge?.invalidateContextualOffers()
        }
        coordinator.onSelectChoice = { [weak self] index in
            Task { @MainActor in self?.runVisibleChoice(index: index) }
        }
        coordinator.start()
        inlineCompletion = coordinator
    }

    private func syncActionOffers() {
        guard let bridge, let model else { return }
        model.setActionOffers(bridge.visibleExecutableActions)
        // Blocker 2: an ambient offer arriving while the panel is closed used
        // to claim Cmd-1..3 from whatever app the user was typing in. Caret
        // owns those chords only while its own panel is on screen showing the
        // choices they address.
        let visible = panel?.isVisible == true
        inlineCompletion?.setVisibleChoiceCount(visible ? min(3, model.runnableOffers.count) : 0)
    }

    /// Cmd-1..3 while Caret's own picker is showing choices. Bound only for as
    /// long as those choices are visible, so the host app keeps the chord the
    /// rest of the time.
    private func runVisibleChoice(index: Int) {
        guard let model else { return }
        // Rechecked here, not just when the count was published: the panel can
        // close between the tap consuming the key and this running.
        guard panel?.isVisible == true else { return }
        let choices = model.runnableOffers
        // The tap only consumed the key because this many choices were
        // visible; if that changed in between, the host should have had it.
        guard index < choices.count else { return }
        model.runOfferedAction(choices[index])
    }

    private func syncPinnedTriggerUI() {
        trigger.setPinnedActions(model?.pinnedChips ?? [])
        if panel?.isVisible != true {
            trigger.update(target: lastTarget)
        }
    }

    /// B-04: the pinned chord used to run an action outright, with no visible
    /// offer and no way to suppress the host's own shortcut. It now opens the
    /// scoped panel -- the same thing clicking the pinned icon does -- so the
    /// keyboard and mouse paths agree and nothing executes without the user
    /// seeing a prepared offer first.
    private func runPinnedAction(slot: Int) {
        guard let model, let actionID = model.pinStore.actionID(forSlot: slot) else { return }
        showPanel(
            at: CGPoint(x: trigger.buttonFrame.maxX, y: trigger.buttonFrame.midY),
            scopedActionID: actionID
        )
    }

    func togglePanel(at point: CGPoint) {
        if panel?.isVisible == true {
            hidePanel()
        } else {
            showPanel(at: point, scopedActionID: nil)
        }
    }

    private func freshTargetForGatewayAction(actionID: String) -> SelectionTarget? {
        if actionID == "translate" {
            return SkillActionInput.translateTarget(
                lastTarget: lastTarget,
                panelContextTarget: panelContextTarget,
                rememberedSelection: rememberedSelection
            )
        }
        if panel?.isVisible == true,
           let panelContextTarget,
           SkillActionRunner.hasInput(panelContextTarget) {
            return panelContextTarget
        }
        monitor.refreshNow()
        guard let target = lastTarget, SkillActionRunner.hasInput(target) else { return nil }
        return target
    }

    private static func panelDimensions(scopedActionID: String?) -> (width: CGFloat, height: CGFloat) {
        let isGateway = scopedActionID.map { GatewaySkillActions.contains($0) } == true
        if isGateway {
            return (ActionsMenuMetrics.gatewayWidth, ActionsMenuMetrics.gatewayPanelHeight)
        }
        return (ActionsMenuMetrics.width, ActionsMenuMetrics.browsePanelHeight)
    }

    private func resyncVisiblePanelFrame() {
        guard panel?.isVisible == true else { return }
        let scopedActionID = model?.scopedActionID
        let dimensions = Self.panelDimensions(scopedActionID: scopedActionID)
        panel?.setFrame(
            near: lastPanelPoint,
            width: dimensions.width,
            height: dimensions.height
        )
    }

    private func showPanel(at point: CGPoint, scopedActionID: String?) {
        lastPanelPoint = point
        if let target = lastTarget, SkillActionRunner.hasInput(target) {
            panelContextTarget = target
        }
        model?.preparePanel(scopedActionID: scopedActionID)
        trigger.hide()
        // Pause before presenting: presenting makes Caret frontmost, and the
        // next capture tick would otherwise read Caret's own focus and
        // invalidate the offers this panel is showing.
        inlineCompletion?.setPaused(true)
        let dimensions = Self.panelDimensions(scopedActionID: scopedActionID)
        let stealsFocus = scopedActionID.map { GatewaySkillActions.contains($0) } != true
        panel?.present(
            at: point,
            width: dimensions.width,
            height: dimensions.height,
            makeKey: stealsFocus
        )
        syncActionOffers()
        installClickOutside()
        if let id = scopedActionID,
           GatewaySkillActions.contains(id),
           let action = model?.action(id: id),
           let model {
            model.run(action, skill: nil)
        }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        inlineCompletion?.setPaused(false)
        inlineCompletion?.setVisibleChoiceCount(0)
        panel?.resignKey()
        removeClickOutside()
        model?.clearPanelScope()
        panelContextTarget = nil
        restoreTypingAppFocus()
        monitor.refreshNow()
        trigger.update(target: lastTarget)
        tabCompletions.update(target: lastTarget)
    }

    /// Caret must not stay frontmost after the panel closes or inline Tab completions stop.
    private func restoreTypingAppFocus() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier == ProcessInfo.processInfo.processIdentifier
        else { return }
        if let pid = lastTarget?.focusedProcessID,
           pid != ProcessInfo.processInfo.processIdentifier,
           let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [.activateIgnoringOtherApps])
            return
        }
        NSApp.hide(nil)
    }

    private func installClickOutside() {
        removeClickOutside()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let screenPoint = NSEvent.mouseLocation
                if let panel = self.panel, panel.isVisible, panel.frame.contains(screenPoint) {
                    return
                }
                if self.trigger.buttonFrame.contains(screenPoint) {
                    return
                }
                self.hidePanel()
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
        let closing = notification.object as? NSWindow
        guard closing === settingsWindow || closing === debugWindow else { return }
        if closing === settingsWindow {
            SettingsMainMenu.uninstall()
        }
        let otherVisible = (closing === settingsWindow && debugWindow?.isVisible == true)
            || (closing === debugWindow && settingsWindow?.isVisible == true)
        if !otherVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKey.unregister()
        monitor.stop()
        inlineCompletion?.stop()
        let bridge = self.bridge
        Task { await bridge?.shutdown() }
        trustTimer?.invalidate()
        removeClickOutside()
        ScreenpipeSupervisor.stop()
    }

    private func requestAccessibilityAndStart() {
        if AXHelpers.isTrusted() {
            AccessibilityTrust.noteTrustedIfNeeded()
            startInputCaptureAndMonitor()
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
                self?.startInputCaptureAndMonitor()
            }
        }
    }

    private func startInputCaptureAndMonitor() {
        TypingPrefixCapture.shared.onChange = { [weak self] in
            Task { @MainActor in
                guard let self, self.panel?.isVisible != true else { return }
                self.monitor.refreshNow()
                self.tabCompletions.update(target: self.lastTarget)
                self.trigger.update(target: self.lastTarget)
            }
        }
        TypingPrefixCapture.shared.start()
        monitor.start()
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
        if let hosting = settingsWindow?.contentView as? NSHostingView<CaretSettingsView> {
            hosting.rootView = CaretSettingsView(model: model)
        } else {
            settingsWindow?.contentView = NSHostingView(rootView: CaretSettingsView(model: model))
        }
        NSApp.setActivationPolicy(.regular)
        SettingsMainMenu.install()
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func showDebugWindow() {
        hidePanel()

        if debugWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Caret Debug"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            debugWindow = window
        }

        debugWindow?.contentView = NSHostingView(rootView: CaretDebugView())
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow?.makeKeyAndOrderFront(nil)
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


/// One action offer and its outcome.
///
/// Running is shown the moment acceptance is claimed, so the panel never looks
/// dead while a workflow is in flight, and a result only ever repeats what the
/// core reported.
struct CaretActionOfferRow: View {
    let offer: CaretActionOffer
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(offer.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(offer.isLocalMeetingDemo ? nil : 1)
                Spacer(minLength: 4)
                statusBadge
            }
            if !offer.effect.isEmpty {
                Text(offer.effect)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(offer.isLocalMeetingDemo ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if offer.isLocalMeetingDemo {
                Text("Local demo using synthetic data. Accepting writes only local demo holds. No message is sent and no external calendar is changed.")
                    .font(.system(size: 11, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                if case .offered = offer.state {
                    ForEach(Array(offer.evidence.enumerated()), id: \.offset) { _, item in
                        Text(item)
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            detail
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if offer.isExecutable { run() } }
    }

    @ViewBuilder private var statusBadge: some View {
        switch offer.state {
        case .offered:
            Text(offer.isExecutable ? (offer.isLocalMeetingDemo ? "Local demo ready" : "Ready") : "Unavailable")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(offer.isExecutable ? .secondary : .tertiary)
        case .running:
            // No spinner animation: this row appears on the keyboard path and
            // a spinner starting mid-keystroke reads as lag.
            Text(offer.isLocalMeetingDemo ? "Running local demo…" : "Running…")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .succeeded(_, _, let scope):
            // "Draft ready" and "Done" are different claims. A draft-only run
            // completed its own job without sending or scheduling anything.
            Label(scope.label, systemImage: scope == .draftOnly ? "doc.text" : "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(scope == .draftOnly ? Color.secondary : Color.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.orange)
        case .cancelled:
            Text("Stopped")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        case .unavailable:
            Text("Unavailable")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private var detail: some View {
        switch offer.state {
        case .cancelled(let summary):
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        case .succeeded(let summary, let evidence, let scope):
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            let rows = CaretActionOffer.visibleEvidence(evidence, scope: scope)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                // Wraps rather than truncating. The adapter's no-effect
                // disclosure runs past 100 characters, and a single clipped
                // line would cut it mid-sentence -- exactly the sentence that
                // stops a draft reading as a booking.
                Text(item)
                    .font(.system(size: 10))
                    .foregroundStyle(scope == .draftOnly ? Color.primary.opacity(0.75) : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed(let summary):
            Text(summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        case .unavailable(let reason):
            Text(reason)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        case .offered:
            if let text = offer.unavailabilityText {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        case .running:
            EmptyView()
        }
    }
}

/// A plain explanatory row. Used where the panel would otherwise be blank.
struct CaretActionStatusRow: View {
    enum Tone { case unavailable }

    let title: String
    let detail: String
    let tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

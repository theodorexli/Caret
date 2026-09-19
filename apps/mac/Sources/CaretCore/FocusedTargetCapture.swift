import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Reads the focused text field through the Accessibility API and turns it into
/// the snapshot the core expects.
///
/// The core cannot see the screen, so anything this cannot actually determine
/// is reported as a suppression rather than as a confident `false`.
public struct HostContext: Equatable, Sendable {
    public let pid: pid_t
    public let bundleID: String
    public let localizedName: String

    public init(pid: pid_t, bundleID: String, localizedName: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.localizedName = localizedName
    }
}

public final class FocusedTargetCapture {
    public struct Configuration: Sendable {
        public var excludedBundleIDs: Set<String>
        /// Clipboard reading stays off until the app turns it on. Until then
        /// every frame carries `{"available": false}`.
        public var clipboardEnabled: Bool
        public var nearbyTextLimit: Int

        public init(
            excludedBundleIDs: Set<String> = [],
            clipboardEnabled: Bool = false,
            nearbyTextLimit: Int = CoreLimits.nearbyTextUnits
        ) {
            self.excludedBundleIDs = excludedBundleIDs
            self.clipboardEnabled = clipboardEnabled
            self.nearbyTextLimit = nearbyTextLimit
        }
    }

    public enum Suppression: Error, Equatable, Sendable {
        case accessibilityNotTrusted
        case noFocusedApplication
        case noFocusedElement
        case unsupportedRole(String)
        case secureField
        case appExcluded(String)
        case valueUnreadable
        case selectionUnreadable
        /// The element the system-wide fallback returned belongs to a process
        /// other than the frontmost app. Reporting it would attribute the text
        /// to the wrong application.
        case processMismatch(elementPID: pid_t, frontmostPID: pid_t)
        /// A composing input source is active. Whether it is composing right
        /// now is not observable through the attributes read here, and a wrong
        /// answer would let an edit land inside a composition.
        case imeCompositionUnobservable(inputSource: String)
        case windowUnavailable
        case nearbyTextUnbounded(NearbyTextWindow.Failure)
    }

    public enum Outcome: Equatable, Sendable {
        case captured(InputSnapshot)
        /// Nothing changed since the last capture, so there is nothing new to
        /// judge. Any live offer stays valid.
        case unchanged
        /// No usable reading. `invalidatesPriorContext` is true whenever the
        /// reason means a previously seen field is no longer the one in front
        /// of the user, so the caller must drop any visible offer.
        case suppressed(Suppression, invalidatesPriorContext: Bool)
    }

    public var configuration: Configuration

    /// Everything that makes one reading distinct from another. Dedupe on the
    /// content digest alone would suppress a caret move, a selection change, or
    /// a switch to a different field or app holding identical text.
    private struct DedupeKey: Equatable {
        let pid: pid_t
        let windowToken: String
        let elementToken: String
        let selection: TextSelection
        let caret: Int
        let contentDigest: String
    }

    private let lock = NSLock()
    private var revision = 0
    private var lastKey: DedupeKey?
    private let elements = AXIdentityRegistry(prefix: "el")
    private let windows = AXIdentityRegistry(prefix: "win")

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    private static let supportedRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
    ]

    /// One reading of the focused field.
    public func capture(now: Date = Date()) -> Outcome {
        switch resolveFocusedField() {
        case .failure(let suppression):
            lock.lock()
            let hadContext = lastKey != nil
            if invalidatesPriorContext(suppression) { lastKey = nil }
            lock.unlock()
            return .suppressed(suppression, invalidatesPriorContext: hadContext && invalidatesPriorContext(suppression))
        case .success(let field):
            return snapshot(from: field, now: now)
        }
    }

    /// The live field as it is right now, for the owner of acceptance to hand
    /// to `InsertionGuard`. Tokens come from the same registries the offer's
    /// target was built with, so a different field that merely looks the same
    /// carries a different token and the guard rejects it.
    public func liveTarget(allowingCaretPanelForPID hostPID: pid_t? = nil) -> InsertionGuard.LiveField? {
        guard case .success(let field) = resolveFocusedField(hostPIDWhenCaretIsFrontmost: hostPID) else { return nil }
        return InsertionGuard.LiveField(
            target: TargetIdentity(
                pid: field.pid,
                bundleID: field.bundleID,
                windowID: field.windowToken,
                elementID: field.elementToken,
                elementRevision: UTF16Text.digest(field.value)
            ),
            value: field.value,
            selection: field.selection,
            secure: false
        )
    }

    /// Drops the remembered reading so the next capture is treated as new.
    /// Call after applying an edit or after dismissing an offer.
    public func invalidate() {
        lock.lock()
        lastKey = nil
        lock.unlock()
    }

    /// One monotonic revision shared with ambient `capture()`, so explicit
    /// invoke and ambient ticks cannot reuse a revision the router has seen.
    private func nextRevision() -> Int {
        lock.lock()
        revision += 1
        let current = revision
        lock.unlock()
        return current
    }

    /// A frame for an explicit panel action. Capture stays paused; this does
    /// not go through the ambient dedupe path.
    public func explicitActionFrame(host: HostContext, complaint: String, now: Date = Date()) -> ContextFrame {
        let trimmed = complaint.trimmingCharacters(in: .whitespacesAndNewlines)
        let field: FocusedField?
        if case .success(let resolved) = resolveFocusedField(hostPIDWhenCaretIsFrontmost: host.pid),
           resolved.pid == host.pid {
            field = resolved
        } else {
            field = nil
        }

        let rawText: String
        if !trimmed.isEmpty {
            rawText = trimmed
        } else if let field {
            rawText = field.value
        } else {
            rawText = ""
        }
        let text = Self.bound(rawText, limit: configuration.nearbyTextLimit)
        let length = UTF16Text.length(text)
        let usedField = trimmed.isEmpty && field != nil
        let target: TargetIdentity
        if usedField, let field {
            target = TargetIdentity(
                pid: field.pid,
                bundleID: field.bundleID,
                windowID: field.windowToken,
                elementID: field.elementToken,
                elementRevision: UTF16Text.digest(field.value)
            )
        } else {
            target = TargetIdentity(
                pid: host.pid,
                bundleID: host.bundleID,
                windowID: "",
                elementID: "",
                elementRevision: ""
            )
        }

        let snapshot = InputSnapshot(
            revision: nextRevision(),
            capturedAt: now,
            target: target,
            role: field?.role ?? "",
            nearbyText: text,
            textOffset: 0,
            caret: length,
            selection: TextSelection(start: length, end: length),
            valueLength: length
        )

        var clipboard = ClipboardContext.unavailable
        if let paste = NSPasteboard.general.string(forType: .string) {
            clipboard = ClipboardContext(
                available: true,
                text: Self.bound(paste, limit: CoreLimits.clipboardUnits),
                capturedAt: nil
            )
        }

        return ContextFrame(
            snapshot: snapshot,
            permissions: permissions(),
            clipboard: clipboard,
            sources: [
                SourceRecord(name: "explicit_invoke", available: true, capturedAt: nil, detail: host.bundleID),
                SourceRecord(name: "frontmost_app", available: true, capturedAt: nil, detail: host.localizedName),
                SourceRecord(name: "clipboard", available: clipboard.available, capturedAt: nil),
            ]
        )
    }

    private static func bound(_ text: String, limit: Int) -> String {
        let units = UTF16Text.length(text)
        guard units > limit else { return text }
        if let sliced = UTF16Text.slice(text, start: 0, end: limit) { return sliced }
        if limit > 0, let sliced = UTF16Text.slice(text, start: 0, end: limit - 1) { return sliced }
        return ""
    }

    // MARK: - Resolution

    private struct FocusedField {
        let pid: pid_t
        let bundleID: String
        let role: String
        let value: String
        let selection: TextSelection
        let caret: Int
        let elementToken: String
        let windowToken: String
    }

    /// A suppression that means the field the user is in is not the one we last
    /// reported, so a visible offer must come down.
    private func invalidatesPriorContext(_ suppression: Suppression) -> Bool {
        switch suppression {
        case .accessibilityNotTrusted, .noFocusedApplication, .noFocusedElement,
             .unsupportedRole, .secureField, .appExcluded, .processMismatch,
             .valueUnreadable, .selectionUnreadable, .windowUnavailable:
            return true
        case .imeCompositionUnobservable, .nearbyTextUnbounded:
            return false
        }
    }

    private func resolveFocusedField(hostPIDWhenCaretIsFrontmost hostPID: pid_t? = nil) -> Result<FocusedField, Suppression> {
        guard AXIsProcessTrusted() else { return .failure(.accessibilityNotTrusted) }
        guard var app = NSWorkspace.shared.frontmostApplication else { return .failure(.noFocusedApplication) }
        // The action picker owns focus during acceptance. Read the original host
        // only in that case; a switch to any other app must still fail validation.
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier, let hostPID {
            guard let host = NSRunningApplication(processIdentifier: hostPID), !host.isTerminated else {
                return .failure(.noFocusedApplication)
            }
            app = host
        }
        let frontmostPID = app.processIdentifier
        let bundleID = app.bundleIdentifier ?? ""
        if configuration.excludedBundleIDs.contains(bundleID) { return .failure(.appExcluded(bundleID)) }

        let appElement = AXUIElementCreateApplication(frontmostPID)
        guard let element = Self.copyElement(appElement, kAXFocusedUIElementAttribute as CFString)
            ?? Self.copyElement(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString)
        else { return .failure(.noFocusedElement) }

        // The system-wide fallback can return an element owned by another
        // process, so the element's own pid decides what we report.
        var elementPID: pid_t = 0
        guard AXUIElementGetPid(element, &elementPID) == .success else {
            return .failure(.processMismatch(elementPID: 0, frontmostPID: frontmostPID))
        }
        guard elementPID == frontmostPID else {
            return .failure(.processMismatch(elementPID: elementPID, frontmostPID: frontmostPID))
        }

        let role = Self.stringValue(element, kAXRoleAttribute as CFString) ?? ""
        let subrole = Self.stringValue(element, kAXSubroleAttribute as CFString) ?? ""
        if role == "AXSecureTextField" || subrole == "AXSecureTextField" { return .failure(.secureField) }
        guard Self.supportedRoles.contains(role) else { return .failure(.unsupportedRole(role)) }

        if let source = Self.composingInputSourceName() {
            return .failure(.imeCompositionUnobservable(inputSource: source))
        }

        guard let value = Self.stringValue(element, kAXValueAttribute as CFString) else {
            return .failure(.valueUnreadable)
        }
        guard let range = Self.selectedRange(element) else { return .failure(.selectionUnreadable) }
        guard let window = Self.copyElement(element, kAXWindowAttribute as CFString)
            ?? Self.copyElement(element, kAXTopLevelUIElementAttribute as CFString)
            ?? Self.copyElement(appElement, kAXFocusedWindowAttribute as CFString)
        else { return .failure(.windowUnavailable) }

        let total = UTF16Text.length(value)
        let selection = TextSelection(
            start: min(max(0, range.location), total),
            end: min(max(0, range.location + range.length), total)
        )

        lock.lock()
        let elementToken = elements.token(for: element)
        let windowToken = windows.token(for: window)
        lock.unlock()

        return .success(FocusedField(
            pid: frontmostPID,
            bundleID: bundleID,
            role: role,
            value: value,
            selection: selection,
            caret: selection.end,
            elementToken: elementToken,
            windowToken: windowToken
        ))
    }

    private func snapshot(from field: FocusedField, now: Date) -> Outcome {
        let contentDigest = UTF16Text.digest(field.value)
        let key = DedupeKey(
            pid: field.pid,
            windowToken: field.windowToken,
            elementToken: field.elementToken,
            selection: field.selection,
            caret: field.caret,
            contentDigest: contentDigest
        )

        lock.lock()
        if lastKey == key {
            lock.unlock()
            return .unchanged
        }
        lock.unlock()

        let window: NearbyTextWindow
        switch NearbyTextWindow.around(
            value: field.value,
            caret: field.caret,
            selection: field.selection,
            limit: configuration.nearbyTextLimit
        ) {
        case .success(let built): window = built
        case .failure(let failure): return .suppressed(.nearbyTextUnbounded(failure), invalidatesPriorContext: false)
        }

        let currentRevision = nextRevision()
        lock.lock()
        lastKey = key
        lock.unlock()

        return .captured(InputSnapshot(
            revision: currentRevision,
            capturedAt: now,
            target: TargetIdentity(
                pid: field.pid,
                bundleID: field.bundleID,
                windowID: field.windowToken,
                elementID: field.elementToken,
                elementRevision: contentDigest
            ),
            role: field.role,
            nearbyText: window.text,
            textOffset: window.offset,
            caret: field.caret,
            selection: field.selection,
            secure: false,
            imeComposing: false,
            appExcluded: false,
            valueLength: UTF16Text.length(field.value)
        ))
    }

    // MARK: - Supporting context

    public func clipboardContext(now: Date = Date()) -> ClipboardContext {
        guard configuration.clipboardEnabled else { return .unavailable }
        guard let text = NSPasteboard.general.string(forType: .string) else { return .unavailable }
        guard UTF16Text.length(text) <= CoreLimits.clipboardUnits else { return .unavailable }
        return ClipboardContext(available: true, text: text, capturedAt: now)
    }

    public func permissions() -> Permissions {
        Permissions(accessibility: AXIsProcessTrusted())
    }

    public func sourceRecords() -> [SourceRecord] {
        [SourceRecord(
            name: "clipboard",
            available: configuration.clipboardEnabled,
            detail: configuration.clipboardEnabled ? "" : "not enabled in settings"
        )]
    }

    // MARK: - Accessibility reads

    private static func stringValue(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value else { return nil }
        return value as? String
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Names the active input source when it is one that composes. `nil` means
    /// a plain keyboard layout, where no composition can be in progress.
    private static func composingInputSourceName() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        guard let typePointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return nil }
        let type = Unmanaged<CFString>.fromOpaque(typePointer).takeUnretainedValue() as String
        guard type == (kTISTypeKeyboardInputMode as String) else { return nil }
        guard let idPointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return "unknown input mode"
        }
        return Unmanaged<CFString>.fromOpaque(idPointer).takeUnretainedValue() as String
    }
}

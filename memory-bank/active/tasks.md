# Current Task: translate-selection-or-clipboard

**Complexity:** Level 1

## Fix

- Translate shared the gateway path (selection → caret line → clipboard). A missing or stale target, or a focused line with no selection, made it look clipboard-only — or used the caret line instead of the clipboard.
- Translate now uses a non-empty selection if one exists, otherwise the clipboard. It never uses the caret line.
- A remembered selection is kept when the monitor publishes nil because Caret is frontmost. A live empty selection still means clipboard.

## Files

- `apps/mac/Sources/Caret/SkillActionRunner.swift` — `SkillActionInput.sourceText` / `translateTarget`; runner uses them
- `apps/mac/Sources/Caret/CaretApp.swift` — `rememberedSelection`; translate target resolution
- `apps/mac/Tests/SkillActionInputTests.swift` — selection vs clipboard vs caret line

## QA

**Result:** PASS

- Completeness holds: Translate takes a non-empty selection, otherwise the clipboard, and never the caret line. Other gateway skills still use the caret-line fallback.
- Advisories (non-blocking): Translate skips `refreshNow()`; `rememberedSelection` is kept on every nil publish, not only Caret-frontmost. Neither breaks the two happy-path use cases.

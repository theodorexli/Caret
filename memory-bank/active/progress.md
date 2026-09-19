# Progress

Fix Translate so it translates the current selection when text is selected, and the clipboard when nothing is selected.

**Complexity:** Level 1

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Restated and confirmed intent with the operator
    - Classified the task as Level 1 (single-component input-source correction)
    - Wrote ephemeral memory-bank files
* Decisions made
    - Treat this as a bug fix of Translate's source text, not a new translation feature
    - Other skill actions keep their existing input rules
* Insights
    - `SkillActionRunner` already prefers selection, then caret line, then clipboard for every gateway skill; the live Translate path may still be losing the selection (panel focus / `freshTargetForGatewayAction`) or treating Translate as clipboard-only

## 2026-09-19 - BUILD - COMPLETE

* Work completed
    - Added `SkillActionInput` so Translate uses selection or clipboard and never the caret line
    - Wired `rememberedSelection` so a selection survives Caret becoming frontmost
    - Added `SkillActionInputTests`; `make check` passed
* Decisions made
    - Other gateway skills keep the caret-line fallback
    - A live empty selection means clipboard, not a remembered phrase
* Insights
    - The shared gateway path hid this: no selection still had a caret line, and a frontmost Caret published a nil target

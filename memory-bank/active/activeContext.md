# Active Context

## Current Task: translate-selection-or-clipboard
**Phase:** QA - COMPLETE (PASS)

## What Was Done
- Translate now takes a non-empty selection if one exists, otherwise the clipboard. Other gateway skills still use the caret line.
- `SkillActionInput` is the testable resolver. Caret keeps `rememberedSelection` when the monitor goes nil because Caret is frontmost.
- `make check` passed: Python 300 tests (4 skipped), Swift CaretTests + CaretCoreTests, pin check, xcodebuild Debug.

## Next Step
- Level 1 wrap-up: persistent files need no update; commit `chore: completed translate-selection-or-clipboard`.

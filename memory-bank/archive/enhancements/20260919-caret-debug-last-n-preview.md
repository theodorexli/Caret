---
task_id: caret-debug-last-n-preview
complexity_level: 2
date: 2026-09-19
status: completed
---

# TASK ARCHIVE: Caret menu debug last-N preview

## SUMMARY

The Caret status-bar menu gained a Debug item that opens a small window with truncated last-2 snippets of windows (recency), minutes (time), and clipboard so a person can see what Caret currently sees. Inference last-N hard-fail is unchanged.

## REQUIREMENTS

- Add Debug to the Caret menu.
- Show last two items of each last-N kind: windows, minutes, clipboard.
- Short preview only: app, title, timestamp, truncated text. No full OCR or accessibility structure.
- Use the same lease-backed last-N source as Caret, not a parallel client.
- Do not change last-N hard-fail for inference callers.

## IMPLEMENTATION

`debug_preview` calls `last_n_windows`, `last_n_minutes`, and `last_n_clipboard` independently, catches `ValueError` per slice, and returns `{n, windows, minutes, clipboard}` with `{ok, items}` or `{ok, error, items}`. Debug calls last-N with `include_structure=False` and minutes `record_cap` so the glance does not hydrate discarded rows. CLI `history-debug` prints that JSON and exits 0 when sections fail.

Swift `HistoryDebug` builds `python3 -m caret history-debug --lease <root>/.local/screenpipe-lease.json`, formats the payload, and loads via `/usr/bin/env` with the ScreenpipeSupervisor Homebrew PATH prefix. Missing project root is a display string. `StatusBarController` adds Debug…; `AppDelegate.showDebugWindow` hosts `CaretDebugView`.

Key files: `caret/screenpipe.py`, `caret/__main__.py`, `tests/test_history_debug.py`, `HistoryDebug.swift`, `CaretDebugView.swift`, `StatusBarController.swift`, `CaretApp.swift`, `HistoryDebugTests.swift`, `Caret.xcodeproj/project.pbxproj`, `README.md`.

## TESTING

- Python `HistoryDebugTests`: truncated last-2, minutes cap, per-slice fail, missing lease, CLI JSON exit 0.
- `make check`: 34 Python tests, pin check, SwiftPM build.
- `xcodebuild test` `HistoryDebugTests`: 3 passed.
- `/niko-preflight` PASS WITH ADVISORY (Cursor Grok 4.6 High Fast).
- `/niko-qa` PASS (Cursor Grok 4.6 High Fast). Advisories: success sections omit `error`; unused `(none)` branch; `load` blocks on appear.

## LESSONS LEARNED

- `last_n_minutes` is a time window that hydrates accessibility structure for every hit. A glance that reuses it must skip structure and cap records, or it is not a glance.
- App-spawned `python3` should reuse the ScreenpipeSupervisor PATH/`env`, not assume a shell PATH.

## PROCESS IMPROVEMENTS

Preflight's minutes-cost advisory was the useful one; applying the cheap skip/cap in build avoided a stall without a replan.

## TECHNICAL IMPROVEMENTS

If Debug had been assumed from the start, last-N would already expose a cheap peek (`include_structure=False`, `record_cap`) and the app would show that peek instead of growing a second client. That is what shipped.

## NEXT STEPS

None. A later pass could share the PATH helper with ScreenpipeSupervisor and move `HistoryDebug.load` off the appear path.

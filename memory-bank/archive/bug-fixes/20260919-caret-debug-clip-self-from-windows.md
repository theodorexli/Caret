---
task_id: caret-debug-clip-self-from-windows
complexity_level: 1
date: 2026-09-19
status: completed
---

# TASK ARCHIVE: caret-debug-clip-self-from-windows

## SUMMARY

Opening Caret Debug focused a window titled `Caret Debug`, which Screenpipe recorded as the newest window. Debug last-N windows now skip that title during the distinct-window walk so the newest remaining row is the window that was in view before Debug opened.

## REQUIREMENTS

- Clip the Debug window out of Debug last-N windows.
- Newest remaining window is the one in view before Debug launched.
- Minutes, clipboard, and inference last-N stay unchanged.

## IMPLEMENTATION

`last_n_windows` gained optional `skip_titles`. `debug_preview` passes `{DEBUG_WINDOW_TITLE}` (`Caret Debug`, matching `showDebugWindow`). Skip happens before the count cap so last-2 still fills with other windows.

Key files: `caret/screenpipe.py`, `tests/test_history_debug.py`.

## TESTING

- New test: newest OCR row titled Caret Debug is omitted; Safari then Cursor remain; minutes still include Debug.
- `make test`: 301 passed, 4 skipped.
- `/niko-qa` PASS (Cursor Grok 4.6 High Fast).

## LESSONS LEARNED

- Distinct-window walk must skip before the count cap, or last-2 becomes last-1 after the clip.
- Title-only skip is enough because Swift sets `window.title = "Caret Debug"` and Screenpipe stores that as `window_name`.

## PROCESS IMPROVEMENTS

None. L1 has no reflect/archive phase; this archive exists because the operator asked for it.

## TECHNICAL IMPROVEMENTS

None.

## NEXT STEPS

None.

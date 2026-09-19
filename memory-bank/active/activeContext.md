# Active Context

## Current Task: Caret menu debug last-N preview
**Phase:** REFLECT COMPLETE

## What Was Done
- Added `debug_preview` and `history-debug` so last-2 windows / minutes / clipboard snippets report per-slice errors.
- Debug last-N skips accessibility structure and caps minutes records.
- Caret menu Debug… opens a small window that runs `python3 -m caret history-debug` via `/usr/bin/env` and Homebrew PATH.
- `make check` 34 Python tests + SwiftPM build; `xcodebuild test` HistoryDebugTests 3 passed.
- QA PASS. Wrote reflection. Operator already requested archive then PR.

## Next Step
- `/niko-archive` then open a draft PR.

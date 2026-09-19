# Active Context

## Current Task: Caret menu debug last-N preview
**Phase:** BUILD - COMPLETE

## What Was Done
- Added `debug_preview` and `history-debug` so last-2 windows / minutes / clipboard snippets report per-slice errors.
- Debug last-N skips accessibility structure and caps minutes records.
- Caret menu Debug… opens a small window that runs `python3 -m caret history-debug` via `/usr/bin/env` and Homebrew PATH.
- `make check` 34 Python tests + SwiftPM build; `xcodebuild test` HistoryDebugTests 3 passed.

## Files created or modified
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/caret/screenpipe.py`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/caret/__main__.py`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/tests/test_history_debug.py`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/apps/mac/Sources/Caret/HistoryDebug.swift`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/apps/mac/Sources/Caret/CaretDebugView.swift`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/apps/mac/Sources/Caret/StatusBarController.swift`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/apps/mac/Sources/Caret/CaretApp.swift`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/apps/mac/Tests/HistoryDebugTests.swift`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/Caret.xcodeproj/project.pbxproj`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/README.md`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/memory-bank/productContext.md`
- `/Users/tex/worktrees/theodorexli/hackathon-2026-09-19/hackathon-2026-09-19-caret-debug/memory-bank/techContext.md`

## Key implementation decisions
- Reuse `last_n_*` with `include_structure=False` and minutes `record_cap`; do not add a Swift Screenpipe client.
- `history-debug` exits 0 when sections fail so the window can show the errors.
- Spawn copies ScreenpipeSupervisor PATH/`env`.

## Deviations from Plan
- Added optional `include_structure` / `record_cap` on last-N (defaults keep inference the same) per preflight advisory.
- Added `HistoryDebug.missingRootMessage` / `load` so the missing-root path is testable.

## Next Step
- Commit, then spawn QA with `cursor-grok-4.6-xhigh-fast`.

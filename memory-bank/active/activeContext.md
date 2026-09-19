# Active Context

## Current Task: caret-screenpipe-history
**Phase:** BUILD - COMPLETE

## What Was Done
- Operator asked for super-abridged TDD (happy paths only).
- Pin launch now stores clipboard and listens on 3031 (`--disable-audio` so spawn is not blocked by mic TCC).
- `last_n_minutes` / `last_n_windows` are newest-first; `last_n_clipboard` + `history-clipboard` added.
- `ScreenpipeSupervisor` starts off the main thread, writes `.local/screenpipe-lease.json`, stops on terminate.
- Python: 16 tests OK. `swift build --package-path apps/mac` OK. `xcodebuild test` blocked here by an unsigned Xcode license.

## Next Step
- QA via Cursor Grok High Fast, then reflect, archive, and open a PR.

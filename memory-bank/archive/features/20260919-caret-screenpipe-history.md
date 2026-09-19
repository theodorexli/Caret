---
task_id: caret-screenpipe-history
complexity_level: 3
date: 2026-09-19
status: completed
---

# TASK ARCHIVE: caret-screenpipe-history

## SUMMARY

`3db8f16` pinned Screenpipe 0.4.50 and added a last-N client that reads a lease; Caret.app did not launch the process. This task makes Caret.app launch and supervise that pin on port 3031 with clipboard storage on, write `.local/screenpipe-lease.json`, and expose last-N windows (most-recently-active), last-N minutes (all activity), and last-N clipboard, all newest-first.

## REQUIREMENTS

- Caret.app launches and supervises published `screenpipe@0.4.50` and writes the existing lease schema.
- The launched process stores clipboard history.
- One Caret history interface: windows, minutes, clipboard; newest-first.
- Missing lease, wrong version, unreachable gatherer, or empty last-N is a hard failure.
- Do not launch `packages/screenpipe`, copy `ee/`, or claim Caret Accessibility covers the Screenpipe binary.

## IMPLEMENTATION

Python last-N talks only to the lease. Caret always spawns the pin on `--port 3031` so it does not attach to leftover launchd `:3030` (same version, clipboard off). Pin argv also has `--disable-clipboard-capture false` and `--disable-audio` (mic TCC otherwise blocks startup).

`ScreenpipeSupervisor` reads `caret/screenpipe_pin.json` via `CaretPaths.projectRoot`, starts `Process` off the main thread, waits for `/health` version match, writes the lease, and terminates the child on quit. A health timeout throws; no lease is written.

`last_n_minutes` and `last_n_windows` keep `/search` descending order (no reverse). `last_n_clipboard` searches `content_type=input` with limit 200 and keeps `event_type == clipboard`. CLI: `history-clipboard --count --lease`.

Key files: `caret/screenpipe_pin.json`, `caret/screenpipe.py`, `caret/__main__.py`, `apps/mac/Sources/Caret/ScreenpipeSupervisor.swift`, `CaretApp.swift`, `Caret.xcodeproj/project.pbxproj`.

No creative phase. Plan decisions: Caret-owned port, reuse `CaretPaths`, happy-path TDD after operator request.

## TESTING

- `python3 -m unittest discover -s tests -v` — 16 tests, OK (pin flags, newest-first minutes/windows, clipboard happy path; existing empty-lease / empty-minutes / wrong-version remain).
- `swift build --package-path apps/mac` — OK.
- `xcodebuild test` not run here (Xcode license unsigned). Supervisor tests exist in `apps/mac/Tests/ScreenpipeSupervisorTests.swift`.
- `/niko-qa` PASS (Cursor Grok High Fast). Preflight was PASS WITH ADVISORY (same model). Gemini 3.8 Flash was requested but not available as a subagent model.

## LESSONS LEARNED

- Version-matching an existing Screenpipe is not enough: capture flags can differ. A dedicated port is safer than attach-if-healthy.
- `CaretPaths.projectRoot` is already the repo-root handle for the Mac app.

## PROCESS IMPROVEMENTS

- Happy-path-only TDD is acceptable on a GSD day if existing hard-fail tests stay.
- When the operator names Preflight/QA models, check the subagent allow-list before promising a mix of families.

## TECHNICAL IMPROVEMENTS

- `start()` still swallows spawn errors with `try?`. A status-bar failure would make a dead gatherer obvious.
- Swift XCTest did not run in this environment; run `xcodebuild test` on a licensed Xcode before calling Mac tests green.

## NEXT STEPS

- Stop or ignore leftover `com.screenpipe.agent` on `:3030` if two recorders are confusing.
- Wire last-N into the Jev context frame (still not connected).
- Run CaretTests under full Xcode when the license is accepted.

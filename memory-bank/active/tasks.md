# Task: Caret menu debug last-N preview

* Task ID: caret-debug-last-n-preview
* Complexity: Level 2
* Type: simple enhancement

Add a Debug item to the Caret status-bar menu that opens a small window showing truncated last-2 snippets of windows (recency), minutes (time), and clipboard from the existing lease-backed last-N APIs.

## Test Plan (TDD)

### Behaviors to Verify

- Debug preview success: last-N windows, minutes, and clipboard each have two or more records → payload has three `ok` sections, each with at most two items, newest first, each item is `{app, title, timestamp, text}` with text truncated and no `structure`
- Minutes overflow: `last_n_minutes` returns many records in the window → debug section still lists only the two newest
- Per-slice hard-fail: one last-N call raises `ValueError` (empty, short, down, bad lease) → that section is `{ok: false, error, items: []}` and the other sections still render
- All slices fail: missing lease or unhealthy gatherer → every section carries the error; no invented rows
- CLI: `python3 -m caret history-debug --lease <path>` → prints the debug JSON on stdout, exit 0 even when sections failed (process-level success); only argparse/usage failures exit non-zero
- Swift formatter: debug JSON → short display string with three headings (Windows, Minutes, Clipboard) and at most two snippet lines each; a failed section shows its error
- Swift command: project root present → `python3 -m caret history-debug --lease <lease>` with cwd = project root; missing project root → display explains Caret cannot see last-N without a project root

### Test Infrastructure

- Framework: Python `unittest` (`make test`); Swift XCTest in `Caret.xcodeproj` (`CaretTests`)
- Test location: `tests/`, `apps/mac/Tests/`
- Conventions: Python classes in `tests/test_*.py` with tempfile lease + patched `_api`; Swift XCTestCase next to the type under test. `make check` runs Python tests and `swift build`, not `xcodebuild test`
- New test files: `tests/test_history_debug.py`, `apps/mac/Tests/HistoryDebugTests.swift`

## Implementation Plan

### 1. Python debug preview — executable

- Files: `tests/test_history_debug.py`, `caret/screenpipe.py`

1. Stub tests: `HistoryDebugTests` with empty `test_preview_returns_two_truncated_items_per_slice`, `test_preview_caps_minutes_at_two`, `test_preview_keeps_other_slices_when_one_fails`, `test_preview_reports_lease_errors_per_slice`
2. Stub interface: `debug_preview(lease_path: Path | None = None, n: int = 2, snippet_chars: int = 80) -> dict` in `caret/screenpipe.py` (empty body / `NotImplementedError`)
3. Write tests and run red: assert three sections, `n == 2`, text cut to `snippet_chars` with no structure, minutes list length 2 when the underlying minutes payload is longer, `ValueError` from one last-N becomes that section's `error`
4. Write code and run green: `debug_preview` calls `last_n_windows(n)`, `last_n_minutes(n)`, `last_n_clipboard(n)` independently, catches `ValueError` per call, keeps `records[:n]`, maps each record to `{app, title, timestamp, text}` with truncated text and no structure

### 2. history-debug CLI — executable

- Files: `tests/test_history_debug.py`, `caret/__main__.py`

1. Stub tests: `test_history_debug_cli_prints_json` (empty)
2. Stub interface: `history-debug` subparser with `--lease` (default `None`, same as the other history commands)
3. Write tests and run red: invoke `caret.__main__.main` via `unittest.mock.patch` of `sys.argv` (or a thin helper) and assert stdout is the `debug_preview` JSON and exit code is 0 when sections contain errors
4. Write code and run green: `history-debug` prints `json.dumps(debug_preview(args.lease), indent=2)` and returns 0

### 3. Swift debug snapshot helpers — executable

- Files: `apps/mac/Tests/HistoryDebugTests.swift`, `apps/mac/Sources/Caret/HistoryDebug.swift`, `Caret.xcodeproj/project.pbxproj`

1. Stub tests: `HistoryDebugTests` with empty `testFormatShowsTwoSnippetsAndSectionErrors`, `testCommandUsesProjectRootAndLease`
2. Stub interface: `HistoryDebug.command(projectRoot: URL) -> [String]` and `HistoryDebug.format(_ payload: [String: Any]) -> String`
3. Write tests and run red: command is `["python3", "-m", "caret", "history-debug", "--lease", "<root>/.local/screenpipe-lease.json"]`; format includes Windows / Minutes / Clipboard headings, two snippet lines, and a section error string
4. Write code and run green: implement command + format; add the new Swift files to the Caret app and CaretTests target in `project.pbxproj` (SPM already compiles everything under `apps/mac/Sources/Caret`)

### 4. Menu item and debug window — executable

- Files: `apps/mac/Sources/Caret/StatusBarController.swift`, `apps/mac/Sources/Caret/CaretApp.swift`, `apps/mac/Sources/Caret/CaretDebugView.swift`, `Caret.xcodeproj/project.pbxproj`

1. Stub tests: none beyond helpers in unit 3 (menu/window wiring is AppKit; no existing UI test harness)
2. Stub interface: `StatusBarController.onDebug`, menu item title `Debug…`, `AppDelegate.showDebugWindow()`, `CaretDebugView` that loads `HistoryDebug` on appear
3. Write tests and run red: already covered by unit 3; this unit is the wiring
4. Write code and run green: add `Debug…` above Quit; open a small titled window (settings-style, not the action panel) that runs `HistoryDebug.command` with `currentDirectoryURL = CaretPaths.projectRoot` and shows `HistoryDebug.format` or the missing-root / process-error text. Missing project root or a process failure is a display string, not a crash. Add `CaretDebugView.swift` to the Xcode app target

### 5. README mention — prose/policy

- Files: `README.md`
- No tests: prose/policy artifact

1. Add one sentence that the Caret menu Debug item shows a short last-2 windows / minutes / clipboard preview of what Caret currently sees
2. Do not document leftover supabase creative work

## Technology Validation

No new technology - validation not required. Reuses `python3 -m caret`, the existing lease, and AppKit/SwiftUI window patterns already used for Settings.

## Dependencies

- Existing `last_n_windows`, `last_n_minutes`, `last_n_clipboard` and `.local/screenpipe-lease.json`
- `CaretPaths.projectRoot` and `ScreenpipeSupervisor.leaseURL`
- `python3` on PATH when the app runs (same assumption as the rest of the starter)

## Challenges & Mitigations

- Last-N hard-fails the whole call when a slice is short or empty: `debug_preview` catches `ValueError` per slice so the window still opens
- `last_n_minutes(2)` can return many records: display layer keeps `records[:2]` only
- `last_n_*` records include accessibility `structure`: omit it and truncate `text` so the window stays a glance
- Shipped app without `CaretProjectRoot` cannot run `python3 -m caret`: show that in the window instead of spawning a useless process
- Xcode project lists files explicitly: register new Swift sources in `project.pbxproj` so `make app` matches `swift build`
- Leftover `memory-bank/active/creative/creative-supabase-company-control-plane.md` is not this task: ignore it during preflight/build

## Pre-Mortem

- Debug window shells Python and contributors think Caret "has no history" when the miss is actually no project root / no lease: already covered by Challenge (explicit display string)
- Plan implements a fourth Swift Screenpipe client and drifts from what Caret sees: do not add HTTP in Swift; only `python3 -m caret history-debug`
- Minutes section dumps the full two-minute firehose: already covered by the two-record cap
- Preflight treats the leftover supabase creative as this task's design: already covered — out of scope, do not follow it

## Status

- [x] Initialization complete
- [x] Test planning complete (TDD)
- [x] Implementation plan complete
- [x] Technology validation complete
- [x] Pre-Mortem complete
- [x] Preflight
- [x] Build
- [x] QA

## QA Results

✅ PASS — implementation is acceptable as-is.

- Completeness: `debug_preview`, `history-debug`, Swift command/format/load, Debug… menu window, and the README sentence all exist and match the brief.
- Regression: inference `last_n_*` defaults and `history-*` hard-fail exit 1 are unchanged; `test_minutes_returns_records` still asserts structure.
- Integrity: no Swift HTTP client, no invented rows, leftover supabase creative unused.
- Advisories (non-blocking): success sections omit `error`; format has an unused `(none)` empty-ok branch; `load` waits on the appear path; PATH prefix is copied from `ScreenpipeSupervisor`.

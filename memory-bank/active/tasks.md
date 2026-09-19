# Task: caret-screenpipe-history

* Task ID: caret-screenpipe-history
* Complexity: Level 3
* Type: feature

Caret.app launches and supervises pinned Screenpipe 0.4.50 with clipboard storage on, writes the existing launcher lease, and exposes last-N windows (most-recently-active), last-N minutes (all activity), and last-N clipboard contents, all newest-first.

## Pinned Info

### Launch and last-N

Caret owns the process and the lease. Python never discovers a port. Callers only use the Caret history commands.

```mermaid
sequenceDiagram
  participant App as Caret.app
  participant SP as Screenpipe 0.4.50
  participant Lease as screenpipe-lease.json
  participant CLI as python3 -m caret

  App->>App as "read pin from CaretProjectRoot"
  App->>SP as "health on pin endpoint"
  alt pin already healthy
    App->>Lease as "write lease for running pid"
  else not running
    App->>SP as "spawn pin.launch"
    App->>SP as "wait until health matches pin"
    App->>Lease as "write lease for child pid"
  end
  CLI->>Lease as "load_lease"
  CLI->>SP as "GET /search for minutes, windows, or clipboard"
```

## Component Analysis

### Affected Components
- `caret/screenpipe_pin.json`: names the npm artifact and launch argv → add `--disable-clipboard-capture false` so clipboard rows are stored
- `caret/screenpipe.py`: pin/lease/last-N client → newest-first minutes and windows; add `last_n_clipboard`
- `caret/__main__.py`: `history-minutes` / `history-windows` → add `history-clipboard --count`
- `apps/mac` `ScreenpipeSupervisor`: new → load pin, spawn or attach, write lease under project root `.local/`
- `apps/mac` `CaretApp` / `AppDelegate`: UI lifecycle → start supervisor at launch
- Tests: `tests/test_screenpipe_*.py` and new Swift supervisor tests

### Cross-Module Dependencies
- Swift supervisor → pin file + Screenpipe process → lease file
- Python last-N → lease → Screenpipe `/health` and `/search`
- CLI → `last_n_*` functions

### Boundary Changes
- Pin launch argv gains clipboard persistence
- Last-N sort becomes newest-first (was chronological for windows/minutes)
- New public CLI: `history-clipboard`
- New lease writer in Caret.app (same lease schema)

### Invariants
- Must launch published `screenpipe@0.4.50`, never `packages/screenpipe`
- Must talk only through the lease (no port scan in Python)
- Must hard-fail on missing lease, wrong version, unreachable gatherer, or empty last-N
- Must not invent clipboard or window text
- TCC stays on the Screenpipe binary

## Open Questions

None - implementation approach is clear. Decisions recorded here:

- Clipboard storage: pin `launch` includes `--disable-clipboard-capture` `false`
- Newest-first: do not reverse `/search` descending results; windows stay first-seen in that descending stream (most-recently-active)
- Clipboard query: `GET /search?content_type=input&order=descending&limit=200`, keep `event_type == "clipboard"`, take N
- Lease path: `{CaretProjectRoot}/.local/screenpipe-lease.json` via `CaretPaths.projectRoot`. Python default stays `.local/screenpipe-lease.json`
- Always spawn on Caret-owned `--port` `3031`. Do not attach to launchd `:3030` (preflight advisory: leftover agent is 0.4.50 with clipboard off)
- `history-clipboard` accepts `--lease` like the other history commands
- `start` must not block the main thread
- No TCC user docs in this task (brief constraint)

## Test Plan (TDD)

### Behaviors to Verify

- Pin launch argv includes `--disable-clipboard-capture` and `false` → load_pin accepts it
- Pin still refuses `packages/screenpipe` in launch
- `last_n_minutes` with two timestamps → records newest-first
- `last_n_windows` with three window keys in descending search order → those keys newest-active-first, not reversed
- `last_n_clipboard` with mixed input events → only clipboard rows, newest-first, length N
- `last_n_clipboard` with no clipboard rows → ValueError empty history
- count < 1 → ValueError
- missing lease / wrong version → existing hard-fail still holds
- Swift `leasePayload` from a fixture pin → required lease fields match pin artifact/version
- Swift pin loader requires clipboard flag in launch
- Swift path join: project root + `.local/screenpipe-lease.json`

### Test Infrastructure

- Framework: Python `unittest` under `tests/`; Swift `XCTest` under `apps/mac/Tests/`
- Conventions: `test_*.py` classes; XCTest `test*` methods; mocked `_api` for Screenpipe
- New test files: `apps/mac/Tests/ScreenpipeSupervisorTests.swift` (or cases added beside existing tests). Extend `tests/test_screenpipe_pin.py` and `tests/test_screenpipe_history.py`

### Integration Tests

- Pin launch list is the argv the supervisor would spawn (same JSON file)
- Full `python3 -m unittest discover -s tests -v`
- `swift build --package-path apps/mac`
- `xcodebuild -project Caret.xcodeproj -scheme Caret -destination platform=macOS test` for Swift tests (no live Screenpipe spawn in unit tests)

## Implementation Plan

### 1. Pin clipboard flag — executable

- Files: `caret/screenpipe_pin.json`, `tests/test_screenpipe_pin.py`

1. Stub tests: assert launch contains `--disable-clipboard-capture` and `false`
2. Stub interface: none (JSON field change)
3. Write tests and run red: pin test fails without the flag
4. Write code and run green: append those two launch tokens

### 2. Newest-first minutes and windows — executable

- Files: `caret/screenpipe.py`, `tests/test_screenpipe_history.py`

1. Stub tests: minutes/windows cases that fail if results are chronological
2. Stub interface: none
3. Write tests and run red
4. Write code and run green: drop the reverse on minutes items and on the unique-window list

### 3. Last-N clipboard — executable

- Files: `caret/screenpipe.py`, `caret/__main__.py`, `tests/test_screenpipe_history.py`

1. Stub tests: `test_clipboard_returns_newest_first`, `test_empty_clipboard_is_hard_fail`, `test_clipboard_count_must_be_positive`
2. Stub interface: `last_n_clipboard(count, lease_path=None) -> dict` with empty body
3. Write tests and run red
4. Write code and run green: search `content_type=input`, keep clipboard `event_type`, map `text_content` / app / timestamp; add `history-clipboard --count`

### 4. Swift supervisor — executable

- Files: `apps/mac/Sources/Caret/ScreenpipeSupervisor.swift`, `apps/mac/Tests/ScreenpipeSupervisorTests.swift`, `Caret.xcodeproj/project.pbxproj`

1. Stub tests: lease payload fields, clipboard flag required, lease URL under project root `.local`
2. Stub interface: `ScreenpipePin`, `leaseURL(projectRoot:)`, `leasePayload(pin:checksum:endpoint:pid:readyAt:)`, `start(projectRoot:)`
3. Write tests and run red
4. Write code and run green: parse pin JSON, spawn or attach, write lease. Wire `AppDelegate.applicationDidFinishLaunching` to `start`. Register new files in the Xcode project (SwiftPM picks up Sources/Caret automatically)

### 5. Brief docs — prose/policy

- Files: `README.md` (one line that Caret launches the pin and last-N includes clipboard)
- No tests: prose/policy artifact

1. State that Caret.app writes `.local/screenpipe-lease.json` and that `history-clipboard` exists
2. Do not add TCC onboarding copy

## Technology Validation

No new technology - validation not required. Uses existing `npx` pin, `Process`, and stdlib HTTP.

## Challenges & Mitigations

- Port 3030 already bound by launchd `com.screenpipe.agent`: Caret uses 3031 and always spawns; leave the leftover agent alone
- `npx` not on app PATH: set process PATH to `/opt/homebrew/bin:/usr/bin:/bin` plus existing PATH
- Installed app without a live SRCROOT: `CaretProjectRoot` is baked at build time; `make app` from this repo keeps it valid for the hackathon
- Clipboard still empty after flag if the process was started without it: attach path only accepts a healthy pin-version server; a leftover recorder without clipboard will make `history-clipboard` hard-fail (honest empty)
- Live spawn is not unit-tested: supervisor unit tests cover pin/lease only; spawn is a thin `Process`

## Pre-Mortem

- Plan assumed Caret must always spawn, so it fights launchd and never writes a lease: attach-if-healthy is in the plan
- Plan left last-N chronological, so the interface violates the brief: step 2 exists
- Plan added a Mac history UI or TCC essay and slipped the hackathon window: docs step is one README line
- Plan treated clipboard as `content_type=all` OCR and never returned copies: step 3 filters `input` + `clipboard`

## Status

- [x] Component analysis complete
- [x] Open questions resolved
- [x] Test planning complete (TDD)
- [x] Implementation plan complete
- [x] Technology validation complete
- [x] Pre-Mortem complete
- [x] Preflight
- [x] Build
- [ ] QA

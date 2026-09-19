# Progress

Caret must launch pinned Screenpipe on app start when the expected port is free, and must not start a second recorder when that port is already taken. `CaretProjectRoot` must be present in the built app so the supervisor can run.

**Complexity:** Level 2

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Confirmed Fresh state; operator approved the intent restatement
    - Classified as Level 2 (simple enhancement, one supervisor subsystem)
* Decisions made
    - Level 2, not Level 1: this is a behavior change (port-gated launch) plus the missing bundle key, not a one-line crash fix
* Insights
    - Installed Caret.app currently omits `CaretProjectRoot` because `INFOPLIST_KEY_CaretProjectRoot` is dropped by `GENERATE_INFOPLIST_FILE`

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Wrote Level 2 TDD plan: port probe + skip-spawn, Info.plist merge, docs
* Decisions made
    - Spawn decision is TCP listen on the pin port, not `/health`
    - Skip-spawn still writes a lease only after pin-version `/health` (existing lease gate)
    - `stop()` must not terminate a process Caret did not spawn
* Insights
    - Supervisor XCTest lives in the Xcode target only; `make check` will not run those tests

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Validated the plan against the codebase: TDD ordering, conventions, dependencies, conflicts, completeness
    - Result: `FAIL (fixable)` - adopt-mode lease write has no planned test and no specified `pid` for the schema-required lease field
* Decisions made
    - Planner must pick the pid story for an adopted listener (sentinel 0 recommended) and add a behavior plus test, or scope the adopt-mode lease write out
* Insights
    - The `CaretProjectRoot` plist fix also activates SkillRepository, MemoryRepository, and CaretNote against the source tree - an unlisted behavior change
    - A stale lease survives a failed/foreign-listener launch; deleting it at `run()` start would make lease freshness invariant (advisory)

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Re-planned: sentinel `pid` `0` for adopt-mode leases, stub `/health` tests, stale-lease delete at `run` start, docs note for skills/memories/notes
* Decisions made
    - Keep the adopt-mode lease write (option a), not scope it out
    - Adopted pid is `0` so Caret does not claim the foreign process
* Insights
    - `run()` against a plain TCP bind would stall on `waitForHealth`; adopt tests need an HTTP stub

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Re-validated the re-planned tasks.md against the codebase: TDD ordering, conventions, dependencies, conflicts, completeness
    - Result: `PASS WITH ADVISORY` - all seven checks pass; the prior `FAIL (fixable)` is resolved by the sentinel-`pid`-0 adopt behavior and its stub-`/health` test
* Decisions made
    - No plan edits needed this run; proceed to Build as-is
* Insights
    - `_require_health` in `caret/screenpipe.py` never reads `pid`, confirming sentinel `0` cannot trip the Python last-N hard-fail path
    - Advisory (non-blocking, radical innovation): a generic `PinnedServiceSupervisor` could let future upstream supervisors (KeyType, GhostType, Computer Use Jev, Skyvern) reuse the launch-if-free/adopt-if-healthy/never-kill-foreign shape instead of reimplementing it per pin

## 2026-09-19 - BUILD - COMPLETE

* Work completed
    - TDD: supervisor tests red, then green (7 cases)
    - Built Debug Caret.app; `CaretProjectRoot` expands to the repo root
    - `make check` OK (24 Python tests); full `CaretTests` OK (11 cases)
* Decisions made
    - SwiftPM `exclude: ["Info.plist"]` so the Xcode-only plist is not a package resource
* Insights
    - `INFOPLIST_FILE` merge is what actually ships `CaretProjectRoot`; `INFOPLIST_KEY_*` does not

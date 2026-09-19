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

## 2026-09-19 - QA - COMPLETE

* Work completed
    - QA `FAIL`: README and techContext overstated adopt-and-lease for any occupied port
* Decisions made
    - Documentation-only Build rerun to match `waitForHealth` before lease write

## 2026-09-19 - BUILD - COMPLETE

* Work completed
    - Corrected README and techContext: no spawn when the port is taken; lease only after pin-version `/health`

## 2026-09-19 - QA - COMPLETE (FAIL)

* Work completed
    - Reviewed the implementation against the approved Level 2 plan and project brief
* Findings
    - README.md and techContext.md incorrectly say any occupied port is adopted and produces a lease; a listener that does not return the pinned Screenpipe version fails the health gate and writes no lease
* Next step
    - Rerun Build to correct the documentation, then rerun QA

## 2026-09-19 - QA - COMPLETE (PASS)

* Work completed
    - Re-reviewed the supervisor, Info.plist merge, tests, README, and techContext against the approved Level 2 plan after the documentation-only Build rerun
    - Result: `PASS` (advisories only)
* Decisions made
    - Prior FAIL is resolved: README and techContext now state no spawn on a taken port and a lease only after pin-version `/health`
    - Implementation is acceptable as-is; unused test `http` flag and productContext altitude are non-blocking
* Insights
    - Built Debug `Caret.app` still expands `CaretProjectRoot` to the repository root; work remains on `feat/caret-screenpipe-launch-if-port-free`

## 2026-09-19 - REFLECT - COMPLETE

* Work completed
    - Wrote reflection; reconciled persistent files (systemPatterns only)
* Decisions made
    - productContext skip — launch-on-3031 remains true at product altitude
    - techContext skip — already states port-free spawn and health-gated lease
    - systemPatterns updated — standing contract is port-gated spawn plus health-gated lease

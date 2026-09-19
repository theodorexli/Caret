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

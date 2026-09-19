# Progress

Change Caret’s Screenpipe start so it execs the pinned `screenpipe` binary and runs it outside Caret’s process tree, so TCC can grant that binary and the 5s permission sheet stops.

**Complexity:** Level 2

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Classified `caret-screenpipe-detached-launch` as Level 2
    - Wrote project brief from the approved intent restatement
* Decisions made
    - Option 1+3 only: detached start + direct binary. No Caret code-signing
    - Feature branch required
* Insights
    - Today’s Caret-spawned `:3031` log showed `screen=false accessibility=false` and a 5s VisionManager retry; a non-child launch of the same binary earlier reported those grants true

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Wrote Level 2 TDD plan for pin argv, launchd supervisor, docs, and live perm check
* Decisions made
    - Caret-owned launchd job (`dev.caret.hackathon.screenpipe`), not a helper `.app`
    - `npx` remains obtain-only; launch argv starts with `screenpipe`
    - XCTest does not call `launchctl`; Build does the live parent/perm check
* Insights
    - If Caret-bootstrapped launchd is still TCC-attributed to Caret, shipping another `Process` child will not fix the sheet

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

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Preflight PASS WITH ADVISORY ([preflight](292ace4c-fc0b-4b85-96d3-51cf89c06166))
* Decisions made
    - Build will take advisories: do not exec `obtain`; set `ownsJob` at bootstrap; XCTest injects resolve and skips `launchctl`; no AssociatedBundleIdentifiers to Caret
* Insights
    - Short-lived `npx --package … which` is allowed; `/usr/bin/env` + obtain tokens is not

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Validated the Level 2 plan against ScreenpipeSupervisor, pin JSON, CaretTests, last-N client, and CaretApp start/stop
    - Wrote `memory-bank/active/.preflight-status` with first line `PASS WITH ADVISORY`
* Decisions made
    - Plan is acceptable as-is; Build may start
    - Did not edit tasks.md (no TDD swap or change-detector strike)
* Insights
    - Highest-risk misread: treating `obtain` as a Process to run before `which`, which would spawn `npx` as a Caret child again
    - Highest-risk design bet: Caret-initiated `launchctl bootstrap` may still put Caret in the TCC chain; the planned fallback is the same path

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

## 2026-09-19 - BUILD - COMPLETE

* Work completed
    - Direct Mach-O resolve + Caret-owned launchd job
    - CaretTests 15 passed; Python 29 passed; `swift build` OK
    - Live Caret start: healthy `:3031`, lease pid 79661, vision recovered and captured
* Decisions made
    - `npx which` is the node shim; walk to `@screenpipe/cli-darwin-arm64/bin/screenpipe`
    - Do not exec `obtain`
* Insights
    - Detached launch got `screen recording: ok` and frames. Accessibility is still a grant on that Mach-O, not a Caret-child TCC bug

## 2026-09-19 - REFLECT - COMPLETE

* Work completed
    - Wrote `memory-bank/active/reflection/reflection-caret-screenpipe-detached-launch.md`
    - Reconciled persistent files (already updated in Build)
* Decisions made
    - None new
* Insights
    - npm `which` is the node shim; the Mach-O is the optional-dependency binary

## 2026-09-19 - QA - COMPLETE (PASS)

* Work completed
    - Semantic review of pin argv, launchd supervisor, docs, and live-check notes against the Level 2 plan
    - Wrote `memory-bank/active/.qa-validation-status`
* Decisions made
    - PASS with advisories; no Build rerun
    - Remaining Accessibility false is an operator grant on the Developer ID binary, not a plan or implementation defect
* Insights
    - `npx which` resolving to a node shim was the real TCC fork; walking to `@screenpipe/cli-darwin-arm64/bin/screenpipe` is what made the live parent/perm check succeed

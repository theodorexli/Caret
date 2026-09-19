# Progress

Clip the Caret Debug window out of Debug last-N windows so the newest item is the window in view before Debug opened.

**Complexity:** Level 1

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Classified caret-debug-clip-self-from-windows as Level 1
    - Wrote project brief, active context, and task stub
* Decisions made
    - Bug fix, single component: Debug last-N windows preview
    - Minutes, clipboard, and inference last-N are out of scope
* Insights
    - Screenpipe records Debug as newest because opening the window is a real focus change; the preview must drop that self-hit

## 2026-09-19 - BUILD - COMPLETE

* Work completed
    - Failing test: Debug as newest window must not appear in the windows glance
    - `last_n_windows` skips titles in `skip_titles` and keeps walking
    - `debug_preview` passes `skip_titles={"Caret Debug"}`
    - `make test`: 301 passed, 4 skipped
* Decisions made
    - Skip by window title `Caret Debug` only, matching `showDebugWindow`
    - Do not skip Debug in minutes or clipboard
    - Do not change inference `last_n_windows` callers
* Insights
    - Distinct-window walk must skip before the count cap, or last-2 becomes last-1 after the clip

## 2026-09-19 - QA - COMPLETE (PASS)

* Work completed
    - Semantic review of `last_n_windows(skip_titles=)` and `debug_preview` against the project brief
    - Wrote `memory-bank/active/.qa-validation-status` as PASS
* Decisions made
    - Accept skip-during-walk; filtering after the cap would shrink last-N
    - No blocking findings; L1 wrap-up is the parent’s next step
* Insights
    - Title-only skip is enough because Swift sets `window.title = "Caret Debug"` and Screenpipe stores that as `window_name`

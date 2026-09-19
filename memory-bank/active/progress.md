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

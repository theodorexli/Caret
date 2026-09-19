# Progress

Add a Caret menu Debug item that shows a short last-2 preview of windows (recency), minutes (time), and clipboard so a person can see what Caret currently sees.

**Complexity:** Level 2

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Confirmed Fresh state (no in-flight standalone or L4 core files)
    - Operator waived approval gates and asked to archive then open a PR when done
    - Classified Level 2: self-contained menu enhancement over existing last-N APIs
* Decisions made
    - "By recency" is last-N windows; "by time" is last-N minutes; plus clipboard
    - Last two of each slice, truncated, not full records
    - Preflight and QA subagents use only `cursor-grok-4.6-xhigh-fast`
* Insights
    - `last_n_*` hard-fails on empty or short slices; the debug view must report that per section instead of aborting the window
    - Leftover supabase creative under `memory-bank/active/creative/` is out of scope

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Wrote Level 2 TDD plan: Python debug preview, CLI, Swift helpers, menu/window, README sentence
    - Mapped last-2 display to existing last-N kinds (windows / minutes / clipboard)
* Decisions made
    - Reuse `last_n_*` and catch `ValueError` per slice; do not add a Swift Screenpipe client
    - Minutes payload is capped at two newest records in the debug view
    - CLI `history-debug` exits 0 when sections fail so the window can show the errors
* Insights
    - Inference last-N stays hard-fail; debug is a separate glance that reports those failures

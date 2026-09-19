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

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Preflight recorded `PASS WITH ADVISORY` in `memory-bank/active/.preflight-status`
* Decisions made
    - Build as planned; apply cheap advisories: forward `lease_path`, lock JSON keys, spawn via `/usr/bin/env` + Homebrew PATH
    - Debug last-N calls use `include_structure=False` and cap minutes records so the window does not hydrate discarded rows
* Insights
    - `last_n_minutes(2)` is a two-minute window, then the preview keeps two rows

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Validated the Level 2 plan against last-N APIs, CLI, status-bar menu, settings window, Screenpipe supervisor launch, and CaretTests membership
    - Wrote `memory-bank/active/.preflight-status` first line `PASS WITH ADVISORY`
* Decisions made
    - Plan is acceptable as-is; leftover supabase creative stays out of scope
    - Unit 4 AppKit wiring without new tests is not a TDD block (no UI harness; do not invent XCUITest)
* Insights
    - `last_n_minutes` hydrates accessibility structure for the whole window before the debug cap; a glance window can stall unless build skips structure / caps records
    - App-spawned `python3` should reuse `ScreenpipeSupervisor` PATH/`env`, not assume a shell PATH
    - `CaretTests` only compiles listed files; `HistoryDebug.swift` must join that target

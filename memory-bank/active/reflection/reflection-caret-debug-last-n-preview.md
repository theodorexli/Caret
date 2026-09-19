---
task_id: caret-debug-last-n-preview
date: 2026-09-19
complexity_level: 2
---

# Reflection: Caret menu debug last-N preview

## Summary

The Caret menu now has a Debug item that shows a short last-2 windows / minutes / clipboard preview of what Caret currently sees. It shipped as planned.

## Requirements vs Outcome

Delivered: menu Debug window, last-2 truncated snippets per last-N kind, per-slice errors, unchanged inference hard-fail. Added optional `include_structure` / `record_cap` so the glance does not hydrate discarded minutes rows.

## Plan Accuracy

The file list and TDD sequence were right. The real risk was minutes cost (200 accessibility hydrations), which preflight caught; build applied the cheap skip/cap. No reordering.

## Build & QA Observations

Python tests and `make check` were clean. `xcodebuild test` HistoryDebugTests passed. QA passed with advisories only (omitted success `error` key, unused `(none)` branch, blocking `waitUntilExit`).

## Insights

### Technical
- `last_n_minutes` is a time window that hydrates structure for every hit. A glance that reuses it must skip structure and cap records, or it is not a glance.

### Process
- Nothing notable

### Million-Dollar Question

If Debug had been assumed from the start, last-N would already expose a cheap peek (`include_structure=False`, `record_cap`) and the app would show that peek instead of growing a second client. That is what we built.

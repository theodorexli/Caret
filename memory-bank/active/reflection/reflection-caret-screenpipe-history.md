---
task_id: caret-screenpipe-history
date: 2026-09-19
complexity_level: 3
---

# Reflection: caret-screenpipe-history

## Summary

Caret.app now launches pinned Screenpipe 0.4.50 on port 3031 with clipboard storage on, writes the existing lease, and the Python facade returns last-N windows, minutes, and clipboard newest-first. The work matched the brief.

## Requirements vs Outcome

Delivered: launch/supervise, clipboard on, three last-N queries, newest-first, hard-fail on empty/wrong gatherer, callers use Caret not Screenpipe. Added `--disable-audio` so the child can start without mic TCC. Did not add TCC docs or a Mac history UI. Operator cut TDD to happy paths; existing empty-lease/empty-minutes/wrong-version tests remain.

## Plan Accuracy

Sequence (pin → sort → clipboard → supervisor → README) was right. Attach-if-healthy was wrong for this machine: launchd `:3030` is 0.4.50 with clipboard off. Preflight’s 3031-always-spawn advisory became the implementation. `CaretPaths.projectRoot` already existed.

## Creative Phase Review

No creative phase. The leftover Supabase creative was out of scope.

## Build & QA Observations

Python 16 tests OK; `swift build` OK. `xcodebuild test` blocked by an unsigned Xcode license on this machine. QA passed with advisories; the silent health-timeout lease write was fixed after QA. README no longer says Screenpipe is unconnected.

## Cross-Phase Analysis

The first plan’s attach-if-healthy would have leased a recorder that does not store clipboard. Preflight caught that against live `/health`. Operator “don’t wait for plan approval” plus GSD made applying that advisory during build the right move.

## Insights

### Technical
- A leftover Screenpipe on `:3030` can be the right version and still have clipboard off. Version match is not capture-config match. A Caret-owned port avoids inheriting that process.
- `INFOPLIST_KEY_CaretProjectRoot` / `CaretPaths` is the existing repo-root handle; do not add a second lookup.

### Process
- Happy-path-only TDD is fine on a GSD day if existing hard-fail tests stay. Do not drop them to “abridge.”
- For Preflight/QA this run, Gemini 3.8 Flash was not an available subagent model; Cursor Grok High Fast ran both.

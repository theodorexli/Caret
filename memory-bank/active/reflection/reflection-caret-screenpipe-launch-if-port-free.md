---
task_id: caret-screenpipe-launch-if-port-free
date: 2026-09-19
complexity_level: 2
---

# Reflection: caret-screenpipe-launch-if-port-free

## Summary

Caret now starts pinned Screenpipe when the pin port is free, and does not spawn when it is taken. `CaretProjectRoot` ships via `INFOPLIST_FILE`. The work succeeded after one documentation QA fail.

## Requirements vs Outcome

Delivered as asked: spawn on a free port, no second recorder on a taken port, bundle root so `start` runs, feature branch. Added adopt-mode lease with sentinel `pid` 0 so last-N still has a lease when an existing listener is the pin.

## Plan Accuracy

File list and TDD order were right. Preflight forced the missing pid/test story. The surprise was docs: first QA failed because "adopt" was written as if any listener produced a lease.

## Build & QA Observations

Supervisor tests and `INFOPLIST_FILE` merge went through on the first green. First QA failed on README/techContext wording; second QA (Grok Fast) passed. Gemini 3.8 Flash was requested for QA/Preflight today but is not on the subagent allow-list.

## Insights

### Technical
- `INFOPLIST_KEY_*` does not ship custom keys under `GENERATE_INFOPLIST_FILE`. Use `INFOPLIST_FILE` merge.
- Spawn gate is the port. Lease write is `/health` matching the pin. Mixing those in docs caused the QA fail.

### Process
- For this repo today, QA and Preflight subagents must be Cursor Grok 4.6 High Fast or Gemini 3.8 Flash only.

### Million-Dollar Question

The same supervisor: probe the pin port, spawn only if free, lease only after pin `/health`, never terminate a process we did not start. That is what we built. A generic pin supervisor can wait.

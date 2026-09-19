---
task_id: caret-screenpipe-detached-launch
date: 2026-09-19
complexity_level: 2
---

# Reflection: caret-screenpipe-detached-launch

## Summary

Caret now bootstraps a launchd job that execs the pinned Developer ID `screenpipe` Mach-O on `:3031`. Live start was healthy and captured frames. Accessibility is still a grant on that binary.

## Requirements vs Outcome

Delivered 1–5 and the launch half of 7: direct Mach-O, not a Caret child, health-gated lease, adopt `pid` 0, quit does not bootout a foreign listener. Feature branch exists. Screen Recording recovered after ~10s. Accessibility stayed false until the user grants `screenpipe` — that is no longer a Caret-child TCC bug.

## Plan Accuracy

Sequence was right. Surprise: `npx which` is a node shim (`lib/cli.js`), not the Mach-O. Added `nativeBinary(fromShim:)` so TCC sees `@screenpipe/cli-darwin-arm64/bin/screenpipe`. Caret-initiated `launchctl bootstrap` did detach (PPID 1).

## Build & QA Observations

TDD on pin + supervisor was clean. Live check proved the path. QA passed with advisories only (AX grant, resolve still shells `npx which`).

## Insights

### Technical
- npm `bin` for this pin is a node wrapper. TCC and launchd must exec the optional-dependency Mach-O.

### Process
- A live parent/`/health` check caught the shim issue that XCTest could not.

### Million-Dollar Question

If Caret had never spawned Screenpipe as a child, the supervisor would have been “resolve Mach-O, write launchd plist, health, lease” from the first pin — which is what we built.

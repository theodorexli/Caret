# Project Brief

## User Story

As a Caret developer, I want the Mac app to launch a specific, pinned Screenpipe version so inference can depend on that gatherer, and so a missing or empty history is a hard failure.

## Use-Case(s)

### Use-Case 1

A teammate opens Caret. Caret starts the pinned Screenpipe. The rest of the app asks for last N minutes or last N windows and gets structured context.

### Use-Case 2

Screenpipe is down, the wrong version is running, or last-N has no usable records. The Caret run that needs that history stops. No inference on empty or invented context.

## Requirements

1. Caret launches a particular Screenpipe version it can depend on, not whatever happens to be on the machine.
2. The rest of Caret requests last N minutes and last N windows through a Caret-owned facade.
3. Screenpipe down, wrong version, unreachable, or missing required history is a hard failure of that run.

## Constraints

1. Do not vendor current commercial Screenpipe source or advance the `892199f` MIT pin. Do not copy `ee/`.
2. Launching their binary does not inherit Caret’s Accessibility. That process needs its own grants.
3. Caret stays a Swift popup plus `python3 -m caret`. Callers must not speak Screenpipe URLs or `AX*` tokens.
4. Do not invent windows or continue inference when history is missing.
5. Today (2026-09-19): hackathon GSD. Happy path only. Ship. Do not polish. Preflight must not block on niceties, extra contracts, or future-proofing.

## Acceptance Criteria

1. A documented pin identifies the Screenpipe version Caret launches.
2. Caret starts that version (or confirms it is already that version) before a history-backed run.
3. `last_n_minutes` and `last_n_windows` return the agreed structured shape, or the run fails.
4. A down sidecar, version mismatch, or empty required window fails the run with a structured error.

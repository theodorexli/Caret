---
task_id: caret-pinned-screenpipe
complexity_level: 4
date: 2026-09-19
status: completed
---

# TASK ARCHIVE: caret-pinned-screenpipe

## SUMMARY

Caret can depend on a pinned Screenpipe CLI (`npm screenpipe@0.4.50`) and ask for last N minutes or last N windows through `python3 -m caret`. Missing lease, wrong version, or empty history is a hard failure. Caret.app does not yet launch or supervise that process. Operator archived this slice on a hackathon GSD day and left launch plus docs as follow-up.

## REQUIREMENTS

- Pin a particular Screenpipe version Caret can depend on, not a random install and not the `892199f` git tree.
- Last N minutes and last N windows through a Caret facade.
- Hard-fail if the gatherer is down, the version is wrong, or last-N is empty.
- Do not vendor current Screenpipe source or copy `ee/`.
- Do not claim Caret Accessibility covers the Screenpipe binary.

## IMPLEMENTATION

Architecture (inlined from the creative, after operator override): Caret launches and supervises a pinned Screenpipe. The Python client talks only to a launcher lease (`artifact_id`, `checksum`, `expected_version`, `endpoint`, `pid`, `ready_at`). Do not rediscover port 3030. Do not vendor the engine. TCC stays on the launched binary. Soft-empty last-N is not valid.

What shipped:

- `caret/screenpipe_pin.json` — npm `screenpipe@0.4.50`, obtain/launch via `npx`, lease field list.
- `caret/screenpipe.py` — `load_pin`, `load_lease`, `last_n_minutes`, `last_n_windows`, AppKit role labels.
- `caret/__main__.py` — `history-minutes` and `history-windows`.
- Tests in `tests/test_screenpipe_pin.py` and `tests/test_screenpipe_history.py`.

What did not ship: Swift launch/supervise, live lease writer, user-facing TCC docs.

## TESTING

`python3 -m unittest discover -s tests -v` — 11 tests, OK. Pin and history tests use a fixture lease and a mocked API. No `/niko-qa` run. Live Screenpipe was used earlier in the session to prove the dump shape; the CLI was not re-run against a live lease in this archive.

## LESSONS LEARNED

- macOS Accessibility is per signature. Spawning Screenpipe from Caret does not inherit Caret’s grant.
- Current Screenpipe is commercial. Runtime pin the published CLI; do not fast-forward `packages/screenpipe`.
- “Sidecar, do not spawn” and “Caret launches a pin” cannot both be true. Preflight correctly blocked until the operator overrode spawn.
- L4 has no single build phase. `/niko-build` on an L4 plan means start a milestone sub-run or ship a slice on a branch.

## PROCESS IMPROVEMENTS

- Update the creative when the operator changes process ownership before writing milestones, so preflight does not fail on a stale decision.
- On hackathon days, treat extra schemas and future-proofing as advisory only.

## TECHNICAL IMPROVEMENTS

A versioned lease file written by Caret.app (milestone 3) is still required before inference can depend on “the process we launched” instead of a hand-written `.local/screenpipe-lease.json`.

## NEXT STEPS

- Launch and supervise the pinned Screenpipe from Caret.app and write the live lease.
- Document that the user grants the launched Screenpipe binary, not Caret, for capture.

## Milestone List

Original L4 list:

1. Pin the Screenpipe artifact Caret will launch — done (npm 0.4.50).
2. Add a Python last-N client that requires the pin and hard-fails — done.
3. Launch and supervise the pinned Screenpipe from Caret.app — not done; deferred.
4. Document TCC for the launched binary and the hard-fail contract — not done; deferred.

No milestones were added or reordered. Scope was cut at archive by operator request.

## Sub-Run Summaries

No per-milestone reflection documents existed. Work ran as one GSD build on `feat/caret-pinned-screenpipe` instead of four classified sub-runs.

## System State

Caret’s Python package can load a pin and a lease and return structured last-N history, or exit 1. The Mac popup still does not start Screenpipe. `packages/screenpipe` is unchanged.

## Cross-Run Insights

Process ownership flipped once (sidecar → Caret launches). Hard-fail on empty history stayed. License and TCC honesty stayed.

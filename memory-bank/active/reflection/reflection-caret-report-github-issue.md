---
task_id: caret-report-github-issue
date: 2026-09-19
complexity_level: 3
---

# Reflection: caret-report-github-issue

## Summary

Caret can now take an explicit panel pick, research a public GitHub repo with unauthenticated HTTP, mint one comment-or-new-issue offer, and write only after accept through templated computer-use-jev. It shipped after six plan/preflight loops, an operator override into Build, and one QA-fix cycle on cancel.

## Requirements vs Outcome

The brief is met: pivot from the frozen host app, fail fast when there is no public GitHub issue target, match-or-open, no invented tracker. Planned weakness left in: the Jev goal interpolates only a slug or issue URL, so the complaint does not land on the GitHub form unless the user pastes it. Non-GitHub trackers stay a comment. Auth is the browser session, not a Caret token.

## Plan Accuracy

Replan 6 named the real call sites (`showPanel` host freeze, `install_offer` without `submit`, `syncActionOffers` as the only Cmd-1 writer, `standDownForExplicitRun` vs `hidePanel`). That is why the happy path built in one pass. The plan's Sol-3 line — "drop the reply, do not cancel the Python request" — was incomplete: `prepareWorkflow` installs before the await returns, so dropping the reply leaves the offer armed. File list and unit order were right. No creative phase ran.

## Creative Phase Review

None. The design lived in the plan's pinned diagrams. That was enough for the happy path and not enough for cancel: the generation Int was specified, the install side effect was not.

## Build & QA Observations

Python units 1–4 went green first; Mac unit 5 compiled against a pre-existing discovery XCTest that assumed `/usr/bin/python3`. First QA (Grok Fast) failed two cancel-path holes and left the happy path alone. The fix was small: `discardPreparedOffer` after a generation mismatch, and clear `explicitStatus` in `clearPanelScope` only. Second QA passed with advisories (unused session id, title-only evidence, leftover offer after hide once shown, stale `systemPatterns` — the last of those is reconciled here).

## Cross-Phase Analysis

Five preflight FAIL (fixable) cycles each folded the last bullet. That produced a plan that finally named the whole happy path, and it also trained the builder to treat "drop the reply" as sufficient cancel. Operator override of the leftover FAIL gate was the right GSD move; QA still earned the cycle by catching the side-effect hole preflight never restated. `syncActionOffers` as sole writer was the plan's best catch — setting `model.actionOffers` from the reply would have demoed as success with a dead Cmd-1.

## Insights

### Technical
- A generation fence on the await is not cancel if the callee already mutated the shared offer store. Undo the side effect (`discardPreparedOffer`) or do not install until the caller confirms.
- `syncActionOffers` is the only writer of `model.actionOffers`. A reply that only updates the model renders and never arms Cmd-1.

### Process
- Folding one preflight bullet at a time will keep missing the next leaf. When the path has two lanes (ambient vs explicit), specify cancel and resume as first-class units, not a Sol-N footnote.
- Operator override of a stale FAIL (fixable) plus a real QA pass is cheaper than a sixth preflight. QA here found what preflight 6 would have had to invent.

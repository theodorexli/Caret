# Active Context

## Current Task: caret-report-github-issue
**Phase:** PLAN - COMPLETE

## What Was Done
- Replan 5, under an operator override to stop folding single preflight bullets. Traced the whole explicit-invoke path in the current source instead: `CaretApp.swift`, `CoreBridgeProvider.swift`, `SkillActionRunner.swift`, `SelectionMonitor.swift`, `FocusedTargetCapture.swift`, `CoreBridgeClient.swift`, `CoreProtocol.swift`, `SkillRepository.swift`, `CaretPaths.swift`, and `bridge.py` / `router.py` / `engine.py` / `registry.py` / `context.py` / `unavailable.py` / `native_computer_use.py`.
- Rewrote `tasks.md` around six units, with named call sites, render conditions and accept-time panel and capture behavior.

## Decisions Made
- One-click invoke: `Model.selectActionFromPanel` runs the action instead of scoping, so `filteredSkills` is off the path and the status row can live in header chrome that renders in both states.
- `Model.explicitStatus` is a dedicated published sentence beside `actionOffers`, independent of `backendStatus`, `unavailabilityText(for:)` and `failSkillPreview`.
- The prepare reply is installed in `CoreBridgeProvider`'s own offer store, which then fires `onActionsChanged`. `syncActionOffers` is the only writer of `model.actionOffers` and the only place `setVisibleChoiceCount` arms Cmd-1.
- Every non-executing offer is dropped when the explicit one is installed, because `visibleExecutableActions` sorts by UUID and Cmd-1 must be deterministic.
- `standDownForExplicitRun` orders the panel out after the synchronous claim; `resumeAfterExplicitRun` on the terminal state is the only place capture resumes.
- Click-outside is suppressed while a prepare is in flight; Escape stays the cancel.
- The descriptor pins `execution_method="computer-use-jev"`, `sample_only=False` and empty `missing_inputs`, the three-part gate `CaretActionOffer.isExecutable` applies.
- `Router.install_offer` moves `_highest_revision` and `_current_target` and clears `_pending`, which is what discards an ambient evaluation already in flight.
- `explicitActionFrame` shares the capture's revision counter, always reads the pasteboard, and emits `explicit_invoke` and `frontmost_app` source records with null capture times.

## Next Step
- Operator: run `/niko-preflight`, or `/niko-build` against this plan. No preflight was spawned from this run.

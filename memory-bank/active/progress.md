# Progress

Add a Caret skill that pauses the current app, understands a complaint, finds that app's public GitHub repository, searches for matching issues, and offers to open a new issue or comment on an existing one. Fail fast with an explicit non-open-source message when GitHub issue search/file is not possible.

**Complexity:** Level 3

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Validated intent: pivot-to-report skill with match-or-open, plus fail-fast when the app is not a public GitHub issue target
    - Classified as Level 3 (complete feature, multiple components, no new architecture)
* Decisions made
    - Current write/search surface is public GitHub only
    - Non-GitHub trackers stay as a code-comment extension point
* Insights
    - Existing Caret skill/workflow contracts are the insertion point; this is not a second judge or history engine

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Mapped the feature onto the existing WorkflowAdapter + skill-note + picker CLI path
    - Locked prepare as read-only `gh` search and execute as computer-use-jev
    - Wrote TDD plan and six implementation units
* Decisions made
    - No GitHub REST client and no `gh issue create` happy path
    - No new bridge RPC; explicit invoke uses `python3 -m caret report-issue`
    - Repo identity comes from evidenced GitHub URLs or `gh search repos`, else fail-fast not-OSS
    - Skill is not a Vercel gateway text transform
* Insights
    - `SkillActionRunner` currently no-ops non-gateway ids; the picker hook is load-bearing
    - `prepare` cannot use computer use to search, because prepare must not navigate

## 2026-09-19 - PREFLIGHT - FAIL (fixable)

* Work completed
    - Preflight subagent (Cursor Grok 4.6 High Fast) rejected the picker CLI accept path
* Decisions made
    - Replan: explicit invoke uses `workflow.prepare` on the long-lived bridge
    - Accept stays `CaretActionOffer` / `offer.accept` / Cmd-1
    - Mac frame comes from `FocusedTargetCapture.explicitActionFrame()`, not `--frame` JSON
* Insights
    - A second accept protocol was invented capability; the bridge already files accepted writes

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Replaced units 4–5 with named prepare + existing accept
    - Named `frontmost_app` as the gh search display name
    - Dropped ambient judge from the happy path
* Decisions made
    - Empty complaint is `Preparation.missing_inputs`
    - Not-OSS is a failed prepare, not a write offer
    - No CaretCLI source-string test

## 2026-09-19 - PREFLIGHT - FAIL (fixable)

* Work completed
    - Preflight 2 named five ship-blockers: hidden panel, router race, default registry, failed-event poisoning, clipboard/liveTarget
* Decisions made
    - `workflow.prepare` is request-reply; `Router.install_offer` does not submit
    - Not-OSS is `workflow_error`, not `failed`
    - Built-in register in `build_registry`
    - `CaretApp.onRun` keeps the panel open for this id
    - No-field accept revalidates pid/bundle only; explicit frames always read the pasteboard

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Replanned units 3–5 around request-reply, built-in load, panel stay, and no-field accept

## 2026-09-19 - PREFLIGHT - FAIL (fixable)

* Work completed
    - Preflight 3: host app is lost when the picker opens; `failSkillPreview` is invisible on the browse panel
* Decisions made
    - Freeze `HostContext` in `showPanel` before Caret is frontmost
    - Show not-OSS with `CaretActionStatusRow` on the browse panel
    - `install_offer` clears `_pending`; Mac replaces `actionOffers` with the reply

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Replanned unit 5 around `HostContext` and the browse-panel status row

## 2026-09-19 - PREFLIGHT - FAIL (fixable)

* Work completed
    - Preflight 4: empty-skills status row is invisible after the skill is clicked; floating panel would cover Jev
* Decisions made
    - Status row lives next to `actionOffers`
    - Accept claims the offer, then `orderOut` before Jev, without `hidePanel`
    - `availability` is false unless the frame has an `explicit_invoke` source
    - Seed `caret/skills/report-github-issue/default.json`; inject `prepareWorkflow` into `SkillActionRunner`

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Folded preflight 4 into unit 5

## 2026-09-19 - PREFLIGHT - COMPLETE (FAIL (fixable))

* Work completed
    - Validated the Level 3 plan against `WorkflowAdapter`, `NativeComputerUseWorkflow`, SkillActionRunner/CaretCLI, the bridge catalog, and the pattern judge
    - Wrote `memory-bank/active/.preflight-status` with first line `FAIL (fixable)`
* Decisions made
    - Did not edit the implementation plan (no TDD swap or change-detector strike)
    - Picker accept/execute and Mac ContextFrame encoding must be added to the plan before build
* Insights
    - `onRun` already calls SkillActionRunner; the hole is accept UI + a legal `--frame`, not a missing onRun hook
    - Default Mac launch uses `--judge pattern` and config-only `--adapter`, so the ambient path does not select this skill
    - Python `InputSnapshot.to_dict()` omits `nearby_text`; Swift `ContextFrame` is the encode path that `from_dict` can accept

## 2026-09-19 - PREFLIGHT - COMPLETE (FAIL (fixable))

* Work completed
    - Re-validated the replanned `workflow.prepare` + existing-accept path against the router, `build_registry`, CaretApp panel/Cmd-1 rules, `liveTarget`, and failed-event handling
    - Wrote `memory-bank/active/.preflight-status` with first line `FAIL (fixable)`
* Decisions made
    - Did not edit the implementation plan (no TDD swap or change-detector strike)
    - Panel-keep, router claim, built-in registry register, coded not-OSS reply, and no-field accept must be added to the plan before build
* Insights
    - `adapters()` is not loaded by the default Mac bridge; only `build_registry` plus `--adapter` from `dev.json` populate the registry
    - `submit` does not take the in-flight slot; the worker will judge a frame left pending during `gh` search
    - A `failed` event is treated as a completion-backend outage, not a skill outcome

## 2026-09-19 - PREFLIGHT - COMPLETE (FAIL (fixable))

* Work completed
    - Re-validated the request-reply + install_offer + keep-panel replan against FocusedTargetCapture, SelectionMonitor, SkillPickerView, GatewayActionPanel, and Router.accept
    - Wrote `memory-bank/active/.preflight-status` with first line `FAIL (fixable)`
* Decisions made
    - Did not edit the implementation plan (no TDD swap or change-detector strike)
    - Host-app snapshot at showPanel, and a browse-panel CaretActionStatusRow for not-OSS, must be added to the plan before build
* Insights
    - The previous five blockers are named in the plan; the remaining holes are Caret-as-frontmost after the picker steals focus, and failSkillPreview rendering only inside GatewayActionPanel
    - SelectionMonitor clears lastTarget once Caret is frontmost, so allowingCaretPanelForPID cannot recover a host PID that was never saved
    - customActions from `caret/skills/<id>/` is the picker identity path for machines that already have Application Support notes

## 2026-09-19 - PREFLIGHT - COMPLETE (FAIL (fixable))

* Work completed
    - Re-validated the HostContext + request-reply replan against browsePanel's empty-skills status row, selectActionFromPanel, SkillActionRunner, runAction, and CaretPanel's floating level
    - Wrote `memory-bank/active/.preflight-status` with first line `FAIL (fixable)`
* Decisions made
    - Did not edit the implementation plan (no TDD swap or change-detector strike)
    - A status row visible after a JSON skill exists, and orderOut-before-Jev after claiming the offer, must be added to the plan before build
* Insights
    - HostContext at showPanel, install_offer, built-in registry, and pid/bundle accept are named and match the current call sites
    - Non-gateway action select only scopes; prepare runs only after a caret/skills JSON skill is clicked, which hides the existing CaretActionStatusRow
    - Cmd-1 does not hide the panel; computer-use-jev would run under a .floating CaretPanel

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Replan 5 under an operator override to stop folding single preflight bullets; traced the whole explicit-invoke path in the current source rather than patching the last finding
    - Read CaretApp, CoreBridgeProvider, SkillActionRunner, SelectionMonitor, FocusedTargetCapture, CoreBridgeClient, CoreProtocol, SkillRepository and CaretPaths on the Swift side, and bridge, router, engine, registry, context, unavailable and native_computer_use on the Python side
    - Rewrote tasks.md as six TDD units naming concrete call sites, render conditions and accept-time panel and capture behavior
* Decisions made
    - One-click invoke: selectActionFromPanel runs the action instead of scoping, taking filteredSkills off the path
    - A dedicated Model.explicitStatus row in browse-panel header chrome, independent of backendStatus and failSkillPreview
    - The prepare reply is installed in CoreBridgeProvider's own store and announced via onActionsChanged, because syncActionOffers is the only writer of model.actionOffers and the only place Cmd-1 is armed
    - Non-executing offers are dropped on install, because visibleExecutableActions sorts by UUID
    - standDownForExplicitRun orders out after the synchronous claim; resumeAfterExplicitRun on the terminal state is the only place capture resumes
    - Click-outside suppressed while a prepare is in flight; Escape stays the cancel
    - Descriptor pins execution_method, sample_only and empty missing_inputs to satisfy CaretActionOffer.isExecutable
    - Jev runs two goal templates, never the raw complaint
* Insights
    - Setting model.actionOffers from the reply is the subtlest trap on this path: it renders correctly, leaves Cmd-1 dead, and is erased by the next ambient event
    - Router.accept compares the acceptance against _current_target as well as the offer, so capture must stay paused for the whole session
    - CaretPaths.skillsRoot is nil without a project root, so the picker identity needs both the JSON skill directory and the seeded note
    - actions.adapters() is asserted to hold exactly two ids, so test_the_action_table_matches_the_registered_ids is a planned modification, not a break

## 2026-09-19 - PREFLIGHT - COMPLETE (FAIL (fixable))

* Work completed
    - Traced the full explicit-invoke path against current Swift and Python source under the wider operator override
    - Verified the planned Cmd-1 arming, executable gate, offer replacement, panel stand-down and terminal resume directions, then checked one transition beyond each
    - Wrote `memory-bank/active/.preflight-status` with first line `FAIL (fixable)`
* Decisions made
    - Did not edit the implementation plan because no TDD swap or change-detector strike applied
    - Replan must cover stale ambient failures, offered-only choice ordering, real Escape cancellation fencing, lifecycle TDD coverage, issue-detail recommendation, and typed `gh` failures
* Insights
    - `Router.complete_failure` does not stale-check, so an ambient evaluation superseded by explicit install can still emit `failed` and disable Cmd-1 interception
    - Retaining executing offers preserves terminal delivery but current visibility filters also keep those running records in UUID-sorted Cmd choices
    - Cancelling a Swift bridge waiter cannot stop synchronous core preparation; late replies need an explicit session identity and disposal path
    - Issue-list title/state data cannot satisfy the brief's requirement to summarize an existing report and judge whether the complaint adds information

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Replan 6: dropped `gh`; public GitHub HTTP for research; auth only at Jev submit
    - Folded Sol-5 findings as GSD patches
* Decisions made
    - No Caret GitHub token on prepare
    - `SearchFailed` is not not-OSS
    - No session state machine

## 2026-09-19 - BUILD - IN-PROGRESS

* Work completed
    - Operator invoked `/niko-build` and overrode the leftover replan-5 `FAIL (fixable)` gate: do not re-preflight, do not ask for plan review
* Decisions made
    - Build replan 6 as written
* Insights
    - No creative-phase docs exist for this task

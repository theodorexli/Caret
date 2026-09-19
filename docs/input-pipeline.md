# Input routing and package ownership

This is the approved implementation contract for the input, UI, workflow and context agents. Sam approved implementation on September 19. The shared core described here is now implemented in `caret/` and reachable over a process boundary; see [What is implemented](#what-is-implemented) for the line between that and the work still owned by the app and the executors. The wire format is in [bridge-protocol.md](bridge-protocol.md).

## Five upstream packages

| Package | Responsibility | Integration boundary |
| --- | --- | --- |
| `keytype` | Inline autocomplete, caret geometry, text insertion | Reuse selected native components inside Caret |
| `ghosttype` | Reference for the second text interaction mode | Merge useful components into the same app; Teddy's hoverable is the action UI |
| `computer-use-jev` | Jev-driven native Mac actions | Adapt its persistent Swift Accessibility worker and typed decisions |
| `skyvern` | Browser control | The only browser execution engine |
| `screenpipe` | Computer history and context retrieval | Owned by the existing context teammate; keep its current pin |

GhostType upstream is itself an autocomplete app. "GhostType mode" in this product means the action hoverable; it does not mean its upstream already implements workflows. Do not run KeyType and GhostType as two apps or install their event taps independently. Caret owns one focus tracker, one suggestion state and one keyboard acceptance path.

`computer-use-jev` is chosen because Skyvern already covers the browser. The remaining executor needs native AX targets and a persistent Swift worker. Its Go coordinator is an explicit integration dependency, currently Go 1.26 at the pinned revision. The existing Python core stays in place. Do not launch the upstream autonomous goal loop every two seconds, and do not use its browser actions as a second browser engine. Text generation remains a separate model call.

Removed from the active checkout: Jev Ultrafast and Browser Harness duplicate browser execution; TypeSafe Computer Use duplicates native execution and adds an OCR-heavy observation path; ActivityWatch, Backscroll, OpenRecall and Retrace provide alternative history collection. ActivityWatch's dedicated AFK/time analytics are outside the selected scope. No current runtime or retained upstream depends on these seven top-level modules. Historical commits retain these references if needed.

## One input loop, two Jev decisions

```text
Application + clipboard + field/selection + Screenpipe history + computer observations
    -> one current context frame
    -> Jev #1: ABSTAIN | INLINE | ACTION
        ABSTAIN -> nothing shown
        INLINE  -> short completion or simple correction -> visible edit -> Tab
        ACTION  -> Jev #2: workflow or allowed computer task -> action hoverable
                    -> user selects -> workflow preview -> execution -> verified result
```

The first decision determines whether Caret has anything useful to offer. INLINE covers a short continuation or simple grammar repair. Larger rewrites, navigation and cross-app work belong to ACTION. Jev classifies; a fast model hosted on Groq generates inline text. Use Cursor's autocomplete interaction as the reference. Keep the Groq model configurable until latency and quality are measured on representative inputs, and let code limit the edit range.

Both queries use one shared judge interface: context in, an explicit set of allowed choices in, one validated choice out. The app and individual workflows must not each build a different ambient router. Jev supplies the judgment at a decision point; code defines the available branches and carries out the selected operation. A model choice can vary between calls, so this is not a claim of deterministic model behavior.

Run the second query only when ACTION wins. It chooses a seeded workflow ID or a supported computer task, with a NONE result available. Workflow code fixes the execution method: Gmail and Calendar integrations for their supported operations, Skyvern for browser steps, Computer Use Jev for native steps. An unsupported task must not silently become unrestricted computer use.

The second query may prepare a read-only proposal before a keystroke so the hoverable is ready. Preparation does not send, write a calendar, type into another app or navigate the user's browser. Acceptance starts the requested workflow. Each consequential step still names its actual effect in the preview.

## Explicit invoke (panel, not ambient)

Some actions are picked from the panel and never go through the two-second
judge. `report-github-issue` is the first: the user opens the panel, Caret
freezes `HostContext` from the frontmost app before presenting, capture stays
paused, and the row runs `workflow.prepare` on that frozen host plus the panel
query as the complaint. The panel stays up until the user accepts the minted
offer or cancels.

This lane owns its own offer install (`Router.install_offer`). It must not
`submit` the ambient queue, must not emit a `failed` event, and must not resume
capture until the accepted run reaches a terminal state. Cmd-1 is armed only
for `.offered` rows, and preparing this action drops every other non-running
offer so the chord is deterministic. Accept orders the panel out
(`standDownForExplicitRun`) without `hidePanel`, so capture does not restart
and the floating panel does not sit over the browser computer-use-jev is
driving. A terminal state is the only resume. Escape cancels the session:
the generation counter advances, a late `prepareWorkflow` install is discarded
from the provider store, and `clearPanelScope` clears the searching sentence.
A finished run writes its summary after that clear so the next panel open can
show it.

The ambient lane still owns `context.update`, the two Jev decisions, and
inline Tab. Explicit invoke must not call `SkillActionRunner` and must not
treat a picker click as a gateway skill scope. Failures on this path are a
status row next to the action list (`explicitStatus`), not the inline
backend banner.

## Two-second cadence

The initial routing interval is 2,000 ms, as requested. This is a starting product setting, not a measured latency or quality claim. At continuous activity it allows at most 1,800 first-stage calls per hour before skips; second-stage and writer calls are additional.

- Sample the latest changed context at most once per interval while the user is interacting. Do not wait for two seconds of silence, which would starve continuous typing.
- Allow one first-stage request in flight. Coalesce further changes into the latest snapshot rather than queueing requests.
- Skip unchanged snapshots, idle periods and mouse movement that changes no meaningful target or selection. Mouse position alone is not new semantic context.
- Pause for secure fields, excluded apps, lock/sleep, permission loss, IME composition and Caret's own generated input. Suspend ambient proposals while a workflow owns the mouse or keyboard; genuine user input interrupts that execution.
- Tag every response with the originating snapshot revision. Discard stale results before presentation and recheck the exact target immediately before committing an edit or action.
- Dismiss a preview as soon as its field, text, selection or caret changes. Preserve native Tab behavior while a fresh preview is unavailable.
- Suppress a dismissed proposal for the same context. Repeated abstention on unchanged input does not justify another model call.

The fast snapshot comes from Caret's live AX focus/caret reader. Screenpipe adds relevant history, with source IDs and capture times. Do not wait for Screenpipe to rediscover the current caret or send its whole history to Jev each tick. This live field read is part of input handling, not a second history recorder.

The context frame includes the current application/window, focused text and selection, permitted clipboard text, relevant history, and the latest computer-use observation or result. Attach capture times and source references. Mark missing sources explicitly; an unavailable clipboard or history provider must not become fabricated context. Collect clipboard changes once at the app boundary rather than having every workflow poll it. The clipboard remains unchanged by observation.

## Keyboard contract

| State | Tab | Command–1 / 2 / 3 |
| --- | --- | --- |
| No visible valid offer | Host app receives Tab unchanged | Host app receives the shortcut unchanged |
| Inline text preview | Commit the displayed completion or correction | No action cards, so pass through |
| Action hoverable | Pass through unless a primary action explicitly displays a Tab hint | Choose the corresponding visible action |
| Workflow preview | Only activate the exact visible primary effect when that preview owns Tab | Choose visible alternatives if provided |

Only one Caret view owns Tab at a time. Showing action cards dismisses an inline offer. Shortcut interception must be scoped to a visible, current offer and must consume the event exactly once. A global observer alone cannot implement key suppression.

Hover reveals an action without requiring a click. Keep the host field focused for inline suggestions. Escape dismisses; it does not rewrite text. Text insertion must preserve the clipboard and participate in the supported host app's undo. A generic Tab must never mean an undisclosed send or booking. The hackathon stops before payment.

## Contracts between owners

These records now exist. The table names where each one lives so a change is made in one place.

| Record | Required information | Implemented as |
| --- | --- | --- |
| `InputSnapshot` | Revision, capture time, app PID/bundle ID, window and element identity, role/security status, caret/selection in UTF-16 offsets, bounded nearby text and digest, relevant source references | `caret.context.InputSnapshot` |
| `ContextFrame` | Current input snapshot, permitted clipboard content, retrieved Screenpipe context and recent computer observations/results, each with freshness and availability | `caret.context.ContextFrame` |
| `RouteDecision` | Snapshot revision, ABSTAIN/INLINE/ACTION, model result and decision timing; no executable code or invented selectors | `caret.judge.Verdict` |
| `InlineProposal` | Snapshot revision, exact replacement range, replacement text, original-value digest | `caret.router.Offer` (`kind="inline"`) |
| `ActionProposal` | Snapshot revision, stable proposal/workflow IDs, visible title and effect, required inputs, evidence, supported execution method | `caret.router.Offer` (`kind="action"`) |
| `WorkflowRun` | Accepted proposal, original target, current stage, recorded effects/remote IDs, cancellation state and completion evidence | `caret.registry.ExecutionResult`; remote IDs still unused |

Screenpipe owns history retrieval and retention. The app owns live target identity and keyboard handling. A model's confidence is not permission to act, and confidence cutoffs need task-specific evaluation before anyone calls them calibrated.

### Workflow handoff

Sam's workflow registry supplies each workflow's stable ID, description, required inputs and supported operations. Paul has proposed `jev-scheduler/` in PR #1; this is a teammate, distinct from the author of `paulsmith/computer-use-jev`. Its `runPipeline()` takes no arguments, resolves its input files from the process working directory, and posts to `SCHEDULE_WEBHOOK_URL` when that variable is set. So it cannot be ambient preparation and cannot be handed live context. It is registered as an opt-in sample workflow instead: `caret.adapters.paul_scheduler` describes the run during preparation and starts his code only after an acceptance, in a separate Node process with the webhook variable removed and his Jev client in its own mock mode. His directory is not copied here and his planner is not reimplemented. The judge selects only registered, available choices. Each workflow exposes preparation from a context frame, execution of an accepted proposal, and cancellation. Preparation returns the visible effect, inputs still needed and evidence; missing inputs produce a request for those inputs rather than execution.

Execution returns its status, recorded effects and source-backed results to the shared context. A workflow can ask the same judge to select its next allowed step when that step needs judgment. Fixed steps remain ordinary code. Skyvern or the native executor runs a selected step and returns an observation; neither starts a competing ambient loop. The workflow owns execution until completion, cancellation or user interruption.

The first implementation slice is done: a changed context frame reaches a real Jev decision, a typed offer returns over the bridge, and an accepted action runs a registered workflow that returns a structured result. Abstention, stale-response rejection, one acceptance causing one execution and an actual returned result are covered by tests. Inline insertion and each executor still need their own supported-app proof when connected.

## Accessibility onboarding is part of the product

The UI owner should make permission status recoverable without terminal commands:

1. Explain Accessibility in terms of placing suggestions and applying accepted edits. Say "supported apps" rather than promising every field in every app.
2. Show a clear Enable action that opens macOS Accessibility settings. The user enables the permission; Caret cannot silently grant itself access.
3. Recheck when the user returns and show a small typing exercise that confirms capture, caret placement and Tab acceptance separately. A checked permission toggle does not prove all three work.
4. Keep a stable bundle identifier, install/build path and signing identity. Align Xcode and `make app`; do not send users between permission entries for Terminal and several Caret binaries. The upstream CLI's permission setup is not the shipping app's onboarding.
5. Request Input Monitoring only if the chosen event mechanism requires it. Request Screen Recording when Screenpipe/OCR capture needs it, with its own explanation. Do not block inline AX completion just because optional history capture is unavailable.
6. Show denied, revoked and helper-disconnected states with one recovery action. Stop capture immediately on revocation. Offer pause and app exclusions from the menu bar.

Current UI review targets for Teddy: `Model.run` logs raw selected text; `SelectionMonitor.publish` excludes selection contents and field identity from its dedupe signature. Remove raw text logging and introduce snapshot identity before attaching model calls. These are source-review findings, not changes made to the UI in this branch.

## What is implemented

The shared core runs today. The app boundary, the executors and history
retrieval do not.

**In `caret/`, with tests:**

| Piece | Module | What it does |
| --- | --- | --- |
| Context records | `caret/context.py` | Typed snapshot, clipboard, history, observations and source availability, with UTF-16 offsets and bounds |
| Shared judge | `caret/judge.py` | One interface for both decisions; an answer outside the supplied choice IDs is rejected |
| Jev client | `caret/providers/jev.py` | Real `POST /v1/systemone` Choice question, verified against the pinned `computer-use-jev` client |
| Groq client | `caret/providers/groq.py` | Real chat-completions call for inline text |
| Scheduling | `caret/router.py` | Two-second cadence, one in-flight evaluation, latest snapshot wins, staleness, suppression, single-use acceptance |
| Two decisions | `caret/engine.py` | Route, then the workflow question only on ACTION, then execution on acceptance |
| Workflow seam | `caret/registry.py`, `caret/adapters/` | Availability, preparation, execution, cancellation |
| Process boundary | `caret/bridge.py` | Persistent JSON-lines stdio bridge; see [bridge-protocol.md](bridge-protocol.md) |

A second judge exists for one reason: to make the loop runnable on a machine
with no Jev key. `caret/providers/gateway.py` reaches Vercel AI Gateway with one
variable, `AI_GATEWAY_API_KEY`, and supplies both a writer and a classifier, so
`--judge gateway --writer gateway` exercises routing, generation, workflow
selection and acceptance end to end. That classifier is a general chat model
asked for JSON naming one of the choice IDs, which is weaker than a typed
decision service: it can ignore the schema, and only `validate_choice` stops a
made-up answer. Jev remains the product judge and the default, and nothing falls
back to the Gateway; it is selected only when a caller names it. No live call
has been made to Vercel AI Gateway, Jev or Groq from this branch. Both Gateway
clients are written against Vercel's published documentation and covered by
tests with a fake transport, and the CI job that would call the service runs on
manual dispatch only.

Two ambient workflows are registered and available: the existing sample planner, which
writes local SQLite holds on labeled synthetic data, and the opt-in
`jev-scheduler` adapter. `book-flight` and `revise` register as unavailable with
their reason, so the judge is never offered them. `report-github-issue` is a
built-in that is available only on an explicit-invoke frame; see
[Explicit invoke](#explicit-invoke-panel-not-ambient).

**Not implemented here, and not started by this slice:**

- **Ambient Swift still does not drive the two-second loop by itself.** Teddy
  owns live AX frames, the hoverable, and Tab / Command ownership. Explicit
  invoke is the exception: the Mac app freezes the host, calls
  `workflow.prepare`, installs the reply offer, and accepts through the
  existing `offer.accept` path.
- **No capture wiring for history.** The core consumes supplied clipboard text, Screenpipe
  results and computer-use observations. Nothing retrieves Screenpipe on this
  path. Explicit invoke does read the pasteboard into the frame it sends.
  `secure`, `ime_composing`, `app_excluded`, `accessibility` and
  `workflow_active` are all caller-supplied, so suppression is only as good as
  what the app reports.
- **Skyvern is still unwired.** Computer Use Jev is the executor for an
  accepted `report-github-issue` offer, using a templated goal. An unsupported
  workflow remains an unavailable choice, never a fabricated result.
- **No live provider run recorded.** The clients are written against the pinned
  upstream source and the published docs, and are covered by tests with a fake
  transport. No call has been made to any of the three services from this branch.

## Work split and acceptance

- **Teddy / UI:** hoverable, inline presentation, scoped Tab/Command shortcuts, focus restoration and permission onboarding. Preserve the new UI rather than replacing it with the older sample popup.
- **Context owner:** Screenpipe integration, exclusions, freshness, source references and bounded retrieval. No competing history engine.
- **Sam / workflows:** select and define the two demo workflows. The three existing catalog seeds remain until that decision is made.
- **Router integration:** implement the two decisions, latest-snapshot scheduling, writer handoff and typed native/Skyvern adapters against the contracts above.

First prove the loop in one supported text app: correct offer, Tab inserts once, undo works, and a focus switch makes an old response unusable. Then connect one real workflow to Teddy's cards. Exercise continuous typing, IME input, secure fields, permission denial/revocation, duplicate keypresses and user interruption. Measure offer acceptance, unwanted interruptions, latency and calls per active minute before tuning the interval or confidence rules.

The reviewed app commit `827a387` has a cursor-adjacent trigger, a pinned action strip, a scrollable menu, install packaging and Accessibility reconnection. Its current pinned shortcuts use Command–Option–1/2/3; the product keyboard contract above remains the integration target. Explicit invoke is the live exception: the panel calls `workflow.prepare` and accepts through `offer.accept`. Ambient inline insertion, Screenpipe retrieval and Skyvern remain integration work.

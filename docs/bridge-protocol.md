# Bridge protocol

Reference for calling Caret's judge from the Mac app. The routing rules it
implements are in [input-pipeline.md](input-pipeline.md); this page is the wire
format.

The app spawns one long-lived process and keeps it alive:

```sh
python3 -m caret.bridge --fixture fixtures/meeting.json --db .local/caret.sqlite
```

One JSON object per line, in both directions. There is no HTTP server, no port
and no extra packaging: it is the repository's own Python over a pipe.

## Requests and replies

A request carries an `id` and gets exactly one reply with the same `id`.

```json
{"id": 1, "method": "context.update", "params": {"frame": {...}}}
{"id": 1, "ok": true, "result": {"status": "admitted", "reason": "", "revision": 7}}
```

A failure replaces `result` with a coded error:

```json
{"id": 4, "ok": false, "error": {"code": "acceptance_rejected", "message": "..."}}
```

| Method | Parameters | Returns |
| --- | --- | --- |
| `hello` | none | Protocol version, the cadence and bound settings, and the workflow catalog |
| `context.update` | `frame` | `status`: `admitted`, `coalesced` or `skipped`, with a `reason` |
| `offer.accept` | `proposal_id`, `revision`, `target` | The inline edit to apply, or the workflow's execution result |
| `offer.dismiss` | `proposal_id` | `{"dismissed": true}` |
| `workflow.prepare` | `workflow_id`, `frame` | `{"offer": …}` — one minted action offer |
| `workflows.list` | none | Every registered workflow with its execution method |
| `shutdown` | none | `{"stopped": true}`, then the process exits |

Error codes: `invalid_json`, `invalid_request`, `invalid_context`,
`unknown_method`, `acceptance_rejected`, `workflow_error`, `provider_error`,
`internal_error`. The last one is the catch-all: an exception no other code
covers still gets a reply, because a request that is answered by the process
exiting cannot be retried.

`workflow.prepare` is request-reply only. It names a registered workflow and a
context frame, installs the resulting offer on the router without submitting
the ambient queue, and returns that offer on the same `id`. It does not wake
the evaluator and it does not write an `offer`, `failed`, or `invalidated`
event. A `WorkflowError` from the adapter — not-open-source, empty complaint,
search failure — is `workflow_error` on the reply. A malformed frame is
`invalid_context`. The app shows the sentence from the reply; it must not wait
for a later event on this path.

## Events

`context.update` returns as soon as the frame is recorded, because a provider
call must not block input handling. The outcome arrives later as an unsolicited
line with no `id`.

```json
{"event": "offer", "offer": {"kind": "inline", "proposal_id": "...", "revision": 7, ...}}
{"event": "abstain", "revision": 8, "reason": "judge-abstained"}
{"event": "invalidated", "proposal_id": "...", "reason": "context-changed"}
{"event": "discarded", "revision": 6, "reason": "stale-snapshot"}
{"event": "failed", "revision": 9, "reason": "judge/route: HTTP 401 from api.typesafe.ai"}
```

`invalidated` means a visible offer stopped being valid and the hoverable or
inline preview should come down. `failed` means a provider failed: show nothing
and do not retry from the app, because the next context change schedules the
next attempt by itself.

Event lines are written in the order the router made the decisions, so an
`offer` always arrives before the `invalidated` line that retires it, even when
the user's next keystroke lands in the middle of the evaluation that produced
it. The app can drive its preview from the stream in arrival order; it does not
have to hold an `invalidated` back in case the matching `offer` is still coming.
Replies and events share the one output stream, and a reply is not a barrier: an
event caused by a `context.update` may be written before or after that update's
reply. Correlate the two by `revision`, not by position.

## The context frame

The app fills this in. The core never observes macOS, so every field below is
the app's own reading, including whether the field is secure and whether
Accessibility is still granted.

```json
{
  "snapshot": {
    "revision": 7,
    "captured_at": "2026-09-19T12:00:00+00:00",
    "target": {"pid": 4242, "bundle_id": "com.example.Editor", "window_id": "w1",
               "element_id": "compose", "element_revision": "v7"},
    "role": "AXTextArea",
    "nearby_text": "I will send the ",
    "text_offset": 0,
    "caret": 16,
    "selection": {"start": 16, "end": 16},
    "secure": false,
    "ime_composing": false,
    "app_excluded": false,
    "value_length": 16
  },
  "permissions": {"accessibility": true},
  "clipboard": {"available": true, "text": "...", "captured_at": "..."},
  "history": [{"source_id": "sp-1", "captured_at": "...", "text": "...", "app": "..."}],
  "observations": [{"source_id": "cu-1", "captured_at": "...", "kind": "result",
                    "summary": "...", "status": "ok"}],
  "sources": [{"name": "screenpipe", "available": true, "captured_at": "..."},
              {"name": "computer-use", "available": false, "detail": "no executor"}],
  "workflow_active": false
}
```

Rules the app has to honor:

- **`revision` increases monotonically.** A revision at or below one already
  seen is refused as superseded. It is how a late provider answer is recognised
  as belonging to text the user has moved past.
- **Offsets are UTF-16 code units**, matching `kAXSelectedTextRange`. `caret`
  and `selection` are absolute positions in the full field value;
  `nearby_text` is a bounded window starting at `text_offset`. Send a window
  that contains the caret.
- **Send a bounded window.** Over the limit the frame is rejected rather than
  truncated, because truncating would shift the offsets an edit is applied at.
  Limits: 4,000 UTF-16 units of nearby text, 2,000 of clipboard, 20 history
  items, 10 observations.
- **State absence explicitly.** An unavailable clipboard is
  `{"available": false}`, not an empty string, and a source that failed belongs
  in `sources` with `available: false`. The judge is told what is missing.
- **`secure`, `ime_composing`, `app_excluded`, `permissions.accessibility` and
  `workflow_active` drive suppression.** The core reads them and nothing else;
  it cannot see the screen. If the app does not report a secure field, the core
  cannot know.

## Applying an accepted inline edit

`offer.accept` on an inline proposal returns a range and replacement text; the
app performs the insertion, owns undo and owns the clipboard.

```json
{"kind": "inline", "status": "ready_to_insert",
 "target": {...}, "replace_start": 16, "replace_end": 16,
 "replacement": " summary to the team",
 "original_digest": "e3b0c44298fc1c14"}
```

`replace_start` equals `replace_end` for an insertion at the caret; with a
selection they are exactly that selection's bounds. The model supplies only the
characters: the range is chosen by code, so a proposal can never name a region
the user did not have selected.

Revalidate the live target against `target` and the existing content against
`original_digest` immediately before inserting. Acceptance is refused if the
target changed, if the revision does not match, if the proposal is more than 30
seconds old, or if it was already accepted. A repeated acceptance is rejected
before any workflow runs, so a duplicate keypress cannot execute twice.

## Providers

| Option | Key | Optional overrides |
| --- | --- | --- |
| `--judge jev` (default) | `TYPESAFE_API_KEY` | `TYPESAFE_ENDPOINT`, `TYPESAFE_MODEL` |
| `--writer groq` (default) | `GROQ_API_KEY` | `GROQ_ENDPOINT`, `GROQ_MODEL` |
| `--judge gateway` | `AI_GATEWAY_API_KEY` | `AI_GATEWAY_ENDPOINT`, `AI_GATEWAY_JUDGE_MODEL` |
| `--writer gateway` | `AI_GATEWAY_API_KEY` | `AI_GATEWAY_ENDPOINT`, `AI_GATEWAY_MODEL` |

A missing key is a startup error: the process exits non-zero naming the variable
before it reads a single request. Nothing falls back to a canned response, so an
unconfigured machine fails visibly instead of producing output that looks like a
model result.

The two `gateway` options run through Vercel AI Gateway, which speaks the OpenAI
chat-completions shape. `--writer gateway` is an ordinary text model.
`--judge gateway` is an LLM classifier: it asks a chat model for JSON naming one
of the choice IDs Caret supplied, and an answer outside that list is refused. It
is not Jev, it is weaker than Jev, and it is selected only when asked for by
name. It exists so the whole two-decision loop can be exercised with one key.
Both default to `amazon/nova-micro`, the cheapest of the fast text models
Vercel's catalog lists for classification and inline suggestion; that is a
documented price-and-fit choice, not a measured one.

`--judge scripted:<path>` and `--writer scripted:<path>` replay a recorded
script. They exist for tests and for the offline example and are never selected
automatically.

`--interval` and `--failure-backoff` set the cadence and the wait after a failed
evaluation. A failure does not suppress its context, so without that wait a
provider that is down would be called again on every keystroke.

## Trying it

```sh
python3 scripts/caret_bridge_example.py                            # no keys, no network
python3 scripts/caret_bridge_example.py --providers live-jev-groq   # both product keys
python3 scripts/caret_bridge_example.py --providers live-gateway    # one Gateway key
```

The example drives the real bridge process with invented input: context updates
inside one interval, the resulting offer, an acceptance, and the same
acceptance a second time. The default run proves the transport, the scheduling
rules and the workflow seam. Only a live run proves anything about the
providers, and a live mode refuses to start when its variable is unset rather
than quietly falling back to a script.

`.github/workflows/live-smoke.yml` runs the `live-gateway` mode on manual
dispatch only. It bills real model calls and it is the only workflow that reads
a provider key, so it is deliberately not attached to a push or a pull request.

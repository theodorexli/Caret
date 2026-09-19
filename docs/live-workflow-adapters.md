# Live workflow adapters

Two adapters in `caret/live_workflows/` plug into the `WorkflowAdapter` seam in
`caret/registry.py`: `book-calendar-link`, which drafts a reply offering meeting
times, and `book-flight`, which reports why it cannot run. Neither sends mail,
writes a calendar or drives a browser.

This page is for whoever registers them and whoever adds the next adapter.
For the seam itself see [bridge-protocol.md](bridge-protocol.md); for the
integration contracts they are written against see
[integrations.md](integrations.md).

## book-calendar-link

The input is the caller's live `ContextFrame`: the text in the focused field,
as the app sent it. No fixture is read.

`prepare` reads that text, asks a configured availability source about the
window the candidate times span, drops every candidate whose buffered hold
overlaps a busy interval, and returns a draft with one evidence line per
surviving option. `execute` returns that draft as `ExecutionResult.data`. That
is the entire effect: `data["sent"]` and `data["calendar_event_created"]` are
both false and there is no code that could make them true.

### The text grammar

Only marked times are proposed:

```
Candidate: 2026-09-22T10:00:00-05:00
Candidate: 2026-09-22T14:00:00-05:00
Duration: 45 minutes
```

A candidate is the marker word, then one ISO 8601 date-time with a `T`
separator and a UTC offset (or `Z`). The duration is marked the same way and
may be given in minutes or hours, once.

Free-running date scraping would read "I cannot meet at
2026-09-22T10:00:00-05:00" and a timestamp quoted from an older message below
the reply as offers, and offering a time the writer ruled out is the one
mistake a draft must not make. So an unmarked timestamp, a date-time with no
offset, a bare wall clock and a relative phrase are all reported back as
mentions the adapter did not interpret, and the preparation says what to write
instead. Ambiguity is never resolved by guessing: two marked durations are two
durations, not an average.

A caller can build a `MeetingRequest` and call `prepare_request`, but corrected
timestamps and duration must also appear as marked values in the current field.
A nonempty excerpt alone does not prove a date. There is no separate correction
panel input channel in this adapter.

Bounds: at most 12 candidates in one request, candidates within 14 days of each
other, durations from 5 to 480 minutes, and at most 3 options in a draft. Each
input bound is a refusal with a reason. The draft keeps the earliest three free
options; additional free options are not separately listed as dropped.

### Availability

One source must be configured. Without one the workflow is unavailable and the
judge is never offered it. Missing configuration is never read as a free
calendar.

**Google Calendar free/busy.** Set `CARET_GOOGLE_CALENDAR_TOKEN` to a bearer
token with a read-only or free/busy scope, and `CARET_GOOGLE_CALENDAR_IDS` to a
comma-separated list of calendar IDs. Nothing else in the environment is read.
`GoogleFreeBusySource` POSTs `timeMin`, `timeMax`, `timeZone` and `items` to the
fixed endpoint `https://www.googleapis.com/calendar/v3/freeBusy` over stdlib
`urllib`, with a short timeout and redirects refused, so a 3xx cannot resend the
Authorization header somewhere else.

The reply is parsed strictly. A body that is not JSON, bounds that do not cover
the window that was asked for, a requested calendar that is missing, a
per-calendar `errors` entry, an omitted `busy` list, or a malformed or
backwards interval each raise `AvailabilityError`. A busy interval is
`[start, end)`, as Google documents it. No failure message contains the token or
any part of the response body.

**Captured snapshot.** Set `CARET_AVAILABILITY_SNAPSHOT` to a JSON file with
`covered_start`, `covered_end`, `captured_at`, `provenance` and an explicit
`busy` list. The busy list must be present: an omitted one would claim the whole
covered window is free. The source refuses a window it does not cover and
expires after 24 hours by default, and its label says it is a replayed capture
and not a live calendar read. That label is what ends up in the evidence and in
`data["availability_source"]`, so a snapshot cannot be shown as API evidence.

An availability source that fails produces no draft. There is no path anywhere
in this package by which a failure becomes an empty busy list.

### Acceptance

The preparation is one-use and held in memory on the adapter instance, which is
enough because nothing external was written and there is nothing to reconcile.
Acceptance recomputes the checks rather than trusting the payload it is handed:
the preparation must still be pending, be younger than 180 seconds, carry the
same proposal and the same evidence it was prepared with, name the same target
field, match the frame signature and text digest, quote excerpts still present
in the field, and propose times that have not passed. Accessibility,
`secure`, `app_excluded` and `ime_composing` are checked separately, because
`ContextFrame.signature()` does not cover them. These checks use the frame the
caller supplies. The inspected bridge passes the preparation frame, not a fresh
macOS observation, so these tests do not establish live permission or target
revalidation. The native owner must revalidate immediately before insertion or
any external effect. This adapter itself only returns text.

Only the newest preparation is retained. Preparing another discards the old draft;
the remaining one can stay in memory until execute, cancel or process shutdown.

The result acceptance returns is built during `prepare` and stored; `execute`
returns that object. Nothing the caller hands back can change what the workflow
reports it produced. A second acceptance, a cancelled preparation and a
tampered one all fail without effect.

## book-flight

Permanently unavailable in this slice, with the reason in
`Availability.reason`: Skyvern is the only permitted browser executor, and no
Skyvern capability is configured whose URL allowlist and pre-payment stop are
enforced by the runner. A prompt telling an agent to stop before payment is text
the page can argue with, so it is not accepted as a guard. `prepare` and
`execute` raise rather than improvising a lesser effect; there is no network
call in the module. `caret/live_workflows/flight.py` is where a real
implementation goes once an enforcing capability exists.

## Registration

Both classes take no constructor arguments. The following is the agreed integration
hook, not a runnable command on this branch. The core owner must first land
`caret.bridge` and its `--adapter` loader; the inspected reference bridge does not
yet accept this flag. Alternatively its owner can explicitly register the instances
returned by `caret.live_workflows.actions.adapters()`.


```sh
python3 -m caret.bridge \
  --adapter caret.live_workflows:MeetingDraftWorkflow \
  --adapter caret.live_workflows:SkyvernFlightWorkflow
```

`caret/live_workflows/actions.py` holds `ACTION_WORKFLOWS`, which maps the Mac
app's action IDs (`CaretApp.actions` in
`apps/mac/Sources/Caret/CaretApp.swift`) onto these workflow IDs. Both already
use the stable IDs, so the mapping is the identity; the other actions map to
`None` because they are text transforms with no adapter.

Dependencies are injected for tests: `MeetingDraftWorkflow(availability_source=,
clock=, environ=)`, and `GoogleFreeBusySource(transport=)`. With no arguments
the source comes from the environment.

## Tests

```sh
python3 -m unittest discover -s tests
CARET_CORE_REFERENCE=/path/to/core-checkout python3 -m unittest discover -s tests
```

`tests/test_live_requests.py` covers reading the text and needs nothing but this
package. `tests/test_live_workflows.py` needs `caret.registry` and
`caret.context`. Until those merge, `tests/live_support.py` locates them through
`CARET_CORE_REFERENCE`, which it appends to `caret.__path__`; the modules are
never copied. Without the variable the module skips and says so, rather than
passing quietly.

No test opens a socket. The Google source is always driven through a recording
transport, and the flight adapter has no execution path to reach.

## Not implemented

Calendar writes, tentative holds and ICS files. Sending, including drafts in
Gmail. Browser execution. Reading clipboard or Screenpipe history: the active
snapshot is the only source, so every excerpt in the evidence can be rechecked
against the field the user is looking at.

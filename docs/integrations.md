# Integration contracts

This page is for teammates connecting live services to the starter. The current CLI accepts sample data only so fixture output cannot silently become a real email.

The selected packages, input cadence, keyboard behavior and team ownership are defined in [input-pipeline.md](input-pipeline.md). Sam owns the definitions of the two demo workflows; do not expand their scope while wiring the routers.

## Source retrieval

Use the active browser or Accessibility context to identify the current thread. A Gmail adapter should retrieve every relevant message and decode plain-text bodies, retaining message IDs and timestamps. `extract_thread` currently decodes one supplied RFC 822 message; it does not infer dates, retrieve a Gmail conversation, parse HTML or resolve relative dates.

Extract the requested window, duration, location and time zone with a generative model, then validate the result against the source text. Ambiguous dates and locations need correction in the preview. Keep source excerpts available to the evidence pane.

The planner currently consumes explicit offset-aware candidate starts, busy intervals and before/after buffers. It excludes intervals that overlap even after buffers, deduplicates starts and returns at most three options. A future timetable adapter must compute those buffers from the selected route rather than treating the sample constants as travel facts.

Every candidate needs a source reference and a successful source status. Missing/failed source results are dropped. With no supported candidates, the planner creates no draft. Live calendar failures must abort planning, never become an empty busy list. Recheck availability immediately before writing events.

## Sending and holds

Create a Gmail draft from the checked options and show it before sending. `Send` must use the exact approved body and retain Gmail's returned message ID. Only a verified sent result advances the workflow to calendar holds. Handle uncertain send results by reconciling against the draft/message ID before retrying.

Create tentative Google Calendar events using stable per-run option identities. Persist returned event IDs. If only some events succeed, show that partial state and allow reconciliation; do not report that all holds exist. The current SQLite holds exercise state transitions only and are not external calendar events.

On a reply, match the selected option with its original evidence. Show a confirmation before retaining one hold and deleting the other events whose IDs belong to this run. A retry must not send another message or delete unrelated calendar events. The staged demo reply must be labeled as staged.

## Computer use and Jev

The application owns allowed operations. Jev selects a workflow ID or an operation/target from current observations. A generative model supplies text. Dates, money and target freshness are checked in code. Retrieved email and page text are evidence, not instructions that can redefine the workflow.

Use Skyvern for browser execution and the selected Computer Use Jev pipeline for native Mac actions. Neither is wired into the starter. Do not keep a second browser executor. The browser adapter must reobserve after navigation and handle frames/new tabs where checkout requires them. Stop before submitting payment. A prompt saying "stop" alone is not an execution guard.

Revise should bind its preview to the original app, window, element, selection and text. Revalidate those immediately before insertion. Adopt KeyType packages selectively and verify native undo in the supported app.

## Primary references

- [Gmail threads](https://developers.google.com/workspace/gmail/api/guides/threads)
- [Gmail drafts](https://developers.google.com/workspace/gmail/api/guides/drafts)
- [Google Calendar free/busy](https://developers.google.com/workspace/calendar/api/v3/reference/freebusy/query)
- [Google Calendar events](https://developers.google.com/workspace/calendar/api/v3/reference/events)
- [Jev documentation](https://docs.typesafe.ai/introduction)

Use app-owned OAuth and Keychain for credentials. Codex's connected accounts do not configure Caret. Keep tokens, personal threads, screenshots and local databases out of Git.

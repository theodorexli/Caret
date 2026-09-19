# System Patterns

## How This System Works

The architecture contract is [docs/input-pipeline.md](../docs/input-pipeline.md). One Jev judge uses current app, clipboard, history and computer observations to choose an inline offer or an action, then selects a workflow or supported computer task. The ambient judge and workflow bridge are still integration work.

At app commit `827a387`, the native UI observes focused fields/selections and shows action rows. Selection logs and closes the panel. The Python CLI independently plans from labeled fixtures and writes local holds to SQLite under `.local/`. The new UI does not yet invoke that CLI. There is no server or container in the default run.

The load-bearing assumption: anything that is not labeled sample data is rejected. Fixture output cannot silently become a real email. Live adapters, when they exist, must be an explicit change to that gate — not a leftover fixture field.

Five upstreams are selected: KeyType and GhostType feed one native input system, Computer Use Jev handles native actions, Skyvern handles browser actions and Screenpipe handles history. Caret.app starts the pinned Screenpipe CLI on the pin port when that port is free. If the port is taken, it does not spawn a second recorder, and it writes a lease only after `/health` matches the pin. The other three upstreams do not run in the default starter. Changing a pin, a submodule SHA, or `.gitmodules` without the others fails the source check. Preserve upstream names, licenses and authorship.

Contributor instructions that already live in `AGENTS.md` (scope, fixtures, credentials, how to check) are not repeated here.

## Process boundary is the public contract

The CLI returns the preview shape (`run_id`, `subject`, `thread_body`, `options`, `draft`, `evidence`, `notice`) and supports `preview` / `hold` / `confirm`. The old Swift caller was replaced by Teddy's action UI. Reconnect via the judge/workflow contract instead of restoring the old sample UI. App transport must carry context revisions and accepted proposal IDs; discuss changes with both owners.

## Sample data cannot become sendable

`plan()` requires `mode == "sample"`. The returned notice states that the draft cannot be sent and that holds are local only. No live Send operation exists. Removing that gate without a live adapter that verifies sources would let synthetic times look like a real offer.

## Failed sources are dropped, never filled in

A candidate without `status == "ok"` and a source is dropped. Overlaps after travel buffers are dropped. Duplicate start times are dropped. At most three remaining options are kept, earliest first. With no supported options, the draft is empty and no hold path should pretend otherwise. A model must not invent a missing time, fare, or timetable. Live calendar failure must abort planning, not become an empty busy list. The intended contracts for Gmail, Calendar, and computer-use live in `docs/integrations.md`; they are not implemented.

## Local holds are a rehearsal, not a calendar

SQLite stores a run's preview JSON and per-option rows (`tentative` / `confirmed` / `released`). Confirming one option releases the others **for that run only**. Retries must not send mail or delete another run's rows. Returned Google Calendar event IDs are a future field; they do not exist in the starter schema. Do not report that external holds exist after a local `hold` or `confirm`.

## Three workflow seeds, one local path

`caret/workflows.json` lists `book-flight`, `book-calendar-link`, and `revise`. Only the sample calendar-link planner executes. Sam owns the two demo workflow definitions; the seeds do not authorize agents to expand scope. Skyvern is the chosen browser executor and Computer Use Jev is the chosen native pipeline. KeyType and GhostType components are combined into one input/acceptance path.

## Timestamps are offset-aware

Every interval the planner accepts must include a timezone offset. Naive datetimes are rejected. Equivalent instants in different offsets still conflict. Travel buffers are nonnegative integer minutes supplied by the caller; they are not measured travel times until a timetable adapter exists.

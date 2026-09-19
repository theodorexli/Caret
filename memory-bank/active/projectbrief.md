# Project Brief

## User Story

As Caret, I want to launch the pinned Screenpipe myself and ask for last-N windows, last-N minutes, or last-N clipboard entries newest-first, so later inference can pull history through one Caret interface instead of talking to Screenpipe directly.

## Use-Case(s)

### Launch the gatherer

Caret.app starts and supervises the pinned Screenpipe (`npm screenpipe@0.4.50`) and writes the launcher lease the Python client already requires.

### Ask for last N windows

A caller asks Caret for the last N distinct windows in most-recently-active order and gets newest-first records.

### Ask for last N minutes

A caller asks Caret for all activity in the last N minutes and gets newest-first records.

### Ask for last N clipboard

A caller asks Caret for the last N stored clipboard contents and gets newest-first records. The launched Screenpipe must be recording clipboard history so this is not empty by configuration.

## Requirements

1. Caret.app launches and supervises the pinned Screenpipe from `caret/screenpipe_pin.json` and writes a live lease (`artifact_id`, `checksum`, `expected_version`, `endpoint`, `pid`, `ready_at`).
2. The launched process stores clipboard history (`--disable-clipboard-capture false` or equivalent).
3. Caret exposes one history interface with three last-N queries: windows (most-recently-active), minutes (all activity), clipboard (contents).
4. All three queries return most-recent to least-recent.
5. Missing lease, wrong version, unreachable gatherer, or empty last-N for the requested type is a hard failure.
6. Callers talk to Caret, not Screenpipe. Screenpipe stays behind the facade.

## Constraints

1. Runtime pin stays published `screenpipe@0.4.50`. Do not launch `packages/screenpipe` or copy `ee/`.
2. Python last-N talks only to the launcher lease. Do not rediscover port 3030.
3. TCC stays on the launched Screenpipe binary. Caret Accessibility does not cover it.
4. Do not invent clipboard or window text. Soft-empty last-N is not valid.
5. Scope is launch, clipboard capture, and the three last-N queries. Do not add OCR/audio/memory type APIs, TCC help docs, or a Mac history UI unless required to launch.

## Acceptance Criteria

1. Starting Caret.app starts the pinned Screenpipe (or reuses the supervised child) and writes a lease the existing Python client accepts.
2. Live `/health` on that process reports clipboard capture on.
3. `python3 -m caret history-windows --windows N` returns N distinct windows, newest-active first, or exits 1.
4. `python3 -m caret history-minutes --minutes N` returns all activity in that window, newest first, or exits 1.
5. `python3 -m caret history-clipboard --count N` (or the same interface’s clipboard query) returns N clipboard contents, newest first, or exits 1.
6. Tests cover pin argv, lease hard-fail, empty last-N hard-fail, newest-first order, and clipboard query mapping.

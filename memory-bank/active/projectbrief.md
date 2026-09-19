# Project Brief

## User Story

As a Caret contributor, I want a Debug item in the Caret menu that shows a short preview of the last two windows, last two time-ordered history items, and last two clipboard items so I can see what Caret currently sees without dumping full last-N payloads.

## Use-Case(s)

### Glance at current context

Open the Caret status-bar menu, choose Debug, and read a small window that lists up to two truncated items from each last-N slice Caret already uses: windows (recency), minutes (time), and clipboard.

### See a miss the same way Caret would

If a slice is empty, the gatherer is down, or the lease is missing, that section shows the failure instead of inventing rows.

## Requirements

1. Add a Debug option to the Caret status-bar menu.
2. The display shows the last two items of each existing last-N kind: windows (by recency), minutes (by time), and clipboard.
3. Show a short info preview only: app, title/window, timestamp, and a truncated text snippet. Do not show full OCR, accessibility structure, or raw JSON.
4. The preview must use the same last-N source Caret already uses (lease-backed Screenpipe via `python3 -m caret`), not a parallel client.
5. Do not change last-N hard-fail behavior for inference callers.

## Constraints

1. Hackathon GSD: happy-path ship, no polish.
2. Do not add purchases, hotel search, or multi-party polling.
3. Do not invent facts when a slice is empty or the gatherer is down.
4. Do not attach to launchd Screenpipe on :3030; Caret's lease on :3031 is the source.
5. Leftover `memory-bank/active/creative/creative-supabase-company-control-plane.md` is from another task and is out of scope.

## Acceptance Criteria

1. The Caret menu includes a Debug item that opens a small info window.
2. The window lists up to two truncated rows for windows, minutes, and clipboard, newest first.
3. A failed or empty slice shows an error or empty note for that section; other sections still render.
4. Existing `history-windows`, `history-minutes`, and `history-clipboard` hard-fail contracts stay unchanged.

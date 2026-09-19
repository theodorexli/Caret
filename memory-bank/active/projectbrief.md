# Project Brief

## User Story

As a Caret user, I want the Debug last-N peek (and the same last-N history client) to read pinned Screenpipe history so I can see windows, minutes, and clipboard instead of HTTP 403 Forbidden.

## Use-Case(s)

### Use-Case 1

Open Caret's Debug last-N preview while the pinned Screenpipe is running. The peek shows last-2 windows, minutes, and clipboard (or an empty-history error), not a 403.

### Use-Case 2

`python3 -m caret history-windows|history-minutes|history-clipboard` against the Caret lease returns history from the pin, not `screenpipe unreachable: HTTP Error 403: Forbidden`.

## Requirements

1. Caret's last-N client must authenticate to Screenpipe 0.4.50's local API so protected endpoints (`/search` and related) succeed.
2. The Debug peek uses that same client and must stop failing with 403.
3. `/health` remains the lease readiness check; do not treat a 403 on history as a health failure.

## Constraints

1. Keep the pinned published `screenpipe@0.4.50` on port 3031. Do not launch `packages/screenpipe` or copy `ee/`.
2. Happy-path hackathon scope: fix the deny so history can be read. Do not add purchases, hotel search, or a Swift Screenpipe client.
3. Do not commit credentials or live API keys.

## Acceptance Criteria

1. Last-N requests to the pin no longer fail solely because the client omitted required local API auth.
2. Debug peek and CLI last-N share that authenticated path.
3. Existing hard-fail cases (missing lease, wrong version, empty last-N) still fail as they do today.

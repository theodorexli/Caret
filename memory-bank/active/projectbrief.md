# Project Brief

## User Story

As a Caret user, I want Caret to start Screenpipe when the app launches unless something is already listening on the pin's expected port, so I get one recorder on that port and not a second one.

## Use-Case(s)

### Use-Case 1

I start Caret. Nothing is listening on the expected port (pin today: `3031`). Caret starts the pinned Screenpipe.

### Use-Case 2

I start Caret. Something is already listening on the expected port. Caret does not start a second recorder.

## Requirements

1. On every Caret start, launch the pinned Screenpipe if the expected port has no listener.
2. If the expected port already has a listener, do not start another recorder.
3. Make any code changes needed so that start actually runs (including putting `CaretProjectRoot` in the app bundle so the supervisor can find the pin).
4. Work on a feature branch.

## Constraints

1. Expected port comes from the pin launch args (today `--port 3031`). Do not attach to leftover launchd `:3030`.
2. Do not launch `packages/screenpipe` or copy `ee/`.
3. If Caret did not spawn the process, quitting Caret must not terminate the existing listener.
4. Keep the existing pin, lease schema, and last-N hard-fail rules.

## Acceptance Criteria

1. App start with a free expected port starts the pin and writes `.local/screenpipe-lease.json` after `/health` matches the pin version.
2. App start with a listener already on the expected port does not spawn a second Screenpipe.
3. A built Caret.app Info.plist contains `CaretProjectRoot` so `ScreenpipeSupervisor.start` is not a no-op.
4. Changes live on a feature branch (not `main`).

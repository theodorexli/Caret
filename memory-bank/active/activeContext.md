# Active Context

## Current Task: caret-screenpipe-403-history
**Phase:** BUILD - COMPLETE

## What Was Done
- Last-N `_api` now authenticates to Screenpipe 0.4.50: Bearer from `SCREENPIPE_LOCAL_API_KEY` / `SCREENPIPE_API_KEY` / `npx screenpipe@0.4.50 auth token`, plus `X-Screenpipe-Client: api`.
- New tests in `tests/test_screenpipe_api.py`. `make check` passed (48 tests, pin check, Swift build).

## Next Step
- Load the Level 1 workflow and start QA.

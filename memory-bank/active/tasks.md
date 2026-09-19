# Current Task: caret-screenpipe-403-history

**Complexity:** Level 1

## Fix

- **What broke:** Debug last-N / `python3 -m caret` history commands got HTTP 403 from Screenpipe `/search`.
- **Why:** Screenpipe 0.4.50 has no localhost bypass. Protected endpoints need `Authorization: Bearer` plus `X-Screenpipe-Client: api`. Caret `_api` only sent `SCREENPIPE_API_KEY` when that env var was set, so Caret.app Debug sent neither header.
- **What changed:** Resolve `SCREENPIPE_LOCAL_API_KEY`, then `SCREENPIPE_API_KEY`, then pinned `screenpipe auth token`. Always send both headers. Fail before the request if no token.
- **Files:** `caret/screenpipe.py`, `tests/test_screenpipe_api.py`

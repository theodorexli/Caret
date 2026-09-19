# Current Task: caret-screenpipe-403-history

**Complexity:** Level 1

## Fix

- **What broke:** Debug last-N / `python3 -m caret` history commands got HTTP 403 from Screenpipe `/search`.
- **Why:** Screenpipe 0.4.50 has no localhost bypass. Protected endpoints need `Authorization: Bearer` plus `X-Screenpipe-Client: api`. Caret `_api` only sent `SCREENPIPE_API_KEY` when that env var was set, so Caret.app Debug sent neither header.
- **What changed:** Resolve `SCREENPIPE_LOCAL_API_KEY`, then `SCREENPIPE_API_KEY`, then pinned `screenpipe auth token`. Always send both headers. Fail before the request if no token.
- **Files:** `caret/screenpipe.py`, `tests/test_screenpipe_api.py`

## QA

**Result:** PASS

- Last-N `_api` matches the brief: Bearer from `SCREENPIPE_LOCAL_API_KEY` / `SCREENPIPE_API_KEY` / pinned `screenpipe auth token`, plus `X-Screenpipe-Client: api`; fail closed if no token.
- Debug peek and CLI history share that path (`history-debug` → `debug_preview` → `last_n_*` → `_api`).
- Swift `/health` lease check is unchanged; a history 403 is not treated as a supervisor health failure.
- Advisories (non-blocking): `_api` also sends auth to Python `_require_health`; `_discover_token` is mocked rather than executed; dead `if not token` after `_discover_token()` already raises.

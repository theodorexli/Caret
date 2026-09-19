# Progress

Make Caret's last-N client (and Debug peek) authenticate to pinned Screenpipe 0.4.50 so history reads stop returning HTTP 403.

**Complexity:** Level 1

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Confirmed intent: fix 403 on Debug last-N / last-N history, then open a draft PR.
    - Classified Level 1 (bug fix, single component: last-N HTTP client).
* Decisions made
    - `/health` staying open while `/search` 403s is the observed split; do not treat this as a supervisor spawn bug unless the client cannot obtain auth without a launch change.
* Insights
    - Screenpipe docs require `Authorization: Bearer $SCREENPIPE_LOCAL_API_KEY` (and often `X-Screenpipe-Client`) on protected endpoints. Caret `_api` only sends `SCREENPIPE_API_KEY` when that env var is set.

## 2026-09-19 - BUILD - COMPLETE

* Work completed
    - Added last-N API auth: env keys, then pinned `screenpipe auth token`, plus `X-Screenpipe-Client: api`.
    - Tests in `tests/test_screenpipe_api.py`; `make check` green.
* Decisions made
    - Discover the token in the Python client so Caret.app Debug does not need a new lease field or Swift Screenpipe client.
    - Fail before calling `/search` when no token is available, instead of sending an unauthenticated request that 403s.
* Insights
    - `/health` staying open while `/search` 403s is expected on 0.4.50; the lease can exist and peek still fail.

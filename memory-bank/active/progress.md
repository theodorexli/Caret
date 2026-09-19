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

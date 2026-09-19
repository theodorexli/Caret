# Current Task: caret-debug-clip-self-from-windows

**Complexity:** Level 1

## Fix

- **What broke:** Debug last-N windows listed the Debug window as newest because opening it is a real Screenpipe hit.
- **Why:** `debug_preview` called `last_n_windows` with no skip, so `(Caret, Caret Debug)` won recency.
- **What changed:** Debug windows load with `skip_titles={"Caret Debug"}`. The walk keeps collecting until it has `n` other distinct windows. Minutes, clipboard, and inference last-N are unchanged.
- **Files:** `caret/screenpipe.py`, `tests/test_history_debug.py`

## QA

**Result:** PASS

- **KISS / DRY / YAGNI:** Skip-during-walk via optional `skip_titles` is the minimum change that keeps last-N filled after clipping Debug. `debug_preview` owns the Debug title; `history-windows` and other callers stay unfiltered.
- **Completeness:** Debug last-N windows omit `Caret Debug` and surface Safari then Cursor; minutes still include Debug. Inference/`history-windows` last-N is unchanged.
- **Regression / Integrity:** Optional kwarg is backward-compatible. Title constant matches `showDebugWindow`. No stubs, TODOs, or debug debris.
- **Documentation:** No project docs describe Debug last-N membership; nothing to update.

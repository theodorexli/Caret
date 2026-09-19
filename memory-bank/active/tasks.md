# Current Task: caret-debug-clip-self-from-windows

**Complexity:** Level 1

## Fix

- **What broke:** Debug last-N windows listed the Debug window as newest because opening it is a real Screenpipe hit.
- **Why:** `debug_preview` called `last_n_windows` with no skip, so `(Caret, Caret Debug)` won recency.
- **What changed:** Debug windows load with `skip_titles={"Caret Debug"}`. The walk keeps collecting until it has `n` other distinct windows. Minutes, clipboard, and inference last-N are unchanged.
- **Files:** `caret/screenpipe.py`, `tests/test_history_debug.py`

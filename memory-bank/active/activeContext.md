# Active Context

## Current Task: caret-pinned-screenpipe
**Phase:** BUILD - IN-PROGRESS (M1+M2 on feat/caret-pinned-screenpipe)

## What Was Done
- Branched `feat/caret-pinned-screenpipe`
- M1: `caret/screenpipe_pin.json` pins npm `screenpipe@0.4.50` and lease fields
- M2: `python3 -m caret history-minutes` / `history-windows` read a lease and hard-fail on miss
- Files: `/Users/tex/github/hackathon-2026-09-19/caret/screenpipe_pin.json`, `caret/screenpipe.py`, `caret/__main__.py`, `tests/test_screenpipe_pin.py`, `tests/test_screenpipe_history.py`

## Next Step
- Milestone 3: Caret.app launches and writes the live lease

## Decisions
- 2026-09-19: move fast and GSD, happy-path focus. No polish.
- Runtime pin is the published CLI 0.4.50, not the MIT git tree.

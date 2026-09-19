# Active Context

## Current Task: caret-screenpipe-detached-launch
**Phase:** BUILD - COMPLETE

## What Was Done
- Pin `launch` is `screenpipe record …`; obtain stays npx metadata
- Supervisor resolves the Developer ID Mach-O (not the node shim) and bootstraps `dev.caret.hackathon.screenpipe`
- Live: `/health` 0.4.50, `vision_reason=ok`, screenpipe PPID 1, ProgramArguments is `@screenpipe/cli-darwin-arm64/bin/screenpipe`
- Screen recording recovered after ~10s and captured frames. Accessibility still missing on that binary (grant `screenpipe`, not Caret)
- Files: `caret/screenpipe_pin.json`, `tests/test_screenpipe_pin.py`, `apps/mac/Sources/Caret/ScreenpipeSupervisor.swift`, `apps/mac/Tests/ScreenpipeSupervisorTests.swift`, `README.md`, `memory-bank/techContext.md`, `memory-bank/systemPatterns.md`, `memory-bank/productContext.md`

## Next Step
- QA

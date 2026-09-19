# Active Context

## Current Task: caret-screenpipe-launch-if-port-free
**Phase:** BUILD - COMPLETE

## What Was Done
- Port-gated spawn on `ScreenpipeSupervisor`: listen check, skip-spawn lease with `pid` 0, stale lease deleted at `run` start
- Merged `CaretProjectRoot` via `apps/mac/Sources/Caret/Info.plist` (`plutil` on Debug app = repo root)
- Docs: README + techContext
- SwiftPM excludes `Info.plist` so `make check` stays clean

## Files
- `/Users/tex/github/hackathon-2026-09-19/apps/mac/Sources/Caret/ScreenpipeSupervisor.swift`
- `/Users/tex/github/hackathon-2026-09-19/apps/mac/Tests/ScreenpipeSupervisorTests.swift`
- `/Users/tex/github/hackathon-2026-09-19/apps/mac/Sources/Caret/Info.plist`
- `/Users/tex/github/hackathon-2026-09-19/Caret.xcodeproj/project.pbxproj`
- `/Users/tex/github/hackathon-2026-09-19/apps/mac/Package.swift`
- `/Users/tex/github/hackathon-2026-09-19/README.md`
- `/Users/tex/github/hackathon-2026-09-19/memory-bank/techContext.md`

## Decisions
- Adopted listener lease uses sentinel `pid` 0
- Spawn decision is TCP connect to 127.0.0.1:port

## Deviations
- Excluded `Info.plist` from the SwiftPM Caret target (`make check` warned it was unhandled)

## Next Step
- QA

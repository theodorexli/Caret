---
task_id: caret-screenpipe-launch-if-port-free
complexity_level: 2
date: 2026-09-19
status: completed
---

# TASK ARCHIVE: caret-screenpipe-launch-if-port-free

## SUMMARY

Caret starts pinned Screenpipe on the pin port when that port is free, and does not start a second recorder when it is taken. `CaretProjectRoot` now ships in the built app via `INFOPLIST_FILE` merge so `ScreenpipeSupervisor.start` can run.

## REQUIREMENTS

- On every Caret start, launch the pin if the expected port has no listener.
- If the expected port is taken, do not spawn.
- Put `CaretProjectRoot` in the app bundle so start is not a no-op.
- Work on a feature branch.
- If Caret did not spawn the process, quit must not terminate the existing listener.

## IMPLEMENTATION

`ScreenpipeSupervisor` probes TCP `127.0.0.1` on the pin `--port`. `shouldSpawn` is the inverse. `run` deletes any stale lease, then either starts the pin child or leaves `process` nil. It writes a lease only after `/health` matches the pin version. An adopted match uses sentinel `pid` 0.

`apps/mac/Sources/Caret/Info.plist` sets `CaretProjectRoot` to `$(SRCROOT)`. The Xcode target sets `INFOPLIST_FILE` and keeps `GENERATE_INFOPLIST_FILE`. SwiftPM excludes that plist. README and techContext state the port-free spawn and health-gated lease.

Key files: `ScreenpipeSupervisor.swift`, `ScreenpipeSupervisorTests.swift`, `Info.plist`, `Caret.xcodeproj/project.pbxproj`, `apps/mac/Package.swift`.

## TESTING

- XCTest supervisor suite: port, listen, shouldSpawn, adopt lease `pid` 0, stale-lease replace (red then green).
- `xcodebuild test` CaretTests: 11 passed.
- `make check`: 24 Python tests, pin check, SwiftPM build.
- Built Debug app: `plutil` `CaretProjectRoot` = repo root.
- `/niko-qa` first pass FAIL (docs overstated adopt-and-lease). Second pass PASS (Cursor Grok 4.6 High Fast).

## LESSONS LEARNED

- `INFOPLIST_KEY_*` does not ship custom keys under `GENERATE_INFOPLIST_FILE`. Use `INFOPLIST_FILE` merge.
- Spawn gate is the port. Lease write is pin-version `/health`. Do not describe those as one step.
- Adopted-lease `pid` must be a sentinel (0), not the foreign process, so `stop()` does not claim it.

## PROCESS IMPROVEMENTS

- For this repo on 2026-09-19, QA and Preflight subagents must be only Cursor Grok 4.6 High Fast or Gemini 3.8 Flash. Gemini is not on the Task allow-list; use grok-fast.

## TECHNICAL IMPROVEMENTS

A generic pin supervisor (launch-if-free / lease-if-healthy / never-kill-foreign) can wait until a second pin needs the same shape.

## NEXT STEPS

None for this task. `/Applications/Caret.app` from an older install still needs a rebuild/`make install` to pick up `CaretProjectRoot`.

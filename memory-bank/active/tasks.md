# Task: caret-screenpipe-detached-launch

* Task ID: caret-screenpipe-detached-launch
* Complexity: Level 2
* Type: bug fix / launch-path change

Caret starts pinned Screenpipe 0.4.50 by execing the resolved Developer ID `screenpipe` Mach-O and bootstrapping a Caret-owned launchd job on `:3031`, not `/usr/bin/env npx` as a Caret child. Lease and adopt-if-port-taken stay. Live check: the recorder’s parent is launchd and permission-monitor can go true for that binary.

## Test Plan (TDD)

### Behaviors to Verify

- Pin launch names the CLI binary, not the npm runner: load `caret/screenpipe_pin.json` → `launch[0]` is `screenpipe`, `obtain` still fetches `screenpipe@0.4.50` via npx, flags still include `--disable-clipboard-capture false` and `--port 3031`, and the git tree is not launched
- Supervisor rejects a pin whose launch is empty or missing `--disable-clipboard-capture` (existing `loadPin`)
- Resolve + argv: given pin launch `["screenpipe", "record", …]` and a resolved binary URL → `programArguments` is `[binary.path, "record", …]` and contains neither `npx` nor `/usr/bin/env`
- Launchd plist: `launchdPlist(...)` → Label `dev.caret.hackathon.screenpipe`, `ProgramArguments` is that argv, WorkingDirectory is the project root
- Adopt unchanged: port already serving pin `/health` → `run` writes lease `pid` 0 and `stop` does not bootout a foreign listener
- Stale lease replace on adopt still works
- Spawn path (unit, no real launchd): when port is free, `run` writes the plist under `.local/` and records that Caret owns the job (so later `stop` will bootout). Do not call `launchctl` inside XCTest
- `stop` after a spawn-owned run clears the owned-job flag

### Test Infrastructure

- Framework: XCTest (`CaretTests`) and Python `unittest`
- Test location: `apps/mac/Tests/ScreenpipeSupervisorTests.swift`, `tests/test_screenpipe_pin.py`
- Conventions: supervisor tests use temp pin roots and local TCP/HTTP stubs; Python pin test reads the real pin file
- New test files: none

## Implementation Plan

### 1. Pin launch argv — executable

- Files: `caret/screenpipe_pin.json`, `tests/test_screenpipe_pin.py`

1. Stub tests: change `test_pin_names_published_cli_and_lease_fields` to empty, add `test_pin_launch_is_binary_not_npx` if the renamed case needs a distinct signature
2. Stub interface: none (JSON only)
3. Write tests and run red: `launch[0] == "screenpipe"`, `"npx" not in launch`, `obtain` still contains `npx` and `screenpipe@0.4.50`, record flags and port unchanged
4. Write code and run green: rewrite `launch` to `["screenpipe", "record", "--disable-telemetry", "--pii-backend", "local", "--audio-transcription-engine", "parakeet", "--disable-audio", "--disable-clipboard-capture", "false", "--port", "3031"]`

### 2. Supervisor resolve, plist, spawn/stop — executable

- Files: `apps/mac/Sources/Caret/ScreenpipeSupervisor.swift`, `apps/mac/Tests/ScreenpipeSupervisorTests.swift`

1. Stub tests: `testProgramArgumentsUseResolvedBinaryNotNpx`, `testLaunchdPlistUsesBinaryAndProjectRoot`, `testRunWritesPlistWhenPortFreeWithoutLaunchctl`, `testStopClearsOwnedJob` (plus keep adopt/stale/port cases; update fixtures that still say `npx` only where they exercise `port(from:)`)
2. Stub interface: `resolveBinary(obtain:name:) throws -> URL`, `programArguments(binary:launch:) -> [String]`, `launchdLabel`, `launchdPlistURL(projectRoot:)`, `launchdPlistXML(...)`, `ownsJob` state; `run`/`stop` signatures unchanged
3. Write tests and run red: argv[0] is the binary path; plist Label and ProgramArguments; `run` on a free port writes `.local/dev.caret.hackathon.screenpipe.plist` and sets owned job (inject or skip `launchctl` via a test hook / `bootstrap` no-op when `CARET_SCREENPIPE_SKIP_LAUNCHCTL` or a package-visible `bootstrapHandler`); adopt path still pid 0
4. Write code and run green: resolve `screenpipe` with `npx -y --package screenpipe@0.4.50` + `which` (or equivalent) after obtain; write plist to `projectRoot/.local/`; `launchctl bootout` then `bootstrap gui/$UID` that plist; `stop` bootouts only if we own the job; never `Process` + `/usr/bin/env`; lease pid is the screenpipe pid from `launchctl` print or `pgrep` of that binary on the pin port, else 1 if owned and healthy

### 3. Docs — prose/policy

- Files: `memory-bank/techContext.md`, `README.md`
- No tests: prose/policy artifact

1. Say Caret bootstraps a launchd job that execs the pinned `screenpipe` binary on `:3031` when the port is free
2. Do not say Caret spawns `npx` as a child

### 4. Live perm check — executable (build verification, not a change-detector)

- Files: none committed; run on this Mac during Build

1. After `make app` / Debug open: confirm listener on `:3031`, `/health` version `0.4.50`, lease written
2. Confirm `screenpipe` parent is `launchd` (not Caret, not `env`, not `npx`)
3. Confirm `~/.screenpipe/screenpipe.*.log` permission-monitor is not stuck `screen=false accessibility=false` after grant+relaunch of the job
4. If launchd-from-Caret is still TCC-responsible as Caret: stop and switch the spawn to a login-item-free `launchctl submit`/`bootstrap` of a plist whose Mach-O is only the Developer ID binary (already the plan). If still false, report blocked — do not ship another Caret-child `Process`

## Technology Validation

No new technology - validation not required. `launchctl` and the pinned npm CLI are already on this machine. Resolve-binary will be proven in Build by running the same `npx --package … which` the supervisor will call.

## Dependencies

- Existing pin `screenpipe@0.4.50` / Developer ID binary
- User-domain `launchctl` (`gui/$UID`)
- Existing lease schema and last-N client (unchanged)

## Challenges & Mitigations

- `npx which` path differs per npm cache: resolve at runtime; do not hardcode `~/.npm/_npx/…`
- XCTest must not bootstrap a real recorder: unit-test plist/argv; gate `launchctl` behind a replaceable hook
- Caret-bootstrapped launchd might still count as Caret for TCC: live check in Build; parent must be launchd; if preflight stays false, do not merge
- `stop()` must not kill a foreign `:3031`: bootout only when `ownsJob`
- Linux CI never runs the supervisor: Python pin test is the Linux contract

## Pre-Mortem

- Launchd job still attributed to ad-hoc Caret, sheets continue: already covered by Challenge (live check / no Caret-child fallback)
- Plan tests only the plist and never proves resolve works: add the Build live check (step 4); fail Build if `:3031` never becomes healthy
- Pin test becomes a change-detector on JSON wording: assert user-facing contract (published CLI binary + flags + no git tree), not a full-string snapshot

## Status

- [x] Initialization complete
- [x] Test planning complete (TDD)
- [x] Implementation plan complete
- [x] Technology validation complete
- [x] Pre-Mortem complete
- [ ] Preflight
- [ ] Build
- [ ] QA

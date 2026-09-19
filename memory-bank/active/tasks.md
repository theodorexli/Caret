# Task: caret-screenpipe-launch-if-port-free

* Task ID: caret-screenpipe-launch-if-port-free
* Complexity: Level 2
* Type: simple enhancement

On Caret start, launch pinned Screenpipe when the pin's expected port has no listener. If that port is already taken, do not spawn. Put `CaretProjectRoot` in the built app Info.plist so `start` can run.

## Test Plan (TDD)

### Behaviors to Verify

- Port from pin: launch args contain `--port 3031` → `port(from:)` is `3031`
- Port free: `isListening` on a port with no local listener → `false`; `shouldSpawn` is `true`
- Port taken: bind a local TCP listener, then `isListening` → `true`; `shouldSpawn` is `false`
- Adopted process is not owned: after a skip-spawn path, `process` stays `nil` so `stop()` does not terminate the existing listener
- Existing: `loadPin` still requires `--disable-clipboard-capture`; `endpoint(from:)` stays `http://127.0.0.1:3031`

### Test Infrastructure

- Framework: XCTest (`CaretTests` in `Caret.xcodeproj`)
- Test location: `apps/mac/Tests/`
- Conventions: `final class …Tests: XCTestCase`, `test…` methods, `XCTAssertEqual` / `XCTAssertTrue` / `XCTAssertNil`
- New test files: none

`make check` runs `swift build --package-path apps/mac` and does not run XCTest. Run new tests with `xcodebuild test` on the CaretTests target. Do not add a parallel SwiftPM test target.

## Implementation Plan

### 1. Port-gated spawn — executable

- Files: `apps/mac/Tests/ScreenpipeSupervisorTests.swift`, `apps/mac/Sources/Caret/ScreenpipeSupervisor.swift`

1. Stub tests: in `ScreenpipeSupervisorTests`, add empty `testPortFromLaunchArgs`, `testIsListeningFalseWhenPortFree`, `testIsListeningTrueWhenPortBound`, `testShouldSpawnOnlyWhenPortFree`, `testStopDoesNotOwnProcessWhenSpawnSkipped`
2. Stub interface: add `port(from: [String]) -> Int`, `isListening(port: Int) -> Bool`, `shouldSpawn(port: Int) -> Bool` on `ScreenpipeSupervisor` (comments in the existing file style)
3. Write tests and run red: `xcodebuild test -project Caret.xcodeproj -scheme Caret -destination 'platform=macOS' -only-testing:CaretTests/ScreenpipeSupervisorTests`
4. Write code and run green: `run` calls `shouldSpawn`; if `false`, do not `Process.run`, leave `process` nil, still `waitForHealth` and write the lease when `/health` matches; if `true`, keep today's spawn path. `stop()` stays `process?.terminate()`

### 2. Bundle project root — prose/policy

- Files: `apps/mac/Sources/Caret/Info.plist`, `Caret.xcodeproj/project.pbxproj`
- No tests: prose/policy artifact (asserting generated Info.plist bytes is a change-detector)

1. Add a small `Info.plist` that sets `CaretProjectRoot` to `$(SRCROOT)`
2. Set `INFOPLIST_FILE` on the Caret app target and keep `GENERATE_INFOPLIST_FILE = YES` so Xcode merges the custom key
3. After the next local `xcodebuild`, confirm with `plutil -extract CaretProjectRoot raw` on the built app

### 3. Starter docs — prose/policy

- Files: `README.md`, `memory-bank/techContext.md`
- No tests: prose/policy artifact

1. State that Caret starts the pin on the expected port when that port is free, and does not start a second recorder when it is taken

## Technology Validation

No new technology - validation not required

## Dependencies

- Existing pin `caret/screenpipe_pin.json` (`--port 3031`)
- Existing `CaretApp` call to `ScreenpipeSupervisor.start` on launch
- Full Xcode (`xcode-select` already points at `/Applications/Xcode.app`)

## Challenges & Mitigations

- `INFOPLIST_KEY_CaretProjectRoot` is ignored today: merge via `INFOPLIST_FILE`, then `plutil` on the built bundle
- A non-Screenpipe listener on `3031`: do not spawn; `waitForHealth` times out; write no lease (`try?` in `start` already swallows that)
- `stop()` must not kill an adopted listener: only terminate `process` when this launch spawned it
- XCTest is not in `make check`: run `xcodebuild test` for supervisor tests during Build

## Pre-Mortem

- Built app still has no `CaretProjectRoot` after the plist step, so start stays a no-op: already covered by Challenge 1 (`plutil` check)
- Spawn gate uses `/health` instead of the port, so a dead listener blocks launch forever: keep the port as the only spawn decision; health stays a lease write gate
- Adopted listener is killed on Caret quit: already covered by Challenge 3

## Status

- [x] Initialization complete
- [x] Test planning complete (TDD)
- [x] Implementation plan complete
- [x] Technology validation complete
- [x] Pre-Mortem complete
- [ ] Preflight
- [ ] Build
- [ ] QA

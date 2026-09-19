---
task_id: caret-screenpipe-detached-launch
complexity_level: 2
date: 2026-09-19
status: completed
---

# TASK ARCHIVE: caret-screenpipe-detached-launch

## SUMMARY

Caret-spawned Screenpipe was a `/usr/bin/env npx` child of ad-hoc Caret, so TCC stayed denied and VisionManager re-prompted every 5s even with Settings ON. Caret now resolves the pinned Developer ID Mach-O and bootstraps launchd job `dev.caret.hackathon.screenpipe` on `:3031`. Live start: `/health` 0.4.50, parent launchd, Screen Recording recovered and captured frames.

## REQUIREMENTS

- Exec the resolved `screenpipe` Mach-O, not `npx` as the recorder.
- Start it outside Caret’s process tree (Caret-owned launchd on `:3031`).
- Lease only after `/health` matches the pin; adopt `pid` 0 if the port is taken.
- Quit must not kill a foreign listener.
- Feature branch. No Caret code-signing. Pin stays `screenpipe@0.4.50`.

## IMPLEMENTATION

`caret/screenpipe_pin.json` `launch` is `["screenpipe", "record", …]`. `obtain` stays npx metadata. `ScreenpipeSupervisor` runs `npx --package screenpipe@0.4.50 which screenpipe`, then walks to `@screenpipe/cli-darwin-arm64/bin/screenpipe` (npm `which` is a node shim). It writes `.local/dev.caret.hackathon.screenpipe.plist` and `launchctl bootstrap gui/$UID`. `ownsJob` is set at bootstrap; `stop()` bootouts only then. Adopt path unchanged.

## TESTING

- Python pin + history tests; CaretTests including argv, plist, spawn-without-launchctl, stop, adopt.
- `swift build --package-path apps/mac`.
- Live Caret Debug: healthy `:3031`, lease pid, `vision_reason=ok`, frames.
- `/niko-qa` PASS.

## LESSONS LEARNED

- npm `bin` for this pin is `lib/cli.js`. TCC and launchd must exec the optional-dependency Mach-O.
- Caret-initiated `launchctl bootstrap` did detach (PPID 1). Accessibility remains a grant on that binary, not a Caret-child bug.

## PROCESS IMPROVEMENTS

- A live parent/`/health` check caught the shim issue XCTest could not.

## TECHNICAL IMPROVEMENTS

None beyond the launch path. Signing Caret (stable Team ID) is still a separate identity fix.

## NEXT STEPS

Grant Accessibility to the `screenpipe` Mach-O, then quit and reopen Caret. `/niko-archive` follow-up is this document.

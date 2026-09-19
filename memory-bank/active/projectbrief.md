# Project Brief

## User Story

As a Caret user on this Mac, I want Caret to start pinned Screenpipe so that the recorder process is trusted for Screen Recording and Accessibility, comes up on the pin port, and stops re-prompting every few seconds.

## Use-Case(s)

### Use-Case 1

I launch Caret.app. If port 3031 is free, Caret starts the pinned Screenpipe 0.4.50 binary (not `npx`), outside Caret’s process tree. After `/health` matches the pin, Caret writes `.local/screenpipe-lease.json`. Last-N windows, minutes, and clipboard work. The native permission sheet does not repeat on a 5s VisionManager retry because the recorder is no longer a Caret child.

### Use-Case 2

Port 3031 is already taken by a matching pin. Caret does not start a second recorder and writes a lease with sentinel `pid` 0 after `/health` matches.

## Requirements

1. Exec the resolved `screenpipe` Mach-O for the pin, not `/usr/bin/env npx`.
2. Start that recorder outside Caret’s process tree (Caret-owned launchd job or helper on `:3031`).
3. Write the existing lease only after `/health` matches the pin version.
4. If the pin port is taken, do not spawn; adopted match uses lease `pid` 0.
5. If Caret did not spawn the job, quit must not terminate a foreign listener.
6. Work on a feature branch.
7. Screenpipe must start successfully and be able to receive the TCC grants it needs.

## Constraints

1. Do not sign Caret (option 2 is out of scope).
2. Do not attach to leftover launchd `:3030` or a random Screenpipe.
3. Do not vendor `packages/screenpipe` or copy `ee/`.
4. Pin stays published `screenpipe@0.4.50`.
5. TCC stays on the launched Screenpipe binary, not inherited from Caret.
6. Fast/aggressive hackathon slice; make the launch actually get perms.

## Acceptance Criteria

1. Launch argv/path names the resolved `screenpipe` binary, not `npx`.
2. The recorder is not a direct child of `Caret` (`/usr/bin/env` + `npx` is gone).
3. After a Caret start with a free pin port, `/health` on `:3031` reports pin version `0.4.50`.
4. Lease is written only after that health match.
5. Last-N CLI still hard-fails on missing lease, wrong version, or empty history.
6. A Caret-spawned recorder can be granted Accessibility and Screen Recording as `screenpipe` (Developer ID), and Caret does not sit in that process’s TCC responsibility chain.

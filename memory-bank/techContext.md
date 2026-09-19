# Tech Context

Native Mac UI in Swift, local workflow core in Python 3.11+ with stdlib only, run state in SQLite. No third-party Python dependencies, no web frontend, no container. Upstream integrations are optional Git submodules and are not on the default run path.

## Environment Setup

- Python 3.11+ for the core. The local package has an empty dependency list in `pyproject.toml`.
- macOS 14+ and Swift 5.9+ (Xcode or Command Line Tools) for the popup. Linux can run the Python tests and source-pin check only.
- Clone without recursive submodules. Fetch a pin with `git submodule update --init --depth 1 packages/<name>` when you need that upstream. `make sources` fetches KeyType and Jev Ultrafast only.
- SQLite files and the built app bundle stay out of Git (`.local/`, `dist/`). Do not commit credentials, personal threads, or screenshots.

## Build Tools

- `Makefile` is the command surface: `demo`, `app`, `test`, `check`, `sources`.
- Mac executable: SwiftPM package at `apps/mac` (`Package.swift`). `scripts/run_mac.py` builds it and writes a development `dist/Caret.app` whose Info.plist points at this checkout and the current Python.
- Python is invoked as `python3 -m caret`. CLI operations are listed by `python3 -m caret --help`.

## Testing Process

- Python: `unittest` discovery under `tests/` (`make test`). Checks should cover scheduling arithmetic, failed-source handling, hold transitions, and duplicate external effects — see `CONTRIBUTING.md`.
- Pin lockstep: `scripts/check_sources.py` requires `sources.json`, `.gitmodules`, and staged submodule SHAs to match.
- Full Mac gate: `make check` (tests + pin check + `swift build`). CI splits this: Linux runs tests, the pin check, and a fixture preview; macOS builds the Swift package (`.github/workflows/ci.yml`).
- Mac CI SDK: the Mac job runs on `macos-15`, which **defaults to Xcode 16.4** (macOS 15 SDK). The workflow selects Xcode 26 so Tahoe APIs compile. `#available(macOS 26.0, *)` is a **runtime** check — the compiler still type-checks both branches against the current SDK. New Apple APIs need a compile-time gate (`#if compiler(>=6.2)` or equivalent) **and** an SDK that has the symbol. Do not add macOS 26+ SwiftUI/AppKit calls without that, and do not remove the Xcode 26 select from the Mac job.
- GitHub Actions repository secret `SUPABASE_HACKATHON_TOKEN` is available for CI jobs that need Supabase (`gh secret list`). Workflows that need it should use `${{ secrets.SUPABASE_HACKATHON_TOKEN }}`. Do not write the value into the repo, plaintext workflow files, or memory-bank.
- No current check uses live Gmail, calendar, or browser accounts, or sends messages. A green run does not prove those integrations.

## Design System

There is no design-token file, Storybook, or brand guide. The popup is a small SwiftUI panel (system fonts and SF Symbols) and is still a sample workspace, not a finished visual language.

## Working in this repo

Keep product code outside `packages/` unless the team is intentionally maintaining an upstream fork. License notes for each pin are in `THIRD_PARTY.md`; Screenpipe is pinned before a license change and its `ee/` tree must not be copied. Integration contracts for work that is not yet wired are in `docs/integrations.md`. Repo-shared agent memory is `.summem/summem`; see the Project Memory block in `AGENTS.md`.

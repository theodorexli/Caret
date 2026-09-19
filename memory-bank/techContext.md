# Tech Context

Native Mac UI in Swift, local workflow core in Python 3.11+ with stdlib only, run state in SQLite. The default run has no third-party Python dependencies, web frontend or container. Five selected upstreams are pinned; Caret.app launches published Screenpipe 0.4.50. See [docs/input-pipeline.md](../docs/input-pipeline.md).

## Environment Setup

- Python 3.11+ for the core. The local package has an empty dependency list in `pyproject.toml`.
- macOS 14+ with full Xcode for `make app`. SwiftPM checks can use Command Line Tools. Linux can run the Python tests and source-pin check only.
- Clone without recursive submodules. `make sources` fetches KeyType, GhostType and Computer Use Jev. Their owners fetch Skyvern and Screenpipe with `git submodule update --init --depth 1 packages/<name>`.
- The pinned Computer Use Jev coordinator requires Go 1.26 and builds a Swift worker. This is an adapter dependency, not a requirement for the current Python demo.
- SQLite files and the built app bundle stay out of Git (`.local/`, `dist/`). Do not commit credentials, personal threads, or screenshots.

## Build Tools

- `Makefile` is the command surface: `demo`, `app`, `test`, `check`, `sources`.
- Mac executable: `Caret.xcodeproj`, with a parallel SwiftPM package for build checks. `scripts/run_mac.py` now uses Xcode and opens `.local/build/Debug/Caret.app`. The app launches the Screenpipe pin and writes `.local/screenpipe-lease.json`; it still does not invoke the Python planner.
- Python is invoked as `python3 -m caret`. History commands are `history-windows`, `history-minutes`, and `history-clipboard` (newest-first). Other operations are listed by `python3 -m caret --help`.

## Testing Process

- Python: `unittest` discovery under `tests/` (`make test`). Checks should cover scheduling arithmetic, failed-source handling, hold transitions, and duplicate external effects — see `CONTRIBUTING.md`.
- Pin lockstep: `scripts/check_sources.py` requires `sources.json`, `.gitmodules`, and staged submodule SHAs to match.
- Full Mac gate: `make check` (tests + pin check + `swift build`). CI splits this: Linux runs tests, the pin check, and a fixture preview; macOS builds the Swift package (`.github/workflows/ci.yml`).
- Mac CI SDK: the Mac job runs on `macos-26` because Tahoe APIs such as `glassEffect` need the Xcode 26 SDK. `macos-15` defaults to Xcode 16.4 and will not compile those symbols. `#available(macOS 26.0, *)` is a **runtime** check — the compiler still type-checks both branches against the current SDK. New Apple APIs need a compile-time gate (`#if compiler(>=6.2)` or equivalent) **and** an SDK that has the symbol. Do not move the Mac job back to default Xcode 16.
- GitHub Actions repository secret `SUPABASE_HACKATHON_TOKEN` is available for CI jobs that need Supabase (`gh secret list`). Workflows that need it should use `${{ secrets.SUPABASE_HACKATHON_TOKEN }}`. Do not write the value into the repo, plaintext workflow files, or memory-bank.
- Chat completions use Vercel AI Gateway (`caret/completions.py`, default model `google/gemini-2.5-flash`). Set `VERCEL_API_GATEWAY_KEY` locally or `${{ secrets.VERCEL_API_GATEWAY_KEY }}` in CI. Optional alias: `AI_GATEWAY_API_KEY`. CLI smoke: `python3 -m caret complete --prompt "Hello"`.
- No current check uses live Gmail, calendar, or browser accounts, or sends messages. A green run does not prove those integrations.

## Design System

The input UI uses SwiftUI/AppKit panels, system fonts and SF Symbols. Teddy owns the UX, hoverable and permission onboarding; do not replace his work while connecting routing.

## Working in this repo

Keep product code outside `packages/` unless the team is intentionally maintaining an upstream fork. License notes for each pin are in `THIRD_PARTY.md`; Screenpipe is pinned before a license change and its `ee/` tree must not be copied. Integration contracts for work that is not yet wired are in `docs/integrations.md`. Repo-shared agent memory is `.summem/summem`; see the Project Memory block in `AGENTS.md`.

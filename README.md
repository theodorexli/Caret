# Caret

A native Mac assistant with two interaction modes: inline completion accepted with Tab, and a nearby action hoverable. Jev chooses whether to abstain, offer a small text edit or propose an action; a second query selects the workflow or computer task. A fast Groq-hosted model generates inline text. This is the target behavior, with integration still in progress.

## Start here

The starter needs Python 3.11+ and macOS 14+. `make app` requires full Xcode; SwiftPM checks can use the Command Line Tools. The local core has no third-party Python dependencies. The selected native executor uses Go 1.26 and a Swift worker when integrated; upstream services have separate setup requirements.

```sh
git clone https://github.com/theodorexli/hackathon-2026-09-19.git
cd hackathon-2026-09-19
make test
make demo
make install    # Release Caret.app → /Applications
# make dmg      # also writes dist/Caret.dmg
```

Caret.app starts pinned Screenpipe 0.4.50 on port 3031 (clipboard history on) when that port is free. It resolves the published `screenpipe` binary and bootstraps a Caret-owned launchd job (`dev.caret.hackathon.screenpipe`) so the recorder is not a Caret child. If the port is already taken, it does not start a second recorder. It writes `.local/screenpipe-lease.json` only after `/health` reports the pin version — for a job Caret started, or for an existing matching listener (lease `pid` 0). A listener that is not that pin gets no lease. The built app Info.plist carries `CaretProjectRoot` so the supervisor, skills, memories, and notes can find this repository. `python3 -m caret` can then ask for last-N windows, minutes, or clipboard, newest first. The Caret menu Debug item shows a short last-2 windows / minutes / clipboard preview of what Caret currently sees.

The current app asks for Accessibility, then shows a blue asterisk beside supported fields and selections. Command–Option or the button opens the scrollable action list; up to three pinned actions use Command–Option–1/2/3. These actions currently log and close the panel. Inline completion, Tab acceptance, Command–1/2/3 and model routing are planned, not wired. The [input pipeline contract](docs/input-pipeline.md) defines the next implementation and the owners.

**This is a contributor starter, not the finished ninety-second demo.** `make demo` runs the Python preview and local SQLite state on explicitly synthetic data. Teddy's current action UI is not connected to that CLI. Gmail, Google Calendar, Jev inference and computer execution are not connected. Accessibility currently locates fields and selections; the app cannot send email, create external events or purchase anything.

## Where to work

| Component | Location | First integration |
| --- | --- | --- |
| Mac input UI | `Caret.xcodeproj`, `apps/mac` | Teddy: inline text, action hoverable, scoped shortcuts and permission polish |
| Workflows | `caret/workflows.json`, `caret/planner.py` | Connect Jev routing and source-backed parameter extraction |
| History and run state | `packages/screenpipe`, `caret/store.py` | Context owner: Screenpipe retrieval; workflow owner: external effect IDs |
| Computer use | `packages/computer-use-jev`, `packages/skyvern` | Native AX execution and browser execution, respectively; stop before payment |
| Gmail and calendar | `docs/integrations.md` | Implement the documented source and action contracts |

The Python CLI exposes JSON preview/hold/confirm operations for the UI bridge to reconnect. There is no server, container or web frontend in the default run. SQLite data stays in ignored `.local/` files. `python3 -m caret workflows` lists the seeds. Sam owns the choice and definitions of the two demo workflows.

## Public repositories

Five selected repositories are pinned under `packages/`: KeyType and GhostType for one combined text interaction, Computer Use Jev for native actions, Skyvern for browser control and Screenpipe for history. Pins and roles live in [sources.json](sources.json). Alternative engines were removed so agents have one clear implementation path.

Fetch only what you need:

```sh
make sources   # KeyType, GhostType and the selected native Jev pipeline
git submodule update --init --depth 1 packages/skyvern
git submodule update --init --depth 1 packages/screenpipe
```

`git submodule update --init --depth 1` fetches all top-level sources. Avoid `--recursive` unless you need an upstream's dependencies. Nothing automatically installs or runs upstream code. Read each upstream's own setup instructions before running it. Make changes to Caret outside submodules unless your team intentionally maintains an upstream fork.

Screenpipe retains its historical MIT pin, whose grant excludes `ee/`; coordinate any change with its owner. Skyvern has AGPL terms. The root license applies only to original Caret files. See [THIRD_PARTY.md](THIRD_PARTY.md).

## Hackathon target

Start with the Austin–Dallas corridor. Before the live demo, connect one reliable travel source or check in a sourced, dated cached timetable. The current synthetic buffer fixture is **not** a timetable and must not be used as factual travel evidence.

Open a real thread, invoke Caret, and inspect its filled request. Enter produces up to three supported options and evidence. Sending the approved draft creates tentative calendar holds. A labeled staged reply selects one option; one confirmation keeps it and removes only this workflow's other holds. The booking workflow uses the browser and stops at the payment page.

Drop options when source calls fail. Never ask a model to invent missing availability, travel times or fares. Do not add multi-party polling, hotel search or ticket purchases to this build. The three seeds are Book a flight, Book a calendar link and Revise; only meeting previews currently execute.

## Checks

`make check` runs the scheduling/store tests, verifies submodule pins and builds the Mac executable. CI runs the Python suite and manifest check on Linux, and the Swift build on macOS. No check uses live accounts or sends messages.

Read [CONTRIBUTING.md](CONTRIBUTING.md) before changing shared contracts.

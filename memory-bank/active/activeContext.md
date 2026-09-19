# Active Context

## Current Task: caret-report-github-issue
**Phase:** QA

## What Was Done
- Built replan 6 end to end. Operator overrode the leftover replan-5 `FAIL (fixable)` gate.
- Units 1–6 implemented. QA failed two cancel-path holes; those are now fixed.
- `make check` after the fix: 329 Python (4 skipped), 98 CaretTests, 72 CaretCoreTests, sources pin, Xcode Debug build.

## Files created or modified
- New: `caret/live_workflows/github.py`, `caret/live_workflows/report_issue.py`, `tests/test_report_issue.py`, `tests/test_report_issue_workflow.py`, `caret/skills/report-github-issue/default.json`, `caret/notes/skills/report-github-issue.md`
- Core: `caret/router.py` (`install_offer`, stale `complete_failure`), `caret/engine.py` (`prepare_named`), `caret/bridge.py` (`workflow.prepare`, built-in register), `caret/workflows.json`, `caret/live_workflows/{actions,__init__}.py`
- Mac: `FocusedTargetCapture` (`HostContext`, `explicitActionFrame`), `CoreBridgeClient.prepareWorkflow`, `CoreBridgeProvider` (prepare, offered-only Cmd-1, no-field accept), `ExplicitInvokeActions`, `CaretApp` (host freeze, panel stay, stand-down, resume)
- Docs: `docs/bridge-protocol.md`, `docs/live-workflow-adapters.md`, `docs/input-pipeline.md`
- Test-only: `apps/mac/Tests/BridgeContractTests.swift` discovery assertion now follows the same candidate order as `CoreLaunchSettings`

## Decisions Made
- `PublicGitHub` via stdlib `urllib` to `api.github.com`, User-Agent, no Authorization on prepare.
- Empty/404 search → not-OSS. Timeout/403/bad JSON → `SearchFailed`.
- First-match issue body GET so recommend can see if the complaint adds information.
- `complete_failure` respects `is_stale`. Cmd-1 is `.offered` only. Escape bumps a generation Int.
- Clipboard `capturedAt` encodes `Date()` when nil so Python `from_dict` accepts an available clipboard; source records stay `capturedAt: nil`.

## Deviations
- Operator skipped a sixth preflight.
- Pre-existing Python-discovery XCTest expected `/usr/bin/python3` while discovery prefers Homebrew 3.14; assertion now matches the candidate list. Not a product change.

## Next Step
- Re-run QA on the cancel-path fixes.

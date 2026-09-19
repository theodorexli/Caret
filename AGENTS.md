# Project Memory

Shared memory for this repository is managed through SumMem.

## At Session Start: Activating SumMem (mandatory)

Run `python3 .summem/summem wake` from the repository root. If you can see a prior project-root SumMem wake in this conversation's history, do not run it again.

## While Working: Register Memories

When something matches the write rule below, record it with SumMem's `note`.

One short line another contributor needs to work on this repository: gotchas, norms, failed approaches, lore and tribal knowledge, etc. Not merely "news" - e.g. that a PR opened, checks passed, or a task completed. Personal, machine-local, and user preference facts stay out. Do not record secrets, live credentials, or personal threads. Skip if nothing qualifies or it is already remembered.

# Agent context

Tracked agent-facing project knowledge lives under `memory-bank/`. Prefer those files over inventing project facts.

## Persistent files

- `memory-bank/productContext.md` — business context: users, use cases, success criteria, constraints
- `memory-bank/systemPatterns.md` — architecture and naming patterns in use
- `memory-bank/techContext.md` — stack, tools, and how to work in this repo

## Archives

Completed work is summarized under `memory-bank/archive/<kind>/YYYYMMDD-<task-id>.md`.

## Active work

`memory-bank/active/` holds the current-task execution trace. If those files exist, an in-flight task may be underway — consult them before starting work that could collide.

## When to load

When the task needs project, architecture, or stack context, read the relevant persistent file(s). Do not load every memory-bank file on every chat.

# Caret contributor instructions

- Start with README.md and docs/input-pipeline.md for the selected stack, two-stage Jev routing, keyboard contract and ownership. Read docs/integrations.md for workflow effects, and `memory-bank/` for current implementation status.
- Keep exactly the five selected upstreams: KeyType, GhostType, Computer Use Jev, Skyvern and Screenpipe. Skyvern owns browser control; Computer Use Jev owns native actions; Screenpipe is the sole history engine.
- Merge KeyType/GhostType components into one Caret app with one input/acceptance owner. GhostType mode means Teddy's action hoverable, not a second running autocomplete app.
- One shared Jev judge chooses ABSTAIN/INLINE/ACTION at most once per two seconds of changed active context, then selects a workflow/task only for ACTION. A fast Groq-hosted model generates inline text. Discard stale results; never execute from ambient classification alone.
- Tab accepts only the current visible offer that owns it; Command–1/2/3 choose visible actions. Otherwise preserve the host app's shortcuts. Revalidate the original target before applying any edit.
- Teddy owns UI and Accessibility onboarding; the context teammate owns Screenpipe; Sam owns the two demo workflow definitions. Coordinate through docs/input-pipeline.md before editing another owner's implementation.
- Paul owns `jev-scheduler/`, proposed in PR #1. Adapt its actual interface when pushed; do not duplicate his implementation or confuse him with the author of the native Computer Use Jev upstream.
- The supported hackathon scope ends before payment. Do not add purchases, hotel search or multi-party polling.
- Fixture content is synthetic and cannot be sent. Drop failed-source options; never invent facts in a draft.
- Keep external credentials and personal data out of Git. Source integrations need explicit configuration.
- Treat packages/ as pinned upstream code. Preserve authorship and licenses; do not bulk rename upstream files.
- Run make check on Mac, or make test plus python3 scripts/check_sources.py for core-only Linux work.
- Preserve other contributors' changes. Use branches and PRs after the initial repository setup.

# Progress

Make Caret launch a pinned Screenpipe version, expose last-N history through a Caret facade, and hard-fail any inference run that lacks a live matching gatherer or usable records.

**Complexity:** Level 4

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Approved intent: Caret launches a particular Screenpipe version it can depend on
    - Classified Level 4 (integration across app launch, version pin, Python facade, TCC/license)
* Decisions made
    - Prior creative stands except miss path: sidecar/engine distribution is still not “vendor current Screenpipe”; this task is launch-and-depend, and a miss is a hard fail
* Insights
    - “Launch a version” is a process-identity problem, not only an HTTP client

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Wrote `memory-bank/active/milestones.md` with four serial-safe milestones
* Decisions made
    - Advisory estimates: pin artifact L2 (license/version contract); Python last-N client L2 (one subsystem, hard-fail + pin check); Caret launch/supervise L3 (process + TCC honesty); docs L1
    - Pin file is owned only by milestone 1; later milestones consume it
    - M2 and M3 may proceed in parallel after M1; M4 follows both
* Insights
    - Launch-and-depend does not lift the ban on vendoring current Screenpipe or claiming Caret’s Accessibility covers their binary

## 2026-09-19 - DESIGN OVERRIDE

* Decisions made
    - Operator: Caret launches and supervises the pinned Screenpipe. The “do not spawn” sidecar decision is revoked.
    - TCC still belongs to the launched binary. Engine still must not be vendored.
    - Python client should use a launcher lease, not discover a random port-3030 process.

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Validated the Level 4 milestone list against the project brief, active architecture decision, and repository integration constraints
    - Recorded `FAIL (blocking)` in `.preflight-status`
* Decisions made
    - None; the operator must resolve whether Caret launches Screenpipe or requires a user-managed sidecar before the plan can proceed
* Insights
    - The active architecture decision selected a sidecar and forbade spawning Screenpipe, while milestone 3 required Caret.app to launch and supervise it. Operator later overrode: Caret launches and supervises.

## 2026-09-19 - PREFLIGHT - LEFT FOR REPLAN

* Work completed
    - Operator revoked “do not spawn”; creative now matches launch-and-supervise
* Decisions made
    - Re-run L4 plan so the milestone list and invariants include the launcher lease

## 2026-09-19 - PLAN - COMPLETE

* Work completed
    - Replanned milestones after launch-and-supervise override
    - Added lease invariant: M1 defines fields, M3 writes the live lease, M2 never rediscovers port 3030
* Decisions made
    - Advisory estimates unchanged: pin L2, Python last-N L2, launch/supervise L3, docs L1
    - M2 and M3 still parallel after M1; M2 may use a fixture lease until M3 writes a live one
* Insights
    - The previous preflight block was a stale creative, not a bad milestone list

## 2026-09-19 - WORKING MODE

* Decisions made
    - Operator, this repo, today: move fast and GSD, happy-path focus. Hackathon — we ship, we do not polish. Preflight should treat extra contracts, schemas, and future-proofing as advisory at most, never blocking.

## 2026-09-19 - PREFLIGHT - COMPLETE

* Work completed
    - Validated the replanned milestone list against the Level 4 preflight checks
    - Recorded `PASS WITH ADVISORY` in `.preflight-status`
* Decisions made
    - All checks passed: prerequisites, checklist shape, coverage, scope, order (DAG agrees with checklist), invariants with handoff rules for pin and lease, per-milestone Done/Risks
* Insights
    - Advisory: a versioned, machine-checked lease contract in M1 would make the M2||M3 parallelism enforceable instead of prose-governed

## 2026-09-19 - BUILD - IN-PROGRESS

* Work completed
    - Created branch `feat/caret-pinned-screenpipe`
    - Shipped pin + last-N CLI (milestones 1 and 2)
    - 11 unittest tests passing
* Decisions made
    - Pin is `npx screenpipe@0.4.50`, not `packages/screenpipe`
    - Lease path defaults to `.local/screenpipe-lease.json`; token from `SCREENPIPE_API_KEY`
* Insights
    - L4 has no single build phase; this build is the first two milestones on a feature branch

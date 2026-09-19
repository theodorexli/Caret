---
name: architecture-docs
description: How to write project architecture documentation as portable principles — genre framing, inclusion bars, orientation diagrams, invariants, and change-surface routing. Use when writing or improving architecture docs, systems atlases, or design-surface explanations (not product how-tos).
---

# Architecture Documentation

Write [Diátaxis](https://diataxis.fr/) **explanation** for the system's design surface: a systems atlas a changer can load without removing a [Chesterton's fence](https://en.wikipedia.org/wiki/Chesterton%27s_fence) they did not see. Prefer principles over outlines to copy. Recipes appear only as illustrations of a stated principle.

This is **not** Diátaxis tutorial, how-to, or reference — keep those outbound in user / contributing / advanced guides. Also not agent-only compact system models or short maintainer orientation notes (“what you need before you touch anything”); related themes may overlap — point by audience; do not merge or silently fork.

Prefer this project's recoverable design *why* over copying another project's outline. Outside examples can corroborate; they do not redefine “good” for *this* system.

This skill is a **reference**: hold the principles while you write.

## Apply an Inclusion Bar

**Principle:** Include a topic only if it helps load the whole-system model, is a Chesterton's fence, or is unsafe to change without knowing it. Omit ordinary facts, procedure recipes, and corner-only subsystem deep-dives.

**Why:** Completeness without a bar becomes a thin seed list or a dump of every pattern in the repo.

**Not this:** Mirroring an internal pattern catalog into Architecture, or treating a brainstorm seed list as the outline with no inclusion test.

## Keep Procedures Outbound

**Principle:** Architecture owns the model. Install steps, repair recipes, Make loops, and CLI flag tables live in how-to guides, linked from Architecture — not recopied as atlas body.

**Why:** Procedure dumps drift and blur Diátaxis boundaries.

**Not this:** Turning Architecture into Contributing 2.0 or pasting troubleshooting runbooks into doctrine pages.

## Cluster at Atlas Grain

**Principle:** Split pages or major sections by how the system is changed or understood (how code arrives and runs vs when work fires vs the data plane) — not one page per noun. Keep tightly coupled contracts on the same page as deep-linkable sections.

**Why:** Micro-pages thrash (“Packaging or Shim?”); mega-files hide change surfaces.

**Not this:** A dozen buzzword pages, or one undifferentiated dump with no thematic contracts.

## Orient with a Diagram That Loads the Model

**Principle:** Near the start, give a diagram that places the major pieces (and, when relevant, actors and flows) so a reader can navigate the rest of the atlas. Choose the *kind* of diagram for this system's load-bearing story — control flow, stack anatomy, desired-state vs generated-state, or another shape that actually orients.

**Why:** A map beats decoration. Mandating one diagram type teaches mimicry.

**Not this:** "Always open with a control-flow Mermaid flowchart," or a diagram that only restates the piece list without relationships. Do not default to a C4 stack unless that *is* the load-bearing story.

## Route Change Surfaces

**Principle:** Help a changer find which page or section owns a class of edits — a short “when you change X, read Y” table on the overview.

**Why:** An atlas that cannot answer “where do I look before I touch this?” fails under change.

**Not this:** Topic pages marketed as optional appendices with no change-oriented entry path.

## Lead with What Is; Explain Why for Fences

**Principle:** State what the system *is* first. Add *why* only for Chesterton's fences — or where ignorance causes damage.

**Why:** Design-diary voice hides the model under history; fence explanations prevent “obvious” removals.

**Not this:** Chronological design narrative as the spine, or unexplained magic with no hint a constraint is intentional.

## Name Invariants and Load-Bearing Boundaries

**Principle:** Call out deliberate absences, API or ownership boundaries, and contracts that look optional but are not — as named invariants or doctrines, not buried asides.

**Why:** Danger often lives in what is *not* there, or where rules change (desired state vs generated output).

**Not this:** Treating every module as equally special, or documenting only the happy path.

## Prefer Durable, Brief Stewardship

**Principle:** Prefer pointers to sources of truth that can change (config files, lockfiles, linked guides) over copying values that will rot. Update when factually wrong or materially incomplete — do not append every task's residue.

**Why:** Stale specifics kill trust. Brevity is inclusion discipline plus update discipline.

**Not this:** Cataloging every dependency version in prose, or a new Architecture section per shipped feature.

## Domain-Mapping Sibling

Some projects need a **domain mental model** (shared concept taxonomy, lossiness, honesty boundaries across tools) more than a systems atlas. Sibling genre: lead with the product goal, partition outcomes (clean / approximate / refuse), write boundary essays when mechanical translation is the wrong problem. Do not force atlas machinery onto that job — and do not treat a taxonomy guide as a substitute atlas when the ask is “how do the pieces fit and which fences must stay.”

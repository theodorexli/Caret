---
name: prompt-authoring
description: How to author a prompt, rule, or skill that an agent will actually follow. Use when writing or editing prompts, rules, skills, or other instructions meant for an AI agent.
---
# Prompt Authoring

Writing for an agent is not writing for a person. A person reads top to bottom and acts as they go, and may have used a programming language that behaves the same way; an agent reads the whole document first and then decides what to do. That one difference drives most of the guidance here. Before you write, work out what kind of thing you are writing, then keep the prose tight enough that the instructions survive being read all at once.

## Classify What You Are Writing

Most prompt-like artifacts are one of three kinds. Knowing which one you are writing tells you how to structure it.

| Kind | What it is | What it should not do |
| --- | --- | --- |
| Workflow | A process the agent executes: ordered steps, transitions, gates. | Bury ordering in prose, or assume the agent reads in document order. |
| Reference | Facts and constraints the agent should hold in mind while it works. | Tell the agent *when* to apply them, or carry a tone. |
| Personality | Disposition, posture, and defaults: how the agent carries itself. | Hardcode a specific process or a specific fact set. |

A workflow is a recipe. A reference is the spec sheet you keep open while cooking. A personality is the cook. The three compose: a reference layers onto whatever personality and workflow are active, and a personality sits underneath every workflow.

Deeper guidance for each kind lives next to this file:

- `references/workflow-prompts.md`
- `references/reference-prompts.md`
- `references/personality-prompts.md`

When the artifact you are writing is a skill, also read `references/skill-frontmatter.md` - the frontmatter and file layout are a separate contract from the prose.

## When It Is None of These

The three kinds are a lens, not a gate. Plenty of good documents are a deliberate mix *or* something else entirely, and forcing a mixed document into one box makes it worse. Write what the document needs; use the kinds to check that each part is doing its job, not to amputate the parts that don't fit.

For example, a style guide for a programming language is mostly reference - facts about syntax and convention. It might still open with one line of personality ("we value clarity over cleverness") and close with a two-step workflow ("run the formatter, then commit"). That is a healthy composite. Do not strip the opening line and the closing steps just to make it "pure reference."

When a document is composite, keep the parts legible: a reader (human or agent) should be able to tell which sentences are facts, which are process, and which are posture.

## Cross-References

Avoid referring to other prompts from inside a prompt. At authoring time you rarely know where another prompt will be at runtime, what version of it is loaded, or whether it is present at all. A reference to something you do not control is a promise you cannot keep, and a skill that assumes its siblings are installed breaks the moment someone installs it alone.

Two cases are safe:

1. Execution handoff. "Now invoke X." This is not a reference to X's *content*; it is a transfer of control. The detail stays in X, where it belongs.
2. Closed execution stack. You are authoring both the orchestrator and the piece it calls, and you control every entry point into the flow. There, a note like "concern Y is handled downstream by X" is accurate, because you are the one guaranteeing it. However, most of the time "concern Y is handled downstream" will suffice without needing to name X; this produces a more extensible, robust design - prefer it.

Everything else - restating what another prompt says, summarizing a sibling's behavior, pointing at a document you don't own - is the thing to cut. If two documents state the same rule, they will eventually drift and disagree.

## Prose Style

An agent spends attention on every sentence it reads. Filler and vagueness are not free; they dilute the instructions that matter. The anti-slop writing tradition has a few rules that apply directly to prompts:

- Name the content in headings. A heading is a label, not a teaser. "Error handling" beats "The Thing About Errors."
- Cut filler openers. "It's important to note that", "Keep in mind that", "When it comes to" add length, not meaning. Open on the instruction.
- End on something concrete. If a rule says "be careful with X," say what careful looks like. A sentence that asserts importance without a detail tells the agent nothing.
- Reserve the absolutes. "Always", "never", and "critical" lose their force when every third line uses them. Spend them only where they are literally true, and the agent will treat them as literal.

## Self-Check

Before you ship a prompt, run this pass:

1. Name the kind (or note that it is a deliberate composite). Does the structure match?
2. If any part is a workflow, is every ordering stated explicitly - numbered steps, named transitions - rather than implied by position?
3. Remove every cross-reference that is not an execution handoff or a closed-stack guarantee.
4. Cut filler openers and hollow sentences. Make each instruction end on something concrete.
5. Check the headings: each names its content, carries no parenthetical, and is short enough to drop into a navigation sidebar.
6. Reserve "always", "never", and "critical" for the few places they are literally true.

# Skill Frontmatter

This file covers the container a skill ships in: the `SKILL.md` frontmatter and the file layout around it. The upstream authority is [Best practices for skill creators](https://agentskills.io/skill-creation/best-practices) and [Optimizing skill descriptions](https://agentskills.io/skill-creation/optimizing-descriptions). Read those for the limits and the numbers, which change; the facts below do not.

## The Description Is the Trigger

An agent sees only `name` and `description` until it decides to load a skill. The description therefore carries the whole triggering burden - it is a decision input, not a label. Write it as an instruction about when to act, phrase it in terms of what the user is trying to do rather than how the skill works, and name the situations that apply even when the user will not use the skill's vocabulary. A description that reads like a title will not fire.

Bound it in the other direction too. A description broad enough to match anything gets loaded when it is useless, which costs context and pulls the agent toward instructions that do not apply. Name at least one near neighbor the skill does *not* cover.

There is a hard character limit on `description`. The [specification](https://agentskills.io/specification) has the current number.

## Re-derive the Description When the Skill Changes Shape

A description describes an arrangement, and arrangements change. When a skill is split, absorbed, refactored, reworked, or left behind by the retirement of the skills it used to work alongside, its description usually still describes the old arrangement and will keep triggering on the old occasions.

So treat any structural change to a skill as a reason to re-derive its description from what the skill now does, rather than editing the old wording. Check the body at the same time: a description that promises a broader scope than the body delivers gives the agent contradictory instructions at the moment it is deciding whether to comply.

## Split When SKILL.md Grows

Detail that is not needed on every run belongs in a sibling file rather than in `SKILL.md`, so it loads on demand. State the condition for reading each one. "Read `references/api-errors.md` when the API returns a non-200" tells the agent when to spend the context; "see `references/` for details" does not.

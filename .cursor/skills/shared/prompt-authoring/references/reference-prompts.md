# Reference Prompts

A reference prompt states facts and constraints the agent should keep in mind while it works: conventions, rules, properties of a system, things that are true regardless of what the agent is doing at the moment. A style guide is a reference. A list of invariants is a reference.

## State Facts, Not Procedure

A reference says what is true, not when to act on it. The moment a document starts sequencing - "first do this, then that" - it has become a workflow, and it should be written and labeled as one. Keep the two apart. If order matters, it belongs in a workflow; a reference that smuggles in a process is hard to reuse and easy to misread.

## Layer Cleanly

A reference does not run on its own. It layers onto whatever personality and workflow are active when the agent consults it. Write it so it composes: state the facts plainly and leave the agent's disposition and current process alone. A reference that bakes in assumptions about the surrounding process - "since you are in the build step..." - only fits one situation, when the whole point of a reference is to hold across many.

## Stay Flat and Scannable

An agent (or a person) consults a reference to find one fact fast, not to read it through. Favor a flat structure with clear headings and short entries. Group related facts so they are easy to locate. Deep nesting and long narrative work against the one job a reference has: quick lookup.

## Carry No Tone

Disposition belongs in a personality prompt. A reference should read as neutral statements of fact. When a reference starts arguing for a posture or adopting a voice, it has drifted into personality, and it will fight whatever personality the agent already has.

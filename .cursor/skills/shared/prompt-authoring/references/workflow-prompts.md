# Workflow Prompts

A workflow prompt tells an agent how to execute a process: do this, then this, stop here, branch there. Workflows are the kind of prompt most often written badly, because authors reach for habits that come from writing for people or for interpreted programs - and neither habit holds.

## An Agent Reads Everything First

A human reads a procedure line by line and acts as they go, so step 4 is genuinely unknown while they work step 2. An interpreted program is the same: position in the file controls what runs when. Authors lean on that without noticing - they let *location in the document* carry ordering information, because for a human or an interpreter it does.

An agent does not work that way. It reads the entire prompt, then decides what to do. By the time it acts on step 2, it has already read step 9 and the final warning. Anything you encoded purely by position is gone, because to the agent there is no "later in the document" - it is all present at once.

So state ordering explicitly. Number the steps. Say what triggers each transition and what gates it ("when the tests pass, continue; otherwise stop"). Never rely on "as described above" or "you'll see why below" to carry sequence - the agent saw both at the same time.

## Numbered Lists Versus Bulleted Lists

The list style is a signal, so use it deliberately.

- A numbered list says order matters: do these in sequence.
- A bulleted list says order does not matter: this is a set, handle them in any order.

Mixing the signal up - numbering a set that has no order, or bulleting steps that must run in sequence - tells the agent the opposite of what you mean.

## Repeat on Purpose, Omit on Purpose

Repetition in a workflow is often correct, not redundant. If a constraint applies at three different steps, and the agent might act at any of them, state the constraint at all three. The instinct to "say it once" comes from writing for a reader who passes through every line in order; an agent may engage a step in isolation, so the constraint has to be present where it is needed.

Omission is just as deliberate. When you want a step handled on its own terms, do not cross-link it to other steps; the silence keeps the agent from dragging in context you wanted left out.

## Emoji as Markers

A small, consistent set of glyphs can help an agent parse structure fast - a stop sign for a hard halt, a single marker for "this is a phase boundary." That is a legitimate use: the glyph is load-bearing.

Keep the set tiny and consistent, and give each glyph one meaning. Decorative emoji, or a different glyph every few lines, are noise the agent has to wade through. If a marker is not doing a job, cut it.

## Diagram the Control Flow

An agent reads a diagram the same way it reads the prose around it. A Mermaid flowchart sitting in the raw text is legible to the agent whether or not it is ever rendered to a picture, so the usual reason to skip one - "this prompt won't be viewed anywhere that draws the chart" - does not apply when the reader is an agent. If you also know the prompt lands somewhere that renders Mermaid for a human, better still; treat that as a bonus, not the deciding factor. Diagram when the shape of the work earns it.

Let the control flow choose the diagram:

- Straight through, with an occasional stop or skip: no diagram. A numbered list with a couple of explicit halts carries it, and a chart would just be the list drawn twice.
- Several branches that split and rejoin: a flowchart. A chart shows branching at a glance in a way a numbered list cannot.
- A lot of back and forth: a sequence diagram. When the work is an exchange - calls and responses, handoffs that return - a sequence diagram captures the round trips that a flowchart flattens.

The above pattern *generalizes* to all the major kinds of `mermaid` diagrams; the above examples are illustrative - not exhaustive - any complex section of prose is a *candidate* for evaluating whether a diagram would enhance comprehension.

When you do diagram, keep the "map" separate from the "driving instructions". The diagram is the map: it shows the flow and nothing else. The prose is how the vehicle is driven: it gives the algorithm for navigating that flow - what to evaluate at each node, what each branch means, where to stop. Don't make the prose re-narrate the diagram, and don't cram the operating rules into the diagram. They are two views of one process, and each carries what the other can't: the chart holds the structure, the prose holds the procedure.

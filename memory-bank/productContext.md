# Product Context

Caret is a native Mac assistant with an always-available Jev judge. App state, clipboard context, Screenpipe history and current computer observations feed one decision service. It chooses abstention, an inline text offer or an action, then selects a workflow when needed. The shared contract is [docs/input-pipeline.md](../docs/input-pipeline.md). This repository is a **contributor starter**, not the finished demo.

## Target Audience

The intended user works in existing Mac apps and wants text assistance or actions without assembling context in a separate chat. Meeting coordination is one demo use case, not the entire product.

Teddy owns the app and UX, the context teammate owns Screenpipe, and Sam owns the choice and definitions of the two demo workflows. Other agents connect the shared judge and workflow contracts without replacing those owners' work.

## Use Cases

These are the three seeded workflows. Only the calendar-link preview currently runs, and only against labeled sample data.

- **Propose meeting times.** From a thread that asks for times, show up to three supported slots plus the evidence used, then (once live sending is connected) put a draft in front of the user before anything leaves the machine.
- **Hold and confirm.** After an approved send, place tentative calendar holds for the offered times. A later reply that picks one time keeps that hold and drops the others from this run.
- **Book a flight.** Navigate a booking site from the chosen option and stop before payment. This seed exists; it does not execute yet.
- **Revise selected text.** Change text in place in the original app after rechecking that the selection is still the same. This seed exists; it does not execute yet.

The CLI supports a **synthetic** Dallas meeting, calculated options and local hold transitions. At app commit `827a387`, Teddy's UI shows a cursor-adjacent trigger, pinned actions and a scrollable action list; its callback logs and closes the panel. It is not connected to the CLI. Live thread retrieval, sending, calendar writes and computer execution remain unconnected.

## Key Benefits

- The user sees the proposed times and the evidence together before anything is sent or held.
- Clock arithmetic, source failures, and hold state are checked in ordinary code rather than trusted to a model.
- Failed or missing sources drop the option. The product does not invent availability, travel times, or fares to fill a gap.

Benefits that depend on live Gmail, calendar, travel data, or a browser executor are targets, not present capabilities.

## Success Criteria

The stated hackathon demo, once sources are connected:

- Start from the Austin–Dallas corridor, with a real travel source or a sourced, dated cached timetable (the current buffer numbers are **not** a timetable).
- Open a real thread, invoke Caret, and inspect a filled request.
- Enter produces up to three supported options and their evidence.
- Sending the approved draft creates tentative calendar holds.
- A labeled staged reply selects one option; one confirmation keeps it and removes only this run's other holds.
- A booking path can reach a payment page and must stop there.

The starter today only proves local preview math and local hold transitions on synthetic data. Which of the remaining demo steps will be live by the event is still being decided.

## Key Constraints

- Supported scope ends before payment. Do not add purchases, hotel search, or multi-party polling.
- Fixture content is synthetic and cannot be sent. A draft is created only from supported, sourced options.
- The app currently observes focused fields and selections through Accessibility to position its trigger. Caret.app launches pinned Screenpipe 0.4.50 on port 3031; last-N windows, minutes, and clipboard are available through `python3 -m caret`.
- Live credentials and personal threads stay out of Git. Source integrations need explicit configuration.
- External sending, calendar writes, Jev routing, and browser execution are **not connected**. Connecting them is future work, not an implied current capability.

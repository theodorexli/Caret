# Project Brief

## User Story

As a Caret user, I want Translate to use the current selection when text is selected, and the clipboard when nothing is selected, so I can translate in place without copying first.

## Use-Case(s)

### Use-Case 1

The user selects text in another app and runs Translate. Caret translates that selection.

### Use-Case 2

The user has no selection and runs Translate. Caret translates the clipboard.

## Requirements

1. Translate uses selected text when a non-empty selection exists.
2. Translate uses the clipboard when nothing is selected.
3. Other skill actions stay on their existing input rules.

## Constraints

1. Happy-path ship only; do not expand Translate into a new workflow or language picker.
2. Preserve the shared gateway skill runner unless Translate truly needs a distinct input path.
3. Do not invent translation facts; the existing skill instructions still govern the model.

## Acceptance Criteria

1. With a non-empty selection, Translate's input is that selection, not the clipboard.
2. With no selection and non-empty clipboard text, Translate's input is the clipboard.
3. Existing gateway tests and `make check` / `make test` stay green.

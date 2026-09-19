# Project Brief

## User Story

As someone opening Caret Debug, I want the last-N windows preview to omit the Debug window itself so I can see the window I was looking at before Debug opened.

## Use-Case(s)

### Use-Case 1

I am looking at another app, then I open Debug from the Caret menu. The newest window in the preview is that other app, not Caret Debug.

## Requirements

1. Clip the Debug window out of last-N **windows** shown by Debug.
2. The newest remaining window is the one in view before Debug launched.

## Constraints

1. Change is limited to Debug last-N windows. Minutes and clipboard stay as they are. Inference last-N hard-fail stays as it is.

## Acceptance Criteria

1. Opening Debug does not list the Debug window as the most recent window.
2. The most recent window shown is the one that was in view before Debug opened.

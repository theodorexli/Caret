# Progress

Add a Caret skill that pauses the current app, understands a complaint, finds that app's public GitHub repository, searches for matching issues, and offers to open a new issue or comment on an existing one. Fail fast with an explicit non-open-source message when GitHub issue search/file is not possible.

**Complexity:** Level 3

## 2026-09-19 - COMPLEXITY-ANALYSIS - COMPLETE

* Work completed
    - Validated intent: pivot-to-report skill with match-or-open, plus fail-fast when the app is not a public GitHub issue target
    - Classified as Level 3 (complete feature, multiple components, no new architecture)
* Decisions made
    - Current write/search surface is public GitHub only
    - Non-GitHub trackers stay as a code-comment extension point
* Insights
    - Existing Caret skill/workflow contracts are the insertion point; this is not a second judge or history engine

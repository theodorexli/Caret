# Project Brief

## User Story

As a Mac user running Caret, I want to pause whatever app I am in, describe a problem I just hit, and have Caret find that app's GitHub repository, search for matching issues, and offer to open a new report or comment on an existing one, so I can file a useful bug without leaving my flow or duplicating a report.

## Use-Case(s)

### Pivot from a broken app to a new issue

I am in some application, something goes wrong, and I invoke the report skill. Caret understands my complaint, identifies the app's public GitHub repository, finds no matching issue, and offers to open one for me.

### Enhance an existing report

Same pivot, but a matching issue already exists. Caret summarizes what that report already says, recommends whether my failure mode adds new information, and offers to post a comment for me.

### Non-open-source fail-fast

The app I am in is not a public GitHub project I can search and file issues against. Caret tells me explicitly that this does not appear to be an open-source application and stops. It does not invent a tracker or a report.

## Requirements

1. Provide a Caret skill the user can invoke from the current application to pivot into a bug report.
2. Understand the user's complaint about what went wrong.
3. Identify the GitHub repository that belongs to the application in use.
4. Search that repository's GitHub issues for reports that match the complaint.
5. If no match exists, offer to open a new GitHub issue.
6. If a match exists, summarize what is already known on that report, recommend whether the user should add a comment with the new failure-mode details, and offer to post that comment.
7. Fail fast, with an explicit "this does not appear to be an open-source application" outcome, when the app is not a public GitHub repository the skill can search and file issues against.
8. Leave a code-comment hook for later work that would find a non-GitHub canonical bug-report location; do not implement that path now.

## Constraints

1. Current scope is public GitHub issue search and write only. Other trackers are out of scope.
2. Do not invent a repository, issue, or fact when lookup or search fails.
3. Do not file or comment without an explicit user offer/acceptance.
4. Live credentials and personal data stay out of Git. GitHub access needs explicit configuration.
5. Preserve Caret's selected upstreams and existing owner boundaries. This is a new skill/workflow on the existing contracts, not a second judge or history engine.
6. Hackathon bias: happy-path ship; fail fast on non-OSS rather than building a vendor-tracker framework.
7. Prefer existing capabilities over new ones. Do not add a GitHub REST client or PyGithub. `prepare` may use the already-present `gh` CLI for read-only search. `execute` must defer the write to the existing computer-use-jev runner (same pattern as `NativeComputerUseWorkflow`), not invent a second browser engine or a `gh issue create` happy path.

## Acceptance Criteria

1. Invoking the skill from a known public GitHub-backed app with a novel complaint produces an offer to open a new issue, not a silent write.
2. Invoking it when a matching issue exists produces a summary of that issue, a recommend-comment-or-not decision, and an offer to comment.
3. Invoking it from an app with no searchable public GitHub issues fails immediately and states that the application does not appear to be open source.
4. Comments in the fail-fast path name the future extension point for non-GitHub canonical report locations without implementing it.

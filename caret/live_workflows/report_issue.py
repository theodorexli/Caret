"""Explicit-invoke workflow: research a public GitHub issue, write only after accept."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from uuid import uuid4

from ..context import ContextFrame
from ..registry import Availability, ExecutionResult, Preparation, WorkflowDescriptor
from .github import GitHubPort, PublicGitHub, complaint_from, recommend, resolve_repo, search_issues

WORKFLOW_ID = "report-github-issue"
EXPLICIT_SOURCE = "explicit_invoke"
ALLOWED_REPO_SOURCES = frozenset({"url", "api-search"})
NEW_ISSUE_GOAL = "Open a new GitHub issue on https://github.com/{slug}/issues/new in the already-signed-in browser session."
COMMENT_GOAL = "Open {issue_url} in the already-signed-in browser session and add a comment on that issue."


class ReportGithubIssueWorkflow:
    """Prepare with public GitHub HTTP; execute a templated computer-use-jev goal."""

    descriptor = WorkflowDescriptor(
        id=WORKFLOW_ID,
        name="Report a GitHub issue",
        description="Search the current app's public GitHub issues and offer to comment or open a new report.",
        required_inputs=("computer-use-jev executable", "TYPESAFE_API_KEY", "signed-in GitHub browser session"),
        execution_method="computer-use-jev",
        sample_only=False,
    )

    def __init__(self, *, github: GitHubPort | None = None, environ=None, clock=time.monotonic, timeout=120.0, spawn=None):
        self.github = github or PublicGitHub()
        self.environ = dict(os.environ if environ is None else environ)
        self.binary = self.environ.get("CARET_COMPUTER_USE_JEV", "")
        self.clock = clock
        self.timeout = timeout
        self.spawn = spawn
        self.pending = {}

    def availability(self, frame: ContextFrame) -> Availability:
        if not any(source.name == EXPLICIT_SOURCE and source.available for source in frame.sources):
            return Availability(False, "Report a GitHub issue is an explicit panel action.")
        if not self.binary:
            return Availability(False, "Set CARET_COMPUTER_USE_JEV to the absolute path of the built executable.")
        if not self.environ.get("TYPESAFE_API_KEY"):
            return Availability(False, "TYPESAFE_API_KEY is missing. Native Jev execution needs its own API credential.")
        return Availability(True)

    def prepare(self, frame: ContextFrame) -> Preparation:
        repo = resolve_repo(frame, self.github)
        complaint = complaint_from(frame)
        matches = search_issues(repo, complaint, self.github)
        decision = recommend(repo, matches, complaint)
        token = str(uuid4())
        payload = {
            "token": token,
            "mode": decision.mode,
            "repo_slug": repo.slug,
            "repo_source": repo.evidence,
        }
        if decision.issue is not None:
            payload["issue_url"] = decision.issue.html_url
            payload["issue_number"] = decision.issue.number
        if decision.mode == "new-issue":
            title = f"Open a GitHub issue on {repo.slug}"
            effect = f"Open a new issue on {repo.html_url} in the signed-in browser. Nothing is filed until you accept."
        elif decision.mode == "comment":
            title = f"Comment on {repo.slug}#{decision.issue.number}"
            effect = f"Add a comment on {decision.issue.html_url}. Nothing is posted until you accept."
        else:
            title = f"{repo.slug}#{decision.issue.number} already describes this"
            effect = f"This looks already covered by {decision.issue.html_url}. Accept to comment anyway."
        preparation = Preparation(
            title=title,
            effect=effect,
            evidence=(decision.summary, f"Repository from {repo.evidence}."),
            payload=payload,
        )
        self.pending[token] = (self.clock(), frame.snapshot, preparation)
        self.pending = {key: value for key, value in self.pending.items() if self.clock() - value[0] <= 30}
        return preparation

    def execute(self, frame: ContextFrame, preparation: Preparation | None) -> ExecutionResult:
        token = preparation.payload.get("token") if preparation else None
        pending = self.pending.pop(token, None) if isinstance(token, str) else None
        if pending is None:
            return ExecutionResult(status="failed", summary="Report proposal is unknown, expired, cancelled or already accepted.")
        created, snapshot, original = pending
        if preparation != original or frame.snapshot != snapshot or self.clock() - created > 30:
            return ExecutionResult(status="failed", summary="The report proposal or its original field changed; nothing ran.")
        if preparation.payload.get("repo_source") not in ALLOWED_REPO_SOURCES:
            return ExecutionResult(status="failed", summary="Repository identity was not evidenced by a URL or public search.")
        if not self.binary:
            return ExecutionResult(status="failed", summary="The configured computer-use-jev executable is missing or not executable.")
        goal = self._goal(preparation)
        command = [self.binary, "-json", "-max-steps", "8", "-goal", goal]
        if self.spawn is not None:
            return self.spawn(command, self.environ)
        return self._run_jev(command)

    def cancel(self, preparation: Preparation | None) -> ExecutionResult:
        token = preparation.payload.get("token") if preparation else None
        if isinstance(token, str):
            self.pending.pop(token, None)
        return ExecutionResult(status="cancelled", summary="Report proposal discarded before execution.")

    def _goal(self, preparation: Preparation) -> str:
        if preparation.payload.get("mode") == "new-issue":
            return NEW_ISSUE_GOAL.format(slug=preparation.payload["repo_slug"])
        return COMMENT_GOAL.format(issue_url=preparation.payload["issue_url"])

    def _run_jev(self, command: list[str]) -> ExecutionResult:
        if not Path(self.binary).is_file() or not os.access(self.binary, os.X_OK):
            return ExecutionResult(status="failed", summary="The configured computer-use-jev executable is missing or not executable.")
        with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
            try:
                process = subprocess.Popen(command, stdout=stdout, stderr=stderr, env=self.environ)
            except OSError as error:
                return ExecutionResult(status="failed", summary=f"Cannot start computer-use-jev: {error}")
            timed_out = False
            try:
                process.wait(timeout=self.timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                process.send_signal(signal.SIGINT)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
            stdout.seek(0)
            trace = stdout.read(2_000_001)
            stderr.seek(0, 2)
            stderr.seek(max(0, stderr.tell() - 2000))
            diagnostic = stderr.read().decode("utf-8", errors="replace")
        key = self.environ.get("TYPESAFE_API_KEY")
        if key:
            diagnostic = diagnostic.replace(key, "[redacted]")
        if timed_out:
            return ExecutionResult(status="failed", summary="Native execution timed out. Some actions may already have occurred.")
        if len(trace) > 2_000_000:
            return ExecutionResult(status="failed", summary="Native trace exceeded the readback limit. Some actions may already have occurred.")
        try:
            records = [json.loads(line) for line in trace.splitlines() if line.strip()]
            if any(not isinstance(record, dict) for record in records):
                raise ValueError("trace records must be objects")
        except (ValueError, UnicodeError):
            return ExecutionResult(status="failed", summary="Native executor returned an invalid trace. Some actions may already have occurred.")
        steps = [record for record in records if isinstance(record.get("number"), int)]
        evidence = tuple(
            f"Step {step['number']}: {step.get('action', 'observation')}: {str(step.get('output', ''))[:300]}"
            for step in steps[-4:]
        )
        if process.returncode != 0:
            return ExecutionResult(
                status="failed",
                summary="Jev native execution did not complete. Some actions may already have occurred.",
                evidence=evidence + ((diagnostic,) if diagnostic else ()),
            )
        if not steps or steps[-1].get("output") != "goal satisfied; no action taken":
            return ExecutionResult(status="failed", summary="Native executor exited without a completion trace.", evidence=evidence)
        return ExecutionResult(
            status="completed",
            summary="Jev finished the accepted GitHub write.",
            evidence=evidence,
            effects=("Native GitHub navigation",),
            data={"executor": "computer-use-jev", "step_count": len(steps)},
        )

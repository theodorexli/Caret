"""ReportGithubIssueWorkflow: explicit prepare, templated Jev execute."""

from __future__ import annotations

from dataclasses import replace
from pathlib import Path
import tempfile
import unittest

from caret.context import SourceRecord
from caret.live_workflows.github import NoComplaint, NotOpenSource, SearchFailed
from caret.live_workflows.report_issue import ReportGithubIssueWorkflow
from caret.registry import Preparation
from support import frame
from test_report_issue import FakeGitHub, explicit_frame


def public_repo(**overrides):
    row = {
        "full_name": "acme/ghostty",
        "private": False,
        "archived": False,
        "has_issues": True,
        "html_url": "https://github.com/acme/ghostty",
    }
    row.update(overrides)
    return row


class RecordingSpawn:
    def __init__(self, result=None):
        self.calls = []
        self.result = result

    def __call__(self, command, environ):
        self.calls.append({"command": list(command), "environ": dict(environ)})
        if self.result is not None:
            return self.result
        from caret.registry import ExecutionResult

        return ExecutionResult(status="completed", summary="Jev finished.", data={"executor": "computer-use-jev"})


def adapter(*, repos=None, issues=None, issue_bodies=None, repo_error=None, binary="/tmp/jev", key="secret", spawn=None, clock=None):
    github = FakeGitHub(repos=repos if repos is not None else [public_repo()], issues=issues, issue_bodies=issue_bodies, repo_error=repo_error)
    now = {"t": 0.0}

    def tick():
        return now["t"]

    workflow = ReportGithubIssueWorkflow(
        github=github,
        environ={"CARET_COMPUTER_USE_JEV": binary, "TYPESAFE_API_KEY": key} if key else {"CARET_COMPUTER_USE_JEV": binary},
        clock=clock or tick,
        spawn=spawn,
    )
    workflow._now = now
    workflow._github = github
    return workflow


class DescriptorTests(unittest.TestCase):
    def test_descriptor_is_an_executable_computer_use_offer(self):
        workflow = ReportGithubIssueWorkflow(environ={})
        self.assertEqual(workflow.descriptor.execution_method, "computer-use-jev")
        self.assertFalse(workflow.descriptor.sample_only)
        self.assertEqual(workflow.descriptor.id, "report-github-issue")

    def test_availability_requires_an_explicit_invoke_source(self):
        workflow = adapter()
        self.assertFalse(workflow.availability(frame(text="It crashed")).available)
        explicit = explicit_frame("It crashed", app="Ghostty")
        self.assertTrue(workflow.availability(explicit).available)
        missing_key = adapter(key="")
        self.assertFalse(missing_key.availability(explicit).available)


class PrepareTests(unittest.TestCase):
    def test_prepare_returns_an_offer_payload_and_spawns_nothing(self):
        spawn = RecordingSpawn()
        workflow = adapter(spawn=spawn)
        complaint = "Window flashes black"
        preparation = workflow.prepare(explicit_frame(complaint, app="Ghostty"))
        self.assertEqual(preparation.missing_inputs, ())
        self.assertEqual(preparation.payload["mode"], "new-issue")
        self.assertEqual(preparation.payload["repo_slug"], "acme/ghostty")
        self.assertEqual(preparation.payload["repo_source"], "api-search")
        self.assertTrue(preparation.payload["token"])
        self.assertEqual(spawn.calls, [])

    def test_prepare_raises_the_typed_github_errors(self):
        with self.assertRaises(NoComplaint):
            adapter().prepare(explicit_frame("", app="Ghostty"))
        with self.assertRaises(NotOpenSource):
            adapter(repos=[]).prepare(explicit_frame("It crashed", app="SecretApp"))
        with self.assertRaises(SearchFailed):
            adapter(repo_error=SearchFailed()).prepare(explicit_frame("It crashed", app="Ghostty"))

    def test_prepare_succeeds_when_the_executor_is_missing(self):
        workflow = adapter(binary="/no/such/jev-binary")
        preparation = workflow.prepare(explicit_frame("It crashed", app="Ghostty"))
        self.assertEqual(preparation.payload["repo_slug"], "acme/ghostty")
        self.assertEqual(preparation.missing_inputs, ())


class ExecuteTests(unittest.TestCase):
    def test_execute_spawns_once_with_a_templated_goal(self):
        spawn = RecordingSpawn()
        workflow = adapter(spawn=spawn)
        complaint = "Window flashes black with a unique tokenxyz"
        context = explicit_frame(complaint, app="Ghostty")
        preparation = workflow.prepare(context)
        result = workflow.execute(context, preparation)
        self.assertEqual(result.status, "completed")
        self.assertEqual(len(spawn.calls), 1)
        goal = spawn.calls[0]["command"][spawn.calls[0]["command"].index("-goal") + 1]
        self.assertIn("acme/ghostty", goal)
        self.assertNotIn(complaint, goal)
        self.assertNotIn("unique tokenxyz", goal)
        self.assertEqual(workflow.execute(context, preparation).status, "failed")
        self.assertEqual(len(spawn.calls), 1)

    def test_execute_refuses_bad_tokens_snapshots_and_repo_sources(self):
        spawn = RecordingSpawn()
        workflow = adapter(spawn=spawn)
        context = explicit_frame("It crashed", app="Ghostty")
        preparation = workflow.prepare(context)
        self.assertEqual(workflow.execute(context, replace(preparation, payload={**preparation.payload, "token": "nope"})).status, "failed")
        moved = replace(context, snapshot=replace(context.snapshot, nearby_text="different crash"))
        self.assertEqual(workflow.execute(moved, workflow.prepare(context)).status, "failed")
        workflow._now["t"] = 31
        expired = workflow.prepare(context)
        workflow._now["t"] = 62
        self.assertEqual(workflow.execute(context, expired).status, "failed")
        fresh = workflow.prepare(context)
        tampered = replace(fresh, payload={**fresh.payload, "repo_source": "guessed"})
        workflow.pending[fresh.payload["token"]] = (workflow._now["t"], context.snapshot, tampered)
        self.assertEqual(workflow.execute(context, tampered).status, "failed")
        self.assertEqual(spawn.calls, [])

    def test_execute_fails_when_the_executor_is_missing(self):
        spawn = RecordingSpawn()
        workflow = adapter(binary="", spawn=spawn)
        context = explicit_frame("It crashed", app="Ghostty")
        preparation = workflow.prepare(context)
        self.assertEqual(workflow.execute(context, preparation).status, "failed")
        self.assertEqual(spawn.calls, [])


if __name__ == "__main__":
    unittest.main()

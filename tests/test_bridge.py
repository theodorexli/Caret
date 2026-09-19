"""The bridge as a real process: JSON lines over real pipes.

These tests spawn `python3 -m caret.bridge` and talk to its stdin and stdout.
The providers are scripted because a unit test must not call a paid endpoint,
but the transport, the threading, the framing and the error envelope are the
real ones.

`EventOrderTests` at the end runs the same Bridge in-process against a pipe pair
of its own. It has to: it pins down what happens when the context changes inside
one specific window of the evaluation, and choosing that moment by hand is the
difference between a test and a coin flip.
"""

import json
import os
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from queue import Empty, Queue

from caret.bridge import END_OF_OUTPUT, Bridge, build_registry
from caret.context import ContextFrame
from caret.engine import Engine
from caret.live_workflows.report_issue import ReportGithubIssueWorkflow
from caret.registry import Availability, ExecutionResult, Preparation, WorkflowDescriptor, WorkflowError, WorkflowRegistry
from caret.router import RouterConfig
from support import RecordingJudge, RecordingWriter

ROOT = Path(__file__).resolve().parent.parent
TIMEOUT = 20.0


class BridgeProcess:
    """Spawns the bridge and separates correlated replies from events."""

    def __init__(self, script: dict, workdir: Path, interval: float = 0.05, extra=(), judge: str | None = None):
        self.script_path = workdir / "script.json"
        self.script_path.write_text(json.dumps(script))
        self.process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "caret.bridge",
                "--judge",
                judge or f"scripted:{self.script_path}",
                "--writer",
                f"scripted:{self.script_path}",
                "--fixture",
                str(ROOT / "fixtures" / "meeting.json"),
                "--db",
                str(workdir / "bridge.sqlite"),
                "--interval",
                str(interval),
                *extra,
            ],
            cwd=ROOT,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.replies: Queue = Queue()
        self.events: Queue = Queue()
        self._next_id = 0
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            line = line.strip()
            if not line:
                continue
            message = json.loads(line)
            (self.replies if "id" in message else self.events).put(message)

    def call(self, method, params=None):
        self._next_id += 1
        self.send_raw(json.dumps({"id": self._next_id, "method": method, "params": params or {}}))
        return self.replies.get(timeout=TIMEOUT)

    def send_raw(self, line: str):
        self.process.stdin.write(line + "\n")
        self.process.stdin.flush()

    def raw_reply(self):
        return self.replies.get(timeout=TIMEOUT)

    def wait_for_event(self, name, timeout=TIMEOUT):
        """Return the next event with this name, skipping bookkeeping events."""
        deadline = threading.Event()
        timer = threading.Timer(timeout, deadline.set)
        timer.start()
        try:
            while not deadline.is_set():
                try:
                    event = self.events.get(timeout=0.5)
                except Empty:
                    continue
                if event.get("event") == name:
                    return event
            return None
        finally:
            timer.cancel()

    def expect_no_event(self, seconds=0.6):
        try:
            return self.events.get(timeout=seconds)
        except Empty:
            return None

    def collect_events(self, quiet_seconds=1.5):
        """Every event until the stream has been quiet for `quiet_seconds`."""
        seen = []
        while True:
            try:
                seen.append(self.events.get(timeout=quiet_seconds))
            except Empty:
                return seen

    def close(self):
        try:
            self.call("shutdown")
        except Exception:
            pass
        try:
            self.process.stdin.close()
        except Exception:
            pass
        try:
            self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:  # pragma: no cover - only on a hang
            self.process.kill()
            self.process.wait(timeout=5)
        for pipe in (self.process.stdout, self.process.stderr):
            if pipe is not None:
                pipe.close()


def synthetic_frame(revision=1, text="I will send the ", element="compose", secure=False, ime=False):
    caret = len(text.encode("utf-16-le")) // 2
    return {
        "snapshot": {
            "revision": revision,
            "captured_at": "2026-09-19T12:00:00+00:00",
            "target": {
                "pid": 4242,
                "bundle_id": "com.example.SyntheticEditor",
                "window_id": "w1",
                "element_id": element,
                "element_revision": f"r{revision}",
            },
            "role": "AXTextArea",
            "nearby_text": text,
            "text_offset": 0,
            "caret": caret,
            "selection": {},
            "secure": secure,
            "ime_composing": ime,
        },
        "permissions": {"accessibility": True},
        "clipboard": {"available": False},
        "history": [],
        "observations": [],
        "sources": [],
    }


class BridgeTestCase(unittest.TestCase):
    script = {"route": ["ABSTAIN"]}
    interval = 0.05
    extra = ()

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.workdir = Path(self._tmp.name)
        self.bridge = BridgeProcess(self.script, self.workdir, self.interval, self.extra)

    def tearDown(self):
        self.bridge.close()
        self._tmp.cleanup()


class HandshakeTests(BridgeTestCase):
    def test_hello_reports_the_protocol_and_the_workflow_catalog(self):
        reply = self.bridge.call("hello")
        self.assertTrue(reply["ok"])
        result = reply["result"]
        self.assertEqual(result["protocol"], 1)
        catalog = {row["id"]: row for row in result["workflows"]}
        self.assertIn("book-calendar-link", catalog)
        self.assertTrue(catalog["book-calendar-link"]["sample_only"])
        self.assertEqual(catalog["book-flight"]["execution_method"], "unwired")

    def test_a_malformed_line_gets_an_error_and_the_process_keeps_running(self):
        self.bridge.send_raw("{not json")
        reply = self.bridge.raw_reply()
        self.assertFalse(reply["ok"])
        self.assertEqual(reply["error"]["code"], "invalid_json")
        self.assertTrue(self.bridge.call("hello")["ok"], "the bridge survives a bad line")

    def test_an_unknown_method_is_refused(self):
        reply = self.bridge.call("context.delete_everything")
        self.assertEqual(reply["error"]["code"], "unknown_method")

    def test_an_invalid_context_frame_is_refused_with_the_offending_field(self):
        broken = synthetic_frame()
        del broken["snapshot"]["caret"]
        reply = self.bridge.call("context.update", {"frame": broken})
        self.assertFalse(reply["ok"])
        self.assertEqual(reply["error"]["code"], "invalid_context")
        self.assertIn("caret", reply["error"]["message"])


class AbstentionTests(BridgeTestCase):
    script = {"route": ["ABSTAIN"]}

    def test_an_abstention_is_reported_and_shows_nothing(self):
        self.assertTrue(self.bridge.call("context.update", {"frame": synthetic_frame(1)})["ok"])
        event = self.bridge.wait_for_event("abstain")
        self.assertIsNotNone(event)
        self.assertEqual(event["revision"], 1)

    def test_a_secure_field_is_skipped_without_any_evaluation(self):
        reply = self.bridge.call("context.update", {"frame": synthetic_frame(1, secure=True)})
        self.assertEqual(reply["result"]["status"], "skipped")
        self.assertEqual(reply["result"]["reason"], "secure-field")
        self.assertIsNone(self.bridge.expect_no_event(), "a secure field must produce no offer traffic")

    def test_ime_composition_is_skipped_without_any_evaluation(self):
        reply = self.bridge.call("context.update", {"frame": synthetic_frame(1, ime=True)})
        self.assertEqual(reply["result"]["reason"], "ime-composing")
        self.assertIsNone(self.bridge.expect_no_event())


class InlineOfferTests(BridgeTestCase):
    script = {"route": ["INLINE"], "inline": ["summary to the team"]}

    def test_an_inline_offer_round_trips_and_is_accepted_once(self):
        self.bridge.call("context.update", {"frame": synthetic_frame(1)})
        event = self.bridge.wait_for_event("offer")
        self.assertIsNotNone(event, "an inline route should publish an offer")
        offer = event["offer"]
        self.assertEqual(offer["kind"], "inline")
        self.assertEqual(offer["replacement"], "summary to the team")
        self.assertEqual(offer["replace_start"], 16)

        accepted = self.bridge.call(
            "offer.accept",
            {"proposal_id": offer["proposal_id"], "revision": offer["revision"], "target": offer["target"]},
        )
        self.assertTrue(accepted["ok"])
        self.assertEqual(accepted["result"]["status"], "ready_to_insert")

        repeat = self.bridge.call(
            "offer.accept",
            {"proposal_id": offer["proposal_id"], "revision": offer["revision"], "target": offer["target"]},
        )
        self.assertFalse(repeat["ok"])
        self.assertEqual(repeat["error"]["code"], "acceptance_rejected")
        self.assertIn("already accepted", repeat["error"]["message"])

    def test_moving_to_another_field_invalidates_the_visible_offer(self):
        self.bridge.call("context.update", {"frame": synthetic_frame(1)})
        offer = self.bridge.wait_for_event("offer")["offer"]

        self.bridge.call("context.update", {"frame": synthetic_frame(2, text="different", element="subject")})
        self.assertIsNotNone(self.bridge.wait_for_event("invalidated"))

        rejected = self.bridge.call(
            "offer.accept",
            {"proposal_id": offer["proposal_id"], "revision": offer["revision"], "target": offer["target"]},
        )
        self.assertFalse(rejected["ok"], "an offer for an abandoned field must not execute")


class ActionExecutionTests(BridgeTestCase):
    script = {"route": ["ACTION"], "workflow": ["book-calendar-link"]}

    def test_an_accepted_action_runs_the_workflow_and_returns_a_real_result(self):
        self.bridge.call("context.update", {"frame": synthetic_frame(1)})
        offer = self.bridge.wait_for_event("offer")["offer"]
        self.assertEqual(offer["workflow_id"], "book-calendar-link")
        self.assertTrue(offer["sample_only"])
        self.assertIn("no external calendar event", offer["effect"])

        accepted = self.bridge.call(
            "offer.accept",
            {"proposal_id": offer["proposal_id"], "revision": offer["revision"], "target": offer["target"]},
        )
        result = accepted["result"]
        self.assertEqual(result["status"], "completed")
        self.assertEqual(len(result["data"]["holds"]), 3)
        self.assertTrue(all(hold["status"] == "tentative" for hold in result["data"]["holds"]))
        self.assertIn("cannot be sent", result["data"]["notice"])

    def test_acceptance_from_a_different_target_is_refused(self):
        self.bridge.call("context.update", {"frame": synthetic_frame(1)})
        offer = self.bridge.wait_for_event("offer")["offer"]
        elsewhere = dict(offer["target"], element_id="some-other-field")
        reply = self.bridge.call(
            "offer.accept",
            {"proposal_id": offer["proposal_id"], "revision": offer["revision"], "target": elsewhere},
        )
        self.assertFalse(reply["ok"])
        self.assertIn("target changed", reply["error"]["message"])


class ProviderFailureTests(BridgeTestCase):
    script = {"route": [{"error": "HTTP 503 from api.typesafe.ai: upstream unavailable"}]}

    def test_a_provider_failure_surfaces_as_a_failure_and_offers_nothing(self):
        self.bridge.call("context.update", {"frame": synthetic_frame(1)})
        event = self.bridge.wait_for_event("failed")
        self.assertIsNotNone(event)
        self.assertIn("503", event["reason"])
        self.assertIsNone(self.bridge.expect_no_event(), "a failure must not be followed by an offer")


class UnmodelledFailureTests(BridgeTestCase):
    """A script with no 'workflow' section makes the scripted judge raise
    ScriptExhausted, which is neither a JudgeError nor a WorkflowError. That is
    the shape of any exception the engine does not model."""

    script = {"route": ["ACTION", "ABSTAIN"]}
    extra = ("--failure-backoff", "0.05")

    def test_an_unmodelled_exception_does_not_stop_later_evaluations(self):
        self.bridge.call("context.update", {"frame": synthetic_frame(1)})
        failed = self.bridge.wait_for_event("failed")
        self.assertIsNotNone(failed)
        self.assertEqual(failed["revision"], 1, "the failure names the frame it happened on")
        self.assertIn("workflow", failed["reason"])

        self.bridge.call("context.update", {"frame": synthetic_frame(2, text="typing on")})
        abstained = self.bridge.wait_for_event("abstain")
        self.assertIsNotNone(abstained, "the evaluation loop must still be running")
        self.assertEqual(abstained["revision"], 2)


class GatewayStartupTests(unittest.TestCase):
    def test_the_gateway_providers_refuse_to_start_without_their_key(self):
        environment = dict(os.environ)
        environment.pop("AI_GATEWAY_API_KEY", None)
        completed = subprocess.run(
            [sys.executable, "-m", "caret.bridge", "--judge", "gateway", "--writer", "gateway"],
            cwd=ROOT,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            env=environment,
            check=False,
        )
        self.assertNotEqual(completed.returncode, 0, "an unconfigured bridge must not start")
        self.assertIn("AI_GATEWAY_API_KEY", completed.stderr)
        self.assertEqual(completed.stdout, "", "a refusal must not look like protocol output")


class SchedulingOverTransportTests(BridgeTestCase):
    script = {"route": ["INLINE"], "inline": ["one"]}
    interval = 1.0
    """Long enough that seven updates land inside one interval, so which frame
    gets evaluated is observable rather than a race."""

    def test_rapid_updates_evaluate_only_the_newest_frame(self):
        statuses = []
        for revision in range(1, 8):
            reply = self.bridge.call(
                "context.update", {"frame": synthetic_frame(revision, text="text " + "x" * revision)}
            )
            statuses.append(reply["result"]["status"])
        self.assertIn("coalesced", statuses, "continuous typing must coalesce, not queue one call per keystroke")
        self.assertEqual(statuses.count("admitted"), 1, "one interval admits one evaluation")

        evaluated = [
            event["offer"]["revision"] if event["event"] == "offer" else event["revision"]
            for event in self.bridge.collect_events()
            if event["event"] in ("offer", "abstain", "failed", "discarded")
        ]
        self.assertIn(7, evaluated, "the newest frame is the one that gets asked about")
        self.assertEqual(
            sorted(set(evaluated) - {1, 7}),
            [],
            f"a superseded revision reached a provider: {evaluated}",
        )

    def test_a_replayed_revision_is_refused(self):
        self.bridge.call("context.update", {"frame": synthetic_frame(5)})
        reply = self.bridge.call("context.update", {"frame": synthetic_frame(4, text="older")})
        self.assertEqual(reply["result"]["reason"], "superseded-revision")


class OrderedOutput:
    """Stands in for stdout and keeps the written lines in order."""

    def __init__(self):
        self._lock = threading.Lock()
        self._lines: list[str] = []

    def write(self, text: str) -> None:
        with self._lock:
            self._lines.append(text)

    def flush(self) -> None:
        pass

    def messages(self) -> list[dict]:
        with self._lock:
            return [json.loads(line) for line in self._lines if line.strip()]


class HeldStdin:
    """Feeds request lines, then holds the read loop open until released.

    A closed stdin stops the bridge, so a test that needs an evaluation to
    finish has to keep the loop alive until it has what it came for.
    """

    def __init__(self, lines, release: threading.Event):
        self._lines = list(lines)
        self._release = release

    def __iter__(self):
        yield from self._lines
        self._release.wait(TIMEOUT)


class ContextChangesOnPublishEngine(Engine):
    """Changes the context the instant an evaluation finishes.

    This is the interleaving the ordering depends on, placed by hand: the app's
    next frame arrives after the router has published an offer and before the
    bridge has had any chance to write it out. Doing it from this thread rather
    than racing the stdin thread for the same window is what makes the result
    the same on every run.
    """

    def pump(self):
        publication = super().pump()
        if publication is not None and publication.status == "published":
            self.submit(
                ContextFrame.from_dict(synthetic_frame(2, text="moved on", element="subject"))
            )
        return publication


class EventOrderTests(unittest.TestCase):
    def test_an_offer_is_written_before_the_invalidation_that_retires_it(self):
        release = threading.Event()
        output = OrderedOutput()
        stdin = HeldStdin(
            [json.dumps({"id": 1, "method": "context.update", "params": {"frame": synthetic_frame(1)}})],
            release,
        )
        registry = WorkflowRegistry()

        def factory(on_invalidate, on_publish):
            return ContextChangesOnPublishEngine(
                RecordingJudge(route=["INLINE"]),
                RecordingWriter("summary to the team"),
                registry,
                RouterConfig(interval_seconds=0.0),
                on_invalidate=on_invalidate,
                on_publish=on_publish,
            )

        bridge = Bridge(factory, registry, stdin, output)
        running = threading.Thread(target=bridge.run, name="bridge-under-test", daemon=True)
        running.start()
        try:
            deadline = time.monotonic() + TIMEOUT
            while time.monotonic() < deadline:
                names = {message.get("event") for message in output.messages()}
                if {"offer", "invalidated"} <= names:
                    break
                time.sleep(0.01)
        finally:
            release.set()
            running.join(timeout=TIMEOUT)

        events = [message for message in output.messages() if "event" in message]
        retired = [event for event in events if event["event"] == "invalidated"]
        self.assertTrue(retired, f"the changed context should have retired the offer: {events}")
        proposal_id = retired[0]["proposal_id"]
        self.assertEqual(retired[0]["reason"], "context-changed")

        announced = [
            index
            for index, event in enumerate(events)
            if event["event"] == "offer" and event["offer"]["proposal_id"] == proposal_id
        ]
        self.assertTrue(announced, f"the retired offer was never announced at all: {events}")
        self.assertLess(
            announced[0],
            events.index(retired[0]),
            "an offer written after its own invalidation lets a client show a preview "
            f"it has already been told to take down: {[event['event'] for event in events]}",
        )


class BuiltInRegistryTests(unittest.TestCase):
    def test_report_github_issue_is_registered_without_an_adapter_flag(self):
        with tempfile.TemporaryDirectory() as tmp:
            registry = build_registry(ROOT / "fixtures" / "meeting.json", Path(tmp) / "caret.sqlite")
            self.assertIsInstance(registry.get("report-github-issue"), ReportGithubIssueWorkflow)


class ReportStub:
    """A built-in-shaped adapter that never talks to GitHub or Jev."""

    descriptor = WorkflowDescriptor(
        id="report-github-issue",
        name="Report a GitHub issue",
        description="",
        execution_method="computer-use-jev",
    )

    def availability(self, frame):
        return Availability(False, "explicit only")

    def prepare(self, frame):
        if "closed-source" in frame.snapshot.nearby_text:
            raise WorkflowError("This does not appear to be an open-source application.")
        return Preparation(title="Open a GitHub issue", effect="Nothing until accept.", payload={"token": "t"})

    def execute(self, frame, preparation):
        return ExecutionResult(status="completed", summary="stub wrote nothing")

    def cancel(self, preparation):
        return ExecutionResult(status="cancelled", summary="cancelled")


class InProcessPrepare:
    def __init__(self):
        self.output = OrderedOutput()
        self.registry = WorkflowRegistry()
        self.registry.register(ReportStub())

        def factory(on_invalidate, on_publish):
            return Engine(
                RecordingJudge(route=["ABSTAIN"]),
                RecordingWriter(),
                self.registry,
                RouterConfig(interval_seconds=0.0),
                on_invalidate=on_invalidate,
                on_publish=on_publish,
            )

        self.bridge = Bridge(factory, self.registry, __import__("io").StringIO(), self.output)
        self._drain = threading.Thread(target=self.bridge._drain_output, name="prepare-drain", daemon=True)
        self._drain.start()

    def handle(self, payload):
        before = len(self.output.messages())
        self.bridge._handle_line(json.dumps(payload))
        deadline = time.monotonic() + TIMEOUT
        while time.monotonic() < deadline:
            messages = self.output.messages()
            if len(messages) > before:
                return messages
            time.sleep(0.01)
        return self.output.messages()

    def close(self):
        self.bridge._outbox.put(END_OF_OUTPUT)
        self._drain.join(timeout=2)


class PrepareWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.session = InProcessPrepare()

    def tearDown(self):
        self.session.close()

    def test_workflow_prepare_replies_with_the_offer_and_emits_no_event(self):
        messages = self.session.handle(
            {
                "id": 7,
                "method": "workflow.prepare",
                "params": {"workflow_id": "report-github-issue", "frame": synthetic_frame(3, text="It crashed")},
            }
        )
        self.assertEqual(len(messages), 1)
        reply = messages[0]
        self.assertEqual(reply["id"], 7)
        self.assertTrue(reply["ok"])
        self.assertEqual(reply["result"]["offer"]["workflow_id"], "report-github-issue")
        self.assertNotIn("event", reply)

    def test_workflow_prepare_returns_workflow_error_without_a_failed_event(self):
        messages = self.session.handle(
            {
                "id": 8,
                "method": "workflow.prepare",
                "params": {
                    "workflow_id": "report-github-issue",
                    "frame": synthetic_frame(3, text="closed-source app crash"),
                },
            }
        )
        self.assertEqual(len(messages), 1)
        reply = messages[0]
        self.assertFalse(reply["ok"])
        self.assertEqual(reply["error"]["code"], "workflow_error")
        self.assertIn("open-source", reply["error"]["message"])
        self.assertNotIn("event", reply)

    def test_prepare_then_accept_does_not_emit_failed(self):
        messages = self.session.handle(
            {
                "id": 1,
                "method": "workflow.prepare",
                "params": {"workflow_id": "report-github-issue", "frame": synthetic_frame(3, text="It crashed")},
            }
        )
        offer = messages[-1]["result"]["offer"]
        messages = self.session.handle(
            {
                "id": 2,
                "method": "offer.accept",
                "params": {
                    "proposal_id": offer["proposal_id"],
                    "revision": offer["revision"],
                    "target": offer["target"],
                },
            }
        )
        reply = messages[-1]
        self.assertTrue(reply["ok"])
        self.assertEqual(reply["result"]["status"], "completed")
        self.assertFalse(any(message.get("event") == "failed" for message in messages))


if __name__ == "__main__":
    unittest.main()

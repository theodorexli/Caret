"""The two decisions, the workflow seam, and what happens when a provider fails."""

import unittest

from caret.adapters import UnavailableWorkflow
from caret.engine import Engine, ProviderFailure
from caret.judge import JudgeError
from caret.registry import (
    Availability,
    ExecutionResult,
    Preparation,
    WorkflowDescriptor,
    WorkflowError,
    WorkflowRegistry,
)
from caret.router import AcceptanceError, RouterConfig
from support import Clock, RecordingJudge, RecordingWriter, frame, target


class CountingWorkflow:
    """Available, cheap, and counts how many times it actually executed."""

    def __init__(self, workflow_id="book-calendar-link", available=True, missing=()):
        self._descriptor = WorkflowDescriptor(
            id=workflow_id,
            name=f"Workflow {workflow_id}",
            description="A test workflow.",
            execution_method="test",
            sample_only=True,
        )
        self._available = available
        self._missing = tuple(missing)
        self.prepared = 0
        self.executed = 0

    @property
    def descriptor(self):
        return self._descriptor

    def availability(self, frame):
        return Availability(self._available, "" if self._available else "not configured in this test")

    def prepare(self, frame):
        self.prepared += 1
        return Preparation(
            title="Do the thing",
            effect="Writes a local row and nothing else.",
            evidence=("Synthetic evidence",),
            missing_inputs=self._missing,
            payload={"ok": True},
        )

    def execute(self, frame, preparation):
        self.executed += 1
        return ExecutionResult(status="completed", summary="did the thing", data={"n": self.executed})

    def cancel(self, preparation):
        return ExecutionResult(status="cancelled", summary="cancelled")


def build(route=None, workflow=None, writer=None, adapters=None, config=None):
    registry = WorkflowRegistry()
    for adapter in adapters or []:
        registry.register(adapter)
    clock = Clock()
    judge = RecordingJudge(route=route, workflow=workflow)
    engine = Engine(judge, writer or RecordingWriter(), registry, config or RouterConfig(), clock=clock)
    return engine, judge, registry, clock


class RouteTests(unittest.TestCase):
    def test_abstain_publishes_nothing(self):
        engine, judge, _, _ = build(route=["ABSTAIN"])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "abstained")
        self.assertIsNone(engine.router.current_offer)
        self.assertEqual(judge.calls, ["route"], "abstaining must not ask the workflow question")

    def test_inline_generates_text_and_publishes_an_offer(self):
        writer = RecordingWriter(text=" the team")
        engine, judge, _, _ = build(route=["INLINE"], writer=writer)
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "published")
        self.assertEqual(publication.offer.kind, "inline")
        self.assertEqual(publication.offer.replacement, " the team")
        self.assertEqual(writer.calls, 1)
        self.assertEqual(judge.calls, ["route"])

    def test_action_asks_a_second_question_and_prepares_the_chosen_workflow(self):
        adapter = CountingWorkflow()
        engine, judge, _, _ = build(route=["ACTION"], workflow=["book-calendar-link"], adapters=[adapter])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(judge.calls, ["route", "workflow"])
        self.assertEqual(publication.offer.workflow_id, "book-calendar-link")
        self.assertEqual(adapter.prepared, 1)
        self.assertEqual(adapter.executed, 0, "preparing must not execute anything")

    def test_nothing_runs_until_the_cadence_and_a_frame_are_both_ready(self):
        engine, judge, _, _ = build(route=["ABSTAIN"])
        self.assertIsNone(engine.pump(), "no context means no model call")
        self.assertEqual(judge.calls, [])


class WorkflowChoiceTests(unittest.TestCase):
    def test_the_judge_is_only_offered_workflows_that_report_available(self):
        available = CountingWorkflow("book-calendar-link")
        missing = UnavailableWorkflow(
            WorkflowDescriptor(id="book-flight", name="Book a flight", description=""), "no executor"
        )
        engine, _, registry, _ = build(route=["ACTION"], workflow=["book-calendar-link"], adapters=[available, missing])
        offered = [choice.id for choice in registry.choices(frame(1))]
        self.assertEqual(offered, ["book-calendar-link"])
        self.assertNotIn("book-flight", offered)

    def test_naming_an_unavailable_workflow_fails_instead_of_running_one(self):
        available = CountingWorkflow("book-calendar-link")
        missing = UnavailableWorkflow(
            WorkflowDescriptor(id="book-flight", name="Book a flight", description=""), "no executor"
        )
        engine, _, _, _ = build(route=["ACTION"], workflow=["book-flight"], adapters=[available, missing])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("book-flight", publication.reason)
        self.assertIsNone(engine.router.current_offer)

    def test_no_available_workflow_abstains_without_a_second_question(self):
        blocked = UnavailableWorkflow(
            WorkflowDescriptor(id="book-flight", name="Book a flight", description=""), "no executor"
        )
        engine, judge, _, _ = build(route=["ACTION"], adapters=[blocked])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual((publication.status, publication.reason), ("abstained", "no-available-workflow"))
        self.assertEqual(judge.calls, ["route"])

    def test_none_is_always_choosable_and_offers_nothing(self):
        engine, judge, _, _ = build(route=["ACTION"], workflow=["NONE"], adapters=[CountingWorkflow()])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual((publication.status, publication.reason), ("abstained", "no-workflow-fits"))
        self.assertIsNone(engine.router.current_offer)


class MalformedProviderTests(unittest.TestCase):
    """A provider that answers with nonsense must not produce an offer."""

    def assert_route_rejected(self, answer):
        engine, _, _, _ = build(route=[answer])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed", f"answer {answer!r} should have failed the tick")
        self.assertIsNone(engine.router.current_offer)
        return publication

    def test_an_unknown_route_label_is_refused(self):
        publication = self.assert_route_rejected("MAYBE")
        self.assertIn("not one of", publication.reason)

    def test_a_non_string_answer_is_refused(self):
        self.assert_route_rejected(17)

    def test_prose_around_the_label_is_refused_rather_than_parsed(self):
        self.assert_route_rejected("I think the answer is INLINE")

    def test_an_empty_answer_is_refused(self):
        self.assert_route_rejected("")

    def test_a_writer_returning_nothing_produces_no_offer(self):
        engine, _, _, _ = build(route=["INLINE"], writer=RecordingWriter(text=""))
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("empty", publication.reason)

    def test_a_writer_exceeding_the_edit_bound_produces_no_offer(self):
        engine, _, _, _ = build(route=["INLINE"], writer=RecordingWriter(text="x" * 5000))
        engine.submit(frame(1))
        self.assertEqual(engine.pump().status, "failed")


class ProviderFailureTests(unittest.TestCase):
    def test_a_judge_failure_produces_no_actionable_success(self):
        engine, _, _, _ = build(route=[JudgeError("HTTP 401 from api.typesafe.ai")])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("401", publication.reason)
        self.assertIsNone(publication.offer)
        with self.assertRaises(AcceptanceError):
            engine.accept("anything", 1, target())

    def test_a_writer_failure_produces_no_actionable_success(self):
        writer = RecordingWriter(error=ProviderFailure("Could not reach api.groq.com"))
        engine, _, _, _ = build(route=["INLINE"], writer=writer)
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIsNone(engine.router.current_offer)
        with self.assertRaises(AcceptanceError):
            engine.accept("anything", 1, target())

    def test_a_second_stage_failure_does_not_fall_back_to_the_first(self):
        engine, _, _, _ = build(
            route=["ACTION"], workflow=[JudgeError("timeout")], adapters=[CountingWorkflow()]
        )
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("judge/workflow", publication.reason)

    def test_a_workflow_that_fails_to_prepare_offers_nothing(self):
        class Broken(CountingWorkflow):
            def prepare(self, frame):
                raise WorkflowError("fixture is unreadable")

        engine, _, _, _ = build(route=["ACTION"], workflow=["book-calendar-link"], adapters=[Broken()])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("unreadable", publication.reason)


class UnexpectedExceptionTests(unittest.TestCase):
    """A tick must finish even when something raises a type the engine does not
    model. The router reopens its single in-flight slot only when an evaluation
    completes, so an escaping exception would stop the loop for the session."""

    def test_an_unexpected_writer_exception_ends_the_tick_and_reopens_the_slot(self):
        writer = RecordingWriter(error=RuntimeError("the transport died"))
        engine, _, _, clock = build(route=["INLINE"], writer=writer)
        engine.submit(frame(1))
        first = engine.pump()
        self.assertEqual(first.status, "failed")
        self.assertIn("unexpected RuntimeError", first.reason)
        self.assertIsNone(engine.router.current_offer)

        clock.advance(RouterConfig().failure_backoff_seconds)
        admission = engine.submit(frame(2, text="still typing", captured_at=clock()))
        self.assertEqual(admission.status, "admitted", "the in-flight slot must have reopened")
        self.assertEqual(engine.pump().status, "failed")
        self.assertEqual(writer.calls, 2, "the second frame really was evaluated")

    def test_an_unexpected_judge_exception_ends_the_tick(self):
        engine, _, _, _ = build(route=[RuntimeError("socket closed mid-read")])
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("unexpected RuntimeError", publication.reason)
        self.assertIsNone(engine.router.current_offer)

    def test_an_unexpected_availability_exception_ends_the_tick(self):
        class BrokenAvailability(CountingWorkflow):
            def availability(self, frame):
                raise RuntimeError("the executor vanished mid-check")

        engine, _, _, _ = build(
            route=["ACTION"], workflow=["book-calendar-link"], adapters=[BrokenAvailability()]
        )
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("unexpected RuntimeError", publication.reason)

    def test_an_unexpected_prepare_exception_ends_the_tick(self):
        class BrokenPrepare(CountingWorkflow):
            def prepare(self, frame):
                raise RuntimeError("the database path is a directory")

        engine, _, _, _ = build(
            route=["ACTION"], workflow=["book-calendar-link"], adapters=[BrokenPrepare()]
        )
        engine.submit(frame(1))
        publication = engine.pump()
        self.assertEqual(publication.status, "failed")
        self.assertIn("unexpected RuntimeError", publication.reason)
        self.assertIsNone(engine.router.current_offer)


class ExecutionTests(unittest.TestCase):
    def setUp(self):
        self.adapter = CountingWorkflow()
        self.engine, _, _, self.clock = build(
            route=["ACTION"], workflow=["book-calendar-link"], adapters=[self.adapter]
        )
        self.engine.submit(frame(1))
        self.offer = self.engine.pump().offer

    def test_acceptance_runs_the_workflow_exactly_once(self):
        result = self.engine.accept(self.offer.proposal_id, self.offer.revision, self.offer.target)
        self.assertEqual(result["status"], "completed")
        self.assertEqual(self.adapter.executed, 1)

    def test_a_repeated_acceptance_cannot_execute_a_second_time(self):
        self.engine.accept(self.offer.proposal_id, self.offer.revision, self.offer.target)
        with self.assertRaisesRegex(AcceptanceError, "already accepted"):
            self.engine.accept(self.offer.proposal_id, self.offer.revision, self.offer.target)
        self.assertEqual(self.adapter.executed, 1, "the workflow must not run twice")

    def test_an_expired_proposal_does_not_execute(self):
        self.clock.advance(RouterConfig().max_offer_age_seconds + 1)
        with self.assertRaises(AcceptanceError):
            self.engine.accept(self.offer.proposal_id, self.offer.revision, self.offer.target)
        self.assertEqual(self.adapter.executed, 0)

    def test_an_acceptance_after_the_field_changed_does_not_execute(self):
        with self.assertRaisesRegex(AcceptanceError, "target changed"):
            self.engine.accept(self.offer.proposal_id, self.offer.revision, target(element="elsewhere"))
        self.assertEqual(self.adapter.executed, 0)

    def test_missing_inputs_are_requested_instead_of_executed(self):
        adapter = CountingWorkflow(missing=("timetable",))
        engine, _, _, _ = build(route=["ACTION"], workflow=["book-calendar-link"], adapters=[adapter])
        engine.submit(frame(1))
        offer = engine.pump().offer
        result = engine.accept(offer.proposal_id, offer.revision, offer.target)
        self.assertEqual(result["status"], "needs_input")
        self.assertIn("timetable", result["summary"])
        self.assertEqual(adapter.executed, 0)

    def test_an_accepted_inline_offer_is_handed_back_for_the_app_to_insert(self):
        engine, _, _, _ = build(route=["INLINE"], writer=RecordingWriter(text=" the team"))
        engine.submit(frame(1))
        offer = engine.pump().offer
        result = engine.accept(offer.proposal_id, offer.revision, offer.target)
        self.assertEqual(result["status"], "ready_to_insert")
        self.assertEqual(result["replacement"], " the team")
        self.assertEqual((result["replace_start"], result["replace_end"]), (16, 16))


class PrepareNamedTests(unittest.TestCase):
    def test_prepare_named_returns_the_offer_without_submit(self):
        adapter = CountingWorkflow("report-github-issue")
        engine, _, _, _ = build(adapters=[adapter])
        offer = engine.prepare_named("report-github-issue", frame(3, text="It crashed"))
        self.assertEqual(offer.workflow_id, "report-github-issue")
        self.assertEqual(adapter.prepared, 1)
        self.assertEqual(adapter.executed, 0)
        self.assertIsNone(engine.router.take_due(engine.clock()))
        self.assertEqual(engine.router.current_offer.proposal_id, offer.proposal_id)

    def test_prepare_named_on_an_unregistered_id_raises(self):
        engine, _, _, _ = build()
        with self.assertRaises(WorkflowError):
            engine.prepare_named("report-github-issue", frame(1))

    def test_a_workflow_error_from_prepare_propagates_unchanged(self):
        class Broken(CountingWorkflow):
            def prepare(self, frame):
                raise WorkflowError("This does not appear to be an open-source application.")

        engine, _, _, _ = build(adapters=[Broken("report-github-issue")])
        with self.assertRaisesRegex(WorkflowError, "open-source"):
            engine.prepare_named("report-github-issue", frame(1))


if __name__ == "__main__":
    unittest.main()

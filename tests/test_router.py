"""Scheduling, suppression and offer lifetime, driven by a hand-moved clock."""

import threading
import unittest

from caret.context import ContextError, InputSnapshot, utf16_length, utf16_slice
from caret.registry import Preparation, WorkflowDescriptor, WorkflowError
from caret.router import (
    ACCESSIBILITY_REVOKED,
    APP_EXCLUDED,
    IME_COMPOSING,
    PROVIDER_BACKOFF,
    SECURE_FIELD,
    STALE_SOURCES,
    SUPERSEDED_REVISION,
    WORKFLOW_ACTIVE,
    AcceptanceError,
    Router,
    RouterConfig,
    build_action_offer,
    build_inline_offer,
)
from support import Clock, frame, target


class SchedulingTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.router = Router(RouterConfig(interval_seconds=2.0))

    def test_continuous_updates_evaluate_only_the_latest_snapshot(self):
        for revision in range(1, 6):
            self.router.submit(frame(revision, text="a" * revision), self.clock())
            self.clock.advance(0.1)
        taken = self.router.take_due(self.clock())
        self.assertEqual(taken.revision, 5, "the newest snapshot should be the one evaluated")
        self.assertIsNone(self.router.take_due(self.clock()), "the superseded frames are gone, not queued")

    def test_only_one_evaluation_runs_at_a_time(self):
        self.router.submit(frame(1), self.clock())
        self.router.take_due(self.clock())
        admission = self.router.submit(frame(2, text="later"), self.clock())
        self.assertEqual((admission.status, admission.reason), ("coalesced", "evaluation-in-flight"))
        self.assertIsNone(self.router.take_due(self.clock()), "nothing starts while one is in flight")

    def test_cadence_holds_the_next_evaluation_for_the_interval(self):
        self.router.submit(frame(1), self.clock())
        first = self.router.take_due(self.clock())
        self.router.complete_abstain(first)

        self.clock.advance(0.5)
        self.assertEqual(self.router.submit(frame(2, text="second"), self.clock()).reason, "cadence")
        self.assertIsNone(self.router.take_due(self.clock()))

        self.clock.advance(1.5)
        self.assertEqual(self.router.take_due(self.clock()).revision, 2)

    def test_a_replayed_or_reordered_revision_is_refused(self):
        self.router.submit(frame(5), self.clock())
        admission = self.router.submit(frame(4, text="older"), self.clock())
        self.assertEqual((admission.status, admission.reason), ("skipped", SUPERSEDED_REVISION))

    def test_same_snapshot_is_not_asked_about_twice(self):
        first = frame(1)
        self.router.submit(first, self.clock())
        self.router.complete_abstain(self.router.take_due(self.clock()))

        self.clock.advance(5)
        repeat = frame(2, captured_at=self.clock())
        self.assertEqual(repeat.signature(), first.signature(), "the builder must produce identical content")
        admission = self.router.submit(repeat, self.clock())
        self.assertEqual((admission.status, admission.reason), ("skipped", "unchanged-context"))
        self.assertIsNone(self.router.take_due(self.clock()))


class SuppressionTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.router = Router()

    def assert_suppressed(self, built, reason):
        admission = self.router.submit(built, self.clock())
        self.assertEqual((admission.status, admission.reason), ("skipped", reason))
        self.assertIsNone(self.router.take_due(self.clock()), "a suppressed frame is never evaluated")

    def test_secure_field_suppresses_ambient_work(self):
        self.assert_suppressed(frame(1, secure=True), SECURE_FIELD)

    def test_ime_composition_suppresses_ambient_work(self):
        self.assert_suppressed(frame(1, ime=True), IME_COMPOSING)

    def test_excluded_application_suppresses_ambient_work(self):
        self.assert_suppressed(frame(1, excluded=True), APP_EXCLUDED)

    def test_lost_accessibility_permission_suppresses_ambient_work(self):
        self.assert_suppressed(frame(1, accessibility=False), ACCESSIBILITY_REVOKED)

    def test_a_running_workflow_suppresses_ambient_work(self):
        self.assert_suppressed(frame(1, workflow_active=True), WORKFLOW_ACTIVE)

    def test_context_older_than_the_freshness_bound_suppresses_ambient_work(self):
        self.assert_suppressed(frame(1, source_age=600.0), STALE_SOURCES)

    def test_suppression_takes_down_a_visible_offer(self):
        invalidated = []
        router = Router(on_invalidate=lambda offer, reason: invalidated.append(reason))
        current = frame(1)
        router.submit(current, self.clock())
        router.complete_offer(router.take_due(self.clock()), build_inline_offer(current, "x", self.clock(), RouterConfig()))
        self.assertIsNotNone(router.current_offer)

        router.submit(frame(2, secure=True), self.clock())
        self.assertIsNone(router.current_offer, "a secure field must clear the visible offer")
        self.assertEqual(invalidated, [SECURE_FIELD])


class StalenessTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.router = Router()
        self.config = RouterConfig()

    def test_a_response_that_arrives_after_a_field_switch_is_discarded(self):
        original = frame(1, element="compose", element_revision="r1")
        self.router.submit(original, self.clock())
        in_flight = self.router.take_due(self.clock())

        # The user clicks into a different field while the provider is working.
        self.router.submit(frame(2, element="subject", element_revision="r9"), self.clock())

        late = build_inline_offer(in_flight, " the team", self.clock(), self.config)
        publication = self.router.complete_offer(in_flight, late)
        self.assertEqual((publication.status, publication.reason), ("discarded", "stale-snapshot"))
        self.assertIsNone(self.router.current_offer, "a stale answer must never become a visible offer")

    def test_a_different_target_at_the_same_revision_is_still_stale(self):
        self.router.submit(frame(3, element="compose"), self.clock())
        self.assertTrue(self.router.is_stale(frame(3, element="elsewhere")))

    def test_editing_the_text_invalidates_a_published_offer(self):
        reasons = []
        router = Router(on_invalidate=lambda offer, reason: reasons.append(reason))
        original = frame(1)
        router.submit(original, self.clock())
        router.complete_offer(router.take_due(self.clock()), build_inline_offer(original, " team", self.clock(), self.config))

        router.submit(frame(2, text="different text entirely"), self.clock())
        self.assertIsNone(router.current_offer)
        self.assertEqual(reasons, ["context-changed"])

    def test_a_provider_failure_backs_off_without_suppressing_the_context(self):
        self.router.submit(frame(1), self.clock())
        publication = self.router.complete_failure(self.router.take_due(self.clock()), "judge: HTTP 503")
        self.assertEqual(publication.status, "failed")
        self.assertIsNone(publication.offer)

        # Continuous typing supplies a new eligible frame every keystroke. The
        # backoff is what stops each one from calling a provider that just failed.
        self.clock.advance(self.config.failure_backoff_seconds / 2)
        held = self.router.submit(frame(2, captured_at=self.clock()), self.clock())
        self.assertEqual((held.status, held.reason), ("coalesced", PROVIDER_BACKOFF))
        self.assertIsNone(self.router.take_due(self.clock()), "nothing runs during the backoff")

        # An abstention would have suppressed this signature for good. A failure
        # must not: the same context is retried once the backoff elapses.
        self.clock.advance(self.config.failure_backoff_seconds)
        retry = frame(3, captured_at=self.clock())
        self.assertEqual(self.router.submit(retry, self.clock()).status, "admitted")
        self.assertEqual(self.router.take_due(self.clock()).revision, 3)

    def test_only_the_newest_frame_survives_a_backoff(self):
        self.router.submit(frame(1), self.clock())
        self.router.complete_failure(self.router.take_due(self.clock()), "judge: HTTP 503")
        for revision in (2, 3, 4):
            self.clock.advance(1)
            self.router.submit(frame(revision, text="x" * revision, captured_at=self.clock()), self.clock())

        self.clock.advance(self.config.failure_backoff_seconds)
        self.assertEqual(self.router.take_due(self.clock()).revision, 4)
        self.assertIsNone(self.router.take_due(self.clock()), "the held frames were replaced, not queued")

    def test_a_successful_evaluation_after_a_backoff_returns_to_the_cadence(self):
        self.router.submit(frame(1), self.clock())
        self.router.complete_failure(self.router.take_due(self.clock()), "judge: HTTP 503")
        self.clock.advance(self.config.failure_backoff_seconds)
        self.router.submit(frame(2, text="second try", captured_at=self.clock()), self.clock())
        self.router.complete_abstain(self.router.take_due(self.clock()))

        self.clock.advance(self.config.interval_seconds)
        admission = self.router.submit(frame(9, text="new text", captured_at=self.clock()), self.clock())
        self.assertEqual(admission.status, "admitted", "one failure must not hold the loop open")


class LifecycleOrderTests(unittest.TestCase):
    """The announcement happens inside the transition, not after it.

    Both callbacks fire with the router's lock held, so a second thread cannot
    land its own event between a state change and the news of it. Without that,
    an offer and the invalidation retiring it can reach the app in either order.
    """

    def test_a_publication_is_announced_before_the_lock_is_released(self):
        clock = Clock()
        announced = []
        competing = threading.Event()
        competitor_finished = threading.Event()

        def on_publish(publication):
            announced.append(("publish", publication.status))
            competitor = threading.Thread(target=invalidate_from_another_thread, daemon=True)
            competitor.start()
            self.assertTrue(competing.wait(5.0), "the competing thread never started")
            self.assertFalse(
                competitor_finished.wait(0.1),
                "another thread invalidated the offer between the transition and its "
                "announcement, so the two events can be announced out of order",
            )
            threads.append(competitor)

        def invalidate_from_another_thread():
            competing.set()
            router.invalidate("context-changed")
            competitor_finished.set()

        threads: list[threading.Thread] = []
        router = Router(
            on_invalidate=lambda offer, reason: announced.append(("invalidate", reason)),
            on_publish=on_publish,
        )
        current = frame(1)
        router.submit(current, clock())
        router.complete_offer(
            router.take_due(clock()), build_inline_offer(current, " the team", clock(), RouterConfig())
        )
        for competitor in threads:
            competitor.join(timeout=5.0)

        self.assertEqual(announced, [("publish", "published"), ("invalidate", "context-changed")])

    def test_every_finished_evaluation_is_announced(self):
        clock = Clock()
        seen = []
        # No cadence and no backoff: this test is about what gets announced, and
        # the waits are covered by SchedulingTests.
        config = RouterConfig(interval_seconds=0.0, failure_backoff_seconds=0.0)
        router = Router(config, on_publish=lambda publication: seen.append(publication.status))

        router.submit(frame(1), clock())
        router.complete_abstain(router.take_due(clock()), "judge-abstained")
        router.submit(frame(2, text="second"), clock())
        router.complete_failure(router.take_due(clock()), "judge: HTTP 503")

        stale = frame(3, text="third")
        router.submit(stale, clock())
        in_flight = router.take_due(clock())
        router.submit(frame(4, text="moved on", element="subject"), clock())
        router.complete_offer(in_flight, build_inline_offer(in_flight, "x", clock(), config))

        self.assertEqual(seen, ["abstained", "failed", "discarded"])


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.router = Router()
        self.config = RouterConfig()
        self.frame = frame(1)
        self.router.submit(self.frame, self.clock())
        self.offer = build_inline_offer(self.frame, " the team", self.clock(), self.config)
        self.router.complete_offer(self.router.take_due(self.clock()), self.offer)

    def accept(self, **overrides):
        args = {
            "proposal_id": self.offer.proposal_id,
            "revision": self.offer.revision,
            "target": self.offer.target,
            "now": self.clock(),
        }
        args.update(overrides)
        return self.router.accept(**args)

    def test_a_current_proposal_is_accepted_once(self):
        self.assertEqual(self.accept().proposal_id, self.offer.proposal_id)

    def test_the_same_proposal_cannot_be_accepted_twice(self):
        self.accept()
        with self.assertRaisesRegex(AcceptanceError, "already accepted"):
            self.accept()

    def test_a_proposal_past_its_window_is_refused(self):
        self.clock.advance(self.config.max_offer_age_seconds + 1)
        with self.assertRaisesRegex(AcceptanceError, "acceptance window"):
            self.accept()

    def test_acceptance_carrying_the_wrong_revision_is_refused(self):
        with self.assertRaisesRegex(AcceptanceError, "built for revision"):
            self.accept(revision=self.offer.revision + 1)

    def test_acceptance_against_a_different_target_is_refused(self):
        with self.assertRaisesRegex(AcceptanceError, "target changed"):
            self.accept(target=target(element="somewhere-else"))

    def test_acceptance_of_an_unknown_proposal_is_refused(self):
        with self.assertRaisesRegex(AcceptanceError, "not the current offer"):
            self.accept(proposal_id="00000000-0000-0000-0000-000000000000")

    def test_an_invalidated_proposal_cannot_be_accepted(self):
        self.router.submit(frame(2, text="moved on"), self.clock())
        with self.assertRaisesRegex(AcceptanceError, "no current offer"):
            self.accept()

    def test_a_relaunch_that_only_changes_the_pid_takes_the_offer_down(self):
        relaunched = frame(2, pid=5555)
        self.assertNotEqual(
            relaunched.signature(),
            self.frame.signature(),
            "the signature must notice a new process even when everything else matches",
        )
        self.router.submit(relaunched, self.clock())
        self.assertIsNone(self.router.current_offer)
        with self.assertRaisesRegex(AcceptanceError, "no current offer"):
            self.accept()

    def test_an_offer_for_a_target_the_router_has_replaced_is_not_accepted(self):
        # complete_offer validates the frame it was asked about, not the offer's
        # own target. Acceptance is the step that executes, so it rechecks rather
        # than trusting that invalidation already ran.
        router = Router()
        router.submit(frame(1), self.clock())
        abandoned = build_inline_offer(frame(1, pid=5555), " the team", self.clock(), self.config)
        router.complete_offer(router.take_due(self.clock()), abandoned)
        with self.assertRaisesRegex(AcceptanceError, "target changed"):
            router.accept(abandoned.proposal_id, abandoned.revision, abandoned.target, self.clock())

    def test_a_consumed_proposal_id_is_not_kept_past_its_acceptance_window(self):
        self.accept()
        self.clock.advance(self.config.max_offer_age_seconds + 1)

        later_frame = frame(2, text="a different sentence", captured_at=self.clock())
        self.router.submit(later_frame, self.clock())
        later = build_inline_offer(later_frame, " and Dana", self.clock(), self.config)
        self.router.complete_offer(self.router.take_due(self.clock()), later)
        self.router.accept(later.proposal_id, later.revision, later.target, self.clock())

        # The first ID has been dropped, so it is refused for having no current
        # offer rather than by name. Either way it cannot execute again.
        with self.assertRaisesRegex(AcceptanceError, "no current offer"):
            self.accept()


class InlineRangeTests(unittest.TestCase):
    """Code fixes the edit range; the model only supplies characters."""

    def setUp(self):
        self.clock = Clock()
        self.config = RouterConfig()

    def test_without_a_selection_the_offer_inserts_at_the_caret(self):
        built = frame(1, text="I will send the ")
        offer = build_inline_offer(built, "summary", self.clock(), self.config)
        self.assertEqual((offer.replace_start, offer.replace_end), (16, 16))
        self.assertEqual(offer.replacement, "summary")

    def test_with_a_selection_the_offer_replaces_exactly_that_selection(self):
        built = frame(1, text="I will send the ", selection=(2, 6))
        offer = build_inline_offer(built, "shall", self.clock(), self.config)
        self.assertEqual((offer.replace_start, offer.replace_end), (2, 6))
        self.assertNotEqual(offer.original_digest, "", "the replaced text is digested for revalidation")

    def test_generation_above_the_bound_is_refused_rather_than_shortened(self):
        with self.assertRaisesRegex(ValueError, "above the"):
            build_inline_offer(frame(1), "x" * 400, self.clock(), self.config)

    def test_empty_generation_is_refused(self):
        with self.assertRaisesRegex(ValueError, "empty"):
            build_inline_offer(frame(1), "", self.clock(), self.config)

    def test_offsets_count_utf16_units_so_astral_characters_do_not_shift_edits(self):
        text = "wave 🌊 "
        built = frame(1, text=text)
        self.assertEqual(utf16_length(text), 8, "the emoji occupies two UTF-16 units")
        offer = build_inline_offer(built, "crest", self.clock(), self.config)
        self.assertEqual(offer.replace_start, 8)
        self.assertEqual(utf16_slice(text, 5, 7), "🌊")

    def test_a_range_that_splits_a_surrogate_pair_is_rejected(self):
        with self.assertRaisesRegex(ContextError, "surrogate"):
            utf16_slice("a🌊b", 1, 2)


class InstallOfferTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.invalidated = []
        self.published = []
        self.router = Router(
            RouterConfig(interval_seconds=0.0, failure_backoff_seconds=10.0),
            on_invalidate=lambda offer, reason: self.invalidated.append((offer.proposal_id, reason)),
            on_publish=lambda publication: self.published.append(publication),
        )

    def action_offer(self, ctx):
        return build_action_offer(
            ctx,
            WorkflowDescriptor(
                id="report-github-issue",
                name="Report",
                description="",
                execution_method="computer-use-jev",
            ),
            Preparation(title="Open a GitHub issue", effect="Nothing until accept.", payload={"token": "t"}),
            self.clock(),
        )

    def test_install_offer_clears_pending_so_take_due_returns_none(self):
        self.router.submit(frame(1), self.clock())
        explicit = frame(2, text="explicit")
        offer = self.action_offer(explicit)
        self.router.install_offer(explicit, offer)
        self.assertIsNone(self.router.take_due(self.clock()))
        self.assertEqual(self.router.current_offer.proposal_id, offer.proposal_id)

    def test_install_offer_moves_target_and_revision_so_accept_succeeds(self):
        explicit = frame(5, text="explicit")
        offer = self.action_offer(explicit)
        self.router.install_offer(explicit, offer)
        accepted = self.router.accept(offer.proposal_id, offer.revision, offer.target, self.clock())
        self.assertEqual(accepted.proposal_id, offer.proposal_id)

    def test_install_offer_invalidates_the_previous_offer(self):
        first = frame(1)
        self.router.submit(first, self.clock())
        first_offer = build_inline_offer(first, "hi", self.clock(), RouterConfig())
        self.router.complete_offer(self.router.take_due(self.clock()), first_offer)
        explicit = frame(2, text="explicit")
        self.router.install_offer(explicit, self.action_offer(explicit))
        self.assertEqual(self.invalidated[-1], (first_offer.proposal_id, "replaced-by-explicit-invoke"))

    def test_an_in_flight_ambient_offer_is_discarded_after_install(self):
        self.router.submit(frame(1), self.clock())
        in_flight = self.router.take_due(self.clock())
        explicit = frame(2, text="explicit")
        installed = self.action_offer(explicit)
        self.router.install_offer(explicit, installed)
        publication = self.router.complete_offer(
            in_flight, build_inline_offer(in_flight, "late", self.clock(), RouterConfig())
        )
        self.assertEqual(publication.status, "discarded")
        self.assertEqual(self.router.current_offer.proposal_id, installed.proposal_id)

    def test_an_in_flight_ambient_failure_is_discarded_after_install(self):
        self.router.submit(frame(1), self.clock())
        in_flight = self.router.take_due(self.clock())
        explicit = frame(2, text="explicit")
        installed = self.action_offer(explicit)
        self.router.install_offer(explicit, installed)
        publication = self.router.complete_failure(in_flight, "judge: boom")
        self.assertEqual(publication.status, "discarded")
        self.assertEqual([item.status for item in self.published], ["discarded"])
        self.assertEqual(self.router.current_offer.proposal_id, installed.proposal_id)
        later = frame(3, text="later still")
        self.router.submit(later, self.clock())
        taken = self.router.take_due(self.clock())
        self.assertIsNotNone(taken)
        self.assertEqual(taken.revision, 3)

    def test_install_offer_with_a_revision_that_is_not_newer_raises(self):
        self.router.submit(frame(5), self.clock())
        with self.assertRaises(WorkflowError):
            self.router.install_offer(frame(5, text="same"), self.action_offer(frame(5, text="same")))


class ActionOfferTests(unittest.TestCase):
    def test_an_action_offer_carries_its_workflow_effect_and_evidence(self):
        descriptor = WorkflowDescriptor(
            id="book-calendar-link", name="Propose times", description="", execution_method="local", sample_only=True
        )
        preparation = Preparation(
            title="Propose 3 times",
            effect="Writes local holds only.",
            evidence=("Synthetic fixture",),
            missing_inputs=("timetable",),
        )
        offer = build_action_offer(frame(1), descriptor, preparation, Clock()())
        self.assertEqual(offer.workflow_id, "book-calendar-link")
        self.assertTrue(offer.sample_only)
        self.assertEqual(offer.missing_inputs, ("timetable",))
        self.assertIn("local holds", offer.to_dict()["effect"])


class SnapshotValidationTests(unittest.TestCase):
    def test_a_caret_outside_the_supplied_window_is_rejected(self):
        with self.assertRaisesRegex(ContextError, "outside the supplied window"):
            InputSnapshot(
                revision=1,
                captured_at=Clock()(),
                target=target(),
                role="AXTextArea",
                nearby_text="short",
                text_offset=0,
                caret=900,
                selection_start=900,
                selection_end=900,
            )

    def test_text_beyond_the_bound_is_rejected_rather_than_truncated(self):
        with self.assertRaisesRegex(ContextError, "bounded window"):
            InputSnapshot(
                revision=1,
                captured_at=Clock()(),
                target=target(),
                role="AXTextArea",
                nearby_text="x" * 5000,
                text_offset=0,
                caret=0,
                selection_start=0,
                selection_end=0,
            )


if __name__ == "__main__":
    unittest.main()

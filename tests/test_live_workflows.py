"""The two adapters against the shared registry seam.

Nothing here reaches the network: the Google source is driven through an
injected transport, and the snapshot source reads values supplied in the test.
No message is sent, no calendar is written and no browser is started.
"""

import pathlib
import unittest
from datetime import datetime, timedelta, timezone

from live_support import RecordingTransport, frame, freebusy_payload, require_core

require_core()

from caret.live_workflows import actions, flight, meeting  # noqa: E402
from caret.live_workflows.availability import (  # noqa: E402
    AvailabilityError,
    AvailabilitySnapshotSource,
    GoogleFreeBusySource,
    resolve_source,
)
from caret.live_workflows.request import CandidateTime, MeetingRequest, build_request  # noqa: E402
from caret.registry import WorkflowAdapter, WorkflowError, WorkflowRegistry  # noqa: E402

CENTRAL = timezone(timedelta(hours=-5))
NOW = datetime(2026, 9, 20, 12, 0, tzinfo=timezone.utc)
TOKEN = "ya29.test-token-value"
CALENDAR = "person@example.com"

TEXT = (
    "Thanks for the note. Candidate: 2026-09-22T10:00:00-05:00 or "
    "Candidate: 2026-09-22T14:00:00-05:00. Duration: 30 minutes."
)


class Clock:
    def __init__(self, now=NOW):
        self.now = now

    def __call__(self):
        return self.now


class StubSource:
    """An availability source with a fixed answer, or a fixed failure."""

    def __init__(self, intervals=(), live=True, error=None, label="stub availability source"):
        from caret.live_workflows.availability import BusyWindow

        self._window = BusyWindow(tuple(intervals), label, live)
        self._error = error
        self.label = label
        self.calls = []

    def busy(self, start, end):
        self.calls.append((start, end))
        if self._error is not None:
            raise self._error
        return self._window


def busy_at(hour, minutes=60):
    start = datetime(2026, 9, 22, hour, 0, tzinfo=CENTRAL)
    return (start, start + timedelta(minutes=minutes))


def google_source(transport, calendars=(CALENDAR,)):
    return GoogleFreeBusySource(TOKEN, tuple(calendars), transport=transport)


class AvailabilityGateTests(unittest.TestCase):
    def test_no_configured_source_means_unavailable(self):
        adapter = meeting.MeetingDraftWorkflow(environ={})
        report = adapter.availability(frame(TEXT))
        self.assertFalse(report.available)
        self.assertIn("CARET_GOOGLE_CALENDAR_TOKEN", report.reason)
        self.assertIn("CARET_AVAILABILITY_SNAPSHOT", report.reason)

    def test_missing_auth_is_never_read_as_an_empty_calendar(self):
        adapter = meeting.MeetingDraftWorkflow(environ={}, clock=Clock())
        preparation = adapter.prepare(frame(TEXT))
        self.assertTrue(preparation.missing_inputs)
        self.assertNotIn("10:00", preparation.effect)
        result = adapter.execute(frame(TEXT), preparation)
        self.assertEqual(result.status, "needs_input")

    def test_a_secure_field_is_not_read(self):
        adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource())
        self.assertFalse(adapter.availability(frame(TEXT, secure=True)).available)
        self.assertFalse(adapter.availability(frame(TEXT, accessibility=False)).available)

    def test_both_adapters_build_with_no_arguments(self):
        self.assertIsInstance(meeting.MeetingDraftWorkflow(), WorkflowAdapter)
        self.assertIsInstance(flight.SkyvernFlightWorkflow(), WorkflowAdapter)


class GoogleFreeBusyTests(unittest.TestCase):
    def setUp(self):
        self.window = (
            datetime(2026, 9, 22, 12, 0, tzinfo=timezone.utc),
            datetime(2026, 9, 23, 12, 0, tzinfo=timezone.utc),
        )

    def _payload(self, calendars):
        return freebusy_payload(self.window[0].isoformat(), self.window[1].isoformat(), calendars)

    def test_a_busy_interval_is_read_from_the_reply(self):
        transport = RecordingTransport(
            payload=self._payload(
                {CALENDAR: {"busy": [{"start": "2026-09-22T15:00:00Z", "end": "2026-09-22T16:00:00Z"}]}}
            )
        )
        window = google_source(transport).busy(*self.window)
        self.assertTrue(window.live)
        self.assertEqual(len(window.intervals), 1)
        call = transport.calls[0]
        self.assertEqual(call["url"], "https://www.googleapis.com/calendar/v3/freeBusy")
        self.assertEqual(call["body"]["items"], [{"id": CALENDAR}])
        self.assertEqual(call["body"]["timeMin"], self.window[0].isoformat())
        self.assertGreater(call["timeout"], 0)

    def test_an_http_failure_is_an_error_not_an_empty_busy_list(self):
        for status in (401, 403, 429, 500):
            with self.subTest(status=status):
                source = google_source(RecordingTransport(status=status))
                with self.assertRaisesRegex(AvailabilityError, f"HTTP {status}"):
                    source.busy(*self.window)

    def test_a_transport_failure_is_an_error(self):
        source = google_source(RecordingTransport(error=TimeoutError("timed out")))
        with self.assertRaises(Exception) as caught:
            source.busy(*self.window)
        self.assertNotIn(TOKEN, str(caught.exception))

    def test_a_body_that_is_not_json_is_an_error(self):
        source = google_source(RecordingTransport(body=b"<html>nope</html>"))
        with self.assertRaisesRegex(AvailabilityError, "not JSON"):
            source.busy(*self.window)

    def test_a_narrower_answer_than_asked_for_is_an_error(self):
        narrow = freebusy_payload(
            self.window[0].isoformat(),
            (self.window[1] - timedelta(hours=6)).isoformat(),
            {CALENDAR: {"busy": []}},
        )
        with self.assertRaisesRegex(AvailabilityError, "narrower"):
            google_source(RecordingTransport(payload=narrow)).busy(*self.window)

    def test_an_omitted_calendar_is_an_error(self):
        payload = self._payload({"other@example.com": {"busy": []}})
        with self.assertRaisesRegex(AvailabilityError, "omitted"):
            google_source(RecordingTransport(payload=payload)).busy(*self.window)

    def test_a_per_calendar_error_is_an_error(self):
        payload = self._payload({CALENDAR: {"errors": [{"domain": "global", "reason": "notFound"}], "busy": []}})
        with self.assertRaises(AvailabilityError):
            google_source(RecordingTransport(payload=payload)).busy(*self.window)

    def test_an_omitted_busy_list_is_an_error(self):
        payload = self._payload({CALENDAR: {}})
        with self.assertRaisesRegex(AvailabilityError, "busy"):
            google_source(RecordingTransport(payload=payload)).busy(*self.window)

    def test_a_malformed_busy_entry_is_an_error(self):
        for entry in ({"start": "2026-09-22T15:00:00Z"}, {"start": "nope", "end": "nope"},
                      {"start": "2026-09-22T16:00:00Z", "end": "2026-09-22T15:00:00Z"}):
            with self.subTest(entry=entry):
                payload = self._payload({CALENDAR: {"busy": [entry]}})
                with self.assertRaises(AvailabilityError):
                    google_source(RecordingTransport(payload=payload)).busy(*self.window)

    def test_no_failure_message_carries_the_token_or_the_response(self):
        secret_body = b'{"timeMin": "bad", "note": "SECRET-RESPONSE-BODY"}'
        source = google_source(RecordingTransport(body=secret_body))
        with self.assertRaises(AvailabilityError) as caught:
            source.busy(*self.window)
        message = str(caught.exception)
        self.assertNotIn(TOKEN, message)
        self.assertNotIn("SECRET-RESPONSE-BODY", message)
        self.assertNotIn(TOKEN, source.label)
        self.assertNotIn(CALENDAR, source.label)


class SnapshotSourceTests(unittest.TestCase):
    def _source(self, clock, captured_at=None, covered=None):
        covered = covered or (
            datetime(2026, 9, 20, 0, 0, tzinfo=timezone.utc),
            datetime(2026, 9, 25, 0, 0, tzinfo=timezone.utc),
        )
        return AvailabilitySnapshotSource(
            busy_intervals=(busy_at(10),),
            covered_start=covered[0],
            covered_end=covered[1],
            captured_at=captured_at or NOW,
            provenance="exported calendar file",
            max_age_seconds=3600,
            clock=clock,
        )

    def test_the_label_says_it_is_a_snapshot(self):
        source = self._source(Clock())
        self.assertIn("snapshot", source.label)
        self.assertIn("not a live calendar read", source.label)
        self.assertFalse(source.busy(*_window()).live)

    def test_an_uncovered_window_is_refused(self):
        source = self._source(
            Clock(),
            covered=(
                datetime(2026, 9, 20, 0, 0, tzinfo=timezone.utc),
                datetime(2026, 9, 21, 0, 0, tzinfo=timezone.utc),
            ),
        )
        with self.assertRaisesRegex(AvailabilityError, "does not cover"):
            source.busy(*_window())

    def test_a_stale_snapshot_is_refused(self):
        clock = Clock(NOW + timedelta(hours=5))
        with self.assertRaisesRegex(AvailabilityError, "old"):
            self._source(clock).busy(*_window())


def _window():
    return (
        datetime(2026, 9, 22, 12, 0, tzinfo=timezone.utc),
        datetime(2026, 9, 22, 21, 0, tzinfo=timezone.utc),
    )


class MeetingPrepareTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.source = StubSource()
        self.adapter = meeting.MeetingDraftWorkflow(availability_source=self.source, clock=self.clock)

    def test_the_draft_comes_from_the_text_in_the_frame(self):
        preparation = self.adapter.prepare(frame(TEXT))
        self.assertEqual(preparation.missing_inputs, ())
        self.assertIn("2026-09-22T10:00:00-05:00", preparation.payload["draft"])
        self.assertIn("2026-09-22T14:00:00-05:00", preparation.payload["draft"])
        other = self.adapter.prepare(
            frame("Candidate: 2026-09-23T09:00:00-05:00. Duration: 30 minutes.", element_revision="v8")
        )
        self.assertIn("2026-09-23T09:00:00-05:00", other.payload["draft"])
        self.assertNotIn("2026-09-22", other.payload["draft"])

    def test_every_option_cites_its_excerpt_and_its_availability_source(self):
        preparation = self.adapter.prepare(frame(TEXT))
        option_lines = [line for line in preparation.evidence if "read from" in line]
        self.assertEqual(len(option_lines), len(preparation.payload["options"]))
        for line in option_lines:
            self.assertIn("Candidate: 2026-09-22T10:00:00-05:00", line)
            self.assertIn("stub availability source", line)
        self.assertTrue(any("duration from" in line for line in preparation.evidence))

    def test_a_busy_interval_removes_its_candidate(self):
        adapter = meeting.MeetingDraftWorkflow(
            availability_source=StubSource(intervals=(busy_at(10),)), clock=self.clock
        )
        preparation = adapter.prepare(frame(TEXT))
        draft = preparation.payload["draft"]
        self.assertNotIn("T10:00:00", draft)
        self.assertIn("T14:00:00", draft)
        self.assertTrue(any("dropped as busy" in line for line in preparation.evidence))

    def test_every_candidate_busy_means_no_draft(self):
        adapter = meeting.MeetingDraftWorkflow(
            availability_source=StubSource(intervals=(busy_at(9, 480),)), clock=self.clock
        )
        preparation = adapter.prepare(frame(TEXT))
        self.assertTrue(preparation.missing_inputs)
        self.assertEqual(preparation.payload, {})

    def test_a_failed_source_does_not_become_an_empty_busy_list(self):
        adapter = meeting.MeetingDraftWorkflow(
            availability_source=StubSource(error=AvailabilityError("HTTP 500")), clock=self.clock
        )
        preparation = adapter.prepare(frame(TEXT))
        self.assertTrue(any("availability source" in item for item in preparation.missing_inputs))
        self.assertEqual(preparation.payload, {})
        self.assertEqual(adapter.execute(frame(TEXT), preparation).status, "needs_input")

    def test_ambiguous_text_proposes_nothing(self):
        preparation = self.adapter.prepare(frame("Can we meet tomorrow afternoon? Duration: 30 minutes."))
        self.assertTrue(preparation.missing_inputs)
        self.assertEqual(self.source.calls, [])
        self.assertTrue(any("tomorrow" in line for line in preparation.evidence))

    def test_the_draft_claims_no_venue_travel_or_send(self):
        preparation = self.adapter.prepare(frame(TEXT))
        draft = preparation.payload["draft"].lower()
        for invented in ("address", "office", "travel", "drive", "flight", "sent", "invite"):
            self.assertNotIn(invented, draft)
        self.assertIn("draft", preparation.effect.lower())

    def test_an_unsourced_caller_correction_is_refused(self):
        request = MeetingRequest(
            candidates=(
                CandidateTime(
                    id="c1",
                    start=datetime(2026, 9, 22, 16, 0, tzinfo=CENTRAL),
                    excerpt="corrected by the user in the review pane",
                    origin="caller correction",
                ),
            ),
            duration_minutes=30,
            duration_source="caller correction",
        )
        preparation = self.adapter.prepare_request(frame(TEXT), request)
        self.assertTrue(preparation.missing_inputs)
        self.assertNotIn("draft", preparation.payload)

    def test_candidates_spread_past_the_window_bound_are_refused(self):
        text = ("Candidate: 2026-09-22T10:00:00-05:00 Candidate: 2026-11-22T10:00:00-05:00 "
                "Duration: 30 minutes")
        preparation = self.adapter.prepare(frame(text))
        self.assertTrue(any("within 14 days" in item for item in preparation.missing_inputs))
        self.assertEqual(self.source.calls, [])

    def test_a_past_candidate_is_dropped(self):
        clock = Clock(datetime(2026, 9, 22, 16, 0, tzinfo=timezone.utc))
        adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=clock)
        preparation = adapter.prepare(frame(TEXT))
        self.assertNotIn("T10:00:00", preparation.payload["draft"])
        self.assertTrue(any("already past" in line for line in preparation.evidence))

    def test_preparing_asks_the_source_once_and_writes_nothing(self):
        transport = RecordingTransport(
            payload=freebusy_payload(
                "2026-09-22T14:00:00+00:00",
                "2026-09-22T20:00:00+00:00",
                {CALENDAR: {"busy": []}},
            )
        )
        adapter = meeting.MeetingDraftWorkflow(
            availability_source=google_source(transport), clock=self.clock
        )
        preparation = adapter.prepare(frame(TEXT))
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(transport.calls[0]["url"], "https://www.googleapis.com/calendar/v3/freeBusy")
        self.assertEqual(preparation.payload["availability_live"], True)
        adapter.execute(frame(TEXT), preparation)
        self.assertEqual(len(transport.calls), 1)


class MeetingExecuteTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=self.clock)
        self.frame = frame(TEXT)
        self.preparation = self.adapter.prepare(self.frame)

    def test_execute_returns_the_bound_draft_and_claims_no_other_effect(self):
        result = self.adapter.execute(self.frame, self.preparation)
        self.assertEqual(result.status, "completed")
        self.assertEqual(result.data["draft"], self.preparation.payload["draft"])
        self.assertFalse(result.data["sent"])
        self.assertFalse(result.data["calendar_event_created"])
        self.assertEqual(len(result.effects), 1)
        self.assertIn("No message was sent", result.effects[0])
        # Swift preserves only status, summary and evidence from this result.
        self.assertIn(meeting.NO_EFFECT, result.to_dict()["evidence"])

    def test_the_serialized_preparation_shows_the_exact_draft(self):
        self.assertIn(self.preparation.payload["draft"], self.preparation.to_dict()["effect"])

    def test_a_new_preparation_releases_the_old_draft(self):
        replacement = self.adapter.prepare(self.frame)
        self.assertEqual(len(self.adapter._pending), 1)
        self.assertEqual(self.adapter.execute(self.frame, self.preparation).status, "failed")
        self.assertEqual(self.adapter.execute(self.frame, replacement).status, "completed")

    def test_a_second_acceptance_fails(self):
        self.assertEqual(self.adapter.execute(self.frame, self.preparation).status, "completed")
        repeated = self.adapter.execute(self.frame, self.preparation)
        self.assertEqual(repeated.status, "failed")
        self.assertEqual(repeated.data, {})

    def test_cancelling_leaves_nothing_to_execute(self):
        cancelled = self.adapter.cancel(self.preparation)
        self.assertEqual(cancelled.status, "cancelled")
        self.assertEqual(cancelled.effects, ())
        self.assertEqual(self.adapter.execute(self.frame, self.preparation).status, "failed")

    def test_a_tampered_draft_fails(self):
        from caret.registry import Preparation

        tampered = Preparation(
            title=self.preparation.title,
            effect=self.preparation.effect,
            evidence=self.preparation.evidence,
            payload={**self.preparation.payload, "draft": "Meet me at 03:00 at my address."},
        )
        result = self.adapter.execute(self.frame, tampered)
        self.assertEqual(result.status, "failed")
        self.assertIn("does not match", result.summary)

    def test_changed_text_fails(self):
        moved = frame(TEXT.replace("10:00:00", "11:00:00"))
        result = self.adapter.execute(moved, self.preparation)
        self.assertEqual(result.status, "failed")
        self.assertIn("changed", result.summary)

    def test_a_different_field_fails(self):
        other = frame(TEXT, element_revision="v9")
        self.assertEqual(self.adapter.execute(other, self.preparation).status, "failed")

    def test_a_stale_preparation_fails(self):
        self.clock.now = NOW + timedelta(minutes=30)
        result = self.adapter.execute(self.frame, self.preparation)
        self.assertEqual(result.status, "failed")
        self.assertIn("limit", result.summary)

    def test_a_time_that_has_passed_fails(self):
        adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=self.clock)
        preparation = adapter.prepare(self.frame)
        self.clock.now = datetime(2026, 9, 23, 0, 0, tzinfo=timezone.utc)
        result = adapter.execute(self.frame, preparation)
        self.assertEqual(result.status, "failed")


class AcceptanceBindingTests(unittest.TestCase):
    """What acceptance rechecks that the frame signature cannot cover."""

    def setUp(self):
        self.clock = Clock()
        self.adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=self.clock)
        self.frame = frame(TEXT)
        self.preparation = self.adapter.prepare(self.frame)

    def test_a_revoked_permission_or_suppressed_field_refuses_acceptance(self):
        # ContextFrame.signature() covers the text and the target, not these, so
        # each has to be rechecked in its own right.
        cases = {
            "accessibility revoked": frame(TEXT, accessibility=False),
            "field now secure": frame(TEXT, secure=True),
        }
        for name, live in cases.items():
            with self.subTest(case=name):
                adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=Clock())
                preparation = adapter.prepare(self.frame)
                self.assertEqual(live.signature(), self.frame.signature())
                result = adapter.execute(live, preparation)
                self.assertEqual(result.status, "failed")
                self.assertEqual(result.data, {})

    def test_an_excluded_app_or_composing_input_method_refuses_acceptance(self):
        from caret.context import ContextFrame
        from dataclasses import replace

        for flag in ("app_excluded", "ime_composing"):
            with self.subTest(flag=flag):
                adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=Clock())
                preparation = adapter.prepare(self.frame)
                live = ContextFrame(
                    snapshot=replace(self.frame.snapshot, **{flag: True}),
                    permissions=self.frame.permissions,
                )
                self.assertEqual(live.signature(), self.frame.signature())
                self.assertEqual(adapter.execute(live, preparation).status, "failed")

    def test_tampering_with_any_reviewed_field_fails(self):
        from caret.registry import Preparation

        payload = self.preparation.payload
        variants = {
            "options": {**payload, "options": [{**payload["options"][0], "start": "2026-09-22T03:00:00-05:00"}]},
            "duration": {**payload, "duration_minutes": 240},
            "source": {**payload, "availability_source": "Google Calendar free/busy"},
            "liveness": {**payload, "availability_live": not payload["availability_live"]},
        }
        for name, altered in variants.items():
            with self.subTest(field=name):
                adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=Clock())
                preparation = adapter.prepare(self.frame)
                tampered = Preparation(
                    title=preparation.title,
                    effect=preparation.effect,
                    evidence=preparation.evidence,
                    payload={**altered, "token": preparation.payload["token"]},
                )
                result = adapter.execute(self.frame, tampered)
                self.assertEqual(result.status, "failed")
                self.assertIn("does not match", result.summary)

    def test_tampering_with_the_evidence_fails(self):
        from caret.registry import Preparation

        tampered = Preparation(
            title=self.preparation.title,
            effect=self.preparation.effect,
            evidence=self.preparation.evidence + ("availability from Google Calendar free/busy",),
            payload=self.preparation.payload,
        )
        result = self.adapter.execute(self.frame, tampered)
        self.assertEqual(result.status, "failed")
        self.assertIn("does not match", result.summary)

    def test_the_returned_result_does_not_alias_the_proposal(self):
        result = self.adapter.execute(self.frame, self.preparation)
        self.assertEqual(result.status, "completed")
        self.assertIsNot(result.data["options"], self.preparation.payload["options"])
        self.preparation.payload["options"][0]["start"] = "2026-09-22T03:00:00-05:00"
        self.assertNotEqual(result.data["options"][0]["start"], "2026-09-22T03:00:00-05:00")


class SnapshotValidationTests(unittest.TestCase):
    """A snapshot that cannot be trusted is refused when it is built."""

    def _write(self, payload):
        import json
        import tempfile

        directory = tempfile.mkdtemp()
        path = pathlib.Path(directory) / "availability.json"
        path.write_text(json.dumps(payload))
        return path

    def _payload(self, **overrides):
        return {
            "covered_start": "2026-09-20T00:00:00+00:00",
            "covered_end": "2026-09-25T00:00:00+00:00",
            "captured_at": "2026-09-20T11:00:00+00:00",
            "provenance": "exported calendar file",
            "busy": [],
            **overrides,
        }

    def test_an_omitted_busy_list_is_refused_rather_than_read_as_free(self):
        payload = self._payload()
        del payload["busy"]
        with self.assertRaisesRegex(AvailabilityError, "busy list explicitly"):
            AvailabilitySnapshotSource.from_file(self._write(payload))
        with self.assertRaisesRegex(AvailabilityError, "busy list explicitly"):
            AvailabilitySnapshotSource.from_file(self._write(self._payload(busy="none")))

    def test_a_malformed_or_naive_busy_entry_is_refused(self):
        for busy in (
            [{"start": "2026-09-22T10:00:00+00:00"}],
            [{"start": "2026-09-22T10:00:00", "end": "2026-09-22T11:00:00"}],
            [{"start": "2026-09-22T11:00:00+00:00", "end": "2026-09-22T10:00:00+00:00"}],
        ):
            with self.subTest(busy=busy):
                with self.assertRaises(AvailabilityError):
                    AvailabilitySnapshotSource.from_file(self._write(self._payload(busy=busy)))

    def test_a_naive_capture_time_is_refused(self):
        with self.assertRaisesRegex(AvailabilityError, "timezone offset"):
            AvailabilitySnapshotSource.from_file(self._write(self._payload(captured_at="2026-09-20T11:00:00")))

    def test_a_capture_from_the_future_is_refused(self):
        with self.assertRaisesRegex(AvailabilityError, "future"):
            AvailabilitySnapshotSource(
                busy_intervals=(),
                covered_start=datetime(2026, 9, 20, tzinfo=timezone.utc),
                covered_end=datetime(2026, 9, 25, tzinfo=timezone.utc),
                captured_at=NOW + timedelta(hours=1),
                provenance="exported calendar file",
                clock=Clock(),
            )

    def test_a_nonpositive_maximum_age_is_refused(self):
        for age in (0, -60):
            with self.subTest(max_age_seconds=age):
                with self.assertRaisesRegex(AvailabilityError, "positive"):
                    AvailabilitySnapshotSource(
                        busy_intervals=(),
                        covered_start=datetime(2026, 9, 20, tzinfo=timezone.utc),
                        covered_end=datetime(2026, 9, 25, tzinfo=timezone.utc),
                        captured_at=NOW,
                        provenance="exported calendar file",
                        max_age_seconds=age,
                        clock=Clock(),
                    )

    def test_a_programmatic_interval_must_be_an_offset_aware_pair(self):
        for intervals in (
            ((datetime(2026, 9, 22, 10), datetime(2026, 9, 22, 11)),),
            ((datetime(2026, 9, 22, 11, tzinfo=timezone.utc), datetime(2026, 9, 22, 10, tzinfo=timezone.utc)),),
            (("2026-09-22T10:00:00+00:00", "2026-09-22T11:00:00+00:00"),),
        ):
            with self.subTest(intervals=intervals):
                with self.assertRaises(AvailabilityError):
                    AvailabilitySnapshotSource(
                        busy_intervals=intervals,
                        covered_start=datetime(2026, 9, 20, tzinfo=timezone.utc),
                        covered_end=datetime(2026, 9, 25, tzinfo=timezone.utc),
                        captured_at=NOW,
                        provenance="exported calendar file",
                        clock=Clock(),
                    )


class FlightTests(unittest.TestCase):
    def setUp(self):
        self.adapter = flight.SkyvernFlightWorkflow()

    def test_it_is_unavailable_with_the_reason(self):
        report = self.adapter.availability(frame("Find me a flight to Dallas on Friday"))
        self.assertFalse(report.available)
        self.assertIn("Skyvern", report.reason)
        self.assertIn("allowlist", report.reason)
        self.assertIn("not an execution guard", report.reason)

    def test_it_refuses_to_prepare_or_execute(self):
        with self.assertRaises(WorkflowError):
            self.adapter.prepare(frame("Find me a flight"))
        with self.assertRaises(WorkflowError):
            self.adapter.execute(frame("Find me a flight"), None)


class RegistryTests(unittest.TestCase):
    def test_only_the_meeting_workflow_is_offered_to_the_judge(self):
        registry = WorkflowRegistry()
        adapter = meeting.MeetingDraftWorkflow(availability_source=StubSource(), clock=Clock())
        registry.register(adapter)
        registry.register(flight.SkyvernFlightWorkflow())
        context = frame(TEXT)
        self.assertEqual([choice.id for choice in registry.choices(context)], ["book-calendar-link"])
        catalog = {row["id"]: row for row in registry.catalog(context)}
        self.assertEqual(catalog["book-calendar-link"]["execution_method"], "draft_only")
        self.assertFalse(catalog["book-calendar-link"]["sample_only"])
        self.assertFalse(catalog["book-flight"]["availability"]["available"])

    def test_the_action_table_matches_the_registered_ids(self):
        self.assertEqual(actions.workflow_for_action("book-calendar-link"), "book-calendar-link")
        self.assertEqual(actions.workflow_for_action("book-flight"), "book-flight")
        self.assertIsNone(actions.workflow_for_action("summarize"))
        with self.assertRaises(KeyError):
            actions.workflow_for_action("book-hotel")
        registry = WorkflowRegistry()
        for adapter in actions.adapters():
            registry.register(adapter)
        self.assertEqual(
            sorted(item.descriptor.id for item in registry.all()),
            ["book-calendar-link", "book-flight"],
        )


class EnvironmentTests(unittest.TestCase):
    def test_resolve_source_reports_what_is_unset(self):
        source, reason = resolve_source({})
        self.assertIsNone(source)
        self.assertIn("CARET_GOOGLE_CALENDAR_IDS", reason)

    def test_google_wins_when_both_are_configured(self):
        source, reason = resolve_source(
            {
                "CARET_GOOGLE_CALENDAR_TOKEN": TOKEN,
                "CARET_GOOGLE_CALENDAR_IDS": CALENDAR,
                "CARET_AVAILABILITY_SNAPSHOT": "/nonexistent.json",
            }
        )
        self.assertIsInstance(source, GoogleFreeBusySource)
        self.assertEqual(reason, "")

    def test_a_request_built_from_the_frame_reads_that_frame(self):
        request = build_request(frame(TEXT).snapshot.nearby_text)
        self.assertEqual(len(request.candidates), 2)


if __name__ == "__main__":
    unittest.main()

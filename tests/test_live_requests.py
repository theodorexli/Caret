"""What the adapter will and will not read out of the user's own text.

These run everywhere: reading text needs no registry and no network.
"""

import unittest
from datetime import datetime, timedelta, timezone

from caret.live_workflows.request import (
    MAX_CANDIDATES,
    CandidateTime,
    MeetingRequest,
    RequestError,
    build_request,
)

CENTRAL = timezone(timedelta(hours=-5))


class ReadingTests(unittest.TestCase):
    def test_marked_times_and_duration_are_read_from_the_text(self):
        request = build_request(
            "Either Candidate: 2026-09-22T10:00:00-05:00 or "
            "Candidate: 2026-09-22T14:00:00-05:00 works. Duration: 45 minutes."
        )
        self.assertTrue(request.ready)
        self.assertEqual(
            [candidate.start for candidate in request.candidates],
            [
                datetime(2026, 9, 22, 10, 0, tzinfo=CENTRAL),
                datetime(2026, 9, 22, 14, 0, tzinfo=CENTRAL),
            ],
        )
        self.assertEqual(request.duration_minutes, 45)
        self.assertIn("Duration: 45 minutes", request.duration_source)
        for candidate in request.candidates:
            self.assertIn("Candidate:", candidate.excerpt)

    def test_different_text_yields_a_different_request(self):
        first = build_request("Candidate: 2026-09-22T10:00:00-05:00 Duration: 30 minutes")
        second = build_request("Candidate: 2026-09-23T16:00:00+01:00 Duration: 1 hour")
        self.assertNotEqual(first.starts(), second.starts())
        self.assertEqual(second.duration_minutes, 60)

    def test_an_unmarked_timestamp_is_reported_not_proposed(self):
        request = build_request(
            "I cannot make 2026-09-22T10:00:00-05:00. Duration: 30 minutes"
        )
        self.assertEqual(request.candidates, ())
        self.assertFalse(request.ready)
        self.assertTrue(
            any("not marked as a candidate" in item for item in request.ambiguous), request.ambiguous
        )

    def test_relative_times_are_reported_not_resolved(self):
        request = build_request("Can we meet tomorrow afternoon? Duration: 30 minutes")
        self.assertFalse(request.ready)
        self.assertEqual(request.candidates, ())
        self.assertTrue(any("candidate time" in item for item in request.missing))
        self.assertTrue(any("tomorrow" in item for item in request.ambiguous))

    def test_a_clock_time_without_a_date_is_reported(self):
        request = build_request("How about 3pm? Duration: 30 minutes")
        self.assertEqual(request.candidates, ())
        self.assertTrue(any("3pm" in item for item in request.ambiguous))

    def test_a_timestamp_without_an_offset_is_reported_not_assumed(self):
        request = build_request("Candidate: 2026-09-22T10:00:00 Duration: 30 minutes")
        self.assertEqual(request.candidates, ())
        self.assertTrue(
            any("no UTC offset" in item for item in request.ambiguous), request.ambiguous
        )

    def test_a_positive_offset_without_seconds_is_unambiguous(self):
        request = build_request("Candidate: 2026-09-22T10:00+02:00 Duration: 30 minutes")
        self.assertEqual(len(request.candidates), 1)
        self.assertEqual(request.candidates[0].start.utcoffset(), timedelta(hours=2))

    def test_utc_is_accepted_as_z(self):
        request = build_request("Candidate: 2026-09-22T10:00:00Z Duration: 30 minutes")
        self.assertEqual(request.candidates[0].start.utcoffset(), timedelta(0))

    def test_two_different_durations_are_not_averaged(self):
        request = build_request(
            "Candidate: 2026-09-22T10:00:00-05:00 Duration: 30 minutes Duration: 1 hour"
        )
        self.assertIsNone(request.duration_minutes)
        self.assertFalse(request.ready)
        self.assertTrue(any("30 minutes, 60 minutes" in item for item in request.missing))

    def test_a_missing_duration_is_named(self):
        request = build_request("Candidate: 2026-09-22T10:00:00-05:00 works")
        self.assertFalse(request.ready)
        self.assertTrue(any("duration" in item for item in request.missing))

    def test_an_out_of_range_duration_is_refused(self):
        request = build_request("Candidate: 2026-09-22T10:00:00-05:00 Duration: 12 hours")
        self.assertIsNone(request.duration_minutes)
        self.assertTrue(any("between 5 and 480" in item for item in request.missing))

    def test_candidate_count_is_bounded(self):
        text = " ".join(
            f"Candidate: 2026-09-22T{hour:02d}:00:00-05:00" for hour in range(1, MAX_CANDIDATES + 4)
        )
        request = build_request(text + " Duration: 30 minutes")
        self.assertEqual(len(request.candidates), MAX_CANDIDATES)
        self.assertTrue(any("candidate bound" in item for item in request.ambiguous))


class CorrectionTests(unittest.TestCase):
    def test_a_corrected_candidate_must_carry_its_source(self):
        with self.assertRaisesRegex(RequestError, "source excerpt"):
            CandidateTime(id="c1", start=datetime.now(timezone.utc), excerpt="  ", origin="user")
        with self.assertRaisesRegex(RequestError, "origin"):
            CandidateTime(id="c1", start=datetime.now(timezone.utc), excerpt="10:00", origin="")

    def test_a_naive_correction_is_refused(self):
        with self.assertRaisesRegex(RequestError, "timezone-aware"):
            CandidateTime(id="c1", start=datetime(2026, 9, 22, 10), excerpt="10:00", origin="user")

    def test_a_duration_needs_a_source(self):
        candidate = CandidateTime(
            id="c1",
            start=datetime(2026, 9, 22, 10, tzinfo=CENTRAL),
            excerpt="Candidate: 2026-09-22T10:00:00-05:00",
            origin="caller correction",
        )
        with self.assertRaisesRegex(RequestError, "source"):
            MeetingRequest(candidates=(candidate,), duration_minutes=30)
        request = MeetingRequest(
            candidates=(candidate,), duration_minutes=30, duration_source="caller correction"
        )
        self.assertTrue(request.ready)

    def test_duplicate_candidate_ids_are_refused(self):
        candidate = CandidateTime(
            id="c1",
            start=datetime(2026, 9, 22, 10, tzinfo=CENTRAL),
            excerpt="text",
            origin="caller correction",
        )
        with self.assertRaisesRegex(RequestError, "unique"):
            MeetingRequest(candidates=(candidate, candidate))

    def test_buffers_must_be_nonnegative_integers(self):
        with self.assertRaisesRegex(RequestError, "nonnegative"):
            MeetingRequest(buffer_before_minutes=-1)


if __name__ == "__main__":
    unittest.main()

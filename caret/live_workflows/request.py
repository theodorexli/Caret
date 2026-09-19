"""The typed request the meeting adapter schedules from.

:mod:`extraction` recognizes the marked literals. This layer decides which of
them may become a proposed time, attaches an identity and a source excerpt to
each one, and names in plain words whatever is still missing. A caller that
disagrees with the reading constructs a :class:`MeetingRequest` directly, but
the types make the correction carry its own evidence: a candidate without an
excerpt and an origin cannot be built at all.

Whatever the reader did not accept is reported rather than dropped. An ISO
timestamp with no ``Candidate:`` marker, a date-time with no UTC offset, a bare
wall clock and a relative phrase each come back as a line saying what is wrong
with it, so the user is told the grammar instead of being told nothing was
found.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime

from .extraction import Mention, read_text

MAX_CANDIDATES = 12
"""Bounds the free/busy request and the evidence list. The caller's window is
already bounded by the core; this bounds what one draft may propose from it."""

MAX_MENTIONS = 6
MIN_DURATION_MINUTES = 5
MAX_DURATION_MINUTES = 480

_NAIVE = re.compile(r"(?<![\w:])\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?(?![\d:])")
_CLOCK_ONLY = re.compile(r"(?<![\w:])\d{1,2}(?::\d{2})?\s*(?:am|pm)\b|(?<![\w:.])\d{1,2}:\d{2}(?![\d:])", re.IGNORECASE)


class RequestError(ValueError):
    """A meeting request was built without the evidence it has to carry."""


@dataclass(frozen=True)
class CandidateTime:
    """One start that may be proposed, and the words it was read from."""

    id: str
    start: datetime
    excerpt: str
    origin: str

    def __post_init__(self) -> None:
        if not isinstance(self.id, str) or not self.id.strip():
            raise RequestError("Each candidate needs a nonempty string ID")
        if not isinstance(self.start, datetime) or self.start.tzinfo is None:
            raise RequestError(f"Candidate '{self.id}' needs a timezone-aware start")
        if not self.excerpt.strip():
            raise RequestError(f"Candidate '{self.id}' needs the source excerpt it was read from")
        if not self.origin.strip():
            raise RequestError(f"Candidate '{self.id}' needs an origin naming where its excerpt came from")


@dataclass(frozen=True)
class MeetingRequest:
    """What may be scheduled, what was refused, and what is still needed."""

    candidates: tuple[CandidateTime, ...] = ()
    duration_minutes: int | None = None
    duration_source: str = ""
    ambiguous: tuple[str, ...] = ()
    missing: tuple[str, ...] = ()
    buffer_before_minutes: int = 0
    buffer_after_minutes: int = 0

    def __post_init__(self) -> None:
        if len(self.candidates) > MAX_CANDIDATES:
            raise RequestError(f"One request proposes at most {MAX_CANDIDATES} candidate times")
        ids = [candidate.id for candidate in self.candidates]
        if len(set(ids)) != len(ids):
            raise RequestError("Candidate IDs must be unique within one request")
        if self.duration_minutes is not None:
            if type(self.duration_minutes) is not int:
                raise RequestError("duration_minutes must be an integer")
            if not MIN_DURATION_MINUTES <= self.duration_minutes <= MAX_DURATION_MINUTES:
                raise RequestError(
                    f"duration_minutes must be between {MIN_DURATION_MINUTES} and {MAX_DURATION_MINUTES}"
                )
            if not self.duration_source.strip():
                raise RequestError("A duration needs a source naming where it came from")
        for name in ("buffer_before_minutes", "buffer_after_minutes"):
            value = getattr(self, name)
            if type(value) is not int or value < 0:
                raise RequestError(f"{name} must be a nonnegative integer")

    @property
    def ready(self) -> bool:
        return not self.missing and bool(self.candidates) and self.duration_minutes is not None

    def starts(self) -> tuple[datetime, ...]:
        return tuple(candidate.start for candidate in self.candidates)


def _dedupe(values: list[str]) -> tuple[str, ...]:
    return tuple(dict.fromkeys(values))[:MAX_MENTIONS]


def _mask(text: str, spans: list[tuple[int, int]]) -> str:
    masked = list(text)
    for lower, upper in spans:
        for index in range(lower, upper):
            masked[index] = " "
    return "".join(masked)


def build_request(
    text: str,
    origin: str = "the focused field",
    buffer_before_minutes: int = 0,
    buffer_after_minutes: int = 0,
) -> MeetingRequest:
    """Read ``text`` into a request. ``origin`` names the source in evidence."""
    reading = read_text(text, source=origin)
    candidates: list[CandidateTime] = []
    ambiguous: list[str] = []
    spans: list[tuple[int, int]] = []
    for mention in reading.candidates:
        spans.append(mention.span)
        if len(candidates) >= MAX_CANDIDATES:
            ambiguous.append(f"\"{mention.text}\" is past the {MAX_CANDIDATES} candidate bound")
            continue
        candidates.append(
            CandidateTime(
                id=f"c{len(candidates) + 1}",
                start=mention.start,
                excerpt=mention.excerpt,
                origin=mention.source,
            )
        )

    remainder = _mask(text, spans + [mention.span for mention in reading.unmarked_times])
    for mention in reading.unmarked_times:
        ambiguous.append(
            f"\"{mention.text}\" is not marked as a candidate; write Candidate: {mention.text}"
        )
    for match in _NAIVE.finditer(remainder):
        ambiguous.append(f"\"{match.group(0)}\" has no UTC offset")
    for match in _CLOCK_ONLY.finditer(remainder):
        ambiguous.append(f"\"{match.group(0).strip()}\" has no date or UTC offset")
    for mention in reading.relative_mentions:
        ambiguous.append(f"\"{mention.text}\" is a relative time this adapter does not resolve")

    missing: list[str] = []
    if not candidates:
        missing.append(
            "at least one marked candidate time, as in "
            "Candidate: 2026-09-22T10:00:00-05:00"
        )
    duration = reading.duration_minutes
    duration_source = ""
    if reading.conflicting_durations:
        listed = ", ".join(f"{value} minutes" for value in reading.conflicting_durations)
        missing.append(f"one meeting duration; the text names {listed}")
        duration = None
    elif duration is None:
        missing.append("a marked duration, as in \"Duration: 45 minutes\" or \"Duration: 1 hour\"")
    elif not MIN_DURATION_MINUTES <= duration <= MAX_DURATION_MINUTES:
        missing.append(
            f"a duration between {MIN_DURATION_MINUTES} and {MAX_DURATION_MINUTES} minutes; "
            f"the text names {duration}"
        )
        duration = None
    elif isinstance(reading.duration_mention, Mention):
        duration_source = f"{origin}: \"{reading.duration_mention.excerpt}\""

    return MeetingRequest(
        candidates=tuple(candidates),
        duration_minutes=duration,
        duration_source=duration_source,
        ambiguous=_dedupe(ambiguous),
        missing=tuple(missing),
        buffer_before_minutes=buffer_before_minutes,
        buffer_after_minutes=buffer_after_minutes,
    )


__all__ = ["MAX_CANDIDATES", "CandidateTime", "MeetingRequest", "RequestError", "build_request"]

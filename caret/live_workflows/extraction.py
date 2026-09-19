"""Recognize the marked candidate times in the caller's own text.

The grammar is deliberately tiny, and every part of it is explicit:

* ``Candidate: 2026-09-22T11:00:00-05:00`` proposes one time. The marker word,
  the ``T`` separator and a UTC offset (or ``Z``) are all required.
* ``Duration: 30 minutes`` states the meeting length once. Minutes and hours
  are the accepted units.

Nothing else in the text becomes a proposal. That is the point of the marker:
free-running date scraping cannot tell "meet at 2026-09-22T11:00:00-05:00" from
"I cannot meet at 2026-09-22T11:00:00-05:00", or from a time quoted out of an
older message below the reply, and offering a time the writer ruled out is the
one failure a draft must not make. An unmarked timestamp, a bare wall clock and
a relative phrase are all collected as mentions instead, so the user is told
what to write rather than being told nothing was found.

This module reads a string. The text it reads is the caller's live snapshot;
the adapter supplies it.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime

EXCERPT_RADIUS = 48
"""Characters kept on each side of a match, so evidence quotes real text."""

ISO = r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2})?(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})"
CANDIDATE = re.compile(rf"\bcandidates?\s*[:=]\s*({ISO})", re.IGNORECASE)
DURATION = re.compile(
    r"\bduration\s*[:=]\s*(\d{1,3})\s*(minutes|minute|mins|min|hours|hour|hrs|hr)\b",
    re.IGNORECASE,
)
UNMARKED = re.compile(ISO)
RELATIVE = re.compile(
    r"\b(?:today|tonight|tomorrow|yesterday|"
    r"(?:next|this|last)\s+(?:week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)|"
    r"monday|tuesday|wednesday|thursday|friday|saturday|sunday|"
    r"morning|afternoon|evening|noon|midnight|asap|sometime|soon|later)\b",
    re.IGNORECASE,
)
HOUR_UNITS = {"hours", "hour", "hrs", "hr"}

GRAMMAR = (
    "Candidate: <ISO 8601 date-time with a T separator and a UTC offset>, "
    "one per proposed time, and Duration: <N minutes|hours> once."
)


@dataclass(frozen=True)
class Mention:
    """One literal match, with the surrounding text it was read from."""

    text: str
    excerpt: str
    source: str
    span: tuple[int, int] = (0, 0)


@dataclass(frozen=True)
class TimeMention(Mention):
    start: datetime = None  # type: ignore[assignment]


@dataclass(frozen=True)
class Reading:
    candidates: tuple[TimeMention, ...] = ()
    duration_minutes: int | None = None
    duration_mention: Mention | None = None
    unmarked_times: tuple[Mention, ...] = ()
    relative_mentions: tuple[Mention, ...] = ()
    conflicting_durations: tuple[int, ...] = ()
    source: str = "the focused field"
    notes: tuple[str, ...] = field(default_factory=tuple)


def excerpt(text: str, start: int, end: int) -> str:
    """The match plus a little context, whitespace-collapsed and elided."""
    lower = max(0, start - EXCERPT_RADIUS)
    upper = min(len(text), end + EXCERPT_RADIUS)
    window = " ".join(text[lower:upper].split())
    return ("..." if lower > 0 else "") + window + ("..." if upper < len(text) else "")


def _parse(literal: str) -> datetime | None:
    normalized = literal[:-1] + "+00:00" if literal.endswith(("Z", "z")) else literal
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    return parsed if parsed.tzinfo is not None else None


def read_text(text: str, source: str = "the focused field") -> Reading:
    """Read the marked candidates and duration out of ``text``."""
    candidates = []
    claimed: list[tuple[int, int]] = []
    for match in CANDIDATE.finditer(text):
        literal = match.group(1)
        parsed = _parse(literal)
        if parsed is None:
            continue
        claimed.append(match.span(1))
        candidates.append(
            TimeMention(
                text=literal,
                excerpt=excerpt(text, match.start(), match.end()),
                source=source,
                span=match.span(),
                start=parsed,
            )
        )

    durations: dict[int, Mention] = {}
    for match in DURATION.finditer(text):
        value = int(match.group(1)) * (60 if match.group(2).lower() in HOUR_UNITS else 1)
        if value > 0:
            durations.setdefault(
                value,
                Mention(match.group(0), excerpt(text, match.start(), match.end()), source, match.span()),
            )

    unmarked = tuple(
        Mention(match.group(0), excerpt(text, match.start(), match.end()), source, match.span())
        for match in UNMARKED.finditer(text)
        if match.span() not in claimed
    )
    relative = tuple(
        Mention(match.group(0), excerpt(text, match.start(), match.end()), source, match.span())
        for match in RELATIVE.finditer(text)
    )

    notes = []
    duration_minutes: int | None = None
    duration_mention: Mention | None = None
    if len(durations) == 1:
        duration_minutes, duration_mention = next(iter(durations.items()))
    elif len(durations) > 1:
        notes.append(
            "The text marks more than one duration "
            f"({', '.join(f'{value} minutes' for value in sorted(durations))})."
        )
    if not candidates and (unmarked or relative):
        notes.append(f"No time is marked as a candidate. Write {GRAMMAR}")
    return Reading(
        candidates=tuple(candidates),
        duration_minutes=duration_minutes,
        duration_mention=duration_mention,
        unmarked_times=unmarked,
        relative_mentions=relative,
        conflicting_durations=tuple(sorted(durations)) if len(durations) > 1 else (),
        source=source,
        notes=tuple(notes),
    )

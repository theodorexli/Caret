"""Pure scheduling functions. Source failures are never replaced by model output."""

from datetime import datetime, timedelta
from email import policy
from email.parser import Parser
from typing import Sequence


def timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise ValueError("Timestamps must include a timezone offset")
    return parsed


def interval(start: str, end: str) -> tuple[datetime, datetime]:
    lower, upper = timestamp(start), timestamp(end)
    if upper <= lower:
        raise ValueError("Interval end must be after its start")
    return lower, upper


def extract_thread(raw: str) -> dict:
    """Decode a supplied RFC 822 message; Gmail thread retrieval is separate."""
    message = Parser(policy=policy.default).parsestr(raw)
    body = message.get_body(preferencelist=("plain",))
    if body is None:
        raise ValueError("The thread must contain a text/plain message")
    return {
        "subject": str(message.get("Subject", "")),
        "sender": str(message.get("From", "")),
        "body": body.get_content().strip(),
    }


def check_schedule_inputs(duration: int, before: int, after: int) -> None:
    if type(duration) is not int or duration <= 0:
        raise ValueError("duration_minutes must be a positive integer")
    if any(type(value) is not int or value < 0 for value in (before, after)):
        raise ValueError("Travel buffers must be nonnegative integer minutes")


def schedule_options(
    candidates: Sequence[tuple[str, datetime]],
    duration: int,
    busy: Sequence[tuple[datetime, datetime]],
    before: int = 0,
    after: int = 0,
    limit: int = 3,
) -> tuple[list[dict], list[str]]:
    """Filter offset-aware candidate starts against busy intervals.

    Shared by :func:`plan` and the live meeting adapter so both apply one rule:
    a candidate is dropped when its buffered hold overlaps any busy interval, or
    when an earlier candidate already claimed the same start. Returns the kept
    options sorted by start and truncated to ``limit``, plus the dropped IDs.
    Callers own where the candidates and busy intervals came from.
    """
    check_schedule_inputs(duration, before, after)
    options: list[dict] = []
    dropped: list[str] = []
    seen: set[datetime] = set()
    for candidate_id, start in candidates:
        end = start + timedelta(minutes=duration)
        blocked_start = start - timedelta(minutes=before)
        blocked_end = end + timedelta(minutes=after)
        if start in seen or any(blocked_start < hi and lo < blocked_end for lo, hi in busy):
            dropped.append(candidate_id)
            continue
        seen.add(start)
        options.append({
            "id": candidate_id, "start": start.isoformat(), "end": end.isoformat(),
            "hold_start": blocked_start.isoformat(), "hold_end": blocked_end.isoformat(),
        })
    options = sorted(options, key=lambda item: timestamp(item["start"]))[:limit]
    return options, dropped


def plan(fixture: dict) -> dict:
    if fixture.get("mode") != "sample":
        raise ValueError("This starter accepts labeled sample data only; connect live adapters first")
    thread = extract_thread(fixture["thread"])
    duration = fixture["duration_minutes"]
    before, after = fixture["buffer_before_minutes"], fixture["buffer_after_minutes"]
    check_schedule_inputs(duration, before, after)
    busy = [interval(item["start"], item["end"]) for item in fixture["busy"]]
    supported: list[tuple[str, datetime]] = []
    sources: dict[str, str] = {}
    dropped = []
    candidate_ids = set()
    for candidate in fixture["candidates"]:
        candidate_id = candidate.get("id")
        if not isinstance(candidate_id, str) or not candidate_id.strip():
            raise ValueError("Each candidate needs a nonempty string ID")
        if candidate_id in candidate_ids:
            raise ValueError(f"Duplicate candidate ID: {candidate_id}")
        candidate_ids.add(candidate_id)
        if candidate.get("status") != "ok" or not candidate.get("source"):
            dropped.append(candidate_id)
            continue
        supported.append((candidate_id, timestamp(candidate["start"])))
        sources[candidate_id] = candidate["source"]
    options, conflicts = schedule_options(supported, duration, busy, before, after)
    dropped.extend(conflicts)
    for option in options:
        option["source"] = sources[option["id"]]
    times = [f"{item['start']} to {item['end']}" for item in options]
    draft = "I can meet at one of these times:\n" + "\n".join(times) if options else ""
    return {
        "mode": "sample", "workflow": "book-calendar-link", "subject": thread["subject"],
        "thread_body": thread["body"], "options": options, "draft": draft,
        "evidence": fixture["evidence"], "dropped": dropped,
        "notice": "Synthetic development data. This draft cannot be sent. Holds are local only.",
    }

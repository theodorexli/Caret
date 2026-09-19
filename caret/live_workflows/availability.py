"""Where "is that time free?" is answered from, and how it fails.

Two sources are supported and both are explicitly configured. The Google
reader performs a real read-only free/busy query. The snapshot source replays
availability the caller captured earlier and says so in its own label, so a
draft can never present stale local data as a live calendar read.

Every failure raises :class:`AvailabilityError`. There is no code path that
turns a failed source into an empty busy list, because an empty busy list means
"everything is free" and no source said that.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Callable, Protocol

from ..context import now_utc
from ..planner import interval

FREEBUSY_ENDPOINT = "https://www.googleapis.com/calendar/v3/freeBusy"
"""Fixed. The endpoint is never taken from configuration or a response."""

MAX_RESPONSE_BYTES = 256 * 1024
DEFAULT_TIMEOUT_SECONDS = 10.0
DEFAULT_SNAPSHOT_MAX_AGE_SECONDS = 24 * 60 * 60

TOKEN_ENV = "CARET_GOOGLE_CALENDAR_TOKEN"
CALENDARS_ENV = "CARET_GOOGLE_CALENDAR_IDS"
SNAPSHOT_ENV = "CARET_AVAILABILITY_SNAPSHOT"


class AvailabilityError(RuntimeError):
    """The availability source could not answer. Never means "free"."""


@dataclass(frozen=True)
class BusyWindow:
    intervals: tuple[tuple[datetime, datetime], ...]
    label: str
    live: bool
    """True only for a source that queried a calendar service during this call."""


class AvailabilitySource(Protocol):
    @property
    def label(self) -> str:  # pragma: no cover - protocol
        ...

    def busy(self, start: datetime, end: datetime) -> BusyWindow:  # pragma: no cover
        ...


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse redirects: a followed 3xx would resend the bearer token elsewhere."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def _https_post(url: str, body: bytes, headers: dict, timeout: float) -> tuple[int, bytes]:
    if url != FREEBUSY_ENDPOINT:
        raise AvailabilityError("Refusing to send calendar credentials to an unexpected endpoint")
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    opener = urllib.request.build_opener(_NoRedirect)
    try:
        with opener.open(request, timeout=timeout) as response:
            return int(response.status), response.read(MAX_RESPONSE_BYTES + 1)
    except urllib.error.HTTPError as error:
        return int(error.code), b""
    except Exception as error:  # timeout, DNS, TLS, refused redirect
        raise AvailabilityError(
            f"Google free/busy could not be reached ({type(error).__name__})"
        ) from None


class GoogleFreeBusySource:
    """Read-only Google Calendar free/busy.

    POSTs ``timeMin``/``timeMax``/``items`` to the fixed v3 ``freeBusy``
    endpoint with a bearer token, per Google's published reference. A busy
    interval is ``[start, end)``. Anything unexpected in the reply - a missing
    calendar, a per-calendar ``errors`` entry, an omitted ``busy`` list, bounds
    that do not cover what was asked - is an error, not an absence of conflicts.
    """

    def __init__(
        self,
        token: str,
        calendar_ids: tuple[str, ...],
        transport: Callable[[str, bytes, dict, float], tuple[int, bytes]] = _https_post,
        timeout: float = DEFAULT_TIMEOUT_SECONDS,
    ) -> None:
        if not token.strip():
            raise AvailabilityError(f"{TOKEN_ENV} is empty")
        if not calendar_ids:
            raise AvailabilityError(f"{CALENDARS_ENV} names no calendar")
        self._token = token.strip()
        self._calendar_ids = tuple(calendar_ids)
        self._transport = transport
        self._timeout = timeout

    @classmethod
    def from_env(cls, env=None, **kwargs) -> "GoogleFreeBusySource | None":
        """Build from the two documented variables, or return None. Nothing else
        in the environment is read or searched."""
        env = os.environ if env is None else env
        token = (env.get(TOKEN_ENV) or "").strip()
        ids = tuple(part.strip() for part in (env.get(CALENDARS_ENV) or "").split(",") if part.strip())
        if not token or not ids:
            return None
        return cls(token, ids, **kwargs)

    @property
    def label(self) -> str:
        count = len(self._calendar_ids)
        return f"Google Calendar free/busy, live read of {count} calendar{'s' if count != 1 else ''}"

    def busy(self, start: datetime, end: datetime) -> BusyWindow:
        body = json.dumps(
            {
                "timeMin": start.isoformat(),
                "timeMax": end.isoformat(),
                "timeZone": "UTC",
                "items": [{"id": calendar_id} for calendar_id in self._calendar_ids],
            }
        ).encode("utf-8")
        status, raw = self._transport(
            FREEBUSY_ENDPOINT,
            body,
            {
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
                "Accept": "application/json",
            },
            self._timeout,
        )
        if status != 200:
            raise AvailabilityError(f"Google free/busy returned HTTP {status}")
        if len(raw) > MAX_RESPONSE_BYTES:
            raise AvailabilityError("Google free/busy returned more data than this adapter accepts")
        return BusyWindow(self._parse(raw, start, end), self.label, live=True)

    def _parse(self, raw: bytes, start: datetime, end: datetime) -> tuple[tuple[datetime, datetime], ...]:
        """Strict, and quiet: no part of the response reaches an error message."""
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            raise AvailabilityError("Google free/busy returned a body that is not JSON") from None
        if not isinstance(payload, dict):
            raise AvailabilityError("Google free/busy returned a body that is not an object")
        try:
            covered = interval(payload["timeMin"], payload["timeMax"])
        except (KeyError, TypeError, ValueError):
            raise AvailabilityError("Google free/busy returned unusable timeMin/timeMax bounds") from None
        if covered[0] > start or covered[1] < end:
            raise AvailabilityError("Google free/busy answered for a narrower window than was requested")
        calendars = payload.get("calendars")
        if not isinstance(calendars, dict):
            raise AvailabilityError("Google free/busy returned no calendars object")
        intervals: list[tuple[datetime, datetime]] = []
        for calendar_id in self._calendar_ids:
            entry = calendars.get(calendar_id)
            if not isinstance(entry, dict):
                raise AvailabilityError("Google free/busy omitted a requested calendar")
            if entry.get("errors"):
                raise AvailabilityError("Google free/busy reported an error for a requested calendar")
            periods = entry.get("busy")
            if not isinstance(periods, list):
                raise AvailabilityError("Google free/busy omitted the busy list for a requested calendar")
            for period in periods:
                try:
                    intervals.append(interval(period["start"], period["end"]))
                except (KeyError, TypeError, ValueError):
                    raise AvailabilityError("Google free/busy returned a malformed busy interval") from None
        return tuple(sorted(intervals))


class AvailabilitySnapshotSource:
    """Availability the caller captured earlier, replayed under its own name.

    Honest by construction: the label says it is a snapshot and names when and
    where it came from, it refuses windows it does not cover, and it expires.
    """

    def __init__(
        self,
        busy_intervals: tuple[tuple[datetime, datetime], ...],
        covered_start: datetime,
        covered_end: datetime,
        captured_at: datetime,
        provenance: str,
        max_age_seconds: float = DEFAULT_SNAPSHOT_MAX_AGE_SECONDS,
        clock: Callable[[], datetime] = now_utc,
    ) -> None:
        if not provenance.strip():
            raise AvailabilityError("An availability snapshot must declare its provenance")
        for name, value in (
            ("covered_start", covered_start),
            ("covered_end", covered_end),
            ("captured_at", captured_at),
        ):
            if value.tzinfo is None:
                raise AvailabilityError(f"Availability snapshot {name} needs a timezone offset")
        if covered_end <= covered_start:
            raise AvailabilityError("Availability snapshot covered_end must be after covered_start")
        if type(max_age_seconds) not in (int, float) or max_age_seconds <= 0:
            raise AvailabilityError("Availability snapshot max_age_seconds must be a positive number")
        if captured_at > clock():
            raise AvailabilityError("An availability snapshot cannot be captured in the future")
        for entry in busy_intervals:
            if not isinstance(entry, tuple) or len(entry) != 2:
                raise AvailabilityError("Each snapshot busy interval must be a (start, end) pair")
            lower, upper = entry
            if not isinstance(lower, datetime) or not isinstance(upper, datetime):
                raise AvailabilityError("Snapshot busy interval bounds must be datetimes")
            if lower.tzinfo is None or upper.tzinfo is None:
                raise AvailabilityError("Snapshot busy interval bounds need a timezone offset")
            if upper <= lower:
                raise AvailabilityError("A snapshot busy interval must end after it starts")
        self._intervals = tuple(sorted(busy_intervals))
        self._covered = (covered_start, covered_end)
        self._captured_at = captured_at
        self._provenance = provenance.strip()
        self._max_age = max_age_seconds
        self._clock = clock

    @classmethod
    def from_file(cls, path: Path, **kwargs) -> "AvailabilitySnapshotSource":
        try:
            payload = json.loads(Path(path).read_text())
        except (OSError, json.JSONDecodeError) as error:
            raise AvailabilityError(f"Availability snapshot could not be read: {type(error).__name__}") from None
        if not isinstance(payload, dict) or not isinstance(payload.get("busy"), list):
            raise AvailabilityError(
                "An availability snapshot must state its busy list explicitly; an omitted "
                "list would claim the whole covered window is free"
            )
        try:
            covered = interval(payload["covered_start"], payload["covered_end"])
            captured_at = datetime.fromisoformat(payload["captured_at"])
            busy = tuple(interval(item["start"], item["end"]) for item in payload["busy"])
            provenance = str(payload["provenance"])
        except (KeyError, TypeError, ValueError):
            raise AvailabilityError(
                "An availability snapshot needs covered_start, covered_end, captured_at, "
                "provenance and a busy list of offset-aware intervals"
            ) from None
        if captured_at.tzinfo is None:
            raise AvailabilityError("Availability snapshot captured_at needs a timezone offset")
        return cls(busy, covered[0], covered[1], captured_at, provenance, **kwargs)

    @classmethod
    def from_env(cls, env=None, **kwargs) -> "AvailabilitySnapshotSource | None":
        env = os.environ if env is None else env
        path = (env.get(SNAPSHOT_ENV) or "").strip()
        return cls.from_file(Path(path), **kwargs) if path else None

    @property
    def label(self) -> str:
        return (
            f"configured availability snapshot from {self._provenance}, captured "
            f"{self._captured_at.isoformat()}, covering "
            f"{self._covered[0].isoformat()} to {self._covered[1].isoformat()} "
            "(replayed capture, not a live calendar read)"
        )

    def busy(self, start: datetime, end: datetime) -> BusyWindow:
        age = (self._clock() - self._captured_at).total_seconds()
        if age > self._max_age:
            raise AvailabilityError(
                f"The configured availability snapshot is {int(age // 60)} minutes old, "
                f"past its {int(self._max_age // 60)} minute limit"
            )
        if start < self._covered[0] or end > self._covered[1]:
            raise AvailabilityError(
                "The configured availability snapshot does not cover the requested window "
                f"({start.isoformat()} to {end.isoformat()})"
            )
        kept = tuple(
            (lower, upper) for lower, upper in self._intervals if lower < end and start < upper
        )
        return BusyWindow(kept, self.label, live=False)


def resolve_source(env=None, **kwargs) -> tuple[AvailabilitySource | None, str]:
    """The configured source, or None with the reason it is not configured."""
    env = os.environ if env is None else env
    google = GoogleFreeBusySource.from_env(env, **kwargs)
    if google is not None:
        return google, ""
    snapshot = AvailabilitySnapshotSource.from_env(env)
    if snapshot is not None:
        return snapshot, ""
    return None, (
        "No availability source is configured. Set "
        f"{TOKEN_ENV} and {CALENDARS_ENV} for a read-only Google Calendar free/busy query, "
        f"or {SNAPSHOT_ENV} to a captured availability snapshot. "
        "Without one, nothing here knows whether a time is free."
    )


def request_window(
    starts: tuple[datetime, ...], duration_minutes: int, before: int, after: int
) -> tuple[datetime, datetime]:
    """The smallest window covering every buffered candidate hold."""
    lower = min(starts) - timedelta(minutes=before)
    upper = max(starts) + timedelta(minutes=duration_minutes + after)
    return lower, upper

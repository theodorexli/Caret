"""The meeting adapter: propose times, return a draft, send nothing.

What it does, end to end. ``availability`` reports whether this machine could
run it at all: Accessibility granted, the field not secure, and an availability
source configured. ``prepare`` reads the caller's own snapshot text, turns it
into a :class:`~caret.live_workflows.request.MeetingRequest`, asks the
configured availability source about the window those candidates span, drops
every candidate whose buffered hold overlaps a busy interval, and returns a
draft with one evidence line per surviving option. ``execute`` returns that
exact draft as structured data.

What it does not do. It never sends mail, never creates or modifies a calendar
event, and never claims to have inserted anything. ``execute`` returns the
approved text; whoever called it decides what to do with it. That is the whole
external effect, and it is why the descriptor's execution method is
``draft_only``.

Failure is always visible. Ambiguous text, a missing duration, an availability
source that could not answer, and a calendar with no free candidate all end in
``needs_input`` with the reason spelled out. None of them ends in a draft.

Acceptance is rechecked against the live frame, not trusted from the payload.
The preparation is one-use, held in memory on the adapter instance: there are
no external writes to reconcile, so a durable record would only add a way for
the two to disagree.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Callable, Mapping

from ..context import ContextFrame, digest, now_utc
from ..planner import schedule_options
from ..registry import Availability, ExecutionResult, Preparation, WorkflowDescriptor
from .availability import AvailabilityError, AvailabilitySource, request_window, resolve_source
from .request import MeetingRequest, build_request

WORKFLOW_ID = "book-calendar-link"
MAX_OPTIONS = 3
MAX_WINDOW_DAYS = 14
"""The widest span of candidates one free/busy request may cover. Candidates
further apart than this are a sign the text was misread, not a long lead time."""

PREPARATION_MAX_AGE_SECONDS = 180.0
"""How long an unaccepted draft stays valid. Past this the calendar may have
changed underneath it, and nothing here watches for that."""

DRAFT_HEADER = "Here are times that work on my calendar:"
NO_EFFECT = (
    "Returned the approved draft text only. No message was sent, and no calendar "
    "event was created, held or modified."
)


@dataclass(frozen=True)
class _Pending:
    """What acceptance is rechecked against, and what it returns.

    ``result`` is the approved result, built at preparation time and held here.
    Acceptance returns this object, so nothing the caller hands back can change
    what the workflow reports it produced.
    """

    frame_signature: str
    target: tuple
    text_digest: str
    revision: int
    proposal_digest: str
    evidence_digest: str
    excerpts: tuple[str, ...]
    starts: tuple[datetime, ...]
    prepared_at: datetime
    result: ExecutionResult


def _proposal_digest(proposal: dict) -> str:
    """One digest over everything the user saw in the proposal."""
    return digest(json.dumps(proposal, sort_keys=True, default=str))


def render_draft(options: list[dict]) -> str:
    lines = [f"- {option['start']} to {option['end']}" for option in options]
    return "\n".join([DRAFT_HEADER, *lines])


class MeetingDraftWorkflow:
    """Draft-only calendar-link workflow, registered as ``book-calendar-link``.

    Constructed with no arguments it reads its availability source from the
    environment, which is what the registry's adapter factory needs. Tests pass
    ``availability_source`` and ``clock`` instead; neither is read from the
    environment when supplied.
    """

    def __init__(
        self,
        availability_source: AvailabilitySource | None = None,
        clock: Callable[[], datetime] = now_utc,
        environ: Mapping[str, str] | None = None,
    ) -> None:
        if availability_source is not None:
            self._source: AvailabilitySource | None = availability_source
            self._unconfigured_reason = ""
        else:
            self._source, self._unconfigured_reason = resolve_source(environ)
        self._clock = clock
        self._pending: dict[str, _Pending] = {}

    @property
    def descriptor(self) -> WorkflowDescriptor:
        return WorkflowDescriptor(
            id=WORKFLOW_ID,
            name="Calendar link",
            description=(
                "Draft a reply offering meeting times from the explicit times in the "
                "current text, checked against a configured read-only availability source."
            ),
            required_inputs=(
                "candidate times with explicit UTC offsets in the current text",
                "a meeting duration in the current text",
                "a configured availability source",
            ),
            execution_method="draft_only",
            sample_only=False,
        )

    @property
    def source_label(self) -> str:
        return self._source.label if self._source is not None else "none"

    def availability(self, frame: ContextFrame) -> Availability:
        if not frame.permissions.accessibility:
            return Availability(False, "Accessibility is not granted, so there is no text to read.")
        if frame.snapshot.secure:
            return Availability(False, "The focused field is secure; Caret does not read it.")
        if self._source is None:
            return Availability(False, self._unconfigured_reason)
        return Availability(True, f"Availability comes from {self._source.label}.")

    def prepare(self, frame: ContextFrame) -> Preparation:
        return self.prepare_request(frame, build_request(frame.snapshot.nearby_text))

    def prepare_request(self, frame: ContextFrame, request: MeetingRequest) -> Preparation:
        """Prepare from a caller-supplied request.

        The entry point for a correction: the caller rebuilds the request with
        its own candidates or duration and calls this. Every candidate still
        carries the excerpt and origin its type demands, so a corrected option
        is as traceable as an extracted one.
        """
        # The core owns one visible offer. Superseding it must not retain an
        # unbounded history of drafts when the router does not call cancel().
        self._pending.clear()
        ready = self.availability(frame)
        if not ready.available:
            return self._blocked("Nothing is proposed.", (ready.reason,), ())
        if not request.ready:
            return self._blocked(
                "Nothing is proposed yet.",
                tuple(request.missing) or ("a candidate time and a duration",),
                self._mention_evidence(request),
            )

        # A caller correction is not evidence by itself. Until the bridge has a
        # separate reviewed-input channel, require the corrected facts in the field.
        sourced = build_request(frame.snapshot.nearby_text)
        if (not sourced.ready or request.duration_minutes != sourced.duration_minutes
                or any(start not in sourced.starts() for start in request.starts())):
            return self._blocked(
                "Nothing is proposed: corrected times are not supported by the current text.",
                ("put the corrected Candidate and Duration values in the focused field",),
                (),
            )
        duration = request.duration_minutes
        starts = request.starts()
        window = request_window(
            starts, duration, request.buffer_before_minutes, request.buffer_after_minutes
        )
        if window[1] - window[0] > timedelta(days=MAX_WINDOW_DAYS):
            return self._blocked(
                "The candidate times are too far apart to check in one request.",
                (
                    f"candidate times within {MAX_WINDOW_DAYS} days of each other; "
                    f"the text spans {window[0].isoformat()} to {window[1].isoformat()}",
                ),
                self._mention_evidence(request),
            )

        try:
            busy = self._source.busy(*window)
        except AvailabilityError as error:
            return self._blocked(
                "No times are offered: the availability source did not answer.",
                (f"a working availability source ({error})",),
                self._mention_evidence(request) + (f"availability source: {self.source_label}",),
            )

        now = self._clock()
        schedulable = [
            (candidate.id, candidate.start) for candidate in request.candidates if candidate.start > now
        ]
        past = [candidate.id for candidate in request.candidates if candidate.start <= now]
        options, conflicted = schedule_options(
            schedulable,
            duration,
            busy.intervals,
            request.buffer_before_minutes,
            request.buffer_after_minutes,
            limit=MAX_OPTIONS,
        )
        if not options:
            return self._blocked(
                "Every candidate time is taken or has passed.",
                ("a candidate time that is free on the configured calendar",),
                self._mention_evidence(request)
                + (f"availability source: {busy.label}",)
                + self._dropped_evidence(conflicted, past),
            )

        by_id = {candidate.id: candidate for candidate in request.candidates}
        evidence = tuple(
            f"{option['start']} to {option['end']} read from {by_id[option['id']].origin}: "
            f"\"{by_id[option['id']].excerpt}\"; availability from {busy.label}"
            for option in options
        )
        evidence += (f"duration from {request.duration_source}",)
        evidence += self._mention_evidence(request) + self._dropped_evidence(conflicted, past)
        draft = render_draft(options)
        token = uuid.uuid4().hex
        proposal = {
            "token": token,
            "workflow": WORKFLOW_ID,
            "draft": draft,
            "options": options,
            "duration_minutes": duration,
            "availability_source": busy.label,
            "availability_live": busy.live,
            "prepared_at": now.isoformat(),
        }
        # The result acceptance will return is built here, from what was reviewed,
        # and kept out of the caller's reach. execute() returns this object; it
        # never rebuilds the result out of the proposal it is handed back.
        result = ExecutionResult(
            status="completed",
            summary=f"Drafted {len(options)} meeting time(s) for review.",
            effects=(NO_EFFECT,),
            # The native WorkflowExecution currently carries evidence, not effects
            # or data. Keep the no-send/no-calendar result visible across that wire.
            evidence=evidence + (NO_EFFECT,),
            data={
                "workflow": WORKFLOW_ID,
                "draft": draft,
                "options": json.loads(json.dumps(options)),
                "duration_minutes": duration,
                "availability_source": busy.label,
                "availability_live": busy.live,
                "sent": False,
                "calendar_event_created": False,
            },
        )
        self._pending[token] = _Pending(
            frame_signature=frame.signature(),
            target=tuple(sorted(frame.snapshot.target.to_dict().items())),
            text_digest=frame.snapshot.text_digest,
            revision=frame.revision,
            proposal_digest=_proposal_digest(proposal),
            evidence_digest=digest("\x1f".join(evidence)),
            excerpts=tuple(by_id[option["id"]].excerpt for option in options),
            starts=tuple(by_id[option["id"]].start for option in options),
            prepared_at=now,
            result=result,
        )
        return Preparation(
            title=f"Offer {len(options)} meeting time{'s' if len(options) > 1 else ''}",
            effect=(
                "Returns this draft text for review. Nothing is sent, and no calendar "
                "event is created.\n\n" + draft
            ),
            evidence=evidence,
            payload=json.loads(json.dumps(proposal)),
        )

    def execute(self, frame: ContextFrame, preparation: Preparation) -> ExecutionResult:
        if preparation.missing_inputs:
            return ExecutionResult(
                status="needs_input",
                summary="; ".join(preparation.missing_inputs),
                evidence=preparation.evidence,
            )
        token = preparation.payload.get("token")
        pending = self._pending.pop(token, None) if isinstance(token, str) else None
        if pending is None:
            return ExecutionResult(
                status="failed",
                summary="This preparation is unknown, already used, or was cancelled. Prepare again.",
            )
        failure = self._recheck(frame, preparation, pending)
        if failure is not None:
            return ExecutionResult(status="failed", summary=failure, evidence=pending.result.evidence)
        return pending.result

    def cancel(self, preparation: Preparation) -> ExecutionResult:
        token = preparation.payload.get("token")
        if isinstance(token, str):
            self._pending.pop(token, None)
        return ExecutionResult(
            status="cancelled",
            summary="Draft discarded. Nothing was sent and nothing was written.",
        )

    def _recheck(self, frame: ContextFrame, preparation: Preparation, pending: _Pending) -> str | None:
        """Everything acceptance has to prove again, cheapest check first."""
        age = (self._clock() - pending.prepared_at).total_seconds()
        if age > PREPARATION_MAX_AGE_SECONDS:
            return (
                f"This draft was prepared {int(age)}s ago, past its "
                f"{int(PREPARATION_MAX_AGE_SECONDS)}s limit. Prepare again."
            )
        # The frame signature covers the text and the target, not these. They are
        # session facts, so an acceptance arriving after Accessibility was revoked
        # or the field turned secure has to be caught on its own.
        if not frame.permissions.accessibility:
            return "Accessibility is no longer granted."
        for flag, message in (
            (frame.snapshot.secure, "The focused field is now secure."),
            (frame.snapshot.app_excluded, "The focused app is now excluded."),
            (frame.snapshot.ime_composing, "An input method is composing in the focused field."),
        ):
            if flag:
                return message
        if tuple(sorted(frame.snapshot.target.to_dict().items())) != pending.target:
            return "The focused field changed after this draft was prepared."
        if frame.revision < pending.revision:
            return "This acceptance carries an older snapshot than the draft was prepared from."
        if frame.snapshot.text_digest != pending.text_digest:
            return "The text changed after this draft was prepared."
        if frame.signature() != pending.frame_signature:
            return "The context changed after this draft was prepared."
        if _proposal_digest(preparation.payload) != pending.proposal_digest:
            return "The proposal does not match what was prepared."
        if digest("\x1f".join(preparation.evidence)) != pending.evidence_digest:
            return "The evidence does not match what was prepared."
        for excerpt in pending.excerpts:
            if excerpt.strip(". ") not in " ".join(frame.snapshot.nearby_text.split()):
                return "The text a proposed time was read from is no longer in the field."
        if any(start <= self._clock() for start in pending.starts):
            return "A proposed time has passed."
        return None

    def _blocked(self, effect: str, missing: tuple[str, ...], evidence: tuple[str, ...]) -> Preparation:
        return Preparation(
            title="Meeting times not proposed",
            effect=effect,
            evidence=evidence,
            missing_inputs=missing,
        )

    @staticmethod
    def _mention_evidence(request: MeetingRequest) -> tuple[str, ...]:
        return tuple(f"not interpreted: {mention}" for mention in request.ambiguous)

    @staticmethod
    def _dropped_evidence(conflicted: list[str], past: list[str]) -> tuple[str, ...]:
        lines = []
        if conflicted:
            lines.append(f"dropped as busy: {', '.join(conflicted)}")
        if past:
            lines.append(f"dropped as already past: {', '.join(past)}")
        return tuple(lines)


def build() -> MeetingDraftWorkflow:
    """Zero-argument factory for ``--adapter caret.live_workflows.meeting:build``."""
    return MeetingDraftWorkflow()


__all__ = ["MeetingDraftWorkflow", "WORKFLOW_ID", "build", "render_draft"]

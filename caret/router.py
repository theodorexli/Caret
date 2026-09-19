"""Scheduling and offer lifecycle: what gets asked, and what stays valid.

This module holds no provider calls and no threads of its own. It is the policy
the bridge and the tests both drive, so the cadence rules can be checked with a
fake clock instead of by waiting two seconds.

Four rules shape it:

* One evaluation in flight. New context replaces the pending frame rather than
  queueing behind it, so under continuous typing the newest snapshot is the one
  that gets asked about.
* A result is published only if the context it described is still current. A
  response that arrives after the user moved to another field is discarded.
* An offer is executed only once, against the exact target and revision it was
  built for.
* Both lifecycle callbacks run while the lock that made the transition is still
  held, so the announcements reach the caller in transition order: an offer is
  announced before the invalidation that retires it, never after.
"""

from __future__ import annotations

import threading
import uuid
from collections import OrderedDict
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Callable

from .context import ContextFrame, TargetIdentity, digest, utf16_length
from .registry import Preparation, WorkflowDescriptor, WorkflowError

INLINE_KIND = "inline"
ACTION_KIND = "action"

# Suppression reasons. The caller supplies the observation; we supply the rule.
SECURE_FIELD = "secure-field"
IME_COMPOSING = "ime-composing"
APP_EXCLUDED = "app-excluded"
ACCESSIBILITY_REVOKED = "accessibility-revoked"
WORKFLOW_ACTIVE = "workflow-active"
STALE_SOURCES = "stale-sources"

# Skip reasons that are not suppression.
UNCHANGED = "unchanged-context"
SUPERSEDED_REVISION = "superseded-revision"

# Coalesce reason: the frame is kept and retried, just not evaluated yet.
PROVIDER_BACKOFF = "provider-backoff"


class AcceptanceError(RuntimeError):
    """An acceptance did not match a current, unconsumed offer."""


@dataclass
class RouterConfig:
    interval_seconds: float = 2.0
    """Minimum wall time between first-stage evaluations while the user is
    active. 2,000 ms is the agreed product starting point, not a measurement."""

    max_source_age_seconds: float = 120.0
    """Supplied history and observations older than this stop counting as
    current context and suppress the tick instead of being sent as fresh."""

    max_offer_age_seconds: float = 30.0
    """An offer nobody accepted within this window is no longer accepted, so a
    stale hoverable cannot execute against text the user has since rewritten."""

    max_inline_units: int = 280
    """Ceiling on a generated inline edit, in UTF-16 units. Output above this is
    a provider failure; code does not shorten a proposal into something the
    model did not write."""

    failure_backoff_seconds: float = 10.0
    """Minimum wall time after a failed evaluation before another one starts.

    A failure must not suppress its context the way an abstention does, or a
    transient outage would silence Caret for text the user is still editing. But
    without a wait of its own, a permanent failure (a revoked key, an outage, a
    rate limit) is retried at the full cadence for as long as the user keeps
    typing, because every keystroke supplies a new eligible frame. Five cadence
    intervals turns that into one call per ten seconds. It is a product bound
    chosen against the 2,000 ms cadence, not a measured provider recovery time."""

    suppression_memory: int = 64
    """Cap on remembered dismissed/abstained signatures, and on remembered
    accepted proposal IDs."""


@dataclass(frozen=True)
class Offer:
    """A proposal bound to the exact snapshot and target it was built from."""

    proposal_id: str
    kind: str
    revision: int
    target: TargetIdentity
    signature: str
    created_at: datetime
    # Inline fields.
    replace_start: int = 0
    replace_end: int = 0
    replacement: str = ""
    original_digest: str = ""
    # Action fields.
    workflow_id: str = ""
    title: str = ""
    effect: str = ""
    evidence: tuple[str, ...] = ()
    required_inputs: tuple[str, ...] = ()
    missing_inputs: tuple[str, ...] = ()
    execution_method: str = ""
    sample_only: bool = False
    preparation: Preparation | None = None
    frame: ContextFrame | None = None
    """The context this offer was built from, kept so execution runs against
    the same evidence the user saw. Never serialized to the app."""

    def to_dict(self) -> dict:
        common = {
            "proposal_id": self.proposal_id,
            "kind": self.kind,
            "revision": self.revision,
            "target": self.target.to_dict(),
            "created_at": self.created_at.isoformat(),
        }
        if self.kind == INLINE_KIND:
            common.update(
                {
                    "replace_start": self.replace_start,
                    "replace_end": self.replace_end,
                    "replacement": self.replacement,
                    "original_digest": self.original_digest,
                }
            )
        else:
            common.update(
                {
                    "workflow_id": self.workflow_id,
                    "title": self.title,
                    "effect": self.effect,
                    "evidence": list(self.evidence),
                    "required_inputs": list(self.required_inputs),
                    "missing_inputs": list(self.missing_inputs),
                    "execution_method": self.execution_method,
                    "sample_only": self.sample_only,
                }
            )
        return common


@dataclass(frozen=True)
class Admission:
    """What submitting a frame did."""

    status: str  # "admitted" | "coalesced" | "skipped"
    reason: str = ""
    revision: int = -1

    def to_dict(self) -> dict:
        return {"status": self.status, "reason": self.reason, "revision": self.revision}


@dataclass(frozen=True)
class Publication:
    """What completing an evaluation did."""

    status: str  # "published" | "abstained" | "discarded" | "failed"
    reason: str = ""
    offer: Offer | None = None
    revision: int = -1

    def to_dict(self) -> dict:
        return {
            "status": self.status,
            "reason": self.reason,
            "revision": self.revision,
            "offer": self.offer.to_dict() if self.offer else None,
        }


def suppression_reason(frame: ContextFrame, now: datetime, config: RouterConfig) -> str | None:
    """Why ambient work must not run for this frame, or None.

    Each condition is an explicit field the app filled in. The core never looks
    at the screen, the keyboard or the permission database to find these out.
    """
    snapshot = frame.snapshot
    if snapshot.secure:
        return SECURE_FIELD
    if snapshot.ime_composing:
        return IME_COMPOSING
    if snapshot.app_excluded:
        return APP_EXCLUDED
    if not frame.permissions.accessibility:
        return ACCESSIBILITY_REVOKED
    if frame.workflow_active:
        return WORKFLOW_ACTIVE
    if frame.stale_sources(now, config.max_source_age_seconds):
        return STALE_SOURCES
    return None


class Router:
    """Holds the pending frame, the in-flight flag and the current offer.

    Safe to call from two threads: the bridge reads stdin on one and evaluates
    on another.
    """

    def __init__(
        self,
        config: RouterConfig | None = None,
        on_invalidate: Callable[[Offer, str], None] | None = None,
        on_publish: Callable[["Publication"], None] | None = None,
    ) -> None:
        self.config = config or RouterConfig()
        self._on_invalidate = on_invalidate
        """Called when a published offer stops being valid, so the app can take
        the hoverable down instead of leaving a proposal it could not execute."""
        self._on_publish = on_publish
        """Called with every finished evaluation, including the discarded ones.

        Both callbacks fire with ``_lock`` held, which is the whole point of
        having this one: a caller that announced the offer after
        ``complete_offer`` returned could be overtaken by a frame change that
        invalidated the same offer in between, and would then show a preview the
        client had already been told to take down. Neither callback may block or
        take another lock, because the router is stopped while it runs."""
        self._lock = threading.RLock()
        self._pending: ContextFrame | None = None
        self._in_flight: ContextFrame | None = None
        self._last_started: datetime | None = None
        self._highest_revision = -1
        self._current_target: TargetIdentity | None = None
        self._offer: Offer | None = None
        self._consumed: OrderedDict[str, datetime] = OrderedDict()
        """Accepted proposal IDs and when they were accepted, so a duplicate
        keypress is refused by name. Pruned in :meth:`accept`."""
        self._suppressed: OrderedDict[str, None] = OrderedDict()
        self._failed_at: datetime | None = None
        """When the most recent failed evaluation started, or None once a later
        evaluation has been claimed. Separate from suppression on purpose: it
        delays the next attempt without marking any context as handled."""

    # -- Inbound context -------------------------------------------------

    def submit(self, frame: ContextFrame, now: datetime) -> Admission:
        """Record the newest context. Returns whether it will be evaluated."""
        with self._lock:
            revision = frame.revision
            if revision <= self._highest_revision:
                return Admission("skipped", SUPERSEDED_REVISION, revision)
            self._highest_revision = revision
            self._current_target = frame.snapshot.target

            reason = suppression_reason(frame, now, self.config)
            if reason is not None:
                self._pending = None
                self._invalidate_locked(reason)
                return Admission("skipped", reason, revision)

            signature = frame.signature()
            if self._offer is not None and self._offer.signature != signature:
                self._invalidate_locked("context-changed")
            if signature in self._suppressed:
                return Admission("skipped", UNCHANGED, revision)

            self._pending = frame
            if self._in_flight is not None:
                return Admission("coalesced", "evaluation-in-flight", revision)
            if not self._backoff_elapsed_locked(now):
                # The frame stays pending, so the newest one is retried once the
                # backoff elapses rather than each changed frame calling a
                # provider that just failed.
                return Admission("coalesced", PROVIDER_BACKOFF, revision)
            if not self._interval_elapsed_locked(now):
                return Admission("coalesced", "cadence", revision)
            return Admission("admitted", "", revision)

    def take_due(self, now: datetime) -> ContextFrame | None:
        """Claim the pending frame if the cadence allows and nothing is running.

        Only the newest submitted frame is ever returned; everything submitted
        while an evaluation was running has already replaced its predecessor.
        """
        with self._lock:
            if self._in_flight is not None or self._pending is None:
                return None
            if not self._interval_elapsed_locked(now) or not self._backoff_elapsed_locked(now):
                return None
            frame = self._pending
            self._pending = None
            self._in_flight = frame
            self._last_started = now
            self._failed_at = None
            return frame

    def next_due_at(self) -> datetime | None:
        with self._lock:
            if self._pending is None or self._in_flight is not None:
                return None
            gates = [self._pending.snapshot.captured_at]
            if self._last_started is not None:
                gates.append(self._last_started + timedelta(seconds=self.config.interval_seconds))
            if self._failed_at is not None:
                gates.append(self._failed_at + timedelta(seconds=self.config.failure_backoff_seconds))
            return max(gates)

    def _interval_elapsed_locked(self, now: datetime) -> bool:
        if self._last_started is None:
            return True
        return (now - self._last_started).total_seconds() >= self.config.interval_seconds

    def _backoff_elapsed_locked(self, now: datetime) -> bool:
        if self._failed_at is None:
            return True
        return (now - self._failed_at).total_seconds() >= self.config.failure_backoff_seconds

    # -- Results ---------------------------------------------------------

    def is_stale(self, frame: ContextFrame) -> bool:
        """True when this frame no longer describes what the user is doing."""
        with self._lock:
            if frame.revision < self._highest_revision:
                return True
            return self._current_target is not None and self._current_target != frame.snapshot.target

    def _publish_locked(self, publication: Publication) -> Publication:
        """Announce a finished evaluation before the lock is released."""
        if self._on_publish is not None:
            self._on_publish(publication)
        return publication

    def complete_abstain(self, frame: ContextFrame, reason: str = "") -> Publication:
        with self._lock:
            self._in_flight = None
            if self.is_stale(frame):
                return self._publish_locked(
                    Publication("discarded", "stale-snapshot", None, frame.revision)
                )
            self._remember_suppressed_locked(frame.signature())
            return self._publish_locked(Publication("abstained", reason, None, frame.revision))

    def complete_failure(self, frame: ContextFrame, reason: str) -> Publication:
        """A provider failed. No offer, and the context is not marked handled,
        so a later tick may retry rather than treating silence as a decision.

        The retry waits for ``failure_backoff_seconds`` measured from the moment
        this failed evaluation began, which is the last time the router started
        one. Suppression is deliberately untouched: the context is still worth
        asking about, just not immediately.

        A stale failure — one whose frame is no longer current — is discarded
        and does not start backoff, so an explicit install is not poisoned by
        the ambient evaluation it replaced.
        """
        with self._lock:
            self._in_flight = None
            if self.is_stale(frame):
                return self._publish_locked(
                    Publication("discarded", "stale-snapshot", None, frame.revision)
                )
            self._failed_at = self._last_started
            return self._publish_locked(Publication("failed", reason, None, frame.revision))

    def complete_offer(self, frame: ContextFrame, offer: Offer) -> Publication:
        with self._lock:
            self._in_flight = None
            if self.is_stale(frame):
                return self._publish_locked(
                    Publication("discarded", "stale-snapshot", None, frame.revision)
                )
            self._offer = offer
            return self._publish_locked(Publication("published", "", offer, frame.revision))

    def install_offer(self, frame: ContextFrame, offer: Offer) -> Offer:
        """Publish an explicit-invoke offer without taking the in-flight slot."""
        with self._lock:
            if frame.revision <= self._highest_revision:
                raise WorkflowError(
                    f"Explicit invoke revision {frame.revision} is not newer than {self._highest_revision}"
                )
            self._highest_revision = frame.revision
            self._current_target = frame.snapshot.target
            self._pending = None
            self._invalidate_locked("replaced-by-explicit-invoke")
            self._offer = offer
            return offer

    # -- Offer lifecycle -------------------------------------------------

    @property
    def current_offer(self) -> Offer | None:
        with self._lock:
            return self._offer

    def _invalidate_locked(self, reason: str) -> Offer | None:
        offer = self._offer
        self._offer = None
        if offer is not None and self._on_invalidate is not None:
            self._on_invalidate(offer, reason)
        return offer

    def invalidate(self, reason: str) -> Offer | None:
        with self._lock:
            return self._invalidate_locked(reason)

    def dismiss(self, proposal_id: str) -> bool:
        """User dismissed an offer. Suppress the same unchanged context."""
        with self._lock:
            if self._offer is None or self._offer.proposal_id != proposal_id:
                return False
            self._remember_suppressed_locked(self._offer.signature)
            self._offer = None
            return True

    def _remember_suppressed_locked(self, signature: str) -> None:
        self._suppressed[signature] = None
        self._suppressed.move_to_end(signature)
        while len(self._suppressed) > self.config.suppression_memory:
            self._suppressed.popitem(last=False)

    def accept(
        self,
        proposal_id: str,
        revision: int,
        target: TargetIdentity,
        now: datetime,
    ) -> Offer:
        """Claim an offer for execution. Succeeds at most once per proposal.

        The caller re-reads the live target immediately before calling this, so
        a mismatch here means the user moved between seeing the offer and
        accepting it.
        """
        with self._lock:
            if proposal_id in self._consumed:
                raise AcceptanceError(f"Proposal '{proposal_id}' was already accepted")
            offer = self._offer
            if offer is None:
                raise AcceptanceError("There is no current offer to accept")
            if offer.proposal_id != proposal_id:
                raise AcceptanceError(
                    f"Proposal '{proposal_id}' is not the current offer '{offer.proposal_id}'"
                )
            if offer.revision != revision:
                raise AcceptanceError(
                    f"Proposal '{proposal_id}' was built for revision {offer.revision}, "
                    f"acceptance carried revision {revision}"
                )
            if target != offer.target:
                raise AcceptanceError("The input target changed after this proposal was shown")
            if self._current_target is not None and offer.target != self._current_target:
                # Comparing the acceptance only with the offer is not enough: a
                # caller can hand back the offer's own stale target. The offer
                # must also belong to the target the newest frame described, or
                # an action would run against a window the user has left.
                raise AcceptanceError(
                    "The live input target changed after this proposal was shown"
                )
            age = (now - offer.created_at).total_seconds()
            if age > self.config.max_offer_age_seconds:
                raise AcceptanceError(
                    f"Proposal '{proposal_id}' is {age:.1f}s old, past the "
                    f"{self.config.max_offer_age_seconds:.0f}s acceptance window"
                )
            # Consume before returning: a concurrent second acceptance loses here,
            # not after the workflow has already run.
            self._remember_consumed_locked(proposal_id, now)
            self._offer = None
            return offer

    def _remember_consumed_locked(self, proposal_id: str, now: datetime) -> None:
        """Record an accepted ID, and drop the ones that can no longer matter.

        An ID older than the acceptance window is already refused by the age
        check above, and its offer is no longer the current one, so keeping it
        only grows memory in a bridge that stays up for a whole session.
        """
        self._consumed[proposal_id] = now
        horizon = now - timedelta(seconds=self.config.max_offer_age_seconds)
        while self._consumed:
            oldest, accepted_at = next(iter(self._consumed.items()))
            if accepted_at >= horizon and len(self._consumed) <= self.config.suppression_memory:
                break
            del self._consumed[oldest]


def build_inline_offer(
    frame: ContextFrame,
    replacement: str,
    now: datetime,
    config: RouterConfig,
) -> Offer:
    """Turn generated text into an offer over a range code chose, not the model.

    With a selection, the offer replaces exactly that selection. Without one, it
    inserts at the caret. The model supplies only the text.
    """
    snapshot = frame.snapshot
    if snapshot.has_selection:
        start, end = snapshot.selection_start, snapshot.selection_end
        original = snapshot.selected_text()
    else:
        start = end = snapshot.caret
        original = ""
    length = utf16_length(replacement)
    if length == 0:
        raise ValueError("Inline generation returned empty text")
    if length > config.max_inline_units:
        raise ValueError(
            f"Inline generation returned {length} UTF-16 units, above the "
            f"{config.max_inline_units} unit bound"
        )
    return Offer(
        proposal_id=str(uuid.uuid4()),
        kind=INLINE_KIND,
        revision=snapshot.revision,
        target=snapshot.target,
        signature=frame.signature(),
        created_at=now,
        frame=frame,
        replace_start=start,
        replace_end=end,
        replacement=replacement,
        original_digest=digest(original),
    )


def build_action_offer(
    frame: ContextFrame,
    descriptor: WorkflowDescriptor,
    preparation: Preparation,
    now: datetime,
) -> Offer:
    return Offer(
        proposal_id=str(uuid.uuid4()),
        kind=ACTION_KIND,
        revision=frame.revision,
        target=frame.snapshot.target,
        signature=frame.signature(),
        created_at=now,
        frame=frame,
        workflow_id=descriptor.id,
        title=preparation.title,
        effect=preparation.effect,
        evidence=tuple(preparation.evidence),
        required_inputs=tuple(descriptor.required_inputs),
        missing_inputs=tuple(preparation.missing_inputs),
        execution_method=descriptor.execution_method,
        sample_only=descriptor.sample_only,
        preparation=preparation,
    )

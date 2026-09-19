"""The two decisions, joined to the router and the workflow registry.

``evaluate`` is the whole ambient loop: ask the judge what to do, and only on
ACTION ask it a second time which registered workflow fits. Nothing here
executes anything. Execution happens in :meth:`Engine.accept`, which runs only
after the user accepts a specific proposal that is still current.

A provider failure ends the tick with a failure publication. It never becomes
an abstention, a cached answer or an empty offer that looks like a decision.
"""

from __future__ import annotations

from datetime import datetime
from typing import Callable

from .context import ContextFrame, TargetIdentity, now_utc
from .judge import (
    ABSTAIN,
    ACTION,
    INLINE,
    NONE,
    Judge,
    JudgeError,
    Writer,
    route_question,
    workflow_question,
)
from .registry import ExecutionResult, WorkflowError, WorkflowRegistry
from .router import (
    ACTION_KIND,
    INLINE_KIND,
    Admission,
    Offer,
    Publication,
    Router,
    RouterConfig,
    build_action_offer,
    build_inline_offer,
)

INLINE_INSTRUCTION = (
    "Continue or correct the user's text at the caret. Reply with only the text to insert or "
    "the text that replaces the selection. No explanation, no quotes, no markdown."
)


class ProviderFailure(RuntimeError):
    """Raised by a Writer when generation could not be completed."""


class Engine:
    """Owns one router, one judge, one writer and one registry."""

    def __init__(
        self,
        judge: Judge,
        writer: Writer,
        registry: WorkflowRegistry,
        config: RouterConfig | None = None,
        clock: Callable[[], datetime] = now_utc,
        on_invalidate: Callable[[object, str], None] | None = None,
        on_publish: Callable[[Publication], None] | None = None,
    ) -> None:
        self.judge = judge
        self.writer = writer
        self.registry = registry
        self.config = config or RouterConfig()
        self.router = Router(self.config, on_invalidate=on_invalidate, on_publish=on_publish)
        self.clock = clock

    # -- Ambient loop ----------------------------------------------------

    def submit(self, frame: ContextFrame) -> Admission:
        return self.router.submit(frame, self.clock())

    def pump(self) -> Publication | None:
        """Run at most one due evaluation. Returns None when nothing is due."""
        frame = self.router.take_due(self.clock())
        if frame is None:
            return None
        return self.evaluate(frame)

    def evaluate(self, frame: ContextFrame) -> Publication:
        """Decide about one claimed frame, and always finish it.

        Every ordinary exception becomes a failure publication. The router's
        single in-flight slot is cleared only by a ``complete_*`` call, so an
        exception escaping this method would leave that slot set for good: every
        later context update would be coalesced behind a frame nobody is
        evaluating, and the loop would stop for the rest of the session. The
        typed provider and workflow errors below stay separate because their
        reasons name where the failure happened; this boundary catches the rest,
        including a bug in Caret's own code.
        """
        try:
            return self._evaluate(frame)
        except Exception as error:
            return self.router.complete_failure(
                frame, f"unexpected {type(error).__name__}: {error}"
            )

    def _evaluate(self, frame: ContextFrame) -> Publication:
        try:
            verdict = self.judge.choose(route_question(), frame)
        except JudgeError as error:
            return self.router.complete_failure(frame, f"judge/route: {error}")

        if verdict.choice_id == ABSTAIN:
            return self.router.complete_abstain(frame, verdict.reason or "judge-abstained")
        if verdict.choice_id == INLINE:
            return self._offer_inline(frame)
        if verdict.choice_id == ACTION:
            return self._offer_action(frame)
        # validate_choice already rejects anything else; this guards a Judge
        # implementation that skipped it.
        return self.router.complete_failure(frame, f"judge/route returned '{verdict.choice_id}'")

    def _offer_inline(self, frame: ContextFrame) -> Publication:
        try:
            text = self.writer.complete(frame, INLINE_INSTRUCTION)
        except ProviderFailure as error:
            return self.router.complete_failure(frame, f"writer: {error}")
        if not isinstance(text, str):
            return self.router.complete_failure(frame, "writer returned a non-string result")
        try:
            offer = build_inline_offer(frame, text, self.clock(), self.config)
        except ValueError as error:
            return self.router.complete_failure(frame, f"inline: {error}")
        return self.router.complete_offer(frame, offer)

    def _offer_action(self, frame: ContextFrame) -> Publication:
        choices = self.registry.choices(frame)
        if not choices:
            return self.router.complete_abstain(frame, "no-available-workflow")
        try:
            verdict = self.judge.choose(workflow_question(choices), frame)
        except JudgeError as error:
            return self.router.complete_failure(frame, f"judge/workflow: {error}")
        if verdict.choice_id == NONE:
            return self.router.complete_abstain(frame, "no-workflow-fits")

        try:
            adapter = self.registry.get(verdict.choice_id)
        except WorkflowError as error:
            return self.router.complete_failure(frame, str(error))
        availability = adapter.availability(frame)
        if not availability.available:
            return self.router.complete_failure(
                frame, f"workflow '{verdict.choice_id}' became unavailable: {availability.reason}"
            )
        try:
            preparation = adapter.prepare(frame)
        except WorkflowError as error:
            return self.router.complete_failure(frame, f"workflow/prepare: {error}")
        offer = build_action_offer(frame, adapter.descriptor, preparation, self.clock())
        return self.router.complete_offer(frame, offer)

    # -- Acceptance ------------------------------------------------------

    def accept(self, proposal_id: str, revision: int, target: TargetIdentity) -> dict:
        """Execute exactly one accepted proposal.

        The router consumes the proposal before any workflow runs, so a repeated
        acceptance is refused rather than executed a second time.
        """
        offer = self.router.accept(proposal_id, revision, target, self.clock())
        if offer.kind == INLINE_KIND:
            # Caret proposes; the app inserts, owns undo and owns the clipboard.
            return {
                "kind": INLINE_KIND,
                "proposal_id": offer.proposal_id,
                "status": "ready_to_insert",
                "target": offer.target.to_dict(),
                "replace_start": offer.replace_start,
                "replace_end": offer.replace_end,
                "replacement": offer.replacement,
                "original_digest": offer.original_digest,
                "note": "Revalidate the range against the live field before inserting.",
            }

        adapter = self.registry.get(offer.workflow_id)
        if offer.missing_inputs:
            result = ExecutionResult(
                status="needs_input",
                summary=f"'{offer.workflow_id}' still needs: {', '.join(offer.missing_inputs)}",
                evidence=offer.evidence,
            )
        else:
            frame = offer.frame
            if frame is None:  # pragma: no cover - offers are always built with a frame
                raise WorkflowError("Accepted offer carries no context frame")
            try:
                result = adapter.execute(frame, offer.preparation)
            except WorkflowError as error:
                result = ExecutionResult(status="failed", summary=str(error))
        return {
            "kind": ACTION_KIND,
            "proposal_id": offer.proposal_id,
            "workflow_id": offer.workflow_id,
            "sample_only": offer.sample_only,
            "execution_method": offer.execution_method,
            **result.to_dict(),
        }

    def dismiss(self, proposal_id: str) -> bool:
        return self.router.dismiss(proposal_id)

    def prepare_named(self, workflow_id: str, frame: ContextFrame) -> Offer:
        """Install an explicit-invoke offer. Does not submit or evaluate."""
        adapter = self.registry.get(workflow_id)
        preparation = adapter.prepare(frame)
        offer = build_action_offer(frame, adapter.descriptor, preparation, self.clock())
        return self.router.install_offer(frame, offer)

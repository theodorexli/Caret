"""The flight workflow, registered and deliberately unavailable.

It exists so the catalog can state a boundary instead of hiding it. Booking a
flight means driving a checkout in a browser, and the only browser executor in
this project is Skyvern. An execution that stops before payment has to be
stopped by something that cannot be talked out of it: a provider-side URL
allowlist and a run that has no payment step. A prompt that says "stop before
payment" is text the page can argue with, so it is not a guard and this adapter
does not accept it as one.

Until such a capability is configured and verified, ``availability`` is false
with that reason, the judge is never offered this workflow, and ``prepare`` and
``execute`` raise rather than improvising a lesser effect. There is no network
call and no browser session in this module.
"""

from __future__ import annotations

from ..context import ContextFrame
from ..registry import (
    Availability,
    ExecutionResult,
    Preparation,
    WorkflowDescriptor,
    WorkflowError,
)

WORKFLOW_ID = "book-flight"

UNAVAILABLE_REASON = (
    "Flight booking is unavailable: no Skyvern capability is configured whose URL "
    "allowlist and pre-payment stop are enforced by the runner itself. A prompt "
    "instructing the agent to stop before payment is not an execution guard, so no "
    "browser run is offered and no purchase can be reached."
)


class SkyvernFlightWorkflow:
    """Skyvern-only flight booking. Reports why it cannot run, and does not run.

    Takes no constructor arguments, so the registry's adapter factory can build
    it. It holds no credentials and opens no session.
    """

    @property
    def descriptor(self) -> WorkflowDescriptor:
        return WorkflowDescriptor(
            id=WORKFLOW_ID,
            name="Book a flight",
            description=(
                "Search and hold a flight through a Skyvern browser run. Unavailable "
                "until an enforcing Skyvern capability is configured."
            ),
            required_inputs=(
                "a Skyvern run whose URL allowlist and pre-payment stop are enforced by the runner",
            ),
            execution_method="skyvern_browser",
            sample_only=False,
        )

    def availability(self, frame: ContextFrame) -> Availability:
        return Availability(False, UNAVAILABLE_REASON)

    def prepare(self, frame: ContextFrame) -> Preparation:
        raise WorkflowError(UNAVAILABLE_REASON)

    def execute(self, frame: ContextFrame, preparation: Preparation) -> ExecutionResult:
        raise WorkflowError(UNAVAILABLE_REASON)

    def cancel(self, preparation: Preparation) -> ExecutionResult:
        return ExecutionResult(status="cancelled", summary="Nothing was prepared.")


def build() -> SkyvernFlightWorkflow:
    """Zero-argument factory for ``--adapter caret.live_workflows.flight:build``."""
    return SkyvernFlightWorkflow()


__all__ = ["SkyvernFlightWorkflow", "UNAVAILABLE_REASON", "WORKFLOW_ID", "build"]

"""Which of Teddy's menu actions correspond to a registered workflow.

The action IDs are the ones declared in
``apps/mac/Sources/Caret/CaretApp.swift`` (``CaretApp.actions``). They are read
here, not redefined: this table is a mapping, and a Swift-side rename has to be
reflected by editing the Swift declaration and this table together.

An action mapped to ``None`` has no workflow adapter. Those actions are text
transforms served by the inline writer path, so routing one to the workflow
registry would look up an ID that is not registered. ``workflow_for_action``
raises on an unknown ID rather than returning ``None``, so a typo and a
deliberate "no workflow" stay distinguishable.
"""

from __future__ import annotations

from . import flight, meeting

ACTION_WORKFLOWS: dict[str, str | None] = {
    "book-flight": flight.WORKFLOW_ID,
    "book-calendar-link": meeting.WORKFLOW_ID,
    "revise": None,
    "summarize": None,
    "translate": None,
    "follow-up": None,
    "extract-tasks": None,
    "tone-polite": None,
}

ADAPTER_CLASS_PATHS: dict[str, str] = {
    meeting.WORKFLOW_ID: "caret.live_workflows:MeetingDraftWorkflow",
    flight.WORKFLOW_ID: "caret.live_workflows:SkyvernFlightWorkflow",
}
"""The ``--adapter`` arguments the bridge is to be given, as the core owner
stated them. The package re-exports both classes, so the submodule paths
resolve to the same objects."""


def workflow_for_action(action_id: str) -> str | None:
    """The workflow ID for a declared action, or None when it has no adapter."""
    try:
        return ACTION_WORKFLOWS[action_id]
    except KeyError:
        known = ", ".join(sorted(ACTION_WORKFLOWS))
        raise KeyError(f"'{action_id}' is not a declared Caret action; known actions: {known}") from None


def adapters() -> tuple:
    """One instance of each adapter this package registers."""
    return (meeting.MeetingDraftWorkflow(), flight.SkyvernFlightWorkflow())


__all__ = ["ACTION_WORKFLOWS", "ADAPTER_CLASS_PATHS", "adapters", "workflow_for_action"]

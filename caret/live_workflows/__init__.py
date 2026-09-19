"""Workflow adapters that run on the caller's live context.

Two adapters plug into ``caret.registry``: a draft-only meeting workflow
(:mod:`~caret.live_workflows.meeting`, ``book-calendar-link``) and a flight
workflow (:mod:`~caret.live_workflows.flight`, ``book-flight``) that reports why
it cannot run. :mod:`~caret.live_workflows.actions` maps the Mac app's action
IDs onto those two. See docs/live-workflow-adapters.md.

The adapter classes are re-exported here, so ``--adapter
caret.live_workflows:MeetingDraftWorkflow`` resolves, but they are resolved on
attribute access rather than at import. ``extraction`` and ``request`` read text
and depend on nothing outside this package; keeping the package import free of
``caret.registry`` and ``caret.context`` means those two stay importable, and
their tests stay runnable, on a checkout that does not carry the core yet.
"""

from __future__ import annotations

_LAZY = {
    "MeetingDraftWorkflow": "meeting",
    "SkyvernFlightWorkflow": "flight",
    "ACTION_WORKFLOWS": "actions",
    "ADAPTER_CLASS_PATHS": "actions",
    "adapters": "actions",
    "workflow_for_action": "actions",
}

__all__ = sorted(_LAZY)


def __getattr__(name: str):
    if name not in _LAZY:
        raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
    module = __import__(f"{__name__}.{_LAZY[name]}", fromlist=[name])
    value = getattr(module, name)
    globals()[name] = value
    return value


def __dir__() -> list[str]:
    return sorted(set(globals()) | set(_LAZY))

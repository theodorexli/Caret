"""Test support for the adapters, including how the shared core is located.

``caret.registry`` and ``caret.context`` belong to another worktree and are not
on this branch yet. Rather than copying them, :func:`require_core` appends that
worktree's ``caret`` directory to ``caret.__path__``, so ``caret.registry``
resolves there while everything else still resolves here. Point
``CARET_CORE_REFERENCE`` at the checkout that has them:

    CARET_CORE_REFERENCE=/path/to/Caret-context-judge \\
        python3 -m unittest discover -s tests -v

Once the core is merged, the plain import succeeds and the variable is ignored.
If neither is true the tests skip with that explanation, because a green run
that silently skipped the seam would be worse than a red one.
"""

from __future__ import annotations

import importlib
import json
import os
import unittest
from pathlib import Path

import caret

CORE_MODULES = ("caret.context", "caret.registry")
REFERENCE_VARIABLE = "CARET_CORE_REFERENCE"


def _core_directory(raw: str) -> Path | None:
    root = Path(raw).expanduser()
    for candidate in (root, root / "caret"):
        if (candidate / "registry.py").is_file() and (candidate / "context.py").is_file():
            return candidate
    return None


def require_core():
    """Import the shared core, extending ``caret.__path__`` if it is elsewhere."""
    try:
        return tuple(importlib.import_module(name) for name in CORE_MODULES)
    except ImportError:
        pass
    raw = (os.environ.get(REFERENCE_VARIABLE) or "").strip()
    if not raw:
        raise unittest.SkipTest(
            "caret.registry and caret.context are not on this branch. Set "
            f"{REFERENCE_VARIABLE} to a checkout that has them to run the adapter tests."
        )
    directory = _core_directory(raw)
    if directory is None:
        raise unittest.SkipTest(
            f"{REFERENCE_VARIABLE}={raw} holds no caret/registry.py and caret/context.py"
        )
    if str(directory) not in caret.__path__:
        caret.__path__.append(str(directory))
    importlib.invalidate_caches()
    try:
        return tuple(importlib.import_module(name) for name in CORE_MODULES)
    except ImportError as error:
        raise unittest.SkipTest(f"{REFERENCE_VARIABLE}={raw} could not be imported: {error}")


def frame(
    text: str,
    revision: int = 7,
    captured_at: str = "2026-09-19T12:00:00+00:00",
    secure: bool = False,
    accessibility: bool = True,
    element_revision: str = "v7",
):
    """A ContextFrame carrying ``text`` as the window around the caret."""
    from caret.context import ContextFrame, InputSnapshot, Permissions, TargetIdentity, utf16_length

    caret_offset = utf16_length(text)
    return ContextFrame(
        snapshot=InputSnapshot(
            revision=revision,
            captured_at=__import__("datetime").datetime.fromisoformat(captured_at),
            target=TargetIdentity(
                pid=4242,
                bundle_id="com.example.Editor",
                window_id="w1",
                element_id="compose",
                element_revision=element_revision,
            ),
            role="AXTextArea",
            nearby_text=text,
            text_offset=0,
            caret=caret_offset,
            selection_start=caret_offset,
            selection_end=caret_offset,
            secure=secure,
            value_length=caret_offset,
        ),
        permissions=Permissions(accessibility=accessibility),
    )


class RecordingTransport:
    """Stands in for the HTTPS POST. Records every call; sends nothing."""

    def __init__(self, status: int = 200, payload=None, body: bytes | None = None, error=None):
        self.status = status
        self.body = body if body is not None else json.dumps(payload or {}).encode("utf-8")
        self.error = error
        self.calls: list[dict] = []

    def __call__(self, url, body, headers, timeout):
        self.calls.append(
            {
                "url": url,
                "body": json.loads(body.decode("utf-8")),
                "headers": dict(headers),
                "timeout": timeout,
            }
        )
        if self.error is not None:
            raise self.error
        return self.status, self.body


def freebusy_payload(time_min: str, time_max: str, calendars: dict) -> dict:
    """A reply shaped like Google's, for the mock transport to return."""
    return {"kind": "calendar#freeBusy", "timeMin": time_min, "timeMax": time_max, "calendars": calendars}

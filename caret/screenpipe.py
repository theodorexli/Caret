"""Pinned Screenpipe artifact, launcher lease, and last-N history."""

from __future__ import annotations

import json
import os
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path

PIN_PATH = Path(__file__).with_name("screenpipe_pin.json")
DEFAULT_LEASE_PATH = Path(".local/screenpipe-lease.json")

# AppKit NSAccessibility.Role.description(with:) plus Screenpipe OCR "block".
ROLE_LABELS = {
    "AXButton": "button",
    "AXRadioButton": "radio button",
    "AXCheckBox": "checkbox",
    "AXPopUpButton": "pop up button",
    "AXStaticText": "text",
    "AXTextArea": "text entry area",
    "AXTextField": "text field",
    "AXHeading": "heading",
    "block": "text block",
}


def load_pin() -> dict:
    pin = json.loads(PIN_PATH.read_text())
    required = (
        "artifact_id",
        "version",
        "obtain",
        "launch",
        "expected_health_version",
        "lease_fields",
    )
    missing = [key for key in required if key not in pin]
    if missing:
        raise ValueError(f"screenpipe pin missing {missing}")
    if pin["version"] != pin["expected_health_version"]:
        raise ValueError("pin version must match expected_health_version")
    launch_text = " ".join(pin["launch"]) + pin["obtain"]
    if "packages/screenpipe" in launch_text:
        raise ValueError("pin must not launch the git source tree")
    return pin


def load_lease(path: Path | None = None) -> dict:
    pin = load_pin()
    lease_path = path or DEFAULT_LEASE_PATH
    if not lease_path.is_file():
        raise ValueError(f"screenpipe lease missing: {lease_path}")
    lease = json.loads(lease_path.read_text())
    missing = [key for key in pin["lease_fields"] if key not in lease]
    if missing:
        raise ValueError(f"screenpipe lease missing {missing}")
    if lease["expected_version"] != pin["expected_health_version"]:
        raise ValueError("screenpipe lease version is not the pin")
    if lease["artifact_id"] != pin["artifact_id"]:
        raise ValueError("screenpipe lease artifact is not the pin")
    return lease


_discovered_token: str | None = None


def _discover_token() -> str:
    """Return the local API token from the pinned ``screenpipe auth token`` CLI."""
    global _discovered_token
    if _discovered_token:
        return _discovered_token
    pin = load_pin()
    package = pin.get("package", "screenpipe")
    version = pin["version"]
    env = os.environ.copy()
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + env.get("PATH", "")
    try:
        completed = subprocess.run(
            ["npx", "-y", "--package", f"{package}@{version}", "screenpipe", "auth", "token"],
            capture_output=True,
            text=True,
            timeout=60,
            env=env,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValueError("screenpipe API token unavailable") from error
    token = (completed.stdout or "").strip()
    if completed.returncode != 0 or not token:
        raise ValueError("screenpipe API token unavailable")
    _discovered_token = token
    return token


def _local_api_token() -> str:
    """Return the pinned Screenpipe local API bearer token.

    Screenpipe 0.4.50 has no localhost bypass: protected endpoints such as
    ``/search`` return HTTP 403 unless the request carries this token.
    ``/health`` stays unauthenticated.
    """
    for name in ("SCREENPIPE_LOCAL_API_KEY", "SCREENPIPE_API_KEY"):
        value = (os.environ.get(name) or "").strip()
        if value:
            return value
    token = _discover_token()
    if not token:
        raise ValueError("screenpipe API token unavailable")
    return token


def _api_headers() -> dict[str, str]:
    """Return headers required by Screenpipe 0.4.50 protected HTTP calls."""
    return {
        "Authorization": f"Bearer {_local_api_token()}",
        "X-Screenpipe-Client": "api",
    }


def _api(lease: dict, path: str, params: dict | None = None) -> dict:
    query = urllib.parse.urlencode({k: v for k, v in (params or {}).items() if v is not None})
    url = lease["endpoint"].rstrip("/") + path + (f"?{query}" if query else "")
    headers = _api_headers()
    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as error:
        raise ValueError(f"screenpipe unreachable: {error}") from error


def _label(role: str) -> str:
    if role in ROLE_LABELS:
        return ROLE_LABELS[role]
    return role[2:].lower() if role.startswith("AX") else (role or "unknown")


def _structure(lease: dict, frame_id) -> tuple[list[dict] | None, str | None]:
    if frame_id is None:
        return None, None
    try:
        payload = _api(lease, f"/frames/{frame_id}/elements", {"source": "accessibility"})
    except ValueError:
        return None, None
    rows = payload.get("data") or []
    if not rows:
        return None, None
    structure = []
    for item in rows[:80]:
        structure.append(
            {
                "role": item.get("role"),
                "label": _label(item.get("role") or ""),
                "text": item.get("text") or "",
                "depth": item.get("depth"),
            }
        )
    return structure, "accessibility"


def _record(lease: dict, item: dict, include_structure: bool = True) -> dict:
    content = item.get("content") or {}
    frame_id = content.get("frame_id") or content.get("id")
    structure, source = (None, None)
    if include_structure:
        structure, source = _structure(lease, frame_id)
    return {
        "timestamp": content.get("timestamp"),
        "app": content.get("app_name") or "",
        "title": content.get("window_name") or "",
        "text_source": content.get("text_source") or item.get("type"),
        "structure_source": source,
        "structure": structure,
        "text": content.get("text") or "",
    }


def _require_health(lease: dict) -> None:
    health = _api(lease, "/health")
    version = health.get("version")
    if version != lease["expected_version"]:
        raise ValueError(f"screenpipe version {version!r} is not the pin")
    if health.get("status") not in {"healthy", "ok"}:
        raise ValueError("screenpipe is not healthy")


def last_n_minutes(
    minutes: int,
    lease_path: Path | None = None,
    include_structure: bool = True,
    record_cap: int | None = None,
) -> dict:
    if minutes < 1:
        raise ValueError("minutes must be >= 1")
    lease = load_lease(lease_path)
    _require_health(lease)
    start = (datetime.now().astimezone() - timedelta(minutes=minutes)).isoformat(timespec="seconds")
    payload = _api(lease, "/search", {"limit": 200, "content_type": "all", "start_time": start, "order": "descending"})
    items = payload.get("data") or []
    if record_cap is not None:
        items = items[:record_cap]
    records = [_record(lease, item, include_structure=include_structure) for item in items]
    if not records:
        raise ValueError("no screenpipe history in the requested minutes")
    return {"kind": "minutes", "n": minutes, "records": records}


def last_n_windows(
    count: int,
    lease_path: Path | None = None,
    include_structure: bool = True,
) -> dict:
    if count < 1:
        raise ValueError("windows must be >= 1")
    lease = load_lease(lease_path)
    _require_health(lease)
    payload = _api(lease, "/search", {"limit": 200, "content_type": "all", "order": "descending"})
    seen = []
    keys = set()
    for item in payload.get("data") or []:
        content = item.get("content") or {}
        key = ((content.get("app_name") or "").strip(), (content.get("window_name") or "").strip())
        if not any(key) or key in keys:
            continue
        keys.add(key)
        seen.append(item)
        if len(seen) == count:
            break
    if len(seen) < count:
        raise ValueError("not enough distinct screenpipe windows")
    return {
        "kind": "windows",
        "n": count,
        "records": [_record(lease, item, include_structure=include_structure) for item in seen],
    }


def _snippet(record: dict, snippet_chars: int) -> dict:
    text = record.get("text") or ""
    if len(text) > snippet_chars:
        text = text[:snippet_chars]
    return {
        "app": record.get("app") or "",
        "title": record.get("title") or "",
        "timestamp": record.get("timestamp"),
        "text": text,
    }


def debug_preview(lease_path: Path | None = None, n: int = 2, snippet_chars: int = 80) -> dict:
    """Last-n snippets of windows, minutes, and clipboard. Per-slice errors stay in the payload."""
    loaders = (
        ("windows", lambda: last_n_windows(n, lease_path, include_structure=False)),
        ("minutes", lambda: last_n_minutes(n, lease_path, include_structure=False, record_cap=n)),
        ("clipboard", lambda: last_n_clipboard(n, lease_path)),
    )
    sections: dict[str, dict] = {}
    for kind, loader in loaders:
        try:
            payload = loader()
            sections[kind] = {
                "ok": True,
                "items": [_snippet(record, snippet_chars) for record in payload["records"][:n]],
            }
        except ValueError as error:
            sections[kind] = {"ok": False, "error": str(error), "items": []}
    return {"n": n, **sections}

def last_n_clipboard(count: int, lease_path: Path | None = None) -> dict:
    if count < 1:
        raise ValueError("count must be >= 1")
    lease = load_lease(lease_path)
    _require_health(lease)
    payload = _api(lease, "/search", {"limit": 200, "content_type": "input", "order": "descending"})
    records = []
    for item in payload.get("data") or []:
        content = item.get("content") or {}
        if content.get("event_type") != "clipboard":
            continue
        records.append(
            {
                "timestamp": content.get("timestamp"),
                "app": content.get("app_name") or "",
                "title": content.get("window_title") or "",
                "text_source": "clipboard",
                "structure_source": None,
                "structure": None,
                "text": content.get("text_content") or "",
            }
        )
        if len(records) == count:
            break
    if len(records) < count:
        raise ValueError("no screenpipe clipboard history")
    return {"kind": "clipboard", "n": count, "records": records}

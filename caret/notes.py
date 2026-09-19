"""Markdown notes with YAML frontmatter for Caret skills and memories."""

from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n(.*)\Z", re.DOTALL)


def notes_root(repo_root: Path | None = None) -> Path:
    base = repo_root if repo_root is not None else Path(__file__).resolve().parent
    return base / "notes"


def _skills_dir(repo_root: Path | None = None) -> Path:
    return notes_root(repo_root) / "skills"


def _memories_dir(repo_root: Path | None = None) -> Path:
    return notes_root(repo_root) / "memories"


def _parse_simple_yaml(block: str) -> dict[str, Any]:
    data: dict[str, Any] = {}
    current_list_key: str | None = None
    for raw_line in block.splitlines():
        line = raw_line.rstrip()
        if not line.strip():
            continue
        if line.startswith("  - ") and current_list_key:
            data.setdefault(current_list_key, []).append(line[4:].strip())
            continue
        current_list_key = None
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if not value:
            current_list_key = key
            data[key] = []
            continue
        if value.startswith("[") and value.endswith("]"):
            inner = value[1:-1].strip()
            data[key] = [part.strip().strip("'\"") for part in inner.split(",") if part.strip()] if inner else []
        else:
            data[key] = value.strip("'\"")
    return data


def parse_note(path: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    match = _FRONTMATTER_RE.match(text)
    if match:
        meta = _parse_simple_yaml(match.group(1))
        body = match.group(2).strip()
    else:
        meta = {}
        body = text.strip()

    title = str(meta.get("title", "")).strip() or path.stem.replace("-", " ").title()
    icon = str(meta.get("icon", "doc.text")).strip() or "doc.text"
    updated_raw = str(meta.get("updated", "")).strip()
    updated_at = _parse_updated(updated_raw, path)
    apps_raw = meta.get("apps", [])
    if isinstance(apps_raw, str):
        apps = [apps_raw]
    elif isinstance(apps_raw, list):
        apps = [str(item).strip() for item in apps_raw if str(item).strip()]
    else:
        apps = []

    return {
        "id": path.stem,
        "title": title,
        "icon": icon,
        "updated_at": updated_at.isoformat(),
        "apps": apps,
        "body": body,
        "path": str(path),
    }


def _parse_updated(value: str, path: Path) -> datetime:
    if value:
        normalized = value.replace("Z", "+00:00")
        try:
            return datetime.fromisoformat(normalized)
        except ValueError:
            pass
    mtime = path.stat().st_mtime
    return datetime.fromtimestamp(mtime, tz=timezone.utc)


def _list_notes(directory: Path) -> list[dict[str, Any]]:
    if not directory.is_dir():
        return []
    notes = [parse_note(path) for path in sorted(directory.glob("*.md"))]
    notes.sort(key=lambda item: item["title"].casefold())
    return notes


def list_skill_notes(repo_root: Path | None = None) -> list[dict[str, Any]]:
    return _list_notes(_skills_dir(repo_root))


def list_memory_notes(repo_root: Path | None = None) -> list[dict[str, Any]]:
    return _list_notes(_memories_dir(repo_root))


def skill_note_icon(action_id: str, repo_root: Path | None = None) -> str:
    path = _skills_dir(repo_root) / f"{action_id}.md"
    if path.is_file():
        return str(parse_note(path)["icon"])
    return "sparkle"

"""Markdown notes with YAML frontmatter for Caret skills and memories."""

from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n(.*)\Z", re.DOTALL)

ACTION_SKILL_ICONS: dict[str, str] = {
    "book-flight": "airplane",
    "book-calendar-link": "calendar",
    "follow-up": "envelope",
    "revise": "pencil",
    "summarize": "list.bullet",
    "translate": "character.book.closed",
    "extract-tasks": "checklist",
    "tone-polite": "hand.wave",
}


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


def _iso_now() -> str:
    return datetime.now(tz=timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def write_note(
    path: Path,
    *,
    title: str,
    icon: str,
    body: str,
    apps: list[str] | None = None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "---",
        f"title: {title}",
        f"icon: {icon}",
        f"updated: {_iso_now()}",
    ]
    if apps:
        lines.append("apps:")
        lines.extend(f"  - {app}" for app in apps)
    lines.extend(["---", body.rstrip(), ""])
    path.write_text("\n".join(lines), encoding="utf-8")


def save_skill_note(
    action_id: str,
    *,
    title: str,
    icon: str,
    body: str,
    apps: list[str] | None = None,
    repo_root: Path | None = None,
) -> dict[str, Any]:
    path = _skills_dir(repo_root) / f"{action_id}.md"
    write_note(path, title=title, icon=icon, body=body, apps=apps)
    return parse_note(path)


def save_memory_note(
    note_id: str,
    *,
    title: str,
    icon: str,
    body: str,
    apps: list[str] | None = None,
    repo_root: Path | None = None,
) -> dict[str, Any]:
    slug = note_id.strip().lower().replace(" ", "-")
    path = _memories_dir(repo_root) / f"{slug}.md"
    write_note(path, title=title, icon=icon, body=body, apps=apps)
    return parse_note(path)


def ensure_action_skill_notes(
    actions: list[tuple[str, str]],
    repo_root: Path | None = None,
) -> list[str]:
    created: list[str] = []
    skills_dir = _skills_dir(repo_root)
    skills_dir.mkdir(parents=True, exist_ok=True)
    for action_id, title in actions:
        path = skills_dir / f"{action_id}.md"
        if path.is_file():
            continue
        icon = ACTION_SKILL_ICONS.get(action_id, "sparkle")
        write_note(
            path,
            title=title,
            icon=icon,
            body=f"Instructions for the **{title}** action.\n",
        )
        created.append(action_id)
    return created


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
    return ACTION_SKILL_ICONS.get(action_id, "sparkle")

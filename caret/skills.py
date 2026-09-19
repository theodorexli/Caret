"""Load, filter, and create on-disk skills scoped to a workflow action id."""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

SKILLS_DIR_NAME = "skills"


def skills_root(repo_root: Path | None = None) -> Path:
    base = repo_root if repo_root is not None else Path(__file__).resolve().parent
    return base / SKILLS_DIR_NAME


def _skill_path(root: Path, action_id: str, skill_id: str) -> Path:
    return root / action_id / f"{skill_id}.json"


def _read_skill(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"skill file must be a JSON object: {path}")
    name = str(data.get("name", "")).strip()
    if not name:
        raise ValueError(f"skill missing name: {path}")
    return {
        "id": path.stem,
        "action_id": path.parent.name,
        "name": name,
        "description": str(data.get("description", "")).strip(),
    }


def list_action_ids(repo_root: Path | None = None) -> list[str]:
    root = skills_root(repo_root)
    if not root.is_dir():
        return []
    return sorted(path.name for path in root.iterdir() if path.is_dir())


def list_skills(action_id: str, repo_root: Path | None = None) -> list[dict[str, Any]]:
    action_dir = skills_root(repo_root) / action_id
    if not action_dir.is_dir():
        return []
    skills: list[dict[str, Any]] = []
    for path in sorted(action_dir.glob("*.json"), key=lambda item: item.stem):
        skills.append(_read_skill(path))
    return skills


def filter_skills(action_id: str, query: str, repo_root: Path | None = None) -> list[dict[str, Any]]:
    needle = query.strip().casefold()
    skills = list_skills(action_id, repo_root=repo_root)
    if not needle:
        return skills
    return [
        skill
        for skill in skills
        if needle in skill["name"].casefold() or needle in skill["description"].casefold()
    ]


_SLUG_RE = re.compile(r"[^a-z0-9]+")


def slugify(text: str) -> str:
    slug = _SLUG_RE.sub("-", text.strip().casefold()).strip("-")
    return slug or "skill"


def create_skill(
    action_id: str,
    name: str,
    *,
    description: str = "",
    repo_root: Path | None = None,
    skill_id: str | None = None,
) -> dict[str, Any]:
    title = name.strip()
    if not title:
        raise ValueError("skill name is required")
    root = skills_root(repo_root)
    action_dir = root / action_id
    action_dir.mkdir(parents=True, exist_ok=True)
    slug = skill_id or slugify(title)
    base = slug
    path = _skill_path(root, action_id, slug)
    counter = 2
    while path.exists():
        slug = f"{base}-{counter}"
        path = _skill_path(root, action_id, slug)
        counter += 1
    payload = {"name": title, "description": description.strip()}
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return _read_skill(path)

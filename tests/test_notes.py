import tempfile
import unittest
from pathlib import Path

from caret.notes import (
    ACTION_SKILL_ICONS,
    ensure_action_skill_notes,
    list_memory_notes,
    list_skill_notes,
    parse_note,
    save_memory_note,
    save_skill_note,
    skill_note_icon,
    write_note,
)


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_parse_note_frontmatter_and_body(self):
        path = self.root / "sample.md"
        path.write_text(
            """---
title: Book flight
icon: airplane
updated: 2026-09-19T18:00:00Z
apps:
  - Slack
  - Mail
---
Prefer nonstop Austin to Dallas.
Use United when price is close.
""",
            encoding="utf-8",
        )
        note = parse_note(path)
        self.assertEqual(note["id"], "sample")
        self.assertEqual(note["title"], "Book flight")
        self.assertEqual(note["icon"], "airplane")
        self.assertEqual(note["apps"], ["Slack", "Mail"])
        self.assertIn("nonstop", note["body"])

    def test_list_skill_notes_sorted_by_title(self):
        skills_dir = self.root / "notes" / "skills"
        skills_dir.mkdir(parents=True)
        (skills_dir / "z-last.md").write_text("---\ntitle: Zeta\nicon: z.circle\n---\n", encoding="utf-8")
        (skills_dir / "book-flight.md").write_text(
            "---\ntitle: Book flight\nicon: airplane\n---\n",
            encoding="utf-8",
        )
        titles = [n["title"] for n in list_skill_notes(repo_root=self.root)]
        self.assertEqual(titles, ["Book flight", "Zeta"])

    def test_skill_note_icon_uses_action_default_without_file(self):
        self.assertEqual(skill_note_icon("book-flight", repo_root=self.root), ACTION_SKILL_ICONS["book-flight"])

    def test_write_and_save_skill_note(self):
        note = save_skill_note(
            "revise",
            title="Revise draft",
            icon="pencil",
            body="Keep my voice.",
            repo_root=self.root,
        )
        self.assertEqual(note["id"], "revise")
        path = self.root / "notes" / "skills" / "revise.md"
        self.assertTrue(path.is_file())
        reread = parse_note(path)
        self.assertEqual(reread["body"], "Keep my voice.")

    def test_save_skill_note_persists_apps(self):
        note = save_skill_note(
            "book-flight",
            title="Book flight",
            icon="airplane",
            body="Search nonstop first.",
            apps=["Slack", "Safari"],
            repo_root=self.root,
        )
        self.assertEqual(note["apps"], ["Slack", "Safari"])
        path = self.root / "notes" / "skills" / "book-flight.md"
        self.assertEqual(parse_note(path)["apps"], ["Slack", "Safari"])

    def test_ensure_action_skill_notes_creates_missing_only(self):
        skills_dir = self.root / "notes" / "skills"
        skills_dir.mkdir(parents=True)
        (skills_dir / "summarize.md").write_text("---\ntitle: Summarize\nicon: list.bullet\n---\n", encoding="utf-8")
        created = ensure_action_skill_notes(
            [
                ("summarize", "Summarize"),
                ("translate", "Translate"),
            ],
            repo_root=self.root,
        )
        self.assertEqual(created, ["translate"])
        self.assertTrue((skills_dir / "translate.md").is_file())

    def test_save_memory_note(self):
        note = save_memory_note(
            "prefs",
            title="Preferences",
            icon="person.crop.circle",
            body="Short sentences.",
            apps=["Slack"],
            repo_root=self.root,
        )
        self.assertEqual(note["apps"], ["Slack"])
        self.assertEqual(len(list_memory_notes(repo_root=self.root)), 1)

    def test_write_note_roundtrip(self):
        path = self.root / "notes" / "memories" / "a.md"
        write_note(
            path,
            title="A",
            icon="star",
            body="Body",
            apps=["Mail"],
        )
        parsed = parse_note(path)
        self.assertEqual(parsed["title"], "A")
        self.assertEqual(parsed["apps"], ["Mail"])


if __name__ == "__main__":
    unittest.main()

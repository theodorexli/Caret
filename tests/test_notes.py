import tempfile
import unittest
from pathlib import Path

from caret.notes import list_memory_notes, list_skill_notes, parse_note, skill_note_icon


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

    def test_skill_note_icon_fallback(self):
        self.assertEqual(skill_note_icon("book-flight", repo_root=self.root), "sparkle")


if __name__ == "__main__":
    unittest.main()

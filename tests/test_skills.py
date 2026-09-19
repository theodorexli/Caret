import json
import tempfile
import unittest
from pathlib import Path

from caret.skills import create_skill, filter_skills, list_skills, skills_root, slugify


class SkillsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_list_and_filter_skills(self):
        action = "summarize"
        skills_dir = skills_root(self.root) / action
        skills_dir.mkdir(parents=True)
        (skills_dir / "bullets.json").write_text(
            json.dumps({"name": "Bullet summary", "description": "Short bullets"}),
            encoding="utf-8",
        )
        (skills_dir / "paragraph.json").write_text(
            json.dumps({"name": "One paragraph", "description": "Single block"}),
            encoding="utf-8",
        )
        self.assertEqual(len(list_skills(action, repo_root=self.root)), 2)
        filtered = filter_skills(action, "bullet", repo_root=self.root)
        self.assertEqual([item["id"] for item in filtered], ["bullets"])

    def test_create_skill_writes_unique_slug(self):
        create_skill("revise", "Polite tone", repo_root=self.root)
        create_skill("revise", "Polite tone", repo_root=self.root)
        ids = [item["id"] for item in list_skills("revise", repo_root=self.root)]
        self.assertEqual(ids, ["polite-tone", "polite-tone-2"])

    def test_slugify(self):
        self.assertEqual(slugify("  Hello World! "), "hello-world")


if __name__ == "__main__":
    unittest.main()

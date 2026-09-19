"""Caret.xcodeproj stays readable by xcodebuild."""

from collections import Counter
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PBXPROJ = ROOT / "Caret.xcodeproj" / "project.pbxproj"

OBJECT_START = re.compile(
    r"^\t\t([0-9A-F]{24}) /\* .+ \*/ = \{(?:isa = ([A-Za-z]+);)?"
)
ISA_LINE = re.compile(r"^\t\t\tisa = ([A-Za-z]+);")
FILE_ENTRY = re.compile(r"^\t\t\t\t([0-9A-F]{24}) ")


def load_objects(text: str) -> dict[str, str]:
    objects: dict[str, str] = {}
    current_id: str | None = None
    pending_isa = False
    for line in text.splitlines():
        start = OBJECT_START.match(line)
        if start:
            current_id = start.group(1)
            if start.group(2):
                objects[current_id] = start.group(2)
                pending_isa = False
            else:
                pending_isa = True
            continue
        if pending_isa and current_id is not None:
            isa = ISA_LINE.match(line)
            if isa:
                objects[current_id] = isa.group(1)
                pending_isa = False
    return objects


def sources_file_ids(text: str) -> list[str]:
    ids: list[str] = []
    in_sources = False
    in_files = False
    for line in text.splitlines():
        if "isa = PBXSourcesBuildPhase;" in line:
            in_sources = True
            in_files = False
            continue
        if in_sources and line.strip() == "files = (":
            in_files = True
            continue
        if in_files:
            if line.strip() == ");":
                in_files = False
                in_sources = False
                continue
            match = FILE_ENTRY.match(line)
            if match:
                ids.append(match.group(1))
    return ids


class XcodeprojTests(unittest.TestCase):
    def setUp(self):
        self.text = PBXPROJ.read_text(encoding="utf-8")

    def test_object_ids_are_unique(self):
        """Each objects-dictionary key must appear once.

        Xcode refuses the project when one ID is both a PBXBuildFile and a
        PBXFileReference, which is what broke `make install`.
        """
        ids = [
            match.group(1)
            for line in self.text.splitlines()
            if (match := OBJECT_START.match(line))
        ]
        duplicates = [item for item, count in Counter(ids).items() if count > 1]
        self.assertEqual(duplicates, [], f"duplicate pbxproj object IDs: {duplicates}")

    def test_sources_phase_files_are_build_files(self):
        """Every Sources `files` entry must be a PBXBuildFile.

        A FileRef in that list is the exact xcodebuild error from the
        B100…55 collision (SettingsMainMenu vs Info.plist).
        """
        objects = load_objects(self.text)
        for file_id in sources_file_ids(self.text):
            with self.subTest(file_id=file_id):
                self.assertIn(file_id, objects)
                self.assertEqual(objects[file_id], "PBXBuildFile")

import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from caret.screenpipe import debug_preview, load_pin


def _lease(directory: str) -> Path:
    pin = load_pin()
    path = Path(directory) / "lease.json"
    path.write_text(
        json.dumps(
            {
                "artifact_id": pin["artifact_id"],
                "checksum": "test",
                "expected_version": pin["expected_health_version"],
                "endpoint": "http://127.0.0.1:3030",
                "pid": 1,
                "ready_at": "2026-09-19T12:00:00-05:00",
            }
        )
    )
    return path


def _ocr(app: str, window: str, text: str, timestamp: str, frame_id: int = 1) -> dict:
    return {
        "type": "OCR",
        "content": {
            "frame_id": frame_id,
            "timestamp": timestamp,
            "app_name": app,
            "window_name": window,
            "text": text,
            "text_source": "accessibility",
        },
    }


def _clip(app: str, title: str, text: str, timestamp: str) -> dict:
    return {
        "type": "Input",
        "content": {
            "event_type": "clipboard",
            "timestamp": timestamp,
            "app_name": app,
            "window_title": title,
            "text_content": text,
        },
    }


class HistoryDebugTests(unittest.TestCase):
    def test_preview_returns_two_truncated_items_per_slice(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)
            long_text = "x" * 120

            def fake_api(_lease, path, params=None):
                if path == "/health":
                    return {"status": "healthy", "version": "0.4.50"}
                if path.endswith("/elements"):
                    raise AssertionError("debug preview must not hydrate accessibility structure")
                if (params or {}).get("content_type") == "input":
                    return {
                        "data": [
                            _clip("Safari", "Inbox", "newer copy", "2026-09-19T12:02:00-05:00"),
                            _clip("Cursor", "hackathon", "older copy", "2026-09-19T12:01:00-05:00"),
                        ]
                    }
                return {
                    "data": [
                        _ocr("Safari", "Inbox", long_text, "2026-09-19T12:02:00-05:00", 2),
                        _ocr("Cursor", "hackathon", "hello", "2026-09-19T12:01:00-05:00", 1),
                    ]
                }

            with patch("caret.screenpipe._api", side_effect=fake_api):
                result = debug_preview(lease, n=2, snippet_chars=80)

            self.assertEqual(result["n"], 2)
            for kind in ("windows", "minutes", "clipboard"):
                self.assertTrue(result[kind]["ok"], result[kind])
                self.assertEqual(len(result[kind]["items"]), 2)
                for item in result[kind]["items"]:
                    self.assertEqual(set(item), {"app", "title", "timestamp", "text"})
                    self.assertNotIn("structure", item)
                    self.assertLessEqual(len(item["text"]), 80)
            self.assertEqual(result["windows"]["items"][0]["app"], "Safari")
            self.assertEqual(result["windows"]["items"][0]["title"], "Inbox")
            self.assertEqual(result["windows"]["items"][0]["text"], "x" * 80)
            self.assertEqual(result["clipboard"]["items"][0]["text"], "newer copy")

    def test_preview_caps_minutes_at_two(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)

            def fake_api(_lease, path, params=None):
                if path == "/health":
                    return {"status": "healthy", "version": "0.4.50"}
                if path.endswith("/elements"):
                    return {"data": []}
                if (params or {}).get("content_type") == "input":
                    return {
                        "data": [
                            _clip("Safari", "Inbox", "a", "2026-09-19T12:02:00-05:00"),
                            _clip("Cursor", "hackathon", "b", "2026-09-19T12:01:00-05:00"),
                        ]
                    }
                return {
                    "data": [
                        _ocr("A", "one", "1", "2026-09-19T12:03:00-05:00"),
                        _ocr("B", "two", "2", "2026-09-19T12:02:00-05:00"),
                        _ocr("C", "three", "3", "2026-09-19T12:01:00-05:00"),
                    ]
                }

            with patch("caret.screenpipe._api", side_effect=fake_api):
                result = debug_preview(lease, n=2)

            self.assertEqual(
                [(row["app"], row["title"]) for row in result["minutes"]["items"]],
                [("A", "one"), ("B", "two")],
            )

    def test_preview_keeps_other_slices_when_one_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)

            def fake_api(_lease, path, params=None):
                if path == "/health":
                    return {"status": "healthy", "version": "0.4.50"}
                if path.endswith("/elements"):
                    return {"data": []}
                if (params or {}).get("content_type") == "input":
                    return {"data": []}
                return {
                    "data": [
                        _ocr("Safari", "Inbox", "a", "2026-09-19T12:02:00-05:00"),
                        _ocr("Cursor", "hackathon", "b", "2026-09-19T12:01:00-05:00"),
                    ]
                }

            with patch("caret.screenpipe._api", side_effect=fake_api):
                result = debug_preview(lease, n=2)

            self.assertTrue(result["windows"]["ok"])
            self.assertTrue(result["minutes"]["ok"])
            self.assertFalse(result["clipboard"]["ok"])
            self.assertEqual(result["clipboard"]["items"], [])
            self.assertIn("clipboard", result["clipboard"]["error"])

    def test_preview_reports_lease_errors_per_slice(self):
        missing = Path("/tmp/caret-no-such-lease.json")
        result = debug_preview(missing, n=2)
        self.assertEqual(result["n"], 2)
        for kind in ("windows", "minutes", "clipboard"):
            self.assertFalse(result[kind]["ok"])
            self.assertEqual(result[kind]["items"], [])
            self.assertIn("lease missing", result[kind]["error"])

    def test_history_debug_cli_prints_json(self):
        from caret.__main__ import main

        payload = {
            "n": 2,
            "windows": {"ok": False, "error": "lease missing", "items": []},
            "minutes": {"ok": False, "error": "lease missing", "items": []},
            "clipboard": {"ok": False, "error": "lease missing", "items": []},
        }
        buffer = io.StringIO()
        with patch("sys.argv", ["caret", "history-debug", "--lease", "/tmp/missing.json"]):
            with patch("caret.__main__.debug_preview", return_value=payload):
                with patch("sys.stdout", buffer):
                    code = main()
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(buffer.getvalue()), payload)


if __name__ == "__main__":
    unittest.main()

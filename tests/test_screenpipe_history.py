import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from caret.screenpipe import last_n_clipboard, last_n_minutes, last_n_windows, load_pin


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


class ScreenpipeHistoryTests(unittest.TestCase):
    def test_missing_lease_is_hard_fail(self):
        with self.assertRaisesRegex(ValueError, "lease missing"):
            last_n_minutes(3, Path("/tmp/caret-no-such-lease.json"))

    def test_empty_minutes_is_hard_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)

            def fake_api(_lease, path, params=None):
                if path == "/health":
                    return {"status": "healthy", "version": "0.4.50"}
                return {"data": []}

            with patch("caret.screenpipe._api", side_effect=fake_api):
                with self.assertRaisesRegex(ValueError, "no screenpipe history"):
                    last_n_minutes(3, lease)

    def test_minutes_returns_records(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)

            def fake_api(_lease, path, params=None):
                if path == "/health":
                    return {"status": "healthy", "version": "0.4.50"}
                if path.endswith("/elements"):
                    return {"data": [{"role": "AXButton", "text": "OK", "depth": 1}]}
                return {
                    "data": [
                        {
                            "type": "OCR",
                            "content": {
                                "frame_id": 2,
                                "timestamp": "2026-09-19T12:01:00-05:00",
                                "app_name": "Cursor",
                                "window_name": "newer",
                                "text": "hi",
                                "text_source": "accessibility",
                            },
                        },
                        {
                            "type": "OCR",
                            "content": {
                                "frame_id": 1,
                                "timestamp": "2026-09-19T12:00:00-05:00",
                                "app_name": "Cursor",
                                "window_name": "hackathon",
                                "text": "hello",
                                "text_source": "accessibility",
                            },
                        },
                    ]
                }

            with patch("caret.screenpipe._api", side_effect=fake_api):
                result = last_n_minutes(3, lease)
            self.assertEqual(result["kind"], "minutes")
            self.assertEqual([row["title"] for row in result["records"]], ["newer", "hackathon"])
            self.assertEqual(result["records"][0]["structure"][0]["label"], "button")

    def test_windows_are_newest_active_first(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)

            def fake_api(_lease, path, params=None):
                if path == "/health":
                    return {"status": "healthy", "version": "0.4.50"}
                if path.endswith("/elements"):
                    return {"data": []}
                return {
                    "data": [
                        {
                            "type": "OCR",
                            "content": {
                                "app_name": "Safari",
                                "window_name": "Inbox",
                                "text": "a",
                                "timestamp": "2026-09-19T12:02:00-05:00",
                            },
                        },
                        {
                            "type": "OCR",
                            "content": {
                                "app_name": "Cursor",
                                "window_name": "hackathon",
                                "text": "b",
                                "timestamp": "2026-09-19T12:01:00-05:00",
                            },
                        },
                    ]
                }

            with patch("caret.screenpipe._api", side_effect=fake_api):
                result = last_n_windows(2, lease)
            self.assertEqual(
                [(row["app"], row["title"]) for row in result["records"]],
                [("Safari", "Inbox"), ("Cursor", "hackathon")],
            )

    def test_clipboard_returns_newest_first(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)

            def fake_api(_lease, path, params=None):
                if path == "/health":
                    return {"status": "healthy", "version": "0.4.50"}
                return {
                    "data": [
                        {
                            "type": "Input",
                            "content": {
                                "event_type": "clipboard",
                                "timestamp": "2026-09-19T12:02:00-05:00",
                                "app_name": "Safari",
                                "window_title": "Inbox",
                                "text_content": "newer copy",
                            },
                        },
                        {
                            "type": "Input",
                            "content": {"event_type": "click", "text_content": "ignored"},
                        },
                        {
                            "type": "Input",
                            "content": {
                                "event_type": "clipboard",
                                "timestamp": "2026-09-19T12:01:00-05:00",
                                "app_name": "Cursor",
                                "window_title": "hackathon",
                                "text_content": "older copy",
                            },
                        },
                    ]
                }

            with patch("caret.screenpipe._api", side_effect=fake_api):
                result = last_n_clipboard(2, lease)
            self.assertEqual(result["kind"], "clipboard")
            self.assertEqual([row["text"] for row in result["records"]], ["newer copy", "older copy"])

    def test_wrong_version_is_hard_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            lease = _lease(directory)

            def fake_api(_lease, path, params=None):
                return {"status": "healthy", "version": "9.9.9"}

            with patch("caret.screenpipe._api", side_effect=fake_api):
                with self.assertRaisesRegex(ValueError, "is not the pin"):
                    last_n_windows(1, lease)


if __name__ == "__main__":
    unittest.main()

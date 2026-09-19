import os
import unittest
from io import BytesIO
from unittest.mock import patch

from caret.screenpipe import _api


def _headers(captured: dict) -> dict[str, str]:
    return {key.lower(): value for key, value in captured["headers"].items()}


class ScreenpipeApiAuthTests(unittest.TestCase):
    def test_api_sends_local_key_and_client_header(self):
        """Protected last-N calls must send Bearer SCREENPIPE_LOCAL_API_KEY and X-Screenpipe-Client: api."""
        captured = {}

        def fake_urlopen(request, timeout=0):
            captured["headers"] = dict(request.header_items())
            return BytesIO(b'{"status":"ok"}')

        lease = {"endpoint": "http://127.0.0.1:3031"}
        with patch.dict(os.environ, {"SCREENPIPE_LOCAL_API_KEY": "local-token"}, clear=True):
            with patch("caret.screenpipe.urllib.request.urlopen", fake_urlopen):
                payload = _api(lease, "/search", {"limit": 1})

        self.assertEqual(payload, {"status": "ok"})
        headers = _headers(captured)
        self.assertEqual(headers["authorization"], "Bearer local-token")
        self.assertEqual(headers["x-screenpipe-client"], "api")

    def test_api_falls_back_to_screenpipe_api_key(self):
        """SCREENPIPE_API_KEY is accepted when SCREENPIPE_LOCAL_API_KEY is unset."""
        captured = {}

        def fake_urlopen(request, timeout=0):
            captured["headers"] = dict(request.header_items())
            return BytesIO(b'{"status":"ok"}')

        lease = {"endpoint": "http://127.0.0.1:3031"}
        with patch.dict(os.environ, {"SCREENPIPE_API_KEY": "legacy-token"}, clear=True):
            with patch("caret.screenpipe.urllib.request.urlopen", fake_urlopen):
                _api(lease, "/search")

        headers = _headers(captured)
        self.assertEqual(headers["authorization"], "Bearer legacy-token")
        self.assertEqual(headers["x-screenpipe-client"], "api")

    def test_api_discovers_token_when_env_empty(self):
        """Caret.app Debug has no env key; discover via screenpipe auth token."""
        captured = {}

        def fake_urlopen(request, timeout=0):
            captured["headers"] = dict(request.header_items())
            return BytesIO(b'{"status":"ok"}')

        lease = {"endpoint": "http://127.0.0.1:3031"}
        with patch.dict(os.environ, {}, clear=True):
            with patch("caret.screenpipe._discover_token", return_value="discovered-token"):
                with patch("caret.screenpipe.urllib.request.urlopen", fake_urlopen):
                    _api(lease, "/search")

        headers = _headers(captured)
        self.assertEqual(headers["authorization"], "Bearer discovered-token")
        self.assertEqual(headers["x-screenpipe-client"], "api")

    def test_api_fails_when_token_unavailable(self):
        """Do not call Screenpipe without a token; that is the 403."""
        called = {"urlopen": False}

        def fake_urlopen(request, timeout=0):
            called["urlopen"] = True
            return BytesIO(b'{"status":"ok"}')

        lease = {"endpoint": "http://127.0.0.1:3031"}
        with patch.dict(os.environ, {}, clear=True):
            with patch("caret.screenpipe._discover_token", side_effect=ValueError("screenpipe API token unavailable")):
                with patch("caret.screenpipe.urllib.request.urlopen", fake_urlopen):
                    with self.assertRaisesRegex(ValueError, "API token unavailable"):
                        _api(lease, "/search")
        self.assertFalse(called["urlopen"])

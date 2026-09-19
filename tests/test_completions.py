import json
import os
import unittest
from io import BytesIO
from unittest.mock import patch

from caret.completions import (
    DEFAULT_MODEL,
    CompletionError,
    complete,
    complete_text,
    gateway_api_key,
    parse_completion_response,
)


class CompletionsTests(unittest.TestCase):
    def test_gateway_api_key_prefers_vercel_env(self):
        with patch.dict(os.environ, {"VERCEL_API_GATEWAY_KEY": "vercel-key", "AI_GATEWAY_API_KEY": "other"}, clear=True):
            self.assertEqual(gateway_api_key(), "vercel-key")

    def test_gateway_api_key_missing_raises(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(CompletionError):
                gateway_api_key()

    def test_parse_completion_response_extracts_text(self):
        payload = {
            "choices": [{"message": {"role": "assistant", "content": "Hello there"}}],
            "usage": {"prompt_tokens": 3, "completion_tokens": 2, "total_tokens": 5},
        }
        result = parse_completion_response(payload)
        self.assertEqual(result.text, "Hello there")
        self.assertEqual(result.model, DEFAULT_MODEL)
        self.assertEqual(result.usage["total_tokens"], 5)

    def test_complete_posts_openai_compatible_request(self):
        response_body = json.dumps(
            {
                "model": "google/gemini-2.5-flash",
                "choices": [{"message": {"role": "assistant", "content": "Done"}}],
                "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
            }
        ).encode("utf-8")

        captured = {}

        def fake_urlopen(request, timeout=0):
            captured["url"] = request.full_url
            captured["headers"] = dict(request.header_items())
            captured["body"] = json.loads(request.data.decode("utf-8"))
            return BytesIO(response_body)

        with patch.dict(os.environ, {"VERCEL_API_GATEWAY_KEY": "test-key"}, clear=True):
            with patch("caret.completions.urlopen", fake_urlopen):
                result = complete_text("Say done", system="You are terse.")

        self.assertEqual(result, "Done")
        self.assertEqual(captured["url"], "https://ai-gateway.vercel.sh/v1/chat/completions")
        self.assertEqual(captured["headers"]["Authorization"], "Bearer test-key")
        self.assertEqual(captured["body"]["model"], DEFAULT_MODEL)
        self.assertFalse(captured["body"]["stream"])
        self.assertEqual(
            captured["body"]["messages"],
            [
                {"role": "system", "content": "You are terse."},
                {"role": "user", "content": "Say done"},
            ],
        )

    def test_complete_http_error_raises_completion_error(self):
        import urllib.error

        def fake_urlopen(_request, timeout=0):
            raise urllib.error.HTTPError(
                url="https://ai-gateway.vercel.sh/v1/chat/completions",
                code=401,
                msg="Unauthorized",
                hdrs=None,
                fp=BytesIO(b'{"error":"bad key"}'),
            )

        with patch.dict(os.environ, {"VERCEL_API_GATEWAY_KEY": "bad"}, clear=True):
            with patch("caret.completions.urlopen", fake_urlopen):
                with self.assertRaises(CompletionError) as ctx:
                    complete([{"role": "user", "content": "hi"}])
        self.assertIn("401", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()

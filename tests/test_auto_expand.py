import unittest

from caret.auto_expand import normalize_continuation, build_auto_expand_messages


class AutoExpandTests(unittest.TestCase):
    def test_build_auto_expand_messages_includes_prefix(self):
        messages = build_auto_expand_messages(
            prefix="Thanks for the update—",
            instructions="Continue in a warm professional tone.",
        )
        self.assertEqual(messages[0]["role"], "system")
        self.assertIn("warm professional", messages[0]["content"])
        self.assertEqual(messages[1]["role"], "user")
        self.assertIn("Thanks for the update", messages[1]["content"])

    def test_normalize_strips_wrapping_quotes_and_prefix_repeat(self):
        self.assertEqual(
            normalize_continuation('  "I\'ll follow up Monday."  ', "I'll follow"),
            " up Monday.",
        )

    def test_normalize_empty_when_only_repeats_prefix(self):
        self.assertEqual(
            normalize_continuation("Thanks for the update", "Thanks for the update"),
            "",
        )


if __name__ == "__main__":
    unittest.main()

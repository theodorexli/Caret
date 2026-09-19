import unittest

from caret.auto_expand import (
    build_auto_expand_messages,
    complete_auto_expand,
    normalize_continuation,
    pattern_completion_suffix,
    should_offer_tab_completion,
)
from unittest.mock import patch


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

    def test_pattern_completion_from_numbered_instruction(self):
        instructions = (
            "General guidance here.\n\n"
            "1. please pull github and rebase and push to github\n"
        )
        self.assertEqual(
            pattern_completion_suffix("please p", instructions),
            "ull github and rebase and push to github",
        )
        self.assertEqual(
            pattern_completion_suffix("please pull github", instructions),
            " and rebase and push to github",
        )
        self.assertEqual(
            pattern_completion_suffix(
                "please pull github and rebase and push to github",
                instructions,
            ),
            "",
        )

    def test_complete_auto_expand_uses_pattern_without_model(self):
        instructions = "1. please pull github and rebase and push to github"
        with patch("caret.auto_expand.complete_text") as mock_complete:
            result = complete_auto_expand(prefix="please p", instructions=instructions)
        self.assertEqual(result, "ull github and rebase and push to github")
        mock_complete.assert_not_called()

    def test_should_offer_without_triggers_needs_min_length(self):
        self.assertFalse(should_offer_tab_completion("a", "Continue naturally."))
        self.assertFalse(should_offer_tab_completion("hel", "Continue naturally."))
        self.assertTrue(should_offer_tab_completion("hello", "Continue naturally."))

    def test_pattern_requires_five_characters(self):
        instructions = "1. please pull github and rebase and push to github"
        self.assertEqual(pattern_completion_suffix("ple", instructions), "")
        self.assertTrue(pattern_completion_suffix("pleas", instructions).startswith("e"))

    def test_should_offer_honors_when_triggers(self):
        instructions = 'When email: Thanks for'
        self.assertTrue(should_offer_tab_completion("Thanks for", instructions))
        self.assertFalse(should_offer_tab_completion("Hello", instructions))

    def test_normalize_empty_when_only_repeats_prefix(self):
        self.assertEqual(
            normalize_continuation("Thanks for the update", "Thanks for the update"),
            "",
        )


if __name__ == "__main__":
    unittest.main()

import unittest

from caret.screenpipe import load_pin


class ScreenpipePinTests(unittest.TestCase):
    def test_pin_names_published_cli_and_lease_fields(self):
        pin = load_pin()
        self.assertEqual(pin["version"], "0.4.50")
        self.assertEqual(pin["expected_health_version"], "0.4.50")
        self.assertIn("npx", pin["obtain"])
        self.assertEqual(pin["launch"][0], "npx")
        self.assertIn("screenpipe@0.4.50", pin["launch"])
        self.assertEqual(
            pin["lease_fields"],
            ["artifact_id", "checksum", "expected_version", "endpoint", "pid", "ready_at"],
        )
        self.assertNotIn("892199f", pin["obtain"])
        self.assertNotIn("packages/screenpipe", pin["launch"])


if __name__ == "__main__":
    unittest.main()

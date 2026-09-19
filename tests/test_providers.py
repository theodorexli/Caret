"""Provider request shaping and response parsing, with the transport faked.

No network call happens here and no API key is read. The fake stands in for
`post_json` so the tests can assert exactly what Caret sends and exactly how it
reacts to a malformed or failing answer.
"""

import json
import unittest
from unittest import mock

from caret.engine import ProviderFailure
from caret.judge import JudgeError, describe_frame, frame_state, route_question, workflow_question
from caret.judge import Choice
from caret.providers import gateway as gateway_module
from caret.providers import groq as groq_module
from caret.providers import jev as jev_module
from caret.providers.gateway import GatewayJudge, GatewayWriter
from caret.providers.groq import GroqWriter
from caret.providers.http import ProviderHTTPError
from caret.providers.jev import JevJudge
from support import frame


def jev_answer(choice, question_key="route", confidence=0.8):
    return {
        "model": "jev-1.13.0",
        "answers": {question_key: {"type": "choice", "choice": choice, "confidence": confidence}},
        "usage": {"input_tokens": 300, "output_tokens": 12},
    }


def groq_answer(content):
    return {
        "id": "chatcmpl-test",
        "choices": [{"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}],
        "usage": {"prompt_tokens": 20, "completion_tokens": 5, "total_tokens": 25},
    }


class JevRequestTests(unittest.TestCase):
    def test_the_request_matches_the_pinned_upstream_wire_shape(self):
        judge = JevJudge(api_key="test-key", model="jev-latest")
        captured = {}

        def fake_post(url, payload, headers, timeout):
            captured.update(url=url, payload=payload, headers=headers, timeout=timeout)
            return jev_answer("INLINE")

        with mock.patch.object(jev_module, "post_json", fake_post):
            verdict = judge.choose(route_question(), frame(1))

        self.assertEqual(captured["url"], "https://api.typesafe.ai/v1/systemone")
        self.assertEqual(captured["headers"]["Authorization"], "Bearer test-key")
        self.assertEqual(captured["payload"]["model"], "jev-latest")
        question = captured["payload"]["questions"]["route"]
        self.assertEqual(question["type"], "choice")
        self.assertEqual(set(question["criteria"]), {"ABSTAIN", "INLINE", "ACTION"})
        self.assertEqual(verdict.choice_id, "INLINE")
        self.assertEqual(verdict.model, "jev-1.13.0")

    def test_the_state_carries_context_and_marks_absent_sources(self):
        judge = JevJudge(api_key="test-key")
        captured = {}
        with mock.patch.object(jev_module, "post_json", lambda u, p, h, t: captured.update(p=p) or jev_answer("ABSTAIN")):
            judge.choose(route_question(), frame(1, clipboard=False))
        state = captured["p"]["state"]
        self.assertEqual(state["clipboard"], {"available": False}, "an absent clipboard is stated, not omitted")
        self.assertEqual(state["application"]["bundle_id"], "com.example.SyntheticEditor")
        self.assertIn("I will send the ", state["field"]["text_before_caret"])
        self.assertEqual(len(state["history"]), 1)

    def test_workflow_criteria_are_exactly_the_supplied_choice_ids(self):
        judge = JevJudge(api_key="test-key")
        captured = {}
        question = workflow_question((Choice("book-calendar-link", "Propose times"),))
        with mock.patch.object(
            jev_module, "post_json", lambda u, p, h, t: captured.update(p=p) or jev_answer("NONE", "workflow")
        ):
            judge.choose(question, frame(1))
        self.assertEqual(
            set(captured["p"]["questions"]["workflow"]["criteria"]), {"book-calendar-link", "NONE"}
        )

    def test_an_api_key_is_required(self):
        with self.assertRaisesRegex(JudgeError, "API key is required"):
            JevJudge(api_key="")


class JevResponseTests(unittest.TestCase):
    def setUp(self):
        self.judge = JevJudge(api_key="test-key")

    def reject(self, body, pattern):
        with mock.patch.object(jev_module, "post_json", lambda *a, **k: body):
            with self.assertRaisesRegex(JudgeError, pattern):
                self.judge.choose(route_question(), frame(1))

    def test_a_missing_answers_object_is_refused(self):
        self.reject({"model": "jev-1"}, "no answer for 'route'")

    def test_an_answer_for_the_wrong_question_is_refused(self):
        self.reject(jev_answer("INLINE", "something-else"), "no answer for 'route'")

    def test_a_non_choice_answer_type_is_refused(self):
        self.reject({"answers": {"route": {"type": "noul", "noul": 0.9}}}, "expected 'choice'")

    def test_a_choice_outside_our_own_options_is_refused(self):
        self.reject(jev_answer("rm -rf /"), "not one of")

    def test_a_null_choice_is_refused(self):
        self.reject({"answers": {"route": {"type": "choice", "choice": None}}}, "expected a choice ID string")

    def test_an_http_failure_becomes_a_judge_error(self):
        def boom(*args, **kwargs):
            raise ProviderHTTPError("HTTP 401 from api.typesafe.ai: bad key", 401)

        with mock.patch.object(jev_module, "post_json", boom):
            with self.assertRaisesRegex(JudgeError, "401"):
                self.judge.choose(route_question(), frame(1))

    def test_confidence_is_recorded_but_does_not_gate_the_answer(self):
        with mock.patch.object(jev_module, "post_json", lambda *a, **k: jev_answer("ACTION", confidence=0.02)):
            verdict = self.judge.choose(route_question(), frame(1))
        self.assertEqual(verdict.choice_id, "ACTION", "a low confidence is reported, not enforced")
        self.assertIn("0.02", verdict.reason)


class GroqTests(unittest.TestCase):
    def setUp(self):
        self.writer = GroqWriter(api_key="test-key")

    def test_the_request_matches_the_documented_chat_completions_shape(self):
        captured = {}

        def fake_post(url, payload, headers, timeout):
            captured.update(url=url, payload=payload, headers=headers)
            return groq_answer(" the team")

        with mock.patch.object(groq_module, "post_json", fake_post):
            text = self.writer.complete(frame(1), "continue")

        self.assertEqual(captured["url"], "https://api.groq.com/openai/v1/chat/completions")
        self.assertEqual(captured["headers"]["Authorization"], "Bearer test-key")
        self.assertEqual(captured["payload"]["model"], "openai/gpt-oss-20b")
        self.assertIn("max_completion_tokens", captured["payload"])
        self.assertNotIn("max_tokens", captured["payload"], "max_tokens is deprecated in favour of max_completion_tokens")
        self.assertFalse(captured["payload"]["stream"])
        self.assertEqual([m["role"] for m in captured["payload"]["messages"]], ["system", "user"])
        self.assertEqual(text, " the team")

    def test_the_default_model_is_not_one_of_the_shut_down_llama_ids(self):
        self.assertNotIn("llama", groq_module.DEFAULT_MODEL)

    def reject(self, body, pattern):
        with mock.patch.object(groq_module, "post_json", lambda *a, **k: body):
            with self.assertRaisesRegex(ProviderFailure, pattern):
                self.writer.complete(frame(1), "continue")

    def test_a_response_without_choices_is_refused(self):
        self.reject({"id": "x"}, "no choices")

    def test_a_choice_without_a_message_is_refused(self):
        self.reject({"choices": [{"index": 0}]}, "no message object")

    def test_non_string_content_is_refused(self):
        self.reject({"choices": [{"message": {"content": {"text": "hi"}}}]}, "expected a string")

    def test_an_empty_completion_is_refused_rather_than_offered(self):
        self.reject(groq_answer("   \n  "), "no usable completion")

    def test_an_http_failure_becomes_a_provider_failure(self):
        def boom(*args, **kwargs):
            raise ProviderHTTPError("HTTP 429 from api.groq.com: rate limit", 429)

        with mock.patch.object(groq_module, "post_json", boom):
            with self.assertRaisesRegex(ProviderFailure, "429"):
                self.writer.complete(frame(1), "continue")

    def test_an_exhausted_budget_with_no_text_names_the_budget(self):
        body = groq_answer("")
        body["choices"][0]["finish_reason"] = "length"
        self.reject(body, "finish_reason=length")

    def test_the_default_budget_covers_a_reasoning_model(self):
        self.assertGreaterEqual(self.writer.client.max_output_tokens, 512)

    def test_a_leading_newline_is_dropped_but_a_leading_space_is_kept(self):
        with mock.patch.object(groq_module, "post_json", lambda *a, **k: groq_answer("\n the team \n")):
            self.assertEqual(self.writer.complete(frame(1), "continue"), " the team")

    def test_an_api_key_is_required(self):
        with self.assertRaisesRegex(ProviderFailure, "API key is required"):
            GroqWriter(api_key="")


def gateway_answer(content, model="amazon/nova-micro"):
    """The documented non-streaming AI Gateway success body."""
    return {
        "id": "chatcmpl-test",
        "object": "chat.completion",
        "created": 1789000000,
        "model": model,
        "choices": [
            {"index": 0, "message": {"role": "assistant", "content": content}, "finish_reason": "stop"}
        ],
        "usage": {"prompt_tokens": 300, "completion_tokens": 12, "total_tokens": 312},
    }


class GatewayWriterTests(unittest.TestCase):
    def setUp(self):
        self.writer = GatewayWriter(api_key="test-key")

    def test_the_request_matches_the_documented_gateway_shape(self):
        captured = {}

        def fake_post(url, payload, headers, timeout):
            captured.update(url=url, payload=payload, headers=headers)
            return gateway_answer(" the team")

        with mock.patch.object(gateway_module, "post_json", fake_post):
            text = self.writer.complete(frame(1), "continue")

        self.assertEqual(captured["url"], "https://ai-gateway.vercel.sh/v1/chat/completions")
        self.assertEqual(captured["headers"]["Authorization"], "Bearer test-key")
        self.assertEqual(captured["payload"]["model"], "amazon/nova-micro")
        self.assertIn(
            "max_tokens",
            captured["payload"],
            "Vercel's parameter reference documents max_tokens",
        )
        self.assertNotIn(
            "max_completion_tokens",
            captured["payload"],
            "Vercel does not list max_completion_tokens as a request parameter",
        )
        self.assertNotIn(
            "response_format", captured["payload"], "the writer asks for prose, not JSON"
        )
        self.assertFalse(captured["payload"]["stream"])
        self.assertEqual([m["role"] for m in captured["payload"]["messages"]], ["system", "user"])
        self.assertEqual(text, " the team")

    def test_an_empty_completion_is_refused_rather_than_offered(self):
        with mock.patch.object(gateway_module, "post_json", lambda *a, **k: gateway_answer("  \n ")):
            with self.assertRaisesRegex(ProviderFailure, "no usable completion"):
                self.writer.complete(frame(1), "continue")

    def test_an_api_key_is_required(self):
        with self.assertRaisesRegex(ProviderFailure, "API key is required"):
            GatewayWriter(api_key="")


class GatewayJudgeTests(unittest.TestCase):
    """The Gateway judge is an LLM classifier, so every answer is rechecked
    against Caret's own choice IDs before it becomes a verdict."""

    def setUp(self):
        self.judge = GatewayJudge(api_key="test-key")

    def ask(self, body, question=None):
        captured = {}

        def fake_post(url, payload, headers, timeout):
            captured.update(url=url, payload=payload, headers=headers)
            return body

        with mock.patch.object(gateway_module, "post_json", fake_post):
            verdict = self.judge.choose(question or route_question(), frame(1))
        return captured, verdict

    def test_the_request_asks_for_a_schema_whose_enum_is_our_choice_ids(self):
        captured, verdict = self.ask(
            gateway_answer('{"choice": "INLINE", "reason": "mid-sentence continuation"}')
        )
        response_format = captured["payload"]["response_format"]
        self.assertEqual(response_format["type"], "json_schema")
        schema = response_format["json_schema"]["schema"]
        self.assertEqual(schema["properties"]["choice"]["enum"], ["ABSTAIN", "INLINE", "ACTION"])
        self.assertEqual(sorted(schema["required"]), ["choice", "reason"])
        self.assertFalse(schema["additionalProperties"])
        self.assertEqual(captured["url"], "https://ai-gateway.vercel.sh/v1/chat/completions")
        self.assertEqual(verdict.choice_id, "INLINE")
        self.assertEqual(verdict.reason, "mid-sentence continuation")
        self.assertEqual(verdict.model, "amazon/nova-micro")

    def test_the_key_travels_only_in_the_authorization_header(self):
        captured, _ = self.ask(gateway_answer('{"choice": "ABSTAIN", "reason": "nothing to add"}'))
        self.assertNotIn("test-key", json.dumps(captured["payload"]))

    def test_the_workflow_question_carries_its_own_enum(self):
        question = workflow_question((Choice("book-calendar-link", "Propose times"),))
        captured, verdict = self.ask(
            gateway_answer('{"choice": "NONE", "reason": "no listed workflow fits"}'), question
        )
        schema = captured["payload"]["response_format"]["json_schema"]["schema"]
        self.assertEqual(schema["properties"]["choice"]["enum"], ["book-calendar-link", "NONE"])
        self.assertEqual(verdict.choice_id, "NONE")

    def reject(self, content, pattern):
        with mock.patch.object(gateway_module, "post_json", lambda *a, **k: gateway_answer(content)):
            with self.assertRaisesRegex(JudgeError, pattern):
                self.judge.choose(route_question(), frame(1))

    def test_a_choice_outside_the_supplied_ids_is_refused(self):
        self.reject('{"choice": "SEND_THE_EMAIL", "reason": "seemed useful"}', "not one of")

    def test_content_that_is_not_json_is_refused(self):
        self.reject("I think INLINE is best here", "not JSON")

    def test_markdown_fenced_json_is_refused_rather_than_unwrapped(self):
        self.reject('```json\n{"choice": "INLINE", "reason": "x"}\n```', "not JSON")

    def test_a_json_value_that_is_not_an_object_is_refused(self):
        self.reject('["INLINE"]', "expected an object")

    def test_a_missing_choice_field_is_refused(self):
        self.reject('{"reason": "forgot to choose"}', "expected a choice ID string")

    def test_a_non_string_choice_is_refused(self):
        self.reject('{"choice": 1, "reason": "second option"}', "expected a choice ID string")

    def test_an_http_failure_becomes_a_judge_error(self):
        def boom(*args, **kwargs):
            raise ProviderHTTPError("HTTP 404 from ai-gateway.vercel.sh: unknown model", 404)

        with mock.patch.object(gateway_module, "post_json", boom):
            with self.assertRaisesRegex(JudgeError, "404"):
                self.judge.choose(route_question(), frame(1))

    def test_an_api_key_is_required(self):
        with self.assertRaisesRegex(JudgeError, "API key is required"):
            GatewayJudge(api_key="")


class CaretSplitTests(unittest.TestCase):
    """Caret offsets are UTF-16 code units, so an astral character before the
    caret must not move the split that a provider is shown."""

    def setUp(self):
        self.frame = frame(1, text="a\U0001f30ab", caret=3)

    def test_the_structured_state_splits_at_the_utf16_caret(self):
        field = frame_state(self.frame)["field"]
        self.assertEqual(field["text_before_caret"], "a\U0001f30a")
        self.assertEqual(field["text_after_caret"], "b")

    def test_the_prose_description_splits_at_the_utf16_caret(self):
        described = describe_frame(self.frame)
        self.assertIn("Text before caret: 'a\U0001f30a'", described)
        self.assertIn("Text after caret: 'b'", described)


class TransportTests(unittest.TestCase):
    def test_every_request_names_the_client_in_its_user_agent(self):
        from caret.providers import http as http_module

        seen = {}

        class FakeResponse:
            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def read(self):
                return b"{}"

        def fake_urlopen(request, timeout):
            seen["ua"] = request.get_header("User-agent")
            return FakeResponse()

        with mock.patch.object(http_module.urllib.request, "urlopen", fake_urlopen):
            http_module.post_json("https://example.invalid/x", {}, {}, 1.0)
        self.assertTrue(seen["ua"].startswith("caret-core/"), seen["ua"])
        self.assertNotIn("Python-urllib", seen["ua"], "the default agent is blocked by Cloudflare at api.groq.com")


class ConfigurationTests(unittest.TestCase):
    """A missing key is an error. It never quietly becomes a canned answer."""

    def test_jev_without_a_key_refuses_rather_than_mocking(self):
        with mock.patch.dict("os.environ", {"TYPESAFE_API_KEY": ""}, clear=False):
            with self.assertRaisesRegex(JudgeError, "TYPESAFE_API_KEY is not set"):
                JevJudge.from_env()

    def test_groq_without_a_key_refuses_rather_than_mocking(self):
        with mock.patch.dict("os.environ", {"GROQ_API_KEY": ""}, clear=False):
            with self.assertRaisesRegex(ProviderFailure, "GROQ_API_KEY is not set"):
                GroqWriter.from_env()

    def test_the_gateway_judge_without_a_key_refuses_rather_than_mocking(self):
        with mock.patch.dict("os.environ", {"AI_GATEWAY_API_KEY": ""}, clear=False):
            with self.assertRaisesRegex(JudgeError, "AI_GATEWAY_API_KEY is not set"):
                GatewayJudge.from_env()

    def test_the_gateway_writer_without_a_key_refuses_rather_than_mocking(self):
        with mock.patch.dict("os.environ", {"AI_GATEWAY_API_KEY": ""}, clear=False):
            with self.assertRaisesRegex(ProviderFailure, "AI_GATEWAY_API_KEY is not set"):
                GatewayWriter.from_env()

    def test_an_error_message_never_contains_the_key(self):
        judge = JevJudge(api_key="secret-value-do-not-leak")

        def boom(*args, **kwargs):
            raise ProviderHTTPError("HTTP 401 from api.typesafe.ai: unauthorized", 401)

        with mock.patch.object(jev_module, "post_json", boom):
            with self.assertRaises(JudgeError) as caught:
                judge.choose(route_question(), frame(1))
        self.assertNotIn("secret-value-do-not-leak", str(caught.exception))

    def test_a_gateway_error_message_never_contains_the_key(self):
        judge = GatewayJudge(api_key="gateway-secret-do-not-leak")

        def boom(*args, **kwargs):
            raise ProviderHTTPError("HTTP 401 from ai-gateway.vercel.sh: unauthorized", 401)

        with mock.patch.object(gateway_module, "post_json", boom):
            with self.assertRaises(JudgeError) as caught:
                judge.choose(route_question(), frame(1))
        self.assertNotIn("gateway-secret-do-not-leak", str(caught.exception))


if __name__ == "__main__":
    unittest.main()

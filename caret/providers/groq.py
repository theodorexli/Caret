"""Groq writer preset for inline text. Jev classifies; this writes.

The request and response handling is :mod:`caret.providers.openai_chat`; this
module is the Groq-specific configuration.

Wire contract (POST https://api.groq.com/openai/v1/chat/completions, bearer auth),
per https://console.groq.com/docs/api-reference#chat-create and
https://console.groq.com/docs/text-chat:

    {"model": "...", "messages": [{"role": "system"|"user", "content": "..."}],
     "temperature": 0.2, "max_completion_tokens": 512, "stream": false}
    -> {"choices": [{"index": 0, "message": {"role": "assistant", "content": "..."},
                     "finish_reason": "stop"}], "usage": {...}}

Errors come back as ``{"error": {"message": ..., "type": ...}}`` with 401 for a
bad key and 429 for a rate limit (https://console.groq.com/docs/errors).

Default model: ``openai/gpt-oss-20b``. Groq's models page lists it at the
highest throughput among current production text models, and unlike
``llama-3.1-8b-instant`` and ``llama-3.3-70b-versatile`` it is absent from the
deprecations page, which gives both Llama IDs a 2026-08-16 shutdown date
(https://console.groq.com/docs/models, https://groq.com/docs/deprecations,
read 2026-09-19). Groq publishes throughput but not time-to-first-token, so
this is a documented-throughput choice, not a measured latency result for
Caret's inputs. Override it with ``GROQ_MODEL`` once latency is measured here.
"""

from __future__ import annotations

import os

from ..context import ContextFrame
from ..engine import ProviderFailure
from .http import post_json
from .openai_chat import (
    MAX_COMPLETION_TOKENS_FIELD,
    ChatError,
    OpenAIChatClient,
    inline_completion,
)

DEFAULT_ENDPOINT = "https://api.groq.com/openai/v1/chat/completions"
DEFAULT_MODEL = "openai/gpt-oss-20b"
API_KEY_ENV = "GROQ_API_KEY"
ENDPOINT_ENV = "GROQ_ENDPOINT"
MODEL_ENV = "GROQ_MODEL"


class GroqWriter:
    """Real Groq client. Construct it only when a key is configured.

    Configuration lives on :attr:`client`.
    """

    def __init__(
        self,
        api_key: str,
        model: str = DEFAULT_MODEL,
        endpoint: str = DEFAULT_ENDPOINT,
        timeout: float = 4.0,
        max_completion_tokens: int = 512,
        temperature: float = 0.2,
    ) -> None:
        """``max_completion_tokens`` is 512, not the 64 an inline edit needs,
        because ``openai/gpt-oss-20b`` is a reasoning model and the budget
        covers its hidden reasoning as well as the visible text. Observed
        2026-09-19 with a live key: at 64 every reply finished with
        ``finish_reason="length"``, 258 reasoning characters and empty content;
        at 512 the same prompt returned text in 0.53 s using 176 tokens. The
        visible edit is still bounded separately by ``MAX_INLINE_UNITS``."""
        if not api_key:
            raise ProviderFailure(f"A Groq API key is required; set {API_KEY_ENV}")
        self.client = OpenAIChatClient(
            service="Groq",
            endpoint=endpoint,
            api_key=api_key,
            model=model,
            timeout=timeout,
            max_output_tokens=max_completion_tokens,
            # Groq's parameter reference deprecates max_tokens in favour of this
            # name, so the preset pins it rather than inheriting a default.
            max_tokens_field=MAX_COMPLETION_TOKENS_FIELD,
            temperature=temperature,
        )
        self.last_usage: dict = {}

    @classmethod
    def from_env(cls, timeout: float = 4.0) -> "GroqWriter":
        """Build from configuration. Raises when unset; never falls back to a mock."""
        key = os.environ.get(API_KEY_ENV, "")
        if not key:
            raise ProviderFailure(
                f"{API_KEY_ENV} is not set. Configure a Groq key, or select a scripted writer "
                "explicitly for offline work."
            )
        return cls(
            api_key=key,
            model=os.environ.get(MODEL_ENV, DEFAULT_MODEL),
            endpoint=os.environ.get(ENDPOINT_ENV, DEFAULT_ENDPOINT),
            timeout=timeout,
        )

    def complete(self, frame: ContextFrame, instruction: str) -> str:
        try:
            reply = inline_completion(self.client, frame, instruction, post_json)
        except ChatError as error:
            raise ProviderFailure(str(error)) from None
        self.last_usage = {
            "latency_ms": round(reply.latency_ms, 1),
            "finish_reason": reply.finish_reason,
            **reply.usage,
        }
        return reply.content

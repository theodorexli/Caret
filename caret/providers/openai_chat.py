"""One OpenAI-compatible chat-completions client, shared by the presets.

Groq and Vercel AI Gateway both speak the OpenAI chat-completions shape, so
request building, response unwrapping and the reply bounds live here once. What
differs is configuration, and each preset states its own: endpoint, the
environment variable that holds the key, the default model, and the name of the
maximum-generation field.

That last one is not cosmetic. Groq's reference documents
``max_completion_tokens`` and deprecates ``max_tokens``. Vercel's current
parameter reference lists ``max_tokens`` and does not list
``max_completion_tokens`` as a request parameter, so acceptance of that name is
unconfirmed there
(https://vercel.com/docs/ai-gateway/sdks-and-apis/openai-chat-completions/chat-completions).
The field name is therefore a per-preset setting rather than one guess applied
to both services.

Each preset passes the JSON POST function from its own module, so the transport
belongs to the preset whose wire contract is being exercised. This module holds
no key material of its own and never puts the key into an error message.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field, replace
from typing import Callable

from ..context import ContextFrame, utf16_length
from ..judge import describe_frame
from .http import ProviderHTTPError

Transport = Callable[[str, dict, dict, float], dict]
"""The ``post_json`` signature: url, payload, headers, timeout -> decoded body."""

MAX_COMPLETION_TOKENS_FIELD = "max_completion_tokens"
MAX_TOKENS_FIELD = "max_tokens"

INLINE_SYSTEM_PROMPT = (
    "You complete text inside whatever application the user is typing in, like an editor's "
    "inline autocomplete. Reply with only the characters to insert at the caret, or only the "
    "replacement for the selected text when there is a selection. Never explain, never repeat "
    "text that is already there, never wrap the answer in quotes or markdown. Keep it to at "
    "most one sentence or clause. If nothing useful can be added, reply with nothing at all."
)

MAX_INLINE_UNITS = 1000
"""Ceiling on a raw writer reply, in UTF-16 units. The router applies its own
tighter bound to the offer; this one rejects a model that ignored the prompt
entirely before that text is carried any further."""


class ChatError(RuntimeError):
    """A chat-completions call failed, or answered with something unusable.

    Each preset translates this into its own domain error, because a writer
    failure and a judge failure are handled differently upstream.
    """


@dataclass(frozen=True)
class ChatReply:
    """The parts of a non-streaming completion Caret uses."""

    content: str
    model: str
    finish_reason: str | None = None
    usage: dict = field(default_factory=dict)
    latency_ms: float = 0.0


class OpenAIChatClient:
    """Configuration plus one request/response round trip. Holds no connection."""

    def __init__(
        self,
        *,
        service: str,
        endpoint: str,
        api_key: str,
        model: str,
        timeout: float,
        max_output_tokens: int,
        max_tokens_field: str,
        temperature: float = 0.2,
    ) -> None:
        self.service = service
        """Human-readable service name. Appears in every error this raises."""
        self.endpoint = endpoint
        self._api_key = api_key
        self.model = model
        self.timeout = timeout
        """Bounded per-request duration. These calls sit inside a two-second
        ambient cadence, so a long wait is a failure rather than patience."""
        self.max_output_tokens = max_output_tokens
        self.max_tokens_field = max_tokens_field
        self.temperature = temperature

    def headers(self) -> dict:
        return {"Authorization": f"Bearer {self._api_key}"}

    def payload(self, messages: list[dict], response_format: dict | None = None) -> dict:
        """The request body. ``response_format`` is per call because a judge's
        schema depends on the choice IDs of the one question being asked."""
        body = {
            "model": self.model,
            "messages": messages,
            "temperature": self.temperature,
            self.max_tokens_field: self.max_output_tokens,
            "stream": False,
        }
        if response_format is not None:
            body["response_format"] = response_format
        return body

    def send(
        self,
        messages: list[dict],
        transport: Transport,
        response_format: dict | None = None,
    ) -> ChatReply:
        started = time.monotonic()
        try:
            body = transport(
                self.endpoint,
                self.payload(messages, response_format),
                self.headers(),
                self.timeout,
            )
        except ProviderHTTPError as error:
            raise ChatError(str(error)) from None
        latency_ms = (time.monotonic() - started) * 1000

        choices = body.get("choices")
        if not isinstance(choices, list) or not choices:
            raise ChatError(f"{self.service} response contained no choices")
        first = choices[0]
        message = first.get("message") if isinstance(first, dict) else None
        if not isinstance(message, dict):
            raise ChatError(f"{self.service} choice contained no message object")
        content = message.get("content")
        if not isinstance(content, str):
            raise ChatError(
                f"{self.service} message content is {type(content).__name__}, expected a string"
            )

        raw_usage = body.get("usage")
        usage = (
            {key: value for key, value in raw_usage.items() if key.endswith("_tokens")}
            if isinstance(raw_usage, dict)
            else {}
        )
        return ChatReply(
            content=content,
            model=str(body.get("model", self.model)),
            finish_reason=first.get("finish_reason"),
            usage=usage,
            latency_ms=latency_ms,
        )


def inline_completion(
    client: OpenAIChatClient,
    frame: ContextFrame,
    instruction: str,
    transport: Transport,
    *,
    system_prompt: str = INLINE_SYSTEM_PROMPT,
) -> ChatReply:
    """Ask for inline text and return the trimmed reply.

    An empty reply is a failed generation for this tick, not an empty edit: the
    prompt tells the model to answer with nothing when it has nothing, and the
    judge, not the writer, decides whether Caret should have stayed quiet.
    """
    reply = client.send(
        [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": f"{instruction}\n\n{describe_frame(frame)}"},
        ],
        transport,
    )
    text = trim_completion(reply.content)
    if not text:
        if reply.finish_reason == "length":
            # A reasoning model spent the whole budget before writing anything.
            # Say so, because the fix is the token budget, not the prompt.
            raise ChatError(
                f"{client.service} hit {client.max_tokens_field}={client.max_output_tokens} "
                f"before producing text (finish_reason=length); raise the budget for {client.model}"
            )
        raise ChatError(f"{client.service} returned no usable completion text")
    length = utf16_length(text)
    if length > MAX_INLINE_UNITS:
        raise ChatError(f"{client.service} returned {length} UTF-16 units for an inline edit")
    return replace(reply, content=text)


def trim_completion(content: str) -> str:
    """Drop formatting newlines while keeping a leading space.

    A leading newline is the model formatting its reply. A leading space is part
    of the completion: continuing "hello" wants " world", not "world".
    """
    return content.lstrip("\r\n").rstrip()

"""Chat completions via Vercel AI Gateway (Gemini 2.5 Flash default)."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Any, Literal, TypedDict
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

GATEWAY_BASE_URL = "https://ai-gateway.vercel.sh/v1"
CHAT_COMPLETIONS_PATH = "/chat/completions"
DEFAULT_MODEL = "google/gemini-2.5-flash"
DEFAULT_TIMEOUT_SECONDS = 120.0

VERCEL_API_GATEWAY_KEY_ENV = "VERCEL_API_GATEWAY_KEY"
AI_GATEWAY_API_KEY_ENV = "AI_GATEWAY_API_KEY"


class ChatMessage(TypedDict):
    role: Literal["system", "user", "assistant"]
    content: str


class CompletionError(RuntimeError):
    """Raised when configuration, transport, or response parsing fails."""


@dataclass(frozen=True)
class CompletionResult:
    text: str
    model: str
    raw: dict[str, Any]
    usage: dict[str, Any]


def gateway_api_key() -> str:
    """Resolve the Vercel AI Gateway bearer token from the environment."""
    for name in (VERCEL_API_GATEWAY_KEY_ENV, AI_GATEWAY_API_KEY_ENV):
        value = os.environ.get(name, "").strip()
        if value:
            return value
    raise CompletionError(
        f"Missing API key: set {VERCEL_API_GATEWAY_KEY_ENV} (GitHub Actions secret) "
        f"or {AI_GATEWAY_API_KEY_ENV} locally."
    )


def parse_completion_response(payload: dict[str, Any], *, model: str = DEFAULT_MODEL) -> CompletionResult:
    try:
        choices = payload["choices"]
        message = choices[0]["message"]
        text = message["content"]
    except (KeyError, IndexError, TypeError) as error:
        raise CompletionError(f"Unexpected completion payload: {payload!r}") from error
    if not isinstance(text, str):
        raise CompletionError(f"Completion content must be a string, got {type(text)!r}")
    usage = payload.get("usage")
    if not isinstance(usage, dict):
        usage = {}
    response_model = payload.get("model")
    resolved_model = response_model if isinstance(response_model, str) and response_model else model
    return CompletionResult(text=text, model=resolved_model, raw=payload, usage=usage)


def complete(
    messages: list[ChatMessage],
    *,
    model: str = DEFAULT_MODEL,
    temperature: float | None = None,
    max_tokens: int | None = None,
    api_key: str | None = None,
    base_url: str = GATEWAY_BASE_URL,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> CompletionResult:
    """Create a non-streaming chat completion through Vercel AI Gateway."""
    key = api_key.strip() if api_key else gateway_api_key()
    url = base_url.rstrip("/") + CHAT_COMPLETIONS_PATH
    body: dict[str, Any] = {
        "model": model,
        "messages": messages,
        "stream": False,
    }
    if temperature is not None:
        body["temperature"] = temperature
    if max_tokens is not None:
        body["max_tokens"] = max_tokens

    data = json.dumps(body).encode("utf-8")
    request = Request(
        url,
        data=data,
        method="POST",
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise CompletionError(f"Gateway HTTP {error.code}: {detail}") from error
    except URLError as error:
        raise CompletionError(f"Gateway request failed: {error}") from error
    except json.JSONDecodeError as error:
        raise CompletionError("Gateway returned invalid JSON") from error

    if not isinstance(payload, dict):
        raise CompletionError(f"Expected JSON object response, got {type(payload)!r}")
    return parse_completion_response(payload, model=model)


def complete_text(
    prompt: str,
    *,
    system: str | None = None,
    model: str = DEFAULT_MODEL,
    temperature: float | None = None,
    max_tokens: int | None = None,
    api_key: str | None = None,
    base_url: str = GATEWAY_BASE_URL,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> str:
    """Convenience wrapper: build messages from a user prompt and return assistant text."""
    messages: list[ChatMessage] = []
    if system:
        messages.append({"role": "system", "content": system})
    messages.append({"role": "user", "content": prompt})
    return complete(
        messages,
        model=model,
        temperature=temperature,
        max_tokens=max_tokens,
        api_key=api_key,
        base_url=base_url,
        timeout=timeout,
    ).text

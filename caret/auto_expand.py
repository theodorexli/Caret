"""Inline auto-expand: model returns only the text to append after the caret prefix."""

from __future__ import annotations

from caret.completions import ChatMessage, complete_text


def build_auto_expand_messages(*, prefix: str, instructions: str) -> list[ChatMessage]:
    trimmed_instructions = instructions.strip() or (
        "Expand the selection or continue from the cursor with the next useful phrase. "
        "Match the user's voice; prefer short inline additions over rewriting."
    )
    system = (
        f"{trimmed_instructions}\n\n"
        "You are an inline autocomplete engine. Return ONLY the continuation text to append "
        "immediately after the user's prefix. Do not repeat the prefix. Do not add quotes, "
        "labels, markdown, or explanation. Keep it short (usually one phrase or sentence)."
    )
    user = (
        "Continue this text from the caret. Prefix (already typed, do not repeat):\n"
        f"{prefix}"
    )
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def normalize_continuation(raw: str, prefix: str) -> str:
    text = raw.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'":
        text = text[1:-1].strip()
    if not text:
        return ""
    if prefix and text.startswith(prefix):
        text = text[len(prefix) :]
    if prefix and text == prefix.strip():
        return ""
    return text


def complete_auto_expand(
    *,
    prefix: str,
    instructions: str = "",
    model: str | None = None,
    max_tokens: int = 96,
) -> str:
    kwargs: dict = {"max_tokens": max_tokens, "temperature": 0.35}
    if model:
        kwargs["model"] = model
    messages = build_auto_expand_messages(prefix=prefix, instructions=instructions)
    raw = complete_text(
        messages[1]["content"],
        system=messages[0]["content"],
        **kwargs,
    )
    return normalize_continuation(raw, prefix)

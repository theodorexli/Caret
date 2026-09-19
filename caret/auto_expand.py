"""Inline auto-expand: pattern match from instructions, then model fallback."""

from __future__ import annotations

import re

from caret.completions import ChatMessage, complete_text

_PATTERN_LINE = re.compile(r"^\s*(?:\d+\.|[-*])\s+(.+)$")
MIN_TYPED_CHARACTERS = 5


def instruction_patterns(instructions: str) -> list[str]:
    """Completion templates from numbered or bulleted instruction lines."""
    patterns: list[str] = []
    for line in instructions.splitlines():
        stripped = line.strip()
        if not stripped or stripped.lower().startswith("when "):
            continue
        match = _PATTERN_LINE.match(line)
        if match:
            text = match.group(1).strip()
            if text:
                patterns.append(text)
    return patterns


def _shared_prefix_length(typed: str, pattern: str) -> int:
    limit = min(len(typed), len(pattern))
    for index in range(limit):
        if typed[index].lower() != pattern[index].lower():
            return index
    return limit


def pattern_completion_suffix(prefix: str, instructions: str) -> str:
    """Return text to append when `prefix` partially matches an instruction pattern."""
    typed = prefix
    if len(typed) < MIN_TYPED_CHARACTERS or not typed.strip():
        return ""

    best_suffix = ""
    best_pattern_len = -1
    for pattern in instruction_patterns(instructions):
        shared = _shared_prefix_length(typed, pattern)
        if shared != len(typed):
            continue
        if shared >= len(pattern):
            continue
        suffix = pattern[shared:]
        if len(pattern) > best_pattern_len:
            best_suffix = suffix
            best_pattern_len = len(pattern)
    return best_suffix


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


def should_offer_tab_completion(prefix: str, instructions: str) -> bool:
    """Return True when the current prefix can receive a Tab completion."""
    if len(prefix) < MIN_TYPED_CHARACTERS:
        return False
    if pattern_completion_suffix(prefix, instructions):
        return True
    stripped = prefix.strip()
    if len(stripped) < MIN_TYPED_CHARACTERS:
        return False
    triggers: list[str] = []
    for line in instructions.splitlines():
        text = line.strip()
        lowered = text.lower()
        if lowered.startswith("when ") and ":" in text:
            trigger = text.split(":", 1)[1].strip().strip("\"'")
            if trigger:
                triggers.append(trigger)
    if not triggers:
        return len(stripped) >= MIN_TYPED_CHARACTERS
    lowered_prefix = stripped.lower()
    return any(
        lowered_prefix.endswith(t.lower()) or t.lower() in lowered_prefix
        for t in triggers
    )


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
    matched = pattern_completion_suffix(prefix, instructions)
    if matched:
        return matched
    if not should_offer_tab_completion(prefix, instructions):
        return ""
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

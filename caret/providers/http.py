"""One stdlib JSON POST, shared by both provider clients.

Kept deliberately small: no session pooling, no retry loop, no dependency. A
failure raises with the status and a short body excerpt so a caller can see why
without the response being dumped into a log. Credentials are passed through
and never returned, echoed or included in an error message.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request


class ProviderHTTPError(RuntimeError):
    """A provider call failed at the transport or HTTP level."""

    def __init__(self, message: str, status: int | None = None) -> None:
        super().__init__(message)
        self.status = status


MAX_ERROR_EXCERPT = 400
USER_AGENT = "caret-core/0.1 (+https://github.com/theodorexli/hackathon-2026-09-19)"


def post_json(url: str, payload: dict, headers: dict[str, str], timeout: float) -> dict:
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(url, data=body, method="POST")
    request.add_header("Content-Type", "application/json")
    # Cloudflare in front of api.groq.com answers 403 "error code: 1010" to the
    # default "Python-urllib/x.y" agent (observed 2026-09-19 with a valid key).
    # Naming the client is enough; nothing here pretends to be a browser.
    request.add_header("User-Agent", USER_AGENT)
    for name, value in headers.items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        excerpt = _excerpt(error)
        raise ProviderHTTPError(f"HTTP {error.code} from {_host(url)}: {excerpt}", error.code) from None
    except urllib.error.URLError as error:
        raise ProviderHTTPError(f"Could not reach {_host(url)}: {error.reason}") from None
    except TimeoutError:
        raise ProviderHTTPError(f"{_host(url)} did not respond within {timeout:.1f}s") from None
    try:
        decoded = json.loads(raw)
    except json.JSONDecodeError:
        raise ProviderHTTPError(f"{_host(url)} returned a non-JSON body: {raw[:MAX_ERROR_EXCERPT]!r}") from None
    if not isinstance(decoded, dict):
        raise ProviderHTTPError(f"{_host(url)} returned {type(decoded).__name__}, expected an object")
    return decoded


def _host(url: str) -> str:
    """Host only. The path can carry identifiers; the host is enough context."""
    without_scheme = url.split("://", 1)[-1]
    return without_scheme.split("/", 1)[0]


def _excerpt(error: urllib.error.HTTPError) -> str:
    try:
        return error.read().decode("utf-8", "replace")[:MAX_ERROR_EXCERPT]
    except Exception:  # pragma: no cover - the body is optional diagnostics
        return "<no body>"

"""Public, unauthenticated GitHub research used by report-github-issue.

Writes never happen here. A later non-GitHub tracker would plug in beside
:class:`GitHubPort`; that path is not implemented.
"""

from __future__ import annotations

import json
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Protocol

from ..context import ContextFrame
from ..registry import WorkflowError

NOT_OPEN_SOURCE_MESSAGE = "This does not appear to be an open-source application."
NO_COMPLAINT_MESSAGE = "Describe the problem so Caret can search GitHub issues."
SEARCH_FAILED_MESSAGE = "Could not search GitHub issues"

USER_AGENT = "Caret-hackathon"
API_ROOT = "https://api.github.com"
_REPO_IN_TEXT = re.compile(
    r"github\.com/([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)/([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?)",
    re.IGNORECASE,
)
_RESERVED_OWNERS = frozenset(
    {"orgs", "settings", "marketplace", "topics", "about", "features", "login", "signup", "explore", "notifications", "new"}
)
_STOP = frozenset(
    {
        "with",
        "from",
        "that",
        "this",
        "have",
        "been",
        "they",
        "them",
        "your",
        "about",
        "when",
        "then",
        "than",
        "into",
        "just",
        "only",
        "also",
        "does",
        "did",
        "the",
        "and",
        "for",
    }
)


class NotOpenSource(WorkflowError):
    """The app has no evidenced public GitHub repository with issues."""

    def __init__(self, message: str = NOT_OPEN_SOURCE_MESSAGE) -> None:
        super().__init__(message)


class NoComplaint(WorkflowError):
    """Nearby text and clipboard were empty after trimming."""

    def __init__(self, message: str = NO_COMPLAINT_MESSAGE) -> None:
        super().__init__(message)


class SearchFailed(WorkflowError):
    """GitHub could not be searched; this is not evidence the app is closed-source."""

    def __init__(self, message: str = SEARCH_FAILED_MESSAGE) -> None:
        super().__init__(message)


@dataclass(frozen=True)
class Repo:
    slug: str
    html_url: str
    evidence: str


@dataclass(frozen=True)
class IssueMatch:
    number: int
    title: str
    html_url: str
    body: str
    state: str = "open"


@dataclass(frozen=True)
class Recommendation:
    mode: str
    repo: Repo
    issue: IssueMatch | None
    summary: str
    recommend_comment: bool


class GitHubPort(Protocol):
    def search_repos(self, query: str) -> list[dict]:
        ...

    def search_issues(self, repo_slug: str, query: str) -> list[dict]:
        ...

    def get_issue(self, repo_slug: str, number: int) -> dict:
        ...


class PublicGitHub:
    """stdlib urllib client for api.github.com. No Authorization header."""

    def __init__(self, opener=None, timeout: float = 8.0) -> None:
        self.opener = opener or urllib.request.urlopen
        self.timeout = timeout

    def search_repos(self, query: str) -> list[dict]:
        return self._items("/search/repositories", {"q": query})

    def search_issues(self, repo_slug: str, query: str) -> list[dict]:
        return self._items("/search/issues", {"q": f"{query} repo:{repo_slug} is:issue"})

    def get_issue(self, repo_slug: str, number: int) -> dict:
        payload = self._get(f"/repos/{repo_slug}/issues/{number}")
        if not payload:
            raise SearchFailed()
        return payload

    def _items(self, path: str, query: dict[str, str]) -> list[dict]:
        payload = self._get(path, query)
        items = (payload or {}).get("items")
        if items is None:
            return []
        if not isinstance(items, list):
            raise SearchFailed()
        return items

    def _get(self, path: str, query: dict[str, str] | None = None) -> dict | None:
        url = API_ROOT + path
        if query:
            url = f"{url}?{urllib.parse.urlencode(query)}"
        request = urllib.request.Request(
            url,
            headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"},
        )
        try:
            with self.opener(request, timeout=self.timeout) as response:
                body = response.read()
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return {"items": []} if path.startswith("/search/") else None
            raise SearchFailed() from error
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            raise SearchFailed() from error
        try:
            payload = json.loads(body.decode("utf-8"))
        except (ValueError, UnicodeError) as error:
            raise SearchFailed() from error
        if not isinstance(payload, dict):
            raise SearchFailed()
        return payload


def complaint_from(frame: ContextFrame) -> str:
    nearby = frame.snapshot.nearby_text.strip()
    if nearby:
        return nearby
    if frame.clipboard.available:
        return frame.clipboard.text.strip()
    return ""


def display_name(frame: ContextFrame) -> str:
    for source in frame.sources:
        if source.name == "frontmost_app" and source.available:
            return source.detail.strip()
    return ""


def repo_from_text(text: str) -> str | None:
    match = _REPO_IN_TEXT.search(text)
    if match is None:
        return None
    owner, repo = match.group(1), match.group(2).removesuffix(".git")
    if owner.lower() in _RESERVED_OWNERS:
        return None
    return f"{owner}/{repo}"


def resolve_repo(frame: ContextFrame, port: GitHubPort) -> Repo:
    complaint = complaint_from(frame)
    if not complaint:
        raise NoComplaint()
    slug = repo_from_text(complaint)
    if slug:
        return Repo(slug=slug, html_url=f"https://github.com/{slug}", evidence="url")
    name = display_name(frame)
    if not name:
        raise NotOpenSource()
    items = port.search_repos(name)
    for item in items:
        if not isinstance(item, dict):
            continue
        if item.get("private") or item.get("archived") or not item.get("has_issues"):
            continue
        found = str(item.get("full_name") or "")
        if "/" not in found:
            continue
        return Repo(
            slug=found,
            html_url=str(item.get("html_url") or f"https://github.com/{found}"),
            evidence="api-search",
        )
    raise NotOpenSource()


def search_issues(repo: Repo, complaint: str, port: GitHubPort) -> list[IssueMatch]:
    items = port.search_issues(repo.slug, complaint)
    if not items:
        return []
    first = items[0]
    if not isinstance(first, dict) or not isinstance(first.get("number"), int):
        raise SearchFailed()
    number = first["number"]
    detail = port.get_issue(repo.slug, number)
    return [
        IssueMatch(
            number=number,
            title=str(first.get("title") or ""),
            html_url=str(first.get("html_url") or ""),
            body=str((detail or {}).get("body") or ""),
            state=str(first.get("state") or "open"),
        )
    ]


def recommend(repo: Repo, matches: list[IssueMatch], complaint: str) -> Recommendation:
    if not matches:
        return Recommendation(
            mode="new-issue",
            repo=repo,
            issue=None,
            summary="No matching public issue was found.",
            recommend_comment=False,
        )
    match = matches[0]
    haystack = f"{match.title}\n{match.body}".lower()
    novel = [token for token in _tokens(complaint) if token not in haystack]
    if novel:
        return Recommendation(
            mode="comment",
            repo=repo,
            issue=match,
            summary=match.title,
            recommend_comment=True,
        )
    return Recommendation(
        mode="already-covered",
        repo=repo,
        issue=match,
        summary=match.title,
        recommend_comment=False,
    )


def _tokens(text: str) -> list[str]:
    return [part for part in re.findall(r"[a-z0-9]+", text.lower()) if len(part) >= 4 and part not in _STOP]

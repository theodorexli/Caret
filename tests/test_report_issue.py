"""Public GitHub research for the report-a-GitHub-issue workflow."""

from __future__ import annotations

from dataclasses import replace
from io import BytesIO
from urllib.error import HTTPError, URLError
import unittest

from caret.context import ClipboardContext, SourceRecord
from caret.live_workflows.github import (
    SEARCH_FAILED_MESSAGE,
    NoComplaint,
    NotOpenSource,
    PublicGitHub,
    SearchFailed,
    complaint_from,
    recommend,
    resolve_repo,
    search_issues,
)
from support import frame


class FakeGitHub:
    """Records calls and returns scripted payloads. Sends nothing."""

    def __init__(
        self,
        repos=None,
        issues=None,
        issue_bodies=None,
        repo_error=None,
        issue_error=None,
        get_error=None,
    ):
        self.repos = list(repos or [])
        self.issues = list(issues or [])
        self.issue_bodies = dict(issue_bodies or {})
        self.repo_error = repo_error
        self.issue_error = issue_error
        self.get_error = get_error
        self.repo_calls: list[str] = []
        self.issue_calls: list[tuple[str, str]] = []
        self.get_calls: list[tuple[str, int]] = []

    def search_repos(self, query: str) -> list[dict]:
        self.repo_calls.append(query)
        if self.repo_error is not None:
            raise self.repo_error
        return list(self.repos)

    def search_issues(self, repo_slug: str, query: str) -> list[dict]:
        self.issue_calls.append((repo_slug, query))
        if self.issue_error is not None:
            raise self.issue_error
        return list(self.issues)

    def get_issue(self, repo_slug: str, number: int) -> dict:
        self.get_calls.append((repo_slug, number))
        if self.get_error is not None:
            raise self.get_error
        return dict(self.issue_bodies.get(number, {"number": number, "body": ""}))


def explicit_frame(text="", app="Ghostty", clipboard=""):
    sources = (
        SourceRecord(name="explicit_invoke", available=True, captured_at=None, detail="dev.ghostty.Ghostty"),
        SourceRecord(name="frontmost_app", available=True, captured_at=None, detail=app),
    )
    clip = (
        ClipboardContext(available=True, text=clipboard, captured_at=None)
        if clipboard
        else ClipboardContext(available=False)
    )
    return replace(frame(text=text, clipboard=False), sources=sources, clipboard=clip)


class ResolveRepoTests(unittest.TestCase):
    def test_a_github_url_in_the_complaint_wins_without_a_repo_search(self):
        port = FakeGitHub(repos=[{"full_name": "wrong/repo", "private": False, "archived": False, "has_issues": True}])
        repo = resolve_repo(
            explicit_frame("Crash at https://github.com/ghostty-org/ghostty when saving"),
            port,
        )
        self.assertEqual(repo.slug, "ghostty-org/ghostty")
        self.assertEqual(repo.evidence, "url")
        self.assertEqual(repo.html_url, "https://github.com/ghostty-org/ghostty")
        self.assertEqual(port.repo_calls, [])

    def test_frontmost_app_search_picks_the_first_public_repo_with_issues(self):
        port = FakeGitHub(
            repos=[
                {"full_name": "acme/archived", "private": False, "archived": True, "has_issues": True, "html_url": "https://github.com/acme/archived"},
                {"full_name": "acme/private", "private": True, "archived": False, "has_issues": True, "html_url": "https://github.com/acme/private"},
                {"full_name": "acme/ghostty", "private": False, "archived": False, "has_issues": True, "html_url": "https://github.com/acme/ghostty"},
            ]
        )
        repo = resolve_repo(explicit_frame("The window flashes black", app="Ghostty"), port)
        self.assertEqual(repo.slug, "acme/ghostty")
        self.assertEqual(repo.evidence, "api-search")
        self.assertEqual(port.repo_calls, ["Ghostty"])

    def test_no_usable_public_repo_is_not_open_source(self):
        port = FakeGitHub(repos=[])
        with self.assertRaises(NotOpenSource) as raised:
            resolve_repo(explicit_frame("It crashed", app="SecretApp"), port)
        self.assertIn("does not appear to be an open-source application", str(raised.exception).lower())

    def test_an_empty_complaint_is_refused(self):
        with self.assertRaises(NoComplaint):
            resolve_repo(explicit_frame("", app="Ghostty"), FakeGitHub())
        clip_frame = explicit_frame("", app="Ghostty", clipboard="  pasted crash log  ")
        self.assertEqual(complaint_from(clip_frame), "pasted crash log")

    def test_a_timeout_or_forbidden_or_bad_json_is_search_failed_not_not_oss(self):
        for error in (
            SearchFailed(SEARCH_FAILED_MESSAGE),
            SearchFailed(SEARCH_FAILED_MESSAGE),
            SearchFailed(SEARCH_FAILED_MESSAGE),
        ):
            with self.subTest(error=type(error).__name__):
                with self.assertRaises(SearchFailed) as raised:
                    resolve_repo(explicit_frame("It crashed", app="Ghostty"), FakeGitHub(repo_error=error))
                self.assertIsInstance(raised.exception, SearchFailed)
                self.assertNotIsInstance(raised.exception, NotOpenSource)
                self.assertEqual(str(raised.exception), SEARCH_FAILED_MESSAGE)

        opener = ScriptedOpener()
        github = PublicGitHub(opener=opener.open, timeout=2.0)
        opener.next = HTTPError("https://api.github.com/search/repositories", 403, "rate", {}, BytesIO(b"{}"))
        with self.assertRaises(SearchFailed):
            github.search_repos("Ghostty")
        opener.next = URLError("timed out")
        with self.assertRaises(SearchFailed):
            github.search_repos("Ghostty")
        opener.next = (200, b"not-json")
        with self.assertRaises(SearchFailed):
            github.search_repos("Ghostty")
        opener.next = (404, b'{"items":[]}')
        self.assertEqual(github.search_repos("Ghostty"), [])
        for call in opener.calls:
            names = {key.lower() for key in call["headers"]}
            self.assertNotIn("authorization", names)
            self.assertIn("user-agent", names)


class RecommendTests(unittest.TestCase):
    def test_a_match_with_new_tokens_recommends_a_comment(self):
        port = FakeGitHub(
            issues=[{"number": 12, "title": "Window flashes black", "html_url": "https://github.com/acme/ghostty/issues/12", "state": "open"}],
            issue_bodies={12: {"number": 12, "body": "The window goes black on launch."}},
        )
        repo = resolve_repo(explicit_frame("Window flashes black with a nil pointer", app="Ghostty"), FakeGitHub(
            repos=[{"full_name": "acme/ghostty", "private": False, "archived": False, "has_issues": True, "html_url": "https://github.com/acme/ghostty"}]
        ))
        matches = search_issues(repo, "Window flashes black with a nil pointer", port)
        self.assertEqual(port.get_calls, [("acme/ghostty", 12)])
        decision = recommend(repo, matches, "Window flashes black with a nil pointer")
        self.assertEqual(decision.mode, "comment")
        self.assertTrue(decision.recommend_comment)
        self.assertEqual(decision.issue.number, 12)
        self.assertIn("Window flashes black", decision.summary)

    def test_a_match_that_already_covers_the_complaint_does_not_recommend_a_comment(self):
        port = FakeGitHub(
            issues=[{"number": 12, "title": "Window flashes black", "html_url": "https://github.com/acme/ghostty/issues/12", "state": "open"}],
            issue_bodies={12: {"number": 12, "body": "The window flashes black on launch."}},
        )
        repo = resolve_repo(explicit_frame("Window flashes black", app="Ghostty"), FakeGitHub(
            repos=[{"full_name": "acme/ghostty", "private": False, "archived": False, "has_issues": True, "html_url": "https://github.com/acme/ghostty"}]
        ))
        matches = search_issues(repo, "Window flashes black", port)
        decision = recommend(repo, matches, "Window flashes black")
        self.assertEqual(decision.mode, "already-covered")
        self.assertFalse(decision.recommend_comment)
        self.assertIn("Window flashes black", decision.summary)

    def test_no_match_is_a_new_issue(self):
        port = FakeGitHub(issues=[])
        repo = resolve_repo(explicit_frame("Window flashes black", app="Ghostty"), FakeGitHub(
            repos=[{"full_name": "acme/ghostty", "private": False, "archived": False, "has_issues": True, "html_url": "https://github.com/acme/ghostty"}]
        ))
        matches = search_issues(repo, "Window flashes black", port)
        self.assertEqual(port.get_calls, [])
        decision = recommend(repo, matches, "Window flashes black")
        self.assertEqual(decision.mode, "new-issue")
        self.assertFalse(decision.recommend_comment)
        self.assertIsNone(decision.issue)


class ScriptedOpener:
    """Returns one scripted urllib response at a time."""

    def __init__(self):
        self.next = None
        self.calls = []

    def open(self, request, timeout=None):
        self.calls.append({"url": request.full_url, "headers": dict(request.header_items()), "timeout": timeout})
        payload = self.next
        if isinstance(payload, Exception):
            raise payload
        status, body = payload
        if status >= 400:
            raise HTTPError(request.full_url, status, "error", {}, BytesIO(body))
        return BytesIO(body)


if __name__ == "__main__":
    unittest.main()

"""Persistent JSON-lines bridge: the process boundary the Mac app calls.

One JSON object per line, in both directions, over stdin and stdout. The app
spawns this once and keeps it alive; there is no HTTP server, no port and no
packaging beyond the Python already in the repository.

Requests carry an ``id`` and get exactly one reply with the same ``id``::

    -> {"id": 1, "method": "context.update", "params": {"frame": {...}}}
    <- {"id": 1, "ok": true, "result": {"status": "admitted", "revision": 7}}

Evaluation is asynchronous because a provider call cannot block the app's
input handling. Results arrive as unsolicited event lines with no ``id``::

    <- {"event": "offer", "offer": {"kind": "inline", "proposal_id": "...", ...}}
    <- {"event": "abstain", "revision": 8, "reason": "judge-abstained"}
    <- {"event": "invalidated", "proposal_id": "...", "reason": "context-changed"}
    <- {"event": "failed", "revision": 9, "reason": "judge/route: HTTP 401 ..."}

Event lines arrive in the order the router made the transitions, so an ``offer``
always precedes the ``invalidated`` line that retires it. An app can drive its
preview straight from the stream without comparing proposal IDs against what it
is already showing.

``context.update`` returns as soon as the frame is recorded, so the app can keep
sampling at its own rate. The cadence, the single in-flight evaluation and the
latest-snapshot-wins rule live in :mod:`caret.router`, not in the caller.

Run it directly to see the options::

    python3 -m caret.bridge --help
"""

from __future__ import annotations

import argparse
import importlib
import json
import queue
import sys
import threading
from pathlib import Path
from typing import TextIO

from .adapters import SampleSchedulerWorkflow, seeds_from_catalog
from .live_workflows.report_issue import ReportGithubIssueWorkflow
from .context import ContextError, ContextFrame, TargetIdentity
from .engine import Engine, ProviderFailure
from .judge import JudgeError
from .registry import WorkflowError, WorkflowRegistry
from .router import AcceptanceError, Offer, Publication, RouterConfig

PROTOCOL_VERSION = 1
POLL_SECONDS = 0.05

EVENT_FOR_STATUS = {"abstained": "abstain", "discarded": "discarded", "failed": "failed"}
"""Event name for each publication status that carries no offer."""

END_OF_OUTPUT = object()
"""Queue sentinel that stops the writer thread once nothing can enqueue."""


class Bridge:
    """Reads requests on one thread, evaluates on another, writes on a third."""

    def __init__(
        self,
        engine_factory,
        registry: WorkflowRegistry,
        stdin: TextIO,
        stdout: TextIO,
    ) -> None:
        self.registry = registry
        self.stdin = stdin
        self.stdout = stdout
        self._outbox: queue.Queue = queue.Queue()
        self._stop = threading.Event()
        self._wake = threading.Event()
        self.engine: Engine = engine_factory(self._on_invalidate, self._on_publish)

    # -- Output ----------------------------------------------------------
    #
    # Every line leaves through this one queue and the one thread that drains
    # it. The router hands over an offer and the invalidation that retires it
    # while holding its own lock, so queue order is the order the lifecycle
    # actually happened in. A per-write lock is not enough: it serializes the
    # bytes of two writes without saying which write comes first, which let a
    # client be told to take a preview down before it had been told the preview
    # existed. Writing from inside the router's lock instead would hand a stalled
    # reader the power to stop the router, so the writing stays out here.

    def _emit(self, payload: dict) -> None:
        self._outbox.put(payload)

    def _drain_output(self) -> None:
        while True:
            payload = self._outbox.get()
            if payload is END_OF_OUTPUT:
                return
            self.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
            self.stdout.flush()

    def _reply(self, request_id, result: dict) -> None:
        self._emit({"id": request_id, "ok": True, "result": result})

    def _fail(self, request_id, code: str, message: str) -> None:
        self._emit({"id": request_id, "ok": False, "error": {"code": code, "message": message}})

    def _on_invalidate(self, offer: Offer, reason: str) -> None:
        self._emit({"event": "invalidated", "proposal_id": offer.proposal_id, "reason": reason})

    def _on_publish(self, publication: Publication) -> None:
        if publication.status == "published" and publication.offer is not None:
            self._emit({"event": "offer", "offer": publication.offer.to_dict()})
        else:
            self._emit(
                {
                    "event": EVENT_FOR_STATUS[publication.status],
                    "revision": publication.revision,
                    "reason": publication.reason,
                }
            )

    # -- Worker ----------------------------------------------------------

    def _worker(self) -> None:
        """Run evaluations. The events they produce are emitted by the router.

        Nothing is written here on the ordinary path: every publication is
        announced through :meth:`_on_publish` while the router still holds the
        lock that produced it.
        """
        while not self._stop.is_set():
            try:
                publication = self.engine.pump()
            except Exception as error:  # pragma: no cover - last-resort guard
                # An evaluation that raised is already turned into a failure
                # publication by Engine.evaluate, which is what releases the
                # router's in-flight slot. Reaching here means something outside
                # the evaluation broke, so wait one poll interval before looping:
                # a repeating failure must not become a hot loop writing events.
                self._emit({"event": "failed", "revision": -1, "reason": f"{type(error).__name__}: {error}"})
                publication = None
            if publication is None:
                self._wake.wait(POLL_SECONDS)
                self._wake.clear()

    # -- Request handling -------------------------------------------------

    def run(self) -> int:
        output = threading.Thread(target=self._drain_output, name="caret-output", daemon=True)
        output.start()
        worker = threading.Thread(target=self._worker, name="caret-evaluate", daemon=True)
        worker.start()
        try:
            for line in self.stdin:
                line = line.strip()
                if not line:
                    continue
                if self._handle_line(line):
                    break
        finally:
            self._stop.set()
            self._wake.set()
            worker.join(timeout=2.0)
            # The writer stops only once nothing can enqueue, so the reply to
            # `shutdown` and any event already queued still reach the app.
            self._outbox.put(END_OF_OUTPUT)
            output.join(timeout=2.0)
        return 0

    def _handle_line(self, line: str) -> bool:
        """Handle one request. Returns True when the bridge should stop."""
        try:
            request = json.loads(line)
        except json.JSONDecodeError as error:
            self._fail(None, "invalid_json", f"Could not parse request line: {error}")
            return False
        if not isinstance(request, dict):
            self._fail(None, "invalid_request", "A request line must be a JSON object")
            return False

        request_id = request.get("id")
        method = request.get("method")
        params = request.get("params") or {}
        if not isinstance(method, str):
            self._fail(request_id, "invalid_request", "Request is missing a string 'method'")
            return False
        if not isinstance(params, dict):
            self._fail(request_id, "invalid_request", "Request 'params' must be an object")
            return False

        try:
            if method == "hello":
                self._reply(request_id, self._hello())
            elif method == "context.update":
                self._reply(request_id, self._context_update(params))
                self._wake.set()
            elif method == "workflow.prepare":
                self._reply(request_id, self._prepare(params))
            elif method == "offer.accept":
                self._reply(request_id, self._accept(params))
            elif method == "offer.dismiss":
                self._reply(request_id, {"dismissed": self.engine.dismiss(str(params.get("proposal_id", "")))})
            elif method == "workflows.list":
                self._reply(request_id, {"workflows": self.registry.catalog()})
            elif method == "shutdown":
                self._reply(request_id, {"stopped": True})
                return True
            else:
                self._fail(request_id, "unknown_method", f"No method named '{method}'")
        except ContextError as error:
            self._fail(request_id, "invalid_context", str(error))
        except AcceptanceError as error:
            self._fail(request_id, "acceptance_rejected", str(error))
        except WorkflowError as error:
            self._fail(request_id, "workflow_error", str(error))
        except (JudgeError, ProviderFailure) as error:
            self._fail(request_id, "provider_error", str(error))
        except Exception as error:
            # One faulty adapter must not take the bridge down. Without this the
            # caller of an already-consumed proposal gets no reply at all and the
            # process exits, which makes the acceptance impossible to retry.
            self._fail(request_id, "internal_error", f"{type(error).__name__}: {error}")
        return False

    def _hello(self) -> dict:
        return {
            "protocol": PROTOCOL_VERSION,
            "interval_seconds": self.engine.config.interval_seconds,
            "max_offer_age_seconds": self.engine.config.max_offer_age_seconds,
            "max_inline_units": self.engine.config.max_inline_units,
            "workflows": self.registry.catalog(),
        }

    def _context_update(self, params: dict) -> dict:
        frame = ContextFrame.from_dict(params.get("frame"), "params.frame")
        return self.engine.submit(frame).to_dict()

    def _prepare(self, params: dict) -> dict:
        workflow_id = params.get("workflow_id")
        if not isinstance(workflow_id, str) or not workflow_id:
            raise WorkflowError("workflow.prepare needs a non-empty 'workflow_id'")
        frame = ContextFrame.from_dict(params.get("frame"), "params.frame")
        offer = self.engine.prepare_named(workflow_id, frame)
        return {"offer": offer.to_dict()}

    def _accept(self, params: dict) -> dict:
        proposal_id = params.get("proposal_id")
        revision = params.get("revision")
        if not isinstance(proposal_id, str) or not proposal_id:
            raise AcceptanceError("Acceptance needs a 'proposal_id'")
        if not isinstance(revision, int) or isinstance(revision, bool):
            raise AcceptanceError("Acceptance needs the integer 'revision' the proposal was built for")
        target = TargetIdentity.from_dict(params.get("target"), "params.target")
        return self.engine.accept(proposal_id, revision, target)


# -- Wiring --------------------------------------------------------------


def _build_judge(spec: str):
    if spec == "jev":
        from .providers import JevJudge

        return JevJudge.from_env()
    if spec == "gateway":
        from .providers import GatewayJudge

        return GatewayJudge.from_env()
    if spec == "pattern":
        from .pattern_judge import PatternJudge

        return PatternJudge()
    if spec.startswith("scripted:"):
        from .testing import ScriptedJudge

        return ScriptedJudge.from_file(Path(spec.split(":", 1)[1]))
    raise SystemExit(
        f"Unknown --judge '{spec}'. Use 'jev', 'gateway', 'pattern' or 'scripted:<path>'."
    )


def _build_writer(spec: str):
    if spec == "groq":
        from .providers import GroqWriter

        return GroqWriter.from_env()
    if spec == "gateway":
        from .providers import GatewayWriter

        return GatewayWriter.from_env()
    if spec.startswith("scripted:"):
        from .testing import ScriptedWriter

        return ScriptedWriter.from_file(Path(spec.split(":", 1)[1]))
    raise SystemExit(f"Unknown --writer '{spec}'. Use 'groq', 'gateway' or 'scripted:<path>'.")


def load_adapter(spec: str):
    """Import ``dotted.module:ClassName`` and instantiate it with no arguments.

    Any failure is a startup error naming the spec. A workflow that cannot be
    loaded must not quietly disappear from the catalog.
    """
    module_name, separator, class_name = spec.partition(":")
    if not separator or not module_name or not class_name:
        raise WorkflowError(f"--adapter '{spec}' must look like 'package.module:ClassName'")
    try:
        module = importlib.import_module(module_name)
    except ImportError as error:
        raise WorkflowError(f"--adapter '{spec}': cannot import '{module_name}': {error}") from None
    factory = getattr(module, class_name, None)
    if factory is None:
        raise WorkflowError(f"--adapter '{spec}': '{module_name}' has no attribute '{class_name}'")
    try:
        adapter = factory()
    except Exception as error:
        raise WorkflowError(f"--adapter '{spec}': constructor raised {type(error).__name__}: {error}") from None
    missing = [name for name in ("descriptor", "availability", "prepare", "execute", "cancel") if not hasattr(adapter, name)]
    if missing:
        raise WorkflowError(f"--adapter '{spec}' is missing {', '.join(missing)}; see caret.registry.WorkflowAdapter")
    return adapter


def build_registry(
    fixture: Path,
    database: Path,
    paul_scheduler: Path | None = None,
    adapters: tuple[str, ...] = (),
    notices: TextIO | None = None,
) -> WorkflowRegistry:
    """Built-ins first, then external ``--adapter`` specs.

    An external adapter whose ID matches a built-in replaces it: the sample
    planner and the unavailable seeds are placeholders for exactly the live
    workflows that arrive this way. The replacement is announced once so a log
    shows which implementation answered. Two externals with one ID is an error.
    """
    registry = WorkflowRegistry()
    registry.register(SampleSchedulerWorkflow(fixture, database))
    registry.register(ReportGithubIssueWorkflow())
    if paul_scheduler is not None:
        from .adapters.paul_scheduler import PaulSchedulerWorkflow

        registry.register(PaulSchedulerWorkflow(paul_scheduler))
    catalog = Path(__file__).with_name("workflows.json")
    for adapter in seeds_from_catalog(catalog, skip=frozenset({"book-calendar-link", "report-github-issue"})):
        registry.register(adapter)

    external: dict[str, str] = {}
    for spec in adapters:
        adapter = load_adapter(spec)
        workflow_id = adapter.descriptor.id
        if workflow_id in external:
            raise WorkflowError(
                f"--adapter '{spec}' and '{external[workflow_id]}' both register '{workflow_id}'"
            )
        replaced = registry.replace(adapter)
        external[workflow_id] = spec
        if replaced is not None and notices is not None:
            print(
                f"caret.bridge: replaced built-in '{workflow_id}' "
                f"(execution_method={replaced.descriptor.execution_method}) with {spec}",
                file=notices,
            )
    return registry


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python3 -m caret.bridge",
        description="Persistent JSON-lines bridge between the Mac app and Caret's judge.",
    )
    parser.add_argument(
        "--judge",
        default="jev",
        help="'jev' reads TYPESAFE_API_KEY and is the product judge. 'gateway' reads "
        "AI_GATEWAY_API_KEY and asks a chat model through Vercel AI Gateway to classify; it is "
        "an explicit alternative, not a fallback. 'scripted:<path>' replays a recorded script "
        "and is for tests and the offline example only; it is never selected automatically.",
    )
    parser.add_argument(
        "--writer",
        default="groq",
        help="'groq' reads GROQ_API_KEY. 'gateway' reads AI_GATEWAY_API_KEY. "
        "'scripted:<path>' replays a recorded script.",
    )
    parser.add_argument("--fixture", type=Path, default=Path("fixtures/meeting.json"))
    parser.add_argument("--db", type=Path, default=Path(".local/caret.sqlite"))
    parser.add_argument("--interval", type=float, default=RouterConfig.interval_seconds)
    parser.add_argument(
        "--failure-backoff",
        type=float,
        default=RouterConfig.failure_backoff_seconds,
        help="Seconds to wait after a failed evaluation before starting another one, so a "
        "provider that is down is not called again on every keystroke.",
    )
    parser.add_argument(
        "--paul-scheduler",
        type=Path,
        default=None,
        help="Opt in to the sample jev-scheduler adapter by pointing at a checkout of it. "
        "Off by default; see docs/input-pipeline.md for what it does and does not do.",
    )
    parser.add_argument(
        "--adapter",
        action="append",
        default=[],
        metavar="MODULE:CLASS",
        help="Register an external workflow adapter, e.g. caret.live_workflows:MeetingDraftWorkflow. "
        "Repeatable. An adapter whose ID matches a built-in replaces it (announced on stderr).",
    )
    args = parser.parse_args(argv)

    try:
        registry = build_registry(
            args.fixture, args.db, args.paul_scheduler, tuple(args.adapter), notices=sys.stderr
        )
    except WorkflowError as error:
        raise SystemExit(f"Workflow configuration failed: {error}") from None
    config = RouterConfig(
        interval_seconds=args.interval,
        failure_backoff_seconds=args.failure_backoff,
    )
    try:
        judge = _build_judge(args.judge)
        writer = _build_writer(args.writer)
    except (JudgeError, ProviderFailure) as error:
        # Exit before reading a single request. A bridge that starts without a
        # usable provider would accept context updates and answer every one with
        # a failure event, which reads like an outage rather than missing
        # configuration.
        raise SystemExit(f"Provider configuration failed: {error}") from None

    def factory(on_invalidate, on_publish):
        return Engine(
            judge, writer, registry, config, on_invalidate=on_invalidate, on_publish=on_publish
        )

    return Bridge(factory, registry, sys.stdin, sys.stdout).run()


if __name__ == "__main__":
    raise SystemExit(main())

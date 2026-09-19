import argparse
import json
import sys
from pathlib import Path

from .completions import DEFAULT_MODEL, CompletionError, complete_text
from .planner import plan
from .screenpipe import last_n_clipboard, last_n_minutes, last_n_windows
from .skills import create_skill, filter_skills, list_skills
from .store import Store


def main() -> int:
    parser = argparse.ArgumentParser(description="Caret local workflow starter")
    parser.add_argument("--db", type=Path, default=Path(".local/caret.sqlite"))
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("workflows")
    skills = commands.add_parser("skills")
    skills_sub = skills.add_subparsers(dest="skills_command", required=True)
    skills_list = skills_sub.add_parser("list")
    skills_list.add_argument("--action", required=True)
    skills_filter = skills_sub.add_parser("filter")
    skills_filter.add_argument("--action", required=True)
    skills_filter.add_argument("--query", default="")
    skills_create = skills_sub.add_parser("create")
    skills_create.add_argument("--action", required=True)
    skills_create.add_argument("--name", required=True)
    skills_create.add_argument("--description", default="")
    preview = commands.add_parser("preview")
    preview.add_argument("--fixture", type=Path, required=True)
    hold = commands.add_parser("hold")
    hold.add_argument("run_id")
    confirm = commands.add_parser("confirm")
    confirm.add_argument("run_id")
    confirm.add_argument("option_id")
    minutes = commands.add_parser("history-minutes")
    minutes.add_argument("--minutes", type=int, default=3)
    minutes.add_argument("--lease", type=Path, default=None)
    windows = commands.add_parser("history-windows")
    windows.add_argument("--windows", type=int, default=3)
    windows.add_argument("--lease", type=Path, default=None)
    clipboard = commands.add_parser("history-clipboard")
    clipboard.add_argument("--count", type=int, default=3)
    clipboard.add_argument("--lease", type=Path, default=None)
    complete_cmd = commands.add_parser("complete", help="Gemini 2.5 Flash via Vercel AI Gateway")
    complete_cmd.add_argument("--prompt", required=True)
    complete_cmd.add_argument("--system", default="")
    complete_cmd.add_argument("--model", default=DEFAULT_MODEL)
    args = parser.parse_args()
    if args.command == "history-minutes":
        try:
            print(json.dumps(last_n_minutes(args.minutes, args.lease), indent=2))
            return 0
        except ValueError as error:
            print(json.dumps({"error": str(error)}), file=sys.stderr)
            return 1
    if args.command == "history-windows":
        try:
            print(json.dumps(last_n_windows(args.windows, args.lease), indent=2))
            return 0
        except ValueError as error:
            print(json.dumps({"error": str(error)}), file=sys.stderr)
            return 1
    if args.command == "history-clipboard":
        try:
            print(json.dumps(last_n_clipboard(args.count, args.lease), indent=2))
            return 0
        except ValueError as error:
            print(json.dumps({"error": str(error)}), file=sys.stderr)
            return 1
    if args.command == "workflows":
        print(Path(__file__).with_name("workflows.json").read_text())
        return 0
    if args.command == "complete":
        try:
            text = complete_text(
                args.prompt,
                system=args.system or None,
                model=args.model,
            )
        except CompletionError as error:
            print(json.dumps({"error": str(error)}), file=sys.stderr)
            return 1
        print(text)
        return 0
    if args.command == "skills":
        if args.skills_command == "list":
            payload = list_skills(args.action)
        elif args.skills_command == "filter":
            payload = filter_skills(args.action, args.query)
        else:
            payload = create_skill(args.action, args.name, description=args.description)
        print(json.dumps(payload, indent=2))
        return 0
    store = Store(args.db)
    try:
        if args.command == "preview":
            result = plan(json.loads(args.fixture.read_text()))
            result["run_id"] = store.save_preview(result)
        elif args.command == "hold":
            result = {"mode": "local", "holds": store.hold(args.run_id)}
        else:
            result = {"mode": "local", "holds": store.confirm(args.run_id, args.option_id)}
        print(json.dumps(result, indent=2))
        return 0
    except (ValueError, KeyError, OSError) as error:
        print(json.dumps({"error": str(error)}), file=sys.stderr)
        return 1
    finally:
        store.close()


if __name__ == "__main__":
    raise SystemExit(main())

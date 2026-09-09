#!/usr/bin/env python3
"""Modules: browse, install, and remove other people's work.

A module is a folder of plain files that teaches this assistant one new job.
Installing one means writing that folder into this brain at
`.claude/skills/<name>/`; removing one means putting that folder in the Trash.
That is the whole mechanism.

This script exists so the rules are MECHANICAL. Rin used to install modules
from a screen inside the app, and the checks lived in its Swift: a hash for
every file, an allow list of what a module may contain, a cap on how big it may
be, and a staging folder so a download that dies halfway leaves nothing behind.
The screen went away; the checks did not get to become prose. They
are all here, and the assistant's job is to ask and to report, never to verify
by eye.

    python3 scripts/module.py list
    python3 scripts/module.py show <name>
    python3 scripts/module.py install <name>
    python3 scripts/module.py installed
    python3 scripts/module.py remove <name>

Nothing here installs without being named. There is no update-all, no
subscribe, and no call home: the list is fetched when it is asked for and at no
other time.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

INDEX_URL = "https://raw.githubusercontent.com/exata531/Rin/main/modules/index.json"
REGISTRY_PAGE = "https://petermei.com/rin/modules.html"
GUIDE_URL = "https://github.com/exata531/Rin/blob/main/docs/modules.md"

# A module is text and small scripts. Both halves of this rule matter: the
# suffix list says what may arrive, and the size caps say how much of it.
ALLOWED_SUFFIXES = {"md", "json", "txt", "yml", "yaml", "toml", "py", "sh", "js", "ts"}
ALLOWED_NAMES = {"LICENSE", "LICENCE", "NOTICE", "CHANGELOG"}
MAX_FILE_BYTES = 64 * 1024
MAX_TOTAL_BYTES = 512 * 1024
MAX_FILES = 40

NAME = re.compile(r"^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$")
TIMEOUT = 20


class Refused(Exception):
    """A rule said no. The message is written for a person to read."""


# ── where things live ────────────────────────────────────────────────────────


def brain(root: str | None) -> Path:
    path = Path(root).expanduser() if root else Path.cwd()
    return path.resolve()


def skills_folder(root: Path) -> Path:
    return root / ".claude" / "skills"


# ── the list ─────────────────────────────────────────────────────────────────


def fetch(url: str, what: str) -> bytes:
    """One GET, through curl.

    Not urllib, deliberately. Python's SSL layer trusts whatever certificate
    bundle that particular python was built against, and on a Mac that has
    installed python from anywhere other than Apple, that bundle is routinely
    missing, the first run of this script on the machine it was written on died
    on exactly that. curl ships with macOS and uses the system's own trust
    store, so it works on a stranger's Mac without them having to fix their
    python first.
    """
    result = subprocess.run(
        ["curl", "-fsSL", "--max-time", str(TIMEOUT), "--proto", "=https", url],
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        detail = result.stderr.decode("utf-8", "replace").strip() or f"curl exited {result.returncode}"
        raise Refused(f"Could not fetch {what}: {detail}")
    return result.stdout


def fetch_index() -> list[dict]:
    body = fetch(INDEX_URL, "the module list")
    try:
        return json.loads(body)["modules"]
    except (ValueError, KeyError) as error:
        raise Refused("The module list came back in a shape this script does not know.") from error


def find(name: str) -> dict:
    for module in fetch_index():
        if module.get("name") == name:
            return module
    raise Refused(f"No module called {name} is on the list. Browse them at {REGISTRY_PAGE}")


def label(module: dict) -> str:
    """The one line that has to be true before anybody agrees to this. Computed
    by the registry from the module's own files, never from its description."""
    return {"network": "reaches the network", "code": "runs code"}.get(
        module.get("tier", "text"), "text only"
    )


def runs_unasked(module: dict) -> bool:
    return bool(module.get("hookEvents")) or module.get("adds", {}).get("servers", 0) > 0


def adds_line(module: dict) -> str:
    adds = module.get("adds", {})
    parts = []
    for key, noun in (("skills", "skill"), ("agents", "agent"), ("commands", "command")):
        count = len(adds.get(key) or [])
        if count:
            parts.append(f"{count} {noun}{'' if count == 1 else 's'}")
    servers = adds.get("servers", 0)
    if servers:
        parts.append(f"{servers} background server{'' if servers == 1 else 's'}")
    return ", ".join(parts) or "nothing"


def source_url(module: dict) -> str:
    source = module.get("source", {})
    commitish = source.get("sha") or source.get("ref") or "main"
    return f"https://github.com/{source.get('repo')}/tree/{commitish}/{source.get('path')}"


# ── checking, before a single byte is fetched ────────────────────────────────


def check(module: dict) -> None:
    files = module.get("files") or []
    if not files:
        raise Refused("That entry lists no files, so there is nothing to install.")
    if len(files) > MAX_FILES:
        raise Refused(f"That module is {len(files)} files; a module may be {MAX_FILES}.")
    total = sum(int(entry.get("bytes", 0)) for entry in files)
    if total > MAX_TOTAL_BYTES:
        raise Refused(f"That module is {total // 1024} KB; a module may be {MAX_TOTAL_BYTES // 1024} KB.")
    for entry in files:
        path = entry.get("path", "")
        size = int(entry.get("bytes", 0))
        if size > MAX_FILE_BYTES:
            raise Refused(f"{path} is {size // 1024} KB; one file may be {MAX_FILE_BYTES // 1024} KB.")
        parts = path.split("/")
        if (
            not path
            or path.startswith("/")
            or path.startswith("~")
            or len(path) >= 200
            or any(part in ("", ".", "..") for part in parts)
        ):
            raise Refused(f"That module wants to write to {path}, which is not somewhere a module may write.")
        name = parts[-1]
        suffix = name.rsplit(".", 1)[-1] if "." in name else ""
        if suffix not in ALLOWED_SUFFIXES and name not in ALLOWED_NAMES:
            raise Refused(f"{path} is not a kind of file a module may contain.")
        if len(entry.get("sha256", "")) != 64:
            raise Refused(f"{path} has no usable hash on the list, so it cannot be verified.")


def fetch_file(module: dict, entry: dict) -> bytes:
    source = module["source"]
    commitish = source.get("sha") or source.get("ref") or "main"
    url = (
        f"https://raw.githubusercontent.com/{source['repo']}/{commitish}/"
        f"{source['path']}/{entry['path']}"
    )
    body = fetch(url, entry["path"])

    # The hash is the whole trust story: the list says what each file is, and a
    # file that is anything else does not get written. Without this the pinned
    # commit would be decoration.
    digest = hashlib.sha256(body).hexdigest()
    if digest != entry["sha256"] or len(body) != int(entry["bytes"]):
        raise Refused(f"{entry['path']} did not match what the list said it would be, so nothing was installed.")
    return body


# ── the verbs ────────────────────────────────────────────────────────────────


def cmd_list(args) -> int:
    modules = fetch_index()
    here = {folder.name for folder in installed_folders(brain(args.brain))}
    if args.json:
        print(json.dumps(modules, indent=2))
        return 0
    for module in modules:
        mark = "installed" if module["name"] in here else label(module)
        print(f"{module['name']}  [{mark}]")
        print(f"  {module['title']}, by {module.get('author', {}).get('github', 'unknown')}")
        print(f"  {module['summary']}")
        if runs_unasked(module):
            print("  starts on its own")
        print()
    print(f"{len(modules)} on the list. Browse: {REGISTRY_PAGE}")
    return 0


def cmd_show(args) -> int:
    module = find(args.name)
    print(f"{module['title']} ({module['name']})")
    print(f"by {module.get('author', {}).get('github', 'unknown')}, {label(module)}")
    print()
    print(module["summary"])
    print()
    print(f"Adds: {adds_line(module)}")
    print(f"Size: {len(module.get('files', []))} files, {module.get('bytes', 0) // 1024} KB")
    if module.get("hookEvents"):
        print(f"Runs by itself on: {', '.join(module['hookEvents'])}")
    for command in module.get("hookCommands") or []:
        print(f"  $ {command}")
    if module.get("network"):
        print(f"Talks to: {', '.join(module['network'])}")
    print(f"Code: {source_url(module)}")
    print()
    print("Nobody reviews these for safety. The labels are read out of the module's")
    print("own files, so they can be wrong in both directions.")
    return 0


def cmd_install(args) -> int:
    root = brain(args.brain)
    folder = skills_folder(root)
    module = find(args.name)
    destination = folder / module["name"]
    if destination.exists():
        raise Refused(f"{module['title']} is already in this brain.")

    check(module)

    # Everything lands on disk and verifies before anything enters the brain, so
    # a download that dies halfway leaves no half-module behind for the
    # assistant to find and half-follow.
    staging = Path(tempfile.mkdtemp(prefix="rin-module-"))
    try:
        for entry in module["files"]:
            body = fetch_file(module, entry)
            target = staging / entry["path"]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(body)

        source = module["source"]
        receipt = {
            "name": module["name"],
            "title": module["title"],
            "repo": source["repo"],
            "path": source["path"],
            "commitish": source.get("sha") or source.get("ref") or "main",
            "installedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        (staging / ".rin-module.json").write_text(json.dumps(receipt, indent=2, sort_keys=True))

        folder.mkdir(parents=True, exist_ok=True)
        shutil.move(str(staging), str(destination))
    finally:
        shutil.rmtree(staging, ignore_errors=True)

    print(f"Installed {module['title']} into {destination.relative_to(root)}")
    print("It works in the next tab you open. Tabs already running keep what they started with.")
    return 0


def installed_folders(root: Path) -> list[Path]:
    folder = skills_folder(root)
    if not folder.is_dir():
        return []
    return sorted(
        entry for entry in folder.iterdir()
        if entry.is_dir() and (entry / ".claude-plugin" / "plugin.json").is_file()
    )


def cmd_installed(args) -> int:
    root = brain(args.brain)
    folders = installed_folders(root)
    if not folders:
        print("Nothing installed. Browse the list, or ask for a module and one gets written.")
        return 0
    for entry in folders:
        manifest = json.loads((entry / ".claude-plugin" / "plugin.json").read_text())
        receipt = entry / ".rin-module.json"
        origin = "yours" if not receipt.is_file() else json.loads(receipt.read_text())["repo"]
        print(f"{manifest.get('name', entry.name)}  [{origin}]")
        if manifest.get("description"):
            print(f"  {manifest['description']}")
    return 0


def cmd_remove(args) -> int:
    root = brain(args.brain)
    target = skills_folder(root) / args.name
    if not target.is_dir():
        raise Refused(f"There is no {args.name} in this brain.")
    # The Trash, not a delete. Somebody removing a module they wrote themselves
    # should be able to get it back.
    script = f'tell application "Finder" to delete POSIX file "{target}"'
    result = subprocess.run(
        ["osascript", "-e", script], capture_output=True, text=True, check=False
    )
    if result.returncode != 0:
        raise Refused(f"Could not move {args.name} to the Trash: {result.stderr.strip()}")
    print(f"Moved {args.name} to the Trash. Nothing else about it is stored anywhere.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--brain", help="the brain folder (default: this one)")
    verbs = parser.add_subparsers(dest="verb", required=True)

    listing = verbs.add_parser("list", help="what is on the list")
    listing.add_argument("--json", action="store_true")
    listing.set_defaults(run=cmd_list)

    show = verbs.add_parser("show", help="everything one module can do")
    show.add_argument("name")
    show.set_defaults(run=cmd_show)

    install = verbs.add_parser("install", help="write one into this brain")
    install.add_argument("name")
    install.set_defaults(run=cmd_install)

    here = verbs.add_parser("installed", help="what this brain already has")
    here.set_defaults(run=cmd_installed)

    remove = verbs.add_parser("remove", help="move one to the Trash")
    remove.add_argument("name")
    remove.set_defaults(run=cmd_remove)

    args = parser.parse_args()
    if getattr(args, "name", None) and not NAME.match(args.name):
        print("A module name is lowercase letters, digits and hyphens.", file=sys.stderr)
        return 2
    try:
        return args.run(args)
    except Refused as refusal:
        print(refusal, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

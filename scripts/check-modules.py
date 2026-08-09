#!/usr/bin/env python3
# checks a module before it goes on the list
# listing is not endorsement but it should at least not be careless

"""Check every module in the registry, then write the index Rin reads.

Three jobs, one pass, no dependencies outside the standard library:

  1. Validate `modules/registry.json` and each module folder it points at.
  2. Read every file a module ships and work out what it can DO, whether it
     runs code, whether it reaches the network, what its hooks fire on. Those
     labels are computed from the files themselves, never taken from what the
     author says about them, which is the only version of that claim worth
     printing.
  3. Write `modules/index.json`: the same list with the labels attached and a
     hash for every file. Rin installs from that index and refuses any file whose hash
     does not match, so what a person sees on the card is what lands in their
     folder.

Run it with no arguments to check and rewrite the index:

    python3 scripts/check-modules.py

`--report` prints the same findings as markdown, which is what the pull
request check posts back into the thread. `--offline` skips modules hosted in
someone else's repo, for when there is no network.

Exit code is 1 if anything failed, which is the whole gate.
"""

import argparse
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOME_REPO = "exata531/Rin"

# A module is text and small scripts. Anything else is either a mistake or
# something that should not be arriving through a list of links.
ALLOWED_SUFFIXES = {
    ".md", ".json", ".txt", ".yml", ".yaml", ".toml",
    ".py", ".sh", ".js", ".ts",
}
ALLOWED_NAMES = {"LICENSE", "LICENCE", "NOTICE", "CHANGELOG"}

MAX_FILE_BYTES = 64 * 1024
MAX_TOTAL_BYTES = 512 * 1024
MAX_FILES = 40

CATEGORIES = [
    "school", "writing", "reading", "health",
    "money", "media", "home", "system",
]

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
SHA_RE = re.compile(r"^[a-f0-9]{40}$")

# Reaching for one of these is not a label, it is a rejection. None of them
# have an honest reason to appear in a module that helps somebody keep notes.
FORBIDDEN = [
    (r"security\s+find-generic-password", "reads the macOS Keychain"),
    (r"\.claude/(settings|\.credentials)", "reads or writes Claude Code's own settings"),
    (r"ANTHROPIC_API_KEY", "reaches for an API key"),
    (r"~/\.ssh|\$HOME/\.ssh", "reads SSH keys"),
    (r"~/\.aws|\$HOME/\.aws", "reads cloud credentials"),
    (r"Library/Messages|chat\.db", "reads the Messages database"),
    (r"Library/Mail\b", "reads the Mail store"),
    (r"Library/Cookies|Cookies\.binarycookies", "reads browser cookies"),
    (r"Photos\.sqlite", "reads the Photos library"),
    (r"\beval\s*\(|\bexec\s*\(", "evaluates code built at runtime"),
    (r"curl[^\n|]*\|\s*(ba)?sh", "pipes a download straight into a shell"),
    (r"claude\s+plugin\s+(install|marketplace)", "installs software on its own"),
    (r"(pip3?|npm|brew|gem)\s+install", "installs software on its own"),
    (r"git\s+(remote\s+add|push)\b", "pushes the folder somewhere"),
]

# These are labels, not rejections: a module is allowed to run code and allowed
# to talk to the network, as long as the card says so before anyone installs it.
#
# Prose is judged more narrowly than code, because a link in a paragraph is
# not a network call. What counts in a markdown file is an instruction the
# assistant would actually carry out; what counts in a script is any of it.
# A bare link is NOT one of these on purpose. Every manifest carries a homepage
# and every README carries a repo link, so counting "https://" would paint the
# loudest label on the quietest module and the label would stop meaning
# anything. What counts is something that would actually place a call.
NETWORK_HINTS = [
    r"\bcurl\b", r"\bwget\b", r"urllib", r"\brequests\b", r"httpx",
    r"\bsocket\b", r"fetch\s*\(",
    r"\bWebFetch\b", r"\bWebSearch\b",
]
PROSE_NETWORK_HINTS = [r"\bcurl\b", r"\bwget\b", r"\bWebFetch\b", r"\bWebSearch\b"]

# Files nothing reads but a person. They are checked for the forbidden list
# like everything else, and they never earn a capability label on their own.
DOC_FILES = {"README.md", "LICENSE", "LICENCE", "NOTICE", "CHANGELOG.md"}

CODE_SUFFIXES = {".py", ".sh", ".js", ".ts"}


class Failure(Exception):
    pass


def read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise Failure(f"{path.relative_to(ROOT)} is missing")
    except json.JSONDecodeError as error:
        raise Failure(f"{path.relative_to(ROOT)} is not valid JSON: {error}")


# ── collecting a module's files ──────────────────────────────────────────────
# Local modules are read off disk. Modules that live in somebody else's repo
# are read at the exact commit the registry entry pins, which is the only
# version anybody will ever install.

def local_files(folder: Path):
    files = []
    for path in sorted(folder.rglob("*")):
        if path.is_dir() or path.name == ".DS_Store":
            continue
        files.append((str(path.relative_to(folder)), path.read_bytes()))
    return files


def github_files(repo: str, path: str, sha: str):
    token = os.environ.get("GITHUB_TOKEN")

    def get(url, accept="application/vnd.github+json"):
        request = urllib.request.Request(url, headers={
            "Accept": accept,
            "User-Agent": "rin-module-check",
            **({"Authorization": f"Bearer {token}"} if token else {}),
        })
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.read()

    tree_url = f"https://api.github.com/repos/{repo}/git/trees/{sha}?recursive=1"
    try:
        tree = json.loads(get(tree_url))
    except urllib.error.HTTPError as error:
        raise Failure(f"cannot read {repo} at {sha[:8]}: HTTP {error.code}")
    except urllib.error.URLError as error:
        raise Failure(f"cannot reach github for {repo}: {error.reason}")

    prefix = "" if path in ("", ".") else path.rstrip("/") + "/"
    files = []
    for node in tree.get("tree", []):
        if node.get("type") != "blob" or not node["path"].startswith(prefix):
            continue
        relative = node["path"][len(prefix):]
        raw = f"https://raw.githubusercontent.com/{repo}/{sha}/{node['path']}"
        files.append((relative, get(raw, accept="text/plain")))
    if not files:
        raise Failure(f"{repo}/{path} at {sha[:8]} holds no files")
    return sorted(files)


# ── reading what a module can do ─────────────────────────────────────────────

def scan(name: str, files):
    """Work out, from the files alone, what this module adds and what it can do."""
    problems = []
    notes = []
    skills, agents, commands = [], [], []
    hook_events, hook_commands = [], []
    servers = 0
    runs_code = False
    network = []

    total = sum(len(body) for _, body in files)
    if len(files) > MAX_FILES:
        problems.append(f"ships {len(files)} files; the limit is {MAX_FILES}")
    if total > MAX_TOTAL_BYTES:
        problems.append(f"is {total // 1024} KB; the limit is {MAX_TOTAL_BYTES // 1024} KB")

    manifest = None
    for relative, body in files:
        path = Path(relative)
        if path.suffix not in ALLOWED_SUFFIXES and path.name not in ALLOWED_NAMES:
            problems.append(f"{relative} is not a kind of file a module may ship")
            continue
        if len(body) > MAX_FILE_BYTES:
            problems.append(f"{relative} is {len(body) // 1024} KB; the limit per file is {MAX_FILE_BYTES // 1024} KB")
        try:
            text = body.decode("utf-8")
        except UnicodeDecodeError:
            problems.append(f"{relative} is not text")
            continue

        for pattern, why in FORBIDDEN:
            if re.search(pattern, text, re.IGNORECASE):
                problems.append(f"{relative} {why}")
        for line in text.splitlines():
            if len(line) > 500:
                problems.append(f"{relative} has a 500-plus character line, which usually means generated or minified code")
                break
        if re.search(r"[A-Za-z0-9+/]{200,}={0,2}", text):
            problems.append(f"{relative} carries a long encoded blob")

        if path.suffix in CODE_SUFFIXES or text.startswith("#!"):
            runs_code = True
        if path.name not in DOC_FILES:
            hints = PROSE_NETWORK_HINTS if path.suffix == ".md" else NETWORK_HINTS
            for hint in hints:
                if re.search(hint, text):
                    network.append(relative)
                    break

        parts = path.parts
        if path.name == "SKILL.md":
            skills.append(parts[1] if len(parts) > 2 and parts[0] == "skills" else name)
        elif parts[:1] == ("agents",) and path.suffix == ".md":
            agents.append(path.stem)
        elif parts[:1] == ("commands",) and path.suffix == ".md":
            commands.append(path.stem)
        elif relative == ".claude-plugin/plugin.json":
            manifest = text
        elif relative in ("hooks/hooks.json", ".mcp.json", ".lsp.json", "monitors/monitors.json"):
            runs_code = True

    if manifest is None:
        problems.append("has no .claude-plugin/plugin.json, so nothing would load it")
    else:
        try:
            declared = json.loads(manifest)
        except json.JSONDecodeError as error:
            problems.append(f"its plugin.json is not valid JSON: {error}")
            declared = {}
        if declared.get("name") != name:
            problems.append(f"its plugin.json is named '{declared.get('name')}' but the registry calls it '{name}'")
        for field in ("hooks", "mcpServers", "lspServers"):
            if declared.get(field):
                runs_code = True
        servers += len(declared.get("mcpServers") or {})

    for relative, body in files:
        if relative != "hooks/hooks.json":
            continue
        try:
            hooks = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            problems.append("its hooks.json is not valid JSON")
            continue
        for event, entries in (hooks.get("hooks") or hooks).items():
            if not isinstance(entries, list):
                continue
            hook_events.append(event)
            for entry in entries:
                for hook in entry.get("hooks", []) if isinstance(entry, dict) else []:
                    command = hook.get("command")
                    if isinstance(command, str):
                        hook_commands.append(command)

    for relative, body in files:
        if relative != ".mcp.json":
            continue
        try:
            declared = json.loads(body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            problems.append("its .mcp.json is not valid JSON")
            continue
        servers += len(declared.get("mcpServers") or {})

    if not skills:
        problems.append("ships no skill, so it would teach the assistant nothing")
    if not any(relative == "README.md" for relative, _ in files):
        problems.append("has no README.md")

    if servers:
        network.append(".mcp.json")

    tier = "text" if not runs_code else "code"
    if network:
        tier = "network"

    if runs_code and not hook_commands and tier != "network":
        notes.append("ships scripts, but nothing that runs on its own")
    if hook_events:
        notes.append("runs by itself on: " + ", ".join(sorted(set(hook_events))))

    return {
        "tier": tier,
        "adds": {
            "skills": sorted(set(skills)),
            "agents": sorted(set(agents)),
            "commands": sorted(set(commands)),
            "servers": servers,
        },
        "hookEvents": sorted(set(hook_events)),
        "hookCommands": hook_commands,
        "network": sorted(set(network)),
        "notes": notes,
        "bytes": total,
        "files": [
            {
                "path": relative,
                "bytes": len(body),
                "sha256": hashlib.sha256(body).hexdigest(),
            }
            for relative, body in files
        ],
    }, problems


# ── the registry itself ──────────────────────────────────────────────────────

def check_entry(entry, seen):
    problems = []
    name = entry.get("name")
    if not isinstance(name, str) or not NAME_RE.match(name or ""):
        problems.append(f"name '{name}' must be lowercase words joined by hyphens")
    if name in seen:
        problems.append(f"'{name}' is listed twice")
    if isinstance(name, str) and name.startswith("rin-"):
        problems.append(f"'{name}' uses the rin- prefix, which is kept for modules that ship with the app")
    for field in ("title", "summary"):
        if not isinstance(entry.get(field), str) or not entry[field].strip():
            problems.append(f"'{name}' has no {field}")
    if len(entry.get("summary", "")) > 240:
        problems.append(f"'{name}' has a summary longer than 240 characters")
    if entry.get("category") not in CATEGORIES:
        problems.append(f"'{name}' has category '{entry.get('category')}'; pick one of {', '.join(CATEGORIES)}")
    author = entry.get("author") or {}
    if not author.get("name") or not author.get("github"):
        problems.append(f"'{name}' needs an author name and github handle")

    source = entry.get("source") or {}
    repo, path = source.get("repo"), source.get("path")
    if not isinstance(repo, str) or repo.count("/") != 1:
        problems.append(f"'{name}' needs a source repo like owner/name")
    if not isinstance(path, str) or path.startswith("/") or ".." in path:
        problems.append(f"'{name}' has a source path that is not a plain folder inside the repo")
    if repo != HOME_REPO:
        sha = source.get("sha")
        if not isinstance(sha, str) or not SHA_RE.match(sha or ""):
            problems.append(
                f"'{name}' lives in another repo, so it needs \"sha\" set to a full 40-character "
                "lowercase commit hash. That commit is the only version anyone will install."
            )
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", action="store_true", help="print the findings as markdown")
    parser.add_argument("--offline", action="store_true", help="skip modules hosted in other repos")
    parser.add_argument("--check-only", action="store_true", help="do not rewrite index.json")
    args = parser.parse_args()

    registry = read_json(ROOT / "modules" / "registry.json")
    entries = registry.get("modules")
    if not isinstance(entries, list):
        print("modules/registry.json has no modules list", file=sys.stderr)
        return 1

    index, failures, seen = [], {}, set()
    for entry in entries:
        name = entry.get("name", "?")
        problems = check_entry(entry, seen)
        seen.add(name)
        if problems:
            failures[name] = problems
            continue

        source = entry["source"]
        try:
            if source["repo"] == HOME_REPO:
                folder = ROOT / source["path"]
                if not folder.is_dir():
                    raise Failure(f"{source['path']} is not a folder in this repo")
                files = local_files(folder)
            elif args.offline:
                continue
            else:
                files = github_files(source["repo"], source["path"], source["sha"])
        except Failure as error:
            failures[name] = [str(error)]
            continue

        scanned, problems = scan(name, files)
        if problems:
            failures[name] = problems
            continue

        index.append({
            "name": name,
            "title": entry["title"],
            "summary": entry["summary"],
            "category": entry["category"],
            "author": entry["author"],
            "source": source,
            **scanned,
        })

    if args.report:
        print(report(index, failures))
    else:
        for name, problems in failures.items():
            for problem in problems:
                print(f"{name}: {problem}", file=sys.stderr)
        for module in index:
            adds = module["adds"]
            print(f"{module['name']}: {label(module['tier'])}, "
                  f"{len(adds['skills'])} skill(s), {len(module['files'])} files")

    if failures:
        return 1

    if not args.check_only:
        (ROOT / "modules" / "index.json").write_text(
            json.dumps({"registry": registry["registry"], "modules": index}, indent=2) + "\n",
            encoding="utf-8",
        )
    return 0


def label(tier):
    return {
        "text": "text only",
        "code": "runs code",
        "network": "reaches the network",
    }[tier]


def report(index, failures):
    lines = ["## What the check found", ""]
    if failures:
        lines.append("**This cannot be merged yet.**")
        lines.append("")
        for name, problems in failures.items():
            lines.append(f"- `{name}`")
            lines.extend(f"  - {problem}" for problem in problems)
        lines.append("")
    for module in index:
        adds = module["adds"]
        lines.append(f"### {module['name']}, {label(module['tier'])}")
        parts = []
        if adds["skills"]:
            parts.append(f"{len(adds['skills'])} skill(s): {', '.join(adds['skills'])}")
        if adds["agents"]:
            parts.append(f"{len(adds['agents'])} agent(s)")
        if adds["commands"]:
            parts.append(f"{len(adds['commands'])} command(s)")
        if adds["servers"]:
            parts.append(f"{adds['servers']} server(s)")
        lines.append("Adds " + ("; ".join(parts) if parts else "nothing"))
        lines.append(f"{len(module['files'])} files, {module['bytes'] // 1024 or 1} KB")
        if module["hookCommands"]:
            lines.append("")
            lines.append("Runs by itself:")
            lines.append("```")
            lines.extend(module["hookCommands"])
            lines.append("```")
        if module["network"]:
            lines.append("")
            lines.append("Network mentioned in: " + ", ".join(f"`{path}`" for path in module["network"]))
        lines.append("")
    lines.append("These labels are read out of the module's own files. They can be wrong "
                 "in both directions, and they are a place to start reading the code, not "
                 "a substitute for reading it.")
    return "\n".join(lines)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Failure as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)

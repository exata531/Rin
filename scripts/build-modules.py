#!/usr/bin/env python3
# builds the modules page on the site from the modules that actually exist
# so the list can never drift from what is really there

"""Write site/modules.html from modules/index.json.

The list on the website is baked in at deploy time rather than fetched by the
page, for the same reason the rest of the site is one self-contained file: it
loads with JavaScript off, it asks nothing of any other host, and an empty
registry renders as an invitation instead of a spinner that never resolves.

Everything interpolated here comes out of a pull request somebody else opened,
so every single field is escaped on the way in. That is the one place this
design introduces an injection surface the site did not have before.

    python3 scripts/build-modules.py

Run `scripts/check-modules.py` first, it is what writes the index this reads.
"""

import html
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

SLUG = re.compile(r"^[a-z0-9]([a-z0-9-]{0,62}[a-z0-9])?$")

ROOT = Path(__file__).resolve().parent.parent
INDEX = ROOT / "modules" / "index.json"
TEMPLATE = ROOT / "scripts" / "modules-template.html"
OUTPUT = ROOT / "site" / "modules.html"

LABELS = {
    "text": "text only",
    "code": "runs code",
    "network": "reaches the network",
}


def esc(value):
    return html.escape(str(value), quote=True)


def safe_url(value):
    """Only ever emit a link we built or one that is plainly an https link."""
    parsed = urlparse(str(value))
    return str(value) if parsed.scheme == "https" and parsed.netloc else ""


def source_url(module):
    source = module["source"]
    ref = source.get("sha") or source.get("ref") or "main"
    return f"https://github.com/{source['repo']}/tree/{ref}/{source['path']}"


def card(module):
    name = module["name"]
    adds = module["adds"]
    label = LABELS.get(module["tier"], module["tier"])

    bullets = []
    for kind in ("skills", "agents", "commands"):
        for item in adds.get(kind, []):
            bullets.append(f"<li>{esc(item)} <span class=\"pill\">{kind[:-1]}</span></li>")
    if adds.get("servers"):
        count = adds["servers"]
        bullets.append(f"<li>{count} background server{'' if count == 1 else 's'}</li>")
    if not bullets:
        bullets.append("<li>nothing the check could see</li>")

    runs = ""
    if module.get("hookCommands"):
        commands = "\n".join(esc(command) for command in module["hookCommands"])
        events = ", ".join(esc(event) for event in module.get("hookEvents", []))
        runs = (
            '<div class="runs"><strong>Runs on its own</strong>'
            + (f" ({events})" if events else "")
            + f":<pre>{commands}</pre></div>"
        )
    elif module.get("hookEvents"):
        runs = "<div class=\"runs\"><strong>Runs on its own</strong>: " \
               + ", ".join(esc(event) for event in module["hookEvents"]) + "</div>"

    kilobytes = max(1, module.get("bytes", 0) // 1024)
    haystack = " ".join([
        module["name"], module["title"], module["summary"],
        module["category"], module["author"]["github"], label,
    ]).lower()

    # The cards do not carry the reveal class the rest of the site uses. On the
    # front page a reveal is decoration over a headline; here the list IS the
    # page, and content that starts at zero opacity is a directory that looks
    # broken for the first half second: and looks empty in anything that
    # screenshots without scrolling.
    # Both ways in, on every card. The button is the move Raycast's web store
    # makes: a page cannot install anything, it can only ask the app to open on
    # the subject, and the app asks the person before it opens at all. The
    # command sits beside it because somebody who does not know what a link is
    # about to do should be able to read the plain version instead.
    command = f"/install {name}"
    get = f"""        <div class="get">
          <a class="add" href="rin://install/{esc(name)}">Add to Rin</a>
          <button class="say" type="button" data-copy="{esc(command)}"
                  aria-label="Copy {esc(command)}">
            <span class="cmd">{esc(command)}</span><span class="did" hidden>copied</span>
          </button>
        </div>"""

    return f"""      <article class="mod" id="m-{esc(name)}" data-cat="{esc(module['category'])}" data-text="{esc(haystack)}">
        <h3>{esc(module['title'])}</h3>
        <p class="by">by {esc(module['author']['github'])}</p>
        <p class="what">{esc(module['summary'])}</p>
        <div class="meta">
          <span class="pill">{esc(module['category'])}</span>
          <span class="pill">{esc(label)}</span>
        </div>
{get}
        <details>
          <summary>What it adds</summary>
          <div class="body">
            <ul>
{chr(10).join('              ' + bullet for bullet in bullets)}
            </ul>
            <p>{len(module['files'])} files, {kilobytes} KB.</p>
            {runs}
            <p><a href="{esc(safe_url(source_url(module)))}">Read the code</a></p>
          </div>
        </details>
      </article>"""


EMPTY = """      <div class="empty">
        <h3>Nothing here yet</h3>
        <p>The registry is a folder in a public repo, and the first module in it will
          be somebody's afternoon. Yours could be the one.</p>
        <a class="btn btn--solid" href="https://github.com/exata531/Rin/blob/main/docs/modules.md">How to write one</a>
      </div>"""


def main():
    if not INDEX.exists():
        print(f"{INDEX.relative_to(ROOT)} is missing, run scripts/check-modules.py first", file=sys.stderr)
        return 1
    try:
        modules = json.loads(INDEX.read_text(encoding="utf-8"))["modules"]
    except (json.JSONDecodeError, KeyError) as error:
        # Stopping here leaves the page that is already deployed in place, which
        # is the right failure: a module silently vanishing from the site is
        # worse than a build somebody can see go red.
        print(f"cannot read the module index: {error}", file=sys.stderr)
        return 1

    for module in sorted(modules, key=lambda entry: entry["title"].lower()):
        for field in ("name", "title", "summary", "category", "author", "source", "files"):
            if not module.get(field):
                print(f"module {module.get('name', '?')} has no {field}", file=sys.stderr)
                return 1
        # The name is the only field that ends up inside a URL rather than
        # inside text, so escaping it is not enough: it has to BE a name.
        if not SLUG.match(module["name"]):
            print(f"module name {module['name']!r} is not lowercase-hyphen-shaped", file=sys.stderr)
            return 1

    ordered = sorted(modules, key=lambda entry: entry["title"].lower())
    body = "\n".join(card(module) for module in ordered)
    grid = f'      <div class="mods">\n{body}\n      </div>' if ordered else EMPTY

    categories = sorted({module["category"] for module in ordered})
    chips = ['          <button class="cat" data-cat="" aria-pressed="true">All</button>']
    chips += [
        f'          <button class="cat" data-cat="{esc(category)}" aria-pressed="false">{esc(category)}</button>'
        for category in categories
    ]

    total = len(ordered)
    count = f"{total} module{'' if total == 1 else 's'}" if total else "none yet"

    page = TEMPLATE.read_text(encoding="utf-8")
    page = page.replace("      <!--MODULES-->", grid)
    page = page.replace("          <!--CATS-->", "\n".join(chips) if ordered else "")
    page = page.replace("<!--COUNT-->", count)
    OUTPUT.write_text(page, encoding="utf-8")
    print(f"wrote {OUTPUT.relative_to(ROOT)} with {total} module(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Mechanical checks for the addons in this repo.

    python scripts/lint.py            every addon
    python scripts/lint.py TradeMaster

There is no Lua on this machine, so these are the errors that can be caught without
running the game. Each check is here because it shipped broken at least once.
"""

import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECTS = os.path.join(ROOT, "AddonProjects")

# Interface\Buildings\White8x8 does not resolve on this client: every frame using it
# draws with no fill at all, and nothing errors. See client-api.md.
BAD_TEXTURES = [
    r"Interface\\+Buildings\\+White8x8",
]

findings = []


def note(path, line, message):
    try:
        rel = os.path.relpath(path, ROOT).replace("\\", "/")
    except ValueError:
        # A different drive has no relative path from the repo on Windows.
        rel = path.replace("\\", "/")
    findings.append("%s:%d  %s" % (rel, line, message))


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def in_comment(text, index):
    """True when the match sits on a line that starts with --.

    Documentation naming a banned pattern is not a use of it: this repo's own
    note about the dead texture path was the first thing the check found.
    """
    start = text.rfind("\n", 0, index) + 1
    return text[start:index].lstrip().startswith("--")


def lua_files(folder):
    for name in sorted(os.listdir(folder)):
        if name.endswith(".lua"):
            yield os.path.join(folder, name)


def check_parses(path, src):
    try:
        from luaparser import ast
    except ImportError:
        return
    try:
        ast.parse(src)
    except Exception as exc:  # noqa: BLE001 - any parse failure is a finding
        note(path, 1, "does not parse: %s" % str(exc).split("\n")[0])


SELF_REF = re.compile(r"\blocal\s+([A-Za-z_]\w*)\s*=\s*[^\n=]*?\(")


def check_self_reference(path, src):
    """local X = f(... X:something ...) reads a nil global.

    The local does not exist until the assignment finishes, so a callback written
    inside the call captures the global of the same name. This shipped as
    "attempt to index global 't'" the first time anyone clicked an order.
    """
    for m in SELF_REF.finditer(src):
        name = m.group(1)
        i, depth = m.end() - 1, 0
        while i < len(src):
            if src[i] == "(":
                depth += 1
            elif src[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        body = src[m.end():i]
        if in_comment(src, m.start()):
            continue
        # A field access (frame.count:GetText()) is a different name entirely.
        if re.search(r"(?<![.:\w])%s\s*[:.]" % re.escape(name), body):
            note(path, line_of(src, m.start()),
                 "`local %s = ...` refers to %s inside its own call: that is a nil global"
                 % (name, name))


def check_textures(path, src):
    for pattern in BAD_TEXTURES:
        for m in re.finditer(pattern, src):
            if in_comment(src, m.start()):
                continue
            note(path, line_of(src, m.start()),
                 "texture path does not resolve on this client, frames draw with no fill")


def toc_path(addon_dir):
    name = os.path.basename(addon_dir)
    return os.path.join(addon_dir, name + ".toc")


def check_toc(addon_dir):
    """Every top-level .lua is listed, every listed file exists, no Bindings.xml.

    The client loads Bindings.xml by filename; listing it loads the bindings twice.
    """
    toc = toc_path(addon_dir)
    if not os.path.exists(toc):
        return
    text = io.open(toc, encoding="utf-8").read()
    listed = []
    for i, raw in enumerate(text.splitlines(), 1):
        entry = raw.strip()
        if not entry or entry.startswith("#"):
            continue
        if entry.lower() == "bindings.xml":
            note(toc, i, "Bindings.xml is loaded by filename; listing it loads it twice")
            continue
        listed.append((i, entry))
        if not os.path.exists(os.path.join(addon_dir, entry.replace("\\", os.sep))):
            note(toc, i, "listed file does not exist: %s" % entry)

    top_level = set(e for _, e in listed if "\\" not in e and "/" not in e)
    for path in lua_files(addon_dir):
        name = os.path.basename(path)
        if name not in top_level:
            note(toc, 1, "%s is not listed, so the client never loads it" % name)


VERSION_TOC = re.compile(r"^##\s*Version:\s*(.+)$", re.M)
VERSION_LUA = re.compile(r'local\s+VERSION\s*=\s*"([^"]+)"')


def check_versions(addon_dir):
    """The .toc, the load message and the README table must agree.

    Four places move together on a release and one of them gets forgotten.
    """
    toc = toc_path(addon_dir)
    if not os.path.exists(toc):
        return
    name = os.path.basename(addon_dir)
    text = io.open(toc, encoding="utf-8").read()
    m = VERSION_TOC.search(text)
    if not m:
        note(toc, 1, "no ## Version: line")
        return
    version = m.group(1).strip()

    core = os.path.join(addon_dir, "Core.lua")
    if os.path.exists(core):
        src = io.open(core, encoding="utf-8").read()
        lua = VERSION_LUA.search(src)
        if lua and lua.group(1) != version:
            note(core, line_of(src, lua.start()),
                 "load message says %s, the .toc says %s" % (lua.group(1), version))

    readme = os.path.join(os.path.dirname(addon_dir), "README.md")
    if os.path.exists(readme):
        src = io.open(readme, encoding="utf-8").read()
        row = re.search(r"^\|\s*%s\s*\|\s*([^|]+?)\s*\|" % re.escape(name), src, re.M)
        if row and row.group(1) != version:
            note(readme, line_of(src, row.start()),
                 "%s is listed as %s, the .toc says %s" % (name, row.group(1), version))


def main(argv):
    wanted = set(argv[1:])
    checked = 0
    for flavor in sorted(os.listdir(PROJECTS)):
        flavor_dir = os.path.join(PROJECTS, flavor)
        if not os.path.isdir(flavor_dir):
            continue
        for addon in sorted(os.listdir(flavor_dir)):
            addon_dir = os.path.join(flavor_dir, addon)
            if not os.path.isdir(addon_dir):
                continue
            if wanted and addon not in wanted:
                continue
            checked += 1
            check_toc(addon_dir)
            check_versions(addon_dir)
            for root, _, names in os.walk(addon_dir):
                for name in sorted(names):
                    if not name.endswith(".lua"):
                        continue
                    path = os.path.join(root, name)
                    src = io.open(path, encoding="utf-8", errors="replace").read()
                    check_parses(path, src)
                    check_self_reference(path, src)
                    check_textures(path, src)

    if findings:
        print("\n".join(findings))
        print("\n%d finding%s across %d addon%s"
              % (len(findings), "" if len(findings) == 1 else "s",
                 checked, "" if checked == 1 else "s"))
        return 1
    print("clean: %d addon%s" % (checked, "" if checked == 1 else "s"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

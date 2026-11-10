"""Voice inventory: every player-facing fixed line in the game, in one page.

Scans the game's GDScript (sim, net, client, client3d, render, server, entities, main.gd)
for string literals that read as words to a player, and the data files under
levels/ (top-level *.json and levels/lore/*.json) for text values. Writes
docs/voice_inventory.md: each line with who says it (by file, a best guess),
where it lives, and whether lore's pages quote it (a line quoted in docs/lore/
is usually one Jeff passed; docs/voice.md names the ones he wrote himself).

Run: python -B tools/voice_inventory.py [--check]
--check exits 1 if docs/voice_inventory.md is out of date, naming this tool;
tests/land.sh and land.ps1 run it before the gate, so a tree that adds or
changes a player's line regenerates the page at its own landing (the
coordinator's, 2026-11-10: combat's hand edit, d1e21aedb, conflicted with
the regenerated page). It reads only the tree, and of it only the files git
knows (committed or staged; `git ls-files`): the scanned code, levels/ and
docs/lore/. Its output is the same on every checkout: sorted, LF line ends,
no date, no path outside the tree. land.sh warns until v0.1.211's unfreeze,
then fails (the coordinator's warn-first day, 748 amended (6)).

Heuristics, not a parser: a GDScript literal counts when it has three or more
words and a lowercase letter, and the line isn't a log/print/assert/comment.
Debug and editor text slips through now and then; that's fine for a review list.
"""

import json
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "docs", "voice_inventory.md")


def _tracked():
    """The files git knows here (committed or staged, `git ls-files`), so a
    scratch file never added doesn't change the page from one checkout to
    the next; None outside a git checkout, where every file counts."""
    try:
        out = subprocess.run(["git", "-C", ROOT, "ls-files", "-z"], capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return {p for p in out.decode("utf-8").split("\0") if p}


TRACKED = _tracked()


def counts(rel):
    """True when [param rel] (from the root, with /) is read: tracked, and on disk."""
    return (TRACKED is None or rel in TRACKED) and os.path.isfile(os.path.join(ROOT, rel))

GD_DIRS = ["sim", "net", "client", "client3d", "render", "server", "entities"]
GD_FILES = ["main.gd"]
# Tool and level-check text a player never reads.
SKIP_FILES = {"sim/level.gd", "client3d/art_check.gd", "client3d/character_lab.gd", "client3d/art_kit.gd"}

# Who says the lines in a file, when the file is one speaker's.
SPEAKER_BY_FILE = {
    "sim/draugr.gd": "the draugr",
    "sim/astral_knight.gd": "the fallen knight",
    "sim/companion.gd": "companions (Pip, Wren, Nix)",
    "sim/companion_mind.gd": "companions (prompt)",
    "sim/companion_card.gd": "companions (card)",
    "sim/companion_facts.gd": "companions (facts)",
    "sim/resident.gd": "residents",
    "sim/resident_card.gd": "residents (card)",
    "sim/townsfolk.gd": "townsfolk",
    "sim/town_memory.gd": "town talk",
    "sim/hearsay.gd": "town talk",
    "sim/lawspeaker.gd": "the lawspeaker",
    "sim/offers.gd": "deal and quest windows",
    "sim/named_mind.gd": "named enemies",
    "sim/named_enemy.gd": "named enemies",
}

SKIP_CALLS = re.compile(
    r"\b(print|printerr|print_debug|prints|push_error|push_warning|assert|_fail|_log|"
    r"log_line|mind_log|Log\.|OS\.|ProjectSettings|load|preload|get_node|has_node)\s*\("
)
STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
CONST = re.compile(r"^\s*(?:static\s+)?const\s+([A-Z_0-9]+)")
FUNC = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)")
WORD = re.compile(r"[A-Za-z']+")


def code_part(line):
    """The line up to a '#' that is outside any string."""
    out, in_str, esc = [], False, False
    for ch in line:
        if in_str:
            out.append(ch)
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == '"':
                in_str = False
        else:
            if ch == "#":
                break
            if ch == '"':
                in_str = True
            out.append(ch)
    return "".join(out)


def wordy(s, need):
    if "res://" in s or "user://" in s or "://" in s:
        return False
    if re.match(r"(error|warning)\b", s):
        return False
    if not re.search(r"[a-z]", s):
        return False
    if re.fullmatch(r"[\w./:%-]+", s):  # identifiers, keys, paths
        return False
    return len(WORD.findall(s)) >= need


def norm(s):
    s = s.replace("\\n", " ").replace('\\"', '"')
    return re.sub(r"\s+", " ", s).strip()


def lore_text():
    parts = []
    d = os.path.join(ROOT, "docs", "lore")
    for name in sorted(os.listdir(d)):
        if name.endswith(".md") and counts("docs/lore/" + name):
            with open(os.path.join(d, name), encoding="utf-8") as f:
                parts.append(re.sub(r"\s+", " ", f.read()))
    return " ".join(parts)


def quoted(line, lore):
    """True when every literal piece of the line (split at %s/%d) of 12+ chars is in lore's pages."""
    pieces = [p.strip(" ,.;:") for p in re.split(r"%[-0-9.]*[sdf]|\[name\]|<[^>]+>", line)]
    pieces = [p for p in pieces if len(p) >= 12]
    return bool(pieces) and all(p in lore for p in pieces)


def gd_files():
    for d in GD_DIRS:
        for base, dirs, names in os.walk(os.path.join(ROOT, d)):
            dirs.sort()  # The same order on every checkout and file system.
            for n in sorted(names):
                rel = os.path.relpath(os.path.join(base, n), ROOT).replace(os.sep, "/")
                if n.endswith(".gd") and rel not in SKIP_FILES and "/level_gen/" not in rel and counts(rel):
                    yield rel
    for f in GD_FILES:
        if counts(f):
            yield f


def scan_gd(rel):
    rows = []
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        lines = f.read().splitlines()
    ctx = ""
    for i, raw in enumerate(lines, 1):
        m = FUNC.match(raw)
        if m:
            ctx = m.group(1) + "()"
        stripped = raw.lstrip()
        if stripped.startswith("#"):
            continue
        code = code_part(raw)
        if SKIP_CALLS.search(code):
            continue
        c = CONST.match(raw)
        where = c.group(1) if c else ctx
        for lit in STRING.findall(code):
            text = norm(lit)
            if wordy(text, 3):
                rows.append((rel, i, where, text))
    return rows


def walk_json(node, path, out):
    if isinstance(node, dict):
        for k, v in node.items():
            if str(k).startswith("_"):  # notes for developers
                continue
            walk_json(v, path + "." + str(k) if path else str(k), out)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk_json(v, "%s[%d]" % (path, i), out)
    elif isinstance(node, str):
        text = norm(node)
        if wordy(text, 4):
            out.append((path, text))


def json_files():
    lv = os.path.join(ROOT, "levels")
    for n in sorted(os.listdir(lv)):
        if n.endswith(".json") and counts("levels/" + n):
            yield "levels/" + n
    for n in sorted(os.listdir(os.path.join(lv, "lore"))):
        if n.endswith(".json") and counts("levels/lore/" + n):
            yield "levels/lore/" + n


def md_cell(s):
    return s.replace("|", "\\|")


def build():
    lore = lore_text()
    out = [
        "<!-- Generated by tools/voice_inventory.py: a hand edit is overwritten, and land.sh checks this page is up to date. Run python -B tools/voice_inventory.py instead. -->",
        "# Voice inventory",
        "",
        "Generated by `python -B tools/voice_inventory.py`; don't edit by hand, re-run it.",
        "Places are file and function (or constant), without line numbers, so others' edits don't churn it.",
        "Every fixed line a player can read, found by a heuristic scan (see the script), with",
        "who says it (by file, a best guess), where it lives, and **L** when lore's pages",
        "(`docs/lore/`) quote it word for word, usually a line Jeff passed. The guide is",
        "`docs/voice.md`; Jeff's own words in it are never reworded without asking him.",
        "",
    ]
    by_speaker = {}
    for rel in gd_files():
        for row in scan_gd(rel):
            spk = SPEAKER_BY_FILE.get(rel, "server and windows" if rel == "main.gd" else "other (" + rel.split("/")[0] + ")")
            by_speaker.setdefault(spk, []).append(row)
    gd_total = sum(len(v) for v in by_speaker.values())
    out.append("## Lines in the code (%d)" % gd_total)
    out.append("")
    for spk in sorted(by_speaker):
        rows = by_speaker[spk]
        out.append("### %s (%d)" % (spk, len(rows)))
        out.append("")
        out.append("| | Line | Where |")
        out.append("|---|---|---|")
        for rel, i, where, text in rows:
            mark = "L" if quoted(text, lore) else ""
            out.append("| %s | %s | `%s` %s |" % (mark, md_cell(text), rel, where))
        out.append("")
    data_rows = []
    for rel in json_files():
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            try:
                data = json.load(f)
            except ValueError:
                continue
        found = []
        walk_json(data, "", found)
        data_rows.append((rel, found))
    out.append("## Lines in the data (%d)" % sum(len(f) for _, f in data_rows))
    out.append("")
    out.append("`levels/lore/*.json` are lore's facts: what is so, said to players through")
    out.append("residents, rumours and companions. Their wording is voice's to suggest and lore's to take.")
    out.append("")
    for rel, found in data_rows:
        if not found:
            continue
        out.append("### %s (%d)" % (rel, len(found)))
        out.append("")
        out.append("| | Line | Key |")
        out.append("|---|---|---|")
        for path, text in found:
            mark = "L" if quoted(text, lore) else ""
            out.append("| %s | %s | `%s` |" % (mark, md_cell(text), path))
        out.append("")
    return "\n".join(out) + "\n"


def main():
    text = build()
    if "--check" in sys.argv:
        # Read as text, so a checkout with CRLF line ends compares the same.
        try:
            with open(OUT, encoding="utf-8") as f:
                ok = f.read() == text
        except OSError:
            ok = False
        if ok:
            print("voice_inventory: up to date")
        else:
            print("voice_inventory: docs/voice_inventory.md is out of date: run python -B tools/voice_inventory.py"
                  " and commit the page with your change (it is generated; never edit it by hand).")
            print("voice_inventory: on a rebase conflict in the page, take either side and run the tool again;"
                  " never merge it by hand.")
            print("voice_inventory: it reads only the files git knows (committed or staged): a new script or data"
                  " file counts once you git add it, a scratch file never added doesn't.")
        sys.exit(0 if ok else 1)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("wrote " + os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()

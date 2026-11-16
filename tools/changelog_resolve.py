"""A CHANGELOG.md-only rebase conflict resolved at its source (decision 539
amended (3)): every release cut moves bullets out of ## Unreleased, and a
resolver that keeps both sides copies them back (dungeon, maps, terrain and
perf after v0.1.160 each did; 539's check refused each landing, a gate slot
late). Instead:

  * the file as it stands on the side being rebased onto (HEAD), cut and all;
  * plus, first under ## Unreleased in their own order, the bullets the commit
    being rebased (REBASE_HEAD) adds against its parent, those the file does
    not carry already (released or not);
  * less any bullet the commit takes out, so one it rewords is not doubled.

A bullet is its "- " line and the indented lines under it that carry it on
(539 amended (4): it kept a wrapped bullet's first line alone).

The generated pages too (539 amended (5): items lost a three-hour turn when
its rebase under the lock met docs/voice_inventory.md, docs/art_status.md and
art/kit/status.json, 2026-11-10): each conflicted one is taken from main's side
(`git checkout --ours`) and its generator run over the merged tree
(tools/voice_inventory.py; tools/art_status.gd under Godot, which also writes
THIRD_PARTY.md's art slot block: a file it changes is staged with the pages).

THIRD_PARTY.md itself too (539 amended (7): maps' Mughouse take met 919's and
920's slot lines there, 2026-11-14): its art and sound slot spans, each
between its marker lines, are written by tools/art_status.gd and
tools/sound_status.tscn (docs/sound_status.md beside it), never by hand. In a
conflict it is taken from main's side and both spans made again, only when
the commit being rebased changes nothing outside the spans and every marker
stands once on each side; main's text outside them must come through
unchanged.

A test file too (539 amended (8), the coordinator's (C), 2026-11-16: perf's
firstclick lost three turns at click_route_test's _ready, each side's new row
call added after the same last one). A tests/*.gd file is merged three ways
from its index stages (git merge-file --diff3), and taken only when every
conflicted hunk is rows added by both sides: no base line changed or removed,
every added line a row call (ROW: `_test_x(...)`, awaited or not) or a comment,
all at one indent, and no row name added by both. Main's rows stay first, the
take's after them, so the take's rows still run last as it wrote them. Any
other hunk in the file (two new functions met at its foot) refuses the whole
file, never half merged. Each merged file is printed, its rows by name, for the
landing's log. The resolver never continues the rebase: the merged file is what
the landing's suite then runs.

Run while `git rebase` is stopped with only CHANGELOG.md, those pages and such
test files in conflict (any of them):
  python -B tools/changelog_resolve.py      writes them, `git add`s them; exit 0
It does not continue the rebase. Exit 1 (nothing written, the conflict left as
it was) when the rebase is not stopped on a commit, another file is in conflict
(THIRD_PARTY.md changed outside its spans included, and a test file
whose conflict is more than rows added), the file has no
## Unreleased heading, or a generator fails. Standard library only.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

PATH = "CHANGELOG.md"
UNRELEASED = "## Unreleased"


def _git(*args):
    done = subprocess.run(["git"] + list(args), capture_output=True)
    if done.returncode != 0:
        raise OSError(done.stderr.decode("utf-8", "replace").strip())
    return done.stdout.decode("utf-8")


def bullets(lines):
    """[(start, end)]: each bullet's lines in [param lines], its "- " line
    and the indented ones under it that carry it on (539 amended (4): a
    bullet wrapped over lines is one bullet)."""
    out = []
    i = 0
    while i < len(lines):
        if lines[i].startswith("- "):
            end = i + 1
            while end < len(lines) and lines[end].startswith("  ") and lines[end].strip() != "":
                end += 1
            out.append((i, end))
            i = end
        else:
            i += 1
    return out


def _texts(text):
    lines = text.replace("\r\n", "\n").split("\n")
    return ["\n".join(lines[start:end]) for start, end in bullets(lines)]


def added_and_taken(before, after):
    """The bullets (each with its continuation lines) CHANGELOG.md
    [param after] has that [param before] does not, and those it no longer
    has, in their files' order."""
    old, new = _texts(before), _texts(after)
    return [bullet for bullet in new if bullet not in old], [bullet for bullet in old if bullet not in new]


def resolve(onto, added, taken):
    """[param onto]'s text with [param added] put first under ## Unreleased
    (those it does not carry anywhere) and [param taken] dropped from it;
    None if it has no ## Unreleased heading. A bullet is its "- " line with
    its continuation lines. Line ends as [param onto] has them."""
    crlf = "\r\n" in onto
    lines = onto.replace("\r\n", "\n").split("\n")
    heading = next((i for i, line in enumerate(lines) if line.strip() == UNRELEASED), None)
    if heading is None:
        return None
    spans = bullets(lines)
    carried = {"\n".join(lines[start:end]) for start, end in spans}
    gone = set(taken) - set(added)
    for start, end in reversed(spans):
        if start > heading and "\n".join(lines[start:end]) in gone and _unreleased(lines, heading, start):
            del lines[start:end]
    new = [line for bullet in dict.fromkeys(added) if bullet not in carried for line in bullet.split("\n")]
    at = heading + 1
    while at < len(lines) and lines[at].strip() == "":
        at += 1
    lines[at:at] = new
    if new and at == heading + 1:
        lines.insert(at, "")
    text = "\n".join(lines)
    return text.replace("\n", "\r\n") if crlf else text


def _unreleased(lines, heading, i):
    """Whether line [param i] is in ## Unreleased (before the next "## ")."""
    return not any(line.startswith("## ") for line in lines[heading + 1:i])


# --- The generated pages (539 amended (5)) ----------------------------------

## Pages a tool writes from the tree: in a conflict, main's side, made again
## over the merged tree. Each generator: the conflicted pages that call for
## it, every file it writes (one not in conflict that it changes is staged
## too, since the merged tree's output is the right one), its command.
GENERATORS = {
    "voice_inventory": {"pages": ["docs/voice_inventory.md"], "writes": ["docs/voice_inventory.md"]},
    "art_status": {"pages": ["docs/art_status.md", "art/kit/status.json"],
        "writes": ["docs/art_status.md", "art/kit/status.json", "THIRD_PARTY.md"]},
    # 539 amended (7), sound's yes: tools/sound_status.tscn, a scene (SoundKit
    # reads Senses, an autoload), from tracked files only.
    "sound_status": {"pages": ["docs/sound_status.md"], "writes": ["docs/sound_status.md", "THIRD_PARTY.md"]},
}
PAGES = [page for each in GENERATORS.values() for page in each["pages"]]
## THIRD_PARTY.md (539 amended (7)): hand-written credits around spans a
## generator writes, each between its own two marker lines. In a conflict it
## is taken from main's side and its spans made again (every span's
## generator runs), only when the commit being rebased changes nothing
## outside them and each marker stands once on every side; else it refuses as
## any other file does. Release: neither span is ever written by hand.
THIRD = "THIRD_PARTY.md"
SPANS = {"art_status": ("<!-- art slots:", "<!-- end of art slots -->"),
    "sound_status": ("<!-- sound slots:", "<!-- end of sound slots -->")}


def outside_spans(text):
    """[param text] with what lies between each span's markers cut out (the
    marker lines kept), or None when a marker is missing, doubled or out of
    order."""
    lines = text.replace("\r\n", "\n").split("\n")
    for start, end in SPANS.values():
        starts = [i for i, line in enumerate(lines) if line.startswith(start)]
        ends = [i for i, line in enumerate(lines) if line.startswith(end)]
        if len(starts) != 1 or len(ends) != 1 or ends[0] < starts[0]:
            return None
        lines = lines[:starts[0] + 1] + lines[ends[0]:]
    return "\n".join(lines)


def third_party_why(commit):
    """"" when THIRD_PARTY.md's conflict may be resolved from main's side,
    else why not."""
    try:
        before, after, ours = (_git("show", ref + ":" + THIRD) for ref in (commit + "^", commit, "HEAD"))
    except OSError:
        return "%s is new or gone on one side" % THIRD
    cut = [outside_spans(each) for each in (before, after, ours)]
    if None in cut:
        return "%s's span markers missing or doubled on a side" % THIRD
    if cut[0] != cut[1]:
        return "the commit changes %s outside its generated spans" % THIRD
    return ""


# --- Test files' rows (539 amended (8)) ------------------------------------

## A row call in a test's body ("_test_x(...)", awaited or not, a comment after
## it), and a comment line; each line's indent is its leading tabs.
ROW = re.compile(r"^(\t+)(?:await )?(_test_\w+)\(.*\)\s*(?:#.*)?$")
NOTE = re.compile(r"^(\t+)#.*$")


def is_test_file(path):
    return path.startswith("tests/") and path.endswith(".gd")


def merge_rows(base, ours, theirs):
    """[param base], [param ours] (main's side) and [param theirs] (the take's)
    merged three ways: (text, main's rows, the take's rows, "") when every
    conflicted hunk is rows added on both sides, main's first; else (None, [],
    [], why not)."""
    crlf = "\r\n" in ours
    folder = tempfile.mkdtemp(prefix="changelog_resolve_rows_")
    try:
        paths = []
        for name, text in (("main", ours), ("base", base), ("take", theirs)):
            paths.append(os.path.join(folder, name))
            with open(paths[-1], "w", encoding="utf-8", newline="") as handle:
                handle.write(text.replace("\r\n", "\n"))
        done = subprocess.run(["git", "merge-file", "-p", "--diff3", "-L", "main", "-L", "base", "-L", "take"] + paths,
            capture_output=True)
    finally:
        for name in os.listdir(folder):
            os.remove(os.path.join(folder, name))
        os.rmdir(folder)
    if done.returncode < 0 or done.returncode > 127:
        return None, [], [], "git merge-file failed (%d)" % done.returncode
    lines = done.stdout.decode("utf-8").split("\n")
    out, mains, takes, hunks = [], [], [], 0
    i = 0
    while i < len(lines):
        if not lines[i].startswith("<<<<<<< main"):
            out.append(lines[i])
            i += 1
            continue
        sides = {"main": [], "base": [], "take": []}
        side = "main"
        i += 1
        while i < len(lines) and not lines[i].startswith(">>>>>>> take"):
            if lines[i].startswith("||||||| base"):
                side = "base"
            elif lines[i] == "=======":
                side = "take"
            else:
                sides[side].append(lines[i])
            i += 1
        if i >= len(lines):
            return None, [], [], "a conflict hunk with no end"
        i += 1
        hunks += 1
        if sides["base"]:
            return None, [], [], "a hunk changes or removes a line (%s)" % sides["base"][0].strip()[:60]
        added = sides["main"] + sides["take"]
        bad = [line for line in added if not ROW.match(line) and not NOTE.match(line)]
        if bad:
            return None, [], [], "a hunk is not rows alone (%s)" % bad[0].strip()[:60]
        if len({(ROW.match(line) or NOTE.match(line)).group(1) for line in added}) != 1:
            return None, [], [], "a hunk's added rows stand at two indents"
        main_rows = [ROW.match(line).group(2) for line in sides["main"] if ROW.match(line)]
        take_rows = [ROW.match(line).group(2) for line in sides["take"] if ROW.match(line)]
        both = sorted(set(main_rows) & set(take_rows))
        if both:
            return None, [], [], "both sides add the row %s" % ", ".join(both)
        mains += main_rows
        takes += take_rows
        out += sides["main"] + sides["take"]
    if hunks == 0:
        return None, [], [], "no conflict hunk to merge"
    text = "\n".join(out)
    return (text.replace("\n", "\r\n") if crlf else text), mains, takes, ""


## The test's own commands (JSON {generator: argv}), never set in a landing.
COMMANDS_ENV = "CHANGELOG_RESOLVE_COMMANDS"
GENERATOR_SECONDS = 300
## A Godot run that printed one of these failed, whatever its exit code.
GODOT_FAILED = ("SCRIPT ERROR", "Parse Error", "ERROR:")


def command(name):
    """[name]'s generator as argv: voice_inventory.py with this Python, or
    art_status.gd (a script) or sound_status.tscn (a scene) under Godot
    ($GODOT_PATH, else `godot`, as land.sh's scripts find it), headless,
    silent, its own log (decision 664)."""
    override = os.environ.get(COMMANDS_ENV)
    if override:
        return json.loads(override)[name]
    if name == "voice_inventory":
        return [sys.executable, "-B", "tools/voice_inventory.py"]
    os.makedirs(os.path.join("build", "logs"), exist_ok=True)
    run = ["--script", "tools/art_status.gd"] if name == "art_status" else ["--scene", "res://tools/sound_status.tscn"]
    return [os.environ.get("GODOT_PATH") or "godot", "--headless", "--audio-driver", "Dummy",
        "--log-file", "build/logs/changelog_resolve_%s.log" % name, "--path", "."] + run


def generate(name):
    """Runs [name]'s generator (stdin closed, GENERATOR_SECONDS at most):
    "" when it worked, else why not."""
    argv = command(name)
    try:
        done = subprocess.run(argv, capture_output=True, stdin=subprocess.DEVNULL, timeout=GENERATOR_SECONDS)
    except (OSError, subprocess.TimeoutExpired) as error:
        return "%s: %s" % (name, error)
    out = (done.stdout + done.stderr).decode("utf-8", "replace")
    failed = done.returncode != 0 or (name != "voice_inventory" and any(each in out for each in GODOT_FAILED))
    return "%s exit %d: %s" % (name, done.returncode, out.strip()[-400:]) if failed else ""


def _changed(path):
    """Whether [path] in the working tree differs from the index."""
    return subprocess.run(["git", "diff", "--quiet", "--", path], capture_output=True).returncode == 1


def main():
    try:
        conflicted = _git("diff", "--name-only", "--diff-filter=U").split()
        commit = _git("rev-parse", "-q", "--verify", "REBASE_HEAD").strip()
    except OSError as error:
        print("changelog_resolve: not stopped in a rebase (%s)" % error, file=sys.stderr)
        return 1
    tests = [each for each in conflicted if is_test_file(each)]
    others = [each for each in conflicted if each != PATH and each not in PAGES and each != THIRD and each not in tests]
    if not conflicted or others:
        print("changelog_resolve: conflicted are %s, not CHANGELOG.md, the generated pages (%s) and test files' rows alone"
            % (conflicted or "none", ", ".join(PAGES + [THIRD + "'s generated spans"])), file=sys.stderr)
        return 1
    # Test files' rows first, in memory: one that is more than rows added refuses the run, nothing written.
    rows = {}
    for path in tests:
        try:
            sides = [_git("show", ":%d:%s" % (stage, path)) for stage in (1, 2, 3)]
        except OSError:
            print("changelog_resolve: %s is new or gone on one side; nothing written" % path, file=sys.stderr)
            return 1
        merged, mains, takes, why = merge_rows(*sides)
        if why:
            print("changelog_resolve: %s: %s; nothing written, the conflict left as it was" % (path, why), file=sys.stderr)
            return 1
        rows[path] = (merged, mains, takes)
    third = THIRD in conflicted
    if third:
        why = third_party_why(commit)
        if why:
            print("changelog_resolve: %s in conflict and %s; nothing written" % (THIRD, why), file=sys.stderr)
            return 1
    text, added, taken = None, [], []
    if PATH in conflicted:
        try:
            before = _git("show", commit + "^:" + PATH)
        except OSError:
            before = ""  # The commit made the file.
        added, taken = added_and_taken(before, _git("show", commit + ":" + PATH))
        text = resolve(_git("show", "HEAD:" + PATH), added, taken)
        if text is None:
            print("changelog_resolve: HEAD's CHANGELOG.md has no %s" % UNRELEASED, file=sys.stderr)
            return 1
    pages = [each for each in conflicted if each in PAGES or each == THIRD]
    names = [name for name, each in GENERATORS.items()
        if any(page in pages for page in each["pages"]) or (third and name in SPANS)]
    touched = [path for name in names for path in GENERATORS[name]["writes"] if path not in pages]
    # Nothing staged until every generator has worked: on a failure each file
    # gets back the bytes it had (the pages their conflict markers, the index
    # still unmerged; what a generator wrote beside them its own).
    kept = {}
    for path in dict.fromkeys(pages + touched):
        if os.path.exists(path):
            with open(path, "rb") as handle:
                kept[path] = handle.read()
    for page in pages:
        _git("checkout", "--ours", "--", page)
    ours_outside = outside_spans(_git("show", "HEAD:" + THIRD)) if third else None
    for name in names:
        why = generate(name)
        if not why and third and name == names[-1]:
            # Main's credits must come through the generators untouched.
            with open(THIRD, encoding="utf-8", newline="") as handle:
                if outside_spans(handle.read()) != ours_outside:
                    why = "%s changed outside its spans by the generators" % THIRD
        if why:
            for path, data in kept.items():
                with open(path, "wb") as handle:
                    handle.write(data)
            print("changelog_resolve: %s; nothing written, the conflict left as it was" % why, file=sys.stderr)
            return 1
    staged = pages + [path for path in dict.fromkeys(touched) if _changed(path)]
    for path, (merged, _mains, _takes) in rows.items():
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(merged)
        staged.append(path)
    if text is not None:
        with open(PATH, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        staged.insert(0, PATH)
    _git("add", "--", *staged)
    if text is not None:
        print("changelog_resolve: %s's CHANGELOG.md, %d bullet(s) of %s added (%d line(s)), %d taken out"
            % ("HEAD", len(added), commit[:8], sum(bullet.count("\n") + 1 for bullet in added), len(set(taken) - set(added))))
    if pages:
        print("changelog_resolve: %s from main's side, made again over the merged tree (%s); staged: %s"
            % (", ".join(pages), ", ".join(names), ", ".join(staged)))
    for path, (_merged, mains, takes) in rows.items():
        print("changelog_resolve: %s rows merged: main's %s, then the take's %s (%s)"
            % (path, ", ".join(mains) or "none", ", ".join(takes) or "none", commit[:8]))
    return 0


if __name__ == "__main__":
    sys.exit(main())

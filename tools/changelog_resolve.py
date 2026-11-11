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

Run while `git rebase` is stopped with only CHANGELOG.md and those pages in
conflict (any of them):
  python -B tools/changelog_resolve.py      writes them, `git add`s them; exit 0
It does not continue the rebase. Exit 1 (nothing written, the conflict left as
it was) when the rebase is not stopped on a commit, another file is in conflict
(THIRD_PARTY.md included), the file has no ## Unreleased heading, or a
generator fails. Standard library only.
"""
import json
import os
import subprocess
import sys

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
}
PAGES = [page for each in GENERATORS.values() for page in each["pages"]]
## The test's own commands (JSON {generator: argv}), never set in a landing.
COMMANDS_ENV = "CHANGELOG_RESOLVE_COMMANDS"
GENERATOR_SECONDS = 300
## A Godot run that printed one of these failed, whatever its exit code.
GODOT_FAILED = ("SCRIPT ERROR", "Parse Error", "ERROR:")


def command(name):
    """[name]'s generator as argv: voice_inventory.py with this Python, or
    art_status.gd under Godot ($GODOT_PATH, else `godot`, as land.sh's
    scripts find it), headless, silent, its own log (decision 664)."""
    override = os.environ.get(COMMANDS_ENV)
    if override:
        return json.loads(override)[name]
    if name == "voice_inventory":
        return [sys.executable, "-B", "tools/voice_inventory.py"]
    os.makedirs(os.path.join("build", "logs"), exist_ok=True)
    return [os.environ.get("GODOT_PATH") or "godot", "--headless", "--audio-driver", "Dummy",
        "--log-file", "build/logs/changelog_resolve_art_status.log", "--path", ".", "--script", "tools/art_status.gd"]


def generate(name):
    """Runs [name]'s generator (stdin closed, GENERATOR_SECONDS at most):
    "" when it worked, else why not."""
    argv = command(name)
    try:
        done = subprocess.run(argv, capture_output=True, stdin=subprocess.DEVNULL, timeout=GENERATOR_SECONDS)
    except (OSError, subprocess.TimeoutExpired) as error:
        return "%s: %s" % (name, error)
    out = (done.stdout + done.stderr).decode("utf-8", "replace")
    failed = done.returncode != 0 or (name == "art_status" and any(each in out for each in GODOT_FAILED))
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
    others = [each for each in conflicted if each != PATH and each not in PAGES]
    if not conflicted or others:
        print("changelog_resolve: conflicted are %s, not CHANGELOG.md and the generated pages (%s) alone"
            % (conflicted or "none", ", ".join(PAGES)), file=sys.stderr)
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
    pages = [each for each in conflicted if each in PAGES]
    names = [name for name, each in GENERATORS.items() if any(page in pages for page in each["pages"])]
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
    for name in names:
        why = generate(name)
        if why:
            for path, data in kept.items():
                with open(path, "wb") as handle:
                    handle.write(data)
            print("changelog_resolve: %s; nothing written, the conflict left as it was" % why, file=sys.stderr)
            return 1
    staged = pages + [path for path in dict.fromkeys(touched) if _changed(path)]
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
    return 0


if __name__ == "__main__":
    sys.exit(main())

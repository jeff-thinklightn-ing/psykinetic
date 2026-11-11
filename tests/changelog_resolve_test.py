"""tools/changelog_resolve.py (decision 539 amended (3)) in a scratch git
repository, rebased as a landing is: a branch adding its bullet on a base
whose ## Unreleased still holds bullets main's cut then moved into a release
(v0.1.160's shape). Resolved, Unreleased is main's plus the branch's one, the
released bullets are where the cut put them, once each; a branch rewording
an Unreleased bullet leaves the new wording only; a conflict in another file
is left alone; CRLF stays CRLF.
  python tests/changelog_resolve_test.py      exit 0 = pass
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import changelog_resolve as resolver  # noqa: E402

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "changelog_resolve.py")
failed = 0


def check(ok, what):
    global failed
    print("  %s  %s" % ("PASS" if ok else "FAIL", what))
    if not ok:
        failed += 1


def git(repo, *args, ok=True):
    done = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True)
    if ok and done.returncode != 0:
        raise RuntimeError("git %s: %s" % (" ".join(args), done.stderr))
    return done


def write(repo, name, text):
    with open(os.path.join(repo, name), "w", encoding="utf-8", newline="") as handle:
        handle.write(text)


def read(repo, name="CHANGELOG.md"):
    with open(os.path.join(repo, name), encoding="utf-8", newline="") as handle:
        return handle.read()


HEAD = "# Changelog\n\nNewest first.\n\n"


def scratch():
    repo = tempfile.mkdtemp(prefix="changelog_resolve_")
    git(repo, "init", "-q", "-b", "main")
    git(repo, "config", "user.email", "test@example.com")
    git(repo, "config", "user.name", "test")
    git(repo, "config", "core.autocrlf", "false")
    return repo


def rebase_stops(repo):
    """Rebases branch onto main; True if it stopped on a conflict."""
    git(repo, "checkout", "-q", "branch")
    return git(repo, "rebase", "-q", "main", ok=False).returncode != 0


def cut_case(crlf=False):
    repo = scratch()
    nl = "\r\n" if crlf else "\n"
    def text(s):
        return s.replace("\n", nl)
    write(repo, "CHANGELOG.md", text(HEAD + "## Unreleased\n\n- Forge rebuilt.\n- Workers paid (528).\n\n## v0.1.159\n\n- Older.\n"))
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    git(repo, "branch", "branch")
    # main: the cut moves both into v0.1.160, then someone lands a bullet.
    write(repo, "CHANGELOG.md", text(HEAD + "## Unreleased\n\n- Hills lit (549).\n\n## v0.1.160\n\n- Forge rebuilt.\n- Workers paid (528).\n\n## v0.1.159\n\n- Older.\n"))
    git(repo, "commit", "-q", "-am", "cut and a landing")
    # branch: its own bullet first under Unreleased, on the old base.
    git(repo, "checkout", "-q", "branch")
    write(repo, "CHANGELOG.md", text(HEAD + "## Unreleased\n\n- Landing retries (530).\n- Forge rebuilt.\n- Workers paid (528).\n\n## v0.1.159\n\n- Older.\n"))
    git(repo, "commit", "-q", "-am", "mine")
    return repo


print("== a cut between the branch's base and main ==")
repo = cut_case()
try:
    check(rebase_stops(repo), "the rebase stops on CHANGELOG.md")
    done = subprocess.run([sys.executable, "-B", TOOL], cwd=repo, capture_output=True, text=True)
    check(done.returncode == 0, "resolved (%s)" % (done.stdout.strip() or done.stderr.strip()))
    text = read(repo)
    unreleased = text.split("## Unreleased")[1].split("## v")[0]
    check("- Landing retries (530)." in unreleased and "- Hills lit (549)." in unreleased, "Unreleased: the branch's bullet and main's")
    check("Forge" not in unreleased and "Workers" not in unreleased, "and none of those the cut released")
    check(text.count("- Forge rebuilt.") == 1 and text.count("- Workers paid (528).") == 1, "each released bullet once, in v0.1.160")
    check(text.index("- Landing retries (530).") < text.index("- Hills lit (549)."), "the branch's first, as a landing puts it")
    check(git(repo, "diff", "--name-only", "--diff-filter=U").stdout.strip() == "", "and staged: no conflict left")
    check(git(repo, "-c", "core.editor=true", "rebase", "--continue", ok=False).returncode == 0
        and git(repo, "log", "-1", "--format=%s").stdout.strip() == "mine", "the rebase goes on, the branch's commit on top")
finally:
    shutil.rmtree(repo, ignore_errors=True)

print("== CRLF ==")
repo = cut_case(crlf=True)
try:
    rebase_stops(repo)
    subprocess.run([sys.executable, "-B", TOOL], cwd=repo, capture_output=True, text=True)
    text = read(repo)
    check("\r\n" in text and "\n" not in text.replace("\r\n", ""), "line ends kept as CRLF")
    check(text.count("- Forge rebuilt.") == 1 and "- Landing retries (530)." in text, "and resolved as with LF")
finally:
    shutil.rmtree(repo, ignore_errors=True)

print("== a bullet reworded ==")
onto = HEAD + "## Unreleased\n\n- Rain halves (533).\n- Hills lit (549).\n\n## v0.1.160\n\n- Older.\n"
added, taken = resolver.added_and_taken("## Unreleased\n\n- Rain halves (533).\n", "## Unreleased\n\n- Rain halves, fog too (533).\n")
out = resolver.resolve(onto, added, taken)
check("- Rain halves, fog too (533)." in out and "- Rain halves (533).\n" not in out and "- Hills lit (549)." in out, "the new wording only, main's others kept")
out = resolver.resolve(onto.replace("## Unreleased\n\n- Rain halves (533).\n", "## Unreleased\n\n") + "- Rain halves (533).\n", added, taken)
check(out.count("- Rain halves (533).") == 1, "one the cut released is left in its release")
check(resolver.resolve("# Changelog\n\n## v0.1.1\n\n- Old.\n", ["- New."], []) is None, "no ## Unreleased: nothing written")

print("== a wrapped bullet (539 amended (4)) ==")
# Buildings' landing: a bullet wrapped over three lines came out as its
# first line alone.
wrapped = "- Plinths under houses (562): the ground\n  levelled round them, the porch\n  a step up.\n"
onto = HEAD + "## Unreleased\n\n- Hills lit (549).\n\n## v0.1.160\n\n- Older.\n"
added, taken = resolver.added_and_taken(HEAD + "## Unreleased\n\n## v0.1.160\n\n- Older.\n",
    HEAD + "## Unreleased\n\n" + wrapped + "\n## v0.1.160\n\n- Older.\n")
check(added == [wrapped.rstrip("\n")] and taken == [], "added as one bullet, its lines together: %r" % added)
out = resolver.resolve(onto, added, taken)
check("## Unreleased\n\n" + wrapped + "- Hills lit (549)." in out, "carried whole, first under Unreleased")
check(resolver.resolve(out, added, taken) == out, "not added again where it stands already")
added, taken = resolver.added_and_taken("## Unreleased\n\n" + wrapped, "## Unreleased\n\n" + wrapped.replace("a step up", "two steps up"))
out = resolver.resolve(HEAD + "## Unreleased\n\n" + wrapped + "- Hills lit (549).\n", added, taken)
check("two steps up" in out and "a step up" not in out and out.count("Plinths") == 1 and "the ground\n  levelled" in out,
    "a continuation reworded: the old bullet out, every line of it, the new in")

print("== a conflict beyond CHANGELOG.md ==")
repo = cut_case()
try:
    git(repo, "checkout", "-q", "main")
    write(repo, "other.txt", "main\n")
    git(repo, "add", "other.txt")
    git(repo, "commit", "-q", "-m", "other on main")
    git(repo, "checkout", "-q", "branch")
    write(repo, "other.txt", "branch\n")
    git(repo, "add", "other.txt")
    git(repo, "commit", "-q", "--amend", "--no-edit")
    rebase_stops(repo)
    before = read(repo)
    done = subprocess.run([sys.executable, "-B", TOOL], cwd=repo, capture_output=True, text=True)
    check(done.returncode == 1 and read(repo) == before, "left alone, exit 1 (%s)" % done.stderr.strip())
    git(repo, "rebase", "--abort", ok=False)
finally:
    shutil.rmtree(repo, ignore_errors=True)

print("== the generated pages (539 amended (5)) ==")
# Items' landing, 16:47 11-10: its rebase under the lock met the generated
# pages beside CHANGELOG.md. A fake generator per page writes what it read of
# the merged tree, so the test sees it ran over that tree.
VOICE = "docs/voice_inventory.md"
ART, ART_JSON, THIRD = "docs/art_status.md", "art/kit/status.json", "THIRD_PARTY.md"
FAKE_VOICE = """
import pathlib
pathlib.Path("docs/voice_inventory.md").write_text("voice from: " + pathlib.Path("lines.txt").read_text(), newline="")
"""
FAKE_ART = """
import pathlib
slots = pathlib.Path("slots.txt").read_text()
pathlib.Path("docs/art_status.md").write_text("art from: " + slots, newline="")
pathlib.Path("art/kit/status.json").write_text("json from: " + slots, newline="")
third = pathlib.Path("THIRD_PARTY.md")
third.write_text(third.read_text().replace("BLOCK old", "BLOCK " + slots.strip()), newline="")
"""
FAILING = """
import sys
print("SCRIPT ERROR: res://tools/art_status.gd")
sys.exit(1)
"""
PAGES_ALL = sorted(["CHANGELOG.md", VOICE, ART, ART_JSON])


def fakes(voice=FAKE_VOICE, art=FAKE_ART):
    return dict(os.environ, CHANGELOG_RESOLVE_COMMANDS=json.dumps({"voice_inventory": [sys.executable, "-c", voice],
        "art_status": [sys.executable, "-c", art]}))


def pages_case(third_party_conflict=False, branch_bullet=True):
    """A cut between base and main as cut_case, plus each side's own input
    (main a line in lines.txt, the branch a slot in slots.txt, merging
    cleanly) and each side's pages made from its own, so they conflict;
    THIRD_PARTY.md's slot block (art_status's) in conflict only when
    [third_party_conflict]; the branch's CHANGELOG bullet unless not
    [branch_bullet] (then the pages alone conflict)."""
    repo = scratch()
    write(repo, "CHANGELOG.md", HEAD + "## Unreleased\n\n- Forge rebuilt.\n\n## v0.1.159\n\n- Older.\n")
    os.makedirs(os.path.join(repo, "docs"))
    os.makedirs(os.path.join(repo, "art", "kit"))
    for name, text in (("lines.txt", "a\n"), ("slots.txt", "s1\n"), (VOICE, "voice from: a\n"), (ART, "art from: s1\n"),
            (ART_JSON, "json from: s1\n"), (THIRD, "# Third party\n\nBLOCK old\n\nOther.\n")):
        write(repo, name, text)
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    git(repo, "branch", "branch")
    write(repo, "CHANGELOG.md", HEAD + "## Unreleased\n\n- Hills lit (549).\n\n## v0.1.160\n\n- Forge rebuilt.\n\n## v0.1.159\n\n- Older.\n")
    write(repo, "lines.txt", "a\nb\n")
    write(repo, VOICE, "voice from: a\nb\n")
    write(repo, ART, "art from: s1\nmain\n")
    write(repo, ART_JSON, "json from: s1\nmain\n")
    if third_party_conflict:
        write(repo, THIRD, "# Third party\n\nBLOCK old\n\nOther, main.\n")
    git(repo, "commit", "-q", "-am", "cut and main's line")
    git(repo, "checkout", "-q", "branch")
    if branch_bullet:
        write(repo, "CHANGELOG.md", HEAD + "## Unreleased\n\n- A slot (563).\n- Forge rebuilt.\n\n## v0.1.159\n\n- Older.\n")
    write(repo, "slots.txt", "s1\ns2\n")
    write(repo, VOICE, "voice from: a\nbranch\n")
    write(repo, ART, "art from: s1\ns2\n")
    write(repo, ART_JSON, "json from: s1\ns2\n")
    if third_party_conflict:
        write(repo, THIRD, "# Third party\n\nBLOCK old\n\nOther, branch.\n")
    git(repo, "commit", "-q", "-am", "a slot")
    return repo


def conflicts(repo):
    return sorted(git(repo, "diff", "--name-only", "--diff-filter=U").stdout.split())


def resolve_in(repo, env):
    return subprocess.run([sys.executable, "-B", TOOL], cwd=repo, capture_output=True, text=True, env=env)


repo = pages_case()
try:
    stopped = rebase_stops(repo)
    check(stopped and conflicts(repo) == PAGES_ALL, "the rebase stops on CHANGELOG.md and the three pages (%s)" % conflicts(repo))
    done = resolve_in(repo, fakes())
    check(done.returncode == 0, "resolved (%s)" % (done.stdout.strip() or done.stderr.strip()))
    check(read(repo, VOICE) == "voice from: a\nb\n", "the voice page made again over the merged tree: %r" % read(repo, VOICE))
    check(read(repo, ART) == "art from: s1\ns2\n" and read(repo, ART_JSON) == "json from: s1\ns2\n",
        "the art pages made again from the merged slots: %r, %r" % (read(repo, ART), read(repo, ART_JSON)))
    check("BLOCK s1\ns2" in read(repo, THIRD) and THIRD in git(repo, "diff", "--cached", "--name-only").stdout.split(),
        "THIRD_PARTY.md's slot block, which art_status writes, staged with them")
    check("- A slot (563)." in read(repo) and read(repo).count("- Forge rebuilt.") == 1, "CHANGELOG.md resolved as before")
    unstaged = [line for line in git(repo, "status", "--porcelain", "--untracked-files=no").stdout.splitlines() if line[1] != " "]
    check(conflicts(repo) == [] and not unstaged, "no conflict left, nothing unstaged (%s)" % unstaged)
    check(git(repo, "-c", "core.editor=true", "rebase", "--continue", ok=False).returncode == 0
        and git(repo, "log", "-1", "--format=%s").stdout.strip() == "a slot", "the rebase goes on, the branch's commit on top")
finally:
    shutil.rmtree(repo, ignore_errors=True)

repo = pages_case(third_party_conflict=True)
try:
    rebase_stops(repo)
    before = {name: read(repo, name) for name in ("CHANGELOG.md", VOICE, ART, ART_JSON, THIRD)}
    done = resolve_in(repo, fakes())
    check(done.returncode == 1 and THIRD in done.stderr, "THIRD_PARTY.md in conflict too: exit 1 (%s)" % done.stderr.strip())
    check(all(read(repo, name) == text for name, text in before.items()) and THIRD in conflicts(repo) and VOICE in conflicts(repo),
        "nothing written, every conflict left")
    git(repo, "rebase", "--abort", ok=False)
finally:
    shutil.rmtree(repo, ignore_errors=True)

repo = pages_case()
try:
    rebase_stops(repo)
    before = {name: read(repo, name) for name in ("CHANGELOG.md", VOICE, ART, ART_JSON, THIRD)}
    done = resolve_in(repo, fakes(art=FAILING))
    check(done.returncode == 1 and "art_status" in done.stderr, "a generator failing: exit 1 (%s)" % done.stderr.strip()[:160])
    after = {name: read(repo, name) for name in before}
    check(after == before, "the files as they were, conflict markers and all (%s)" % [name for name in before if after[name] != before[name]])
    check(conflicts(repo) == PAGES_ALL, "and still in conflict (%s)" % conflicts(repo))
    git(repo, "rebase", "--abort", ok=False)
finally:
    shutil.rmtree(repo, ignore_errors=True)

repo = pages_case(branch_bullet=False)
try:
    rebase_stops(repo)
    pages_only = conflicts(repo)
    done = resolve_in(repo, fakes())
    check(pages_only == sorted([VOICE, ART, ART_JSON]) and done.returncode == 0 and conflicts(repo) == []
        and read(repo, VOICE) == "voice from: a\nb\n",
        "the pages in conflict without CHANGELOG.md (%s): made again, exit 0 (%s)" % (pages_only, (done.stdout + done.stderr).strip()[:160]))
    git(repo, "rebase", "--abort", ok=False)
finally:
    shutil.rmtree(repo, ignore_errors=True)

print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

"""tools/changelog_resolve.py (decision 539 amended (3)) in a scratch git
repository, rebased as a landing is: a branch adding its bullet on a base
whose ## Unreleased still holds bullets main's cut then moved into a release
(v0.1.160's shape). Resolved, Unreleased is main's plus the branch's one, the
released bullets are where the cut put them, once each; a branch rewording
an Unreleased bullet leaves the new wording only; a conflict in another file
is left alone; CRLF stays CRLF.
  python tests/changelog_resolve_test.py      exit 0 = pass
"""
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

print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

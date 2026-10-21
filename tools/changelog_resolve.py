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

Run while `git rebase` is stopped with CHANGELOG.md the only conflicted file:
  python -B tools/changelog_resolve.py      writes it, `git add`s it; exit 0
It does not continue the rebase. Exit 1 (nothing written) when the rebase is
not stopped on a commit, another file is in conflict, or the file has no
## Unreleased heading. Standard library only.
"""
import subprocess
import sys

PATH = "CHANGELOG.md"
UNRELEASED = "## Unreleased"


def _git(*args):
    done = subprocess.run(["git"] + list(args), capture_output=True)
    if done.returncode != 0:
        raise OSError(done.stderr.decode("utf-8", "replace").strip())
    return done.stdout.decode("utf-8")


def added_and_taken(diff):
    """The bullets a unified diff of CHANGELOG.md adds and takes out."""
    added, taken = [], []
    for line in diff.replace("\r\n", "\n").split("\n"):
        if line.startswith("+- "):
            added.append(line[1:])
        elif line.startswith("-- "):
            taken.append(line[1:])
    return added, taken


def resolve(onto, added, taken):
    """[param onto]'s text with [param added] put first under ## Unreleased
    (those it does not carry anywhere) and [param taken] dropped from it;
    None if it has no ## Unreleased heading. Line ends as [param onto] has
    them."""
    crlf = "\r\n" in onto
    lines = onto.replace("\r\n", "\n").split("\n")
    heading = next((i for i, line in enumerate(lines) if line.strip() == UNRELEASED), None)
    if heading is None:
        return None
    carried = {line for line in lines if line.startswith("- ")}
    gone = set(taken) - set(added)
    lines = [line for i, line in enumerate(lines) if not (i > heading and line in gone and _unreleased(lines, heading, i))]
    new = [bullet for bullet in dict.fromkeys(added) if bullet not in carried]
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


def main():
    try:
        conflicted = _git("diff", "--name-only", "--diff-filter=U").split()
        commit = _git("rev-parse", "-q", "--verify", "REBASE_HEAD").strip()
    except OSError as error:
        print("changelog_resolve: not stopped in a rebase (%s)" % error, file=sys.stderr)
        return 1
    if conflicted != [PATH]:
        print("changelog_resolve: conflicted are %s, not CHANGELOG.md alone" % (conflicted or "none"), file=sys.stderr)
        return 1
    added, taken = added_and_taken(_git("diff", commit + "^", commit, "--", PATH))
    text = resolve(_git("show", "HEAD:" + PATH), added, taken)
    if text is None:
        print("changelog_resolve: HEAD's CHANGELOG.md has no %s" % UNRELEASED, file=sys.stderr)
        return 1
    with open(PATH, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    _git("add", PATH)
    print("changelog_resolve: %s's CHANGELOG.md, %d bullet(s) of %s added, %d taken out"
        % ("HEAD", len(added), commit[:8], len(set(taken) - set(added))))
    return 0


if __name__ == "__main__":
    sys.exit(main())

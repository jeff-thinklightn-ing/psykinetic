"""CHANGELOG.md checked before a landing's tests (decision 539): a released
section is as its tag has it, and no bullet stands both under ## Unreleased
and in a released section. On 2026-10-19 economy's 522 bullet went into the
v0.1.157 section, maps' 525 amendment into v0.1.158's, and terrain's forge and
528 bullets stood under Unreleased beside their released copies: a rebase
keeps a bullet beside the heading it was next to, and a cut moves the heading.

  * The newest "## vX.Y.Z" section must read exactly (blank lines too) as
    the same section in tag vX.Y.Z's CHANGELOG.md. At a release cut the newest
    heading has no tag yet (the suite runs before release_client tags it):
    then the next section down is checked against its own tag.
  * No bullet line under ## Unreleased may also stand in a released section.
  * One that begins as a released bullet does (its first clause, _clause;
    539 amended (2)) is warned of: probably already released, check.

Tags are fetched first (git fetch -q --tags); a tag that cannot be had is a
warning, not a failure.
  python tools/changelog_check.py      exit 0 = clean, 1 = a problem (named)
Standard library only.
"""
import os
import subprocess
import sys

UNRELEASED = "## Unreleased"


def sections(text):
    """[(heading, the section's text: its heading line to the next "## ")]."""
    out = []
    lines = text.splitlines(keepends=True)
    start = None
    for i, line in enumerate(lines):
        if line.startswith("## "):
            if start is not None:
                out.append((lines[start].rstrip("\r\n"), "".join(lines[start:i])))
            start = i
    if start is not None:
        out.append((lines[start].rstrip("\r\n"), "".join(lines[start:])))
    return out


def _released(heading):
    return heading.startswith("## v")


def _bullets(section_text):
    return [line.rstrip("\r\n") for line in section_text.splitlines() if line.startswith("- ")]


## A first clause shorter than this ("Fixed", "Landing tests") says too
## little to match on: the bullet's first CLAUSE_CHARS characters are taken.
CLAUSE_MIN_CHARS = 20
CLAUSE_CHARS = 60


def _clause(bullet):
    """A bullet's first clause, to the first ":", ";" or "(", case and
    whitespace folded; its first CLAUSE_CHARS characters when that is under
    CLAUSE_MIN_CHARS (539 amended (2): 533's "Clearer skies in the town lands"
    came back under Unreleased as written, after v0.1.159 shipped it edited)."""
    text = " ".join(bullet[2:].split()).lower()
    ends = [at for at in (text.find(":"), text.find(";"), text.find("(")) if at >= 0]
    clause = text[:min(ends)].strip() if ends else text
    return clause if len(clause) >= CLAUSE_MIN_CHARS else text[:CLAUSE_CHARS]


def check(text, tag_changelog):
    """(problems, warnings) for CHANGELOG [param text]. [param tag_changelog]
    (version) gives that tag's CHANGELOG.md text, or None if there is no such
    tag, or raises OSError if tags cannot be had."""
    problems, warnings = [], []
    found = sections(_lf(text))
    released = [(heading, body) for heading, body in found if _released(heading)]
    unreleased = [body for heading, body in found if heading.strip() == UNRELEASED]
    # A bullet both unreleased and released: the same line, or (539 amended
    # (2)) the same first clause, for a cut may have shipped an edited copy.
    # A clause that begins two or more released bullets is a set phrase ("This
    # release changes what the server and client send each other"), not one.
    carried = {}
    begun = {}
    uses = {}
    for heading, body in released:
        for bullet in _bullets(body):
            carried.setdefault(bullet, heading[3:].strip())
            begun.setdefault(_clause(bullet), (heading[3:].strip(), bullet))
            uses[_clause(bullet)] = uses.get(_clause(bullet), 0) + 1
    begun = {clause: was for clause, was in begun.items() if uses[clause] == 1}
    for body in unreleased:
        for bullet in _bullets(body):
            if bullet in carried:
                problems.append("under ## Unreleased: drop it: %s already carries it: %s" % (carried[bullet], _short(bullet)))
            elif _clause(bullet) in begun:
                # A warning: a set phrase used a second time reads the same
                # (the protocol notes of v0.1.140 and v0.1.150 would have hit).
                version, theirs = begun[_clause(bullet)]
                warnings.append("under ## Unreleased, it begins as %s's %r: probably already released, check: drop it, or reword it if it is new: %s"
                    % (version, _short(theirs), _short(bullet)))
    # The newest released section, as its tag has it (the one below at a cut).
    for heading, body in released[:2]:
        version = heading[3:].split()[0]
        try:
            tagged = tag_changelog(version)
        except OSError as error:
            warnings.append("tag %s could not be read (%s): %s not checked" % (version, error, heading))
            return problems, warnings
        if tagged is None:
            if heading == released[0][0]:
                continue  # A cut under way: not tagged yet.
            warnings.append("no tag %s: %s not checked" % (version, heading))
            return problems, warnings
        theirs = dict(sections(_lf(tagged))).get(heading)
        if theirs is None:
            warnings.append("tag %s's CHANGELOG has no %s: not checked" % (version, heading))
        elif theirs != body:
            problems.extend(_differences(heading, body, theirs))
        return problems, warnings
    return problems, warnings


def _differences(heading, ours, theirs):
    out = []
    tagged = theirs.splitlines()
    for bullet in _bullets(ours):
        if bullet not in tagged:
            out.append("in %s but not in its tag: move it under ## Unreleased: %s" % (heading, _short(bullet)))
    mine = ours.splitlines()
    for bullet in _bullets(theirs):
        if bullet not in mine:
            out.append("in tag %s's %s but missing or changed here: put it back as released: %s" % (heading[3:].strip(), heading, _short(bullet)))
    if not out:
        # The same bullets: the lines between differ (a blank line, a heading's spacing).
        for number, (a, b) in enumerate(zip(mine + [None] * len(tagged), tagged + [None] * len(mine))):
            if a != b:
                out.append("%s differs from its tag at its line %d (here %r, tagged %r): make it as tagged" % (heading, number + 1, a, b))
                break
    return out


def _lf(text):
    """Line ends as the repository keeps them (a checkout may have CRLF)."""
    return text.replace("\r\n", "\n")


def _short(bullet):
    return bullet if len(bullet) <= 120 else bullet[:117] + "..."


def _git_tag_changelog(root):
    def read(version):
        known = subprocess.run(["git", "-C", root, "rev-parse", "-q", "--verify", "refs/tags/" + version],
            capture_output=True, text=True)
        if known.returncode != 0:
            return None
        shown = subprocess.run(["git", "-C", root, "show", version + ":CHANGELOG.md"], capture_output=True)
        if shown.returncode != 0:
            raise OSError(shown.stderr.decode("utf-8", "replace").strip())
        return shown.stdout.decode("utf-8")
    return read


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    fetched = subprocess.run(["git", "-C", root, "fetch", "-q", "--tags"], capture_output=True, text=True, timeout=120)
    if fetched.returncode != 0:
        print("changelog: WARNING tags not fetched (%s); checking against the tags here" % fetched.stderr.strip())
    with open(os.path.join(root, "CHANGELOG.md"), encoding="utf-8", newline="") as handle:
        text = handle.read()
    problems, warnings = check(text, _git_tag_changelog(root))
    for warning in warnings:
        print("changelog: WARNING " + warning)
    for problem in problems:
        print("changelog: FAIL " + problem)
    if problems:
        print("CHANGELOG: FAIL (decision 539)")
        return 1
    print("CHANGELOG: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""tools/changelog_check.py (decision 539), on CHANGELOGs shaped as
2026-10-19's slips: a bullet put in a released section (economy's 522 in
v0.1.157's, maps' 525 amended in v0.1.158's), bullets under Unreleased beside
their released copies (terrain's forge and 528), a stray blank line, a cut
whose heading is not tagged yet, and a tag that cannot be read.
  python tests/changelog_check_test.py      exit 0 = pass
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import changelog_check as changelog  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    print("  %s  %s" % ("PASS" if ok else "FAIL", what))
    if not ok:
        failed += 1


HEAD = "# Changelog\n\nNewest first.\n\n"
V158 = "## v0.1.158\n\n- Hills are drawn (525).\n- The smith's forge is rebuilt.\n\n"
V157 = "## v0.1.157\n\n- Caravans sell at the castle (504).\n\n"
TAGS = {"v0.1.158": HEAD + "## Unreleased\n\n" + V158 + V157, "v0.1.157": HEAD + "## Unreleased\n\n" + V157}


def tags(version):
    return TAGS.get(version)


def run(text, reader=tags):
    return changelog.check(text, reader)


print("== clean ==")
problems, warnings = run(HEAD + "## Unreleased\n\n- A new thing (539).\n\n" + V158 + V157)
check(problems == [] and warnings == [], "a bullet under Unreleased, released sections as tagged: %s %s" % (problems, warnings))
problems, _ = run((HEAD + "## Unreleased\n\n" + V158 + V157).replace("\n", "\r\n"))
check(problems == [], "a CRLF checkout reads as the repository's LF")

print("== a bullet in a released section ==")
slipped = HEAD + "## Unreleased\n\n" + V158.replace("- Hills", "- Workers make a living (522).\n- Hills") + V157
problems, _ = run(slipped)
check(len(problems) == 1 and "move it under ## Unreleased" in problems[0] and "(522)" in problems[0], "economy's 522 in the newest section: %s" % problems)
amended = HEAD + "## Unreleased\n\n" + V158.replace("Hills are drawn (525).", "Hills are drawn (525), the camera rises over a ridge.") + V157
problems, _ = run(amended)
check(any("move it under ## Unreleased" in each and "ridge" in each for each in problems)
    and any("put it back as released" in each and "Hills are drawn (525)." in each for each in problems), "maps' 525 amended in place: %s" % problems)
problems, _ = run(HEAD + "## Unreleased\n\n" + V158.replace("(525).\n", "(525).\n\n") + V157)
check(len(problems) == 1 and "line 4" in problems[0] and "make it as tagged" in problems[0], "a stray blank line: %s" % problems)

print("== a bullet both unreleased and released ==")
twice = HEAD + "## Unreleased\n\n- The smith's forge is rebuilt.\n- Caravans sell at the castle (504).\n\n" + V158 + V157
problems, _ = run(twice)
check(len(problems) == 2 and all("drop it:" in each for each in problems)
    and "v0.1.158 already carries it" in problems[0] and "v0.1.157 already carries it" in problems[1], "terrain's forge and an older one: %s" % problems)

print("== at a cut ==")
cut = HEAD + "## Unreleased\n\n## v0.1.159\n\n- A new thing (539).\n\n" + V158 + V157
problems, warnings = run(cut)
check(problems == [] and warnings == [], "the newest not tagged yet: the one below checked, clean")
problems, _ = run(cut.replace("- Hills", "- Slipped in (530).\n- Hills"))
check(len(problems) == 1 and "v0.1.158" in problems[0] and "(530)" in problems[0], "...and a slip there is found: %s" % problems)
problems, warnings = run(cut, lambda version: None)
check(problems == [] and len(warnings) == 1 and "no tag v0.1.158" in warnings[0], "no tags at all: a warning, not a failure")


def unreadable(version):
    raise OSError("fatal: not a git repository")


problems, warnings = run(slipped, unreadable)
check(problems == [] and len(warnings) == 1 and "could not be read" in warnings[0], "tags that cannot be had: a warning")

print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

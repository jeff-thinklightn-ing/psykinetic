"""tools/voice_inventory.py --land (748 amended (8)) in a scratch git
repository holding a copy of the tool and one script with a player's line, as
tests/land.sh runs it before the gate. A stale page under this tree's land
lock, clean and ahead of origin/main, is regenerated as a commit of its own
that touches only the page (exit 0, its sha named), also from a side
worktree (items-cast under items' lock), psykinetic-release under release's,
and a gated run given the owner's name (HEAVY_JOB_HELD); with no lock, another
tree's lock (ui-design under ui's: a tree's own folder), a dirty tree or
nothing ahead it is only a warning (exit 3,
nothing committed); a page up to date is exit 0 with nothing committed; a
generator that fails is exit 2, nothing committed, the page untouched.
  python tests/voice_inventory_test.py      exit 0 = pass
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "voice_inventory.py")
PAGE = "docs/voice_inventory.md"
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


def write(repo, name, text, binary=False):
    path = os.path.join(repo, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb" if binary else "w", **({} if binary else {"encoding": "utf-8", "newline": "\n"})) as handle:
        handle.write(text)


def read(repo, name=PAGE):
    with open(os.path.join(repo, name), encoding="utf-8") as handle:
        return handle.read()


def head(repo):
    return git(repo, "rev-parse", "HEAD").stdout.strip()


def run(repo, *args, held=""):
    env = dict(os.environ)
    env.pop("PSYKINETIC_LAND_LOCK", None)
    env.pop("HEAVY_JOB_HELD", None)
    if held:
        env["HEAVY_JOB_HELD"] = held
    return subprocess.run([sys.executable, "-B", os.path.join(repo, "tools", "voice_inventory.py")] + list(args),
                          capture_output=True, text=True, cwd=repo, env=env)


def scratch(stale=True):
    """A repo with origin/main at its base (the page up to date), then one
    commit ahead adding a player's line, its page stale unless [param stale]
    is False (then the commit regenerates the page too). Also a lock folder."""
    root = tempfile.mkdtemp(prefix="voice_inventory_")
    repo = os.path.join(root, "repo")
    os.makedirs(os.path.join(repo, "tools"))
    shutil.copy(TOOL, os.path.join(repo, "tools", "voice_inventory.py"))
    git(repo, "init", "-q", "-b", "voice")
    git(repo, "config", "user.email", "test@example.com")
    git(repo, "config", "user.name", "test")
    git(repo, "config", "core.autocrlf", "false")
    write(repo, "main.gd", 'const LINE := "The hall\'s door shuts behind you."\n')
    write(repo, PAGE, "")
    write(repo, "docs/lore/crypt.md", "# The crypt\n")
    # The trees' own folders (holds_lock: ui-design is no side worktree of ui).
    write(repo, "tests/port_offsets.txt", "# offsets\nvoice 4200\nitems 1800\nui 3200\nui-design 4800\n"
                                          "psykinetic-release 3400\n")
    os.makedirs(os.path.join(repo, "levels", "lore"), exist_ok=True)
    git(repo, "add", "-A")
    done = run(repo)
    if done.returncode != 0:
        raise RuntimeError("generator: %s" % (done.stdout + done.stderr))
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "base")
    git(repo, "update-ref", "refs/remotes/origin/main", head(repo))
    write(repo, "main.gd", 'const LINE := "The hall\'s door shuts behind you."\n'
                           'const MORE := "You feel a cool draught coming from one of the niches."\n')
    if not stale:
        run(repo)
    git(repo, "commit", "-q", "-am", "a new line")
    lock = os.path.join(root, "land.lock")
    return root, repo, lock


def take(lock, tree):
    os.makedirs(lock, exist_ok=True)
    with open(os.path.join(lock, "owner"), "w", encoding="utf-8") as handle:
        handle.write(tree + "\n")


def folds(tree="voice", owner="voice", held=""):
    root, repo, lock = scratch()
    take(lock, owner)
    before = head(repo)
    done = run(repo, "--land", tree, "--lock", lock, held=held)
    check(done.returncode == 0, "%s under %s's lock%s, clean, ahead, stale: exit 0 (%d: %s)"
          % (tree, owner, " (gate run %s)" % held if held else "", done.returncode, done.stdout.strip()))
    after = head(repo)
    check(after != before and git(repo, "rev-parse", "HEAD~1").stdout.strip() == before,
          "one new commit on top of the landing's own")
    files = git(repo, "show", "--name-only", "--format=", "HEAD").stdout.split()
    check(files == [PAGE], "the new commit touches only the page (%s)" % files)
    check("cool draught" in read(repo), "the page now holds the new line")
    check(run(repo, "--check").returncode == 0, "--check passes after it")
    check(git(repo, "rev-parse", "--short", "HEAD").stdout.strip() in done.stdout, "the line names the new sha")
    check(not git(repo, "status", "--porcelain", "--untracked-files=no").stdout.strip(), "the tree is clean after it")
    shutil.rmtree(root, ignore_errors=True)


def warns(what, setup, tree="voice"):
    root, repo, lock = scratch()
    setup(repo, lock)
    before, page = head(repo), read(repo)
    done = run(repo, "--land", tree, "--lock", lock)
    check(done.returncode == 3, "%s: exit 3, a warning (%d)" % (what, done.returncode))
    check("VOICE INVENTORY STALE" in done.stdout, "%s: says VOICE INVENTORY STALE" % what)
    check(head(repo) == before and read(repo) == page, "%s: nothing committed, the page untouched" % what)
    shutil.rmtree(root, ignore_errors=True)


def dirty(repo, lock):
    take(lock, "voice")
    write(repo, "main.gd", read(repo, "main.gd") + "# an edit not committed\n")


def behind(repo, lock):
    take(lock, "voice")
    git(repo, "update-ref", "refs/remotes/origin/main", head(repo))


def fresh():
    root, repo, lock = scratch(stale=False)
    take(lock, "voice")
    before = head(repo)
    done = run(repo, "--land", "voice", "--lock", lock)
    check(done.returncode == 0 and head(repo) == before, "an up-to-date page: exit 0, nothing committed (%d)"
          % done.returncode)
    shutil.rmtree(root, ignore_errors=True)


def broken():
    root, repo, lock = scratch()
    take(lock, "voice")
    write(repo, "main.gd", b'const LINE := "Bad bytes \xff\xfe here, read as text."\n', binary=True)
    git(repo, "commit", "-q", "-am", "a script the generator can't read")
    before, page = head(repo), read(repo)
    done = run(repo, "--land", "voice", "--lock", lock)
    check(done.returncode == 2, "a generator that fails: exit 2, the landing stops (%d)" % done.returncode)
    check("voice_inventory.py --check" in done.stdout, "it names the command to see it")
    check(head(repo) == before and read(repo) == page, "a generator that fails: nothing committed, the page untouched")
    shutil.rmtree(root, ignore_errors=True)


def chests():
    """748 amended (10): chest titles listed by PackPanel.title_name's rule (chest_test's cases), read
    ones marked R, an unread one a warning in --check and --land that never fails either."""
    root, repo, lock = scratch(stale=False)
    level = {"entities": [
        {"at": [1, 1], "name": "Offering stone", "props": {"role": "offering", "slots": ["", "", "", ""]}},
        {"at": [2, 1], "name": "Runner’s pack", "props": {"role": "commission"}},
        {"at": [3, 1], "name": "Miser's hoard", "props": {"cache": "gold"}},
        {"at": [4, 1], "name": "KitChest1", "props": {"slots": ["", ""]}},
        {"at": [5, 1], "name": "Chest1", "props": {"slots": ["", ""]}},
        {"at": [6, 1], "name": " altar", "props": {"temple": True}},
        {"at": [7, 1], "name": "Robbers_chest", "props": {"cache": "loot"}},
        {"at": [8, 1], "name": "Old Tam", "props": {"trade": "smith"}},
    ]}
    write(repo, "levels/crypt/level.json", json.dumps(level, ensure_ascii=False))
    git(repo, "add", "-A")
    check(run(repo).returncode == 0, "the generator runs over a level with chests")
    page = read(repo)
    rows = [line for line in page.splitlines() if line.endswith("| `levels/crypt/level.json` |")]
    titles = [line.split(" | ")[1] for line in rows]
    check(titles == ["Offering stone", "Runner’s pack", "Miser's hoard"],
          "names that read as names are titles; working names, ids, a lowercase tag and a non-chest are not (%s)" % titles)
    check("## Chest titles (3)" in page, "the section counts them")
    check(rows[0].startswith("| R |") and rows[2].startswith("|  |"), "a read title is marked R, an unread one not")
    git(repo, "commit", "-q", "-am", "chests")
    done = run(repo, "--check")
    check(done.returncode == 0, "an unread title never fails --check (%d)" % done.returncode)
    # A curly apostrophe passes the rule but is not the read straight one: its own title, unread.
    check("2 chest title(s) voice hasn't read: Runner’s pack (crypt), Miser's hoard (crypt)" in done.stdout,
          "--check names the unread ones (%s)" % done.stdout.strip())
    landed = run(repo, "--land", "voice", "--lock", lock)
    check(landed.returncode == 0 and "Miser's hoard (crypt)" in landed.stdout, "--land warns of it too, exit 0 (%d)" % landed.returncode)
    shutil.rmtree(root, ignore_errors=True)


folds()
folds("items-cast", "items")
folds("psykinetic-release", "release")
folds("wt608", "dungeon", held="dungeon-suite-4242.json")
warns("another tree's gate run", lambda repo, lock: take(lock, "voice"), tree="wt608")
warns("no lock", lambda repo, lock: None)
warns("ui-design under ui's lock (a tree's own folder, no side of ui)", lambda repo, lock: take(lock, "ui"), tree="ui-design")
warns("another tree's lock", lambda repo, lock: take(lock, "ui"))
warns("a dirty tree", dirty)
warns("nothing ahead of origin/main", behind)
fresh()
broken()
chests()
print("voice_inventory_test: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
sys.exit(0 if failed == 0 else 1)

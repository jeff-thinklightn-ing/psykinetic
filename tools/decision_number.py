"""Decision numbers and amendment labels by script (decision 834), not by hand
from release. Every tree takes the next number before it commits:

  decision_number.py new <tree> "<what>"                    prints the next number: 845
  decision_number.py amend <tree> <decision> "<what>"       prints the next label: 688 amended (9)
  decision_number.py drop <tree> <number-or-label> "<why>"  a hand-out that will never land (left a gap)
  decision_number.py status [--all]                         hand-outs not yet on origin/main (--all: the log)
  decision_number.py seed release <label> <tree> "<what>"   release's hand-over, before open
  decision_number.py open release                           release: hand-over done, numbers open

Exit 0 with the number or label alone on stdout; any failure exits non-zero
with nothing on stdout, so `n=$(sh tools/decision_number.sh new perf "x")`
is safe in a script.

State lives outside every checkout, beside the land lock: C:/dev/decision_numbers
(DECISION_NUMBERS_DIR to put it elsewhere, as the test does). log.tsv is
append-only, a line an event: time, tree, event (seed, open, new, amend,
drop), number or label, what. A lock folder (atomic mkdir) is held only for
the read and the append, milliseconds; it is taken over only when it is past
LOCK_STALE_SECONDS and its holder's process is gone.

The next number is one over the highest of: any heading "## N" in
docs/decisions.md as origin/main has it (`git show`, before the lock, no
fetch: every checkout shares one origin/main, and the log covers anything
newer), the floor release's open wrote, and every number in the log. The next
amendment of D is one over the highest k of "D amended (k)" anywhere in that
file (headings and paragraphs; a bare "D amended" is (1)), of an "Amended"
line inside D's entry (each one more than the last unless it names its k:
"Amended (3)", "Amended a fourth time"), of "D amended a fifth time" and "D's
eighth amendment", and in the log. A
decision on neither is refused, so a typo can't start a series. So nothing on
main, and nothing handed out and not yet landed, is handed out again.

A dropped number stays a gap, never returned: a returned one could reach two
trees (the one that dropped it and took its work back up, and the next).
drop is the holder's or release's, and only stops status listing it.
Follow-ups (the coordinator's ruling): one landing on its own takes the next
"amended (k)"; a paragraph added to work not yet landed stays under its
hand-out; a tree landing its side of a named decision uses that number.
PROTOCOL_REVISION numbers and release versions stay with release.
"""
import ctypes
import datetime
import os
import re
import subprocess
import sys
import time

STATE_DIR = os.environ.get("DECISION_NUMBERS_DIR") or "C:/dev/decision_numbers"
## Read instead of origin/main's docs/decisions.md (the test's own file).
DECISIONS_ENV = "DECISION_NUMBERS_DECISIONS"
RELEASE = "release"
## A lock older than this, its holder's process gone, is taken over.
LOCK_STALE_SECONDS = 30.0
## How long an ask waits for the lock before it gives up (exit 4).
LOCK_WAIT_SECONDS = 20.0
## "D amended (k)" with k over this is no label (a year, a sha): unplaced.
MOST_AMENDMENTS = 200
EVENTS = ("seed", "open", "new", "amend", "drop")

HEADING = re.compile(r"^## (\d+)", re.M)
LABEL = re.compile(r"\b(\d+) amended(?: \((\d+)\))?")
AMEND_LABEL = re.compile(r"^(\d+) amended \((\d+)\)$")
## An amendment inside its decision's entry (the first parser missed these: 49
## decisions undercounted on 11-10, 539 by four): a line starting "Amended"
## under "## N", as "Amended (k)", "Amended a fourth time", or bare, "again"
## or a date (the next).
INNER = re.compile(r"^Amended\b(?: \((\d+)\)| (?:a|an) (\w+) time)?")
ORDINALS = {word: n for n, word in enumerate(("first second third fourth fifth sixth seventh eighth ninth tenth eleventh "
    "twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth twentieth").split(), 1)}
## "394 amended a fifth time", "394's eighth amendment": anywhere.
SPELLED = re.compile(r"\b(\d+)(?: amended (?:a|an) (\w+) time|'s (\w+) amendment)")


def _path(*parts):
    return os.path.join(STATE_DIR, *parts)


# --- What main holds (pure: the test gives it text) -------------------------

def parse(text):
    """[text] (docs/decisions.md) as (highest heading number, {decision: highest
    k}, unplaced): every "## N" heading, every "D amended (k)" (a bare "D
    amended", or one whose brackets hold no small number, a date or a sha, is
    (1)), and the labels it can't place ("D amended (k)" with k past
    MOST_AMENDMENTS)."""
    highest = max([int(n) for n in HEADING.findall(text)] or [0])
    amended, unplaced = {}, []
    for decision, k in LABEL.findall(text):
        decision = int(decision)
        if k and int(k) > MOST_AMENDMENTS:
            unplaced.append("%d amended (%s)" % (decision, k))
            continue
        amended[decision] = max(amended.get(decision, 0), int(k) if k else 1)
    for decision, first, second in SPELLED.findall(text):
        k = ORDINALS.get(first or second)
        if k:
            amended[int(decision)] = max(amended.get(int(decision), 0), k)
    # Inside an entry: each "Amended" line one more than the entry's last,
    # unless it names its own k. Rounding up on purpose: a skipped label is a
    # gap, a repeated one two meanings.
    entry, count = None, 0
    for line in text.split("\n"):
        heading = HEADING.match(line)
        if heading:
            entry, count = int(heading.group(1)), 0
            continue
        inner = INNER.match(line) if entry is not None else None
        if inner:
            named = ORDINALS.get(inner.group(2))
            if inner.group(1) and int(inner.group(1)) <= MOST_AMENDMENTS:
                named = int(inner.group(1))
            count = count + 1 if named is None else max(count, named)
            amended[entry] = max(amended.get(entry, 0), count)
    known = set(int(n) for n in HEADING.findall(text)) | set(amended)
    return highest, amended, known, unplaced


def main_text():
    """docs/decisions.md as origin/main has it (or DECISIONS_ENV's file)."""
    path = os.environ.get(DECISIONS_ENV)
    if path:
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    out = subprocess.run(["git", "show", "origin/main:docs/decisions.md"], capture_output=True)
    if out.returncode != 0:
        raise SystemExit(_fail("can't read origin/main:docs/decisions.md here: %s" % out.stderr.decode(errors="replace").strip(), 2))
    return out.stdout.decode("utf-8", errors="replace")


# --- The log -----------------------------------------------------------------

def read_log():
    """The log's events: dicts of time, tree, event, label, what."""
    out = []
    try:
        with open(_path("log.tsv"), encoding="utf-8") as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 5 and parts[2] in EVENTS:
                    out.append(dict(zip(("time", "tree", "event", "label", "what"), parts)))
    except OSError:
        pass
    return out


def clean(text):
    """[text] as one log field: no tabs or newlines."""
    return re.sub(r"[\t\r\n]+", " ", text).strip()


def append(tree, event, label, what):
    line = "\t".join((datetime.datetime.now().isoformat(timespec="seconds"), clean(tree), event, clean(label), clean(what)))
    with open(_path("log.tsv"), "a", encoding="utf-8") as handle:
        handle.write(line + "\n")


def next_number(highest_on_main, events):
    """One over the highest of main's headings, open's floor and every
    label's leading number in the log (an amendment's is a decision already
    counted, so it changes nothing)."""
    best = highest_on_main
    for each in events:
        found = re.match(r"(\d+)", each["label"])
        if found:
            best = max(best, int(found.group(1)))
    return best + 1


def next_amendment(decision, amended, known, events):
    """[decision]'s next label, or None when it is neither on main nor in the log."""
    best = amended.get(decision, 0)
    in_log = False
    for each in events:
        # Release's seeds as written ("489 amended (4) plus the chimney
        # paragraph"): each "D amended (k)" in a label counts toward k.
        for named, k in re.findall(r"\b(\d+) amended \((\d+)\)", each["label"]):
            if int(named) == decision:
                best = max(best, int(k))
                in_log = True
        # A bare "D amended" of release's may be the first or the next after
        # main's: it holds the one after main's highest (over-counting only
        # makes a gap), and is listed till dropped.
        bare = re.match(r"(\d+) amended(?! \(\d+\))", each["label"])
        if bare and int(bare.group(1)) == decision and each["event"] == "seed":
            best = max(best, amended.get(decision, 0) + 1)
            in_log = True
        if re.match(r"%d(?!\d)" % decision, each["label"]) and each["event"] in ("new", "seed"):
            in_log = True
    if decision not in known and not in_log:
        return None
    return "%d amended (%d)" % (decision, best + 1)


def is_open(events):
    return any(each["event"] == "open" for each in events)


def on_main(label, text, headings):
    """Whether [label] has landed: a number's "## N" heading ([headings]), or
    an amendment label's own words, in main's [text]. Release's other seeded
    shapes can't be told: listed till dropped."""
    if AMEND_LABEL.match(label):
        return re.search(r"\b%s" % re.escape(label), text) is not None
    if re.fullmatch(r"\d+", label):
        return int(label) in headings
    return False


# --- The lock ----------------------------------------------------------------

def alive(pid):
    if not pid:
        return False
    if os.name != "nt":
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False
    kernel = ctypes.windll.kernel32
    kernel.OpenProcess.restype = ctypes.c_void_p
    handle = kernel.OpenProcess(0x1000, False, pid)  # QUERY_LIMITED_INFORMATION
    if not handle:
        return False
    code = ctypes.c_ulong()
    ok = kernel.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(code))
    kernel.CloseHandle(ctypes.c_void_p(handle))
    return bool(ok) and code.value == 259  # STILL_ACTIVE


class Lock:
    """The state's lock folder, held for the read and the append."""

    def __enter__(self):
        os.makedirs(STATE_DIR, exist_ok=True)
        lock = _path("lock")
        until = time.time() + LOCK_WAIT_SECONDS
        while True:
            try:
                os.mkdir(lock)
                with open(os.path.join(lock, "owner"), "w") as handle:
                    handle.write("%d %f\n" % (os.getpid(), time.time()))
                return self
            except (FileExistsError, PermissionError):
                # PermissionError (834 amended (1)): on Windows, a mkdir while the last
                # holder's rmdir is still delete-pending is refused as access denied, not
                # as existing: held a moment longer, so waited for like any other hold
                # (it took 5 of 360 asks, 12 at once, and failed a landing, 2026-11-12).
                if self._stale(lock):
                    try:
                        os.remove(os.path.join(lock, "owner"))
                    except OSError:
                        pass
                    try:
                        os.rmdir(lock)
                    except OSError:
                        pass
                    continue
            if time.time() > until:
                raise SystemExit(_fail("the decision numbers' lock is held (%s): try again" % lock, 4))
            time.sleep(0.02)

    @staticmethod
    def _stale(lock):
        try:
            age = time.time() - os.path.getmtime(lock)
        except OSError:
            return False
        if age < LOCK_STALE_SECONDS:
            return False
        try:
            with open(os.path.join(lock, "owner")) as handle:
                pid = int(handle.read().split()[0])
        except (OSError, ValueError, IndexError):
            pid = None
        return not alive(pid)

    def __exit__(self, *_):
        try:
            os.remove(_path("lock", "owner"))
        except OSError:
            pass
        # A waiter's look into the folder can hold it open for a moment on Windows: its
        # rmdir then refused, tried again for up to a second (834 amended (1)).
        until = time.time() + 1.0
        while True:
            try:
                os.rmdir(_path("lock"))
                return
            except PermissionError:
                if time.time() > until:
                    raise
                time.sleep(0.02)


def _fail(message, code):
    print("decision_number: %s" % message, file=sys.stderr)
    return code


# --- Commands ----------------------------------------------------------------

def new(tree, what):
    highest, _, _, _ = parse(main_text())
    with Lock():
        events = read_log()
        if not is_open(events):
            return _fail("not open yet: ask release", 3)
        number = str(next_number(highest, events))
        append(tree, "new", number, what)
    print(number)
    return 0


def amend(tree, decision, what):
    if not re.fullmatch(r"\d+", decision):
        return _fail("amend <tree> <decision> \"<what>\": a decision is a number, not %r" % decision, 2)
    _, amended, known, _ = parse(main_text())
    with Lock():
        events = read_log()
        if not is_open(events):
            return _fail("not open yet: ask release", 3)
        label = next_amendment(int(decision), amended, known, events)
        if label is None:
            return _fail("no decision %s, on main or handed out" % decision, 2)
        append(tree, "amend", label, what)
    print(label)
    return 0


def outstanding(events, text):
    """Hand-outs (new, amend, seed) not on main and not dropped, oldest first."""
    headings = set(int(n) for n in HEADING.findall(text))
    dropped = set(each["label"] for each in events if each["event"] == "drop")
    return [each for each in events if each["event"] in ("new", "amend", "seed") and each["label"] not in dropped
        and not on_main(each["label"], text, headings)]


def drop(tree, label, why):
    text = main_text()
    with Lock():
        events = read_log()
        held = [each for each in outstanding(events, text) if each["label"] == label]
        if not held:
            return _fail("%s is not out (not handed out, landed, or dropped already)" % label, 2)
        holder = held[-1]["tree"]
        if tree not in (holder, RELEASE):
            return _fail("%s is %s's: only its holder or release drops it" % (label, holder), 2)
        append(tree, "drop", label, why)
    print(label)
    return 0


def seed(by, label, tree, what):
    if by != RELEASE:
        return _fail("seed is release's, for the hand-over", 2)
    with Lock():
        events = read_log()
        if is_open(events):
            return _fail("open already: take numbers with new and amend", 2)
        append(tree, "seed", label, what)
    print(clean(label))
    return 0


def open_numbers(by):
    """Release's: the hand-over is in; numbers open, over main's highest
    heading as a fetch finds it now (written as the floor)."""
    if by != RELEASE:
        return _fail("open is release's", 2)
    if not os.environ.get(DECISIONS_ENV):
        subprocess.run(["git", "fetch", "-q", "origin", "main"])
    highest, _, _, _ = parse(main_text())
    with Lock():
        events = read_log()
        if is_open(events):
            return _fail("open already", 2)
        append(RELEASE, "open", str(highest), "the floor: origin/main's highest heading at open")
    print(highest)
    return 0


def status(show_all):
    text = main_text()
    events = read_log()
    if show_all:
        for each in events:
            print("\t".join((each["time"], each["tree"], each["event"], each["label"], each["what"])))
        return 0
    if not is_open(events):
        print("not open yet: release seeds its hand-outs, then opens")
    now = datetime.datetime.now()
    out = outstanding(events, text)
    width = min(48, max([len(each["label"]) for each in out] or [0]))
    for each in out:
        try:
            age = (now - datetime.datetime.fromisoformat(each["time"])).total_seconds() / 3600.0
        except ValueError:
            age = 0.0
        print("%-*s  %-16s %5.1f h  %s%s" % (width, each["label"], each["tree"], age, each["what"],
            " (seeded)" if each["event"] == "seed" else ""))
    return 0


def main(args):
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    command, rest = args[0], args[1:]
    if command == "new" and len(rest) == 2:
        return new(rest[0], rest[1])
    if command == "amend" and len(rest) == 3:
        return amend(rest[0], rest[1], rest[2])
    if command == "drop" and len(rest) == 3:
        return drop(rest[0], rest[1], rest[2])
    if command == "seed" and len(rest) == 4:
        return seed(rest[0], rest[1], rest[2], rest[3])
    if command == "open" and len(rest) == 1:
        return open_numbers(rest[0])
    if command == "status" and rest in ([], ["--all"]):
        return status(rest == ["--all"])
    return _fail("usage: new <tree> \"<what>\" | amend <tree> <decision> \"<what>\" | drop <tree> <label> \"<why>\" | "
        "status [--all] | seed release <label> <tree> \"<what>\" | open release", 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

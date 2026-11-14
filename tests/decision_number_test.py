"""tools/decision_number.py (decision 834): numbers and labels by script.
A state folder and a decisions.md of its own (DECISION_NUMBERS_DIR,
DECISION_NUMBERS_DECISIONS), never the real C:/dev/decision_numbers.
Python only, no Godot: a few seconds."""
import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STATE = tempfile.mkdtemp(prefix="decision_number_test_")
os.environ["DECISION_NUMBERS_DIR"] = os.path.join(STATE, "numbers")
DECISIONS = os.path.join(STATE, "decisions.md")
os.environ["DECISION_NUMBERS_DECISIONS"] = DECISIONS
sys.path.insert(0, os.path.join(ROOT, "tools"))
import decision_number as dn  # noqa: E402

failed = 0


def check(ok, what):
    global failed
    print("  %s  %s" % ("PASS" if ok else "FAIL", what))
    if not ok:
        failed += 1


def ask(*args):
    """dn.main in this process: (exit code, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        try:
            code = dn.main(list(args))
        except SystemExit as stop:
            code = stop.code
    return code, out.getvalue().strip(), err.getvalue().strip()


def log_lines():
    with open(os.path.join(os.environ["DECISION_NUMBERS_DIR"], "log.tsv"), encoding="utf-8") as handle:
        return [line.rstrip("\n").split("\t") for line in handle]


with open(DECISIONS, "w", encoding="utf-8") as handle:
    handle.write("# Decisions\n\n## 686. Something\ntext\n\n## 687, economy's side (x)\n\n## 688. Bodies\n"
        "688 amended (2026-10-01, combat): first.\n688 amended (7) (release's label): later.\n"
        "## 700 amended: a heading shape\n\n## 702. Last\n702 amended: bare, so (1).\n573 amended (1beb8148): a sha.\n")

print("== parse ==")
highest, amended, known, unplaced = dn.parse(open(DECISIONS, encoding="utf-8").read())
check(highest == 702, "the highest over every heading shape: %d" % highest)
check(amended.get(688) == 7 and amended.get(702) == 1 and amended.get(573) == 1,
    "D amended (k); a bare one and one with a date or a sha in brackets are (1): %s" % amended)
check(not unplaced, "nothing unplaced: %s" % unplaced)
check(dn.parse("700 amended (2026)\n")[3] == ["700 amended (2026)"], "a bracketed year is no label: unplaced")
# 11-10: 539's entry holds "Amended (economy's ...)", then (2), (3) and (4),
# and the script handed out 539 amended (1).
inner = ("## 539. A check\ntext\nAmended (economy's check, by release): x.\nAmended (2) (release): y.\n"
    "Amended (4) (release): z.\n## 540. Next\nAmended 2026-10-20: a date, so (1).\nAmended again: (2).\n"
    "## 541. More\nAmended a third time (release): w.\n"
    "## 542. Last\n542 amended a fifth time, then 394's eighth amendment.\n")
amended = dn.parse(inner)[1]
check(amended.get(539) == 4 and amended.get(540) == 2 and amended.get(541) == 3,
    "an \"Amended\" line inside its entry counts for it, one more than the last unless it names its k: %s" % amended)
check(amended.get(542) == 5 and amended.get(394) == 8, "\"D amended a fifth time\" and \"D's eighth amendment\" too: %s" % amended)
check(dn.parse("## 543. X\nAmended (3): a.\nAmended (2): b.\n")[1].get(543) == 3, "a lower k after a higher keeps the higher")

print("== closed until release opens ==")
code, out, err = ask("new", "perf", "x")
check(code == 3 and out == "" and "not open yet: ask release" in err, "new before the hand-over: refused, nothing on stdout (%s)" % err)
check(ask("amend", "perf", "688", "x")[0] == 3, "amend too")
check(ask("seed", "perf", "703", "economy", "x")[0] == 2, "seed is release's alone")
check(ask("seed", "release", "703", "economy", "day turn\twith a tab\nand a newline") == (0, "703", ""), "release seeds its hand-outs")
check(ask("seed", "release", "688 amended (8)", "combat", "free body")[0] == 0, "an amendment")
check(ask("seed", "release", "489 amended (4) plus the chimney paragraph", "buildings", "as written")[0] == 0,
    "a label as release wrote it")
check(ask("seed", "release", "686 amended", "terrain", "bare, as release wrote it")[0] == 0, "a bare label")
check(log_lines()[0][4] == "day turn with a tab and a newline", "tabs and newlines stripped: %r" % log_lines()[0][4])
check(ask("open", "perf")[0] == 2, "open is release's")
check(ask("open", "release") == (0, "702", ""), "release opens: the floor, main's highest")
check(ask("seed", "release", "999", "x", "late")[0] == 2, "no seeding once open")
check(ask("open", "release")[0] == 2, "nor opening twice")

print("== new and amend ==")
check(ask("new", "perf", "x") == (0, "704", ""), "a seeded number is skipped: 704")
check(ask("amend", "perf", "688", "x") == (0, "688 amended (9)", ""), "past main's (7) and the seeded (8)")
check(ask("amend", "perf", "702", "x") == (0, "702 amended (2)", ""), "a bare one counts as (1)")
check(ask("amend", "perf", "489", "x") == (0, "489 amended (5)", ""), "a seeded label as written counts toward k")
check(ask("amend", "perf", "703", "x") == (0, "703 amended (1)", ""), "a decision handed out and not landed can be amended")
check(ask("amend", "perf", "686", "x") == (0, "686 amended (2)", ""), "a bare seeded label holds the one after main's highest")
code, out, err = ask("amend", "perf", "912", "x")
check(code == 2 and out == "" and "no decision 912" in err, "an unknown decision is refused: %s" % err)
check(ask("amend", "perf", "68", "x")[0] == 2, "a prefix of one is no decision")
check(ask("amend", "perf", "six", "x")[0] == 2, "nor a word")
with open(DECISIONS, "a", encoding="utf-8") as handle:
    handle.write("## 710. Landed elsewhere\n")
check(ask("new", "perf", "x") == (0, "711", ""), "a number on main is skipped")

print("== drop ==")
check(ask("drop", "ui", "711", "not mine")[0] == 2, "drop by a tree not holding it: refused")
check(ask("drop", "perf", "711", "work dropped") == (0, "711", ""), "drop by its holder")
check(ask("new", "perf", "x") == (0, "712", ""), "a dropped number is never returned")
check(ask("drop", "release", "712", "for perf") == (0, "712", ""), "release may drop any")
check(ask("drop", "perf", "712", "again")[0] == 2, "not twice")

print("== status ==")
code, out, _ = ask("status")
labels = [line.split()[0] for line in out.splitlines()]
check(code == 0 and "703" in labels and "704" in labels and "711" not in labels and "712" not in labels,
    "status: what is out, not what was dropped: %s" % labels)
with open(DECISIONS, "a", encoding="utf-8") as handle:
    handle.write("## 704. Landed\n688 amended (9) (perf): landed.\n")
code, out, _ = ask("status")
check("704 " not in out + " " and "688 amended (9)" not in out and "688 amended (8)" in out,
    "a landed number and label leave status; the seeded (8) still out:\n%s" % out)
check("489 amended (4) plus the chimney paragraph" in out and "(seeded)" in out, "release's own shapes listed till dropped")
check(len(ask("status", "--all")[1].splitlines()) == len(log_lines()), "--all: the whole log")
check("686 amended " in out + " " and "702 amended (2)" in out, "a bare seeded label listed till dropped")

print("== at once ==")
base = int(ask("new", "perf", "x")[1])
start = time.time() + 1.5
runner = ("import sys, time; sys.path.insert(0, %r); import decision_number as dn; "
    "time.sleep(max(0.0, %f - time.time())); sys.exit(dn.main(sys.argv[1:]))") % (os.path.join(ROOT, "tools"), start)
procs = [subprocess.Popen([sys.executable, "-B", "-c", runner, "new", "t%d" % i, "at once"], stdout=subprocess.PIPE,
    stderr=subprocess.PIPE) for i in range(12)]
got = []
errors = []
for proc in procs:
    out, err = proc.communicate(timeout=60)
    if proc.returncode == 0:
        got.append(int(out.decode().strip()))
    else:
        # A failed ask's own words in the check line (834 amended (1)): this once read only "11 got".
        errors.append("exit %d: %s" % (proc.returncode, " | ".join(err.decode(errors="replace").strip().splitlines()[-2:])))
check(sorted(got) == list(range(base + 1, base + 13)), "12 asking new at once: 12 different, consecutive (%s)%s"
    % (sorted(got), "; " + "; ".join(errors) if errors else ""))
k = int(ask("amend", "perf", "688", "x")[1].split("(")[1].rstrip(")"))
start = time.time() + 1.5
runner = ("import sys, time; sys.path.insert(0, %r); import decision_number as dn; "
    "time.sleep(max(0.0, %f - time.time())); sys.exit(dn.main(sys.argv[1:]))") % (os.path.join(ROOT, "tools"), start)
procs = [subprocess.Popen([sys.executable, "-B", "-c", runner, "amend", "t%d" % i, "688", "at once"], stdout=subprocess.PIPE,
    stderr=subprocess.PIPE) for i in range(6)]
answers = [proc.communicate(timeout=60) for proc in procs]
labels = sorted(out.decode().strip() for out, _ in answers)
errors = [" | ".join(err.decode(errors="replace").strip().splitlines()[-2:]) for (_, err), proc in zip(answers, procs) if proc.returncode != 0]
want = sorted("688 amended (%d)" % n for n in range(k + 1, k + 7))
check(labels == want, "6 asking amend 688 at once: (k+1) to (k+6): %s%s" % (labels, "; " + "; ".join(errors) if errors else ""))

print("== the lock ==")
lock = os.path.join(os.environ["DECISION_NUMBERS_DIR"], "lock")
gone = subprocess.Popen([sys.executable, "-c", "pass"])
gone.wait()
os.mkdir(lock)
with open(os.path.join(lock, "owner"), "w") as handle:
    handle.write("%d %f\n" % (gone.pid, time.time() - 60))
old = time.time() - 60
os.utime(lock, (old, old))
code, out, _ = ask("new", "perf", "x")
check(code == 0 and out and not os.path.exists(lock), "a lock past 30 s whose holder is gone is taken over")
os.mkdir(lock)
with open(os.path.join(lock, "owner"), "w") as handle:
    handle.write("%d %f\n" % (os.getpid(), time.time() - 60))
os.utime(lock, (old, old))
saved_wait, dn.LOCK_WAIT_SECONDS = dn.LOCK_WAIT_SECONDS, 0.3
code, out, err = ask("new", "perf", "x")
dn.LOCK_WAIT_SECONDS = saved_wait
check(code == 4 and out == "" and "lock is held" in err, "an old lock whose holder lives is not taken: exit 4 (%s)" % err)
shutil.rmtree(lock)
# 834 amended (1): Windows refusing the lock's mkdir as access denied (a delete still pending)
# is waited for like a hold, within the same deadline: one that never clears ends in exit 4,
# not a spin; one that clears is taken.
real_mkdir = os.mkdir
refusals = {"left": 10 ** 9}
def refusing_mkdir(path, *rest):
    if os.path.basename(path) == "lock" and refusals["left"] > 0:
        refusals["left"] -= 1
        raise PermissionError(5, "Access is denied", path)
    return real_mkdir(path, *rest)
dn.os.mkdir = refusing_mkdir
saved_wait, dn.LOCK_WAIT_SECONDS = dn.LOCK_WAIT_SECONDS, 0.3
began = time.time()
code, out, err = ask("new", "perf", "x")
took = time.time() - began
check(code == 4 and out == "" and "lock is held" in err and took < 30,
    "a lock mkdir refused as access denied forever: exit 4 within the deadline, %.1f s (%s)" % (took, err))
refusals["left"] = 3
code, out, err = ask("new", "perf", "x")
check(code == 0 and out.isdigit() and refusals["left"] == 0, "refused three times, then taken: %s (%s)" % (out, err))
dn.os.mkdir = real_mkdir
dn.LOCK_WAIT_SECONDS = saved_wait

print("== the real docs/decisions.md ==")
real = os.path.join(ROOT, "docs", "decisions.md")
text = open(real, encoding="utf-8").read()
highest, amended, known, unplaced = dn.parse(text)
odd = [line for line in text.splitlines() if line.startswith("## ") and not dn.HEADING.match(line)]
check(not odd, "every '## ' heading placed (%d unplaced%s)" % (len(odd), ": " + "; ".join(odd[:5]) if odd else ""))
check(not unplaced, "every 'D amended' label placed (%d unplaced%s)" % (len(unplaced), ": " + "; ".join(unplaced[:5]) if unplaced else ""))
shutil.rmtree(os.environ["DECISION_NUMBERS_DIR"])
os.environ["DECISION_NUMBERS_DECISIONS"] = real
check(ask("open", "release")[0] == 0, "opened over the real file")
code, out, _ = ask("new", "perf", "x")
check(code == 0 and int(out) > 833, "new there gives more than 833: %s" % out)
print("  (highest heading %d, %d decisions with amendments, highest k %d on %d)" % (
    highest, len(amended), max(amended.values()), max(amended, key=amended.get)))

shutil.rmtree(STATE, ignore_errors=True)
print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

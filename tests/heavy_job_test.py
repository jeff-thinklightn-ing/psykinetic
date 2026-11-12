#!/usr/bin/env python3
"""tools/heavy_job.py's gate (decision 394): its decision with made-up
memory numbers, the estimate update, the newest-first stop, and a take and
release through a state folder of its own (HEAVY_JOBS_DIR), never the real
one.
  python tests/heavy_job_test.py
"""
import contextlib
import datetime
import io
import json
import os
import re
import shutil
import sys
import tempfile
import time

sys.dont_write_bytecode = True  # No __pycache__ left in tools/.
STATE = tempfile.mkdtemp(prefix="heavy_job_test_")
os.environ["HEAVY_JOBS_DIR"] = STATE
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import heavy_job as gate  # noqa: E402
# Never ask saturn from a test (394 amended (33)): a take of suite asks the
# checkout's own tools/remote_tests.sh kind, which reaches saturn. Stubbed
# here as "saturn does not answer"; the swap's own checks set their own.
gate.PROBE_COMMAND = [sys.executable, "-c", "print('suite')"]
# Nor clear this checkout's stray files (394 amended (35)): on for its own checks only.
gate.STRAY_CHECK = False

real_boot_time = gate.boot_time
gate.boot_time = lambda: 0.0  # Entries made up as hours old stay after this machine's boot.

failed = 0


def check(ok, what):
    global failed
    print("  %s  %s" % ("PASS" if ok else "FAIL", what))
    if not ok:
        failed += 1


suite = {"ram_gb": 4.0, "gpu_gb": 0.0, "gpu": False}
mesh = {"ram_gb": 9.0, "gpu_gb": 12.0, "gpu": True}
comfy = {"ram_gb": 6.0, "gpu_gb": 10.0, "gpu": True}


def running(ram, using, gpu=False, started=0.0):
    return {"ram_gb": ram, "using_gb": using, "gpu": gpu, "started": started}


print("== the gate ==")
check(gate.decide(suite, [], True, 30.0, None)[0], "room: 30 GB free for 4 + 8")
ok, why = gate.decide(suite, [], True, 11.0, None)
check(not ok and "wanted" in why, "11 GB free is not 4 + 8: %s" % why)
check(gate.decide(suite, [], True, 12.0, None)[0], "exactly 4 + 8 free starts")
ok, why = gate.decide(suite, [], False, 60.0, None)
check(not ok and "queue" in why, "not at the head: waits however much is free")
ok, why = gate.decide(suite, [running(3, 1), running(3, 1), running(3, 1)], True, 60.0, None)
check(not ok and "3 heavy" in why, "three running: waits (%s)" % why)
ok, why = gate.decide(mesh, [running(6, 6, gpu=True)], True, 60.0, 20.0)
check(not ok and "GPU job" in why, "never two GPU jobs: %s" % why)
check(gate.decide(mesh, [running(4, 4)], True, 60.0, 20.0)[0], "a GPU job beside a CPU one")
ok, why = gate.decide(comfy, [], True, 60.0, 8.0)
check(not ok and "GPU free" in why, "8 GB GPU free is not 10: %s" % why)
check(gate.decide(comfy, [], True, 60.0, None)[0], "no GPU known: only RAM counts")
# A job just started has taken little yet: what it is still owed counts.
ok, why = gate.decide(suite, [running(9, 1)], True, 18.0, None)
check(not ok and "owed" in why, "18 free but 8 owed to a mesh just started: waits (%s)" % why)
check(gate.decide(suite, [running(9, 9)], True, 20.0, None)[0], "the mesh at its estimate: nothing owed, 20 free starts")
check(gate.reserved_gb([running(9, 12)]) == 0.0, "a job past its estimate owes nothing (not less)")

print("== a kind's cap, and commit ==")
capped = dict(suite, kind="suite", max_running=1)
other = dict(running(4, 4), kind="suite")
ok, why = gate.decide(capped, [other], True, 60.0, None)
check(not ok and "at most 1" in why, "one suite running: a second waits, room or not (%s)" % why)
check(gate.decide(capped, [dict(running(2, 2), kind="godot_import")], True, 60.0, None)[0], "a suite beside an import")
check(gate.decide(dict(suite, kind="godot_import"), [other], True, 60.0, None)[0], "an import beside a suite (no cap)")
bench_row = dict(suite, kind="bench", excludes=["suite"])
ok, why = gate.decide(bench_row, [other], True, 60.0, None)
check(not ok and "never beside" in why, "a bench waits while a suite runs (%s)" % why)
ok, why = gate.decide(dict(capped, excludes=["bench"]), [dict(running(2, 2), kind="bench")], True, 60.0, None)
check(not ok and "never beside" in why, "and a suite while a bench runs (%s)" % why)
check(gate.decide(bench_row, [dict(running(2, 2), kind="godot_import")], True, 60.0, None)[0], "a bench beside an import")
check("suite" in gate.KINDS["bench"]["excludes"] and "bench" in gate.KINDS["suite"]["excludes"], "the kinds say so both ways")
# A landing whose Godot tests run on saturn (suite_remote): a kind of its own, sized for the parts left here.
remote_row = dict(gate.KINDS["suite_remote"], kind="suite_remote")
check("suite_remote" in gate.KINDS["bench"]["excludes"] and "bench" in remote_row["excludes"], "a bench and a saturn landing's local parts never together, both ways")
check(gate.out_of_reach(dict(gate.KINDS["suite_lean3"]), [], 12.5) and not gate.out_of_reach(remote_row, [], 12.5),
    "12.5 GB free: a lean suite is out of reach, a saturn landing's local parts are not")
check("variant_of" not in remote_row and "lean" not in remote_row, "and the suite's estimate never learns from it")
check(remote_row.get("remote") and gate.limit_seconds(dict(remote_row, runs_s=[415.0])) == remote_row["max_minutes"] * 60.0,
    "its limit is fixed, not three short runs' median: saturn's own timeouts sum past that")

print("== going past those that wait on their own kind ==")
import_row = dict(suite, kind="godot_import")
queued_suite = dict(capped, excludes=["bench"])
check(gate.may_pass(import_row, [queued_suite], [other]), "an import goes past a suite waiting for the suite running")
check(not gate.may_pass(dict(capped, excludes=["bench"]), [queued_suite], [other]), "a second suite does not go past the first")
check(not gate.may_pass(bench_row, [queued_suite], [other]), "nor a bench (it excludes suites)")
check(not gate.may_pass(import_row, [dict(suite, kind="trellis_mesh", gpu=True)], [other]),
	"nor anything past a job waiting for memory (first come for that)")
check(gate.may_pass(import_row, [], [other]), "first in the queue: its turn")
# art-gen's mesh job at the head wanting 28.9 + 8 GB with 32 GB free and
# nothing running held ten landings for half an hour (release, 2026-10-18).
mesh = dict(suite, kind="trellis_mesh", ram_gb=28.9, gpu=True)
check(gate.out_of_reach(mesh, [], 32.0) and gate.may_pass(capped, [mesh], [], 32.0),
	"a job out of reach even with nothing running is gone past by one that fits")
check(not gate.out_of_reach(mesh, [dict(running(6, 6), kind="suite")], 32.0) and not gate.may_pass(import_row, [mesh], [dict(running(6, 6), kind="suite")], 32.0),
	"but not when the running jobs' memory would make room: then first come again")
check(gate.out_of_reach(mesh, [], 60.0, 20.0), "out of reach on commit too")
ok, why = gate.decide(suite, [], True, 60.0, None, 5.0)
check(not ok and why.startswith("commit"), "60 GB RAM free but 5 GB commit: waits, saying commit (%s)" % why)
check(gate.decide(suite, [], True, 60.0, None, 4.0 + gate.COMMIT_MARGIN_GB)[0], "commit at the estimate plus its margin starts")
check(gate.decide(suite, [], True, 60.0, None, None)[0], "no commit known: RAM alone")

print("== stopping: the newest job, under the margin ==")
older, newer = running(4, 4, started=10.0), running(9, 9, started=20.0)
check(not gate.should_stop(older, [older, newer], 5.0), "under the margin, the older job keeps on")
check(gate.should_stop(newer, [older, newer], 5.0), "the newest stops")
check(not gate.should_stop(newer, [older, newer], 9.0), "above the margin, nothing stops")
check(gate.should_stop(newer, [older, newer], 30.0, gate.COMMIT_STOP_GB - 0.5), "RAM to spare but free commit under COMMIT_STOP_GB: the newest stops (394 amended (16))")
check(not gate.should_stop(older, [older, newer], 30.0, gate.COMMIT_STOP_GB - 0.5), "and the older keeps on")
check(not gate.should_stop(newer, [older, newer], 30.0, gate.COMMIT_STOP_GB + 0.5), "above it, nothing stops")
check(gate.short_of_memory(30.0, 1.0) == "commit" and gate.short_of_memory(5.0, 1.0) == "RAM" and gate.short_of_memory(30.0, None) == "",
	"what it is short of is named, RAM first; no commit known, RAM alone")
lean3 = dict(suite, ram_gb=7.2, commit_gb=6.1)
check(gate.decide(lean3, [], True, 15.9, None, 13.3)[0], "today's baseline (15.9 GB RAM, 13.3 GB commit free): a lean suite starts (394 amended (16))")

print("== estimates ==")
check(gate.updated_estimate(4.0, 6.0) == 6.0, "a higher peak: up to it at once")
check(gate.updated_estimate(4.0, 2.0) == 3.6, "a lower peak: down a fifth of the way")

print("== take and release, a state folder of its own ==")
gate.POLL_SECONDS = 0.05
gate.WATCH_SECONDS = 0.2
gate.MARGIN_GB = -1e9  # The gate's room is not what this part tests.
gate.COMMIT_MARGIN_GB = -1e9
check(gate.take("test", "suite", os.getpid()) == 0, "take")
entries = gate._entries("running")
check(len(entries) == 1 and entries[0]["tree"] == "test", "running: one, test's")
check(gate.release("test", "suite") == 0 and not gate._entries("running"), "released: none running")
dead = {"tree": "gone", "kind": "bench", "pid": 999999, "queued": time.time(), "started": time.time(),
    "ram_gb": 3.0, "gpu": False}
with gate.StateLock():
    gate._write(gate._path("running", "gone-bench-999999.json"), dead)
    check(not gate._entries("running"), "a running entry whose process is gone is dropped")
old_take = {"tree": "forgot", "kind": "suite", "pid": os.getpid(), "queued": time.time() - 7200,
    "started": time.time() - gate.TAKE_STALE_SECONDS - 60, "ram_gb": 6.0, "gpu": False, "watched": False}
with gate.StateLock():
    gate._write(gate._path("running", "forgot-suite-1.json"), old_take)
    check(not gate._entries("running"), "a take held past TAKE_STALE_SECONDS is dropped, its shell alive or not")
    gate._write(gate._path("queue", "forgot-suite-1.json"), old_take)
    check(len(gate._entries("queue")) == 1, "a take waiting its turn that long is kept")
    gate._write(gate._path("queue", "dead-suite-1.json"), dict(old_take, tree="dead", waiter=999999))
    check(len(gate._entries("queue")) == 1, "a queued take whose waiter is gone (a stopped landing) is dropped")
    os.remove(gate._path("queue", "forgot-suite-1.json"))
    gate._write(gate._path("running", "forgot-suite-1.json"), dict(old_take, adopted_by=os.getpid()))
    check(len(gate._entries("running")) == 1, "a take that old is kept while a run inside it lives (a slow landing)")
    os.remove(gate._path("running", "forgot-suite-1.json"))

print("== an id reused, an entry from before a reboot (394 amended (8)) ==")
me = gate.started_at(os.getpid())
fresh = {"tree": "mine", "kind": "suite", "pid": os.getpid(), "pid_since": me, "queued": time.time(), "started": time.time(),
    "ram_gb": 6.0, "gpu": False, "watched": True}
with gate.StateLock():
    gate._write(gate._path("running", "mine-suite-1.json"), fresh)
    check(len(gate._entries("running")) == 1, "a live id with its own start time is kept")
    if me is not None:
        gate._write(gate._path("running", "mine-suite-1.json"), dict(fresh, pid_since=me - 1))
        check(not gate._entries("running"), "the same id with another start time (reused by a new process) is dropped")
        gate._write(gate._path("queue", "mine-suite-1.json"), dict(fresh, waiter=os.getpid(), waiter_since=me + 1))
        check(not gate._entries("queue"), "and a queued entry whose waiter's id was reused")
    gate._write(gate._path("running", "mine-suite-1.json"), {k: v for k, v in fresh.items() if k != "pid_since"})
    check(len(gate._entries("running")) == 1, "an entry with no start time (an older heavy_job.py) by its id alone")
    gate.boot_time = lambda: fresh["queued"] + 1  # The machine started after it was queued.
    check(not gate._entries("running"), "an entry queued before the machine started is dropped")
    gate.boot_time = lambda: 0.0
    for folder in ("running", "queue"):
        for name in os.listdir(gate._path(folder)):
            os.remove(gate._path(folder, name))
if os.name == "nt":
    booted = real_boot_time()
    check(0 < time.time() - booted < 365 * 86400, "the machine's start read (%.1f h ago)" % ((time.time() - booted) / 3600))

print("== a soak (394 amended (8)) ==")
table = gate.kinds()
soak_row = dict(table["soak"], kind="soak")
suite_running = dict(running(6, 6), kind="suite")
check(gate.decide(soak_row, [suite_running], True, 60.0, None)[0], "a soak starts beside a suite")
check(gate.decide(dict(table["suite"], kind="suite"), [dict(running(2, 2), kind="soak")], True, 60.0, None)[0],
    "and a suite beside a soak")
ok, why = gate.decide(soak_row, [dict(running(1, 1), kind="bench")], True, 60.0, None)
check(not ok and "never beside" in why, "never beside a bench (%s)" % why)
ok, why = gate.decide(dict(table["bench"], kind="bench"), [dict(running(2, 2), kind="soak")], True, 60.0, None)
check(not ok and "never beside" in why, "nor a bench beside a soak (%s)" % why)
ok, why = gate.decide(soak_row, [dict(running(2, 2), kind="soak")], True, 60.0, None)
check(not ok and "at most 1" in why, "one soak at a time (%s)" % why)
check(gate.may_pass(soak_row, [dict(table["suite"], kind="suite")], [suite_running]),
    "a soak goes past a suite waiting for the suite running")
check(gate.limit_seconds(dict(table["soak"], runs_s=[60.0, 60.0, 60.0])) == 180 * 60.0,
    "its limit is 180 minutes, whatever its runs took")
check(gate.limit_seconds(table["soak"], expect_minutes=600) == 36000.0, "--expect over that")

print("== a scene (394 amended (17)) ==")
scene_row = dict(table["scene"], kind="scene")
check(gate.decide(scene_row, [suite_running], True, 60.0, None)[0], "a scene starts beside a suite")
check(gate.decide(dict(table["suite"], kind="suite"), [dict(running(1, 1), kind="scene")], True, 60.0, None)[0],
    "and a suite beside a scene")
check(gate.decide(scene_row, [suite_running, dict(running(1, 1), kind="scene")], True, 60.0, None)[0],
    "two scenes at once")
ok, why = gate.decide(scene_row, [dict(running(1, 1), kind="scene"), dict(running(1, 1), kind="scene")], True, 60.0, None)
check(not ok and "at most 2" in why, "not three (%s)" % why)
ok, why = gate.decide(scene_row, [dict(running(1, 1), kind="bench")], True, 60.0, None)
check(not ok and "never beside" in why, "never beside a bench (%s)" % why)
ok, why = gate.decide(dict(table["bench"], kind="bench"), [dict(running(1, 1), kind="scene")], True, 60.0, None)
check(not ok and "never beside" in why, "nor a bench beside a scene (%s)" % why)
with gate.StateLock():
    gate._write(gate._path("kinds.json"), {"bench": {"ram_gb": 1.2, "gpu_gb": 0.0, "gpu": False, "excludes": ["suite"]}})
check("soak" in gate.kinds()["bench"]["excludes"], "a kinds.json from before the soak still keeps a bench from one")
check("scene" in gate.kinds()["bench"]["excludes"], "and from a scene")
os.remove(gate._path("kinds.json"))

print("== a windowed Godot off-screen and silent, or refused (664 amended (2)) ==")
G = "/c/Users/jequi/Godot/Godot_v4.7.2-stable_win64.exe"
check(gate.unseen_problem(["/usr/bin/timeout", "900", G + "_console.exe", "--headless", "--path", ".", "--scene", "x.tscn"]) is None,
    "a headless one passes")
check(gate.unseen_problem(["/usr/bin/timeout", "400", G, "--log-file", "a.log", "--audio-driver", "Dummy", "--position", "4000,4000",
    "--path", ".", "--scene", "res://tools/map_bench.tscn", "--", "--map=wilds"]) is None, "map_bench as perf's benches start it passes")
why = gate.unseen_problem([G, "--audio-driver", "Dummy", "--path", ".", "--", "--position", "4000,4000", "--map=wilds"])
check(why is not None and "--position" in why and "after it" in why and gate.OFF_SCREEN in why,
    "--position after the first -- (terrain's, 00:02) is refused, saying what to add: %s" % why)
why = gate.unseen_problem(["C:\\Users\\jequi\\Godot\\Godot_v4.7.2-stable_win64.exe", "--path", "."])
check(why is not None and "--position or --audio-driver" in why, "a bare windowed one, a Windows path: both named (%s)" % why)
check(gate.unseen_problem(["bash", "tools/clip.sh", "x", "out"]) is None, "a script is not looked into (godot_log_check reads the repo's)")
check(gate.unseen_problem(["python", "-B", "tools/x.py", "--", "godot"]) is not None, "a Godot anywhere in the line is read")
code = gate.main(["run", "perf", "scene", "--", G, "--path", "."])
check(code == 2, "heavy_job run refuses it before queueing (exit %s)" % code)
code = gate.main(["run", "perf", "scene", "--visible", "--", sys.executable, "-c", "pass"])
check(code == 0, "--visible is taken as an option (exit %s)" % code)
code = gate.main(["run", "perf", "scene", "--expect", "300", "--", sys.executable, "-c", "pass"])
check(code == 2 and not gate._entries("queue"), "a scene with --expect 300 is refused before it queues: a soak (394 amended (32)) (%s)" % code)
code = gate.main(["run", "perf", "scene", "--expect", "20", "--", sys.executable, "-c", "pass"])
check(code == 0, "--expect 20 runs (%s)" % code)
# 394 amended (31): never queue at the gate holding the land lock.
check(gate.lock_owned("perf", "perf") and gate.lock_owned("psykinetic-release", "release") and gate.lock_owned("items-cast", "items")
    and not gate.lock_owned("ui-design", "ui") and not gate.lock_owned("maps", "perf") and not gate.lock_owned("perf", ""),
    "the lock's owner matched by holds_lock's rules")
held_lock = os.path.join(STATE, "held.lock")
os.makedirs(held_lock, exist_ok=True)
real_memory_nq = gate._memory
gate._memory = lambda: (60.0, 60.0)
for owner, tree, want in (("perf", "perf", gate.NO_QUEUE_CODE), ("release", "psykinetic-release", gate.NO_QUEUE_CODE),
        ("maps", "perf", 0)):
    with open(os.path.join(held_lock, "owner"), "w") as handle:
        handle.write(owner + "\n")
    code = gate.main(["run", tree, "scene", "--no-queue-under-lock", held_lock, "--", sys.executable, "-c", "pass"])
    check(code == want and not gate._entries("queue"),
        "%s's run, the lock %s's: exit %s, never queued (%s)" % (tree, owner, want, code))
gate.take("perf", "scene", os.getpid())
with open(os.path.join(held_lock, "owner"), "w") as handle:
    handle.write("perf\n")
code = gate.main(["run", "perf", "scene", "--no-queue-under-lock", held_lock, "--", sys.executable, "-c", "pass"])
check(code == 0, "holding the lock inside its own take: it runs in the take (%s)" % code)
gate.release("perf", "scene")
check(gate.main(["run", "perf", "scene", "--no-queue-under-lock", os.path.join(STATE, "no.lock"), "--", sys.executable, "-c", "pass"]) == 0,
    "no lock held: it runs as before")
gate._memory = real_memory_nq
shutil.rmtree(held_lock, ignore_errors=True)

print("== a take beaten while its tree waits on the land lock (394 amended (31)) ==")
import subprocess  # noqa: E402


def old_take(tree, pid=None, beat=None):
    entry = {"tree": tree, "kind": "suite", "pid": pid, "queued": time.time() - 7200,
        "started": time.time() - gate.TAKE_STALE_SECONDS - 60, "ram_gb": 6.0, "gpu": False, "watched": False}
    if pid:
        entry["pid_since"] = gate.started_at(pid)
    if beat is not None:
        entry["beat"] = beat
    gate._write(gate._path("running", "%s-suite-1.json" % tree), entry)


def takes():
    return {each["tree"]: each for each in gate._entries("running")}


with gate.StateLock():
    old_take("waiting", beat=time.time() - 60)
    check("waiting" in takes(), "a take past TAKE_STALE_SECONDS, beaten a minute ago, is kept")
    old_take("waiting")
    check("waiting" not in takes(), "unbeaten, it is dropped as before")
def young_take(tree, pid=None):
    entry = {"tree": tree, "kind": "suite", "pid": pid, "queued": time.time(), "started": time.time() - 60,
        "ram_gb": 6.0, "gpu": False, "watched": False}
    if pid:
        entry["pid_since"] = gate.started_at(pid)
    gate._write(gate._path("running", "%s-suite-1.json" % tree), entry)


for tree in ("psykinetic-release", "items-cast", "ui-design"):
    young_take(tree)
check(gate.beat("release", "suite") == 0 and "beat" in takes()["psykinetic-release"],
    "release's lock beats psykinetic-release's take (holds_lock's rules, 748 amended (8))")
check(gate.beat("items", "suite") == 0 and "beat" in takes()["items-cast"], "items' lock beats its side worktree's take")
check(gate.beat("ui", "suite") == 1 and "beat" not in takes()["ui-design"],
    "ui's lock never beats ui-design's, a tree of its own (it beat: %s)" % [t for t, e in takes().items() if "beat" in e])
young_take("renamed", os.getpid())
check(gate.beat("release", "suite") == 0 and "beat" in takes()["renamed"],
    "a take whose holder is this process's ancestor comes before psykinetic-<owner>")
check(gate.beat("nobody", "suite") == 0, "and is found whatever its name")
for tree in list(takes()):
    os.remove(gate._path("running", "%s-suite-1.json" % tree))
check(gate.beat("release", "suite") == 1, "no take held: exit 1")
gate._write(gate._path("running", "maps-suite_remote-1.json"), {"tree": "maps", "kind": "suite_remote", "pid": None,
    "queued": time.time(), "started": time.time() - 60, "ram_gb": 2.0, "gpu": False, "watched": False})
gate._write(gate._path("running", "maps-scene-1.json"), {"tree": "maps", "kind": "scene", "pid": None,
    "queued": time.time(), "started": time.time() - 60, "ram_gb": 1.0, "gpu": False, "watched": False})
check(gate.main(["beat", "maps"]) == 0 and "beat" in gate._read(gate._path("running", "maps-suite_remote-1.json"))
    and "beat" not in gate._read(gate._path("running", "maps-scene-1.json")),
    "with no kind named, any landing's take is beaten (a remote landing's suite_remote), never a scene")
os.remove(gate._path("running", "maps-suite_remote-1.json"))
os.remove(gate._path("running", "maps-scene-1.json"))

# tools/land_lock.sh itself: a frozen lock is never beaten, and says so with exit 3.
shell = shutil.which("sh") or next((p for p in (r"C:\Program Files\Git\bin\sh.exe", r"C:\Program Files\Git\usr\bin\sh.exe")
    if os.path.exists(p)), None)
if shell is None:
    print("  SKIP  land_lock.sh's beat: no sh here")
else:
    repo = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    lock = os.path.join(STATE, "land.lock")
    lock_env = dict(os.environ, PSYKINETIC_LAND_LOCK=lock.replace("\\", "/"), HEAVY_JOBS_DIR=STATE)
    def try_lock(what):
        done = subprocess.run([shell, "tools/land_lock.sh", "take", "probe", what], cwd=repo, env=lock_env,
            capture_output=True, text=True, timeout=60)
        return done.returncode, done.stdout + done.stderr
    def hold_lock(owner, what):
        shutil.rmtree(lock, ignore_errors=True)
        os.makedirs(lock)
        for name, value in (("owner", owner), ("what", what), ("taken", str(int(time.time()))), ("since", str(int(time.time())))):
            with open(os.path.join(lock, name), "w") as handle:
                handle.write(value + "\n")
    probe = {"tree": "probe", "kind": "suite", "pid": None, "queued": time.time(), "started": time.time() - 600,
        "ram_gb": 6.0, "gpu": False, "watched": False}
    gate._write(gate._path("running", "probe-suite-1.json"), probe)
    hold_lock("release", "main frozen for v0.1.212")
    code, said = try_lock("a landing")
    check(code == 3 and "main frozen" in said and "requeue" in said and "beat" not in takes().get("probe", {}),
        "a take tried against a frozen lock: exit 3, told to requeue, its gate take not beaten (%s, %s)" % (code, said.strip()))
    hold_lock("builder", "859: builder spot tool")
    code, said = try_lock("a landing")
    check(code == 1 and "beat" in takes().get("probe", {}), "held by a landing: exit 1, and its gate take beaten (%s)" % code)
    shutil.rmtree(lock, ignore_errors=True)
    gate._write(gate._path("running", "probe-suite-1.json"), probe)
    code, said = try_lock("a landing")
    check(code == 0 and "beat" in takes().get("probe", {}), "free: taken, and beaten (%s)" % code)
    shutil.rmtree(lock, ignore_errors=True)
    os.remove(gate._path("running", "probe-suite-1.json"))
    try:
        os.remove(lock + ".log")
    except OSError:
        pass

print("== the guard: older gate code's check skips a take new code holds (394 amended (37)) ==")


def pre31_stale(entry):
    """c89bb21fa^'s _entries check of a running entry, as it was: older gate
    code still run from checkouts that predate 394 amended (31)."""
    pid = entry.get("pid")
    stale = bool(pid) and not gate.alive(pid, entry.get("pid_since"))
    if not entry.get("watched") and not gate.alive(entry.get("adopted_by"), entry.get("adopted_since")):
        stale = stale or time.time() - entry.get("started", entry["queued"]) > gate.TAKE_STALE_SECONDS
    return stale


def held_file(tree):
    return next((name for name in os.listdir(gate._path("running")) if name.startswith(tree + "-")), None)


def aged(tree, **more):
    """[tree]'s take made 31 minutes old (and [more] set), as written."""
    name = held_file(tree)
    entry = gate._read(gate._path("running", name))
    entry.update(dict({"started": time.time() - gate.TAKE_STALE_SECONDS - 60}, **more))
    gate._write(gate._path("running", name), entry)
    return entry


holder = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
gate.take("pidded", "suite_remote", holder.pid)
entry = aged("pidded")
check(entry.get("gate") == gate.GATE_REVISION and entry.get("checkout") == gate.CHECKOUT,
    "a take carries the gate's revision and its checkout (%s, %s)" % (entry.get("gate"), entry.get("checkout")))
check(entry.get("guard") and entry.get("adopted_by") == holder.pid, "its --pid named as its guard")
check(not pre31_stale(entry), "older code's check skips it, 31 minutes old, while its holder lives")
with gate.StateLock():
    check(held_file("pidded") is None or not any(each["tree"] == "pidded" for each in gate._entries("running")),
        "new code drops it, unbeaten 31 minutes: the guard is no adoption to the beats")
gate.take("pidded", "suite_remote", holder.pid)
entry = aged("pidded", beat=time.time() - 60)
with gate.StateLock():
    check(any(each["tree"] == "pidded" for each in gate._entries("running")), "beaten a minute ago, new code keeps it")
holder.kill()
holder.wait()
check(pre31_stale(entry), "its holder dead: older code drops it, as it should")
gate.release("pidded", "suite_remote")

# A run adopts the take, then gives it back: the guard returns, no gap.
holder = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
gate.take("adopt", "suite_remote", holder.pid)
check(gate.run("adopt", "suite_remote", [sys.executable, "-c", "pass"]) == 0, "a run inside the take")
entry = gate._read(gate._path("running", held_file("adopt")))
check(entry.get("guard") and entry.get("adopted_by") == holder.pid and not pre31_stale(dict(entry, started=0.0)),
    "the run ended: its guard is back on the holder (%s, %s)" % (entry.get("guard"), entry.get("adopted_by")))
gate.release("adopt", "suite_remote")
holder.kill()
holder.wait()

# Older code's entries, and an unbeaten landing take (394 amended (38), the
# coordinator's three ages): one with no revision stands for both pre-31 and
# 31-36 code (the same on disk) and is counted, never named; one with a lower
# revision is named and logged once; one from this code is neither.
def seeded(name, tree, **more):
    gate._write(gate._path("queue", name), dict({"tree": tree, "kind": "scene", "pid": None, "waiter": os.getpid(),
        "waiter_since": gate.started_at(os.getpid()), "queued": time.time()}, **more))
seeded("0000000000000000001-oldie-1.json", "oldie")
seeded("0000000000000000002-lower-1.json", "lower", gate=gate.GATE_REVISION - 1, checkout="C:/dev/psykinetic-trees/lower")
seeded("0000000000000000003-current-1.json", "current", gate=gate.GATE_REVISION, checkout=gate.CHECKOUT)
gate._write(gate._path("running", "stuck-suite_remote-1.json"), gate.guard({"tree": "stuck", "kind": "suite_remote", "pid": None,
    "queued": time.time() - 700, "started": time.time() - 700, "ram_gb": 1.7, "gpu": False, "watched": False,
    "gate": gate.GATE_REVISION, "checkout": "C:/dev/psykinetic-trees/stuck"}, os.getpid(), gate.started_at(os.getpid())))
with open(gate._path("heavy_jobs.log"), "a") as handle:  # 37's own note of an unrevised entry, as it wrote them.
    handle.write("%s\told_gate\tearly\tscene\tqueue, pid 1, its checkout unknown (written before 394 amended (37)); rebase it\n"
        % time.strftime("%Y-%m-%dT%H:%M:%S"))
said = io.StringIO()
with contextlib.redirect_stdout(said):
    gate.status()
    gate.status()
said = said.getvalue()
named = [line for line in said.splitlines() if line.startswith("on older gate code:")]
check(len(named) == 2 and all("lower scene (queued), pid %d, gate revision %d of %d, C:/dev/psykinetic-trees/lower"
    % (os.getpid(), gate.GATE_REVISION - 1, gate.GATE_REVISION) in line for line in named),
    "status names only the entry of a known lower revision, with its checkout (%s)" % named[:1])
check(not any("oldie" in line or "current" in line for line in named), "nor one with no revision, nor one of this code")
check("written before 394 amended (37), gate revision unknown: 1 (a count only" in said,
    "an unrevised entry is counted, with no claim of harm")
since = time.strftime("%H:%M", time.localtime(gate._read(gate._path("running", "stuck-suite_remote-1.json"))["started"]))
check(("unbeaten: stuck suite_remote held 12 min, since %s, no beat" % since) in said and "C:/dev/psykinetic-trees/stuck" in said,
    "status names a landing take 10 minutes unbeaten: whose, since when, and its checkout (the coordinator's ask)")
with open(gate._path("heavy_jobs.log")) as handle:
    logged = handle.read()
check(logged.count("\told_gate\tlower\t") == 1 and logged.count("\tunbeaten\tstuck\t") == 1
    and "\told_gate\toldie\t" not in logged and "\told_gate\tcurrent\t" not in logged,
    "the lower one and the unbeaten take each logged once; the unrevised and the current not at all")
said = io.StringIO()
with contextlib.redirect_stdout(said):
    gate.summary(datetime.date.today().isoformat())
by_tree = dict(re.findall(r": (old_gate|unbeaten) by tree: (.*)", said.getvalue()))
check("lower 1" in by_tree.get("old_gate", "") and "early" not in by_tree.get("old_gate", "")
    and "stuck 1" in by_tree.get("unbeaten", ""),
    "the summary counts them by tree, leaving out 37's notes of unrevised entries (%s)" % by_tree)
for name in ("0000000000000000001-oldie-1.json", "0000000000000000002-lower-1.json", "0000000000000000003-current-1.json"):
    os.remove(gate._path("queue", name))
os.remove(gate._path("running", "stuck-suite_remote-1.json"))

if shell is not None:
    # The case that bit (the coordinator's): a take made by `heavy_job.sh take`, a
    # process that ends at once, from a script that then waits on the land lock.
    env = dict(os.environ, HEAVY_JOBS_DIR=STATE)
    script = subprocess.Popen([shell, "-c", "sh tools/heavy_job.sh take shortcall suite_remote && echo taken && read line"],
        cwd=repo, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    start = time.time()
    while held_file("shortcall") is None and time.time() - start < 60 and script.poll() is None:
        time.sleep(0.2)
    time.sleep(1.0)  # `take` itself gone.
    entry = aged("shortcall") if held_file("shortcall") else {}
    guard_by = entry.get("adopted_by")
    check(entry.get("guard") and gate.alive(guard_by, entry.get("adopted_since")) and script.pid in gate.ancestors(guard_by),
        "a take by a short process names the waiting script's shell, alive (%s, under %s)" % (guard_by, script.pid))
    check(not pre31_stale(entry), "older code skips it, 31 minutes old, while that script lives")
    subprocess.run(["taskkill", "/PID", str(guard_by), "/T", "/F"] if os.name == "nt" else ["kill", str(guard_by)],
        capture_output=True)
    script.kill()
    script.wait()
    time.sleep(0.5)
    check(entry and pre31_stale(entry), "and drops it once the script has died")
    if held_file("shortcall"):
        os.remove(gate._path("running", held_file("shortcall")))

    # release's case: a refused try against a held lock beats a suite_remote take.
    gate._write(gate._path("running", "probe-suite_remote-1.json"), {"tree": "probe", "kind": "suite_remote", "pid": None,
        "queued": time.time(), "started": time.time() - 600, "ram_gb": 1.7, "gpu": False, "watched": False})
    hold_lock("buildings", "734 amended (7): the temple furnished")
    code, said = try_lock("a landing")
    check(code == 1 and "beat" in (gate._read(gate._path("running", "probe-suite_remote-1.json")) or {}),
        "a refused try beats its tree's suite_remote take (release's case, 11-12) (%s)" % code)
    # A beat that fails is told, not dropped into /dev/null.
    lock_env["HEAVY_JOB_BEAT_BREAK"] = "1"
    code, said = try_lock("a landing")
    del lock_env["HEAVY_JOB_BEAT_BREAK"]
    with open(gate._path("heavy_jobs.log")) as handle:
        failed_beats = [line for line in handle if "\tbeat_failed\tprobe\t" in line]
    check(code == 1 and len(failed_beats) == 1 and "HEAVY_JOB_BEAT_BREAK" in failed_beats[0],
        "a failed beat is logged as beat_failed with its error (%s, %s)" % (code, failed_beats[:1]))
    shutil.rmtree(lock, ignore_errors=True)
    os.remove(gate._path("running", "probe-suite_remote-1.json"))
    try:
        os.remove(lock + ".log")
    except OSError:
        pass

print("== going past a bench that waits on a suite (backfill, 394 amended (18)) ==")
runs = {"suite": dict(table["suite"], runs_s=[450.0, 500.0, 460.0]), "suite_lean3": dict(table["suite_lean3"], runs_s=[1000.0]),
    "scene": dict(table["scene"], runs_s=[40.0, 70.0, 10.0]), "bench": dict(table["bench"], runs_s=[300.0])}
backfill_runs = runs
now = 10000.0
bench_queued = dict(table["bench"], kind="bench", tree="environment")
suite_at = lambda started, **more: dict(running(6, 6), kind="suite", started=started, **more)
scene_long = gate.backfill_length(runs["scene"])
check(scene_long == 87.5, "a scene counts on its longest run times 1.25: %s s" % scene_long)
check(gate.backfill_length(runs["scene"], expect_minutes=3) == 180.0, "or its --expect")
check(gate.backfill_length(dict(table["scene"], runs_s=[])) is None, "no runs recorded: none")
check(not gate.may_pass(scene_row, [bench_queued], [suite_at(now - 100)]),
    "without the kinds and the clock, the old rule: a scene never goes past a bench")
ok, past, why = gate.passes(scene_row, [bench_queued], [suite_at(now - 100)], 60.0, None, runs, now, scene_long)
check(ok and past and past[0]["due"] == now - 100 + 460.0, "a scene goes past a bench whose suite is due in 360 s")
check(gate.decide(scene_row, [suite_at(now - 100)], ok, 60.0, None)[0], "and starts beside the suite")
ok, _, why = gate.passes(scene_row, [bench_queued], [suite_at(now - 400)], 60.0, None, runs, now, scene_long)
check(not ok and "due in 60 s" in why, "not when it would still run as the suite ends (%s)" % why)
ok, _, why = gate.passes(scene_row, [bench_queued], [suite_at(now - 470)], 60.0, None, runs, now, scene_long)
check(not ok and "past its usual length" in why, "nor once the suite is past its median (%s)" % why)
ok, _, why = gate.passes(scene_row, [bench_queued], [suite_at(now - 100)], 60.0, None, {"scene": runs["scene"]}, now, scene_long)
check(not ok and "runs recorded" in why, "nor when the suite has no runs recorded (%s)" % why)
ok, _, why = gate.passes(scene_row, [bench_queued], [suite_at(now - 100)], 60.0, None, runs, now, None)
check(not ok, "nor a kind with no runs of its own")
ok, past, _ = gate.passes(scene_row, [bench_queued], [suite_at(now - 300, estimate="suite_lean3")], 60.0, None, runs, now, scene_long)
check(ok and past[0]["due"] == now + 700.0, "a lean suite's end from the lean runs")
# The bench waits on memory, not kind: first come first served still.
ok, _, _ = gate.passes(scene_row, [bench_queued], [], 60.0, None, runs, now, scene_long)
check(not ok, "a bench waiting on memory or the count lets nobody past")
check(not gate.passes(dict(table["bench"], kind="bench"), [bench_queued], [suite_at(now - 100)], 60.0, None, runs, now, 10.0)[0],
    "nor its own kind")
soak_at = dict(running(2, 2), kind="soak", started=now - 100)
ok, _, why = gate.passes(dict(table["suite"], kind="suite"), [bench_queued], [soak_at], 60.0, None, runs, now,
    gate.backfill_length(runs["suite"]))
check(not ok, "a suite behind a bench waiting on a soak (no soak runs) still waits (%s)" % why)
mesh_head = dict(table["trellis_mesh"], kind="trellis_mesh", ram_gb=1e12)
ok, _, _ = gate.passes(scene_row, [mesh_head, bench_queued], [suite_at(now - 100)], 60.0, None, runs, now, scene_long)
check(ok, "an out-of-reach head ahead is passed as before, the bench by backfill")
# 394 amended (21): a soak held only by the queue (behind a bench waiting on the
# suite) held every scene and import behind it, 2026-11-04 10:00.
soak_queued = dict(soak_row, tree="economy")
import_queued = dict(table["godot_import"], kind="godot_import")
ok, past, _ = gate.passes(scene_row, [bench_queued, soak_queued], [suite_at(now - 100)], 60.0, None, runs, now, scene_long)
check(ok and [each["kind"] for each in past] == ["bench"], "a scene goes past a soak the queue holds, the bench by backfill")
check(gate.may_pass(import_queued, [bench_queued, soak_queued], [suite_at(now - 100)], 60.0),
    "an import goes past both, without the clock")
check(not gate.passes(scene_row, [bench_queued, soak_queued, dict(runs["scene"], kind="scene", tree="items")], [suite_at(now - 100)], 60.0,
    None, runs, now, scene_long)[0], "a scene still waits behind a scene that may start")
check(gate.passes(scene_row, [bench_queued, soak_queued, dict(scene_row, tree="items", expect_s=900.0)], [suite_at(now - 100)], 60.0,
    None, runs, now, scene_long)[0], "but goes past one held only by its own length at the bench (394 amended (28))")
ok, _, _ = gate.passes(dict(soak_row, tree="b"), [bench_queued, soak_queued], [suite_at(now - 100)], 60.0, None, runs, now, 600.0)
check(not ok, "a second soak still waits behind the first")
check(not gate.passes(scene_row, [soak_queued], [], 60.0, None, runs, now, scene_long)[0],
    "a soak that may start (nothing ahead of it) holds those behind it as a head")
memory_head = dict(table["godot_import"], kind="godot_import", tree="maps")
check(not gate.passes(scene_row, [memory_head, bench_queued, soak_queued], [suite_at(now - 100)], 60.0, None, runs, now, scene_long)[0],
    "a head not held by kind holds everyone behind it, those it holds too")
check(not gate.passes(import_queued, [soak_queued, bench_queued], [suite_at(now - 100)], 60.0, None, runs, now, 60.0)[0],
    "a soak ahead of the bench may start: it is a head, not held")
check(gate.blockers(dict(table["bench"], kind="bench"), [suite_at(now), dict(running(1, 1), kind="godot_import")]) == [suite_at(now)],
    "a bench's blockers: the suite, not an import")
# 394 amended (22): an import beside three counted jobs, one at a time so.
import_now = dict(table["godot_import"], kind="godot_import")
three = [suite_at(now), dict(running(1, 1), kind="scene"), dict(running(1, 1), kind="scene")]
check(import_now.get("below_normal"), "an import runs below normal priority")
check(gate.decide(import_now, three, True, 60.0, None)[0], "an import starts beside a suite and two scenes")
check(not gate.decide(import_now, three + [dict(running(1, 1), kind="godot_import")], True, 60.0, None)[0],
    "but not beside another import left uncounted")
check(not gate.decide(scene_row, three[:2] + [dict(running(1, 1), kind="godot_import")] * 2, True, 60.0, None)[0],
    "a second import counts: a suite, a scene and two imports hold a scene out")
check(gate.decide(scene_row, three[:2] + [dict(running(1, 1), kind="godot_import")], True, 60.0, None)[0],
    "one import is not counted: a scene starts beside it, a suite and a scene")
check(not gate.decide(dict(table["godot_export"], kind="godot_export"), three, True, 60.0, None)[0],
    "an export still counts")

if os.name == "nt":
    probe = "import ctypes; k = ctypes.windll.kernel32; k.GetCurrentProcess.restype = ctypes.c_void_p; " \
        "raise SystemExit(0 if k.GetPriorityClass(ctypes.c_void_p(k.GetCurrentProcess())) == 0x4000 else 1)"
    check(gate.run("test", "soak", [sys.executable, "-c", probe]) == 0, "a soak runs below normal priority")
    check(gate.run("test", "scene", [sys.executable, "-c", probe]) == 0, "a scene runs below normal priority")
    check(gate.run("test", "suite", [sys.executable, "-c", probe]) == 1, "a suite does not")

code = gate.run("test", "suite", [sys.executable, "-c", "import time; time.sleep(1)"])
check(code == 0 and "last_peak_gb" in gate.kinds()["suite"], "run: the command's exit code, the kind's peak recorded")
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tdone\ttest\tsuite\t" in text and "\tstale\tgone\tbench\t" in text, "the log has the run and the stale entry")

if os.name == "nt":
    print("== what a run leaves running is stopped ==")
    pid_file = os.path.join(STATE, "orphan.pid")
    leave = ("import subprocess, sys; child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)']); "
        "open(sys.argv[1], 'w').write(str(child.pid))")
    gate.run("test", "bench", [sys.executable, "-c", leave, pid_file])
    orphan = int(open(pid_file).read())
    time.sleep(0.5)
    check(not gate.alive(orphan), "the command's own child, left behind when it exited, is stopped")

try:
    gate.take("nopid", "suite", 999999)
    check(False, "a take with a dead pid stops waiting")
except SystemExit as stop:
    check(stop.code == 3, "a take whose pid is no live process stops waiting at once (exit 3), not forever")

real_total = gate.total_ram_gb
gate.total_ram_gb = lambda: gate.kinds()["suite"]["ram_gb"] + gate.MARGIN_GB - 1.0
try:
    gate.take("huge", "suite", os.getpid())
    check(False, "a job bigger than the machine is refused")
except SystemExit as stop:
    check(stop.code == 4 and not gate._entries("queue"), "a job whose estimate and margin pass the machine's RAM is refused at once (exit 4), never queued")
gate.total_ram_gb = real_total

print("== a head out of reach keeps its place; jobs that fit go past it (a bug in 394 amended (28)) ==")
# 20:37 11-10: a model loaded outside the gate put every queued suite out of
# reach; each stepped to the back in the order its waiter looked, and the
# two queued first ended last. Now none steps: the blocked keep first-come
# order, and a job that fits starts past them.
import threading
gate.total_ram_gb = lambda: None
table = gate._read(gate._path("kinds.json")) or {}
saved_table = json.loads(json.dumps(table))
table["trellis_mesh"] = dict(gate.kinds()["trellis_mesh"], ram_gb=1e12, commit_gb=1e12)
table["soak"] = dict(gate.kinds()["soak"], ram_gb=0.1, commit_gb=0.1)
gate._write(gate._path("kinds.json"), table)
real_poll, gate.POLL_SECONDS = gate.POLL_SECONDS, 0.1
def wait_for(condition, seconds=60.0):
    # Polled, not slept: under a loaded landing a fixed wait was overrun
    # (release, art-kit's landing 2026-10-18).
    until = time.time() + seconds
    while not condition() and time.time() < until:
        time.sleep(0.05)
    return condition()
def queue_order():
    return [each["tree"] for each in gate._entries("queue")]
blocked = []
for name in ("physics", "items", "maps"):
    blocked.append(threading.Thread(target=lambda name=name: gate.take(name, "trellis_mesh", os.getpid()), daemon=True))
    blocked[-1].start()
    wait_for(lambda name=name: name in queue_order())
fits = threading.Thread(target=lambda: gate.take("small", "soak", os.getpid()), daemon=True)
fits.start()
check(wait_for(lambda: any(each["tree"] == "small" for each in gate._entries("running"))),
    "a job that fits starts past three out of reach: %s" % [each["tree"] for each in gate._entries("running")])
time.sleep(1.5)
with open(gate._path("heavy_jobs.log")) as log:
    asides = [line for line in log if "\taside\t" in line]
check(queue_order() == ["physics", "items", "maps"] and not asides,
    "the three out of reach keep first-come order, none stepped aside: %s %s" % (queue_order(), asides))
gate.release("small", "soak")
for each in gate._entries("queue"):
    gate._retried(os.remove, gate._path("queue", each["file"]))  # A waiter may hold it open a moment (Windows).
for each in blocked + [fits]:
    each.join(5)
gate._write(gate._path("kinds.json"), saved_table)
gate.POLL_SECONDS = real_poll
gate.total_ram_gb = real_total

print("== a run inside the tree's own take ==")
gate.take("lander", "suite", os.getpid())
gate.MAX_RUNNING = 0  # Were it to queue, it would never start.
code = gate.run("lander", "suite", [sys.executable, "-c", "x = bytearray(200 * 1024 * 1024); import time; time.sleep(5)"])
gate.MAX_RUNNING = 3
entries = gate._entries("running")
check(code == 0, "the run adopts the take instead of queueing behind it")
check(len(entries) == 1 and not entries[0].get("watched") and entries[0]["using_gb"] == 0.0,
    "the take is still held afterwards, owing its whole estimate again")
check(gate.release("lander", "suite") == 0, "and its holder releases it")
with open(gate._path("heavy_jobs.log")) as log:
    adopted = [line for line in log if "\tdone\tlander\tsuite\texit 0" in line]
check(adopted and float(adopted[0].split("peak ")[1].split(" GB")[0]) >= 0.15, "the run inside the take was measured: %s" % (
    adopted[0].strip() if adopted else "no line"))

print("== a suite out of reach runs lean (394 amended (9), (10)) ==")
full = dict(gate.KINDS["suite"], kind="suite", ram_gb=14.6, commit_gb=12.2, lean_first=False)
table = {"suite": full, "suite_lean3": dict(gate.KINDS["suite_lean3"], ram_gb=8.0, runs_s=[600.0])}
lean = gate.lean_row(table, "suite")
check(lean["kind"] == "suite" and lean["estimate"] == "suite_lean3" and lean["ram_gb"] == 8.0 and "lean" not in lean
    and lean["max_running"] == 1 and "bench" in lean["excludes"] and lean["runs_s"] == [600.0],
    "the lean row: a suite's caps and exclusions, the variant's estimate and runs")
check(gate.lean_row(dict(table, bench=dict(gate.KINDS["bench"])), "bench") is None, "a kind with no variant has no lean row")
saved_margins = gate.MARGIN_GB, gate.COMMIT_MARGIN_GB
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 8.0
after = gate.LEAN_AFTER_SECONDS
check(gate.goes_lean(full, lean, after, [], 18.3, 20.2), "maps' wait: 18.3 GB free, 14.6 + 8 out of reach, 8 + 8 in: lean")
check(not gate.goes_lean(full, lean, after - 1, [], 18.3, 20.2), "not before LEAN_AFTER_SECONDS")
check(not gate.goes_lean(full, lean, after, [], 30.0, 30.0), "nor when the full suite is in reach")
check(not gate.goes_lean(full, lean, after, [dict(running(14.6, 10.0), kind="suite")], 18.3, 20.2),
    "nor while a suite running will give its memory back (a wait on the gate, not outside it)")
check(not gate.goes_lean(full, lean, after, [], 12.0, 20.2), "nor when the lean one is out of reach too")
check(not gate.goes_lean(full, None, after, [], 18.3, 20.2), "nor with no lean variant")
first = dict(full, lean_first=True)
check(gate.goes_lean(first, lean, 0, [], 18.3, 20.2), "lean_first (394 amended (23)): lean at once when the full one is out of reach")
check(not gate.goes_lean(first, lean, 0, [], 30.0, 30.0), "lean_first: still full when the full one is in reach")
check(not gate.goes_lean(first, lean, 0, [], 12.0, 20.2), "lean_first: nor when the lean one is out of reach too")
check(gate.KINDS["suite"].get("lean_first") is True and gate.kinds()["suite"].get("lean_first") is True,
    "the suite is lean_first, over a kinds.json row written before it")
# Companions' lean take, judged by those behind it at the full suite's
# estimate, looked out of reach: sound's suite and then economy's went past
# it as each running suite ended (release, 2026-10-25; 394 amended (15)).
went_lean = {"kind": "suite", "estimate": "suite_lean3"}
check(gate.queued_row(table, went_lean, full)["ram_gb"] == 8.0, "a ticket that went lean is judged by the lean estimate")
check(gate.queued_row(table, {"kind": "suite"}, full)["ram_gb"] == 14.6 and gate.queued_row(table, {"kind": "suite", "estimate": "suite"}, full)["ram_gb"] == 14.6,
    "one that did not, by its kind's")
check(gate.queued_row(table, {"kind": "made_up"}, full)["kind"] == "made_up", "a kind the table lacks: the default row, its own kind")
behind_suite = dict(lean)
check(not gate.may_pass(behind_suite, [gate.queued_row(table, went_lean, full)], [], 18.3, 20.2),
    "a suite queued behind a lean suite in reach no longer goes past it")
check(not gate.may_pass(dict(gate.KINDS["bench"], kind="bench"), [gate.queued_row(table, went_lean, full)], [], 18.3, 20.2),
    "nor a bench")
check(gate.may_pass(behind_suite, [gate.queued_row(table, {"kind": "suite"}, full)], [], 18.3, 20.2),
    "as it did past the full suite, out of reach (the rule for a job held by memory outside the gate)")
check(not gate.decide(lean, [dict(running(1, 1), kind="bench")], True, 60.0, None)[0]
    and not gate.decide(lean, [dict(running(1, 1), kind="suite")], True, 60.0, None)[0],
    "a lean suite still never beside a bench or another suite")
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = saved_margins
# Through a take and a run, the full suite never in reach.
gate.total_ram_gb = lambda: None
saved_table = gate._read(gate._path("kinds.json"))
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=1e12, commit_gb=1e12)})
gate.LEAN_AFTER_SECONDS = 0
check(gate.take("thin", "suite", os.getpid()) == 0, "a take of a suite out of reach")
entries = gate._entries("running")
check(len(entries) == 1 and entries[0]["kind"] == "suite" and entries[0]["estimate"] == "suite_lean3"
    and entries[0]["ram_gb"] == gate.KINDS["suite_lean3"]["ram_gb"], "holds a suite, lean, at suite_lean3's estimate: %s" % entries)
check(gate.holds("thin", "suite"), "the tree holds a suite")
told = os.path.join(STATE, "kind.txt")
code = gate.run("thin", "suite", [sys.executable, "-c", "import os; open(%r, 'w').write(os.environ.get(%r, ''))" % (told, gate.KIND_ENV)])
check(code == 0 and open(told).read() == "suite_lean3", "a run inside the lean take tells its command HEAVY_JOB_KIND=suite_lean3")
check(gate.release("thin", "suite") == 0 and not gate._entries("running"), "released as a suite")
code = gate.run("thin2", "suite", [sys.executable, "-c", "import os; open(%r, 'w').write(os.environ.get(%r, ''))" % (told, gate.KIND_ENV)])
saved = gate._read(gate._path("kinds.json"))
check(code == 0 and open(told).read() == "suite_lean3", "a run of a suite out of reach runs lean")
check(len(saved.get("suite_lean3", {}).get("runs_s", [])) == 2 and saved["suite"]["ram_gb"] == 1e12 and not saved["suite"].get("runs_s"),
    "its time goes to suite_lean3's row, the full suite's left alone: %s" % saved)
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tlean\tthin2\tsuite\t" in text and ", lean" in text.split("\tdone\tthin2\tsuite\t")[1].split("\n")[0],
    "the log says it went lean, and its done line")
check(gate.main(["take", "x", "suite_lean3"]) == 2, "suite_lean3 is no kind to take or run itself")
# 394 amended (10): what held the memory at the peak, and the working set
# at once beside the sum of each process's own peak.
check(gate.short_command('"C:\\Users\\x\\Godot_console.exe" --log-file "C:\\a b\\x.log" --headless --path . --scene res://tests/view_test.tscn')
    == "Godot_console.exe --headless --scene res://tests/view_test.tscn", "a Godot's command line, short: %s" % gate.short_command(
    '"C:\\Users\\x\\Godot_console.exe" --log-file "C:\\a b\\x.log" --headless --path . --scene res://tests/view_test.tscn'))
if os.name == "nt":
    gate.PEAK_LIST_SECONDS = 0.0
    code = gate.run("lister", "bench", [sys.executable, "-c", "x = bytearray(300 * 1024 * 1024); import time; time.sleep(3)"])
    with open(gate._path("heavy_jobs.log")) as log:
        done = [line for line in log if "\tdone\tlister\tbench\t" in line]
    check(code == 0 and done and "working set at once" in done[0], "the done line has the working set at once: %s" % (done[0].strip() if done else "none"))
    kept = gate._path("peaks", "lister-bench.txt")
    text = open(kept).read() if os.path.exists(kept) else ""
    check("python" in text.lower() and "bytearray" in text, "the processes at the commit peak kept in peaks/: %s" % text.splitlines()[-1:])
    gate.PEAK_LIST_SECONDS = 15.0
gate.LEAN_AFTER_SECONDS = after
gate.total_ram_gb = real_total
if saved_table is None:
    os.remove(gate._path("kinds.json"))
else:
    gate._write(gate._path("kinds.json"), saved_table)

print("== a run adopts its own ancestor's take, whatever the names (394 amended (11)) ==")
# Maps landed from a side worktree, wt-umbrage, under a take as "maps":
# land.sh, named for its folder, queued behind its own take 29.6 minutes.
check(gate.ancestors(os.getpid())[0] == os.getpid(), "a process is first among its own ancestors")
import subprocess
sibling = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"])
gate.take("other", "suite", sibling.pid)
check(gate._adopt_take("wt-umbrage", "suite") == (None, None), "a take another process holds, under another name: not adopted")
gate.release("other", "suite")
sibling.kill()
sibling.wait()
gate.take("maps", "suite", os.getpid())
child = subprocess.run([sys.executable, "-c", "import sys; sys.dont_write_bytecode = True; sys.path.insert(0, %r); import heavy_job as gate; "
    "gate.POLL_SECONDS = 0.05; gate.WATCH_SECONDS = 0.2; "
    "sys.exit(gate.run('wt-umbrage', 'suite', [sys.executable, '-c', 'pass']))" % os.path.dirname(os.path.abspath(gate.__file__))],
    env=dict(os.environ), timeout=60, capture_output=True, text=True)
check(child.returncode == 0 and "inside this tree's take" in child.stderr,
    "a run in a child process, as wt-umbrage, adopts the parent's take as maps: %s" % child.stderr.strip()[-200:])
entries = gate._entries("running")
check(len(entries) == 1 and entries[0]["tree"] == "maps", "the take is still maps', its holder's to release")
gate.release("maps", "suite")

print("== the state lock denied a moment ==")
# Windows answers PermissionError, not FileExistsError, while the lock is
# being deleted by its holder: economy's waiter died of it and lost its place.
real_open, denials = os.open, [3]
def flaky_open(path, *rest):
    if path.endswith("state.lock") and denials[0] > 0:
        denials[0] -= 1
        raise PermissionError(13, "Permission denied", path)
    return real_open(path, *rest)
os.open = flaky_open
try:
    with gate.StateLock():
        locked = True
except PermissionError:
    locked = False
os.open = real_open
check(locked and denials[0] == 0, "a denied state lock is waited on, as a held one")

print("== a gated run inside a gated run ==")
# ui's bench script run through the gate, and frame_budget.ps1 inside it
# asking for a bench again: bench is at most 1, so it queued behind its own
# parent forever (2026-10-17, 13 jobs stuck behind it).
script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools", "heavy_job.py")
inner = ("import subprocess, sys; s = sys.argv[1]; py = sys.executable; "
    "t = subprocess.run([py, s, 'take', 'inner', 'suite']).returncode; "
    "r = subprocess.run([py, s, 'run', 'inner', 'bench', '--', py, '-c', 'raise SystemExit(7)'], timeout=60).returncode; "
    "g = subprocess.run([py, s, 'release', 'inner', 'suite']).returncode; "
    "sys.exit(r if t == 0 and g == 0 else 1)")
code = gate.run("outer", "bench", [sys.executable, "-c", inner, script])
check(code == 7, "the inner run goes straight through, its exit code back (got %s)" % code)
check(not gate._entries("running") and not gate._entries("queue"), "nothing left held or queued after")
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tnested\tinner\tbench\tinside outer bench" in text, "the log says it ran inside the outer run")

print("== a run's limit ==")
check(gate.limit_seconds({"max_minutes": 90}) == 5400.0, "no runs recorded: the kind's max_minutes")
check(gate.limit_seconds({"runs_s": [100.0, 120.0, 90.0]}) == gate.OVERRUN_FLOOR_SECONDS, "short runs: the floor")
check(gate.limit_seconds({"runs_s": [1000.0, 1200.0, 900.0, 5000.0]}) == 3 * 1100.0, "3x the median of the runs")
check(gate.limit_seconds({"runs_s": [100.0], "max_minutes": 90}, expect_minutes=600) == 36000.0, "--expect over all")
check(gate.limit_seconds({}) is None, "a kind with neither: no limit")
window = gate.HUNG_SECONDS
check(gate.hung([(0.0, 0.0), (window, 1.0)], window, 0.0)[0], "1 s of CPU in the window: hung")
check(not gate.hung([(0.0, 0.0), (window, 0.2 * window)], window, 0.0)[0], "a fifth of a core (npc's soak): not hung")
check(not gate.hung([(0.0, 0.0), (window - 1, 0.0)], window - 1, 0.0)[0], "not before the window has run")

print("== a run over its limit, hung, or busy ==")
sleeper = [sys.executable, "-c", "import time; time.sleep(60)"]
began = time.time()
code = gate.run("slow", "bench", sleeper, expect_minutes=0.05)
check(code == gate.STOPPED_CODE and time.time() - began < 30, "over its --expect: stopped, exit 5 (got %s after %.0f s)" % (
    code, time.time() - began))
check(not gate._entries("running"), "and nothing left held")
real_window, gate.HUNG_SECONDS = gate.HUNG_SECONDS, 4.0
began = time.time()
code = gate.run("idle", "bench", sleeper)
check(code == gate.STOPPED_CODE and time.time() - began < 30, "idle the whole window: stopped as hung, exit 5 (got %s after %.0f s)" % (
    code, time.time() - began))
# A wider window for the busy one: a 4 s window can be mostly the child's
# own start on a loaded machine (lore's landing beside an import, 688 s,
# 2026-10-21: stopped as hung with nothing wrong).
gate.HUNG_SECONDS = 10.0
code = gate.run("busy", "bench", [sys.executable, "-c", "import time\nend = time.time() + 20\nwhile time.time() < end: pass"])
check(code == 0, "busy the whole window: left to finish (got %s)" % code)
gate.HUNG_SECONDS = real_window
runs = gate.kinds()["bench"].get("runs_s", [])
check(runs and runs[-1] >= 19.0, "a clean run's time recorded for the kind's limit: %s" % runs)
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\toverrun\tslow\tbench\t" in text and "\thung\tidle\tbench\t" in text, "the log says overrun and hung")
busy = [line.split("\t")[1] for line in text.splitlines() if "\tbusy\tbench\t" in line]
check("overrun" not in busy and "hung" not in busy, "and the busy one neither: %s" % busy)

print("== RAM and commit told apart ==")
# What a GPU job puts on the card is charged to commit with no RAM behind it:
# trellis_mesh's 28.9 GB, one figure, held it out of reach of 32 GB free.
margins = gate.MARGIN_GB, gate.COMMIT_MARGIN_GB
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 8.0
mesh = {"kind": "trellis_mesh", "ram_gb": 9.0, "commit_gb": 28.9, "gpu_gb": 23.6, "gpu": True}
check(gate.decide(mesh, [], True, 32.0, 30.0, 40.0) == (True, ""), "RAM checked on RAM, commit on commit: it starts")
ok, why = gate.decide(mesh, [], True, 32.0, 30.0, 34.7)
check(not ok and why.startswith("commit:"), "short of commit, it waits on commit: %s" % why)
check(not gate.out_of_reach(mesh, [], 32.0, 40.0) and gate.out_of_reach(mesh, [], 32.0, 30.0), "out of reach by commit alone")
holding = [{"kind": "trellis_mesh", "ram_gb": 9.0, "commit_gb": 28.9, "gpu": True, "using_gb": 5.0, "using_commit_gb": 27.0}]
check(abs(gate.reserved_commit_gb(holding) - 1.9) < 1e-6 and gate.reserved_gb(holding) == 4.0, "owed: each by its own use")
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = margins
old = {"ram_gb": 28.86, "gpu_gb": 23.56, "gpu": True}
check(gate._split(dict(old), 9.0) == dict(old, ram_gb=9.0, commit_gb=28.86), "an old GPU row: its figure is commit, RAM back to its first")
check(gate._split({"ram_gb": 9.9, "gpu": False}, 6.5) == {"ram_gb": 9.9, "commit_gb": 9.9, "gpu": False}, "an old CPU row: both the same")
code = gate.run("mem", "godot_import", [sys.executable, "-c", "x = bytearray(300 * 1024 * 1024); import time; time.sleep(3)"])
row = gate.kinds()["godot_import"]
check(code == 0 and row.get("last_peak_gb", 0) >= 0.25 and row.get("last_commit_gb", 0) >= 0.25,
    "a run measures both: RAM %s, commit %s" % (row.get("last_peak_gb"), row.get("last_commit_gb")))

print("== a scene that died at launch ==")
# Decision 530: tests/run.sh notes each in the gate's log, and the summary counts them.
check(gate.main(["note", "suite", "stopped", "x"]) == 2, "note takes only its own events")
check(gate.main(["note", "suite", "launch", "items_test", "exit", "127", "at", "launch"]) == 0, "a launch failure noted")
with open(os.path.join(STATE, "heavy_jobs.log")) as handle:
    noted = [line for line in handle if "\tlaunch\tsuite\tsuite\t" in line]
check(len(noted) == 1 and "items_test exit 127 at launch; free RAM" in noted[0], "logged with free RAM and commit: %s" % noted)
shown = io.StringIO()
with contextlib.redirect_stdout(shown):
    gate.summary(datetime.date.today().isoformat())
check("launch: items_test" in shown.getvalue() and "1 launch" in shown.getvalue(), "the summary lists and counts it")
# 530 amended: a crash at launch carries its top frame and backtrace, and the
# summary groups crashes by top frame, the backtrace left in the log.
for scene in ("anim_rig_test", "view_test"):
    gate.main(["note", "suite", "launch", scene, "exit 139 at launch; crashed (Program crashed with signal 11) at main+40d4d61;",
        "backtrace: main+40d4d61 main+61555f"])
shown = io.StringIO()
with contextlib.redirect_stdout(shown):
    gate.summary(datetime.date.today().isoformat())
check("launch crashes by top frame: main+40d4d61 2" in shown.getvalue() and "3 launch" in shown.getvalue()
    and "backtrace:" not in shown.getvalue(), "crashes grouped by top frame, the backtrace kept to the log: %s" % shown.getvalue().splitlines()[-1])

print("== a child's exit code as a shell sees it ==")
# A killed Git Bash hands Windows its wait status (signal 9: 2304), which a
# shell reads modulo 256 as 0: economy's landing pushed over a killed suite
# (2026-10-23). run returns 128 + the signal, never 0 for a failure.
check([gate.shell_code(c) for c in (0, 1, 5, 137, 255)] == [0, 1, 5, 137, 255], "0 to 255 as they are")
check(gate.shell_code(2304) == 137 and gate.shell_code(15 << 8) == 143, "a signal's wait status: 128 + the signal")
check(all(gate.shell_code(c) != 0 for c in (256, 512, -1073741510, -1)), "any other out of range: never 0")
code = gate.run("killed", "suite", [sys.executable, "-c", "import sys; sys.exit(2304)"])
check(code == 137, "run hands on 137 for a child that exited 2304 (%s)" % code)

print("== backfill through the queue (394 amended (18)) ==")
import subprocess
real_poll, gate.POLL_SECONDS = gate.POLL_SECONDS, 0.1
real_total, gate.total_ram_gb = gate.total_ram_gb, lambda: None
gate._write(gate._path("kinds.json"), backfill_runs)
for folder in ("queue", "running"):
    for each in gate._entries(folder):
        gate._retried(os.remove, gate._path(folder, each["file"]))
# A suite's take running 100 s, a bench queued behind it by a live waiter.
gate._write(gate._path("running", "land-suite-%d.json" % os.getpid()), {"tree": "land", "kind": "suite", "pid": os.getpid(),
    "pid_since": gate.started_at(os.getpid()), "started": time.time() - 100, "queued": time.time() - 100, "ram_gb": 0.1, "gpu": False, "using_gb": 0.1,
    "watched": False})
gate._write(gate._path("queue", "%019d-environment-1.json" % time.time_ns()), {"tree": "environment", "kind": "bench", "pid": None,
    "waiter": os.getpid(), "waiter_since": gate.started_at(os.getpid()), "queued": time.time()})
started = time.time()
code = gate.run("ui", "scene", [sys.executable, "-c", "pass"])
check(code == 0 and time.time() - started < 30, "a scene runs at once past the bench (%.0f s)" % (time.time() - started))
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tbackfill\tui\tscene\tpast environment bench, waiting on suite due in " in text, "the log says so")
for each in gate._entries("queue"):
    gate._retried(os.remove, gate._path("queue", each["file"]))  # A waiter may hold it open a moment (Windows).
os.remove(gate._path("running", "land-suite-%d.json" % os.getpid()))
# A backfilled scene still running when the suite has gone: the bench's wait
# from then is logged as late.
child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(6)"])
gate._write(gate._path("running", "ui-scene-%d.json" % child.pid), {"tree": "ui", "kind": "scene", "pid": child.pid,
    "pid_since": gate.started_at(child.pid), "started": time.time(), "queued": time.time() - 100, "ram_gb": 0.1, "gpu": False, "using_gb": 0.1,
    "watched": False, "backfill": {"past": "environment bench", "due": time.time() - 1}})
shown = io.StringIO()
with contextlib.redirect_stdout(shown):
    gate.status()
check("(went past environment bench, due by " in shown.getvalue(), "status shows it: %s" % shown.getvalue().splitlines()[1:2])
gate.take("environment", "bench", os.getpid())
child.wait()
gate.release("environment", "bench")
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tbackfill_late\tenvironment\tbench\twaited " in text, "the bench's wait on it logged as late")
started_line = [line for line in text.splitlines() if "\tstart\tenvironment\tbench\t" in line]
check(started_line and "first in the queue)" in started_line[-1], "its start says how long it was first in the queue: %s" % started_line[-1:])
# A job behind the head while a backfilled scene holds them both: those
# minutes are the head's, never logged as late again (only the head's own
# wait). The scene ends before the head goes; before, it was logged late.
child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(3)"])
gate._write(gate._path("running", "ui-scene-%d.json" % child.pid), {"tree": "ui", "kind": "scene", "pid": child.pid,
    "pid_since": gate.started_at(child.pid), "started": time.time(), "queued": time.time() - 100, "ram_gb": 0.1, "gpu": False, "using_gb": 0.1,
    "watched": False, "backfill": {"past": "environment bench", "due": time.time() - 1}})
first = "%019d-front-1.json" % time.time_ns()
gate._write(gate._path("queue", first), {"tree": "front", "kind": "bench", "pid": None,
    "waiter": os.getpid(), "waiter_since": gate.started_at(os.getpid()), "queued": time.time()})
threading = __import__("threading")
# The head leaves once the scene has ended, not at a fixed time: under load the
# scene's python took longer to start than a 5 s timer allowed, the head left
# while the scene still held "behind", and its wait was logged late (terrain's
# landing, 11-12 10:51; release's report).
def head_leaves(scene=child):
    scene.wait()
    time.sleep(1.0)
    gate._retried(os.remove, gate._path("queue", first))
threading.Thread(target=head_leaves).start()
gate.take("behind", "bench", os.getpid())
child.wait()
gate.release("behind", "bench")
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tbackfill_late\tbehind\tbench\t" not in text, "a job behind the head held by it too: not logged late")
shown = io.StringIO()
with contextlib.redirect_stdout(shown):
    gate.summary(datetime.date.today().isoformat())
check("1 backfill, 1 late (" in shown.getvalue(), "the summary counts both: %s" % [line for line in shown.getvalue().splitlines() if "late" in line])
gate.POLL_SECONDS = real_poll
gate.total_ram_gb = real_total
os.remove(gate._path("kinds.json"))

print("== a take's own processes, and kinds never measured (394 amended (20)) ==")
# comfy_batch is only ever taken, so never measured: its first 6 GB stood for
# its commit while its ComfyUI server used up the machine's (2026-11-04).
if os.path.exists(gate._path("kinds.json")):
    os.remove(gate._path("kinds.json"))
fresh = gate.kinds()
check(fresh["comfy_batch"]["commit_gb"] == 20.0, "comfy_batch's commit estimate before any measure: 20 GB")
check(fresh["godot_export"]["commit_gb"] == 2 * gate.KINDS["godot_export"]["ram_gb"], "an unmeasured kind: commit at twice its RAM")
gate._write(gate._path("kinds.json"), {"godot_export": dict(gate.KINDS["godot_export"], ram_gb=2.5, commit_gb=2.6)})
check(gate.kinds()["godot_export"]["commit_gb"] == 2.6, "a measured one: its own")
gate._write(gate._path("kinds.json"), {"godot_export": {"ram_gb": 2.5, "gpu_gb": 0.0, "gpu": False}})
check(gate.kinds()["godot_export"]["commit_gb"] == 2.5, "an old measured row without commit: as before (_split)")
os.remove(gate._path("kinds.json"))
# measure_attached with made-up numbers: sums now, peaks kept, a gone one nothing.
me = {"pid": os.getpid(), "since": gate.started_at(os.getpid())}
entry = {"attached": [dict(me), {"pid": 99999999, "since": 1}]}
numbers = {os.getpid(): (1.0, 3.0, 1.5, 4.0)}
check(gate.measure_attached(entry, lambda pid: numbers.get(pid)) and entry["using_gb"] == 1.0 and entry["using_commit_gb"] == 3.0
    and entry["attached_peak_commit_gb"] == 4.0, "attached: its use now and its peak (%s)" % entry)
numbers[os.getpid()] = (0.5, 1.0, 1.5, 4.0)
gate.measure_attached(entry, lambda pid: numbers.get(pid))
check(entry["using_commit_gb"] == 1.0 and entry["attached_peak_commit_gb"] == 4.0, "falls with it, the peak kept")
check(not gate.measure_attached({}, lambda pid: None), "an entry with nothing attached: untouched")
# Through take, attach and release: a child holding about 300 MB.
import subprocess
holder = subprocess.Popen([sys.executable, "-c", "import time; block = bytearray(300 * 1024 * 1024); time.sleep(30)"])
time.sleep(2)
check(gate.main(["attach", "art", "godot_export", "--pid", str(holder.pid)]) == 1, "attach with no take: refused")
gate.take("art", "godot_export", os.getpid())
check(gate.main(["attach", "art", "godot_export", "--pid", str(holder.pid)]) == 0, "attach to the take")
with gate.StateLock():
    held = [each for each in gate._entries("running") if each["tree"] == "art"]
check(len(held) == 1 and held[0].get("using_commit_gb", 0.0) >= 0.25, "the take's use is the attached child's: %.2f GB commit" % (
    held[0].get("using_commit_gb", 0.0) if held else -1))
check(gate.reserved_commit_gb(held) < gate.commit_of(held[0]), "and what it is owed shrinks by it")
holder.kill()
holder.wait()
gate.release("art", "godot_export")
row = gate.kinds()["godot_export"]
check(row.get("last_commit_gb", 0.0) >= 0.25 and row["commit_gb"] >= 0.25, "release records the attached peak as the kind's: %s" % row.get("last_commit_gb"))
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tattach\tart\tgodot_export\tpid " in text and "attached peak " in text, "the log has the attach and the peak")
if os.path.exists(gate._path("kinds.json")):  # Not there when the attach failed: the FAILs above say why.
    os.remove(gate._path("kinds.json"))

print("== a waiter re-reads its estimate at every look (394 amended (24)) ==")
import threading
real_memory, real_total_ram, real_poll = gate._memory, gate.total_ram_gb, gate.POLL_SECONDS
real_margins = gate.MARGIN_GB, gate.COMMIT_MARGIN_GB
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 4.0  # The real ones: this part is about room (earlier parts set none).
gate._memory = lambda: (40.0, 40.0)
gate.total_ram_gb = lambda: None
gate.POLL_SECONDS = 0.05
for each in gate._entries("queue") + gate._entries("running"):
    folder = "running" if os.path.exists(gate._path("running", each["file"])) else "queue"
    os.remove(gate._path(folder, each["file"]))
def owed_job(tree, kind, ram):
    # Running, owed all of [ram] (nothing used yet): 40 GB free, 15 owed, 25 to give.
    gate._write(gate._path("running", "%s-%s-%d.json" % (tree, kind, os.getpid())), {"tree": tree, "kind": kind,
        "pid": os.getpid(), "pid_since": gate.started_at(os.getpid()), "queued": time.time(), "started": time.time(),
        "ram_gb": ram, "commit_gb": ram, "gpu": False, "using_gb": 0.0, "using_commit_gb": 0.0, "watched": True})
def until(condition, seconds=30.0):
    end = time.time() + seconds
    while not condition() and time.time() < end:
        time.sleep(0.05)
    return condition()
def trees(folder):
    return [each["tree"] for each in gate._entries(folder)]
saved_kinds = gate._read(gate._path("kinds.json"))
gate._write(gate._path("kinds.json"), {"scene": dict(gate.KINDS["scene"], ram_gb=20.0, commit_gb=1.0)})
owed_job("held", "godot_import", 15.0)
waiter = threading.Thread(target=lambda: gate.take("late", "scene", os.getpid()), daemon=True)
waiter.start()
until(lambda: trees("queue") == ["late"])
time.sleep(0.5)
check(trees("queue") == ["late"], "queued under a 20 GB estimate, 25 GB to give: it waits (%s)" % trees("queue"))
gate._write(gate._path("kinds.json"), {"scene": dict(gate.KINDS["scene"], ram_gb=2.0, commit_gb=1.0)})
check(until(lambda: "late" in trees("running")), "the estimate falls to 2 GB: the same waiter starts, not requeued (%s)" % trees("running"))
waiter.join(5)
gate.release("late", "scene")
# A suite first in the queue waits on memory the running job will give back (25 + 8 wanted, 25 to give):
# the scene behind it, in reach, never goes past it.
gate._write(gate._path("kinds.json"), {"scene": dict(gate.KINDS["scene"], ram_gb=2.0, commit_gb=1.0),
    "suite": dict(gate.KINDS["suite"], ram_gb=25.0, commit_gb=1.0, lean_first=False)})
gate._write(gate._path("queue", "%019d-first-%d.json" % (time.time_ns(), os.getpid())), {"tree": "first", "kind": "suite",
    "pid": None, "waiter": os.getpid(), "waiter_since": gate.started_at(os.getpid()), "queued": time.time()})
behind = threading.Thread(target=lambda: gate.take("behind", "scene", os.getpid()), daemon=True)
behind.start()
until(lambda: trees("queue") == ["first", "behind"])
time.sleep(1.0)
check(trees("queue") == ["first", "behind"] and "behind" not in trees("running"),
    "a scene behind a suite waiting on memory stays behind it: the suite is never delayed (%s)" % trees("queue"))
for each in gate._entries("queue") + gate._entries("running"):
    folder = "running" if os.path.exists(gate._path("running", each["file"])) else "queue"
    os.remove(gate._path(folder, each["file"]))
behind.join(5)
check(gate.run("phys", "scene", ["bash", "tests/net_test.sh"]) == 2 and not trees("queue"),
    "net_test under scene: refused before it queues (run it as net)")
check([gate.many_godot_test(each) for each in (["powershell", "-File", "tests\\net_test.ps1"],
    ["godot", "--scene", "res://tests/net_test.tscn"], ["sh", "-c", "sh tests/net_test.sh x"])] == ["net_test"] * 3,
    "net_test named by its file, any path or quoting")
check(gate.many_godot_test(["godot", "--path", ".", "--scene", "tests/free_net_test.tscn"]) is None
    and gate.many_godot_test(["godot", "--scene", "tests/net_test_x.tscn"]) is None,
    "a name it is part of is no match (combat's free_net_test, a single Godot, 11-10)")
check("net" in gate.kinds() and gate.kinds()["net"]["max_running"] == 1 and "bench" in gate.kinds()["net"]["excludes"],
    "net, a kind of its own: one at a time, never beside a bench")
gate._memory, gate.total_ram_gb, gate.POLL_SECONDS = real_memory, real_total_ram, real_poll
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = real_margins
if saved_kinds is not None:
    gate._write(gate._path("kinds.json"), saved_kinds)
elif os.path.exists(gate._path("kinds.json")):
    os.remove(gate._path("kinds.json"))

print("== release moves one queued entry to the front (394 amended (25)) ==")
gate._memory = lambda: (40.0, 40.0)
gate.total_ram_gb = lambda: None
gate.POLL_SECONDS = 0.05
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 4.0
saved_kinds = gate._read(gate._path("kinds.json"))
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=2.0, commit_gb=1.0, lean_first=False),
    "bench": dict(gate.KINDS["bench"], ram_gb=2.0, commit_gb=1.0)})
def clear_gate():
    for each in gate._entries("queue") + gate._entries("running"):
        folder = "running" if os.path.exists(gate._path("running", each["file"])) else "queue"
        gate._retried(os.remove, gate._path(folder, each["file"]))
def queued(tree, kind, waiter=True):
    name = "%019d-%s-%d.json" % (time.time_ns(), tree, os.getpid())
    entry = {"tree": tree, "kind": kind, "pid": None, "queued": time.time()}
    if waiter:
        entry.update(waiter=os.getpid(), waiter_since=gate.started_at(os.getpid()))
    gate._write(gate._path("queue", name), entry)
    time.sleep(0.01)
    return name
def queue_of():
    return ["%s %s" % (each["tree"], each["kind"]) for each in gate._entries("queue")]
clear_gate()
queued("art", "suite")
queued("ui", "bench")
late = queued("fix", "suite")
check(gate.main(["front", "fix", "suite", "--by", "perf", "--why", "mine"]) == 2 and queue_of()[-1] == "fix suite",
    "front by another tree: refused, nothing moved (%s)" % queue_of())
check(gate.main(["front", "fix", "suite", "--by", "release"]) == 2, "front with no --why: refused")
check(gate.main(["front", "nobody", "suite", "--by", "release", "--why", "x"]) == 3, "front of an entry not queued: refused")
check(gate.main(["front", "fix", "suite", "--by", "release", "--why", "view_test's back step fails every landing"]) == 0
    and queue_of() == ["fix suite", "art suite", "ui bench"], "release fronts it: first among the waiters (%s)" % queue_of())
check(os.path.exists(gate._path("queue", late)), "its ticket keeps its name: its waiter still finds it")
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tfront\tfix\tsuite\tby release, why: view_test's back step fails every landing; jumped: art suite, ui bench" in text,
    "the log has who fronted it, why, and whom it jumped")
check("\trefused\tfix\tsuite\tfront by perf" in text, "and the refused front")
queued("other", "suite")
check(gate.main(["front", "other", "suite", "--by", "release", "--why", "y"]) == 3 and queue_of()[-1] == "other suite",
    "a second front while the first still waits: refused")
out = io.StringIO()
with contextlib.redirect_stdout(out):
    gate.summary(datetime.date.today().isoformat())
check("fix suite front: by release, why: view_test's back step" in out.getvalue(), "the day's summary lists the front")
clear_gate()
queued("art", "suite")
queued("ghost", "suite", waiter=False)
check(gate.main(["front", "ghost", "suite", "--by", "release", "--why", "z"]) == 3 and queue_of()[0] == "art suite",
    "an entry with no live waiter: refused, nothing moved")
# The coordinator's case: a suite running and a bench queued ahead. The fronted suite never starts
# beside the running one nor slips the suite/bench exclusion, and the bench it passed still runs.
clear_gate()
owed_job("main", "suite", 2.0)
bench = threading.Thread(target=lambda: gate.take("ui", "bench", os.getpid()), daemon=True)
bench.start()
until(lambda: queue_of() == ["ui bench"])
landing = threading.Thread(target=lambda: gate.take("fix", "suite", os.getpid()), daemon=True)
landing.start()
until(lambda: queue_of() == ["ui bench", "fix suite"])
check(gate.main(["front", "fix", "suite", "--by", "release", "--why", "every landing pays for it"]) == 0
    and queue_of() == ["fix suite", "ui bench"], "fronted past the bench (%s)" % queue_of())
time.sleep(1.0)
check(trees("running") == ["main"], "a suite running: the fronted suite waits for it (suite at most 1), the bench too (%s)" % trees("running"))
for each in gate._entries("running"):
    os.remove(gate._path("running", each["file"]))
check(until(lambda: trees("running") == ["fix"]), "the running suite done: the fronted one starts (%s)" % trees("running"))
time.sleep(0.5)
check(trees("running") == ["fix"] and queue_of() == ["ui bench"], "the bench never beside it (%s, %s)" % (trees("running"), queue_of()))
landing.join(5)
gate.release("fix", "suite")
check(until(lambda: trees("running") == ["ui"]), "the suite released: the bench it passed runs (%s)" % trees("running"))
bench.join(5)
gate.release("ui", "bench")
clear_gate()
gate._memory, gate.total_ram_gb, gate.POLL_SECONDS = real_memory, real_total_ram, real_poll
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = real_margins
if saved_kinds is not None:
    gate._write(gate._path("kinds.json"), saved_kinds)
elif os.path.exists(gate._path("kinds.json")):
    os.remove(gate._path("kinds.json"))

print("== status says why each row waits, and what each running job is owed (394 amended (26)) ==")
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 4.0
gate.total_ram_gb = lambda: None
saved_kinds = gate._read(gate._path("kinds.json"))
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=18.0, commit_gb=1.0, lean_first=False),
    "scene": dict(gate.KINDS["scene"], ram_gb=1.3, commit_gb=1.0)})
clear_gate()
owed_job("builder", "suite", 18.0)  # Owed all 18 GB: 26 free, 8 to give.
queued("items", "scene")
queued("npc", "scene")
queued("import", "godot_import")
def status_lines(free):
    gate._memory = lambda: (free, free)
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        gate.status()
    return out.getvalue().splitlines()
lines = status_lines(26.0)
check(lines[0].endswith("; owed to running jobs: RAM 18.0 GB, commit 18.0 GB"), "the first line ends with what is owed: %s" % lines[0])
check(lines[1].startswith("running builder suite, ") and lines[1].endswith("; owed 18.0 GB"), "a running job's line ends with its owed: %s" % lines[1])
check(lines[2].startswith("queued items scene, ") and "; waits: " in lines[2] and "wanted" in lines[2],
    "the head waits on memory, saying so: %s" % lines[2])
check(lines[3].startswith("queued npc scene, ") and "; waits: behind the head, items scene, which waits on: " in lines[3],
    "the scene behind it: behind that head: %s" % lines[3])
check(lines[4].startswith("queued import godot_import, ") and "; waits: behind the head" in lines[4],
    "and the import behind a head waiting on memory (first come for memory): %s" % lines[4])
lines = status_lines(40.0)
check(lines[2].endswith("; may start at its next look"), "with room, the head may start: %s" % lines[2])
reasons = gate.queue_reasons(gate._entries("queue"), gate._entries("running"), 26.0, 26.0, None)
check(len(reasons) == 3 and reasons[0].startswith("waits: "), "queue_reasons, read only: %s" % reasons)
check([each["tree"] for each in gate._entries("queue")] == ["items", "npc", "import"], "status moved nothing")
clear_gate()
gate._memory, gate.total_ram_gb = real_memory, real_total_ram
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = real_margins
if saved_kinds is not None:
    gate._write(gate._path("kinds.json"), saved_kinds)
elif os.path.exists(gate._path("kinds.json")):
    os.remove(gate._path("kinds.json"))

print("== a long --expect scene behind a bench holds no shorter scene (394 amended (28)) ==")
# 11-10: playtest's tour (--expect 25) behind terrain's bench while suites ran
# back to back: it could never go past the bench, and those behind judged it by
# the scene kind's runs, saw it free to go, and waited behind it 84 minutes.
check(gate.backfill_length(dict(gate.KINDS["scene"], runs_s=[100.0], expect_s=1500.0)) == 1500.0,
    "a row from a queue entry counts on its waiter's --expect")
check(gate.backfill_length(dict(gate.KINDS["scene"], runs_s=[100.0], expect_s=1500.0), expect_minutes=2) == 120.0,
    "its own waiter's --expect first")
now = 10000.0
short_row = dict(gate.KINDS["scene"], kind="scene")
suite_on = dict(running(6, 6), kind="suite", started=now - 30)
long_runs = {"suite": dict(gate.KINDS["suite"], runs_s=[800.0]), "scene": dict(gate.KINDS["scene"], runs_s=[100.0]),
    "bench": dict(gate.KINDS["bench"], runs_s=[300.0])}
bench_ahead = dict(gate.KINDS["bench"], kind="bench", tree="terrain")
tour = dict(short_row, tree="playtest", expect_s=1500.0)
ok, _, why, holder = gate.passes_held(tour, [bench_ahead], [suite_on], 60.0, None, long_runs, now, gate.backfill_length(tour))
check(not ok and holder == 0 and "needs 1500 s" in why, "the tour may not go past the bench: %s" % why)
ok, past, _, holder = gate.passes_held(short_row, [bench_ahead, tour], [suite_on], 60.0, None, long_runs, now, 125.0)
check(ok and holder is None and [each["kind"] for each in past] == ["bench"],
    "a short scene behind it goes past both, the bench by backfill")
two_scenes = [suite_on, dict(running(1, 1), kind="scene", started=now), dict(running(1, 1), kind="scene", started=now)]
ok, _, _, holder = gate.passes_held(short_row, [bench_ahead, tour], two_scenes, 60.0, None, long_runs, now, 125.0)
check(not ok and holder == 1, "with two scenes running the tour waits on its kind: it holds the scene behind it")
check(not gate.passes(short_row, [dict(short_row, tree="a")], [dict(running(1, 1), kind="scene")] * 2, 60.0, None,
    long_runs, now, 125.0)[0], "a scene waiting on the cap holds the same kind, as before")
# The same through the waiters: a suite running, a bench queued, the tour, three short scenes.
gate._memory = lambda: (40.0, 40.0)
gate.total_ram_gb = lambda: None
gate.POLL_SECONDS = 0.05
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 4.0
saved_kinds = gate._read(gate._path("kinds.json"))
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=6.0, commit_gb=1.0, lean_first=False, runs_s=[800.0]),
    "scene": dict(gate.KINDS["scene"], ram_gb=1.0, commit_gb=1.0, runs_s=[100.0]),
    "bench": dict(gate.KINDS["bench"], ram_gb=2.0, commit_gb=1.0, runs_s=[300.0])})
clear_gate()
gate._write(gate._path("running", "physics-suite-%d.json" % os.getpid()), {"tree": "physics", "kind": "suite",
    "pid": os.getpid(), "pid_since": gate.started_at(os.getpid()), "queued": time.time() - 60, "started": time.time() - 30,
    "ram_gb": 6.0, "commit_gb": 1.0, "gpu": False, "using_gb": 6.0, "using_commit_gb": 1.0, "watched": True})
queued("terrain", "bench")
long_waiter = threading.Thread(target=lambda: gate.wait_turn("playtest", "scene", os.getpid(), False, 25), daemon=True)
long_waiter.start()
until(lambda: queue_of() == ["terrain bench", "playtest scene"])
entry = [each for each in gate._entries("queue") if each["tree"] == "playtest"]
check(entry and entry[0].get("expect_s") == 1500.0, "the tour's queue entry carries its --expect (%s)" % entry)
shorts = []
for name in ("ea1", "ea2", "ea3"):
    shorts.append(threading.Thread(target=lambda name=name: gate.take(name, "scene", os.getpid()), daemon=True))
    shorts[-1].start()
    until(lambda name=name: name in trees("queue") + trees("running"))
check(until(lambda: sorted(trees("running")) == ["ea1", "ea2", "physics"]),
    "beside the suite, the first two short scenes run past the bench and the tour (%s)" % trees("running"))
time.sleep(0.5)
check(queue_of() == ["terrain bench", "playtest scene", "ea3 scene"], "the tour and the third wait (%s)" % queue_of())
lines = status_lines(40.0)
tour_line = [each for each in lines if each.startswith("queued playtest scene")]
check(tour_line and "; waits: behind the head, terrain bench, which waits on: " in tour_line[0]
    and "; going past it needs 1500 s" in tour_line[0], "status names the bench as what holds the tour, and why: %s" % tour_line)
third = [each for each in lines if each.startswith("queued ea3 scene")]
check(third and "; waits: behind playtest scene (2nd in the queue), which waits on: " in third[0],
    "the third waits on the tour (three jobs running, two of them scenes): %s" % third)
gate.release("ea1", "scene")
check(until(lambda: "ea3" in trees("running")), "a scene done: the third starts, the tour still waits (%s)" % trees("running"))
check(queue_of() == ["terrain bench", "playtest scene"], "(%s)" % queue_of())
gate.release("ea2", "scene")
gate.release("ea3", "scene")
clear_gate()  # The tour's waiter finds its place dropped and ends.
long_waiter.join(5)
for each in shorts:
    each.join(5)
gate._memory, gate.total_ram_gb, gate.POLL_SECONDS = real_memory, real_total_ram, real_poll
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = real_margins
if saved_kinds is not None:
    gate._write(gate._path("kinds.json"), saved_kinds)
elif os.path.exists(gate._path("kinds.json")):
    os.remove(gate._path("kinds.json"))

print("== estimates by the working set at once (394 amended (27)) ==")
saved_kinds = gate._read(gate._path("kinds.json"))
row = {"ram_gb": 20.5, "ram_once_gb": 15.0, "ram_peaks_gb": 20.5}
gate.record_ram(row, 17.7, 20.0)
check(row["ram_once_gb"] == 17.7 and row["ram_peaks_gb"] == 20.4 and row["ram_gb"] == 17.7
    and row["last_once_gb"] == 17.7 and row["last_peak_gb"] == 20.0,
    "a run: each measure under the same rule (up at once, down a fifth), ram_gb at once: %s" % row)
gate.record_ram(row, 12.0, 14.0)
check(row["ram_once_gb"] == 16.56 and row["ram_gb"] == 16.56, "down a fifth toward the run: %s" % row)
fresh = gate.record_ram({"ram_gb": 6.5}, 4.0, 5.0)
check(fresh["ram_once_gb"] == 6.0 and fresh["ram_peaks_gb"] == 6.2 and fresh["ram_gb"] == 6.0,
    "a row with neither yet starts both from ram_gb: %s" % fresh)
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=20.4, ram_once_gb=16.56, ram_peaks_gb=20.4)})
check(gate.kinds()["suite"]["ram_gb"] == 16.56, "kinds: ram_gb is the at-once estimate")
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=21.0, ram_once_gb=16.56, ram_peaks_gb=20.4)})
check(gate.kinds()["suite"]["ram_gb"] == 16.56, "over a ram_gb an older heavy_job.py wrote from summed peaks")
check(gate.measures(gate.kinds()["suite"]) == "; RAM by at once 16.6, summed peaks 20.4", "both figures shown: %s" % gate.measures(gate.kinds()["suite"]))
shown = io.StringIO()
with contextlib.redirect_stdout(shown):
    shown_code = gate.main(["kinds"])
suite_line = [line for line in shown.getvalue().splitlines() if line.startswith("suite ")]
check(shown_code == 0 and suite_line and suite_line[0].endswith("; RAM by at once 16.6, summed peaks 20.4"),
    "heavy_job kinds prints, both figures on the suite's line: %s" % (suite_line[0] if suite_line else "none"))
gate.RAM_MEASURE = gate.SUMMED_PEAKS
check(gate.kinds()["suite"]["ram_gb"] == 20.4 and gate.measures(gate.kinds()["suite"]).startswith("; RAM by summed peaks 20.4"),
    "RAM_MEASURE back to summed peaks: every kind back at once")
gate.RAM_MEASURE = gate.AT_ONCE
lines = ["2026-11-10T0%d:00:00\tdone\tt\tsuite\texit 0, 800 s, peak 17.0 GB, commit 14.0 GB, working set at once %.1f GB\n" % (i, v)
    for i, v in enumerate((14.0, 16.0, 13.0))]
lines.append("2026-11-10T05:00:00\tdone\tt\tsuite\texit 0, 1250 s, peak 7.0 GB, commit 5.6 GB, working set at once 5.8 GB, lean\n")
lines.append("2026-11-10T06:00:00\tdone\tt\tsuite\treleased after 900 s\n")
check(gate.seeded_once("suite", None, lines) == round(max(13.0, 0.8 * 16.0 + 0.2 * 13.0), 2),
    "seeded from the log: its full runs replayed, the lean one and a release left out: %s" % gate.seeded_once("suite", None, lines))
check(gate.seeded_once("suite_lean3", "suite", lines) == 5.8, "a variant from its kind's lean runs")
check(gate.seeded_once("bench", None, lines) is None, "a kind with no runs in the log: none")
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=20.5), "bench": dict(gate.KINDS["bench"], ram_gb=3.0)})
check(gate.seed_measures(), "seed_measures writes once")
seeded = gate._read(gate._path("kinds.json"))
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
want = gate.seeded_once("suite", None, text.splitlines(True))
check(seeded["suite"]["ram_peaks_gb"] == 20.5 and seeded["suite"]["ram_once_gb"] == (round(want, 2) if want is not None else 20.5)
    and seeded["suite"]["ram_gb"] == seeded["suite"]["ram_once_gb"], "the suite: summed peaks kept, at once seeded: %s" % seeded["suite"])
want = gate.seeded_once("bench", None, text.splitlines(True))
check(seeded["bench"]["ram_peaks_gb"] == 3.0 and seeded["bench"]["ram_once_gb"] == (round(want, 2) if want is not None else 3.0),
    "the bench the same: %s" % seeded["bench"])
check("\tmeasure\theavy_job\tkinds\tRAM estimates seeded, by at once: " in text, "the log says so, both figures")
check(not gate.seed_measures(), "and never again")
if os.name == "nt":
    # One process's own peak, between two watches: 300 MB held a moment, then let go.
    code = gate.run("blip", "bench", [sys.executable, "-c", "x = bytearray(300 * 1024 * 1024); x[::4096] = b'1' * len(x[::4096]); "
        "del x; import time; time.sleep(3)"])
    with open(gate._path("heavy_jobs.log")) as log:
        done = [line for line in log if "\tdone\tblip\tbench\t" in line]
    once = float(done[0].split("working set at once ")[1].split(" GB")[0]) if done else 0.0
    check(code == 0 and once >= 0.28, "the working set at once never under one process's own peak: %s" % (done[0].strip() if done else "none"))
    check(gate.kinds()["bench"].get("last_once_gb", 0.0) >= 0.28, "and it is the bench's at-once measure")

print("== a suite goes lean at its turn, not its first look (394 amended (27)) ==")
gate.total_ram_gb = lambda: None
gate.POLL_SECONDS = 0.1
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 8.0
gate._write(gate._path("kinds.json"), {"suite": dict(gate.KINDS["suite"], ram_gb=14.6, commit_gb=1.0),
    "suite_lean3": dict(gate.KINDS["suite_lean3"], ram_gb=8.0, commit_gb=1.0)})
clear_gate()
table = gate.kinds()
low = (18.3, 30.0)  # 14.6 + 8 out of reach, 8 + 8 in
gate._memory = lambda: low
first = {"kind": "suite", "queued": time.time() - 1}
check(gate.due_row(table, first, table["suite"], [], *low)["ram_gb"] == 8.0, "out of reach, it runs as its lean row at its turn")
check(gate.due_row(table, first, table["suite"], [], 40.0, 40.0)["ram_gb"] == 14.6, "with room, full")
check(gate.due_row(table, dict(first, estimate="suite_lean3"), table["suite"], [], 40.0, 40.0)["ram_gb"] == 8.0, "gone lean, lean")
check(not gate.may_pass(gate.lean_row(table, "suite"), [gate.due_row(table, first, table["suite"], [], *low)], [], *low),
    "a suite behind a full one out of reach does not go past it, lean, to start first")
gate._memory = lambda: (40.0, 40.0)
check(gate.take("holder", "suite", os.getpid()) == 0, "a suite held")
gate._memory = lambda: low
turn = threading.Thread(target=lambda: gate.take("turn", "suite", os.getpid()), daemon=True)
turn.start()
wait_for(lambda: queue_of() == ["turn suite"])
time.sleep(1.0)
entry = gate._entries("queue")[0] if gate._entries("queue") else {}
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check(entry.get("estimate", "suite") == "suite" and "\tlean\tturn\tsuite\t" not in text,
    "out of reach while a suite runs: still full, no lean chosen (%s)" % entry)
reasons = gate.queue_reasons(gate._entries("queue"), gate._entries("running"), low[0], low[1], None)
check(reasons and "at most 1 at once" in reasons[0], "status: it waits on the suite running, not on memory: %s" % reasons)
gate._memory = lambda: (40.0, 40.0)
gate.release("holder", "suite")
wait_for(lambda: any(each["tree"] == "turn" for each in gate._entries("running")))
held = [each for each in gate._entries("running") if each["tree"] == "turn"]
check(held and held[0]["estimate"] == "suite" and held[0]["ram_gb"] == 14.6, "room at its turn: it starts full (%s)" % held)
turn.join(5)
gate.release("turn", "suite")
gate._memory = lambda: low
check(gate.take("holder", "suite", os.getpid()) == 0 and gate._entries("running")[0]["estimate"] == "suite_lean3",
    "no room at its turn, nothing ahead: lean at once")
turn2 = threading.Thread(target=lambda: gate.take("turn2", "suite", os.getpid()), daemon=True)
turn2.start()
wait_for(lambda: queue_of() == ["turn2 suite"])
time.sleep(1.0)
entry = gate._entries("queue")[0] if gate._entries("queue") else {}
check(entry.get("estimate", "suite") == "suite", "queued behind it, still full")
waited_from = time.time()
gate.release("holder", "suite")
wait_for(lambda: any(each["tree"] == "turn2" for each in gate._entries("running")))
held = [each for each in gate._entries("running") if each["tree"] == "turn2"]
check(held and held[0]["estimate"] == "suite_lean3" and time.time() - waited_from < 5.0,
    "no room at its turn: lean at once, no wait first (%s)" % held)
with open(gate._path("heavy_jobs.log")) as log:
    lean_lines = [line for line in log if "\tlean\tturn2\tsuite\t" in line]
check(len(lean_lines) == 1 and "at its turn, full 14.6 + 8 GB" in lean_lines[0], "the lean line, once, with the full figure: %s" % (
    lean_lines[0].strip() if lean_lines else "none"))
turn2.join(5)
gate.release("turn2", "suite")
clear_gate()
print("== a memory wait names the lean run (394 amended (34)) ==")
lean_table = {"suite": dict(gate.KINDS["suite"], ram_gb=18.4), "suite_lean3": dict(gate.KINDS["suite_lean3"], ram_gb=6.4)}
full_row = dict(lean_table["suite"], kind="suite")
_, full_why = gate.decide(full_row, [], True, 12.4, None, 40.0)
check(gate.at_least(lean_table, full_row, full_why).endswith("18.4 + %.0f GB wanted (it runs lean at its turn: 6.4 + %.0f GB)" % (
    gate.MARGIN_GB, gate.MARGIN_GB)), "a full suite out of reach says the lean run's figure: %s" % gate.at_least(lean_table, full_row, full_why))
lean_only = gate.lean_row(lean_table, "suite")
_, lean_why = gate.decide(lean_only, [], True, 12.4, None, 40.0)
check(gate.at_least(lean_table, lean_only, lean_why) == lean_why, "a lean one, unchanged")
check(gate.at_least(lean_table, dict(gate.KINDS["scene"], kind="scene"), "1 + 8 GB wanted") == "1 + 8 GB wanted"
    and gate.at_least(lean_table, full_row, "1 suite running, at most 1 at once") == "1 suite running, at most 1 at once",
    "a kind with no lean run, or a wait on the count, unchanged")
print("== a take of suite swapped for saturn at its grant (394 amended (33)) ==")
saved_swap = (gate._memory, gate.total_ram_gb, gate.MARGIN_GB, gate.COMMIT_MARGIN_GB, gate.PROBE_COMMAND, gate.PROBE_SECONDS)
gate.total_ram_gb = lambda: None
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = 8.0, 8.0
asked = os.path.join(STATE, "asked.txt")


def probe(body):
    """A stand-in for tools/remote_tests.sh kind: notes that it was asked, then [body]."""
    return [sys.executable, "-c", "open(%r, 'a').write('x')\n" % asked + body]


def swap_log():
    with open(gate._path("heavy_jobs.log")) as handle:
        return handle.read()


# Saturn answers; 12.5 GB free: a suite, lean too, is out of reach; saturn's local parts are not.
gate._memory = lambda: (12.5, 40.0)
gate.PROBE_COMMAND = probe("print('suite_remote')")
check(gate.take("swapper", "suite", os.getpid()) == 0, "a take of suite with 12.5 GB free and saturn answering")
held = gate._entries("running")
check(len(held) == 1 and held[0]["kind"] == "suite_remote" and held[0]["asked"] == "suite"
    and held[0]["ram_gb"] == gate.kinds()["suite_remote"]["ram_gb"], "granted as suite_remote, asked suite: %s" % held)
check(gate.holds("swapper", "suite") and gate.holds("swapper", "suite_remote"),
    "it holds suite (a script's holds line unchanged) and suite_remote (land.sh's first check)")
check("\tstart\tswapper\tsuite_remote\tasked suite, saturn answers" in swap_log(), "the start line says it was swapped")
# tests/land.ps1 runs a suite here inside it: the take is taken back as a suite.
name, estimate = gate._adopt_take("swapper", "suite")
held = gate._entries("running")
check(name is not None and len(held) == 1 and held[0]["kind"] == "suite" and "asked" not in held[0]
    and "\tunswapped\tswapper\tsuite\t" in swap_log(), "a local suite run inside it takes it back as a suite: %s" % held)
check(gate.release("swapper", "suite") == 0 and not gate._entries("running"), "released as a suite")
gate.take("swapper", "suite", os.getpid())
check(gate.release("swapper", "suite") == 0 and not gate._entries("running")
    and "\tdone\tswapper\tsuite_remote\treleased" in swap_log(), "a swapped take released by `release <tree> suite`")
# Fail safe: a probe that hangs past PROBE_SECONDS, or errs, leaves a suite.
gate._memory = lambda: (60.0, 60.0)
gate.PROBE_SECONDS = 1.0
gate.PROBE_COMMAND = probe("import time; time.sleep(30); print('suite_remote')")
began = time.time()
gate.take("hang", "suite", os.getpid())
held = gate._entries("running")
check(len(held) == 1 and held[0]["kind"] == "suite" and "asked" not in held[0] and time.time() - began < 15,
    "a probe that hangs: a suite here after the probe's limit (%.1f s): %s" % (time.time() - began, held))
gate.release("hang", "suite")
gate.PROBE_COMMAND = probe("import sys; print('suite_remote'); sys.exit(1)")
gate.take("err", "suite", os.getpid())
held = gate._entries("running")
check(len(held) == 1 and held[0]["kind"] == "suite", "a probe that errs, whatever it printed: a suite here: %s" % held)
gate.release("err", "suite")
gate.PROBE_COMMAND = [sys.executable + "-missing"]
check(gate.saturn_answers() is False, "a probe that cannot start is no")
# LAND_LOCAL=1 (the cut) never asks; a scene is never swapped.
if os.path.exists(asked):
    os.remove(asked)
gate.PROBE_COMMAND = probe("print('suite_remote')")
os.environ["LAND_LOCAL"] = "1"
gate.take("cut", "suite", os.getpid())
del os.environ["LAND_LOCAL"]
held = gate._entries("running")
check(len(held) == 1 and held[0]["kind"] == "suite" and not os.path.exists(asked), "LAND_LOCAL=1: a suite, saturn never asked: %s" % held)
gate.release("cut", "suite")
gate.take("scener", "scene", os.getpid())
held = gate._entries("running")
check(len(held) == 1 and held[0]["kind"] == "scene" and not os.path.exists(asked), "a scene is never swapped nor asked about")
gate.release("scener", "scene")
(gate._memory, gate.total_ram_gb, gate.MARGIN_GB, gate.COMMIT_MARGIN_GB, gate.PROBE_COMMAND, gate.PROBE_SECONDS) = saved_swap

print("== a landing's take clears or refuses untracked files main tracks (394 amended (35)) ==")
import subprocess  # noqa: E402
repo = tempfile.mkdtemp(prefix="heavy_job_stray_")
def git(*args):
    return subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "core.autocrlf=false"] + list(args),
        cwd=repo, capture_output=True, text=True)
def put(path, text="x"):
    full = os.path.join(repo, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w") as handle:
        handle.write(text)
git("init", "-q")
for path in ("a.gd", "keep.txt"):
    put(path)
git("add", "-A")
git("commit", "-q", "-m", "base")
base = git("rev-parse", "HEAD").stdout.strip()
for path in ("tours/fish.gd", "tours/fish.gd.uid", "art/a.png.import", "levels/wilds.json"):
    put(path)
git("add", "-A")
git("commit", "-q", "-m", "main")
git("update-ref", "refs/remotes/origin/main", "HEAD")
git("checkout", "-q", "--detach", base)
check(gate.stray_tracked(repo) == ([], []), "nothing untracked: nothing done")
put("tours/fish.gd.uid")
put("art/a.png.import")
put("notes.txt")
removed, refused = gate.stray_tracked(repo)
check(removed == ["art/a.png.import", "tours/fish.gd.uid"] and refused == [],
    "generated files main tracks removed, an untracked file main doesn't track left alone: %s %s" % (removed, refused))
check(not os.path.exists(os.path.join(repo, "tours", "fish.gd.uid")) and os.path.exists(os.path.join(repo, "notes.txt")),
    "the .uid is gone, notes.txt kept")
check(git("rebase", "-q", "origin/main").returncode == 0, "the rebase onto main then goes through")
git("checkout", "-q", "--detach", base)
put("tours/fish.gd.uid")
put("levels/wilds.json")
gate.STRAY_CHECK = True
here = os.getcwd()
os.chdir(repo)
err = io.StringIO()
with contextlib.redirect_stderr(err):
    code = gate.take("stray", "suite", os.getpid())
os.chdir(here)
check(code == 2 and "levels/wilds.json" in err.getvalue() and "tours/fish.gd.uid" in err.getvalue(),
    "a take of suite with a real file main tracks: refused at once, exit 2, names it (%d): %s" % (code, err.getvalue().strip()[-200:]))
check(not any(os.path.isdir(gate._path(f)) and gate._entries(f) for f in ("queued", "running")), "nothing queued or taken")
check(os.path.exists(os.path.join(repo, "levels", "wilds.json")), "the real file is left alone")
os.chdir(repo)
check(gate.stray_refused("stray", "bench") is False, "a bench's take never looks (not a landing kind)")
os.chdir(here)
gate.STRAY_CHECK = False
check(gate.stray_tracked(STATE) == ([], []), "not a checkout: nothing done")
shutil.rmtree(repo, ignore_errors=True)
clear_gate()
gate._memory, gate.total_ram_gb, gate.POLL_SECONDS = real_memory, real_total_ram, real_poll
gate.MARGIN_GB, gate.COMMIT_MARGIN_GB = real_margins
if saved_kinds is not None:
    gate._write(gate._path("kinds.json"), saved_kinds)
elif os.path.exists(gate._path("kinds.json")):
    os.remove(gate._path("kinds.json"))

shutil.rmtree(STATE, ignore_errors=True)
print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

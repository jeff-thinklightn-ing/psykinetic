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
import os
import shutil
import sys
import tempfile
import time

sys.dont_write_bytecode = True  # No __pycache__ left in tools/.
STATE = tempfile.mkdtemp(prefix="heavy_job_test_")
os.environ["HEAVY_JOBS_DIR"] = STATE
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import heavy_job as gate  # noqa: E402

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
# An out-of-reach suite stepped behind a bench queued after it, the bench
# became the head and the landing waited for it (release, 2026-10-25).
out_suite = dict(suite, kind="suite", excludes=["bench"])
bench_queued = dict(gate.KINDS["bench"], kind="bench")
soak_queued = dict(gate.KINDS["soak"], kind="soak")
check(not gate.may_step_aside(out_suite, [dict(import_row), bench_queued]), "an out-of-reach suite never steps behind a bench")
check(not gate.may_step_aside(dict(bench_queued), [dict(out_suite, excludes=[])]),
	"nor a bench behind a suite, the exclusion said by the other side only")
check(not gate.may_step_aside(dict(mesh, kind="soak", excludes=[]), [bench_queued]), "nor a soak behind a bench")
check(gate.may_step_aside(mesh, [dict(import_row), soak_queued]), "but past kinds it runs beside, as before")
check(gate.may_step_aside(out_suite, []), "and with none behind, nothing to keep")
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
check(gate.blockers(dict(table["bench"], kind="bench"), [suite_at(now), dict(running(1, 1), kind="godot_import")]) == [suite_at(now)],
    "a bench's blockers: the suite, not an import")

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

print("== a head out of reach steps to the back ==")
# Waiters from a tree's older heavy_job.py don't go past it themselves.
import threading
gate.total_ram_gb = lambda: None
table = gate._read(gate._path("kinds.json")) or {}
table["trellis_mesh"] = dict(gate.kinds()["trellis_mesh"], ram_gb=1e12)
gate._write(gate._path("kinds.json"), table)
real_poll, gate.POLL_SECONDS = gate.POLL_SECONDS, 0.1
big = threading.Thread(target=lambda: gate.take("art", "trellis_mesh", os.getpid()), daemon=True)
def wait_for(condition, seconds=60.0):
    # Polled, not slept: under a loaded landing a fixed wait was overrun
    # (release, art-kit's landing 2026-10-18).
    until = time.time() + seconds
    while not condition() and time.time() < until:
        time.sleep(0.05)
    return condition()
def queue_order():
    return [each["tree"] for each in gate._entries("queue")]
def stepped_aside():
    with open(gate._path("heavy_jobs.log")) as log:
        return "\taside\tart\ttrellis_mesh\t" in log.read()
big.start()
wait_for(lambda: queue_order() == ["art"])
# Its queue file held open a moment as it steps aside (a reader, a scanner):
# Windows refuses the rename, and the waiter tries again rather than ending
# (it ended once, in ui's landing, 2026-10-24).
held = open(gate._path("queue", gate._entries("queue")[0]["file"]))
gate._write(gate._path("queue", "%019d-old-1.json" % time.time_ns()), {"tree": "old", "kind": "suite", "pid": None,
    "waiter": os.getpid(), "queued": time.time()})
time.sleep(0.4)
held.close()
wait_for(lambda: queue_order() == ["old", "art"] and stepped_aside())
check(big.is_alive(), "the waiter lived through its file being held open")
order = queue_order()
check(order == ["old", "art"], "the job behind goes first in the queue's own order: %s" % order)
for each in gate._entries("queue"):
    os.remove(gate._path("queue", each["file"]))
big.join(5)
# The same head with a bench behind it, the head's kind excluding benches
# (394 amended (14)): it keeps its place, so the bench never becomes the head.
table["trellis_mesh"] = dict(table["trellis_mesh"], excludes=["bench"])
gate._write(gate._path("kinds.json"), table)
kept = threading.Thread(target=lambda: gate.take("art2", "trellis_mesh", os.getpid()), daemon=True)
kept.start()
wait_for(lambda: queue_order() == ["art2"])
gate._write(gate._path("queue", "%019d-later-1.json" % time.time_ns()), {"tree": "later", "kind": "bench", "pid": None,
    "waiter": os.getpid(), "queued": time.time()})
time.sleep(1.0)
order = queue_order()
check(order == ["art2", "later"], "an out-of-reach head never steps behind a kind it excludes: %s" % order)
for each in gate._entries("queue"):
    os.remove(gate._path("queue", each["file"]))
kept.join(5)
gate.POLL_SECONDS = real_poll
gate.total_ram_gb = real_total
check(stepped_aside(), "the log says it stepped aside")

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
full = dict(gate.KINDS["suite"], kind="suite", ram_gb=14.6, commit_gb=12.2)
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
        os.remove(gate._path(folder, each["file"]))
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
    os.remove(gate._path("queue", each["file"]))
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
shown = io.StringIO()
with contextlib.redirect_stdout(shown):
    gate.summary(datetime.date.today().isoformat())
check("1 backfill, 1 late (" in shown.getvalue(), "the summary counts both: %s" % shown.getvalue().splitlines()[-1])
gate.POLL_SECONDS = real_poll
gate.total_ram_gb = real_total
os.remove(gate._path("kinds.json"))

shutil.rmtree(STATE, ignore_errors=True)
print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

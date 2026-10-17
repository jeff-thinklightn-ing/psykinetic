#!/usr/bin/env python3
"""tools/heavy_job.py's gate (decision 394): its decision with made-up
memory numbers, the estimate update, the newest-first stop, and a take and
release through a state folder of its own (HEAVY_JOBS_DIR), never the real
one.
  python tests/heavy_job_test.py
"""
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
ok, why = gate.decide(suite, [], True, 60.0, None, 5.0)
check(not ok and why.startswith("commit"), "60 GB RAM free but 5 GB commit: waits, saying commit (%s)" % why)
check(gate.decide(suite, [], True, 60.0, None, 4.0 + gate.COMMIT_MARGIN_GB)[0], "commit at the estimate plus its margin starts")
check(gate.decide(suite, [], True, 60.0, None, None)[0], "no commit known: RAM alone")

print("== stopping: the newest job, under the margin ==")
older, newer = running(4, 4, started=10.0), running(9, 9, started=20.0)
check(not gate.should_stop(older, [older, newer], 5.0), "under the margin, the older job keeps on")
check(gate.should_stop(newer, [older, newer], 5.0), "the newest stops")
check(not gate.should_stop(newer, [older, newer], 9.0), "above the margin, nothing stops")

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

shutil.rmtree(STATE, ignore_errors=True)
print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

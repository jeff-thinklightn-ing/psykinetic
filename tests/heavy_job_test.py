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
check(gate.take("test", "suite", os.getpid()) == 0, "take")
entries = gate._entries("running")
check(len(entries) == 1 and entries[0]["tree"] == "test", "running: one, test's")
check(gate.release("test", "suite") == 0 and not gate._entries("running"), "released: none running")
dead = {"tree": "gone", "kind": "bench", "pid": 999999, "queued": time.time(), "started": time.time(),
    "ram_gb": 3.0, "gpu": False}
with gate.StateLock():
    gate._write(gate._path("running", "gone-bench-999999.json"), dead)
    check(not gate._entries("running"), "a running entry whose process is gone is dropped")
code = gate.run("test", "suite", [sys.executable, "-c", "import time; time.sleep(1)"])
check(code == 0 and "last_peak_gb" in gate.kinds()["suite"], "run: the command's exit code, the kind's peak recorded")
with open(gate._path("heavy_jobs.log")) as log:
    text = log.read()
check("\tdone\ttest\tsuite\t" in text and "\tstale\tgone\tbench\t" in text, "the log has the run and the stale entry")

shutil.rmtree(STATE, ignore_errors=True)
print("\nRESULT: %s" % ("PASS" if failed == 0 else "FAIL (%d failed)" % failed))
sys.exit(1 if failed else 0)

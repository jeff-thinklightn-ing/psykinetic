#!/usr/bin/env python3
"""The resource gate for heavy jobs (decision 394, Jeff's rule): before a
session starts a heavy job (mesh or image generation, a test suite, a bench,
a Godot import or export) it asks this gate, shared by every tree and
art-gen, which lets it start only when there is room:

  * free RAM, less what running jobs have yet to take of their estimates,
    at least the job's estimate plus MARGIN_GB (8: the machine keeps 8 GB
    free);
  * free commit (what Windows can still promise, RAM and pagefile, before
    allocations fail), less the same, at least the estimate plus
    COMMIT_MARGIN_GB;
  * for a GPU kind, free GPU memory (nvidia-smi) at least its GPU estimate;
  * fewer than MAX_RUNNING heavy jobs running (one godot_import not counted:
    394 amended (22)), never two GPU jobs, and no
    more of a kind than its max_running (suite 1: a suite runs its scenes
    in parallel and fills the CPU, and two together took ten times as long
    each; bench 1, as the bench lock);
  * none of the kinds it excludes running: a bench and a suite never run
    together (a bench's timings beside a suite are the suite's, not the
    build's: one build measured 20 to 42 ms a frame by what ran beside it),
    nor a bench and a soak; a soak (sim steps counted, no timings: town_soak,
    town_balance) runs beside a suite, below normal priority, one at a time
    (394 amended (8): economy's 150-minute soak as a bench held five
    landings and a cut); a scene (one test scene run alone, a session
    checking its change) runs beside a suite too, below normal priority, two
    at most, never beside a bench (394 amended (17): solo scene runs outside
    the gate took a landing's CPU, and three landings' net_test timing
    checks failed one night, each passing again on a retry).

An entry names its processes by id and start time (pid_since, waiter_since,
adopted_since): one whose id now belongs to another process, or queued
before the machine last started, is stale and dropped (394 amended (8)).

Otherwise it waits in a queue, first come first served: only the job at
its head may start, so a big job is not starved by small ones; except that
a job may go past those before it that wait only on their own kind (a
suite behind a suite: may_pass), when it is of another kind, or that are
held only by such rows before them (394 amended (21)). A job run
through `run` is watched: if free RAM falls under the margin while it runs
and it is the newest job running, its own wrapper stops its own child (no
one else's process: never kill by name, never another session's) and puts
it back in the queue, MAX_RESTARTS times at most. Each kind's estimate is
updated from the most `run` sees the whole process tree hold at once (394
amended (27); RAM_MEASURE), rising at once and falling slowly. A `run` by a tree that already
holds a take of the kind (land.sh under its landing's take), or whose
take's holder is this run's own ancestor process whatever the tree's name
(394 amended (11): maps landed from a side worktree, wt-umbrage, under a
take as "maps", and land.sh, named for its folder, queued behind its own
take 29.6 minutes holding the land lock), adopts the take instead of
queueing: it measures the take's entry, so what it is owed
shrinks as it really uses memory, and it is never stopped (its landing
holds the land lock, which must never wait on the gate). A run gives its
command HEAVY_JOB_HELD (its entry's name): a run, take or release started
under it (frame_budget.ps1 inside a gated bench script) neither queues nor
releases, since the outer run holds the room and measures its whole tree;
before this, such a run queued behind its own parent forever.

A run has a time limit (limit_seconds): its --expect minutes, else
OVERRUN_FACTOR times the median of its kind's last RUN_HISTORY clean runs
(never under OVERRUN_FLOOR_SECONDS), else its kind's max_minutes. Past it,
or using under HUNG_CPU of a core for HUNG_SECONDS (kinds off the GPU), its
own wrapper stops it, logs "overrun" or "hung" and exits 5, not queued
again: a bench stuck on a parse error, or crawling, held the one bench
slot 10 h on 2026-10-17 and 7.6 h on 2026-10-18 with landings behind it.
A soak meant to run for hours says so with --expect; the soak kind's limit
is its max_minutes (180) whatever its runs took (fixed_limit).

A suite out of reach (memory held outside the gate) at its turn (394
amended (27); for LEAN_AFTER_SECONDS, a kind not lean_first) runs lean (394 amended (9), (10), (12)): land.sh reads HEAVY_JOB_KIND,
suite_lean3, and runs fewer scenes at once and its other parts (net_test,
state_test, server_boot_test) after the suite, not beside it, net_test's
groups one after another; under suite_lean3's own estimate, when that one
is in reach. It is still a suite in running/ (its caps and exclusions, and
an older heavy_job.py's, hold), marked "estimate": suite_lean3, whose row
its peak and time update. Each new lean shape takes a new name, so it
starts from a seed: suite_lean (fewer scenes alone) recorded 13.8 GB,
suite_lean2 (the parts after the suite) 11.8. Maps' suite
waited 23 minutes at 18 GB free for 14.6 + 8 on 2026-10-24, about twenty
sessions, a browser and Jeff's Ableton holding the rest.

A take is not watched: it owes its whole estimate while held, and its
kind's estimate is never measured. A process its holder starts after the
take (art-gen's ComfyUI server, which loads the models) is attached to it
(`attach`, 394 amended (20)): each look at the running jobs reads its
working set and commit as the take's use, so the gate counts that memory as
the job's, not as held outside the gate, and release records the attached
processes' peaks (Windows' own peak counters) as the kind's estimate. A
kind with no measured row is judged on commit at UNMEASURED_COMMIT_FACTOR
times its RAM estimate, unless its first row names its commit: comfy_batch,
only ever taken, sat on its first 6 GB while its server used up the commit
(2026-11-04 00:09-00:23: free commit 1-2 GB with 15 GB of RAM free, nine
scenes stopped, three died at launch with 0xC0000142).

State and log live outside the repo, in STATE_DIR (HEAVY_JOBS_DIR to put
them elsewhere, as the test does): running/ and queue/ hold a file a job,
kinds.json the estimates and caps (edit a kind's max_running there to
tune it), heavy_jobs.log a line an event (`summary`).

  heavy_job.py run <tree> <kind> [--expect MIN] [--visible] [--no-queue-under-lock DIR] -- <command...>
                                                   wait, run, release; the command's exit code (5: stopped,
                                                   over its limit or hung; a long soak passes --expect MIN);
                                                   a windowed Godot in <command> runs off-screen and silent
                                                   unless --visible (664 amended (2)); with the land lock
                                                   at DIR held by <tree> (lock_owned), it runs only inside
                                                   a take, else exits 6 unqueued (394 amended (31))
  heavy_job.py take <tree> <kind> [--pid N]        wait, then hold a place (scripts that cannot wrap);
                                                   N a Windows process id (Git Bash: $(cat /proc/$$/winpid))
  heavy_job.py attach <tree> <kind> --pid N        a process started under <tree>'s take of <kind> (a
                                                   model server): measured as the take's (394 amended (20))
  heavy_job.py release <tree> <kind>               give back what take held
  heavy_job.py holds <tree> <kind>                 exit 0 if <tree> holds a <kind> (run or take)
  heavy_job.py beat <owner> [<kind>]               the land lock's <owner>'s take of <kind> (any
                                                   landing's: suite, suite_*) alive now: TAKE_STALE_SECONDS
                                                   count from here (exit 1: none held; 394 amended (31))
  heavy_job.py front <tree> <kind> --by release --why "<reason>"
                                                   release alone: that queued entry first among the
                                                   waiters, never past what runs (394 amended (25))
  heavy_job.py status                             running, queued, free memory
  heavy_job.py kinds                               the kinds and their estimates
  heavy_job.py summary [YYYY-MM-DD]                what waited or was stopped that day (today)
  heavy_job.py note <tree> launch <detail...>      log a test scene that died at launch (decision 530),
                                                   or `timeout`, one killed for time (90 amended (1)),
                                                   with free RAM and commit; prints the line's detail

Standard library only (ctypes for Windows), so any Python can run it by path.
"""
import ctypes
import datetime
import json
import os
import re
import subprocess
import sys
import time

STATE_DIR = os.environ.get("HEAVY_JOBS_DIR", r"C:\dev\psykinetic-trees\heavy_jobs")
MARGIN_GB = 8.0
## Commit (RAM and pagefile, 100 GB here) kept free to start a job: past
## it allocations fail and programs crash. 4, not 8 (394 amended (16)): with
## a session's MCP servers holding 13 GB of commit, 8 kept even a lean suite
## out for hours while RAM had room; COMMIT_STOP_GB guards the run instead.
COMMIT_MARGIN_GB = 4.0
## Free commit under this many watches running (LOW_WATCHES) stops the
## newest job, as free RAM under MARGIN_GB does (394 amended (16)).
COMMIT_STOP_GB = 2.0
MAX_RUNNING = 3
## Running jobs of an "uncounted" kind (godot_import: short, below normal
## priority) left out of MAX_RUNNING, this many at most (394 amended (22)).
UNCOUNTED_MOST = 1
## A job holding the gate this long is flagged in status, the log and the
## summary (a bench held 588 minutes on 2026-10-17 before anyone saw it).
LONG_HOLD_SECONDS = 3600
## Set by `run` for its command: the name of its running entry.
HELD_ENV = "HEAVY_JOB_HELD"
## Set by `run` for its command: the kind whose estimate it runs under
## (suite_lean3 for a lean suite, 394 amended (9), (10), (12)).
KIND_ENV = "HEAVY_JOB_KIND"
## A job out of reach this long runs as its kind's lean variant, if any;
## at once for a kind marked "lean_first" (394 amended (23): the suite, whose
## full run hasn't fitted beside the sessions' own memory since 11-07, so each
## landing waited these five minutes for nothing).
LEAN_AFTER_SECONDS = 5 * 60
## A run's processes are listed (memory, command line) when its commit
## passes the last listing's by this much, at most this often (394 amended
## (10)): what held the memory at its peak, printed and kept in peaks/.
PEAK_LIST_STEP_GB = 0.25
PEAK_LIST_SECONDS = 15.0
MAX_GPU_RUNNING = 1
POLL_SECONDS = 5.0
WATCH_SECONDS = 2.0
## Free RAM under the margin this many watches running stops the newest job.
LOW_WATCHES = 2
MAX_RESTARTS = 2
## A take running this long is forgotten, even while the shell that took it
## lives on (a session's shell, a loop that never released): a landing takes
## under 10 minutes, and a land lock is stale at 15.
## Since 394 amended (31) it counts from the take's last beat when later
## (`beat`; tools/land_lock.sh take beats its tree's suite take each try, so a
## take held while its tree waits on the land lock is never dropped: perf's
## 360 amended (1) and combat's 340 amended (2) lost theirs so, 11-11).
TAKE_STALE_SECONDS = 30 * 60
## The guard (394 amended (37)): the gate code's revision, written into every
## entry it makes. Older gate code is still run from checkouts that predate
## a change (perf-hitch's waiter, before 31, dropped perf's beaten take at
## 30 minutes on 11-12; art-kit's 01:29 waiter dropped ui's and
## pc-character's). An entry without it, or with a lower one, was written by
## older code: `status` names it with its checkout, the daily summary counts
## it by tree. Raise it with any change older code would get wrong.
GATE_REVISION = 37
## This checkout, written into every entry (which folder to rebase).
CHECKOUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
## A landing's take this old with no beat and no run adopting it: its land
## lock tries are not beating it (a broken or old land_lock.sh), flagged in
## `status` and counted in the daily summary by tree (release's ask, 11-12).
UNBEATEN_SECONDS = 10 * 60
## Who has been told of already (old_gate, unbeaten): each once in the log.
NOTED_FILE = "noted.json"
## A wait this long goes in the log (and so in `summary`) with its reason.
LONG_WAIT_SECONDS = 5 * 60
## The state's own lock, if its holder died holding it.
LOCK_STALE_SECONDS = 30
## A run's limit: this many times its kind's median clean run, at least the
## floor; how many runs the median reads.
OVERRUN_FACTOR = 3.0
OVERRUN_FLOOR_SECONDS = 30 * 60
RUN_HISTORY = 9
## A run off the GPU using under this share of one core over the last
## HUNG_SECONDS (and running that long) is hung.
HUNG_CPU = 0.03
HUNG_SECONDS = 10 * 60
## Exit code of a run its wrapper stopped as over its limit or hung.
STOPPED_CODE = 5
## A job going past one it conflicts with (backfill, 394 amended (18))
## counts on its longest recorded run times this.
BACKFILL_MARGIN = 1.25
## The kinds and their first estimates (GB), before any is measured;
## max_minutes: the limit before the kind has recorded runs.
KINDS = {
    "trellis_mesh": {"ram_gb": 9.0, "gpu_gb": 12.0, "gpu": True},
    # Its commit near trellis_mesh's measured 20.8 GB until attach measures
    # its server (394 amended (20)).
    "comfy_batch": {"ram_gb": 6.0, "gpu_gb": 10.0, "gpu": True, "commit_gb": 20.0},
    "suite": {"ram_gb": 6.5, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["bench"], "max_minutes": 90,
        "lean": "suite_lean3", "lean_first": True},  # tests/land.sh: 6.3 GB measured
    # A suite run lean (394 amended (9), (10), (12)): its estimate and runs only;
    # it runs as a suite (lean_row), never as a kind of its own.
    "suite_lean3": {"ram_gb": 8.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90, "variant_of": "suite"},
    # A landing whose Godot tests run on saturn (tools/remote_tests.sh; Jeff,
    # 2026-11-11): only the exported server's boot and the tool tests run on
    # this PC, so it asks for their room, not a suite's. A kind of its own, so
    # the suite's estimate never learns from a run that held no suite; land.sh
    # picks it when saturn answers, and a landing takes it by the name
    # `tools/remote_tests.sh kind` prints. "remote": its work is on another
    # machine, so this PC's CPU says nothing of whether it is hung (ssh and
    # tee idle while saturn runs the suite); its limit is fixed instead, over
    # the sum of remote_tests.sh's own timeouts.
    "suite_remote": {"ram_gb": 3.0, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["bench"], "max_minutes": 60,
        "fixed_limit": True, "remote": True},
    "bench": {"ram_gb": 3.0, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["suite", "suite_remote", "soak", "scene"], "max_minutes": 90},
    # Not counted under MAX_RUNNING, one at a time (394 amended (22)): six
    # imports waited on the count beside a suite and two scenes, 2026-11-04.
    "godot_import": {"ram_gb": 2.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90,
        "uncounted": True, "below_normal": True},
    "godot_export": {"ram_gb": 3.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90},
    # A soak (394 amended an eighth time) counts sim steps, not time: it
    # runs beside a suite, at below-normal priority so the suite's scenes
    # come first, never beside a bench (whose timings it would skew); its
    # limit is max_minutes, not its median run, since --days sets its length.
    "soak": {"ram_gb": 2.5, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["bench"], "max_minutes": 180,
        "fixed_limit": True, "below_normal": True},
    # A test scene run alone (394 amended (17)): beside a suite, below
    # normal priority so the landing's scenes and net_test come first.
    # max_expect (394 amended (32)): a scene's --expect is at most 20 minutes;
    # a longer run is a soak (11-11 19:52-20:50: a "scene" row with a
    # 300-minute limit, 192 runs chained inside it, held a slot of three).
    "scene": {"ram_gb": 1.5, "gpu_gb": 0.0, "gpu": False, "max_running": 2, "excludes": ["bench"], "max_minutes": 30,
        "below_normal": True, "max_expect": 20},
    # A test that starts several Godots, run alone (394 amended (24)): net_test
    # (its servers and four clients, 11.7 GB at once). Its own estimate: as a
    # scene it tripled the scene estimate every tree waits on, as a suite it
    # would pull the full suite's down and take the landings' one slot.
    "net": {"ram_gb": 13.6, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["bench"], "max_minutes": 30,
        "below_normal": True},
}
## A many-Godot test, by its command (394 amended (24)): a run of one under
## another kind is refused, named, before it queues.
MANY_GODOT_TESTS = ("net_test",)


def many_godot_test(command):
    """The MANY_GODOT_TESTS name a [command] runs, or None: a file named it
    (net_test.sh, res://tests/net_test.tscn), never a name it is part of.
    Matched as a substring, combat's free_net_test.tscn (one Godot, 0.75
    GB) was refused as a scene and waited 51 minutes as a net run (11-10)."""
    for part in command:
        for word in re.split(r"[\\/\s'\"=:]+", str(part)):
            for name in MANY_GODOT_TESTS:
                if word == name or word.startswith(name + "."):
                    return name
    return None


## A kind never measured (no kinds.json row) is judged on commit at this
## times its RAM estimate, unless its first row names commit_gb (394
## amended (20)).
UNMEASURED_COMMIT_FACTOR = 2.0
## What a kind's RAM estimate is measured by (394 amended (27)): AT_ONCE, the
## most its processes held together (each watch's sum, never under the largest
## one process's own peak), or SUMMED_PEAKS, each process's own peak added up
## (the measure before): a suite's processes peak at different moments, so
## the sum ran 2-3 GB over what the suite ever held (11-10: 14.0-20.5 GB summed,
## 11.8-17.7 at once) and held every landing lean. Both are kept in kinds.json
## (MEASURE_FIELDS) under the same rule (updated_estimate); ram_gb is the one
## named here, so setting SUMMED_PEAKS puts every kind back at once. Commit is
## measured at once already (the job object's own peak, exact).
AT_ONCE, SUMMED_PEAKS = "at once", "summed peaks"
RAM_MEASURE = AT_ONCE
MEASURE_FIELDS = {AT_ONCE: "ram_once_gb", SUMMED_PEAKS: "ram_peaks_gb"}
## A kind's at-once estimate, first seeded from its last done lines in the log
## (replayed under updated_estimate), this many at most.
SEED_RUNS = 20
GB = 1024.0 ** 3


# --- The decision (pure: the test gives it numbers) -------------------------

def reserved_gb(running):
    """What running jobs are still owed: each one's estimate less what it
    already uses (a take, unwatched, owes its whole estimate)."""
    return sum(max(0.0, job["ram_gb"] - job.get("using_gb", 0.0)) for job in running)


def commit_of(row):
    """A kind's or job's commit estimate: commit_gb, else its RAM estimate.
    They differ for a GPU job: what it puts on the card is charged to
    Windows' commit too, with no RAM behind it (perf measured 6 GB moved to
    the card: commit 8.1 -> 14.1 GB, working set unchanged)."""
    return row.get("commit_gb", row["ram_gb"])


def reserved_commit_gb(running):
    """What running jobs are still owed of commit, as reserved_gb of RAM."""
    return sum(max(0.0, commit_of(job) - job.get("using_commit_gb", job.get("using_gb", 0.0))) for job in running)


def decide(job, running, head, free_ram_gb, free_gpu_gb, free_commit_gb=None):
    """Whether [job] may start now: (True, "") or (False, why). [job]: its
    kind's row, with "kind"; [running]: the jobs running ({kind, ram_gb,
    using_gb, gpu}); [head]: whether it is first in the queue; free memory
    in GB (free_gpu_gb or free_commit_gb None: not known)."""
    if not head:
        return False, "behind others in the queue"
    if counted(running) >= MAX_RUNNING and not (job.get("uncounted") and uncounted(running) < UNCOUNTED_MOST):
        return False, "%d heavy jobs running" % counted(running)
    for each in running:
        if each.get("kind") in job.get("excludes", []):
            return False, "a %s running (never beside a %s)" % (each.get("kind"), job.get("kind"))
    cap = job.get("max_running")
    if cap is not None and sum(1 for each in running if each.get("kind") == job.get("kind")) >= cap:
        return False, "%d %s running, at most %d at once" % (cap, job.get("kind"), cap)
    if job["gpu"] and sum(1 for each in running if each["gpu"]) >= MAX_GPU_RUNNING:
        return False, "a GPU job is running"
    room = free_ram_gb - reserved_gb(running)
    if room < job["ram_gb"] + MARGIN_GB:
        return False, "%.1f GB free (%.1f GB owed to running jobs), %.1f + %.0f GB wanted" % (
            free_ram_gb, reserved_gb(running), job["ram_gb"], MARGIN_GB)
    if free_commit_gb is not None and free_commit_gb - reserved_commit_gb(running) < commit_of(job) + COMMIT_MARGIN_GB:
        return False, "commit: %.1f GB free (%.1f GB owed to running jobs), %.1f + %.0f GB wanted; a bigger pagefile raises it" % (
            free_commit_gb, reserved_commit_gb(running), commit_of(job), COMMIT_MARGIN_GB)
    if job["gpu"] and free_gpu_gb is not None and free_gpu_gb < job["gpu_gb"]:
        return False, "%.1f GB GPU free, %.1f GB wanted" % (free_gpu_gb, job["gpu_gb"])
    return True, ""


def uncounted(running):
    """How many running jobs are of an uncounted kind (394 amended (22))."""
    return sum(1 for each in running if KINDS.get(each.get("kind"), {}).get("uncounted"))


def counted(running):
    """The running jobs MAX_RUNNING counts: all but UNCOUNTED_MOST of an
    uncounted kind."""
    return len(running) - min(UNCOUNTED_MOST, uncounted(running))


def lean_row(table, kind):
    """[kind]'s lean variant (394 amended (9)) from the kinds [table]: its
    row (caps, exclusions) with its variant's estimates and runs, and
    "estimate" naming the variant; None when it has none."""
    variant = table[kind].get("lean")
    if not variant or variant not in table:
        return None
    measured = table[variant]
    row = dict(table[kind], kind=kind, ram_gb=measured["ram_gb"], commit_gb=commit_of(measured),
        runs_s=measured.get("runs_s", []), estimate=variant)
    row.pop("lean", None)
    return row


def queued_row(table, entry, default):
    """The row the queue [entry] is judged by, by those queued beside it:
    its kind's from [table] ([default] for a kind it lacks), or its lean
    variant's once its ticket says it went lean (394 amended (15)). Judged
    at the full suite's 15.4 + 8 GB, companions' lean take looked out of
    reach to the suites behind it, which went past it each time the one
    running ended (sound's, then economy's, 2026-10-25)."""
    kind = entry["kind"]
    if entry.get("estimate", kind) != kind and kind in table:
        lean = lean_row(table, kind)
        if lean is not None and lean["estimate"] == entry["estimate"]:
            return lean
    return dict(table.get(kind, default), kind=kind)


def due_row(table, entry, default, running, free_ram_gb, free_commit_gb=None, row=None, now=None):
    """The row the queue [entry] runs as at its turn (394 amended (27)): its
    queued_row ([row] if given), or its lean row while it has not gone lean
    and goes_lean says it would. A suite chooses lean only when it starts;
    till then those queued beside it (and its own waiter) judge it by what it
    would run as: a full suite out of reach would look passable (may_pass)
    to the suites behind it, which would go lean and start first."""
    row = queued_row(table, entry, default) if row is None else row
    kind = entry["kind"]
    if entry.get("estimate", kind) != kind or not row.get("lean"):
        return row
    lean = lean_row(table, kind)
    waited = (time.time() if now is None else now) - entry.get("queued", time.time() if now is None else now)
    return lean if goes_lean(row, lean, waited, running, free_ram_gb, free_commit_gb) else row


def judged_row(table, entry, default, running, free_ram_gb, free_commit_gb=None, now=None):
    """The queue [entry] as those behind it judge it: its due_row, with its
    tree and, if its waiter gave one, its --expect as "expect_s" (394
    amended (28))."""
    row = dict(due_row(table, entry, default, running, free_ram_gb, free_commit_gb, now=now), tree=entry["tree"])
    if entry.get("expect_s") is not None:
        row["expect_s"] = entry["expect_s"]
    return row


def at_least(table, row, why):
    """[why] for a full suite held by memory, with what it would run as at
    its turn: a full suite out of reach whose lean run is out of reach too is
    judged full, and its line said "18.4 + 8 GB wanted" while it would start
    lean at 6.4 (the coordinator and buildings, 11-11). Text only: the
    judging is unchanged."""
    if not why or "GB wanted" not in why or not row.get("lean") or row.get("estimate", row.get("kind")) != row.get("kind"):
        return why
    lean = lean_row(table, row["kind"])
    if lean is None:
        return why
    return "%s (it runs lean at its turn: %.1f + %.0f GB)" % (why, lean["ram_gb"], MARGIN_GB)


def holder_name(queue, place):
    """How a wait names the queue row at [place] that holds it: "the head,
    <tree> <kind>" for the first, else "<tree> <kind> (<n>th in the queue)"."""
    entry = queue[place]
    if place == 0:
        return "the head, %s %s" % (entry["tree"], entry["kind"])
    return "%s %s (%s in the queue)" % (entry["tree"], entry["kind"], _ordinal(place + 1))


def goes_lean(row, lean, waited_s, running, free_ram_gb, free_commit_gb=None):
    """Whether a job of [row] waiting [waited_s] runs as [lean] (its lean
    variant, or None): out of reach that long, and the lean one in reach.
    A wait on the queue, or on its own kind, never makes it lean. A kind
    marked "lean_first" waits no time first (394 amended (23)): it still runs
    full whenever the full run is in reach."""
    after = 0 if row.get("lean_first") else LEAN_AFTER_SECONDS
    return (lean is not None and waited_s >= after
        and out_of_reach(row, running, free_ram_gb, free_commit_gb)
        and not out_of_reach(lean, running, free_ram_gb, free_commit_gb))


def kind_blocked(job, running):
    """Whether [job] waits only on its own kind: one it excludes running, or
    as many of its kind as its max_running."""
    if any(each.get("kind") in job.get("excludes", []) for each in running):
        return True
    cap = job.get("max_running")
    return cap is not None and sum(1 for each in running if each.get("kind") == job.get("kind")) >= cap


def out_of_reach(job, running, free_ram_gb, free_commit_gb=None):
    """Whether [job] could not start even were every gated job done: its
    estimate and margin over free RAM plus what running jobs use (or the
    same for commit). It waits on memory held outside the gate (sessions,
    browsers, a model server), which no job in the queue gives back."""
    back = sum(each.get("using_gb", 0.0) for each in running)
    if free_ram_gb + back < job["ram_gb"] + MARGIN_GB:
        return True
    back = sum(each.get("using_commit_gb", each.get("using_gb", 0.0)) for each in running)
    return free_commit_gb is not None and free_commit_gb + back < commit_of(job) + COMMIT_MARGIN_GB


def may_pass(job, ahead, running, free_ram_gb=None, free_commit_gb=None, table=None, now=None, length_s=None):
    """Whether [job] may start though [ahead] (the rows queued before it)
    came first: none, or each is out of reach (out_of_reach: a 29 GB mesh
    job on a machine with 32 GB free held ten landings behind it), or waits
    only on its own kind (kind_blocked: a suite behind a suite, a bench
    beside one) and [job] is of another kind that neither excludes. A wait
    for memory the queue will give back, or for the running count, is first
    come first served for everyone: a big job is not starved; once in reach
    it holds those behind it again. With [table] (the kinds), [now] and
    [length_s] (backfill_length), it may also go past one it conflicts with
    when it ends first (backfill)."""
    return passes(job, ahead, running, free_ram_gb, free_commit_gb, table, now, length_s)[0]


def passes(job, ahead, running, free_ram_gb=None, free_commit_gb=None, table=None, now=None, length_s=None):
    """may_pass's answer as (ok, past, why): past, the rows [job] goes past by
    backfill, each with "due", when its blockers should end; why, when it
    may not, what backfill would have needed ("" if backfill never applied).

    A row ahead held only by the queue (394 amended (21)) counts as one held
    by kind: it may not start, as [job] may not, because a row before it
    waits on kind (a soak behind a bench behind a suite: the soak may not go
    past the bench, and nothing ran that excludes a soak). Before, it looked
    like a head waiting on memory and held all behind it: four scenes and
    six imports, allowed beside the suite running, waited behind economy's
    soak while 13.5 GB stood free (2026-11-04 10:00). The rows that hold it
    are ahead of [job] too, so [job] still meets each: a head waiting on
    memory or the count holds it, its own kind holds it, one it conflicts
    with only by backfill."""
    return passes_held(job, ahead, running, free_ram_gb, free_commit_gb, table, now, length_s)[:3]


def passes_held(job, ahead, running, free_ram_gb=None, free_commit_gb=None, table=None, now=None, length_s=None):
    """passes's answer and, when [job] may not start, the index in [ahead]
    of the row that holds it (394 amended (28)): (ok, past, why, holder),
    holder None when it may. Each row ahead is judged by its own length
    (backfill_length: its waiter's --expect, from its queue entry)."""
    held = []
    for other in ahead:
        held.append(kind_blocked(other, running) or not _passes(
            other, ahead[:len(held)], held, running, free_ram_gb, free_commit_gb, table, now, backfill_length(other))[0])
    return _passes(job, ahead, held, running, free_ram_gb, free_commit_gb, table, now, length_s)


def _passes(job, ahead, held, running, free_ram_gb, free_commit_gb, table, now, length_s):
    """passes over [ahead], [held] saying for each whether it waits on kind,
    its own or by those before it.

    One of [job]'s own kind ahead holds it only while that one waits on its
    kind (kind_blocked: its cap reached, or one it excludes running; 394
    amended (28)). Held otherwise, it waits on a row before it, which [job]
    meets too, or on its own length at a backfill: then a shorter job of
    the same kind may go first. Playtest's tour (--expect 25, 1500 s) could
    never go past terrain's bench while suites ran back to back, and every
    scene behind it waited 84 minutes (11-10)."""
    past = []
    for place, (other, waits) in enumerate(zip(ahead, held)):
        if free_ram_gb is not None and out_of_reach(other, running, free_ram_gb, free_commit_gb):
            continue
        if not waits:
            return False, [], "", place
        if other.get("kind") == job.get("kind") and kind_blocked(other, running):
            return False, [], "", place
        if conflicts(job, other):
            ok, due, why = may_backfill(other, running, table, now, length_s)
            if not ok:
                return False, [], why, place
            past.append(dict(other, due=due))
    return True, past, "", None


def conflicts(job, other):
    """Whether either of [job] and [other] excludes the other's kind."""
    return other.get("kind") in job.get("excludes", []) or job.get("kind") in other.get("excludes", [])


def median_s(runs):
    runs = sorted(runs)
    middle = len(runs) // 2
    return runs[middle] if len(runs) % 2 else (runs[middle - 1] + runs[middle]) / 2.0


def backfill_length(row, expect_minutes=None):
    """How long a job of [row] is counted on to run when it goes past
    another (backfill): its --expect, else its kind's longest recorded run
    times BACKFILL_MARGIN; None (never goes past) with neither. A row
    judged from a queue entry carries that waiter's --expect as "expect_s"
    (394 amended (28)): without it, those behind judged a 25-minute tour by
    its kind's 3.6-minute runs."""
    if expect_minutes is not None:
        return expect_minutes * 60.0
    if row.get("expect_s") is not None:
        return float(row["expect_s"])
    runs = row.get("runs_s", [])
    return max(runs) * BACKFILL_MARGIN if runs else None


def blockers(job, running):
    """The running jobs that keep [job] out by kind: those it excludes or
    that exclude it, and its own kind's once at its cap."""
    found = [each for each in running if conflicts(job, each)]
    cap = job.get("max_running")
    same = [each for each in running if each.get("kind") == job.get("kind")]
    if cap is not None and len(same) >= cap:
        found += same
    return found


def may_backfill(head, running, table, now, length_s):
    """Whether a job [length_s] long may start ahead of [head], which it
    conflicts with (394 amended (18)): [head] waits on kind alone and its
    blockers should end (each one's start plus its estimate's median run,
    from [table]) after the job would. A blocker with no runs recorded or
    past its median has no known end: nobody goes past. (ok, due, why):
    due, when the blockers should all have ended."""
    if table is None or now is None:
        return False, None, ""
    if length_s is None:
        return False, None, "going past it needs runs of this kind recorded"
    ends = []
    for each in blockers(head, running):
        runs = table.get(each.get("estimate", each.get("kind")), {}).get("runs_s", [])
        if not runs or each.get("started") is None:
            return False, None, "going past it needs the %s's runs recorded" % each.get("kind")
        end = each["started"] + median_s(runs)
        if end <= now:
            return False, None, "the %s running is past its usual length, its end unknown" % each.get("kind")
        ends.append(end)
    if not ends:
        return False, None, ""
    due = max(ends)
    if now + length_s > due:
        return False, None, "going past it needs %.0f s, the %s is due in %.0f s" % (
            length_s, "/".join(sorted(set(each.get("kind") for each in blockers(head, running)))), due - now)
    return True, due, ""


def short_of_memory(free_ram_gb, free_commit_gb=None):
    """What a running job is short of: "RAM" under MARGIN_GB, "commit" under
    COMMIT_STOP_GB (394 amended (16)), else ""."""
    if free_ram_gb < MARGIN_GB:
        return "RAM"
    if free_commit_gb is not None and free_commit_gb < COMMIT_STOP_GB:
        return "commit"
    return ""


def should_stop(me, running, free_ram_gb, free_commit_gb=None):
    """Whether the watched job [me] stops its child: free RAM is under the
    margin, or free commit under COMMIT_STOP_GB, and no running job started
    after it."""
    if not short_of_memory(free_ram_gb, free_commit_gb):
        return False
    return all(each["started"] <= me["started"] for each in running)


def shell_code(code):
    """A child's exit code as a shell sees it: 0 to 255, and never 0 when it
    failed. A Git Bash process killed by a signal hands Windows its wait
    status (signal 9: 2304, 9 << 8), which a shell takes modulo 256 as 0:
    economy's landing pushed 7504160b over a suite killed mid-run
    (2026-10-23). Such a status becomes 128 + the signal; any other code out
    of range (a negative NTSTATUS, a multiple of 256) becomes 1."""
    if 0 <= code <= 255:
        return code
    signal = (code >> 8) & 0x7F
    if code > 0 and code & 0xFF == 0 and 0 < signal < 65:
        return 128 + signal
    return code & 0xFF or 1


def limit_seconds(row, expect_minutes=None):
    """How long a run of [row]'s kind may hold the gate: [expect_minutes]
    when given, else OVERRUN_FACTOR times the median of its recorded runs
    ("runs_s"), never under the floor, else its max_minutes; None: no limit."""
    if expect_minutes is not None:
        return expect_minutes * 60.0
    if row.get("fixed_limit") and row.get("max_minutes") is not None:
        return row["max_minutes"] * 60.0  # A soak: its length is its own --days.
    runs = row.get("runs_s", [])
    if runs:
        return max(OVERRUN_FLOOR_SECONDS, OVERRUN_FACTOR * median_s(runs))
    if row.get("max_minutes") is not None:
        return row["max_minutes"] * 60.0
    return None


def hung(samples, now, started):
    """Whether a run is hung: running HUNG_SECONDS, and over the last
    HUNG_SECONDS of [samples] ((time, cpu seconds), oldest first) its CPU
    under HUNG_CPU of a core. Also the share, or None before it is known."""
    if now - started < HUNG_SECONDS:
        return False, None
    then = [each for each in samples if each[0] <= now - HUNG_SECONDS]
    if not then or samples[-1][1] is None or then[-1][1] is None:
        return False, None
    share = (samples[-1][1] - then[-1][1]) / max(1e-9, samples[-1][0] - then[-1][0])
    return share < HUNG_CPU, share


def short_command(command):
    """A process's command line for the peak listing: the program's name,
    not its path; a Godot's arguments less --path and its log file; at most
    160 characters."""
    words = command.split('"')
    if command.startswith('"') and len(words) > 2:
        program, rest = words[1], '"'.join(words[2:])
    else:
        program, _, rest = command.partition(" ")
    program = re.split(r"[\\/]", program)[-1]
    rest = re.sub(r'--log-file\s+("[^"]*"|\S+)\s*|--path\s+\S+\s*', "", rest).strip()
    return ("%s %s" % (program, rest)).strip()[:160]


def updated_estimate(old_gb, peak_gb):
    """A kind's estimate after a run that peaked at [peak_gb]: up to it at
    once, down toward it slowly."""
    return round(max(peak_gb, 0.8 * old_gb + 0.2 * peak_gb), 2)


def record_ram(saved, at_once_gb, peaks_gb):
    """[saved] (a kinds.json row) after a run that held [at_once_gb] at once
    and whose processes' own peaks summed to [peaks_gb] (394 amended (27)):
    each measure's estimate under updated_estimate, from ram_gb where it has
    none yet; ram_gb the one RAM_MEASURE names."""
    for field, measured, last in (("ram_once_gb", at_once_gb, "last_once_gb"), ("ram_peaks_gb", peaks_gb, "last_peak_gb")):
        if measured > 0.0:
            saved[field] = updated_estimate(saved.get(field, saved["ram_gb"]), measured)
            saved[last] = round(measured, 2)
    saved["ram_gb"] = saved.get(MEASURE_FIELDS[RAM_MEASURE], saved["ram_gb"])
    return saved


def seeded_once(kind, variant_of, lines):
    """[kind]'s at-once estimate from the log's [lines] (394 amended (27)):
    its last SEED_RUNS done lines with a working set at once (a variant's: its
    kind's lean ones), replayed under updated_estimate; None if it has none."""
    runs = []
    for line in lines:
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 5 or parts[1] != "done" or parts[3] != (variant_of or kind):
            continue
        if parts[4].endswith(", lean") != bool(variant_of):
            continue
        found = re.search(r"working set at once ([0-9.]+) GB", parts[4])
        if found:
            runs.append(float(found.group(1)))
    estimate = None
    for each in runs[-SEED_RUNS:]:
        estimate = each if estimate is None else updated_estimate(estimate, each)
    return estimate


def seed_measures():
    """Gives each measured kinds.json row its two estimates once (394 amended
    (27)): ram_peaks_gb its ram_gb (summed peaks till now), ram_once_gb from
    the log (seeded_once, else ram_gb), and ram_gb the one RAM_MEASURE names.
    Whether it wrote."""
    table = _read(_path("kinds.json")) or {}
    if all("ram_once_gb" in row for row in table.values() if "ram_gb" in row):
        return False
    with StateLock():
        table = _read(_path("kinds.json")) or {}
        lines = []
        try:
            with open(_path("heavy_jobs.log"), encoding="utf-8", errors="replace") as handle:
                lines = [line for line in handle if "\tdone\t" in line and "working set at once" in line]
        except OSError:
            pass
        wrote = False
        for name, row in table.items():
            if "ram_gb" not in row or "ram_once_gb" in row:
                continue
            row.setdefault("ram_peaks_gb", row["ram_gb"])
            once = seeded_once(name, KINDS.get(name, {}).get("variant_of"), lines)
            row["ram_once_gb"] = round(once, 2) if once is not None else row["ram_gb"]
            row["ram_gb"] = row[MEASURE_FIELDS[RAM_MEASURE]]
            wrote = True
        if wrote:
            _write(_path("kinds.json"), table)
            log("measure", "heavy_job", "kinds", "RAM estimates seeded, by %s: %s" % (RAM_MEASURE, ", ".join(
                "%s %.1f (summed peaks %.1f)" % (name, row["ram_once_gb"], row["ram_peaks_gb"])
                for name, row in sorted(table.items()) if "ram_once_gb" in row)))
        return wrote


# --- The machine -------------------------------------------------------------

def free_ram_gb():
    return _memory()[0]


def total_ram_gb():
    """The machine's physical RAM in GB, or None where not known."""
    if os.name == "nt":
        kilobytes = ctypes.c_ulonglong(0)
        if ctypes.windll.kernel32.GetPhysicallyInstalledSystemMemory(ctypes.byref(kilobytes)):
            return kilobytes.value / (1024.0 * 1024.0)
        return None
    try:
        with open("/proc/meminfo") as meminfo:
            for line in meminfo:
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) * 1024 / GB
    except OSError:
        pass
    return None


def _memory():
    """(free RAM, free commit) in GB; free commit, what Windows can still
    promise (RAM and pagefile) before allocations fail, None elsewhere."""
    if os.name == "nt":
        class Status(ctypes.Structure):
            _fields_ = [("length", ctypes.c_ulong), ("load", ctypes.c_ulong),
                ("total_phys", ctypes.c_ulonglong), ("avail_phys", ctypes.c_ulonglong),
                ("total_page", ctypes.c_ulonglong), ("avail_page", ctypes.c_ulonglong),
                ("total_virtual", ctypes.c_ulonglong), ("avail_virtual", ctypes.c_ulonglong),
                ("avail_extended", ctypes.c_ulonglong)]
        status = Status()
        status.length = ctypes.sizeof(Status)
        ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
        return status.avail_phys / GB, status.avail_page / GB
    with open("/proc/meminfo") as meminfo:
        for line in meminfo:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) * 1024 / GB, None
    return 0.0, None


def gpu_gb():
    """(free, used) GPU memory in GB, or (None, None) with no nvidia-smi."""
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=memory.free,memory.used", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=10).stdout.strip().splitlines()
        free, used = out[0].split(",")
        return float(free) / 1024.0, float(used) / 1024.0
    except (OSError, ValueError, IndexError, subprocess.SubprocessError):
        return None, None


def alive(pid, since=None):
    """Whether process [pid] runs, and, given [since] (its started_at when
    the entry was written), is still that process: an id Windows has given
    to another since (after a reboot, or a long day) is not (394 amended
    (8))."""
    if not pid:
        return False
    if os.name == "nt":
        kernel = ctypes.windll.kernel32
        kernel.OpenProcess.restype = ctypes.c_void_p
        handle = kernel.OpenProcess(0x1000, False, int(pid))  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        code = ctypes.c_ulong()
        kernel.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(code))
        kernel.CloseHandle(ctypes.c_void_p(handle))
        if code.value != 259:  # STILL_ACTIVE
            return False
    else:
        try:
            os.kill(int(pid), 0)
        except OSError:
            return False
    return since is None or started_at(pid) in (None, since)


class _Counters(ctypes.Structure):
    _fields_ = [("cb", ctypes.c_ulong), ("faults", ctypes.c_ulong),
        ("peak_working_set", ctypes.c_size_t), ("working_set", ctypes.c_size_t),
        ("quota_peak_paged", ctypes.c_size_t), ("quota_paged", ctypes.c_size_t),
        ("quota_peak_nonpaged", ctypes.c_size_t), ("quota_nonpaged", ctypes.c_size_t),
        ("pagefile", ctypes.c_size_t), ("peak_pagefile", ctypes.c_size_t)]


def process_memory(pid):
    """Process [pid]'s (working set, commit, peak working set, peak
    commit) in GB, as Windows counts them; None if it is not to be read."""
    if not pid or os.name != "nt":
        return None
    kernel = ctypes.windll.kernel32
    kernel.OpenProcess.restype = ctypes.c_void_p
    process = kernel.OpenProcess(0x1000 | 0x0010, False, int(pid))  # QUERY_LIMITED | VM_READ
    if not process:
        return None
    counters = _Counters()
    counters.cb = ctypes.sizeof(counters)
    ok = kernel.K32GetProcessMemoryInfo(ctypes.c_void_p(process), ctypes.byref(counters), counters.cb)
    kernel.CloseHandle(ctypes.c_void_p(process))
    if not ok:
        return None
    return (counters.working_set / GB, counters.pagefile / GB, counters.peak_working_set / GB, counters.peak_pagefile / GB)


def measure_attached(entry, read=process_memory):
    """A take's [entry] with its attached processes (394 amended (20))
    read by [read] (process_memory): its using_gb and using_commit_gb their
    sums now, attached_peak_gb and attached_peak_commit_gb the most seen
    (their own peak counters); one gone, or its id reused, counts nothing.
    Whether the entry changed."""
    if not entry.get("attached"):
        return False
    using, commit = 0.0, 0.0
    peak, peak_commit = entry.get("attached_peak_gb", 0.0), entry.get("attached_peak_commit_gb", 0.0)
    for each in entry["attached"]:
        if not alive(each.get("pid"), each.get("since")):
            continue
        numbers = read(each["pid"])
        if numbers is None:
            continue
        using += numbers[0]
        commit += numbers[1]
        each["peak_gb"] = max(each.get("peak_gb", 0.0), numbers[2])
        each["peak_commit_gb"] = max(each.get("peak_commit_gb", 0.0), numbers[3])
    peak = max(peak, sum(each.get("peak_gb", 0.0) for each in entry["attached"]))
    peak_commit = max(peak_commit, sum(each.get("peak_commit_gb", 0.0) for each in entry["attached"]))
    # At once (394 amended (27)): their sum now, never under one's own peak.
    entry["attached_once_gb"] = round(max(entry.get("attached_once_gb", 0.0), using,
        max([each.get("peak_gb", 0.0) for each in entry["attached"]] or [0.0])), 3)
    now = (round(using, 3), round(commit, 3), round(peak, 3), round(peak_commit, 3))
    was = (entry.get("using_gb"), entry.get("using_commit_gb"), entry.get("attached_peak_gb"), entry.get("attached_peak_commit_gb"))
    entry["using_gb"], entry["using_commit_gb"], entry["attached_peak_gb"], entry["attached_peak_commit_gb"] = now
    return now != was


def started_at(pid):
    """When process [pid] was created, as Windows counts it (100 ns since
    1601), or None (not Windows, or not to be read)."""
    if not pid or os.name != "nt":
        return None
    kernel = ctypes.windll.kernel32
    kernel.OpenProcess.restype = ctypes.c_void_p
    handle = kernel.OpenProcess(0x1000, False, int(pid))
    if not handle:
        return None
    times = [ctypes.c_ulonglong() for _ in range(4)]
    ok = kernel.GetProcessTimes(ctypes.c_void_p(handle), *[ctypes.byref(each) for each in times])
    kernel.CloseHandle(ctypes.c_void_p(handle))
    return times[0].value if ok else None


def ancestors(pid):
    """[pid] and its ancestors' ids, nearest first (394 amended (11)). A
    parent counts only if it was created before its child: a dead parent's
    id given to a newer process is no ancestor. Windows (a Toolhelp
    snapshot) or /proc; elsewhere [pid] alone."""
    parents = {}
    if os.name == "nt":
        class Entry(ctypes.Structure):
            _fields_ = [("size", ctypes.c_ulong), ("usage", ctypes.c_ulong), ("pid", ctypes.c_ulong),
                ("heap", ctypes.c_size_t), ("module", ctypes.c_ulong), ("threads", ctypes.c_ulong),
                ("parent", ctypes.c_ulong), ("priority", ctypes.c_long), ("flags", ctypes.c_ulong),
                ("exe", ctypes.c_wchar * 260)]
        kernel = ctypes.windll.kernel32
        kernel.CreateToolhelp32Snapshot.restype = ctypes.c_void_p
        snapshot = kernel.CreateToolhelp32Snapshot(0x2, 0)  # TH32CS_SNAPPROCESS
        if snapshot and snapshot != ctypes.c_void_p(-1).value:
            entry = Entry()
            entry.size = ctypes.sizeof(Entry)
            more = kernel.Process32FirstW(ctypes.c_void_p(snapshot), ctypes.byref(entry))
            while more:
                parents[entry.pid] = entry.parent
                more = kernel.Process32NextW(ctypes.c_void_p(snapshot), ctypes.byref(entry))
            kernel.CloseHandle(ctypes.c_void_p(snapshot))
    out = [int(pid)]
    while len(out) < 64:
        child = out[-1]
        if os.name == "nt":
            parent = parents.get(child)
        else:
            try:
                with open("/proc/%d/stat" % child) as stat:
                    parent = int(stat.read().rsplit(")", 1)[1].split()[1])
            except (OSError, ValueError, IndexError):
                parent = None
        if not parent or parent in out:
            break
        born, parent_born = started_at(child), started_at(parent)
        if born is not None and (parent_born is None or parent_born > born):
            break
        out.append(parent)
    return out


def boot_time():
    """When this machine last started (time.time() seconds), or 0.0 where
    not known: an entry queued before it is from before a reboot."""
    if os.name != "nt":
        return 0.0
    ctypes.windll.kernel32.GetTickCount64.restype = ctypes.c_ulonglong
    return time.time() - ctypes.windll.kernel32.GetTickCount64() / 1000.0


class Job:
    """[child] (this wrapper's own) and every process it starts, in a
    Windows job object: they join it as they are made, whatever runs them
    (a shell's background subshells, timeout, an exec), so the job's memory
    is theirs and stopping it stops them all. Elsewhere, the child alone."""

    def __init__(self, child):
        self.child = child
        self.handle = None
        if os.name == "nt":
            kernel = ctypes.windll.kernel32
            kernel.CreateJobObjectW.restype = ctypes.c_void_p
            handle = kernel.CreateJobObjectW(None, None)
            if handle and kernel.AssignProcessToJobObject(ctypes.c_void_p(handle), ctypes.c_void_p(int(child._handle))):
                self.handle = handle

    class _Ids(ctypes.Structure):
        _fields_ = [("assigned", ctypes.c_ulong), ("listed", ctypes.c_ulong), ("ids", ctypes.c_size_t * 1024)]

    def _ids(self):
        """The job's live processes' ids (JobObjectBasicProcessIdList)."""
        if self.handle is None:
            return []
        ids = self._Ids()
        if not ctypes.windll.kernel32.QueryInformationJobObject(ctypes.c_void_p(self.handle), 3, ctypes.byref(ids),
                ctypes.sizeof(ids), None):
            return []
        return [int(ids.ids[i]) for i in range(ids.listed)]

    def processes(self):
        """How many of the job's processes still run."""
        return len(self._ids())

    def listing(self):
        """The job's live processes now, biggest first: (private commit GB,
        working set GB, command line) each (394 amended (10))."""
        ids = self._ids()
        if not ids:
            return []
        kernel = ctypes.windll.kernel32
        sizes = {}
        for pid in ids:
            process = kernel.OpenProcess(0x1000 | 0x0010, False, pid)
            if not process:
                continue
            counters = self._Counters()
            counters.cb = ctypes.sizeof(counters)
            if kernel.K32GetProcessMemoryInfo(ctypes.c_void_p(process), ctypes.byref(counters), counters.cb):
                sizes[pid] = (counters.pagefile / GB, counters.working_set / GB)
            kernel.CloseHandle(ctypes.c_void_p(process))
        lines = {}
        try:
            found = subprocess.run(["powershell.exe", "-NoProfile", "-Command",
                "Get-CimInstance Win32_Process -Filter '%s' | ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }"
                % " OR ".join("ProcessId=%d" % pid for pid in sizes)], capture_output=True, text=True, timeout=20)
            for line in found.stdout.splitlines():
                pid, _, command = line.partition("\t")
                if pid.strip().isdigit():
                    lines[int(pid)] = command.strip()
        except (OSError, subprocess.SubprocessError):
            pass
        return sorted(((private, working, short_command(lines.get(pid, "pid %d" % pid)))
            for pid, (private, working) in sizes.items()), reverse=True)

    _Counters = _Counters

    def using_gb(self):
        """The working set of the job's processes now."""
        return self.memory()[0]

    def memory(self):
        """The job's live processes' (working set now, commit now, the sum of
        their own peak working sets, the largest one process's own peak), GB.
        The peaks catch what a watch every WATCH_SECONDS misses (a model's
        weights read on the CPU a moment before they go to the card); the
        largest one is a floor under the working set at once (394 amended
        (27)): when it peaked, the job held at least that."""
        if self.handle is None:
            return 0.0, 0.0, 0.0, 0.0
        kernel = ctypes.windll.kernel32
        Counters = self._Counters
        kernel.OpenProcess.restype = ctypes.c_void_p
        total, commit, peaks, top = 0, 0, 0, 0
        for pid in self._ids():
            process = kernel.OpenProcess(0x1000 | 0x0010, False, pid)  # QUERY_LIMITED | VM_READ
            if not process:
                continue
            counters = Counters()
            counters.cb = ctypes.sizeof(Counters)
            if kernel.K32GetProcessMemoryInfo(ctypes.c_void_p(process), ctypes.byref(counters), counters.cb):
                total += counters.working_set
                commit += counters.pagefile
                peaks += counters.peak_working_set
                top = max(top, counters.peak_working_set)
            kernel.CloseHandle(ctypes.c_void_p(process))
        return total / GB, commit / GB, peaks / GB, top / GB

    def peak_gb(self):
        """The most memory the job's processes held at once (committed), as
        Windows counted it."""
        if self.handle is None:
            return 0.0

        class Limits(ctypes.Structure):
            _fields_ = [("user_time", ctypes.c_longlong), ("job_user_time", ctypes.c_longlong), ("flags", ctypes.c_ulong),
                ("min_ws", ctypes.c_size_t), ("max_ws", ctypes.c_size_t), ("processes", ctypes.c_ulong),
                ("affinity", ctypes.c_size_t), ("priority", ctypes.c_ulong), ("scheduling", ctypes.c_ulong),
                ("io", ctypes.c_ulonglong * 6), ("process_limit", ctypes.c_size_t), ("job_limit", ctypes.c_size_t),
                ("peak_process", ctypes.c_size_t), ("peak_job", ctypes.c_size_t)]
        limits = Limits()
        if not ctypes.windll.kernel32.QueryInformationJobObject(ctypes.c_void_p(self.handle), 9, ctypes.byref(limits),
                ctypes.sizeof(limits), None):  # 9: JobObjectExtendedLimitInformation
            return 0.0
        return limits.peak_job / GB

    def cpu_seconds(self):
        """The CPU time (user and kernel) the job's processes have used, the
        ended ones' too; None when not known."""
        if self.handle is None:
            return None

        class Accounting(ctypes.Structure):
            _fields_ = [("user", ctypes.c_longlong), ("kernel", ctypes.c_longlong),
                ("period_user", ctypes.c_longlong), ("period_kernel", ctypes.c_longlong),
                ("faults", ctypes.c_ulong), ("processes", ctypes.c_ulong), ("active", ctypes.c_ulong),
                ("terminated", ctypes.c_ulong)]
        accounting = Accounting()
        if not ctypes.windll.kernel32.QueryInformationJobObject(ctypes.c_void_p(self.handle), 1, ctypes.byref(accounting),
                ctypes.sizeof(accounting), None):  # 1: JobObjectBasicAccountingInformation
            return None
        return (accounting.user + accounting.kernel) / 1e7  # 100 ns units

    def stop(self):
        """Stops the child and everything it started."""
        if self.handle is not None:
            ctypes.windll.kernel32.TerminateJobObject(ctypes.c_void_p(self.handle), 1)
        else:
            self.child.kill()

    def close(self):
        if self.handle is not None:
            ctypes.windll.kernel32.CloseHandle(ctypes.c_void_p(self.handle))
            self.handle = None


# --- State --------------------------------------------------------------------

def _path(*parts):
    return os.path.join(STATE_DIR, *parts)


class StateLock:
    """The state's own lock, held for a moment while files change."""

    def __enter__(self):
        os.makedirs(_path("running"), exist_ok=True)
        os.makedirs(_path("queue"), exist_ok=True)
        lock = _path("state.lock")
        denied_since = None
        while True:
            try:
                os.close(os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY))
                return self
            except PermissionError:
                # Windows: the lock is being deleted (its holder's __exit__)
                # or a scanner has it open a moment: busy, as FileExistsError.
                # Still denied after LOCK_STALE_SECONDS is a real fault.
                denied_since = denied_since or time.time()
                if time.time() - denied_since > LOCK_STALE_SECONDS:
                    raise
                time.sleep(0.05)
            except FileExistsError:
                denied_since = None
                try:
                    if time.time() - os.path.getmtime(lock) > LOCK_STALE_SECONDS:
                        os.remove(lock)
                        continue
                except OSError:
                    pass
                time.sleep(0.05)

    def __exit__(self, *_):
        try:
            os.remove(_path("state.lock"))
        except OSError:
            pass


def _read(path):
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def _write(path, data):
    temp = path + ".tmp"
    with open(temp, "w") as handle:
        json.dump(data, handle)
    _retried(os.replace, temp, path)


def _retried(action, *paths):
    """[action] (os.replace, os.remove) on [paths], tried again for a second
    while Windows says the file is in use: something (a scanner, a reader)
    has it open a moment. A waiter's rename to the back of the queue failed
    so once and ended the waiter (ui's landing, 2026-10-24)."""
    for attempt in range(20):
        try:
            return action(*paths)
        except PermissionError:
            time.sleep(0.05)
    return action(*paths)


def kinds():
    saved = _read(_path("kinds.json")) or {}
    table = {}
    for name, first in KINDS.items():
        row = dict(first, **saved.get(name, {}))
        if name not in saved and "commit_gb" not in first:
            row["commit_gb"] = round(UNMEASURED_COMMIT_FACTOR * first["ram_gb"], 2)
        # Exclusions the code adds (a bench never beside a soak or a scene) hold over a
        # kinds.json written before them.
        row["excludes"] = sorted(set(first.get("excludes", [])) | set(saved.get(name, {}).get("excludes", [])))
        if not row["excludes"]:
            del row["excludes"]
        # The measure's own estimate (394 amended (27)), over a ram_gb an older
        # heavy_job.py wrote from summed peaks.
        if MEASURE_FIELDS[RAM_MEASURE] in row:
            row["ram_gb"] = row[MEASURE_FIELDS[RAM_MEASURE]]
        table[name] = _split(row, first["ram_gb"])
    for name, row in saved.items():
        table.setdefault(name, _split(dict(row), 0.0))
    return table


def _split(row, floor_gb):
    """A row measured before RAM and commit were told apart (one ram_gb,
    the larger of the two): that was its commit. A GPU kind's RAM is then
    taken as that less its GPU estimate (what it put on the card), never
    under [floor_gb] (its first estimate): trellis_mesh's 28.9 GB was about
    5 GB of RAM and 23.6 on the card. The next run measures both."""
    if "commit_gb" not in row:
        row["commit_gb"] = row["ram_gb"]
        if row.get("gpu"):
            row["ram_gb"] = round(max(floor_gb, row["ram_gb"] - row.get("gpu_gb", 0.0)), 2)
    return row


def _entries(folder):
    """The live entries of running/ or queue/, oldest first; stale ones
    (their process gone, or a running take past TAKE_STALE_SECONDS)
    removed."""
    out = []
    booted = boot_time()
    for name in sorted(os.listdir(_path(folder))):
        if not name.endswith(".json"):
            continue
        entry = _read(_path(folder, name))
        if entry is None:
            continue
        pid = entry.get("pid")
        # Each id with its process's start time, where the entry has one: an
        # id reused by another process is not its holder (394 amended (8)).
        stale = bool(pid) and not alive(pid, entry.get("pid_since"))
        stale = stale or entry.get("queued", booted) < booted  # From before a reboot.
        if folder == "queue" and entry.get("waiter"):
            stale = stale or not alive(entry["waiter"], entry.get("waiter_since"))
        # A real adoption (a run of land.sh's, alive) shields a take; the guard
        # (394 amended (37)), its holder named as adopter for older code's
        # check, does not: here the beats decide.
        adopted = not entry.get("guard") and alive(entry.get("adopted_by"), entry.get("adopted_since"))
        if folder == "running" and not entry.get("watched") and not adopted:
            held_since = max(entry.get("started", entry["queued"]), entry.get("beat", 0.0))
            stale = stale or time.time() - held_since > TAKE_STALE_SECONDS
        if stale:
            os.remove(_path(folder, name))
            log("stale", entry["tree"], entry["kind"], "%s dropped" % folder)
            continue
        if folder == "running" and not entry.get("watched") and measure_attached(entry):
            _write(_path(folder, name), entry)
        entry["file"] = name
        out.append(entry)
    _note_odd(folder, out)
    if folder == "queue":
        out.sort(key=_order)  # A fronted entry's "order" puts it first (394 amended (25)).
    return out


def older_code(entry):
    """Whether [entry] was written by gate code known to be older than this:
    a lower GATE_REVISION. An entry with none was written before 394 amended
    (37), by code from before 31 (which drops landing takes at 30 minutes) or
    from 31 to 36 (which does not): the same on disk, so it is not named
    (394 amended (38)); unrevised() counts them."""
    return "gate" in entry and entry["gate"] < GATE_REVISION


def unrevised(entry):
    """Whether [entry] carries no GATE_REVISION: written before 394 amended
    (37), its code's age unknown (394 amended (38))."""
    return "gate" not in entry


def unbeaten(entry, now=None):
    """Whether [entry], a landing's take (not a run), has gone
    UNBEATEN_SECONDS since its start with no beat and no run adopting it."""
    if entry.get("watched") or not landing_kind(entry["kind"]) or entry.get("beat"):
        return False
    if not entry.get("guard") and entry.get("adopted_by"):
        return False
    return (now or time.time()) - entry.get("started", entry.get("queued", 0.0)) > UNBEATEN_SECONDS


def _where(entry):
    return entry.get("checkout") or "its checkout unknown (written before 394 amended (37))"


def _note_odd(folder, entries):
    """Logs, once each, an entry written by older gate code (old_gate) and a
    landing's take gone unbeaten (unbeaten): the daily summary's counts by
    tree. Under the state lock, as _entries is."""
    odd = []
    for entry in entries:
        if older_code(entry):
            odd.append(("old_gate", entry, "%s, pid %s, gate revision %s, %s; rebase it (394 amended (38))" % (
                folder, entry.get("waiter") if folder == "queue" else entry.get("pid"), entry["gate"], _where(entry))))
        if folder == "running" and unbeaten(entry):
            odd.append(("unbeaten", entry, "held %.0f min, since %s, with no beat from its land lock tries, pid %s, %s" % (
                (time.time() - entry.get("started", 0.0)) / 60, time.strftime("%H:%M", time.localtime(entry.get("started", 0.0))),
                entry.get("pid"), _where(entry))))
    if not odd:
        return
    noted = _read(_path(NOTED_FILE)) or {}
    changed = False
    for event, entry, detail in odd:
        key = "%s:%s:%s" % (event, folder, entry["file"])
        if key in noted:
            continue
        noted[key] = time.time()
        changed = True
        log(event, entry["tree"], entry["kind"], detail)
    if changed:
        day = time.time() - 86400
        _write(_path(NOTED_FILE), {key: when for key, when in noted.items() if when > day})


def guard_holder(pid, caller):
    """The process a take's guard names (394 amended (37)): its --pid, else
    its caller's (heavy_job.sh passes the shell that ran it: `take` itself
    ends at once, and a dead adopter shields nothing), else this process's
    parent. (pid, its start time) or (None, None)."""
    for each in (pid, caller):
        if each and alive(each):
            return int(each), started_at(each)
    chain = ancestors(os.getpid())
    if len(chain) > 1:
        return chain[1], started_at(chain[1])
    return None, None


def guard(entry, holder, since):
    """[entry], a take, shielded from older code's stale check (394 amended
    (37)): before 31 it dropped a take 30 minutes after its start, beaten or
    not, unless its adopted_by process lived. The holder is named so; new
    code ignores a guard (the beats decide), and older code drops it only
    once the holder has died."""
    if holder:
        entry.update({"adopted_by": holder, "adopted_since": since, "guard": True, "guard_by": holder, "guard_since": since})
    return entry


def _order(entry):
    """A queue entry's place: its "order" when release has fronted it, else
    when it queued (its ticket's leading nanoseconds)."""
    order = entry.get("order")
    if order is not None:
        return order
    head = entry["file"].split("-")[0]
    return int(head) if head.isdigit() else 0


def log(event, tree, kind, detail=""):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(_path("heavy_jobs.log"), "a") as handle:
        handle.write("%s\t%s\t%s\t%s\t%s\n" % (datetime.datetime.now().isoformat(timespec="seconds"), event, tree, kind, detail))


# --- Commands -----------------------------------------------------------------

## The swap (394 amended (33)): a take of "suite" whose landing saturn would
## run is granted as suite_remote, asked "suite". The probe is the landing's own
## `tools/remote_tests.sh kind`, run in the taker's checkout, at most once a
## minute and only when the row could start as either; PROBE_SECONDS caps it,
## and anything but a prompt "suite_remote" (a hang, an error, no script,
## LAND_LOCAL=1) leaves the row a suite, waiting as before.
PROBE_COMMAND = ["bash", "tools/remote_tests.sh", "kind"]
PROBE_SECONDS = 8.0
PROBE_EVERY_SECONDS = 60.0


def saturn_answers():
    """Whether the landing in this checkout would run on saturn now: True
    only on a prompt "suite_remote" from PROBE_COMMAND."""
    if os.environ.get("LAND_LOCAL"):
        return False
    if PROBE_COMMAND[:2] == ["bash", "tools/remote_tests.sh"] and not os.path.isfile(PROBE_COMMAND[1]):
        return False
    try:
        done = subprocess.run(PROBE_COMMAND, stdin=subprocess.DEVNULL, capture_output=True, text=True,
            timeout=PROBE_SECONDS)
    except (subprocess.TimeoutExpired, OSError):
        return False
    return done.returncode == 0 and done.stdout.strip().splitlines()[-1:] == ["suite_remote"]


def wait_turn(tree, kind, pid, watched, expect_minutes=None, caller=None):
    """Queues, waits to be at the head with room, then moves to running.
    Returns the running entry's file name and the kind whose estimate it
    holds: [kind], or its lean variant (goes_lean). [expect_minutes]: how
    long it says it runs, counted on if it goes past another (backfill)."""
    row = dict(kinds()[kind], kind=kind)
    estimate = kind
    total = total_ram_gb()
    if total is not None and row["ram_gb"] + MARGIN_GB > total:
        print("heavy_job: %s %s wants %.1f + %.0f GB, more than this machine's %.0f GB of RAM: it could never start; "
            "not queued (lower its estimate in kinds.json if that is wrong)" % (tree, kind, row["ram_gb"], MARGIN_GB, total),
            file=sys.stderr)
        log("refused", tree, kind, "%.1f + %.0f GB over %.0f GB of RAM" % (row["ram_gb"], MARGIN_GB, total))
        raise SystemExit(4)
    queued = time.time()
    ticket = "%019d-%s-%s.json" % (time.time_ns(), tree, pid or os.getpid())
    with StateLock():
        # "waiter": this wrapper, which waits for the turn; a take's pid (its
        # holder) may be none, and a queue file whose waiter died is dropped.
        # "expect_s": its --expect, for those behind it to judge its length
        # by (backfill_length, 394 amended (28)).
        _write(_path("queue", ticket), dict({"tree": tree, "kind": kind, "pid": pid, "pid_since": started_at(pid),
            "waiter": os.getpid(), "waiter_since": started_at(os.getpid()), "queued": queued,
            "gate": GATE_REVISION, "checkout": CHECKOUT},
            **({"expect_s": expect_minutes * 60.0} if expect_minutes is not None else {})))
    said = 0.0
    long_logged = False
    # Since when only backfilled jobs have kept this one out (394 amended
    # (18)): its wait from then is the backfill's cost, logged as late. Only
    # while it is first in the queue: a job further back waits on those
    # ahead of it too, and every waiter's late counted the same minutes again.
    held_by_backfill = None
    # Since when it has been first in the queue: a long wait is mostly the
    # queue ahead of it, its time at the head what held it alone.
    head_since = None
    # The swap (394 amended (33)): a take of suite only, never under LAND_LOCAL.
    may_swap = kind == "suite" and not watched and not os.environ.get("LAND_LOCAL")
    probed_at, answered = None, False
    swapped = None
    while True:
        with StateLock():
            queue = _entries("queue")
            running = _entries("running")
            free_gpu, _ = gpu_gb() if row["gpu"] else (None, None)
            if not any(each["file"] == ticket for each in queue):
                # Dropped as stale: its pid is no live Windows process (Git
                # Bash's $$ is not one), so it would wait forever.
                print("heavy_job: %s %s: its place in the queue was dropped (pid %s is no live process); not waiting" % (
                    tree, kind, pid), file=sys.stderr)
                raise SystemExit(3)
            place = next((i for i, each in enumerate(queue) if each["file"] == ticket), 0) + 1
            table = kinds()
            # Its own estimate as kinds.json has it now (394 amended (24)), its
            # lean variant's once it has gone lean: not the one read when it
            # queued. A scene queued the second one heavy scene raised the
            # kind's estimate to 13.6 GB judged itself by that while the
            # estimate fell to 4.4, and held nine scenes behind it (11-09).
            if kind in table:
                fresh = dict(table[kind], kind=kind) if estimate == kind else lean_row(table, kind)
                if fresh is not None:
                    row = fresh
            free_ram, free_commit = _memory()
            # First in the queue, or every job before it waits on its own
            # kind alone (may_pass): an import is not held behind a suite
            # waiting for a suite. Each judged as it would run at its turn
            # (due_row, 394 amended (27)).
            ahead = [judged_row(table, each, row, running, free_ram, free_commit) for each in queue[:place - 1]]
            # Lean is chosen when it would start, not at its first look (394
            # amended (27)): till then a suite out of reach is judged as its lean
            # row and stays full, so room at its turn starts it full. Chosen at
            # entry, the 10:36 suites (11-10) went lean at 23-25 GB free with a
            # suite running and stayed lean for the two hours to their turns.
            full = row
            if estimate == kind:
                row = due_row(table, {"kind": kind, "queued": queued}, row, running, free_ram, free_commit, row)
            now = time.time()
            if place == 1 and head_since is None:
                head_since = now
                entry = _read(_path("queue", ticket))
                if entry is not None:
                    entry["head_since"] = head_since
                    _write(_path("queue", ticket), entry)
            head, past, past_why, holder = passes_held(row, ahead, running, free_ram, free_commit, table, now,
                backfill_length(row, expect_minutes))
            ok, why = decide(row, running, head, free_ram, free_gpu, free_commit)
            why = at_least(table, row, why)
            swapped = None
            probe_now = False
            if may_swap and "suite_remote" in table:
                # Judged as suite_remote too; saturn asked only when that
                # row could start, outside the state lock (below).
                remote_row = dict(table["suite_remote"], kind="suite_remote")
                r_head, r_past, _, _ = passes_held(remote_row, ahead, running, free_ram, free_commit, table, now,
                    backfill_length(remote_row, expect_minutes))
                r_ok, _ = decide(remote_row, running, r_head, free_ram, None, free_commit)
                fresh = probed_at is not None and now - probed_at < PROBE_EVERY_SECONDS
                if r_ok and fresh and answered:
                    swapped = remote_row
                    ok, head, past, why = True, r_head, r_past, ""
                elif r_ok and not fresh:
                    probe_now = True
                    ok, why = False, "asking saturn (tools/remote_tests.sh kind)"
            if ok and swapped is None and row is not full:
                estimate = row["estimate"]
                entry = _read(_path("queue", ticket))
                if entry is not None:
                    entry["estimate"] = estimate
                    _write(_path("queue", ticket), entry)
                log("lean", tree, kind, "out of reach %.0f s at %.1f GB free: runs as %s, %.1f GB; at its turn, full %.1f + %.0f GB%s" % (
                    time.time() - queued, free_ram, estimate, row["ram_gb"], full["ram_gb"], MARGIN_GB, measures(full)))
                print("heavy_job: %s %s out of reach (memory held outside the gate): runs lean, as %s (%.1f + %.0f GB)" % (
                    tree, kind, estimate, row["ram_gb"], MARGIN_GB), file=sys.stderr)
            stuck = blockers(row, running)
            if place == 1 and stuck and all(each.get("backfill") for each in stuck):
                held_by_backfill = held_by_backfill or now
            elif stuck or place != 1:
                held_by_backfill = None
            if not ok and head and out_of_reach(row, running, free_ram, free_commit):
                # It keeps its place (a bug in 394 amended (28), release's
                # report): jobs that fit go past it (_passes), and it no
                # longer steps to the back. At 20:37 11-10 a model loaded
                # outside the gate put every queued suite out of reach; each
                # in turn found all ahead out of reach, stepped to the back
                # in the order its waiter looked, and physics and items,
                # queued first, ended 13th and 14th. The step was for waiters
                # from a heavy_job.py older than 10-18's rule, none left.
                why += "; out of reach even with no heavy job running (memory held outside the gate): jobs that fit go past it"
            if not head and holder is not None:
                # The row that holds it (394 amended (28)), not always the
                # head: playtest's tour, 8th, held the scenes behind it while
                # each said it waited on the head, a suite.
                other = ahead[holder]
                _, other_why = decide(other, running, True, free_ram, gpu_gb()[0] if other["gpu"] else None, free_commit)
                other_why = at_least(table, other, other_why)
                why = "%s, waits on: %s" % (holder_name(queue, holder), other_why or "its next look")
                if past_why:
                    why += "; %s" % past_why
            if ok and swapped is not None:
                _retried(os.remove, _path("queue", ticket))
                name = "%s-%s-%s.json" % (tree, "suite_remote", pid or os.getpid())
                entry = {"tree": tree, "kind": "suite_remote", "asked": kind, "pid": pid, "pid_since": started_at(pid),
                    "queued": queued, "started": time.time(), "ram_gb": swapped["ram_gb"], "commit_gb": commit_of(swapped),
                    "gpu": False, "using_gb": 0.0, "using_commit_gb": 0.0, "watched": watched, "estimate": "suite_remote"}
                if past:
                    entry["backfill"] = {"past": ", ".join("%s %s" % (each["tree"], each["kind"]) for each in past),
                        "due": min(each["due"] for each in past)}
                _write(_path("running", name), entry)
                waited = time.time() - queued
                log("start", tree, "suite_remote", "asked suite, saturn answers (394 amended (33))" + (
                    "; waited %.0f s" % waited if waited >= POLL_SECONDS else ""))
                print("heavy_job: %s suite: saturn answers, taken as suite_remote (the Godot parts on saturn)" % tree,
                    file=sys.stderr)
                return name, "suite_remote"
            if ok:
                _retried(os.remove, _path("queue", ticket))
                name = "%s-%s-%s.json" % (tree, kind, pid or os.getpid())
                entry = {"tree": tree, "kind": kind, "pid": pid, "pid_since": started_at(pid), "queued": queued,
                    "started": time.time(), "ram_gb": row["ram_gb"], "commit_gb": commit_of(row), "gpu": row["gpu"], "using_gb": 0.0,
                    "using_commit_gb": 0.0, "watched": watched, "estimate": estimate,
                    "gate": GATE_REVISION, "checkout": CHECKOUT}
                if not watched:
                    guard(entry, *guard_holder(pid, caller))
                if past:
                    # Gone past these by backfill (394 amended (18)): due
                    # to end before their blockers do.
                    entry["backfill"] = {"past": ", ".join("%s %s" % (each["tree"], each["kind"]) for each in past),
                        "due": min(each["due"] for each in past)}
                    log("backfill", tree, kind, "past %s, waiting on %s due in %.0f s; expects %.0f s" % (
                        entry["backfill"]["past"], "/".join(sorted(set(each.get("kind") for each in stuck_of(past, running)))),
                        entry["backfill"]["due"] - now, backfill_length(row, expect_minutes)))
                if held_by_backfill is not None and now - held_by_backfill >= POLL_SECONDS:
                    log("backfill_late", tree, kind, "waited %.0f s after its blockers ended, on jobs that went past it" % (
                        now - held_by_backfill))
                _write(_path("running", name), entry)
                waited = time.time() - queued
                lean = ", lean" if estimate != kind else ""
                at_head = " (%.0f s of it first in the queue)" % (now - head_since) if head_since is not None else ""
                log("start", tree, kind, ("waited %.0f s%s" % (waited, at_head) if waited >= POLL_SECONDS else "") + lean)
                if waited >= POLL_SECONDS:
                    print("heavy_job: %s %s starts after waiting %.0f s%s" % (tree, kind, waited, lean), file=sys.stderr)
                return name, estimate
        if probe_now:
            answered = saturn_answers()
            probed_at = time.time()
            continue
        waited = time.time() - queued
        if time.time() - said >= 60.0:
            said = time.time()
            print("heavy_job: %s %s waiting %.0f min, %s of %d in the queue: %s (the machine, not this script; heavy_job status shows the rest)" % (
                tree, kind, waited / 60, _ordinal(place), len(queue), why), file=sys.stderr)
        if waited >= LONG_WAIT_SECONDS and not long_logged:
            long_logged = True
            log("waiting", tree, kind, "%.0f s, %s of %d: %s" % (waited, _ordinal(place), len(queue), why))
        time.sleep(POLL_SECONDS)


def stuck_of(past, running):
    """The running jobs that kept the rows in [past] out."""
    found = []
    for each in past:
        found += [job for job in blockers(each, running) if job not in found]
    return found


def _ordinal(n):
    return "%d%s" % (n, "th" if 10 <= n % 100 <= 20 else {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th"))


def _adopt_take(tree, kind):
    """The file name of [tree]'s take of [kind] in running/, or of a take
    of [kind] held by this process's own ancestor whatever its tree (394
    amended (11)), marked adopted by this wrapper (it does not age out
    while this lives), and the kind whose estimate it holds; or (None,
    None)."""
    mine = None
    with StateLock():
        for entry in _entries("running"):
            if kind not in (entry["kind"], entry.get("asked")) or entry.get("watched"):
                continue
            if entry["tree"] != tree:
                if mine is None:
                    mine = set(ancestors(os.getpid()))
                if not entry.get("pid") or int(entry["pid"]) not in mine:
                    continue
            name = entry.pop("file")
            if entry["kind"] != kind:
                # A local suite run inside a take swapped for saturn (394
                # amended (33)): tests/land.ps1, which has no saturn path. It
                # runs here as the suite it asked for, held as a lean suite;
                # the memory watch stops it if that is short.
                lean = lean_row(kinds(), kind) or dict(kinds()[kind], kind=kind)
                entry.update(kind=kind, estimate=lean.get("estimate", kind), ram_gb=lean["ram_gb"], commit_gb=commit_of(lean))
                entry.pop("asked", None)
                log("unswapped", entry["tree"], kind, "a local %s run inside a take saturn was to run" % kind)
            entry["adopted_by"] = os.getpid()
            entry["adopted_since"] = started_at(os.getpid())
            entry.pop("guard", None)
            _write(_path("running", name), entry)
            return name, entry.get("estimate", kind)
    return None, None


def _outer_run():
    """The running entry of the gated run this process was started under
    (HELD_ENV, which `run` gives its command), while that entry stands, or
    None."""
    held = os.environ.get(HELD_ENV, "")
    if not held:
        return None
    with StateLock():
        for entry in _entries("running"):
            if entry["file"] == held:
                return entry
    return None


# 664 amended (2): a windowed Godot opened on Jeff's screen (terrain's shots,
# 2026-10-31 00:02: --position came after the first "--", where the engine
# leaves it to the game). The options the engine reads are those before it.
OFF_SCREEN = "--position 4000,4000 --audio-driver Dummy"


def unseen_problem(command):
    """Why a Godot started straight from [command] (its own words, or under
    timeout) would show on the screen or play aloud: None when it is
    headless, or its engine options (before the first "--" after it) carry
    --position and --audio-driver. A script it runs is not looked into."""
    for i, word in enumerate(command):
        if not re.match(r"godot", os.path.basename(word.replace("\\", "/")), re.I):
            continue
        rest = command[i + 1:]
        engine = rest[:rest.index("--")] if "--" in rest else rest
        names = [option.split("=", 1)[0] for option in engine]
        if "--headless" in names:
            return None
        lacks = [option for option in ("--position", "--audio-driver") if option not in names]
        if not lacks:
            return None
        after = [option for option in lacks if option in [o.split("=", 1)[0] for o in rest]]
        return "a windowed Godot without %s before the first \"--\"%s: add %s right after the Godot exe " \
            "(or pass heavy_job run --visible when Jeff asks to see it)" % (" or ".join(lacks),
            " (%s after it, where the engine ignores it)" % " and ".join(after) if after else "", OFF_SCREEN)
    return None


## The exit code of a run that would have queued while its tree holds the
## land lock (--no-queue-under-lock, 394 amended (31)).
NO_QUEUE_CODE = 6


def lock_owned(tree, owner):
    """Whether the land lock's [owner] is the checkout [tree] by voice's
    holds_lock rules (748 amended (8)), as beat_rank reads them: the same
    name, psykinetic-<owner>, or a side worktree <owner>-<anything> that is
    no tree's own folder."""
    if not tree or not owner:
        return False
    return (owner == tree or tree == "psykinetic-" + owner
        or (tree.startswith(owner + "-") and tree not in tree_folders()))


def lock_owner(folder):
    """The land lock [folder]'s owner, or "" (not held); a Git Bash path
    (/c/dev/land.lock) read as Windows'."""
    drive = re.match(r"^/([a-zA-Z])/(.*)$", folder)
    if drive and os.name == "nt":
        folder = "%s:/%s" % (drive.group(1).upper(), drive.group(2))
    try:
        with open(os.path.join(folder, "owner"), encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return ""


def run(tree, kind, command, expect_minutes=None, no_queue=False):
    # A gated run inside another (frame_budget.ps1 under a bench script run
    # through the gate) would queue behind its own parent forever: the outer
    # run already holds the room and measures every process under it.
    outer = _outer_run()
    if outer is not None:
        print("heavy_job: %s %s inside %s's %s run, which holds and measures it; not queued again" % (
            tree, kind, outer["tree"], outer["kind"]), file=sys.stderr)
        log("nested", tree, kind, "inside %s %s" % (outer["tree"], outer["kind"]))
        return shell_code(subprocess.call(command))
    many = many_godot_test(command)
    if many is not None and kind != "net":
        print("heavy_job: %s starts several Godots: run it as net, not %s (394 amended (24))" % (many, kind), file=sys.stderr)
        log("refused", tree, kind, "%s is a net run" % many)
        return 2
    restarts = 0
    while True:
        adopted, estimate = _adopt_take(tree, kind)
        if adopted is not None:
            name = adopted
            print("heavy_job: %s %s inside this tree's take, measured as a run" % (tree, kind), file=sys.stderr)
        elif no_queue:
            # 394 amended (31): land.sh holding the land lock with no take to adopt
            # queued at the gate with main locked (perf 09:45-10:12, animation
            # 11:04-11:22, 11-11: their takes dropped while they waited on the lock).
            print("heavy_job: %s %s: this tree holds the land lock and has no take of %s to run in: not queued "
                "(never queue at the gate holding the lock: release the lock, take the gate, then the lock again)"
                % (tree, kind, kind), file=sys.stderr)
            log("refused", tree, kind, "holding the land lock with no take to adopt")
            return NO_QUEUE_CODE
        else:
            name, estimate = wait_turn(tree, kind, os.getpid(), True, expect_minutes)
        started = time.time()
        row = kinds()[kind] if estimate == kind else (lean_row(kinds(), kind) or kinds()[kind])
        # A soak below normal priority, and what it starts with it (Windows
        # gives a below-normal process's children its class).
        flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0) if row.get("below_normal") else 0
        child = subprocess.Popen(command, env=dict(os.environ, **{HELD_ENV: name, KIND_ENV: estimate}), creationflags=flags)
        job = Job(child)
        peak, low, stopped, long_logged = 0.0, 0, False, False
        short_of = ""
        gpu_peak, commit_peak, at_once = 0.0, 0.0, 0.0
        # What held the memory at its peak (394 amended (10)): the listing
        # taken when the commit last rose past the one before.
        listed, listed_gb, listed_at = [], 0.0, 0.0
        limit = limit_seconds(row, expect_minutes)
        samples, ended = [(started, job.cpu_seconds())], None
        while child.poll() is None:
            time.sleep(WATCH_SECONDS)
            using, committed, peaks, top = job.memory()
            peak = max(peak, using, peaks)
            at_once = max(at_once, using, top)
            if os.name == "nt" and committed >= listed_gb + PEAK_LIST_STEP_GB and time.time() - listed_at >= PEAK_LIST_SECONDS:
                listed, listed_gb, listed_at = job.listing(), committed, time.time()
            commit_peak = max(commit_peak, committed, job.peak_gb())
            if row["gpu"]:
                _, used = gpu_gb()
                gpu_peak = max(gpu_peak, used or 0.0)
            now = time.time()
            samples.append((now, job.cpu_seconds()))
            while len(samples) > 2 and samples[1][0] <= now - HUNG_SECONDS:
                samples.pop(0)  # Keeps one sample at or past the window's start.
            idle, share = hung(samples, now, started)
            with StateLock():
                entry = _read(_path("running", name))
                if entry is not None:
                    entry["using_gb"] = using
                    entry["using_commit_gb"] = committed
                    entry["limit_s"] = limit
                    entry["cpu_share"] = share
                    _write(_path("running", name), entry)
                running = _entries("running")
            if limit is not None and now - started >= limit:
                ended = ("overrun", "over its limit of %.0f min (%s)" % (limit / 60,
                    "--expect" if expect_minutes is not None else "its kind's max_minutes" if row.get("fixed_limit")
                    else "%g x its kind's median run, or its max_minutes" % OVERRUN_FACTOR))
            elif idle and not row["gpu"] and not row.get("remote"):
                ended = ("hung", "hung: %.1f%% of a core the last %.0f min" % (share * 100, HUNG_SECONDS / 60))
            if ended is not None:
                job.stop()
                child.wait()
                break
            if not long_logged and time.time() - started >= LONG_HOLD_SECONDS:
                long_logged = True
                log("long", tree, kind, "still running after %.0f min" % (LONG_HOLD_SECONDS / 60))
                print("heavy_job: %s %s has held the gate %.0f min" % (tree, kind, LONG_HOLD_SECONDS / 60), file=sys.stderr)
            free, free_commit = _memory()
            short = short_of_memory(free, free_commit)
            low = low + 1 if short else 0
            if (adopted is None and low >= LOW_WATCHES and entry is not None and should_stop(entry, running, free, free_commit)
                    and child.poll() is None):
                short_of = short
                job.stop()
                child.wait()
                stopped = True
                break
        commit_peak = max(commit_peak, job.peak_gb())
        # What the command left running (a test's server or client whose
        # script was killed) would go on using the machine outside the gate.
        left = job.processes()
        if left:
            job.stop()
            log("left", tree, kind, "%d processes still running when it ended: stopped" % left)
        job.close()
        code = child.returncode
        duration = time.time() - started
        with StateLock():
            if adopted is None:
                try:
                    os.remove(_path("running", name))
                except OSError:
                    pass
            else:
                # The take is its holder's to release; with nothing in it
                # measured, it owes its whole estimate again.
                entry = _read(_path("running", name))
                if entry is not None:
                    entry["using_gb"] = 0.0
                    entry["using_commit_gb"] = 0.0
                    entry.pop("adopted_by", None)
                    entry.pop("adopted_since", None)
                    # Its guard back (394 amended (37)): no gap in which older
                    # code's check finds it unshielded.
                    guard(entry, entry.get("guard_by") if alive(entry.get("guard_by"), entry.get("guard_since")) else None,
                        entry.get("guard_since"))
                    _write(_path("running", name), entry)
            if not stopped and ended is None and (peak > 0.0 or commit_peak > 0.0 or code == 0):
                table = _read(_path("kinds.json")) or {}
                saved = dict(kinds()[estimate])
                if peak > 0.0:
                    record_ram(saved, at_once, peak)
                    if saved["gpu"] and gpu_peak > 0.0:
                        saved["gpu_gb"] = updated_estimate(saved["gpu_gb"], gpu_peak)
                if commit_peak > 0.0:
                    saved["commit_gb"] = updated_estimate(commit_of(saved), commit_peak)
                    saved["last_commit_gb"] = round(commit_peak, 2)
                if code == 0 and expect_minutes is None:
                    # Clean runs only, and no declared soak, set the limit.
                    saved["runs_s"] = (saved.get("runs_s", []) + [round(duration, 1)])[-RUN_HISTORY:]
                table[estimate] = saved
                _write(_path("kinds.json"), table)
        if ended is not None:
            log(ended[0], tree, kind, "stopped after %.0f min, %s; peak %.1f GB" % (duration / 60, ended[1], peak))
            print("heavy_job: %s %s stopped after %.0f min, %s; if it is meant to run longer, pass --expect MIN "
                "(heavy_job run %s %s --expect MIN -- ...)" % (tree, kind, duration / 60, ended[1], tree, kind), file=sys.stderr)
            return STOPPED_CODE
        if not stopped:
            log("done", tree, kind, "exit %s, %.0f s, peak %.1f GB, commit %.1f GB, working set at once %.1f GB%s" % (
                code, duration, peak, commit_peak, at_once, ", lean" if estimate != kind else ""))
            keep_listing(tree, kind, listed, listed_gb, commit_peak)
            return shell_code(code)
        restarts += 1
        under = "free commit under %.0f GB" % COMMIT_STOP_GB if short_of == "commit" else "free RAM under %.0f GB" % MARGIN_GB
        log("stopped", tree, kind, "%s after %.0f s (peak %.1f GB); restart %d of %d" % (
            under, duration, peak, restarts, MAX_RESTARTS))
        print("heavy_job: %s %s stopped: %s, the newest job; queued again" % (tree, kind, under), file=sys.stderr)
        if restarts > MAX_RESTARTS:
            return 75


def keep_listing(tree, kind, listed, listed_gb, commit_peak):
    """Prints a run's processes at its commit peak (394 amended (10)) and
    keeps them in peaks/<tree>-<kind>.txt, the last run's."""
    if not listed:
        return
    lines = ["heavy_job: %s %s at its commit peak (listed at %.1f GB of %.1f GB), private / working set GB:" % (
        tree, kind, listed_gb, commit_peak)]
    lines += ["  %5.2f %5.2f  %s" % each for each in listed if each[0] >= 0.05]
    print("\n".join(lines), file=sys.stderr)
    os.makedirs(_path("peaks"), exist_ok=True)
    with open(_path("peaks", "%s-%s.txt" % (tree, kind)), "w") as handle:
        handle.write("%s\n%s\n" % (datetime.datetime.now().isoformat(timespec="seconds"), "\n".join(lines)))


def take(tree, kind, pid, caller=None):
    outer = _outer_run()
    if outer is not None:
        print("heavy_job: %s %s inside %s's %s run, which holds it; nothing taken" % (
            tree, kind, outer["tree"], outer["kind"]))
        return 0
    if stray_refused(tree, kind):
        return 2
    _, estimate = wait_turn(tree, kind, pid, False, caller=caller)
    print("heavy_job: %s %s taken%s" % (tree, kind, " (on saturn, as suite_remote)" if estimate == "suite_remote" and kind != estimate
        else " (lean, as %s)" % estimate if estimate != kind else ""))
    return 0


def attach(tree, kind, pid):
    """Process [pid], started under [tree]'s take of [kind], measured as
    the take's from now on (394 amended (20))."""
    if _outer_run() is not None:
        print("heavy_job: %s %s inside a run, which measures its whole tree; nothing attached" % (tree, kind))
        return 0
    if not alive(pid):
        print("heavy_job: no process %s to attach" % pid, file=sys.stderr)
        return 1
    with StateLock():
        for entry in _entries("running"):
            if entry["tree"] == tree and kind in (entry["kind"], entry.get("asked")) and not entry.get("watched"):
                name = entry.pop("file")
                attached = [each for each in entry.get("attached", []) if each.get("pid") != int(pid)]
                entry["attached"] = attached + [{"pid": int(pid), "since": started_at(pid)}]
                measure_attached(entry)
                _write(_path("running", name), entry)
                log("attach", tree, kind, "pid %s, %.1f GB commit now" % (pid, entry.get("using_commit_gb", 0.0)))
                print("heavy_job: %s %s: pid %s measured as the take's" % (tree, kind, pid))
                return 0
    print("heavy_job: %s holds no %s take to attach to" % (tree, kind), file=sys.stderr)
    return 1


def record_attached(kind, entry):
    """[kind]'s row in kinds.json after a take whose attached processes
    peaked as [entry] says (394 amended (20)): RAM and commit as a run's
    peaks set them. Nothing when none was measured."""
    peak, peak_commit = entry.get("attached_peak_gb", 0.0), entry.get("attached_peak_commit_gb", 0.0)
    if peak <= 0.0 and peak_commit <= 0.0:
        return
    table = _read(_path("kinds.json")) or {}
    saved = dict(kinds()[kind])
    if peak > 0.0:
        record_ram(saved, entry.get("attached_once_gb", peak), peak)
    if peak_commit > 0.0:
        saved["commit_gb"] = updated_estimate(commit_of(saved), peak_commit)
        saved["last_commit_gb"] = round(peak_commit, 2)
    table[kind] = saved
    _write(_path("kinds.json"), table)


def release(tree, kind):
    outer = _outer_run()
    if outer is not None:
        # What a take inside a run "took" was the run's own entry.
        print("heavy_job: %s %s inside %s's %s run; nothing to release" % (tree, kind, outer["tree"], outer["kind"]))
        return 0
    with StateLock():
        for entry in _entries("running"):
            if entry["tree"] == tree and kind in (entry["kind"], entry.get("asked")) and not entry.get("watched"):
                # A swapped take (394 amended (33)) released by the kind it asked for.
                os.remove(_path("running", entry["file"]))
                record_attached(entry["kind"], entry)
                attached = (", attached peak %.1f GB, commit %.1f GB" % (entry.get("attached_peak_gb", 0.0),
                    entry.get("attached_peak_commit_gb", 0.0))) if entry.get("attached") else ""
                log("done", tree, entry["kind"], "released after %.0f s%s" % (time.time() - entry["started"], attached))
                print("heavy_job: %s %s released" % (tree, entry["kind"]))
                return 0
    print("heavy_job: %s holds no %s" % (tree, kind), file=sys.stderr)
    return 1


def tree_folders():
    """The trees' own folder names, tests/port_offsets.txt's (each has a line)."""
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "port_offsets.txt"),
                encoding="utf-8") as handle:
            return {line.split()[0] for line in handle if line.strip() and not line.startswith("#")}
    except OSError:
        return set()


def beat_rank(entry, owner, own, mine):
    """How near a take [entry] is to the land lock's [owner] (394 amended
    (31), voice's holds_lock rules of 748 amended (8)): 0 its tree is the
    owner; 1 its holder is an ancestor of this process ([mine], ids); 2
    psykinetic-<owner> (release's checkout takes the lock as "release"); 3
    a side worktree <owner>-<anything> that is no tree's own folder ([own]:
    ui-design is no side of ui); None, not the owner's."""
    tree = entry["tree"]
    if tree == owner:
        return 0
    if entry.get("pid") and int(entry["pid"]) in mine:
        return 1
    if tree == "psykinetic-" + owner:
        return 2
    if tree.startswith(owner + "-") and tree not in own:
        return 3
    return None


# 394 amended (35): a landing's take first clears its checkout of untracked files
# that origin/main tracks. An import writes a script's .gd.uid or an image's
# .import before the tree that made it commits it; the landing's rebase onto main
# then stops ("untracked working tree files would be overwritten") at its turn,
# after hours queued (buildings' and ui's fronted takes, 11-12 02:18, ended in
# seconds on tests/tour/tours/fish_click.gd.uid). Off in the gate's own test,
# which sets it on for its own checks in a scratch repository.
STRAY_CHECK = True
STRAY_GENERATED = (".uid", ".import")


def stray_tracked(cwd=None):
    """Untracked files in the checkout at [cwd] that origin/main tracks, as
    (removed, refused): generated kinds (STRAY_GENERATED) deleted here, the rest
    left alone. ([], []) when it isn't a checkout or has no origin/main."""
    def git(*args):
        done = subprocess.run(["git"] + list(args), cwd=cwd, capture_output=True, timeout=60)
        return done.stdout.decode("utf-8", "replace").split("\0") if done.returncode == 0 else None
    try:
        tracked = git("ls-tree", "-r", "-z", "--name-only", "origin/main")
        untracked = git("ls-files", "-z", "--others", "--exclude-standard")
        top = git("rev-parse", "--show-toplevel")
    except (OSError, subprocess.SubprocessError):
        return [], []
    if tracked is None or untracked is None or top is None:
        return [], []
    top = top[0].strip()
    both = sorted(set(path for path in untracked if path) & set(path for path in tracked if path))
    removed, refused = [], []
    for path in both:
        if path.endswith(STRAY_GENERATED):
            try:
                os.remove(os.path.join(top, path))
                removed.append(path)
            except OSError:
                refused.append(path)
        else:
            refused.append(path)
    return removed, refused


def stray_refused(tree, kind):
    """For a landing kind: clear the checkout's stray generated files, naming
    each; True (and the names said) when any other untracked file main tracks
    stands in the way, so the take is refused before it queues."""
    if not STRAY_CHECK or not landing_kind(kind):
        return False
    removed, refused = stray_tracked()
    for path in removed:
        print("heavy_job: removed the untracked %s, which origin/main tracks (a generated file; 394 amended (35))" % path,
            file=sys.stderr)
        log("stray", tree, kind, "removed %s" % path)
    if not refused:
        return False
    print("heavy_job: %s %s not queued: untracked files here that origin/main tracks would stop the rebase onto main; "
        "move or delete them, then queue again (394 amended (35)):\n  %s" % (tree, kind, "\n  ".join(refused)), file=sys.stderr)
    log("refused", tree, kind, "untracked files main tracks: %s" % ", ".join(refused))
    return True


def landing_kind(kind):
    """Whether [kind] is a landing's (suite, or a suite_* kind of its own such
    as a remote landing's): the takes land_lock.sh beats."""
    return kind == "suite" or kind.startswith("suite_")


def beat(owner, kind=None):
    """The take of [kind] (None: any landing_kind) held by the land lock's
    [owner] (beat_rank: the nearest) marked alive now (394 amended (31)):
    its TAKE_STALE_SECONDS count from here. 0 if one was found, else 1. A
    run is watched and never goes stale so; nothing to beat."""
    if os.environ.get("HEAVY_JOB_BEAT_BREAK"):
        raise RuntimeError("HEAVY_JOB_BEAT_BREAK set (heavy_job_test's failed beat)")
    with StateLock():
        takes = [each for each in _entries("running") if not each.get("watched")
            and (each["kind"] == kind if kind else landing_kind(each["kind"]))]
        own, mine = tree_folders(), set(ancestors(os.getpid())) if takes else set()
        ranked = sorted((rank, place) for place, rank in enumerate(beat_rank(each, owner, own, mine) for each in takes)
            if rank is not None)
        if not ranked:
            return 1
        entry = takes[ranked[0][1]]
        name = entry.pop("file")
        entry["beat"] = time.time()
        _write(_path("running", name), entry)
        return 0


def holds(tree, kind):
    """Whether [tree] holds a [kind] now (a take, or a run going): a script
    called inside it (land.sh, under its session's take) does not queue
    again. As a run adopts a take (394 amended (11)), one of [kind] held by
    this process's own ancestor counts whatever tree it is named for: land.sh
    asks this to choose between suite and suite_remote, and a landing script
    that took suite under another name must not be sent to queue again for
    suite_remote while it holds the land lock."""
    with StateLock():
        # A swapped take (394 amended (33)) holds the kind it asked for too.
        entries = [entry for entry in _entries("running") if kind in (entry["kind"], entry.get("asked"))]
    if any(entry["tree"] == tree for entry in entries):
        return True
    if not entries:
        return False
    mine = set(ancestors(os.getpid()))
    return any(entry.get("pid") and int(entry["pid"]) in mine for entry in entries)


def queue_reasons(queue, running, free_ram, free_commit, free_gpu, now=None):
    """Each queued entry's reason, as its waiter's next look would judge it
    (wait_turn's passes and decide, read only): "may start at its next look",
    or "waits: " and what holds it; one behind a head names that head and
    what the head waits on (394 amended (26)). Since 394 amended (28) it
    names the row that holds it, the head or one further on ("behind <tree>
    <kind> (<n>th in the queue)"), and judges each by its waiter's --expect."""
    table = kinds()
    now = time.time() if now is None else now
    out = []
    for place, entry in enumerate(queue):
        # A kind the table lacks (a kinds.json older than the entry): judged as a suite, the heaviest.
        default = dict(table.get(entry["kind"]) or KINDS.get(entry["kind"]) or table["suite"])
        row = judged_row(table, entry, default, running, free_ram, free_commit, now=now)
        ahead = [judged_row(table, each, default, running, free_ram, free_commit, now=now) for each in queue[:place]]
        head, past, past_why, holder = passes_held(row, ahead, running, free_ram, free_commit, table, now, backfill_length(row))
        ok, why = decide(row, running, head, free_ram, free_gpu if row["gpu"] else None, free_commit)
        if ok:
            out.append("may start at its next look" + (" (past %s by backfill)" % ", ".join(
                "%s %s" % (each["tree"], each["kind"]) for each in past) if past else ""))
        elif not head and holder is not None:
            other = ahead[holder]
            _, other_why = decide(other, running, True, free_ram, free_gpu if other["gpu"] else None, free_commit)
            other_why = at_least(table, other, other_why)
            out.append("waits: behind %s, which waits on: %s%s" % (holder_name(queue, holder),
                other_why or "its next look", "; " + past_why if past_why else ""))
        else:
            out.append("waits: %s" % at_least(table, row, why))
    return out


def status():
    """Running and queued jobs and free memory. Since 394 amended (26) each
    line ends with what explains a wait: what each running job is still
    owed of its estimate, and each queued row's reason, the gate's own
    decide/passes answer for it at this moment (what its waiter sees). The
    state is read under the lock as before and judged after letting it go:
    status never writes it, so it can't stall a waiter. Earlier text of each
    line is unchanged (scripts read it); the reason comes after "; "."""
    with StateLock():
        running = _entries("running")
        queue = _entries("queue")
    free_gpu, used_gpu = gpu_gb()
    free_ram, free_commit = _memory()
    print("free RAM %.1f GB (margin %.0f GB), commit %s, GPU %s; owed to running jobs: RAM %.1f GB, commit %.1f GB" % (
        free_ram, MARGIN_GB,
        "%.1f GB free (margin %.0f GB)" % (free_commit, COMMIT_MARGIN_GB) if free_commit is not None else "unknown",
        "%.1f GB free" % free_gpu if free_gpu is not None else "unknown",
        reserved_gb(running), reserved_commit_gb(running)))
    for entry in running:
        held = time.time() - entry["started"]
        limit, share = entry.get("limit_s"), entry.get("cpu_share")
        flag = ""
        if limit is not None and held >= limit:
            flag = "  OVERRUN"
        elif share is not None and share < HUNG_CPU:
            flag = "  HUNG? (cpu %.0f%% the last %.0f min)" % (share * 100, HUNG_SECONDS / 60)
        elif held >= LONG_HOLD_SECONDS:
            flag = "  LONG: held %.0f min, is it stuck?" % (held / 60)
        backfill = entry.get("backfill")
        print("running %s %s, %s, using %.1f of %.1f GB%s%s" % (entry["tree"], entry["kind"],
            "held %.0f of %.0f min" % (held / 60, limit / 60) if limit is not None else "%.0f s" % held,
            entry.get("using_gb", 0.0), entry["ram_gb"], ("" if entry.get("watched") else " (taken)")
            + (" (lean)" if entry.get("estimate", entry["kind"]) != entry["kind"] else "")
            + (" (went past %s, due by %s)" % (backfill["past"], time.strftime("%H:%M", time.localtime(backfill["due"])))
                if backfill else ""), flag) + "; owed %.1f GB" % reserved_gb([entry]))
    reasons = queue_reasons(queue, running, free_ram, free_commit, free_gpu)
    for place, entry in enumerate(queue, 1):
        print("queued %s %s, %.0f s (%s)%s%s" % (entry["tree"], entry["kind"], time.time() - entry["queued"], _ordinal(place),
            ", first for %.0f s" % (time.time() - entry["head_since"]) if entry.get("head_since") else "",
            ", lean" if entry.get("estimate", entry["kind"]) != entry["kind"] else "")
            + (", fronted by %s: %s" % (entry["fronted"]["by"], entry["fronted"]["why"]) if entry.get("fronted") else "")
            + "; " + reasons[place - 1])
    # After the rows (394 amended (37)): their lines and order unchanged for scripts.
    for folder, entries in (("running", running), ("queued", queue)):
        for entry in entries:
            if older_code(entry):
                print("on older gate code: %s %s (%s), pid %s, gate revision %s of %s, %s; rebase it" % (
                    entry["tree"], entry["kind"], folder, entry.get("waiter") if folder == "queued" else entry.get("pid"),
                    entry["gate"], GATE_REVISION, _where(entry)))
    # 394 amended (38): no revision says nothing of the code's age, so a count, no names.
    unknown = sum(1 for entry in running + queue if unrevised(entry))
    if unknown:
        print("written before 394 amended (37), gate revision unknown: %d (a count only: most are 31 to 36 code,"
            " which drops nothing; stop none on it)" % unknown)
    for entry in running:
        if unbeaten(entry):
            print("unbeaten: %s %s held %.0f min, since %s, no beat from its land lock tries (pid %s, %s)" % (
                entry["tree"], entry["kind"], (time.time() - entry["started"]) / 60,
                time.strftime("%H:%M", time.localtime(entry["started"])), entry.get("pid"), _where(entry)))
    if not running and not queue:
        print("no heavy jobs")
    return 0


def show_kinds():
    for name, row in sorted(kinds().items()):
        print("%-14s %5.1f GB RAM, %.1f GB commit%s%s%s%s%s" % (name, row["ram_gb"], commit_of(row),
            ", GPU %.1f GB" % row["gpu_gb"] if row["gpu"] else "",
            ", at most %d at once" % row["max_running"] if row.get("max_running") is not None else "",
            ", last peak %.1f GB" % row["last_peak_gb"] if "last_peak_gb" in row else "",
            " (commit %.1f)" % row["last_commit_gb"] if "last_commit_gb" in row else "",
            measures(row)))
    return 0


def measures(row):
    """[row]'s two RAM estimates, for a while (394 amended (27)), the deciding
    one first: "; RAM by at once 17.7, summed peaks 20.5" ("" if none yet)."""
    if "ram_once_gb" not in row and "ram_peaks_gb" not in row:
        return ""
    other = SUMMED_PEAKS if RAM_MEASURE == AT_ONCE else AT_ONCE
    return "; RAM by %s %.1f, %s %.1f" % (RAM_MEASURE, row.get(MEASURE_FIELDS[RAM_MEASURE], row["ram_gb"]),
        other, row.get(MEASURE_FIELDS[other], row["ram_gb"]))


def summary(day):
    lines = []
    try:
        with open(_path("heavy_jobs.log")) as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 5 and parts[0].startswith(day) and (parts[1] in SUMMARY_EVENTS or "waited" in parts[4]):
                    if parts[1] == "old_gate" and "gate revision" not in parts[4]:
                        continue  # 37's own notes of an unrevised entry: its age unknown (394 amended (38)).
                    lines.append(parts)
    except OSError:
        pass
    if not lines:
        print("%s: no heavy job waited or was stopped" % day)
    for when, event, tree, kind, detail in lines:
        if event == "launch":
            detail = detail.split("; backtrace:")[0]  # The whole one stays in the log.
        print("%s %s %s %s: %s" % (when[11:16], tree, kind, event if event in SUMMARY_EVENTS else "waited", detail))
    counts = ["%d %s" % (sum(1 for each in lines if each[1] == event), event) for event in ("overrun", "hung", "launch", "timeout")]
    late = [float(re.match(r"waited (\d+)", each[4]).group(1)) for each in lines
        if each[1] == "backfill_late" and re.match(r"waited (\d+)", each[4])]
    counts.append("%d backfill, %d late (%.0f s in all)" % (sum(1 for each in lines if each[1] == "backfill"), len(late), sum(late)))
    print("%s: %s" % (day, ", ".join(counts)))
    # By tree (394 amended (37)): a tree with old gate code, or whose land lock
    # tries don't beat its take, shows up the same day.
    for event in ("old_gate", "unbeaten", "beat_failed"):
        by_tree = {}
        for each in lines:
            if each[1] == event:
                by_tree[each[2]] = by_tree.get(each[2], 0) + 1
        if by_tree:
            print("%s: %s by tree: %s" % (day, event, ", ".join("%s %d" % pair for pair in sorted(by_tree.items()))))
    # Launch crashes by their top frame (530 amended): the same frame again
    # and again is an engine or asset bug to chase, not the machine.
    crashes = {}
    for each in lines:
        found = re.search(r"; crashed \([^)]*\) at ([^\s;]+)", each[4]) if each[1] == "launch" else None
        if found:
            crashes[found.group(1)] = crashes.get(found.group(1), 0) + 1
    if crashes:
        print("%s: launch crashes by top frame: %s" % (day, ", ".join("%s %d" % (frame, count)
            for frame, count in sorted(crashes.items(), key=lambda item: -item[1]))))
    return 0


## The log's events the daily summary lists.
SUMMARY_EVENTS = ("stopped", "waiting", "long", "overrun", "hung", "launch", "timeout", "backfill", "backfill_late", "front",
    "old_gate", "unbeaten", "beat_failed")
## Who may move a queued entry to the front (394 amended (25)): release, for a
## change every queued landing is paying for (a failing check on main, a broken
## tool) or on Jeff's word. Names are an honour system, as the land lock's are.
FRONT_BY = "release"


def front(tree, kind, by, why):
    """[tree]'s queued [kind] made first among the waiters, by release, for
    [why] (394 amended (25)). Only its place in the queue changes: the ticket
    keeps its name (a renamed one reads to its own waiter as dropped, and it
    would exit 3), and running jobs are never touched, so it still waits for
    room, a kind's cap and what it excludes. Refused: not release; no reason;
    not queued; its waiter dead; another fronted entry still waiting."""
    if by != FRONT_BY:
        print("heavy_job: front is release's alone (394 amended (25)); %s: tell the coordinator why instead" % (by or "no --by"),
            file=sys.stderr)
        log("refused", tree, kind, "front by %s" % (by or "nobody"))
        return 2
    if not why.strip():
        print("heavy_job: front needs --why \"<reason>\" (394 amended (25))", file=sys.stderr)
        return 2
    with StateLock():
        queue = _entries("queue")
        mine = [each for each in queue if each["tree"] == tree and each["kind"] == kind]
        if not mine:
            print("heavy_job: %s %s is not queued; nothing moved" % (tree, kind), file=sys.stderr)
            return 3
        target = mine[0]
        waiter = target.get("waiter")
        if not waiter or not alive(waiter, target.get("waiter_since")):
            print("heavy_job: %s %s: its waiter (pid %s) is gone; nothing moved" % (tree, kind, waiter), file=sys.stderr)
            return 3
        earlier = [each for each in queue if each.get("fronted") and each["file"] != target["file"]]
        if earlier:
            print("heavy_job: %s %s, fronted before, still waits: one front at a time; nothing moved" % (
                earlier[0]["tree"], earlier[0]["kind"]), file=sys.stderr)
            return 3
        place = queue.index(target)
        if place == 0:
            print("heavy_job: %s %s is first already" % (tree, kind))
            return 0
        jumped = ", ".join("%s %s" % (each["tree"], each["kind"]) for each in queue[:place])
        entry = _read(_path("queue", target["file"]))
        if entry is None:
            print("heavy_job: %s %s left the queue as it was moved; nothing moved" % (tree, kind), file=sys.stderr)
            return 3
        entry["order"] = _order(queue[0]) - 1
        entry["fronted"] = {"by": by, "why": why, "at": time.time()}
        _write(_path("queue", target["file"]), entry)
        log("front", tree, kind, "by %s, why: %s; jumped: %s" % (by, why, jumped))
    print("heavy_job: %s %s moved to the front of the queue, past %s; it still waits for room and what runs" % (tree, kind, jumped))
    return 0
## What a script outside the gate may log with `note` (decision 530: a test
## scene that died at launch, before any of its own code ran).
NOTE_EVENTS = ("launch", "timeout", "beat_failed")  # timeout: a test scene killed for time (90 amended (1)).


def note(tree, event, detail):
    """Logs [param event] for [param tree] with the machine's free RAM and
    commit added, and prints that line's detail (for the caller's own log)."""
    ram, commit = _memory()
    detail = "%s; free RAM %.1f GB, commit %s" % (detail, ram, "%.1f GB" % commit if commit is not None else "unknown")
    log(event, tree, "suite", detail)
    print(detail)
    return 0


def main(args):
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    command = args[0]
    # Not status or kinds: they never write the state (394 amended (26)).
    if command in ("run", "take", "attach", "release"):
        seed_measures()
    if command == "beat" and len(args) == 2:
        return beat(args[1])  # Any landing kind's take (394 amended (31)).
    if command in ("run", "take", "attach", "release", "holds", "beat", "front") and (len(args) < 3 or args[2] not in kinds()
            or kinds()[args[2]].get("variant_of")):
        print("heavy_job: %s <tree> <kind>, a kind of: %s" % (command, ", ".join(sorted(kinds()))), file=sys.stderr)
        return 2
    if command == "run":
        if "--" not in args or args.index("--") == len(args) - 1:
            print("heavy_job: run <tree> <kind> [--expect MIN] -- <command...>", file=sys.stderr)
            return 2
        options = args[3:args.index("--")]
        expect = None
        visible = "--visible" in options
        if visible:
            options.remove("--visible")
        no_queue = False
        if "--no-queue-under-lock" in options:
            at = options.index("--no-queue-under-lock")
            if at + 1 >= len(options):
                print("heavy_job: --no-queue-under-lock <land lock folder>", file=sys.stderr)
                return 2
            no_queue = lock_owned(args[1], lock_owner(options[at + 1]))
            del options[at:at + 2]
        if options:
            if options[0] != "--expect" or len(options) != 2:
                print("heavy_job: run <tree> <kind> [--expect MIN] [--visible] [--no-queue-under-lock DIR] -- <command...>",
                    file=sys.stderr)
                return 2
            expect = float(options[1])
        command = args[args.index("--") + 1:]
        most = kinds()[args[2]].get("max_expect")
        if expect is not None and most is not None and expect > most:
            print("heavy_job: a %s runs at most %g minutes (--expect %g): a longer run is a soak, "
                "heavy_job run %s soak --expect %g -- ... (394 amended (32))" % (args[2], most, expect, args[1], expect),
                file=sys.stderr)
            log("refused", args[1], args[2], "--expect %g over its kind's %g" % (expect, most))
            return 2
        problem = None if visible else unseen_problem(command)
        if problem is not None:
            print("heavy_job: not run: %s (664 amended (2))" % problem, file=sys.stderr)
            return 2
        return run(args[1], args[2], command, expect, no_queue)
    if command == "take":
        pid = int(args[args.index("--pid") + 1]) if "--pid" in args else None
        # heavy_job.sh's --caller: the shell that ran it (394 amended (37)).
        at = args.index("--caller") if "--caller" in args else -1
        caller = int(args[at + 1]) if 0 <= at < len(args) - 1 and args[at + 1].isdigit() else None
        return take(args[1], args[2], pid, caller)
    if command == "attach":
        if "--pid" not in args or args.index("--pid") == len(args) - 1 or not args[args.index("--pid") + 1].isdigit():
            print("heavy_job: attach <tree> <kind> --pid N", file=sys.stderr)
            return 2
        return attach(args[1], args[2], int(args[args.index("--pid") + 1]))
    if command == "release":
        return release(args[1], args[2])
    if command == "beat":
        return beat(args[1], args[2])
    if command == "holds":
        return 0 if holds(args[1], args[2]) else 1
    if command == "front":
        def option(name):
            return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else ""
        return front(args[1], args[2], option("--by"), option("--why"))
    if command == "status":
        return status()
    if command == "kinds":
        return show_kinds()
    if command == "summary":
        return summary(args[1] if len(args) > 1 else datetime.date.today().isoformat())
    if command == "note":
        if len(args) < 4 or args[2] not in NOTE_EVENTS:
            print("heavy_job: note <tree> <event> <detail...>, an event of: %s" % ", ".join(NOTE_EVENTS), file=sys.stderr)
            return 2
        return note(args[1], args[2], " ".join(args[3:]))
    print("heavy_job: no command %s (run, take, attach, release, front, status, kinds, summary, note)" % command, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

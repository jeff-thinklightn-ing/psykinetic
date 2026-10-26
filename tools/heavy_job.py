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
  * fewer than MAX_RUNNING heavy jobs running, never two GPU jobs, and no
    more of a kind than its max_running (suite 1: a suite runs its scenes
    in parallel and fills the CPU, and two together took ten times as long
    each; bench 1, as the bench lock);
  * none of the kinds it excludes running: a bench and a suite never run
    together (a bench's timings beside a suite are the suite's, not the
    build's: one build measured 20 to 42 ms a frame by what ran beside it),
    nor a bench and a soak; a soak (sim steps counted, no timings: town_soak,
    town_balance) runs beside a suite, below normal priority, one at a time
    (394 amended (8): economy's 150-minute soak as a bench held five
    landings and a cut).

An entry names its processes by id and start time (pid_since, waiter_since,
adopted_since): one whose id now belongs to another process, or queued
before the machine last started, is stale and dropped (394 amended (8)).

Otherwise it waits in a queue, first come first served: only the job at
its head may start, so a big job is not starved by small ones; except that
a job may go past those before it that wait only on their own kind (a
suite behind a suite: may_pass), when it is of another kind. A job run
through `run` is watched: if free RAM falls under the margin while it runs
and it is the newest job running, its own wrapper stops its own child (no
one else's process: never kill by name, never another session's) and puts
it back in the queue, MAX_RESTARTS times at most. Each kind's estimate is
updated from the peak `run` measures (the whole process tree's working
set), rising at once and falling slowly. A `run` by a tree that already
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

A suite out of reach (memory held outside the gate) for LEAN_AFTER_SECONDS
runs lean (394 amended (9), (10), (12)): land.sh reads HEAVY_JOB_KIND,
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

State and log live outside the repo, in STATE_DIR (HEAVY_JOBS_DIR to put
them elsewhere, as the test does): running/ and queue/ hold a file a job,
kinds.json the estimates and caps (edit a kind's max_running there to
tune it), heavy_jobs.log a line an event (`summary`).

  heavy_job.py run <tree> <kind> [--expect MIN] -- <command...>
                                                   wait, run, release; the command's exit code (5: stopped,
                                                   over its limit or hung; a long soak passes --expect MIN)
  heavy_job.py take <tree> <kind> [--pid N]        wait, then hold a place (scripts that cannot wrap);
                                                   N a Windows process id (Git Bash: $(cat /proc/$$/winpid))
  heavy_job.py release <tree> <kind>               give back what take held
  heavy_job.py holds <tree> <kind>                 exit 0 if <tree> holds a <kind> (run or take)
  heavy_job.py status                              running, queued, free memory
  heavy_job.py kinds                               the kinds and their estimates
  heavy_job.py summary [YYYY-MM-DD]                what waited or was stopped that day (today)
  heavy_job.py note <tree> launch <detail...>      log a test scene that died at launch (decision 530),
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
## Commit (RAM and pagefile, 100 GB here) kept free: past it allocations
## fail and programs crash.
COMMIT_MARGIN_GB = 8.0
MAX_RUNNING = 3
## A job holding the gate this long is flagged in status, the log and the
## summary (a bench held 588 minutes on 2026-10-17 before anyone saw it).
LONG_HOLD_SECONDS = 3600
## Set by `run` for its command: the name of its running entry.
HELD_ENV = "HEAVY_JOB_HELD"
## Set by `run` for its command: the kind whose estimate it runs under
## (suite_lean3 for a lean suite, 394 amended (9), (10), (12)).
KIND_ENV = "HEAVY_JOB_KIND"
## A job out of reach this long runs as its kind's lean variant, if any.
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
TAKE_STALE_SECONDS = 30 * 60
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
## The kinds and their first estimates (GB), before any is measured;
## max_minutes: the limit before the kind has recorded runs.
KINDS = {
    "trellis_mesh": {"ram_gb": 9.0, "gpu_gb": 12.0, "gpu": True},
    "comfy_batch": {"ram_gb": 6.0, "gpu_gb": 10.0, "gpu": True},
    "suite": {"ram_gb": 6.5, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["bench"], "max_minutes": 90,
        "lean": "suite_lean3"},  # tests/land.sh: 6.3 GB measured
    # A suite run lean (394 amended (9), (10), (12)): its estimate and runs only;
    # it runs as a suite (lean_row), never as a kind of its own.
    "suite_lean3": {"ram_gb": 8.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90, "variant_of": "suite"},
    "bench": {"ram_gb": 3.0, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["suite", "soak"], "max_minutes": 90},
    "godot_import": {"ram_gb": 2.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90},
    "godot_export": {"ram_gb": 3.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90},
    # A soak (394 amended an eighth time) counts sim steps, not time: it
    # runs beside a suite, at below-normal priority so the suite's scenes
    # come first, never beside a bench (whose timings it would skew); its
    # limit is max_minutes, not its median run, since --days sets its length.
    "soak": {"ram_gb": 2.5, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["bench"], "max_minutes": 180,
        "fixed_limit": True, "below_normal": True},
}
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
    if len(running) >= MAX_RUNNING:
        return False, "%d heavy jobs running" % len(running)
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


def goes_lean(row, lean, waited_s, running, free_ram_gb, free_commit_gb=None):
    """Whether a job of [row] waiting [waited_s] runs as [lean] (its lean
    variant, or None): out of reach that long, and the lean one in reach.
    A wait on the queue, or on its own kind, never makes it lean."""
    return (lean is not None and waited_s >= LEAN_AFTER_SECONDS
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


def may_pass(job, ahead, running, free_ram_gb=None, free_commit_gb=None):
    """Whether [job] may start though [ahead] (the rows queued before it)
    came first: none, or each is out of reach (out_of_reach: a 29 GB mesh
    job on a machine with 32 GB free held ten landings behind it), or waits
    only on its own kind (kind_blocked: a suite behind a suite, a bench
    beside one) and [job] is of another kind that neither excludes. A wait
    for memory the queue will give back, or for the running count, is first
    come first served for everyone: a big job is not starved; once in reach
    it holds those behind it again."""
    for other in ahead:
        if free_ram_gb is not None and out_of_reach(other, running, free_ram_gb, free_commit_gb):
            continue
        if not kind_blocked(other, running):
            return False
        if other.get("kind") == job.get("kind") or other.get("kind") in job.get("excludes", [])                 or job.get("kind") in other.get("excludes", []):
            return False
    return True


def may_step_aside(job, behind):
    """Whether [job], out of reach, may step to the back of the queue past
    [behind] (the rows queued after it): never past a kind that excludes it
    or that it excludes (394 amended (14)). A suite out of reach for its
    first LEAN_AFTER_SECONDS stepped behind a bench, which became the head
    and, excluding suites, held the landing for the whole bench."""
    return not any(other.get("kind") in job.get("excludes", []) or job.get("kind") in other.get("excludes", [])
        for other in behind)


def should_stop(me, running, free_ram_gb):
    """Whether the watched job [me] stops its child: free RAM is under the
    margin and no running job started after it."""
    if free_ram_gb >= MARGIN_GB:
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
    runs = sorted(row.get("runs_s", []))
    if runs:
        middle = len(runs) // 2
        median = runs[middle] if len(runs) % 2 else (runs[middle - 1] + runs[middle]) / 2.0
        return max(OVERRUN_FLOOR_SECONDS, OVERRUN_FACTOR * median)
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

    class _Counters(ctypes.Structure):
        _fields_ = [("cb", ctypes.c_ulong), ("faults", ctypes.c_ulong),
            ("peak_working_set", ctypes.c_size_t), ("working_set", ctypes.c_size_t),
            ("quota_peak_paged", ctypes.c_size_t), ("quota_paged", ctypes.c_size_t),
            ("quota_peak_nonpaged", ctypes.c_size_t), ("quota_nonpaged", ctypes.c_size_t),
            ("pagefile", ctypes.c_size_t), ("peak_pagefile", ctypes.c_size_t)]

    def using_gb(self):
        """The working set of the job's processes now."""
        return self.memory()[0]

    def memory(self):
        """The job's live processes' (working set now, commit now, the sum of
        their own peak working sets), GB. The peaks catch what a watch every
        WATCH_SECONDS misses (a model's weights read on the CPU a moment
        before they go to the card)."""
        if self.handle is None:
            return 0.0, 0.0, 0.0
        kernel = ctypes.windll.kernel32
        Counters = self._Counters
        kernel.OpenProcess.restype = ctypes.c_void_p
        total, commit, peaks = 0, 0, 0
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
            kernel.CloseHandle(ctypes.c_void_p(process))
        return total / GB, commit / GB, peaks / GB

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
        # Exclusions the code adds (a bench never beside a soak) hold over a
        # kinds.json written before them.
        row["excludes"] = sorted(set(first.get("excludes", [])) | set(saved.get(name, {}).get("excludes", [])))
        if not row["excludes"]:
            del row["excludes"]
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
        if folder == "running" and not entry.get("watched") and not alive(entry.get("adopted_by"), entry.get("adopted_since")):
            stale = stale or time.time() - entry.get("started", entry["queued"]) > TAKE_STALE_SECONDS
        if stale:
            os.remove(_path(folder, name))
            log("stale", entry["tree"], entry["kind"], "%s dropped" % folder)
            continue
        entry["file"] = name
        out.append(entry)
    return out


def log(event, tree, kind, detail=""):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(_path("heavy_jobs.log"), "a") as handle:
        handle.write("%s\t%s\t%s\t%s\t%s\n" % (datetime.datetime.now().isoformat(timespec="seconds"), event, tree, kind, detail))


# --- Commands -----------------------------------------------------------------

def wait_turn(tree, kind, pid, watched):
    """Queues, waits to be at the head with room, then moves to running.
    Returns the running entry's file name and the kind whose estimate it
    holds: [kind], or its lean variant (goes_lean)."""
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
        _write(_path("queue", ticket), {"tree": tree, "kind": kind, "pid": pid, "pid_since": started_at(pid),
            "waiter": os.getpid(), "waiter_since": started_at(os.getpid()), "queued": queued})
    said = 0.0
    long_logged = False
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
            ahead = [queued_row(table, each, row) for each in queue[:place - 1]]
            # First in the queue, or every job before it waits on its own
            # kind alone (may_pass): an import is not held behind a suite
            # waiting for a suite.
            free_ram, free_commit = _memory()
            if estimate == kind and goes_lean(row, lean_row(kinds(), kind) if row.get("lean") else None,
                    time.time() - queued, running, free_ram, free_commit):
                row = lean_row(kinds(), kind)
                estimate = row["estimate"]
                entry = _read(_path("queue", ticket))
                if entry is not None:
                    entry["estimate"] = estimate
                    _write(_path("queue", ticket), entry)
                log("lean", tree, kind, "out of reach %.0f s at %.1f GB free: runs as %s, %.1f GB" % (
                    time.time() - queued, free_ram, estimate, row["ram_gb"]))
                print("heavy_job: %s %s out of reach (memory held outside the gate): runs lean, as %s (%.1f + %.0f GB)" % (
                    tree, kind, estimate, row["ram_gb"], MARGIN_GB), file=sys.stderr)
            head = may_pass(row, ahead, running, free_ram, free_commit)
            ok, why = decide(row, running, head, free_ram, free_gpu, free_commit)
            if not ok and head and out_of_reach(row, running, free_ram, free_commit):
                why += "; out of reach even with no heavy job running (memory held outside the gate): jobs that fit go past it"
                behind = [queued_row(table, each, row) for each in queue[place:]]
                if place < len(queue) and may_step_aside(dict(row, kind=kind), behind):
                    # Steps to the back itself: waiters started from an older
                    # heavy_job.py (a tree not yet rebased) don't know the
                    # rule above and would hold behind it (107 minutes,
                    # 2026-10-18). Its turn comes again as the queue drains.
                    aside = "%019d-%s-%s.json" % (time.time_ns(), tree, pid or os.getpid())
                    try:
                        _retried(os.replace, _path("queue", ticket), _path("queue", aside))
                    except PermissionError:
                        aside = None  # Still in use: tried again at the next look.
                    if aside is not None:
                        ticket = aside
                        log("aside", tree, kind, "out of reach; to the back of %d" % len(queue))
            if not head and queue and queue[0]["file"] != ticket:
                first = queue[0]
                first_row = dict(kinds().get(first["kind"], row), kind=first["kind"])
                first_gpu = gpu_gb()[0] if first_row["gpu"] else None
                _, first_why = decide(first_row, running, True, free_ram, first_gpu, free_commit)
                why = "the head, %s %s, waits on: %s" % (first["tree"], first["kind"], first_why or "its next look")
            if ok:
                _retried(os.remove, _path("queue", ticket))
                name = "%s-%s-%s.json" % (tree, kind, pid or os.getpid())
                _write(_path("running", name), {"tree": tree, "kind": kind, "pid": pid, "pid_since": started_at(pid), "queued": queued,
                    "started": time.time(), "ram_gb": row["ram_gb"], "commit_gb": commit_of(row), "gpu": row["gpu"], "using_gb": 0.0,
                    "using_commit_gb": 0.0, "watched": watched, "estimate": estimate})
                waited = time.time() - queued
                lean = ", lean" if estimate != kind else ""
                log("start", tree, kind, ("waited %.0f s" % waited if waited >= POLL_SECONDS else "") + lean)
                if waited >= POLL_SECONDS:
                    print("heavy_job: %s %s starts after waiting %.0f s%s" % (tree, kind, waited, lean), file=sys.stderr)
                return name, estimate
        waited = time.time() - queued
        if time.time() - said >= 60.0:
            said = time.time()
            print("heavy_job: %s %s waiting %.0f min, %s of %d in the queue: %s (the machine, not this script; heavy_job status shows the rest)" % (
                tree, kind, waited / 60, _ordinal(place), len(queue), why), file=sys.stderr)
        if waited >= LONG_WAIT_SECONDS and not long_logged:
            long_logged = True
            log("waiting", tree, kind, "%.0f s, %s of %d: %s" % (waited, _ordinal(place), len(queue), why))
        time.sleep(POLL_SECONDS)


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
            if entry["kind"] != kind or entry.get("watched"):
                continue
            if entry["tree"] != tree:
                if mine is None:
                    mine = set(ancestors(os.getpid()))
                if not entry.get("pid") or int(entry["pid"]) not in mine:
                    continue
            name = entry.pop("file")
            entry["adopted_by"] = os.getpid()
            entry["adopted_since"] = started_at(os.getpid())
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


def run(tree, kind, command, expect_minutes=None):
    # A gated run inside another (frame_budget.ps1 under a bench script run
    # through the gate) would queue behind its own parent forever: the outer
    # run already holds the room and measures every process under it.
    outer = _outer_run()
    if outer is not None:
        print("heavy_job: %s %s inside %s's %s run, which holds and measures it; not queued again" % (
            tree, kind, outer["tree"], outer["kind"]), file=sys.stderr)
        log("nested", tree, kind, "inside %s %s" % (outer["tree"], outer["kind"]))
        return shell_code(subprocess.call(command))
    restarts = 0
    while True:
        adopted, estimate = _adopt_take(tree, kind)
        if adopted is not None:
            name = adopted
            print("heavy_job: %s %s inside this tree's take, measured as a run" % (tree, kind), file=sys.stderr)
        else:
            name, estimate = wait_turn(tree, kind, os.getpid(), True)
        started = time.time()
        row = kinds()[kind] if estimate == kind else (lean_row(kinds(), kind) or kinds()[kind])
        # A soak below normal priority, and what it starts with it (Windows
        # gives a below-normal process's children its class).
        flags = getattr(subprocess, "BELOW_NORMAL_PRIORITY_CLASS", 0) if row.get("below_normal") else 0
        child = subprocess.Popen(command, env=dict(os.environ, **{HELD_ENV: name, KIND_ENV: estimate}), creationflags=flags)
        job = Job(child)
        peak, low, stopped, long_logged = 0.0, 0, False, False
        gpu_peak, commit_peak, at_once = 0.0, 0.0, 0.0
        # What held the memory at its peak (394 amended (10)): the listing
        # taken when the commit last rose past the one before.
        listed, listed_gb, listed_at = [], 0.0, 0.0
        limit = limit_seconds(row, expect_minutes)
        samples, ended = [(started, job.cpu_seconds())], None
        while child.poll() is None:
            time.sleep(WATCH_SECONDS)
            using, committed, peaks = job.memory()
            peak = max(peak, using, peaks)
            at_once = max(at_once, using)
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
            elif idle and not row["gpu"]:
                ended = ("hung", "hung: %.1f%% of a core the last %.0f min" % (share * 100, HUNG_SECONDS / 60))
            if ended is not None:
                job.stop()
                child.wait()
                break
            if not long_logged and time.time() - started >= LONG_HOLD_SECONDS:
                long_logged = True
                log("long", tree, kind, "still running after %.0f min" % (LONG_HOLD_SECONDS / 60))
                print("heavy_job: %s %s has held the gate %.0f min" % (tree, kind, LONG_HOLD_SECONDS / 60), file=sys.stderr)
            free = free_ram_gb()
            low = low + 1 if free < MARGIN_GB else 0
            if (adopted is None and low >= LOW_WATCHES and entry is not None and should_stop(entry, running, free)
                    and child.poll() is None):
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
                    _write(_path("running", name), entry)
            if not stopped and ended is None and (peak > 0.0 or commit_peak > 0.0 or code == 0):
                table = _read(_path("kinds.json")) or {}
                saved = dict(kinds()[estimate])
                if peak > 0.0:
                    saved["ram_gb"] = updated_estimate(saved["ram_gb"], peak)
                    if saved["gpu"] and gpu_peak > 0.0:
                        saved["gpu_gb"] = updated_estimate(saved["gpu_gb"], gpu_peak)
                    saved["last_peak_gb"] = round(peak, 2)
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
        log("stopped", tree, kind, "free RAM under %.0f GB after %.0f s (peak %.1f GB); restart %d of %d" % (
            MARGIN_GB, duration, peak, restarts, MAX_RESTARTS))
        print("heavy_job: %s %s stopped: free RAM under %.0f GB, the newest job; queued again" % (tree, kind, MARGIN_GB), file=sys.stderr)
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


def take(tree, kind, pid):
    outer = _outer_run()
    if outer is not None:
        print("heavy_job: %s %s inside %s's %s run, which holds it; nothing taken" % (
            tree, kind, outer["tree"], outer["kind"]))
        return 0
    _, estimate = wait_turn(tree, kind, pid, False)
    print("heavy_job: %s %s taken%s" % (tree, kind, " (lean, as %s)" % estimate if estimate != kind else ""))
    return 0


def release(tree, kind):
    outer = _outer_run()
    if outer is not None:
        # What a take inside a run "took" was the run's own entry.
        print("heavy_job: %s %s inside %s's %s run; nothing to release" % (tree, kind, outer["tree"], outer["kind"]))
        return 0
    with StateLock():
        for entry in _entries("running"):
            if entry["tree"] == tree and entry["kind"] == kind and not entry.get("watched"):
                os.remove(_path("running", entry["file"]))
                log("done", tree, kind, "released after %.0f s" % (time.time() - entry["started"]))
                print("heavy_job: %s %s released" % (tree, kind))
                return 0
    print("heavy_job: %s holds no %s" % (tree, kind), file=sys.stderr)
    return 1


def holds(tree, kind):
    """Whether [tree] holds a [kind] now (a take, or a run going): a script
    called inside it (land.sh, under its session's take) does not queue
    again."""
    with StateLock():
        return any(entry["tree"] == tree and entry["kind"] == kind for entry in _entries("running"))


def status():
    with StateLock():
        running = _entries("running")
        queue = _entries("queue")
    free_gpu, used_gpu = gpu_gb()
    free_ram, free_commit = _memory()
    print("free RAM %.1f GB (margin %.0f GB), commit %s, GPU %s" % (free_ram, MARGIN_GB,
        "%.1f GB free (margin %.0f GB)" % (free_commit, COMMIT_MARGIN_GB) if free_commit is not None else "unknown",
        "%.1f GB free" % free_gpu if free_gpu is not None else "unknown"))
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
        print("running %s %s, %s, using %.1f of %.1f GB%s%s" % (entry["tree"], entry["kind"],
            "held %.0f of %.0f min" % (held / 60, limit / 60) if limit is not None else "%.0f s" % held,
            entry.get("using_gb", 0.0), entry["ram_gb"], ("" if entry.get("watched") else " (taken)")
            + (" (lean)" if entry.get("estimate", entry["kind"]) != entry["kind"] else ""), flag))
    for place, entry in enumerate(queue, 1):
        print("queued %s %s, %.0f s (%s)%s" % (entry["tree"], entry["kind"], time.time() - entry["queued"], _ordinal(place),
            ", lean" if entry.get("estimate", entry["kind"]) != entry["kind"] else ""))
    if not running and not queue:
        print("no heavy jobs")
    return 0


def show_kinds():
    for name, row in sorted(kinds().items()):
        print("%-14s %5.1f GB RAM, %.1f GB commit%s%s%s%s" % (name, row["ram_gb"], commit_of(row),
            ", GPU %.1f GB" % row["gpu_gb"] if row["gpu"] else "",
            ", at most %d at once" % row["max_running"] if row.get("max_running") is not None else "",
            ", last peak %.1f GB" % row["last_peak_gb"] if "last_peak_gb" in row else "",
            " (commit %.1f)" % row["last_commit_gb"] if "last_commit_gb" in row else ""))
    return 0


def summary(day):
    lines = []
    try:
        with open(_path("heavy_jobs.log")) as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 5 and parts[0].startswith(day) and (parts[1] in SUMMARY_EVENTS or "waited" in parts[4]):
                    lines.append(parts)
    except OSError:
        pass
    if not lines:
        print("%s: no heavy job waited or was stopped" % day)
    for when, event, tree, kind, detail in lines:
        if event == "launch":
            detail = detail.split("; backtrace:")[0]  # The whole one stays in the log.
        print("%s %s %s %s: %s" % (when[11:16], tree, kind, event if event in SUMMARY_EVENTS else "waited", detail))
    counts = ["%d %s" % (sum(1 for each in lines if each[1] == event), event) for event in ("overrun", "hung", "launch")]
    print("%s: %s" % (day, ", ".join(counts)))
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
SUMMARY_EVENTS = ("stopped", "waiting", "long", "overrun", "hung", "launch")
## What a script outside the gate may log with `note` (decision 530: a test
## scene that died at launch, before any of its own code ran).
NOTE_EVENTS = ("launch",)


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
    if command in ("run", "take", "release", "holds") and (len(args) < 3 or args[2] not in kinds()
            or kinds()[args[2]].get("variant_of")):
        print("heavy_job: %s <tree> <kind>, a kind of: %s" % (command, ", ".join(sorted(kinds()))), file=sys.stderr)
        return 2
    if command == "run":
        if "--" not in args or args.index("--") == len(args) - 1:
            print("heavy_job: run <tree> <kind> [--expect MIN] -- <command...>", file=sys.stderr)
            return 2
        options = args[3:args.index("--")]
        expect = None
        if options:
            if options[0] != "--expect" or len(options) != 2:
                print("heavy_job: run <tree> <kind> [--expect MIN] -- <command...>", file=sys.stderr)
                return 2
            expect = float(options[1])
        return run(args[1], args[2], args[args.index("--") + 1:], expect)
    if command == "take":
        pid = int(args[args.index("--pid") + 1]) if "--pid" in args else None
        return take(args[1], args[2], pid)
    if command == "release":
        return release(args[1], args[2])
    if command == "holds":
        return 0 if holds(args[1], args[2]) else 1
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
    print("heavy_job: no command %s (run, take, release, status, kinds, summary, note)" % command, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

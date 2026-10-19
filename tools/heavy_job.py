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
    build's: one build measured 20 to 42 ms a frame by what ran beside it).

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
holds a take of the kind (land.sh under its landing's take) adopts the
take instead of queueing: it measures the take's entry, so what it is owed
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
A soak meant to run for hours says so with --expect.

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

Standard library only (ctypes for Windows), so any Python can run it by path.
"""
import ctypes
import datetime
import json
import os
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
    "suite": {"ram_gb": 6.5, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["bench"], "max_minutes": 90},  # tests/land.sh: 6.3 GB measured
    "bench": {"ram_gb": 3.0, "gpu_gb": 0.0, "gpu": False, "max_running": 1, "excludes": ["suite"], "max_minutes": 90},
    "godot_import": {"ram_gb": 2.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90},
    "godot_export": {"ram_gb": 3.0, "gpu_gb": 0.0, "gpu": False, "max_minutes": 90},
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


def should_stop(me, running, free_ram_gb):
    """Whether the watched job [me] stops its child: free RAM is under the
    margin and no running job started after it."""
    if free_ram_gb >= MARGIN_GB:
        return False
    return all(each["started"] <= me["started"] for each in running)


def limit_seconds(row, expect_minutes=None):
    """How long a run of [row]'s kind may hold the gate: [expect_minutes]
    when given, else OVERRUN_FACTOR times the median of its recorded runs
    ("runs_s"), never under the floor, else its max_minutes; None: no limit."""
    if expect_minutes is not None:
        return expect_minutes * 60.0
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


def alive(pid):
    if not pid:
        return False
    if os.name == "nt":
        kernel = ctypes.windll.kernel32
        handle = kernel.OpenProcess(0x1000, False, int(pid))  # PROCESS_QUERY_LIMITED_INFORMATION
        if not handle:
            return False
        code = ctypes.c_ulong()
        kernel.GetExitCodeProcess(handle, ctypes.byref(code))
        kernel.CloseHandle(handle)
        return code.value == 259  # STILL_ACTIVE
    try:
        os.kill(int(pid), 0)
        return True
    except OSError:
        return False


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

        class Counters(ctypes.Structure):
            _fields_ = [("cb", ctypes.c_ulong), ("faults", ctypes.c_ulong),
                ("peak_working_set", ctypes.c_size_t), ("working_set", ctypes.c_size_t),
                ("quota_peak_paged", ctypes.c_size_t), ("quota_paged", ctypes.c_size_t),
                ("quota_peak_nonpaged", ctypes.c_size_t), ("quota_nonpaged", ctypes.c_size_t),
                ("pagefile", ctypes.c_size_t), ("peak_pagefile", ctypes.c_size_t)]
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
    for attempt in range(20):
        try:
            os.replace(temp, path)
            return
        except PermissionError:
            # Windows: something (a scanner, a reader) has it open a moment.
            time.sleep(0.05)
    os.replace(temp, path)


def kinds():
    saved = _read(_path("kinds.json")) or {}
    table = {}
    for name, first in KINDS.items():
        table[name] = _split(dict(first, **saved.get(name, {})), first["ram_gb"])
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
    for name in sorted(os.listdir(_path(folder))):
        if not name.endswith(".json"):
            continue
        entry = _read(_path(folder, name))
        if entry is None:
            continue
        pid = entry.get("pid")
        stale = bool(pid) and not alive(pid)
        if folder == "queue" and entry.get("waiter"):
            stale = stale or not alive(entry["waiter"])
        if folder == "running" and not entry.get("watched") and not alive(entry.get("adopted_by")):
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
    Returns the running entry's file name."""
    row = dict(kinds()[kind], kind=kind)
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
        _write(_path("queue", ticket), {"tree": tree, "kind": kind, "pid": pid, "waiter": os.getpid(), "queued": queued})
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
            ahead = [dict(kinds().get(each["kind"], row), kind=each["kind"]) for each in queue[:place - 1]]
            # First in the queue, or every job before it waits on its own
            # kind alone (may_pass): an import is not held behind a suite
            # waiting for a suite.
            free_ram, free_commit = _memory()
            head = may_pass(row, ahead, running, free_ram, free_commit)
            ok, why = decide(row, running, head, free_ram, free_gpu, free_commit)
            if not ok and head and out_of_reach(row, running, free_ram, free_commit):
                why += "; out of reach even with no heavy job running (memory held outside the gate): jobs that fit go past it"
                if place < len(queue):
                    # Steps to the back itself: waiters started from an older
                    # heavy_job.py (a tree not yet rebased) don't know the
                    # rule above and would hold behind it (107 minutes,
                    # 2026-10-18). Its turn comes again as the queue drains.
                    aside = "%019d-%s-%s.json" % (time.time_ns(), tree, pid or os.getpid())
                    os.replace(_path("queue", ticket), _path("queue", aside))
                    ticket = aside
                    log("aside", tree, kind, "out of reach; to the back of %d" % len(queue))
            if not head and queue and queue[0]["file"] != ticket:
                first = queue[0]
                first_row = dict(kinds().get(first["kind"], row), kind=first["kind"])
                first_gpu = gpu_gb()[0] if first_row["gpu"] else None
                _, first_why = decide(first_row, running, True, free_ram, first_gpu, free_commit)
                why = "the head, %s %s, waits on: %s" % (first["tree"], first["kind"], first_why or "its next look")
            if ok:
                os.remove(_path("queue", ticket))
                name = "%s-%s-%s.json" % (tree, kind, pid or os.getpid())
                _write(_path("running", name), {"tree": tree, "kind": kind, "pid": pid, "queued": queued,
                    "started": time.time(), "ram_gb": row["ram_gb"], "commit_gb": commit_of(row), "gpu": row["gpu"], "using_gb": 0.0,
                    "using_commit_gb": 0.0, "watched": watched})
                waited = time.time() - queued
                log("start", tree, kind, "waited %.0f s" % waited if waited >= POLL_SECONDS else "")
                if waited >= POLL_SECONDS:
                    print("heavy_job: %s %s starts after waiting %.0f s" % (tree, kind, waited), file=sys.stderr)
                return name
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
    """The file name of [tree]'s take of [kind] in running/, marked adopted
    by this wrapper (it does not age out while this lives), or None."""
    with StateLock():
        for entry in _entries("running"):
            if entry["tree"] == tree and entry["kind"] == kind and not entry.get("watched"):
                name = entry.pop("file")
                entry["adopted_by"] = os.getpid()
                _write(_path("running", name), entry)
                return name
    return None


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
        return subprocess.call(command)
    restarts = 0
    while True:
        adopted = _adopt_take(tree, kind)
        if adopted is not None:
            name = adopted
            print("heavy_job: %s %s inside this tree's take, measured as a run" % (tree, kind), file=sys.stderr)
        else:
            name = wait_turn(tree, kind, os.getpid(), True)
        started = time.time()
        child = subprocess.Popen(command, env=dict(os.environ, **{HELD_ENV: name}))
        job = Job(child)
        peak, low, stopped, long_logged = 0.0, 0, False, False
        gpu_peak, commit_peak = 0.0, 0.0
        row = kinds()[kind]
        limit = limit_seconds(row, expect_minutes)
        samples, ended = [(started, job.cpu_seconds())], None
        while child.poll() is None:
            time.sleep(WATCH_SECONDS)
            using, committed, peaks = job.memory()
            peak = max(peak, using, peaks)
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
                    "--expect" if expect_minutes is not None else "%g x its kind's median run, or its max_minutes" % OVERRUN_FACTOR))
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
                saved = dict(kinds()[kind])
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
                table[kind] = saved
                _write(_path("kinds.json"), table)
        if ended is not None:
            log(ended[0], tree, kind, "stopped after %.0f min, %s; peak %.1f GB" % (duration / 60, ended[1], peak))
            print("heavy_job: %s %s stopped after %.0f min, %s; if it is meant to run longer, pass --expect MIN "
                "(heavy_job run %s %s --expect MIN -- ...)" % (tree, kind, duration / 60, ended[1], tree, kind), file=sys.stderr)
            return STOPPED_CODE
        if not stopped:
            log("done", tree, kind, "exit %s, %.0f s, peak %.1f GB, commit %.1f GB" % (code, duration, peak, commit_peak))
            return code
        restarts += 1
        log("stopped", tree, kind, "free RAM under %.0f GB after %.0f s (peak %.1f GB); restart %d of %d" % (
            MARGIN_GB, duration, peak, restarts, MAX_RESTARTS))
        print("heavy_job: %s %s stopped: free RAM under %.0f GB, the newest job; queued again" % (tree, kind, MARGIN_GB), file=sys.stderr)
        if restarts > MAX_RESTARTS:
            return 75


def take(tree, kind, pid):
    outer = _outer_run()
    if outer is not None:
        print("heavy_job: %s %s inside %s's %s run, which holds it; nothing taken" % (
            tree, kind, outer["tree"], outer["kind"]))
        return 0
    wait_turn(tree, kind, pid, False)
    print("heavy_job: %s %s taken" % (tree, kind))
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
            entry.get("using_gb", 0.0), entry["ram_gb"], "" if entry.get("watched") else " (taken)", flag))
    for place, entry in enumerate(queue, 1):
        print("queued %s %s, %.0f s (%s)" % (entry["tree"], entry["kind"], time.time() - entry["queued"], _ordinal(place)))
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
        print("%s %s %s %s: %s" % (when[11:16], tree, kind, event if event in SUMMARY_EVENTS else "waited", detail))
    counts = ["%d %s" % (sum(1 for each in lines if each[1] == event), event) for event in ("overrun", "hung")]
    print("%s: %s" % (day, ", ".join(counts)))
    return 0


## The log's events the daily summary lists.
SUMMARY_EVENTS = ("stopped", "waiting", "long", "overrun", "hung")


def main(args):
    if not args or args[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    command = args[0]
    if command in ("run", "take", "release", "holds") and (len(args) < 3 or args[2] not in kinds()):
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
    print("heavy_job: no command %s (run, take, release, status, kinds, summary)" % command, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

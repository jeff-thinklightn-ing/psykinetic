# Psykinetic

Read `docs/roadmap.md` before starting work: it says what is being built, in what order,
which worktree owns each step, and the design rules not to break without asking Jeff.

## Folders

- `C:\dev\psykinetic` (`main`): home base. Pulls, plays the latest, small chores, keeps
  `docs/roadmap.md` and this file current. Two sessions work here, coordinator and release
  (below). Feature work happens in a worktree.
- `C:\dev\psykinetic-trees\<name>` (branch `<name>`): one worktree per job in the roadmap
  (`perf`, `pc-character`, ...). One Claude Code session per folder.

## Who to ask (two sessions in the main folder; ListAgents shows their names)

- **coordinator**: the roadmap and `docs/roadmap.md`, priorities, what each tree does
  next, cross-tree design (send it your design before you build a step; it approves and
  routes between trees), questions for Jeff and his "waiting on you" list, the weekly
  summary, and this file.
- **release**: landing and shipping. The landing lock (it may freeze `main`, settle who
  lands next, and clear a stale lock), decision numbers, `PROTOCOL_REVISION` numbers and
  release versions, cutting the batched releases, deploying the server, the box's health
  and rollbacks, `CHANGELOG.md`, and `THIRD_PARTY.md`. Ask it for a number before you
  commit; tell it when you land (commit, protocol change, new `class_name`).
- A design question goes to the coordinator first; once approved, get its decision number
  from release.

## Landing work

- Only `main` is released. In a worktree, rebase onto `origin/main` before each change,
  run `tests/land.sh` (or `land.ps1`: the suite's scenes at once, beside net_test and
  state_test; decision 278), commit, and land it per change with `git push origin HEAD:main`. If the push is refused, `main`
  moved: rebase, retest, push again. A branch never collects unlanded work.
- Take the landing lock for your final retest and push, so nobody lands between them:
  `sh tools/land_lock.sh take <tree> "<what>"`, then fetch, rebase, retest, push, and
  `sh tools/land_lock.sh release <tree>`. If it's held, keep working and try again in a
  few minutes; never push while another tree holds it. Don't hold it for anything else
  (record clips and run benches before taking it): a landing takes under 10 minutes, and
  a land lock older than 15 is stale and may be taken over. If taking it fails, stop: a
  script must never push after a failed take.
- Releases are batched (Jeff, 2026-10-14): worktrees don't run `tools/release_client.ps1`.
  A tested change lands on `main` straight away, with its bullets added under
  `## Unreleased` at the top of `CHANGELOG.md` (create the heading if it's missing). The
  release session cuts releases: it freezes `main` briefly, runs the suite on `main`, inserts
  the next `## vX.Y.Z` heading under `## Unreleased` (decision 324), runs the release script, deploys the server,
  and unfreezes. Between releases `main` runs ahead of the box; that's expected. Say in
  your landing message if your change alters the wire format, so it isn't left unreleased.
  After a rebase, check your bullet still sits under `## Unreleased`, above the first
  `## v` heading: a cut moves the heading, and git keeps a bullet beside the old top one.
- Every architectural choice gets its own numbered entry at the bottom of
  `docs/decisions.md`, in the same commit as the code. With several worktree sessions
  running, ask the release session for the number before
  committing, so two trees don't take the same one.
- After a pull or rebase that brings in a new `class_name`, run
  `godot --headless --path . --import` before testing: each worktree has its own `.godot`
  class cache, and without it scripts naming the new class fail to compile. Name any new
  `class_name` when you report a landing.
- The release session deploys the server to the box after releases; worktree sessions don't.
- Worktrees share one Godot `user://` folder (`%APPDATA%/Godot/app_userdata/Psykinetic`),
  which holds the edited-level overlay every test reads. Tests, benches and tools never
  write levels there: register them in memory (`Level.register`), point `Level.overlay_dir`
  at a private folder, or run with `APPDATA` set to a temp folder. Ports come from
  `tests/port_offsets.txt` (`tests/test_ports.gd`); temp folders are named per checkout,
  and any `user://` path a test writes comes from `test_ports.gd`'s `scratch(name)`
  (`user://tests_<checkout>/name`), never a fixed `"user://x/"`.
  Each test scene needs a base port and scratch name of its own: `tests/suite_test` fails
  the suite when two share one, since the scenes now run at the same time.
- Worktrees share one machine's CPU: take the bench lock before any run whose timings
  you report (map_bench, frame numbers, network benches with many processes):
  `sh tools/bench_lock.sh take <tree> "<what>"`, then `release <tree>` after. If it's
  held, wait. Keep many-process runs short. A windowed clip recording (Godot's movie
  maker writes gigabytes of frames and starves everything else) counts as a heavy run:
  take the bench lock for it too, and clear its frames from `%TEMP%` after.
- Heavy jobs go through the resource gate (Jeff, 2026-10-17): before a mesh or image
  generation, a full test suite, a bench, a Godot import or export, ask `tools/heavy_job`
  (perf lands it; until then, one such job per session at a time and the bench lock). The
  gate checks free RAM (and GPU memory for GPU jobs) against the job kind's recorded
  estimate plus an 8 GB margin and how many heavy jobs already run; if there is no room the
  job waits in its queue rather than starting. Estimates update from what jobs actually
  used. If free memory falls under the margin while jobs run, the newest job's own wrapper
  stops it first; nobody stops another session's job. The daily summary lists jobs that
  waited or were stopped.
- Stop only processes you started, by PID. Never `taskkill /IM` or `pkill` a program
  name: that kills every tree's Godot, including other sessions' tests and benches.
  Stopping a background task can leave its shell script and Godot children running: after
  stopping one, find its children by command line and stop them by PID too.
- Joining depends on `Net.protocol()`, not the build (decision 239). A new message kind,
  RPC script, or property you `replicate()` must be listed in `net/net.gd`
  (`MESSAGE_KINDS`, `RPC_SCRIPTS`, `SUBCLASS_REPLICATED`); `tests/protocol_test` names
  what's missing. A change to what an existing message or RPC carries, or to what a
  replicated value means, needs `PROTOCOL_REVISION` bumped: see the comment above it in
  `net/net.gd`. Say in your landing message if the protocol changed
  (`godot --headless --path . -- --print-protocol` before and after); a protocol change
  needs the server redeployed with the next release, a client-only change doesn't.
- Edit files with the editor tool, not shell heredocs or `sed`, when the text has
  backslashes: heredocs here have eaten `\` line continuations and turned `\a` or `\t` in
  Windows paths into control characters. From python, write a backslash as `chr(92)`.
- Never commit a real token: check the diff of `project.godot`.

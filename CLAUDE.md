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
  state_test; decision 278; since 450 it also exports the server pack and boots it with one
  client joining, about 60 s beside the suite), commit, and land it per change with `git push origin HEAD:main`. If the push is refused, `main`
  moved: rebase, retest, push again. A branch never collects unlanded work.
- Take the landing lock for your final retest and push, so nobody lands between them, with
  the resource gate taken first (decision 394): `sh tools/heavy_job.sh take <tree> suite`
  (waits if the machine is short, holding no lock yet), then
  `sh tools/land_lock.sh take <tree> "<what>"`, then fetch, rebase, import, `bash
  tests/land.sh` (it sees your take and doesn't queue again), push,
  `sh tools/land_lock.sh release <tree>`, and `sh tools/heavy_job.sh release <tree> suite`.
  Never wait on the gate while holding the land lock. The suite take covers that landing's
  import; elsewhere run an import as `sh tools/heavy_job.sh run <tree> godot_import --
  "$GODOT_PATH" --headless --path . --import`, and a plain test run just calls land.sh,
  which gates itself. If the lock is held, keep working and try again in a
  few minutes; never push while another tree holds it. Don't hold it for anything else
  (record clips and run benches before taking it): a landing takes under 20 minutes (a
  lean one about 16), and a land lock older than 25 is stale and may be taken over (667). If taking it fails, stop: a
  script must never push after a failed take.
- Releases are batched (Jeff, 2026-10-14): worktrees don't run `tools/release_client.ps1`.
  A tested change lands on `main` straight away, with its bullets added under
  `## Unreleased` at the top of `CHANGELOG.md` (create the heading if it's missing). The
  release session cuts releases: it freezes `main` briefly, runs the suite on `main`, inserts
  the next `## vX.Y.Z` heading under `## Unreleased` (decision 324), runs the release script, deploys the server,
  and unfreezes. Between releases `main` runs ahead of the box; that's expected. The cadence (coordinator, 2026-10-21, after a day's work sat unreleased): release cuts once a day in the morning, and sooner when Jeff asks or a fix he has seen is in. Say in
  your landing message if your change alters the wire format, so it isn't left unreleased.
  Every cut comes with a checklist for Jeff (Jeff, 2026-10-23: "for every cut i need a change
  log of things to check"): when release says the box is up, the coordinator writes
  `C:/dev/review/cuts/<version>.md` from the cut's CHANGELOG section, grouped by where to go, each
  line what to do and what to look for, with known leaks and what is not in the build, and gives
  him the path.
  After a rebase, check your bullet still sits under `## Unreleased`, above the first
  `## v` heading: a cut moves the heading, and git keeps a bullet beside the old top one; since 539, land.sh fails on a bullet in a shipped section or in two places, naming it, and (539 amended (4), 0fc2e053) on any non-bullet line under `## Unreleased`: one line per bullet, never wrapped. On a CHANGELOG-only rebase conflict, run `python -B tools/changelog_resolve.py`, then `GIT_EDITOR=true git rebase --continue`, once per commit that stops; never keep both sides (four trees' own resolvers did, each costing a refused landing, 2026-10-20).
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
- A windowed Godot (a shot run, a clip, a windowed bench, the editor) takes the screen and the GPU
  from Jeff: when the coordinator says he is working on this machine (Blender, a play test), no
  tree opens one until the all-clear; headless tests and landings go on (Jeff, 2026-10-21: "godot
  needs to be opened in --headless, i can't get anything done in blender"). A shot run that must
  happen puts its window off-screen (`--position 4000,4000`) and never takes focus.
  Every test, shot or clip Godot a session starts also runs silent, with `--audio-driver Dummy`
  (Jeff, 2026-10-28: test windows' music rang on his speakers).
- Heavy jobs go through the resource gate (Jeff, 2026-10-17): before a mesh or image
  generation, a full test suite, a bench, a Godot import or export, run it through the gate:
  `sh tools/heavy_job.sh run <tree> <kind> -- <command>` (or `heavy_job.ps1`; kinds:
  trellis_mesh, comfy_batch, suite, bench, godot_import, godot_export, soak, scene; `status`, `kinds` and
  `summary` show the rest; `take`/`release` only for a script that can't wrap). Perf lands
  it; until then, one such job per session at a time and the bench lock. The gate checks
  free RAM (and GPU memory for GPU jobs) against the kind's recorded estimate plus an 8 GB
  margin and how many heavy jobs already run; if there is no room the job waits in a
  first-come queue rather than starting. Estimates update from what jobs actually used.
  Take the gate before the land lock, never while holding it (the landing flow above);
  `heavy_job holds <tree> <kind>` says whether your tree already holds a kind. A script run
  under `heavy_job run` doesn't call heavy_job itself: before perf's f2892ae a nested take
  queued behind its own parent for ever and, since suites and benches exclude each other,
  stalled every landing (ui's bench did, 10 hours, 2026-10-18); now the inner call passes
  through (HEAVY_JOB_HELD), but the outer run is the one that gates and measures. Every gated
  run has a time limit (`--expect MIN`, else about 3× the kind's recorded run, else 90 minutes):
  past it, or idle under 3% of a core for 10 minutes, its own wrapper stops it (exit 5), so a
  long soak passes `--expect`, and every Godot line under the gate carries `timeout` and
  `</dev/null` (npc's soak with a parse error spun 7.6 hours overnight, 2026-10-19). If free
  memory falls under
  the margin while jobs run, the newest job's own wrapper stops it first and retries;
  nobody stops another session's job. The daily summary lists jobs that waited or were
  stopped. A soak (a run that counts sim days, not timings: town_soak, town_balance, npc's 30-day
  run) is the `soak` kind since 394's eighth amendment (751cb726): it runs beside suites, never beside a
  bench, one at a time, at below-normal priority, with a 180-minute default limit (`--expect` overrides);
  never register a soak as a bench (economy's 150-minute soak as a bench held five landings and a cut,
  2026-10-21). A test scene run alone goes through the gate as `scene` (`sh tools/heavy_job.sh run
  <tree> scene -- /usr/bin/timeout 900 "$GODOT_PATH" --headless --path . --scene tests/x.tscn --
  --run-marker=<n> </dev/null`): beside a suite at below-normal priority, two at most, never beside a
  bench (394 amended (17); ungated solo scenes stole CPU from landings and failed their timing checks).
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
- The box's world and players stay on the box: never copy `/var/lib/psykinetic/world.json`, the
  overlay or a player record off it, and never run a player's id in a local client. Read the box
  through grepped journal and log lines, and keep no file holding names or ids (2026-10-17).

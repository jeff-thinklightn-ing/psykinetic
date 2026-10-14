# Psykinetic

Read `docs/roadmap.md` before starting work: it says what is being built, in what order,
which worktree owns each step, and the design rules not to break without asking Jeff.

## Folders

- `C:\dev\psykinetic` (`main`): home base. Pulls, plays the latest, small chores, keeps
  `docs/roadmap.md` and this file current. Feature work happens in a worktree.
- `C:\dev\psykinetic-trees\<name>` (branch `<name>`): one worktree per job in the roadmap
  (`perf`, `pc-character`, ...). One Claude Code session per folder.

## Landing work

- Only `main` is released. In a worktree, rebase onto `origin/main` before each change,
  test, commit, and land it per change (`git push origin HEAD:main`, or release with
  `tools/release_client.ps1`, which pushes `HEAD:main` itself). If the push is refused,
  `main` moved: rebase, retest, push again. A branch never collects unreleased work.
- A tested change to the game is released straight away: `## vX.Y.Z` section at the top of
  `CHANGELOG.md`, then `tools/release_client.ps1` with the next version (needs
  `GODOT_PATH`, a clean tree, the Windows export template and `gh`). Docs and tools-only
  changes land on `main` without a release.
- Every architectural choice gets its own numbered entry at the bottom of
  `docs/decisions.md`, in the same commit as the code. With several worktree sessions
  running, ask the coordinator (the session in the main folder) for the number before
  committing, so two trees don't take the same one.
- Releases take turns the same way: ask the coordinator for the version before running
  `tools/release_client.ps1`, so a release being retested doesn't lose its number to
  another tree's.
- After a pull or rebase that brings in a new `class_name`, run
  `godot --headless --path . --import` before testing: each worktree has its own `.godot`
  class cache, and without it scripts naming the new class fail to compile. Name any new
  `class_name` when you report a landing.
- The coordinator deploys the server to the box after releases; worktree sessions don't.
- Worktrees share one Godot `user://` folder (`%APPDATA%/Godot/app_userdata/Psykinetic`),
  which holds the edited-level overlay every test reads. Tests, benches and tools never
  write levels there: register them in memory (`Level.register`), point `Level.overlay_dir`
  at a private folder, or run with `APPDATA` set to a temp folder. Ports come from
  `tests/port_offsets.txt` (`tests/test_ports.gd`); temp folders are named per checkout.
- Worktrees share one machine's CPU: take the bench lock before any run whose timings
  you report (map_bench, frame numbers, network benches with many processes):
  `sh tools/bench_lock.sh take <tree> "<what>"`, then `release <tree>` after. If it's
  held, wait. Keep many-process runs short.
- Stop only processes you started, by PID. Never `taskkill /IM` or `pkill` a program
  name: that kills every tree's Godot, including other sessions' tests and benches.
- Server and client must be built from the same commit; a release that changes the wire
  format needs the server redeployed (`server/deploy.sh`, on Jeff's box).
- Never commit a real token: check the diff of `project.godot`.

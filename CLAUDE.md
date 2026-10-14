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
- Server and client must be built from the same commit; a release that changes the wire
  format needs the server redeployed (`server/deploy.sh`, on Jeff's box).
- Never commit a real token: check the diff of `project.godot`.

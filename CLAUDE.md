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
  lands next, and clear a stale lock), `PROTOCOL_REVISION` numbers and
  release versions, cutting the batched releases, deploying the server, the box's health
  and rollbacks, `CHANGELOG.md`, and `THIRD_PARTY.md`. Ask it for a revision number before
  you commit; tell it when you land (commit, protocol change, new `class_name`). Decision
  numbers come from a script since 834 (Landing work, below); release settles a clash or a
  mis-issued label there.
- A design question goes to the coordinator first; once approved, take its decision number
  from the script (`sh tools/decision_number.sh new <tree> "<what>"`).
- New player-facing lines (dialogue, windows, signs, barks) go to the `voice` worktree session
  for wording before they land (Jeff, 2026-10-31); facts in them still go to `lore`. A
  CHANGELOG bullet is a player-facing line too: voice reads its words before the commit that
  carries it, not after it lands.
- The interface is two trees (Jeff, 2026-11-09): `ui` owns what a window does (behaviour and
  flow), `ui-design` owns how it looks (theme, fonts, the shared parts, spacing). A new or
  changed window gets `ui-design`'s mock before `ui` builds it, and no window script sets a
  colour, font or size of its own. Since 840 every landing checks it (`tests/style_test`): each
  file's line in `tests/style_budget.txt` (theme overrides, loose colours, fonts) only falls, so
  a new one goes into `ui-design`'s theme, and lowering a file's count lowers its line in the
  same commit. A raise is asked of `ui-design`, who brings it to the coordinator.

## Content ships as packages (Jeff, 2026-11-06)

"Coordinate so that these additions go in as packages. So a sign can't go in before the
place, and a text and loot don't go in before a quest is in."

- A package is everything a player can see, hear or be told about one addition: the place
  or building, its entrance and link, the signs and waystones pointing at it, its map name
  and found-place reward, its creatures, its loot and caches, its quest steps, its lines
  (barks, talk, lore facts given to residents or the companion) and its sounds.
- A player meets a package whole or not at all. A piece may land on `main` before the rest
  only switched off (hidden, unreachable and unmentioned) in a released build; nothing
  visible points at a piece that isn't in.
- The coordinator names each package and its pieces when approving the design, and says
  which tree switches it on. Tell the coordinator in your landing message which package
  your piece belongs to and whether it lands off.
- Before each cut, release lists any player-visible piece on `main` whose package isn't
  complete; the coordinator rules on each (switch it off, or hold the cut) before the
  build goes out. Cut checklists list only complete packages.

## No tree is idle (Jeff, 2026-11-11)

"what made me call this out is animation reporting nothing to do", on the morning he reported
that the walk looks like skipping and the people look like "bad claymation place holders".

- A tree with nothing queued, or waiting on the gate or a freeze, doesn't ask "what next". It
  looks at its own area in the game as a player meets it (Umbrage first, ordinary play, the
  nearest zoom) and brings the coordinator its three worst things: one line each, with a still
  or a number, and what it would do. A report of Jeff's goes first, then queued work, then this.
- Passing tests and a far-camera still are not "it looks right". Art and animation are shown at
  the nearest zoom beside Jeff's goblin before they land. A look names its camera (out of doors
  the low camera, a new player's own, or the high one, with its zoom: the playing zoom is low at
  1.0, the nearest 0.4; inside a walled space the overhead "inside view", 671), its distance, and
  is shot with the player standing in the place: a panned lens shows what no player sees
  (2026-11-14: a "tipped fir" was a branch round a panned lens). A tour's click or key goes in
  as an input event (`Input.parse_input_event`), never as a direct call to Main's handler: a
  direct call is not a player's press, and beside a parsed Shift it failed where no player
  could (11-15, the bow's taps). A tour's click is the bot's own (`tests/tour/bot.gd`'s `click`,
  aimed by `Client3D.screen_point_of`; 935 amended (8), (9)): the press is picked at the event's
  own position, on the cell, and no pointer is warped per click (on a laptop one warp to the game
  window's centre a run at most, on the coordinator's terms). A check that reads the same
  for the right pose and the wrong one is no watch: a stance is read by its clip's name, and a
  still's time comes from the run's log (11-14: an axe's edge direction passed for the ready
  and the rest alike). A still that needs the town's people settles on the town's step
  (`World.steps >= 310`: the settled are found at the first turn, step 300), not a frame count.
- Playtest runs a look pass on every released build: close stills of each kind of person and
  creature, the player walking and a companion following, kept in
  `C:/dev/review/look/<version>/` and laid beside the last build's. A difference nobody intended
  is reported the day it appears.

## Landing work

- Only `main` is released. In a worktree, rebase onto `origin/main` before each change,
  run `tests/land.sh` (or `land.ps1`: the suite's scenes at once, beside net_test and
  state_test; decision 278; since 450 it also exports the server pack and boots it with one
  client joining, about 60 s beside the suite), commit, and land it per change with `git push origin HEAD:main`. If the push is refused, `main`
  moved: rebase, retest, push again. A branch never collects unlanded work.
- Before you queue a landing, run on your own take the tests that use what your diff changes,
  plus any that failed your last landing (a solo scene through the gate is minutes; a failed
  landing costs every tree behind you a suite). Grep the tests for a constant, name or count you
  changed: of the four takes that failed their landing for a real fault on 11-10 and 11-11, two
  had not run the failing test (a slot count raised from 22 to 27 with two tests hard-coding 22),
  one met a broken main and one a true clash with another tree's new check
  (`C:/dev/review/perf/flakes.md`). Also run `bash tests/land.sh --checks` (`land.ps1 -Checks`)
  on the rebased take before you queue (278 amended (5)): the checks a landing makes before the
  gate (the CHANGELOG's bullets, Godot launches' logs, the lists' lines, the server prints' names
  (284 amended (2): a server print never names a companion or a player, and
  `tools/print_names_budget.txt` only falls), the voice inventory), with no lock and no Godot,
  in seconds; it prints `LANDING CHECKS: PASS` or `FAIL (why)`, and a FAIL there would have
  failed your landing after its wait in the queue. A tool test (not a Godot part) that fails
  on a temp-folder fault (Permission denied, unable to write file, Access is denied, no failed
  check) is rerun once, 5 s later, and the PASS/FAIL line says "; retried: <tests> (temp
  folder)" (278 amended (8)). A tool test stops only a process it can still show is its own
  (its pid made before it recorded it, or its command line unchanged), never a pid alone
  (perf-timed's landing, 11-13 22:19); heavy_job_test's real takes go by a free-memory figure
  of the test's own, never read by a real take (394 amended (50)). Since 278 amended (9) (7c4dcbbf9) view_test and
  view_land_test each run as two scenes (view_test and view_world_test, view_land_test and
  view_land_far_test, one script each with a port of its own): a new row goes in the half whose
  list names its subject (the header of each half says what it holds), a take that adds a var to Client3D runs both
  halves before it queues (the every-var check, `_test_neighbour_swap`, wants each sorted into
  `client3d/room_fields.gd`'s VIEW or ROOM and runs in view_world_test: a take that ran
  view_test alone failed its landing on it, 11-14), and land.sh names any suite
  scene over 220 s as a warning ("slow scene: ..."), never a failure: its tree splits it at its
  next row. Since 278 amended (10) level_test is two scenes too, two scripts over
  `tests/level_test_base.gd`: level_dungeons_test holds the laid levels (the barrow and its deep,
  the crypts, camps and bands, the castle), level_test the rest; a new row goes in its half.
  Never run the same scene twice at once from one checkout: both take one port.
  After any rebase that brings in other trees' landings, a take that changes a `.gd` runs `bash
  tools/load_check.sh` again before its gate take, and a FAIL is not queued: two takes that each
  add the same name merge cleanly and no longer parse (economy's and ui's `const RACK_REACH` in
  main.gd, 11-17). A mend for a report of Jeff's never waits on a bench to queue: the bench follows.
- Take the landing lock for your final retest and push, so nobody lands between them, with
  the resource gate taken first (decision 394): `kind=$(bash tools/remote_tests.sh kind)`,
  `sh tools/heavy_job.sh take <tree> $kind`
  (waits if the machine is short, holding no lock yet), then
  `sh tools/land_lock.sh take <tree> "<what>"`, then fetch, rebase, import, `bash
  tests/land.sh` (it sees your take and doesn't queue again), push,
  `sh tools/land_lock.sh release <tree>`, and `sh tools/heavy_job.sh release <tree> $kind`.
  A release that can't remove the lock's folder (a file another process holds open on Windows)
  retries for 5 s, then prints `release incomplete`, logs the files left and exits 5 (667 amended
  (6), 116c867e1). Your push stands: log it and give back your gate take, never loop on the
  release. The remnant is held under your name and goes stale by the rule; the next take after
  that clears it. Only its owner or release releases it by hand.
  Fetch and rebase onto `origin/main` before you take the gate as well as after the lock, so
  the gate's waiter runs main's code: a take queued from an older checkout is judged by that
  older code until the tree rebases (394 amended (53), (54); `heavy_job.sh status` lists each
  take "on older gate code"). A queued row from older code that waits only on its own old count
  holds nobody behind it (394 amended (55), fe5d77b43): newer rows pass it, it keeps its place,
  and status notes it; rebase it all the same. The fetch and rebase after the lock's take stay
  as they are: they make the tested sha main's tip.
  The gate take, the lock take and `PSYKINETIC_TREE` are one name: a landing under a second
  name (`<tree>-<what>`) takes both as that name and sets `PSYKINETIC_TREE` to it, or leaves it
  unset (883: land.sh then takes the lock's name). On 11-15 a script took the gate and the
  lock as `animation-gather` and ran land.sh as `animation`: land.sh queued a second take
  behind its own lock, its beat kept the lock fresh, and no tree landed for 41 minutes.
  Since 883 amended (2) (a8cab46a6) such a landing stops at once: land.sh exits 7, holding
  nothing, when the lock was taken from its checkout under a name that is not `PSYKINETIC_TREE`
  (release the lock and run again under one name), and the gate answers exit 6, with nothing
  queued, to a landing's take asked from the checkout that holds the lock without its take.
  Neither is retried in a loop. `heavy_job.sh status` names a landing "self-waiting". Once every
  part has ended land.sh has 180 s to end, then fails itself with a line saying so (its first
  landing hung 46 minutes on a bare `wait`): give the lock back and run the landing again.
  Since 667 amended (3) (ffeb4a634) a land script's push is `sh tools/land_push.sh <tree>
  <tested sha>` in place of its own `git push`: `<tree>` is the lock take's name, `<tested
  sha>` the 40-hex sha the `LANDING TESTS: PASS ... tested <sha>` line names, called only
  after that PASS line with the lock still held. Each try is cut at 60 s; a network error is
  tried twice more, a minute apart, a refusal never (buildings' street check passed its tests
  and lost its turn to a five-minute connection timeout, 2026-11-13). Exit 0: on main; 1: not
  landed, run the landing again from the start; 2: a usage fault; 3: main frozen, release the
  gate's take and requeue. Every try is logged in `C:/dev/land.lock.log`.
  At a cut release first runs `land_lock.sh freeze`: from then a take answers exit 3, "main
  frozen (pending)", while the landing holding the lock finishes; treat it as a held freeze
  (release your gate take, requeue after the unfreeze) (667 amended (4)). A land script waits
  the freeze out itself, by the freeze's own mark and never by status's words ("freeze pending"
  passed a waiter grepping "frozen", 11-16): `while [ -n "$(find
  "${PSYKINETIC_LAND_LOCK:-/c/dev/land.lock}.freeze/beat" -mmin -26 2>/dev/null)" ]; do sleep
  60; done`, then it queues again; a take refused by a freeze gets that script at once, not a
  wait for word of the unfreeze.
  Since 394 amended (65) (b9cc225a2) a land script's fetch and rebase is `bash
  tools/land_rebase.sh <tree>` in place of its own `git rebase origin/main`: it runs the
  resolvers itself (the CHANGELOG, the generated pages, the lists) and at anything else aborts,
  leaves the checkout as it was and names the files (exit 1). `bash tools/land_rebase.sh --would
  [--no-fetch] <tree>` says whether that rebase would stop, touching no working tree: "clean",
  "resolvable: <files>" or "CONFLICT: <files>" (exit 1). A waiter runs it when it queues and
  when main's tip moves, and a CONFLICT is rebased by hand before its turn, not at it (a real
  conflict sat ninety minutes unseen in the queue, 11-16).
  A lock that reads free with takes waiting on it is short of room, not untried: `<lock>.log`'s
  "kept for <tree>: free, and N GB short" line says so (394 amended (63)). `heavy_job.sh
  status` prints "older room check: N of M landing takes" (394 amended (64)); while N is over 0
  no tree starts a solo scene, an import or a load_check of its own while the lock reads free
  with takes waiting: wait until a landing holds it. A waiter that steps out (stopped, or its
  take dropped) removes its own `<lock>.waiters/<tree>.json`. A take that changes the gate
  queues under main's gate code (a copy of `origin/main`'s `tools/heavy_job.py`), never its own
  unlanded code, and its diff is answered by the coordinator first (an unlanded gate change's
  own waiter stalled the queue an hour, a cut's export with it, 11-16).
  Since 878 (Jeff, 2026-11-11: "go ahead and move landings' test runs to saturn") a landing's
  Godot tests (the suite, state_test, net_test) run on saturn through `tools/remote_tests.sh`,
  in about 8 minutes, with server_boot_test and the tool tests here: `kind` prints
  `suite_remote` when saturn answers and your work is committed, else `suite`, which runs
  everything here as before. Saturn tests the commit, so commit before you take. A lost
  connection fails the landing: run it again, never push on it. A saturn slot whose landing
  is gone on this PC (no land-lock beat in 150 s and no gate take, or this tree's own earlier
  sha while it holds the lock) is taken over at once by the next prepare, logged in saturn's
  `~/land/.slot_clears.log` (878 amended (1)). Since 878 amended (2) (e508cf6ab) a landing's
  saturn prepare can fail, and its line says why: "SATURN SLOT REFUSED: ... requeue" (or
  "waited 10 minutes") is another landing's slot, never this commit's fault: no part ran,
  requeue; "the import failed" is this commit's own import on saturn, its SCRIPT ERROR lines
  above it; "saturn does not have", "could not check out" or "is not clean" is a send or
  checkout fault: requeue and tell perf. A landing gives its slot back itself on every way
  out; nobody clears one by hand. A first landing under a new tree name takes
  saturn's newest scene times (90 amended (2)); the landing log's "durations:" line says where
  its caps came from, and a tree that reads "durations: none" tells perf. `LAND_LOCAL=1` keeps
  everything here (the cut's suite on main does); `land.ps1` has no saturn path. This is the
  only thing of a tree's that runs on saturn: a solo scene, a probe or a bench there is asked
  of the coordinator, and beyond a landing's own run no session writes to saturn without
  Jeff's own OK in that session.
  Never wait on the gate while holding the land lock. The suite take covers that landing's
  import; elsewhere run an import as `sh tools/heavy_job.sh run <tree> godot_import --
  "$GODOT_PATH" --headless --path . --import`, and a plain test run just calls land.sh,
  which gates itself. If the lock is held when your gate take starts, wait for it holding the
  take (394 amended (31): every try beats the take, so it never goes stale while you wait):
  `until sh tools/land_lock.sh take <tree> "<what>"; do c=$?; [ $c = 1 ] || break; sh
  tools/heavy_job.sh holds <tree> $kind || break; sleep 30; done` (30 s, not less: every try
  starts half a dozen processes, and this PC leaks memory by process starts). Exit 1 is
  another tree landing, the only one to wait on; exit 3 is main frozen: release your take and
  requeue after the unfreeze; a take no longer held, or any other exit: stop. A script pushes
  only when its own take of the lock returned 0; never push while another tree holds it. Don't hold it for anything else
  (record clips and run benches before taking it): a landing takes under 20 minutes (a
  lean one about 16), and a land lock is stale, and may be taken over, 25 minutes after its take or its last beat (667; since 667 amended land.sh beats it each minute while its tests run, so a live landing never goes stale and none is cut short to stay under 25). A
  script must never push after a failed take. Since 667 amended (2) (cd7f84f76) the lock's take
  itself clears what would stop the rebase: an untracked `*.import` or `*.uid` in your checkout
  that main has since begun to track (an import's `.uid` written before the file was committed
  stopped three fronted landings at their rebase on 11-12, a model's `.import` four on 11-13);
  each removal is logged in `C:/dev/land.lock.log`. Any other untracked file main now tracks
  refuses the take with exit 4, a line naming the file, and nothing held: exit 4 means stop and
  read the line, never retry it in a loop; move or commit the file, then take again.
  `land.sh --checks` runs the same check, so you see it before you queue. A commit that adds a
  model or image carries its `.import` (import first, then `git status --short` clean).
- Releases are batched (Jeff, 2026-10-14): worktrees don't run `tools/release_client.ps1`.
  A tested change lands on `main` straight away, with its bullets added under
  `## Unreleased` at the top of `CHANGELOG.md` (create the heading if it's missing). The
  release session cuts releases: it freezes `main` briefly, runs the suite on `main`, inserts
  the next `## vX.Y.Z` heading under `## Unreleased` (decision 324), runs the release script, deploys the server,
  and unfreezes. Between releases `main` runs ahead of the box; that's expected. The cadence (coordinator, 2026-10-21, after a day's work sat unreleased): release cuts once a day in the morning, and sooner when Jeff asks or a fix he has seen is in. A mend for a report of Jeff's is cut the day it lands, not held for the morning, and a regression that blocks that cut is reverted, not waited on (Jeff, 2026-11-14, reporting the same four things a second time: "if the lag between feedback and change it is very difficult to give feedback"); its row in `C:/dev/review/your_reports.md` names the build to check and is fixed only when seen joined in the released build. Say in
  your landing message if your change alters the wire format, so it isn't left unreleased.
  A joined client draws its own pack's levels: levels are not in `Net.protocol()` and are not
  sent at a join. So say in your landing message if a `levels/` file changed and whether it is
  drawn decor only; before a cut that would put a client ahead of the box, release lists the
  level files changed since the box's tag, and the server goes out with the client unless every
  one is decor (v0.1.227: a client-only cut would have drawn a stair the server did not have).
  Every cut comes with a checklist for Jeff (Jeff, 2026-10-23: "for every cut i need a change
  log of things to check"): when release says the box is up, the coordinator writes
  `C:/dev/review/cuts/<version>.md` from the cut's CHANGELOG section, grouped by where to go, each
  line what to do and what to look for, with known leaks and what is not in the build, and gives
  him the path.
  After a rebase, check your bullet still sits under `## Unreleased`, above the first
  `## v` heading: a cut moves the heading, and git keeps a bullet beside the old top one; since 539, land.sh fails on a bullet in a shipped section or in two places, naming it, and (539 amended (4), 0fc2e053) on any non-bullet line under `## Unreleased`: one line per bullet, never wrapped. On a rebase conflict in CHANGELOG.md alone, or with the generated pages beside it (`docs/voice_inventory.md`, `docs/art_status.md`, `art/kit/status.json`: taken from main's side and regenerated, 539 amended (5), 4003d2a0c; `THIRD_PARTY.md` too since 539 amended (7), be392c4a1: its art and sound slot spans taken from main's side and made again, only when the commit changes nothing outside those spans; any other conflicted file it refuses), run `python -B tools/changelog_resolve.py`, then `GIT_EDITOR=true git rebase --continue`, once per commit that stops; never keep both sides (four trees' own resolvers did, each costing a refused landing, 2026-10-20).
- Every architectural choice gets its own numbered entry at the bottom of
  `docs/decisions.md`, in the same commit as the code. With several worktree sessions
  running, take the number from the script before committing, so two trees don't take the
  same one (834, open since 2026-11-10; never a guessed number): `sh tools/decision_number.sh
  new <tree> "<what>"` for a new decision, `amend <tree> <decision> "<what>"` for the next
  `amended (k)`, `status` for what is out, `drop <tree> <number-or-label> "<why>"` to give one
  back. A follow-up that lands on its own takes the next amended (k) from the script; a
  paragraph added to work not yet landed stays under its hand-out and takes nothing; a tree
  landing its side of a decision the coordinator named uses that decision's number and takes
  nothing. Until the script is mended, a paragraph never names another tree's unlanded label by
  its number (it says "environment's speaker fade, unlanded"): the script counts a label as
  landed wherever its words appear in `docs/decisions.md` (11-14: 623 amended (8), quoted in
  another tree's landed paragraph, could not be given back).
- After a pull or rebase that brings in a new `class_name`, run
  `godot --headless --path . --import` before testing: each worktree has its own `.godot`
  class cache, and without it scripts naming the new class fail to compile. Name any new
  `class_name` when you report a landing.
- The lists every tree adds a name to are one name a line, in order by the name's text (944,
  b939185bd): `client3d/room_fields.gd`'s VIEW and ROOM, `net/net.gd`'s MESSAGE_KINDS and
  SUBCLASS_REPLICATED. A new name goes on a line of its own in its place, never at the end
  (two takes that each added to one line cost the second its turn: sound's 940, 38 minutes on
  the lock, 2026-11-15). `python -B tools/list_lines.py` checks them (land.sh's checks and
  `--checks` run it) and `--fix` writes them so. A rebase that stops in either file with a
  conflict in the lists' names alone: `python -B tools/list_lines.py --fix`, `git add
  client3d/room_fields.gd net/net.gd`, `GIT_EDITOR=true git rebase --continue`. Exit 2 is some
  other conflict in the file: that one is resolved by hand.
- The release session deploys the server to the box after releases; worktree sessions don't.
- Worktrees share one Godot `user://` folder (`%APPDATA%/Godot/app_userdata/Psykinetic`),
  which holds the edited-level overlay every test reads. Tests, benches and tools never
  write levels there: register them in memory (`Level.register`), point `Level.overlay_dir`
  at a private folder, or run with `APPDATA` set to a temp folder. Ports come from
  `tests/port_offsets.txt` (`tests/test_ports.gd`); temp folders are named per checkout,
  and any `user://` path a test writes comes from `test_ports.gd`'s `scratch(name)`
  (`user://tests_<checkout>/name`), never a fixed `"user://x/"`.
  Each test scene needs a base port and scratch name of its own: `tests/suite_test` fails
  the suite when two share one, since the scenes now run at the same time. Since 278 amended
  (2) it claims every port a test asks `test_ports.gd` for, base or not: write each as a
  number, one of the file's constants, or either `+ k` (a variable it can't read fails,
  naming the line), and run `suite_test` alone before queuing a take that adds a test or a port.
- Worktrees share one machine's CPU: take the bench lock before any run whose timings
  you report (map_bench, frame numbers, network benches with many processes):
  `sh tools/bench_lock.sh take <tree> "<what>"`, then `release <tree>` after. If it's
  held, wait. Take a bench's gate take first and the bench lock when it starts (`heavy_job.sh
  run` for the bench with the bench lock taken inside it, or take/holds before the lock);
  never hold the bench lock while waiting on the gate, as with the land lock (2026-11-14: a
  bench queued about five hours behind the evening's landings held the bench lock all that
  time; a timing that can't find its gap is asked of the coordinator for saturn or a laptop).
  Since 394 amended (56) (4eb0fd78c) `heavy_job.sh status` and the daily summary name a bench
  or soak queued over an hour ("landings keep passing it: ask the coordinator for saturn or a
  laptop"): ask then, rather than wait on.
  Keep many-process runs short. A windowed clip recording (Godot's movie
  maker writes gigabytes of frames and starves everything else) counts as a heavy run:
  take the bench lock for it too, and clear its frames from `%TEMP%` after.
- A windowed Godot (a shot run, a clip, a windowed bench, the editor) takes the screen and the GPU
  from Jeff: when the coordinator says he is working on this machine (Blender, a play test), no
  tree opens one until the all-clear; headless tests and landings go on (Jeff, 2026-10-21: "godot
  needs to be opened in --headless, i can't get anything done in blender"). A shot run that must
  happen puts its window off-screen (`--position 4000,4000`) and never takes focus.
  Every test, shot or clip Godot a session starts also runs silent, with `--audio-driver Dummy`
  (Jeff, 2026-10-28: test windows' music rang on his speakers).
  Stills, clips and windowed benches run on the laptops through `tools/remote_shot.sh` (decision
  828 amended; `--runner lenovo|atlas`, Lenovo by default), with no clearance: a run starts at once
  on the laptop's screen, in front without taking focus, silent, so Jeff can watch (Jeff, 11-09:
  "i want the visuals to show up on screen ... so i can see what being done"); he stops it from its
  tray icon. Its runner.log says whether the laptop was used during the run and its power at start
  and end, so a bench says whether its timings count. Since 828 amended (2) it adds `--host` when
  no mode is named (without it the game sits at the connect screen and its numbers are void) and
  refuses a locked laptop; check a bench number against its "BENCH ran:" line. Each session needs Jeff's own OK, in that
  session, before writing to a laptop; a peer can't pass it on. This PC's off-screen runs are for
  when the laptops are busy or off, or a session lacks that OK, and still need the coordinator's
  window check. That check covers one start, at the minute it is given, and one off-screen
  Godot runs on this PC at a time: a script that loops over stills or clips asks before each
  start (2026-11-10: one tree's loop of seven stills stopped another's cleared run).
  `--position` alone does not stop a window taking focus as it is made: the launcher writes a
  temporary `override.cfg` in its checkout (`[display]`, `window/size/no_focus=true`) before
  Godot starts, removes it on exit, never commits it, and the run logs the flag.
- Heavy jobs go through the resource gate (Jeff, 2026-10-17): before a mesh or image
  generation, a full test suite, a bench, a Godot import or export, run it through the gate:
  `sh tools/heavy_job.sh run <tree> <kind> -- <command>` (or `heavy_job.ps1`; kinds:
  trellis_mesh, comfy_batch, suite, bench, godot_import, godot_export, soak, scene, net; `status`, `kinds` and
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
  stopped. Only release moves a queued job to the front (`heavy_job front <tree> <kind> --by
  release --why "<reason>"`, 394 amended (25)), for a change every queued landing pays for or on
  Jeff's word; a tree tells the coordinator why, never asks release. A soak (a run that counts sim days, not timings: town_soak, town_balance, npc's 30-day
  run) is the `soak` kind since 394's eighth amendment (751cb726): it runs beside suites, never beside a
  bench, one at a time, at below-normal priority, with a 180-minute default limit (`--expect` overrides);
  never register a soak as a bench (economy's 150-minute soak as a bench held five landings and a cut,
  2026-10-21). A test scene run alone goes through the gate as `scene`: `sh tools/heavy_job.sh run
  <tree> scene -- bash tests/run.sh tests/x_test.tscn </dev/null` (278 amended (6), e0ecaa47b: several
  scenes may be named; run.sh gives each its marker, port, log and time limit, stops a scene 3 s after
  a script of its fails to parse, and refuses net_test; the older line still works, `sh
  tools/heavy_job.sh run <tree> scene -- /usr/bin/timeout 900 "$GODOT_PATH" --headless --path .
  --scene tests/x.tscn -- --run-marker=<n> </dev/null`): beside a suite at below-normal priority, two
  at most, never beside a bench (394 amended (17); ungated solo scenes stole CPU from landings and
  failed their timing checks). Load a scene whose script you changed once this way before you send it
  to anyone or queue it: a parse error is seconds here and a failed landing in the queue.
  Before that, run `bash tools/load_check.sh` on every take that changes a script (278 amended
  (7)): it loads each changed `.gd` with the autoloads in, through the gate in seconds, and
  prints `LOAD_CHECK: PASS` or `FAIL` with the file named; use it in place of
  `--check-only`, which fails sound scripts and so was skipped or misread. It does not run the
  code: a fault met only at run time (a typed array given a plain one) still needs the scene.
  A load_check starts past the gate's queue when its 0.5 GB and the margin are free and no
  bench runs, one at a time, never counted toward the heavy-job cap (394 amended (48)); run it
  before queueing a take. An import (godot_import) also starts past the gate's queue (394
  amended (49)): one at a time, never beside a local suite or a bench; a load_check or import
  from a checkout older than that waits its turn, so rebase before running one.
  net_test run alone is the `net` kind (394 amended (24)): it starts several Godots (about 12 GB at
  once), so it runs one at a time, never beside a bench, and the gate refuses it under any other kind.
- Disk (2026-11-16: C: filled to 0.58 GB free and every landing stopped). A scratch worktree is
  removed by the session that made it (`git worktree remove`) when its take lands or is dropped,
  never one a live waiter or queued take runs in. Read the free space before any write over
  1 GB; under 40 GB free start nothing new on disk and tell the coordinator. Nobody runs `git
  worktree prune`, `gc` or `repack`: the shared store's upkeep is release's, at a freeze. A keep
  branch stays local; a branch goes to origin only when a laptop or saturn must build it, and
  its tree deletes it there after.
- Models (2026-11-17: a 10.5 GB model in this PC's Ollama left 4.4 GB of commit, and the land
  lock stood free two minutes with three takes kept for it). No model loads on this PC's Ollama
  unless `heavy_job.sh status` shows about 22 GB of commit free, never beside a cut's local
  suite, and only on a slot the coordinator gives. A Godot scene that asks the game's own mind
  is a model load (it sends keep_alive -1 and never unloads): a test or tour that is not that
  run points `PSYKINETIC_LLM_URL` at nothing (`http://127.0.0.1:9/api/chat`). A run that loads
  a model unloads it on every way out, a gate stop included, and never unloads one it did not
  load (the desktop's Ollama answers other work of Jeff's). A model's name stays off pushed pages.
- Stop only processes you started, by PID. Never `taskkill /IM` or `pkill` a program
  name: that kills every tree's Godot, including other sessions' tests and benches.
  Stopping a background task can leave its shell script and Godot children running: after
  stopping one, find its children by command line and stop them by PID too. Stop a PID only
  when it is in your own process tree and was created at or after your own run's start; never
  one matched on generic arguments (2026-11-12: a filter on `run-marker=1` stopped another
  tree's queued scene).
- A landing's waiter (its land script, from the gate take to the push) runs detached from the
  session's task shell: start it with the Start-Process wrapper (a .sh file it runs, not
  `bash -c "..."`, which Start-Process splits; unset PYTHONIOENCODING in it), writing its own
  log you read. Never as a run_in_background task alone: Claude Code stops an idle session's
  background shells when the machine is short of memory (2026-11-12 23:44, about ten
  sessions), and a waiter that dies with the shell loses its place.
- After a "stopped because the system is running low on memory" notice, check by PID and
  command line what actually died (the script, its heavy_job waiter, its Godots) before
  believing it: on 11-12 most scripts under the reaped shells lived on. Never requeue a take
  that is still alive. Restart only what is gone, and only when Jeff says so in that session,
  as the notice asks: the coordinator's or a peer's go does not count.
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

# Running the dedicated server

A Linux box runs the sim as a systemd service; players connect over the
tailnet. The server keeps a JSON snapshot of the room so a restart does not
reset it.

## What is involved

| Piece | Where |
| --- | --- |
| Export preset `Linux Server` (Linux, Dedicated Server type) | `export_presets.cfg` |
| systemd unit | `server/psykinetic.service` |
| Deploy script: pull, export, install, restart | `server/deploy.sh` |
| Snapshot code | `net/snapshot.gd`, used by `main.gd` |
| Console client | `server/admin.sh` → `--admin-port` |
| Token file template | `server/env.example` → `/etc/psykinetic/env` |
| Client bundle | `client/` (`launch.bat`, `update.ps1`, `README.txt`, `settings.example.cfg`), built by `tools/release_client.ps1` |
| Version | `version.txt`, `CHANGELOG.md` |

The service runs:

```
/opt/psykinetic/psykinetic-server --headless --server --port=7777 --state=/var/lib/psykinetic/world.json --token=${PSYKINETIC_TOKEN}
```

with `PSYKINETIC_TOKEN` read from `/etc/psykinetic/env`.

`--headless` is needed: the Dedicated Server export strips textures and
other visuals from the `.pck` but the binary is a normal one, so without the
flag it would try to open a window.

## One-time setup on the box

Needs: git, sudo, and a Linux Godot 4.7.2 editor binary with the Linux
export templates installed (Editor → Manage Export Templates, or put them in
`~/.local/share/godot/export_templates/4.7.2.stable/`). The export runs
headless, so the editor binary is used but never opens.

```sh
# The service user. No shell, no home of its own.
sudo useradd --system --home-dir /var/lib/psykinetic --shell /usr/sbin/nologin psykinetic

# Install location for the binary and .pck; state goes under /var/lib.
sudo install -d -o psykinetic -g psykinetic /opt/psykinetic
sudo install -d -o psykinetic -g psykinetic /var/lib/psykinetic

# The repo, and where Godot is.
git clone https://github.com/jeff-thinklightn-ing/psykinetic.git ~/psykinetic
export GODOT_PATH=/path/to/Godot_v4.7.2-stable_linux.x86_64   # put it in your shell profile too

# The join token. Root-only; the real file is never in the repo.
sudo install -d -m 755 /etc/psykinetic
sudo install -m 600 ~/psykinetic/server/env.example /etc/psykinetic/env
sudo sed -i "s/change-me/$(openssl rand -hex 16)/" /etc/psykinetic/env
sudo cat /etc/psykinetic/env     # note the token; players need it

# The unit.
sudo cp ~/psykinetic/server/psykinetic.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable psykinetic
```

Then do the first deploy (below). `deploy.sh` uses `sudo` for the install
and restart steps, so run it as a user that has it.

If the box has a firewall, open UDP 7777 to the tailnet.

## Deploy

```sh
~/psykinetic/server/deploy.sh
```

It does, in order, in `~/psykinetic`: `git clean -f -- '*.uid' '*.import'`
(untracked files the engine generated, which would block the pull once
the repo brings its own copy; tracked and ignored files are untouched);
`git pull --ff-only`; a headless import (`--import`), only ever after the
pull; a headless export of the `Linux Server` preset to `build/`; copies the binary to
`/opt/psykinetic/psykinetic-server` and the `.pck` next to it (the running
server keeps the files it started from); restarts it gracefully; prints the
service status. Without
`GODOT_PATH` set (as over a non-interactive ssh, where `.bashrc` is not
read) it uses the newest `~/godot/Godot_v*_linux.x86_64`.

The graceful restart (decision 240): once the build is exported,
`deploy.sh` asks the running server for `stop 60 update` on the console.
The players are told in the party chat, from `Server`, now and at 10 and 3
seconds left; at 0 the server saves the snapshot, lets everyone go and
exits 0, which the unit's `Restart=on-failure` leaves down. Only then is
the new build installed (a running server reads its `.pck` as it goes, so
it is never replaced under one) and started with `systemctl restart`.
Clients reconnect by themselves (every 2 seconds, for 3 minutes, the HUD
saying `server restarting, reconnecting… (n)`) and are put back where they
stood. If the server is still up a minute after the countdown, or anything
fails once it has stopped, `deploy.sh` installs and restarts it anyway.
`PSYKINETIC_RESTART_SECONDS` changes the countdown; `deploy.sh --now`
installs and restarts at once, as does a server too old to know `stop`, or
one not running.

`restart` on the console is the same countdown with exit code 75, which
systemd starts again after `RestartSec=5`, as the same build: a restart
without a deploy.

Staged (decision 242): `deploy.sh --staged` tries the new build before the
running server is touched. `server/stage.sh` prints the running server's
build and protocol beside the new one's and whether the clients must
update; starts the new build from `build/` as the deploying user on UDP
7787 with its console on 7788 (never 7777/7778, nor the box's Ollama on
11600), with a throwaway token and copies of the live snapshot and edited
levels, writing only under a temp folder (its mind log and transcripts
too); has a headless client (the Godot binary, on the repo) join, walk a
step and report; and stops it with `stop 0`, which must save and exit 0.
If any of that fails, or either printed a script error, `deploy.sh` stops
there with the staged logs' last lines and the live server as it was.

From the dev machine, `tools\deploy_box.ps1` (`-Now` for no countdown) is
the coordinator's one command after a release, and asks nothing: it prints
the box's build and protocol beside `origin/main`'s, and whether the
clients must update (and if so whether that version is released yet,
since an unpublished one leaves them nothing to update to); runs
`deploy.sh --staged` over ssh; and prints what the box runs afterwards. It
exits non-zero if staging or the deploy fails.

From the dev machine, `tools\ship.ps1` runs it over ssh as its last step
(`$env:PSYKINETIC_BOX`, default `jequig@100.78.120.114`), streams its
output, then runs `admin.sh players` to show the server is up; `-NoDeploy`
skips that. Its own pull before `deploy.sh` cleans the same way first.
Before it commits, `ship.ps1` runs a headless import on the dev machine
and refuses to go on if a script has no `.uid`, so every `.uid` is
committed with its script and the box never generates one first. It
then stops and lists any untracked file, unless given `-IncludeUntracked`,
so a file dropped into the project (an asset pack, say) is never swept
into a release by accident. The ssh key must be set up: the script never prompts.

The mind log: a dedicated server writes its companions' decisions to
`/var/lib/psykinetic/mind.log` (one JSON line each; see docs/design.md),
the service's state directory, without any flag. At 5 MB it is moved to
`mind.log.1` (replacing the one before) and a new one is started, so at
most about 10 MB is ever on disk.

Transcripts: beside it, `/var/lib/psykinetic/transcripts/` holds a
plain-text file per companion per day, `<companion>-<YYYY-MM-DD>.txt`
(server local time): a timestamped line for everything said to her and by
her, with events as short bracketed notes between them, exactly as her
voice sees the exchange. Files older than 30 days are deleted. On the
console, `transcript pip` prints today's and `transcript pip 2026-10-01` an
older one; or read the files directly:

```sh
sudo tail -f /var/lib/psykinetic/transcripts/Pip-$(date +%F).txt
```

`transcript rebuild` makes transcripts from the mind log too (`mind.log.1`
and `mind.log`), for the days before transcripts were kept: every voice
ask logged the recent exchange, so Jeff's lines, hers and the events are
all recovered, each timed when it was first seen. They head the day's
file between `[Rebuilt from the mind log ...]` and `[End of what was
rebuilt.]`; running it again replaces them, and lines written live are
kept.

The sudo commands `deploy.sh` runs: `install` (three times),
`systemctl restart psykinetic`, `systemctl status psykinetic` — exactly the
ones `/etc/sudoers.d/psykinetic-deploy` allows without a password. The
countdown needs no sudo: `admin.sh` and `systemctl is-active`.

`PSYKINETIC_REPO` overrides the repo location.

## Logs

The project sets `application/run/flush_stdout_on_print`, so every line
reaches journald as it is printed, not when a buffer fills.

```sh
journalctl -u psykinetic -f          # follow
journalctl -u psykinetic -n 200      # the last 200 lines
```

The server prints a line when it starts listening, when a peer joins or
leaves (`[net] peer N joined as PlayerN at (x, y)`), on every player move
with an occupancy check, one line per push, and `[state] ...` lines for the
snapshot.

```sh
systemctl status psykinetic          # running? last restart?
sudo systemctl restart psykinetic
```

The unit restarts the server 5 seconds after any failure.

## Console

The server takes four commands: `reset` (rebuild the room from the map;
player records are kept, anyone online keeps their place, and companions
that died come back; the reply names them), `respawn`
(bring every dead monster and crate back now), `players` (who is connected,
where, with what hp), `save` (write the snapshot now). Also `companions`,
`mind ...` (see the mind log), `zones` (each loaded zone, awake or
asleep, its tick and who is in it), `zone reset <name>` (rebuild that zone
from its map, loading it if need be; `reset` alone rebuilds the default
zone), `zone move <player> <zone>` (send a player and their companion
there), `version` (the build and protocol it runs), `restart [<seconds>]
[<why>]` (60 by default: count down, telling the players, then save and
exit 75 for systemd to start it again; the clients reconnect; see Deploy),
`stop [<seconds>] [<why>]` (the same, exiting 0: down until started, as
`deploy.sh` does), `restart cancel`, `reload <zone>|all` (read a zone's level
from disk again and rebuild it as builder mode does, the players staying
where they are, everyone there sent the new terrain: no restart; `all`
does each open zone whose level files changed since they were read, such as
an edited level put into the overlay by hand), and
`transcript <name> [<YYYY-MM-DD>]` (a companion's transcript, today's by
default); `help` lists them.

Players can also rebuild the room themselves: `R` in the game does what
`reset` does, for whoever presses it, and the server logs
`[world] <name> reset the room`. That is on while the game is only being
tested; add `--no-player-reset` to the unit's `ExecStart` to leave it to the
console.

Under systemd the server's stdin is closed, so the unit runs it with
`--admin-port=7778` and commands go over a localhost TCP connection, one
per connection, reply written back. `server/admin.sh` wraps that with
bash's `/dev/tcp`, no netcat needed:

```sh
~/psykinetic/server/admin.sh players
~/psykinetic/server/admin.sh respawn
~/psykinetic/server/admin.sh reset
~/psykinetic/server/admin.sh save
~/psykinetic/server/admin.sh restart 30 a quick fix
~/psykinetic/server/admin.sh transcript pip
```

It must run on the box; the port only listens on localhost. By hand:
`exec 3<>/dev/tcp/127.0.0.1/7778; echo players >&3; cat <&3`.

A server started in a terminal (or any mode with `--console`) also reads
the same commands from stdin.

`perception list|grid|both` switches what the companions are told they
see around them (see docs/design.md), for every companion at once, until
the next restart; `perception` alone says which. `--perception=` on the
command line (or `PSYKINETIC_PERCEPTION` in `/etc/psykinetic/env`) sets it
from the start.

Dead monsters and broken crates come back on their own after 60 seconds,
once no player is within 6 tiles of the spawn tile; `respawn` skips the
wait. Players still get their own 2-second respawn.

## Companion minds

Every player gets a companion. Its decisions come from a *mind*: the
scripted one by default, or a language model served by Ollama. To use one,
name the model in `/etc/psykinetic/env`; the URL is only needed if Ollama is
not on the same box at its usual port:

```
PSYKINETIC_LLM_URL=http://127.0.0.1:11434/api/chat
PSYKINETIC_LLM_MODEL=qwen3:14b
PSYKINETIC_MIND_WHY=1
```

(or pass `--llm-model=`, `--llm-url=` and `--mind-why`). The box runs
qwen3:14b, with each answer's reason in the mind log. The default URL is Ollama's native
chat endpoint. The server asks it for JSON output with reasoning off and the
model kept loaded (`"format": "json"`, `"think": false`, `"keep_alive": -1`),
so the first decision does not pay a model load; and each time a companion
comes into the world it asks the model to load (a chat with no messages),
so a restarted Ollama is ready before her first ask. A URL ending in
`/chat/completions` is treated as an OpenAI-compatible endpoint instead.

Her voice can run on its own endpoint and model, a bigger model on a bigger
card, while stances and the instruction check stay on the first (they want
speed, the voice wants words):

```
PSYKINETIC_VOICE_URL=http://<rig>:11434/api/chat
PSYKINETIC_VOICE_MODEL=qwen3:32b
```

(or `--voice-url=` and `--voice-model=`). Either left out is the same as
the `LLM` one.

Each decision is one request with a 2-second timeout; while it is out, or if
it fails or answers nonsense, the scripted mind's answer is used, and the log
says so (`[mind] ollama: ...`). The server never waits on it.

Console: `companions` lists each companion with its owner, intent and the
mind that answered last; `mind scripted` / `mind ollama` switches every
companion's mind at once. Players give orders with keys 1 (follow), 2 (hold
here), 3 (attack my target), 4 (fall back).

## Connecting a client

On a machine on the tailnet, with the project:

```
godot --path . --client --address=<tailnet-ip> --token=<the token>
```

Add `--port=<n>` if the server is not on 7777. `tailscale ip -4` on the box
gives the address. `F3` in the client shows peer id, round trip time and
mispredictions.

Players get the self-updating Windows client from a GitHub release (see
Releasing the client). They unzip it, run `launch.bat`, and the game asks
for the address and token once, then keeps them in `settings.cfg` next to
the exe. Nothing in the zip carries an address or token.

## Releasing the client

Versions live in `version.txt` at the project root (`0.1.0`). The game reads
it at start and a client sends it when it joins, but what decides whether it
may join is the protocol, `Net.protocol()`: a fingerprint of everything that
goes over the wire (decision 239). A client of another build with the same
protocol plays; so a release that changes only the client (looks, art, the
view) needs no server deploy, and a server deploy that changes nothing on
the wire leaves the clients as they are.

To tell which a release is: `--print-protocol` prints a build's version and
protocol (`PROTOCOL v0.1.140 3f2a91c0d4e7`) and quits; on the box, the
console's `version` says what the server runs. The same protocol: a
client-only release, the server stays. A different one: deploy the server
from the release's commit too.

On a Windows machine with the Windows export templates installed, a clean
working tree, and `gh` logged in:

```
tools\release_client.ps1                 # bumps the patch number: 0.1.0 -> 0.1.1
tools\release_client.ps1 -Version 0.2.0  # releases exactly that version
```

It writes `version.txt`, commits `Release vX.Y.Z` and tags it; exports the
`Windows Client` preset to `build\client\`; adds `version.txt`,
`launch.bat`, `update.ps1`, `settings.example.cfg` and `README.txt`; zips it
to `build\psykinetic-client-vX.Y.Z.zip`; then pushes the commit and tag and
runs `gh release create` with the top section of `CHANGELOG.md` as the
notes. Without `gh` it prints the manual steps instead. It refuses to zip if
any bundled text file carries a real token.

So before releasing: add a `## vX.Y.Z` section at the top of `CHANGELOG.md`
and commit it. Then, if the protocol changed, deploy the server
(`server/deploy.sh`) from the same commit.

A server and a client with different protocols cannot play: the one that is
behind is named (`client out of date` when the server's build is newer,
`server out of date` when the client's is). Deploying the server from a
newer commit that changes the wire *without* releasing leaves clients with
the same version number and another protocol: `build mismatch`. The F3
overlay shows the build and protocol (`build:`), and the server's build when
it differs.

Clients update themselves: `launch.bat` runs `update.ps1`, which asks the
GitHub API for the latest release, and if its tag is newer than the local
`version.txt`, downloads the zip and unpacks it over the client folder,
keeping `settings.cfg`. It waits for a running `psykinetic.exe` to quit
(15 seconds at most, then leaves the files alone), needs no admin rights,
and on any failure writes one line to `update.log` and starts the game
anyway.

The game also updates itself (decision 241): turned away as `client out of
date` by a server of a newer build (after a deploy that changed the
protocol, say, the clients reconnecting), an exported game starts
`update.ps1` and quits; it waits for the game, installs the latest release
and starts it again, which then joins. Never on `server out of date`, never
from the editor or a checkout, and never twice in 10 minutes: it writes
`update_marker.txt` beside the game first, so a release that still does not
match (the server deployed before the release was published) cannot loop;
the game then says it is out of date as before. So release the client
before deploying a server whose protocol changed. A client of an older
build with the same protocol plays, and is told once in the party chat
that a newer game is out.

## Join authentication

The server only accepts a peer that sends the token, its version and its
protocol (`Net.authenticate`, which the client does the moment it connects).
Until then the peer has no player and every gameplay RPC from it is ignored.
A protocol mismatch, or a wrong or empty token, is rejected at once; another
build with the same protocol is let in, logged as `[net] peer N is vX, the
server vY: the same protocol ..., so it plays`. A peer that sends nothing is
dropped after 5 seconds. The log line is
`[net] rejected peer N from <address> (<why>)`. At most 16 peers can be
authenticated at once (`--max-players=<n>` for fewer, or more); the rest
are refused as `server full`.

A rejected client is told why before it is cut off and shows it:
`authentication failed`, `client out of date` (another protocol, and the
server's build is newer: run launch.bat), `server out of date` (another
protocol, and the client's build is newer: the server is due a deploy),
`build mismatch` (another protocol under the same version number: release
and deploy from the same commit),
`already connected` (that player id is online already), or `server full`.

The hello also carries the client's `player_id` and name. The id is a UUID
the client makes on its first run and keeps in `settings.cfg`; it is how the
server knows a returning player. Deleting `settings.cfg` makes a new one, so
that player starts over.

`--server` refuses to start without `--token` (it logs why and exits 1).
`--host` without a token is local play: anyone who connects is let in.

To change the token: edit `/etc/psykinetic/env`, then
`sudo systemctl restart psykinetic`. Everyone needs the new one.

## The snapshot (`--state`)

With `--state=<path>` the server (or a host) writes a JSON snapshot every 30
ticks (3 seconds) and on clean shutdown, and loads it when it starts.

- **What is in it**: every level entity — monsters, crates, the boulder —
  with its type, name, tile, hp, stamina, facing and the static properties
  it was spawned with (mass, material, colour); and a record for every
  player who has ever joined, keyed by their `player_id`: name, tile, hp,
  stamina, facing, colour, last seen. A returning player is put back on
  that tile (or the nearest free one) with those stats and that colour.
- **What is not**: the room. Terrain always comes from the level
  (`levels/<name>/`, docs/levels.md). The file (version 2) holds every
  loaded zone, and each player's zone: a restart loads those zones again
  as saved and puts each player back in theirs. `--map` only says where new
  players start. An entity that died or broke is simply absent and stays gone.
- **Looks follow the build, not the file**: the file says where a level
  entity stands and how hurt it is; its shape, colour, size, mass and the
  rest come from the map in the build that loads it. A deploy that changes
  how a crate or the boulder looks shows up on the next start, with
  everything still where it was left.
- **Writes are atomic**: the file is written as `<path>.tmp` and renamed, so
  a crash mid-write leaves the previous snapshot intact.
- **Bad or missing file**: logged (`[state] ... starting fresh`) and the
  room is generated from scratch. Entries inside the file that make no sense
  are skipped with a warning; the rest still load. Nothing here crashes the
  server.
- **`R` on a host** rebuilds the room fresh, ignoring the snapshot; the next
  write then overwrites it.
- **Respawn timers**: a dead monster or crate is in the file as a slot
  with its remaining delay, so a restart does not reset the wait.
- **Shutdown**: `systemctl stop` sends SIGTERM, which Godot does not handle
  as a clean quit, so a stop can lose up to the last 3 seconds of state.
  Window close and in-game quit save properly.

To reset the world: stop the service, delete `/var/lib/psykinetic/world.json`,
start it again.

`tests/state_test.ps1` / `tests/state_test.sh` check the save, load and
bad-file paths headless.

## Perception eval

`tools\perception_eval.ps1`, on the dev machine, measures how well her
voice answers questions about what is around her in each perception mode,
against the box's model: it opens an ssh tunnel to the box's Ollama (port
11434 is not open to the tailnet), runs `tests/perception_eval.tscn`
headless through it, and closes the tunnel. Nothing is deployed and the
server is not touched, but it shares the box's Ollama with the server,
so its latency is only clean while nobody is playing. Eight fixed scenes
(test room and sample level) x four questions asked as Jeff x three modes
x `-Runs` (default 3); each answer is scored by keyword against the truth
the sim gives. The report (accuracy per mode and per question, latency,
prompt tokens) goes to `build\perception_eval.md`, every answer to
`build\perception_eval.jsonl`. `-Preview` prints the scenes, their maps,
lists and truth without asking the model. The first results are in
`docs/perception_eval.md`.

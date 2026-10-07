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
`/opt/psykinetic/psykinetic-server` and the `.pck` next to it;
`systemctl restart psykinetic`; prints the service status. Without
`GODOT_PATH` set (as over a non-interactive ssh, where `.bashrc` is not
read) it uses the newest `~/godot/Godot_v*_linux.x86_64`.

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
the service's state directory, without any flag. It grows; truncate it
when it gets large (`sudo truncate -s 0 /var/lib/psykinetic/mind.log`).

The sudo commands `deploy.sh` runs: `install` (three times),
`systemctl restart psykinetic`, `systemctl status psykinetic` — exactly the
ones `/etc/sudoers.d/psykinetic-deploy` allows without a password.

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
where, with what hp), `save` (write the snapshot now).

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
```

It must run on the box; the port only listens on localhost. By hand:
`exec 3<>/dev/tcp/127.0.0.1/7778; echo players >&3; cat <&3`.

A server started in a terminal (or any mode with `--console`) also reads
the same commands from stdin.

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
PSYKINETIC_LLM_MODEL=qwen3
```

(or pass `--llm-model=` and `--llm-url=`). The default URL is Ollama's native
chat endpoint. The server asks it for JSON output with reasoning off and the
model kept loaded (`"format": "json"`, `"think": false`, `"keep_alive": -1`),
so the first decision does not pay a model load. A URL ending in
`/chat/completions` is treated as an OpenAI-compatible endpoint instead.

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
it at start, a client sends it when it joins, and the server rejects any
other version with a `client out of date` message, so the server and the
clients must be released together.

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
and commit it. Then deploy the server (`server/deploy.sh`) from the same
commit so the versions match.

Deploying the server from a newer commit *without* releasing leaves clients
on the old build with the same version number. The server refuses those with
`build mismatch` (it compares a fingerprint of the wire format, shown as
`build:` in the F3 overlay), so: every server deploy that changes what goes
over the wire needs a client release from the same commit.

Clients update themselves: `launch.bat` runs `update.ps1`, which asks the
GitHub API for the latest release, and if its tag is newer than the local
`version.txt`, downloads the zip and unpacks it over the client folder,
keeping `settings.cfg`. It never runs while `psykinetic.exe` is running,
needs no admin rights, and on any failure writes one line to `update.log`
and starts the game anyway.

## Join authentication

The server only accepts a peer that sends the token and its version
(`Net.authenticate`, which the client does the moment it connects). Until
then the peer has no player and every gameplay RPC from it is ignored. A
version mismatch, or a wrong or empty token, is rejected at once; a peer
that sends nothing is dropped after 5 seconds. The log line is
`[net] rejected peer N from <address> (<why>)`. At most 4 peers can be
authenticated at once; the rest are refused as `server full`.

A rejected client is told why before it is cut off and shows it:
`authentication failed`, `client out of date` (with both versions),
`build mismatch` (same version number, but the server was built from
different code: release and deploy from the same commit),
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
- **What is not**: the room. Terrain always comes from the ASCII map in
  `main.gd`. An entity that died or broke is simply absent and stays gone.
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

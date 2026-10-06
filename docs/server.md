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

It does, in order: `git pull --ff-only` in `~/psykinetic`; a headless export
of the `Linux Server` preset to `build/`; copies the binary to
`/opt/psykinetic/psykinetic-server` and the `.pck` next to it;
`systemctl restart psykinetic`; prints the service status.

`PSYKINETIC_REPO` overrides the repo location.

## Logs

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
`authentication failed`, `client out of date` (with both versions), or
`server full`.

`--server` refuses to start without `--token` (it logs why and exits 1).
`--host` without a token is local play: anyone who connects is let in.

To change the token: edit `/etc/psykinetic/env`, then
`sudo systemctl restart psykinetic`. Everyone needs the new one.

## The snapshot (`--state`)

With `--state=<path>` the server (or a host) writes a JSON snapshot every 30
ticks (3 seconds) and on clean shutdown, and loads it when it starts.

- **What is in it**: every level entity — monsters, crates, the boulder —
  with its type, name, tile, hp, stamina, facing and the static properties
  it was spawned with (mass, material, colour). Not players: they belong to
  whichever peer is connected and are respawned when a peer joins.
- **What is not**: the room. Terrain always comes from the ASCII map in
  `main.gd`. An entity that died or broke is simply absent and stays gone.
- **Writes are atomic**: the file is written as `<path>.tmp` and renamed, so
  a crash mid-write leaves the previous snapshot intact.
- **Bad or missing file**: logged (`[state] ... starting fresh`) and the
  room is generated from scratch. Entries inside the file that make no sense
  are skipped with a warning; the rest still load. Nothing here crashes the
  server.
- **`R` on a host** rebuilds the room fresh, ignoring the snapshot; the next
  write then overwrites it.
- **Shutdown**: `systemctl stop` sends SIGTERM, which Godot does not handle
  as a clean quit, so a stop can lose up to the last 3 seconds of state.
  Window close and in-game quit save properly.

To reset the world: stop the service, delete `/var/lib/psykinetic/world.json`,
start it again.

`tests/state_test.ps1` / `tests/state_test.sh` check the save, load and
bad-file paths headless.

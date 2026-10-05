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

The service runs:

```
/opt/psykinetic/psykinetic-server --headless --server --port=7777 --state=/var/lib/psykinetic/world.json
```

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

On a machine on the tailnet, with the project or an exported client:

```
godot --path . --client --address=<tailnet-ip>
```

Add `--port=<n>` if the server is not on 7777. `tailscale ip -4` on the box
gives the address. `F3` in the client shows peer id, round trip time and
mispredictions.

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

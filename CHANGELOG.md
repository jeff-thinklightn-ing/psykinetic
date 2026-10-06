# Changelog

Newest first. `tools/release_client.ps1` uses the top section as the release
notes.

## v0.1.4

Fixes the client closing a few seconds after connecting.

- A client and server built from different code now refuse each other with
  a "build mismatch" message instead of the client crashing. The 0.1.3
  client did exactly that against a newer server.
- Player names show over their capsules, like companions' names.
- Coming back or respawning never puts you next to a monster: if one is
  within 5 tiles you appear on the safest start tile instead. For the first
  3 seconds, or until you move or attack, monsters leave you alone and your
  capsule is drawn faded.
- Companions: the join log now says what happened to yours (new, waiting for
  you, or died earlier). The language-model mind talks to Ollama's native
  endpoint with reasoning off.
- Entities are built from one generic scene, so new kinds of things can be
  added on the server without a client update.
- The boulder is now round.

## v0.1.0

First playable build.

- Isometric grid sim at 10 Hz: eight-direction movement, walking pushes,
  force pushes with impact damage, stun on collision, fire tiles, stamina
  that fades knockback as it runs down.
- Click to walk or attack, right click to shove, drag to toss in a chosen
  direction, including over your own head.
- Multiplayer over ENet with a dedicated Linux server, client-side
  prediction, join tokens, and a world snapshot that survives restarts.
- Self-updating Windows client: `launch.bat` checks GitHub for a newer
  release before starting the game.

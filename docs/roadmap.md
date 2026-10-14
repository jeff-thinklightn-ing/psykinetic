# Psykinetic roadmap

Last updated: 2026-10-14. Owner: Jeff. Every session reads this before starting work.
The player-facing version (for Dire) lives in a separate doc; this one is for building.

## Goal right now

The foundations work (co-op server, zones, physics combat, talking companions, level
editor, art pipeline). What's missing is a reason to play: something to find, something
you become, someone to save. Everything below serves the first scenario: rescue the smith.

## Top priority: builder mode (`builder` worktree)

Real-time map building in the game, driven by the Claude API, so places with things to do
can be made quickly. This is the most important track right now.

| Pass | Job | Done when |
|------|-----|-----------|
| 1 | **Canvas and stamps** | Editor resize (grow/shrink from any side; entities and level.json shift to match). A 256 × 256 outdoor map `levels/wilds` with forest edges. Prefabs: select an area in the editor, save as a named prefab (terrain, edges, entities, idle behaviours) under `levels/prefabs/`, stamp anywhere with rotation. Seed a few by hand: small house, campfire camp (gather points), fenced field, well. |
| 2 | **Area tools** | Usable by hand in the editor: pond (water blob with shore), grove (scattered trees, optional clearing), path between clicked points (winding, with width), fence/wall line, scatter (rocks, crates, bushes). Each with size and seed, and undo. |
| 3 | **Builder mode** | In-game dev toggle (B): drag to select an area, type a request ("a pond here", "a goblin camp guarding a chest"). The server sends the area, its contents, the legend and the prefab list to Claude (key in `/etc/psykinetic/env`, never in the client or repo) with tools for paint terrain, path, place entity (monsters with idle behaviour, chests with contents), stamp prefab, and the area tools. Edits show as a ghost preview; Enter accepts, Esc discards, follow-ups refine ("bigger", "move it north"). Accepted edits go through the editor's undo and save to the map files. Log cost per request; spend limit set in the Console. |
| 4 | **New area at an edge** | Needs the world map from `maps` (edge links, the area graph). Builder tool `new_area(side, size, description)`: when the selection touches a map edge, create a new level with forest edges, link both ways through `neighbours` (walk off one edge, arrive at the matching edge at the same position), optionally draft it from the description, load it live. Undo removes area and link. |

It should place *things to do*, not just scenery: chests with loot, camps to clear,
captives, puzzles, larders. The first thing built with it: the farmstead for the smith scenario.

## Order of work (combat and characters)

Each step is what the next one needs. Weapons only feel good if you can read them;
a story only matters if there's something to fight with.

| # | Step | Done when | Worktree |
|---|------|-----------|----------|
| 1 | **Performance** | 256² map: load < 2 s (3D build included), server tick < 20 ms at castle density with many players spread over the map (Jeff: "needs to accommodate larger numbers"; benched at 1, 4, 9 and 16 players), 60 fps on the laptop; per-frame scripts < 4 ms at 128², < 8 ms at 256². Far-away monsters think less often (full rate within ~30 cells of a player/companion, reduced at 30–60; fights always full rate). Beyond that, and in zones nobody is in, the world is not paused: it moves on at a slow world tick (see "The world moves on" below). | `perf` |
| 2 | **Network smoothness** | No rubber-banding in a castle fight. Knockback sent as one event (direction, distance, start tick) every client plays identically; others drawn ~100–150 ms in the past and interpolated; corrections blended, not snapped; camera follows a smoothed position. Report corrections/min and worst snap before/after. | after `perf` (same client code) |
| 3 | **Combat animation states** | Synced from sim state: wind-up (longer for heavy attacks), strike, recover, hit (direction-aware), pushed (matches knockback event), knocked down (fall/lie/get up, timed to sim), block, guard break, death. Clean blends, no popping. | after `pc-character` |
| 4 | **Player character** | One shared humanoid body for players and companions, human proportions so the animation library fits, hand attach points for weapons. Replaces the capsule. | `pc-character` |
| 5 | **Weapon models** | Hammer, sword, shield, giant axe, spear, dagger, bow — flat, faceted style, attach to hand bones. | art session (Blender MCP) |
| 6 | **Weapons as verbs** | See "How it plays". Each weapon changes what the attack does in the physics; one of each in the castle chests; tests per verb. Items become instances (today an item is a bare id) and start recording their history here. | later |
| 7 | **The smith scenario** | A map and story to use it all in (see below). | later |

### The world moves on (design rule for the performance work)

Activity while players are away or out of range is part of the game (camps grow, captives
are moved, enemies hold and retake ground; see the backlog's offline consequences). So
nothing far away is simply paused, but it doesn't need the 10 Hz sim either:

- **Near players:** the full tick, as now.
- **Far, or a zone with nobody in it:** a slow world tick (seconds to minutes apart) that
  moves things on in coarse steps: who holds what, where groups are, what has grown or
  been taken. No pathfinding cell by cell and no hits.
- **When players arrive:** the area is settled from where the world tick left it (on wake,
  where `World._woke` logs the time asleep today), then runs at the full tick.
- **Offline:** the world tick keeps running on the server with no one connected, at the
  same coarse rate.

- **Movement is real** (Jeff, 2026-10-14): groups on the world tick walk real paths at their
  own speed, never jump, inside areas as well as between them.
- **Held ground is physical:** a group can't route through ground another faction holds
  (the cells within a held place's radius; contested ground blocks everyone). It goes
  around, or it meets the holders and the world tick makes the encounter (fight or take).
- **Server downtime pauses the world:** the world tick's clock is saved and resumes where it
  stopped; nothing is caught up for the time the server was down. Players being offline
  pauses nothing.

Perf should leave room for this when it builds the far-monster cut-off: the far tier
hands over to the world tick, not to a stop.

## Running in parallel (not on the critical path)

| Worktree | Job |
|----------|-----|
| `companions` | Repetition filter compares normalized text (curly/straight quotes, case, punctuation); stay silent more readily after minor events; a real OPEN/CLOSE DOOR action the voice can choose; record last words in transcripts. |
| `live-updates` | Protocol version separate from build version (only a protocol mismatch blocks joining); graceful update (60 s chat warning, save, restart, clients auto-reconnect); client self-update on reconnect; live reload for data files; then auto-deploy in the ship flow; a staging port where a new build is checked before swapping in. |
| `maps` | **World map and connectivity.** One graph of every area (nodes) and how they connect (edges): today's point links in each `level.json` plus edge links (`neighbours`: walk off one edge, arrive at the matching edge at the same position). A validation pass: links go both ways where they should, spawn points exist, no area is unreachable. A node map view in the editor (Godot's `GraphEdit`/`GraphNode`): areas as boxes, links as wires, add/remove/retarget links, open an area. Routing between areas over the graph (Godot's `AStar2D`) for the world tick to move groups across areas. Builder pass 4 builds on it. Done (decisions 194–206, with territory: places, factions, holdings, routes that keep off held ground). Now: **send each player only nearby entities** (interest radius instead of the whole zone), for larger player counts. |

Main folder = home base: pulls, plays the latest, small chores, keeps this file and
`CLAUDE.md` current. One Claude Code session per folder.

## The first scenario: the smith

A farmstead near the castle was raided and the goblins took the smith. Fight through the
fields and the overrun castle, find him held in the keep, bring him home.

- **Loot:** weapons and gear in the castle's chests and on its goblins.
- **Rescue:** the smith becomes the first town resident and reworks weapons.
- **Companions:** react to the raid, the captive, and what's found.
- **World primer:** a page on the town, goblins and land so companions talk like they live
  there — to write with Dire. Tone reference: *Gísla saga* (grim, fated, loyal; named
  weapons and grudges).

## How it plays (design rules — don't violate without asking Jeff)

- **No classes, no XP treadmill.** What you carry and how you play decide what you're good at.
- **Weapons are verbs**, not damage tiers:
  - Hammer: knockback (high push force).
  - Sword & shield: block arc in facing direction absorbs damage and pushes at stamina cost; heavy hits break guard.
  - Giant axe: slow, two-handed, 3-cell arc, knocks targets down ~1.5 s (prone: can't act or resist pushes).
  - Spear: hits two cells away; braced, stops a charge.
  - Dagger: fast, low damage, +100% from behind (uses facing).
  - Bow: range; longer draw = stronger shot.
- **You become what you do** — slowly. Habits shift the body (heavier/leaner/sharper mind); it's a trade, not a climb (heavy is slow, light is easy to throw). Two hands = choices (sword or the staff that feeds mind).
- **Gear is kept; buffs are earned.** Weapons are never consumable. Food, magic items and social time (cards with a local) give temporary buffs, found in town or on the road (larders, libraries, puzzles); companions remind you when they fade. Buffs never drop you below baseline.
- **Items have history.** Each item records carriers (with time held) and up to five notable events. Later: items take the name of a long-time holder ("Wren's dagger") and slowly absorb that holder's strength (capped, slow, drifts to a new owner). Record history from the moment items become instances (step 6), even before naming is built.
- **The long game is the world**, not the character: town grows with rescued people, enemies hold and retake ground, companions remember.
- **Companion prompts say what's true and what to do, never what to say.**
- **Licensing:** no assets with non-commercial or regional restrictions; record every third-party asset/tool/model in `THIRD_PARTY.md` with a `source` per asset.

## Backlog (decided or agreed ideas, not yet scheduled)

Gathered from the whole project history. Items marked *idea* are brainstorms Jeff liked
but hasn't committed to; confirm before building them.

### Game loop, town and world
- **Town as the progression.** Everything found on a run (gold, ores, weapons) goes to the town stockpile. Rescued people join the town as shopkeepers, guards, the smith; the town has its own experience that pays for upgrades. Not every companion is a rescued prisoner — they're met in varied ways.
- **Companion growth.** Companions gain experience from a run but only keep it if they make it back to town alive (and grow when a run is won); fallen companions can be brought back in town. Players have no XP; their growth is the body shape above.
- **Winning the run** (the objective) earns the big reward; losing never takes away what's already banked. Not punitive.
- **Enemies win by holding things, not taking your loot:** captives, territory, getting stronger in an area.
- **Persistent consequences while you're offline** *(idea)*: log in to find a companion kidnapped, or the fort smouldering after you raided the enemy's mines for ores one too many times. You respawn, resurrect townspeople, rebuild walls; the captive waits in the dungeon for you to retrieve.
- **A fort with defences you build up** *(idea)*.
- **Factions** *(idea)*: AI characters who can defect between factions; factions need upkeep; endgame about diplomacy and regional resources. Don't copy the Nemesis System — Warner Bros. holds a patent on it until 2036.
- **Captives and rescue:** a fallen companion left behind is taken, to be rescued later; the goblins took the smith *and* his hammer.
- **Hauling:** physical loot you carry or drag home; carts on laid tracks for crates, Minecraft-style *(idea)*.

### Combat and bodies
- **Fighter controls** (from the combat discussion): left click = quick swing; left hold-release = charged swing; right click = grapple; right drag = toss.
- **Resources stay diegetic:** stamina (fighters), focus (archers/rogues), mind (casters); no bars. Mind is its own channel — body damage doesn't silence a caster; magic items and spells feed it.
- **Bandaging replaces passive regen:** right-click-hold on an adjacent ally, out of combat, bandage sound, then regen starts and you can step away. A reason to break off from a fight. The bandaging kit item exists; the action doesn't yet. Companions need matching verbs (bandage an ally, hand an item over).
- **Bodies come in a range:** heavy, lean, in between, for men and women alike, sharing one skeleton. Bigger = more mass (harder to shove, hits harder, slower) — Dire's point, and the physics already says so.
- **Body variation for monsters:** desynced animation phase and ±10% speed, ±12% scale with mass to match, colour variants, hood up/down, hand props (club, dagger, torch), temperament (bold, cautious, cowardly). Brutes visibly bigger than imps. Labels show just the kind ("Imp"), and only for monsters in sight.
- **Water physics:** crates float (walkable), boulders sink, creatures that fall in are slowed/stunned and can climb out; heavy ones drown.
- **Siege breathing room:** doors players can close and monsters can't open; monster respawns at the map edge/treeline, ≥12 cells from players, never inside walls; waves with lulls instead of constant respawns.

### Monster AI pass
- **Sight by light** (the heat/light fields exist): things are seen if lit or glowing; carrying a lantern makes you visible too. Sight cones use the facing that's now in the sim.
- **Hearing:** fights, doors, footsteps and speech make noise; monsters investigate.
- **Alertness states** (idle → suspicious → hunting → fighting), pursuit that gives up, doors break pursuit.
- **Speech as noise:** normal speech ~10 cells, ALL CAPS shouts carry farther, a whisper mode (`/w`) barely carries; bubbles only within hearing range.
- **Companion LOOK verb** (go check a dark or unseen spot and report back), built on the same sight machinery.

### Items
- **Item history** (parked until step 6, weapons as verbs, which makes items instances): carriers with time held, up to five notable events.
- Later: items take a long-time holder's name ("Wren's dagger"); slowly absorb the holder's strength (a caster's staff gains mind) — capped, slow, drifts to a new owner; gifts between companions, townsfolk and players.
- *Ideas from Gísla saga:* cursed heirlooms (strong, but bring ill luck to whoever won't let go); reforging a broken heirloom into something new that keeps its name; a split token (two halves of a coin) carried by two friends.
- **Upkeep buffs:** food (mass), magic items (aura), social time like cards with a local (wits); found on the road too (larders, libraries, puzzles); companions mention when they fade, once.

### Companions
- **Card system:** random trait tables (birthplace, religion, parentage, profession, hobby, food preference, and so on) rolled at creation; one model call writes the card; a "how we met" field. *Idea from the saga:* good and bad omens/dreams.
- **World primer** to write with Dire (tone: *Gísla saga*).
- **Claude voice option** *(experiment)*: let a companion's voice run on the Claude API (Haiku/Sonnet) with fallback to the box's 14B; compare transcripts and cost. The `--voice-url` setting for a bigger local model already exists.
- **Promises match actions:** doors are real (in `companions`); "I'll check the chest" can stay roleplay.

### Maps, editor and outdoors
- **Editor:** F5 play from the editor; properties panel (chest contents, link destinations, start names) instead of hand-editing level.json; select/copy/paste; height painting; 3D preview.
- **Outdoors:** trees that block sight and slow you, tall grass that hides you, rocks and cliffs using height, streams with fords/bridges. Outdoor maps generated from a written composition (text → plan → height and terrain maps → rules pass → editor touch-up).
- **Castle map fixes:** fire that looks like fire (flicker, flames, warm light), not flat yellow squares.

### Engine, network and tooling
- **Keep the map bench** as a release check at 128² and 256², with budgets for tick time, load time and frame rate.
- **Staging server:** run a new build on a second port and check it before swapping it in.
- **Licensing records:** `THIRD_PARTY.md`, a `source` per asset with a test that fails without one, and dated license copies (e.g. DINOv3, 2025-08-19).
- **Goblin model touch-ups** when it matters in game: rest pose (stands upright like the mannequin), feet pointing forward.

### Later
- **Music and ambience:** ambient beds first (wind, fire, birds); layered calm/tension/combat music per zone with stingers via Godot's interactive audio; ACE-Step (Apache 2.0, local) as the likely generator. Not needed yet.
- **Lighting pass:** dark ambient, light from torches and fires doing the work; nerve tied to light.

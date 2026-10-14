# Psykinetic roadmap

Last updated: 2026-10-14. Owner: Jeff. Every session reads this before starting work.
The player-facing version (for Dire) lives in a separate doc; this one is for building.

## Goal right now

The foundations work (co-op server, zones, physics combat, talking companions, level
editor, art pipeline). What's missing is a reason to play: something to find, something
you become, someone to save. Everything below serves the first scenario: rescue the smith.

## Order of work

Each step is what the next one needs. Weapons only feel good if you can read them;
a story only matters if there's something to fight with.

| # | Step | Done when | Worktree |
|---|------|-----------|----------|
| 1 | **Performance** | 128² map: load < 2 s, server tick < 20 ms at castle density, 60 fps on the laptop; per-frame scripts < 4 ms at 128², < 8 ms at 256². Far-away monsters think less often (full rate within ~30 cells of a player/companion, reduced at 30–60, idle paused beyond; fights always full rate). | `perf` |
| 2 | **Network smoothness** | No rubber-banding in a castle fight. Knockback sent as one event (direction, distance, start tick) every client plays identically; others drawn ~100–150 ms in the past and interpolated; corrections blended, not snapped; camera follows a smoothed position. Report corrections/min and worst snap before/after. | after `perf` (same client code) |
| 3 | **Combat animation states** | Synced from sim state: wind-up (longer for heavy attacks), strike, recover, hit (direction-aware), pushed (matches knockback event), knocked down (fall/lie/get up, timed to sim), block, guard break, death. Clean blends, no popping. | after `pc-character` |
| 4 | **Player character** | One shared humanoid body for players and companions, human proportions so the animation library fits, hand attach points for weapons. Replaces the capsule. | `pc-character` |
| 5 | **Weapon models** | Hammer, sword, shield, giant axe, spear, dagger, bow — flat, faceted style, attach to hand bones. | art session (Blender MCP) |
| 6 | **Weapons as verbs** | See "How it plays". Each weapon changes what the attack does in the physics; one of each in the castle chests; tests per verb. | later |
| 7 | **The smith scenario** | A map and story to use it all in (see below). | later |

## Running in parallel (not on the critical path)

| Worktree | Job |
|----------|-----|
| `companions` | Repetition filter compares normalized text (curly/straight quotes, case, punctuation); stay silent more readily after minor events; a real OPEN/CLOSE DOOR action the voice can choose; record last words in transcripts. |
| `live-updates` | Protocol version separate from build version (only a protocol mismatch blocks joining); graceful update (60 s chat warning, save, restart, clients auto-reconnect); client self-update on reconnect; live reload for data files; then auto-deploy in the ship flow; a staging port where a new build is checked before swapping in. |

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
- **Items have history.** Each item records carriers (with time held) and up to five notable events. Later: items take the name of a long-time holder ("Wren's dagger") and slowly absorb that holder's strength (capped, slow, drifts to a new owner). Record history from the start even before naming is built.
- **The long game is the world**, not the character: town grows with rescued people, enemies hold and retake ground, companions remember.
- **Companion prompts say what's true and what to do, never what to say.**
- **Licensing:** no assets with non-commercial or regional restrictions; record every third-party asset/tool/model in `THIRD_PARTY.md` with a `source` per asset.

## Later (parked)

Monster AI pass (sight by light, hearing, alertness, leash, doors break pursuit, speech
volume as noise), sieges with waves and lulls, captives (a fallen companion taken and
rescued), builder mode (select an area in game and describe it; new areas at map edges),
forest/meadow/mountain outdoor zones, music and ambience, companion LOOK verb.

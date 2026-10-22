# Psykinetic: Combat Input & Weapon Kits (v0 design)

Starting brief for the combat worktree. Written Oct 22, 2026.

Items marked **[decided]** are Jeff's calls. Items marked **[proposed]** are first-pass suggestions to build and playtest, not locked. When in doubt, build the decided parts and keep proposed numbers in data so they're easy to tune.

## Constraint: existing archery is off-limits

**[decided]** Archery already works in game. Do not overwrite, rewrite, refactor, or replace any existing archery code, data, assets, or behavior in this pass. Anything new for the bow (stand-and-shoot, backstep, heavy shot) is added alongside the existing system, extending it without changing how current shots behave. If a new feature seems to require changing existing archery, stop and flag it for Jeff instead of making the change.

## Why this pass exists

Dire's critique: most games reduce input to "click on a thing, a thing happens" (click-to-adventure). The goal is for the *same* click to produce different outcomes depending on angle, timing, momentum, what you're holding, and what's around you. Psykinetic already runs on force, mass, pushback and collision damage, so combat depth should come from that physics, not from more buttons or scripted outcomes.

## Principles

- **[decided]** No gesture casting. Combat is fast-paced; gesture recognition doesn't fit.
- **[decided]** Stick to real physics interactions. Moves are physics events (bodies with mass and velocity), not animations with damage numbers attached.
- **[decided]** The mouse is for combat. Non-combat actions live on the keyboard.
- **[proposed]** Let the sim decide outcomes. Avoid special-case scripting (e.g., don't script "charge stops at ogre"; let mass do it).
- **[proposed]** Enemies should be able to use the same moves as players, so players learn to read and counter them.
- Server-authoritative as usual: the client sends an intent (action + target point + modifier), the server validates and executes in the sim.

## Input map

| Input | Action | Status |
|---|---|---|
| Left click | Move (click an enemy: walk up and attack) | **[decided]** move; attack-on-enemy-click **[proposed]**, see open questions |
| Stand-and-swing key + left click | Attack in place toward the cursor, no movement | **[decided]** concept; **[proposed]** Shift as the key |
| Ctrl + left click | Weapon's signature move | **[decided]** |
| Right click | Defend: block or parry depending on what's held | **[decided]** |
| B | Puts a bandage on the cursor; click yourself or an ally/companion to apply | **[decided]** replaces the old right-click-hold bandage |

Notes:
- **[decided]** With an item on the cursor (bandage), clicks apply the item; no attack happens.
- **[proposed]** Cancel cursor-item mode with B again or Esc. The out-of-combat-only bandaging rule stays.
- **[proposed]** The cursor-item mode is generic, so later consumables (food buffs, throwables, handing gear to a companion) reuse it.
- **[proposed]** Avoid Alt as a modifier (Windows OS shortcuts).

## Stand-and-swing

- Swings hit whatever is in the arc, with no locked target. You can swing into empty space (meeting an enemy coming through a door) and hold a choke point without stepping forward.
- **[decided]** Rapid repeated swings (spinning to clear a knockback space around you) are a panic move and must deplete stamina.

## Stamina and exhaustion

- **[decided]** Swings cost stamina; larger weapons drain faster.
- **[proposed]** Drain scales with weapon weight *relative to the wielder's* strength/mass, so a heavy build carries a giant axe more cheaply than a light build does.
- **[proposed]** Swing recovery time scales with weapon weight; heavy weapons also turn slower, so flanking matters.
- **[proposed]** Whiffs cost slightly more than hits.
- **[proposed]** Exhausted state at zero: slower movement, weaker swings, no signature moves, a short delay before regen. Make it visible (stance/breathing) so allies and companions can react; companions may call it out ("you're winded").
- Resources per kit (existing design): fighters use stamina, casters use mind, archers use focus.

## Physics modifiers (apply to every action)

All outcomes are scaled by:
1. **Weapon weight:** bigger push per hit, bigger drain.
2. **Body build:** mass, reach, wind-up. Heavy bodies push harder and resist being pushed; light bodies get knocked around but move and draw faster.
3. **Resource state:** stamina / mind / focus available.

**[proposed]** Also worth folding in where cheap:
- **Angle of contact:** push direction comes from the attacker-to-target vector at impact, so positioning (knocking an enemy into a wall or another enemy) is a skill.
- **Momentum:** moving into an attack adds force.
- **Feel:** short hit-stop on heavy impacts, a slight screen nudge, distinct sounds per weapon/material.

## Weapon kits (first three)

**[decided]** First kits: sword and shield, magical staff, bow and arrow. These are archetypes, not locked classes (progression is "what you do shapes your body"). The bow already exists in game; extend it rather than rebuild it.

All per-kit moves below are **[proposed]** unless noted.

### Sword and shield (stamina)
- **Click:** slash, moderate push.
- **Stand-and-swing:** short arc in place.
- **Ctrl + click:** shield bash. Short lunge that shoves and staggers; light enemies go down, heavy ones barely move (mass decides).
- **Right click:** hold to raise the shield toward the cursor (directional). Each absorbed hit costs stamina; heavy hits still push the blocker back by mass difference. Hits from behind or the side aren't blocked.
  - A tap timed at the moment of impact = parry: staggers the attacker and opens a riposte. Mistimed = no block.

### Magical staff (mind)
- **Click:** kinetic bolt. Short-range force projectile, more push than damage.
- **Stand-and-swing:** cast in place toward the cursor.
- **Ctrl + click:** telekinetic grab and throw. Pick up the object or enemy under the cursor and fling it. Mind cost scales with the target's mass; very heavy targets may be impossible. Intended as the caster's identity move.
- **Right click:** ward, held. Deflects projectiles and pushes melee attackers back; drains mind while held.

### Bow and arrow (focus)
> Existing archery stays as is (see the constraint at the top). Everything below is additive.

- **Click:** shot; draw strength/wind-up depends on build (existing rule: light builds wind up more, heavy builds can't keep distance as well).
- **Stand-and-swing:** shoot in place. Especially important for archers, who shouldn't walk toward targets.
- **Ctrl + click:** heavy shot with real knockback; pins light enemies to a wall if one is directly behind them.
- **Right click:** backstep / quick dodge to open distance; costs focus.

### Intended cross-kit interactions (playtest for these)
- Shield blocks arrows; ward deflects them.
- Shield bash can knock an enemy into position for the staff's throw; the archer can pin a thrown enemy.
- Two-hands rule (existing): you can't hold the sword and the staff at once.

## Later kits (not this pass)
Already sketched, for reference only: spear (Ctrl = charge to the clicked spot, knocking back everything in the path, **[decided]** as the example move; right click = brace, so charging enemies take damage from their own momentum), hammer (ground slam, radial push), giant axe (knockdown sweep, little or no block).

## Suggested build order

1. Input plumbing: stand-and-swing key, Ctrl modifier, right-click defend intent, B cursor-item mode (move bandaging off right click). Weapon behavior defined in data per kit.
2. Stamina costs per swing (relative weight), exhausted state.
3. Sword and shield: directional block, then parry timing, then shield bash.
4. Bow: stand-and-shoot, backstep, heavy shot with pin, all added on top of the existing archery without modifying it. Existing archery behavior must be unchanged after this step.
5. Staff: kinetic bolt, ward, then grab-and-throw (the largest piece; depends on picking up and launching arbitrary bodies in the sim).
6. Feel pass: hit-stop, sounds, exhaustion visuals.

Add headless tests where the sim allows, e.g.: a bash knocks a light enemy farther than a heavy one; stamina reaches zero after N rapid swings and blocks signature moves; a block from the front absorbs and from behind doesn't; a throw's mind cost rises with mass.

## Open questions

- Should a plain click on an enemy still auto-walk and attack, or should plain click only move (all attacks via stand-and-swing)? Leaning: keep auto-attack for now, watch whether players drift to stand-and-swing.
- Held vs. tapped defense: proposed held for shield and ward, tapped for parry. Confirm in play.
- Friendly fire in co-op: can your bash or throw shove allies? Proposed: allies get pushed but not damaged.
- Does the current bow have hold-to-draw, or click-and-fire? Determines how heavy shot is built.
- Signature-move wind-up length: long enough to read and react to, short enough to keep the pace fast.

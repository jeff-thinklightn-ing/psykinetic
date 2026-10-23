# Archery refinement (decision 583, 2026-10-22)

Jeff's plan for the day was "combat feel and archery refinement". The coordinator approved this
design as written. Jeff's words are quoted; the rest is the design.

## What Jeff asked for

- The arrow on the string while drawing ("the arrow doesn't load into the bow with drawing").
- While drawing, the mouse disappears and an arc shows the range.
- Range grows the longer the draw is held, in increments ("the range has increments").
- A shorter shot does more damage, with no partial draw ("no throttle there").
- Aim at any angle, not by tile ("use a circle which the aim can move along at many degrees").
- The arrow flies "directly from tip to mouse point and hits whatever is in between".
- "after the full range it sags down and lands in ground, not hitting ground at its target like it
  does now".
- Arrows aren't used up or picked up; they "decay over 10 seconds like they do now".

## The buttons (Jeff: "lets do this with archery, just like shift+LMB to draw back, mouse to move only")

- The draw is Shift (the stand key, decision 593) with the left button held, the hold stepping the
  range out. Letting go of the button fires; letting go before draw_min lowers the bow unshot.
  Letting go of Shift mid-draw does nothing: the draw lasts until the button comes up (combat).
- The left button alone with a bow is a plain click, never a draw: walk (and hold to steer), talk
  to a friend, go to a chest. Whether it attacks a foe is ui's to settle with the coordinator.
  Neither a click nor a short Shift press is a quick shot: the first step hits hardest (×1.5).
- With a bow, Shift+LMB draws and never swings; Ctrl's signature is unchanged.
- The right button stays free for the bow's backstep, combat's, later.
- Before this (583 amended, v0.1.166) the left button alone drew after a quarter second held.

## Defaults until Jeff says otherwise (the coordinator's)

- The semicircle is centred on the aim, and the archer turns continuously with the mouse.
- Four range steps over about 2 s.
- Walking while drawn is allowed, at half pace; drawing doesn't root you.

## The sim (items; enemy-ai for monster archers): a protocol change

- **Range:** the ranged verb gains "steps", 4 ranges in cells (e.g. 3, 5, 7, 9), each reached after
  so many ticks of draw (the first at draw_min). `World.range_of(entity)` gives the current step's
  range in cells, 0 before draw_min; it replaces `draw_of` as what the views read.
- **Damage:** by the step shot at, shortest hardest: the verb's "damage_at", a multiplier per step
  (e.g. ×1.5, ×1.2, ×1.0, ×0.8). It's the chosen step that counts, wherever the arrow stops.
- **Aim:** `try_loose(by, angle: float)`, in radians as `Vector2.angle()` on the grid (the map's x
  axis is 0, the grid's y the second component).
- **The line:** a ray from the shooter's centre at that angle, walked cell by cell as a supercover,
  up to the step's range. It hits the first body or blocker on it (a wall, a closed door, higher
  ground). Friends are spared as before (456).
- **What the views get:** `GridEntity.shot(to: Vector2, struck: StringName)`, the point where the
  arrow stops in cell units and what stopped it: body, wood, stone, or ground (range spent).
- **Monster archers:** they hold the draw until the step covers the distance to their target (or
  the longest step), then loose at the angle to it.
- **Arrows:** not used up; the bundle is untouched.

## The aim (ui)

- While drawing (Shift and the left button held), the cursor is hidden.
- A semicircle on the ground at the current step's radius, jumping outward at each step.
- An aim marker on the arc where the line from the player to the mouse crosses it.
- A read of the step's damage beside the marker.
- `Main.aim_angle` (radians on the ground plane) and `Main.aim_drawn`, set every frame while drawn.
- On releasing the left button, the angle is sent; releasing before draw_min cancels.
  The aim is shown only while drawing, so only after Shift+LMB.

## The client's 3D (pc-character)

- The nocked arrow shows on the string from the first frame of the draw. It had been hidden with
  the bow's old string box since 462 amended (3).
- While drawn, the archer turns to `Main.aim_angle` continuously, so the bow points at the marker.
- **The flight** (`Client3D._on_shot`): art-kit's fx.arrow leaves the bow and flies level at the
  bow's height to where it stops. Then:
  - into a body, it's gone with the hit; a spared friend keeps it a while (456);
  - into wood (a closed door), it sticks at its angle, head in;
  - off stone, it glances back and down and lies at the wall's foot;
  - its range spent, it carries on about 1.8 m in a short fall and stands in the ground nose down;
    into water, it's gone.
- It never passes through anything or lands at the aimed cell. Arrows left about go after 10 s
  (`SHOT_STUCK_SECONDS`).
- The client reads the sim's point and what stopped it; its arrival sound follows that
  (`_shot_sound`).

## As built (items' side, cdcb2c30)

- The ranged verb's steps are [3, 5, 7, 9], and its damage_at is [1.5, 1.2, 1.0, 0.8]. draw_min is 5
  ticks, with a new step every 5 ticks (draw_step 5).
- `World.range_of(entity)`, `World.longest_range(entity)` and `World.draw_step(entity)` (-1
  before draw_min). draw_of stays 0..1 toward the longest step's draw (draw_full 20), so the bow's
  pull and creak are unchanged.
- `World.try_loose(by, angle)`: radians as `Vector2.angle()`, 0 east, +y south.
  `World.loosed(by, angle, step)`.
- `World.shot_aim(by, angle, cells)` and `World.shot_ray(from, angle, cells)`.
- `GridEntity.shot(to: Vector2, struck: StringName)`. The point is in cell units (a cell's centre
  is `Vector2(cell)`): at a wall, where the ray crosses its face; for a body, abreast of its cell's
  centre; spent, the range's end. struck is body, wood (a closed door), stone (a wall, higher
  ground, the map's end) or ground.
- Walking drawn: the step's ticks × `World.DRAWN_TICK_SCALE` (2.0), and the draw is kept.
- Wire: PROTOCOL_REVISION 31.

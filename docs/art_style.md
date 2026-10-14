# Psykinetic art style

How the game's own art is made, so pieces made months apart sit together. Every model the game
draws is a **slot** in `art/kit/slots.json`; this page is the rules a slot's art follows, and
the manifest says each slot's size, origin, parts and budget. The goblin
(`art/models/characters/goblin.blend`) is the reference for the look.

## The look

- **Low-poly and faceted.** Shapes read from the game camera (orthographic, looking down at
  about 50°, a room on screen), not up close. Big planes, chamfers where light should catch,
  no detail smaller than about 5 cm. Silhouette first.
- **Flat or hand-painted colour, no photo textures.** Either flat colour per face (a
  material per colour, baked to one later), or one hand-painted image over a UV map as the
  goblin has (`art/models/paint/goblin_paint.png`, 2048²). No normal maps, no photo scans.
- **Rough, not shiny.** Roughness 0.8 to 0.95 for stone, wood, cloth and earth; 0.5 to 0.65
  for leather and skin; under 0.3 only for eyes, wet things and polished metal. Metallic 0
  except bare metal (gate bars, nails, blades) at 1.
- **Light does the drama.** Interiors are dark and lit by torches and lanterns; outdoors a
  day sun. Don't paint light or shadow into colours beyond a little darkening in crevices
  (ambient occlusion, subtle). Keep albedo mid-valued (nothing near pure black or white), so
  a torch and the sun both read.
- **Muted and earthy, with a few saturated accents** (fire, magic, a banner). Grime and wear
  at edges and bases, not all over.

## Palette

Starting points, not a cage. The goblin's paint and the game's ground colours set them.

| Use | Colours |
|-----|---------|
| Stone (walls, posts, cliffs) | `#ebb48e` warm sandstone (today's walls), `#8f8f8a` grey stone, `#6b6660` dark stone |
| Wood | `#796145` light, `#5e4c41` mid, `#3b2e24` dark (beams, old planks) |
| Earth and ground | grass `#36a340`, dirt `#755c38`, sand `#c7b380`, forest floor `#2c4224` |
| Foliage | `#5d7742` (the goblin's green), `#4f6a35`, `#7a8f4a` lit tips |
| Cloth | `#4c4a3b` olive, `#29231b` near-black, plus one accent per faction |
| Metal | `#55575c` iron, `#8a6a3a` bronze |
| Light | torch `#ffb861`, water `#336bd9` |

## Scale and axes

- **1 cell = 1 m.** A wall is 3 m tall (Client3D.WALL_HEIGHT), a height level 0.5 m
  (LEVEL_RISE). The goblin stands 1.2 m. A player is about 1.8 m.
- Model in metres with Blender's default units; export glTF with **+Y up** (Blender's
  exporter does this by default).
- **Edge pieces** (walls, doors, rubble) run along **z** from -0.5 to 0.5, centred on the
  edge's line at **x = 0**, base at y = 0. A 0.5 m thick wall spans x -0.25 to 0.25.
- **Vertex pieces** (posts) and **cell pieces** (props, plants, rocks, trees) stand centred
  on their origin, base at y = 0, front facing **+Z**.
- **Held pieces** (items, weapons) have their origin at the `grip` socket, where the hand
  holds them, with their length along +Y. A two-handed one has a second socket `grip_2` (an
  empty named `grip_2`) for the other hand, so it fits the character's hand attach points.
- A **moving part** is its own object, named as the manifest names it (`leaf` for a door),
  with its origin at the pivot: a hinge's on the hinge line, a slide's at its closed position.
- **States** (locked, barred, broken) are optional objects named `state_<name>`, shown only in
  that state.

## Budgets

Triangles per piece, as the manifest's `budget`. These are ceilings, not targets: a piece
drawn a thousand times (a wall, a tuft) should be well under.

| Kind | Triangles | Notes |
|------|-----------|-------|
| Wall module (1 m) | 300 | tiles along z; ends match wall.profile |
| Post | 200 | |
| Door, frame and leaf | 700 | the leaf about a third |
| Tree | 800 | |
| Rock (small), plant, tuft | 200 | scatter: one mesh, one material, no hierarchy |
| Prop (crate, barrel, chest) | 500 | |
| Building | 3000 | |
| Character (reference) | the goblin is 3,780 | pc-character owns characters |

Materials: one per piece wherever possible (scatter must have one); at most three. Textures:
512² for a prop, 1024² for a building, 2048² only for characters. Tileable textures (ground,
rock, wall stone) say their world size in the manifest's `tile_m`.

## Making a slot's art

1. Look up the slot in `art/kit/slots.json`: its size, kind, parts and budget.
2. Model it in Blender, to the conventions above.
3. Record where it came from: a scene custom property `source` (for example
   `"jeff, blender"`). The manifest's `source` field for the slot says the same, with the
   licence and date.
4. Save `<slot>.blend` and export `<slot>.glb` into `art/kit/<category>/<slot>/`. Variants
   are `<slot>.2.glb`, `<slot>.3.glb`. A texture slot takes `<slot>.png` instead.

The game then draws it in place of the slot's fill or grey box. The `.blend` is committed
beside its `.glb` as the source. Godot ignores `.blend` files here (Blender import is off),
so only the `.glb` is ever read, and the server's headless import needs no Blender.

## Licensing

No assets with non-commercial or regional restrictions. Each slot's art records its source
in the manifest. A slot drawn from a third-party fill names the fill's source, and that
source's licence is listed under the manifest's `sources`. Today's fills are the Kenney
Castle Kit (CC0).

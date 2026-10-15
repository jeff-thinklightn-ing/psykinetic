# Psykinetic art style

How the game's own art is made, so pieces made months apart sit together. Every model the game
draws is a **slot** in `art/kit/slots.json`; this page is the rules a slot's art follows, and
the manifest says each slot's size, origin, parts and budget. The goblin
(`art/models/characters/goblin.blend`) is the reference for the look. Jeff's answers that set
these rules are in `docs/art_slots_review.md`.

## The look

- **Flat-shaded, faceted low-poly**, like the goblin. Shapes read from the game camera
  (orthographic, looking down at about 50°, a room on screen), not up close. Big planes,
  chamfers where light should catch, no detail smaller than about 5 cm. Silhouette first.
  Flat shading: faces stay faceted, no smoothing across them.
- **Flat colours from one shared palette, no painted textures** (for now). Every face takes
  one swatch of the palette atlas (below). No gradients, normal maps or photo textures.
- **Muted and earthy**: stone, wood, moss, leather. **A few saturated accents** for
  torchlight, banners and magic, and nothing else.
- **Light does the drama.** Interiors are dark and lit by torches and lanterns; outdoors a
  day sun. Don't paint light or shadow into colours: pick a darker swatch for crevices and
  undersides instead. Nothing near pure black or white, so a torch and the sun both read.
- **Rough, not shiny.** The palette material's roughness is 0.9 for everything. Wear shows
  as a darker swatch at edges and bases, not all over.

## Palette

`art/kit/palette.png` is the atlas: 8 rows of 8 swatches, 16 px each (128 × 128), lighter to
the left. Every piece uses the one material `palette` (`art/kit/palette.tres`), which shows
it sampled nearest, so a face keeps exactly its swatch's colour. Colour a face by putting its
UVs inside one swatch (the template does this for the grey box). Jeff may repaint swatches;
keep the rows.

| Row | Use | Swatches, light to dark |
|-----|-----|-------------------------|
| 0 | stone, warm (today's walls) | `#f2c9a6` `#ebb48e` `#d49c78` `#b8845f` `#9a6c4c` `#7c573d` `#5f4330` `#433024` |
| 1 | stone, grey | `#c9c7c0` `#b0aea6` `#97958d` `#8f8f8a` `#77766f` `#6b6660` `#545049` `#3b3834` |
| 2 | wood | `#b8946a` `#9e7c55` `#8a6a48` `#796145` `#6a523a` `#5e4c41` `#4a3a2c` `#3b2e24` |
| 3 | earth (sand to dark soil) | `#d8c89a` `#c7b380` `#a88e5e` `#8c7148` `#755c38` `#5f4a2e` `#4a3a25` `#2c2418` |
| 4 | foliage, moss | `#a8bf6a` `#8fa857` `#7a8f4a` `#5d7742` `#4f6a35` `#36a340` `#2f5a2a` `#2c4224` |
| 5 | cloth, leather | `#c2b8a0` `#9c8f74` `#7a6e58` `#4c4a3b` `#6b4a35` `#55392a` `#3d2a1f` `#29231b` |
| 6 | metal (iron, then bronze) | `#c7c9cc` `#a3a6ab` `#7d8086` `#55575c` `#3e4044` `#c79a55` `#a37d40` `#8a6a3a` |
| 7 | accents | flame `#ffd27a`, torchlight `#ffb861`, ember `#e8792e`, banner red `#b8322a`, banner blue `#2f5aa8`, magic violet `#7a4fb0`, magic teal `#3fb8a8`, bone `#f4efe6` |

## Materials

**One material for everything: `palette`** (decision 261). The game swaps any material named
`palette` in a `.glb` for the shared one, so every piece draws with the same material. A
slot may allow a second (`"materials": 2` in the manifest) only for a special part: something
that glows (a flame, a forge's mouth, magic) or glass. Ground, rock and wall-stone textures
are texture slots, not materials on a model (see Budgets).

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
- **Buildings** are a roof, an interior floor and trim, **never walls**. The walls are the map's
  wall edges, drawn by terrain's wall runs and faded edge by edge. The slot's `footprint` is in
  cells, its origin is the footprint's middle, and its size includes the roof's 0.3 m overhang.
  The named objects `roof` (origin at the eaves, 3 m up, the wall height), `floor` (origin on
  the ground) and `trim` (eaves, ridge, chimney, porch) are separate, so the game can hide the
  roof while you're inside.
- A **moving part** is its own object, named as the manifest names it (`leaf` for a door),
  with its origin at the pivot: a hinge's on the hinge line, a slide's at its closed position.
- **States** are optional objects named `state_<name>`, shown only in that state, as the slot's
  `states` lists them. A door's are `state_locked` (a lock plate), `state_barred` (a bar across)
  and `state_broken` (splintered boards on the leaf: a broken door stays open). Open and closed
  are the leaf's swing, not states.

## Budgets

Triangles per piece, as the manifest's `budget`. These are ceilings, not targets: a piece
drawn a thousand times (a wall, a tuft) should be well under.

| Kind | Triangles | Notes |
|------|-----------|-------|
| Wall module (1 m) | 300 | tiles along z; ends match wall.profile |
| Post | 200 | |
| Door, frame and leaf | 600 | the leaf about a third |
| Tree | 1500 | |
| Rock (small), plant | 200 | |
| Scatter (tuft, flower, stone, root) | 50 to 150 | one mesh, one material, no hierarchy: drawn by MultiMesh |
| Prop (crate, barrel, chest ...) | 300 to 800 | by size: a sack 300, a cart 800 |
| Building | 3000 | |
| Character (reference) | the goblin is 3,780 | pc-character owns characters |

Materials: the one `palette` (above). Tileable textures (ground, rock, wall stone) are texture
slots: 512 px square, tiling every 4 m (the manifest's `tile_m` gives the world size).

## Making a slot's art

1. Look up the slot in `art/kit/slots.json`: its size, kind, parts and budget.
2. Start from its template: `tools\art_template.ps1 prop.chest` writes
   `art/kit/props/prop.chest/prop.chest.blend` with the slot's grey box as the game makes it.
   It has the right size and origin, the moving parts as objects with their origins at the
   pivots (the chest's `lid`), the sockets, every face in the `palette` material on a grey
   swatch, and a wireframe `guide` collection with the slot's outline, which exporting leaves
   out. Model over the boxes or replace them, to the conventions above, keeping the parts'
   names and origins. Colour faces by moving their UVs onto a swatch.
3. Record where it came from: a scene custom property `source` (for example
   `"jeff, blender"`). The manifest's `source` field for the slot says the same, with the
   licence and date: `{"by": "jeff", "tool": "blender", "license": "own", "date":
   "2026-10-20"}`. Art that started as a generated candidate also cites its note:
   `"notes": "D:/assets/candidates/door.single/notes.md"` (the models and licences used are
   listed in `THIRD_PARTY.md`).
4. Save it as `<slot>.blend` (variants `<slot>.2.blend` ...) and drop it in:
   `tools\art_drop.ps1 <path to door.single.blend>`. It copies the file into
   `art/kit/<category>/<slot>/`, exports `<slot>.glb` through Blender, imports it and checks
   it against the slot, naming anything to change ("100.0 times the slot's size every way:
   modelled in centimetres?", "no object named "leaf"", "4,200 triangles, the slot's budget
   is 2,000"). Fix it in Blender and run the same line again. A `.glb` made elsewhere, or a
   texture slot's `<slot>.png`, drops in the same way.
5. To see it as the game will while you work: `godot --path . tools/art_preview.tscn --
   --slot=door.single`. It shows the slot from the game's camera, on a 1 m grid inside the
   slot's outline, with the goblin beside it for scale. Its moving parts swing, its states
   take turns, and what the check says is on screen. Every save of the `.blend` is exported
   and shown again (Left/Right for other slots, Q/E to turn, G for the grey box, L for
   torchlight).
6. `tools/art_check.gd` checks every slot's art at once
   (`godot --headless --path . --script tools/art_check.gd`), and the tests hold all of it
   to its slot.

The game then draws it in place of the slot's fill or grey box. The `.blend` is committed
beside its `.glb` as the source. Godot ignores `.blend` files here (Blender import is off),
so only the `.glb` is ever read, and the server's headless import needs no Blender.

## Licensing

No assets with non-commercial or regional restrictions. Each slot's art records its source
in the manifest. A slot drawn from a third-party fill names the fill's source, and that
source's licence is listed under the manifest's `sources`. Today's fills are the Kenney
Castle Kit (CC0).

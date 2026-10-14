# Art kit: what Jeff decides

Fill this in and tell the coordinator; it goes to the art-kit worktree, which builds the
slot manifest (`art/kit/slots.json`), grey boxes and the drop-in tools from it.

How to answer: tick `[x]` to keep a slot, leave `[ ]` to cut it, add a line under any slot
or section with changes ("make it 2 m", "later", "need a variant for ..."). Add slots at the
end of any list. Sizes are metres (1 cell = 1 m); x = across, y = up, z = along the edge.

## 1. Questions

1. **Palette and shading.** Describe the look, or name references (games, artists, the goblin).
   Flat colours, gradients, painted textures, or a small shared texture atlas?
   > Flat-shaded, faceted low-poly like the goblin. Muted, earthy palette (stone, wood, moss, leather) with a few saturated accents for torchlight, banners and magic. Flat colours from one shared palette atlas; no painted textures for now.
2. **Polygon budgets.** Art-kit's starting point: wall module 300 tris, door 600, prop 300–800,
   tree 1,500, building 3,000, scatter piece 50–150. Raise, lower, or fine?
   > Fine as proposed.
3. **Materials per piece.** One shared atlas material for everything (cheapest to draw), or
   up to 2–3 materials per piece?
   > One shared atlas material for everything. A second material only for special cases (glowing parts, glass).
4. **Your Blender.** Where is it installed (path), and which version? Needed for dropping
   `.blend` files into a slot (the tool exports them to `.glb`). Both files get committed;
   the game reads only the `.glb`.
   > Blender 5.2.2 LTS. Path: "C:\Program Files (x86)\Steam\steamapps\common\Blender\blender.exe"
5. **What you'll make first.** The first 3–5 slots you plan to replace, so their grey boxes
   and templates come first.
   > wall.straight, door.single, prop.crate, prop.chest, tree.pine
6. **Kenney.** Keep Kenney pieces as stand-ins until each slot is replaced (nothing looks
   worse meanwhile), or switch everything to grey boxes now so it's obvious what's left?
   > Keep Kenney as stand-ins where a piece exists, grey boxes for everything else, and use the "placeholders remaining" list to see what's left.
7. **Template in Blender.** Want a script that opens a slot's grey box in Blender at the right
   size, origin and named moving parts, to model over? (yes / later / no)
   > Yes.

## 2. Walls

Edge pieces, 0.5 m thick, centred on the cell edge. Each comes in three heights as
variants: low 1 m, full 3 m, tall 4.5 m. Terrain sweeps `wall.profile` along straight runs;
the modules cover ends, corners, openings and ruins.

- [x] `wall.profile`: the cross-section terrain sweeps along runs (0.5 wide, with a marked cap band)
- [x] `wall.straight`: 1 m section
- [x] `wall.end`: a run's free end
- [x] `wall.corner`: L joint
- [x] `wall.t`: T joint
- [x] `wall.cross`: + joint
- [x] `wall.post`: a free-standing pillar at a cell corner
- [x] `wall.window`: 1 m section with an opening (still blocks movement)
- [x] `wall.straight_ruined`: broken top
- [x] `wall.end_ruined`: broken end
- [x] `wall.rubble`: a low rubble "gap", fills a full 1 m edge, at least 0.6 m tall, reads as blocked
- Heights: keep 1 / 3 / 4.5 m? > Yes.

## 3. Doors

Frame plus moving parts. Open/closed come from the hinge or slide; locked, barred and
broken are extra nodes shown per state.

- [x] `door.single`: 1 m edge, one leaf hinged at one side
- [x] `door.double`: 2 m, two leaves
- [x] `door.gate`: 2 m, two heavy leaves (castle gate)
- [x] `door.portcullis`: grate that slides up
- [x] `door.trapdoor`: floor piece, 1×1 m, hinged on one edge
- States wanted: [x] locked  [x] barred  [x] broken  (others?) > Plus open and closed.

## 4. Buildings

Multi-cell footprints. Interiors or not?

- [x] `building.hut`: 3×3 cells
- [x] `building.house`: 4×6 cells
- [x] `building.shed`: 2×3 cells
- [x] `building.well`: 1×1 cell
- Roof pieces later? Walk-in interiors? > Walk-in interiors yes; the roof (and the wall between camera and player) hides when you're inside. Roof pieces later.

## 5. Trees and plants

Three variants each by default; scattered pieces are one mesh and one material each.

- [x] `tree.broadleaf`: ~6 m
- [x] `tree.pine`
- [x] `tree.small`
- [x] `tree.dead`
- [x] `tree.stump`
- [x] `tree.log`
- [x] `plant.bush`
- [x] `plant.fern`
- [x] `plant.tuft`: grass tuft (scatter)
- [x] `plant.flowers` (scatter)
- [x] `plant.reeds`: by water (scatter)
- [x] `plant.roots` (scatter)
- Variants per tree/plant (default 3): > 3 is fine.

## 6. Rocks

- [x] `rock.small`: scatter
- [x] `rock.large`: ~2 m
- [x] `rock.boulder`: the pushable boulder entity, 1 m
- [x] `rock.material`: tileable rock texture terrain uses for cliff faces

## 7. Props

- [x] `prop.crate`: pushable
- [x] `prop.barrel`
- [x] `prop.cart`
- [x] `prop.chest`: lid hinges open
- [x] `prop.torch`: wall sconce, with a flame point
- [x] `prop.lantern`: carried and hung
- [x] `prop.campfire`
- [x] `prop.fence`: 1 m edge piece
- [x] `prop.fence_post`
- [x] `prop.stairs`: 1 cell, 0.5 m rise
- [x] `prop.table`
- [x] `prop.bench`
- [x] `prop.bed`
- [x] `prop.sack`
- More props? > Add for the town and story: prop.grave, prop.anvil, prop.forge, prop.bookshelf, prop.market_stall, prop.signpost. For territory and goblins: prop.banner (shows who holds a place), prop.tent, prop.palisade, prop.cage. For terrain links: prop.bridge, prop.ladder.

## 8. Ground textures

Optional tileable textures; where empty, terrain's shader draws procedural colour.

- [x] `ground.grass`
- [x] `ground.dirt`
- [x] `ground.stone`
- [x] `ground.sand`
- Texture size (default 512 px, covering how many metres?): > 512 px covering 4 m.

## 9. Out of scope here (say if you want any in)

- Characters, the goblin's rig, the shared humanoid body: the `pc-character` tree.
- Audio (Kenney sounds).
- Weapons (roadmap step 5, art session).
- Fire and water: shaders, not models.
> Agreed, all out of scope here.

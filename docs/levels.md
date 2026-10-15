# Levels

A level is a folder `levels/<name>/` (loaded by `sim/level.gd`):

| File | |
|---|---|
| `layout.png` | the map, one colour per pixel from the legend below |
| `height.png` | optional: how high each cell stands, in grey |
| `level.json` | its name, legend overrides, the entities' names and props, the start order, spawn points, level links |

Every level is a zone on the server (docs/design.md, Zones): loaded on
its first visit, kept loaded. `--map=<name>` is where new players start;
everyone else is in the zone they were last in. On a server's console,
`zones` lists them and `zone reset <name>` rebuilds one from its map.
`levels/test_room` is the original room; `levels/sample` uses every entry in
the legend, with heights, stairs and a link back to the test room;
`levels/castle` is the first map made in the level editor. `levels/wilds`
is the land south of it, 256 x 256 cells under the sky, made by
`tools/make_wilds.gd` (below).

## The grid: double resolution

`layout.png` is drawn at double resolution, like the ASCII maps
`sim/terrain.gd` reads: the pixel at `(2x, 2y)` is **cell** `(x, y)`, the
pixel at `(2x + 1, 2y)` is the **edge** east of it, `(2x, 2y + 1)` the edge
south of it, and the `(odd, odd)` pixels are **corners**, which mean nothing.
A map of `W x H` cells is about `2W x 2H` pixels.

- A **wall** pixel on an edge between two walkable cells is a thin wall
  there; a **door** pixel, a door.
- An edge between a walkable cell and void is always a wall, the outer
  wall, whether or not it is drawn: a map may outline itself in wall pixels
  or leave them out.
- A wall or door pixel on a cell position is void.
- Any other colour on an edge (filler such as the ground's own, or void)
  leaves it open. Painting the edges and corners between cells of one
  ground in that ground's colour makes the picture read as the map.

## The legend

![The legend's swatches, in the order of the table](levels_legend.png)

In the order of the swatches above:

| Colour | Meaning | On | |
|---|---|---|---|
| `#000000` | void | cell | nothing there; also any pixel more than half transparent |
| `#9a9a9a` | stone floor | cell | walkable |
| `#4f9a3c` | grass | cell | walkable |
| `#8a6440` | dirt | cell | walkable |
| `#2f6fd0` | water | cell | not walkable, but no wall: nothing is built along it, sight passes over, a pushed body stops at its edge unhurt |
| `#ff6a00` | fire | cell | walkable; burns any creature standing in it |
| `#3c2a22` | wall | edge | a thin wall |
| `#c88a3c` | door | edge | a door (wood, 20 hp) |
| `#e8d44a` | stair | cell | walkable; joins two heights (below) |
| `#00ffff` | player start | cell | a joining player's place |
| `#ff3030` | monster: imp | cell | mass 40 |
| `#a00000` | monster: brute | cell | mass 70 |
| `#ff80a0` | monster: sneak | cell | mass 25 |
| `#f0b070` | crate | cell | a wooden crate to push |
| `#5a5a78` | boulder | cell | a stone boulder, mass 200 |
| `#7a3cb4` | cart | cell | a low cart, mass 60 |
| `#8c4a1c` | chest | cell | a chest of 4 slots; its props say what is in it |
| `#ffe000` | torch | cell | a torch on a post: light, and a little heat |
| `#fff0b0` | lantern | cell | a lantern on a short post: light only |
| `#ff00ff` | level link | cell | stepping onto it takes that player (and companion) to another zone |

A marker's cell (start, monster, crate, boulder, cart, chest, torch, lantern, link) is
walkable, and its ground is the kind most of its four neighbours are
(stone if none). A colour not in the legend is void, and the server says so
when it loads the map.

`level.json` can change or add colours:

```json
"legend": {"wall": "#402a20", "monster_wraith": "#c0c0ff"},
"monsters": {"wraith": {"mass": 20.0, "sight_range": 9}}
```

A new `monster_<type>` colour needs its type under `"monsters"` with its
props.

## Heights and stairs

`height.png` is the size of `layout.png`; a cell pixel's grey is its
height, level `n` = grey `n * 40` (`0`, `40`, ... `240`), up to 6 levels.
No `height.png` means everything is at 0.

- Walking between two cells of different heights needs a **stair**: a
  stair pixel on the lower cell, next to a cell exactly one level up, climbs
  toward that cell (its direction comes from its neighbours). Up it and down
  it are walkable; anything else is a **ledge**, which nobody walks up or
  down, and no diagonal crosses a change of height.
- A body **pushed off a ledge** falls: it stops in the cell below, stunned,
  and takes 3 impact per level fallen (`World.FALL_IMPACT_PER_LEVEL`). A body
  pushed at a ledge up does not move: it is stopped, as by a wall.
- **Higher cells see over lower walls**: a wall or door stops sight only if
  the one looking stands no higher than both cells it is between. Ground
  higher than both ends of a line of sight blocks it.
- The 3D view raises each cell by half a unit a level, draws stone cliff
  faces down its sides, and draws stairs as four steps; walls and doors
  stand on the higher of their two cells. The 2D view draws higher cells
  lighter.

## Light, heat and north

- `"ambient"` (0 to 1, default 1): the light everywhere before any
  source. At 1 the level is fully lit; below `Companion.DARK` (0.35) a cell
  with nothing near is dark: drawn darker in 3D, and a companion says so.
  Fire, torches, lanterns and the lantern every player and companion
  carries light it (docs/design.md, Heat and light).
- `"outdoor"` (`true` or `false`, default `false`): under the sky. The 3D
  view lights it with a day sky and sun instead of the dark under-stone
  look, lays a forest floor under everything, and draws its outline (every
  edge between the land and the void) as a band of trees on the void
  instead of walls: a tree on every cell beside the land, thinning out over
  three cells, scattered to eight. Walls painted inside the map stay
  walls. The forest's edge blocks walking and sight exactly as the outer
  wall does; a companion is told she is outdoors, and her map's `#` is
  "wall or forest". `levels/castle` is outdoors. (Later the forest's edge
  may be crossable, into a forest map.)
- `"north"` (`"up"`, `"down"`, `"left"` or `"right"`, default `"up"`):
  which way in layout.png is north. Every direction a companion hears is a
  compass point from it, and the HUD compass shows it.

## level.json

```json
{
	"name": "Sample",
	"centre": [6, 5],
	"starts": [[1, 4], [2, 4], [1, 3], [2, 3]],
	"entities": [
		{"at": [8, 7], "name": "Sneak", "props": {"sight_range": 4}},
		{"at": [13, 9], "name": "Brute", "tint": "#802020", "facing": [-1, 0], "idle": "guard"},
		{"at": [3, 2], "idle": {"mode": "patrol", "route": [[3, 2], [9, 2], [9, 6]], "loop": false}},
		{"at": [5, 8], "idle": {"mode": "gather", "point": [6, 9]}}
	],
	"spawn_points": {"path_end": [13, 5]},
	"links": [{"at": [14, 5], "to_map": "test_room", "to_spawn": ""}]
}
```

All of it is optional.

- `centre`: where the camera first looks (default: the first start).
- `starts`: the order the start markers are taken in; start markers not
  listed come after, in reading order (rows top to bottom, then left to
  right).
- `entities`: names, props (`mass`, `sight_range`, `body_material` as
  `"stone"` / `"wood"` / `"flesh"`, a chest's `slots` as item ids:
  `["bandaging_kit", "", "", ""]`) and tints for the markers at those
  cells, which are spawned first, in this order (the order is the entity
  id order, and a server's snapshot finds its entities by their slots).
  Other markers follow in reading order, named by kind: `Crate1`, `Imp2`.
  A monster's entry may also say which way it faces, `"facing": [dx, dy]`
  (each -1, 0 or 1; without one it faces a way of its own, from its name),
  and how it idles with nobody in sight, `"idle"`: a mode, or the mode
  with what it needs:
  - `"guard"`: stays on its cell facing its way, and now and then glances
    aside (up to 90 degrees) and back.
  - `"wander"` (`"radius"`, default 3): strolls to cells near its own,
    pausing between.
  - `"patrol"` (`"route"`: cells, `"loop"`: true to go round, false to go
    back and forth): walks the route, pausing at each cell of it. Without a
    route, a short loop of its own about its cell.
  - `"gather"` (`"point"`: a cell, like a fire): stands or sits round it,
    facing it, each in a place of its own.
  - `"none"`: stands where it is.

  Without one, imps wander, brutes guard and sneaks patrol (a monster of no
  kind stands). An entry with nothing but `at`, `facing` and `idle` (as the
  level editor writes them) leaves the spawn order as it is, so setting a
  monster's facing does not rename it or move its slot. It idles at a slower step than it chases; a fight
  interrupts it, and after the fight it walks back (its cell, its route,
  its place at the point) and goes on.
- `spawn_points`: named cells where a link into this map can arrive.
- `links`: one per link marker, `to_map` the level to load and
  `to_spawn` the spawn point there ("" for its first start); `"one_way":
  true` for a link with no way back on purpose (a drop, a trapdoor), so the
  world map's check does not flag it.
- `neighbours`: the level across each map edge, `{"east": "wilds"}`: walk
  off the east edge and arrive at the west edge of wilds at the same row
  (north and south keep the column). The neighbour names this level on its
  opposite side (see Edge links).
- `places`: what factions hold here (see Places and who holds them), by
  key: `{"goblin_camp": {"at": [200, 40], "kind": "camp", "radius": 12,
  "worth": 2, "holder": "goblins", "name": "the goblin camp"}}`. `kind` is
  camp, keep, farm, gate, mine, stockpile (where the town banks what is
  brought home: see The stockpile) or other; `radius` defaults to 8
  cells, `worth` to 1, `holder` (who holds it at the start) to nobody.
- `buildings`: the buildings standing here, a list of `{"slot":
  "building.house", "at": [12, 4], "facing": [0, 1]}`. `slot` is one of
  `Level.BUILDINGS` (building.hut 3 x 3, building.house 4 x 6,
  building.shed 2 x 3, building.well 1 x 1, across by deep facing north or south, the other way
  round facing east or west); `at` is the footprint's top-left cell;
  `facing` is the side its front is on (south if not given). The
  footprint is the inside, ordinary floor; the building's walls and door
  are the map's own edges round it, drawn in the layout as any wall, so a
  building changes no rule: it says where the roof, the inside floor and
  the trim are drawn (art-kit's `building.*` slots), and what counts as
  inside. A well stands on a water cell instead (`Level.ON_WATER`): the
  water stops walkers and lets sight pass, it has no walls and no inside,
  and its water is drawn as ground under its rim. One not on floor (or
  water) of one height, or overlapping another, is left
  out with a warning; one whose outline has open edges stands, with a
  warning. The building prefabs below lay the walls and the record together
  (decision 265).
  A building may also say what it is to its town: `"use"` (one of the
  economy's buildings in `levels/economy.json`: forge, kitchen, inn) and
  `"town"` (the key of a stockpile place on this map), as
  `{"slot": "building.house", "at": [12, 4], "use": "forge", "town":
  "square"}`. The town's records (economy's Towns) then give its state:
  damaged after a raid, standing again once repaired. One a town already
  has, a use there is not, or a town that is no stockpile place stands
  unlinked, with a warning; one outside its place's radius is linked, with
  a warning. A building with no use is scenery and always stands.
- `town_walls`: which ring of this map's walls is a town's wall, a list of
  `{"town": "square", "rect": [x, y, w, h]}`. `town` is a stockpile place's
  key, as for buildings; `rect` is the cells the wall encloses, and the wall
  is its outline: the edge just outside each border cell, drawn in the
  layout as walls, with doors for gates. The town's walls level (economy)
  says how it looks: 0 a rubble bank that still blocks, 1 a palisade, 2
  stone, 3 stone with towers (decision 298). One whose town is no
  stockpile place, or has a wall already, or whose rect is off the map, is
  left out; open edges on its ring, or a place cell outside it, are warned.

## Level links

A player stepping onto a link marker goes to the zone `to_map`, loaded
if nobody has been there yet, at `to_spawn` (the nearest free cell to it;
a safe start if a monster is close), their companion beside them. Nobody
else moves. Travel does not heal or revive, as a reset does. Their record
keeps the zone, so a restart brings them back there. The test room's link
is in its top-left corner, (1, 1), to the sample; the sample's leads back.
Its second, at the dead end of the south-east corridor, (30, 34), goes to
`levels/castle` ("The Castle"), arriving at (26, 13) beside the castle's
own link at (27, 12), which comes back to (30, 33).

## Edge links

A player who walks into the edge of a map where level.json names a
neighbour on that side goes there, with their companion, as a link takes
them: they arrive on the neighbour's opposite edge at the same row (east,
west) or column (north, south), kept on the map if the neighbour is
shorter, at the nearest free cell to it. The outline stays a wall (an
outdoor map's forest edge); the bump against it is the crossing. Only
players cross for now; `WorldMap.crossing(area, cell, direction)` gives
the same answer without a player or a zone, for the world tick to move
groups across.

## The world map

`WorldMap.build()` (`sim/world_map.gd`) reads every level (`Level.names()`:
the folders under `levels/`, prefabs left out) into one graph: the areas,
and the ways between them, point links and neighbours alike. Its
`problems()` lists what is wrong with how they connect:

- a link or neighbour to a level that does not exist, or to a spawn point
  the level does not have;
- a way with no way back (unless the link says `"one_way": true`), and a
  neighbour the other level does not name back on its opposite side;
- a cell level.json holds that is off the map (the cells are the ones a
  resize moves, `LevelMap.moved_config`), and a spawn point or start on no
  floor;
- an area that cannot be reached from the default map, or has no way back
  to it;
- the level's own load warnings (a link off its marker, a marker with no
  link).

`godot --headless --path . --scene res://tools/check_world.tscn` prints the
list (exit code 1 if there is anything on it).

### Places and who holds them

A place (level.json `places`) is a cell and a radius in an area that a
faction holds. The factions are in `levels/factions.json` (the goblins and
the town: a name, a colour, the monster kinds acting for each, who each is
hostile to); "nobody" holds what no faction does. Held ground is the cells
within a held place's radius (a disc); ground two factions' places both
cover is contested; a place nobody holds is open ground and counts for no
one. An area's holder is only a label: the faction holding the most worth
of its places (contested on a tie, nobody with none).

`Holdings` (`sim/holdings.gd`) is who holds each place now (by id,
`<area>/<key>`), how strong they are there, and since which world step.
The server makes it at boot (`World.holdings`): the levels' starting
holders, then the snapshot's `holdings` over them (a snapshot from before
holdings loads with the levels' own). The world tick reads it (`holder`,
`places_in`, `places_of`, `ground`, `area_holder`, `blocked_cells`) and
changes it (`take`, `strengthen`, `weaken`), and it says so
(`place_taken`, `area_changed`, `strength_changed`). A builder change
accepted takes up places added, moved or gone (`rebind`). A camp's place
belongs on its gather point, where its group gathers. Prefabs keep their
places, and stamping one gives a key the map already has a `_2`; builder
mode's `mark_place` marks one. Nothing in play shows them yet.

### The stockpile

A place of kind `stockpile` is where the town keeps what players bring
home: gold, ore, wood, cloth and food as counts, and gear item by item
(`Stockpile`, `sim/stockpile.gd`, kept as `World.stockpile` and saved in
the snapshot). Things reach it physically: put into a depot (a chest
with `"props": {"depot": true}` inside the place's radius), put down
or thrown onto the place's ground, or carried in on a crate or cart
pushed onto it (the cart is unloaded and stays). Either way they are banked at once (a
sack of ore as its ore, gear as itself; the store counts it, its ledger
says who and when). Picking loot up counts for nothing, and so does
carrying it onto the ground: only what is let go of there is banked.
All of it only while the town holds the place: if another faction takes
it, the depot refuses and what is put down there just lies there. Players
never take from the stockpile; the town's own work (production, the
shop, raids) does.

A shop counter is a chest with `"props": {"shop": true}` inside a
stockpile place's radius (decision 280). A player beside it sees what the
town's workshops have made for sale, with prices, and buys with their
own gold; something put into the counter is sold to the town, if the
town is short of it. Like a depot it keeps nothing, and works only while
the town holds the place.

In builder mode, stamp the `town_store` prefab for a whole store: an open
yard with its depot and shop counter, and the stockpile place the town
holds (decision 301). The place tool's `use` (`depot` or `shop`) makes any
chest one, and `Stockpile.check` says what is wrong with a level's store.

### Routes between areas

`world_map.routes()` (`WorldRoutes`, `sim/world_routes.gd`) finds the
cheapest way from a cell in one area to a cell in another, for the world
tick to move groups without walking them cell by cell:
`route(from_area, from_cell, to_area, to_cell)` gives the legs, one per
area passed through ({area, from, to, steps, way}), or [] if there is none.
Its graph's points are the ways' ends (a link's marker and its spawn point;
an edge's middle floor cell and the matching cell across), joined inside
each area at the real length of the walk (walls, doors, corners, ledges
and stairs as World walks; a diagonal is 1.5 steps). Those lengths come
from a distance field per way end (the steps from it to every cell of its
area), made on a WorkerThreadPool task when the routes are made, from
copies of the areas, so making routes costs the caller a few milliseconds;
the fields follow in about half a second (the wilds' are most of it).
`is_ready()` says when they are all in; until then a route walks the areas
it needs there and then (about a quarter of a second for the wilds), so the
world tick can wait a tick instead. With them, a route's first and last
legs are lookups; a route inside one area still walks from start to end.
`along(legs, cells)` says where a group is after that many steps of a
route ({area, cell, leg, done}), the cell on a shortest walk where the
fields have it. `blocked` (a Callable taking a way and a faction) can close
a way for every route found after. A WorldMap built again (a level edited,
a builder change accepted) makes new routes and new fields.

Held ground is physical: `World.holdings.make_routes(world_map)` gives
routes with a layer per faction, and `route(..., faction)` never walks
ground another faction holds (contested ground among it). It goes round;
if it cannot, it walks as far as it can, past held ground it can get
round, to the edge of the first it cannot, and its last leg says so:
`"meets": "<place id>"`, for the world tick to make the encounter (a goal
in held ground is met the same way; a group standing in it meets it where
it is). Each layer has its own fields; a place taken makes that area's
fields again on the pool, and until they are in its routes walk the area.
A route with no faction ignores held ground.

### The world map editor

```
Godot_v4.7.2-stable_win64.exe --path <project> -- --world-map
```

shows every level as a box and every way as a wire (`editor/world_map_view`,
a GraphEdit). A box has an "in" row (where links arrive), its four sides
(its neighbours) and a row per link (its cell, where it goes, a list of the
target's spawn points to arrive at, and x to take it out of level.json).
Drag a side to a side of another box to make the two neighbours both ways;
drag a link to a box's "in" to send it there (arriving at `from_<this
level>` if the target has that spawn point, else its first); drag a wire's
end away to undo either. A new point link needs its marker, so it starts
in the level editor; double-click a box to open its level there. The panel
on the right lists the problems as they stand. A box's title is tinted
with the colour of its area's holder, and it lists its places, each with
its holder's colour (as the levels start them: the server's holdings are
not read here). Ctrl+S writes the changed
level.json files and where the boxes are (`levels/world_map.json`, read by
nothing else). For code (builder mode's new area at an edge),
`WorldMap.join(doc_a, side, doc_b)` and `unjoin` do the same to two MapDocs
and return what they replaced, for undo.

## The level editor

```
Godot_v4.7.2-stable_win64.exe --path <project> --edit=<name> [--edit-size=32x24]
```

opens `levels/<name>/layout.png` as a top-down grid (`editor/`), or a blank
map of that many cells (default 32 x 24) if there is none yet; nothing is
written until you save. Run it from the project: an exported game cannot
write its levels.

- **The palette** (left) has every cell type and thing in the legend,
  the three edge types (wall, door, clear), and any colour `level.json`
  adds. Click one, or press its key: `1`-`0` for the first ten (stone,
  grass, dirt, water, fire, stair, wall, door, clear, void), `Shift+1`-`0`
  for the next (start, imp, brute, sneak, crate, boulder, cart, chest,
  torch, lantern), `Alt+1` for link and `Alt+` the rest.
- **Cells**: left click paints the cell under the cursor; a drag paints
  the line of cells it passes over.
- **Edges**: with wall, door or clear picked, the edge nearest the cursor
  lights up and a click sets it; a drag sets a straight run along that
  line, however the cursor wanders off it.
- **Right click** (and drag) erases: cells to void, edges to clear.
- `Ctrl+S` saves, `Ctrl+Z` undoes a stroke, `Ctrl+Y` (or `Ctrl+Shift+Z`)
  redoes it. Middle drag or the arrow keys pan, the wheel zooms.
- The faint lines along the floor's outline are the outer walls the game
  builds by itself; you never need to draw them.
- `Ctrl+R` shows the **canvas** panel: grow or shrink the map by 1 or 8
  cells on any side. Everything keeps its place on the ground, and
  `level.json`'s cells move with it (entities, routes, gather points,
  starts, spawn points, links, the centre), as does `height.png`. What falls
  off a shrunk side is dropped, and the status line names it. Each change is
  one undo step.
- **Prefabs**: the area tool (`A`) drags out a rectangle (right click lets
  go); its panel saves what is in it under a name as a prefab. The stamp
  tool (`P`) lists the prefabs: pick one and it follows the cursor as a
  see-through ghost, `R` (or a right click) turns it a quarter clockwise
  (`Shift+R` back), and a click lays it down, one undo step. See Prefabs below.
- **Area tools** (`editor/area_tools.gd`): with an area dragged out, its
  panel fills it, one undo step each, from the **seed** shown (`-` / `+`
  to change it; the same seed gives the same result):
  - **pond**: an uneven blob of water in one piece, with a shore of dirt
    (0-4 cells wide) round it inside the area;
  - **grove**: trees scattered over the ellipse in the area, thickest in
    its middle, at a density (10-100%), with a clearing of grass in the
    middle if asked. A tree is a void cell, drawn as one outdoors;
  - **scatter**: boulders, crates and trees (pick which) on a share of its
    ground cells (1-30%), never two side by side, never on a marker;
  - **fence**: a wall round the area with a gate (a door) in the middle
    of the side picked, or none.

  **again, next seed** takes the last fill back and lays it with the next
  seed, while it is still the last thing done.
- **Path** (`T`): clicks add points (right click takes the last back);
  `Enter` lays a winding path of dirt, stone or grass through them in
  order, `[` and `]` its width (1-6). It crosses anything, water and void
  included, and opens the walls and doors it runs through.
- Anything a fill, a path or a stamp lays over takes that cell's
  `level.json` entry and link with it.

Saving writes the same double-resolution `layout.png` (the file's own size
kept), its `.import` set to Image, and reports what the server would warn
about. `level.json` is written when something in it changed (a monster's
facing or idling, a resize); `height.png` only after a resize. Run from the
project, the game reads `layout.png` itself rather than its import, so a
saved map plays at once with `--map=<name>`.

Not yet: painting heights, a 3D preview, and fences that look like fences (a
fence is a wall, drawn as the castle's).

## The wilds

`levels/wilds` (256 x 256, outdoor) is written by `tools/make_wilds.gd`
from a fixed seed: grass with patches of dirt, an uneven band of forest
round it (4 to 24 cells deep), groves inside (void, drawn as trees; none
under 16 cells) and a few ponds, a winding dirt path from its link at the
top to a farmstead in the middle (two houses, two fenced fields and a well,
stamped from the prefabs) and on to a goblin camp in the north-east, its
three imps the only monsters for now. The castle's road leads to it: the
link at the foot of the road, (16, 23), arrives at the top of the wilds'
path, and the link there goes back to (16, 22). Run the tool again to
remake it, then touch it up in the editor (running it again undoes the
touching up).

## Prefabs

A prefab is a piece of map to stamp elsewhere, kept in
`levels/prefabs/<name>/` in a level's own format: `layout.png`,
`level.json`, and `height.png` if it has heights, its top-left cell at
(0, 0) (`editor/prefab.gd`). Its `level.json` holds only what goes with the
piece: the entities' entries (names, props such as a chest's `slots`,
facing, idling with its route or gather point), links, places, buildings,
and any `legend` or `monsters` it uses; no starts, spawn points or centre. A prefab is not a
level: the server never loads one, and the level tests skip the folder.

Stamping one with its top-left at a cell, turned 0-3 quarter turns:

- each of its cells that is not **void** replaces the map's, with its
  height; its void cells leave the map as it was, so a round camp lays round;
- each edge between two of its cells, one of them not void, becomes the
  prefab's (clear where it has none). Walls round a house are part of the
  prefab only if the ring of cells outside them is too, which is why the
  house and the field carry a ring of dirt or grass;
- the map's entries and links on the cells it covers go, and the prefab's
  are put where their cells land, with facings, routes and gather points
  turned with it.
- the map's buildings whose footprint it lands on go, and its own are
  added where they land, turned with it.

Seeded by hand (`tools/seed_prefabs.gd` draws them; run it again after
changing a drawing):

| Prefab | Cells | |
|---|---|---|
| `small_house` | 6 x 6 | a stone room with a door south, a chest (a bandaging kit) and a lantern, a ring of dirt |
| `campfire_camp` | 7 x 7 | a round dirt clearing, three imps gathered at the fire, a chest and crates |
| `fenced_field` | 10 x 6 | dirt behind a fence with a gate south, a ring of grass |
| `well` | 5 x 5 | a building.well on water ringed with stone |
| `building_hut` | 5 x 5 | a building.hut: 3 x 3 of stone in walls, a door south, a ring of dirt |
| `building_house` | 6 x 8 | a building.house: 4 x 6 of stone in walls, a door south, a ring of dirt |
| `building_shed` | 4 x 5 | a building.shed: 2 x 3 of stone in walls, a door south, a ring of dirt |

A camp's group is its gather point: every monster gathering at one cell is
that camp, so a coarse world tick can move the group (or hand the place
over) by that cell, without the per-tick AI.

## Builder mode

In the game, `B` turns builder mode on for a player allowed to build (a
host's own player; on a server, the player ids in `--builders` or
`PSYKINETIC_BUILDERS`). It is on only where the server has
`ANTHROPIC_API_KEY` in its environment (`/etc/psykinetic/env`, never in a
client), or runs with `--builder-stub`, which answers from a script.

- A left drag picks an area (up to 64 x 64), outlined on the ground, and a
  box opens: say what to make there ("a pond", "a goblin camp guarding a
  chest"). The server asks Claude (`builder/`, decision 197), which changes
  a copy of the level with the editor's own tools, kept to the area.
- The proposal shows over the area as a ghost, coloured as the legend,
  with what Claude says it made and what the request cost. `Enter` (the box
  empty) accepts it; words in the box are a follow-up ("bigger", "move it
  north") that remakes it; `Esc` discards it. `Ctrl+Z` takes back the last
  change to the level. `B` leaves; walking waits while it is on.
- Accepted, it is one undo step on the level, saved to the **overlay**
  (`user://levels/<name>/`, decision 199): a level there is read instead of
  `levels/<name>/`, by the server and by `Level` everywhere. The zone is
  rebuilt from it as `zone reset` does, without healing: players stay where
  they are, monsters and chests are spawned again (so a chest can be looted
  twice; a known gap of a dev tool). Everyone in the zone, and everyone who
  comes in later, is sent the edited level (the "terrain" message, decision
  200), since a client's own copy is its pck's.
- **A new area beyond the edge**: when the area picked touches the map's
  edge with no neighbour beyond it, Claude can make a new level there
  (`new_area`, asked for as "somewhere new to the east", "the woods past
  here"): a first draft (`builder/area_draft.gd`) of grass and dirt, groves
  and maybe a pond, forest round it 3 to 11 cells deep and open where the
  way arrives, with a start just inside. The level picked gets a way of dirt
  from the middle of the area out to its edge, and the two become
  neighbours both ways (walk off the edge, arrive on the new level's
  opposite edge at the same row or column; see Edge links). The ghost
  outlines the new level past the edge in orange. Accepted, the new level is
  saved to the overlay first, then the level picked; it opens when someone
  first walks in. `Ctrl+Z` takes back the way, the neighbour and the new
  level together; not while anyone is in it.
- The server logs every request: what was asked, its tokens in and out,
  what it cost, the request id. A request stops at `--builder-max-cost`
  dollars (default 1); the account's limit is set in the Claude Console.
  `--builder-model` (default `claude-opus-5-5`) and `--builder-effort`
  (default medium) choose how it thinks.
- On the server's console: `builder` (how it is, the money spent, the
  edited levels), `builder export` (each edited level's files and where
  they go in the repo), `builder drop <name>` (the edits forgotten, the
  repo's level again, the zone rebuilt). Once an edited level is copied
  into `levels/` and committed, drop it: at boot the server warns about
  every level it reads from the overlay, as a later change to that level
  in the repo would not be seen.

## Making a level

1. Draw `layout.png` in the level editor (above) or in any paint program (at 1 pixel per cell or edge, no
   smoothing), and `height.png` if it has heights.
2. Import both as **Image**, not as a texture: the dedicated server has
   no renderer to read a texture's pixels from. The editor sets this for
   `layout.png`; for a picture painted elsewhere, and for `height.png`, it is
   "Import As: Image" in Godot's Import dock. `tests/level_test.tscn` checks
   this for the test room.
3. Write `level.json` if anything needs naming, ordering or linking.
4. `--map=<name>` to play it; the server prints any warning about the map
   (unknown colours, a stair with nothing above it, a link with no entry).

# Levels

A level is a folder `levels/<name>/` (loaded by `sim/level.gd`):

| File | |
|---|---|
| `layout.png` | the map, one colour per pixel from the legend below |
| `height.png` | optional: how high each cell stands, in grey |
| `relief.png` | optional, outdoors: the ground's elevation in metres, one pixel a cell (see Relief) |
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
| `#6fa8e0` | ford | cell | shallow water, walked through: a step into it takes twice as long and costs routes twice (decision 505); its footing is the ground round it |
| `#a8c850` | tall_grass | cell | grass grown tall (decision 508): grass ground that hides whoever stands in it (World.cover_at 0.7; how a look uses it is Senses'), a step into it takes 1.25 times as long, and a body of 40 kg or more walking through tramples flat the cells it leaves, for two days (a trail; where it stands still hides it) (no cover, no slowing); not under a building. The editor paints it, and fills an area with it ("tall grass": meadow patches and a band along the trees, clear of markers, spawn points and places; TallGrass.lay) |
| `#c8b878` | slope | cell | a ramp of ground outdoors (decision 513): a stair to the sim (a one-level rise to its one orthogonal neighbour a level up; two in a row climb two), drawn as a ramp, not steps; its footing the ground round it |
| `#6e6a64` | rock | cell | a rock (decision 513): no floor, walled round like void, so it stops a step and sight, but drawn as rock (art-kit's rock slots), not a tree; its footing the ground round it. A height step with no stair or slope is a cliff: a face of rock, no step up or down, a fall for a body pushed off; sight from under it sees its lip and nothing behind it. The editor's "outcrop" area fill raises one (Outcrops.lay) |
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

## Relief

Hills, valleys and ridges (decision 525). `relief.png` is one pixel a cell
(the level's size in cells, not layout.png's), each the ground's elevation
in centimetres as `R * 256 + G` (B unused; 0 to 655.35 m), written by
`Relief.image` and read by `Relief.read`. Godot's PNG loader keeps 8 bits a
channel, so the centimetres are split over two. Its `.import` is as Image,
like height.png's. With no `relief.png` the elevation is derived from the
whole levels, 0.5 m a level (`Relief.LEVEL_M`), and the level walks, falls
and sees exactly as above. Given both, `relief.png` is the ground and the
level says so; its whole levels (`World.height_at`, terrain `heights`) are
its elevation rounded to levels, for what still reads levels.

- **Walking is by slope.** An orthogonal step rising or falling up to
  `Relief.WALK_RISE` (0.45 m) is walked; more is a cliff, as a ledge above.
  A diagonal is walked when it (within 0.45 x sqrt 2) and both of its
  orthogonal routes are. A stair or slope cell climbs up to
  `Relief.STAIR_RISE` (0.5 m) its own way; it is found as above, a cell
  0.25 to 0.5 m up. `Relief.cliff_between` and `Relief.step` are the rules,
  for the sim, the routes and the views alike.
- **Uphill is slower**: a step rising `r` takes `1 + 0.5 r / 0.45` as long
  (`Relief.pace`; 1.5 at the steepest), and the world map's routes cost the
  climb in their half steps, so they take valleys and saddles. Down is as
  fast as the flat.
- **A fall** off a cliff hurts `FALL_IMPACT_PER_LEVEL` for each 0.5 m of the
  drop, rounded (one at least).
- **Sight over relief** is a line from 1.5 m over the viewer's ground to 1 m
  over the seen cell's, stopped by ground above it: a ridge hides the
  valley behind it, and from under a cliff higher than the eye its lip is
  seen, not what stands back from it. Walls are seen over by an eye more
  than 0.45 m over both their cells. Light and heat keep the whole levels'
  rule. A level with no `relief.png` sees as above.
- **Buildings stand on pads**: a building's or roof's cells lie within
  `Relief.PAD_FLAT` (0.05 m) of each other, or it is left out, said as
  "not all on clear floor of one height". A bridge's banks likewise.
- **Water holds its surface**: a water or ford cell's elevation is the
  water's. A pond (water no stream runs through) lies level within 0.05
  m; a stream steps only down along its path; dry ground beside water
  stands at least `Relief.SHORE_LIP` (0.1 m) over it. What is not so is
  said, and left as it is.
- `Relief.corner_heights(field, size, cell)` gives a cell's four ground
  corners (the mean of the cells joined to it walkably at each, per side
  of a cliff): the views' ground follows it.
- The "terrain" message carries `relief.png` with the other files.

The sample level has one: its whole levels lifted 0.2 m over its water,
and a gentle rise of about 0.9 m east of the stream. `levels/hills` is the
showcase (`tools/make_hills.tscn`): a valley winding down the middle, its
floor falling 5 m north to south and its river looping down it as a
curve (`waters`, 559), 1.7 to 3.2 cells wide, swinging about 7 cells
either way every 26 or so, with a ford and a bridge, a dirt road (563)
from the link west over the bridge and up through the west escarpment's
way, a waterfall (570): a stream across the plateau's top dropping 7.9 m off
its west cliff into a pool, forded below it, running on into the river, hills rolling 2 m either way, two escarpments (525
amended (2)): one to the west with a 3 m face east over the valley, a long
slope up to it from the west and a ramp through its face, and one 2.5 m
high south-east of the valley facing north; and a plateau 6 m up to the
east whose west side is a cliff, its south side a spur falling 0.25 m a
cell that is the way up. Its flanks
are mostly 0.3 m a step, the full walkable 0.4 in bands; its ground is
painted by slope with no stone (the stone ground draws as paving): bare
dirt on the steep bands, the crests, the banks and the plateau's rim,
grass elsewhere.

**Laying relief.** `Relief.lay(map, rect, seed, options)` lays hills,
valleys and ridges over an area of a `LevelMap`: a rolling noise (`base`,
`amplitude`, `scale`), `ridges` and `valleys` along polylines, a `tilt`,
`plateaus` raised with cliff `faces` (the other sides falling away as a
`spur`), `keep_flat` pads, and `streams` found where the water runs (a
priority flood, then the cells draining most, keeping to a valley's floor),
carved under their banks. A `rivers` entry, `{line, wavelength,
amplitude, width, seed}` (559), is laid as a curve rather than found: a
sine-generated meander about its line (the way it heads swings either
side of the line's as a sine of the distance along it, so its loops are
round all through), loops `wavelength` cells of the line long reaching
`amplitude` either side, both wandering by the seed; control points every
tenth of a wavelength, each its width (`[least, most]`, wandering); its
cells the curve's raster, as on load; its curve returned in `waters` for
level.json. Keep it to a valley's floor at least `amplitude` + `most`
wide. `Relief.road(map, from, via, to, width, crossings)` (563) lays a
road as a curve for `roads`: the cheapest walk over walkable ground (never
into water but the `crossings`, a bridge's cells; never up or down a
cliff; climbs and the edges of water, void and cliffs dearer), then made
round: its corners cut, a gentle wander across it, a control point every 4
cells, a crossing's cells and two either side kept so it runs straight
over a bridge, each point `width` wide but narrowed where it must be, as
round and winding as lets its cells lie on the ground with no cliff
between them. A valley has a floor (`valley_floor` cells either
side of its line) falling `valley_fall` along it, so its stream runs its
length; a ridge entry may be `{line, height, width}` (a knoll: one point).
An `escarpments` entry, `{line, face, height, back, taper, ways,
way_width}`, is a face `height` m high down its line, looking `face`
(a side or a Vector2i), with the ground behind rising to it over `back`
cells; its edges are kept out of the cap but where the `taper` at its ends
brings it under the walk, within `way_width` / 2 of each of its `ways`
(fractions along the line), or where it comes out under 1 m, and there the
cap makes ramps fanning out below it. `lay` returns the `faces` it kept out
of the cap, for a later pass over the same ground to keep.
With `kinds` it paints the ground by slope too: stone where a step to a
neighbour is 0.34 m or more, bare dirt from 0.24 m, on a crest (0.3 m over
the cells within 3) and beside water, grass elsewhere, the thresholds
wandering ±0.04 m so the bands are no contour lines (`rock_step` and
`dirt_step` set them). `slope` caps a step lower than 0.4 m, with
`steep_bands` (a share of the ground, in noise bands) still at 0.4: gentler
flanks with steep bands through them. The editor's relief fill paints so.
Everything but the faces is limited to `Relief.LAY_SLOPE` (0.4 m) a step,
so it is walked; the same seed lays the same ground. `Relief.pad(map,
rect)` levels a footprint and a cell round it.

## Light, heat and north

- `"ambient"` (0 to 1, default 1): the light everywhere before any
  source. At 1 the level is fully lit; below `Companion.DARK` (0.35) a cell
  with nothing near is dark: drawn darker in 3D, and a companion says so.
  Fire, torches, lanterns and the lantern every player and companion
  carries light it (docs/design.md, Heat and light).
- `"damp"` (`true` or `false`, default `false`): too damp for a flame (the
  barrow's deepest layer). Its torches, lanterns and fire are put out as it
  is read, each kind said in a warning ("too damp to light"), and a carried
  lantern reaches `Fields.carried_reach(true)` cells (2, half its 4). Set it
  with a low `"ambient"` (about 0.03): beyond a lantern's short pool it is
  dark.
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
- `"dead_ground"` (`true` or `false`, default `false`): nothing lives here,
  no game and no crops (`WorldMap.is_dead`, decision 368). Game's richness
  (`WorldRichness`, for the herds) is 0 on it, as it is indoors, under a
  building's roof and on ground a faction other than the town holds; on
  the rest it thins toward the mine (any place of kind `"mine"`), by the
  walking steps from it across the world map: none within
  `levels/economy.json` `wildlife.mine_dead` (40) steps, full from
  `mine_full` (400) on.
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
- `loot`: a loot table for every chest or monster without its own
  (below): `{"chest": "supplies", "monster": "pockets", "brute":
  "armoury"}`, a monster kind's own key first; `"monster"` leaves wild
  animals out.
- `entities`: names, props (`mass`, `sight_range`, `body_material` as
  `"stone"` / `"wood"` / `"flesh"`, a chest's `slots` as item ids:
  `["bandaging_kit", "", "", ""]`) and tints for the markers at those
  cells, which are spawned first, in this order (the order is the entity
  id order, and a server's snapshot finds its entities by their slots).
  Other markers follow in reading order, named by kind: `Crate1`, `Imp2`.
  A chest's or a monster's entry may name a loot table, `"loot":
  "supplies"` (levels/loot.json; decision 330): rolled as the level is
  built, by the level's name and the cell, so the same each time, a
  chest's empty slots filled, a monster carrying up to 4 things, which it
  drops where it falls. It leaves the spawn order as it was; the
  builder's `place` tool takes `loot` the same way.
  A monster's entry may say what it holds, `"wields": {"right": "spear",
  "left": "shield"}` (catalog ids; its kind's row in levels/monsters.json
  may say the same, and the entry wins; decision 338): it fights with them
  as a player does, and drops them where it falls.
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
- `canopy` and `clearings` (terrain's, decision 464): `"canopy": {"kind":
  "evergreen"}` draws the level's interior void cells as grown pines under
  a closed canopy; `"clearings": [{"centre": [x, y], "radius": r}]` are kept
  open to the sky (radius 6 or more stays sunlit; environment hangs its
  light there). levels/forest is the first.
- `streams` (decision 505): `[{"path": [[x, y], ...]}]`, each a stream's
  cells from its source to its mouth along its middle, the way it flows
  (terrain draws the current from it). Every cell is water (a ford, or
  under a bridge) beside the one before; water with no entry is still.
  The editor's path tool lays one ("as a stream"); `Streams.lay` lays one
  in a generator.
- `waters` and `roads` (decision 559; Jeff: water and roads "drawn as
  smooth curves, then rasterized to cells"): `"waters": [{"points": [[x,
  y, width], ...], "closed": false}]`, control points in cell units, a
  river or stream source first, its width per point; `"closed": true` a
  pond or lake, the curve its shore (width unused). `"roads": [{"points":
  [[x, y, width], ...], "kind": "dirt"}]` ("stone" too). The curve is a
  centripetal Catmull-Rom through the points sampled every quarter cell
  (`Curves.sample`), widths eased between the points'. On load the cells
  come from it (`Curves.cells`): an open water's floor cells within its
  width / 2, a closed one's inside it, are water (a ford's or a bridge's
  kept); a road's floor cells take its kind. An open water's middle
  (`Curves.middle`, a side step at a time) is its `streams` path. The
  layout carries the same cells (whatever lays the curve writes both); a
  cell it has otherwise is made so and said. The views draw the water and
  the roads from the curves, not the cells.
- a bridge is a building entry: `{"slot": "bridge", "at": [x, y],
  "facing": [dx, dy], "length": n, "width": 1 or 2}` (decision 505), its
  length along its facing, all of it over water or fords, a bank of one
  height beyond each end. Its cells are walked on at the banks' height
  with the water still under them, and railings along its sides stop
  walkers but not sight. levels/sample has one, with a ford.
- `markets` (decision 504): `{"castle": {"at": [x, y], "name": "the
  castle market"}}`, where trade routes end that are no town's store; the
  id is `market:<key>`, the cell must be floor. levels/castle has the one.
- `links`: one per link marker, `to_map` the level to load and
  `to_spawn` the spawn point there ("" for its first start); `"one_way":
  true` for a link with no way back on purpose (a drop, a trapdoor), so the
  world map's check does not flag it; `"closed": true` for a way shown but
  not travelled yet (decision 463): stepping on it says "The way on is
  closed." and goes nowhere, no route passes through it, and its `to_map`
  may be a level still to come; `"hidden": true` (608) for a way behind the
  barrow's hidden door, closed to the world map and its routes (maps' side:
  no group walks it) while Main needs nothing from it, the door keeping the
  way; `"sealed": "<mark>"` for a way open to the
  marked alone (decision 540): a player steps through only when their
  record holds that mark (`PlayerRecord.marks`; `Main.mark_player`, the
  console's `mark <player> <mark>` or `-<mark>`), else "The way is sealed."
  once a stand; their companion goes with them; to the world map and routes
  it is closed. The barrow's shortcut from the temple is sealed `draugr`.
- `walls` and `floors`: the wall and floor sets the map is drawn in
  (art-kit's `wall.<set>.*` and `floor.<set>`: castle, wood, stone, cave;
  castle if not given or not a set). The floor set is drawn on the map's
  stone ground; grass, dirt and sand stay as they are. A building's walls
  and inside are drawn in its slot's `wall_set` and `floor_set` (wood for
  homes) whatever the map's are. Drawing only: the sets change no rule.
- `neighbours`: the level across each map edge, `{"east": "wilds"}`: walk
  off the east edge and arrive at the west edge of wilds at the same row
  (north and south keep the column). The neighbour names this level on its
  opposite side (see Edge links).
- `places`: what factions hold here (see Places and who holds them), by
  key: `{"goblin_camp": {"at": [200, 40], "kind": "camp", "radius": 12,
  "worth": 2, "holder": "goblins", "name": "the goblin camp"}}`. `kind` is
  camp, keep, farm, gate, mine, stockpile (where the town banks what is
  brought home: see The stockpile), woodlot, hunting_ground, quarry or
  other; `radius` defaults to 8 cells, `worth` to 1, `holder` (who holds it
  at the start) to nobody. `town` (decision 517), if given, is the key of
  the stockpile place on this map whose town works it (a woodlot its
  woodcutter's); one that is no stockpile place is said, and it works for
  none.
  A camp may hold captives from the start (decision 518): `"holds":
  [{"town": "wilds/store", "resident": "a woodcutter's son", "name":
  "Tam", "trade": "hauler"}]`; `resident` is a worker id, a resident's
  name, or role words `a <trade>'s <son|daughter|brother|sister|father|
  mother|cousin>` (the kin is the town's resident of that trade); `name`
  and `trade` are for one minted. The server places each once, taken by
  the camp as a raid takes, so the kin's plea and the rescue are the
  ordinary ones. For the sample and tests, not a real level.
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
  inside. The crypt's burial table (3 x 2) and pillars (2 x 2) are solid
  and doorless too (580 step 3): rock blocks a level says by their slot.
  A well stands on a water cell instead (`Level.ON_WATER`): the
  water stops walkers and lets sight pass, it has no walls and no inside,
  and its water is drawn as ground under its rim. A solid building
  (`Level.SOLID`, decision 550: building.mound 5 x 5, a barrow) has no
  inside and no floor but its door, the front row's middle cell: the rest
  of its footprint is taken out of the floor as the level is read (nobody
  walks onto it, routes go round), listed in terrain `solid`, and stops
  sight as a wall does; it has no walls on its outline and none is asked
  for (its slot's mesh is the mound), and a link may sit on its door. One not on floor (or
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
  unlinked, with a warning. It may stand anywhere on the map: the place's
  radius is the store's yard, not the town. A building with no use is
  scenery and always stands.
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

## Regenerating levels

The delve-again places (the labyrinths under the castle, the tower's
inside: decision 465) are laid again every few days. A level opts in with
level.json `"regenerate"`:

```json
"regenerate": {
	"generator": "maze",
	"every_days": 3,
	"anchors": [{"rect": [1, 1, 5, 5], "name": "gatehouse"}, {"rect": [19, 11, 5, 5], "name": "deep"}],
	"monsters": {"imp": 3}
}
```

The authored layout.png, height.png and level.json are the template. Each
anchor's cells are copied verbatim every generation: walls, floor,
markers, heights, the links in and out, spawn points, starts, places and
the entities listed there. Every link, spawn point and start must sit
inside an anchor; Level warns of one that does not, since the next
generation loses it. The rest of the map is the generator's: a script
`sim/level_gen/<generator>.gd` with `static func generate(template:
LevelMap, config, seed) -> LevelMap`. `maze` carves a one-cell maze in the
rock between the anchors, opens a doorway or two into each (on a side the
template leaves open; a wall pixel seals a side), joins up what the
anchors cut apart, and lays `monsters` markers (`{kind: count}`) in the
corridors, dead ends first. The seed is the area's name and the
generation number, so a generation is the same on any machine; a map whose
anchors do not all reach each other is thrown away and the next seed
tried, eight times, after which the last map stands.

The `labyrinth` generator (decision 470) lays rooms and halls instead of a
maze, in one of two styles, `"style"`: `"dwarven"` (the halls under the
gatehouse: rooms square-cut, a couple of great halls with a row of pillars,
corridors straight with one bend and two cells wide between halls and
anchors, a door where a corridor meets a room, torches along the ways and
inside the doors, alcoves off the rooms) or `"old"` (the older labyrinths
below: caverns grown from a seed cell, crooked ways, blind ways wandering
into the rock, no doors and no torches, so lanterns matter) or `"barrow"`
(decision 541, Jeff's crypt page: tombs layered, oldest deepest; what each
room is goes by its depth, the distance from the `"entrance"` anchor, the
first unless named, as a share of the map's farthest reach: the shallow
third the town's square tombs with doors, torches and burial niches, an
alcove cell off the walls; the middle third narrow passage graves with
crooked ways and niches, no doors; the deepest the old caverns; chests in
the deepest niches first, the dead a third in each depth band (deepest
first within a band; a layer with one band deepest first), monsters otherwise deepest first unless `"near": {kind:
anchor}` sends a kind to an anchor, the robbers to the altar; its ways are
three cells wide, a brush along the path right up to a shallow tomb's
wall, the tomb walled where the way touches it and entered by its one door
cell, the torches by the walls, the deep blind ways short, a passage grave
a cell under the least width and up to four over the most length, a cavern
grown in a box two cells bigger each way: 541 amended, Jeff: "way too
cramped"). The rules every dungeon is generated under (612, Jeff:
"dungeons need procedural rule - whats different is just the
arrangements"; a level's template is its arrangement, the fixed rooms as
its anchors, and everything between comes from the rules): no passage one
cell wide, so a player, their companion and a second player pass each
other (`Tools.widen` after the carving carves a cell beside every cell of
a single-width run, the dwarven corridors two wide into plain rooms too,
the join-up paths and the caverns' blind ways widened to stubs; rooms and
anchors two cells of rock apart, `ROOM_GAP`; `Tools.join_all` first joins
any part a wall or a failed way left apart, through no wall); a doorway
is a door edge in a room's wall, the one cell allowed (a way that runs
through a walled room gets one each side), with the way outside
it as wide as any; a dead end a cell deep (a tomb's alcove, a niche, the
hidden door's stair cell) may be one; a solid building's cells and a
ledge (a height step with no stair) close a way as a wall does. `Level.narrow_runs` (and
`Tools.narrow_runs` on a LevelMap) is the check: a cell with no open side
across its axis joined to another such cell along it; labyrinth_test runs
it on every generated style and layer, level_test on every regenerating
level's template. Its own keys:
`"rooms": {"count": [lo, hi], "size": [[w, h], [w, h]]}` (least and most),
`"loops"` (extra ways as a share of the rooms and anchors, 0.2), `"chests"`
and `"crates"` (counts; chests on the blind ways' ends and room corners
first), and `"monsters"` as the maze (brutes in the great halls first). The
anchors and rooms are joined by a minimum spanning tree over their centres
plus the loops. Any key of the block beyond the four Level reads is the
generator's own and passed as written. `tools/plan_sheet.tscn` draws a
generation large, the anchors outlined (`--level=<name>` or
`--sample=dwarven|old|barrow`, `--generation=n`, `--out=<png>`).

The first real levels that regenerate are the barrow's three layers
(decision 580, Jeff's "crypt is still too cramped" and his answers on what
each holds; 542 and 541 amended before it), one place to the players, the
Barrow of the Fallen, three zones to the server, each laid again on its own
in the barrow style every 3 days, every way five cells clear and every room
8 x 7 or more (Jeff: "halls need to be at least 2 tiles wider than the
walls"; a wall draws 0.5 m thick and 3 m tall, and across the camera's view
hides about 2.5 cells behind it). The templates are written from
`tools/plan_sheet`'s samples (`sample_barrow`, `sample_barrow_deep`,
`sample_barrow_lair`), their twins.

- `levels/barrow`, "The Barrow", 80 x 60, `"layer": 1` (every room shallow:
  the town's newer tombs, square chambers with doors and torches): four
  anchors kept through every generation: the first hall under the mound's
  door (26 x 16: the link up to the wilds' "from_barrow", the spawn point
  "from_wilds", the burial table at its centre (art-kit's
  `building.burial_table`, 3 x 2, a solid doorless building; 580 step 3), seven
  niches a side cut into its east and west walls holding the town's dead
  (`"niches"` below: arches and hollows, a sealed slab now and then), a bay
  two rows tall each side where the ways come in (612), and the stair down to the Ossuary
  behind one of the niches: the hidden door (608). That niche's edge is a
  door spawned locked and stone (`Main.HIDDEN_LOCK`, a key nobody holds)
  with one alcove cell behind it holding the link to "from_above"
  (`"hidden": true`); the generator picks which niche each generation
  (`Labyrinth.niche_plan`, the one change it makes inside the anchor) and
  moves the link and "from_below" with it. A step into any niche presses
  on it (`World.niche_pressed`): "Only the dead lie here." once a stand,
  but the true one gives ("The slab swings aside: a stair goes down into
  the dark."), its lock lifted and the door opened for everyone in the
  zone until the level is laid again or the server restarts (door state is
  not in the snapshot: it is found anew); E at it presses too; a climb
  from below pushes it open from behind. The client draws the true niche
  as art-kit's `wall.crypt.cracked` till found and `wall.crypt.niche_open`
  after, by the Door's state). The clues to it (608 amended; Jeff: "foot
  prints, a draft, a text saying 'you feel a cool draft coming from one of
  the niches'") all read the one marker, the level's hidden niche
  (`World.hidden_niche()`: `{cell, edge, open}`, `{}` in a zone with none;
  the hall `Main.hall_rect(zone_name)`, the "entrance" anchor's rect): the
  line "You feel a cool draft coming from one of the niches." to a player
  alone the first time they step into the hall each generation while the
  door is shut (dungeon's; a restart says it again, as the door is found
  again), art-kit's footprints before it (terrain places them), a dust
  draft from the edge while shut (environment's), a whisper there (sound's),
  and a companion asked to search the room walks near it (companions'),
  the altar room (18 x 14, the
  altar and its two skeleton guards), Pip's niche off its west side (the
  place `barrow/niche`, npc's), and the robbers' camp (10 x 8) with the
  Runner's pack. The robbers (4) are sent near the altar; no dead walk it,
  and the generated level.json lists no graves and no niches for it.
- `levels/barrow_deep`, "The Ossuary", 100 x 80, `"layer": 2` (the tombs
  by depth): the ancient dead the town moved down, walking home (14, a
  draft number Jeff tunes, spread a third to each depth band; decision 631;
  skeletons) through the galleries, the graves as before and the niches
  cut along the galleries' walls (608: shelves and columbarium cells, a
  hollow here and there, about one wall cell in six, rock behind each; no
  door among them). Two
  anchors: the stair foot at the top (the link back up to "from_below")
  and the stair room at the far side with the stair down (the link to the
  hall's "from_above", "from_below" beside it).
- `levels/barrow_lair`, "Hall of Fallen Souls", 100 x 80, `"layer": 3`
  (every room deep: caverns, crooked ways, no doors, no torches; `"damp":
  true` and `"ambient"` 0.03: no flame burns well there and the dark is
  near total, environment's sim and terrain's look): the oldest
  dead (6 skeletons) and, kept whole as the anchor `lair` (548's room he
  keeps), the hall itself, 32 x 22, walled all round but for one door cell
  in its north wall: six pillars 2 x 2 in two rows (art-kit's
  `building.crypt_pillar`, solid doorless buildings; 580 step 3), the
  round table at its middle (`building.round_table`, 3 x 3, solid) with
  eight chairs round it (`building.hall_chair`, walked onto, `Level.OPEN_AIR`,
  so a ghost sits and a player passes) and four broken tables along the
  east and west walls (`building.broken_table`, 2 x 1 turned along the
  wall, solid), the dais 12 x 4 at the far end one height level
  up (the template's height.png; its front row twelve stairs, its sides
  ledges, its back against the south wall) with the draugr on his throne
  (`building.throne`, walked onto, at his cell facing the hall), and the
  hidden exit behind the throne, the temple's sealed shortcut's end (540,
  `draugr`, the spawn point "from_temple"); its one door, in the north wall,
  shuts and locks behind the first player in while he sits (573 amended,
  Jeff's puzzle: `Main._hold_hall_door` on the draugr's `hall_door` signal,
  `World.hold_door` with a lock nobody holds, stone; his gold, his death or
  one's own are the ways out; the sealed shortcut stays the blessed's way). The level's `"stills":
  ["barrow_deep", "barrow"]` names the zones whose dead he stills when laid
  to rest, and its `"dead"` key how the oldest dead differ (bold, seeing the
  living in the dark, lying in no grave): enemy-ai's.

Each layer's level.json carries `"depth"` (1, 2, 3 going down; the surface
is 0): maps' zone-transition cues draw a link to a deeper level as a stair
down and to a shallower one as a stair up from it. The block's `"layer"` and `"ways"` (3 or 5, an odd width) are the barrow
style's own keys (`sim/level_gen/labyrinth.gd`): the brush of 541 amended
reaches two cells each side for five, carved ring by ring so a cell is
only carved beside one already floor nearer in (a wider brush once left
cells cut off behind a tomb's ring). The wilds hold the mound's door and
the shortcut's other end (maps' side of 542; the shortcut's `to_map` is
`barrow_lair`).
The halls under the castle (613, dungeon's side; Jeff: the smith sought a
great dwarven forge deep below, his hired guards were ambushed, and he is
held there forging goblin weapons): `levels/castle_halls`, "The Dwarven
Halls", 90 x 70, `"depth": 1`, the labyrinth's dwarven style with `"ways":
5` (the brush of 541 amended carves its ways too when a level names the
width; unsaid, a dwarven level's ways stay two wide) and its great halls'
pillars as blocks two cells square five apart, two in from every wall
(612), laid again every 3 days. The way in is a stair in the castle's south
gatehouse: a 3 x 3 guardroom off the gate passage's west jamb (maps' side:
floor x 11..13, rows 17..19, its door onto the gate's way), the link at
(11, 18) to "from_castle", the castle's spawn "from_halls" at (12, 18)
beside it. Three anchors are kept through every generation: the stair
foot (10 x 8 at the top: the link up, the spawn, the start, two torches;
the anchor depth is counted from), the ambush a third of the way down
(14 x 10, walled north and south, where the smith's guards fell: his cart
and two crates as markers, and three of the guards where they fell, decor
`"fallen_guard"` with a facing, 613 amended: one on his side toward the
cart, one face down running north, one as he fell), and the great forge at
the deepest point (20 x 14, walled but for its north side): the forge 6 x 3
against its south wall (`building.dwarven_forge`, solid and doorless,
facing north into the room, the anvils along its front), the goblins'
weapon rack against the south wall east of it (`building.weapon_rack`,
2 x 1, solid: no fight stands a body in the blades), four pillars 2 x 2 in
two rows (art-kit's `building.crypt_pillar` `"variant": 2`, the dwarven
band), a chest in each back corner, torches, and between the forge's
anvils the place
`dwarven_forge` (`"kind": "refuge"`, `"where": "castle_dungeon"`, radius 3;
maps' kind and where, economy's 613): the sought smith is held there,
npc's body at its nearest free cell when a player is near, and the
goblins' band (rules' `sought.guards.castle_dungeon`, 3 imps and a brute)
stands at it while he is held (enemy-ai's side, kept to the room). Regen
keeps the place through every generation (`generated_config` keeps places
inside anchors). The halls' own goblins are the block's `"monsters"`
(5 imps wandering the ways, a brute holding a post; enemy-ai's first
count), `"chests": 3` in the alcoves beside the forge's two, the chests'
loot the default table until economy's `dwarven_hoard` row. The halls are
open from day one, smith or no smith: the forge is a place to find. The
plan sheet draws it as the barrow's (`--level=castle_halls`);
`tools/plan_sheet`'s `sample_castle_halls` is the template's twin, and the
template is written from it, as the barrow's are.

Levels regenerate only on a server started with `--regenerate` (as raid
groups with `--raids`, decision 328) or after the console's `regenerate on`
(`regenerate` alone lists the marked levels and their generations); the
box's service runs with it. `regenerate now <level>` (541 amended) lays a
marked level again at once, due or not, the switch on or off, so long as
nobody is in it (it says so otherwise): release runs it after a deploy
that changes a template, players checked first, so Jeff meets the new
shape at the deploy rather than at the next due day. Off, and in any test run (tests/run.sh passes
`--run-marker`) on the shared overlay, nothing is laid (`Regen.may_write`):
the barrow stays its template, its anchors in the rock. A test that wants
generations switches `Net.regenerate` on and points `Level.overlay_dir` at
its own scratch folder, as regen_test does.

The barrow's level.json sets `"grave_goods": true` (decision 555, items'
grave goods for the companions' loyalty): everything a chest keeps or one
of the dead carries and drops there is minted as grave goods, the altar,
the generated chests, the skeletons, the robbers and the draugr alike; the
generated level.json keeps the key (`Regen.generated_config` passes any
top-level key through). The Runner's pack, a robber's own, is exempt by
its entry's props `"grave": false`. The Ossuary's and the Hall's generated
chests roll their goods from `levels/loot.json` (`"loot": {"chest": ...}`
in the template, kept by the generated level.json): `ossuary_grave` (a
mail shirt in one chest in four, a dagger) and `fallen_grave` (plate in one
in twenty, mail in one in four, a sword), the only loot that gives armour
(622, dungeon's side: mail and plate enter the world as grave goods;
Snagfin fences them, economy's). The first layer's chests roll nothing.

A generated level.json also carries (decision 542 amended) `"graves":
[[x, y, band], ...]`, one per dead-end floor cell outside the anchors (the
tomb niches and the blind ways' ends), none with a chest on it, the band 0,
1 or 2 by its depth from the `"entrance"` anchor (`Regen.BANDS`, the barrow
style's own bands), so enemy-ai's walking skeletons are each given a grave
in a shallower band to go home to; and `"niches": [[x, y, dx, dy, kind,
variant], ...]` (608; 542 amended's alcove cells before), the burial niches
cut into wall edges: `(x, y)` the room's floor cell before one, `(dx, dy)` the
step onto its wall (a wall edge with rock behind it; for kind `"hidden"` a
door edge with its alcove, a floor cell, behind), `kind` `"a"` (arches),
`"b"` (shelves), `"c"` (hollows), `"d"` (columbarium cells) or `"hidden"`
(the first hall's hidden door), `variant` 1 (open) or 2 (sealed, slabbed or
full). `Level.niches_from` reads them into terrain `"niches"` as `[{cell,
out, edge, kind, variant}]` (`out` the step out of the wall into the room,
`edge` the Terrain edge key) for terrain's draw (art-kit's
`wall.crypt.niche_<kind>` on the edge, +x toward the cell) and
`World.niche_edges`; a bad one is said and left out. The first hall's 14 are
the template's (`tools/plan_sheet.barrow_niches`), re-rolled each generation;
the Ossuary's are generated (`Regen.niches_of`); the dark below has none. The
barrow's template holds
enemy-ai's kinds by the level's own `"legend"` colours (skeleton, robber,
three skeleton guards in the altar room, the draugr in his lair), Pip's niche
(a 2 x 2 anchor off the altar room with the place `barrow/niche`) and the
runner's pack (a chest in the lair's corner), npc's.

Decor (decision 647, moss and webs; Jeff: "moss and spiderwebs for decor, no
live plants"; 658, the kinds and how each sits): `"decor": [[x, y, dx, dy,
kind, variant], ...]`, the niches' shape, one entry a piece of art-kit's
`prop.<kind>`, drawn and never solid, never on the wire's meaning (a client
without the slot skips it). `Level.DECOR_KINDS` says how each kind sits on
its floor cell `(x, y)` and how many variants it has: `flat` on the cell,
`(dx, dy)` `(0, 0)` for a yaw rolled by the cell (`"moss_patch"`, 3), or a
side for the way the piece's front turns when the kind is faced
(`"fallen_guard"`, 2, either); `wall` along the wall edge the step names,
rock behind it (`"moss_strip"`, 2); `edge` on any edge of the cell the step
names, wall, open or a fence's, indoors or out of doors, seen from the cell
(`"grave_fence"`, 3: maps' fence round the pauper's graves on Held, 654; its
one post stands at the piece's +z end, so a run is laid from one side and
neighbours share the post); `corner` in the cell's corner the diagonal names
(both its walls wall edges: `"web_corner"`, 2); `niche` across the mouth of
the open burial niche (kind `"a"` or `"c"`, variant 1: never the hidden one,
never a sealed slab) whose cell and step those are (`"web_niche"`, 2).
`Level.decor_from` reads them into terrain `"decor"` as `[{cell, out, edge,
kind, variant}]` (`out` the step as given; `edge` the Terrain edge key, a
wall, edge and niche piece's) for terrain's draw (`Client3D._add_decor`: a
flat piece on its cell, turned by the roll or its facing; an edge-borne one
at the edge's midpoint, +x toward the cell, z along the edge); one on no
floor, misfit to its kind or place, or doubling another is said and left
out. The
templates hold a few by hand (`tools/plan_sheet.BARROW_DECOR`: webs in the
first hall's corners by the way in and a strip of moss at its south wall;
`LAIR_DECOR`: the damp hall's moss along its walls and floor and its four
cobwebbed corners), kept by every generation; the rest `Regen.decor_of`
rolls by the generation's seed over the floor outside the anchors, never a
cell the ways run through (the generator's record, `LevelMap.extras`
`"paths"`), a link's, a marker's or a spawn point's: moss strips on a share
of the wall feet by the level's damp (`"damp": true` 0.35, the Ossuary
0.15, the first hall 0.05, half as much again in the deep band), moss
patches on open floor at 0.4 of that, webs in 0.3 of the corners and across
0.25 of the open niches (the first hall's included, since they are
re-rolled; a template's own niche web is dropped for the same reason). The
generator lays no plant anywhere; the decor is stone-grown.

What the draugr gives (decision 573, Jeff's resurrection charges; 544's
blessing before it): laid to rest in a pact, he blesses every player standing
alive in his lair and their companion in the zone (the mark `draugr`, 540,
for good: the sealed shortcut opens, the temple's offering is waived, 546)
and gives each player the deal's charges, 5, 10 or 15 by the gold given
(economy's `return.field` deals: 20, 50, 100), up to what they can hold (25,
50, 75 by the hardest deal they ever won; `PlayerRecord.barrow` {tokens,
best, containers}, economy's arithmetic). A charge brings a blessed body
back where it fell (544's channel), one off the resurrector's own count; a
charge is a count on the record, no item, nothing trades it (the device's
halves of 544 are keepsakes now). The player carries the count and the room
on the wire (`Player.charges`, `charge_room`; protocol 30). The draugr's
level rises by the charges the players in the zone hold when a pact begins
(`Main.charges_in_zone`), and a player coming into the zone during a pact
heals him (`Draugr.living_came`, enemy-ai's), so the halls never scale, only
he does, and spending charges makes the next pact easier.

When it shifts: on the slow world tick (every `World.WORLD_TICK_STEPS`), a
level whose `every_days` have gone by since its last generation is laid
again, only while its zone is asleep (nobody in it, nobody dead there
waiting to respawn); a level that is due when someone travels into it is
laid again first, before they arrive; never under anyone's feet. The
generation count lives in the snapshot (`"regen": {area: {generation,
at_step}}`).

What stays: the anchors, and in them every saved entity, respawn timer,
monster record and floor pile, matched by its marker cell (the cells are
the same, so the keys of decision 433 still mean the same markers): a
chest in the gatehouse keeps what was put in it. What goes: everything
outside, laid fresh from the new markers; things lying on the floor out
there are gone, their ItemBook history ending "lost in the shifting
halls"; places outside the anchors leave the holdings and every player's
map. The generated level is registered in memory and written to the
server's level overlay (`Level.overlay_dir`), so `Level.overlaid` is true
and clients are sent its "terrain" message on entry; the "map" message
says `"generation"`. A level that is in the overlay without the mark (one
edited in builder mode) is never written over. Coming back at a newer
generation than the one you last saw says "The ways have shifted since you
were last here."; a first visit says nothing. A player (or a companion
left waiting) whose saved cell is rock now comes back at the nearest
anchor's spawn point, else the nearest floor, their companion beside them.

The castle and the tower are never marked: they are the consistent
overworld, and the entrance markers; the halls below and the tower's
inside are levels of their own, linked from them, the link's cell an
anchor on the shifting side. No real level is marked yet (tests make
their own in code: `tests/regen_test`).

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
- an area that cannot be reached from the start zone (else the default
  map), or has no way back to it;
- a start zone that is not a level, or has no starts of its own;
- the level's own load warnings (a link off its marker, a marker with no
  link).

`godot --headless --path . --scene res://tools/check_world.tscn` prints the
list (exit code 1 if there is anything on it).

### What lies past a border

`WorldMap.ways_out(area, gap)` (decision 325) gives each way out of an area
with where its target lies against it, for drawing what is beyond a border:
`kind` (link or edge), `to_map`, a link's `from_cell` (our marker) and
`to_cell` (where it arrives: its spawn point, else the target's first start),
an edge's `side`, `out` (the direction away from our land), `to_ours` (a
`Transform2D` taking the target's cells into ours) and `one_way`. A
neighbour abuts exactly as `arrival()` puts a crossing (the same row or
column); a link's target faces us by the edge its arrival is nearest, that
edge `gap` cells past where our land ends going out from the marker (not
the map's edge), the arrival across from our marker. It reads
cells, not the levels' `"north"`, as `arrival()` does, so what is shown and
where a crossing lands cannot disagree.

### The start zone

Where a new player begins is data, not a server flag (decision 300):
`levels/world_map.json` names the zone,

```json
{ "start": { "zone": "wilds" } }
```

and the players appear on that level's `start` cells (its `"starts"`).
`Main.default_zone()` takes `--map` first (tests, a host trying a level),
then this, then `Level.DEFAULT_MAP` (`test_room`) when neither names a
level. A player with a record goes back to their own zone wherever it is.
The world map is measured from the start zone (`WorldMap.root()`): what it
cannot reach, or what has no way back to it, is flagged, and so is a start
zone with no `start` cells (Level would stand its first floor cell in). The
world map view (`--world-map`) lays out from it and marks its box
", start".

### Places and who holds them

A place (level.json `places`) is a cell and a radius in an area that a
faction holds. The factions are in `levels/factions.json` (the Blood Rot,
key `goblins`; the orcs and kobolds allied to it; the town): a name, a
colour, the monster kinds acting for each (the one place a kind's faction
is said), who each is hostile to, `lore_id` (its entry in levels/lore), and
`allied_to`, the faction it is allied to (decision 416). An ally is on its
lead's side, one level deep: it takes on the lead's enemies, walks its and
the other allies' ground, and their raid groups draw on its kinds. "nobody"
holds what no faction does. Held ground is the cells within a held place's
radius (a disc); ground two factions' places both cover is contested (two
of one side's is the lead's); a place nobody holds is open ground and counts for no
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

A placed `building.temple` or `building.healers_hut` makes a place of its
own, kind `temple` or `healers_hut`, on the cell outside the middle of its
front (`Level.building_places`, decision 372): where the fallen come back.
It is keyed `<kind>@x,y`, held by nobody and worth nothing, so it holds no
ground (a temple in town stands on the town's ground by the stockpile's
radius; a hut out in the wilds is neutral), and it moves or goes with the
building, so nothing in `places` is written for it.
`Holdings.nearest(kinds, area, cell, routes)` is the nearest place of
those kinds by walking steps (on the server, `World.raid_groups.routes`).

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

### Raid groups

A place of kind `camp` that a faction holds sends raid groups at the towns
of factions hostile to it (decision 328): a group walks the world routes on
its faction's layer on the world tick, raids a town nobody watches by the
numbers (economy's `Towns.raid_arrives`), carries food and captives home,
and in a zone with a player in it becomes real raiders (enemy-ai's
`World.raids`). The camps also make each town's threat. A camp's `worth`
is its size: bigger camps threaten more and send stronger groups. Raids are
off until the console's `raids on` (or `--raids`); `raids` lists the groups,
`raids send <camp> <town>` sends one now. Camps are content: none is in a
real level until Jeff asks.

### Trade routes

Each town has a trade route to each market and to each other town that can
be walked (decision 504, `TradeRoutes`): the world routes' open layer, a
closed link no way. Economy sends caravans over them (its goods, the
residents who go); they walk on the world tick and arrive, and where the
way crosses ground nobody holds within `raid_reach` (30) cells of a camp
hostile to the town, that camp may strike as it passes, taking food and
people only. The world map draws each route through known areas as a
dashed brass way, a dot for each caravan.

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
- **The properties panel** (decision 506): with the select tool (`V`),
  a click on a thing shows its fields in the panel, and a second click on
  the same cell the next thing there: a link (its level, where it arrives,
  one way, closed), a crate, cart or chest (its name, what is in it), a
  start (its order), a spawn point (its name), a place (name, kind, holder,
  radius, worth), a market (its name, and its cell, picked on the map), a
  building (facing, use, town; a bridge's length and width), a stream (its
  course; reverse it, take it out) or a regenerate anchor (its name, its
  rect picked by two corners). With nothing selected (`Esc`) it shows the
  level's own fields (name, outdoor, zone, region, border, north, light,
  sets, canopy, neighbours, the regenerate block) and "add a market". A
  value that cannot be (a level there is not, a spawn point it has not, a
  faction or item there is not, out of range) is refused and the status
  says why; what is written is one undo step, then the level goes through
  the game's loader and the world map's checks, and what they say of the
  thing shows in the panel (red for what the game would leave out).
  Renaming a spawn point that other levels' links arrive at asks first,
  naming them, and changes and saves them too. The table of kinds and
  fields is `editor/editor_fields.gd`: a new `level.json` key is a row.
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
- **Copy and paste** (decision 516): with an area dragged out, `Ctrl+C`
  copies it (cells, edges, heights, entities, links, places, buildings,
  roofs, spawn points, starts, markets, and the streams wholly in it) to the
  editor's clipboard, and `Ctrl+X` copies it and clears it to void. `Ctrl+V`
  picks the stamp tool holding the clipboard: `R` turns it, each click lays
  it, one undo step each (a spawn point, place or market whose name is taken
  becomes `_2`, `_3`...), until `Esc`. The clipboard lasts the editor
  session; it is not saved.
- **Climbs checked as you go** (decision 516): with the heights shown, a
  stair or slope the game would leave as floor (no cell one level up beside
  it) or that could climb more than one way is tinted red, and the height and
  stairs panels list it. The stairs tool lays stairs or slopes (its panel).
- **The ground in metres** (decision 525): the height panel's "ground in
  metres" gives the map relief (relief.png) from its heights, one undo
  step; from then on the height tool is a brush in metres: LMB raises the
  cells under it (by the strength at its middle, less to its edge), RMB
  lowers, "smooth" pulls each toward the cells round it, "flatten" (or
  Shift) sets the picked height, Alt+click picks one. The heights view
  shades the ground by height, writes its metres when zoomed in, and draws
  every step steeper than a walk (a cliff) red; the panel counts them. The
  area panel's **relief** fill lays hills over the area (`Relief.lay`, its
  streams added to level.json), and **pad** levels it for a building. A
  resize carries the relief, a new side taking its neighbour's height.
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
- **Height** (`H`, decision 357): a click raises the cells under the
  brush a level, a drag every cell it passes (each once a stroke); a right
  click lowers them; `Shift`+click sets them to the picked level, `Alt`+click
  picks a cell's level. `[` and `]` size the brush (1, 3, 5 or 9 across).
  Levels run 0 to 6; void cells have none.
- **Stairs** (`S`): press on the low cell and drag the way it climbs. One
  cell makes a stair, its high side raised a level if it isn't and the edge
  between opened; a longer drag makes a flight, a level a cell. If it can't
  (the top level, void beyond), the status line says why.
- With an area dragged out, the area panel's **Heights** row raises,
  lowers or levels it (at the picked level), or makes a stepped hill in it,
  its top the picked level.
- While Height or Stairs is picked (`Ctrl`+`H` for every tool), each cell is
  tinted by its level (darker at 0, lighter each level up) with the level
  written on it, cliffs are drawn heavier the higher they are, and each
  stair shows the way it climbs (a red dot: it climbs nowhere and plays as
  floor). The status line says the hovered cell's level.

  These changes are `HeightTools`' (`editor/height_tools.gd`), the same
  ones builder mode lays.

Saving writes the same double-resolution `layout.png` (the file's own size
kept), its `.import` set to Image, and reports what the server would warn
about. `level.json` is written when something in it changed (a monster's
facing or idling, a resize); `height.png` when a height changed. Run from the
project, the game reads `layout.png` itself rather than its import, so a
saved map plays at once with `--map=<name>`.

Not yet: a 3D preview, and fences that look like fences (a
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

Its landmarks (Jeff: "wilds needs better land marks") are laid over the
touched-up map a layer at a time by `tools/make_wilds_marks.tscn`, which
writes only what its layer owns. The relief (565): `relief.png`, laid by
`Relief.lay`: a roll of 1.5 m either way, a ridge across the north-east
from (140, 30) to (215, 70) whose 3.5 m escarpment face looks south-west
over the middle, its long back rising from the north-east, a way up it
45% along; a valley from the north edge at (62, 0) down to the south at
(118, 255), about 3 m under its flanks; each pond level 0.3 m under its
lowest shore. The town, every link, spawn point, start and building, and
the camp's gathering point stand on level pads. Every cell keeps its kind.
The marks (567), placed once into `level.json`'s `buildings` (its text kept
as it was) and padded like any building: a great tree at (44, 132), a
cairn on the ridge's back at (184, 40), a waystone where the roads will meet
at (128, 128), a ring of eight standing stones round (70, 202), each in open
ground (no forest or water within a few cells), the ring one pad.
The water (568): a river laid as a curve down the valley from the north
edge to the south (wavelength 34, swinging 7 cells, 2 to 3.2 wide, on a
floor 11 either side), the groves under it cleared (the forest round the
land kept: it runs on unseen under it at the edges), a ford across it at
row 41 and a bridge at row 128 where the hills road will cross; and the
three ponds traced from their cells into closed curves (`Curves.trace`),
their cells then the curve's. `level.json` gains `waters` and the bridge.
The roads (569): three dirt roads laid as curves (`Relief.road`, swinging up
to 7 cells either side over turns of about 48) from the castle's, the
hills' and the forest's spawn points to the crossroads round the waystone,
the hills road over the bridge; their grass cells bare dirt; `level.json`
gains `roads`. The south-east road to the mound and Held waits for Held.

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

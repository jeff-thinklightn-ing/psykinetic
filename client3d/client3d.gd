class_name Client3D
extends Node3D
## The 3D view of the game. Instanced by Main under the same tree as the 2D
## view unless the client runs with renderer 2d (see Net.renderer), so all the net code, the
## entity specs, the settings file and the map data are the ones the 2D
## client uses; the 2D nodes are simply hidden and go on being the
## replicated state. One tile is one unit: grid (x, y) is 3D (x, 0, y). The
## sim is the physics: there are no physics bodies here, only meshes and,
## for picking, Area3Ds.
##
## The room is built once from the parsed map (Terrain): the ground
## (_build_ground), and on it the art slots (ArtKit, art/kit/slots.json),
## each at its real size: a wall.castle.straight per wall edge, centred on the
## boundary line; a wall.castle.post at every vertex where walls meet at an angle
## or end; a door.single for a door, its leaf hinged at the edge's start
## end, turning with the Door node. Fire is an emissive quad with a small
## light. Flat-colour boxes in the kit's stone (_box, _stone) stay
## available for interior walls later (BOX_WALLS).
##
## Near and far: a wall, doorway, post or tree that hides the local player
## or their companion from the camera (a line from it to their feet,
## middle or head passes through it) is near and drawn at NEAR_ALPHA, so
## they show through it, with the rest of its run; the rest are opaque.
## Recomputed whenever the camera or they move; a piece stays near a
## moment after it stops hiding them (_update_fade).
##
## Entities get a puppet each: a primitive at the scale table's size,
## coloured as the 2D sprite is, with a Label3D name on creatures, a warm-white light on players and companions, and an Area3D
## of the same shape for picking. Puppets follow the 2D nodes every frame,
## so they move as those do: at a steady speed along the walk. A creature
## has a nose that turns with its shown facing, and lunges when it swings.
## Speech is a bubble on the HUD (SpeechBubbles), placed through
## bubble_anchor and tile_px.
##
## Camera: orthographic, tilted `pitch` from horizontal (CAMERA_PITCH at
## rest), yawed by `yaw` about the local player, who is kept at the middle
## of the screen: 0 matches the 2D diamond (+x down-right, +y down-left).
## The ortho size is CAMERA_SIZE times `zoom`, and times up to
## PEEK_PULL_BACK during a WASD pitch peek. The mouse wheel zooms in either
## scheme, a ZOOM_STEP a notch between ZOOM_MIN and ZOOM_MAX, eased
## (ZOOM_RATE), on the player. The zoom is saved (Net.camera_zoom). Click
## scheme: a middle drag pans, sliding the view off the player (`pan`,
## PAN_MAX at most) so the ground under the cursor stays under it; let go,
## it eases back onto the player.
##
## Turning, in both schemes: the yaw turns freely, all the way round, and
## rests only on the diamond views (multiples of ORBIT_STEP from 0). Let
## go, it settles on the next diamond the way it was turning, or back on
## the one it set off from if it turned less than TURN_COMMIT
## (settle_target), and stays there; that diamond is saved in settings.cfg
## (Net.camera_yaw). Click scheme: A/D turn at TURN_RATE while held, and
## the settle starts at that speed so the release flows into it; W/S tilt
## while held at TILT_RATE, between PITCH_MIN and PITCH_MAX, slowing into
## either end, and spring back to CAMERA_PITCH over TILT_RETURN_SECONDS.
## WASD scheme: a sideways middle drag turns, its settle eased out over
## SETTLE_SECONDS; a vertical one is a pitch peek, tilting toward
## PEEK_PITCH in proportion to the drag (full over PEEK_DRAG_PX, eased) and
## springing back over PEEK_RETURN_SECONDS. The near/far rule reads only
## the yaw, so the near walls stay see-through through any tilt.
## While a movement key is held (frozen, set by Main) the yaw does not
## move at all; a drag meanwhile applies when the keys are let go. It
## follows the player; in WASD it leans toward the cursor as the 2D camera
## does (Main.camera_lean).
##
## Combat reads off the puppets. A creature with hp has an HP bar over it
## (hp_bar.gdshader: billboarded, over everything, HP_BAR_PER_HP wide per
## hp of its max, green, amber below HP_AMBER, red below HP_RED), shown
## while it is hurt or has been in a fight in the last COMBAT_SECONDS, or
## while Alt is held (show_all_bars, set by Main), and faded in and out;
## hp_bars=0 in settings.cfg turns them off. A death (on_death, from the
## server's "death" message) makes a corpse of the puppet: it tips onto its
## side over FALL_SECONDS with a little bounce, flashes, drops its lantern,
## lies CORPSE_SECONDS, then sinks over SINK_SECONDS. A companion says a
## last line; the local player's own death pulls the camera back and
## drains the colour until they are back. Sounds (Sfx) play on the
## server's events only: swings, blows by cause, impacts by what was hit,
## deaths by kind, doors opening and closing, and footsteps as tiles
## change, from where they happen; the listener is on the player, not the
## far-off camera.
##
## Picking is by ray from the camera through the cursor: an entity or door
## Area3D first, else the floor plane, which Main snaps to the nearest
## walkable cell. The hover is a square outline of the cell, the click
## ripple a ring, the toss aim an arrow, all flat on the floor. All input
## is Main's; this view only answers its picks and draws what it is told.

## A burning and a bleeding body's name (decision 375).
const AIL_BURN := Color(1.0, 0.6, 0.25)
const AIL_BLEED := Color(0.95, 0.3, 0.3)
const WALL_HEIGHT := 3.0
## A kind's roof set (decision 488): shingle, Jeff's pick (art-gen's c6),
## unless its kind names another ("roof_set" in levels/buildings.json) that
## art-kit has a material.roof.<set> for, as thatch once it reads as thatch.
const KIND_ROOF := "shingle"
## How much of a ruin's walls stand broken (decision 489).
const RUIN_BROKEN := 0.45
## A window's wall may differ from a storey this much (it is stretched to
## it); how many windows stand with their shutters open (489 amended).
const WINDOW_STRETCH := 0.6
## A kind's wood walls stand on a stone footing (decision 489 amended, the
## plinth): this tall over its pad, this much proud of the wood each side.
const PLINTH_HEIGHT := 0.6
const PLINTH_PROUD := 0.05
const SHUTTERS_OPEN := 0.66
## A window lit by the hour goes out at this hour, the sun down; how often
## the window lights are looked at, seconds (decision 566).
const LAMP_OUT := 22.0
const LAMP_CHECK := 2.0
## Wall runs (_add_wall_runs), each in its set's profile and variation
## (_wall_set: art-kit's wall.<set>.profile, decision 287): at most this
## many edges a mesh; a height every WALL_SWAY edges, the body up to the
## set's sway of cap_y either way; an edge's top broken off as often as
## the set's broken (WALL_BROKEN_LOW to _HIGH of cap_y, over
## WALL_BROKEN_STEPS steps); a breach of rubble as often as its gap in a
## run of WALL_GAP_RUN edges or more (WALL_RUBBLE_LOW to _HIGH tall,
## WALL_RUBBLE_SPREAD wider than the wall each side); its stone's texture
## this many metres a tile.
const WALL_RUN_MOST := 16
const WALL_SWAY := 3
const WALL_BROKEN_LOW := 0.45
const WALL_BROKEN_HIGH := 0.8
const WALL_BROKEN_STEPS := 4
const WALL_GAP_RUN := 6
const WALL_RUBBLE_LOW := 0.9
const WALL_RUBBLE_HIGH := 1.15
const WALL_RUBBLE_SPREAD := 0.1
const WALL_TILE := 2.0
## The set a map's walls and floors are in when level.json names none, or
## names one art-kit has not (decision 285).
const DEFAULT_SET := "castle"
## Each set's wall stone until material.wall.<set> has a texture: a palette
## swatch, and its courses (_stone_courses): rows a tile, and the blocks'
## shortest and longest, as a share of the tile (wood's are planks).
const WALL_LOOKS := {
	"castle": [Vector2i(0, 1), 5, 0.3, 0.55],
	"wood": [Vector2i(2, 3), 12, 0.7, 1.0],
	"stone": [Vector2i(1, 2), 4, 0.35, 0.6],
	"cave": [Vector2i(1, 5), 3, 0.5, 0.9],
}
## The floor sets the ground draws (ground.gdshader's floors texture, a
## byte a cell: 0 the ground's own look), and their colours: swatches.
const FLOOR_SETS := {"castle": 0, "wood": 1, "stone": 2, "cave": 3}
const FLOOR_SWATCHES := {"wood": Vector2i(2, 2), "stone": Vector2i(1, 2), "cave": Vector2i(1, 5)}
## What an edge of a run is drawn as.
## (WALL_PIECE: an art-kit piece in its place, wall.<set>.straight_ruined
## or .rubble, when the set has its art.)
enum { WALL_WHOLE, WALL_TOPLESS, WALL_RUBBLE, WALL_PIECE }
## One height level (height.png) in units; a stair is a ramp up one.
const LEVEL_RISE := 0.5
## Cliffs: rock's colour (sRGB), a row of facets this tall at most, this
## many facets along a cell's edge, points pushed about this far.
## The cliffs' rock: a palette swatch (row, column).
const CLIFF_ROCK := Vector2i(1, 5)
const CLIFF_ROW := 0.2
const CLIFF_ACROSS := 4
const CLIFF_JITTER := 0.07
## The cave set's walls (decision 286): rock, not a swept profile. A run is
## faceted as the cliffs are, CAVE_ALONG facets a metre along and CAVE_ROWS
## up; its thickness at the foot is the profile's times CAVE_THICK_LOW to
## _HIGH (0.6 to 0.9 m), its top CAVE_TOP_LOW to _HIGH along it, a ragged
## ridge CAVE_RIDGE above, its faces pushed up to CAVE_BUMP; nothing past
## CAVE_REACH from the edge's line, into a walkable cell. A post where the
## set has no art is a lump of the same rock, CAVE_LUMP_SIDES round.
const CAVE_SET := "cave"
const CAVE_ALONG := 4
const CAVE_ROWS := 8
const CAVE_THICK_LOW := 0.75
const CAVE_THICK_HIGH := 1.12
const CAVE_TOP_LOW := 2.4
const CAVE_TOP_HIGH := 3.4
const CAVE_RIDGE := 0.15
const CAVE_BUMP := 0.1
const CAVE_REACH := 0.45
const CAVE_LUMP_SIDES := 8
## Each ground kind's colour: a swatch of art-kit's palette (row, column;
## docs/art_style.md), read from art/kit/palette.png, so a repainted swatch
## repaints the ground; and its channel in the ground's kinds texture
## (ground.gdshader). A kind not here is stone; sand is ready for a map
## that paints it.
const GROUND_SWATCHES := {"grass": Vector2i(4, 3), "dirt": Vector2i(3, 4), "stone": Vector2i(1, 3), "sand": Vector2i(3, 1)}
## art-kit's palette atlas, and its swatches as the style guide gives them.
const PALETTE_IMAGE := "res://art/kit/palette.png"
const PALETTE_FALLBACK: PackedStringArray = [
	"#f2c9a6", "#ebb48e", "#d49c78", "#b8845f", "#9a6c4c", "#7c573d", "#5f4330", "#433024",
	"#c9c7c0", "#b0aea6", "#97958d", "#8f8f8a", "#77766f", "#6b6660", "#545049", "#3b3834",
	"#b8946a", "#9e7c55", "#8a6a48", "#796145", "#6a523a", "#5e4c41", "#4a3a2c", "#3b2e24",
	"#d8c89a", "#c7b380", "#a88e5e", "#8c7148", "#755c38", "#5f4a2e", "#4a3a25", "#2c2418",
	"#a8bf6a", "#8fa857", "#7a8f4a", "#5d7742", "#4f6a35", "#36a340", "#2f5a2a", "#2c4224",
	"#c2b8a0", "#9c8f74", "#7a6e58", "#4c4a3b", "#6b4a35", "#55392a", "#3d2a1f", "#29231b",
	"#c7c9cc", "#a3a6ab", "#7d8086", "#55575c", "#3e4044", "#c79a55", "#a37d40", "#8a6a3a",
	"#ffd27a", "#ffb861", "#e8792e", "#b8322a", "#2f5aa8", "#7a4fb0", "#3fb8a8", "#f4efe6",
	"#f4efe6", "#8fb3b0", "#5f8a8c", "#46707a", "#2f4f5c", "#213a45", "#16272f", "#0d181d",
]
const GROUND_CHANNELS := {"grass": 0, "dirt": 1, "stone": 2, "sand": 3}
## Water (_build_water): its colours shallow and deep, its foam (swatches
## of art-kit's water row, 8); its surface this far above its level, its
## bed's middle this far below, the bed's ground (in the kinds texture,
## under the water's own tint).
const WATER_SHALLOW := Vector2i(8, 2)
const WATER_DEEP := Vector2i(8, 4)
const WATER_FOAM := Vector2i(8, 0)
const WATER_LIFT := 0.01
## (Above FOREST_FLOOR_DEPTH, or the forest floor under the map hides it.)
const WATER_BED_DEPTH := 0.15
## On a relief (decision 525), how far a ford's bed lies under its surface,
## and the water's edge under its surface where a bank meets it (a bank
## within Relief.WALK_RISE of the water slopes into it as grass, no face).
const FORD_DEPTH := 0.06
const SHORE_SINK := 0.02
## Hills read (decision 525 amended, terrain's side): how strongly a slope
## is lit by the relief light (ground.gdshader's slope_shade; tuned from the
## shots), how high that light stands (degrees), and the valley floors'
## darkening: a corner CONCAVITY_FULL metres under the ground round it
## (CONCAVITY_REACH cells away) takes CONCAVITY_MOST of the foot's shade.
const SLOPE_SHADE := 6.0
const HILLSHADE_HIGH := 40.0
const CONCAVITY_FULL := 1.5
const CONCAVITY_REACH := 2
const CONCAVITY_MOST := 0.5
## A crest: a corner standing over the ground round it catches the light,
## CREST_MOST of the ledge top's lift at CONCAVITY_FULL metres over.
const CREST_MOST := 1.0
const WATER_BED_KIND := "dirt"
## The water's edge unsquared (decision 553): the shore field (shore_image)
## has SHORE_RES texels a cell; a one-wide stream winds within its cells up
## to STREAM_WIND either side of their middles, STREAM_HALF wide each side
## of its line; the water's edge never strays further than SHORE_BOUND from
## the cells' true edge (the shader's warp, SHORE_WARP, inside it).
const SHORE_RES := 4
const STREAM_WIND := 0.2
const STREAM_HALF := 0.42
const SHORE_BOUND := 0.35
const SHORE_WARP := 0.1
## A stream's ribbon (decision 557, _build_ribbons): RIBBON_STEPS points a
## cell along it, RIBBON_UNDER of a cell past its water under the banks; a
## step down its path of more than FALL_LEAST metres is a fall.
const RIBBON_STEPS := 8
## The waters as curves (559, terrain's side, _read_curves): a cell's
## nearest sample kept out to CURVE_REACH past the curve's half width; a
## point's nearest point searched CURVE_SEARCH samples either side of it;
## a river's surface smoothed over CURVE_SMOOTH samples either side.
const CURVE_REACH := 2.5
const CURVE_SEARCH := 8
const CURVE_SMOOTH := 4
const RIBBON_UNDER := 0.3
## A fall this tall (m) or more hangs as a curtain from its lip to the
## water below (_build_curve_ribbon), in CURTAIN_ROWS rows bowed out down
## the stream; a shorter one is a white slope.
const FALL_TALL := 1.0
const CURTAIN_ROWS := 4
## Mist at a tall fall's foot (570 amended, terrain's side, _build_mists):
## at most MIST_PUFFS soft puffs a fall, drifting up and down the stream
## from the churn, each MIST_SIZE across, lasting MIST_SECONDS; a fall
## MIST_FULL tall or more has them all, a shorter one fewer.
const MIST_PUFFS := 24
## The forest's edge as curves (decision 575, _read_edges): the outline of
## the cells the forest grows round, simplified within EDGE_SIMPLIFY
## (a staircase's run a line), each point moved up to EDGE_WOBBLE across
## it by a slow noise, so the curve keeps within EDGE_BOUND of the cells'
## edge: no walkable cell looks forest, no forest cell open.
const EDGE_SIMPLIFY := 0.3
const EDGE_WOBBLE := 0.14
const EDGE_BOUND := 0.45
## The trees along it (_add_edge_trees): one every EDGE_SPACING (a range)
## along the curve, EDGE_DEPTH (a range) into the forest, the nearest
## thinned to EDGE_NEAR_KEEP of them.
const EDGE_SPACING := Vector2(0.7, 1.1)
const EDGE_DEPTH := Vector2(0.3, 1.4)
const EDGE_NEAR_KEEP := 0.75
## Roots on the land within this of the edge (the scatter, 575).
const EDGE_ROOTS := 0.7
const MIST_SIZE := 1.1
const MIST_SECONDS := 2.6
const MIST_FULL := 6.0
## The hidden niche's draft (608 amended, environment's side; Jeff: "you
## feel a cool draft coming from one of the niches"): DRAFT_PUFFS puffs
## DRAFT_SIZE across, at most DRAFT_ALPHA opaque, from the cracked wall's
## foot, DRAFT_LOW high at most, drifting DRAFT_SPEED (m/s, a range) into
## the room and fading over DRAFT_SECONDS: about a cell and a half. Lit as
## the scene is, so in the barrow's dark only a light held near shows it;
## noticeable then, not subtle (0.7 across at 0.18 until 608 amended (2)
## read as nothing in a still).
const DRAFT_PUFFS := 7
const DRAFT_SIZE := 0.9
const DRAFT_ALPHA := 0.35
const DRAFT_LOW := 0.45
const DRAFT_SPEED := Vector2(0.22, 0.34)
const DRAFT_SECONDS := 4.0
const FALL_LEAST := 0.25
## A bridge's pieces stand this far over the banks' height, so the water
## drawn under (WATER_LIFT up) never shows through the deck.
const BRIDGE_LIFT := 0.04
## art-kit's bridge pieces (decision 505): a deck a cell, a rail along each
## outer long edge, an end onto each bank.
const BRIDGE_DECK := "bridge.wood.deck"
const BRIDGE_RAIL := "bridge.wood.rail"
const BRIDGE_END := "bridge.wood.end"
## Rocks (decision 513, terrain's side): art-kit's rock.large over each 2x2
## clump of rock cells, rock.small on every other one; each turned, sized
## and sunk by its cell (sizes and sinks: these ranges).
## The barrow's niches as wall edges (608, terrain's side): a niche of
## kind k is art-kit's wall.crypt.niche_<k> in its wall run; the hidden one,
## a door edge, wall.crypt.cracked while shut and wall.crypt.niche_open once
## found. Each piece 0.5 m thick on its edge, +x toward the room.
const NICHE_PIECE := "wall.crypt.niche_%s"
const NICHE_CRACKED := "wall.crypt.cracked"
## A dais indoors (580 step 3, terrain's side; the Hall of Fallen Souls):
## an edge between two floors exactly one level apart is art-kit's
## dais.edge in place of a cliff face, dais.steps where the low cell is a
## stair climbing onto it (its steps reach DAIS_STEPS_REACH into that cell,
## drawn flat under them). In buildings' edge frame: along z, +x the low
## side, its origin on the low floor at the edge's middle.
const DAIS_EDGE := "dais.edge"
const DAIS_STEPS := "dais.steps"
const DAIS_STEPS_REACH := 0.624
const NICHE_OPEN := "wall.crypt.niche_open"
## The hidden niche's footprints (608 amended, terrain's side): art-kit's
## flat dust mesh on its entry cell, +x toward the wall; left when found.
const NICHE_FOOTPRINTS := "prop.footprints"
## A damp place's decor (647, terrain's side; Jeff: "moss and spiderwebs
## for decor, no live plants"): terrain "decor"'s entries as art-kit's
## prop.<kind>, by kind's frame: moss_patch flat on its cell at a yaw of its
## own; moss_strip and web_niche on their edge (+x the room, along -out);
## web_corner in its cell's corner out names (the piece's own the -x/-z
## one, DECOR_CORNER, turned to it).
const DECOR_SLOT := "prop.%s"
const DECOR_CORNER := Vector2i(-1, -1)
const ROCK_SMALL := "rock.small"
const ROCK_LARGE := "rock.large"
const ROCK_SMALL_SIZES := Vector2(0.9, 1.3)
const ROCK_LARGE_SIZES := Vector2(0.9, 1.1)
const ROCK_SINK := Vector2(0.05, 0.15)
const WATER_SHADER := preload("res://client3d/water.gdshader")
## Drawn before the marks on it (hover, ripple, builder's ghost: 0) and the
## faded walls (188).
const WATER_PRIORITY := -1
const TORCH := Color(1.0, 0.72, 0.38)
## The ground is drawn in squares this many cells across, a mesh each: few
## draws, and squares off screen are culled.
const FLOOR_CHUNK := 16
const GROUND_SHADER := preload("res://client3d/ground.gdshader")
## The ground and the scatter with the sight-line cut-out, swapped in only
## while it is in (decision 549 amended: a discard costs the GPU its early
## depth test on every frame, cut or not).
const GROUND_SIGHT_SHADER := preload("res://client3d/ground_sight.gdshader")
const SCATTER_SIGHT_SHADER := preload("res://client3d/scatter_sight.gdshader")
const LightShafts := preload("res://client3d/light_shafts.gd")
const Heartbeat := preload("res://client3d/heartbeat.gd")
const Bandaging := preload("res://client3d/bandaging.gd")
## A cell's corners, from its top left, in the order the ground's arrays
## keep them.
const GROUND_CORNERS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
## The highest a cell stands (Level.MAX_HEIGHT), for the ground's corners.
const MAX_GROUND_HEIGHT := Level.MAX_HEIGHT
## The ground's noise texture, texels across (64 features across it).
const GROUND_NOISE_SIZE := 512
## A wall's thickness, for the flat boxes and a door's pick shape.
const WALL_THICKNESS := 0.5
const POST_SIZE := 0.5
## Flat-colour walls instead of the kit pieces (for interiors later).
const BOX_WALLS := false
## The kit's stone, sampled from its colormap at the wall mesh's UVs.
const STONE := Color("ebb48e")
## The 2D floor tile's colour (the box floor).
const FLOOR := Color("4b7164")
const NEAR_ALPHA := 0.3
## A near piece's mesh keeps its own material override under this meta
## while it is see-through.
const OPAQUE_META := &"opaque_material"
## A mesh's own surface overrides (its season's materials), kept while it
## is faded: one per surface, null where none.
const OPAQUE_SURFACES_META := &"opaque_surfaces"
## The season (decision 362; terrain's side, decision 387):
## trees, their forest's floors and the canopy past them drawn in
## season.gdshader (season_material), a see-through copy beside each (this
## meta) for the near fade.
const SEASON_SHADER := preload("res://client3d/season.gdshader")
const SEASON_NEAR_SHADER := preload("res://client3d/season_near.gdshader")
const SEASON_NEAR_META := &"season_near"
## A doorway's door.single (ArtKit): its frame, and its hinged leaf.
const DOOR_FRAME := ^"Door/Body"
const DOOR_LEAF := ^"Door/leaf"
## Near pieces blend only their nearest surface: every near piece's depth
## is drawn first (NEAR_DEPTH_SHADER, at NEAR_DEPTH_PRIORITY), then their
## colour where it matches (NEAR_PRIORITY). Plain alpha showed every face
## behind the front one, doubled where two pieces meet (a light seam at
## each joint), and flickered as the pieces' sort order flipped. Water,
## rings and the target outline (priority 0) are drawn before, so what is
## behind a near piece shows through it; the HP bars (10) after, on top.
## (Godot's own depth pre-pass writes only nearly opaque pixels: none here.)
const NEAR_DEPTH_PRIORITY := 1
const NEAR_PRIORITY := 2
const NEAR_DEPTH_SHADER := """shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_always;
void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
"""
const CAMERA_PITCH := 50.0
## The low-horizon camera (decision 623, a trial toggle; Jeff: "drop the
## camera angle so we can see the sky"): outdoors, with Net.camera_low on,
## a perspective camera LOW_PITCH above the ground at LOW_FOV, half the
## distance off (LOW_DISTANCE_SHARE of CAMERA_DISTANCE; the wheel, a peek
## and the mourning pull-back scale that distance, as they do the ortho
## size), seeing LOW_FAR out under LOW_FOG of haze over the look's own
## fog with LOW_AERIAL of the sky in it, the sun's shadows out to
## LOW_SHADOW_DISTANCE in two splits so the edge where they stop is not
## in the middle of the view. The tilt's floor is LOW_PITCH_MIN; the ridge
## rule (525) lifts it as before. Under stone, and with the toggle off, the
## ortho camera exactly as before. What is drawn and known stays within
## World.NEAR_TILES (decision 238): a body beyond it is not drawn, a click
## past it lands at its edge on the way (within_near), the view's reach for
## shadows and puppets is held to it.
const LOW_PITCH := 22.0
const LOW_FOV := 50.0
const LOW_DISTANCE_SHARE := 0.5
const LOW_FAR := 300.0
const LOW_FOG := 0.012
const LOW_AERIAL := 0.6
const LOW_SHADOW_DISTANCE := 150.0
const LOW_PITCH_MIN := 15.0
## The scatter's own reach under the low camera (decision 653; Jeff:
## "clipping of ground details they should load in earlier"): it is built
## out to LOW_SCATTER_REACH of the aim (Client3D.scatter_reach_low, which
## map_bench sets), not World.NEAR_TILES, and shrinks into the ground over
## the last SCATTER_FADE of it, so its edge lies in the haze, not at the
## player's feet. Bodies, clicks and shadows keep NEAR_TILES. Chunks
## further than SCATTER_KEEP past the reach are freed, so what is drawn
## is held by distance, not by how far the player has walked; with more
## than SCATTER_BACKLOG steps due, steps go on within SCATTER_BUDGET_USEC
## a frame, so a turn or a walk fills in quickly.
const LOW_SCATTER_REACH := 90.0
const SCATTER_FADE := 16.0
const SCATTER_KEEP := 16.0
const SCATTER_BACKLOG := 8
const SCATTER_BUDGET_USEC := 2000
## Over hills (decision 525): how far back toward the camera the ground is
## looked at, how far under the line to the player (aimed RIDGE_AIM over
## their feet) it must stay, and how fast (degrees a second) the pitch
## follows.
const RIDGE_REACH := 14.0
const RIDGE_CLEAR := 0.3
const RIDGE_AIM := 1.0
const RIDGE_EASE := 40.0
## The most the camera lifts over a ridge (degrees): past it the view is near
## top-down and loses the slope and the player (better a ridge's edge in
## the way than no view of the hill at all).
const RIDGE_PITCH_MAX := 70.0
## Seeing the player through ground that hides them (decision 549): a
## sight-line cut-out in the ground's, cliffs' and scatter's shaders
## (sight.gdshaderinc), eased in and out over this long (s), as a wall fades.
const SIGHT_EASE := 0.25
const CLIFF_SHADER := preload("res://client3d/cliff.gdshader")
## Picking on the drawn ground: how far apart (m, across) the ray is tried.
const PICK_STEP := 0.2
const CAMERA_DISTANCE := 40.0
## Orthographic height in units: a 1.5-unit character, foreshortened by
## cos(CAMERA_PITCH), is about a twelfth of it.
const CAMERA_SIZE := 12.0
## The resting yaws are multiples of this: the diamond views.
const ORBIT_STEP := 90.0
## The wheel's zoom: a factor on CAMERA_SIZE (smaller is nearer), this
## much a notch, held to ZOOM_MIN..ZOOM_MAX, eased toward at ZOOM_RATE (an
## exponential rate a second: a notch is all but done in a quarter second).
const ZOOM_STEP := 1.1
const ZOOM_MIN := 0.8
## ZOOM_MAX keeps the view's widest reach (_view_reach: about 19 to 22
## tiles, wide screens and a peek the most) within World.NEAR_TILES, so what
## is on screen thinks every tick (decision 238).
const ZOOM_MAX := 1.1
const ZOOM_RATE := 14.0
## Click scheme, a middle drag: the view slides off the player, the ground
## under the cursor kept under it, no further than PAN_MAX tiles; a middle
## click brings it back, eased at ZOOM_RATE.
const PAN_MAX := 10.0
## A WASD middle drag let go: on to its diamond, eased out.
const SETTLE_SECONDS := 0.25
## A turn of less than this, let go, goes back to the diamond it set off
## from; any more goes on to the next one.
const TURN_COMMIT := 10.0
## A/D let go back to the diamond it set off from: the settle takes the
## time a stop from the turning speed would, plus this, for the turn back.
const TURN_RETURN_EXTRA := 0.15
## Click scheme keys: A/D turn this fast (degrees a second); W/S tilt this
## fast between PITCH_MIN and PITCH_MAX, slowing over the last
## TILT_EASE_DEGREES at either end, and the tilt springs back over
## TILT_RETURN_SECONDS when they are let go.
const TURN_RATE := 180.0
const TILT_RATE := 60.0
const PITCH_MIN := 40.0
const PITCH_MAX := 85.0
const TILT_EASE_DEGREES := 8.0
const TILT_RETURN_SECONDS := 0.25
## The pitch peek: the tilt it goes to, the drag for all of it (screen
## px), how far it pulls back (ortho size), and the spring back.
const PEEK_PITCH := 85.0
const PEEK_DRAG_PX := 300.0
const PEEK_PULL_BACK := 1.2
const PEEK_RETURN_SECONDS := 0.25
const PLAYER_LIGHT_RANGE := 6.0
## A damp level (580, terrain's side; level.json "damp", Jeff: "damp and
## dark, human eyesight barely lights it up, its too moist to light
## lamps"): its ambient this share of the zone's, toward DAMP_COLD; a faint
## cold haze (DAMP_FOG, DAMP_FOG_DENSITY); a carried lantern at the sim's
## reach (Fields.carried_reach) and DAMP_LANTERN of its energy.
const DAMP_AMBIENT := 0.4
const DAMP_COLD := Color(0.42, 0.5, 0.58)
const DAMP_FOG := Color(0.025, 0.03, 0.04)
const DAMP_FOG_DENSITY := 0.02
const DAMP_LANTERN := 0.75
## A light casts shadows only while its reach overlaps the ground the camera
## shows, give or take this (cells); checked when the view moves a cell or
## changes size, and every SHADOW_RECHECK seconds for lights that move.
const SHADOW_MARGIN := 2.0
## A puppet is kept up each frame only while its entity is within the view's
## reach and this (cells), or within earshot (Sfx.MAX_DISTANCE); further
## off, only what it will need on coming back (its tile, its hp).
const PUPPET_MARGIN := 4.0
## Under the low camera a body crossing World.NEAR_TILES eases in or out
## over this long (s) through its meshes' transparency, instead of
## popping (the low-angle fight, 4; _ease_reach). The sim still sends and
## withdraws it at its own edge (238); the eased moment is the client's.
const REACH_EASE := 0.5
## A puppet left far off is looked at again every this many frames (its
## coming near, its hp), not every frame.
const FAR_EVERY := 4
const SHADOW_RECHECK := 0.5
## Warm white, whatever the body's colour.
const PLAYER_LIGHT := Color(1.0, 0.93, 0.82)
const FIRE := Color(1.0, 0.45, 0.1)
const FIRE_SHADER := preload("res://client3d/fire.gdshader")
const SCATTER_SHADER := preload("res://client3d/scatter.gdshader")
## How wide a cell's fire patch is drawn, in cells.
const FIRE_SPREAD := 1.5
## A fire cell's flames (decision 523): how many, and their heights (m).
const FIRE_FLAMES := Vector2i(2, 3)
const FIRE_FLAME_SIZES := Vector2(0.45, 0.75)
## A torch marker's art (art-kit's standing torch; the stone post until it
## has art).
const TORCH_POST := "prop.torch_post"
## The floor where there is no light at all (Fields), as a share of its
## colour; the glow it takes on near heat, at most WARM_MOST of the way.
const FLOOR_DARKEST := 0.3
## The floor's brightness rises over this band of light (smoothly), so
## ground where a body is seen (Senses.DARK, inside it) reads plainly
## brighter than ground where it is only glimpsed: a torch's pool has an
## edge (decision 304).
const FLOOR_LIGHT_LOW := 0.2
const FLOOR_LIGHT_HIGH := 0.7
const WARM := Color(1.0, 0.5, 0.2)
const WARM_MOST := 0.45
const LANTERN := Color(1.0, 0.93, 0.7)
const AMBIENT := Color(0.05, 0.05, 0.07)
const BACKGROUND := Color(0.02, 0.02, 0.025)
const SUN := Color(0.6, 0.7, 1.0)
const SUN_ENERGY := 0.1
## Outdoors (level.json "outdoor"): a day sky lights the place (the camera
## looks down, so the sky is seen as its light and as the ground's colour
## past the forest), and the outline is a band of the kit's trees on the
## void beside the land instead of walls: one on every cell beside it,
## thinning out to FOREST_DEPTH, a scatter out to FOREST_REACH, over a
## forest floor. A tree between the camera and the player is see-through,
## as a near wall is. The ambient light is neutral (DAY_AMBIENT), not the
## sky's, whose lower half is the forest's green: colour comes from the
## lights.
const SKY_TOP := Color("4f86c6")
const SKY_HORIZON := Color("b8d0e6")
const FOREST_FLOOR := Color("2c4224")
const DAY_SUN := Color(1.0, 0.95, 0.86)
const DAY_SUN_ENERGY := 1.1
const DAY_AMBIENT := Color(1.0, 1.0, 1.0)
const DAY_AMBIENT_ENERGY := 0.6
## Outdoors the sky follows the world clock (DayNight, decision 292): these
## keys, by the sun's height in degrees, each the sky's top and horizon,
## the ambient light, the sun's (or under the horizon the moon's) light
## and the haze, are blended between; midday is the DAY_* look above,
## from 12° up (it was 22°, decision 534), and the haze while the sun is up
## no thicker than midday's. Warm gold at dawn and dusk, cool blue under
## the moon.
const SKY_KEYS := [
	[-14.0, {"top": Color("0b1322"), "horizon": Color("1d2b45"), "ambient": Color(0.42, 0.5, 0.8), "ambient_energy": 0.24,
		"light": Color(0.62, 0.72, 1.0), "energy": 0.26, "fog": Color("1d2b45"), "fog_density": 0.003}],
	[-5.0, {"top": Color("1f2a46"), "horizon": Color("6a4a5a"), "ambient": Color(0.55, 0.52, 0.72), "ambient_energy": 0.26,
		"light": Color(0.7, 0.72, 1.0), "energy": 0.1, "fog": Color("4a3e55"), "fog_density": 0.003}],
	[-1.0, {"top": Color("3a4a72"), "horizon": Color("c7794a"), "ambient": Color(0.85, 0.7, 0.62), "ambient_energy": 0.36,
		"light": Color(1.0, 0.55, 0.3), "energy": 0.0, "fog": Color("b0765a"), "fog_density": 0.0025}],
	[6.0, {"top": Color("6283b8"), "horizon": Color("e3a96f"), "ambient": Color(1.0, 0.9, 0.78), "ambient_energy": 0.48,
		"light": Color(1.0, 0.72, 0.42), "energy": 0.8, "fog": Color("d9a77c"), "fog_density": 0.0008}],
	[12.0, {"top": SKY_TOP, "horizon": SKY_HORIZON, "ambient": DAY_AMBIENT, "ambient_energy": DAY_AMBIENT_ENERGY,
		"light": DAY_SUN, "energy": DAY_SUN_ENERGY, "fog": SKY_HORIZON, "fog_density": 0.0008}],
]
## Under the weather (decision 309): how much of the sun's light full cloud
## takes (the ambient stays, so a storm's noon is grey, not dark); the haze
## full fog and full rain add (Environment fog density, per unit: the
## camera is CAMERA_DISTANCE off); full fog's layer along the ground, up
## to FOG_HEIGHT. Eased in decision 534 (Jeff's "muted"): a grey sky
## still lights a coloured ground.
const CLOUD_SUN := 0.5
## The seasons' light (decision 362): winter's cool, pale tint, the sun
## weaker by WINTER_SUN; summer's warmer; snow cover's lift to the ambient
## (winter's half as strong since decision 534).
const WINTER_LIGHT := Color(0.86, 0.92, 1.0)
const WINTER_SKY := Color("9fb3c8")
const SUMMER_LIGHT := Color(1.0, 0.93, 0.8)
const WINTER_SUN := 0.1
const SNOW_AMBIENT := 0.35
## Under a forest's canopy (decision 477): the ambient's share full cover
## at the sim's full shade (DayNight.CANOPY_SHADE) takes, the green it is
## tinted, and the haze's; how fast the cover round the view eases (per
## second), and how far round it is read (cells).
const CANOPY_AMBIENT := 0.6
const CANOPY_TINT := Color(0.42, 0.55, 0.36)
const CANOPY_FOG := Color(0.3, 0.38, 0.28)
const CANOPY_EASE := 3.0
const CANOPY_AROUND := 2
const FOG_DENSITY := 0.012
## Rain's own haze is a trace (0.008 until decision 534 amended: rain read
## as fog); fog and storms bring theirs through their fog.
const RAIN_FOG_DENSITY := 0.001
## How much rain darkens the greyed colours under it (0.25 until 534 amended).
const RAIN_DARK := 0.1
const FOG_HEIGHT := 2.5
const FOG_HEIGHT_DENSITY := 0.22
## Under this height (degrees) the light is the moon's, opposite the sun.
const MOON_BELOW := -1.0
## Shadows are cast from a sun lifted toward the zenith (shadow_elevation):
## from SHADOW_LOW (degrees) at the horizon, so even the first and last
## hour's are under one and a half times what casts them, to SHADOW_HIGH
## overhead, so noon's are short (Jeff: "shadows in general are too long,
## it should be pretty subtle"; 20° flat until 534 amended (2), 14° before
## 534 let a house's run 30-40 cells). They are SHADOW_STRENGTH dark (1 is
## black; 0.6 until 534 amended (3), Jeff: "i'll go with 0.8"), and fade out over SHADOW_FADE either side of MOON_BELOW, where
## the light swaps to the moon.
const SHADOW_LOW := 35.0
const SHADOW_HIGH := 85.0
const SHADOW_STRENGTH := 0.8
const SHADOW_FADE := 5.0
## Away from the sky, each kind of place's ambient light, [colour, energy]
## (decision 304), spread as the sim's light is: a room is dim but all of
## it shows, warm-grey; a cave is moonlight, shapes without colour; a
## dungeon is near black past the lamps.
const ZONE_LOOK := {"indoors": [Color(0.62, 0.56, 0.48), 0.55], "cave": [Color(0.42, 0.48, 0.62), 0.22],
	"dungeon": [AMBIENT, 0.5]}
## The sky moves on in steps of a game minute (a day's 1440th): the sun's
## direction stays put between, so shadow edges do not crawl (decision 292).
const SKY_STEPS := 1440
## The sun's shadows reach this far from the camera (it stands
## CAMERA_DISTANCE from what it looks at).
const SHADOW_DISTANCE := 70.0
## The sun's shadow map (px) and its blur: at 4096 and 1.5 the shadows were
## speckled blobs, at these clean shapes for no frame time perf could
## measure (decision 526).
const SUN_SHADOW_SIZE := 8192
const SUN_SHADOW_BLUR := 1.0
## Below the water's bed.
const FOREST_FLOOR_DEPTH := 0.2
## A piece fades when the line from the camera to the local player or
## their companion, at each of these heights (feet, middle, head), passes
## through its bounds, and the piece stands on the camera's side of them
## (not a wall at their back in a corner); a wall fades with its whole run.
## The bounds are the meshes' own: grown, a wall at their back that they
## stand beside was grazed by the line, and its run faded.
const FADE_HEIGHTS: Array[float] = [0.3, 0.9, 1.5]
## How long a piece stays faded after it stops hiding them, so walking along
## a wall does not make it flicker.
const FADE_HOLD := 0.4
## The pieces that can fade are indexed by squares this many units across
## (_index_occluders), so the lines to the player are tested against those
## near them only, not every tree of a big map (310).
const FADE_CHUNK := 8.0
## A fight's other side (the low-angle fight, 1): a live monster hunting
## or fighting (its alert, replicated) or lately struck or striking
## (COMBAT_SECONDS, as its bar shows) within this many tiles of the local
## player or their companion is hidden from the camera no more than they
## are: what stands between it and the camera fades as for them
## (_fight_points). An idle, suspicious or fleeing one keeps its cover, so
## what the sim lets sneak up still does. Not its roof or its room's near
## side: those open for the player alone.
const FIGHT_TILES := 6.0
## A damaged building's roof until its slot has a roof_damaged part: tipped
## and dropped at its eaves, caved in at a glance (_show_state).
const ROOF_SAG := Transform3D(Basis(Vector3.RIGHT, 0.18), Vector3(0.0, -0.45, 0.0))
## A kind's roof sagging (_kind_sag): its tilt (radians) about its middle, and how far it is let down.
const KIND_SAG := 0.05
const KIND_SAG_DROP := 0.05
## A roof set's shape until roof.<set>.profile says (decision 364): metres
## it rises a cell in from the eave, its thickness, how far it reaches past
## the walls; and its colour until material.roof.<set> has a texture.
const ROOF_PROFILE := {"rise": 0.75, "thickness": 0.15, "overhang": 0.3}
const ROOF_SWATCH := Vector2i(2, 4)
## A barge board's depth and thickness (m); how far a ridge cap's base sits
## below the apex (roof.<set>.ridge: its lowest edges 0.25 m out on a 0.75
## pitch).
const ROOF_BARGE := Vector2(0.05, 0.2)
const ROOF_CAP_DROP := 0.1875
## A building's side is near the camera, and fades while the player is
## inside (_inside_walls), when its outward way and the camera's, flat,
## agree more than this (the cosine): both sides toward the camera in a
## diamond view, not the sides it looks along.
const NEAR_SIDE := 0.2
const FOREST_DEPTH := 3
## Monster kinds drawn as an animated model instead of a capsule: the scene
## (retargeted on import to SkeletonProfileHumanoid, its skeleton
## %GeneralSkeleton), its clips (an AnimationLibrary of retargeted clips,
## art/models/animations), how tall it stands, and which way it faces as
## modelled ("faces": the yaw that turns its front to +X; the goblin faces
## +Z, its toes ahead of its feet, so a quarter turn).
## What a humanoid on the UAL skeleton does in a fight (roadmap step 3, perf's
## rig plays them): the strikes by what is in the striking hand (an Items id,
## "" bare-handed), each [clip, contact]: the seconds in, at speed 1, its blow
## lands (the striking hand's fastest forward, measured by
## tools/humanoid_clips.py --contacts); the guard, the knockdown, lying and
## getting up, the hits by the side a blow came from, the deaths, the bow (the pack's pistol stands in) and
## the dodges. Clips the UAL lacks are authored by tools/humanoid_clips.py on
## its skeleton; all are in art/models/animations/goblin.res.
const HUMANOID_MOVES := {
	"strikes": {
		"": [["Punch_Jab", 0.17], ["Punch_Cross", 0.21]],
		"sword": [["Sword_Attack", 0.38], ["Sword_Attack_Standing", 0.38]],
		"giant_axe": [["Axe_Overhead", 0.42]],
		"hammer": [["Mace_Overhead", 0.42]],  # One-handed: Axe_Overhead's left hand would grip nothing.
		"pick": [["Axe_Overhead", 0.42]],  # A miner's swing, two-handed (items' 479; the kobold's, 478).
		"dagger": [["Dagger_Stab", 0.17]],
		"spear": [["Spear_Thrust", 0.29]],
		"shield": [["Shield_Bash", 0.17]],
		"kick": [["Kick", 0.25]],
	},
	"block": "Block_Idle", "knockdown": "Knockdown", "lying": "Lie", "get_up": "Get_Up",
	# A blow taken, by the side it came from (each a list to pick from without repeats).
	"hits": {"front": ["Hit_Chest", "Hit_Head"], "left": ["Hit_Shoulder_L"], "right": ["Hit_Shoulder_R"], "back": ["Hit_Back"]},
	"deaths": ["Death01", "Death02"], "bow_draw": "Bow_Draw", "bow_aim": "Bow_Hold", "bow_shoot": "Bow_Loose", "bow_idle": "Bow_Idle",
	"dodges": ["Dodge_Left", "Dodge_Right"], "stance": "Sword_Idle", "ready": "Axe_Ready",
}
## Attach points (decision 451): where a humanoid holds and hangs things, on
## its skeleton's bones (the retargeted SkeletonProfileHumanoid's names, so
## every humanoid model has the same bones in the same frames: a hand's +Y
## along the fingers, +X toward the right hand's index and the left's little
## finger, +Z out of the palm; the trunk's +X its left, +Z its front), as
## {socket: [bone, transform in the bone's frame]}. A held piece (art_style:
## its origin the grip, its length along +Y) sits at a hand's socket in the
## middle of the hand, its length out of the thumb's side. The bodies' hands
## are mittens (their fingers don't bend the mesh), so the grip is the
## mitten's middle, not the knuckle line tools/grip_sockets.gd measured from
## the finger bones; there it sat at the hand's end (Jeff: "sword hilt is at
## the end of hand, not in palm"). The mitten, posed, from the wrist: 0.017
## to 0.13 along +Y, its middle 0.069 (the woman's 0.065), 0.005 to the palm's
## side of the bone (build/hand/measure.py). The goblin takes the human hand's
## frame scaled to its hand's length, 0.69.
const HAND_GRIP := 0.07
const HAND_PALM := 0.005
static func _sockets(hand: float, hip: float, back: float, chest: float) -> Dictionary:
	return {
		"hand_r": ["RightHand", Transform3D(Basis(Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)),
			Vector3(0.0, HAND_GRIP, HAND_PALM) * hand)],
		"hand_l": ["LeftHand", Transform3D(Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)),
			Vector3(0.0, HAND_GRIP, HAND_PALM) * hand)],
		# The left forearm's middle (_attach_sockets puts it there), in a shield's
		# frame: its face (+z) out of the back of the forearm (the bone's -X), its
		# +y along the forearm toward the wrist (+Y).
		"arm_l": ["LeftLowerArm", Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), Vector3.ZERO)],
		# Between the shoulder blades, a stowed thing's length up and over the right shoulder.
		"back": ["UpperChest", Transform3D(Basis(Vector3(0, 0, -1), PI * 0.2), Vector3(0.0, chest, -back))],
		# The left hip, a hung thing's length down.
		"belt_l": ["Hips", Transform3D(Basis(Vector3(0, 0, 1), PI), Vector3(hip, 0.0, 0.0))],
	}
const HUMAN_SOCKETS := {"hand": 1.0, "hip": 0.17, "back": 0.13, "chest": 0.04, "crown": true}
const GOBLIN_SOCKETS := {"hand": 0.69, "hip": 0.19, "back": 0.16, "chest": 0.02}
## The Blood Rot's allies' (decision 478): their hands as long as a human's
## times their people's (body_gen's PROPORTIONS and height), their bodies
## broader or slighter.
const ORC_SOCKETS := {"hand": 1.47, "hip": 0.24, "back": 0.19, "chest": 0.06}
const KOBOLD_SOCKETS := {"hand": 0.92, "hip": 0.12, "back": 0.1, "chest": 0.03}
## Their gaits' paces, by tools/gait_pace.gd (the kobold's short legs
## scurry: it jogs at 1.8 tiles a second where a man jogs at 3.6).
## The orc's since its TRELLIS body (decision 529): its jog measured (3.35, its legs bent
## as its concept stands), its walk and sprint as the generator's were to its jog (0.82 of them).
const ORC_GAITS: Array[Array] = [[CLIP_WALK, 0.86], ["Jog_Short", 3.35], ["Sprint_Short", 5.15]]
## The kobold's since its TRELLIS body (529 amended), each measured.
const KOBOLD_GAITS: Array[Array] = [[CLIP_WALK, 0.39], ["Jog_Short", 1.63], ["Sprint_Short", 2.44]]
## The imp is the Blood Rot goblin; the brute an orc and the sneak a kobold,
## allied peoples (decision 416), each body_gen's (decision 478) and drawn as a
## person is ("parts", a PersonLook of its "people"), or art-gen's mesh in its
## own paint (decision 529: "paint", its material, the goblin's shader; its
## PersonLook only its stature, its mesh hunched as its concept stands). The
## barrow's dead are art-kit's by hand on the human skeleton, on the palette:
## the skeleton creature.skeleton's variant 1, the barrow guard its variant 2
## (helm, mail and shield), the human gaits and sockets, fidgets of their own;
## the draugr creature.draugr, the human skeleton scaled DRAUGR_SCALE (its
## gaits and sockets so too); the ghost creature.ghost, the skeleton under a
## translucent shroud that casts no shadow (GHOST_MATERIAL).
const MODELS := {
	"imp": {"scene": "res://art/models/characters/goblin.glb", "clips": "res://art/models/animations/goblin.res", "height": 1.2,
		"faces": PI * 0.5, "moves": HUMANOID_MOVES, "sockets": GOBLIN_SOCKETS, "goblin": true},
	"brute": {"scene": "res://art/models/characters/orc.glb", "clips": "res://art/models/animations/goblin.res", "height": 1.95,
		"faces": PI * 0.5, "by_mass": false, "gaits": ORC_GAITS, "backpedal": 4.30, "people": "orc",
		"paint": "res://art/models/characters/orc_body.tres",
		"fidgets": ORC_FIDGETS, "moves": HUMANOID_MOVES, "sockets": ORC_SOCKETS},
	"sneak": {"scene": "res://art/models/characters/kobold.glb", "clips": "res://art/models/animations/goblin.res", "height": 1.0,
		"faces": PI * 0.5, "by_mass": false, "gaits": KOBOLD_GAITS, "backpedal": 2.10, "people": "kobold",
		"paint": "res://art/models/characters/kobold_body.tres",
		"fidgets": KOBOLD_FIDGETS, "moves": HUMANOID_MOVES, "sockets": KOBOLD_SOCKETS},
	"skeleton": {"scene": "res://art/kit/creatures/creature.skeleton/creature.skeleton.glb",
		"clips": "res://art/models/animations/goblin.res", "height": 1.75, "faces": PI * 0.5, "by_mass": false,
		"gaits": HUMAN_GAITS, "fidgets": DEAD_FIDGETS, "moves": HUMANOID_MOVES, "sockets": HUMAN_SOCKETS},
	"skeleton_guard": {"scene": "res://art/kit/creatures/creature.skeleton/creature.skeleton.2.glb",
		"clips": "res://art/models/animations/goblin.res", "height": 1.75, "faces": PI * 0.5, "by_mass": false,
		"gaits": HUMAN_GAITS, "fidgets": DEAD_FIDGETS, "moves": HUMANOID_MOVES, "sockets": HUMAN_SOCKETS},
	"draugr": {"scene": "res://art/kit/creatures/creature.draugr/creature.draugr.glb",
		"clips": "res://art/models/animations/goblin.res", "height": 1.75 * DRAUGR_SCALE, "faces": PI * 0.5, "by_mass": false,
		"gaits": DRAUGR_GAITS, "fidgets": DEAD_FIDGETS, "moves": HUMANOID_MOVES, "sockets": DRAUGR_SOCKETS},
	"ghost": {"scene": "res://art/kit/creatures/creature.ghost/creature.ghost.glb",
		"clips": "res://art/models/animations/goblin.res", "height": 1.75, "faces": PI * 0.5, "by_mass": false,
		"gaits": HUMAN_GAITS, "fidgets": DEAD_FIDGETS, "moves": HUMANOID_MOVES, "sockets": HUMAN_SOCKETS},
}
## A model's surface in this material (art-kit's ghost's shroud) is see-through
## and casts no shadow (the coordinator's ruling): its mesh's shadow is off.
const GHOST_MATERIAL := "ghost"
## Each modelled monster is its own (_vary, seeded by its name, so every
## view sees the same one): its size goes with its mass, as the cube root of
## its mass over MODEL_MASS, within MODEL_SCALE_MIN/MAX, give or take
## MODEL_SCALE_SPREAD; its pace (GAITS', as its legs are longer or shorter,
## give or take PACE_SPREAD) and its idle tempo (TEMPO_SPREAD) its own; and
## loops start where they will, so a crowd does not move as one.
const MODEL_MASS := 40.0
const MODEL_SCALE_MIN := 0.8
const MODEL_SCALE_MAX := 1.4
const MODEL_SCALE_SPREAD := 0.05
const PACE_SPREAD := 0.08
const TEMPO_SPREAD := 0.10
## A blow, a flinch, a death: one of these, never the same blow or flinch
## twice running.
const ATTACK_CLIPS: Array[String] = ["Punch_Jab", "Punch_Cross", "Kick"]
const HIT_CLIPS: Array[String] = ["Hit_Chest", "Hit_Head", "Hit_Shoulder_L", "Hit_Shoulder_R"]
const DEATH_CLIPS: Array[String] = ["Death01", "Death02"]
## Standing, a model now and then fidgets (once FIDGET_CALM_SECONDS from the
## last blow near it, every FIDGET_SECONDS_MIN to MAX): one of FIDGETS (or
## its model's "fidgets"), by weight, not the one before; a loop among them
## is played for one round of it. When, and which, are its own and differ
## run to run (its "fidget_rng", seeded by its name and _session_seed; Jeff:
## "the idle need variability and same scratch is very predictable"), while
## its size, pace and blows stay its name's alone, alike on every view. Hurt
## or winded it stands tired.
const CLIP_LOOK_ABOUT := "Idle_LookAround"
const FIDGETS := {"Idle_LookAround": 4, "Idle_Talking": 2, "Drink": 1, "Fixing_Kneeling": 1,
	"PickUp_Kneeling": 1, "Crouch_Idle": 1, "Fidget_Shift": 1, "Fidget_LookBack": 1}
## A person's: the head scratch (Idle_LookAround) the rarest of them
## (tools/humanoid_clips.py's fidgets); the orc's and the kobold's their own.
const HUMAN_FIDGETS := {"Idle_LookAround": 1, "Fidget_Shift": 3, "Fidget_LookBack": 3, "Fidget_Shoulders": 3,
	"Fidget_Sleeve": 2, "Fidget_ArmsCrossed": 2}
## The dead's: no drinking or talking, a look round and a shift of the bones.
const DEAD_FIDGETS := {"Idle_LookAround": 2, "Fidget_Shift": 2, "Fidget_LookBack": 1}
const ORC_FIDGETS := {"Idle_LookAround": 1, "Fidget_Shoulders": 3, "Fidget_ArmsCrossed": 3, "Fidget_Shift": 2}
const KOBOLD_FIDGETS := {"Idle_LookAround": 1, "Fidget_LookBack": 3, "Fidget_Sleeve": 3, "Fidget_Shift": 2}
## This run's: so a person's fidgets come at other moments each run.
static var _session_seed := randi()
const CLIP_TIRED := "Idle_Tired"
## Sitting (Monster.Pose.SIT, at a gathering): down, sat, and up again.
const CLIP_SIT_DOWN := "GroundSit_Enter"
const CLIP_SITTING := "GroundSit_Idle"
const CLIP_SIT_UP := "GroundSit_Exit"
const FIDGET_SECONDS_MIN := 6.0
const FIDGET_SECONDS_MAX := 25.0
const FIDGET_CALM_SECONDS := 4.0
const TIRED_BELOW := 0.34
## A wound-up blow (Monster's HEAVY): this clip, played so that its swing
## connects (CLIP_HEAVY_CONTACT seconds in, at speed 1: measured on the
## goblin, just past the hand's fastest) as the sim's blow lands; that
## blow's own swing then plays no other clip.
const CLIP_HEAVY := "Sword_Attack"
const CLIP_HEAVY_CONTACT := 0.45
const CLIP_IDLE := "Idle"
const CLIP_WALK := "Walk"
const CLIP_JOG := "Jog_Fwd"
const CLIP_SPRINT := "Sprint"
const CLIP_ATTACK := "Punch_Jab"
const CLIP_HIT := "Hit_Chest"
const CLIP_DEATH := "Death01"
## Knocked about: a plain push back backpedals for the slide (at least
## KNOCK_MIN_SECONDS), facing whence it came; a toss rolls over backwards
## (the forward roll played in reverse), facing whence it came too, then
## lands; a push back doubles over when it gets there, hit or not (the sim
## stuns it for that beat, World.knockback_stun_ticks), and a toss does too
## if a wall or a door (or a fall) stops it. A blow into another body is a
## hit as ever.
const CLIP_BACKPEDAL := "Jog_Bwd"
const CLIP_IMPACT := "Hit_Stomach"
const CLIP_ROLL := "Roll"
const CLIP_LAND := "Jump_Land"
const KNOCK_MIN_SECONDS := 0.45
## The backpedal's pace at speed 1, as GAITS'; the roll is played this
## much faster, to fit a toss's short flight.
const BACKPEDAL_CLIP_SPEED := 2.6
const ROLL_SPEED := 1.6
## A push whose slide has not shown by then (the view draws others a
## little in the past) is knocked about where it stands.
const KNOCK_WAIT_SECONDS := 0.6
## Moving, a model walks, jogs or sprints by its pace, each clip played at
## the pace over its own (tiles a second at speed 1), so a planted foot stays
## put instead of skating. A clip's pace is the one at which the goblin's
## planted feet drift least, measured by moving the model under the clip
## (decision 160).
const GAITS: Array[Array] = [[CLIP_WALK, 0.5], [CLIP_JOG, 3.5], [CLIP_SPRINT, 5.4]]
## Gaits change past the geometric mean of their paces, this much beyond it
## either way, so a pace near a change does not flicker between them.
const GAIT_HYSTERESIS := 1.15
## People (players, companions, residents): humanoid bodies (decision 243), a
## man's and a woman's (the entity's "body", decision 388), made by
## tools/body_gen.py (decision 419) on the animation library's own skeleton,
## so its clips play at the proportions they were made for. Each is drawn as
## its PersonLook (look_for): shape keys, a stature, the parts it wears
## (hair, beard, headwear, apron: meshes of the same scene, shown or not), its
## colours, its posture (an additive pose on its AnimRig, POSTURES). Their gaits
## are their own (HUMAN_GAITS: the two step alike), paced by their stature, as
## is their backpedal; all drawn in HUMAN_MATERIAL ("parts"), the tunic in the
## player's colour (the capsule's); standing, they only look about now and then.
## Their size is not their mass: what they carry counts in their mass, and
## picking up a hammer should not make them grow.
const HUMAN := {"scene": "res://art/models/characters/human_m.glb", "clips": "res://art/models/animations/goblin.res",
	"height": 1.75, "faces": PI * 0.5, "by_mass": false,
	"gaits": HUMAN_GAITS, "backpedal": 4.66,
	"parts": true, "fidgets": HUMAN_FIDGETS, "moves": HUMANOID_MOVES, "sockets": HUMAN_SOCKETS}
## The human bodies' gaits (decision 399 amended twice): the pack's jog and
## sprint take 2.6 m and 4 m steps, too long for a player's 4 tiles a second
## (Jeff on v0.1.149); Jog_Short and Sprint_Short narrow their swing
## (tools/humanoid_clips.py). Narrowed to 0.45 the jog's 1.25 m steps glided
## (Jeff on v0.1.150: "too short of strides now, theres a glide to it"): at
## 0.62 a player's jog plays at about 1.1 times, in 1.65 m steps. Paces by
## tools/gait_pace.gd on each body (hers are shorter legs, 5% slower), scaled
## by a person's stature: the jog gives way to the sprint at about 5.2 tiles
## a second.
const HUMAN_GAITS: Array[Array] = [[CLIP_WALK, 0.94], ["Jog_Short", 3.63], ["Sprint_Short", 5.55]]
## The draugr: the human skeleton scaled up (art-kit's, 2.1 m and more), its
## strides and its hands' sockets with it.
const DRAUGR_SCALE := 1.2
const DRAUGR_GAITS: Array[Array] = [[CLIP_WALK, 0.94 * DRAUGR_SCALE], ["Jog_Short", 3.63 * DRAUGR_SCALE], ["Sprint_Short", 5.55 * DRAUGR_SCALE]]
const DRAUGR_SOCKETS := {"hand": DRAUGR_SCALE, "hip": 0.17 * DRAUGR_SCALE, "back": 0.13 * DRAUGR_SCALE, "chest": 0.04 * DRAUGR_SCALE}
const HUMAN_F_GAITS: Array[Array] = [[CLIP_WALK, 0.89], ["Jog_Short", 3.44], ["Sprint_Short", 5.27]]
## The human bodies' one material, shared: each body's parts' colours are its
## instance's (HUMAN_PARTS, from its mesh's extras; the tunic the player's).
const HUMAN_MATERIAL := preload("res://art/models/characters/human_body.tres")
## The goblin's one material (decision 494): its paint varied per goblin by
## instance parameters (goblin_look), so a raid draws in one batch.
const GOBLIN_MATERIAL := preload("res://art/models/characters/goblin_body.tres")
## Its copy's shader under the hover outline: the same, marking the stencil.
const GOBLIN_MARKING_SHADER := preload("res://art/models/characters/goblin_marking.gdshader")
## A goblin's variation (goblin_look), each drawn by its name: its build (a
## width on its height, GOBLIN_WIDTH), its skin's shift within the Blood
## Rot's greens (hue, saturation, value: GOBLIN_SKIN_*), its gear tinted to
## one of GOBLIN_GEAR (or its own, GOBLIN_OWN_GEAR of the time) and a mark of
## GOBLIN_MARKS (or none, GOBLIN_UNMARKED of the time).
const GOBLIN_WIDTH := Vector2(0.88, 1.12)
const GOBLIN_SKIN_HUE := Vector2(-0.06, 0.05)
const GOBLIN_SKIN_SAT := Vector2(0.85, 1.15)
const GOBLIN_SKIN_VALUE := Vector2(0.8, 1.15)
const GOBLIN_GEAR := {"brown": "6b4a35", "dark": "3d2a1f", "grey": "7d8086", "red": "8a3a2c", "ochre": "a37d40",
	"straw": "9c8f74"}
const GOBLIN_OWN_GEAR := 0.3
const GOBLIN_MARKS := ["scarred", "striped", "red-handed"]
const GOBLIN_UNMARKED := 0.55
## Its hood up (GOBLIN_HOOD_UP of the time) or down, bare-headed; its ears
## from small to big (goblin.glb's Ears_Small and Ears_Big, tools/goblin_hood.py),
## a word past GOBLIN_EARS_SAID either way (decision 494 amended).
const GOBLIN_HOOD_UP := 0.7
## A painted ally's variation (painted_look; decision 529): a little broader or
## slighter, its skin's hue barely turned (an orc stays grey-blue, a kobold
## red to purple), its colour and lightness more, marked or not.
const PAINTED_WIDTH := Vector2(0.94, 1.06)
const PAINTED_SKIN_HUE := Vector2(-0.025, 0.025)
const PAINTED_SKIN_SAT := Vector2(0.8, 1.3)
const PAINTED_SKIN_VALUE := Vector2(0.85, 1.12)
const PAINTED_UNMARKED := 0.55
const GOBLIN_EARS_SAID := 0.6
const HUMAN_PARTS := ["skin", "hair", "tunic", "trousers"]
## A PersonLook's posture: its pose in the clips (rest plus the bend,
## tools/humanoid_clips.py), added at full weight.
const POSTURES := {"stooped": "Posture_Stooped", "slouching": "Posture_Slouch"}
const HUMAN_F := {"scene": "res://art/models/characters/human_f.glb", "clips": "res://art/models/animations/goblin.res",
	"height": 1.66, "faces": PI * 0.5, "by_mass": false,
	"gaits": HUMAN_F_GAITS, "backpedal": 4.66,
	"parts": true, "fidgets": HUMAN_FIDGETS, "moves": HUMANOID_MOVES, "sockets": HUMAN_SOCKETS}
## Moving faster than this (tiles a second) walks.
const WALKING := 0.4
const CLIP_BLEND := 0.15
## A body's pose's level of detail (_pose_every): metres from the camera's
## aim (the view is CAMERA_SIZE across) posed every frame, then every other; beyond, every POSE_FAR_EVERY; out
## of the frame, every POSE_UNSEEN_EVERY. A hundred bodies posed every frame
## cost 2.6 ms (26 us each).
const POSE_NEAR := 9.0
const POSE_MID := 16.0
const POSE_FAR_EVERY := 3
const POSE_UNSEEN_EVERY := 8
## How long after a blow's news a drawn body's blow lands: remote bodies are
## drawn about a tick and a half behind the sim (decision 390).
const STRIKE_LANDS_IN := 1.5 * World.TICK_DT
const MODEL_RADIUS := 0.3
## A click this near a monster's body (ground units, past its own pick
## shape, from the cursor's ray to the line from its feet to its head) is a
## click on it: a model is slim, and a click just off one would land on the
## ground behind it, a walk round it instead of a hit.
const PICK_SLACK := 0.45
## Under the low camera the slack is this share of the screen's height
## instead (either side; pick_slack_at): under perspective a far body is
## small on screen and PICK_SLACK of ground beside it a hair, so the slack
## is a thumb's width of screen whatever its distance and whatever the
## screen's pixels, never under PICK_SLACK (the low-angle fight, 2).
const PICK_SLACK_SHARE := 0.025
## At most this many pick shapes are looked through (the local player, a
## door) for the entity under the cursor.
const PICK_DEPTH := 8
const FOREST_REACH := 8
## A glimpse of the level past a way out (_plan_glimpses): this many of its
## cells deep from the side it shows us, this many cells of trees between
## our land and it, a lane through them this many cells either side of the
## way's line.
const GLIMPSE_DEPTH := 18
const GLIMPSE_GAP := 3
const GLIMPSE_LANE := 1
## A link's glimpse reaches this many cells either side of the way's line.
const GLIMPSE_WIDE := 20
const TREE_HEIGHT := 3.6
## A thing thrown onto a pile is drawn flying there if the pile shows it
## within this many ticks of the throw, for THROW_FLIGHT_SECONDS.
const THROWN_SHOWN_TICKS := 10
## A pile of what grows wild (Forage.HERBS, decision 502) stands as the
## plant it was picked from, about this wide.
const GROWING_WIDE := 0.5
const THROW_FLIGHT_SECONDS := 0.4
const PILE_RING := Color(0.95, 0.85, 0.55, 0.55)
## Trees: lean up to this far (radians), sit up to this far off their
## cell's middle, gather in clumps about FOREST_CLUMP cells across; the
## ground runs this many cells into the forest (216, 252).
const TREE_LEAN := 0.1
const TREE_NUDGE := 0.42
const FOREST_CLUMP := 6.0
const FOREST_GROUND := 3
## The art slots made once before a room is built (_warm_art).
const WARM_CATEGORIES: Array[String] = ["walls", "doors", "trees", "rocks", "buildings"]
## Saplings: how often an edge cell has one besides its tree, and their
## size against a tree's (252, 277).
const SAPLING_CHANCE := 0.6
const SAPLING_SIZE := Vector2(0.35, 0.6)
## Dead wood (277 amended), each only once its slot has art of its own or
## a fill (_deadwood_drawn): how often an edge cell with no sapling has its
## tree felled, a stump toward the land in its place; how often a cell in the forest with no tree has a
## stump or a log (a LOG_SHARE of them logs); how often a tree is dead.
const STUMP_EDGE_CHANCE := 0.12
const DEADWOOD_CHANCE := 0.14
const LOG_SHARE := 0.4
const DEAD_TREE_CHANCE := 0.04
## A felled forest cell by its stage (591, terrain's side; maps' Clearing):
## a stump on its dirt; grass; scrub, the grass thick and tall
## (SCATTER_SCRUB) with a bush SCRUB_BUSH of the time; saplings, two or
## three small trees CLEARING_SAPLING of a tree's height.
const SCATTER_SCRUB := {"tuft": 6.0, "tall": 2.5, "flower": 0.2, "stone": 0.05}
const SCRUB_BUSH := 0.6
const CLEARING_SAPLING := Vector2(0.3, 0.5)
## Scatter: how many of each, on average, a cell of each ground has (the
## forest's ring is "forest"), and roots more on the land at the forest's
## edge; each kind's size range; a flower's colours.
const SCATTER_DENSITY := {
	"grass": {"tuft": 3.0, "flower": 0.15, "stone": 0.05},
	"dirt": {"tuft": 0.25, "stone": 0.35},
	"sand": {"tuft": 0.12, "stone": 0.15},
	"stone": {"tuft": 0.06},
	"forest": {"tuft": 1.4, "root": 0.25, "stone": 0.1, "flower": 0.04},
}
const SCATTER_EDGE_ROOTS := 0.3
## Indoors nothing grows but on grass ground laid there on purpose (Jeff
## on the barrow: "moss and spiderwebs for decor, no live plants"; the
## sample's yard keeps its grass): elsewhere indoors only these kinds.
const SCATTER_INDOORS: Array[String] = ["stone"]
## A grass cell under a canopy this thick or more takes the forest's
## scatter (decision 467: ground.gdshader turns it to needles from 0.45).
const SCATTER_ROOF := 0.6
## How much of the season's snow lies on the forest's scatter under its roof
## (the ground has a third: ground.gdshader).
const SCATTER_ROOF_SNOW := 0.12
## How light its dried straw is there, out of season: it takes no shadow, so
## the roof's shade is put in.
const SCATTER_ROOF_STRAW := 0.5
const SCATTER_REEDS := 1.6
## Tall grass (decision 508, terrain's side): its clumps in place of the
## grass's tufts, a few flowers among them; at the patch's edge, where the
## camera sees them side-on, a little taller.
const SCATTER_TALL := {"tall": 9.0, "flower": 0.08}
const TALL_EDGE_SCALE := 1.2
const SCATTER_SIZES := {"tuft": Vector2(0.7, 1.3), "flower": Vector2(0.8, 1.1), "stone": Vector2(0.6, 1.6), "root": Vector2(0.8, 1.4),
		"reeds": Vector2(0.8, 1.3), "tall": Vector2(0.9, 1.1)}
## Flowers: the palette's accents (row 7: flame, bone, banner red, magic
## violet), the few saturated things on the ground.
const FLOWER_SWATCHES: Array[Vector2i] = [Vector2i(7, 0), Vector2i(7, 7), Vector2i(7, 3), Vector2i(7, 5)]
## Label3D: units per font pixel, with the font size, for a name about a
## quarter unit tall.
const LABEL_SIZE := 0.004
## Under the low camera a name over a body reads at every depth (the
## low-angle fight, 5; _sync_name): never smaller on screen than at the
## camera's aim (grown with its depth past the aim's), the nearest drawn
## over the farther (its render priority by depth), and past NAME_TILES
## of the local player only the party's and a foe's (hunting, fighting or
## lately struck, as the fade's _fight_points) or the marked target's;
## the rest wait till they are near, so a town's names don't crowd a
## fight.
const NAME_TILES := 8.0
const LABEL_FONT_SIZE := 64
const SPEECH := Color(1, 0.95, 0.6)
const HOVER := Color(1, 1, 1, 0.35)
## The monster a click would attack (the one under the cursor) is
## outlined (off-white), its own look untouched. Its body draws as ever but marks its
## pixels in the stencil buffer (its materials' copies, OUTLINE_STENCIL);
## over it, its meshes draw again in this colour, nudged this many screen
## pixels each of the eight ways (one pass a way, OUTLINE_SHADER), only
## where the body did not: an even rim round its silhouette, ears and
## fingers too, whatever its normals. The passes are drawn OUTLINE_NEARER
## (ground units) nearer the camera than the body, so the floor just in
## front of its feet does not hide the rim there; anything further in
## front still does.
const TARGET_OUTLINE := Color(0.93, 0.9, 0.82)
## A foe seen through what hides it (the low-angle fight, combat's (b)):
## a monster hunting or fighting (or lately struck) whose chest a nearer
## body (another's or the player's own) hides from the camera, or any
## body inside an active telegraph, wears the target's rim in this colour
## drawn with no depth test (_seen_through, _update_seen_through), so it
## shows through the body before it. Never through a wall or a building:
## only bodies are asked (hidden_by_body), and what the sim did not send
## is not there to outline, so its sight rule still says what you know.
const SEEN_OUTLINE := Color(0.93, 0.78, 0.52, 0.7)
const TARGET_PIXELS := 3.0
const OUTLINE_NEARER := 0.4
const OUTLINE_STENCIL := 1
const OUTLINE_SHADER := """shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
stencil_mode read, compare_not_equal, 1;
uniform vec4 colour : source_color = vec4(1.0);
uniform vec2 nudge = vec2(0.0);
uniform float nearer = 0.4;
void vertex() {
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	view.z += nearer;
	POSITION = PROJECTION_MATRIX * view;
	POSITION.xy += nudge * 2.0 / VIEWPORT_SIZE * POSITION.w;
}
void fragment() {
	ALBEDO = colour.rgb;
	// Drawn with the see-through things, after every solid one: the body has
	// marked the stencil by then.
	ALPHA = colour.a;
}
"""
const RIPPLE := Color(0.58, 0.76, 0.69)
const RIPPLE_SECONDS := 0.25
const RING_SEGMENTS := 40
## The hover outline: a square this far from the cell's centre, this thick.
const HOVER_HALF := 0.47
const HOVER_LINE := 0.05
## The aim's arc: its line's width (ground units), the marker's radius, a
## pip's radius and spacing, the most pips (the shortest step's).
const AIM_LINE := 0.08
const AIM_MARK := 0.22
const AIM_PIP := 0.13
const AIM_PIP_GAP := 0.32
const AIM_PIPS_MOST := 4
const AIM_SEGMENTS := 48
## The aim's ring, the cone's fill and its sides are built in strips this
## long (cells), every vertex on the ground under it (_height_in, the
## ground mesh's own height: a cell's two triangles, the shore's fine quads,
## the dais stairs), so they lie on a slope, a ridge, a ramp or stairs
## instead of sinking into rising ground or floating over a dip (Jeff:
## "on a slanted ground it disappears into the terrain"), as the telegraph
## fill and the stand ring do; rebuilt only when the aim or the archer moves.
const AIM_STRIP := 0.25
## The cone of flight (Jeff: "a cone of flight that narrows the longer the
## aim"; combat's design): the fill's alpha, the time the drawn half-angle
## eases toward the sim's over, in ticks (so a tick's step never pops).
const AIM_CONE_FILL := 0.18
const AIM_CONE_EASE_TICKS := 1.0
## Under a camera pitched below AIM_LOW_PITCH (degrees: the low camera, a
## deep S tilt) the cone's edges (its sides, its far arc) stand
## AIM_EDGE_LIFT (m) above the ground and its fill is AIM_CONE_FILL_LOW
## instead: a ring on the ground at 22 degrees is squashed near three to
## one and reads as a sliver (the low-angle fight, combat's (d);
## edge_lift).
const AIM_LOW_PITCH := 30.0
const AIM_EDGE_LIFT := 0.1
const AIM_CONE_FILL_LOW := 0.32
## The most the view leads the archer by, the WASD lean counted (perf, 617:
## the view's reach stays inside World.NEAR_TILES on every aspect).
const AIM_LEAD_CELLS := 4.0
## A telegraph's fill: faint at its start, full as it lands; the landing
## flash's alpha and length.
const TELEGRAPH_FAINT := 0.18
const TELEGRAPH_FULL := 0.6
const TELEGRAPH_FLASH := 0.95
const TELEGRAPH_FLASH_MSEC := 300
## A telegraph drawn smooth (combat's 602 amended, Telegraph.outline; the
## low-angle fight, combat's (a)): its fill is the outline's polygon cut to
## the sent cells (so a wall's clip cuts it too), and along the outline's
## edge stands a curtain this tall (m), drawn after bodies with no depth
## test, so the far rim shows past the boss's own body at 22 degrees. The
## curtain's alpha is the fill's times TELEGRAPH_CURTAIN_ALPHA, and
## TELEGRAPH_LOW_BOOST more under a pitch below TELEGRAPH_LOW_PITCH (the
## cone's low-pitch rule, 636, at the same degrees). A message without a
## shape, or one whose outline is not known here, draws the cells as
## before.
const TELEGRAPH_CURTAIN := 0.4
const TELEGRAPH_LOW_PITCH := 30.0
const TELEGRAPH_CURTAIN_ALPHA := 1.4
const TELEGRAPH_LOW_BOOST := 1.5
const TOSS := Color(1.0, 0.85, 0.4, 0.85)
const TOSS_LENGTH := 1.3
## A speech bubble's tail sits this far over a creature's head (just
## above its name).
const BUBBLE_OVER_HEAD := 0.55
## HP bars: units wide per hp of max hp, how tall, how high over the head,
## when the colour turns, how long after a fight one stays, how fast it fades.
const HP_BAR_PER_HP := 0.045
const HP_BAR_HEIGHT := 0.1
const HP_BAR_ABOVE := 0.1
const HP_AMBER := 0.5
const HP_RED := 0.25
const HP_GREEN_COLOR := Color(0.35, 0.85, 0.35)
const HP_AMBER_COLOR := Color(0.95, 0.7, 0.2)
const HP_RED_COLOR := Color(0.9, 0.2, 0.15)
const COMBAT_SECONDS := 4.0
const HP_BAR_FADE := 4.0
## Death: the fall (with its bounce), the flash, how long the body lies,
## the sink into the floor, and how far it sinks; a lantern's drop and how
## long it takes to go out.
const FALL_SECONDS := 0.3
const FALL_LIFT := 0.28
const FLASH := Color(3.0, 3.0, 3.0)
const FLASH_SECONDS := 0.15
const CORPSE_SECONDS := 8.0
const SINK_SECONDS := 1.0
const SINK_DEPTH := 1.4
const LANTERN_OUT_SECONDS := 1.2
## A puppet whose entity went keeps this long, still, in case its death
## comes after it (the message and the despawn race).
const DEPARTED_SECONDS := 0.5
## The local player dead: the camera pulls back to this times its size and
## the colour drains to this saturation, over these times; back faster.
const MOURN_PULL_BACK := 1.4
const MOURN_SATURATION := 0.15
const MOURN_SECONDS := 3.0
const MOURN_RETURN_SECONDS := 0.5
## A swing's pitch: lighter bodies swing higher.
const SWING_PITCH_LIGHT := 1.2
const SWING_PITCH_HEAVY := 0.85
## A death's sound slot by the kind of body that fell (a monster's otherwise).
const DEATH_SOUNDS := {"monster": "sfx.goblin_death", "player": "sfx.death_player", "companion": "sfx.death_companion"}
## A swing pushes the body this far out toward the blow, and back.
const LUNGE := 0.3
## Knocked down: how far the body tips (radians), and how fast.
const DOWN_TILT := 1.4
const DOWN_TILT_SPEED := 9.0
## A shot's arrow: metres a second as drawn (its hit is heard as it arrives).
const SHOT_SPEED := 40.0
## A shot that strikes nobody stands in the ground this long, and one that
## meets a friend sticks in them as long (decision 456).
const SHOT_STUCK_SECONDS := 10.0
## An arrow's flight (_on_shot): into a body this high on it (times its
## model's scale); its head this far into what it sticks in; past a spent range
## on this far, falling to the ground, ARROW_SAG_SLOW times slower than its
## flight; off stone back ARROW_GLANCE, up ARROW_GLANCE_UP, turned
## ARROW_GLANCE_TURN, over ARROW_GLANCE_SECONDS.
const ARROW_CHEST := 1.1
const ARROW_BURY := 0.12
const ARROW_SAG := 1.8
const ARROW_SAG_SLOW := 1.6
const ARROW_GLANCE := 0.5
const ARROW_GLANCE_UP := 0.3
const ARROW_GLANCE_TURN := 2.2
const ARROW_GLANCE_SECONDS := 0.35
## An arrow while it flies (the coordinator: a hairline in the game's camera)
## is drawn ARROW_FLIGHT_GIRTH times its girth, a pale trail ARROW_TRAIL long
## tapering behind it (ARROW_TRAIL_ALPHA); both go as it comes to rest, so
## the arrow standing or lying is its true size (_rest_arrow).
const ARROW_FLIGHT_GIRTH := 2.5
const ARROW_TRAIL := 1.3
const ARROW_TRAIL_ALPHA := 0.3
## The bow's held creak (decision 475): its pitch, and its level over the
## slot's in dB, from no draw (x) to full (y).
const CREAK_PITCH := Vector2(0.85, 1.25)
const CREAK_DB := Vector2(-18.0, 0.0)
const LUNGE_SECONDS := 0.16
## Just above the floor, so the rings never z-fight with it.
const ON_FLOOR := 0.02

## Shape -> mesh factory; sizes from the scale table.
var _shapes := {
	"capsule": func() -> Mesh:
		var mesh := CapsuleMesh.new()
		mesh.radius = 0.3
		mesh.height = Iso.HEIGHTS["capsule"]
		return mesh,
	"cube": func() -> Mesh:
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * Iso.HEIGHTS["cube"]
		return mesh,
	"barrel": func() -> Mesh:
		var mesh := CylinderMesh.new()
		mesh.height = Iso.HEIGHTS["barrel"]
		mesh.top_radius = 0.35
		mesh.bottom_radius = 0.35
		return mesh,
	"sphere": func() -> Mesh:
		var mesh := SphereMesh.new()
		mesh.radius = Iso.HEIGHTS["sphere"] * 0.5
		mesh.height = Iso.HEIGHTS["sphere"]
		return mesh,
	"slab": func() -> Mesh:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, Iso.HEIGHTS["slab"], 0.9)
		return mesh,
	"flat": func() -> Mesh:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.9, Iso.HEIGHTS["flat"], 0.9)
		return mesh,
}

var _camera: Camera3D
var _camera_target := Vector3.ZERO
## The player as the camera follows them: a jump eased, a slide not
## (client3d/camera_ease.gd).
var _camera_ease: RefCounted = preload("res://client3d/camera_ease.gd").new()
## The camera's yaw now, and the diamond it rests at (or is settling on).
var yaw := 0.0
var _yaw_step := 0.0
## The yaw easing toward a diamond: from, to, how far along (1: at rest),
## and how: SINE_OUT (a drag's settle) or FLOW (an A/D release: a cubic
## that starts at _ease_velocity degrees a second and stops on the
## diamond), over _ease_seconds. Driven from _process, not a Tween, so it
## moves before Main's pick.
enum Ease { SINE_OUT, FLOW }
var _ease_from := 0.0
var _ease_to := 0.0
var _ease_t := 1.0
var _ease_curve := Ease.SINE_OUT
var _ease_velocity := 0.0
var _ease_seconds := SETTLE_SECONDS
## A/D: the way it is turning (0: not), and the diamond it set off from.
var _turning := 0.0
var _turn_from := 0.0
## WASD's middle drag: the yaw it started from, how far it has gone, and
## whether a release came while frozen (it settles when they unfreeze).
var _dragging := false
var _drag_base := 0.0
var _drag_offset := 0.0
var _settle_pending := false
## Held still by Main while a movement key is down.
var frozen := false
## The camera's tilt from horizontal now, in degrees; CAMERA_PITCH at rest.
var pitch := CAMERA_PITCH
## The wheel's zoom now and where it is easing to.
var zoom := 1.0
var _zoom_to := 1.0
## The click scheme's pan: how far the view is off the player (ground
## units), what it was when this drag began, and whether it is easing home.
var pan := Vector3.ZERO
var _pan_base := Vector3.ZERO
var _pan_home := false
## A W/S tilt springing back: from, and how far along (1: not springing).
var _tilt_from := CAMERA_PITCH
var _tilt_t := 1.0
## The pitch peek: held, how far in (0 at rest .. 1 full), and the spring
## back's start and progress (1: not springing).
var _peeking := false
var _peek := 0.0
var _peek_from := 0.0
var _peek_t := 1.0
## WASD: the camera's lean toward the cursor, in grid units (Main.camera_lean).
var _lead := Vector2.ZERO
var _room: Node3D
## Where the camera first looks (the level's centre).
var _centre := Vector2i.ZERO
## The ground (_build_ground). Each floor cell's index, its kind, and the
## shade last drawn on it [bright, warm]: shaded by the light and heat
## fields (_shade_floor) whenever World says they changed, only the cells
## that changed.
var _grounds: Dictionary[Vector2i, int] = {}
var _ground_kinds: Dictionary[Vector2i, String] = {}
var _ground_shades: Dictionary[Vector2i, Vector2] = {}
## A cell's shade by index, as drawn: bright, warm, a byte each.
var _cell_shades := PackedByteArray()
## Indoors, each cell's brightness (as _cell_shades') over the mask's
## cells, for the soft scatter (the global "floor_shade", its rect
## "floor_shade_rect"): the plants darken with the floor under them (580,
## terrain's side: they kept full light in the dark lair).
var _shade_image: Image
var _shade_texture: ImageTexture
## The corners: a vertex in the ground's meshes is a corner of one chunk at
## one height. For each, its chunk, its shade's byte in _ground_bytes, and
## the (up to 4, else -1) cells around it at its height, whose shades it
## averages. A cell's vertices (its corners in every chunk that has them)
## are _cell_vertices[_cell_vertex_start[i] .. _cell_vertex_start[i + 1]].
var _vertex_chunk := PackedInt32Array()
var _vertex_byte := PackedInt32Array()
var _vertex_cells := PackedInt32Array()
var _cell_vertex_start := PackedInt32Array()
var _cell_vertices := PackedInt32Array()
## Every chunk's attribute stream (CUSTOM0, the shade) one after another;
## a chunk's mesh, its first byte here and its length.
var _ground_bytes := PackedByteArray()
var _ground_meshes: Array[ArrayMesh] = []
var _chunk_byte_start := PackedInt32Array()
## The vertex attribute stream's stride and CUSTOM0's place in it.
var _ground_stride := 4
var _ground_custom := 0
var _shade_due := false
## The lights that may cast shadows (torches, carried lanterns), and the
## view they were last sorted for (_update_shadows).
var _shadow_lights: Array[OmniLight3D] = []
var _shadow_key := Vector3i(1 << 30, 0, 0)
var _shadow_checked := 0.0
## A new floor: every cell is shaded, whatever the fields say changed.
var _shade_all := true
## The flat stone boxes' material (its see-through copy from
## _see_through_of).
var _stone_opaque: StandardMaterial3D
## Wall edge key -> its piece; vertex -> its post.
var _walls: Dictionary[Vector3i, Node3D] = {}
## The wall edges drawn as a breach of rubble (_add_wall_run).
var _wall_breaches: Array[Vector3i] = []
## Each wall edge's set where it is not the map's (_walls_set, level.json
## "walls"): a building's outline is in its slot's wall_set (wood for
## homes, its variation whole and level enough for a roof); filled by
## whoever knows them before the room is built, or before rebuild_walls.
var _wall_sets: Dictionary[Vector3i, String] = {}
var _walls_set := DEFAULT_SET
## Wall edges drawn "broken" (a ragged stub, never under WALL_BROKEN_LOW of
## the cap; wall.<set>.straight_ruined when the set has its art) or
## "rubble" (a low bank, never a way through; wall.<set>.rubble when it
## has art), whatever their set; the sim's wall stands either way.
## Buildings fills and clears its own, then calls rebuild_walls.
var _wall_states: Dictionary[Vector3i, String] = {}
## Each floor cell's set where it is not the map's (_floors_set, level.json
## "floors", on its stone ground): a building's inside is its slot's
## floor_set. The floors' bytes as sent (FLOOR_SETS), a texel a cell.
var _floor_sets: Dictionary[Vector2i, String] = {}
var _floors_set := DEFAULT_SET
var _floor_bytes := PackedByteArray()
var _floor_mask: ImageTexture
## The edges in _wall_sets and cells in _floor_sets that are there for a
## building, and the cells in _dry_water that are there for a well.
var _building_walls: Array[Vector3i] = []
## How tall a building's walls stand where its slot says ("wall_height",
## the temple's 4.5 m), by edge; an edge not here is WALL_HEIGHT. Terrain's
## runs draw them so.
var _wall_heights: Dictionary[Vector3i, float] = {}
## A kind building's outline edges (489 amended): a cell of its pad, whose
## elevation its walls, posts and doors stand at whatever the ground outside.
var _pad_cell: Dictionary[Vector3i, Vector2i] = {}
## A kind building's wood wall edges, which stand on a stone plinth
## (_add_plinth).
var _plinths: Dictionary[Vector3i, bool] = {}
## The edges in _wall_states and _wall_sets that are there for a damaged
## building or a town wall (_show_state, _show_town_wall), and each town
## wall drawn: {town_id, walls, gates, rect, towers (vertex -> Node3D),
## shown: the look it has}.
var _state_walls: Array[Vector3i] = []
## The window edges whose outside is their run's -x: the piece turned half
## round (_dress_window).
var _window_flipped: Dictionary[Vector3i, bool] = {}
## A kind's window edges -> [its town's id, its building's code] (decision
## 566): whose window light a window there is (_dress_window): [town id,
## building code, its building standing] (_show_stage keeps the last).
var _window_code: Dictionary[Vector3i, Array] = {}
## The window lights drawn: [its glow node, its _window_code row] each
## (_update_lamps).
var _glows: Array[Array] = []
## Each town's buildings awake ({code: bool}, set_awake: economy's "town"
## message, npc's flag); a code not in it is lit by the hour.
var _awake: Dictionary[String, Dictionary] = {}
## The folds' beasts (640, set_folds): what to draw, and the node they are
## drawn under (in the room, so a rebuild frees them).
var _folds: Array = []
var _fold_sheep: Node3D
## A fold's beasts: the art, the most drawn whatever the count, where each
## stands ((across from the middle, in from the gate's fence) in metres:
## clear of the fence and the trough along the back) and how each is
## turned from the gate's way.
const FOLD_SHEEP := "creature.sheep"
const FOLD_SHEEP_MOST := 6
const FOLD_SPOTS: Array[Vector2] = [Vector2(-1.2, 2.0), Vector2(1.3, 2.6), Vector2(-0.3, 3.7), Vector2(1.9, 4.3),
	Vector2(-1.9, 4.1), Vector2(0.5, 1.3)]
const FOLD_YAWS: Array[float] = [0.4, 2.2, -1.1, 3.0, 1.2, -2.4]
## Seconds since the window lights were last looked at (LAMP_CHECK).
var _lamp_clock := 0.0
var _town_wall_sets: Array[Vector3i] = []
var _town_walls: Array[Dictionary] = []
var _building_floors: Array[Vector2i] = []
var _building_dry: Array[Vector2i] = []
## Water cells drawn as plain ground (a well's, whose rim stands round it):
## no surface, no sunk bed, no wet shore; their ground the land's beside
## them. The sim still has them as water. Filled the same way.
var _dry_water: Dictionary[Vector2i, bool] = {}
## The water under a bridge (terrain "bridged", decision 505): its bed's
## elevation (m), the stream's, not the deck's (_measure_streams).
var _bed_levels: Dictionary[Vector2i, float] = {}
## Fords (terrain "fords"): floor under a shallow sheet of the stream.
var _fords: Dictionary[Vector2i, bool] = {}
## Rocks (terrain "rocks", decision 513): no floor to the sim, but ground of
## their footing here, under a rock, and never a tree.
var _rocks: Dictionary[Vector2i, bool] = {}
## A solid building's cells (decision 550): land under its mesh, not floor,
## so no ground the relax moves (558: its edges are the ground's sides).
var _solid_cells: Dictionary[Vector2i, bool] = {}
var _posts: Dictionary[Vector2i, Node3D] = {}
## Door edge key -> the doorway node (jambs, lintel, hinge). A double
## door's two edges share theirs (decision 403).
var _doorways: Dictionary[Vector3i, Node3D] = {}
## Door edge key -> [its leaf's hinge, the leaf's open angle, whether the
## frame's own state_<name> nodes follow this edge's Door]: a door.single's
## "leaf"; a door.double's leaf_a or leaf_b, the one on this edge's half.
var _door_hinges: Dictionary[Vector3i, Array] = {}
## Door edge key -> the state_<name> nodes that follow its Door.
var _door_states: Dictionary[Vector3i, Array] = {}
## Entity instance id -> its puppet.
var _puppets: Dictionary[int, Node3D] = {}
var _hover: MeshInstance3D
## The ring at the feet of the body a standing swing would strike
## (stand_ring; the low-angle fight, combat's (c)).
var _stand_ring: MeshInstance3D
## The channel's ring (544, ui's side), one, on the body being brought back.
var _channel_ring: MeshInstance3D
## The bow's aim while drawn (the archery aim, ui's side; Jeff: "the game
## draws a semi circle for distance... the aim can move along at many
## degrees"): a flat semicircle on the ground round the archer, its middle
## on the aim, its radius the range step; the marker on it at the aim's
## angle; pips beside the marker, more at the short steps (harder).
var _aim_arc: MeshInstance3D
var _aim_mark: MeshInstance3D
var _aim_pips: Array[MeshInstance3D] = []
var _aim_arc_radius := -1.0
## The cone of flight (combat's design, ui's side): a flat wedge from the
## archer along the aim, as long as the step, its half-angle the sim's
## spread (World.spread_of: the server rolls the line inside it), the arc
## cut to its far end; the fill and the two side lines. _aim_cone_shown is
## the half-angle drawn now, eased toward the sim's; -1 while no cone.
var _aim_cone: MeshInstance3D
var _aim_cone_rim: MeshInstance3D
var _aim_arc_lift := 0.0
## The archer's grid point the ring was last built from (the ground under
## it differs from cell to cell).
var _aim_arc_origin := Vector2(INF, INF)
var _aim_cone_shown := -1.0
var _aim_arc_span := -1.0
## The archer's aim lead (decision 617; Jeff: "archers should be able to
## zoom out further"): while the bow is drawn the view slides off the
## archer toward the aim, eased like the pan, held with the WASD lean to
## AIM_LEAD_CELLS in all; back onto the archer when the bow lowers.
var _aim_lead := Vector3.ZERO
var _aim_lead_to := Vector3.ZERO
var _aim_arc_angle := -1000.0
## The bosses' ground telegraphs (combat's 602, ui's side; Jeff: "a small
## red cone on the ground indicates the area"): id -> {quads, from, lands,
## landed_at}; one flat quad per cell that will be hit, filling toward
## lands_tick, a flash on landing.
var _telegraphs: Dictionary = {}
var _cell_quad: ArrayMesh
## The outline's passes (the first; each the next's next_pass), the
## outlined puppet (null: none), and each body material's copy that marks
## the stencil, by the material.
var _outline: ShaderMaterial
var _seen_through: ShaderMaterial
var _outlined: Node3D
var _marking: Dictionary[Material, Material] = {}
var _toss: MeshInstance3D
var _ring_mesh: ArrayMesh
## Main's speech bubbles, for last words.
var bubbles: SpeechBubbles
## Main: Alt is held, so every HP bar shows.
var show_all_bars := false
## Entity instance id -> when it was last in a fight (msec), and its hp as
## last seen.
var _combat_at: Dictionary[int, int] = {}
## Puppet id -> [msec, what it swung with] of its last swing: a blow that
## lands soon after, beside it, was its (_struck_with).
var _swings: Dictionary[int, Array] = {}
## Each pile's things as last drawn: what came or went is heard
## (_pile_sounds). Quiet till this msec after the piles are drawn anew (a
## zone's piles coming and going are no one's doing).
var _pile_ids: Dictionary = {}
var _piles_quiet_until := 0
## Each door's hp as last drawn: a blow on it is heard (_sync_doors).
var _door_hp: Dictionary[Vector3i, int] = {}
## A thing that slid this far, or a body pushed, lands this long after.
const SLIDE_SECONDS := 0.35
## A swing's blow lands within this many ms of it, this many cells off.
const BLOW_AFTER_MS := 700
const BLOW_REACH := 2
## A person grunts with one swing in this many, and a goblin cries out at
## one blow in this many (a grunt every time wears thin).
const EFFORT_EVERY := 3
const PAIN_EVERY := 2
## A goblin standing idle mutters every so often (s, picked between these).
const CHATTER_SECONDS := Vector2(8.0, 25.0)
var _last_hp: Dictionary[int, int] = {}
## Entity instance id -> its tile as last seen, for footsteps.
var _last_tile: Dictionary[int, Vector2i] = {}
## Tall grass trampled just now (decision 508): cell -> when (ms), so the
## step that flattens it still rustles, whether the "grass" news comes
## before the step or after it.
var _flattened: Dictionary[Vector2i, int] = {}
const FLATTENED_MS := 1000
## Arrows in flight (_on_shot): {end: its last cell, arrive: msec, heard:
## whether a body's hit or guard was heard for it}; what stopped one that
## hit no body is heard as it arrives (_arrow_landed).
var _arrows: Array[Dictionary] = []
## Entity name -> the "death" message, for an entity still here when it
## came; it falls when it goes.
var _pending_deaths: Dictionary[String, Dictionary] = {}
## A breakable thing's name -> the slot it breaks with (SoundKit.breaking),
## noted when it is drawn: its death says only that it was an object.
var _break_sounds: Dictionary[String, String] = {}
## Entity name -> {"puppet", "at"}: puppets whose entity went, kept a moment.
var _departed: Dictionary[String, Dictionary] = {}
## Door edge key -> open, as last seen, for their sounds.
var _door_open: Dictionary[Vector3i, bool] = {}
## Door edge -> the instance id of the Door node last shown there: a door
## that comes back into a player's interest (decision 217) is a new node,
## and its state is not a change to sound.
var _door_node: Dictionary[Vector3i, int] = {}
## The doors whose leaf may have to move or show (World.door_shown, or a new
## room): _sync_doors looks at these alone, till each is still.
var _doors_due: Dictionary[Vector3i, bool] = {}
## The puppets of entities too far off to keep up (_sync_puppets).
var _far: Dictionary[int, bool] = {}
## The local player's entity name while there is one.
var _local_name := ""
## The local player's death: 0 alive .. 1 fully mourned.
var _mourning := false
var _mourn := 0.0
## The local player lying downed (Mortally Wounded, 587): the colour
## drains as in mourning, over the same times, and the camera stays
## (_update_mourning). Jeff, v0.1.169: "the mortally wounded screen
## doesn't go gray like it was meant to."
var _down := 0.0
var _environment: Environment
var _listener: AudioListener3D
var sfx: Sfx
## The beds under it all: forest, wind, rain, dungeon, town (Ambience).
var ambience: Ambience
## The music over it: layers by zone, time and tension, and stingers (Music).
var music: Music
## The local player's heart while Mortally Wounded, over the ducked mix (587).
var heartbeat: Heartbeat
## Bandaging heard: a cloth ruffle from each bandager while it runs.
var bandaging: Bandaging
## The cells fire burns on, torches (_add_torch) and fires (_add_fire),
## for their crackle (Ambience).
var torch_cells: Array[Vector2i] = []
var _hp_bar_shader: Shader
var _terrain: Dictionary = {}
var _sun: DirectionalLight3D
var _outdoor := false
## The low-horizon camera is on now (decision 623): Net.camera_low and
## outdoors.
var _low := false
## Fire's drawn lights (decision 523): [light, its energy, its phase, how far
## it swings], flickered and faded by day each frame (_flicker_fires), on
## the view's own clock (_fire_time, accumulated frame time).
var _fire_lights: Array[Array] = []
var _fire_time := 0.0
## Outdoors: the sky, and the step of the day (SKY_STEPS) it shows, -1 for
## none yet.
var _sky_material: ProceduralSkyMaterial
var _sky_step := -1
## The sky's look at that step (sky_look), before the weather; the light
## by day there (0..1); the weather drawn (decision 309).
var _look := {}
var _look_daylight := 0.0
## The haze's density (look's own, the weather's share), for _set_haze.
var _haze := Vector2.ZERO
var _weather_view: WeatherView
## The canopy's cover round the view, eased (0..1), the way to the sun in
## the view's directions, and the shafts (null where there is no canopy).
var _canopy_cover := 0.0
var _toward_sun := Vector3.UP
var _shafts: Node3D
## The ground's material, and the sky's light on its floor (its sky_floor:
## 0 indoors).
var _ground_shader_material: ShaderMaterial
var _sky_floor := 0.0
## The cliff faces' material: the same sky light (decision 513 amended).
var _cliff_material: ShaderMaterial
## Floor and water cells: the land the forest stands around.
var _land: Dictionary[Vector2i, bool] = {}
## The ground's elevation (decision 525): terrain "relief", metres a cell
## row by row over _relief_size cells; empty for a terrain with none (a
## glimpse's, a test's), whose cells stand at their whole levels.
var _relief := PackedFloat32Array()
var _relief_size := Vector2i.ZERO
## Whether the level gave its relief (relief.png): then its water's surface
## follows its cells (a stream's slopes down its path) and its bed sinks
## under it; a level with none keeps its water as before.
var _relief_given := false
## Water and fords as the ground draws them (wet: their ground is a bed under
## the surface).
var _wet: Dictionary[Vector2i, bool] = {}
## The drawn ground's highest and lowest corner (m), for picking.
var _ground_top := 0.0
## The ground's material, told the relief light's way as the camera turns
## (slope_shade), and the yaw it was last told for.
var _ground_look: ShaderMaterial
var _hillshade_yaw := NAN
var _ground_bottom := 0.0
## Each ground cell's four corners (metres, GROUND_CORNERS order) as the
## mesh draws them (_build_ground): Relief.corner_heights, a ramp's or a
## stream bed's where those apply. _height_in reads them.
var _corners: Dictionary[Vector2i, PackedFloat32Array] = {}
## Corners where a stair's ramp sets them: the stair's high side up to the
## cell it climbs to, and the cells round it (_shape_ramps).
var _ramp_heights: Dictionary[Vector2i, PackedFloat32Array] = {}
## Stairs up onto a dais (by the way each climbs), flat under dais.steps;
## _height_in walks them up the steps.
var _dais_stairs: Dictionary[Vector2i, Vector2i] = {}
## The camera's pitch while a ridge would hide the player (_ridge_lift),
## eased; 0 when none.
var _ridge_pitch := 0.0
## How far the sight-line cut-out is in (0..1), eased (_update_sight).
var _sight_cut := 0.0
## Whether the ground hides the player, worked out for _sight_key (their
## place and the camera's angle).
var _sight_hidden := false
var _sight_key := Vector4.INF
## Where the map's water is, a texel a cell (_build_ground), for the ground's
## wet shore and the water's own; its first cell and size; the bodies drawn.
var _water_mask: ImageTexture
## The shore field (decision 553, shore_image): SHORE_RES texels a cell
## over the water mask's cells, the water's edge where it is a half; its
## image too, for what stands on the ground (shore_at).
var _shore_mask: ImageTexture
## The water's depth (559, terrain's side): half the distance into it, out
## to two cells, at the shore field's texels (_water_depth, _curve_field).
var _depth_image: Image
var _depth_mask: ImageTexture
var _shore_image: Image
## The shore's cells drawn finer (decision 553, _shore_band): each one's
## heights, (SHORE_RES + 1) squared row by row.
var _shore_heights: Dictionary[Vector2i, PackedFloat32Array] = {}
## The streams' own cells (decision 557, _streams_cells) and their ribbons.
var _stream_cells: Dictionary[Vector2i, bool] = {}
## The waters as curves (559, terrain's side, _read_curves): each one's
## curve, closed, surface and shallows; their cells (-> which water); each
## cell near one -> (which water, its nearest sample).
var _curve_waters: Array[Dictionary] = []
var _curve_cells: Dictionary[Vector2i, int] = {}
var _curve_near_sample: Dictionary[Vector2i, Vector2i] = {}
## A cell near more than one water (where a stream meets a river): the
## others' (which water, its nearest sample), so the field is their union.
var _curve_near_also: Dictionary[Vector2i, Array] = {}
## The segments worth searching from a cell (_near_segments), as found:
## (cell, which curve, its nearest sample) -> each segment's first sample;
## the waters', the roads' and the forest edge's (by cell alone).
var _curve_kept: Dictionary[Vector4i, PackedInt32Array] = {}
var _road_kept: Dictionary[Vector4i, PackedInt32Array] = {}
var _edge_kept: Dictionary[Vector2i, PackedVector2Array] = {}
## The roads as curves (563, terrain's side, _read_roads): each one's
## curve and kind; their cells (-> which road); each cell near one ->
## (which road, its nearest sample); their field (_road_field).
var _road_curves: Array[Dictionary] = []
var _road_cells: Dictionary[Vector2i, int] = {}
var _road_near_sample: Dictionary[Vector2i, Vector2i] = {}
var _road_near_also: Dictionary[Vector2i, Array] = {}
## The forest's edge as closed curves (decision 575, _read_edges): each
## {curve: Curves.sample's, closed}; each cell near one -> (which, its
## nearest sample); the others'; its field (_edge_field) for the ground.
var _edge_curves: Array[Dictionary] = []
var _edge_near_sample: Dictionary[Vector2i, Vector2i] = {}
var _edge_near_also: Dictionary[Vector2i, Array] = {}
var _edge_mask: ImageTexture
## The barrow's niches by their wall edge (608, terrain's side, terrain
## "niches"): {cell, out, kind, variant}; the hidden niches' door pieces by
## their edge: [cracked, open, its draft].
var _niche_at: Dictionary[Vector3i, Dictionary] = {}
var _hidden_niches: Dictionary[Vector3i, Array] = {}
## The ledges as curves (585, terrain's side, maps' terrain "ledges"): each
## {curve: Curves' sample with tops and feet, closed, up: 1 if its high side
## is right of its way (y down), else -1}; each cell near one -> (which, its
## nearest sample) and the others'; each cell the curve splits ->
## {up: whether its own middle is the high side's, across: the cell whose
## plane draws its other side, parts: [[polygon, own], ...]}.
var _ledge_curves: Array[Dictionary] = []
var _ledge_near_sample: Dictionary[Vector2i, Vector2i] = {}
var _ledge_near_also: Dictionary[Vector2i, Array] = {}
var _ledge_split: Dictionary[Vector2i, Dictionary] = {}
var _road_image: Image
var _road_mask: ImageTexture
var _stream_ribbons: Array[MeshInstance3D] = []
## Built water (decision 595): water no "waters" curve lays and no stream's
## path, a stone basin, a well's or a cistern's cells; drawn square and still
## (_build_water), never rounded, its own field none.
var _built_water: Dictionary[Vector2i, bool] = {}
## Each tall fall's foot (570 amended, terrain's side): {at (the foot's
## middle on the water), across, down (the stream's way, flat), width,
## drop}, from _build_curve_ribbon; its mist (_build_mists).
var _fall_feet: Array[Dictionary] = []
var _mists: Array[GPUParticles3D] = []
## Where the streams fall (decision 557): {cell: Vector2i, drop: float}
## each, the cell below the step; a new array each build (sound's ambience
## tells a new level by it).
var stream_falls: Array[Dictionary] = []
## How far each void cell outdoors is from the land, out to FOREST_REACH
## (_measure_forest); the ground's cells in index order, and where its
## forest ones (after floor and water) begin.
var _forest_distance: Dictionary[Vector2i, int] = {}
var _ground_cells: Array = []
var _ground_water_end := 0
var _ground_floor_end := 0
## Scatter (_grow_scatter): each chunk's ground cells (indices), the chunks
## scattered, those due near the view (nearest first), and the chunk the
## view was over when they were sorted.
var _scatter_chunks: Dictionary[Vector2i, PackedInt32Array] = {}
var _scattered: Dictionary[Vector2i, bool] = {}
var _scatter_due: Array[Vector2i] = []
var _scatter_aim := Vector2i(1 << 30, 0)
var _scatter_reach_at := -1.0
## The scatter's reach under the low camera (LOW_SCATTER_REACH; benches set
## it).
var scatter_reach_low := LOW_SCATTER_REACH
## Planned scatter still to make, a [chunk, kind, items] a frame.
var _scatter_jobs: Array[Array] = []
## Tall grass (decision 508, terrain's side): its cells, and where each
## cell's clumps were drawn ([MultiMesh, index], ...), so a cell trampled
## or standing again is redrawn without the rest of its chunk, and the
## cells drawn flat now.
var _tall: Dictionary[Vector2i, bool] = {}
var _tall_where: Dictionary[Vector2i, Array] = {}
var _tall_flat: Dictionary[Vector2i, bool] = {}
var _mask_origin := Vector2i.ZERO
var _mask_size := Vector2i.ONE
## The canopy over this map (decision 466; Fields.canopy_at, from the same
## level data): each cell's cover in one R8 texel, on the ground mask's
## grid, the texel at (0, 0) being cell canopy_origin; null where the map
## has no canopy. Read by environment's look and the ground.
var canopy_texture: ImageTexture
var canopy_origin := Vector2i.ZERO
var _water_bodies: Array[MeshInstance3D] = []
## Each rock face drawn: [the cell above, the direction it faces].
var _cliff_edges: Array[Array] = []
var _trees: Dictionary[Vector2i, Node3D] = {}
## Past the forest, outdoors: its canopy and far floor (TerrainBorder),
## under the room; null indoors or where level.json says "border": "none".
var _border: TerrainBorder
## A grown forest's trees (decision 467) where the level has a canopy and
## a trees.json: null elsewhere. The void cells under their trunks, which
## the forest's ring leaves to them and the ground runs under.
var _grown: GrownTrees
var _grown_trunks: Dictionary[Vector2i, bool] = {}
## Glimpses of the levels past this one's ways out (decision 327): each
## planned ({to, terrain: the target's cells nearest us, moved into ours,
## cells: theirs and the lane to them}) before the forest is measured, so
## the forest grows round them, then drawn by a view of their own; the
## cells the forest grows round (the land and the glimpses); whether this
## view is a glimpse (built only: no camera, puppets, picks or light).
var _glimpse_plans: Array[Dictionary] = []
var _glimpses: Array[Client3D] = []
var _wooded: Dictionary[Vector2i, bool] = {}
var _glimpse := false
## The saplings at the forest's edge (_add_sapling), faded as trees are.
var _saplings: Dictionary[Vector2i, Node3D] = {}
## The felled cells as drawn (591, terrain's side): cell -> stage; each
## one's props (a stump, a bush, saplings).
var _clearing: Dictionary[Vector2i, String] = {}
var _clearing_props: Dictionary[Vector2i, Array] = {}
## Cells felled at the build that have grown back to trunks since: the void
## again, though _land (fixed for the build) still holds them.
var _grown_back: Dictionary[Vector2i, bool] = {}
## Each scattered chunk's MultiMeshes, so one chunk is drawn again alone.
var _scatter_nodes: Dictionary[Vector2i, Array] = {}
## The ground's kinds texture (a texel a cell) and its image, so one cell's
## kind changes alone.
var _kinds_image: Image
var _kinds_texture: ImageTexture
## Each building drawn (_add_buildings): {rect: its footprint, node: the
## slot's instance, roof: its "roof" part (null if it has none), off: the
## roof hidden as the local player is inside}; which building each
## footprint cell is in; the roofs off now and when each was last wanted off.
var _buildings: Array[Dictionary] = []
## The laid plots drawn (591 amended (step 2)), by their rect's corner:
## what _sync_plots adds or drops.
var _plots_drawn: Dictionary[Vector2i, bool] = {}
## A building's record states in decline (649, economy's Towns.buildings_of):
## out of use, a ruin, gone (the ruin over: its piece no more).
const DECLINE_GONE := "gone"
const DECLINES: Array[String] = [Towns.DISREPAIR, Towns.RUIN, DECLINE_GONE]
## Weeds at a building's foot in decline: one an outline edge in this many.
const WEED_EVERY := 2
## Weeds this far from an edge's middle (out of a building in disrepair,
## into a ruin's footprint).
const WEED_OUT := 0.35
## A ruin's wall edges, by their hash, one in RUIN_GAP_EVERY a gap, the
## next RUIN_STUBS of every RUIN_GAP_EVERY a ragged stub ("broken"), the
## rest a low bank of rubble; one of its floor's cells in RUIN_BOARDS_KEPT
## keeps its boards, the rest bare ground.
const RUIN_GAP_EVERY := 5
const RUIN_STUBS := 2
const RUIN_BOARDS_KEPT := 2
## A ruin's litter, by a cell's hash, one in RUIN_LITTER_EVERY: a rubble
## heap, fallen planks, a stone, a weed through the floor, in turn.
const RUIN_LITTER_EVERY := 3
## A ruin's plinth (489 amended) broken off: each half edge's top between
## these shares of PLINTH_HEIGHT, by its roll; one edge in RUIN_SPILL_EVERY
## has a stone spilled off it to one side, this far out from its face.
const RUIN_PLINTH_LOW := 0.25
const RUIN_PLINTH_HIGH := 0.9
const RUIN_SPILL_EVERY := 3
const RUIN_SPILL_OUT := 0.35
## A ruin's wall edges (649): no post stands for them.
var _ruin_edges: Dictionary[Vector3i, bool] = {}
var _building_at: Dictionary[Vector2i, int] = {}
## Where a body stands on a cell whose piece has a stand point (580 step 3:
## the throne's "stand", [x, y up, z] in the piece's frame, turned by its
## yaw): the offset from the cell's middle; a cell not in it, its middle.
var _stand_at: Dictionary[Vector2i, Vector3] = {}
var _roofs_off: Dictionary[int, float] = {}
## Town id -> {kind: {state, level}}, as Main was told (set_town).
var town_states := {}
## Level -> its damaged roofs' indices, as Main was told (set_roofs,
## decision 383).
var roof_states := {}
## For each wall and doorway edge, the pieces of its run (_wall_runs), as
## the occluders were indexed.
var _runs: Dictionary[Vector3i, Array] = {}
## Each GroundPile's heap of things (_show_piles), under the room.
var _pile_nodes: Dictionary[GroundPile, Node3D] = {}
var _pile_ring_mesh: Mesh
var _see_through: Dictionary[Material, Material] = {}
## [piece, its bounds, is a tree, the pieces that fade with it], for every
## wall, doorway frame, post and tree, made once per room; the pieces
## faded now, those hiding them as last worked out and what for, and when
## each piece last hid them (_fade_clock).
var _occluders: Array[Array] = []
var _occluders_built := false
## Which of _occluders' bounds touch each FADE_CHUNK square (flat, x and z),
## and the highest top of any.
var _occluder_chunks: Dictionary[Vector2i, Array] = {}
var _occluder_top := 0.0
var _faded: Dictionary[Node3D, bool] = {}
var _hiding: Dictionary[Node3D, bool] = {}
var _hid_at: Dictionary[Node3D, float] = {}
var _fade_key := ""
## Seconds of frames drawn, for FADE_HOLD.
var _fade_clock := 0.0


## Builds the room and the rig. [param terrain] is Terrain.parse's result,
## the same the 2D view paints from.
func setup(terrain: Dictionary, centre := Vector2i.ZERO) -> void:
	_terrain = terrain
	_centre = centre
	_ring_mesh = _make_ring(0.42, 0.5)
	_build_environment()
	_apply_sky()
	_build_camera()
	_build_room()
	_hover = _make_flat(_make_square_outline(HOVER_HALF, HOVER_LINE), HOVER)
	_hover.visible = false
	add_child(_hover)
	_channel_ring = _make_flat(_make_square_outline(HOVER_HALF, HOVER_LINE), Color(UiTheme.color("brass_bright"), 0.9))
	_channel_ring.visible = false
	add_child(_channel_ring)
	_stand_ring = _make_ring_instance(Color(UiTheme.color("brass_bright"), 0.85))
	_stand_ring.visible = false
	add_child(_stand_ring)
	_aim_arc = _make_flat(_make_arc(1.0, AIM_LINE), Color(UiTheme.color("brass_bright"), 0.8))
	_aim_arc.visible = false
	add_child(_aim_arc)
	_aim_cone = _make_flat(ArrayMesh.new(), Color(UiTheme.color("brass_bright"), AIM_CONE_FILL))
	_aim_cone.visible = false
	add_child(_aim_cone)
	_aim_cone_rim = _make_flat(ArrayMesh.new(), Color(UiTheme.color("brass_bright"), 0.8))
	_aim_cone_rim.visible = false
	add_child(_aim_cone_rim)
	_aim_mark = _make_flat(_make_ring(0.0, AIM_MARK), Color(UiTheme.color("brass_bright"), 0.95))
	_aim_mark.visible = false
	add_child(_aim_mark)
	for i in AIM_PIPS_MOST:
		var pip := _make_flat(_make_ring(0.0, AIM_PIP), Color(UiTheme.color("brass_bright"), 0.95))
		pip.visible = false
		add_child(pip)
		_aim_pips.append(pip)
	var outline_shader := Shader.new()
	outline_shader.code = OUTLINE_SHADER
	var after: ShaderMaterial = null
	for way: Vector2i in World.DIRECTIONS:
		var pass_ := ShaderMaterial.new()
		pass_.shader = outline_shader
		pass_.set_shader_parameter("colour", TARGET_OUTLINE)
		pass_.set_shader_parameter("nudge", Vector2(way).normalized() * TARGET_PIXELS)
		pass_.set_shader_parameter("nearer", OUTLINE_NEARER)
		pass_.next_pass = after
		after = pass_
	_outline = after
	var seen_shader := Shader.new()
	seen_shader.code = OUTLINE_SHADER.replace("depth_draw_never;", "depth_draw_never, depth_test_disabled;")
	after = null
	for way: Vector2i in World.DIRECTIONS:
		var pass_ := ShaderMaterial.new()
		pass_.shader = seen_shader
		pass_.set_shader_parameter("colour", SEEN_OUTLINE)
		pass_.set_shader_parameter("nudge", Vector2(way).normalized() * TARGET_PIXELS)
		pass_.set_shader_parameter("nearer", OUTLINE_NEARER)
		pass_.next_pass = after
		after = pass_
	_seen_through = after
	_toss = _make_flat(_make_arrow(TOSS_LENGTH), TOSS)
	_toss.visible = false
	add_child(_toss)
	_hp_bar_shader = preload("res://client3d/hp_bar.gdshader")
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	ambience = Ambience.new()
	ambience.name = "Ambience"
	ambience.view = self
	add_child(ambience)
	music = Music.new()
	music.name = "Music"
	music.view = self
	add_child(music)
	heartbeat = Heartbeat.new()
	heartbeat.name = "Heartbeat"
	heartbeat.view = self
	add_child(heartbeat)
	bandaging = Bandaging.new()
	bandaging.name = "Bandaging"
	bandaging.view = self
	add_child(bandaging)
	# Sounds are heard from the player's place: the camera is 40 units off.
	_listener = AudioListener3D.new()
	_listener.name = "Listener"
	add_child(_listener)
	_listener.make_current()
	# The saved diamond, or --test-yaw exactly, for screenshots.
	yaw = Net.camera_yaw
	_yaw_step = nearest_diamond(yaw)
	pitch = rest_pitch()
	if not Net.camera_low_changed.is_connected(_on_camera_low_changed):
		Net.camera_low_changed.connect(_on_camera_low_changed)
	zoom = clampf(Net.camera_zoom, ZOOM_MIN, ZOOM_MAX)
	_zoom_to = zoom
	_apply_size()
	_place_camera()
	_classify_walls()
	_start_warm_ups()


func _process(delta: float) -> void:
	_end_warm_ups()
	_sync_puppets()
	_update_seen_through()
	_sync_doors()
	_ease_yaw(delta)
	_ease_peek(delta)
	_ease_tilt(delta)
	_ease_zoom(delta)
	_ease_pan(delta)
	_follow(delta)
	_fade_clock += delta
	_update_fade()
	_lamp_clock += delta
	if _lamp_clock >= LAMP_CHECK:
		_lamp_clock = 0.0
		_update_lamps()
	_update_grown()
	_update_shadows()
	_update_sky(delta)
	_grow_scatter()
	_drop_departed()
	_update_mourning(delta)
	_flicker_fires(delta)


# --- Rig ---------------------------------------------------------------------

func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = BACKGROUND
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.name = "Environment"
	world_environment.environment = environment
	add_child(world_environment)
	environment.adjustment_enabled = true
	_environment = environment

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = SUN
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55.0, 160.0, 0.0)
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = SHADOW_DISTANCE
	sun.shadow_blur = SUN_SHADOW_BLUR
	RenderingServer.directional_shadow_atlas_set_size(SUN_SHADOW_SIZE, true)
	add_child(sun)
	_sun = sun
	_weather_view = WeatherView.new()
	add_child(_weather_view)


## The dark under-stone look, or outdoors the sky on the world clock
## (_update_sky): its light, the sun or the moon.
func _apply_sky() -> void:
	_outdoor = bool(_terrain.get("outdoor", false))
	_sky_step = -1
	_environment.fog_enabled = false
	_set_sky_floor(0.0)
	_weather_view.set_outdoor(_outdoor)
	if _outdoor:
		_sky_material = ProceduralSkyMaterial.new()
		_sky_material.ground_horizon_color = FOREST_FLOOR.lightened(0.2)
		_sky_material.ground_bottom_color = FOREST_FLOOR
		var sky := Sky.new()
		sky.sky_material = _sky_material
		_environment.sky = sky
		_environment.background_mode = Environment.BG_SKY
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.fog_enabled = true
		_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		_environment.fog_sky_affect = 0.0
		_update_sky(0.0)
	else:
		_sky_material = null
		_sun.rotation_degrees = Vector3(-55.0, 160.0, 0.0)
		_environment.background_mode = Environment.BG_COLOR
		_environment.background_color = BACKGROUND
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var look: Array = ZONE_LOOK.get(str(_terrain.get("zone", "indoors")), ZONE_LOOK["indoors"])
		_environment.ambient_light_color = look[0]
		_environment.ambient_light_energy = look[1]
		_sun.light_color = SUN
		_sun.light_energy = SUN_ENERGY
		# A damp level (580, terrain's side): darker and colder, a faint
		# haze in the lanterns' light.
		if bool(_terrain.get("damp", false)):
			_environment.ambient_light_color = (look[0] as Color).lerp(DAMP_COLD, 0.6)
			_environment.ambient_light_energy = float(look[1]) * DAMP_AMBIENT
			_environment.fog_enabled = true
			_environment.fog_mode = Environment.FOG_MODE_EXPONENTIAL
			_environment.fog_light_color = DAMP_FOG
			_environment.fog_density = DAMP_FOG_DENSITY
			_environment.fog_sky_affect = 0.0
	# The carried lanterns at this level's reach (580).
	for puppet: Node3D in _puppets.values():
		var lantern := puppet.get_node_or_null("Lantern") as OmniLight3D
		if lantern != null:
			_size_lantern(lantern)


## A carried lantern's light as this level has it (580, terrain's side):
## its reach the sim's (Fields.carried_reach: half on a damp level) over
## PLAYER_LIGHT_RANGE, dimmer when damp.
func _size_lantern(light: OmniLight3D) -> void:
	var damp := bool(_terrain.get("damp", false))
	light.omni_range = PLAYER_LIGHT_RANGE * Fields.carried_reach(damp) / float(Fields.CARRIED_REACH)
	light.light_energy = 1.2 * (DAMP_LANTERN if damp else 1.0)


## The cells' brightness for the soft scatter (580, terrain's side): an L8
## image over the mask's cells, full until _shade_floor writes each one,
## published as the global "floor_shade" with its rect (origin, size in
## cells) indoors by the main view; outdoors (the sky lights the plants)
## or in a glimpse, none (the rect's size 0).
func _publish_floor_shade() -> void:
	_shade_image = null
	_shade_texture = null
	if _glimpse:
		return
	if _outdoor or _mask_size.x <= 0 or _mask_size.y <= 0:
		RenderingServer.global_shader_parameter_set("floor_shade_rect", Vector4.ZERO)
		return
	_shade_image = Image.create(_mask_size.x, _mask_size.y, false, Image.FORMAT_L8)
	_shade_image.fill(Color.WHITE)
	_shade_texture = ImageTexture.create_from_image(_shade_image)
	RenderingServer.global_shader_parameter_set("floor_shade", _shade_texture)
	RenderingServer.global_shader_parameter_set("floor_shade_rect", Vector4(_mask_origin.x, _mask_origin.y, _mask_size.x, _mask_size.y))


## The floor's brightness, a share of its colour, for [param light] on it
## (Fields): FLOOR_DARKEST in the dark, full from FLOOR_LIGHT_HIGH.
static func floor_brightness(light: float) -> float:
	return lerpf(FLOOR_DARKEST, 1.0, smoothstep(FLOOR_LIGHT_LOW, FLOOR_LIGHT_HIGH, light))


## The cliff faces' sky_floor for the floor's [param level] (decision 513
## amended): the same outdoors, so a face is as dark as the ground at night;
## 1 indoors (level 0), the faces as before.
static func cliff_sky(level: float) -> float:
	return level if level > 0.0 else 1.0


## The sky's light on the outdoor floor, as a brightness (0 indoors); under
## a full canopy [param roof] (the same if under 0).
func _set_sky_floor(level: float, roof := -1.0) -> void:
	_sky_floor = level
	if _ground_shader_material != null:
		_ground_shader_material.set_shader_parameter("sky_floor", level)
		_ground_shader_material.set_shader_parameter("sky_floor_roof", level if roof < 0.0 else roof)
	if _cliff_material != null:
		_cliff_material.set_shader_parameter("sky_floor", cliff_sky(level))
	for view in _glimpses:
		view._set_sky_floor(level, roof)


## Outdoors: the sky, its light and the sun or moon as the world clock
## stands (DayNight), moved on a game minute at a time (SKY_STEPS), under
## the weather (decision 309: eased every frame, drawn when it changes).
func _update_sky(delta: float) -> void:
	if not _outdoor or _sky_material == null:
		return
	var at := DayNight.fraction(DayNight.now())
	var step := floori(at * SKY_STEPS) % SKY_STEPS
	var weathered := _weather_view.ease_toward(World.fields.weather, delta)
	var season := Season.at(World.fields.region, DayNight.now())
	_weather_view.set_season(season)
	var covered := _ease_canopy(delta)
	if _camera != null:
		var ahead := -_camera.global_transform.basis.z
		_weather_view.set_view(_low, _camera.global_position, Vector2(ahead.x, ahead.z))
	_weather_view.place(_camera_target, delta, _look.get("weather_fog", SKY_HORIZON), _look_daylight, _level_direction)
	_set_haze()
	if _shafts != null:
		_shafts.place(_camera_target, _toward_sun, LightShafts.strength_for(_look_daylight, _weather_view.weather))
	if step == _sky_step and not weathered and not covered:
		return
	if step != _sky_step:
		_sky_step = step
		var fraction := float(step) / SKY_STEPS
		var elevation := DayNight.elevation_at(fraction)
		_look = sky_look(elevation).duplicate()
		_look_daylight = smoothstep(DayNight.TWILIGHT_LOW, DayNight.TWILIGHT_HIGH, elevation)
		# The moon by night, opposite the sun; either casts from its
		# height lifted (shadow_elevation), from where it stands round.
		var toward := DayNight.sun_at(fraction)
		_toward_sun = _level_direction(toward).normalized()
		if elevation < MOON_BELOW:
			toward = -toward
		var round_by := Vector2(toward.x, toward.z).normalized()
		var lifted := deg_to_rad(shadow_elevation(rad_to_deg(asin(clampf(toward.y, -1.0, 1.0)))))
		toward = Vector3(round_by.x * cos(lifted), sin(lifted), round_by.y * cos(lifted))
		_sun.shadow_opacity = SHADOW_STRENGTH * smoothstep(0.0, SHADOW_FADE, absf(elevation - MOON_BELOW))
		_sun.basis = Basis.looking_at(-_level_direction(toward.normalized()), Vector3.UP)
	var look := canopied_look(weathered_look(seasoned_look(_look, season), _weather_view.weather),
			_canopy_cover * World.fields.canopy_shade / DayNight.CANOPY_SHADE)
	_look["weather_fog"] = look["fog"]
	_sky_material.sky_top_color = look["top"]
	_sky_material.sky_horizon_color = hazed_horizon(look, _weather_view.weather) if _low else look["horizon"]
	_environment.ambient_light_color = look["ambient"]
	_environment.ambient_light_energy = look["ambient_energy"]
	_environment.fog_light_color = look["fog"]
	_haze = Vector2(float(look["fog_density"]) - float(look["fog_weather"]), look["fog_weather"])
	_set_haze()
	_environment.fog_height = look["fog_height"]
	_environment.fog_height_density = look["fog_height_density"]
	_sun.light_color = look["light"]
	_sun.light_energy = look["energy"]
	# The floor as the sim lights it: cloud takes Weather.CLOUD_DIM of the
	# day's light over the night's (Fields.ambient_at).
	var day := DayNight.daylight_at(float(_sky_step) / SKY_STEPS)
	var share := 1.0 - Weather.CLOUD_DIM * float(_weather_view.weather["cloud"])
	var light := DayNight.NIGHT + (day - DayNight.NIGHT) * share
	var roof := DayNight.NIGHT + (day - DayNight.NIGHT) * share * (1.0 - World.fields.canopy_shade)
	var lit := bool(_terrain.get("daylight", false))
	_set_sky_floor(floor_brightness(light) if lit else 0.0, floor_brightness(roof) if lit else 0.0)


## The haze's density (623, environment's side): the look's own [param base]
## and the [param weather]'s share (weathered_look's fog_weather, per unit,
## tuned for a camera CAMERA_DISTANCE off); under the [param low] camera
## [param distance] off, the weather's share scaled so the aim reads as in
## ortho (a storm then hides the hills) and LOW_FOG over it. Ortho: as ever.
static func hazed_density(base: float, weather: float, low: bool, distance: float) -> float:
	if not low:
		return base + weather
	return base + weather * CAMERA_DISTANCE / maxf(distance, 1.0) + LOW_FOG


## The sky's horizon under the low camera (623, environment's side): the
## [param look]'s, drawn toward its haze's colour as the [param weather]
## (Weather.at's amounts) thickens, so the land fades into the sky with no
## band: grey under overcast, the fog's in fog.
static func hazed_horizon(look: Dictionary, weather: Dictionary) -> Color:
	var thick := clampf(maxf(maxf(float(weather.get("fog", 0.0)), float(weather.get("rain", 0.0))),
			0.6 * float(weather.get("cloud", 0.0))), 0.0, 1.0)
	return (look["horizon"] as Color).lerp(look["fog"], thick)


## The haze as it stands: hazed_density of the look's last (_haze), for the
## camera's distance now (the wheel moves it under the low camera).
func _set_haze() -> void:
	_environment.fog_density = hazed_density(_haze.x, _haze.y, _low, _camera_distance())


## The height (degrees) shadows are cast from for a light [param elevation]
## high: SHADOW_LOW at or under the horizon, rising to SHADOW_HIGH overhead.
static func shadow_elevation(elevation: float) -> float:
	return lerpf(SHADOW_LOW, SHADOW_HIGH, clampf(elevation, 0.0, 90.0) / 90.0)


## [param look] (sky_look's) in [param season] (Season.at's): winter's
## light cooler and paler, its sun weaker, summer's a little warmer;
## snow on the ground throws light back up (decision 362).
static func seasoned_look(look: Dictionary, season: Dictionary) -> Dictionary:
	var winter := float(season.get("winter", 0.0))
	var summer := float(season.get("summer", 0.0))
	var snow := float(season.get("snow", 0.0))
	var out := look.duplicate()
	out["light"] = (look["light"] as Color).lerp(WINTER_LIGHT, 0.175 * winter).lerp(SUMMER_LIGHT, 0.25 * summer)
	out["energy"] = float(look["energy"]) * (1.0 - WINTER_SUN * winter)
	out["top"] = (look["top"] as Color).lerp(WINTER_SKY, 0.15 * winter)
	out["horizon"] = (look["horizon"] as Color).lerp(WINTER_SKY.lightened(0.3), 0.15 * winter)
	out["ambient"] = (look["ambient"] as Color).lerp(WINTER_LIGHT, 0.15 * winter)
	out["ambient_energy"] = float(look["ambient_energy"]) * (1.0 + SNOW_AMBIENT * snow)
	return out


## [param look] (sky_look's) under [param weather] (Weather.at's amounts):
## cloud greys the sky and takes the sun's light (its shadows fade with
## it), fog thickens the haze and lies along the ground, rain darkens.
static func weathered_look(look: Dictionary, weather: Dictionary) -> Dictionary:
	var cloud := float(weather.get("cloud", 0.0))
	var fog := float(weather.get("fog", 0.0))
	var rain := float(weather.get("rain", 0.0))
	var out := look.duplicate()
	var grey := func(colour: Color, amount: float) -> Color:
		var value := colour.get_luminance() * (1.0 - RAIN_DARK * rain)
		return colour.lerp(Color(value, value, value * 1.04), amount)
	out["top"] = grey.call(look["top"], 0.75 * cloud)
	out["horizon"] = grey.call(look["horizon"], 0.6 * cloud)
	out["ambient"] = grey.call(look["ambient"], 0.25 * cloud)
	out["light"] = grey.call(look["light"], 0.25 * cloud)
	out["energy"] = float(look["energy"]) * (1.0 - CLOUD_SUN * cloud)
	out["fog"] = grey.call(look["fog"], maxf(0.6 * cloud, 0.8 * fog))
	out["fog_weather"] = FOG_DENSITY * fog + RAIN_FOG_DENSITY * rain
	out["fog_density"] = float(look["fog_density"]) + float(out["fog_weather"])
	out["fog_height"] = FOG_HEIGHT
	out["fog_height_density"] = FOG_HEIGHT_DENSITY * fog
	return out


## [param look] under a forest's canopy of [param under] (0..1: its cover
## round the view, as a share of the sim's full shade; decision 477): the
## ambient darker and greener, the haze too. The sun's light stays: the
## crowns' shadows take it, so the clearings stay sunlit.
static func canopied_look(look: Dictionary, under: float) -> Dictionary:
	if under <= 0.0:
		return look
	var out := look.duplicate()
	out["ambient"] = (look["ambient"] as Color).lerp(CANOPY_TINT, 0.45 * under)
	out["ambient_energy"] = float(look["ambient_energy"]) * (1.0 - CANOPY_AMBIENT * under)
	out["fog"] = (look["fog"] as Color).lerp(CANOPY_FOG, 0.5 * under)
	return out


## Eases the canopy's cover round the view toward the sim's (the mean of
## Fields.canopy_at within CANOPY_AROUND cells of the view's middle) and
## tells the weather it and its drips; true if it changed.
func _ease_canopy(delta: float) -> bool:
	var target := 0.0
	if World.fields.canopy_kind != "":
		var middle := Vector2i(roundi(_camera_target.x), roundi(_camera_target.z))
		for dy in range(-CANOPY_AROUND, CANOPY_AROUND + 1):
			for dx in range(-CANOPY_AROUND, CANOPY_AROUND + 1):
				target += World.fields.canopy_at(middle + Vector2i(dx, dy))
		target /= float((2 * CANOPY_AROUND + 1) * (2 * CANOPY_AROUND + 1))
	var before := _canopy_cover
	_canopy_cover = target if absf(target - before) < 0.002 else lerpf(before, target, 1.0 - exp(-CANOPY_EASE * delta))
	_weather_view.set_canopy(_canopy_cover, Weather.drip_at(World.fields.region, DayNight.now(), _canopy_cover))
	return _canopy_cover != before


## SKY_KEYS blended for the sun [param elevation] degrees high.
static func sky_look(elevation: float) -> Dictionary:
	if elevation <= SKY_KEYS[0][0]:
		return SKY_KEYS[0][1]
	for i in range(1, SKY_KEYS.size()):
		if elevation <= SKY_KEYS[i][0]:
			var weight: float = inverse_lerp(SKY_KEYS[i - 1][0], SKY_KEYS[i][0], elevation)
			var low: Dictionary = SKY_KEYS[i - 1][1]
			var high: Dictionary = SKY_KEYS[i][1]
			var look := {}
			for key: String in low:
				look[key] = lerp(low[key], high[key], weight)
			return look
	return SKY_KEYS[-1][1]


## DayNight's direction [param toward] (x east, y up, z south) in this
## view's space, turned to the level's north (grid x, y are 3D x, z).
func _level_direction(toward: Vector3) -> Vector3:
	var north: Vector2i = _terrain.get("north", Vector2i(0, -1))
	var east := Vector3(-north.y, 0.0, north.x)
	var south := Vector3(-north.x, 0.0, -north.y)
	return east * toward.x + Vector3.UP * toward.y + south * toward.z


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.1
	_camera.far = CAMERA_DISTANCE * 3.0
	add_child(_camera)
	_camera_target = _tile_position(_centre)
	_apply_camera_mode()
	_place_camera()
	_camera.current = true


## Whether the low-horizon camera (decision 623) is on now: the toggle, and
## outdoors.
func low_camera() -> bool:
	return _low


## The pitch at rest: LOW_PITCH under the low camera, CAMERA_PITCH else.
func rest_pitch() -> float:
	return LOW_PITCH if _low else CAMERA_PITCH


## The tilt's floor: LOW_PITCH_MIN under the low camera, PITCH_MIN else.
func pitch_floor() -> float:
	return LOW_PITCH_MIN if _low else PITCH_MIN


## The camera's distance from its target: CAMERA_DISTANCE; under the low
## camera, LOW_DISTANCE_SHARE of it scaled as the ortho size is (the wheel,
## a peek, the mourning pull-back).
func _camera_distance() -> float:
	return CAMERA_DISTANCE * LOW_DISTANCE_SHARE * _size_factor() if _low else CAMERA_DISTANCE


## The low camera on or off as Net.camera_low and the map say (decision
## 623): the projection, its reach and haze, the sun's shadow distance, and
## the pitch to its rest. Off restores the ortho view exactly. On a build,
## a map change, and the toggle.
func _apply_camera_mode() -> void:
	if _camera == null:
		return
	var low: bool = Net.camera_low and _outdoor
	var was := _low
	_low = low
	if low:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = LOW_FOV
		_camera.far = LOW_FAR
	else:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.far = CAMERA_DISTANCE * 3.0
	if _environment != null:
		_environment.fog_aerial_perspective = LOW_AERIAL if low else 0.0
	if _sun != null:
		_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if low \
				else DirectionalLight3D.SHADOW_ORTHOGONAL
		_sun.directional_shadow_max_distance = LOW_SHADOW_DISTANCE if low else SHADOW_DISTANCE
	if low != was:
		pitch = rest_pitch()
		_tilt_t = 1.0
		_sky_step = -1  # The look again, with or without the haze.
		_update_sky(0.0)
		if not low:
			for puppet: Node3D in _puppets.values():
				puppet.visible = true
				_set_transparency(puppet, 0.0)
				puppet.remove_meta("reach_in")
				puppet.remove_meta("reach_at")
				var label := puppet.get_node_or_null("Name") as Label3D
				if label != null:
					label.scale = Vector3.ONE
					label.render_priority = 0
					label.visible = not label.text.is_empty()
	_shadow_key = Vector3i(1 << 30, 0, 0)  # Shadows looked at again for the new reach.
	_apply_size()
	_place_camera()


func _on_camera_low_changed(_low_now: bool) -> void:
	_apply_camera_mode()


## [param grid] held within World.NEAR_TILES of the camera's aim, along the
## line to it (decision 238: what is on screen thinks every tick; under the
## low camera the screen shows further than that).
func within_near(grid: Vector2) -> Vector2:
	var aim := Vector2(_camera_target.x, _camera_target.z)
	var away := grid - aim
	if away.length() <= World.NEAR_TILES:
		return grid
	return aim + away.normalized() * World.NEAR_TILES


## The camera's offset from its target: `pitch` above the ground on the
## +x +z side (grid +x toward the viewer down-right, +y down-left, as in
## the 2D view), turned about the vertical by the yaw.
func _camera_offset() -> Vector3:
	var tilt := deg_to_rad(maxf(pitch, _ridge_pitch))
	var distance := _camera_distance()
	var horizontal := distance * cos(tilt)
	var offset := Vector3(horizontal / sqrt(2.0), distance * sin(tilt), horizontal / sqrt(2.0))
	return offset.rotated(Vector3.UP, deg_to_rad(yaw))


## Which way a grid offset [param offset] runs on screen at the camera's
## aim (unit, y down): the HUD compass's north.
func screen_direction(offset: Vector2) -> Vector2:
	if _camera == null:
		return Vector2.UP
	var from := _camera.unproject_position(_camera_target)
	var to := _camera.unproject_position(_camera_target + Vector3(offset.x, 0.0, offset.y))
	return (to - from).normalized() if from.distance_to(to) > 0.001 else Vector2.UP


func _place_camera() -> void:
	_aim_hillshade()
	_camera.position = _camera_target + _camera_offset()
	_camera.look_at(_camera_target, Vector3.UP)
	if _listener != null:
		# On the ground under the camera's aim (less any pan: the ears stay
		# with the player), turned as the camera is, so left and right in
		# the ears are left and right on the screen.
		_listener.global_transform = Transform3D(_camera.global_transform.basis, _camera_target - pan + Vector3.UP)


## The camera stays on the player (plus the WASD lean, which eases by
## itself): the player is the middle of the screen, and the yaw turns
## about them. A jump of the player's drawn place (a correction) is eased
## over a few frames, a slide followed as it is (_camera_ease).
func _follow(delta: float) -> void:
	var player := _local_player()
	if player == null:
		return
	var puppet: Node3D = _puppets.get(player.get_instance_id())
	if puppet == null:
		return
	_local_name = String(player.name)
	sfx.listener = player.tile  # Sounds are heard from here, as a monster there would.
	_lead = Main.camera_lean(_lead, get_viewport(), yaw, delta)
	_aim_lead = _aim_lead.lerp(_aim_lead_to, 1.0 - exp(-ZOOM_RATE * delta))
	if _aim_lead_to == Vector3.ZERO and _aim_lead.length() < 0.001:
		_aim_lead = Vector3.ZERO
	_camera_target = _camera_ease.follow(puppet.position, delta) + lead_offset(_lead, _aim_lead) + pan
	_ridge_pitch = move_toward(_ridge_pitch, ridge_pitch(puppet.position), RIDGE_EASE * delta)
	_place_camera()
	_update_sight(puppet.position, delta)


## The sight-line cut-out (decision 549): eased in while the ground
## hides the player at [param at] (their feet) from the camera as it now
## stands, out when not; the shaders' globals set for it.
func _update_sight(at: Vector3, delta: float) -> void:
	if _relief.is_empty() and _sight_cut == 0.0:
		return
	# Asked again only when the player's place or the camera's angle moved
	# (a walk over the ground a frame cost about half a millisecond).
	var key := Vector4(snappedf(at.x, 0.25), snappedf(at.z, 0.25), yaw, snappedf(maxf(pitch, _ridge_pitch), 0.5))
	if key != _sight_key:
		_sight_key = key
		_sight_hidden = hidden_by_ground(at, maxf(pitch, _ridge_pitch))
	var was := _sight_cut
	_sight_cut = move_toward(_sight_cut, 1.0 if _sight_hidden else 0.0, delta / SIGHT_EASE)
	if _sight_cut == 0.0 and was == 0.0:
		return  # Nothing cut, nothing to tell the shaders.
	# The cut-out's shaders only while it is in; the materials keep their
	# parameters across the swap.
	var cutting := _sight_cut > 0.0
	if _ground_look != null and (_ground_look.shader == GROUND_SIGHT_SHADER) != cutting:
		_ground_look.shader = GROUND_SIGHT_SHADER if cutting else GROUND_SHADER
	if _scatter_sway != null and (_scatter_sway.shader == SCATTER_SIGHT_SHADER) != cutting:
		_scatter_sway.shader = SCATTER_SIGHT_SHADER if cutting else SCATTER_SHADER
	var toward := _camera_offset().normalized()
	RenderingServer.global_shader_parameter_set("sight_focus", Vector4(at.x, at.y + RIDGE_AIM, at.z, at.y))
	RenderingServer.global_shader_parameter_set("sight_toward", Vector4(toward.x, toward.y, toward.z, 0.0))
	RenderingServer.global_shader_parameter_set("sight_cut", _sight_cut)


## Whether the ground stands over the line from the camera, at
## [param pitch_degrees] and this yaw, to the middle of a body at
## [param at] (its feet): the relief between them, RIDGE_REACH back; never
## on a level with no relief.
func hidden_by_ground(at: Vector3, pitch_degrees: float) -> bool:
	if _relief.is_empty():
		return false
	var back := Vector2(1.0, 1.0).normalized().rotated(-deg_to_rad(yaw))
	var rise := tan(deg_to_rad(pitch_degrees))
	var aim := at.y + RIDGE_AIM
	var d := 0.75
	while d <= RIDGE_REACH:
		if _ground_height(Vector2(at.x, at.z) + back * d) > aim + d * rise:
			return true
		d += 0.25
	return false


## The ground's relief light set for the camera's yaw, when it turned.
func _aim_hillshade() -> void:
	if _ground_look == null or is_equal_approx(_hillshade_yaw, yaw):
		return
	_hillshade_yaw = yaw
	_ground_look.set_shader_parameter("relief_light", hillshade_light(yaw))


## The relief light (decision 525 amended, terrain's side), toward it: from
## the screen's upper left, HILLSHADE_HIGH degrees up, turned with the
## camera's [param yaw_degrees]. A fixed light, not the sun: a north-south
## ridge's flanks face east and west, and the noon sun, due south, lights
## both alike, so by the sun alone a valley reads flat at noon.
static func hillshade_light(yaw_degrees: float) -> Vector3:
	# The camera sits toward +x +z of its aim (turned by the yaw): the
	# screen's up is away from it, its left a quarter turn from that.
	var up := -Vector3(1.0, 0.0, 1.0).normalized().rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	var left := up.rotated(Vector3.UP, PI * 0.5)
	var across := (up + left).normalized()
	var high := deg_to_rad(HILLSHADE_HIGH)
	return (across * cos(high) + Vector3.UP * sin(high)).normalized()


## The pitch (degrees) the camera needs to see over the ground between it and
## [param at] (decision 525): the ground along the camera's way back,
## RIDGE_REACH metres of it, kept RIDGE_CLEAR under the line to a body's
## middle there; 0 where nothing rises (a level with no hills: always).
func ridge_pitch(at: Vector3) -> float:
	if _relief.is_empty():
		return 0.0
	var back := Vector2(1.0, 1.0).normalized().rotated(-deg_to_rad(yaw))
	var need := 0.0
	var aim := at.y + RIDGE_AIM
	var d := 1.0
	while d <= RIDGE_REACH:
		var ground := _ground_height(Vector2(at.x, at.z) + back * d)
		need = maxf(need, rad_to_deg(atan2(ground + RIDGE_CLEAR - aim, d)))
		d += 0.5
	return clampf(need, 0.0, RIDGE_PITCH_MAX)


func _local_player() -> Player:
	# The roster (players and companions), not a copy of every entity: this
	# is asked several times a frame.
	for entity in World.sought():
		if entity is Player and entity.owner_peer == Net.local_id and entity.spawned:
			return entity
	return null


# --- Orbit ---------------------------------------------------------------------

## The ortho size: CAMERA_SIZE, times the pitch peek's pull back while
## there is one (eased as its tilt is).
func _apply_size() -> void:
	_camera.size = CAMERA_SIZE * _size_factor()
	if _low:
		_place_camera()  # The wheel, a peek and the pull-back move the camera instead.


## The wheel's zoom, a pitch peek's and the mourning's pull-back, as one
## factor on the ortho size (and under the low camera, on its distance).
func _size_factor() -> float:
	return zoom * lerpf(1.0, PEEK_PULL_BACK, smoothstep(0.0, 1.0, _peek)) \
			* lerpf(1.0, MOURN_PULL_BACK, smoothstep(0.0, 1.0, _mourn))


## How tall the view is at the camera's aim (ground units, straight across
## the screen): the ortho size, or under the low camera the frustum's
## height at its distance.
func _view_height() -> float:
	if _low:
		return 2.0 * _camera_distance() * tan(deg_to_rad(_camera.fov * 0.5))
	return _camera.size


## The mouse wheel, [param notches] of it (positive in, nearer the player;
## negative out): ZOOM_STEP a notch, held to ZOOM_MIN..ZOOM_MAX, eased
## there; saved. The camera is on the player, so that is the centre.
func zoom_by(notches: int) -> void:
	_zoom_to = clampf(_zoom_to / pow(ZOOM_STEP, notches), ZOOM_MIN, ZOOM_MAX)
	_save_zoom()


## Click scheme: a middle drag begins; pan_by moves from where it is now.
func begin_pan() -> void:
	_pan_base = pan
	_pan_home = false


## The drag is [param offset] (screen px) from where it went down: the view
## slides so the ground under the cursor stays under it (an ortho view, so
## a pixel across is size / height of ground, and one up and down that over
## the sine of the tilt), held to PAN_MAX.
func pan_by(offset: Vector2) -> void:
	var height := get_viewport().get_visible_rect().size.y
	if _camera == null or height <= 0.0:
		return
	var per_px := _view_height() / height
	var basis := _camera.global_transform.basis
	var right := Vector3(basis.x.x, 0.0, basis.x.z).normalized()
	var ahead := Vector3(-basis.z.x, 0.0, -basis.z.z).normalized()
	var moved := -right * offset.x * per_px + ahead * offset.y * per_px / sin(deg_to_rad(pitch))
	pan = (_pan_base + moved).limit_length(PAN_MAX)


## The middle drag let go: the view eases back onto the player.
func end_pan() -> void:
	_pan_home = true


func _ease_pan(delta: float) -> void:
	if not _pan_home:
		return
	pan = pan.lerp(Vector3.ZERO, 1.0 - exp(-ZOOM_RATE * delta))
	if pan.length() < 0.001:
		pan = Vector3.ZERO
		_pan_home = false


func _save_zoom() -> void:
	Net.camera_zoom = _zoom_to
	Net.save_view_settings()


func _ease_zoom(delta: float) -> void:
	if is_equal_approx(zoom, _zoom_to):
		return
	zoom = lerpf(zoom, _zoom_to, 1.0 - exp(-ZOOM_RATE * delta))
	if absf(zoom - _zoom_to) < 0.0005:
		zoom = _zoom_to
	_apply_size()


## Click scheme, A/D held: turn [param direction] (-1 or 1) for
## [param delta] seconds at TURN_RATE, through any angle.
func turn(direction: float, delta: float) -> void:
	if _turning == 0.0:
		_turn_from = _yaw_step
	_ease_t = 1.0
	_turning = signf(direction)
	_set_yaw(yaw + TURN_RATE * _turning * delta)


## Click scheme, A/D let go: settle on the diamond settle_target gives, and
## keep it. The settle starts at the turning speed and slows to a stop on
## the diamond: going on, in the time that stop takes (twice the distance
## over the speed); going back, it runs on a little, turns and comes back,
## TURN_RETURN_EXTRA longer.
func end_turn() -> void:
	var direction := _turning
	_turning = 0.0
	if direction == 0.0:
		return
	var target := settle_target(_turn_from, yaw, direction)
	var distance := (target - yaw) * direction
	_settle_on(target)
	_ease_curve = Ease.FLOW
	_ease_velocity = TURN_RATE * direction
	if distance > 0.0:
		_ease_seconds = 2.0 * distance / TURN_RATE
	elif distance < 0.0:
		_ease_seconds = 2.0 * absf(distance) / TURN_RATE + TURN_RETURN_EXTRA
	else:
		_ease_t = 1.0


## Where a turn that set off from the diamond [param from] and was let go
## at [param degrees], going [param direction], settles: back on [param
## from] if it turned less than TURN_COMMIT, otherwise the next diamond
## the way it was going (the one it is on, if it is exactly on one).
static func settle_target(from: float, degrees: float, direction: float) -> float:
	if absf(degrees - from) < TURN_COMMIT:
		return from
	if direction > 0.0:
		return ceilf(degrees / ORBIT_STEP - 0.0001) * ORBIT_STEP
	return floorf(degrees / ORBIT_STEP + 0.0001) * ORBIT_STEP


## Click scheme, W/S held: tilt [param direction] (1 up toward top-down,
## -1 down toward level) for [param delta] seconds at TILT_RATE, slowing
## over the last TILT_EASE_DEGREES before either end.
func tilt(direction: float, delta: float) -> void:
	if _peeking or direction == 0.0:
		return
	_tilt_t = 1.0
	var limit := PITCH_MAX if direction > 0.0 else pitch_floor()
	var left := absf(limit - pitch)
	var speed := TILT_RATE * clampf(left / TILT_EASE_DEGREES, 0.1, 1.0)
	_set_pitch(move_toward(pitch, limit, speed * delta))


## Click scheme, W/S let go: back to CAMERA_PITCH over
## TILT_RETURN_SECONDS. Nothing is saved.
func end_tilt() -> void:
	_tilt_from = pitch
	_tilt_t = 0.0


func _ease_tilt(delta: float) -> void:
	if _tilt_t >= 1.0:
		return
	_tilt_t = minf(_tilt_t + delta / TILT_RETURN_SECONDS, 1.0)
	_set_pitch(lerpf(_tilt_from, rest_pitch(), sin(_tilt_t * PI * 0.5)))


func _set_pitch(degrees: float) -> void:
	pitch = degrees
	_apply_size()
	_place_camera()


## The middle button went down on a vertical drag: a pitch peek from
## wherever the camera is now (a spring back under way stops there).
func begin_pitch_peek() -> void:
	_peeking = true
	_peek_t = 1.0


## The peek is [param pixels] of vertical drag, either way: that share of
## PEEK_DRAG_PX of the full tilt and pull back.
func pitch_peek(pixels: float) -> void:
	if _peeking:
		_set_peek(clampf(absf(pixels) / PEEK_DRAG_PX, 0.0, 1.0))


## The middle button came up: back to the resting pitch and size over
## PEEK_RETURN_SECONDS.
func end_pitch_peek() -> void:
	if not _peeking:
		return
	_peeking = false
	_peek_from = _peek
	_peek_t = 0.0


## The spring back, a sine out.
func _ease_peek(delta: float) -> void:
	if _peek_t >= 1.0:
		return
	_peek_t = minf(_peek_t + delta / PEEK_RETURN_SECONDS, 1.0)
	_set_peek(lerpf(_peek_from, 0.0, sin(_peek_t * PI * 0.5)))


## How far in the peek is, 0..1: the pitch and size it gives, eased in
## and out (smoothstep), so the tilt starts and ends gently.
func _set_peek(amount: float) -> void:
	_peek = amount
	var eased := smoothstep(0.0, 1.0, amount)
	_set_pitch(lerpf(CAMERA_PITCH, PEEK_PITCH, eased))


## WASD: the middle button went down; the drag turns from the yaw now.
func begin_drag() -> void:
	_dragging = true
	_settle_pending = false
	_drag_base = yaw
	_drag_offset = 0.0
	_ease_t = 1.0


## WASD: the drag is [param degrees] from where it began. Followed at once,
## unless frozen (then it waits) or easing back in after a freeze (then it
## is where the ease is going).
func drag(degrees: float) -> void:
	if not _dragging:
		return
	_drag_offset = degrees
	if frozen:
		return
	if _ease_t < 1.0:
		_ease_to = _drag_base + degrees
	else:
		_set_yaw(_drag_base + degrees)


## WASD: the middle button came up: settle as an A/D turn does, on the
## next diamond the way it was dragged (or back, under TURN_COMMIT), now
## or, if frozen, when the keys are let go.
func end_drag() -> void:
	if not _dragging:
		return
	_dragging = false
	if frozen:
		_settle_pending = true
	else:
		_settle_on(_drag_target())


func _drag_target() -> float:
	return settle_target(nearest_diamond(_drag_base), _drag_base + _drag_offset, signf(_drag_offset))


## Main: a movement key is (not) held. Held, the yaw stops where it is;
## let go, what the middle button did meanwhile applies.
func set_frozen(on: bool) -> void:
	if frozen == on:
		return
	frozen = on
	if on:
		return
	if _dragging:
		_ease_toward(_drag_base + _drag_offset)
	elif _settle_pending:
		_settle_pending = false
		_settle_on(_drag_target())


## The diamond view nearest [param degrees]; half way between two (an
## axis view), the higher.
static func nearest_diamond(degrees: float) -> float:
	return snappedf(degrees, ORBIT_STEP)


## Eases to the diamond [param step], which the yaw then rests on and the
## settings file keeps.
func _settle_on(step: float) -> void:
	_yaw_step = step
	Net.camera_yaw = fposmod(step, 360.0)
	Net.save_view_settings()
	_ease_toward(step)


func _ease_toward(degrees: float) -> void:
	_ease_from = yaw
	_ease_to = degrees
	_ease_t = 0.0
	_ease_seconds = SETTLE_SECONDS
	_ease_curve = Ease.SINE_OUT


## One frame of the ease; nothing while frozen.
func _ease_yaw(delta: float) -> void:
	if frozen or _ease_t >= 1.0:
		return
	_ease_t = minf(_ease_t + delta / _ease_seconds, 1.0)
	var s := _ease_t
	if _ease_curve == Ease.FLOW:
		# Cubic Hermite: from _ease_from at _ease_velocity to _ease_to at rest.
		var along := (-2.0 * s * s * s + 3.0 * s * s) * (_ease_to - _ease_from)
		var carried := (s * s * s - 2.0 * s * s + s) * _ease_seconds * _ease_velocity
		_set_yaw(_ease_from + along + carried)
	else:
		_set_yaw(lerpf(_ease_from, _ease_to, sin(s * PI * 0.5)))


func _set_yaw(degrees: float) -> void:
	if is_equal_approx(degrees, yaw):
		return
	yaw = degrees
	_place_camera()
	# Not every piece set again (_classify_walls): only those whose fade
	# changes, so a turn costs what a step does (310).
	_update_fade()


# --- Picking --------------------------------------------------------------------

func _mouse_ray() -> Array[Vector3]:
	var mouse := get_viewport().get_mouse_position()
	return [_camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse)]


## Where the cursor's ray meets the ground plane, in grid units; NaN when
## it does not. Under the low camera, no further than World.NEAR_TILES from
## the camera's aim (within_near).
func mouse_grid() -> Vector2:
	var hit := _mouse_ground()
	if _low and not is_nan(hit.x):
		return within_near(hit)
	return hit


func _mouse_ground() -> Vector2:
	var ray := _mouse_ray()
	if absf(ray[1].y) < 0.0001:
		return Vector2(NAN, NAN)
	# Down the ray from where it comes as low as the highest ground to where
	# it passes the lowest, in short steps: the first point under the ground
	# (as drawn, slopes and ramps too), then halved in to it; the ground
	# plane if none.
	if ray[1].y < 0.0 and not _corners.is_empty():
		var start := maxf((_ground_top - ray[0].y) / ray[1].y, 0.0)
		var end := (_ground_bottom - 0.01 - ray[0].y) / ray[1].y
		var step := PICK_STEP / maxf(Vector2(ray[1].x, ray[1].z).length(), 0.05)
		var before := start
		var t := start
		while t <= end:
			var at: Vector3 = ray[0] + ray[1] * t
			if at.y <= _ground_height(Vector2(at.x, at.z)):
				for i in 6:
					var middle := (before + t) * 0.5
					var mid: Vector3 = ray[0] + ray[1] * middle
					if mid.y <= _ground_height(Vector2(mid.x, mid.z)):
						t = middle
					else:
						before = middle
				var hit: Vector3 = ray[0] + ray[1] * t
				return Vector2(hit.x, hit.z)
			before = t
			t += step
	var t := -ray[0].y / ray[1].y
	if t < 0.0:
		return Vector2(NAN, NAN)
	var hit := ray[0] + ray[1] * t
	return Vector2(hit.x, hit.z)


## How high the ground is under [param grid] (a puppet's place): its cell's
## height, or on a stair, the ramp's.
func _ground_height(grid: Vector2) -> float:
	return _height_in(Vector2i(roundi(grid.x), roundi(grid.y)), grid)


## How high [param cell]'s ground is at [param point] (on it or its edge),
## on the triangle the mesh draws there (its corners: _corner_heights): a
## slope's, a ramp's, or flat. Every puppet every frame: a lookup and a
## few sums.
func _height_in(cell: Vector2i, point: Vector2) -> float:
	var at := (point - Vector2(cell) + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	if _shore_heights.has(cell):
		# A shore cell's finer quad (decision 553), its triangles as a cell's.
		var fine: PackedFloat32Array = _shore_heights[cell]
		var x := mini(floori(at.x * SHORE_RES), SHORE_RES - 1)
		var y := mini(floori(at.y * SHORE_RES), SHORE_RES - 1)
		var row := SHORE_RES + 1
		var q := y * row + x
		at = at * SHORE_RES - Vector2(x, y)
		if at.x + at.y <= 1.0:
			return fine[q] + (fine[q + 1] - fine[q]) * at.x + (fine[q + row] - fine[q]) * at.y
		return fine[q + row + 1] + (fine[q + row] - fine[q + row + 1]) * (1.0 - at.x) \
				+ (fine[q + 1] - fine[q + row + 1]) * (1.0 - at.y)
	if _dais_stairs.has(cell):
		# Up dais.steps: flat to their foot, then up to the dais at the edge.
		var along := (at - Vector2(0.5, 0.5)).dot(Vector2(_dais_stairs[cell])) + 0.5
		return _elevation(cell) + LEVEL_RISE * clampf((along - (1.0 - DAIS_STEPS_REACH)) / DAIS_STEPS_REACH, 0.0, 1.0)
	var h := _corner_heights(cell)
	# The quad's two triangles: (0, 1, 2) where x + y <= 1, (1, 3, 2) past it.
	if at.x + at.y <= 1.0:
		return h[0] + (h[1] - h[0]) * at.x + (h[2] - h[0]) * at.y
	return h[3] + (h[2] - h[3]) * (1.0 - at.x) + (h[1] - h[3]) * (1.0 - at.y)


## [param cell]'s ground in metres at its middle (decision 525): its
## elevation in the relief, else its whole level.
func _elevation(cell: Vector2i) -> float:
	if _relief.is_empty() or not Relief.on_map(_relief_size, cell):
		return _height(cell) * LEVEL_RISE
	return Relief.at(_relief, _relief_size, cell)


## [param cell]'s ground corners (metres, GROUND_CORNERS order), as drawn.
func _corner_heights(cell: Vector2i) -> PackedFloat32Array:
	if _corners.has(cell):
		return _corners[cell]
	return _ground_corners(cell)


## [param cell]'s corners worked out: a stream bed's under a bridge, a
## ramp's, else the relief's (Relief.corner_heights: each the mean of the
## cells joined to it walkably, per side of a cliff), else its whole level
## flat.
func _ground_corners(cell: Vector2i) -> PackedFloat32Array:
	if _relief_given and (_wet.has(cell) or _bed_levels.has(cell)):
		# Under the water's surface (decision 525): each corner the water's
		# bed there (_shore_bed); the mesh sinks those with water all round.
		var own := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		for c in 4:
			own[c] = _shore_bed(cell + GROUND_CORNERS[c], _bed_levels.get(cell, _elevation(cell)))
		return own
	if _relief_given and _relief_size != Vector2i.ZERO and Relief.on_map(_relief_size, cell) and not _ramp_heights.has(cell):
		# A bank: a corner the water touches comes down to the water's edge
		# (one vertex with it: a grassy slope into the brook, no face) where
		# the lowest land there stands within a walk of the highest water, as
		# the sim's step to it is: decided by the corner, so every land cell
		# meeting there agrees; a true cliff keeps its face.
		var own := Relief.corner_heights(_relief, _relief_size, cell)
		# A corner's cells are all in the 3 x 3 round the cell: with no water
		# there, no corner is a bank (most of a map; _water_top asks each).
		var near_water := false
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var round_cell := cell + Vector2i(dx, dy)
				if _wet.has(round_cell) or _bed_levels.has(round_cell):
					near_water = true
		if not near_water:
			return own
		for c in 4:
			var vertex := cell + GROUND_CORNERS[c]
			var top := _water_top(vertex)
			if top > -INF and _land_low(vertex) - top <= Relief.WALK_RISE:
				# The water on this land's side of a tall fall, if any is
				# (570, terrain's side: no bank pulled up the face).
				var bed := _shore_bed(vertex, _elevation(cell))
				own[c] = bed if not is_inf(bed) else _shore_bed(vertex)
		return own
	if _bed_levels.has(cell):
		var bed := _bed_levels[cell]
		return PackedFloat32Array([bed, bed, bed, bed])
	if _ramp_heights.has(cell):
		return _ramp_heights[cell]
	if _relief.is_empty() or not Relief.on_map(_relief_size, cell):
		var flat := _height(cell) * LEVEL_RISE
		return PackedFloat32Array([flat, flat, flat, flat])
	return Relief.corner_heights(_relief, _relief_size, cell)


## The ground's elevation (m) at each cell the forest's border and grown
## trees stand round (decision 525): the land and the wooded cells.
func _elevations() -> Dictionary:
	var out := {}
	for cell: Vector2i in _wooded:
		out[cell] = _elevation(cell)
	for cell: Vector2i in _terrain.get("heights", {}):
		out[cell] = _elevation(cell)
	return out


## The water's surface at the ground's corner [param vertex] (decision 525):
## the mean of the surfaces of the water cells round it (a bridge's water at
## its bed), so a pond's is flat and a stream's slopes down its path. For a
## water cell at [param level], only the water within FALL_TALL of it (570,
## terrain's side): across a tall fall the cells above and below keep their
## own, a face between them, not a bed ramped from the lip to the foot.
func _water_corner(vertex: Vector2i, level := NAN) -> float:
	var sum := 0.0
	var count := 0
	for cell: Vector2i in [vertex - Vector2i.ONE, vertex - Vector2i(0, 1), vertex - Vector2i(1, 0), vertex]:
		if _wet.has(cell) or _bed_levels.has(cell):
			var surface: float = _bed_levels.get(cell, _elevation(cell))
			if not is_nan(level) and absf(surface - level) >= FALL_TALL:
				continue
			sum += surface
			count += 1
	return sum / count if count > 0 else INF


## The lowest land (not water) at corner [param vertex] (INF for none).
func _land_low(vertex: Vector2i) -> float:
	var low := INF
	for cell: Vector2i in [vertex - Vector2i.ONE, vertex - Vector2i(0, 1), vertex - Vector2i(1, 0), vertex]:
		if not _wet.has(cell) and not _bed_levels.has(cell) and Relief.on_map(_relief_size, cell):
			low = minf(low, _elevation(cell))
	return low


## The highest water surface at corner [param vertex] (-INF for none).
func _water_top(vertex: Vector2i) -> float:
	var top := -INF
	for cell: Vector2i in [vertex - Vector2i.ONE, vertex - Vector2i(0, 1), vertex - Vector2i(1, 0), vertex]:
		if _wet.has(cell) or _bed_levels.has(cell):
			top = maxf(top, _bed_levels.get(cell, _elevation(cell)))
	return top


## The ground's height under the water at corner [param vertex] (decision
## 525): just under the surface (SHORE_SINK), a ford's FORD_DEPTH under. On
## a river's curve the surface is the curve's where that is lower than its
## cells' mean (559, terrain's side: a narrow stream's corner by a cliff,
## drawn whole, under the water drawn there).
func _shore_bed(vertex: Vector2i, level := NAN) -> float:
	var ford := false
	for cell: Vector2i in [vertex - Vector2i.ONE, vertex - Vector2i(0, 1), vertex - Vector2i(1, 0), vertex]:
		ford = ford or _fords.has(cell)
	var surface := _water_corner(vertex, level)
	var curved := _curve_surface(Vector2(vertex) - Vector2(0.5, 0.5))
	if not is_nan(curved) and (is_nan(level) or absf(curved - level) < FALL_TALL):
		surface = minf(surface, curved)
	return surface - (FORD_DEPTH if ford else SHORE_SINK)


## How much of a valley floor corner [param vertex] is at [param height]
## (0..CONCAVITY_MOST): the ground round it, CONCAVITY_REACH cells away,
## standing over it, CONCAVITY_FULL metres for the most (decision 525).
func _concavity(vertex: Vector2i, height: float) -> float:
	return maxf(_bend(vertex, height), 0.0) * CONCAVITY_MOST


## How much of a crest corner [param vertex] is at [param height] (0..
## CREST_MOST): it standing over the ground round it.
func _crest(vertex: Vector2i, height: float) -> float:
	return maxf(-_bend(vertex, height), 0.0) * CREST_MOST


## The ground round corner [param vertex] (CONCAVITY_REACH cells away) over
## [param height], in CONCAVITY_FULLs, -1..1: a hollow's positive, a crest's
## negative; 0 on a level with no relief.
func _bend(vertex: Vector2i, height: float) -> float:
	if not _relief_given:
		return 0.0
	var sum := 0.0
	var count := 0
	for offset: Vector2i in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
			Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var cell := vertex + offset * CONCAVITY_REACH - Vector2i(0 if offset.x < 0 else 1, 0 if offset.y < 0 else 1)
		if Relief.on_map(_relief_size, cell):
			sum += Relief.at(_relief, _relief_size, cell)
			count += 1
	if count == 0:
		return 0.0
	return clampf((sum / count - height) / CONCAVITY_FULL, -1.0, 1.0)


## The terrain's relief (decision 525) for this build: its field, or none.
func _read_field() -> void:
	# As walked: bodies stand on a bridge's deck (505 amended); terrain
	# "relief" alone has the water under it.
	_relief = Level.walk_relief(_terrain) if _terrain.has("relief") else PackedFloat32Array()
	_relief_size = _terrain.get("relief_size", Vector2i.ZERO)
	_relief_given = bool(_terrain.get("relief_given", false))
	if _relief.size() != _relief_size.x * _relief_size.y:
		_relief = PackedFloat32Array()
		_relief_size = Vector2i.ZERO
		_relief_given = false


## The corners a stair raises: its two on its high side a level up (a ramp
## to the cell above), and the same corner of every cell round them at the
## stair's own height, which the sim walks onto the stair from the side: so
## the ground slopes off the ramp's side, all of it one vertex, where a step
## up beside the ramp would show a ledge the sim does not have.
func _shape_ramps() -> void:
	_ramp_heights.clear()
	_dais_stairs.clear()
	var stairs: Dictionary = _terrain.get("stairs", {})
	var around: Array[Vector2i] = [-Vector2i.ONE, Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]
	for stair: Vector2i in stairs:
		var up: Vector2i = stairs[stair]
		var height := _elevation(stair)
		if _is_dais(stair + up, stair):
			_dais_stairs[stair] = up
			continue
		# The ramp's top: the cell it climbs to (a level up where there is no
		# relief, up to Relief.STAIR_RISE where there is).
		var top := _elevation(stair + up)
		if top <= height + Relief.EPSILON:
			top = height + LEVEL_RISE
		for c in 4:
			if (Vector2(GROUND_CORNERS[c]) - Vector2(0.5, 0.5)).dot(Vector2(up)) <= 0.0:
				continue
			var corner := stair + GROUND_CORNERS[c]
			for a in 4:
				var cell := corner + around[a]
				if cell != stair and (not _land.has(cell) or stairs.has(cell) or absf(_elevation(cell) - height) > Relief.EPSILON):
					continue
				var heights: PackedFloat32Array = _ramp_heights.get(cell, _ground_corners(cell)).duplicate()
				# The corner is this cell's corner 3 - a.
				heights[3 - a] = top
				_ramp_heights[cell] = heights


## Lies a flat mark (hover, ripple) on [param cell]'s ground, [param lift]
## above it: at the ramp's middle on a stair, tilted with it.
func _lay_on_ground(mark: Node3D, cell: Vector2i, lift: float) -> void:
	# Tilted with the ground there (a ramp's, a slope's), by its corners.
	var h := _corner_heights(cell)
	var normal := Vector3(-((h[1] - h[0]) + (h[3] - h[2])) * 0.5, 1.0, -((h[2] - h[0]) + (h[3] - h[1])) * 0.5).normalized()
	var tilt := Quaternion(Vector3.UP, normal) if normal.y < 0.9999 else Quaternion.IDENTITY
	mark.quaternion = tilt
	mark.position = Vector3(cell.x, _height_in(cell, Vector2(cell)), cell.y) + tilt * Vector3(0.0, lift, 0.0)


## The first pick Area3D the cursor's ray hits, with its "entity" or
## "door" meta, or {}.
func _pick() -> Dictionary:
	var ray := _mouse_ray()
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * CAMERA_DISTANCE * 3.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return get_world_3d().direct_space_state.intersect_ray(query)


## The entity whose puppet is under the cursor, or null. The local player
## is looked through, so clicks pass on to what is behind it; a door in
## front stops the ray. Where no puppet is hit, a monster within PICK_SLACK
## of the cursor's ray is the one (the nearest, if more).
func entity_under_mouse() -> GridEntity:
	var own := _local_player()
	var ray := _mouse_ray()
	var query := PhysicsRayQueryParameters3D.create(ray[0], ray[0] + ray[1] * CAMERA_DISTANCE * 3.0)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for i in PICK_DEPTH:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var area: Area3D = hit["collider"]
		if not area.has_meta("entity"):
			return null
		var entity := instance_from_id(area.get_meta("entity")) as GridEntity
		if entity != null and entity.spawned and entity != own:
			return entity
		exclude.append(hit["rid"])
	return monster_near_ray(ray[0], ray[1])


## The slack beside a body at [param at] (global), in ground units:
## PICK_SLACK, or under the low camera PICK_SLACK_SHARE of the screen's
## height at the body's depth from the camera (the frustum's height there
## is twice the depth by the tangent of half the fov), whichever is more.
func pick_slack_at(at: Vector3) -> float:
	if not _low or _camera == null:
		return PICK_SLACK
	var depth := maxf((at - _camera.global_position).dot(-_camera.global_transform.basis.z), 0.0)
	return maxf(PICK_SLACK, PICK_SLACK_SHARE * 2.0 * depth * tan(deg_to_rad(_camera.fov * 0.5)))


## The monster whose body passes within MODEL_RADIUS + pick_slack_at of the
## ray from [param origin] along [param direction] (the nearest, as a share
## of its own slack), or null.
func monster_near_ray(origin: Vector3, direction: Vector3) -> GridEntity:
	var far := origin + direction * CAMERA_DISTANCE * 3.0
	var best: GridEntity = null
	var best_share := 1.0
	for id: int in _puppets:
		if _far.has(id):
			continue  # Out of the view (and its reach) altogether.
		var entity := instance_from_id(id) as GridEntity
		var puppet := _puppets[id]
		if not entity is Monster or not entity.spawned or not is_instance_valid(puppet) or not puppet.is_visible_in_tree():
			continue
		var feet := puppet.global_position
		var head := feet + Vector3.UP * float(puppet.get_meta("pick_height", 1.0))
		var closest := Geometry3D.get_closest_points_between_segments(origin, far, feet, head)
		var share := closest[0].distance_to(closest[1]) / (MODEL_RADIUS + pick_slack_at(closest[1]))
		if share < best_share:
			best = entity
			best_share = share
	return best


## The door whose leaf or frame is under the cursor, or null.
func door_under_mouse() -> Door:
	var hit := _pick()
	if hit.is_empty():
		return null
	var area: Area3D = hit["collider"]
	if not area.has_meta("door"):
		return null
	var key: Vector3i = area.get_meta("door")
	for door in World.get_doors():
		if door.key == key:
			return door
	return null


## Where a grid direction points on screen (for the toss drag).
func screen_vector(direction: Vector2i) -> Vector2:
	return _camera.unproject_position(Vector3(direction.x, 0.0, direction.y)) \
			- _camera.unproject_position(Vector3.ZERO)


## A tile's centre in viewport coordinates (for --test-hover).
func screen_of_tile(tile: Vector2i) -> Vector2:
	return _camera.unproject_position(_tile_position(tile))


# --- Rings ------------------------------------------------------------------------

## A flat annulus in the ground plane, radii in units.
func _make_ring(inner: float, outer: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RING_SEGMENTS:
		var a0 := TAU * i / RING_SEGMENTS
		var a1 := TAU * (i + 1) / RING_SEGMENTS
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		for vertex in [i0, o0, o1, i0, o1, i1]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	return surface.commit()


## A semicircle's band in the ground plane, [param radius] to its middle
## and [param line] wide, from -90 to +90 degrees about [param angle] (the
## aim's way, radians on the grid: x along world x, y along world z, the
## marker's own arithmetic, so no turn of the node is needed); [param span]
## either side of the angle instead of 90 degrees for the cone's far end.
static func _make_arc(radius: float, line: float, angle := 0.0, span := PI * 0.5) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := radius - line * 0.5
	var outer := radius + line * 0.5
	for i in AIM_SEGMENTS:
		var a0 := angle - span + 2.0 * span * i / AIM_SEGMENTS
		var a1 := angle - span + 2.0 * span * (i + 1) / AIM_SEGMENTS
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		for vertex in [i0, o0, o1, i0, o1, i1]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(vertex)
	return surface.commit()


## Flat quads in the ground plane, each [a, b, c, d] corner order.
static func _flat_mesh(quads: Array[PackedVector2Array]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in quads:
		for i: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(quad[i].x, 0.0, quad[i].y))
	return surface.commit()


## Quads as given, each [a, b, c, d] corner order, facing up.
static func _quads_mesh(quads: Array[PackedVector3Array]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in quads:
		for i: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(quad[i])
	return surface.commit()


## A square outline round the cell's centre: the inner edge [param half]
## minus [param line] out, the outer [param half].
static func _make_square_outline(half: float, line: float) -> ArrayMesh:
	var inner := half - line
	var quads: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, -inner), Vector2(-half, -inner)]),
		PackedVector2Array([Vector2(-half, inner), Vector2(half, inner), Vector2(half, half), Vector2(-half, half)]),
		PackedVector2Array([Vector2(-half, -inner), Vector2(-inner, -inner), Vector2(-inner, inner), Vector2(-half, inner)]),
		PackedVector2Array([Vector2(inner, -inner), Vector2(half, -inner), Vector2(half, inner), Vector2(inner, inner)]),
	]
	return _flat_mesh(quads)


## An arrow along +x from the origin, [param length] long.
static func _make_arrow(length: float) -> ArrayMesh:
	var shaft := 0.07
	var head := 0.3
	var neck := length - head
	var quads: Array[PackedVector2Array] = [
		PackedVector2Array([Vector2(0.25, -shaft), Vector2(neck, -shaft), Vector2(neck, shaft), Vector2(0.25, shaft)]),
		# The head as a quad with two corners at the tip.
		PackedVector2Array([Vector2(neck, -head * 0.7), Vector2(length, 0.0), Vector2(length, 0.0), Vector2(neck, head * 0.7)]),
	]
	return _flat_mesh(quads)


func _make_ring_instance(color: Color) -> MeshInstance3D:
	return _make_flat(_ring_mesh, color)


func _make_flat(mesh: Mesh, color: Color) -> MeshInstance3D:
	var flat := MeshInstance3D.new()
	flat.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	flat.material_override = material
	flat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return flat


# --- Builder mode: the area picked, the proposal as a ghost ------------------------------

const BUILDER_AREA := Color(0.45, 0.8, 1.0, 0.9)
## A building's code label: the area frame's blue, a little paler, this
## high over its ground and this many times a name's size.
const BUILDING_CODE := Color(0.75, 0.92, 1.0)
const CODE_HEIGHT := 4.5
const CODE_SCALE := 2.5
## A new level's outline, beyond the map's edge.
const BUILDER_BEYOND := Color(1.0, 0.7, 0.3, 0.9)
const BUILDER_GHOST_ALPHA := 0.6
## A ghost's void cell: forest outdoors, nothing indoors.
const BUILDER_VOID := Color(0.08, 0.3, 0.12)
## A ghost's cell whose height changes: from this at 0 to BUILDER_HIGH at
## Level.MAX_HEIGHT, drawn at its new height.
const BUILDER_LOW := Color(0.3, 0.27, 0.22)
const BUILDER_HIGH := Color(0.97, 0.95, 0.88)
## A roof the proposal adds: its rect outlined, raised to about the eaves.
const BUILDER_ROOF := Color(0.85, 0.35, 0.25, 0.9)
var _builder_marks: Node3D
## Builder mode's building codes over the buildings (decision 537), and
## whether they are on (kept over a rebuilt level).
var _code_labels: Node3D
var _codes_on := false


## Builder mode's marks: [param area]'s outline (size zero: none) and, over
## it, the cells and edges a proposal would change ([[x, y, meaning]...],
## [[x, y, side, kind]...]), see-through, coloured as the legend;
## [param beyond] (a new level's place past the map's edge) outlined; and
## the cells whose height changes ([[x, y, level]...]) at their new height,
## lighter the higher; and the roofs it adds ([[x, y, w, h]...]) outlined.
func show_builder(area: Rect2i, cells: Array = [], edges: Array = [], beyond := Rect2i(), heights: Array = [], roofs: Array = []) -> void:
	clear_builder()
	if area.size == Vector2i.ZERO:
		return
	_builder_marks = Node3D.new()
	add_child(_builder_marks)
	var frame := _make_flat(_frame_mesh(area, 0.08), BUILDER_AREA)
	frame.position.y = ON_FLOOR * 3.0 + _elevation(area.position)
	_builder_marks.add_child(frame)
	if beyond.size != Vector2i.ZERO:
		var far := _make_flat(_frame_mesh(beyond, 0.25), BUILDER_BEYOND)
		far.position.y = ON_FLOOR * 3.0
		_builder_marks.add_child(far)
	for each: Variant in roofs:
		var rect := Rect2i(int(each[0]), int(each[1]), int(each[2]), int(each[3]))
		var outline := _make_flat(_frame_mesh(rect, 0.12), BUILDER_ROOF)
		outline.position.y = _elevation(rect.position) + 0.75
		_builder_marks.add_child(outline)
	# Cells, one mesh a colour; a thing as a smaller square on its cell.
	var raised := {}
	for each: Variant in heights:
		raised[Vector2i(int(each[0]), int(each[1]))] = clampi(int(each[2]), 0, Level.MAX_HEIGHT)
	var by_colour := {}
	var drawn := {}
	for each: Variant in cells:
		var at := Vector2i(int(each[0]), int(each[1]))
		var meaning := str(each[2])
		# A monster kind past the default legend (507) is ghosted as a monster.
		var fallback := str(Level.LEGEND["monster_imp"]) if meaning.begins_with("monster_") else "#ff00ff"
		var colour := BUILDER_VOID if meaning == "void" else Color(str(Level.LEGEND.get(meaning, fallback)))
		var half := 0.5 if meaning in Level.GROUNDS or meaning in ["void", "water", "fire", "stair"] else 0.3
		if half == 0.5:
			drawn[at] = true
		_ghost_quad(by_colour, at, colour, half, ON_FLOOR * 4.0 if half < 0.5 else ON_FLOOR * 2.0, raised)
	for at: Vector2i in raised:
		if not drawn.has(at):
			_ghost_quad(by_colour, at, BUILDER_LOW.lerp(BUILDER_HIGH, raised[at] / float(Level.MAX_HEIGHT)), 0.5, ON_FLOOR * 2.0, raised)
	for key: String in by_colour:
		var ghost := _make_flat(_quads_mesh(by_colour[key]["quads"]), Color(by_colour[key]["colour"], BUILDER_GHOST_ALPHA))
		_builder_marks.add_child(ghost)
	# Edges: a see-through wall or door standing on each, nothing for clear.
	for each: Variant in edges:
		var kind := str(each[3])
		if kind == "clear":
			continue
		var key := Vector3i(int(each[0]), int(each[1]), int(each[2]))
		var cell := Vector2i(key.x, key.y)
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.08, 0.7, 1.0) if key.z == Terrain.EAST else Vector3(1.0, 0.7, 0.08)
		box.mesh = mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(Color(str(Level.LEGEND[kind])).lightened(0.3), BUILDER_GHOST_ALPHA)
		box.material_override = material
		box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		box.position = _tile_position(cell) + (Vector3(0.5, 0.35, 0.0) if key.z == Terrain.EAST else Vector3(0.0, 0.35, 0.5))
		_builder_marks.add_child(box)


## A ghost's square [param half] across from the middle of cell [param at],
## [param lift] above its ground (its new height in [param raised] if it
## has one, flat; else the ground as drawn, a ramp's slope too), added to
## [param by_colour]'s quads of [param colour].
func _ghost_quad(by_colour: Dictionary, at: Vector2i, colour: Color, half: float, lift: float, raised: Dictionary) -> void:
	var quad := PackedVector3Array()
	for offset: Vector2 in [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]:
		var point := Vector2(at) + offset
		var ground := float(raised[at]) * LEVEL_RISE if raised.has(at) else _height_in(at, point)
		quad.append(Vector3(point.x, ground + lift, point.y))
	var key := colour.to_html()
	if not by_colour.has(key):
		by_colour[key] = {"colour": colour, "quads": [] as Array[PackedVector3Array]}
	by_colour[key]["quads"].append(quad)


## A flat frame round the cells of [param rect], [param line] wide.
static func _frame_mesh(rect: Rect2i, line: float) -> ArrayMesh:
	var a := Vector2(rect.position) - Vector2(0.5, 0.5)
	var b := Vector2(rect.end) - Vector2(0.5, 0.5)
	var quads: Array[PackedVector2Array] = [
		PackedVector2Array([a, Vector2(b.x, a.y), Vector2(b.x, a.y + line), Vector2(a.x, a.y + line)]),
		PackedVector2Array([Vector2(a.x, b.y - line), Vector2(b.x, b.y - line), b, Vector2(a.x, b.y)]),
		PackedVector2Array([a, Vector2(a.x + line, a.y), Vector2(a.x + line, b.y), Vector2(a.x, b.y)]),
		PackedVector2Array([Vector2(b.x - line, a.y), Vector2(b.x, a.y), b, Vector2(b.x - line, b.y)]),
	]
	return _flat_mesh(quads)


## Each building's code (Level.building_codes: "H3 house") floating over
## its middle while [param on] (builder mode, decision 537).
func show_building_codes(on: bool) -> void:
	_codes_on = on
	if _code_labels != null:
		_code_labels.queue_free()
		_code_labels = null
	if not on:
		return
	_code_labels = Node3D.new()
	_code_labels.name = "BuildingCodes"
	add_child(_code_labels)
	for building: Dictionary in _drawn_buildings():
		var rect: Rect2i = building["rect"]
		var middle := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
		var label := _label("Code_%s" % building.get("code", ""), BuilderUI.building_words(building), BUILDING_CODE, 0.0)
		label.pixel_size = LABEL_SIZE * CODE_SCALE
		label.position = Vector3(middle.x, _elevation(rect.position) + CODE_HEIGHT, middle.y)
		_code_labels.add_child(label)


func clear_builder() -> void:
	if _builder_marks != null:
		_builder_marks.queue_free()
		_builder_marks = null


## The hover outline on [param tile], or hidden.
func hover(tile: Vector2i, show: bool) -> void:
	_hover.visible = show
	if show:
		_lay_on_ground(_hover, tile, ON_FLOOR)


## The channel's ring (544, ui's side): on [param tile], under the body
## being brought back, brass_bright, half again as wide at the start and
## the cell's own size as [param fraction] (0 to 1) completes, the draw's
## language (475); [param show] false hides it.
## The body a swing from where the player stands would strike (Main's
## stand_target_now, World.stand_target), ringed at its feet on [param
## tile] in brass: the swing's reach read on the body, not the cell, since
## at the low camera's angle a cell behind a body is hidden by it;
## [param show] false hides it.
func stand_ring(tile: Vector2i, show := true) -> void:
	_stand_ring.visible = show
	if show:
		_lay_on_ground(_stand_ring, tile, ON_FLOOR * 1.5)


func channel_ring(tile: Vector2i, fraction: float, show := true) -> void:
	_channel_ring.visible = show
	if show:
		var k := 1.0 + 0.5 * (1.0 - clampf(fraction, 0.0, 1.0))
		_channel_ring.scale = Vector3(k, 1.0, k)
		_lay_on_ground(_channel_ring, tile, ON_FLOOR)


## A telegraph [param id] shown on [param cells] (combat's Telegraph.cells:
## the cells that will be hit), from [param from_tick] to [param
## lands_tick] (world ticks); shown again replaces it.
func telegraph_show(id: String, cells: Array, from_tick: int, lands_tick: int, shape: Dictionary = {}) -> void:
	telegraph_drop(id)
	if _cell_quad == null:
		_cell_quad = _flat_mesh([PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])])
	var quads: Array[MeshInstance3D] = []
	var struck: Array[Vector2i] = []
	for each: Variant in cells:
		var cell := Vector2i(each) if each is Vector2i or each is Vector2 else (Vector2i(int(each[0]), int(each[1])) if each is Array and each.size() >= 2 else Vector2i(-100000, -100000))
		if cell.x <= -100000:
			continue
		struck.append(cell)
	var outline := telegraph_outline(shape)
	var curtain: MeshInstance3D = null
	if outline.is_empty() or struck.is_empty():
		for cell in struck:
			var quad := _make_flat(_cell_quad, Color(UiTheme.color("alarm"), TELEGRAPH_FAINT))
			_lay_on_ground(quad, cell, ON_FLOOR * 1.5)
			add_child(quad)
			quads.append(quad)
	else:
		var origin := Vector2(float(shape["origin"][0]), float(shape["origin"][1]))
		var fill := _make_flat(_ground_polygons_mesh(telegraph_fill_polygons(outline, origin, struck)), Color(UiTheme.color("alarm"), TELEGRAPH_FAINT))
		add_child(fill)
		quads.append(fill)
		curtain = _make_flat(_curtain_mesh(telegraph_curtain_segments(outline, origin, struck)), Color(UiTheme.color("alarm"), TELEGRAPH_FAINT * TELEGRAPH_CURTAIN_ALPHA))
		var material := curtain.material_override as StandardMaterial3D
		if material != null:
			material.no_depth_test = true
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			material.render_priority = 20
		add_child(curtain)
	_telegraphs[id] = {"quads": quads, "curtain": curtain, "cells": struck, "from": from_tick, "lands": lands_tick, "landed_at": -1}


## Combat's Telegraph.outline for [param shape]: the drawn shape as a
## polygon about the origin cell's centre, in cells, in order round it;
## [] without the class (found by name, so this parses before combat's
## side lands) or a shape that does not read.
static func telegraph_outline(shape: Dictionary) -> PackedVector2Array:
	if shape.is_empty() or not shape.has("origin"):
		return PackedVector2Array()
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if str(entry.get("class", "")) == "Telegraph":
			var script: Variant = load(str(entry.get("path", "")))
			if script is GDScript and (script as GDScript).has_method("outline"):
				var out: Variant = (script as GDScript).call("outline", shape)
				return out if out is PackedVector2Array else PackedVector2Array()
	return PackedVector2Array()


## The fill: [param outline] (about [param origin], the origin cell) cut to
## each of the [param struck] cells' squares, as polygons in grid units.
## Nothing outside the cells the blow lands on (a wall's clip).
static func telegraph_fill_polygons(outline: PackedVector2Array, origin: Vector2, struck: Array[Vector2i]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for cell in struck:
		var at := Vector2(cell) - origin
		var square := PackedVector2Array([at + Vector2(-0.5, -0.5), at + Vector2(0.5, -0.5), at + Vector2(0.5, 0.5), at + Vector2(-0.5, 0.5)])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(outline, square):
			if piece.size() < 3 or Geometry2D.is_polygon_clockwise(piece):
				continue
			var shifted := PackedVector2Array()
			for point in piece:
				shifted.append(point + origin)
			out.append(shifted)
	return out


## The curtain's pieces: each segment of [param outline] (closed) whose
## middle lies in a [param struck] cell, as [a, b] in grid units; a full
## ring's two seam segments (between its rims at one angle) are left out.
static func telegraph_curtain_segments(outline: PackedVector2Array, origin: Vector2, struck: Array[Vector2i]) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	if outline.size() < 2:
		return out
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		if a.is_equal_approx(b):
			continue
		if a.length() > 0.01 and b.length() > 0.01 and absf(angle_difference(a.angle(), b.angle())) < 0.0001 and absf(a.length() - b.length()) > 0.01:
			continue  # A seam between a ring's rims.
		var middle := (a + b) * 0.5 + origin
		var inside := false
		for cell in struck:
			if absf(middle.x - cell.x) <= 0.51 and absf(middle.y - cell.y) <= 0.51:
				inside = true
				break
		if inside:
			out.append(PackedVector2Array([a + origin, b + origin]))
	return out


## [param polygons] (grid units) as one mesh on the ground, each vertex at
## the ground's height under it plus a hair.
func _ground_polygons_mesh(polygons: Array[PackedVector2Array]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for polygon in polygons:
		var indices := Geometry2D.triangulate_polygon(polygon)
		for index in indices:
			var point := polygon[index]
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x, _height_in(Vector2i(point.round()), point) + ON_FLOOR * 1.5, point.y))
	return surface.commit()


## [param segments] ([a, b] each, grid units) as a curtain TELEGRAPH_CURTAIN
## tall standing on the ground along them.
func _curtain_mesh(segments: Array[PackedVector2Array]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in segments:
		var a := segment[0]
		var b := segment[1]
		var foot_a := Vector3(a.x, _height_in(Vector2i(a.round()), a) + ON_FLOOR * 1.5, a.y)
		var foot_b := Vector3(b.x, _height_in(Vector2i(b.round()), b) + ON_FLOOR * 1.5, b.y)
		var quad: Array[Vector3] = [foot_a, foot_b, foot_b + Vector3.UP * TELEGRAPH_CURTAIN, foot_a + Vector3.UP * TELEGRAPH_CURTAIN]
		for j: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(quad[j])
	return surface.commit()


## Telegraph [param id] ended: [param landed] true flashes it and lets it
## go; false (called off) takes it away at once.
func telegraph_land(id: String, landed: bool) -> void:
	if not _telegraphs.has(id):
		return
	if landed:
		_telegraphs[id]["landed_at"] = Time.get_ticks_msec()
	else:
		telegraph_drop(id)


func telegraph_drop(id: String) -> void:
	if not _telegraphs.has(id):
		return
	for quad: MeshInstance3D in _telegraphs[id]["quads"]:
		quad.queue_free()
	var curtain: MeshInstance3D = _telegraphs[id].get("curtain")
	if curtain != null:
		curtain.queue_free()
	_telegraphs.erase(id)


## Each frame at world [param tick]: every telegraph's fill, the flash of
## one landed, gone after TELEGRAPH_FLASH_MSEC.
func telegraph_tick(tick: int) -> void:
	var now := Time.get_ticks_msec()
	for id: String in _telegraphs.keys():
		var entry: Dictionary = _telegraphs[id]
		var alpha: float
		if int(entry["landed_at"]) >= 0:
			if now - int(entry["landed_at"]) > TELEGRAPH_FLASH_MSEC:
				telegraph_drop(id)
				continue
			alpha = TELEGRAPH_FLASH
		else:
			alpha = lerpf(TELEGRAPH_FAINT, TELEGRAPH_FULL, telegraph_fill(int(entry["from"]), int(entry["lands"]), tick))
		for quad: MeshInstance3D in entry["quads"]:
			var material := quad.material_override as StandardMaterial3D
			if material != null:
				material.albedo_color = Color(UiTheme.color("alarm"), alpha)
		var curtain: MeshInstance3D = entry.get("curtain")
		if curtain != null and curtain.material_override is StandardMaterial3D:
			(curtain.material_override as StandardMaterial3D).albedo_color = Color(UiTheme.color("alarm"), curtain_alpha(alpha))


## The curtain's alpha for the fill's [param alpha]: TELEGRAPH_CURTAIN_ALPHA
## times it, TELEGRAPH_LOW_BOOST more under a pitch below TELEGRAPH_LOW_PITCH.
func curtain_alpha(alpha: float) -> float:
	return clampf(alpha * TELEGRAPH_CURTAIN_ALPHA * (TELEGRAPH_LOW_BOOST if pitch < TELEGRAPH_LOW_PITCH else 1.0), 0.0, 1.0)


## How far a telegraph has run (0 to 1) from [param from_tick] to [param
## lands_tick] at [param tick]; 1 when the window is empty.
static func telegraph_fill(from_tick: int, lands_tick: int, tick: int) -> float:
	return 1.0 if lands_tick <= from_tick else clampf(float(tick - from_tick) / float(lands_tick - from_tick), 0.0, 1.0)


## The telegraphs shown (tests).
func telegraphs_shown() -> int:
	return _telegraphs.size()


## The aim lead on or off: [param way] the aim's direction on the grid
## (unit), the target AIM_LEAD_CELLS that way while [param on].
func aim_lead(way: Vector2, on: bool) -> void:
	_aim_lead_to = Vector3(way.x, 0.0, way.y) * AIM_LEAD_CELLS if on and way.length() > 0.0 else Vector3.ZERO


## The view's offset from the archer: the WASD lean plus the aim lead, the
## two together held to AIM_LEAD_CELLS once the lead is on (the lean alone
## as ever when it is not).
static func lead_offset(lean: Vector2, aim: Vector3) -> Vector3:
	var lean3 := Vector3(lean.x, 0.0, lean.y)
	if aim == Vector3.ZERO:
		return lean3
	return (lean3 + aim).limit_length(AIM_LEAD_CELLS)


## The bow's aim while drawn: the arc round [param origin] (the archer's
## grid point), its middle at [param angle] (radians on the grid, x as 0),
## at [param radius] cells; the marker on it at the angle; [param pips]
## beside the marker, across the aim; all at [param alpha] (the fade-in);
## [param show] false hides it all. With [param spread] (the sim's
## half-angle, radians; below 0 for none) the arc is the far end of the
## cone of flight, a wedge from the archer that long and that wide, its
## drawn half-angle eased toward the sim's over a tick.
func aim_arc(origin: Vector2, angle: float, radius: float, alpha: float, pips: int, show: bool, spread := -1.0) -> void:
	_aim_arc.visible = show and radius > 0.0
	_aim_mark.visible = _aim_arc.visible
	for i in _aim_pips.size():
		_aim_pips[i].visible = _aim_arc.visible and i < pips
	var cone := _aim_arc.visible and spread >= 0.0
	_aim_cone.visible = cone
	_aim_cone_rim.visible = cone
	if not _aim_arc.visible:
		_aim_cone_shown = -1.0
		return
	_aim_cone_shown = eased_spread(_aim_cone_shown, spread, get_process_delta_time()) if cone else -1.0
	var span := _aim_cone_shown if cone else PI * 0.5
	var lift := edge_lift()
	var moved := absf(radius - _aim_arc_radius) > 0.01 or absf(angle - _aim_arc_angle) > 0.002 or absf(span - _aim_arc_span) > 0.0005 \
			or absf(lift - _aim_arc_lift) > 0.001
	var cell := Vector2i(origin.round())
	var base := _height_in(cell, origin)
	var centre := Vector3(origin.x, base + ON_FLOOR * 2.0, origin.y)
	if moved or origin != _aim_arc_origin:
		_aim_arc_radius = radius
		_aim_arc_angle = angle
		_aim_arc_span = span
		_aim_arc_lift = lift
		_aim_arc_origin = origin
		_aim_arc.mesh = _ground_arc_mesh(origin, radius, AIM_LINE, angle, span, base)
	_aim_arc.position = centre + Vector3.UP * lift
	_aim_arc.rotation = Vector3.ZERO  # The mesh carries the angle (_make_arc).
	_tint_aim(_aim_arc, alpha * 0.8)
	if cone:
		if moved or _aim_cone.position != centre:
			_aim_cone.mesh = _cone_mesh(origin, angle, radius, span, base)
			_aim_cone_rim.mesh = _cone_rim_mesh(origin, angle, radius, span, base, lift)
		_aim_cone.position = centre
		_aim_cone_rim.position = centre
		_tint_aim(_aim_cone, alpha * (AIM_CONE_FILL_LOW if lift > 0.0 else AIM_CONE_FILL))
		_tint_aim(_aim_cone_rim, alpha * 0.8)
	var way := Vector2.from_angle(angle)
	var point := origin + way * radius
	var at := Vector3(point.x, _height_in(Vector2i(point.round()), point) + ON_FLOOR * 3.0, point.y)
	_aim_mark.position = at
	_tint_aim(_aim_mark, alpha * 0.95)
	# The pips in a row across the aim, just past the marker, centred on it.
	var across := Vector2(-way.y, way.x)
	for i in pips:
		if i >= _aim_pips.size():
			break
		var offset := across * ((i - (pips - 1) * 0.5) * AIM_PIP_GAP) + way * (AIM_MARK + AIM_PIP_GAP)
		var p := point + offset
		_aim_pips[i].position = Vector3(p.x, _height_in(Vector2i(p.round()), p) + ON_FLOOR * 3.0, p.y)
		_tint_aim(_aim_pips[i], alpha * 0.95)


## How far the cone's edges stand off the ground: AIM_EDGE_LIFT under a
## camera pitched below AIM_LOW_PITCH, else none.
func edge_lift() -> float:
	return AIM_EDGE_LIFT if pitch < AIM_LOW_PITCH else 0.0


## The drawn half-angle this frame: [param target] at once from none
## ([param shown] below 0), else [param shown] eased toward it over
## AIM_CONE_EASE_TICKS of the sim's ticks ([param delta] seconds this frame).
static func eased_spread(shown: float, target: float, delta: float) -> float:
	if shown < 0.0 or target < 0.0:
		return target
	return shown + (target - shown) * clampf(delta / (World.TICK_DT * AIM_CONE_EASE_TICKS), 0.0, 1.0)


## The cone's far end: AIM_SEGMENTS + 1 grid points at [param radius] from
## [param origin], from [param angle] - [param half] to [param angle] +
## [param half].
static func cone_points(origin: Vector2, angle: float, radius: float, half: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in AIM_SEGMENTS + 1:
		out.append(origin + Vector2.from_angle(angle - half + 2.0 * half * i / AIM_SEGMENTS) * radius)
	return out


## A grid point of the cone as a vertex relative to the archer's cell at
## [param base] height: on the ground under it (a wedge over a slope follows it).
func _cone_vertex(origin: Vector2, point: Vector2, base: float, lift: float) -> Vector3:
	return Vector3(point.x - origin.x, _height_in(Vector2i(point.round()), point) - base + lift, point.y - origin.y)


## How many pieces an arc [param length] cells long is drawn in: AIM_STRIP
## a piece, AIM_SEGMENTS at least.
static func arc_pieces(length: float) -> int:
	return maxi(AIM_SEGMENTS, ceili(length / AIM_STRIP))


## The aim's ring on the ground: the band [param radius] to its middle and
## [param line] wide, [param span] either side of [param angle], as a strip
## of quads AIM_STRIP long at most, each corner on the ground under it,
## relative to the archer's cell at [param base] (_cone_vertex). The node
## carries the floor bias and the low camera's lift (aim_arc).
func _ground_arc_mesh(origin: Vector2, radius: float, line: float, angle: float, span: float, base: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := radius - line * 0.5
	var outer := radius + line * 0.5
	var pieces := arc_pieces(2.0 * span * radius)
	for i in pieces:
		var a0 := angle - span + 2.0 * span * i / pieces
		var a1 := angle - span + 2.0 * span * (i + 1) / pieces
		var quad: Array[Vector3] = [_cone_vertex(origin, origin + Vector2.from_angle(a0) * inner, base, 0.0),
			_cone_vertex(origin, origin + Vector2.from_angle(a0) * outer, base, 0.0),
			_cone_vertex(origin, origin + Vector2.from_angle(a1) * outer, base, 0.0),
			_cone_vertex(origin, origin + Vector2.from_angle(a1) * inner, base, 0.0)]
		for j: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(quad[j])
	return surface.commit()


## The cone's fill: rings AIM_STRIP apart from the archer to its far end,
## each ring's points AIM_STRIP apart at most, every vertex on the ground
## under it, so the wedge lies on whatever ground rises or falls between.
func _cone_mesh(origin: Vector2, angle: float, radius: float, half: float, base: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := maxi(ceili(radius / AIM_STRIP), 1)
	var pieces := arc_pieces(2.0 * half * radius)
	var apex := Vector3(0.0, ON_FLOOR, 0.0)
	var last: Array[Vector3] = []
	for r in range(1, rings + 1):
		var ring: Array[Vector3] = []
		for i in pieces + 1:
			var point := origin + Vector2.from_angle(angle - half + 2.0 * half * i / pieces) * (radius * r / rings)
			ring.append(_cone_vertex(origin, point, base, ON_FLOOR))
		for i in pieces:
			var corners: Array[Vector3] = []
			if r == 1:
				corners.assign([apex, ring[i], ring[i + 1]])
			else:
				corners.assign([last[i], ring[i], ring[i + 1], last[i], ring[i + 1], last[i + 1]])
			for vertex in corners:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(vertex)
		last = ring
	return surface.commit()


## The cone's two sides as lines AIM_LINE wide from the archer to the far
## end's corners, a piece AIM_STRIP long so each follows the ground,
## [param lift] above it.
func _cone_rim_mesh(origin: Vector2, angle: float, radius: float, half: float, base: float, lift := 0.0) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pieces := maxi(ceili(radius / AIM_STRIP), 1)
	for side: float in [-1.0, 1.0]:
		var way := Vector2.from_angle(angle + side * half)
		var across := Vector2(-way.y, way.x) * AIM_LINE * 0.5
		for i in pieces:
			var a := origin + way * (radius * i / pieces)
			var b := origin + way * (radius * (i + 1) / pieces)
			var quad: Array[Vector3] = [_cone_vertex(origin, a - across, base, ON_FLOOR * 1.5 + lift), _cone_vertex(origin, b - across, base, ON_FLOOR * 1.5 + lift),
				_cone_vertex(origin, b + across, base, ON_FLOOR * 1.5 + lift), _cone_vertex(origin, a + across, base, ON_FLOOR * 1.5 + lift)]
			for j: int in [0, 1, 2, 0, 2, 3]:
				surface.set_normal(Vector3.UP)
				surface.add_vertex(quad[j])
	return surface.commit()


func _tint_aim(flat: MeshInstance3D, alpha: float) -> void:
	var material := flat.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(UiTheme.color("brass_bright"), clampf(alpha, 0.0, 1.0))


## A bow's draw read in the world (decision 475, ui's): the hover ring and
## the outline tighten and brighten as [param fraction] (World.draw_of, 0 to
## 1) completes: the ring half again as wide and dim at the start, the
## cell's own size in brass_bright at a full draw; the outline's passes
## nudged wider and paler at the start, their own width and brass at the
## end. [param fraction] below 0: the plain look (no draw).
func draw_look(fraction: float) -> void:
	var drawing := fraction >= 0.0
	var k := 1.0 if not drawing else 1.0 + 0.6 * (1.0 - clampf(fraction, 0.0, 1.0))
	_hover.scale = Vector3(k, 1.0, k)
	var ring_material := _hover.material_override as StandardMaterial3D
	if ring_material != null:
		var brass := UiTheme.color("brass_bright")
		ring_material.albedo_color = HOVER if not drawing else HOVER.lerp(Color(brass, 0.9), clampf(fraction, 0.0, 1.0))
	var pass_ := _outline
	while pass_ != null:
		var nudge: Vector2 = pass_.get_shader_parameter("nudge")
		if nudge.length() > 0.0:
			pass_.set_shader_parameter("nudge", nudge.normalized() * TARGET_PIXELS * k)
		pass_.set_shader_parameter("colour", TARGET_OUTLINE if not drawing
				else TARGET_OUTLINE.lerp(UiTheme.color("brass_bright"), clampf(fraction, 0.0, 1.0)))
		pass_ = pass_.next_pass as ShaderMaterial


## Outlines [param entity] as the one the next click attacks, and nothing
## else (null: none).
func target(entity: GridEntity) -> void:
	var puppet: Node3D = _puppets.get(entity.get_instance_id()) if entity != null else null
	if puppet == _outlined:
		return
	_show_outline(_outlined, false)
	_outlined = puppet
	_show_outline(puppet, true)


## [param puppet]'s outline shown or hidden: its body's meshes with the
## outline's passes over them and marking the stencil, or as they were.
func _show_outline(puppet: Node3D, show: bool, rim: ShaderMaterial = null) -> void:
	if puppet == null or not is_instance_valid(puppet):
		return
	var body := puppet.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	if body is MeshInstance3D:
		meshes.append(body)
	for source: MeshInstance3D in meshes:
		source.material_overlay = (rim if rim != null else _outline) if show else null
		_mark_stencil(source, show)


## Each frame: the foes seen through what hides them (SEEN_OUTLINE). The
## marked target keeps its own rim.
func _update_seen_through() -> void:
	if _camera == null:
		return
	var now := Time.get_ticks_msec()
	for id: int in _puppets:
		var puppet := _puppets[id]
		var had := puppet.has_meta("seen_through")
		if puppet == _outlined:
			if had:
				puppet.remove_meta("seen_through")  # Its target's rim is on it now (target()).
			continue
		var entity := instance_from_id(id) as GridEntity
		var seen := false
		if entity is Monster and entity.spawned and entity.hp > 0 and not _far.has(id) and puppet.visible:
			var alert: Monster.Alert = (entity as Monster).alert
			var fights: bool = alert == Monster.Alert.FIGHTING or alert == Monster.Alert.HUNTING \
					or now - _combat_at.get(id, -100000) < COMBAT_SECONDS * 1000.0
			seen = in_telegraph(entity.tile) or (fights and hidden_by_body(puppet, id))
		if seen != had:
			if seen:
				puppet.set_meta("seen_through", true)
			else:
				puppet.remove_meta("seen_through")
			_show_outline(puppet, seen, _seen_through)


## Whether a body (a pick shape with an entity, not [param id]'s own)
## stands between the camera and [param puppet]'s chest. Walls, doors and
## the ground are not asked: a wall that hides a foe fades instead.
func hidden_by_body(puppet: Node3D, id: int) -> bool:
	var chest := puppet.global_position + Vector3.UP * (float(puppet.get_meta("pick_height", 1.0)) * 0.6)
	var ahead := -_camera.global_transform.basis.z
	var origin := _camera.global_position if _camera.projection == Camera3D.PROJECTION_PERSPECTIVE else chest - ahead * CAMERA_DISTANCE * 3.0
	var query := PhysicsRayQueryParameters3D.create(origin, chest)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	for i in PICK_DEPTH:
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return false
		var area: Area3D = hit["collider"]
		if area.has_meta("entity"):
			var other := int(area.get_meta("entity"))
			if other == id:
				return false
			var body := instance_from_id(other) as GridEntity
			if body != null and body.spawned:
				return true
		exclude.append(hit["rid"])
	return false


## Whether [param tile] lies in an active telegraph (shown, not yet landed).
func in_telegraph(tile: Vector2i) -> bool:
	for entry: Dictionary in _telegraphs.values():
		if int(entry["landed_at"]) < 0 and tile in entry["cells"]:
			return true
	return false


## [param source] drawn with its materials' copies that mark the stencil
## (OUTLINE_STENCIL) where it draws, or ([param mark] false) with its own
## again, its surfaces' own overrides too (a painted ally's paint, the
## palette: put back, not cleared, or a body unmarked, as one is when it
## dies, went white). The copies look the same.
func _mark_stencil(source: MeshInstance3D, mark: bool) -> void:
	if not mark:
		if source.has_meta("own_override"):
			source.material_override = source.get_meta("own_override")
			source.remove_meta("own_override")
			var own_surfaces: Array = source.get_meta("own_surfaces", [])
			for surface in source.get_surface_override_material_count():
				source.set_surface_override_material(surface, own_surfaces[surface] if surface < own_surfaces.size() else null)
			source.remove_meta("own_surfaces")
		return
	if source.has_meta("own_override"):
		return
	source.set_meta("own_override", source.material_override)
	var kept: Array[Material] = []
	for surface in source.get_surface_override_material_count():
		kept.append(source.get_surface_override_material(surface))
	source.set_meta("own_surfaces", kept)
	if source.material_override != null:
		source.material_override = _marking_copy(source.material_override)
		return
	for surface in source.get_surface_override_material_count():
		var own := source.get_active_material(surface)
		if own != null:
			source.set_surface_override_material(surface, _marking_copy(own))


## [param material]'s copy that marks the stencil as it draws (cached).
func _marking_copy(material: Material) -> Material:
	if not _marking.has(material):
		var copy := material.duplicate() as Material
		if copy is BaseMaterial3D:
			copy.stencil_mode = BaseMaterial3D.STENCIL_MODE_CUSTOM
			copy.stencil_flags = BaseMaterial3D.STENCIL_FLAG_WRITE
			copy.stencil_compare = BaseMaterial3D.STENCIL_COMPARE_ALWAYS
			copy.stencil_reference = OUTLINE_STENCIL
		elif copy is ShaderMaterial and (material as ShaderMaterial).shader == GOBLIN_MATERIAL.shader:
			(copy as ShaderMaterial).shader = GOBLIN_MARKING_SHADER
		_marking[material] = copy
	return _marking[material]


## The toss aim during a right drag: an arrow on the floor from
## [param target] the way it will go; hidden for ZERO or no target.
## Sound slot [param slot] from where [param entity] is drawn (Sfx).
func play_at(slot: String, entity: GridEntity) -> void:
	var puppet: Node3D = _puppets.get(entity.get_instance_id())
	sfx.play(slot,(puppet.position if puppet != null else _tile_position(entity.tile)) + Vector3.UP * 0.5)


func toss_aim(target: GridEntity, direction: Vector2i) -> void:
	_toss.visible = direction != Vector2i.ZERO and is_instance_valid(target)
	if not _toss.visible:
		return
	var puppet: Node3D = _puppets.get(target.get_instance_id())
	var at := puppet.position if puppet != null else _tile_position(target.tile)
	_toss.position = Vector3(at.x, _ground_height(Vector2(at.x, at.z)) + ON_FLOOR * 3.0, at.z)
	_toss.rotation.y = -Vector2(direction).angle()


## Where a speech bubble of [param key] points on screen: just above the
## name of the entity with that instance id, or over a corpse puppet with
## that one; null when there is none or it is behind the camera.
func bubble_anchor(key: int) -> Variant:
	var puppet: Node3D = _puppets.get(key)
	if puppet == null:
		puppet = instance_from_id(key) as Node3D
	if puppet == null or not puppet.is_inside_tree() or _camera == null:
		return null
	var at := puppet.global_position + Vector3.UP * float(puppet.get_meta("bubble_height", 1.0))
	if _camera.is_position_behind(at) or (_low and not puppet.visible):
		return null
	return _camera.unproject_position(at)


## Screen px per tile now: the ortho size is the view's height in units.
func tile_px() -> float:
	if _camera == null or _camera.size <= 0.0:
		return SpeechBubbles.REFERENCE_TILE_PX
	return get_viewport().get_visible_rect().size.y / _camera.size


## The click ripple: a ring that grows from a few px to the cell and fades
## over RIPPLE_SECONDS, then is gone.
func ripple(tile: Vector2i) -> void:
	var ring := _make_ring_instance(RIPPLE)
	_lay_on_ground(ring, tile, ON_FLOOR * 2.0)
	add_child(ring)
	var material := ring.material_override as StandardMaterial3D
	ring.scale = Vector3(0.2, 1.0, 0.2)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(1.4, 1.0, 1.4), RIPPLE_SECONDS)
	tween.tween_property(material, "albedo_color:a", 0.0, RIPPLE_SECONDS)
	tween.chain().tween_callback(ring.queue_free)


# --- Room ----------------------------------------------------------------------

## A cell's centre on its ground, at its height (on a slope, as drawn).
func _tile_position(tile: Vector2i) -> Vector3:
	return Vector3(tile.x, _height_in(tile, Vector2(tile)), tile.y)


## This view's terrain, not the World's: the room is built before the World
## has its terrain, and a client's World mirrors the same map anyway.
func _height(cell: Vector2i) -> int:
	return int(_terrain.get("heights", {}).get(cell, 0))


func _stair(cell: Vector2i) -> Vector2i:
	return _terrain.get("stairs", {}).get(cell, Vector2i.ZERO)


## The room drawn afresh for [param terrain] (a map loaded live).
func rebuild(terrain: Dictionary, centre: Vector2i) -> void:
	_terrain = terrain
	_centre = centre
	if _room != null:
		_room.free()
	_pile_nodes.clear()
	_walls.clear()
	_wall_breaches.clear()
	_scattered.clear()
	_scatter_due.clear()
	_scatter_jobs.clear()
	_scatter_aim = Vector2i(1 << 30, 0)
	_posts.clear()
	_doorways.clear()
	_door_hinges.clear()
	_door_states.clear()
	_doors_due.clear()
	_grounds.clear()
	_ground_kinds.clear()
	torch_cells.clear()
	_ground_shades.clear()
	_shade_all = true
	_trees.clear()
	_saplings.clear()
	_clearing_props.clear()
	_scatter_nodes.clear()
	_border = null
	_grown = null
	_grown_trunks.clear()
	_glimpses.clear()
	_buildings.clear()
	_building_at.clear()
	_stand_at.clear()
	_roofs_off.clear()
	_runs.clear()
	_water_bodies.clear()
	_stream_ribbons.clear()
	_fall_feet.clear()
	_mists.clear()
	_occluders.clear()
	_occluders_built = false
	_faded.clear()
	_hiding.clear()
	_hid_at.clear()
	_fade_key = ""
	_apply_sky()
	_build_room()
	_classify_walls()
	_camera_target = _tile_position(_centre)
	# A new map: the view starts on the player.
	pan = Vector3.ZERO
	_pan_home = false
	_apply_camera_mode()  # Outdoors or under stone now (623).
	_start_warm_ups()


## The depth pass every near material draws first (_make_near).
static var _near_depth: ShaderMaterial


func _stone(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(STONE, alpha)
	material.roughness = 0.9
	if alpha < 1.0:
		_make_near(material)
	return material


## [param material] as a near piece is drawn: see-through, its nearest
## surface only (NEAR_DEPTH_SHADER first, as its next pass).
static func _make_near(material: BaseMaterial3D) -> void:
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = NEAR_PRIORITY
	material.next_pass = _near_depth_pass()


## The depth pass a see-through copy draws after itself, made once.
static func _near_depth_pass() -> ShaderMaterial:
	if _near_depth == null:
		var shader := Shader.new()
		shader.code = NEAR_DEPTH_SHADER
		_near_depth = ShaderMaterial.new()
		_near_depth.shader = shader
		_near_depth.render_priority = NEAR_DEPTH_PRIORITY
	return _near_depth


## Each material as the season draws it, by [its id, leaf]: [the season's,
## the material] (held, so its id is never another's).
static var _season_materials: Dictionary = {}


## [param material] (a BaseMaterial3D: the palette, a fill's, a flat colour,
## vertex colours) drawn in season (season.gdshader): its own look, then
## snow on what faces up, and with [param leaf] its foliage dried out of
## season and turned in autumn. Kept and shared by material and leaf
## unless not [param shared] (a material made for one build). Its
## see-through copy beside it (SEASON_NEAR_META), for the near fade.
static func season_material(material: Material, leaf: bool, shared := true) -> Material:
	var base := material as BaseMaterial3D
	if base == null:
		return material
	var key := [base.get_instance_id(), leaf]
	if shared and _season_materials.has(key):
		return _season_materials[key][0]
	var made := _season_copy(SEASON_SHADER, base, leaf)
	var near := _season_copy(SEASON_NEAR_SHADER, base, leaf)
	near.set_shader_parameter("alpha", NEAR_ALPHA)
	near.render_priority = NEAR_PRIORITY
	near.next_pass = _near_depth_pass()
	made.set_meta(SEASON_NEAR_META, near)
	if shared:
		_season_materials[key] = [made, base]
	return made


static func _season_copy(shader: Shader, base: BaseMaterial3D, leaf: bool) -> ShaderMaterial:
	var made := ShaderMaterial.new()
	made.shader = shader
	made.set_shader_parameter("albedo_color", base.albedo_color)
	made.set_shader_parameter("use_texture", base.albedo_texture != null)
	if base.albedo_texture != null:
		made.set_shader_parameter("albedo_texture", base.albedo_texture)
	made.set_shader_parameter("use_vertex_color", base.vertex_color_use_as_albedo)
	made.set_shader_parameter("vertex_srgb", base.vertex_color_is_srgb)
	made.set_shader_parameter("roughness", base.roughness)
	made.set_shader_parameter("leaf", leaf)
	return made


## [param node]'s meshes drawn in season (season_material): their
## overrides, else their surfaces' materials, as overrides.
static func season_dress(node: Node, leaf: bool) -> void:
	var walk: Array[Node] = [node]
	while not walk.is_empty():
		var next := walk.pop_back() as Node
		walk.append_array(next.get_children())
		var mesh := next as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		if mesh.material_override != null:
			mesh.material_override = season_material(mesh.material_override, leaf)
			continue
		for surface in mesh.mesh.get_surface_count():
			var own := mesh.get_surface_override_material(surface)
			if own == null:
				own = mesh.mesh.surface_get_material(surface)
			if own != null:
				mesh.set_surface_override_material(surface, season_material(own, leaf))


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


func _build_room() -> void:
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_stone_opaque = _stone(1.0)
	# The map's sets; a building's walls and inside in its slot's sets
	# (decision 285): the last map's buildings' out, this one's in, what
	# else is in the sets left as it is.
	# A well's water is drawn as the ground round it, under its rim.
	_walls_set = _known_set(str(_terrain.get("walls", DEFAULT_SET)))
	_floors_set = _known_set(str(_terrain.get("floors", DEFAULT_SET)))
	for key in _building_walls:
		_wall_sets.erase(key)
		_wall_heights.erase(key)
	_building_walls.clear()
	_pad_cell.clear()
	_plinths.clear()
	_ruin_edges.clear()
	# A damaged building's and a town wall's looks: the last map's out.
	for key in _state_walls:
		_wall_states.erase(key)
	_state_walls.clear()
	_window_flipped.clear()
	_window_code.clear()
	_glows.clear()
	for key in _town_wall_sets:
		_wall_sets.erase(key)
	_town_wall_sets.clear()
	_town_walls.clear()
	for cell in _building_floors:
		_floor_sets.erase(cell)
	_building_floors.clear()
	for cell in _building_dry:
		_dry_water.erase(cell)
	_building_dry.clear()
	for building: Dictionary in _drawn_buildings():
		_building_sets(building)
	_warm_art()
	var fire: Array[Vector2i] = _terrain["fire"]
	var kinds: Dictionary = _terrain.get("kinds", {})
	_clearing.assign(_terrain.get("clearing", {}))
	_grown_back.clear()
	# A new set each build, never changed after: the border's worker reads it.
	_land = {}
	for cell: Vector2i in _terrain["floor"] + _terrain.get("water", []):
		_land[cell] = true
	# Rocks (decision 513, terrain's side) are the land's too: ground under a
	# rock, where the void's would be a tree.
	_rocks.clear()
	for cell: Vector2i in _terrain.get("rocks", []):
		_rocks[cell] = true
		_land[cell] = true
	# A solid building's cells (decision 550) are land under its mesh, no tree.
	_solid_cells.clear()
	for cell: Vector2i in _terrain.get("solid", []):
		_land[cell] = true
		_solid_cells[cell] = true
	_glimpse_plans.clear()
	if _outdoor:
		_glimpse_plans = _plan_glimpses()
	_wooded = _land
	if not _glimpse_plans.is_empty():
		_wooded = _land.duplicate()
		for plan: Dictionary in _glimpse_plans:
			for cell: Vector2i in plan["cells"]:
				_wooded[cell] = true
	var grown := {}
	if _outdoor and str(_terrain.get("canopy_kind", "")) != "":
		grown = GrownTrees.data_for(str(_terrain.get("level", "")))
		_grown_trunks = GrownTrees.trunk_cells(grown, _land)
		if not _grown_trunks.is_empty():
			_wooded = _wooded.duplicate()
			_wooded.merge(_grown_trunks)
	_forest_distance.clear()
	if _outdoor:
		_forest_distance = _measure_forest()
	_read_edges()
	_read_field()
	_sight_key = Vector4.INF  # A new ground: ask again whether it hides the player.
	_bed_levels.clear()
	_corners.clear()
	_wet.clear()
	_shape_ramps()
	_build_ground(kinds)
	_fire_lights.clear()
	for cell: Vector2i in fire:
		if _grounds.has(cell):
			_add_fire(cell)
	_build_water()
	_add_cliffs()
	_add_rocks()
	for cell: Vector2i in _terrain.get("torches", []):
		_add_torch(cell)
	for cell: Vector2i in _terrain.get("lanterns", []):
		_add_lantern(cell)
	if not World.fields_changed_signal.is_connected(_on_fields_changed):
		World.fields_changed_signal.connect(_on_fields_changed)
	_on_fields_changed()
	_add_walls()
	_add_decor()
	if _outdoor:
		_add_forest()
		for cell: Vector2i in _clearing:
			_dress_clearing(cell)
		if not _grown_trunks.is_empty():
			var ground: Dictionary[Vector2i, bool] = {}
			for cell: Vector2i in _terrain["floor"]:
				ground[cell] = true
			_grown = GrownTrees.new()
			_grown.name = "GrownTrees"
			_room.add_child(_grown)
			_grown.build(grown, _land, ground, _elevations(), 1.0, str(_terrain["canopy_kind"]) == "broadleaf")
		if str(_terrain.get("border", "forest")) != "none":
			_border = TerrainBorder.new()
			_border.name = "Border"
			_room.add_child(_border)
			_border.build(_wooded, _elevations(), 1.0, _forest_floor_colour(), FOREST_FLOOR_DEPTH, true, PineStands.drawn())
		for plan: Dictionary in _glimpse_plans:
			_add_glimpse(plan)
	_add_buildings()
	_add_link_cues()
	_add_roofs()
	_add_town_walls()
	# Every door's leaf set once; from then on those that change.
	if not World.door_shown.is_connected(_on_door_shown):
		World.door_shown.connect(_on_door_shown)
	if not World.grass_changed.is_connected(_on_grass_changed):
		World.grass_changed.connect(_on_grass_changed)
	for door in World.get_doors():
		_doors_due[door.key] = true
	_show_piles()


## The walls, doorways and posts of the terrain's edges; none along an
## outdoor map's outline, which is the forest's edge, nor round an open-air
## building (Level.OPEN_AIR), whose slot draws its fence.
func _add_walls() -> void:
	_read_niches()
	var edges: Dictionary = _terrain["edges"]
	var kind_at := func(key: Vector3i) -> int: return edges.get(key, Terrain.Edge.OPEN)
	var vertices: Dictionary[Vector2i, bool] = {}
	var wall_keys: Array[Vector3i] = []
	var doubles := _double_doors()
	var seconds := doubles.values()
	var fences := _fence_keys()
	for key: Vector3i in edges:
		if not _edge_drawn(key, fences):
			continue
		match edges[key]:
			Terrain.Edge.WALL:
				if BOX_WALLS:
					_add_wall(key)
				else:
					wall_keys.append(key)
			Terrain.Edge.DOOR:
				# The hidden niche's door is no doorway but its wall (608).
				if _niche_at.has(key) and str(_niche_at[key]["kind"]) == "hidden":
					_add_hidden_niche(key)
				elif not key in seconds:
					_add_doorway(key, doubles.get(key, key))
			_:
				continue
		for end in 2:
			vertices[WallEdge.vertex_at(key, end)] = true
	_add_wall_runs(wall_keys)
	for vertex in vertices:
		if _needs_post(vertex, kind_at) or _sets_meet(vertex):
			_add_post(vertex)


## The edges that are a fence, not a wall: an open-air building's outline
## (Level.OPEN_AIR, its slot draws the fence) and a bridge's railings
## (decision 505, its slot draws them).
func _fence_keys() -> Dictionary[Vector3i, bool]:
	var fences: Dictionary[Vector3i, bool] = {}
	for building: Dictionary in _terrain.get("buildings", []):
		if building["slot"] in Level.OPEN_AIR:
			for key in Level.building_outline(building):
				fences[key] = true
	for key: Vector3i in _terrain.get("railings", []):
		fences[key] = true
	return fences


## Whether edge [param key] is drawn as what it is: not outdoors on the
## outline (the forest's edge, _add_forest), nor a wall that is a fence
## ([param fences], _fence_keys) or a rock's own (decision 513: the rock is
## drawn, not a wall round it).
func _edge_drawn(key: Vector3i, fences: Dictionary[Vector3i, bool]) -> bool:
	var kind: int = _terrain["edges"].get(key, Terrain.Edge.OPEN)
	if kind == Terrain.Edge.OPEN or _outdoor and _is_outline(key):
		return false
	return kind != Terrain.Edge.WALL or not fences.has(key) and not _rock_edge(key)


## Each link's cue (decision 589: Level.link_cues): art-kit's piece on its
## cell, its front (+Z) the way out: a gate arch over it, a waystone either
## side of it (the cells beside, as scenery), a stair down or up; nothing for
## "sealed" (its own slab) or "none". Drawn only: the cell is walked on.
func _add_link_cues() -> void:
	for cue: Dictionary in _terrain.get("link_cues", []):
		var slot := str(Level.CUE_SLOTS.get(cue["cue"], ""))
		if slot.is_empty() or not ArtKit.has(slot):
			continue
		var at: Vector2i = cue["tile"]
		var facing: Vector2i = cue["facing"]
		var places: Array[Vector2i] = [at]
		if cue["cue"] == "waystones":
			var across := Vector2i(facing.y, facing.x)
			places = [at + across, at - across]
		for cell in places:
			var node := ArtKit.instance(slot, int(cue["variant"]))
			node.name = "Cue_%d_%d" % [cell.x, cell.y]
			node.position = Vector3(cell.x, _elevation(cell), cell.y)
			node.rotation.y = atan2(float(facing.x), float(facing.y))
			_room.add_child(node)


## The terrain's buildings (Level.buildings_from): art-kit's slot over each
## footprint, its front (+Z) to the building's facing, standing on its
## ground; the slot's "roof" part is what hides while the local player is
## inside (_update_roofs). The walls are the map's own wall runs.
func _add_buildings() -> void:
	if _codes_on:
		show_building_codes.call_deferred(true)
	_plots_drawn.clear()
	for building: Dictionary in _drawn_buildings():
		if building.get("plot", false):
			_plots_drawn[(building["rect"] as Rect2i).position] = true
		if building.has("kind"):
			_add_kind(building)
			continue
		if str(building["slot"]) in Level.SPANS_WATER:
			_add_bridge(building)
			continue
		var rect: Rect2i = building["rect"]
		var slot := str(building["slot"])
		var facing: Vector2i = building["facing"]
		var node := ArtKit.instance(slot, int(building.get("variant", 1)))
		# Leaves that turn with the seasons (a great tree's crown, 567).
		if ArtKit.spec(slot).get("leaf", false):
			season_dress(node, true)
		# Whole (decision 287): its damaged roof and its rubble shown only damaged.
		var damaged := node.find_children("state_*", "Node3D", true, false)
		if node.get_node_or_null("roof_damaged") != null:
			damaged.append(node.get_node("roof_damaged"))
		for part: Node3D in damaged:
			part.visible = false
		var middle := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
		node.position = Vector3(middle.x, _elevation(rect.position), middle.y)
		node.rotation.y = deg_to_rad(float(building["yaw"])) if building.has("yaw") else atan2(float(facing.x), float(facing.y))
		_room.add_child(node)
		var index := _buildings.size()
		var roof: Node3D = node.get_node_or_null("roof")
		_buildings.append({"rect": rect, "node": node, "roof": roof, "off": false, "roof_at": roof.transform if roof != null else Transform3D(),
			"use": str(building.get("use", "")), "town_id": str(building.get("town_id", "")), "damaged": false,
			"open_air": slot in Level.OPEN_AIR, "crop": ""})
		_show_state(_buildings[index])
		if ArtKit.spec(slot).get("stand") is Array:
			for cell in Level.rect_cells(rect):
				_stand_at[cell] = stand_offset(slot, rect, node.rotation.y, cell)
		if slot in Level.ON_WATER or slot in Level.OPEN_AIR or _glimpse:
			continue  # Nobody stands in a well, a field is open (or a glimpse): no inside.
		# The rain stops on its roof even while the roof is cut away
		# (decision 309; WeatherView's heightfield sees only what is drawn).
		var keep_dry := GPUParticlesCollisionBox3D.new()
		var eaves := float(ArtKit.spec(slot).get("wall_height", WALL_HEIGHT))
		keep_dry.size = Vector3(rect.size.x, eaves, rect.size.y)
		keep_dry.position = Vector3(middle.x, _elevation(rect.position) + eaves * 0.5, middle.y)
		_room.add_child(keep_dry)
		for cell in Level.rect_cells(rect):
			_building_at[cell] = index


## The buildings drawn: the level's, and its towns' laid plots' (591
## amended, Level.plot_building), raised by their records' stages (566).
func _drawn_buildings() -> Array:
	return _terrain.get("buildings", []) + _terrain.get("plot_buildings", [])


## [param building]'s walls and floor in its sets (decision 285): its
## outline's wall sets and heights, a kind's pad and plinth, windows and a
## ruin's breaks, its floor set; a well's water dry under it.
func _building_sets(building: Dictionary) -> void:
	if building["slot"] in Level.ON_WATER:
		for cell in Level.rect_cells(building["rect"]):
			if not _dry_water.has(cell):
				_building_dry.append(cell)
				_dry_water[cell] = true
		return
	if building["slot"] in Level.OPEN_AIR or building["slot"] in Level.SPANS_WATER:
		return  # Its fence (a bridge's railings) is its slot's mesh; a bridge's water stays.
	# A kind (decision 488) names its sets and eaves; a slot's spec does.
	var spec: Dictionary = {"wall_set": building["wall_set"], "wall_height": building["eaves"], "floor_set": building["floor_set"]} \
			if building.has("kind") else ArtKit.spec(str(building["slot"]))
	if str(spec.get("floor_set", "")).is_empty():
		spec.erase("floor_set")
	var wall_set := _known_set(str(spec.get("wall_set", _walls_set)))
	var wall_height := float(spec.get("wall_height", WALL_HEIGHT))
	# A kind's walls each to its block's eaves (BuildingComposer, 489).
	var heights: Dictionary[Vector3i, float] = {}
	var windows: Array[Vector3i] = []
	var cells: Dictionary[Vector2i, bool] = {}
	var pad := Vector2i.ZERO
	if building.has("kind"):
		heights = BuildingComposer.wall_heights(building)
		windows = BuildingComposer.windows(building, _terrain["edges"])
		for cell in Level.building_cells(building):
			cells[cell] = true
		pad = cells.keys()[0]
	for key in Level.building_outline(building):
		if not _wall_sets.has(key):
			_building_walls.append(key)
			_wall_sets[key] = wall_set
			var tall: float = heights.get(key, wall_height)
			if not is_equal_approx(tall, WALL_HEIGHT):
				_wall_heights[key] = tall
			if building.has("kind"):
				_pad_cell[key] = pad
				if wall_set == "wood":
					_plinths[key] = true
		# A kind's windows (489 amended), its wood walls of a storey's height:
		# art-kit's window there, turned so its shutters open outward.
		if building.has("kind") and wall_set == "wood" and key in windows \
				and absf(_height_of(key) - WALL_HEIGHT) <= WINDOW_STRETCH:
			_set_wall_state(key, "window")
			_window_code[key] = [str(building.get("town_id", "")), str(building.get("code", "")), true]
			var sides := Terrain.edge_cells(key)
			# A run's +x is east for an east edge, north (its first cell) for a south one.
			var outside_first := not cells.has(sides[0])
			_window_flipped[key] = outside_first if key.z == Terrain.EAST else not outside_first
		# A ruin's walls broken here and there before they are drawn (489).
		if building.get("ruined", false) and _terrain["edges"].get(key) == Terrain.Edge.WALL \
				and _roll(Vector2i(key.x, key.y), 40 + key.z) < RUIN_BROKEN:
			_set_wall_state(key, "broken")
	if spec.has("floor_set"):
		var floor_set := _known_set(str(spec["floor_set"]))
		for cell in Level.building_cells(building):
			if not _floor_sets.has(cell):
				_building_floors.append(cell)
				_floor_sets[cell] = floor_set


## A town's plots laid or dropped since the room was built (591 amended
## (step 2), 649; Main lays them in the terrain, Clearing.lay_plots, or
## takes them out, Clearing.unlay_plot, then calls clearing_changed): a
## laid one's sets, its kind drawn at its record's stage, its walls drawn
## (its floor set waits for the next build of the room); a dropped one's
## building hidden, its sets out, its walls drawn again from the edges left.
func _sync_plots() -> void:
	var walls: Array[Vector3i] = []
	var laid: Dictionary[Vector2i, bool] = {}
	for building: Dictionary in _terrain.get("plot_buildings", []):
		var at: Vector2i = (building["rect"] as Rect2i).position
		laid[at] = true
		if _plots_drawn.has(at):
			continue
		_plots_drawn[at] = true
		_building_sets(building)
		_add_kind(building)
		walls.append_array(Level.building_outline(building))
	for at: Vector2i in _plots_drawn.keys():
		if not laid.has(at):
			_plots_drawn.erase(at)
			walls.append_array(_drop_plot(at))
	if not walls.is_empty():
		rebuild_walls(walls)


## The drawn plot whose rect's corner is [param at] taken down: its
## building hidden and done with ("dropped": no stage, roof or inside), its
## outline's sets and looks out. Its outline, to draw again.
func _drop_plot(at: Vector2i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for index in _buildings.size():
		var entry := _buildings[index]
		if not entry.get("plot", false) or entry.get("dropped", false) or (entry["rect"] as Rect2i).position != at:
			continue
		entry["dropped"] = true
		(entry["node"] as Node3D).visible = false
		entry["roof"] = null
		for cell: Vector2i in entry["inside"]:
			if _building_at.get(cell, -1) == index:
				_building_at.erase(cell)
		for key: Vector3i in entry["outline"]:
			_wall_sets.erase(key)
			_wall_heights.erase(key)
			_pad_cell.erase(key)
			_plinths.erase(key)
			_window_code.erase(key)
			_window_flipped.erase(key)
			if _wall_states.has(key):
				_wall_states.erase(key)
			_building_walls.erase(key)
			out.append(key)
	return out


## A building of a kind (Level.kinds, decision 488): its walls and floor are
## the map's, in its kind's sets (_build_room), each wall to its block's
## eaves; what stands over them is BuildingComposer's (decision 489): its
## "roof" (off while the local player is inside any of its cells, as a
## slot's is; none on a ruin) and its parts. A ruin's walls were broken
## here and there as the sets were (_build_room), as a damaged one's are.
func _add_kind(building: Dictionary) -> void:
	var rect: Rect2i = building["rect"]
	var cells := Level.building_cells(building)
	# Its pad (Relief.flat): any of its cells, not its rect's corner, which an
	# L's notch leaves outside it.
	var base := _elevation(cells[0])
	var eaves := float(building["eaves"])
	var named := str(building.get("roof_set", ""))
	var roof_set := named if not named.is_empty() and ArtKit.has("material.roof." + named) else KIND_ROOF
	var node := BuildingComposer.compose(building, roof_set)
	node.name = "Building_%d_%d" % [rect.position.x, rect.position.y]
	node.position = Vector3(rect.position.x, base, rect.position.y)
	_room.add_child(node)
	var roof: Node3D = node.get_node_or_null("roof")
	var inside: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		inside[cell] = true
	var index := _buildings.size()
	_buildings.append({"rect": rect, "node": node, "roof": roof, "off": false, "roof_at": roof.transform if roof != null else Transform3D(),
		"use": str(building.get("use", "")), "town_id": str(building.get("town_id", "")), "damaged": false,
		"open_air": false, "crop": "", "inside": inside, "outline": Level.building_outline(building),
		"kind": building, "stage": BuildingComposer.STANDING, "scaffold": false, "heights": {}, "windows": [],
		"plot": building.get("plot", false)})
	# Its walls as built (566): what a stage cuts down and puts back.
	for key: Vector3i in _buildings[index]["outline"]:
		_buildings[index]["heights"][key] = _height_of(key)
		if _wall_states.get(key) == "window":
			_buildings[index]["windows"].append(key)
	_show_state(_buildings[index])
	if _glimpse or roof == null:
		return  # A glimpse is drawn only; a ruin is open to the sky.
	for block: Rect2i in building["blocks"]:
		var keep_dry := GPUParticlesCollisionBox3D.new()
		keep_dry.size = Vector3(block.size.x, eaves, block.size.y)
		var middle := Vector2(block.position) + Vector2(block.size - Vector2i.ONE) * 0.5
		keep_dry.position = Vector3(middle.x, base + eaves * 0.5, middle.y)
		_room.add_child(keep_dry)
	for cell in cells:
		_building_at[cell] = index


## The terrain's roofs (Level.roofs_from, decision 364): each a gable
## drawn from its set (_roof_mesh) over its rect, at the walls' top, its
## ridge along x or z; kept with the buildings (_buildings), so it is off
## while the local player is under it, fades when it hides them, and
## draws as its town has it as theirs do.
func _add_roofs() -> void:
	for given: Dictionary in _terrain.get("roofs", []):
		var rect: Rect2i = given["rect"]
		var holder := Node3D.new()
		holder.name = "Roof_%d_%d" % [rect.position.x, rect.position.y]
		var middle := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
		holder.position = Vector3(middle.x, _elevation(rect.position), middle.y)
		var along_x := str(given.get("ridge", "z")) == "x"
		# Built along z; a ridge along x is the same turned a quarter.
		holder.rotation.y = PI * 0.5 if along_x else 0.0
		var span := Vector2(rect.size.y, rect.size.x) if along_x else Vector2(rect.size)
		var roof_set := str(given.get("set", Level.ROOF_SETS[0]))
		var roof := _roof_mesh(roof_set, span.x, span.y)
		roof.name = "roof"
		roof.position.y = WALL_HEIGHT
		holder.add_child(roof)
		_room.add_child(holder)
		# A corner no wall comes to stands on a post (a shelter's).
		for vertex: Vector2i in [rect.position, Vector2i(rect.end.x, rect.position.y), Vector2i(rect.position.x, rect.end.y), rect.end]:
			var walled := Level.outline(rect).any(func(key: Vector3i) -> bool:
				return _terrain["edges"].has(key) and _edge_vertices(key).has(vertex))
			if not walled and not _posts.has(vertex):
				_add_post(vertex)
		var index := _buildings.size()
		_buildings.append({"rect": rect, "node": holder, "roof": roof, "off": false, "roof_at": roof.transform,
			"use": str(given.get("use", "")), "town_id": str(given.get("town_id", "")), "damaged": false,
			"roof_index": _terrain.get("roofs", []).find(given), "set": roof_set, "span": span, "along_x": along_x, "holed": false})
		_show_state(_buildings[index])
		if _glimpse:
			continue
		_show_holes(_buildings[index])
		var keep_dry := GPUParticlesCollisionBox3D.new()
		keep_dry.size = Vector3(rect.size.x, WALL_HEIGHT, rect.size.y)
		keep_dry.position = holder.position + Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
		_room.add_child(keep_dry)
		for cell in Level.rect_cells(rect):
			_building_at[cell] = index


## The two vertices (cell corners, Vector2i(x, y) the top-left of cell (x,
## y)) at the ends of edge [param key].
static func _edge_vertices(key: Vector3i) -> Array[Vector2i]:
	if key.z == Terrain.EAST:
		return [Vector2i(key.x + 1, key.y), Vector2i(key.x + 1, key.y + 1)]
	return [Vector2i(key.x, key.y + 1), Vector2i(key.x + 1, key.y + 1)]


## A gable roof of set [param roof_set] over a room [param across] cells
## wide (x) and [param along] long (z, the ridge), its origin the room's
## middle at the walls' top: two slopes from roof.<set>.profile (rise a
## cell, thickness, overhang past the walls) with barge boards down the
## gables' edges, the gable ends' triangles in this map's wall set, a roof.<set>.ridge a cell along the ridge and a
## roof.<set>.end (a finial) at each end of it, grey stand-ins where the set has no
## art yet.
func _roof_mesh(roof_set: String, across: float, along: float, holes: Array[Vector2] = []) -> Node3D:
	var profile := ROOF_PROFILE.duplicate()
	var slot := "roof.%s.profile" % roof_set
	if ArtKit.has(slot):
		var spec := ArtKit.spec(slot)
		for key: String in profile:
			profile[key] = float(spec.get(key, profile[key]))
	var half := across * 0.5
	var apex := float(profile["rise"]) * half
	var pitch := apex / half
	var reach := float(profile["overhang"])
	var thick := float(profile["thickness"])
	var length := along + reach * 2.0
	var out := Node3D.new()
	# The slopes: from the eave, reach past the wall and as far below its
	# top, to the ridge; a top and an underside, u along the ridge and v
	# down the slope in metres (material.roof.<set>'s tile_m). Laid a cell
	# at a time (the overhangs strips of their own), so a hole (a broken
	# cell's middle in [param holes], the roof's own x and z) is a cell left
	# out.
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slope := Vector2(half + reach, apex + reach * pitch).length()
	var down := sqrt(1.0 + pitch * pitch)
	var cuts: Array[float] = [-half - reach]
	for k in int(across) + 1:
		cuts.append(-half + k)
	cuts.append(half + reach)
	if not cuts.has(0.0):
		cuts.append(0.0)
	cuts.sort()
	var rows: Array[float] = [-length * 0.5]
	for k in int(along) + 1:
		rows.append(-along * 0.5 + k)
	rows.append(length * 0.5)
	var height := func(x: float) -> float: return apex - absf(x) * pitch
	for j in rows.size() - 1:
		for i in cuts.size() - 1:
			var x0 := cuts[i]
			var x1 := cuts[i + 1]
			var z0 := rows[j]
			var z1 := rows[j + 1]
			var middle := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var cell := Vector2(floorf(middle.x + half) - half + 0.5, floorf(middle.y + along * 0.5) - along * 0.5 + 0.5)
			if holes.any(func(hole: Vector2) -> bool: return hole.is_equal_approx(cell)):
				continue
			for lift in [thick, 0.0]:
				var corners := [Vector3(x0, height.call(x0) + lift, z0), Vector3(x0, height.call(x0) + lift, z1),
					Vector3(x1, height.call(x1) + lift, z1), Vector3(x1, height.call(x1) + lift, z0)]
				for k in [0, 1, 2, 0, 2, 3]:
					var corner: Vector3 = corners[k]
					tool.set_uv(Vector2(corner.z + length * 0.5, absf(corner.x) * down) / 2.0)
					tool.add_vertex(corner)
	tool.generate_normals()
	# Each hole dressed: roof.<set>.broken lying on the slope, x down it, its
	# origin on the slope's underside (its rafters within the slope).
	if ArtKit.has("roof.%s.broken" % roof_set):
		for i in holes.size():
			var hole := holes[i]
			var piece := ArtKit.instance("roof.%s.broken" % roof_set)
			piece.name = "Broken_%d" % i
			var side := 1.0 if hole.x >= 0.0 else -1.0
			piece.position = Vector3(hole.x, height.call(hole.x), hole.y)
			piece.rotation = Vector3(0.0, 0.0 if side > 0.0 else PI, -atan(pitch))
			out.add_child(piece)
	var slopes := MeshInstance3D.new()
	slopes.name = "Slopes"
	slopes.mesh = tool.commit()
	slopes.material_override = _roof_material(roof_set)
	out.add_child(slopes)
	# The gable ends: the wall set's triangle under each end, on the wall line.
	var gables := SurfaceTool.new()
	gables.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [-along * 0.5, along * 0.5]:
		for point: Vector3 in [Vector3(-half, 0, z), Vector3(half, 0, z), Vector3(0, apex, z)]:
			gables.set_uv(Vector2(point.x, -point.y) / WALL_TILE)
			gables.add_vertex(point)
	gables.generate_normals()
	var ends := MeshInstance3D.new()
	ends.name = "Gables"
	ends.mesh = gables.commit()
	var wall := _wall_material(_walls_set).duplicate() as StandardMaterial3D
	wall.cull_mode = BaseMaterial3D.CULL_DISABLED
	ends.material_override = wall
	out.add_child(ends)
	# The barge boards: down each gable's edge, under the slopes' rim.
	for z in [-length * 0.5, length * 0.5]:
		for side in [-1.0, 1.0]:
			var board := MeshInstance3D.new()
			var shape := BoxMesh.new()
			shape.size = Vector3(slope, ROOF_BARGE.y, ROOF_BARGE.x)
			board.mesh = shape
			board.material_override = _roof_material(roof_set)
			board.position = Vector3(side * (half + reach) * 0.5, (apex - reach * pitch) * 0.5, z)
			board.rotation.z = -side * atan(pitch)
			out.add_child(board)
	# The ridge and its ends: art-kit's pieces, or a grey cap along it. A
	# cap's base is a saddle whose lowest edges are ROOF_CAP_DROP below the
	# apex of the slopes' top faces.
	var top := Vector3(0.0, apex + thick, 0.0)
	if ArtKit.has("roof.%s.ridge" % roof_set):
		for k in int(along):
			var cap := ArtKit.instance("roof.%s.ridge" % roof_set)
			cap.position = top + Vector3(0.0, -ROOF_CAP_DROP, k - (along - 1.0) * 0.5)
			out.add_child(cap)
	else:
		var cap := _box(Vector3(0.3, 0.15, length), _roof_material(roof_set))
		cap.position = top - Vector3(0.0, 0.08, 0.0)
		out.add_child(cap)
	if ArtKit.has("roof.%s.end" % roof_set):
		for side in [-1.0, 1.0]:
			var finial := ArtKit.instance("roof.%s.end" % roof_set)
			finial.position = top + Vector3(0.0, 0.0, side * length * 0.5)
			finial.rotation.y = 0.0 if side < 0.0 else PI
			out.add_child(finial)
	return out


## A roof set's slopes: material.roof.<set>'s texture if it has one, else
## a flat ROOF_SWATCH; both faces drawn (its underside is seen at the
## eaves). One a set.
static var _roof_materials: Dictionary[String, StandardMaterial3D] = {}


static func _roof_material(roof_set: String) -> StandardMaterial3D:
	if not _roof_materials.has(roof_set):
		var material := StandardMaterial3D.new()
		var own := ArtKit.texture("material.roof." + roof_set) if ArtKit.has("material.roof." + roof_set) else null
		material.albedo_texture = own
		material.albedo_color = Color.WHITE if own != null else swatch(ROOF_SWATCH.x, ROOF_SWATCH.y)
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_roof_materials[roof_set] = material
	return _roof_materials[roof_set]


## Sets [param level]'s damaged roofs to [param damaged] (their indices,
## the "roofs" message, decision 383), and draws each of this map's so.
## Kept across rebuilds: a roof's state is not the map's.
func set_roofs(level: String, damaged: Array) -> void:
	roof_states[level] = damaged.map(func(index: Variant) -> int: return int(index))
	for building in _buildings:
		if building.has("roof_index"):
			_show_holes(building)


## Roof [param building] drawn as its level has it: damaged, broken open
## over a third of its cells (Level.broken_cells, the cells the sim opens to
## the sky), each hole dressed with roof.<set>.broken; else whole. Its mesh
## is made again either way, its fade and being off kept.
func _show_holes(building: Dictionary) -> void:
	var damaged: bool = int(building["roof_index"]) in roof_states.get(str(_terrain.get("level", "")), [])
	if damaged == building["holed"]:
		return
	building["holed"] = damaged
	var holes: Array[Vector2] = []
	if damaged:
		var rect: Rect2i = building["rect"]
		var middle := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
		for cell in Level.broken_cells(rect):
			var off := Vector2(cell) - middle
			# Into the roof's own cells: turned a quarter, local x is -z.
			holes.append(Vector2(-off.y, off.x) if building["along_x"] else off)
	var was: Node3D = building["roof"]
	_set_near(was, false)
	_faded.erase(was)
	_hid_at.erase(was)
	_hiding.erase(was)
	var span: Vector2 = building["span"]
	var roof := _roof_mesh(str(building["set"]), span.x, span.y, holes)
	roof.name = "roof"
	roof.transform = was.transform
	var holder: Node3D = building["node"]
	holder.remove_child(was)
	was.queue_free()
	holder.add_child(roof)
	building["roof"] = roof
	_occluders_built = false
	if building["off"]:
		for node in _descendants(roof):
			if node is GeometryInstance3D:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## An open-air building's crop (decision 452 amended, economy's 449): its
## town record's "crop" ("sown", "growing", "ripe", "flattened"; "" or none
## bare) shows the slot's state_<crop>, the other crop states hidden; a
## name the slot has no node for shows none.
func _show_crop(building: Dictionary) -> void:
	var crop := ""
	if not str(building["use"]).is_empty():
		crop = str(town_states.get(building["town_id"], {}).get(building["use"], {}).get("crop", ""))
	if crop == building["crop"]:
		return
	building["crop"] = crop
	for part: Node3D in (building["node"] as Node3D).find_children("state_*", "Node3D", true, false):
		if part.name != "state_damaged":
			part.visible = not crop.is_empty() and part.name == "state_" + crop


## Sets the buildings of [param town] (its id) to [param buildings] ({kind:
## {state, level}}, the "town" message, decision 297), and draws each of
## its buildings so. Kept across rebuilds: a town's state is not the map's.
func set_town(town: String, buildings: Dictionary) -> void:
	town_states[town] = buildings
	for building in _buildings:
		if building["town_id"] == town:
			_show_state(building)
	for ring in _town_walls:
		if ring["town_id"] == town:
			_show_town_wall(ring)


## [param building] drawn as its town has it: damaged, the slot's
## roof_damaged in its roof's place and its state_damaged (rubble) shown;
## until a slot has a roof_damaged, its roof sags (ROOF_SAG); a kind at its
## stage (566); in decline (649: DECLINES) as _show_decline draws it; else
## as built, as is a building no town has a record of.
func _show_state(building: Dictionary) -> void:
	if building.get("dropped", false):
		return  # A dropped plot (649): no more of its town's looks.
	var state := Towns.STANDING
	if not str(building["use"]).is_empty():
		state = str(town_states.get(building["town_id"], {}).get(building["use"], {}).get("state", Towns.STANDING))
	if building.get("open_air", false):
		_show_crop(building)
	var damaged := state == Towns.DAMAGED or state == Towns.DISREPAIR
	var decline := state if state in DECLINES else ""
	if decline != building.get("decline", "") and not str(building.get("decline", "")).is_empty():
		# Out of its decline (built again): its looks put back, then drawn
		# afresh as its stage and damage have it.
		_undo_decline(building)
		building["stage"] = -1
		building["damaged"] = not damaged
	if building.has("kind"):
		var record: Dictionary = {}
		if not str(building["use"]).is_empty():
			record = town_states.get(building["town_id"], {}).get(building["use"], {})
		var at := BuildingComposer.plot_stage(record) if building.get("plot", false) else BuildingComposer.stage(record)
		_show_stage(building, at, BuildingComposer.scaffolded(record))
	if damaged != building["damaged"]:
		_show_damage(building, damaged)
	if decline != building.get("decline", ""):
		_show_decline(building, decline)


## [param building] damaged or not (_show_state): a disrepair's too (649).
func _show_damage(building: Dictionary, damaged: bool) -> void:
	building["damaged"] = damaged
	var node: Node3D = building["node"]
	var whole: Node3D = node.get_node_or_null("roof")
	var broken: Node3D = node.get_node_or_null("roof_damaged")
	var was: Node3D = building["roof"]
	if was != null:
		# The roof that goes keeps nothing of the fade or of being off.
		_set_near(was, false)
		_faded.erase(was)
		_hid_at.erase(was)
		_hiding.erase(was)
	if broken != null:
		if whole != null:
			whole.visible = not damaged
		broken.visible = damaged
		building["roof"] = broken if damaged else whole
	elif whole != null:
		whole.transform = building["roof_at"] * (_kind_sag(building) if building.has("kind") else ROOF_SAG) if damaged else building["roof_at"]
	var heaps := node.find_child("state_damaged", true, false) as Node3D
	if heaps != null:
		heaps.visible = damaged
	# Its walls broken here and there (terrain's "broken": a ragged stub,
	# never a way through; the sim keeps the wall).
	var changed: Array[Vector3i] = []
	for key in building.get("outline", Level.outline(building["rect"])) if not building.get("open_air", false) else []:
		if _terrain["edges"].get(key) == Terrain.Edge.WALL and _broken_pick(key):
			_set_wall_state(key, "broken" if damaged else "")
			changed.append(key)
	if not changed.is_empty():
		rebuild_walls(changed)
	# What hides the player is indexed again, with the roof now shown.
	_occluders_built = false
	if _camera != null and building["off"]:
		_update_fade(true)


## [param building] in decline (649; one look for every building, slot or
## kind, from its record's state, never a piece of its own): "disrepair"
## damaged (_show_damage: its roof broken or sagging, its walls broken here
## and there), its lamps out, weeds at its foot; "ruin" its walls ragged
## stubs, low banks of rubble (wall.<set>.rubble) and gaps (_ruin_wall: the
## sim's walls are down, walked over), no post, roof, door or parts, half its
## floor's boards gone to bare ground, its stones, planks and weeds lying in
## it (_weeds); "gone" none of it drawn, no wall, post or door, its plot bare
## ground (terrain grows it back).
func _show_decline(building: Dictionary, decline: String) -> void:
	building["decline"] = decline
	var node: Node3D = building["node"]
	var down := decline == Towns.RUIN or decline == DECLINE_GONE
	node.visible = decline != DECLINE_GONE
	if down:
		for name: String in ["roof", "roof_damaged"]:
			var cover := node.get_node_or_null(name) as Node3D
			if cover != null:
				cover.visible = false
		var was: Node3D = building["roof"]
		if was != null:
			_set_near(was, false)
			_faded.erase(was)
			_hid_at.erase(was)
			_hiding.erase(was)
		building["roof"] = null
		var parts := node.get_node_or_null("parts") as Node3D
		if parts != null:
			parts.visible = false
	var changed: Array[Vector3i] = []
	for key: Vector3i in building.get("outline", Level.outline(building["rect"])) if not building.get("open_air", false) else []:
		match _terrain["edges"].get(key, Terrain.Edge.OPEN):
			Terrain.Edge.WALL:
				if _window_code.has(key):
					_window_code[key][2] = false
				if down:
					_set_wall_state(key, _ruin_wall(key) if decline == Towns.RUIN else "plot")
					_ruin_edges[key] = true
					changed.append(key)
			Terrain.Edge.DOOR:
				if down:
					_set_wall_state(key, "plot")
					_ruin_edges[key] = true
					if _doorways.has(key):
						(_doorways[key] as Node3D).visible = false
					changed.append(key)
	if down:
		_floor_gone(building, decline)
	_weeds(building, decline != DECLINE_GONE)
	if not changed.is_empty():
		rebuild_walls(changed)
	_occluders_built = false


## [param building]'s decline (649) put back (_show_state then draws its
## stage and damage afresh): seen, roofed and its parts as built, its walls'
## and door's looks cleared, its lamps as a standing one's, no weeds.
func _undo_decline(building: Dictionary) -> void:
	building["decline"] = ""
	var node: Node3D = building["node"]
	node.visible = true
	var whole := node.get_node_or_null("roof") as Node3D
	if whole != null:
		whole.visible = true
		building["roof"] = whole
	var broken := node.get_node_or_null("roof_damaged") as Node3D
	if broken != null:
		broken.visible = false
	var parts := node.get_node_or_null("parts") as Node3D
	if parts != null:
		parts.visible = true
	var changed: Array[Vector3i] = []
	for key: Vector3i in building.get("outline", Level.outline(building["rect"])) if not building.get("open_air", false) else []:
		if _window_code.has(key):
			_window_code[key][2] = true
		_ruin_edges.erase(key)
		if _wall_states.get(key, "") in ["rubble", "plot", "broken"]:
			_set_wall_state(key, "window" if key in building.get("windows", []) else "")
			changed.append(key)
		if _doorways.has(key):
			(_doorways[key] as Node3D).visible = true
	_weeds(building, false)
	_floor_gone(building, "")
	if not changed.is_empty():
		rebuild_walls(changed)


## A kind's roof sagging, damaged or in disrepair (649): tilted KIND_SAG
## about its own middle at the eaves and let down KIND_SAG_DROP, so its
## walls stay under it (ROOF_SAG turns a roof about its building's corner
## on the ground, which drops a kind's far end through its walls).
func _kind_sag(building: Dictionary) -> Transform3D:
	var rect: Rect2i = building["rect"]
	var middle := Vector3((rect.size.x - 1) * 0.5, float(building["kind"]["eaves"]), (rect.size.y - 1) * 0.5)
	var turn := Transform3D(Basis(Vector3.RIGHT, KIND_SAG), Vector3.ZERO)
	return Transform3D(Basis.IDENTITY, middle + Vector3(0.0, -KIND_SAG_DROP, 0.0)) * turn * Transform3D(Basis.IDENTITY, -middle)


## A wall edge of a ruin (649), by its hash: "plot" (a gap), "broken" (a
## ragged stub) or "rubble" (a low bank), RUIN_GAP_EVERY and RUIN_STUBS.
static func _ruin_wall(key: Vector3i) -> String:
	var turn := posmod(_edge_hash(key), RUIN_GAP_EVERY)
	return "plot" if turn == 0 else "broken" if turn <= RUIN_STUBS else "rubble"


static func _edge_hash(key: Vector3i) -> int:
	return (key.x * 73856093) ^ (key.y * 19349663) ^ (key.z * 83492791)


static func _cell_hash(cell: Vector2i) -> int:
	return absi((cell.x * 73856093) ^ (cell.y * 19349663)) >> 3


## [param building]'s floor bared in [param decline] (649): gone, every
## cell of its plot; a ruin, all but one in RUIN_BOARDS_KEPT by its hash:
## its floor set (_floor_sets) out of the ground's floor mask; every cell's
## ground drawn as dirt (a kept board's too, or its stone shows at the
## edges of the bare cells), both kept by the building; "" puts them back.
func _floor_gone(building: Dictionary, decline: String) -> void:
	var was: Dictionary = building.get("floor_was", {})
	var grounds: Dictionary = building.get("ground_was", {})
	var cells: Array[Vector2i] = []
	if decline.is_empty():
		for cell: Vector2i in grounds:
			_set_ground_kind(cell, grounds[cell])
		for cell: Vector2i in was:
			_floor_sets[cell] = was[cell]
		cells.assign(was.keys())
		building.erase("floor_was")
		building.erase("ground_was")
	else:
		for cell in Level.rect_cells(building["rect"]):
			var kept := decline == Towns.RUIN and posmod(_cell_hash(cell), RUIN_BOARDS_KEPT) == 0
			if _floor_sets.has(cell) and not kept:
				was[cell] = _floor_sets[cell]
				_floor_sets.erase(cell)
				cells.append(cell)
			var kind: String = _ground_kinds.get(cell, "dirt")
			if kind != "dirt" and _grounds.has(cell):
				grounds[cell] = kind
				_set_ground_kind(cell, "dirt")
				if not cells.has(cell):
					cells.append(cell)
		building["floor_was"] = was
		building["ground_was"] = grounds
	if cells.is_empty() or _floor_mask == null:
		return
	for cell in cells:
		var at := cell - _mask_origin
		if at.x < 0 or at.y < 0 or at.x >= _mask_size.x or at.y >= _mask_size.y:
			continue
		_floor_bytes[at.y * _mask_size.x + at.x] = FLOOR_SETS.get(_floor_set(cell, str(_ground_kinds.get(cell, "stone"))), 0)
	_floor_mask.update(Image.create_from_data(_mask_size.x, _mask_size.y, false, Image.FORMAT_R8, _floor_bytes))


## Weeds (art-kit's scatter.tuft, a plant.fern now and then) at
## [param building]'s foot in decline (649): by one outline edge in
## WEED_EVERY (by its hash), out of its walls, or into a ruin's footprint,
## and in a ruin its litter; taken away when [param on] is false. Held in
## the room, by the building.
func _weeds(building: Dictionary, on: bool) -> void:
	var had: Variant = building.get("weeds")
	if had is Node3D and is_instance_valid(had):
		(had as Node3D).queue_free()
	building.erase("weeds")
	if not on or _room == null or not ArtKit.has("scatter.tuft"):
		return
	var rect: Rect2i = building["rect"]
	var holder := Node3D.new()
	holder.name = "Weeds_%d_%d" % [rect.position.x, rect.position.y]
	var ruin: bool = building.get("decline", "") == Towns.RUIN
	for key: Vector3i in building.get("outline", Level.outline(rect)):
		var hash := (key.x * 73856093) ^ (key.y * 19349663) ^ (key.z * 83492791)
		if posmod(hash, WEED_EVERY) != 0:
			continue
		var sides := Terrain.edge_cells(key)
		var within: Vector2i = sides[0] if rect.has_point(sides[0]) else sides[1]
		var beyond: Vector2i = sides[1] if within == sides[0] else sides[0]
		var middle := (Vector2(sides[0]) + Vector2(sides[1])) * 0.5
		var cell: Vector2i = within if ruin else beyond
		var at := middle + Vector2(cell - (beyond if ruin else within)) * WEED_OUT
		var slot := "plant.fern" if posmod(hash >> 4, 5) == 0 and ArtKit.has("plant.fern") else "scatter.tuft"
		var weed := ArtKit.instance(slot)
		weed.position = Vector3(at.x, _elevation(cell), at.y)
		weed.rotation.y = float(posmod(hash >> 8, 628)) * 0.01
		holder.add_child(weed)
	# A ruin's litter: by a cell's hash, one in RUIN_LITTER_EVERY lies a
	# rubble heap, fallen planks, a stone or a weed through the floor.
	var litter: Array[String] = ["building.rubble_heap", "prop.planks", "scatter.stone", "scatter.tuft"]
	for cell in Level.rect_cells(rect) if ruin else []:
		var roll := _cell_hash(cell)
		if posmod(roll, RUIN_LITTER_EVERY) != 0:
			continue
		var slot: String = litter[posmod(roll >> 2, litter.size())]
		if not ArtKit.has(slot):
			continue
		var piece := ArtKit.instance(slot)
		var jitter := Vector2(posmod(roll >> 5, 7) - 3, posmod(roll >> 8, 7) - 3) * 0.08
		piece.position = Vector3(cell.x + jitter.x, _elevation(cell), cell.y + jitter.y)
		piece.rotation.y = float(posmod(roll >> 11, 628)) * 0.01
		holder.add_child(piece)
	_room.add_child(holder)
	building["weeds"] = holder


## A kind [param building] drawn at stage [param at] (decision 566,
## BuildingComposer.stage), in scaffold when [param scaffold]: its site's
## pieces; its roofs and parts only from their stages (a roof not yet on
## is none to hide); its walls none on its plot ("plot": nor their posts),
## its corner posts alone on its frame ("frame"), then cut to
## BuildingComposer.wall_fraction of their height, its windows and door
## only once its walls are whole. Its walls are drawn again
## (rebuild_walls) only when a stage before standing is left or come to.
func _show_stage(building: Dictionary, at: int, scaffold: bool) -> void:
	var was: int = building["stage"]
	if at == was and scaffold == building["scaffold"]:
		return
	building["stage"] = at
	building["scaffold"] = scaffold
	var node: Node3D = building["node"]
	var old := node.get_node_or_null("Site")
	if old != null:
		node.remove_child(old)
		old.queue_free()
	if at != BuildingComposer.STANDING or scaffold:
		node.add_child(BuildingComposer.site(building["kind"], at, scaffold))
	var roof: Node3D = node.get_node_or_null("roof")
	if roof != null:
		roof.visible = at >= BuildingComposer.COVERING
		if building["roof"] != null or roof.visible:
			_set_near(roof, false)
			_faded.erase(roof)
			_hid_at.erase(roof)
			_hiding.erase(roof)
		building["roof"] = roof if roof.visible else null
	var parts: Node3D = node.get_node_or_null("parts")
	if parts != null:
		parts.visible = at == BuildingComposer.STANDING
	if at == was or at == BuildingComposer.STANDING and was == BuildingComposer.STANDING:
		return
	var fraction := BuildingComposer.wall_fraction(at)
	var heights: Dictionary = building["heights"]
	for key: Vector3i in building["outline"]:
		match _terrain["edges"].get(key, Terrain.Edge.OPEN):
			Terrain.Edge.WALL:
				# Its lamps lit only once it stands: nobody lives in it before.
				if _window_code.has(key):
					_window_code[key][2] = at == BuildingComposer.STANDING
				if at == BuildingComposer.PLOT:
					_set_wall_state(key, "plot")
				elif fraction <= 0.0:
					_set_wall_state(key, "frame")
				else:
					_set_wall_state(key, "window" if fraction >= 1.0 and key in building["windows"] else "")
				# A frame's posts stand to the walls' full height.
				var keep := fraction if fraction > 0.0 else 1.0
				var tall: float = heights.get(key, WALL_HEIGHT) * keep
				if is_equal_approx(tall, WALL_HEIGHT):
					_wall_heights.erase(key)
				else:
					_wall_heights[key] = tall
			Terrain.Edge.DOOR:
				# No post by a door on a plot either.
				_set_wall_state(key, "plot" if at == BuildingComposer.PLOT else "")
				if _doorways.has(key):
					(_doorways[key] as Node3D).visible = fraction >= 1.0
	rebuild_walls(building["outline"])


## Whether wall edge [param key] stands unbuilt (566): on a plot ("plot")
## or a frame ("frame"), no wall drawn.
func _unbuilt(key: Vector3i) -> bool:
	var state: String = _wall_states.get(key, "")
	return state == "plot" or state == "frame"


## [param town]'s buildings awake ({code: bool}: economy's "town" message,
## npc's flag; decision 566): their window lights as they say.
func set_awake(town: String, awake: Dictionary) -> void:
	_awake[town] = awake
	_update_lamps()


## The beasts drawn in this zone's folds (640, maps' side; economy's
## "folds" message, Main.fold_view): [{rect, facing, count}], each fold's
## rect and facing (its gate's way) and the sheep its holding has, drawn as
## min(count, FOLD_SHEEP_MOST) creature.sheep standing in it, scenery, not
## entities; drawn again whole on each call and after a rebuild.
func set_folds(folds: Array) -> void:
	_folds = folds
	_draw_folds()


func _draw_folds() -> void:
	if is_instance_valid(_fold_sheep):
		_fold_sheep.free()
	_fold_sheep = null
	if _room == null or _folds.is_empty() or not ArtKit.has(FOLD_SHEEP):
		return
	_fold_sheep = Node3D.new()
	_fold_sheep.name = "FoldSheep"
	_room.add_child(_fold_sheep)
	for fold: Dictionary in _folds:
		var spots := fold_spots(fold["rect"], fold["facing"], int(fold["count"]))
		for i in spots.size():
			var at: Vector2 = spots[i]
			var pose := Node3D.new()
			# Every fourth a ram (the slot's variant 2), each turned its own way.
			var art := ArtKit.instance(FOLD_SHEEP, 2 if i % 4 == 3 else 1)
			pose.add_child(art)
			pose.position = Vector3(at.x, _elevation(Vector2i(roundi(at.x), roundi(at.y))), at.y)
			pose.rotation.y = FOLD_YAWS[i % FOLD_YAWS.size()] + atan2(float(fold["facing"].x), float(fold["facing"].y))
			_fold_sheep.add_child(pose)
			var view := CreatureView.new(FOLD_SHEEP, art, pose)
			pose.add_child(view)
			var graze := view.resolve("graze")
			if graze != "" and view.rig != null and i % 2 == 0:
				view.rig.loop(graze)


## Where [param count] sheep stand in a fold of [param rect] whose gate
## looks [param facing] (min(count, FOLD_SHEEP_MOST) of FOLD_SPOTS, each
## turned from the fold's own frame to the map's), in cells: inside the
## fence, off the trough's strip along the back.
static func fold_spots(rect: Rect2i, facing: Vector2i, count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var front := Vector2(facing)
	var across := Vector2(-front.y, front.x)
	var middle := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
	var half := float(rect.size.y if facing.y != 0 else rect.size.x) * 0.5
	for i in mini(maxi(count, 0), FOLD_SHEEP_MOST):
		var spot: Vector2 = FOLD_SPOTS[i]
		# spot.x across from the middle, spot.y in from the gate's fence.
		out.append(middle + front * (half - spot.y) + across * spot.x)
	return out


## Each window light lit or out (lamp_lit), as its building's town says
## and the hour; one freed with its walls is let go.
func _update_lamps() -> void:
	var now := DayNight.now()
	var hour := DayNight.hour(now)
	var sun := DayNight.elevation(now)
	_glows = _glows.filter(func(each: Array) -> bool: return is_instance_valid(each[0]))
	for each in _glows:
		(each[0] as Node3D).visible = _window_lit(each[1], hour, sun)


## Whether a window of _window_code row [param row] is lit: its building
## standing, then as lamp_lit says.
func _window_lit(row: Array, hour: float, sun: float) -> bool:
	return bool(row[2]) and lamp_lit(_awake.get(row[0], {}), str(row[1]), hour, sun)


## Whether a window of building [param code] is lit (566): only with the
## sun down; then as [param awake] ({code: bool}) says, else until
## LAMP_OUT o'clock.
static func lamp_lit(awake: Dictionary, code: String, hour: float, sun: float) -> bool:
	if sun > 0.0:
		return false
	if awake.has(code):
		return bool(awake[code])
	return hour >= 12.0 and hour < LAMP_OUT


## Whether a damaged building's or town wall's edge [param key] is one
## drawn broken: a third of them, by a hash of where it is, the same on
## every peer.
static func _broken_pick(key: Vector3i) -> bool:
	var hash := (key.x * 374761393 + key.y * 668265263 + key.z * 2246822519) & 0x7fffffff
	hash = ((hash ^ (hash >> 13)) * 1274126177) & 0x7fffffff
	return (hash ^ (hash >> 16)) % 3 == 0


## A window piece [param made] on edge [param key] (489 amended): turned
## half round where its outside is the run's -x (_window_flipped), as tall
## as the wall there, its shutters open (two in three, by the edge: each
## leaf 90 to 108 degrees, a little apart) or shut.
func _dress_window(made: Node3D, key: Vector3i) -> void:
	if _window_flipped.get(key, false):
		made.rotation.y = PI
	# Its light (566): art-kit's "glow" pane, lit as its building is.
	var glow := made.find_child("glow", true, false) as Node3D
	if glow != null and _window_code.has(key):
		_glows.append([glow, _window_code[key]])
		glow.visible = _window_lit(_window_code[key], DayNight.hour(DayNight.now()),
				DayNight.elevation(DayNight.now()))
	made.scale.y = _height_of(key) / WALL_HEIGHT
	var cell := Vector2i(key.x, key.y)
	if _roll(cell, 50 + key.z) >= SHUTTERS_OPEN:
		return
	var a := made.find_child("shutter_a", true, false) as Node3D
	var b := made.find_child("shutter_b", true, false) as Node3D
	if a != null:
		a.rotation_degrees.y = lerpf(90.0, 108.0, _roll(cell, 52 + key.z))
	if b != null:
		b.rotation_degrees.y = -lerpf(90.0, 108.0, _roll(cell, 54 + key.z))


## Sets wall edge [param key]'s state in _wall_states ("" takes it out),
## kept as this view's own (_state_walls).
func _set_wall_state(key: Vector3i, state: String) -> void:
	if state.is_empty():
		_wall_states.erase(key)
		_state_walls.erase(key)
		return
	_wall_states[key] = state
	if not _state_walls.has(key):
		_state_walls.append(key)


## The terrain's town walls (Level.town_walls_from), each drawn as its
## town's walls level has it (_show_town_wall).
func _add_town_walls() -> void:
	for given: Dictionary in _terrain.get("town_walls", []):
		var ring := {"town_id": str(given.get("town_id", "")), "walls": given["walls"], "gates": given["gates"],
			"rect": given["rect"], "towers": {}, "shown": ""}
		_town_walls.append(ring)
		_show_town_wall(ring)


## [param ring] drawn as its town has its walls (decision 298): no record
## (level 0, or only planned) a bank of rubble along it that still blocks;
## level 1 a palisade (wall set wood), 2 stone, 3 stone with towers at its
## corners and beside its gates; damaged, a third of it broken.
func _show_town_wall(ring: Dictionary) -> void:
	var record: Dictionary = town_states.get(ring["town_id"], {}).get("walls", {})
	var state := str(record.get("state", Towns.PLANNED))
	var level := 0 if state == Towns.PLANNED else int(record.get("level", 0))
	var damaged := state == Towns.DAMAGED and level > 0
	var look := "%d%s" % [level, " damaged" if damaged else ""]
	if look == ring["shown"]:
		return
	ring["shown"] = look
	var wall_set := "stone" if level >= 2 else "wood" if level == 1 else ""
	for key: Vector3i in ring["walls"]:
		if wall_set.is_empty():
			_wall_sets.erase(key)
			_town_wall_sets.erase(key)
		else:
			_wall_sets[key] = _known_set(wall_set)
			if not _town_wall_sets.has(key):
				_town_wall_sets.append(key)
		_set_wall_state(key, "rubble" if level == 0 else "broken" if damaged and _broken_pick(key) else "")
	var towers: Dictionary = ring["towers"]
	if level >= 3 and towers.is_empty():
		var rect: Rect2i = ring["rect"]
		var at: Dictionary[Vector2i, bool] = {}
		for corner in [rect.position, Vector2i(rect.end.x, rect.position.y), Vector2i(rect.position.x, rect.end.y), rect.end]:
			at[corner] = true
		for gate: Vector3i in ring["gates"]:
			at[WallEdge.vertex_at(gate, 0)] = true
			at[WallEdge.vertex_at(gate, 1)] = true
		var slot := "wall.%s.tower" % _known_set(wall_set)
		for vertex: Vector2i in at:
			if not ArtKit.has(slot):
				break
			var tower := ArtKit.instance(slot)
			tower.name = "Tower_%d_%d" % [vertex.x, vertex.y]
			tower.position = Vector3(vertex.x - 0.5, _elevation(vertex), vertex.y - 0.5)
			_room.add_child(tower)
			towers[vertex] = tower
	for tower: Node3D in towers.values():
		tower.visible = level >= 3
	rebuild_walls(ring["walls"])


## Every art slot the room may be built from (WARM_CATEGORIES), made once
## and let go, before the room is: the first of a slot loaded into an
## already big room cost seconds (a 256x256 outdoor map's first tree 4 s,
## its room's freeing 2.5 s; made first, 9 ms and 0.2 s). Once a process.
static var _warmed := false


static func _warm_art() -> void:
	if _warmed:
		return
	_warmed = true
	for slot: String in ArtKit.slots():
		var spec: Dictionary = ArtKit.spec(slot)
		if str(spec.get("type", "mesh")) == "mesh" and str(spec.get("category", "")) in WARM_CATEGORIES:
			ArtKit.instance(slot).free()


## Shader warm-ups (decision 495): what another part of the view will draw
## later and whose first draw hitches (a material's pipelines compiled on
## first use: pc-character's goblin outline, 20.6 ms on a fresh profile).
## Each a static func's Callable (never a lambda: a lambda held here has
## crashed Godot at exit) taking nothing and returning a Node3D drawn as in
## play (skinned, its next pass or stencil twin, its shadows), or null.
## Registered from client code before a room is built; the server builds
## no rooms. After a room is built each not yet warmed in this process is
## drawn for WARM_FRAMES frames WARM_DEPTH under the ground at the view's
## middle, then freed: its draws issued, so every pipeline compiles, but
## behind the opaque ground, so nothing of it ever shows (nor its shadow,
## cast below the ground). Godot (Forward+ on d3d12, 4.4 and on) also
## compiles pipelines in the background with its ubershaders, and keeps a
## shader cache in user data: check those before adding a warm-up.
static var warm_ups: Array[Callable] = [Callable(GrownTrees, "warm"), Callable(Client3D, "warm_goblin"), Callable(Client3D, "warm_painted")]
static var _warmed_ups: Dictionary[String, bool] = {}
const WARM_FRAMES := 2
const WARM_DEPTH := 6.0
var _warming: Array[Node3D] = []
var _warm_frames := 0


## Draws each warm-up not yet warmed in this process (decision 495).
func _start_warm_ups() -> void:
	if _glimpse or _room == null:
		return
	for warm: Callable in warm_ups:
		var key := "%s.%s" % [warm.get_object(), warm.get_method()]
		if _warmed_ups.has(key) or not warm.is_valid():
			continue
		_warmed_ups[key] = true
		var node: Node3D = warm.call()
		if node == null:
			continue
		node.name = "WarmUp_%d" % _warming.size()
		_room.add_child(node)
		node.position = _camera_target + Vector3.DOWN * WARM_DEPTH
		_warming.append(node)
	_warm_frames = WARM_FRAMES if not _warming.is_empty() else 0


## Frees the warm-ups once they have been drawn WARM_FRAMES frames.
func _end_warm_ups() -> void:
	if _warm_frames <= 0:
		return
	_warm_frames -= 1
	if _warm_frames > 0:
		return
	for node in _warming:
		if is_instance_valid(node):
			node.queue_free()
	_warming.clear()


## An edge between the land and the void: the map's outline, as the forest
## stands now (a cell felled since the build is land, one grown back void).
func _is_outline(key: Vector3i) -> bool:
	var sides := Terrain.edge_cells(key)
	return _on_land(sides[0]) != _on_land(sides[1])


func _on_land(cell: Vector2i) -> bool:
	return _clearing.has(cell) or _land.has(cell) and not _grown_back.has(cell)


## Trees on the void around the land, and the forest floor under them.
func _add_forest() -> void:
	if _land.is_empty():
		return
	var distance := _forest_distance
	var low := Vector2i(1 << 20, 1 << 20)
	var high := -low
	# Past the first ring, stands of pines once they are drawn (PineStands),
	# and a tree of its own on each cell left between them.
	var stood: Dictionary[Vector2i, bool] = {}
	var stands := PineStands.drawn()
	if stands:
		_add_stands(distance, stood)
	for cell: Vector2i in distance:
		low = low.min(cell)
		high = high.max(cell)
		var away := distance[cell]
		if away == 0 or stood.has(cell):
			continue
		# The first ring's trees from the edge's curve (decision 575,
		# _add_edge_trees), not a tree a cell along the cells' edge.
		if away == 1 and not _edge_curves.is_empty():
			continue
		if stands and away >= PineStands.FROM:
			# A solo pine between stands, once tree.pine has art: the holes
			# read as more of the stand.
			_add_tree(cell, 1.0, "tree.pine" if _deadwood_drawn("tree.pine") else "")
			continue
		# Trees in clumps: thick where the clump field is high, thin
		# between; the first ring always, so the edge reads closed.
		var clump := _field(Vector2(cell), FOREST_CLUMP, 40)
		var roll := _roll(cell, 0)
		# Now and then an edge cell's tree was felled: its stump, toward the
		# land, where its crown would hide it; the trees beside it close the edge.
		var felled := away == 1 and _roll(cell, 50) >= SAPLING_CHANCE and _roll(cell, 57) < STUMP_EDGE_CHANCE 				and _deadwood_drawn("tree.stump")
		if felled:
			_add_deadwood(cell, "tree.stump", distance)
		elif away == 1 or away <= FOREST_DEPTH and roll < 0.35 + 0.6 * clump or roll < 0.08 + 0.45 * clump:
			_add_tree(cell, clump)
			# At the edge, now and then a sapling too, toward the land: the
			# edge's line, and its shadow, no longer a tree a cell.
			if away == 1 and _roll(cell, 50) < SAPLING_CHANCE:
				_add_sapling(cell, distance)
		elif roll < 0.33:
			var rock := ArtKit.instance("rock.small")
			rock.name = "Rock_%d_%d" % [cell.x, cell.y]
			rock.position = _tile_position(cell)
			rock.rotation.y = _roll(cell, 3) * TAU
			_room.add_child(rock)
		elif roll < 0.33 + DEADWOOD_CHANCE:
			_add_deadwood(cell, "tree.log" if _roll(cell, 58) < LOG_SHARE else "tree.stump", distance)
	_add_edge_trees(distance, stood)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(high - low) + Vector2.ONE * 2.0
	var forest_floor := MeshInstance3D.new()
	forest_floor.name = "ForestFloor"
	forest_floor.mesh = floor_mesh
	if PineStands.drawn():
		forest_floor.material_override = PineStands.floor_material(_forest_floor_colour())
	else:
		var material := StandardMaterial3D.new()
		material.albedo_color = _forest_floor_colour()
		material.roughness = 1.0
		forest_floor.material_override = season_material(material, false, false)
	forest_floor.position = Vector3((low.x + high.x) * 0.5, -FOREST_FLOOR_DEPTH, (low.y + high.y) * 0.5)
	_room.add_child(forest_floor)


## Scatter: grass tufts, flowers, small stones and roots on the ground,
## off the grid: per cell, by a hash of it, a number of each by the cell's
## ground (SCATTER_DENSITY; the forest's ring has its own), each at its own
## place in the cell, size, turn and lean, on the ground's height there.
## One MultiMesh a chunk and kind, made when the view comes near the chunk
## (_grow_scatter, a step a frame, more with a backlog) and freed when it
## is left SCATTER_KEEP past the reach; no shadows; nothing on water or
## fire. Visual only: the sim knows none of it.
func _grow_scatter() -> void:
	if _camera == null or _ground_cells.is_empty():
		return
	var aim := Vector2(_camera_target.x, _camera_target.z)
	var edge := _scatter_reach()
	var reach := edge + FLOOR_CHUNK
	if _scatter_sway != null:
		_scatter_sway.set_shader_parameter("reach_fade", Vector4(aim.x, aim.y, edge - SCATTER_FADE, edge) if _low else Vector4(0, 0, 1e9, 1e9))
	var key := Vector2i(floori(aim.x / FLOOR_CHUNK), floori(aim.y / FLOOR_CHUNK))
	if key != _scatter_aim or edge != _scatter_reach_at:
		if edge != _scatter_reach_at:
			_scatter_reach_at = edge
			for chunk: Vector2i in _scatter_nodes:
				for drawn: Node in _scatter_nodes[chunk]:
					_scatter_range(drawn)
		_scatter_aim = key
		_scatter_due.clear()
		for chunk: Vector2i in _scatter_chunks:
			var away := (Vector2(chunk * FLOOR_CHUNK) + Vector2.ONE * FLOOR_CHUNK * 0.5).distance_to(aim)
			if not _scattered.has(chunk) and away <= reach:
				_scatter_due.append(chunk)
			elif _scattered.has(chunk) and away > reach + SCATTER_KEEP:
				_unscatter(chunk)
		_scatter_due.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return Vector2(a * FLOOR_CHUNK).distance_squared_to(aim) < Vector2(b * FLOOR_CHUNK).distance_squared_to(aim))
	# A step a frame (a kind's MultiMesh of a chunk planned, or the next
	# chunk's plan); with a backlog, steps until the frame's budget is spent.
	var started := Time.get_ticks_usec()
	var backlog := _scatter_jobs.size() + _scatter_due.size() > SCATTER_BACKLOG
	while _scatter_step() and backlog and Time.get_ticks_usec() - started < SCATTER_BUDGET_USEC:
		pass


## One step of the scatter due; false with none left.
func _scatter_step() -> bool:
	if not _scatter_jobs.is_empty():
		var job: Array = _scatter_jobs.pop_front()
		_scatter_build(job[0], job[1], job[2])
	elif not _scatter_due.is_empty():
		var chunk: Vector2i = _scatter_due.pop_front()
		_scattered[chunk] = true
		var placed := _scatter_plan(chunk)
		for kind: String in placed:
			_scatter_jobs.append([chunk, kind, placed[kind]])
	else:
		return false
	return true


## How far from the aim the scatter is built: under the low camera its own
## reach (decision 653), else what the screen shows.
func _scatter_reach() -> float:
	if _camera == null:
		return INF
	return scatter_reach_low if _low else _view_reach()


## [param drawn]'s draw distance: the kinds that don't sway (their material
## has no fade of its own) fade out by the camera's distance over the
## reach's last SCATTER_FADE under the low camera; else drawn as far as seen.
func _scatter_range(drawn: Node) -> void:
	var instance := drawn as GeometryInstance3D
	if instance == null or instance.material_override is ShaderMaterial:
		return
	instance.visibility_range_end = _scatter_reach_at if _low else 0.0
	instance.visibility_range_end_margin = SCATTER_FADE if _low else 0.0
	instance.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


## [param chunk]'s scatter freed (made again when the view comes near).
func _unscatter(chunk: Vector2i) -> void:
	_scatter_jobs.assign(_scatter_jobs.filter(func(job: Array) -> bool: return job[0] != chunk))
	_scattered.erase(chunk)
	for drawn: Node in _scatter_nodes.get(chunk, []):
		drawn.queue_free()
	_scatter_nodes.erase(chunk)
	for cell: Vector2i in _tall_where.keys():
		if Vector2i(floori(cell.x / float(FLOOR_CHUNK)), floori(cell.y / float(FLOOR_CHUNK))) == chunk:
			_tall_where.erase(cell)
			_tall_flat.erase(cell)


## Every chunk's scatter now, near or not (tests, benches).
func _scatter_all() -> void:
	for chunk: Vector2i in _scatter_chunks:
		if not _scattered.has(chunk):
			_scatter_chunk(chunk)


## [param chunk]'s scatter: its cells' tufts, flowers, stones and roots.
func _scatter_chunk(chunk: Vector2i) -> void:
	_scattered[chunk] = true
	var placed := _scatter_plan(chunk)
	for kind: String in placed:
		_scatter_build(chunk, kind, placed[kind])


## One kind's scatter in [param chunk], from its plan: a MultiMesh.
func _scatter_build(chunk: Vector2i, kind: String, items: Array) -> void:
	if _room == null:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	# The swaying kinds' snow (scatter.gdshader): how much, their height, and
	# their straw's shade.
	var swaying := kind in SWAYING
	multimesh.use_custom_data = swaying
	multimesh.mesh = _scatter_mesh(kind)
	multimesh.instance_count = items.size()
	var fit := _scatter_fit(kind)
	var over_tall := 1.0 / maxf(multimesh.mesh.get_aabb().end.y, 0.01)
	for i in items.size():
		var cell: Vector2i = items[i][0]
		var at: Vector2 = items[i][1]
		var salt: int = items[i][2]
		var size := lerpf(fit[0].x, fit[0].y, _roll(cell, 103 + salt))
		if kind == "tall" and _tall_edge(cell):
			size *= TALL_EDGE_SCALE
		var tilt: float = fit[1]
		var lean := Vector3((_roll(cell, 104 + salt) - 0.5) * 2.0 * tilt, _roll(cell, 105 + salt) * TAU, (_roll(cell, 106 + salt) - 0.5) * 2.0 * tilt)
		var basis := Basis.from_euler(lean).scaled(Vector3.ONE * size)
		multimesh.set_instance_transform(i, Transform3D(basis, Vector3(at.x, _height_in(cell, at) - fit[2], at.y)))
		var tint := _scatter_tint(kind, cell, salt, items[i][3])
		multimesh.set_instance_color(i, tall_look(tint, World.is_trampled(cell)) if kind == "tall" else tint)
		if swaying:
			multimesh.set_instance_custom_data(i, scatter_custom(items[i][3], over_tall, kind != "reeds"))
		if kind == "tall":
			if not _tall_where.has(cell):
				_tall_where[cell] = []
			_tall_where[cell].append([multimesh, i])
			if World.is_trampled(cell):
				_tall_flat[cell] = true
	var drawn := MultiMeshInstance3D.new()
	drawn.name = "Scatter_%d_%d_%s" % [chunk.x, chunk.y, kind]
	drawn.multimesh = multimesh
	drawn.material_override = _scatter_material(kind)
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scatter_range(drawn)
	_room.add_child(drawn)
	if not _scatter_nodes.has(chunk):
		_scatter_nodes[chunk] = []
	_scatter_nodes[chunk].append(drawn)


## Where [param chunk]'s scatter goes, by kind: [cell, place, salt, under
## the forest] each (made from the cells alone, the same on every peer).
func _scatter_plan(chunk: Vector2i) -> Dictionary[String, Array]:
	var fire: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _terrain["fire"]:
		fire[cell] = true
	var placed: Dictionary[String, Array] = {}
	var roof: Dictionary = _terrain.get("canopy", {})
	for index: int in _scatter_chunks[chunk]:
		var cell: Vector2i = _ground_cells[index]
		if index >= _ground_floor_end and index < _ground_water_end or fire.has(cell) or _dry_water.has(cell) or _fords.has(cell) \
				or _rocks.has(cell):
			continue
		# Grass under a grown forest's roof (its cover past SCATTER_ROOF) is
		# its floor of needles, as the ground draws it: the forest's scatter.
		var forest := index >= _ground_water_end 				or _ground_kinds[cell] == "grass" and float(roof.get(cell, 0.0)) > SCATTER_ROOF and not _floor_sets.has(cell)
		var ground := "forest" if forest else _ground_kinds[cell]
		var density: Dictionary = SCATTER_TALL if _tall.has(cell) else SCATTER_DENSITY.get(ground, {})
		var scrub: bool = _clearing.get(cell, "") == "scrub"
		if scrub and not forest:
			density = SCATTER_SCRUB  # A felled cell grown up (591).
		# Roots where the land meets the forest; reeds by water.
		if not forest and _forest_distance.has(cell) and _forest_edge(cell):
			density = density.duplicate()
			density["root"] = density.get("root", 0.0) + SCATTER_EDGE_ROOTS
		if not forest and _by_water(cell):
			density = density.duplicate()
			density["reeds"] = SCATTER_REEDS
		# By the forest's edge's curve (decision 575) each point is the
		# forest's or the land's by its side of the curve, not by its cell:
		# the land's kinds and the forest's both offered, each point kept
		# on its own side, the roots on the land within EDGE_ROOTS of it.
		var sides: Array = [[density, forest, false]]
		if not _edge_curves.is_empty() and _edge_near_sample.has(cell) and not _tall.has(cell):
			var land: Dictionary = (SCATTER_SCRUB if scrub else SCATTER_DENSITY.get(_ground_kinds.get(cell, "grass") if _ground_kinds.get(cell, "") != "forest" else "grass", {})).duplicate()
			land["root"] = land.get("root", 0.0) + SCATTER_EDGE_ROOTS
			if _by_water(cell):
				land["reeds"] = SCATTER_REEDS
			sides = [[land, false, true], [SCATTER_DENSITY.get("forest", {}), true, true]]
		var salt := 0
		for side: Array in sides:
			var offered: Dictionary = side[0]
			var on_forest: bool = side[1]
			var by_curve: bool = side[2]
			if on_forest and by_curve:
				salt += 500
			for kind: String in offered:
				salt += 10
				if not _outdoor and not SCATTER_INDOORS.has(kind) and _ground_kinds.get(cell, "") != "grass":
					continue  # No live plants on a floor under stone.
				var count := floori(offered[kind] + _roll(cell, 100 + salt))
				for n in count:
					var at := Vector2(cell) + Vector2(_roll(cell, 101 + salt + n * 7), _roll(cell, 102 + salt + n * 7)) - Vector2(0.5, 0.5)
					if not _road_curves.is_empty() and _road_near(at).x > -0.1:
						continue  # On a road (563, terrain's side).
					if _ledge_split.has(cell) and _ledge_other_side(cell, at):
						continue  # Past a ledge's curve, the other ground's (585).
					if by_curve:
						var into := _edge_signed(at)
						if not is_nan(into) and ((into > 0.0) != on_forest or kind == "root" and not on_forest and into < -EDGE_ROOTS):
							continue
					if not placed.has(kind):
						placed[kind] = []
					placed[kind].append([cell, at, n + salt, on_forest])
	return placed


## How a kind of scatter is placed: [scale range, most lean (radians),
## sink], from art-kit's slot (scatter.<kind>'s "scatter"), else SCATTER_SIZES.
static var _scatter_fits: Dictionary[String, Array] = {}


static func _scatter_fit(kind: String) -> Array:
	if not _scatter_fits.has(kind):
		var slot := "scatter." + kind
		var fields: Dictionary = ArtKit.spec(slot).get("scatter", {}) if ArtKit.has(slot) else {}
		var scale: Array = fields.get("scale", [SCATTER_SIZES[kind].x, SCATTER_SIZES[kind].y])
		_scatter_fits[kind] = [Vector2(scale[0], scale[1]), deg_to_rad(float(fields.get("tilt_max", 8.0))), float(fields.get("sink", 0.01))]
	return _scatter_fits[kind]


## Whether a land [param cell] has water beside it (eight ways).
func _by_water(cell: Vector2i) -> bool:
	for direction: Vector2i in World.DIRECTIONS:
		var index: int = _grounds.get(cell + direction, -1)
		if index >= _ground_floor_end and index < _ground_water_end:
			return true
	return false


## Whether a land [param cell] is beside the forest (a void cell round it).
func _forest_edge(cell: Vector2i) -> bool:
	for direction: Vector2i in World.DIRECTIONS:
		if _forest_distance.get(cell + direction, 0) >= 1:
			return true
	return false


## Whether tall grass [param cell] is on its patch's edge (a side not tall
## grass).
func _tall_edge(cell: Vector2i) -> bool:
	for direction: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		if not _tall.has(cell + direction):
			return true
	return false


## A swaying item's custom data (scatter.gdshader): r how much snow lies on
## it, g one over its mesh's height ([param over_tall]), b its straw's light,
## a 1 if it sinks into the snow ([param buried]: not reeds, which stand in
## the water); less snow and darker straw under the forest's roof.
static func scatter_custom(forest: bool, over_tall: float, buried := true) -> Color:
	return Color(SCATTER_ROOF_SNOW if forest else 1.0, over_tall, SCATTER_ROOF_STRAW if forest else 1.0, 1.0 if buried else 0.0)


## An item's colour: its kind's, varied, darker under the forest; a flower
## one of FLOWER_SWATCHES.
func _scatter_tint(kind: String, cell: Vector2i, salt: int, forest: bool) -> Color:
	var shade := lerpf(0.82, 1.12, _roll(cell, 107 + salt))
	var flower: Vector2i = FLOWER_SWATCHES[floori(_roll(cell, 108 + salt) * FLOWER_SWATCHES.size()) % FLOWER_SWATCHES.size()]
	var colour: Color = swatch(flower.x, flower.y) \
			if kind == "flower" else Color.WHITE * shade
	if forest:
		colour = colour * Color(0.6, 0.72, 0.6)
	elif kind == "tuft" and _ground_kinds.get(cell, "grass") != "grass":
		colour = colour * Color(1.15, 1.05, 0.65)  # Dry, off the grass.
	if kind == "tall":
		colour = colour * Color(1.06, 1.02, 0.78)  # Riper than the lawn.
	return Color(colour, 1.0)


## A tall grass clump's colour, [param trampled] or standing: its alpha 0
## lays it flat (scatter.gdshader's pressed mat), 1 stands it.
static func tall_look(colour: Color, trampled: bool) -> Color:
	return Color(colour, 0.0 if trampled else 1.0)


## Each drawn clump of [param cells] laid flat or stood again, as World
## has it trampled now.
func _show_trampled(cells: Array) -> void:
	for cell: Vector2i in cells:
		var trampled := World.is_trampled(cell)
		if trampled:
			_tall_flat[cell] = true
		else:
			_tall_flat.erase(cell)
		for drawn: Array in _tall_where.get(cell, []):
			var multimesh: MultiMesh = drawn[0]
			multimesh.set_instance_color(drawn[1], tall_look(multimesh.get_instance_color(drawn[1]), trampled))


## The scatter's materials: vertex colours times each instance's, rough,
## both sides of a blade drawn; the soft kinds (SWAYING) bend in the wind
## (scatter.gdshader, decision 309), stones and roots don't.
const SWAYING: Array[String] = ["tuft", "flower", "reeds", "tall"]
static var _scatter_look: StandardMaterial3D
static var _scatter_sway: ShaderMaterial


static func _scatter_material(kind := "") -> Material:
	if kind in SWAYING:
		if _scatter_sway == null:
			_scatter_sway = ShaderMaterial.new()
			_scatter_sway.shader = SCATTER_SHADER
		return _scatter_sway
	if _scatter_look == null:
		_scatter_look = StandardMaterial3D.new()
		_scatter_look.vertex_color_use_as_albedo = true
		_scatter_look.vertex_color_is_srgb = true
		_scatter_look.roughness = 1.0
		_scatter_look.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _scatter_look


## A kind of scatter's mesh, made once: art-kit's slot (scatter.<kind>)
## when it has art, else a small low-poly stand-in made here.
static var _scatter_meshes: Dictionary[String, Mesh] = {}


static func _scatter_mesh(kind: String) -> Mesh:
	if _scatter_meshes.has(kind):
		return _scatter_meshes[kind]
	var slot := "scatter." + kind
	var mesh: Mesh = null
	if ArtKit.has(slot) and ArtKit.filled_by(slot) != "placeholder":
		var piece := ArtKit.instance(slot)
		for node in ArtKit._descendants(piece):
			if node is MeshInstance3D:
				mesh = _coloured(node as MeshInstance3D)
				break
		piece.free()
	if mesh == null:
		mesh = _make_scatter(kind)
	_scatter_meshes[kind] = mesh
	return mesh


## [param source]'s mesh with its colour in its vertices, as the scatter's
## materials draw (vertex colours times each instance's): a surface with no
## vertex colours of its own takes its material's albedo colour times its
## texture (the palette) at each vertex's UV. Art's scatter is coloured by
## the palette through UVs; drawn as it came it was white.
static func _coloured(source: MeshInstance3D) -> Mesh:
	var made := ArrayMesh.new()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var colours: Variant = arrays[Mesh.ARRAY_COLOR]
		if colours == null or (colours as PackedColorArray).is_empty():
			var material := source.get_active_material(surface) as BaseMaterial3D
			var base := material.albedo_color if material != null else Color.WHITE
			var image: Image = null
			if material != null and material.albedo_texture != null:
				image = material.albedo_texture.get_image()
				if image != null and image.is_compressed():
					image.decompress()
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
			var baked := PackedColorArray()
			for i in points.size():
				var colour := base
				if image != null and uvs != null and i < (uvs as PackedVector2Array).size():
					var uv: Vector2 = uvs[i]
					var size := image.get_size()
					colour *= image.get_pixel(clampi(int(fposmod(uv.x, 1.0) * size.x), 0, size.x - 1), clampi(int(fposmod(uv.y, 1.0) * size.y), 0, size.y - 1))
				baked.append(Color(colour, 1.0))
			arrays[Mesh.ARRAY_COLOR] = baked
		made.add_surface_from_arrays(source.mesh.surface_get_primitive_type(surface), arrays)
	return made


static func _make_scatter(kind: String) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"tuft", "flower":
			var blades := 6 if kind == "tuft" else 4
			for b in blades:
				var turn := b * TAU / blades + rng.randf_range(-0.4, 0.4)
				var out := Vector3(cos(turn), 0.0, sin(turn))
				var side := Vector3(-out.z, 0.0, out.x) * 0.04
				var root := out * rng.randf_range(0.0, 0.05)
				var tip := root + out * rng.randf_range(0.05, 0.12) + Vector3.UP * rng.randf_range(0.12, 0.22)
				var base := swatch(4, 4)
				var top := swatch(4, 1)
				_scatter_triangle(surface, [root - side, root + side, tip], [base, base, top])
			if kind == "flower":
				for p in 3:
					var at := Vector3(rng.randf_range(-0.07, 0.07), rng.randf_range(0.18, 0.26), rng.randf_range(-0.07, 0.07))
					var r := 0.05
					var white := Color.WHITE
					_scatter_triangle(surface, [at + Vector3(-r, 0, 0), at + Vector3(0, 0, -r), at + Vector3(r, 0, 0)], [white, white, white])
					_scatter_triangle(surface, [at + Vector3(-r, 0, 0), at + Vector3(r, 0, 0), at + Vector3(0, 0, r)], [white, white, white])
		"tall":
			# A clump of ten long thin blades, each in two segments, near
			# upright and bowing out a little toward the tip, pale toward it,
			# every other one under a seed head (decision 508, terrain's
			# side): a yellowing meadow against the lawn.
			var base := swatch(4, 4)
			var middle := swatch(4, 3)
			var seed := swatch(7, 7)
			var top := swatch(3, 1).lerp(seed, 0.6)
			for b in 10:
				var turn := b * TAU / 10.0 + rng.randf_range(-0.35, 0.35)
				var out := Vector3(cos(turn), 0.0, sin(turn))
				var side := Vector3(-out.z, 0.0, out.x) * 0.025
				var root := out * rng.randf_range(0.0, 0.06)
				var tall := rng.randf_range(0.8, 1.0)
				var knee := root + out * rng.randf_range(0.02, 0.05) + Vector3.UP * tall * 0.55
				var tip := root + out * rng.randf_range(0.08, 0.16) + Vector3.UP * tall
				_scatter_triangle(surface, [root - side, root + side, knee + side * 0.6], [base, base, middle])
				_scatter_triangle(surface, [root - side, knee + side * 0.6, knee - side * 0.6], [base, middle, middle])
				_scatter_triangle(surface, [knee - side * 0.6, knee + side * 0.6, tip], [middle, middle, top])
				if b % 2 == 0:
					var head := tip.lerp(knee, 0.18)
					var crest := tip + (tip - knee).normalized() * 0.06
					_scatter_triangle(surface, [head - side * 1.6, head + side * 1.6, crest], [seed, seed, seed])
					_scatter_triangle(surface, [head - side * 1.6, crest, head + side * 1.6], [seed, seed, seed])
		"reeds":
			# Tall thin blades, a few with a brown head.
			var stalk := swatch(4, 3)
			var tip := swatch(3, 1)
			var head := swatch(2, 5)
			for b in 7:
				var turn := b * TAU / 7.0 + rng.randf_range(-0.4, 0.4)
				var out := Vector3(cos(turn), 0.0, sin(turn))
				var side := Vector3(-out.z, 0.0, out.x) * 0.022
				var root := out * rng.randf_range(0.0, 0.07)
				var top := root + out * rng.randf_range(0.03, 0.1) + Vector3.UP * rng.randf_range(0.38, 0.6)
				_scatter_triangle(surface, [root - side, root + side, top], [stalk, stalk, tip])
				if b % 3 == 0:
					var at := root.lerp(top, 0.8)
					var h := Vector3(0.0, 0.07, 0.0)
					var w := side * 1.6
					_scatter_triangle(surface, [at - w, at + w, at + w + h], [head, head, head])
					_scatter_triangle(surface, [at - w, at + w + h, at - w + h], [head, head, head])
		"stone":
			# A squashed, jittered octahedron.
			var points: Array[Vector3] = []
			for direction: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP, Vector3.DOWN]:
				points.append(direction * Vector3(0.12, 0.07, 0.1) * rng.randf_range(0.75, 1.25) + Vector3(0, 0.03, 0))
			var grey := swatch(1, 2)
			for face: Array in [[0, 4, 2], [2, 4, 1], [1, 4, 3], [3, 4, 0], [0, 2, 5], [2, 1, 5], [1, 3, 5], [3, 0, 5]]:
				var shade := grey * rng.randf_range(0.85, 1.1)
				_scatter_triangle(surface, [points[face[0]], points[face[1]], points[face[2]]], [shade, shade, shade])
		"root":
			# A low arching strip, bent, thinning to its end.
			var brown := swatch(2, 3)
			var steps := 5
			for s in steps:
				var t0 := s / float(steps)
				var t1 := (s + 1) / float(steps)
				var arc := func(t: float) -> Vector3: return Vector3(t * 0.6 - 0.3, sin(t * PI) * 0.06, sin(t * 3.0) * 0.06)
				var w0 := 0.04 * (1.0 - t0 * 0.7)
				var w1 := 0.04 * (1.0 - t1 * 0.7)
				var a: Vector3 = arc.call(t0)
				var b: Vector3 = arc.call(t1)
				_scatter_triangle(surface, [a + Vector3(0, 0, -w0), a + Vector3(0, w0, 0), b + Vector3(0, w1, 0)], [brown, brown, brown])
				_scatter_triangle(surface, [a + Vector3(0, 0, -w0), b + Vector3(0, w1, 0), b + Vector3(0, 0, -w1)], [brown, brown, brown])
				_scatter_triangle(surface, [a + Vector3(0, w0, 0), a + Vector3(0, 0, w0), b + Vector3(0, 0, w1)], [brown, brown, brown])
				_scatter_triangle(surface, [a + Vector3(0, w0, 0), b + Vector3(0, 0, w1), b + Vector3(0, w1, 0)], [brown, brown, brown])
	surface.generate_normals()
	return surface.commit()


static func _scatter_triangle(surface: SurfaceTool, points: Array, colours: Array) -> void:
	for k in 3:
		surface.set_color(colours[k])
		surface.add_vertex(points[k])


## How far each void cell is from the land (cells, eight ways), out to
## FOREST_REACH: a walk outward from every land cell at once.
func _measure_forest() -> Dictionary[Vector2i, int]:
	# The walk starts from the land's outline only (a land cell with void
	# beside it): the land within is 0 by being land, and walking it cost
	# a 256x256 map 65,536 cells to reach a few thousand.
	var distance: Dictionary[Vector2i, int] = {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in _wooded:
		for direction: Vector2i in World.DIRECTIONS:
			if not _wooded.has(cell + direction):
				distance[cell] = 0
				frontier.append(cell)
				break
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		if distance[cell] >= FOREST_REACH:
			continue
		for direction: Vector2i in World.DIRECTIONS:
			var next := cell + direction
			if not distance.has(next) and not _wooded.has(next):
				distance[next] = distance[cell] + 1
				frontier.append(next)
	return distance


## The glimpses past this level's ways out (WorldMap.ways_out, maps'
## decision 325), each as _add_glimpse draws it: the target level's cells
## within GLIMPSE_DEPTH of the side it shows us, moved into our cells, none
## on our land; its heights lifted so the way's two ends stand level. An
## edge's target is placed as crossing it arrives; a link's land GLIMPSE_GAP
## cells past where our land ends along the way (ways_out places their map
## there; a map with void round its land, as the wilds is, is slid in to
## its land), and a lane of the marker's ground runs to it through the
## trees, the glimpse GLIMPSE_WIDE cells either side of it. A way with no
## way back (a drop), or into a level not outdoors (a dungeon's door),
## shows nothing.
func _plan_glimpses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var area := str(_terrain.get("level", ""))
	if area.is_empty() or not Level.names().has(area):
		return out
	var world := WorldMap.build()
	if not world.areas.has(area):
		return out
	var size: Vector2i = world.areas[area]["size"]
	for way: Dictionary in world.ways_out(area, GLIMPSE_GAP):
		if way["one_way"]:
			continue
		var target := _glimpse_level(str(way["to_map"]))
		# Only a place under the same sky shows past the trees: a door
		# down into a dungeon shows nothing.
		if target.is_empty() or not bool(target["terrain"].get("outdoor", false)):
			continue
		var plan := _glimpse_plan(way, target["terrain"], target["size"], size)
		if not (plan["cells"] as Dictionary).is_empty():
			out.append(plan)
	return out


## Level [param level_name] as last read for a glimpse, read again only
## when WorldMap's digest of it changed (a parse of the wilds is 55 ms).
static var _glimpse_levels: Dictionary[String, Array] = {}


static func _glimpse_level(level_name: String) -> Dictionary:
	var digest := str(WorldMap._read_before.get(level_name, {}).get("digest", ""))
	var kept: Array = _glimpse_levels.get(level_name, [])
	if kept.is_empty() or digest.is_empty() or kept[0] != digest:
		kept = [digest, Level.load_level(level_name)]
		_glimpse_levels[level_name] = kept
	return kept[1]


func _glimpse_plan(way: Dictionary, terrain: Dictionary, to_size: Vector2i, size: Vector2i) -> Dictionary:
	var away: Vector2i = way["out"]
	var shift := Vector2i((way["to_ours"] as Transform2D).origin.round())
	var lift := 0
	var margin := 0
	var lane: Array[Vector2i] = []
	var lane_kind := "grass"
	var lane_height := 0
	if way["kind"] == "link":
		var marker: Vector2i = way["from_cell"]
		var edge := marker
		var steps := 0
		while _land.has(edge + away) and steps < size.x + size.y:
			edge += away
			steps += 1
		edge += away
		# ways_out puts their map's edge GLIMPSE_GAP past where our land
		# ends; their land's edge goes there instead (the wilds' begins 16
		# rows into its map), their depth counted from it.
		var arrive: Vector2i = way["to_cell"]
		var their_land: Dictionary[Vector2i, bool] = {}
		for cell: Vector2i in terrain.get("floor", []) + terrain.get("water", []):
			their_land[cell] = true
		var back := 0
		while their_land.has(arrive - away * (back + 1)) and back < to_size.x + to_size.y:
			back += 1
		var to_their_edge: int = {Vector2i(0, -1): to_size.y - arrive.y, Vector2i(0, 1): arrive.y + 1,
				Vector2i(-1, 0): to_size.x - arrive.x, Vector2i(1, 0): arrive.x + 1}.get(away, 0)
		margin = to_their_edge - (back + 1)
		shift -= away * margin
		lift = _height(marker) - int(terrain.get("heights", {}).get(arrive, 0))
		lane_kind = str(_terrain.get("kinds", {}).get(marker, "grass"))
		lane_height = _height(marker)
		var across := Vector2i(absi(away.y), absi(away.x))
		for k in GLIMPSE_GAP:
			for w in range(-GLIMPSE_LANE, GLIMPSE_LANE + 1):
				var cell := edge + away * k + across * w
				if not _land.has(cell):
					lane.append(cell)
	# How deep a target cell is from the side it shows us (facing -away).
	var deep := func(cell: Vector2i) -> int:
		match away:
			Vector2i(0, -1): return to_size.y - 1 - cell.y
			Vector2i(0, 1): return cell.y
			Vector2i(-1, 0): return to_size.x - 1 - cell.x
			_: return cell.x
	var floor_cells: Array[Vector2i] = []
	var water: Array[Vector2i] = []
	var kinds := {}
	var heights := {}
	var stairs := {}
	var cells: Dictionary[Vector2i, bool] = {}
	var theirs: Dictionary = terrain.get("kinds", {})
	for list: String in ["floor", "water"]:
		for cell: Vector2i in terrain.get(list, []):
			var ours := cell + shift
			var aside := ours - (way["from_cell"] as Vector2i) if way["kind"] == "link" else Vector2i.ZERO
			if deep.call(cell) - margin >= GLIMPSE_DEPTH or absi(aside.x * away.y) + absi(aside.y * away.x) > GLIMPSE_WIDE 					or _near_land(ours, GLIMPSE_GAP):
				continue
			(floor_cells if list == "floor" else water).append(ours)
			cells[ours] = true
			if theirs.has(cell):
				kinds[ours] = theirs[cell]
			heights[ours] = clampi(int(terrain.get("heights", {}).get(cell, 0)) + lift, 0, Level.MAX_HEIGHT)
			if terrain.get("stairs", {}).has(cell):
				stairs[ours] = terrain["stairs"][cell]
	for cell in lane:
		if cells.has(cell):
			continue
		floor_cells.append(cell)
		cells[cell] = true
		kinds[cell] = lane_kind
		heights[cell] = lane_height
	var edges := {}
	for key: Vector3i in terrain.get("edges", {}):
		var ours := Vector3i(key.x + shift.x, key.y + shift.y, key.z)
		var sides := Terrain.edge_cells(ours)
		if cells.has(sides[0]) and cells.has(sides[1]):
			edges[ours] = terrain["edges"][key]
	# Its buildings wholly in the glimpse, as built (no town's state: it
	# is drawn only).
	var buildings: Array[Dictionary] = []
	for building: Dictionary in terrain.get("buildings", []):
		var rect := Rect2i((building["rect"] as Rect2i).position + shift, (building["rect"] as Rect2i).size)
		if Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return cells.has(cell)):
			var moved: Dictionary = building.duplicate()
			moved["rect"] = rect
			moved["cell"] = rect.position
			moved["blocks"] = (building.get("blocks", [building["rect"]]) as Array).map(func(block: Rect2i) -> Rect2i:
				return Rect2i(block.position + shift, block.size))
			moved.erase("use")
			moved.erase("town_id")
			buildings.append(moved)
	var roofs: Array[Dictionary] = []
	for roof: Dictionary in terrain.get("roofs", []):
		var rect := Rect2i((roof["rect"] as Rect2i).position + shift, (roof["rect"] as Rect2i).size)
		if Level.rect_cells(rect).all(func(cell: Vector2i) -> bool: return cells.has(cell)):
			roofs.append({"rect": rect, "set": roof["set"], "ridge": roof["ridge"]})
	return {"to": str(way["to_map"]), "cells": cells, "terrain": {
		"floor": floor_cells, "water": water, "kinds": kinds, "heights": heights, "stairs": stairs, "edges": edges,
		"fire": [], "torches": [], "lanterns": [], "buildings": buildings, "roofs": roofs, "outdoor": true, "zone": "outdoors",
		"walls": terrain.get("walls", DEFAULT_SET), "floors": terrain.get("floors", DEFAULT_SET), "border": "none"}}


## Whether any of our land is within [param reach] cells of [param cell]
## (eight ways): a glimpse keeps that far off, the trees between.
func _near_land(cell: Vector2i, reach: int) -> bool:
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if _land.has(cell + Vector2i(dx, dy)):
				return true
	return false


## A glimpse drawn: a view of its own under the room, built from the plan's
## terrain and nothing else (its ground, water, ledges, walls and doors,
## shut, and its buildings, roofed; no forest, which ours grows round it;
## no light of its own, lit by our sky; nothing in it picked, faded or
## thought about).
func _add_glimpse(plan: Dictionary) -> void:
	var view := Client3D.new()
	view.name = "Glimpse_" + str(plan["to"])
	view._glimpse = true
	_room.add_child(view)
	# (After it is in the tree: being ready turns _process on.)
	view.set_process(false)
	view._draw_glimpse(plan["terrain"])
	view._set_sky_floor(_sky_floor)
	_glimpses.append(view)


func _draw_glimpse(terrain: Dictionary) -> void:
	_terrain = terrain
	_outdoor = true
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_walls_set = _known_set(str(terrain.get("walls", DEFAULT_SET)))
	_floors_set = _known_set(str(terrain.get("floors", DEFAULT_SET)))
	_land = {}
	for cell: Vector2i in terrain["floor"] + terrain["water"]:
		_land[cell] = true
	_wooded = _land
	_shape_ramps()
	_build_ground(terrain["kinds"])
	_build_water()
	_add_cliffs()
	_add_walls()
	_add_buildings()
	_add_link_cues()
	_add_roofs()


## A tree slot on [param cell], sized by [param clump] (the biggest in a
## clump's heart) and by the cell, turned, leaning a little and set off its
## cell's middle, so every peer grows the same forest and no row shows.
## [param kind] a slot to use (a solo pine between stands), else broadleaf
## or small, now and then dead.
func _add_tree(cell: Vector2i, clump := 0.5, kind := "", at := Vector2.INF) -> void:
	var slot := kind if kind != "" else ("tree.broadleaf" if _roll(cell, 1) < 0.6 else "tree.small")
	if kind == "" and _roll(cell, 59) < DEAD_TREE_CHANCE and _deadwood_drawn("tree.dead"):
		slot = "tree.dead"
	var tree := ArtKit.instance(slot, 1 + int(_roll(cell, 60) * maxi(1, ArtKit.variant_count(slot))))
	tree.name = "Tree_%d_%d" % [cell.x, cell.y]
	var size := lerpf(0.7, 1.05, _roll(cell, 2)) * lerpf(0.9, 1.3, clump)
	tree.scale = Vector3.ONE * TREE_HEIGHT * size / ArtKit.size(slot).y
	tree.rotation = Vector3((_roll(cell, 6) - 0.5) * 2.0 * TREE_LEAN, _roll(cell, 3) * TAU, (_roll(cell, 7) - 0.5) * 2.0 * TREE_LEAN)
	tree.position = _tile_position(cell) + Vector3(_roll(cell, 4) - 0.5, 0.0, _roll(cell, 5) - 0.5) * TREE_NUDGE * 2.0
	if at != Vector2.INF:
		tree.position = Vector3(at.x, _ground_height(at), at.y)
	season_dress(tree, slot != "tree.dead" and slot != "tree.pine")
	_room.add_child(tree)
	_trees[cell] = tree


## The trees at the forest's edge from its curve (decision 575): along
## each, one every EDGE_SPACING, EDGE_DEPTH into the forest along its
## normal, the nearer thinned (kept EDGE_NEAR_KEEP of the time at the
## least depth, always at the most), a tree a cell at most and only on the
## forest's cells ([param distance] 1 or more, not a pine stand's in
## [param stood]): the edge ragged, its line the curve's, no row of cells.
func _add_edge_trees(distance: Dictionary[Vector2i, int], stood: Dictionary[Vector2i, bool]) -> void:
	for w in _edge_curves.size():
		var curve: Dictionary = _edge_curves[w]["curve"]
		var points: PackedVector2Array = curve["points"]
		var tangents: PackedVector2Array = curve["tangents"]
		var key := Vector2i(0, w * 7919)
		var next := lerpf(EDGE_SPACING.x, EDGE_SPACING.y, _roll(key, 61))
		var walked := 0.0
		for k in points.size():
			walked += Curves.SPACING
			if walked < next:
				continue
			walked = 0.0
			key = Vector2i(k, w * 7919)
			next = lerpf(EDGE_SPACING.x, EDGE_SPACING.y, _roll(key, 61))
			var depth := lerpf(EDGE_DEPTH.x, EDGE_DEPTH.y, _roll(key, 62))
			if _roll(key, 63) > lerpf(EDGE_NEAR_KEEP, 1.0, inverse_lerp(EDGE_DEPTH.x, EDGE_DEPTH.y, depth)):
				continue
			# Into the forest: left of the way round (the land on its right).
			var into := Vector2(tangents[k].y, -tangents[k].x)
			var at := points[k] + into * depth + Vector2(tangents[k]) * (_roll(key, 64) - 0.5) * 0.4
			var cell := Vector2i(roundi(at.x), roundi(at.y))
			# Its place taken (a stand's, a deeper tree's): just inside the
			# first ring instead, so the edge still reads closed.
			if stood.has(cell) or _trees.has(cell) or distance.get(cell, 0) < 1:
				at = points[k] + into * lerpf(EDGE_DEPTH.x, 0.55, _roll(key, 65)) + Vector2(tangents[k]) * (_roll(key, 64) - 0.5) * 0.4
				cell = Vector2i(roundi(at.x), roundi(at.y))
			if distance.get(cell, 0) < 1 or stood.has(cell) or _trees.has(cell) or _edge_signed(at) < EDGE_DEPTH.x * 0.5:
				continue
			# Now and then a tree felled at the edge, its stump left (as the
			# cells' first ring had them); else the tree, a sapling by it
			# toward the land now and then.
			if distance[cell] == 1 and _roll(cell, 50) >= SAPLING_CHANCE and _roll(cell, 57) < STUMP_EDGE_CHANCE \
					and _deadwood_drawn("tree.stump") and not _room.has_node("Deadwood_%d_%d" % [cell.x, cell.y]):
				_add_deadwood(cell, "tree.stump", distance)
				continue
			_add_tree(cell, _field(at, FOREST_CLUMP, 40), "", at)
			if distance[cell] == 1 and _roll(cell, 50) < SAPLING_CHANCE:
				_add_sapling(cell, distance)


## The forest floor under the trees past the first ring: the stands'
## needles once they are drawn.
static func _forest_floor_colour() -> Color:
	return PineStands.NEEDLES if PineStands.drawn() else FOREST_FLOOR


## The border's pine stands on [param distance]'s band (PineStands.plan),
## their cells put in [param stood]: those with a cell within
## PineStands.NEAR of the land a node each, faded as a tree is between the
## camera and the player; the rest one MultiMesh a chunk and variant, with
## no shadows.
func _add_stands(distance: Dictionary[Vector2i, int], stood: Dictionary[Vector2i, bool]) -> void:
	var far: Dictionary[Vector3i, Array] = {}
	for stand: Dictionary in PineStands.plan(distance, PineStands.variants()):
		var corner: Vector2i = stand["cell"]
		for at in PineStands.FOOTPRINT:
			stood[corner + at] = true
		var variant: int = stand["variant"]
		if int(stand["near"]) <= PineStands.NEAR:
			var piece := Node3D.new()
			piece.name = "Stand_%d_%d" % [corner.x, corner.y]
			piece.set_meta(&"slot", PineStands.SLOT)
			piece.transform = PineStands.transform_of(stand)
			var drawn := MeshInstance3D.new()
			drawn.mesh = PineStands.mesh(variant)
			piece.add_child(drawn)
			_room.add_child(piece)
			_trees[corner] = piece
			continue
		var key := Vector3i(floori(corner.x / float(PineStands.CHUNK)), floori(corner.y / float(PineStands.CHUNK)), variant)
		if not far.has(key):
			far[key] = []
		far[key].append(PineStands.transform_of(stand))
	for key: Vector3i in far:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = PineStands.mesh(key.z)
		multimesh.instance_count = far[key].size()
		for i in far[key].size():
			multimesh.set_instance_transform(i, far[key][i])
		var drawn := MultiMeshInstance3D.new()
		drawn.name = "Stands_%d_%d_%d" % [key.x, key.y, key.z]
		drawn.multimesh = multimesh
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_room.add_child(drawn)


## What lies on the ground: each GroundPile drawn as its things' art slots
## (ArtKit, item.<id>: a grey box till art comes), lying on their side,
## the top one last; one just thrown flies there from where it was thrown.
func _show_piles() -> void:
	if not World.pile_shown.is_connected(_on_pile_shown):
		World.pile_shown.connect(_on_pile_shown)
		World.pile_gone.connect(_on_pile_gone)
	_piles_quiet_until = Time.get_ticks_msec() + 500
	_pile_ids.clear()
	for pile: GroundPile in World.zone.piles.values():
		_on_pile_shown(pile)


func _on_pile_shown(pile: GroundPile) -> void:
	# Only the zone shown (a host's other zones' nodes sit under hidden holders).
	if _room == null or not is_instance_valid(pile) or not pile.is_inside_tree() or not (pile.get_parent() as Node2D).visible:
		return
	_pile_sounds(pile, pile.ids)
	_drop_heap(pile)
	var heap := Node3D.new()
	heap.name = GroundPile.name_for(pile.tile)
	heap.position = _tile_position(pile.tile)
	# A pale ring on the ground under it, so a small thing reads from afar.
	var ring := MeshInstance3D.new()
	ring.mesh = _pile_ring()
	ring.position.y = 0.01
	heap.add_child(ring)
	var growing := growing_slot(pile.ids)
	# One model per kind (619, ui's side): five herbs lie as one, the hint
	# counts them; the ring keeps a small heap readable from afar.
	var kinds := PackedStringArray()
	for id in pile.ids:
		if not kinds.has(id):
			kinds.append(id)
	for i in kinds.size():
		var slot := growing if not growing.is_empty() else str(Items.def(kinds[i]).get("art", ""))
		if not ArtKit.has(slot):
			continue
		var thing := ArtKit.instance(slot)
		if not growing.is_empty():
			# Standing, small, turned by the cell, the others round it.
			var size := ArtKit.size(slot)
			thing.scale = Vector3.ONE * minf(GROWING_WIDE / maxf(maxf(size.x, size.z), 0.01), 1.0)
			thing.rotation = Vector3(0.0, _roll(pile.tile, 10 + i) * TAU, 0.0)
			thing.position = Vector3(cos(i * 2.4) * 0.25 * mini(i, 1), 0.0, sin(i * 2.4) * 0.25 * mini(i, 1))
		else:
			# On its side, its length along the ground, turned by the cell and
			# its place in the heap, a little apart from the others.
			thing.rotation = Vector3(0.0, _roll(pile.tile, 10 + i) * TAU, PI * 0.5)
			thing.position = Vector3(cos(i * 2.4) * 0.18 * mini(i, 1), ArtKit.size(slot).z * 0.5,
					sin(i * 2.4) * 0.18 * mini(i, 1))
		heap.add_child(thing)
		if i == kinds.size() - 1 and pile.thrown_from != World.NO_CELL and World.tick - pile.thrown_tick < THROWN_SHOWN_TICKS:
			_fly(thing, _tile_position(pile.thrown_from) - heap.position + Vector3.UP * 1.2, thing.position)
	if pile.gold > 0 and ArtKit.has(Items.GOLD_ART):
		# Its gold (601 amended: a count, never a thing): one coin purse on its
		# side, under the rest.
		var coins := ArtKit.instance(Items.GOLD_ART)
		coins.rotation = Vector3(0.0, _roll(pile.tile, 9) * TAU, PI * 0.5)
		coins.position = Vector3(-0.15 * mini(pile.ids.size(), 1), ArtKit.size(Items.GOLD_ART).z * 0.5, 0.12 * mini(pile.ids.size(), 1))
		heap.add_child(coins)
	_room.add_child(heap)
	_pile_nodes[pile] = heap


## The plant a pile of [param ids] stands as: the first of Forage.PLANTS the
## kit has when every one is Forage.HERBS, else "" (drawn as things).
static func growing_slot(ids: PackedStringArray) -> String:
	if ids.is_empty():
		return ""
	for id in ids:
		if id != Forage.HERBS:
			return ""
	for slot in Forage.PLANTS:
		if ArtKit.has(slot):
			return slot
	return ""


## A pile gone (World.pile_gone): its last things picked up.
func _on_pile_gone(pile: GroundPile) -> void:
	_pile_sounds(pile, PackedStringArray())
	_drop_heap(pile)


func _drop_heap(pile: GroundPile) -> void:
	var heap: Node3D = _pile_nodes.get(pile)
	if heap != null:
		_pile_nodes.erase(pile)
		if is_instance_valid(heap):
			heap.queue_free()


## A pile's things now [param ids], against what it held: one more is a
## thing put down (or thrown, landing as its flight ends, and the throw
## heard where it left), one fewer a thing picked up.
func _pile_sounds(pile: GroundPile, ids: PackedStringArray) -> void:
	var was: PackedStringArray = _pile_ids.get(pile, PackedStringArray())
	if ids.is_empty():
		_pile_ids.erase(pile)
	else:
		_pile_ids[pile] = ids.duplicate()
	if Time.get_ticks_msec() < _piles_quiet_until or _room == null:
		return
	if not is_inside_tree() or not is_instance_valid(sfx) or not sfx.is_inside_tree():
		return  # The scene coming down: its piles leave too, unheard (a fallen goblin's purse at a test's end, decision 601).
	if World.zone != null and pile.zone != "" and pile.zone != World.zone.name:
		return  # Another zone's (a host's), or the one just left.
	var at := _tile_position(pile.tile) + Vector3.UP * 0.2
	if ids.size() > was.size():
		var top := ids[ids.size() - 1]
		if pile.thrown_from != World.NO_CELL and World.tick - pile.thrown_tick < THROWN_SHOWN_TICKS:
			sfx.play("sfx.throw", _tile_position(pile.thrown_from) + Vector3.UP * 1.2)
			_play_later("sfx.splash" if World.is_water(pile.tile) else SoundKit.handled(top, "land"), at, THROW_FLIGHT_SECONDS)
		else:
			sfx.play(SoundKit.handled(top, "drop"), at)
	elif ids.size() < was.size():
		var gone := was[was.size() - 1]
		for id: String in was:
			if id not in ids:
				gone = id
		sfx.play(SoundKit.handled(gone, "pickup"), at)
		if Items.weight_of(gone) >= World.THUD_HEAVY_KG:
			# A heavy thing lifted: a grunt from the person beside it.
			for entity in World.get_entities():
				if (entity is Player or entity is Companion) and _cells_apart(entity.tile, pile.tile) <= 1:
					sfx.play(SoundKit.voice(entity, "effort_lift"), _tile_position(entity.tile) + Vector3.UP * 1.5)
					break


## The ring under a pile: one mesh and material for all of them.
func _pile_ring() -> Mesh:
	if _pile_ring_mesh == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.26
		torus.outer_radius = 0.32
		torus.rings = 24
		torus.ring_segments = 4
		var material := StandardMaterial3D.new()
		material.albedo_color = PILE_RING
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		torus.material = material
		_pile_ring_mesh = torus
	return _pile_ring_mesh


## [param thing] flies from [param from] to [param to] (its heap's space) in
## an arc, over THROW_FLIGHT_SECONDS.
func _fly(thing: Node3D, from: Vector3, to: Vector3) -> void:
	thing.position = from
	var tween := thing.create_tween()
	tween.tween_method(func(t: float) -> void:
		if is_instance_valid(thing):
			thing.position = from.lerp(to, t) + Vector3.UP * sin(t * PI) * (0.6 + from.distance_to(to) * 0.15),
		0.0, 1.0, THROW_FLIGHT_SECONDS)


## A young tree on edge [param cell] (a void cell beside the land), small,
## set off toward the land and sideways, still in its own cell.
func _add_sapling(cell: Vector2i, distance: Dictionary[Vector2i, int]) -> void:
	var toward := Vector2.ZERO
	for direction: Vector2i in World.DIRECTIONS:
		if distance.get(cell + direction, -1) == 0:
			toward += Vector2(direction)
	if toward == Vector2.ZERO:
		return
	toward = toward.normalized()
	var side := Vector2(-toward.y, toward.x) * (_roll(cell, 51) - 0.5) * 0.5
	var at := toward * lerpf(0.25, 0.42, _roll(cell, 52)) + side
	at = at.clamp(-Vector2.ONE * 0.45, Vector2.ONE * 0.45)
	var slot := "tree.small"
	var sapling := ArtKit.instance(slot)
	sapling.name = "Sapling_%d_%d" % [cell.x, cell.y]
	sapling.scale = Vector3.ONE * TREE_HEIGHT * lerpf(SAPLING_SIZE.x, SAPLING_SIZE.y, _roll(cell, 53)) / ArtKit.size(slot).y
	sapling.rotation = Vector3((_roll(cell, 54) - 0.5) * 2.0 * TREE_LEAN, _roll(cell, 55) * TAU, (_roll(cell, 56) - 0.5) * 2.0 * TREE_LEAN)
	sapling.position = _tile_position(cell) + Vector3(at.x, 0.0, at.y)
	season_dress(sapling, true)
	_room.add_child(sapling)
	_saplings[cell] = sapling


## A stump or a log ([param slot]) in forest [param cell]: on the edge,
## set off toward the land as a sapling is; deeper in, anywhere in its
## cell; turned and its variant by the cell. Nothing while the slot has no
## art (_deadwood_drawn). Small: never faded.
func _add_deadwood(cell: Vector2i, slot: String, distance: Dictionary[Vector2i, int]) -> void:
	if not _deadwood_drawn(slot):
		return
	var toward := Vector2.ZERO
	for direction: Vector2i in World.DIRECTIONS:
		if distance.get(cell + direction, -1) == 0:
			toward += Vector2(direction)
	var at := Vector2(_roll(cell, 61) - 0.5, _roll(cell, 62) - 0.5) * 0.5
	if toward != Vector2.ZERO:
		at = toward.normalized() * lerpf(0.2, 0.38, _roll(cell, 61))
	var wood := ArtKit.instance(slot, 1 + int(_roll(cell, 63) * maxi(1, ArtKit.variant_count(slot))))
	wood.name = "Deadwood_%d_%d" % [cell.x, cell.y]
	wood.scale = Vector3.ONE * lerpf(0.8, 1.2, _roll(cell, 64))
	wood.rotation.y = _roll(cell, 65) * TAU
	wood.position = _tile_position(cell) + Vector3(at.x, 0.0, at.y)
	season_dress(wood, false)
	_room.add_child(wood)


## Felled [param cell]'s props for its stage (591, terrain's side;
## _clearing): a stump; a bush now and then in scrub; two or three
## saplings. Each turned, sized and placed by the cell; the old ones gone.
func _dress_clearing(cell: Vector2i) -> void:
	for prop: Node3D in _clearing_props.get(cell, []):
		_forget_piece(prop)
	_clearing_props.erase(cell)
	var props: Array[Node3D] = []
	match _clearing.get(cell, ""):
		"stump":
			if _deadwood_drawn("tree.stump"):
				props.append(_clearing_prop(cell, "tree.stump", 0, lerpf(0.8, 1.2, _roll(cell, 71))))
		"scrub":
			if _roll(cell, 72) < SCRUB_BUSH and _deadwood_drawn("plant.bush"):
				props.append(_clearing_prop(cell, "plant.bush", 0, lerpf(0.7, 1.1, _roll(cell, 73))))
		"saplings":
			for n in 2 + int(_roll(cell, 74) < 0.5):
				var sapling := _clearing_prop(cell, "tree.small", n,
						TREE_HEIGHT * lerpf(CLEARING_SAPLING.x, CLEARING_SAPLING.y, _roll(cell, 75 + n)) / ArtKit.size("tree.small").y)
				sapling.rotation.x = (_roll(cell, 78 + n) - 0.5) * 2.0 * TREE_LEAN
				sapling.set_meta(&"fades", true)
				props.append(sapling)
	if not props.is_empty():
		_clearing_props[cell] = props
	_occluders_built = false


## A [param slot] in felled [param cell] (the [param n]th), [param size]
## times its own: its variant, turn and place in the cell by the cell.
func _clearing_prop(cell: Vector2i, slot: String, n: int, size: float) -> Node3D:
	var prop := ArtKit.instance(slot, 1 + int(_roll(cell, 80 + n) * maxi(1, ArtKit.variant_count(slot))))
	prop.name = "Clearing_%d_%d_%d" % [cell.x, cell.y, n]
	prop.scale = Vector3.ONE * size
	prop.rotation.y = _roll(cell, 83 + n) * TAU
	# Apart in the cell: the nth a third of a turn round its middle.
	var turn := (_roll(cell, 86) + n / 3.0) * TAU
	var at := Vector2(cell) + Vector2.from_angle(turn) * (0.15 + 0.2 * _roll(cell, 87 + n) if n > 0 or slot == "tree.small" else 0.2 * _roll(cell, 87))
	prop.position = Vector3(at.x, _ground_height(at), at.y)
	season_dress(prop, slot != "tree.stump")
	_room.add_child(prop)
	return prop


## A piece taken off the room: out of the fade's lists, then freed.
func _forget_piece(piece: Node3D) -> void:
	_faded.erase(piece)
	_hiding.erase(piece)
	_hid_at.erase(piece)
	piece.queue_free()
	_occluders_built = false


## The felled cells of a "clearing" message drawn (591, terrain's side;
## Main calls it with [param terrain] already laid, [param cells] as
## [[x, y, stage]], "trunk" grown back). A stage that changes on the land
## swaps the cell's props, its ground's kind and its chunk's scatter, and
## is done. A fell takes the cell's tree away at once and leaves its
## stage's props; a regrowth takes the props and puts a tree back; the
## outline they move (the forest's ring, the edge's curve, the ground) is
## drawn at the next zone load, never mid-visit (the coordinator: a whole
## rebuild freezes the view 1 to 3.5 s wherever the player stands).
func clearing_changed(terrain: Dictionary, cells: Array) -> void:
	_terrain = terrain
	if _room == null:
		return
	var chunks: Dictionary[Vector2i, bool] = {}
	for each: Array in cells:
		var cell := Vector2i(int(each[0]), int(each[1]))
		var stage := str(each[2])
		var was: String = _clearing.get(cell, Clearing.TRUNK)
		if stage == was:
			continue
		chunks[Vector2i(floori(cell.x / float(FLOOR_CHUNK)), floori(cell.y / float(FLOOR_CHUNK)))] = true
		if stage == Clearing.TRUNK:
			_clearing.erase(cell)
			_grown_back[cell] = true
			_dress_clearing(cell)
			if not _trees.has(cell):
				_add_tree(cell, _field(Vector2(cell), FOREST_CLUMP, 40))
			continue
		_clearing[cell] = stage
		_grown_back.erase(cell)
		if was == Clearing.TRUNK:
			# Felled: its tree (or a sapling or dead wood on its cell) goes.
			if _trees.has(cell) and str(_trees[cell].name).begins_with("Tree_"):
				_forget_piece(_trees[cell])
				_trees.erase(cell)
			if _saplings.has(cell):
				_forget_piece(_saplings[cell])
				_saplings.erase(cell)
			var wood := _room.get_node_or_null("Deadwood_%d_%d" % [cell.x, cell.y]) as Node3D
			if wood != null:
				_forget_piece(wood)
		_dress_clearing(cell)
		_set_ground_kind(cell, Clearing.STAGE_KINDS.get(stage, "grass"))
	for chunk: Vector2i in chunks:
		_rescatter(chunk)
	_sync_plots()


## Land [param cell]'s ground drawn as [param kind] (a texel of the kinds
## texture); a cell of the forest's ring keeps its look till the outline
## is redrawn.
func _set_ground_kind(cell: Vector2i, kind: String) -> void:
	var index: int = _grounds.get(cell, -1)
	if index < 0 or index >= _ground_floor_end or _kinds_image == null or _ground_kinds.get(cell, "") == kind:
		return
	_ground_kinds[cell] = kind
	var at := cell - _mask_origin
	if at.x < 0 or at.y < 0 or at.x >= _kinds_image.get_width() or at.y >= _kinds_image.get_height():
		return
	var texel := Color(0, 0, 0, 0)
	texel[GROUND_CHANNELS[kind]] = 1.0
	_kinds_image.set_pixel(at.x, at.y, texel)
	_kinds_texture.update(_kinds_image)


## [param chunk]'s scatter drawn again from its plan, if it was drawn (else
## when the view comes to it, as ever).
func _rescatter(chunk: Vector2i) -> void:
	var drawn := _scattered.has(chunk)
	_unscatter(chunk)
	if drawn:
		_scatter_chunk(chunk)


## Whether [param slot] (dead wood: tree.stump, tree.log, tree.dead) is
## drawn: once it has art of its own or a fill, never as a grey box.
static func _deadwood_drawn(slot: String) -> bool:
	return ArtKit.has(slot) and ArtKit.filled_by(slot) != "placeholder"


## Smooth noise 0..1 over the cells, features about [param size] cells
## across: a hash at a coarse lattice, eased between; the same everywhere.
static func _field(at: Vector2, size: float, salt: int) -> float:
	var p := at / size
	var corner := Vector2i(floori(p.x), floori(p.y))
	var f := p - Vector2(corner)
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var top := lerpf(_roll(corner, salt), _roll(corner + Vector2i(1, 0), salt), f.x)
	var bottom := lerpf(_roll(corner + Vector2i(0, 1), salt), _roll(corner + Vector2i(1, 1), salt), f.x)
	return lerpf(top, bottom, f.y)


## 0..1, the same for [param cell] and [param salt] on every peer.
static func _roll(cell: Vector2i, salt: int) -> float:
	return float(absi(hash(Vector3i(cell.x, cell.y, salt))) % 10007) / 10007.0


func _see_through_of(material: Material) -> Material:
	if material.has_meta(SEASON_NEAR_META):
		return material.get_meta(SEASON_NEAR_META)
	if not _see_through.has(material):
		var copy := material.duplicate() as BaseMaterial3D
		if copy == null:
			return material
		copy.albedo_color = Color(copy.albedo_color, NEAR_ALPHA)
		_make_near(copy)
		_see_through[material] = copy
	return _see_through[material]


## An edge on the ground: its midpoint, and its yaw (a south edge runs
## along x, an east edge along z; the pieces are built along z).
static func _edge_midpoint(key: Vector3i) -> Vector3:
	if key.z == Terrain.EAST:
		return Vector3(key.x + 0.5, 0.0, key.y)
	return Vector3(key.x, 0.0, key.y + 0.5)


static func _edge_yaw(key: Vector3i) -> float:
	return 0.0 if key.z == Terrain.EAST else PI * 0.5


## A flat-colour box standing on the ground, its origin at its base.
func _box(size: Vector3, material: Material) -> Node3D:
	var holder := Node3D.new()
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position.y = size.y * 0.5
	holder.add_child(box)
	return holder


## The ground: one mesh per FLOOR_CHUNK square, a vertex at each corner of
## its cells (one per height where cells of different heights meet), so no
## cell is a tile of its own. The kinds go in a texture, a texel a cell,
## that ground.gdshader reads with noise (ragged borders, not cell edges);
## the light and heat on each corner go in its CUSTOM0 bytes, updated where
## they change (_shade_floor).
func _build_ground(kinds: Dictionary) -> void:
	# Water's cells are the ground too, its bed: a corner with water all
	# round it sinks WATER_BED_DEPTH, so a pond deepens toward its middle
	# and meets its shore with no edge (the surface is _build_water's).
	# Outdoors, the void's first FOREST_GROUND cells are the ground too,
	# under the forest: the land runs into the forest floor along a ragged
	# line (the mask's g), not the cells' outline.
	# Dry water (_dry_water) is drawn as the land: placed with it, before
	# the water; floor_count is where the land ends. A bridge's cells are
	# floor to the sim but water here, at the stream's bed (_bed_levels).
	_measure_streams()
	_wet.clear()
	for cell: Vector2i in _terrain.get("water", []):
		if not _dry_water.has(cell):
			_wet[cell] = true
	_wet.merge(_fords)
	_ground_top = -INF
	_ground_bottom = INF
	# Tall grass's cells, read here so setup's first build has them as a
	# rebuild's does (decision 508, terrain's side); its clumps are drawn anew.
	_tall.clear()
	for cell: Vector2i in _terrain.get("tall_grass", []):
		_tall[cell] = true
	_tall_where.clear()
	_tall_flat.clear()
	var land: Array = []
	for cell: Vector2i in _terrain["floor"]:
		if not _bed_levels.has(cell):
			land.append(cell)
	# A rock's ground is its footing (kinds), under the rock (_add_rocks).
	land.append_array(_rocks.keys())
	# A solid building's cells (decision 550) are out of the floor, but the
	# ground under it is the level's own kind (a mound's grass), so a round
	# piece on its square sits on that, not the forest's floor.
	for cell: Vector2i in _terrain.get("solid", []):
		if not _rocks.has(cell):
			land.append(cell)
	var floor_size: int = land.size()
	var dry: Array = []
	var wet: Array = []
	for cell: Vector2i in _terrain.get("water", []):
		(dry if _dry_water.has(cell) else wet).append(cell)
	wet.append_array(_bed_levels.keys())
	var cells: Array = land + dry + wet
	var floor_count := floor_size + dry.size()
	# A stream's own cells (decision 557), its ribbon's: the mask's a.
	var running: Dictionary = {}
	for cell: Vector2i in wet:
		running[cell] = true
	running.merge(_fords)
	_stream_cells = _streams_cells(running)
	# The waters as curves (559, terrain's side): theirs too.
	_read_curves()
	# The roads as curves (563, terrain's side).
	_read_roads()
	# The ledges as curves (585, terrain's side).
	_read_ledges()
	for cell: Vector2i in _curve_cells:
		_stream_cells[cell] = true
	# Built water (decision 595): Jeff's curve rule is for natural water
	# (rivers, streams, natural shorelines), and all of it is a curve; water
	# with no curve near it (within its reach, so a bank cell the level lays
	# beside a curve's own is natural) is built, drawn square.
	_built_water.clear()
	var stream_path: Dictionary[Vector2i, bool] = {}
	for stream: Dictionary in _terrain.get("streams", []):
		for cell: Vector2i in stream.get("path", []):
			stream_path[cell] = true
	for cell: Vector2i in _wet:
		if not _fords.has(cell) and not _curve_near_sample.has(cell) and not stream_path.has(cell) and not _bed_levels.has(cell):
			_built_water[cell] = true
	var water_end := cells.size()
	# Under the stands the floor is their needles (the forest floor's), so
	# the land runs only into the first ring.
	var ground_ring := PineStands.FROM - 1 if PineStands.drawn() else FOREST_GROUND
	for cell: Vector2i in _forest_distance:
		if _forest_distance[cell] >= 1 and _forest_distance[cell] <= ground_ring:
			cells.append(cell)
	# The ground runs under a grown forest's trunks (decision 467).
	cells.append_array(_grown_trunks.keys())
	_ground_cells = cells
	_ground_water_end = water_end
	_ground_floor_end = floor_count
	_cell_shades = PackedByteArray()
	_vertex_chunk = PackedInt32Array()
	_vertex_byte = PackedInt32Array()
	_vertex_cells = PackedInt32Array()
	_cell_vertex_start = PackedInt32Array()
	_cell_vertices = PackedInt32Array()
	_ground_bytes = PackedByteArray()
	_ground_meshes.clear()
	_scatter_chunks.clear()
	_chunk_byte_start = PackedInt32Array()
	if cells.is_empty():
		return
	var low := Vector2i(1 << 30, 1 << 30)
	var high := -low
	for cell: Vector2i in cells:
		low = low.min(cell)
		high = high.max(cell)
	# The cells by place (index or -1) and the levels of their corners (a
	# stair's two on its high side a level up: a ramp), the kinds texture a
	# texel a cell with a border of one, and the cells by chunk.
	var across := high.x - low.x + 3
	var down := high.y - low.y + 3
	var origin := low - Vector2i.ONE
	var at := PackedInt32Array()
	at.resize(across * down)
	at.fill(-1)
	var heights := PackedFloat32Array()
	heights.resize(cells.size() * 4)
	var kind_bytes := PackedByteArray()
	kind_bytes.resize(across * down * 4)
	# The water mask: r water (a ford's and a bridge's too), g the forest's
	# ground, b a ford's shallows.
	var water_bytes := PackedByteArray()
	water_bytes.resize(across * down * 4)
	_floor_bytes = PackedByteArray()
	_floor_bytes.resize(across * down)
	var chunks: Dictionary[Vector2i, PackedInt32Array] = {}
	for i in cells.size():
		var cell: Vector2i = cells[i]
		var kind := str(kinds.get(cell, "stone")) if i < floor_size else _bed_kind(cell, kinds, floor_size) if i < water_end else "grass"
		# A road's cell drawn as the ground round it: the road is drawn from
		# its curve (563, terrain's side), never as its cells.
		if i < floor_size and _road_cells.has(cell):
			kind = _road_kind_round(cell, kinds)
		if not GROUND_CHANNELS.has(kind):
			kind = "stone"
		_grounds[cell] = i
		_ground_kinds[cell] = kind
		var corner_heights := _ground_corners(cell)
		_corners[cell] = corner_heights
		for c in 4:
			heights[i * 4 + c] = corner_heights[c]
		_ground_top = maxf(_ground_top, maxf(maxf(corner_heights[0], corner_heights[1]), maxf(corner_heights[2], corner_heights[3])))
		_ground_bottom = minf(_ground_bottom, minf(minf(corner_heights[0], corner_heights[1]), minf(corner_heights[2], corner_heights[3])))
		var place := (cell.y - origin.y) * across + cell.x - origin.x
		at[place] = i
		kind_bytes[place * 4 + GROUND_CHANNELS[kind]] = 255
		if i < floor_count:
			_floor_bytes[place] = FLOOR_SETS.get(_floor_set(cell, kind), 0)
		if i >= water_end:
			water_bytes[place * 4 + 1] = 255
		elif i >= floor_count or _fords.has(cell):
			water_bytes[place * 4] = 255
		if _fords.has(cell):
			water_bytes[place * 4 + 2] = 255
		if _stream_cells.has(cell):
			water_bytes[place * 4 + 3] = 255
		var chunk := Vector2i(floori(cell.x / float(FLOOR_CHUNK)), floori(cell.y / float(FLOOR_CHUNK)))
		if not chunks.has(chunk):
			chunks[chunk] = PackedInt32Array()
		chunks[chunk].append(i)
	_scatter_chunks = chunks
	_cell_shades.resize(cells.size() * 2)
	for i in cells.size():
		_cell_shades[i * 2] = 255
	var format := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_INDEX \
			| Mesh.ARRAY_FORMAT_CUSTOM0 | (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	_ground_stride = RenderingServer.mesh_surface_get_format_attribute_stride(format, 1)
	_ground_custom = RenderingServer.mesh_surface_get_format_offset(format, 1, Mesh.ARRAY_CUSTOM0)
	_water_mask = ImageTexture.create_from_image(Image.create_from_data(across, down, false, Image.FORMAT_RGBA8, water_bytes))
	var wet_cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in wet:
		wet_cells[cell] = true
	wet_cells.merge(_fords)
	# The cells' field for water without a curve, a curve's from the curve
	# itself (559, terrain's side), never from its cells. The cells' path
	# (553's rounded cells, 557's cell streams) is only a fallback for a
	# level with no curves (the sample, tests): Jeff vetoed it (556 and 558
	# withdrawn), and every shipped level's water is a curve.
	var by_cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in wet_cells:
		if not _curve_cells.has(cell) and not _built_water.has(cell):
			by_cells[cell] = true
	var cell_streams: Array = (_terrain.get("streams", []) as Array).filter(func(stream: Dictionary) -> bool:
		return not (stream.get("path", []) as Array).all(func(cell: Vector2i) -> bool: return _curve_cells.has(cell)))
	_shore_image = shore_image(cell_streams, by_cells, origin, Vector2i(across, down))
	_depth_image = _water_depth(by_cells, origin, _shore_image.get_size())
	_curve_field(_shore_image, _depth_image, origin)
	_shore_mask = ImageTexture.create_from_image(_shore_image)
	_depth_mask = ImageTexture.create_from_image(_depth_image)
	_road_image = _road_field(origin, _shore_image.get_size())
	_road_mask = ImageTexture.create_from_image(_road_image)
	_floor_mask = ImageTexture.create_from_image(Image.create_from_data(across, down, false, Image.FORMAT_R8, _floor_bytes))
	_mask_origin = origin
	_mask_size = Vector2i(across, down)
	_publish_floor_shade()
	canopy_texture = canopy_mask(_terrain.get("canopy", {}), origin, _mask_size)
	canopy_origin = origin
	var material := _ground_material(kind_bytes, across, down, origin)
	material.set_shader_parameter("roads", _road_mask)
	_edge_mask = ImageTexture.create_from_image(_edge_field(origin, _shore_image.get_size())) if not _edge_curves.is_empty() else null
	material.set_shader_parameter("forest_edge", _edge_mask)
	# Hills read (decision 525, terrain's side): slopes lit against the sun.
	material.set_shader_parameter("slope_shade", SLOPE_SHADE if _relief_given else 0.0)
	_ground_look = material
	_hillshade_yaw = NAN
	_aim_hillshade()
	material.set_shader_parameter("canopy", canopy_texture)
	_build_shafts()
	# Each (cell, vertex) the cell's shade reaches, gathered by cell after.
	var pair_cell := PackedInt32Array()
	var pair_vertex := PackedInt32Array()
	# The cells round a corner, and which of their corners it is.
	var around: Array[Vector2i] = [-Vector2i.ONE, Vector2i(0, -1), Vector2i(-1, 0), Vector2i.ZERO]
	var ends := PackedInt32Array([0, 0, 0, 0])
	# The shore's cells drawn finer, SHORE_RES a side (decision 553).
	_shore_heights = _shore_band(cells, floor_count, water_end)
	# The cells a ledge's curve splits (585, terrain's side): each side drawn
	# at its own ground, meeting the face on the curve.
	_plan_ledge_splits(cells, floor_count)
	# A chunk's vertex for each corner (or a shore cell's finer point, in
	# SHORE_RES units) and height (mm): one a side of a cliff.
	var local: Dictionary[Vector3i, int] = {}
	for chunk: Vector2i in chunks:
		var chunk_index := _ground_meshes.size()
		var base := chunk * FLOOR_CHUNK
		var byte_start := _ground_bytes.size()
		_chunk_byte_start.append(byte_start)
		local.clear()
		var positions := PackedVector3Array()
		var indices := PackedInt32Array()
		# Each corner's relief, a byte each: at the foot of a drop (shaded),
		# at its top (lit a little).
		var feet := PackedByteArray()
		var tops := PackedByteArray()
		# The shore cells' finer triangles, as spans of indices [from, to).
		var finer := PackedInt32Array()
		for i in chunks[chunk]:
			var cell: Vector2i = cells[i]
			if _shore_heights.has(cell):
				finer.append(indices.size())
				_shore_cell(cell, positions, indices, feet, tops, local, chunk_index, byte_start, pair_cell, pair_vertex)
				finer.append(indices.size())
				continue
			if _ledge_split.has(cell):
				_ledge_cell(cell, positions, indices, feet, tops, local, chunk_index, byte_start, pair_cell, pair_vertex)
				continue
			for c in 4:
				var corner := cell + GROUND_CORNERS[c]
				var level := heights[i * 4 + c]
				var key := Vector3i(corner.x * SHORE_RES, corner.y * SHORE_RES, roundi(level * 1000.0))
				var vertex: int = local.get(key, -1)
				if vertex < 0:
					vertex = positions.size()
					local[key] = vertex
					var sunk := true
					for a in 4:
						var next := corner + around[a]
						var other := at[(next.y - origin.y) * across + next.x - origin.x]
						sunk = sunk and other >= floor_count and other < water_end
					positions.append(Vector3(corner.x - 0.5, level - (WATER_BED_DEPTH if sunk else 0.0), corner.y - 0.5))
					var global := _vertex_chunk.size()
					_vertex_chunk.append(chunk_index)
					_vertex_byte.append(byte_start + vertex * _ground_stride + _ground_custom)
					var foot := false
					var top := false
					for a in 4:
						var next := corner + around[a]
						var other := at[(next.y - origin.y) * across + next.x - origin.x]
						# This corner is the other cell's corner 3 - a.
						var theirs := heights[other * 4 + 3 - a] if other >= 0 else 0.0
						foot = foot or theirs > level + Relief.EPSILON
						top = top or theirs < level - Relief.EPSILON
						if other >= 0 and absf(theirs - level) > Relief.EPSILON:
							other = -1
						_vertex_cells.append(other)
						if other >= 0:
							pair_cell.append(other)
							pair_vertex.append(global)
					feet.append(255 if foot else roundi(_concavity(corner, level) * 255.0))
					tops.append(255 if top else roundi(_crest(corner, level) * 255.0))
				ends[c] = vertex
			indices.append_array([ends[0], ends[1], ends[2], ends[1], ends[3], ends[2]])
		var custom := PackedByteArray()
		custom.resize(positions.size() * 4)
		_ground_bytes.resize(byte_start + positions.size() * _ground_stride)
		for v in positions.size():
			var byte := byte_start + v * _ground_stride + _ground_custom
			# (A glimpse's own light is none: the sky's alone, sky_floor.)
			custom[v * 4] = 0 if _glimpse else 255
			custom[v * 4 + 2] = feet[v]
			custom[v * 4 + 3] = tops[v]
			_ground_bytes[byte] = 0 if _glimpse else 255
			_ground_bytes[byte + 2] = feet[v]
			_ground_bytes[byte + 3] = tops[v]
		# Up, but tilted on and beside a ramp: each corner the sum of the
		# faces round it. A shore cell's finer triangle counts as the whole
		# cell's it stands for (SHORE_RES squared its area), so a corner it
		# shares with a cell drawn whole leans as much its way as before
		# (else the bank's slope stops at the band, a light seam).
		var normals := PackedVector3Array()
		normals.resize(positions.size())
		normals.fill(Vector3.ZERO)
		var span := 0
		for t in range(0, indices.size(), 3):
			while span < finer.size() and t >= finer[span + 1]:
				span += 2
			var weight := float(SHORE_RES * SHORE_RES) if span < finer.size() and t >= finer[span] else 1.0
			var face := (positions[indices[t + 2]] - positions[indices[t]]).cross(positions[indices[t + 1]] - positions[indices[t]]) * weight
			for k in 3:
				normals[indices[t + k]] += face
		for v in normals.size():
			normals[v] = normals[v].normalized()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_CUSTOM0] = custom
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
				Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		_ground_meshes.append(mesh)
		var drawn := MeshInstance3D.new()
		drawn.name = "Ground_%d_%d" % [chunk.x, chunk.y]
		drawn.mesh = mesh
		drawn.material_override = material
		# On relief the ground casts (the hills' cues sheet): an escarpment's
		# back and a way throw their shadow across the valley at a low sun,
		# no longer than shadow_elevation lets any shadow be.
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _relief_given \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_room.add_child(drawn)
	_chunk_byte_start.append(_ground_bytes.size())
	# The pairs gathered by cell.
	_cell_vertex_start.resize(cells.size() + 1)
	_cell_vertex_start.fill(0)
	for cell in pair_cell:
		_cell_vertex_start[cell + 1] += 1
	for i in cells.size():
		_cell_vertex_start[i + 1] += _cell_vertex_start[i]
	_cell_vertices.resize(pair_cell.size())
	var filled := _cell_vertex_start.duplicate()
	for p in pair_cell.size():
		var cell := pair_cell[p]
		_cell_vertices[filled[cell]] = pair_vertex[p]
		filled[cell] += 1


## The shore's cells drawn finer (decision 553), by cell: each one's
## heights ((SHORE_RES + 1) squared, row by row); none on a level with no
## relief, whose water lies over its ground and shows its edge by the shore
## field alone (the flat ground drawn as before). A shore cell is a ground
## cell of land or water (not the forest's ring, a building's floor, a
## rock's or a ramp's) with both water and land in the 3 x 3 round it and no
## cliff on any side (its corners and its neighbour's differ). A point's
## height eases from the dry ground to the bed by the shore field there
## (shore_at, 0.3 to 0.5), each a mix of its cell's corners' (_shore_corner),
## so two cells meet on their edge and the water meets the ground on the
## field's half. Its corners' heights become the cell's in _corners.
func _shore_band(cells: Array, floor_count: int, water_end: int) -> Dictionary[Vector2i, PackedFloat32Array]:
	var band: Dictionary[Vector2i, PackedFloat32Array] = {}
	if _shore_image == null or _glimpse or not _relief_given:
		return band
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var picked: Dictionary[Vector2i, bool] = {}
	for i in water_end:
		var cell: Vector2i = cells[i]
		if _rocks.has(cell) or _ramp_heights.has(cell) or _floor_bytes_at(cell) != 0:
			continue
		var water := false
		var land := false
		for y in range(-1, 2):
			for x in range(-1, 2):
				var near := cell + Vector2i(x, y)
				var index: int = _grounds.get(near, -1)
				if index < 0 or index >= water_end:
					continue
				if (_wet.has(near) and not _built_water.has(near)) or _bed_levels.has(near):
					water = true
				else:
					land = true
		if not (water and land) and not _curve_cells.has(cell):
			continue
		var own: PackedFloat32Array = _corners[cell]
		var cliff := false
		for side in sides:
			var next := cell + side
			if not _corners.has(next):
				continue
			var theirs: PackedFloat32Array = _corners[next]
			for c in 4:
				var k := GROUND_CORNERS.find(cell + GROUND_CORNERS[c] - next)
				if k >= 0 and absf(theirs[k] - own[c]) > Relief.EPSILON:
					cliff = true
		if not cliff:
			picked[cell] = true
	var corners: Dictionary[Vector2i, Vector2] = {}
	for cell: Vector2i in picked:
		for c in 4:
			var corner := cell + GROUND_CORNERS[c]
			if not corners.has(corner):
				corners[corner] = _shore_corner(corner, picked, floor_count, water_end)
	var row := SHORE_RES + 1
	for cell: Vector2i in picked:
		if _curve_band(cell):
			band[cell] = _curve_fine(cell, picked)
			continue
		var ends: Array[Vector2] = []
		for c in 4:
			ends.append(corners[cell + GROUND_CORNERS[c]])
		var fine := PackedFloat32Array()
		fine.resize(row * row)
		for y in row:
			for x in row:
				var u := x / float(SHORE_RES)
				var v := y / float(SHORE_RES)
				var mixed := ends[0].lerp(ends[1], u).lerp(ends[2].lerp(ends[3], u), v)
				var m := shore_at(Vector2(cell) + Vector2(u - 0.5, v - 0.5))
				fine[y * row + x] = lerpf(mixed.y, mixed.x, smoothstep(0.3, 0.5, m))
		band[cell] = fine
	for cell: Vector2i in band:
		var fine: PackedFloat32Array = band[cell]
		_corners[cell] = PackedFloat32Array([fine[0], fine[SHORE_RES], fine[SHORE_RES * row], fine[row * row - 1]])
	return band


## Whether [param cell] has a building's floor set (the floors mask), 0
## for the ground's own.
func _floor_bytes_at(cell: Vector2i) -> int:
	var at := cell - _mask_origin
	if at.x < 0 or at.y < 0 or at.x >= _mask_size.x or at.y >= _mask_size.y:
		return 0
	return _floor_bytes[at.y * _mask_size.x + at.x]


## A shore corner's heights (decision 553): x its bed's (the ground as the
## cells draw it, under the water's edge where water and land meet at
## it), y the dry ground's (the ground as the cells draw it: the bank
## already comes down to the water, decision 525, so the field shapes only
## its last dip under the edge, not a wall). Both the picked cells' own
## where a cell round it is drawn whole (not in [param picked]), so the
## finer cells meet it with no gap.
func _shore_corner(corner: Vector2i, picked: Dictionary, floor_count: int, water_end: int) -> Vector2:
	var drawn := 0.0
	var count := 0
	var pinned := false
	var all_water := true
	var land := false
	var water := false
	for a in 4:
		var cell := corner + SHORE_AROUND[a]
		var index: int = _grounds.get(cell, -1)
		if index < 0:
			all_water = false
			continue
		pinned = pinned or not picked.has(cell)
		# This corner is the cell's corner 3 - a, as the cell draws it: the
		# picked cells' only, which meet their sides with no cliff (a cell
		# across the corner may stand a cliff over them).
		if picked.has(cell):
			drawn += _corners[cell][3 - a]
			count += 1
		all_water = all_water and index >= floor_count and index < water_end
		if index >= water_end:
			continue
		if _wet.has(cell) or _bed_levels.has(cell):
			water = true
		else:
			land = true
	var bed := drawn / maxi(count, 1) - (WATER_BED_DEPTH if all_water else 0.0)
	if pinned or not water or not land:
		return Vector2(bed, bed)
	return Vector2(minf(bed, _water_corner(corner) - SHORE_SINK), bed)


## The water's surface at [param point] (decision 557): over the cell it is
## in, the bilinear of its corners' (_water_corner), as the bed under it
## (_shore_bed) is; a corner with no water round it the mean of the cell's
## that have; the cell's own level with none.
func _water_surface(point: Vector2) -> float:
	var cell := Vector2i(roundi(point.x), roundi(point.y))
	var ys := PackedFloat32Array([INF, INF, INF, INF])
	var sum := 0.0
	var count := 0
	for c in 4:
		ys[c] = _water_corner(cell + GROUND_CORNERS[c])
		if ys[c] < INF:
			sum += ys[c]
			count += 1
	if count == 0:
		return _bed_levels.get(cell, _elevation(cell))
	for c in 4:
		if ys[c] == INF:
			ys[c] = sum / count
	var f := (point - Vector2(cell) + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	return lerpf(lerpf(ys[0], ys[1], f.x), lerpf(ys[2], ys[3], f.x), f.y)


## A stream's own cells (decision 557): its path's, and the water beside
## them (side or corner) that is not a pond's inside (water all round).
## The ribbons draw them; the bodies (_build_water) leave them out.
func _streams_cells(wet: Dictionary) -> Dictionary[Vector2i, bool]:
	var own: Dictionary[Vector2i, bool] = {}
	for stream: Dictionary in _terrain.get("streams", []):
		for cell: Vector2i in stream.get("path", []):
			own[cell] = true
			for y in range(-1, 2):
				for x in range(-1, 2):
					var near := cell + Vector2i(x, y)
					if not wet.has(near) or own.has(near):
						continue
					var inside := true
					for yy in range(-1, 2):
						for xx in range(-1, 2):
							inside = inside and wet.has(near + Vector2i(xx, yy))
					if not inside:
						own[near] = true
	return own


## Each stream's water as a ribbon along its path (decision 557, step 2 of
## the unsquaring, on 553's spline): the Catmull-Rom through its path
## cells' middles, RIBBON_STEPS a cell, out half a cell from the furthest of
## its own cells across the flow each side and RIBBON_UNDER more under the
## banks, where the shore field (553) draws the edge. Its surface the
## water's along it (_water_surface), so a fall's drop (over FALL_LEAST)
## slopes over its cell and the bed stays SHORE_SINK under it. Each
## point's colour: the way it runs (r, g: 0.5 plus half of it), how fast
## (b: half FLOW_SPEED's share, faster where it drops), its fall's foam (a).
## The falls listed in stream_falls, a new array each build.
func _build_ribbons() -> void:
	var falls: Array[Dictionary] = []
	for index in (_terrain.get("streams", []) as Array).size():
		var path: Array = _terrain["streams"][index].get("path", [])
		if path.size() < 2:
			continue
		var levels := PackedFloat32Array()
		var widths := PackedVector2Array()
		for i in path.size():
			var cell: Vector2i = path[i]
			# The ground's drop down the path (a bridge's cell by its bed, not
			# the deck the level writes into its relief): its falls and how
			# fast it runs.
			levels.append(_bed_levels.get(cell, _elevation(cell)))
			var way: Vector2i = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).sign()
			var across := Vector2i(0, 1) if absi(way.x) >= absi(way.y) else Vector2i(1, 0)
			var reach := Vector2.ZERO
			for k in range(1, 3):
				if _stream_cells.has(cell + across * k) and reach.x == k - 1:
					reach.x = k
				if _stream_cells.has(cell - across * k) and reach.y == k - 1:
					reach.y = k
			# Across the flow's normal (turned left of the way): which side
			# is the axis's plus.
			var left := Vector2(-way.y, way.x)
			widths.append(Vector2(reach.x, reach.y) if left.dot(Vector2(across)) >= 0.0 else Vector2(reach.y, reach.x))
		for i in range(1, path.size()):
			var drop := levels[i - 1] - levels[i]
			if drop > FALL_LEAST:
				falls.append({"cell": path[i], "drop": drop})
		# A stream laid from a water's curve is drawn from the curve
		# (_build_curve_ribbon); its falls listed here all the same.
		if path.all(func(cell: Vector2i) -> bool: return _curve_cells.has(cell)):
			continue
		var positions := PackedVector3Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		var samples := (path.size() - 1) * RIBBON_STEPS
		var before := INF
		for s in range(-RIBBON_STEPS / 2, samples + RIBBON_STEPS / 2 + 1):
			# Past either end, on along the way it runs, half a cell.
			var at := clampi(s, 0, samples)
			var i := mini(at / RIBBON_STEPS, path.size() - 2)
			var t := (at - i * RIBBON_STEPS) / float(RIBBON_STEPS)
			var a := Vector2(path[maxi(i - 1, 0)])
			var b := Vector2(path[i])
			var c := Vector2(path[i + 1])
			var d := Vector2(path[mini(i + 2, path.size() - 1)])
			var point := 0.5 * (2.0 * b + (c - a) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t
					+ (3.0 * b - a - 3.0 * c + d) * t * t * t)
			var tangent := (0.5 * ((c - a) + 2.0 * (2.0 * a - 5.0 * b + 4.0 * c - d) * t
					+ 3.0 * (3.0 * b - a - 3.0 * c + d) * t * t)).normalized()
			if tangent == Vector2.ZERO:
				tangent = (c - b).normalized()
			point += tangent * (s - at) / float(RIBBON_STEPS)
			var normal := Vector2(-tangent.y, tangent.x)
			var width: Vector2 = widths[i].lerp(widths[i + 1], t)
			var drop := levels[i] - levels[i + 1]
			# Never rising down the stream: between two path cells, within
			# their surfaces and no higher than the point before (a wide
			# river's cells across a bend, each laid from its own point along
			# its curve, can lift the field a little off its path; 559).
			var level := _water_surface(point) + WATER_LIFT
			if s > 0 and s <= samples:
				var upper := _water_surface(b) + WATER_LIFT
				var lower := _water_surface(c) + WATER_LIFT
				level = clampf(minf(level, before), minf(lower, upper), upper)
			elif s > samples:
				level = minf(level, before)
			before = level
			# White water from a fall's step: rising over the step to the cell
			# below, trailing off over the cell after it (557 amended).
			var after := levels[i - 1] - levels[i] if i > 0 else 0.0
			var fall := maxf(smoothstep(FALL_LEAST * 0.5, FALL_LEAST * 2.0, drop) * (sin(t * PI) if t < 0.5 else 1.0),
					smoothstep(FALL_LEAST * 0.5, FALL_LEAST * 2.0, after) * pow(1.0 - t, 1.5))
			var speed := clampf(0.5 + drop * 0.6, 0.5, 1.0)
			var colour := Color(tangent.x * 0.5 + 0.5, tangent.y * 0.5 + 0.5, speed, fall)
			for side: float in [width.x + 0.5 + RIBBON_UNDER, 0.0, -(width.y + 0.5 + RIBBON_UNDER)]:
				var spot := point + normal * side
				positions.append(Vector3(spot.x, level, spot.y))
				colours.append(colour)
			if s > -RIBBON_STEPS / 2:
				var row := positions.size() - 3
				var last := row - 3
				for k in 2:
					indices.append_array([last + k, row + k, last + k + 1, last + k + 1, row + k, row + k + 1])
		var normals := PackedVector3Array()
		normals.resize(positions.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colours
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var drawn := MeshInstance3D.new()
		drawn.name = "Stream_%d" % index
		drawn.mesh = mesh
		var material := _water_material()
		material.set_shader_parameter("ribbon", true)
		drawn.material_override = material
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_room.add_child(drawn)
		_stream_ribbons.append(drawn)
	stream_falls = falls


## The level's waters as curves (559, terrain's side, maps' 559: terrain "waters",
## each {curve: Curves.sample's, closed}), drawn from the curve and never
## from its cells (Jeff: "nothing inside the water shows the grid"). For
## each: its cells (Curves.cells), its surface along it (_curve_profile)
## and its fords' shallows along it; and for each cell near any of them
## the nearest sample (_curve_near reads the curve from there).
func _read_curves() -> void:
	_curve_waters.clear()
	_curve_cells.clear()
	_curve_near_sample.clear()
	_curve_near_also.clear()
	_curve_kept.clear()
	if _glimpse:
		return
	for w in (_terrain.get("waters", []) as Array).size():
		var water: Dictionary = _terrain["waters"][w]
		var curve: Dictionary = water["curve"]
		var points: PackedVector2Array = curve["points"]
		var widths: PackedFloat32Array = curve["widths"]
		var closed := bool(water.get("closed", false))
		if points.size() < 2:
			continue
		for cell: Vector2i in Curves.cells(curve, closed):
			# An earlier water keeps a cell a later one meets (as the level
			# lays them: a stream stops at the river).
			if (_grounds.has(cell) or _terrain_water_has(cell)) and not _curve_cells.has(cell):
				_curve_cells[cell] = w
		_stamp_near(curve, closed, _curve_waters.size(), _curve_near_sample, _curve_near_also)
		_curve_waters.append({"curve": curve, "closed": closed, "profile": PackedFloat32Array(), "shoal": PackedFloat32Array()})
	# Ponds inside their closed curve: every cell inside reads its curve too.
	for w in _curve_waters.size():
		if not _curve_waters[w]["closed"]:
			_curve_waters[w]["profile"] = _curve_profile(_curve_waters[w]["curve"])
			_curve_waters[w]["shoal"] = _curve_shoal(w)
			_meet_at_end(w)
	for cell: Vector2i in _curve_cells:
		if not _curve_near_sample.has(cell):
			_curve_near_sample[cell] = Vector2i(_curve_cells[cell], 0)


## A stream [param w] that ends in an earlier river (where it meets it, a
## confluence): its surface no lower than the river's there, so the two
## meet with no step down into the river's own water.
func _meet_at_end(w: int) -> void:
	var points: PackedVector2Array = _curve_waters[w]["curve"]["points"]
	var end := points[points.size() - 1]
	var cell := Vector2i(roundi(end.x), roundi(end.y))
	if not _curve_near_sample.has(cell):
		return
	var level := -INF
	for near: Vector2i in [_curve_near_sample[cell]] + _curve_near_also.get(cell, []):
		if near.x >= w or _curve_waters[near.x]["closed"]:
			continue
		var at := _near_one(_curve_waters, near, end, _curve_kept)
		if at.x <= 0.0:
			continue
		var profile: PackedFloat32Array = _curve_waters[near.x]["profile"]
		var i := clampi(floori(at.y), 0, profile.size() - 1)
		level = maxf(level, lerpf(profile[i], profile[mini(i + 1, profile.size() - 1)], at.y - i))
	if level == -INF:
		return
	var own: PackedFloat32Array = _curve_waters[w]["profile"]
	for k in own.size():
		own[k] = maxf(own[k], level)
	_curve_waters[w]["profile"] = own


## Whether the level lays water at [param cell] (its water, fords or bridges).
func _terrain_water_has(cell: Vector2i) -> bool:
	return _wet.has(cell) or _fords.has(cell) or _bed_levels.has(cell)


## Where [param point] is to the nearest water curve (559, terrain's side): x the
## signed distance, past its edge (the curve's width / 2 there, a pond's
## shore) into the water positive; y the sample index along it (fractional);
## z which water (-1: none near). Searched round the nearest sample of the
## point's cell, so a lookup costs a few segments, never the whole curve.
func _curve_near(point: Vector2) -> Vector3:
	return _near_on(_curve_waters, _curve_near_sample, point, _curve_near_also, _curve_kept)


## Each cell within reach of [param curve] (CURVE_REACH past its half
## width) -> (its [param index], its nearest sample) in [param into]; a
## cell another curve already reaches gets it in [param also] instead
## (where curves meet, _near_on takes their union).
func _stamp_near(curve: Dictionary, closed: bool, index: int, into: Dictionary, also: Dictionary) -> void:
	var points: PackedVector2Array = curve["points"]
	var widths: PackedFloat32Array = curve["widths"]
	var gaps: Dictionary[Vector2i, float] = {}
	var nearest: Dictionary[Vector2i, int] = {}
	for k in points.size():
		var reach := (widths[k] * 0.5 if not closed else 0.0) + CURVE_REACH
		var point := points[k]
		for y in range(floori(point.y - reach), ceili(point.y + reach) + 1):
			for x in range(floori(point.x - reach), ceili(point.x + reach) + 1):
				var cell := Vector2i(x, y)
				var gap := Vector2(cell).distance_to(point)
				if gap <= reach + 0.71 and gap < float(gaps.get(cell, INF)):
					gaps[cell] = gap
					nearest[cell] = k
	for cell: Vector2i in nearest:
		if into.has(cell):
			(also.get_or_add(cell, []) as Array).append(Vector2i(index, nearest[cell]))
		else:
			into[cell] = Vector2i(index, nearest[cell])


## _curve_near over [param curves] (each {curve, closed}) by their
## [param near] map and [param also] (_stamp_near's): where curves meet,
## the one the point is furthest into (their union).
func _near_on(curves: Array, near_map: Dictionary, point: Vector2, also: Dictionary, kept := {}) -> Vector3:
	var cell := Vector2i(roundi(point.x), roundi(point.y))
	if not near_map.has(cell):
		return Vector3(-INF, 0.0, -1.0)
	var best := _near_one(curves, near_map[cell], point, kept)
	for near: Vector2i in also.get(cell, []):
		var other := _near_one(curves, near, point, kept)
		if other.x > best.x:
			best = other
	return best


## A point is at most this far from its cell's middle (half a cell's
## diagonal, and a little over for rounding).
const CELL_REACH := 0.75


## The segments of [param points] searched round sample [param at] (by
## [param span], as _near_one and _edge_signed search them, in their
## order) that can be the nearest to some point of [param cell]: none
## whose distance from the cell's middle is over CELL_REACH x 2 past the
## nearest's, which no point of the cell can be nearer than the nearest's
## (each point is within CELL_REACH of the middle), so the search finds the
## same segment, the first at the least distance, in a few. Each segment
## by its first sample's index.
static func _near_segments(points: PackedVector2Array, closed: bool, at: int, span: int, cell: Vector2i) -> PackedInt32Array:
	var n := points.size()
	var middle := Vector2(cell)
	var found := PackedInt32Array()
	var gaps := PackedFloat32Array()
	var least := INF
	for j in range(at - span, at + span):
		var i := j
		if closed:
			i = posmod(j, n)
		elif i < 0 or i + 1 >= n:
			continue
		var gap := middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, points[i], points[(i + 1) % n]))
		found.append(i)
		gaps.append(gap)
		least = minf(least, gap)
	var out := PackedInt32Array()
	for k in found.size():
		if gaps[k] <= least + CELL_REACH * 2.0:
			out.append(found[k])
	return out


## Where [param point] is to one curve of [param curves], searched round
## its sample [param near] (which curve, which sample): as _curve_near.
## [param kept] holds _near_segments' by cell and [param near], made on
## first use (cleared with the curves; a test's own curves, a fresh one).
func _near_one(curves: Array, near: Vector2i, point: Vector2, kept := {}) -> Vector3:
	var water: Dictionary = curves[near.x]
	var curve: Dictionary = water["curve"]
	var points: PackedVector2Array = curve["points"]
	var widths: PackedFloat32Array = curve["widths"]
	var closed: bool = water["closed"]
	var n := points.size()
	var best := INF
	var along := 0.0
	var width := 0.0
	var span := CURVE_SEARCH if not closed else n
	var cell := Vector2i(roundi(point.x), roundi(point.y))
	var key := Vector4i(cell.x, cell.y, near.x, near.y)
	if not kept.has(key):
		kept[key] = _near_segments(points, closed, near.y, span, cell)
	for i: int in kept[key]:
		var a := points[i]
		var b := points[(i + 1) % n]
		var on := Geometry2D.get_closest_point_to_segment(point, a, b)
		var gap := point.distance_to(on)
		if gap < best:
			best = gap
			var t := a.distance_to(on) / maxf(a.distance_to(b), 0.0001)
			along = i + t
			width = lerpf(widths[i], widths[(i + 1) % n], t)
	if closed:
		return Vector3(best if Curves.inside(curve, point) else -best, along, near.x)
	return Vector3(width * 0.5 - best, along, near.x)


## The ground under each of [param curve]'s samples, before any
## smoothing: a bridge's water at its bed, not the deck the level writes
## into its relief (that read as a fall past every bridge).
func _curve_ground(curve: Dictionary) -> PackedFloat32Array:
	var base := PackedFloat32Array()
	for point: Vector2 in curve["points"]:
		var cell := Vector2i(roundi(point.x), roundi(point.y))
		base.append(_bed_levels.get(cell, _elevation(cell)))
	return base


## A river's surface along its samples (559, terrain's side): the ground under
## each (a bridge's water at its bed) smoothed over CURVE_SMOOTH samples
## either side, then never rising from the source down. A fall (a drop of
## over FALL_LEAST from one sample to the next) breaks the smoothing: each
## run between falls smoothed on its own, so the water keeps the step
## (a tall one hangs as a curtain, _build_curve_ribbon) and never sinks
## under the bed above the lip.
func _curve_profile(curve: Dictionary) -> PackedFloat32Array:
	var base := _curve_ground(curve)
	var runs := PackedInt32Array()
	runs.resize(base.size())
	for k in range(1, base.size()):
		runs[k] = runs[k - 1] + (1 if base[k - 1] - base[k] > FALL_LEAST else 0)
	var out := PackedFloat32Array()
	out.resize(base.size())
	for k in base.size():
		var sum := 0.0
		var count := 0
		for j in range(maxi(k - CURVE_SMOOTH, 0), mini(k + CURVE_SMOOTH, base.size() - 1) + 1):
			if runs[j] == runs[k]:
				sum += base[j]
				count += 1
		out[k] = sum / count
	for k in range(1, out.size()):
		out[k] = minf(out[k], out[k - 1])
	# The pool at a fall's foot stands on the ground there for a cell (the
	# smoothing had it under the foot cell's ground, a dry band between the
	# curtain and the water), never rising past it.
	var reach := int(1.0 / Curves.SPACING)
	for k in range(1, out.size()):
		if runs[k] == runs[k - 1]:
			continue
		for j in range(k, mini(k + reach + 1, out.size())):
			out[j] = minf(maxf(out[j], base[j] + SHORE_SINK), out[j - 1])
		for j in range(k + reach + 1, out.size()):
			if out[j] <= out[j - 1]:
				break
			out[j] = out[j - 1]
	return out


## Water [param w]'s fords as shallows along it (559, terrain's side): 1 at each
## ford cell's nearest sample, easing to 0 a cell either side.
func _curve_shoal(w: int) -> PackedFloat32Array:
	var points: PackedVector2Array = _curve_waters[w]["curve"]["points"]
	var shoal := PackedFloat32Array()
	shoal.resize(points.size())
	for cell: Vector2i in _fords:
		var near := _curve_near(Vector2(cell))
		if int(near.z) != w:
			continue
		for k in points.size():
			var gap := absf(k - near.y) * Curves.SPACING
			shoal[k] = maxf(shoal[k], 1.0 - smoothstep(0.5, 1.2, gap))
	return shoal


## The water's surface over [param point] on a river curve (559, terrain's side):
## its profile at the nearest sample; NAN off any.
func _curve_surface(point: Vector2) -> float:
	var near := _curve_near(point)
	if near.z < 0.0 or _curve_waters[int(near.z)]["closed"]:
		return NAN
	var profile: PackedFloat32Array = _curve_waters[int(near.z)]["profile"]
	var i := clampi(floori(near.y), 0, profile.size() - 1)
	return lerpf(profile[i], profile[mini(i + 1, profile.size() - 1)], near.y - i)


## The shore field's curve part (559, terrain's side): each texel near a
## water curve into [param image] 0.5 plus its signed distance (the edge at
## a half, a cell from dry to wet), into [param depth] half the distance
## into it (out to two cells); the larger kept where a water without a
## curve's is there too.
func _curve_field(image: Image, depth: Image, origin: Vector2i) -> void:
	var size := image.get_size()
	for cell: Vector2i in _curve_near_sample:
		var at := cell - origin
		if at.x < 0 or at.y < 0 or at.x * SHORE_RES >= size.x or at.y * SHORE_RES >= size.y:
			continue
		for v in SHORE_RES:
			for u in SHORE_RES:
				var point := Vector2(cell) + (Vector2(u, v) + Vector2(0.5, 0.5)) / SHORE_RES - Vector2(0.5, 0.5)
				var signed := _curve_near(point).x
				if signed == -INF:
					continue
				var texel := Vector2i(at.x * SHORE_RES + u, at.y * SHORE_RES + v)
				image.set_pixelv(texel, Color(maxf(image.get_pixelv(texel).r, clampf(0.5 + signed, 0.0, 1.0)), 0.0, 0.0))
				depth.set_pixelv(texel, Color(maxf(depth.get_pixelv(texel).r, clampf(signed * 0.5, 0.0, 1.0)), 0.0, 0.0))


## Each river curve's water as a ribbon (559, terrain's side, 557 on the curve):
## along its own samples, out to its width / 2 and RIBBON_UNDER under the
## banks each side, at its profile; each point's colour the way it runs
## (its tangent), how fast (b: faster where it drops), a fall's foam (a);
## its UV's x the fords' shallows. Where its surface drops FALL_TALL or more
## from one sample to the next (a tall fall, 570) it hangs as a curtain from
## the lip to the water below: rows bowed out down the stream (as water
## falls, out as the square root of the drop), white, their UV's y 1 (the
## shader's streaks run down it), facing down the stream. A pond (closed)
## is its curve's polygon, pushed out RIBBON_UNDER, at its level.
func _build_curve_ribbon(w: int) -> void:
	var water: Dictionary = _curve_waters[w]
	var curve: Dictionary = water["curve"]
	var points: PackedVector2Array = curve["points"]
	var widths: PackedFloat32Array = curve["widths"]
	var tangents: PackedVector2Array = curve["tangents"]
	var positions := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	if water["closed"]:
		var level := -INF
		for cell: Vector2i in _curve_cells:
			if _curve_cells[cell] == w:
				level = maxf(level, _bed_levels.get(cell, _elevation(cell)))
		var ring := Geometry2D.offset_polygon(points, RIBBON_UNDER)
		if ring.is_empty():
			return
		var shape: PackedVector2Array = ring[0]
		for point in shape:
			positions.append(Vector3(point.x, level + WATER_LIFT, point.y))
			colours.append(Color(0.5, 0.5, 0.0, 0.0))
			uvs.append(Vector2.ZERO)
			normals.append(Vector3.UP)
		indices = Geometry2D.triangulate_polygon(shape)
	else:
		var profile: PackedFloat32Array = water["profile"]
		var shoal: PackedFloat32Array = water["shoal"]
		var ground := _curve_ground(curve)
		var n := points.size()
		var reach := int(1.0 / Curves.SPACING)
		# From the first sample over water to the last: past them the curve
		# runs on over land (off the map's edge, where the level lays none
		# of its cells). Over another water's cells (a stream's end in the
		# river it meets, 570) it runs on, fading out over a cell (UV's y
		# under a half), so it ends in that water with no edge or gap.
		var start := 0
		var stop := n - 1
		while start < stop and not _curve_cells.has(Vector2i(points[start].round())):
			start += 1
		while stop > start and not _curve_cells.has(Vector2i(points[stop].round())):
			stop -= 1
		var first_own := start
		var last_own := stop
		while first_own < stop and _curve_cells.get(Vector2i(points[first_own].round()), -1) != w:
			first_own += 1
		while last_own > first_own and _curve_cells.get(Vector2i(points[last_own].round()), -1) != w:
			last_own -= 1
		for k in range(start, stop + 1):
			var tangent := tangents[k]
			var normal := Vector2(-tangent.y, tangent.x)
			var half := widths[k] * 0.5 + RIBBON_UNDER
			var ahead := mini(k + reach, n - 1)
			# The ground's drop over the cell ahead and behind, unsmoothed: a
			# fall's step stays a step.
			var drop := ground[k] - ground[ahead]
			var behind := ground[maxi(k - reach, 0)] - ground[k]
			# White water where it drops more than FALL_LEAST over a cell,
			# trailing on past it (557 amended's look).
			var fall := maxf(smoothstep(FALL_LEAST * 0.5, FALL_LEAST * 2.0, drop), smoothstep(FALL_LEAST * 0.5, FALL_LEAST * 2.0, behind) * 0.8)
			var speed := clampf(0.5 + drop * 0.6, 0.5, 1.0)
			var colour := Color(tangent.x * 0.5 + 0.5, tangent.y * 0.5 + 0.5, speed, fall)
			# A tall fall: the curtain's rows from the lip (the last sample's
			# place and height, on) down to this one's, before its own row.
			if k > start and profile[k - 1] - profile[k] >= FALL_TALL:
				var lip := points[k - 1]
				var drop_here := profile[k - 1] - profile[k]
				var facing := Vector3(tangent.x, 0.25, tangent.y).normalized()
				var lip_half := widths[k - 1] * 0.5 + RIBBON_UNDER
				_fall_feet.append({"at": Vector3(points[k].x, profile[k] + WATER_LIFT, points[k].y), "across": Vector3(normal.x, 0.0, normal.y),
						"down": Vector3(tangent.x, 0.0, tangent.y), "width": widths[k], "drop": drop_here})
				for r in CURTAIN_ROWS + 1:
					var t := r / float(CURTAIN_ROWS)
					var at := lip.lerp(points[k], sqrt(t))
					var across := Vector2(-tangents[k - 1].y, tangents[k - 1].x).lerp(normal, t)
					var curtain_half := lerpf(lip_half, half, t)
					for side: float in [curtain_half, 0.0, -curtain_half]:
						var spot := at + across * side
						positions.append(Vector3(spot.x, profile[k - 1] - drop_here * t + WATER_LIFT, spot.y))
						colours.append(Color(colour.r, colour.g, 1.0, 1.0))
						uvs.append(Vector2(0.0, 1.0))
						normals.append(facing)
					_ribbon_quads(positions.size(), indices)
			var outside := maxi(first_own - k, k - last_own)
			var fade := clampf(outside / float(reach), 0.0, 1.0) * 0.49
			for side: float in [half, 0.0, -half]:
				var spot := points[k] + normal * side
				positions.append(Vector3(spot.x, profile[k] + WATER_LIFT, spot.y))
				colours.append(colour)
				uvs.append(Vector2(shoal[k], fade))
				normals.append(Vector3.UP)
			if k > start:
				_ribbon_quads(positions.size(), indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var drawn := MeshInstance3D.new()
	drawn.name = "Water_curve_%d" % w
	drawn.mesh = mesh
	var material := _water_material()
	material.set_shader_parameter("ribbon", true)
	material.set_shader_parameter("curved", true)
	drawn.material_override = material
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_room.add_child(drawn)
	_stream_ribbons.append(drawn)


## The forest's edge drawn from curves, not cells (decision 575; Jeff:
## "never cell regions with rounded edges"): the outline of the cells the
## forest grows round (_wooded: the land, glimpses, grown trunks), every
## loop of it (the land's rim and each grove inside it), each simplified
## (a staircase's run a line), its points moved across it a little by a
## slow noise, then a closed curve through them (Curves.sample). The land's
## cells stay the truth: the sim, the walk and sight never see the curve.
## Traced here: an authored forest's shape would be maps' "forests" curves
## in level.json later, read here the same way.
func _read_edges() -> void:
	_edge_curves.clear()
	_edge_near_sample.clear()
	_edge_near_also.clear()
	_edge_kept.clear()
	if not _outdoor or _wooded.is_empty() or _forest_distance.is_empty():
		return
	for loop: PackedVector2Array in _outline_loops(_wooded):
		var simple := _simplify_loop(loop, EDGE_SIMPLIFY)
		if simple.size() < 3:
			continue
		# A point a cell along each run: the curve through them keeps to the
		# runs (through their ends alone it bowed half a cell off a long one).
		var points := PackedVector2Array()
		for i in simple.size():
			var a := simple[i]
			var b := simple[(i + 1) % simple.size()]
			var steps := maxi(1, roundi(a.distance_to(b)))
			for j in steps:
				points.append(a.lerp(b, float(j) / steps))
		var moved := PackedVector2Array()
		for i in points.size():
			var along := (points[(i + 1) % points.size()] - points[i - 1]).normalized()
			var side := Vector2(-along.y, along.x)
			moved.append(points[i] + side * (_field(points[i], 3.0, 77) - 0.5) * 2.0 * EDGE_WOBBLE)
		var widths := PackedFloat32Array()
		widths.resize(moved.size())
		var curve := Curves.sample(moved, widths, true)
		if (curve["points"] as PackedVector2Array).size() < 3:
			continue
		_stamp_near(curve, true, _edge_curves.size(), _edge_near_sample, _edge_near_also)
		_edge_curves.append({"curve": curve, "closed": true})


## Every loop of the outline of [param cells] (their squares' outer edges,
## each loop going round with the cells on its right, y down), as the
## middles of its edges, so no corner of the grid is left. Where two cells
## meet at a corner alone (a pinch), the way on turns right: each loop
## keeps tight round its own cells.
static func _outline_loops(cells: Dictionary) -> Array[PackedVector2Array]:
	var leaving: Dictionary[Vector2, Array] = {}
	var edges := 0
	for cell: Vector2i in cells:
		var x := float(cell.x)
		var y := float(cell.y)
		var corners: Array[Vector2] = [Vector2(x - 0.5, y - 0.5), Vector2(x + 0.5, y - 0.5), Vector2(x + 0.5, y + 0.5), Vector2(x - 0.5, y + 0.5)]
		var sides: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
		for k in 4:
			if not cells.has(cell + sides[k]):
				if not leaving.has(corners[k]):
					leaving[corners[k]] = []
				leaving[corners[k]].append(corners[(k + 1) % 4])
				edges += 1
	var loops: Array[PackedVector2Array] = []
	while edges > 0:
		var start: Vector2 = leaving.keys()[0]
		var at := start
		var way := Vector2.ZERO
		var middles := PackedVector2Array()
		while leaving.has(at):
			var ends: Array = leaving[at]
			var pick := 0
			if ends.size() > 1 and way != Vector2.ZERO:
				var turn := -INF
				for i in ends.size():
					var to: Vector2 = ends[i] - at
					var right := way.x * to.y - way.y * to.x
					if right > turn:
						turn = right
						pick = i
			var after: Vector2 = ends[pick]
			ends.remove_at(pick)
			if ends.is_empty():
				leaving.erase(at)
			edges -= 1
			middles.append((at + after) / 2.0)
			way = after - at
			at = after
			if at == start and not leaving.has(at):
				break
			if at == start and middles.size() > 2:
				break
		loops.append(middles)
	return loops


## [param loop] (closed) with the fewest points within [param tolerance]
## of it (Douglas-Peucker, split at its two points farthest apart).
static func _simplify_loop(loop: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if loop.size() <= 4:
		return loop
	var far := 0
	for i in loop.size():
		if loop[i].distance_squared_to(loop[0]) > loop[far].distance_squared_to(loop[0]):
			far = i
	var first := _simplify_run(loop.slice(0, far + 1), tolerance)
	var back := loop.slice(far)
	back.append(loop[0])
	var second := _simplify_run(back, tolerance)
	var out := first.slice(0, first.size() - 1)
	out.append_array(second.slice(0, second.size() - 1))
	return out


## [param run]'s ends and the fewest points between within [param
## tolerance] of it (Douglas-Peucker).
static func _simplify_run(run: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if run.size() <= 2:
		return run
	var a := run[0]
	var b := run[run.size() - 1]
	var worst := -1.0
	var at := 0
	for i in range(1, run.size() - 1):
		var gap := run[i].distance_to(Geometry2D.get_closest_point_to_segment(run[i], a, b))
		if gap > worst:
			worst = gap
			at = i
	if worst <= tolerance:
		return PackedVector2Array([a, b])
	var left := _simplify_run(run.slice(0, at + 1), tolerance)
	var right := _simplify_run(run.slice(at), tolerance)
	left.resize(left.size() - 1)
	left.append_array(right)
	return left


## How far [param point] is into the forest past its edge's curve (decision
## 575): positive on the forest's side, negative on the land's; NAN with no
## edge near. The nearest of the curves near, its side by the way it runs
## (the land on its right going round).
func _edge_signed(point: Vector2) -> float:
	var cell := Vector2i(roundi(point.x), roundi(point.y))
	if not _edge_near_sample.has(cell):
		return NAN
	if not _edge_kept.has(cell):
		_edge_kept[cell] = _edge_segments(cell)
	return _edge_signed_on(point, _edge_kept[cell])


## _edge_signed against the segments [param ends] (_edge_segments' for the
## point's cell).
static func _edge_signed_on(point: Vector2, ends: PackedVector2Array) -> float:
	var best := INF
	var signed := NAN
	for k in range(0, ends.size(), 2):
		var a := ends[k]
		var b := ends[k + 1]
		var way := b - a
		var on := Geometry2D.get_closest_point_to_segment(point, a, b)
		var gap := point.distance_to(on)
		if gap < best:
			best = gap
			var cross := way.x * (point.y - a.y) - way.y * (point.x - a.x)
			signed = -gap if cross > 0.0 else gap
	return signed


## The edge's segments searched from [param cell] (round its near curves'
## samples, CURVE_SEARCH each way, in that order) that can be the nearest
## to a point of it, as _near_segments: each segment's two ends in turn.
func _edge_segments(cell: Vector2i) -> PackedVector2Array:
	var middle := Vector2(cell)
	var found := PackedVector2Array()
	var gaps := PackedFloat32Array()
	var least := INF
	for near: Vector2i in [_edge_near_sample[cell]] + _edge_near_also.get(cell, []):
		var points: PackedVector2Array = _edge_curves[near.x]["curve"]["points"]
		var n := points.size()
		for j in range(near.y - CURVE_SEARCH, near.y + CURVE_SEARCH):
			var a := points[posmod(j, n)]
			var b := points[posmod(j + 1, n)]
			# The seam's near-repeat point is no segment: its side is none.
			if (b - a).length_squared() < 0.0025:
				continue
			var gap := middle.distance_to(Geometry2D.get_closest_point_to_segment(middle, a, b))
			found.append(a)
			found.append(b)
			gaps.append(gap)
			least = minf(least, gap)
	var out := PackedVector2Array()
	for k in gaps.size():
		if gaps[k] <= least + CELL_REACH * 2.0:
			out.append(found[k * 2])
			out.append(found[k * 2 + 1])
	return out


## The forest edge's field (decision 575): an RG8 image the shore field's
## size and texels, r 0.5 plus the signed distance into the forest
## (_edge_signed: its edge at a half), g 1 where it is written (near an
## edge); the ground reads the cells' forest mask elsewhere.
func _edge_field(origin: Vector2i, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RG8)
	for cell: Vector2i in _edge_near_sample:
		var at := cell - origin
		if at.x < 0 or at.y < 0 or at.x * SHORE_RES >= size.x or at.y * SHORE_RES >= size.y:
			continue
		# Every texel's point rounds to this cell: its segments, once.
		if not _edge_kept.has(cell):
			_edge_kept[cell] = _edge_segments(cell)
		var ends: PackedVector2Array = _edge_kept[cell]
		if ends.is_empty():
			continue
		for v in SHORE_RES:
			for u in SHORE_RES:
				var point := Vector2(cell) + (Vector2(u, v) + Vector2(0.5, 0.5)) / SHORE_RES - Vector2(0.5, 0.5)
				var signed := _edge_signed_on(point, ends)
				if is_nan(signed):
					continue
				image.set_pixelv(Vector2i(at.x * SHORE_RES + u, at.y * SHORE_RES + v), Color(clampf(0.5 + signed, 0.0, 1.0), 1.0, 0.0))
	return image


## Mist at each tall fall's foot (570 amended, terrain's side; the
## coordinator: "a few soft particles in the pool's churn, cheap"): soft
## white billboard puffs rising from across the curtain's foot and drifting
## down the stream as they swell and fade, MIST_PUFFS at most a fall (fewer
## for a shorter one). None where there is no tall fall.
func _build_mists() -> void:
	for foot: Dictionary in _fall_feet:
		var mist := GPUParticles3D.new()
		mist.name = "Mist"
		mist.amount = maxi(6, roundi(MIST_PUFFS * clampf(float(foot["drop"]) / MIST_FULL, 0.0, 1.0)))
		mist.lifetime = MIST_SECONDS
		mist.preprocess = MIST_SECONDS
		mist.local_coords = false
		mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mist.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
		mist.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 5.0, 8.0))
		var down: Vector3 = foot["down"]
		var across: Vector3 = foot["across"]
		var process := ParticleProcessMaterial.new()
		process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		# Across the foot (its x, in the mist's own frame).
		process.emission_box_extents = Vector3(float(foot["width"]) * 0.5, 0.05, 0.2)
		process.direction = Vector3(0.0, 1.0, 0.6).normalized()
		process.spread = 25.0
		process.initial_velocity_min = 0.25
		process.initial_velocity_max = 0.6
		process.gravity = Vector3(0.0, -0.05, 0.0)
		process.damping_min = 0.2
		process.damping_max = 0.4
		process.scale_min = 0.6
		process.scale_max = 1.0
		var swell := Curve.new()
		swell.add_point(Vector2(0.0, 0.4))
		swell.add_point(Vector2(1.0, 1.0))
		var swell_texture := CurveTexture.new()
		swell_texture.curve = swell
		process.scale_curve = swell_texture
		var fade := Gradient.new()
		fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
		fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		fade.add_point(0.2, Color(1.0, 1.0, 1.0, 0.32))
		var fade_texture := GradientTexture1D.new()
		fade_texture.gradient = fade
		process.color_ramp = fade_texture
		mist.process_material = process
		mist.draw_pass_1 = _soft_puff(MIST_SIZE)
		# Its frame: x across the foot, z down the stream, y up.
		var at: Vector3 = foot["at"]
		mist.transform = Transform3D(Basis(-across, Vector3.UP, down), at + Vector3.UP * 0.1 + down * 0.15)
		_room.add_child(mist)
		_mists.append(mist)


## The level's ledges as curves (585, terrain's side; Jeff: "terrain needs
## to have smooth edges for ledges and terraces as well. it should not
## conform to tiles"): maps' terrain "ledges", each traced from the relief's
## cliff edges and within 0.45 of them (level_test). The sim's walk keeps the
## cells' cliffs (cliff_between); only the drawing follows the curve.
func _read_ledges() -> void:
	_ledge_curves.clear()
	_ledge_near_sample.clear()
	_ledge_near_also.clear()
	_ledge_split.clear()
	if _glimpse or not _relief_given:
		return
	for ledge: Dictionary in _terrain.get("ledges", []):
		var curve: Dictionary = ledge["curve"]
		if (curve["points"] as PackedVector2Array).size() < 2:
			continue
		if not curve.has("widths"):
			# No width to a ledge: its reach is CURVE_REACH from the line.
			curve = curve.duplicate()
			var none := PackedFloat32Array()
			none.resize((curve["points"] as PackedVector2Array).size())
			curve["widths"] = none
		var closed := bool(ledge.get("closed", false))
		_stamp_near(curve, closed, _ledge_curves.size(), _ledge_near_sample, _ledge_near_also)
		_ledge_curves.append({"curve": curve, "closed": closed, "up": 1 if str(ledge.get("up", "right")) == "right" else -1})


## Where [param point] is to the nearest ledge's curve near it (585): x how
## far past it on its high side (negative on its low side), y which ledge,
## z the sample index (fractional) along it; y -1 with none near.
func _ledge_near(point: Vector2) -> Vector3:
	var cell := Vector2i(roundi(point.x), roundi(point.y))
	if not _ledge_near_sample.has(cell):
		return Vector3(0.0, -1.0, 0.0)
	var best := INF
	var out := Vector3(0.0, -1.0, 0.0)
	for near: Vector2i in [_ledge_near_sample[cell]] + _ledge_near_also.get(cell, []):
		var ledge: Dictionary = _ledge_curves[near.x]
		var points: PackedVector2Array = ledge["curve"]["points"]
		var closed: bool = ledge["closed"]
		var n := points.size()
		for j in range(near.y - CURVE_SEARCH, near.y + CURVE_SEARCH):
			if not closed and (j < 0 or j + 1 >= n):
				continue
			var a := points[posmod(j, n)]
			var b := points[posmod(j + 1, n)]
			var way := b - a
			if way.length_squared() < 0.0025:
				continue
			var on := Geometry2D.get_closest_point_to_segment(point, a, b)
			var gap := point.distance_to(on)
			if gap < best:
				best = gap
				var cross := way.x * (point.y - a.y) - way.y * (point.x - a.x)
				var right := cross > 0.0
				var high := right == (int(ledge["up"]) > 0)
				out = Vector3(gap if high else -gap, near.x, posmod(j, n) + a.distance_to(on) / maxf(way.length(), 0.0001))
	return out


## The cells each ledge's curve crosses (585), split along it: each with its
## own middle's side, the cell beside it (a side, across the curve) whose
## plane draws its other side, and its square cut in two along the curve,
## the parts as polygons. A cell with no neighbour across, or the curve not
## through it, is drawn whole as before.
func _plan_ledge_splits(cells: Array, floor_count: int) -> void:
	_ledge_split.clear()
	if _ledge_curves.is_empty():
		return
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for i in floor_count:
		var cell: Vector2i = cells[i]
		if not _ledge_near_sample.has(cell) or _shore_heights.has(cell) or _rocks.has(cell) or _ramp_heights.has(cell):
			continue
		var middle := _ledge_near(Vector2(cell))
		if middle.y < 0.0 or absf(middle.x) > 0.75:
			continue
		var ledge: Dictionary = _ledge_curves[int(middle.y)]
		var own_high := middle.x > 0.0
		# The curve through the cell: a corner on the other side.
		var square := PackedVector2Array([Vector2(cell) + Vector2(-0.5, -0.5), Vector2(cell) + Vector2(0.5, -0.5),
				Vector2(cell) + Vector2(0.5, 0.5), Vector2(cell) + Vector2(-0.5, 0.5)])
		var crossed := false
		for corner in square:
			var at := _ledge_near(corner.lerp(Vector2(cell), 0.02))
			crossed = crossed or (at.y == middle.y and (at.x > 0.0) != own_high)
		if not crossed:
			continue
		# The cell across: a side whose middle is on the other side of it,
		# the nearer to the curve.
		var across := Vector2i(1 << 20, 0)
		var nearest := INF
		for side in sides:
			var next := cell + side
			var index: int = _grounds.get(next, -1)
			if index < 0 or index >= floor_count:
				continue
			var at := _ledge_near(Vector2(next))
			if at.y != middle.y or (at.x > 0.0) == own_high:
				continue
			if absf(at.x) < nearest:
				nearest = absf(at.x)
				across = next
		if across.x == 1 << 20:
			continue
		# The high side as a polygon: the curve's run through here, closed
		# three cells out on its high side.
		var points: PackedVector2Array = ledge["curve"]["points"]
		var tangents: PackedVector2Array = ledge["curve"]["tangents"]
		var n := points.size()
		var k := int(middle.z)
		var run := PackedVector2Array()
		var from := k - 8
		var to := k + 9
		if not bool(ledge["closed"]):
			from = maxi(from, 0)
			to = mini(to, n - 1)
		for j in range(from, to + 1):
			run.append(points[posmod(j, n)])
		var first_t := tangents[posmod(from, n)]
		var last_t := tangents[posmod(to, n)]
		var up := float(ledge["up"])
		var high_first := Vector2(-first_t.y, first_t.x) * up
		var high_last := Vector2(-last_t.y, last_t.x) * up
		# Run on past its ends, so the polygon spans the cell.
		run.insert(0, run[0] - first_t * 2.0)
		run.append(run[run.size() - 1] + last_t * 2.0)
		var high_side := PackedVector2Array(run)
		high_side.append(run[run.size() - 1] + high_last * 3.0)
		high_side.append(run[0] + high_first * 3.0)
		var parts: Array = []
		# Each part with whether it is the high side's, by where a point
		# inside it is (a sharp turn can fold the side polygon); past the
		# curve's open end there is no face, and the cell's own ground holds.
		var pieces: Array[PackedVector2Array] = []
		pieces.append_array(Geometry2D.intersect_polygons(square, high_side))
		pieces.append_array(Geometry2D.clip_polygons(square, high_side))
		for polygon in pieces:
			var inside := _inside_point(polygon)
			var at := _ledge_near(inside)
			var high := own_high
			if at.y == middle.y and (bool(ledge["closed"]) or at.z > 0.5 and at.z < n - 1.5):
				high = at.x > 0.0
			parts.append([polygon, high])
		if parts.all(func(part: Array) -> bool: return bool(part[1]) == own_high):
			continue
		if parts.size() < 2:
			continue
		_ledge_split[cell] = {"high": own_high, "across": across, "parts": parts, "ledge": int(middle.y)}


## A point inside [param polygon]: its first triangle's middle.
static func _inside_point(polygon: PackedVector2Array) -> Vector2:
	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.size() < 3:
		return polygon[0]
	return (polygon[triangles[0]] + polygon[triangles[1]] + polygon[triangles[2]]) / 3.0


## Whether [param point] in split [param cell] is past its ledge's curve,
## on the other ground's side (585).
func _ledge_other_side(cell: Vector2i, point: Vector2) -> bool:
	var split: Dictionary = _ledge_split[cell]
	var at := _ledge_near(point)
	return at.y == float(split["ledge"]) and (at.x > 0.0) != bool(split["high"])


## The plane of [param cell]'s drawn corners (bilinear) at [param point],
## inside the cell or a little past it (585: a split cell's other side drawn
## as the cell across's ground carried on to the curve).
func _cell_plane(cell: Vector2i, point: Vector2) -> float:
	var h := _corner_heights(cell)
	var at := point - Vector2(cell) + Vector2(0.5, 0.5)
	return lerpf(lerpf(h[0], h[1], at.x), lerpf(h[2], h[3], at.x), at.y)


## The ground on the high or low side ([param high]) of the ledge near
## [param point] (585): the plane of the cell there on that side, else the
## one beside it on that side nearest.
func _ledge_ground(point: Vector2, high: bool) -> float:
	var cell := Vector2i(roundi(point.x), roundi(point.y))
	var best := cell
	var gap := INF
	for y in range(-1, 2):
		for x in range(-1, 2):
			var near := cell + Vector2i(x, y)
			if not _corners.has(near):
				continue
			var at := _ledge_near(Vector2(near))
			if at.y < 0.0 or (at.x > 0.0) != high:
				continue
			var d := Vector2(near).distance_to(point)
			if d < gap:
				gap = d
				best = near
	return _cell_plane(best, point)


## Whether the cliff between [param cell] and [param next] is a ledge's,
## drawn along its curve (585): their middles either side of one ledge's
## curve near them.
func _ledge_covers(cell: Vector2i, next: Vector2i) -> bool:
	if _ledge_curves.is_empty() or not _ledge_near_sample.has(cell):
		return false
	var a := _ledge_near(Vector2(cell))
	var b := _ledge_near(Vector2(next))
	if a.y < 0.0 or a.y != b.y or (a.x > 0.0) == (b.x > 0.0):
		return false
	# The curve runs along this edge (within half a cell of its middle) and
	# its face there drops: else (a bank the ledges leave out, a taper's end)
	# the cell edge keeps its own face.
	var middle := (Vector2(cell) + Vector2(next)) / 2.0
	var at := _ledge_near(middle)
	if at.y != a.y or absf(at.x) > 0.5:
		return false
	var points: PackedVector2Array = _ledge_curves[int(at.y)]["curve"]["points"]
	var on := points[clampi(roundi(at.z), 0, points.size() - 1)]
	var drop := _ledge_ground(on, true) - _ledge_ground(on, false)
	return drop >= absf(_elevation(cell) - _elevation(next)) * 0.5


## The ledges' faces (585, terrain's side) into [param faces] (by chunk, as
## _add_cliffs'): along each curve's samples, from the high side's ground
## there down to the low side's, facing the low side; nothing where they
## meet (a taper's end, a slope).
func _add_ledge_faces(faces: Dictionary) -> void:
	for ledge: Dictionary in _ledge_curves:
		var points: PackedVector2Array = ledge["curve"]["points"]
		var tangents: PackedVector2Array = ledge["curve"]["tangents"]
		var up := float(ledge["up"])
		var count := points.size() - (0 if ledge["closed"] else 1)
		var tops := PackedFloat32Array()
		var feet := PackedFloat32Array()
		for point in points:
			tops.append(_ledge_ground(point, true))
			feet.append(_ledge_ground(point, false))
		for k in count:
			var j := (k + 1) % points.size()
			var top := Vector2(tops[k], tops[j])
			var foot := Vector2(minf(feet[k], tops[k]), minf(feet[j], tops[j]))
			if top.x - foot.x <= Relief.EPSILON and top.y - foot.y <= Relief.EPSILON:
				continue
			var middle := (points[k] + points[j]) / 2.0
			var cell := Vector2i(roundi(middle.x), roundi(middle.y))
			var chunk := Vector2i(floori(cell.x / float(FLOOR_CHUNK)), floori(cell.y / float(FLOOR_CHUNK)))
			if not faces.has(chunk):
				faces[chunk] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
			var t := (tangents[k] + tangents[j]).normalized()
			var low := Vector2(t.y, -t.x) * up
			_cliff_strip(faces[chunk], points[k], points[j], top, foot, Vector3(low.x, 0.0, low.y), 1)


## A split cell's two grounds into a chunk's arrays (585): each part of its
## square triangulated, its own side at its own corners' plane, the other at
## the cell across's, so each meets the face on the curve; a square corner
## keyed as the whole cells' are, so it joins them.
func _ledge_cell(cell: Vector2i, positions: PackedVector3Array, indices: PackedInt32Array,
		feet: PackedByteArray, tops: PackedByteArray, local: Dictionary, chunk_index: int, byte_start: int,
		pair_cell: PackedInt32Array, pair_vertex: PackedInt32Array) -> void:
	var split: Dictionary = _ledge_split[cell]
	var across: Vector2i = split["across"]
	for part: Array in split["parts"]:
		var polygon: PackedVector2Array = part[0]
		var own := bool(part[1]) == bool(split["high"])
		var drawn := cell if own else across
		var lit: int = _grounds.get(drawn, -1)
		var triangles := Geometry2D.triangulate_polygon(polygon)
		var made := PackedInt32Array()
		for point in polygon:
			var level := _cell_plane(drawn, point)
			var corner := Vector2i(roundi(point.x + 0.5), roundi(point.y + 0.5))
			var on_corner := (point - (Vector2(corner) - Vector2(0.5, 0.5))).length() < 0.0001
			var key := Vector3i(corner.x * SHORE_RES, corner.y * SHORE_RES, roundi(level * 1000.0))
			var vertex: int = local.get(key, -1) if on_corner else -1
			if vertex < 0:
				vertex = positions.size()
				if on_corner:
					local[key] = vertex
				positions.append(Vector3(point.x, level, point.y))
				var global := _vertex_chunk.size()
				_vertex_chunk.append(chunk_index)
				_vertex_byte.append(byte_start + vertex * _ground_stride + _ground_custom)
				_vertex_cells.append_array([lit, -1, -1, -1])
				if lit >= 0:
					pair_cell.append(lit)
					pair_vertex.append(global)
				feet.append(roundi(_concavity(corner, level) * 255.0))
				tops.append(roundi(_crest(corner, level) * 255.0))
			made.append(vertex)
		for t in triangles:
			indices.append(made[t])


## The two quads joining a ribbon's last row of three points (ending at
## [param size]) to the row before it, into [param indices].
static func _ribbon_quads(size: int, indices: PackedInt32Array) -> void:
	var row := size - 3
	var last := row - 3
	for j in 2:
		indices.append_array([last + j, row + j, last + j + 1, last + j + 1, row + j, row + j + 1])


## The depth of [param wet]'s water (cells without a curve; 559, terrain's
## side): an L8 image the size of the shore field, half the box distance
## from each texel to the nearest cell that is not water, out to two cells
## (as water.gdshader worked it out per pixel before), 0 elsewhere. Only
## the water's own texels are written.
static func _water_depth(wet: Dictionary, origin: Vector2i, size: Vector2i) -> Image:
	var out := Image.create(size.x, size.y, false, Image.FORMAT_L8)
	for cell: Vector2i in wet:
		var at := cell - origin
		if at.x < 0 or at.y < 0 or at.x * SHORE_RES >= size.x or at.y * SHORE_RES >= size.y:
			continue
		for v in SHORE_RES:
			for u in SHORE_RES:
				var point := (Vector2(u, v) + Vector2(0.5, 0.5)) / SHORE_RES - Vector2(0.5, 0.5)
				var nearest := 1.5
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						if not wet.has(cell + Vector2i(dx, dy)):
							var off := ((point - Vector2(dx, dy)).abs() - Vector2(0.5, 0.5)).max(Vector2.ZERO)
							nearest = minf(nearest, off.length())
				out.set_pixel(at.x * SHORE_RES + u, at.y * SHORE_RES + v, Color(clampf(nearest * 0.5, 0.0, 1.0), 0.0, 0.0))
	return out


## Whether [param cell], picked for the shore's finer cells, is drawn from
## a river's curve (559, terrain's side): near one, not a pond's.
func _curve_band(cell: Vector2i) -> bool:
	if not _curve_near_sample.has(cell):
		return false
	return not _curve_waters[_curve_near_sample[cell].x]["closed"]


## [param cell]'s finer heights from its river's curve (559, terrain's
## side): the ground as drawn (its corners' bilinear), easing under the
## water's edge (the curve's signed distance, as the shore field) to the
## bed, SHORE_SINK under the river's surface there and WATER_BED_DEPTH more
## toward its middle; nothing from the cells. A point on an edge or corner
## it shares with a cell drawn whole (not in [param picked]) keeps that
## cell's ground, so they meet with no gap.
func _curve_fine(cell: Vector2i, picked: Dictionary) -> PackedFloat32Array:
	var row := SHORE_RES + 1
	var h: PackedFloat32Array = _corners[cell]
	# As a cell drawn whole draws them: a corner with water all round sunk
	# WATER_BED_DEPTH (_build_ground).
	var drawn := PackedFloat32Array(h)
	for c in 4:
		var sunk := true
		for a in 4:
			var index: int = _grounds.get(cell + GROUND_CORNERS[c] + SHORE_AROUND[a], -1)
			sunk = sunk and index >= _ground_floor_end and index < _ground_water_end
		if sunk:
			drawn[c] -= WATER_BED_DEPTH
	var fine := PackedFloat32Array()
	fine.resize(row * row)
	for y in row:
		for x in row:
			var u := x / float(SHORE_RES)
			var v := y / float(SHORE_RES)
			var dry := lerpf(lerpf(h[0], h[1], u), lerpf(h[2], h[3], u), v)
			var pinned := false
			for dy: int in ([0, -1] if y == 0 else [0, 1] if y == SHORE_RES else [0]):
				for dx: int in ([0, -1] if x == 0 else [0, 1] if x == SHORE_RES else [0]):
					var near := cell + Vector2i(dx, dy)
					pinned = pinned or (near != cell and _grounds.has(near) and not picked.has(near))
			var point := Vector2(cell) + Vector2(u - 0.5, v - 0.5)
			var surface := _curve_surface(point)
			if pinned:
				fine[y * row + x] = lerpf(lerpf(drawn[0], drawn[1], u), lerpf(drawn[2], drawn[3], u), v)
				continue
			if is_nan(surface):
				fine[y * row + x] = dry
				continue
			var signed := _curve_near(point).x
			var under := smoothstep(0.3, 0.5, clampf(0.5 + signed, 0.0, 1.0))
			var bed := surface - SHORE_SINK - WATER_BED_DEPTH * smoothstep(0.0, 1.0, clampf(signed * 0.5, 0.0, 1.0))
			fine[y * row + x] = lerpf(dry, bed, under)
	return fine


## The level's roads as curves (563, terrain's side, maps' 563: terrain
## "roads", each {curve: Curves.sample's, kind}), drawn from the curve, not
## its cells: each one's cells (Curves.cells) and for every cell near one
## its nearest sample (_road_near reads the curve from there).
func _read_roads() -> void:
	_road_curves.clear()
	_road_cells.clear()
	_road_near_sample.clear()
	_road_near_also.clear()
	_road_kept.clear()
	if _glimpse:
		return
	for road: Dictionary in _terrain.get("roads", []):
		var curve: Dictionary = road["curve"]
		if (curve["points"] as PackedVector2Array).size() < 2:
			continue
		var index := _road_curves.size()
		for cell: Vector2i in Curves.cells(curve, false):
			_road_cells[cell] = index
		_stamp_near(curve, false, index, _road_near_sample, _road_near_also)
		_road_curves.append({"curve": curve, "closed": false, "kind": str(road.get("kind", "dirt"))})


## Where [param point] is to the nearest road's curve (563, terrain's side):
## x the signed distance, inside its width positive; y along it; z which
## road (-1: none near). As _curve_near.
func _road_near(point: Vector2) -> Vector3:
	return _near_on(_road_curves, _road_near_sample, point, _road_near_also, _road_kept)


## The kind a road's [param cell] is drawn as under the road (563,
## terrain's side): the one most cells round it have that are no road's
## (grass with none), so the road's own kind is drawn from its curve alone,
## not as its cells.
func _road_kind_round(cell: Vector2i, kinds: Dictionary) -> String:
	var counts: Dictionary[String, int] = {}
	for y in range(-1, 2):
		for x in range(-1, 2):
			var near := cell + Vector2i(x, y)
			if near == cell or _road_cells.has(near) or not kinds.has(near):
				continue
			var kind := str(kinds[near])
			if GROUND_CHANNELS.has(kind):
				counts[kind] = counts.get(kind, 0) + 1
	var best := "grass"
	for kind: String in counts:
		if counts[kind] > counts.get(best, 0):
			best = kind
	return best


## The roads' field (563, terrain's side): an RG8 image the shore field's
## size and texels, r a dirt road's and g a stone road's, 0.5 plus the
## signed distance from the road's curve (its edge at a half), the larger
## kept where roads meet. Only the texels near a road are written.
func _road_field(origin: Vector2i, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RG8)
	for cell: Vector2i in _road_near_sample:
		var at := cell - origin
		if at.x < 0 or at.y < 0 or at.x * SHORE_RES >= size.x or at.y * SHORE_RES >= size.y:
			continue
		for v in SHORE_RES:
			for u in SHORE_RES:
				var point := Vector2(cell) + (Vector2(u, v) + Vector2(0.5, 0.5)) / SHORE_RES - Vector2(0.5, 0.5)
				var near := _road_near(point)
				if near.z < 0.0:
					continue
				var value := clampf(0.5 + near.x, 0.0, 1.0)
				var texel := Vector2i(at.x * SHORE_RES + u, at.y * SHORE_RES + v)
				var was := image.get_pixelv(texel)
				if _road_curves[int(near.z)]["kind"] == "stone":
					image.set_pixelv(texel, Color(was.r, maxf(was.g, value), 0.0))
				else:
					image.set_pixelv(texel, Color(maxf(was.r, value), was.g, 0.0))
	return image


## The roads' field (_road_field) at [param point], the larger of its two
## (dirt and stone), read bilinearly as the shader reads it: over a half on
## a road.
func road_at(point: Vector2) -> float:
	if _road_image == null:
		return 0.0
	var texel := (point - Vector2(_mask_origin) + Vector2(0.5, 0.5)) * SHORE_RES - Vector2(0.5, 0.5)
	var low := Vector2i(floori(texel.x), floori(texel.y))
	var f := texel - Vector2(low)
	var size := _road_image.get_size()
	var v := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for k in 4:
		var at := (low + Vector2i(k & 1, k >> 1)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		var here := _road_image.get_pixelv(at)
		v[k] = maxf(here.r, here.g)
	return lerpf(lerpf(v[0], v[1], f.x), lerpf(v[2], v[3], f.x), f.y)


## The cells round a corner, the corner being each one's corner 3 - a.
const SHORE_AROUND: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]


## A shore cell's finer quads into a chunk's arrays (decision 553): its
## (SHORE_RES + 1) squared points, each shared with the cell beside it on an
## edge or corner (keyed in SHORE_RES units, as the whole cells' corners);
## each lit by the cells it touches that draw it at its height
## (_vertex_cells), its relief bytes mixed from its cell's corners'.
func _shore_cell(cell: Vector2i, positions: PackedVector3Array, indices: PackedInt32Array,
		feet: PackedByteArray, tops: PackedByteArray, local: Dictionary, chunk_index: int, byte_start: int,
		pair_cell: PackedInt32Array, pair_vertex: PackedInt32Array) -> void:
	var fine: PackedFloat32Array = _shore_heights[cell]
	var row := SHORE_RES + 1
	var corner_feet := PackedFloat32Array()
	var corner_tops := PackedFloat32Array()
	for c in 4:
		var corner := cell + GROUND_CORNERS[c]
		var level := fine[[0, SHORE_RES, SHORE_RES * row, row * row - 1][c]]
		corner_feet.append(_concavity(corner, level))
		corner_tops.append(_crest(corner, level))
	var made := PackedInt32Array()
	made.resize(row * row)
	for y in row:
		for x in row:
			var level := fine[y * row + x]
			var key := Vector3i(cell.x * SHORE_RES + x, cell.y * SHORE_RES + y, roundi(level * 1000.0))
			var vertex: int = local.get(key, -1)
			if vertex < 0:
				vertex = positions.size()
				local[key] = vertex
				var point := Vector2(cell.x - 0.5 + x / float(SHORE_RES), cell.y - 0.5 + y / float(SHORE_RES))
				positions.append(Vector3(point.x, level, point.y))
				var global := _vertex_chunk.size()
				_vertex_chunk.append(chunk_index)
				_vertex_byte.append(byte_start + vertex * _ground_stride + _ground_custom)
				# The cells it touches: on a corner the four round it, on an
				# edge the two, else its own; each lights it where it draws
				# it at this height.
				var touched: Array[Vector2i] = []
				for dy: int in ([0, -1] if y == 0 else [0, 1] if y == SHORE_RES else [0]):
					for dx: int in ([0, -1] if x == 0 else [0, 1] if x == SHORE_RES else [0]):
						touched.append(cell + Vector2i(dx, dy))
				for k in 4:
					var other: int = -1
					if k < touched.size():
						var near := touched[k]
						other = _grounds.get(near, -1)
						if other >= 0 and (_shore_heights.has(near) or _corners.has(near)) \
								and absf(_height_in(near, point) - level) > Relief.EPSILON:
							other = -1
					_vertex_cells.append(other)
					if other >= 0:
						pair_cell.append(other)
						pair_vertex.append(global)
				var u := x / float(SHORE_RES)
				var v := y / float(SHORE_RES)
				feet.append(roundi(lerpf(lerpf(corner_feet[0], corner_feet[1], u), lerpf(corner_feet[2], corner_feet[3], u), v) * 255.0))
				tops.append(roundi(lerpf(lerpf(corner_tops[0], corner_tops[1], u), lerpf(corner_tops[2], corner_tops[3], u), v) * 255.0))
			made[y * row + x] = vertex
	for y in SHORE_RES:
		for x in SHORE_RES:
			var q := y * row + x
			indices.append_array([made[q], made[q + 1], made[q + row], made[q + 1], made[q + row + 1], made[q + row]])


## What a water cell's bed is: the ground of the land beside it, so its bank
## runs on under the water; out of sight of land, WATER_BED_KIND.
## ([param floor_count]: the indices below it are floor, already placed.)
func _bed_kind(cell: Vector2i, kinds: Dictionary, floor_count: int) -> String:
	for y in range(-1, 2):
		for x in range(-1, 2):
			var near := cell + Vector2i(x, y)
			if _grounds.get(near, floor_count) < floor_count:
				var kind := str(kinds.get(near, "stone"))
				return kind if GROUND_CHANNELS.has(kind) else "stone"
	return WATER_BED_KIND


## The ground's material: ground.gdshader with the kinds texture
## [param bytes] ([param across] by [param down] texels, the first at
## [param origin]) and the kinds' colours.
func _ground_material(bytes: PackedByteArray, across: int, down: int, origin: Vector2i) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GROUND_SHADER
	var image := Image.create_from_data(across, down, false, Image.FORMAT_RGBA8, bytes)
	_kinds_image = image
	_kinds_texture = ImageTexture.create_from_image(image)
	material.set_shader_parameter("kinds", _kinds_texture)
	material.set_shader_parameter("kinds_origin", Vector2(origin))
	material.set_shader_parameter("kinds_size", Vector2(across, down))
	var tiles := Vector4.ONE * 4.0
	for i in GROUND_KINDS.size():
		var kind: String = GROUND_KINDS[i]
		material.set_shader_parameter(kind, ground_colour(kind))
		# Its own texture once ground.<kind> has art (decision 437).
		var own := ground_texture(kind)
		material.set_shader_parameter(kind + "_tex", own)
		material.set_shader_parameter(kind + "_own", own != null)
		if ArtKit.has("ground." + kind):
			tiles[i] = float(ArtKit.spec("ground." + kind).get("tile_m", 4.0))
	material.set_shader_parameter("kind_tiles", tiles)
	material.set_shader_parameter("warm", WARM)
	material.set_shader_parameter("noise_tex", _ground_noise())
	material.set_shader_parameter("water", _water_mask)
	material.set_shader_parameter("shore", _shore_mask)
	# Past pine stands the forest's edge runs into their needles (423), as
	# dark as the floor beyond looks in the canopy's shade (the edge is in
	# the sun).
	material.set_shader_parameter("forest_floor", _forest_floor_colour().darkened(EDGE_NEEDLES_DARK) if PineStands.drawn() else FOREST_FLOOR)
	material.set_shader_parameter("needles_shade", 1.0 - EDGE_NEEDLES_DARK)
	var needles := PineStands.needles_texture() if PineStands.drawn() else null
	material.set_shader_parameter("needles_tex", needles)
	material.set_shader_parameter("needles_own", needles != null)
	if ArtKit.has(PineStands.NEEDLES_SLOT):
		material.set_shader_parameter("needles_tile", float(ArtKit.spec(PineStands.NEEDLES_SLOT).get("tile_m", 4.0)))
	material.set_shader_parameter("sky_floor", _sky_floor)
	material.set_shader_parameter("floors", _floor_mask)
	for floor_set: String in FLOOR_SWATCHES:
		var at: Vector2i = FLOOR_SWATCHES[floor_set]
		material.set_shader_parameter("floor_" + floor_set, swatch(at.x, at.y))
		var own := ArtKit.texture("floor." + floor_set)
		material.set_shader_parameter("floor_%s_tex" % floor_set, own)
		material.set_shader_parameter("floor_%s_own" % floor_set, own != null)
	_ground_shader_material = material
	return material


## The canopy's light shafts (decision 477), over this map's clearings and
## gaps; none where it has no canopy.
func _build_shafts() -> void:
	if _shafts != null:
		_shafts.queue_free()
		_shafts = null
	var canopy: Dictionary = _terrain.get("canopy", {})
	if canopy.is_empty() or not bool(_terrain.get("outdoor", false)):
		return
	_shafts = LightShafts.new()
	add_child(_shafts)
	_shafts.setup(_terrain.get("clearings", []), canopy, _tile_position)


## The noise the ground's shader reads (a texture lookup is far cheaper than
## noise worked out per pixel): made once, on a thread, the same everywhere.
static var _noise_texture: NoiseTexture2D


static func _ground_noise() -> NoiseTexture2D:
	if _noise_texture == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.seed = 1
		noise.frequency = 64.0 / GROUND_NOISE_SIZE
		noise.fractal_type = FastNoiseLite.FRACTAL_NONE
		_noise_texture = NoiseTexture2D.new()
		_noise_texture.width = GROUND_NOISE_SIZE
		_noise_texture.height = GROUND_NOISE_SIZE
		_noise_texture.seamless = true
		_noise_texture.generate_mipmaps = true
		_noise_texture.noise = noise
	return _noise_texture


## How much darker the needles are where the land's ground runs into them
## (sunlit) than on the forest floor beyond (in the canopy's shade).
const EDGE_NEEDLES_DARK := 0.3
## The ground's kinds in the kinds texture's channels' order (r, g, b, a).
const GROUND_KINDS: PackedStringArray = ["grass", "dirt", "stone", "sand"]
## Tests only: a ground kind drawn with this texture while its slot has no
## image of its own.
static var ground_stand_ins: Dictionary[String, Texture2D] = {}


## A ground kind's own texture (ground.<kind>), else the tests' stand-in,
## else null (its procedural look).
static func ground_texture(kind: String) -> Texture2D:
	var own := ArtKit.texture("ground." + kind) if ArtKit.has("ground." + kind) else null
	return own if own != null else ground_stand_ins.get(kind)


## A ground kind's colour (sRGB), from the palette.
static func ground_colour(kind: String) -> Color:
	var at: Vector2i = GROUND_SWATCHES.get(kind, GROUND_SWATCHES["stone"])
	return swatch(at.x, at.y)


## Swatch [param column] of row [param row] of art-kit's palette (sRGB):
## read from art/kit/palette.png (8 swatches across, a row each kind), so Jeff's repaints show;
## the style guide's colours if it cannot be read.
static var _palette: Image


static func swatch(row: int, column: int) -> Color:
	if _palette == null:
		var texture := load(PALETTE_IMAGE) as Texture2D if ResourceLoader.exists(PALETTE_IMAGE) else null
		_palette = texture.get_image() if texture != null else null
		if _palette != null and _palette.is_compressed():
			_palette.decompress()
		if _palette == null or _palette.get_width() < 8:
			_palette = Image.create(8, PALETTE_FALLBACK.size() / 8, false, Image.FORMAT_RGB8)
			for y in PALETTE_FALLBACK.size() / 8:
				for x in 8:
					_palette.set_pixel(x, y, Color(PALETTE_FALLBACK[y * 8 + x]))
	var size := _palette.get_width() / 8
	return _palette.get_pixel(column * size + size / 2, row * size + size / 2)


## What a ground cell of [param kind] is drawn as, shaded [param bright]
## (1: fully lit) and warmed [param warm], before the shader's noise (sRGB).
func _ground_colour(kind: String, bright: float, warm: float) -> Color:
	return (ground_colour(kind) * bright).lerp(WARM, warm)


## Water: one surface a body of water (its cells, joined side to side),
## just above the ground, over its cells and the land round them at its
## level, so water.gdshader can draw its shore off the cells' edges (by
## the water mask, a texel a cell, read through noise, never more than
## about a third of a cell from the true edge) with foam on the land side.
## The bed under it is the ground's (_build_ground).
func _build_water() -> void:
	# A stream's fords and the water under its bridges are its water too.
	var water: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _terrain.get("water", []):
		if not _dry_water.has(cell):
			water[cell] = true
	for cell: Vector2i in _fords:
		water[cell] = true
	for cell: Vector2i in _bed_levels:
		water[cell] = true
	# A stream's own cells are its ribbon's (decision 557).
	for cell: Vector2i in _stream_cells:
		water.erase(cell)
	_build_ribbons()
	for w in _curve_waters.size():
		_build_curve_ribbon(w)
	_build_mists()
	if water.is_empty():
		return
	var material := _water_material()
	var seen: Dictionary[Vector2i, bool] = {}
	var sides: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for start: Vector2i in water:
		if seen.has(start):
			continue
		seen[start] = true
		var level: float = _bed_levels.get(start, _elevation(start))
		var body: Array[Vector2i] = [start]
		var head := 0
		while head < body.size():
			var cell := body[head]
			head += 1
			level = maxf(level, _bed_levels.get(cell, _elevation(cell)))
			for side in sides:
				var next := cell + side
				if water.has(next) and not seen.has(next):
					seen[next] = true
					body.append(next)
		# Its cells, and the land beside them at its level that no wall
		# parts from them: water never shows past a wall. On a relief the
		# land beside it at any height (decision 553): its bank dips under
		# the water where the shore field rounds into it, and stands over
		# the water elsewhere, hiding it.
		var covered: Dictionary[Vector2i, bool] = {}
		# Built water (decision 595) draws its own cells alone: a basin's
		# edge is its cells' edge, crisp.
		var built := body.all(func(cell: Vector2i) -> bool: return _built_water.has(cell))
		for cell in body:
			covered[cell] = true
			if built:
				continue
			for y in range(-1, 2):
				for x in range(-1, 2):
					var near := cell + Vector2i(x, y)
					if covered.has(near) or water.has(near) or _stream_cells.has(near) or not _grounds.has(near) \
							or (not _relief_given and absf(_elevation(near) - level) > Relief.EPSILON):
						continue
					var walled := false
					for step: Vector2i in [Vector2i(x, 0), Vector2i(0, y)]:
						if step != Vector2i.ZERO:
							walled = walled or _edge_kind(cell, step) == Terrain.Edge.WALL \
									or _edge_kind(near, -step) == Terrain.Edge.WALL
					if not walled:
						covered[near] = true
		var top := level + WATER_LIFT
		var positions := PackedVector3Array()
		var indices := PackedInt32Array()
		for cell: Vector2i in covered:
			var first := positions.size()
			# On a relief the surface follows the water's cells (a stream
			# slopes down its path, decision 525); else the body's level. A
			# bank's corner with no water round it takes the mean of its
			# cell's that have.
			var ys := PackedFloat32Array([top, top, top, top])
			if _relief_given:
				var sum := 0.0
				var count := 0
				for c in 4:
					ys[c] = _water_corner(cell + GROUND_CORNERS[c])
					if ys[c] < INF:
						sum += ys[c]
						count += 1
				for c in 4:
					if ys[c] == INF:
						ys[c] = sum / count if count > 0 else level
					ys[c] += WATER_LIFT
			for c in 4:
				var corner := GROUND_CORNERS[c]
				positions.append(Vector3(cell.x + corner.x - 0.5, ys[c], cell.y + corner.y - 0.5))
			indices.append_array([first, first + 1, first + 2, first + 1, first + 3, first + 2])
		var normals := PackedVector3Array()
		normals.resize(positions.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var drawn := MeshInstance3D.new()
		drawn.name = "Water_%d_%d" % [start.x, start.y]
		drawn.mesh = mesh
		drawn.material_override = material
		if built:
			var still := _water_material()
			still.set_shader_parameter("built", true)
			drawn.material_override = still
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_room.add_child(drawn)
		_water_bodies.append(drawn)


## The streams' cells as the ground and water draw them (decision 505,
## terrain's side): the fords, and each bridged cell's bed level, the lowest
## of the water and fords round its bridge (the sim has the deck's).
func _measure_streams() -> void:
	_fords.clear()
	for cell: Vector2i in _terrain.get("fords", []):
		_fords[cell] = true
	var bridged: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _terrain.get("bridged", []):
		bridged[cell] = true
	if bridged.is_empty():
		return
	var wet: Dictionary[Vector2i, bool] = _fords.duplicate()
	for cell: Vector2i in _terrain.get("water", []):
		wet[cell] = true
	for building: Dictionary in _terrain.get("buildings", []):
		if not str(building.get("slot", "")) in Level.SPANS_WATER or not building.has("rect"):
			continue
		var rect: Rect2i = building["rect"]
		var level := INF
		for y in range(rect.position.y - 1, rect.end.y + 1):
			for x in range(rect.position.x - 1, rect.end.x + 1):
				if wet.has(Vector2i(x, y)):
					level = minf(level, _elevation(Vector2i(x, y)))
		for cell in Level.rect_cells(rect):
			if bridged.has(cell):
				_bed_levels[cell] = level if level < INF else _elevation(cell)


## The shore field (decision 553): an L8 image of [param size] cells from
## cell [param origin], SHORE_RES texels a cell (a texel's middle at cell
## origin + (texel + 0.5) / SHORE_RES - 0.5), 255 in the water, 0 on land, the
## water's edge where it is a half. The [param wet] cells, a texel a cell,
## scaled up bilinearly (a box a cell wide over them), so a straight run of
## cells keeps its edge, a corner rounds and a lone cell is near a disc, the
## edge no further than 0.29 of a cell off its cells' (SHORE_BOUND); but a stream's one-wide cells (its two
## sides dry) left out of that and drawn along its path instead, a
## Catmull-Rom through their middles wandering STREAM_WIND either side
## (a noise along it), STREAM_HALF wide each side: it winds within them.
static func shore_image(streams: Array, wet: Dictionary, origin: Vector2i, size: Vector2i) -> Image:
	var narrow: Dictionary[Vector2i, bool] = {}
	for stream: Dictionary in streams:
		var path: Array = stream.get("path", [])
		for i in path.size():
			var way: Vector2i = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).sign()
			var side := Vector2i(-way.y, way.x)
			if way != Vector2i.ZERO and not wet.has(path[i] + side) and not wet.has(path[i] - side):
				narrow[path[i]] = true
	var cells := PackedByteArray()
	cells.resize(size.x * size.y)
	for cell: Vector2i in wet:
		var at := cell - origin
		if not narrow.has(cell) and at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y:
			cells[at.y * size.x + at.x] = 255
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_L8, cells)
	var across := size.x * SHORE_RES
	var down := size.y * SHORE_RES
	image.resize(across, down, Image.INTERPOLATE_BILINEAR)
	var bytes := image.get_data()
	var wander := FastNoiseLite.new()
	wander.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	wander.seed = 553
	wander.frequency = 0.15
	wander.fractal_type = FastNoiseLite.FRACTAL_NONE
	var reach := ceili(STREAM_HALF * SHORE_RES) + 1
	for stream: Dictionary in streams:
		var path: Array = stream.get("path", [])
		var along := 0.0
		for i in path.size() - 1:
			var a := Vector2(path[maxi(i - 1, 0)])
			var b := Vector2(path[i])
			var c := Vector2(path[i + 1])
			var d := Vector2(path[mini(i + 2, path.size() - 1)])
			for k in SHORE_RES * 2:
				var t := k / float(SHORE_RES * 2)
				var point := 0.5 * (2.0 * b + (c - a) * t + (2.0 * a - 5.0 * b + 4.0 * c - d) * t * t
						+ (3.0 * b - a - 3.0 * c + d) * t * t * t)
				var tangent := (0.5 * ((c - a) + 2.0 * (2.0 * a - 5.0 * b + 4.0 * c - d) * t
						+ 3.0 * (3.0 * b - a - 3.0 * c + d) * t * t)).normalized()
				point += Vector2(-tangent.y, tangent.x) * wander.get_noise_1d(along) * STREAM_WIND
				along += b.distance_to(c) / (SHORE_RES * 2)
				# The texels round it, in texel units.
				var middle := (point - Vector2(origin) + Vector2(0.5, 0.5)) * SHORE_RES - Vector2(0.5, 0.5)
				for y in range(floori(middle.y) - reach, floori(middle.y) + reach + 2):
					for x in range(floori(middle.x) - reach, floori(middle.x) + reach + 2):
						if x < 0 or y < 0 or x >= across or y >= down:
							continue
						var off := Vector2(x, y).distance_to(middle) / SHORE_RES
						var cover := roundi(clampf((STREAM_HALF - off) * SHORE_RES + 0.5, 0.0, 1.0) * 255.0)
						if cover > bytes[y * across + x]:
							bytes[y * across + x] = cover
	# The bound: a texel further than SHORE_BOUND from a cell of the other
	# kind (box distance) is its own cell's, water or land, wherever a
	# stream's winding or its meeting the water left it.
	var near_water: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in wet:
		for y in range(-1, 2):
			for x in range(-1, 2):
				near_water[cell + Vector2i(x, y)] = true
	for cell: Vector2i in near_water:
		var at := cell - origin
		if at.x < 0 or at.y < 0 or at.x >= size.x or at.y >= size.y:
			continue
		var water := wet.has(cell)
		for v in SHORE_RES:
			for u in SHORE_RES:
				var point := (Vector2(u, v) + Vector2(0.5, 0.5)) / SHORE_RES - Vector2(0.5, 0.5)
				var far := INF
				for y in range(-1, 2):
					for x in range(-1, 2):
						if wet.has(cell + Vector2i(x, y)) != water:
							var gap := (point - Vector2(x, y)).abs() - Vector2(0.5, 0.5)
							far = minf(far, maxf(maxf(gap.x, gap.y), 0.0))
				if far <= SHORE_BOUND:
					continue
				var texel := (at.y * SHORE_RES + v) * across + at.x * SHORE_RES + u
				bytes[texel] = maxi(bytes[texel], 141) if water else mini(bytes[texel], 114)
	return Image.create_from_data(across, down, false, Image.FORMAT_L8, bytes)


## The shore field (shore_image) at [param point] (cells), 0 on land to 1 in
## the water, the edge at a half; 0 off it.
func shore_at(point: Vector2) -> float:
	if _shore_image == null:
		return 0.0
	var texel := (point - Vector2(_mask_origin) + Vector2(0.5, 0.5)) * SHORE_RES - Vector2(0.5, 0.5)
	var low := Vector2i(floori(texel.x), floori(texel.y))
	var f := texel - Vector2(low)
	var size := _shore_image.get_size()
	var v := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for k in 4:
		var at := (low + Vector2i(k & 1, k >> 1)).clamp(Vector2i.ZERO, size - Vector2i.ONE)
		v[k] = _shore_image.get_pixelv(at).r
	return lerpf(lerpf(v[0], v[1], f.x), lerpf(v[2], v[3], f.x), f.y)


## A bridge (decision 505, terrain's side): art-kit's BRIDGE_DECK on each
## of its cells (its variant by the cell), BRIDGE_RAIL along its outer long
## edges and BRIDGE_END onto the bank past each end, at the deck's height
## (the sim's) BRIDGE_LIFT up, the water running on under it. A MultiMesh
## for each piece's variant and mesh, named piece_variant_mesh.
func _add_bridge(building: Dictionary) -> void:
	var rect: Rect2i = building["rect"]
	var facing: Vector2i = building["facing"]
	var along := Vector2i(absi(facing.x), absi(facing.y))
	var across := Vector2i(along.y, along.x)
	var top := _elevation(rect.position) + BRIDGE_LIFT
	var pieces: Dictionary[String, Array] = {}
	for cell in Level.rect_cells(rect):
		var deck := "%s/%d" % [BRIDGE_DECK, 1 + posmod(hash(cell), maxi(ArtKit.variant_count(BRIDGE_DECK), 1))]
		pieces.get_or_add(deck, []).append(Transform3D(_turned_to(along), Vector3(cell.x, top, cell.y)))
		for side: Vector2i in [across, -across]:
			if not rect.has_point(cell + side):
				var edge := Vector2(cell) + Vector2(side) * 0.5
				pieces.get_or_add(BRIDGE_RAIL + "/1", []).append(Transform3D(_turned_to(along), Vector3(edge.x, top, edge.y)))
		for end: Vector2i in [along, -along]:
			if not rect.has_point(cell + end):
				var edge := Vector2(cell) + Vector2(end) * 0.5
				pieces.get_or_add(BRIDGE_END + "/1", []).append(Transform3D(_turned_to(end), Vector3(edge.x, top, edge.y)))
	var bridge := Node3D.new()
	bridge.name = "Bridge_%d_%d" % [rect.position.x, rect.position.y]
	for key: String in pieces:
		var slot := key.get_slice("/", 0)
		var made := ArtKit.instance(slot, int(key.get_slice("/", 1)))
		var meshes := made.find_children("*", "MeshInstance3D", true, false)
		for m in meshes.size():
			var drawn := meshes[m] as MeshInstance3D
			var local := ArtKit._place_in(drawn, made)
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = drawn.mesh
			multimesh.instance_count = pieces[key].size()
			for i in pieces[key].size():
				multimesh.set_instance_transform(i, pieces[key][i] * local)
			var many := MultiMeshInstance3D.new()
			many.name = "%s_%s_%d" % [slot.get_slice(".", 2), key.get_slice("/", 1), m]
			many.multimesh = multimesh
			many.material_override = drawn.material_override
			bridge.add_child(many)
		made.free()
	_room.add_child(bridge)


## Whether the edge [param key] has a rock on a side (Level walls a rock
## round as it does the void; the view draws the rock instead).
func _rock_edge(key: Vector3i) -> bool:
	return Terrain.edge_cells(key).any(func(cell: Vector2i) -> bool: return _rocks.has(cell))


## The barrow's niches by their wall edge (608, terrain's side): terrain
## "niches", each {cell (the room's floor cell), out (the step out of the
## wall into the room), edge, kind, variant}; an older level's without edge
## or kind, the edge behind its cell and kind "a".
func _read_niches() -> void:
	_niche_at.clear()
	_hidden_niches.clear()
	for niche: Dictionary in _terrain.get("niches", []):
		var cell: Vector2i = niche["cell"]
		var out: Vector2i = niche["out"]
		var edge: Vector3i = niche.get("edge", Terrain.edge_key(cell, -out))
		_niche_at[edge] = {"cell": cell, "out": out, "kind": str(niche.get("kind", "a")), "variant": int(niche.get("variant", 1))}


## Each of terrain "decor"'s entries (647) as its piece, once its slot is
## drawn (no grey box): see DECOR_SLOT.
func _add_decor() -> void:
	for entry: Dictionary in _terrain.get("decor", []):
		var kind := str(entry["kind"])
		var slot := DECOR_SLOT % kind
		if not _deadwood_drawn(slot):
			continue
		var cell: Vector2i = entry["cell"]
		var out: Vector2i = entry["out"]
		# A variant art-kit has not made yet is its first (variant_count).
		var piece := ArtKit.instance(slot, clampi(int(entry.get("variant", 1)), 1, maxi(1, ArtKit.variant_count(slot))))
		piece.name = "Decor_%d_%d_%s_%d_%d" % [cell.x, cell.y, kind, out.x, out.y]
		var at := Vector2(cell)
		match str(Level.DECOR_KINDS.get(kind, {}).get("sits", "edge")):
			"flat":
				# Its yaw rolled by the cell, or (658: a faced piece, a fallen
				# guard) its front, +z, turned the way its step names.
				piece.rotation.y = _roll(cell, 70) * TAU if out == Vector2i.ZERO else atan2(float(out.x), float(out.y))
			"corner":
				piece.rotation.y = _yaw_of(Vector2(out)) - _yaw_of(Vector2(DECOR_CORNER))
			_:
				# On its edge (a wall's foot, a niche's mouth, or any edge out
				# of doors, 658), the cell on +x: +x along -out, z along the edge.
				at += Vector2(out) * 0.5
				piece.rotation.y = _yaw_of(-Vector2(out))
		piece.position = Vector3(at.x, _height_in(cell, at), at.y)
		_room.add_child(piece)


## The turn about y that takes +x to [param way] (x, z on the ground).
static func _yaw_of(way: Vector2) -> float:
	return atan2(-way.y, way.x)


## The hidden niche's door edge (608, terrain's side): no doorway, no leaf,
## but the wall: wall.crypt.cracked while its Door is shut, wall.crypt.
## niche_open once it opens (_sync_doors), +x toward the room; and its
## draft while shut (608 amended, environment's side, _make_draft).
func _add_hidden_niche(key: Vector3i) -> void:
	var niche: Dictionary = _niche_at[key]
	var out: Vector2i = niche["out"]
	var holder := Node3D.new()
	holder.name = "HiddenNiche_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	holder.position = _edge_midpoint(key) + Vector3(0.0, _edge_base(key), 0.0)
	holder.rotation.y = atan2(-float(out.y), float(out.x))
	var shut := ArtKit.instance(NICHE_CRACKED)
	shut.name = "Cracked"
	holder.add_child(shut)
	var found := ArtKit.instance(NICHE_OPEN)
	found.name = "Open"
	found.visible = false
	holder.add_child(found)
	var draft := _make_draft()
	holder.add_child(draft)
	_room.add_child(holder)
	_walls[key] = holder
	_hidden_niches[key] = [shut, found, draft]
	_doors_due[key] = true
	# Its footprints (608 amended): on the entry cell, going to the wall
	# (+x along -out) and one back, on the floor; there whether found or not.
	if ArtKit.has(NICHE_FOOTPRINTS):
		var cell: Vector2i = niche["cell"]
		var prints := ArtKit.instance(NICHE_FOOTPRINTS)
		prints.name = "Footprints_%d_%d" % [cell.x, cell.y]
		prints.position = Vector3(cell.x, _height_in(cell, Vector2(cell)), cell.y)
		prints.rotation.y = atan2(float(out.y), -float(out.x))
		_room.add_child(prints)


## The hidden niche on [param key] shut or [param opened]: the cracked wall
## and its draft, or the open niche (its last puffs fade as they go).
func _show_hidden_niche(key: Vector3i, opened: bool) -> void:
	(_hidden_niches[key][0] as Node3D).visible = not opened
	(_hidden_niches[key][1] as Node3D).visible = opened
	(_hidden_niches[key][2] as GPUParticles3D).emitting = not opened


## The draft out of a hidden niche (608 amended, environment's side): in
## its holder's frame (+x into the room, z along the wall), faint puffs
## from along the cracked wall's foot drifting low into the room, sinking a
## little, swelling and fading (DRAFT_*). Lit as the mists are.
func _make_draft() -> GPUParticles3D:
	var draft := GPUParticles3D.new()
	draft.name = "Draft"
	draft.amount = DRAFT_PUFFS
	draft.lifetime = DRAFT_SECONDS
	draft.preprocess = DRAFT_SECONDS
	draft.local_coords = true
	draft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	draft.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD
	draft.visibility_aabb = AABB(Vector3(-0.5, -0.5, -1.0), Vector3(2.5, 1.5, 2.0))
	draft.position = Vector3(0.1, DRAFT_LOW * 0.5, 0.0)
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(0.05, DRAFT_LOW * 0.4, 0.4)
	process.direction = Vector3(1.0, -0.08, 0.0)
	process.spread = 12.0
	process.initial_velocity_min = DRAFT_SPEED.x
	process.initial_velocity_max = DRAFT_SPEED.y
	process.gravity = Vector3(0.0, -0.01, 0.0)
	process.damping_min = 0.02
	process.damping_max = 0.05
	# A slow waver across the wall's run.
	process.turbulence_enabled = true
	process.turbulence_noise_strength = 0.15
	process.turbulence_noise_speed_random = 0.1
	process.turbulence_influence_min = 0.02
	process.turbulence_influence_max = 0.05
	process.scale_min = 0.6
	process.scale_max = 1.0
	var swell := Curve.new()
	swell.add_point(Vector2(0.0, 0.5))
	swell.add_point(Vector2(1.0, 1.2))
	var swell_texture := CurveTexture.new()
	swell_texture.curve = swell
	process.scale_curve = swell_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	fade.add_point(0.3, Color(1.0, 1.0, 1.0, DRAFT_ALPHA))
	var fade_texture := GradientTexture1D.new()
	fade_texture.gradient = fade
	process.color_ramp = fade_texture
	draft.process_material = process
	draft.draw_pass_1 = _soft_puff(DRAFT_SIZE)
	return draft


## A soft round puff [param size] across for a particle pass: lit as the
## scene is (unshaded it glowed at dusk), soft all round, coloured by the
## particle's colour ramp.
static func _soft_puff(size: float) -> QuadMesh:
	var puff := QuadMesh.new()
	puff.size = Vector2(size, size)
	var material := StandardMaterial3D.new()
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material.roughness = 1.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.vertex_color_use_as_albedo = true
	material.proximity_fade_enabled = true
	material.proximity_fade_distance = 0.6
	var soft := Gradient.new()
	soft.set_color(0, Color(0.92, 0.95, 0.97, 1.0))
	soft.set_color(1, Color(0.92, 0.95, 0.97, 0.0))
	var round_texture := GradientTexture2D.new()
	round_texture.gradient = soft
	round_texture.fill = GradientTexture2D.FILL_RADIAL
	round_texture.fill_from = Vector2(0.5, 0.5)
	round_texture.fill_to = Vector2(0.5, 0.0)
	round_texture.width = 64
	round_texture.height = 64
	material.albedo_texture = round_texture
	puff.material = material
	return puff


## The rocks (terrain "rocks", decision 513, terrain's side): rock_plan's
## large rocks over their clumps and small ones on the rest, each turned,
## sized and sunk by its cell, one MultiMesh a slot, variant and mesh under
## "Rocks", casting shadows.
func _add_rocks() -> void:
	if _rocks.is_empty():
		return
	var plan := rock_plan(_rocks)
	var pieces: Dictionary[String, Array] = {}
	for cell: Vector2i in plan["small"]:
		var size := lerpf(ROCK_SMALL_SIZES.x, ROCK_SMALL_SIZES.y, _roll(cell, 131))
		var sink := lerpf(ROCK_SINK.x, ROCK_SINK.y, _roll(cell, 132))
		var basis := Basis(Vector3.UP, _roll(cell, 133) * TAU).scaled(Vector3.ONE * size)
		pieces.get_or_add(ROCK_SMALL + "/1", []).append(Transform3D(basis, Vector3(cell.x, _height_in(cell, Vector2(cell)) - sink, cell.y)))
	for cell: Vector2i in plan["large"]:
		var size := lerpf(ROCK_LARGE_SIZES.x, ROCK_LARGE_SIZES.y, _roll(cell, 134))
		var sink := lerpf(ROCK_SINK.x, ROCK_SINK.y, _roll(cell, 135))
		var basis := Basis(Vector3.UP, _roll(cell, 136) * TAU).scaled(Vector3.ONE * size)
		# On the lowest of its four cells, so no side stands in the air.
		var low := INF
		for step: Vector2i in [Vector2i.ZERO, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.ONE]:
			low = minf(low, _height_in(cell + step, Vector2(cell + step)))
		var variant := 1 + posmod(hash(cell), maxi(ArtKit.variant_count(ROCK_LARGE), 1))
		pieces.get_or_add("%s/%d" % [ROCK_LARGE, variant], []).append(Transform3D(basis, Vector3(cell.x + 0.5, low - sink, cell.y + 0.5)))
	var rocks := Node3D.new()
	rocks.name = "Rocks"
	for key: String in pieces:
		var slot := key.get_slice("/", 0)
		var made := ArtKit.instance(slot, int(key.get_slice("/", 1)))
		var meshes := made.find_children("*", "MeshInstance3D", true, false)
		for m in meshes.size():
			var drawn := meshes[m] as MeshInstance3D
			var local := ArtKit._place_in(drawn, made)
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = drawn.mesh
			multimesh.instance_count = pieces[key].size()
			for i in pieces[key].size():
				multimesh.set_instance_transform(i, pieces[key][i] * local)
			var many := MultiMeshInstance3D.new()
			many.name = "%s_%s_%d" % [slot.get_slice(".", 1), key.get_slice("/", 1), m]
			many.multimesh = multimesh
			many.material_override = drawn.material_override
			many.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			rocks.add_child(many)
		made.free()
	_room.add_child(rocks)


## Where [param rocks]' (cell -> true) rocks go: {large: the top-left cell
## of each 2x2 clump, taken in reading order, no cell in two; small: every
## rock cell left}.
static func rock_plan(rocks: Dictionary) -> Dictionary:
	var cells: Array = rocks.keys()
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or a.y == b.y and a.x < b.x)
	var used: Dictionary[Vector2i, bool] = {}
	var large: Array[Vector2i] = []
	var small: Array[Vector2i] = []
	for cell: Vector2i in cells:
		if used.has(cell):
			continue
		var clump: Array[Vector2i] = [cell, cell + Vector2i.RIGHT, cell + Vector2i.DOWN, cell + Vector2i.ONE]
		if clump.all(func(at: Vector2i) -> bool: return rocks.has(at) and not used.has(at)):
			large.append(cell)
			for at in clump:
				used[at] = true
	for cell: Vector2i in cells:
		if not used.has(cell):
			small.append(cell)
	return {"large": large, "small": small}


## A basis turning a piece's +Z toward [param direction] (a step on the grid).
static func _turned_to(direction: Vector2i) -> Basis:
	return Basis(Vector3.UP, atan2(float(direction.x), float(direction.y)))

## [param canopy] (cell -> cover) as an R8 texture of [param size] texels
## from cell [param origin]; null for none.
static func canopy_mask(canopy: Dictionary, origin: Vector2i, size: Vector2i) -> ImageTexture:
	if canopy.is_empty():
		return null
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y)
	for cell: Vector2i in canopy:
		var at := cell - origin
		if at.x >= 0 and at.y >= 0 and at.x < size.x and at.y < size.y:
			bytes[at.y * size.x + at.x] = roundi(clampf(canopy[cell], 0.0, 1.0) * 255.0)
	return ImageTexture.create_from_image(Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, bytes))


## What stands on [param cell]'s side toward [param direction].
func _edge_kind(cell: Vector2i, direction: Vector2i) -> int:
	return _terrain["edges"].get(Terrain.edge_key(cell, direction), Terrain.Edge.OPEN)


## The water's material, for this map's water mask.
func _water_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = WATER_SHADER
	material.render_priority = WATER_PRIORITY
	material.set_shader_parameter("water", _water_mask)
	material.set_shader_parameter("mask_origin", Vector2(_mask_origin))
	material.set_shader_parameter("mask_size", Vector2(_mask_size))
	material.set_shader_parameter("noise_tex", _ground_noise())
	material.set_shader_parameter("shallow", swatch(WATER_SHALLOW.x, WATER_SHALLOW.y))
	material.set_shader_parameter("deep", swatch(WATER_DEEP.x, WATER_DEEP.y))
	material.set_shader_parameter("foam", swatch(WATER_FOAM.x, WATER_FOAM.y))
	material.set_shader_parameter("shore", _shore_mask)
	material.set_shader_parameter("depth_tex", _depth_mask)
	return material


## Cliff faces: wherever a cell's edge stands above its neighbour's (or
## above the void or water past it), rock from the one down to the other,
## and nothing where a ramp joins them. A face is a strip of small facets
## jittered by where each point is, the same for every strip that shares
## it (so faces meet without gaps) and still at the top and bottom (so they
## meet the ground), one mesh a chunk.
func _add_cliffs() -> void:
	var floor_cells: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _terrain["floor"]:
		if not _bed_levels.has(cell):
			floor_cells[cell] = true
	# A rock on a lip stands on the raised ground: its face drawn as the
	# ground's.
	floor_cells.merge(_rocks)
	var water: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in _terrain.get("water", []):
		water[cell] = true
	for cell: Vector2i in _bed_levels:
		water[cell] = true
	# Each side: the corners on it (GROUND_CORNERS indices), as the cell
	# and as its neighbour has them.
	var sides := {
		Vector2i(1, 0): [[1, 3], [0, 2]], Vector2i(-1, 0): [[2, 0], [3, 1]],
		Vector2i(0, 1): [[3, 2], [1, 0]], Vector2i(0, -1): [[0, 1], [2, 3]],
	}
	var faces: Dictionary[Vector2i, Array] = {}
	_cliff_edges.clear()
	for cell: Vector2i in floor_cells:
		var own := _corner_heights(cell)
		if maxf(maxf(own[0], own[1]), maxf(own[2], own[3])) <= _ground_bottom + Relief.EPSILON:
			continue
		for direction: Vector2i in sides:
			var next := cell + direction
			var theirs := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
			if floor_cells.has(next):
				theirs = _corner_heights(next)
			elif water.has(next) and _relief_given:
				theirs = _corner_heights(next)  # Down to the bed (decision 525).
			elif water.has(next):
				var level: float = _bed_levels.get(next, _elevation(next))
				theirs = PackedFloat32Array([level, level, level, level])
			var mine: Array = sides[direction][0]
			var their: Array = sides[direction][1]
			var top := Vector2(own[mine[0]], own[mine[1]])
			var bottom := Vector2(minf(own[mine[0]], theirs[their[0]]), minf(own[mine[1]], theirs[their[1]]))
			if (top - bottom).length() <= Relief.EPSILON:
				continue
			_cliff_edges.append([cell, direction])
			# A dais's edge indoors: art-kit's piece for the face (580 step 3).
			if floor_cells.has(next) and _is_dais(cell, next) and absf(top.x - bottom.x - LEVEL_RISE) <= Relief.EPSILON \
					and absf(top.y - bottom.y - LEVEL_RISE) <= Relief.EPSILON:
				_add_dais_edge(cell, direction, bottom.x)
				continue
			# A ledge's face along its curve stands for this one (585).
			if _ledge_covers(cell, next):
				continue
			var chunk := Vector2i(floori(cell.x / float(FLOOR_CHUNK)), floori(cell.y / float(FLOOR_CHUNK)))
			if not faces.has(chunk):
				faces[chunk] = [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
			var from := Vector2(cell + GROUND_CORNERS[mine[0]]) - Vector2(0.5, 0.5)
			var to := Vector2(cell + GROUND_CORNERS[mine[1]]) - Vector2(0.5, 0.5)
			_cliff_strip(faces[chunk], from, to, top, bottom, Vector3(direction.x, 0.0, direction.y))
	_add_ledge_faces(faces)
	# Their vertex colours, rough, both sides, under the sky's light as the
	# ground (513 amended); seen through where they hide the player
	# (cliff.gdshader, decision 549).
	var material := ShaderMaterial.new()
	material.shader = CLIFF_SHADER
	material.set_shader_parameter("sky_floor", cliff_sky(_sky_floor))
	_cliff_material = material
	for chunk: Vector2i in faces:
		# A rim with nothing to drop from (565: the wilds' relief has some).
		if (faces[chunk][0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = faces[chunk][0]
		arrays[Mesh.ARRAY_NORMAL] = faces[chunk][1]
		arrays[Mesh.ARRAY_COLOR] = faces[chunk][2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var drawn := MeshInstance3D.new()
		drawn.name = "Cliffs_%d_%d" % [chunk.x, chunk.y]
		drawn.mesh = mesh
		drawn.material_override = material
		_room.add_child(drawn)


## Whether the edge from [param high] down to [param low] is a dais's
## (580 step 3): indoors on built levels (no relief given: a relief's
## steps are the land's rock, the sample's), both of them land, [param high]
## exactly one level up, and art-kit's two pieces drawn (else a cliff).
func _is_dais(high: Vector2i, low: Vector2i) -> bool:
	return not _outdoor and not _relief_given and _land.has(high) and _land.has(low) \
			and absf(_elevation(high) - _elevation(low) - LEVEL_RISE) <= Relief.EPSILON \
			and _deadwood_drawn(DAIS_EDGE) and _deadwood_drawn(DAIS_STEPS)


## A dais's edge on [param cell]'s side toward [param direction] (the low
## floor, at [param floor_at]): dais.steps where that cell is a stair up
## onto it, else dais.edge; turned so its +x points down off the dais.
func _add_dais_edge(cell: Vector2i, direction: Vector2i, floor_at: float) -> void:
	var low := cell + direction
	var steps: bool = _dais_stairs.get(low, Vector2i.ZERO) == -direction
	var slot := DAIS_STEPS if steps else DAIS_EDGE
	var piece := ArtKit.instance(slot)
	piece.set_meta(&"slot", slot)
	piece.name = "Dais_%d_%d_%d_%d" % [cell.x, cell.y, direction.x, direction.y]
	var middle := Vector2(cell) + Vector2(direction) * 0.5
	piece.position = Vector3(middle.x, floor_at, middle.y)
	piece.rotation.y = atan2(-float(direction.y), float(direction.x))
	_room.add_child(piece)


## One cliff face into [param into] ([positions, normals, colours]): along
## the edge [param from] to [param to], from [param top] (heights at each
## end) down to [param bottom], facing [param out], [param across] columns.
func _cliff_strip(into: Array, from: Vector2, to: Vector2, top: Vector2, bottom: Vector2, out: Vector3,
		across := CLIFF_ACROSS) -> void:
	var drop := maxf(top.x - bottom.x, top.y - bottom.y)
	var rows := maxi(1, ceili(drop / CLIFF_ROW))
	var points: Array[PackedVector3Array] = []
	for j in rows + 1:
		var row := PackedVector3Array()
		var v := j / float(rows)
		for i in across + 1:
			var u := i / float(across)
			var at := from.lerp(to, u)
			var low := lerpf(bottom.x, bottom.y, u)
			var high := lerpf(top.x, top.y, u)
			var point := Vector3(at.x, lerpf(low, high, v), at.y)
			# Pushed less where the face is low (a wedge's thin end: none).
			if j > 0 and j < rows:
				point += _cliff_jitter(point) * minf((high - low) / LEVEL_RISE, 1.0)
			row.append(point)
		points.append(row)
	# Taken out of [param into] while they grow: a packed array still held
	# there too is copied whole by its first append (copy on write), so a
	# chunk's faces cost the square of its size (the hills' rebuild, about
	# 150 ms).
	var positions: PackedVector3Array = into[0]
	var normals: PackedVector3Array = into[1]
	var colours: PackedColorArray = into[2]
	into[0] = PackedVector3Array()
	into[1] = PackedVector3Array()
	into[2] = PackedColorArray()
	var rock := swatch(CLIFF_ROCK.x, CLIFF_ROCK.y)
	for j in rows:
		for i in across:
			var a := points[j][i]
			var b := points[j][i + 1]
			var c := points[j + 1][i]
			var d := points[j + 1][i + 1]
			for t in 2:
				var p0 := a if t == 0 else b
				var p1 := b if t == 0 else d
				var p2 := c
				var normal := (p1 - p0).cross(p2 - p0)
				if normal.length_squared() < 0.000001:
					continue  # A wedge's point.
				normal = normal.normalized()
				if normal.dot(out) < 0.0:
					normal = -normal
				var middle := (p0 + p1 + p2) / 3.0
				var shade := lerpf(0.8, 1.15, _roll(Vector2i(roundi(middle.x * 16.0), roundi(middle.z * 16.0)), roundi(middle.y * 16.0)))
				# Darker toward the foot.
				shade *= lerpf(0.72, 1.0, clampf(inverse_lerp(minf(bottom.x, bottom.y), maxf(top.x, top.y), middle.y), 0.0, 1.0))
				var colour := Color(rock * shade, 1.0)
				positions.append(p0)
				positions.append(p1)
				positions.append(p2)
				normals.append(normal)
				normals.append(normal)
				normals.append(normal)
				colours.append(colour)
				colours.append(colour)
				colours.append(colour)
	into[0] = positions
	into[1] = normals
	into[2] = colours


## How far a cliff's point is pushed: by where it is alone, so every face
## that has the point pushes it alike.
static func _cliff_jitter(point: Vector3) -> Vector3:
	var key := Vector2i(roundi(point.x * 64.0), roundi(point.z * 64.0))
	var level := roundi(point.y * 64.0)
	return Vector3(_roll(key, level) - 0.5, (_roll(key, level + 7) - 0.5) * 0.4, _roll(key, level + 13) - 0.5) * CLIFF_JITTER * 2.0


## The heat and light changed (the map, a door): the floor is shaded
## again at the end of the frame, once however many changes came.
func _on_fields_changed() -> void:
	if not _shade_due:
		_shade_due = true
		_shade_floor.call_deferred()


## Each floor cell darkened by the light it lacks (fixed sources and the
## level's ambient light; the carried lanterns are real lights here) and
## warmed by the heat on it: the glow around a fire. A changed cell's
## corners take the average of the cells around them, in every chunk that
## has them, and each chunk with a changed corner is sent once, the span
## that changed.
func _shade_floor() -> void:
	_shade_due = false
	if _grounds.is_empty():
		return
	var touched := World.fields.take_touched(World)
	var cells: Array = _grounds.keys() if touched["all"] or _shade_all else touched["cells"]
	_shade_all = false
	# Heat as World.is_burning reads it: the map's alone while nobody
	# carries any (heat_at goes through every entity, for every cell).
	var carried := World.fields.any_carried_heat(World)
	var dirty := PackedInt32Array()
	var marked: Dictionary[int, bool] = {}
	var shades_moved := false
	for cell: Vector2i in cells:
		var index: int = _grounds.get(cell, -1)
		if index < 0:
			continue
		# The sky's light outdoors is the sun's to draw, not the floor's.
		var light := World.light_at(cell, false, false)
		var heat := World.heat_at(cell) if carried else World.fields.map_heat_at(World, cell)
		var warmth := clampf((heat - 1.0) / (World.HEAT_BURN - 1.0), 0.0, 1.0)
		var shade := Vector2(snappedf(floor_brightness(light), 0.1), snappedf(warmth * WARM_MOST, 0.05))
		if _ground_shades.get(cell) == shade:
			continue
		_ground_shades[cell] = shade
		_cell_shades[index * 2] = roundi(minf(shade.x, 1.0) * 255.0)
		_cell_shades[index * 2 + 1] = roundi(shade.y * 255.0)
		if _shade_image != null:
			var at := cell - _mask_origin
			if at.x >= 0 and at.y >= 0 and at.x < _mask_size.x and at.y < _mask_size.y:
				_shade_image.set_pixel(at.x, at.y, Color(minf(shade.x, 1.0), 0.0, 0.0))
				shades_moved = true
		for k in range(_cell_vertex_start[index], _cell_vertex_start[index + 1]):
			var vertex := _cell_vertices[k]
			if not marked.has(vertex):
				marked[vertex] = true
				dirty.append(vertex)
	if shades_moved:
		_shade_texture.update(_shade_image)
	if dirty.is_empty():
		return
	# Each chunk's changed span of shade bytes [first, last].
	var spans: Dictionary[int, Vector2i] = {}
	for vertex in dirty:
		var bright := 0
		var warm := 0
		var count := 0
		for k in range(vertex * 4, vertex * 4 + 4):
			var cell := _vertex_cells[k]
			if cell >= 0:
				bright += _cell_shades[cell * 2]
				warm += _cell_shades[cell * 2 + 1]
				count += 1
		var byte := _vertex_byte[vertex]
		_ground_bytes[byte] = roundi(bright / float(count))
		_ground_bytes[byte + 1] = roundi(warm / float(count))
		var chunk := _vertex_chunk[vertex]
		var span: Vector2i = spans.get(chunk, Vector2i(byte, byte))
		spans[chunk] = Vector2i(mini(span.x, byte), maxi(span.y, byte))
	for chunk: int in spans:
		var first := spans[chunk].x - _ground_custom
		var last := spans[chunk].y - _ground_custom + _ground_stride
		_ground_meshes[chunk].surface_update_attribute_region(0, first - _chunk_byte_start[chunk],
				_ground_bytes.slice(first, last))


## A lantern hung on a short post, and its pale light.
func _add_lantern(cell: Vector2i) -> void:
	var at := _tile_position(cell)
	var post := _box(Vector3(0.06, 0.8, 0.06), _stone_opaque)
	post.name = "Lantern_%d_%d" % [cell.x, cell.y]
	post.position = at
	_room.add_child(post)
	var light := OmniLight3D.new()
	light.light_color = LANTERN
	light.light_energy = 1.1
	light.omni_range = 4.0
	light.position = at + Vector3(0.0, 0.95, 0.0)
	_room.add_child(light)


## A torch standing in its cell: art-kit's prop.torch_post, its flame at
## the slot's socket (Flames, decision 523), or a stone post with the flame
## on its top until the slot has art; and its warm light, over the flame,
## flickering.
func _add_torch(cell: Vector2i) -> void:
	torch_cells.append(cell)
	var at := _tile_position(cell)
	var post: Node3D
	var flame: Node3D
	if ArtKit.has(TORCH_POST) and ArtKit.filled_by(TORCH_POST) != "placeholder":
		post = ArtKit.instance(TORCH_POST)
		post.rotation.y = _roll(cell, 141) * TAU
		flame = Flames.at_socket(post, TORCH_POST, hash(cell))
		if flame == null:  # Art with no flame socket: on its top.
			flame = Flames.light(post, Vector3(0.0, ArtKit.size(TORCH_POST).y, 0.0), Flames.size_of(TORCH_POST), hash(cell))
	else:
		post = _box(Vector3(0.1, 1.1, 0.1), _stone_opaque)
		flame = Flames.light(post, Vector3(0.0, 1.1, 0.0), Flames.size_of(TORCH_POST), hash(cell))
	post.name = "Torch_%d_%d" % [cell.x, cell.y]
	post.position = at
	_room.add_child(post)
	var light := OmniLight3D.new()
	light.light_color = TORCH
	light.light_energy = 1.4
	light.omni_range = 4.5
	# Over the flame, wherever its post puts it.
	light.position = post.transform * flame.position + Vector3(0.0, Flames.size_of(TORCH_POST) * 0.6, 0.0)
	_room.add_child(light)
	_cast_shadows(light)
	_fire_lights.append([light, light.light_energy, _roll(cell, 142) * TAU, Flames.TORCH_FLICKER])


## The base of an edge's wall: a kind building's its pad (_pad_cell), else
## the higher of the cells it stands between.
func _edge_base(key: Vector3i) -> float:
	if _pad_cell.has(key):
		return _elevation(_pad_cell[key])
	var cells := Terrain.edge_cells(key)
	return maxf(_elevation(cells[0]), _elevation(cells[1]))


func _add_wall(key: Vector3i) -> void:
	var wall: Node3D
	if BOX_WALLS:
		wall = _box(Vector3(WALL_THICKNESS, WALL_HEIGHT, 1.0), _stone_opaque)
	else:
		wall = ArtKit.instance("wall.castle.straight")
	wall.name = "Wall_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	wall.position = _edge_midpoint(key) + Vector3(0.0, _edge_base(key), 0.0)
	wall.rotation.y = _edge_yaw(key)
	_room.add_child(wall)
	_walls[key] = wall


## The walls: each straight run of wall edges of one set and wall height
## (to where it turns, meets another wall, set or wall height, a door, a
## change of ground height, or
## WALL_RUN_MOST edges) is one mesh, its set's wall.<set>.profile swept
## along it, varied as the set's variation says: the body under the
## profile's cap_y rises and falls along the run (sway: a height every
## WALL_SWAY edges, straight between), the cap band on top kept whole; now
## and then an edge's top is broken off (broken), and in a long run,
## rarely, an edge is a breach filled with rubble (gap), low but never a
## way through (the sim keeps the wall); the run leans a little (lean,
## degrees at most), its top sags between its ends (sag, metres) and its
## faces are pushed about (jitter, metres). An edge in _wall_states is
## broken or rubble whatever its set says. Every edge of a run is in
## _walls as the run's node, so the run fades as one (_wall_runs, 188).
func _add_wall_runs(keys: Array[Vector3i]) -> void:
	var lines: Dictionary[Vector2i, Array] = {}
	for key in keys:
		if _unbuilt(key):
			continue  # A building's plot or frame (566): no wall yet.
		var line := _line_of(key)
		if not lines.has(line):
			lines[line] = []
		lines[line].append(key)
	var standing := func(key: Vector3i) -> int:
		return _terrain["edges"].get(key, Terrain.Edge.OPEN) if not (_outdoor and _is_outline(key)) else Terrain.Edge.OPEN
	for line: Vector2i in lines:
		var along: Array = lines[line]
		along.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return _along(a) < _along(b))
		var run: Array[Vector3i] = []
		for key: Vector3i in along:
			if not run.is_empty():
				var last := run[-1]
				var joined := _along(key) == _along(last) + 1 and _edge_base(key) == _edge_base(last) \
						and _set_of(key) == _set_of(last) and _height_of(key) == _height_of(last) \
						and run.size() < WALL_RUN_MOST and not _needs_post(WallEdge.vertex_at(key, 1 if key.z == Terrain.EAST else 0), standing)
				if not joined:
					_add_wall_run(run)
					run = []
			run.append(key)
		if not run.is_empty():
			_add_wall_run(run)


## Draws the wall runs on the lines of [param edges] again, with their
## posts, after their sets or states changed (_wall_sets, _wall_states):
## buildings sets a town's walls broken or rubble and calls this. The rest
## of the room stays; what hides the player is indexed again. The old runs
## are hidden at once and freed two frames later (a 3D node freed before
## the room's first frame is drawn costs seconds: 296; Godot's
## godotengine/godot#124579).
func rebuild_walls(edges: Array[Vector3i]) -> void:
	if _room == null or BOX_WALLS:
		return
	var lines: Dictionary[Vector2i, bool] = {}
	for key in edges:
		lines[_line_of(key)] = true
	var old: Dictionary[Node3D, bool] = {}
	for key: Vector3i in _walls.keys():
		if lines.has(_line_of(key)):
			old[_walls[key]] = true
			_walls.erase(key)
	_wall_breaches = _wall_breaches.filter(func(key: Vector3i) -> bool: return not lines.has(_line_of(key)))
	var keys: Array[Vector3i] = []
	var vertices: Dictionary[Vector2i, bool] = {}
	# The edges given stand their posts again too, even one now open (a
	# felled cell's: clearing_walls).
	for key in edges:
		for end in 2:
			vertices[WallEdge.vertex_at(key, end)] = true
	var fences := _fence_keys()
	for key: Vector3i in _terrain["edges"]:
		if not lines.has(_line_of(key)) or not _edge_drawn(key, fences):
			continue
		if _terrain["edges"][key] == Terrain.Edge.WALL:
			keys.append(key)
		for end in 2:
			vertices[WallEdge.vertex_at(key, end)] = true
	for vertex in vertices:
		if _posts.has(vertex):
			old[_posts[vertex]] = true
			_posts.erase(vertex)
	for piece in old:
		piece.visible = false
		_faded.erase(piece)
		_hiding.erase(piece)
		_hid_at.erase(piece)
	_free_later(old.keys())
	_add_wall_runs(keys)
	# A plot's edges (566) are none: no post stands on them; nor on a bank of
	# rubble (a ruin's, 649; a town wall's at level 0), low as it is.
	var kind_at := func(key: Vector3i) -> int:
		return Terrain.Edge.OPEN if _wall_states.get(key) in ["plot", "rubble"] or _ruin_edges.has(key) \
				else _terrain["edges"].get(key, Terrain.Edge.OPEN)
	for vertex in vertices:
		var built := WallEdge.edges_at_vertex(vertex).any(func(entry: Array) -> bool:
				return kind_at.call(entry[0]) != Terrain.Edge.OPEN and _edge_drawn(entry[0], fences))
		if built and (_needs_post(vertex, kind_at) or _sets_meet(vertex)):
			_add_post(vertex)
	_occluders_built = false
	_update_fade()


## The walls on [param edges] drawn again after the forest was felled or grew
## back there (591 amended, terrain's side; maps' Level.relay_outline: key ->
## its Terrain.Edge now, OPEN where the outline's wall went): Main calls it
## after clearing_changed, with the terrain's edges already changed. A felled
## row's walls against the land go, and its posts; the forest's new edge is
## the outline, drawn as trees, not walls.
func clearing_walls(edges: Dictionary) -> void:
	var keys: Array[Vector3i] = []
	keys.assign(edges.keys())
	if not keys.is_empty():
		rebuild_walls(keys)


## Frees [param pieces] two frames from now, if a rebuild has not already.
func _free_later(pieces: Array) -> void:
	for frame in 2:
		await get_tree().process_frame
	# Untyped: a room rebuilt meanwhile has freed them, and a freed one
	# cannot even be held in a typed variable.
	for piece in pieces:
		if is_instance_valid(piece):
			(piece as Node).queue_free()


## The line an edge stands on: east edges run along z at x + 0.5, south
## edges along x at y + 0.5.
static func _line_of(key: Vector3i) -> Vector2i:
	return Vector2i(key.z, key.x if key.z == Terrain.EAST else key.y)


## The set a wall edge is drawn in (_wall_sets, else the map's).
func _set_of(key: Vector3i) -> String:
	return _wall_sets.get(key, _walls_set)


## How tall a wall edge stands (_wall_heights, a building's; else
## WALL_HEIGHT).
func _height_of(key: Vector3i) -> float:
	return _wall_heights.get(key, WALL_HEIGHT)


## A set's profile [param points] and [param cap] (its body's top) for a
## wall [param tall] metres high: the body stretched up by the difference
## from the set's [param top], the cap band above it kept as it is.
static func _profile_for(points: PackedVector2Array, cap: float, top: float, tall: float) -> Array:
	var rise := tall - top
	if is_zero_approx(rise):
		return [points, cap]
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p.x, p.y * (cap + rise) / cap if p.y <= cap else p.y + rise))
	return [out, cap + rise]


## The set a floor cell is drawn in: its own (_floor_sets), else the map's
## on its stone ground, else the ground's own look.
func _floor_set(cell: Vector2i, kind: String) -> String:
	if _floor_sets.has(cell):
		return _floor_sets[cell]
	return _floors_set if kind == "stone" else DEFAULT_SET


## [param set_name] if art-kit has the set (its wall.<set>.profile), else
## DEFAULT_SET.
static func _known_set(set_name: String) -> String:
	return set_name if ArtKit.has("wall.%s.profile" % set_name) else DEFAULT_SET


## Where an edge is along its line: its z for an east edge, its x for a
## south one.
static func _along(key: Vector3i) -> int:
	return key.y if key.z == Terrain.EAST else key.x


## One run of wall edges of one set, in order along its line, as one mesh.
func _add_wall_run(run: Array[Vector3i]) -> void:
	var first := run[0]
	var set_name := _set_of(first)
	var wall_set := _wall_set(set_name)
	var variation: Dictionary = wall_set["variation"]
	var east := first.z == Terrain.EAST
	# Built in the run's own frame (x across, y up from its base, z along
	# from its first vertex) and placed by its node: an east run as it is,
	# a south one turned a quarter (the profile is the same either side).
	var line := first.x + 0.5 if east else first.y + 0.5
	var start := _along(first) - 0.5
	var base := _edge_base(first)
	var count := run.size()
	# What each edge is: whole, broken off, or a breach of rubble: as
	# _wall_states says, else as the set's variation rolls.
	var states := PackedInt32Array()
	states.resize(count)
	var gap: float = variation["gap"]
	var broken: float = variation["broken"]
	var sway: float = variation["sway"]
	var sag: float = variation["sag"]
	for i in count:
		match _wall_states.get(run[i], ""):
			"rubble": states[i] = WALL_RUBBLE
			"broken": states[i] = WALL_TOPLESS
	for i in count:
		var cell := Vector2i(run[i].x, run[i].y)
		if states[i] == WALL_WHOLE and count >= WALL_GAP_RUN and i >= 2 and i <= count - 3 and _roll(cell, 20 + run[i].z) < gap \
				and (i < 3 or states[i - 1] != WALL_RUBBLE and states[i - 2] != WALL_RUBBLE):
			states[i] = WALL_RUBBLE
	for i in count:
		if states[i] == WALL_WHOLE and (_roll(Vector2i(run[i].x, run[i].y), 22 + run[i].z) < broken
				or i > 0 and states[i - 1] == WALL_RUBBLE or i < count - 1 and states[i + 1] == WALL_RUBBLE):
			states[i] = WALL_TOPLESS
	if set_name == CAVE_SET:
		for k in count:
			if states[k] == WALL_RUBBLE:
				_wall_breaches.append(run[k])
		_add_cave_run(run, states)
		return
	# A broken or rubble edge the set has art for is that piece.
	var pieces: Dictionary[int, String] = {}
	for k in count:
		if states[k] == WALL_RUBBLE:
			_wall_breaches.append(run[k])
		var piece := ""
		if states[k] == WALL_RUBBLE:
			piece = "wall.%s.rubble" % set_name
		elif states[k] == WALL_TOPLESS and _wall_states.has(run[k]):
			piece = "wall.%s.straight_ruined" % set_name
		elif states[k] == WALL_WHOLE and _wall_states.get(run[k]) == "window":
			piece = "wall.%s.window" % set_name
		elif states[k] == WALL_WHOLE and _niche_at.has(run[k]) and str(_niche_at[run[k]]["kind"]) != "hidden":
			piece = NICHE_PIECE % _niche_at[run[k]]["kind"]
		if piece != "" and ArtKit.has(piece) and ArtKit.filled_by(piece) != "placeholder":
			pieces[k] = piece
	for k: int in pieces:
		states[k] = WALL_PIECE
	# A building's taller walls (its wall_height): the profile's body
	# stretched to it.
	var shaped := _profile_for(wall_set["points"], wall_set["cap"], wall_set["top"], _height_of(first))
	var points: PackedVector2Array = shaped[0]
	var cap: float = shaped[1]
	var faces: PackedInt32Array = wall_set["faces"]
	var half: float = wall_set["half"]
	# The top's sag between the run's ends, at a vertex s along it.
	var sagged := func(s: int) -> float: return sag * 4.0 * s * (count - s) / float(count * count)
	var mesh := [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
	var i := 0
	while i < count:
		if states[i] == WALL_PIECE:
			i += 1
			continue
		if states[i] != WALL_WHOLE:
			_wall_broken(mesh, i, run, states, cap, half, sway)
			i += 1
			continue
		# A span of whole edges, to the next sway point or broken edge (a
		# sagging set's every edge, for its curve).
		var j := i + 1
		while j < count and states[j] == WALL_WHOLE and sag <= 0.0 and (_along(run[j]) % WALL_SWAY) != 0:
			j += 1
		var low: float = _wall_height(run[i], 0, cap, sway) - sagged.call(i)
		var high: float = _wall_height(run[j - 1], 1, cap, sway) - sagged.call(j)
		for k in points.size():
			var p := points[k]
			var q := points[(k + 1) % points.size()]
			if p.y <= 0.0 and q.y <= 0.0:
				continue  # The bottom, on the ground.
			_wall_quad(mesh, Vector3(p.x, _profile_y(p.y, cap, low), i), Vector3(q.x, _profile_y(q.y, cap, low), i),
					Vector3(q.x, _profile_y(q.y, cap, high), j), Vector3(p.x, _profile_y(p.y, cap, high), j),
					Vector3(q.y - p.y, -(q.x - p.x), 0.0), absf(q.y - p.y) < absf(q.x - p.x))
		# An end that nothing hides: the run's own, or against a broken edge.
		if i == 0 or states[i - 1] != WALL_WHOLE:
			_wall_cap(mesh, i, points, faces, cap, low, -1.0)
		if j == count or states[j] != WALL_WHOLE:
			_wall_cap(mesh, j, points, faces, cap, high, 1.0)
		i = j
	var lean := deg_to_rad((_roll(Vector2i(first.x, first.y), 34 + first.z) - 0.5) * 2.0 * float(variation["lean"]))
	_wall_bend(mesh, tan(lean), float(variation["jitter"]), first)
	var holder := Node3D.new()
	holder.position = Vector3(line, base, start) if east else Vector3(start, base, line)
	holder.rotation.y = 0.0 if east else PI * 0.5
	holder.name = "Wall_%d_%d_%s" % [first.x, first.y, "e" if east else "s"]
	for k: int in pieces:
		var niche: Dictionary = _niche_at.get(run[k], {})
		var made := ArtKit.instance(pieces[k], int(niche.get("variant", 1)))
		made.name = "Piece_%d" % k
		made.position = Vector3(0.0, 0.0, k + 0.5)
		if _wall_states.get(run[k]) == "window":
			_dress_window(made, run[k])
		if not niche.is_empty():
			# Its +x toward the niche's room: the run's +x is east (an east
			# run) or north (a south run, turned a quarter).
			var across := Vector2i(1, 0) if east else Vector2i(0, -1)
			made.rotation.y = 0.0 if (niche["out"] as Vector2i) == across else PI
		holder.add_child(made)
	if _plinths.has(first):
		_add_plinth(holder, run, base, wall_set["half"])
	if mesh[0].is_empty() and holder.get_child_count() == 0:
		holder.free()
		return
	_room.add_child(holder)
	for key in run:
		_walls[key] = holder
	if mesh[0].is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh[0]
	arrays[Mesh.ARRAY_NORMAL] = mesh[1]
	arrays[Mesh.ARRAY_TEX_UV] = mesh[2]
	arrays[Mesh.ARRAY_INDEX] = mesh[3]
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var drawn := MeshInstance3D.new()
	drawn.name = "Body"
	drawn.mesh = array_mesh
	drawn.material_override = _wall_material(set_name)
	holder.add_child(drawn)


## [param run]'s stone plinth (489 amended) in [param holder] (the run's
## frame: x across, y up from [param base], z along): a band PLINTH_HEIGHT
## over its pad, PLINTH_PROUD wider than the wood's [param half] each side,
## its foot down to the lowest ground beside the run (on a slope, a taller
## footing downhill rather than a gap under the timber), its ends reaching
## half its width on past a corner, not into a door or the next plinth's run.
## A ruin's (649, _ruin_edges) is broken off: by half edges, each its own
## height (RUIN_PLINTH_LOW..HIGH), a stone spilled off one edge in
## RUIN_SPILL_EVERY; its gaps have none, being no run.
func _add_plinth(holder: Node3D, run: Array[Vector3i], base: float, half: float) -> void:
	var out := half + PLINTH_PROUD
	var low := 0.0
	for key in run:
		for cell in Terrain.edge_cells(key):
			low = minf(low, _elevation(cell) - base)
	low -= PLINTH_PROUD
	var reach := func(key: Vector3i) -> float:
		var kind: int = _terrain["edges"].get(key, Terrain.Edge.OPEN)
		return 0.0 if kind == Terrain.Edge.DOOR or _plinths.has(key) and kind == Terrain.Edge.WALL else out
	var first := run[0]
	var last := run[-1]
	var step := Vector3i(0, 1, 0) if first.z == Terrain.EAST else Vector3i(1, 0, 0)
	var from: float = -reach.call(first - step)
	var to: float = run.size() + reach.call(last + step)
	# Its blocks [from, to, top]: one whole band, or a ruin's broken one.
	var blocks: Array[Vector3] = [Vector3(from, to, PLINTH_HEIGHT)]
	if run.any(func(key: Vector3i) -> bool: return _ruin_edges.has(key)):
		blocks.clear()
		for k in run.size():
			var key := run[k]
			for part in 2:
				var top := PLINTH_HEIGHT * lerpf(RUIN_PLINTH_LOW, RUIN_PLINTH_HIGH, _roll(Vector2i(key.x, key.y), 60 + key.z * 2 + part))
				blocks.append(Vector3(from if k == 0 and part == 0 else k + part * 0.5,
						to if k == run.size() - 1 and part == 1 else k + 0.5 + part * 0.5, top))
			if posmod(_edge_hash(key), RUIN_SPILL_EVERY) == 0 and ArtKit.has("scatter.stone"):
				var stone := ArtKit.instance("scatter.stone")
				var side := 1.0 if _roll(Vector2i(key.x, key.y), 64 + key.z) < 0.5 else -1.0
				stone.position = Vector3(side * (out + RUIN_SPILL_OUT), 0.0, k + _roll(Vector2i(key.x, key.y), 66 + key.z))
				stone.rotation.y = _roll(Vector2i(key.x, key.y), 68 + key.z) * TAU
				stone.name = "Spill_%d" % k
				holder.add_child(stone)
	var mesh := [PackedVector3Array(), PackedVector3Array(), PackedVector2Array(), PackedInt32Array()]
	for block in blocks:
		var top := block.z
		for side: float in [-1.0, 1.0]:
			var x := side * out
			_wall_quad(mesh, Vector3(x, low, block.x), Vector3(x, top, block.x), Vector3(x, top, block.y), Vector3(x, low, block.y),
					Vector3(side, 0.0, 0.0), false)
		_wall_quad(mesh, Vector3(-out, top, block.x), Vector3(out, top, block.x), Vector3(out, top, block.y),
				Vector3(-out, top, block.y), Vector3.UP, true)
		for end: float in [block.x, block.y]:
			_wall_quad(mesh, Vector3(-out, low, end), Vector3(out, low, end), Vector3(out, top, end), Vector3(-out, top, end),
					Vector3(0.0, 0.0, -1.0 if end == block.x else 1.0), false)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh[0]
	arrays[Mesh.ARRAY_NORMAL] = mesh[1]
	arrays[Mesh.ARRAY_TEX_UV] = mesh[2]
	arrays[Mesh.ARRAY_INDEX] = mesh[3]
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var drawn := MeshInstance3D.new()
	drawn.name = "Plinth"
	drawn.mesh = array_mesh
	drawn.material_override = _wall_material("stone")
	holder.add_child(drawn)


## A run of the cave set (286): rock in the run's frame (x across, y up,
## z along), its shape read from where it is in the world, so runs on one
## line meet without a seam: each column along it CAVE_ROWS points up each
## side, the profile's width at that height times a thickness that wanders
## along the line, pushed about; a ragged ridge on top; the run's own ends
## closed. A broken edge stands about half as tall, rubble as rubble does
## (WALL_RUBBLE_LOW to _HIGH). Faceted, coloured as the cliffs.
func _add_cave_run(run: Array[Vector3i], states: PackedInt32Array) -> void:
	var first := run[0]
	var east := first.z == Terrain.EAST
	var line := first.x + 0.5 if east else first.y + 0.5
	var start := _along(first) - 0.5
	var base := _edge_base(first)
	var count := run.size()
	var seed := _line_of(first)
	var wall_set := _wall_set(CAVE_SET)
	var profile: PackedVector2Array = wall_set["points"]
	var tall: float = wall_set["top"]
	# Each column's top and width, and its points: left side up, the ridge,
	# right side down.
	var steps := count * CAVE_ALONG
	var columns: Array[PackedVector3Array] = []
	for step in steps + 1:
		var z := step / float(CAVE_ALONG)
		var along := start + z
		var top := INF
		for i: int in [floori(z - 0.001), floori(z + 0.001)]:
			if i < 0 or i >= count:
				continue
			var whole := lerpf(CAVE_TOP_LOW, CAVE_TOP_HIGH, _cave_noise(along, seed, 0))
			match states[i]:
				WALL_TOPLESS: top = minf(top, whole * 0.55)
				WALL_RUBBLE: top = minf(top, lerpf(WALL_RUBBLE_LOW, WALL_RUBBLE_HIGH, _cave_noise(along, seed, 2)))
				_: top = minf(top, whole)
		var thick := lerpf(CAVE_THICK_LOW, CAVE_THICK_HIGH, _cave_noise(along, seed, 1))
		var column := PackedVector3Array()
		for side: float in [-1.0, 1.0]:
			for r in CAVE_ROWS + 1:
				var row := r if side < 0.0 else CAVE_ROWS - r
				var v := row / float(CAVE_ROWS)
				var y := v * top
				var x := side * _profile_half(profile, v * tall) * thick
				if row > 0:
					var bump := _cave_bump(along, y, side, seed)
					x += bump.x * minf(1.0, y)
					y += bump.y if row < CAVE_ROWS else 0.0
				column.append(Vector3(clampf(x, -CAVE_REACH, CAVE_REACH), y, z))
			if side < 0.0:
				var ridge := _cave_bump(along, top, 0.0, seed)
				column.append(Vector3(clampf(ridge.x, -CAVE_REACH, CAVE_REACH), top + CAVE_RIDGE * (0.5 + ridge.y / CAVE_BUMP * 0.5), z))
		columns.append(column)
	var mesh := [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
	var points := columns[0].size()
	for step in steps:
		var a := columns[step]
		var b := columns[step + 1]
		# Up the left side, over the ridge, down the right.
		for k in points - 1:
			var out := Vector3(-1.0 if k <= CAVE_ROWS else 1.0, 0.0, 0.0)
			if k == CAVE_ROWS or k == CAVE_ROWS + 1:
				out = Vector3(out.x * 0.3, 1.0, 0.0)
			_rock_quad(mesh, a[k], b[k], b[k + 1], a[k + 1], out, 0.0, tall)
	# The run's ends: the column as a face.
	for end in 2:
		var column := columns[0 if end == 0 else steps]
		var out := Vector3(0.0, 0.0, -1.0 if end == 0 else 1.0)
		for k in CAVE_ROWS:
			_rock_quad(mesh, column[k], column[k + 1], column[points - 2 - k], column[points - 1 - k], out, 0.0, tall)
		_rock_quad(mesh, column[CAVE_ROWS], column[CAVE_ROWS + 1], column[CAVE_ROWS + 2], column[CAVE_ROWS], out, 0.0, tall)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh[0]
	arrays[Mesh.ARRAY_NORMAL] = mesh[1]
	arrays[Mesh.ARRAY_COLOR] = mesh[2]
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var holder := Node3D.new()
	holder.position = Vector3(line, base, start) if east else Vector3(start, base, line)
	holder.rotation.y = 0.0 if east else PI * 0.5
	holder.name = "Wall_%d_%d_%s" % [first.x, first.y, "e" if east else "s"]
	var drawn := MeshInstance3D.new()
	drawn.name = "Body"
	drawn.mesh = array_mesh
	drawn.material_override = _rock_material()
	holder.add_child(drawn)
	_room.add_child(holder)
	for key in run:
		_walls[key] = holder


## A quad a b c d of rock into [param mesh] ([positions, normals, colours]),
## as two flat facets facing [param out], each its own shade of the cliffs'
## rock, darker toward the foot ([param low] to [param high]).
func _rock_quad(mesh: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, low: float, high: float) -> void:
	for triangle: Array in [[a, b, c], [a, c, d]]:
		var p0: Vector3 = triangle[0]
		var p1: Vector3 = triangle[1]
		var p2: Vector3 = triangle[2]
		var normal := (p1 - p0).cross(p2 - p0)
		if normal.length_squared() < 0.0000001:
			continue
		normal = normal.normalized()
		if normal.dot(out) < 0.0:
			normal = -normal
			var swap := p1
			p1 = p2
			p2 = swap
		var middle := (p0 + p1 + p2) / 3.0
		var shade := lerpf(0.8, 1.15, _roll(Vector2i(roundi(middle.x * 16.0) + roundi(middle.y * 16.0) * 131, roundi(middle.z * 16.0)), 38))
		shade *= lerpf(0.72, 1.0, clampf(inverse_lerp(low, high, middle.y), 0.0, 1.0))
		var colour := Color(swatch(CLIFF_ROCK.x, CLIFF_ROCK.y) * shade, 1.0)
		mesh[0].append_array([p0, p1, p2])
		mesh[1].append_array([normal, normal, normal])
		mesh[2].append_array([colour, colour, colour])


## A lump of the cave's rock at [param vertex] (its post, while wall.cave.end
## has no art): CAVE_LUMP_SIDES round, as wide as the walls are at their
## thickest, as tall as they are there, pushed about as they are.
func _cave_lump(vertex: Vector2i) -> Node3D:
	var wall_set := _wall_set(CAVE_SET)
	var profile: PackedVector2Array = wall_set["points"]
	var tall: float = wall_set["top"]
	var seed := Vector2i(vertex.x * 7, vertex.y * 13)
	var top := lerpf(CAVE_TOP_LOW, CAVE_TOP_HIGH, _cave_noise(vertex.x * 1.7 + vertex.y, seed, 0)) + CAVE_RIDGE
	var rings: Array[PackedVector3Array] = []
	for r in CAVE_ROWS + 1:
		var v := r / float(CAVE_ROWS)
		var ring := PackedVector3Array()
		var radius := minf(_profile_half(profile, v * tall) * CAVE_THICK_HIGH, CAVE_REACH) if r < CAVE_ROWS else 0.08
		for k in CAVE_LUMP_SIDES:
			var angle := TAU * k / CAVE_LUMP_SIDES
			var bump := _cave_bump(angle * 3.0 + vertex.x, v * top, 1.0, seed) if r > 0 else Vector2.ZERO
			var reach := clampf(radius + bump.x, 0.05, CAVE_REACH)
			ring.append(Vector3(cos(angle) * reach, v * top + (bump.y if r > 0 and r < CAVE_ROWS else 0.0), sin(angle) * reach))
		rings.append(ring)
	var mesh := [PackedVector3Array(), PackedVector3Array(), PackedColorArray()]
	for r in CAVE_ROWS:
		for k in CAVE_LUMP_SIDES:
			var next := (k + 1) % CAVE_LUMP_SIDES
			var middle := (rings[r][k] + rings[r][next]) * 0.5
			_rock_quad(mesh, rings[r][k], rings[r][next], rings[r + 1][next], rings[r + 1][k], Vector3(middle.x, 0.2, middle.z), 0.0, top)
	# Its top closed.
	var peak := Vector3(0.0, top + CAVE_RIDGE, 0.0)
	for k in CAVE_LUMP_SIDES:
		_rock_quad(mesh, rings[CAVE_ROWS][k], rings[CAVE_ROWS][(k + 1) % CAVE_LUMP_SIDES], peak, peak, Vector3.UP, 0.0, top)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh[0]
	arrays[Mesh.ARRAY_NORMAL] = mesh[1]
	arrays[Mesh.ARRAY_COLOR] = mesh[2]
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var holder := Node3D.new()
	var drawn := MeshInstance3D.new()
	drawn.name = "Body"
	drawn.mesh = array_mesh
	drawn.material_override = _rock_material()
	holder.add_child(drawn)
	return holder


## How wide [param profile] is either side of its middle at [param y] (the
## widest of where its sides cross that height).
static func _profile_half(profile: PackedVector2Array, y: float) -> float:
	var half := 0.0
	for k in profile.size():
		var p := profile[k]
		var q := profile[(k + 1) % profile.size()]
		if (p.y <= y and q.y >= y or q.y <= y and p.y >= y) and p.y != q.y:
			half = maxf(half, absf(lerpf(p.x, q.x, (y - p.y) / (q.y - p.y))))
		elif is_equal_approx(p.y, y):
			half = maxf(half, absf(p.x))
	return half


## Smooth noise 0..1 along a line of the cave's walls ([param seed] the
## line, [param channel] which wander: 0 the top, 1 the thickness, 2
## rubble's top), the same for every run on the line.
static var _cave_noise_source: FastNoiseLite


static func _cave_noise(along: float, seed: Vector2i, channel: int) -> float:
	if _cave_noise_source == null:
		_cave_noise_source = FastNoiseLite.new()
		_cave_noise_source.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_cave_noise_source.seed = 286
		_cave_noise_source.frequency = 0.45
	var value := _cave_noise_source.get_noise_2d(along, seed.x * 37.0 + seed.y * 11.3 + channel * 101.0)
	return clampf(value * 0.5 + 0.5, 0.0, 1.0)


## How far a cave wall's point is pushed (across, up), by where it is alone
## (its place along, its height, its side), so the runs that share it push
## it alike.
static func _cave_bump(along: float, y: float, side: float, seed: Vector2i) -> Vector2:
	var key := Vector2i(roundi(along * 64.0) * 3 + roundi(side) + 1, seed.x * 100003 + seed.y)
	var level := roundi(y * 32.0)
	return Vector2((_roll(key, level) - 0.5) * 2.0, (_roll(key, level + 5) - 0.5) * 0.6) * CAVE_BUMP


## The rock's material: the cliffs' (vertex colour, flat facets), made once.
static var _rock: StandardMaterial3D


static func _rock_material() -> StandardMaterial3D:
	if _rock == null:
		_rock = StandardMaterial3D.new()
		_rock.vertex_color_use_as_albedo = true
		_rock.roughness = 1.0
		_rock.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _rock


## A run's mesh leant across by [param shear] (metres across a metre up:
## the base stays on its line) and its points pushed across and up by up to
## [param jitter] metres, the same push wherever a point is shared, so no
## seam opens; the normals turned with the lean.
func _wall_bend(mesh: Array, shear: float, jitter: float, first: Vector3i) -> void:
	if shear == 0.0 and jitter <= 0.0:
		return
	var positions: PackedVector3Array = mesh[0]
	var normals: PackedVector3Array = mesh[1]
	for k in positions.size():
		var p := positions[k]
		if jitter > 0.0 and p.y > 0.001:
			var at := Vector2i(roundi(p.x * 997.0) + roundi(p.y * 991.0) * 31 + first.x * 7 + first.y * 13, roundi(p.z * 983.0))
			p += Vector3(_roll(at, 36) - 0.5, (_roll(at, 37) - 0.5) * 0.5, 0.0) * 2.0 * jitter
		p.x += p.y * shear
		positions[k] = p
		var n := normals[k]
		normals[k] = Vector3(n.x, n.y - n.x * shear, n.z).normalized()
	mesh[0] = positions
	mesh[1] = normals


## How tall the body under the cap stands at [param key]'s end [param end]
## (0 its start, 1 its end): a height at every WALL_SWAY-th vertex along
## the line, up to [param sway] of [param cap] either way, straight
## between, so neighbouring runs on one line agree.
func _wall_height(key: Vector3i, end: int, cap: float, sway_by: float) -> float:
	var at := _along(key) + end
	var before := at - posmod(at, WALL_SWAY)
	var after := before + WALL_SWAY
	var line := Vector2i(key.x if key.z == Terrain.EAST else key.y, key.z)
	var sway := func(along: int) -> float: return (_roll(Vector2i(line.x * 7 + line.y, along), 24) - 0.5) * 2.0 * sway_by
	return cap * (1.0 + lerpf(sway.call(before), sway.call(after), float(at - before) / WALL_SWAY))


## A profile height as drawn: the body (under [param cap]) stretched to
## [param body], the band above it as it is.
static func _profile_y(y: float, cap: float, body: float) -> float:
	return y * body / cap if y <= cap else body + (y - cap)


## A broken or rubble edge [param i] of [param run]: a slab [param wall_half]
## a side with a ragged top (lower, wider and lumpier for rubble), over
## WALL_BROKEN_STEPS steps.
func _wall_broken(mesh: Array, i: int, run: Array[Vector3i], states: PackedInt32Array, cap: float, wall_half: float, sway: float) -> void:
	var key := run[i]
	var rubble := states[i] == WALL_RUBBLE
	var half := wall_half + WALL_RUBBLE_SPREAD if rubble else wall_half
	var heights := PackedFloat32Array()
	var lean := PackedFloat32Array()
	for step in WALL_BROKEN_STEPS + 1:
		var cell := Vector2i(_along(key) * WALL_BROKEN_STEPS + step, key.x + key.y * 7 + key.z * 13)
		var roll := _roll(cell, 26)
		if rubble:
			heights.append(lerpf(WALL_RUBBLE_LOW, WALL_RUBBLE_HIGH, roll))
		elif step == 0 and i > 0 and states[i - 1] == WALL_WHOLE:
			heights.append(_wall_height(key, 0, cap, sway) * 0.85)
		elif step == WALL_BROKEN_STEPS and i < run.size() - 1 and states[i + 1] == WALL_WHOLE:
			heights.append(_wall_height(key, 1, cap, sway) * 0.85)
		else:
			heights.append(cap * lerpf(WALL_BROKEN_LOW, WALL_BROKEN_HIGH, roll))
		lean.append((_roll(cell, 28) - 0.5) * (0.24 if rubble else 0.0))
	for step in WALL_BROKEN_STEPS:
		var s0 := i + step / float(WALL_BROKEN_STEPS)
		var s1 := i + (step + 1) / float(WALL_BROKEN_STEPS)
		var h0 := heights[step]
		var h1 := heights[step + 1]
		var l0 := lean[step]
		var l1 := lean[step + 1]
		for side: float in [-1.0, 1.0]:
			_wall_quad(mesh, Vector3(side * half, 0.0, s0), Vector3(side * half, 0.0, s1),
					Vector3(side * half * 0.8 + l1, h1, s1), Vector3(side * half * 0.8 + l0, h0, s0), Vector3(side, 0.0, 0.0), false)
		_wall_quad(mesh, Vector3(-half * 0.8 + l0, h0, s0), Vector3(half * 0.8 + l0, h0, s0),
				Vector3(half * 0.8 + l1, h1, s1), Vector3(-half * 0.8 + l1, h1, s1), Vector3(0.0, 1.0, 0.0), true)
	# Its ends, where what is beside it is not the same slab.
	for end in 2:
		var other := i - 1 if end == 0 else i + 1
		if other >= 0 and other < run.size() and states[other] == states[i]:
			continue
		var s := float(i + end)
		var h := heights[0 if end == 0 else WALL_BROKEN_STEPS]
		var l := lean[0 if end == 0 else WALL_BROKEN_STEPS]
		_wall_quad(mesh, Vector3(-half, 0.0, s), Vector3(half, 0.0, s), Vector3(half * 0.8 + l, h, s),
				Vector3(-half * 0.8 + l, h, s), Vector3(0.0, 0.0, -1.0 if end == 0 else 1.0), false)


## A whole run's end at [param s]: the profile as a face, [param body] tall,
## facing [param facing] along the run (in the run's frame).
func _wall_cap(mesh: Array, s: float, points: PackedVector2Array, faces: PackedInt32Array, cap: float, body: float, facing: float) -> void:
	var positions: PackedVector3Array = mesh[0]
	var normal := Vector3(0.0, 0.0, facing)
	for t in range(0, faces.size(), 3):
		var a := points[faces[t]]
		var b := points[faces[t + 1]]
		var c := points[faces[t + 2]]
		var first := positions.size()
		var pa := Vector3(a.x, _profile_y(a.y, cap, body), s)
		var pb := Vector3(b.x, _profile_y(b.y, cap, body), s)
		var pc := Vector3(c.x, _profile_y(c.y, cap, body), s)
		if (pc - pa).cross(pb - pa).dot(normal) < 0.0:
			var swap := pb
			pb = pc
			pc = swap
		positions.append(pa)
		positions.append(pb)
		positions.append(pc)
		for k in 3:
			mesh[1].append(normal)
		mesh[2].append(Vector2(pa.x, pa.y) / WALL_TILE)
		mesh[2].append(Vector2(pb.x, pb.y) / WALL_TILE)
		mesh[2].append(Vector2(pc.x, pc.y) / WALL_TILE)
		mesh[3].append(first)
		mesh[3].append(first + 1)
		mesh[3].append(first + 2)
	mesh[0] = positions


## A quad a b c d into [param mesh], in a run's frame (x across, y up, z
## along), facing [param out]; its texture by metres: along and up on a
## side, along and across on a top ([param flat]).
func _wall_quad(mesh: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, flat: bool) -> void:
	if (c - a).cross(b - a).dot(out) < 0.0:
		var swap := b
		b = d
		d = swap
	var face := (c - a).cross(b - a)
	var normal := face.normalized() if face.length_squared() > 0.0000001 else out.normalized()
	var positions: PackedVector3Array = mesh[0]
	var normals: PackedVector3Array = mesh[1]
	var uvs: PackedVector2Array = mesh[2]
	var indices: PackedInt32Array = mesh[3]
	var first := positions.size()
	positions.append(a)
	positions.append(b)
	positions.append(c)
	positions.append(d)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	normals.append(normal)
	if flat:
		uvs.append(Vector2(a.z, a.x) / WALL_TILE)
		uvs.append(Vector2(b.z, b.x) / WALL_TILE)
		uvs.append(Vector2(c.z, c.x) / WALL_TILE)
		uvs.append(Vector2(d.z, d.x) / WALL_TILE)
	else:
		uvs.append(Vector2(a.z, a.y) / WALL_TILE)
		uvs.append(Vector2(b.z, b.y) / WALL_TILE)
		uvs.append(Vector2(c.z, c.y) / WALL_TILE)
		uvs.append(Vector2(d.z, d.y) / WALL_TILE)
	indices.append(first)
	indices.append(first + 1)
	indices.append(first + 2)
	indices.append(first)
	indices.append(first + 2)
	indices.append(first + 3)
	mesh[0] = positions
	mesh[1] = normals
	mesh[2] = uvs
	mesh[3] = indices


## A wall set from the art slots (wall.<set>.profile): its points (x
## across, y up), its cap_y (the top, for the cave's, which has none: all
## body), its face as triangles (indices into the points), its half
## thickness, and its variation (sway, broken, gap, lean, jitter, sag; 0
## where it says none); made once a set.
static var _sets: Dictionary[String, Dictionary] = {}


static func _wall_set(set_name: String) -> Dictionary:
	if not _sets.has(set_name):
		var spec := ArtKit.spec("wall.%s.profile" % set_name)
		var points := PackedVector2Array()
		var top := 0.0
		var half := 0.0
		for each: Array in spec.get("points", [[-0.25, 0.0], [0.25, 0.0], [0.25, 3.0], [-0.25, 3.0]]):
			points.append(Vector2(each[0], each[1]))
			top = maxf(top, float(each[1]))
			half = maxf(half, absf(float(each[0])))
		var given: Dictionary = spec.get("variation", {})
		var variation := {}
		for key: String in ["sway", "broken", "gap", "lean", "jitter", "sag"]:
			variation[key] = float(given.get(key, 0.0))
		_sets[set_name] = {"points": points, "cap": float(spec.get("cap_y", top)), "faces": Geometry2D.triangulate_polygon(points),
				"half": half, "top": top, "variation": variation}
	return _sets[set_name]


## A set's walls' material: material.wall.<set>'s texture if it has one,
## else courses made here (_stone_courses) in its swatch (WALL_LOOKS); a
## plain StandardMaterial3D, so a near run's see-through copy is made as
## any other's (_see_through_of). One a set.
static var _wall_stones: Dictionary[String, StandardMaterial3D] = {}


static func _wall_material(set_name: String) -> StandardMaterial3D:
	if not _wall_stones.has(set_name):
		var look: Array = WALL_LOOKS.get(set_name, WALL_LOOKS[DEFAULT_SET])
		var material := StandardMaterial3D.new()
		var own := ArtKit.texture("material.wall." + set_name)
		material.albedo_texture = own if own != null else _stone_courses(look[1], look[2], look[3], 0 if set_name == DEFAULT_SET else set_name.hash())
		material.albedo_color = Color.WHITE if own != null else swatch(look[0].x, look[0].y)
		material.roughness = 0.9
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_wall_stones[set_name] = material
	return _wall_stones[set_name]


## Courses of stone blocks (or planks), WALL_TILE metres square, tiling:
## [param rows] rows of blocks [param shortest] to [param longest] of the
## tile long, each its own shade, mortar between; [param salt] for a set's
## own (0: the castle's, as it always was).
static func _stone_courses(rows: int, shortest: float, longest: float, salt: int) -> ImageTexture:
	var size := 128
	var bytes := PackedByteArray()
	bytes.resize(size * size * 3)
	for row in rows:
		var top := row * size / rows
		var bottom := (row + 1) * size / rows
		# The row's joints across, from a shift so rows do not line up.
		var joints: Array[int] = []
		var x := int(_roll(Vector2i(row, 1 + salt), 30) * size * 0.5)
		var end := x + size
		while x < end - size * 0.15:
			joints.append(x % size)
			x += int(lerpf(shortest, longest, _roll(Vector2i(row, x + salt), 31)) * size)
		for y in range(top, bottom):
			for px in size:
				# The block: the last joint at or before px, round the tile.
				var block := joints.size() - 1
				var gap := size
				for k in joints.size():
					var behind := posmod(px - joints[k], size)
					if behind < gap:
						gap = behind
						block = k
				var mortar := y - top < 2 or gap < 2
				var shade := 0.78 if mortar else lerpf(0.9, 1.0, _roll(Vector2i(row, block + salt), 32)) * lerpf(0.97, 1.0, _roll(Vector2i(px, y), 33))
				var value := int(shade * 255.0)
				var at := (y * size + px) * 3
				bytes[at] = value
				bytes[at + 1] = value
				bytes[at + 2] = value
	var image := Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## A door.single on the edge, its leaf (DOOR_LEAF) hinged at the edge's
## start end and swinging with the Door node, and an Area3D over the module
## for picking. Its frame (DOOR_FRAME) fades with its wall's run. With
## [param pair] the next edge along (_double_doors), a door.double over
## both instead (decision 403): each edge's Door still its own, swinging the
## leaf on its half, picked by its own area.
func _add_doorway(key: Vector3i, pair := key) -> void:
	var double := pair != key
	var doorway := Node3D.new()
	doorway.name = "Door_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	doorway.position = (_edge_midpoint(key) + _edge_midpoint(pair)) * 0.5 + Vector3(0.0, _edge_base(key), 0.0)
	doorway.rotation.y = _edge_yaw(key)
	var piece := ArtKit.instance("door.double" if double else "door.single")
	piece.name = "Door"
	doorway.add_child(piece)
	var keys: Array[Vector3i] = [key]
	if double:
		keys.append(pair)
	# In a wall taller than the frame (a building's wall_height), the wall
	# goes on over it: a lintel of the wall's set, in the frame's Body so it
	# fades with it.
	var tall := _doorway_height(key)
	if tall > WALL_HEIGHT and piece.has_node("Body"):
		var wall_set := _wall_set(_set_of(key))
		var lintel := MeshInstance3D.new()
		lintel.name = "Lintel"
		var block := BoxMesh.new()
		block.size = Vector3(float(wall_set["half"]) * 2.0, tall - WALL_HEIGHT, float(keys.size()))
		lintel.mesh = block
		lintel.material_override = _wall_material(_set_of(key))
		lintel.position.y = (tall + WALL_HEIGHT) * 0.5
		piece.get_node("Body").add_child(lintel)
	for each in keys:
		# Where the edge's half lies along the doorway (its local z).
		var along := (doorway.transform.affine_inverse() * _edge_midpoint(each)).z if double else 0.0
		if not double:
			_door_hinges[each] = [doorway.get_node(DOOR_LEAF), PI * 0.5, true]
		elif along < 0.0:
			_door_hinges[each] = [piece.get_node("leaf_a"), PI * 0.5, true]
		else:
			_door_hinges[each] = [piece.get_node("leaf_b"), -PI * 0.5, false]
		_doorways[each] = doorway
		if _glimpse:
			continue  # Nothing in a glimpse is picked.
		var area := Area3D.new()
		area.name = "Pick" if not double else "Pick_%d_%d" % [each.x, each.y]
		area.set_meta("door", each)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, 1.0)
		shape.shape = box
		shape.position = Vector3(0.0, WALL_HEIGHT * 0.5, along)
		area.add_child(shape)
		doorway.add_child(area)
	_room.add_child(doorway)


## The doorways drawn as one door.double (decision 403): a building's door
## edges side by side on its outline, two at a time from each run's start
## (a third left a door.single). First edge -> the next along.
func _double_doors() -> Dictionary[Vector3i, Vector3i]:
	var edges: Dictionary = _terrain["edges"]
	var out: Dictionary[Vector3i, Vector3i] = {}
	for building: Dictionary in _drawn_buildings():
		var outline := Level.building_outline(building)
		var door := func(key: Vector3i) -> bool: return key in outline and edges.get(key, Terrain.Edge.OPEN) == Terrain.Edge.DOOR
		for key in outline:
			var step := Vector3i(0, 1, 0) if key.z == Terrain.EAST else Vector3i(1, 0, 0)
			if not door.call(key) or door.call(key - step):
				continue
			var at := key
			while door.call(at) and door.call(at + step):
				out[at] = at + step
				at += step * 2
	return out


## How tall the wall a doorway stands in is: the tallest of the walls on
## its line either side of it (a building's outline: _wall_heights), else
## WALL_HEIGHT.
func _doorway_height(key: Vector3i) -> float:
	var step := Vector3i(0, 1, 0) if key.z == Terrain.EAST else Vector3i(1, 0, 0)
	var tall := _height_of(key)
	for side: Vector3i in [step, -step]:
		var next := key + side
		while _terrain["edges"].get(next, Terrain.Edge.OPEN) == Terrain.Edge.DOOR:
			next += side
		if _terrain["edges"].get(next, Terrain.Edge.OPEN) == Terrain.Edge.WALL:
			tall = maxf(tall, _height_of(next))
	return tall


## A post where walls meet at an angle, or a wall ends; none along a
## straight run.
static func _needs_post(vertex: Vector2i, kind_at: Callable) -> bool:
	var directions: Array[Vector2] = []
	for entry: Array in WallEdge.edges_at_vertex(vertex):
		var kind: int = kind_at.call(entry[0])
		if kind == Terrain.Edge.OPEN:
			continue
		directions.append(WallEdge.away_from(entry[0], entry[1]))
	if directions.size() != 2:
		return true
	return directions[0].dot(directions[1]) > -0.9


## Whether walls of two sets, or two heights, meet at [param vertex]: a
## post between them, so the step from one to the other is not seen.
func _sets_meet(vertex: Vector2i) -> bool:
	var seen := ""
	for entry: Array in WallEdge.edges_at_vertex(vertex):
		var key: Vector3i = entry[0]
		if _terrain["edges"].get(key, Terrain.Edge.OPEN) != Terrain.Edge.WALL or _outdoor and _is_outline(key):
			continue
		var look := "%s %s" % [_set_of(key), _height_of(key)]
		if seen != "" and look != seen:
			return true
		seen = look
	return false


## The set a post at [param vertex] is in: the thickest of its walls'.
func _post_set(vertex: Vector2i) -> String:
	var out := _walls_set
	var widest := -1.0
	for entry: Array in WallEdge.edges_at_vertex(vertex):
		var key: Vector3i = entry[0]
		if _terrain["edges"].get(key, Terrain.Edge.OPEN) == Terrain.Edge.OPEN:
			continue
		var half: float = _wall_set(_set_of(key))["half"]
		if half > widest:
			widest = half
			out = _set_of(key)
	return out


## A post in its set (_post_set): wall.<set>.post, or .end for a set with
## no post (the cave's); a column of the set's own stone where the slot has
## no art yet.
func _add_post(vertex: Vector2i) -> void:
	var post: Node3D
	var set_name := _post_set(vertex)
	var slot := "wall.%s.post" % set_name if ArtKit.has("wall.%s.post" % set_name) else "wall.%s.end" % set_name
	# As tall as the tallest wall at it: the set's _tall piece where it has
	# art, else the post stretched; squeezed where every wall at it is lower
	# than a storey (a lean-to's, decision 489), so it stands no higher.
	var tall := 0.0
	for entry: Array in WallEdge.edges_at_vertex(vertex):
		if _terrain["edges"].get(entry[0], Terrain.Edge.OPEN) != Terrain.Edge.OPEN and not _wall_states.get(entry[0]) in ["plot", "rubble"] \
				and not _ruin_edges.has(entry[0]):
			tall = maxf(tall, _height_of(entry[0]))
	if tall <= 0.0:
		tall = WALL_HEIGHT
	var stretch := 1.0
	if tall > WALL_HEIGHT:
		var tall_slot := slot + "_tall"
		if ArtKit.has(tall_slot) and ArtKit.filled_by(tall_slot) != "placeholder":
			slot = tall_slot
		else:
			stretch = tall / WALL_HEIGHT
	elif tall < WALL_HEIGHT:
		stretch = tall / WALL_HEIGHT
	if BOX_WALLS:
		post = _box(Vector3(POST_SIZE, tall, POST_SIZE), _stone_opaque)
	elif set_name == CAVE_SET and (not ArtKit.has(slot) or ArtKit.filled_by(slot) == "placeholder"):
		post = _cave_lump(vertex)
	elif not ArtKit.has(slot) or ArtKit.filled_by(slot) == "placeholder" and set_name != DEFAULT_SET:
		var wall_set := _wall_set(set_name)
		var side: float = wall_set["half"] * 2.0
		post = _box(Vector3(side, wall_set["top"] + tall - WALL_HEIGHT, side), _wall_material(set_name))
	else:
		post = ArtKit.instance(slot)
		post.scale.y = stretch
	post.name = "Post_%d_%d" % [vertex.x, vertex.y]
	var base := 0.0
	for corner: Vector2i in [vertex, vertex - Vector2i(1, 0), vertex - Vector2i(0, 1), vertex - Vector2i(1, 1)]:
		base = maxf(base, _elevation(corner))
	# A kind building's on its pad (_pad_cell).
	for entry: Array in WallEdge.edges_at_vertex(vertex):
		if _pad_cell.has(entry[0]):
			base = _elevation(_pad_cell[entry[0]])
			break
	post.position = Vector3(vertex.x - 0.5, base, vertex.y - 0.5)
	_room.add_child(post)
	_posts[vertex] = post


## Fire on the ground: a ragged glowing patch (fire.gdshader) wider than
## its cell, so cells of fire side by side run together; one mesh for all.
static var _fire_mesh: PlaneMesh


func _add_fire(cell: Vector2i) -> void:
	torch_cells.append(cell)
	if _fire_mesh == null:
		_fire_mesh = PlaneMesh.new()
		_fire_mesh.size = Vector2(FIRE_SPREAD, FIRE_SPREAD)
		var material := ShaderMaterial.new()
		material.shader = FIRE_SHADER
		material.set_shader_parameter("fire", FIRE)
		_fire_mesh.material = material
	var quad := MeshInstance3D.new()
	quad.name = "Fire_%d_%d" % [cell.x, cell.y]
	quad.mesh = _fire_mesh
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.position = _tile_position(cell) + Vector3(0.0, ON_FLOOR, 0.0)
	quad.rotation.y = _roll(cell, 6) * TAU
	_room.add_child(quad)
	# Its flames (decision 523), at places in the cell by the cell.
	var flames := FIRE_FLAMES.x + floori(_roll(cell, 143) * (FIRE_FLAMES.y - FIRE_FLAMES.x + 1))
	for n in flames:
		var off := Vector2(_roll(cell, 144 + n * 3), _roll(cell, 145 + n * 3)) - Vector2(0.5, 0.5)
		var size := lerpf(FIRE_FLAME_SIZES.x, FIRE_FLAME_SIZES.y, _roll(cell, 146 + n * 3))
		var flame := Flames.light(quad, Vector3(off.x * 0.6, 0.0, off.y * 0.6), size, hash(Vector3i(cell.x, cell.y, n)))
		flame.name = "Flame%d" % n
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 1.5
	light.omni_range = 2.5
	light.position = _tile_position(cell) + Vector3(0.0, 0.5, 0.0)
	_room.add_child(light)
	_fire_lights.append([light, light.light_energy, _roll(cell, 147) * TAU, Flames.FIRE_FLICKER])


## Fire's drawn lights each frame (decision 523): each flickers on its own
## phase (Flames.flicker) and, outdoors, fades by day where the sky reaches
## (Flames.day_share). World's light (Fields) is never touched: it stays
## steady for Senses.
func _flicker_fires(delta: float) -> void:
	if _fire_lights.is_empty():
		return
	_fire_time += delta
	var share := Flames.day_share(_look_daylight, _outdoor, World.fields.canopy_shade if World.fields != null else 0.0)
	for fire: Array in _fire_lights:
		var light := fire[0] as OmniLight3D
		if is_instance_valid(light):
			light.light_energy = float(fire[1]) * share * Flames.flicker(_fire_time, float(fire[2]), float(fire[3]))


# --- Shadows -------------------------------------------------------------------

## [param light] casts shadows while it can reach what the camera shows:
## on until the next frame's _update_shadows (it may not be placed yet).
func _cast_shadows(light: OmniLight3D) -> void:
	_shadow_lights.append(light)
	light.shadow_enabled = true
	_shadow_key = Vector3i(1 << 30, 0, 0)


## How far from the camera's aim, on the ground, the screen reaches: the
## ortho view's half diagonal, its height stretched by the pitch.
func _view_reach() -> float:
	if _camera == null:
		return INF
	if _low:
		return World.NEAR_TILES  # The screen shows further; what is kept up does not (238).
	var screen := get_viewport().get_visible_rect().size
	var half_height := _camera.size * 0.5 / maxf(sin(deg_to_rad(pitch)), 0.1)
	var half_width := _camera.size * 0.5 * screen.x / maxf(screen.y, 1.0)
	return Vector2(half_width, half_height).length()


func _shows_light(light: OmniLight3D, reach: float) -> bool:
	var at := light.global_position
	var away := Vector2(at.x - _camera_target.x, at.z - _camera_target.z).length()
	return away <= reach + light.omni_range + SHADOW_MARGIN


## Shadows on for the lights that reach the view, off for the rest, so a
## big map's many torches and lanterns hold no shadow maps for ground
## nobody is looking at (the camera's culling leaves out most of them
## already; this leaves out the rest).
func _update_shadows() -> void:
	if _camera == null or _shadow_lights.is_empty():
		return
	var reach := _view_reach()
	var key := Vector3i(roundi(_camera_target.x), roundi(_camera_target.z), roundi(reach * 2.0))
	var now := Time.get_ticks_msec() / 1000.0
	if key == _shadow_key and now - _shadow_checked < SHADOW_RECHECK:
		return
	_shadow_key = key
	_shadow_checked = now
	var kept: Array[OmniLight3D] = []
	for light in _shadow_lights:
		if not is_instance_valid(light):
			continue
		kept.append(light)
		var shows := _shows_light(light, reach)
		if light.shadow_enabled != shows:
			light.shadow_enabled = shows
	_shadow_lights = kept


# --- Near and far ----------------------------------------------------------------

func _classify_walls() -> void:
	_update_fade(true)


## Fades what hides the local player or their companion from the camera,
## and only that: what hides them is worked out again whenever the camera or
## they have moved, and a piece that stops hiding them stays faded for
## FADE_HOLD ([param force]: every piece set again).
func _update_fade(force := false) -> void:
	if _camera == null or _room == null or not _camera.is_inside_tree():
		return
	if not _occluders_built:
		_index_occluders()
	var points := _focus_points()
	var roofs_changed := _update_roofs(points)
	var toward := _camera.global_transform.basis.z
	var fought := points + _fight_points(points)
	var key := "%s %s %s" % [toward, _camera.global_position, fought]
	if key != _fade_key or force:
		_fade_key = key
		_hiding = _hiding_pieces(fought, toward)
		_hiding.merge(_inside_walls(points, toward))
	for piece in _hiding:
		_hid_at[piece] = _fade_clock
	var now: Dictionary[Node3D, bool] = {}
	for piece: Node3D in _hid_at.keys():
		if _fade_clock - _hid_at[piece] <= FADE_HOLD:
			now[piece] = true
		else:
			_hid_at.erase(piece)
	if not force and not roofs_changed and now.size() == _faded.size() and now.keys().all(func(piece: Node3D) -> bool: return _faded.has(piece)):
		return
	for entry in _occluders:
		var piece: Node3D = entry[0]
		var fade := now.has(piece)
		if fade == _faded.has(piece) and not force:
			continue
		_set_near(piece, fade)
	_faded = now
	# A roof off draws nothing but its shadow, so the inside stays shaded.
	for building in _buildings:
		var roof: Node3D = building["roof"]
		if roof == null or not building["off"]:
			continue
		_set_near(roof, false)
		for node in _descendants(roof):
			if node is GeometryInstance3D:
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## The walls of the buildings [param points] are inside that face the
## camera ([param toward]), each with its run: the near side of the room,
## faded whether or not it hides them, so a player in a corner of it is
## not hidden by the wall beside them. A side the camera looks along is
## not near.
func _inside_walls(points: Array[Vector3], toward: Vector3) -> Dictionary[Node3D, bool]:
	var out: Dictionary[Node3D, bool] = {}
	if _buildings.is_empty():
		return out
	var flat := Vector2(toward.x, toward.z).normalized()
	var inside: Dictionary[int, bool] = {}
	for point in points:
		var at := to_local(point)
		var cell := Vector2i(roundi(at.x), roundi(at.z))
		if _building_at.has(cell):
			inside[_building_at[cell]] = true
	for index in inside:
		var rect: Rect2i = _buildings[index]["rect"]
		var cells: Dictionary = _buildings[index].get("inside", {})
		for key in _buildings[index].get("outline", Level.outline(rect)):
			if not _runs.has(key):
				continue
			var outward := Vector2(1, 0) if key.z == Terrain.EAST else Vector2(0, 1)
			# Out is toward the edge's second cell when its first is inside.
			var first := Terrain.edge_cells(key)[0]
			if not (cells.has(first) if not cells.is_empty() else rect.has_point(first)):
				outward = -outward
			if outward.dot(flat) > NEAR_SIDE:
				for piece: Node3D in _runs[key]:
					out[piece] = true
	return out


## Which buildings' roofs are off: those the local player or their
## companion ([param points]) is inside, and for FADE_HOLD after they
## leave. A roof back on is set as the fade has it. Whether any changed.
func _update_roofs(points: Array[Vector3]) -> bool:
	if _buildings.is_empty():
		return false
	for point in points:
		var at := to_local(point)
		var cell := Vector2i(roundi(at.x), roundi(at.z))
		if _building_at.has(cell):
			_roofs_off[_building_at[cell]] = _fade_clock
	var changed := false
	for index in _buildings.size():
		var off := _roofs_off.has(index) and _fade_clock - _roofs_off[index] <= FADE_HOLD
		if not off:
			_roofs_off.erase(index)
		var building := _buildings[index]
		if off == building["off"]:
			continue
		building["off"] = off
		changed = true
		if not off and building["roof"] != null:
			_set_near(building["roof"], _faded.has(building["roof"]))
	return changed


## The pieces the lines from the camera to [param points] pass through,
## with what fades with them. The camera is orthographic: its line to a
## point runs back from it along [param toward], up to the camera's plane.
## Only the pieces in the squares a line crosses below the highest top are
## tried (_occluder_chunks).
func _hiding_pieces(points: Array[Vector3], toward: Vector3) -> Dictionary[Node3D, bool]:
	var out: Dictionary[Node3D, bool] = {}
	var tried: Dictionary[int, bool] = {}
	for point in points:
		var reach := maxf((_camera.global_position - point).dot(toward), 0.0)
		if toward.y > 0.01:
			reach = minf(reach, maxf(_occluder_top - point.y, 0.0) / toward.y)
		var end := point + toward * reach
		var low := Vector2i(floori(minf(point.x, end.x) / FADE_CHUNK), floori(minf(point.z, end.z) / FADE_CHUNK))
		var high := Vector2i(floori(maxf(point.x, end.x) / FADE_CHUNK), floori(maxf(point.z, end.z) / FADE_CHUNK))
		for x in range(low.x, high.x + 1):
			for z in range(low.y, high.y + 1):
				for index: int in _occluder_chunks.get(Vector2i(x, z), []):
					tried[index] = true
	for index in tried:
		var entry := _occluders[index]
		var bounds: AABB = entry[1]
		for point in points:
			var ahead := bounds.get_center() - point
			var reach := maxf((_camera.global_position - point).dot(toward), 0.0)
			if ahead.x * toward.x + ahead.z * toward.z > 0.0 and bounds.intersects_segment(point, point + toward * reach) != null:
				for piece: Node3D in entry[3]:
					out[piece] = true
				break
	return out


## Where the local player and their companion are, at FADE_HEIGHTS: as
## drawn, or at their tile before they have a puppet.
## A grown forest's cutaway on the local player (else the view's middle),
## its near chunks round the view's middle.
func _update_grown() -> void:
	if _grown == null:
		return
	if _camera != null:
		_grown.set_see(Net.see_through * _camera.size * 0.5)
	var points := _focus_points()
	_grown.set_focus(_room.to_local(points[0]) if not points.is_empty() else _camera_target, _camera_target)


func _focus_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for entity in World.get_entities():
		if not entity.spawned:
			continue
		if not (entity is Player and entity.owner_peer == Net.local_id or entity is Companion and entity.keeper_peer == Net.local_id):
			continue
		var puppet: Node3D = _puppets.get(entity.get_instance_id())
		var at := puppet.global_position if puppet != null else to_global(_tile_position(entity.tile))
		for height in FADE_HEIGHTS:
			out.append(at + Vector3(0.0, height, 0.0))
	return out


## Where the fight's other side is, at FADE_HEIGHTS: each live monster
## drawn within FIGHT_TILES of a point of [param focus] (the player's and
## the companion's, _focus_points). None with no one to fight.
func _fight_points(focus: Array[Vector3]) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if focus.is_empty():
		return out
	var now := Time.get_ticks_msec()
	for entity in World.get_entities():
		if not entity is Monster or not entity.spawned or entity.hp <= 0:
			continue
		var id := entity.get_instance_id()
		var alert: Monster.Alert = (entity as Monster).alert
		if alert != Monster.Alert.FIGHTING and alert != Monster.Alert.HUNTING and now - _combat_at.get(id, -100000) >= COMBAT_SECONDS * 1000.0:
			continue
		var puppet: Node3D = _puppets.get(id)
		if puppet == null or not puppet.visible or _far.has(id):
			continue
		var at := puppet.global_position
		var near := false
		for i in range(0, focus.size(), FADE_HEIGHTS.size()):
			if Vector2(at.x, at.z).distance_to(Vector2(focus[i].x, focus[i].z)) <= FIGHT_TILES:
				near = true
				break
		if near:
			for height in FADE_HEIGHTS:
				out.append(at + Vector3(0.0, height, 0.0))
	return out


func _index_occluders() -> void:
	_occluders.clear()
	var runs := _wall_runs()
	_runs = runs
	# A run of wall is one node for all its edges (_add_wall_runs), but
	# what hides the player is still asked edge by edge, by the edge's own
	# bounds: a run's would reach far past the player either way.
	for key: Vector3i in _walls:
		var bounds := _bounds(_walls[key]) if BOX_WALLS else _edge_bounds(key)
		_occluders.append([_walls[key], bounds, false, runs[key]])
	var framed: Dictionary[Node3D, bool] = {}
	for key: Vector3i in _doorways:
		var frame := _doorways[key].get_node(DOOR_FRAME) as Node3D
		if not framed.has(frame):  # A double door's two edges: one frame.
			framed[frame] = true
			_occluders.append([frame, _bounds(frame), false, runs[key]])
	for post: Node3D in _posts.values():
		_occluders.append([post, _bounds(post), false, [post]])
	for tree: Node3D in _trees.values() + _saplings.values():
		_occluders.append([tree, _bounds(tree), true, [tree]])
	for props: Array in _clearing_props.values():
		for prop: Node3D in props:
			if prop.has_meta(&"fades"):
				_occluders.append([prop, _bounds(prop), true, [prop]])
	# A roof between the camera and a player outside fades as a wall does.
	for building in _buildings:
		if building["roof"] != null:
			_occluders.append([building["roof"], _bounds(building["roof"]), false, [building["roof"]]])
	_occluder_chunks.clear()
	_occluder_top = 0.0
	for index in _occluders.size():
		var bounds: AABB = _occluders[index][1]
		_occluder_top = maxf(_occluder_top, bounds.end.y)
		for x in range(floori(bounds.position.x / FADE_CHUNK), floori(bounds.end.x / FADE_CHUNK) + 1):
			for z in range(floori(bounds.position.z / FADE_CHUNK), floori(bounds.end.z / FADE_CHUNK) + 1):
				var chunk := Vector2i(x, z)
				if not _occluder_chunks.has(chunk):
					_occluder_chunks[chunk] = []
				_occluder_chunks[chunk].append(index)
	_occluders_built = true


## For each wall and doorway edge, the pieces of its run: the walls and
## doorway frames in a straight line with it, and the posts along and at
## the ends of that line, up to where it turns, ends or another wall meets
## it (a room's side, not the whole castle's).
func _wall_runs() -> Dictionary[Vector3i, Array]:
	var out: Dictionary[Vector3i, Array] = {}
	var standing := func(key: Vector3i) -> bool: return _walls.has(key) or _doorways.has(key)
	for start: Vector3i in _walls.keys() + _doorways.keys():
		if out.has(start):
			continue
		var edges: Array[Vector3i] = [start]
		var vertices: Array[Vector2i] = []
		for end in 2:
			var key := start
			var at := end
			while true:
				var vertex := WallEdge.vertex_at(key, at)
				vertices.append(vertex)
				var meeting := 0
				for entry: Array in WallEdge.edges_at_vertex(vertex):
					if standing.call(entry[0]):
						meeting += 1
				var along := Vector3i(0, 1 if at == 0 else -1, 0) if key.z == Terrain.EAST else Vector3i(-1 if at == 0 else 1, 0, 0)
				var next := key + along
				if meeting > 2 or not standing.call(next) or next in edges:
					break
				edges.append(next)
				key = next
		var pieces: Array = []
		for key in edges:
			var piece: Node3D = _walls[key] if _walls.has(key) else _doorways[key].get_node(DOOR_FRAME)
			if not pieces.has(piece):
				pieces.append(piece)
		for vertex in vertices:
			if _posts.has(vertex) and not pieces.has(_posts[vertex]):
				pieces.append(_posts[vertex])
		for key in edges:
			out[key] = pieces
	return out


## A wall edge's own share of its run: its set's thickness across, the
## edge along, its height (_height_of) up from its base.
func _edge_bounds(key: Vector3i) -> AABB:
	var middle := _edge_midpoint(key) + Vector3(0.0, _edge_base(key), 0.0)
	var across: float = _wall_set(_set_of(key))["half"]
	var half := Vector3(across, 0.0, 0.5) if key.z == Terrain.EAST else Vector3(0.5, 0.0, across)
	return AABB(middle - half, half * 2.0 + Vector3(0.0, _height_of(key), 0.0))


## [param piece]'s meshes' bounds, in the world.
func _bounds(piece: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in _descendants(piece):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var box := mesh.global_transform * mesh.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## A near piece (a wall, a door's frame, a post, a tree between the camera
## and the player) is see-through and casts no shadow, so a lantern behind
## it still lights the floor in front; else as modelled. Every material
## under [param piece] is swapped for its see-through copy (_see_through_of):
## an override (a grey box, a flat box) as the mesh's override, kept in its
## OPAQUE_META to go back to; a surface's own as the surface's override.
func _set_near(piece: Node3D, near: bool) -> void:
	for node in _descendants(piece):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		if mesh.material_override != null or mesh.has_meta(OPAQUE_META):
			if not mesh.has_meta(OPAQUE_META):
				mesh.set_meta(OPAQUE_META, mesh.material_override)
			var own: Material = mesh.get_meta(OPAQUE_META)
			mesh.material_override = _see_through_of(own) if near else own
		else:
			# Its own overrides (its season's) kept, and put back after.
			if not mesh.has_meta(OPAQUE_SURFACES_META):
				var kept: Array[Material] = []
				for surface in mesh.mesh.get_surface_count():
					kept.append(mesh.get_surface_override_material(surface))
				mesh.set_meta(OPAQUE_SURFACES_META, kept)
			var opaque: Array[Material] = mesh.get_meta(OPAQUE_SURFACES_META)
			for surface in mesh.mesh.get_surface_count():
				var own: Material = opaque[surface] if opaque[surface] != null else mesh.mesh.surface_get_material(surface)
				mesh.set_surface_override_material(surface, _see_through_of(own) if near and own != null else opaque[surface])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if near \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Under the low camera, [param puppet] drawn or not by whether its body
## is [param within] World.NEAR_TILES: a change eases over REACH_EASE from
## [param now] (ms), its meshes' transparency rising as it leaves and
## falling as it comes, hidden only once gone; a puppet just [param made]
## is simply drawn or not.
func _ease_reach(puppet: Node3D, within: bool, made: bool, now: int) -> void:
	if made or not puppet.has_meta("reach_in"):
		puppet.set_meta("reach_in", within)
		puppet.visible = within
		return
	if bool(puppet.get_meta("reach_in")) != within:
		puppet.set_meta("reach_in", within)
		puppet.set_meta("reach_at", now)
		puppet.visible = true
	if not puppet.has_meta("reach_at"):
		return
	var share := clampf((now - int(puppet.get_meta("reach_at"))) / (REACH_EASE * 1000.0), 0.0, 1.0)
	if share >= 1.0:
		puppet.remove_meta("reach_at")
		_set_transparency(puppet, 0.0 if within else 1.0)
		puppet.visible = within
		return
	_set_transparency(puppet, 1.0 - share if within else share)


## Every drawn part of [param puppet] (its meshes, its name, its bar) at
## [param transparency] (0 solid, 1 gone).
func _set_transparency(puppet: Node3D, transparency: float) -> void:
	for node in _descendants(puppet):
		if node is GeometryInstance3D:
			(node as GeometryInstance3D).transparency = transparency


# --- Entities ----------------------------------------------------------------

## One puppet per spawned entity, placed where its 2D node is (the grid
## position under the azimuth-0 projection), turned to its shown facing,
## removed when it goes.
func _sync_puppets() -> void:
	var seen: Dictionary[int, bool] = {}
	var now := Time.get_ticks_msec()
	var reach := maxf(_view_reach() + PUPPET_MARGIN, Sfx.MAX_DISTANCE) if _camera != null else INF
	var aim := Vector2(_camera_target.x, _camera_target.z)
	var frame := Engine.get_process_frames()
	# World's own list, not a copy: nothing here spawns or despawns.
	for entity in World.entities():
		if not entity.spawned:
			continue
		var id := entity.get_instance_id()
		seen[id] = true
		if (id + frame) % FAR_EVERY != 0 and _far.has(id):
			# Far off when last looked at: looked at again every FAR_EVERY
			# frames (a big map holds thousands of them).
			continue
		var made := not _puppets.has(id)
		if not made and not _far.has(id) and Vector2(entity.tile).distance_to(aim) <= reach 				and _puppets[id].get_meta("body", &"") != body_of(entity):
			# Its body came after it did (a client hears it a moment later).
			if _puppets[id] == _outlined:
				target(null)
			_puppets[id].queue_free()
			made = true
		if made:
			_puppets[id] = _make_puppet(entity)
		var puppet := _puppets[id]
		if not made and Vector2(entity.tile).distance_to(aim) > reach:
			# Far off: unseen and unheard. Its tile and hp are kept, so it
			# makes no footstep for the way it came and its bar shows a
			# fight it had, when it comes near. Its puppet (animation,
			# skeleton) and its entity's drawing are stopped meanwhile: a
			# thousand idle animations a frame were most of a big map's
			# frame.
			if not _far.has(id):
				puppet.process_mode = Node.PROCESS_MODE_DISABLED
				entity.set_process(false)
			_far[id] = true
			_last_tile[id] = entity.tile
			if _last_hp.get(id, entity.hp) != entity.hp:
				_combat_at[id] = now
			_last_hp[id] = entity.hp
			continue
		if _far.has(id):
			_far.erase(id)
			puppet.remove_meta("last_at")  # Not a run from where it was last drawn.
			puppet.process_mode = Node.PROCESS_MODE_INHERIT
			entity.set_process(true)
			entity._display_caught_up()
		if _low:
			# The low camera sees past World.NEAR_TILES: a body out there is
			# not drawn (it would stand still, unthinking, 238); one crossing
			# the edge eases in or out (REACH_EASE).
			_ease_reach(puppet, Vector2(entity.tile).distance_to(aim) <= World.NEAR_TILES, made, now)
		var grid := Iso.local_to_grid(entity.position)
		var at := Vector3(grid.x, _ground_height(grid), grid.y)
		if puppet.position != at:
			puppet.position = at
		var yaw := _sleeping_yaw(entity, _tending_yaw(entity, _aimed_yaw(entity, -entity.shown_facing().angle())))
		var facing := puppet.get_node_or_null("Facing") as Node3D
		# (Angles kept as float32: compared near enough, not ==.)
		if facing != null:
			if not entity is Monster and work_word(entity) != "sleep_side":  # Asleep, laid down at once.
				yaw = _standing_turn(puppet, facing.rotation.y, yaw)
			if not is_equal_approx(facing.rotation.y, yaw):
				facing.rotation.y = yaw
		_sync_held(entity, puppet)
		_sync_worn(entity, puppet)
		if entity is Resident:
			_sync_addressing(entity as Resident, puppet)
			_sync_work(entity as Resident, puppet)
		elif entity is Player or entity is Companion:
			_sync_work(entity, puppet)  # Its bandaging (the kneel); a companion's sleep.
		_sync_bow(entity, puppet)
		if entity is Player:
			var lantern := puppet.get_node_or_null("Lantern") as Node3D
			if lantern != null and lantern.visible != (entity.emit_light > 0.0):
				lantern.visible = entity.emit_light > 0.0  # Covered (L).
		elif entity is Monster:
			_sync_alert(entity as Monster, puppet)
			_sync_chatter(entity as Monster, puppet)
		_sync_down(entity, puppet)
		if (entity is Player or entity is Companion) and bool(puppet.get_meta("downed", false)) != World.is_downed(entity):
			puppet.set_meta("downed", World.is_downed(entity))  # Its fall, if it comes, a bleed-out (628).
		_sync_draw(entity, puppet)
		_sync_ailments(entity, puppet)
		_sync_name(entity, puppet, now)
		if puppet.has_meta("rig"):
			var body := puppet.get_node("Body") as Node3D
			_lay(puppet, body, yaw, entity.tile)
			if not is_equal_approx(body.rotation.y, yaw):
				body.rotation.y = yaw
			(puppet.get_meta("rig") as AnimRig).every = _pose_every(puppet)
			_animate(puppet)
		elif puppet.has_meta("creature_view"):
			var body := puppet.get_node("Body") as Node3D
			if not is_equal_approx(body.rotation.y, yaw):
				body.rotation.y = yaw
			var view := puppet.get_meta("creature_view") as CreatureView
			if view.rig != null:
				view.rig.every = _pose_every(puppet)
			view.frame(puppet, entity as Monster)
		_sync_bar(entity, puppet, now)
		_step_sound(entity, puppet)
	for id in _puppets.keys():
		if not seen.has(id):
			_entity_went(id)


## The entity of puppet [param id] is gone: it falls if its death has come;
## otherwise it is kept still a moment in case its death is on its way.
func _entity_went(id: int) -> void:
	var puppet: Node3D = _puppets[id]
	_puppets.erase(id)
	_stop_creak(puppet)
	if puppet == _outlined:
		target(null)
	_combat_at.erase(id)
	_last_hp.erase(id)
	_last_tile.erase(id)
	_far.erase(id)
	var entity_name: String = puppet.get_meta("entity_name", "")
	if _pending_deaths.has(entity_name):
		_fall(puppet, _pending_deaths[entity_name])
		_pending_deaths.erase(entity_name)
	else:
		_departed[entity_name] = {"puppet": puppet, "at": Time.get_ticks_msec()}


func _drop_departed() -> void:
	var now := Time.get_ticks_msec()
	for entity_name: String in _departed.keys():
		if now - int(_departed[entity_name]["at"]) >= DEPARTED_SECONDS * 1000.0:
			(_departed[entity_name]["puppet"] as Node3D).queue_free()
			_departed.erase(entity_name)


## The HP bar: its fill and colour from the hp, and whether it shows: hurt,
## in a fight lately, or Alt held; faded either way.
func _sync_bar(entity: GridEntity, puppet: Node3D, now: int) -> void:
	var bar := puppet.get_node_or_null("HpBar") as MeshInstance3D
	if bar == null:
		return
	var id := entity.get_instance_id()
	if _last_hp.get(id, entity.hp) != entity.hp:
		_combat_at[id] = now
	_last_hp[id] = entity.hp
	var share := clampf(float(entity.hp) / maxf(entity.max_hp, 1.0), 0.0, 1.0)
	var material := bar.material_override as ShaderMaterial
	var wanted := 0.0
	if Net.hp_bars and (show_all_bars or share < 1.0 or now - _combat_at.get(id, -100000) < COMBAT_SECONDS * 1000.0):
		wanted = 1.0
	var alpha := move_toward(float(material.get_shader_parameter("alpha")), wanted, get_process_delta_time() * HP_BAR_FADE)
	material.set_shader_parameter("alpha", alpha)
	material.set_shader_parameter("fill", share)
	material.set_shader_parameter("fill_color", hp_color(share))
	bar.visible = alpha > 0.001


## The bar's colour for [param share] of hp left.
static func hp_color(share: float) -> Color:
	if share < HP_RED:
		return HP_RED_COLOR
	if share < HP_AMBER:
		return HP_AMBER_COLOR
	return HP_GREEN_COLOR


## A footstep when a creature's replicated tile moves on by one.
func _step_sound(entity: GridEntity, puppet: Node3D) -> void:
	var id := entity.get_instance_id()
	var last: Vector2i = _last_tile.get(id, entity.tile)
	_last_tile[id] = entity.tile
	if entity.is_creature() and last != entity.tile and World.distance(last, entity.tile) == 1:
		# A ford (decision 505) is waded, though it isn't deep water.
		var wet := World.is_water(entity.tile) or World.is_ford(entity.tile)
		var ground: String = "water" if wet else _ground_kinds.get(entity.tile, "stone")
		var creature := str(entity.spawn_spec.get("kind", "")) if entity is Monster else ""
		sfx.play(SoundKit.footstep(ground, entity.mass, creature), puppet.position, 1.0, 0.0, Senses.step_radius(entity))
		if rustles(entity.tile, _flattened.get(entity.tile, -FLATTENED_MS), Time.get_ticks_msec()):
			sfx.play("sfx.grass_rustle", puppet.position, 1.0, 0.0, Senses.step_radius(entity))


## Whether a step into [param tile] rustles: standing tall grass (decision
## 508), or tall grass flattened at [param flattened] (ms) within
## FLATTENED_MS of [param now] (that step's own trampling).
static func rustles(tile: Vector2i, flattened: int, now: int) -> bool:
	return World.cover_at(tile) > 0.0 or World.is_tall_grass(tile) and now - flattened < FLATTENED_MS


## Tall grass trampled ([param flat], flat [x, y, ...]) noted for
## rustles(); a full "grass" message (both empty) notes nothing. Its clumps
## are laid flat, and those [param stood] stood again.
func _on_grass_changed(_level: String, flat: PackedInt32Array, stood: PackedInt32Array) -> void:
	var now := Time.get_ticks_msec()
	var changed: Array[Vector2i] = []
	for i in range(0, flat.size() - 1, 2):
		_flattened[Vector2i(flat[i], flat[i + 1])] = now
		changed.append(Vector2i(flat[i], flat[i + 1]))
	for i in range(0, stood.size() - 1, 2):
		changed.append(Vector2i(stood[i], stood[i + 1]))
	# The drawn tall grass (decision 508, terrain's side): the cells told,
	# or after a full set (both empty) every clump, laid flat or stood.
	_show_trampled(_tall_where.keys() if flat.is_empty() and stood.is_empty() else changed)
	for cell: Vector2i in _flattened.keys():
		if now - _flattened[cell] >= FLATTENED_MS:
			_flattened.erase(cell)


## A blow landed: a thud on flesh for an attack (an impact makes its own
## sound, and fire has none yet). A shot's lands when its arrow gets there
## (_arrows), not when the sim's news does (decision 390).
func _on_struck(_amount: int, cause: StringName, id: int) -> void:
	if cause == &"shot":
		var target := instance_from_id(id) as GridEntity
		var flying := _arrow_to(target.tile) if target != null else {}
		if not flying.is_empty():
			var wait: int = int(flying["arrive"]) - Time.get_ticks_msec()
			if wait > 0:
				get_tree().create_timer(wait / 1000.0).timeout.connect(_on_struck.bind(_amount, cause, id))
				return
	_combat_at[id] = Time.get_ticks_msec()
	var puppet: Node3D = _puppets.get(id)
	if puppet != null and cause != &"impact":
		_play_once(puppet, _pick_clip(puppet, HIT_CLIPS))  # An impact is shown by _on_impacted.
		if puppet.has_meta("creature_view"):
			(puppet.get_meta("creature_view") as CreatureView).hit()
	if puppet != null and cause == &"shot":
		var shot := instance_from_id(id) as GridEntity
		sfx.play("sfx.arrow_hit_flesh", puppet.position + Vector3.UP * 0.8)
		_pain(shot, puppet)
	if puppet != null and cause == &"attack":
		var struck := instance_from_id(id) as GridEntity
		sfx.play(_struck_with(struck), puppet.position + Vector3.UP * 0.8)
		_pain(struck, puppet)
		if music != null and struck != null and sfx.listener != null and _cells_apart(struck.tile, sfx.listener) <= Music.TENSION_NEAR:
			music.fight_near()


## Pushed [param tiles]: a model is knocked back (_animate), a backpedal or,
## for a toss, a roll, once the slide shows.
func _on_pushed(tiles: int, id: int) -> void:
	_combat_at[id] = Time.get_ticks_msec()
	var puppet: Node3D = _puppets.get(id)
	var entity := instance_from_id(id) as GridEntity
	if entity != null and tiles > 0:
		# Shoved into water: a splash as it lands there.
		get_tree().create_timer(SLIDE_SECONDS).timeout.connect(func() -> void:
			if is_instance_valid(entity) and is_instance_valid(sfx) and sfx.is_inside_tree() and World.is_water(entity.tile):
				sfx.play("sfx.splash", _tile_position(entity.tile)))
	if puppet == null or entity == null or tiles <= 0 or not puppet.has_meta("rig"):
		return
	if puppet.has_meta("knock"):
		var knock: Dictionary = puppet.get_meta("knock")
		if not knock.get("ending", false) and absf(angle_difference(float(knock["yaw"]),
				-(-Vector2(entity.push_direction)).angle())) < 0.01 and Time.get_ticks_msec() - int(knock["since"]) < 500:
			# The same knock, already under way (a guessed shove the server
			# then did otherwise, the same way): it goes on.
			return
	# Facing whence it came, the way the sim says it was pushed, whatever the
	# slide on screen does.
	puppet.set_meta("knock", {"toss": entity.tossed, "impact": false, "since": Time.get_ticks_msec(), "started": -1,
			"yaw": -(-Vector2(entity.push_direction)).angle(), "shown": (puppet.get_node("Body") as Node3D).rotation.y})


## An impact: the sound of what it hit; into a wall or a door (or the
## ground, falling), a model doubles over: at the end of its slide if it is
## knocked back, else now.
func _on_impacted(_amount: int, against: StringName, id: int) -> void:
	_combat_at[id] = Time.get_ticks_msec()
	var puppet: Node3D = _puppets.get(id)
	if puppet == null:
		return
	if against == &"stone" or against == &"wood":
		if puppet.has_meta("knock"):
			(puppet.get_meta("knock") as Dictionary)["impact"] = true
		else:
			_play_once(puppet, CLIP_IMPACT)
	elif against == &"body":
		_play_once(puppet, _pick_clip(puppet, HIT_CLIPS))
	var at := puppet.position + Vector3.UP * 0.6
	match against:
		&"stone":
			sfx.play("sfx.knockback_stone", at)
		&"wood":
			sfx.play("sfx.knockback_wood", at)
		&"body":
			sfx.play("sfx.knockback_body", at)
			sfx.play("sfx.knockback_body_soft", at)


## The server's "death" message: the puppet falls now if its entity has
## gone, or when it goes. A broken thing just breaks.
func on_death(data: Dictionary) -> void:
	var entity_name := str(data.get("entity", ""))
	if str(data.get("kind", "")) == "object":
		var tile: Variant = data.get("tile")
		var at := Vector3(tile[0], 0.4, tile[1]) if tile is Array and tile.size() == 2 else _camera_target
		sfx.play(_break_sounds.get(entity_name, "sfx.break_wood"), at)
		_break_sounds.erase(entity_name)
		return
	if _departed.has(entity_name):
		_fall(_departed[entity_name]["puppet"], data)
		_departed.erase(entity_name)
		return
	for id: int in _puppets:
		if _puppets[id].get_meta("entity_name", "") == entity_name:
			_pending_deaths[entity_name] = data
			return


## A monster's name with how alert it is (Monster.Alert): "?" looking into
## something, "!" after someone, "~" running.
## Knocked down (GridEntity.down_until; decision 343): the body tips over
## to lie on the ground, and rises again when it wears off.
func _sync_down(entity: GridEntity, puppet: Node3D) -> void:
	var body := puppet.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var lying := World.tick + World.tick_alpha < entity.down_until
	if lying != bool(puppet.get_meta("lying", false)):
		puppet.set_meta("lying", lying)
		if lying:
			sfx.play("sfx.knockdown", puppet.position + Vector3.UP * 0.3)
	var want := DOWN_TILT if lying else 0.0
	if not is_equal_approx(body.rotation.x, want):
		body.rotation.x = move_toward(body.rotation.x, want, get_process_delta_time() * DOWN_TILT_SPEED)


## Burning or bleeding (GridEntity.ailments; decision 375): its name
## tinted, orange for fire, red for blood, white again when it ends.
func _sync_ailments(entity: GridEntity, puppet: Node3D) -> void:
	var label := puppet.get_node_or_null("Name") as Label3D
	if label == null:
		return
	var tint := AIL_BURN if entity.ailments.has("burn") else AIL_BLEED if entity.ailments.has("bleed") else Color.WHITE
	if label.modulate != tint:
		label.modulate = tint


## Its name under the low camera (NAME_TILES): sized to read at its depth,
## the nearest over the farther, shown past NAME_TILES only for the party,
## a foe or the marked target. Nothing under the ortho camera.
func _sync_name(entity: GridEntity, puppet: Node3D, now: int) -> void:
	if not _low or _camera == null:
		return
	var label := puppet.get_node_or_null("Name") as Label3D
	if label == null:
		return
	var depth := maxf((label.global_position - _camera.global_position).dot(-_camera.global_transform.basis.z), 0.0)
	label.scale = Vector3.ONE * maxf(1.0, depth / maxf(_camera_distance(), 1.0))
	label.render_priority = clampi(100 - roundi(depth), -100, 100)
	label.visible = not label.text.is_empty() and name_shown(entity, puppet, now)


## Whether [param entity]'s name shows under the low camera: within
## NAME_TILES of the local player (or the camera's aim with none); past
## that only the party's, a foe's (as _fight_points counts one) or the
## marked target's.
func name_shown(entity: GridEntity, puppet: Node3D, now: int) -> bool:
	if entity is Player or entity is Companion or puppet == _outlined:
		return true
	var own := _local_player()
	var from := Vector2(_camera_target.x, _camera_target.z)
	if own != null and _puppets.has(own.get_instance_id()):
		var at: Vector3 = _puppets[own.get_instance_id()].global_position
		from = Vector2(at.x, at.z)
	if Vector2(puppet.global_position.x, puppet.global_position.z).distance_to(from) <= NAME_TILES:
		return true
	if entity is Monster:
		var alert: Monster.Alert = (entity as Monster).alert
		if alert == Monster.Alert.FIGHTING or alert == Monster.Alert.HUNTING:
			return true
		if now - _combat_at.get(entity.get_instance_id(), -100000) < COMBAT_SECONDS * 1000.0:
			return true
	return false


func _sync_alert(monster: Monster, puppet: Node3D) -> void:
	var was := int(puppet.get_meta("alert", Monster.Alert.IDLE))
	if was == monster.alert:
		return
	puppet.set_meta("alert", monster.alert)
	if was == Monster.Alert.IDLE and monster.alert == Monster.Alert.SUSPICIOUS:
		# Its head comes up: a deer snorts (the stalker's cue to freeze).
		var slot := SoundKit.cry(str(puppet.get_meta("creature", "")), "suspicious")
		if slot != "":
			sfx.play(slot, puppet.position + Vector3.UP * 0.8)
	var label := puppet.get_node_or_null("Name") as Label3D
	if label == null:
		return
	var marks := {Monster.Alert.SUSPICIOUS: " ?", Monster.Alert.HUNTING: " !", Monster.Alert.FIGHTING: " !",
		Monster.Alert.FLEEING: " ~"}
	label.text = str(puppet.get_meta("caption", label.text)) + str(marks.get(monster.alert, ""))


## A corpse: it tips onto its side with a bounce, flashes, drops its
## lantern, lies a while, sinks into the floor and is gone. Nothing of it
## can be picked; its name and bar go at once.
func _fall(puppet: Node3D, data: Dictionary) -> void:
	puppet.name = "Corpse_" + str(data.get("entity", ""))
	puppet.set_meta("corpse", true)
	for part: String in ["Pick", "HpBar", "Name"]:
		var node := puppet.get_node_or_null(part)
		if node != null:
			puppet.remove_child(node)
			node.queue_free()
	var kind := str(data.get("kind", "monster"))
	var death_slot: String = DEATH_SOUNDS.get(kind, "sfx.goblin_death")
	if kind == "monster":
		death_slot = SoundKit.death(str(puppet.get_meta("creature", "")))
	# A player or companion who lay downed (Mortally Wounded) and bled out
	# breathes their last (628, Jeff: "the scream on bleed out is not a good
	# fit"); a sudden death keeps the blow and the cry.
	var bled: bool = kind in ["player", "companion"] and bool(puppet.get_meta("downed", false))
	if not bled:
		sfx.play(death_slot, puppet.position + Vector3.UP * 0.5)
	# Their body's voice (decision 388), kept on the puppet: the entity may be gone.
	var voice := "voice.%s_%s" % ["last_breath" if bled else "death", puppet.get_meta("body", "male" if kind == "player" else "female")] if kind in ["player", "companion"] else ""
	if voice != "":
		sfx.play(voice, puppet.position + Vector3.UP * 1.5)
	_play_later("sfx.bodyfall", puppet.position, FALL_SECONDS * 0.75)
	var lantern := puppet.get_node_or_null("Lantern") as OmniLight3D
	if lantern != null:
		lantern.reparent(self)
		var drop := create_tween().set_parallel(true)
		drop.tween_property(lantern, "position:y", 0.2, FALL_SECONDS).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		drop.tween_property(lantern, "light_energy", 0.0, LANTERN_OUT_SECONDS)
		drop.chain().tween_callback(lantern.queue_free)
	var body := puppet.get_node_or_null("Body") as MeshInstance3D
	if body != null and body.material_override is StandardMaterial3D:
		var material := body.material_override as StandardMaterial3D
		var glow := material.emission
		material.emission = FLASH
		create_tween().tween_property(material, "emission", glow, FLASH_SECONDS)
	var line := str(data.get("say", ""))
	if not line.is_empty() and bubbles != null:
		puppet.set_meta("bubble_height", 1.0)
		bubbles.show_line(puppet.get_instance_id(), line)
	# A model plays its death and lies where it fell; the rest go over onto
	# their side, a touch too far, back, and still.
	if puppet.has_meta("knock"):
		puppet.remove_meta("knock")
	var dying := (puppet.get_meta("creature_view") as CreatureView).die() if puppet.has_meta("creature_view") else 0.0
	if dying > 0.0:
		# A creature plays its death and lies where it fell, as a model does.
		var lies := create_tween()
		lies.tween_interval(CORPSE_SECONDS + dying)
		lies.tween_property(puppet, "position:y", -SINK_DEPTH, SINK_SECONDS).set_ease(Tween.EASE_IN)
		lies.tween_callback(puppet.queue_free)
		return
	var death := _pick_clip(puppet, DEATH_CLIPS)
	if _play_once(puppet, death):
		puppet.set_meta("busy_until", 1 << 62)
		var lie := create_tween()
		lie.tween_interval(CORPSE_SECONDS + (puppet.get_meta("rig") as AnimRig).length(death))
		lie.tween_property(puppet, "position:y", -SINK_DEPTH, SINK_SECONDS).set_ease(Tween.EASE_IN)
		lie.tween_callback(puppet.queue_free)
		if kind == "player" and str(data.get("entity", "")) == _local_name:
			_mourn_local()
		return
	var side := PI * 0.5
	var fall := create_tween()
	fall.set_parallel(true)
	fall.tween_property(puppet, "rotation:z", side * 1.08, FALL_SECONDS * 0.75).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fall.tween_property(puppet, "position:y", FALL_LIFT, FALL_SECONDS * 0.75)
	fall.chain().tween_property(puppet, "rotation:z", side * 0.97, FALL_SECONDS * 0.15)
	fall.chain().tween_property(puppet, "rotation:z", side, FALL_SECONDS * 0.1)
	fall.chain().tween_interval(CORPSE_SECONDS)
	fall.chain().tween_property(puppet, "position:y", FALL_LIFT - SINK_DEPTH, SINK_SECONDS).set_ease(Tween.EASE_IN)
	fall.chain().tween_callback(puppet.queue_free)
	if kind == "player" and str(data.get("entity", "")) == _local_name:
		_mourn_local()


## The local player has died: mourning (_update_mourning) and its stinger.
func _mourn_local() -> void:
	_mourning = true
	if music != null:
		music.sting("death")


## What a blow on [param struck] sounds like: the weapon of whoever swung
## beside it just now (_swings; a person's, whose hands are known), else
## the plain hit.
func _struck_with(struck: GridEntity) -> String:
	if struck == null:
		return "sfx.hit_flesh"
	var now := Time.get_ticks_msec()
	var best := -1
	var best_cells := BLOW_REACH + 1
	for swinger_id: int in _swings:
		var swinger := instance_from_id(swinger_id) as GridEntity
		if swinger == null or swinger == struck or now - int(_swings[swinger_id][0]) > BLOW_AFTER_MS:
			continue
		var cells := _cells_apart(swinger.tile, struck.tile)
		if cells < best_cells:
			best = swinger_id
			best_cells = cells
	if best < 0:
		return "sfx.hit_flesh"
	var by := instance_from_id(best) as GridEntity
	if not (by is Player or by is Companion):
		return "sfx.hit_flesh"  # A monster's hands aren't sent to clients.
	return SoundKit.hit(str(_swings[best][1]))


## [param struck] cries out at a blow: a person's grunt now and then, a
## goblin's yelp, pitched by its kind.
func _pain(struck: GridEntity, puppet: Node3D) -> void:
	var voice := SoundKit.voice(struck, "effort_hurt")
	if voice != "":
		sfx.play(voice, puppet.position + Vector3.UP * 1.5)
		return
	var creature := str(puppet.get_meta("creature", ""))
	if struck is Monster and not struck is Animal and creature in SoundKit.GOBLINS and randi() % PAIN_EVERY == 0:
		sfx.play("sfx.goblin_pain", puppet.position + Vector3.UP * 0.8, float(SoundKit.CREATURE_PITCH.get(creature, 1.0)))


## A goblin standing idle mutters now and then (heard by players only:
## its slot carries no noise).
func _sync_chatter(monster: Monster, puppet: Node3D) -> void:
	if monster is Animal or monster.alert != Monster.Alert.IDLE or str(puppet.get_meta("creature", "")) not in SoundKit.GOBLINS:
		return
	var now := Time.get_ticks_msec()
	if not puppet.has_meta("chatter_at"):
		puppet.set_meta("chatter_at", now + int(randf_range(CHATTER_SECONDS.x, CHATTER_SECONDS.y) * 1000.0))
	elif now >= int(puppet.get_meta("chatter_at")):
		puppet.set_meta("chatter_at", now + int(randf_range(CHATTER_SECONDS.x, CHATTER_SECONDS.y) * 1000.0))
		sfx.play("sfx.goblin_chatter", puppet.position + Vector3.UP * 0.8,
				float(SoundKit.CREATURE_PITCH.get(str(puppet.get_meta("creature", "")), 1.0)))


## [param slot] at [param at] after [param seconds] (a body landing as its
## fall ends).
func _play_later(slot: String, at: Vector3, seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(sfx) and sfx.is_inside_tree():
			sfx.play(slot, at))


## A person's bow drawn (raised "draw", replicated for players): the
## creak once as the stance begins, then the bow's creak held while it stays
## drawn, its pitch and level rising with World.draw_of (decision 475).
func _sync_draw(entity: GridEntity, puppet: Node3D) -> void:
	var drawing := entity.raised == "draw"
	var at := puppet.position + Vector3.UP * 1.2
	if drawing != bool(puppet.get_meta("drawing", false)):
		puppet.set_meta("drawing", drawing)
		if drawing:
			sfx.play("sfx.bow_draw", at)
	var creak := puppet.get_meta("creak") as AudioStreamPlayer3D if puppet.has_meta("creak") else null
	if not drawing:
		_stop_creak(puppet)
		return
	if creak == null or not is_instance_valid(creak):
		creak = sfx.hold("sfx.bow_creak", at)
		if creak == null:
			return
		puppet.set_meta("creak", creak)
	var tune := creak_tune(World.draw_of(entity))
	sfx.steer(creak, at, tune.x, tune.y)


## The held creak's pitch (x) and level over its slot's in dB (y) at
## [param draw] (0..1): low and faint as the string comes back, high and
## full at the jaw.
static func creak_tune(draw: float) -> Vector2:
	return Vector2(lerpf(CREAK_PITCH.x, CREAK_PITCH.y, draw), lerpf(CREAK_DB.x, CREAK_DB.y, draw))


## The bow's held creak stopped: loosed, or the draw let down.
func _stop_creak(puppet: Node3D) -> void:
	if not puppet.has_meta("creak"):
		return
	var creak := puppet.get_meta("creak") as AudioStreamPlayer3D
	if creak != null and is_instance_valid(creak):
		creak.queue_free()
	puppet.remove_meta("creak")


## The arrow in flight to [param cell] not yet heard, marked heard now; {}
## for none.
func _arrow_to(cell: Vector2i) -> Dictionary:
	for arrow: Dictionary in _arrows:
		if arrow["end"] == cell and not arrow["heard"]:
			arrow["heard"] = true
			return arrow
	return {}


## What an arrow's end sounds like by what stopped it (the sim's struck,
## decision 583): wood, stone, or, its range spent, the ground or water at
## [param cell]; a body's hit is _on_struck's.
static func _shot_sound(struck: StringName, cell: Vector2i, from := Vector2i(2147483647, 0), trees: Dictionary = {}) -> String:
	match struck:
		&"wood":
			return "sfx.arrow_hit_wood"
		&"stone":
			# A forest's edge is stone to the sim but a tree to the ear (609): _arrow_landed's look past it.
			if from.x != 2147483647 and _arrow_landed(from, cell, trees) == "sfx.arrow_hit_wood":
				return "sfx.arrow_hit_wood"
			return "sfx.arrow_hit_stone"
	return "sfx.arrow_water" if World.is_water(cell) else "sfx.arrow_land"


## What an arrow from [param from] that stopped at [param end] without
## striking anyone sounds like, by what lies past it along the shot
## (World.shot_line's stops): a closed door's or a tree's wood (a cell of
## [param trees], the forest's, by the cell past it), a wall's or higher
## ground's stone, water's plip, else the arrow coming down in the ground at
## its range's end.
static func _arrow_landed(from: Vector2i, end: Vector2i, trees: Dictionary = {}) -> String:
	if World.is_water(end):
		return "sfx.arrow_water"
	var d := end - from
	var longest := maxi(absi(d.x), absi(d.y))
	if longest == 0:
		d = Vector2i(1, 0)
		longest = 1
	var step := Vector2i(roundi(float(d.x) / longest), roundi(float(d.y) / longest))
	var edges: Array[Vector2i] = [step]
	if step.x != 0 and step.y != 0:
		edges = [Vector2i(step.x, 0), Vector2i(0, step.y)]
	var wall := false
	for edge: Vector2i in edges:
		match World.edge_kind(end, edge):
			Terrain.Edge.DOOR:
				var door := World.door_across(end, edge)
				if door != null and not door.is_open():
					return "sfx.arrow_hit_wood"
			Terrain.Edge.WALL:
				wall = true
	var past := end + step
	if not wall and not World.is_walkable(past) and not World.is_water(past):
		for x in range(-1, 2):
			for y in range(-1, 2):
				if trees.has(past + Vector2i(x, y)):
					return "sfx.arrow_hit_wood"
	if wall or World.height_at(past) > World.height_at(from) or not (World.is_walkable(past) or World.is_water(past)):
		return "sfx.arrow_hit_stone"
	return "sfx.arrow_land"


## Cells between [param a] and [param b], Chebyshev (as hearing counts).
static func _cells_apart(a: Vector2i, b: Variant) -> int:
	var to: Vector2i = b
	return maxi(absi(a.x - to.x), absi(a.y - to.y))


## The local player dead: pull back and drain the colour, slowly; back as
## soon as they are.
func _update_mourning(delta: float) -> void:
	if _mourning and _local_player() != null and _puppets.has(_local_player().get_instance_id()):
		_mourning = false
	var target := 1.0 if _mourning else 0.0
	var seconds := MOURN_SECONDS if _mourning else MOURN_RETURN_SECONDS
	var before := _mourn
	_mourn = move_toward(_mourn, target, delta / seconds)
	var downed := _local_player() != null and World.is_downed(_local_player())
	var down_before := _down
	_down = move_toward(_down, 1.0 if downed else 0.0, delta / (MOURN_SECONDS if downed else MOURN_RETURN_SECONDS))
	if is_equal_approx(before, _mourn) and _mourn == 0.0 and is_equal_approx(down_before, _down) and _down == 0.0:
		return
	_environment.adjustment_saturation = lerpf(1.0, MOURN_SATURATION, smoothstep(0.0, 1.0, maxf(_mourn, _down)))
	_apply_size()


## The art slot [param entity] is drawn as (its spawn spec's "art": a crate,
## a chest, a boulder, a cart), once that slot has art of its own; "" while
## it has none, and the entity is its shape, tinted, as before (decision 264).
static func art_slot_for(entity: GridEntity) -> String:
	var slot := str(entity.spawn_spec.get("art", ""))
	if slot == "" or not ArtKit.has(slot) or ArtKit.filled_by(slot) != "own":
		return ""
	return slot


## The creature slot [param entity] is drawn from (decision 359): its kind's
## "art" (Monster.art_of: creature.boar for a boar, the wilds' animals of
## decision 319) once that slot has art of its own, played by a
## CreatureView; "" while it has none, and it is its shape, as before.
static func creature_slot_for(entity: GridEntity) -> String:
	if not entity is Monster:
		return ""
	var slot := Monster.art_of(str(entity.spawn_spec.get("kind", "")))
	if slot == "" or not ArtKit.has(slot) or str(ArtKit.spec(slot).get("kind", "")) != "creature" or ArtKit.filled_by(slot) != "own":
		return ""
	return slot


## The model for [param entity]: HUMAN or HUMAN_F by its look's body for a
## person (a player, a companion, a resident, or a monster whose kind is drawn
## as one: person_words), MODELS' entry for a monster of a kind that has one,
## or {}.
static func model_for(entity: GridEntity) -> Dictionary:
	var kind := str(entity.spawn_spec.get("kind", ""))
	if entity is Resident and MODELS.has(kind):
		# A goblin among the townsfolk (decision 471, Snagfin): its kind's body, at home in
		# town, bare-headed (494's hood down).
		var model: Dictionary = MODELS[kind].duplicate()
		model["at_home"] = true
		return model
	if entity is Player or entity is Companion or entity is Resident or not person_words(entity).is_empty():
		return HUMAN_F if look_for(entity).body == &"female" else HUMAN
	if not entity is Monster:
		return {}
	return MODELS.get(str(entity.spawn_spec.get("kind", "")), {})


## The model as the puppet's Body: the scene turned to face +X (as the
## nose does, so Body turns with the facing; MODELS' "faces"), with an AnimationPlayer on
## its root playing its clips through an AnimRig of its own (decision 390),
## kept as the puppet's "rig"; its fight's clips (a model's "moves") as its
## "moves".
func _make_model(model: Dictionary, puppet: Node3D) -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	var scene := (load(model["scene"]) as PackedScene).instantiate() as Node3D
	scene.name = "Model"
	scene.rotation.y = float(model.get("faces", 0.0))
	body.add_child(scene)
	scene.scale = Vector3.ONE * float(puppet.get_meta("model_scale", 1.0))
	# A body's fixed parts (belt, boots) on art-kit's palette, as its pieces are.
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var own := mesh.mesh.surface_get_material(surface)
			if own != null and own.resource_name == ArtKit.PALETTE_NAME:
				mesh.set_surface_override_material(surface, load(ArtKit.PALETTE))
			elif own != null and own.resource_name == GHOST_MATERIAL:
				mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if model.get("parts", false):
		# A person's tunic in their colour; an ally's in its look's.
		var tunic: Color = Color.WHITE if model.has("people") else puppet.get_meta("tint", Color.WHITE)
		_dress(scene, tunic)
		if puppet.has_meta("look"):
			(puppet.get_meta("look") as PersonLook).apply(scene, tunic)
	if model.has("paint"):
		# Its own paint (decision 529): its people's material, its variation as the goblin's is.
		var look := painted_look(str(puppet.get_meta("entity_name", "")))
		puppet.set_meta("painted_look", look)
		scene.scale = Vector3(scene.scale.x * float(look["width"]), scene.scale.y, scene.scale.z * float(look["width"]))
		# (Its own material where this build lacks the paint: no error, as warm_painted.)
		var paint := load(str(model["paint"])) as Material if ResourceLoader.exists(str(model["paint"])) else null
		for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			_paint_skin(mesh, paint)
			mesh.set_instance_shader_parameter("skin", look["skin"])
			mesh.set_instance_shader_parameter("gear", Color(1.0, 1.0, 1.0, 0.0))
			mesh.set_instance_shader_parameter("mark", look["mark"])
	if model.get("goblin", false):
		# Its own goblin (decision 494): the shared material, its variation as instance parameters.
		var look := goblin_look(str(puppet.get_meta("entity_name", "")))
		if model.get("at_home", false) and look["hood"]:
			look["hood"] = false
			look["words"] = (str(look["words"]) + " hood=down").strip_edges()
		puppet.set_meta("goblin_look", look)
		scene.scale = Vector3(scene.scale.x * float(look["width"]), scene.scale.y, scene.scale.z * float(look["width"]))
		for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = GOBLIN_MATERIAL
			mesh.set_instance_shader_parameter("skin", look["skin"])
			mesh.set_instance_shader_parameter("gear", look["gear"])
			mesh.set_instance_shader_parameter("mark", look["mark"])
			if mesh.name == "Hood":
				mesh.visible = look["hood"]
			var ears := float(look["ears"])
			for key: String in ["Ears_Big", "Ears_Small"]:
				var index := mesh.find_blend_shape_by_name(key)
				if index >= 0:
					mesh.set_blend_shape_value(index, maxf(ears, 0.0) if key == "Ears_Big" else maxf(-ears, 0.0))
	if model.has("tint"):
		_tint(scene, str(model["tint"]), puppet.get_meta("tint", Color.WHITE))
	puppet.set_meta("gaits", model.get("gaits", GAITS))
	puppet.set_meta("backpedal", float(model.get("backpedal", BACKPEDAL_CLIP_SPEED)))
	puppet.set_meta("fidgets", model.get("fidgets", FIDGETS))
	puppet.set_meta("moves", model.get("moves", {}))
	var rig := AnimRig.make(scene, load(model["clips"]) as AnimationLibrary, CLIP_BLEND, true,
			puppet.get_meta("rng") if puppet.has_meta("rng") else null)
	rig.loop(CLIP_IDLE)
	if model.has("sockets"):
		_attach_sockets(scene, model["sockets"], float(puppet.get_meta("model_scale", 1.0)), puppet)
		_wear_hat(scene, puppet)
	if puppet.has_meta("look") and not model.has("paint"):
		# (A painted ally's mesh stands in its concept's stance already: no second hunch.)
		var posture := str(POSTURES.get((puppet.get_meta("look") as PersonLook).posture, ""))
		if posture != "" and rig.has(posture):
			rig.posture((load(model["clips"]) as AnimationLibrary).get_animation(posture), 1.0)
	puppet.set_meta("rig", rig)
	return body


## [param scene]'s attach points (decision 451): a BoneAttachment3D on its
## skeleton for each socket's bone, the socket a node under it at its place
## in the bone's frame, scaled back by [param model_scale] so what it holds
## keeps its own size; kept as the puppet's "sockets" {name: Node3D}.
static func _attach_sockets(scene: Node3D, sizes: Dictionary, model_scale: float, puppet: Node3D) -> void:
	var skeletons := scene.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var made := {}
	var table := _sockets(sizes["hand"], sizes["hip"], sizes["back"], sizes["chest"])
	var shoulder := _shoulder_socket(skeleton, sizes["hand"])
	if not shoulder.is_empty():
		table["shoulder"] = shoulder
	var crown := _head_socket(skeleton) if sizes.get("crown", false) else []
	if not crown.is_empty():
		table["head"] = crown
	for name: String in table:
		var bone: String = table[name][0]
		if skeleton.find_bone(bone) < 0:
			continue
		var on := BoneAttachment3D.new()
		on.name = "On" + bone
		on.bone_name = bone
		skeleton.add_child(on)
		var socket := Node3D.new()
		socket.name = name
		socket.transform = table[name][1]
		if name == "arm_l" and skeleton.find_bone("LeftHand") >= 0:
			socket.position = skeleton.get_bone_rest(skeleton.find_bone("LeftHand")).origin * 0.5
		socket.scale = Vector3.ONE / maxf(model_scale, 0.01)
		on.add_child(socket)
		made[name] = socket
	puppet.set_meta("sockets", made)
	puppet.set_meta("held", ["", ""])
	if made.has("hand_r") and made.has("hand_l") and skeleton.find_bone("LeftUpperArm") >= 0 and skeleton.find_bone("LeftLowerArm") >= 0:
		# The left hand on a two-handed piece's second grip (451 amended (2), step 4), off till one is held.
		puppet.set_meta("reach", HandReach.make(skeleton, (made["hand_r"] as Node3D).transform, (made["hand_l"] as Node3D).transform))


## What [param entity] holds in each hand drawn at its puppet's hand sockets
## (decision 451): each thing from its art slot (ArtKit: its own art, a
## fill, or a grey box sized as the slot is until it has art), swapped when
## the slot changes, gone when the hand empties. An archer's arrows aren't in
## its hand but in a quiver on its back (decision 462 amended (3)).
## A held weapon (art_style: its length +y, its edge, head or point's
## striking side +x, thin in z) is turned a quarter about its grip
## (HELD_EDGE_TURN): the hand socket puts a piece's +x out of the palm, so
## each edge faced across the body and the flat into the swing (Jeff: "great
## axe ... held sideways by player and draugr"); turned, +x lies along the
## fingers toward the knuckles, the way the hand swings. A shield keeps its
## own turn, the bow none; a work's tool is turned by its clip (GRASP).
const HELD_EDGE_TURN := Basis(Vector3.UP, -PI * 0.5)
## Where a shield's strap is in its own frame (art-kit's "strap" socket:
## the forearm's axis at its middle, behind the back face), SHIELD_STRAP when
## its slot names none.
const SHIELD_STRAP := Vector3(0.0, -0.06, -0.075)
static func _strap_of(art: String) -> Vector3:
	var at: Variant = ArtKit.spec(art).get("sockets", {}).get("strap")
	return Vector3(at[0], at[1], at[2]) if at is Array and at.size() == 3 else SHIELD_STRAP
static func _edge_first(id: String) -> bool:
	var tags: Array = Items.def(id).get("tags", [])
	return "weapon" in tags and not "ranged" in tags and not "shield" in tags
func _sync_held(entity: GridEntity, puppet: Node3D) -> void:
	if not puppet.has_meta("sockets"):
		return
	var held: Array = puppet.get_meta("held")
	var sockets: Dictionary = puppet.get_meta("sockets")
	var ids := held_ids(entity)
	var work := work_of(entity)
	if work.has("right") and ids[0] == "":
		ids[0] = ART_ID + str(work["right"])
	if work.has("left") and ids[1] == "":
		ids[1] = ART_ID + str(work["left"])
	_sync_load(puppet, sockets, str(work.get("shoulder", "")))
	var quiver := ""
	if World.drawn_with(entity) != "" and ARROW_VARIANTS.has(ids[0]):
		quiver = ids[0]
		ids[0] = ""
	if quiver != str(puppet.get_meta("quiver", "")):
		puppet.set_meta("quiver", quiver)
		var back := sockets.get("back") as Node3D
		if back != null:
			var old := back.get_node_or_null("Quiver")
			if old != null:
				back.remove_child(old)
				old.queue_free()
			if quiver != "" and ArtKit.has(QUIVER):
				var piece := ArtKit.instance(QUIVER, int(ARROW_VARIANTS[quiver]))
				piece.name = "Quiver"
				back.add_child(piece)
	var changed := false
	for hand in 2:
		var id: String = ids[hand]
		if id == held[hand]:
			continue
		held[hand] = id
		changed = true
		var socket := sockets.get("hand_r" if hand == 0 else "hand_l") as Node3D
		if socket == null:
			continue
		var places: Array = [socket] if hand == 0 or not sockets.has("arm_l") else [socket, sockets["arm_l"]]
		for place: Node3D in places:
			for old in place.get_children():
				# Out of the way now, so the new thing is the one named "Held".
				place.remove_child(old)
				old.queue_free()
		if id == "":
			continue
		var own := id.begins_with(ART_ID)
		var art := id.substr(ART_ID.length()) if own else str(Items.def(id).get("art", "item." + id))
		if ArtKit.has(art):
			var thing := ArtKit.instance(art)
			thing.name = "Held"
			if not own and "shield" in Items.def(id).get("tags", []) and sockets.has("arm_l"):
				# Strapped on the outside of the forearm (451 amended (2); Jeff: "shield
				# should be carried on the outside of arm, not inside"): the arm_l
				# socket's frame is the shield's, so its strap point goes on the
				# forearm's middle.
				socket = sockets["arm_l"]
				thing.position = -_strap_of(art)
			elif not own and "shield" in Items.def(id).get("tags", []):
				# A body with no forearm socket: out of the back of the hand, a quarter
				# turn about its grip's axis (its face +z, art_style).
				thing.basis = Basis(Vector3.UP, PI * 0.5)
			elif not own and _edge_first(id):
				thing.basis = HELD_EDGE_TURN
			if own and hand == 0:
				_grip(thing, work)
			socket.add_child(thing)
	if changed and puppet.has_meta("reach"):
		_sync_reach(puppet.get_meta("reach") as HandReach, sockets, ids)


## The left hand brought to the right hand's piece's second grip (HandReach;
## 451 amended (2), step 4) while the left hand is empty, the piece takes two
## hands and its art has one ("grip_2", art-kit's sockets: the giant axe's and
## the battle axe's, 0.45 m up) within REACH_SPAN of its grip: the two-handed
## clips (Axe_Ready, Axe_Overhead) hold the hands humanoid_clips' GREAT_GRIP
## (0.45 m) apart, and farther the left arm can't reach it from them (0.3 m
## short at 0.87), so a wider grip keeps the clip's left hand.
## A work's own tool keeps its clip's hands (humanoid_clips authors both).
const REACH_SPAN := 0.6
static func _sync_reach(reach: HandReach, sockets: Dictionary, ids: Array) -> void:
	var held := (sockets["hand_r"] as Node3D).get_node_or_null("Held") as Node3D
	var id := str(ids[0])
	var second: Variant = null
	if held != null and str(ids[1]) == "" and id != "" and not id.begins_with(ART_ID) and int(Items.def(id).get("hands", 1)) == 2:
		second = ArtKit.spec(str(Items.def(id).get("art", "item." + id))).get("sockets", {}).get("grip_2")
	if second is Array and (second as Array).size() == 3 and Vector3(second[0], second[1], second[2]).length() <= REACH_SPAN:
		reach.reach(true, held.transform, Vector3(second[0], second[1], second[2]))
	else:
		reach.reach(false)


## The armour [param entity] wears (items' 622; a player's and a
## companion's worn item, a resident's look's worn= word) drawn on its
## body (PersonLook.wear), when it changes.
func _sync_worn(entity: GridEntity, puppet: Node3D) -> void:
	if not puppet.has_meta("look"):
		return
	var look := puppet.get_meta("look") as PersonLook
	var id := str(entity.get("worn")) if "worn" in entity else ""
	var key := id if not id.is_empty() else look.worn
	var model := puppet.get_node_or_null("Body/Model") as Node3D
	if model == null or key == str(model.get_meta("worn", "")):
		return
	model.set_meta("worn", key)  # On the model: a body made again wears it again.
	look.wear(model, id)


## A carried lantern as it hangs at the belt: a small dark frame round a
## warm glow, below the socket.
static var _lantern_parts: Array = []
static func _hanging_lantern() -> Node3D:
	if _lantern_parts.is_empty():
		var frame := BoxMesh.new()
		frame.size = Vector3(0.09, 0.13, 0.09)
		var iron := StandardMaterial3D.new()
		iron.albedo_color = Color(0.16, 0.14, 0.12)
		iron.roughness = 0.8
		var glow := BoxMesh.new()
		glow.size = Vector3(0.1, 0.08, 0.1)
		var flame := StandardMaterial3D.new()
		flame.albedo_color = PLAYER_LIGHT
		flame.emission_enabled = true
		flame.emission = PLAYER_LIGHT
		flame.emission_energy_multiplier = 1.5
		_lantern_parts = [frame, iron, glow, flame]
	var lantern := Node3D.new()
	lantern.name = "LanternBody"
	for i in 2:
		var piece := MeshInstance3D.new()
		piece.mesh = _lantern_parts[i * 2]
		piece.material_override = _lantern_parts[i * 2 + 1]
		piece.position = Vector3(0.0, 0.1, 0.0)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if i == 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		lantern.add_child(piece)
	return lantern


## The arrows' kinds as their nocked arrow's and their quiver's variants
## (fx.arrow, gear.quiver); an archer's quiver on its back socket (462 amended (3)).
const ARROW_VARIANTS := {"arrows": 1, "arrows_flame": 2, "arrows_barbed": 3}
const QUIVER := "gear.quiver"


## What [param entity] holds as drawn [right hand, left hand]: its hand
## slots, but a bow (World.drawn_slot) always in the left and the other
## hand's thing (its arrows) in the right, as a right-handed archer holds
## them (decision 462).
static func held_ids(entity: GridEntity) -> Array:
	var right := entity.slots[Items.RIGHT_HAND] if entity.slots.size() > Items.RIGHT_HAND else ""
	var left := entity.slots[Items.LEFT_HAND] if entity.slots.size() > Items.LEFT_HAND else ""
	if World.drawn_slot(entity) == Items.RIGHT_HAND:
		return [left, right]
	return [right, left]


## How far into Bow_Draw [param entity]'s pose is (0 to 1), scrubbed by the
## sim's draw (decision 462): before the draw counts (draw_of 0, until its
## draw_min) the nock, the clip's first BOW_NOCK_END, by the ticks toward
## draw_min; then the pull, the rest of the clip, by World.draw_of from
## where it starts (draw_min over draw_full) to 1. Carried on between ticks
## by World.tick_alpha, so it moves every frame, not ten times a second.
const BOW_NOCK_END := 0.3
static func bow_pull(entity: GridEntity) -> float:
	var verb := Items.verb_of(World.drawn_with(entity))
	if verb.is_empty() or entity.raised != "draw":
		return 0.0
	var quick := World.draw_quick(entity)  # A quick bow's, and the armour's (decision 622, step 2).
	var least := roundi(int(verb.get("draw_min", 0)) * quick)
	var full := World.draw_full_ticks(entity)
	var drawn := World.tick - entity.raised_tick
	var progress := World.draw_of(entity)
	if progress <= 0.0:
		return BOW_NOCK_END * clampf((drawn + World.tick_alpha) / maxf(1.0, least), 0.0, 1.0)
	progress = minf(1.0, progress * (drawn + World.tick_alpha) / maxf(1.0, drawn))
	var start := least / full
	return BOW_NOCK_END + (1.0 - BOW_NOCK_END) * clampf((progress - start) / maxf(0.001, 1.0 - start), 0.0, 1.0)


## A bow's look on its puppet (decision 462), from what the sim replicates
## (items' signals): a bow in hand and nothing raised, Bow_Idle on the upper
## layer; raised "draw", Bow_Draw held at bow_pull (the arm drawing back as
## World.draw_of grows), then Bow_Hold once it reaches 1; the
## shot (_on_shot), Bow_Loose; a draw let go with no shot, back to Bow_Idle. A
## raised shield ("block") holds the guard (Block_Idle) on the upper layer.
## Walking or running with the bow down ("carry", 462 amended (3)) the upper
## layer lets go: both arms swing with the gait, the bow in the left hand.
## Standing with a two-handed piece the left hand is on (HandReach, 451
## amended (2), step 4), its ready stance ("ready", Axe_Ready) on the upper
## layer, both hands before the body on the haft (standing idle only).
## While drawn the drawing hand shows one arrow (fx.arrow, its kind's
## variant) on the bow's string, the string pulled back to that hand.
func _sync_bow(entity: GridEntity, puppet: Node3D) -> void:
	if not puppet.has_meta("rig") or not puppet.has_meta("sockets"):
		return
	var rig := puppet.get_meta("rig") as AnimRig
	var moves: Dictionary = puppet.get_meta("moves", {})
	if moves.is_empty():
		return
	var ids := held_ids(entity)
	var bow := World.drawn_with(entity)
	var state := str(puppet.get_meta("bow_state", ""))
	var now := Time.get_ticks_msec()
	var want := ""
	if entity.raised == "block":
		want = "block"
	elif bow != "" and entity.raised == "draw":
		want = "hold" if World.draw_of(entity) >= 1.0 else "draw"
	elif bow != "":
		want = "loose" if state == "loose" and now < int(puppet.get_meta("bow_until", 0)) else "idle"
		if want == "idle" and (puppet.get_meta("gaits", GAITS) as Array).any(
				func(gait: Array) -> bool: return gait[0] == rig.base_clip()):
			want = "carry"
	elif puppet.has_meta("reach") and (puppet.get_meta("reach") as HandReach).active and rig.base_clip() == CLIP_IDLE:
		want = "ready"  # Standing only: not over a gait, a lying body or a kneel.
	if want == "draw":
		var clip := str(moves.get("bow_draw", ""))
		rig.upper_at(clip, bow_pull(entity) * rig.length(clip))
	elif want != state:
		match want:
			"hold":
				rig.upper(str(moves.get("bow_aim", "")))
			"idle":
				rig.upper(str(moves.get("bow_idle", "")))
			"block":
				rig.upper(str(moves.get("block", "")))
			"ready":
				rig.upper(str(moves.get("ready", "")))
			"", "carry":
				rig.upper_off()
	puppet.set_meta("bow_state", want)
	if bow != "":
		_turn_carried(puppet, want == "carry", now)
	_show_nocked(puppet, ids, want in ["draw", "hold"])


## The bow as it's carried at a walk or run (462 amended (3)): a quarter turn
## in the hand and out from it a little, so its limbs clear the hip and leg as
## the arm swings (no vertex inside the body through the gaits, five builds,
## anim_rig_test); turned to it and back over about BOW_TURN_SECONDS.
const BOW_CARRY := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.04, 0.0, 0.0))
const BOW_TURN_SECONDS := 0.2
func _turn_carried(puppet: Node3D, carried: bool, now: int) -> void:
	var bow := ((puppet.get_meta("sockets") as Dictionary)["hand_l"] as Node3D).get_node_or_null("Held") as Node3D
	var then := int(puppet.get_meta("bow_turned_at", now))
	puppet.set_meta("bow_turned_at", now)
	if bow == null:
		return
	var want := BOW_CARRY if carried else Transform3D.IDENTITY
	if bow.transform.is_equal_approx(want):
		return
	var step := 1.0 - exp(-(now - then) / 1000.0 * 5.0 / BOW_TURN_SECONDS)
	bow.transform = bow.transform.interpolate_with(want, clampf(step, 0.0, 1.0))
	if bow.transform.origin.distance_to(want.origin) < 0.002 and bow.basis.get_rotation_quaternion().angle_to(want.basis.get_rotation_quaternion()) < 0.02:
		bow.transform = want


## While drawn, one arrow on the bow's string at its nock, the string pulled
## back toward the drawing hand; let go, the arrow gone and the string
## springing back (bow_string).
const NOCKED_TURN := Basis(Vector3.RIGHT, PI * 0.5)
func _show_nocked(puppet: Node3D, ids: Array, drawn: bool) -> void:
	var sockets: Dictionary = puppet.get_meta("sockets")
	var bow := (sockets["hand_l"] as Node3D).get_node_or_null("Held") as Node3D
	if bow == null:
		return
	var string := bow.find_child("string", true, false) as Node3D
	var arrow := bow.find_child("Nocked", true, false) as Node3D
	if string != null and not string.has_meta("rest"):
		_string_segments(string)
	# The limbs bend only near the camera (BOW_FLEX_RANGE): a raid's far
	# archers keep the rigid bow, their strings still drawn.
	var flex := _camera == null or puppet.global_position.distance_to(_camera_target) <= BOW_FLEX_RANGE
	if not drawn:
		if arrow != null:
			arrow.queue_free()
		if string != null and string.has_meta("pulled"):
			# Let go: the spring from where it was drawn to.
			string.set_meta("loosed", [Time.get_ticks_msec(), float(string.get_meta("pulled"))])
			string.remove_meta("pulled")
		if string != null and string.has_meta("loosed"):
			var loosed: Array = string.get_meta("loosed")
			var at := (Time.get_ticks_msec() - int(loosed[0])) / 1000.0
			var rest: Vector3 = string.get_meta("rest")
			string.position = rest + Vector3(0.0, 0.0, bow_string(float(loosed[1]), at))
			if at >= STRING_SETTLE:
				string.remove_meta("loosed")
			_string_bend(string, flex)
		return
	if arrow == null and ArtKit.has("fx.arrow"):
		arrow = ArtKit.instance("fx.arrow", int(ARROW_VARIANTS.get(str(ids[0]), 1)))
		arrow.name = "Nocked"
		# Its notch at the nock, its head (+y) toward the target (the bow's +z). On the
		# string's parent, kept at the string below, never under the string itself: the art's
		# string box is hidden for the drawn segments (_string_segments), and the arrow went with it
		# (Jeff: "the arrow doesn't load into the bow with drawing").
		arrow.basis = NOCKED_TURN
		var nock := bow.find_child("nock", true, false) as Node3D
		(string.get_parent() if string != null else nock if nock != null else bow).add_child(arrow)
	if string != null:
		# Back toward the drawing hand, never past it nor forward of the brace,
		# nor further than a bow draws (BOW_DRAW_MAX: a pose not yet applied).
		var hand := (string.get_parent() as Node3D).global_transform.affine_inverse() * (sockets["hand_r"] as Node3D).global_position
		var rest: Vector3 = string.get_meta("rest")
		string.position = Vector3(rest.x, rest.y, clampf(hand.z, rest.z - BOW_DRAW_MAX, rest.z))
		string.set_meta("pulled", rest.z - string.position.z)
		if string.has_meta("loosed"):
			string.remove_meta("loosed")
		_string_bend(string, flex)
		if arrow != null:
			arrow.transform = string.transform * Transform3D(NOCKED_TURN, Vector3.ZERO)


## The string's nock point [param seconds] after a draw of [param pulled] m
## was let go, along the bow's z from its brace (+ toward the target): back
## to the brace in STRING_SNAP, a quarter swing; then a damped ring about it
## (STRING_HZ, damped by STRING_DAMPING) whose first swing past the brace is
## STRING_OVERSHOOT of the draw, never more than STRING_OVERSHOOT_MAX; still
## after STRING_SETTLE. A function of the time alone, so a long frame can't
## throw it further than the swing itself goes.
const STRING_SNAP := 0.03
const STRING_HZ := 9.0
const STRING_DAMPING := 0.2
const STRING_OVERSHOOT := 0.12
const STRING_OVERSHOOT_MAX := 0.05
const STRING_SETTLE := 0.4
static func bow_string(pulled: float, seconds: float) -> float:
	if seconds >= STRING_SETTLE or pulled <= 0.0:
		return 0.0
	if seconds < STRING_SNAP:
		return -pulled * cos(PI * 0.5 * seconds / STRING_SNAP)
	var omega := TAU * STRING_HZ
	var t := seconds - STRING_SNAP
	var ring := minf(pulled * STRING_OVERSHOOT, STRING_OVERSHOOT_MAX)
	return ring * exp(-STRING_DAMPING * omega * t) * sin(omega * sqrt(1.0 - STRING_DAMPING * STRING_DAMPING) * t)


## The bow art's "string" part (a straight box tip to tip, its pivot at the
## nock) drawn instead as two thin segments, tip to nock and nock to tip
## (462 amended (3)), so a drawn string bends at the hand: the box hidden,
## the tips read off its bounds, the segments closed boxes of its own
## thickness and material (seen from every side), every corner on the
## string's own swatch (its first vertex's UV). Kept as the string's metas
## "rest", "tips" and "segments"; the bow's own meshes as "limbs" (_bow_limbs).
static var _string_boxes := {}
static func _string_segments(string: Node3D) -> void:
	string.set_meta("rest", string.position)
	var boxes := string.find_children("*", "MeshInstance3D", true, false)
	var box := string as MeshInstance3D if string is MeshInstance3D else (boxes.front() as MeshInstance3D if not boxes.is_empty() else null)
	if box == null:
		return
	var parent := string.get_parent() as Node3D
	var to_parent := parent.global_transform.affine_inverse() * box.global_transform
	var bounds := box.get_aabb()
	var middle := bounds.get_center()
	var top := to_parent * Vector3(middle.x, bounds.end.y, middle.z)
	var bottom := to_parent * Vector3(middle.x, bounds.position.y, middle.z)
	var width := (to_parent.basis * Vector3(minf(bounds.size.x, bounds.size.z), 0.0, 0.0)).length()
	var uv := Vector2.ZERO
	if box.mesh != null and box.mesh.get_surface_count() > 0:
		var uvs: Variant = box.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		if uvs is PackedVector2Array and not (uvs as PackedVector2Array).is_empty():
			uv = (uvs as PackedVector2Array)[0]
	if not _string_boxes.has(uv):
		var arrays := BoxMesh.new().get_mesh_arrays()
		var flat := PackedVector2Array()
		flat.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		flat.fill(uv)
		arrays[Mesh.ARRAY_TEX_UV] = flat
		var made := ArrayMesh.new()
		made.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_string_boxes[uv] = made
	var segments: Array[MeshInstance3D] = []
	for i in 2:
		var piece := MeshInstance3D.new()
		piece.name = "StringSegment%d" % i
		piece.mesh = _string_boxes[uv]
		piece.material_override = box.get_active_material(0)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(piece)
		segments.append(piece)
	box.visible = false
	string.set_meta("tips", [top, bottom, maxf(width, 0.002)])
	string.set_meta("segments", segments)
	string.set_meta("limbs", _bow_limbs(parent, string, box, maxf(absf(top.y), absf(bottom.y))))
	_string_bend(string)


## The bow's own meshes (everything under [param bow] but its string), each
## given its own copy of its mesh to bend (462 amended (4)), made once and
## freed with the bow: per surface [the copy, its surface, its vertex buffer
## as the art has it, the buffer's stride and the position's offset in it,
## the vertices that move (beyond the grip), where they are, how far out each
## is (the square, and the cube signed by the side), the bow's -z and -y in
## the mesh's frame]. A bend writes only the moving positions into a copy of
## the buffer, not a new mesh. [param reach]: the limb's length, grip to tip.
static func _bow_limbs(bow: Node3D, string: Node3D, box: MeshInstance3D, reach: float) -> Array:
	var limbs := []
	var grip := reach * BOW_GRIP
	for piece: MeshInstance3D in bow.find_children("*", "MeshInstance3D", true, false):
		if piece == box or string.is_ancestor_of(piece) or piece.name.begins_with("StringSegment") or piece.mesh == null:
			continue
		var to_bow := bow.global_transform.affine_inverse() * piece.global_transform
		var back := to_bow.affine_inverse().basis
		var own := ArrayMesh.new()
		for i in piece.mesh.get_surface_count():
			var arrays := piece.mesh.surface_get_arrays(i)
			own.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
			own.surface_set_material(i, piece.mesh.surface_get_material(i))
			var data := RenderingServer.mesh_get_surface(own.get_rid(), i)
			var format := int(data["format"])
			var count := int(data["vertex_count"])
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var moving := PackedInt32Array()
			var squares := PackedFloat32Array()
			var cubes := PackedFloat32Array()
			for v in points.size():
				var at := to_bow * points[v]
				var out := clampf((absf(at.y) - grip) / maxf(reach - grip, 0.001), 0.0, 1.0)
				if out > 0.0:
					moving.append(v)
					squares.append(out * out)
					cubes.append(signf(at.y) * out * out * out)
			limbs.append([own, i, data["vertex_data"], RenderingServer.mesh_surface_get_format_vertex_stride(format, count),
				RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_VERTEX), moving, points, squares, cubes,
				back * Vector3.BACK, back * Vector3.UP])
		piece.mesh = own
		# Bent, it reaches a little past the art's bounds: not culled for it.
		piece.custom_aabb = own.get_aabb().grow(BOW_BEND * 2.0)
	return limbs


## Where a point of the bow (in its frame: limbs along y from the grip at the
## origin, the target toward +z) is when its limbs are bent [param bend] m at
## the tips toward the string (-z; below 0, forward): nothing within the grip
## (BOW_GRIP of the limb's length), then a curve growing as the square of the
## way out to the tip, its height drawn in so the limb keeps its length.
## [param reach] is the limb's length, grip to tip.
const BOW_BEND := 0.05
const BOW_GRIP := 0.12
const BOW_DRAW := 0.45
const BOW_DRAW_MAX := 0.75
## The least change of the bend written again (m): half a millimetre.
const BOW_BEND_STEP := 0.0005
## How near the camera's mark an archer's limbs bend (m).
const BOW_FLEX_RANGE := 14.0
static func bent(point: Vector3, bend: float, reach: float) -> Vector3:
	var grip := reach * BOW_GRIP
	var out := clampf((absf(point.y) - grip) / maxf(reach - grip, 0.001), 0.0, 1.0)
	if out <= 0.0 or is_zero_approx(bend):
		return point
	var shorter := 2.0 * bend * bend / (3.0 * maxf(reach - grip, 0.001))
	return point + Vector3(0.0, -signf(point.y) * shorter * out * out * out, -bend * out * out)


## The limbs bent as the string is drawn: BOW_BEND at the tips at a draw of
## BOW_DRAW m (no more past it), none at rest, a little forward as the string
## rings past the brace; the art's own positions again once it's still. Only
## the moving positions written, into a copy of the buffer (bent's sums, in
## the mesh's frame).
static func _bend_limbs(string: Node3D, bend: float, reach: float) -> void:
	var was := float(string.get_meta("bent", 0.0))
	# Not again for less than BOW_BEND_STEP, but always back to straight.
	if absf(bend - was) < BOW_BEND_STEP and not (bend == 0.0 and was != 0.0):
		return
	string.set_meta("bent", bend)
	var grip := reach * BOW_GRIP
	var shorter := 2.0 * bend * bend / (3.0 * maxf(reach - grip, 0.001))
	for limb: Array in string.get_meta("limbs", []):
		var buffer: PackedByteArray = (limb[2] as PackedByteArray).duplicate()
		var stride: int = limb[3]
		var offset: int = limb[4]
		var moving: PackedInt32Array = limb[5]
		var points: PackedVector3Array = limb[6]
		var squares: PackedFloat32Array = limb[7]
		var cubes: PackedFloat32Array = limb[8]
		var toward: Vector3 = limb[9]
		var up: Vector3 = limb[10]
		if not is_zero_approx(bend):
			for k in moving.size():
				var v := moving[k]
				var at := points[v] - toward * (bend * squares[k]) - up * (shorter * cubes[k])
				var byte := v * stride + offset
				buffer.encode_float(byte, at.x)
				buffer.encode_float(byte + 4, at.y)
				buffer.encode_float(byte + 8, at.z)
		RenderingServer.mesh_surface_update_vertex_region((limb[0] as ArrayMesh).get_rid(), limb[1], 0, buffer)


## The two segments from the tips to the string's nock as it is now, the
## limbs bent by how far the nock is back of its brace (462 amended (4));
## kept straight unless [param flex].
static func _string_bend(string: Node3D, flex := true) -> void:
	if not string.has_meta("segments"):
		return
	var tips: Array = string.get_meta("tips")
	var nock := string.position
	var segments: Array = string.get_meta("segments")
	var width: float = tips[2]
	var rest: Vector3 = string.get_meta("rest", nock)
	var reach := maxf(absf((tips[0] as Vector3).y), absf((tips[1] as Vector3).y))
	var bend := BOW_BEND * clampf((rest.z - nock.z) / BOW_DRAW, -0.3, 1.0) if flex else 0.0
	_bend_limbs(string, bend, reach)
	for i in 2:
		var tip: Vector3 = bent(tips[i], bend, reach)
		var along := tip - nock
		var length := maxf(along.length(), 0.001)
		var up := along / length
		var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
		(segments[i] as MeshInstance3D).transform = Transform3D(
			Basis(side * width, up * length, side.cross(up).normalized() * width), (nock + tip) * 0.5)


## A human body's meshes in HUMAN_MATERIAL, each part in its own colour (its
## mesh's extras, as tools/body_build.py wrote them), the tunic in
## [param tunic] unless that is white (no colour of its own).
static func _dress(scene: Node3D, tunic: Color) -> void:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = HUMAN_MATERIAL
		var own: Dictionary = mesh.get_meta("extras", {})
		for part: String in HUMAN_PARTS:
			if own.has(part):
				mesh.set_instance_shader_parameter(part, Color(str(own[part])))
		if tunic != Color.WHITE:
			mesh.set_instance_shader_parameter("tunic", tunic)


## Each surface of [param scene]'s meshes whose material is named
## [param material] drawn in [param colour] instead (a copy of it).
static func _tint(scene: Node3D, material: String, colour: Color) -> void:
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var own := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			if own != null and own.resource_name == material:
				var tinted := own.duplicate() as BaseMaterial3D
				tinted.albedo_color = colour
				mesh.set_surface_override_material(surface, tinted)


## Two goblins for the warm-up (warm_ups, decision 495; 494 amended): one in
## GOBLIN_MATERIAL, one in its hover outline's stencil twin, skinned and
## casting shadows as in play, so the first hover on a goblin does not stall
## a frame compiling the twin (20.6 ms, cold, before).
static func warm_goblin() -> Node3D:
	var piece := Node3D.new()
	var twin := GOBLIN_MATERIAL.duplicate() as ShaderMaterial
	twin.shader = GOBLIN_MARKING_SHADER
	for material: Material in [GOBLIN_MATERIAL, twin]:
		var scene := (load(MODELS["imp"]["scene"]) as PackedScene).instantiate() as Node3D
		for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = material
		piece.add_child(scene)
	return piece


## The painted allies for the warm-up (warm_ups; decision 529): each MODELS
## "paint" in its material and its hover outline's stencil twin, skinned, as
## warm_goblin does the goblin's.
## A model whose paint or scene this build lacks (a pck without the art, terrain's bench on
## 11a3f6af: "Cannot call method 'duplicate' on a null value") is passed over, not warmed.
static func warm_painted(models: Dictionary = MODELS) -> Node3D:
	var piece := Node3D.new()
	# The materials held by the piece itself till its children are gone (a twin held by its
	# surfaces alone was freed before them as the piece was: the renderer's "material is null").
	var held: Array[Material] = []
	piece.set_meta("materials", held)
	for kind: String in models:
		if not models[kind].has("paint"):
			continue
		var paint_path := str(models[kind]["paint"])
		var scene_path := str(models[kind]["scene"])
		if not ResourceLoader.exists(paint_path) or not ResourceLoader.exists(scene_path):
			continue
		var paint := load(paint_path) as ShaderMaterial
		var made := load(scene_path) as PackedScene
		if paint == null or made == null:
			continue
		var twin := paint.duplicate() as ShaderMaterial
		twin.shader = GOBLIN_MARKING_SHADER
		held.append_array([paint, twin])
		for material: Material in [paint, twin]:
			var scene := made.instantiate() as Node3D
			for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
				_paint_skin(mesh, material)
			piece.add_child(scene)
	return piece


## [param mesh]'s skin in [param paint]: every surface but those on art-kit's palette (a
## hand-made body's plate, chain and belt), which are drawn in the palette (decision 529 amended).
static func _paint_skin(mesh: MeshInstance3D, paint: Material) -> void:
	if paint == null:
		return  # Its own material where this build lacks the paint.
	for surface in mesh.mesh.get_surface_count():
		var own := mesh.mesh.surface_get_material(surface)
		var palette := own != null and own.resource_name == ArtKit.PALETTE_NAME
		mesh.set_surface_override_material(surface, load(ArtKit.PALETTE) if palette else paint)


## A painted ally's look by its name (decision 529), the same on every peer
## (goblin_look's hash): {width, skin (hue shift, saturation, value: within
## PAINTED_SKIN_*), mark (one of GOBLIN_MARKS, one-hot, or none:
## PAINTED_UNMARKED of the time; body_marks.py's chest scar, arm stripes and
## red hand), words}.
static func painted_look(ally_name: String) -> Dictionary:
	var h := 2166136261
	for byte in ally_name.to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & 0xffffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var width := rng.randf_range(PAINTED_WIDTH.x, PAINTED_WIDTH.y)
	var skin := Vector3(rng.randf_range(PAINTED_SKIN_HUE.x, PAINTED_SKIN_HUE.y), rng.randf_range(PAINTED_SKIN_SAT.x, PAINTED_SKIN_SAT.y),
		rng.randf_range(PAINTED_SKIN_VALUE.x, PAINTED_SKIN_VALUE.y))
	var marked := rng.randf() >= PAINTED_UNMARKED
	var mark_index := rng.randi() % GOBLIN_MARKS.size()
	var mark := Vector3.ZERO
	if marked:
		mark[mark_index] = 1.0
	var words: Array[String] = []
	if width < 0.97:
		words.append("build=lean")
	elif width > 1.03:
		words.append("build=stocky")
	if skin.z < 0.92:
		words.append("skin=dark")
	elif skin.z > 1.06:
		words.append("skin=pale")
	if marked:
		words.append("mark=" + GOBLIN_MARKS[mark_index])
	return {"width": width, "skin": skin, "mark": mark, "words": " ".join(words)}


## A goblin's look by its name (decision 494), the same on every peer (a
## hash of the name's bytes, not the engine's String.hash): {width, skin
## (Vector3: hue shift, saturation, value), gear (Color, its amount in .a),
## mark (Vector3, one-hot or none), words}, its words for what a voice might
## call it ("build=lean skin=dark gear=red mark=scarred", a word only where
## it stands out).
static func goblin_look(goblin_name: String) -> Dictionary:
	var h := 2166136261
	for byte in goblin_name.to_utf8_buffer():
		h = ((h ^ byte) * 16777619) & 0xffffffff
	var rng := RandomNumberGenerator.new()
	rng.seed = h
	var width := rng.randf_range(GOBLIN_WIDTH.x, GOBLIN_WIDTH.y)
	var skin := Vector3(rng.randf_range(GOBLIN_SKIN_HUE.x, GOBLIN_SKIN_HUE.y), rng.randf_range(GOBLIN_SKIN_SAT.x, GOBLIN_SKIN_SAT.y),
		rng.randf_range(GOBLIN_SKIN_VALUE.x, GOBLIN_SKIN_VALUE.y))
	var own := rng.randf() < GOBLIN_OWN_GEAR
	var gear_name: String = GOBLIN_GEAR.keys()[rng.randi() % GOBLIN_GEAR.size()]
	var gear := Color(GOBLIN_GEAR[gear_name])
	gear.a = 0.0 if own else 0.85
	var marked := rng.randf() >= GOBLIN_UNMARKED
	var mark_index := rng.randi() % GOBLIN_MARKS.size()
	var mark := Vector3.ZERO
	if marked:
		mark[mark_index] = 1.0
	var words: Array[String] = []
	if width < 0.95:
		words.append("build=lean")
	elif width > 1.05:
		words.append("build=stocky")
	if skin.z < 0.9:
		words.append("skin=dark")
	elif skin.z > 1.07:
		words.append("skin=pale")
	elif skin.x < -0.03:
		words.append("skin=yellowish")
	elif skin.x > 0.03:
		words.append("skin=bluish")
	if not own:
		words.append("gear=" + gear_name)
	if marked:
		words.append("mark=" + GOBLIN_MARKS[mark_index])
	# Drawn after the rest, so a goblin keeps the look it had before (494 amended).
	var hood := rng.randf() < GOBLIN_HOOD_UP
	var ears := rng.randf_range(-1.0, 1.0)
	if not hood:
		words.append("hood=down")
	if absf(ears) > GOBLIN_EARS_SAID:
		words.append("ears=" + ("big" if ears > 0.0 else "small"))
	return {"width": width, "skin": skin, "gear": gear, "mark": mark, "hood": hood, "ears": ears, "words": " ".join(words)}


## [param entity]'s own look and manner (see MODEL_MASS), on its puppet:
## "model_scale", "pace" (its gaits' paces over the model's), "tempo" and
## "rng", which picks its blows and flinches. A model not sized "by_mass"
## varies its size a little all the same.
static func _vary(entity: GridEntity, puppet: Node3D, model: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(entity.name))
	var size := 1.0
	if model.get("by_mass", true):
		size = clampf(pow(entity.mass / MODEL_MASS, 1.0 / 3.0), MODEL_SCALE_MIN, MODEL_SCALE_MAX)
	size *= 1.0 + rng.randf_range(-MODEL_SCALE_SPREAD, MODEL_SCALE_SPREAD)
	if model.get("parts", false) or model.has("people"):
		# A person: their look's stature (its pace with it: longer legs, longer strides); a
		# painted ally its stature only (decision 529).
		var look := look_for(entity)
		puppet.set_meta("look", look)
		size = look.scale
	puppet.set_meta("model_scale", size)
	puppet.set_meta("pace", size * (1.0 + rng.randf_range(-PACE_SPREAD, PACE_SPREAD)))
	puppet.set_meta("tempo", 1.0 + rng.randf_range(-TEMPO_SPREAD, TEMPO_SPREAD))
	puppet.set_meta("rng", rng)
	var fidget_rng := RandomNumberGenerator.new()
	fidget_rng.seed = hash(String(entity.name)) ^ _session_seed
	puppet.set_meta("fidget_rng", fidget_rng)
	puppet.set_meta("fidget_at", Time.get_ticks_msec() + int(fidget_rng.randf_range(2.0, FIDGET_SECONDS_MAX) * 1000.0))


## One of [param clips], at random, not [param puppet]'s last of them (the
## one there is, when there is one: decision 390's).
static func _pick_clip(puppet: Node3D, clips: Array[String]) -> String:
	var rng: RandomNumberGenerator = puppet.get_meta("rng") if puppet.has_meta("rng") else null
	if rng == null:
		return clips[0]
	var key := "last_" + clips[0]
	var last := str(puppet.get_meta(key, ""))
	var choices := clips.filter(func(clip: String) -> bool: return clip != last)
	if choices.is_empty():
		choices = clips
	var clip: String = choices[rng.randi() % choices.size()]
	puppet.set_meta(key, clip)
	return clip


## One of FIDGETS for [param puppet], by weight, not its last (any with no
## clip in [param rig] left out); "" for none.
static func _pick_fidget(puppet: Node3D, rig: AnimRig) -> String:
	var rng: RandomNumberGenerator = puppet.get_meta("fidget_rng", puppet.get_meta("rng", null))
	var last := str(puppet.get_meta("last_fidget", ""))
	var fidgets: Dictionary = puppet.get_meta("fidgets", FIDGETS)
	var total := 0
	for clip: String in fidgets:
		if clip != last and rig.has(clip):
			total += int(fidgets[clip])
	if total == 0:
		return ""
	var roll := rng.randi_range(1, total) if rng != null else 1
	for clip: String in fidgets:
		if clip == last or not rig.has(clip):
			continue
		roll -= int(fidgets[clip])
		if roll <= 0:
			puppet.set_meta("last_fidget", clip)
			return clip
	return ""


## Whether [param puppet]'s monster is sitting (Monster.Pose.SIT).
static func _sitting(puppet: Node3D) -> bool:
	var entity := instance_from_id(int(puppet.get_meta("entity_id", 0))) as Monster
	return entity != null and entity.pose == Monster.Pose.SIT


## Visible work (566, pc-character's side; Jeff: "town people need to be doing
## activities to better the town, chopping wood, going hunting, building a half
## constructed building, sleeping at night"): npc's Resident.activity, a word,
## as the body shows it: the clip it plays standing at the work ("clip"; walking,
## its gait), the tool in its right hand while that hand is empty ("right", an
## art slot: art-kit's tool.*) and in its left ("left": a hunter's bow), the
## load on its shoulder ("shoulder": carry.*),
## an upper-layer clip over its walk and stand ("upper"), lying ("lying"), the
## tool slid down the hand by "grip" metres along its length (its +y; the axe's
## origin is its butt: two-handed, the right hand holds it up the haft and the
## butt is in the left, humanoid_clips.py's CHOP_GRIP and a little over).
## A word not here shows nothing (the sim may name one before it's drawn). The
## sim sets only the facing (toward the work); the strokes are the client's,
## each body out of step with the next (AnimRig.loop starts a clip somewhere
## along it, seeded per body).
const ACTIVITIES := {
	"chop": {"clip": "Chop", "right": "tool.axe", "grip": 0.22},
	"saw": {"clip": "Saw", "right": "tool.saw"},
	"hammer": {"clip": "Hammer", "right": "tool.hammer"},
	"carry_log": {"upper": "Carry_Shoulder", "shoulder": "carry.log"},
	"sleep": {"clip": "Lie", "lying": true},
	# The bandage kneel (Jeff: "a kneeling next to the target animation"): a
	# player's or a companion's while it tends (GridEntity.tending), turned to
	# the patient and leant toward it this far (metres), hands at its work.
	"bandage": {"clip": "Fixing_Kneeling", "toward": 0.3},
	# A companion asleep on the night watch (621 amended, Companion.asleep): on
	# her side, knees drawn up, a slow breath (humanoid_clips' Sleep_Side_Loop),
	# her front to the fire (_sleeping_yaw).
	"sleep_side": {"clip": "Sleep_Side", "lying": true},
	# Townsfolk at work (566 amended, pc-character's side; npc's words, the
	# coordinator's approval): a hunter crouched with a bow, not drawn (stalk);
	# game and sacks carried on the shoulder; a hoe's strokes, walking a row too
	# (the upper layer; humanoid_clips' Hoe_Loop, the right hand this far up
	# the haft from its butt); leaning on a crook; shearing, knelt.
	"stalk": {"clip": "Crouch_Idle", "left": "item.bow"},
	"carry_game": {"upper": "Carry_Game", "shoulder": "carry.game"},
	"carry_sack": {"upper": "Carry_Shoulder", "shoulder": "carry.sack"},
	"hoe": {"upper": "Hoe", "right": "tool.hoe", "grip": 0.75},
	"herd": {"clip": "Herd", "right": "tool.crook"},
	"shear": {"clip": "Fixing_Kneeling", "right": "tool.shears"},
}
## A hand's id that names an art slot, not an item (a work's tool).
const ART_ID := "art:"


## [param tool] in its socket as [param work] holds it (its "grip").
static func _grip(tool: Node3D, work: Dictionary) -> void:
	tool.position = Vector3(0.0, -float(work.get("grip", 0.0)), 0.0)


## [param entity]'s work as ACTIVITIES has it ({} for none): a resident's
## activity, anyone's bandaging (tending).
static func work_of(entity: GridEntity) -> Dictionary:
	return ACTIVITIES.get(work_word(entity), {})


## The ACTIVITIES word of [param entity]'s work: a resident's activity,
## "sleep_side" for a companion asleep, "bandage" while it tends; "" for none.
static func work_word(entity: GridEntity) -> String:
	if entity is Resident and ACTIVITIES.has((entity as Resident).activity):
		return (entity as Resident).activity
	if entity is Companion and (entity as Companion).asleep:
		return "sleep_side"
	return "bandage" if not entity.tending.is_empty() else ""


## A bandager's facing (the bandage kneel): toward the body it tends;
## [param yaw] while it tends none, or itself.
static func _tending_yaw(entity: GridEntity, yaw: float) -> float:
	if entity.tending.is_empty() or entity.tending == String(entity.name):
		return yaw
	for other in World.get_entities():
		if String(other.name) == entity.tending:
			var way := Vector2(other.tile - entity.tile)
			return yaw if way == Vector2.ZERO else -way.angle()
	return yaw


## How far a sleeper's front is turned from its facing: Sleep_Side lies on its
## left side, its front where its left hand was (the model's +X), and _lay
## turns a lying model round (faces + PI), which puts that front on the body's
## +Z, a quarter turn clockwise of its facing seen from above.
const SLEEP_FRONT := -PI / 2.0
## How far round a sleeper a fire is looked for: Companion's watch rule
## (rules' fire_cells, 2).
const SLEEP_FIRE_REACH := 2


## A companion asleep (621 amended): her facing laid so her front is to the
## nearest fire within SLEEP_FIRE_REACH cells; [param yaw] while awake or with
## no fire found.
static func _sleeping_yaw(entity: GridEntity, yaw: float) -> float:
	if not entity is Companion or not (entity as Companion).asleep:
		return yaw
	var best := Vector2i.ZERO
	var found := false
	for dy in range(-SLEEP_FIRE_REACH, SLEEP_FIRE_REACH + 1):
		for dx in range(-SLEEP_FIRE_REACH, SLEEP_FIRE_REACH + 1):
			var way := Vector2i(dx, dy)
			if way != Vector2i.ZERO and World.is_fire(entity.tile + way) and (not found or Vector2(way).length() < Vector2(best).length()):
				best = way
				found = true
	return -Vector2(best).angle() - SLEEP_FRONT if found else yaw


## The work kept on the puppet ("work", read by _animate and _lay), and its
## upper layer: the work's, else let go of if it was a work's.
func _sync_work(entity: GridEntity, puppet: Node3D) -> void:
	var work := work_of(entity)
	puppet.set_meta("work", work_word(entity) if not work.is_empty() else "")
	if not puppet.has_meta("rig"):
		return
	var rig := puppet.get_meta("rig") as AnimRig
	var upper := str(work.get("upper", ""))
	if upper != "" and rig.upper_clip() != upper and rig.has(upper):
		rig.upper(upper)
	elif upper == "" and rig.upper_clip() != "" and ACTIVITIES.values().any(func(w: Dictionary) -> bool: return str(w.get("upper", "")) == rig.upper_clip()):
		rig.upper_off()


## The shoulder's load: [param slot]'s piece on the "shoulder" socket, gone
## when it's "" (kept as the puppet's "load"); held level with the body
## (SHOULDER_LEVEL in the skeleton's frame), not tipped with the chest the gait
## leans (the walk's 25°, its back end up into the head).
func _sync_load(puppet: Node3D, sockets: Dictionary, slot: String) -> void:
	if slot == str(puppet.get_meta("load", "")):
		_level_load(sockets)
		return
	puppet.set_meta("load", slot)
	var shoulder := sockets.get("shoulder") as Node3D
	if shoulder == null:
		return
	var old := shoulder.get_node_or_null("Load")
	if old != null:
		shoulder.remove_child(old)
		old.queue_free()
	if slot != "" and ArtKit.has(slot):
		var piece := ArtKit.instance(slot)
		piece.name = "Load"
		shoulder.add_child(piece)


## The load on [param sockets]' shoulder, if any, level with the skeleton
## (the socket's BoneAttachment3D's parent), however the chest leans.
static func _level_load(sockets: Dictionary) -> void:
	var shoulder := sockets.get("shoulder") as Node3D
	var carried := shoulder.get_node_or_null("Load") as Node3D if shoulder != null else null
	if carried != null:
		carried.global_basis = (shoulder.get_parent().get_parent() as Node3D).global_basis * SHOULDER_LEVEL


## The "shoulder" socket (566): on the upper chest over the right shoulder,
## out past its joint (SHOULDER_OUT of the way from the chest's middle to it,
## so a log's thickness clears the head: in from it, art-kit's 0.27 m log went
## through the crown), +y up off the shoulder's top and +x forward along the
## body, level in the body's own frame, not the chest bone's (its rest leans
## forward: the log's back end rose to the head) (a carried log lies fore and
## aft, art-kit's carry.*: its origin where it rests, its length along x);
## measured off [param skeleton]'s rest, so every body has it where its own
## shoulder is. [] without the bones.
const SHOULDER_OUT := 1.4
const SHOULDER_UP := 0.09
## The "head" socket (the bard's hat; npc's look word hat=<word>): on the Head
## bone at the top of the skull, its Body's highest vertex within HEAD_LINE of
## the bone's centre line at rest (ears and hair aside), the skull's middle
## front to back (HEAD_BAND below that), +x forward and +y up,
## level in the body's frame (SHOULDER_LEVEL), as art-kit's gear.hat is made:
## its origin at the cap's inside crown. Measured once per body mesh, so the
## woman's head (0.216 m above the bone) and the man's (0.228) each get theirs.
## People only (their sockets' "crown"); [] without the bone or the Body.
const HEAD_LINE := 0.05
const HEAD_BAND := 0.08
static var _crowns := {}
static func _head_socket(skeleton: Skeleton3D) -> Array:
	var head := skeleton.find_bone("Head")
	var body := skeleton.get_node_or_null("Body") as MeshInstance3D
	if head < 0 or body == null or body.mesh == null:
		return []
	var rest := skeleton.get_bone_global_rest(head)
	if not _crowns.has(body.mesh):
		var vertices: PackedVector3Array = body.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var top := rest.origin.y
		for v in vertices:
			if absf(v.x - rest.origin.x) < HEAD_LINE:
				top = maxf(top, v.y)
		# Front to back, the skull's middle within HEAD_BAND of its top (the top vertex is forward
		# of it: a cap there stood off the brow and the back of the head came through its band).
		var front := -INF
		var back := INF
		for v in vertices:
			if v.y > top - HEAD_BAND and v.y > rest.origin.y:
				front = maxf(front, v.z)
				back = minf(back, v.z)
		_crowns[body.mesh] = Vector3(rest.origin.x, top, (front + back) * 0.5 if front > back else rest.origin.z)
	return ["Head", Transform3D(rest.basis.orthonormalized().inverse() * SHOULDER_LEVEL, rest.affine_inverse() * (_crowns[body.mesh] as Vector3))]


## A hat by its look word (npc's look_spec "hat=<word>"; the bard's): HATS'
## art slot and variant on the "head" socket, the look's own headwear (hood,
## brimmed hat, cap) put away under it. A word not in HATS, or a build
## without the piece, wears nothing new (as an old client does).
const HATS := {"bard": ["gear.hat", 1]}
const HEADWEAR_MESHES: Array[String] = ["Hood", "Hat_Brimmed", "Cap_Soft"]
static func _wear_hat(scene: Node3D, puppet: Node3D) -> void:
	var look := puppet.get_meta("look") as PersonLook if puppet.has_meta("look") else null
	var head := (puppet.get_meta("sockets", {}) as Dictionary).get("head") as Node3D
	if look == null or head == null:
		return
	var hat: Array = HATS.get(str(look.words.get("hat", "")), [])
	if hat.is_empty() or not ArtKit.has(hat[0]):
		return
	var piece := ArtKit.instance(hat[0], int(hat[1]))
	piece.name = "Hat"
	head.add_child(piece)
	for mesh: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name) in HEADWEAR_MESHES:
			mesh.visible = false


## A load on the shoulder, in the skeleton's frame: +x the body's front, +y up.
const SHOULDER_LEVEL := Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0))
static func _shoulder_socket(skeleton: Skeleton3D, hand: float) -> Array:
	var chest := skeleton.find_bone("UpperChest")
	var arm := skeleton.find_bone("RightUpperArm")
	if chest < 0 or arm < 0:
		return []
	var rest := skeleton.get_bone_global_rest(chest)
	var joint := skeleton.get_bone_global_rest(arm).origin
	var at := Vector3(lerpf(rest.origin.x, joint.x, SHOULDER_OUT), joint.y + SHOULDER_UP * hand, joint.z)
	return ["UpperChest", Transform3D(rest.basis.orthonormalized().inverse() * SHOULDER_LEVEL, rest.affine_inverse() * at)]


## Where on [param cell] a body stands in [param slot]'s piece over [param
## rect], turned by [param yaw] (580 step 3): its "stand" point less the
## cell's middle; none (zero) without one.
static func stand_offset(slot: String, rect: Rect2i, yaw: float, cell: Vector2i) -> Vector3:
	var stand: Variant = ArtKit.spec(slot).get("stand")
	if not stand is Array or (stand as Array).size() != 3:
		return Vector3.ZERO
	var middle := Vector2(rect.position) + Vector2(rect.size - Vector2i.ONE) * 0.5
	var point := Basis(Vector3.UP, yaw) * Vector3(float(stand[0]), float(stand[1]), float(stand[2]))
	return Vector3(middle.x - cell.x, 0.0, middle.y - cell.y) + point


## A sleeper lies on its bed cell (566): the Lie clip falls back from the feet,
## its head behind them, so the model turns half round to put the head toward
## the facing (the sim's: to the wall) and the body moves back by the lying
## body's middle (LIE_MIDDLE, measured: the head 1.14 m behind the feet' 0.23
## ahead) so it lies on the cell, not beside it. Else as it stands. [param yaw]
## the facing's, turned by the caller. Standing on a cell whose piece has a
## stand point (_stand_at: the draugr on his throne, 580 step 3), the body
## stands there, until step 4's seated idle replaces it.
const LIE_MIDDLE := 0.46
func _lay(puppet: Node3D, body: Node3D, yaw: float, cell := Vector2i(-1, -1)) -> void:
	var work: Dictionary = ACTIVITIES.get(str(puppet.get_meta("work", "")), {})
	var lying := bool(work.get("lying", false))
	var offset: Vector3 = _stand_at.get(cell, Vector3.ZERO)
	if work.has("toward") and float(puppet.get_meta("speed", 0.0)) <= WALKING:
		# Leant in to its work (the bandage kneel), only while it is still: walking, as it stands.
		offset += Vector3(cos(yaw), 0.0, -sin(yaw)) * float(work["toward"]) * float(puppet.get_meta("model_scale", 1.0))
	if lying:
		var ahead := Vector3(cos(yaw), 0.0, -sin(yaw))
		offset = -ahead * LIE_MIDDLE * float(puppet.get_meta("model_scale", 1.0))
	if body.position != offset:
		body.position = offset
	var model := body.get_node_or_null("Model") as Node3D
	if model == null:
		return
	if not puppet.has_meta("faces"):
		puppet.set_meta("faces", model.rotation.y)
	var want := float(puppet.get_meta("faces")) + (PI if lying else 0.0)
	if not is_equal_approx(model.rotation.y, want):
		model.rotation.y = want


## While the local player draws (decision 583), its body turns to ui's aim,
## Main.aim_angle (radians on the grid, as the sim's), not its eight-way
## facing, so the bow points at the marker; [param yaw] otherwise. Read by
## name: before ui's aim it is the facing, as before.
func _aimed_yaw(entity: GridEntity, yaw: float) -> float:
	if String(entity.name) != _local_name or entity.raised != "draw":
		return yaw
	var main := get_parent()
	if main == null or main.get("aim_drawn") != true:
		return yaw
	return -float(main.get("aim_angle"))


## A body standing still turns slower than it walks round (560, pc-character's
## side; Jeff: a resident clicked "stop, turn to face the player"): when its
## facing swings by more than STAND_TURN_MIN while it stands, the puppet turns
## at STAND_TURN_SPEED (a half turn in about 0.4 s), its feet shuffling
## (shuffle_until, the walk at STAND_SHUFFLE_PACE), not spun on the spot in a
## tenth of a second as the shown facing eases; moving, it follows the facing.
## People only (residents, companions, players): a monster still turns at
## once, its threat read from its facing. The yaw to show from [param shown] toward [param yaw].
const STAND_TURN_MIN := PI / 4.0
const STAND_TURN_SPEED := PI / 0.4
const STAND_SHUFFLE_PACE := 0.6
const CLIP_TALKING := "Idle_Talking"
func _standing_turn(puppet: Node3D, shown: float, yaw: float) -> float:
	var now := Time.get_ticks_msec()
	var then := int(puppet.get_meta("turned_ms", -1))
	puppet.set_meta("turned_ms", now)
	var left := angle_difference(shown, yaw)
	var turning: bool = puppet.get_meta("turning", false)
	if then < 0 or float(puppet.get_meta("speed", 0.0)) > WALKING or not turning and absf(left) <= STAND_TURN_MIN:
		puppet.set_meta("turning", false)
		return yaw
	var step := STAND_TURN_SPEED * clampf((now - then) / 1000.0, 0.0, 0.1)
	if absf(left) <= step:
		puppet.set_meta("turning", false)
		return yaw
	puppet.set_meta("turning", true)
	puppet.set_meta("shuffle_until", now + 120)
	return shown + signf(left) * step


## A resident addressing someone (Resident.addressing, npc's, 560) looks at
## them: its head turned toward theirs by a LookAtModifier3D on its skeleton
## (made the first time, its limits a neck's: LOOK_LIMIT across, LOOK_LIMIT_UP
## up and down), eased in and out over LOOK_EASE; and while it stands it plays
## CLIP_TALKING (_animate). The target is a marker kept at their eyes
## (_eyes_of).
const LOOK_LIMIT := deg_to_rad(70.0)
const LOOK_LIMIT_UP := deg_to_rad(35.0)
const LOOK_EASE := 0.3
const LOOK_EYES := 1.6
func _sync_addressing(resident: Resident, puppet: Node3D) -> void:
	var whom := resident.get_node_or_null(NodePath(resident.addressing)) as GridEntity if resident.addressing != "" else null
	var body: Node3D = _puppets.get(whom.get_instance_id()) if whom != null else null
	puppet.set_meta("addressing", resident.addressing if body != null else "")
	var look := puppet.get_node_or_null("Look") as Node3D
	if body == null and look == null:
		return
	if look == null:
		var skeletons := puppet.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return
		var skeleton := skeletons[0] as Skeleton3D
		var head := skeleton.find_bone("Head")
		if head < 0:
			return
		look = Node3D.new()
		look.name = "Look"
		puppet.add_child(look)
		var turn := LookAtModifier3D.new()
		turn.name = "LookAt"
		turn.bone_name = "Head"
		turn.forward_axis = _bone_axis(skeleton.get_bone_global_rest(head).basis.inverse() * Vector3.BACK)
		turn.use_angle_limitation = true
		turn.symmetry_limitation = true
		turn.primary_limit_angle = LOOK_LIMIT
		turn.secondary_limit_angle = LOOK_LIMIT_UP
		turn.duration = LOOK_EASE
		turn.influence = 0.0
		skeleton.add_child(turn)
		turn.target_node = turn.get_path_to(look)
		look.set_meta("turn", turn)
	var turn := look.get_meta("turn") as LookAtModifier3D
	var wanted := 1.0 if body != null else 0.0
	if body != null:
		look.global_position = _eyes_of(body)
	var step := clampf((Time.get_ticks_msec() - int(look.get_meta("eased_ms", Time.get_ticks_msec()))) / 1000.0 / LOOK_EASE, 0.0, 1.0)
	look.set_meta("eased_ms", Time.get_ticks_msec())
	turn.influence = move_toward(turn.influence, wanted, step)


## Where [param body]'s eyes are: its head bone as posed, else LOOK_EYES m up.
static func _eyes_of(body: Node3D) -> Vector3:
	var skeletons := body.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		var skeleton := skeletons[0] as Skeleton3D
		var head := skeleton.find_bone("Head")
		if head >= 0:
			return skeleton.global_transform * skeleton.get_bone_global_pose(head).origin
	return body.global_position + Vector3.UP * LOOK_EYES


## The bone axis (SkeletonModifier3D.BoneAxis) nearest [param along], a
## direction in the bone's own frame.
static func _bone_axis(along: Vector3) -> SkeletonModifier3D.BoneAxis:
	var axis := along.abs().max_axis_index()
	var plus := along[axis] >= 0.0
	match axis:
		Vector3.AXIS_X:
			return SkeletonModifier3D.BONE_AXIS_PLUS_X if plus else SkeletonModifier3D.BONE_AXIS_MINUS_X
		Vector3.AXIS_Y:
			return SkeletonModifier3D.BONE_AXIS_PLUS_Y if plus else SkeletonModifier3D.BONE_AXIS_MINUS_Y
	return SkeletonModifier3D.BONE_AXIS_PLUS_Z if plus else SkeletonModifier3D.BONE_AXIS_MINUS_Z


## Standing: tired when hurt or winded, else idle.
static func _idle_clip(puppet: Node3D) -> String:
	var entity := instance_from_id(int(puppet.get_meta("entity_id", 0))) as GridEntity
	if entity != null and entity.max_hp > 0 and (float(entity.hp) / entity.max_hp < TIRED_BELOW
			or entity.max_stamina > 0 and entity.stamina_fraction() < GridEntity.WINDED_BELOW):
		return CLIP_TIRED
	return CLIP_IDLE


## A model's clip for what it is doing: a one-off (an attack, a flinch, a
## death) plays out; otherwise it walks while it moves, at its pace, and
## stands idle when it does not.
func _animate(puppet: Node3D) -> void:
	var rig := puppet.get_meta("rig") as AnimRig
	var now := Time.get_ticks_msec()
	var last: Vector3 = puppet.get_meta("last_at", puppet.position)
	var seconds := (now - int(puppet.get_meta("last_ms", now))) / 1000.0
	puppet.set_meta("last_at", puppet.position)
	puppet.set_meta("last_ms", now)
	var speed: float = puppet.get_meta("speed", 0.0)
	var step := Vector2(puppet.position.x - last.x, puppet.position.z - last.z)
	if seconds > 0.0:
		speed = lerpf(speed, step.length() / seconds, clampf(seconds * 12.0, 0.0, 1.0))
	puppet.set_meta("speed", speed)
	if puppet.has_meta("knock") and _knocked(puppet, rig, speed, now):
		return
	var calm := now - int(_combat_at.get(int(puppet.get_meta("entity_id", 0)), -(1 << 40))) > int(FIDGET_CALM_SECONDS * 1000.0)
	if puppet.get_meta("fidgeting", false) and (speed > WALKING or not calm):
		# A fidget (or sitting down, or getting up) is no reason to stand
		# still: it goes.
		puppet.set_meta("fidgeting", false)
		puppet.set_meta("busy_until", 0)
	if speed > WALKING and puppet.get_meta("seated", false):
		puppet.set_meta("seated", false)
		puppet.set_meta("busy_until", 0)
	if now < int(puppet.get_meta("busy_until", 0)):
		return
	puppet.set_meta("fidgeting", false)
	var pace: float = puppet.get_meta("pace", 1.0)
	var tempo: float = puppet.get_meta("tempo", 1.0)
	if speed <= WALKING and rig.has(CLIP_SITTING):
		var sitting := _sitting(puppet)
		var seated: bool = puppet.get_meta("seated", false)
		if sitting and not seated:
			_play_fidget(puppet, rig, CLIP_SIT_DOWN, now, tempo)
			puppet.set_meta("seated", true)
			return
		if sitting:
			rig.loop(CLIP_SITTING, tempo)
			return
		if seated:
			_play_fidget(puppet, rig, CLIP_SIT_UP, now, tempo)
			puppet.set_meta("seated", false)
			return
	if speed > WALKING:
		var gaits: Array = puppet.get_meta("gaits", GAITS)
		var gait: Array = gaits[gait_for(rig.base_clip(), speed / pace, gaits)]
		rig.loop(gait[0], clampf(speed / (float(gait[1]) * pace), 0.3, 3.0))
		return
	var work: Dictionary = ACTIVITIES.get(str(puppet.get_meta("work", "")), {})
	if speed <= WALKING and work.has("clip") and rig.has(str(work["clip"])):
		# At its work (566): the work's clip, looped.
		rig.loop(str(work["clip"]), tempo)
		return
	if now < int(puppet.get_meta("shuffle_until", 0)) and rig.has(CLIP_WALK):
		# Turning where it stands (_standing_turn): its feet shuffle round.
		rig.loop(CLIP_WALK, STAND_SHUFFLE_PACE)
		return
	if str(puppet.get_meta("addressing", "")) != "" and rig.has(CLIP_TALKING):
		# Addressing someone (560): it talks to them.
		rig.loop(CLIP_TALKING, tempo)
		return
	var idle := _idle_clip(puppet)
	var both_hands := puppet.has_meta("reach") and (puppet.get_meta("reach") as HandReach).active  # Ready with a two-hander: no fidgets.
	if idle == CLIP_IDLE and calm and not both_hands and puppet.has_meta("rng") and now >= int(puppet.get_meta("fidget_at", 0)):
		var rng: RandomNumberGenerator = puppet.get_meta("fidget_rng", puppet.get_meta("rng"))
		puppet.set_meta("fidget_at", now + int(rng.randf_range(FIDGET_SECONDS_MIN, FIDGET_SECONDS_MAX) * 1000.0))
		var fidget := _pick_fidget(puppet, rig)
		if not fidget.is_empty():
			_play_fidget(puppet, rig, fidget, now, tempo)
			return
	rig.loop(idle, tempo)


## [param clip] once through from its start, at [param tempo], blended in,
## the model busy with it till it ends (a fidget: dropped if it moves or a
## fight comes to it).
static func _play_fidget(puppet: Node3D, rig: AnimRig, clip: String, now: int, tempo: float) -> void:
	var seconds := rig.once(clip, tempo, CLIP_BLEND * 2.0)
	puppet.set_meta("fidgeting", true)
	puppet.set_meta("busy_until", now + int(seconds * 1000.0))


## A knocked-back model's frame (see CLIP_BACKPEDAL): true while the knock
## has the model, false once it is over (or before its slide shows, so the
## blow's own clip plays on). The sim says which slide is the push's
## (GridEntity.push_shown), so a slide cut short or drawn in pieces on a
## client, or one never drawn, is still known for what it is.
func _knocked(puppet: Node3D, rig: AnimRig, speed: float, now: int) -> bool:
	var knock: Dictionary = puppet.get_meta("knock")
	var toss: bool = knock["toss"]
	var started: int = knock["started"]
	var entity := instance_from_id(int(puppet.get_meta("entity_id", 0))) as GridEntity
	var shown := entity.push_shown if entity != null else GridEntity.PushShown.OVER
	var walking := entity != null and entity.stepping
	if started < 0:
		var waited := now - int(knock["since"]) >= int(KNOCK_WAIT_SECONDS * 1000.0)
		if walking and waited:
			# It walked off before its slide ever showed: no knock to show.
			puppet.remove_meta("knock")
			return false
		if (walking or shown == GridEntity.PushShown.WAITING) and not waited:
			# Not on screen yet (or the step before it still is).
			return false
		started = now
		knock["started"] = now
		if toss:
			rig.cancel_strike()
			puppet.set_meta("busy_until", now + int(rig.once(CLIP_ROLL, -ROLL_SPEED) * 1000.0))
		else:
			rig.cancel_strike()
			rig.loop(CLIP_BACKPEDAL, 1.0, -1.0, true)
	if not walking:
		# Turned to it as the sim turns a body, not snapped round.
		knock["shown"] = lerp_angle(knock["shown"], knock["yaw"],
				1.0 - exp(-GridEntity.TURN_RATE * get_process_delta_time()))
		(puppet.get_node("Body") as Node3D).rotation.y = knock["shown"]
		if knock.get("ending", false):
			# Doubling over (or landing), still facing whence it came.
			if now < int(puppet.get_meta("busy_until", 0)):
				return true
		else:
			if not toss:
				rig.set_speed(clampf(speed / (float(puppet.get_meta("backpedal", BACKPEDAL_CLIP_SPEED)) * float(puppet.get_meta("pace", 1.0))), 1.0, 4.0))
			var held := now < int(puppet.get_meta("busy_until", 0)) if toss else now - started < int(KNOCK_MIN_SECONDS * 1000.0)
			# It doubles over when it gets there: a push back always, a toss
			# if a wall or a door stopped it. One knocked where it stands holds.
			var slid: bool = knock.get("slid", false) or shown == GridEntity.PushShown.SLIDING
			knock["slid"] = slid
			var arrived := shown != GridEntity.PushShown.SLIDING and shown != GridEntity.PushShown.WAITING
			if shown == GridEntity.PushShown.SLIDING or held and not (arrived and (knock["impact"] or slid and not toss)):
				return true
			_play_once(puppet, CLIP_IMPACT if knock["impact"] or not toss else CLIP_LAND)
			knock["ending"] = true
			return true
	puppet.remove_meta("knock")
	puppet.set_meta("busy_until", 0)
	if entity != null:
		# Back to its facing from where the knock left it, turning.
		entity.turn_shown_from(-float(knock["shown"]))
	if walking:
		# Off on its own: the walk takes over now, from where it faces.
		(puppet.get_node("Body") as Node3D).rotation.y = knock["shown"]
	return false


## How often [param puppet]'s body is posed (AnimRig.every, decision 390):
## every frame near what the camera looks at (POSE_NEAR, on the ground: the
## view is orthographic, so nearer the camera is nothing), every other
## within POSE_MID, every POSE_FAR_EVERY beyond, every POSE_UNSEEN_EVERY out
## of the frame.
func _pose_every(puppet: Node3D) -> int:
	if _camera == null:
		return 1
	var at := puppet.global_position + Vector3.UP
	if not _camera.is_position_in_frustum(at):
		return POSE_UNSEEN_EVERY
	var away := Vector2(at.x - _camera_target.x, at.z - _camera_target.z).length_squared()
	if away <= POSE_NEAR * POSE_NEAR:
		return 1
	return 2 if away <= POSE_MID * POSE_MID else POSE_FAR_EVERY


## The index in [param gaits] (GAITS, or a model's own) for moving at
## [param speed] (tiles a second) from the clip playing, [param current]: a
## gait already reached holds till a little below its change.
static func gait_for(current: String, speed: float, gaits: Array = GAITS) -> int:
	var at := 0
	for i in gaits.size():
		if gaits[i][0] == current:
			at = i
	var index := 0
	for i in range(1, gaits.size()):
		var change := sqrt(float(gaits[i - 1][1]) * float(gaits[i][1]))
		if speed > change * (1.0 / GAIT_HYSTERESIS if at >= i else GAIT_HYSTERESIS):
			index = i
	return index


## True if [param clip] is one of GAITS'.
static func is_gait(clip: String) -> bool:
	return GAITS.any(func(gait: Array) -> bool: return gait[0] == clip)


## Plays [param clip] once on [param puppet]'s model, if it has one, and
## holds it till done (a blow it was striking cut short: a flinch, a fall
## take it). False if there is no model.
func _play_once(puppet: Node3D, clip: String) -> bool:
	if not puppet.has_meta("rig"):
		return false
	var rig := puppet.get_meta("rig") as AnimRig
	if not rig.has(clip):
		return false
	puppet.set_meta("fidgeting", false)
	rig.cancel_strike()
	puppet.set_meta("busy_until", Time.get_ticks_msec() + int(rig.once(clip) * 1000.0))
	return true


## [param puppet]'s blow for [param swinger] holding [param weapon]: one of
## its model's strikes for that weapon (HUMANOID_MOVES' "strikes"; bare
## hands' if it has none for it), not the last one, played so its contact
## lands when the drawn body's blow does (STRIKE_LANDS_IN: bodies are drawn
## that far behind the sim, the local player's own at once) and recovered
## by its next. A model with no strikes plays one of ATTACK_CLIPS. False if
## there is no model.
func _strike(puppet: Node3D, swinger: GridEntity, weapon: String) -> bool:
	var strikes: Dictionary = (puppet.get_meta("moves", {}) as Dictionary).get("strikes", {})
	var choices: Array = strikes.get(weapon, strikes.get("", []))
	if choices.is_empty() or not puppet.has_meta("rig"):
		return _play_once(puppet, _pick_clip(puppet, ATTACK_CLIPS))
	var names: Array[String] = []
	for choice: Array in choices:
		names.append(str(choice[0]))
	var clip := _pick_clip(puppet, names)
	var contact := float(choices[names.find(clip)][1])
	var own := swinger is Player and (swinger as Player).owner_peer == Net.local_id
	var lands_in := 0.0 if own else STRIKE_LANDS_IN
	var between := World.attack_ticks_of(swinger) * World.TICK_DT if swinger != null else 1.0
	var rig := puppet.get_meta("rig") as AnimRig
	puppet.set_meta("fidgeting", false)
	var seconds := rig.strike(clip, contact, lands_in, maxf(between - lands_in - contact, 0.2))
	puppet.set_meta("busy_until", Time.get_ticks_msec() + int(seconds * 1000.0))
	return true


static func _hook(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)


## A person's look (decision 419): their spawn spec's "look" (a resident's
## from npc's card, a companion's from hers, a player's as they chose it in
## the options panel's Character section, decision 439; as Main writes them),
## seeded by their name where it names no seed; a player's (and anyone's that
## names none) body is their "body"; a player wears no headwear or apron. A
## monster of an allied people (MODELS' "people") is drawn as one of them
## (decision 478).
static func look_for(entity: GridEntity) -> PersonLook:
	var look := str(entity.spawn_spec.get("look", ""))
	if not look.begins_with("seed=") and not " seed=" in look:
		look = ("seed=%d " % absi(hash(String(entity.name)))) + look
	if entity is Player:
		look += " headwear=none apron=no garb=none"
	if entity is Monster:
		var people := str(MODELS.get(str(entity.spawn_spec.get("kind", "")), {}).get("people", ""))
		if people != "":
			look += " people=" + people
		var words := person_words(entity)
		if not words.is_empty():
			look += " " + words
	return PersonLook.make(look, body_of(entity))


## A monster kind drawn as a person (Jeff: "have the grave robbers use the
## character body type"): its row's "person" in monsters.json, look words
## laid over its seed's (e.g. "headwear=hood garb=none"), puts it in the
## human body with a build and a look, as townsfolk are: their sockets (its
## row's "wields" in its hands, the head socket), their gaits and clips. ""
## for a kind drawn its own way, and for anything not a monster.
static func person_words(entity: GridEntity) -> String:
	if not entity is Monster:
		return ""
	var row: Variant = Monster.kinds().get(str(entity.spawn_spec.get("kind", "")), {})
	return str((row as Dictionary).get("person", "")) if row is Dictionary else ""


## [param entity]'s body (decision 388), &"" if it wears none.
static func body_of(entity: GridEntity) -> StringName:
	var body: Variant = entity.get("body")
	return StringName(body) if body != null else &""


func _make_puppet(entity: GridEntity) -> Node3D:
	var puppet := Node3D.new()
	puppet.name = entity.name
	puppet.set_meta("body", body_of(entity))
	puppet.set_meta("entity_name", String(entity.name))
	puppet.set_meta("entity_id", entity.get_instance_id())
	var shape := EntityFactory.shape_name_for(entity.spawn_spec)
	var model := model_for(entity)
	if not model.is_empty():
		_vary(entity, puppet, model)
	var art := art_slot_for(entity)
	var creature := creature_slot_for(entity) if model.is_empty() else ""
	if creature != "":
		art = ""
	var height: float = float(model["height"]) * float(puppet.get_meta("model_scale", 1.0)) if not model.is_empty() 			else ArtKit.size(creature).y if creature != "" else ArtKit.size(art).y if art != "" else Iso.HEIGHTS[shape]
	var material := StandardMaterial3D.new()
	var sprite := entity.get_node_or_null("Sprite") as Sprite2D
	material.albedo_color = sprite.modulate if sprite != null else Color.WHITE
	puppet.set_meta("tint", material.albedo_color)  # A model's "tint" material.
	material.roughness = 0.8
	# A touch of glow so a body reads in the dark away from any light.
	material.emission_enabled = true
	material.emission = material.albedo_color * 0.12
	var area := Area3D.new()
	area.name = "Pick"
	area.set_meta("entity", entity.get_instance_id())
	puppet.set_meta("pick_height", height)
	var collision := CollisionShape3D.new()
	collision.position.y = height * 0.5
	area.add_child(collision)
	if creature != "":
		# Its creature slot's rigged art (decision 359): Body turns to its
		# facing (+X ahead, as the nose), Pose turns the art's front (+Z)
		# there and is what the view's stand-in tweens tip and push.
		var drawn := Node3D.new()
		drawn.name = "Body"
		var pose := Node3D.new()
		pose.name = "Pose"
		pose.rotation.y = PI * 0.5
		var instance := ArtKit.instance(creature)
		pose.add_child(instance)
		drawn.add_child(pose)
		puppet.add_child(drawn)
		var view := CreatureView.new(creature, instance, pose)
		puppet.add_child(view)
		puppet.set_meta("creature_view", view)
		# The pick shape turns with nothing: a cylinder round its middle,
		# whichever way it faces.
		var cylinder := CylinderShape3D.new()
		var size := ArtKit.size(creature)
		cylinder.radius = maxf(size.x, size.z) * 0.4
		cylinder.height = size.y
		collision.shape = cylinder
	elif art != "":
		# Its slot's own art, standing on the tile; the pick shape its size.
		var drawn := Node3D.new()
		drawn.name = "Body"
		drawn.add_child(ArtKit.instance(art))
		puppet.add_child(drawn)
		var box := BoxShape3D.new()
		box.size = ArtKit.size(art)
		collision.shape = box
	elif model.is_empty():
		var body := MeshInstance3D.new()
		body.name = "Body"
		body.mesh = (_shapes[shape] as Callable).call()
		body.position.y = height * 0.5
		body.material_override = material
		puppet.add_child(body)
		# The pick shape: the body's own.
		collision.shape = _pick_shape(shape, body.mesh)
	else:
		puppet.add_child(_make_model(model, puppet))
		var capsule := CapsuleShape3D.new()
		capsule.radius = MODEL_RADIUS
		capsule.height = height
		collision.shape = capsule
	puppet.add_child(area)
	if entity.is_creature():
		var caption: String = entity.label if not entity.label.is_empty() else entity.name
		puppet.add_child(_label("Name", caption, Color.WHITE, height + 0.35))
		puppet.set_meta("caption", caption)
		puppet.set_meta("bubble_height", height + BUBBLE_OVER_HEAD)
		# The nose: which way it faces, turned each frame (see _sync_puppets).
		# A model turns itself instead.
		var pivot := Node3D.new()
		pivot.name = "Facing"
		if model.is_empty() and creature == "":
			var nose := MeshInstance3D.new()
			var nose_mesh := BoxMesh.new()
			nose_mesh.size = Vector3(0.18, 0.1, 0.14)
			nose.mesh = nose_mesh
			nose.material_override = material
			nose.position = Vector3(0.3, height * 0.72, 0.0)
			pivot.add_child(nose)
		puppet.add_child(pivot)
		var id := entity.get_instance_id()
		# Hooked once: a puppet made again (a body that came late) finds them hooked.
		_hook(entity.swung, _on_swung.bind(id))
		_hook(entity.shot, _on_shot.bind(id))
		_hook(entity.winding, _on_winding.bind(id))
		_hook(entity.guarded, _on_guarded.bind(id))
		if entity is Player or entity is Companion:
			puppet.set_meta("body", str(entity.get("body")))
		_hook(entity.struck, _on_struck.bind(id))
		_hook(entity.impacted, _on_impacted.bind(id))
		_hook(entity.pushed, _on_pushed.bind(id))
		if entity is Monster:
			_hook((entity as Monster).cried, _on_cried.bind(id))
			puppet.set_meta("creature", str(entity.spawn_spec.get("kind", "")))
		if entity.max_hp > 0:
			puppet.add_child(_make_bar(entity.max_hp, height + HP_BAR_ABOVE))
	elif entity.is_breakable():
		entity.impacted.connect(_on_impacted.bind(entity.get_instance_id()))
		_break_sounds[String(entity.name)] = SoundKit.breaking(entity)
	if entity is Player or entity is Companion:
		var light := OmniLight3D.new()
		light.name = "Lantern"
		light.light_color = PLAYER_LIGHT
		_size_lantern(light)
		_cast_shadows(light)
		# Above the head: inside the body it would light the body from within
		# and leave its outside in its own shadow.
		light.position.y = height + 0.6
		puppet.add_child(light)
		# The lantern itself hangs at the belt (decision 451), the light above.
		var belt: Node3D = (puppet.get_meta("sockets", {}) as Dictionary).get("belt_l")
		if belt != null:
			belt.add_child(_hanging_lantern())
	add_child(puppet)
	return puppet


## An HP bar [param max_hp] long, [param height] up.
func _make_bar(max_hp: int, height: float) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	bar.name = "HpBar"
	var quad := QuadMesh.new()
	quad.size = Vector2(HP_BAR_PER_HP * max_hp, HP_BAR_HEIGHT)
	bar.mesh = quad
	var material := ShaderMaterial.new()
	material.shader = _hp_bar_shader
	material.set_shader_parameter("alpha", 0.0)
	material.render_priority = 10
	bar.material_override = material
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position.y = height
	bar.visible = false
	return bar


## A swing: the body goes out toward the blow and back, with a whoosh
## pitched by the swinger's weight.
func _on_swung(direction: Vector2i, id: int) -> void:
	var puppet: Node3D = _puppets.get(id)
	if puppet == null:
		return
	_combat_at[id] = Time.get_ticks_msec()
	var swinger := instance_from_id(id) as GridEntity
	var heft := clampf(inverse_lerp(20.0, 100.0, swinger.mass if swinger != null else 50.0), 0.0, 1.0)
	var weapon := World.wielded(swinger) if swinger != null else ""
	_swings[id] = [Time.get_ticks_msec(), weapon]
	sfx.play(SoundKit.swing(weapon), puppet.position + Vector3.UP * 0.8, lerpf(SWING_PITCH_LIGHT, SWING_PITCH_HEAVY, heft))
	var effort := SoundKit.voice(swinger, "effort_swing")
	if effort != "" and randi() % EFFORT_EVERY == 0:
		sfx.play(effort, puppet.position + Vector3.UP * 1.5)
	if Time.get_ticks_msec() > int(puppet.get_meta("wound_until", 0)):
		_strike(puppet, swinger, weapon)
		if puppet.has_meta("creature_view"):
			(puppet.get_meta("creature_view") as CreatureView).swing()
	var body := puppet.get_node("Body") as Node3D
	var rest := Vector3(0.0, body.position.y, 0.0)
	var out := rest + Vector3(direction.x, 0.0, direction.y).normalized() * LUNGE
	var tween := create_tween()
	tween.tween_property(body, "position", out, LUNGE_SECONDS * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(body, "position", rest, LUNGE_SECONDS * 0.6).set_ease(Tween.EASE_IN)


## A blow taken on a guard (World._meet_guard): a knock on wood; one
## that [param broken] it, wood splitting and a stagger.
func _on_guarded(broken: bool, id: int) -> void:
	var puppet: Node3D = _puppets.get(id)
	if puppet == null:
		return
	_combat_at[id] = Time.get_ticks_msec()
	var holder_now := instance_from_id(id) as GridEntity
	if holder_now != null:
		_arrow_to(holder_now.tile)  # An arrow taken on a guard: not a miss.
	var guard := ""
	var holder := instance_from_id(id) as GridEntity
	if holder != null and World.holds_in_hands(holder):
		for slot in [Items.LEFT_HAND, Items.RIGHT_HAND]:
			var held := holder.slots[slot] if slot < holder.slots.size() else ""
			if held != "" and str(Items.verb_of(held).get("kind", "")) == "block":
				guard = held if guard == "" or Items.has_tag(held, "shield") else guard
	# A guard broken: the same knock, harder.
	sfx.play(SoundKit.block(guard), puppet.position + Vector3.UP * 0.9, 1.0, 4.0 if broken else 0.0)
	if broken:
		_play_once(puppet, _pick_clip(puppet, HIT_CLIPS))


## A shot (World.shoot) stopped at [param point] (cells), [param struck]
## stopping it (decision 583): the bow's twang, and the arrow flies from the
## bow to there (its landing below). As it arrives, a body there is heard
## struck (_on_struck) or guarding (_on_guarded); else what stopped it
## (_shot_sound).
func _on_shot(point: Vector2, struck: StringName, id: int) -> void:
	var to := Vector2i(point.round())  # The cell it stopped in.
	var puppet: Node3D = _puppets.get(id)
	if puppet == null or puppet.get_parent() == null:
		return
	_combat_at[id] = Time.get_ticks_msec()
	# The bow's loose (decision 462): the release and the recovery, then idle.
	if puppet.has_meta("rig") and str(puppet.get_meta("bow_state", "")) in ["draw", "hold"]:
		var clip := str((puppet.get_meta("moves", {}) as Dictionary).get("bow_shoot", ""))
		var rig := puppet.get_meta("rig") as AnimRig
		rig.upper(clip, 1.0, true)
		puppet.set_meta("bow_state", "loose")
		puppet.set_meta("bow_until", Time.get_ticks_msec() + int(rig.length(clip) * 1000.0))
	var shooter := instance_from_id(id) as GridEntity
	var from := _bow_tip(puppet)
	var hit := World.get_entity_at(to) if struck == &"body" else null
	var body: Node3D = _puppets.get(hit.get_instance_id()) if hit != null and hit != shooter else null
	var landed := _shot_sound(struck, to, shooter.tile if shooter != null else to, _trees)
	# Where it stops (decision 583, the sim's point): abreast of the body struck, chest high; at the
	# face of the wall or closed door it met; else its range's end. Flown level at the bow's height.
	var stop := Vector3(point.x, from.y, point.y)
	var along := Vector3(stop.x - from.x, 0.0, stop.z - from.z).normalized()
	if along.is_zero_approx():
		along = Vector3.FORWARD
	if body != null:
		stop.y = body.position.y + ARROW_CHEST * float(body.get_meta("model_scale", 1.0))
	_stop_creak(puppet)
	sfx.play("sfx.bow_loose", from)
	var flight := 0.0 if from.distance_to(stop) < 0.1 else maxf(0.06, from.distance_to(stop) / SHOT_SPEED)
	# Nothing struck short of a wall: on past the end into a short fall (Jeff: "after the full range
	# it sags down and lands in ground, not hitting ground at its target like it does now").
	var sags := body == null and landed in ["sfx.arrow_land", "sfx.arrow_water"]
	var down := stop + along * ARROW_SAG
	down.y = _ground_height(Vector2(down.x, down.z))
	var falling := ARROW_SAG / SHOT_SPEED * ARROW_SAG_SLOW if sags else 0.0
	var end := down if sags else stop
	var flying := {"end": to, "arrive": Time.get_ticks_msec() + roundi((flight + falling) * 1000.0), "heard": false}
	_arrows.append(flying)
	# The hit, sent with the shot, comes first; whatever is left by the
	# arrow's arrival is a friend spared or a miss.
	get_tree().create_timer(maxf(flight + falling, 0.05)).timeout.connect(func() -> void:
		_arrows.erase(flying)
		if not flying["heard"] and is_instance_valid(sfx) and sfx.is_inside_tree():
			var met := World.get_entity_at(to)
			# A friend on the line (decision 456): it sticks in them, softly.
			var by := instance_from_id(id) as GridEntity  # By id: the shooter may be gone by now.
			var spared := met != null and by != null and World.spares(by, met)
			sfx.play("sfx.arrow_spared" if spared else landed, end))
	if flight <= 0.0:
		return
	_whistle(from, end, flight + falling)
	var arrow := _flying_arrow(shooter)
	arrow.name = "ShotArrow"
	puppet.get_parent().add_child(arrow, true)
	_fly_arrow(arrow)
	_head_arrow(arrow, from, stop - from)
	var tween := create_tween()
	tween.tween_method(func(t: float) -> void: _head_arrow(arrow, from.lerp(stop, t), stop - from), 0.0, 1.0, flight)
	if not sags:
		tween.tween_callback(_rest_arrow.bind(arrow))
	if body != null and shooter != null and World.spares(shooter, hit):
		# A friend on the line (decision 456): it sticks in them a while,
		# moving with them.
		tween.tween_callback(func() -> void:
			if is_instance_valid(body) and is_instance_valid(arrow):
				arrow.reparent(body))
		tween.tween_interval(SHOT_STUCK_SECONDS)
	elif body != null:
		pass  # Into the body struck: gone with the hit.
	elif landed == "sfx.arrow_hit_wood":
		# Into the wood at its angle, its head in a little.
		tween.tween_callback(func() -> void: _head_arrow(arrow, stop + along * ARROW_BURY, stop - from))
		tween.tween_interval(SHOT_STUCK_SECONDS)
	elif landed == "sfx.arrow_hit_stone":
		# Off the stone: back a little, turning over, and down to lie on the ground below it.
		var rest := stop - along * ARROW_GLANCE
		rest.y = _ground_height(Vector2(rest.x, rest.z)) + 0.02
		var lying := along.rotated(Vector3.UP, ARROW_GLANCE_TURN)
		tween.tween_method(func(t: float) -> void:
			_head_arrow(arrow, stop.lerp(rest, t) + Vector3.UP * sin(PI * t) * ARROW_GLANCE_UP,
				(-along).slerp(lying, t) + Vector3.UP * (1.0 - 2.0 * t) * 0.5), 0.0, 1.0, ARROW_GLANCE_SECONDS)
		tween.tween_callback(func() -> void: _head_arrow(arrow, rest, lying))
		tween.tween_interval(SHOT_STUCK_SECONDS)
	else:
		# Its range spent: on and down in a short fall, nose first, to stand in the ground at its
		# angle; into water it's gone.
		var drop := stop.y - down.y
		tween.tween_method(func(t: float) -> void:
			_head_arrow(arrow, stop + along * ARROW_SAG * t + Vector3.DOWN * drop * t * t,
				along * ARROW_SAG + Vector3.DOWN * 2.0 * drop * t), 0.0, 1.0, falling)
		tween.tween_callback(_rest_arrow.bind(arrow))
		if landed == "sfx.arrow_land":
			tween.tween_callback(func() -> void:
				_head_arrow(arrow, down + (along * ARROW_SAG + Vector3.DOWN * 2.0 * drop).normalized() * ARROW_BURY,
					along * ARROW_SAG + Vector3.DOWN * 2.0 * drop))
			tween.tween_interval(SHOT_STUCK_SECONDS)
	tween.tween_callback(func() -> void:
		if is_instance_valid(arrow):
			arrow.queue_free())


## An arrow flying [param from] to [param end] over [param flight] seconds
## whistles where it passes nearest the listener, as it passes; not for the
## archer (the loose has its own), whose arrow starts within a cell of them.
func _whistle(from: Vector3, end: Vector3, flight: float) -> void:
	if sfx.listener == null:
		return
	var ear := _tile_position(sfx.listener)
	var line := Vector2(end.x - from.x, end.z - from.z)
	var along := clampf(Vector2(ear.x - from.x, ear.z - from.z).dot(line) / maxf(line.length_squared(), 0.0001), 0.0, 1.0)
	if Vector2(ear.x - from.x, ear.z - from.z).length() < 1.5 or along >= 1.0:
		return
	var by := from.lerp(end, along)
	get_tree().create_timer(maxf(along * flight, 0.01)).timeout.connect(func() -> void:
		if is_instance_valid(sfx) and sfx.is_inside_tree():
			sfx.play("sfx.arrow_flight", by))


## Where a shot leaves [param puppet]'s bow: the arrow on its string if it is
## still drawn, else the bow in its hand, else chest high; in the puppets'
## parent's frame.
func _bow_tip(puppet: Node3D) -> Vector3:
	var sockets: Dictionary = puppet.get_meta("sockets", {})
	var bow := (sockets["hand_l"] as Node3D).get_node_or_null("Held") as Node3D if sockets.has("hand_l") else null
	var nocked := bow.find_child("Nocked", true, false) as Node3D if bow != null else null
	var at := nocked if nocked != null else bow
	if at == null or not at.is_inside_tree() or puppet.get_parent() == null:
		return puppet.position + Vector3.UP * 1.1
	return (puppet.get_parent() as Node3D).to_local(at.global_position)


## The arrow in flight: art-kit's fx.arrow, its shooter's arrows' variant;
## a pale stick where this build lacks it.
static func _flying_arrow(shooter: GridEntity) -> Node3D:
	if ArtKit.has("fx.arrow"):
		var ids := held_ids(shooter) if shooter != null else ["", ""]
		return ArtKit.instance("fx.arrow", int(ARROW_VARIANTS.get(str(ids[0]), 1)))
	var stick := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.7, 0.03)
	stick.mesh = mesh
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color(0.85, 0.8, 0.65)
	stick.material_override = paint
	return stick


## [param arrow] at [param at], its head (its +y, as art-kit draws it) along
## [param heading]; its girth (x and z) its meta "girth" times, 1 at rest.
static func _head_arrow(arrow: Node3D, at: Vector3, heading: Vector3) -> void:
	if not is_instance_valid(arrow):
		return
	var y := heading.normalized() if not heading.is_zero_approx() else Vector3.FORWARD
	var x := y.cross(Vector3.UP) if absf(y.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	x = x.normalized()
	var girth := float(arrow.get_meta("girth")) if arrow.has_meta("girth") else 1.0
	arrow.transform = Transform3D(Basis(x * girth, y, x.cross(y) * girth), at)


## [param arrow] dressed for its flight: ARROW_FLIGHT_GIRTH thick, and a pale
## trail tapering back from its tail (a cone, ARROW_TRAIL long; it marks the
## line, it isn't a comet), unlit and casting no shadow.
static func _fly_arrow(arrow: Node3D) -> void:
	arrow.set_meta("girth", ARROW_FLIGHT_GIRTH)
	var tail := 0.0
	for mesh: MeshInstance3D in ([arrow] if arrow is MeshInstance3D else []) + arrow.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.get_aabb()
		tail = minf(tail, (arrow.global_transform.affine_inverse() * mesh.global_transform * box.position).y if mesh.is_inside_tree() else box.position.y)
	var trail := MeshInstance3D.new()
	trail.name = "Trail"
	var cone := CylinderMesh.new()
	cone.height = ARROW_TRAIL
	cone.top_radius = 0.008
	cone.bottom_radius = 0.0
	cone.radial_segments = 6
	cone.rings = 1
	trail.mesh = cone
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.albedo_color = Color(1.0, 0.97, 0.88, ARROW_TRAIL_ALPHA)
	trail.material_override = paint
	trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trail.position = Vector3(0.0, tail - ARROW_TRAIL * 0.5, 0.0)
	arrow.add_child(trail)


## [param arrow] come to rest (struck, stuck, glanced, or down past its
## range): its true girth, its trail gone.
static func _rest_arrow(arrow: Node3D) -> void:
	if not is_instance_valid(arrow):
		return
	arrow.remove_meta("girth")
	arrow.transform.basis = arrow.transform.basis.orthonormalized()
	var trail := arrow.get_node_or_null("Trail")
	if trail != null:
		arrow.remove_child(trail)
		trail.queue_free()


## A blow wound up over [param ticks]: the heavy swing, timed to connect
## as it lands.
## A monster cried out (Monster.cried: a call to its pack, a rout): its
## kind's slot for it, pitched by its size, from where it is drawn.
func _on_cried(cry: StringName, id: int) -> void:
	var puppet: Node3D = _puppets.get(id)
	var monster := instance_from_id(id) as Monster
	if puppet == null or monster == null:
		return
	var creature := str(monster.spawn_spec.get("kind", ""))
	if puppet.has_meta("creature_view"):
		var view := puppet.get_meta("creature_view") as CreatureView
		if cry == &"charge":
			view.charge()
		elif cry == &"rout":
			view.bolt()
	var slot := SoundKit.cry(creature, String(cry))
	if slot != "":
		sfx.play(slot, puppet.position + Vector3.UP * 0.8, float(SoundKit.CREATURE_PITCH.get(creature, 1.0)))
	if cry == &"rout" and not monster is Animal and music != null and sfx.listener != null 			and _cells_apart(monster.tile, sfx.listener) <= Music.TENSION_NEAR:
		music.sting("victory")


func _on_winding(_direction: Vector2i, ticks: int, id: int) -> void:
	var puppet: Node3D = _puppets.get(id)
	if puppet == null:
		return
	if ticks <= 0:
		# Given up (decision 392): the wind-up stops; the gait or rest takes over.
		puppet.set_meta("wound_until", 0)
		if puppet.has_meta("creature_view"):
			(puppet.get_meta("creature_view") as CreatureView).unwind()
		elif puppet.has_meta("rig"):
			(puppet.get_meta("rig") as AnimRig).cancel_strike()
			puppet.set_meta("busy_until", 0)
		return
	_combat_at[id] = Time.get_ticks_msec()
	if puppet.has_meta("creature_view"):
		# A creature's wound-up blow: its attack, timed to land with the sim's.
		(puppet.get_meta("creature_view") as CreatureView).wind(ticks * World.TICK_DT)
		puppet.set_meta("wound_until", Time.get_ticks_msec() + int(ticks * World.TICK_DT * 1000.0) + 400)
		return
	if not puppet.has_meta("rig") or not (puppet.get_meta("rig") as AnimRig).has(CLIP_HEAVY):
		return
	var rig := puppet.get_meta("rig") as AnimRig
	var seconds := ticks * World.TICK_DT
	puppet.set_meta("fidgeting", false)
	# Its contact as the wound-up blow lands, the rest at the same pace.
	var after := (rig.length(CLIP_HEAVY) - CLIP_HEAVY_CONTACT) * seconds / CLIP_HEAVY_CONTACT
	var now := Time.get_ticks_msec()
	puppet.set_meta("busy_until", now + int(rig.strike(CLIP_HEAVY, CLIP_HEAVY_CONTACT, seconds, after) * 1000.0))
	puppet.set_meta("wound_until", now + int(seconds * 1000.0) + 400)


func _pick_shape(shape_name: String, mesh: Mesh) -> Shape3D:
	match shape_name:
		"capsule":
			var capsule := CapsuleShape3D.new()
			capsule.radius = (mesh as CapsuleMesh).radius
			capsule.height = (mesh as CapsuleMesh).height
			return capsule
		"sphere":
			var sphere := SphereShape3D.new()
			sphere.radius = (mesh as SphereMesh).radius
			return sphere
		"barrel":
			var cylinder := CylinderShape3D.new()
			cylinder.radius = (mesh as CylinderMesh).top_radius
			cylinder.height = (mesh as CylinderMesh).height
			return cylinder
		_:
			var box := BoxShape3D.new()
			box.size = (mesh as BoxMesh).size
			return box


func _label(name_: String, text: String, color: Color, height: float) -> Label3D:
	var label := Label3D.new()
	label.name = name_
	label.text = text
	label.visible = not text.is_empty()
	label.pixel_size = LABEL_SIZE
	label.font_size = LABEL_FONT_SIZE
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 12
	label.position.y = height
	return label


## The state_<name> nodes door edge [param key]'s Door shows: those in its
## leaf, and if it has the frame's (_door_hinges), those in no leaf.
func _states_of(key: Vector3i) -> Array:
	var hinge: Node3D = _door_hinges[key][0]
	var piece := _doorways[key].get_node(^"Door")
	var leaves := piece.get_children().filter(func(node: Node) -> bool: return str(node.name).begins_with("leaf"))
	return piece.find_children("state_*", "Node3D", true, false).filter(func(node: Node) -> bool:
		if hinge.is_ancestor_of(node):
			return true
		return _door_hinges[key][2] and not leaves.any(func(leaf: Node) -> bool: return leaf.is_ancestor_of(node)))


func _on_door_shown(door: Door) -> void:
	_doors_due[door.key] = true


## The leaf of each door follows its Door node's open state: the doors
## that changed, till their leaves are still (a big map's two thousand
## doors, each looked at every frame, took 5 ms of it).
func _sync_doors() -> void:
	for key: Vector3i in _doors_due.keys():
		var door := World.door_on(key)
		# The hidden niche (608): cracked while shut, open once found; no
		# leaf to swing, no wood to sound.
		if _hidden_niches.has(key):
			if door != null:
				_show_hidden_niche(key, door.is_open())
			_doors_due.erase(key)
			continue
		var doorway: Node3D = _doorways.get(key)
		if door == null or doorway == null:
			_doors_due.erase(key)
			continue
		var hinge: Node3D = _door_hinges[key][0]
		var same_door: bool = _door_node.get(door.key, 0) == door.get_instance_id()
		var at := doorway.position + Vector3.UP
		if same_door and _door_open.has(door.key) and _door_open[door.key] != door.is_open() and not door.is_broken():
			if door.is_open() and door.lock != "":
				sfx.play("sfx.door_wood_unlock", at)  # A key turned first.
			sfx.play("sfx.door_wood_open" if door.is_open() else "sfx.door_wood_close", at)
			if not door.is_open() and door.lock != "":
				_play_later("sfx.door_wood_lock", at, 0.4)  # And locked again behind.
		if same_door and _door_hp.has(door.key) and door.hp < _door_hp[door.key]:
			sfx.play("sfx.door_wood_break" if door.is_broken() else "sfx.door_wood_struck", at)
		_door_hp[door.key] = door.hp
		_door_open[door.key] = door.is_open()
		_door_node[door.key] = door.get_instance_id()
		# The art's "state_<name>" nodes (art_style.md) show in that state
		# alone; a broken door whose art has state_broken keeps its leaf,
		# open and splintered, else the leaf goes. A double door's leaf's
		# own follow its edge's Door, the frame's the first edge's.
		if not _door_states.has(key):
			_door_states[key] = _states_of(key)
		var shown := "state_" + door.state()
		var broken_art := false
		for node: Node3D in _door_states[key]:
			node.visible = str(node.name) == shown
			broken_art = broken_art or str(node.name) == "state_broken"
		hinge.visible = not door.is_broken() or broken_art
		var target: float = float(_door_hinges[key][1]) if door.is_open() else 0.0
		hinge.rotation.y = move_toward(hinge.rotation.y, target, get_process_delta_time() / Door.SWING_SECONDS * PI * 0.5)
		if is_equal_approx(hinge.rotation.y, target):  # (A float32 angle: never == PI / 2.)
			_doors_due.erase(key)

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
## The room is built once from the parsed map (Terrain) out of the Kenney
## Castle Kit (1-unit modules, KIT_WALL_HEIGHT tall), at the kit's own
## proportions and scaled only in height to WALL_HEIGHT: the ground piece
## per floor cell; the narrow wall segment per wall edge, centred on the
## boundary line; the narrow corner post at every vertex where walls meet
## at an angle or end; the doorway piece with the gate leaf hinged at the
## edge's start for a door, turning with the Door node. Fire is an emissive
## quad with a small light. Flat-colour boxes in the kit's stone (_box,
## _stone) stay available for interior walls later (BOX_WALLS).
##
## Near and far: a wall, doorway, post or tree that stands between the
## camera and the local player or their companion is near and drawn at
## NEAR_ALPHA, so they show through it; the rest are opaque. Recomputed
## whenever the camera or they move (_update_fade).
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

const KIT := "res://art/kenney-castle/Models/GLB format/"
const WALL_HEIGHT := 3.0
## One height level (height.png) in units; a stair is drawn in STAIR_STEPS.
const LEVEL_RISE := 0.5
const STAIR_STEPS := 4
## Ground kinds' tints on the kit's floor; water and torches.
const GROUND_TINTS := {"grass": Color(0.55, 0.8, 0.45), "dirt": Color(0.85, 0.65, 0.45)}
## The kit's floor piece is grass; stone (any kind without a tint) is this
## grey instead, untextured.
const STONE_FLOOR := Color(0.56, 0.56, 0.54)
const WATER := Color(0.2, 0.42, 0.85, 0.75)
## Under water, so it is never drawn over the void or the forest floor.
const WATER_BED := Color(0.16, 0.24, 0.3)
const WATER_DEPTH := 0.08
const TORCH := Color(1.0, 0.72, 0.38)
const KIT_WALL_HEIGHT := 1.31
## The kit's walls are this thick and occupy x in [-0.5, 0] of their
## module; they are shifted to straddle the edge.
const WALL_THICKNESS := 0.5
const POST_SIZE := 0.5
## The kit's gate leaf, in kit units: thickness x, height y, width z. It
## fits the kit's doorway as is.
const GATE_SIZE := Vector3(0.1516, 0.910339, 0.662151)
## Flat-colour walls instead of the kit pieces (for interiors later).
const BOX_WALLS := false
## The kit's stone, sampled from its colormap at the wall mesh's UVs.
const STONE := Color("ebb48e")
## The 2D floor tile's colour (the box floor).
const FLOOR := Color("4b7164")
const NEAR_ALPHA := 0.3
const CAMERA_PITCH := 50.0
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
const ZOOM_MAX := 1.4
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
## Warm white, whatever the body's colour.
const PLAYER_LIGHT := Color(1.0, 0.93, 0.82)
const FIRE := Color(1.0, 0.45, 0.1)
## The floor where there is no light at all (Fields), as a share of its
## colour; the glow it takes on near heat, at most WARM_MOST of the way.
const FLOOR_DARKEST := 0.3
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
## Below the water's bed.
const FOREST_FLOOR_DEPTH := 0.2
## A piece fades when a ray from the local player or their companion, at
## each of these heights, toward the camera passes within FADE_MARGIN of
## its bounds, and the piece stands on the camera's side of them (not a
## wall at their back in a corner); a wall fades with its whole run.
const FADE_HEIGHTS: Array[float] = [0.3, 0.9, 1.5]
const FADE_MARGIN := 0.3
const FOREST_DEPTH := 3
## Monster kinds drawn as an animated model instead of a capsule: the scene
## (retargeted on import to SkeletonProfileHumanoid, its skeleton
## %GeneralSkeleton), its clips (an AnimationLibrary of retargeted clips,
## art/models/animations), how tall it stands, and which way it faces as
## modelled ("faces": the yaw that turns its front to +X; the goblin faces
## +Z, its toes ahead of its feet, so a quarter turn).
const MODELS := {
	"imp": {"scene": "res://art/models/characters/goblin.glb", "clips": "res://art/models/animations/goblin.res", "height": 1.2,
		"faces": PI * 0.5},
	"brute": {"scene": "res://art/models/characters/goblin.glb", "clips": "res://art/models/animations/goblin.res", "height": 1.2,
		"faces": PI * 0.5},
	"sneak": {"scene": "res://art/models/characters/goblin.glb", "clips": "res://art/models/animations/goblin.res", "height": 1.2,
		"faces": PI * 0.5},
}
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
## last blow near it, every FIDGET_SECONDS_MIN to MAX): one of FIDGETS, by
## weight, not the one before; a loop among them is played for one round
## of it. Hurt or winded it stands tired.
const CLIP_LOOK_ABOUT := "Idle_LookAround"
const FIDGETS := {"Idle_LookAround": 4, "Idle_Talking": 2, "Drink": 1, "Fixing_Kneeling": 1,
	"PickUp_Kneeling": 1, "Crouch_Idle": 1}
const CLIP_TIRED := "Idle_Tired"
## Sitting (Monster.Pose.SIT, at a gathering): down, sat, and up again.
const CLIP_SIT_DOWN := "GroundSit_Enter"
const CLIP_SITTING := "GroundSit_Idle"
const CLIP_SIT_UP := "GroundSit_Exit"
const FIDGET_SECONDS_MIN := 7.0
const FIDGET_SECONDS_MAX := 20.0
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
## Moving faster than this (tiles a second) walks.
const WALKING := 0.4
const CLIP_BLEND := 0.15
const MODEL_RADIUS := 0.3
## A click this near a monster's body (ground units, past its own pick
## shape, from the cursor's ray to the line from its feet to its head) is a
## click on it: a model is slim, and a click just off one would land on the
## ground behind it, a walk round it instead of a hit.
const PICK_SLACK := 0.45
## At most this many pick shapes are looked through (the local player, a
## door) for the entity under the cursor.
const PICK_DEPTH := 8
const FOREST_REACH := 8
const TREE_HEIGHT := 3.6
## Label3D: units per font pixel, with the font size, for a name about a
## quarter unit tall.
const LABEL_SIZE := 0.004
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
## A swing pushes the body this far out toward the blow, and back.
const LUNGE := 0.3
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
## Kit floor material per ground kind, made once.
var _ground_materials: Dictionary[String, Material] = {}
## Each floor cell's ground and kind, shaded by the light and heat fields
## (_shade_floor) whenever World says they changed.
var _grounds: Dictionary[Vector2i, Node3D] = {}
var _ground_kinds: Dictionary[Vector2i, String] = {}
var _shade_due := false
## The kit's own material and a see-through copy of it; the flat stone
## pair likewise.
var _kit_opaque: Material
var _kit_near: Material
var _stone_opaque: StandardMaterial3D
var _stone_near: StandardMaterial3D
## Wall edge key -> its piece; vertex -> its post.
var _walls: Dictionary[Vector3i, Node3D] = {}
var _posts: Dictionary[Vector2i, Node3D] = {}
## Door edge key -> the doorway node (jambs, lintel, hinge).
var _doorways: Dictionary[Vector3i, Node3D] = {}
## Entity instance id -> its puppet.
var _puppets: Dictionary[int, Node3D] = {}
var _hover: MeshInstance3D
## The outline's passes (the first; each the next's next_pass), the
## outlined puppet (null: none), and each body material's copy that marks
## the stencil, by the material.
var _outline: ShaderMaterial
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
var _last_hp: Dictionary[int, int] = {}
## Entity instance id -> its tile as last seen, for footsteps.
var _last_tile: Dictionary[int, Vector2i] = {}
## Entity name -> the "death" message, for an entity still here when it
## came; it falls when it goes.
var _pending_deaths: Dictionary[String, Dictionary] = {}
## Entity name -> {"puppet", "at"}: puppets whose entity went, kept a moment.
var _departed: Dictionary[String, Dictionary] = {}
## Door edge key -> open, as last seen, for their sounds.
var _door_open: Dictionary[Vector3i, bool] = {}
## The local player's entity name while there is one.
var _local_name := ""
## The local player's death: 0 alive .. 1 fully mourned.
var _mourning := false
var _mourn := 0.0
var _environment: Environment
var _listener: AudioListener3D
var sfx: Sfx
var _hp_bar_shader: Shader
var _terrain: Dictionary = {}
var _sun: DirectionalLight3D
var _outdoor := false
## Floor and water cells: the land the forest stands around.
var _land: Dictionary[Vector2i, bool] = {}
var _trees: Dictionary[Vector2i, Node3D] = {}
var _see_through: Dictionary[Material, Material] = {}
## [piece, its bounds grown by FADE_MARGIN, is a tree, the pieces that fade
## with it], for every wall, doorway frame, post and tree, made once per
## room; the pieces faded now, and what they were worked out for.
var _occluders: Array[Array] = []
var _occluders_built := false
var _faded: Dictionary[Node3D, bool] = {}
var _fade_key := ""
var _kit_heights: Dictionary[String, float] = {}


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
	_toss = _make_flat(_make_arrow(TOSS_LENGTH), TOSS)
	_toss.visible = false
	add_child(_toss)
	_hp_bar_shader = preload("res://client3d/hp_bar.gdshader")
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	# Sounds are heard from the player's place: the camera is 40 units off.
	_listener = AudioListener3D.new()
	_listener.name = "Listener"
	add_child(_listener)
	_listener.make_current()
	# The saved diamond, or --test-yaw exactly, for screenshots.
	yaw = Net.camera_yaw
	_yaw_step = nearest_diamond(yaw)
	pitch = CAMERA_PITCH
	zoom = clampf(Net.camera_zoom, ZOOM_MIN, ZOOM_MAX)
	_zoom_to = zoom
	_apply_size()
	_place_camera()
	_classify_walls()


func _process(delta: float) -> void:
	_sync_puppets()
	_sync_doors()
	_ease_yaw(delta)
	_ease_peek(delta)
	_ease_tilt(delta)
	_ease_zoom(delta)
	_ease_pan(delta)
	_follow(delta)
	_update_fade()
	_drop_departed()
	_update_mourning(delta)


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
	add_child(sun)
	_sun = sun


## The dark under-stone look, or outdoors a day sky: its light, a warm sun.
func _apply_sky() -> void:
	_outdoor = bool(_terrain.get("outdoor", false))
	if _outdoor:
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = SKY_TOP
		sky_material.sky_horizon_color = SKY_HORIZON
		sky_material.ground_horizon_color = FOREST_FLOOR.lightened(0.2)
		sky_material.ground_bottom_color = FOREST_FLOOR
		var sky := Sky.new()
		sky.sky_material = sky_material
		_environment.sky = sky
		_environment.background_mode = Environment.BG_SKY
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color = DAY_AMBIENT
		_environment.ambient_light_energy = DAY_AMBIENT_ENERGY
		_sun.light_color = DAY_SUN
		_sun.light_energy = DAY_SUN_ENERGY
	else:
		_environment.background_mode = Environment.BG_COLOR
		_environment.background_color = BACKGROUND
		_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		_environment.ambient_light_color = AMBIENT
		_environment.ambient_light_energy = 1.0
		_sun.light_color = SUN
		_sun.light_energy = SUN_ENERGY


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_SIZE
	_camera.near = 0.1
	_camera.far = CAMERA_DISTANCE * 3.0
	add_child(_camera)
	_camera_target = _tile_position(_centre)
	_place_camera()
	_camera.current = true


## The camera's offset from its target: `pitch` above the ground on the
## +x +z side (grid +x toward the viewer down-right, +y down-left, as in
## the 2D view), turned about the vertical by the yaw.
func _camera_offset() -> Vector3:
	var tilt := deg_to_rad(pitch)
	var horizontal := CAMERA_DISTANCE * cos(tilt)
	var offset := Vector3(horizontal / sqrt(2.0), CAMERA_DISTANCE * sin(tilt), horizontal / sqrt(2.0))
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
	_camera.position = _camera_target + _camera_offset()
	_camera.look_at(_camera_target, Vector3.UP)
	if _listener != null:
		# On the ground under the camera's aim (less any pan: the ears stay
		# with the player), turned as the camera is, so left and right in
		# the ears are left and right on the screen.
		_listener.global_transform = Transform3D(_camera.global_transform.basis, _camera_target - pan + Vector3.UP)


## The camera stays on the player (plus the WASD lean, which eases by
## itself): the player is the middle of the screen, and the yaw turns
## about them.
func _follow(delta: float) -> void:
	var player := _local_player()
	if player == null:
		return
	var puppet: Node3D = _puppets.get(player.get_instance_id())
	if puppet == null:
		return
	_local_name = String(player.name)
	_lead = Main.camera_lean(_lead, get_viewport(), yaw, delta)
	_camera_target = puppet.position + Vector3(_lead.x, 0.0, _lead.y) + pan
	_place_camera()


func _local_player() -> Player:
	for entity in World.get_entities():
		if entity is Player and entity.owner_peer == Net.local_id and entity.spawned:
			return entity
	return null


# --- Orbit ---------------------------------------------------------------------

## The ortho size: CAMERA_SIZE, times the pitch peek's pull back while
## there is one (eased as its tilt is).
func _apply_size() -> void:
	_camera.size = CAMERA_SIZE * zoom * lerpf(1.0, PEEK_PULL_BACK, smoothstep(0.0, 1.0, _peek)) \
			* lerpf(1.0, MOURN_PULL_BACK, smoothstep(0.0, 1.0, _mourn))


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
	var per_px := _camera.size / height
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
	var limit := PITCH_MAX if direction > 0.0 else PITCH_MIN
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
	_set_pitch(lerpf(_tilt_from, CAMERA_PITCH, sin(_tilt_t * PI * 0.5)))


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
	_classify_walls()


# --- Picking --------------------------------------------------------------------

func _mouse_ray() -> Array[Vector3]:
	var mouse := get_viewport().get_mouse_position()
	return [_camera.project_ray_origin(mouse), _camera.project_ray_normal(mouse)]


## Where the cursor's ray meets the ground plane, in grid units; NaN when
## it does not.
func mouse_grid() -> Vector2:
	var ray := _mouse_ray()
	if absf(ray[1].y) < 0.0001:
		return Vector2(NAN, NAN)
	# From the highest level down: the first ground the ray meets at its own
	# height; the ground plane if none.
	for level in range(Level.MAX_HEIGHT, 0, -1):
		var t := (level * LEVEL_RISE - ray[0].y) / ray[1].y
		if t < 0.0:
			continue
		var at := ray[0] + ray[1] * t
		if _height(Vector2i(roundi(at.x), roundi(at.z))) == level:
			return Vector2(at.x, at.z)
	var t := -ray[0].y / ray[1].y
	if t < 0.0:
		return Vector2(NAN, NAN)
	var hit := ray[0] + ray[1] * t
	return Vector2(hit.x, hit.z)


## How high the ground is under [param grid] (a puppet's place): its cell's
## height, a stair's halfway up it.
func _ground_height(grid: Vector2) -> float:
	var cell := Vector2i(roundi(grid.x), roundi(grid.y))
	var height := float(_height(cell))
	if _stair(cell) != Vector2i.ZERO:
		height += 0.5
	return height * LEVEL_RISE


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


## The monster whose body passes within MODEL_RADIUS + PICK_SLACK of the
## ray from [param origin] along [param direction] (the nearest), or null.
func monster_near_ray(origin: Vector3, direction: Vector3) -> GridEntity:
	var far := origin + direction * CAMERA_DISTANCE * 3.0
	var best: GridEntity = null
	var best_off := MODEL_RADIUS + PICK_SLACK
	for id: int in _puppets:
		var entity := instance_from_id(id) as GridEntity
		var puppet := _puppets[id]
		if not entity is Monster or not entity.spawned or not is_instance_valid(puppet) or not puppet.is_visible_in_tree():
			continue
		var feet := puppet.global_position
		var head := feet + Vector3.UP * float(puppet.get_meta("pick_height", 1.0))
		var closest := Geometry3D.get_closest_points_between_segments(origin, far, feet, head)
		var off := closest[0].distance_to(closest[1])
		if off < best_off:
			best = entity
			best_off = off
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


## Flat quads in the ground plane, each [a, b, c, d] corner order.
static func _flat_mesh(quads: Array[PackedVector2Array]) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in quads:
		for i: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(quad[i].x, 0.0, quad[i].y))
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


## The hover outline on [param tile], or hidden.
func hover(tile: Vector2i, show: bool) -> void:
	_hover.visible = show
	if show:
		_hover.position = _tile_position(tile) + Vector3(0.0, ON_FLOOR, 0.0)


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
func _show_outline(puppet: Node3D, show: bool) -> void:
	if puppet == null or not is_instance_valid(puppet):
		return
	var body := puppet.get_node_or_null("Body") as Node3D
	if body == null:
		return
	var meshes := body.find_children("*", "MeshInstance3D", true, false)
	if body is MeshInstance3D:
		meshes.append(body)
	for source: MeshInstance3D in meshes:
		source.material_overlay = _outline if show else null
		_mark_stencil(source, show)


## [param source] drawn with its materials' copies that mark the stencil
## (OUTLINE_STENCIL) where it draws, or ([param mark] false) with its own
## again. The copies look the same.
func _mark_stencil(source: MeshInstance3D, mark: bool) -> void:
	if not mark:
		if source.has_meta("own_override"):
			source.material_override = source.get_meta("own_override")
			source.remove_meta("own_override")
			for surface in source.get_surface_override_material_count():
				source.set_surface_override_material(surface, null)
		return
	if source.has_meta("own_override"):
		return
	source.set_meta("own_override", source.material_override)
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
		_marking[material] = copy
	return _marking[material]


## The toss aim during a right drag: an arrow on the floor from
## [param target] the way it will go; hidden for ZERO or no target.
## Sound [param set_name] from where [param entity] is drawn (Sfx).
func play_at(set_name: String, entity: GridEntity) -> void:
	var puppet: Node3D = _puppets.get(entity.get_instance_id())
	sfx.play(set_name, (puppet.position if puppet != null else _tile_position(entity.tile)) + Vector3.UP * 0.5)


func toss_aim(target: GridEntity, direction: Vector2i) -> void:
	_toss.visible = direction != Vector2i.ZERO and is_instance_valid(target)
	if not _toss.visible:
		return
	var puppet: Node3D = _puppets.get(target.get_instance_id())
	var at := puppet.position if puppet != null else _tile_position(target.tile)
	_toss.position = Vector3(at.x, ON_FLOOR * 3.0, at.z)
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
	if _camera.is_position_behind(at):
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
	ring.position = _tile_position(tile) + Vector3(0.0, ON_FLOOR * 2.0, 0.0)
	add_child(ring)
	var material := ring.material_override as StandardMaterial3D
	ring.scale = Vector3(0.2, 1.0, 0.2)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(1.4, 1.0, 1.4), RIPPLE_SECONDS)
	tween.tween_property(material, "albedo_color:a", 0.0, RIPPLE_SECONDS)
	tween.chain().tween_callback(ring.queue_free)


# --- Room ----------------------------------------------------------------------

## A cell's centre on its ground, at its height.
func _tile_position(tile: Vector2i) -> Vector3:
	return Vector3(tile.x, _height(tile) * LEVEL_RISE, tile.y)


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
	_walls.clear()
	_posts.clear()
	_doorways.clear()
	_grounds.clear()
	_ground_kinds.clear()
	_trees.clear()
	_occluders.clear()
	_occluders_built = false
	_faded.clear()
	_fade_key = ""
	_apply_sky()
	_build_room()
	_classify_walls()
	_camera_target = _tile_position(_centre)
	# A new map: the view starts on the player.
	pan = Vector3.ZERO
	_pan_home = false


func _kit(piece: String) -> Node3D:
	var scene: PackedScene = load(KIT + piece + ".glb")
	return scene.instantiate() as Node3D


func _stone(alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(STONE, alpha)
	material.roughness = 0.9
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


## The kit pieces share one material (a colormap); the see-through copy
## is it with alpha.
func _load_kit_materials() -> void:
	var sample := _kit("wall-narrow")
	for node in _descendants(sample):
		if node is MeshInstance3D:
			_kit_opaque = (node as MeshInstance3D).mesh.surface_get_material(0)
			break
	sample.free()
	var near := _kit_opaque.duplicate() as BaseMaterial3D
	near.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	near.albedo_color = Color(near.albedo_color, NEAR_ALPHA)
	_kit_near = near


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


func _build_room() -> void:
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_load_kit_materials()
	_stone_opaque = _stone(1.0)
	_stone_near = _stone(NEAR_ALPHA)
	var fire: Array[Vector2i] = _terrain["fire"]
	var kinds: Dictionary = _terrain.get("kinds", {})
	_land.clear()
	for cell: Vector2i in _terrain["floor"] + _terrain.get("water", []):
		_land[cell] = true
	for cell: Vector2i in _terrain["floor"]:
		var ground := _kit("ground")
		ground.name = "Floor_%d_%d" % [cell.x, cell.y]
		ground.position = _tile_position(cell)
		_tint_ground(ground, str(kinds.get(cell, "stone")))
		_room.add_child(ground)
		_grounds[cell] = ground
		_ground_kinds[cell] = str(kinds.get(cell, "stone"))
		if cell in fire:
			_add_fire(cell)
	for cell: Vector2i in _terrain.get("water", []):
		_add_water(cell)
	_add_cliffs()
	var stairs: Dictionary = _terrain.get("stairs", {})
	for cell: Vector2i in stairs:
		_add_stair(cell, stairs[cell])
	for cell: Vector2i in _terrain.get("torches", []):
		_add_torch(cell)
	for cell: Vector2i in _terrain.get("lanterns", []):
		_add_lantern(cell)
	if not World.fields_changed_signal.is_connected(_on_fields_changed):
		World.fields_changed_signal.connect(_on_fields_changed)
	_on_fields_changed()
	var edges: Dictionary = _terrain["edges"]
	var kind_at := func(key: Vector3i) -> int: return edges.get(key, Terrain.Edge.OPEN)
	var vertices: Dictionary[Vector2i, bool] = {}
	for key: Vector3i in edges:
		if _outdoor and _is_outline(key):
			continue  # The forest's edge, not a wall (_add_forest).
		match edges[key]:
			Terrain.Edge.WALL:
				_add_wall(key)
			Terrain.Edge.DOOR:
				_add_doorway(key)
			_:
				continue
		for end in 2:
			vertices[WallEdge.vertex_at(key, end)] = true
	for vertex in vertices:
		if _needs_post(vertex, kind_at):
			_add_post(vertex)
	if _outdoor:
		_add_forest()


## An edge between the land and the void: the map's outline.
func _is_outline(key: Vector3i) -> bool:
	var sides := Terrain.edge_cells(key)
	return _land.has(sides[0]) != _land.has(sides[1])


## Trees on the void around the land, and the forest floor under them.
func _add_forest() -> void:
	if _land.is_empty():
		return
	# How far each void cell is from the land (cells, eight ways), out to
	# FOREST_REACH: a walk outward from every land cell at once.
	var distance: Dictionary[Vector2i, int] = {}
	var frontier: Array[Vector2i] = []
	for cell: Vector2i in _land:
		distance[cell] = 0
		frontier.append(cell)
	var head := 0
	while head < frontier.size():
		var cell := frontier[head]
		head += 1
		if distance[cell] >= FOREST_REACH:
			continue
		for direction: Vector2i in World.DIRECTIONS:
			var next := cell + direction
			if not distance.has(next):
				distance[next] = distance[cell] + 1
				frontier.append(next)
	var low := Vector2i(1 << 20, 1 << 20)
	var high := -low
	for cell: Vector2i in distance:
		low = low.min(cell)
		high = high.max(cell)
		var away := distance[cell]
		if away == 0:
			continue
		var roll := _roll(cell, 0)
		if away == 1 or away <= FOREST_DEPTH and roll < 0.7 or roll < 0.25:
			_add_tree(cell)
		elif roll < 0.33:
			var rock := _kit("rocks-small")
			rock.name = "Rock_%d_%d" % [cell.x, cell.y]
			rock.position = _tile_position(cell)
			rock.rotation.y = _roll(cell, 3) * TAU
			_room.add_child(rock)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(high - low) + Vector2.ONE * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = FOREST_FLOOR
	material.roughness = 1.0
	var forest_floor := MeshInstance3D.new()
	forest_floor.name = "ForestFloor"
	forest_floor.mesh = floor_mesh
	forest_floor.material_override = material
	forest_floor.position = Vector3((low.x + high.x) * 0.5, -FOREST_FLOOR_DEPTH, (low.y + high.y) * 0.5)
	_room.add_child(forest_floor)


## One of the kit's trees on [param cell], sized, turned and nudged by the
## cell, so every peer grows the same forest.
func _add_tree(cell: Vector2i) -> void:
	var piece := "tree-large" if _roll(cell, 1) < 0.6 else "tree-small"
	var tree := _kit(piece)
	tree.name = "Tree_%d_%d" % [cell.x, cell.y]
	tree.scale = Vector3.ONE * TREE_HEIGHT * lerpf(0.85, 1.2, _roll(cell, 2)) / _kit_height(piece)
	tree.rotation.y = _roll(cell, 3) * TAU
	tree.position = _tile_position(cell) + Vector3(_roll(cell, 4) - 0.5, 0.0, _roll(cell, 5) - 0.5) * 0.3
	_room.add_child(tree)
	_trees[cell] = tree


## 0..1, the same for [param cell] and [param salt] on every peer.
static func _roll(cell: Vector2i, salt: int) -> float:
	return float(absi(hash(Vector3i(cell.x, cell.y, salt))) % 10007) / 10007.0


## How tall a kit piece stands, as modelled (its meshes' bounds).
func _kit_height(piece: String) -> float:
	if not _kit_heights.has(piece):
		var sample := _kit(piece)
		var top := 0.0
		for node in _descendants(sample):
			var mesh := node as MeshInstance3D
			if mesh == null or mesh.mesh == null:
				continue
			var place := Transform3D.IDENTITY
			var at: Node = mesh
			while at != sample and at is Node3D:
				place = (at as Node3D).transform * place
				at = at.get_parent()
			top = maxf(top, (place * mesh.mesh.get_aabb()).end.y)
		sample.free()
		_kit_heights[piece] = maxf(top, 0.01)
	return _kit_heights[piece]


## A tree see-through and shadowless between the camera and the player (as
## a near wall is), or as modelled.
func _set_tree(tree: Node3D, near: bool) -> void:
	for node in _descendants(tree):
		var mesh := node as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var own := mesh.mesh.surface_get_material(surface)
			mesh.set_surface_override_material(surface, _see_through_of(own) if near and own != null else null)
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if near \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _see_through_of(material: Material) -> Material:
	if not _see_through.has(material):
		var copy := material.duplicate() as BaseMaterial3D
		if copy == null:
			return material
		copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		copy.albedo_color = Color(copy.albedo_color, NEAR_ALPHA)
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


## A kit wall module (narrow wall or doorway) on an edge: the piece sits
## in x [-0.5, 0] of its module, so it is shifted to straddle the line,
## and stretched in height only.
func _kit_wall(piece: String) -> Node3D:
	var holder := Node3D.new()
	var mesh := _kit(piece)
	mesh.position.x = WALL_THICKNESS * 0.5
	holder.scale = Vector3(1.0, WALL_HEIGHT / KIT_WALL_HEIGHT, 1.0)
	holder.add_child(mesh)
	return holder


## The kit's floor in its kind's colour: grass and dirt tinted, stone grey.
func _tint_ground(ground: Node3D, kind: String) -> void:
	var material := _ground_base(kind)
	for node in _descendants(ground):
		if node is MeshInstance3D:
			(node as MeshInstance3D).material_override = material


## A floor kind's plain material: the kit's grass tinted (GROUND_TINTS), or
## for stone, STONE_FLOOR without the kit's texture.
func _ground_base(kind: String) -> BaseMaterial3D:
	if not _ground_materials.has(kind):
		var material := _kit_opaque.duplicate() as BaseMaterial3D
		if GROUND_TINTS.has(kind):
			material.albedo_color = material.albedo_color * GROUND_TINTS[kind]
		else:
			material.albedo_texture = null
			material.albedo_color = STONE_FLOOR
		_ground_materials[kind] = material
	return _ground_materials[kind]


func _add_water(cell: Vector2i) -> void:
	var quad := MeshInstance3D.new()
	quad.name = "Water_%d_%d" % [cell.x, cell.y]
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.albedo_color = WATER
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.15
	mesh.material = material
	quad.mesh = mesh
	quad.position = _tile_position(cell) - Vector3(0.0, WATER_DEPTH, 0.0)
	_room.add_child(quad)
	var bed := MeshInstance3D.new()
	bed.name = "WaterBed_%d_%d" % [cell.x, cell.y]
	var bed_mesh := PlaneMesh.new()
	bed_mesh.size = Vector2.ONE
	var bed_material := StandardMaterial3D.new()
	bed_material.albedo_color = WATER_BED
	bed_material.roughness = 1.0
	bed_mesh.material = bed_material
	bed.mesh = bed_mesh
	bed.position = _tile_position(cell) - Vector3(0.0, (WATER_DEPTH + FOREST_FLOOR_DEPTH) * 0.5, 0.0)
	_room.add_child(bed)


## Cliff faces: where a cell stands above its neighbour (or above the void
## or water at the map's edge), a face of stone down to it, unless a stair
## joins them.
func _add_cliffs() -> void:
	var stairs: Dictionary = _terrain.get("stairs", {})
	for cell: Vector2i in _terrain["floor"]:
		var top := _height(cell)
		if top == 0:
			continue
		for direction: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next := cell + direction
			var low := _height(next) if next in _terrain["floor"] or next in _terrain.get("water", []) else 0
			if low >= top or stairs.get(next, Vector2i.ZERO) == -direction:
				continue
			var face := _box(Vector3(1.0, (top - low) * LEVEL_RISE, 0.06), _stone_opaque)
			face.name = "Cliff_%d_%d_%d_%d" % [cell.x, cell.y, direction.x, direction.y]
			face.position = Vector3(cell.x + direction.x * 0.5, low * LEVEL_RISE, cell.y + direction.y * 0.5)
			face.rotation.y = PI * 0.5 if direction.x != 0 else 0.0
			_room.add_child(face)


## A stair: STAIR_STEPS stone steps on its cell, rising one level toward
## [param up].
func _add_stair(cell: Vector2i, up: Vector2i) -> void:
	var base := _tile_position(cell)
	var holder := Node3D.new()
	holder.name = "Stair_%d_%d" % [cell.x, cell.y]
	holder.position = base
	holder.rotation.y = -Vector2(up).angle() + PI * 0.5
	for i in STAIR_STEPS:
		var rise := (i + 1) * LEVEL_RISE / STAIR_STEPS
		var step := _box(Vector3(1.0, rise, 1.0 / STAIR_STEPS), _stone_opaque)
		step.position.z = -0.5 + (i + 0.5) / STAIR_STEPS
		holder.add_child(step)
	_room.add_child(holder)


## The heat and light changed (the map, a door): the floor is shaded
## again at the end of the frame, once however many changes came.
func _on_fields_changed() -> void:
	if not _shade_due:
		_shade_due = true
		_shade_floor.call_deferred()


## Each floor cell darkened by the light it lacks (fixed sources and the
## level's ambient light; the carried lanterns are real lights here) and
## warmed by the heat on it: the glow around a fire.
func _shade_floor() -> void:
	_shade_due = false
	for cell: Vector2i in _grounds:
		var ground := _grounds[cell]
		if not is_instance_valid(ground):
			continue
		var light := World.light_at(cell, false)
		var warmth := clampf((World.heat_at(cell) - 1.0) / (World.HEAT_BURN - 1.0), 0.0, 1.0)
		var bright := snappedf(lerpf(FLOOR_DARKEST, 1.0, light), 0.1)
		var warm := snappedf(warmth * WARM_MOST, 0.05)
		var kind := _ground_kinds[cell]
		if bright >= 1.0 and warm <= 0.0:
			_restore_ground(ground, kind)
			continue
		var key := "%s_%.1f_%.2f" % [kind, bright, warm]
		if not _ground_materials.has(key):
			var material := _ground_base(kind).duplicate() as BaseMaterial3D
			var colour: Color = material.albedo_color * bright
			material.albedo_color = colour.lerp(WARM, warm)
			if warm > 0.0:
				material.emission_enabled = true
				material.emission = WARM * warm
			_ground_materials[key] = material
		for node in _descendants(ground):
			if node is MeshInstance3D:
				(node as MeshInstance3D).material_override = _ground_materials[key]


## A floor back to its kind's plain colour.
func _restore_ground(ground: Node3D, kind: String) -> void:
	_tint_ground(ground, kind)


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


## A torch on a post, and its warm light.
func _add_torch(cell: Vector2i) -> void:
	var at := _tile_position(cell)
	var post := _box(Vector3(0.1, 1.1, 0.1), _stone_opaque)
	post.name = "Torch_%d_%d" % [cell.x, cell.y]
	post.position = at
	_room.add_child(post)
	var flame := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.2
	var material := StandardMaterial3D.new()
	material.albedo_color = TORCH
	material.emission_enabled = true
	material.emission = TORCH
	material.emission_energy_multiplier = 3.0
	mesh.material = material
	flame.mesh = mesh
	flame.position = at + Vector3(0.0, 1.2, 0.0)
	_room.add_child(flame)
	var light := OmniLight3D.new()
	light.light_color = TORCH
	light.light_energy = 1.4
	light.omni_range = 4.5
	light.shadow_enabled = true
	light.position = at + Vector3(0.0, 1.3, 0.0)
	_room.add_child(light)


## The base of an edge's wall: the higher of the cells it stands between.
func _edge_base(key: Vector3i) -> float:
	var cells := Terrain.edge_cells(key)
	return maxi(_height(cells[0]), _height(cells[1])) * LEVEL_RISE


func _add_wall(key: Vector3i) -> void:
	var wall: Node3D
	if BOX_WALLS:
		wall = _box(Vector3(WALL_THICKNESS, WALL_HEIGHT, 1.0), _stone_opaque)
	else:
		wall = _kit_wall("wall-narrow")
	wall.name = "Wall_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	wall.position = _edge_midpoint(key) + Vector3(0.0, _edge_base(key), 0.0)
	wall.rotation.y = _edge_yaw(key)
	_room.add_child(wall)
	_walls[key] = wall


## The kit's doorway on the edge with its gate leaf, hinged at the edge's
## start end and swinging with the Door node, and an Area3D over the
## module for picking.
func _add_doorway(key: Vector3i) -> void:
	var doorway := Node3D.new()
	doorway.name = "Door_%d_%d_%s" % [key.x, key.y, "e" if key.z == Terrain.EAST else "s"]
	doorway.position = _edge_midpoint(key) + Vector3(0.0, _edge_base(key), 0.0)
	doorway.rotation.y = _edge_yaw(key)
	var frame := _kit_wall("wall-doorway")
	frame.name = "Frame"
	doorway.add_child(frame)
	var hinge := Node3D.new()
	hinge.name = "Hinge"
	hinge.position.z = -GATE_SIZE.z * 0.5
	var leaf := _kit("gate")
	leaf.scale = Vector3(1.0, WALL_HEIGHT / KIT_WALL_HEIGHT, 1.0)
	leaf.position.z = GATE_SIZE.z * 0.5
	hinge.add_child(leaf)
	doorway.add_child(hinge)
	var area := Area3D.new()
	area.name = "Pick"
	area.set_meta("door", key)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WALL_THICKNESS, WALL_HEIGHT, 1.0)
	shape.shape = box
	shape.position.y = WALL_HEIGHT * 0.5
	area.add_child(shape)
	doorway.add_child(area)
	_room.add_child(doorway)
	_doorways[key] = doorway


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


func _add_post(vertex: Vector2i) -> void:
	var post: Node3D
	if BOX_WALLS:
		post = _box(Vector3(POST_SIZE, WALL_HEIGHT, POST_SIZE), _stone_opaque)
	else:
		post = _kit("wall-narrow-corner")
		post.scale = Vector3(1.0, WALL_HEIGHT / KIT_WALL_HEIGHT, 1.0)
	post.name = "Post_%d_%d" % [vertex.x, vertex.y]
	var base := 0
	for corner: Vector2i in [vertex, vertex - Vector2i(1, 0), vertex - Vector2i(0, 1), vertex - Vector2i(1, 1)]:
		base = maxi(base, _height(corner))
	post.position = Vector3(vertex.x - 0.5, base * LEVEL_RISE, vertex.y - 0.5)
	_room.add_child(post)
	_posts[vertex] = post


func _add_fire(cell: Vector2i) -> void:
	var quad := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.9, 0.9)
	var material := StandardMaterial3D.new()
	material.albedo_color = FIRE
	material.emission_enabled = true
	material.emission = FIRE
	material.emission_energy_multiplier = 2.0
	mesh.material = material
	quad.mesh = mesh
	quad.position = _tile_position(cell) + Vector3(0.0, ON_FLOOR, 0.0)
	_room.add_child(quad)
	var light := OmniLight3D.new()
	light.light_color = FIRE
	light.light_energy = 1.5
	light.omni_range = 2.5
	light.position = _tile_position(cell) + Vector3(0.0, 0.5, 0.0)
	_room.add_child(light)


# --- Near and far ----------------------------------------------------------------

func _classify_walls() -> void:
	_update_fade(true)


## Fades what stands between the camera and the local player or their
## companion, and only that, whenever the camera or they have moved
## ([param force]: every piece set again).
func _update_fade(force := false) -> void:
	if _camera == null or _room == null or not _camera.is_inside_tree():
		return
	if not _occluders_built:
		_index_occluders()
	var points := _focus_points()
	var toward := _camera.global_transform.basis.z
	var key := "%s %s" % [toward, points]
	if key == _fade_key and not force:
		return
	_fade_key = key
	var now: Dictionary[Node3D, bool] = {}
	for entry in _occluders:
		var bounds: AABB = entry[1]
		for point in points:
			var ahead := bounds.get_center() - point
			if ahead.x * toward.x + ahead.z * toward.z > 0.0 and bounds.intersects_ray(point, toward) != null:
				for piece: Node3D in entry[3]:
					now[piece] = true
				break
	for entry in _occluders:
		var piece: Node3D = entry[0]
		var fade := now.has(piece)
		if fade == _faded.has(piece) and not force:
			continue
		if entry[2]:
			_set_tree(piece, fade)
		else:
			_set_stone(piece, fade)
	_faded = now


## Where the local player and their companion are, at FADE_HEIGHTS: as
## drawn, or at their tile before they have a puppet.
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


func _index_occluders() -> void:
	_occluders.clear()
	var runs := _wall_runs()
	for key: Vector3i in _walls:
		_occluders.append([_walls[key], _bounds(_walls[key]), false, runs[key]])
	for key: Vector3i in _doorways:
		var frame := _doorways[key].get_node("Frame") as Node3D
		_occluders.append([frame, _bounds(frame), false, runs[key]])
	for post: Node3D in _posts.values():
		_occluders.append([post, _bounds(post), false, [post]])
	for tree: Node3D in _trees.values():
		_occluders.append([tree, _bounds(tree), true, [tree]])
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
			pieces.append(_walls[key] if _walls.has(key) else _doorways[key].get_node("Frame"))
		for vertex in vertices:
			if _posts.has(vertex) and not pieces.has(_posts[vertex]):
				pieces.append(_posts[vertex])
		for key in edges:
			out[key] = pieces
	return out


## [param piece]'s meshes' bounds, in the world, grown by FADE_MARGIN.
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
	return out.grow(FADE_MARGIN)


## A near piece is see-through and casts no shadow, so a lantern behind it
## still lights the floor in front. Every mesh under [param piece] takes
## the kit material pair, or the flat stone pair for a box.
func _set_stone(piece: Node3D, near: bool) -> void:
	for node in _descendants(piece):
		var mesh := node as MeshInstance3D
		if mesh == null:
			continue
		var boxed := mesh.mesh is BoxMesh
		if boxed:
			mesh.material_override = _stone_near if near else _stone_opaque
		else:
			mesh.material_override = _kit_near if near else _kit_opaque
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if near \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


# --- Entities ----------------------------------------------------------------

## One puppet per spawned entity, placed where its 2D node is (the grid
## position under the azimuth-0 projection), turned to its shown facing,
## removed when it goes.
func _sync_puppets() -> void:
	var seen: Dictionary[int, bool] = {}
	var now := Time.get_ticks_msec()
	for entity in World.get_entities():
		if not entity.spawned:
			continue
		var id := entity.get_instance_id()
		seen[id] = true
		if not _puppets.has(id):
			_puppets[id] = _make_puppet(entity)
		var puppet := _puppets[id]
		var grid := Iso.local_to_grid(entity.position)
		puppet.position = Vector3(grid.x, _ground_height(grid), grid.y)
		var facing := puppet.get_node_or_null("Facing") as Node3D
		if facing != null:
			facing.rotation.y = -entity.shown_facing().angle()
		if puppet.has_meta("animator"):
			(puppet.get_node("Body") as Node3D).rotation.y = -entity.shown_facing().angle()
			_animate(puppet)
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
	if puppet == _outlined:
		target(null)
	_combat_at.erase(id)
	_last_hp.erase(id)
	_last_tile.erase(id)
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
		sfx.play("footstep", puppet.position)


## A blow landed: a thud on flesh for an attack (an impact makes its own
## sound, and fire has none yet).
func _on_struck(_amount: int, cause: StringName, id: int) -> void:
	_combat_at[id] = Time.get_ticks_msec()
	var puppet: Node3D = _puppets.get(id)
	if puppet != null and cause != &"impact":
		_play_once(puppet, _pick_clip(puppet, HIT_CLIPS))  # An impact is shown by _on_impacted.
	if puppet != null and cause == &"attack":
		sfx.play("hit", puppet.position + Vector3.UP * 0.8)


## Pushed [param tiles]: a model is knocked back (_animate), a backpedal or,
## for a toss, a roll, once the slide shows.
func _on_pushed(tiles: int, id: int) -> void:
	_combat_at[id] = Time.get_ticks_msec()
	var puppet: Node3D = _puppets.get(id)
	var entity := instance_from_id(id) as GridEntity
	if puppet == null or entity == null or tiles <= 0 or not puppet.has_meta("animator"):
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
			sfx.play("impact_stone", at)
		&"wood":
			sfx.play("impact_wood", at)
		&"body":
			sfx.play("impact_body", at)
			sfx.play("impact_body_soft", at)


## The server's "death" message: the puppet falls now if its entity has
## gone, or when it goes. A broken thing just breaks.
func on_death(data: Dictionary) -> void:
	var entity_name := str(data.get("entity", ""))
	if str(data.get("kind", "")) == "object":
		var tile: Variant = data.get("tile")
		var at := Vector3(tile[0], 0.4, tile[1]) if tile is Array and tile.size() == 2 else _camera_target
		sfx.play("break", at)
		return
	if _departed.has(entity_name):
		_fall(_departed[entity_name]["puppet"], data)
		_departed.erase(entity_name)
		return
	for id: int in _puppets:
		if _puppets[id].get_meta("entity_name", "") == entity_name:
			_pending_deaths[entity_name] = data
			return


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
	sfx.play("death_" + kind, puppet.position + Vector3.UP * 0.5)
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
	var death := _pick_clip(puppet, DEATH_CLIPS)
	if _play_once(puppet, death):
		puppet.set_meta("busy_until", 1 << 62)
		var lie := create_tween()
		lie.tween_interval(CORPSE_SECONDS + (puppet.get_meta("animator") as AnimationPlayer).get_animation(death).length)
		lie.tween_property(puppet, "position:y", -SINK_DEPTH, SINK_SECONDS).set_ease(Tween.EASE_IN)
		lie.tween_callback(puppet.queue_free)
		if kind == "player" and str(data.get("entity", "")) == _local_name:
			_mourning = true
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
		_mourning = true


## The local player dead: pull back and drain the colour, slowly; back as
## soon as they are.
func _update_mourning(delta: float) -> void:
	if _mourning and _local_player() != null and _puppets.has(_local_player().get_instance_id()):
		_mourning = false
	var target := 1.0 if _mourning else 0.0
	var seconds := MOURN_SECONDS if _mourning else MOURN_RETURN_SECONDS
	var before := _mourn
	_mourn = move_toward(_mourn, target, delta / seconds)
	if is_equal_approx(before, _mourn) and _mourn == 0.0:
		return
	_environment.adjustment_saturation = lerpf(1.0, MOURN_SATURATION, smoothstep(0.0, 1.0, _mourn))
	_apply_size()


## MODELS' entry for [param entity] (a monster of a kind that has one), or {}.
static func model_for(entity: GridEntity) -> Dictionary:
	if not entity is Monster:
		return {}
	return MODELS.get(str(entity.spawn_spec.get("kind", "")), {})


## The model as the puppet's Body: the scene turned to face +X (as the
## nose does, so Body turns with the facing; MODELS' "faces"), with an AnimationPlayer on
## its root playing its clips, kept as the puppet's "animator".
func _make_model(model: Dictionary, puppet: Node3D) -> Node3D:
	var body := Node3D.new()
	body.name = "Body"
	var scene := (load(model["scene"]) as PackedScene).instantiate() as Node3D
	scene.name = "Model"
	scene.rotation.y = float(model.get("faces", 0.0))
	body.add_child(scene)
	scene.scale = Vector3.ONE * float(puppet.get_meta("model_scale", 1.0))
	var animator := AnimationPlayer.new()
	animator.name = "Animator"
	scene.add_child(animator)
	animator.root_node = NodePath("..")
	animator.add_animation_library("", load(model["clips"]) as AnimationLibrary)
	animator.play(CLIP_IDLE)
	puppet.set_meta("animator", animator)
	_start_anywhere(puppet, animator)
	return body


## [param entity]'s own look and manner (see MODEL_MASS), on its puppet:
## "model_scale", "pace" (its gaits' paces over GAITS'), "tempo" and "rng",
## which picks its blows and flinches.
static func _vary(entity: GridEntity, puppet: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(String(entity.name))
	var size := clampf(pow(entity.mass / MODEL_MASS, 1.0 / 3.0), MODEL_SCALE_MIN, MODEL_SCALE_MAX)
	size *= 1.0 + rng.randf_range(-MODEL_SCALE_SPREAD, MODEL_SCALE_SPREAD)
	puppet.set_meta("model_scale", size)
	puppet.set_meta("pace", size * (1.0 + rng.randf_range(-PACE_SPREAD, PACE_SPREAD)))
	puppet.set_meta("tempo", 1.0 + rng.randf_range(-TEMPO_SPREAD, TEMPO_SPREAD))
	puppet.set_meta("rng", rng)
	puppet.set_meta("fidget_at", Time.get_ticks_msec() + int(rng.randf_range(2.0, FIDGET_SECONDS_MAX) * 1000.0))


## A loop just started somewhere along it, not at its start.
static func _start_anywhere(puppet: Node3D, animator: AnimationPlayer) -> void:
	var rng: RandomNumberGenerator = puppet.get_meta("rng") if puppet.has_meta("rng") else null
	var clip := animator.get_animation(animator.current_animation)
	if rng != null and clip != null:
		animator.seek(rng.randf() * clip.length, true)


## One of [param clips], at random, not [param puppet]'s last of them.
static func _pick_clip(puppet: Node3D, clips: Array[String]) -> String:
	var rng: RandomNumberGenerator = puppet.get_meta("rng") if puppet.has_meta("rng") else null
	if rng == null:
		return clips[0]
	var key := "last_" + clips[0]
	var last := str(puppet.get_meta(key, ""))
	var choices := clips.filter(func(clip: String) -> bool: return clip != last)
	var clip: String = choices[rng.randi() % choices.size()]
	puppet.set_meta(key, clip)
	return clip


## One of FIDGETS for [param puppet], by weight, not its last (any with no
## clip in [param animator] left out); "" for none.
static func _pick_fidget(puppet: Node3D, animator: AnimationPlayer) -> String:
	var rng: RandomNumberGenerator = puppet.get_meta("rng") if puppet.has_meta("rng") else null
	var last := str(puppet.get_meta("last_fidget", ""))
	var total := 0
	for clip: String in FIDGETS:
		if clip != last and animator.has_animation(clip):
			total += int(FIDGETS[clip])
	if total == 0:
		return ""
	var roll := rng.randi_range(1, total) if rng != null else 1
	for clip: String in FIDGETS:
		if clip == last or not animator.has_animation(clip):
			continue
		roll -= int(FIDGETS[clip])
		if roll <= 0:
			puppet.set_meta("last_fidget", clip)
			return clip
	return ""


## Whether [param puppet]'s monster is sitting (Monster.Pose.SIT).
static func _sitting(puppet: Node3D) -> bool:
	var entity := instance_from_id(int(puppet.get_meta("entity_id", 0))) as Monster
	return entity != null and entity.pose == Monster.Pose.SIT


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
	var animator := puppet.get_meta("animator") as AnimationPlayer
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
	if puppet.has_meta("knock") and _knocked(puppet, animator, speed, now):
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
	if speed <= WALKING and animator.has_animation(CLIP_SITTING):
		var sitting := _sitting(puppet)
		var seated: bool = puppet.get_meta("seated", false)
		if sitting and not seated:
			_play_fidget(puppet, animator, CLIP_SIT_DOWN, now, tempo)
			puppet.set_meta("seated", true)
			return
		if sitting:
			if animator.current_animation != CLIP_SITTING:
				animator.play(CLIP_SITTING, CLIP_BLEND)
				_start_anywhere(puppet, animator)
			animator.speed_scale = tempo
			return
		if seated:
			_play_fidget(puppet, animator, CLIP_SIT_UP, now, tempo)
			puppet.set_meta("seated", false)
			return
	if speed > WALKING:
		var gait: Array = GAITS[gait_for(animator.current_animation, speed / pace)]
		if animator.current_animation != gait[0]:
			animator.play(gait[0], CLIP_BLEND)
			_start_anywhere(puppet, animator)
		animator.speed_scale = clampf(speed / (float(gait[1]) * pace), 0.3, 3.0)
		return
	var idle := _idle_clip(puppet)
	if idle == CLIP_IDLE and calm and puppet.has_meta("rng") and now >= int(puppet.get_meta("fidget_at", 0)):
		var rng: RandomNumberGenerator = puppet.get_meta("rng")
		puppet.set_meta("fidget_at", now + int(rng.randf_range(FIDGET_SECONDS_MIN, FIDGET_SECONDS_MAX) * 1000.0))
		var fidget := _pick_fidget(puppet, animator)
		if not fidget.is_empty():
			_play_fidget(puppet, animator, fidget, now, tempo)
			return
	if animator.current_animation != idle:
		animator.play(idle, CLIP_BLEND)
		_start_anywhere(puppet, animator)
	animator.speed_scale = tempo


## [param clip] once through from its start, at [param tempo], blended in,
## the model busy with it till it ends (a fidget: dropped if it moves or a
## fight comes to it).
static func _play_fidget(puppet: Node3D, animator: AnimationPlayer, clip: String, now: int, tempo: float) -> void:
	animator.play(clip, CLIP_BLEND * 2.0)
	animator.seek(0.0, true)
	animator.speed_scale = tempo
	puppet.set_meta("fidgeting", true)
	puppet.set_meta("busy_until", now + int(animator.get_animation(clip).length / tempo * 1000.0))


## A knocked-back model's frame (see CLIP_BACKPEDAL): true while the knock
## has the model, false once it is over (or before its slide shows, so the
## blow's own clip plays on). The sim says which slide is the push's
## (GridEntity.push_shown), so a slide cut short or drawn in pieces on a
## client, or one never drawn, is still known for what it is.
func _knocked(puppet: Node3D, animator: AnimationPlayer, speed: float, now: int) -> bool:
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
			animator.play_backwards(CLIP_ROLL, CLIP_BLEND)
			animator.speed_scale = ROLL_SPEED
			puppet.set_meta("busy_until", now + int(animator.get_animation(CLIP_ROLL).length / ROLL_SPEED * 1000.0))
		else:
			animator.play(CLIP_BACKPEDAL, CLIP_BLEND)
			animator.seek(0.0, true)
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
				animator.speed_scale = clampf(speed / (BACKPEDAL_CLIP_SPEED * float(puppet.get_meta("pace", 1.0))), 1.0, 4.0)
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


## The GAITS index for moving at [param speed] (tiles a second) from the
## clip playing, [param current]: a gait already reached holds till a little
## below its change.
static func gait_for(current: String, speed: float) -> int:
	var at := 0
	for i in GAITS.size():
		if GAITS[i][0] == current:
			at = i
	var index := 0
	for i in range(1, GAITS.size()):
		var change := sqrt(float(GAITS[i - 1][1]) * float(GAITS[i][1]))
		if speed > change * (1.0 / GAIT_HYSTERESIS if at >= i else GAIT_HYSTERESIS):
			index = i
	return index


## True if [param clip] is one of GAITS'.
static func is_gait(clip: String) -> bool:
	return GAITS.any(func(gait: Array) -> bool: return gait[0] == clip)


## Plays [param clip] once on [param puppet]'s model, if it has one, and
## holds it till done. False if there is no model.
func _play_once(puppet: Node3D, clip: String) -> bool:
	if not puppet.has_meta("animator"):
		return false
	var animator := puppet.get_meta("animator") as AnimationPlayer
	if not animator.has_animation(clip):
		return false
	animator.speed_scale = 1.0
	puppet.set_meta("fidgeting", false)
	animator.play(clip, CLIP_BLEND)
	animator.seek(0.0, true)
	puppet.set_meta("busy_until", Time.get_ticks_msec() + int(animator.get_animation(clip).length * 1000.0))
	return true


func _make_puppet(entity: GridEntity) -> Node3D:
	var puppet := Node3D.new()
	puppet.name = entity.name
	puppet.set_meta("entity_name", String(entity.name))
	puppet.set_meta("entity_id", entity.get_instance_id())
	var shape := EntityFactory.shape_name_for(entity.spawn_spec)
	var model := model_for(entity)
	if not model.is_empty():
		_vary(entity, puppet)
	var height: float = float(model["height"]) * float(puppet.get_meta("model_scale", 1.0)) if not model.is_empty() else Iso.HEIGHTS[shape]
	var material := StandardMaterial3D.new()
	var sprite := entity.get_node_or_null("Sprite") as Sprite2D
	material.albedo_color = sprite.modulate if sprite != null else Color.WHITE
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
	if model.is_empty():
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
		puppet.set_meta("bubble_height", height + BUBBLE_OVER_HEAD)
		# The nose: which way it faces, turned each frame (see _sync_puppets).
		# A model turns itself instead.
		var pivot := Node3D.new()
		pivot.name = "Facing"
		if model.is_empty():
			var nose := MeshInstance3D.new()
			var nose_mesh := BoxMesh.new()
			nose_mesh.size = Vector3(0.18, 0.1, 0.14)
			nose.mesh = nose_mesh
			nose.material_override = material
			nose.position = Vector3(0.3, height * 0.72, 0.0)
			pivot.add_child(nose)
		puppet.add_child(pivot)
		var id := entity.get_instance_id()
		entity.swung.connect(_on_swung.bind(id))
		entity.struck.connect(_on_struck.bind(id))
		entity.impacted.connect(_on_impacted.bind(id))
		entity.pushed.connect(_on_pushed.bind(id))
		if entity is Monster:
			(entity as Monster).winding.connect(_on_winding.bind(id))
		if entity.max_hp > 0:
			puppet.add_child(_make_bar(entity.max_hp, height + HP_BAR_ABOVE))
	elif entity.is_breakable():
		entity.impacted.connect(_on_impacted.bind(entity.get_instance_id()))
	if entity is Player or entity is Companion:
		var light := OmniLight3D.new()
		light.name = "Lantern"
		light.light_color = PLAYER_LIGHT
		light.light_energy = 1.2
		light.omni_range = PLAYER_LIGHT_RANGE
		light.shadow_enabled = true
		# Above the head: inside the body it would light the body from within
		# and leave its outside in its own shadow.
		light.position.y = height + 0.6
		puppet.add_child(light)
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
	sfx.play("swing", puppet.position + Vector3.UP * 0.8, lerpf(SWING_PITCH_LIGHT, SWING_PITCH_HEAVY, heft))
	if Time.get_ticks_msec() > int(puppet.get_meta("wound_until", 0)):
		_play_once(puppet, _pick_clip(puppet, ATTACK_CLIPS))
	var body := puppet.get_node("Body") as Node3D
	var rest := Vector3(0.0, body.position.y, 0.0)
	var out := rest + Vector3(direction.x, 0.0, direction.y).normalized() * LUNGE
	var tween := create_tween()
	tween.tween_property(body, "position", out, LUNGE_SECONDS * 0.4).set_ease(Tween.EASE_OUT)
	tween.tween_property(body, "position", rest, LUNGE_SECONDS * 0.6).set_ease(Tween.EASE_IN)


## A blow wound up over [param ticks]: the heavy swing, timed to connect
## as it lands.
func _on_winding(_direction: Vector2i, ticks: int, id: int) -> void:
	var puppet: Node3D = _puppets.get(id)
	if puppet == null:
		return
	_combat_at[id] = Time.get_ticks_msec()
	if not _play_once(puppet, CLIP_HEAVY):
		return
	var animator := puppet.get_meta("animator") as AnimationPlayer
	var seconds := ticks * World.TICK_DT
	animator.speed_scale = CLIP_HEAVY_CONTACT / seconds
	var now := Time.get_ticks_msec()
	puppet.set_meta("busy_until", now + int(animator.get_animation(CLIP_HEAVY).length / animator.speed_scale * 1000.0))
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


## The leaf of each door follows its Door node's open state.
func _sync_doors() -> void:
	for door in World.get_doors():
		var doorway: Node3D = _doorways.get(door.key)
		if doorway == null:
			continue
		var hinge := doorway.get_node("Hinge") as Node3D
		if _door_open.has(door.key) and _door_open[door.key] != door.is_open() and not door.is_broken():
			sfx.play("door_open" if door.is_open() else "door_close", doorway.position + Vector3.UP)
		_door_open[door.key] = door.is_open()
		hinge.visible = not door.is_broken()
		var target: float = PI * 0.5 if door.is_open() else 0.0
		hinge.rotation.y = move_toward(hinge.rotation.y, target, get_process_delta_time() / Door.SWING_SECONDS * PI * 0.5)

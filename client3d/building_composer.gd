class_name BuildingComposer
extends RefCounted
## Draws a building of a kind (Level.kinds, decision 488) from its blocks,
## seeded (decision 489): the grid is the rules and the look need not show
## it, so nothing here keeps to whole metres. Each block's roof by its role:
## the main block's a gable along its longer side at the kind's eaves; a
## wing's a gable a little lower; a lean-to's, an outshot's or a bay's a
## single slope rising to the block it leans on, its high side under that
## one's eaves. Every roof reaches past its walls (overhang), sags a little
## in the middle of its ridge, and is set a few centimetres off true; a
## round kind's one faceted cone over all its blocks. A chimney stands at a
## gable end of a house's main block when its seed says so (art-kit's
## chimney.stone if it is there, else a stack of the stone set); a porch
## over the front door and a cruck frame on a gable end by kind (art-kit's
## edge pieces). A ruin has no roof and no porch, perhaps its chimney.
## The walls and floors are not drawn here: they are the map's edges, the
## terrain's runs in the kind's sets (Client3D).
## What it makes is kept by kind, size, seed, facing and ruin (compose), so
## a street of one kind costs one build of each look; the copies share
## their meshes. Each block draws from its own seeded stream (_stream), its
## eaves first, so the walls under it are drawn to them (wall_heights)
## without building the roof.

## A roof's rise over its half-span, its overhang and its sag over its
## length, each seeded between these.
const RISE := Vector2(0.75, 1.1)
## A profile's own rise strays this far either way (734).
const RISE_SPREAD := 0.05
## A bellcast's reach past the walls when its profile says none (734).
const BELLCAST_REACH := 0.6
const REACH := Vector2(0.3, 0.5)
## A block's overhang strays this far either way from its roof set's
## (roof.<set>.profile's "overhang"; REACH's middle without one).
const REACH_SPREAD := 0.1
const SAG := Vector2(0.01, 0.025)
## How far below the main block's eaves a wing's are, and a lean-to's low
## eave; a lean-to's high side keeps LEAN_TUCK under them.
const WING_DROP := Vector2(0.25, 0.5)
const LEAN_DROP := Vector2(0.7, 1.0)
const LEAN_TUCK := 0.15
## A whole roof's tilt off true (radians) and each block's shift (m).
const TILT := 0.012
const SHIFT := 0.05
const THICK := 0.15
## Lengthwise steps of a slope, so its sag shows.
const STEPS := 8
## A round roof's facets and how far each point strays (of the radius).
const FACETS := 11
const FACET_STRAY := 0.05
## The kinds that may have a chimney, and how likely.
const CHIMNEYS := {"house": 0.7, "l_house": 0.7, "house_leanto": 0.6, "house_wing": 0.7, "two_storey": 0.8,
	"cottage": 0.8, "inn": 0.9, "hall": 0.6, "longhouse": 0.5, "hut": 0.3, "healers_hut": 0.5, "forge": 1.0, "butchery": 0.5}
const CHIMNEY := Vector3(0.75, 0.9, 0.65)
## A chimney's meta: where its smoke rises from (its top, in its frame).
const SMOKE_AT := &"smoke_at"
## A bayed roof's (734) pieces: each slope sheet, ridge, eave and hole's
## bay (meta BAY), a hole's mark (HOLE), its slopes' bays' ridge middles
## (BAY_MIDDLES, on the node _slopes makes), its height Callable (HEIGHT)
## and [rise, length, thickness] (SPAN) there too.
const BAY := &"bay"
const HOLE := &"hole"
const BAY_MIDDLES := &"bay_middles"
const HEIGHT := &"height"
const SPAN := &"span"
## A bayed roof's cut bays (734): damaged DAMAGED_BAYS of them, in
## disrepair DISREPAIR_BAYS (the damaged ones among them), each one more
## at times by its seed; show_bays' stream (_stream's salt).
const DAMAGED_BAYS := 2
const DISREPAIR_BAYS := 5
const BAY_SALT := 7341
## A gable's window (734) this far up its gable; a belfry this far in from
## its front wall.
const GABLE_WINDOW_UP := 0.4
const BELFRY_IN := 1.0
## The uses whose slot building (art with no chimney of its own) is given
## one (slot_chimney): a fire's trades.
const SLOT_HEARTHS: Array[String] = ["forge", "kitchen"]
## An art-walled slot's (Level.ART_WALLED, 718: the turf house) furnishings,
## each a socket of its own -> [prop slot, turn about y (radians)]: the pot
## on its tripod over the hearth, the bed its head to -x (art-kit's bed
## lies head -z), the shelf hung on the back wall.
const FURNISHINGS := {"hearth": ["prop.pot_tripod", 0.0], "bed": ["prop.bed_straw", PI / 2.0], "shelf": ["prop.shelf_herbs", 0.0]}
## Its wall quarters (north -z), each its way out from its middle (x, z).
const QUARTERS := {"wall_nw": Vector2(-1, -1), "wall_ne": Vector2(1, -1), "wall_sw": Vector2(-1, 1), "wall_se": Vector2(1, 1)}
## Its parts and the piece art_dress adds that only a ruin shows.
const WALLS_RUIN := "walls_ruin"
const STATE_RUIN := "state_ruin"
const RUIN_POT := "ruin_pot"
## Its hearth's flame (m), the pot's fire under it.
const HEARTH_FLAME := 0.5
## The kinds that may have a porch over their front door, and how likely;
## those with a cruck frame on a gable end, and the gable's span (cells)
## its 4.16 m frame suits.
const PORCHES := {"house": 0.5, "l_house": 0.5, "house_leanto": 0.4, "house_wing": 0.5, "two_storey": 0.4,
	"cottage": 0.4, "inn": 0.9, "hall": 0.6}
const CRUCKS := {"longhouse": 0.8, "cottage": 0.4, "hut": 0.3, "house": 0.2}
const CRUCK_SPAN := Vector2i(4, 6)
## How likely a wall of a straight stretch is a window (windows).
const WINDOW_ODDS := 0.3
## Posts under open edges (591): every this many vertices along a run, and
## a plain post's side where art-kit has none.
const OPEN_POST_EVERY := 2
const OPEN_POST := 0.22
## The kind drawn as a camp (649): tents and a fire ring, no roof (Level.ROOFLESS).
const CAMP := "camp"
## A camp's fire, cells from its middle toward its front; its tents, cells
## behind its middle, and each this far to a side of it when two.
const CAMP_FIRE_OUT := 1.0
const CAMP_TENT_BACK := 0.9
const CAMP_TENT_APART := 1.6
## The roles of blocks roofed with a single slope.
const LEANING: Array[String] = ["leanto", "outshot", "bay"]
## The stream salt for what is the building's own, not a block's.
const WHOLE := 1000

## Each look made, packed: a resource, so the cache holds no nodes (freed
## with the script, nothing left at exit), its meshes shared by every copy.
static var _made: Dictionary[String, PackedScene] = {}


## [param building] (Level's, with its kind) drawn: a Node3D whose origin is
## its box's top-left cell's middle at its ground, holding "roof" (every
## roof, what hides while the player is inside; none on a ruin) and
## "parts" (a chimney). [param roof_set] names the roof's material set.
static func compose(building: Dictionary, roof_set: String) -> Node3D:
	var key := "%s|%s|%d|%s|%s|%s|%s" % [building["kind"], building["size"], building["seed"], building["facing"],
		building.get("ruined", false), building["eaves"], roof_set]
	if not _made.has(key):
		var built := _build(building, roof_set)
		for node in built.find_children("*", "", true, false):
			# An art piece's body is an instance of its .glb's scene: made a
			# plain node of this look's, or packing keeps the instance and
			# its own nodes beside it, and each copy leaves those strays.
			node.scene_file_path = ""
			node.owner = built
		var packed := PackedScene.new()
		packed.pack(built)
		built.free()
		_made[key] = packed
	return _made[key].instantiate()


## Forgets what was made (a test, or new art).
static func forget() -> void:
	_made.clear()


## Each outline edge of [param building] -> the height its wall is drawn
## to: the eaves of the block whose cell it bounds (a wing's lower, a
## lean-to's its low eave), so no roof sits under its walls' tops.
static func wall_heights(building: Dictionary) -> Dictionary[Vector3i, float]:
	var out: Dictionary[Vector3i, float] = {}
	var blocks: Array = building["blocks"]
	var heights: Array[float] = []
	for index in blocks.size():
		heights.append(block_eaves(building, index))
	for key in Level.building_outline(building):
		for cell in Terrain.edge_cells(key):
			var index := blocks.find_custom(func(block: Rect2i) -> bool: return block.has_point(cell))
			if index >= 0:
				out[key] = heights[index]
				break
	return out


## Block [param index]'s eaves: the kind's for its main block (the largest)
## and for a round kind's every block; a lean-to's low eave, a wing's a
## little lower, as its stream draws first.
static func block_eaves(building: Dictionary, index: int) -> float:
	var eaves := float(building["eaves"])
	var blocks: Array = building["blocks"]
	if index == _main_of(blocks) or str(building.get("roof", "gable")) == "round":
		return eaves
	var rng := _stream(building, index)
	if _leaning(building, index):
		return eaves - rng.randf_range(LEAN_DROP.x, LEAN_DROP.y)
	return eaves - rng.randf_range(WING_DROP.x, WING_DROP.y)


## Whether block [param index] is a single slope leaning on another: its
## role a lean-to's, an outshot's or a bay's, and another block beside it.
static func _leaning(building: Dictionary, index: int) -> bool:
	var roles: Array = building.get("roles", [])
	return index < roles.size() and str(roles[index]) in LEANING 			and _leans_on(building["blocks"][index], building["blocks"]) != Vector2i.ZERO


## [param building]'s seeded stream for [param salt]: a block's index, or
## WHOLE for what is the building's own (its tilt, its chimney).
static func _stream(building: Dictionary, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(building["seed"]), salt])
	return rng


## The main block's roof's rise over its eaves, as _block_roof draws it
## (its stream: the reach, then the rise; its kind's roof set's profile).
static func _main_rise(building: Dictionary) -> float:
	var blocks: Array = building["blocks"]
	var main: Rect2i = blocks[_main_of(blocks)]
	var rng := _stream(building, _main_of(blocks))
	rng.randf()  # Its reach.
	var profile := _profile(_set_of(building, covered_in(building)))
	return float(mini(main.size.x, main.size.y)) * 0.5 * _rise_draw(profile, rng)


## [param roof_set]'s profile (roof.<set>.profile: its thickness and
## overhang, else THICK and REACH's middle; decision 734: its "rise" over
## the half-span, 0 for the seeded RISE; its "bellcast", how far its last
## "bellcast_reach" metres past the walls kick up flatter, 0 for none; its
## "bay", the length its cover is laid and broken in, 0 for one sheet).
static func _profile(roof_set: String) -> Dictionary:
	var out := {"thickness": THICK, "overhang": (REACH.x + REACH.y) * 0.5, "rise": 0.0, "bellcast": 0.0, "bellcast_reach": BELLCAST_REACH,
		"bay": 0.0}
	var slot := "roof.%s.profile" % roof_set
	if ArtKit.has(slot):
		var spec := ArtKit.spec(slot)
		for key: String in out:
			out[key] = float(spec.get(key, out[key]))
	return out


## The roof set whose profile and edge pieces [param building] takes:
## [param roof_set], the one it is covered in, unless that stands in for
## its kind's own ("roof_set") whose material art-kit has not made but
## whose profile it has (734: the temple's slate before its slates).
static func _set_of(building: Dictionary, roof_set: String) -> String:
	var named := str(building.get("roof_set", ""))
	if named.is_empty() or ArtKit.has("material.roof." + named) or not ArtKit.has("roof.%s.profile" % named):
		return roof_set
	return named


## The roof set Client3D covers [param building] in (_add_kind): its
## kind's own where art-kit has its material, else KIND_ROOF.
static func covered_in(building: Dictionary) -> String:
	var named := str(building.get("roof_set", ""))
	return named if not named.is_empty() and ArtKit.has("material.roof." + named) else Client3D.KIND_ROOF


## A gable's rise over its half-span, drawn from [param rng] (one draw):
## the profile's own "rise", a little either way, else RISE's range.
static func _rise_draw(profile: Dictionary, rng: RandomNumberGenerator) -> float:
	var rise := float(profile.get("rise", 0.0))
	if rise > 0.0:
		return rng.randf_range(rise - RISE_SPREAD, rise + RISE_SPREAD)
	return rng.randf_range(RISE.x, RISE.y)


## The index of [param blocks]' largest (the first of the largest).
static func _main_of(blocks: Array) -> int:
	var best := 0
	for index in blocks.size():
		if (blocks[index] as Rect2i).get_area() > (blocks[best] as Rect2i).get_area():
			best = index
	return best


static func _build(building: Dictionary, roof_set: String) -> Node3D:
	var rng := _stream(building, WHOLE)
	var rect: Rect2i = building["rect"]
	var blocks: Array = building["blocks"]
	var eaves := float(building["eaves"])
	var out := Node3D.new()
	out.name = "Composed"
	var parts := Node3D.new()
	parts.name = "parts"
	out.add_child(parts)
	var main: Rect2i = blocks[_main_of(blocks)]
	var ruined: bool = building.get("ruined", false)
	var roofless := Level.roofless(building)
	if not roofless:
		_open_posts(building, parts)
	if building["kind"] == CAMP:
		_camp(building, parts)
	if not roofless:
		var roof := Node3D.new()
		roof.name = "roof"
		roof.rotation = Vector3(rng.randf_range(-TILT, TILT), 0.0, rng.randf_range(-TILT, TILT))
		out.add_child(roof)
		var material := Client3D._roof_material(roof_set)
		var gable := Client3D._wall_material(Client3D._known_set(str(building.get("wall_set", Client3D.DEFAULT_SET)))).duplicate() as StandardMaterial3D
		gable.cull_mode = BaseMaterial3D.CULL_DISABLED
		if str(building.get("roof", "gable")) == "round":
			roof.add_child(_cone(Vector2(rect.size), eaves, rng, material))
		else:
			var trim_set := _set_of(building, roof_set)
			for index in blocks.size():
				var piece := _block_roof(building, index, material, gable, _profile(trim_set), trim_set)
				piece.name = "Roof_%d" % index
				roof.add_child(piece)
			_gable_windows(building, roof)
			_belfry(building, roof)
			# Its slopes' height is a lambda, which a packed look can't keep.
			for node: Node in roof.find_children("*", "Node3D", true, false):
				if node.has_meta(HEIGHT):
					node.remove_meta(HEIGHT)
	var odds := float(CHIMNEYS.get(str(building["kind"]), 0.0)) * (0.6 if ruined else 1.0)
	if rng.randf() < odds and str(building.get("roof", "gable")) != "round" and str(building.get("roof", "")) != Level.ROOFLESS:
		parts.add_child(_chimney(building, main, rect, eaves, rng))
	if not roofless and rng.randf() < float(PORCHES.get(str(building["kind"]), 0.0)):
		var porch := porch_of(building)
		if porch != null:
			parts.add_child(porch)
	if rng.randf() < float(CRUCKS.get(str(building["kind"]), 0.0)):
		var cruck := cruck_of(building, rng.randf() < 0.5)
		if cruck != null:
			parts.add_child(cruck)
	if not ruined:
		_buttresses(building, parts)
		_steps(building, parts)
	return out


## Art-kit's edge piece [param slot] (along z, its front +x, its origin on
## the edge's middle at the ground) at [param middle] (the building's
## frame, x and z) with its front toward [param out]; null if the slot is
## not there.
static func _edge_piece(slot: String, middle: Vector2, out: Vector2i) -> Node3D:
	if not ArtKit.has(slot):
		return null
	var piece := ArtKit.instance(slot)
	piece.name = slot.get_slice(".", 0).capitalize()
	piece.position = Vector3(middle.x, 0.0, middle.y)
	piece.rotation.y = atan2(-float(out.y), float(out.x))
	return piece


## [param building]'s window edges, seeded by cell: walls of its outline in
## a straight stretch (both neighbours along the line its walls too, not a
## corner, nor beside a door), at WINDOW_ODDS each, never two side by side.
## A ruin has none. [param edges] are the map's (Terrain.Edge by key).
static func windows(building: Dictionary, edges: Dictionary) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if building.get("ruined", false):
		return out
	var bays := _wall_bays(building)
	if not bays.is_empty():
		return bays["windows"]  # A chapel's lancets (734), between its buttresses.
	var outline := Level.building_outline(building)
	var wall := func(key: Vector3i) -> bool: return key in outline and edges.get(key) == Terrain.Edge.WALL
	for key in outline:
		var step := Vector3i(0, 1, 0) if key.z == Terrain.EAST else Vector3i(1, 0, 0)
		if not wall.call(key) or not wall.call(key - step) or not wall.call(key + step) or out.has(key - step):
			continue
		var roll := float(absi(hash([int(building["seed"]), key])) % 10007) / 10007.0
		if roll < WINDOW_ODDS:
			out.append(key)
	return out


## [param building]'s wall set's profile (wall.<set>.profile), {} without.
static func _wall_profile(building: Dictionary) -> Dictionary:
	var slot := "wall.%s.profile" % str(building.get("wall_set", ""))
	return ArtKit.spec(slot) if ArtKit.has(slot) else {}


## A buttressed wall set's (734: its profile's "windows" is
## "between_buttresses") bays along [param building]'s main block's long
## sides: "buttresses", [vertex middle, outward side] at every second
## vertex along each side (none at a corner, nor by a door), and
## "windows", the edge between each two (none at a side's ends, nor by a
## door); {} for any other set.
static func _wall_bays(building: Dictionary) -> Dictionary:
	if str(_wall_profile(building).get("windows", "")) != "between_buttresses":
		return {}
	var blocks: Array = building["blocks"]
	var main: Rect2i = blocks[_main_of(blocks)]
	var rect: Rect2i = building["rect"]
	var along_x := main.size.x > main.size.y
	var doors: Array = building.get("doors", [])
	var box := Rect2(Vector2(main.position) - Vector2(0.5, 0.5), Vector2(main.size))
	# Each long side's edges in order along it: [where along, key, middle].
	var sides: Dictionary[Vector2i, Array] = {}
	for key in Level.building_outline(building):
		var edge := _edge_out(building, key)
		var middle: Vector2 = Vector2(rect.position) + edge[0]
		var out: Vector2i = edge[1]
		if (out.y if along_x else out.x) == 0:
			continue
		var line := middle.y if along_x else middle.x
		var place := middle.x if along_x else middle.y
		var on_line := is_equal_approx(line, box.position.y if along_x else box.position.x) \
				or is_equal_approx(line, box.end.y if along_x else box.end.x)
		var within := place > (box.position.x if along_x else box.position.y) and place < (box.end.x if along_x else box.end.y)
		if not on_line or not within:
			continue
		if not sides.has(out):
			sides[out] = []
		sides[out].append([place, key, edge[0]])
	var buttresses: Array = []
	var windows: Array[Vector3i] = []
	for out: Vector2i in sides:
		var run: Array = sides[out]
		run.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		var door := func(i: int) -> bool: return i >= 0 and i < run.size() and doors.has(run[i][1])
		for i in range(1, run.size()):
			if i % 2 == 0 and not door.call(i - 1) and not door.call(i):
				buttresses.append([((run[i - 1][2] as Vector2) + (run[i][2] as Vector2)) * 0.5, out])
		for i in range(1, run.size() - 1):
			if i % 2 == 1 and not door.call(i - 1) and not door.call(i) and not door.call(i + 1):
				windows.append(run[i][1])
	return {"buttresses": buttresses, "windows": windows}


## A buttressed set's buttresses (734: wall.<set>.buttress_tall) in
## [param parts], its +x out from the wall; none without the slot.
static func _buttresses(building: Dictionary, parts: Node3D) -> void:
	var slot := "wall.%s.buttress_tall" % str(building.get("wall_set", ""))
	var bays := _wall_bays(building)
	if bays.is_empty() or not ArtKit.has(slot):
		return
	for index in (bays["buttresses"] as Array).size():
		var entry: Array = bays["buttresses"][index]
		var piece := _edge_piece(slot, entry[0], entry[1])
		piece.name = "Buttress_%d" % index
		parts.add_child(piece)


## Its wall set's steps (734: steps.<set>, a chapel's) before
## [param building]'s front doors, out from their middle; none without.
static func _steps(building: Dictionary, parts: Node3D) -> void:
	var slot := "steps.%s" % str(building.get("wall_set", ""))
	if not ArtKit.has(slot):
		return
	var facing: Vector2i = building["facing"]
	var middle := Vector2.ZERO
	var count := 0
	for key: Vector3i in building.get("doors", []):
		var edge := _edge_out(building, key)
		if edge[1] == facing:
			middle += edge[0]
			count += 1
	if count == 0:
		return
	var piece := _edge_piece(slot, middle / count, facing)
	piece.name = "Steps"
	parts.add_child(piece)


## The main block's gable roof's slopes (_slopes' node, with its HEIGHT and
## SPAN) under [param roof], and the sign of its z toward
## [param building]'s front; [] for a round, lean-to or missing one.
static func _main_slopes(building: Dictionary, roof: Node3D) -> Array:
	var holder := roof.get_node_or_null("Roof_%d" % _main_of(building["blocks"])) as Node3D
	if holder == null or holder.get_child_count() == 0 or not holder.get_child(0).has_meta(SPAN):
		return []
	var facing: Vector2i = building["facing"]
	var front := holder.basis.inverse() * Vector3(facing.x, 0.0, facing.y)
	return [holder.get_child(0), signf(front.z) if absf(front.z) > 0.5 else 1.0]


## Its wall set's gable windows (734): gable.<set>.rose on its main roof's
## front gable, gable.<set>.oculus on its back, each centred
## GABLE_WINDOW_UP of the way up its gable, its +x outward; in the roof, so
## it hides and fades with it. A slot art-kit has not got is left out.
static func _gable_windows(building: Dictionary, roof: Node3D) -> void:
	var found := _main_slopes(building, roof)
	if found.is_empty():
		return
	var slopes: Node3D = found[0]
	var span: Vector3 = slopes.get_meta(SPAN)
	for pair: Array in [["rose", float(found[1])], ["oculus", -float(found[1])]]:
		var slot := "gable.%s.%s" % [building.get("wall_set", ""), pair[0]]
		if not ArtKit.has(slot):
			continue
		var piece := ArtKit.instance(slot)
		piece.name = str(pair[0]).capitalize()
		piece.position = Vector3(0.0, span.x * GABLE_WINDOW_UP, float(pair[1]) * span.y * 0.5)
		piece.rotation.y = -float(pair[1]) * PI * 0.5
		slopes.add_child(piece)


## Its wall set's belfry (734: belfry.<set>) on its main roof's ridge,
## BELFRY_IN from its front wall, its foot's middle on the ridge, facing
## its front; in the roof. None without the slot.
static func _belfry(building: Dictionary, roof: Node3D) -> void:
	var slot := "belfry.%s" % str(building.get("wall_set", ""))
	var found := _main_slopes(building, roof)
	if found.is_empty() or not ArtKit.has(slot):
		return
	var slopes: Node3D = found[0]
	var span: Vector3 = slopes.get_meta(SPAN)
	var z := float(found[1]) * (span.y * 0.5 - BELFRY_IN)
	var piece := ArtKit.instance(slot)
	piece.name = "Belfry"
	piece.position = Vector3(0.0, float((slopes.get_meta(HEIGHT) as Callable).call(0.0, z)) + span.z, z)
	piece.rotation.y = -float(found[1]) * PI * 0.5
	slopes.add_child(piece)


## Whether [param composed] has a bayed roof (734): one cut by bay.
static func bayed(composed: Node3D) -> bool:
	return not _bayed_slopes(composed).is_empty()


static func _bayed_slopes(composed: Node3D) -> Array[Node]:
	return composed.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return node.has_meta(BAY_MIDDLES))


## [param composed]'s bayed roofs (734) covered as [param cover] says:
## "whole"; "half", only the bays nearer [param building]'s front on (its
## covering stage), the rest bare; "damaged" or "disrepair", its seed's
## DAMAGED_BAYS or DISREPAIR_BAYS (one more at times) cut, each a hole
## (roof.<set>.hole) where art-kit has one, else open; disrepair's cut
## bays always the damaged ones and more.
static func show_bays(building: Dictionary, composed: Node3D, cover: String) -> void:
	var facing := Vector3(float((building["facing"] as Vector2i).x), 0.0, float((building["facing"] as Vector2i).y))
	for slopes: Node3D in _bayed_slopes(composed):
		var middles: Array = slopes.get_meta(BAY_MIDDLES)
		var frame := Transform3D.IDENTITY
		var node: Node = slopes
		while node != composed and node is Node3D:
			frame = (node as Node3D).transform * frame
			node = node.get_parent()
		var order: Array = range(middles.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			return (frame * (middles[a] as Vector3)).dot(facing) > (frame * (middles[b] as Vector3)).dot(facing))
		var bare: Array = []
		var cut: Array = []
		if cover == "half":
			bare = order.slice(ceili(middles.size() * 0.5))
		elif cover == "damaged" or cover == "disrepair":
			var rng := _stream(building, BAY_SALT)
			var shuffled: Array = range(middles.size())
			for i in range(shuffled.size() - 1, 0, -1):
				var j := rng.randi_range(0, i)
				var swap: int = shuffled[i]
				shuffled[i] = shuffled[j]
				shuffled[j] = swap
			var some := DAMAGED_BAYS + rng.randi_range(0, 1)
			var more := DISREPAIR_BAYS + rng.randi_range(0, 1)
			cut = shuffled.slice(0, mini(some if cover == "damaged" else more, middles.size()))
		var pieces: Array[Node] = slopes.find_children("*", "Node3D", true, false)
		for piece: Node in pieces:
			if not piece.has_meta(BAY):
				continue
			var k: int = piece.get_meta(BAY)
			(piece as Node3D).visible = not bare.has(k) and cut.has(k) == piece.has_meta(HOLE)


## [param key]'s middle in [param building]'s frame and its outward side
## (from its inside cell to its outside one).
static func _edge_out(building: Dictionary, key: Vector3i) -> Array:
	var rect: Rect2i = building["rect"]
	var sides := Terrain.edge_cells(key)
	var inside := Level.building_cells(building).has(sides[0])
	var out := (sides[1] - sides[0]) * (1 if inside else -1)
	return [(Vector2(sides[0]) + Vector2(sides[1])) * 0.5 - Vector2(rect.position), out]


## A porch over [param building]'s first door (art-kit's porch.timber; its
## wide one, porch.timber_wide, over a door two edges wide), null without
## the slot or a door.
static func porch_of(building: Dictionary) -> Node3D:
	var doors: Array = building.get("doors", [])
	if doors.is_empty():
		return null
	var first: Array = _edge_out(building, doors[0])
	var wide: bool = doors.size() > 1 and (_edge_out(building, doors[1])[0] as Vector2).distance_to(first[0]) < 1.01 \
			and _edge_out(building, doors[1])[1] == first[1]
	var middle: Vector2 = first[0]
	if wide:
		middle = (middle + (_edge_out(building, doors[1])[0] as Vector2)) * 0.5
	return _edge_piece("porch.timber_wide" if wide and ArtKit.has("porch.timber_wide") else "porch.timber", middle, first[1])


## A cruck frame on a gable end of [param building]'s main block (the far
## one from its doors, else [param far]'s pick), its outer face out; null
## without the slot, or where the gable is not CRUCK_SPAN wide.
static func cruck_of(building: Dictionary, far: bool) -> Node3D:
	var blocks: Array = building["blocks"]
	var main: Rect2i = blocks[_main_of(blocks)]
	var rect: Rect2i = building["rect"]
	var along_x := main.size.x > main.size.y
	var span := main.size.y if along_x else main.size.x
	if span < CRUCK_SPAN.x or span > CRUCK_SPAN.y:
		return null
	var middle := Vector2(main.position - rect.position) + Vector2(main.size - Vector2i.ONE) * 0.5
	var reach := float(main.size.x if along_x else main.size.y) * 0.5
	var ends: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0)]
	if not along_x:
		ends = [Vector2i(0, 1), Vector2i(0, -1)]
	var outline := Level.building_outline(building)
	var doored := ends.filter(func(side: Vector2i) -> bool:
		return (building.get("doors", []) as Array).any(func(key: Vector3i) -> bool:
			return key in outline and _edge_out(building, key)[1] == side))
	var free := ends.filter(func(side: Vector2i) -> bool: return not side in doored)
	if free.is_empty():
		return null
	var side: Vector2i = free[0] if free.size() == 1 or not far else free[1]
	return _edge_piece("frame.cruck", middle + Vector2(side) * reach, side)


## Block [param index]'s roof by its role, placed in the building's frame
## (its box's top-left cell's middle at the origin), from its own stream.
static func _block_roof(building: Dictionary, index: int, material: Material, gable: Material, profile: Dictionary,
		trim_set := "") -> Node3D:
	var blocks: Array = building["blocks"]
	var block: Rect2i = blocks[index]
	var rect: Rect2i = building["rect"]
	var eaves := float(building["eaves"])
	var is_main := index == _main_of(blocks)
	var rng := _stream(building, index)
	var at := eaves if is_main else block_eaves(building, index)
	if not is_main:
		rng.randf()  # Its eaves' draw, made by block_eaves.
	var middle := Vector2(block.position - rect.position) + Vector2(block.size - Vector2i.ONE) * 0.5
	# Its overhang about its roof set's, a little either way.
	var reach := rng.randf_range(profile["overhang"] - REACH_SPREAD, profile["overhang"] + REACH_SPREAD)
	var thick: float = profile["thickness"]
	var holder := Node3D.new()
	var leans := _leans_on(block, blocks)
	if not is_main and _leaning(building, index):
		# A single slope, its high side toward the block it leans on.
		var across := float(block.size.x if leans.x != 0 else block.size.y)
		var along := float(block.size.y if leans.x != 0 else block.size.x)
		var low := at
		var rise := maxf(eaves - LEAN_TUCK - low, 0.3)
		holder.add_child(_slopes(across, along, rise, reach, rng.randf_range(SAG.x, SAG.y) * along, true, thick, material, gable, trim_set, profile))
		holder.position = Vector3(middle.x, low, middle.y)
		holder.rotation.y = {Vector2i(1, 0): 0.0, Vector2i(-1, 0): PI, Vector2i(0, 1): -PI * 0.5, Vector2i(0, -1): PI * 0.5}[leans]
	else:
		var along_x := block.size.x > block.size.y
		var span := Vector2(block.size.y, block.size.x) if along_x else Vector2(block.size)
		var rise := span.x * 0.5 * _rise_draw(profile, rng)
		holder.add_child(_slopes(span.x, span.y, rise, reach, rng.randf_range(SAG.x, SAG.y) * span.y, false, thick, material, gable, trim_set, profile))
		holder.position = Vector3(middle.x, at, middle.y)
		holder.rotation.y = PI * 0.5 if along_x else 0.0
	holder.position += Vector3(rng.randf_range(-SHIFT, SHIFT), 0.0, rng.randf_range(-SHIFT, SHIFT))
	return holder


## The side of [param block] (a unit step) most of whose outside cells are
## another block's: what a lean-to leans on; ZERO for none.
static func _leans_on(block: Rect2i, blocks: Array) -> Vector2i:
	var best := Vector2i.ZERO
	var most := 0
	for side: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var touching := 0
		for cell in Level.rect_cells(block):
			var next := cell + side
			if block.has_point(next):
				continue
			for other: Rect2i in blocks:
				if other != block and other.has_point(next):
					touching += 1
					break
		if touching > most:
			most = touching
			best = side
	return best


## A roof's slopes across x and along z, its eaves at y 0: a gable from
## both eaves to the ridge over x = 0, or a lean-to ([param mono]) from its
## low eave at -x to its high side at +x; reaching [param reach] past the
## walls each way, the ridge sagging [param sag] in the middle of its
## length (the eaves do not), a top [param thick] above its underside; and its
## ends closed down to the eaves in [param gable]. Its [param profile]'s
## bellcast (decision 734) kicks its low edges up flatter past the walls.
## Its roof set's ([param trim_set]) edge pieces laid along it (_trims).
static func _slopes(across: float, along: float, rise: float, reach: float, sag: float, mono: bool, thick: float,
		material: Material, gable: Material, trim_set := "", profile := {}) -> Node3D:
	var half := across * 0.5
	var edge := half + reach
	var length := along + reach * 2.0
	# The bellcast: none on the walls' line, its full lift at the eave.
	var cast := float(profile.get("bellcast", 0.0))
	var cast_from := maxf(half, edge - float(profile.get("bellcast_reach", BELLCAST_REACH)))
	var height := func(x: float, z: float) -> float:
		var h := rise * (x + half) / across if mono else rise * (1.0 - absf(x) / half)
		var t := clampf(h / rise, 0.0, 1.0)
		var u := 2.0 * z / length
		var out := h - sag * (1.0 - u * u) * t
		var low := -x if mono else absf(x)
		if cast > 0.0 and low > cast_from and edge > cast_from:
			out += cast * pow((low - cast_from) / (edge - cast_from), 2.0)
		return out
	var xs: Array[float] = [-edge, edge]
	if not mono:
		xs.insert(1, 0.0)
	if cast > 0.0 and edge > cast_from:
		# Its curve's own points, so the kick bends.
		for low: float in [cast_from, (cast_from + edge) * 0.5]:
			xs.append(-low)
			if not mono:
				xs.append(low)
		xs.sort()
	var out := Node3D.new()
	out.set_meta(HEIGHT, height)
	out.set_meta(SPAN, Vector3(rise, along, thick))
	# A bayed cover (734): a sheet a bay, each its own to cut (show_bays).
	var bay := float(profile.get("bay", 0.0))
	var bays := maxi(ceili(length / bay - 0.01), 1) if bay > 0.0 else 1
	var middles: Array[Vector3] = []
	for b in bays:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var steps := STEPS if bays == 1 else maxi(ceili(float(STEPS) / bays), 1)
		for i in xs.size() - 1:
			for j in steps:
				var z0 := -length * 0.5 + length * (b * steps + j) / (bays * steps)
				var z1 := -length * 0.5 + length * (b * steps + j + 1) / (bays * steps)
				for lift in [thick, 0.0]:
					var corners := [Vector3(xs[i], height.call(xs[i], z0) + lift, z0), Vector3(xs[i], height.call(xs[i], z1) + lift, z1),
						Vector3(xs[i + 1], height.call(xs[i + 1], z1) + lift, z1), Vector3(xs[i + 1], height.call(xs[i + 1], z0) + lift, z0)]
					for k in [0, 1, 2, 0, 2, 3]:
						var corner: Vector3 = corners[k]
						tool.set_uv(Vector2(corner.z + length * 0.5, absf(corner.x)) / 2.0)
						tool.add_vertex(corner)
		tool.generate_normals()
		var slopes := MeshInstance3D.new()
		slopes.name = "Slopes" if bays == 1 else "Slopes_%d" % b
		slopes.mesh = tool.commit()
		slopes.material_override = material
		out.add_child(slopes)
		if bays > 1:
			var z := -length * 0.5 + length * (b + 0.5) / bays
			middles.append(Vector3(0.0, float(height.call(0.0, z)), z))
			slopes.set_meta(BAY, b)
	if bays > 1:
		out.set_meta(BAY_MIDDLES, middles)
	var ends := SurfaceTool.new()
	ends.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in [-along * 0.5, along * 0.5]:
		var points: Array[Vector3] = [Vector3(-half, 0.0, z), Vector3(half, 0.0, z)]
		points.append(Vector3(half, height.call(half, z), z) if mono else Vector3(0.0, height.call(0.0, z), z))
		for point in points:
			ends.set_uv(Vector2(point.x, -point.y) / Client3D.WALL_TILE)
			ends.add_vertex(point)
	ends.generate_normals()
	var gables := MeshInstance3D.new()
	gables.name = "Gables"
	gables.mesh = ends.commit()
	gables.material_override = gable
	out.add_child(gables)
	if trim_set == "thatch" or bays > 1:  # Thatch's rolls, a bayed set's pieces (734); shingle's are slot roofs'.
		var trims := _trims(trim_set, height, edge, length, rise / across if mono else rise / half, mono, thick, bays)
		if trims.get_child_count() > 0:
			out.add_child(trims)
		else:
			trims.free()
	return out


## A roof's edge pieces (489 amended; decision 734 for every set), art-kit's
## roof.<set>.ridge along a gable's ridge, roof.<set>.eave along each low
## eave (a lean-to's high side meets its wall and has none), one a metre
## over [param length]; roof.<set>.verge up each end's slope edges, one a
## metre along the slope (the last shortened), its +x out past the end;
## roof.<set>.end on each end of a gable's ridge. All on the top of the
## cover ([param thick] above [param height]'s underside), the ridge's
## pitched to its sag, the eaves' turned outward and laid down the slope
## ([param pitch] its fall a metre). Thatch's rolls have their origin in
## their middle; every other set's at their -z end (art-kit's rule).
## Slots art-kit has not got are left out.
static func _trims(roof_set: String, height: Callable, edge: float, length: float, pitch: float, mono: bool, thick: float,
		bays := 1) -> Node3D:
	var out := Node3D.new()
	out.name = "Trim"
	var centred := roof_set == "thatch"
	var slot := func(piece: String) -> String: return "roof.%s.%s" % [roof_set, piece]
	var bayed := bays > 1
	var count := bays if bayed else maxi(ceili(length), 1)
	var step := length / count
	var sides: Array[float] = [-1.0]
	if not mono:
		sides.append(1.0)
	for k in count:
		var z := -length * 0.5 + step * (k + (0.5 if centred else 0.0))
		if not mono and ArtKit.has(slot.call("ridge")):
			var ridge := ArtKit.instance(slot.call("ridge"))
			ridge.name = "Ridge_%d" % k
			var fall := (float(height.call(0.0, z + 0.05)) - float(height.call(0.0, z - 0.05))) / 0.1
			ridge.position = Vector3(0.0, float(height.call(0.0, z)) + thick, z)
			ridge.rotation.x = -atan(fall)
			if bayed:
				ridge.set_meta(BAY, k)
			out.add_child(ridge)
		if ArtKit.has(slot.call("eave")):
			for side in sides:
				var eave := ArtKit.instance(slot.call("eave"))
				eave.name = "Eave_%d_%d" % [k, side]
				eave.position = Vector3(side * edge, float(height.call(side * edge, z)) + thick, z)
				# Its +x out past the eave, its -x up the slope under the cover.
				eave.rotation = Vector3(0.0, 0.0 if side > 0.0 else PI, -atan(pitch))
				if bayed:
					eave.set_meta(BAY, k)
				out.add_child(eave)
		if bayed and ArtKit.has(slot.call("hole")):
			# A bay's hole, hidden till its bay is cut (show_bays): laid in
			# the middle of each slope, its +y off the slope.
			for side in sides:
				var x := side * edge * 0.5 if not mono else 0.0
				var lean := Vector3(-pitch * side if not mono else -pitch, 1.0, 0.0)
				var hole := _laid(ArtKit.instance(slot.call("hole")), Vector3(x, float(height.call(x, z)) + thick, z),
						Vector3(x, float(height.call(x, z + step)) + thick, z + step), Vector3(side, 0.0, 0.0), false, lean)
				hole.name = "Hole_%d_%d" % [k, side]
				hole.set_meta(BAY, k)
				hole.set_meta(HOLE, true)
				hole.visible = false
				out.add_child(hole)
	for end: float in [-1.0, 1.0]:
		var z := end * length * 0.5
		if ArtKit.has(slot.call("verge")):
			# Each slope's edge, from its eave up: a gable's two, a lean-to's one.
			var runs: Array = [[-edge, 0.0], [edge, 0.0]] if not mono else [[-edge, edge]]
			for run: Array in runs:
				var pieces := maxi(ceili(absf(float(run[1]) - float(run[0])) / cos(atan(pitch))), 1)
				for i in pieces:
					var x0: float = lerpf(run[0], run[1], float(i) / pieces)
					var x1: float = lerpf(run[0], run[1], float(i + 1) / pieces)
					var verge := _laid(ArtKit.instance(slot.call("verge")),
							Vector3(x0, float(height.call(x0, z)) + thick, z), Vector3(x1, float(height.call(x1, z)) + thick, z),
							Vector3(0.0, 0.0, end), centred)
					verge.name = "Verge_%d_%d_%d" % [end, run[0], i]
					out.add_child(verge)
		if not mono and ArtKit.has(slot.call("end")):
			var cap := ArtKit.instance(slot.call("end"))
			cap.name = "End_%d" % end
			cap.position = Vector3(0.0, float(height.call(0.0, z)) + thick, z)
			cap.rotation.y = 0.0 if end > 0.0 else PI
			out.add_child(cap)
	return out


## [param piece] (1 m along its z) laid from [param a] to [param b],
## stretched to fit: its +x toward [param outward], its +y off the line
## toward [param up], its origin at its -z end (in its middle when
## [param centred]).
static func _laid(piece: Node3D, a: Vector3, b: Vector3, outward: Vector3, centred: bool, up := Vector3.UP) -> Node3D:
	var z := (b - a).normalized()
	var y := (up - z * up.dot(z)).normalized()
	var x := y.cross(z)
	if x.dot(outward) < 0.0:
		var swap := a
		a = b
		b = swap
		z = -z
		x = -x
	piece.transform = Transform3D(Basis(x, y, z) * Basis.from_scale(Vector3(1.0, 1.0, a.distance_to(b))), (a + b) * 0.5 if centred else a)
	return piece


## A round kind's roof: a cone of FACETS faces over its box (its blocks'
## cells inside it), its points straying a little, reaching past the walls.
static func _cone(size: Vector2, eaves: float, rng: RandomNumberGenerator, material: Material) -> Node3D:
	var radius := maxf(size.x, size.y) * 0.5 + rng.randf_range(REACH.x, REACH.y)
	var apex := Vector3(rng.randf_range(-SHIFT, SHIFT), radius * rng.randf_range(1.0, 1.3), rng.randf_range(-SHIFT, SHIFT))
	var drop := radius - maxf(size.x, size.y) * 0.5
	var rim: Array[Vector3] = []
	for k in FACETS:
		var angle := TAU * k / FACETS
		var r := radius * (1.0 + rng.randf_range(-FACET_STRAY, FACET_STRAY))
		rim.append(Vector3(cos(angle) * r, -drop * 0.6, sin(angle) * r))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in FACETS:
		for point: Vector3 in [rim[k], rim[(k + 1) % FACETS], apex]:
			tool.set_uv(Vector2(point.x, point.z) / 2.0)
			tool.add_vertex(point)
	tool.generate_normals()
	var cone := MeshInstance3D.new()
	cone.name = "Cone"
	cone.mesh = tool.commit()
	cone.material_override = material
	var holder := Node3D.new()
	holder.name = "Roof_0"
	holder.position = Vector3((size.x - 1.0) * 0.5, eaves, (size.y - 1.0) * 0.5)
	holder.add_child(cone)
	return holder


## A chimney at one gable end of [param main], a little off its middle:
## art-kit's chimney.stone seated on the roof where it stands (the slope's
## height there, so its stack clears the roof round it however steep), else
## a stack and cap of the stone set from the ground to over the ridge. Its
## top (meta SMOKE_AT, in its own frame) is where its smoke rises from.
static func _chimney(building: Dictionary, main: Rect2i, rect: Rect2i, eaves: float, rng: RandomNumberGenerator) -> Node3D:
	var middle := Vector2(main.position - rect.position) + Vector2(main.size - Vector2i.ONE) * 0.5
	var along_x := main.size.x > main.size.y
	var end := (float(main.size.x if along_x else main.size.y) * 0.5 - 0.35) * (1.0 if rng.randf() < 0.5 else -1.0)
	var off := rng.randf_range(-0.3, 0.3)
	var at := middle + (Vector2(end, off) if along_x else Vector2(off, end))
	var half := float(mini(main.size.x, main.size.y)) * 0.5
	var rise := _main_rise(building)
	var ridge := eaves + rise
	var out := Node3D.new()
	out.name = "Chimney"
	out.position = Vector3(at.x, 0.0, at.y)
	out.rotation.y = rng.randf_range(-0.05, 0.05)
	if ArtKit.has("chimney.stone"):
		var piece := ArtKit.instance("chimney.stone")
		piece.position.y = eaves + rise * (1.0 - absf(off) / half)
		out.add_child(piece)
		out.set_meta(SMOKE_AT, Vector3(0.0, piece.position.y + ArtKit.size("chimney.stone").y, 0.0))
		return out
	var stone := Client3D._wall_material("stone")
	var tall := ridge + rng.randf_range(0.4, 0.8)
	for part: Array in [[Vector3(CHIMNEY.x, tall, CHIMNEY.z), tall * 0.5], [Vector3(CHIMNEY.x + 0.12, 0.14, CHIMNEY.z + 0.12), tall + 0.07]]:
		var box := MeshInstance3D.new()
		var shape := BoxMesh.new()
		shape.size = part[0]
		box.mesh = shape
		box.material_override = stone
		box.position.y = part[1]
		out.add_child(box)
	out.set_meta(SMOKE_AT, Vector3(0.0, tall + 0.14, 0.0))
	return out


## A chimney for slot building [param slot] (its art has none) used as
## [param use]: one of SLOT_HEARTHS, art-kit's chimney.stone seated on the
## roof near one gable end, a little down the slope (the slot's ridge runs
## along z over its middle, its eaves at wall_height); null for another
## use, a slot without a pitched roof, or no chimney.stone.
static func slot_chimney(slot: String, use: String, seed: int) -> Node3D:
	if not use in SLOT_HEARTHS or not ArtKit.has("chimney.stone") or not ArtKit.has(slot):
		return null
	var spec := ArtKit.spec(slot)
	var size := ArtKit.size(slot)
	var eaves := float(spec.get("wall_height", Client3D.WALL_HEIGHT))
	var rise := size.y - eaves
	if rise < 0.3 or size.x < 1.5:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var half := size.x * 0.5
	var off := rng.randf_range(0.35, 0.55) * (1.0 if rng.randf() < 0.5 else -1.0)
	var end := (size.z * 0.5 - 0.7) * (1.0 if rng.randf() < 0.5 else -1.0)
	var out := Node3D.new()
	out.name = "Chimney"
	out.position = Vector3(off, 0.0, end)
	var piece := ArtKit.instance("chimney.stone")
	piece.position.y = eaves + rise * (1.0 - absf(off) / half)
	out.add_child(piece)
	out.set_meta(SMOKE_AT, Vector3(0.0, piece.position.y + ArtKit.size("chimney.stone").y, 0.0))
	return out


## An art-walled [param slot]'s [param node] (Level.ART_WALLED, 718: the turf house)
## dressed: its roof_disrepair and state_disrepair named as a slot's
## damaged roof and rubble (roof_damaged, state_damaged: Client3D's damage
## shows them in disrepair, there being no roof_damaged), its walls_ruin
## hidden; in a "parts" its FURNISHINGS at their sockets and a "Chimney" at
## its chimney socket (SMOKE_AT its own middle: 710's smoke); beside them
## its pot tipped over and cold (RUIN_POT, variant 2), hidden. Its pot's
## flame (HEARTH_FLAME, its noise by [param seed]), or null.
static func art_dress(node: Node3D, slot: String, seed: int) -> Node3D:
	for names: Array in [["roof_disrepair", "roof_damaged"], ["state_disrepair", "state_damaged"]]:
		var part := node.get_node_or_null(str(names[0]))
		if part != null:
			part.name = str(names[1])
	var ruin := node.get_node_or_null(WALLS_RUIN) as Node3D
	if ruin != null:
		ruin.visible = false
	var sockets: Dictionary = ArtKit.spec(slot).get("sockets", {}) if ArtKit.has(slot) else {}
	var parts := Node3D.new()
	parts.name = "parts"
	node.add_child(parts)
	var flame: Node3D = null
	for socket: String in FURNISHINGS:
		var prop := str(FURNISHINGS[socket][0])
		if not sockets.get(socket) is Array or not ArtKit.has(prop):
			continue
		var at := Vector3(float(sockets[socket][0]), float(sockets[socket][1]), float(sockets[socket][2]))
		var piece := ArtKit.instance(prop)
		piece.name = socket.capitalize()
		piece.position = at
		piece.rotation.y = float(FURNISHINGS[socket][1])
		parts.add_child(piece)
		if socket == "hearth":
			var socket_at: Variant = Flames.socket_of(prop)
			if socket_at != null:
				flame = Flames.light(piece, socket_at, HEARTH_FLAME, seed)
			var tipped := ArtKit.instance(prop, 2)
			tipped.name = RUIN_POT
			tipped.position = at
			tipped.visible = false
			node.add_child(tipped)
	if sockets.get("chimney") is Array:
		var chimney := Node3D.new()
		chimney.name = "Chimney"
		chimney.position = Vector3(float(sockets["chimney"][0]), float(sockets["chimney"][1]), float(sockets["chimney"][2]))
		chimney.set_meta(SMOKE_AT, Vector3.ZERO)
		parts.add_child(chimney)
	return flame


## [param node]'s wall quarters (QUARTERS, art_dress's slot), each
## [quarter, its way out on the map (Vector2: x, z) as [param node] is
## turned]: what Client3D fades on the camera's side while you are inside.
static func quarters(node: Node3D) -> Array:
	var out: Array = []
	for name: String in QUARTERS:
		var quarter := node.get_node_or_null(name) as Node3D
		if quarter == null:
			continue
		var way: Vector2 = QUARTERS[name]
		var turned := node.basis * Vector3(way.x, 0.0, way.y)
		out.append([quarter, Vector2(turned.x, turned.z).normalized()])
	return out


## A building being built (decision 566): drawn in stages by its build
## job's progress (economy's, 0..1, on its town record). PLOT its staked
## ground, FRAME its sills and corner posts, WALLS to WALLS + 3 its walls a
## quarter storey higher each, RAFTERS its main roof's rafters, COVERING
## its roofs on, STANDING as it is drawn when built.
const PLOT := 0
const FRAME := 1
const WALLS := 2
const RAFTERS := 6
const COVERING := 7
const STANDING := 8
## A planned building drawn as its staked plot (the coordinator's ruling on
## 566, Jeff's to overturn): false draws one standing until its job's
## progress is under way.
const PLANNED_AS_PLOT := true
## The site's plain timber where art-kit has no piece: a stake, a sill's
## section, a scaffold's reach out from the wall and its plank's height,
## the woodpile, a rafter's section.
const STAKE := Vector3(0.06, 0.6, 0.06)
const SILL := 0.2
const SCAFFOLD_OUT := 0.7
const SCAFFOLD_PLANK := 1.6
const WOODPILE := Vector3(1.2, 0.5, 0.6)
const RAFTER := 0.12
## The woodpile and the planks beside it share its cell, this far either
## side of its middle.
const SITE_PROP_SPACING := 0.3


## The stage [param record] (a town's record of the building's use: state,
## level, progress) is drawn at: a first build (planned, or building at
## level 0) by its progress; anything else STANDING.
static func stage(record: Dictionary) -> int:
	var state := str(record.get("state", Towns.STANDING))
	var first := state == Towns.PLANNED or state == Towns.BUILDING and int(record.get("level", 0)) == 0
	if not first:
		return STANDING
	var progress := float(record.get("progress", 0.0))
	if state == Towns.PLANNED and not PLANNED_AS_PLOT and progress <= 0.0:
		return STANDING
	var at := PLOT
	# Where each stage after PLOT begins: economy's, which resends the town
	# record as progress crosses each.
	for cut in Towns.BUILD_STAGES:
		if progress >= cut:
			at += 1
	return at


## A laid plot's stage from its town's [param record] (591 amended, the
## coordinator's ruling: a plot is not a building): staked (PLOT) with no
## record yet or one only planned, else as stage has it; never standing
## for being laid.
static func plot_stage(record: Dictionary) -> int:
	if record.is_empty() or str(record.get("state", "")) == Towns.PLANNED:
		return PLOT
	return stage(record)


## Whether [param record]'s building stands in scaffold: a level being
## raised, or a repair under way (damaged, with a job's progress).
static func scaffolded(record: Dictionary) -> bool:
	var state := str(record.get("state", Towns.STANDING))
	return record.has("progress") and (state == Towns.DAMAGED
			or state == Towns.BUILDING and int(record.get("level", 0)) >= 1)


## How much of its walls' height stands at stage [param at]: none to its
## frame, a quarter more each walls stage, all from its rafters.
static func wall_fraction(at: int) -> float:
	return clampf(float(at - FRAME) / 4.0, 0.0, 1.0)


## [param building]'s site at stage [param at] (its frame, origin as
## compose's): stakes and string round its outline on its plot; sills
## along its walls until its rafters; its main roof's rafters at RAFTERS;
## scaffold along its walls from its half walls until it stands, or all
## round when [param scaffold] (a raise or a repair); its woodpile until it
## stands; a sawhorse by it while the frame is sawn, planks while the walls
## go up; the ladder on the bay nearest its door. Art-kit's pieces where
## it has them, else plain timber.
static func site(building: Dictionary, at: int, scaffold: bool) -> Node3D:
	var out := Node3D.new()
	out.name = "Site"
	var wood := Client3D._wall_material("wood")
	var doors: Array = building.get("doors", [])
	var storey := float(building["eaves"])
	# The bay with the ladder: the one nearest its door.
	var ladder := Vector3i(-1, -1, -1)
	if not doors.is_empty():
		var door_at: Vector2 = _edge_out(building, doors[0])[0]
		var nearest := INF
		for key in Level.building_outline(building):
			var far := (_edge_out(building, key)[0] as Vector2).distance_to(door_at)
			if not doors.has(key) and far < nearest:
				nearest = far
				ladder = key
	for key in Level.building_outline(building):
		var edge := _edge_out(building, key)
		var middle: Vector2 = edge[0]
		var side: Vector2i = edge[1]
		if at == PLOT:
			out.add_child(_site_piece("site.stake", middle, side, [
					[STAKE, Vector3(0.0, STAKE.y * 0.5, -0.5)],
					[Vector3(0.015, 0.015, 1.0), Vector3(0.0, STAKE.y * 0.8, 0.0)]], wood))
		elif at < RAFTERS and not doors.has(key):
			out.add_child(_site_piece("frame.sill", middle, side, [[Vector3(SILL, SILL, 1.0), Vector3(0.0, SILL * 0.5, 0.0)]], wood))
		if not doors.has(key) and (scaffold or at >= WALLS + 1 and at < STANDING):
			var slot := "scaffold.bay_ladder" if key == ladder and ArtKit.has("scaffold.bay_ladder") else "scaffold.bay"
			var bay := _site_piece(slot, middle, side, [
					[Vector3(0.1, storey, 0.1), Vector3(SCAFFOLD_OUT, storey * 0.5, -0.45)],
					[Vector3(0.1, storey, 0.1), Vector3(SCAFFOLD_OUT, storey * 0.5, 0.45)],
					[Vector3(0.35, 0.05, 1.0), Vector3(SCAFFOLD_OUT - 0.15, SCAFFOLD_PLANK, 0.0)]], wood)
			bay.name = "Bay"
			if ArtKit.has(slot):
				bay.scale.y = storey / Client3D.WALL_HEIGHT  # Art-kit's is a storey of 3 m.
			out.add_child(bay)
	if at == RAFTERS:
		out.add_child(_rafters(building, wood))
	if at < STANDING:
		# Its woodpile (art-kit's prop.woodpile, full to its frame, half
		# through its walls, low under its roof) and beside it its planks
		# while its walls go up; its sawbuck on a cell of its own while its
		# posts are sawn, its log across the way its sawyer faces it.
		var cells := Level.site_cells(building)
		var cell: Vector2i = cells["woodpile"]
		var rect: Rect2i = building["rect"]
		var at_cell := Vector3(cell.x - rect.position.x, 0.0, cell.y - rect.position.y)
		var fill := "full" if at <= FRAME else "half" if at < RAFTERS else "low"
		var pile: Node3D
		if ArtKit.has("prop.woodpile"):
			pile = ArtKit.instance("prop.woodpile")
			for state: Node3D in pile.find_children("state_*", "Node3D", true, false):
				state.visible = state.name == "state_" + fill
		else:
			var tall: float = WOODPILE.y * float({"full": 1.0, "half": 0.6, "low": 0.3}[fill])
			pile = _timber(Vector3(WOODPILE.x, tall, WOODPILE.z), Vector3(0.0, tall * 0.5, 0.0), wood)
		pile.name = "Woodpile"
		pile.position = at_cell + Vector3(0.0, 0.0, -SITE_PROP_SPACING)
		out.add_child(pile)
		if at <= FRAME and ArtKit.has("prop.sawhorse"):
			var buck: Vector2i = cells["sawbuck"]
			var facing: Vector2i = cells["saw"] - buck
			var sawhorse := ArtKit.instance("prop.sawhorse")
			sawhorse.name = "Sawhorse"
			sawhorse.position = Vector3(buck.x - rect.position.x, 0.0, buck.y - rect.position.y)
			# Its log along x: across a sawyer to its north or south.
			sawhorse.rotation.y = PI * 0.5 if facing.x != 0 else 0.0
			out.add_child(sawhorse)
		elif at > FRAME and at < RAFTERS and ArtKit.has("prop.planks"):
			var planks := ArtKit.instance("prop.planks")
			planks.name = "Planks"
			planks.position = at_cell + Vector3(0.0, 0.0, SITE_PROP_SPACING)
			out.add_child(planks)
	return out


## An edge piece of the site: art-kit's [param slot] as _edge_piece lays
## it, else [param boxes] ([size, position] each, in the edge's frame:
## along z, its outside +x) of plain [param wood].
static func _site_piece(slot: String, middle: Vector2, out: Vector2i, boxes: Array, wood: Material) -> Node3D:
	var piece := _edge_piece(slot, middle, out)
	if piece != null:
		piece.name = slot.get_slice(".", 1).capitalize()
		return piece
	var holder := Node3D.new()
	holder.name = slot.get_slice(".", 1).capitalize()
	holder.position = Vector3(middle.x, 0.0, middle.y)
	holder.rotation.y = atan2(-float(out.y), float(out.x))
	for box: Array in boxes:
		holder.add_child(_timber(box[0], box[1], wood))
	return holder


## A plain timber box of [param size] at [param at].
## Posts under [param building]'s open edges (its "open", 591: a forge's
## front, a market's every side) in [param parts], each as tall as its
## edges' walls would stand (wall_heights: a lean-to's low eave): one at
## each corner of an open run and every OPEN_POST_EVERY vertices along it,
## none where a wall or a door ends (the walls' own post stands there).
## Art-kit's wall.wood.post stretched, else a timber.
static func _open_posts(building: Dictionary, parts: Node3D) -> void:
	var open: Array = building.get("open", [])
	if open.is_empty():
		return
	var rect: Rect2i = building["rect"]
	var heights := wall_heights(building)
	var walled: Dictionary[Vector2i, bool] = {}
	var tall: Dictionary[Vector2i, float] = {}
	var directions: Dictionary[Vector2i, Dictionary] = {}
	for key: Vector3i in Level.building_outline(building):
		for end in 2:
			var vertex := WallEdge.vertex_at(key, end)
			if not key in open:
				walled[vertex] = true
				continue
			tall[vertex] = minf(tall.get(vertex, INF), float(heights.get(key, building["eaves"])))
			if not directions.has(vertex):
				directions[vertex] = {}
			directions[vertex][key.z] = true
	var wood := Client3D._wall_material("wood")
	for vertex: Vector2i in tall:
		var corner := (directions[vertex] as Dictionary).size() > 1
		if walled.has(vertex) or not corner and posmod(vertex.x + vertex.y, OPEN_POST_EVERY) != 0:
			continue
		var height: float = tall[vertex]
		var at := Vector3(vertex.x - 0.5 - rect.position.x, 0.0, vertex.y - 0.5 - rect.position.y)
		var post: Node3D
		if ArtKit.has("wall.wood.post"):
			post = ArtKit.instance("wall.wood.post")
			post.scale.y = height / Client3D.WALL_HEIGHT
			post.position = at
		else:
			post = _timber(Vector3(OPEN_POST, height, OPEN_POST), at + Vector3(0.0, height * 0.5, 0.0), wood)
		post.name = "OpenPost_%d_%d" % [vertex.x, vertex.y]
		parts.add_child(post)


## A camp's (649) fire ring and tents in [param parts]: art-kit's
## prop.campfire in from its middle toward its front, its prop.tent behind
## (two side by side on a camp six across), each facing the camp's front;
## a piece art-kit has not is left out.
static func _camp(building: Dictionary, parts: Node3D) -> void:
	var rect: Rect2i = building["rect"]
	var facing: Vector2i = building["facing"]
	var front := Vector2(facing)
	var side := Vector2(-facing.y, facing.x)
	var middle := Vector2(rect.size - Vector2i.ONE) * 0.5
	var fire := middle + front * CAMP_FIRE_OUT
	if ArtKit.has("prop.campfire"):
		var ring := ArtKit.instance("prop.campfire")
		ring.name = "Campfire"
		ring.position = Vector3(fire.x, 0.0, fire.y)
		parts.add_child(ring)
	if not ArtKit.has("prop.tent"):
		return
	var tents := 2 if mini(rect.size.x, rect.size.y) >= 6 else 1
	for index in tents:
		var at := middle - front * CAMP_TENT_BACK
		if tents > 1:
			at += side * CAMP_TENT_APART * (index * 2 - 1)
		var tent := ArtKit.instance("prop.tent")
		tent.name = "Tent_%d" % index
		tent.position = Vector3(at.x, 0.0, at.y)
		tent.rotation.y = atan2(front.x, front.y)
		parts.add_child(tent)


static func _timber(size: Vector3, at: Vector3, wood: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = wood
	mesh.position = at
	return mesh


## [param building]'s main block's rafters: a pair a metre along its ridge,
## from its eaves to its ridge (its rise as its roof's); art-kit's
## roof.rafters where it has them (a pair for a 4 m span rising 2 m, its
## origin at the apex, stretched to this one), else plain timber.
static func _rafters(building: Dictionary, wood: Material) -> Node3D:
	var out := Node3D.new()
	out.name = "Rafters"
	var blocks: Array = building["blocks"]
	var main: Rect2i = blocks[_main_of(blocks)]
	var rect: Rect2i = building["rect"]
	var middle := Vector2(main.position - rect.position) + Vector2(main.size - Vector2i.ONE) * 0.5
	var along_x := main.size.x > main.size.y
	var span := float(main.size.y if along_x else main.size.x)
	var length := float(main.size.x if along_x else main.size.y)
	var rise := _main_rise(building)
	out.position = Vector3(middle.x, float(building["eaves"]), middle.y)
	out.rotation.y = PI * 0.5 if along_x else 0.0
	var count := maxi(int(length), 1)
	var slope := sqrt(span * span * 0.25 + rise * rise)
	for k in count:
		var z := -length * 0.5 + (k + 0.5) * length / count
		if ArtKit.has("roof.rafters"):
			var pair := ArtKit.instance("roof.rafters")
			pair.position = Vector3(0.0, rise, z)
			pair.scale = Vector3(span / 4.0, rise / 2.0, 1.0)
			out.add_child(pair)
			continue
		for side: float in [-1.0, 1.0]:
			var rafter := _timber(Vector3(slope, RAFTER, RAFTER), Vector3(side * span * 0.25, rise * 0.5, z), wood)
			rafter.rotation.z = -side * atan2(rise, span * 0.5)
			out.add_child(rafter)
	return out

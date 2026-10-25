class_name ArtKit
extends RefCounted
## The game's art, by slot: every model the 3D view draws is a named slot
## in art/kit/slots.json (its size, origin, moving parts, budget, where it
## is used and where its art came from), and ArtKit.instance(slot) is how
## the view gets one. A slot is drawn from, in order:
##
## - its own art: art/kit/<category>/<slot>/<slot>.glb (variants
##   <slot>.2.glb, <slot>.3.glb ...), made to the slot's conventions, so
##   it is placed as is;
## - else its fill: a third-party piece the manifest names (today the
##   Kenney Castle Kit), moved and scaled to the slot's conventions by the
##   fill's offset and scale;
## - else a grey box: the slot's size (or its "grey" boxes), its moving
##   parts boxes of their own so they still move, in its category's grey,
##   with the slot's name over it when labels are on.
##
## Conventions (docs/art_style.md): metres, +Y up, one cell is 1 m. An edge
## piece (a wall, a door) runs along z over [-0.5, 0.5], centred on the
## edge's line at x = 0, its base at y = 0; a vertex piece (a post) and a
## cell piece (a prop, a tree, a rock) stand centred on their origin, base
## at y = 0, front to +Z. A held piece (an item, a weapon) has its origin
## at its "grip" socket, where the hand holds it, its length along +Y; a
## two-handed one has a "grip_2" socket for the other hand.
##
## An instance is a Node3D named for the slot (its "slot" meta the slot's
## name) holding "Body", everything that does not move, and one child per
## moving part, named as the part, its origin at the part's pivot: turn a
## hinge's node about its axis, slide a slide's along its. How a slot is
## put together is worked out once (_compile: which scenes, where, scaled
## how), so an instance only makes its nodes, from what is kept: the .glb
## scenes as loaded (decision 183: a scene nothing holds is let go and
## loaded again for the next) and the grey boxes' meshes and materials;
## every instance of a slot shares its meshes. (A slot packed once into a
## PackedScene of its own and instantiated cost 2.7 MB and 4.5 ms an
## instance on a 256x256 map's first build.)

const MANIFEST := "res://art/kit/slots.json"
const MORE := "slots_*.json"
const ROOT := "res://art/kit/"
## The one material every slot's art shares (decision 261): flat colours
## from PALETTE's swatches, sampled nearest. A .glb whose material is
## named PALETTE_NAME draws with this one instead of its own copy.
const PALETTE := "res://art/kit/palette.tres"
const PALETTE_NAME := "palette"
## Where a creature's blow lands in its clip when the slot's clip names no
## "contact": this far through it (CreatureView strikes it so; ArtCheck
## checks a named one).
const CLIP_CONTACT := 0.5
## How animation reads (combat's feel tuning, step 2, pc-character's side):
## FEEL's numbers by key ("<script>.<constant>"), each the value of a
## constant in the script that reads it, `feel(key, CONSTANT)` at the moment
## it is used, the constant the value a key FEEL lacks. `set_feel` changes
## one for this run (the tuning panel, a local host): the next clip, step or
## blow takes it. FEEL stays the source; a set Jeff saves comes back into it.
const FEEL := "res://art/kit/feel.json"
static var _feel: Dictionary = {}
static var _feel_read := false
## Counts set_feel's changes, so a reader that keeps what it worked out from
## FEEL (Client3D.paced) knows when to work it out again.
static var feel_serial := 0
## The greys a placeholder is drawn in, by category: told apart, all plainly
## not art.
const GREYS := {
	"walls": Color(0.62, 0.62, 0.6),
	"doors": Color(0.5, 0.47, 0.44),
	"trees": Color(0.52, 0.56, 0.5),
	"plants": Color(0.55, 0.6, 0.52),
	"rocks": Color(0.5, 0.5, 0.52),
	"buildings": Color(0.6, 0.57, 0.53),
	"props": Color(0.58, 0.55, 0.5),
}
const GREY := Color(0.55, 0.55, 0.55)
const LABEL_PIXEL := 0.004

## Every slot drawn as its grey box, own art or fill notwithstanding
## (settings.cfg art_placeholders=1): to see sizes in the real map.
static var show_placeholders := false
## The slot's name over each grey box (settings.cfg art_labels=1).
static var show_labels := false
## A slot's own files are read as they are on disk (a .glb through
## GLTFDocument, a .png as an image), not as Godot imported them: the
## preview (tools/art_preview) sets it, to show a file the moment it is
## saved, with no editor to import it.
static var live := false

static var _manifest: Dictionary = {}
static var _scenes: Dictionary[String, PackedScene] = {}
static var _boxes: Dictionary[Vector3, BoxMesh] = {}
## Each slot's recipes (_compile), and its grey box's while
## show_placeholders.
static var _recipes: Dictionary[String, Array] = {}
static var _grey_recipes: Dictionary[String, Array] = {}
static var _variants: Dictionary[String, int] = {}
static var _greys: Dictionary[Color, StandardMaterial3D] = {}
## Told the slot whose art changed ("" for every slot) each time forget
## runs (a drop, the preview's reload): what keeps something drawn from a
## slot, as ItemIcons' icons, draws it again (on_changed, off_changed).
static var _listeners: Array[Callable] = []


## The manifest as read from MANIFEST, once, with the slots of every
## generated manifest beside it (MORE: slots_<what>.json, written by a tool
## from a catalog, as the items' are) added to its own; a slot named twice
## is an error and the first kept.
static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var main := _read(MANIFEST)
		if main.is_empty():
			return {}
		var slots: Dictionary = main.get("slots", {})
		for file in DirAccess.get_files_at(ROOT):
			if not file.match(MORE):
				continue
			var more: Dictionary = _read(ROOT + file).get("slots", {})
			for slot: String in more:
				if slots.has(slot):
					push_error("ArtKit: %s names slot %s again" % [ROOT + file, slot])
					continue
				slots[slot] = more[slot]
		# A generated slot's fields given or changed by hand (slots.json's
		# "overrides": a bow's string part and sockets, which the item
		# catalog can't say).
		var overrides: Dictionary = main.get("overrides", {})
		for slot: String in overrides:
			if not slots.has(slot):
				push_error("ArtKit: %s overrides slot %s, which no file names" % [MANIFEST, slot])
				continue
			slots[slot] = (slots[slot] as Dictionary).merged(overrides[slot], true)
		main["slots"] = slots
		_manifest = main
	return _manifest


static func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_error("ArtKit: %s is not a JSON object (%s)" % [path, FileAccess.get_open_error()])
		return {}
	return parsed


## FEEL's [param key], or [param default] (the constant it stands for) when
## FEEL has none.
static func feel(key: String, default: float) -> float:
	if not _feel_read:
		_feel_read = true
		_feel = (_read(FEEL).get("feel", {}) as Dictionary).duplicate()
	return float(_feel.get(key, default))


## [param key] set to [param value] for this run; [param value] null puts
## FEEL's back.
static func set_feel(key: String, value: Variant) -> void:
	feel(key, 0.0)
	feel_serial += 1
	if value == null:
		var file: Dictionary = _read(FEEL).get("feel", {})
		if file.has(key):
			_feel[key] = file[key]
		else:
			_feel.erase(key)
	else:
		_feel[key] = float(value)


## The feel on combat's tuning panel (673, F7; registered as Tuning's "feel"
## source where the camera's is, Main): each key FEEL has, as "feel.<key>",
## with its range (FEEL_RANGES). A rig's blend is read when the rig is made,
## so client3d.clip_blend and creature_view.blend take on bodies made after a
## change ("spawn"); the rest at the next clip, step or blow ("now").
const FEEL_RANGES := {"client3d.clip_blend": [0.0, 0.5], "client3d.clip_heavy_contact": [0.2, 0.8],
	"client3d.backpedal_clip_speed": [1.0, 5.0], "client3d.roll_speed": [0.5, 3.0], "client3d.down_tilt_speed": [1.0, 20.0],
	"client3d.shot_speed": [10.0, 80.0], "client3d.gait_rate": [0.5, 2.0], "anim_rig.strike_speed_min": [0.1, 1.0],
	"anim_rig.strike_speed_max": [1.0, 6.0], "art_kit.clip_contact": [0.1, 0.9], "creature_view.speed_min": [0.2, 1.0],
	"creature_view.speed_max": [1.0, 3.0], "creature_view.charge_speed": [1.0, 3.0], "creature_view.blend": [0.0, 0.5],
	"client3d.gait.Walk": [0.3, 2.0], "client3d.gait.Jog_Short": [1.5, 6.0], "client3d.gait.Sprint_Short": [2.5, 9.0],
	"client3d.gait_f.Walk": [0.3, 2.0], "client3d.gait_f.Jog_Short": [1.5, 6.0], "client3d.gait_f.Sprint_Short": [2.5, 9.0]}
const FEEL_ON_SPAWN: Array[String] = ["client3d.clip_blend", "creature_view.blend"]
static func feel_fields() -> Array:
	feel("", 0.0)
	var rows := []
	for key: String in _read(FEEL).get("feel", {}):
		var span: Array = FEEL_RANGES.get(key, [0.0, 2.0 * float(_feel[key])])
		rows.append({"path": "feel." + key, "group": "Animation", "min": span[0], "max": span[1],
			"owner": "pc-character", "takes": "spawn" if key in FEEL_ON_SPAWN else "now"})
	return rows


## Tuning's getter and setter for "feel.<key>" paths: null and false for a key
## FEEL lacks.
static func feel_value(path: String) -> Variant:
	var key := path.trim_prefix("feel.")
	feel(key, 0.0)
	return _feel.get(key) if path.begins_with("feel.") else null


static func set_feel_value(path: String, value: Variant) -> bool:
	if feel_value(path) == null or not (value is float or value is int):
		return false
	set_feel(path.trim_prefix("feel."), value)
	return true


static func slots() -> Dictionary:
	return manifest().get("slots", {})


static func has(slot: String) -> bool:
	return slots().has(slot)


## [param slot]'s entry; an unknown slot is an error and an empty entry.
static func spec(slot: String) -> Dictionary:
	if not has(slot):
		push_error("ArtKit: no slot %s in %s" % [slot, MANIFEST])
		return {}
	return slots()[slot]


## The slot's size in metres (x across, y up, z along).
static func size(slot: String) -> Vector3:
	return _vec(spec(slot).get("size", [1, 1, 1]))


## The folder a slot's own files go in.
static func folder(slot: String) -> String:
	return ROOT + str(spec(slot).get("category", "misc")) + "/" + slot + "/"


## The path of the slot's own model, variant [param variant] (1 is
## <slot>.glb, 2 <slot>.2.glb, ...); a slot whose "model" names a file the
## game draws from elsewhere (a humanoid body in art/models, Client3D's
## MODELS) is that file, one variant, so the checks see the file drawn.
static func own_path(slot: String, variant := 1) -> String:
	var model := str(spec(slot).get("model", ""))
	if model != "":
		return model if variant <= 1 else ""
	return folder(slot) + slot + (".glb" if variant <= 1 else ".%d.glb" % variant)


## The path of a texture slot's own image (variant [param variant]:
## <slot>.png, <slot>.2.png ...).
static func texture_path(slot: String, variant := 1) -> String:
	return folder(slot) + slot + (".png" if variant <= 1 else ".%d.png" % variant)


## A texture slot's own image (variant [param variant], wrapped into range),
## or null while it has none (whoever draws it then uses a stand-in of its
## own: terrain's procedural colour).
static func texture(slot: String, variant := 1) -> Texture2D:
	var count := variant_count(slot)
	var path := texture_path(slot, 1 + posmod(variant - 1, maxi(count, 1)))
	if not _exists(path):
		return null
	if live:
		var image := Image.load_from_file(ProjectSettings.globalize_path(path))
		return ImageTexture.create_from_image(image) if image != null else null
	return load(path) as Texture2D


## How many variants of its own the slot has; 0: none (its fill or grey box).
## A texture slot's are its images (<slot>.png, <slot>.2.png ...).
static func variant_count(slot: String) -> int:
	if not _variants.has(slot):
		var count := 0
		var texture_slot := str(spec(slot).get("type", "mesh")) == "texture"
		while _exists(texture_path(slot, count + 1) if texture_slot else own_path(slot, count + 1)):
			count += 1
		_variants[slot] = count
	return _variants[slot]


## Where the slot's art comes from: "own", "fill" (third-party) or
## "placeholder".
static func filled_by(slot: String) -> String:
	if variant_count(slot) > 0:
		return "own"
	if spec(slot).has("fill"):
		return "fill"
	return "placeholder"


## The art's credits for the game's Credits (decision 406, amended):
## {summary: "Art: <each maker drawn from now>", entries: [{title, by,
## license, url}]}: each source a slot is filled from now ("Castle Kit 2.0,
## Kenney" is "Castle Kit 2.0" by Kenney), then the manifest's "credits"
## (third-party parts in our own art) while a slot they name draws its own
## art, or always with no slots. Our own and generated art need no line.
static func credits() -> Dictionary:
	var all := slots().keys()
	all.sort()
	var entries: Array[Dictionary] = []
	var sources: Dictionary = manifest().get("sources", {})
	var names := sources.keys()
	names.sort()
	for name: String in names:
		if not all.any(func(slot: String) -> bool:
				return filled_by(slot) == "fill" and str(spec(slot)["fill"].get("from", "")) == name):
			continue
		var source: Dictionary = sources[name]
		var full := str(source.get("name", name))
		entries.append({"title": full.get_slice(", ", 0), "by": full.get_slice(", ", 1) if ", " in full else "",
			"license": str(source.get("license", "")), "url": str(source.get("url", ""))})
	for credit: Dictionary in manifest().get("credits", []):
		var named: Array = credit.get("slots", [])
		if named.is_empty() or named.any(func(slot: String) -> bool: return has(slot) and filled_by(slot) == "own"):
			entries.append({"title": str(credit["title"]), "by": str(credit["by"]),
				"license": str(credit.get("license", "")), "url": str(credit.get("url", ""))})
	var makers: Array[String] = []
	for entry: Dictionary in entries:
		if entry["by"] != "" and entry["by"] not in makers:
			makers.append(entry["by"])
	makers.sort()
	return {"summary": "Art: " + ", ".join(makers), "entries": entries}


## A new instance of [param slot] (variant [param variant] of its own art,
## wrapped into range; its fill or grey box has one).
static func instance(slot: String, variant := 1) -> Node3D:
	var table := _grey_recipes if show_placeholders else _recipes
	var recipes: Array = table.get(slot, [])
	if recipes.is_empty():
		recipes = _compile(slot)
		table[slot] = recipes
	return _make(recipes[posmod(variant - 1, recipes.size())])


## Forgets what was made for [param slot] (every slot when empty), so the
## next instance reads its files again.
static func forget(slot := "") -> void:
	if slot == "":
		_scenes.clear()
		_variants.clear()
		_recipes.clear()
		_grey_recipes.clear()
		_manifest = {}
	else:
		for variant in range(1, variant_count(slot) + 2):
			_scenes.erase(own_path(slot, variant))
		_variants.erase(slot)
		_recipes.erase(slot)
		_grey_recipes.erase(slot)
	for listener in _listeners.duplicate():
		if listener.is_valid():
			listener.call(slot)
		else:
			_listeners.erase(listener)  # Its object is gone.


## [param listener] is called with a slot each time its art changes, "" for
## every slot (forget).
static func on_changed(listener: Callable) -> void:
	if listener not in _listeners:
		_listeners.append(listener)


static func off_changed(listener: Callable) -> void:
	_listeners.erase(listener)


## How [param slot] is put together, worked out once: a recipe per variant
## (one for a fill or a grey box). A recipe is [its steps, its lifts, the
## slot]: each step a node to make, [parent step (-1 for the root), name,
## transform, what: a PackedScene to instantiate, [mesh, material] for a
## box, a String for a label, null for a plain Node3D]; each lift a part
## of the body's scene moved out beside it, [its path in the body, its
## name, where it stands]; a grey box's has a fourth, true, and its
## instances the meta "grey".
static func _compile(slot: String) -> Array:
	if show_placeholders:
		return [_grey_recipe(slot)]
	var count := variant_count(slot)
	if count > 0:
		var out: Array = []
		for variant in range(1, count + 1):
			out.append(_own_recipe(slot, variant))
		return out
	if spec(slot).has("fill"):
		return [_fill_recipe(slot)]
	return [_grey_recipe(slot)]


## An instance from [param recipe].
static func _make(recipe: Array) -> Node3D:
	var nodes: Array[Node3D] = []
	for step: Array in recipe[0]:
		var what: Variant = step[3]
		var node: Node3D
		if what is PackedScene:
			node = (what as PackedScene).instantiate()
		elif what is Array:
			var box := MeshInstance3D.new()
			box.mesh = what[0]
			box.material_override = what[1]
			node = box
		elif what is String:
			var label := Label3D.new()
			label.text = what
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.pixel_size = LABEL_PIXEL
			node = label
		else:
			node = Node3D.new()
		node.name = step[1]
		node.transform = step[2]
		if step[0] >= 0:
			nodes[step[0]].add_child(node)
		nodes.append(node)
	var root := nodes[0]
	root.set_meta(&"slot", recipe[2])
	if recipe.size() > 3:
		root.set_meta(&"grey", true)
	for lift: Array in recipe[1]:
		var part := nodes[1].get_node(lift[0]) as Node3D
		for node in _descendants(part):
			node.owner = null  # The body's scene's; the part leaves it.
		part.get_parent().remove_child(part)
		part.name = lift[1]
		root.add_child(part)
		part.transform = lift[2]
	return root


static func _step(steps: Array, parent: int, name: String, place: Transform3D, what: Variant) -> int:
	steps.append([parent, StringName(name), place, what])
	return steps.size() - 1


## The slot's own model as the body: its part nodes (found by name
## anywhere in it) are lifted out beside it, where they stood.
static func _own_recipe(slot: String, variant: int) -> Array:
	var steps: Array = []
	_step(steps, -1, slot.replace(".", "_"), Transform3D.IDENTITY, null)
	var scene := _scene(own_path(slot, variant))
	_step(steps, 0, "Body", Transform3D.IDENTITY, scene)
	var lifts: Array = []
	var nodes := _scene_nodes(scene)
	for part: Dictionary in spec(slot).get("parts", []):
		var found: Array = []
		for node: Array in nodes.slice(1):
			if str(node[0]).get_file() == str(part["name"]):
				found = node
				break
		if found.is_empty():
			push_error("ArtKit: %s has no part %s (%s)" % [own_path(slot, variant), part["name"], spec(slot).get("uses", "")])
			continue
		lifts.append([NodePath(found[0]), StringName(str(part["name"])), found[1]])
	return [steps, lifts, slot]


## The fill's piece as the body, and each part's piece under a node at the
## fill's pivot for it.
static func _fill_recipe(slot: String) -> Array:
	var fill: Dictionary = spec(slot)["fill"]
	var steps: Array = []
	_step(steps, -1, slot.replace(".", "_"), Transform3D.IDENTITY, null)
	_fill_step(steps, 0, "Body", fill, slot)
	var parts: Dictionary = fill.get("parts", {})
	for part: Dictionary in spec(slot).get("parts", []):
		var name := str(part["name"])
		var given: Dictionary = parts.get(name, {})
		var pivot := _vec(given.get("pivot", part.get("pivot", [0, 0, 0])))
		var node := _step(steps, 0, name, Transform3D(Basis.IDENTITY, pivot), null)
		if not given.is_empty():
			_fill_step(steps, node, "Piece", given, slot)
	return [steps, [], slot]


## A step for one third-party piece: [param fill]'s "from" source's
## "piece", moved by "offset" and scaled by "scale" (a number or [x, y,
## z]); "fit": "height" scales it evenly to stand as tall as the slot.
static func _fill_step(steps: Array, parent: int, name: String, fill: Dictionary, slot: String) -> void:
	var source: Dictionary = manifest().get("sources", {}).get(str(fill.get("from", "")), {})
	var scene := _scene(str(source.get("path", "")) + str(fill["piece"]) + str(source.get("extension", ".glb")))
	var scale_by: Variant = fill.get("scale", 1.0)
	var factor := _vec(scale_by) if scale_by is Array else Vector3.ONE * float(scale_by)
	if str(fill.get("fit", "")) == "height":
		factor *= size(slot).y / maxf(_scene_bounds(scene).end.y, 0.001)
	_step(steps, parent, name, Transform3D(Basis.from_scale(factor), _vec(fill.get("offset", [0, 0, 0]))), scene)


## The grey box: the slot's "grey" boxes for its body (each {"at": centre,
## "size"}), else one box its size standing on its origin; each part's own
## "grey" boxes, or a box its "size", from its pivot; a held piece's
## sockets but its grip as empties; the slot's name over it when
## show_labels.
static func _grey_recipe(slot: String) -> Array:
	var entry := spec(slot)
	var material := _grey(GREYS.get(str(entry.get("category", "")), GREY))
	var steps: Array = []
	_step(steps, -1, slot.replace(".", "_"), Transform3D.IDENTITY, null)
	var body := _step(steps, 0, "Body", Transform3D.IDENTITY, null)
	# "grey": "none": a body of no boxes (a building, all of whose grey is
	# its named parts: its roof, floor and trim).
	var given: Variant = entry.get("grey", [])
	var boxes: Array = given if given is Array else []
	if boxes.is_empty() and not given is String:
		var whole := size(slot)
		# Its origin at the bottom ("base"), the middle ("centre": a shield,
		# held at the middle of its back) or the top.
		var origin := str(entry.get("origin", "base"))
		var base := 0.0 if origin == "base" else -whole.y * 0.5 if origin == "centre" else -whole.y
		base += float(entry.get("base", 0.0))
		# A slot whose box's middle is off its origin ("middle": a porch out
		# from its wall) has its box there.
		var middle := _vec(entry.get("middle", [0, 0, 0]))
		boxes = [{"at": [middle.x, base + whole.y * 0.5, middle.z], "size": [whole.x, whole.y, whole.z]}]
	for i in boxes.size():
		_grey_step(steps, body, "Box%d" % i, boxes[i], material)
	for part: Dictionary in entry.get("parts", []):
		var node := _step(steps, 0, str(part["name"]), Transform3D(Basis.IDENTITY, _vec(part.get("pivot", [0, 0, 0]))), null)
		var own: Array = part.get("grey", [])
		if own.is_empty() and part.has("size"):
			var extent := _vec(part["size"])
			own = [{"at": [0, extent.y * 0.5, extent.z * 0.5], "size": part["size"]}]
		for i in own.size():
			_grey_step(steps, node, "Box%d" % i, own[i], material)
	# A held piece's sockets (grip_2: the other hand) as empties, as its art has them.
	var sockets: Variant = entry.get("sockets", {})
	if str(entry.get("kind", "")) == "held" and sockets is Dictionary:
		for socket: String in sockets:
			if socket != "grip":
				_step(steps, 0, socket, Transform3D(Basis.IDENTITY, _vec(sockets[socket])), null)
	if show_labels:
		_step(steps, 0, "Label", Transform3D(Basis.IDENTITY, Vector3(0.0, size(slot).y + 0.2, 0.0)), slot)
	return [steps, [], slot, true]  # A grey box: ArtCheck asks no rig of it.


static func _grey_step(steps: Array, parent: int, name: String, box: Dictionary, material: Material) -> void:
	var extent := _vec(box["size"])
	if not _boxes.has(extent):
		var mesh := BoxMesh.new()
		mesh.size = extent
		_boxes[extent] = mesh
	_step(steps, parent, name, Transform3D(Basis.IDENTITY, _vec(box["at"])), [_boxes[extent], material])


static func _grey(colour: Color) -> StandardMaterial3D:
	if not _greys.has(colour):
		var material := StandardMaterial3D.new()
		material.albedo_color = colour
		material.roughness = 0.9
		_greys[colour] = material
	return _greys[colour]


## The scene at [param path], loaded once and kept.
static func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var own := path.begins_with(ROOT)
		_scenes[path] = _read_glb(path) if live and own else load(path) as PackedScene
		if own and _scenes[path] != null:
			_share_palette(_scenes[path])
	return _scenes[path]


## [param scene]'s surfaces drawn in a material named PALETTE_NAME take the
## shared PALETTE instead (set on the meshes, which every instance shares).
static func _share_palette(scene: PackedScene) -> void:
	var shared := load(PALETTE) as Material
	for node: Array in _scene_nodes(scene):
		var mesh: Mesh = node[2]
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var own := mesh.surface_get_material(surface)
			if own != null and own != shared and own.resource_name == PALETTE_NAME:
				mesh.surface_set_material(surface, shared)


## [param scene]'s nodes read from its state, none made (decision 296: in
## Godot 4.7.2 freeing a VisualInstance3D while thousands of new ones are
## still undrawn stalls for seconds, so nothing here makes a sample to free):
## each [its path from the root as the root's get_path_to gives it, its
## transform in the root's space, its mesh or null], parents first; an
## instanced scene's nodes under the node that instances it.
static func _scene_nodes(scene: PackedScene, base := Transform3D.IDENTITY, prefix := "") -> Array:
	var state := scene.get_state()
	var out: Array = []
	var placed: Dictionary[String, Transform3D] = {}
	for i in state.get_node_count():
		var path := str(state.get_node_path(i)).trim_prefix(".").trim_prefix("/")
		var parent := str(state.get_node_path(i, true)).trim_prefix(".").trim_prefix("/")
		var local := Transform3D.IDENTITY
		var mesh: Mesh = null
		for property in state.get_node_property_count(i):
			match state.get_node_property_name(i, property):
				&"transform":
					local = state.get_node_property_value(i, property)
				&"mesh":
					mesh = state.get_node_property_value(i, property) as Mesh
		var full := path if prefix == "" else (prefix if path == "" else prefix + "/" + path)
		# The root stands where it is put: its own transform is not its nodes'.
		var place: Transform3D = base if i == 0 else placed.get(parent, base) * local
		placed[path] = place
		var inner := state.get_node_instance(i)
		if inner != null:
			var nested := _scene_nodes(inner, place, full)
			if mesh == null and not nested.is_empty():
				mesh = nested[0][2]
			out.append([full, place, mesh])
			out.append_array(nested.slice(1))
			continue
		out.append([full, place, mesh])
	return out


## [param scene]'s meshes' bounds in its root's space, as bounds_of an
## instance's, none made.
static func _scene_bounds(scene: PackedScene) -> AABB:
	var out := AABB()
	var first := true
	for node: Array in _scene_nodes(scene):
		var mesh: Mesh = node[2]
		if mesh == null:
			continue
		var box: AABB = (node[1] as Transform3D) * mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## A slot's file there to read: imported, or (live) on disk.
static func _exists(path: String) -> bool:
	return FileAccess.file_exists(path) if live else ResourceLoader.exists(path)


## A .glb read from disk as the importer would make it, packed as a scene.
static func _read_glb(path: String) -> PackedScene:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error := document.append_from_file(ProjectSettings.globalize_path(path), state)
	var scene := PackedScene.new()
	if error != OK:
		push_error("ArtKit: could not read %s (%s)" % [path, error_string(error)])
		var empty := Node3D.new()
		scene.pack(empty)
		empty.free()
		return scene
	var root := document.generate_scene(state) as Node3D
	for node in _descendants(root):
		if node != root:
			node.owner = root
	scene.pack(root)
	root.free()
	return scene


## How tall [param node] stands as modelled: the top of its meshes' bounds.
static func top_of(node: Node3D) -> float:
	return bounds_of(node).end.y


## [param node]'s meshes' bounds, in its own space.
static func bounds_of(node: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for child in _descendants(node):
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		var box := _place_in(mesh, node) * mesh.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## [param node]'s transform in [param ancestor]'s space.
static func _place_in(node: Node3D, ancestor: Node) -> Transform3D:
	var place := Transform3D.IDENTITY
	var at: Node = node
	while at != ancestor and at is Node3D:
		place = (at as Node3D).transform * place
		at = at.get_parent()
	return place


static func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


static func _vec(value: Variant) -> Vector3:
	var list: Array = value
	return Vector3(float(list[0]), float(list[1]), float(list[2]))

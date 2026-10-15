extends Node
## The art slots (ArtKit, art/kit/slots.json): the manifest is whole, every
## slot is drawn at its size from its own art, its fill or its grey box,
## with its moving parts where the manifest says, and every filled slot
## says where its art came from. Run it with tests/run.ps1 or tests/run.sh.
## Prints PASS/FAIL per assertion and quits with exit code 1 if any
## assertion failed, 0 otherwise.

const TYPES := ["mesh", "texture", "profile"]
const KINDS := ["edge", "vertex", "cell", "floor", "held", "creature"]
## How far a drawn slot's bounds may be from its size, a share of it.
const TOLERANCE := 0.05

var _failures := 0


func _ready() -> void:
	_test_manifest()
	_test_sources()
	_test_fills_fit()
	_test_grey_boxes()
	_test_parts()
	_test_kept()
	_test_own_art_says_where_from()
	_test_profile()
	_test_check_passes_grey_boxes()
	_test_check_names_mistakes()
	_test_own_art_checks()
	_test_status_current()
	_test_live_read()
	_test_live_is_preview_only()
	_test_palette_shared()
	_test_scene_read()
	_test_changed_told()
	_test_creature_rig()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_manifest() -> void:
	print("\n== the manifest: every slot has a category, a type, a use; a mesh slot a kind and a size ==")
	var slots := ArtKit.slots()
	_check(not slots.is_empty(), "slots.json has slots (%d)" % slots.size())
	for slot: String in slots:
		var entry: Dictionary = slots[slot]
		var problems: Array[String] = []
		if slot.get_slice(".", 0) == "" or not "." in slot:
			problems.append("a name is <group>.<name>")
		if str(entry.get("category", "")) == "":
			problems.append("no category")
		if str(entry.get("type", "")) not in TYPES:
			problems.append("type %s, not one of %s" % [entry.get("type"), TYPES])
		if str(entry.get("uses", "")) == "":
			problems.append("no uses")
		if entry.get("type") in ["mesh", "profile"]:
			if str(entry.get("kind", "")) not in KINDS:
				problems.append("kind %s, not one of %s" % [entry.get("kind"), KINDS])
			if not entry.get("size") is Array or (entry["size"] as Array).size() != 3:
				problems.append("no size [x, y, z]")
		if entry.get("type") == "mesh" and not entry.has("budget"):
			problems.append("no budget")
		if entry.get("type") == "texture" and float(entry.get("tile_m", 0.0)) <= 0.0:
			problems.append("no tile_m")
		if entry.has("scatter") and bool((entry["scatter"] as Dictionary).get("blocks", false)):
			problems.append("scatter is drawn only: blocks is false")
		_check(problems.is_empty(), "%s %s" % [slot, problems if not problems.is_empty() else "whole"])


func _test_sources() -> void:
	print("\n== every fill names a source the manifest knows, with its licence, and a piece it has ==")
	var sources: Dictionary = ArtKit.manifest().get("sources", {})
	for name: String in sources:
		var source: Dictionary = sources[name]
		_check(str(source.get("license", "")) != "" and FileAccess.file_exists("res://" + str(source.get("license_file", ""))),
				"source %s: licence %s, its text at %s" % [name, source.get("license"), source.get("license_file")])
	for slot: String in ArtKit.slots():
		var fill: Dictionary = ArtKit.spec(slot).get("fill", {})
		var pieces: Array[Dictionary] = []
		if not fill.is_empty():
			pieces.append(fill)
		for part: Dictionary in (fill.get("parts", {}) as Dictionary).values():
			pieces.append(part)
		for piece in pieces:
			var source: Dictionary = sources.get(str(piece.get("from", "")), {})
			var path := str(source.get("path", "")) + str(piece.get("piece", "")) + str(source.get("extension", ".glb"))
			_check(not source.is_empty() and ResourceLoader.exists(path), "%s: %s from %s (%s)" % [slot, piece.get("piece"), piece.get("from"), path])


func _test_fills_fit() -> void:
	print("\n== a fill is drawn at its slot's size, standing on its origin as the slot's kind says ==")
	for slot: String in ArtKit.slots():
		if ArtKit.spec(slot).get("type") != "mesh" or ArtKit.filled_by(slot) != "fill":
			continue
		var node := ArtKit.instance(slot)
		_check_fits(slot, _body_bounds(node), "its fill")
		node.free()
	# As the 3D view drew the Kenney pieces before slots (decision 220): a
	# wall straddles its edge's line, 3 m tall, the leaf hinged at the
	# doorway's opening.
	var wall := ArtKit.instance("wall.castle.straight")
	var box := ArtKit.bounds_of(wall)
	_check(box.position.is_equal_approx(Vector3(-0.25, 0.0, -0.5)) and box.size.is_equal_approx(Vector3(0.5, 3.0, 1.0)),
			"wall.straight's fill straddles the edge, 3 m tall (%s)" % box)
	wall.free()


func _test_grey_boxes() -> void:
	print("\n== every mesh slot's grey box is its size, labelled when labels are on ==")
	ArtKit.show_placeholders = true
	ArtKit.show_labels = true
	ArtKit.forget()
	for slot: String in ArtKit.slots():
		if ArtKit.spec(slot).get("type") != "mesh":
			continue
		var node := ArtKit.instance(slot)
		_check_fits(slot, ArtKit.bounds_of(node), "its grey box")
		var label := node.get_node_or_null("Label") as Label3D
		_check(label != null and label.text == slot and str(node.get_meta("slot")) == slot, "%s: labelled %s" % [slot, label.text if label != null else "-"])
		node.free()
	ArtKit.show_placeholders = false
	ArtKit.show_labels = false
	ArtKit.forget()
	var node := ArtKit.instance("wall.castle.rubble")
	_check(ArtKit.filled_by("wall.castle.rubble") == "placeholder" and node.get_node_or_null("Label") == null,
			"a slot with no art and no fill is its grey box in the game too, without a label unless asked")
	node.free()


func _test_parts() -> void:
	print("\n== a moving part is a node of its own at its pivot, beside the body, drawn or grey ==")
	for placeholders in [false, true]:
		ArtKit.show_placeholders = placeholders
		ArtKit.forget()
		for slot: String in ArtKit.slots():
			for part: Dictionary in ArtKit.spec(slot).get("parts", []):
				var node := ArtKit.instance(slot)
				var moving := node.get_node_or_null(NodePath(str(part["name"]))) as Node3D
				var pivot := ArtKit._vec(part["pivot"])
				_check(moving != null and moving.position.distance_to(pivot) < 0.01 and not ArtKit.bounds_of(moving).size.is_zero_approx(),
						"%s (%s): %s at %s, with something to see" % [slot, "grey" if placeholders else ArtKit.filled_by(slot), part["name"], moving.position if moving != null else "-"])
				if moving != null and part.get("motion") == "hinge":
					moving.rotation.y = PI * 0.5
					var swung := _body_bounds(node).merge(ArtKit.bounds_of(moving))
					_check(moving.position.distance_to(pivot) < 0.01, "%s: turning %s leaves it on its hinge (%s)" % [slot, part["name"], swung])
				node.free()
	ArtKit.show_placeholders = false
	ArtKit.forget()


func _test_kept() -> void:
	print("\n== a slot's scene is made once: its instances share their meshes ==")
	var one := ArtKit.instance("wall.castle.straight")
	var two := ArtKit.instance("wall.castle.straight")
	var meshes: Array[Mesh] = []
	for node: Node3D in [one, two]:
		for child in node.find_children("*", "MeshInstance3D", true, false):
			meshes.append((child as MeshInstance3D).mesh)
	_check(meshes.size() == 2 and meshes[0] == meshes[1], "two walls, one mesh")
	one.free()
	two.free()


func _test_own_art_says_where_from() -> void:
	print("\n== a slot with its own art says where it came from ==")
	var own := 0
	for slot: String in ArtKit.slots():
		if ArtKit.filled_by(slot) != "own":
			continue
		own += 1
		var source: Dictionary = ArtKit.spec(slot).get("source", {})
		_check(str(source.get("by", "")) != "" and str(source.get("license", "")) != "", "%s: by %s, %s" % [slot, source.get("by"), source.get("license")])
	print("  (%d slots with their own art)" % own)


func _test_profile() -> void:
	print("\n== each wall set's profile: a closed section within its thickness, its cap line (if any) inside it; its material, floor and variation ==")
	var sets: Array[String] = []
	for slot: String in ArtKit.slots():
		var entry := ArtKit.spec(slot)
		if str(entry.get("type", "")) != "profile":
			continue
		var set_name := slot.trim_prefix("wall.").trim_suffix(".profile")
		sets.append(set_name)
		var points: Array = entry.get("points", [])
		var half := ArtKit.size(slot).x * 0.5
		var top := 0.0
		var inside := points.size() >= 3
		for point: Array in points:
			inside = inside and absf(float(point[0])) <= half + 0.001 and float(point[1]) >= 0.0
			top = maxf(top, float(point[1]))
		var cap := float(entry.get("cap_y", top * 0.5))  # The cave's has none.
		var variation: Dictionary = entry.get("variation", {})
		var tunable := true
		for key: String in ["sway", "broken", "gap", "lean", "jitter", "sag"]:
			tunable = tunable and (variation.get(key) is float or variation.get(key) is int)
		_check(inside and cap > 0.0 and cap < top and str(entry.get("material", "")) == "material.wall." + set_name
				and ArtKit.has("material.wall." + set_name) and ArtKit.has("floor." + set_name) and tunable,
				"%s: %d points in x [-%.2f, %.2f], cap %s, top %.2f, %s and floor.%s, variation %s" % [
				slot, points.size(), half, half, entry.get("cap_y", "none"), top, entry.get("material"), set_name, variation])
	_check(sets.size() >= 4 and "castle" in sets, "the wall sets: %s" % [sets])
	for slot: String in ArtKit.slots():
		var entry := ArtKit.spec(slot)
		if entry.has("wall_set") or entry.has("floor_set"):
			_check(str(entry.get("wall_set", "")) in sets and str(entry.get("floor_set", "")) in sets,
					"%s's wall_set %s and floor_set %s are sets" % [slot, entry.get("wall_set"), entry.get("floor_set")])


func _test_check_passes_grey_boxes() -> void:
	print("
== ArtCheck: every mesh slot's grey box is art that fits it ==")
	ArtKit.show_placeholders = true
	ArtKit.forget()
	for slot: String in ArtKit.slots():
		if ArtKit.spec(slot).get("type") != "mesh":
			continue
		var node := ArtKit.instance(slot)
		var problems := ArtCheck.check_node(slot, node)
		_check(problems.is_empty(), "%s %s" % [slot, problems if not problems.is_empty() else "fits"])
		node.free()
	ArtKit.show_placeholders = false
	ArtKit.forget()


func _test_check_names_mistakes() -> void:
	print("
== ArtCheck: each mistake is named, with what to change ==")
	ArtKit.show_placeholders = true
	ArtKit.forget()
	var cases := {
		"modelled in centimetres": func(door: Node3D) -> void: (door.get_node("Body") as Node3D).scale = Vector3.ONE * 100.0; door.get_node("leaf").position *= 100.0,
		"too big,": func(door: Node3D) -> void: (door.get_node("Body") as Node3D).scale.x = 2.0,
		"no object named \"leaf\"": func(door: Node3D) -> void: door.get_node("leaf").free(),
		"\"leaf\" turns about": func(door: Node3D) -> void: door.get_node("leaf").position.z = 0.2,
		"middle of its base": func(door: Node3D) -> void: (door.get_node("Body") as Node3D).position.x = 0.4; door.get_node("leaf").position.x = 0.4,
		"its base is at y": func(door: Node3D) -> void: (door.get_node("Body") as Node3D).position.y = 0.5; door.get_node("leaf").position.y = 0.5,
		"materials, at most": func(door: Node3D) -> void:
			for mesh in door.find_children("*", "MeshInstance3D", true, false):
				(mesh as MeshInstance3D).material_override = StandardMaterial3D.new(),
	}
	for expected: String in cases:
		var door := ArtKit.instance("door.single")
		(cases[expected] as Callable).call(door)
		var problems := ArtCheck.check_node("door.single", door)
		_check(problems.any(func(line: String) -> bool: return line.begins_with("error: ") and expected in line),
				"door.single, %s: %s" % [expected, problems])
		door.free()
	var entry := ArtKit.spec("door.single")
	var budget: int = entry["budget"]
	entry["budget"] = 10
	var door := ArtKit.instance("door.single")
	var over := ArtCheck.check_node("door.single", door)
	_check(over.any(func(line: String) -> bool: return "triangles, the slot's budget is 10" in line), "over budget: %s" % [over])
	door.free()
	entry["budget"] = budget
	var rock := ArtKit.instance("rock.small")
	var extra := MeshInstance3D.new()
	extra.mesh = BoxMesh.new()
	extra.scale = Vector3.ONE * 0.1
	rock.get_node("Body").add_child(extra)
	var scattered := ArtCheck.check_node("rock.small", rock)
	_check(scattered.any(func(line: String) -> bool: return "one mesh with one material" in line), "a scatter piece of two meshes: %s" % [scattered])
	rock.free()
	ArtKit.show_placeholders = false
	ArtKit.forget()


func _test_own_art_checks() -> void:
	print("
== every slot's own art passes ArtCheck; every file in art/kit is a slot's; every .blend has its .glb ==")
	for slot: String in ArtKit.slots():
		if ArtKit.variant_count(slot) == 0:
			continue
		var errors := ArtCheck.check(slot).filter(func(line: String) -> bool: return line.begins_with("error"))
		_check(errors.is_empty(), "%s %s" % [slot, errors if not errors.is_empty() else "fits its slot"])
	var folders := ArtCheck.check_folders()
	_check(folders.is_empty(), "art/kit's folders %s" % [folders if not folders.is_empty() else "are all slots', their files named for them"])
	var orphans: Array[String] = []
	for slot: String in ArtKit.slots():
		var folder := ArtKit.folder(slot)
		if not DirAccess.dir_exists_absolute(folder):
			continue
		for file in DirAccess.get_files_at(folder):
			if file.ends_with(".blend") and not FileAccess.file_exists(folder + file.get_basename() + ".glb"):
				orphans.append(folder + file)
	_check(orphans.is_empty(), "every .blend has its .glb beside it %s" % [orphans if not orphans.is_empty() else ""])


func _test_status_current() -> void:
	print("
== docs/art_status.md and THIRD_PARTY.md say what each slot is drawn from now ==")
	var status := FileAccess.get_file_as_string("res://docs/art_status.md")
	_check(status == ArtCheck.status_markdown(), "docs/art_status.md is current (run tools/art_status.gd if not)")
	_check(FileAccess.get_file_as_string("res://art/kit/status.json") == ArtCheck.status_json(), "art/kit/status.json is current (run tools/art_status.gd if not)")
	var priority := ArtCheck.check_priority()
	_check(priority.is_empty(), "art/kit/priority.json names each slot once at most %s" % [priority if not priority.is_empty() else ""])
	var order := ArtCheck.priority_order()
	_check(order.size() == ArtKit.slots().size() and order[0].slot == "ground.grass" and order[-1].group in ["rest", "profiles"],
		"every slot is in the priority order once, grass first")
	var third := FileAccess.get_file_as_string("res://THIRD_PARTY.md")
	_check(ArtCheck.third_party_block() in third, "THIRD_PARTY.md's art slot block is current (run tools/art_status.gd if not)")
	for name: String in ArtKit.manifest().get("sources", {}):
		var source: Dictionary = ArtKit.manifest()["sources"][name]
		_check(str(source.get("license_file", "")) in third, "THIRD_PARTY.md names %s's licence text" % name)


func _test_live_read() -> void:
	print("
== live (the preview): a .glb read from disk as saved keeps its parts and fits as imported ==")
	ArtKit.show_placeholders = true
	ArtKit.forget()
	var door := ArtKit.instance("door.single")
	ArtKit.show_placeholders = false
	ArtKit.forget()
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(door, state)
	var folder := OS.get_temp_dir().path_join("psykinetic-art-kit-%s" % ProjectSettings.globalize_path("res://").md5_text().left(8))
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join("door.single.glb")
	var error := document.write_to_filesystem(state, path)
	door.free()
	_check(error == OK, "a grey door written as a .glb (%s)" % error_string(error))
	var read := ArtKit._read_glb(path).instantiate() as Node3D
	var problems := ArtCheck.check_node("door.single", read).filter(func(line: String) -> bool: return line.begins_with("error"))
	_check(read.find_child("leaf", true, false) != null and problems.is_empty(), "read back from disk, its leaf is there and it fits its slot %s" % [problems])
	read.free()
	DirAccess.remove_absolute(path)


func _test_palette_shared() -> void:
	print("
== one material: art coloured from the palette draws with the shared one; another is named ==")
	var shared := load(ArtKit.PALETTE) as StandardMaterial3D
	_check(shared != null and shared.albedo_texture != null and shared.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST,
			"%s: the atlas, sampled nearest" % ArtKit.PALETTE)
	var own := StandardMaterial3D.new()
	own.resource_name = ArtKit.PALETTE_NAME
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.surface_set_material(0, own)
	root.add_child(mesh)
	mesh.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	root.free()
	ArtKit._share_palette(scene)
	var drawn := scene.instantiate()
	_check((drawn.get_child(0) as MeshInstance3D).mesh.surface_get_material(0) == shared, "a .glb's own \"palette\" material is swapped for the shared one")
	drawn.free()
	ArtKit.show_placeholders = true
	ArtKit.forget()
	var door := ArtKit.instance("door.single")
	var other := StandardMaterial3D.new()
	other.resource_name = "Material.001"
	for box in door.find_children("*", "MeshInstance3D", true, false):
		(box as MeshInstance3D).material_override = other
	var problems := ArtCheck.check_node("door.single", door)
	_check(problems.any(func(line: String) -> bool: return line.begins_with("warning") and "Material.001" in line and "palette" in line),
			"a material of its own is named, with what to use instead: %s" % [problems])
	door.free()
	ArtKit.show_placeholders = false
	ArtKit.forget()


func _test_scene_read() -> void:
	print("
== a scene read without making it (decision 296): its bounds and parts as an instance's ==")
	var sources: Dictionary = ArtKit.manifest().get("sources", {})
	var pieces := 0
	var same := true
	for slot: String in ArtKit.slots():
		var fill: Dictionary = ArtKit.spec(slot).get("fill", {})
		if fill.is_empty():
			continue
		var source: Dictionary = sources.get(str(fill["from"]), {})
		var scene := ArtKit._scene(str(source.get("path", "")) + str(fill["piece"]) + str(source.get("extension", ".glb")))
		var made := scene.instantiate() as Node3D
		var read := ArtKit._scene_bounds(scene)
		var drawn := ArtKit.bounds_of(made)
		made.free()
		pieces += 1
		if not (read.position.is_equal_approx(drawn.position) and read.size.is_equal_approx(drawn.size)):
			same = false
			print("    %s: read %s, drawn %s" % [slot, read, drawn])
	_check(pieces > 0 and same, "%d fills' pieces: the same bounds read as made" % pieces)
	# A packed door with its leaf deeper in it, moved and turned, as a .glb's.
	ArtKit.show_placeholders = true
	ArtKit.forget()
	var door := ArtKit.instance("door.single")
	ArtKit.show_placeholders = false
	ArtKit.forget()
	var frame := Node3D.new()
	frame.name = "Frame"
	frame.position = Vector3(0.1, 0.2, 0.0)
	frame.rotation.y = 0.3
	var leaf := door.get_node("leaf") as Node3D
	door.remove_child(leaf)
	door.add_child(frame)
	frame.add_child(leaf)
	for node in ArtKit._descendants(door):
		if node != door:
			node.owner = door
	var place := ArtKit._place_in(leaf, door)
	var made_bounds := ArtKit.bounds_of(door)
	var scene := PackedScene.new()
	scene.pack(door)
	door.free()
	var found: Array = []
	for node: Array in ArtKit._scene_nodes(scene):
		if str(node[0]) == "Frame/leaf":
			found = node
	var read_bounds := ArtKit._scene_bounds(scene)
	_check(not found.is_empty() and (found[1] as Transform3D).is_equal_approx(place)
			and read_bounds.position.is_equal_approx(made_bounds.position) and read_bounds.size.is_equal_approx(made_bounds.size),
			"its leaf found at Frame/leaf where it stands (%s), and its bounds as made" % [found[1] if not found.is_empty() else "none"])


func _test_creature_rig() -> void:
	print("
== a creature (decision 319): a rig, and its clips by any of their names; a required one missing is an error ==")
	ArtKit.show_placeholders = true
	ArtKit.forget()
	var grey := ArtKit.instance("creature.wolf")
	ArtKit.show_placeholders = false
	ArtKit.forget()
	_check(ArtCheck.check_node("creature.wolf", grey).is_empty(), "its grey box fits, no rig asked of it")
	grey.remove_meta(&"grey")
	var bare := ArtCheck.check_node("creature.wolf", grey)
	_check(bare.any(func(line: String) -> bool: return line.begins_with("error: no armature")), "unrigged art: no armature named")
	grey.add_child(Skeleton3D.new())
	var player := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for clip in ["AnimalArmature|Idle", "Walk", "Gallop", "Attack", "Death", "Idle_HitReact_Left", "Eating"]:
		library.add_animation(clip, Animation.new())
	player.add_animation_library("", library)
	grey.add_child(player)
	var rigged := ArtCheck.check_node("creature.wolf", grey)
	var errors := rigged.filter(func(line: String) -> bool: return line.begins_with("error"))
	_check(errors.is_empty() and rigged.any(func(line: String) -> bool: return "\"howl\"" in line and "head-up tween" in line)
			and rigged.any(func(line: String) -> bool: return "\"trot\"" in line and "walk, faster" in line),
			"the pack's wolf: its run is Gallop, its hit Idle_HitReact_Left; howl and trot named with what stands in %s" % [errors])
	library.remove_animation("Attack")
	var biteless := ArtCheck.check_node("creature.wolf", grey)
	_check(biteless.any(func(line: String) -> bool: return line.begins_with("error: no \"attack\" clip")), "no attack: an error, it reads wrong without one")
	grey.free()


func _test_changed_told() -> void:
	print("
== a slot's art changing is told: what drew from it (an item's icon) is drawn again ==")
	var heard: Array[String] = []
	var listener := func(slot: String) -> void: heard.append(slot)
	ArtKit.on_changed(listener)
	ArtKit.forget("prop.crate")
	ArtKit.forget()
	ArtKit.off_changed(listener)
	ArtKit.forget("prop.chest")
	_check(heard == ["prop.crate", ""], "told prop.crate, then every slot (\"\"), and nothing once off (%s)" % [heard])
	# An item's icon, kept, goes when its slot's art changes; another's stays.
	var icons := ItemIcons.new()
	var ids: Array = Items.ids().filter(func(id: String) -> bool: return ItemIcons._slot(id) != "")
	if ids.size() < 2:
		icons.free()
		return
	var slot := ItemIcons._slot(ids[0])
	var other: String = ids.filter(func(id: String) -> bool: return ItemIcons._slot(id) != slot).front()
	icons._cache[ItemIcons._key(ids[0])] = ImageTexture.new()
	icons._cache[ItemIcons._key(other)] = ImageTexture.new()
	icons._art_changed(slot)
	_check(not icons._cache.has(ItemIcons._key(ids[0])) and icons._cache.has(ItemIcons._key(other)),
			"%s's art changed: %s's icon is drawn again, %s's kept" % [slot, ids[0], other])
	icons.free()


## Only the preview reads art live: the game, its tools and the export
## always draw imported resources (decision 246).
func _test_live_is_preview_only() -> void:
	print("
== ArtKit.live is set by tools/art_preview alone ==")
	_check(not ArtKit.live, "off unless set")
	var setters: Array[String] = []
	var pattern := RegEx.create_from_string("ArtKit[.]live[ \t]*=[^=]")
	for path in _scripts("res://"):
		if path in ["res://tools/art_preview.gd", "res://tests/art_kit_test.gd"]:
			continue
		if pattern.search(FileAccess.get_file_as_string(path)) != null:
			setters.append(path)
	_check(setters.is_empty(), "no other script sets it %s" % [setters])


## Every .gd under [param folder], outside .godot and the Kenney packs.
func _scripts(folder: String) -> Array[String]:
	var out: Array[String] = []
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			out.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		if not sub.begins_with(".") and sub != "art":
			out.append_array(_scripts(folder.path_join(sub)))
	return out


## [param node]'s body's bounds, in the slot's space.
func _body_bounds(node: Node3D) -> AABB:
	var body := node.get_node("Body") as Node3D
	return body.transform * ArtKit.bounds_of(body)


func _check_fits(slot: String, box: AABB, what: String) -> void:
	var size := ArtKit.size(slot)
	var off := (box.size - size).abs() / size
	var centre := box.get_center()
	var floor := str(ArtKit.spec(slot).get("kind", "")) == "floor"
	var stands := absf(box.end.y if floor else box.position.y) < 0.01 and absf(centre.x) < size.x * TOLERANCE + 0.01 and absf(centre.z) < size.z * TOLERANCE + 0.01
	_check(off.x <= TOLERANCE and off.y <= TOLERANCE and off.z <= TOLERANCE and stands,
			"%s: %s is %s, the slot %s, standing on its origin (%s)" % [slot, what, box.size, size, box.position])


func _check(ok: bool, label: String) -> void:
	print(("  PASS  " if ok else "  FAIL  ") + label)
	if not ok:
		_failures += 1

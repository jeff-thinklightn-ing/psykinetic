class_name ArtCheck
extends RefCounted
## Checks a slot's own art against its entry in the manifest (ArtKit,
## art/kit/slots.json), and says what is wrong in words that say what to
## change: its size, where its origin is, its moving parts and where they
## turn, its triangles and materials, a scatter piece's single mesh, a held
## piece's second grip, a creature's rig and clips, where it came from, and
## files in a slot's folder
## that are not named for it. A problem is a line beginning "error:" (the
## art does not fit its slot) or "warning:" (worth a look). tools/art_check
## prints these; tools/art_drop runs it on a dropped file; art_kit_test
## holds every slot's own art to it.

## How far a size may be off, a share of the slot's (a slot's "tolerance"
## overrides), plus SLACK.
const TOLERANCE := 0.05
## Metres any measure may be off by, for rounding in the export.
const SLACK := 0.02
## Materials a piece may have unless its slot says ("materials"): the
## shared palette (decision 261); a slot with a glowing or glass part says 2.
const MATERIALS := 1


## Every problem with [param slot]'s own art (none when it has none yet).
static func check(slot: String) -> Array[String]:
	var out: Array[String] = []
	if not ArtKit.has(slot):
		out.append("error: %s is not a slot in %s" % [slot, ArtKit.MANIFEST])
		return out
	var entry := ArtKit.spec(slot)
	if str(entry.get("type", "mesh")) == "texture":
		out.append_array(_check_texture(slot))
	else:
		for variant in range(1, ArtKit.variant_count(slot) + 1):
			var path := ArtKit.own_path(slot, variant)
			var scene := ArtKit._scene(path)
			if scene == null:
				out.append("error: %s does not load (Godot's import failed, or it names a file that isn't there): export it again" % path.get_file())
				continue
			var node := scene.instantiate() as Node3D
			for problem in check_node(slot, node):
				var cut := problem.find(": ") + 2
				out.append(problem.left(cut) + path.get_file() + ": " + problem.substr(cut))
			node.free()
			out.append_array(_check_blend(path))
	if ArtKit.variant_count(slot) > 0:
		var source: Dictionary = entry.get("source", {})
		if str(source.get("by", "")) == "" or str(source.get("license", "")) == "":
			out.append("error: %s has art of its own but no \"source\" in %s: add \"source\": {\"by\": \"<who made it>\", \"tool\": \"blender\", \"license\": \"<licence>\", \"date\": \"<yyyy-mm-dd>\"} to its entry" % [slot, ArtKit.MANIFEST])
	return out


## The problems with [param node] as [param slot]'s art: the node as its
## .glb's scene makes it, parts in their closed place.
static func check_node(slot: String, node: Node3D) -> Array[String]:
	var out: Array[String] = []
	var entry := ArtKit.spec(slot)
	var kind := str(entry.get("kind", "cell"))
	var want := ArtKit.size(slot)
	var box := ArtKit.bounds_of(node)
	var share := float(entry.get("tolerance", TOLERANCE))
	var axes := ["x (across)", "y (up)", "z (along)"] if kind == "edge" else ["x", "y (up)", "z"]
	var ratios := Vector3(box.size.x / maxf(want.x, 0.001), box.size.y / maxf(want.y, 0.001), box.size.z / maxf(want.z, 0.001))
	var even := ratios.x > 0.0 and absf(ratios.y / ratios.x - 1.0) < 0.1 and absf(ratios.z / ratios.x - 1.0) < 0.1
	if even and (ratios.x > 1.5 or ratios.x < 0.67):
		out.append("error: %s times the slot's size every way (%.2f x %.2f x %.2f m, the slot %.2f x %.2f x %.2f): %s" % [
			_times(ratios.x), box.size.x, box.size.y, box.size.z, want.x, want.y, want.z,
			"modelled in centimetres? Apply a scale of 0.01" if absf(ratios.x / 100.0 - 1.0) < 0.1 else "scale it by %s and apply the scale" % str(snappedf(1.0 / ratios.x, 0.001))])
	for axis in (range(3) if not (even and (ratios.x > 1.5 or ratios.x < 0.67)) else []):
		var have := box.size[axis]
		var limit := want[axis] * share + SLACK
		if absf(have - want[axis]) > limit:
			out.append("error: %s %.2f m in %s, the slot is %.2f m (±%d%%): %s" % [
				"too big," if have > want[axis] else "too small,", have, axes[axis], want[axis], roundi(share * 100.0),
				"scale it, or check it was modelled in metres" if absf(have / maxf(want[axis], 0.001) - 1.0) > 0.5 else "trim or stretch it"])
	var centre := box.get_center()
	if kind == "held":
		pass  # Its origin is its grip, anywhere along it.
	elif kind == "floor":
		if absf(box.end.y) > SLACK:
			out.append("error: its top is at y %.2f m: a floor piece's top is at its origin (y = 0)" % box.end.y)
	elif absf(box.position.y) > SLACK:
		out.append("error: its base is at y %.2f m: the origin should be at the bottom (y = 0), so it stands on the ground" % box.position.y)
	if kind != "held" and (absf(centre.x) > want.x * share + SLACK or absf(centre.z) > want.z * share + SLACK):
		out.append("error: its middle is at x %.2f, z %.2f m: the origin should be at the middle of its base%s (set the origin in Blender, or move the mesh)" % [
			centre.x, centre.z, ", on the edge's line" if kind == "edge" else ""])
	for part: Dictionary in entry.get("parts", []):
		var name := str(part["name"])
		var found := node.find_child(name, true, false) as Node3D
		if found == null:
			out.append("error: no object named \"%s\" (its %s part): name the moving part \"%s\" in Blender, its origin on the %s" % [
				name, part.get("motion", "moving"), name, "hinge line" if part.get("motion") == "hinge" else "pivot"])
			continue
		var pivot := ArtKit._vec(part.get("pivot", [0, 0, 0]))
		var at := ArtKit._place_in(found, node).origin
		if at.distance_to(pivot) > SLACK * 2.0:
			out.append("error: \"%s\" turns about (%.2f, %.2f, %.2f), the slot's %s is at (%.2f, %.2f, %.2f): put its origin there" % [
				name, at.x, at.y, at.z, "hinge" if part.get("motion") == "hinge" else "pivot", pivot.x, pivot.y, pivot.z])
	if kind == "held":
		var sockets: Dictionary = entry.get("sockets", {})
		for socket: String in sockets:
			if socket != "grip" and node.find_child(socket, true, false) == null:
				out.append("error: no empty named \"%s\": add one where %s" % [socket, "the other hand holds it" if socket == "grip_2" else "the slot's socket is"])
	var counts := _count(node)
	var budget := int(entry.get("budget", 0))
	if budget > 0 and counts.triangles > budget:
		out.append("error: %d triangles, the slot's budget is %d: simplify it (Decimate, or fewer bevel segments)" % [counts.triangles, budget])
	var allowed := int(entry.get("materials", MATERIALS))
	if counts.materials > allowed:
		out.append("error: %d materials, at most %d: use the shared \"palette\" material (the template has it)%s" % [
			counts.materials, allowed, ", and one more for the glowing or glass part" if allowed > 1 else ""])
	var foreign: Array = counts.names.filter(func(name: String) -> bool: return name != "" and name != ArtKit.PALETTE_NAME)
	if foreign.size() > allowed - 1 and not foreign.is_empty():
		out.append("warning: material%s %s, not the shared \"palette\": colour it from the palette (the template's material), so it draws with every other piece" % [
			"s" if foreign.size() > 1 else "", ", ".join(foreign.map(func(name: String) -> String: return "\"%s\"" % name))])
	if not node.has_meta(&"grey"):
		var off := _off_swatch(node)
		if off.x > 0:
			out.append("warning: %d of %d UVs on the palette sit off its swatches' middles: colour faces by moving their UVs to a swatch's middle (the palette has %d rows: UVs made for %d come out a row off)" % [
				off.x, off.y, _palette_rows(), _palette_rows() - 1])
	if entry.has("scatter") and (counts.meshes != 1 or counts.surfaces != 1 or counts.others > 0):
		out.append("error: a scattered piece is one mesh with one material and nothing else (it has %d meshes, %d surfaces, %d other objects): join it into one object" % [
			counts.meshes, counts.surfaces, counts.others])
	var states: Array = entry.get("states", [])
	for child in node.find_children("state_*", "", true, false):
		if str(child.name).trim_prefix("state_") not in states:
			out.append("warning: \"%s\" is not one of the slot's states %s, so it never shows" % [child.name, states])
	if kind == "creature" and not node.has_meta(&"grey"):
		out.append_array(_check_rig(entry, node))
	return out


## How many UVs on [param node]'s palette surfaces sit more than a fifth of
## a swatch off every swatch's middle, of how many (x of y): a face takes
## its swatch's colour, so a UV off the middle was placed for another
## palette's grid.
static func _off_swatch(node: Node3D) -> Vector2i:
	var shared := load(ArtKit.PALETTE) as Material
	var rows := _palette_rows()
	var out := Vector2i.ZERO
	for child in ArtKit._descendants(node):
		var mesh := child as MeshInstance3D
		if mesh == null or mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			if material == null or material != shared and material.resource_name != ArtKit.PALETTE_NAME:
				continue
			var uvs: Variant = mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			if uvs == null:
				continue
			for uv: Vector2 in uvs:
				var cell := Vector2(uv.x * PALETTE_COLUMNS, uv.y * rows)
				var from_middle := (cell - cell.floor() - Vector2(0.5, 0.5)).abs()
				out.y += 1
				if from_middle.x > 0.2 or from_middle.y > 0.2:
					out.x += 1
	return out


## The palette atlas's rows of swatches (its height over a swatch's width).
static func _palette_rows() -> int:
	var image := load(PALETTE_IMAGE) as Texture2D
	return maxi(1, roundi(image.get_height() / (image.get_width() / float(PALETTE_COLUMNS)))) if image != null else 9


const PALETTE_IMAGE := "res://art/kit/palette.png"
const PALETTE_COLUMNS := 8


## A creature's rig and clips (decision 319): an armature (a Skeleton3D),
## and each clip the slot lists found by any of its names; a required one
## missing is an error, one with a fallback a warning naming what stands in.
static func _check_rig(entry: Dictionary, node: Node3D) -> Array[String]:
	var out: Array[String] = []
	if node.find_children("*", "Skeleton3D", true, false).is_empty():
		out.append("error: no armature: a creature is a rigged body, its mesh skinned to one Skeleton3D")
	var have := clip_names(node)
	for clip: Dictionary in entry.get("clips", []):
		# Where its blow lands, a fraction of the clip (CreatureView strikes it
		# so this lands with the sim's blow; CONTACT without).
		var contact: Variant = clip.get("contact", CreatureView.CONTACT)
		if not (contact is float or contact is int) or float(contact) <= 0.0 or float(contact) >= 1.0:
			out.append("error: \"%s\" clip's contact %s: a fraction of the clip, over 0 and under 1, where its blow lands" % [clip["name"], contact])
		var names: Array = clip.get("names", [clip["name"]])
		if names.any(func(name: String) -> bool: return have.has(name.to_lower())):
			continue
		var called := "\"%s\" clip (named any of %s)" % [clip["name"], ", ".join(names)]
		if clip.get("required", false):
			out.append("error: no %s: the creature reads wrong without it (its clips: %s)" % [called, ", ".join(have.keys()) if not have.is_empty() else "none"])
		elif clip.has("fallback"):
			out.append("warning: no %s: %s stands in" % [called, clip["fallback"]])
		else:
			out.append("warning: no %s: nice to have" % called)
	return out


## The names of [param node]'s animation clips, lower case, without the
## library's or an armature's prefix ("AnimalArmature|Gallop" is "gallop").
static func clip_names(node: Node) -> Dictionary:
	var out := {}
	for player: AnimationPlayer in node.find_children("*", "AnimationPlayer", true, false):
		for name in player.get_animation_list():
			var bare := str(name)
			bare = bare.substr(bare.rfind("/") + 1)
			bare = bare.substr(bare.rfind("|") + 1)
			out[bare.to_lower()] = true
	return out


static func _times(ratio: float) -> String:
	return str(snappedf(ratio, 0.1)) if ratio >= 1.0 else "1/" + str(snappedf(1.0 / ratio, 0.1))


## Triangles, distinct materials, meshes, their surfaces, and nodes that are
## neither a mesh nor the root nor a mesh's holder, under [param node].
static func _count(node: Node3D) -> Dictionary:
	var out := {"triangles": 0, "materials": 0, "meshes": 0, "surfaces": 0, "others": 0, "names": []}
	var materials := {}
	for child in ArtKit._descendants(node):
		var mesh := child as MeshInstance3D
		if mesh == null:
			if child != node and child.get_child_count() == 0 or child is Skeleton3D:
				out.others += 1
			continue
		if mesh.mesh == null:
			continue
		out.meshes += 1
		for surface in mesh.mesh.get_surface_count():
			out.surfaces += 1
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			out.triangles += (indices as PackedInt32Array).size() / 3 if indices != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var material := mesh.get_active_material(surface)
			if material != null:
				materials[material] = true
	out.materials = materials.size()
	for material: Material in materials:
		(out.names as Array).append(material.resource_name)
	return out


## A .glb's .blend beside it: there (it is the source), and not changed
## since the .glb was exported. (Times are the files' own, so this is for
## the drop tool on the machine where the art is made; a checkout sets
## both to when it wrote them.)
static func _check_blend(glb: String) -> Array[String]:
	var out: Array[String] = []
	var blend := glb.get_basename() + ".blend"
	if not FileAccess.file_exists(blend):
		if glb.get_basename().get_extension().is_valid_int():
			return out  # A variant may share the first's .blend.
		out.append("warning: %s has no %s beside it: commit the source with it" % [glb.get_file(), blend.get_file()])
	elif FileAccess.get_modified_time(blend) > FileAccess.get_modified_time(glb) + 2:
		out.append("warning: %s was saved after %s was exported: export it again (tools/art_drop.ps1 %s)" % [blend.get_file(), glb.get_file(), blend.get_file()])
	return out


static func _check_texture(slot: String) -> Array[String]:
	var out: Array[String] = []
	var texture := ArtKit.texture(slot)
	if texture == null:
		return out
	var size := Vector2i(texture.get_width(), texture.get_height())
	if size.x != size.y or size.x & (size.x - 1) != 0:
		out.append("warning: %s is %d x %d: a tileable texture is square, a power of two (512, 1024)" % [ArtKit.texture_path(slot).get_file(), size.x, size.y])
	if size.x > 2048:
		out.append("error: %s is %d across: at most 2048" % [ArtKit.texture_path(slot).get_file(), size.x])
	return out


## Files in art/kit's slot folders that no slot will read: a folder that is
## no slot's, or a file not named for its slot (a .glb named otherwise is
## never drawn).
static func check_folders() -> Array[String]:
	var out: Array[String] = []
	var known := {}
	for slot: String in ArtKit.slots():
		known[ArtKit.folder(slot)] = slot
	for category in DirAccess.get_directories_at(ArtKit.ROOT):
		var at := ArtKit.ROOT + category + "/"
		for folder in DirAccess.get_directories_at(at):
			var path := at + folder + "/"
			if not known.has(path):
				out.append("error: %s is no slot's folder (a slot named %s is in category \"%s\"?)" % [path, folder, ArtKit.spec(folder).get("category", "?") if ArtKit.has(folder) else "?"])
				continue
			var slot: String = known[path]
			for file in DirAccess.get_files_at(path):
				if file.ends_with(".import") or file.ends_with(".uid") or file.begins_with("."):
					continue
				var stem := file.get_basename()
				var named := stem == slot or stem.get_basename() == slot and stem.get_extension().is_valid_int()
				if not named:
					out.append("error: %s%s is not named for its slot: call it %s.%s" % [path, file, slot, file.get_extension()])
	return out


## docs/art_status.md as it should read now: every slot by what it is
## drawn from, the placeholders first (tools/art_status.gd writes it;
## art_kit_test fails while it is out of date).
static func status_markdown() -> String:
	var groups := {"placeholder": [], "fill": [], "own": []}
	var slots := ArtKit.slots().keys()
	slots.sort()
	for slot: String in slots:
		groups[ArtKit.filled_by(slot)].append(slot)
	var lines: Array[String] = [
		"# Art slots: what each is drawn from",
		"",
		"Generated by `tools/art_status.gd` from `art/kit/slots.json` and the slot folders; run it",
		"after art lands (`tools/art_drop.ps1` does). %d slots: %d with art of their own, %d from a" % [
			slots.size(), groups.own.size(), groups.fill.size()],
		"third-party fill, %d placeholders. The conventions are in `docs/art_style.md`." % groups.placeholder.size(),
		"The order art-kit wants art in is `art/kit/priority.json`; `art/kit/status.json` has every",
		"slot in that order with what it is drawn from, for tools (art-gen reads it).",
		"",
		"## Placeholders remaining",
		"",
		"Drawn as a grey box (a texture slot: terrain's procedural colour).",
		"",
		"| Slot | Kind | Size (m) | Budget | Used for |",
		"|------|------|----------|--------|----------|",
	]
	for slot: String in groups.placeholder:
		lines.append(_row(slot, [_kind(slot), _size(slot), _budget(slot), _uses(slot)]))
	lines.append_array(["", "## Third-party fills to replace", "",
		"| Slot | Kind | Size (m) | Budget | Drawn from | Licence |", "|------|------|----------|--------|------------|---------|"])
	for slot: String in groups.fill:
		var fill: Dictionary = ArtKit.spec(slot)["fill"]
		var source: Dictionary = ArtKit.manifest().get("sources", {}).get(str(fill.get("from", "")), {})
		lines.append(_row(slot, [_kind(slot), _size(slot), _budget(slot),
			"%s: %s" % [source.get("name", fill.get("from")), fill.get("piece")], str(source.get("license", "?"))]))
	lines.append_array(["", "## Own art", "", "| Slot | Variants | By | Licence | Date |", "|------|----------|----|---------|------|"])
	for slot: String in groups.own:
		var source: Dictionary = ArtKit.spec(slot).get("source", {})
		lines.append(_row(slot, [str(ArtKit.variant_count(slot)), str(source.get("by", "?")), str(source.get("license", "?")), str(source.get("date", ""))]))
	return "\n".join(lines) + "\n"


## art/kit/status.json as it should read now, for art-gen and other tools:
## every slot in the order art/kit/priority.json wants its art, with what
## it is drawn from now ("own", "fill" or "placeholder"), its group, and
## who makes it when that isn't art-gen (tools/art_status.gd writes it;
## art_kit_test fails while it is out of date).
static func status_json() -> String:
	var order := priority_order()
	var counts := {"own": 0, "fill": 0, "placeholder": 0}
	var entries: Array = []
	for at in order.size():
		var slot: String = order[at].slot
		var entry := ArtKit.spec(slot)
		var filled := ArtKit.filled_by(slot)
		counts[filled] += 1
		var row := {"slot": slot, "status": filled, "group": order[at].group, "order": at + 1,
			"type": str(entry.get("type", "model")), "kind": _kind(slot), "category": str(entry.get("category", "")),
			"size": _size(slot), "budget": int(entry.get("budget", 0))}
		if order[at].has("for"):
			row["for"] = order[at]["for"]
		entries.append(row)
	return JSON.stringify({
		"about": "Generated by tools/art_status.gd from art/kit/slots.json, art/kit/priority.json and the slot folders; don't edit. status: own (its own art), fill (a third-party piece, to replace), placeholder (a grey box, or terrain's procedural colour for a texture). Slots are in the order art-kit wants their art; one with \"for\" is made by someone other than art-gen.",
		"counts": counts, "slots": entries}, "\t", false) + "\n"


## Every slot as {slot, group[, for]}, in art/kit/priority.json's order;
## slots it doesn't name come last, in the group "rest", by name.
static func priority_order() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRIORITY))
	var groups: Array = parsed.get("groups", []) if parsed is Dictionary else []
	for group: Dictionary in groups:
		for slot: String in group.get("slots", []):
			if seen.has(slot) or not ArtKit.has(slot):
				continue
			seen[slot] = true
			var row := {"slot": slot, "group": str(group.get("name", ""))}
			if group.has("for"):
				row["for"] = str(group["for"])
			out.append(row)
	var rest := ArtKit.slots().keys()
	rest.sort()
	for slot: String in rest:
		if not seen.has(slot):
			out.append({"slot": slot, "group": "rest"})
	return out


## Problems with art/kit/priority.json: a slot named twice or no slot.
static func check_priority() -> Array[String]:
	var out: Array[String] = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRIORITY))
	if not parsed is Dictionary:
		return ["error: %s is not a JSON object" % PRIORITY]
	var seen := {}
	for group: Dictionary in parsed.get("groups", []):
		for slot: String in group.get("slots", []):
			if not ArtKit.has(slot):
				out.append("error: %s names %s, no slot" % [PRIORITY, slot])
			elif seen.has(slot):
				out.append("error: %s names %s twice (%s, %s)" % [PRIORITY, slot, seen[slot], group.get("name", "")])
			seen[slot] = str(group.get("name", ""))
	return out


const PRIORITY := "res://art/kit/priority.json"


## THIRD_PARTY.md's art slot block as it should read now: each third-party
## source the manifest names, and the slots drawn from it.
static func third_party_block() -> String:
	var lines: Array[String] = [THIRD_PARTY_BEGIN, "", "| Source | Licence | Where | Slots drawn from it |", "|--------|---------|-------|---------------------|"]
	var sources: Dictionary = ArtKit.manifest().get("sources", {})
	var names := sources.keys()
	names.sort()
	for name: String in names:
		var source: Dictionary = sources[name]
		var drawn: Array[String] = []
		var slots := ArtKit.slots().keys()
		slots.sort()
		for slot: String in slots:
			if ArtKit.filled_by(slot) == "fill" and str(ArtKit.spec(slot)["fill"].get("from", "")) == name:
				drawn.append(slot)
		lines.append("| [%s](%s) | %s (`%s`) | `%s` | %s |" % [source.get("name", name), source.get("url", ""), source.get("license", "?"),
			source.get("license_file", ""), str(source.get("path", "")).trim_prefix("res://"), ", ".join(drawn) if not drawn.is_empty() else "none now"])
	var own: Array[String] = []
	for slot: String in ArtKit.slots():
		var by := str(ArtKit.spec(slot).get("source", {}).get("by", ""))
		if ArtKit.filled_by(slot) == "own" and by != "" and not by.to_lower().begins_with("jeff"):
			own.append("%s (%s, %s)" % [slot, by, ArtKit.spec(slot)["source"].get("license", "?")])
	lines.append("")
	lines.append("Slots whose own art came from someone else: %s." % (", ".join(own) if not own.is_empty() else "none"))
	lines.append("")
	lines.append(THIRD_PARTY_END)
	return "\n".join(lines)


const THIRD_PARTY_BEGIN := "<!-- art slots: written by tools/art_status.gd from art/kit/slots.json; edit there -->"
const THIRD_PARTY_END := "<!-- end of art slots -->"


static func _row(slot: String, cells: Array) -> String:
	return "| `%s` | %s |" % [slot, " | ".join(cells.map(func(cell: Variant) -> String: return str(cell).replace("|", "/")))]


static func _budget(slot: String) -> String:
	var entry := ArtKit.spec(slot)
	return str(int(entry["budget"])) if entry.has("budget") else ""


static func _kind(slot: String) -> String:
	var entry := ArtKit.spec(slot)
	return str(entry.get("kind", entry.get("type", "")))


static func _size(slot: String) -> String:
	var entry := ArtKit.spec(slot)
	if str(entry.get("type", "")) == "texture":
		return "tile %s" % entry.get("tile_m", "?")
	var size := ArtKit.size(slot)
	return "%s x %s x %s" % [snappedf(size.x, 0.01), snappedf(size.y, 0.01), snappedf(size.z, 0.01)]


static func _uses(slot: String) -> String:
	var uses := str(ArtKit.spec(slot).get("uses", ""))
	return uses if uses.length() <= 90 else uses.left(87) + "..."

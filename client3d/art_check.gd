class_name ArtCheck
extends RefCounted
## Checks a slot's own art against its entry in the manifest (ArtKit,
## art/kit/slots.json), and says what is wrong in words that say what to
## change: its size, where its origin is, its moving parts and where they
## turn, its triangles and materials, a scatter piece's single mesh, a held
## piece's second grip, where it came from, and files in a slot's folder
## that are not named for it. A problem is a line beginning "error:" (the
## art does not fit its slot) or "warning:" (worth a look). tools/art_check
## prints these; tools/art_drop runs it on a dropped file; art_kit_test
## holds every slot's own art to it.

## How far a size may be off, a share of the slot's (a slot's "tolerance"
## overrides), plus SLACK.
const TOLERANCE := 0.05
## Metres any measure may be off by, for rounding in the export.
const SLACK := 0.02
## Materials a piece may have unless its slot says ("materials").
const MATERIALS := 3


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
			var node := (load(path) as PackedScene).instantiate() as Node3D
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
		out.append("error: %d materials, at most %d: join them into one (one image over a UV map)" % [counts.materials, allowed])
	if entry.has("scatter") and (counts.meshes != 1 or counts.surfaces != 1 or counts.others > 0):
		out.append("error: a scattered piece is one mesh with one material and nothing else (it has %d meshes, %d surfaces, %d other objects): join it into one object" % [
			counts.meshes, counts.surfaces, counts.others])
	var states: Array = entry.get("states", [])
	for child in node.find_children("state_*", "", true, false):
		if str(child.name).trim_prefix("state_") not in states:
			out.append("warning: \"%s\" is not one of the slot's states %s, so it never shows" % [child.name, states])
	return out


static func _times(ratio: float) -> String:
	return str(snappedf(ratio, 0.1)) if ratio >= 1.0 else "1/" + str(snappedf(1.0 / ratio, 0.1))


## Triangles, distinct materials, meshes, their surfaces, and nodes that are
## neither a mesh nor the root nor a mesh's holder, under [param node].
static func _count(node: Node3D) -> Dictionary:
	var out := {"triangles": 0, "materials": 0, "meshes": 0, "surfaces": 0, "others": 0}
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

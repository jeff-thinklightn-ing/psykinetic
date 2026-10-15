class_name ItemIcons
extends Node
## Each item's icon for the HUD (the pack panel), drawn from its art-kit
## slot (Items' "art") on demand: the first ask for one queues it and gives
## null; it is rendered in a SubViewport of its own (an orthographic camera
## from the game's 3/4 angle, SIZE px, a clear background), one a frame,
## kept, and icon_ready(id) says it is there. A long thing (a spear, a bundle
## of wood) is turned to lie across the icon's diagonal. Headless nothing is
## rendered: icon gives null always, and the panel shows names instead.
## Client only; the server never makes one. Ground piles keep their 3D art.
## When an item's art changes, forget(id) (or forget() for all) draws it
## again the next time it is asked for.

signal icon_ready(id: String)

const SIZE := 128
## The camera: turned YAW about the vertical and tipped down PITCH, as the
## game's camera looks on.
const YAW := PI * 0.25
const PITCH := -PI / 6.0
## Room round the thing, a share of its size on screen.
const MARGIN := 1.18
## Taller than this times its width and depth: laid across the diagonal.
const LONG := 1.6

## Off headless: whether icons are drawn at all.
var enabled := DisplayServer.get_name() != "headless"

## Drawn icons, by item id and whether the art was placeholders.
var _cache: Dictionary[String, Texture2D] = {}
var _queue: Array[String] = []
var _busy := false
var _viewport: SubViewport
var _camera: Camera3D
var _stage: Node3D


## The camera frame that fits [param bounds], placed by [param place] (a
## box turned is fitted by its own corners, not by a bigger box round it),
## seen along [param view] (a camera basis: it looks down its -z): its
## transform, orthographic size (height = width, square) and far plane,
## all of it in view with MARGIN round it.
static func frame(bounds: AABB, view: Basis, place := Transform3D.IDENTITY) -> Dictionary:
	var inverse := view.inverse()
	var low := Vector3.INF
	var high := -Vector3.INF
	for i in 8:
		var corner := inverse * (place * bounds.get_endpoint(i))
		low = low.min(corner)
		high = high.max(corner)
	var middle := view * ((low + high) * 0.5)
	var extent := high - low
	var size := maxf(maxf(extent.x, extent.y) * MARGIN, 0.01)
	var back := extent.z * 0.5 + 1.0
	return {"transform": Transform3D(view, middle + view.z * back), "size": size, "far": back + extent.z * 0.5 + 1.0}


## The camera's basis for an icon.
static func view_basis() -> Basis:
	return Basis.from_euler(Vector3(PITCH, YAW, 0.0))


## How a thing of [param size] (the art slot's) is turned for its icon: a
## long one rolled an eighth of a turn about the line of sight, its top to
## the right; anything else as it stands.
static func pose(size: Vector3) -> Basis:
	if size.y > maxf(size.x, size.z) * LONG:
		return Basis(view_basis().z, -PI * 0.25)
	return Basis.IDENTITY


func _ready() -> void:
	if not enabled:
		return
	ArtKit.on_changed(_art_changed)
	_viewport = SubViewport.new()
	_viewport.name = "Icons"
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.75, 0.8)
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-PI * 0.3, PI * 0.15, 0.0)
	sun.light_energy = 1.2
	_viewport.add_child(sun)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.05
	_viewport.add_child(_camera)
	_stage = Node3D.new()
	_viewport.add_child(_stage)


## [param id]'s icon, or null: not drawn yet (it is queued, and icon_ready
## follows), headless, or no art for it.
func icon(id: String) -> Texture2D:
	if not enabled or not Items.exists(id):
		return null
	var key := _key(id)
	if _cache.has(key):
		return _cache[key]
	if not ArtKit.has(_slot(id)):
		return null
	if id not in _queue:
		_queue.append(id)
	return null


## Draws [param id]'s icon again when next asked for; every item's when
## empty (the art changed).
func forget(id := "") -> void:
	if id.is_empty():
		_cache.clear()
		return
	_cache.erase(_key(id))
	_cache.erase(_key(id, not ArtKit.show_placeholders))


func _exit_tree() -> void:
	ArtKit.off_changed(_art_changed)


## A slot's art changed (ArtKit.forget): the icons drawn from it, again.
func _art_changed(slot: String) -> void:
	if slot.is_empty():
		forget()
		return
	for id: String in Items.ids():
		if _slot(id) == slot:
			forget(id)


func _process(_delta: float) -> void:
	if not enabled or _busy or _queue.is_empty():
		return
	_draw(_queue.pop_front())


func _draw(id: String) -> void:
	_busy = true
	var slot := _slot(id)
	var thing := ArtKit.instance(slot)
	var pivot := Node3D.new()
	pivot.basis = pose(ArtKit.size(slot))
	pivot.add_child(thing)
	_stage.add_child(pivot)
	var fit := frame(ArtKit.bounds_of(thing), view_basis(), pivot.transform * thing.transform)
	_camera.transform = fit["transform"]
	_camera.size = fit["size"]
	_camera.far = fit["far"]
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# The viewport draws this frame; its image can be read after.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	pivot.queue_free()
	_busy = false
	if image == null or image.is_empty():
		return
	_cache[_key(id)] = ImageTexture.create_from_image(image)
	icon_ready.emit(id)


static func _slot(id: String) -> String:
	return str(Items.def(id).get("art", ""))


static func _key(id: String, placeholders := ArtKit.show_placeholders) -> String:
	return "%s|%s" % [id, "grey" if placeholders else "art"]

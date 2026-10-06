class_name EntityFactory
extends RefCounted
## Builds any entity from a spawn spec, on every peer alike, out of the one
## generic scene (entities/entity.tscn: a Node2D with a Sprite). The spec
## says what it is and what it looks like:
##
##   script   which GridEntity subclass to attach ("res://sim/monster.gd");
##            missing or not a GridEntity: the base class, logged once
##   shape    "capsule" | "cube" | "barrel" | "sphere" | "slab" | "flat";
##            anything else is drawn as a capsule and logged once
##   tint     Color for the sprite (optional)
##   scale    uniform float on top of the shape's size (optional, 1.0)
##   label    name drawn over the sprite (optional)
##   name     node name
##   tile     start tile
##   peer     owning peer id (players), 0 otherwise
##   props    any other property to set on the entity (mass, max_hp, ...)
##   spawn    level-slot index, for respawn
##
## So a new kind of thing needs no new scene: a script the client already
## has, a shape, and props.

const SCENE := preload("res://entities/entity.tscn")
const BASE_SCRIPT := preload("res://sim/grid_entity.gd")
const DEFAULT_SHAPE := "capsule"
## Bump when the meaning of a spawn spec changes in a way an older client
## would get wrong. Part of Net.protocol().
const SPEC_VERSION := 3
## Placeholder art per shape. Each sprite is scaled so it stands
## Iso.HEIGHTS[shape] tile heights tall, and placed so the texture row
## "foot" (where the body meets the ground) sits on the tile's centre.
## Shapes with a face get the small facing pip.
const SHAPES := {
	"capsule": {"texture": preload("res://art/capsule.svg"), "foot": 18.0, "facing": true},
	"cube": {"texture": preload("res://art/crate.svg"), "foot": 15.0, "facing": false},
	"barrel": {"texture": preload("res://art/barrel.svg"), "foot": 16.0, "facing": false},
	"sphere": {"texture": preload("res://art/sphere.svg"), "foot": 9.5, "facing": false},
	"slab": {"texture": preload("res://art/slab.svg"), "foot": 10.0, "facing": false},
	"flat": {"texture": preload("res://art/flat.svg"), "foot": 5.0, "facing": false},
}

static var _warned: Dictionary[String, bool] = {}
static var _scripts: Dictionary[String, Script] = {}


static func build(spec: Dictionary) -> GridEntity:
	var node: Node2D = SCENE.instantiate()
	node.set_script(script_for(spec))
	var entity := node as GridEntity
	entity.name = str(spec.get("name", "Entity"))

	var shape := shape_for(spec)
	var sprite: Sprite2D = entity.get_node("Sprite")
	var texture: Texture2D = shape["texture"]
	sprite.texture = texture
	var size := Iso.height_px(shape_name_for(spec)) / texture.get_height()
	sprite.scale = Vector2(size, size)
	sprite.position = Vector2(0, -(float(shape["foot"]) - texture.get_height() * 0.5) * size)
	if shape["facing"]:
		var pip := Polygon2D.new()
		pip.name = "Facing"
		pip.position = Vector2(0, -2)
		pip.color = Color(0.05, 0.05, 0.1, 0.9)
		pip.polygon = PackedVector2Array([Vector2(-1.5, 0), Vector2(0, -1.5), Vector2(1.5, 0), Vector2(0, 1.5)])
		sprite.add_child(pip)

	if spec.get("tint") is Color:
		entity.tint = spec["tint"]
	var scale := float(spec.get("scale", 1.0))
	if scale > 0.0 and scale != 1.0:
		entity.scale = Vector2(scale, scale)
	entity.label = str(spec.get("label", ""))
	var props: Dictionary = spec.get("props", {})
	for property: String in props:
		entity.set(property, props[property])

	entity.owner_peer = int(spec.get("peer", 0))
	entity.spawn_spec = spec
	entity.start_tile = spec.get("tile", Vector2i.ZERO)
	# Placeholders until World (server) or the synchronizer (client) says otherwise.
	entity.tile = entity.start_tile
	entity.hp = entity.max_hp
	entity.stamina = entity.max_stamina
	return entity


## The spec's script if it is a GridEntity subclass, else the base class.
static func script_for(spec: Dictionary) -> Script:
	var path := str(spec.get("script", ""))
	if path.is_empty():
		return BASE_SCRIPT
	if _scripts.has(path):
		return _scripts[path]
	var script: Script = null
	if ResourceLoader.exists(path):
		script = load(path) as Script
	if script == null or not _extends_base(script):
		_warn_once("script " + path, "[spawn] %s is not a GridEntity script; using the base class" % path)
		script = BASE_SCRIPT
	_scripts[path] = script
	return script


static func _extends_base(script: Script) -> bool:
	var current: Script = script
	while current != null:
		if current == BASE_SCRIPT:
			return true
		current = current.get_base_script()
	return false


static func shape_for(spec: Dictionary) -> Dictionary:
	var shape := str(spec.get("shape", DEFAULT_SHAPE))
	if SHAPES.has(shape):
		return SHAPES[shape]
	_warn_once("shape " + shape, "[spawn] unknown shape %s; drawing a capsule" % shape)
	return SHAPES[DEFAULT_SHAPE]


## The SHAPES key a spec resolves to (DEFAULT_SHAPE for an unknown one).
static func shape_name_for(spec: Dictionary) -> String:
	var shape := str(spec.get("shape", DEFAULT_SHAPE))
	return shape if SHAPES.has(shape) else DEFAULT_SHAPE


## The short type name for logs: "monster" for res://sim/monster.gd.
static func type_name(spec: Dictionary) -> String:
	var path := str(spec.get("script", ""))
	return path.get_file().get_basename() if not path.is_empty() else "entity"


static func _warn_once(key: String, message: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(message)

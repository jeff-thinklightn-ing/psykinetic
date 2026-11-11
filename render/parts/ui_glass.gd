class_name UiGlass
extends PanelContainer
## A window's pane in the approved look (decision 854; Jeff, 11-10: "the solid
## with glass look is approved"): the theme's Glass panel (the lifted pane at
## 0.70, a lit rim, a soft shadow) with the world behind it frosted, blurred
## and half its colour taken out, so the pane reads as glass over any ground.
## The frost is a Node2D drawn behind the panel (show_behind_parent), shaped
## by the pane's own corners, so a container's layout never moves it. Off
## (frost = false, the flat-tint setting for slow machines), or headless, the
## pane is the same tint over the sharp world.

const SHADER := preload("res://render/parts/ui_glass.gdshader")
const GROUP := &"ui_glass"

## Whether panes frost the world behind them (the flat-tint setting; perf
## measures the cost on the low machine before it is on there by default).
static var frost := DisplayServer.get_name() != "headless"

var _frost: Node2D


func _init() -> void:
	theme_type_variation = &"Glass"


func _ready() -> void:
	add_to_group(GROUP)
	resized.connect(_redraw_frost)
	_apply()


## Turns the frost on or off for every pane open now and every one made after.
static func set_frost(on: bool) -> void:
	frost = on and DisplayServer.get_name() != "headless"
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for pane: Node in tree.get_nodes_in_group(GROUP):
		(pane as UiGlass)._apply()


## Whether this pane draws its frost now.
func frosted() -> bool:
	return _frost != null and _frost.visible


func _apply() -> void:
	if frost and _frost == null:
		_frost = _Frost.new()
		_frost.name = "Frost"
		_frost.show_behind_parent = true
		var material := ShaderMaterial.new()
		material.shader = SHADER
		_frost.material = material
		add_child(_frost, false, Node.INTERNAL_MODE_FRONT)
	if _frost != null:
		_frost.visible = frost
		_redraw_frost()


func _redraw_frost() -> void:
	if _frost != null:
		_frost.queue_redraw()


## The frost: the pane's shape, white, which the shader fills with the world
## behind it, blurred and greyed.
class _Frost extends Node2D:
	func _draw() -> void:
		var pane := get_parent() as Control
		if pane == null:
			return
		var shape := StyleBoxFlat.new()
		var style := pane.get_theme_stylebox(&"panel")
		var radius := (style as StyleBoxFlat).corner_radius_top_left if style is StyleBoxFlat else 0
		shape.set_corner_radius_all(radius)
		shape.bg_color = Color.WHITE
		draw_style_box(shape, Rect2(Vector2.ZERO, pane.size))

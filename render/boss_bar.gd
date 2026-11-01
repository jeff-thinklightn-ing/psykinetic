class_name BossBar
extends Control
## A boss in sight (752, ui's side; Jeff on v0.1.194: "the boss should have
## some graphical indicator"; the coordinator's pick A): his name in brass
## beside a drawn skull at the top centre of the HUD, over a long bar of his
## hp, shown while a boss (enemy-ai's replicated Monster.boss, keyed on the
## flag and never on a kind) is spawned, alive, in the local player's zone
## and within SIGHT tiles of them. Brand the Ox now; any later boss is data.
## His nameplate in the world is brass with the same skull over it
## (Client3D._sync_named). The look is the shared theme's (UiTheme).

## How near a boss is, in tiles, for the bar to show.
const SIGHT := 14
## The bar's size and its place under the top edge, at 1080 lines (scaled
## for a taller screen as the minimap is).
const BAR_WIDTH := 420.0
const BAR_HEIGHT := 10.0
const TOP := 18.0
const SKULL := 22.0

## Main's: () -> the boss to show, or null.
var boss_of: Callable
## The boss shown, null for none.
var boss: GridEntity = null
## hp and max_hp as last drawn.
var _drawn := Vector2i(-1, -1)
var _name := ""

var _title: Label
var _skull: TextureRect


func _init() -> void:
	name = "BossBar"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	_title = Label.new()
	_title.theme_type_variation = &"Heading"
	_title.add_theme_color_override("font_color", UiTheme.color("brass_bright"))
	_title.add_theme_color_override("font_outline_color", UiTheme.color("outline"))
	_title.add_theme_constant_override("outline_size", UiTheme.constant("outline"))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_skull = TextureRect.new()
	_skull.texture = skull_texture(64, UiTheme.color("brass_bright"))
	_skull.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_skull.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_skull)


func _process(_delta: float) -> void:
	var now: GridEntity = boss_of.call() if boss_of.is_valid() else null
	if now != boss:
		boss = now
		_drawn = Vector2i(-1, -1)
	visible = boss != null and is_instance_valid(boss)
	if not visible:
		return
	var words := given_name_of(boss)
	if words.is_empty():
		words = boss.label if not boss.label.is_empty() else String(boss.name)
	var k := ui_scale()
	var screen := get_viewport_rect().size
	if words != _name:
		_name = words
		_title.text = words
	_title.size = _title.get_combined_minimum_size()
	var skull := SKULL * k
	var row := _title.size.x + skull + 8.0 * k
	_skull.size = Vector2(skull, skull)
	_skull.position = Vector2((screen.x - row) / 2.0, TOP * k + (_title.size.y - skull) / 2.0)
	_title.position = Vector2(_skull.position.x + skull + 8.0 * k, TOP * k)
	var hp := Vector2i(boss.hp, int(boss.max_hp))
	if hp != _drawn:
		_drawn = hp
		queue_redraw()


func ui_scale() -> float:
	var screen := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	return maxf(1.0, screen.y / Minimap.BASE_HEIGHT)


## The bar's rect on screen, under the name.
func bar_rect() -> Rect2:
	var k := ui_scale()
	var screen := get_viewport_rect().size
	var width := BAR_WIDTH * k
	var top := TOP * k + (_title.size.y if _title != null else 0.0) + 4.0 * k
	return Rect2((screen.x - width) / 2.0, top, width, BAR_HEIGHT * k)


## His share of hp left, 0 to 1.
func share() -> float:
	if boss == null or not is_instance_valid(boss):
		return 0.0
	return clampf(float(boss.hp) / maxf(float(boss.max_hp), 1.0), 0.0, 1.0)


func _draw() -> void:
	if boss == null:
		return
	var k := ui_scale()
	var rect := bar_rect()
	draw_rect(rect.grow(2.0 * k), UiTheme.color("outline"))
	draw_rect(rect, UiTheme.color("backing_deep"))
	var fill := rect
	fill.size.x *= share()
	draw_rect(fill, UiTheme.color("alarm"))
	draw_rect(rect.grow(2.0 * k), UiTheme.color("brass"), false, maxf(1.0, k))


## A monster's own name (752, enemy-ai's replicated Monster.given_name:
## "Crake", "Brand the Ox"), "" for none.
static func given_name_of(entity: GridEntity) -> String:
	return (entity as Monster).given_name if entity is Monster else ""


## Whether [param entity] is a boss (752, enemy-ai's replicated Monster.boss).
static func is_boss(entity: GridEntity) -> bool:
	return entity is Monster and (entity as Monster).boss


## A skull, [param px] square, in [param colour] with a dark rim: the boss's
## mark (the theme's fonts have none), drawn here for the bar and the
## nameplate both.
static func skull_texture(px: int, colour: Color) -> ImageTexture:
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var inside := func(x: float, y: float) -> bool:
		var head := Vector2(x - 0.5, (y - 0.4) * 1.08).length() <= 0.36
		var jaw := x >= 0.3 and x <= 0.7 and y >= 0.55 and y <= 0.86
		var eye := Vector2(x - 0.355, y - 0.44).length() <= 0.1 or Vector2(x - 0.645, y - 0.44).length() <= 0.1
		var nose := absf(x - 0.5) <= 0.045 * (y - 0.54) / 0.1 and y >= 0.54 and y <= 0.64
		var teeth := y >= 0.74 and (absf(x - 0.43) <= 0.018 or absf(x - 0.57) <= 0.018)
		return (head or jaw) and not eye and not nose and not teeth
	var rim := Color(0.06, 0.05, 0.04, 0.95)
	var mask: Array[bool] = []
	mask.resize(px * px)
	for y in px:
		for x in px:
			mask[y * px + x] = inside.call((x + 0.5) / px, (y + 0.5) / px)
	var r := maxi(1, px / 20)
	for y in px:
		for x in px:
			if mask[y * px + x]:
				image.set_pixel(x, y, colour)
				continue
			var near := false
			for dy in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < px and ny < px and mask[ny * px + nx]:
						near = true
			image.set_pixel(x, y, rim if near else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)

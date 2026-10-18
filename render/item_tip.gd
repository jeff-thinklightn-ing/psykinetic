class_name ItemTip
extends PanelContainer
## What a thing in a slot is, on hover (ui's step 3): its name (a named
## thing's in brass, items' decision 365), what it is and does from the
## catalog the client holds (the verb's words, its hands, its weight:
## items' "says" when the catalog has them), its strength's meaning, its
## condition and growth marks, the kills line (415) and the story line
## (items' "story: ..."), from the slot's note (World._show_notes). Shown by
## PackPanel over the slot the mouse is on. The look is the shared
## theme's (UiTheme, docs/ui_style.md).

const WIDTH := 640.0
const GAP := 12.0
## Plain words for a verb's kind, used until the catalog says (items' "says").
const VERB_WORDS := {"knockback": "knocks back", "block": "blocks blows from ahead", "knockdown": "knocks down",
	"reach": "strikes two cells away", "backstab": "more from behind", "ranged": "shoots"}

var _column: VBoxContainer


func _init() -> void:
	name = "ItemTip"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 10


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 4)
	add_child(_column)


## The tip's lines for [param id] with its slot note [param note]:
## [{text, style}] each, style one of name, title, kind, strength, mark,
## warn, kills, story. Empty for no thing.
static func lines_for(id: String, note: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if id.is_empty():
		return out
	var catalog := Items.name_of(id)
	var rows := note.split("\n", false)
	var head := rows[0] if rows.size() > 0 else ""
	# The head: the title (a named thing's "Wren's dagger (quiet, ill-starred)"
	# or the catalog name), then the condition and the growth marks after commas.
	var marks: Array[String] = []
	var title := head
	var rest := ""
	if head.contains(")"):
		title = head.substr(0, head.find(")") + 1)
		rest = head.substr(head.find(")") + 1)
	elif head.contains(","):
		title = head.substr(0, head.find(","))
		rest = head.substr(head.find(","))
	for part: String in rest.split(",", false):
		if not part.strip_edges().is_empty():
			marks.append(part.strip_edges())
	var strengths: Array[String] = []
	if title.contains("("):
		for part: String in title.substr(title.find("(") + 1).trim_suffix(")").split(",", false):
			strengths.append(part.strip_edges())
		title = title.substr(0, title.find("(")).strip_edges()
	var named := not title.is_empty() and title != catalog
	out.append({"text": title if not title.is_empty() else catalog, "style": "name" if named else "title"})
	if named:
		out.append({"text": catalog, "style": "kind"})
	# What it is and does, from the catalog.
	var def := Items.def(id)
	var about: Array[String] = []
	var verb: Dictionary = def.get("verb", {})
	if not verb.is_empty():
		var says := str(verb.get("says", ""))
		about.append(says if not says.is_empty() else str(VERB_WORDS.get(str(verb.get("kind", "")), str(verb.get("kind", "")))))
	if int(def.get("hands", 0)) >= 2:
		about.append("both hands")
	elif not verb.is_empty():
		about.append("one hand")
	if float(def.get("weight", 0.0)) > 0.0:
		about.append("%s kg" % str(snappedf(float(def["weight"]), 0.1)))
	if not about.is_empty():
		out.append({"text": "; ".join(about), "style": "kind"})
	for strength in strengths:
		if strength == World.KEPT_MARK:
			out.append({"text": "%s: kept from the one it is named for" % strength, "style": "warn"})
		else:
			var says := str(Items.naming()["strengths"].get(strength, {}).get("says", ""))
			out.append({"text": "%s%s" % [strength, ": " + says if not says.is_empty() else ""], "style": "strength"})
	for mark in marks:
		# A growth mark (items' 417, 421) explained in the catalog's words.
		var says := ""
		if mark.ends_with("-bane"):
			says = str(Items.growth().get("says", {}).get("bane", ""))
		elif mark.begins_with("vengeance"):
			says = str(Items.growth().get("says", {}).get("vengeance", ""))
		elif mark == "blessed":
			says = str(Items.growth().get("says", {}).get("blessed", ""))
		out.append({"text": "%s%s" % [mark, ": " + says if not says.is_empty() else ""], "style": "mark"})
	for i in range(1, rows.size()):
		var row := rows[i].strip_edges()
		if row.begins_with("story:"):
			out.append({"text": row.trim_prefix("story:").strip_edges(), "style": "story"})
		elif not row.is_empty():
			out.append({"text": row, "style": "kills"})
	return out


## Shown for [param id] with [param note], its bottom left at [param at]
## (the slot's top left, in the HUD's units), kept on screen.
func show_for(id: String, note: String, at: Vector2) -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	var rows := lines_for(id, note)
	if rows.is_empty():
		visible = false
		return
	for row in rows:
		var label := Label.new()
		label.text = row["text"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Wrapped at the tip's width (a label with no width wraps every word).
		label.custom_minimum_size = Vector2(WIDTH - 2 * UiTheme.constant("pad"), 0)
		match row["style"]:
			"name":
				label.theme_type_variation = &"Name"
			"title":
				label.add_theme_font_override("font", UiTheme.font("serif"))
			"kind", "kills":
				label.theme_type_variation = &"Caption"
			"story":
				label.theme_type_variation = &"Caption"
				label.add_theme_font_override("font", UiTheme.font("serif"))
			"strength":
				label.add_theme_color_override("font_color", UiTheme.color("brass"))
			"mark":
				label.add_theme_color_override("font_color", UiTheme.color("text_dim"))
			"warn":
				label.add_theme_color_override("font_color", UiTheme.color("rust"))
		_column.add_child(label)
	visible = true
	# Laid out over a frame before it is placed: above the slot, else beside it.
	reset_size()
	await get_tree().process_frame
	if not visible:
		return
	var screen := get_viewport_rect().size
	var margin := float(UiTheme.constant("margin"))
	var top_left := at - Vector2(0.0, size.y + GAP)
	if top_left.y < margin:
		top_left = Vector2(at.x - size.x - GAP, maxf(at.y + UiTheme.constant("slot") - size.y, margin))
	top_left.x = clampf(top_left.x, margin, screen.x - size.x - margin)
	top_left.y = clampf(top_left.y, margin, screen.y - size.y - margin)
	global_position = top_left


## The texts shown, top to bottom (tests).
func texts() -> Array[String]:
	var out: Array[String] = []
	for label: Label in _column.get_children():
		out.append(label.text)
	return out

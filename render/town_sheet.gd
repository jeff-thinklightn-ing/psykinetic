class_name TownSheet
extends PanelContainer
## The town status sheet (decision 624, ui's side; Jeff, 2026-10-22: "a
## town status sheet... the population, the faction, the needs, hunger
## etc."): N opens it in the middle of the screen for the town whose ground
## the player stands on, a click on a town's row in the known world opens
## it for that town; Esc or N closes it. It says how the town is doing in
## the game's words, no bars, numbers only where the sim already tells the
## player them. Step 1 reads what a client has today, by key name, nothing
## stubbed: the heading "Held, a village" (the "town" message's "stage");
## who holds it (world_state "holdings", in the known world's words); its
## buildings from the "town" message ("Standing: the forge, the kitchen.
## Building: the temple, half built. Planned: the well."); its people from
## the Resident bodies the client sees while on the town's ground ("12
## people: 4 farmers, 2 hunters, a priest"; "You haven't seen who lives
## here" from elsewhere); the dole line as the town said it (Main.town_notes,
## 353); the season and the day. Economy's "town_sheet" rows (624,
## economy's side: treasury, officials, fed and hungry, needs, the mood
## stand-in, the sought, the next stage) fill in by key as they arrive,
## each absent till then (economy_lines). The look is the shared theme's
## (UiTheme, docs/ui_style.md).

const WIDTH := 980.0
## A building job's progress as a word (the "town" message's "progress").
const BEGUN := 0.34
const HALF := 0.67

## The town shown (its id, "<zone>/<key>"), "" for none.
var town := ""

var _title: Label
var _held: Label
var _people: Label
var _buildings: Label
var _dole: Label
var _economy: VBoxContainer
var _when: Label
var _none: Label


func _init() -> void:
	name = "TownSheet"
	visible = false
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _ready() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UiTheme.constant("row"))
	add_child(column)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	column.add_child(_title)
	_none = _line(column)
	_held = _line(column)
	_people = _line(column)
	_buildings = _line(column)
	_dole = _line(column)
	_economy = VBoxContainer.new()
	_economy.add_theme_constant_override("separation", UiTheme.constant("row"))
	column.add_child(_economy)
	_when = _line(column)
	_when.add_theme_color_override("font_color", UiTheme.color("text_dim"))


func _line(column: VBoxContainer) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	return label


## The sheet for town [param id] (Main's town_states key), named [param
## town_name] (the known world's place words), at [param stage] ("" before
## 591's stages); held by [param holder] (the known world's faction words,
## "" for nobody); its [param buildings] as the "town" message has them;
## [param trades] the trade of each resident body seen on its ground, or
## null from elsewhere; [param dole] the dole line as the town said it;
## [param season] and [param day] as the HUD knows them; [param sheet]
## economy's "town_sheet" message for it ({} till it comes). No town: the
## sheet says so.
func show_town(id: String, town_name: String, stage: String, holder: String, buildings: Dictionary, trades: Variant,
		dole: String, season: String, day: int, sheet: Dictionary = {}) -> void:
	town = id
	var known := not id.is_empty()
	_title.text = title_words(town_name, stage) if known else "No town"
	_none.visible = not known
	_none.text = none_words() if not known else ""
	_held.text = held_words(holder) if known else ""
	_held.visible = known and not _held.text.is_empty()
	_people.text = people_words(trades) if known else ""
	_people.visible = known
	_buildings.text = buildings_words(buildings) if known else ""
	_buildings.visible = known and not _buildings.text.is_empty()
	_dole.text = dole.strip_edges() if known else ""
	_dole.visible = known and not _dole.text.is_empty()
	for child in _economy.get_children():
		_economy.remove_child(child)  # Gone now, not at the frame's end: a second show in the same frame reads clean.
		child.queue_free()
	if known:
		for words in economy_lines(sheet):
			var line := Label.new()
			line.text = words
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_economy.add_child(line)
	_when.text = when_words(season, day) if known else ""
	_when.visible = known


## The lines shown, top to bottom, the title first (tests).
func lines_shown() -> PackedStringArray:
	var out := PackedStringArray([_title.text])
	for label: Label in [_none, _held, _people, _buildings, _dole]:
		if label.visible and not label.text.is_empty():
			out.append(label.text)
	for line: Label in _economy.get_children():
		out.append(line.text)
	if _when.visible and not _when.text.is_empty():
		out.append(_when.text)
	return out


## "Held, a village"; "Held" before the stages.
static func title_words(town_name: String, stage: String) -> String:
	var word := stage.strip_edges()
	if word.is_empty():
		return town_name
	return "%s, %s %s" % [town_name, "an" if word[0] in "aeiou" else "a", word]


## "Held by the Blood Rot." as the known world names the holder; "" for
## nobody.
static func held_words(holder: String) -> String:
	return "Held by %s." % holder if not holder.strip_edges().is_empty() else ""


## The people from the bodies seen: "12 people: 4 farmers, 2 hunters, a
## priest."; "No one is about." for none seen; the away words for null
## (the player is not on the town's ground).
static func people_words(trades: Variant) -> String:
	if not trades is Array:
		return away_words()
	var seen: Array = trades
	if seen.is_empty():
		return "No one is about."
	var counts := {}
	for trade: Variant in seen:
		var word := str(trade).strip_edges().replace("_", " ")
		if word.is_empty():
			word = "other"
		counts[word] = int(counts.get(word, 0)) + 1
	var words: Array[String] = []
	var order: Array = counts.keys()
	order.sort_custom(func(a: String, b: String) -> bool:
		return counts[a] > counts[b] if counts[a] != counts[b] else a < b)
	for word: String in order:
		var n: int = counts[word]
		words.append("%d %ss" % [n, word] if n > 1 else "%s %s" % ["an" if word[0] in "aeiou" else "a", word])
	return "%d %s: %s." % [seen.size(), "person" if seen.size() == 1 else "people", ", ".join(words)]


static func away_words() -> String:
	return "You haven't seen who lives here."


static func none_words() -> String:
	return "No town is known here."


## The buildings in words from the "town" message's dictionary (kind ->
## {state, progress?}): "Standing: the forge, the kitchen. Building: the
## temple, half built. Damaged: the walls. Planned: the well." Each group
## only when it has a kind; "" for none told.
static func buildings_words(buildings: Dictionary) -> String:
	var standing: Array[String] = []
	var building: Array[String] = []
	var damaged: Array[String] = []
	var planned: Array[String] = []
	var kinds: Array = buildings.keys()
	kinds.sort()
	for kind: Variant in kinds:
		var entry: Variant = buildings[kind]
		if not entry is Dictionary:
			continue
		var state := str(entry.get("state", ""))
		var progress := float(entry.get("progress", -1.0))
		var name := "the %s" % str(kind).replace("_", " ")
		if state == "standing":
			standing.append(name)
		elif state == "damaged":
			damaged.append("%s, being mended" % name if progress >= 0.0 else name)
		elif progress >= 0.0:
			building.append("%s, %s" % [name, progress_words(progress)])
		elif state == "planned":
			planned.append(name)
	var parts: Array[String] = []
	if not standing.is_empty():
		parts.append("Standing: %s." % ", ".join(standing))
	if not building.is_empty():
		parts.append("Building: %s." % ", ".join(building))
	if not damaged.is_empty():
		parts.append("Damaged: %s." % ", ".join(damaged))
	if not planned.is_empty():
		parts.append("Planned: %s." % ", ".join(planned))
	return " ".join(parts)


## A job's progress (0..1) as a word: begun, half built, nearly done.
static func progress_words(progress: float) -> String:
	if progress < BEGUN:
		return "begun"
	if progress < HALF:
		return "half built"
	return "nearly done"


## "Summer, day 14."
static func when_words(season: String, day: int) -> String:
	var word := season.strip_edges()
	if word.is_empty():
		return "Day %d." % day
	return "%s, day %d." % [word.capitalize(), day]


## Economy's rows (624, economy's side) from its "town_sheet" message, each
## only when its key is there: a why alone ("you don't know that town");
## "Held is uneasy." (faction {name} and the mood stand-in); "Treasury: 150
## gold."; the officials, "unpaid" after one owed a wage; "3 fed by the
## town, 2 hungry, 1 sick."; "Needs: wood, badly (bring 20); herbs, a
## little (bring 4)."; "Held seeks a smith and a healer."; "To be a
## village: 3 more people, a priest, 40 more gold."
static func economy_lines(sheet: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if sheet.is_empty():
		return out
	var why := str(sheet.get("why", "")).strip_edges()
	if not why.is_empty():
		out.append(why.left(1).to_upper() + why.substr(1))
		return out
	var town_name := str(sheet.get("name", "The town"))
	var mood := str(sheet.get("mood", "")).strip_edges()
	if not mood.is_empty():
		out.append("%s is %s." % [town_name, mood])
	if sheet.has("treasury"):
		out.append("Treasury: %d gold." % int(sheet["treasury"]))
	if sheet.get("officials") is Array and not (sheet["officials"] as Array).is_empty():
		var names: Array[String] = []
		for each: Variant in sheet["officials"]:
			if each is Dictionary:
				var who := str(each.get("name", "")).strip_edges()
				var trade := str(each.get("trade", "")).replace("_", " ")
				var words := "%s the %s" % [who, trade] if not who.is_empty() and not trade.is_empty() else (who if not who.is_empty() else "the %s" % trade)
				if each.has("paid") and not bool(each["paid"]):
					words += " (unpaid)"
				names.append(words)
		if not names.is_empty():
			out.append("Officials: %s." % ", ".join(names))
	var fed: Array[String] = []
	if sheet.has("dole"):
		fed.append("%d fed by the town" % int(sheet["dole"]))
	if sheet.has("hungry"):
		fed.append("%d hungry" % int(sheet["hungry"]))
	if sheet.has("sick"):
		fed.append("%d sick" % int(sheet["sick"]))
	if not fed.is_empty():
		var fed_words := ", ".join(fed)
		out.append(fed_words.left(1).to_upper() + fed_words.substr(1) + ".")
	if sheet.get("needs") is Array and not (sheet["needs"] as Array).is_empty():
		var needs: Array[String] = []
		for each: Variant in sheet["needs"]:
			if each is Dictionary:
				var id := str(each.get("id", "")).replace("_", " ")
				var words := "%s, %s" % [id, short_words(float(each.get("short", 0.0)))]
				if int(each.get("bring", 0)) > 0:
					words += " (bring %d)" % int(each["bring"])
				needs.append(words)
		out.append("Needs: %s." % "; ".join(needs))
	if sheet.get("sought") is Array and not (sheet["sought"] as Array).is_empty():
		var wanted: Array[String] = []
		for each: Variant in sheet["sought"]:
			var trade := str(each.get("trade", "") if each is Dictionary else each).replace("_", " ")
			if not trade.is_empty():
				wanted.append("%s %s" % ["an" if trade[0] in "aeiou" else "a", trade])
		if not wanted.is_empty():
			out.append("%s seeks %s." % [town_name, join_and(wanted)])
	if sheet.get("next_stage") is Dictionary:
		var next: Dictionary = sheet["next_stage"]
		var stage := str(next.get("stage", "")).strip_edges()
		var wants: Array[String] = []
		for each: Variant in next.get("needs", []):
			if each is Dictionary:
				wants.append(need_words(each))
		if not stage.is_empty() and not wants.is_empty():
			out.append("To be %s %s: %s." % ["an" if stage[0] in "aeiou" else "a", stage, join_and(wants)])
	if sheet.get("strain") is Dictionary:
		var strained := strain_words(sheet["strain"])
		if not strained.is_empty():
			out.append(strained)
	return out


## The strain line (649, ui's side; economy's "strain" {days, of, why}):
## "Strained 4 days of 10: hunger, the store short of food."; the days
## alone when no reason is recorded (a captive carried off adds days
## without one); nothing while the town is not strained.
static func strain_words(strain: Dictionary) -> String:
	var days := int(strain.get("days", 0))
	if days <= 0:
		return ""
	var of := int(strain.get("of", 0))
	var head := "Strained %d %s of %d" % [days, "day" if days == 1 else "days", of] if of > 0 else "Strained %d %s" % [days, "day" if days == 1 else "days"]
	var why := str(strain.get("why", ""))
	if why == "hunger":
		why = "hunger, the store short of food"
	return "%s: %s." % [head, why] if not why.is_empty() else "%s." % head


## A next-stage need {what, have, need} in words: "3 more people", "a
## priest", "40 more gold", "the walls standing".
static func need_words(need: Dictionary) -> String:
	var what := str(need.get("what", "")).replace("_", " ")
	var short := maxi(int(need.get("need", 0)) - int(need.get("have", 0)), 0)
	if what in ["people", "residents"]:
		return "%d more %s" % [short, "person" if short == 1 else "people"]
	if what in ["gold", "wood", "food", "ore"]:
		return "%d more %s" % [short, what]
	if what.begins_with("standing:") or what.begins_with("building:"):
		return "the %s standing" % what.get_slice(":", 1).replace("_", " ")
	if short > 1:
		return "%d %ss" % [short, what]
	return "%s %s" % ["an" if not what.is_empty() and what[0] in "aeiou" else "a", what]


## A shortage (0..1) as a word: badly past two thirds, some past a third, a
## little otherwise.
static func short_words(short: float) -> String:
	if short >= HALF:
		return "badly"
	if short >= BEGUN:
		return "some"
	return "a little"


## "a smith", "a smith and a healer", "a smith, a healer and a guard".
static func join_and(words: Array[String]) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, words.size() - 1)), words[words.size() - 1]]

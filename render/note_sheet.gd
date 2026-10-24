class_name NoteSheet
extends PanelContainer
## A note pinned to a door, read (decision 643, ui's side; Jeff: "a small
## note saying where they went"). npc's "notes" message lists a zone's
## notes {tile, text}, the tile the cell just outside the door where a
## player stands to read it; Main keeps them by zone. E on that cell, or
## facing it, opens this sheet with the text; it closes by Esc, when the
## player moves off the cell and the one it faces, or when the note is
## taken down (Main._update_note). Hovering the cell says "a note" at the
## cursor (Main's hover label). The look is the shared theme's (UiTheme,
## docs/ui_style.md); the text travels ready-made from the server.

const WIDTH := 520.0
## The hover word over a note's cell.
const HOVER_WORD := "a note"
const TITLE := "A note on the door"

## The cell whose note is shown, NONE for none.
var tile := Vector2i(-9999, -9999)
## The text shown, "" for none.
var text := ""

var _title: Label
var _words: Label
var _hint: Label


func _init() -> void:
	name = "NoteSheet"
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
	_title.theme_type_variation = &"Heading"
	_title.text = TITLE
	column.add_child(_title)
	_words = Label.new()
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_words)
	_hint = Label.new()
	_hint.theme_type_variation = &"Caption"
	_hint.add_theme_color_override("font_color", UiTheme.color("text_dim"))
	_hint.text = "Esc puts it back."
	column.add_child(_hint)


## The note at [param at] read: [param words] shown.
func show_note(at: Vector2i, words: String) -> void:
	tile = at
	text = words
	_words.text = words
	visible = true


func close() -> void:
	visible = false
	tile = Vector2i(-9999, -9999)
	text = ""

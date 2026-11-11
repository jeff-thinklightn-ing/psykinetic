class_name UiLine
extends Label
## The line at a window's foot that says what just happened (decision 854; the
## store Jeff approved, 11-10): done in bone ("Bought a spear for 1 gold."),
## refused in rust ("You need 2 more gold."). A click never fails silently: a
## refusal is said here and its square flashes (UiSlot.flash_refused). A held
## refusal (out of reach, asleep) stays until cleared; the words are voice's.

var refused := false


func _init() -> void:
	theme_type_variation = &"FootLine"
	autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## What was done.
func say(words: String) -> void:
	_show(words, false)


## Why a click did nothing.
func refuse(words: String) -> void:
	_show(words, true)


func clear() -> void:
	_show("", false)


func _show(words: String, was_refused: bool) -> void:
	refused = was_refused and not words.is_empty()
	theme_type_variation = &"FootLineRefused" if refused else &"FootLine"
	text = words

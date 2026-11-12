class_name UiCodeChip
extends RefCounted
## A building's code inline in a RichTextLabel (decision 886; builder's answer
## panel, approved 11-12, C:/dev/review/ui-design/builder/): a dark chip behind
## it (a no-break space inside each end), its letter dim and its figure
## bright, a hair apart, in bold, so "T1" never reads as "Ti" (decision 537's
## codes over a busy world did). The colours are the theme's CodeChip type.
## Where the server marks a code as "[T1]" in a line, add_line splits on the
## marks and draws each as a chip.

## A code as the server marks it: "[T1]", a letter or two then a figure or more.
const MARK := "\\[([A-Za-z]{1,2}[0-9]+)\\]"
## Between the letter and the figure: a hair's width that never breaks. A no-break space set at
## HAIR_SCALE of the line's size (886 amended (2): the hair space U+200A is a breaking space, so a
## wrap could leave "T" at a line's end and "1" on the next; the narrow no-break space U+202F is not
## in Alegreya Sans; and the sans bold's hair space is 0.29 em, wider than a space, 886 amended (1)).
const HAIR := "\u00a0"
## The hair's size against the line's: a no-break space is 0.165 em, so about 0.05 em of the line.
const HAIR_SCALE := 0.3
## Inside the chip's back at each end: a no-break space, its margin. The Lines highlight has no
## side padding of its own (it reached past the words' own spaces and swallowed them: "the[T1]temple").
const EDGE := "\u00a0"

static var _mark: RegEx


## [param code] ("T1") added at [param rich]'s end as a chip.
static func add_to(rich: RichTextLabel, code: String) -> void:
	var split := _split(code)
	rich.push_bgcolor(rich.get_theme_color(&"back", &"CodeChip"))
	rich.add_text(EDGE)
	rich.push_bold()
	rich.push_color(rich.get_theme_color(&"letter", &"CodeChip"))
	rich.add_text(split[0])
	rich.pop()
	rich.pop()
	rich.push_font_size(maxi(1, roundi(rich.get_theme_font_size(&"normal_font_size") * HAIR_SCALE)))
	rich.add_text(HAIR)
	rich.pop()
	rich.push_bold()
	rich.push_color(rich.get_theme_color(&"figure", &"CodeChip"))
	rich.add_text(split[1])
	rich.pop()
	rich.pop()
	rich.add_text(EDGE)
	rich.pop()


## [param line] added at [param rich]'s end, each "[T1]" in it a chip.
static func add_line(rich: RichTextLabel, line: String) -> void:
	if _mark == null:
		_mark = RegEx.create_from_string(MARK)
	var at := 0
	for found: RegExMatch in _mark.search_all(line):
		if found.get_start() > at:
			rich.add_text(line.substr(at, found.get_start() - at))
		add_to(rich, found.get_string(1))
		at = found.get_end()
	if at < line.length():
		rich.add_text(line.substr(at))


## "T1" -> ["T", "1"]: the letters, then the rest.
static func _split(code: String) -> PackedStringArray:
	var i := 0
	while i < code.length() and not code[i].is_valid_int():
		i += 1
	return PackedStringArray([code.left(i), code.substr(i)])

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
## Between the letter and the figure: a hair space, in the regular face (886 amended (1): the
## sans bold's hair space is 0.29 em, wider than its own space, so "T1" read "T 1").
const HAIR := "\u200a"
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
	rich.add_text(HAIR)
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

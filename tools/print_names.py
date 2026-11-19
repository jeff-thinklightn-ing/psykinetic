"""No server log line names a companion or carries a player's id (279 amended (3) and (4), 284 amended (2)).

The server's prints go to the box's journal. A companion's name is rolled from her player's id
(decision 293) and kept, and it is her node's name and her label, so a line naming her is a steady
stand-in for that player; a player's id is what they prove themselves with. 279 amended (3)'s first
count of such lines was made by hand and missed twelve. This reads every print in the server's
code (main.gd, sim/, net/), each call joined across its lines, and fails on:

  companion   her name: Companion._name_of, a companion card's "name", pet_name, pet.name/label
  entity      any entity by node name or label where the entity may be her (entity, other,
              target, intent_target, who, body, e, actor, occupant, victim, attacker: .name or
              .label; any .label; and her own bare name in sim/companion.gd)
  player_id   a whole player id: player_id, keeper_id, owner_id, the peer-to-id table

Each passes inside Companion.tag(...), Main.pet_tag(...) or Companion.log_name(...) (and an id
inside Standing.score(...), which reads by it and prints a number): a per-boot
"#n", her player's place in this run's order of first mention, kept in memory only. A print whose
text starts "[test]" runs only under a test flag and is not read.

World._log's lines (279 amended (4)) are printed through World.masked, which puts each companion of
the zone, by node name or label as a whole word, as her tag: in them her name and an entity's are
not read (a whole player id and a player's name still are). It fails (log_print) unless World._log
prints once, through masked(message), and if any print reads its kept lines (last_log,
recent_logs), a second printer of the message unmasked.

Lines that still name a player (284 amended (1) left them; the coordinator's (3), 2026-11-16, holds
them for Jeff and release) are counted per file in tools/print_names_budget.txt, which only falls:

  player_name     the player's name: record.name, player_name, Main._display_name(...)
  id_letters      the first letters of their id: <id>.left(n)
  player_node     a Player node's name, "Player<index>", the record's kept index: player.name,
                  (x as Player).name

A companion handed to a printer (284 amended (2)'s leftover, release's box read, 11-17): a call
that passes her id formatted raw ("folk:%s" % id, "companion:%s" % ...) or a card's name
(x["name"], x.get("name")) into a parameter its function prints raw, itself or through the
functions it hands that parameter to (by name, across the server's files), is counted per file:

  companion_arg   the call that hands her over (sim/economy.gd: stockpile.deposit and _sale)
  relay_print     the print that prints such a parameter raw (sim/stockpile.gd: deposit's line)

A parameter is printed raw when it stands bare in a print's code outside a tag; functions are
matched by name alone, so two of one name count as one. Both kinds are budgeted as the rest.

  python -B tools/print_names.py           check: exit 0, or 1 naming each line or count
  python -B tools/print_names.py --list    every line read as a hit, by rule, then the check
  python -B tools/print_names.py --counts  the budget as it stands, one line per file

A count over its line fails (a new line names a player); a count under it fails too (lower the
line in the same commit). Godot-free. PRINT_NAMES_ROOT=<folder> reads another checkout.
"""

import os
import re
import sys

ROOT = os.environ.get("PRINT_NAMES_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUDGET = os.path.join(ROOT, "tools", "print_names_budget.txt")
FOLDERS = ["sim", "net"]
FILES = ["main.gd"]

CALL = re.compile(r"(?<![\w.])(print|printerr|printraw|print_rich|push_warning|push_error)\(")
# World._log's lines (279 amended (4)): printed through World.masked, which puts each companion of the
# zone as her tag, so her name and an entity's are not read in them; an id or a player's name still is.
# Bare _log( in sim/world.gd alone (sim/companion.gd's _log is her mind log, never the journal).
LOG_CALL = re.compile(r"(?<![\w.])(?:World\.)?_log\(")
WORLD_LOG = re.compile(r"(?<![\w.])World\._log\(")
LOG_HOME = "sim/world.gd"
# The one print World._log makes, and the only one of its message: through masked().
LOG_PRINT = re.compile(r"^func _log\(message: String\) -> void:\n((?:\t.*\n|\n)*)", re.M)
RAW_LOG = re.compile(r"\b(?:last_log|recent_logs)\b")
# A tag in place of a name or id: its whole call, nested parens and all, is taken out before the rules.
# Standing.score(card, id) reads by the id and prints a number.
TAGGED = re.compile(r"(?<![\w])(?:(?:Companion\.|Main\.)?(?:pet_tag|tag|log_name)|Standing\.score)\(")

GENERIC = r"(?:entity|other|target|intent_target|who|body|e|actor|occupant|victim|attacker)"
RULES = [
	("companion", re.compile(
		r"_name_of\(|\bpet_name\b|\bpet\.(?:name|label)\b"
		r'|\b(?:companion|hers|traits|record\.companion)\s*(?:\.get\(\s*|\[\s*)"name"')),
	("entity", re.compile(r"\b%s\.(?:name|label)\b|\.label\b|\bkeeper_label\b" % GENERIC)),
	("player_id", re.compile(r"\b(?:player_id|keeper_id|owner_id)\b|\b_peer_ids\s*(?:\[|\.get\()")),
]
SELF_NAME = re.compile(r"(?<![\w.])name\b(?!\s*=)")  # Her own node name, in sim/companion.gd.
# A companion handed to a printer (284 amended (2)'s leftover): her id formatted raw, or a card's name.
HANDED = re.compile(r'"(?:folk|companion):%[sd]"\s*%|\bwho\s*(?:\[\s*|\.get\(\s*)"name"')
MASKED = re.compile(r"(?<![\w])(?:World\.)?masked\(")
# A call that only looks the id up (_players.get(_peer_of(id))): any call but str(), taken out for the id rule.
# World.masked is no lookup: it hides a companion of the printing zone, never a player's id.
LOOKUP = re.compile(r"(?<![\w.])(?!str\(|_peer_ids\.get\(|(?:World\.)?masked\()(?:\w+\.)*\w+\(")
NEVER = re.compile(r"(?!)")  # Takes nothing out.
FUNC = re.compile(r"^(?:static\s+)?func\s+(\w+)\(", re.M)
ANY_CALL = re.compile(r"(?<![\w.])((?:\w+\.)*)(\w+)\(")  # A call: its receiver (if any) and name.
BUDGETED = [
	("player_name", re.compile(r"\brecord\.name\b|\bplayer_name\w*\b|\b_display_name\(")),
	("id_letters", re.compile(r"\.left\(\s*\d+\s*\)")),
	("player_node", re.compile(r"\bplayer\.name\b|\(\s*\w+\s+as\s+Player\s*\)\.name\b")),
	("companion_arg", None),  # Counted by handed(), not by a pattern.
	("id_arg", None),
	("relay_print", None),
]


def server_files():
	out = [f for f in FILES if os.path.exists(os.path.join(ROOT, f))]
	for folder in FOLDERS:
		for base, _, names in os.walk(os.path.join(ROOT, folder)):
			for name in sorted(names):
				if name.endswith(".gd"):
					out.append(os.path.relpath(os.path.join(base, name), ROOT).replace(os.sep, "/"))
	return sorted(out)


def _string_end(text, i):
	"""Index just past the string literal starting at text[i] (a quote)."""
	q = text[i]
	if text.startswith(q * 3, i):
		j = text.find(q * 3, i + 3)
		return len(text) if j < 0 else j + 3
	j = i + 1
	while j < len(text) and text[j] != q and text[j] != "\n":
		j += 2 if text[j] == "\\" else 1
	return j + 1


def _in_code(text, start):
	"""Whether text[start] is code: not in a comment or a string on its line."""
	i = text.rfind("\n", 0, start) + 1
	while i < start:
		c = text[i]
		if c == "#":
			return False
		if c in "\"'":
			i = _string_end(text, i)
			if i > start:
				return False
			continue
		i += 1
	return True


def calls(text, call=CALL):
	"""[(line number, code with each string kept, first string's text)] of every call [call] finds."""
	out = []
	for m in call.finditer(text):
		if not _in_code(text, m.start()):
			continue
		depth, i, code, first = 1, m.end(), [], None
		while i < len(text) and depth > 0:
			c = text[i]
			if c in "\"'":
				j = _string_end(text, i)
				if first is None:
					first = text[i:j].strip("\"'")
				code.append(text[i:j])
				i = j
				continue
			if c == "#":
				i = text.find("\n", i)
				if i < 0:
					break
				continue
			depth += c == "("
			depth -= c == ")"
			code.append(" " if c in "\n\t\\" else c)
			i += 1
		out.append((text.count("\n", 0, m.start()) + 1, "".join(code), first or ""))
	return out


def _untagged(code, tagged=None):
	"""The call's code with each tag call (and all inside it) taken out."""
	while True:
		m = (tagged or TAGGED).search(code)
		if not m:
			return code
		depth, i = 1, m.end()
		while i < len(code) and depth > 0:
			depth += code[i] == "("
			depth -= code[i] == ")"
			i += 1
		code = code[:m.start()] + "#" + code[i:]


def _blanked(code):
	"""Strings emptied, so a word inside a line's text is never read as code; a "name" key kept."""
	return re.sub(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'',
		lambda m: m.group(0) if m.group(0) == '"name"' else '""', code)


def functions(text):
	"""[(name, [parameter names], body, first line of the body)] of each top-level func."""
	out = []
	for m in FUNC.finditer(text):
		depth, i = 1, m.end()
		while i < len(text) and depth > 0:
			depth += text[i] in "([{"
			depth -= text[i] in ")]}"
			i += 1
		params = [re.match(r"\s*(\w*)", each).group(1) for each in split_args(text[m.end():i - 1])]
		start = text.find("\n", i) + 1
		end = re.compile(r"^[^\s#]", re.M).search(text, start)
		out.append((m.group(1), [each for each in params if each], text[start:end.start() if end else len(text)],
			text.count("\n", 0, start) + 1))
	return out


def split_args(code):
	"""A call's arguments, split at its top-level commas (strings and brackets kept whole)."""
	out, depth, i, last = [], 0, 0, 0
	while i < len(code):
		c = code[i]
		if c in "\"'":
			i = _string_end(code, i)
			continue
		depth += c in "([{"
		depth -= c in ")]}"
		if c == "," and depth == 0:
			out.append(code[last:i])
			last = i + 1
		i += 1
	out.append(code[last:])
	return [each.strip() for each in out]


def _bare(word, code):
	"""Whether [word] stands as a bare name in [code] (strings blanked): not a member, not a call, and
	not read through one of its own (id.left(8), entity.name: the other rules read those)."""
	return re.search(r"(?<![\w.])%s\b(?!\s*[(.\[])" % re.escape(word), code) is not None


def _shown(word, code):
	"""Whether [word] is printed raw in a print's [code]: bare, and not only tested (`by != ""`, `if by`)."""
	tested = r"\b(?:if|not|elif)\s+%s\b|%s\s*(?:[!=]=|[<>]=?)" % ((re.escape(word),) * 2)
	return _bare(word, re.sub(tested, "#", code))


def handed():
	"""(the calls that hand a companion to a printer, the prints that print her), each [(file, line,
	code)]: 284 amended (2)'s leftover, followed parameter by parameter through the functions."""
	funcs = {}  # (file, name): (params, first line, [(callee keys, line, args)], [(line, code, blanked code)] of its prints)
	bodies = []
	files = server_files()
	by_base = {}
	for f in files:
		by_base.setdefault(os.path.splitext(os.path.basename(f))[0].lower(), []).append(f)
	for f in files:
		text = open(os.path.join(ROOT, f), encoding="utf-8").read()
		for name, params, body, line in functions(text):
			bodies.append((f, name, params, body, line))
	names = {}
	for f, name, _, _, _ in bodies:
		names.setdefault(name, []).append(f)

	def callees(f, receiver, name):
		# A bare call is the file's own function; "stockpile.deposit" the one in stockpile.gd where a
		# file of the receiver's name has it; else every server function of that name.
		where = names.get(name, [])
		if not receiver:
			return [(f, name)] if f in where else []
		mine = [each for each in by_base.get(receiver.lstrip("_").lower(), []) if each in where]
		return [(each, name) for each in (mine or where)]

	for f, name, params, body, line in bodies:
		found = [m for m in ANY_CALL.finditer(body) if _in_code(body, m.start())]
		made = [(callees(f, m.group(1).rstrip(".").split(".")[-1] if m.group(1) else "", m.group(2)), l, split_args(c))
			for m, (l, c, _) in zip(found, calls(body, ANY_CALL))]
		# World.masked puts each companion of the zone as her tag (279 amended (4)): a name inside it is not
		# hers. A player's id goes through it raw, so the id is followed in the print as written (the
		# coordinator's ruling, 11-19).
		shown = [(l, c, _blanked(_untagged(_untagged(c), MASKED)), _blanked(_untagged(c)))
			for l, c, s in calls(body) if not s.startswith("[test]")]
		funcs[(f, name)] = (params, line, made, shown)

	def handed_bare(made, param, slots_of, lookups=False):
		# The (callee, slot) pairs [param] is handed to bare, among the slots [slots_of] gives each callee;
		# with [lookups], an argument that only looks it up (_players.get(_peer_of(id))) hands nothing on.
		for keys, _, args in made:
			for key in keys:
				for slot in slots_of.get(key, ()):
					if slot < len(args) and _bare(param, _blanked(_untagged(_untagged(args[slot]), LOOKUP if lookups else NEVER))):
						yield key, slot

	def follow(col, forms):
		# The walk for one kind: shown's column [col] is the prints as it reads them.
		# The slots each function prints raw: itself, or by handing them on to such a slot (a fixed point).
		printed = {}
		for key, (params, _, _, shown) in funcs.items():
			for code in [each[col] for each in shown]:
				printed.setdefault(key, set()).update(i for i, p in enumerate(params) if _shown(p, code))
		changed = True
		while changed:
			changed = False
			for key, (params, _, made, _) in funcs.items():
				for i, p in enumerate(params):
					if i not in printed.get(key, ()) and any(handed_bare(made, p, printed, col == 3)):
						printed.setdefault(key, set()).add(i)
						changed = True
		# The calls that hand her into a printed slot; then onward, from those slots alone.
		# A whole player id handed the same way is counted apart (id_arg): 279 amended (3)'s rule, met
		# through a printer (Economy.pay_loan's "debt:<id>", 11-17).
		reach = {}
		for (f, _), (params, line, made, _) in funcs.items():
			for keys, l, args in made:
				hit = {}
				for key in keys:
					for found, form in forms:
						got = [slot for slot in printed.get(key, ()) if slot < len(args) and form(args[slot])]
						if got:
							hit[id(found)] = found
							reach.setdefault(key, set()).update(got)
				for found in hit.values():
					found.append((f, line + l - 1, "%s(%s)" % (keys[0][1], ", ".join(args))))
		changed = True
		while changed:
			changed = False
			for key, (params, _, made, _) in funcs.items():
				for i in list(reach.get(key, ())):
					if i >= len(params):
						continue
					for callee, slot in list(handed_bare(made, params[i], printed, col == 3)):
						if slot not in reach.setdefault(callee, set()):
							reach[callee].add(slot)
							changed = True
		relays = []
		for (f, name), (params, line, _, shown) in funcs.items():
			for l, c, code in [(each[0], each[1], each[col]) for each in shown]:
				if any(i < len(params) and _shown(params[i], code) for i in reach.get((f, name), ())):
					relays.append((f, line + l - 1, c))
		return relays

	whole_id = dict(RULES)["player_id"]
	gave, ids = [], []
	relays = follow(2, [(gave, lambda arg: HANDED.search(_untagged(arg)))])
	relays += follow(3, [(ids, lambda arg: whole_id.search(_blanked(_untagged(_untagged(arg), LOOKUP))))])
	return sorted(gave), sorted(ids), sorted(set(relays))


def scan():
	"""(hits [(file, line, rule, code)], counts {file: {rule: n}})."""
	hits, counts = [], {}
	for f in server_files():
		text = open(os.path.join(ROOT, f), encoding="utf-8").read()
		logged = [(line, code, first, True) for line, code, first in calls(text, LOG_CALL if f == LOG_HOME else WORLD_LOG)]
		for line, code, first, masked in [(l, c, s, False) for l, c, s in calls(text)] + logged:
			if first.startswith("[test]"):
				continue
			bare = _untagged(code)
			blank = _blanked(bare)
			for rule, pattern in RULES:
				if masked and rule != "player_id":
					continue  # World.masked puts her as her tag; an entity's name is hers only if she is it.
				if pattern.search(blank):
					hits.append((f, line, rule, code))
			if f == "sim/companion.gd" and not masked and SELF_NAME.search(blank):
				hits.append((f, line, "entity", code))
			for rule, pattern in BUDGETED:
				if pattern is None:
					continue
				if masked and rule == "player_node":
					continue  # A Player's node among World._log's entity names: Jeff's pick, as the rest.
				if pattern.search(blank):
					counts.setdefault(f, {}).setdefault(rule, 0)
					counts[f][rule] += 1
					hits.append((f, line, rule, code))
		if not masked_print_ok(f, text):
			hits.append((f, 0, "log_print", "World._log prints its message only through masked(message), once; "
				"no other print reads last_log or recent_logs"))
	gave, ids, relays = handed()
	for rule, found in (("companion_arg", gave), ("id_arg", ids), ("relay_print", relays)):
		for f, line, code in found:
			counts.setdefault(f, {}).setdefault(rule, 0)
			counts[f][rule] += 1
			hits.append((f, line, rule, code))
	return hits, counts


def masked_print_ok(f, text):
	"""World._log prints once, through masked(message); no print anywhere reads its kept lines."""
	for line, code, first in calls(text):
		if RAW_LOG.search(_blanked(code)) and not first.startswith("[test]"):
			return False
	if f != LOG_HOME:
		return True
	m = LOG_PRINT.search(text)
	if not m:
		return False
	body = m.group(1)
	printed = calls(body)
	return len(printed) == 1 and "masked(message)" in printed[0][1]


def read_budget():
	budget = {}
	if not os.path.exists(BUDGET):
		return budget
	for raw in open(BUDGET, encoding="utf-8"):
		line = raw.split("#", 1)[0].split()
		if len(line) == 3:
			budget.setdefault(line[0], {})[line[1]] = int(line[2])
	return budget


def main(argv):
	# A line holding a character the pipe's code page lacks (cp1252 under a Start-Process landing,
	# PYTHONIOENCODING unset) is shown with a stand-in, never a crash that hides which line it was.
	sys.stdout.reconfigure(errors="replace")
	hits, counts = scan()
	if "--counts" in argv:
		for f in sorted(counts):
			for rule, _ in BUDGETED:
				if counts[f].get(rule):
					print("%s %s %d" % (f, rule, counts[f][rule]))
		return 0
	if "--list" in argv:
		for f, line, rule, code in hits:
			print("%s:%d %s: %s" % (f, line, rule, code[:160]))
	budget = read_budget()
	failed = []
	for f, line, rule, code in hits:
		if rule == "log_print":
			failed.append("%s: %s (279 amended (4))" % (f, code))
		elif rule in dict(RULES) or rule == "entity":
			failed.append("%s:%d names %s: print(%s" % (f, line, {"companion": "a companion", "entity": "an entity by node name or label (her, if it is her: Companion.log_name)", "player_id": "a whole player id (Companion.tag)"}[rule], code[:140]))
	for f in sorted(set(counts) | set(budget)):
		for rule, _ in BUDGETED:
			have, allowed = counts.get(f, {}).get(rule, 0), budget.get(f, {}).get(rule, 0)
			if have > allowed:
				failed.append("%s: %d %s lines, over its line of %d in tools/print_names_budget.txt (a new line names a player)" % (f, have, rule, allowed))
			elif have < allowed:
				failed.append("%s: %d %s lines, under its line of %d: lower it in tools/print_names_budget.txt in this commit" % (f, have, rule, allowed))
	for line in failed:
		print(line)
	if failed:
		print("print_names: %d problem(s) (279 amended (3), 284 amended (2))" % len(failed))
		return 1
	print("print_names: no server print names a companion or carries a player id; the player-name lines within their budget")
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))

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
BUDGETED = [
	("player_name", re.compile(r"\brecord\.name\b|\bplayer_name\w*\b|\b_display_name\(")),
	("id_letters", re.compile(r"\.left\(\s*\d+\s*\)")),
	("player_node", re.compile(r"\bplayer\.name\b|\(\s*\w+\s+as\s+Player\s*\)\.name\b")),
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


def _untagged(code):
	"""The call's code with each tag call (and all inside it) taken out."""
	while True:
		m = TAGGED.search(code)
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
				if masked and rule == "player_node":
					continue  # A Player's node among World._log's entity names: Jeff's pick, as the rest.
				if pattern.search(blank):
					counts.setdefault(f, {}).setdefault(rule, 0)
					counts[f][rule] += 1
					hits.append((f, line, rule, code))
		if not masked_print_ok(f, text):
			hits.append((f, 0, "log_print", "World._log prints its message only through masked(message), once; "
				"no other print reads last_log or recent_logs"))
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

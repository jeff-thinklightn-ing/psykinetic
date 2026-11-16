"""The lists every tree adds a name to, one name a line, sorted (decision 944).

Client3D's vars sorted for swap_room (client3d/room_fields.gd's VIEW and ROOM) and the
protocol's names (net/net.gd's MESSAGE_KINDS and SUBCLASS_REPLICATED) were written many
names to a line, or all on one line, each new name put at the end: two takes that each
added one edited the same line, and the second to land met a conflict at its rebase and
went back to the end of the queue (sound-940 after 38 minutes on the lock, 2026-11-15
16:23). One name a line, in order, puts two adds on lines of their own, and git merges them.

  python -B tools/list_lines.py          check: exit 0, or 1 naming each list out of shape
  python -B tools/list_lines.py --fix    rewrite each list one name a line, sorted, no repeats; a file
                                         stopped in a rebase with a conflict in its lists' names alone
                                         gets them merged three ways from the index's stages: each side's
                                         adds and removals kept (exit 2 for any other conflict in it)

Order is by the name's text (the quoted string, its & aside). A comment after a name is kept
on its line. The values, and so Net.protocol(), are unchanged by --fix: MESSAGE_KINDS and
SUBCLASS_REPLICATED were already in order.
"""

import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LISTS = [
	("client3d/room_fields.gd", "VIEW"),
	("client3d/room_fields.gd", "ROOM"),
	("net/net.gd", "MESSAGE_KINDS"),
	("net/net.gd", "SUBCLASS_REPLICATED"),
]
ENTRY = re.compile(r'(&?"[^"]*")\s*,?\s*(#.*)?')


def _span(lines, name):
	"""(first, last) line indices of `const <name> ... = [` through its closing `]`, or None."""
	head = re.compile(r"^const %s\b[^=]*=\s*\[" % re.escape(name))
	for i, line in enumerate(lines):
		if head.match(line):
			depth = 0
			for j in range(i, len(lines)):
				code = lines[j].split("#", 1)[0]
				depth += code.count("[") - code.count("]")
				if depth <= 0 and j >= i:
					return i, j
			return None
	return None


def _entries(lines, first, last):
	"""[(value, comment)] in the list as written."""
	text = []
	for j in range(first, last + 1):
		line = lines[j]
		if j == first:
			line = line.split("=", 1)[1].split("[", 1)[1]  # After "= [", not the type's "Array[".
		comment = ""
		if "#" in line.split('"')[-1]:
			line, comment = line.rsplit("#", 1)
			comment = "#" + comment.rstrip("\n")
		if j == last:
			line = line.rsplit("]", 1)[0]
		names = re.findall(r'&?"[^"]*"', line)
		for k, value in enumerate(names):
			text.append((value, comment.strip() if k == len(names) - 1 else ""))
	return text


def _key(value):
	return value.lstrip("&").strip('"')


def _shaped(lines, first, last, entries):
	"""Whether the list is one name a line, in order, with no repeats."""
	values = [value for value, _ in entries]
	if values != sorted(values, key=_key) or len(set(map(_key, values))) != len(values):
		return False
	if last - first != len(entries) + 1:
		return False
	for k in range(len(entries)):
		line = lines[first + 1 + k].strip()
		if not ENTRY.fullmatch(line) or len(re.findall(r'&?"[^"]*"', line)) != 1:
			return False
	return lines[last].strip() == "]"


def _written(head, entries):
	out = [head.rstrip() + "\n"]
	seen = set()
	for value, comment in sorted(entries, key=lambda e: _key(e[0])):
		if _key(value) in seen:
			continue
		seen.add(_key(value))
		out.append("\t%s,%s\n" % (value, ("  " + comment) if comment else ""))
	out.append("]\n")
	return out


def _sides(lines):
	"""A file stopped in a merge or rebase, as (ours, theirs) line lists; None with no conflict markers."""
	if not any(line.startswith("<<<<<<< ") for line in lines):
		return None
	ours, theirs, side = [], [], None
	for line in lines:
		if line.startswith("<<<<<<< "):
			side = "ours"
		elif line.startswith("||||||| ") and side == "ours":
			side = "base"
		elif line.startswith("=======") and side in ("ours", "base"):
			side = "theirs"
		elif line.startswith(">>>>>>> ") and side == "theirs":
			side = None
		elif side is None:
			ours.append(line)
			theirs.append(line)
		elif side == "ours":
			ours.append(line)
		elif side == "theirs":
			theirs.append(line)
	return ours, theirs


def _skeleton(lines, names):
	"""The file with each named list's names taken out: what must agree for a merge of names alone."""
	out = list(lines)
	for name in names:
		span = _span(out, name)
		if span is not None:
			out[span[0]:span[1] + 1] = ["<list %s>\n" % name]
	return out


def _resolve(path, full, names):
	"""A conflict in [path] only in its lists' names: written as ours (a rebase's ours is main's) with each
	list merged three ways against the base (git's stage 1): a name either side added kept, one either side
	removed left out. Anything else in conflict: refused, by hand. True if written."""
	with open(full, encoding="utf-8", newline="") as f:
		lines = f.readlines()
	sides = _sides(lines)
	if sides is None:
		return True
	ours, theirs = sides
	if _skeleton(ours, names) != _skeleton(theirs, names):
		print("list_lines: %s: a conflict outside its lists (%s): resolve it by hand" % (path, ", ".join(names)))
		return False
	# Each side's names come from its whole file in the index (stages 1 base, 2 ours, 3 theirs): the sides
	# rebuilt from the markers are mixed, since git takes the part of a list only one side rewrote from
	# that side and marks only the rest.
	stages = [_stage(path, k) for k in (1, 2, 3)]
	three = all(s is not None for s in stages) and all(_span(s, name) is not None for s in stages for name in names)
	for name in names:
		mine = _span(ours, name)
		if three:
			base_entries, ours_entries, theirs_entries = [_entries(s, *_span(s, name)) for s in stages]
			ours_names = {_key(v) for v, _ in ours_entries}
			theirs_names = {_key(v) for v, _ in theirs_entries}
			# A name either side took out of the base stays out (ui-design's take removing
			# &"_hp_bar_shader" while 944 rewrote the list); one either side added stays.
			gone = {_key(v) for v, _ in base_entries if _key(v) not in ours_names or _key(v) not in theirs_names}
			entries = [(v, c) for v, c in ours_entries + theirs_entries if _key(v) not in gone]
		else:
			entries = _entries(ours, *mine) + _entries(theirs, *_span(theirs, name))
		head = ours[mine[0]].split("=", 1)[0].rstrip() + " = ["
		ours[mine[0]:mine[1] + 1] = _written(head, entries)
	with open(full, "w", encoding="utf-8", newline="") as f:
		f.writelines(ours)
	print("list_lines: %s: its conflict was in its lists' names alone: %s" % (path,
		"merged three ways (the index's base, ours and theirs): each side's adds and removals kept" if three
		else "no stages in the index: both sides' names kept; a name either side removed is back, take it out by hand"))
	return True


def _stage(path, k):
	"""[path] as the index holds it at stage [k] in a stopped merge or rebase (1 base, 2 ours, 3 theirs); None if none."""
	try:
		out = subprocess.run(["git", "-C", ROOT, "show", ":%d:%s" % (k, path)], capture_output=True, check=True)
	except (OSError, subprocess.CalledProcessError):
		return None
	return out.stdout.decode("utf-8").splitlines(keepends=True)


def main(argv):
	fix = "--fix" in argv
	bad = []
	if fix:
		files = {}
		for path, name in LISTS:
			files.setdefault(path, []).append(name)
		for path, names in files.items():
			if not _resolve(path, os.path.join(ROOT, path), names):
				return 2
	for path, name in LISTS:
		full = os.path.join(ROOT, path)
		with open(full, encoding="utf-8", newline="") as f:
			lines = f.readlines()
		span = _span(lines, name)
		if span is None:
			bad.append("%s: no list %s" % (path, name))
			continue
		first, last = span
		entries = _entries(lines, first, last)
		if _shaped(lines, first, last, entries):
			continue
		if not fix:
			values = [_key(v) for v, _ in entries]
			why = "names out of order" if values != sorted(values) else "a repeated name" if len(set(values)) != len(values) else "more than one name on a line"
			bad.append("%s: %s (%s)" % (path, name, why))
			continue
		head = lines[first].split("=", 1)[0].rstrip() + " = ["
		lines[first:last + 1] = _written(head, entries)
		with open(full, "w", encoding="utf-8", newline="") as f:
			f.writelines(lines)
		print("list_lines: %s %s written one name a line, sorted (%d names)" % (path, name, len(set(_key(v) for v, _ in entries))))
	if bad:
		for line in bad:
			print("list_lines: " + line)
		print("list_lines: one name a line, in order (decision 944): python -B tools/list_lines.py --fix, then commit")
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))

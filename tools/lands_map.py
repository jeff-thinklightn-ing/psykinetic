"""Draws the lands from levels/world_plane.json (decision 650 amended):

    python -I tools/lands_map.py [--out DIR]

writes DIR/lands.png and DIR/README.md (DIR: C:/dev/review/lands). Each
outdoor level with an origin on the plane is stamped there from its
layout.png in its own colours (forest, water, cleared ground, roads), its
name on it; the links between them as dots, those down into a level with no
place on the plane (a barrow, the halls) as a square named for where it
goes; each place lore names that no level holds yet as an outline (solid
agreed, dashed draft); the landmarks as triangles; the named lands as faint
outlines; a scale and the compass. Run it after any change to the plane, so
the picture never drifts from the data. Reads only the repository's files.
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLANE = os.path.join(ROOT, "levels", "world_plane.json")
OUT = "C:/dev/review/lands"
# Pixels a cell, and the margin round everything drawn (cells).
SCALE = 1.5
MARGIN = 40
FOREST = (34, 70, 40)
BACKGROUND = (226, 222, 210)
PAPER = (245, 243, 238)
INK = (25, 25, 25)
AGREED = (170, 30, 30)
DRAFT = (200, 110, 20)
REGION = (90, 90, 140)
LINK = (255, 255, 255)
BELOW = (60, 40, 120)


def font(size, bold=False):
	for name in (("segoeuib.ttf" if bold else "segoeui.ttf"), "arial.ttf"):
		try:
			return ImageFont.truetype(os.path.join("C:/Windows/Fonts", name), size)
		except OSError:
			continue
	return ImageFont.load_default()


def level_config(name):
	path = os.path.join(ROOT, "levels", name, "level.json")
	if not os.path.exists(path):
		return {}
	with open(path, encoding="utf-8") as f:
		return json.load(f)


def level_layout(name):
	path = os.path.join(ROOT, "levels", name, "layout.png")
	return Image.open(path).convert("RGB") if os.path.exists(path) else None


def rect_of(at, size):
	return [at[0], at[1], at[0] + size[0], at[1] + size[1]]


def main():
	parser = argparse.ArgumentParser()
	parser.add_argument("--out", default=OUT)
	args = parser.parse_args()
	with open(PLANE, encoding="utf-8") as f:
		plane = json.load(f)
	zones = {}
	for name, zone in plane.get("zones", {}).items():
		layout = level_layout(name)
		if layout is None:
			print("[lands] %s has an origin but no layout.png" % name)
			continue
		size = ((layout.width + 1) // 2, (layout.height + 1) // 2)
		zones[name] = {"origin": zone["origin"], "size": size, "layout": layout, "config": level_config(name), "height": zone.get("height", 0.0)}
	places = plane.get("places", [])
	regions = plane.get("regions", [])
	marks = plane.get("landmarks", [])
	# What is drawn: every level, place and landmark (the regions clipped to it).
	boxes = [rect_of(z["origin"], z["size"]) for z in zones.values()]
	boxes += [[p["rect"][0], p["rect"][1], p["rect"][0] + p["rect"][2], p["rect"][1] + p["rect"][3]] for p in places]
	boxes += [[m["at"][0], m["at"][1], m["at"][0] + 1, m["at"][1] + 1] for m in marks]
	left = min(b[0] for b in boxes) - MARGIN
	top = min(b[1] for b in boxes) - MARGIN
	right = max(b[2] for b in boxes) + MARGIN
	bottom = max(b[3] for b in boxes) + MARGIN
	head = 70
	width = int((right - left) * SCALE)
	height = int((bottom - top) * SCALE)
	image = Image.new("RGB", (width, height + head + 40), PAPER)
	draw = ImageDraw.Draw(image)
	draw.rectangle([0, head, width, head + height], fill=BACKGROUND)

	def to_px(x, y):
		return ((x - left) * SCALE, (y - top) * SCALE + head)

	small = font(14)
	label = font(17)
	big = font(20, True)
	# The named lands first, faint, under everything.
	for region in regions:
		x, y, w, h = region["rect"]
		a = to_px(max(x, left), max(y, top))
		b = to_px(min(x + w, right), min(y + h, bottom))
		draw.rectangle([a, b], outline=REGION, width=2)
		text = region["name"] + ("" if region.get("status") == "agreed" else " (draft)")
		draw.text((a[0] + 6, a[1] + 4), text, font=big, fill=REGION)
	# The levels, stamped cell by cell.
	for name, zone in zones.items():
		ox, oy = zone["origin"]
		layout = zone["layout"]
		for cy in range(zone["size"][1]):
			for cx in range(zone["size"][0]):
				colour = layout.getpixel((cx * 2, cy * 2))
				if colour == (0, 0, 0):
					colour = FOREST
				elif colour in ((0, 255, 255), (255, 0, 255)):
					colour = (230, 230, 230)
				a = to_px(ox + cx, oy + cy)
				draw.rectangle([a, (a[0] + SCALE, a[1] + SCALE)], fill=colour)
		a = to_px(ox, oy)
		b = to_px(ox + zone["size"][0], oy + zone["size"][1])
		draw.rectangle([a, b], outline=INK, width=1)
	# The links: dots where two levels on the plane meet; a square for a way
	# down to a level with no place on it.
	below = []
	for name, zone in zones.items():
		for link in zone["config"].get("links", []):
			at = (zone["origin"][0] + int(link["at"][0]), zone["origin"][1] + int(link["at"][1]))
			c = to_px(at[0] + 0.5, at[1] + 0.5)
			target = str(link.get("to_map", ""))
			if target in zones:
				draw.ellipse([c[0] - 3, c[1] - 3, c[0] + 3, c[1] + 3], fill=LINK, outline=INK)
			else:
				named = level_config(target).get("name", target)
				draw.rectangle([c[0] - 4, c[1] - 4, c[0] + 4, c[1] + 4], fill=BELOW, outline=LINK)
				below.append((name, link["at"], target, named, bool(link.get("closed", False))))
				draw.text((c[0] + 6, c[1] - 8), named + (" (closed)" if link.get("closed") else ""), font=small, fill=INK)
	# The levels' names.
	for name, zone in zones.items():
		a = to_px(zone["origin"][0], zone["origin"][1])
		text = "%s (%s)" % (zone["config"].get("name", name), name)
		box = draw.textbbox((a[0] + 4, a[1] + 3), text, font=label)
		draw.rectangle(box, fill=PAPER)
		draw.text((a[0] + 4, a[1] + 3), text, font=label, fill=INK)
	# The places lore names that no level holds yet.
	for place in places:
		x, y, w, h = place["rect"]
		colour = AGREED if place.get("status") == "agreed" else DRAFT
		a = to_px(x, y)
		b = to_px(x + w, y + h)
		if place.get("kind") == "ring":
			draw.ellipse([a, b], outline=colour, width=3)
		elif place.get("status") == "agreed":
			draw.rectangle([a, b], outline=colour, width=3)
		else:
			dashed(draw, a, b, colour)
		text = place["name"] + ("" if place.get("status") == "agreed" else " (draft)")
		draw.text((a[0] + 4, a[1] + 3), text, font=label, fill=colour)
	# The landmarks.
	for mark in marks:
		c = to_px(mark["at"][0] + 0.5, mark["at"][1] + 0.5)
		draw.polygon([(c[0], c[1] - 10), (c[0] - 8, c[1] + 6), (c[0] + 8, c[1] + 6)], fill=INK, outline=PAPER)
		draw.text((c[0] + 10, c[1] + 4), "%s (landmark)" % mark["id"].replace("_", " "), font=small, fill=INK)
	# The title, the scale and the compass.
	draw.text((12, 10), "The lands, from levels/world_plane.json (decision 650 amended)", font=font(26, True), fill=INK)
	draw.text((12, 42), "Solid red outline: agreed, no level yet. Dashed orange: a draft to move. White dots: links between levels. Purple squares: ways below or on.", font=small, fill=INK)
	sx, sy = 20, head + height + 18
	draw.line([(sx, sy), (sx + 100 * SCALE, sy)], fill=INK, width=3)
	draw.text((sx + 100 * SCALE + 8, sy - 9), "100 cells (a cell a metre)", font=small, fill=INK)
	nx, ny = width - 40, head + 20
	draw.polygon([(nx, ny), (nx - 9, ny + 26), (nx + 9, ny + 26)], fill=INK)
	draw.text((nx - 6, ny + 28), "N", font=label, fill=INK)
	os.makedirs(args.out, exist_ok=True)
	image.save(os.path.join(args.out, "lands.png"))
	with open(os.path.join(args.out, "README.md"), "w", encoding="utf-8", newline="\n") as f:
		f.write(readme(zones, places, regions, marks, below, (left, top, right, bottom)))
	print("[lands] %s: %d levels, %d places, %d landmarks, %d regions, %d x %d px" % (
		os.path.join(args.out, "lands.png"), len(zones), len(places), len(marks), len(regions), image.width, image.height))


def dashed(draw, a, b, colour, dash=10):
	for (x0, y0), (x1, y1) in [((a[0], a[1]), (b[0], a[1])), ((b[0], a[1]), (b[0], b[1])), ((b[0], b[1]), (a[0], b[1])), ((a[0], b[1]), (a[0], a[1]))]:
		length = max(abs(x1 - x0), abs(y1 - y0))
		steps = int(length // dash)
		for i in range(0, steps, 2):
			t0, t1 = i / max(steps, 1), min(i + 1, steps) / max(steps, 1)
			draw.line([(x0 + (x1 - x0) * t0, y0 + (y1 - y0) * t0), (x0 + (x1 - x0) * t1, y0 + (y1 - y0) * t1)], fill=colour, width=3)


def readme(zones, places, regions, marks, below, bounds):
	out = ["# The lands", "",
		"`lands.png` is drawn by `tools/lands_map.py` from `levels/world_plane.json` (decision 650 amended),",
		"the one truth of where everything in the region lies. Coordinates are world cells (a cell a metre),",
		"x east, y south; a level's origin is the world cell of its cell (0, 0). Shown: x %d..%d, y %d..%d." % (bounds[0], bounds[2], bounds[1], bounds[3]),
		"", "## Levels (built)", ""]
	for name, zone in zones.items():
		out.append("- **%s** (`%s`): origin (%d, %d), %d x %d cells, ground %+.2f m." % (
			zone["config"].get("name", name), name, zone["origin"][0], zone["origin"][1], zone["size"][0], zone["size"][1], zone["height"]))
	out += ["", "## Ways below or on (a level with no place on the plane)", ""]
	for name, at, target, named, closed in below:
		out.append("- from %s at (%d, %d): **%s** (`%s`)%s." % (name, int(at[0]), int(at[1]), named, target, ", closed" if closed else ""))
	out += ["", "## Places no level holds yet", ""]
	for place in places:
		x, y, w, h = place["rect"]
		out.append("- **%s** (`%s`, %s): x %d..%d, y %d..%d. %s" % (place["name"], place["id"], place.get("status", "draft"), x, x + w, y, y + h, place.get("about", "")))
	out += ["", "## Landmarks (seen far off)", ""]
	for mark in marks:
		out.append("- **%s**: at (%d, %d), %s, standing on %.2f m." % (mark["id"], mark["at"][0], mark["at"][1], mark["slot"], mark.get("base", 0.0)))
	out += ["", "## Named lands", ""]
	for region in regions:
		x, y, w, h = region["rect"]
		out.append("- **%s** (%s): x %d..%d, y %d..%d. %s" % (region["name"], region.get("status", "draft"), x, x + w, y, y + h, region.get("about", "")))
	out += ["", "To move something: change its entry in `levels/world_plane.json` (a level's origin also moves its",
		"links' far ends, so a level's origin is maps' to change), then run `python -I tools/lands_map.py`.", ""]
	return "\n".join(out)


if __name__ == "__main__":
	sys.exit(main())

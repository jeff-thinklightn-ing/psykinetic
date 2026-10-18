# The goblin's marks (decision 494), drawn once onto a mask over its paint texture's UVs: a mark
# a channel, so a shader draws one or none by seed. Red: a scar across the left eye. Green: white
# stripes on both cheeks. Blue: a red hand over the mouth. At 512 px (the paint is 2048): the face
# sits at x 1710..1960, y 880..1200 of the paint (eyes at 1795,977 and 1880,977).
#   python tools/goblin_marks.py art/models/characters/goblin_marks.png
import sys

from PIL import Image, ImageDraw

SIZE = 512
K = SIZE / 2048.0


def main() -> None:
	out = sys.argv[1]
	channels = []
	# Red: a scar, a slash down and across the left eye.
	scar = Image.new("L", (SIZE, SIZE), 0)
	d = ImageDraw.Draw(scar)
	d.line([(1772 * K, 925 * K), (1838 * K, 1035 * K)], fill=255, width=max(2, int(12 * K)))
	channels.append(scar)
	# Green: three stripes on each cheek.
	stripes = Image.new("L", (SIZE, SIZE), 0)
	d = ImageDraw.Draw(stripes)
	for y in (1028, 1048, 1068):
		d.rectangle([(1742 * K, y * K), (1790 * K, (y + 8) * K)], fill=255)
		d.rectangle([(1888 * K, y * K), (1936 * K, (y + 8) * K)], fill=255)
	channels.append(stripes)
	# Blue: a hand, palm over the mouth, fingers spread up the face.
	hand = Image.new("L", (SIZE, SIZE), 0)
	d = ImageDraw.Draw(hand)
	d.ellipse([(1812 * K, 1062 * K), (1876 * K, 1122 * K)], fill=255)
	for x0, x1 in [(1810, 1790), (1828, 1820), (1846, 1850), (1864, 1882)]:
		d.line([(x0 * K, 1070 * K), (x1 * K, 1000 * K)], fill=255, width=max(2, int(12 * K)))
	d.line([(1876 * K, 1090 * K), (1912 * K, 1070 * K)], fill=255, width=max(2, int(12 * K)))
	channels.append(hand)
	Image.merge("RGB", channels).save(out)
	print("wrote %s" % out)


if __name__ == "__main__":
	main()

extends "res://tests/tour/tours/seams.gd"
## The foothills' road seams re-shot (327 amended, maps: glimpse walls were
## drawn on the lane, read as lone brick walls by the road on 11-01):
##   sh tools/tour.sh lane_walls --offscreen
## Noon, four yaws, the camera low, from the two spots that showed them.

const LANE_SPOTS := [Vector2i(128, 5), Vector2i(128, 90)]


func run(bot: Node) -> void:
	await bot.admin("hour 12")
	for at: Vector2i in LANE_SPOTS:
		await _enter(bot, "foothills")
		await _shoot_at(bot, "foothills", at, "the foothills' road by the seam", 12, true)

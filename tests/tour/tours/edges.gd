extends "res://tests/tour/tours/seams.gd"
## The seam tour's edge heights alone, headless and quick (a few minutes):
##   sh tools/tour.sh edges
## Each outdoor level entered, its edges measured on the world plane, every
## seam where two touch asserted within EDGE_RISE; each seam's cells written
## to seam_<a>_<b>.csv beside the report.


func run(bot: Node) -> void:
	for zone_name: String in OUTDOOR:
		if await _enter(bot, zone_name):
			_measure_edges(bot, zone_name)
	_compare_edges(bot)

extends RefCounted
## The smoke tour: joins, looks about, walks a few cells by click, and
## reads the admin console's help (the harness's own check).


func run(bot: Node) -> void:
	var start: Vector2i = bot.cell()
	bot.log_line("standing at %s in %s; %d bodies seen" % [start, bot.zone(), bot.seen().size()])
	for entity: GridEntity in bot.seen().slice(0, 12):
		bot.log_line("  %s (%s) at %s" % [entity.name, entity.get_class(), entity.tile])
	var help: String = await bot.admin("help")
	bot.expect(not help.is_empty(), "the admin console answers")
	# A walkable cell a few steps off, by the client's own path finder.
	var goal := start
	for offset: Vector2i in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3)]:
		if World.is_walkable(start + offset) and World.get_entity_at(start + offset) == null \
				and not World.walk_path(start, start + offset).is_empty():
			goal = start + offset
			break
	bot.expect(goal != start, "found a walkable cell near the start", str(goal))
	var arrived: bool = await bot.walk_to(goal, 0, 20.0)
	bot.expect(arrived, "a click walks to %s" % goal, "stands at %s" % bot.cell())

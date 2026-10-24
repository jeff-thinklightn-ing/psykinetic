extends Node
## The draugr's fight played through once, headless (decisions 573, 602,
## 603; the coordinator's ask, so a cut need not wait on a clip): a scripted
## player pays 20 for the pact, survives his spin, steps into his charge to
## his axe and disarms him, and beats him till he yields and blesses them.
## His mind is enemy-ai's (Draugr._special_tick); the moves are combat's
## (World.try_spin, try_axe_throw, try_axe_charge); the pushes physics'.
## Every step waits on what the sim does, within a limit, as a play would.
##
## A test-built draugr has no row's body, so his stamina rules are set by
## hand from his row (100, swing_stamina, his breath, his own blows), and
## his battle axe put in his hands (a giant axe where items' is not in).

const SPECS := {
	"P": {"script": "res://sim/player.gd", "shape": "capsule"},
	"u": {"script": "res://sim/draugr.gd", "shape": "capsule", "kind": "draugr"},
}
const LEVEL := "dft_hall"
const ROWS: Array[String] = [
	"####################",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"#..................#",
	"####################",
]

var _failures := 0
var _room: Node2D
var _shown: Array = []
var _ended: Array = []


func _ready() -> void:
	World.set_process(false)
	var probe := Draugr.new()
	var minded := probe.has_method("_special_tick")
	probe.free()
	if not World.has_method("try_spin") or not minded:
		print("  (the draugr's moves or his mind not in: skipped)")
		print("\nRESULT: PASS (0 failed)")
		get_tree().quit(0)
		return
	_play_through()
	print("")
	print("RESULT: %s (%d failed)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _play_through() -> void:
	print("\n== the draugr's fight, once through: pay 20, survive the spin, stop the charge, win ==")
	Monster.idling = true
	Level.register(LEVEL, Level.image_from_rows(ROWS), null, {"regenerate": {"anchors": [{"rect": [1, 1, 18, 5], "name": "lair"}]}})
	World.reset()
	_room = Node2D.new()
	add_child(_room)
	World.load_terrain(Terrain.parse(Terrain.expand(ROWS)))
	World.zone.name = LEVEL
	var draugr := EntityFactory.build(SPECS["u"].merged({"name": "Draugr1", "tile": Vector2i(9, 3),
		"props": Level.MONSTER_TYPES["draugr"].duplicate()})) as Draugr
	_room.add_child(draugr)
	World.spawn(draugr, Vector2i(9, 3))
	draugr.max_stamina = 100
	draugr.stamina = 100
	draugr.pays_swings = true
	_check(draugr.peaceable, "seated at his spawn: peaceable, a click talks (648, npc's side)")
	var row: Dictionary = Monster.kinds()["draugr"]
	draugr.stamina_regen_every = int(row.get("stamina_regen_every", 1))
	draugr.stamina_regen_amount = int(row.get("stamina_regen", 0))
	draugr.blows = row.get("blows", {})
	draugr.sight_range = 10
	draugr.senses.cone_cos = -1.0
	draugr.slots = Items.tidy(["", "", "", "", "", ""], Items.CARRIED)
	var axe := "battle_axe" if Items.exists("battle_axe") else "giant_axe"  # Items' (603, items' side), once in.
	World.set_slots(draugr, Items.tidy(["", "", "", "", axe, ""], Items.CARRIED))
	var player := EntityFactory.build(SPECS["P"].merged({"name": "Player1"})) as Player
	player.player_id = "p1"
	_room.add_child(player)
	World.spawn(player, Vector2i(15, 3))
	player.max_hp = 40
	player.hp = 40
	World.put_item(player, player, Player.RIGHT_HAND, World.items.mint("sword", "built"))
	var was_economy := World.economy
	World.economy = Economy.new({"purses": {"p1": 200}})
	World.telegraph_started.connect(_on_shown)
	World.telegraph_ended.connect(_on_ended)
	var said: Array = []
	draugr.connect("said", func(text: String) -> void: said.append(text))

	# 1. The pact: 20 gold, the easy deal.
	var offers := draugr.offers_for("p1")
	var taken := draugr.accept_offer(player, offers[0], 20)
	_check(taken.get("ok", false) and draugr.state == Draugr.State.PACT and draugr.difficulty == "easy" and World.gold_of("p1") == 180 and not draugr.peaceable,
			"20 gold paid: the pact is on at the easy deal (%s gold left)" % World.gold_of("p1"))
	draugr.target = player

	# 2. His spin: the player beside him strikes him; struck twice, he spins.
	World._relocate(player, Vector2i(8, 3))
	var hp := player.hp
	var spun := _until(200, func() -> bool:
		if player.action_target != draugr:
			World.order_attack(player, draugr)
		return _landed("spin"))
	_check(spun and "spin" in _kinds(), "struck twice beside him: he winds up the spin, its cone shown, and it lands")
	_check(player.spawned and player.hp > 0 and player.hp < hp, "the sweep struck the player, who lives (%d of %d)" % [player.hp, hp])
	_check(draugr.stamina <= int(_mind("BACK_OFF_STAMINA")) + 2 and World.is_winded(draugr), "he is spent: %d stamina, winded" % draugr.stamina)
	_check(_until(20, func() -> bool: return bool(draugr.get("backing_off"))), "he backs off to get his breath")
	player.action_order = GridEntity.Order.NONE
	player.action_target = null

	# 3. His throw: the player stands off on a clear line; he gets his
	# breath and throws.
	World._relocate(player, _stand_off(draugr, 6))
	var thrown := _until(600, func() -> bool:
		draugr.target = player
		return str(World.axe_state(draugr)["where"]) == "ground")
	_check(thrown and _landed("throw"), "his breath back, the player six off: the throw down its line, the axe on the ground at %s" % World.axe_state(draugr)["cell"])

	# 4. His charge: the player steps into its line, beside him, and stops it.
	var charging := _until(200, func() -> bool: return _showing("charge"))
	_check(charging, "he roars for his axe: the charge's line shown")
	var toward: Vector2i = World.axe_state(draugr)["cell"]
	var step := (toward - draugr.tile).clamp(Vector2i(-1, -1), Vector2i(1, 1))
	if World.get_entity_at(draugr.tile + step) != player:
		World._relocate(player, draugr.tile + step)
	var stopped := _until(60, func() -> bool: return World.is_disarmed(draugr) or str(World.axe_state(draugr)["where"]) == "hand")
	_check(stopped and World.is_disarmed(draugr) and str(World.axe_state(draugr)["where"]) == "ground",
			"the player in his way stops the charge: disarmed, his axe still lying")

	# 5. The rest of the fight, his fists against the sword, till he yields.
	draugr.target = player
	var won := _until(1500, func() -> bool:
		if player.hp < 10:
			player.hp = player.max_hp  # A bandage between blows: the script is about him, not her luck.
		if player.action_target != draugr:
			World.order_attack(player, draugr)
		return draugr.state != Draugr.State.PACT)
	_check(won and draugr.blessed_last == ["p1"] and not said.is_empty() and said.back() == _mind("WON") and draugr.spawned,
			"beaten, he yields, never dies, and blesses the player (%s; \"%s\")" % [draugr.blessed_last, said.back() if not said.is_empty() else ""])
	_check(not World.is_disarmed(draugr) or draugr.state == Draugr.State.AT_REST, "and rests, the fight over")

	World.telegraph_started.disconnect(_on_shown)
	World.telegraph_ended.disconnect(_on_ended)
	World.economy = was_economy
	World.dead_rest.clear()
	World.reset()
	_room.free()
	Level.unregister(LEVEL)


## The draugr's mind's constant [param name] (enemy-ai's, read by name so
## this parses before his mind is in).
func _mind(name: String) -> Variant:
	return (load("res://sim/draugr.gd") as Script).get_script_constant_map().get(name)


## Steps the world up to [param ticks] times, [param done] asked after each;
## whether it came true.
func _until(ticks: int, done: Callable) -> bool:
	for i in ticks:
		World.step()
		if bool(done.call()):
			return true
	return false


## A floor cell [param cells] off [param from] on a clear line, inside the
## lair.
func _stand_off(from: GridEntity, cells: int) -> Vector2i:
	for way: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var at := from.tile + way * cells
		if at.x >= 1 and at.x <= 18 and at.y >= 1 and at.y <= 5 and World.is_free(at):
			return at
	return from.tile + Vector2i(cells, 0)


func _on_shown(_id: int, data: Dictionary) -> void:
	_shown.append(data)


func _on_ended(id: int, landed: bool) -> void:
	_ended.append([id, landed])


func _kinds() -> Array:
	return _shown.map(func(data: Dictionary) -> String: return str(data["kind"]))


## Whether a telegraph of [param kind] has landed.
func _landed(kind: String) -> bool:
	for data: Dictionary in _shown:
		if str(data["kind"]) == kind and [int(data["id"]), true] in _ended:
			return true
	return false


## Whether a telegraph of [param kind] is showing now.
func _showing(kind: String) -> bool:
	for data: Dictionary in _shown:
		if str(data["kind"]) == kind and World.telegraphs().has(int(data["id"])):
			return true
	return false


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
	print("  %s  %s" % ["PASS" if ok else "FAIL", label])

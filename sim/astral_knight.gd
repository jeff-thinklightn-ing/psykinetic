class_name AstralKnight
extends Monster
## The fallen knight's astral projection in the barrow's Altar Room (747;
## Jeff: "a astral projection of a fallen knight in the altar room that
## gives the quest ... prove your strength and stop the grave robbers and
## ill then give access to the crypt"). He stands where he is, talks as the
## draugr does (talks, offers_for, accept_offer: Main's talking-monster
## path and ui's window) and is never hurt: a blow passes through him (his
## body is not flesh, World.damage's is_breakable). His quest is Main's
## (World.barrow_quest, barrow_quest_step): his offers are its steps.

signal said(text: String)

## His lines (lore drafts them for Jeff).
const ASK_TITLE := "Prove your strength"
const ASK_WORDS := "I need your help, but first prove your strength. Stop the grave robbers who dig in this barrow, every one of them, and I will give you access to the crypt."
const NOT_YET_TITLE := "Not yet"
const NOT_YET := "Some of the grave robbers still walk these halls. Stop them all, then return."
const TURN_IN_TITLE := "The robbers are stopped"
const TURN_IN_WORDS := "Tell him the Mound-breakers are stopped."
const REVEALED := "You have proven yourself. In the First Hall, the niche that breathes cold air is the way down to the Ossuary; it will open for you now. Below lies the Hall of the Fallen, where the draugr keeps his watch."
const DONE := "The way below is open to you. The Hall of the Fallen waits beneath the Ossuary."


func _ready() -> void:
	super()
	talks = true
	acts = false
	body_material = BodyMaterial.STONE  # Not flesh: no blow lands (World.damage's is_breakable).
	if Net.is_authority():
		peaceable = true


## He stands and waits: no senses, no fight, no step.
func _sim_tick() -> void:
	pass


## [param player_id]'s offers: his quest's step (the ask, not yet or the
## turn-in), one offer a step; once it is done, none (a greeting hears DONE).
func offers_for(player_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var step: Array = {"ask": [":ask", ASK_TITLE, ASK_WORDS], "open": [":not_yet", NOT_YET_TITLE, NOT_YET],
		"ready": [":turn_in", TURN_IN_TITLE, TURN_IN_WORDS]}.get(_quest(player_id), [])
	if not step.is_empty():
		out.append({"id": "quest:%d%s" % [id, step[0]], "kind": "deal", "title": step[1], "words": step[2],
			"what": {"level": "quest", "steps": []}, "accept": "take", "cost": 0})
	return out


## [param player] says yes to [param offer]: the ask taken, or the quest
## turned in (his reveal said); "not yet" is only his words again.
func accept_offer(player: Player, offer: Dictionary, _gold: int) -> Dictionary:
	var offer_id := str(offer.get("id", ""))
	var at := _quest(player.player_id)
	if offer_id.ends_with(":ask") and at == "ask" and _quest_step(player.player_id, "take"):
		return {"ok": true, "say": "", "line": "%s takes up the fallen knight's task." % player.name}
	if offer_id.ends_with(":turn_in") and at == "ready" and _quest_step(player.player_id, "turn_in"):
		said.emit(REVEALED)
		return {"ok": true, "say": "", "line": "%s has proven their strength to the fallen knight." % player.name}
	if at == "":
		return {"ok": false, "say": DONE, "line": ""}
	return {"ok": false, "say": NOT_YET if at == "open" else "", "line": ""}


## Rest words for a greeting with nothing to offer (Main's _monster_greeted):
## his quest done, he tells the way again.
func resting() -> bool:
	return true


func rest_words() -> String:
	return DONE


func _quest(player_id: String) -> String:
	var hook: Variant = World.get("barrow_quest")
	if not hook is Callable or not (hook as Callable).is_valid() or player_id.is_empty():
		return ""
	return str((hook as Callable).call(player_id))


func _quest_step(player_id: String, step: String) -> bool:
	var hook: Variant = World.get("barrow_quest_step")
	return hook is Callable and (hook as Callable).is_valid() and bool((hook as Callable).call(player_id, step))

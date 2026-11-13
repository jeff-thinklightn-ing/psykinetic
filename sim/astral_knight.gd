class_name AstralKnight
extends Monster
## The fallen knight's astral projection in the barrow's First Hall, by its bier (747;
## Jeff: "a astral projection of a fallen knight in the altar room that
## gives the quest ... prove your strength and stop the grave robbers and
## ill then give access to the crypt"). He stands where he is, talks as the
## draugr does (talks, offers_for, accept_offer: Main's talking-monster
## path and ui's window) and is never hurt: a blow passes through him (his
## body is not flesh, World.damage's is_breakable). His quest is Main's
## (World.barrow_quest, barrow_quest_step): his offers are its steps.

signal said(text: String)

## His lines (lore's, Jeff approved 2026-10-31). He is the generation's
## sepulcher knight: ASK_WORDS' %s is Main.barrow_knight (ask_words).
const ASK_TITLE := "Prove your strength"
const ASK_WORDS := "I am %s, a knight of Theus, and my bones lie beneath the temple, held by the draugr. The Mound-breakers dig for them, to sell them. Put down every one of them, and prove your strength. Then I will show you the way below."
## ASK_WORDS before the barrow's first generation, when he has no name.
const ASK_UNNAMED := "I am a knight of Theus, and my bones lie beneath the temple, held by the draugr. The Mound-breakers dig for them, to sell them. Put down every one of them, and prove your strength. Then I will show you the way below."
const NOT_YET_TITLE := "Not yet"
const NOT_YET := "Some of the Mound-breakers still dig. Put them all down, then come back to me."
const TURN_IN_TITLE := "The robbers are put down"
const TURN_IN_WORDS := "The Mound-breakers are put down."
const REVEALED := "Then you are strong enough. Here in this hall, the niche that breathes cold air hides the way down to the Ossuary; it will open for you now. Beyond it lies the Hall of Fallen Souls, where the draugr keeps my remains. Bring them to Aldous, at the temple's altar, and let me rest."
const DONE := "The way below is open to you. My remains wait in the Hall of Fallen Souls."
## The altar step (896, "full circle", voice's words; no new fact of
## the world, the coordinator): with Main.altar_turn_in on (altar_on), his
## reveal sends the remains back to this hall's altar, not to Aldous; a
## player without them hears AWAIT, one carrying them is asked to lay them
## (LAY_TITLE, the coordinator's words), and once laid he thanks them.
const REVEALED_ALTAR := "Then you are strong enough. Here in this hall, the niche that breathes cold air hides the way down to the Ossuary; it will open for you now. Beyond it lies the Hall of Fallen Souls, where the draugr keeps my remains. Bring them here, to this altar, and let me rest."
const AWAIT := "My remains wait in the Hall of Fallen Souls. Bring them here, to this altar."
const LAY_TITLE := "Lay my remains on the altar"
const LAY_WORDS := "You carry my bones. Lay them here, on the altar."
const LAID := "I am home. Thank you."
const DONE_LAID := "My bones are home. Go well."
## Main.altar_turn_in's mirror (its setter): the altar step on.
static var altar_on := false
## His remains laid on his altar this generation, by anyone (896): art-kit's
## piece lies on the bier while it is true. Kept in his spawn props, so a
## restart keeps it and a new generation (a new spawn) clears it.
var remains_laid := false
## A quest offer's accept that takes nothing (747 amended (5)): his words
## alone, ui's window closing on its one button.
const WORDS_ONLY := "none"


func _ready() -> void:
	super()
	talks = true
	acts = false
	body_material = BodyMaterial.STONE  # Not flesh: no blow lands (World.damage's is_breakable).
	replicate("remains_laid")  # 896: for the remains on the bier.
	remains_laid = bool((spawn_spec.get("props", {}) as Dictionary).get("remains_laid", false))
	if Net.is_authority():
		peaceable = true


## He stands and waits: no senses, no fight, no step.
func _sim_tick() -> void:
	pass


## Never a threat to anyone (companions: Main._fight_near and Pip's
## "danger" asked Monster.threatens, which reads a player as threatened).
func threatens(_entity: GridEntity) -> bool:
	return false


## [param player_id]'s offers: his quest's step (the ask, not yet or the
## turn-in), one offer a step; once it is done, his closing words alone
## (747 amended (5); Jeff on v0.1.197: "fallen knight was not interactable":
## a click opened nothing, DONE only a "Server:" line in the chat), accept
## WORDS_ONLY: ui's window shows them with one button that closes it.
func offers_for(player_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := _quest(player_id)
	var step: Array = {"ask": [":ask", ASK_TITLE, ask_words(), "take"], "open": [":not_yet", NOT_YET_TITLE, NOT_YET, "take"],
		"ready": [":turn_in", TURN_IN_TITLE, TURN_IN_WORDS, "take"], "altar": [":await", "", AWAIT, WORDS_ONLY],
		"carried": [":lay", LAY_TITLE, LAY_WORDS, "take"]}.get(at, [])
	if step.is_empty() and at.is_empty() and _quest_known(player_id):
		step = [":done", "", DONE_LAID if altar_on else DONE, WORDS_ONLY]
	if not step.is_empty():
		out.append({"id": "quest:%d%s" % [id, step[0]], "kind": "deal", "title": step[1], "words": step[2],
			"what": {"level": "quest", "steps": []}, "accept": step[3], "cost": 0})
	return out


## [param player] says yes to [param offer]: the ask taken, or the quest
## turned in (his reveal said); "not yet" is only his words again. "line"
## is said of them to the others there, "you_line" to them (133 amended (2)).
func accept_offer(player: Player, offer: Dictionary, _gold: int) -> Dictionary:
	var offer_id := str(offer.get("id", ""))
	var at := _quest(player.player_id)
	if offer_id.ends_with(":ask") and at == "ask" and _quest_step(player.player_id, "take"):
		return {"ok": true, "say": "", "line": "%s takes up the fallen knight's task." % player.name,
			"you_line": "You take up the fallen knight's task."}
	if offer_id.ends_with(":lay") and at == "carried" and _quest_step(player.player_id, "lay"):
		said.emit(LAID)  # 896: his remains on the altar, the same as a click on it.
		return {"ok": true, "say": "", "line": "%s lays %s remains on the altar." % [player.name, whose()],
			"you_line": "You lay %s remains on the altar." % whose()}
	if offer_id.ends_with(":turn_in") and at == "ready" and _quest_step(player.player_id, "turn_in"):
		said.emit(REVEALED_ALTAR if altar_on else REVEALED)
		return {"ok": true, "say": "", "line": "%s has proven their strength to the fallen knight." % player.name,
			"you_line": "You have proven your strength to the fallen knight."}
	if at == "":
		return {"ok": false, "say": DONE_LAID if altar_on else DONE, "line": ""}
	if at == "altar":
		return {"ok": false, "say": AWAIT, "line": ""}
	return {"ok": false, "say": NOT_YET if at == "open" else "", "line": ""}


## His remains are laid on his altar (896, Main._lay_remains): kept for the generation.
func lay_remains() -> void:
	remains_laid = true
	_keep_prop("remains_laid", true)


## Rest words for a greeting with nothing to offer (Main's _monster_greeted):
## his quest done, he tells the way again.
func resting() -> bool:
	return true


func rest_words() -> String:
	return DONE_LAID if altar_on else DONE


## His ask, naming him: the knight barrow_deep's generation keeps
## (Main.barrow_knight through Offers.ctx), ASK_UNNAMED with none.
func ask_words() -> String:
	var knight := str(Offers._call(Offers.ctx, "barrow_knight")) if Offers.ctx.has("barrow_knight") else ""
	return ASK_UNNAMED if knight.is_empty() or knight == "<null>" else ASK_WORDS % knight


## Whose remains, for the party lines (voice): his name's, as ASK_WORDS
## names him, "the knight's" before a generation names one (ASK_UNNAMED).
static func whose() -> String:
	var knight := str(Offers._call(Offers.ctx, "barrow_knight")) if Offers.ctx.has("barrow_knight") else ""
	return "the knight's" if knight.is_empty() or knight == "<null>" else "%s's" % knight


func _quest(player_id: String) -> String:
	var hook: Variant = World.get("barrow_quest")
	if not hook is Callable or not (hook as Callable).is_valid() or player_id.is_empty():
		return ""
	return str((hook as Callable).call(player_id))


## Whether Main keeps a quest for [param player_id] (its hook set and a
## record): "" from _quest then means done, not unknown.
func _quest_known(player_id: String) -> bool:
	var hook: Variant = World.get("barrow_quest_known")
	return hook is Callable and (hook as Callable).is_valid() and not player_id.is_empty() and bool((hook as Callable).call(player_id))


func _quest_step(player_id: String, step: String) -> bool:
	var hook: Variant = World.get("barrow_quest_step")
	return hook is Callable and (hook as Callable).is_valid() and bool((hook as Callable).call(player_id, step))

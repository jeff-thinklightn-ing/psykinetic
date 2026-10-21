class_name RoadKnowledge
extends RefCounted
## What a companion knows of the roads, and how fresh it is (decision 551
## phase 2, npc's side; Jeff: "next time she could refuse: it isn't safe,
## there are bandits on that road"). Her card's roads.dangers (Guide's,
## 551) hold what she lived through, each {area, place, why, from "lived",
## day, weight}; here the road's news she heard joins them, {area (the
## camp's), camp, faction (its word at the time), goods, why "raided", from
## "heard", day, weight}. A danger weighs its full weight for fresh_days
## (heard 4, lived 8: lived outlasts hearsay), then straight down to
## nothing at twice that, when it is pruned. The world answers three ways:
## a camp nobody holds any more drops its heard dangers on sight ("a
## cleared camp lets her go next time"), the days fade them, and a passage
## through an area without a stop halves that area's dangers, once a day.
## The refusal that weighs them against her temper and bond, her words and
## the stop are companions' (Guide); this never names Guide, so the Guide →
## WorldNews → PlayerRecord → Companion chain stays open, and the guide
## rules (companion_traits.json "guide") come in as an argument. Pure sim.

const HEARD := "heard"
const LIVED := "lived"
const RAIDED := "raided"

const FRESH_DAYS := {HEARD: 4, LIVED: 8}
const HEARD_WEIGHTS := {RAIDED: 2}

## What she says of a lived danger ("why" → the clause before the day).
const LIVED_WORDS := {
	"downed": "I went down there",
	"taken": "I was carried off there",
	"fell": "you fell there",
	"hurt": "we were hurt badly there",
}

const DAY_WORDS := ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]


## Her roads on [param card] (record.companion), {areas, places, dangers,
## passed}, made when missing (Guide.roads_of's shape, plus passed).
static func roads_of(card: Dictionary) -> Dictionary:
	var roads: Variant = card.get("roads")
	if not roads is Dictionary:
		roads = {}
		card["roads"] = roads
	for key: String in ["areas", "places", "dangers"]:
		if not roads.get(key) is Array:
			roads[key] = []
	if not roads.get("passed") is Dictionary:
		roads["passed"] = {}
	return roads


static func dangers_of(card: Dictionary) -> Array:
	return roads_of(card)["dangers"]


# --- Hearing -------------------------------------------------------------------------

## The road's [param news] (Townsfolk's road_news: {kind, day, camp, goods,
## ...}) reaches her: a wagon struck ("raided") by a camp [param holdings]
## knows becomes a heard danger of the camp's area, weighted by
## [param rules] heard_weights; the same camp on the same day is no new
## one. A wagon home again or lost adds nothing: one that got through was
## lucky, and a lost one names no camp. The entry added, {} for none.
static func heard(card: Dictionary, news: Dictionary, holdings: Holdings, rules: Dictionary) -> Dictionary:
	if str(news.get("kind", "")) != RAIDED or holdings == null:
		return {}
	var camp := str(news.get("camp", ""))
	var place := holdings.place(camp)
	if camp.is_empty() or place.is_empty():
		return {}
	var day := int(news.get("day", 0))
	var dangers := dangers_of(card)
	for each: Variant in dangers:
		if each is Dictionary and each.get("from") == HEARD and each.get("camp") == camp and int(each.get("day", -1)) == day:
			return {}
	var holder := holdings.holder(camp)
	var faction := holdings.factions.display_name(holder) if holdings.factions != null and holder != Factions.NOBODY else ""
	var entry := {"area": str(place.get("area", "")), "camp": camp, "faction": faction,
		"goods": str(news.get("goods", "")), "why": RAIDED, "from": HEARD, "day": day,
		"weight": int(_rule_of(rules, "heard_weights", RAIDED, HEARD_WEIGHTS))}
	dangers.append(entry)
	return entry


# --- Weighing ------------------------------------------------------------------------

## What stands against a walk through [param areas] on [param day]: the
## dangers on them, each at its weight faded by age ([method standing]),
## after the dead and the cleared are pruned. {weight (their sum), worst
## (the heaviest standing entry, with its "standing"; {} for none)}.
static func weigh(card: Dictionary, areas: Array, day: int, holdings: Holdings, rules: Dictionary) -> Dictionary:
	prune(card, day, holdings, rules)
	var total := 0.0
	var worst := {}
	var worst_at := 0.0
	for each: Variant in dangers_of(card):
		if not each is Dictionary or str(each.get("area", "")) not in areas:
			continue
		var now := standing(each, day, rules)
		total += now
		if now > worst_at:
			worst_at = now
			worst = each.duplicate()
			worst["standing"] = now
	return {"weight": total, "worst": worst}


## [param entry]'s weight on [param day]: whole within fresh_days of its
## day, nothing from twice that, straight between.
static func standing(entry: Dictionary, day: int, rules: Dictionary) -> float:
	var fresh := fresh_days(rules, str(entry.get("from", LIVED)))
	var age := maxi(day - int(entry.get("day", day)), 0)
	var weight := float(entry.get("weight", 1))
	if age <= fresh:
		return weight
	if fresh <= 0 or age >= 2 * fresh:
		return 0.0
	return weight * float(2 * fresh - age) / float(fresh)


## Drops what no longer counts on [param day]: a danger faded to nothing or
## with no weight left, and a heard one whose camp nobody holds any more
## (cleared), or that is no place of [param holdings]. How many went.
static func prune(card: Dictionary, day: int, holdings: Holdings, rules: Dictionary) -> int:
	var dangers := dangers_of(card)
	var kept: Array = []
	for each: Variant in dangers:
		if not each is Dictionary:
			continue
		var gone := standing(each, day, rules) <= 0.0
		if not gone and each.get("from") == HEARD and holdings != null:
			var camp := str(each.get("camp", ""))
			gone = holdings.place(camp).is_empty() or holdings.holder(camp) == Factions.NOBODY
		if not gone:
			kept.append(each)
	var dropped := dangers.size() - kept.size()
	if dropped > 0:
		dangers.assign(kept)
	return dropped


## She led her player through [param area] to its far side with no stop on
## [param day]: every danger of the area is halved (rounded down, so a
## restart's whole numbers keep it; at nothing it is pruned next), once a
## day an area (roads.passed). True if any weight moved.
static func passed(card: Dictionary, area: String, day: int) -> bool:
	var roads := roads_of(card)
	var days: Dictionary = roads["passed"]
	if area.is_empty() or int(days.get(area, -1)) == day:
		return false
	days[area] = day
	var moved := false
	for each: Variant in roads["dangers"]:
		if each is Dictionary and str(each.get("area", "")) == area and int(each.get("weight", 0)) > 0:
			each["weight"] = int(each.get("weight", 0)) / 2
			moved = true
	return moved


# --- Words ---------------------------------------------------------------------------

## The clause after "it isn't safe" for [param worst] (weigh's) on
## [param day]: heard, "there are bandits on the road through the Wilds:
## the Blood Rot struck a wagon carrying 3 wool there four days back";
## lived, first person, "I was carried off there, six days back". The
## area's name from [param world_map] when given, else its id's last word.
## "" for {}.
static func reason(worst: Dictionary, day: int, world_map: WorldMap = null) -> String:
	if worst.is_empty():
		return ""
	var when := day_words(day - int(worst.get("day", day)))
	if worst.get("from") == HEARD:
		var who := str(worst.get("faction", ""))
		var goods := str(worst.get("goods", ""))
		return "there are bandits on the road through %s: %s struck a wagon%s there %s" % [
			area_words(str(worst.get("area", "")), world_map), who if not who.is_empty() else "raiders",
			"" if goods.is_empty() else " carrying " + goods, when]
	return "%s, %s" % [LIVED_WORDS.get(str(worst.get("why", "")), "it went badly there"), when]


## "today", "yesterday", "four days back".
static func day_words(age: int) -> String:
	if age <= 0:
		return "today"
	if age == 1:
		return "yesterday"
	return "%s days back" % (DAY_WORDS[age] if age < DAY_WORDS.size() else str(age))


## [param area]'s display name on [param world_map], else its id's last
## word with its underscores spaced ("o/wild_hills" → "wild hills").
static func area_words(area: String, world_map: WorldMap = null) -> String:
	if world_map != null and world_map.areas.has(area):
		var shown := str(world_map.areas[area].get("display_name", ""))
		if not shown.is_empty():
			return shown
	return area.get_file().replace("_", " ")


# --- Rules ---------------------------------------------------------------------------

## fresh_days of [param rules] for [param from] ("heard" or "lived").
static func fresh_days(rules: Dictionary, from: String) -> int:
	return int(_rule_of(rules, "fresh_days", from, FRESH_DAYS))


static func _rule_of(rules: Dictionary, table: String, key: String, otherwise: Dictionary) -> float:
	var found: Variant = rules.get(table, {})
	if found is Dictionary and found.has(key):
		return float(found[key])
	return float(otherwise.get(key, 1))

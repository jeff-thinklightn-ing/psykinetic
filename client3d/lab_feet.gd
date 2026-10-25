extends RefCounted
## The Character Lab's foot-slide readout (674 step 3): tools/gait_pace.gd's
## measure (decision 160), taken live on a body as the lab plays it, so it
## reads Jeff's own exports too. Each sample the two toe bones' places; the
## lower toe, within PLANTED_M of its lowest over the window, is the planted
## one, and the ground's speed under it is its speed backwards along the
## body's front (the toes ahead of the feet at rest). Over the last loop of
## the clip: the measured pace (the median of those speeds: the floor's speed
## that keeps the planted foot still) and the slide at a given pace (how fast
## the planted foot moves over a floor running at it: the median and the 90th
## of the planted samples, the worst moment being a foot's plant or lift).

const PLANTED_M := 0.02
## The slide shown red: over this share of the pace (a gait), or over
## STILL_RED m/s (a clip that stands, its pace 0).
const SLIDE_RED := 0.05
const STILL_RED := 0.05

var skeleton: Skeleton3D
var toes: Array[int] = []
var front := Vector3.RIGHT
## [time, foot, height, ground speed] per sample, the window's.
var samples: Array[Array] = []
var clock := 0.0
var _last: Array = []


## On [param model] (a body as Client3D makes it, in the tree): its toes and
## its front, or no meter (toes empty) when its skeleton lacks them.
func _init(model: Node3D) -> void:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	skeleton = found[0] as Skeleton3D
	var feet: Array[int] = [skeleton.find_bone("LeftFoot"), skeleton.find_bone("RightFoot")]
	toes = [skeleton.find_bone("LeftToes"), skeleton.find_bone("RightToes")]
	if toes.has(-1) or feet.has(-1):
		toes = []
		return
	var ahead := Vector3.ZERO
	for i in 2:
		ahead += skeleton.get_bone_global_rest(toes[i]).origin - skeleton.get_bone_global_rest(feet[i]).origin
	ahead = skeleton.global_basis * ahead
	ahead.y = 0.0
	if ahead.length() > 0.0001:
		front = ahead.normalized()


## The samples dropped (a new clip, speed or body).
func reset() -> void:
	samples.clear()
	_last = []


## One sample, [param delta] seconds on from the last, keeping [param window]
## seconds of them.
func sample(delta: float, window: float) -> void:
	if toes.is_empty() or delta <= 0.0:
		return
	clock += delta
	var now := [_at(0), _at(1)]
	if not _last.is_empty():
		var foot := 0 if (now[0] as Vector3).y <= (now[1] as Vector3).y else 1
		var ground := -((now[foot] as Vector3) - (_last[foot] as Vector3)).dot(front) / delta
		samples.append([clock, foot, (now[foot] as Vector3).y, ground])
	_last = now
	while not samples.is_empty() and clock - float(samples[0][0]) > window:
		samples.pop_front()


## Over the window: {"pace", "slide", "slide_90", "planted"} at a floor
## running at [param pace]; {} with nothing planted yet.
func measure(pace: float) -> Dictionary:
	var lows: Array[float] = [INF, INF]
	for each in samples:
		lows[int(each[1])] = minf(lows[int(each[1])], float(each[2]))
	var grounds: Array[float] = []
	var slides: Array[float] = []
	for each in samples:
		if float(each[2]) <= lows[int(each[1])] + PLANTED_M:
			grounds.append(float(each[3]))
			slides.append(absf(float(each[3]) - pace))
	if grounds.is_empty():
		return {}
	grounds.sort()
	slides.sort()
	return {"pace": grounds[grounds.size() / 2], "slide": slides[slides.size() / 2],
		"slide_90": slides[mini(slides.size() - 1, slides.size() * 9 / 10)], "planted": grounds.size()}


## Where the planted toe is now, on the floor's plane, if the last sample's
## lower foot is planted (within PLANTED_M of its lowest over the window);
## null otherwise.
func planted_toe() -> Variant:
	if samples.is_empty() or _last.is_empty():
		return null
	var foot := int(samples[-1][1])
	var low := INF
	for each in samples:
		if int(each[1]) == foot:
			low = minf(low, float(each[2]))
	return _last[foot] if float(samples[-1][2]) <= low + PLANTED_M else null


## Whether [param measured]'s slide shows red at [param pace].
static func red(measured: Dictionary, pace: float) -> bool:
	var slide := float(measured.get("slide", 0.0))
	return slide > (SLIDE_RED * pace if pace > 0.0 else STILL_RED)


func _at(i: int) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(toes[i]).origin

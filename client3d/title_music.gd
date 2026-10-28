extends Node
## The title screen's music (decision 656; Jeff's theme since 656 amended,
## "use the psykinetic theme1 wav for the login/options screen"): music.title
## on the Music bus while the main menu and the connect screen show, faded in
## over FADE_IN as the menu opens and out over FADE_OUT as the world starts
## loading, then gone. A whole track, not a loop cut clean at its seam: it
## plays through, fades out over its last FADE_OUT, and comes in again from
## its start over FADE_IN (_round), so its end never clicks into its start. Main makes it
## with the menu (_show_menu) and lets it go (_end_title_music) on a client's
## first "map" message, or on Play for a host, whose world is already there;
## the game's own Music comes with the view.

## Seconds the title fades in over, and out over.
const FADE_IN := 1.0
const FADE_OUT := 1.0
## dB a fade starts from or ends at: silent enough to start or stop on.
const SILENT_DB := -60.0
const SLOT := "music.title"

var player: AudioStreamPlayer = null
## Whether it is on its way out (stop called): it frees itself once faded.
var stopping := false
## Whether this round is fading out at its end (_process).
var _ending := false
var _tween: Tween = null


func _ready() -> void:
	# The menu comes before any view, so the buses and their volumes may not be made yet.
	Sfx.apply_volumes()
	if not Net.volumes_changed.is_connected(Sfx.apply_volumes):
		Net.volumes_changed.connect(Sfx.apply_volumes)
	var files := SoundKit.files(SLOT)
	if files.is_empty():
		return
	var stream: AudioStream = load(files[0])
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false  # Round again by _round, faded.
	player = AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Music"
	player.volume_db = SILENT_DB
	add_child(player)
	player.finished.connect(_again)
	player.play()
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", SoundKit.volume_db(SLOT), FADE_IN)


## Near its end: faded out over what is left of FADE_OUT, once a round.
func _process(_delta: float) -> void:
	if player == null or stopping or _ending or not player.playing:
		return
	var left := player.stream.get_length() - player.get_playback_position()
	if left <= FADE_OUT:
		_ending = true
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(player, "volume_db", SILENT_DB, maxf(left, 0.01))


## Played through: again from its start, faded in.
func _again() -> void:
	if stopping or not is_inside_tree():
		return
	_ending = false
	player.volume_db = SILENT_DB
	player.play()
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", SoundKit.volume_db(SLOT), FADE_IN)


## Whether the title is heard (or fading in).
func playing() -> bool:
	return player != null and player.playing and not stopping


## Faded out over FADE_OUT, then gone (the game starts).
func stop() -> void:
	if stopping:
		return
	stopping = true
	if _tween != null:
		_tween.kill()
	if player == null or not is_inside_tree():
		queue_free()
		return
	_tween = create_tween()
	_tween.tween_property(player, "volume_db", SILENT_DB, FADE_OUT)
	_tween.tween_callback(queue_free)


## The stream let go as this goes: a stream still playing at quit is reported
## as a leak.
func _exit_tree() -> void:
	if player != null:
		player.stop()
		player.stream = null

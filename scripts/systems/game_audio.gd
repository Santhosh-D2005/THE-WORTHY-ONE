class_name GameAudio
extends Node
## All sound of THE WORTHY ONE goes through this node (one in the game scene, one in the main menu scene).
##
## SOUNDS (Milestone 1.18): the files in res://assets/audio/ are ORIGINAL, synthesised by tools/make_audio.py (see assets/audio/README.md:
## no samples, no third-party material, released CC0). They are loaded here by name; a file that is missing, fails to load or is not an
## AudioStream simply leaves that cue silent, so a missing asset can never crash the game. `cue_streams` can still override any cue from the
## editor, as before.
##
## EVENTS -> CUES (LevelManager / the menus decide, this node only plays):
##   tap            a valid, in-rhythm tap that added progress (5+ per second: very short and soft)
##   tap_slow       an alternating tap that was too slow (no progress): a duller tick
##   first_tap      the tap that starts an attempt
##   pull           the extraction completes and the blade starts to rise
##   freed          the blade leaves the wood (the camera impact): one clear, restrained steel ring
##   level_complete the level-complete card appears: two soft low bell tones
##   planted        the next sword lands in the stump
##   failure        the run failed
##   ui_tap         PLAY-less buttons: QUIT, RESUME, MAIN MENU, TRY AGAIN
##   ui_play        the PLAY button
##   pause / resume reserved (no sound: pausing is handled by pausing the streams, see below)
## `cue_requested` is emitted for EVERY cue even when no stream exists, so tests (and future systems such as haptics) can listen.
##
## AMBIENCE: one looping forest-wind stream (play_ambience / stop_ambience), very quiet; it fades in and out. It is a separate player so
## it is never stolen by the cue pool.
##
## PAUSING: this node listens to GameManager.state_changed. While the game is PAUSED every player (cues and ambience) is paused, so a ring
## or the wind stops with the game and continues where it was on resume. A cue played WHILE paused (the sound of pressing RESUME) is
## played normally. Leaving a screen frees this node with its scene, which stops everything it was playing.

signal cue_requested(cue: StringName, intensity: float)

const CUES: Array[StringName] = [&"tap", &"tap_slow", &"first_tap", &"pull", &"freed", &"level_complete", &"planted", &"failure", &"pause", &"resume", &"ui_tap", &"ui_play"]
const POOL_SIZE := 6
## cue name -> file name (without extension) in the asset folder. `pause` and `resume` have no sound.
const CUE_FILES := {
	&"tap": "tap", &"tap_slow": "tap_slow", &"first_tap": "first_tap", &"pull": "pull", &"freed": "freed",
	&"level_complete": "level_complete", &"planted": "planted", &"failure": "failure", &"ui_tap": "ui_tap", &"ui_play": "ui_play",
}
## Default level of each cue (dB, relative to the file; the files are normalised to peaks of 0.3-0.55). Quiet on purpose.
const DEFAULT_VOLUMES_DB := {
	&"tap": -15.0, &"tap_slow": -17.0, &"first_tap": -12.0, &"pull": -12.0, &"freed": -11.0,
	&"level_complete": -13.0, &"planted": -12.0, &"failure": -13.0, &"ui_tap": -13.0, &"ui_play": -10.0,
}
const AMBIENCE_FILE := "ambience"
const SILENT_DB := -60.0
## How many frames before the end of the data the ambience loop wraps (see _make_loop).
const LOOP_END_MARGIN_FRAMES := 64

## Folder the sound files are read from (a variable so a test can point it at a folder that does not exist).
@export var asset_dir: String = "res://assets/audio/"
## cue name -> AudioStream. Filled from the asset folder on start; anything set here beforehand is kept.
@export var cue_streams: Dictionary = {}
## cue name -> volume in dB (optional; the defaults above are used otherwise).
@export var cue_volumes_db: Dictionary = {}
@export var bus: StringName = &"Master"

var cue_count: int = 0
var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _ambience_player: AudioStreamPlayer = null
var _ambience_tween: Tween = null
var _ambience_stream: AudioStream = null
var _paused: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_cue_streams()
	GameManager.state_changed.connect(_on_state_changed)

func _load_cue_streams() -> void:
	for cue in CUE_FILES:
		if cue_streams.get(cue) is AudioStream:
			continue
		var stream := _load_stream(CUE_FILES[cue])
		if stream != null:
			cue_streams[cue] = stream

## Load one sound file by name, or null (never an error) when it is missing or not an AudioStream.
func _load_stream(file_name: String) -> AudioStream:
	var path := asset_dir.path_join(file_name + ".wav")
	if not ResourceLoader.exists(path):
		return null
	var resource := load(path)
	return resource as AudioStream

## Play a cue. `intensity` (0..1) lets a stream-less game still tell listeners how big the moment is
## (higher levels give the bigger extraction); streams may scale their volume with it.
func play(cue: StringName, intensity: float = 0.0) -> void:
	cue_count += 1
	cue_requested.emit(cue, intensity)
	var raw: Variant = cue_streams.get(cue)
	var stream: AudioStream = raw if raw is AudioStream else null  # (a non-stream value in the slot is ignored, never cast)
	if stream == null:
		return  # no asset: silent by design
	if _players.is_empty():
		for i in POOL_SIZE:
			var player := AudioStreamPlayer.new()
			player.bus = bus
			add_child(player)
			_players.append(player)
	var chosen := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	chosen.stream_paused = false  # a cue that is played now is heard now, even while the game is paused (RESUME's own click)
	chosen.stream = stream
	var base_db: float = float(cue_volumes_db.get(cue, DEFAULT_VOLUMES_DB.get(cue, 0.0)))
	chosen.volume_db = base_db + linear_to_db(lerpf(0.8, 1.0, clampf(intensity, 0.0, 1.0)))
	chosen.play()

func has_stream(cue: StringName) -> bool:
	return cue_streams.get(cue) is AudioStream

# ---- Ambience -----------------------------------------------------------------------------------------

## Start the looping forest ambience at `volume_db`, fading in. Calling it again only retargets the volume (never a second loop).
func play_ambience(volume_db: float = -24.0, fade_seconds: float = 1.5) -> void:
	if _ambience_stream == null:
		_ambience_stream = _make_loop(_load_stream(AMBIENCE_FILE))
	if _ambience_stream == null:
		return  # no asset: silent by design
	if _ambience_player == null:
		_ambience_player = AudioStreamPlayer.new()
		_ambience_player.name = "Ambience"
		_ambience_player.bus = bus
		_ambience_player.stream = _ambience_stream
		_ambience_player.volume_db = SILENT_DB
		add_child(_ambience_player)
	_ambience_player.stream_paused = _paused
	if not _ambience_player.playing:
		_ambience_player.volume_db = SILENT_DB
		_ambience_player.play()
	_fade_ambience_to(volume_db, fade_seconds, false)

## Fade the ambience out and stop it.
func stop_ambience(fade_seconds: float = 0.5) -> void:
	if _ambience_player == null or not _ambience_player.playing:
		return
	_fade_ambience_to(SILENT_DB, fade_seconds, true)

func is_ambience_playing() -> bool:
	return _ambience_player != null and _ambience_player.playing

func ambience_player() -> AudioStreamPlayer:
	return _ambience_player

func _fade_ambience_to(target_db: float, seconds: float, stop_when_done: bool) -> void:
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	if seconds <= 0.0:
		_ambience_player.volume_db = target_db
		if stop_when_done:
			_ambience_player.stop()
		return
	_ambience_tween = create_tween()
	_ambience_tween.tween_property(_ambience_player, "volume_db", target_db, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if stop_when_done:
		_ambience_tween.tween_callback(_ambience_player.stop)

## A looping copy of a stream (the shared imported resource is never modified).
static func _make_loop(stream: AudioStream) -> AudioStream:
	if stream == null:
		return null
	var looped := stream.duplicate() as AudioStream
	if looped is AudioStreamWAV:
		var wav := looped as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# The loop ends a few frames BEFORE the end of the data. Ending it exactly at the end crashed the Android mixer (SIGSEGV in the
		# audio thread, about 18 s after launch, found by the 1.19 phone test): it reads a frame or two past the loop end when it wraps.
		var bytes_per_frame := (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
		var frames := wav.data.size() / bytes_per_frame
		wav.loop_end = maxi(frames - LOOP_END_MARGIN_FRAMES, 1)
	elif "loop" in looped:
		looped.set("loop", true)
	return looped

# ---- Pausing ------------------------------------------------------------------------------------------

func _on_state_changed(state: GameManager.State) -> void:
	set_paused(state == GameManager.State.PAUSED)

## Pause or resume every stream this node owns (the cues and the ambience).
func set_paused(paused: bool) -> void:
	_paused = paused
	for player in _players:
		player.stream_paused = paused
	if _ambience_player != null:
		_ambience_player.stream_paused = paused

func is_paused() -> bool:
	return _paused

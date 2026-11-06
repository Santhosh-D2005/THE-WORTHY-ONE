extends Node
## Milestone 1.18 focused audio tests: the sound files and their loading, the safety of missing assets, the ambience loop and its fades,
## pausing / resuming / leaving, and which events fire which cues (menu and game scenes, by controlled triggering: nobody plays the game).
## Run headless:   godot --headless --path . res://tests/audio_tests.tscn
## Headless runs use Godot's dummy audio driver, so this verifies the logic and the player state, NOT what is audible. Exit code 0 = all passed.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const MENU_SCENE := "res://scenes/ui/main_menu.tscn"

var _checks := 0
var _failures := 0

func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  ", label)
	else:
		_failures += 1
		print("  FAIL  ", label)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().size = Vector2i(540, 960)
	await _frames(3)
	await _t_assets()
	await _t_missing_assets()
	await _t_ambience()
	await _t_pause()
	await _t_menu()
	await _t_game_events()
	await _t_loop_boundary()
	await _t_player_cleanup()
	print("\n==== %d checks, %d failed ====" % [_checks, _failures])
	print("RESULT: ALL PASSED" if _failures == 0 else "RESULT: FAILURES")
	get_tree().quit(0 if _failures == 0 else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame

func _new_audio() -> GameAudio:
	var audio := GameAudio.new()
	add_child(audio)
	return audio

# ---- 1. the files ---------------------------------------------------------------------------------

func _t_assets() -> void:
	print("\n[1] SOUND FILES")
	var audio := _new_audio()
	await _frames(2)
	var loaded := 0
	var quiet := true
	for cue in GameAudio.CUE_FILES:
		if audio.has_stream(cue):
			loaded += 1
			var stream := audio.cue_streams[cue] as AudioStream
			if stream.get_length() <= 0.0 or stream.get_length() > 3.0:
				quiet = false
	_check(loaded == GameAudio.CUE_FILES.size(), "all %d cue files exist, import and load (%d loaded)" % [GameAudio.CUE_FILES.size(), loaded])
	_check(quiet, "every cue is between 0 and 3 seconds long (short, never a long sound)")
	_check(ResourceLoader.exists("res://assets/audio/ambience.wav") and (load("res://assets/audio/ambience.wav") as AudioStream).get_length() > 10.0, "the ambience file exists and is a long loop")
	_check(FileAccess.file_exists("res://assets/audio/README.md"), "the audio origin and licence note exists")
	var volumes_ok := true
	for cue in GameAudio.CUE_FILES:
		var db: float = GameAudio.DEFAULT_VOLUMES_DB.get(cue, 99.0)
		if db > -9.0 or db < -30.0:
			volumes_ok = false
	_check(volumes_ok, "every default cue volume is between -30 and -9 dB (quiet by design)")
	audio.queue_free()

# ---- 2. missing assets cannot crash ------------------------------------------------------------------

func _t_missing_assets() -> void:
	print("\n[2] MISSING OR BROKEN ASSETS")
	var audio := GameAudio.new()
	audio.asset_dir = "res://assets/does_not_exist/"
	add_child(audio)
	await _frames(2)
	var heard: Array[StringName] = []
	audio.cue_requested.connect(func(cue: StringName, _i: float) -> void: heard.append(cue))
	for cue in GameAudio.CUES:
		audio.play(cue, 0.5)
	_check(heard.size() == GameAudio.CUES.size() and not audio.has_stream(&"tap"), "with no sound files every cue still reports itself and nothing crashes")
	audio.play_ambience()
	audio.stop_ambience()
	audio.set_paused(true)
	audio.set_paused(false)
	_check(not audio.is_ambience_playing(), "ambience with no file is a quiet no-op (play, stop and pause do not crash)")
	audio.play(&"not_a_cue")
	_check(heard.back() == &"not_a_cue", "an unknown cue name is harmless")
	# A stream slot holding something that is not an AudioStream is ignored, not trusted.
	var odd := GameAudio.new()
	odd.cue_streams = {&"tap": "not a stream"}
	odd.asset_dir = "res://assets/does_not_exist/"
	add_child(odd)
	await _frames(2)
	odd.play(&"tap")
	_check(not odd.has_stream(&"tap"), "a non-stream value in cue_streams is ignored")
	audio.queue_free()
	odd.queue_free()

# ---- 3. ambience loop and fades -----------------------------------------------------------------------

func _t_ambience() -> void:
	print("\n[3] AMBIENCE LOOP")
	var audio := _new_audio()
	await _frames(2)
	audio.play_ambience(-24.0, 0.4)
	await _frames(2)
	var player := audio.ambience_player()
	_check(audio.is_ambience_playing() and player != null, "the ambience starts")
	var stream := player.stream as AudioStreamWAV
	_check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end > 100000, "it is a forward loop covering the whole file (loop end %d frames)" % (stream.loop_end if stream != null else -1))
	_check(stream != null and stream.format == AudioStreamWAV.FORMAT_16_BITS, "the looping file is imported uncompressed (16-bit PCM), the format whose looping is certain")
	var shared := load("res://assets/audio/ambience.wav") as AudioStreamWAV
	_check(shared.loop_mode != AudioStreamWAV.LOOP_FORWARD, "the shared imported resource itself was not modified")
	_check(player.volume_db <= -24.0 + 0.5, "it starts silent and fades in (%.1f dB right after the start)" % player.volume_db)
	var children_before := audio.get_child_count()
	audio.play_ambience(-24.0, 0.4)
	audio.play_ambience(-24.0, 0.4)
	_check(audio.get_child_count() == children_before and audio.is_ambience_playing(), "calling it again never starts a second loop")
	await _wait(0.6)
	_check(absf(player.volume_db - (-24.0)) < 0.5, "after the fade it sits at its level (%.1f dB)" % player.volume_db)
	audio.stop_ambience(0.3)
	_check(audio.is_ambience_playing(), "stopping fades first, the sound is still there at once")
	await _wait(0.5)
	_check(not audio.is_ambience_playing(), "and then it stops")
	audio.queue_free()

# ---- 4. pause / resume ---------------------------------------------------------------------------------

func _t_pause() -> void:
	print("\n[4] PAUSE AND RESUME")
	var main: Node = load(MAIN_SCENE).instantiate()
	add_child(main)
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	var audio: GameAudio = main.get_node("Audio")
	audio.play(&"freed")
	audio.play(&"level_complete")
	await _frames(2)
	_check(audio.is_ambience_playing(), "the game scene's ambience is running")
	main._pause()
	await _frames(2)
	var all_paused := audio.ambience_player().stream_paused
	var holding := 0
	for child in audio.get_children():
		# (Godot keeps the pause flag only on a player that holds a stream; an idle pool player makes no sound and play() un-pauses it.)
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream != null:
			holding += 1
			if not (child as AudioStreamPlayer).stream_paused:
				all_paused = false
	all_paused = all_paused and holding >= 3
	_check(all_paused and audio.is_paused(), "pausing the game pauses the ambience and every cue player")
	var playing_cue: AudioStreamPlayer = null
	audio.play(&"ui_tap")  # the click of pressing RESUME while still paused
	for child in audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream == audio.cue_streams[&"ui_tap"] and (child as AudioStreamPlayer).playing:
			playing_cue = child
	_check(playing_cue != null and not playing_cue.stream_paused, "a click played while paused is not itself paused")
	main._timers.resume()
	GameManager.resume_game()
	await _frames(2)
	var any_paused := audio.ambience_player().stream_paused
	for child in audio.get_children():
		if child is AudioStreamPlayer and (child as AudioStreamPlayer).stream_paused:
			any_paused = true
	_check(not any_paused and not audio.is_paused(), "resuming un-pauses everything, where it left off")
	# Leaving the scene stops its sound with it.
	main.queue_free()
	await _frames(3)
	_check(not is_instance_valid(audio), "leaving the game scene frees its audio node (and so everything it was playing)")
	get_tree().paused = false

# ---- 5. main menu ---------------------------------------------------------------------------------------

func _t_menu() -> void:
	print("\n[5] MAIN MENU")
	var menu: MainMenu = load(MENU_SCENE).instantiate()
	add_child(menu)
	var changes: Array[String] = []
	var quits := [0]
	menu.scene_changer = func(path: String) -> void: changes.append(path)
	menu.app_quitter = func() -> void: quits[0] += 1
	var audio: GameAudio = menu.get_node("Audio")
	var heard: Array[StringName] = []
	audio.cue_requested.connect(func(cue: StringName, _i: float) -> void: heard.append(cue))
	await _frames(3)
	_check(audio.is_ambience_playing(), "the menu's forest ambience starts with the menu")
	var guard := Time.get_ticks_msec() + 3000
	while not menu.buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	menu.play_button().pressed.emit()
	menu.play_button().pressed.emit()
	menu.quit_button().pressed.emit()
	await _wait(0.7)
	_check(heard == [&"ui_play"], "PLAY makes exactly one sound, ui_play (double presses and QUIT after it make none): %s" % [heard])
	_check(changes == ["res://scenes/main/main.tscn"] and quits[0] == 0, "navigation is unchanged: PLAY still asks for the game scene once, QUIT did nothing after it")
	_check(not audio.is_ambience_playing(), "the ambience faded out and stopped with the screen fade")
	menu.queue_free()
	await _frames(2)
	var menu2: MainMenu = load(MENU_SCENE).instantiate()
	add_child(menu2)
	var quits2 := [0]
	menu2.app_quitter = func() -> void: quits2[0] += 1
	var audio2: GameAudio = menu2.get_node("Audio")
	var heard2: Array[StringName] = []
	audio2.cue_requested.connect(func(cue: StringName, _i: float) -> void: heard2.append(cue))
	guard = Time.get_ticks_msec() + 3000
	while not menu2.buttons_ready and Time.get_ticks_msec() < guard:
		await get_tree().process_frame
	menu2.quit_button().pressed.emit()
	await _wait(0.7)
	_check(heard2 == [&"ui_tap"] and quits2[0] == 1, "QUIT makes one soft click and still leaves the app once")
	menu2.queue_free()

# ---- 6. the game's button events and cues ----------------------------------------------------------------

func _t_game_events() -> void:
	print("\n[6] GAME EVENTS")
	var main: Node = load(MAIN_SCENE).instantiate()
	add_child(main)
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	main.scene_changer = func(_path: String) -> void: pass
	var audio: GameAudio = main.get_node("Audio")
	var heard: Array[StringName] = []
	audio.cue_requested.connect(func(cue: StringName, _i: float) -> void: heard.append(cue))
	var pause_menu: PauseMenu = main.get_node("PauseMenu")
	var failure: FailureScreen = main.get_node("FailureScreen")
	main._pause()
	main._open_pause_menu()
	await _frames(2)
	pause_menu.resume_requested.emit()
	await _frames(2)
	_check(heard == [&"ui_tap"] and GameManager.state != GameManager.State.PAUSED, "RESUME makes one soft click and still resumes the game")
	heard.clear()
	main._pause()
	main._open_pause_menu()
	await _frames(2)
	pause_menu.quit_requested.emit()
	await _frames(2)
	_check(heard == [&"ui_tap"], "the pause menu's MAIN MENU makes one soft click")
	heard.clear()
	failure.retry_requested.emit()
	failure.main_menu_requested.emit()
	_check(heard == [&"ui_tap", &"ui_tap"], "TRY AGAIN and the failure screen's MAIN MENU each make one soft click")
	# The existing gameplay cues still fire from the same places (no change there): a controlled trigger of a few of them.
	heard.clear()
	main.get_node("InputController").handle_tap(TapSide.Side.LEFT)
	await _frames(2)
	_check(heard.has(&"first_tap"), "the first tap still fires first_tap")
	main.queue_free()
	await _frames(2)
	get_tree().paused = false

# ---- 7. the loop boundary (Milestone 1.19: guards the Android crash fix) -------------------------------------

func _t_loop_boundary() -> void:
	print("\n[7] LOOP BOUNDARY")
	# The 1.18 build crashed on the phone ~20 s after launch, about when the 16 s ambience first wrapped. The loop now ends a few frames
	# BEFORE the end of the data. These checks pin that down; they cannot prove the cause (the headless dummy audio driver never runs the
	# real mixer), but they make sure the loop end can never silently go back to the very end of the buffer.
	var shared := load("res://assets/audio/ambience.wav") as AudioStreamWAV
	var frames := shared.data.size() / 2
	print("   ambience: %d frames, %d Hz, %.3f s" % [frames, shared.mix_rate, float(frames) / float(shared.mix_rate)])
	_check(shared.format == AudioStreamWAV.FORMAT_16_BITS and not shared.stereo and frames == 352800, "the ambience is 16-bit mono with 352800 frames (16 s at 22050 Hz)")
	var looped := GameAudio._make_loop(shared) as AudioStreamWAV
	print("   loop: begin %d, end %d (data ends at %d)" % [looped.loop_begin, looped.loop_end, frames])
	_check(looped.loop_end == frames - GameAudio.LOOP_END_MARGIN_FRAMES and looped.loop_end < frames, "the loop ends %d frames before the end of the data, never at it" % (frames - looped.loop_end))
	_check(GameAudio.LOOP_END_MARGIN_FRAMES >= 16 and GameAudio.LOOP_END_MARGIN_FRAMES <= 2000, "the margin is a few frames, not a large cut (%d frames = %.1f ms)" % [GameAudio.LOOP_END_MARGIN_FRAMES, 1000.0 * GameAudio.LOOP_END_MARGIN_FRAMES / 22050.0])
	_check(looped.loop_mode == AudioStreamWAV.LOOP_FORWARD and looped.loop_begin == 0 and looped.loop_begin < looped.loop_end, "a forward loop from the start")
	_check(looped.data.size() == shared.data.size() and shared.loop_mode != AudioStreamWAV.LOOP_FORWARD, "the audio data is untouched and the shared resource is not modified")
	# Every sample layout gets the same treatment (frames are bytes / bytes-per-frame).
	for spec in [["8-bit mono", AudioStreamWAV.FORMAT_8_BITS, false, 1], ["16-bit mono", AudioStreamWAV.FORMAT_16_BITS, false, 2], ["16-bit stereo", AudioStreamWAV.FORMAT_16_BITS, true, 4]]:
		var synthetic := AudioStreamWAV.new()
		synthetic.format = spec[1]
		synthetic.stereo = spec[2]
		synthetic.mix_rate = 22050
		var data := PackedByteArray()
		data.resize(5000 * int(spec[3]))
		synthetic.data = data
		var result := GameAudio._make_loop(synthetic) as AudioStreamWAV
		_check(result.loop_end == 5000 - GameAudio.LOOP_END_MARGIN_FRAMES and result.loop_end < 5000, "%s: the loop end is %d of 5000 frames, inside the data" % [spec[0], result.loop_end])
	_check(GameAudio._make_loop(null) == null, "a null stream gives no loop (no crash)")

# ---- 8. players and nodes are cleaned up --------------------------------------------------------------------

func _t_player_cleanup() -> void:
	print("\n[8] PLAYER CLEANUP")
	var audio := _new_audio()
	await _frames(2)
	audio.play_ambience(-24.0, 0.0)
	_check(audio.is_ambience_playing(), "the ambience starts")
	audio.stop_ambience(0.0)
	_check(not audio.is_ambience_playing(), "an instant stop stops it at once")
	for i in 3:
		audio.play_ambience(-24.0, 0.0)
		audio.stop_ambience(0.0)
	audio.play_ambience(-24.0, 0.0)
	var ambience_players := 0
	for child in audio.get_children():
		if child is AudioStreamPlayer and child.name == "Ambience":
			ambience_players += 1
	_check(ambience_players == 1 and audio.is_ambience_playing(), "start / stop / start again reuses the one player (%d ambience players)" % ambience_players)
	audio.queue_free()
	await _frames(3)
	var leftover := find_children("*", "AudioStreamPlayer", true, false).size()
	_check(leftover == 0, "after the audio node is freed no audio player is left in the tree (%d left)" % leftover)
	# Opening and closing the menu repeatedly leaves no players behind and never doubles the ambience.
	for i in 4:
		var menu: MainMenu = load(MENU_SCENE).instantiate()
		add_child(menu)
		await _frames(3)
		var menu_audio: GameAudio = menu.get_node("Audio")
		var loops := 0
		for child in menu_audio.get_children():
			if child is AudioStreamPlayer and child.name == "Ambience":
				loops += 1
		_check(loops == 1 and menu_audio.is_ambience_playing(), "menu open %d: exactly one ambience loop is playing" % (i + 1))
		menu.queue_free()
		await _frames(3)
	var after_menus := find_children("*", "AudioStreamPlayer", true, false).size()
	_check(after_menus == 0, "after four menu open/close cycles no audio player is left (%d left)" % after_menus)

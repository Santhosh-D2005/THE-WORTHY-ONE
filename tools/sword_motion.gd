extends Node
## Measures how the sword MOVES on screen while the player taps at different speeds (desktop run).
##   godot --path . res://tools/sword_motion.tscn
## Pixels are "phone render pixels": the phone renders the 3D scene at 0.6 x 720 = 432 px wide, so one
## 1080-wide viewport unit = 0.4 render pixels. A render pixel is the smallest step the player can see.
## The bar really rises (level-1 gain, no decay) so the vertical motion is the real motion, not a frozen sword.
## Reported per tapping speed (alternating in-rhythm taps, 3 s each):
##   x_range_px         sideways peak-to-peak movement of the pommel (a calm sword barely moves sideways)
##   x_reversals_ps     sideways direction flips per second (vibration)
##   y_reversals_ps     vertical direction flips per second: the sword should only ever rise while progress rises
##   y_speed_jerk_px    biggest frame-to-frame change of vertical speed (pops / stepping)
##   y_step_max_px      biggest single-frame vertical move
##   height_error_px    worst difference between the drawn height and the height implied by progress (0 = glued)

const PHONE_RENDER_PX_PER_VIEWPORT_UNIT := 432.0 / 1080.0

func _ready() -> void:
	get_window().size = Vector2i(540, 960)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	var input: InputController = main.get_node("InputController")
	var sword: SwordController = main.get_node("Stage/Sword")
	var camera: Camera3D = main.get_node("Stage/Camera3D")
	var extraction: ExtractionManager = main.get_node("ExtractionManager")
	while GameManager.state != GameManager.State.READY:
		await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout  # let the landing camera-shake die out (it would move the whole view)
	var results := {}
	var pommel := Vector3(0.0, SwordController.BLADE_LENGTH + 0.07 + SwordController.GRIP_LENGTH + 0.155, 0.0)
	for interval_msec in [300, 220, 120, 70]:
		extraction.reset()
		extraction.set_active(true)
		extraction.configure(100.0 / 15.0, 0.0, 5.0)  # the real level-1 gain (1.8: 15 taps = 6.67 % per tap), no decay; at most 12 taps are sent so the level never completes
		sword.set_progress(0.0)
		input.reset_alternation()
		await get_tree().create_timer(0.4).timeout
		var xs: Array[float] = []
		var ys: Array[float] = []
		var errors: Array[float] = []
		var next_tap := Time.get_ticks_msec()
		var left := true
		var taps_sent := 0
		var start := Time.get_ticks_msec()
		while Time.get_ticks_msec() - start < 3000:
			if Time.get_ticks_msec() >= next_tap and taps_sent < 12:
				taps_sent += 1
				input.handle_tap(TapSide.Side.LEFT if left else TapSide.Side.RIGHT)
				left = not left
				next_tap += interval_msec
			await get_tree().process_frame
			var screen: Vector2 = camera.unproject_position(sword._visual.to_global(pommel))
			xs.append(screen.x * PHONE_RENDER_PX_PER_VIEWPORT_UNIT)
			ys.append(screen.y * PHONE_RENDER_PX_PER_VIEWPORT_UNIT)
			var ideal := camera.unproject_position(Vector3(0.0, sword._rest_position.y + extraction.progress / 100.0 * sword.full_lift + pommel.y, 0.0))
			errors.append(absf(ideal.y * PHONE_RENDER_PX_PER_VIEWPORT_UNIT - ys[ys.size() - 1]))
		results[interval_msec] = _metrics(xs, ys, errors, 3.0)
	print("\nSword motion while tapping (phone render pixels, 3 s per speed, 12 real taps at the level-1 gain)")
	print("  tap gap | x_range | x_rev/s | y_rev/s | y_jerk | y_step_max | height_error")
	for interval_msec in results:
		var m: Dictionary = results[interval_msec]
		print("  %4d ms | %7.2f | %7.1f | %7.1f | %6.2f | %10.2f | %12.2f" % [interval_msec, m["x_range"], m["x_rev"], m["y_rev"], m["y_jerk"], m["y_step"], m["height_error"]])
	get_tree().quit()

func _reversals(values: Array[float]) -> int:
	var count := 0
	var previous_sign := 0
	for i in range(1, values.size()):
		var d := values[i] - values[i - 1]
		if absf(d) < 0.02:
			continue  # sub-1/50-pixel changes are not visible
		var sign_now := 1 if d > 0.0 else -1
		if previous_sign != 0 and sign_now != previous_sign:
			count += 1
		previous_sign = sign_now
	return count

func _metrics(xs: Array[float], ys: Array[float], errors: Array[float], seconds: float) -> Dictionary:
	var jerk := 0.0
	var step := 0.0
	for i in range(2, ys.size()):
		var v1 := ys[i] - ys[i - 1]
		var v0 := ys[i - 1] - ys[i - 2]
		jerk = maxf(jerk, absf(v1 - v0))
		step = maxf(step, absf(v1))
	return {
		"x_range": (xs.max() as float) - (xs.min() as float),
		"x_rev": float(_reversals(xs)) / seconds,
		"y_rev": float(_reversals(ys)) / seconds,
		"y_jerk": jerk, "y_step": step,
		"height_error": errors.max() as float,
	}

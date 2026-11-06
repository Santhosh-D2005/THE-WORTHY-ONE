class_name GameplayCamera
extends Camera3D
## Fixed cinematic camera framing the stump in portrait, with a small impact shake.
##
## FRAMING ACROSS ASPECT RATIOS: the design is 9:16 with a 50 degree HORIZONTAL field of view.
## - Taller than 9:16 (most modern phones): keep that horizontal FOV. The stump keeps its width and
##   more forest appears above and below.
## - Wider than 9:16 (tablets): keeping the horizontal FOV would zoom in and crop the top and
##   bottom, so the VERTICAL field of view of the 9:16 design is kept instead. The composition
##   (stump, sword, headroom) stays the same and extra forest appears at the sides.
## At exactly 9:16 both rules give the identical image.

const DESIGN_ASPECT := 1080.0 / 1920.0
const DESIGN_HORIZONTAL_FOV := 50.0

@export var camera_position: Vector3 = Vector3(0.0, 3.5, 5.1)
@export var look_target: Vector3 = Vector3(0.0, 1.7, 0.0)
@export var shake_strength: float = 0.09

var _base_fov: float = DESIGN_HORIZONTAL_FOV
## Added to the framing FOV (degrees). Kept for tests and tools; the extraction no longer uses it (1.8: the camera now
## moves physically - it creeps in while the sword resists, then rises with the blade - instead of zooming).
var extra_fov: float = 0.0:
	set(value):
		extra_fov = value
		fov = _base_fov + extra_fov

## Phase A, the final resistance: from 70 % progress on the camera creeps toward the sword (up to TENSION_DOLLY units
## at 100 %), smoothly, so rapid taps never make it jump. It eases back if progress is lost.
const TENSION_DOLLY := 0.30
## Phase C, the reward: the camera follows the freed blade upward and moves in a little more.
const RELEASE_DOLLY := 0.55     # + RELEASE_DOLLY_EXTRA x level strength
const RELEASE_DOLLY_EXTRA := 0.30
const RELEASE_LIFT := 0.55      # how far the aim point rises with the blade (+ extra)
const RELEASE_LIFT_EXTRA := 0.30
const RELEASE_RISE_SECONDS := 0.45
const RELEASE_RETURN_SECONDS := 0.70
var _tension_target: float = 0.0
var _tension_shown: float = 0.0
var _locked: bool = false           # true during the release: progress no longer drives the tension
var _release: float = 0.0           # 0..1, tweened by impact()
var _release_dolly: float = RELEASE_DOLLY
var _release_lift: float = RELEASE_LIFT
var _release_tween: Tween = null
var _shake_time: float = 0.0
var _pose_dirty: bool = true

func _ready() -> void:
	_apply_pose()
	update_framing()
	get_viewport().size_changed.connect(update_framing)

## Choose which FOV axis stays fixed for the current window aspect ratio.
func update_framing() -> void:
	var size := get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	if aspect > DESIGN_ASPECT + 0.001:
		keep_aspect = Camera3D.KEEP_HEIGHT
		_base_fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(DESIGN_HORIZONTAL_FOV * 0.5)) / DESIGN_ASPECT))
	else:
		keep_aspect = Camera3D.KEEP_WIDTH
		_base_fov = DESIGN_HORIZONTAL_FOV
	fov = _base_fov + extra_fov

## Extraction progress 0..100 -> how tense the pull is (0 below 70 %, 1 at 100 %).
func set_tension_from_progress(progress: float) -> void:
	if _locked:
		return
	_tension_target = smoothstep(70.0, 100.0, progress)

func tension() -> float:
	return _tension_shown

## Distance (world units) the camera has moved toward the sword from its framing position.
func dolly_amount() -> float:
	return camera_position.distance_to(position)

## The sword has come free. A short, DETERMINISTIC damped thump (no random), and the camera rises with the blade:
## up in RELEASE_RISE_SECONDS, stays while the sword hangs, then returns so that it is back at its framing exactly
## `total_seconds` from now (the end of the sequence). `strength` 0..1 grows with the level.
func impact(strength: float, total_seconds: float = 2.0) -> void:
	strength = clampf(strength, 0.0, 1.0)
	shake(0.30 + 0.25 * strength)
	_locked = true
	_tension_target = 0.0
	_release_dolly = RELEASE_DOLLY + RELEASE_DOLLY_EXTRA * strength
	_release_lift = RELEASE_LIFT + RELEASE_LIFT_EXTRA * strength
	if _release_tween != null:
		_release_tween.kill()
	_release_tween = create_tween()
	_release_tween.tween_property(self, "_release", 1.0, RELEASE_RISE_SECONDS).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	var stay := maxf(0.0, total_seconds - RELEASE_RISE_SECONDS - RELEASE_RETURN_SECONDS)
	_release_tween.tween_interval(stay)
	_release_tween.tween_property(self, "_release", 0.0, RELEASE_RETURN_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_release_tween.tween_callback(func() -> void:
		_locked = false
		_pose_dirty = true)

## Back to the plain framing at once (new run / failure).
func reset_framing() -> void:
	if _release_tween != null:
		_release_tween.kill()
	_release = 0.0
	_locked = false
	_tension_target = 0.0
	_tension_shown = 0.0
	_trauma = 0.0
	h_offset = 0.0
	v_offset = 0.0
	_pose_dirty = true

var _trauma: float = 0.0

func shake(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)

func _process(delta: float) -> void:
	if not is_equal_approx(_tension_shown, _tension_target):
		# Frame-rate independent smoothing; settles exactly so the camera stops updating.
		_tension_shown = lerpf(_tension_shown, _tension_target, 1.0 - exp(-6.0 * delta))
		if absf(_tension_shown - _tension_target) < 0.0005:
			_tension_shown = _tension_target
		_pose_dirty = true
	if _release_tween != null and _release_tween.is_running():
		_pose_dirty = true
	if _pose_dirty:
		_apply_pose()
	if _trauma > 0.0:
		_trauma = maxf(0.0, _trauma - delta * 2.4)
		_shake_time += delta
		var amplitude := _trauma * _trauma * shake_strength
		# Two fixed, unrelated frequencies: a steady damped tremor that always looks the same.
		h_offset = sin(_shake_time * 47.0) * amplitude
		v_offset = sin(_shake_time * 61.0 + 1.3) * amplitude
		if _trauma == 0.0:
			h_offset = 0.0
			v_offset = 0.0

func _apply_pose() -> void:
	_pose_dirty = false
	var forward := (look_target - camera_position).normalized()
	# max(): while the release takes over, the fading tension must never pull the camera back for a moment.
	var dolly := maxf(TENSION_DOLLY * _tension_shown, _release_dolly * _release)
	var aim := look_target + Vector3.UP * (_release_lift * _release)
	look_at_from_position(camera_position + forward * dolly, aim)

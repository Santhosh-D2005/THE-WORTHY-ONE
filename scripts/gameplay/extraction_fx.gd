class_name ExtractionFx
extends Node
## Milestones 1.11-1.14: the ONE shared state behind the forest compression, the stump cracks and the amber glow.
##
## There is a single authoritative number, `strain` (0..1): the extraction progress smoothed by a frame-rate independent
## exponential follow. Everything visual is a pure function of it (compression = strain, cracks = strain, glow = glow_for(strain)
## x a gate), so the effects can never drift apart and, because strain follows the real progress, they recede whenever progress does
## and are exactly zero at zero progress. There are no per-effect timers.
##   follow     strain chases progress / 100 (FOLLOW_RATE)
##   anticipate the last tap landed: strain is pushed to 1 fast (ANTICIPATION_RATE), so cracks and glow are at their maximum
##              before the blade is released; progress no longer drives it
##   release    the blade is free: strain falls smoothly (RELEASE_RATE) and the glow gate closes first (GLOW_FADE_RATE), so the
##              forest unwinds while the empty stump quietly goes dark
##   fade_out   failure: strain falls quickly to zero
##   reset      a new attempt / level: everything snaps to the baseline
## The node is pausable (a child of the Stage) and switches its own _process off whenever nothing is changing.

const FOLLOW_RATE := 6.0
const ANTICIPATION_RATE := 14.0
const RELEASE_RATE := 3.0
const FAILURE_RATE := 6.0
const GLOW_FADE_RATE := 4.5

var strain: float = 0.0
var glow_gate: float = 1.0
var _target: float = 0.0
var _rate: float = FOLLOW_RATE
var _locked: bool = false
var _releasing: bool = false
var _forest: ForestEnvironment
var _stump: StumpBuilder
var _compression_on := true
var _cracks_on := true
var _applied_strain := -1.0
var _applied_gate := -1.0

func setup(forest: ForestEnvironment, stump: StumpBuilder) -> void:
	_forest = forest
	_stump = stump
	var args := RenderQuality.launch_arguments()  # debug builds only: measuring switches
	if "--no-fx" in args:
		_compression_on = false
		_cracks_on = false
	if "--no-compress" in args:
		_compression_on = false
	if "--no-cracks" in args:
		_cracks_on = false
	set_process(false)

## The brightness of the glow for a strain: 0 at 0, restrained (about 0.3) at 25 %, 0.5 at 50 %, 0.75 at 75 %, 1 at 100 %.
static func glow_for(value: float) -> float:
	value = clampf(value, 0.0, 1.0)
	return smoothstep(0.03, 0.15, value) * lerpf(0.15, 1.0, pow(value, 1.3))

func set_progress(progress: float) -> void:
	if _locked:
		return
	_target = clampf(progress / 100.0, 0.0, 1.0)
	_rate = FOLLOW_RATE
	set_process(true)

func anticipate() -> void:
	_locked = true
	_target = 1.0
	_rate = ANTICIPATION_RATE
	set_process(true)

func release() -> void:
	_locked = true
	_releasing = true
	_target = 0.0
	_rate = RELEASE_RATE
	set_process(true)

func fade_out() -> void:
	_locked = true
	_target = 0.0
	_rate = FAILURE_RATE
	set_process(true)

func reset() -> void:
	strain = 0.0
	glow_gate = 1.0
	_target = 0.0
	_rate = FOLLOW_RATE
	_locked = false
	_releasing = false
	_apply(true)
	set_process(false)

func _process(delta: float) -> void:
	var blend := 1.0 - exp(-_rate * delta)
	strain = lerpf(strain, _target, blend)
	if absf(strain - _target) < 0.0005:
		strain = _target
	if _releasing:
		glow_gate = lerpf(glow_gate, 0.0, 1.0 - exp(-GLOW_FADE_RATE * delta))
		if glow_gate < 0.002:
			glow_gate = 0.0
	_apply(false)
	if strain == _target and (not _releasing or glow_gate == 0.0):
		set_process(false)

func _apply(force: bool) -> void:
	if not force and is_equal_approx(strain, _applied_strain) and is_equal_approx(glow_gate, _applied_gate):
		return
	_applied_strain = strain
	_applied_gate = glow_gate
	if _compression_on and _forest != null:
		_forest.set_compression(strain)
	if _cracks_on and _stump != null:
		_stump.set_cracks(strain, glow_for(strain) * glow_gate)

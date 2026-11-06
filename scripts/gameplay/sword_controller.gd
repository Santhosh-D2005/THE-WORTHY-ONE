class_name SwordController
extends Node3D
## Builds the PLACEHOLDER sword and drives all of its motion.
##
## Height is a direct function of extraction progress:  y = rest_y + progress/100 * full_lift.
## Only the visual smoothing and tap "kick" are layered on top, so the sword can never look
## disconnected from the real progress value.
##
## Local space: origin = blade tip, +Y = up the blade. The node sits inside the cut face.
## To use a Blender sword: replace _build_placeholder_visuals() with an instanced model
## whose origin is also at the blade tip.

signal planted  ## The new sword has landed in the stump (camera shake / thud hook).
signal failure_settled  ## The failure animation finished; the sword is exactly at its embedded rest pose.

const BLADE_LENGTH := 1.6
const BLADE_WIDTH := 0.19
const BLADE_THICKNESS := 0.04
const GUARD_WIDTH := 0.8
const GRIP_LENGTH := 0.42

## How deep the blade is embedded at 0% progress.
@export var embed_depth: float = 0.9
## Vertical travel from 0% to 100% progress. Equal to embed_depth, so the tip reaches the wood
## surface at 100% and the finish animation lifts the sword fully clear.
@export var full_lift: float = 0.9
## Stiffness (rad/s) of the critically damped spring that carries the drawn height to the real progress.
## 24 = within 2 % of a progress step after about 0.25 s, no overshoot, and the speed changes smoothly (no
## start/stop pops), so rapid taps merge into one continuous rise.
@export var follow_speed: float = 24.0
## Where the cut surface is (world Y); sword rest position derives from it.
@export var stump_top_y: float = 1.0

var _visual: Node3D
var _rest_position: Vector3
var _progress: float = 0.0
var _display_progress: float = 0.0
var _kick: float = 0.0       # 0..1 impulse set by each valid tap, decays quickly
var _progress_velocity: float = 0.0  # speed of the critically damped height spring (progress points / s)
var _strain: float = 0.0     # 0..1 low-level tremble while the sword slips back
var _slipping: bool = false
var _animating: bool = false      # sword is in (or between) scripted animations; ignores taps
var _tween_running: bool = false  # a scripted tween is active; blocks overlapping animations
var _settling: bool = false       # the extraction anticipation: the height spring still runs, so the blade reaches 100 %
var _time: float = 0.0

## MILESTONE 1.10, micro-motion: ONE rigid object moves a hair under the player's effort. Every valid tap sets an "effort" of 1 that
## fades over about half a second; the blade leans and shifts a few millimetres to alternating sides and rises a hair, all of it
## through critically damped springs (heavy, never springy, no overshoot) and all of it bounded by the constants below. It is
## pure object-level translation and roll of `_visual` (no bending, no scaling), it ends exactly at zero when tapping stops, and
## it is wiped by reset_pose / the failure / the extraction. The blade's height is still only a function of progress.
const MICRO_SIDE := 0.006        # metres: sideways shift (peak, at high progress)
const MICRO_ROLL := 0.009        # radians: lean about the embedded point (peak)
const MICRO_UP := 0.005          # metres: the tiny "effort" lift on top of the real height
const MICRO_OMEGA := 12.0        # rad/s of the critically damped springs
const MICRO_SETTLE_OMEGA := 30.0 # the final anticipation: the residue is gone before the release
const MICRO_EFFORT_FADE := 1.8   # effort per second
var _micro_effort: float = 0.0
var _micro_sign: float = 1.0
var _micro_last_flip: float = -10.0  # the lean changes side at most once per MICRO_FLIP_SECONDS, whatever the tap rate: a slow rocking, never a per-tap shake
const MICRO_FLIP_SECONDS := 0.45
var _micro_x := Vector2.ZERO     # (value, velocity) of each channel
var _micro_y := Vector2.ZERO
var _micro_roll := Vector2.ZERO

func _ready() -> void:
	_rest_position = Vector3(0.0, stump_top_y - embed_depth, 0.0)
	position = _rest_position
	_visual = Node3D.new()
	_visual.name = "Visual"
	add_child(_visual)
	var t := PerfProbe.begin()
	_build_placeholder_visuals()
	PerfProbe.end("sword_build", t)
	call_deferred("_build_slot")

func _build_placeholder_visuals() -> void:
	var steel := MaterialFactory.steel()
	var dark_steel := MaterialFactory.dark_steel()
	var gold := MaterialFactory.aged_gold()
	var leather := MaterialFactory.leather()

	# Faceted blade (hexagonal lens section) with a recessed fuller on both faces.
	_add_mesh("Blade", _make_blade_mesh(), Vector3.ZERO, steel)
	var fuller_start := 0.42
	var fuller_length := BLADE_LENGTH - 0.12 - fuller_start
	_add_box("Fuller", Vector3(0.035, fuller_length, BLADE_THICKNESS * 2.0 + 0.004),
		Vector3(0, fuller_start + fuller_length * 0.5, 0), dark_steel)

	# Cross-guard: central block, two arms that sweep slightly toward the blade, ball finials.
	var guard_y := BLADE_LENGTH + 0.035
	_add_box("GuardCenter", Vector3(0.18, 0.1, 0.12), Vector3(0, guard_y, 0), gold)
	for side in [-1.0, 1.0]:
		var previous := Vector3(side * 0.09, guard_y, 0.0)
		for step in 3:
			var f := float(step + 1) / 3.0
			var next := Vector3(side * (0.09 + f * 0.30), guard_y - f * f * 0.05, 0.0)
			_add_limb("GuardArm", previous, next, 0.032 - f * 0.008, gold)
			previous = next
		var finial := SphereMesh.new()
		finial.radius = 0.04
		finial.height = 0.08
		finial.radial_segments = 10
		finial.rings = 5
		_add_mesh("GuardFinial", finial, previous, gold)

	# Grip: leather core with raised wrap bands, then a faceted pommel.
	var grip_start := BLADE_LENGTH + 0.07
	var grip := CylinderMesh.new()
	grip.top_radius = 0.032
	grip.bottom_radius = 0.032
	grip.height = GRIP_LENGTH
	grip.radial_segments = 14
	_add_mesh("Grip", grip, Vector3(0, grip_start + GRIP_LENGTH * 0.5, 0), leather)
	var band_count := 7
	for band in band_count:
		var ring := CylinderMesh.new()
		ring.top_radius = 0.039
		ring.bottom_radius = 0.039
		ring.height = 0.022
		ring.radial_segments = 14
		_add_mesh("GripBand", ring, Vector3(0, grip_start + 0.035 + float(band) * (GRIP_LENGTH - 0.07) / float(band_count - 1), 0), dark_steel)
	var collar := CylinderMesh.new()
	collar.top_radius = 0.05
	collar.bottom_radius = 0.06
	collar.height = 0.04
	collar.radial_segments = 14
	_add_mesh("GripCollar", collar, Vector3(0, grip_start + GRIP_LENGTH + 0.02, 0), gold)
	var pommel := SphereMesh.new()
	pommel.radius = 0.07
	pommel.height = 0.12
	pommel.radial_segments = 10
	pommel.rings = 5
	_add_mesh("Pommel", pommel, Vector3(0, grip_start + GRIP_LENGTH + 0.085, 0), gold)

## Blade: sections along Y, each a six-point lens. Width swells after the point, then tapers
## slightly toward the guard. Flat shading (non-indexed triangles) keeps the bevel facets crisp.
func _make_blade_mesh() -> ArrayMesh:
	var half_width := BLADE_WIDTH * 0.5
	var half_thick := BLADE_THICKNESS * 0.5
	# [height along blade, width scale, thickness scale]
	var sections: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(0.10, 0.55, 0.7),
		Vector3(0.38, 1.0, 1.0),
		Vector3(BLADE_LENGTH * 0.7, 0.96, 1.0),
		Vector3(BLADE_LENGTH, 0.88, 1.0),
	]
	var rings: Array[PackedVector3Array] = []
	for section in sections:
		var w := half_width * section.y
		var t := half_thick * section.z
		var y := section.x
		rings.append(PackedVector3Array([
			Vector3(-w, y, 0.0), Vector3(-w * 0.32, y, t), Vector3(w * 0.32, y, t),
			Vector3(w, y, 0.0), Vector3(w * 0.32, y, -t), Vector3(-w * 0.32, y, -t),
		]))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in rings.size() - 1:
		for i in 6:
			var j := (i + 1) % 6
			_add_oriented_triangle(surface, rings[r][i], rings[r + 1][i], rings[r][j])
			_add_oriented_triangle(surface, rings[r][j], rings[r + 1][i], rings[r + 1][j])
	# Flat end under the guard.
	var top := rings[rings.size() - 1]
	var top_center := Vector3(0, BLADE_LENGTH, 0)
	for i in 6:
		_add_oriented_triangle(surface, top_center, top[i], top[(i + 1) % 6])
	surface.generate_normals()
	return surface.commit()

## Adds a triangle wound (clockwise = front in Godot) so its face points away from the blade axis (+Y through origin).
func _add_oriented_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	var center := (a + b + c) / 3.0
	var outward := Vector3(center.x, 0.0, center.z)
	if center.x == 0.0 and center.z == 0.0:
		outward = Vector3.UP
	if normal.dot(outward) > 0.0:  # Godot front faces are clockwise
		var swap := b
		b = c
		c = swap
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

## A short tapered cylinder between two points (guard arms).
func _add_limb(node_name: String, from_point: Vector3, to_point: Vector3, radius: float, material: Material) -> void:
	var offset := to_point - from_point
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.8
	mesh.bottom_radius = radius
	mesh.height = offset.length()
	mesh.radial_segments = 8
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	var y_axis := offset.normalized()
	var x_axis := y_axis.cross(Vector3.FORWARD).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	instance.transform = Transform3D(Basis(x_axis, y_axis, z_axis), (from_point + to_point) * 0.5)
	_visual.add_child(instance)

func _add_box(node_name: String, size: Vector3, offset: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add_mesh(node_name, mesh, offset, material)

func _add_mesh(node_name: String, mesh: Mesh, offset: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	_visual.add_child(instance)

# ---- Level 9999: the final sword ---------------------------------------------------------------
## For the last level the same blade is dressed in gold: polished glowing metal, a winged cross-guard, gems, runes up the fuller, a halo behind
## it and a pulsing aura. All of it is extra nodes under `_visual` plus a material swap; switching it off puts every original material back.
const AURA_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.35, 1.0);
uniform float intensity = 1.0;
void fragment() {
	float f = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float pulse = 0.72 + 0.28 * sin(TIME * 2.4 + UV.y * 7.0);
	ALBEDO = glow_color.rgb * f * intensity * pulse * 2.2;
	ALPHA = clamp(f * 0.95, 0.0, 1.0);
}
"""

var _finale_nodes: Array[Node3D] = []
var _finale_original: Dictionary = {}
var _finale_built: bool = false
var _finale_on: bool = false

func is_finale() -> bool:
	return _finale_on

func apply_finale(on: bool) -> void:
	if on == _finale_on:
		return
	_finale_on = on
	if on and not _finale_built:
		_build_finale_ornaments()
	for node in _finale_nodes:
		node.visible = on
	var polished := _finale_material(Color(0.93, 0.86, 0.66), 1.0, 0.18, Color(1.0, 0.75, 0.32), 0.35)
	var gold := _finale_material(Color(1.0, 0.78, 0.30), 1.0, 0.22, Color(1.0, 0.62, 0.15), 0.8)
	var glow := _finale_material(Color(1.0, 0.85, 0.5), 0.6, 0.3, Color(1.0, 0.72, 0.25), 3.2)
	var wrap := _finale_material(Color(0.12, 0.07, 0.04), 0.2, 0.55, Color(1.0, 0.55, 0.15), 0.25)
	for child in _visual.get_children():
		var part := child as MeshInstance3D
		if part == null or part in _finale_nodes:
			continue
		if on:
			_finale_original[part] = part.material_override
			var swap: Material = gold
			match str(part.name).rstrip("0123456789"):
				"Blade": swap = polished
				"Fuller": swap = glow
				"Grip": swap = wrap
			part.material_override = swap
		elif _finale_original.has(part):
			part.material_override = _finale_original[part]
	if not on:
		_finale_original.clear()

func _finale_material(color: Color, metallic: float, roughness: float, emission: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.emission_enabled = true
	material.emission = emission
	material.emission_energy_multiplier = energy
	return material

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _finale_add(node_name: String, mesh: Mesh, offset: Vector3, material: Material, rotation_euler: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.position = offset
	instance.rotation = rotation_euler
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(instance)
	_finale_nodes.append(instance)
	return instance

func _build_finale_ornaments() -> void:
	_finale_built = true
	var gold := _finale_material(Color(1.0, 0.78, 0.30), 1.0, 0.22, Color(1.0, 0.62, 0.15), 0.9)
	var guard_y := BLADE_LENGTH + 0.035
	var grip_start := BLADE_LENGTH + 0.07
	# Winged cross-guard: four layered feathers on each side, sweeping up and out.
	for side in [-1.0, 1.0]:
		for i in 4:
			var feather := PrismMesh.new()
			feather.size = Vector3(0.34 - float(i) * 0.05, 0.05, 0.07)
			_finale_add("FinaleWing", feather, Vector3(side * (0.34 + float(i) * 0.075), guard_y + 0.045 + float(i) * 0.062, 0.0), gold,
				Vector3(0.0, 0.0, side * (-0.28 - float(i) * 0.20)))
		var tip := SphereMesh.new()
		tip.radius = 0.028
		tip.height = 0.056
		_finale_add("FinaleWingTip", tip, Vector3(side * 0.80, guard_y + 0.36, 0.0), _glow_material(Color(1.0, 0.82, 0.45), 3.0))
	# Gems: a ruby in the middle of the guard (both faces) and a pale star-stone on the pommel.
	var ruby := SphereMesh.new()
	ruby.radius = 0.052
	ruby.height = 0.104
	ruby.radial_segments = 12
	ruby.rings = 6
	_finale_add("FinaleRubyFront", ruby, Vector3(0.0, guard_y, 0.07), _glow_material(Color(1.0, 0.18, 0.12), 3.4))
	_finale_add("FinaleRubyBack", ruby, Vector3(0.0, guard_y, -0.07), _glow_material(Color(1.0, 0.18, 0.12), 3.4))
	var star_stone := SphereMesh.new()
	star_stone.radius = 0.05
	star_stone.height = 0.10
	_finale_add("FinaleStarStone", star_stone, Vector3(0.0, grip_start + GRIP_LENGTH + 0.175, 0.0), _glow_material(Color(0.7, 0.9, 1.0), 3.6))
	for k in 5:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 0.022
		spike.height = 0.085
		var angle := TAU * float(k) / 5.0
		_finale_add("FinalePommelSpike", spike, Vector3(cos(angle) * 0.055, grip_start + GRIP_LENGTH + 0.14, sin(angle) * 0.055), gold,
			Vector3(sin(angle) * 0.5, 0.0, -cos(angle) * 0.5))
	# Runes up both faces of the fuller, three alternating shapes.
	var rune_material := _glow_material(Color(1.0, 0.80, 0.38), 3.4)
	for r in 8:
		var y := 0.55 + float(r) * 0.115
		for face in [-1.0, 1.0]:
			var z: float = face * (BLADE_THICKNESS + 0.008)
			match r % 3:
				0:
					var bar := BoxMesh.new()
					bar.size = Vector3(0.05, 0.012, 0.008)
					_finale_add("FinaleRune", bar, Vector3(0.0, y, z), rune_material)
					var stem := BoxMesh.new()
					stem.size = Vector3(0.012, 0.05, 0.008)
					_finale_add("FinaleRune", stem, Vector3(0.0, y, z), rune_material)
				1:
					var diamond := BoxMesh.new()
					diamond.size = Vector3(0.03, 0.03, 0.008)
					_finale_add("FinaleRune", diamond, Vector3(0.0, y, z), rune_material, Vector3(0.0, 0.0, PI * 0.25))
				_:
					var tick := BoxMesh.new()
					tick.size = Vector3(0.012, 0.06, 0.008)
					_finale_add("FinaleRune", tick, Vector3(-0.025, y, z), rune_material)
					_finale_add("FinaleRune", tick, Vector3(0.025, y, z), rune_material)
	# Gold wire wrapped round the grip.
	for b in 5:
		var wire := TorusMesh.new()
		wire.inner_radius = 0.034
		wire.outer_radius = 0.041
		wire.rings = 14
		wire.ring_segments = 6
		_finale_add("FinaleWire", wire, Vector3(0.0, grip_start + 0.06 + float(b) * 0.075, 0.0), gold)
	# A halo behind the blade and the aura that wraps it.
	var halo := TorusMesh.new()
	halo.inner_radius = 0.86
	halo.outer_radius = 0.90
	halo.rings = 48
	halo.ring_segments = 6
	_finale_add("FinaleHalo", halo, Vector3(0.0, 1.05, -0.16), _glow_material(Color(1.0, 0.76, 0.34), 2.6), Vector3(PI * 0.5, 0.0, 0.0))
	var halo_inner := TorusMesh.new()
	halo_inner.inner_radius = 0.60
	halo_inner.outer_radius = 0.615
	halo_inner.rings = 48
	halo_inner.ring_segments = 4
	_finale_add("FinaleHaloInner", halo_inner, Vector3(0.0, 1.05, -0.17), _glow_material(Color(1.0, 0.9, 0.6), 2.2), Vector3(PI * 0.5, 0.0, 0.0))
	var shader := Shader.new()
	shader.code = AURA_SHADER
	var aura := ShaderMaterial.new()
	aura.shader = shader
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.15
	capsule.height = 1.95
	capsule.radial_segments = 16
	capsule.rings = 8
	var aura_node := _finale_add("FinaleAura", capsule, Vector3(0.0, 0.95, 0.0), aura)
	aura_node.scale = Vector3(1.0, 1.0, 0.55)
	for node in _finale_nodes:
		node.visible = false

# ---- Gameplay hooks ----------------------------------------------------------------------

## Mirror the authoritative progress value (0..100).
func set_progress(value: float) -> void:
	_progress = value

## A valid tap: instant micro-jolt whose size grows with progress.
func on_valid_tap() -> void:
	if _animating:
		return
	_kick = 1.0
	_micro_effort = 1.0
	if _time - _micro_last_flip >= MICRO_FLIP_SECONDS:
		_micro_sign = -_micro_sign
		_micro_last_flip = _time

func set_slipping(value: bool) -> void:
	_slipping = value

## Failure animation timing and "seating" spring (all deterministic, nothing random).
const FAILURE_DURATION := 0.9
const FAILURE_SETTLE_FRACTION := 0.6    # the position eases in over this share of the duration
const FAILURE_SPRING_AMPLITUDE := 0.014 # how far the sword briefly sinks while the wood grips it
const FAILURE_SPRING_DECAY := 7.0       # 1/s, how fast the seating motion dies out
const FAILURE_SPRING_FREQUENCY := 24.0  # rad/s

## Reset to the embedded pose at 0% (used between attempts).
func reset_pose() -> void:
	_progress = 0.0
	_display_progress = 0.0
	_kick = 0.0
	_progress_velocity = 0.0
	_strain = 0.0
	_slipping = false
	position = _rest_position
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	_settling = false
	_clear_micro()
	_show_slot(false)

func _clear_micro() -> void:
	_micro_effort = 0.0
	_micro_last_flip = -10.0
	_micro_x = Vector2.ZERO
	_micro_y = Vector2.ZERO
	_micro_roll = Vector2.ZERO

## One critically damped spring step (frame-rate independent). state = (value, velocity).
static func _spring(state: Vector2, target: float, omega: float, delta: float) -> Vector2:
	var x := omega * delta
	var damping := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := state.x - target
	var temp := (state.y + omega * change) * delta
	return Vector2(target + (change + temp) * damping, (state.y - omega * temp) * damping)

## The size of the micro-motion right now, as (sideways metres, lift metres, roll radians). Tests and tools read this.
func micro_offset() -> Vector3:
	return Vector3(_micro_x.x, _micro_y.x, _micro_roll.x)

# ---- Per-frame motion --------------------------------------------------------------------

func _process(delta: float) -> void:
	if _animating and not _settling:
		return
	_time += delta
	# Follow the real progress value with a critically damped spring (frame-rate independent, no overshoot,
	# continuous speed): the drawn height lags the real progress by about 0.1 s and never jerks.
	var omega := follow_speed
	var x := omega * delta
	var damping := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := _display_progress - _progress
	var temp := (_progress_velocity + omega * change) * delta
	_progress_velocity = (_progress_velocity - omega * temp) * damping
	_display_progress = _progress + (change + temp) * damping
	position = _rest_position + Vector3(0.0, _display_progress / 100.0 * full_lift, 0.0)

	_kick = move_toward(_kick, 0.0, delta * 7.0)
	_strain = move_toward(_strain, 1.0 if _slipping else 0.0, delta * 6.0)
	# MILESTONE 1.10: the micro-motion (see MICRO_*). History: 1.5 shook the blade sideways at 14 Hz on every tap, 1.6 thumped it, and
	# 1.7 removed all motion because the 1-pixel direction reversals crawled along the edges of the upscaled image. The new motion is
	# a heavy, critically damped lean (it can only flip direction once per tap and the springs low-pass it), small enough to stay a
	# few render pixels at most. Ownership: this function is the ONLY writer of _visual.position and _visual.rotation:z while
	# playing; the extraction tween owns _visual.rotation:y only (1.10 fixed the old per-frame "rotation = ZERO" that fought it).
	_micro_effort = move_toward(_micro_effort, 0.0, delta * MICRO_EFFORT_FADE)
	var shown := _micro_effort if not _settling else 0.0
	var gain := shown * (0.45 + 0.55 * clampf(_display_progress / 100.0, 0.0, 1.0))
	var micro_omega := MICRO_SETTLE_OMEGA if _settling else MICRO_OMEGA
	_micro_x = _spring(_micro_x, _micro_sign * gain * MICRO_SIDE, micro_omega, delta)
	_micro_y = _spring(_micro_y, gain * MICRO_UP, micro_omega, delta)
	_micro_roll = _spring(_micro_roll, -_micro_sign * gain * MICRO_ROLL, micro_omega, delta)
	if shown == 0.0 and absf(_micro_x.x) + absf(_micro_y.x) + absf(_micro_roll.x) < 0.00002 and absf(_micro_x.y) + absf(_micro_y.y) + absf(_micro_roll.y) < 0.0005:
		_clear_micro()  # fully settled: exactly the embedded pose, nothing left to drift
	_visual.position = Vector3(_micro_x.x, _micro_y.x, 0.0)
	_visual.rotation.z = _micro_roll.x
	if not _settling:
		_visual.rotation.x = 0.0
		_visual.rotation.y = 0.0

# ---- Success animation ---------------------------------------------------------------------

## Extraction timeline (seconds), Milestone 1.8. A = final resistance, B = release, C = reward, then the lift away.
##   A  EXTRACTION_ANTICIPATION_SECONDS  the last tap has landed; the blade finishes its smooth rise to the very top
##                                       (the height spring keeps running) and is gripped there for a heartbeat while the
##                                       camera is at its tightest. No shaking: the blade only rises, then stops.
##   B  `freed` is emitted: the blade leaves the wood in one decisive, fast pull (EXTRACTION_PULL_SECONDS, quint-out),
##                                       the empty cut in the stump becomes visible and the camera rises with it.
##   C  the freed sword floats a little higher, drifts toward the camera and turns slowly about its own axis while
##      the level card is read (the hold grows with the level), then
##      EXTRACTION_LIFT_SECONDS lifts it out of frame.
const EXTRACTION_ANTICIPATION_SECONDS := 0.20
const EXTRACTION_PULL_SECONDS := 0.35
const EXTRACTION_LIFT_SECONDS := 0.45
const EXTRACTION_COUNTER_TWIST := 0.05  # radians, during the anticipation
const EXTRACTION_TURN_RADIANS := 0.30  # a slow quarter-ish turn of the blade; never a spin

## How long the freed sword hangs in the air after the pull: 0.75 s on level 1, up to 1.2 s from level 11.
static func extraction_hold_seconds(intensity: float) -> float:
	return 0.75 + 0.45 * clampf(intensity, 0.0, 1.0)

## The whole sequence from the last tap to the end of the lift.
static func extraction_total_seconds(intensity: float) -> float:
	return EXTRACTION_ANTICIPATION_SECONDS + EXTRACTION_PULL_SECONDS + extraction_hold_seconds(intensity) + EXTRACTION_LIFT_SECONDS

## The part of the sequence that follows the release moment (what the camera and the level card have to fit into).
static func extraction_after_release_seconds(intensity: float) -> float:
	return EXTRACTION_PULL_SECONDS + extraction_hold_seconds(intensity) + EXTRACTION_LIFT_SECONDS

## The blade has just left the wood. Camera, light, level card and sound are triggered from here.
signal freed

## The empty cut left in the stump when the blade is gone (a thin dark slot). Built lazily, shown from the release
## until the next sword is dropped in. One tiny unlit quad: no per-frame cost.
var _slot: MeshInstance3D

func _build_slot() -> void:
	if _slot != null:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(BLADE_WIDTH * 0.95, 0.012, BLADE_THICKNESS * 1.7)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.035, 0.022, 0.012)
	_slot = MeshInstance3D.new()
	_slot.name = "EmptySlot"
	_slot.mesh = mesh
	_slot.material_override = mat
	_slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slot.top_level = true
	_slot.visible = false
	add_child(_slot)
	_slot.global_position = Vector3(0.0, stump_top_y + 0.004, 0.0)

func _show_slot(visible_now: bool) -> void:
	if _slot == null:
		if visible_now:
			_build_slot()
		else:
			return
	_slot.visible = visible_now

func slot_visible() -> bool:
	return _slot != null and _slot.visible

## Hold, release, present, lift away. Awaitable.
## No spin and no shake: the blade is still for the anticipation, then it rises with a decelerating pull, floats up a
## little further, drifts toward the camera and turns slowly (so it never sweeps sideways), hangs while the level card is
## read, then lifts away with an accelerating ease. Everything is one chain of eased tweens; nothing is random.
## `intensity` (0..1, from the level) lengthens the hold, raises the rise and brings the sword closer to the camera.
func play_extraction(intensity: float = 0.0) -> void:
	if _tween_running:
		push_warning("SwordController.play_extraction() ignored: an animation is already running")
		return
	_tween_running = true
	_animating = true
	# (1.10: the visual is NOT zeroed here: the micro-motion residue is settled by _process during the anticipation, so no jump)
	intensity = clampf(intensity, 0.0, 1.0)
	var hold := extraction_hold_seconds(intensity)
	var free_y := _rest_position.y + full_lift + 0.60 + 0.25 * intensity
	var gone_y := _rest_position.y + full_lift + 6.0
	var toward_camera := 0.30 + 0.40 * intensity
	# ONE tween. Step 1: the anticipation. Step 2 (callback): the release. Step 3 is a parallel group lasting exactly
	# pull + hold: the rise takes the first EXTRACTION_PULL_SECONDS, the drift and turn take the whole group. Step 4:
	# the lift away.
	_settling = true
	var tween := create_tween()
	# Anticipation: the blade is worked slightly against its turn (a small counter-twist, as if wrenched in the wood) while it
	# finishes its rise; the release then turns it the other way. Smooth, tiny and one-way: not a shake.
	tween.tween_property(_visual, "rotation:y", -EXTRACTION_COUNTER_TWIST, EXTRACTION_ANTICIPATION_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_release_now)
	tween.tween_property(self, "position:y", free_y, EXTRACTION_PULL_SECONDS).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "position:z", toward_camera, EXTRACTION_PULL_SECONDS + hold).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_visual, "rotation:y", EXTRACTION_TURN_RADIANS, EXTRACTION_PULL_SECONDS + hold).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", gone_y, EXTRACTION_LIFT_SECONDS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	_tween_running = false

func _release_now() -> void:
	_settling = false
	_clear_micro()
	_visual.position = Vector3.ZERO
	_visual.rotation.z = 0.0
	position.y = _rest_position.y + full_lift  # exactly the top of the pull; the release rises from here
	_show_slot(true)
	freed.emit()

## Drop a fresh sword into the stump from above. Awaitable.
func play_entrance() -> void:
	if _tween_running:
		push_warning("SwordController.play_entrance() ignored: an animation is already running")
		return
	_tween_running = true
	_animating = true
	_progress = 0.0
	_display_progress = 0.0
	_progress_velocity = 0.0
	_clear_micro()
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	position = _rest_position + Vector3(0.0, 7.0, 0.0)
	_show_slot(false)
	var tween := create_tween()
	tween.tween_property(self, "position:y", _rest_position.y, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tween.finished
	_tween_running = false
	position = _rest_position
	_animating = false
	planted.emit()

## Failure: the sword settles back into the wood with a decelerating, gripped feel and a small
## damped "seating" spring. Fully deterministic; the end pose is EXACTLY the embedded rest
## pose. Awaitable. Ignored (with a warning) if another animation is running.
func play_failure() -> void:
	if _tween_running:
		push_warning("SwordController.play_failure() ignored: an animation is already running")
		return
	_tween_running = true
	_animating = true
	_kick = 0.0
	_progress_velocity = 0.0
	_strain = 0.0
	_slipping = false
	_failure_residue = micro_offset()  # (1.10) the lean the blade had at the failure: it eases out with the seating, no snap
	_clear_micro()
	_visual.rotation = Vector3.ZERO
	var start_y := position.y
	var tween := create_tween()
	tween.tween_method(_apply_failure_pose.bind(start_y), 0.0, 1.0, FAILURE_DURATION)
	await tween.finished
	_tween_running = false
	position = _rest_position
	_visual.position = Vector3.ZERO
	_visual.rotation = Vector3.ZERO
	failure_settled.emit()

var _failure_residue := Vector3.ZERO

func _apply_failure_pose(t: float, start_y: float) -> void:
	var settle := 1.0 - pow(1.0 - clampf(t / FAILURE_SETTLE_FRACTION, 0.0, 1.0), 3.0)  # cubic ease-out
	position.y = lerpf(start_y, _rest_position.y, settle)
	var residue := 1.0 - settle
	var seconds := t * FAILURE_DURATION
	var envelope := exp(-FAILURE_SPRING_DECAY * seconds)
	# Starts at 0, first dips slightly (the wood grips), then rebounds and dies out.
	_visual.position = Vector3(
		FAILURE_SPRING_AMPLITUDE * 0.3 * envelope * sin(FAILURE_SPRING_FREQUENCY * 1.3 * seconds),
		-FAILURE_SPRING_AMPLITUDE * envelope * sin(FAILURE_SPRING_FREQUENCY * seconds),
		0.0) + Vector3(_failure_residue.x, _failure_residue.y, 0.0) * residue
	_visual.rotation.z = _failure_residue.z * residue

## Put the sword back in its embedded start pose and let it react to gameplay again
## (used when a new run starts after failure; no entrance animation is needed because the
## sword never left the stump).
func restore_embedded() -> void:
	if _tween_running:
		push_warning("SwordController.restore_embedded() ignored: an animation is already running")
		return
	reset_pose()
	_animating = false


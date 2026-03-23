extends Node3D
class_name CafeCustomer

## A cafe patron who peeks over the table edge to watch the model trains.
## Rises up, tracks the player with their head, reacts to derailments, and
## can be knocked back by flying train debris.

signal done        ## emitted when fully hidden — manager frees the node
signal hit_scored  ## emitted once the first time this customer is hit by debris

enum State { RISING, WATCHING, SINKING }

const HIDE_Y     := -8.0   # fully below table surface (2x head: top at y=6.1, so -8+6.1=-1.9)
const SHOW_Y     :=  0.0   # fully risen — head clears table edge
const RISE_SPEED := 4.5    # units/sec — ~1.8s over 8-unit travel
const SINK_SPEED := 3.5
const WATCH_TIME := 20.0
const CONE_COS      := 0.5    # cos(60°) — half-angle of view cone
const VIEW_DISTANCE := 110.0  # max XZ distance to detect a derail (table diagonal ≈96)

var _state: State = State.RISING
var _watch_timer: float = 0.0
var _player_ref: Node3D = null
var _face_dir: Vector3 = Vector3.FORWARD
var _body_container: Node3D = null   # bounce/shake tweens target this; root node only rises/sinks
var _head_pivot: Node3D = null
var _eye_l: MeshInstance3D = null
var _eye_r: MeshInstance3D = null
var _hit: bool = false
var _rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func setup(player: Node3D, face_dir: Vector3) -> void:
	_rng.randomize()
	_player_ref = player
	_face_dir = face_dir.normalized()
	position.y = HIDE_Y
	_build_body()
	_build_hit_area()

# ---------------------------------------------------------------------------
# Body construction
# ---------------------------------------------------------------------------

func _build_body() -> void:
	var skin   := Color(0.95, 0.82, 0.72)
	var hair_c := Color(
		_rng.randf_range(0.10, 0.50),
		_rng.randf_range(0.06, 0.32),
		_rng.randf_range(0.04, 0.18))
	var shirt  := Color(
		_rng.randf_range(0.30, 0.90),
		_rng.randf_range(0.30, 0.90),
		_rng.randf_range(0.30, 0.90))

	# Container node — bounce/shake tweens move this; root y is reserved for rise/sink
	_body_container = Node3D.new()
	add_child(_body_container)

	# Body — tall CapsuleMesh; bottom reaches ROOM_FLOOR (-22) when node is at y=0
	# Center at y=-9.5: top=3.0 (matches head pivot), bottom=-22.0
	var body_mi  := MeshInstance3D.new()
	var cap      := CapsuleMesh.new()
	cap.radius   = 1.6
	cap.height   = 25.0
	body_mi.mesh = cap
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = shirt
	body_mi.material_override = body_mat
	body_mi.position = Vector3(0.0, -9.5, 0.0)
	_body_container.add_child(body_mi)

	# Head pivot — rotates each frame to track the player
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0.0, 3.0, 0.0)
	_body_container.add_child(_head_pivot)

	# Head box — 2× scale: 6.2³
	var head_mi  := MeshInstance3D.new()
	var head_box := BoxMesh.new()
	head_box.size = Vector3(6.2, 6.2, 6.2)
	head_mi.mesh  = head_box
	var head_mat  := StandardMaterial3D.new()
	head_mat.albedo_color = skin
	head_mi.material_override = head_mat
	_head_pivot.add_child(head_mi)

	# Hair — sits on top of head: y = head_half (3.1) + hair_half (1.2) = 4.3
	var hair_mi  := MeshInstance3D.new()
	var hair_box := BoxMesh.new()
	hair_box.size = Vector3(6.4, 2.4, 6.4)
	hair_mi.mesh  = hair_box
	var hair_mat  := StandardMaterial3D.new()
	hair_mat.albedo_color = hair_c
	hair_mi.material_override = hair_mat
	hair_mi.position = Vector3(0.0, 4.3, 0.0)
	_head_pivot.add_child(hair_mi)

	# Eyes — on the -Z face so look_at() orients the face toward the target
	# head_half_z = 3.1; eye at z = -(3.1 + eye_half_z=0.25) = -3.35
	for side in [-1.0, 1.0]:
		var eye_mi  := MeshInstance3D.new()
		var eye_box := BoxMesh.new()
		eye_box.size = Vector3(1.50, 1.20, 0.50)
		eye_mi.mesh  = eye_box
		var eye_mat  := StandardMaterial3D.new()
		eye_mat.albedo_color = Color.WHITE
		eye_mi.material_override = eye_mat
		eye_mi.position = Vector3(side * 1.60, 0.40, -3.35)
		_head_pivot.add_child(eye_mi)
		if side < 0.0:
			_eye_l = eye_mi
		else:
			_eye_r = eye_mi

		# Dark pupil
		var pupil_mi  := MeshInstance3D.new()
		var pupil_box := BoxMesh.new()
		pupil_box.size = Vector3(0.70, 0.70, 0.30)
		pupil_mi.mesh  = pupil_box
		var pupil_mat  := StandardMaterial3D.new()
		pupil_mat.albedo_color = Color(0.10, 0.08, 0.08)
		pupil_mi.material_override = pupil_mat
		pupil_mi.position = Vector3(side * 1.60, 0.40, -3.50)
		_head_pivot.add_child(pupil_mi)

func _build_hit_area() -> void:
	var area := Area3D.new()
	area.monitoring  = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask  = GameConstants.LAYER_DEBRIS   # matches physics car layer 8
	var cs    := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8.0, 12.0, 8.0)
	cs.shape   = shape
	cs.position = Vector3(0.0, 2.0, 0.0)
	area.add_child(cs)
	area.body_entered.connect(_on_hit_by_debris)
	add_child(area)

# ---------------------------------------------------------------------------
# Per-frame update
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	match _state:
		State.RISING:
			position.y = move_toward(position.y, SHOW_Y, RISE_SPEED * delta)
			_update_head_tracking()
			if absf(position.y - SHOW_Y) < 0.05:
				position.y = SHOW_Y
				_state = State.WATCHING
				_watch_timer = WATCH_TIME
		State.WATCHING:
			_watch_timer -= delta
			_update_head_tracking()
			if _watch_timer <= 0.0:
				_state = State.SINKING
		State.SINKING:
			position.y = move_toward(position.y, HIDE_Y, SINK_SPEED * delta)
			if absf(position.y - HIDE_Y) < 0.05:
				position.y = HIDE_Y
				done.emit()
				queue_free()

## Rotates the head to face the player's current world position (yaw only).
## Only sets rotation.y so that ongoing X/Z wobble tweens are not overridden.
func _update_head_tracking() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	var to := _player_ref.global_position - _head_pivot.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	_head_pivot.rotation.y = atan2(-to.x, -to.z)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Returns true only when this customer is fully risen, not yet hit, and the
## event position falls within their viewing cone (CONE_COS = cos 60°).
##
## Math: project both positions onto XZ, compute the direction vector from
## customer to event, dot it against the (fixed) inward face direction.
## A result > CONE_COS means the angle between them is < 60°, i.e. in-view.
## Using 2D Vector2 throughout to avoid any accidental 3D normalisation issues.
func can_see_position(world_pos: Vector3) -> bool:
	# Guard: only score when customer is fully up and watching
	if _state != State.WATCHING or _hit:
		return false

	# XZ-plane direction from this customer to the event
	var my_xz    := Vector2(global_position.x, global_position.z)
	var event_xz := Vector2(world_pos.x, world_pos.z)
	var to_xz    := event_xz - my_xz

	# Degenerate: event is directly overhead/underfoot — count as visible
	if to_xz.length_squared() < 0.01:
		return true

	# Distance limit: too far away to notice
	if to_xz.length() > VIEW_DISTANCE:
		return false

	# _face_dir is normalised in setup(); grab its XZ components as 2D
	var face_2d := Vector2(_face_dir.x, _face_dir.z)

	# dot > CONE_COS means angle from face direction < 60°
	if to_xz.normalized().dot(face_2d) <= CONE_COS:
		return false

	# Line-of-sight: 5 rays from face points to event, blocked by layer 1 (walls/table)
	return _has_line_of_sight(world_pos)

## Cast 5 rays from different points on the face toward the target.
## Returns true (line-of-sight clear) if ANY ray reaches the target unobstructed.
## Origins: centre of head + four face offsets (±right, ±up) ~2 units apart.
## This greatly reduces false negatives when a small obstruction clips just one ray.
func _has_line_of_sight(to: Vector3) -> bool:
	if not is_inside_tree():
		return true
	var space_state := get_world_3d().direct_space_state
	var excl: Array = []
	if _player_ref != null and is_instance_valid(_player_ref):
		excl = [_player_ref.get_rid()]

	# Head pivot only rotates on Y so basis.x = world-right of face, basis.y = up
	var centre : Vector3 = _head_pivot.global_position
	var right  : Vector3 = _head_pivot.global_transform.basis.x * 2.0
	var up     : Vector3 = Vector3.UP * 2.0

	var origins: Array = [
		centre,
		centre + right,
		centre - right,
		centre + up,
		centre - up,
	]
	for origin: Vector3 in origins:
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.collision_mask = 1
		query.exclude        = excl
		if space_state.intersect_ray(query).is_empty():
			return true   # at least one ray has clear sight
	return false          # all five rays were blocked

func trigger_happy() -> void:
	# Only react when fully up and watching — not while still rising or leaving
	if _state != State.WATCHING or _hit:
		return
	# Body bounces up twice
	var tw := create_tween()
	tw.tween_property(_body_container, "position:y", 3.0, 0.10).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body_container, "position:y", 0.0, 0.18).set_ease(Tween.EASE_IN)
	tw.tween_property(_body_container, "position:y", 1.2, 0.08).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body_container, "position:y", 0.0, 0.14).set_ease(Tween.EASE_IN)
	# Head wobbles side-to-side simultaneously
	var tw2 := create_tween()
	tw2.tween_property(_head_pivot, "rotation_degrees:z",  22.0, 0.09)
	tw2.tween_property(_head_pivot, "rotation_degrees:z", -18.0, 0.11)
	tw2.tween_property(_head_pivot, "rotation_degrees:z",  13.0, 0.09)
	tw2.tween_property(_head_pivot, "rotation_degrees:z",  -8.0, 0.09)
	tw2.tween_property(_head_pivot, "rotation_degrees:z",   0.0, 0.10)

func trigger_hit() -> void:
	if _hit:
		return
	_hit = true
	hit_scored.emit()
	_set_x_eyes()
	_spawn_stars()
	# Head snaps back hard, then slumps forward — more violent than trigger_happy
	var tw := create_tween()
	tw.tween_property(_head_pivot, "rotation_degrees:x", -55.0, 0.10).set_ease(Tween.EASE_OUT)
	tw.tween_property(_head_pivot, "rotation_degrees:x",  25.0, 0.14)
	tw.tween_property(_head_pivot, "rotation_degrees:x", -35.0, 0.10)
	tw.tween_property(_head_pivot, "rotation_degrees:x",   0.0, 0.18)
	# Body shakes, then start sinking after the recoil settles
	var tw2 := create_tween()
	tw2.tween_property(_body_container, "position:y",  2.0, 0.08).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_body_container, "position:y", -1.5, 0.10).set_ease(Tween.EASE_IN)
	tw2.tween_property(_body_container, "position:y",  0.8, 0.08).set_ease(Tween.EASE_OUT)
	tw2.tween_property(_body_container, "position:y",  0.0, 0.12).set_ease(Tween.EASE_IN)
	tw2.tween_callback(func() -> void: _state = State.SINKING)

# ---------------------------------------------------------------------------
# Hit reaction helpers
# ---------------------------------------------------------------------------

func _set_x_eyes() -> void:
	for eye in [_eye_l, _eye_r]:
		if eye == null or not is_instance_valid(eye):
			continue
		# Hide the normal eye mesh
		eye.visible = false
		# Two thin boxes rotated ±45° form an X in the YZ plane
		var x_color := Color(0.90, 0.10, 0.10)
		for angle in [45.0, -45.0]:
			var bar     := MeshInstance3D.new()
			var bar_box := BoxMesh.new()
			bar_box.size = Vector3(0.40, 1.30, 0.40)
			bar.mesh     = bar_box
			var bar_mat  := StandardMaterial3D.new()
			bar_mat.albedo_color = x_color
			bar.material_override = bar_mat
			bar.position = eye.position
			bar.rotation_degrees.z = angle
			_head_pivot.add_child(bar)

func _spawn_stars() -> void:
	var stars                  := CPUParticles3D.new()
	stars.emitting             = true
	stars.amount               = 24
	stars.lifetime             = 1.8
	stars.one_shot             = true
	stars.explosiveness        = 0.9
	stars.direction            = Vector3.UP
	stars.spread               = 70.0
	stars.gravity              = Vector3(0.0, -8.0, 0.0)
	stars.initial_velocity_min = 5.0
	stars.initial_velocity_max = 11.0
	stars.scale_amount_min     = 0.8
	stars.scale_amount_max     = 1.6
	stars.angle_min            = 0.0
	stars.angle_max            = 360.0     # random initial rotation per particle
	stars.angular_velocity_min = -240.0
	stars.angular_velocity_max =  240.0   # spin as they fly

	# QuadMesh (flat square) with billboard mode so it always faces the camera.
	# Gold emissive material makes them glow — no vertex_color needed.
	var star_mesh  := QuadMesh.new()
	star_mesh.size = Vector2(1.2, 1.2)
	var star_mat   := StandardMaterial3D.new()
	star_mat.albedo_color     = Color(1.0, 0.90, 0.10)   # bright gold
	star_mat.emission_enabled = true
	star_mat.emission         = Color(1.0, 0.75, 0.0) * 2.5   # warm glow
	star_mat.billboard_mode   = BaseMaterial3D.BILLBOARD_ENABLED
	star_mat.cull_mode        = BaseMaterial3D.CULL_DISABLED   # visible from both sides
	star_mesh.material        = star_mat

	stars.mesh     = star_mesh
	stars.position = Vector3(0.0, 9.0, 0.0)   # above 2× head
	_head_pivot.add_child(stars)

# ---------------------------------------------------------------------------
# Debris collision
# ---------------------------------------------------------------------------

func _on_hit_by_debris(_body: Node3D) -> void:
	trigger_hit()

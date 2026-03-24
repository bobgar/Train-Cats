extends CharacterBody3D
class_name Player

## Third-person cat controller.
## Movement: WASD or left stick.  Sprint: Shift, LB, or LT.  Jump: Space or A.
## Swipe: left-click, E, X, or RB.
## Camera: auto-follows behind cat; right stick or mouse (when captured) for manual override.

const WALK_SPEED       := 8.0
const SPRINT_SPEED     := 20.0
const JUMP_SPEED       := 12.0
const GRAVITY          := 26.0
const MOUSE_SENS       := 0.26
const CAM_DIST         := 11.0
const CTRL_DEADZONE    := 0.15
const CTRL_SENS        := 120.0   # right-stick degrees per second
const CAM_FOLLOW_SPEED := 2.0     # how fast camera swings behind player

# Camera orbit angles (degrees)
var _cam_yaw:   float = 0.0    # 0 = camera sits in world +Z from player
var _cam_pitch: float = 22.0   # degrees above horizontal

var _body_pivot: Node3D        # rotates to face movement direction
var _camera: Camera3D

var _paws: Array = []          # [left Node3D, right Node3D]
var _paw_rest: Array = []      # rest positions in _body_pivot local space
var _is_swiping: bool = false
var _swipe_side: int = 0       # alternates 0/1 for left/right paw
var _leg_phase: float = 0.0
var _body_area: Area3D         # overlaps train sensors for hit detection

var _spawn_pos: Vector3        # set on _ready; used to respawn after falling
var _respawning: bool = false  # true while waiting for respawn countdown

var _respawn_overlay: CanvasLayer = null
var _respawn_label:   Label       = null

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

func _ready() -> void:
	_spawn_pos = position
	_build_collision()
	_build_body_area()
	_build_cat()
	_build_camera()
	_build_respawn_overlay()

func _build_collision() -> void:
	collision_layer = GameConstants.LAYER_WORLD
	collision_mask  = GameConstants.LAYER_WORLD
	var cs  := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.55
	cs.shape    = cap
	cs.position = Vector3(0, 0.78, 0)
	add_child(cs)

func _build_body_area() -> void:
	_body_area = Area3D.new()
	_body_area.collision_layer = 0
	_body_area.collision_mask  = GameConstants.LAYER_TRAIN   # overlaps train Area3D sensors (layer 2)
	var cs  := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.48
	cap.height = 1.55
	cs.shape    = cap
	cs.position = Vector3(0, 0.78, 0)
	_body_area.add_child(cs)
	add_child(_body_area)

func _build_cat() -> void:
	_body_pivot = Node3D.new()
	_body_pivot.position.y = 0.62
	add_child(_body_pivot)

	var fur  := Color(0.88, 0.52, 0.18)
	var furd := Color(0.66, 0.35, 0.10)
	var crm  := Color(0.94, 0.88, 0.76)
	var eye  := Color(0.08, 0.06, 0.03)
	var nose := Color(0.90, 0.55, 0.58)

	# Body
	MeshBuilder.colored_box(_body_pivot, Vector3(0.68, 0.50, 0.88), fur,  Vector3.ZERO)
	# Belly (lighter strip)
	MeshBuilder.colored_box(_body_pivot, Vector3(0.28, 0.46, 0.70), crm.darkened(0.12), Vector3(0, -0.06, 0.04))

	# Head (forward-up)
	var hd := Vector3(0, 0.38, -0.52)
	MeshBuilder.colored_box(_body_pivot, Vector3(0.60, 0.52, 0.54), fur, hd)

	# Ears
	MeshBuilder.colored_box(_body_pivot, Vector3(0.13, 0.25, 0.10), furd, hd + Vector3(-0.17,  0.35, 0.04))
	MeshBuilder.colored_box(_body_pivot, Vector3(0.13, 0.25, 0.10), furd, hd + Vector3( 0.17,  0.35, 0.04))
	# Eyes
	MeshBuilder.colored_box(_body_pivot, Vector3(0.11, 0.10, 0.05), eye,  hd + Vector3(-0.14,  0.06, -0.27))
	MeshBuilder.colored_box(_body_pivot, Vector3(0.11, 0.10, 0.05), eye,  hd + Vector3( 0.14,  0.06, -0.27))
	# Nose
	MeshBuilder.colored_box(_body_pivot, Vector3(0.09, 0.07, 0.05), nose, hd + Vector3( 0,    -0.09, -0.28))

	# Tail (angled upward from rear)
	var tail := MeshBuilder.colored_box(_body_pivot, Vector3(0.12, 0.60, 0.12), fur, Vector3(0.06, 0.24, 0.52))
	tail.rotation_degrees.x = -46.0

	# Rear legs + paws
	for sx in [-1.0, 1.0]:
		MeshBuilder.colored_box(_body_pivot, Vector3(0.19, 0.44, 0.22), furd, Vector3(sx * 0.26, -0.30,  0.30))
		MeshBuilder.colored_box(_body_pivot, Vector3(0.22, 0.10, 0.36), crm,  Vector3(sx * 0.26, -0.54,  0.40))

	# Front paws — separate Node3D for animation
	for i in range(2):
		var sx: float = -1.0 if i == 0 else 1.0
		var paw := Node3D.new()
		var rest := Vector3(sx * 0.27, -0.31, -0.38)
		paw.position = rest
		_body_pivot.add_child(paw)
		MeshBuilder.colored_box(paw, Vector3(0.18, 0.40, 0.18), furd, Vector3.ZERO)               # upper leg
		MeshBuilder.colored_box(paw, Vector3(0.22, 0.10, 0.30), crm,  Vector3(0, -0.22, -0.02))   # paw tip
		_paws.append(paw)
		_paw_rest.append(rest)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov  = 62.0
	_camera.near = 0.15
	add_child(_camera)

func _build_respawn_overlay() -> void:
	_respawn_overlay        = CanvasLayer.new()
	_respawn_overlay.layer  = 25
	_respawn_overlay.visible = false
	add_child(_respawn_overlay)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_respawn_overlay.add_child(root)

	# Dark strip behind the text
	var bg := ColorRect.new()
	bg.color          = Color(0.0, 0.0, 0.0, 0.60)
	bg.anchor_left    = 0.0;  bg.anchor_right  = 1.0
	bg.anchor_top     = 0.36; bg.anchor_bottom = 0.64
	bg.offset_left    = 0;    bg.offset_right  = 0
	bg.offset_top     = 0;    bg.offset_bottom = 0
	root.add_child(bg)

	_respawn_label = UIBuilder.anchor_label(root, "Respawning in 3...",
		0.0, 1.0, 0.40, 0.60, 42, Color.WHITE)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			KEY_E:
				if not _is_swiping:
					_do_swipe()

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_cam_yaw   -= event.relative.x * MOUSE_SENS
		_cam_pitch  = clamp(_cam_pitch + event.relative.y * MOUSE_SENS, 5.0, 62.0)

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		elif not _is_swiping:
			_do_swipe()

	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_X or event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			if not _is_swiping:
				_do_swipe()

# ---------------------------------------------------------------------------
# Physics — movement
# ---------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Trigger respawn countdown when falling off the table
	if global_position.y < -8.0 and not _respawning:
		_start_respawn()

	# Freeze all movement during the respawn countdown
	if _respawning:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0:
		velocity.y = 0.0

	# Jump — Space or controller A button
	if (Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)) and is_on_floor():
		velocity.y = JUMP_SPEED

	# Read movement input — keyboard and/or controller left stick
	var kx := float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT)) \
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT))
	var ky := float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN)) \
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	var jx := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var jy := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(jx) < CTRL_DEADZONE: jx = 0.0
	if absf(jy) < CTRL_DEADZONE: jy = 0.0
	var ix := clampf(kx + jx, -1.0, 1.0)
	var iy := clampf(ky + jy, -1.0, 1.0)
	var sprint := Input.is_key_pressed(KEY_SHIFT) \
			or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER) \
			or Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5
	var spd    := SPRINT_SPEED if sprint else WALK_SPEED
	var moving := ix != 0.0 or iy != 0.0

	if moving:
		var yaw_rad := deg_to_rad(_cam_yaw)
		# Camera-relative horizontal basis vectors
		var cam_fwd   := Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))  # cam → player projected
		var cam_right := Vector3( cos(yaw_rad), 0.0, -sin(yaw_rad))
		var move3 := (cam_right * ix + cam_fwd * (-iy)).normalized()
		velocity.x = move3.x * spd
		velocity.z = move3.z * spd
		# Body faces movement direction (local -Z = move direction)
		var target_y := atan2(-move3.x, -move3.z)
		_body_pivot.rotation.y = lerp_angle(_body_pivot.rotation.y, target_y, 0.18)
	else:
		var decel := spd * 10.0 * delta
		velocity.x = move_toward(velocity.x, 0.0, decel)
		velocity.z = move_toward(velocity.z, 0.0, decel)

	_animate_legs(delta, moving, sprint)
	move_and_slide()
	# Walk-into-train: break any train the body is touching while moving
	var h_spd := Vector2(velocity.x, velocity.z).length()
	if h_spd > WALK_SPEED * 0.4 and _body_pivot != null:
		var fwd: Vector3 = -_body_pivot.global_transform.basis.z
		for area in _body_area.get_overlapping_areas():
			if area.has_meta("owning_train"):
				var train = area.get_meta("owning_train")
				if not train.is_derailed():
					train.call("_swipe_derail", fwd, 6.0)

# ---------------------------------------------------------------------------
# Camera — orbital, updated in _process so it's smooth even at high physics rate
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Camera stays frozen while respawning
	if _respawning:
		return

	# Right stick — manual camera control
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var stick_active := absf(rx) > CTRL_DEADZONE or absf(ry) > CTRL_DEADZONE
	if absf(rx) > CTRL_DEADZONE:
		_cam_yaw   -= rx * CTRL_SENS * delta
	if absf(ry) > CTRL_DEADZONE:
		_cam_pitch  = clamp(_cam_pitch + ry * CTRL_SENS * delta, 5.0, 62.0)

	# Auto-follow: smoothly swing camera behind cat while moving,
	# unless the right stick or mouse look is overriding it
	var mouse_active := Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED
	if not stick_active and not mouse_active:
		var h_spd := Vector2(velocity.x, velocity.z).length()
		if h_spd > 1.0:
			_cam_yaw = rad_to_deg(lerp_angle(
				deg_to_rad(_cam_yaw), _body_pivot.rotation.y, delta * CAM_FOLLOW_SPEED))

	var yaw_r   := deg_to_rad(_cam_yaw)
	var pitch_r := deg_to_rad(_cam_pitch)
	var cp := cos(pitch_r)
	var sp := sin(pitch_r)
	# Orbit offset: camera sits at (yaw, pitch) spherical coords around player
	var offset := Vector3(sin(yaw_r) * cp, sp, cos(yaw_r) * cp) * CAM_DIST
	var look_at    := global_position + Vector3.UP * 0.8
	var cam_pos    := look_at + offset
	cam_pos.y       = maxf(cam_pos.y, 1.5)   # never clip below the table surface
	_camera.global_position = cam_pos
	_camera.look_at(look_at, Vector3.UP)

# ---------------------------------------------------------------------------
# Respawn
# ---------------------------------------------------------------------------

func _start_respawn() -> void:
	_respawning = true
	velocity    = Vector3.ZERO
	_respawn_overlay.visible = true
	for count: int in [3, 2, 1]:
		_respawn_label.text = "Respawning in %d..." % count
		await get_tree().create_timer(1.0).timeout
	_respawn_overlay.visible = false
	global_position = _spawn_pos
	velocity        = Vector3.ZERO
	_respawning     = false

# ---------------------------------------------------------------------------
# Leg animation
# ---------------------------------------------------------------------------

func _animate_legs(delta: float, moving: bool, sprint: bool) -> void:
	if moving:
		_leg_phase += delta * (10.0 if sprint else 6.0)
	# Front paws swing in opposite phase when moving; hold still otherwise
	if not _is_swiping:
		var az := 0.18 if not sprint else 0.26
		var ay := 0.08
		_paws[0].position = _paw_rest[0] + Vector3(0,  sin(_leg_phase) * ay,  sin(_leg_phase) * az)
		_paws[1].position = _paw_rest[1] + Vector3(0, -sin(_leg_phase) * ay, -sin(_leg_phase) * az)

# ---------------------------------------------------------------------------
# Paw swipe
# ---------------------------------------------------------------------------

func _do_swipe() -> void:
	_is_swiping = true
	var idx  := _swipe_side
	_swipe_side = 1 - _swipe_side
	var paw: Node3D   = _paws[idx]
	var rest: Vector3 = _paw_rest[idx]
	# Arc swipe: wind-up outward/upward, then strike across and forward
	var sx: float     = sign(rest.x)   # -1 = left paw, +1 = right paw
	var wind_up: Vector3 = Vector3(sx * 0.38, rest.y + 0.22, rest.z + 0.14)
	var strike: Vector3  = Vector3(-sx * 0.18, rest.y - 0.10, rest.z - 0.90)

	var tween := create_tween()
	tween.tween_property(paw, "position", wind_up, 0.08)
	tween.tween_property(paw, "position", strike,  0.13)
	tween.tween_callback(_check_swipe_hit)
	tween.tween_property(paw, "position", rest, 0.18)
	tween.tween_callback(func() -> void: _is_swiping = false)

func _check_swipe_hit() -> void:
	var fwd: Vector3 = -_body_pivot.global_transform.basis.z  # body local -Z = cat's forward
	# Active trains: use body area overlap tracking (always up-to-date, no query timing issues)
	for area in _body_area.get_overlapping_areas():
		if area.has_meta("owning_train"):
			var train = area.get_meta("owning_train")
			if not train.is_derailed():
				train.call("_swipe_derail", fwd, 14.0)
	# Physics wrecks (RigidBody3D): sphere query on layer 1
	var hit_pos: Vector3 = global_position + Vector3.UP * 0.8 + fwd * 1.5
	var query  := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius        = 1.7
	query.shape          = sphere
	query.transform      = Transform3D(Basis(), hit_pos)
	query.collision_mask = GameConstants.LAYER_WORLD
	query.collide_with_areas  = false
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	for h in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var col = h.get("collider")
		if col is RigidBody3D:
			var dir: Vector3 = col.global_position - global_position
			dir.y = absf(dir.y) + 0.5
			col.apply_central_impulse(dir.normalized() * 32.0)

extends Node3D
class_name Train

## Each car independently samples its position along the path.
## Features: acceleration/deceleration, lookahead avoidance, physics derailment.

enum State { MOVING, STOPPED, DERAILED }

@export var max_speed: float = 8.0
@export var acceleration: float = 5.0
@export var deceleration: float = 7.0

var _gen                        # TrackGenerator (untyped — class cache bootstrapping)
var _station_nodes: Array       # Array of Vector2i
var _state: State = State.MOVING
var _stop_timer: float = 0.0
var _current_speed: float = 0.0

# Path data rebuilt on each departure
var _path: Array                # Array of Vector2i
var _path_world: Array          # Array of Vector3
var _path_cumlen: Array         # Array of float (cumulative distance)
var _total_path_len: float = 0.0
var _head_dist: float = 0.0

# Per-car nodes, area sensors, and spacing
var _cars: Array = []           # Array of Node3D
var _car_areas: Array = []      # Array of Area3D (one per car, for collision)
var _car_spacing: float = 2.55

var _lookahead: RayCast3D = null  # Forward proximity sensor on the locomotive

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(gen, stations: Array, start: Vector2i, color: Color, num_cars: int) -> void:
	_gen = gen
	_station_nodes = stations
	_build_visuals(num_cars, color)
	_build_lookahead()
	_depart_from(start)

func is_derailed() -> bool:
	return _state == State.DERAILED

# ---------------------------------------------------------------------------
# Visual construction
# ---------------------------------------------------------------------------

func _build_visuals(num_cars: int, color: Color) -> void:
	var car_len := 2.3
	_car_spacing = car_len + 0.25
	for i in range(num_cars):
		var car := Node3D.new()
		_build_car(car, car_len, color, i == 0)
		_attach_car_area(car, car_len)
		add_child(car)
		_cars.append(car)

func _build_car(car: Node3D, car_len: float, color: Color, is_loco: bool) -> void:
	var body_color := color.darkened(0.18) if is_loco else color
	_mi_box(car, Vector3(car_len - 0.1, 0.88, 1.46), body_color, Vector3(0, 1.02, 0))
	if is_loco:
		_mi_box(car, Vector3(car_len * 0.45, 0.46, 1.46), body_color.darkened(0.12),
			Vector3(car_len * 0.22, 1.69, 0))
		_mi_box(car, Vector3(0.18, 0.48, 0.18), Color(0.15, 0.15, 0.15),
			Vector3(-car_len * 0.30, 1.90, 0))
		_mi_box(car, Vector3(0.28, 0.22, 0.12), Color(1.0, 0.95, 0.70),
			Vector3(car_len * 0.5 - 0.06, 1.04, 0))
	else:
		_mi_box(car, Vector3(car_len - 0.55, 0.28, 0.06), Color(0.76, 0.88, 0.96),
			Vector3(0, 1.28, 0.76))
		_mi_box(car, Vector3(car_len - 0.55, 0.28, 0.06), Color(0.76, 0.88, 0.96),
			Vector3(0, 1.28, -0.76))
	_mi_box(car, Vector3(car_len - 0.15, 0.18, 1.22), Color(0.14, 0.14, 0.16),
		Vector3(0, 0.50, 0))
	for wx in [car_len * 0.28, -car_len * 0.28]:
		for wz in [0.70, -0.70]:
			_mi_cyl(car, 0.26, 0.20, Color(0.12, 0.12, 0.14), Vector3(wx, 0.28, wz))

## Add an Area3D sensor to a car for train-train collision detection.
func _attach_car_area(car: Node3D, car_len: float) -> void:
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 2
	area.monitoring = true
	area.monitorable = true
	area.set_meta("owning_train", self)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(car_len - 0.15, 1.5, 1.6)
	cs.shape = box
	cs.position = Vector3(0, 0.75, 0)
	area.add_child(cs)
	area.area_entered.connect(_on_car_area_entered)
	car.add_child(area)
	_car_areas.append(area)

## RayCast3D mounted on the locomotive, pointing forward. Detects trains ahead.
func _build_lookahead() -> void:
	if _cars.is_empty():
		return
	_lookahead = RayCast3D.new()
	_lookahead.collision_mask = 2
	_lookahead.collide_with_areas = true
	_lookahead.collide_with_bodies = false
	_lookahead.target_position = Vector3(7.0, 0.5, 0.0)  # 7 units ahead in local +X
	_lookahead.enabled = true
	for area in _car_areas:
		_lookahead.add_exception(area)      # ignore own car sensors
	_cars[0].add_child(_lookahead)

func _mi_box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)

func _mi_cyl(parent: Node3D, radius: float, height: float, color: Color, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = PI * 0.5
	parent.add_child(mi)

# ---------------------------------------------------------------------------
# Collision detection & derailment
# ---------------------------------------------------------------------------

func _on_car_area_entered(other_area: Area3D) -> void:
	if _state == State.DERAILED:
		return
	if not other_area.has_meta("owning_train"):
		return
	var other_train = other_area.get_meta("owning_train")
	if other_train == self or other_train.is_derailed():
		return
	# Only crash if we're moving fast enough to matter
	if _current_speed >= 1.8:
		_derail()

## Switch to DERAILED state: spawn tumbling physics cars, propagate to anything overlapping.
func _derail() -> void:
	if _state == State.DERAILED:
		return
	_state = State.DERAILED
	var vel := _heading_dir() * _current_speed
	_current_speed = 0.0

	# Propagate derailment to any trains we're physically touching right now
	for area in _car_areas:
		for other_var in area.get_overlapping_areas():
			var other_area := other_var as Area3D
			if other_area != null and other_area.has_meta("owning_train"):
				var other = other_area.get_meta("owning_train")
				if other != self and not other.is_derailed():
					other.call("_derail")

	for car in _cars:
		_spawn_physics_car(car, vel)
		car.visible = false

func _heading_dir() -> Vector3:
	if _path_world.size() < 2:
		return Vector3.FORWARD
	return (_sample_path(_head_dist + 0.5) - _sample_path(_head_dist - 0.5)).normalized()

## Spawn a tumbling RigidBody3D in place of a car when derailed.
func _spawn_physics_car(car: Node3D, base_vel: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.global_transform = car.global_transform
	rb.mass = 1.5

	# Read body color from the first MeshInstance3D child
	var car_color := Color(0.5, 0.5, 0.5)
	for child in car.get_children():
		if child is MeshInstance3D:
			var mat := child.material_override as StandardMaterial3D
			if mat != null:
				car_color = mat.albedo_color
			break

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.1, 1.3, 1.5)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = car_color
	mi.material_override = mat
	mi.position = Vector3(0, 0.65, 0)
	rb.add_child(mi)

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 1.3, 1.5)
	cs.shape = shape
	cs.position = Vector3(0, 0.65, 0)
	rb.add_child(cs)

	# Launch with train's current velocity + random scatter
	rb.linear_velocity = base_vel + Vector3(
		randf_range(-1.5, 1.5),
		randf_range(0.5, 3.0),
		randf_range(-1.5, 1.5)
	)
	rb.angular_velocity = Vector3(
		randf_range(-5.0, 5.0),
		randf_range(-2.0, 2.0),
		randf_range(-5.0, 5.0)
	)

	get_parent().add_child(rb)

# ---------------------------------------------------------------------------
# Path sampling
# ---------------------------------------------------------------------------

func _build_path_data() -> void:
	_path_world = []
	_path_cumlen = [0.0]
	_total_path_len = 0.0
	for i in range(_path.size()):
		_path_world.append(_gen.nodes[_path[i]])
		if i > 0:
			var seg: float = (_path_world[i - 1] as Vector3).distance_to(_path_world[i])
			_total_path_len += seg
			_path_cumlen.append(_total_path_len)

func _sample_path(dist: float) -> Vector3:
	if _path_world.size() == 0:
		return Vector3.ZERO
	dist = clampf(dist, 0.0, _total_path_len)
	for i in range(_path_cumlen.size() - 1):
		var seg_start: float = _path_cumlen[i]
		var seg_end: float = _path_cumlen[i + 1]
		if dist <= seg_end:
			var seg_len: float = seg_end - seg_start
			if seg_len < 0.0001:
				return _path_world[i]
			return (_path_world[i] as Vector3).lerp(_path_world[i + 1],
				(dist - seg_start) / seg_len)
	return _path_world[_path_world.size() - 1]

# ---------------------------------------------------------------------------
# Movement & AI
# ---------------------------------------------------------------------------

func _depart_from(from: Vector2i) -> void:
	if _station_nodes.size() < 2:
		return
	var options: Array = []
	for s_var in _station_nodes:
		var s: Vector2i = s_var
		if s != from:
			options.append(s)
	if options.is_empty():
		return
	var dest: Vector2i = options[randi() % options.size()]
	_path = _bfs(from, dest)
	_build_path_data()
	_head_dist = (_cars.size() - 1) * _car_spacing
	_state = State.MOVING
	_update_car_transforms()

func _bfs(start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return [start]
	var visited: Dictionary = {start: true}
	var queue: Array = [[start]]
	while queue.size() > 0:
		var current_path: Array = queue.pop_front()
		var cur: Vector2i = current_path[-1]
		for nb_var in _gen.adjacency.get(cur, []):
			var nb: Vector2i = nb_var
			if nb == goal:
				return current_path + [nb]
			if not visited.has(nb):
				visited[nb] = true
				queue.append(current_path + [nb])
	return [start]

func _process(delta: float) -> void:
	if _state == State.DERAILED:
		return
	match _state:
		State.MOVING:
			_tick_moving(delta)
		State.STOPPED:
			_stop_timer -= delta
			if _stop_timer <= 0.0:
				_depart_from(_path[_path.size() - 1])

func _tick_moving(delta: float) -> void:
	# --- Avoidance: slow to zero if another train is directly ahead ---
	var want_speed := max_speed
	if _lookahead != null and _lookahead.is_colliding():
		var hit = _lookahead.get_collider()
		if hit is Area3D and hit.has_meta("owning_train"):
			var other = hit.get_meta("owning_train")
			if other != self and not other.is_derailed():
				want_speed = 0.0

	# --- Acceleration / deceleration ---
	var rate := deceleration if _current_speed > want_speed else acceleration
	_current_speed = move_toward(_current_speed, want_speed, rate * delta)

	_head_dist += _current_speed * delta
	if _head_dist >= _total_path_len:
		_head_dist = _total_path_len
		_current_speed = 0.0
		_update_car_transforms()
		_arrive()
	else:
		_update_car_transforms()

func _update_car_transforms() -> void:
	for i in range(_cars.size()):
		var car_dist: float = _head_dist - i * _car_spacing
		_cars[i].global_position = _sample_path(car_dist) + Vector3.UP * 0.25
		var dir: Vector3 = (_sample_path(car_dist + 0.25) - _sample_path(car_dist - 0.25)).normalized()
		if dir.length_squared() > 0.001:
			_cars[i].rotation.y = atan2(-dir.z, dir.x)

func _arrive() -> void:
	_state = State.STOPPED
	_stop_timer = randf_range(2.5, 5.5)

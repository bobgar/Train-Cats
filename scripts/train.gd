extends Node3D
class_name Train

## Train AI state machine:
##   MOVING             → normal forward travel with avoidance braking
##   STOPPED            → dwell at station
##   REVERSING          → backing up to a junction to yield
##   WAITING_AT_JUNCTION→ holding at junction until path ahead clears
##   DERAILED           → tumbling physics; respawns after timer

enum State { MOVING, STOPPED, REVERSING, WAITING_AT_JUNCTION, DERAILED }

signal derailed(world_pos: Vector3)   ## emitted once when train first derails

@export var max_speed: float = 8.0
@export var acceleration: float = 5.0
@export var deceleration: float = 7.0

var _gen                          # TrackGenerator (untyped — class-cache bootstrap)
var _station_nodes: Array         # Array of Vector2i
var _color: Color
var _num_cars: int = 0
var _state: State = State.MOVING
var _stop_timer: float = 0.0
var _respawn_timer: float = 0.0
var _current_speed: float = 0.0

# How long to wait when stopped-while-blocked before deciding to reverse.
# Randomised per train so two facing trains don't both reverse simultaneously.
var _patience_limit: float = 2.0
var _patience_timer: float = 0.0

# Reversal targets
var _reverse_target: float = 0.0        # _head_dist to reverse back to
var _reverse_target_node: Vector2i      # grid node at that distance (for rerouting)
var _reverse_wait_timer: float = 0.0    # how long to hold at junction

# Path data
var _path: Array                  # Array of Vector2i
var _path_world: Array            # Array of Vector3 (dense, follows Bezier curves)
var _path_cumlen: Array           # Array of float (cumulative distance per dense point)
var _path_node_cumlen: Array      # Array of float (cumulative distance per grid node in _path)
var _total_path_len: float = 0.0
var _head_dist: float = 0.0

var _cars: Array = []             # Array of Node3D
var _car_areas: Array = []        # Array of Area3D (collision sensors)
var _car_spacing: float = 2.55

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(gen, stations: Array, start: Vector2i, color: Color, num_cars: int) -> void:
	_gen = gen
	_station_nodes = stations
	_color = color
	_num_cars = num_cars
	_patience_limit = randf_range(1.5, 2.8)   # stagger so trains don't all reverse at once
	_build_visuals(num_cars, color)
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
# Avoidance — synchronous direct-space ray, always current
# ---------------------------------------------------------------------------

func _is_path_blocked() -> bool:
	if _cars.is_empty() or _path_world.is_empty():
		return false
	var origin: Vector3 = _cars[0].global_position + Vector3.UP * 0.5
	var target: Vector3 = origin + _heading_dir() * 8.0
	var excl: Array = []
	for area in _car_areas:
		excl.append((area as Area3D).get_rid())
	var params := PhysicsRayQueryParameters3D.create(origin, target, 2, excl)
	params.collide_with_areas = true
	params.collide_with_bodies = false
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	if result.is_empty():
		return false
	var collider = result.get("collider")
	if collider is Area3D and collider.has_meta("owning_train"):
		var other = collider.get_meta("owning_train")
		return other != self and not other.is_derailed()
	return false

func _heading_dir() -> Vector3:
	if _path_world.size() < 2:
		return Vector3.FORWARD
	return (_sample_path(_head_dist + 0.5) - _sample_path(_head_dist - 0.5)).normalized()

# ---------------------------------------------------------------------------
# Collision detection & derailment
# ---------------------------------------------------------------------------

## Called by Player when the cat swipes this train.
## Derails the train and launches its physics cars in the swipe direction.
func _swipe_derail(swipe_dir: Vector3, force: float) -> void:
	if _state == State.DERAILED:
		return
	_state = State.DERAILED
	derailed.emit(global_position)
	var base_vel := swipe_dir * force * 0.5 + _heading_dir() * _current_speed
	_current_speed = 0.0
	_respawn_timer = 5.5
	for car in _cars:
		var launch: Vector3 = base_vel + swipe_dir * force + Vector3(
			randf_range(-1.5, 1.5), randf_range(1.5, 4.0), randf_range(-1.5, 1.5))
		_spawn_physics_car(car, launch)
		car.visible = false

func _on_car_area_entered(other_area: Area3D) -> void:
	if _state == State.DERAILED:
		return
	if not other_area.has_meta("owning_train"):
		return
	var other_train = other_area.get_meta("owning_train")
	if other_train == self or other_train.is_derailed():
		return
	if _current_speed >= 1.8:
		_derail()

func _derail() -> void:
	if _state == State.DERAILED:
		return
	_state = State.DERAILED
	derailed.emit(global_position)
	var vel := _heading_dir() * _current_speed
	_current_speed = 0.0
	_respawn_timer = 5.5

	for area in _car_areas:
		for other_var in area.get_overlapping_areas():
			var other_area := other_var as Area3D
			if other_area != null and other_area.has_meta("owning_train"):
				var other = other_area.get_meta("owning_train")
				if other != self and not other.is_derailed():
					other.call("_derail")

	for car in _cars:
		var scatter: Vector3 = vel + Vector3(
			randf_range(-1.5, 1.5), randf_range(0.5, 3.0), randf_range(-1.5, 1.5))
		_spawn_physics_car(car, scatter)
		car.visible = false

func _spawn_physics_car(car: Node3D, launch_vel: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.global_transform = car.global_transform
	rb.mass = 1.5
	rb.collision_layer = 9   # layer 1 (world) + layer 8 (customer hit detection)
	rb.collision_mask  = 1   # collide with world floor/table
	# Copy every MeshInstance3D from the original car so it keeps its look.
	# Build a list of the new materials so we can fade them all together.
	var fade_mats: Array = []
	for child in car.get_children():
		if child is MeshInstance3D:
			var src := child as MeshInstance3D
			var mi  := MeshInstance3D.new()
			mi.mesh     = src.mesh
			mi.position = src.position
			mi.rotation = src.rotation
			mi.scale    = src.scale
			var orig := src.material_override as StandardMaterial3D
			var new_mat := StandardMaterial3D.new()
			if orig != null:
				new_mat.albedo_color = orig.albedo_color
			new_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mi.material_override = new_mat
			rb.add_child(mi)
			fade_mats.append(new_mat)
	# Bounding-box collider (approximate is fine for tumbling physics)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.1, 1.3, 1.5)
	cs.shape = shape
	cs.position = Vector3(0, 0.65, 0)
	rb.add_child(cs)
	rb.linear_velocity  = launch_vel
	rb.angular_velocity = Vector3(
		randf_range(-5.0, 5.0), randf_range(-2.0, 2.0), randf_range(-5.0, 5.0))
	get_parent().add_child(rb)
	var tween := rb.create_tween()
	tween.tween_interval(3.5)
	tween.tween_method(func(a: float) -> void:
		for m in fade_mats:
			(m as StandardMaterial3D).albedo_color.a = a
		, 1.0, 0.0, 1.5)
	tween.tween_callback(func() -> void: rb.queue_free())

# ---------------------------------------------------------------------------
# Path sampling
# ---------------------------------------------------------------------------

func _build_path_data() -> void:
	_path_world       = []
	_path_cumlen      = [0.0]
	_path_node_cumlen = []
	_total_path_len   = 0.0
	var first_segment := true
	for i in range(_path.size() - 1):
		var a: Vector2i = _path[i]
		var b: Vector2i = _path[i + 1]
		if i == 0:
			_path_node_cumlen.append(_total_path_len)
		var pts: Array = _gen.get_edge_curve(a, b)
		if pts.is_empty():
			pts = [_gen.nodes[a], _gen.nodes[b]]
		# Skip index 0 after the first segment — it duplicates the previous segment's last point
		var start_j: int = 0 if first_segment else 1
		for j in range(start_j, pts.size()):
			var pt: Vector3 = pts[j]
			_path_world.append(pt)
			if _path_world.size() > 1:
				var seg: float = (_path_world[-2] as Vector3).distance_to(pt)
				_total_path_len += seg
				_path_cumlen.append(_total_path_len)
		first_segment = false
		# Record cumulative distance at grid node b (before any junction arc)
		_path_node_cumlen.append(_total_path_len)
		# Splice junction arc between this edge and the next
		if _gen._is_pullback_node(b) and i + 2 < _path.size():
			var arc: Array = _gen.get_junction_arc(b, a, _path[i + 2])
			for j in range(1, arc.size()):   # skip index 0 = duplicate of edge endpoint
				var pt: Vector3 = arc[j]
				_path_world.append(pt)
				var seg: float = (_path_world[-2] as Vector3).distance_to(pt)
				_total_path_len += seg
				_path_cumlen.append(_total_path_len)
	# Single-node path edge case
	if _path_world.is_empty() and _path.size() > 0:
		_path_world.append(_gen.nodes[_path[0]])
		_path_node_cumlen.append(0.0)

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
	_path = _bfs(from, options[randi() % options.size()])
	_build_path_data()
	_head_dist = (_cars.size() - 1) * _car_spacing
	_patience_timer = 0.0
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
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			_respawn()
		return
	match _state:
		State.MOVING:             _tick_moving(delta)
		State.STOPPED:            _tick_stopped(delta)
		State.REVERSING:          _tick_reversing(delta)
		State.WAITING_AT_JUNCTION: _tick_waiting_at_junction(delta)

func _tick_stopped(delta: float) -> void:
	_stop_timer -= delta
	if _stop_timer <= 0.0:
		_depart_from(_path[_path.size() - 1])

func _tick_moving(delta: float) -> void:
	var blocked := _is_path_blocked()

	# Patience: count up while fully stopped and blocked.
	# When patience runs out, reverse to yield at a junction.
	if blocked and _current_speed < 0.15:
		_patience_timer += delta
		if _patience_timer >= _patience_limit:
			_start_reversing()
			return
	else:
		_patience_timer = 0.0

	var want_speed := max_speed if not blocked else 0.0
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

## Begin reversing: find the nearest junction behind the locomotive and back up to it.
func _start_reversing() -> void:
	_patience_timer = 0.0
	_reverse_target = _find_junction_behind()

	# Already at or behind the junction — skip straight to waiting
	if _head_dist - _reverse_target < 0.5:
		_state = State.WAITING_AT_JUNCTION
		_reverse_wait_timer = randf_range(1.5, 3.0)
		return

	_state = State.REVERSING

## Walk backwards along _path from the current position to find the nearest
## junction node (3+ connections). Returns the cumulative path distance there.
func _find_junction_behind() -> float:
	# Use _path_node_cumlen (one entry per grid node) to avoid out-of-bounds on
	# _path[], which is far smaller than the dense _path_cumlen after Bezier expansion.
	var cur_idx := 0
	for i in range(_path_node_cumlen.size() - 1):
		if _head_dist >= _path_node_cumlen[i]:
			cur_idx = i

	for i in range(cur_idx, -1, -1):
		var gpos: Vector2i = _path[i]
		if (_gen.adjacency.get(gpos, []) as Array).size() >= 3:
			_reverse_target_node = gpos
			return _path_node_cumlen[i]

	# No junction on this path — reverse to start and reroute from there
	_reverse_target_node = _path[0]
	return 0.0

## Reverse along the current path (decreasing _head_dist) until reaching the junction.
## The train keeps facing forward (looks like it's reversing, not turning around).
func _tick_reversing(delta: float) -> void:
	var rev_speed := max_speed * 0.55
	var rate := deceleration if _current_speed > rev_speed else acceleration
	_current_speed = move_toward(_current_speed, rev_speed, rate * delta)

	_head_dist -= _current_speed * delta

	if _head_dist <= _reverse_target:
		_head_dist = maxf(_reverse_target, 0.0)
		_current_speed = 0.0
		_update_car_transforms()
		_state = State.WAITING_AT_JUNCTION
		_reverse_wait_timer = randf_range(2.0, 4.0)
	else:
		_update_car_transforms()

## Hold at the junction. Resume forward the moment the path clears.
## If still blocked when the timer expires, reroute to a new destination.
func _tick_waiting_at_junction(delta: float) -> void:
	_reverse_wait_timer -= delta

	if not _is_path_blocked():
		_patience_timer = 0.0
		_state = State.MOVING
		return

	if _reverse_wait_timer <= 0.0:
		_depart_from(_reverse_target_node)

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

func _respawn() -> void:
	var new_train = get_script().new()
	new_train.max_speed    = max_speed
	new_train.acceleration = acceleration
	new_train.deceleration = deceleration
	var parent := get_parent()
	parent.add_child(new_train)
	new_train.call("setup", _gen, _station_nodes,
		_station_nodes[randi() % _station_nodes.size()], _color, _num_cars)
	# Re-register with CustomerManager so the new train's derailed signal is tracked
	var mgr := parent.get_node_or_null("CustomerManager")
	if mgr != null:
		mgr.call("register_train", new_train)
	queue_free()

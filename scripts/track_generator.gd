extends Node3D
class_name TrackGenerator

## Procedurally generates a 3D railroad network on a grid.
## Uses randomized Prim's spanning tree + extra edges for connectivity
## with lots of junctions and loops.

@export var grid_width: int = 12
@export var grid_height: int = 12
@export var cell_size: float = 8.0
@export var extra_edge_chance: float = 0.60

## Public: Vector2i grid pos -> Vector3 world pos
var nodes: Dictionary = {}
## Public: Vector2i -> Array of Vector2i neighbors (bidirectional)
var adjacency: Dictionary = {}

var _edges: Array = []
var _edge_set: Dictionary = {}
var _rail_mat: StandardMaterial3D
var _tie_mat: StandardMaterial3D

func _ready() -> void:
	_build_materials()
	_build_nodes()
	_build_spanning_tree()
	_add_extra_edges()
	_render_all()

func _build_materials() -> void:
	_rail_mat = StandardMaterial3D.new()
	_rail_mat.albedo_color = Color(0.52, 0.52, 0.56)
	_tie_mat = StandardMaterial3D.new()
	_tie_mat.albedo_color = Color(0.28, 0.18, 0.10)

func _build_nodes() -> void:
	var half_w: float = grid_width * cell_size * 0.5
	var half_h: float = grid_height * cell_size * 0.5
	for x in range(grid_width):
		for z in range(grid_height):
			nodes[Vector2i(x, z)] = Vector3(
				x * cell_size - half_w,
				0.0,
				z * cell_size - half_h
			)

func _build_spanning_tree() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var visited: Dictionary = {}
	var frontier: Array = []
	var start := Vector2i(rng.randi() % grid_width, rng.randi() % grid_height)
	visited[start] = true
	_push_neighbors(start, visited, frontier)
	while frontier.size() > 0:
		var idx := rng.randi() % frontier.size()
		var edge: Array = frontier[idx]
		frontier.remove_at(idx)
		var to: Vector2i = edge[1]
		if visited.has(to):
			continue
		visited[to] = true
		_add_edge(edge[0], to)
		_push_neighbors(to, visited, frontier)

func _push_neighbors(node: Vector2i, visited: Dictionary, frontier: Array) -> void:
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nb: Vector2i = node + offset
		if nodes.has(nb) and not visited.has(nb):
			frontier.append([node, nb])

func _add_extra_edges() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for x in range(grid_width):
		for z in range(grid_height):
			var from := Vector2i(x, z)
			for offset in [Vector2i(1, 0), Vector2i(0, 1)]:
				var to: Vector2i = from + offset
				if nodes.has(to) and rng.randf() < extra_edge_chance:
					_add_edge(from, to)

func _add_edge(a: Vector2i, b: Vector2i) -> void:
	var key: String
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		key = "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	else:
		key = "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]
	if _edge_set.has(key):
		return
	_edge_set[key] = true
	_edges.append([a, b])
	# Build adjacency (bidirectional)
	if not adjacency.has(a):
		adjacency[a] = []
	if not adjacency.has(b):
		adjacency[b] = []
	(adjacency[a] as Array).append(b)
	(adjacency[b] as Array).append(a)

func _render_all() -> void:
	for edge in _edges:
		_spawn_segment(nodes[edge[0]], nodes[edge[1]])

## Returns up to max_count boundary grid nodes that have track connections,
## shuffled so station placement is random each run.
func get_boundary_nodes(max_count: int) -> Array:
	var candidates: Array = []
	for x in range(grid_width):
		for z in range(grid_height):
			var gpos := Vector2i(x, z)
			var on_edge: bool = (x == 0 or x == grid_width - 1 or z == 0 or z == grid_height - 1)
			if on_edge and adjacency.has(gpos) and (adjacency[gpos] as Array).size() > 0:
				candidates.append(gpos)
	candidates.shuffle()
	return candidates.slice(0, min(max_count, candidates.size()))

## Returns the world-space outward direction for a boundary grid node.
func get_outward_dir(gpos: Vector2i) -> Vector3:
	if gpos.x == 0:
		return Vector3(-1, 0, 0)
	elif gpos.x == grid_width - 1:
		return Vector3(1, 0, 0)
	elif gpos.y == 0:
		return Vector3(0, 0, -1)
	return Vector3(0, 0, 1)

func _spawn_segment(from: Vector3, to: Vector3) -> void:
	var length: float = from.distance_to(to)
	var center: Vector3 = (from + to) * 0.5
	var dir: Vector3 = (to - from).normalized()
	var yaw: float = atan2(-dir.z, dir.x)
	var perp: Vector3 = Vector3(-dir.z, 0.0, dir.x)

	var ballast := _make_mesh_instance(Vector3(length, 0.06, 1.6), Color(0.55, 0.50, 0.44))
	ballast.position = center + Vector3.UP * 0.02
	ballast.rotation.y = yaw
	add_child(ballast)

	for side in [-0.58, 0.58]:
		var rail := _make_static_box(Vector3(length - 0.1, 0.13, 0.10), _rail_mat)
		rail.position = center + perp * side + Vector3.UP * 0.13
		rail.rotation.y = yaw
		add_child(rail)

	var num_ties: int = max(2, int(length / 0.85))
	for i in range(num_ties):
		var t: float = (float(i) + 0.5) / float(num_ties)
		var tie := _make_static_box(Vector3(0.20, 0.08, 1.30), _tie_mat)
		tie.position = from.lerp(to, t) + Vector3.UP * 0.05
		tie.rotation.y = yaw
		add_child(tie)

func _make_mesh_instance(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	return mi

func _make_static_box(size: Vector3, mat: StandardMaterial3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body

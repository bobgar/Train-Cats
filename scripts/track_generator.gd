extends Node3D
class_name TrackGenerator

## Procedurally generates a 3D railroad network on a grid.
## Uses randomized Prim's spanning tree + extra edges for connectivity
## with lots of junctions and loops.
## Each edge is rendered as a smooth cubic Bezier curve with tangents
## smoothed by neighbouring connections, giving organic railway curves.

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
var _edge_curves: Dictionary = {}   # canonical key -> Array[Vector3] sampled curve points
var _junction_arcs: Dictionary = {} # center|nb_a|nb_b key -> Array[Vector3] arc points
var _station_set: Dictionary = {}   # Vector2i gpos -> true; these nodes skip pullback
const _CORNER_RADIUS: float = 2.6
var _rail_mat: StandardMaterial3D
var _tie_mat: StandardMaterial3D

func _ready() -> void:
	_build_materials()
	_build_nodes()
	_build_spanning_tree()
	_add_extra_edges()
	_apply_node_jitter()   # must be after adjacency is final, before curve math
	# Curves and rendering are deferred — call build_curves_and_render() from main
	# after station nodes are known, so only station nodes skip pullback/arcs.

## Called from main.gd after stations are placed so _station_set is populated first.
func build_curves_and_render(station_nodes: Array) -> void:
	for gpos_var in station_nodes:
		_station_set[gpos_var as Vector2i] = true
	_build_all_curves()
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

# ---------------------------------------------------------------------------
# Node jitter — offset interior nodes to break grid regularity
# ---------------------------------------------------------------------------

func _apply_node_jitter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var jitter: float = cell_size * 0.28   # ±2.24 units; min gap stays > 3.5 units
	for x in range(grid_width):
		for z in range(grid_height):
			var is_boundary: bool = (x == 0 or x == grid_width - 1
				or z == 0 or z == grid_height - 1)
			if is_boundary:
				continue
			var gpos := Vector2i(x, z)
			var w: Vector3 = nodes[gpos]
			w.x += rng.randf_range(-jitter, jitter)
			w.z += rng.randf_range(-jitter, jitter)
			nodes[gpos] = w

# ---------------------------------------------------------------------------
# Pullback helpers — shorten edges near interior nodes for junction arcs
# ---------------------------------------------------------------------------

func _is_pullback_node(gpos: Vector2i) -> bool:
	return not _station_set.has(gpos)   # every non-station node gets pullback + arcs

func _pullback_point(node_gpos: Vector2i, neighbor_gpos: Vector2i) -> Vector3:
	var center_pos: Vector3 = nodes[node_gpos]
	var nb_pos: Vector3 = nodes[neighbor_gpos]
	var dist: float = center_pos.distance_to(nb_pos)
	var radius: float = minf(_CORNER_RADIUS, dist * 0.42)
	return center_pos + (nb_pos - center_pos).normalized() * radius

# ---------------------------------------------------------------------------
# Bezier curve generation
# ---------------------------------------------------------------------------

func _canonical_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]

func _canonical_a_is_first(a: Vector2i, b: Vector2i) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)

## Returns the unit departure direction from node_gpos heading toward toward_gpos,
## smoothed through the node when an "opposite" neighbour exists.
func _compute_tangent(node_gpos: Vector2i, toward_gpos: Vector2i) -> Vector3:
	var a_pos: Vector3 = nodes[node_gpos]
	var b_pos: Vector3 = nodes[toward_gpos]
	var a_to_b: Vector3 = (b_pos - a_pos).normalized()
	var best_dot: float = 0.0
	var best_pos: Vector3 = Vector3.ZERO
	var found: bool = false
	for nb_var in (adjacency.get(node_gpos, []) as Array):
		var nb: Vector2i = nb_var
		if nb == toward_gpos:
			continue
		var a_to_nb: Vector3 = (nodes[nb] - a_pos).normalized()
		var d: float = a_to_nb.dot(a_to_b)
		if d < best_dot:
			best_dot = d
			best_pos = nodes[nb]
			found = true
	if found and best_dot < -0.4:
		return (b_pos - best_pos).normalized()
	return a_to_b

func _cubic_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return p0*(u*u*u) + p1*(3.0*u*u*t) + p2*(3.0*u*t*t) + p3*(t*t*t)

func _build_curve_for_edge(a: Vector2i, b: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var p0: Vector3 = _pullback_point(a, b) if _is_pullback_node(a) else nodes[a]
	var p3: Vector3 = _pullback_point(b, a) if _is_pullback_node(b) else nodes[b]
	var chord: float = p0.distance_to(p3)
	if chord < 0.01:
		return
	var cp_dist: float = chord * 0.33
	var tan_a: Vector3 = _compute_tangent(a, b)   # departure from A toward B
	var tan_b: Vector3 = _compute_tangent(b, a)   # departure from B toward A
	# p1 displaced forward from A; p2 displaced A-ward from B (tan_b points toward A)
	var p1: Vector3 = p0 + tan_a * cp_dist
	var p2: Vector3 = p3 + tan_b * cp_dist
	# Gentle C-curve offset — suppressed at pullback endpoints to preserve junction arc continuity
	var perp: Vector3 = Vector3(-tan_a.z, 0.0, tan_a.x).normalized()
	var c_off: float = rng.randf_range(-0.55, 0.55)
	if not _is_pullback_node(a):
		p1 += perp * c_off
	if not _is_pullback_node(b):
		p2 += perp * c_off
	var num_pts: int = maxi(8, int(chord / 0.5))
	var pts: Array = []
	for i in range(num_pts + 1):
		pts.append(_cubic_bezier(p0, p1, p2, p3, float(i) / float(num_pts)))
	# Store in canonical (smaller-first) order
	if not _canonical_a_is_first(a, b):
		pts.reverse()
	_edge_curves[_canonical_key(a, b)] = pts

func _build_all_curves() -> void:
	for edge in _edges:
		_build_curve_for_edge(edge[0], edge[1])
	_compute_all_junction_arcs()

## Public: returns dense curve points for edge a→b in the correct traversal direction.
func get_edge_curve(a: Vector2i, b: Vector2i) -> Array:
	var key: String = _canonical_key(a, b)
	if not _edge_curves.has(key):
		return []
	var stored: Array = _edge_curves[key]
	if _canonical_a_is_first(a, b):
		return stored
	var rev: Array = stored.duplicate()
	rev.reverse()
	return rev

# ---------------------------------------------------------------------------
# Junction arc generation — fills the gap at interior nodes between two edges
# ---------------------------------------------------------------------------

func _junction_arc_key(center: Vector2i, nb_a: Vector2i, nb_b: Vector2i) -> String:
	var a: Vector2i = nb_a
	var b: Vector2i = nb_b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var tmp: Vector2i = a; a = b; b = tmp
	return "%d,%d|%d,%d|%d,%d" % [center.x, center.y, a.x, a.y, b.x, b.y]

func _junction_arc_a_is_first(nb_a: Vector2i, nb_b: Vector2i) -> bool:
	return nb_a.x < nb_b.x or (nb_a.x == nb_b.x and nb_a.y < nb_b.y)

func _compute_junction_arc(center: Vector2i, nb_a: Vector2i, nb_b: Vector2i) -> void:
	var p0: Vector3 = _pullback_point(center, nb_a)
	var p3: Vector3 = _pullback_point(center, nb_b)
	var chord: float = p0.distance_to(p3)
	if chord < 0.01:
		return
	# tan_in: direction arriving at the junction from nb_a side
	# tan_out_inv: direction pointing back from nb_b side toward junction (for p2 placement)
	var tan_in: Vector3 = (nodes[center] - nodes[nb_a]).normalized()
	var tan_out_inv: Vector3 = -(nodes[nb_b] - nodes[center]).normalized()
	var cp_dist: float = chord * 0.45
	var p1: Vector3 = p0 + tan_in * cp_dist
	var p2: Vector3 = p3 + tan_out_inv * cp_dist
	var num_pts: int = maxi(4, int(chord / 0.5))
	var pts: Array = []
	for i in range(num_pts + 1):
		pts.append(_cubic_bezier(p0, p1, p2, p3, float(i) / float(num_pts)))
	if not _junction_arc_a_is_first(nb_a, nb_b):
		pts.reverse()
	_junction_arcs[_junction_arc_key(center, nb_a, nb_b)] = pts

func _compute_all_junction_arcs() -> void:
	for gpos_var in adjacency.keys():
		var center: Vector2i = gpos_var
		if not _is_pullback_node(center):
			continue
		var nbs: Array = adjacency.get(center, []) as Array
		for i in range(nbs.size()):
			for j in range(i + 1, nbs.size()):
				var nb_a: Vector2i = nbs[i]
				var nb_b: Vector2i = nbs[j]
				_compute_junction_arc(center, nb_a, nb_b)

## Public: returns junction arc points for a train passing through center from from_nb to to_nb.
func get_junction_arc(center: Vector2i, from_nb: Vector2i, to_nb: Vector2i) -> Array:
	var key := _junction_arc_key(center, from_nb, to_nb)
	if not _junction_arcs.has(key):
		return []
	var stored: Array = _junction_arcs[key]
	if _junction_arc_a_is_first(from_nb, to_nb):
		return stored
	var rev: Array = stored.duplicate()
	rev.reverse()
	return rev

## Returns all sampled world-space points on every track curve and junction arc.
## Called by EnvironmentSpawner after build_curves_and_render() to find clear space.
func get_all_sample_points() -> Array:
	var pts: Array = []
	for key in _edge_curves.keys():
		for pt_var in (_edge_curves[key] as Array):
			pts.append(pt_var)
	for key in _junction_arcs.keys():
		for pt_var in (_junction_arcs[key] as Array):
			pts.append(pt_var)
	return pts

## Returns edge-curve points only (no junction arcs) for building/tree clearance.
## Junction arc midpoints intrude into cell interiors and would block all placement.
func get_edge_sample_points() -> Array:
	var pts: Array = []
	for key in _edge_curves.keys():
		for pt_var in (_edge_curves[key] as Array):
			pts.append(pt_var)
	return pts

## Returns the raw [[a, b], ...] edge list for tunnel selection.
func get_edges() -> Array:
	return _edges

## Returns true if gpos is a station node (skips pullback / junction arcs).
func is_station(gpos: Vector2i) -> bool:
	return _station_set.has(gpos)

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

func _render_all() -> void:
	for edge in _edges:
		_spawn_curved_segment(get_edge_curve(edge[0], edge[1]))
	# Render junction arcs to fill gaps at interior nodes
	for gpos_var in adjacency.keys():
		var center: Vector2i = gpos_var
		if not _is_pullback_node(center):
			continue
		var nbs: Array = adjacency.get(center, []) as Array
		for i in range(nbs.size()):
			for j in range(i + 1, nbs.size()):
				var nb_a: Vector2i = nbs[i]
				var nb_b: Vector2i = nbs[j]
				var arc: Array = get_junction_arc(center, nb_a, nb_b)
				if not arc.is_empty():
					_spawn_curved_segment(arc)

## Renders ballast, rails, and ties along a dense array of curve points.
func _spawn_curved_segment(points: Array) -> void:
	var n: int = points.size()
	if n < 2:
		return
	for i in range(n - 1):
		var seg_from: Vector3 = points[i]
		var seg_to: Vector3   = points[i + 1]
		var seg_len: float    = seg_from.distance_to(seg_to)
		if seg_len < 0.001:
			continue
		var center: Vector3 = (seg_from + seg_to) * 0.5
		var dir: Vector3    = (seg_to - seg_from).normalized()
		var yaw: float      = atan2(-dir.z, dir.x)
		var perp: Vector3   = Vector3(-dir.z, 0.0, dir.x)
		# Ballast strip
		var ballast := _make_mesh_instance(
			Vector3(seg_len + 0.02, 0.06, 1.6), Color(0.55, 0.50, 0.44))
		ballast.position  = center + Vector3.UP * 0.02
		ballast.rotation.y = yaw
		add_child(ballast)
		# Two rails
		for side in [-0.58, 0.58]:
			var rail := _make_static_box(
				Vector3(seg_len + 0.02, 0.13, 0.10), _rail_mat)
			rail.position   = center + perp * side + Vector3.UP * 0.13
			rail.rotation.y = yaw
			add_child(rail)
		# Ties
		var num_ties: int = maxi(1, int(seg_len / 0.85))
		for j in range(num_ties):
			var t: float = (float(j) + 0.5) / float(num_ties)
			var tie := _make_static_box(Vector3(0.20, 0.08, 1.30), _tie_mat)
			tie.position   = seg_from.lerp(seg_to, t) + Vector3.UP * 0.05
			tie.rotation.y = yaw
			add_child(tie)

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
	body.collision_layer = 4   # separate layer so the player (mask=1) walks over rails
	body.collision_mask  = 0
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

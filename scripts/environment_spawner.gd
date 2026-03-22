extends Node3D
class_name EnvironmentSpawner

## Populates the world with buildings and trees, avoiding railroad tracks.
## Three building styles (industrial shed, brick block, glass office) each
## spawn with randomised height, width, and length. Trees spawn in clumps.

const _BLDG_COUNT  := 38
const _BLDG_TRIES  := 350
const _TREE_CLUMPS := 32
const _TRACK_GAP   := 1.5   # min clearance (units) from track centerline to building edge / tree centre
const _BLDG_SEP    := 1.8   # min gap between building footprints

const _TUNNEL_COUNT  := 4
const _TUNNEL_WALL_H := 3.0    # interior height — fits player capsule (1.55) with margin
const _TUNNEL_HALF_W := 1.2    # interior half-width — clears ballast (0.8 half) with margin
const _TUNNEL_WALL_T := 0.45   # wall / ceiling thickness

var _rng := RandomNumberGenerator.new()
var _track_pts := PackedVector2Array()   # XZ of every track sample point
var _bldgs: Array = []                   # [{cx, cz, rx, rz}] of placed buildings

# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

func setup(gen) -> void:
	_rng.randomize()
	var raw: Array = gen.get_edge_sample_points()
	_track_pts.resize(raw.size())
	for i in range(raw.size()):
		var p: Vector3 = raw[i] as Vector3
		_track_pts[i] = Vector2(p.x, p.z)
	_place_buildings()
	_place_trees()
	_place_tunnels(gen)

# ---------------------------------------------------------------------------
# Spatial helpers
# ---------------------------------------------------------------------------

## True if xz is within r units of any track sample point.
func _near_track(xz: Vector2, r: float) -> bool:
	var r2 := r * r
	for tp: Vector2 in _track_pts:
		if xz.distance_squared_to(tp) < r2:
			return true
	return false

## True if the building rectangle (cx,cz) ± (rx,rz) is at least _TRACK_GAP away
## from every track sample point, using exact point-to-rectangle distance.
func _rect_clear_of_track(cx: float, cz: float, rx: float, rz: float) -> bool:
	var r2 := _TRACK_GAP * _TRACK_GAP
	for tp: Vector2 in _track_pts:
		var dx := tp.x - cx
		var dz := tp.y - cz
		# Quick AABB reject — point outside expanded bounding box → skip
		if absf(dx) > rx + _TRACK_GAP or absf(dz) > rz + _TRACK_GAP:
			continue
		# Exact nearest-point-on-rectangle distance
		var nx := clampf(dx, -rx, rx)
		var nz := clampf(dz, -rz, rz)
		if (dx - nx) * (dx - nx) + (dz - nz) * (dz - nz) < r2:
			return false
	return true

## True if the building footprint does NOT overlap any previously placed building.
func _rect_clear_of_bldgs(cx: float, cz: float, rx: float, rz: float) -> bool:
	for b in _bldgs:
		if absf(cx - b.cx) < rx + b.rx + _BLDG_SEP and absf(cz - b.cz) < rz + b.rz + _BLDG_SEP:
			return false
	return true

# ---------------------------------------------------------------------------
# Building placement
# ---------------------------------------------------------------------------

func _place_buildings() -> void:
	var placed := 0
	for _i in range(_BLDG_TRIES):
		if placed >= _BLDG_COUNT:
			break
		var cx := _rng.randf_range(-26.0, 20.0)
		var cz := _rng.randf_range(-26.0, 20.0)
		var style := _rng.randi() % 3
		var w: float; var h: float; var l: float
		match style:
			0:  # Industrial shed — wide, low
				w = _rng.randf_range(6.0, 14.0)
				l = _rng.randf_range(8.0, 18.0)
				h = _rng.randf_range(3.5, 6.0)
			1:  # Brick block — medium width, tall
				w = _rng.randf_range(4.0, 8.5)
				l = _rng.randf_range(4.0, 9.0)
				h = _rng.randf_range(5.0, 11.0)
			_:  # Glass office — compact footprint, very tall
				w = _rng.randf_range(4.0, 8.0)
				l = _rng.randf_range(4.0, 8.0)
				h = _rng.randf_range(8.0, 15.0)
		var rx := w * 0.5
		var rz := l * 0.5
		if not _rect_clear_of_track(cx, cz, rx, rz): continue
		if not _rect_clear_of_bldgs(cx, cz, rx, rz): continue
		var root := Node3D.new()
		root.position = Vector3(cx, 0.0, cz)
		match style:
			0: _bldg_industrial(root, w, h, l)
			1: _bldg_brick(root, w, h, l)
			_: _bldg_office(root, w, h, l)
		add_child(root)
		_bldgs.append({cx = cx, cz = cz, rx = rx, rz = rz})
		placed += 1

# ---------------------------------------------------------------------------
# Building styles
# ---------------------------------------------------------------------------

## Style 0 — Industrial / Warehouse
## Wide, low profile with a peaked roof ridge and optional chimney stack.
func _bldg_industrial(root: Node3D, w: float, h: float, l: float) -> void:
	var bc := Color(
		_rng.randf_range(0.48, 0.62),
		_rng.randf_range(0.50, 0.62),
		_rng.randf_range(0.48, 0.60))
	# Main body (collision + mesh)
	_sb(root, Vector3(w, h, l), bc).position = Vector3(0, h * 0.5, 0)
	# Dark base band
	_mi(root, Vector3(w + 0.08, 0.38, l + 0.08), bc.darkened(0.28)).position = Vector3(0, 0.19, 0)
	# Flat eave overhang
	_mi(root, Vector3(w + 0.55, 0.24, l + 0.55), bc.darkened(0.18)).position = Vector3(0, h + 0.12, 0)
	# Peaked ridge — square cross-section box rotated 45° along its length
	var rs := h * 0.22
	var ridge := _mi(root, Vector3(l + 0.28, rs * 1.42, rs * 1.42), bc.lightened(0.06))
	ridge.position = Vector3(0, h + rs, 0)
	ridge.rotation_degrees.x = 45.0
	# Chimney / vent (50% chance)
	if _rng.randf() > 0.50:
		var ch := _mi(root, Vector3(0.46, _rng.randf_range(0.8, 1.5), 0.46), bc.darkened(0.38))
		ch.position = Vector3(
			_rng.randf_range(-w * 0.28, w * 0.28), h + 0.55,
			_rng.randf_range(-l * 0.28, l * 0.28))
	# Dock door on one long face
	var door := _mi(root, Vector3(w * 0.28, h * 0.48, 0.10), bc.darkened(0.50))
	door.position = Vector3(0, h * 0.24, l * 0.5 + 0.05)

## Style 1 — Brick Block / Apartment
## Taller footprint with horizontal window rows on all four sides.
func _bldg_brick(root: Node3D, w: float, h: float, l: float) -> void:
	var warm := _rng.randf() > 0.45
	var bc: Color
	if warm:
		bc = Color(_rng.randf_range(0.50, 0.62), _rng.randf_range(0.26, 0.38), _rng.randf_range(0.18, 0.28))
	else:
		bc = Color(_rng.randf_range(0.40, 0.54), _rng.randf_range(0.38, 0.50), _rng.randf_range(0.40, 0.52))
	_sb(root, Vector3(w, h, l), bc).position = Vector3(0, h * 0.5, 0)
	# Roof parapet
	_mi(root, Vector3(w + 0.24, 0.50, l + 0.24), bc.darkened(0.22)).position = Vector3(0, h + 0.25, 0)
	# Horizontal window bands, one per floor
	var floors := maxi(1, int(h / 2.8))
	for f in range(floors):
		var fy: float
		if floors == 1:
			fy = h * 0.55
		else:
			fy = 1.1 + float(f) * (h - 1.8) / float(floors - 1)
		fy = clampf(fy, 0.7, h - 0.5)
		var wc := Color(0.75, 0.86, 0.96) if _rng.randf() > 0.30 else Color(0.92, 0.82, 0.56)
		var wh := 0.44
		# Front and back glass strips
		for side in [-1.0, 1.0]:
			_mi(root, Vector3(w * 0.74, wh, 0.09), wc).position = Vector3(0, fy, side * (l * 0.5 + 0.05))
		# Left and right glass strips
		for side in [-1.0, 1.0]:
			_mi(root, Vector3(0.09, wh, l * 0.70), wc).position = Vector3(side * (w * 0.5 + 0.05), fy, 0)
	# Entrance recess on front face
	var ent := _mi(root, Vector3(w * 0.22, h * 0.22, 0.10), bc.darkened(0.55))
	ent.position = Vector3(0, h * 0.11, l * 0.5 + 0.05)

## Style 2 — Glass Office Tower
## Tall, glassy, with thin horizontal floor bands and a rooftop crown.
func _bldg_office(root: Node3D, w: float, h: float, l: float) -> void:
	var hue := _rng.randf_range(-0.07, 0.07)
	var bc := Color(0.28 + hue, 0.44, 0.70)
	_sb(root, Vector3(w, h, l), bc).position = Vector3(0, h * 0.5, 0)
	# Horizontal floor bands
	var band_c := bc.lightened(0.16)
	var bands := maxi(2, int(h / 2.2))
	for b_i in range(1, bands):
		var by := float(b_i) * h / float(bands)
		_mi(root, Vector3(w + 0.15, 0.15, l + 0.15), band_c).position = Vector3(0, by, 0)
	# Setback crown
	_mi(root, Vector3(w * 0.62, 0.52, l * 0.62), bc.lightened(0.24)).position = Vector3(0, h + 0.26, 0)
	# Antenna mast on taller towers
	if h > 10.0:
		_mi(root, Vector3(0.11, _rng.randf_range(1.0, 1.8), 0.11),
			bc.lightened(0.32)).position = Vector3(0, h + 0.78, 0)
	# Subtle corner pillars
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mi(root, Vector3(0.22, h, 0.22), bc.darkened(0.10)).position = Vector3(sx * w * 0.5, h * 0.5, sz * l * 0.5)

# ---------------------------------------------------------------------------
# Tree placement
# ---------------------------------------------------------------------------

func _place_trees() -> void:
	for _ci in range(_TREE_CLUMPS):
		var cx := _rng.randf_range(-26.0, 20.0)
		var cz := _rng.randf_range(-26.0, 20.0)
		# 18% chance of a lone tree, otherwise a clump of 3–7
		var count := 1 if _rng.randf() < 0.18 else _rng.randi_range(3, 7)
		for _ti in range(count):
			var tx := cx + (_rng.randf_range(-4.5, 4.5) if count > 1 else 0.0)
			var tz := cz + (_rng.randf_range(-4.5, 4.5) if count > 1 else 0.0)
			if _near_track(Vector2(tx, tz), _TRACK_GAP):
				continue
			var sc := _rng.randf_range(0.70, 1.40)
			var node := Node3D.new()
			node.position = Vector3(tx, 0.0, tz)
			if _rng.randi() % 2 == 0:
				_tree_conifer(node, sc)
			else:
				_tree_round(node, sc)
			add_child(node)

# ---------------------------------------------------------------------------
# Tree styles
# ---------------------------------------------------------------------------

## Conifer — three stacked pyramid-shaped foliage tiers over a thin trunk.
func _tree_conifer(node: Node3D, s: float) -> void:
	_mi(node, Vector3(0.13 * s, 0.65 * s, 0.13 * s),
		Color(0.28, 0.18, 0.11)).position = Vector3(0, 0.33 * s, 0)
	var greens := [Color(0.13, 0.38, 0.15), Color(0.16, 0.46, 0.18), Color(0.19, 0.53, 0.21)]
	var wids   := [1.28, 0.90, 0.55]
	var base   := 0.55 * s
	for i in range(3):
		_mi(node, Vector3(wids[i] * s, 0.60 * s, wids[i] * s),
			greens[i]).position = Vector3(0, base + float(i) * 0.50 * s, 0)

## Round deciduous tree — trunk plus a low-poly sphere canopy.
func _tree_round(node: Node3D, s: float) -> void:
	_mi(node, Vector3(0.17 * s, 0.90 * s, 0.17 * s),
		Color(0.30, 0.20, 0.12)).position = Vector3(0, 0.45 * s, 0)
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.84 * s
	sphere.height = 1.40 * s
	sphere.radial_segments = 6
	sphere.rings = 4
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, _rng.randf_range(0.34, 0.50), 0.13)
	mi.material_override = mat
	mi.position = Vector3(0, (0.90 + 0.70) * s, 0)   # place sphere bottom at trunk top
	node.add_child(mi)

# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

## StaticBody3D box — used for the main building body (player collision on layer 1).
func _sb(parent: Node3D, size: Vector3, color: Color) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask  = 0
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	sb.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	return sb

## MeshInstance3D box — used for roof, windows, and other decorative detail.
func _mi(parent: Node3D, size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	parent.add_child(mi)
	return mi

# ---------------------------------------------------------------------------
# Tunnel placement
# ---------------------------------------------------------------------------

func _place_tunnels(gen) -> void:
	var edges: Array = gen.get_edges()
	var candidates: Array = []
	for edge_var in edges:
		var edge: Array = edge_var as Array
		var a: Vector2i = edge[0]
		var b: Vector2i = edge[1]
		if gen.is_station(a) or gen.is_station(b):
			continue
		var pts: Array = gen.get_edge_curve(a, b)
		if pts.size() >= 8:
			candidates.append(edge)
	candidates.shuffle()
	var count: int = mini(_TUNNEL_COUNT, candidates.size())
	for i in range(count):
		var edge: Array = candidates[i] as Array
		var pts: Array = gen.get_edge_curve(edge[0], edge[1])
		_spawn_tunnel(pts)

## Spawns a box tunnel over the middle ~44% of an edge curve.
## Walls have collision (layer 1) so the player can walk through but not clip sides.
func _spawn_tunnel(pts: Array) -> void:
	var n: int = pts.size()
	var si: int = int(n * 0.28)
	var ei: int = int(n * 0.72)
	if ei - si < 3:
		return
	var wall_col   := Color(0.33, 0.30, 0.28)
	var portal_col := Color(0.22, 0.20, 0.19)
	var outer_half: float = _TUNNEL_HALF_W + _TUNNEL_WALL_T

	# Tunnel body: walls + ceiling per segment
	for i in range(si, ei - 1):
		var p0: Vector3  = pts[i]
		var p1: Vector3  = pts[i + 1]
		var seg_len: float = p0.distance_to(p1)
		if seg_len < 0.001:
			continue
		var ctr: Vector3  = (p0 + p1) * 0.5
		var dir: Vector3  = (p1 - p0).normalized()
		var yaw: float    = atan2(-dir.z, dir.x)
		var perp: Vector3 = Vector3(-dir.z, 0.0, dir.x)
		var sl: float     = seg_len + 0.04

		var lw := _sb(self, Vector3(sl, _TUNNEL_WALL_H, _TUNNEL_WALL_T), wall_col)
		lw.position  = ctr + perp * (_TUNNEL_HALF_W + _TUNNEL_WALL_T * 0.5) + Vector3.UP * (_TUNNEL_WALL_H * 0.5)
		lw.rotation.y = yaw

		var rw := _sb(self, Vector3(sl, _TUNNEL_WALL_H, _TUNNEL_WALL_T), wall_col)
		rw.position  = ctr - perp * (_TUNNEL_HALF_W + _TUNNEL_WALL_T * 0.5) + Vector3.UP * (_TUNNEL_WALL_H * 0.5)
		rw.rotation.y = yaw

		var ceil := _mi(self, Vector3(sl, _TUNNEL_WALL_T, outer_half * 2), wall_col)
		ceil.position  = ctr + Vector3.UP * (_TUNNEL_WALL_H + _TUNNEL_WALL_T * 0.5)
		ceil.rotation.y = yaw

	# Portal frames at entry and exit
	for is_entry in [true, false]:
		var pt: Vector3
		var dir: Vector3
		if is_entry:
			pt  = pts[si]
			dir = (pts[si + 1] - pts[si]).normalized()
		else:
			pt  = pts[ei - 1]
			dir = (pts[ei - 1] - pts[ei - 2]).normalized()
		var yaw: float    = atan2(-dir.z, dir.x)
		var perp: Vector3 = Vector3(-dir.z, 0.0, dir.x)
		var pw: float     = _TUNNEL_WALL_T * 2.0
		var ph: float     = _TUNNEL_WALL_H + _TUNNEL_WALL_T + pw

		# Side pillars
		var lp := _mi(self, Vector3(pw, ph, pw), portal_col)
		lp.position  = pt + perp * (outer_half + pw * 0.5) + Vector3.UP * (ph * 0.5)
		lp.rotation.y = yaw
		var rp := _mi(self, Vector3(pw, ph, pw), portal_col)
		rp.position  = pt - perp * (outer_half + pw * 0.5) + Vector3.UP * (ph * 0.5)
		rp.rotation.y = yaw
		# Lintel across top
		var li := _mi(self, Vector3(pw, pw, outer_half * 2 + pw * 2), portal_col)
		li.position  = pt + Vector3.UP * (_TUNNEL_WALL_H + _TUNNEL_WALL_T + pw * 0.5)
		li.rotation.y = yaw

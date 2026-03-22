extends Node3D
class_name Station

## A train station placed at a boundary grid node.
## Visually extends outward from the track network.

var grid_pos: Vector2i

func setup(gpos: Vector2i, world_pos: Vector3, out_dir: Vector3) -> void:
	grid_pos = gpos
	position = world_pos
	_build(out_dir)

func _build(out_dir: Vector3) -> void:
	# Perpendicular vector in the XZ plane (for column spacing along platform length)
	var perp := Vector3(-out_dir.z, 0.0, out_dir.x)
	# Platform box orientation: 2.5 deep (along out_dir), 4.8 wide (perpendicular)
	var rot_y := atan2(-out_dir.z, out_dir.x)
	var base := out_dir * 2.8

	# --- Platform slab ---
	var plat := _sbox(Vector3(2.5, 0.35, 4.8), Color(0.70, 0.66, 0.60))
	plat.position = base + Vector3.UP * 0.175
	plat.rotation.y = rot_y
	add_child(plat)

	# --- Canopy roof ---
	var canopy := _sbox(Vector3(2.5, 0.12, 4.8), Color(0.46, 0.15, 0.09))
	canopy.position = base + Vector3.UP * 1.88
	canopy.rotation.y = rot_y
	add_child(canopy)

	# --- Support columns (offset along perp so they straddle the platform) ---
	for side in [-2.0, 2.0]:
		var col := _sbox(Vector3(0.14, 1.52, 0.14), Color(0.28, 0.28, 0.32))
		col.position = base + perp * side + Vector3.UP * 0.94
		add_child(col)

	# --- Yellow sign board (faces away from track) ---
	var board := _sbox(Vector3(1.4, 0.48, 0.10), Color(0.92, 0.82, 0.16))
	board.position = base + out_dir * 1.5 + Vector3.UP * 1.5
	board.rotation.y = rot_y
	add_child(board)

	# --- Sign post ---
	var post := _sbox(Vector3(0.10, 1.1, 0.10), Color(0.22, 0.22, 0.25))
	post.position = base + out_dir * 1.5 + Vector3.UP * 0.55
	add_child(post)

## StaticBody3D box with mesh + collision.
func _sbox(size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	return body

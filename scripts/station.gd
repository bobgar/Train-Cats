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
	var plat := MeshBuilder.static_colored_box(self, Vector3(2.5, 0.35, 4.8), Color(0.70, 0.66, 0.60), base + Vector3.UP * 0.175)
	plat.rotation.y = rot_y

	# --- Canopy roof ---
	var canopy := MeshBuilder.static_colored_box(self, Vector3(2.5, 0.12, 4.8), Color(0.46, 0.15, 0.09), base + Vector3.UP * 1.88)
	canopy.rotation.y = rot_y

	# --- Support columns (offset along perp so they straddle the platform) ---
	for side in [-2.0, 2.0]:
		MeshBuilder.static_colored_box(self, Vector3(0.14, 1.52, 0.14), Color(0.28, 0.28, 0.32), base + perp * side + Vector3.UP * 0.94)

	# --- Yellow sign board (faces away from track) ---
	var board := MeshBuilder.static_colored_box(self, Vector3(1.4, 0.48, 0.10), Color(0.92, 0.82, 0.16), base + out_dir * 1.5 + Vector3.UP * 1.5)
	board.rotation.y = rot_y

	# --- Sign post ---
	MeshBuilder.static_colored_box(self, Vector3(0.10, 1.1, 0.10), Color(0.22, 0.22, 0.25), base + out_dir * 1.5 + Vector3.UP * 0.55)

extends Node
## Shared factory methods for creating colored box meshes and solid physics boxes.
## Replaces the duplicate _mi / _mi_box / _sb / _sbox / _solid_box /
## _make_mesh_instance helpers that previously existed in six different scripts.

## Creates a MeshInstance3D with a BoxMesh of the given size and color,
## adds it to parent at pos, and returns it (caller may set rotation etc.).
static func colored_box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh   = mesh
	var mat   := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

## Creates a StaticBody3D (mesh + BoxShape3D collision) with the given size and color,
## adds it to parent at pos on the given collision layer, and returns it.
## collision_mask is always 0 — static scenery does not need to query anything.
static func static_colored_box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, collision_layer: int = 1) -> StaticBody3D:
	var sb    := StaticBody3D.new()
	sb.collision_layer = collision_layer
	sb.collision_mask  = 0
	var mi    := MeshInstance3D.new()
	var mesh  := BoxMesh.new()
	mesh.size  = size
	mi.mesh    = mesh
	var mat    := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	sb.add_child(mi)
	var cs    := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape   = shape
	sb.add_child(cs)
	sb.position = pos
	parent.add_child(sb)
	return sb

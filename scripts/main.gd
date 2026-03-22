extends Node3D

const TRAIN_COLORS: Array = [
	Color(0.88, 0.14, 0.14),  # Red
	Color(0.14, 0.34, 0.90),  # Blue
	Color(0.14, 0.72, 0.28),  # Green
	Color(0.96, 0.58, 0.08),  # Orange
	Color(0.62, 0.14, 0.80),  # Purple
	Color(0.90, 0.84, 0.12),  # Yellow
	Color(0.12, 0.70, 0.74),  # Teal
	Color(0.90, 0.30, 0.65),  # Pink
]

const TrackGeneratorScript = preload("res://scripts/track_generator.gd")
const StationScript = preload("res://scripts/station.gd")
const TrainScript = preload("res://scripts/train.gd")
const PlayerScript = preload("res://scripts/player.gd")

func _ready() -> void:
	_setup_environment()
	_add_ground()
	var gen = _add_tracks()
	var station_gpos: Array = _spawn_stations(gen)
	_spawn_trains(gen, station_gpos)
	_spawn_player()

func _setup_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var proc_sky := ProceduralSkyMaterial.new()
	proc_sky.sky_top_color = Color(0.18, 0.38, 0.72)
	proc_sky.sky_horizon_color = Color(0.55, 0.68, 0.88)
	proc_sky.ground_horizon_color = Color(0.38, 0.48, 0.28)
	proc_sky.ground_bottom_color = Color(0.18, 0.28, 0.12)
	sky.sky_material = proc_sky
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)

func _add_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	var mi := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(300, 300)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.42, 0.25)
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	add_child(body)

func _add_tracks():
	var gen = TrackGeneratorScript.new()
	gen.name = "TrackGenerator"
	add_child(gen)
	return gen

func _spawn_stations(gen) -> Array:
	var boundary: Array = gen.get_boundary_nodes(10)
	var station_gpos: Array = []
	for gpos_var in boundary:
		var gpos: Vector2i = gpos_var
		var world_pos: Vector3 = gen.nodes[gpos]
		var out_dir: Vector3 = gen.get_outward_dir(gpos)
		var station = StationScript.new()
		station.name = "Station_%d_%d" % [gpos.x, gpos.y]
		station.call("setup", gpos, world_pos, out_dir)
		add_child(station)
		station_gpos.append(gpos)
	return station_gpos

func _spawn_player() -> void:
	var player = PlayerScript.new()
	player.name = "Player"
	player.position = Vector3(0, 2, 0)
	add_child(player)

func _spawn_trains(gen, stations: Array) -> void:
	if stations.size() < 2:
		return
	var num_trains: int = mini(7, stations.size())
	for i in range(num_trains):
		var start: Vector2i = stations[i % stations.size()]
		var color: Color = TRAIN_COLORS[i % TRAIN_COLORS.size()]
		var num_cars: int = 2 + (i % 4)  # 2, 3, 4, or 5 cars

		# Smaller trains are faster and more agile; larger trains are slower and sluggish.
		# size_t: 0.0 = 2-car (lightest), 1.0 = 5-car (heaviest)
		var size_t: float = float(num_cars - 2) / 3.0
		var train = TrainScript.new()
		train.name = "Train_%d" % i
		train.max_speed  = lerp(11.5, 5.5, size_t) + randf_range(-0.5, 0.5)
		train.acceleration = lerp(9.0,  2.0, size_t)
		train.deceleration = lerp(14.0, 4.5, size_t)
		add_child(train)
		train.call("setup", gen, stations, start, color, num_cars)

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

const TrackGeneratorScript     = preload("res://scripts/track_generator.gd")
const StationScript            = preload("res://scripts/station.gd")
const TrainScript              = preload("res://scripts/train.gd")
const PlayerScript             = preload("res://scripts/player.gd")
const EnvironmentSpawnerScript = preload("res://scripts/environment_spawner.gd")
const CustomerManagerScript    = preload("res://scripts/customer_manager.gd")
const HUDScript                = preload("res://scripts/hud.gd")
const TitleScreenScript        = preload("res://scripts/title_screen.gd")
const RoundScoreboardScript    = preload("res://scripts/round_scoreboard.gd")

# Track grid is set to 8×8 at 7.0 units → nodes span approx ±28 in X and Z.
# TABLE is sized to contain the track + station platforms.
# Room walls are pushed far on 3 sides so the table is clearly smaller than the room.
const TABLE_HW   := 34.0   # table half-width  (X): table spans -34 to +34
const TABLE_HD   := 34.0   # table half-depth  (Z): table spans -34 to +34

const FRONT_WALL_Z := -42.0  # exterior / window wall — table is "against" this
const BACK_WALL_Z  :=  95.0  # kitchen wall — far behind the table
const SIDE_WALL_X  :=  78.0  # side walls — wide gap beside the table
const ROOM_FLOOR   := -22.0  # visual cafe floor level
const WALL_TOP     :=  28.0  # top of all walls

# Derived conveniences
const WALL_H   := WALL_TOP - ROOM_FLOOR   # 50
const WALL_CY  := ROOM_FLOOR + WALL_H * 0.5   # 3  (wall centre Y)

# ---------------------------------------------------------------------------
# Round progression: points needed to pass each round
# Formula: 9n² + 9n + 22  (n = round number)
# Matches the original hand-tuned values closely and grows to infinity:
#   R1=40  R2=76  R3=130  R4=202  R5=292  R6=400  R7=526  R8=670 …
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Game state
# ---------------------------------------------------------------------------
enum GameState { TITLE, PLAYING, ROUND_END, GAME_OVER }

var _game_state: GameState = GameState.TITLE
var _current_round: int    = 1

# Node references built in _ready
var _player_node: Node      = null
var _customer_manager: Node = null
var _hud: Node              = null
var _title_screen: Node     = null
var _round_scoreboard: Node = null
var _gameplay_cam: Camera3D = null   # normal play camera (child of player)
var _cinematic_cam: Camera3D = null  # zoom-in cam during round end

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_setup_environment()
	_add_ground()
	_add_table_structure()
	_add_cafe_room()
	var gen = _add_tracks()
	var station_gpos: Array = _spawn_stations(gen)
	gen.call("build_curves_and_render", station_gpos)
	_spawn_world_objects(gen)

	_player_node      = _spawn_player()
	_customer_manager = _spawn_customer_manager(_player_node)
	_spawn_trains(gen, station_gpos, _customer_manager)
	_spawn_cinematic_cam()

	_hud             = HUDScript.new()
	_hud.name        = "HUD"
	add_child(_hud)
	_customer_manager.score_changed.connect(_hud.update_score)

	_title_screen      = TitleScreenScript.new()
	_title_screen.name = "TitleScreen"
	add_child(_title_screen)
	_title_screen.continue_pressed.connect(_on_title_continue)

	_round_scoreboard      = RoundScoreboardScript.new()
	_round_scoreboard.name = "RoundScoreboard"
	add_child(_round_scoreboard)
	_round_scoreboard.continue_pressed.connect(_on_scoreboard_continue)

	_connect_hud_signals()

	# Start paused at title screen
	get_tree().paused = true
	_title_screen.configure(false)

func _spawn_world_objects(gen) -> void:
	var env := EnvironmentSpawnerScript.new()
	env.name = "EnvironmentSpawner"
	add_child(env)
	env.call("setup", gen)

# ---------------------------------------------------------------------------
# Game state transitions
# ---------------------------------------------------------------------------

func _on_title_continue() -> void:
	_start_round()

func _start_round() -> void:
	_game_state = GameState.PLAYING
	_customer_manager.call("reset_round")
	var req := _round_requirement(_current_round)
	_hud.start_round(_current_round, req)
	get_tree().paused = false
	# Make sure gameplay camera is active
	if _gameplay_cam != null:
		_gameplay_cam.current = true
	if _cinematic_cam != null:
		_cinematic_cam.current = false

func _on_hud_time_up() -> void:
	if _game_state != GameState.PLAYING:
		return
	_end_round()

func _end_round() -> void:
	_game_state = GameState.ROUND_END
	_hud.stop()
	get_tree().paused = true

	var stats: Dictionary = _customer_manager.call("get_stats")
	var score: int   = stats.get("score", 0)
	var req: int     = _round_requirement(_current_round)
	var passed: bool = score >= req

	# Cinematic zoom — tween camera toward cat's face then show scoreboard
	_do_cinematic_zoom(func() -> void:
		_round_scoreboard.show_result(
			score, req,
			stats.get("impressed", 0), stats.get("hit", 0),
			passed, _current_round))

func _on_scoreboard_continue() -> void:
	var stats: Dictionary = _customer_manager.call("get_stats")
	var score: int   = stats.get("score", 0)
	var req: int     = _round_requirement(_current_round)
	var passed: bool = score >= req

	# Restore gameplay camera
	if _gameplay_cam != null:
		_gameplay_cam.current = true
	if _cinematic_cam != null:
		_cinematic_cam.current = false

	if passed:
		_current_round += 1
		_start_round()
	else:
		# Game over — show title with game-over header
		_game_state    = GameState.GAME_OVER
		_current_round = 1
		_title_screen.configure(true)

func _round_requirement(round_num: int) -> int:
	var n := float(round_num)
	return roundi(9.0 * n * n + 9.0 * n + 22.0)

# ---------------------------------------------------------------------------
# Cinematic camera zoom
# ---------------------------------------------------------------------------

func _spawn_cinematic_cam() -> void:
	_cinematic_cam          = Camera3D.new()
	_cinematic_cam.name     = "CinematicCam"
	_cinematic_cam.current  = false
	add_child(_cinematic_cam)

func _do_cinematic_zoom(on_done: Callable) -> void:
	if _player_node == null or not is_instance_valid(_player_node):
		on_done.call()
		return

	_cinematic_cam.current = true
	if _gameplay_cam != null:
		_gameplay_cam.current = false

	# Snapshot cat position once — clamp y so the orbit stays above the table
	# even if the cat is mid-fall when the round ends.
	var cat_pos: Vector3 = _player_node.global_position
	cat_pos.y = maxf(cat_pos.y, 0.0)
	var look_target      := cat_pos + Vector3(0.0, 1.2, 0.0)

	# Orbit 180° around the cat: start behind (+Z) and sweep to front (-Z),
	# descending from a wide radius to a close one.
	# angle = 0 → behind (cat_pos + (0, h, r)), angle = PI → front (cat_pos + (0, h, -r))
	var start_radius := 22.0
	var end_radius   :=  7.0
	var start_height := 12.0
	var end_height   :=  3.5

	var tw := create_tween()
	tw.tween_method(
		func(t: float) -> void:
			var angle  : float = t * PI
			var radius : float = lerp(start_radius, end_radius, t)
			var height : float = lerp(start_height, end_height, t)
			var offset := Vector3(sin(angle) * radius, height, cos(angle) * radius)
			_cinematic_cam.global_position = cat_pos + offset
			if _cinematic_cam.global_position.distance_to(look_target) > 0.1:
				_cinematic_cam.look_at(look_target, Vector3.UP),
		0.0, 1.0, 2.0
	).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(on_done)

# ---------------------------------------------------------------------------
# Lighting / sky
# ---------------------------------------------------------------------------

func _setup_environment() -> void:
	var env      := WorldEnvironment.new()
	var e        := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky      := Sky.new()
	var proc_sky := ProceduralSkyMaterial.new()
	proc_sky.sky_top_color        = Color(0.82, 0.72, 0.60)
	proc_sky.sky_horizon_color    = Color(0.90, 0.82, 0.70)
	proc_sky.ground_horizon_color = Color(0.72, 0.64, 0.54)
	proc_sky.ground_bottom_color  = Color(0.58, 0.50, 0.42)
	sky.sky_material = proc_sky
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70, -20, 0)
	sun.light_energy     = 1.2
	sun.light_color      = Color(1.0, 0.94, 0.82)
	sun.shadow_enabled   = true
	add_child(sun)

# ---------------------------------------------------------------------------
# Ground — tile floor everywhere; wood table-top overlay just on table area
# ---------------------------------------------------------------------------

func _add_ground() -> void:
	# Table surface — physics only covers table footprint so player can fall off the edge
	var table := StaticBody3D.new()
	table.name = "TableSurface"
	table.collision_layer = 1
	table.collision_mask  = 0
	var tcs   := CollisionShape3D.new()
	var tbox  := BoxShape3D.new()
	tbox.size  = Vector3(TABLE_HW * 2, 1.0, TABLE_HD * 2)
	tcs.shape  = tbox
	tcs.position = Vector3(0.0, -0.5, 0.0)   # top face sits exactly at y=0
	table.add_child(tcs)
	# Wood surface visual — PlaneMesh (zero thickness) so track ties above y=0 are fully visible
	var wood_mi   := MeshInstance3D.new()
	var wood_mesh := PlaneMesh.new()
	wood_mesh.size = Vector2(TABLE_HW * 2, TABLE_HD * 2)
	wood_mi.mesh   = wood_mesh
	var wood_mat   := StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.72, 0.54, 0.30)
	wood_mi.material_override = wood_mat
	wood_mi.position = Vector3(0.0, 0.001, 0.0)
	table.add_child(wood_mi)
	add_child(table)

	# Cafe floor — infinite physics plane at ROOM_FLOOR so player lands after falling
	var cafe := StaticBody3D.new()
	cafe.name     = "CafeFloor"
	cafe.position = Vector3(0.0, ROOM_FLOOR, 0.0)
	cafe.collision_layer = 1
	cafe.collision_mask  = 0
	var fcs := CollisionShape3D.new()
	fcs.shape = WorldBoundaryShape3D.new()
	cafe.add_child(fcs)
	add_child(cafe)

	# Tile floor visual at ROOM_FLOOR
	var tile_mi   := MeshInstance3D.new()
	var tile_mesh := PlaneMesh.new()
	tile_mesh.size = Vector2(400.0, 400.0)
	tile_mi.mesh   = tile_mesh
	var tile_mat   := StandardMaterial3D.new()
	tile_mat.albedo_color = Color(0.62, 0.56, 0.50)
	tile_mi.material_override = tile_mat
	tile_mi.position = Vector3(0.0, ROOM_FLOOR + 0.001, 0.0)
	add_child(tile_mi)

# ---------------------------------------------------------------------------
# Table — apron edges and legs make the elevated-table read clear
# ---------------------------------------------------------------------------

func _add_table_structure() -> void:
	var wood      := Color(0.58, 0.40, 0.18)
	var wood_dark := Color(0.44, 0.30, 0.12)

	var apron_h  := 4.0
	var apron_cy := 0.12 - apron_h * 0.5   # -1.88 (flush with table top, hanging down)

	# Four apron panels around table perimeter
	_mi_box(Vector3(TABLE_HW * 2 + 4, apron_h, 2.0), wood,
		Vector3(0.0,        apron_cy, -TABLE_HD))
	_mi_box(Vector3(TABLE_HW * 2 + 4, apron_h, 2.0), wood,
		Vector3(0.0,        apron_cy,  TABLE_HD))
	_mi_box(Vector3(2.0, apron_h, TABLE_HD * 2), wood,
		Vector3(-TABLE_HW,  apron_cy,  0.0))
	_mi_box(Vector3(2.0, apron_h, TABLE_HD * 2), wood,
		Vector3( TABLE_HW,  apron_cy,  0.0))

	# Four legs
	var leg_top := 0.12 - apron_h           # -3.88
	var leg_h   := absf(ROOM_FLOOR - leg_top)   # 18.12
	var leg_cy  := leg_top - leg_h * 0.5   # -12.94
	var inset   := 4.0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_mi_box(Vector3(4.0, leg_h, 4.0), wood_dark,
				Vector3(sx * (TABLE_HW - inset), leg_cy, sz * (TABLE_HD - inset)))

	# (cafe floor visual and physics are handled in _add_ground)

# ---------------------------------------------------------------------------
# Cafe room walls
# ---------------------------------------------------------------------------

func _add_cafe_room() -> void:
	_add_exterior_wall()
	_add_kitchen_wall()
	_add_side_walls()
	_add_ceiling()

## Front wall (z = FRONT_WALL_Z) — large picture window; table sits close against it.
func _add_exterior_wall() -> void:
	var plaster := Color(0.86, 0.82, 0.76)
	var trim    := Color(0.32, 0.24, 0.14)
	var sky_c   := Color(0.62, 0.76, 0.92)
	var wz      := FRONT_WALL_Z   # -42

	# Window geometry (absolute Y — clearly above table surface at y=0)
	var win_y   := 10.0
	var win_h   := 18.0   # spans y=1 to y=19
	var win_w   := 40.0
	var win_top := win_y + win_h * 0.5    # 19
	var win_bot := win_y - win_h * 0.5    # 1

	# Wall width spans the full room (−SIDE_WALL_X to +SIDE_WALL_X)
	var side_w  := SIDE_WALL_X - win_w * 0.5  # 58  (each side piece)
	var below_h := win_bot - ROOM_FLOOR         # 23
	var above_h := WALL_TOP - win_top            # 9

	# Four solid pieces around the window opening
	_solid_box(Vector3(side_w, WALL_H, 2.0), plaster,
		Vector3(-(SIDE_WALL_X - side_w * 0.5), WALL_CY, wz))
	_solid_box(Vector3(side_w, WALL_H, 2.0), plaster,
		Vector3(  SIDE_WALL_X - side_w * 0.5,  WALL_CY, wz))
	_solid_box(Vector3(win_w, below_h, 2.0), plaster,
		Vector3(0.0, ROOM_FLOOR + below_h * 0.5, wz))
	_solid_box(Vector3(win_w, above_h, 2.0), plaster,
		Vector3(0.0, win_top + above_h * 0.5, wz))

	# Window glass
	_mi_box(Vector3(win_w, win_h, 0.4), sky_c,
		Vector3(0.0, win_y, wz + 1.0))

	# Window frame strips
	var fw := 1.2
	_mi_box(Vector3(win_w + fw * 2, fw, 0.7), trim,
		Vector3(0.0, win_top + fw * 0.5, wz + 0.7))
	_mi_box(Vector3(win_w + fw * 2, fw, 0.7), trim,
		Vector3(0.0, win_bot - fw * 0.5, wz + 0.7))
	_mi_box(Vector3(fw, win_h + fw * 2, 0.7), trim,
		Vector3(-(win_w * 0.5 + fw * 0.5), win_y, wz + 0.7))
	_mi_box(Vector3(fw, win_h + fw * 2, 0.7), trim,
		Vector3(  win_w * 0.5 + fw * 0.5,  win_y, wz + 0.7))
	_mi_box(Vector3(win_w + fw * 2 + 1, 0.7, 2.0), trim,
		Vector3(0.0, win_bot - fw - 0.35, wz + 0.7))  # sill

	# Cafe sign above window
	_mi_box(Vector3(24.0, 3.5, 0.9), Color(0.26, 0.14, 0.06),
		Vector3(0.0, win_top + fw + 2.5, wz + 0.9))

	# Street scene behind the glass
	_mi_box(Vector3(600, 0.3, 0.4),  Color(0.72, 0.70, 0.66),
		Vector3(0.0,  ROOM_FLOOR,       wz - 6.0))   # sidewalk
	_mi_box(Vector3(12, 26, 0.4),    Color(0.66, 0.62, 0.56),
		Vector3(-14, ROOM_FLOOR + 13,   wz - 10.0))  # building L
	_mi_box(Vector3(16, 20, 0.4),    Color(0.70, 0.66, 0.60),
		Vector3( 12, ROOM_FLOOR + 10,   wz - 13.0))  # building R
	_mi_box(Vector3(0.4, 14, 0.4),   Color(0.22, 0.20, 0.16),
		Vector3(-28, ROOM_FLOOR + 7,    wz - 5.0))   # lamp post
	_mi_box(Vector3(4.0, 0.4, 0.4),  Color(0.22, 0.20, 0.16),
		Vector3(-26.5, ROOM_FLOOR + 14, wz - 5.0))   # lamp arm

## Back wall (z = BACK_WALL_Z) — kitchen; far behind the table.
func _add_kitchen_wall() -> void:
	var tile    := Color(0.90, 0.88, 0.84)
	var cabinet := Color(0.50, 0.36, 0.20)
	var counter := Color(0.78, 0.74, 0.70)
	var wz      := BACK_WALL_Z   # +95

	_solid_box(Vector3(SIDE_WALL_X * 2, WALL_H, 2.0), tile,
		Vector3(0.0, WALL_CY, wz))

	_mi_box(Vector3(120.0, 3.8, 8.0), counter,
		Vector3(0.0, ROOM_FLOOR + 1.9, wz - 5.5))
	_mi_box(Vector3(90.0, 12.0, 5.0), cabinet,
		Vector3(-8.0, ROOM_FLOOR + 22.0, wz - 3.0))
	for di in range(4):
		var dx: float = float(di) * 18.0 - 35.0
		_mi_box(Vector3(16.0, 10.5, 0.5), cabinet.lightened(0.12),
			Vector3(dx, ROOM_FLOOR + 21.5, wz - 5.8))

	_mi_box(Vector3(6.0, 7.0, 5.0), Color(0.14, 0.12, 0.10),
		Vector3(-36.0, ROOM_FLOOR + 5.8, wz - 6.5))   # espresso machine
	_mi_box(Vector3(3.0, 4.0, 3.0), Color(0.22, 0.18, 0.16),
		Vector3(-36.0, ROOM_FLOOR + 9.8, wz - 6.5))   # hopper
	_mi_box(Vector3(10.0, 0.3, 6.0), Color(0.76, 0.76, 0.76),
		Vector3( 12.0, ROOM_FLOOR + 3.95, wz - 6.5))  # sink
	_mi_box(Vector3(0.4,  3.0, 0.4), Color(0.82, 0.82, 0.80),
		Vector3( 12.0, ROOM_FLOOR + 6.0,  wz - 9.5))  # faucet

	var mug_cols: Array = [
		Color(0.92, 0.30, 0.26), Color(0.26, 0.50, 0.88),
		Color(0.28, 0.70, 0.38), Color(0.92, 0.84, 0.28), Color(0.90, 0.88, 0.86)]
	for mi_i in range(mug_cols.size()):
		_mi_box(Vector3(2.0, 2.8, 2.0), mug_cols[mi_i],
			Vector3(float(mi_i) * 8.0 - 20.0, ROOM_FLOOR + 5.3, wz - 7.0))

## Side walls (x = ±SIDE_WALL_X) — each has an 18-unit door gap at z ≈ 0.
## The room runs from FRONT_WALL_Z to BACK_WALL_Z (asymmetric; most space is behind table).
func _add_side_walls() -> void:
	var plaster := Color(0.86, 0.82, 0.76)
	var trim    := Color(0.32, 0.24, 0.14)

	# Room depth: FRONT_WALL_Z to BACK_WALL_Z = -42 to +95  (total 137)
	# Door gap: z = -9 to +9  (18 units)
	var fz       := FRONT_WALL_Z     # -42
	var bz       := BACK_WALL_Z      # +95
	var gap_r    := 9.0
	var front_w  := gap_r - fz       # 51  (z from -42 to -9)
	var back_w   := bz - gap_r       # 86  (z from  +9 to +95)
	var front_cz := fz + front_w * 0.5   # -42 + 25.5 = -16.5
	var back_cz  := gap_r + back_w * 0.5  # 9 + 43 = +52

	for sgn in [-1.0, 1.0]:
		var wx: float = sgn * SIDE_WALL_X

		_solid_box(Vector3(2.0, WALL_H, front_w), plaster, Vector3(wx, WALL_CY, front_cz))
		_solid_box(Vector3(2.0, WALL_H, back_w),  plaster, Vector3(wx, WALL_CY, back_cz))

		# Door jamb posts
		_mi_box(Vector3(1.8, WALL_H, 1.8), trim, Vector3(wx, WALL_CY, -gap_r))
		_mi_box(Vector3(1.8, WALL_H, 1.8), trim, Vector3(wx, WALL_CY,  gap_r))

		# Art print
		var art_c := Color(0.48, 0.62, 0.74) if sgn < 0 else Color(0.62, 0.48, 0.74)
		var inset : float = 0.8 * sgn
		_mi_box(Vector3(0.5, 14.0, 20.0), art_c,  Vector3(wx + inset, 12.0, 30.0))
		_mi_box(Vector3(0.6, 15.5, 21.5), trim,   Vector3(wx + inset, 12.0, 30.0))

func _add_ceiling() -> void:
	_mi_box(Vector3(300.0, 0.8, 300.0), Color(0.92, 0.90, 0.86),
		Vector3(0.0, WALL_TOP, 0.0))
	var lamp_c := Color(0.28, 0.22, 0.14)
	for lx in [-20.0, 0.0, 20.0]:
		_mi_box(Vector3(0.25, 8.0, 0.25), lamp_c, Vector3(lx, WALL_TOP - 4.5, -5.0))
		_mi_box(Vector3(4.0,  2.5, 4.0),  lamp_c, Vector3(lx, WALL_TOP - 9.25, -5.0))

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _solid_box(size: Vector3, color: Color, pos: Vector3) -> StaticBody3D:
	var sb    := StaticBody3D.new()
	sb.collision_layer = 1
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
	add_child(sb)
	return sb

func _mi_box(size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi   := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh   = mesh
	var mat   := StandardMaterial3D.new()
	mat.albedo_color = color
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi

# ---------------------------------------------------------------------------
# Track — smaller 8×8 grid so the table is compact relative to the room
# ---------------------------------------------------------------------------

func _add_tracks():
	var gen = TrackGeneratorScript.new()
	# 8×8 grid at 7 units → nodes span ~-28 to +21 in each axis
	# (fits inside the TABLE_HW/HD=34 footprint with station platform margin)
	gen.grid_width  = 8
	gen.grid_height = 8
	gen.cell_size   = 7.0
	gen.name = "TrackGenerator"
	add_child(gen)
	return gen

func _spawn_stations(gen) -> Array:
	var boundary: Array = gen.get_boundary_nodes(10)
	var station_gpos: Array = []
	for gpos_var in boundary:
		var gpos: Vector2i   = gpos_var
		var world_pos: Vector3 = gen.nodes[gpos]
		var out_dir: Vector3   = gen.get_outward_dir(gpos)
		var station = StationScript.new()
		station.name = "Station_%d_%d" % [gpos.x, gpos.y]
		station.call("setup", gpos, world_pos, out_dir)
		add_child(station)
		station_gpos.append(gpos)
	return station_gpos

func _spawn_player() -> Node:
	var player = PlayerScript.new()
	player.name = "Player"
	player.position = Vector3(0, 2, 0)
	# PAUSABLE so player controls freeze whenever get_tree().paused = true.
	# (main.gd is PROCESS_MODE_ALWAYS for tweens; children inherit that unless overridden.)
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	# Player's _ready runs synchronously during add_child; camera exists now
	_gameplay_cam = _find_camera(player)
	return player

func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child in node.get_children():
		var result := _find_camera(child)
		if result != null:
			return result
	return null

func _spawn_customer_manager(player: Node) -> Node:
	var mgr = CustomerManagerScript.new()
	mgr.name = "CustomerManager"
	add_child(mgr)
	mgr.call("setup", player, TABLE_HW, TABLE_HD)
	# Connect timer's time_up after HUD is created (done in _ready after this call)
	return mgr

func _spawn_trains(gen, stations: Array, manager: Node) -> void:
	if stations.size() < 2:
		return
	var num_trains: int = mini(7, stations.size())
	for i in range(num_trains):
		var start: Vector2i = stations[i % stations.size()]
		var color: Color    = TRAIN_COLORS[i % TRAIN_COLORS.size()]
		var num_cars: int   = 2 + (i % 4)
		var size_t: float   = float(num_cars - 2) / 3.0
		var train = TrainScript.new()
		train.name         = "Train_%d" % i
		train.max_speed    = lerp(11.5, 5.5, size_t) + randf_range(-0.5, 0.5)
		train.acceleration = lerp(9.0,  2.0, size_t)
		train.deceleration = lerp(14.0, 4.5, size_t)
		add_child(train)
		train.call("setup", gen, stations, start, color, num_cars)
		manager.call("register_train", train)

# Connect HUD time_up after HUD exists — called at end of _ready
func _connect_hud_signals() -> void:
	_hud.time_up.connect(_on_hud_time_up)

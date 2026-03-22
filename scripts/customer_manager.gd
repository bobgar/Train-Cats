extends Node3D
class_name CustomerManager

## Manages the pool of cafe customers who peek over the table edge.
## Maintains ~MAX_ACTIVE customers at all times, respawning them after
## a short delay. Connects to train derail signals and awards points.

const CafeCustomerScript = preload("res://scripts/cafe_customer.gd")

const MAX_ACTIVE      := 5
const RESPAWN_DELAY   := 5.0
const PTS_CONE_DERAIL := 10   # points when watched train is knocked over
const PTS_HIT_DEBRIS  := 25   # points when hit by flying train debris

# Customer y-position when hidden (must match CafeCustomer.HIDE_Y)
const _HIDE_Y := -6.0

var _player: Node3D = null
var _table_hw: float = 34.0
var _table_hd: float = 34.0
var _customers: Array = []       # active CafeCustomer nodes
var _spawn_timers: Array = []    # remaining wait times before next spawn
var _score: int = 0
var _score_label: Label = null
var _rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func setup(player: Node3D, table_hw: float, table_hd: float) -> void:
	_rng.randomize()
	_player   = player
	_table_hw = table_hw
	_table_hd = table_hd
	_build_score_ui()
	# Stagger initial spawns slightly so they don't all pop up at once
	for i in range(MAX_ACTIVE):
		_spawn_timers.append(float(i) * 0.8)

func register_train(train: Node) -> void:
	train.derailed.connect(_on_train_derailed)   # signature: (world_pos, by_player)

# ---------------------------------------------------------------------------
# Per-frame management
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	# Tick spawn timers; fire when they reach zero
	var fired: Array = []
	for i in range(_spawn_timers.size()):
		_spawn_timers[i] -= delta
		if _spawn_timers[i] <= 0.0:
			fired.append(i)
	# Remove in reverse order to preserve indices
	for i in range(fired.size() - 1, -1, -1):
		_spawn_timers.remove_at(fired[i])
	for _f in fired:
		_spawn_one()

# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------

## Minimum XZ distance between any two customer spawn points.
## Head width is 6.2 units; 12 leaves ~5.8 units of gap between head edges.
const MIN_SEP := 12.0
## Offset customers this far outside the table apron edges (aprons are 2 units
## thick centred at ±TABLE_HW/HD so outer face is at ±(TABLE_HW+1)).
const SPAWN_OFFSET := 3.5
const SPAWN_MARGIN := 4.0   # stay back from table corners on each edge

func _spawn_one() -> void:
	var total := _customers.size() + _spawn_timers.size()
	if total >= MAX_ACTIVE:
		return

	# Try up to 20 random positions; skip any that would overlap an existing customer.
	for _attempt in range(20):
		var edge := _rng.randi() % 4
		var pos  := Vector3.ZERO
		var face := Vector3.ZERO
		match edge:
			0:   # +X
				pos  = Vector3(_table_hw + SPAWN_OFFSET, _HIDE_Y,
					_rng.randf_range(-_table_hd + SPAWN_MARGIN, _table_hd - SPAWN_MARGIN))
				face = Vector3(-1.0, 0.0, 0.0)
			1:   # -X
				pos  = Vector3(-_table_hw - SPAWN_OFFSET, _HIDE_Y,
					_rng.randf_range(-_table_hd + SPAWN_MARGIN, _table_hd - SPAWN_MARGIN))
				face = Vector3(1.0, 0.0, 0.0)
			2:   # +Z
				pos  = Vector3(
					_rng.randf_range(-_table_hw + SPAWN_MARGIN, _table_hw - SPAWN_MARGIN),
					_HIDE_Y, _table_hd + SPAWN_OFFSET)
				face = Vector3(0.0, 0.0, -1.0)
			3:   # -Z
				pos  = Vector3(
					_rng.randf_range(-_table_hw + SPAWN_MARGIN, _table_hw - SPAWN_MARGIN),
					_HIDE_Y, -_table_hd - SPAWN_OFFSET)
				face = Vector3(0.0, 0.0, 1.0)

		# Reject if too close to any existing customer (XZ only — y varies during rise)
		var too_close := false
		for c in _customers:
			if not is_instance_valid(c):
				continue
			var dx: float = c.position.x - pos.x
			var dz: float = c.position.z - pos.z
			if dx * dx + dz * dz < MIN_SEP * MIN_SEP:
				too_close = true
				break
		if too_close:
			continue

		# Valid position found — spawn here
		var customer := CafeCustomerScript.new()
		customer.position = pos
		add_child(customer)
		customer.call("setup", _player, face)
		customer.done.connect(_on_customer_done.bind(customer))
		_customers.append(customer)
		_track_hit_score(customer)
		return
	# All 20 attempts overlapped — silently skip; next respawn timer will retry

## Connect a one-shot check so we award PTS_HIT_DEBRIS the first time
## the customer is hit (before "done" fires).
func _track_hit_score(customer: Node) -> void:
	# We poll via the customer's Area3D body_entered — but that already calls
	# trigger_hit internally.  Simplest hook: connect a thin lambda to the
	# Area3D's body_entered signal on the customer's hit area.
	for child in customer.get_children():
		if child is Area3D:
			child.body_entered.connect(func(_b: Node3D) -> void:
				_add_score(PTS_HIT_DEBRIS)
				_update_ui())
			break

# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

func _on_train_derailed(world_pos: Vector3, by_player: bool) -> void:
	# Customers only react when the CAT caused the crash, not train-vs-train
	if not by_player:
		return
	for c in _customers:
		if not is_instance_valid(c):
			continue
		if c.call("is_in_view_cone", world_pos):
			c.call("trigger_happy")
			_add_score(PTS_CONE_DERAIL)
	_update_ui()

func _on_customer_done(customer: Node) -> void:
	_customers.erase(customer)
	_spawn_timers.append(RESPAWN_DELAY)

# ---------------------------------------------------------------------------
# Score
# ---------------------------------------------------------------------------

func _add_score(pts: int) -> void:
	_score += pts
	_update_ui()

func _update_ui() -> void:
	if _score_label != null:
		_score_label.text = "Score: %d" % _score

# ---------------------------------------------------------------------------
# Score UI
# ---------------------------------------------------------------------------

func _build_score_ui() -> void:
	var canvas     := CanvasLayer.new()
	canvas.layer   = 10
	var label      := Label.new()
	label.text     = "Score: 0"
	label.position = Vector2(16.0, 16.0)

	# Style — slightly transparent dark background, large white text
	var settings := LabelSettings.new()
	settings.font_size    = 28
	settings.font_color   = Color(1.0, 1.0, 1.0)
	settings.outline_size = 3
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.8)
	label.label_settings  = settings

	canvas.add_child(label)
	add_child(canvas)
	_score_label = label

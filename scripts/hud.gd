extends CanvasLayer
class_name HUD

## In-game HUD: round timer (centre top), score (top-left), round number (top-right).
## Emits time_up when the 60-second round timer expires.

signal time_up

const ROUND_DURATION := 60.0

var _timer_label: Label = null
var _score_label: Label = null
var _round_label: Label = null

var _time_left: float  = ROUND_DURATION
var _active: bool      = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	_build_ui()

func _build_ui() -> void:
	var viewport_w := 1280.0   # design resolution — labels anchor by position

	# Score — top-left
	_score_label = _make_label("Score: 0", Vector2(16, 16), 28)
	add_child(_score_label)

	# Round — top-right
	_round_label = _make_label("Round 1", Vector2(viewport_w - 160, 16), 28)
	add_child(_round_label)

	# Timer — top-centre
	_timer_label = _make_label("1:00", Vector2(viewport_w * 0.5 - 60, 16), 36)
	add_child(_timer_label)

func _make_label(txt: String, pos: Vector2, fsize: int) -> Label:
	var lbl := Label.new()
	lbl.text     = txt
	lbl.position = pos
	var settings := LabelSettings.new()
	settings.font_size     = fsize
	settings.font_color    = Color(1.0, 1.0, 1.0)
	settings.outline_size  = 3
	settings.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	lbl.label_settings = settings
	return lbl

# ---------------------------------------------------------------------------
# Public API (called from main.gd)
# ---------------------------------------------------------------------------

func start_round(round_num: int, required: int) -> void:
	_time_left = ROUND_DURATION
	_active    = true
	_round_label.text = "Round %d  (need %d)" % [round_num, required]
	_update_timer_label()

func stop() -> void:
	_active = false

func update_score(new_score: int) -> void:
	_score_label.text = "Score: %d" % new_score

# ---------------------------------------------------------------------------
# Per-frame
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_active    = false
		_update_timer_label()
		time_up.emit()
		return
	_update_timer_label()

func _update_timer_label() -> void:
	var secs := int(ceil(_time_left))
	var m    := secs / 60
	var s    := secs % 60
	_timer_label.text = "%d:%02d" % [m, s]
	# Flash red in the last 10 seconds
	if _time_left <= 10.0:
		_timer_label.label_settings.font_color = Color(1.0, 0.3, 0.3)
	else:
		_timer_label.label_settings.font_color = Color(1.0, 1.0, 1.0)

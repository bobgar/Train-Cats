extends CanvasLayer
class_name HUD

## In-game HUD using anchor-based layout so elements stay in place on any
## screen size.  Score (top-left), Timer (top-centre), Round + Need (top-right).

signal time_up

const ROUND_DURATION := 60.0

var _timer_label:  Label = null
var _score_label:  Label = null
var _round_label:  Label = null
var _needed_label: Label = null
var _root:         Control = null

var _time_left: float = ROUND_DURATION
var _active:    bool  = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer   = 10
	visible = false
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Score — top-left
	_score_label  = _a_lbl("Score: 0",  0.01, 0.35, 0.01, 0.09, 28,
		Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)

	# Timer — top-centre (larger font)
	_timer_label  = _a_lbl("1:00",      0.35, 0.65, 0.01, 0.09, 36,
		Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)

	# Round number — top-right first line
	_round_label  = _a_lbl("Round 1",   0.65, 0.99, 0.01, 0.07, 24,
		Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)

	# Points needed — top-right second line
	_needed_label = _a_lbl("Need: 40",  0.65, 0.99, 0.07, 0.13, 20,
		Color(1.0, 1.0, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)

func _a_lbl(text: String, al: float, ar: float, at: float, ab: float,
		fsize: int, col: Color, halign: HorizontalAlignment) -> Label:
	var lbl := Label.new()
	lbl.text                 = text
	lbl.anchor_left          = al
	lbl.anchor_right         = ar
	lbl.anchor_top           = at
	lbl.anchor_bottom        = ab
	lbl.offset_left          = 0
	lbl.offset_right         = 0
	lbl.offset_top           = 0
	lbl.offset_bottom        = 0
	lbl.horizontal_alignment = halign
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	var s := LabelSettings.new()
	s.font_size     = fsize
	s.font_color    = col
	s.outline_size  = 3
	s.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	lbl.label_settings = s
	_root.add_child(lbl)
	return lbl

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_round(round_num: int, required: int) -> void:
	_time_left             = ROUND_DURATION
	_active                = true
	visible                = true
	_round_label.text      = "Round %d" % round_num
	_needed_label.text     = "Need: %d pts" % required
	_score_label.text      = "Score: 0"
	_update_timer_label()

func stop() -> void:
	_active  = false
	visible  = false

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
	_timer_label.text = "%d:%02d" % [secs / 60, secs % 60]
	_timer_label.label_settings.font_color = \
		Color(1.0, 0.3, 0.3) if _time_left <= 10.0 else Color(1.0, 1.0, 1.0)

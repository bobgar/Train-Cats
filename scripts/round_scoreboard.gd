extends CanvasLayer
class_name RoundScoreboard

## Scoreboard panel that swings in from above between rounds.
## Shows score vs required, impressed count, hit count.

signal continue_pressed

var _panel: Control = null
var _title_label: Label = null
var _score_label: Label = null
var _req_label: Label = null
var _impressed_label: Label = null
var _hit_label: Label = null
var _result_label: Label = null
var _hint_label: Label = null

var _ready_for_input: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 15
	visible = false
	_build_ui()

func _build_ui() -> void:
	# Semi-transparent dark background
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Panel
	_panel = Control.new()
	_panel.size     = Vector2(560, 380)
	_panel.position = Vector2(640 - 280, -400)   # starts off-screen above
	add_child(_panel)

	var panel_bg := ColorRect.new()
	panel_bg.color    = Color(0.12, 0.10, 0.08, 0.95)
	panel_bg.size     = Vector2(560, 380)
	panel_bg.position = Vector2.ZERO
	_panel.add_child(panel_bg)

	var border := ColorRect.new()
	border.color    = Color(0.80, 0.70, 0.30)
	border.size     = Vector2(560, 4)
	border.position = Vector2(0, 0)
	_panel.add_child(border)
	var border2 := ColorRect.new()
	border2.color    = Color(0.80, 0.70, 0.30)
	border2.size     = Vector2(560, 4)
	border2.position = Vector2(0, 376)
	_panel.add_child(border2)

	_title_label    = _panel_label("Round Complete!", Vector2(280, 28),  36, Color(1.0, 0.90, 0.30), true)
	_score_label    = _panel_label("Score: 0",        Vector2(280, 90),  30, Color.WHITE, true)
	_req_label      = _panel_label("Required: 0",     Vector2(280, 130), 26, Color(0.85, 0.85, 0.85), true)
	_impressed_label = _panel_label("Impressed: 0",   Vector2(280, 185), 24, Color(0.70, 1.0, 0.70), true)
	_hit_label      = _panel_label("Hit by debris: 0",Vector2(280, 220), 24, Color(1.0, 0.70, 0.40), true)
	_result_label   = _panel_label("PASSED",          Vector2(280, 290), 40, Color(0.30, 1.0, 0.40), true)
	_hint_label     = _panel_label("Press Space to continue", Vector2(280, 348), 20, Color(0.75, 0.75, 0.75), true)

func _panel_label(txt: String, pos: Vector2, fsize: int, col: Color, centred: bool) -> Label:
	var lbl := Label.new()
	lbl.text     = txt
	lbl.position = pos - (Vector2(280, 12) if centred else Vector2.ZERO)
	if centred:
		lbl.size = Vector2(560, 40)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var s := LabelSettings.new()
	s.font_size     = fsize
	s.font_color    = col
	s.outline_size  = 2
	s.outline_color = Color(0, 0, 0, 0.9)
	lbl.label_settings = s
	_panel.add_child(lbl)
	return lbl

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_result(score: int, required: int, impressed: int, hit: int, passed: bool, round_num: int) -> void:
	_ready_for_input = false
	visible = true

	_title_label.text    = "Round %d Complete!" % round_num if passed else "Round %d Failed" % round_num
	_score_label.text    = "Score: %d" % score
	_req_label.text      = "Required: %d" % required
	_impressed_label.text = "Customers impressed: %d" % impressed
	_hit_label.text      = "Customers hit: %d" % hit

	if passed:
		_result_label.text = "PASSED!"
		_result_label.label_settings.font_color = Color(0.30, 1.0, 0.40)
	else:
		_result_label.text = "FAILED"
		_result_label.label_settings.font_color = Color(1.0, 0.30, 0.30)

	# Swing panel in from above (bounce ease)
	_panel.position.y = -400
	var tw := create_tween()
	tw.tween_property(_panel, "position:y", 170.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_callback(func() -> void:
		_ready_for_input = true)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _ready_for_input:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			visible = false
			continue_pressed.emit()

extends CanvasLayer
class_name RoundScoreboard

## Between-round scoreboard.
## Swings in from above by animating the CanvasLayer's own offset property,
## so the whole panel slides down without touching anchor values.
## All text positions are anchor-based fractions of the viewport.

signal continue_pressed

var _title_label:     Label = null
var _score_label:     Label = null
var _req_label:       Label = null
var _impressed_label: Label = null
var _hit_label:       Label = null
var _result_label:    Label = null
var _root:            Control = null

var _ready_for_input: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer   = 15
	visible = false
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Dimmed full-screen backdrop
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.65)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# Dark panel box
	_a_rect(Color(0.12, 0.10, 0.08, 0.96), 0.12, 0.88, 0.08, 0.93)

	# Gold accent strips (top and bottom of panel)
	_a_rect(Color(0.80, 0.70, 0.30, 1.0),  0.12, 0.88, 0.08, 0.095)
	_a_rect(Color(0.80, 0.70, 0.30, 1.0),  0.12, 0.88, 0.915, 0.93)

	# Content labels — all horizontally centred inside the panel column
	_title_label     = _a_lbl("Round Complete!",       0.12, 0.88, 0.10, 0.21, 36, Color(1.0, 0.90, 0.30))
	_score_label     = _a_lbl("Score: 0",              0.12, 0.88, 0.23, 0.33, 30, Color.WHITE)
	_req_label       = _a_lbl("Required: 0",           0.12, 0.88, 0.34, 0.42, 26, Color(0.85, 0.85, 0.85))
	_impressed_label = _a_lbl("Customers impressed: 0",0.12, 0.88, 0.46, 0.54, 24, Color(0.70, 1.0, 0.70))
	_hit_label       = _a_lbl("Customers hit: 0",      0.12, 0.88, 0.55, 0.63, 24, Color(1.0, 0.70, 0.40))
	_result_label    = _a_lbl("PASSED!",               0.12, 0.88, 0.68, 0.81, 42, Color(0.30, 1.0, 0.40))
	_a_lbl("Press Space to continue",                  0.12, 0.88, 0.85, 0.92, 20, Color(0.75, 0.75, 0.75))

func _a_rect(col: Color, al: float, ar: float, at: float, ab: float) -> void:
	var r := ColorRect.new()
	r.color         = col
	r.anchor_left   = al;  r.anchor_right  = ar
	r.anchor_top    = at;  r.anchor_bottom = ab
	r.offset_left   = 0;   r.offset_right  = 0
	r.offset_top    = 0;   r.offset_bottom = 0
	_root.add_child(r)

func _a_lbl(text: String, al: float, ar: float, at: float, ab: float,
		fsize: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text                 = text
	lbl.anchor_left          = al
	lbl.anchor_right         = ar
	lbl.anchor_top           = at
	lbl.anchor_bottom        = ab
	lbl.offset_left          = 0;  lbl.offset_right  = 0
	lbl.offset_top           = 0;  lbl.offset_bottom = 0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	var s := LabelSettings.new()
	s.font_size     = fsize
	s.font_color    = col
	s.outline_size  = 2
	s.outline_color = Color(0, 0, 0, 0.9)
	lbl.label_settings = s
	_root.add_child(lbl)
	return lbl

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_result(score: int, required: int, impressed: int, hit: int,
		passed: bool, round_num: int) -> void:
	_ready_for_input = false
	visible = true

	var title_base := "Round %d Complete!" if passed else "Round %d Failed"
	_title_label.text     = title_base % round_num
	_score_label.text     = "Score: %d" % score
	_req_label.text       = "Required: %d" % required
	_impressed_label.text = "Customers impressed: %d" % impressed
	_hit_label.text       = "Customers hit by debris: %d" % hit

	_result_label.text = "PASSED!" if passed else "FAILED"
	_result_label.label_settings.font_color = \
		Color(0.30, 1.0, 0.40) if passed else Color(1.0, 0.30, 0.30)

	# Slide the whole layer in from above
	var vp_h: float = get_viewport().get_visible_rect().size.y
	offset = Vector2(0.0, -vp_h)
	var tw := create_tween()
	tw.tween_property(self, "offset", Vector2.ZERO, 0.55) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_callback(func() -> void: _ready_for_input = true)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _ready_for_input:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			offset  = Vector2.ZERO
			visible = false
			continue_pressed.emit()

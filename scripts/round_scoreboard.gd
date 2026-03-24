extends CanvasLayer
class_name RoundScoreboard

## Between-round scoreboard.
## Swings in from above by animating the CanvasLayer's own offset property,
## so the whole panel slides down without touching anchor values.
## All text positions are anchor-based fractions of the viewport.

signal continue_pressed

var _title_label:     Label = null
var _base_label:      Label = null
var _mult_label:      Label = null
var _total_label:     Label = null
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
	UIBuilder.anchor_rect(_root, Color(0.12, 0.10, 0.08, 0.96), 0.12, 0.88, 0.08, 0.93)

	# Gold accent strips (top and bottom of panel)
	UIBuilder.anchor_rect(_root, Color(0.80, 0.70, 0.30, 1.0),  0.12, 0.88, 0.08, 0.095)
	UIBuilder.anchor_rect(_root, Color(0.80, 0.70, 0.30, 1.0),  0.12, 0.88, 0.915, 0.93)

	# Content labels — all horizontally centred inside the panel column
	_title_label     = UIBuilder.anchor_label(_root, GameConstants.ROUND_COMPLETE % 1,
		0.12, 0.88, 0.10, 0.20, 36, Color(1.0, 0.90, 0.30))
	_base_label      = UIBuilder.anchor_label(_root, GameConstants.BASE_LABEL % 0,
		0.12, 0.88, 0.21, 0.29, 24, Color(0.80, 0.80, 0.80))
	_mult_label      = UIBuilder.anchor_label(_root, GameConstants.MULTIPLIER_LABEL % 1,
		0.12, 0.88, 0.29, 0.37, 24, Color(1.0, 0.85, 0.30))
	_total_label     = UIBuilder.anchor_label(_root, GameConstants.TOTAL_LABEL % 0,
		0.12, 0.88, 0.37, 0.46, 30, Color.WHITE)
	_req_label       = UIBuilder.anchor_label(_root, GameConstants.REQUIRED_LABEL % 0,
		0.12, 0.88, 0.47, 0.54, 22, Color(0.85, 0.85, 0.85))
	_impressed_label = UIBuilder.anchor_label(_root, GameConstants.IMPRESSED_LABEL % 0,
		0.12, 0.88, 0.55, 0.62, 22, Color(0.70, 1.0, 0.70))
	_hit_label       = UIBuilder.anchor_label(_root, GameConstants.HIT_LABEL % 0,
		0.12, 0.88, 0.62, 0.69, 22, Color(1.0, 0.70, 0.40))
	_result_label    = UIBuilder.anchor_label(_root, GameConstants.RESULT_PASSED,
		0.12, 0.88, 0.72, 0.84, 42, Color(0.30, 1.0, 0.40))
	UIBuilder.anchor_label(_root, GameConstants.PRESS_SPACE_CONTINUE,
		0.12, 0.88, 0.86, 0.93, 20, Color(0.75, 0.75, 0.75))

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func show_result(score: int, base_score: int, required: int, impressed: int, hit: int,
		multiplier: int, passed: bool, round_num: int) -> void:
	_ready_for_input = false
	visible = true

	var title_fmt := GameConstants.ROUND_COMPLETE if passed else GameConstants.ROUND_FAILED
	_title_label.text     = title_fmt % round_num
	_base_label.text      = GameConstants.BASE_LABEL % base_score
	_mult_label.text      = GameConstants.MULTIPLIER_LABEL % multiplier
	_total_label.text     = GameConstants.TOTAL_LABEL % score
	_req_label.text       = GameConstants.REQUIRED_LABEL % required
	_impressed_label.text = GameConstants.IMPRESSED_LABEL % impressed
	_hit_label.text       = GameConstants.HIT_LABEL % hit

	_result_label.text = GameConstants.RESULT_PASSED if passed else GameConstants.RESULT_FAILED
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

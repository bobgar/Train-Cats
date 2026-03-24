extends CanvasLayer
class_name TitleScreen

## Title / game-over screen.
## All positions expressed as fractions of the viewport so the layout adapts
## to any resolution.  The bouncing letters live inside an anchor-positioned
## container; their per-frame animation uses pixel offsets within that container.

signal continue_pressed

const LETTERS       := ["T","R","A","I","N"," ","C","A","T","S"]
const LETTER_W      := 72.0   # pixels per letter slot
const LETTER_BASE_Y := 10.0   # pixels from letters-container top (before bounce)

var _letter_labels: Array   = []
var _game_over_label: Label = null
var _time:           float  = 0.0
var _ready_for_input: bool  = false
var _root:           Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer   = 20
	visible = false
	_build_ui()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.84)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(bg)

	# "GAME OVER" header — hidden until configure(true)
	_game_over_label = UIBuilder.anchor_label(_root, GameConstants.GAME_OVER,
		0.0, 1.0, 0.04, 0.14, 48, Color(1.0, 0.3, 0.3))
	_game_over_label.visible = false

	# -----------------------------------------------------------------------
	# Bouncing "TRAIN CATS" letters
	# Each letter lives in a sub-container that is centred horizontally and
	# anchored to the upper-third of the screen.
	# -----------------------------------------------------------------------
	var letters_container := Control.new()
	letters_container.anchor_left   = 0.0
	letters_container.anchor_right  = 1.0
	letters_container.anchor_top    = 0.12
	letters_container.anchor_bottom = 0.35
	letters_container.offset_left   = 0
	letters_container.offset_right  = 0
	letters_container.offset_top    = 0
	letters_container.offset_bottom = 0
	_root.add_child(letters_container)

	# A narrow row centred horizontally within the container
	var total_w := float(LETTERS.size()) * LETTER_W
	var row := Control.new()
	row.anchor_left   = 0.5
	row.anchor_right  = 0.5
	row.anchor_top    = 0.0
	row.anchor_bottom = 1.0
	row.offset_left   = -total_w * 0.5
	row.offset_right  =  total_w * 0.5
	row.offset_top    = 0
	row.offset_bottom = 0
	letters_container.add_child(row)

	for i in range(LETTERS.size()):
		var lbl := Label.new()
		lbl.text     = LETTERS[i]
		lbl.position = Vector2(float(i) * LETTER_W, LETTER_BASE_Y)
		lbl.size     = Vector2(LETTER_W, 100)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var s := LabelSettings.new()
		s.font_size     = 80
		s.font_color    = Color.WHITE
		s.outline_size  = 3
		s.outline_color = Color(0, 0, 0, 0.9)
		lbl.label_settings = s
		row.add_child(lbl)
		_letter_labels.append(lbl)

	# -----------------------------------------------------------------------
	# Static text — anchors place each band below the letters
	# -----------------------------------------------------------------------

	# Credits
	UIBuilder.anchor_label(_root, GameConstants.CREDITS_LABEL,
		0.0, 1.0, 0.36, 0.43, 28, Color(0.85, 0.85, 0.85))

	# Controls (auto-wrap, centred)
	var ctrl_lbl := UIBuilder.anchor_label(_root, GameConstants.CONTROLS_LABEL,
		0.10, 0.90, 0.43, 0.78, 22, Color(0.90, 0.90, 0.90))
	ctrl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Press Space — well clear of controls text
	UIBuilder.anchor_label(_root, GameConstants.PRESS_SPACE_PLAY,
		0.0, 1.0, 0.82, 0.91, 28, Color(1.0, 1.0, 0.45))

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func configure(is_game_over: bool) -> void:
	_game_over_label.visible = is_game_over
	_time             = 0.0
	_ready_for_input  = false
	visible           = true
	# Brief delay so a held key doesn't skip past the screen instantly
	get_tree().create_timer(0.4).timeout.connect(
		func() -> void: _ready_for_input = true)

# ---------------------------------------------------------------------------
# Per-frame letter animation
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	for i in range(_letter_labels.size()):
		if LETTERS[i] == " ":
			continue
		var lbl: Label = _letter_labels[i]
		lbl.position.y = LETTER_BASE_Y + sin(_time * 3.0 + float(i) * 0.5) * 18.0
		var hue := fmod(_time * 0.25 + float(i) / float(LETTERS.size()), 1.0)
		lbl.label_settings.font_color = Color.from_hsv(hue, 1.0, 1.0)

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

extends CanvasLayer
class_name TitleScreen

## Title screen shown at game start and after a game-over.
## "TRAIN CATS" bounces in rainbow letters; any key continues.

signal continue_pressed

const LETTERS := ["T","R","A","I","N"," ","C","A","T","S"]

var _letter_labels: Array = []
var _letter_base_y: Array = []
var _game_over_label: Label = null
var _time: float = 0.0
var _ready_for_input: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_ui()

func _build_ui() -> void:
	# Dark semi-transparent background
	var bg := ColorRect.new()
	bg.color          = Color(0.0, 0.0, 0.0, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Game-over header (hidden by default)
	_game_over_label = _make_label("GAME OVER", Vector2(640 - 160, 60), 48, Color(1.0, 0.3, 0.3))
	_game_over_label.visible = false
	add_child(_game_over_label)

	# "TRAIN CATS" — one Label per letter so each can bounce/colour independently
	var letter_w := 72.0
	var total_w  := float(LETTERS.size()) * letter_w
	var start_x  := 640.0 - total_w * 0.5
	var base_y   := 220.0

	for i in range(LETTERS.size()):
		var lbl := _make_label(LETTERS[i], Vector2(start_x + float(i) * letter_w, base_y), 80, Color.WHITE)
		add_child(lbl)
		_letter_labels.append(lbl)
		_letter_base_y.append(base_y)

	# Credits
	_make_label_centered("by Kevin Kohler", 340, 28, Color(0.85, 0.85, 0.85))

	# Controls
	var ctrl_text := (
		"Controls:\n" +
		"  WASD / Arrow keys — Move\n" +
		"  Space — Swipe attack\n" +
		"  Mouse — Look around"
	)
	var ctrl_lbl := Label.new()
	ctrl_lbl.text     = ctrl_text
	ctrl_lbl.position = Vector2(640 - 200, 400)
	var s1 := LabelSettings.new()
	s1.font_size     = 22
	s1.font_color    = Color(0.90, 0.90, 0.90)
	s1.outline_size  = 2
	s1.outline_color = Color(0, 0, 0, 0.8)
	ctrl_lbl.label_settings = s1
	add_child(ctrl_lbl)

	# Press any key prompt
	_make_label_centered("Press any key to play", 580, 26, Color(1.0, 1.0, 0.5))

func _make_label(txt: String, pos: Vector2, fsize: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text     = txt
	lbl.position = pos
	var s := LabelSettings.new()
	s.font_size     = fsize
	s.font_color    = col
	s.outline_size  = 3
	s.outline_color = Color(0, 0, 0, 0.9)
	lbl.label_settings = s
	return lbl

func _make_label_centered(txt: String, y: float, fsize: int, col: Color) -> void:
	var lbl := Label.new()
	lbl.text            = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position        = Vector2(0, y)
	lbl.size            = Vector2(1280, 60)
	var s := LabelSettings.new()
	s.font_size     = fsize
	s.font_color    = col
	s.outline_size  = 2
	s.outline_color = Color(0, 0, 0, 0.9)
	lbl.label_settings = s
	add_child(lbl)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func configure(is_game_over: bool) -> void:
	_game_over_label.visible = is_game_over
	_time            = 0.0
	_ready_for_input = false
	visible          = true
	# Small delay so a held key doesn't instantly dismiss
	var t := get_tree().create_timer(0.4)
	t.timeout.connect(func() -> void: _ready_for_input = true)

# ---------------------------------------------------------------------------
# Per-frame animation
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	for i in range(_letter_labels.size()):
		var lbl: Label = _letter_labels[i]
		# Skip the space character
		if LETTERS[i] == " ":
			continue
		# Bounce
		var bounce := sin(_time * 3.0 + float(i) * 0.5) * 18.0
		lbl.position.y = _letter_base_y[i] + bounce
		# Rainbow colour cycling
		var hue := fmod(_time * 0.25 + float(i) / float(LETTERS.size()), 1.0)
		lbl.label_settings.font_color = Color.from_hsv(hue, 1.0, 1.0)

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not _ready_for_input:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		visible = false
		continue_pressed.emit()
	elif event is InputEventMouseButton and event.pressed:
		visible = false
		continue_pressed.emit()

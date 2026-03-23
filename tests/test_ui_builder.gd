extends Object
## Tests UIBuilder.anchor_label() and UIBuilder.anchor_rect() return correct nodes.

const UIBuilder = preload("res://autoloads/UIBuilder.gd")

func run() -> bool:
	var ok := true

	var parent := Control.new()

	# anchor_label
	var lbl := UIBuilder.anchor_label(parent, "Hello",
		0.1, 0.9, 0.2, 0.8, 24, Color.RED)

	ok = _assert_true("label_not_null", lbl != null) and ok
	if lbl != null:
		ok = _assert_eq_f("anchor_left",   lbl.anchor_left,   0.1) and ok
		ok = _assert_eq_f("anchor_right",  lbl.anchor_right,  0.9) and ok
		ok = _assert_eq_f("anchor_top",    lbl.anchor_top,    0.2) and ok
		ok = _assert_eq_f("anchor_bottom", lbl.anchor_bottom, 0.8) and ok
		ok = _assert_eq_i("font_size", lbl.label_settings.font_size, 24) and ok
		ok = _assert_true("added_to_parent", lbl.get_parent() == parent) and ok

	# anchor_rect
	var rect := UIBuilder.anchor_rect(parent, Color.BLUE, 0.0, 1.0, 0.5, 1.0)

	ok = _assert_true("rect_not_null", rect != null) and ok
	if rect != null:
		ok = _assert_eq_f("rect_anchor_left",   rect.anchor_left,   0.0) and ok
		ok = _assert_eq_f("rect_anchor_right",  rect.anchor_right,  1.0) and ok
		ok = _assert_eq_f("rect_anchor_top",    rect.anchor_top,    0.5) and ok
		ok = _assert_eq_f("rect_anchor_bottom", rect.anchor_bottom, 1.0) and ok

	parent.free()

	if ok:
		print("PASS  test_ui_builder")
	return ok

func _assert_true(label: String, got: bool) -> bool:
	if got:
		return true
	print("FAIL  test_ui_builder %s: expected true" % label)
	return false

func _assert_eq_f(label: String, got: float, expected: float) -> bool:
	if absf(got - expected) < 0.0001:
		return true
	print("FAIL  test_ui_builder %s: expected %.4f, got %.4f" % [label, expected, got])
	return false

func _assert_eq_i(label: String, got: int, expected: int) -> bool:
	if got == expected:
		return true
	print("FAIL  test_ui_builder %s: expected %d, got %d" % [label, expected, got])
	return false

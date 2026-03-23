extends Object
## Tests the view-cone geometry of CafeCustomer.can_see_position().
## Creates minimal stub instances that exercise the pure-geometry path
## (LOS check is skipped when not in a scene tree).

const CafeCustomerScript = preload("res://scripts/cafe_customer.gd")

func run() -> bool:
	var ok := true

	# Build a customer facing -Z (inward from +Z edge).
	# We skip LOS by using positions far from any physics — the can_see_position()
	# call exits early with true when not inside the scene tree.
	var c = CafeCustomerScript.new()
	# Manually set the fields can_see_position() reads without calling setup()
	c._state     = CafeCustomerScript.State.WATCHING
	c._hit       = false
	c._face_dir  = Vector3(0.0, 0.0, -1.0)   # facing -Z
	c.position   = Vector3.ZERO
	# No _player_ref needed — geometry only

	# --- In front, within range ---
	# Target at (0, 0, -5): directly in front, dot = 1.0 > CONE_COS=0.5
	ok = _assert_true("in_front", c.can_see_position(Vector3(0, 0, -5))) and ok

	# --- Behind customer ---
	# Target at (0, 0, +5): behind, dot with face(-Z) = -1.0, not > 0.5
	ok = _assert_false("behind", c.can_see_position(Vector3(0, 0, 5))) and ok

	# --- Beyond VIEW_DISTANCE ---
	ok = _assert_false("too_far", c.can_see_position(Vector3(0, 0, -200))) and ok

	# --- Wrong state (RISING) ---
	c._state = CafeCustomerScript.State.RISING
	ok = _assert_false("rising_state", c.can_see_position(Vector3(0, 0, -5))) and ok

	c.free()

	if ok:
		print("PASS  test_view_cone")
	return ok

func _assert_true(label: String, got: bool) -> bool:
	if got:
		return true
	print("FAIL  test_view_cone %s: expected true, got false" % label)
	return false

func _assert_false(label: String, got: bool) -> bool:
	if not got:
		return true
	print("FAIL  test_view_cone %s: expected false, got true" % label)
	return false

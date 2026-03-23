extends Object
## Tests CustomerManager score accumulation and reset logic.

const CustomerManagerScript = preload("res://scripts/customer_manager.gd")
const GameConstants = preload("res://autoloads/GameConstants.gd")

func run() -> bool:
	var ok := true

	var mgr = CustomerManagerScript.new()
	# Call reset_round() to put it in a clean state
	mgr.reset_round()

	# Manually invoke the private score helper to simulate scoring
	mgr._add_score(GameConstants.PTS_CONE_DERAIL)
	mgr._add_score(GameConstants.PTS_CONE_DERAIL)
	mgr._add_score(GameConstants.PTS_HIT_DEBRIS)

	var expected_score := GameConstants.PTS_CONE_DERAIL * 2 + GameConstants.PTS_HIT_DEBRIS
	var stats: Dictionary = mgr.get_stats()

	ok = _assert_eq("score", stats.get("score", -1), expected_score) and ok

	# Reset clears score
	mgr.reset_round()
	stats = mgr.get_stats()
	ok = _assert_eq("score_after_reset", stats.get("score", -1), 0) and ok

	mgr.free()

	if ok:
		print("PASS  test_score_accumulation")
	return ok

func _assert_eq(label: String, got: int, expected: int) -> bool:
	if got == expected:
		return true
	print("FAIL  test_score_accumulation %s: expected %d, got %d" % [label, expected, got])
	return false

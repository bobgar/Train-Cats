extends Object
## Tests GameConstants.round_requirement() formula correctness and growth properties.

const GameConstants = preload("res://autoloads/GameConstants.gd")

func run() -> bool:
	var ok := true

	# Known anchor values
	ok = _assert_eq("R1=40",    GameConstants.round_requirement(1),  40)   and ok
	ok = _assert_eq("R2=80",    GameConstants.round_requirement(2),  80)   and ok
	ok = _assert_eq("R3=130",   GameConstants.round_requirement(3),  130)  and ok
	ok = _assert_eq("R4=200",   GameConstants.round_requirement(4),  200)  and ok
	ok = _assert_eq("R5=290",   GameConstants.round_requirement(5),  290)  and ok
	ok = _assert_eq("R6=400",   GameConstants.round_requirement(6),  400)  and ok
	ok = _assert_eq("R7=530",   GameConstants.round_requirement(7),  530)  and ok
	ok = _assert_eq("R10=1010", GameConstants.round_requirement(10), 1010) and ok

	# Must be strictly increasing
	var prev := 0
	for n in range(1, 51):
		var req := GameConstants.round_requirement(n)
		if req <= prev:
			print("FAIL round_requirement strictly_increasing at n=%d: %d not > %d" % [n, req, prev])
			ok = false
		prev = req

	if ok:
		print("PASS  test_round_requirements")
	return ok

func _assert_eq(label: String, got: int, expected: int) -> bool:
	if got == expected:
		return true
	print("FAIL  test_round_requirements %s: expected %d, got %d" % [label, expected, got])
	return false

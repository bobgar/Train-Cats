extends SceneTree
## Headless test runner.
## Usage:
##   "C:\tools\Godot_v4.6.1-stable_win64.exe" --path "c:\projects\WillowsGame" \
##     --headless --script res://tests/test_runner.gd
##
## Exits 0 if all tests pass, 1 if any fail.

func _init() -> void:
	var all_pass := true

	var suites: Array = [
		"res://tests/test_round_requirements.gd",
		"res://tests/test_view_cone.gd",
		"res://tests/test_score_accumulation.gd",
		"res://tests/test_ui_builder.gd",
	]

	for path in suites:
		var script = load(path)
		if script == null:
			print("LOAD FAILED: " + path)
			all_pass = false
			continue
		var suite = script.new()
		var passed: bool = suite.run()
		if not passed:
			all_pass = false

	print("")
	if all_pass:
		print("All tests passed.")
		quit(0)
	else:
		print("Some tests FAILED.")
		quit(1)

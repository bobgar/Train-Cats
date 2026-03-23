extends Node
## Central registry for game-wide numeric constants.
## Import or reference these instead of repeating magic numbers in scripts.

# ---------------------------------------------------------------------------
# Table / room geometry
# ---------------------------------------------------------------------------
const TABLE_HW    := 34.0   # table half-width  (X): table spans -34 to +34
const TABLE_HD    := 34.0   # table half-depth  (Z): table spans -34 to +34
const ROOM_FLOOR  := -22.0  # visual cafe floor level (Y)

# ---------------------------------------------------------------------------
# Collision layers
# ---------------------------------------------------------------------------
const LAYER_WORLD  := 1   # floor, walls, table, buildings, player
const LAYER_TRAIN  := 2   # train car sensor Area3D (train-vs-train detection)
const LAYER_TRACK  := 4   # rails and ties (player does not collide; mask=1)
const LAYER_DEBRIS := 8   # flying RigidBody3D car pieces (triggers customer hit_area)

# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------
const PTS_CONE_DERAIL := 10   # awarded per watching customer when cat derails a train
const PTS_HIT_DEBRIS  := 25   # awarded when a customer is hit by flying debris

# ---------------------------------------------------------------------------
# Round progression
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# UI strings — all display text lives here for easy localization later.
# Replace with tr() calls once a proper locale/translation import is set up.
# ---------------------------------------------------------------------------
const SCORE_LABEL         := "Score: %d"
const ROUND_LABEL         := "Round %d"
const NEED_LABEL          := "Need: %d pts"
const ROUND_COMPLETE      := "Round %d Complete!"
const ROUND_FAILED        := "Round %d Failed"
const REQUIRED_LABEL      := "Required: %d"
const IMPRESSED_LABEL     := "Customers impressed: %d"
const HIT_LABEL           := "Customers hit by debris: %d"
const RESULT_PASSED       := "PASSED!"
const RESULT_FAILED       := "FAILED"
const PRESS_SPACE_CONTINUE := "Press Space to continue"
const GAME_OVER           := "GAME OVER"
const CREDITS_LABEL       := "by Kevin Kohler"
const CONTROLS_LABEL      := "Controls:\n  WASD / Arrow keys — Move     Shift — Run\n  Space — Jump     E or Click — Swipe     Mouse — Look around"
const PRESS_SPACE_PLAY    := "Press Space to play"
const PAUSED              := "PAUSED"
const PAUSE_RETURN_TITLE  := "Return to title screen?"
const PAUSE_QUIT          := "Space — Quit to Title"
const PAUSE_RESUME        := "Escape — Resume"

# ---------------------------------------------------------------------------
# Round progression
# ---------------------------------------------------------------------------
## Returns the minimum score required to pass round n (1-indexed).
## Formula: 9n² + 9n + 22, rounded to the nearest 10.
## Sequence: R1=40  R2=76→80  R3=130  R4=202→200  R5=292→290  R6=400  R7=526→530  …
static func round_requirement(n: int) -> int:
	var raw := 9.0 * float(n) * float(n) + 9.0 * float(n) + 22.0
	return int(round(raw / 10.0)) * 10

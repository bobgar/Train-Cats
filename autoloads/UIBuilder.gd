extends Node
## Shared factory methods for anchor-based UI controls.
## Replaces the duplicate _a_lbl / _a_rect / _pause_lbl helpers
## that previously existed in hud.gd, round_scoreboard.gd,
## title_screen.gd, and main.gd.

## Creates a Label anchored to the given viewport-fraction rectangle,
## with the given font size and color, adds it to parent, and returns it.
static func anchor_label(parent: Control, text: String,
		al: float, ar: float, at: float, ab: float,
		font_size: int, color: Color,
		h_align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var lbl := Label.new()
	lbl.text                 = text
	lbl.anchor_left          = al
	lbl.anchor_right         = ar
	lbl.anchor_top           = at
	lbl.anchor_bottom        = ab
	lbl.offset_left          = 0;  lbl.offset_right  = 0
	lbl.offset_top           = 0;  lbl.offset_bottom = 0
	lbl.horizontal_alignment = h_align
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	var s := LabelSettings.new()
	s.font_size     = font_size
	s.font_color    = color
	s.outline_size  = 2
	s.outline_color = Color(0, 0, 0, 0.9)
	lbl.label_settings = s
	parent.add_child(lbl)
	return lbl

## Creates a ColorRect anchored to the given viewport-fraction rectangle,
## adds it to parent, and returns it.
static func anchor_rect(parent: Control, color: Color,
		al: float, ar: float, at: float, ab: float) -> ColorRect:
	var r := ColorRect.new()
	r.color         = color
	r.anchor_left   = al;  r.anchor_right  = ar
	r.anchor_top    = at;  r.anchor_bottom = ab
	r.offset_left   = 0;   r.offset_right  = 0
	r.offset_top    = 0;   r.offset_bottom = 0
	parent.add_child(r)
	return r

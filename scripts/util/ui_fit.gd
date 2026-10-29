# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name UiFit
## Fitting the UI into the 1280x720 screen it's laid out for.


## A tab bar's tabs at a smaller text size with slimmer sides, so a row of
## them (the Ships and Shop tabs) fits across the screen.
static func compact_tabs(tabs: Control, font_size: int, pad := 8) -> void:
	tabs.add_theme_font_size_override(&"font_size", font_size)
	for state: StringName in [&"tab_selected", &"tab_unselected", &"tab_hovered", &"tab_disabled"]:
		var box := tabs.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			var slim: StyleBoxFlat = box.duplicate()
			slim.content_margin_left = pad
			slim.content_margin_right = pad
			tabs.add_theme_stylebox_override(state, slim)


## Short money for a table: $11.5T, $2.3B, $860M, $45k.
static func big_money(n: float) -> String:
	var sign := "-" if n < 0.0 else ""
	var a := absf(n)
	if a >= 1e12:
		return "%s$%sT" % [sign, Fmt.decimal(a / 1e12, 1)]
	if a >= 1e9:
		return "%s$%sB" % [sign, Fmt.decimal(a / 1e9, 2 if a < 1e10 else 1)]
	return sign + "$" + Fmt.short(a)

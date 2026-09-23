class_name AlertDot
extends Control
## A small red dot pinned to the top-right corner of its parent, e.g. a nav
## button, to say something there needs the player.

const THEME_TYPE := &"AlertDot"
const RADIUS := 7.0
const INSET := 10.0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -INSET - RADIUS * 2.0
	offset_right = -INSET
	offset_top = INSET - RADIUS
	offset_bottom = INSET + RADIUS


func _draw() -> void:
	var color := get_theme_color(&"color", THEME_TYPE) if has_theme_color(&"color", THEME_TYPE) else Color(0.9, 0.2, 0.2)
	draw_circle(size / 2.0, RADIUS, color, true, -1.0, true)

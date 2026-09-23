class_name AlertDot
extends Control
## A small red dot pinned to the top-right corner of its parent, e.g. a nav
## button, to say something there needs the player.

const THEME_TYPE := &"AlertDot"

var radius := 7.0
## Distance from the parent's right (x) and top (y) edges to the dot's center.
var inset := Vector2(17, 10)


func _init(dot_radius := 7.0, corner_inset := Vector2(17, 10)) -> void:
	radius = dot_radius
	inset = corner_inset


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	offset_left = -inset.x - radius
	offset_right = -inset.x + radius
	offset_top = inset.y - radius
	offset_bottom = inset.y + radius


func _draw() -> void:
	var color := get_theme_color(&"color", THEME_TYPE) if has_theme_color(&"color", THEME_TYPE) else Color(0.9, 0.2, 0.2)
	draw_circle(size / 2.0, radius, color, true, -1.0, true)

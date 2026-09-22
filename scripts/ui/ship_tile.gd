class_name ShipTile
extends Button
## One tile on the Ships screen: status dot and ship name.

const THEME_TYPE := &"StatusDot"
const DOT_RADIUS := 8.0

var ship: Ship

var _dot := Control.new()


func _init(for_ship: Ship) -> void:
	ship = for_ship
	custom_minimum_size = Vector2(0, 72)
	size_flags_horizontal = SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, 16)
	row.add_theme_constant_override(&"separation", 12)
	add_child(row)

	_dot.custom_minimum_size = Vector2.ONE * DOT_RADIUS * 2.0
	_dot.size_flags_vertical = SIZE_SHRINK_CENTER
	_dot.mouse_filter = MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	row.add_child(_dot)

	var label := Label.new()
	label.text = ship.name
	label.size_flags_vertical = SIZE_SHRINK_CENTER
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)


func _ready() -> void:
	GameState.ship_changed.connect(_on_ship_changed)


func _on_ship_changed(changed: Ship) -> void:
	if changed == ship:
		_dot.queue_redraw()


func _draw_dot() -> void:
	var color_name := &"running" if ship.is_running() else &"stopped"
	var color := Color.GREEN if ship.is_running() else Color.RED
	if has_theme_color(color_name, THEME_TYPE):
		color = get_theme_color(color_name, THEME_TYPE)
	_dot.draw_circle(_dot.size / 2.0, DOT_RADIUS, color, true, -1.0, true)

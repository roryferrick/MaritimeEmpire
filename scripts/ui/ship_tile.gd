class_name ShipTile
extends Button
## One tile on the Ships screen: status dot, ship name, and mini maintenance,
## fuel and cargo bars.

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

	var column := VBoxContainer.new()
	column.mouse_filter = MOUSE_FILTER_IGNORE
	column.size_flags_vertical = SIZE_SHRINK_CENTER
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 6)
	row.add_child(column)

	var label := Label.new()
	label.text = ship.name
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(label)
	column.add_child(ShipBars.new(ship, true))


func _ready() -> void:
	GameState.ship_changed.connect(_on_ship_changed)


func _on_ship_changed(changed: Ship) -> void:
	if changed == ship:
		_dot.queue_redraw()


func _draw_dot() -> void:
	var running := ship.is_running() and not ship.is_held()  # Held ships show red.
	var color_name := &"running" if running else &"stopped"
	var color := Color.GREEN if running else Color.RED
	if has_theme_color(color_name, THEME_TYPE):
		color = get_theme_color(color_name, THEME_TYPE)
	_dot.draw_circle(_dot.size / 2.0, DOT_RADIUS, color, true, -1.0, true)

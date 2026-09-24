class_name ShipTile
extends Button
## One compact tile on the Ships screen: status dot, ship name, what it's
## carrying and its level (highlighted while it has skill points to spend), and
## mini maintenance, fuel and cargo bars. Hovering shows the full name.

const THEME_TYPE := &"StatusDot"
const DOT_RADIUS := 5.0
const NAME_FONT_SIZE := 13
const INFO_FONT_SIZE := 11
const PADDING := 5

var ship: Ship

var _dot := Control.new()
var _info := Label.new()
var _name := Label.new()


func _init(for_ship: Ship) -> void:
	ship = for_ship

	size_flags_horizontal = SIZE_EXPAND_FILL
	tooltip_text = ship.name

	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, PADDING)
	row.add_theme_constant_override(&"separation", 5)
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
	column.add_theme_constant_override(&"separation", 1)
	row.add_child(column)

	_name.text = ship.name
	_name.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.custom_minimum_size.x = 1  # Lets the name shrink (with an ellipsis) to fit the tile.
	column.add_child(_name)
	_info.add_theme_font_size_override(&"font_size", INFO_FONT_SIZE)
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info.custom_minimum_size.x = 1
	column.add_child(_info)
	var bars := ShipBars.new(ship, true)
	column.add_child(bars)
	_update_info()


func _ready() -> void:
	GameState.ship_changed.connect(_on_ship_changed)
	# A Button doesn't size itself to its children: fit the tile to its content.
	var row: Control = get_child(0)
	custom_minimum_size.y = row.get_combined_minimum_size().y + 2.0 * PADDING


func _on_ship_changed(changed: Ship) -> void:
	if changed == ship:
		_dot.queue_redraw()
		_name.text = ship.name
		tooltip_text = ship.name
		_update_info()


## "Coffee · Lv 3" (green, with "+2", while it has skill points to spend);
## recovery boats just say what they are.
func _update_info() -> void:
	if ship.is_recovery():
		_info.text = "Recovery"
		_info.theme_type_variation = &"DimLabel"
		return
	var cargo: String = GameData.commodity(ship.cargo_id).get("name", "") if not ship.cargo_id.is_empty() else "empty"
	var points := ship.skill_points()
	_info.text = "%s · Lv %d%s" % [cargo, ship.level(), " +%d" % points if points > 0 else ""]
	_info.theme_type_variation = &"GainLabel" if points > 0 else &"DimLabel"


## Green while running, amber while waiting in port for a full load, red when
## stopped.
func _draw_dot() -> void:
	var running := ship.is_active()
	var color_name := &"running" if running else &"stopped"
	var color := Color.GREEN if running else Color.RED
	if ship.is_docked() and not ship.load_wait.is_empty():
		color_name = &"waiting"
		color = Color(0.95, 0.7, 0.2)
	if has_theme_color(color_name, THEME_TYPE):
		color = get_theme_color(color_name, THEME_TYPE)
	_dot.draw_circle(_dot.size / 2.0, DOT_RADIUS, color, true, -1.0, true)

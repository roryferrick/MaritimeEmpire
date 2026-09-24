class_name ShipBars
extends Control
## Live maintenance, fuel and cargo bars for one ship, top to bottom. Cargo is
## full at sea, empties while unloading and fills again while loading.
## Compact bars are thin unlabeled strips, for tiles and lists.

const THEME_TYPE := &"ShipBars"
const BAR_HEIGHT := 10.0
const COMPACT_BAR_HEIGHT := 4.0
const COMPACT_GAP := 3.0
const LABEL_GAP := 2.0
const ROW_GAP := 8.0

var ship: Ship
var compact := false


func _init(for_ship: Ship, is_compact := false) -> void:
	ship = for_ship
	compact = is_compact
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	custom_minimum_size.y = 3.0 * _row_height() - _gap()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()


func _draw() -> void:
	var cargo_text: String = GameData.commodity(ship.cargo_id).get("name", "Loaded") if not ship.cargo_id.is_empty() else "Empty"
	if ship.is_docking():
		cargo_text = "Unloading" if ship.dock_time < ship.dock_seconds() / 2.0 else "Loading"
	var load_bar := ["Cargo", ship.cargo_level(), &"cargo", cargo_text]
	if ship.is_recovery():  # A Mammoth's load is the ship it's carrying.
		var carrying := ship.is_carrying()
		load_bar = ["Tow", 1.0 if carrying else 0.0, &"cargo", ship.rescuing.name if carrying else "Empty"]
	var bars := [
		["Maintenance", ship.maintenance, &"maintenance", "%d%%" % floori(ship.maintenance * 100.0)],
		["Fuel", ship.fuel_level(), &"fuel", "%d%%" % floori(ship.fuel_level() * 100.0)],
		load_bar,
	]
	var y := 0.0
	for bar: Array in bars:
		if not compact:
			_draw_labels(y, bar[0], bar[3])
			y += _font_height() + LABEL_GAP
		var height := COMPACT_BAR_HEIGHT if compact else BAR_HEIGHT
		var track := Rect2(0.0, y, size.x, height)
		draw_rect(track, _color(&"track", Color(1, 1, 1, 0.15)))
		draw_rect(Rect2(track.position, Vector2(size.x * clampf(bar[1], 0.0, 1.0), height)),
			_color(bar[2], Color.WHITE))
		y += height + _gap()


func _draw_labels(y: float, title: String, value: String) -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var baseline := y + font.get_ascent(font_size)
	var color := _color(&"label", Color(1, 1, 1, 0.65))
	draw_string(font, Vector2(0.0, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	draw_string(font, Vector2(0.0, baseline), value, HORIZONTAL_ALIGNMENT_RIGHT, size.x, font_size, color)


func _row_height() -> float:
	if compact:
		return COMPACT_BAR_HEIGHT + COMPACT_GAP
	return _font_height() + LABEL_GAP + BAR_HEIGHT + ROW_GAP


func _gap() -> float:
	return COMPACT_GAP if compact else ROW_GAP


func _font_height() -> float:
	return get_theme_default_font().get_height(get_theme_default_font_size())


func _color(color_name: StringName, fallback: Color) -> Color:
	return get_theme_color(color_name, THEME_TYPE) if has_theme_color(color_name, THEME_TYPE) else fallback

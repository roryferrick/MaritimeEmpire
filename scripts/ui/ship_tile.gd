# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ShipTile
extends Button
## One compact tile on the Ships screen: status dot, ship name, what it's
## carrying and its level (highlighted while it has skill points to spend), and
## mini maintenance, fuel and cargo bars, with its captain's picture and name,
## and what it earned in the last 10 minutes under its name.
## Hovering shows the full name.

const THEME_TYPE := &"StatusDot"
const DOT_RADIUS := 5.0
const NAME_FONT_SIZE := 13
const INFO_FONT_SIZE := 11
const PADDING := 5
const CAPTAIN_SIZE := 30.0

var ship: Ship

var _dot := Control.new()
var _info := Label.new()
var _name := Label.new()
var _captain := Label.new()
## What it has earned in the last 10 minutes (see show_earnings()).
var _earned := Label.new()


func _init(for_ship: Ship) -> void:
	ship = for_ship

	size_flags_horizontal = SIZE_EXPAND_FILL
	tooltip_text = ship.name

	# The dot, the captain and the column beside them in a row; under the row,
	# the whole tile wide, what it's earned.
	var box := VBoxContainer.new()
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, PADDING)
	box.add_theme_constant_override(&"separation", 2)
	add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_theme_constant_override(&"separation", 5)
	box.add_child(row)

	_dot.custom_minimum_size = Vector2.ONE * DOT_RADIUS * 2.0
	_dot.size_flags_vertical = SIZE_SHRINK_CENTER
	_dot.mouse_filter = MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	row.add_child(_dot)

	var face := Portrait.new(ship.captain(), true)
	face.custom_minimum_size = Vector2.ONE * CAPTAIN_SIZE
	face.size_flags_vertical = SIZE_SHRINK_CENTER
	face.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(face)

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
	_captain.text = "Capt. %s" % ship.captain().get("name", "")
	_captain.theme_type_variation = &"DimLabel"
	_captain.add_theme_font_size_override(&"font_size", INFO_FONT_SIZE)
	_captain.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_captain.custom_minimum_size.x = 1
	column.add_child(_captain)
	var bars := ShipBars.new(ship, true)
	column.add_child(bars)
	# What it's earned lately and over how long of game time, under it all, the tile's width.
	_earned.add_theme_font_size_override(&"font_size", INFO_FONT_SIZE)
	_earned.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_earned.custom_minimum_size.x = 1
	_earned.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_earned.visible = false
	box.add_child(_earned)
	_update_info()


func _ready() -> void:
	# A Button doesn't size itself to its children: fit the tile to its content.
	var row: Control = get_child(0)
	custom_minimum_size.y = row.get_combined_minimum_size().y + 2.0 * PADDING


## Brings the tile up to date with its ship (the Ships screen calls this when
## the ship changes).
func refresh() -> void:
	_dot.queue_redraw()
	_name.text = ship.name
	tooltip_text = ship.name
	_update_info()


## Hovering shows the full name and what the ship is doing (why it's held...).
func _get_tooltip(_at_position: Vector2) -> String:
	return "%s\n%s" % [ship.name, ship.status_text()]


## What needs the player (in red: "Held in port"), or else "Coffee · Lv 3"
## (green, with "+2", while it has skill points to spend); recovery boats say
## "Recovery" in place of the cargo.
func _update_info() -> void:
	var reason := ship.attention_reason()
	if not reason.is_empty() and reason != Ship.UPGRADES_REASON:
		_info.text = reason[0].to_upper() + reason.substr(1)
		_info.theme_type_variation = &"ErrorLabel"
		return
	var cargo: String = GameData.commodity(ship.cargo_id).get("name", "") if not ship.cargo_id.is_empty() else "empty"
	if ship.is_recovery():
		cargo = "Recovery"
	elif ship.is_icebreaker():
		cargo = "Icebreaker"
	elif ship.is_tug():
		cargo = "Tug at %s" % GameData.port_name(ship.base_port)
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


## Shows what the ship has earned (profit) in the last 10 minutes under its
## name, green or red; nothing for a ship that hasn't earned or spent.
func show_earnings(amount: float) -> void:
	_earned.visible = absf(amount) >= 1.0
	_earned.text = "%s%s in %s" % ["+" if amount > 0.0 else "", Fmt.money_short(roundi(amount)), GameState.recent_window_short()]
	_earned.theme_type_variation = &"GainLabel" if amount > 0.0 else &"ErrorLabel"
	_earned.tooltip_text = "Earned over the last %s of game time (10 minutes of play)" % GameState.recent_window_text()

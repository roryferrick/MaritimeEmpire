# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name DrydockPopup
extends PanelContainer
## Orders a drydock for a ship (ShipParts, GameState.order_drydock()): the yard
## (a shipyard port or the company's hub with the Drydock facility, nearest
## first, with the days out of service), the upgrades to fit, and the cost.

const WIDTH := 520.0

var ship: Ship
var _yards: Array = []
var _yard := OptionButton.new()
var _ticks := {}  # part id -> CheckBox
var _cost := Label.new()
var _order := Button.new()


func _init(for_ship: Ship) -> void:
	ship = for_ship
	theme_type_variation = &"PopupPanel"


func _ready() -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = WIDTH
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Drydock %s" % ship.name
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	var major := ShipParts.major_deficit(ship)
	box.add_child(_dim("Major parts (engine, propeller, shaft, plating) are only put right in drydock; the ship is out of service for the days and comes back as new, with any upgrades fitted. Its major parts are %d%% worn now.%s" % [roundi(major * 100.0), " It must be empty and in port to go." if not ship.cargo_id.is_empty() else ""]))
	_yards = ShipParts.yards_for(ship)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.add_child(_text("Yard"))
	for yard: Dictionary in _yards:
		_yard.add_item("%s%s · %s · %d days" % [GameData.port_name(str(yard.port)), " (your drydock)" if bool(yard.own) else "", "here" if float(yard.nm) <= 0.0 else "%s nm" % Fmt.thousands(roundi(float(yard.nm))), roundi(float(yard.days))])
	_yard.item_selected.connect(func(_i: int) -> void: _update())
	row.add_child(_yard)
	box.add_child(row)
	if _yards.is_empty():
		box.add_child(_dim("No shipyard this ship can reach from here."))
	var open := ShipParts.upgrades_open(ship)
	if not open.is_empty():
		box.add_child(_text("Upgrades to fit"))
		for part_id: String in open:
			var info := ShipParts.part(part_id)
			var upgrade: Dictionary = info.upgrade
			var tick := CheckBox.new()
			tick.text = "%s on the %s — %s (%s)" % [str(upgrade.name), str(info.name).to_lower(), _effects_text(upgrade.get("effects", {})), Fmt.money(ShipParts.upgrade_cost(ship, part_id))]
			tick.add_theme_font_size_override(&"font_size", 14)
			tick.toggled.connect(func(_on: bool) -> void: _update())
			_ticks[part_id] = tick
			box.add_child(tick)
	_cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_cost)
	_order.text = "Order the drydock"
	_order.pressed.connect(_confirm)
	box.add_child(_order)
	_update()


func _chosen() -> Array:
	var out := []
	for part_id: String in _ticks:
		if (_ticks[part_id] as CheckBox).button_pressed:
			out.append(part_id)
	return out


func _update() -> void:
	if _yards.is_empty() or _yard.selected < 0:
		_cost.text = ""
		_order.disabled = true
		return
	var yard: Dictionary = _yards[_yard.selected]
	var cost := ShipParts.drydock_cost(ship, str(yard.port), _chosen())
	var error := GameState.drydock_error(ship, str(yard.port), _chosen())
	_cost.text = "%s: repairs%s%s, %d days in the yard%s. %s" % [Fmt.money(cost), "" if bool(yard.own) else " and the yard's fee", "" if _chosen().is_empty() else " and %d upgrade%s" % [_chosen().size(), "" if _chosen().size() == 1 else "s"], roundi(float(yard.days)),
		"" if float(yard.nm) <= 0.0 else " after sailing %s nm there" % Fmt.thousands(roundi(float(yard.nm))), error if not error.is_empty() else "Paid when the work starts; its route resumes after."]
	_order.disabled = not error.is_empty()


func _confirm() -> void:
	if _yards.is_empty() or _yard.selected < 0:
		return
	GameState.order_drydock(ship, str(_yards[_yard.selected].port), _chosen())
	queue_free()


static func _effects_text(effects: Dictionary) -> String:
	var words := {fuel = "fuel", speed = "speed", breakdowns = "breakdowns", dock = "port time"}
	var parts := PackedStringArray()
	for key: String in effects:
		var value := float(effects[key])
		parts.append("%s%d%% %s" % ["+" if value > 1.0 else "-", roundi(absf(value - 1.0) * 100.0), words.get(key, key)])
	return ", ".join(parts)


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	return label

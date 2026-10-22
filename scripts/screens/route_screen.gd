# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## Full-screen gray map for building a looping route by clicking ports in order.
## Ports the ship can't reach from the current stop, or that are too small for
## it, are grayed out; boxes over the others say what a load of each of its
## cargoes would make sailed there from the current stop (see MapView.price_line).

## Emitted when the player accepts or cancels.
signal finished

var _ship: Ship
var _waypoints: Array[String] = []
var _message := ""  # Feedback about the last click; cleared on the next change.

@onready var _map: MapView = %MapView


func _ready() -> void:
	_map.port_clicked.connect(_add_waypoint)
	%UndoButton.pressed.connect(_undo)
	%CancelButton.pressed.connect(finished.emit)
	%AcceptButton.pressed.connect(_accept)


func open(ship: Ship) -> void:
	_ship = ship
	_waypoints.clear()
	_message = ""
	%TitleLabel.text = "Route for %s" % ship.name
	var current := "Current route: %s" % GameData.route_text(ship.route) if ship.has_route() else "No current route."
	var needs := str(ship.model().get("min_port", ""))
	var docks := " Docks only at %s ports or bigger, or at an HQ or hub." % needs.capitalize() if not needs.is_empty() else ""
	%CurrentLabel.text = "%s\nRange: %s nm on a tank; ports farther off are reached by way of refuel stops, shown on the map and below.%s Starting from %s." % [
		current, Fmt.thousands(roundi(ship.range_nm())), docks, GameData.port_name(ship.reference_port())]
	_refresh()
	# Refit once the top and bottom bars have gone and the map has its full size.
	await get_tree().process_frame
	_map.reset_view(ship.reference_port())


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		finished.emit()


## The port the next waypoint is sailed from.
func _from_port() -> String:
	return _waypoints[-1] if not _waypoints.is_empty() else _ship.reference_port()


func _add_waypoint(port_id: String) -> void:
	var from := _from_port()
	if not _waypoints.is_empty() and port_id == from:
		_message = "Already stopping at %s. Pick a different port." % GameData.port_name(port_id)
	elif not _ship.fits_port(port_id):
		_message = GameState.port_size_error(_ship.model(), port_id)
	elif port_id != from and not GameState.can_get_to(_ship, from, port_id):
		_message = GameState._reach_error(_ship, from, port_id)
	else:
		_waypoints.append(port_id)
		var stops := GameState.refuel_stops(_ship, from, port_id)
		_message = "" if stops.is_empty() else "Beyond one tank from %s: it %s on the way." % [GameData.port_name(from), GameState.refuel_text(stops)]
	_refresh()


## The X beside a stop: takes it out of the route (and, if that leaves the same
## port twice in a row, one of them too).
func _remove_waypoint(index: int) -> void:
	if index < 0 or index >= _waypoints.size():
		return
	_waypoints.remove_at(index)
	var i := 1
	while i < _waypoints.size():
		if _waypoints[i] == _waypoints[i - 1]:
			_waypoints.remove_at(i)
		else:
			i += 1
	_message = ""
	_refresh()


func _undo() -> void:
	if not _waypoints.is_empty():
		_waypoints.pop_back()
	_message = ""
	_refresh()


func _accept() -> void:
	if not GameState.route_error(_waypoints, _ship).is_empty():
		return
	GameState.assign_route(_ship, _waypoints)
	ActivityLog.add("%s: new route %s" % [_ship.name, GameData.route_text(_waypoints)], ActivityLog.Kind.INFO,
		ActivityLog.ship_color(_ship))
	finished.emit()


func _refresh() -> void:
	_map.route = _waypoints.duplicate()
	var from := _from_port()
	# Over each port in reach, what a load of each of the ship's cargoes would make sailed there from the last stop.
	_map.price_ship = _ship
	_map.price_line = str(_ship.model().get("category", ""))
	_map.price_origin = from
	var dimmed := {}
	for port: Dictionary in GameData.ports:
		if port.id != from and not GameState.can_get_to(_ship, from, port.id):
			dimmed[port.id] = true
	_map.dimmed_ports = dimmed
	# Legs beyond one tank go by way of their refuel stops, marked on the map.
	var hops := {}
	for i in (_waypoints.size() if _waypoints.size() >= 2 else 0):
		var stops := GameState.refuel_stops(_ship, _waypoints[i], _waypoints[(i + 1) % _waypoints.size()])
		if not stops.is_empty():
			hops[i] = stops
	_map.route_hops = hops
	_rebuild_list()

	var error := GameState.route_error(_waypoints, _ship)
	%AcceptButton.disabled = not error.is_empty()
	%UndoButton.disabled = _waypoints.is_empty()
	if not _message.is_empty():
		%ErrorLabel.text = _message
	elif _waypoints.size() >= 2:
		%ErrorLabel.text = error
	else:
		%ErrorLabel.text = ""


func _rebuild_list() -> void:
	for child in %WaypointList.get_children():
		%WaypointList.remove_child(child)
		child.queue_free()

	var n := _waypoints.size()
	var total_nm := 0.0
	var total_lock_s := 0.0
	var total_sailing_s := 0.0
	var total_refuels := 0
	# Getting to the first stop from where the ship is now, if that needs refuel stops.
	var start := _ship.reference_port()
	if n > 0 and not _waypoints.has(start):
		var first_stops := GameState.refuel_stops(_ship, start, _waypoints[0])
		if not first_stops.is_empty():
			var getting := _refuel_label(first_stops)
			getting.text = "      Getting to %s from %s first: it %s." % [GameData.port_name(_waypoints[0]), GameData.port_name(start), GameState.refuel_text(first_stops)]
			%WaypointList.add_child(getting)
	for i in n:
		var stop_row := HBoxContainer.new()
		var stop := Label.new()
		stop.text = "%d. %s (%s)" % [i + 1, GameData.port_name(_waypoints[i]), GameState.port_size_text(_waypoints[i])]
		stop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stop_row.add_child(stop)
		var cut := Button.new()  # Takes this stop out of the route.
		cut.text = "X"
		cut.flat = true
		cut.focus_mode = Control.FOCUS_NONE
		cut.tooltip_text = "Take %s out of the route" % GameData.port_name(_waypoints[i])
		cut.pressed.connect(_remove_waypoint.bind(i))
		stop_row.add_child(cut)
		%WaypointList.add_child(stop_row)
		if n < 2:
			continue
		var next := _waypoints[(i + 1) % n]
		if next == _waypoints[i]:
			continue
		# Beyond one tank: by way of its refuel stops, each a stop in port (its time counted).
		var stops := GameState.refuel_stops(_ship, _waypoints[i], next)
		var distance := 0.0
		var lock_s := 0.0
		var sailing_s := 0.0
		var at := _waypoints[i]
		for port: String in stops + [next]:
			distance += GameData.distance_nm(at, port)
			lock_s += GameData.canal_lock_seconds(at, port)
			sailing_s += _sailing_seconds(at, port)
			if port != next:
				lock_s += _ship.dock_seconds()
			at = port
		total_refuels += stops.size()
		total_sailing_s += sailing_s
		total_nm += distance
		total_lock_s += lock_s
		var leg := Label.new()
		leg.theme_type_variation = &"DimLabel" if GameState.can_get_to(_ship, _waypoints[i], next) else &"ErrorLabel"
		leg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var prefix := "back to" if i == n - 1 else "to"
		leg.text = "      %s %s · %s%s" % [prefix, GameData.port_name(next), _leg_text(distance, sailing_s, lock_s), _canal_text(_waypoints[i], next)]
		%WaypointList.add_child(leg)
		if not stops.is_empty():
			%WaypointList.add_child(_refuel_label(stops))
		var trade := Label.new()
		var sails_empty: bool = GameState.market.best_cargo(_ship.model(), _waypoints[i], next)[0] == ""
		trade.theme_type_variation = &"ErrorLabel" if sails_empty else &"GainLabel"
		trade.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		trade.text = "      %s" % _trade_text(_waypoints[i], next)
		%WaypointList.add_child(trade)

	if n == 0:
		%TotalLabel.text = "Click ports on the map in the order the ship should visit them."
	elif n == 1:
		%TotalLabel.text = "Add at least one more port."
	else:
		%TotalLabel.text = "Full loop: %s" % _leg_text(total_nm, total_sailing_s, total_lock_s)
		if total_refuels > 0:
			%TotalLabel.text += "\nIncludes %d refuel stop%s (no trading there), marked on the map." % [total_refuels, "" if total_refuels == 1 else "s"]


## Distance and time: sailing at top speed (slower in convoy canals), plus
## extra_s in locks (not counting any wait for a free chamber or a convoy), in
## play time and, in brackets, calendar time.
func _leg_text(distance_nm: float, sailing_s: float, extra_s := 0.0) -> String:
	if sailing_s == INF:
		return "%s nm · ?" % Fmt.thousands(roundi(distance_nm))
	var seconds := sailing_s + extra_s
	return "%s nm · %s (about %s)" % [Fmt.thousands(roundi(distance_nm)), Fmt.duration(seconds),
		Fmt.calendar_duration(seconds * GameState.calendar_seconds_per_second())]


## Seconds to sail a leg at top speed, through its zones (convoy canals slow
## ships, and they ease in and out of port).
func _sailing_seconds(from_port: String, to_port: String) -> float:
	var speed := _ship.top_speed()
	if speed <= 0.0:
		return INF
	var seconds := 0.0
	var mile := 0.0
	for zone: Array in _ship.leg_zones(from_port, to_port):
		seconds += (float(zone[0]) - mile) / (speed * float(zone[1]))
		mile = zone[0]
	return seconds


## About what a leg's fuel and wear cost to put back, at top speed through its
## zones (rough seas wear faster), at the arrival port's prices (where it
## refuels and repairs), less any hub discount there; INF if it can't sail.
func _running_cost(from_port: String, to_port: String) -> float:
	var speed := _ship.top_speed()
	if speed <= 0.0:
		return INF
	var seconds := 0.0
	var wear := 0.0
	var mile := 0.0
	for zone: Array in _ship.leg_zones(from_port, to_port):
		var t := (float(zone[0]) - mile) / (speed * float(zone[1]))
		seconds += t
		wear += _ship.wear_per_s() * float(zone[2]) * t
		mile = zone[0]
	var fuel_cost := _ship.fuel_per_s() * seconds * GameState.market.fuel_price(to_port)
	var repair_cost := minf(wear, 1.0) * _ship.full_repair_cost() * GameState.port_sizes.cost_factor(to_port)
	return fuel_cost + repair_cost


## Each canal on a leg, e.g. " · Panama Canal: toll 20% of cargo value, +50%
## profit", plus the longest convoy wait and any cargo unloaded to pass, any
## seasonal closure it's subject to, and rough seas; "" for none.
func _canal_text(from_port: String, to_port: String) -> String:
	var text := ""
	for crossing: Dictionary in GameData.canal_crossings(from_port, to_port):
		var canal: Dictionary = crossing.canal
		var parts := PackedStringArray()
		var share := float(canal.get("toll_share", 0.0))
		if share > 0.0:
			parts.append("toll %d%% of cargo value" % roundi(share * 100.0))
		if float(canal.get("profit_bonus", 0.0)) > 0.0:
			parts.append("+%d%% profit" % roundi(float(canal.profit_bonus) * 100.0))
		if canal.get("type", "") == "convoy":
			parts.append("up to %s waiting for a convoy" % Fmt.duration(float(canal.get("convoy_interval_s", 90))))
		var lighten := float(canal.get("lighten", {}).get(_ship.model_id, 0.0))
		if lighten > 0.0:
			parts.append("unloads %d%% of its cargo to pass" % roundi(lighten * 100.0))
		text += " · %s: %s" % [canal.name, ", ".join(parts)] if not parts.is_empty() else " · %s" % canal.name
	if GameState.seasons:
		for closure: Dictionary in GameState.seasonal.leg_closures(from_port, to_port):
			text += " · %s closed %s to %s (%s)" % [closure.name, Seasons.date_text(closure.from), Seasons.date_text(closure.to), closure.why]
	if GameData.is_rough_port(from_port) or GameData.is_rough_port(to_port):
		text += " · rough seas: +%d%% trade profit, 2x wear" % roundi(float(GameData.config.get("rough_seas", {}).get("pay_bonus", 0.0)) * 100.0)
	return text


## What the ship would load for a leg and about how much it would make, at
## today's prices: "loads Toys: about +$2,300", or that it would sail empty and
## what that costs.
func _trade_text(from_port: String, to_port: String) -> String:
	var model := _ship.model()
	var best := GameState.market.best_cargo(model, from_port, to_port)
	if best[0] == "":
		var cost := _running_cost(from_port, to_port)
		if cost == INF:
			return "nothing to trade: sails empty"
		return "nothing to trade: sails empty, about -%s in fuel and repairs" % Fmt.money(roundi(cost))
	var quantity := floori(_ship.capacity() * (1.0 - GameData.leg_lightening(from_port, to_port, model)))
	var margin: float = (GameState.company_sell_price(to_port, best[0], GameState.owner_of(_ship)) - GameState.company_buy_price(from_port, best[0], GameState.owner_of(_ship))) * quantity
	var fee := GameState.port_fee(to_port, margin)
	return "loads %s: about +%s%s" % [GameData.commodity(best[0]).get("name", best[0]), Fmt.money(roundi(best[1] * quantity - fee)),
		" after a %s port fee" % Fmt.money(fee) if fee > 0 else ""]


## Refuel stops' colour in the list (as on the map: MapView.REFUEL_COLOR).
func _refuel_label(stops: Array[String]) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override(&"font_color", MapView.REFUEL_COLOR)
	label.text = "      Beyond one tank: %s on the way (no trading there)" % GameState.refuel_text(stops)
	return label

extends Control
## Full-screen gray map for building a looping route by clicking ports in order.
## Ports the ship can't reach from the current stop are grayed out.

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
	%CurrentLabel.text = "%s\nRange: %s nm per leg. Starting from %s." % [
		current, Fmt.thousands(roundi(ship.range_nm())), GameData.port_name(ship.reference_port())]
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
	elif port_id != from and not _ship.can_sail(from, port_id):
		_message = "%s is out of range: %s nm from %s, and this ship's range is %s nm." % [
			GameData.port_name(port_id), Fmt.thousands(roundi(GameData.distance_nm(from, port_id))),
			GameData.port_name(from), Fmt.thousands(roundi(_ship.range_nm()))]
	else:
		_waypoints.append(port_id)
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
	var dimmed := {}
	for port: Dictionary in GameData.ports:
		if port.id != from and not _ship.can_sail(from, port.id):
			dimmed[port.id] = true
	_map.dimmed_ports = dimmed
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
	for i in n:
		var stop := Label.new()
		stop.text = "%d. %s" % [i + 1, GameData.port_name(_waypoints[i])]
		%WaypointList.add_child(stop)
		if n < 2:
			continue
		var next := _waypoints[(i + 1) % n]
		if next == _waypoints[i]:
			continue
		var distance := GameData.distance_nm(_waypoints[i], next)
		var lock_s := GameData.canal_lock_seconds(_waypoints[i], next)
		var sailing_s := _sailing_seconds(_waypoints[i], next)
		total_sailing_s += sailing_s
		total_nm += distance
		total_lock_s += lock_s
		var leg := Label.new()
		leg.theme_type_variation = &"DimLabel" if _ship.can_sail(_waypoints[i], next) else &"ErrorLabel"
		leg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var prefix := "back to" if i == n - 1 else "to"
		leg.text = "      %s %s · %s%s" % [prefix, GameData.port_name(next), _leg_text(distance, sailing_s, lock_s), _canal_text(_waypoints[i], next)]
		%WaypointList.add_child(leg)

	if n == 0:
		%TotalLabel.text = "Click ports on the map in the order the ship should visit them."
	elif n == 1:
		%TotalLabel.text = "Add at least one more port."
	else:
		%TotalLabel.text = "Full loop: %s" % _leg_text(total_nm, total_sailing_s, total_lock_s)


## Distance and time: sailing at top speed (slower in convoy canals), plus
## extra_s in locks (not counting any wait for a free chamber or a convoy).
func _leg_text(distance_nm: float, sailing_s: float, extra_s := 0.0) -> String:
	var time := Fmt.duration(sailing_s + extra_s) if sailing_s < INF else "?"
	return "%s nm · %s" % [Fmt.thousands(roundi(distance_nm)), time]


## Seconds to sail a leg at top speed, through its zones (convoy canals slow ships).
func _sailing_seconds(from_port: String, to_port: String) -> float:
	var speed := _ship.top_speed()
	if speed <= 0.0:
		return INF
	var seconds := 0.0
	var mile := 0.0
	for zone: Array in GameData.lane_zones(from_port, to_port):
		seconds += (float(zone[0]) - mile) / (speed * float(zone[1]))
		mile = zone[0]
	return seconds


## Each canal on a leg, e.g. " · Panama Canal: toll $4,200, +50% XP", plus the
## longest convoy wait and any cargo unloaded to pass; "" for none.
func _canal_text(from_port: String, to_port: String) -> String:
	var text := ""
	for crossing: Dictionary in GameData.canal_crossings(from_port, to_port):
		var canal: Dictionary = crossing.canal
		var parts := PackedStringArray()
		var toll := GameData.canal_toll(from_port, to_port, _ship.model(), canal)
		if toll > 0:
			parts.append("toll %s" % Fmt.money(toll))
		if float(canal.get("xp_bonus", 0.0)) > 0.0:
			parts.append("+%d%% XP" % roundi(float(canal.xp_bonus) * 100.0))
		if canal.get("type", "") == "convoy":
			parts.append("up to %s waiting for a convoy" % Fmt.duration(float(canal.get("convoy_interval_s", 90))))
		var lighten := float(canal.get("lighten", {}).get(_ship.model_id, 0.0))
		if lighten > 0.0:
			parts.append("unloads %d%% to pass (pay -%d%%)" % [roundi(lighten * 100.0), roundi(lighten * 100.0)])
		text += " · %s: %s" % [canal.name, ", ".join(parts)] if not parts.is_empty() else " · %s" % canal.name
	if GameData.is_rough_port(from_port) or GameData.is_rough_port(to_port):
		text += " · rough seas: +%d%% pay and XP, 2x wear" % roundi(float(GameData.config.get("rough_seas", {}).get("pay_bonus", 0.0)) * 100.0)
	return text

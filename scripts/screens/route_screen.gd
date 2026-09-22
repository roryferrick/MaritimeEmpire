extends Control
## Full-screen gray map for building a looping route by clicking ports in order.

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
	if ship.has_route():
		%CurrentLabel.text = "Current route: %s" % GameData.route_text(ship.route)
	else:
		%CurrentLabel.text = "No current route."
	_refresh()
	# Refit once the top and bottom bars have gone and the map has its full size.
	await get_tree().process_frame
	_map.fit_to_ports()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		finished.emit()


func _add_waypoint(port_id: String) -> void:
	if not _waypoints.is_empty() and _waypoints[-1] == port_id:
		_message = "Already stopping at %s. Pick a different port." % GameData.port_name(port_id)
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
	if not GameState.route_error(_waypoints).is_empty():
		return
	GameState.assign_route(_ship, _waypoints)
	Toast.show_message("%s: new route %s" % [_ship.name, GameData.route_text(_waypoints)])
	finished.emit()


func _refresh() -> void:
	_map.route = _waypoints.duplicate()
	_rebuild_list()

	var error := GameState.route_error(_waypoints)
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
		total_nm += distance
		var leg := Label.new()
		leg.theme_type_variation = &"DimLabel"
		var prefix := "back to" if i == n - 1 else "to"
		leg.text = "      %s %s · %s" % [prefix, GameData.port_name(next), _leg_text(distance)]
		%WaypointList.add_child(leg)

	if n == 0:
		%TotalLabel.text = "Click ports on the map in the order the ship should visit them."
	elif n == 1:
		%TotalLabel.text = "Add at least one more port."
	else:
		%TotalLabel.text = "Full loop: %s" % _leg_text(total_nm)


func _leg_text(distance_nm: float) -> String:
	var speed := _ship.speed()
	var time := Fmt.duration(distance_nm / speed) if speed > 0.0 else "?"
	return "%s nm · %s" % [Fmt.thousands(roundi(distance_nm)), time]

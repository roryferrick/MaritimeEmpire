class_name Ship
extends RefCounted
## A player-owned ship. Holds state only; GameState moves it.
##
## A ship is either docked (docked_at is set) or sailing a leg from_port -> to_port.
## Routes are loops of port ids; route_index is the route stop the ship is at or
## heading to.

var name := ""
var model_id := ""
var route: Array[String] = []
## Replaces route when the ship reaches the end of its current leg.
var pending_route: Array[String] = []
var route_index := -1
var paused := false
var docked_at := ""
var from_port := ""
var to_port := ""
var traveled_nm := 0.0


func _init(ship_name := "", ship_model_id := "", start_port := "") -> void:
	name = ship_name
	model_id = ship_model_id
	docked_at = start_port


func model() -> Dictionary:
	return GameData.get_ship_model(model_id)


func speed() -> float:
	return float(model().get("speed_nm_per_s", 0))


func capacity() -> int:
	return int(model().get("capacity", 0))


## Longest single leg this ship can sail, in nautical miles.
func range_nm() -> float:
	return float(model().get("range_nm", 0))


func can_sail(from: String, to: String) -> bool:
	return from != to and GameData.distance_nm(from, to) <= range_nm()


## The port a new route starts from: where it's docked, or where it's heading.
func reference_port() -> String:
	return docked_at if is_docked() else to_port


func is_docked() -> bool:
	return not docked_at.is_empty()


func has_route() -> bool:
	return not route.is_empty()


## Green on the status dot: has a route and isn't paused.
func is_running() -> bool:
	return has_route() and not paused


func leg_length() -> float:
	return GameData.distance_nm(from_port, to_port)


func leg_progress() -> float:
	var length := leg_length()
	return clampf(traveled_nm / length, 0.0, 1.0) if length > 0.0 else 1.0


## Position in projected map coordinates.
func world_position() -> Vector2:
	if is_docked():
		return GameData.port_position(docked_at)
	var sea_lane = GameData.lane(from_port, to_port)
	if sea_lane == null:
		return GameData.port_position(from_port)
	return sea_lane.sample(traveled_nm)[0]


## Direction of travel in projected map coordinates (zero when docked).
func heading() -> Vector2:
	if is_docked():
		return Vector2.ZERO
	var sea_lane = GameData.lane(from_port, to_port)
	return sea_lane.sample(traveled_nm)[1] if sea_lane else Vector2.ZERO


## Index of the route stop to sail to next from the port the ship is docked at.
func next_route_index() -> int:
	if route_index >= 0 and route_index < route.size() and route[route_index] == docked_at:
		return (route_index + 1) % route.size()
	var here := route.find(docked_at)
	if here >= 0:
		return (here + 1) % route.size()
	return 0  # Not on the route yet: head to its first stop.


func status_text() -> String:
	if is_docked():
		var text := "Docked at %s" % GameData.port_name(docked_at)
		if not has_route():
			text += " (no route)"
		elif paused:
			text += " (paused)"
		return text
	var destination := GameData.port_name(to_port)
	if paused:
		return "Stopping at %s" % destination
	return "En route to %s — %d%%" % [destination, int(leg_progress() * 100.0)]


func to_dict() -> Dictionary:
	return {
		"name": name,
		"model_id": model_id,
		"route": route,
		"pending_route": pending_route,
		"route_index": route_index,
		"paused": paused,
		"docked_at": docked_at,
		"from_port": from_port,
		"to_port": to_port,
		"traveled_nm": traveled_nm,
	}


static func from_dict(data: Dictionary) -> Ship:
	var ship := Ship.new(data.get("name", ""), data.get("model_id", ""), data.get("docked_at", ""))
	ship.route.assign(data.get("route", []))
	ship.pending_route.assign(data.get("pending_route", []))
	ship.route_index = int(data.get("route_index", -1))
	ship.paused = bool(data.get("paused", false))
	ship.from_port = data.get("from_port", "")
	ship.to_port = data.get("to_port", "")
	ship.traveled_nm = float(data.get("traveled_nm", 0.0))
	return ship

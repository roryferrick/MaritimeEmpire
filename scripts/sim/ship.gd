class_name Ship
extends RefCounted
## A player-owned ship. Holds state only; GameState moves it.
##
## A ship is either docked (docked_at is set) or sailing a leg from_port -> to_port.
## Routes are loops of port ids; route_index is the route stop the ship is at or
## heading to.
##
## Maintenance (0..1) wears down while the ship runs at sea and slows it down;
## fuel burns at a constant rate per second at sea. After arriving, a ship docks
## for dock_seconds(): it unloads (and is paid), is repaired then refueled if
## those toggles are on, and loads again before it can leave.

## Speed never drops below this fraction of top speed, however worn the ship is.
const MIN_SPEED_FACTOR := 0.5

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

var fuel := 0.0
var maintenance := 1.0
var auto_refuel := true
var auto_repair := true
## Seconds since the ship docked at the end of a leg; -1 when not unloading/loading.
var dock_time := -1.0
## Earned on the leg just sailed; paid when unloading finishes.
var cargo_payment := 0
var unloaded := true
## Rates (per second) that refill what was missing on arrival within one refill phase.
var repair_rate := 0.0
var refuel_rate := 0.0
## Spent at the current stop, for display.
var stop_fuel_cost := 0.0
var stop_repair_cost := 0.0
## Fractions of a dollar spent but not yet taken from the player's money.
var bill := 0.0
## Why a running ship is stuck in port, or "".
var hold_reason := ""


func _init(ship_name := "", ship_model_id := "", start_port := "") -> void:
	name = ship_name
	model_id = ship_model_id
	docked_at = start_port
	fuel = fuel_tank()


func model() -> Dictionary:
	return GameData.get_ship_model(model_id)


func top_speed() -> float:
	return float(model().get("speed_nm_per_s", 0))


## Current speed: top speed scaled by maintenance, down to MIN_SPEED_FACTOR.
func speed() -> float:
	return top_speed() * maxf(maintenance, MIN_SPEED_FACTOR)


func capacity() -> int:
	return int(model().get("capacity", 0))


## Longest single leg this ship can sail at full maintenance, in nautical miles.
func range_nm() -> float:
	return float(model().get("range_nm", 0))


func fuel_tank() -> float:
	return float(model().get("fuel_tank", 0))


## Fuel burned per second at sea.
func fuel_per_s() -> float:
	return float(model().get("fuel_per_s", 0))


## Maintenance lost per second of running at sea.
func wear_per_s() -> float:
	return float(model().get("wear_pct_per_min", 0)) / 100.0 / 60.0


## Cost of restoring 100% maintenance (from 0%).
func full_repair_cost() -> float:
	return float(model().get("repair_cost_per_pct", 0)) * 100.0


func dock_seconds() -> float:
	return float(model().get("dock_s", 0))


## How long the repair phase takes, and then the refuel phase, while docked.
func refill_phase_seconds() -> float:
	return float(model().get("refill_phase_s", 5))


func can_sail(from: String, to: String) -> bool:
	return from != to and GameData.distance_nm(from, to) <= range_nm()


## Seconds to sail a distance starting at a given maintenance, slowing as the
## ship wears until it hits MIN_SPEED_FACTOR.
func sailing_seconds(distance: float, start_maintenance: float) -> float:
	var v := top_speed()
	var w := wear_per_s()
	var m := start_maintenance
	if v <= 0.0:
		return INF
	if w <= 0.0 or m <= MIN_SPEED_FACTOR:
		return distance / (v * maxf(m, MIN_SPEED_FACTOR))
	var fade_time := (m - MIN_SPEED_FACTOR) / w
	var fade_distance := v * (m + MIN_SPEED_FACTOR) / 2.0 * fade_time
	if distance <= fade_distance:
		return (m - sqrt(m * m - 2.0 * w * distance / v)) / w
	return fade_time + (distance - fade_distance) / (v * MIN_SPEED_FACTOR)


## Fuel needed to sail between two ports, leaving at the current maintenance.
func fuel_needed(from: String, to: String) -> float:
	return fuel_per_s() * sailing_seconds(GameData.distance_nm(from, to), maintenance)


## The port a new route starts from: where it's docked, or where it's heading.
func reference_port() -> String:
	return docked_at if is_docked() else to_port


func is_docked() -> bool:
	return not docked_at.is_empty()


## Unloading and loading after arriving at a port.
func is_docking() -> bool:
	return is_docked() and dock_time >= 0.0


func has_route() -> bool:
	return not route.is_empty()


## Green on the status dot: has a route and isn't paused.
func is_running() -> bool:
	return has_route() and not paused


## Running, but stuck in port (e.g. not enough fuel).
func is_held() -> bool:
	return not hold_reason.is_empty()


func fuel_level() -> float:
	var tank := fuel_tank()
	return clampf(fuel / tank, 0.0, 1.0) if tank > 0.0 else 0.0


## 1 when loaded; empties while unloading and fills again while loading.
func cargo_level() -> float:
	if not is_docking() or dock_seconds() <= 0.0:
		return 1.0
	return clampf(absf(1.0 - 2.0 * dock_time / dock_seconds()), 0.0, 1.0)


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
		var port := GameData.port_name(docked_at)
		if is_docking():
			return ("Unloading at %s" if dock_time < dock_seconds() / 2.0 else "Loading at %s") % port
		var text := "Docked at %s" % port
		if not has_route():
			text += " (no route)"
		elif paused:
			text += " (paused)"
		elif is_held():
			text += " — %s" % hold_reason
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
		"fuel": fuel,
		"maintenance": maintenance,
		"auto_refuel": auto_refuel,
		"auto_repair": auto_repair,
		"dock_time": dock_time,
		"cargo_payment": cargo_payment,
		"unloaded": unloaded,
		"repair_rate": repair_rate,
		"refuel_rate": refuel_rate,
		"stop_fuel_cost": stop_fuel_cost,
		"stop_repair_cost": stop_repair_cost,
		"bill": bill,
	}


## Saves from before fuel and maintenance load with full tanks, 100%
## maintenance and both toggles on.
static func from_dict(data: Dictionary) -> Ship:
	var ship := Ship.new(data.get("name", ""), data.get("model_id", ""), data.get("docked_at", ""))
	ship.route.assign(data.get("route", []))
	ship.pending_route.assign(data.get("pending_route", []))
	ship.route_index = int(data.get("route_index", -1))
	ship.paused = bool(data.get("paused", false))
	ship.from_port = data.get("from_port", "")
	ship.to_port = data.get("to_port", "")
	ship.traveled_nm = float(data.get("traveled_nm", 0.0))
	ship.fuel = float(data.get("fuel", ship.fuel_tank()))
	ship.maintenance = float(data.get("maintenance", 1.0))
	ship.auto_refuel = bool(data.get("auto_refuel", true))
	ship.auto_repair = bool(data.get("auto_repair", true))
	ship.dock_time = float(data.get("dock_time", -1.0))
	ship.cargo_payment = int(data.get("cargo_payment", 0))
	ship.unloaded = bool(data.get("unloaded", true))
	ship.repair_rate = float(data.get("repair_rate", 0.0))
	ship.refuel_rate = float(data.get("refuel_rate", 0.0))
	ship.stop_fuel_cost = float(data.get("stop_fuel_cost", 0.0))
	ship.stop_repair_cost = float(data.get("stop_repair_cost", 0.0))
	ship.bill = float(data.get("bill", 0.0))
	return ship

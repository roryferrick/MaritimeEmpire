class_name Ship
extends RefCounted
## A player-owned ship. Holds state only; GameState moves it.
##
## A ship is either docked (docked_at is set) or sailing a leg from_port -> to_port.
## Routes are loops of port ids; route_index is the route stop the ship is at or
## heading to.
##
## Maintenance (0..1) wears down while the ship runs at sea and slows it down
## (at 0% it stops); fuel burns at a constant rate per second at sea. After
## arriving, a ship docks for dock_seconds(): it unloads (and is paid), is
## repaired then refueled if those toggles are on, and loads again before it
## can leave.
##
## A ship that runs out of fuel or maintenance at sea is lost until a recovery
## boat (a Mammoth, or a Mini Mammoth for small ships) tows it to the nearer
## end of its leg. A recovery boat has no route: it sails a job (a list of lane
## segments) to the lost ship, turns to line up with it, carries it to port,
## then sails home.

## How long a Mammoth takes to turn and line up with a lost ship, and to turn
## the pair around if it's towing it back the way it came.
const ALIGN_SECONDS := 2.0

## Job phases for a Mammoth.
const JOB_NONE := ""
const JOB_APPROACH := "approach"
const JOB_ALIGN := "align"
const JOB_TOW := "tow"

## A ship sells for this fraction of its price, times its maintenance.
const SELL_FRACTION := 0.5

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
## Earned and spent at the current stop, for display.
var stop_sale := 0
var stop_fuel_cost := 0.0
var stop_repair_cost := 0.0
## Fractions of a dollar spent but not yet taken from the player's money.
var bill := 0.0
## Why a running ship is stuck in port, or "".
var hold_reason := ""

## Why this ship is stranded at sea ("out of fuel", "engine failure"), or "".
var lost_reason := ""
## Send the cheapest capable recovery boat automatically when lost.
var auto_recover := true
## When it was lost, relative to other lost ships (lower = earlier), for the recovery queue.
var lost_order := 0
## At sea without the fuel (or maintenance) to reach the end of its leg.
var at_risk := false
## Lifetime money in (income) and out (fuel, repair, and recovery: what a
## recovery boat spent saving this ship), in dollars.
var ledger := {"income": 0.0, "fuel": 0.0, "repair": 0.0, "recovery": 0.0}
## The Mammoth sent to recover this ship, if any.
var rescuer: Ship = null

## Mammoth only: the lost ship it's recovering, the job phase, where the
## current segment ends (nm along from_port -> to_port), the segments still to
## sail ([from, to, start_nm, end_nm]), seconds spent aligning, and the port
## it's towing to.
var rescuing: Ship = null
var job_phase := JOB_NONE
var segment_end := 0.0
var job_segments: Array = []
var align_time := 0.0
var tow_port := ""
## Recovery boat only: the ship its spending is charged to, from being sent
## on a job until it has refilled back at home.
var billing: Ship = null


func _init(ship_name := "", ship_model_id := "", start_port := "") -> void:
	name = ship_name
	model_id = ship_model_id
	docked_at = start_port
	fuel = fuel_tank()


func model() -> Dictionary:
	return GameData.get_ship_model(model_id)


## A recovery boat (Mammoth or Mini Mammoth): recovers lost ships instead of sailing routes.
func is_recovery() -> bool:
	return bool(model().get("recovery", false))


## Recovery boat only: whether it can carry this ship (models listed in
## "carries", or any model if none are listed).
func can_carry(other: Ship) -> bool:
	var carries: Array = model().get("carries", [])
	return is_recovery() and (carries.is_empty() or carries.has(other.model_id))


## What the ship sells for: half its price, scaled by maintenance.
func sell_price() -> int:
	return floori(float(model().get("price", 0)) * SELL_FRACTION * clampf(maintenance, 0.0, 1.0))


## Docked and not busy recovering (or being recovered).
func can_sell() -> bool:
	return is_docked() and not is_on_job() and not is_lost()


func profit() -> float:
	return ledger.income - ledger.fuel - ledger.repair - ledger.recovery


func top_speed() -> float:
	return float(model().get("speed_nm_per_s", 0))


## Current speed: top speed scaled by maintenance.
func speed() -> float:
	return top_speed() * clampf(maintenance, 0.0, 1.0)


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
## ship wears. INF if it would wear down to a stop first.
func sailing_seconds(distance: float, start_maintenance: float) -> float:
	var v := top_speed()
	var w := wear_per_s()
	var m := start_maintenance
	if distance <= 0.0:
		return 0.0
	if v <= 0.0 or m <= 0.0:
		return INF
	if w <= 0.0:
		return distance / (v * m)
	var discriminant := m * m - 2.0 * w * distance / v
	if discriminant < 0.0:
		return INF
	return (m - sqrt(discriminant)) / w


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


## Stranded at sea, waiting for (or being carried by) a Mammoth.
func is_lost() -> bool:
	return not lost_reason.is_empty()


## A Mammoth out on a job.
func is_on_job() -> bool:
	return job_phase != JOB_NONE


## Riding on a Mammoth (from partway through its alignment until port).
func is_carried() -> bool:
	return rescuer != null and rescuer.is_carrying()


## Mammoth only: has the lost ship aboard.
func is_carrying() -> bool:
	return job_phase == JOB_TOW or (job_phase == JOB_ALIGN and align_time >= ALIGN_SECONDS)


## Mammoth only: turns the pair around after lining up, when towing back the way the ship came.
func tow_turns_around() -> bool:
	return rescuing != null and tow_port == rescuing.from_port


## Mammoth only: total seconds spent lining up (and turning around if needed).
func align_seconds() -> float:
	return ALIGN_SECONDS * (2.0 if tow_turns_around() else 1.0)


## Green on the status dot.
func is_active() -> bool:
	if is_recovery():
		return is_on_job() or not is_docked()
	return is_running() and not is_held() and not is_lost()


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
	if is_carried():
		return rescuer.world_position()
	if is_docked():
		return GameData.port_position(docked_at)
	var sea_lane = GameData.lane(from_port, to_port)
	if sea_lane == null:
		return GameData.port_position(from_port)
	return sea_lane.sample(traveled_nm)[0]


## Direction of travel in projected map coordinates (zero when docked).
func heading() -> Vector2:
	if is_carried():
		return rescuer.heading()
	if is_docked():
		return Vector2.ZERO
	if job_phase == JOB_ALIGN:
		return _align_heading()
	return _lane_heading(from_port, to_port, traveled_nm)


## Turns from the approach heading to the lost ship's heading, then (if
## towing it back) on round to face the way it came.
func _align_heading() -> Vector2:
	var arrive := _lane_heading(from_port, to_port, traveled_nm).angle()
	var ship_angle := _lane_heading(rescuing.from_port, rescuing.to_port, rescuing.traveled_nm).angle()
	if align_time < ALIGN_SECONDS:
		return Vector2.from_angle(lerp_angle(arrive, ship_angle, align_time / ALIGN_SECONDS))
	var t := (align_time - ALIGN_SECONDS) / ALIGN_SECONDS if tow_turns_around() else 0.0
	return Vector2.from_angle(ship_angle + PI * clampf(t, 0.0, 1.0))


static func _lane_heading(from: String, to: String, distance: float) -> Vector2:
	var sea_lane = GameData.lane(from, to)
	return sea_lane.sample(distance)[1] if sea_lane else Vector2.ZERO


## Index of the route stop to sail to next from the port the ship is docked at.
func next_route_index() -> int:
	if route_index >= 0 and route_index < route.size() and route[route_index] == docked_at:
		return (route_index + 1) % route.size()
	var here := route.find(docked_at)
	if here >= 0:
		return (here + 1) % route.size()
	return 0  # Not on the route yet: head to its first stop.


func status_text() -> String:
	if is_recovery():
		return _recovery_status_text()
	if is_lost():
		if rescuer == null:
			if auto_recover:
				return "Lost at sea (%s), waiting for a free recovery boat" % lost_reason
			return "Lost at sea (%s)" % lost_reason
		if is_carried():
			return "Being carried to %s by %s" % [GameData.port_name(rescuer.tow_port), rescuer.name]
		return "Lost at sea (%s), %s on the way" % [lost_reason, rescuer.name]
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
	var text := "En route to %s — %d%%" % [destination, int(leg_progress() * 100.0)]
	return text + " — won't make it!" if at_risk else text


func _recovery_status_text() -> String:
	match job_phase:
		JOB_APPROACH:
			return "Heading to recover %s" % rescuing.name
		JOB_ALIGN:
			return "Lining up with %s" % rescuing.name
		JOB_TOW:
			return "Carrying %s to %s" % [rescuing.name, GameData.port_name(tow_port)]
	if is_docked():
		var port := GameData.port_name(docked_at)
		if is_docking():
			return "Refueling at %s" % port
		if is_held():
			return "Docked at %s — %s" % [port, hold_reason]
		return "Standing by at %s" % port
	return "Returning to %s — %d%%" % [GameData.port_name(to_port), int(leg_progress() * 100.0)]


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
		"stop_sale": stop_sale,
		"stop_fuel_cost": stop_fuel_cost,
		"stop_repair_cost": stop_repair_cost,
		"bill": bill,
		"lost_reason": lost_reason,
		"rescuing": rescuing.name if rescuing else "",
		"job_phase": job_phase,
		"segment_end": segment_end,
		"job_segments": job_segments,
		"align_time": align_time,
		"tow_port": tow_port,
		"billing": billing.name if billing else "",
		"auto_recover": auto_recover,
		"lost_order": lost_order,
		"ledger": ledger,
	}


## Saves from before fuel and maintenance load with full tanks, 100%
## maintenance and both toggles on. Call link_rescues() once every ship is loaded.
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
	ship.stop_sale = int(data.get("stop_sale", 0))
	ship.stop_fuel_cost = float(data.get("stop_fuel_cost", 0.0))
	ship.stop_repair_cost = float(data.get("stop_repair_cost", 0.0))
	ship.bill = float(data.get("bill", 0.0))
	ship.lost_reason = data.get("lost_reason", "")
	ship.job_phase = data.get("job_phase", JOB_NONE)
	ship.segment_end = float(data.get("segment_end", 0.0))
	ship.job_segments = data.get("job_segments", [])
	ship.align_time = float(data.get("align_time", 0.0))
	ship.tow_port = data.get("tow_port", "")
	ship.auto_recover = bool(data.get("auto_recover", true))
	ship.lost_order = int(data.get("lost_order", 0))
	var saved_ledger: Dictionary = data.get("ledger", {})
	for key: String in ship.ledger:
		ship.ledger[key] = float(saved_ledger.get(key, 0.0))
	ship.set_meta(&"billing", data.get("billing", ""))
	ship.set_meta(&"rescuing", data.get("rescuing", ""))
	return ship


## Reconnects recovery boats to the ships they're recovering (and billing) after loading.
static func link_rescues(all: Array[Ship]) -> void:
	for mammoth in all:
		var target: String = mammoth.get_meta(&"rescuing", "")
		var billed: String = mammoth.get_meta(&"billing", "")
		mammoth.remove_meta(&"rescuing")
		mammoth.remove_meta(&"billing")
		for ship in all:
			if not target.is_empty() and ship.name == target:
				mammoth.rescuing = ship
				ship.rescuer = mammoth
			if not billed.is_empty() and ship.name == billed:
				mammoth.billing = ship
		if mammoth.rescuing == null:
			mammoth.job_phase = JOB_NONE

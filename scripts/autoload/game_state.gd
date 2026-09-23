extends Node
## State of the running game session: money, ships and their movement, plus
## saving and loading.
##
## The world only advances while a session is open. The game saves on quit
## and on a timer; nothing happens while the game is closed.

signal money_changed(money: int)
signal containers_changed(total: int)
## A ship was bought or sold.
signal ships_changed
## A ship docked, finished docking, departed, was held in port, was
## paused/resumed, got a new route, or had a refuel/repair toggle changed.
signal ship_changed(ship: Ship)
## A ship finished unloading at a port and was paid.
signal ship_arrived(ship: Ship, port_id: String, payment: int)
## A running ship is stuck in port, e.g. without enough fuel for its next leg.
signal ship_held(ship: Ship, reason: String)
## A ship left a port, with what it earned and spent there.
signal ship_departed(ship: Ship, port_id: String, sale: int, fuel_cost: int, repair_cost: int)
## A random breakdown knocked a ship's maintenance down.
signal ship_broke_down(ship: Ship)
## A ship ran out of fuel or maintenance at sea.
signal ship_lost(ship: Ship)
## A Mammoth dropped a lost ship at a port (its destination, or back where it came from).
signal ship_recovered(ship: Ship, mammoth: Ship, port_id: String, to_destination: bool)
## A recovery boat was sent to a lost ship (automatically, if auto is true).
signal recovery_sent(ship: Ship, boat: Ship, cost: int, auto: bool)
## A ship at sea no longer has the fuel or maintenance to reach port.
signal ship_at_risk(ship: Ship)
## A ship was sold.
signal ship_sold(ship: Ship, price: int)
## The company earned XP (from a delivery).
signal company_xp_changed(total_xp: float)
## The company reached a new level; unlocks lists what it opened up.
signal company_leveled(level: int, unlocks: Array[String])
## A ship reached a new level and has a skill point to spend.
signal ship_leveled(ship: Ship, level: int)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 2
const MAX_NAME_LENGTH := 24
const MAX_COMPANY_NAME_LENGTH := 32
## Seconds of spare fuel a ship must have beyond what its next leg needs.
const DEPARTURE_MARGIN_S := 1.0
## A worn-out Mammoth still crawls at this fraction of top speed, so it can always finish a job.
const MIN_RECOVERY_SPEED_FACTOR := 0.05
## The finances window: money is tallied in buckets this many seconds long,
## kept for WINDOW_SECONDS.
const BUCKET_SECONDS := 10.0
const WINDOW_SECONDS := 600.0
## How often lost ships with auto-recovery on look for a free boat.
const AUTO_RECOVERY_INTERVAL := 0.5
## Kinds of money tallied in the finances.
const MONEY_KINDS: Array[String] = ["income", "fuel", "repair", "recovery", "bought", "sold"]

var money: int = 0:
	set(value):
		money = value
		money_changed.emit(money)

var containers_delivered: int = 0:
	set(value):
		containers_delivered = value
		containers_changed.emit(containers_delivered)

var company_name := ""
## New ships are delivered here.
var home_port := ""
var ships: Array[Ship] = []
var in_session := false

## Seconds the company has been playing (only counts while a session is open).
var play_time := 0.0
## Total company XP from deliveries; see Progression for levels.
var company_xp := 0.0
## All-time totals for each of MONEY_KINDS.
var totals := {}
## Recent money, oldest first: {start (play_time), fleet: {kind: amount},
## ships: {ship name: {kind: amount}}}.
var _window: Array = []

var _autosave_timer := Timer.new()
var _breakdown_clock := 0.0
var _auto_recovery_clock := 0.0


func _ready() -> void:
	_autosave_timer.wait_time = float(GameData.config.get("autosave_seconds", 30))
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _process(delta: float) -> void:
	if not in_session:
		return
	play_time += delta
	for ship in ships:
		_advance(ship, delta)
	_roll_breakdowns(delta)
	_auto_recovery_clock += delta
	if _auto_recovery_clock >= AUTO_RECOVERY_INTERVAL:
		_auto_recovery_clock = 0.0
		_send_queued_recoveries()


# --- Ships ---------------------------------------------------------------

func buy_ship(model_id: String, ship_name: String) -> Ship:
	ship_name = ship_name.strip_edges()
	if not buy_error(model_id).is_empty() or not ship_name_error(ship_name).is_empty():
		return null
	var price := int(GameData.get_ship_model(model_id).get("price", 0))
	money -= price
	_record(null, "bought", price)
	var ship := Ship.new(ship_name, model_id, home_port)
	ships.append(ship)
	ships_changed.emit()
	save_game()
	return ship


func owned_count(model_id: String) -> int:
	return ships.filter(func(ship: Ship) -> bool: return ship.model_id == model_id).size()


## Why the player can't buy another of this model, or "" if they can.
func buy_error(model_id: String) -> String:
	var model := GameData.get_ship_model(model_id)
	if company_level() < Progression.unlock_level(model):
		return "Unlocks at company level %d." % Progression.unlock_level(model)
	if not model.get("recovery", false) and cargo_ship_count() >= Progression.fleet_slots(company_level()):
		var next := Progression.next_slots(company_level())
		var more := " Reach level %d for %d." % next if not next.is_empty() else ""
		return "All %d fleet slots are full.%s" % [Progression.fleet_slots(company_level()), more]
	var limit := int(model.get("max_owned", 0))
	if limit > 0 and owned_count(model_id) >= limit:
		return "You already own the maximum of %d %s ships." % [limit, model.get("name", model_id)]
	if money < int(model.get("price", 0)):
		return "You can't afford this ship."
	return ""


func company_name_error(new_company_name: String) -> String:
	return "Enter a company name." if new_company_name.strip_edges().is_empty() else ""


func company_level() -> int:
	return int(Progression.company_level(company_xp).level)


## Cargo ships owned (recovery boats don't use fleet slots).
func cargo_ship_count() -> int:
	return ships.filter(func(ship: Ship) -> bool: return not ship.is_recovery()).size()


## Spends one of a ship's skill points on "speed", "durability" or "efficiency".
func level_skill(ship: Ship, skill: String) -> void:
	if not ship.can_level_skill(skill):
		return
	ship.skills[skill] = int(ship.skills[skill]) + 1
	ship_changed.emit(ship)


## Why a ship name can't be used, or "" if it's fine.
func ship_name_error(ship_name: String) -> String:
	ship_name = ship_name.strip_edges()
	if ship_name.is_empty():
		return "Enter a name."
	for ship in ships:
		if ship.name.nocasecmp_to(ship_name) == 0:
			return "You already have a ship called %s." % ship.name
	return ""


func suggest_ship_name() -> String:
	var first: Array = GameData.ship_names.get("first", [])
	var second: Array = GameData.ship_names.get("second", [])
	if not first.is_empty() and not second.is_empty():
		for attempt in 100:
			var candidate := "%s %s" % [first.pick_random(), second.pick_random()]
			if ship_name_error(candidate).is_empty():
				return candidate
	var n := ships.size() + 1
	while not ship_name_error("Ship %d" % n).is_empty():
		n += 1
	return "Ship %d" % n


## Why a route can't be given to a ship, or "" if it's valid. Routes loop, so
## the last stop also can't be the same as the first, and every leg (including
## the one back to the start, and the trip from where the ship is now to the
## route's first port) must be within the ship's range.
func route_error(route: Array[String], ship: Ship) -> String:
	if route.size() < 2:
		return "A route needs at least 2 ports."
	for i in range(1, route.size()):
		if route[i] == route[i - 1]:
			return "A ship can't visit the same port twice in a row."
	if route[-1] == route[0]:
		return "The route loops back to %s, so it can't also end there." % GameData.port_name(route[0])
	for i in route.size():
		var from := route[i]
		var to := route[(i + 1) % route.size()]
		if not ship.can_sail(from, to):
			return _range_error(ship, from, to)
	var start := ship.reference_port()
	if not route.has(start) and not ship.can_sail(start, route[0]):
		return _range_error(ship, start, route[0])
	return ""


func _range_error(ship: Ship, from: String, to: String) -> String:
	return "%s to %s is %s nm, beyond this ship's %s nm range." % [
		GameData.port_name(from), GameData.port_name(to),
		Fmt.thousands(roundi(GameData.distance_nm(from, to))), Fmt.thousands(roundi(ship.range_nm()))]


## Gives a ship a new route and sets it running. A ship at sea finishes its
## current leg first.
func assign_route(ship: Ship, route: Array[String]) -> void:
	if ship.is_recovery() or not route_error(route, ship).is_empty():
		return
	ship.paused = false
	if ship.is_docked():
		ship.route = route.duplicate()
		ship.pending_route.clear()
		ship.route_index = ship.route.find(ship.docked_at)
	else:
		ship.pending_route = route.duplicate()
	ship_changed.emit(ship)


## A ship paused at sea carries on to its next port and waits there.
func set_paused(ship: Ship, paused: bool) -> void:
	if not ship.has_route():
		return
	ship.paused = paused
	ship_changed.emit(ship)


func set_auto_refuel(ship: Ship, on: bool) -> void:
	ship.auto_refuel = on
	ship_changed.emit(ship)


func set_auto_repair(ship: Ship, on: bool) -> void:
	ship.auto_repair = on
	ship_changed.emit(ship)


func set_auto_recover(ship: Ship, on: bool) -> void:
	ship.auto_recover = on
	ship_changed.emit(ship)


## Why a ship can't be sold right now, or "".
func sell_error(ship: Ship) -> String:
	if ship.is_lost():
		return "A lost ship can't be sold."
	if not ship.can_sell():
		return "Ships can only be sold while docked."
	return ""


## Sells a docked ship for Ship.sell_price(). Returns why it couldn't, or "".
func sell_ship(ship: Ship) -> String:
	var error := sell_error(ship)
	if not error.is_empty():
		return error
	var price := ship.sell_price()
	for other in ships:
		if other.billing == ship:
			other.billing = null
	ships.erase(ship)
	money += price
	_record(null, "sold", price)
	ship_sold.emit(ship, price)
	ships_changed.emit()
	save_game()
	return ""


func _advance(ship: Ship, delta: float) -> void:
	if ship.is_on_job():
		_advance_job(ship, delta)
	elif ship.is_docked():
		_advance_docked(ship, delta)
	elif not ship.is_lost() and _sail(ship, delta) and ship.traveled_nm >= ship.leg_length():
		_arrive(ship, ship.to_port)


## Wears, burns fuel and moves a ship along its current lane. Returns false if
## the ship ran out of fuel or maintenance and is now lost at sea. Mammoths
## only set off when they can finish, so they're never lost.
func _sail(ship: Ship, delta: float) -> bool:
	if ship.is_running() or ship.is_recovery():
		ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * delta, 0.0)
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * delta, 0.0)
	if not ship.is_recovery():
		if ship.fuel <= 0.0:
			_lose(ship, "out of fuel")
			return false
		if ship.maintenance <= 0.0:
			_lose(ship, "broken down")
			return false
	var speed := ship.speed()
	if ship.is_recovery():
		speed = maxf(speed, ship.top_speed() * MIN_RECOVERY_SPEED_FACTOR)
	ship.traveled_nm += speed * delta
	if not ship.is_recovery():
		_check_at_risk(ship)
	return true


## Flags a ship that no longer has the fuel (or maintenance) to finish its leg.
func _check_at_risk(ship: Ship) -> void:
	var left := ship.leg_length() - ship.traveled_nm
	var at_risk := ship.fuel < ship.fuel_per_s() * ship.sailing_seconds(left, ship.maintenance)
	if at_risk == ship.at_risk:
		return
	ship.at_risk = at_risk
	if at_risk:
		ship_at_risk.emit(ship)
	ship_changed.emit(ship)


func _lose(ship: Ship, reason: String) -> void:
	ship.lost_reason = reason
	ship.lost_order = roundi(play_time * 1000.0)
	ship.at_risk = false
	ship_lost.emit(ship)
	ship_changed.emit(ship)


## Every breakdown_interval_s, a breakdown_chance roll; on a hit, one random
## ship at sea (not a Mammoth) loses breakdown_hit of maintenance.
func _roll_breakdowns(delta: float) -> void:
	var interval := float(GameData.config.get("breakdown_interval_s", 5))
	_breakdown_clock += delta
	while _breakdown_clock >= interval:
		_breakdown_clock -= interval
		if randf() >= float(GameData.config.get("breakdown_chance", 0.01)):
			continue
		var candidates := ships.filter(func(ship: Ship) -> bool:
			return not ship.is_recovery() and not ship.is_docked() and not ship.is_lost())
		if candidates.is_empty():
			continue
		var ship: Ship = candidates.pick_random()
		if randf() < ship.breakdown_resistance():
			continue  # Its durability skill shrugged it off.
		ship.maintenance = maxf(ship.maintenance - float(GameData.config.get("breakdown_hit", 0.5)), 0.0)
		ship_broke_down.emit(ship)
		if ship.maintenance <= 0.0:
			_lose(ship, "broken down")


func _arrive(ship: Ship, port: String, paid := true) -> void:
	ship.at_risk = false
	ship.cargo_payment = GameData.leg_payment(ship.from_port, port, ship.capacity()) if paid else 0
	ship.unloaded = ship.cargo_payment <= 0
	ship.docked_at = port
	ship.from_port = ""
	ship.to_port = ""
	ship.traveled_nm = 0.0
	if not ship.pending_route.is_empty():
		ship.route = ship.pending_route.duplicate()
		ship.pending_route.clear()
		ship.route_index = ship.route.find(port)
	ship.dock_time = 0.0
	var phase := ship.refill_phase_seconds()
	ship.repair_rate = (1.0 - ship.maintenance) / phase
	ship.refuel_rate = (ship.fuel_tank() - ship.fuel) / phase
	ship.stop_sale = 0
	ship.stop_fuel_cost = 0.0
	ship.stop_repair_cost = 0.0
	ship_changed.emit(ship)


## Docking runs on a fixed clock: repair for one refill phase, then refuel for
## one, with unloading (and payment) over the first half of the dock time and
## loading over the second. Afterwards a running ship leaves as soon as it has
## the fuel for its next leg, and a Mammoth away from home sails back.
func _advance_docked(ship: Ship, delta: float) -> void:
	if ship.is_docking():
		var phase := ship.refill_phase_seconds()
		var start := ship.dock_time
		var end := start + delta
		if ship.auto_repair:
			_repair(ship, ship.repair_rate * _overlap(start, end, 0.0, phase))
		if ship.auto_refuel:
			_refuel(ship, ship.refuel_rate * _overlap(start, end, phase, 2.0 * phase))
		ship.dock_time = end
		if not ship.unloaded and end >= ship.dock_seconds() / 2.0:
			_unload(ship)
		if end < ship.dock_seconds():
			return
		ship.dock_time = -1.0
		if ship.docked_at == home_port:
			ship.billing = null
		ship_changed.emit(ship)
	if ship.is_recovery() and ship.docked_at != home_port:
		_try_depart(ship, delta, home_port)
	elif ship.is_running():
		_try_depart(ship, delta, ship.route[ship.next_route_index()])
	else:
		_set_hold(ship, "")


func _unload(ship: Ship) -> void:
	ship.unloaded = true
	ship.stop_sale = ship.cargo_payment
	money += ship.cargo_payment
	_record(ship, "income", ship.cargo_payment)
	containers_delivered += ship.capacity()
	ship_arrived.emit(ship, ship.docked_at, ship.cargo_payment)
	var pay_rate := float(GameData.config.get("pay_per_container_nm", 1.0))
	_gain_xp(ship, Progression.xp_for_delivery(1, ship.cargo_payment / pay_rate))


## Adds delivery XP to the company and the ship, announcing any level-ups.
func _gain_xp(ship: Ship, amount: float) -> void:
	var company_before := company_level()
	var ship_before := ship.level()
	company_xp += amount
	ship.xp += amount
	company_xp_changed.emit(company_xp)
	for level in range(company_before + 1, company_level() + 1):
		company_leveled.emit(level, Progression.unlocks_at(level))
	if ship.level() > ship_before:
		ship_leveled.emit(ship, ship.level())
		ship_changed.emit(ship)


## Fuel a ship must have to set off on a leg: enough for the leg, allowing for
## wear, plus a little spare.
func _fuel_to_leave(ship: Ship, to: String) -> float:
	return ship.fuel_needed(ship.docked_at, to) + ship.fuel_per_s() * DEPARTURE_MARGIN_S


## Leaves once it has fuel for the leg to `to`. A ship that ran out of money
## while refilling tops up (as the toggles and money allow) until its tank is
## full or the money runs out, and is held in port while it lacks fuel for the leg.
func _try_depart(ship: Ship, delta: float, to: String) -> void:
	var phase := ship.refill_phase_seconds()
	var topping_up := ship.auto_refuel and ship.fuel < ship.fuel_tank() and _can_spend(ship)
	if topping_up or ship.fuel < _fuel_to_leave(ship, to):
		var too_worn := _fuel_to_leave(ship, to) > ship.fuel_tank()
		if too_worn and ship.auto_repair:
			_repair(ship, delta / phase)
		elif ship.auto_refuel:
			_refuel(ship, ship.fuel_tank() / phase * delta)
		var need := _fuel_to_leave(ship, to)
		if ship.fuel >= need and ship.fuel < ship.fuel_tank() and ship.auto_refuel and _can_spend(ship):
			_set_hold(ship, "")
			return  # Still topping up.
		if ship.fuel < need:
			var destination := GameData.port_name(to)
			var fresh_need := ship.fuel_per_s() * (DEPARTURE_MARGIN_S
				+ ship.sailing_seconds(GameData.distance_nm(ship.docked_at, to), 1.0))
			if fresh_need > ship.fuel_tank():
				_set_hold(ship, "%s is beyond this ship's range; assign a new route" % destination)
			elif need > ship.fuel_tank():
				_set_hold(ship, "too worn to reach %s on a full tank%s" % [destination,
					", waiting for money to repair" if ship.auto_repair else "; turn on repair"])
			elif not ship.auto_refuel:
				_set_hold(ship, "not enough fuel for %s; turn on refuel" % destination)
			else:
				_set_hold(ship, "waiting for money to buy fuel for %s" % destination)
			return
	_set_hold(ship, "")
	_depart(ship, to)


func _set_hold(ship: Ship, reason: String) -> void:
	if ship.hold_reason == reason:
		return
	ship.hold_reason = reason
	if not reason.is_empty():
		ship_held.emit(ship, reason)
	ship_changed.emit(ship)


func _depart(ship: Ship, to: String) -> void:
	if not ship.is_recovery():
		ship.route_index = ship.next_route_index()
	_leave_port(ship)
	ship.from_port = ship.docked_at
	ship.to_port = to
	ship.traveled_nm = 0.0
	ship.docked_at = ""
	ship_changed.emit(ship)


## Reports what the ship earned and spent at the port it's leaving.
func _leave_port(ship: Ship) -> void:
	var fuel := roundi(ship.stop_fuel_cost)
	var repair := roundi(ship.stop_repair_cost)
	if ship.stop_sale > 0 or fuel > 0 or repair > 0:
		ship_departed.emit(ship, ship.docked_at, ship.stop_sale, fuel, repair)
	ship.stop_sale = 0
	ship.stop_fuel_cost = 0.0
	ship.stop_repair_cost = 0.0
	ship.dock_time = -1.0
	ship.hold_reason = ""


# --- Recovery --------------------------------------------------------------

## How the cheapest free recovery boat able to carry a lost ship would recover
## it: {mammoth, segments, tow_port, approach_nm, seconds, fuel, cost}, or
## {error} saying why none can.
func recovery_plan(lost: Ship) -> Dictionary:
	if not lost.is_lost() or lost.rescuer != null:
		return {error = "This ship doesn't need recovering."}
	var capable := ships.filter(func(ship: Ship) -> bool: return ship.can_carry(lost))
	if capable.is_empty():
		var model_name: String = lost.model().get("name", lost.model_id)
		if ships.any(func(ship: Ship) -> bool: return ship.is_recovery()):
			return {error = "Only a Mammoth can carry a %s. Buy one in the Shop." % model_name}
		return {error = "Buy a Mammoth or Mini Mammoth in the Shop to recover lost ships."}
	var best := {}
	var reason := "Every recovery boat that can carry it is busy."
	for boat: Ship in capable:
		if boat.is_on_job() or not boat.is_docked() or boat.is_docking():
			continue
		var plan := _plan_for(boat, lost)
		if boat.fuel < plan.fuel:
			reason = "No free recovery boat has the fuel and maintenance to reach it."
			continue
		if best.is_empty() or plan.cost < best.cost:
			best = plan
	return best if not best.is_empty() else {error = reason}


## Lost ships with auto-recovery on, longest-lost first, each get the cheapest
## free boat that can carry them, if there is one.
func _send_queued_recoveries() -> void:
	var waiting := ships.filter(func(ship: Ship) -> bool:
		return ship.is_lost() and ship.auto_recover and ship.rescuer == null)
	waiting.sort_custom(func(a: Ship, b: Ship) -> bool: return a.lost_order < b.lost_order)
	for ship: Ship in waiting:
		_send_recovery(ship, true)


## Sends the cheapest free recovery boat that can carry a lost ship. Returns
## why it couldn't, or "".
func send_recovery(lost: Ship) -> String:
	return _send_recovery(lost, false)


## From sending until it has refilled back at home, the boat's spending is
## charged to the ship it's recovering.
func _send_recovery(lost: Ship, auto: bool) -> String:
	var plan := recovery_plan(lost)
	if plan.has("error"):
		return plan.error
	var mammoth: Ship = plan.mammoth
	_leave_port(mammoth)
	mammoth.docked_at = ""
	mammoth.rescuing = lost
	mammoth.billing = lost
	lost.rescuer = mammoth
	recovery_sent.emit(lost, mammoth, roundi(plan.cost), auto)
	mammoth.tow_port = plan.tow_port
	mammoth.job_segments = plan.segments.duplicate(true)
	mammoth.job_phase = Ship.JOB_APPROACH
	_start_segment(mammoth, mammoth.job_segments.pop_front())
	ship_changed.emit(mammoth)
	ship_changed.emit(lost)
	return ""


## The Mammoth sails the lanes to the lost ship's position (via whichever end of
## its leg is closer), then carries it to the nearer end of its leg.
func _plan_for(mammoth: Ship, lost: Ship) -> Dictionary:
	var start := mammoth.docked_at
	var a := lost.from_port
	var b := lost.to_port
	var done := lost.traveled_nm
	var left := lost.leg_length() - done
	var via_a := (0.0 if start == a else GameData.distance_nm(start, a)) + done
	var via_b := (0.0 if start == b else GameData.distance_nm(start, b)) + left
	var segments := []
	if via_a <= via_b:
		if start != a:
			segments.append([start, a, 0.0, GameData.distance_nm(start, a)])
		segments.append([a, b, 0.0, done])
	else:
		if start != b:
			segments.append([start, b, 0.0, GameData.distance_nm(start, b)])
		segments.append([b, a, 0.0, left])
	var tow_port := a if done <= left else b
	if tow_port == a:
		segments.append([b, a, left, left + done])
	else:
		segments.append([a, b, done, done + left])
	var approach_nm := minf(via_a, via_b)
	var seconds := mammoth.sailing_seconds(approach_nm + minf(done, left), mammoth.maintenance)
	var home_seconds := 0.0
	if tow_port != home_port:
		home_seconds = mammoth.sailing_seconds(GameData.distance_nm(tow_port, home_port), 1.0)
	var running := seconds + home_seconds
	return {
		mammoth = mammoth,
		segments = segments,
		tow_port = tow_port,
		approach_nm = approach_nm,
		seconds = seconds + Ship.ALIGN_SECONDS * (2.0 if tow_port == a else 1.0),
		fuel = mammoth.fuel_per_s() * (seconds + DEPARTURE_MARGIN_S),
		cost = mammoth.fuel_per_s() * running * float(GameData.config.get("fuel_price", 0))
			+ minf(mammoth.wear_per_s() * running, 1.0) * mammoth.full_repair_cost(),
	}


func _start_segment(ship: Ship, segment: Array) -> void:
	ship.from_port = segment[0]
	ship.to_port = segment[1]
	ship.traveled_nm = segment[2]
	ship.segment_end = segment[3]


## A Mammoth on a job: sail to the lost ship, line up with it, carry it to port.
func _advance_job(mammoth: Ship, delta: float) -> void:
	if mammoth.job_phase == Ship.JOB_ALIGN:
		mammoth.align_time += delta
		if mammoth.align_time >= mammoth.align_seconds():
			mammoth.job_phase = Ship.JOB_TOW
			_start_segment(mammoth, mammoth.job_segments.pop_front())
			ship_changed.emit(mammoth)
			ship_changed.emit(mammoth.rescuing)
		return
	_sail(mammoth, delta)
	if mammoth.traveled_nm < mammoth.segment_end:
		return
	mammoth.traveled_nm = mammoth.segment_end
	if mammoth.job_phase == Ship.JOB_TOW:
		_deliver(mammoth)
	elif mammoth.job_segments.size() > 1:
		_start_segment(mammoth, mammoth.job_segments.pop_front())
	else:
		mammoth.job_phase = Ship.JOB_ALIGN
		mammoth.align_time = 0.0
		ship_changed.emit(mammoth)


## Drops the carried ship at the tow port. It's paid as usual if that's where
## it was going, and nothing if it was taken back to where it came from.
func _deliver(mammoth: Ship) -> void:
	var lost := mammoth.rescuing
	var port := mammoth.tow_port
	var to_destination := port == lost.to_port
	mammoth.rescuing = null
	mammoth.job_phase = Ship.JOB_NONE
	mammoth.job_segments.clear()
	mammoth.tow_port = ""
	lost.rescuer = null
	lost.lost_reason = ""
	_arrive(mammoth, port, false)
	_arrive(lost, port, to_destination)
	ship_recovered.emit(lost, mammoth, port, to_destination)


## Restores up to `amount` of maintenance, as far as money allows.
func _repair(ship: Ship, amount: float) -> void:
	amount = minf(amount, 1.0 - ship.maintenance)
	if amount <= 0.0:
		return
	var cost := amount * ship.full_repair_cost()
	var paid := _spend(ship, cost, "repair")
	ship.stop_repair_cost += paid
	ship.maintenance = minf(ship.maintenance + amount * paid / cost, 1.0)


## Adds up to `amount` of fuel, as far as money allows.
func _refuel(ship: Ship, amount: float) -> void:
	amount = minf(amount, ship.fuel_tank() - ship.fuel)
	if amount <= 0.0:
		return
	var cost := amount * float(GameData.config.get("fuel_price", 0))
	var paid := _spend(ship, cost, "fuel")
	ship.stop_fuel_cost += paid
	ship.fuel = minf(ship.fuel + amount * paid / cost, ship.fuel_tank())


## Spends up to `cost` dollars of a kind ("fuel" or "repair") without going
## below $0 and returns what was spent. Money is whole dollars, so fractions
## build up on the ship's bill.
func _spend(ship: Ship, cost: float, kind: String) -> float:
	if cost <= 0.0:
		return 0.0
	var paid := minf(cost, float(money) - ship.bill)
	if paid <= 0.0:
		return 0.0
	_record(ship, kind, paid)
	ship.bill += paid
	var whole := floori(ship.bill)
	if whole > 0:
		ship.bill -= whole
		money -= whole
	return paid


func _can_spend(ship: Ship) -> bool:
	return float(money) - ship.bill > 0.0


## Length of the overlap between the time spans [a0, a1) and [b0, b1).
static func _overlap(a0: float, a1: float, b0: float, b1: float) -> float:
	return maxf(minf(a1, b1) - maxf(a0, b0), 0.0)


# --- Finances ------------------------------------------------------------

## Tallies money of a kind (see MONEY_KINDS) for a ship (null for the company
## as a whole: buying and selling ships). A recovery boat's spending goes on
## the books of the ship it's recovering.
func _record(ship: Ship, kind: String, amount: float) -> void:
	if ship and ship.billing:
		ship = ship.billing
		kind = "recovery"
	totals[kind] = float(totals.get(kind, 0.0)) + amount
	var bucket := _current_bucket()
	bucket.fleet[kind] = float(bucket.fleet.get(kind, 0.0)) + amount
	if ship:
		ship.ledger[kind] = float(ship.ledger.get(kind, 0.0)) + amount
		var tally: Dictionary = bucket.ships.get_or_add(ship.name, {})
		tally[kind] = float(tally.get(kind, 0.0)) + amount


func _current_bucket() -> Dictionary:
	var start := floorf(play_time / BUCKET_SECONDS) * BUCKET_SECONDS
	if _window.is_empty() or _window[-1].start < start:
		_window.append({start = start, fleet = {}, ships = {}})
	while _window[0].start < play_time - WINDOW_SECONDS:
		_window.pop_front()
	return _window[-1]


## Money over the last WINDOW_SECONDS: {fleet: {kind: amount}, ships: {ship
## name: profit}}.
func recent_finances() -> Dictionary:
	var fleet := {}
	var ship_profit := {}
	for bucket: Dictionary in _window:
		if bucket.start < play_time - WINDOW_SECONDS:
			continue
		for kind: String in bucket.fleet:
			fleet[kind] = float(fleet.get(kind, 0.0)) + bucket.fleet[kind]
		for ship_name: String in bucket.ships:
			var tally: Dictionary = bucket.ships[ship_name]
			var costs := float(tally.get("fuel", 0.0)) + float(tally.get("repair", 0.0)) + float(tally.get("recovery", 0.0))
			ship_profit[ship_name] = float(ship_profit.get(ship_name, 0.0)) + float(tally.get("income", 0.0)) - costs
	return {fleet = fleet, ships = ship_profit}


# --- Saving --------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func new_game(new_company_name: String, new_home_port: String) -> void:
	company_name = new_company_name.strip_edges()
	home_port = new_home_port
	money = int(GameData.config.get("starting_money", 10000))
	containers_delivered = 0
	_clear_ships()
	play_time = 0.0
	totals = {}
	company_xp = 0.0
	_window = []
	_begin_session()
	save_game()


## Loads the save file and starts a session. Returns why it couldn't, or "".
func continue_game() -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameState: save file %s is missing or corrupt" % SAVE_PATH)
		return "The saved game could not be read."
	if int(data.get("version", 0)) != SAVE_VERSION:
		return "This save is from an older version of the game and can't be loaded. Start a new game."
	company_name = data.get("company_name", "")
	home_port = data.get("home_port", "")
	money = int(data.get("money", 0))
	containers_delivered = int(data.get("containers_delivered", 0))
	_clear_ships()
	play_time = float(data.get("play_time", 0.0))
	totals = data.get("totals", {})
	# Saves from before XP: count the XP past deliveries would have earned.
	var pay_rate := float(GameData.config.get("pay_per_container_nm", 1.0))
	company_xp = float(data.get("company_xp",
		Progression.xp_for_delivery(1, float(totals.get("income", 0.0)) / pay_rate)))
	_window = data.get("finance_window", [])
	for ship_data: Dictionary in data.get("ships", []):
		ships.append(Ship.from_dict(ship_data))
	Ship.link_rescues(ships)
	_begin_session()
	return ""


func save_game() -> void:
	if not in_session:
		return
	var data := {
		"version": SAVE_VERSION,
		"company_name": company_name,
		"home_port": home_port,
		"money": money,
		"play_time": play_time,
		"company_xp": company_xp,
		"totals": totals,
		"finance_window": _window,
		"containers_delivered": containers_delivered,
		"ships": ships.map(func(ship: Ship) -> Dictionary: return ship.to_dict()),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: could not write save (%s)" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))


## Ships and the Mammoths recovering them point at each other; break those
## links so the old ships are freed.
func _clear_ships() -> void:
	for ship in ships:
		ship.rescuer = null
		ship.rescuing = null
		ship.billing = null
	ships.clear()


func _begin_session() -> void:
	ActivityLog.clear()
	in_session = true
	_autosave_timer.start()

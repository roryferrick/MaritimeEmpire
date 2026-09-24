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
## A ship left a port, with what it earned and spent there (toll: the canal
## toll paid on the leg that brought it there).
signal ship_departed(ship: Ship, port_id: String, sale: int, fuel_cost: int, repair_cost: int, toll: int)
## A cargo ship entered a canal and paid its toll.
signal canal_entered(ship: Ship, canal: Dictionary, toll: int)
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
## The HQ or a hub was built, upgraded or leveled up.
signal hubs_changed
## An HQ or hub reached a new level and has an upgrade point to spend.
signal hub_leveled(hub: Hub, level: int)
## A new hub was founded at a port.
signal hub_built(hub: Hub)
## The fast-forward speed changed.
signal time_speed_changed(speed: int)

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
const MONEY_KINDS: Array[String] = ["income", "fuel", "repair", "tolls", "bought", "sold", "hubs"]
## Order "Upgrade all" levels skills in, and breaks ties in.
const AUTO_UPGRADE_ORDER: Array[String] = ["speed", "efficiency", "durability"]
## Fast-forward speeds the top bar button cycles through.
const TIME_SPEEDS: Array[int] = [1, 2, 4]

var money: int = 0:
	set(value):
		money = value
		money_changed.emit(money)

var containers_delivered: int = 0:
	set(value):
		containers_delivered = value
		containers_changed.emit(containers_delivered)

var company_name := ""
## The company's color id (see game_config company_colors): its name in the
## top bar and the rings around its HQ and hubs.
var company_color := "purple"
## New ships are delivered here.
var home_port := ""
var ships: Array[Ship] = []
var in_session := false
## Fast forward: the world advances this many times per frame. Not saved;
## every session starts at 1x.
var time_speed := 1:
	set(value):
		time_speed = value
		time_speed_changed.emit(time_speed)

## Seconds the company has been playing (only counts while a session is open).
var play_time := 0.0
## Total company XP from deliveries; see Progression for levels.
var company_xp := 0.0
## The map's Routes switch: show the fleet's route lanes faintly.
var show_active_routes := true
## The HQ (at the home port, first) and the hubs placed since.
var hubs: Array[Hub] = []
## All-time totals for each of MONEY_KINDS.
var totals := {}
## Per canal id: {crossings, tolls, xp (the extra company XP its bonus gave)}.
var canal_stats := {}
## Recent money, oldest first: {start (play_time), fleet: {kind: amount},
## ships: {ship name: {kind: amount}}}.
var _window: Array = []

var _autosave_timer := Timer.new()
var _breakdown_clock := 0.0
var _auto_recovery_clock := 0.0
## Lock chambers (GameData.chamber_key()): the ship in or heading into each,
## and the ships waiting for each, in order.
var _chamber_ships := {}
var _chamber_lines := {}


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
	# Fast forward runs whole extra steps rather than one longer one, so ships
	# arrive, dock and break down exactly as they would at 1x.
	for step in time_speed:
		_step(delta)


func _step(delta: float) -> void:
	play_time += delta
	for ship in ships:
		_advance(ship, delta)
	_roll_breakdowns(delta)
	_auto_recovery_clock += delta
	if _auto_recovery_clock >= AUTO_RECOVERY_INTERVAL:
		_auto_recovery_clock = 0.0
		_send_queued_recoveries()


## Steps to the next of TIME_SPEEDS, back to 1x after the fastest.
func cycle_time_speed() -> void:
	time_speed = TIME_SPEEDS[(TIME_SPEEDS.find(time_speed) + 1) % TIME_SPEEDS.size()]


# --- Ships ---------------------------------------------------------------

## Buys a ship and launches it docked at port_id, which must be the HQ or a hub
## (the HQ if empty).
func buy_ship(model_id: String, ship_name: String, port_id := "") -> Ship:
	ship_name = ship_name.strip_edges()
	if port_id.is_empty():
		port_id = home_port
	if not buy_error(model_id).is_empty() or not ship_name_error(ship_name).is_empty() or not hub_at(port_id):
		return null
	var price := int(GameData.get_ship_model(model_id).get("price", 0))
	money -= price
	_record(null, "bought", price)
	var ship := Ship.new(ship_name, model_id, port_id)
	ships.append(ship)
	if ship.is_recovery():
		ship.base_port = port_id
		_rebalance_recovery_boats()
	ships_changed.emit()
	save_game()
	return ship


func owned_count(model_id: String) -> int:
	return ships.filter(func(ship: Ship) -> bool: return ship.model_id == model_id).size()


## Why the player can't buy another of this model, or "" if they can.
func buy_error(model_id: String) -> String:
	var model := GameData.get_ship_model(model_id)
	var level := company_level()
	if level < Progression.unlock_level(model):
		return "Unlocks at company level %d." % Progression.unlock_level(model)
	var slots := Progression.model_slots(model, level)
	if owned_count(model_id) >= slots:
		var next := Progression.next_slot_level(model, level)
		if next < 0:
			return "You already own the maximum of %d %s ships." % [slots, model.get("name", model_id)]
		return "All %d %s slots are full. Level %d gives another." % [slots, model.get("name", model_id), next]
	if money < int(model.get("price", 0)):
		return "You can't afford this ship."
	return ""


func company_name_error(new_company_name: String) -> String:
	return "Enter a company name." if new_company_name.strip_edges().is_empty() else ""


## The company's color as a Color (purple if its id isn't in the config).
func company_color_value() -> Color:
	for entry: Array in GameData.config.get("company_colors", []):
		if entry[0] == company_color:
			return Color.from_string(entry[2], Color.MEDIUM_PURPLE)
	return Color.from_string("#b67cf2", Color.MEDIUM_PURPLE)


func company_level() -> int:
	return int(Progression.company_level(company_xp).level)


## Spends one of a ship's skill points on "speed", "durability" or "efficiency".
func level_skill(ship: Ship, skill: String) -> void:
	if not ship.can_level_skill(skill):
		return
	ship.skills[skill] = int(ship.skills[skill]) + 1
	ship_changed.emit(ship)


## Spends all of every ship's skill points round-robin: each point goes to the
## lowest skill, ties broken in AUTO_UPGRADE_ORDER, so a ship fills speed 1,
## efficiency 1, durability 1, speed 2... Returns how many points were spent.
func upgrade_all() -> int:
	var spent := 0
	for ship in ships:
		var before := spent
		while ship.skill_points() > 0:
			var best := ""
			for skill in AUTO_UPGRADE_ORDER:
				if ship.can_level_skill(skill) and (best.is_empty() or int(ship.skills[skill]) < int(ship.skills[best])):
					best = skill
			if best.is_empty():
				break
			ship.skills[best] = int(ship.skills[best]) + 1
			spent += 1
		if spent > before:
			ship_changed.emit(ship)
	return spent


## Unspent skill points across the fleet.
func unspent_skill_points() -> int:
	var points := 0
	for ship in ships:
		points += maxi(ship.skill_points(), 0)
	return points


# --- Headquarters and hubs ---------------------------------------------

## The HQ or hub at a port, or null.
func hub_at(port_id: String) -> Hub:
	for hub in hubs:
		if hub.port_id == port_id:
			return hub
	return null


## A hub bonus for ships at a port (0 if there's no hub there): "xp", "costs",
## "speed" or "pay".
func hub_bonus(port_id: String, path: String) -> float:
	var hub := hub_at(port_id)
	return hub.bonus(path) if hub else 0.0


## Hubs the company can still place.
func hubs_available() -> int:
	return maxi(Progression.hub_slots(company_level()) - hubs.size(), 0)


## Why a hub can't be built at a port, or "".
func build_hub_error(port_id: String) -> String:
	if hub_at(port_id):
		return "There's already a hub here."
	if hubs_available() <= 0:
		var every := int(Hub.settings().get("every_company_levels", 15))
		return "A new hub unlocks every %d company levels." % every
	return ""


## Founds a hub at a port, for good. Returns why it couldn't, or "".
func build_hub(port_id: String) -> String:
	var error := build_hub_error(port_id)
	if not error.is_empty():
		return error
	var hub := Hub.new(port_id)
	hubs.append(hub)
	_rebalance_recovery_boats()
	hub_built.emit(hub)
	hubs_changed.emit()
	save_game()
	return ""


## Why a hub can't take its next point in a path right now, or "".
func upgrade_hub_error(hub: Hub, path: String) -> String:
	if int(hub.upgrades.get(path, 0)) >= Hub.max_path_level():
		return "This path is maxed."
	if hub.upgrade_points() <= 0:
		return "No upgrade points: the hub gets one each level."
	if money < hub.upgrade_cost(path):
		return "Costs %s." % Fmt.money(hub.upgrade_cost(path))
	return ""


## Whether any of a hub's paths can be upgraded right now (points and money).
func hub_can_upgrade(hub: Hub) -> bool:
	return Hub.PATHS.any(func(path: Array) -> bool: return upgrade_hub_error(hub, path[0]).is_empty())


## Spends one of a hub's upgrade points on a path, and its price.
func upgrade_hub(hub: Hub, path: String) -> void:
	if not upgrade_hub_error(hub, path).is_empty():
		return
	var cost := hub.upgrade_cost(path)
	money -= cost
	_record(null, "hubs", cost)
	hub.upgrades[path] = int(hub.upgrades[path]) + 1
	hubs_changed.emit()


## Spreads recovery boats evenly across the HQ and hubs, model by model: each
## port gets its share (the ports with the most boats already keep any extra
## one), boats already at a port within its share stay, and the rest are
## re-based to the nearest port still short that a full tank can reach. A
## re-based boat sails there once it's free.
func _rebalance_recovery_boats() -> void:
	var ports := hubs.map(func(hub: Hub) -> String: return hub.port_id)
	if ports.is_empty():
		return
	var models := {}
	for ship in ships:
		if ship.is_recovery():
			models.get_or_add(ship.model_id, []).append(ship)
	for boats: Array in models.values():
		var count := {}
		for port: String in ports:
			count[port] = boats.filter(func(boat: Ship) -> bool: return boat.base_port == port).size()
		var by_count := ports.duplicate()
		by_count.sort_custom(func(a: String, b: String) -> bool: return count[a] > count[b])
		var quota := {}
		for i in by_count.size():
			quota[by_count[i]] = floori(float(boats.size()) / ports.size()) + (1 if i < boats.size() % ports.size() else 0)
		var kept := {}
		var surplus := []
		for boat: Ship in boats:
			var port := boat.base_port
			if quota.has(port) and int(kept.get(port, 0)) < int(quota[port]):
				kept[port] = int(kept.get(port, 0)) + 1
			else:
				surplus.append(boat)
		for boat: Ship in surplus:
			var here: String = boat.docked_at if boat.is_docked() else (boat.to_port if not boat.to_port.is_empty() else boat.base_port)
			var best := ""
			for port: String in ports:
				if int(kept.get(port, 0)) >= int(quota[port]) or not (port == here or boat.can_reach(here, port)):
					continue
				if best.is_empty() or GameData.distance_nm(here, port) < GameData.distance_nm(here, best):
					best = port
			if best.is_empty():
				continue  # No short port it can reach: it stays where it's based.
			kept[best] = int(kept.get(best, 0)) + 1
			if boat.base_port != best:
				boat.base_port = best
				ship_changed.emit(boat)


## Recovery boats based at a port.
func recovery_boats_at(port_id: String) -> Array:
	return ships.filter(func(ship: Ship) -> bool: return ship.is_recovery() and ship.base_port == port_id)


## XP a hub needs for its next level (0 at the max level).
func hub_level_cost(hub: Hub) -> float:
	return Progression.hub_level_cost(hub.level, company_level()) if hub.level < Hub.max_level() else 0.0


func _gain_hub_xp(hub: Hub, amount: float) -> void:
	if hub.level >= Hub.max_level():
		return
	hub.xp += amount
	var leveled := false
	while hub.level < Hub.max_level() and hub.xp >= hub_level_cost(hub):
		hub.xp -= hub_level_cost(hub)
		hub.level += 1
		leveled = true
		hub_leveled.emit(hub, hub.level)
	if hub.level >= Hub.max_level():
		hub.xp = 0.0
	if leveled:
		hubs_changed.emit()


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
			if candidate.length() <= MAX_NAME_LENGTH and ship_name_error(candidate).is_empty():
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
	ships.erase(ship)
	if ship.is_recovery():
		_rebalance_recovery_boats()
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
## only set off when they can finish, so they're never lost. In a canal, a
## ship waiting in a lock chamber, in line or for toll money stays put with its
## engines off (no fuel or wear).
func _sail(ship: Ship, delta: float) -> bool:
	var crossing := GameData.canal_crossing(ship.from_port, ship.to_port)
	if not crossing.is_empty() and _held_in_canal(ship, crossing, delta):
		return true
	if ship.is_running() or ship.is_recovery():
		ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * delta, 0.0)
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * delta, 0.0)
	if not ship.is_recovery():
		ship.sea_time += delta
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
	var target := ship.traveled_nm + speed * delta
	if not crossing.is_empty():
		target = _sail_canal(ship, crossing, target)
	ship.traveled_nm = target
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
	_leave_canal(ship)
	ship.lost_reason = reason
	ship.lost_order = roundi(play_time * 1000.0)
	ship.at_risk = false
	ship_lost.emit(ship)
	ship_changed.emit(ship)


## From the breakdowns min_company_level on, every interval_s each ship at sea
## (not recovery boats, and not in a canal) rolls its own
## Ship.breakdown_chance(); on a hit it loses hit of its maintenance, and is
## lost at sea if that leaves it at 0%.
func _roll_breakdowns(delta: float) -> void:
	var settings: Dictionary = GameData.config.get("breakdowns", {})
	var interval := float(settings.get("interval_s", 5))
	_breakdown_clock += delta
	while _breakdown_clock >= interval:
		_breakdown_clock -= interval
		if company_level() < int(settings.get("min_company_level", 6)):
			continue
		for ship in ships:
			if ship.is_recovery() or ship.is_docked() or ship.is_lost() or _in_canal(ship) or randf() >= ship.breakdown_chance():
				continue
			ship.maintenance = maxf(ship.maintenance - float(settings.get("hit", 0.5)), 0.0)
			ship_broke_down.emit(ship)
			if ship.maintenance <= 0.0:
				_lose(ship, "broken down")


func _arrive(ship: Ship, port: String, paid := true) -> void:
	ship.at_risk = false
	_leave_canal(ship)
	var crossing := GameData.canal_crossing(ship.from_port, port)
	ship.delivery_canal = crossing.canal.id if paid and ship.canal_entered and not crossing.is_empty() and not ship.is_recovery() else ""
	ship.stop_toll = ship.leg_toll
	ship.leg_toll = 0
	ship.canal_entered = false
	ship.cargo_payment = GameData.leg_payment(ship.from_port, port, ship.model()) if paid else 0
	ship.cargo_payment = roundi(ship.cargo_payment * (1.0 + hub_bonus(port, "pay")))
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
		ship_changed.emit(ship)
	if ship.is_recovery() and ship.docked_at != ship.base_port:
		_try_depart(ship, delta, ship.base_port)
	elif ship.is_running():
		_try_depart(ship, delta, ship.route[ship.next_route_index()])
	else:
		_set_hold(ship, "")


func _unload(ship: Ship) -> void:
	ship.unloaded = true
	ship.stop_sale = ship.cargo_payment
	money += ship.cargo_payment
	_record(ship, "income", ship.cargo_payment)
	if ship.model().get("category", "") == "container":
		containers_delivered += ship.capacity()
	ship_arrived.emit(ship, ship.docked_at, ship.cargo_payment)
	var hub := hub_at(ship.docked_at)
	var xp := Progression.xp_for_payment(ship.cargo_payment)
	# Cargo that came through a canal earns its XP bonus on top of the hub's.
	var canal := GameData.get_canal(ship.delivery_canal)
	var canal_bonus := float(canal.get("xp_bonus", 0.0))
	ship.delivery_canal = ""
	_gain_xp(ship, xp, 1.0 + (hub.bonus("xp") if hub else 0.0) + canal_bonus,
		1.0 + (hub.company_xp_bonus() if hub else 0.0) + canal_bonus)
	if canal_bonus > 0.0:
		var stats: Dictionary = canal_stats.get_or_add(canal.id, {crossings = 0, tolls = 0.0, xp = 0.0})
		stats.xp = float(stats.xp) + xp * canal_bonus
	if hub:
		hub.deliveries += 1
		hub.income += ship.cargo_payment
		_gain_hub_xp(hub, xp * (1.0 + canal_bonus))


## Adds delivery XP to the company (times company_multiplier, from a hub's
## company XP bonus) and to the ship (times ship_multiplier, from its ship XP
## upgrade), announcing any level-ups.
func _gain_xp(ship: Ship, amount: float, ship_multiplier := 1.0, company_multiplier := 1.0) -> void:
	var company_before := company_level()
	var ship_before := ship.level()
	company_xp += amount * company_multiplier
	ship.xp += amount * ship_multiplier
	var bucket := _current_bucket()
	bucket.fleet["xp"] = float(bucket.fleet.get("xp", 0.0)) + amount * company_multiplier
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
	_start_canal_leg(ship)
	ship_changed.emit(ship)


## Reports what the ship earned and spent at the port it's leaving (and the
## toll for the leg that brought it there).
func _leave_port(ship: Ship) -> void:
	var fuel := roundi(ship.stop_fuel_cost)
	var repair := roundi(ship.stop_repair_cost)
	if ship.stop_sale > 0 or fuel > 0 or repair > 0 or ship.stop_toll > 0:
		ship_departed.emit(ship, ship.docked_at, ship.stop_sale, fuel, repair, ship.stop_toll)
	ship.stop_sale = 0
	ship.stop_toll = 0
	ship.stop_fuel_cost = 0.0
	ship.stop_repair_cost = 0.0
	ship.dock_time = -1.0
	ship.hold_reason = ""


# --- Canals ----------------------------------------------------------------
#
# A lane through a canal (GameData.canal_crossing()) passes its lock chambers
# in order. Each chamber has a lane each way, holding one ship: a ship
# reserves the chamber ahead as it comes up to it (or joins the line for it,
# stopping queue_spacing_nm behind the ship ahead), sails in, and sits there
# step_seconds while the water rises or falls. It then leaves, unless the next
# chamber is close by (hold_chamber_nm), in which case it stays in this one until
# it has that one. Cargo ships pay the toll on entering the canal.

## Stops a ship that's in a lock chamber, in line, or waiting for toll money.
## Returns true while it's held there this frame.
func _held_in_canal(ship: Ship, crossing: Dictionary, delta: float) -> bool:
	if ship.lock_time >= 0.0:
		ship.lock_time += delta
		if ship.lock_time < float(crossing.canal.get("step_seconds", 3)):
			return true
		if _next_chamber_close(ship, crossing) and not _take_chamber(ship, crossing, ship.canal_step):
			return true
		_free_chamber(ship, _chamber_key(crossing, ship.canal_step - 1))
		ship.lock_time = -1.0
		ship_changed.emit(ship)
		return false
	match ship.canal_state:
		Ship.CANAL_TOLL:
			return not _pay_toll(ship, crossing)
		Ship.CANAL_QUEUED:
			if _take_chamber(ship, crossing, ship.canal_step):
				return false
			return ship.traveled_nm >= _line_stop(ship, crossing) - 0.001
	return false


## How far a ship sailing toward `target` (nm along its lane) gets: it stops at
## the canal entrance without toll money, at its place in line for a busy
## chamber, or in the chamber it has reserved.
func _sail_canal(ship: Ship, crossing: Dictionary, target: float) -> float:
	var from := ship.traveled_nm
	if not ship.canal_entered and from <= crossing.start_nm and target >= crossing.start_nm and not _pay_toll(ship, crossing):
		ship.canal_state = Ship.CANAL_TOLL
		ship_changed.emit(ship)
		return crossing.start_nm
	var step := ship.canal_step
	if not _chamber_ahead(ship, crossing, step):
		return target
	var chamber: Dictionary = crossing.chambers[step]
	if ship.canal_state.is_empty():
		var in_line := _sailing_in_line(_chamber_lines.get(_chamber_key(crossing, step), []), null)
		if target < chamber.mile - _line_spacing(crossing) * (in_line + 1):
			return target
		_take_chamber(ship, crossing, step)
	if ship.canal_state == Ship.CANAL_QUEUED:
		return maxf(from, minf(target, _line_stop(ship, crossing)))
	if target < chamber.mile:
		return target
	ship.canal_step += 1
	ship.lock_time = 0.0
	ship.canal_state = ""
	ship_changed.emit(ship)
	return chamber.mile


## Reserves a chamber if it's free and the ship is first in line for it;
## otherwise puts the ship in line (if it isn't already). Returns true if reserved.
func _take_chamber(ship: Ship, crossing: Dictionary, step: int) -> bool:
	var key := _chamber_key(crossing, step)
	var line: Array = _chamber_lines.get_or_add(key, [])
	if _chamber_ships.has(key) or (not line.is_empty() and line[0] != ship):
		if not line.has(ship):
			line.append(ship)
			ship.canal_state = Ship.CANAL_QUEUED
			ship.canal_queue_since = play_time
			ship_changed.emit(ship)
		return false
	line.erase(ship)
	_chamber_ships[key] = ship
	ship.canal_state = Ship.CANAL_RESERVED
	ship_changed.emit(ship)
	return true


func _free_chamber(ship: Ship, key: String) -> void:
	if _chamber_ships.get(key) == ship:
		_chamber_ships.erase(key)


## True if the lane has a chamber at this step before the ship's stretch ends
## (a recovery boat's job segment can end partway along a lane).
func _chamber_ahead(ship: Ship, crossing: Dictionary, step: int) -> bool:
	var end := ship.segment_end if ship.is_on_job() else ship.leg_length()
	return step < crossing.chambers.size() and crossing.chambers[step].mile < end


## True if the ship's next chamber is close enough that it waits in the one it's in.
func _next_chamber_close(ship: Ship, crossing: Dictionary) -> bool:
	var step := ship.canal_step
	if not _chamber_ahead(ship, crossing, step):
		return false
	var gap: float = crossing.chambers[step].mile - crossing.chambers[step - 1].mile
	return gap <= float(crossing.canal.get("hold_chamber_nm", 3.0))


## Where a ship in line stops: queue_spacing_nm behind each ship ahead of it
## that's still sailing (ships waiting in the chamber before don't count).
func _line_stop(ship: Ship, crossing: Dictionary) -> float:
	var line: Array = _chamber_lines.get(_chamber_key(crossing, ship.canal_step), [])
	var ahead := _sailing_in_line(line, ship)
	return crossing.chambers[ship.canal_step].mile - _line_spacing(crossing) * (ahead + 1)


## Ships in a line that are sailing rather than waiting in a chamber, up to `before` (all if null).
static func _sailing_in_line(line: Array, before: Ship) -> int:
	var count := 0
	for other: Ship in line:
		if other == before:
			break
		if other.lock_time < 0.0:
			count += 1
	return count


static func _line_spacing(crossing: Dictionary) -> float:
	return float(crossing.canal.get("queue_spacing_nm", 1.6))


static func _chamber_key(crossing: Dictionary, step: int) -> String:
	return GameData.chamber_key(crossing.canal.id, crossing.chambers[step].index, crossing.forward)


## Charges a cargo ship its toll for entering the canal. Returns false if it
## can't afford it yet. Recovery boats go through free.
func _pay_toll(ship: Ship, crossing: Dictionary) -> bool:
	var canal: Dictionary = crossing.canal
	if not ship.is_recovery():
		var toll := GameData.canal_toll(ship.from_port, ship.to_port, ship.model())
		if money < toll:
			return false
		money -= toll
		_record(ship, "tolls", toll)
		ship.leg_toll += toll
		var stats: Dictionary = canal_stats.get_or_add(canal.id, {crossings = 0, tolls = 0.0, xp = 0.0})
		stats.crossings = int(stats.crossings) + 1
		stats.tolls = float(stats.tolls) + toll
		canal_entered.emit(ship, canal, toll)
	ship.canal_entered = true
	ship.canal_state = ""
	ship_changed.emit(ship)
	return true


## Sets up a ship's canal state for the leg or job segment it's starting (which
## may start partway along its lane, past some chambers).
func _start_canal_leg(ship: Ship) -> void:
	_leave_canal(ship)
	ship.canal_step = 0
	ship.canal_entered = false
	var crossing := GameData.canal_crossing(ship.from_port, ship.to_port)
	if crossing.is_empty():
		return
	for chamber: Dictionary in crossing.chambers:
		if chamber.mile < ship.traveled_nm - 0.001:
			ship.canal_step += 1
	ship.canal_entered = ship.traveled_nm > crossing.start_nm + 0.001


## Frees any chamber a ship holds and takes it out of every line.
func _leave_canal(ship: Ship) -> void:
	for key: String in _chamber_ships.keys():
		if _chamber_ships[key] == ship:
			_chamber_ships.erase(key)
	for line: Array in _chamber_lines.values():
		line.erase(ship)
	ship.lock_time = -1.0
	ship.canal_state = ""


## True while a ship is between a canal's entrance and exit, or held up at one
## (in line, even back past the entrance, or waiting for toll money): no
## breakdowns there.
func _in_canal(ship: Ship) -> bool:
	if ship.is_docked() or ship.from_port.is_empty():
		return false
	if not ship.canal_state.is_empty() or ship.lock_time >= 0.0:
		return true
	var crossing := GameData.canal_crossing(ship.from_port, ship.to_port)
	return not crossing.is_empty() and ship.traveled_nm >= crossing.start_nm and ship.traveled_nm <= crossing.end_nm


## Rebuilds who holds and waits for each chamber from the ships' own state,
## after loading. Saves from before canals work out each ship's progress from
## where it is.
func _rebuild_canal_lines() -> void:
	_chamber_ships.clear()
	_chamber_lines.clear()
	var waiting: Array[Ship] = []
	for ship in ships:
		var crossing := {}
		if not ship.is_docked() and not ship.is_lost() and not ship.from_port.is_empty():
			crossing = GameData.canal_crossing(ship.from_port, ship.to_port)
		if crossing.is_empty():
			ship.canal_step = 0
			ship.lock_time = -1.0
			ship.canal_state = ""
			continue
		if ship.canal_step < 0 or ship.canal_step > crossing.chambers.size():
			_start_canal_leg(ship)
		if ship.lock_time >= 0.0 and ship.canal_step > 0:
			_chamber_ships[_chamber_key(crossing, ship.canal_step - 1)] = ship
		if ship.canal_state == Ship.CANAL_RESERVED and ship.canal_step < crossing.chambers.size():
			_chamber_ships[_chamber_key(crossing, ship.canal_step)] = ship
		elif ship.canal_state == Ship.CANAL_QUEUED and ship.canal_step < crossing.chambers.size():
			waiting.append(ship)
	waiting.sort_custom(func(a: Ship, b: Ship) -> bool: return a.canal_queue_since < b.canal_queue_since)
	for ship in waiting:
		var crossing := GameData.canal_crossing(ship.from_port, ship.to_port)
		_chamber_lines.get_or_add(_chamber_key(crossing, ship.canal_step), []).append(ship)


## The ship in (or heading into) one lane of a lock chamber, or null.
func chamber_ship(canal_id: String, chamber_index: int, forward: bool) -> Ship:
	return _chamber_ships.get(GameData.chamber_key(canal_id, chamber_index, forward))


## Ships waiting for one lane of a lock chamber, first in line first.
func chamber_line(canal_id: String, chamber_index: int, forward: bool) -> Array:
	return _chamber_lines.get(GameData.chamber_key(canal_id, chamber_index, forward), [])


## A ship's place (1 = first) in line for its next chamber, or 0 if it isn't in one.
func canal_line_position(ship: Ship) -> int:
	if ship.canal_state != Ship.CANAL_QUEUED:
		return 0
	var crossing := GameData.canal_crossing(ship.from_port, ship.to_port)
	if crossing.is_empty() or ship.canal_step >= crossing.chambers.size():
		return 0
	return chamber_line(crossing.canal.id, crossing.chambers[ship.canal_step].index, crossing.forward).find(ship) + 1


# --- Recovery --------------------------------------------------------------

## How the nearest free recovery boat able to carry a lost ship (the cheapest,
## if two are as near) would recover it: {mammoth, segments, tow_port, approach_nm, seconds, fuel, cost}, or
## {error} saying why none can.
func recovery_plan(lost: Ship) -> Dictionary:
	if not lost.is_lost() or lost.rescuer != null:
		return {error = "This ship doesn't need recovering."}
	var capable := ships.filter(func(ship: Ship) -> bool: return ship.can_carry(lost))
	if capable.is_empty():
		var model_name: String = lost.model().get("name", lost.model_id)
		if ships.any(func(ship: Ship) -> bool: return ship.is_recovery()):
			return {error = "Only a Mammoth can carry a %s. Buy one in the Shop." % model_name}
		return {error = "Buy a Mammoth or Buffalo in the Shop to recover lost ships."}
	var best := {}
	var reason := "Every recovery boat that can carry it is busy."
	for boat: Ship in capable:
		if boat.is_on_job() or not boat.is_docked() or boat.is_docking():
			continue
		var plan := _plan_for(boat, lost)
		if boat.fuel < plan.fuel:
			reason = "No free recovery boat has the fuel and maintenance to reach it."
			continue
		if best.is_empty() or plan.approach_nm < best.approach_nm \
				or (is_equal_approx(plan.approach_nm, best.approach_nm) and plan.cost < best.cost):
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


## Sends the nearest free recovery boat that can carry a lost ship. Returns
## why it couldn't, or "".
func send_recovery(lost: Ship) -> String:
	return _send_recovery(lost, false)


## Sends the nearest free capable boat; auto says whether auto-recovery sent it.
func _send_recovery(lost: Ship, auto: bool) -> String:
	var plan := recovery_plan(lost)
	if plan.has("error"):
		return plan.error
	var mammoth: Ship = plan.mammoth
	_leave_port(mammoth)
	mammoth.docked_at = ""
	mammoth.rescuing = lost
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
	if tow_port != mammoth.base_port:
		home_seconds = mammoth.sailing_seconds(GameData.distance_nm(tow_port, mammoth.base_port), 1.0)
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
	_start_canal_leg(ship)


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
	var cost := amount * ship.full_repair_cost() * (1.0 - hub_bonus(ship.docked_at, "costs"))
	var paid := _spend(ship, cost, "repair")
	ship.stop_repair_cost += paid
	ship.maintenance = minf(ship.maintenance + amount * paid / cost, 1.0)


## Adds up to `amount` of fuel, as far as money allows.
func _refuel(ship: Ship, amount: float) -> void:
	amount = minf(amount, ship.fuel_tank() - ship.fuel)
	if amount <= 0.0:
		return
	var cost := amount * float(GameData.config.get("fuel_price", 0)) * (1.0 - hub_bonus(ship.docked_at, "costs"))
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
## as a whole: buying and selling ships, hub upgrades). Recovery boats pay for their own
## fuel and repairs.
func _record(ship: Ship, kind: String, amount: float) -> void:
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


## Company XP per minute over the last WINDOW_SECONDS (or the time played, if
## less), or 0 before any.
func recent_xp_per_minute() -> float:
	var minutes := minf(WINDOW_SECONDS, play_time) / 60.0
	return float(recent_finances().fleet.get("xp", 0.0)) / minutes if minutes > 0.0 else 0.0


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
			var costs := float(tally.get("fuel", 0.0)) + float(tally.get("repair", 0.0)) + float(tally.get("tolls", 0.0))
			ship_profit[ship_name] = float(ship_profit.get(ship_name, 0.0)) + float(tally.get("income", 0.0)) - costs
	return {fleet = fleet, ships = ship_profit}


# --- Saving --------------------------------------------------------------

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func new_game(new_company_name: String, new_home_port: String, new_color := "purple") -> void:
	company_name = new_company_name.strip_edges()
	company_color = new_color
	home_port = new_home_port
	money = int(GameData.config.get("starting_money", 10000))
	containers_delivered = 0
	_clear_ships()
	play_time = 0.0
	totals = {}
	canal_stats = {}
	_chamber_ships.clear()
	_chamber_lines.clear()
	company_xp = 0.0
	show_active_routes = true
	hubs.assign([Hub.new(home_port, true)])
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
	company_color = data.get("company_color", "purple")  # Saves from before colors: purple.
	home_port = data.get("home_port", "")
	money = int(data.get("money", 0))
	containers_delivered = int(data.get("containers_delivered", 0))
	_clear_ships()
	play_time = float(data.get("play_time", 0.0))
	totals = data.get("totals", {})
	canal_stats = data.get("canal_stats", {})
	# Saves from before XP: count the XP past deliveries would have earned.
	company_xp = float(data.get("company_xp", Progression.xp_for_payment(float(totals.get("income", 0.0)))))
	_window = data.get("finance_window", [])
	show_active_routes = bool(data.get("show_active_routes", true))
	hubs.clear()
	for hub_data: Dictionary in data.get("hubs", []):
		hubs.append(Hub.from_dict(hub_data))
	if hubs.is_empty():  # Saves from before hubs: the HQ at the home port.
		hubs.append(Hub.new(home_port, true))
	for ship_data: Dictionary in data.get("ships", []):
		ships.append(Ship.from_dict(ship_data))
	Ship.link_rescues(ships)
	_rebuild_canal_lines()
	for ship in ships:
		if ship.is_recovery() and ship.base_port.is_empty():  # Saves from before bases.
			ship.base_port = home_port
	_rebalance_recovery_boats()
	_begin_session()
	return ""


func save_game() -> void:
	if not in_session:
		return
	var data := {
		"version": SAVE_VERSION,
		"company_name": company_name,
		"company_color": company_color,
		"home_port": home_port,
		"money": money,
		"play_time": play_time,
		"company_xp": company_xp,
		"show_active_routes": show_active_routes,
		"hubs": hubs.map(func(hub: Hub) -> Dictionary: return hub.to_dict()),
		"totals": totals,
		"canal_stats": canal_stats,
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
	ships.clear()


func _begin_session() -> void:
	ActivityLog.clear()
	time_speed = 1
	in_session = true
	_autosave_timer.start()

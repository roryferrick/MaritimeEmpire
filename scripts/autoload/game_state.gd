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
## A ship sold its cargo at a port: what it was, how many units, what they cost
## to buy, what they sold for, and the canal tolls paid on the way.
signal cargo_sold(ship: Ship, port_id: String, commodity_id: String, quantity: int, cost: int, sale: int, tolls: int)
## A ship bought cargo at a port to sell at its next one (to_port).
signal cargo_loaded(ship: Ship, port_id: String, commodity_id: String, quantity: int, cost: int, to_port: String)
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
## A model got its mega upgrade.
signal mega_upgraded(model_id: String)
## A port grew or shrank into a new size band (see PortSizes).
signal port_band_changed(port_id: String, band: String, grew: bool)
## The fast-forward speed changed.
signal time_speed_changed(speed: int)

## Each save slot is its own file (see save_path()).
const SAVE_SLOTS := 3
## The one save from before slots; it becomes slot 1.
const LEGACY_SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 3
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
const MONEY_KINDS: Array[String] = ["income", "cargo", "fuel", "repair", "tolls", "bought", "sold", "hubs", "upgrades", "mega"]
## Order "Upgrade all" levels skills in, and breaks ties in.
const AUTO_UPGRADE_ORDER: Array[String] = ["speed", "efficiency", "durability"]
## Game speeds the top bar button cycles through (0 = paused).
const TIME_SPEEDS: Array[int] = [0, 1, 2, 4, 8]
## The hidden gem (click the company name): money it gives, once per company.
const HIDDEN_GEM_MONEY := 10000000
## How often (game seconds) a ship waiting in port for a full load looks again
## (it also looks as soon as the money reaches what it needed).
const LOAD_RECHECK_S := 2.0
## How often (game seconds) a ship at sea checks it can still make port (see
## _check_at_risk()); a breakdown or a new leg checks at once.
const AT_RISK_CHECK_S := 0.25
## How long (game seconds) a worked-out fuel_reserve() is used before it's redone.
const FUEL_RESERVE_REFRESH_S := 0.25

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
## Models whose first-purchase price (first_price in ship_models.json) has been used.
var first_prices_used: Array[String] = []
## Models with their mega upgrade (see mega_error()).
var mega_upgrades: Array[String] = []
## Whether the hidden gem has been claimed this run.
var hidden_gem_claimed := false
## New ships are delivered here.
var home_port := ""
var ships: Array[Ship] = []
var in_session := false
## The save slot (1 to SAVE_SLOTS) this session saves to.
var save_slot := 1
## Game speed: the world advances this many times per frame (0 = paused). Not
## saved; every session starts at 1x.
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
## Money cargo purchases leave in the bank (set on the Finances screen). Fuel
## and repairs can still use it, so no ship is stranded by it.
var bank_reserve := 0
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
## fuel_reserve(), and the play_time it was worked out at.
var _fuel_reserve := 0.0
var _fuel_reserve_time := -1.0
## Moves ships through canals: tolls, locks and convoys.
var canal_traffic := CanalTraffic.new(self)
## Commodity prices: drift and the impact of the player's own trades.
var market := Market.new(self)
## Port sizes: how they grow and shrink, and what they change.
var port_sizes := PortSizes.new(self)


func _ready() -> void:
	_autosave_timer.wait_time = float(GameData.config.get("autosave_seconds", 30))
	_autosave_timer.timeout.connect(save_game)
	add_child(_autosave_timer)
	_migrate_legacy_save()
	port_sizes.band_changed.connect(port_band_changed.emit)


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
	canal_traffic.step(delta)
	port_sizes.step(delta)
	for ship in ships:
		_advance(ship, delta)
	_roll_breakdowns(delta)
	_auto_recovery_clock += delta
	if _auto_recovery_clock >= AUTO_RECOVERY_INTERVAL:
		_auto_recovery_clock = 0.0
		_send_queued_recoveries()


## The calendar date and time now, as a Unix time (see game_config calendar).
func calendar_time() -> int:
	return calendar_time_at(play_time)


## The calendar date and time at a play time.
func calendar_time_at(at_play_time: float) -> int:
	var calendar: Dictionary = GameData.config.get("calendar", {})
	var start := Time.get_unix_time_from_datetime_string(str(calendar.get("start", "2000-01-01T00:00:00")))
	return int(start + at_play_time * calendar_seconds_per_second())


## Calendar seconds that pass per second of play (at 1x).
func calendar_seconds_per_second() -> float:
	return float(GameData.config.get("calendar", {}).get("minutes_per_second", 20)) * 60.0


## Steps to the next of TIME_SPEEDS, back to paused after the fastest.
func cycle_time_speed() -> void:
	time_speed = TIME_SPEEDS[(TIME_SPEEDS.find(time_speed) + 1) % TIME_SPEEDS.size()]


# --- Ships ---------------------------------------------------------------

## Buys a ship and launches it docked at port_id, which must be the HQ or a hub
## it can launch at (see can_launch_at(); the HQ if empty).
func buy_ship(model_id: String, ship_name: String, port_id := "") -> Ship:
	ship_name = ship_name.strip_edges()
	if port_id.is_empty():
		port_id = home_port
	var model := GameData.get_ship_model(model_id)
	if not buy_error(model_id).is_empty() or not ship_name_error(ship_name).is_empty() or not can_launch_at(model_id, port_id):
		return null
	var price := ship_price(model_id)
	if price < int(model.get("price", 0)):
		first_prices_used.append(model_id)
	money -= price
	_record(null, "bought", price)
	var ship := Ship.new(ship_name, model_id, port_id)
	ship.purchase_price = price
	ships.append(ship)
	if ship.is_recovery():
		ship.base_port = port_id
		_rebalance_recovery_boats()
	ships_changed.emit()
	save_game()
	return ship


func owned_count(model_id: String) -> int:
	return ships.filter(func(ship: Ship) -> bool: return ship.model_id == model_id).size()


## What the next ship of this model costs: its first_price if it has one and
## the company has never bought one (and owns none, for saves from before
## first prices), otherwise its price.
func ship_price(model_id: String) -> int:
	var model := GameData.get_ship_model(model_id)
	if model.has("first_price") and not first_prices_used.has(model_id) and owned_count(model_id) == 0:
		return int(model.first_price)
	return int(model.get("price", 0))


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
	if money < ship_price(model_id):
		return "You can't afford this ship."
	if not hubs.any(func(hub: Hub) -> bool: return can_launch_at(model_id, hub.port_id)):
		return "Your HQ and hubs are all too small to launch a %s, which needs a %s port." % [
			model.get("name", model_id), str(model.get("min_port", "")).capitalize()]
	return ""


## True once a model's mega upgrade is bought.
func has_mega(model_id: String) -> bool:
	return mega_upgrades.has(model_id)


## A model's mega upgrade: game_config mega.cost_factor x its price.
func mega_cost(model_id: String) -> int:
	return int(GameData.get_ship_model(model_id).get("price", 0)) * int(GameData.config.get("mega", {}).get("cost_factor", 80))


## What a model's mega upgrade does: "+50% speed and profit" for cargo ships,
## "+50% speed, -50% fuel" for recovery boats (from game_config mega).
func mega_effect(model_id: String) -> String:
	var settings: Dictionary = GameData.config.get("mega", {})
	var speed := roundi(float(settings.get("speed_bonus", 0.5)) * 100.0)
	if GameData.get_ship_model(model_id).get("recovery", false):
		return "+%d%% speed, -%d%% fuel" % [speed, roundi(float(settings.get("recovery_fuel_saving", 0.5)) * 100.0)]
	var profit := roundi(float(settings.get("profit_bonus", 0.5)) * 100.0)
	return "+%d%% speed and profit" % speed if profit == speed else "+%d%% speed, +%d%% profit" % [speed, profit]


## True when a model qualifies for its mega upgrade: all max_owned ships owned,
## every one at the top level, and not bought yet (it may still cost too much).
func mega_ready(model_id: String) -> bool:
	var model := GameData.get_ship_model(model_id)
	if has_mega(model_id):
		return false
	var line := ships.filter(func(ship: Ship) -> bool: return ship.model_id == model_id)
	return line.size() >= int(model.get("max_owned", 8)) and line.all(func(ship: Ship) -> bool: return ship.level() >= Progression.ship_max_level())


## Why the mega upgrade can't be bought now, or "".
func mega_error(model_id: String) -> String:
	var model := GameData.get_ship_model(model_id)
	if has_mega(model_id):
		return "Already upgraded."
	if not mega_ready(model_id):
		return "Own %d %s ships, all at level %d." % [int(model.get("max_owned", 8)), model.get("name", model_id), Progression.ship_max_level()]
	if money < mega_cost(model_id):
		return "You can't afford this (%s short)." % Fmt.money(mega_cost(model_id) - money)
	return ""


func buy_mega(model_id: String) -> void:
	if not mega_error(model_id).is_empty():
		return
	var cost := mega_cost(model_id)
	money -= cost
	_record(null, "mega", cost)
	mega_upgrades.append(model_id)
	mega_upgraded.emit(model_id)
	for ship in ships:
		if ship.model_id == model_id:
			ship.invalidate_stats()
			ship_changed.emit(ship)
	save_game()


## Adds HIDDEN_GEM_MONEY to the bank, the first time only.
func claim_hidden_gem() -> void:
	if hidden_gem_claimed:
		return
	hidden_gem_claimed = true
	money += HIDDEN_GEM_MONEY
	ActivityLog.add("You found a hidden gem: +%s" % Fmt.money(HIDDEN_GEM_MONEY), ActivityLog.Kind.GOOD)
	save_game()


func company_name_error(new_company_name: String) -> String:
	return "Enter a company name." if new_company_name.strip_edges().is_empty() else ""


## The company's color (or another color id's) as a Color (purple if the id
## isn't in the config).
func company_color_value(color_id := company_color) -> Color:
	for entry: Array in GameData.config.get("company_colors", []):
		if entry[0] == color_id:
			return Color.from_string(entry[2], Color.MEDIUM_PURPLE)
	return Color.from_string("#b67cf2", Color.MEDIUM_PURPLE)


func company_level() -> int:
	return int(Progression.company_level(company_xp).level)


## What a ship's next level of a skill costs: game_config skill_costs first
## share of the model's price, plus step more for each level the skill already
## has (10%, 15% ... 55% for the 10th).
func skill_cost(ship: Ship, skill: String) -> int:
	return _skill_price(ship.model(), int(ship.skills.get(skill, 0)))


## What a skill level costs for a model when the skill is at `level`.
func _skill_price(model: Dictionary, level: int) -> int:
	var settings: Dictionary = GameData.config.get("skill_costs", {})
	var share := float(settings.get("first", 0.1)) + float(settings.get("step", 0.05)) * level
	return roundi(float(model.get("price", 0)) * share)


## Why a ship can't take the next level of a skill now, or "".
func skill_error(ship: Ship, skill: String) -> String:
	if int(ship.skills.get(skill, 0)) >= Progression.skill_max_level():
		return "Maxed out."
	if ship.skill_points() <= 0:
		return "No upgrade points to spend."
	if money < skill_cost(ship, skill):
		return "You can't afford this (%s short)." % Fmt.money(skill_cost(ship, skill) - money)
	return ""


## Spends one of a ship's skill points on "speed", "durability" or
## "efficiency", paying skill_cost().
func level_skill(ship: Ship, skill: String) -> void:
	if not skill_error(ship, skill).is_empty():
		return
	_buy_skill(ship, skill)
	ship_changed.emit(ship)


func _buy_skill(ship: Ship, skill: String) -> void:
	var cost := skill_cost(ship, skill)
	money -= cost
	_record(null, "upgrades", cost)
	ship.skills[skill] = int(ship.skills[skill]) + 1
	ship.invalidate_stats()


## Every unspent skill point in the fleet as [cost, ship, skill], cheapest
## first. Each ship's points go round-robin to its lowest skill (ties broken in
## AUTO_UPGRADE_ORDER: speed 1, efficiency 1, durability 1, speed 2...), which is
## also its cheapest, so buying in this order keeps every ship's order.
func _upgrade_plan() -> Array:
	var plan := []
	for ship in ships:
		var levels := ship.skills.duplicate()
		for point in ship.skill_points():
			var best := ""
			for skill in AUTO_UPGRADE_ORDER:
				if int(levels[skill]) < Progression.skill_max_level() and (best.is_empty() or int(levels[skill]) < int(levels[best])):
					best = skill
			if best.is_empty():
				break
			plan.append([_skill_price(ship.model(), int(levels[best])), ship, best])
			levels[best] = int(levels[best]) + 1
	plan.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return plan


## What spending every unspent skill point would cost.
func upgrade_all_cost() -> int:
	var total := 0
	for entry: Array in _upgrade_plan():
		total += int(entry[0])
	return total


## The cheapest unspent upgrade in the fleet, or 0 if there's none.
func cheapest_upgrade_cost() -> int:
	var plan := _upgrade_plan()
	return int(plan[0][0]) if not plan.is_empty() else 0


## Buys the fleet's unspent upgrades, cheapest first (see _upgrade_plan()), for
## as long as the money lasts without dipping into the bank_reserve. Returns
## how many were bought.
func upgrade_all() -> int:
	var bought := 0
	var changed := {}
	for entry: Array in _upgrade_plan():
		if money - int(entry[0]) < bank_reserve:
			break
		_buy_skill(entry[1], entry[2])
		changed[entry[1]] = true
		bought += 1
	for ship: Ship in changed:
		ship_changed.emit(ship)
	return bought


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
## re-based boat sails there once it's free. A model too big for the St.
## Lawrence Seaway is never based at a Great Lakes hub.
func _rebalance_recovery_boats() -> void:
	var models := {}
	for ship in ships:
		if ship.is_recovery():
			models.get_or_add(ship.model_id, []).append(ship)
	for boats: Array in models.values():
		var model: Dictionary = boats[0].model()
		var ports := hubs.map(func(hub: Hub) -> String: return hub.port_id).filter(func(port: String) -> bool:
			return bool(model.get("seaway", false)) or not GameData.get_port(port).get("seaway", false))
		if ports.is_empty():
			continue
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


## Why a ship name can't be used, or "" if it's fine (renaming_ship may keep its
## own name, in a different case).
func ship_name_error(ship_name: String, renaming_ship: Ship = null) -> String:
	ship_name = ship_name.strip_edges()
	if ship_name.is_empty():
		return "Enter a name."
	for ship in ships:
		if ship != renaming_ship and ship.name.nocasecmp_to(ship_name) == 0:
			return "You already have a ship called %s." % ship.name
	return ""



## Renames a ship, carrying its recent finances over to the new name. Returns
## why it couldn't, or "".
func rename_ship(ship: Ship, new_name: String) -> String:
	new_name = new_name.strip_edges().left(MAX_NAME_LENGTH)
	var error := ship_name_error(new_name, ship)
	if not error.is_empty() or new_name == ship.name:
		return error
	for bucket: Dictionary in _window:
		if bucket.ships.has(ship.name):
			bucket.ships[new_name] = bucket.ships[ship.name]
			bucket.ships.erase(ship.name)
	ship.name = new_name
	ship_changed.emit(ship)
	save_game()
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


## A port's size as shown: "Medium 29".
func port_size_text(port_id: String) -> String:
	return "%s %d" % [port_sizes.band(port_id).capitalize(), port_sizes.level(port_id)]


## "Taipei (Small 11) is too small for a Dominator, which needs a Large port."
func port_size_error(model: Dictionary, port_id: String) -> String:
	return "%s (%s) is too small for a %s, which needs a %s port." % [GameData.port_name(port_id),
		port_size_text(port_id), model.get("name", ""),
		str(model.get("min_port", "")).capitalize()]


## Whether a new ship of this model can be launched at a port (the HQ or a
## hub): big enough for it, and not on the Great Lakes if it's too big for the Seaway.
func can_launch_at(model_id: String, port_id: String) -> bool:
	var model := GameData.get_ship_model(model_id)
	var too_big_for_seaway: bool = not model.get("seaway", false) and GameData.get_port(port_id).get("seaway", false)
	return hub_at(port_id) != null and not too_big_for_seaway and port_sizes.fits(model, port_id)


func _range_error(ship: Ship, from: String, to: String) -> String:
	if not ship.fits_port(to):
		return port_size_error(ship.model(), to)
	if not ship.fits_lane(from, to):
		return "%s is on the Great Lakes, and a %s is too big for the St. Lawrence Seaway." % [
			GameData.port_name(to if GameData.get_port(to).get("seaway", false) else from), ship.model().get("name", "")]
	if GameData.distance_nm(from, to) <= ship.range_nm():
		return "%s to %s is too far for one tank with the slow canal stretches and rough seas on the way." % [
			GameData.port_name(from), GameData.port_name(to)]
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


func set_full_loads(ship: Ship, on: bool) -> void:
	ship.full_loads = on
	ship.load_check_time = 0.0  # Act on it at once rather than at the next look.
	ship_changed.emit(ship)


func set_bank_reserve(amount: int) -> void:
	bank_reserve = maxi(amount, 0)


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
	# A ship waiting in port for a full load, not due another look: nothing to do.
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and money < ship.load_need and ship.is_docked():
		return
	if ship.is_on_job():
		_advance_job(ship, delta)
	elif ship.is_docked():
		_advance_docked(ship, delta)
	elif not ship.is_lost() and _sail(ship, delta) and ship.traveled_nm >= ship.leg_length():
		_arrive(ship, ship.to_port)


## Wears, burns fuel and moves a ship along its current lane. Returns false if
## the ship ran out of fuel or maintenance and is now lost at sea. Mammoths
## only set off when they can finish, so they're never lost. Speed and wear
## follow the lane's zones (slower in convoy canals, faster wear in rough seas).
## A ship held in a canal (see CanalTraffic) stays put with its engines off, and
## one slowed by the ship ahead burns fuel and wears only for the distance it
## makes, so the fuel it set off with always covers the leg.
func _sail(ship: Ship, delta: float) -> bool:
	if canal_traffic.hold(ship, delta):
		return true
	var zone := ship.zone_factors(ship.traveled_nm)
	var speed := ship.speed()
	if ship.is_recovery():
		speed = maxf(speed, ship.top_speed() * MIN_RECOVERY_SPEED_FACTOR)
	speed *= float(zone[0])
	var target := canal_traffic.limit(ship, ship.traveled_nm + speed * delta)
	var effort := clampf((target - ship.traveled_nm) / (speed * delta), 0.0, 1.0) if speed * delta > 0.0 else 1.0
	if ship.is_running() or ship.is_recovery():
		ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * float(zone[1]) * delta * effort, 0.0)
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * delta * effort, 0.0)
	ship.traveled_nm = target
	if not ship.is_recovery():
		ship.sea_time += delta * effort
		if ship.fuel <= 0.0:
			_lose(ship, "out of fuel")
			return false
		if ship.maintenance <= 0.0:
			_lose(ship, "broken down")
			return false
		if play_time >= ship.risk_check_time:
			ship.risk_check_time = play_time + AT_RISK_CHECK_S
			_check_at_risk(ship)
	return true


## Flags a ship that no longer has the fuel (or maintenance) to finish its leg.
func _check_at_risk(ship: Ship) -> void:
	var seconds := ship.leg_seconds(ship.from_port, ship.to_port, ship.traveled_nm, ship.leg_length(), ship.maintenance)
	var at_risk := ship.fuel < ship.fuel_per_s() * seconds
	if at_risk == ship.at_risk:
		return
	ship.at_risk = at_risk
	if at_risk:
		ship_at_risk.emit(ship)
	ship_changed.emit(ship)


func _lose(ship: Ship, reason: String) -> void:
	canal_traffic.leave(ship)
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
			if ship.is_recovery() or ship.is_docked() or ship.is_lost() or canal_traffic.in_canal(ship) or randf() >= ship.breakdown_chance():
				continue
			ship.maintenance = maxf(ship.maintenance - float(settings.get("hit", 0.5)), 0.0)
			ship.risk_check_time = 0.0  # Check at once whether it can still make port.
			ship_broke_down.emit(ship)
			if ship.maintenance <= 0.0:
				_lose(ship, "broken down")


func _arrive(ship: Ship, port: String, paid := true) -> void:
	ship.at_risk = false
	canal_traffic.leave(ship)
	ship.delivery_canals.clear()
	if paid and not ship.is_recovery():
		ship.delivery_canals.assign(ship.canals_entered)
	ship.stop_toll = ship.leg_toll
	ship.leg_toll = 0
	ship.canals_entered.clear()
	# The cargo sells here, at this port's price, when unloading finishes; the
	# leg's bonuses and the hub's Pay upgrade add to a profitable trade's profit.
	# XP counts the leg it came, none if a recovery boat carried it back.
	ship.cargo_payment = 0
	ship.cargo_leg_nm = 0.0
	if not ship.cargo_id.is_empty():
		var sale := ship.cargo_qty * market.sell_price(port, ship.cargo_id)
		ship.cargo_payment = roundi(sale + trade_bonus(ship.from_port, port, sale - ship.cargo_cost, ship.model_id))
		ship.cargo_leg_nm = GameData.distance_nm(ship.from_port, port) if paid and ship.from_port != port else 0.0
	ship.unloaded = ship.is_recovery()
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
	ship.stop_cost = 0
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


## Halfway through a stop: sells the cargo it brought (if any), then loads its
## next one for where it's going (if it's running a route).
func _unload(ship: Ship) -> void:
	ship.unloaded = true
	if not ship.cargo_id.is_empty():
		_sell_cargo(ship)
	if ship.is_running():
		_load_cargo(ship, ship.route[ship.next_route_index()])
	ship_changed.emit(ship)


func _sell_cargo(ship: Ship) -> void:
	var commodity := GameData.commodity(ship.cargo_id)
	ship.stop_sale = ship.cargo_payment
	ship.stop_cost = ship.cargo_cost
	money += ship.cargo_payment
	_record(ship, "income", ship.cargo_payment)
	market.trade(ship.docked_at, ship.cargo_id, ship.cargo_payment, false)
	port_sizes.add_traffic(ship.docked_at, ship.cargo_payment)
	if commodity.get("unit", "") == "container":
		containers_delivered += ship.cargo_qty
	cargo_sold.emit(ship, ship.docked_at, ship.cargo_id, ship.cargo_qty, ship.cargo_cost, ship.cargo_payment, ship.stop_toll)
	var hub := hub_at(ship.docked_at)
	var xp := Progression.xp_for_cargo(ship.cargo_qty, ship.cargo_id, ship.cargo_leg_nm)
	# Cargo that came through canals earns their XP bonuses on top of the hub's.
	var canal_bonus := 0.0
	for canal_id in ship.delivery_canals:
		var canal := GameData.get_canal(canal_id)
		var bonus := float(canal.get("xp_bonus", 0.0))
		canal_bonus += bonus
		if bonus > 0.0:
			var stats: Dictionary = canal_stats.get_or_add(canal_id, {crossings = 0, tolls = 0.0, xp = 0.0})
			stats.xp = float(stats.xp) + xp * bonus
	ship.delivery_canals.clear()
	_gain_xp(ship, xp, 1.0 + (hub.bonus("xp") if hub else 0.0) + canal_bonus,
		1.0 + (hub.company_xp_bonus() if hub else 0.0) + canal_bonus)
	if hub:
		hub.deliveries += 1
		hub.income += ship.cargo_payment
		_gain_hub_xp(hub, xp * (1.0 + canal_bonus))
	ship.cargo_id = ""
	ship.cargo_qty = 0
	ship.cargo_cost = 0
	ship.cargo_payment = 0


## Buys the most profitable cargo the ship can carry to its next port (see
## Market.best_cargo()): a full hold (less what a canal makes it leave behind),
## or as much as the money allows while keeping the fleet's fuel reserve (see
## fuel_reserve()) and the bank_reserve, unless full loads are on, when it buys
## nothing short of a full hold. Nothing if no cargo makes a profit. A full load
## taken out of a hub by a ship that arrived empty gives the hub XP.
## Returns the cargo it chose (bought or not, for lack of money), or "" if none pays.
func _load_cargo(ship: Ship, to: String) -> String:
	if ship.is_recovery() or not ship.cargo_id.is_empty() or not ship.is_docked() or to.is_empty() or to == ship.docked_at:
		return ""
	var best := market.best_cargo(ship.model(), ship.docked_at, to)
	if best[0] == "":
		return ""
	var price := market.buy_price(ship.docked_at, best[0])
	var fuel_reserve := fuel_reserve()
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())))
	var quantity := mini(room, floori((float(money) - ship.bill - fuel_reserve - bank_reserve) / price))
	if quantity <= 0 or (ship.full_loads and quantity < room):
		# What a full hold would need in the bank, for ships waiting for one.
		ship.load_need = roundi(room * price + ship.bill + fuel_reserve + bank_reserve)
		return best[0]
	var cost := roundi(quantity * price)
	money -= cost
	_record(ship, "cargo", cost)
	market.trade(ship.docked_at, best[0], cost, true)
	port_sizes.add_traffic(ship.docked_at, cost)
	ship.cargo_id = best[0]
	ship.cargo_from = ship.docked_at
	ship.cargo_qty = quantity
	ship.cargo_cost = cost
	cargo_loaded.emit(ship, ship.docked_at, best[0], quantity, cost, to)
	# A ship that came in empty and leaves with a full hold (a one-way route out of
	# a hub) earns the hub the XP the load will earn where it's delivered.
	var hub := hub_at(ship.docked_at)
	if hub and ship.stop_sale == 0 and quantity >= room:
		_gain_hub_xp(hub, Progression.xp_for_cargo(quantity, best[0], GameData.distance_nm(ship.docked_at, to)))
	ship_changed.emit(ship)
	return best[0]


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
	# Waiting for a full load, and not due another look (see _waiting_for_load()).
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and money < ship.load_need:
		return
	if not ship.fits_port(to):
		_set_hold(ship, "%s is too small for this ship; assign a new route" % GameData.port_name(to))
		return
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
			if not ship.fits_lane(ship.docked_at, to):
				_set_hold(ship, "%s is on the Great Lakes, and this ship is too big for the Seaway; assign a new route" % destination)
			elif not ship.can_reach(ship.docked_at, to):
				_set_hold(ship, "%s is beyond this ship's range; assign a new route" % destination)
			elif need > ship.fuel_tank():
				_set_hold(ship, "too worn to reach %s on a full tank%s" % [destination,
					", waiting for money to repair" if ship.auto_repair else "; turn on repair"])
			elif not ship.auto_refuel:
				_set_hold(ship, "not enough fuel for %s; turn on refuel" % destination)
			else:
				_set_hold(ship, "waiting for money to buy fuel for %s" % destination)
			return
	if _waiting_for_load(ship, to):
		return
	_set_hold(ship, "")
	_depart(ship, to)


## With full loads on, a cargo ship with an empty hold stays in port until it
## can buy a full one (see _load_cargo()), saying why in its load_wait. A leg
## where no cargo makes a profit is sailed empty straight away.
func _waiting_for_load(ship: Ship, to: String) -> bool:
	if ship.is_recovery() or not ship.full_loads or not ship.cargo_id.is_empty():
		_set_load_wait(ship, "")
		return false
	# Already waiting: look again as soon as the money reaches what a full hold
	# needed, and otherwise only every LOAD_RECHECK_S (prices drift slowly).
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and money < ship.load_need:
		return true
	ship.load_check_time = play_time + LOAD_RECHECK_S
	if _load_cargo(ship, to).is_empty() or not ship.cargo_id.is_empty():
		_set_load_wait(ship, "")
		return false
	_set_hold(ship, "")
	var reason := "waiting for money for a full load to %s" % GameData.port_name(to)
	if bank_reserve > 0:
		reason += " (keeping %s in the bank)" % Fmt.money(bank_reserve)
	_set_load_wait(ship, reason)
	return true


func _set_load_wait(ship: Ship, reason: String) -> void:
	if ship.load_wait != reason:
		ship.load_wait = reason
		ship_changed.emit(ship)


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
		_load_cargo(ship, to)  # If it didn't load when unloading (a new ship, or a new route).
	_leave_port(ship)
	ship.from_port = ship.docked_at
	ship.to_port = to
	ship.risk_check_time = 0.0
	ship.traveled_nm = 0.0
	ship.docked_at = ""
	canal_traffic.start_leg(ship)
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
	ship.load_wait = ""


# --- Canals ----------------------------------------------------------------

## Extra money on a profitable trade from a leg's bonuses: the profit x (the
## leg's sale factor (rough seas, upper lakes) x the destination hub's Pay
## upgrade x the model's mega upgrade, if it has one - 1). Nothing on a loss.
func trade_bonus(from_port: String, to_port: String, profit: float, model_id := "") -> float:
	if profit <= 0.0:
		return 0.0
	var mega := 1.0 + (float(GameData.config.get("mega", {}).get("profit_bonus", 0.5)) if has_mega(model_id) else 0.0)
	return profit * (GameData.sale_factor(from_port, to_port) * (1.0 + hub_bonus(to_port, "pay")) * mega - 1.0)


## Money cargo purchases leave alone so no ship is stranded for fuel: what
## topping up every ship's tank would cost at the port it's at or heading to (a
## cargo ship at sea counting the fuel it will burn to get there). A buffer, so
## it's worked out at most every FUEL_RESERVE_REFRESH_S of game time: with a big
## fleet it's costly, and ships buying cargo ask for it many times a second.
func fuel_reserve() -> float:
	if _fuel_reserve_time >= 0.0 and play_time >= _fuel_reserve_time and play_time - _fuel_reserve_time < FUEL_RESERVE_REFRESH_S:
		return _fuel_reserve
	var total := 0.0
	for ship in ships:
		var port := ship.docked_at if ship.is_docked() else ship.to_port
		if port.is_empty():
			continue
		var fuel_left := ship.fuel
		if not ship.is_docked() and not ship.is_recovery() and not ship.from_port.is_empty():
			var seconds := ship.leg_seconds(ship.from_port, ship.to_port, ship.traveled_nm, ship.leg_length(), ship.maintenance)
			fuel_left -= ship.fuel_per_s() * seconds
		total += clampf(ship.fuel_tank() - fuel_left, 0.0, ship.fuel_tank()) * market.fuel_price(port)
	_fuel_reserve = total
	_fuel_reserve_time = play_time
	return total


## A canal's toll for a ship: its toll_share of what the ship's cargo will sell
## for at the end of the leg (nothing for an empty ship).
func cargo_toll(ship: Ship, canal: Dictionary) -> int:
	if ship.cargo_id.is_empty():
		return 0
	var value := ship.cargo_qty * market.sell_price(ship.to_port, ship.cargo_id)
	return roundi(value * float(canal.get("toll_share", 0.0)))


## Charges a canal toll to a ship's ledger and the finances.
func record_toll(ship: Ship, canal: Dictionary, toll: int) -> void:
	_record(ship, "tolls", toll)
	var stats: Dictionary = canal_stats.get_or_add(canal.id, {crossings = 0, tolls = 0.0, xp = 0.0})
	stats.crossings = int(stats.crossings) + 1
	stats.tolls = float(stats.tolls) + toll


# --- Recovery --------------------------------------------------------------

## How the nearest free recovery boat able to carry a lost ship (the cheapest,
## if two are as near) would recover it: {mammoth, segments, tow_port, approach_nm, seconds, fuel, cost}, or
## {error} saying why none can.
func recovery_plan(lost: Ship) -> Dictionary:
	if not lost.is_lost() or lost.rescuer != null:
		return {error = "This ship doesn't need recovering."}
	var capable := ships.filter(func(ship: Ship) -> bool:
		return ship.can_carry(lost) and ship.fits_lane(lost.from_port, lost.to_port))
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
	mammoth.job_nm = 0.0
	for segment: Array in plan.segments:
		mammoth.job_nm += float(segment[3]) - float(segment[2])
	mammoth.carry_nm = float(plan.segments[-1][3]) - float(plan.segments[-1][2])
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
		cost = mammoth.fuel_per_s() * running * market.fuel_price(mammoth.docked_at)
			+ minf(mammoth.wear_per_s() * running, 1.0) * mammoth.full_repair_cost() * port_sizes.cost_factor(mammoth.docked_at),
	}


func _start_segment(ship: Ship, segment: Array) -> void:
	ship.from_port = segment[0]
	ship.to_port = segment[1]
	ship.traveled_nm = segment[2]
	ship.segment_end = segment[3]
	canal_traffic.start_leg(ship)


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
	_gain_recovery_xp(mammoth, lost)


## A finished recovery: the boat earns game_config recovery_xp.per_nm for every
## mile of the job, and the company company_share of what the rescued ship's
## full hold would earn over the miles it was carried.
func _gain_recovery_xp(mammoth: Ship, lost: Ship) -> void:
	var settings: Dictionary = GameData.config.get("recovery_xp", {})
	var cargo: Array = lost.model().get("cargo", [])
	var company := 0.0
	if not cargo.is_empty():
		company = Progression.xp_for_cargo(lost.capacity(), cargo[0], mammoth.carry_nm) * float(settings.get("company_share", 1.0))
	var boat := mammoth.job_nm * float(settings.get("per_nm", 1.0))
	if boat > 0.0:
		_gain_xp(mammoth, boat, 1.0, company / boat)  # The company's XP as a multiple of the boat's.
	mammoth.job_nm = 0.0
	mammoth.carry_nm = 0.0


## Restores up to `amount` of maintenance, as far as money allows.
func _repair(ship: Ship, amount: float) -> void:
	amount = minf(amount, 1.0 - ship.maintenance)
	if amount <= 0.0:
		return
	var cost := amount * ship.full_repair_cost() * port_sizes.cost_factor(ship.docked_at) * (1.0 - hub_bonus(ship.docked_at, "costs"))
	var paid := _spend(ship, cost, "repair")
	ship.stop_repair_cost += paid
	ship.maintenance = minf(ship.maintenance + amount * paid / cost, 1.0)


## Adds up to `amount` of fuel, as far as money allows.
func _refuel(ship: Ship, amount: float) -> void:
	amount = minf(amount, ship.fuel_tank() - ship.fuel)
	if amount <= 0.0:
		return
	var cost := amount * market.fuel_price(ship.docked_at) * (1.0 - hub_bonus(ship.docked_at, "costs"))
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
			var costs := float(tally.get("fuel", 0.0)) + float(tally.get("repair", 0.0)) + float(tally.get("tolls", 0.0)) + float(tally.get("cargo", 0.0))
			ship_profit[ship_name] = float(ship_profit.get(ship_name, 0.0)) + float(tally.get("income", 0.0)) - costs
	return {fleet = fleet, ships = ship_profit}


# --- Saving --------------------------------------------------------------

func save_path(slot: int) -> String:
	return "user://save_%d.json" % slot


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(save_path(slot))


## What the main menu shows for a slot: {company_name, company_color, money,
## date (calendar Unix time)}, plus error if it can't be loaded; {} if empty.
func save_summary(slot: int) -> Dictionary:
	if not has_save(slot):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot)))
	if typeof(data) != TYPE_DICTIONARY:
		return {error = "Unreadable save"}
	var summary := {
		company_name = str(data.get("company_name", "")),
		company_color = str(data.get("company_color", "purple")),
		money = int(data.get("money", 0)),
		date = calendar_time_at(float(data.get("play_time", 0.0))),
	}
	if int(data.get("version", 0)) != SAVE_VERSION:
		summary.error = "Old save, can't be loaded"
	return summary


func delete_save(slot: int) -> void:
	DirAccess.remove_absolute(save_path(slot))


## The single save from before slots moves into slot 1.
func _migrate_legacy_save() -> void:
	if FileAccess.file_exists(LEGACY_SAVE_PATH) and not has_save(1):
		DirAccess.rename_absolute(LEGACY_SAVE_PATH, save_path(1))


## Starts a new company in save_slot, replacing any save there.
func new_game(new_company_name: String, new_home_port: String, new_color := "purple") -> void:
	company_name = new_company_name.strip_edges()
	company_color = new_color
	home_port = new_home_port
	money = int(GameData.config.get("starting_money", 10000))
	containers_delivered = 0
	first_prices_used = []
	mega_upgrades = []
	hidden_gem_claimed = false
	_clear_ships()
	play_time = 0.0
	totals = {}
	canal_stats = {}
	canal_traffic.clear()
	market.clear()
	port_sizes.reset()
	company_xp = 0.0
	show_active_routes = true
	bank_reserve = 0
	hubs.assign([Hub.new(home_port, true)])
	_window = []
	_begin_session()
	save_game()


## Loads a slot's save and starts a session saving to it. Returns why it
## couldn't, or "".
func continue_game(slot: int) -> String:
	var path := save_path(slot)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameState: save file %s is missing or corrupt" % path)
		return "The saved game could not be read."
	if int(data.get("version", 0)) != SAVE_VERSION:
		return "This save is from before commodity trading and can't be loaded. Delete it to start a new game in this slot."
	save_slot = slot
	company_name = data.get("company_name", "")
	company_color = data.get("company_color", "purple")  # Saves from before colors: purple.
	home_port = data.get("home_port", "")
	money = int(data.get("money", 0))
	containers_delivered = int(data.get("containers_delivered", 0))
	first_prices_used.assign(data.get("first_prices_used", []))
	mega_upgrades.assign(data.get("mega_upgrades", []))
	hidden_gem_claimed = bool(data.get("hidden_gem_claimed", false))
	_clear_ships()
	play_time = float(data.get("play_time", 0.0))
	totals = data.get("totals", {})
	canal_stats = data.get("canal_stats", {})
	market.from_dict(data.get("market", {}))
	var had_port_sizes := port_sizes.from_dict(data.get("port_sizes", {}))
	# Saves from before XP: count the XP past deliveries would have earned.
	company_xp = float(data.get("company_xp", 0.0))
	_window = data.get("finance_window", [])
	show_active_routes = bool(data.get("show_active_routes", true))
	bank_reserve = int(data.get("bank_reserve", 0))
	hubs.clear()
	for hub_data: Dictionary in data.get("hubs", []):
		hubs.append(Hub.from_dict(hub_data))
	if hubs.is_empty():  # Saves from before hubs: the HQ at the home port.
		hubs.append(Hub.new(home_port, true))
	for ship_data: Dictionary in data.get("ships", []):
		ships.append(Ship.from_dict(ship_data))
	Ship.link_rescues(ships)
	for ship in ships:
		ship.invalidate_stats()  # Skills and mega upgrades are all loaded now.
	canal_traffic.rebuild(ships)
	for ship in ships:
		if ship.is_recovery() and ship.base_port.is_empty():  # Saves from before bases.
			ship.base_port = home_port
	if not had_port_sizes:
		_fit_ports_to_routes()
	_rebalance_recovery_boats()
	_begin_session()
	return ""


## Saves from before port sizes: every port a ship is at, sailing between or
## routed through is raised just enough for it (as if the fleet's traffic had
## already grown it), so no ship is held by the new size limits.
func _fit_ports_to_routes() -> void:
	for ship in ships:
		var needs := str(ship.model().get("min_port", ""))
		if needs.is_empty():
			continue
		var ports: Array[String] = []
		ports.append_array(ship.route)
		ports.append_array(ship.pending_route)
		ports.append_array([ship.docked_at, ship.from_port, ship.to_port])
		for port_id in ports:
			if not port_id.is_empty():
				port_sizes.raise_to(port_id, port_sizes.band_min(needs))


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
		"bank_reserve": bank_reserve,
		"hubs": hubs.map(func(hub: Hub) -> Dictionary: return hub.to_dict()),
		"totals": totals,
		"canal_stats": canal_stats,
		"market": market.to_dict(),
		"port_sizes": port_sizes.to_dict(),
		"finance_window": _window,
		"containers_delivered": containers_delivered,
		"first_prices_used": first_prices_used,
		"mega_upgrades": mega_upgrades,
		"hidden_gem_claimed": hidden_gem_claimed,
		"ships": ships.map(func(ship: Ship) -> Dictionary: return ship.to_dict()),
	}
	var file := FileAccess.open(save_path(save_slot), FileAccess.WRITE)
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

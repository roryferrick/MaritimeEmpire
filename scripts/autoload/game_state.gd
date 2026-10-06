extends Node
## State of the running game session: money, ships and their movement, plus
## saving and loading.
##
## The world only advances while a session is open. The game saves on quit
## and on a timer; nothing happens while the game is closed.

signal money_changed(money: int)
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
## Game speeds the top bar button cycles through (0 = paused).
const TIME_SPEEDS: Array[int] = [0, 1, 2, 4, 8]
## The hidden gem (click the company name): money it gives, once per company.
const HIDDEN_GEM_MONEY := 10000000
## How often (game seconds) a ship waiting in port for a full load looks again
## (it also looks as soon as the money reaches what it needed).
const LOAD_RECHECK_S := 2.0
## How often (game seconds) a ship at sea checks it can still make port (see
## _check_at_risk()); a breakdown or a new leg checks at once.
const AT_RISK_CHECK_S := 1.0
## A ship bound for a port a storm has closed waits this far off it.
const STORM_OFFSHORE_NM := 25.0
## How often storm warnings are looked for, and how far ahead (in seconds of
## play: two calendar days) a storm heading for a port is warned of.
const STORM_WARNING_CHECK_S := 1.0
const STORM_WARNING_AHEAD_S := 144.0
## A ship is said to be sailing through a storm once it's this strong there.
const STORM_SHIP_NOTICE := 0.3
## How long (game seconds) a worked-out fuel_reserve() is used before it's redone.
const FUEL_RESERVE_REFRESH_S := 3.0
## How often (seconds of play) the season warnings look again at which ports,
## canals and Arctic routes the player uses.
const PLAYER_USE_REFRESH_S := 10.0
## How often (seconds of play) a ship at sea looks again at the storms and ice
## where it is.
const STORM_FACTOR_REFRESH_S := 0.25
## How often (seconds of play) a docking ship is repaired and refueled (and
## pays for it).
const REFILL_BILL_S := 0.25
## Seconds between tugs leaving port on the same job, so they head out in line.
const TUG_STAGGER_S := 1.5

## Every company in the game (one in single player; see Company), and the one
## this player controls. The money, hubs, company_xp... below are its: the
## screens use those, while the sim works with each ship's own company.
var companies: Array[Company] = []
var company := Company.new()

var money: int:
	get: return company.money
	set(value):
		company.money = value
		money_changed.emit(value)
var delivered: Dictionary:
	get: return company.delivered
	set(value): company.delivered = value
var earlier_containers: int:
	get: return company.earlier_containers
	set(value): company.earlier_containers = value
var company_name: String:
	get: return company.name
	set(value): company.name = value
var company_color: String:
	get: return company.color
	set(value): company.color = value
var first_prices_used: Array[String]:
	get: return company.first_prices_used
var mega_upgrades: Array[String]:
	get: return company.mega_upgrades
var hidden_gem_claimed: bool:
	get: return company.hidden_gem_claimed
	set(value): company.hidden_gem_claimed = value
var home_port: String:
	get: return company.home_port
	set(value): company.home_port = value
var company_xp: float:
	get: return company.xp
	set(value): company.xp = value
var show_active_routes: bool:
	get: return company.show_active_routes
	set(value): company.show_active_routes = value
var muted_models: Array[String]:
	get: return company.muted_models
var activity_collapsed: bool:
	get: return company.activity_collapsed
	set(value): company.activity_collapsed = value
var tutorials: bool:
	get: return company.tutorials
	set(value): company.tutorials = value
var tutorials_on: bool:
	get: return company.tutorials_on
	set(value): company.tutorials_on = value
var tutorial_done: Array[String]:
	get: return company.tutorial_done
var bank_reserve: int:
	get: return company.bank_reserve
	set(value): company.bank_reserve = value
var hubs: Array[Hub]:
	get: return company.hubs
var totals: Dictionary:
	get: return company.totals
	set(value): company.totals = value
var canal_stats: Dictionary:
	get: return company.canal_stats
	set(value): company.canal_stats = value

var ships: Array[Ship] = []
## The id the next ship bought gets (see Ship.id).
var next_ship_id := 1
var in_session := false
## The save slot (1 to SAVE_SLOTS) this session saves to.
var save_slot := 1
## Whether save_slot is one of the multiplayer slots (kept apart from the
## single player ones, and played solo until hosting is built).
var multiplayer_save := false
## Game speed: the world advances this many times per frame (0 = paused). Not
## saved; every session starts at 1x.
var time_speed := 1:
	set(value):
		if Net.is_client() and not Net.syncing:
			return  # Only the host sets the speed; it comes with its updates.
		if value == 0 and time_speed > 0:
			_resume_speed = time_speed  # What Space (toggle_pause()) carries on at.
		time_speed = mini(value, max_time_speed)
		time_speed_changed.emit(time_speed)
## The speed the game was paused from (see toggle_pause()).
var _resume_speed := 1

## The fastest game speed this save allows (one of TIME_SPEEDS, chosen when
## the company is founded; saves from before the choice allow the fastest).
var max_time_speed: int = TIME_SPEEDS[-1]
## How stormy this save is (Weather.LEVELS: none, moderate or harsh) and
## whether it has seasonal closures; both chosen when the company is founded.
var storms := "none"
var seasons := false

## Seconds the company has been playing (only counts while a session is open).
var play_time := 0.0
## The calendar's start (Unix time) and calendar seconds per second of play,
## read from game_config once (-1 until then).
var _calendar_start := -1
var _calendar_rate := 0.0

var _autosave_timer := Timer.new()
var _breakdown_clock := 0.0
var _auto_recovery_clock := 0.0
var _storm_warning_clock := 0.0
## Storm warnings already given: port id -> the storm closing it; "storm/port"
## keys for storms heading for a port; ship -> the storm it's sailing through.
var _closed_ports := {}
var _storm_warned := {}
var _ships_in_storms := {}
## Seasonal closures and ice zones: id -> whether in season when last looked
## (to log changes), and the ids of closures already warned of ahead.
var _season_closed := {}
var _season_warned := {}
## For the season warnings: the ports, canals and Arctic routes the player uses
## ({ports, canals, zones: ice zone id -> touches one of the ports}), and when
## they were worked out (play_time).
var _player_use := {}
var _player_use_time := 0.0
## Moves ships through canals: tolls, locks and convoys.
var canal_traffic := CanalTraffic.new(self)
## Commodity prices: drift and the impact of the player's own trades.
var market := Market.new(self)
var weather := Weather.new(self)
var seasonal := Seasons.new(self)
var icebreaking := Icebreaking.new(self)
## Port sizes: how they grow and shrink, and what they change.
var port_sizes := PortSizes.new(self)
## Every port's berths and queue (see Docks).
var docks := Docks.new(self)


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
	if Net.is_client():
		_client_frame(delta)  # The host runs the world.
		return
	# Fast forward runs whole extra steps rather than one longer one, so ships
	# arrive, dock and break down exactly as they would at 1x.
	for step in time_speed:
		_step(delta)


func _step(delta: float) -> void:
	play_time += delta
	canal_traffic.step(delta)
	port_sizes.step(delta)
	weather.step(delta)
	icebreaking.refresh()
	for ship in ships:
		_advance(ship, delta)
	_roll_breakdowns(delta)
	_storm_warning_clock += delta
	if _storm_warning_clock >= STORM_WARNING_CHECK_S:
		_storm_warning_clock = 0.0
		_storm_warnings()
		_season_warnings()
	_auto_recovery_clock += delta
	if _auto_recovery_clock >= AUTO_RECOVERY_INTERVAL:
		_auto_recovery_clock = 0.0
		_send_queued_recoveries()


## The calendar date and time now, as a Unix time (see game_config calendar).
func calendar_time() -> int:
	return calendar_time_at(play_time)


## The calendar date and time at a play time.
func calendar_time_at(at_play_time: float) -> int:
	if _calendar_start < 0:  # Parsed once: every ship asks every step.
		var calendar: Dictionary = GameData.config.get("calendar", {})
		_calendar_start = Time.get_unix_time_from_datetime_string(str(calendar.get("start", "2000-01-01T00:00:00")))
		_calendar_rate = calendar_seconds_per_second()
	return int(_calendar_start + at_play_time * _calendar_rate)


## Calendar seconds that pass per second of play (at 1x).
func calendar_seconds_per_second() -> float:
	return float(GameData.config.get("calendar", {}).get("minutes_per_second", 20)) * 60.0


## The game speeds this save allows: TIME_SPEEDS up to max_time_speed.
func allowed_time_speeds() -> Array[int]:
	var speeds: Array[int] = []
	speeds.assign(TIME_SPEEDS.filter(func(speed: int) -> bool: return speed <= max_time_speed))
	return speeds


## Steps to the next allowed speed, back to paused after the fastest.
func cycle_time_speed() -> void:
	if Net.is_client():
		return  # Only the host sets the speed.
	var speeds := allowed_time_speeds()
	time_speed = speeds[(speeds.find(time_speed) + 1) % speeds.size()]


## Space: pauses, or carries on at the speed it was paused from (1x if none).
func toggle_pause() -> void:
	if Net.is_client():
		return  # Only the host sets the speed.
	time_speed = clampi(_resume_speed, 1, max_time_speed) if time_speed == 0 else 0


# --- Ships ---------------------------------------------------------------

## Buys a ship and launches it docked at port_id, which must be the HQ or a hub
## it can launch at (see can_launch_at(); the HQ if empty).
func buy_ship(model_id: String, ship_name: String, port_id := "") -> Ship:
	ship_name = ship_name.strip_edges()
	if port_id.is_empty():
		port_id = home_port
	var model := GameData.get_ship_model(model_id)
	var tug: bool = model.get("tug", false)
	if tug:
		port_id = tug_port_for_new()  # Tugs go straight to the route port that needs one most.
	if not buy_error(model_id).is_empty() or not ship_name_error(ship_name).is_empty() or (not tug and not can_launch_at(model_id, port_id)):
		return null
	if Net.command(&"buy_ship", [model_id, ship_name, port_id]):
		return null  # The host buys it (see Net).
	var price := ship_price(model_id)
	if price < int(model.get("price", 0)):
		first_prices_used.append(model_id)
	money -= price
	_record(null, "bought", price)
	var ship := Ship.new(ship_name, model_id, port_id)
	ship.id = next_ship_id
	next_ship_id += 1
	ship.company = company
	ship.purchase_price = price
	ships.append(ship)
	if ship.is_service():
		ship.base_port = port_id
		if ship.is_recovery():
			_rebalance_recovery_boats()
	ships_changed.emit()
	save_game()
	return ship


func owned_count(model_id: String) -> int:
	return fleet().filter(func(ship: Ship) -> bool: return ship.model_id == model_id).size()


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
	if model.get("tug", false):
		if tug_ports().is_empty():
			return "Tugs are based at the ports on your ships' routes: give a ship a route first."
		if owned_count(model_id) >= tug_slots():
			return "Each port on your routes takes %d tugs, and all %d tug slots are full. Routes to more ports give more." % [tugs_per_port(), tug_slots()]
		return "You can't afford this ship." if money < ship_price(model_id) else ""
	var slots := Progression.model_slots(model, level)
	if owned_count(model_id) >= slots:
		var next := Progression.next_slot_level(model, level)
		if next < 0:
			return "You already own the maximum of %d %s ships." % [slots, model.get("name", model_id)]
		return "All %d %s slots are full. Level %d gives another." % [slots, model.get("name", model_id), next]
	if money < ship_price(model_id):
		return "You can't afford this ship."
	if not hubs.any(func(hub: Hub) -> bool: return can_launch_at(model_id, hub.port_id)):
		var on_lakes := hubs.all(func(hub: Hub) -> bool: return GameData.get_port(hub.port_id).get("seaway", false))
		if on_lakes and not model.get("seaway", false):
			return "A %s is too big for the St. Lawrence Seaway, and your HQ and hubs are all on the Great Lakes. Found a hub on the coast to launch one." % model.get("name", model_id)
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
	var line := fleet().filter(func(ship: Ship) -> bool: return ship.model_id == model_id)
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
	if Net.command(&"buy_mega", [model_id]):
		return
	var cost := mega_cost(model_id)
	money -= cost
	_record(null, "mega", cost)
	mega_upgrades.append(model_id)
	mega_upgraded.emit(model_id)
	for ship in fleet():
		if ship.model_id == model_id:
			ship.invalidate_stats()
			ship_changed.emit(ship)
	save_game()


## Adds HIDDEN_GEM_MONEY to the bank, the first time only.
func claim_hidden_gem() -> void:
	if hidden_gem_claimed:
		return
	if Net.command(&"claim_hidden_gem"):
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


## Shows a control's text in a company color; dark colors (black, navy...) get
## a light outline so they still read on the dark UI.
func apply_company_text_color(control: Control, color_id := company_color) -> void:
	var color := company_color_value(color_id)
	for item: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color", &"font_hover_pressed_color"]:
		control.add_theme_color_override(item, color)
	if color.get_luminance() < 0.25:
		control.add_theme_color_override(&"font_outline_color", Color(0.85, 0.87, 0.9))
		control.add_theme_constant_override(&"outline_size", 4)


## This player's company level.
func company_level() -> int:
	return company.level()


## The highest company level in the game: when the world's own features
## (storms, seasonal closures) start (in single player, the company's level).
func world_level() -> int:
	var best := company.level()
	for other in companies:
		best = maxi(best, other.level())
	return best


## The company a ship belongs to (this player's, if it has none yet).
func owner_of(ship: Ship) -> Company:
	return ship.company if ship.company != null else company


## A company's ships.
func fleet(of: Company = null) -> Array[Ship]:
	var who := of if of != null else company
	var out: Array[Ship] = []
	for ship in ships:
		if owner_of(ship) == who:
			out.append(ship)
	return out


## Adds money to a company (or takes it, if negative), telling the screens
## when it's this player's.
func _add_money(to: Company, amount: int) -> void:
	to.money += amount
	if to == company:
		money_changed.emit(to.money)


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
	if not ship.skill_names().has(skill):
		return "Not an upgrade for this ship."
	if int(ship.skills.get(skill, 0)) >= Progression.skill_max_level():
		return "Maxed out."
	if ship.skill_points() <= 0:
		return "No upgrade points to spend."
	if owner_of(ship).money < skill_cost(ship, skill):
		return "You can't afford this (%s short)." % Fmt.money(skill_cost(ship, skill) - owner_of(ship).money)
	return ""


## Spends one of a ship's skill points on "speed", "durability" or
## "efficiency", paying skill_cost().
func level_skill(ship: Ship, skill: String) -> void:
	if not skill_error(ship, skill).is_empty():
		return
	if Net.command(&"level_skill", [ship, skill]):
		return
	_buy_skill(ship, skill)
	ship_changed.emit(ship)


func _buy_skill(ship: Ship, skill: String) -> void:
	var cost := skill_cost(ship, skill)
	_add_money(owner_of(ship), -cost)
	_record(null, "upgrades", cost, owner_of(ship))
	ship.skills[skill] = int(ship.skills[skill]) + 1
	ship.invalidate_stats()


## Every unspent skill point in the fleet as [cost, ship, skill], cheapest
## first. Each ship's points go round-robin to its lowest skill (ties broken in
## Ship.skill_names() order: speed 1, efficiency 1, durability 1, speed 2...), which is
## also its cheapest, so buying in this order keeps every ship's order.
func _upgrade_plan() -> Array:
	var plan := []
	for ship in fleet():
		var levels := ship.skills.duplicate()
		for point in ship.skill_points():
			var best := ""
			for skill in ship.skill_names():
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
	if Net.command(&"upgrade_all"):
		return 0
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
	for ship in fleet():
		points += maxi(ship.skill_points(), 0)
	return points


# --- Headquarters and hubs ---------------------------------------------

## The HQ or hub a company (this player's by default) has at a port, or null.
func hub_at(port_id: String, of: Company = null) -> Hub:
	return (of if of != null else company).hub_at(port_id)


## A company's hub bonus for ships at a port (0 if it has no hub there): "xp",
## "costs", "speed" or "pay".
func hub_bonus(port_id: String, path: String, of: Company = null) -> float:
	return (of if of != null else company).hub_bonus(port_id, path)


## Every company in the game (just this player's before any are listed).
func all_companies() -> Array[Company]:
	if companies.is_empty():
		return [company]
	return companies


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
	if Net.command(&"build_hub", [port_id]):
		return ""
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
	if Net.command(&"upgrade_hub", [hub, path]):
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
	for who in all_companies():
		_rebalance_boats_of(who)


func _rebalance_boats_of(who: Company) -> void:
	var models := {}
	for ship in fleet(who):
		if ship.is_recovery():
			models.get_or_add(ship.model_id, []).append(ship)
	for boats: Array in models.values():
		var model: Dictionary = boats[0].model()
		var ports := who.hubs.map(func(hub: Hub) -> String: return hub.port_id).filter(func(port: String) -> bool:
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


## A company's (this player's by default) recovery boats based at a port.
func recovery_boats_at(port_id: String, of: Company = null) -> Array:
	return fleet(of).filter(func(ship: Ship) -> bool: return ship.is_recovery() and ship.base_port == port_id)


## XP a hub needs for its next level (0 at the max level).
func hub_level_cost(hub: Hub, of: Company = null) -> float:
	return Progression.hub_level_cost(hub.level, (of if of != null else company).level()) if hub.level < Hub.max_level() else 0.0


func _gain_hub_xp(hub: Hub, amount: float, of: Company = null) -> void:
	if hub.level >= Hub.max_level():
		return
	hub.xp += amount
	var leveled := false
	while hub.level < Hub.max_level() and hub.xp >= hub_level_cost(hub, of):
		hub.xp -= hub_level_cost(hub, of)
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
	if Net.command(&"rename_ship", [ship, new_name]):
		return ""
	for bucket: Dictionary in owner_of(ship).finance_window:
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
	if ship.is_service() or not route_error(route, ship).is_empty():
		return
	if Net.command(&"assign_route", [ship, route]):
		return
	ship.paused = false
	if ship.is_docked():
		ship.route = route.duplicate()
		ship.pending_route.clear()
		ship.route_index = ship.route.find(ship.docked_at)
	else:
		ship.pending_route = route.duplicate()
	_rebalance_tugs()
	ship_changed.emit(ship)


## A ship paused at sea carries on to its next port and waits there.
func set_paused(ship: Ship, paused: bool) -> void:
	if not ship.has_route():
		return
	if Net.command(&"set_paused", [ship, paused]):
		return
	ship.paused = paused
	ship_changed.emit(ship)


func set_auto_refuel(ship: Ship, on: bool) -> void:
	if Net.command(&"set_auto_refuel", [ship, on]):
		return
	ship.auto_refuel = on
	ship_changed.emit(ship)


func set_auto_repair(ship: Ship, on: bool) -> void:
	if Net.command(&"set_auto_repair", [ship, on]):
		return
	ship.auto_repair = on
	ship_changed.emit(ship)


func set_auto_recover(ship: Ship, on: bool) -> void:
	if Net.command(&"set_auto_recover", [ship, on]):
		return
	ship.auto_recover = on
	ship_changed.emit(ship)


func set_full_loads(ship: Ship, on: bool) -> void:
	if Net.command(&"set_full_loads", [ship, on]):
		return
	ship.full_loads = on
	ship.load_check_time = 0.0  # Act on it at once rather than at the next look.
	ship_changed.emit(ship)


func set_bank_reserve(amount: int) -> void:
	if Net.command(&"set_bank_reserve", [amount]):
		return
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
	if Net.command(&"sell_ship", [ship]):
		return ""
	var price := ship.sell_price()
	docks.release(ship)
	ships.erase(ship)
	if ship.is_icebreaker():
		_release_convoy(ship)
		icebreaking.refresh(true)
	if ship.is_recovery():
		_rebalance_recovery_boats()
	_rebalance_tugs()
	_add_money(owner_of(ship), price)
	_record(null, "sold", price, owner_of(ship))
	ship_sold.emit(ship, price)
	ships_changed.emit()
	save_game()
	return ""


func _advance(ship: Ship, delta: float) -> void:
	# A ship waiting in port for a full load, not due another look: nothing to do.
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and owner_of(ship).money < ship.load_need and ship.is_docked() \
			and ship.berth_phase == Ship.BERTH_NONE:
		return
	# A recovery boat or tug standing by at its base (most of them, most of the
	# time): nothing to do until it's sent out.
	if ship.dock_time < 0.0 and ship.docked_at == ship.base_port and ship.hold_reason.is_empty() \
			and not ship.docked_at.is_empty() and (ship.is_recovery() or ship.is_tug()) and not ship.is_on_job():
		return
	if ship.is_icebreaker():
		_advance_icebreaker(ship, delta)
	elif ship.is_tug() and ship.is_on_job():
		_advance_tug_job(ship, delta)
	elif ship.is_on_job():
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
	if ship.escort != null:
		return true  # In a convoy: its icebreaker moves it (see _escort()).
	var zone := ship.zone_factors(ship.traveled_nm)
	var storm := _storm_factors(ship)
	var speed := ship.speed()
	if ship.is_service():
		speed = maxf(speed, ship.top_speed() * MIN_RECOVERY_SPEED_FACTOR)
	speed *= float(zone[0]) * float(storm[0])
	var target := _ice_hold(ship, _storm_hold(ship, canal_traffic.limit(ship, ship.traveled_nm + speed * delta)))
	var effort := clampf((target - ship.traveled_nm) / (speed * delta), 0.0, 1.0) if speed * delta > 0.0 else 1.0
	if ship.is_running() or ship.is_service():
		ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * float(zone[1]) * float(storm[1]) * delta * effort, 0.0)
	# A storm costs time, not fuel per mile: the engines make less way, so the
	# fuel a ship set off with still covers the leg.
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * float(storm[0]) * delta * effort, 0.0)
	ship.traveled_nm = target
	if not ship.is_service():
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


## [speed factor, wear factor] for a ship at sea from the storms and seasonal
## ice where it is (see Weather.factors() and Seasons.factors()); [1, 1] in
## port or when neither is active.
func _storm_factors(ship: Ship) -> Array:
	if ship.is_docked() or ship.from_port.is_empty():
		return [1.0, 1.0]
	# Storms drift and ice comes and goes slowly: each ship looks again only
	# every STORM_FACTOR_REFRESH_S (and on a new leg: see _depart(), _start_segment()).
	if play_time < ship.storm_check_time:
		return ship.storm_factors
	ship.storm_check_time = play_time + STORM_FACTOR_REFRESH_S
	ship.storm_factors = [1.0, 1.0]
	# Nothing to ask about where the ship is unless a storm is out or some ice is in.
	var storms_out := weather.active() and not weather.storms.is_empty()
	var ice_in := seasonal.active() and not seasonal.zones_now().is_empty()
	if storms_out or ice_in:
		var at := Geo.unproject(ship.world_position())
		var storm := weather.factors(at) if storms_out else [1.0, 1.0]
		var ice := seasonal.factors(at) if ice_in else [1.0, 1.0]
		ship.storm_factors = [float(storm[0]) * float(ice[0]), float(storm[1]) * float(ice[1])]
	return ship.storm_factors


## Where a ship may sail to this step: no closer than STORM_OFFSHORE_NM to a
## port a storm has closed (recovery boats go in regardless), saying so in its
## weather_wait.
func _storm_hold(ship: Ship, target: float) -> float:
	var storm := {} if ship.is_service() else weather.closed_by(ship.to_port)
	if storm.is_empty():
		ship.weather_wait = ""
		return target
	var stop := maxf(ship.leg_length() - STORM_OFFSHORE_NM, 0.0)
	if target <= stop:
		ship.weather_wait = ""
		return target
	ship.weather_wait = "waiting off %s for %s to pass" % [GameData.port_name(ship.to_port), Weather.title(storm)]
	return maxf(ship.traveled_nm, stop)


## Where a ship may sail to this step when its lane runs into an ice area with
## an icebreaker (see Icebreaking): no further than the ice edge until the
## icebreaker comes to lead it through, waiting there (engines off) in
## ice_wait. Service ships go on regardless.
func _ice_hold(ship: Ship, target: float) -> float:
	if ship.is_service():
		return target
	var item := icebreaking.area_for_leg(ship.from_port, ship.to_port)
	var entry := icebreaking.entry_mile(item, ship.from_port, ship.to_port) if not item.is_empty() else -1.0
	if entry <= 0.0 or ship.traveled_nm > entry + 0.001 or target <= entry:
		if not ship.ice_wait.is_empty() and ship.escort == null:
			ship.ice_wait = ""  # The ice went out of season, or the icebreaker left.
			ship.weather_wait = ""
		return target
	if ship.ice_wait != item.id:
		ship.ice_wait = item.id
		ship.ice_wait_since = play_time
	ship.weather_wait = "waiting at the edge of the %s ice for an icebreaker" % item.name
	return maxf(ship.traveled_nm, entry)


## Activity log warnings about storms (while they're active) for the ports
## that matter to the player (the HQ and hubs, and every port a ship is at,
## heading to or has on its route): a tropical storm heading for one (within
## STORM_WARNING_AHEAD_S), one closing or reopening, and a ship sailing into a
## storm.
func _storm_warnings() -> void:
	if not weather.active():
		_closed_ports.clear()
		_ships_in_storms.clear()
		return
	var ports := _player_ports()
	var ahead := {}  # Tropical storm -> where it will be.
	for storm in weather.storms:
		if Weather.TROPICAL.has(storm.kind):
			ahead[storm] = weather.position_after(storm, STORM_WARNING_AHEAD_S)
	for port_id: String in ports:
		var closing := weather.closed_by(port_id)
		var was: String = _closed_ports.get(port_id, "")
		if not closing.is_empty() and was.is_empty():
			_closed_ports[port_id] = Weather.title(closing)
			ActivityLog.add("%s is closed: %s is overhead. Ships wait until it passes." % [GameData.port_name(port_id), Weather.title(closing)], ActivityLog.Kind.BAD)
		elif closing.is_empty() and not was.is_empty():
			_closed_ports.erase(port_id)
			ActivityLog.add("%s is open again: %s has passed." % [GameData.port_name(port_id), was], ActivityLog.Kind.GOOD)
		if not closing.is_empty():
			continue
		var port := GameData.get_port(port_id)
		var at := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
		for storm: Dictionary in ahead:
			var key := "%s/%s/%s" % [storm.basin, storm.name, port_id]
			if _storm_warned.has(key):
				continue
			var then: Vector2 = ahead[storm]
			if Geo.distance_nm(then, at) < float(storm.radius_nm) * 0.5 and Geo.distance_nm(Vector2(storm.lon, storm.lat), at) >= float(storm.radius_nm) * 0.5:
				_storm_warned[key] = true
				ActivityLog.add("%s is heading for %s (about 2 days away)." % [Weather.title(storm), GameData.port_name(port_id)], ActivityLog.Kind.BAD)
	for ship in fleet():
		var named := ""
		if not ship.is_docked() and not ship.from_port.is_empty() and not ship.is_lost():
			var found := weather.strongest_at(Geo.unproject(ship.world_position()))
			if float(found[1]) >= STORM_SHIP_NOTICE:
				named = Weather.title(found[0])
		if named.is_empty():
			_ships_in_storms.erase(ship)
		elif _ships_in_storms.get(ship, "") != named:
			_ships_in_storms[ship] = named
			ActivityLog.add("%s is sailing through %s: slower, and wearing faster." % [ship.name, named], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


## The ports that matter to the player, as a set: the HQ and hubs, and every
## port a ship is at, heading to or has on its route.
func _player_ports() -> Dictionary:
	var ports := {}
	for hub in hubs:
		ports[hub.port_id] = true
	for ship in fleet():
		for port_id: String in [ship.docked_at, ship.to_port]:
			if not port_id.is_empty():
				ports[port_id] = true
		for port_id in ship.route:
			ports[port_id] = true
	return ports


## The canals the player's ships use, and the stretches of sea with a seasonal
## closure they sail through (by closure id), as a set: on the leg each is
## sailing and every leg of its route.
func _player_canals() -> Dictionary:
	var canals := {}
	for ship in fleet():
		var legs := []
		if not ship.from_port.is_empty():
			legs.append([ship.from_port, ship.to_port])
		for i in ship.route.size():
			legs.append([ship.route[i], ship.route[(i + 1) % ship.route.size()]])
		for leg: Array in legs:
			if leg[0] != leg[1]:
				for crossing: Dictionary in GameData.canal_crossings(leg[0], leg[1]):
					canals[crossing.canal.id] = true
				for closure: Dictionary in seasonal.closures():
					if closure.has("circles") and seasonal.lane_enters(closure, leg[0], leg[1]):
						canals[closure.id] = true
	return canals


## Activity log notes about the seasonal closures that touch the player's
## ports or canals (while closures are active): warn_days calendar days before
## one shuts, and when it shuts and reopens; and when an ice zone with one of
## their ports in it freezes and thaws.
func _season_warnings() -> void:
	if not seasonal.active():
		_season_closed.clear()
		return
	var now := calendar_time()
	var ahead := now + int(float(GameData.config.get("seasons", {}).get("warn_days", 10)) * 86400.0)
	# What the player uses changes slowly, and working it out walks every leg
	# of every route: refreshed every PLAYER_USE_REFRESH_S of play.
	if _player_use.is_empty() or play_time - _player_use_time >= PLAYER_USE_REFRESH_S:
		_player_use_time = play_time
		_player_use = {ports = _player_ports(), canals = _player_canals(), zones = {}}
	var ports: Dictionary = _player_use.ports
	var canals: Dictionary = _player_use.canals
	var items: Array = seasonal.closures() + seasonal.ice_zones()
	for item: Dictionary in items:
		var relevant: bool = canals.has(item.get("canal", "")) or (item.has("circles") and canals.has(item.id)) or item.get("ports", []).any(func(p: String) -> bool: return ports.has(p))
		if item.has("center"):
			if not _player_use.zones.has(item.id):
				var center := Vector2(item.center[0], item.center[1])
				_player_use.zones[item.id] = ports.keys().any(func(p: String) -> bool:
					var port := GameData.get_port(p)
					return Geo.distance_nm(center, Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))) <= float(item.radius_nm))
			relevant = _player_use.zones[item.id]
		var closed := Seasons.in_season(item, now)
		var was = _season_closed.get(item.id)
		_season_closed[item.id] = closed
		if not relevant or was == closed:
			continue
		var is_zone: bool = item.has("center")
		if closed and is_zone:
			ActivityLog.add("The %s has set in: ships crawl through it until %s." % [item.name, Seasons.date_text(item.to)], ActivityLog.Kind.BAD)
		elif closed and not icebreaking.lifting(item).is_empty():
			ActivityLog.add("%s %s iced in until %s, but your icebreakers will lead ships through." % [Seasons.subject(item),
				Seasons.verb(item, "is", "are"), Seasons.date_text(item.to)], ActivityLog.Kind.INFO)
		elif closed:
			ActivityLog.add("%s %s closed for %s until %s." % [Seasons.subject(item), Seasons.verb(item, "has", "have"), item.why,
				Seasons.date_text(item.to)], ActivityLog.Kind.BAD)
		elif was != null and is_zone:
			ActivityLog.add("The %s has cleared." % item.name, ActivityLog.Kind.GOOD)
		elif was != null:
			ActivityLog.add("%s %s reopened." % [Seasons.subject(item), Seasons.verb(item, "has", "have")], ActivityLog.Kind.GOOD)
	for item: Dictionary in seasonal.closures():
		# Warned once per season: forgotten once it's open and not closing soon.
		if not Seasons.in_season(item, now) and not Seasons.in_season(item, ahead):
			_season_warned.erase(item.id)
			continue
		if _season_warned.has(item.id) or Seasons.in_season(item, now):
			continue
		if not (canals.has(item.get("canal", "")) or (item.has("circles") and canals.has(item.id)) or item.get("ports", []).any(func(p: String) -> bool: return ports.has(p))):
			continue
		_season_warned[item.id] = true
		ActivityLog.add("%s %s for %s on %s: ships won't start legs they can't finish before then." % [Seasons.subject(item),
			Seasons.verb(item, "closes", "close"), item.why, Seasons.date_text(item.from)], ActivityLog.Kind.BAD)


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
## (not service ships, not in a canal, and not waiting out weather or ice or
## in an icebreaker's convoy) rolls its own
## Ship.breakdown_chance(); on a hit it loses hit of its maintenance, and is
## lost at sea if that leaves it at 0%.
func _roll_breakdowns(delta: float) -> void:
	var settings: Dictionary = GameData.config.get("breakdowns", {})
	var interval := float(settings.get("interval_s", 5))
	_breakdown_clock += delta
	while _breakdown_clock >= interval:
		_breakdown_clock -= interval
		var from_level := int(settings.get("min_company_level", 6))
		for ship in ships:
			if owner_of(ship).level() < from_level:
				continue  # Each company's ships break down from its own level.
			if ship.is_service() or ship.is_docked() or ship.is_lost() or canal_traffic.in_canal(ship) or not ship.weather_wait.is_empty() or ship.escort != null or randf() >= ship.breakdown_chance() * _storm_factors(ship)[1]:
				continue
			ship.maintenance = maxf(ship.maintenance - float(settings.get("hit", 0.5)), 0.0)
			ship.risk_check_time = 0.0  # Check at once whether it can still make port.
			ship_broke_down.emit(ship)
			if ship.maintenance <= 0.0:
				_lose(ship, "broken down")


func _arrive(ship: Ship, port: String, paid := true) -> void:
	ship.weather_wait = ""
	ship.ice_wait = ""
	ship.at_risk = false
	canal_traffic.leave(ship)
	ship.delivery_canals.clear()
	if paid and not ship.is_service():
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
		ship.cargo_payment = roundi(sale + trade_bonus(ship.from_port, port, sale - ship.cargo_cost, ship.model_id, owner_of(ship)))
		ship.cargo_leg_nm = GameData.distance_nm(ship.from_port, port) if paid and ship.from_port != port else 0.0
	ship.unloaded = ship.is_service()
	ship.docked_at = port
	ship.from_port = ""
	ship.to_port = ""
	ship.traveled_nm = 0.0
	if not ship.is_service():
		# Its stop waits for a berth: it anchors and queues (see _advance_docked()).
		ship.berth = -1
		ship.berth_phase = Ship.BERTH_WAIT
		ship.berth_since = play_time
		docks.join_queue(ship)
	if not ship.pending_route.is_empty():
		ship.route = ship.pending_route.duplicate()
		ship.pending_route.clear()
		ship.route_index = ship.route.find(port)
	ship.dock_time = 0.0
	ship.refill_billed = 0.0
	var phase := ship.refill_phase_seconds()
	ship.repair_rate = (1.0 - ship.maintenance) / phase
	ship.refuel_rate = (ship.fuel_tank() - ship.fuel) / phase
	ship.stop_sale = 0
	ship.stop_cost = 0
	ship.stop_fuel_cost = 0.0
	ship.stop_repair_cost = 0.0
	ship_changed.emit(ship)


## A cargo ship's stop needs a berth (see Docks): it waits at anchor for one,
## first come first served, comes alongside (docks in_s), and only then does
## its stop; when it's done it pulls out (docks out_s), to sail or, if it
## can't go yet, to lie at the anchorage. The stop runs on a fixed clock:
## repair for one refill phase, then refuel for one, with unloading (and
## payment) over the first half of the dock time and loading over the second.
## Afterwards a running ship leaves as soon as it has the fuel for its next
## leg, and a Mammoth away from home sails back.
func _advance_docked(ship: Ship, delta: float) -> void:
	if not _advance_berth(ship, delta):
		return
	if ship.is_docking():
		var end := ship.dock_time + delta
		var dock_s := ship.dock_seconds()
		# Repairs and fuel are done (and paid for) every REFILL_BILL_S rather than
		# every step: the same amounts at the same pace, for less work.
		if end >= dock_s or end - ship.refill_billed >= REFILL_BILL_S or end < ship.refill_billed:
			var phase := ship.refill_phase_seconds()
			var start := minf(ship.refill_billed, end)
			if ship.auto_repair:
				_repair(ship, ship.repair_rate * _overlap(start, end, 0.0, phase))
			if ship.auto_refuel:
				_refuel(ship, ship.refuel_rate * _overlap(start, end, phase, 2.0 * phase))
			ship.refill_billed = end
		ship.dock_time = end
		if not ship.unloaded and end >= dock_s / 2.0:
			_unload(ship)
		if end < dock_s:
			return
		ship.dock_time = -1.0
		ship_changed.emit(ship)
	if ship.is_service() and not ship.base_port.is_empty() and ship.docked_at != ship.base_port and not _on_ice_duty(ship):
		_try_depart(ship, delta, ship.base_port)
	elif ship.is_running():
		_try_depart(ship, delta, ship.route[ship.next_route_index()])
	else:
		_set_hold(ship, "")
	if ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
		_pull_out(ship, "")  # Done, but not going yet: off to the anchorage to wait.


## A cargo ship's berth: queuing for one, coming alongside, pulling out. True
## once it's moored (or never needed one), when its stop can go on.
func _advance_berth(ship: Ship, delta: float) -> bool:
	var settings := Docks.settings()
	match ship.berth_phase:
		Ship.BERTH_WAIT:
			if not docks.claim(ship):
				return false
			ship.berth_phase = Ship.BERTH_IN
			ship.berth_time = 0.0
			ship_changed.emit(ship)
			return false
		Ship.BERTH_IN:
			ship.berth_time += delta
			if ship.berth_time < float(settings.get("in_s", 2.5)):
				return false
			ship.berth_phase = Ship.BERTH_NONE
			ship_changed.emit(ship)
		Ship.BERTH_OUT:
			ship.berth_time += delta
			if ship.berth_time < float(settings.get("out_s", 2.0)):
				return false
			docks.release(ship)
			ship.berth_phase = Ship.BERTH_NONE
			var to := ship.depart_to
			ship.depart_to = ""
			if not to.is_empty():
				_set_off(ship, to)
			else:
				ship_changed.emit(ship)
			return false
	return true


## Starts pulling out of its berth, then sails for `to` ("" to anchor).
func _pull_out(ship: Ship, to: String) -> void:
	ship.berth_phase = Ship.BERTH_OUT
	ship.berth_time = 0.0
	ship.depart_to = to
	ship_changed.emit(ship)


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
	var who := owner_of(ship)
	ship.stop_sale = ship.cargo_payment
	ship.stop_cost = ship.cargo_cost
	_add_money(who, ship.cargo_payment)
	_record(ship, "income", ship.cargo_payment)
	market.trade(ship.docked_at, ship.cargo_id, ship.cargo_payment, false)
	port_sizes.add_traffic(ship.docked_at, ship.cargo_payment)
	who.delivered[ship.cargo_id] = int(who.delivered.get(ship.cargo_id, 0)) + ship.cargo_qty
	cargo_sold.emit(ship, ship.docked_at, ship.cargo_id, ship.cargo_qty, ship.cargo_cost, ship.cargo_payment, ship.stop_toll)
	var hub := hub_at(ship.docked_at, who)
	var xp := Progression.xp_for_cargo(ship.cargo_qty, ship.cargo_id, ship.cargo_leg_nm)
	# Cargo that came through canals earns their XP bonuses on top of the hub's.
	var canal_bonus := 0.0
	for canal_id in ship.delivery_canals:
		var canal := GameData.get_canal(canal_id)
		var bonus := float(canal.get("xp_bonus", 0.0))
		canal_bonus += bonus
		if bonus > 0.0:
			var stats: Dictionary = who.canal_stats.get_or_add(canal_id, {crossings = 0, tolls = 0.0, xp = 0.0})
			stats.xp = float(stats.xp) + xp * bonus
	ship.delivery_canals.clear()
	_gain_xp(ship, xp, 1.0 + (hub.bonus("xp") if hub else 0.0) + canal_bonus,
		1.0 + (hub.company_xp_bonus() if hub else 0.0) + canal_bonus)
	if hub:
		hub.deliveries += 1
		hub.income += ship.cargo_payment
		_gain_hub_xp(hub, xp * (1.0 + canal_bonus), who)
	ship.cargo_id = ""
	ship.cargo_qty = 0
	ship.cargo_cost = 0
	ship.cargo_payment = 0


## Buys the most profitable cargo the ship can carry to its next port (see
## Market.best_cargo()): a full hold (less what a canal makes it leave behind),
## or as much as its company's money allows while keeping its fuel reserve
## (see fuel_reserve()) and bank_reserve, unless full loads are on, when it
## buys nothing short of a full hold. Nothing if no cargo makes a profit. A
## full load taken out of a hub by a ship that arrived empty gives the hub XP.
## Returns the cargo it chose (bought or not, for lack of money), or "" if none pays.
func _load_cargo(ship: Ship, to: String) -> String:
	if ship.is_service() or not ship.cargo_id.is_empty() or not ship.is_docked() or to.is_empty() or to == ship.docked_at:
		return ""
	var who := owner_of(ship)
	var best := market.best_cargo(ship.model(), ship.docked_at, to, who)
	if best[0] == "":
		return ""
	var price := market.buy_price(ship.docked_at, best[0])
	var reserve := fuel_reserve(who)
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())))
	var quantity := mini(room, floori((float(who.money) - ship.bill - reserve - who.bank_reserve) / price))
	if quantity <= 0 or (ship.full_loads and quantity < room):
		# What a full hold would need in the bank, for ships waiting for one.
		ship.load_need = roundi(room * price + ship.bill + reserve + who.bank_reserve)
		return best[0]
	var cost := roundi(quantity * price)
	_add_money(who, -cost)
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
	var hub := hub_at(ship.docked_at, who)
	if hub and ship.stop_sale == 0 and quantity >= room:
		_gain_hub_xp(hub, Progression.xp_for_cargo(quantity, best[0], GameData.distance_nm(ship.docked_at, to)), who)
	ship_changed.emit(ship)
	return best[0]


## Adds delivery XP to the ship's company (times company_multiplier, from a
## hub's company XP bonus) and to the ship (times ship_multiplier, from its
## ship XP upgrade), announcing this player's level-ups.
func _gain_xp(ship: Ship, amount: float, ship_multiplier := 1.0, company_multiplier := 1.0) -> void:
	var who := owner_of(ship)
	var company_before := who.level()
	var ship_before := ship.level()
	who.xp += amount * company_multiplier
	ship.xp += amount * ship_multiplier
	var bucket := _current_bucket(who)
	bucket.fleet["xp"] = float(bucket.fleet.get("xp", 0.0)) + amount * company_multiplier
	if who == company:
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
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and owner_of(ship).money < ship.load_need:
		return
	if not ship.fits_port(to):
		_set_hold(ship, "%s is too small for this ship; assign a new route" % GameData.port_name(to))
		return
	# A storm over the port: wait it out (nothing for the player to do).
	var storm := weather.closed_by(ship.docked_at)
	if not storm.is_empty():
		ship.weather_wait = "%s is closed by %s" % [GameData.port_name(ship.docked_at), Weather.title(storm)]
		return
	# A leg it couldn't finish before a seasonal closure shuts its way: wait for
	# the closure to end (again nothing for the player to do).
	if seasonal.active():
		var seconds := ship.leg_seconds(ship.docked_at, to, 0.0, GameData.distance_nm(ship.docked_at, to), maxf(ship.maintenance, 0.01))
		var closure := seasonal.leg_blocker(ship.docked_at, to, seconds)
		if not closure.is_empty():
			ship.weather_wait = Seasons.wait_text(closure)
			return
	ship.weather_wait = ""
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
	# Leaving a port in an ice area that has an icebreaker: wait for it to lead
	# the way out (it calls _depart() itself; see _begin_escort()).
	if not ship.is_service():
		var item := icebreaking.area_for_leg(ship.docked_at, to)
		if not item.is_empty() and icebreaking.entry_mile(item, ship.docked_at, to) == 0.0:
			if ship.ice_wait != item.id:
				ship.ice_wait = item.id
				ship.ice_wait_since = play_time
			ship.ice_to = to
			ship.weather_wait = "waiting for an icebreaker to lead it out through the %s ice" % item.name
			return
		if not ship.ice_wait.is_empty() and ship.escort == null:
			ship.ice_wait = ""
	_set_hold(ship, "")
	_depart(ship, to)


## With full loads on, a cargo ship with an empty hold stays in port until it
## can buy a full one (see _load_cargo()), saying why in its load_wait. A leg
## where no cargo makes a profit is sailed empty straight away.
func _waiting_for_load(ship: Ship, to: String) -> bool:
	if ship.is_service() or not ship.full_loads or not ship.cargo_id.is_empty():
		_set_load_wait(ship, "")
		return false
	# Already waiting: look again as soon as the money reaches what a full hold
	# needed, and otherwise only every LOAD_RECHECK_S (prices drift slowly).
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and owner_of(ship).money < ship.load_need:
		return true
	ship.load_check_time = play_time + LOAD_RECHECK_S
	if _load_cargo(ship, to).is_empty() or not ship.cargo_id.is_empty():
		_set_load_wait(ship, "")
		return false
	_set_hold(ship, "")
	var reason := "waiting for money for a full load to %s" % GameData.port_name(to)
	if owner_of(ship).bank_reserve > 0:
		reason += " (keeping %s in the bank)" % Fmt.money(owner_of(ship).bank_reserve)
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


## Sails for `to`: a ship at a berth pulls out first (see _pull_out()); one
## at the anchorage sets off straight away.
func _depart(ship: Ship, to: String) -> void:
	if ship.berth >= 0:
		if ship.berth_phase != Ship.BERTH_OUT:
			_pull_out(ship, to)
		return
	_set_off(ship, to)


func _set_off(ship: Ship, to: String) -> void:
	docks.release(ship)  # It might have been queuing (a convoy leaving an iced port).
	ship.berth_phase = Ship.BERTH_NONE
	if not ship.is_service():
		ship.route_index = ship.next_route_index()
		_load_cargo(ship, to)  # If it didn't load when unloading (a new ship, or a new route).
	_leave_port(ship)
	ship.from_port = ship.docked_at
	ship.to_port = to
	ship.risk_check_time = 0.0
	ship.storm_check_time = 0.0
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


# --- Icebreakers -----------------------------------------------------------

## Stations an icebreaker at an ice area (game_config icebreaking), or at none
## (""): it then waits at the nearest of the area's ports it can use. Returns
## why it can't, or "". A convoy it was leading or fetching carries on alone.
func station_icebreaker(ship: Ship, area_id: String) -> String:
	var base := ship.reference_port()
	if not area_id.is_empty():
		var item := icebreaking.area(area_id)
		var error := icebreaking.station_error(item, ship.model())
		if not error.is_empty():
			return error
		base = icebreaking.station_port(item, ship.model(), ship.reference_port())
	if Net.command(&"station_icebreaker", [ship, area_id]):
		return ""
	_release_convoy(ship)
	ship.station = area_id
	ship.base_port = base
	icebreaking.refresh(true)
	ship_changed.emit(ship)
	save_game()
	return ""


## Lets an icebreaker's convoy go (they carry on alone, or wait for another)
## and ends its escort. A ship it was on its way to fetch waits again.
func _release_convoy(icebreaker: Ship) -> void:
	for ship in icebreaker.convoy:
		if ship.escort == icebreaker:
			ship.escort = null
	icebreaker.convoy.clear()
	if icebreaker.ice_phase == "approach" or icebreaker.ice_phase == "escort":
		icebreaker.ice_phase = ""  # It finishes the stretch of lane it's on, then docks.
	icebreaker.job_segments.clear()


## An icebreaker: idle in port it docks (refuels and repairs) and sails home
## to its station, or sets off for the next convoy waiting in its area; then
## it sails out to the convoy ("approach"), turns to face the way it'll lead
## if it came in the other way ("turn_in"), leads it through the ice
## ("escort"), and, if it let the convoy go at the ice edge, turns round
## ("turn_back") and comes back to the port it led it from ("return").
func _advance_icebreaker(ship: Ship, delta: float) -> void:
	match ship.ice_phase:
		"":
			if ship.is_docked():
				if ship.dock_time < 0.0 and not ship.station.is_empty() and icebreaking.open(icebreaking.area(ship.station)):
					var convoy := icebreaking.next_convoy(ship)
					if not convoy.is_empty():
						_start_convoy(ship, convoy)
						return
				_advance_docked(ship, delta)
			elif _sail(ship, delta) and ship.traveled_nm >= ship.leg_length():
				_arrive(ship, ship.to_port, false)
		"approach":
			_sail(ship, delta)
			if ship.traveled_nm >= ship.segment_end:
				if not ship.job_segments.is_empty():
					_start_segment(ship, ship.job_segments.pop_front())
				elif _escort_turn_needed(ship):
					ship.ice_phase = "turn_in"
					ship.align_time = 0.0
				else:
					_begin_escort(ship)
		"turn_in":
			ship.align_time += delta
			if ship.align_time >= Ship.ALIGN_SECONDS:
				_begin_escort(ship)
		"turn_back":
			ship.align_time += delta
			if ship.align_time >= Ship.ALIGN_SECONDS:
				var leg := ship.escort_leg
				var length := GameData.distance_nm(leg[0], leg[1])
				ship.ice_phase = "return"
				_start_segment(ship, [leg[1], leg[0], length - float(leg[3]), length])
		"escort":
			_escort(ship, delta)
		"return":
			if _sail(ship, delta) and ship.traveled_nm >= ship.segment_end:
				ship.ice_phase = ""
				_arrive(ship, ship.to_port, false)


## True while an icebreaker is docked in its own ice area while the ice is in
## season: it stays there ready for the next convoy, rather than going home to
## its station port (ships it just led in will want leading out).
func _on_ice_duty(ship: Ship) -> bool:
	if not ship.is_icebreaker() or ship.station.is_empty():
		return false
	var item := icebreaking.area(ship.station)
	return icebreaking.open(item) and icebreaking.port_inside(item, ship.docked_at)


## Sends an icebreaker docked in its area to lead a convoy: to the port they're
## waiting in, or to the ice edge on their lane (through whichever end of the
## lane is nearer).
func _start_convoy(icebreaker: Ship, convoy: Array[Ship]) -> void:
	var first := convoy[0]
	var leg := Icebreaking.waiting_leg(first)
	var a: String = leg[0]
	var b: String = leg[1]
	var item := icebreaking.area(icebreaker.station)
	var length := GameData.distance_nm(a, b)
	var start := 0.0 if first.is_docked() else icebreaking.entry_mile(item, a, b)
	var here := icebreaker.docked_at
	var segments := []
	if first.is_docked():
		if here != a:
			segments.append([here, a, 0.0, GameData.distance_nm(here, a)])
	else:
		var via_a := (0.0 if here == a else GameData.distance_nm(here, a)) + start
		var via_b := (0.0 if here == b else GameData.distance_nm(here, b)) + length - start
		if via_a <= via_b:
			if here != a:
				segments.append([here, a, 0.0, GameData.distance_nm(here, a)])
			if start > 0.0:
				segments.append([a, b, 0.0, start])
		else:
			if here != b:
				segments.append([here, b, 0.0, GameData.distance_nm(here, b)])
			segments.append([b, a, 0.0, length - start])
	icebreaker.convoy = convoy
	for i in convoy.size():
		convoy[i].escort = icebreaker
		convoy[i].escort_place = i
	icebreaker.escort_leg = [a, b, start, icebreaking.escort_end(item, a, b)]
	_leave_port(icebreaker)
	icebreaker.docked_at = ""
	if segments.is_empty():
		_begin_escort(icebreaker)
	else:
		icebreaker.ice_phase = "approach"
		icebreaker.job_segments = segments
		_start_segment(icebreaker, icebreaker.job_segments.pop_front())
	ship_changed.emit(icebreaker)


## The icebreaker is at the head of its convoy: it starts leading it along the
## lane, and ships waiting in port set off behind it.
func _begin_escort(icebreaker: Ship) -> void:
	var leg := icebreaker.escort_leg
	icebreaker.ice_phase = "escort"
	_start_segment(icebreaker, [leg[0], leg[1], leg[2], leg[3]])
	for ship in icebreaker.convoy:
		if ship.is_docked():
			ship.ice_wait = ""
			ship.weather_wait = ""
			_set_hold(ship, "")
			_depart(ship, leg[1])
		ship.weather_wait = "following %s through the %s ice" % [icebreaker.name, icebreaking.area(icebreaker.station).get("name", "")]
		ship_changed.emit(ship)


## Leads a convoy through the ice: the icebreaker ahead at escort speed, each
## ship gap_nm behind the one before, burning fuel and wearing for the miles
## it makes. When they're all through, they go on alone (or arrive, if the
## lane ended in the ice) and the icebreaker docks there or turns back.
func _escort(icebreaker: Ship, delta: float) -> void:
	var leg := icebreaker.escort_leg
	var end: float = leg[3]
	var convoy := icebreaker.convoy.filter(func(ship: Ship) -> bool: return ship.escort == icebreaker and ships.has(ship))
	var slowest := icebreaker.speed()
	for ship: Ship in convoy:
		slowest = minf(slowest, maxf(ship.speed(), ship.top_speed() * 0.2))
	var speed := slowest * icebreaking.escort_factor(icebreaker)
	var moved := minf(speed * delta, end - icebreaker.traveled_nm)
	_burn(icebreaker, moved, speed)
	icebreaker.traveled_nm += moved
	var through := icebreaker.traveled_nm >= end - 0.001
	var done := through
	for ship: Ship in convoy:
		var limit := end if through else icebreaker.traveled_nm - icebreaking.gap_nm() * (ship.escort_place + 1)
		var next := clampf(minf(ship.traveled_nm + speed * delta, limit), ship.traveled_nm, end)
		_burn(ship, next - ship.traveled_nm, speed)
		ship.traveled_nm = next
		if next < end - 0.001:
			done = false
	if not done:
		return
	var length := GameData.distance_nm(leg[0], leg[1])
	var arrived := end >= length - 0.01
	for ship: Ship in convoy:
		ship.escort = null
		ship.weather_wait = ""
		if arrived:
			_arrive(ship, leg[1])
		else:
			ship_changed.emit(ship)
	icebreaker.convoy.clear()
	if arrived:
		icebreaker.ice_phase = ""
		_arrive(icebreaker, leg[1], false)
	else:
		# Turn round (a turning circle, not a pivot) before heading back.
		icebreaker.ice_phase = "turn_back"
		icebreaker.align_time = 0.0


## True if an icebreaker at the head of its convoy is facing more than a right
## angle off the way it's to lead it (it came in through the far end of the
## lane), so it must turn first.
func _escort_turn_needed(icebreaker: Ship) -> bool:
	var here = GameData.lane(icebreaker.from_port, icebreaker.to_port)
	var leg := icebreaker.escort_leg
	var ahead = GameData.lane(leg[0], leg[1])
	if here == null or ahead == null:
		return false
	var facing: Vector2 = here.sample(icebreaker.traveled_nm)[1]
	var going: Vector2 = ahead.sample(float(leg[2]))[1]
	return absf(facing.angle_to(going)) > PI / 2.0


## Fuel and wear for miles made at a speed (a convoy's pace, not the ship's
## own), so a slow convoy costs no more per mile than sailing alone.
func _burn(ship: Ship, miles: float, speed: float) -> void:
	if miles <= 0.0 or speed <= 0.0:
		return
	var seconds := miles / maxf(ship.speed(), speed)
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * seconds, 0.0)
	ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * seconds, 0.01)
	if not ship.is_service():
		ship.sea_time += seconds


# --- Tugs ------------------------------------------------------------------

## The ports on a company's (this player's by default) cargo ships' routes (and routes they'll take up
## after this leg), sorted: each takes tugs_per_port() tugs.
func tug_ports(of: Company = null) -> Array[String]:
	var ports := {}
	for ship in fleet(of):
		if ship.is_service():
			continue
		for port_id in ship.route:
			ports[port_id] = true
		for port_id in ship.pending_route:
			ports[port_id] = true
	var out: Array[String] = []
	out.assign(ports.keys())
	out.sort()
	return out


## How many tugs each port on the routes takes (game_config tugs per_port).
func tugs_per_port() -> int:
	return int(GameData.config.get("tugs", {}).get("per_port", 2))


## How many tugs the company can own: tugs_per_port() for each port on its routes.
func tug_slots(of: Company = null) -> int:
	return tug_ports(of).size() * tugs_per_port()


## A company's tugs based at a port.
func tugs_at(port_id: String, of: Company = null) -> Array:
	return fleet(of).filter(func(ship: Ship) -> bool: return ship.is_tug() and ship.base_port == port_id)


## Where a new tug is based: the route port with the fewest tugs, the busiest
## first (on the most ships' routes), so they spread evenly. "" if there's none.
func tug_port_for_new(of: Company = null) -> String:
	var ports := tug_ports(of)
	var count := _tug_counts(ports, of)
	var busy := {}
	for ship in fleet(of):
		for port_id in ship.route:
			busy[port_id] = int(busy.get(port_id, 0)) + 1
	ports.sort_custom(func(a: String, b: String) -> bool:
		if count[a] != count[b]:
			return count[a] < count[b]
		return int(busy.get(a, 0)) > int(busy.get(b, 0)))
	return ports[0] if not ports.is_empty() else ""


func _tug_counts(ports: Array[String], of: Company = null) -> Dictionary:
	var count := {}
	for port_id in ports:
		count[port_id] = 0
	for ship in fleet(of):
		if ship.is_tug() and count.has(ship.base_port):
			count[ship.base_port] += 1
	return count


## Keeps tugs on the routes: a tug based at a port no longer on any route (or
## one over its port's share) is re-based to the nearest route port still
## short of tugs that a full tank can reach, and sails there once it's free.
## One with nowhere to go stays put.
func _rebalance_tugs() -> void:
	for who in all_companies():
		_rebalance_tugs_of(who)


func _rebalance_tugs_of(of: Company) -> void:
	var ports := tug_ports(of)
	var count := _tug_counts(ports, of)
	var kept := {}
	var surplus := []
	for ship in fleet(of):
		if not ship.is_tug():
			continue
		if count.has(ship.base_port) and int(kept.get(ship.base_port, 0)) < tugs_per_port():
			kept[ship.base_port] = int(kept.get(ship.base_port, 0)) + 1
		else:
			surplus.append(ship)
	for tug: Ship in surplus:
		var here: String = tug.docked_at if tug.is_docked() else (tug.tow_port if tug.is_on_job() else tug.to_port)
		var best := ""
		for port_id in ports:
			if int(kept.get(port_id, 0)) >= tugs_per_port() or not (port_id == here or tug.can_reach(here, port_id)):
				continue
			if best.is_empty() or GameData.distance_nm(here, port_id) < GameData.distance_nm(here, best):
				best = port_id
		if best.is_empty():
			continue
		kept[best] = int(kept.get(best, 0)) + 1
		if tug.base_port != best:
			tug.base_port = best
			ship_changed.emit(tug)


## Each tug's share of towing: game_config tugs tow_factor x its speed.
func _tow_speed(tug: Ship) -> float:
	var speed := maxf(tug.speed(), tug.top_speed() * MIN_RECOVERY_SPEED_FACTOR)
	return speed * float(GameData.config.get("tugs", {}).get("tow_factor", 0.5))


## The tugs that would fetch a lost ship: the free ones (docked at their base,
## with the reach and fuel) based at the nearer end of its leg they can reach
## it from, up to tugs_per_port(). {tugs (lead first), tow_port, miles (from
## the tugs' port), seconds, cost}, or {} if none can.
func tug_plan(lost: Ship) -> Dictionary:
	if not lost.is_lost() or lost.rescuer != null or lost.from_port.is_empty():
		return {}
	var ends := [[lost.from_port, lost.traveled_nm], [lost.to_port, lost.leg_length() - lost.traveled_nm]]
	ends.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
	for end: Array in ends:
		var port: String = end[0]
		var miles: float = maxf(float(end[1]), 0.0)
		var team: Array = ships.filter(func(tug: Ship) -> bool:
			return tug.is_tug() and owner_of(tug) == owner_of(lost) and tug.base_port == port and tug.docked_at == port and not tug.is_docking() \
				and not tug.is_on_job() and tug.reach_nm() >= miles and tug.fuel >= _tug_fuel(tug, miles))
		if team.is_empty():
			continue
		team = team.slice(0, tugs_per_port())
		var tow := 0.0
		var approach := 0.0
		for tug: Ship in team:
			tow += _tow_speed(tug)
			approach = maxf(approach, miles / maxf(tug.speed(), 0.01))
		var seconds := approach + TUG_STAGGER_S * (team.size() - 1) + Ship.ALIGN_SECONDS + miles / tow
		var cost := 0.0
		for tug: Ship in team:
			cost += tug.fuel_per_s() * seconds * market.fuel_price(port) \
				+ minf(tug.wear_per_s() * seconds, 1.0) * tug.full_repair_cost() * port_sizes.cost_factor(port)
		return {tugs = team, tow_port = port, miles = miles, seconds = seconds, cost = cost}
	return {}


## Fuel a tug needs to fetch a ship `miles` out: out there, and back towing it
## on its own (the slow case), plus a little spare.
func _tug_fuel(tug: Ship, miles: float) -> float:
	var seconds := miles / maxf(tug.speed(), 0.01) + Ship.ALIGN_SECONDS + miles / maxf(_tow_speed(tug), 0.01)
	return tug.fuel_per_s() * (seconds + DEPARTURE_MARGIN_S)


## Sends a tug_plan()'s tugs out along the lost ship's lane from their port.
func _send_tugs(lost: Ship, plan: Dictionary, auto: bool) -> void:
	var port: String = plan.tow_port
	var other := lost.to_port if port == lost.from_port else lost.from_port
	var miles: float = plan.miles
	var back := GameData.distance_nm(other, port)
	var team: Array = plan.tugs
	for i in team.size():
		var tug: Ship = team[i]
		tug.rescuing = lost
		tug.tug_lead = i == 0
		tug.tow_port = port
		tug.job_segments = [[other, port, back - miles, back]]
		tug.job_nm = miles * 2.0
		tug.carry_nm = miles
		tug.align_time = 0.0
		# They head out one after the other (see _advance_tug_job()), in line.
		tug.tug_wait = TUG_STAGGER_S * i
		tug.job_phase = Ship.JOB_APPROACH
		ship_changed.emit(tug)
	lost.rescuer = team[0]
	recovery_sent.emit(lost, team[0], roundi(plan.cost), auto)
	ship_changed.emit(lost)


## A tug on a job: it sails out to the lost ship and turns round there; once
## every tug on the job has, the lead one tows it in at all their tow speeds
## added up (the other pushing at its stern), each burning fuel and wearing as
## it goes, and hands it over at their port.
func _advance_tug_job(tug: Ship, delta: float) -> void:
	match tug.job_phase:
		Ship.JOB_APPROACH:
			if tug.is_docked():
				# Still in port: sets off once its turn comes, along the lost
				# ship's lane (the way back it'll tow it, reversed).
				tug.tug_wait -= delta
				if tug.tug_wait > 0.0:
					return
				var tow: Array = tug.job_segments[0]
				_leave_port(tug)
				tug.docked_at = ""
				_start_segment(tug, [tow[1], tow[0], 0.0, float(tow[3]) - float(tow[2])])
				ship_changed.emit(tug)
				return
			_sail(tug, delta)
			if tug.traveled_nm >= tug.segment_end:
				tug.traveled_nm = tug.segment_end
				canal_traffic.leave(tug)
				tug.job_phase = Ship.JOB_ALIGN
				tug.align_time = 0.0
				ship_changed.emit(tug)
		Ship.JOB_ALIGN:
			tug.align_time += delta
			if not tug.tug_lead:
				return
			var team := tug.tug_team()
			if not team.all(func(each: Ship) -> bool: return each.tug_ready()):
				return
			for each in team:
				each.job_phase = Ship.JOB_TOW
				_start_segment(each, each.job_segments[0])
				canal_traffic.leave(each)  # Towing near port: no lock queues.
				ship_changed.emit(each)
			ship_changed.emit(tug.rescuing)
		Ship.JOB_TOW:
			if not tug.tug_lead:
				return  # Its lead moves the pair (see below).
			var team := tug.tug_team()
			var speed := 0.0
			for each in team:
				speed += _tow_speed(each)
			var target := minf(tug.traveled_nm + speed * delta, tug.segment_end)
			for each in team:
				each.traveled_nm = target
				each.fuel = maxf(each.fuel - each.fuel_per_s() * delta, 0.0)
				each.maintenance = maxf(each.maintenance - each.wear_per_s() * delta, 0.01)
			if target >= tug.segment_end:
				_deliver_tugs(tug, team)


## Hands the towed ship over at the tugs' port (paid as usual if that's where
## it was going), docks the tugs there, and gives each its XP.
func _deliver_tugs(lead: Ship, team: Array[Ship]) -> void:
	var lost := lead.rescuing
	var port := lead.tow_port
	var to_destination := port == lost.to_port
	ship_recovered.emit(lost, lead, port, to_destination)  # While the team's still together, for its names.
	var settings: Dictionary = GameData.config.get("recovery_xp", {})
	var cargo: Array = lost.model().get("cargo", [])
	for tug in team:
		var boat := tug.job_nm * float(settings.get("per_nm", 1.0))
		var company := 0.0
		if tug == lead and not cargo.is_empty():
			company = Progression.xp_for_cargo(lost.capacity(), cargo[0], tug.carry_nm) * float(settings.get("company_share", 1.0))
		tug.rescuing = null
		tug.job_phase = Ship.JOB_NONE
		tug.job_segments.clear()
		tug.tow_port = ""
		tug.tug_lead = false
		tug.job_nm = 0.0
		tug.carry_nm = 0.0
		_arrive(tug, port, false)
		if boat > 0.0:
			_gain_xp(tug, boat, 1.0, company / boat)
	lost.rescuer = null
	lost.lost_reason = ""
	_arrive(lost, port, to_destination)


# --- Canals ----------------------------------------------------------------

## Extra money on a profitable trade from a leg's bonuses: the profit x (the
## leg's sale factor (rough seas, upper lakes) x the destination hub's Pay
## upgrade x the model's mega upgrade, if it has one - 1). Nothing on a loss.
func trade_bonus(from_port: String, to_port: String, profit: float, model_id := "", of: Company = null) -> float:
	if profit <= 0.0:
		return 0.0
	var who := of if of != null else company
	var mega := 1.0 + (float(GameData.config.get("mega", {}).get("profit_bonus", 0.5)) if who.has_mega(model_id) else 0.0)
	return profit * (GameData.sale_factor(from_port, to_port) * (1.0 + who.hub_bonus(to_port, "pay")) * mega - 1.0)


## Money cargo purchases leave alone so no ship is stranded for fuel: what
## topping up every ship's tank would cost at the port it's at or heading to (a
## cargo ship at sea counting the fuel it will burn to get there). A buffer, so
## it's worked out at most every FUEL_RESERVE_REFRESH_S of game time: with a big
## fleet it's costly, and ships buying cargo ask for it many times a second.
func fuel_reserve(of: Company = null) -> float:
	var who := of if of != null else company
	if who.fuel_reserve_time >= 0.0 and play_time >= who.fuel_reserve_time and play_time - who.fuel_reserve_time < FUEL_RESERVE_REFRESH_S:
		return who.fuel_reserve
	var total := 0.0
	var prices := {}  # Port -> fuel price, looked up once each (many ships share ports).
	for ship in fleet(who):
		var port := ship.docked_at if ship.is_docked() else ship.to_port
		if port.is_empty():
			continue
		var fuel_left := ship.fuel
		if not ship.is_docked() and not ship.is_service() and not ship.from_port.is_empty():
			# The rest of the leg at its speed now: near enough for a buffer, and
			# far quicker than leg_seconds() for every ship at sea.
			var seconds := (ship.leg_length() - ship.traveled_nm) / maxf(ship.speed(), 0.01)
			fuel_left -= ship.fuel_per_s() * seconds
		var missing := clampf(ship.fuel_tank() - fuel_left, 0.0, ship.fuel_tank())
		if missing <= 0.0:
			continue
		if not prices.has(port):
			prices[port] = market.fuel_price(port)
		total += missing * float(prices[port])
	who.fuel_reserve = total
	who.fuel_reserve_time = play_time
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
	var stats: Dictionary = owner_of(ship).canal_stats.get_or_add(canal.id, {crossings = 0, tolls = 0.0, xp = 0.0})
	stats.crossings = int(stats.crossings) + 1
	stats.tolls = float(stats.tolls) + toll


# --- Recovery --------------------------------------------------------------

## How the nearest free recovery boat able to carry a lost ship (the cheapest,
## if two are as near) would recover it: {mammoth, segments, tow_port, approach_nm, seconds, fuel, cost}, or
## {error} saying why none can.
func recovery_plan(lost: Ship) -> Dictionary:
	if not lost.is_lost() or lost.rescuer != null:
		return {error = "This ship doesn't need recovering."}
	# Free tugs near enough come first: closer, quicker and cheaper.
	var tugs := tug_plan(lost)
	if not tugs.is_empty():
		return tugs
	var own := fleet(owner_of(lost))  # A company recovers its own ships.
	var capable := own.filter(func(ship: Ship) -> bool:
		return ship.can_carry(lost) and ship.fits_lane(lost.from_port, lost.to_port))
	if capable.is_empty():
		var model_name: String = lost.model().get("name", lost.model_id)
		if own.any(func(ship: Ship) -> bool: return ship.is_recovery()):
			return {error = "Only a Mammoth can carry a %s. Buy one in the Shop." % model_name}
		if own.any(func(ship: Ship) -> bool: return ship.is_tug()):
			return {error = "No free tug is based near enough. Buy a Mammoth or Buffalo in the Shop to recover ships further out."}
		return {error = "Buy a Mammoth or Buffalo in the Shop to recover lost ships (or tugs, for ships lost near your ports)."}
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
	var plan := recovery_plan(lost)
	if plan.has("error"):
		return plan.error
	if Net.command(&"send_recovery", [lost]):
		return ""
	return _send_recovery(lost, false)


## Sends the nearest free capable boat; auto says whether auto-recovery sent it.
func _send_recovery(lost: Ship, auto: bool) -> String:
	var plan := recovery_plan(lost)
	if plan.has("error"):
		return plan.error
	if plan.has("tugs"):
		_send_tugs(lost, plan, auto)
		return ""
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
		seconds = seconds + Ship.ALIGN_SECONDS + Ship.LOAD_SECONDS * 2.0 + (Ship.SPIN_SECONDS if (tow_port == a) == (via_a <= via_b) else 0.0),
		fuel = mammoth.fuel_per_s() * (seconds + DEPARTURE_MARGIN_S),
		cost = mammoth.fuel_per_s() * running * market.fuel_price(mammoth.docked_at)
			+ minf(mammoth.wear_per_s() * running, 1.0) * mammoth.full_repair_cost() * port_sizes.cost_factor(mammoth.docked_at),
	}


func _start_segment(ship: Ship, segment: Array) -> void:
	ship.from_port = segment[0]
	ship.to_port = segment[1]
	ship.traveled_nm = segment[2]
	ship.segment_end = segment[3]
	ship.storm_check_time = 0.0
	canal_traffic.start_leg(ship)


## A recovery boat on a job: sail to the lost ship, line up with it and take it
## aboard (see Ship.LOAD_SECONDS), carry it to port and float it off there.
func _advance_job(mammoth: Ship, delta: float) -> void:
	if mammoth.job_phase == Ship.JOB_UNLOAD:
		mammoth.align_time += delta
		if mammoth.align_time >= Ship.LOAD_SECONDS:
			_deliver(mammoth)
		return
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
		# At the port: ballast down and float the ship off before handing it over.
		mammoth.job_phase = Ship.JOB_UNLOAD
		mammoth.align_time = 0.0
		ship_changed.emit(mammoth)
	elif mammoth.job_segments.size() > 1:
		_start_segment(mammoth, mammoth.job_segments.pop_front())
	else:
		mammoth.job_phase = Ship.JOB_ALIGN
		mammoth.align_time = 0.0
		# Met head on (sailing towards the end it came from): it floats aboard stern first.
		mammoth.carry_reversed = mammoth.to_port == mammoth.rescuing.from_port
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
	var cost := amount * ship.full_repair_cost() * port_sizes.cost_factor(ship.docked_at) * (1.0 - hub_bonus(ship.docked_at, "costs", owner_of(ship)))
	var paid := _spend(ship, cost, "repair")
	ship.stop_repair_cost += paid
	ship.maintenance = minf(ship.maintenance + amount * paid / cost, 1.0)


## Adds up to `amount` of fuel, as far as money allows.
func _refuel(ship: Ship, amount: float) -> void:
	amount = minf(amount, ship.fuel_tank() - ship.fuel)
	if amount <= 0.0:
		return
	var cost := amount * market.fuel_price(ship.docked_at) * (1.0 - hub_bonus(ship.docked_at, "costs", owner_of(ship)))
	var paid := _spend(ship, cost, "fuel")
	ship.stop_fuel_cost += paid
	ship.fuel = minf(ship.fuel + amount * paid / cost, ship.fuel_tank())


## Spends up to `cost` dollars of a kind ("fuel" or "repair") without going
## below $0 and returns what was spent. Money is whole dollars, so fractions
## build up on the ship's bill.
func _spend(ship: Ship, cost: float, kind: String) -> float:
	if cost <= 0.0:
		return 0.0
	var paid := minf(cost, float(owner_of(ship).money) - ship.bill)
	if paid <= 0.0:
		return 0.0
	_record(ship, kind, paid)
	ship.bill += paid
	var whole := floori(ship.bill)
	if whole > 0:
		ship.bill -= whole
		_add_money(owner_of(ship), -whole)
	return paid


func _can_spend(ship: Ship) -> bool:
	return float(owner_of(ship).money) - ship.bill > 0.0


## Length of the overlap between the time spans [a0, a1) and [b0, b1).
static func _overlap(a0: float, a1: float, b0: float, b1: float) -> float:
	return maxf(minf(a1, b1) - maxf(a0, b0), 0.0)


# --- Finances ------------------------------------------------------------

## Tallies money of a kind (see MONEY_KINDS) for a ship (null for a company as
## a whole: buying and selling ships, hub upgrades), in its company's finances
## (who's, or else the ship's, or else this player's). Recovery boats pay for
## their own fuel and repairs.
func _record(ship: Ship, kind: String, amount: float, who: Company = null) -> void:
	if who == null:
		who = owner_of(ship) if ship else company
	who.totals[kind] = float(who.totals.get(kind, 0.0)) + amount
	var bucket := _current_bucket(who)
	bucket.fleet[kind] = float(bucket.fleet.get(kind, 0.0)) + amount
	if ship:
		ship.ledger[kind] = float(ship.ledger.get(kind, 0.0)) + amount
		var tally: Dictionary = bucket.ships.get_or_add(ship.name, {})
		tally[kind] = float(tally.get(kind, 0.0)) + amount


## A company's (this player's by default) bucket of recent money for now.
func _current_bucket(of: Company = null) -> Dictionary:
	var window := (of if of != null else company).finance_window
	var start := floorf(play_time / BUCKET_SECONDS) * BUCKET_SECONDS
	if window.is_empty() or window[-1].start < start:
		window.append({start = start, fleet = {}, ships = {}})
	while window[0].start < play_time - WINDOW_SECONDS:
		window.pop_front()
	return window[-1]


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
	for bucket: Dictionary in company.finance_window:
		if bucket.start < play_time - WINDOW_SECONDS:
			continue
		for kind: String in bucket.fleet:
			fleet[kind] = float(fleet.get(kind, 0.0)) + bucket.fleet[kind]
		for ship_name: String in bucket.ships:
			var tally: Dictionary = bucket.ships[ship_name]
			var costs := float(tally.get("fuel", 0.0)) + float(tally.get("repair", 0.0)) + float(tally.get("tolls", 0.0)) + float(tally.get("cargo", 0.0))
			ship_profit[ship_name] = float(ship_profit.get(ship_name, 0.0)) + float(tally.get("income", 0.0)) - costs
	return {fleet = fleet, ships = ship_profit}




# --- Multiplayer -----------------------------------------------------------

## True if a ship is this player's.
func is_mine(ship: Ship) -> bool:
	return owner_of(ship) == company


func ship_by_id(id: int) -> Ship:
	for ship in ships:
		if ship.id == id:
			return ship
	return null


## Why a company can't be founded in this game with a name and home port, or
## "": every company has its own home port.
func found_company_error(new_name: String, new_home_port: String) -> String:
	if new_name.strip_edges().is_empty():
		return "Enter a company name."
	if GameData.get_port(new_home_port).is_empty():
		return "Pick a home port."
	for each in all_companies():
		if each.home_port == new_home_port:
			return "%s is already %s's home port: pick another." % [GameData.port_name(new_home_port), each.name]
		if each.name.to_lower() == new_name.strip_edges().to_lower():
			return "There's already a company called %s." % each.name
	return ""


## Founds a company in this game (a joining player's), with the starting money
## and its HQ at its home port. Returns its place in companies.
func found_company(new_name: String, new_color: String, new_home_port: String) -> int:
	var founded := Company.new(new_name.strip_edges().left(MAX_COMPANY_NAME_LENGTH), new_color, new_home_port)
	founded.money = int(GameData.config.get("starting_money", 10000))
	founded.hubs.assign([Hub.new(new_home_port, true)])
	if companies.is_empty():
		companies.assign([company])
	companies.append(founded)
	save_game()
	return companies.size() - 1


## A joined player's own map and log settings (Company.PREF_KEYS), kept in the
## host's save.
func set_prefs(prefs: Dictionary) -> void:
	var kept := {}
	for key in Company.PREF_KEYS:
		if prefs.has(key):
			kept[key] = prefs[key]
	company.apply_update(kept)


## A joined game's session: the world comes from the host (see Net), so it
## doesn't run or save it.
func begin_client_session() -> void:
	ActivityLog.clear()
	in_session = true


## A joined game's frame: the clock and the ships move on smoothly between the
## host's updates (each sailing ship at its speed as of the last ones), and
## this player's storm and season warnings are looked at as in single player.
func _client_frame(delta: float) -> void:
	play_time += delta * time_speed
	for ship in ships:
		if ship.berth_phase == Ship.BERTH_IN or ship.berth_phase == Ship.BERTH_OUT:
			ship.berth_time += delta * time_speed  # Coming alongside or pulling out, smoothly between updates.
		if ship.is_docked() or ship.from_port.is_empty():
			continue
		var rate := Net.ship_rate(ship)
		if rate > 0.0:
			var end := ship.segment_end if ship.is_on_job() and ship.segment_end > 0.0 else ship.leg_length()
			ship.traveled_nm = minf(ship.traveled_nm + rate * delta, maxf(end, ship.traveled_nm))
	_storm_warning_clock += delta * time_speed
	if _storm_warning_clock >= STORM_WARNING_CHECK_S:
		_storm_warning_clock = 0.0
		_storm_warnings()
		_season_warnings()
# --- Saving --------------------------------------------------------------

func save_path(slot: int, online := multiplayer_save) -> String:
	return ("user://save_mp_%d.json" if online else "user://save_%d.json") % slot


func has_save(slot: int, online := multiplayer_save) -> bool:
	return FileAccess.file_exists(save_path(slot, online))


## What the main menu shows for a slot: {company_name, company_color,
## home_port (id), max_time_speed, storms, seasons, money, date (calendar Unix
## time)}, plus error if it can't be loaded; {} if empty.
func save_summary(slot: int, online := multiplayer_save) -> Dictionary:
	if not has_save(slot, online):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path(slot, online)))
	if typeof(data) != TYPE_DICTIONARY:
		return {error = "Unreadable save"}
	# This player's company (a save from before companies holds its one at the top).
	var mine: Dictionary = data
	var list: Array = data.get("companies", [])
	if not list.is_empty():
		mine = list[clampi(int(data.get("local_company", 0)), 0, list.size() - 1)]
	var summary := {
		company_name = str(mine.get("company_name", "")),
		company_color = str(mine.get("company_color", "purple")),
		home_port = str(mine.get("home_port", "")),
		max_time_speed = int(data.get("max_time_speed", TIME_SPEEDS[-1])),
		storms = str(data.get("storms", "none")),
		seasons = bool(data.get("seasons", false)),
		money = int(mine.get("money", 0)),
		date = calendar_time_at(float(data.get("play_time", 0.0))),
		companies = maxi(list.size(), 1),
	}
	if int(data.get("version", 0)) != SAVE_VERSION:
		summary.error = "Old save, can't be loaded"
	return summary


func delete_save(slot: int, online := multiplayer_save) -> void:
	DirAccess.remove_absolute(save_path(slot, online))


## The single save from before slots moves into slot 1.
func _migrate_legacy_save() -> void:
	if FileAccess.file_exists(LEGACY_SAVE_PATH) and not has_save(1, false):
		DirAccess.rename_absolute(LEGACY_SAVE_PATH, save_path(1, false))


## Starts a new company in save_slot, replacing any save there. options (all
## optional): tutorials (bool), max_time_speed (one of TIME_SPEEDS), storms
## (one of Weather.LEVELS) and seasons (bool: seasonal closures).
func new_game(new_company_name: String, new_home_port: String, new_color := "purple", options := {}) -> void:
	company = Company.new(new_company_name.strip_edges(), new_color, new_home_port)
	company.money = int(GameData.config.get("starting_money", 10000))
	company.tutorials = bool(options.get("tutorials", false))
	company.hubs.assign([Hub.new(new_home_port, true)])
	companies.assign([company])
	_clear_ships()
	next_ship_id = 1
	play_time = 0.0
	canal_traffic.clear()
	market.clear()
	port_sizes.reset()
	max_time_speed = int(options.get("max_time_speed", TIME_SPEEDS[-1]))
	storms = str(options.get("storms", "none"))
	seasons = bool(options.get("seasons", false))
	weather.clear()
	money_changed.emit(money)
	_begin_session()
	save_game()


## Loads a slot's save and starts a session saving to it. Returns why it
## couldn't, or "". A save from before companies loads as its one company.
func continue_game(slot: int) -> String:
	var path := save_path(slot)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameState: save file %s is missing or corrupt" % path)
		return "The saved game could not be read."
	if int(data.get("version", 0)) != SAVE_VERSION:
		return "This save is from before commodity trading and can't be loaded. Delete it to start a new game in this slot."
	save_slot = slot
	load_world(data)
	_begin_session()
	return ""


## Loads a world_dict() (a save, or the host's game when joining one), with
## this player's company the one at `local` (the save's own if -1). Saves from
## before companies load as their one company.
func load_world(data: Dictionary, local := -1) -> void:
	companies.clear()
	for company_data: Dictionary in data.get("companies", [data]):
		companies.append(Company.from_dict(company_data))
	company = companies[clampi(local if local >= 0 else int(data.get("local_company", 0)), 0, companies.size() - 1)]
	_clear_ships()
	play_time = float(data.get("play_time", 0.0))
	market.from_dict(data.get("market", {}))
	var had_port_sizes := port_sizes.from_dict(data.get("port_sizes", {}))
	max_time_speed = int(data.get("max_time_speed", TIME_SPEEDS[-1]))
	# Saves from before weather have no storms or seasonal closures.
	storms = str(data.get("storms", "none"))
	seasons = bool(data.get("seasons", false))
	weather.from_dict(data.get("weather", {}))
	next_ship_id = int(data.get("next_ship_id", 1))
	for ship_data: Dictionary in data.get("ships", []):
		var ship := Ship.from_dict(ship_data)
		ship.company = companies[clampi(int(ship_data.get("company", 0)), 0, companies.size() - 1)]
		if ship.id <= 0:  # Saves from before ship ids.
			ship.id = next_ship_id
			next_ship_id += 1
		next_ship_id = maxi(next_ship_id, ship.id + 1)
		ships.append(ship)
	Ship.link_rescues(ships)
	for ship in ships:
		ship.invalidate_stats()  # Skills and mega upgrades are all loaded now.
	canal_traffic.rebuild(ships)
	docks.rebuild(ships)
	for ship in ships:
		if ship.is_recovery() and ship.base_port.is_empty():  # Saves from before bases.
			ship.base_port = owner_of(ship).home_port
	if not had_port_sizes:
		_fit_ports_to_routes()
	_rebalance_recovery_boats()
	_rebalance_tugs()
	money_changed.emit(money)


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
	if not in_session or Net.is_client():
		return  # A joined player's game is the host's to save.
	var file := FileAccess.open(save_path(save_slot), FileAccess.WRITE)
	if file == null:
		push_error("GameState: could not write save (%s)" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(world_dict(), "\t"))


## The whole game as a save holds it: the world, every company (and which is
## this player's) and every ship (with its company's place in the list).
func world_dict() -> Dictionary:
	var all := all_companies()
	return {
		"version": SAVE_VERSION,
		"multiplayer": multiplayer_save,
		"companies": all.map(func(each: Company) -> Dictionary: return each.to_dict()),
		"local_company": all.find(Net.acting_for if Net.acting_for != null else company),
		"next_ship_id": next_ship_id,
		"play_time": play_time,
		"max_time_speed": max_time_speed,
		"storms": storms,
		"seasons": seasons,
		"weather": weather.to_dict(),
		"market": market.to_dict(),
		"port_sizes": port_sizes.to_dict(),
		"ships": ships.map(func(ship: Ship) -> Dictionary:
			var ship_data := ship.to_dict()
			ship_data["company"] = maxi(all.find(owner_of(ship)), 0)
			return ship_data),
	}


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
	icebreaking.refresh(true)
	_autosave_timer.start()

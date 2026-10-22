# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
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
signal cargo_sold(ship: Ship, port_id: String, commodity_id: String, quantity: int, cost: int, sale: int, tolls: int, fee: int)
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
## A storm battered a ship lying at anchor (see _batter_anchored()).
signal ship_battered(ship: Ship, storm: Dictionary)
## A company paid its crews (see _check_payday()): one of its ships (so it goes
## to its player in multiplayer), the total and how many ships.
signal wages_paid(ship: Ship, total: int, ship_count: int)
## A ship ran out of fuel or maintenance at sea.
signal ship_lost(ship: Ship)
## A Mammoth dropped a lost ship at a port (its destination, or back where it came from).
signal ship_recovered(ship: Ship, mammoth: Ship, port_id: String, to_destination: bool)
## A recovery boat left a ship within its port's tugs' reach for them to tow in.
signal tugs_handed(ship: Ship, boat: Ship, port_id: String)
## A recovery boat was sent to a lost ship (automatically, if auto is true).
signal recovery_sent(ship: Ship, boat: Ship, cost: int, auto: bool)
## A ship at sea no longer has the fuel or maintenance to reach port.
signal ship_at_risk(ship: Ship)
## A ship was sold.
signal ship_sold(ship: Ship, price: int)
## The HQ or a hub was built or changed.
signal hubs_changed
## A new hub was founded at a port.
signal hub_built(hub: Hub)
## A company took another company type (this player's, or a company's in multiplayer).
signal company_types_changed
## A company changed its logo.
signal logo_changed
## A company's rating in a type reached a new whole star (up) or fell to one (see Ratings).
signal rating_changed(company: Company, type_id: String, star: int, up: bool)
## A port grew or shrank into a new size band (see PortSizes).
signal port_band_changed(port_id: String, band: String, grew: bool)
## The fast-forward speed changed.
signal time_speed_changed(speed: int)

## Each save slot is its own file (see save_path()).
const SAVE_SLOTS := 3
## The one save from before slots; it becomes slot 1.
const LEGACY_SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 4
const MAX_NAME_LENGTH := 24
const MAX_COMPANY_NAME_LENGTH := 32
## Seconds of spare fuel a ship must have beyond what its next leg needs.
const DEPARTURE_MARGIN_S := 1.0
## A worn-out Mammoth still crawls at this fraction of top speed, so it can always finish a job.
const MIN_RECOVERY_SPEED_FACTOR := 0.05
## The finances window: money is tallied in buckets this many seconds long,
## kept for as long as the longest window: WINDOW_SECONDS (the company's
## recent figures: Finances) or the ships' own,
## SHIP_EARNINGS_DAYS of calendar time (each ship's earnings on the Ships tab).
const BUCKET_SECONDS := 30.0
const WINDOW_SECONDS := 600.0
const SHIP_EARNINGS_DAYS := 30.0
## How often lost ships with auto-recovery on look for a free boat.
const AUTO_RECOVERY_INTERVAL := 0.5
## Kinds of money tallied in the finances.
const MONEY_KINDS: Array[String] = ["income", "cargo", "fuel", "repair", "tolls", "port_fees", "wages", "interest", "bought", "sold", "hubs", "hub_upkeep", "divisions", "upgrades", "logo", "supplies", "land", "land_sold", "farms", "farm_sales", "factories", "factory_sales", "energy_built", "energy_sold", "energy", "energy_sales", "industry", "industry_sales", "research_pay", "research_gear", "research_penalty"]
## Game speeds the top bar button cycles through (0 = paused).
const TIME_SPEEDS: Array[int] = [0, 1, 2, 4, 8]
## The longest step fast forward takes (s of play): at 4x and 8x a frame runs
## fewer, longer steps (never more than time_speed of them), each no longer
## than a 1x frame at about 28 fps, which the game takes in its stride
## anyway. Each step costs about the same however long, so 8x at 60 fps runs
## 4 steps a frame rather than 8.
const MAX_STEP_S := 0.036
## The hidden gems: three spots on the map that each pay HIDDEN_GEM_MONEY, once
## per company, when clicked (see claim_hidden_gem()): a wonder's picture
## (wonder, a WonderPopup id) or a stretch of land ((lon, lat) area, clicked on
## the land: MapView.gem_at()). Finding them earns the Hidden gems line's stars.
const HIDDEN_GEM_MONEY := 10000000
const HIDDEN_GEMS := {
	"giza": {name = "the Great Pyramid of Giza", wonder = "great_pyramid"},
	"oregon": {name = "Oregon", area = [
		Vector2(-124.8, 42.0), Vector2(-124.8, 42.8), Vector2(-124.4, 44.0), Vector2(-124.3, 45.0), Vector2(-124.2, 46.0),
		Vector2(-123.9, 46.25), Vector2(-123.4, 46.18), Vector2(-123.0, 46.1), Vector2(-122.8, 45.85), Vector2(-122.75, 45.65),
		Vector2(-122.3, 45.55), Vector2(-121.2, 45.65), Vector2(-120.6, 45.75), Vector2(-119.6, 45.92), Vector2(-119.0, 46.0),
		Vector2(-116.92, 46.0), Vector2(-116.47, 45.6), Vector2(-116.78, 45.1), Vector2(-117.0, 44.75), Vector2(-117.24, 44.3),
		Vector2(-117.03, 44.0), Vector2(-117.03, 42.0)]},
	"talkeetna": {name = "the Talkeetna Mountains", area = [
		Vector2(-150.1, 62.3), Vector2(-150.0, 61.75), Vector2(-148.9, 61.65), Vector2(-147.3, 61.8), Vector2(-146.4, 62.2),
		Vector2(-146.8, 62.7), Vector2(-148.0, 63.0), Vector2(-149.4, 62.75)]},
}
## A hub's warehouse for a commodity, built on its plots (see build_industry();
## until 2026-10-15 these were industry buildings, a toy factory or a steel
## mill): what it's called, by the commodity's unit or kind: stockyards for
## livestock, cold stores for seafood and fresh produce, terminals for oil and
## gas, warehouses for the rest.
const WAREHOUSE_KINDS := {head = "stockyard", crate = "cold store", pallet = "cold store", oil = "terminal", gas = "terminal"}
## How often (game seconds) a ship waiting in port for a full load looks again
## (it also looks as soon as the money reaches what it needed).
const LOAD_RECHECK_S := 2.0
## A cargo ship at the anchorage with nothing to load sets off straight from
## there only this fit (and with the fuel for its leg); otherwise it comes into
## port for repairs and fuel first (see _anchored_call()).
const DIRECT_DEPART_MAINTENANCE := 0.95
## How often (game seconds) a ship at sea checks it can still make port (see
## _check_at_risk()); a breakdown or a new leg checks at once.
const AT_RISK_CHECK_S := 1.0
## A ship done with its stop but not sailing yet waits at its pier while the
## port has at least this many berths free; otherwise it pulls out to the anchorage.
const WAIT_AT_PIER_FREE := 2
## How often (s of play) ships waiting at the anchorages are looked at, to
## come in to a pier where there's room.
const WAKE_WAITING_S := 2.0
## A ship bound for a port a storm has closed waits this far off it.
const STORM_OFFSHORE_NM := 25.0
## How often storm warnings are looked for, and how far ahead (in seconds of
## play: two calendar days) a storm heading for a port is warned of.
const STORM_WARNING_CHECK_S := 1.0
const STORM_WARNING_AHEAD_S := 144.0
## A storm over this strength (0..1) where a ship lies at anchor batters it,
## once, taking this much of its maintenance (see _batter_anchored()).
const STORM_BATTER_AT := 0.5
const STORM_BATTER := 0.2
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
## How often a ship at sea looks again for an icebreaker's ice area on its leg.
const ICE_HOLD_REFRESH_S := 0.5
## How often a ship in port looks again at whether a seasonal closure blocks its next leg.
const SEASON_RECHECK_S := 1.0
## How often a ship held in port because its next stop is beyond its reach,
## even refuelling on the way, looks again (the refuel stops are a search).
const REACH_RECHECK_S := 2.0
## How often (seconds of play) a docking ship is repaired and refueled (and
## pays for it).
const REFILL_BILL_S := 0.25
## Seconds between tugs leaving port on the same job, so they head out in line.
const TUG_STAGGER_S := 1.5
## How long (s) tugs stay with a ship that has to wait at the anchorage when
## there's no map to work it out (see anchor_route).
const TUG_ANCHOR_S := 10.0
## A recovery boat leaves a ship this share of its port's tugs' reach out (see _tug_handoff_nm()).
const TUG_HANDOFF_SHARE := 0.9

## Every company in the game (one in single player; see Company), and the one
## this player controls. The money, hubs... below are its: the
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
var home_port: String:
	get: return company.home_port
	set(value): company.home_port = value
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
## Set by the map: how long (s of play) a ship takes to sail its way into its
## berth (true) or out of it (false) at its own speed (see _berth_seconds()).
var berth_route := Callable()
## Set by the map: how long (s of play) tugs stay with a ship they've towed in
## that has to wait at the anchorage (see _deliver_tugs()).
var anchor_route := Callable()
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
## The last crew pay period paid (see _check_payday()), counted from the calendar's start.
var wage_period := 0
var play_time := 0.0
## The calendar's start (Unix time) and calendar seconds per second of play,
## read from game_config once (-1 until then).
var _calendar_start := -1
var _calendar_rate := 0.0

var _autosave_timer := Timer.new()
## The autosave being written off the main thread (a WorkerThreadPool task), or -1.
var _autosave_task := -1
var _breakdown_clock := 0.0
var _auto_recovery_clock := 0.0
## When ships waiting at the anchorages were last looked at (see _wake_waiting_ships()).
var _wake_clock := 0.0
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
## The living world: zones, people, producers, stockpiles and prices (see WorldEconomy).
var world := WorldEconomy.new(self)
## The world's AI shipping firms, on paper, carrying the zones' surpluses (see ShippingFirms).
var firms := ShippingFirms.new(self)
## The other firms' ships drawn on the map (see AmbientTraffic); not saved.
var traffic := AmbientTraffic.new(self)
## The world's price history (its own file beside the save) and the news (saved with the game).
var history := WorldHistory.new(self)
var news := News.new(self)
## Days the world runs before a new game begins, so ships are already at sea and
## the zones' stocks have settled (warm_up_world()).
const WARM_UP_DAYS := 90
var weather := Weather.new(self)
## Divine Actions (the game mode chosen at founding: see Divine); off in most games.
var divine := Divine.new(self)
var seasonal := Seasons.new(self)
var icebreaking := Icebreaking.new(self)
## Port sizes: how they grow and shrink, and what they change.
var port_sizes := PortSizes.new(self)
## Every port's berths and queue (see Docks).
var docks := Docks.new(self)
## Every company's star ratings by company type (see Ratings).
var ratings := Ratings.new(self)
## Cruise ships' voyages, bookings, prices and refits (see Cruises).
var cruises := Cruises.new(self)
## The farm ports' plots, crops, herds and weather years (see Farms).
var farms := Farms.new(self)
## A farm changed hands, was planted or stocked, or a day's harvest came in (see Farms).
signal farms_changed
## The oil and gas fields' rigs, the companies' buildings and stores (see Energy).
var energy := Energy.new(self)
## The Research type's contracts board, first discoveries and expeditions (see Research).
var research := Research.new(self)
## A research ship finished a site (first: no company had before), earning xp; a dive gone wrong (see Research).
signal research_discovered(ship: Ship, site_id: String, first: bool, xp: float)
signal research_mishap(ship: Ship, what: String)
## A rig or building was bought, sold or upgraded, or a day's output came in (see Energy).
signal energy_changed
## The vehicle and boat makers, likeness and the companies' factories for them (see Manufacturers).
var makers := Manufacturers.new(self)
## A factory was built, closed or sold from, or a day's output came in (see Manufacturers).
signal makers_changed
## The Cargo & Ore mines, plants and factories (see Industry), saved with the world.
var industry := Industry.new(self)
## A site was built, closed, sold or sold from, or a day's output came in (see Industry).
signal industry_changed
## Each step's ships, natively where the native library's there (ShipStepper:
## see native/README.md), and whether to use it (tests compare the two).
var _ship_stepper: Object = null
var use_ship_stepper := true


func _ready() -> void:
	_autosave_timer.wait_time = float(GameData.config.get("autosave_seconds", 30))
	_autosave_timer.timeout.connect(_autosave)
	add_child(_autosave_timer)
	_migrate_legacy_save()
	port_sizes.band_changed.connect(port_band_changed.emit)
	ratings.connect_signals()
	cruises.connect_signals()
	research.connect_signals()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _exit_tree() -> void:
	_finish_autosave()  # (Quitting: the autosave's written out first.)


func _process(delta: float) -> void:
	if not in_session:
		return
	if Net.is_client():
		_client_frame(delta)  # The host runs the world.
		return
	if warm_up_left > 0:
		_warm_up_frame()  # (A new game's world running up to its start, behind the loading screen.)
		return
	GameData.warm_next_month(0.5)
	# Fast forward runs extra steps rather than one long one, so ships arrive,
	# dock and break down as they would at 1x: as many as time_speed, each no
	# longer than MAX_STEP_S (fewer, so a frame at 8x costs less).
	var t_sim := Time.get_ticks_usec()
	var steps := time_speed
	if steps > 1:
		steps = clampi(ceili(delta * time_speed / MAX_STEP_S), 1, time_speed)
	for step in steps:
		_step(delta * time_speed / steps)
	MapView._prof("sim", t_sim)
	var t_tr := Time.get_ticks_usec()
	traffic.scan()
	MapView._prof("traffic.scan", t_tr)


func _step(delta: float) -> void:
	play_time += delta
	_regrow_stocks()
	var month_now := Currents.month_of(calendar_time())
	if month_now != GameData.month:
		GameData.set_month(month_now)  # (The routes on the currents and their push go by the month: see GameData.way_now().)
	var t_s := Time.get_ticks_usec()
	canal_traffic.step(delta)
	port_sizes.step(delta)
	weather.step(delta)
	divine.step(delta)
	MapView._prof("sim.world", t_s)
	t_s = Time.get_ticks_usec()
	_check_payday()
	MapView._prof("sim.payday", t_s)
	t_s = Time.get_ticks_usec()
	icebreaking.refresh()
	MapView._prof("sim.ice", t_s)
	t_s = Time.get_ticks_usec()
	if _ship_stepper == null and ClassDB.class_exists(&"ShipStepper"):
		_ship_stepper = ClassDB.instantiate(&"ShipStepper")
		_ship_stepper.setup(self, {open_sea_zone = Ship.OPEN_SEA_ZONE, min_recovery_speed = MIN_RECOVERY_SPEED_FACTOR,
			kind_icebreaker = Ship.KIND_ICEBREAKER, kind_cargo = Ship.KIND_CARGO, kind_recovery = Ship.KIND_RECOVERY, kind_tug = Ship.KIND_TUG, at_risk_check_s = AT_RISK_CHECK_S})
	if _ship_stepper != null and use_ship_stepper:
		_ship_stepper.advance(ships, delta)  # (The same as the loop below, the plain sailing worked out natively.)
	else:
		for ship in ships:
			_advance(ship, delta)
	MapView._prof("sim.ships", t_s)
	t_s = Time.get_ticks_usec()
	_roll_breakdowns(delta)
	MapView._prof("sim.breakdowns", t_s)
	ratings.step(delta)
	t_s = Time.get_ticks_usec()
	world.step(delta)
	MapView._prof("sim.world", t_s)
	t_s = Time.get_ticks_usec()
	firms.step(delta)
	MapView._prof("sim.firms", t_s)
	traffic.step(delta)
	t_s = Time.get_ticks_usec()
	farms.step(delta)
	makers.step(delta)
	industry.step(delta)
	energy.step(delta)
	research.step(delta)
	MapView._prof("sim.farms", t_s)
	t_s = Time.get_ticks_usec()
	_storm_warning_clock += delta
	if _storm_warning_clock >= STORM_WARNING_CHECK_S:
		_storm_warning_clock = 0.0
		_storm_warnings()
		_batter_anchored()
		_season_warnings()
	_auto_recovery_clock += delta
	if _auto_recovery_clock >= AUTO_RECOVERY_INTERVAL:
		_auto_recovery_clock = 0.0
		_send_queued_recoveries()
	_wake_clock += delta
	if _wake_clock >= WAKE_WAITING_S:
		_wake_clock = 0.0
		_wake_waiting_ships()
	MapView._prof("sim.rest", t_s)


## The calendar runs on Greenwich time (GMT): the longitude (degrees) its
## time of day is read at, 0. The sun stands over Greenwich at 12:00
## (MapView._update_night()), each place's own hour by the sun is an hour on
## for every 15 degrees east (Birds.local_hour()), and the top bar shows it as
## London time (Fmt.calendar(): GMT, or BST in the summer).
func clock_longitude() -> float:
	return 0.0


## The calendar date and time now, as a Unix time (see game_config calendar).
func calendar_time() -> int:
	return calendar_time_at(play_time)


## The ships' earnings window (SHIP_EARNINGS_DAYS of calendar time) in
## seconds of play.
func ship_window_seconds() -> float:
	return SHIP_EARNINGS_DAYS * 86400.0 / maxf(calendar_seconds_per_second(), 1.0)


## How long a finances window (`seconds` of play: the ships' earnings window by
## default) is in game time, as the Ships tab says it: "30 days", "1 day" or "12 hours".
func recent_window_text(seconds := -1.0) -> String:
	var hours := (seconds if seconds > 0.0 else ship_window_seconds()) * calendar_seconds_per_second() / 3600.0
	if hours >= 47.0:
		return "%d days" % roundi(hours / 24.0)
	if hours >= 23.0:
		return "1 day"
	return "%d hours" % maxi(roundi(hours), 1)

## The same, short, for a ship tile: "30d", "1d" or "12h".
func recent_window_short(seconds := -1.0) -> String:
	var hours := (seconds if seconds > 0.0 else ship_window_seconds()) * calendar_seconds_per_second() / 3600.0
	if hours >= 23.0:
		return "%dd" % maxi(roundi(hours / 24.0), 1)
	return "%dh" % maxi(roundi(hours), 1)


## The calendar date and time at a play time.
func calendar_time_at(at_play_time: float) -> int:
	if _calendar_start < 0:  # Parsed once: every ship asks every step.
		var calendar: Dictionary = GameData.config.get("calendar", {})
		_calendar_start = Time.get_unix_time_from_datetime_string(str(calendar.get("start", "2000-01-01T00:00:00")))
		_calendar_rate = calendar_seconds_per_second()
	return int(_calendar_start + at_play_time * _calendar_rate)


## Calendar days that pass per second of play (at 1x).
func days_per_second() -> float:
	return calendar_seconds_per_second() / 86400.0


## Calendar seconds that pass per second of play (at 1x).
func calendar_seconds_per_second() -> float:
	return float(GameData.config.get("calendar", {}).get("minutes_per_second", 20)) * 60.0


## How much faster the calendar runs than the old one matched to real knots
## (game_config calendar pace): durations a player waits for in real time are
## stretched by it.
func calendar_pace() -> float:
	return float(GameData.config.get("calendar", {}).get("pace", 1.0))


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
## The tug model's id ("" if there's none).
func tug_model_id() -> String:
	for model: Dictionary in GameData.ship_models:
		if model.get("tug", false):
			return str(model.id)
	return ""


## How many tugs Buy All Tugs would buy now (as many free slots as the money covers).
func tugs_to_buy() -> int:
	var tug := tug_model_id()
	if tug.is_empty() or not buy_error(tug).is_empty():
		return 0
	var free := tug_slots() - owned_count(tug)
	var price := maxi(ship_price(tug), 1)
	return clampi(1 + (money - price) / price, 0, free)


## Fills every free tug slot (as money allows), each tug with a suggested name
## and based at the route port that needs one most. Returns how many it bought.
func buy_all_tugs() -> int:
	if Net.command(&"buy_all_tugs"):
		return 0
	var tug := tug_model_id()
	var bought := 0
	while not tug.is_empty() and buy_error(tug).is_empty():
		if buy_ship(tug, suggest_ship_name()) == null:
			break
		bought += 1
	return bought


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
	ship_name = Net.clean_text(ship_name)
	var price := ship_price(model_id)
	if model.has("first_price") and price == int(model.first_price) and price < int(model.get("price", 0)):
		first_prices_used.append(model_id)
	money -= price
	_record(null, "bought", price)
	var ship := Ship.new(ship_name, model_id, port_id)
	ship.id = next_ship_id
	next_ship_id += 1
	ship.company = company
	ship.purchase_price = price
	ship.captains = Characters.officers_for(model)
	ships.append(ship)
	if ship.is_cruise():
		cruises.ensure(ship)
	if ship.is_service():
		ship.base_port = port_id
		if ship.is_recovery():
			_rebalance_recovery_boats()
	if is_mine(ship):
		SteamAchievements.note_ship_bought(model_id)
	ships_changed.emit()
	save_game()
	return ship


func owned_count(model_id: String) -> int:
	# (Asked for every model at once, often: counted once a frame, and again as
	# soon as a ship's bought or sold, or another company asks: Buy All Tugs
	# buys in a loop in one frame, and the Shop redraws in the frame it buys.)
	var key := [Engine.get_process_frames(), ships.size(), company]
	if key != _owned_counts_key:
		_owned_counts_key = key
		_owned_counts.clear()
		for ship in fleet():
			_owned_counts[ship.model_id] = int(_owned_counts.get(ship.model_id, 0)) + 1
	return int(_owned_counts.get(model_id, 0))

var _owned_counts := {}
var _owned_counts_key := []


## What the next ship of this model costs: its first_price if it has one and
## the company has never bought one (and owns none, for saves from before
## first prices), otherwise its price; a tug less its animal discount (see
## tug_discount()).
func ship_price(model_id: String) -> int:
	var model := GameData.get_ship_model(model_id)
	if model.has("first_price") and not first_prices_used.has(model_id) and owned_count(model_id) == 0:
		return int(model.first_price)
	if model.get("tug", false):
		return roundi(int(model.get("price", 0)) * (1.0 - tug_discount()))
	return int(model.get("price", 0))


## Tugs cost TUG_ANIMAL_DISCOUNT less for every third of the field guide's
## animals the company has seen (clicked on the map: the Field guide line's
## stars, see Achievements), up to 60% with all of them.
const TUG_ANIMAL_DISCOUNT := 0.2
func tug_discount() -> float:
	var seen := company.discovered.size()
	if _tug_discount_key != [company, seen]:
		_tug_discount_key = [company, seen]
		var all := Achievements.animal_count()
		var stars := Achievements.stars_for(Achievements.seen_count(company), Achievements.ANIMAL_STARS.map(func(share: float) -> int: return roundi(share * all)))
		_tug_discount = TUG_ANIMAL_DISCOUNT * stars
	return _tug_discount
var _tug_discount := 0.0
var _tug_discount_key := []


## Why the player can't buy another of this model, or "" if they can.
func buy_error(model_id: String) -> String:
	var model := GameData.get_ship_model(model_id)
	if not Progression.can_buy_model(model):
		return locked_type_note(Progression.type_of_model(model))
	if model.get("tug", false):
		if tug_ports().is_empty():
			return "Tugs are based at the ports on your ships' routes: give a ship a route first."
		if owned_count(model_id) >= tug_slots():
			return "Each port on your routes takes %d tugs, and all %d tug slots are full. Routes to more ports give more." % [tugs_per_port(), tug_slots()]
		return "You can't afford this ship." if money < ship_price(model_id) else ""
	if money < ship_price(model_id):
		return "You can't afford this ship."
	if not hubs.any(func(hub: Hub) -> bool: return can_launch_at(model_id, hub.port_id)):
		var on_lakes := hubs.all(func(hub: Hub) -> bool: return GameData.get_port(hub.port_id).get("seaway", false))
		if on_lakes and not model.get("seaway", false):
			return "A %s is too big for the St. Lawrence Seaway, and your HQ and hubs are all on the Great Lakes. Found a hub on the coast to launch one." % model.get("name", model_id)
		return "Your HQ and hubs can't launch a %s, which needs a %s port or an HQ or hub." % [
			model.get("name", model_id), str(model.get("min_port", "")).capitalize()]
	return ""


## True if this player's company has found a hidden gem (a HIDDEN_GEMS id).
func hidden_gem_found(gem_id: String) -> bool:
	return company.hidden_gems.has(gem_id)


## A hidden gem found: adds HIDDEN_GEM_MONEY to the bank, the first time only.
func claim_hidden_gem(gem_id: String) -> void:
	if not HIDDEN_GEMS.has(gem_id) or hidden_gem_found(gem_id):
		return
	if Net.command(&"claim_hidden_gem", [gem_id]):
		return
	company.hidden_gems.append(gem_id)
	money += HIDDEN_GEM_MONEY
	ActivityLog.add("You found a hidden gem in %s: +%s (%d of %d)" % [HIDDEN_GEMS[gem_id].name, Fmt.money(HIDDEN_GEM_MONEY),
		company.hidden_gems.size(), HIDDEN_GEMS.size()], ActivityLog.Kind.GOOD)
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


## A company's value (this player's if null): its money less its loan, plus
## what its ships would sell for and what it paid for its hubs after the HQ.
## (Its farms, plants and other buildings join with the new economy.)
func company_value(of: Company = null) -> float:
	var who := of if of != null else company
	var kept: Array = _values_kept.get(who, [])
	if not kept.is_empty() and play_time >= float(kept[0]) and play_time - float(kept[0]) < VALUE_KEEP_S:
		return float(kept[1])
	var value := float(who.money - who.loan)
	for ship in ships:
		if owner_of(ship) == who:
			value += ship.sell_price()
	var settings := Hub.settings()
	for i in range(1, who.hubs.size()):
		value += float(settings.get("price", 5000000)) * pow(float(settings.get("price_growth", 2.0)), i - 1)
	_values_kept[who] = [play_time, value]
	return value
## company_value() for each company lately: Company -> [play time, value]; kept
## VALUE_KEEP_S, as the map asks every frame (its HQ building: see MapView).
var _values_kept := {}
const VALUE_KEEP_S := 2.0


## The company a ship belongs to (this player's, if it has none yet).
func owner_of(ship: Ship) -> Company:
	return ship.company if ship.company != null else company


## The ships the map draws: every company's and the ambient traffic's ghosts
## (AmbientTraffic), made once a frame.
func drawn_ships() -> Array[Ship]:
	var frame := Engine.get_process_frames()
	if frame != _drawn_frame or _drawn.size() != ships.size() + traffic.ghosts.size():
		_drawn_frame = frame
		_drawn = ships.duplicate()
		_drawn.append_array(traffic.ghosts)
	return _drawn
var _drawn: Array[Ship] = []
var _drawn_frame := -1


## A company's ships.
func fleet(of: Company = null) -> Array[Ship]:
	var who := of if of != null else company
	var out: Array[Ship] = []
	for ship in ships:
		if owner_of(ship) == who:
			out.append(ship)
	return out


## The port fee on a delivery: game_config port_fee (10%) of the trade's margin
## (what the cargo sold for, less what it cost), at a port where the company
## has no HQ or hub; nothing at its own, or on a trade at a loss. The company's
## stars in the cargo's type (type_id) make it cheaper or dearer (Ratings).
func port_fee(port_id: String, margin: float, of: Company = null, type_id := "") -> int:
	var who := of if of != null else company
	if margin <= 0.0 or who.hub_at(port_id) != null:
		return 0
	return roundi(margin * float(GameData.config.get("port_fee", 0.1)) * ratings.factor(who, type_id, "fees") * Research.perk(who, "fees"))


## A model's crew: [captains, crew], by its tier (game_config crew).
static func crew_of(model: Dictionary) -> Array:
	var settings: Dictionary = GameData.config.get("crew", {})
	if model.has("fishing"):  # A fishing or crabbing boat's own crew (ship_models.json fishing crew): its skipper and mates, the rest deckhands.
		var hands := maxi(int(model.fishing.get("crew", 3)), 2)
		var officers := 1 if hands <= 6 else (2 if hands <= 25 else 4)
		return [officers, hands - officers]
	var tier := clampi(int(model.get("tier", 1)), 1, 5) - 1
	var captains := int(settings.get("captains", [1])[mini(tier, settings.get("captains", [1]).size() - 1)])
	if model.has("cruise"):  # A cruise ship: its tier's officers, and a hand for every CRUISE_GUESTS_PER_HAND guests.
		return [captains, ceili(float(model.cruise.get("guests", 0)) / CRUISE_GUESTS_PER_HAND)]
	return [captains, int(settings.get("crew", [2])[mini(tier, settings.get("crew", [2]).size() - 1)])]
## A cruise ship's crew: one hand for every this many guests (before its Crew service level).
const CRUISE_GUESTS_PER_HAND := 5.0


## What a model's captains and crew are paid each period (game_config crew).
static func crew_wages(model: Dictionary) -> int:
	var settings: Dictionary = GameData.config.get("crew", {})
	var crew := crew_of(model)
	return int(crew[0]) * int(settings.get("captain_wage", 0)) + int(crew[1]) * int(settings.get("crew_wage", 0))


## The crew pay period now: game_config crew period_days of calendar time,
## counted from the calendar's start.
func _pay_period() -> int:
	var days := float(GameData.config.get("crew", {}).get("period_days", 14))
	return floori((calendar_time() - calendar_time_at(0.0)) / (days * 86400.0))


## Payday, once a period: each ship that worked in the period that just ended
## (sailed, did a job or a stop in port: see _advance()) pays its captains and
## crew their wages, whatever the money (it may go into debt: see in_debt());
## ships idle all period pay nothing. A save from before wages starts counting
## from now.
func _check_payday() -> void:
	var period := _pay_period()
	if period == wage_period:
		return
	if wage_period < 0:
		wage_period = period
		return
	wage_period = period
	var paid := {}  # Company -> [total, ships, one of its ships].
	for ship in ships:
		if not ship.worked:
			continue
		ship.worked = false
		var wages := roundi(crew_wages(ship.model()) * Traits.factor(owner_of(ship), "wages", false))  # (A thrifty or ex-navy CEO pays less: see Traits.)
		if ship.is_cruise():
			wages = roundi(wages * cruises.crew_factor(ship))  # (Its Crew service level.)
		var who := owner_of(ship)
		wages = roundi(wages * Research.perk(who, "wages"))  # (The Trenches perk: see Research.)
		_add_money(who, -wages)
		_record(ship, "wages", wages)
		var tally: Array = paid.get_or_add(who, [0, 0, ship])
		tally[0] += wages
		tally[1] += 1
	for who: Company in paid:
		wages_paid.emit(paid[who][2], paid[who][0], paid[who][1])
	farms.pay_wages()  # (The farm workers', at the same time.)
	energy.pay_wages()  # (The rigs' crews and the refinery workers' too.)
	_pay_hub_upkeep()
	# Interest on loans, paid at the same time.
	for who in all_companies():
		var interest := roundi(loan_interest(who.loan) * Traits.factor(who, "interest", false))  # (A bookkeeper CEO borrows cheaper: see Traits.)
		if interest > 0:
			_add_money(who, -interest)
			_record(null, "interest", interest, who)
			if who == company:
				ActivityLog.add("Paid %s interest on your %s loan." % [Fmt.money(interest), Fmt.money(who.loan)], ActivityLog.Kind.INFO)


## Every HQ's and hub's upkeep (Hub.upkeep(), a month's worth) for the pay
## period just ended, paid with the wages.
func _pay_hub_upkeep() -> void:
	var share := float(GameData.config.get("crew", {}).get("period_days", 14)) / (365.25 / 12.0)
	for who in all_companies():
		var total := 0
		for hub in who.hubs:
			total += roundi(hub.upkeep() * share)
		if total > 0:
			_add_money(who, -total)
			_record(null, "hub_upkeep", total, who)


# --- Loans -------------------------------------------------------------------

## game_config loans: {max, step, yearly_interest}.
static func loan_settings() -> Dictionary:
	return GameData.config.get("loans", {})


## The interest on a loan each crew pay period (yearly_interest, a period's share).
static func loan_interest(amount: int) -> int:
	var days := float(GameData.config.get("crew", {}).get("period_days", 14))
	return roundi(amount * float(loan_settings().get("yearly_interest", 0.08)) * days / 365.0)


## Why this player's company can't borrow another step, or "".
func take_loan_error() -> String:
	if company.loan + int(loan_settings().get("step", 1000000)) > int(loan_settings().get("max", 10000000)):
		return "You've borrowed the most the bank will lend (%s)." % Fmt.money(int(loan_settings().get("max", 10000000)))
	return ""


## Borrows another step (game_config loans step) up to the max. Returns why it
## couldn't, or "".
func take_loan() -> String:
	var error := take_loan_error()
	if not error.is_empty():
		return error
	if Net.command(&"take_loan"):
		return ""
	var step := int(loan_settings().get("step", 1000000))
	company.loan += step
	_add_money(company, step)
	ActivityLog.add("Borrowed %s (%s owed in all)." % [Fmt.money(step), Fmt.money(company.loan)], ActivityLog.Kind.INFO)
	return ""


## Why this player's company can't pay a step of its loan back, or "".
func repay_loan_error() -> String:
	var step := mini(int(loan_settings().get("step", 1000000)), company.loan)
	if step <= 0:
		return "You don't owe the bank anything."
	if company.money < step:
		return "You need %s to pay back." % Fmt.money(step)
	return ""


## Pays back a step of the loan (or what's left of it). Returns why it couldn't, or "".
func repay_loan() -> String:
	var error := repay_loan_error()
	if not error.is_empty():
		return error
	if Net.command(&"repay_loan"):
		return ""
	var step := mini(int(loan_settings().get("step", 1000000)), company.loan)
	company.loan -= step
	_add_money(company, -step)
	ActivityLog.add("Paid back %s of your loan%s." % [Fmt.money(step), "" if company.loan == 0 else " (%s still owed)" % Fmt.money(company.loan)], ActivityLog.Kind.GOOD)
	return ""


## True if a company (this player's by default) is in debt: crew wages (see
## _pay_wages()) can take its money below $0. Its ships then run on credit,
## buying their fuel, repairs, cargo and canal tolls whatever the money, so
## nothing stops and sales pay the debt off; but nothing else can be bought
## (ships, upgrades) until it's back above $0.
func in_debt(of: Company = null) -> bool:
	return (of if of != null else company).money < 0


## True while a ship waiting for a full load is still short of the money for
## it (never in debt, when it loads on credit).
func _short_of_load(ship: Ship) -> bool:
	var who := owner_of(ship)
	return not in_debt(who) and who.money < ship.load_need


## Adds money to a company (or takes it, if negative), telling the screens
## when it's this player's.
func _add_money(to: Company, amount: int) -> void:
	to.money += amount
	if to == company:
		money_changed.emit(to.money)


# --- Headquarters and hubs ---------------------------------------------

## The HQ or hub a company (this player's by default) has at a port, or null.
func hub_at(port_id: String, of: Company = null) -> Hub:
	return (of if of != null else company).hub_at(port_id)


## Every company in the game (just this player's before any are listed).
func all_companies() -> Array[Company]:
	if companies.is_empty():
		return [company]
	return companies


## What buying into another company type (a division) costs: game_config
## company_types.division_price.
func division_price() -> int:
	return int(GameData.config.get("company_types", {}).get("division_price", 5000000))


func choose_company_type_error(type_id: String, of: Company = null) -> String:
	var who := of if of != null else company
	if Progression.company_type(type_id).is_empty():
		return "There's no such company type."
	if Progression.company_type(type_id).get("coming_soon", false):
		return "%s is coming soon." % Progression.type_name(type_id)
	if who.has_type(type_id):
		return "Your company already has it."
	if who.money < division_price():
		return "A new division costs %s (%s short)." % [Fmt.money(division_price()), Fmt.money(division_price() - who.money)]
	return ""


## Buys into another company type (a division), for good: all its ships can
## be bought from now on. Returns why it couldn't, or "".
func choose_company_type(type_id: String) -> String:
	var error := choose_company_type_error(type_id)
	if not error.is_empty():
		return error
	if Net.command(&"choose_company_type", [type_id]):
		return ""
	var price := division_price()
	money -= price
	_record(null, "divisions", price)
	take_company_type(company, type_id)
	ActivityLog.add("Your company opened a %s division for %s: its ships can be bought now." % [Progression.type_name(type_id), Fmt.money(price)], ActivityLog.Kind.GOOD)
	save_game()
	return ""


## Gives a company a type, noting the play time it was taken.
func take_company_type(who: Company, type_id: String) -> void:
	who.company_types[type_id] = play_time
	company_types_changed.emit()
	ships_changed.emit()


## Why a model of a type the company lacks can't be bought.
func locked_type_note(type_id: String) -> String:
	return "Comes with the %s company type: open a %s division (%s) to buy it." % [Progression.type_name(type_id), Progression.type_name(type_id), Fmt.money(division_price())]


## A cruise ship's free settings (Cruises): any of prices {class: $},
## monthly [12 %], package, departure {mode, days, fill}; changed any time.
## Returns why not, or "".
func set_cruise_settings(ship: Ship, changes: Dictionary) -> String:
	if not ship.is_cruise() or owner_of(ship) != company:
		return "Not one of your cruise ships."
	if Net.command(&"set_cruise_settings", [ship, changes]):
		return ""
	cruises.ensure(ship)
	for key: String in changes:
		match key:
			"prices":
				ship.cruise.auto_prices = false  # (Its own now: they stop following the recommendations.)
				var prices := {}
				for cls: String in Cruises.CLASSES:
					prices[cls] = clampi(int(changes.prices.get(cls, ship.cruise.prices.get(cls, 0))), 0, 10000000)
				ship.cruise.prices = prices
			"monthly":
				ship.cruise.auto_monthly = false
				var monthly: Array = changes.monthly
				if monthly.size() == 12:
					ship.cruise.monthly = monthly.map(func(value: Variant) -> int: return clampi(int(value), -50, 50))
			"auto_prices", "auto_monthly":  # (Back to following the recommendations.)
				ship.cruise[key] = true
				cruises.follow_recommendations(ship)
			"service":
				var service := {}
				for dial: String in Cruises.SERVICES:
					service[dial] = clampi(int(changes.service.get(dial, ship.cruise.service.get(dial, 1))), 0, 4)
				ship.cruise.service = service
			"package":
				if (Cruises.settings().get("packages", {}) as Dictionary).has(str(changes.package)):
					ship.cruise.package = str(changes.package)
			"departure":
				var rule: Dictionary = changes.departure
				ship.cruise.departure = {mode = str(rule.get("mode", "both")) if ["time", "fill", "both"].has(str(rule.get("mode", ""))) else "both",
					days = clampi(int(rule.get("days", 2)), 0, 4), fill = clampi(int(rule.get("fill", 3)), 0, 4)}
	ship_changed.emit(ship)
	return ""


## Refits a cruise ship to a new setup ({cabins, amenities, looks}; see Cruises.refit()).
func refit_cruise(ship: Ship, setup: Dictionary) -> String:
	if not ship.is_cruise() or owner_of(ship) != company:
		return "Not one of your cruise ships."
	var error := cruises.refit_error(ship, setup)
	if not error.is_empty():
		return error
	if Net.command(&"refit_cruise", [ship, setup]):
		return ""
	var quote := cruises.refit_quote(ship, setup)
	error = cruises.refit(ship, setup)
	if error.is_empty():
		ActivityLog.add("%s is in refit at %s: %s, back in %s." % [ship.name, GameData.port_name(ship.docked_at), Fmt.money(int(quote.cost)),
			Fmt.duration(float(quote.days) * 86400.0 / calendar_seconds_per_second())], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))
		ship_changed.emit(ship)
		save_game()
	return error


## Builds a cruise terminal at a port (Cruises.terminal_cost()), so the company's cruise ships can sail from it.
func buy_terminal(port_id: String) -> String:
	var error := cruises.terminal_error(company, port_id)
	if not error.is_empty():
		return error
	if Net.command(&"buy_terminal", [port_id]):
		return ""
	var cost := cruises.terminal_cost(company)
	company.terminals.append(port_id)
	_add_money(company, -cost)
	_record(null, "hubs", cost)
	ActivityLog.add("Built a cruise terminal at %s (%s): your cruise ships can sail from there." % [GameData.port_name(port_id), Fmt.money(cost)], ActivityLog.Kind.GOOD)
	hubs_changed.emit()
	save_game()
	return ""


## What changing the company's logo costs (it's chosen free when founding).
const LOGO_CHANGE_COST := 1000000


func set_logo_error(new_logo: Dictionary) -> String:
	if not CompanyLogo.SHAPES.has(str(new_logo.get("shape", ""))) or not CompanyLogo.LAYOUTS.has(str(new_logo.get("layout", ""))):
		return "That isn't a logo."
	if str(new_logo.get("secondary", "")) == company.color:
		return "Pick a second colour other than the company's own."
	if money < LOGO_CHANGE_COST:
		return "Changing the logo costs %s." % Fmt.money(LOGO_CHANGE_COST)
	return ""


## Changes the company's logo for LOGO_CHANGE_COST. Returns why it couldn't, or "".
func set_logo(new_logo: Dictionary) -> String:
	var error := set_logo_error(new_logo)
	if not error.is_empty():
		return error
	if Net.command(&"set_logo", [new_logo]):
		return ""
	company.logo = {shape = str(new_logo.shape), layout = str(new_logo.layout), secondary = str(new_logo.get("secondary", "white")), swap = bool(new_logo.get("swap", false))}
	_add_money(company, -LOGO_CHANGE_COST)
	_record(null, "logo", LOGO_CHANGE_COST)
	ActivityLog.add("Your company has a new logo (%s)." % Fmt.money(LOGO_CHANGE_COST), ActivityLog.Kind.INFO)
	logo_changed.emit()
	save_game()
	return ""


## Why a hub can't be built at a port, or "".
func build_hub_error(port_id: String) -> String:
	if hub_at(port_id):
		return "There's already a hub here."
	if money < hub_price():
		return "A new hub costs %s (%s short)." % [Fmt.money(hub_price()), Fmt.money(hub_price() - money)]
	return ""


## What the next hub costs: hubs.price for the first after the HQ, each
## next hubs.price_growth times the last.
func hub_price() -> int:
	var settings := Hub.settings()
	return roundi(float(settings.get("price", 5000000)) * pow(float(settings.get("price_growth", 2.0)), maxi(hubs.size() - 1, 0)))


## Founds a hub at a port, for good. Returns why it couldn't, or "".
func build_hub(port_id: String) -> String:
	var error := build_hub_error(port_id)
	if not error.is_empty():
		return error
	if Net.command(&"build_hub", [port_id]):
		return ""
	var price := hub_price()
	money -= price
	_record(null, "hubs", price)
	var hub := Hub.new(port_id)
	hubs.append(hub)
	_rebalance_recovery_boats()
	hub_built.emit(hub)
	hubs_changed.emit()
	save_game()
	return ""


## Why a building for a commodity can't go on a hub's industry plot right
## now, or "".
func build_industry_error(hub: Hub, slot: int, commodity_id: String) -> String:
	if slot < 0 or slot >= Hub.INDUSTRY_SLOTS:
		return "No such plot."
	if not hub.industries[slot].is_empty():
		return "Something's built there already."
	if GameData.commodity(commodity_id).is_empty():
		return "No such commodity."
	if GameData.commodity(commodity_id).get("maker", false):
		return "Build for its kind (cars, trucks or boats)."
	if hub.has_industry(commodity_id):
		return "This hub has a %s building already." % GameData.commodity(commodity_id).get("name", commodity_id)
	var price := industry_price()
	if money < price:
		return "Costs %s." % Fmt.money(price)
	return ""


## What a building costs (hubs.industry.price), and what demolishing one
## gives back.
func industry_price() -> int:
	return int(Hub.industry_settings().get("price", 15000000))


func industry_refund() -> int:
	return roundi(industry_price() * float(Hub.industry_settings().get("refund", 0.5)))


## Builds a commodity's building on one of a hub's industry plots, for its price.
func build_industry(hub: Hub, slot: int, commodity_id: String) -> void:
	if not build_industry_error(hub, slot, commodity_id).is_empty():
		return
	if Net.command(&"build_industry", [hub, slot, commodity_id]):
		return
	var price := industry_price()
	money -= price
	_record(null, "hubs", price)
	hub.industries[slot] = commodity_id
	ActivityLog.add("Built a %s at %s" % [industry_name(commodity_id), hub.title()], ActivityLog.Kind.GOOD)
	hubs_changed.emit()


## A plant of the player's (an industry site, a farm plot, a maker's factory or
## an energy building) set to sell its output locally: each day's output goes
## into its zone's stockpile (WorldEconomy) and is paid for at the port's price
## less LOCAL_SALE_CUT for the handling, instead of waiting in its store for
## the company's ships. kind: "site", "plot", "factory" ("maker|port") or
## "plant" ("port/building").
const LOCAL_SALE_CUT := 0.1


func set_local_sale(kind: String, key: String, on: bool) -> void:
	if Net.command(&"set_local_sale", [kind, key, on]):
		return
	match kind:
		"site":
			if industry.owner_of(key) == company:
				industry.site(key).local = on
				industry_changed.emit()
		"plot":
			if farms.owner_of(key) == company:
				farms.plot(key).local = on
				farms_changed.emit()
		"factory":
			var parts := key.split("|")
			var factory := Manufacturers.factory(company, parts[0], parts[1]) if parts.size() == 2 else {}
			if not factory.is_empty():
				factory.local = on
				makers_changed.emit()
		"plant":
			var parts := key.split("/")
			var plants := energy.plants_at(company, parts[0]) if parts.size() == 2 else {}
			if plants.has(parts[1]):
				plants[parts[1]].local = on
				energy_changed.emit()


## Sells a plant's output into its port's zone (see set_local_sale()): the
## amount into the zone's stockpile, the company paid the port's price (x
## factor: a breed's worth) less LOCAL_SALE_CUT. Returns what it was paid.
func sell_locally(who: Company, port_id: String, good: String, amount: float, kind: String, factor := 1.0) -> int:
	if amount <= 0.0:
		return 0
	var value := roundi(amount * company_sell_price(port_id, good, who) * factor * (1.0 - LOCAL_SALE_CUT))
	var z := world.zone_of_port(port_id)
	var g := world.good_index(good)
	if z >= 0 and g >= 0:
		world.deliver(z, g, amount)
	_add_money(who, value)
	_record(null, kind, -value, who)
	return value

## Pulls down the building on one of a hub's industry plots, for some of its price back.
func demolish_industry(hub: Hub, slot: int) -> void:
	if slot < 0 or slot >= Hub.INDUSTRY_SLOTS or hub.industries[slot].is_empty():
		return
	if Net.command(&"demolish_industry", [hub, slot]):
		return
	var refund := industry_refund()
	money += refund
	_record(null, "hubs", -refund)
	ActivityLog.add("Pulled down the %s at %s" % [industry_name(hub.industries[slot]), hub.title()], ActivityLog.Kind.INFO)
	hub.industries[slot] = ""
	hubs_changed.emit()


## A commodity's industry building's name ("Coffee roastery").
static func industry_name(commodity_id: String) -> String:
	var item := GameData.commodity(commodity_id)
	var kind := str(WAREHOUSE_KINDS.get(GameData.family_of(commodity_id), WAREHOUSE_KINDS.get(str(item.get("unit", "")), "warehouse")))
	return "%s %s" % [item.get("name", commodity_id), kind]


## A commodity's price for a company at a port: the market's, less (buying)
## or more (selling) by its building for it there, if it has a hub there with
## one (see Hub.industry_bonus(): a maker's goods go by their kind's), and
## buying a maker's goods at its own factories less once it likes the company
## enough (Manufacturers.buy_factor()).
func company_buy_price(port_id: String, commodity_id: String, of: Company = null) -> float:
	var hub := hub_at(port_id, of)
	return market.buy_price(port_id, commodity_id) * (1.0 - (hub.industry_bonus(GameData.family_of(commodity_id), "buy") if hub else 0.0)) * divine.price_factor(port_id, false) \
		* Manufacturers.buy_factor(of if of != null else company, port_id, commodity_id)


func company_sell_price(port_id: String, commodity_id: String, of: Company = null) -> float:
	var hub := hub_at(port_id, of)
	return market.sell_price(port_id, commodity_id) * (1.0 + (hub.industry_bonus(GameData.family_of(commodity_id), "sell") if hub else 0.0)) * divine.price_factor(port_id, true) \
		* ratings.factor(of if of != null else company, Progression.type_of_commodity(commodity_id), "price") * Research.perk(of if of != null else company, "price") * Traits.factor(of if of != null else company, "price")  # (The type's stars: see Ratings; the research perks: see Research.)


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
	set_ship_name(ship, Net.clean_text(new_name))
	save_game()
	return ""


## Gives a ship a new name, carrying its recent finances over to it.
func set_ship_name(ship: Ship, new_name: String) -> void:
	if new_name == ship.name:
		return
	for bucket: Dictionary in owner_of(ship).finance_window:
		if bucket.ships.has(ship.name):
			bucket.ships[new_name] = bucket.ships[ship.name]
			bucket.ships.erase(ship.name)
	ship.name = new_name
	ship_changed.emit(ship)


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
## route's first port) must be one it can make, refuelling at ports on the way
## if it's beyond one tank (see refuel_path()).
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
		if not can_get_to(ship, from, to):
			return _reach_error(ship, from, to)
	var start := ship.reference_port()
	if not route.has(start) and not can_get_to(ship, start, route[0]):
		return _reach_error(ship, start, route[0])
	return ""


# --- Refuel stops ----------------------------------------------------------------

## A port beyond one tank is reached by way of refuel stops: the ship sails
## port to port, each leg one it can sail on a full tank (Ship.can_sail()),
## each stop a port it fits that its company has unlocked, and fills up at
## each (Ship.hop_to; GameState._try_depart() picks the next stop). Routes
## may have legs like that, a fishing boat's ground may lie beyond a trip
## from its port, and a ship sent somewhere new steps its way there.

## A refuel stop counts as this many extra miles, so of two ways about as
## long the one with fewer stops wins.
const REFUEL_STOP_NM := 120.0
## Each port's lanes to the others, nearest first ([id, nm] each), built for a
## port the first time it's asked for.
var _lane_neighbours := {}
## Kept refuel trees (refuel_tree()), dropped when the month changes (the
## currents change how long legs take).
var _refuel_trees := {}
var _refuel_trees_key := []


func _lane_neighbours_of(port_id: String) -> Array:
	if not _lane_neighbours.has(port_id):
		var out := []
		for port: Dictionary in GameData.ports:
			var id := str(port.id)
			if id == port_id:
				continue
			var nm := GameData.distance_nm(port_id, id, -1)
			if nm < INF:
				out.append([id, nm])
		out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) < float(b[1]))
		_lane_neighbours[port_id] = out
	return _lane_neighbours[port_id]


## Every port a ship can get to from `from` stepping port to port and
## refuelling at each: {nm: {port: miles there, refuel stops counted},
## prev: {port: the stop before it}, stops: {port: refuel stops on the way},
## done: {port: true}}. Kept for ships alike (model, speed, burn, wear) from
## the same port. The search goes nearest first; with `until` it stops once
## that port is settled, and carries on from there when asked again (a big
## ship's whole tree is tens of ms). The ports in done are settled (their nm,
## prev and stops final); the rest are only reached so far, till it's done.
func refuel_tree(ship: Ship, from: String, until := "") -> Dictionary:
	var month_key := [GameData.month, companies.size()]
	if month_key != _refuel_trees_key:
		_refuel_trees.clear()
		_refuel_trees_key = month_key
	var key := [ship.model_id, ship.top_speed(), ship.fuel_per_s(), ship.wear_per_s(), from]
	var tree: Dictionary = _refuel_trees.get(key, {})
	if tree.is_empty():
		tree = {nm = {from: 0.0}, prev = {}, stops = {from: 0}, done = {}, open = {from: true}, bad = {}}
		_refuel_trees[key] = tree
	var open: Dictionary = tree.open  # (Ports reached but not yet stepped on from.)
	var done: Dictionary = tree.done
	if open.is_empty() or done.has(until):
		return tree
	var reach := ship.range_nm()
	var best: Dictionary = tree.nm
	var prev: Dictionary = tree.prev
	var stops: Dictionary = tree.stops
	# Legs are checked for fuel (Ship.can_sail(), costly the first time for a
	# lane: its zones) only as the search settles on them, not every one in
	# range: a leg that fails is ruled out and the port is reached again by
	# its next best way from the ports already settled.
	var bad: Dictionary = tree.bad
	var usable := {}  # (Whether each port is open to the ship and fits it, asked once.)
	while not open.is_empty():
		var here := ""
		var here_nm := INF
		for port: String in open:
			if float(best[port]) < here_nm:
				here_nm = best[port]
				here = port
		open.erase(here)
		if here != from and not ship.can_sail(prev[here], here):
			bad[[prev[here], here]] = true
			best.erase(here)
			prev.erase(here)
			var ways := []
			for settled: String in done:
				var leg := GameData.distance_nm(settled, here, -1)
				if leg <= reach and not bad.has([settled, here]):
					ways.append([float(best[settled]) + leg + (REFUEL_STOP_NM if settled != from else 0.0), settled])
			ways.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
			if not ways.is_empty():
				best[here] = ways[0][0]
				prev[here] = ways[0][1]
				stops[here] = int(stops[ways[0][1]]) + (1 if ways[0][1] != from else 0)
				open[here] = true  # (Checked again when it's next the nearest.)
			continue
		done[here] = true
		var step_nm := REFUEL_STOP_NM if here != from else 0.0
		for pair: Array in _lane_neighbours_of(here):
			var nm := float(pair[1])
			if nm > reach:
				break
			var there: String = pair[0]
			if done.has(there) or not bad.is_empty() and bad.has([here, there]):
				continue
			var total := here_nm + nm + step_nm
			if total >= float(best.get(there, INF)):
				continue
			var ok: Variant = usable.get(there)
			if ok == null:
				ok = ship.fits_port(there)
				usable[there] = ok
			if not ok or not ship.fits_lane(here, there):
				continue
			best[there] = total
			prev[there] = here
			stops[there] = int(stops[here]) + (1 if here != from else 0)
			open[there] = true
		if here == until:
			break
	return tree


## The ports a ship stops at going from `from` to `to`, `to` last: just [to]
## for a leg it can sail on one tank, the refuel stops before it otherwise;
## [] if it can't get there even refuelling on the way.
func refuel_path(ship: Ship, from: String, to: String) -> Array[String]:
	var path: Array[String] = []
	if from == to:
		return path
	if ship.can_sail(from, to):
		path.append(to)
		return path
	var tree := refuel_tree(ship, from, to)
	if not (tree.done as Dictionary).has(to):
		return path
	var at := to
	while at != from:
		path.push_front(at)
		at = tree.prev[at]
	return path


## The refuel stops on the way from one port to another (refuel_path() less
## its end); [] for a leg sailed on one tank, or one it can't make at all.
func refuel_stops(ship: Ship, from: String, to: String) -> Array[String]:
	var path := refuel_path(ship, from, to)
	if not path.is_empty():
		path.pop_back()
	return path


## True if a ship can get from one port to another at all, refuelling on the way if it must.
func can_get_to(ship: Ship, from: String, to: String) -> bool:
	return from == to or ship.can_sail(from, to) or (refuel_tree(ship, from, to).done as Dictionary).has(to)


## The sea miles from one port to another by way of its refuel stops (INF if it can't get there).
func refuel_path_nm(ship: Ship, from: String, to: String) -> float:
	var nm := 0.0
	var at := from
	var path := refuel_path(ship, from, to)
	if path.is_empty() and from != to:
		return INF
	for port in path:
		nm += GameData.distance_nm(at, port)
		at = port
	return nm


## "refuels at Valletta and Heraklion" and the like, for the route screen,
## popups and the log.
static func refuel_text(stops: Array) -> String:
	var names := PackedStringArray()
	for port: String in stops:
		names.append(GameData.port_name(port))
	if names.is_empty():
		return ""
	if names.size() == 1:
		return "refuels at %s" % names[0]
	return "refuels at %s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[-1]]


## A port's size as shown: "Medium 29".
func port_size_text(port_id: String) -> String:
	return "%s %d" % [port_sizes.band(port_id).capitalize(), port_sizes.level(port_id)]


## "Taipei (Small 11) is too small for a Dominator, which needs a Large port or an HQ or hub."
func port_size_error(model: Dictionary, port_id: String) -> String:
	return "%s (%s) is too small for a %s, which needs a %s port or an HQ or hub." % [GameData.port_name(port_id),
		port_size_text(port_id), model.get("name", ""),
		str(model.get("min_port", "")).capitalize()]


## Whether a new ship of this model can be launched at a port (the HQ or a
## hub): big enough for it, and not on the Great Lakes if it's too big for the Seaway.
func can_launch_at(model_id: String, port_id: String) -> bool:
	var model := GameData.get_ship_model(model_id)
	var too_big_for_seaway: bool = not model.get("seaway", false) and GameData.get_port(port_id).get("seaway", false)
	return hub_at(port_id) != null and not too_big_for_seaway and port_sizes.fits(model, port_id)


## Why a ship can't get from one port to another even refuelling on the way.
func _reach_error(ship: Ship, from: String, to: String) -> String:
	if not ship.fits_port(to) or not ship.fits_lane(from, to):
		return _range_error(ship, from, to)
	return "%s can't be reached from %s, even refuelling on the way: no chain of ports within this ship's %s nm range leads there." % [
		GameData.port_name(to), GameData.port_name(from), Fmt.thousands(roundi(ship.range_nm()))]


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
	if ship.job_phase == Ship.JOB_RIG:
		ship.set_meta(&"rig_off", true)  # (Off rig runs once it's back from this one: see _advance_rig().)
	else:
		ship.rig_field = ""  # (Off rig runs, if it was on them: see set_rig_run().)
		ship.rig_port = ""
	if ship.is_docked():
		ship.route = route.duplicate()
		ship.pending_route.clear()
		ship.hop_to = ""  # (A new plan: any refuel stops are worked out again from here.)
		ship.route_index = ship.route.find(ship.docked_at)
	else:
		ship.pending_route = route.duplicate()
	_rebalance_tugs()
	if ship.is_cruise():
		cruises.follow_recommendations(ship)  # (Prices left to the recommendations follow the new itinerary.)
	ship_changed.emit(ship)


## A ship paused at sea carries on to its next port and waits there.
func set_paused(ship: Ship, paused: bool) -> void:
	if not ship.has_route() and not ship.is_fishing():  # (A fishing boat pauses in port between trips.)
		return
	if Net.command(&"set_paused", [ship, paused]):
		return
	ship.paused = paused
	ship_changed.emit(ship)


## A ship's skin (see Ship.skin): "" as the Shop, "base", or "pack/skin" (a
## skin of the catalog: the player choosing it owns it; see SkinPicker).
func set_skin(ship: Ship, skin: String) -> void:
	if not skin.is_empty() and skin != "base" and not Cosmetics.is_skin_key(skin):
		return
	if Net.command(&"set_skin", [ship, skin]):
		return
	ship.skin = skin
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
	var t_x := Time.get_ticks_usec()
	_advance_timed(ship, delta)
	MapView._prof("sim.advance", t_x)

func _advance_timed(ship: Ship, delta: float) -> void:
	# A ship waiting in port for a full load, not due another look: nothing to do.
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and _short_of_load(ship) and ship.is_docked() \
			and ship.berth_phase == Ship.BERTH_NONE:
		return
	# A recovery boat or tug standing by at its base (most of them, most of the
	# time): nothing to do until it's sent out.
	if ship.dock_time < 0.0 and ship.docked_at == ship.base_port and ship.hold_reason.is_empty() \
			and not ship.docked_at.is_empty() and (ship.is_recovery() or ship.is_tug()) and not ship.is_on_job():
		return
	# A cargo ship lying idle at the anchorage (no route, or paused): likewise.
	if ship.dock_time < 0.0 and ship.berth < 0 and ship.berth_phase == Ship.BERTH_NONE and ship.hold_reason.is_empty() \
			and not ship.docked_at.is_empty() and not ship.is_service() and not ship.is_running():
		return
	# Working, so its crew is paid this period (see _pay_wages()): sailing, on a
	# job, or doing a stop in port.
	var on_job := ship.is_on_job()  # (Asked once: this runs for every ship, every step.)
	if not ship.worked and (not ship.is_docked() and not ship.is_lost() or on_job or ship.is_docking()):
		ship.worked = true
	var t_v := Time.get_ticks_usec()
	if ship.is_icebreaker():
		_advance_icebreaker(ship, delta)
		MapView._prof("advance.icebreaker", t_v)
	elif on_job and ship.is_fishing():
		_advance_fishing(ship, delta)
		MapView._prof("advance.fishing", t_v)
	elif on_job and (ship.job_phase == Ship.JOB_RIG or ship.job_phase == Ship.JOB_REPAIR):
		_advance_rig(ship, delta)  # (A rig run or a tug's repair: see Energy.)
		MapView._prof("advance.rig", t_v)
	elif on_job and ship.job_phase == Ship.JOB_RESEARCH:
		research.advance(ship, delta)  # (An expedition: see Research.)
		MapView._prof("advance.research", t_v)
	elif on_job and ship.is_tug():
		_advance_tug_job(ship, delta)
		MapView._prof("advance.tug", t_v)
	elif on_job:
		_advance_job(ship, delta)
		MapView._prof("advance.job", t_v)
	elif ship.is_docked():
		_advance_docked(ship, delta)
		MapView._prof("advance.docked", t_v)
	elif not ship.is_lost() and _sail(ship, delta) and ship.traveled_nm >= ship.leg_length():
		_arrive(ship, ship.to_port)
		MapView._prof("advance.sail_arrive", t_v)
	else:
		MapView._prof("advance.sail", t_v)


## Wears, burns fuel and moves a ship along its current lane. Returns false if
## the ship ran out of fuel or maintenance and is now lost at sea. Mammoths
## only set off when they can finish, so they're never lost. Speed and wear
## follow the lane's zones (slower in convoy canals, faster wear in rough seas).
## A ship held in a canal (see CanalTraffic) stays put with its engines off, and
## one slowed by the ship ahead burns fuel and wears only for the distance it
## makes, so the fuel it set off with always covers the leg.
func _sail(ship: Ship, delta: float) -> bool:
	# Canals, storm-closed ports and icebreakers' ice hold up few ships: the
	# rest skip asking (this runs for every ship at sea, every step).
	var canal := ship.lock_time >= 0.0 or not ship.canal_state.is_empty() or ship.leg_has_canal()
	if canal and canal_traffic.hold(ship, delta):
		return true
	if ship.escort != null:
		return true  # In a convoy: its icebreaker moves it (see _escort()).
	var zone := ship.zone_at(ship.traveled_nm)
	var storm := _storm_factors(ship)
	var speed := ship.speed()
	var service := ship.is_service() and not ship.is_fishing()  # (A fishing boat sails, wears and can be lost like a cargo ship.)
	if service:
		speed = maxf(speed, ship.top_speed() * MIN_RECOVERY_SPEED_FACTOR)
	speed *= float(zone[1]) * float(storm[0])
	var target := ship.traveled_nm + speed * delta
	if canal:
		target = canal_traffic.limit(ship, target)
	if weather.can_close():
		target = _storm_hold(ship, target)
	elif not ship.weather_wait.is_empty() and ship.ice_wait.is_empty():
		ship.weather_wait = ""  # A storm that closed its port has eased.
	if icebreaking.any_open_closure() or not ship.ice_wait.is_empty():
		target = _ice_hold(ship, target)
	var effort := clampf((target - ship.traveled_nm) / (speed * delta), 0.0, 1.0) if speed * delta > 0.0 else 1.0
	if service or ship.is_running() or ship.is_fishing():
		ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * float(zone[2]) * float(storm[1]) * delta * effort, 0.0)
	# A storm costs time, not fuel per mile: the engines make less way, so the
	# fuel a ship set off with still covers the leg.
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * float(storm[0]) * delta * effort, 0.0)
	ship.traveled_nm = target
	if not service:
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
	var t_x := Time.get_ticks_usec()
	var out := _storm_factors_timed(ship)
	MapView._prof("sim.storm_factors", t_x)
	return out

func _storm_factors_timed(ship: Ship) -> Array:
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
		var t_f := Time.get_ticks_usec()
		var at := Geo.unproject(ship.world_position())
		var storm := weather.factors(at) if storms_out else [1.0, 1.0]
		MapView._prof("storm.weather", t_f)
		t_f = Time.get_ticks_usec()
		var ice := seasonal.factors(at) if ice_in else [1.0, 1.0]
		MapView._prof("storm.ice", t_f)
		if storms_out and divine.escorted(ship):
			storm[1] = 1.0  # The sea's escorts shield it from the storm's wear (Divine).
		ship.storm_factors = [float(storm[0]) * float(ice[0]), float(storm[1]) * float(ice[1])]
	# The birds following it (see BirdBoosts): faster, wearing less, and the storm's
	# slowing and wearing shrugged off in part (its fuel saving is in Ship.fuel_per_s()).
	var t_b := Time.get_ticks_usec()
	var boosts := bird_boosts(ship)
	MapView._prof("storm.birds", t_b)
	if not boosts.is_empty():
		var shelter := float(boosts.storm)
		if storms_out and shelter > 0.0:
			ship.storm_factors[0] = lerpf(float(ship.storm_factors[0]), 1.0, shelter) if float(ship.storm_factors[0]) < 1.0 else float(ship.storm_factors[0])
			ship.storm_factors[1] = lerpf(float(ship.storm_factors[1]), 1.0, shelter) if float(ship.storm_factors[1]) > 1.0 else float(ship.storm_factors[1])
		ship.storm_factors[0] = float(ship.storm_factors[0]) * (1.0 + float(boosts.speed))
		ship.storm_factors[1] = float(ship.storm_factors[1]) * (1.0 - float(boosts.wear))
	if divine.on:
		# Its blessings (the birds following it, fair winds, sharks hurrying a rescuer) speed it up.
		ship.storm_factors[0] = float(ship.storm_factors[0]) * divine.speed_factor(ship)
	return ship.storm_factors


## What the birds following a ship give it (BirdBoosts.total(): {speed, wear,
## fuel, storm} shares), looked at again every BIRD_BOOST_REFRESH_S; {} with
## no birds. Sets the ship's fuel saving too (Ship.bird_fuel_saving).
const BIRD_BOOST_REFRESH_S := 5.0
## How many of a species the boosts count at most (they saturate: BirdBoosts.EXTRA_PER_BIRD up to 3),
## and how many birds are looked at closely for one ship (a big colony that all planned to follow it is a hitch).
const BIRD_BOOST_COUNT_CAP := 8
const BIRD_BOOST_LOOK_CAP := 8
var _bird_boosts := {}  # Ship -> [until (play time), boosts].

func bird_boosts(ship: Ship) -> Dictionary:
	var kept: Array = _bird_boosts.get(ship, [])
	if not kept.is_empty() and play_time < float(kept[0]):
		return kept[1]
	var boosts := {}
	if not ship.is_service():
		var t_f := Time.get_ticks_usec()
		var following: Array = BirdLife.shared().following(ship, BIRD_BOOST_COUNT_CAP, BIRD_BOOST_LOOK_CAP)  # (The boosts saturate at a few birds: see BirdBoosts.)
		MapView._prof("birds.following", t_f)
		if not following.is_empty():
			t_f = Time.get_ticks_usec()
			boosts = BirdBoosts.total(following)
			MapView._prof("birds.total", t_f)
			if float(boosts.speed) <= 0.0 and float(boosts.wear) <= 0.0 and float(boosts.fuel) <= 0.0 and float(boosts.storm) <= 0.0:
				boosts = {}
	var saving := float(boosts.get("fuel", 0.0))
	if saving != ship.bird_fuel_saving:
		ship.bird_fuel_saving = saving
		ship.invalidate_stats()
	_bird_boosts[ship] = [play_time + BIRD_BOOST_REFRESH_S, boosts]
	return boosts


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
	if ship.is_service() or ship.research_gear.has("ice"):  # (A research ship with an ice hull goes on through: see Research.)
		return target
	# Areas open and close slowly: looked up again only every ICE_HOLD_REFRESH_S
	# (and on a new leg).
	if play_time >= ship.ice_check_time or play_time < ship.ice_check_time - ICE_HOLD_REFRESH_S:
		ship.ice_check_time = play_time + ICE_HOLD_REFRESH_S
		ship.ice_area = icebreaking.area_for_leg(ship.from_port, ship.to_port)
		ship.ice_entry = icebreaking.entry_mile(ship.ice_area, ship.from_port, ship.to_port) if not ship.ice_area.is_empty() else -1.0
	var item := ship.ice_area
	var entry := ship.ice_entry
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
	var t_x := Time.get_ticks_usec()
	_check_at_risk_timed(ship)
	MapView._prof("sim.at_risk", t_x)

func _check_at_risk_timed(ship: Ship) -> void:
	var seconds := ship.leg_seconds(ship.from_port, ship.to_port, ship.traveled_nm, ship.leg_length(), ship.maintenance)
	var at_risk := ship.fuel < ship.fuel_per_s() * seconds
	if at_risk == ship.at_risk:
		return
	ship.at_risk = at_risk
	if at_risk:
		ship_at_risk.emit(ship)
	ship_changed.emit(ship)


## The Kraken takes a ship at sea (Divine): lost where it is, its engines wrecked.
func lose_to_kraken(ship: Ship) -> void:
	if ship.is_docked() or ship.is_lost():
		return
	ship.maintenance = 0.0
	ship.risk_check_time = 0.0
	_lose(ship, "taken by the Kraken")


## Why this company (the acting one: a joined player's, a rival's) can't use a
## divine power on a target now, or "" (see Divine.error()).
func divine_act_error(power: String, target: Variant) -> String:
	return divine.error(power, target, company)


## This company uses a divine power on a target (a (lon, lat) Vector2, a port
## id, a ship id, or null): the host does it for a joined player (a Net
## command). Returns what was done, or "" if it couldn't be (see divine_act_error()).
func divine_act(power: String, target: Variant) -> String:
	if Net.command(&"divine_act", [power, target]):
		return ""
	var who := company
	var why := divine.error(power, target, who)
	if not why.is_empty():
		ActivityLog.add(why, ActivityLog.Kind.BAD)
		return ""
	var text := divine.act(power, target, who)
	var hit_me := divine.hits(power, target, company if Net.acting_for == null else Net.acting_for)
	ActivityLog.add("%s %s." % [who.name, text], ActivityLog.Kind.BAD if hit_me and who != company else ActivityLog.Kind.INFO, company_color_value(who.color))
	money_changed.emit(money)
	if power == "lightning":
		hubs_changed.emit()
	return text


func _lose(ship: Ship, reason: String) -> void:
	canal_traffic.leave(ship)
	ship.lost_reason = reason
	ship.lost_order = roundi(play_time * 1000.0)
	ship.at_risk = false
	makers.on_mishap(ship, true)  # (A maker whose goods are aboard isn't pleased.)
	ship_lost.emit(ship)
	ship_changed.emit(ship)


## Once a second (with the storm warnings): ships lying at anchor in port
## (waiting for a berth, idle, tugs, recovery boats and other service ships)
## ride out the storms there: one over STORM_BATTER_AT of its strength where
## the port is batters each ship once, taking STORM_BATTER of its maintenance.
func _batter_anchored() -> void:
	if weather.storms.is_empty() or not weather.active():
		return
	var at_ports := {}  # Port id -> [strongest storm, strength], once a step.
	for ship in ships:
		if not ship.is_docked() or ship.berth >= 0:
			continue
		if not at_ports.has(ship.docked_at):
			var port := GameData.get_port(ship.docked_at)
			at_ports[ship.docked_at] = weather.strongest_at(Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))))
		var found: Array = at_ports[ship.docked_at]
		if float(found[1]) <= STORM_BATTER_AT or ship.storm_hit == Weather.key(found[0]):
			continue
		ship.storm_hit = Weather.key(found[0])
		ship.maintenance = maxf(ship.maintenance - STORM_BATTER, 0.0)
		ship_battered.emit(ship, found[0])
		ship_changed.emit(ship)


## Every interval_s each ship at sea
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
		for ship in ships:
			if ship.is_service() and not ship.is_fishing() or ship.is_docked() or ship.is_lost() or canal_traffic.in_canal(ship) or not ship.weather_wait.is_empty() or ship.escort != null or randf() >= ship.breakdown_chance() * _storm_factors(ship)[1]:
				continue  # (A fishing boat breaks down like a cargo ship, and is towed in like one.)
			ship.maintenance = maxf(ship.maintenance - float(settings.get("hit", 0.5)), 0.0)
			ship.risk_check_time = 0.0  # Check at once whether it can still make port.
			if ship.maintenance > 0.0:
				makers.on_mishap(ship, false)  # (Lost, it's counted in _lose().)
			ship_broke_down.emit(ship)
			if ship.maintenance <= 0.0:
				_lose(ship, "broken down")


func _arrive(ship: Ship, port: String, paid := true) -> void:
	var t_x := Time.get_ticks_usec()
	_arrive_timed(ship, port, paid)
	MapView._prof("sim.arrive", t_x)

func _arrive_timed(ship: Ship, port: String, paid := true) -> void:
	# A refuel stop on its way to somewhere beyond one tank (see hop_to): no
	# trade here, its cargo (or catch) stays aboard for where it's bound. A new
	# route waiting to start drops the old plan.
	if not ship.pending_route.is_empty() or ship.hop_to == port:
		ship.hop_to = ""
	var refuel_stop := not ship.hop_to.is_empty()
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
	# leg's bonuses add to a profitable trade's profit.
	ship.cargo_payment = 0
	ship.cargo_leg_nm = 0.0
	if not ship.cargo_id.is_empty() and not refuel_stop:
		# Counted from where it was loaded (refuel stops on the way don't count as legs).
		var origin := ship.cargo_from if not ship.cargo_from.is_empty() and GameData.distance_nm(ship.cargo_from, port) < INF else ship.from_port
		var sale := ship.cargo_qty * company_sell_price(port, ship.cargo_id, owner_of(ship)) * ship.cargo_value_factor(play_time, days_per_second())
		ship.cargo_payment = roundi(sale + trade_bonus(origin, port, sale - ship.cargo_cost, ship.model_id, owner_of(ship)))
		ship.cargo_leg_nm = GameData.distance_nm(origin, port) if paid and origin != port else 0.0
	ship.unloaded = ship.is_service() and not ship.is_fishing() or refuel_stop
	ship.docked_at = port
	if ship.is_cruise() and not refuel_stop:
		cruises.arrived(ship, port)  # (A port of call, or home: the voyage's end.)
	ship.from_port = ""
	ship.to_port = ""
	ship.traveled_nm = 0.0
	if not ship.is_service() or ship.is_fishing():
		# Its stop waits for a berth: it anchors and queues (see _advance_docked()); a fishing boat lands its catch alongside.
		ship.berth = -1
		ship.berth_half = -1
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
	if ship.berth_phase == Ship.BERTH_WAIT:
		# With a berth free (and no one ahead of it), straight on in from the
		# harbour mouth: never a tick "waiting", or the map has it set off for
		# its spot to wait (a turn away) and back again.
		_claim_berth(ship)
	ship_changed.emit(ship)


## A cargo ship's stop needs a berth (see Docks): it waits at anchor for one,
## first come first served, comes alongside (at its own speed: _berth_seconds()), and only then does
## its stop; when it's done it pulls out (docks out_s), to sail or, if it
## can't go yet, to lie at the anchorage. The stop runs on a fixed clock:
## repair for one refill phase, then refuel for one, with unloading (and
## payment) over the first half of the dock time and loading over the second.
## Afterwards a running ship leaves as soon as it has the fuel for its next
## leg, and a Mammoth away from home sails back.
func _advance_docked(ship: Ship, delta: float) -> void:
	# A cargo ship waiting at the anchorage comes in to a pier while the port has
	# room to spare (and goes back out if it fills up: see below).
	if ship.berth < 0 and ship.berth_phase == Ship.BERTH_NONE and not ship.is_service() and not ship.is_docking() and not ship.is_on_job() and ship.is_running() and docks.free_berths(ship.docked_at) > WAIT_AT_PIER_FREE + 1:
		ship.berth_phase = Ship.BERTH_WAIT  # (An idle or paused ship lies at the moorings: see _wake_waiting_ships().)
	var t_ab := Time.get_ticks_usec()
	var berthing := not _advance_berth(ship, delta)
	MapView._prof("adv.berth", t_ab)
	if berthing:
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
	var t_ad := Time.get_ticks_usec()
	if ship.is_fishing():
		_fishing_in_port(ship, delta)
		MapView._prof("adv.fishing", t_ad)
	elif ship.is_service() and not ship.base_port.is_empty() and ship.docked_at != ship.base_port and not _on_ice_duty(ship):
		_try_depart(ship, delta, ship.base_port)
		MapView._prof("adv.try_depart", t_ad)
	elif ship.is_rig_runner() and ship.is_running():
		_rig_in_port(ship, delta)  # (Off to its field again, or back to its delivery port: see Energy.)
	elif ship.is_research() and ship.is_running():
		research.in_port(ship, delta)  # (Off on its expedition, or back to its base: see Research.)
	elif ship.is_cruise() and ship.is_running() and cruises.in_port(ship, delta):
		pass  # (A cruise ship in a refit, or at home taking bookings: see Cruises.)
	elif ship.is_running():
		_try_depart(ship, delta, ship.route[ship.next_route_index()])
		MapView._prof("adv.try_depart", t_ad)
	else:
		_set_hold(ship, "")
	if ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE and (docks.free_berths(ship.docked_at) < WAIT_AT_PIER_FREE or not ship.is_running() and not ship.is_service()):
		t_ad = Time.get_ticks_usec()
		_pull_out(ship, "")  # Done, but not going yet: it waits at its pier while the port has room, else off to the moorings; an idle or paused ship always goes to the moorings.
		MapView._prof("adv.pull_out", t_ad)


## A cargo ship's berth: queuing for one, coming alongside, pulling out. True
## once it's moored (or never needed one), when its stop can go on.
func _advance_berth(ship: Ship, delta: float) -> bool:
	var settings := Docks.settings()
	match ship.berth_phase:
		Ship.BERTH_WAIT:
			if _claim_berth(ship):
				var t_bs := Time.get_ticks_usec()
				ship_changed.emit(ship)
				MapView._prof("berth.changed", t_bs)
			return false
		Ship.BERTH_IN:
			ship.berth_time += delta
			if ship.berth_time < (ship.berth_duration if ship.berth_duration > 0.0 else float(settings.get("in_s", 6.0))):
				return false
			ship.berth_phase = Ship.BERTH_NONE
			ship_changed.emit(ship)
		Ship.BERTH_OUT:
			ship.berth_time += delta
			if ship.berth_time < (ship.berth_duration if ship.berth_duration > 0.0 else float(settings.get("out_s", 5.0))):
				return false
			docks.release(ship)
			ship.berth_phase = Ship.BERTH_NONE
			var to := ship.depart_to
			ship.depart_to = ""
			if ship.is_fishing() and ship.has_meta(&"fish_trip"):
				ship.remove_meta(&"fish_trip")
				_set_off_fishing(ship)  # (Clear of its pier: off on its trip. See _fishing_in_port().)
			elif ship.has_meta(&"rig_trip"):
				ship.remove_meta(&"rig_trip")
				_start_rig_trip(ship)  # (Clear of its pier: out to its field. See _rig_in_port().)
			elif ship.has_meta(&"research_trip"):
				ship.remove_meta(&"research_trip")
				research.start_trip(ship)  # (Clear of its pier: out on its expedition. See Research.in_port().)
			elif not to.is_empty():
				_set_off(ship, to, true)
			else:
				ship_changed.emit(ship)
			return false
	return true


## A ship waiting for a berth takes one if it's its turn and one's free, and
## starts coming alongside (BERTH_IN): true if it did.
func _claim_berth(ship: Ship) -> bool:
	var t_cl := Time.get_ticks_usec()
	var claimed := docks.claim(ship)
	MapView._prof("berth.claim", t_cl)
	if not claimed:
		return false
	ship.berth_phase = Ship.BERTH_IN
	ship.berth_time = 0.0
	var t_bs := Time.get_ticks_usec()
	ship.berth_duration = _berth_seconds(ship, true)
	MapView._prof("berth.seconds", t_bs)
	return true


## Starts pulling out of its berth, then sails for `to` ("" to anchor).
func _pull_out(ship: Ship, to: String) -> void:
	ship.berth_phase = Ship.BERTH_OUT
	ship.berth_time = 0.0
	ship.depart_to = to
	ship.berth_duration = _berth_seconds(ship, false)
	ship_changed.emit(ship)


## How long a ship's coming alongside (or pulling out) takes, s of play: the
## way in through its marina (or out) at its own speed, slowing only at the
## end (or getting going at the start), as berth_route (the map) works it out,
## plus, coming in, docks slide_s sliding onto its berth on its thrusters
## (pulling out it drives off ahead); without a map, docks in_s (out_s).
func _berth_seconds(ship: Ship, coming_in: bool) -> float:
	var settings := Docks.settings()
	if berth_route.is_valid():
		var sail: float = berth_route.call(ship, coming_in)
		if sail > 0.0:
			return sail + (float(settings.get("slide_s", 1.5)) if coming_in else 0.0)  # (It drives off: no slide.)
	return float(settings.get("in_s" if coming_in else "out_s", 6.0))


## Halfway through a stop: sells the cargo it brought (if any), then loads its
## next one for where it's going (if it's running a route).
func _unload(ship: Ship) -> void:
	var t_x := Time.get_ticks_usec()
	_unload_timed(ship)
	MapView._prof("sim.unload", t_x)

func _unload_timed(ship: Ship) -> void:
	ship.unloaded = true
	if ship.is_fishing() and ship.catch > 0.0 and ship.docked_at == ship.base_port:  # (Elsewhere it's on its way home: see _fishing_in_port().)
		_land_catch(ship, ship.docked_at)
	if not ship.cargo_id.is_empty() and not owner_of(ship).plants.is_empty():
		_deliver_to_plants(ship)  # (Its company's refineries here take what their tanks have room for: see Energy.)
	if not ship.cargo_id.is_empty():
		var t_u := Time.get_ticks_usec()
		_sell_cargo(ship)
		MapView._prof("unload.sell", t_u)
	if ship.is_running() and not ship.is_refuel_stop() and not ship.is_rig_runner():
		var t_l := Time.get_ticks_usec()
		_load_cargo(ship, ship.route[ship.next_route_index()])
		MapView._prof("unload.load", t_l)
	var t_c := Time.get_ticks_usec()
	ship_changed.emit(ship)
	MapView._prof("unload.changed", t_c)


func _sell_cargo(ship: Ship) -> void:
	var who := owner_of(ship)
	var stolen := roundi(ship.cargo_payment * divine.stolen(ship))
	if stolen > 0:  # The frigatebirds following it take their cut (Divine).
		ship.cargo_payment -= stolen
		if who == company:
			ActivityLog.add("The frigatebirds following %s made off with %s of its sale at %s." % [ship.name, Fmt.money(stolen), GameData.port_name(ship.docked_at)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))
	# What its company's sites at the port take as inputs goes into their store, at
	# the port's buy price (what they'd have paid for it there): see Industry.
	var into_sites := industry.take_delivery(ship)
	var site_value := int(into_sites[1])
	if int(into_sites[0]) > 0:
		ship.cargo_payment = roundi(ship.cargo_payment * (1.0 - float(into_sites[0]) / ship.cargo_qty)) + site_value
	ship.stop_sale = ship.cargo_payment
	ship.stop_cost = ship.cargo_cost
	_add_money(who, ship.cargo_payment)
	_record(ship, "income", ship.cargo_payment)
	if site_value > 0:
		_add_money(who, -site_value)
		_record(null, "industry", site_value, who)
	if ship.cargo_cut > 0.0:  # From its factory: the maker's cut of the sale, as the cargo's cost (see Manufacturers.load_ship()).
		var cut := roundi(ship.cargo_payment * ship.cargo_cut)
		_add_money(who, -cut)
		_record(ship, "cargo", cut)
		ship.stop_cost = cut
		ship.cargo_cost = cut
		ship.cargo_cut = 0.0
	makers.on_trade(who, ship.cargo_id, ship.cargo_payment, false)
	_tally_port_trade(who, ship.docked_at, ship.cargo_id, ship.cargo_qty, ship.cargo_payment, true)
	if world.zone_of_port(ship.docked_at) >= 0 and world.good_index(ship.cargo_id) >= 0:
		world.add_inbound(world.zone_of_port(ship.docked_at), world.good_index(ship.cargo_id), -ship.cargo_qty)
	var t_s := Time.get_ticks_usec()
	market.trade(ship.docked_at, ship.cargo_id, ship.cargo_payment - site_value, false)
	MapView._prof("sell.trade", t_s)
	port_sizes.add_traffic(ship.docked_at, ship.cargo_payment)
	who.delivered[ship.cargo_id] = int(who.delivered.get(ship.cargo_id, 0)) + ship.cargo_qty
	var fee := port_fee(ship.docked_at, ship.cargo_payment - ship.cargo_cost, who, Progression.type_of_model(ship.model()))
	if fee > 0:
		_add_money(who, -fee)
		_record(ship, "port_fees", fee)
	var t_e := Time.get_ticks_usec()
	cargo_sold.emit(ship, ship.docked_at, ship.cargo_id, ship.cargo_qty, ship.cargo_cost, ship.cargo_payment, ship.stop_toll, fee)
	MapView._prof("sell.sold", t_e)
	var hub := hub_at(ship.docked_at, who)
	ship.delivery_canals.clear()
	if hub:
		hub.deliveries += 1
		hub.income += ship.cargo_payment
	ship.cargo_id = ""
	ship.cargo_qty = 0
	ship.cargo_cost = 0
	ship.cargo_payment = 0


## Buys the most profitable cargo the ship can carry to its next port (see
## Market.best_cargo()): a full hold (less what a canal makes it leave behind),
## or as much as its company's money allows while keeping its fuel reserve
## (see fuel_reserve()) and bank_reserve, unless full loads are on, when it
## buys nothing short of a full hold. Nothing if no cargo makes a profit.
## Returns the cargo it chose (bought or not, for lack of money), or "" if none pays.
func _load_cargo(ship: Ship, to: String) -> String:
	if ship.is_service() or not ship.cargo_id.is_empty() or not ship.is_docked() or to.is_empty() or to == ship.docked_at:
		return ""
	ship.cargo_breed = ""
	ship.cargo_fresh = 1.0
	ship.cargo_since = play_time
	ship.cargo_farm = false
	if str(ship.model().get("category", "")) == "seafood":
		var t_st := Time.get_ticks_usec()
		var stored := _load_from_store(ship, to)
		MapView._prof("load.store", t_st)
		if not stored.is_empty():
			return stored[0]
	if owner_of(ship).farm_stores.has(ship.docked_at):  # (Its farm's harvest, free: see Farms.load_ship().)
		var farmed := farms.load_ship(ship, to)
		if not farmed.is_empty():
			return farmed[0]
	ship.cargo_cut = 0.0
	if not owner_of(ship).factories.is_empty():  # (Its factory's output, free: see Manufacturers.load_ship().)
		var made := makers.load_ship(ship, to)
		if not made.is_empty():
			return made[0]
	if owner_of(ship).energy_stores.has(ship.docked_at):  # (Its refineries' and pipelines' goods, free: see Energy.load_ship().)
		var stored := energy.load_ship(ship, to)
		if not stored.is_empty():
			return stored[0]
	var mined := industry.load_ship(ship, to)  # (Its mines', plants' and factories' output, free: see Industry.load_ship().)
	if not mined.is_empty():
		return mined[0]
	var who := owner_of(ship)
	var t_b := Time.get_ticks_usec()
	var feed := energy.feed_for(ship, to) if not who.plants.is_empty() else ""
	var best := [feed] if not feed.is_empty() else market.best_cargo(ship.model(), ship.docked_at, to, who)  # (Input for its refinery there first: see Energy.feed_for().)
	MapView._prof("load.best", t_b)
	if best[0] == "":
		return ""
	var price := company_buy_price(ship.docked_at, best[0], who)
	var reserve := fuel_reserve(who)
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())) / GameData.hold_of(best[0]))
	var quantity := mini(room, floori((float(who.money) - ship.bill - reserve - who.bank_reserve) / price))
	if in_debt(who):
		quantity = room  # On credit (see in_debt()).
	var zone := world.zone_of_port(ship.docked_at)
	var good := world.good_index(best[0])
	if zone >= 0 and good >= 0:
		quantity = mini(quantity, floori(world.zone_stock(zone, good)))  # (No more than the zone has.)
	if quantity <= 0 or (ship.full_loads and quantity < room):
		# What a full hold would need in the bank, for ships waiting for one.
		ship.load_need = roundi(room * price + ship.bill + reserve + who.bank_reserve)
		return best[0]
	var cost := roundi(quantity * price)
	var t_m := Time.get_ticks_usec()
	_add_money(who, -cost)
	_record(ship, "cargo", cost)
	_tally_port_trade(who, ship.docked_at, best[0], quantity, cost, false)
	MapView._prof("load.money", t_m)
	t_m = Time.get_ticks_usec()
	if not Manufacturers.first_pick(who, ship.docked_at, best[0]):  # (A maker that likes it enough holds the price for it.)
		market.trade(ship.docked_at, best[0], cost, true)
	makers.on_trade(who, best[0], cost, true)
	port_sizes.add_traffic(ship.docked_at, cost)
	MapView._prof("load.trade", t_m)
	ship.cargo_id = best[0]
	ship.cargo_from = ship.docked_at
	ship.cargo_qty = quantity
	ship.cargo_cost = cost
	var t_e := Time.get_ticks_usec()
	cargo_loaded.emit(ship, ship.docked_at, best[0], quantity, cost, to)
	if good >= 0 and world.zone_of_port(to) >= 0:
		world.add_inbound(world.zone_of_port(to), good, quantity)  # (On its way: the price there looks ahead to it.)
	MapView._prof("load.loaded", t_e)
	ship_changed.emit(ship)
	return best[0]


## Fuel a ship must have to set off on a leg: enough for the leg, allowing for
## wear, plus a little spare.
func _fuel_to_leave(ship: Ship, to: String) -> float:
	return ship.fuel_needed(ship.docked_at, to) + ship.fuel_per_s() * DEPARTURE_MARGIN_S


## Leaves once it has fuel for the leg to `to`. A ship that ran out of money
## while refilling tops up (as the toggles and money allow) until its tank is
## full or the money runs out, and is held in port while it lacks fuel for the leg.
func _try_depart(ship: Ship, delta: float, to: String) -> void:
	# Waiting for a full load, and not due another look (see _waiting_for_load()).
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and _short_of_load(ship):
		return
	if not ship.fits_port(to):
		_set_hold(ship, "%s is too small for this ship; assign a new route" % GameData.port_name(to))
		return
	# Beyond one tank: the next refuel stop on the way (see refuel_path()) is
	# where it sails now, and it carries on from there. Its cargo is still for `to`.
	var bound := to
	if not ship.can_sail(ship.docked_at, to):
		if ship.reach_check_to == to and play_time < ship.reach_check_time and not ship.hold_reason.is_empty():
			return  # (Held as beyond its reach: not due another look.)
		var path := refuel_path(ship, ship.docked_at, to)
		if path.is_empty():
			_set_hold(ship, "%s is beyond this ship's reach, even refuelling on the way; assign a new route" % GameData.port_name(to))
			ship.reach_check_to = to
			ship.reach_check_time = play_time + REACH_RECHECK_S
			return
		to = path[0]
	ship.bound_for = bound  # (Becomes its hop_to as it sets off for `to`: see _set_off().)
	ship.bound_step = to
	# A storm over the port: wait it out (nothing for the player to do).
	var storm := weather.closed_by(ship.docked_at)
	if not storm.is_empty():
		ship.weather_wait = "%s is closed by %s" % [GameData.port_name(ship.docked_at), Weather.title(storm)]
		return
	# A leg it couldn't finish before a seasonal closure shuts its way: wait for
	# the closure to end (again nothing for the player to do).
	if seasonal.active():
		# Costly to work out, and closures come and go by the calendar day: looked
		# at again only every SEASON_RECHECK_S (or for a new destination).
		if play_time >= ship.season_check_time or ship.season_check_to != to or play_time < ship.season_check_time - SEASON_RECHECK_S:
			ship.season_check_time = play_time + SEASON_RECHECK_S
			ship.season_check_to = to
			var seconds := ship.leg_seconds(ship.docked_at, to, 0.0, GameData.distance_nm(ship.docked_at, to), maxf(ship.maintenance, 0.01))
			ship.season_blocker = seasonal.leg_blocker(ship.docked_at, to, seconds)
		if not ship.season_blocker.is_empty():
			ship.weather_wait = Seasons.wait_text(ship.season_blocker)
			return
	ship.weather_wait = ""
	# A cargo ship lying at the anchorage loads, refuels and repairs only in
	# port: it comes in for a stop if it needs to (see _anchored_call()).
	var anchored := not ship.is_service() and ship.berth < 0
	if anchored and _anchored_call(ship, to, bound):
		return
	var phase := ship.refill_phase_seconds()
	var topping_up := not anchored and ship.auto_refuel and ship.fuel < ship.fuel_tank() and _can_spend(ship)
	if topping_up or ship.fuel < _fuel_to_leave(ship, to):
		var too_worn := _fuel_to_leave(ship, to) > ship.fuel_tank()
		if anchored:
			pass  # (Can't take fuel or repairs out here: it says why below.)
		elif too_worn and ship.auto_repair:
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
	if not ship.is_refuel_stop() and _waiting_for_load(ship, bound):
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


## A cargo ship lying at the anchorage, about to sail for `to`: comes into port
## for a stop (queuing for a berth: see _call_in()) when it has a cargo to
## pick up for the leg (once it can afford a full one, with full loads on), or
## needs fuel for the leg or repairs (under DIRECT_DEPART_MAINTENANCE) and has
## the money for them. True if it's coming in or waiting; false if it can go
## on to set off straight from the anchorage (or be held for a reason the
## stop wouldn't help: out of range, no money for fuel...).
func _anchored_call(ship: Ship, to: String, bound := "") -> bool:
	var who := owner_of(ship)
	if bound.is_empty():
		bound = to
	if ship.cargo_id.is_empty() and not ship.is_refuel_stop():
		var best: String = market.best_cargo(ship.model(), ship.docked_at, bound, who)[0]
		if not best.is_empty():
			if ship.full_loads and not in_debt(who):
				var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, bound, ship.model())))
				ship.load_need = roundi(room * company_buy_price(ship.docked_at, best, who) + ship.bill + fuel_reserve(who) + who.bank_reserve)
				if who.money < ship.load_need:
					ship.load_check_time = play_time + LOAD_RECHECK_S
					_set_hold(ship, "")
					var reason := "waiting for money for a full load to %s" % GameData.port_name(bound)
					if who.bank_reserve > 0:
						reason += " (keeping %s in the bank)" % Fmt.money(who.bank_reserve)
					_set_load_wait(ship, reason)
					return true
			_set_load_wait(ship, "")
			_call_in(ship)
			return true
	_set_load_wait(ship, "")
	var need := _fuel_to_leave(ship, to)
	var short_of_fuel := ship.fuel < need and need <= ship.fuel_tank() and ship.auto_refuel
	var worn := ship.maintenance < DIRECT_DEPART_MAINTENANCE and ship.auto_repair
	if (short_of_fuel or worn) and _can_spend(ship):
		_call_in(ship)
		return true
	return false


## A cargo ship lying at the anchorage comes into port for a stop: it queues
## for a berth, comes alongside and does a stop as if it had just arrived
## (repairs, fuel, loading for its next leg; a cargo already aboard stays
## aboard), then sails.
func _call_in(ship: Ship) -> void:
	ship.unloaded = not ship.cargo_id.is_empty()
	ship.berth = -1
	ship.berth_half = -1
	ship.berth_phase = Ship.BERTH_WAIT
	ship.berth_since = play_time
	docks.join_queue(ship)
	ship.dock_time = 0.0
	ship.refill_billed = 0.0
	var phase := ship.refill_phase_seconds()
	ship.repair_rate = (1.0 - ship.maintenance) / phase
	ship.refuel_rate = (ship.fuel_tank() - ship.fuel) / phase
	ship.stop_sale = 0
	ship.stop_cost = 0
	ship.stop_fuel_cost = 0.0
	ship.stop_repair_cost = 0.0
	_set_hold(ship, "")
	ship_changed.emit(ship)


## With full loads on, a cargo ship with an empty hold stays in port until it
## can buy a full one (see _load_cargo()), saying why in its load_wait. A leg
## where no cargo makes a profit is sailed empty straight away.
func _waiting_for_load(ship: Ship, to: String) -> bool:
	if ship.is_service() or not ship.full_loads or not ship.cargo_id.is_empty():
		_set_load_wait(ship, "")
		return false
	# Already waiting: look again as soon as the money reaches what a full hold
	# needed, and otherwise only every LOAD_RECHECK_S (prices drift slowly).
	if not ship.load_wait.is_empty() and play_time < ship.load_check_time and _short_of_load(ship):
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
	var t_x := Time.get_ticks_usec()
	_depart_timed(ship, to)
	MapView._prof("sim.depart", t_x)

func _depart_timed(ship: Ship, to: String) -> void:
	if ship.berth >= 0:
		if ship.berth_phase != Ship.BERTH_OUT:
			_pull_out(ship, to)
		return
	_set_off(ship, to)


## Sets off for `to`: from a berth (it may still load there, if it didn't when
## unloading: a new ship, or a new route), or straight from the anchorage.
func _set_off(ship: Ship, to: String, from_berth := false) -> void:
	docks.release(ship)  # It might have been queuing (a convoy leaving an iced port).
	var bound := ship.bound_for if not ship.bound_for.is_empty() and ship.bound_step == to else to
	ship.bound_for = ""
	ship.bound_step = ""
	ship.berth_phase = Ship.BERTH_NONE
	if not ship.is_service():
		ship.route_index = ship.next_route_index()
		if from_berth and not ship.is_refuel_stop():  # (No trade at a refuel stop.)
			_load_cargo(ship, bound)
	ship.hop_to = bound if bound != to else ""  # (Bound beyond this leg: the port it's sailing to is a refuel stop.)
	_leave_port(ship)
	ship.from_port = ship.docked_at
	ship.to_port = to
	ship.risk_check_time = 0.0
	ship.storm_check_time = 0.0
	ship.ice_check_time = 0.0
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
	# (Asked for every tug model at once: a loop over the fleet, kept for the frame.)
	var frame := Engine.get_process_frames()
	if _tug_ports_frame == frame and _tug_ports_of == of:
		return _tug_ports_kept
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
	_tug_ports_frame = frame
	_tug_ports_of = of
	_tug_ports_kept = out
	return out

var _tug_ports_frame := -1
var _tug_ports_of: Company = null
var _tug_ports_kept: Array[String] = []


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
				and not tug.is_on_job() and _tug_can_fetch(tug, miles))
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


## Whether a free tug reaches, and has the fuel, to fetch a ship `miles` out.
func _tug_can_fetch(tug: Ship, miles: float) -> bool:
	return tug.reach_nm() >= miles and tug.fuel >= _tug_fuel(tug, miles)


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
## added up (the other pulling beside it), each burning fuel and wearing as
## it goes, and hands it over at their port; there they work it in to its
## berth (or its spot at the anchorage) and let it go.
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
		Ship.JOB_BERTH:
			tug.align_time += delta
			if not tug.tug_lead:
				return  # Its lead lets them both go (see below).
			var lost := tug.rescuing
			var done := lost == null or lost.docked_at != tug.tow_port
			if not done:
				if tug.assist_s < 0.0:
					done = lost.berth_phase != Ship.BERTH_IN  # Moored (or off again).
				else:
					done = tug.align_time >= tug.assist_s or lost.berth_phase == Ship.BERTH_IN
			if done:
				_release_tugs(tug, tug.tug_team())


## Hands the towed ship over at the tugs' port (paid as usual if that's where
## it was going); they stay with it to bring it
## alongside its berth (or to its spot at the anchorage) before they let go.
func _deliver_tugs(lead: Ship, team: Array[Ship]) -> void:
	var lost := lead.rescuing
	var port := lead.tow_port
	var to_destination := port == lost.to_port
	ship_recovered.emit(lost, lead, port, to_destination)  # While the team's still together, for its names.
	for tug in team:
		# On to work it in (still holding it: see JOB_BERTH in _advance_tug_job()).
		tug.job_phase = Ship.JOB_BERTH
		tug.job_segments.clear()
		tug.align_time = 0.0
		tug.job_nm = 0.0
		tug.carry_nm = 0.0
	lost.rescuer = lead
	lost.lost_reason = ""
	_arrive(lost, port, to_destination)
	# Alongside its berth if it can have one now (as it would next step), else
	# to its spot at the anchorage to wait.
	if lost.berth_phase == Ship.BERTH_WAIT and docks.claim(lost):
		lost.berth_phase = Ship.BERTH_IN
		lost.berth_time = 0.0
		lost.berth_duration = _berth_seconds(lost, true)
	var anchoring := lost.berth_phase != Ship.BERTH_IN
	var anchor_s := float(anchor_route.call(lost)) if anchoring and anchor_route.is_valid() else TUG_ANCHOR_S
	for tug in team:
		tug.assist_s = anchor_s if anchoring else -1.0
		ship_changed.emit(tug)


## Lets the ship go once the tugs have it moored (or at its spot at the
## anchorage), and docks them at their port.
func _release_tugs(lead: Ship, team: Array[Ship]) -> void:
	var port := lead.tow_port
	var lost := lead.rescuing
	for tug in team:
		tug.rescuing = null
		tug.job_phase = Ship.JOB_NONE
		tug.tow_port = ""
		tug.tug_lead = false
		tug.assist_s = -1.0
		tug.align_time = 0.0
		_arrive(tug, port, false)
		ship_changed.emit(tug)
	if lost != null:
		lost.rescuer = null
		ship_changed.emit(lost)


# --- Canals ----------------------------------------------------------------

## Extra money on a profitable trade from a leg's bonuses: the profit x (the
## leg's sale factor (rough seas, upper lakes) plus its canals' bonuses - 1).
## Nothing on a loss.
func trade_bonus(from_port: String, to_port: String, profit: float, model_id := "", of: Company = null) -> float:
	if profit <= 0.0:
		return 0.0
	return profit * (trade_bonus_factor(from_port, to_port, model_id, of) - 1.0)


## What a leg's bonuses multiply a profitable trade's profit by (see trade_bonus()):
## its sale factor plus its canals' profit bonuses.
func trade_bonus_factor(from_port: String, to_port: String, _model_id := "", _of: Company = null) -> float:
	return GameData.sale_factor(from_port, to_port) + GameData.leg_canal_profit_bonus(from_port, to_port)


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
	var value := ship.cargo_qty * market.sell_price(ship.to_port, ship.cargo_id) * ship.cargo_value_factor(play_time, days_per_second())
	return roundi(value * float(canal.get("toll_share", 0.0)))


## Charges a canal toll to a ship's ledger and the finances.
func record_toll(ship: Ship, canal: Dictionary, toll: int) -> void:
	_record(ship, "tolls", toll)
	var stats: Dictionary = owner_of(ship).canal_stats.get_or_add(canal.id, {crossings = 0, tolls = 0.0})
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
	if waiting.is_empty():
		return
	waiting.sort_custom(func(a: Ship, b: Ship) -> bool: return a.lost_order < b.lost_order)
	# Working out a recovery is costly, and most of the time every boat that
	# could fetch a ship is busy: a ship no free tug or boat could fetch is
	# skipped (what's free is looked at again after each one sent).
	var free := _free_rescuers()
	for ship: Ship in waiting:
		if not _could_fetch(ship, free):
			continue
		if _send_recovery(ship, true).is_empty() and ship.rescuer != null:
			free = _free_rescuers()


## Who could set out on a recovery now (see tug_plan() and recovery_plan()):
## {boats: company -> its free recovery boats, tugs: [company, port] -> the
## free tugs based there}.
func _free_rescuers() -> Dictionary:
	var boats := {}
	var tugs := {}
	for ship in ships:
		if ship.is_on_job() or not ship.is_docked() or ship.is_docking():
			continue
		if ship.is_recovery():
			(boats.get_or_add(owner_of(ship), []) as Array).append(ship)
		elif ship.is_tug() and ship.base_port == ship.docked_at:
			(tugs.get_or_add([owner_of(ship), ship.docked_at], []) as Array).append(ship)
	return {boats = boats, tugs = tugs}


## Whether any of the free rescuers (see _free_rescuers()) might fetch a lost
## ship: a tug at either end of its leg that reaches it, or a boat that can
## carry it on its lane. (If none, recovery_plan() would find none either.)
func _could_fetch(lost: Ship, free: Dictionary) -> bool:
	var owner := owner_of(lost)
	if not lost.from_port.is_empty():
		for end: Array in [[lost.from_port, lost.traveled_nm], [lost.to_port, lost.leg_length() - lost.traveled_nm]]:
			for tug: Ship in free.tugs.get([owner, end[0]], []):
				if _tug_can_fetch(tug, maxf(float(end[1]), 0.0)):
					return true
	for boat: Ship in free.boats.get(owner, []):
		if boat.can_carry(lost) and boat.fits_lane(lost.from_port, lost.to_port):
			return true
	return false


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
	if Fisheries.is_ground(tow_port):  # A fishing boat lost on its ground: taken in to the port its lane comes from, not out to the ground.
		tow_port = b if tow_port == a else a
	# With tugs based there, it only carries the ship within their reach (a
	# little inside it) and floats it off at sea for them to tow in.
	var handoff := _tug_handoff_nm(tow_port, owner_of(lost))
	var carry := minf(done, left)
	var short := handoff if handoff > 0.0 and carry > handoff else 0.0
	if tow_port == a:
		segments.append([b, a, left, left + done - short])
	else:
		segments.append([a, b, done, done + left - short])
	var approach_nm := minf(via_a, via_b)
	var seconds := mammoth.sailing_seconds(approach_nm + carry - short, mammoth.maintenance)
	var home_seconds := 0.0
	if tow_port != mammoth.base_port:
		home_seconds = mammoth.sailing_seconds(GameData.distance_nm(tow_port, mammoth.base_port), 1.0)
	var into_port := mammoth.sailing_seconds(short, mammoth.maintenance) if short > 0.0 else 0.0  # After handing it to the tugs.
	var running := seconds + into_port + home_seconds
	return {
		mammoth = mammoth,
		segments = segments,
		tow_port = tow_port,
		approach_nm = approach_nm,
		handoff_nm = short,
		seconds = seconds + Ship.ALIGN_SECONDS + Ship.LOAD_SECONDS * 2.0 + (Ship.SPIN_SECONDS if (tow_port == a) == (via_a <= via_b) else 0.0),
		fuel = mammoth.fuel_per_s() * (seconds + into_port + DEPARTURE_MARGIN_S),
		cost = mammoth.fuel_per_s() * running * market.fuel_price(mammoth.docked_at)
			+ minf(mammoth.wear_per_s() * running, 1.0) * mammoth.full_repair_cost() * port_sizes.cost_factor(mammoth.docked_at),
	}


func _start_segment(ship: Ship, segment: Array) -> void:
	ship.from_port = segment[0]
	ship.to_port = segment[1]
	ship.traveled_nm = segment[2]
	ship.segment_end = segment[3]
	ship.storm_check_time = 0.0
	ship.ice_check_time = 0.0
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
	var lane_end := GameData.distance_nm(mammoth.from_port, mammoth.to_port)
	if mammoth.traveled_nm < lane_end - 0.01:
		_hand_to_tugs(mammoth, lost)
		return
	mammoth.rescuing = null
	mammoth.job_phase = Ship.JOB_NONE
	mammoth.job_segments.clear()
	mammoth.tow_port = ""
	lost.rescuer = null
	lost.lost_reason = ""
	_arrive(mammoth, port, false)
	_arrive(lost, port, to_destination)
	ship_recovered.emit(lost, mammoth, port, to_destination)


## How far out (nm) a recovery boat leaves a ship for the tugs based at a port
## to tow in: a little inside the longest reach of the company's tugs there,
## or 0 if it has none (the boat takes the ship all the way in).
func _tug_handoff_nm(port_id: String, of: Company) -> float:
	var reach := 0.0
	for tug: Ship in tugs_at(port_id, of):
		reach = maxf(reach, tug.reach_nm())
	return reach * TUG_HANDOFF_SHARE


## A recovery boat that's carried a ship within its port's tugs' reach floats
## it off there and sails on into port itself; the ship, lost again at that
## spot on its own leg, is fetched by the tugs (now, or once they're free).
func _hand_to_tugs(mammoth: Ship, lost: Ship) -> void:
	var port := mammoth.tow_port
	lost.traveled_nm = mammoth.traveled_nm if mammoth.from_port == lost.from_port else lost.leg_length() - mammoth.traveled_nm
	lost.rescuer = null
	mammoth.rescuing = null
	mammoth.job_phase = Ship.JOB_NONE
	mammoth.job_segments.clear()
	mammoth.tow_port = ""
	mammoth.align_time = 0.0
	mammoth.segment_end = 0.0
	tugs_handed.emit(lost, mammoth, port)
	ship_changed.emit(mammoth)
	ship_changed.emit(lost)
	_send_recovery(lost, true)  # Its port's tugs, if they're free.


## Restores up to `amount` of maintenance, as far as money allows.
func _repair(ship: Ship, amount: float) -> void:
	amount = minf(amount, 1.0 - ship.maintenance)
	if amount <= 0.0:
		return
	var cost := amount * ship.full_repair_cost() * port_sizes.cost_factor(ship.docked_at) * Research.perk(owner_of(ship), "repairs")
	var paid := _spend(ship, cost, "repair")
	ship.stop_repair_cost += paid
	ship.maintenance = minf(ship.maintenance + amount * paid / cost, 1.0)


## Adds up to `amount` of fuel, as far as money allows.
func _refuel(ship: Ship, amount: float) -> void:
	amount = minf(amount, ship.fuel_tank() - ship.fuel)
	if amount <= 0.0:
		return
	if not owner_of(ship).energy_stores.is_empty():  # Free from its company's own Diesel here (see Energy.bunker()).
		var free := energy.bunker(ship, amount, market.fuel_price(ship.docked_at))
		ship.fuel = minf(ship.fuel + free, ship.fuel_tank())
		amount -= free
		if amount <= 0.001:
			return
	var cost := amount * market.fuel_price(ship.docked_at)
	var paid := _spend(ship, cost, "fuel")
	ship.stop_fuel_cost += paid
	ship.fuel = minf(ship.fuel + amount * paid / cost, ship.fuel_tank())


## Spends up to `cost` dollars of a kind ("fuel" or "repair") without going
## below $0 (or all of it on credit, if its company is in debt already: see
## in_debt()) and returns what was spent. Money is whole dollars, so fractions
## build up on the ship's bill.
func _spend(ship: Ship, cost: float, kind: String) -> float:
	if cost <= 0.0:
		return 0.0
	var paid := cost if in_debt(owner_of(ship)) else minf(cost, float(owner_of(ship).money) - ship.bill)
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
## a whole: buying and selling ships, founding hubs), in its company's finances
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


## Counts a company's trade at a port (Company.port_trade): `units` of a
## commodity bought there for `money` (sold false) or sold there for it.
func _tally_port_trade(who: Company, port: String, commodity: String, units: int, money: float, sold: bool) -> void:
	if port.is_empty() or commodity.is_empty() or units <= 0:
		return
	var here: Dictionary = who.port_trade.get_or_add(port, {since = play_time, goods = {}})
	var tally: Array = (here.goods as Dictionary).get_or_add(commodity, [0, 0.0, 0, 0.0])
	var at := 2 if sold else 0
	tally[at] = int(tally[at]) + units
	tally[at + 1] = float(tally[at + 1]) + money


## Game time (s of play) in a 30-day month, for the port trade summary's rates.
const TRADE_MONTH_DAYS := 30.0

## A company's (this player's by default) trade at a port, for the port
## popup's trade tab: {days (of game time it's been counted), rows: [{id,
## bought, spent, sold, earned, industry (what a building for it here
## would have saved and added, a month: its buy discount off the spending
## and its sell bonus on the earnings, the HQ's more), built (one stands
## here)}] most worth an industry first}.
func port_trade_summary(port: String, of: Company = null) -> Dictionary:
	var who := of if of != null else company
	var here: Dictionary = who.port_trade.get(port, {})
	var days := maxf(play_time - float(here.get("since", play_time)), 0.0) * calendar_seconds_per_second() / 86400.0
	var hub := who.hub_at(port)
	var warehouse := Hub.industry_settings()
	var boost := float(Hub.settings().get("hq_multiplier", 1.5)) if hub != null and hub.is_hq else 1.0
	var per_month := TRADE_MONTH_DAYS / maxf(days, 1.0)
	var rows := []
	for id: String in here.get("goods", {}):
		var tally: Array = here.goods[id]
		var built := hub != null and hub.has_industry(id)
		var worth := (float(tally[1]) * float(warehouse.get("buy_discount", 0.2)) + float(tally[3]) * float(warehouse.get("sell_bonus", 0.2))) * boost
		rows.append({id = id, bought = int(tally[0]), spent = float(tally[1]), sold = int(tally[2]), earned = float(tally[3]),
			industry = worth * per_month, built = built})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.industry) > float(b.industry))
	return {days = days, rows = rows}


## A company's (this player's by default) bucket of recent money for now.
func _current_bucket(of: Company = null) -> Dictionary:
	var window := (of if of != null else company).finance_window
	var start := floorf(play_time / BUCKET_SECONDS) * BUCKET_SECONDS
	if window.is_empty() or window[-1].start < start:
		window.append({start = start, fleet = {}, ships = {}})
	var keep := maxf(WINDOW_SECONDS, ship_window_seconds())
	while window[0].start < play_time - keep:
		window.pop_front()
	return window[-1]


## A company's money (this player's by default) over the last `seconds` of
## play (WINDOW_SECONDS by default; ship_window_seconds() for the ships'
## earnings): {fleet: {kind: amount}, ships: {ship name: profit}}.
func recent_finances(of: Company = null, seconds := WINDOW_SECONDS) -> Dictionary:
	var fleet := {}
	var ship_profit := {}
	for bucket: Dictionary in (of if of != null else company).finance_window:
		if bucket.start < play_time - seconds:
			continue
		for kind: String in bucket.fleet:
			fleet[kind] = float(fleet.get(kind, 0.0)) + bucket.fleet[kind]
		for ship_name: String in bucket.ships:
			var tally: Dictionary = bucket.ships[ship_name]
			var costs := 0.0
			for kind: String in ["fuel", "repair", "tolls", "cargo", "port_fees", "wages"]:
				costs += float(tally.get(kind, 0.0))
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
func found_company_error(new_name: String, new_home_port: String, new_color := "") -> String:
	if new_name.strip_edges().is_empty():
		return "Enter a company name."
	if not new_color.is_empty() and color_taken(new_color):
		return "Another company has that color: pick another."
	if GameData.get_port(new_home_port).is_empty():
		return "Pick a home port."
	if GameData.start_info(new_home_port).is_empty():
		return "Pick one of the starting ports on the globe."
	for each in all_companies():
		if each.home_port == new_home_port:
			return "%s is already %s's home port: pick another." % [GameData.port_name(new_home_port), each.name]
		if each.name.to_lower() == new_name.strip_edges().to_lower():
			return "There's already a company called %s." % each.name
	return ""


## Founds a company in this game (a joining player's), with the starting money,
## its HQ at its home port, the company type they chose and the CEO they made
## (Characters.clean(): a random one if it won't do). Returns its place in companies.
func found_company(new_name: String, new_color: String, new_home_port: String, new_ceo := {}, new_type := "cargo") -> int:
	new_color = free_color(new_color)  # (Never a color another company has.)
	var founded := Company.new(new_name.strip_edges().left(MAX_COMPANY_NAME_LENGTH), new_color, new_home_port)
	founded.money = int(GameData.config.get("starting_money", 10000))
	var playable: bool = not Progression.company_type(new_type).is_empty() and not Progression.company_type(new_type).get("coming_soon", false)
	founded.company_types = {new_type if playable else "cargo": 1}
	founded.logo = CompanyLogo.default_logo(founded.color)
	founded.ceo = Characters.clean(new_ceo)
	if founded.ceo.is_empty():
		founded.ceo = Company.random_ceo()
	founded.hubs.assign([Hub.new(new_home_port, true)])
	if companies.is_empty():
		companies.assign([company])
	companies.append(founded)
	save_game()
	return companies.size() - 1


## True if a company in the game (a player's or a rival's) has a color already:
## no two companies share one, in single player or multiplayer.
func color_taken(color_id: String, but: Company = null) -> bool:
	for each: Company in all_companies():
		if each != but and each.color == color_id:
			return true
	return false


## The first color no company has (picker order), or the one given if free.
func free_color(wanted := "") -> String:
	if not wanted.is_empty() and not color_taken(wanted):
		return wanted
	for entry: Array in GameData.config.get("company_colors", []):
		if not color_taken(str(entry[0])):
			return str(entry[0])
	return wanted

## A joined player's own map and log settings (Company.PREF_KEYS), kept in the
## host's save.
func set_prefs(prefs: Dictionary) -> void:
	var kept := {}
	for key in Company.PREF_KEYS:
		if prefs.has(key):
			kept[key] = prefs[key]
	company.apply_update(kept)


## Dresses a company's people of a role ("captain" or "crew") on a line (a
## model category, see CrewLooks): part "hat", "shirt" or "trousers" set to a
## choice of CrewLooks.choices(part); an empty part puts that role's outfit
## back to the line's default.
func set_uniform(line: String, role: String, part: String, value: String) -> void:
	if Net.command(&"set_uniform", [line, role, part, value]):
		return
	if not role in CrewLooks.ROLES or not CrewLooks.has_line(line):
		return
	var lines: Dictionary = company.uniforms.get(line, {})
	var outfit: Dictionary = lines.get(role, {})
	if part.is_empty():
		outfit = {}
	elif CrewLooks.is_choice(part, value):
		if value == str(CrewLooks.default_outfit(line, role)[part]):
			outfit.erase(part)
		else:
			outfit[part] = value
	else:
		return
	lines[role] = outfit
	company.uniforms[line] = lines
	uniforms_changed.emit(company)


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
		if ship.is_tug() and ship.job_phase in [Ship.JOB_ALIGN, Ship.JOB_BERTH]:
			ship.align_time += delta * time_speed  # Turning round (or at work in port), smoothly too.
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
		_batter_anchored()
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
	_finish_autosave()
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
		divine = bool((data.get("divine", {}) as Dictionary).get("on", false)),
		money = int(mine.get("money", 0)),
		date = calendar_time_at(float(data.get("play_time", 0.0))),
		companies = maxi(list.size(), 1),
		start_type = "",  # (Its first company type; "" for a save from before types: every type.)
		logo = mine.get("logo", {}) if mine.get("logo") is Dictionary and not (mine.get("logo") as Dictionary).is_empty() else CompanyLogo.default_logo(str(mine.get("company_color", "purple"))),
	}
	var types: Variant = mine.get("company_types", {})
	if types is Dictionary and not (types as Dictionary).is_empty():
		summary.start_type = str((types as Dictionary).keys()[0])
	if int(data.get("version", 0)) != SAVE_VERSION:
		summary.error = "Old save, can't be loaded"
	return summary


func delete_save(slot: int, online := multiplayer_save) -> void:
	_finish_autosave()
	DirAccess.remove_absolute(save_path(slot, online))
	DirAccess.remove_absolute(save_path(slot, online) + WorldHistory.HISTORY_SUFFIX)


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
	company.company_types = {str(options.get("company_type", "cargo")): 1}
	company.logo = options.get("logo", {}) if not (options.get("logo", {}) as Dictionary).is_empty() else CompanyLogo.default_logo(company.color)
	company.tutorials = bool(options.get("tutorials", false))
	company.ceo = options.get("ceo", {}) if not (options.get("ceo", {}) as Dictionary).is_empty() else Company.random_ceo()
	if not (company.ceo as Dictionary).has("skills"):
		company.ceo.skills = Traits.random_skills(RandomNumberGenerator.new())
	company.hubs.assign([Hub.new(new_home_port, true)])
	companies.assign([company])
	_clear_ships()
	_values_kept.clear()
	next_ship_id = 1
	play_time = 0.0
	wage_period = 0
	canal_traffic.clear()
	market.clear()
	port_sizes.reset()
	max_time_speed = int(options.get("max_time_speed", TIME_SPEEDS[-1]))
	storms = str(options.get("storms", "none"))
	seasons = bool(options.get("seasons", false))
	weather.clear()
	divine.reset()
	divine.on = bool(options.get("divine", false))
	ratings.reset()
	farms.reset()
	energy.reset()
	research.reset()
	industry.reset()
	history.clear()
	news.clear()
	world.make_world(int(options.get("seed", randi())))
	firms.generate(world, world.seed)
	money_changed.emit(money)
	SteamAchievements.note_game_created()
	if options.get("start") is Dictionary and not (options.start as Dictionary).is_empty():
		Backstories.apply(self, options.start)  # (Its money, debt, backers, ships, standing and the CEO's traits.)
		company.story = Backstories.story(options.start, str(company.ceo.get("name", "")))
		money_changed.emit(money)
	_begin_session()
	_start_warm_up(WARM_UP_DAYS)  # (Saved once it's run: see _warm_up_frame().)


## A ship given, not bought (a backstory start's): docked at a port, in the company's fleet.
func grant_ship(model_id: String, ship_name: String, port_id: String) -> Ship:
	var model := GameData.get_ship_model(model_id)
	if model.is_empty():
		return null
	var ship := Ship.new(Net.clean_text(ship_name.strip_edges()), model_id, port_id)
	ship.id = next_ship_id
	next_ship_id += 1
	ship.company = company
	ship.purchase_price = int(model.get("price", 0))
	ship.captains = Characters.officers_for(model)
	ships.append(ship)
	if ship.is_cruise():
		cruises.ensure(ship)
	ships_changed.emit()
	return ship


## Loads a slot's save and starts a session saving to it. Returns why it
## couldn't, or "". A save from before companies loads as its one company.
func continue_game(slot: int) -> String:
	_finish_autosave()
	var path := save_path(slot)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		push_error("GameState: save file %s is missing or corrupt" % path)
		return "The saved game could not be read."
	if int(data.get("version", 0)) != SAVE_VERSION:
		return "This save is from before the living world (no more levels or regions) and can't be loaded. Delete it to start a new game in this slot."
	save_slot = slot
	load_world(data)
	_begin_session()
	return ""


## Loads a world_dict() (a save, or the host's game when joining one), with
## this player's company the one at `local` (the save's own if -1). Saves from
## before companies load as their one company.
func load_world(data: Dictionary, local := -1) -> void:
	data = _without_retired_ports(data)
	ratings.reset()
	companies.clear()
	_values_kept.clear()
	for company_data: Dictionary in data.get("companies", [data]):
		companies.append(Company.from_dict(company_data))
	company = companies[clampi(local if local >= 0 else int(data.get("local_company", 0)), 0, companies.size() - 1)]
	_clear_ships()
	play_time = float(data.get("play_time", 0.0))
	fish_stocks = data.get("fish_stocks", {})
	_stock_day = -1
	wage_period = int(data.get("wage_period", -1))  # Saves from before wages: none owed for the time before.
	market.from_dict(data.get("market", {}))
	world.from_dict(data.get("world", {}))
	firms.from_dict(data.get("firms", {}), world)
	news.from_dict(data.get("news", {}))
	history.load(save_path(save_slot) + WorldHistory.HISTORY_SUFFIX, world)  # (Joining a game: none; the host's history isn't sent.)
	var had_port_sizes := port_sizes.from_dict(data.get("port_sizes", {}))
	max_time_speed = int(data.get("max_time_speed", TIME_SPEEDS[-1]))
	# Saves from before weather have no storms or seasonal closures.
	storms = str(data.get("storms", "none"))
	seasons = bool(data.get("seasons", false))
	weather.from_dict(data.get("weather", {}))
	divine.from_dict(data.get("divine", {}))
	farms.from_dict(data.get("farms", {}))
	energy.from_dict(data.get("energy", {}))
	research.from_dict(data.get("research", {}))
	industry.from_dict(data.get("industry", {}))
	next_ship_id = int(data.get("next_ship_id", 1))
	for ship_data: Dictionary in data.get("ships", []):
		var ship := Ship.from_dict(ship_data)
		ship.company = companies[clampi(int(ship_data.get("company", 0)), 0, companies.size() - 1)]
		if ship.id <= 0:  # Saves from before ship ids.
			ship.id = next_ship_id
			next_ship_id += 1
		next_ship_id = maxi(next_ship_id, ship.id + 1)
		Manufacturers.convert_old_cargo(ship)  # (Saves from before the makers: their cars and trucks aboard become a maker's.)
		ships.append(ship)
	Ship.link_rescues(ships)
	for ship in ships:
		ship.invalidate_stats()  # Everything it depends on is loaded now.
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
	_finish_autosave()  # (So an older autosave can't land after this.)
	_write_save(save_path(save_slot), world_dict())
	WorldHistory.write(save_path(save_slot) + WorldHistory.HISTORY_SUFFIX, history.to_bytes())


## The timed autosave: the game is copied here, then turned into text and
## written off the main thread (most of the time it takes with a big fleet),
## so play doesn't hitch.
func _autosave() -> void:
	if not in_session or Net.is_client():
		return
	_finish_autosave()
	var data := world_dict()
	# Its own copy: the ships' routes and such are the live ones. The world's and
	# the firms' parts are made fresh by their to_dict() (and are the biggest), so
	# they're kept as they are rather than copied again.
	var fresh := {world = data.world, firms = data.firms}
	data.erase("world")
	data.erase("firms")
	data = data.duplicate(true)
	data.merge(fresh)
	_autosaves += 1
	if _autosaves % HISTORY_EVERY_AUTOSAVES == 0:  # (A few MB written at once, so not every time: the history is the least of a save.)
		WorldHistory.write(save_path(save_slot) + WorldHistory.HISTORY_SUFFIX, history.to_bytes())
	_autosave_task = WorkerThreadPool.add_task(_write_save.bind(save_path(save_slot), data), false, "Autosave")


var _autosaves := 0
const HISTORY_EVERY_AUTOSAVES := 10

## Waits for the autosave being written, if any.
func _finish_autosave() -> void:
	if _autosave_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_autosave_task)
		_autosave_task = -1


func _write_save(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("GameState: could not write save (%s)" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))


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
		"fish_stocks": fish_stocks,
		"wage_period": wage_period,
		"max_time_speed": max_time_speed,
		"storms": storms,
		"seasons": seasons,
		"weather": weather.to_dict(),
		"divine": divine.to_dict(),
		"farms": farms.to_dict(),
		"energy": energy.to_dict(),
		"research": research.to_dict(),
		"industry": industry.to_dict(),
		"market": market.to_dict(),
		"world": world.to_dict(),
		"firms": firms.to_dict(),
		"news": news.to_dict(),
		"port_sizes": port_sizes.to_dict(),
		"ships": ships.map(func(ship: Ship) -> Dictionary:
			var ship_data := ship.to_dict()
			ship_data["company"] = maxi(all.find(owner_of(ship)), 0)
			return ship_data),
	}


## Ships and the Mammoths recovering them point at each other; break those
## links so the old ships are freed.
func _clear_ships() -> void:
	traffic.clear()
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


## A save with every port taken out of the game (GameData.RETIRED_PORTS) swapped
## for the port that took its place, wherever it's named (ships' routes, where
## they are and are bound, hubs, home ports...), so nothing points at a port
## that's gone. A company left with two hubs at one port keeps its HQ (or the
## first).
func _without_retired_ports(data: Variant) -> Variant:
	if data is String:
		return GameData.RETIRED_PORTS.get(data, data)
	if data is Array:
		var out := []
		for item: Variant in data:
			out.append(_without_retired_ports(item))
		return out
	if data is Dictionary:
		var out := {}
		for key: Variant in data:
			out[key] = _without_retired_ports(data[key])
		# A route that now stops twice in a row at one port stops there once.
		for key: String in ["route", "pending_route"]:
			if out.get(key) is Array and (out[key] as Array).size() > 1:
				var stops := []
				for stop: Variant in out[key]:
					if stops.is_empty() or stops[-1] != stop:
						stops.append(stop)
				while stops.size() > 1 and stops[0] == stops[-1]:
					stops.pop_back()
				out[key] = stops if stops.size() > 1 else []
		if out.has("hubs") and out.hubs is Array:
			var kept := []
			var ports := {}
			for hub: Variant in out.hubs:
				if hub is Dictionary and ports.has(hub.get("port_id", "")):
					if bool(hub.get("is_hq", false)):
						kept[ports[hub.port_id]] = hub  # The HQ wins.
					continue
				if hub is Dictionary:
					ports[hub.get("port_id", "")] = kept.size()
				kept.append(hub)
			out.hubs = kept
		return out
	return data


## Every WAKE_WAITING_S: a running cargo ship lying at a port's moorings or
## anchorage (waiting for a load, or for fuel money) comes in to a pier while
## the port has room to spare (more than WAIT_AT_PIER_FREE berths free),
## queuing for one like any other (see _advance_berth()); it pulls out again
## if the port fills up (see _advance_docked()). An idle or paused ship stays
## at the moorings, its long-term parking, till it has somewhere to go.
func _wake_waiting_ships() -> void:
	for ship in ships:
		if ship.berth >= 0 or ship.berth_phase != Ship.BERTH_NONE or not ship.is_docked() or ship.is_service() or ship.is_on_job() or ship.is_docking() or ship.is_lost() or not ship.is_running():
			continue
		if docks.free_berths(ship.docked_at) > WAIT_AT_PIER_FREE + 1:
			ship.berth_phase = Ship.BERTH_WAIT
			ship_changed.emit(ship)


# --- Fishing and crabbing ------------------------------------------------------

## Each fishing ground's stocks: "ground>species" -> the share of the most it
## holds that's left (1, or missing: untouched). Drawn down by every boat's
## catch, growing back a little each calendar day (Fisheries.REGROW_A_YEAR).
var fish_stocks := {}
## How often (s of play) a fishing boat waiting in port looks again for a trip.
const FISH_RECHECK_S := 2.0
var _stock_day := -1
## A company's uniforms changed (set_uniform()).
signal uniforms_changed(company: Company)
## A catch landed (or put in the cold store, `stored`) at a port: its value at that port's price.
signal catch_landed(ship: Ship, port: String, species: String, crates: int, value: int, stored: bool)
## A small boat trolling landed one giant fish (a bluefin, a marlin) that filled its hold.
signal trophy_caught(ship: Ship, species: String)

## The month the seasons go by (0-11).
func fishing_month() -> int:
	return Currents.month_of(calendar_time())


## The stocks grow back once a calendar day.
func _regrow_stocks() -> void:
	var day := floori(calendar_time() / Fisheries.DAY_S)
	if day == _stock_day:
		return
	var days := 1 if _stock_day < 0 else mini(day - _stock_day, 30)
	_stock_day = day
	var grow := Fisheries.REGROW_A_YEAR / 365.0 * days
	for key: String in fish_stocks.keys():
		var stock := float(fish_stocks[key])
		stock += (1.0 - stock) * grow
		if stock >= 0.999:
			fish_stocks.erase(key)
		else:
			fish_stocks[key] = stock


## What a fishing boat can go after from its base this month (Fisheries.options()), best first.
func fishing_options(ship: Ship, base := "") -> Array:
	if base.is_empty():
		base = ship.base_port
	var who := owner_of(ship)
	return Fisheries.shared().options(ship, base, fishing_month(), fish_stocks,
		func(port: String, family: String) -> float: return company_sell_price(port, family, who))


## Its next trip from the port it fishes from (fishing_stage()): {ground,
## species, work_limit_s} (worked out from its target, or its ground's best
## this season, or the best anywhere), or {wait: why it stays in port}.
func fishing_plan(ship: Ship) -> Dictionary:
	var fish := Fisheries.shared()
	var choices := fishing_options(ship, fishing_stage(ship))
	if choices.is_empty():
		return {wait = "no fishing grounds within reach for its gear"}
	if ship.fish_target.is_empty() and not ship.fish_area.is_empty():
		# Sent to a ground (the Fishing Grounds screen): only what's there.
		choices = choices.filter(func(option: Dictionary) -> bool: return option.ground == ship.fish_area)
		if choices.is_empty():
			return {wait = "nothing at %s it can catch" % Fisheries.ground_name(ship.fish_area)}
	var pick := {}
	var full := ""  # (A ground it would have gone to, with GROUND_BOATS boats on it already.)
	var counts := _ground_boats(ship)
	if ship.fish_target.is_empty():
		for option: Dictionary in choices:
			if option.in_season:
				if int(counts.get(option.ground, 0)) >= GROUND_BOATS:
					full = option.ground
					continue
				pick = option
				break
		if pick.is_empty():
			if not ship.fish_area.is_empty():
				if not full.is_empty():
					return {wait = "%s has %d boats on it already" % [Fisheries.ground_name(ship.fish_area), GROUND_BOATS]}
				return {wait = "nothing it can catch is in season at %s now" % Fisheries.ground_name(ship.fish_area)}
			if not full.is_empty():
				return {wait = "every ground in season within reach has %d boats on it" % GROUND_BOATS}
			return {wait = "nothing it can catch is in season within reach"}
	else:
		var later := {}
		for option: Dictionary in choices:
			if option.species != ship.fish_target or (not ship.fish_area.is_empty() and option.ground != ship.fish_area):
				continue
			if option.in_season:
				if int(counts.get(option.ground, 0)) >= GROUND_BOATS:
					full = option.ground
					continue
				pick = option
				break
			if later.is_empty():
				later = option
		if pick.is_empty():
			var what := fish.species_word(ship.fish_target)
			if not full.is_empty():
				return {wait = "%s has %d boats on it already" % [GameData.port_name(Fisheries.end_of(full)), GROUND_BOATS]}
			if later.is_empty():
				return {wait = "no %s within reach" % what}
			return {wait = "%s at %s is in season %s" % [what, GameData.port_name(Fisheries.end_of(later.ground)), later.season]}
	# How long it can stay working: its trip's most days, less the sailing there
	# and back, and what its tank holds.
	var gear: Dictionary = ship.model().get("fishing", {})
	var trip_days: Array = gear.get("trip_days", [3, 7])
	var day_s := Fisheries.DAY_S / maxf(calendar_seconds_per_second(), 1.0)
	var sail_s := ship.sailing_seconds(float(pick.miles), maxf(ship.maintenance, 0.5))
	var work_s := maxf(float(trip_days[1]) * day_s - 2.0 * sail_s, float(trip_days[0]) * day_s * 0.5)
	var tank_s := (ship.fuel_tank() / maxf(ship.fuel_per_s(), 0.0001) - 2.0 * sail_s - DEPARTURE_MARGIN_S) / Fisheries.WORK_FUEL
	work_s = minf(work_s, tank_s)
	if work_s < day_s * 0.25:
		return {wait = "%s is too far for its tank" % GameData.port_name(Fisheries.end_of(pick.ground))}
	# And what its hull can take: it's to come home with FISH_HOME_MAINTENANCE
	# left (the sailing out and back, and the working, in the ground's weather
	# this month), so it plans its time out from what it has to spend.
	var hull_s := _fishing_hull_seconds(ship, pick.ground, sail_s)
	if hull_s < day_s * 0.25:
		if ship.maintenance < 0.999 and ship.auto_repair:
			return {wait = "waiting for repairs before its next trip"}
		if ship.maintenance < 0.999:
			return {wait = "too worn for a trip; turn on repair"}
		return {wait = "%s is too far for its hull" % GameData.port_name(Fisheries.end_of(pick.ground))}
	work_s = minf(work_s, hull_s)
	return {ground = pick.ground, species = pick.species, work_limit_s = work_s, miles = pick.miles}


## What a fishing boat is to come home from a trip with (of its maintenance)
## on a normal day: its trips are planned to it (fishing_plan()), and it turns
## for home when what it has left would take it under (see _work_ground()).
const FISH_HOME_MAINTENANCE := 0.7

## How long (s of play) a boat can work a ground and still come home with
## FISH_HOME_MAINTENANCE left: what it may spend less the sailing there and
## back (`sail_s` one way), at its wear working there (ROUGH_WEAR in the
## ground's rough months). INF for a boat that doesn't wear.
func _fishing_hull_seconds(ship: Ship, ground: String, sail_s: float) -> float:
	var wear := ship.wear_per_s()
	if wear <= 0.0:
		return INF
	var rough := Fisheries.shared().rough(ground, fishing_month())
	var spend := ship.maintenance - FISH_HOME_MAINTENANCE - 2.0 * wear * sail_s
	return spend / (wear * (Fisheries.ROUGH_WEAR if rough else 1.0))


## The port a fishing boat sets out on its trips from: its base, unless it's
## been sent to a ground (fish_area) beyond a trip from there, when it's the
## port by that ground it can reach (refuelling on the way: refuel_path())
## that makes the way there and out to the ground shortest. "" if it can't
## get to any.
func fishing_stage(ship: Ship) -> String:
	var base := ship.base_port
	if ship.fish_area.is_empty() or base.is_empty():
		return base
	var key := [base, ship.fish_area, ship.model_id, ship.fuel_per_s()]
	if ship.get_meta(&"stage_key", []) == key:
		return str(ship.get_meta(&"stage", base))
	var stage := fishing_stage_from(ship, base, ship.fish_area)
	ship.set_meta(&"stage_key", key)
	ship.set_meta(&"stage", stage)
	return stage


## fishing_stage() for any base and ground: the base itself if a trip from it
## reaches the ground, else the best port to fish from (or "").
func fishing_stage_from(ship: Ship, base: String, ground: String) -> String:
	var fish := Fisheries.shared()
	var reach := ship.range_nm()
	if fish.miles_to(base, ground) <= reach:
		return base
	var best := ""
	var best_nm := INF
	for port: String in fish.grounds.get(ground, {}).get("ports", []):
		var out := fish.miles_to(port, ground)
		if out > reach or not ship.fits_port(port):
			continue
		var there := refuel_path_nm(ship, base, port)
		if there + out < best_nm:
			best_nm = there + out
			best = port
	return best


## A fishing boat in port with its stop done. At its base it lands anything it
## brought back. Then: with a catch aboard away from its base, it heads home
## to land it; away from the port it fishes from (fishing_stage()), it heads
## there (both by way of refuel stops if they're beyond one tank:
## _try_depart()); at that port it sets out on its next trip once it has the fuel.
func _fishing_in_port(ship: Ship, delta := 0.0) -> void:
	var here := ship.docked_at
	if ship.catch > 0.0 and here == ship.base_port:
		_land_catch(ship, here)
	if not ship.paused:
		var stage := fishing_stage(ship)
		if stage.is_empty():
			_set_fish_wait(ship, "can't reach %s from %s, even refuelling on the way" % [Fisheries.ground_name(ship.fish_area), GameData.port_name(ship.base_port)])
			if ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
				_pull_out(ship, "")
			return
		if ship.catch > 0.0 and ship.catch < 1.0 and here != ship.base_port:
			ship.catch = 0.0  # (Less than a crate: not worth the trip home.)
		var goal := ship.base_port if ship.catch >= 1.0 else stage
		if here != goal:
			ship.fish_home = ""
			_set_fish_wait(ship, "")
			_try_depart(ship, delta, goal)
			if ship.is_docked() and ship.is_held():
				_set_fish_wait(ship, ship.hold_reason)
			return
		ship.fish_home = here
	# Waiting (out of season, out of fuel money): it looks again every FISH_RECHECK_S, not every step.
	if not ship.fish_wait.is_empty() and play_time < float(ship.get_meta(&"fish_check", 0.0)):
		return
	ship.set_meta(&"fish_check", play_time + FISH_RECHECK_S)
	if ship.paused:
		_set_fish_wait(ship, "paused")
		return
	var storm := weather.closed_by(ship.docked_at)
	if not storm.is_empty():
		_set_fish_wait(ship, "%s is closed by %s" % [GameData.port_name(ship.docked_at), Weather.title(storm)])
		return
	var plan := fishing_plan(ship)
	if plan.has("wait"):
		_set_fish_wait(ship, plan.wait)
		if ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
			_pull_out(ship, "")  # Waiting: off to the moorings, the pier free for others.
		return
	var need := ship.fuel_per_s() * (2.0 * ship.sailing_seconds(float(plan.miles), maxf(ship.maintenance, 0.5)) + float(plan.work_limit_s) * Fisheries.WORK_FUEL * 0.25 + DEPARTURE_MARGIN_S)
	if ship.fuel < need:
		if ship.auto_refuel:
			_refuel(ship, need - ship.fuel)
		if ship.fuel < need:
			_set_fish_wait(ship, "waiting for the money for fuel")
			return
	# At its pier: it pulls out and sails straight on out of the harbour onto
	# its trip (its first leg's end as where it's bound: see _advance_berth(),
	# which starts the trip once it's clear). From the moorings, it sets off
	# from its spot (the map takes it out the way it came in).
	if ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
		var legs := Fisheries.shared().legs(_trip_home(ship), plan.ground)
		ship.set_meta(&"fish_trip", true)
		_pull_out(ship, str((legs[0] as Array)[0][1]))
		return
	_set_off_fishing(ship, plan)


## The port a fishing boat's trip set out from and comes back to.
func _trip_home(ship: Ship) -> String:
	return ship.fish_home if not ship.fish_home.is_empty() else ship.base_port


## A fishing boat clear of its pier (or at its spot) with a trip to make sets
## out on it: the trip is planned again (what's in season, the ground's boats,
## its fuel and hull can have changed while it pulled out), and it works the
## ground for what its tank can do of the plan's time.
func _set_off_fishing(ship: Ship, plan := {}) -> void:
	if plan.is_empty():
		plan = fishing_plan(ship)
		if plan.has("wait"):
			_set_fish_wait(ship, plan.wait)  # (It lies at the moorings meanwhile: see _update_spots().)
			ship_changed.emit(ship)
			return
	var spare_s := (ship.fuel / maxf(ship.fuel_per_s(), 0.0001) - 2.0 * ship.sailing_seconds(float(plan.miles), maxf(ship.maintenance, 0.5)) - DEPARTURE_MARGIN_S) / Fisheries.WORK_FUEL
	_start_fishing(ship, plan.ground, plan.species, minf(float(plan.work_limit_s), spare_s))


func _set_fish_wait(ship: Ship, why: String) -> void:
	if ship.fish_wait != why:
		ship.fish_wait = why
		ship_changed.emit(ship)


## How many boats (every company's) can work a ground at once: each its own
## spot on it (Ship.fish_slot), so they spread out over it.
const GROUND_BOATS := 8


## Each ground's boats heading out to it or working it (not those on their way
## home), but `except`: {ground: count}.
func _ground_boats(except: Ship = null) -> Dictionary:
	var counts := {}
	for other in ships:
		if other != except and other.job_phase == Ship.JOB_FISH and (other.fish_phase == "out" or other.fish_phase == "work"):
			counts[other.fish_ground] = int(counts.get(other.fish_ground, 0)) + 1
	return counts


## The lowest of a ground's spots no other boat out to it or on it has.
func _free_ground_slot(ground: String, ship: Ship) -> int:
	var used := {}
	for other in ships:
		if other != ship and other.job_phase == Ship.JOB_FISH and other.fish_ground == ground and other.fish_phase != "home":
			used[other.fish_slot] = true
	for slot in GROUND_BOATS:
		if not used.has(slot):
			return slot
	return 0


## Sets out for a ground: on a job the whole trip (Ship.JOB_FISH), sailing its legs out.
func _start_fishing(ship: Ship, ground: String, species: String, work_limit_s: float) -> void:
	var legs := Fisheries.shared().legs(_trip_home(ship), ground)
	_set_hold(ship, "")
	_leave_port(ship)
	ship.docked_at = ""
	ship.fish_wait = ""
	ship.job_phase = Ship.JOB_FISH
	ship.fish_phase = "out"
	ship.fish_ground = ground
	ship.fish_species = species
	ship.fish_slot = _free_ground_slot(ground, ship)
	ship.catch = 0.0
	ship.catch_grade = float(Fisheries.shared().species[species].grade)
	ship.work_s = 0.0
	ship.work_limit_s = maxf(work_limit_s, 0.0)
	ship.job_segments = (legs[0] as Array).duplicate(true)
	_start_segment(ship, ship.job_segments.pop_front())
	ship_changed.emit(ship)


## A fishing boat on its trip: sailing out, working the ground, sailing home.
func _advance_fishing(ship: Ship, delta: float) -> void:
	if ship.fish_phase == "work":
		_work_ground(ship, delta)
		return
	if not _sail(ship, delta):
		_fishing_lost(ship)
		return
	if ship.traveled_nm < ship.segment_end:
		return
	ship.traveled_nm = ship.segment_end
	if not ship.job_segments.is_empty():
		_start_segment(ship, ship.job_segments.pop_front())
		return
	if ship.fish_phase == "out":
		ship.fish_phase = "work"
		ship.work_s = 0.0
		ship_changed.emit(ship)
		return
	# Home: its catch lands as it comes in (see _fishing_in_port()).
	var base := ship.to_port
	ship.job_phase = Ship.JOB_NONE
	ship.fish_phase = ""
	ship.job_segments.clear()
	ship.segment_end = 0.0
	_arrive(ship, base, false)


## A day's work on a ground, as play time passes: pots hauled (or nets and
## lines worked), the catch filling the hold at the ground's rate this month,
## thinned by its stock and slowed by storms; fuel burned at Fisheries.WORK_FUEL
## and wear, more in a storm and in the ground's rough months. It turns for
## home with a full hold, at the end of its time there, when the season
## closes, or when it needs what it has left to get home.
func _work_ground(ship: Ship, delta: float) -> void:
	var fish := Fisheries.shared()
	var model := ship.model()
	var month := fishing_month()
	var key := "%s>%s" % [ship.fish_ground, ship.fish_species]
	var stock := float(fish_stocks.get(key, 1.0))
	var rate := fish.crates_a_day(model, ship.fish_ground, ship.fish_species, month, stock) * Research.catch_factor(owner_of(ship), ship.fish_ground)  # (Its company's research: see Research.)
	var storm := _storm_factors(ship)
	var rough := fish.rough(ship.fish_ground, month)
	var days := delta * calendar_seconds_per_second() / Fisheries.DAY_S
	ship.worked = true
	ship.sea_time += delta
	ship.work_s += delta
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * Fisheries.WORK_FUEL * delta, 0.0)
	ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * float(storm[1]) * (Fisheries.ROUGH_WEAR if rough else 1.0) * delta, 0.0)
	if ship.fuel <= 0.0:
		_lose(ship, "out of fuel")
		_fishing_lost(ship)
		return
	if ship.maintenance <= 0.0:
		_lose(ship, "broken down" if not rough else "battered by the %s" % ("sea" if storm[1] <= 1.0 else "storm"))
		_fishing_lost(ship)
		return
	var room := float(ship.capacity()) - ship.catch
	var amount := minf(rate * days * float(storm[0]), room)
	# A small trolling boat may hook one giant (a bluefin, a marlin) that fills its hold.
	var trophy_chance := float(model.get("fishing", {}).get("trophy_chance", 0.0))
	if trophy_chance > 0.0 and rate > 0.0 and fish.species[ship.fish_species].get("trophy", false) and randf() < trophy_chance * days:
		amount = room
		trophy_caught.emit(ship, ship.fish_species)
	if amount > 0.0:
		ship.catch += amount
		var stock_t := float(fish.grounds[ship.fish_ground].stock_t)
		fish_stocks[key] = maxf(stock - amount / (stock_t * 40.0), 0.0)  # (40 crates a ton.)
	# Time to head home?
	var home_nm := fish.miles_to(_trip_home(ship), ship.fish_ground)
	var home_s := ship.sailing_seconds(home_nm, ship.maintenance)
	var short := home_s == INF or ship.fuel < ship.fuel_per_s() * (home_s + DEPARTURE_MARGIN_S) * 1.05
	var worn := ship.maintenance - ship.wear_per_s() * home_s * 1.05 <= FISH_HOME_MAINTENANCE  # (Home with FISH_HOME_MAINTENANCE left.)
	if ship.catch >= float(ship.capacity()) - 0.01 or ship.work_s >= ship.work_limit_s or rate <= 0.0 or short or worn:
		_head_home(ship)


func _head_home(ship: Ship) -> void:
	var legs := Fisheries.shared().legs(_trip_home(ship), ship.fish_ground)
	ship.fish_phase = "home"
	ship.job_segments = (legs[1] as Array).duplicate(true)
	_start_segment(ship, ship.job_segments.pop_front())
	ship_changed.emit(ship)


## Lost at sea on a trip: its trip ends where it is (its catch stays aboard,
## landed wherever it's brought in), and it waits for a recovery boat or tugs like any ship.
func _fishing_lost(ship: Ship) -> void:
	ship.job_phase = Ship.JOB_NONE
	ship.fish_phase = ""
	ship.job_segments.clear()
	ship.segment_end = 0.0
	ship_changed.emit(ship)


## Lands a boat's catch at a port, at the price a crate of its family fetches
## there (its species' grade in): sold there, or, at the company's HQ or a
## hub (the only ports with its freezers), into its cold store for its seafood
## carriers (by its landing choice; "auto" stores it where a carrier of the
## company's calls, else sells).
func _land_catch(ship: Ship, port: String) -> void:
	var crates := floori(ship.catch)
	var species := ship.fish_species
	ship.catch = 0.0
	if crates <= 0 or species.is_empty():
		return
	var who := owner_of(ship)
	var family := Fisheries.shared().family_of(species)
	var value := roundi(crates * company_sell_price(port, family, who) * ship.catch_grade)
	# Freezers are at the company's HQ and hubs only (anywhere else it sells).
	var store := hub_at(port, who) != null and (ship.fish_landing == "store" or (ship.fish_landing == "auto" and _carrier_calls(port, who)))
	if store:
		var at: Dictionary = who.cold_stores.get_or_add(port, {})
		at[family] = float(at.get(family, 0.0)) + crates * ship.catch_grade  # (Its grade as more crates of the family.)
		_record(ship, "income", value)
	else:
		_add_money(who, value)
		_record(ship, "income", value)
		_tally_port_trade(who, port, family, crates, value, true)
		market.trade(port, family, value, false)
		port_sizes.add_traffic(port, value)
	catch_landed.emit(ship, port, species, crates, value, store)
	ship_changed.emit(ship)


## True if one of a company's seafood carriers has a port on its route.
func _carrier_calls(port: String, who: Company) -> bool:
	for ship in fleet(who):
		if str(ship.model().get("category", "")) == "seafood" and ship.route.has(port):
			return true
	return false


## A seafood carrier loading at a port where its company's cold store holds
## catch: it takes the family that pays most where it's going, free (its
## boats' catch, already counted as theirs: Ship ledgers, the store's worth at
## this port as its cost), up to its room. [family, crates], or [] for none.
func _load_from_store(ship: Ship, to: String) -> Array:
	var who := owner_of(ship)
	var store: Dictionary = who.cold_stores.get(ship.docked_at, {})
	if store.is_empty() or str(ship.model().get("category", "")) != "seafood":
		return []
	var best := ""
	var best_gain := 0.0
	for family: String in store:
		var crates := float(store[family])
		if crates < 1.0:
			continue
		var gain := minf(crates, ship.capacity()) * company_sell_price(to, family, who)
		if gain > best_gain:
			best_gain = gain
			best = family
	if best.is_empty():
		return []
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())))
	var quantity := mini(room, floori(float(store[best])))
	if quantity <= 0:
		return []
	store[best] = float(store[best]) - quantity
	if float(store[best]) < 1.0:
		store.erase(best)
	if store.is_empty():
		who.cold_stores.erase(ship.docked_at)
	var cost := roundi(quantity * company_sell_price(ship.docked_at, best, who))
	_record(ship, "cargo", cost)
	ship.cargo_id = best
	ship.cargo_from = ship.docked_at
	ship.cargo_qty = quantity
	ship.cargo_cost = cost
	cargo_loaded.emit(ship, ship.docked_at, best, quantity, cost, to)
	ship_changed.emit(ship)
	return [best, quantity]


## Sets what a fishing boat goes after: a species (and ground: "" for the
## best one for it), or "" for the most timely and profitable each trip.
func set_fishing_target(ship: Ship, species: String, ground := "") -> void:
	if Net.command(&"set_fishing_target", [ship, species, ground]):
		return
	if not ship.is_fishing():
		return
	ship.fish_target = species
	ship.fish_area = ground if not species.is_empty() else ""
	ship.fish_wait = ""
	ship.set_meta(&"fish_check", 0.0)  # (A new target: it looks again at once.)
	ship_changed.emit(ship)


## Sets where a fishing boat is based (any port): it sails there once it's
## in port and lands its catch there from then on.
func set_fishing_base(ship: Ship, port_id: String) -> void:
	if Net.command(&"set_fishing_base", [ship, port_id]):
		return
	if not ship.is_fishing() or GameData.get_port(port_id).is_empty() or Fisheries.is_ground(port_id):
		return
	ship.base_port = port_id
	ship.fish_wait = ""
	ship_changed.emit(ship)


## Sets what a fishing boat does with its catch landed: "auto", "sell" or "store".
func set_fish_landing(ship: Ship, mode: String) -> void:
	if Net.command(&"set_fish_landing", [ship, mode]):
		return
	if ship.is_fishing() and mode in ["auto", "sell", "store"]:
		ship.fish_landing = mode
		ship_changed.emit(ship)


# --- The Fishing Grounds screen's assignments --------------------------------------

## A company picked (or dropped) a fishing ground. Dropping one calls its boats off it.
signal fish_areas_changed

## Picks a ground on the Fishing Grounds screen (on), or drops it and calls
## every boat sent there off it (they go back to fishing the best within reach of their port).
func select_fish_area(ground: String, on: bool) -> void:
	if Net.command(&"select_fish_area", [ground, on]):
		return
	if not Fisheries.shared().grounds.has(ground):
		return
	if on:
		company.fish_areas.get_or_add(ground, {})
	else:
		company.fish_areas.erase(ground)
		for ship in fleet(company):
			if ship.is_fishing() and ship.fish_area == ground:
				_call_off(ship)
	fish_areas_changed.emit()


## The boats of a company's fleet of a model sent to a ground.
func fish_area_boats(ground: String, model_id: String, who: Company = null) -> Array[Ship]:
	var out: Array[Ship] = []
	for ship in fleet(who if who != null else company):
		if ship.model_id == model_id and ship.fish_area == ground and ship.is_fishing():
			out.append(ship)
	return out


## A company's boats of a model not sent to any ground (free to send).
func free_fish_boats(model_id: String, who: Company = null) -> Array[Ship]:
	var out: Array[Ship] = []
	for ship in fleet(who if who != null else company):
		if ship.model_id == model_id and ship.is_fishing() and ship.fish_area.is_empty() and not ship.is_lost():
			out.append(ship)
	return out


## Where a model's boats sent to a ground land their catch and whether it goes
## in the freezer ({port, freeze}): as set, or by default the port by the
## ground nearest it (fish_area_default_port()), selling.
func fish_area_setting(ground: String, model_id: String) -> Dictionary:
	var setting: Dictionary = company.fish_areas.get(ground, {}).get(model_id, {})
	var port := str(setting.get("port", ""))
	if port.is_empty():
		port = fish_area_default_port(ground)
	return {port = port, freeze = bool(setting.get("freeze", false)) and hub_at(port) != null}


## The port by a ground its lanes run from that's nearest it.
func fish_area_default_port(ground: String) -> String:
	var fish := Fisheries.shared()
	var best := ""
	var best_nm := INF
	for port: String in fish.grounds.get(ground, {}).get("ports", []):
		var nm := fish.miles_to(port, ground)
		if nm < best_nm:
			best_nm = nm
			best = port
	return best


## Sends boats of a model to a ground (or calls some off) until `count` of them
## are there: the free ones nearest the ground first, each based at the
## model's landing port there, its catch frozen or sold as set (see
## set_fish_area_model()); called off, a boat goes back to fishing the best
## within reach of its port.
func assign_fish_boats(ground: String, model_id: String, count: int) -> void:
	if Net.command(&"assign_fish_boats", [ground, model_id, count]):
		return
	var fish := Fisheries.shared()
	if not fish.grounds.has(ground) or not fish.model_works_ground(GameData.get_ship_model(model_id), ground):
		return
	company.fish_areas.get_or_add(ground, {})
	var sent := fish_area_boats(ground, model_id)
	while sent.size() > maxi(count, 0):
		_call_off(sent.pop_back())
	if sent.size() < count:
		var free := free_fish_boats(model_id)
		var end := Fisheries.end_of(ground)
		free.sort_custom(func(a: Ship, b: Ship) -> bool:
			return GameData.distance_nm(a.reference_port() if not a.reference_port().is_empty() else a.base_port, end, -1) < GameData.distance_nm(b.reference_port() if not b.reference_port().is_empty() else b.base_port, end, -1))
		var setting := fish_area_setting(ground, model_id)
		for ship in free:
			if sent.size() >= count:
				break
			ship.fish_area = ground
			ship.fish_target = ""
			ship.base_port = str(setting.port)
			ship.fish_landing = "store" if setting.freeze else "sell"
			ship.fish_wait = ""
			ship.set_meta(&"fish_check", 0.0)
			sent.append(ship)
			ship_changed.emit(ship)
	fish_areas_changed.emit()


## Where a model's boats sent to a ground land their catch (any port they can
## get to), and whether it goes in the freezer (the company's HQ or a hub
## only): for the boats there now and any sent later.
func set_fish_area_model(ground: String, model_id: String, port: String, freeze: bool) -> void:
	if Net.command(&"set_fish_area_model", [ground, model_id, port, freeze]):
		return
	if GameData.get_port(port).is_empty() or Fisheries.is_ground(port) or not Fisheries.shared().grounds.has(ground):
		return
	freeze = freeze and hub_at(port) != null
	var models: Dictionary = company.fish_areas.get_or_add(ground, {})
	models[model_id] = {port = port, freeze = freeze}
	for ship in fish_area_boats(ground, model_id):
		ship.base_port = port
		ship.fish_landing = "store" if freeze else "sell"
		ship.fish_wait = ""
		ship.set_meta(&"fish_check", 0.0)
		ship_changed.emit(ship)
	fish_areas_changed.emit()


func _call_off(ship: Ship) -> void:
	ship.fish_area = ""
	ship.fish_target = ""
	ship.fish_wait = ""
	ship.set_meta(&"fish_check", 0.0)
	ship_changed.emit(ship)


# --- Farms (see Farms): this player's actions ------------------------------------------

## Buys a plot from the land (Farms.buy_error() says why it can't).
func buy_plot(key: String) -> void:
	if Net.command(&"buy_plot", [key]):
		return
	farms.buy(company, key)


## Sells a plot back to the land, its herd into the store first.
func sell_plot(key: String) -> void:
	if Net.command(&"sell_plot", [key]):
		return
	var price := farms.sell_to_land(company, key)
	if price > 0:
		ActivityLog.add("Sold your plot at %s back to the land for %s." % [GameData.port_name(Farms.port_of(key)), Fmt.money(price)], ActivityLog.Kind.INFO)


## Lists a plot for other Agriculture companies at an asking price (0 takes it off the list).
func list_plot(key: String, price: int) -> void:
	if Net.command(&"list_plot", [key, price]):
		return
	farms.list(company, key, price)


## Buys another company's listed plot at its asking price.
func buy_listed_plot(key: String) -> void:
	if Net.command(&"buy_listed_plot", [key]):
		return
	farms.buy_listing(company, key)


func plant_plot(key: String, crop_id: String) -> void:
	if Net.command(&"plant_plot", [key, crop_id]):
		return
	farms.plant(company, key, crop_id)


func stock_plot(key: String, breed_id: String) -> void:
	if Net.command(&"stock_plot", [key, breed_id]):
		return
	farms.stock(company, key, breed_id)


func clear_plot(key: String) -> void:
	if Net.command(&"clear_plot", [key]):
		return
	farms.clear(company, key)


func upgrade_plot(key: String, upgrade_id: String) -> void:
	if Net.command(&"upgrade_plot", [key, upgrade_id]):
		return
	farms.add_upgrade(company, key, upgrade_id)


func build_cold_store(port_id: String) -> void:
	if Net.command(&"build_cold_store", [port_id]):
		return
	farms.build_cold_store(company, port_id)


## Sells what's in the farm store at a port of one item, at the port's price.
func sell_farm_item(port_id: String, item: String) -> void:
	if Net.command(&"sell_farm_item", [port_id, item]):
		return
	var value := farms.sell_item(company, port_id, item)
	if value > 0:
		ActivityLog.add("Sold the %s in your farm store at %s for %s." % [Farms.item_name(item).to_lower(), GameData.port_name(port_id), Fmt.money(value)], ActivityLog.Kind.GOOD)


# --- Makers (see Manufacturers): this player's actions ------------------------------------------

## Builds a factory for a maker at a port (Manufacturers.build_error() says why it can't).
func build_factory(maker_id: String, port_id: String) -> void:
	if Net.command(&"build_factory", [maker_id, port_id]):
		return
	if not makers.build_error(company, maker_id, port_id).is_empty():
		return
	makers.build(company, maker_id, port_id)
	ActivityLog.add("Built a %s factory at %s for %s. It makes about %s %s a month." % [Manufacturers.maker(maker_id).name, GameData.port_name(port_id),
		Fmt.money(Manufacturers.factory_cost(maker_id)), Fmt.thousands(roundi(Manufacturers.output_a_day(maker_id) * 365.25 / 12.0)),
		GameData.commodity(maker_id).get("units", "vehicles")], ActivityLog.Kind.GOOD)


## Closes this player's factory for a maker at a port: the maker buys it back for a quarter of its price.
func close_factory(maker_id: String, port_id: String) -> void:
	if Net.command(&"close_factory", [maker_id, port_id]):
		return
	var refund := makers.close(company, maker_id, port_id)
	if refund > 0:
		ActivityLog.add("Closed your %s factory at %s: %s bought it back for %s." % [Manufacturers.maker(maker_id).name, GameData.port_name(port_id),
			Manufacturers.maker(maker_id).name, Fmt.money(refund)], ActivityLog.Kind.INFO)


## Sells a factory's stockpile where it is, at the port's price less the maker's cut.
func sell_factory_stock(maker_id: String, port_id: String) -> void:
	if Net.command(&"sell_factory_stock", [maker_id, port_id]):
		return
	var value := makers.sell_stock(company, maker_id, port_id)
	if value > 0:
		ActivityLog.add("Sold your %s factory's stock at %s for %s, after the maker's cut." % [Manufacturers.maker(maker_id).name, GameData.port_name(port_id), Fmt.money(value)], ActivityLog.Kind.GOOD)


# --- Oil and gas (see Energy): rig runs, repairs, and this player's actions ----------------------

## A ship delivering to a port where its company's buildings take in its cargo:
## what their tanks have room for goes into the store (no sale); the rest
## sells as usual.
func _deliver_to_plants(ship: Ship) -> void:
	var who := owner_of(ship)
	if not who.plants.has(ship.docked_at) or ship.cargo_qty <= 0:
		return
	var taken := energy.take_delivery(who, ship.docked_at, ship.cargo_id, ship.cargo_qty)
	if taken <= 0:
		return
	var left := 1.0 - float(taken) / ship.cargo_qty
	who.delivered[ship.cargo_id] = int(who.delivered.get(ship.cargo_id, 0)) + taken
	if who == company:
		ActivityLog.add("%s unloaded %s tons of %s into your tanks at %s." % [ship.name, Fmt.thousands(taken), Energy.good_word(ship.cargo_id),
			GameData.port_name(ship.docked_at)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))
	ship.cargo_qty -= taken
	ship.cargo_payment = roundi(ship.cargo_payment * left)
	ship.cargo_cost = roundi(ship.cargo_cost * left)
	if ship.cargo_qty <= 0:
		ship.cargo_id = ""
		ship.cargo_qty = 0
		ship.cargo_cost = 0
		ship.cargo_payment = 0
		ship.delivery_canals.clear()


## Puts a ship on rig runs between a field and a port (its route just that
## port), or takes it off them (field ""): Energy.run_error() says why it can't.
func set_rig_run(ship: Ship, field_id: String, port_id: String) -> void:
	if not field_id.is_empty() and not energy.run_error(company, ship, field_id, port_id).is_empty():
		return
	if Net.command(&"set_rig_run", [ship, field_id, port_id]):
		return
	_set_rig_run(ship, field_id, port_id)


func _set_rig_run(ship: Ship, field_id: String, port_id: String) -> void:
	var who := owner_of(ship)
	if field_id.is_empty():
		if not ship.is_rig_runner():
			return
		if ship.job_phase == Ship.JOB_RIG:
			ship.set_meta(&"rig_off", true)  # (Back from this one first: see _advance_rig().)
		else:
			ship.rig_field = ""
			ship.rig_port = ""
			ship.route.clear()
			ship.pending_route.clear()
			_set_hold(ship, "")
		ship_changed.emit(ship)
		return
	if not energy.run_error(who, ship, field_id, port_id).is_empty():
		return
	ship.remove_meta(&"rig_off")
	ship.rig_field = field_id
	ship.rig_port = port_id
	ship.paused = false
	if ship.is_docked():
		ship.route.assign([port_id])
		ship.pending_route.clear()
		ship.hop_to = ""
		ship.route_index = 0
	else:
		ship.pending_route.assign([port_id])
	_set_hold(ship, "")
	_rebalance_tugs()
	ship_changed.emit(ship)


## A ship on rig runs in port with its stop done: away from its delivery port
## it heads there; there, it sets out for its field once it has the fuel for
## the trip there and back.
func _rig_in_port(ship: Ship, delta: float) -> void:
	if ship.docked_at != ship.rig_port:
		_try_depart(ship, delta, ship.rig_port)
		return
	var who := owner_of(ship)
	var where := Energy.field_name(ship.rig_field)
	if energy.owned_by(who, ship.rig_field).is_empty():
		_set_hold(ship, "you have no rigs at %s any more; give it a new route" % where)
		return
	var miles := Energy.miles_to(ship.rig_port, ship.rig_field)
	if miles == INF:
		_set_hold(ship, "there's no way out to %s from here" % where)
		return
	var storm := weather.closed_by(ship.docked_at)
	if not storm.is_empty():
		_set_hold(ship, "%s is closed by %s" % [GameData.port_name(ship.docked_at), Weather.title(storm)])
		return
	var need := ship.fuel_per_s() * (2.0 * ship.sailing_seconds(miles, maxf(ship.maintenance, 0.5)) + DEPARTURE_MARGIN_S)
	if need > ship.fuel_tank():
		_set_hold(ship, "%s is too far there and back on one tank; give it a nearer port" % where)
		return
	if ship.fuel < need:
		if ship.auto_refuel:
			_refuel(ship, need - ship.fuel)
		if ship.fuel < need:
			_set_hold(ship, "waiting for the money for fuel")
			return
	_set_hold(ship, "")
	# At its pier: it pulls out and sails straight on out to its field (its
	# first leg's end as where it's bound: see _advance_berth(), which starts
	# the trip once it's clear). From the moorings, it sets off from its spot.
	if ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
		var legs := Energy.legs(ship.docked_at, ship.rig_field)
		ship.set_meta(&"rig_trip", true)
		_pull_out(ship, str((legs[0] as Array)[0][1]))
		return
	_start_rig_trip(ship)


## Sets out for its field: on a job the whole trip (Ship.JOB_RIG), sailing its legs out.
func _start_rig_trip(ship: Ship) -> void:
	if not ship.is_rig_runner() or ship.docked_at.is_empty():
		return
	var legs := Energy.legs(ship.docked_at, ship.rig_field)
	if (legs[0] as Array).is_empty() or float(legs[0][-1][3]) == INF:
		return
	_set_hold(ship, "")
	_leave_port(ship)
	ship.docked_at = ""
	ship.job_phase = Ship.JOB_RIG
	ship.rig_phase = "out"
	ship.rig_wait = 0.0
	ship.job_segments = (legs[0] as Array).duplicate(true)
	_start_segment(ship, ship.job_segments.pop_front())
	ship_changed.emit(ship)


## The field a rig run or a tug's repair is for.
func _rig_field_of(ship: Ship) -> String:
	return ship.rig_field if ship.job_phase == Ship.JOB_RIG else Energy.field_of(ship.rig_slot)


## A rig run or a tug's repair: sailing out, alongside the rigs (loading, or
## repairing), sailing home.
func _advance_rig(ship: Ship, delta: float) -> void:
	if ship.rig_phase == "load":
		ship.worked = true
		ship.rig_wait += delta
		if ship.job_phase == Ship.JOB_REPAIR:
			_repair_at_rig(ship)
		else:
			_load_at_rig(ship)
		return
	if not _sail(ship, delta):
		_rig_lost(ship)
		return
	if ship.traveled_nm < ship.segment_end:
		return
	ship.traveled_nm = ship.segment_end
	if not ship.job_segments.is_empty():
		_start_segment(ship, ship.job_segments.pop_front())
		return
	if ship.rig_phase == "out":
		ship.rig_phase = "load"
		ship.rig_wait = 0.0
		ship_changed.emit(ship)
		return
	# Home: a tug back from its repair, or a ship with its load for its delivery port.
	var port := ship.to_port
	var repair := ship.job_phase == Ship.JOB_REPAIR
	var field_id := _rig_field_of(ship)
	ship.job_phase = Ship.JOB_NONE
	ship.rig_phase = ""
	ship.job_segments.clear()
	ship.segment_end = 0.0
	if repair:
		ship.rig_slot = ""
		ship.rig_port = ""
		_arrive(ship, port, false)
		return
	_arrive(ship, port, true)
	if not ship.cargo_id.is_empty():
		ship.cargo_leg_nm = Energy.miles_to(port, field_id)  # (Its leg from the field.)
	if ship.has_meta(&"rig_off"):
		ship.remove_meta(&"rig_off")
		ship.rig_field = ""
		ship.rig_port = ""
		if ship.pending_route.is_empty() and ship.route == [port]:
			ship.route.clear()


## Alongside the rigs: it loads what they've stored (topping up as they pump),
## for a stop's time at least, and heads home full, or after rig_wait_days.
func _load_at_rig(ship: Ship) -> void:
	var full := not ship.cargo_id.is_empty() and ship.cargo_qty >= floori(ship.capacity() / GameData.hold_of(ship.cargo_id))
	if not full and energy.load_at_field(ship) > 0:
		ship_changed.emit(ship)
		full = ship.cargo_qty >= floori(ship.capacity() / GameData.hold_of(ship.cargo_id))
	if ship.rig_wait < float(ship.model().get("dock_s", 10)):
		return
	var day_s := Energy.DAY_S / maxf(calendar_seconds_per_second(), 1.0)
	if full or ship.rig_wait >= float(Energy.setting("rig_wait_days", 3)) * day_s or energy.owned_by(owner_of(ship), ship.rig_field).is_empty():
		_head_home_from_rig(ship)


## A tug alongside a damaged rig: repair_days of work, then it's sound and the tug heads home.
func _repair_at_rig(ship: Ship) -> void:
	var day_s := Energy.DAY_S / maxf(calendar_seconds_per_second(), 1.0)
	if ship.rig_wait < float(Energy.setting("repair_days", 2)) * day_s:
		return
	energy.repaired(ship.rig_slot)
	_head_home_from_rig(ship)


func _head_home_from_rig(ship: Ship) -> void:
	var home := ship.rig_port
	var legs := Energy.legs(home, _rig_field_of(ship))
	ship.rig_phase = "home"
	ship.job_segments = (legs[1] as Array).duplicate(true)
	_start_segment(ship, ship.job_segments.pop_front())
	if ship.job_phase == Ship.JOB_RIG and not ship.cargo_id.is_empty():
		cargo_loaded.emit(ship, Energy.end_of(ship.rig_field), ship.cargo_id, ship.cargo_qty, ship.cargo_cost, home)
	ship_changed.emit(ship)


## Lost at sea on a rig run (its load stays aboard, sold wherever it's brought
## in, or its delivery port after) or a tug's repair (the rig waits for another).
func _rig_lost(ship: Ship) -> void:
	if ship.job_phase == Ship.JOB_REPAIR and energy.slots.has(ship.rig_slot):
		energy.slots[ship.rig_slot].tug = 0
		ship.rig_slot = ""
	ship.job_phase = Ship.JOB_NONE
	ship.rig_phase = ""
	ship.job_segments.clear()
	ship.segment_end = 0.0
	ship_changed.emit(ship)


## Sends this player's nearest free tug out to repair a damaged rig (Energy.repair_error() says why it can't).
func send_rig_tug(key: String) -> void:
	if not energy.repair_error(company, key).is_empty():
		return
	if Net.command(&"send_rig_tug", [key]):
		return
	_send_rig_tug(company, key)


func _send_rig_tug(who: Company, key: String) -> void:
	if not energy.repair_error(who, key).is_empty():
		return
	var tug: Ship = energy.repair_tug(who, key)[0]
	var fee := energy.repair_fee(key)
	_add_money(who, -fee)
	_record(null, "energy", fee, who)
	energy.slots[key].tug = tug.id
	var legs := Energy.legs(tug.docked_at, Energy.field_of(key))
	tug.rig_slot = key
	tug.rig_port = tug.docked_at
	_set_hold(tug, "")
	_leave_port(tug)
	tug.docked_at = ""
	tug.job_phase = Ship.JOB_REPAIR
	tug.rig_phase = "out"
	tug.rig_wait = 0.0
	tug.job_segments = (legs[0] as Array).duplicate(true)
	_start_segment(tug, tug.job_segments.pop_front())
	if who == company:
		ActivityLog.add("%s is heading out to repair your %s at %s (%s)." % [tug.name, str(Energy.rig_info(str(energy.slots[key].kind)).get("name", "rig")).to_lower(),
			Energy.field_name(Energy.field_of(key)), Fmt.money(fee)], ActivityLog.Kind.INFO, ActivityLog.ship_color(tug))
	energy._changed()
	ship_changed.emit(tug)


## Buys a free slot at a field for its rig or platform (Energy.buy_error() says why it can't).
func buy_rig(key: String) -> void:
	if Net.command(&"buy_rig", [key]):
		return
	energy.buy(company, key)


func sell_rig(key: String) -> void:
	if Net.command(&"sell_rig", [key]):
		return
	var price := energy.sell_back(company, key)
	if price > 0:
		ActivityLog.add("Sold your rig at %s for %s." % [Energy.field_name(Energy.field_of(key)), Fmt.money(price)], ActivityLog.Kind.INFO)


## Lists a slot for other Tankers companies at an asking price (0 takes it off the list).
func list_rig(key: String, price: int) -> void:
	if Net.command(&"list_rig", [key, price]):
		return
	energy.list(company, key, price)


func buy_listed_rig(key: String) -> void:
	if Net.command(&"buy_listed_rig", [key]):
		return
	energy.buy_listing(company, key)


func upgrade_rig(key: String, upgrade_id: String) -> void:
	if Net.command(&"upgrade_rig", [key, upgrade_id]):
		return
	energy.add_upgrade(company, key, upgrade_id)


func lay_pipeline(key: String) -> void:
	if Net.command(&"lay_pipeline", [key]):
		return
	if not energy.pipe_error(company, key).is_empty():
		return
	var target: Array = energy.pipe_target(company, Energy.field_of(key))
	energy.lay_pipe(company, key)
	ActivityLog.add("Laid a pipeline from %s to %s." % [Energy.field_name(Energy.field_of(key)), GameData.port_name(str(target[0]))], ActivityLog.Kind.GOOD)


## "a" or "an" before a word.
static func _a(word: String) -> String:
	return ("an " if word.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + word


## Puts up a building at a port (Energy.build_error() says why it can't).
func build_plant(building_id: String, port_id: String) -> void:
	if Net.command(&"build_plant", [building_id, port_id]):
		return
	if not energy.build_error(company, building_id, port_id).is_empty():
		return
	energy.build(company, building_id, port_id)
	ActivityLog.add("Built %s at %s." % [_a(str(Energy.building(building_id).name).to_lower()), GameData.port_name(port_id)], ActivityLog.Kind.GOOD)


func demolish_plant(building_id: String, port_id: String) -> void:
	if Net.command(&"demolish_plant", [building_id, port_id]):
		return
	var refund := energy.demolish(company, building_id, port_id)
	if refund > 0:
		ActivityLog.add("Pulled down your %s at %s for %s." % [str(Energy.building(building_id).name).to_lower(), GameData.port_name(port_id), Fmt.money(refund)], ActivityLog.Kind.INFO)


func upgrade_plant(building_id: String, port_id: String, upgrade_id: String) -> void:
	if Net.command(&"upgrade_plant", [building_id, port_id, upgrade_id]):
		return
	energy.upgrade_plant(company, building_id, port_id, upgrade_id)


func set_plant_mode(building_id: String, port_id: String, mode: String) -> void:
	if Net.command(&"set_plant_mode", [building_id, port_id, mode]):
		return
	energy.set_mode(company, building_id, port_id, mode)


## Sells what this player's store at a port holds of a good, at the port's price.
func sell_energy_item(port_id: String, commodity: String) -> void:
	if Net.command(&"sell_energy_item", [port_id, commodity]):
		return
	var value := energy.sell_item(company, port_id, commodity)
	if value > 0:
		ActivityLog.add("Sold the %s in your tanks at %s for %s." % [Energy.good_word(commodity), GameData.port_name(port_id), Fmt.money(value)], ActivityLog.Kind.GOOD)


# --- Industry (see Industry): this player's actions ---------------------------------------------

## Builds a mine, camp, plant or factory at a port (Industry.build_error() says why it can't).
func build_site(building_id: String, port_id: String) -> void:
	if Net.command(&"build_site", [building_id, port_id]):
		return
	var key := industry.build(company, building_id, port_id)
	if not key.is_empty():
		ActivityLog.add("Built a %s at %s for %s. It makes about %s %s of %s a month." % [str(Industry.building(building_id).name).to_lower(), GameData.port_name(port_id),
			Fmt.money(Industry.cost(building_id)), Fmt.thousands(roundi(Industry.output_a_month(building_id))),
			GameData.commodity(str(Industry.building(building_id).makes)).get("units", "units"), str(GameData.commodity(str(Industry.building(building_id).makes)).get("name", "")).to_lower()], ActivityLog.Kind.GOOD)


## Closes this player's site, for a quarter of its price back.
func close_site(key: String) -> void:
	if Net.command(&"close_site", [key]):
		return
	var refund := industry.close(company, key)
	if refund > 0:
		ActivityLog.add("Closed your %s at %s: %s back." % [str(Industry.building(Industry.building_of(key)).get("name", "")).to_lower(), GameData.port_name(Industry.port_of(key)), Fmt.money(refund)], ActivityLog.Kind.INFO)


## Sells a site's stockpile where it is, at the port's price.
func sell_site_stock(key: String) -> void:
	if Net.command(&"sell_site_stock", [key]):
		return
	var value := industry.sell_stock(company, key)
	if value > 0:
		ActivityLog.add("Sold the stock of your %s at %s for %s." % [str(Industry.building(Industry.building_of(key)).get("name", "")).to_lower(), GameData.port_name(Industry.port_of(key)), Fmt.money(value)], ActivityLog.Kind.GOOD)


## Lists a site for other Cargo & Ore companies at an asking price (0 takes it off the list).
func list_site(key: String, price: int) -> void:
	if Net.command(&"list_site", [key, price]):
		return
	industry.list(company, key, price)


## Buys another company's listed site at its asking price.
func buy_listed_site(key: String) -> void:
	if Net.command(&"buy_listed_site", [key]):
		return
	industry.buy_listing(company, key)


# --- Research (see Research) ----------------------------------------------------------

## Sends a docked research ship on an expedition: to a site (or a contract's
## target, with contract_id), from where it is. Research.trip_error() says why it can't.
func send_expedition(ship: Ship, target: String, contract_id := 0) -> void:
	var offer := research.offer_by_id(contract_id) if contract_id > 0 else {}
	if not research.trip_error(company, ship, target, offer).is_empty():
		return
	if Net.command(&"send_expedition", [ship, target, contract_id]):
		return
	research.send(owner_of(ship), ship, target, contract_id)


## Calls a research ship's expedition off (one out at sea heads home).
func recall_expedition(ship: Ship) -> void:
	if Net.command(&"recall_expedition", [ship]):
		return
	research.recall(ship)


## Sends an idle research ship to another port, its new base.
func move_research_ship(ship: Ship, port_id: String) -> void:
	if Net.command(&"move_research_ship", [ship, port_id]):
		return
	research.move(owner_of(ship), ship, port_id)


func fit_gear(ship: Ship, gear_id: String) -> void:
	if not research.fit_error(owner_of(ship), ship, gear_id).is_empty():
		return
	if Net.command(&"fit_gear", [ship, gear_id]):
		return
	research.fit(owner_of(ship), ship, gear_id)


func remove_gear(ship: Ship, gear_id: String) -> void:
	if Net.command(&"remove_gear", [ship, gear_id]):
		return
	research.remove(owner_of(ship), ship, gear_id)


## Takes a contract off the board (Research.accept_error() says why it can't).
func accept_contract(contract_id: int) -> void:
	if not research.accept_error(company, contract_id).is_empty():
		return
	if Net.command(&"accept_contract", [contract_id]):
		return
	research.accept(company, contract_id)


## Gives a taken contract up: it fails, its penalty paid.
func abandon_contract(contract_id: int) -> void:
	if Net.command(&"abandon_contract", [contract_id]):
		return
	research.abandon(company, contract_id)


## A new game's world runs WARM_UP_DAYS before play time 0 so ships are at sea
## and stocks have settled when it begins: the clock is wound back and stepped
## up to 0, a few days a frame behind the loading screen (which says how far
## it is; GameRoot.is_warm() waits), the game saved once it's there.
var warm_up_left := 0
var warm_up_total := 0
var _warm_up_to := 0.0
## How long a frame of the warm-up may take (ms).
const WARM_UP_FRAME_MS := 40.0


func _start_warm_up(days: int) -> void:
	warm_up_total = days
	warm_up_left = days
	_warm_up_to = play_time
	play_time -= days * 86400.0 / calendar_seconds_per_second()


## Steps the warm-up a day at a time till its frame's time is up (or, with no
## limit, to the end).
func _warm_up_frame(limit_ms := WARM_UP_FRAME_MS) -> void:
	var day_s := 86400.0 / calendar_seconds_per_second()
	var start := Time.get_ticks_usec()
	while warm_up_left > 0:
		var i := warm_up_total - warm_up_left
		play_time += day_s
		world._step_day()
		firms._arrive(world)
		if i % ShippingFirms.DISPATCH_DAYS == 0:
			firms.dispatch_day()
		warm_up_left -= 1
		if Time.get_ticks_usec() - start >= limit_ms * 1000.0:
			break
	if warm_up_left > 0:
		return
	play_time = _warm_up_to
	world.day = world._today()
	history.weekly_day = world.day  # (The warm-up counted its own days: the next weekly sample a week from now.)
	firms._dispatch_day = world.day - ShippingFirms.DISPATCH_DAYS
	news.clear()  # (The warm-up's weeks made news before the game began: the history keeps them, the paper doesn't.)
	save_game()


## Runs the whole warm-up at once (tools and tests).
func warm_up_world(days: int) -> void:
	_start_warm_up(days)
	_warm_up_frame(INF)

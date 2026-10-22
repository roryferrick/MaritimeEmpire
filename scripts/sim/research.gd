# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Research
extends RefCounted
## The Research company type (data/research.json): survey vessels and deep-sea
## motherships (ship_models.json research: depth_m, gear_slots) go out to
## places under the sea (the sites: 200+ real trenches, wrecks, vents, sunken
## cities...) and hold on station to survey them.
##
## A research ship is a cargo-kind ship with no cargo (Ship.is_research()). It
## lies idle in port till sent on an expedition (GameState.send_expedition()):
## its route is then its base port, and once there with its stop done it sets
## out (in_port()), a job the whole trip (Ship.JOB_RESEARCH, research_phase
## "out", "work" on station, "home"), sailing the lanes laid out to each site
## ("PORT-@res_ID": tools/build_map_data.gd --fishing-only) like a fishing
## boat to its ground. On station it burns WORK_FUEL of its fuel and wears;
## storms pause the survey; each day a dive may fail (losing the day) and on
## the deepest sites a worn ship may lose its ROV or sub. When the site's
## days are done it's discovered (discover()) and the ship sails home and
## lies idle again. Only a ship deep enough (depth_m) with the site's needs
## fitted (gear: bought into its slots) can go.
##
## Personal research earns no money: research points (Company.research_points,
## banked for developing the company's own tech: DESIGN_LIVING_WORLD.md M5; the
## ship's tier rate for the trip's time, by the site's difficulty, half again for
## the first company to finish a site), the journal (Company.research done), the Research rating
## and perks: each category's at 25/50/100% of its sites done (perk()), and
## local ones (catch near surveyed wrecks and reefs: catch_factor(); sights
## for Expedition cruises: sights_near()). Contracts pay: a board shared by
## every company (board), a site, oil and gas field or fishing ground with a
## client, pay and deadline; taken (accept()), done by a ship sent with it, or
## failed at the deadline (its pay forfeited and a penalty paid).
##
## Hidden sites (not famous) show only as a search area till revealed: by a
## sonar ship working nearby, finishing a site nearby, or taking a contract
## there (Company.research revealed).

signal changed
## A site finished by a company's ship: first if no company had before; research points earned.
signal discovered(who: Company, site_id: String, first: bool, ship: Ship, points: float)
## A contract done (ok, paid) or failed (not ok, paid is the penalty).
signal contract_finished(who: Company, offer: Dictionary, ok: bool, paid: int)
## Hidden sites a company now knows of: their ids.
signal revealed(who: Company, site_ids: Array)
## A dive gone wrong: what happened ("a dive failed", "lost its ROV").
signal mishap(ship: Ship, what: String)

const PATH := "res://data/research.json"
const END_PREFIX := "@res_"
const DAY_S := 86400.0
## The share of its fuel burn a ship uses on station (holding position, launching and recovering).
const WORK_FUEL := 0.3
## A storm worse than this (its speed factor under it) stops the survey.
const STORM_PAUSE := 0.75
## The company tallies fade a little each day (rolling, for the rating).
const TALLY_FADE := 0.97
const LINES: Array[String] = ["survey", "mothership"]
const GEAR_REFUND := 0.5
## Most contracts a company may hold at once: this, plus one for every two research ships.
const OPEN_BASE := 2

static var _data := {}
static var _sites := {}
static var _site_order: Array[String] = []
static var _categories := {}
static var _gear := {}
static var _kinds := {}
static var _lane_ends := {}
static var _ways := {}
static var _perk_cache := {}  # Company instance id -> [done count, {stat: factor}]
static var _near_cache := {}  # "company id|kind|place" -> [done count, value]

var _state: Node
## The contracts board: [{id, kind, client, target (a lane end), site (site id
## or ""), title, needs, depth, days, pay, deadline (days to do it once taken),
## posted, expires (calendar days), taken_by (company index or -1), due}].
var board: Array = []
## Site id -> the index of the first company to finish it.
var firsts := {}
var next_id := 1
var day := -1
var version := 0
var _rng := RandomNumberGenerator.new()


func _init(state: Node) -> void:
	_state = state
	_rng.randomize()


func connect_signals() -> void:
	_state.ship_lost.connect(func(ship: Ship) -> void:
		if ship.is_research():
			_tally(_state.owner_of(ship), "losses", 1.0))
	_state.ship_broke_down.connect(func(ship: Ship) -> void:
		if ship.is_research():
			_tally(_state.owner_of(ship), "breakdowns", 1.0))


# --- The data ------------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if not parsed is Dictionary:
			push_error("Research: could not read %s" % PATH)
			return {}
		_data = parsed
		for site: Dictionary in _data.get("sites", []):
			_sites[site.id] = site
			_site_order.append(str(site.id))
		for each: Dictionary in _data.get("categories", []):
			_categories[each.id] = each
		for each: Dictionary in _data.get("gear", []):
			_gear[each.id] = each
		for each: Dictionary in _data.get("kinds", []):
			_kinds[each.id] = each
	return _data


static func setting(key: String, default: Variant = null) -> Variant:
	return data().get("settings", {}).get(key, default)


static func site(site_id: String) -> Dictionary:
	data()
	return _sites.get(site_id, {})


static func site_ids() -> Array[String]:
	data()
	return _site_order


static func categories() -> Array:
	return data().get("categories", [])


static func category(category_id: String) -> Dictionary:
	data()
	return _categories.get(category_id, {})


static func gear_list() -> Array:
	return data().get("gear", [])


static func gear_info(gear_id: String) -> Dictionary:
	data()
	return _gear.get(gear_id, {})


static func gear_name(gear_id: String) -> String:
	return str(gear_info(gear_id).get("name", gear_id))


static func kind(kind_id: String) -> Dictionary:
	data()
	return _kinds.get(kind_id, {})


static func line_name(line: String) -> String:
	return str(data().get("lines", {}).get(line, line))


## A site's end of its lanes ("@res_rms_titanic"), and back.
static func end_of(site_id: String) -> String:
	return END_PREFIX + site_id


static func is_site_end(port_id: String) -> bool:
	return port_id.begins_with(END_PREFIX)


static func site_of_end(end: String) -> String:
	return end.substr(END_PREFIX.length()) if is_site_end(end) else ""


## Where a contract or expedition goes: a site, an oil or gas field, or a fishing ground, by name.
static func target_name(end: String) -> String:
	if is_site_end(end):
		return str(site(site_of_end(end)).get("name", end))
	if Energy.is_field_end(end):
		return Energy.field_name(Energy.field_of_end(end))
	if Fisheries.is_ground(end):
		return Fisheries.ground_name(end.substr(1))
	return GameData.port_name(end)


## A target's real place (lon, lat): a site's own spot, else its lanes' end.
static func target_lonlat(end: String) -> Vector2:
	if is_site_end(end):
		var each := site(site_of_end(end))
		return Vector2(float(each.get("lon", 0)), float(each.get("lat", 0)))
	var port := GameData.get_port(end)
	return Vector2(float(port.get("lon", 0)), float(port.get("lat", 0)))


## Sea miles between two places (lon, lat), as the crow flies.
static func nm_between(a: Vector2, b: Vector2) -> float:
	var la := deg_to_rad(a.y)
	var lb := deg_to_rad(b.y)
	var d := sin((lb - la) / 2.0) ** 2 + cos(la) * cos(lb) * sin(deg_to_rad(b.x - a.x) / 2.0) ** 2
	return 2.0 * asin(sqrt(clampf(d, 0.0, 1.0))) * 3440.065


# --- Lanes ------------------------------------------------------------------------------

## The ports a lane end's lanes run from (the lane tool's, nearest first).
static func lane_ports(end: String) -> Array:
	if _lane_ends.is_empty():
		_lane_ends = GameData.fishing_lanes()
	return _lane_ends.get(end, [])


## Whether ships can get out to a target at all (its lanes were laid).
static func reachable(end: String) -> bool:
	return not lane_ports(end).is_empty()


## The port a ship from `base` sets out to a target by, and the miles one way:
## [port, miles], or ["", INF] if there's no way (as Energy.way_to()).
static func way_to(base: String, end: String) -> Array:
	var key := base + ">" + end
	if _ways.has(key):
		return _ways[key]
	var best := ""
	var best_nm := INF
	for port: String in lane_ports(end):
		if port == base:
			continue
		var nm := GameData.distance_nm(base, port, -1) + GameData.distance_nm(port, end, -1)
		if nm < best_nm:
			best_nm = nm
			best = port
	var straight := GameData.distance_nm(base, end, -1)
	var way := [base, straight] if straight < INF and straight <= best_nm * 1.3 else [best, best_nm]
	_ways[key] = way
	return way


static func miles_to(base: String, end: String) -> float:
	return float(way_to(base, end)[1])


## A trip's legs out to a target from `base` and back: [out, home], each a
## list of [from, to, start_nm, end_nm] segments.
static func legs(base: String, end: String) -> Array:
	var port: String = way_to(base, end)[0]
	var out := []
	var home := []
	if port.is_empty():
		return [out, home]
	if base != port:
		out.append([base, port, 0.0, GameData.distance_nm(base, port, -1)])
	out.append([port, end, 0.0, GameData.distance_nm(port, end, -1)])
	home.append([end, port, 0.0, GameData.distance_nm(end, port, -1)])
	if base != port:
		home.append([port, base, 0.0, GameData.distance_nm(port, base, -1)])
	return [out, home]


# --- Ships and gear ----------------------------------------------------------------------

static func can_research(who: Company) -> bool:
	return who != null and who.has_type("research")


static func is_research_model(model: Dictionary) -> bool:
	return model.has("research")


static func depth_of(model: Dictionary) -> int:
	return int(model.get("research", {}).get("depth_m", 0))


static func slots_of(model: Dictionary) -> int:
	return int(model.get("research", {}).get("gear_slots", 0))


static func can_fit(model: Dictionary, gear_id: String) -> bool:
	return (gear_info(gear_id).get("lines", []) as Array).has(str(model.get("category", "")))


## What fitting a piece of gear costs on a model: its share of the model's price.
static func gear_cost(model: Dictionary, gear_id: String) -> int:
	var cost := float(model.get("price", 0)) * float(gear_info(gear_id).get("cost", 0.1))
	return _round_2(cost)


static func _round_2(value: float) -> int:
	if value <= 0.0:
		return 0
	var magnitude := pow(10.0, floorf(log(value) / log(10.0)) - 1.0)
	return int(roundf(value / magnitude) * magnitude)


## Why a piece of gear can't be fitted now, or "".
func fit_error(who: Company, ship: Ship, gear_id: String) -> String:
	if not ship.is_research():
		return "Only research ships carry research gear."
	if gear_info(gear_id).is_empty():
		return "There's no such gear."
	if not can_fit(ship.model(), gear_id):
		return "%s can't be fitted on %s." % [gear_name(gear_id), line_name(str(ship.model().get("category", ""))).to_lower()]
	if ship.research_gear.has(gear_id):
		return "It already has one."
	if ship.research_gear.size() >= slots_of(ship.model()):
		return "Its %d gear slots are full: take something off first." % slots_of(ship.model())
	if not ship.is_docked() or ship.job_phase != Ship.JOB_NONE:
		return "Gear is fitted in port."
	if who.money < gear_cost(ship.model(), gear_id):
		return "You can't afford it."
	return ""


func fit(who: Company, ship: Ship, gear_id: String) -> bool:
	if not fit_error(who, ship, gear_id).is_empty():
		return false
	var cost := gear_cost(ship.model(), gear_id)
	_state._add_money(who, -cost)
	_state._record(ship, "research_gear", cost, who)
	ship.research_gear.append(gear_id)
	_state.ship_changed.emit(ship)
	_changed()
	return true


## Takes a piece of gear off (in port), for GEAR_REFUND of its cost.
func remove(who: Company, ship: Ship, gear_id: String) -> int:
	if not ship.research_gear.has(gear_id) or not ship.is_docked() or ship.job_phase != Ship.JOB_NONE:
		return 0
	var back := roundi(gear_cost(ship.model(), gear_id) * GEAR_REFUND)
	ship.research_gear.erase(gear_id)
	_state._add_money(who, back)
	_state._record(ship, "research_gear", -back, who)
	_state.ship_changed.emit(ship)
	_changed()
	return back


# --- Targets -----------------------------------------------------------------------------

## What a target needs fitted: a site's needs, an offer's own (industry surveys).
static func needs_of(end: String, offer := {}) -> Array:
	if not offer.is_empty():
		return offer.get("needs", [])
	if is_site_end(end):
		return site(site_of_end(end)).get("needs", [])
	return ["sonar"]


static func depth_at(end: String, offer := {}) -> int:
	if not offer.is_empty():
		return int(offer.get("depth", 0))
	return int(site(site_of_end(end)).get("depth_m", 200))


## Calendar days on station a target takes (an offer's, else its site's).
static func days_at(end: String, offer := {}) -> float:
	if not offer.is_empty():
		return float(offer.get("days", 3))
	return float(site(site_of_end(end)).get("days", 3))


## Seconds of play a calendar day takes at 1x.
func day_s() -> float:
	return DAY_S / maxf(_state.calendar_seconds_per_second(), 1.0)


## Seconds of play a ship needs on station: the target's days, a fifth less with sonar.
func station_s(ship: Ship, end: String, offer := {}) -> float:
	var days := days_at(end, offer)
	if ship.research_gear.has("sonar"):
		days *= 1.0 - float(setting("sonar_speedup", 0.2))
	return days * day_s()


## Fuel for a trip there and back with its time on station, and a little spare.
func trip_fuel(ship: Ship, end: String, offer := {}) -> float:
	var miles := miles_to(ship.docked_at if ship.is_docked() else ship.research_base, end)
	return ship.fuel_per_s() * (2.0 * ship.sailing_seconds(miles, maxf(ship.maintenance, 0.5)) + station_s(ship, end, offer) * WORK_FUEL + _state.DEPARTURE_MARGIN_S)


## The gear a ship lacks for a target.
static func missing(ship: Ship, end: String, offer := {}) -> Array:
	return needs_of(end, offer).filter(func(gear_id: String) -> bool: return not ship.research_gear.has(gear_id))


## Why a ship can't go to a target now (from where it is), or "". With
## from_port, as if it were docked there (for planning).
func trip_error(who: Company, ship: Ship, end: String, offer := {}, from_port := "") -> String:
	if not ship.is_research():
		return "Only research ships go on expeditions."
	if ship.is_lost():
		return "It's lost at sea."
	var base := from_port if not from_port.is_empty() else ship.docked_at
	if from_port.is_empty():
		if not ship.is_docked():
			return "It's at sea: send it once it's in port."
		if ship.job_phase != Ship.JOB_NONE or not ship.research_target.is_empty():
			return "It's already on an expedition."
	if not reachable(end):
		return "There's no way out to %s yet." % target_name(end)
	var depth := depth_at(end, offer)
	if depth > depth_of(ship.model()):
		return "Too deep: %s m down, past the %s m this ship can reach." % [Fmt.thousands(depth), Fmt.thousands(depth_of(ship.model()))]
	var lacking := missing(ship, end, offer)
	if not lacking.is_empty():
		return "It needs %s fitted." % _and_list(lacking.map(func(gear_id: String) -> String: return gear_name(gear_id)))
	if not offer.is_empty() and int(offer.get("taken_by", -1)) != _index_of(who):
		return "Take the contract first."
	var miles := miles_to(base, end)
	if miles == INF:
		return "There's no way out to %s from %s." % [target_name(end), GameData.port_name(base)]
	if miles > ship.range_nm():
		return "%s is %s nm from %s; it reaches %s nm. Move it to a nearer port first." % [target_name(end), Fmt.thousands(roundi(miles)), GameData.port_name(base), Fmt.thousands(roundi(ship.range_nm()))]
	var need := ship.fuel_per_s() * (2.0 * ship.sailing_seconds(miles, 1.0) + station_s(ship, end, offer) * WORK_FUEL)
	if need > ship.fuel_tank():
		return "%s is too far there and back on one tank from %s." % [target_name(end), GameData.port_name(base)]
	return ""


static func _and_list(items: Array) -> String:
	if items.size() <= 1:
		return "".join(PackedStringArray(items))
	return ", ".join(PackedStringArray(items.slice(0, -1))) + " and " + str(items[-1])


# --- Expeditions ---------------------------------------------------------------------------

## Sends a docked research ship out to a target (with a contract it holds, or
## 0 for its own research); its port now its base. False if it can't go.
func send(who: Company, ship: Ship, end: String, contract_id := 0) -> bool:
	var offer := offer_by_id(contract_id) if contract_id > 0 else {}
	if contract_id > 0 and offer.is_empty():
		return false
	if not trip_error(who, ship, end, offer).is_empty():
		return false
	ship.research_target = end
	ship.research_contract = contract_id
	ship.research_base = ship.docked_at
	ship.paused = false
	ship.route.assign([ship.docked_at])
	ship.pending_route.clear()
	ship.hop_to = ""
	ship.route_index = 0
	_state._set_hold(ship, "")
	_state.ship_changed.emit(ship)
	_changed()
	return true


## Moves an idle research ship to another port (its new base), to set out from there.
func move(who: Company, ship: Ship, port_id: String) -> bool:
	if not ship.is_research() or ship.job_phase != Ship.JOB_NONE or not ship.research_target.is_empty() or GameData.get_port(port_id).is_empty() or port_id.begins_with("@"):
		return false
	ship.research_base = port_id
	ship.paused = false
	if ship.is_docked():
		ship.route.assign([port_id])
		ship.route_index = 0
	else:
		ship.pending_route.assign([port_id])
	_state._set_hold(ship, "")
	_state.ship_changed.emit(ship)
	return true


## Calls an expedition off: one not yet out stays in port; one out heads home now.
func recall(ship: Ship) -> void:
	if ship.job_phase == Ship.JOB_RESEARCH:
		if ship.research_phase == "out" or ship.research_phase == "work":
			_head_home(ship, false)
		return
	ship.research_target = ""
	ship.research_contract = 0
	_state._set_hold(ship, "")
	_state.ship_changed.emit(ship)


## A research ship in port with its stop done (GameState._advance_docked()):
## away from its base it sails there; there, with an expedition to make, it
## sets out once it has the fuel; with none it lies idle.
func in_port(ship: Ship, delta: float) -> void:
	if ship.research_base.is_empty():
		ship.research_base = ship.docked_at
	if ship.docked_at != ship.research_base:
		_state._try_depart(ship, delta, ship.research_base)
		return
	if ship.research_target.is_empty():
		ship.route.clear()
		_state._set_hold(ship, "")
		_state.ship_changed.emit(ship)
		return
	var who: Company = _state.owner_of(ship)
	var offer := offer_by_id(ship.research_contract) if ship.research_contract > 0 else {}
	if ship.research_contract > 0 and offer.is_empty():
		ship.research_contract = 0  # (The contract's gone: failed or done another way.)
		if not is_site_end(ship.research_target):
			ship.research_target = ""
			return
	var error := trip_error(who, ship, ship.research_target, offer, ship.docked_at)
	if not error.is_empty():
		_state._set_hold(ship, error)
		return
	var storm: Dictionary = _state.weather.closed_by(ship.docked_at)
	if not storm.is_empty():
		_state._set_hold(ship, "%s is closed by %s" % [GameData.port_name(ship.docked_at), Weather.title(storm)])
		return
	var need := trip_fuel(ship, ship.research_target, offer)
	if ship.fuel < need:
		if ship.auto_refuel:
			_state._refuel(ship, need - ship.fuel)
		if ship.fuel < need:
			_state._set_hold(ship, "waiting for the money for fuel")
			return
	_state._set_hold(ship, "")
	if ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
		var out: Array = legs(ship.docked_at, ship.research_target)[0]
		ship.set_meta(&"research_trip", true)
		_state._pull_out(ship, str(out[0][1]))
		return
	start_trip(ship)


## Sets out for its target: on a job the whole trip, sailing its legs out.
func start_trip(ship: Ship) -> void:
	if not ship.is_research() or ship.docked_at.is_empty() or ship.research_target.is_empty():
		return
	var trip := legs(ship.docked_at, ship.research_target)
	if (trip[0] as Array).is_empty() or float(trip[0][-1][3]) == INF:
		return
	_state._set_hold(ship, "")
	_state._leave_port(ship)
	ship.docked_at = ""
	ship.job_phase = Ship.JOB_RESEARCH
	ship.research_phase = "out"
	ship.research_work = 0.0
	ship.research_roll = 0.0
	ship.research_since = _state.play_time
	ship.job_segments = (trip[0] as Array).duplicate(true)
	_state._start_segment(ship, ship.job_segments.pop_front())
	_tally(_state.owner_of(ship), "trips", 1.0)
	_state.ship_changed.emit(ship)


## A ship on its expedition: sailing out, on station, sailing home.
func advance(ship: Ship, delta: float) -> void:
	if ship.research_phase == "work":
		_work(ship, delta)
		return
	if not _state._sail(ship, delta):
		_trip_lost(ship)
		return
	if ship.traveled_nm < ship.segment_end:
		return
	ship.traveled_nm = ship.segment_end
	if not ship.job_segments.is_empty():
		_state._start_segment(ship, ship.job_segments.pop_front())
		return
	if ship.research_phase == "out":
		ship.research_phase = "work"
		ship.research_work = 0.0
		ship.research_roll = 0.0
		if ship.research_gear.has("sonar"):  # (Its sonar sweeps the seas round about: see reveal_near().)
			reveal_near(_state.owner_of(ship), target_lonlat(ship.research_target), float(setting("reveal_nm", 450)))
		_state.ship_changed.emit(ship)
		return
	# Home: it lies idle there (see in_port()) once its stop is done.
	var port: String = ship.to_port
	ship.job_phase = Ship.JOB_NONE
	ship.research_phase = ""
	ship.research_target = ""
	ship.research_contract = 0
	ship.job_segments.clear()
	ship.segment_end = 0.0
	ship.weather_wait = ""
	_state._arrive(ship, port, false)
	_changed()


## On station: the survey goes on as play time passes (paused by a bad storm),
## its fuel and hull wearing; each day's dives may go wrong. Done, the site is
## discovered (or the contract done) and it heads home; short of the fuel or
## hull to get home it turns back first.
func _work(ship: Ship, delta: float) -> void:
	var storm: Array = _state._storm_factors(ship)
	ship.worked = true
	ship.sea_time += delta
	ship.fuel = maxf(ship.fuel - ship.fuel_per_s() * WORK_FUEL * delta, 0.0)
	ship.maintenance = maxf(ship.maintenance - ship.wear_per_s() * float(storm[1]) * delta, 0.0)
	if ship.fuel <= 0.0:
		_state._lose(ship, "out of fuel")
		_trip_lost(ship)
		return
	if ship.maintenance <= 0.0:
		_state._lose(ship, "broken down")
		_trip_lost(ship)
		return
	var paused := float(storm[0]) < STORM_PAUSE
	var note := "survey paused by the storm" if paused else ""
	if ship.weather_wait != note:
		ship.weather_wait = note
		_state.ship_changed.emit(ship)
	if not paused:
		ship.research_work += delta
		ship.research_roll += delta
		if ship.research_roll >= day_s():
			ship.research_roll -= day_s()
			if not _roll_day(ship):
				return
	var offer := offer_by_id(ship.research_contract) if ship.research_contract > 0 else {}
	if ship.research_work >= station_s(ship, ship.research_target, offer):
		_complete(ship, offer)
		return
	# Enough left to get home?
	var miles := miles_to(ship.research_base, ship.research_target)
	var home_s := ship.sailing_seconds(miles, ship.maintenance)
	if home_s == INF or ship.fuel < ship.fuel_per_s() * (home_s + _state.DEPARTURE_MARGIN_S) * 1.05 or ship.maintenance - ship.wear_per_s() * home_s * 1.05 <= 0.15:
		if _state.is_mine(ship):
			ActivityLog.add("%s turned back from %s before finishing, short of fuel or worn out." % [ship.name, target_name(ship.research_target)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))
		_head_home(ship, false)


## A day's dives: one may fail (the day lost: more likely on a worn ship),
## and on the deepest sites a worn ship may lose its ROV or sub. False if it
## turned for home (its gear for the job gone).
func _roll_day(ship: Ship) -> bool:
	var who: Company = _state.owner_of(ship)
	_tally(who, "dives", 1.0)
	if _rng.randf() < float(setting("fail_chance_per_day", 0.06)) * (1.5 - clampf(ship.maintenance, 0.0, 1.0)):
		ship.research_work = maxf(ship.research_work - day_s(), 0.0)
		_tally(who, "dive_fails", 1.0)
		_mishap(ship, "a dive failed, losing a day")
	var depth := depth_at(ship.research_target, offer_by_id(ship.research_contract) if ship.research_contract > 0 else {})
	if depth > int(setting("gear_loss_depth", 6000)) and ship.maintenance < float(setting("gear_loss_maintenance", 0.5)) \
			and _rng.randf() < float(setting("gear_loss_chance", 0.12)):
		var gone := "sub" if ship.research_gear.has("sub") else ("rov" if ship.research_gear.has("rov") else "")
		if not gone.is_empty():
			ship.research_gear.erase(gone)
			_tally(who, "gear_lost", 1.0)
			_mishap(ship, "lost its %s on a dive" % gear_name(gone).to_lower())
			if needs_of(ship.research_target).has(gone):
				_head_home(ship, false)
				return false
	return true


## The survey's done: the site is the company's (and the first's), a
## contract's pay comes in; then home.
func _complete(ship: Ship, offer: Dictionary) -> void:
	var who: Company = _state.owner_of(ship)
	var site_id := site_of_end(ship.research_target)
	if not site_id.is_empty():
		discover(who, site_id, ship)
	elif offer.is_empty():
		earn_points(ship, points_rate(ship.model()) * (_state.play_time - ship.research_since) * 0.5)
	if not offer.is_empty():
		_finish_contract(who, offer, ship)
	_head_home(ship, true)


func _head_home(ship: Ship, _done: bool) -> void:
	var trip := legs(ship.research_base, ship.research_target)
	ship.research_phase = "home"
	ship.weather_wait = ""
	ship.job_segments = (trip[1] as Array).duplicate(true)
	if ship.job_segments.is_empty():
		ship.job_phase = Ship.JOB_NONE
		ship.research_phase = ""
		return
	_state._start_segment(ship, ship.job_segments.pop_front())
	_state.ship_changed.emit(ship)


## Lost at sea on an expedition: the trip ends where it is (its contract
## stays taken, to send another ship before the deadline); once it's brought
## in, it sails back to its base (its route).
func _trip_lost(ship: Ship) -> void:
	ship.job_phase = Ship.JOB_NONE
	ship.research_phase = ""
	ship.research_target = ""
	ship.research_contract = 0
	ship.job_segments.clear()
	ship.segment_end = 0.0
	ship.weather_wait = ""
	_state.ship_changed.emit(ship)


## What a research ship is doing, in words.
func status_text(ship: Ship) -> String:
	if ship.is_lost():
		return "lost at sea"
	var where := Research.target_name(ship.research_target) if not ship.research_target.is_empty() else ""
	if ship.job_phase == Ship.JOB_RESEARCH:
		match ship.research_phase:
			"out":
				return "sailing out to %s" % where
			"work":
				var offer := offer_by_id(ship.research_contract) if ship.research_contract > 0 else {}
				var share := ship.research_work / maxf(station_s(ship, ship.research_target, offer), 0.001)
				return "on station at %s: %d%% done%s" % [where, roundi(clampf(share, 0.0, 1.0) * 100.0), " (paused by a storm)" if not ship.weather_wait.is_empty() else ""]
			"home":
				return "heading home to %s" % GameData.port_name(ship.research_base)
	if ship.is_docked():
		if not where.is_empty():
			return "setting out for %s%s" % [where, (": " + ship.hold_reason) if ship.is_held() else ""]
		if ship.is_running() and ship.docked_at != ship.research_base:
			return "leaving for %s" % GameData.port_name(ship.research_base)
		return "idle at %s" % GameData.port_name(ship.docked_at)
	return "sailing to %s" % GameData.port_name(ship.to_port)


# --- Discoveries, research points and the journal ----------------------------------------

## A company's research record (Company.research), its parts made if missing.
static func record_of(who: Company) -> Dictionary:
	var rec := who.research
	for key: String in ["done", "revealed", "tally"]:
		if not rec.get(key) is Dictionary:
			rec[key] = {}
	return rec


static func is_done(who: Company, site_id: String) -> bool:
	return who != null and (record_of(who).done as Dictionary).has(site_id)


## Whether a company knows where a site is: famous ones from the start, the rest once revealed or done.
static func is_known(who: Company, site_id: String) -> bool:
	if bool(site(site_id).get("famous", false)):
		return true
	return who != null and ((record_of(who).revealed as Dictionary).has(site_id) or is_done(who, site_id))


## A hidden site's search area: its middle, off the site itself by the same
## amount every time (so the area doesn't give the spot away).
static func hint_lonlat(site_id: String) -> Vector2:
	var each := site(site_id)
	var seed := absi(site_id.hash())
	var angle := float(seed % 360) * PI / 180.0
	var away := float(setting("hint_nm", 260)) * (0.15 + float((seed / 360) % 30) / 100.0) / 60.0
	var lat := float(each.get("lat", 0)) + sin(angle) * away
	var lon := float(each.get("lon", 0)) + cos(angle) * away / maxf(cos(deg_to_rad(lat)), 0.2)
	return Vector2(wrapf(lon, -180.0, 180.0), clampf(lat, -85.0, 85.0))


## Research points a second a model earns on an expedition: points_per_minute
## for a tier 1 ship, doubling with each tier.
static func points_rate(model: Dictionary) -> float:
	return float(setting("points_per_minute", 1.0)) * pow(2.0, int(model.get("tier", 1)) - 1) / 60.0


## Banks research points for a ship's company.
func earn_points(ship: Ship, points: float) -> void:
	if points > 0.0:
		_state.owner_of(ship).research_points += points


## A site finished by a company's ship: into its journal (the first company's
## too), research points for the trip, the sites near it revealed.
func discover(who: Company, site_id: String, ship: Ship) -> void:
	var rec := record_of(who)
	var again := (rec.done as Dictionary).has(site_id)
	var first := not firsts.has(site_id)
	if first:
		firsts[site_id] = _index_of(who)
	if not again:
		rec.done[site_id] = {day = today(), first = first, ship = ship.name if ship != null else ""}
		(rec.revealed as Dictionary).erase(site_id)
		_tally(who, "discoveries", 1.0 + float(site(site_id).get("difficulty", 1)) * 0.25)
	var points := 0.0
	if ship != null:
		var each := site(site_id)
		points = points_rate(ship.model()) * maxf(_state.play_time - ship.research_since, 60.0) * (0.8 + 0.2 * float(each.get("difficulty", 1)))
		if first:
			points *= 1.0 + float(setting("first_bonus", 0.5))
		if ship.research_gear.has("sub"):
			points *= 1.5
		if ship.research_gear.has("film"):
			points *= 1.1
		if again:
			points *= 0.25
		earn_points(ship, points)
	reveal_near(who, target_lonlat(end_of(site_id)), float(setting("reveal_nm", 450)))
	if not again:
		for each_ship: Ship in _state.fleet(who):
			each_ship.invalidate_stats()  # (Its perks may have stepped up: see perk().)
	discovered.emit(who, site_id, first and not again, ship, points)
	if ship != null:
		_state.research_discovered.emit(ship, site_id, first and not again, points)
	_changed()


## Reveals the hidden sites within nm of a place to a company.
func reveal_near(who: Company, lonlat: Vector2, nm: float) -> void:
	var found := []
	for site_id: String in site_ids():
		if is_known(who, site_id):
			continue
		var each := site(site_id)
		if nm_between(lonlat, Vector2(float(each.lon), float(each.lat))) <= nm:
			record_of(who).revealed[site_id] = true
			found.append(site_id)
	if not found.is_empty():
		revealed.emit(who, found)
		_changed()


## [done, total] of a category's sites (all, with "").
static func progress(who: Company, category_id := "") -> Array:
	var done := 0
	var total := 0
	for site_id: String in site_ids():
		if not category_id.is_empty() and str(site(site_id).category) != category_id:
			continue
		total += 1
		if is_done(who, site_id):
			done += 1
	return [done, total]


## How many of a category's perk steps a company has reached (0 to 3).
static func perk_step(who: Company, category_id: String) -> int:
	var counts := progress(who, category_id)
	var share := 100.0 * float(counts[0]) / maxf(float(counts[1]), 1.0)
	var step := 0
	for threshold: float in setting("perk_steps", [25, 50, 100]):
		if share >= threshold - 0.001:
			step += 1
	return step


## The multiplier a company's research perks put on a stat ("wages", "fuel",
## "speed", "wear", "breakdowns", "repairs", "fees", "price", "catch"): 1 with none.
static func perk(who: Company, stat: String) -> float:
	if who == null or who.research.is_empty():
		return 1.0
	var done: int = (who.research.get("done", {}) as Dictionary).size()
	var key := who.get_instance_id()
	var cached: Array = _perk_cache.get(key, [-1, {}])
	if int(cached[0]) != done:
		var perks := {}
		for each: Dictionary in categories():
			var step := perk_step(who, each.id)
			if step > 0:
				var info: Dictionary = each.perk
				perks[info.stat] = float(perks.get(info.stat, 1.0)) + float(info.steps[step - 1])
		cached = [done, perks]
		_perk_cache[key] = cached
	return float(cached[1].get(stat, 1.0))


## A fishing ground's catch for a company: its Reefs perk, and more where it
## has surveyed a wreck, reef, seamount or relic within catch_nm of the ground.
static func catch_factor(who: Company, ground_id: String) -> float:
	var factor := perk(who, "catch")
	if who == null or who.research.is_empty():
		return factor
	var locals: Dictionary = setting("local_perks", {})
	var near := _near(who, "catch", "@" + ground_id, float(locals.get("catch_nm", 400)), locals.get("catch_categories", []))
	return factor * (1.0 + (float(locals.get("catch", 0.25)) if near > 0 else 0.0))


## How many sites a company has surveyed near a port, for its Expedition cruises' sights.
static func sights_near(who: Company, port_id: String) -> int:
	if who == null or who.research.is_empty():
		return 0
	var locals: Dictionary = setting("local_perks", {})
	return _near(who, "cruise", port_id, float(locals.get("cruise_nm", 350)), locals.get("cruise_categories", []))


static func _near(who: Company, what: String, place: String, nm: float, kinds: Array) -> int:
	var done: Dictionary = who.research.get("done", {})
	var key := "%d|%s|%s" % [who.get_instance_id(), what, place]
	var cached: Array = _near_cache.get(key, [-1, 0])
	if int(cached[0]) == done.size():
		return int(cached[1])
	var port := GameData.get_port(place)
	var here := Vector2(float(port.get("lon", 0)), float(port.get("lat", 0)))
	var count := 0
	for site_id: String in done:
		var each := site(site_id)
		if kinds.has(str(each.get("category", ""))) and nm_between(here, Vector2(float(each.lon), float(each.lat))) <= nm:
			count += 1
	_near_cache[key] = [done.size(), count]
	return count


# --- Contracts ------------------------------------------------------------------------------

func offer_by_id(contract_id: int) -> Dictionary:
	for offer: Dictionary in board:
		if int(offer.id) == contract_id:
			return offer
	return {}


## A company's taken contracts.
func taken_by(who: Company) -> Array:
	var index := _index_of(who)
	return board.filter(func(offer: Dictionary) -> bool: return int(offer.taken_by) == index)


func max_open(who: Company) -> int:
	var ships: int = _state.fleet(who).filter(func(ship: Ship) -> bool: return ship.is_research()).size()
	return OPEN_BASE + ships / 2


## The cheapest research model that could do a target: deep enough and able
## to fit its needs (a crewed sub only on a mothership), or {}.
static func cheapest_for(depth: int, needs: Array) -> Dictionary:
	var best := {}
	for model: Dictionary in GameData.ship_models:
		if not is_research_model(model) or depth_of(model) < depth:
			continue
		if not needs.all(func(gear_id: String) -> bool: return can_fit(model, gear_id)):
			continue
		if best.is_empty() or int(model.get("price", 0)) < int(best.get("price", 0)):
			best = model
	return best


## Its tier (1 to 5).
static func tier_needed(depth: int, needs: Array) -> int:
	return int(cheapest_for(depth, needs).get("tier", 5))


## Why a company can't take a contract, or "".
func accept_error(who: Company, contract_id: int) -> String:
	var offer := offer_by_id(contract_id)
	if offer.is_empty():
		return "That contract has gone."
	if int(offer.taken_by) >= 0:
		return "Someone has already taken it."
	if not can_research(who):
		return "Only Research companies take contracts."
	if taken_by(who).size() >= max_open(who):
		return "You hold %d contracts already: finish one first (more with more research ships)." % max_open(who)
	return ""


func accept(who: Company, contract_id: int) -> bool:
	if not accept_error(who, contract_id).is_empty():
		return false
	var offer := offer_by_id(contract_id)
	offer.taken_by = _index_of(who)
	offer.due = today() + int(offer.deadline)
	if not str(offer.site).is_empty() and not is_known(who, offer.site):
		record_of(who).revealed[offer.site] = true
		revealed.emit(who, [offer.site])
	_changed()
	return true


## Gives a taken contract up: it fails (its penalty paid).
func abandon(who: Company, contract_id: int) -> void:
	var offer := offer_by_id(contract_id)
	if offer.is_empty() or int(offer.taken_by) != _index_of(who):
		return
	_fail_contract(who, offer)


func _finish_contract(who: Company, offer: Dictionary, ship: Ship) -> void:
	var pay := int(offer.pay)
	var ok := true
	if str(offer.kind) == "documentary" and ship.research_gear.has("film"):
		pay = roundi(pay * 1.5)
	if _rng.randf() < float(kind(str(offer.kind)).get("fail", 0.0)):
		pay = roundi(pay * 0.25)  # (A salvage that brought up only a little.)
		ok = false
		_mishap(ship, "recovered only part of what was down there")
	_state._add_money(who, pay)
	_state._record(ship, "research_pay", pay, who)
	earn_points(ship, points_rate(ship.model()) * maxf(_state.play_time - ship.research_since, 60.0) * 0.5)
	_tally(who, "contracts", 1.0)
	_tally(who, "on_time", 1.0 if ok else 0.5)
	board.erase(offer)
	contract_finished.emit(who, offer, true, pay)
	_changed()


func _fail_contract(who: Company, offer: Dictionary) -> void:
	var penalty := roundi(float(offer.pay) * float(setting("penalty", 0.1)))
	_state._add_money(who, -penalty)
	_state._record(null, "research_penalty", penalty, who)
	_tally(who, "contracts", 1.0)
	_tally(who, "failed", 1.0)
	board.erase(offer)
	for ship: Ship in _state.fleet(who):
		if ship.research_contract == int(offer.id):
			ship.research_contract = 0
			if not is_site_end(ship.research_target) and ship.job_phase != Ship.JOB_RESEARCH:
				ship.research_target = ""
	contract_finished.emit(who, offer, false, penalty)
	_changed()


## New offers for the board, up to board_size untaken.
func _fill_board(all := false) -> void:
	var open := board.filter(func(offer: Dictionary) -> bool: return int(offer.taken_by) < 0).size()
	var room := int(setting("board_size", 14)) - open
	for i in (room if all else mini(room, 4)):
		var offer := _make_offer()
		if not offer.is_empty():
			board.append(offer)


func _make_offer() -> Dictionary:
	var kinds := ["science", "science", "industry", "industry", "salvage", "documentary", "search"]
	for attempt in 12:
		var kind_id: String = kinds[_rng.randi() % kinds.size()]
		var offer := _offer_for(kind_id)
		if not offer.is_empty() and reachable(str(offer.target)):
			return offer
	return {}


func _offer_for(kind_id: String) -> Dictionary:
	var info := kind(kind_id)
	var clients: Array = info.get("clients", ["A client"])
	var offer := {id = next_id, kind = kind_id, client = clients[_rng.randi() % clients.size()], site = "", target = "", title = "",
		posted = today(), expires = today() + int(setting("expire_days", 40)), taken_by = -1, due = -1}
	var site_id := ""
	match kind_id:
		"industry":
			var targets := []
			for field_id: String in Energy.field_ids():
				targets.append(Energy.end_of(field_id))
			for ground_id: String in Fisheries.shared().ground_order:
				targets.append("@" + ground_id)
			if targets.is_empty():
				return {}
			var end: String = targets[_rng.randi() % targets.size()]
			var works := ["Cable route survey", "Wind farm site survey", "Pipeline route survey", "Seabed survey"] if not Energy.is_field_end(end) \
				else ["Seabed survey", "Pipeline route survey", "Rig site survey"]
			offer.target = end
			offer.title = "%s: %s" % [works[_rng.randi() % works.size()], target_name(end)]
			offer.needs = ["sonar"] if _rng.randf() < 0.6 else ["sonar", "lab"]
			offer.depth = 200
			offer.days = 12.0
			offer.difficulty = 1
		_:
			var pool := site_ids().filter(func(id: String) -> bool:
				var each := site(id)
				var category_id := str(each.category)
				match kind_id:
					"science": return category_id in ["trench", "vent", "seamount", "reef", "canyon", "wildlife"]
					"salvage": return category_id in ["wreck", "relic", "ruins"]
					"documentary": return bool(each.get("famous", false))
					"search": return not bool(each.get("famous", false))
				return false)
			if pool.is_empty():
				return {}
			site_id = pool[_rng.randi() % pool.size()]
			var each := site(site_id)
			offer.site = site_id
			offer.target = end_of(site_id)
			var verbs := {science = ["Survey", "Sample", "Map", "Study"], salvage = ["Recover artefacts from", "Salvage", "Raise finds from"],
				documentary = ["Film", "Film a documentary at"], search = ["Search for"]}
			var list: Array = verbs[kind_id]
			offer.title = "%s %s" % [list[_rng.randi() % list.size()], str(each.name)]
			offer.needs = (each.needs as Array).duplicate()
			if kind_id == "science" and str(each.category) in ["vent", "reef"] and not offer.needs.has("lab"):
				offer.needs.append("lab")
			offer.depth = int(each.depth_m)
			offer.days = float(each.days) + (2.0 if kind_id == "salvage" else 0.0)
			offer.difficulty = int(each.get("difficulty", 1))
	var cheapest := cheapest_for(int(offer.depth), offer.needs)
	var tier := int(cheapest.get("tier", 5))
	var pay := float(cheapest.get("price", 1000000)) * float(setting("pay_rate", 0.03)) * (float(offer.days) + 32.0) * float(info.get("pay", 1.0)) * (0.8 + 0.1 * float(offer.difficulty)) * _rng.randf_range(0.9, 1.15)
	offer.pay = _round_2(pay)
	offer.tier = tier
	offer.deadline = int(setting("deadline_days", 30)) + roundi(float(offer.days) * 2.0)
	next_id += 1
	return offer


# --- The days -------------------------------------------------------------------------------

func today() -> int:
	return floori((_state.calendar_time() - _state.calendar_time_at(0.0)) / DAY_S)


func step(_delta: float) -> void:
	if Net.role == Net.Role.CLIENT:
		return
	var now := today()
	if day < 0:
		day = now
		_fill_board(true)
		_changed()
		return
	var ran := 0
	while day < now and ran < 4:
		day += 1
		ran += 1
		_run_day()
	if ran > 0:
		_changed()


func _run_day() -> void:
	for who: Company in _state.all_companies():
		if who.research.is_empty():
			continue
		var tally: Dictionary = record_of(who).tally
		for key: String in tally:
			tally[key] = float(tally[key]) * TALLY_FADE
	var all: Array[Company] = _state.all_companies()
	for offer: Dictionary in board.duplicate():
		var index := int(offer.taken_by)
		if index >= 0:
			if day > int(offer.due) and index < all.size():
				_fail_contract(all[index], offer)
		elif day > int(offer.expires):
			board.erase(offer)
	if day % maxi(int(setting("refresh_days", 4)), 1) == 0:
		_fill_board()


func _tally(who: Company, key: String, amount: float) -> void:
	if who == null:
		return
	var tally: Dictionary = record_of(who).tally
	tally[key] = float(tally.get(key, 0.0)) + amount


func _mishap(ship: Ship, what: String) -> void:
	mishap.emit(ship, what)
	_state.research_mishap.emit(ship, what)


func _index_of(who: Company) -> int:
	return _state.all_companies().find(who)


func _changed() -> void:
	version += 1
	changed.emit()


# --- The rating -------------------------------------------------------------------------------

## The Research rating's four parts (0 to 5 each, a quarter of the stars):
## Contracts (done on time against failed, and how many against the level),
## Discoveries (sites done, weighted by difficulty and firsts, against the
## level), Fleet & gear (research ships' maintenance and gear slots filled),
## Safety & reliability (failed dives, lost gear, breakdowns and losses
## against dives made). With the figures behind them.
func rating_parts(who: Company, ships: Array) -> Dictionary:
	var rec := record_of(who)
	var tally: Dictionary = rec.tally
	var since := maxf(_state.play_time - who.type_taken("research"), 0.0) / 3600.0 * 3.0  # (About 3 a hour of play, as company levels came late on.)
	var contracts := float(tally.get("contracts", 0.0))
	var on_time := float(tally.get("on_time", 0.0))
	var contract_part := 0.0
	if contracts > 0.01:
		contract_part = 5.0 * clampf(on_time / contracts, 0.0, 1.0) * clampf(contracts / 3.0, 0.0, 1.0)
	var score := 0.0
	for site_id: String in rec.done:
		var entry: Dictionary = rec.done[site_id]
		score += float(site(site_id).get("difficulty", 1)) * (2.0 if entry.get("first", false) else 1.0)
	var expected := 4.0 + float(since) * 1.5
	var discovery_part := 5.0 * clampf(score / expected, 0.0, 1.0)
	var fleet_part := 0.0
	var research_ships := ships.filter(func(ship: Ship) -> bool: return ship.is_research())
	if not research_ships.is_empty():
		var condition := 0.0
		var fitted := 0.0
		for ship: Ship in research_ships:
			condition += clampf((ship.maintenance - 0.4) / 0.55, 0.0, 1.0)
			fitted += float(ship.research_gear.size()) / maxf(float(slots_of(ship.model())), 1.0)
		fleet_part = 5.0 * (0.6 * condition + 0.4 * fitted) / research_ships.size()
	var dives := float(tally.get("dives", 0.0))
	var trouble := float(tally.get("dive_fails", 0.0)) * 0.5 + float(tally.get("gear_lost", 0.0)) * 2.0 + float(tally.get("breakdowns", 0.0)) + float(tally.get("losses", 0.0)) * 3.0
	var safety_part := 0.0
	if dives > 0.01:
		safety_part = 5.0 * clampf(1.0 - trouble / maxf(dives * 0.6, 1.0), 0.0, 1.0)
	return {parts = [contract_part, discovery_part, fleet_part, safety_part],
		figures = {contracts = contracts, on_time = on_time, failed = float(tally.get("failed", 0.0)), score = score, expected = expected,
			sites = (rec.done as Dictionary).size(), ships = research_ships.size(), dives = dives, trouble = trouble}}


# --- State --------------------------------------------------------------------------------------

func reset() -> void:
	board.clear()
	firsts.clear()
	next_id = 1
	day = -1
	_perk_cache.clear()
	_near_cache.clear()
	version += 1


func to_dict() -> Dictionary:
	return {board = board, firsts = firsts, next_id = next_id, day = day}


func from_dict(saved: Dictionary) -> void:
	board = saved.get("board", []) if saved.get("board") is Array else []
	for offer: Dictionary in board:
		offer.id = int(offer.get("id", 0))
		offer.taken_by = int(offer.get("taken_by", -1))
		offer.due = int(offer.get("due", -1))
	firsts = {}
	var saved_firsts: Variant = saved.get("firsts", {})
	if saved_firsts is Dictionary:
		for site_id: String in saved_firsts:
			firsts[site_id] = int(saved_firsts[site_id])
	next_id = int(saved.get("next_id", 1))
	day = int(saved.get("day", -1))
	_perk_cache.clear()
	_near_cache.clear()
	version += 1
	changed.emit()

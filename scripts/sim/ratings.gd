# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Ratings
extends RefCounted
## Every company's star rating (0 to 5) in each company type it has
## (Company.ratings), worked out from a sample a minute of play (SAMPLE_S) over
## the last WINDOW samples (about 2 hours), the stars the window's average with
## the minutes not yet on record counting as nothing: a type taken new starts
## at 0 and earns its stars as it runs (a save from before ratings fills its
## window with its first sample instead, so nothing drops).
##
## A cruise line's sample has four parts, a quarter each (Cruises.rating_parts():
## guest experience, itinerary, reliability & safety, value & reviews). A cargo
## type's has three, a third of the stars each:
## - Condition: its ships' maintenance (from 40% up to 95%), the share of
##   their upgrade points spent, and the mega upgrades of its models;
## - Reliability: ships standing idle (paused, held, no route or lost),
##   departures with an empty hold, and breakdowns and losses (a loss counts 3);
## - Scale & reach: its ships against what its slots allow at the company's
##   level, the ports it has traded at lately against what that level
##   expects, and the company's hubs against its hub slots.
## The stars change what its ships' cargo sells for, the port fees on it and
## the XP it earns (EFFECTS: nothing at 2.5 stars, the most at 0 and 5). Each
## whole star gained or lost is announced (GameState.rating_changed).

const SAMPLE_S := 60.0
const WINDOW := 120
## How long a port counts as served after the type last traded there (s of play).
const PORT_MEMORY_S := 1800.0
## At 5 stars (and the opposite at 0): sale prices, port fees, XP.
const EFFECTS := {price = 0.05, fees = -0.2, xp = 0.1}
const PART_NAMES := ["Condition", "Reliability", "Scale & reach"]
const CRUISE_PART_NAMES := ["Guest experience", "Itinerary", "Reliability & safety", "Value & reviews"]

var _state: Node
var _clock := 0.0
## Events since the last sample: Company -> {type id: {departures, empty, breakdowns, losses}}.
var _events := {}
## The figures behind each part's latest sample: Company -> {type id: {...}}.
var details := {}
## Stars as last worked out: Company -> {type id: [key, stars]}.
var _stars := {}


func _init(state: Node) -> void:
	_state = state


## Hooks the game's events (GameState, once its signals exist).
func connect_signals() -> void:
	_state.ship_departed.connect(func(ship: Ship, _port: String, _sale: int, _fuel: int, _repair: int, _toll: int) -> void:
		if not ship.is_service() and not ship.is_cruise() and ship.has_route():
			var tally := _tally(ship)
			if not tally.is_empty():
				tally.departures = int(tally.get("departures", 0)) + 1
				if ship.cargo_id.is_empty() or ship.cargo_qty <= 0:
					tally.empty = int(tally.get("empty", 0)) + 1)
	_state.ship_broke_down.connect(func(ship: Ship) -> void:
		var tally := _tally(ship)
		if not tally.is_empty():
			tally.breakdowns = int(tally.get("breakdowns", 0)) + 1)
	_state.ship_lost.connect(func(ship: Ship) -> void:
		var tally := _tally(ship)
		if not tally.is_empty():
			tally.losses = int(tally.get("losses", 0)) + 1)
	_state.cargo_sold.connect(func(ship: Ship, port_id: String, _c: String, _q: int, _cost: int, _sale: int, _t: int, _f: int) -> void: _served(ship, port_id))
	_state.cargo_loaded.connect(func(ship: Ship, port_id: String, _c: String, _q: int, _cost: int, _to: String) -> void: _served(ship, port_id))
	_state.catch_landed.connect(func(ship: Ship, port_id: String, _s: String, _crates: int, _v: int, _stored: bool) -> void: _served(ship, port_id))


func reset() -> void:
	_clock = 0.0
	_events.clear()
	details.clear()
	_stars.clear()


func step(delta: float) -> void:
	_clock += delta
	if _clock < SAMPLE_S:
		return
	_clock -= SAMPLE_S
	for company: Company in _state.all_companies():
		sample(company)
	_events.clear()


## The types a company is rated in: those it has (every type for a company from
## before types).
static func rated_types(company: Company) -> Array:
	var out := []
	for type: Dictionary in Progression.company_types():
		if company.has_type(type.id):
			out.append(type.id)
	return out


## The parts a type's rating is made of (Cruises has its own four).
static func part_names(type_id: String) -> Array:
	return CRUISE_PART_NAMES if type_id == "cruises" else PART_NAMES


## A company's stars in a type (0 to 5): its window's average.
func stars(company: Company, type_id: String) -> float:
	if company == null or type_id.is_empty():
		return 2.5
	var entry: Dictionary = company.ratings.get(type_id, {})
	var samples: Array = entry.get("samples", [])
	var key := [samples.size(), samples.back() if not samples.is_empty() else null]
	var kept: Array = (_stars.get_or_add(company, {}) as Dictionary).get(type_id, [])
	if not kept.is_empty() and kept[0] == key:
		return kept[1]
	var total := 0.0
	for sample: Array in samples:
		var sum := 0.0
		for part: Variant in sample:
			sum += float(part)
		total += sum / maxf(sample.size(), 1.0)
	var value := clampf(total / WINDOW, 0.0, 5.0)
	_stars[company][type_id] = [key, value]
	return value


## Each part's stars (0 to 5) over the samples on record (none yet: 0).
func part_stars(company: Company, type_id: String) -> Array:
	var samples: Array = company.ratings.get(type_id, {}).get("samples", [])
	var parts := []
	parts.resize(part_names(type_id).size())
	parts.fill(0.0)
	for sample: Array in samples:
		for i in mini(sample.size(), parts.size()):
			parts[i] += float(sample[i])
	return parts.map(func(total: float) -> float: return total / maxf(samples.size(), 1.0))


## How many minutes of a type's window are on record (WINDOW when full).
func minutes_on_record(company: Company, type_id: String) -> int:
	return (company.ratings.get(type_id, {}).get("samples", []) as Array).size()


## A rating effect's factor for a company's type ("price", "fees" or "xp"):
## 1 at 2.5 stars, 1 + EFFECTS at 5, 1 - EFFECTS at 0. 1 for no type.
func factor(company: Company, type_id: String, effect: String) -> float:
	if company == null or type_id.is_empty() or not company.has_type(type_id):
		return 1.0
	return 1.0 + float(EFFECTS[effect]) * (stars(company, type_id) - 2.5) / 2.5


## Takes a sample of each of a company's types, announcing whole stars gained or lost.
func sample(company: Company) -> void:
	var level := company.level()
	var fleet: Array[Ship] = _state.fleet(company)
	var events: Dictionary = _events.get(company, {})
	for type_id: String in rated_types(company):
		var entry: Dictionary = company.ratings.get_or_add(type_id, {samples = [], ports = {}, star = 0})
		var ships := fleet.filter(func(ship: Ship) -> bool: return Progression.type_of_model(ship.model()) == type_id)
		var figures: Dictionary
		var sample: Array
		if type_id == "cruises":  # (Its own four parts: see Cruises.rating_parts().)
			var cruise := (_state.cruises as Cruises).rating_parts(company, ships)
			figures = cruise.figures
			sample = (cruise.parts as Array).map(func(part: float) -> float: return snappedf(part, 0.01))
		else:
			figures = _figures(company, type_id, ships, events.get(type_id, {}), entry, level)
			sample = [snappedf(figures.condition, 0.01), snappedf(figures.reliability, 0.01), snappedf(figures.scale, 0.01)]
		(details.get_or_add(company, {}) as Dictionary)[type_id] = figures
		var samples: Array = entry.samples
		if company.ratings_seed and samples.is_empty():
			for i in WINDOW:  # (A save from before ratings: its first sample stands for the whole window.)
				samples.append(sample.duplicate())
		else:
			samples.append(sample)
		while samples.size() > WINDOW:
			samples.pop_front()
		var star := floori(stars(company, type_id))
		if company.ratings_seed:
			entry.star = star  # (Where a save from before ratings stands: nothing to announce.)
		elif star != int(entry.get("star", 0)):
			var up := star > int(entry.get("star", 0))
			entry.star = star
			_state.rating_changed.emit(company, type_id, star, up)
	company.ratings_seed = false


## The figures behind a type's sample, each part 0 to 5.
func _figures(company: Company, type_id: String, ships: Array, events: Dictionary, entry: Dictionary, level: int) -> Dictionary:
	var n := ships.size()
	var maintenance := 0.0
	var spent := 0
	var unspent := 0
	var idle := 0
	var models := {}
	for ship: Ship in ships:
		maintenance += ship.maintenance
		unspent += ship.skill_points()
		spent += int(ship.skills.speed) + int(ship.skills.durability) + int(ship.skills.efficiency) + int(ship.skills.get("range", 0))
		idle += 0 if ship.is_active() else 1
		models[ship.model_id] = true
	maintenance /= maxf(n, 1.0)
	var upgrades := float(spent) / maxf(spent + unspent, 1.0) if spent + unspent > 0 else 1.0
	var megas := models.keys().filter(func(id: String) -> bool: return company.has_mega(id)).size()
	var mega := float(megas) / maxf(models.size(), 1.0)
	var condition := 0.0 if n == 0 else 5.0 * (0.6 * clampf((maintenance - 0.4) / 0.55, 0.0, 1.0) + 0.3 * upgrades + 0.1 * mega)
	var departures := int(events.get("departures", 0))
	var empty_share := float(events.get("empty", 0)) / departures if departures > 0 else 0.0
	var incidents := int(events.get("breakdowns", 0)) + 3 * int(events.get("losses", 0))
	var incident_share := minf(incidents * 10.0 / maxf(n, 1.0), 1.0)
	var idle_share := float(idle) / maxf(n, 1.0)
	var reliability := 0.0 if n == 0 else 5.0 * (1.0 - (0.4 * idle_share + 0.3 * empty_share + 0.3 * incident_share))
	var slots := 0
	for model: Dictionary in GameData.ship_models:
		if Progression.type_of_model(model) == type_id:
			slots += Progression.model_slots(model, level, company)
	var expected_ships := maxf(1.0, 0.4 * slots)
	var ports: Dictionary = entry.get("ports", {})
	for port_id: String in ports.keys():
		if _state.play_time - float(ports[port_id]) > PORT_MEMORY_S:
			ports.erase(port_id)
	var expected_ports := minf(3.0 + level * 0.4, 40.0)
	var hub_slots := Progression.hub_slots(level)
	var scale := 5.0 * (0.5 * minf(n / expected_ships, 1.0) + 0.35 * minf(ports.size() / expected_ports, 1.0) + 0.15 * minf(float(company.hubs.size()) / hub_slots, 1.0))
	return {condition = clampf(condition, 0.0, 5.0), reliability = clampf(reliability, 0.0, 5.0), scale = clampf(scale, 0.0, 5.0),
		ships = n, maintenance = maintenance, upgrades = upgrades, mega = mega, megas = megas, models = models.size(),
		idle = idle, departures = departures, empty = int(events.get("empty", 0)), breakdowns = int(events.get("breakdowns", 0)),
		losses = int(events.get("losses", 0)), expected_ships = expected_ships, ports = ports.size(), expected_ports = expected_ports,
		hubs = company.hubs.size(), hub_slots = hub_slots}


## This minute's event tally for a ship's company and type ({} for a ship outside the types).
func _tally(ship: Ship) -> Dictionary:
	var type_id := Progression.type_of_model(ship.model())
	if type_id.is_empty():
		return {}
	var by_type: Dictionary = _events.get_or_add(_state.owner_of(ship), {})
	return by_type.get_or_add(type_id, {})


## Notes that a ship's type traded at a port (for Scale & reach).
func _served(ship: Ship, port_id: String) -> void:
	var type_id := Progression.type_of_model(ship.model())
	var who: Company = _state.owner_of(ship)
	if type_id.is_empty() or not who.has_type(type_id):
		return
	var entry: Dictionary = who.ratings.get_or_add(type_id, {samples = [], ports = {}, star = 0})
	(entry.get_or_add("ports", {}) as Dictionary)[port_id] = _state.play_time

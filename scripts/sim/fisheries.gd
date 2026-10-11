# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Fisheries
extends RefCounted
## Fishing and crabbing (data/fisheries.json): the seafood families (the
## commodities the catch is landed as, in crates of 25 kg), the species and
## the gear each is caught with, and the grounds where they're caught, in
## their seasons. Each ground is reached along its own sea lanes: one from
## each of its nearest ports out to its middle (keyed "PORT-@ground" with the
## rest: tools/build_map_data.gd --fishing-only), so a trip is the lane from
## a boat's base to one of those ports and out along it. A boat's options are the grounds and species its gear and
## size can work, within its reach of its base; its best is what pays most a
## day in this month's seasons, with the stocks as they are.
##
## Stocks (GameState.fish_stocks, "ground>species" -> share of the most the
## ground holds) are drawn down by each boat's catch and grow back over the
## year: a fished-out ground catches less.

const PATH := "res://data/fisheries.json"
## Calendar seconds a day, and the share of a boat's fuel burn while it works
## a ground (hauling pots, towing nets and trolling, drifting between).
const DAY_S := 86400.0
const WORK_FUEL := 0.35
## How a ground's stock grows back: the share of what's missing a year.
const REGROW_A_YEAR := 1.6
## The catch thins as a stock falls (catch x stock^STOCK_POWER).
const STOCK_POWER := 0.7
## Wear while working rough seas in their months (the Bering Sea in winter).
const ROUGH_WEAR := 2.2
const TROPHY_ODDS_FLOOR := 0.0

static var _shared: Fisheries = null

var families := {}  # id -> {id, name, kind, base, color}
var family_order: Array[String] = []
var species := {}  # id -> {name, latin, family, gear, grade, trophy}
var grounds := {}  # id -> {id, name, lon, lat, radius_nm, depth, rough_months, stock_t, species: {id: {months, density}}, ports: the ports its lanes run from}
var ground_order: Array[String] = []


static func shared() -> Fisheries:
	if _shared == null:
		_shared = Fisheries.new()
		_shared._load()
	return _shared


func _load() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		push_error("Fisheries: could not read %s" % PATH)
		return
	for family: Dictionary in parsed.get("families", []):
		families[family.id] = family
		family_order.append(str(family.id))
	species = parsed.get("species", {})
	var lanes := GameData.fishing_lanes()  # "@ground" -> [ports]
	for ground: Dictionary in parsed.get("grounds", []):
		ground.ports = lanes.get("@" + str(ground.id), [])
		grounds[ground.id] = ground
		ground_order.append(str(ground.id))


## A ground's end of its lanes, as a port id ("@bristol_bay"), and back.
static func end_of(ground_id: String) -> String:
	return "@" + ground_id

static func is_ground(port_id: String) -> bool:
	return port_id.begins_with("@")


## True if a commodity is a seafood family.
func is_seafood(commodity_id: String) -> bool:
	return families.has(commodity_id)


## A species' name ("Red king crab"), or its id.
func species_name(species_id: String) -> String:
	return str((species.get(species_id, {}) as Dictionary).get("name", species_id))


## A species' name inside a sentence ("trolling for japanese sea bass" no:
## "for Japanese sea bass", "for snow crab"): its first letter lower case
## unless its first word is a name (Atlantic, Japanese, Alaska...).
func species_word(species_id: String) -> String:
	var name := species_name(species_id)
	if name.get_slice(" ", 0) in PROPER_WORDS:
		return name
	return name.left(1).to_lower() + name.substr(1)

## First words of species names that keep their capital in a sentence.
const PROPER_WORDS := ["Atlantic", "Pacific", "Arctic", "Antarctic", "Alaska", "Japanese", "Australian", "European", "Spanish", "Peruvian",
	"Dungeness", "Jonah", "Tanner", "Tasmanian", "Florida", "Chinook", "Coho", "Sockeye"]


## The family (commodity) a species is landed as.
func family_of(species_id: String) -> String:
	return str((species.get(species_id, {}) as Dictionary).get("family", ""))


## True if a ground's species is in season in a month (0-11).
func in_season(ground_id: String, species_id: String, month: int) -> bool:
	var entry: Dictionary = (grounds.get(ground_id, {}).get("species", {}) as Dictionary).get(species_id, {})
	return not entry.is_empty() and (entry.months as Array).has(float(month + 1))


## The months (1-12) a ground's species is in season.
func season(ground_id: String, species_id: String) -> Array:
	return ((grounds.get(ground_id, {}).get("species", {}) as Dictionary).get(species_id, {}) as Dictionary).get("months", [])


## Its season in words: "October to January", "all year".
func season_text(ground_id: String, species_id: String) -> String:
	var months := season(ground_id, species_id)
	if months.size() >= 12:
		return "all year"
	if months.is_empty():
		return "never"
	var names := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	# The runs of months, each from its first to its last (a run may wrap the year).
	var have := {}
	for m: float in months:
		have[int(m)] = true
	var runs := []
	for m in range(1, 13):
		if have.has(m) and not have.has((m + 10) % 12 + 1):
			var end := m
			while have.has(end % 12 + 1) and end % 12 + 1 != m:
				end = end % 12 + 1
			runs.append(names[m - 1] if end == m else "%s to %s" % [names[m - 1], names[end - 1]])
	return " and ".join(runs)


## True if a ground's seas are rough in a month (0-11).
func rough(ground_id: String, month: int) -> bool:
	return (grounds.get(ground_id, {}).get("rough_months", []) as Array).has(float(month + 1))


## A boat model's fishing (ship_models.json fishing), or {}.
static func gear_of(model: Dictionary) -> Dictionary:
	return model.get("fishing", {})


## True if a boat model can work a ground's species: its gear catches it and it fishes that depth.
func can_work(model: Dictionary, ground_id: String, species_id: String) -> bool:
	var gear := gear_of(model)
	var ground: Dictionary = grounds.get(ground_id, {})
	if gear.is_empty() or ground.is_empty() or (ground.ports as Array).is_empty() or not (ground.species as Dictionary).has(species_id):
		return false
	return (gear.get("gear", []) as Array).has(str(species[species_id].gear)) and (gear.get("depth", []) as Array).has(str(ground.depth))


## Crates a day a boat model catches on a ground: its rate x how thick the
## species is there x the stock left (thinning as it falls); none out of season.
func crates_a_day(model: Dictionary, ground_id: String, species_id: String, month: int, stock: float) -> float:
	if not in_season(ground_id, species_id, month):
		return 0.0
	var density := float(grounds[ground_id].species[species_id].density)
	return float(gear_of(model).get("rate", 0.0)) * density * pow(clampf(stock, 0.0, 1.0), STOCK_POWER)


## The port a boat from `base` sets out to a ground by (one of the ports its
## lanes run from: the one making the trip shortest), and the trip's sea
## miles one way: [port, miles], or ["", INF] if there's no way.
func way_to(base: String, ground_id: String) -> Array:
	var best := ""
	var best_nm := INF
	var end := end_of(ground_id)
	for port: String in (grounds.get(ground_id, {}) as Dictionary).get("ports", []):
		if port == base:
			continue
		var nm := GameData.distance_nm(base, port, -1) + GameData.distance_nm(port, end, -1)
		if nm < best_nm:
			best_nm = nm
			best = port
	# Its own route straight out, unless going by another port is much shorter.
	var straight := GameData.distance_nm(base, end, -1)
	if straight < INF and straight <= best_nm * DIRECT_SLACK:
		return [base, straight]
	return [best, best_nm]


## How much longer (times) a boat's own route straight out to a ground may be
## than going by way of another port, and still be taken.
const DIRECT_SLACK := 1.3


## The sea miles from a port to a ground, INF if there's no way.
func miles_to(base: String, ground_id: String) -> float:
	return float(way_to(base, ground_id)[1])


## The legs out to a ground and home again, as recovery jobs sail them
## ([from, to, start_nm, end_nm] each): base to the port it sets out by, then
## that port's lane out to the ground; home, the same back.
func legs(base: String, ground_id: String) -> Array:
	var port: String = way_to(base, ground_id)[0]
	var end := end_of(ground_id)
	var out := []
	var home := []
	if base != port:
		out.append([base, port, 0.0, GameData.distance_nm(base, port, -1)])
	out.append([port, end, 0.0, GameData.distance_nm(port, end, -1)])
	home.append([end, port, 0.0, GameData.distance_nm(end, port, -1)])
	if base != port:
		home.append([port, base, 0.0, GameData.distance_nm(port, base, -1)])
	return [out, home]


## Everything a boat can go after from a base: [{ground, species, miles,
## in_season, crates_a_day, price (a crate landed at the base, this species'
## grade in), per_day (its value a day at sea, the trip there and back
## counted), season (in words)}], best first.
func options(ship: Ship, base: String, month: int, stocks: Dictionary, price_at: Callable) -> Array:
	var model := ship.model()
	var gear := gear_of(model)
	if gear.is_empty() or base.is_empty():
		return []
	var reach := float(model.get("range_nm", 0.0))
	var speed := maxf(float(model.get("speed_nm_per_s", 1.0)), 0.1)
	var hold := float(model.get("capacity", 1.0))
	var trip_days: Array = gear.get("trip_days", [3, 7])
	var day_play_s := DAY_S / maxf(GameState.calendar_seconds_per_second(), 1.0)
	var out := []
	for ground_id: String in ground_order:
		var ground: Dictionary = grounds[ground_id]
		if (ground.ports as Array).is_empty():
			continue
		var miles := miles_to(base, ground_id)
		if miles == INF or miles > reach:
			continue
		for species_id: String in ground.species:
			if not can_work(model, ground_id, species_id):
				continue
			var stock := float(stocks.get("%s>%s" % [ground_id, species_id], 1.0))
			var rate := crates_a_day(model, ground_id, species_id, month, stock)
			var price := float(price_at.call(base, family_of(species_id))) * float(species[species_id].grade)
			# A trip: there and back at sea speed, and the days working till the
			# hold's full (or the most it stays out).
			var sail_days := miles * 2.0 / speed / day_play_s
			var work_days := minf(hold / maxf(rate, 0.001), maxf(float(trip_days[1]) - sail_days, 0.5)) if rate > 0.0 else 0.0
			var crates := minf(rate * work_days, hold)
			var per_day := crates * price / maxf(sail_days + work_days, 0.25) if rate > 0.0 else 0.0
			out.append({ground = ground_id, species = species_id, miles = miles, in_season = rate > 0.0, crates_a_day = rate, price = price,
				per_day = per_day, season = season_text(ground_id, species_id), stock = stock})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.per_day > b.per_day if a.per_day != b.per_day else a.miles < b.miles)
	return out


## A boat's gear in words: "Trolls lines", "Nets and trolls lines", "30 crab pots".
static func gear_text(gear: Dictionary) -> String:
	var kinds: Array = gear.get("gear", [])
	if kinds.has("trap"):
		return "%d crab pots" % int(gear.get("traps", 0))
	var words := {troll = "trolls lines", net = "runs nets", trawl = "trawls"}
	var parts := kinds.map(func(kind: String) -> String: return str(words.get(kind, kind)))
	var text := " and ".join(parts)
	return text.left(1).to_upper() + text.substr(1)


## How long its trips run: "trips of 3 to 7 days".
static func trip_text(gear: Dictionary) -> String:
	var days: Array = gear.get("trip_days", [3, 7])
	return "trips of %d to %d days" % [int(days[0]), int(days[1])]

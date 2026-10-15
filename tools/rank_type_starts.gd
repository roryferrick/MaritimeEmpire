# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Ranks every port as an HQ for each company type but Cargo & Ore (whose
## starts are data/starts.json's) and writes data/type_starts.json: per type,
## excellent (the top 5, in 5 different market regions), great (the next 20),
## fair (the 20 after) and hard (20 of the biggest ports left where its first
## ships still clear a profit), each {port, note}. Great Lakes ports are left
## to starts.json's great_lakes, for every type. Ports a season closes (game_config
## seasons closures) can only be hard starts.
##
## A port's score: its type's first-tier ships' $ a minute (8 parts) and
## second-tier ships' (3 parts), each the best a new company there can do with
## only its home port's market region open: the best 2- or 3-port loop (as
## RivalAI works them out: cargo margins with the port fee, fuel, repairs and
## wages), or for a fishing or crabbing boat based there, the best catch in
## season averaged over the year (Fisheries.options()) less its wages. A port
## where the first-tier ships can't make money isn't offered.
##
##   Godot --headless --path . tools/rank_type_starts.tscn -- [--only cruises]

const OUT := "res://data/type_starts.json"
const TIER_WEIGHTS := {1: 8.0, 2: 3.0}
const KIND_SIZES := {excellent = 5, great = 20, fair = 20, hard = 20}

var _fake := Company.new("Ranking", "purple", "")
## With "--only a,b": just those types, merged into the file as it is.
var _only: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--only")
	if at >= 0 and at + 1 < args.size():
		_only.assign(args[at + 1].split(","))
	await get_tree().process_frame
	GameState.company = _fake
	_fake.company_types = {"cruises": 1}  # (So its cruise ratings and prices work out as a new company's.)
	GameState.companies.assign([_fake])
	GameState.market.clear()
	GameState.port_sizes.reset()
	GameState.play_time = 0.0
	var lakes: Array = GameData.starts.get("great_lakes", {}).get("ports", [])
	var kept: Dictionary = GameData.type_starts.duplicate(true) if not _only.is_empty() else {}
	var out := {"_comment": "HQ ports recommended for each company type but Cargo & Ore (data/starts.json), made by tools/rank_type_starts.tscn: see its header for how. Kinds as starts.json: excellent (5, different market regions), great (20), fair (20), hard (20 big ports with a thin profit); notes give the best first-tier run. The Great Lakes ports are starts.json's great_lakes for every type. Rerun after changing markets.json, ship models, ports, regions or fisheries."}
	var scores := {}  # type id -> [[score, port, note]]
	for type: Dictionary in Progression.company_types():
		if type.id != "cargo":
			if _only.is_empty() or _only.has(type.id):
				scores[type.id] = []
	var started := Time.get_ticks_msec()
	for port: Dictionary in GameData.ports:
		if lakes.has(port.id):
			continue
		_fake.home_port = port.id
		_fake.hubs.assign([Hub.new(port.id, true)])
		_fake.regions.assign([str(GameData.port_region(port.id).get("id", ""))])
		for type_id: String in scores:
			var scored := _score(type_id, port.id)
			if not scored.is_empty():
				(scores[type_id] as Array).append(scored)
	print("Scored %d ports in %d s" % [GameData.ports.size(), (Time.get_ticks_msec() - started) / 1000])
	for type_id: String in kept:
		if type_id != "_comment" and not scores.has(type_id):
			out[type_id] = kept[type_id]
	for type_id: String in scores:
		out[type_id] = _sort_kinds(scores[type_id])
		print("%s: %d ports make money; excellent %s" % [type_id, (scores[type_id] as Array).size(), ", ".join(out[type_id].excellent.map(func(entry: Dictionary) -> String: return "%s (%s)" % [GameData.port_name(entry.port), entry.note]))])
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(_json(out))
	file.close()
	print("Wrote ", OUT)
	get_tree().quit()


## [score, port, note] for a type's start at a port, or [] if its first ships lose money there.
func _score(type_id: String, port_id: String) -> Array:
	var score := 0.0
	var best_first := -INF
	var note := ""
	for tier: int in TIER_WEIGHTS:
		var models := CompanyTypeCards._line_models(Progression.company_type(type_id), tier)
		if models.is_empty():
			continue
		var sum := 0.0
		for model: Dictionary in models:
			var found := _fishing(model, port_id) if model.has("fishing") else (_cruising(model, port_id) if model.has("cruise") else _trading(model, port_id))
			var per_minute: float = found[0]
			sum += maxf(per_minute, 0.0)
			if tier == 1 and per_minute > best_first:
				best_first = per_minute
				note = "%s: %s (about %s a minute each)." % [_plural(str(model.name)), found[1], Fmt.money(roundi(per_minute / 100.0) * 100)]
		score += float(TIER_WEIGHTS[tier]) * sum / models.size()
	if best_first <= 0.0:
		return []
	return [score, port_id, note]


## [$ a minute, "oil to Malta, gas back"] for a cargo model's best loop from the port.
func _trading(model: Dictionary, port_id: String) -> Array:
	var loops: Array = GameState.rivals._work_out_loops(_fake, model, port_id, true)
	if loops.is_empty():
		return [-INF, ""]
	var loop: Array = loops[0][1]
	var legs := PackedStringArray()
	for i in loop.size():
		var a: String = loop[i]
		var b: String = loop[(i + 1) % loop.size()]
		var cargo: Array = GameState.market.best_cargo(model, a, b, _fake)
		var what := str(GameData.commodity(str(cargo[0])).get("name", "nothing")).to_lower() if not str(cargo[0]).is_empty() else "empty"
		legs.append("%s %s" % [what, "back" if i == loop.size() - 1 else "to " + GameData.port_name(b)])
	return [float(loops[0][0]) * 60.0, ", ".join(legs)]


## [$ a minute, "salmon off Kobe, 9 months a year"] for a fishing or crabbing
## boat based at the port: its best catch in season each month, averaged over
## the year, less its crew's wages.
func _fishing(model: Dictionary, port_id: String) -> Array:
	var boat := Ship.new("", model.id, port_id)
	boat.company = _fake
	boat.base_port = port_id
	var fish := Fisheries.shared()
	var total := 0.0
	var months := 0
	var favourite := {}
	for month in 12:
		var options: Array = fish.options(boat, port_id, month, {}, func(port: String, family: String) -> float: return GameState.company_sell_price(port, family, _fake))
		for option: Dictionary in options:
			if option.in_season:
				total += float(option.per_day)
				months += 1
				var key := "%s|%s" % [option.species, option.ground]
				favourite[key] = int(favourite.get(key, 0)) + 1
				break
	if months == 0:
		return [-INF, ""]
	var day_minutes := Fisheries.DAY_S / GameState.calendar_seconds_per_second() / 60.0
	var wages := float(GameState.crew_wages(model)) / (float(GameData.config.get("crew", {}).get("period_days", 14)) * day_minutes)
	var best_key := ""
	for key: String in favourite:
		if best_key.is_empty() or int(favourite[key]) > int(favourite[best_key]):
			best_key = key
	var parts := best_key.split("|")
	return [total / 12.0 / day_minutes - wages, "%s off %s, something in season %d months a year" % [fish.species_word(parts[0]), Fisheries.ground_name(parts[1]), months]]


## [$ a minute, "Western Med from here: 3 ports of call, 4 nights"] for a cruise
## model based at the port: the itinerary a rival would plan (RivalAI), sold
## at the recommended prices, filled from the port's would-be cruisers over
## up to 3 days (at most 90%), less its supplies, port fees, fuel and wages.
func _cruising(model: Dictionary, port_id: String) -> Array:
	var ship := Ship.new("", model.id, port_id)
	ship.company = _fake
	ship.docked_at = port_id
	ship.cruise = Cruises.default_setup(ship)
	var route: Array = GameState.rivals._cruise_itinerary(_fake, ship)
	if route.size() < 2:
		return [-INF, ""]
	ship.route.assign(route)
	var cruises: Cruises = GameState.cruises
	cruises.use_recommended(ship)
	var s := Cruises.settings()
	var nights := cruises.nights(ship)
	var trip := cruises.trip(ship)
	var day_s: float = 86400.0 / GameState.calendar_seconds_per_second()
	var capacity := Cruises.total(cruises.capacity(ship))
	var pool := float(s.get("pool_per_size", 30)) * GameState.port_sizes.size(port_id)
	var guests := minf(capacity * 0.9, pool * 3.0)
	var wait_days := clampf(guests / maxf(pool, 1.0), 1.0, 3.0)
	var ticket := 0.0
	for cls: String in Cruises.CLASSES:
		ticket += float(cruises.recommend(ship, cls, -1, false).price) * float(cruises.capacity(ship)[cls]) / maxf(capacity, 1.0)
	var income := guests * (ticket + cruises.onboard_per_guest(ship) + cruises.excursions_per_guest(ship) * 0.5)
	var costs := guests * (nights * (float(s.get("supplies_per_night", 22)) + float(s.get("entertainment_per_night", 6))) + float(s.get("port_fee_per_guest", 6)) * (route.size() - 1))
	var seconds := float(trip.seconds) + wait_days * day_s
	costs += float(model.get("fuel_per_s", 0)) * float(trip.seconds) * float(GameState.market.fuel_price(port_id))
	costs += float(GameState.crew_wages(model)) * seconds / (float(GameData.config.get("crew", {}).get("period_days", 14)) * day_s)
	var stops := PackedStringArray()
	for id: String in route.slice(1):
		stops.append(GameData.port_name(id))
	return [(income - costs) / seconds * 60.0, "%d-night cruises to %s" % [nights, ", ".join(stops)]]


## "Bunker Tankers", "Sport Fishers": a model's name made plural, its size number dropped.
static func _plural(name: String) -> String:
	var words := name.split(" ")
	if words.size() > 1 and words[-1].is_valid_int():
		words.remove_at(words.size() - 1)
	return " ".join(words) + "s"


## The scored ports as starts.json kinds, best first.
func _sort_kinds(scored: Array) -> Dictionary:
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var kinds := {excellent = [], great = [], fair = [], hard = []}
	var used := {}
	var regions := {}
	# Ports a season closes (game_config seasons closures: the Antarctic stations, the
	# icebound ports) are never better than a hard start.
	for closure: Dictionary in GameData.config.get("seasons", {}).get("closures", []):
		for port_id: String in closure.get("ports", []):
			used[port_id] = true
	var closed := used.duplicate()
	for entry: Array in scored:
		var region := str(GameData.port_region(entry[1]).get("id", ""))
		if (kinds.excellent as Array).size() < int(KIND_SIZES.excellent) and not regions.has(region) and not used.has(entry[1]):
			regions[region] = true
			used[entry[1]] = true
			kinds.excellent.append({port = entry[1], note = entry[2]})
	for kind: String in ["great", "fair"]:
		for entry: Array in scored:
			if (kinds[kind] as Array).size() >= int(KIND_SIZES[kind]):
				break
			if not used.has(entry[1]):
				used[entry[1]] = true
				kinds[kind].append({port = entry[1], note = entry[2]})
	var rest := scored.filter(func(entry: Array) -> bool: return not used.has(entry[1]) or (closed.has(entry[1]) and not _listed(kinds, entry[1])))
	rest.sort_custom(func(a: Array, b: Array) -> bool: return int(GameData.get_port(a[1]).get("rank", 999)) < int(GameData.get_port(b[1]).get("rank", 999)))
	for entry: Array in rest.slice(0, int(KIND_SIZES.hard)):
		kinds.hard.append({port = entry[1], note = entry[2]})
	return kinds


## True if a port is in one of the kinds already.
static func _listed(kinds: Dictionary, port_id: String) -> bool:
	for kind: String in kinds:
		for entry: Dictionary in kinds[kind]:
			if entry.port == port_id:
				return true
	return false


## The file as data/starts.json is laid out: a line per port.
func _json(out: Dictionary) -> String:
	var text := "{\n\t\"_comment\": %s" % JSON.stringify(out._comment)
	for type_id: String in out:
		if type_id == "_comment":
			continue
		text += ",\n\t\"%s\": {" % type_id
		var kinds: Dictionary = out[type_id]
		var first := true
		for kind: String in ["excellent", "great", "fair", "hard"]:
			text += ("" if first else ",") + "\n\t\t\"%s\": [" % kind
			first = false
			var lines := PackedStringArray()
			for entry: Dictionary in kinds[kind]:
				lines.append("\n\t\t\t{\"port\": %s, \"note\": %s}" % [JSON.stringify(entry.port), JSON.stringify(entry.note)])
			text += ",".join(lines) + "\n\t\t]"
		text += "\n\t}"
	return text + "\n}\n"

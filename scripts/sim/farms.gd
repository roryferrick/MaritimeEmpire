# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Farms
extends RefCounted
## Farms (data/farms.json), for Agriculture companies: the farm ports, their
## plots and who owns them, what each grows (a crop, or a pasture's herd),
## the harvests into each company's farm store at the port, the weather years,
## the wages, and the listings between companies. GameState owns one (its
## farms) and runs it a step at a time; its actions are GameState's (with
## their Net commands), which call the ones here for a company.
##
## Plots are keyed "PORT#n" (n from 0). The calendar runs a day at a time
## (DAY_S of calendar time): each day every planted plot in its harvest months
## gathers its share of the year's yield into its owner's store, each full
## herd's young go there too, and the store's fresh crops lose a little of
## their value. A new year draws the year after's droughts, frosts and hard
## winters (so the Farms screen can show them a year ahead).

const PATH := "res://data/farms.json"
const DAY_S := 86400.0
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
## Livestock in the store: "cows:angus" (species and breed).
const BREED_SEP := ":"
## How the harvest tallies fade (a day): the rating looks at about the last few months.
const TALLY_FADE := 0.985

static var _data := {}
static var _crops := {}
static var _breeds := {}
static var _ports := {}

## Plot key -> {owner (company index in GameState.all_companies(), -1 for the
## land's), crop ("" none), breed ("" none: a pasture has a breed and no crop),
## planted (calendar day), head (a pasture's herd), upgrades [ids], listing
## (asking price, 0 if not listed), paid (what its owner paid)}. Only plots
## ever bought are here.
var plots := {}
## Weather years: year (as a string) -> {port: "drought", "frost" or "winter"}.
var events := {}
## The calendar day last run (-1 until the first step).
var day := -1
## Counts every change (the map redraws a farm port's fields when it moves on).
var version := 0
var _state: Node


func _init(state: Node) -> void:
	_state = state


## Tells the screens (GameState.farms_changed) and the map (version) something changed.
func _changed() -> void:
	version += 1
	_state.farms_changed.emit()


# --- The data ---------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
		for crop: Dictionary in _data.get("crops", []):
			_crops[crop.id] = crop
		for breed: Dictionary in _data.get("breeds", []):
			_breeds[breed.id] = breed
		for port: Dictionary in _data.get("ports", []):
			_ports[port.port] = port
	return _data


static func settings() -> Dictionary:
	return data().get("settings", {})


static func setting(key: String, default: Variant = 0.0) -> Variant:
	return settings().get(key, default)


## The farm ports' ids, in the data's order.
static func port_ids() -> Array[String]:
	data()
	var out: Array[String] = []
	out.assign(_ports.keys())
	return out


static func is_farm_port(port_id: String) -> bool:
	data()
	return _ports.has(port_id)


## A farm port's entry: {port, climate, plots, known, blurb}, or {}.
static func port_info(port_id: String) -> Dictionary:
	data()
	return _ports.get(port_id, {})


static func climate_of(port_id: String) -> String:
	return str(port_info(port_id).get("climate", ""))


static func climate_name(climate: String) -> String:
	return str(data().get("climates", {}).get(climate, climate.capitalize()))


static func crop(crop_id: String) -> Dictionary:
	data()
	return _crops.get(crop_id, {})


static func crop_ids() -> Array[String]:
	data()
	var out: Array[String] = []
	out.assign(_crops.keys())
	return out


static func is_crop(commodity_id: String) -> bool:
	data()
	return _crops.has(commodity_id)


## True for the fruit, berries and vegetables (the Fresh produce carriers' cargo).
static func is_fresh(commodity_id: String) -> bool:
	return str(crop(commodity_id).get("kind", "")) == "fresh"


## The share of its value a commodity loses a day in the store and aboard (0 for most).
static func loses_a_day(commodity_id: String) -> float:
	return float(crop(commodity_id).get("loses_a_day", 0.0))


static func breed(breed_id: String) -> Dictionary:
	data()
	return _breeds.get(breed_id, {})


## A species' breeds (cows, sheep, pigs, horses), in the data's order.
static func breeds_of(species: String) -> Array:
	return data().get("breeds", []).filter(func(each: Dictionary) -> bool: return each.species == species)


static func species_list() -> Array[String]:
	return ["cows", "sheep", "pigs", "horses"]


static func breed_name(breed_id: String) -> String:
	return str(breed(breed_id).get("name", breed_id))


static func upgrade(upgrade_id: String) -> Dictionary:
	for each: Dictionary in data().get("upgrades", []):
		if each.id == upgrade_id:
			return each
	return {}


## How well a climate suits something that grows best in `best` (0.25 to 1).
static func fit_for(climate: String, best: Array) -> float:
	var table: Dictionary = data().get("climate_fit", {}).get(climate, {})
	var fit := 0.0
	for each: String in best:
		fit = maxf(fit, float(table.get(each, 0.25)))
	return fit if not best.is_empty() else 0.0


static func crop_fit(port_id: String, crop_id: String) -> float:
	return fit_for(climate_of(port_id), crop(crop_id).get("climates", []))


static func breed_fit(port_id: String, breed_id: String) -> float:
	return fit_for(climate_of(port_id), breed(breed_id).get("climates", []))


## A fit in words: "Ideal", "Good", "Fair", "Poor".
static func fit_text(fit: float) -> String:
	if fit >= 0.95:
		return "Ideal"
	if fit >= 0.7:
		return "Good"
	if fit >= 0.5:
		return "Fair"
	return "Poor"


static func key_of(port_id: String, index: int) -> String:
	return "%s#%d" % [port_id, index]


static func port_of(key: String) -> String:
	return key.get_slice("#", 0)


static func index_of(key: String) -> int:
	return int(key.get_slice("#", 1))


## A farm port's plot keys.
static func keys_at(port_id: String) -> Array[String]:
	var out: Array[String] = []
	for i in int(port_info(port_id).get("plots", 0)):
		out.append(key_of(port_id, i))
	return out


## A plot's fertility (fertility [min, max]): fixed by its port and place.
static func fertility(key: String) -> float:
	var range: Array = setting("fertility", [0.65, 1.3])
	var port_id := port_of(key)
	# Each port's soil a little richer or poorer, each plot its own within it.
	var port_share := _hash(port_id + "/soil")
	var plot_share := _hash(key + "/soil")
	return snappedf(lerpf(float(range[0]), float(range[1]), clampf(0.35 * port_share + 0.65 * plot_share, 0.0, 1.0)), 0.01)


## A repeatable number in [0, 1) for a string, well mixed (plot keys differ by a digit).
static func _hash(text: String) -> float:
	return text.sha1_text().substr(0, 6).hex_to_int() / 16777216.0


## The months (1-12) a crop harvests at a port: its months north of the
## equator, six months later south of it, and at a tropical port twice a year
## (six months later again) unless it's gathered all year.
static func harvest_months(port_id: String, crop_id: String) -> Array[int]:
	var months: Array[int] = []
	var south := float(GameData.get_port(port_id).get("lat", 0.0)) < 0.0
	for m: float in crop(crop_id).get("harvest", []):
		months.append(int(m) if not south else (int(m) + 5) % 12 + 1)
	if months.size() < 12 and climate_of(port_id) in ["tropical", "tropical_highland"]:
		for m: int in months.duplicate():
			var again := (m + 5) % 12 + 1
			if not months.has(again):
				months.append(again)
	months.sort()
	return months


static func months_text(months: Array) -> String:
	return Fisheries.months_text(months)


## A store item's commodity ("cows" for "cows:angus") and breed ("" for crops).
static func item_commodity(item: String) -> String:
	return item.get_slice(BREED_SEP, 0)


static func item_breed(item: String) -> String:
	return item.get_slice(BREED_SEP, 1) if item.contains(BREED_SEP) else ""


## A store item's name: "Apples", "Angus cattle".
static func item_name(item: String) -> String:
	var commodity := str(GameData.commodity(item_commodity(item)).get("name", item_commodity(item)))
	var breed_id := item_breed(item)
	if breed_id.is_empty():
		return commodity
	return "%s %s" % [breed_name(breed_id), commodity.to_lower()]


## What a breed is worth against its plain species (1 for no breed).
static func breed_value(breed_id: String) -> float:
	return float(breed(breed_id).get("value", 1.0)) if not breed_id.is_empty() else 1.0


# --- State ---------------------------------------------------------------------------

func reset() -> void:
	plots.clear()
	events.clear()
	day = -1


func to_dict() -> Dictionary:
	return {plots = plots, events = events, day = day}


func from_dict(saved: Dictionary) -> void:
	plots = saved.get("plots", {}) if saved.get("plots") is Dictionary else {}
	events = saved.get("events", {}) if saved.get("events") is Dictionary else {}
	day = int(saved.get("day", -1))
	version += 1
	for key: String in plots:
		var plot: Dictionary = plots[key]
		plot.owner = int(plot.get("owner", -1))


## A plot's state ({} for one never bought).
func plot(key: String) -> Dictionary:
	return plots.get(key, {})


## The company owning a plot, or null for the land's.
func owner_of(key: String) -> Company:
	var index := int(plot(key).get("owner", -1))
	var all: Array[Company] = _state.all_companies()
	return all[index] if index >= 0 and index < all.size() else null


func _index_of(who: Company) -> int:
	return _state.all_companies().find(who)


## A company's plots (keys), by port.
func owned_by(who: Company, port_id := "") -> Array[String]:
	var index := _index_of(who)
	var out: Array[String] = []
	for key: String in plots:
		if int(plots[key].get("owner", -1)) == index and (port_id.is_empty() or port_of(key) == port_id):
			out.append(key)
	out.sort_custom(func(a: String, b: String) -> bool: return a < b if port_of(a) != port_of(b) else index_of(a) < index_of(b))
	return out


## How many of a port's plots are owned (by anyone).
func taken_at(port_id: String) -> int:
	var count := 0
	for key in keys_at(port_id):
		if owner_of(key) != null:
			count += 1
	return count


## The most of a port's plots one company may own (max_share of them).
static func most_at(port_id: String) -> int:
	return maxi(floori(int(port_info(port_id).get("plots", 0)) * float(setting("max_share", 0.5))), 1)


## What the land asks for a plot now: plot_price from its fertility and the
## share of the port's land already taken, to the nearest $10,000.
func land_price(key: String) -> int:
	var prices: Array = setting("plot_price", [1000000, 6000000])
	var range: Array = setting("fertility", [0.65, 1.3])
	var fert := clampf(inverse_lerp(float(range[0]), float(range[1]), fertility(key)), 0.0, 1.0)
	var port_id := port_of(key)
	var taken := float(taken_at(port_id)) / maxf(int(port_info(port_id).get("plots", 1)), 1.0)
	return roundi(lerpf(float(prices[0]), float(prices[1]), 0.65 * fert + 0.35 * taken) / 10000.0) * 10000


## True if a company can farm: an Agriculture company (or one from before types).
static func can_farm(who: Company) -> bool:
	return who != null and who.has_type("agriculture")


## The calendar day now (since the calendar's start) and its date.
func today() -> int:
	return floori((_state.calendar_time() - _state.calendar_time_at(0.0)) / DAY_S)


func month_now() -> int:
	return int(Time.get_datetime_dict_from_unix_time(_state.calendar_time()).month)


func year_now() -> int:
	return int(Time.get_datetime_dict_from_unix_time(_state.calendar_time()).year)


# --- Yields ----------------------------------------------------------------------------

## A crop's climate fit at a plot with its upgrades (greenhouses lift fresh
## crops halfway to an ideal fit).
func effective_fit(key: String, crop_id: String) -> float:
	var fit := crop_fit(port_of(key), crop_id)
	if is_fresh(crop_id) and _has(key, "greenhouse"):
		fit += (1.0 - fit) * 0.5
	return fit


func _has(key: String, upgrade_id: String) -> bool:
	return (plot(key).get("upgrades", []) as Array).has(upgrade_id)


## A crop's yield a year at a plot (its units), at full bearing in a plain
## year: yield_value at its base price, times fertility, fit and upgrades.
func yield_a_year(key: String, crop_id: String) -> float:
	var base := float(GameData.commodity(crop_id).get("base", 1.0))
	var amount := float(setting("yield_value", 4000000)) / maxf(base, 1.0) * fertility(key) * effective_fit(key, crop_id)
	if _has(key, "irrigation"):
		amount *= float(setting("irrigation_yield", 1.1))
	if _has(key, "machinery"):
		amount *= float(setting("machinery_yield", 1.05))
	if is_fresh(crop_id) and _has(key, "greenhouse"):
		amount *= float(setting("greenhouse_yield", 1.25))
	return amount


## What sowing a crop costs (an annual crop each year: seed_share of a year's
## yield at its base price; an orchard once: sapling_share).
func planting_cost(key: String, crop_id: String) -> int:
	var share := float(setting("sapling_share", 0.35)) if crop(crop_id).get("orchard", false) else float(setting("seed_share", 0.08))
	return roundi(float(setting("yield_value", 4000000)) * fertility(key) * share / 1000.0) * 1000


## An orchard's bearing (0 at planting to 1 after orchard_years); 1 for annual crops once grown.
func bearing(key: String) -> float:
	var entry := plot(key)
	var crop_id := str(entry.get("crop", ""))
	var age := today() - int(entry.get("planted", 0))
	if crop(crop_id).get("orchard", false):
		return clampf(age / (365.0 * float(setting("orchard_years", 2))), 0.0, 1.0)
	return 1.0 if age >= int(setting("grow_days", 90)) else 0.0


## The head a pasture's land carries for a breed (Better grass more).
func head_room(key: String, breed_id: String) -> float:
	return float(breed(breed_id).get("head", 0)) * (float(setting("grass_head", 1.2)) if _has(key, "grass") else 1.0)


## A full herd's young a year at a plot (head), in a plain year.
func young_a_year(key: String, breed_id: String) -> float:
	return head_room(key, breed_id) * float(breed(breed_id).get("growth", 0.0)) * breed_fit(port_of(key), breed_id)


## What stocking a pasture costs at its port: the breed's herd at stock_share
## of its market value there.
func stock_cost(key: String, breed_id: String) -> int:
	var species := str(breed(breed_id).get("species", ""))
	var price: float = _state.market.sell_price(port_of(key), species) if not species.is_empty() else 0.0
	return roundi(head_room(key, breed_id) * price * breed_value(breed_id) * float(setting("stock_share", 0.2)) / 1000.0) * 1000


## A year's weather at a port: "drought", "frost", "winter" or "".
func event_at(port_id: String, year: int) -> String:
	return str(events.get(str(year), {}).get(port_id, ""))


## This year's and next year's weather at a port.
func outlook(port_id: String) -> Array[String]:
	return [event_at(port_id, year_now()), event_at(port_id, year_now() + 1)]


static func event_text(kind: String) -> String:
	return {drought = "Drought", frost = "Late frost", winter = "Hard winter"}.get(kind, "")


## What a crop's year at a plot is cut to by the year's weather (irrigation
## and greenhouses soften it).
func weather_factor(key: String, crop_id: String, year: int) -> float:
	match event_at(port_of(key), year):
		"drought":
			return float(setting("irrigated_drought_yield", 0.9)) if _has(key, "irrigation") else float(setting("drought_yield", 0.45))
		"frost":
			if is_fresh(crop_id) and not _has(key, "greenhouse"):
				return float(setting("frost_yield", 0.35))
	return 1.0


## The next harvest month (1-12) of a plot's crop from now, or 0.
func next_harvest(key: String) -> int:
	var crop_id := str(plot(key).get("crop", ""))
	if crop_id.is_empty():
		return 0
	var months := harvest_months(port_of(key), crop_id)
	var now := month_now()
	for step in 12:
		var m := (now - 1 + step) % 12 + 1
		if months.has(m):
			return m
	return 0


# --- The days ---------------------------------------------------------------------------

func step(_delta: float) -> void:
	var now := today()
	if day < 0:
		day = now
		_draw_years()
		return
	var ran := 0
	while day < now and ran < 4:  # (Fast forward: a few days a step at most, the rest the next steps.)
		day += 1
		ran += 1
		_run_day()
	if ran > 0:
		_changed()


func _run_day() -> void:
	var date := Time.get_datetime_dict_from_unix_time(_state.calendar_time_at(0.0) + day * int(DAY_S))
	var month := int(date.month)
	var year := int(date.year)
	if int(date.month) == 1 and int(date.day) == 1 or not events.has(str(year + 1)):
		_draw_years()
	var all: Array[Company] = _state.all_companies()
	for key: String in plots.keys():
		var entry: Dictionary = plots[key]
		var index := int(entry.get("owner", -1))
		if index < 0 or index >= all.size():
			continue
		var who := all[index]
		if not str(entry.get("crop", "")).is_empty():
			_grow_crop(who, key, entry, month, year)
		elif not str(entry.get("breed", "")).is_empty():
			_grow_herd(who, key, entry, year)
	for who in all:
		_age_store(who)


## A day of a crop: in its harvest months, a day's share of the year's yield
## into the store (storms over the port take most of a day's), and an annual
## crop sown again on its anniversaries.
func _grow_crop(who: Company, key: String, entry: Dictionary, month: int, year: int) -> void:
	var crop_id := str(entry.crop)
	var port_id := port_of(key)
	var age := day - int(entry.get("planted", day))
	if not crop(crop_id).get("orchard", false) and age > 0 and age % 365 == 0:
		var cost := planting_cost(key, crop_id)
		_state._add_money(who, -cost)
		_state._record(null, "farms", cost, who)
	var months := harvest_months(port_id, crop_id)
	if not months.has(month):
		return
	var share := bearing(key)
	if share <= 0.0:
		return
	var amount := yield_a_year(key, crop_id) / months.size() / 30.4 * share * weather_factor(key, crop_id, year)
	if _state.weather.active():
		var port := GameData.get_port(port_id)
		var storm: float = _state.weather.strongest_at(Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))))[1]
		if storm > 0.3:
			amount *= float(setting("storm_yield", 0.3))
	_add_to_store(who, port_id, crop_id, amount, 1.0)


## A day of a herd: short of what the land carries it grows back; full, its
## young go into the store (a hard winter and drought take some). Now and
## then an outbreak takes part of it.
func _grow_herd(who: Company, key: String, entry: Dictionary, year: int) -> void:
	var breed_id := str(entry.breed)
	var port_id := port_of(key)
	var room := head_room(key, breed_id)
	var growth := float(breed(breed_id).get("growth", 0.0)) * breed_fit(port_id, breed_id) / 365.0
	var head := float(entry.get("head", 0.0))
	var vets := _has(key, "vets")
	if randf() < float(setting("disease_odds", 0.08)) * (0.25 if vets else 1.0) / 365.0:
		var losses: Array = setting("disease_loss", [0.1, 0.3])
		var lost := head * randf_range(float(losses[0]), float(losses[1])) * (0.5 if vets else 1.0)
		entry.head = head - lost
		if who == _state.company:
			ActivityLog.add("An outbreak took %s of the %s herd at %s." % [Fmt.thousands(roundi(lost)), breed_name(breed_id), GameData.port_name(port_id)], ActivityLog.Kind.BAD)
		return
	if head < room - 0.5:
		entry.head = minf(head + head * growth * 3.0 + 1.0, room)  # (A herd short of full keeps its young: it fills back in a year or two.)
		return
	var young := room * growth
	match event_at(port_id, year):
		"winter":
			young *= 1.0 - (float(setting("barn_winter_loss", 0.05)) if _has(key, "barns") else float(setting("hard_winter_loss", 0.4)))
		"drought":
			young *= 0.6
	_add_to_store(who, port_id, str(breed(breed_id).species) + BREED_SEP + breed_id, young, 1.0)


## Adds to a company's farm store at a port: the amount at its freshness
## (mixed in with what's there).
func _add_to_store(who: Company, port_id: String, item: String, amount: float, fresh: float) -> void:
	if amount <= 0.0:
		return
	var store: Dictionary = who.farm_stores.get_or_add(port_id, {items = {}, cold = false})
	var items: Dictionary = store.get_or_add("items", {})
	var held: Array = items.get(item, [0.0, 1.0])
	var total := float(held[0]) + amount
	items[item] = [total, (float(held[0]) * float(held[1]) + amount * fresh) / total]
	var value := amount * _value_at(port_id, item, who) * fresh
	who.farm_tally.harvested = float(who.farm_tally.get("harvested", 0.0)) + value


## A store item's value a unit at a port (its breed's value in).
func _value_at(port_id: String, item: String, who: Company) -> float:
	return float(_state.company_sell_price(port_id, item_commodity(item), who)) * breed_value(item_breed(item))


## A day in a company's stores: fresh crops lose freshness (a cold store
## slows it), dry ones a little; what falls under spoiled_below is thrown away.
func _age_store(who: Company) -> void:
	for tally: String in ["harvested", "spoiled"]:
		who.farm_tally[tally] = float(who.farm_tally.get(tally, 0.0)) * TALLY_FADE
	for port_id: String in who.farm_stores.keys():
		var store: Dictionary = who.farm_stores[port_id]
		var items: Dictionary = store.get("items", {})
		for item: String in items.keys():
			if not item_breed(item).is_empty():
				continue  # (Livestock waits in the pens.)
			var held: Array = items[item]
			var loss := loses_a_day(item) if is_fresh(item) else float(setting("dry_loss_a_day", 0.002))
			if bool(store.get("cold", false)):
				loss *= float(setting("cold_store_factor", 0.25))
			held[1] = float(held[1]) - loss
			if float(held[1]) < float(setting("spoiled_below", 0.25)):
				var lost := float(held[0]) * _value_at(port_id, item, who) * float(held[1])
				who.farm_tally.spoiled = float(who.farm_tally.get("spoiled", 0.0)) + lost
				items.erase(item)
				if who == _state.company and float(held[0]) >= 1.0:
					ActivityLog.add("%s %s spoiled in your farm store at %s." % [Fmt.thousands(roundi(float(held[0]))), item_name(item).to_lower(), GameData.port_name(port_id)], ActivityLog.Kind.BAD)
			elif float(held[0]) < 0.5:
				items.erase(item)


## Draws the weather for this year (if it hasn't been) and the next: each
## farm port at most one of a drought, a late frost or a hard winter.
func _draw_years() -> void:
	var year := year_now()
	for each in [year, year + 1]:
		if events.has(str(each)):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("farm weather %d %d" % [each, _state.all_companies().size()])
		var drawn := {}
		for port_id in port_ids():
			var climate := climate_of(port_id)
			var dry := 1.5 if climate in ["arid", "mediterranean", "subtropical", "continental"] else (0.5 if climate in ["tropical", "tropical_highland"] else 1.0)
			var roll := rng.randf()
			var drought := float(setting("drought_odds", 0.06)) * dry
			var frost := float(setting("frost_odds", 0.06)) if climate in ["cool", "continental", "oceanic", "mediterranean"] else 0.0
			var winter := float(setting("hard_winter_odds", 0.15)) if climate in ["cool", "continental"] else 0.0
			if roll < drought:
				drawn[port_id] = "drought"
			elif roll < drought + frost:
				drawn[port_id] = "frost"
			elif roll < drought + frost + winter:
				drawn[port_id] = "winter"
		events[str(each)] = drawn
		if each == year + 1 and day >= 0:
			_announce(each, drawn)
	for key: String in events.keys():
		if int(key) < year - 1:
			events.erase(key)


## Tells this player of next year's weather at the farm ports where it farms.
func _announce(year: int, drawn: Dictionary) -> void:
	var mine := {}
	for key in owned_by(_state.company):
		mine[port_of(key)] = true
	for port_id: String in drawn:
		if mine.has(port_id):
			ActivityLog.add("The almanac says %s at %s next year (%d)." % [event_text(drawn[port_id]).to_lower(), GameData.port_name(port_id), year], ActivityLog.Kind.BAD)


## Farm workers' wages for a pay period: wages_per_plot for each planted plot
## or pasture (half with machinery). Called with the crews' wages.
func pay_wages() -> void:
	var all: Array[Company] = _state.all_companies()
	var paid := {}
	for key: String in plots:
		var entry: Dictionary = plots[key]
		var index := int(entry.get("owner", -1))
		if index < 0 or index >= all.size() or (str(entry.get("crop", "")).is_empty() and str(entry.get("breed", "")).is_empty()):
			continue
		var wages := float(setting("wages_per_plot", 23000)) * (0.5 if _has(key, "machinery") else 1.0)
		paid[all[index]] = float(paid.get(all[index], 0.0)) + wages
	for who: Company in paid:
		var total := roundi(paid[who])
		_state._add_money(who, -total)
		_state._record(null, "farms", total, who)


# --- Actions (a company's, through GameState) ---------------------------------------------------

## Why a company can't buy a plot from the land ("" if it can).
func buy_error(who: Company, key: String) -> String:
	var port_id := port_of(key)
	if not can_farm(who):
		return "Only Agriculture companies farm"
	if not is_farm_port(port_id) or index_of(key) >= int(port_info(port_id).get("plots", 0)):
		return "No such plot"
	if owner_of(key) != null:
		return "Owned by %s" % owner_of(key).name
	if not who.regions.is_empty() and not who.regions.has(str(GameData.port_region(port_id).get("id", ""))):
		return "Unlock %s first" % GameData.port_region(port_id).get("name", "its region")
	if owned_by(who, port_id).size() >= most_at(port_id):
		return "You can own at most %d of the %d plots here" % [most_at(port_id), int(port_info(port_id).get("plots", 0))]
	if _state.in_debt(who) or who.money < land_price(key):
		return "Not enough money"
	return ""


func buy(who: Company, key: String) -> void:
	if not buy_error(who, key).is_empty():
		return
	var price := land_price(key)
	_state._add_money(who, -price)
	_state._record(null, "land", price, who)
	plots[key] = {owner = _index_of(who), crop = "", breed = "", planted = today(), head = 0.0, upgrades = [], listing = 0, paid = price}
	_changed()


## Sells a plot back to the land for land_sale_share of its price (its crop
## and herd go with it; the herd into the store first).
func sell_error(who: Company, key: String) -> String:
	return "" if owner_of(key) == who and who != null else "Not your plot"


func sell_to_land(who: Company, key: String) -> int:
	if not sell_error(who, key).is_empty():
		return 0
	var price := land_sale_price(key)
	clear(who, key)
	plots.erase(key)
	_state._add_money(who, price)
	_state._record(null, "land_sold", price, who)
	_changed()
	return price


## What selling a plot back to the land pays now.
func land_sale_price(key: String) -> int:
	return roundi(land_price(key) * float(setting("land_sale_share", 0.5)) / 10000.0) * 10000


## Lists a plot for other Agriculture companies at an asking price (0 takes it off).
func list(who: Company, key: String, price: int) -> void:
	if owner_of(key) != who or who == null:
		return
	plots[key].listing = maxi(price, 0)
	_changed()


## Why a company can't buy a listed plot ("" if it can).
func listing_error(who: Company, key: String) -> String:
	var entry := plot(key)
	var seller := owner_of(key)
	if seller == null or int(entry.get("listing", 0)) <= 0:
		return "Not for sale"
	if seller == who:
		return "Your own plot"
	if not can_farm(who):
		return "Only Agriculture companies farm"
	var port_id := port_of(key)
	if not who.regions.is_empty() and not who.regions.has(str(GameData.port_region(port_id).get("id", ""))):
		return "Unlock %s first" % GameData.port_region(port_id).get("name", "its region")
	if owned_by(who, port_id).size() >= most_at(port_id):
		return "You can own at most %d of the %d plots here" % [most_at(port_id), int(port_info(port_id).get("plots", 0))]
	if _state.in_debt(who) or who.money < int(entry.listing):
		return "Not enough money"
	return ""


## Buys a listed plot, crop, herd and upgrades with it: the seller is paid.
func buy_listing(who: Company, key: String) -> void:
	if not listing_error(who, key).is_empty():
		return
	var entry: Dictionary = plots[key]
	var seller := owner_of(key)
	var price := int(entry.listing)
	_state._add_money(who, -price)
	_state._record(null, "land", price, who)
	_state._add_money(seller, price)
	_state._record(null, "land_sold", price, seller)
	entry.owner = _index_of(who)
	entry.listing = 0
	entry.paid = price
	if seller == _state.company:
		ActivityLog.add("%s bought your plot at %s for %s." % [who.name, GameData.port_name(port_of(key)), Fmt.money(price)], ActivityLog.Kind.GOOD)
	_changed()


## Why a crop can't be planted on a plot ("" if it can).
func plant_error(who: Company, key: String, crop_id: String) -> String:
	if owner_of(key) != who or who == null:
		return "Not your plot"
	if not is_crop(crop_id):
		return "Not a crop"
	if str(plot(key).get("crop", "")) == crop_id:
		return "Already growing"
	if _state.in_debt(who) or who.money < planting_cost(key, crop_id):
		return "Not enough money"
	return ""


## Plants a crop (pulling up what was there; a herd goes into the store).
func plant(who: Company, key: String, crop_id: String) -> void:
	if not plant_error(who, key, crop_id).is_empty():
		return
	clear(who, key)
	var cost := planting_cost(key, crop_id)
	_state._add_money(who, -cost)
	_state._record(null, "farms", cost, who)
	plots[key].crop = crop_id
	plots[key].planted = today()
	_changed()


func stock_error(who: Company, key: String, breed_id: String) -> String:
	if owner_of(key) != who or who == null:
		return "Not your plot"
	if breed(breed_id).is_empty():
		return "Not a breed"
	if str(plot(key).get("breed", "")) == breed_id:
		return "Already stocked"
	if _state.in_debt(who) or who.money < stock_cost(key, breed_id):
		return "Not enough money"
	return ""


## Makes a plot a pasture stocked with a breed's herd (bought from local breeders).
func stock(who: Company, key: String, breed_id: String) -> void:
	if not stock_error(who, key, breed_id).is_empty():
		return
	clear(who, key)
	var cost := stock_cost(key, breed_id)
	_state._add_money(who, -cost)
	_state._record(null, "farms", cost, who)
	plots[key].breed = breed_id
	plots[key].head = head_room(key, breed_id)
	plots[key].planted = today()
	_changed()


## Leaves a plot bare: its crop pulled up, its herd driven into the store to ship or sell.
func clear(who: Company, key: String) -> void:
	if owner_of(key) != who or who == null:
		return
	var entry: Dictionary = plots[key]
	var breed_id := str(entry.get("breed", ""))
	if not breed_id.is_empty() and float(entry.get("head", 0.0)) >= 1.0:
		_add_to_store(who, port_of(key), str(breed(breed_id).species) + BREED_SEP + breed_id, float(entry.head), 1.0)
	entry.crop = ""
	entry.breed = ""
	entry.head = 0.0
	_changed()


## Why an upgrade can't go on a plot ("" if it can).
func upgrade_error(who: Company, key: String, upgrade_id: String) -> String:
	var info := upgrade(upgrade_id)
	if owner_of(key) != who or who == null:
		return "Not your plot"
	if info.is_empty():
		return "No such upgrade"
	if _has(key, upgrade_id):
		return "Built"
	if _state.in_debt(who) or who.money < int(info.cost):
		return "Not enough money"
	return ""


func add_upgrade(who: Company, key: String, upgrade_id: String) -> void:
	if not upgrade_error(who, key, upgrade_id).is_empty():
		return
	var cost := int(upgrade(upgrade_id).cost)
	_state._add_money(who, -cost)
	_state._record(null, "farms", cost, who)
	(plots[key].upgrades as Array).append(upgrade_id)
	_changed()


## Why a company can't build a cold store for its farm store at a port.
func cold_store_error(who: Company, port_id: String) -> String:
	if owned_by(who, port_id).is_empty():
		return "You have no farm here"
	if bool(who.farm_stores.get(port_id, {}).get("cold", false)):
		return "Built"
	if _state.in_debt(who) or who.money < int(setting("cold_store_cost", 1500000)):
		return "Not enough money"
	return ""


func build_cold_store(who: Company, port_id: String) -> void:
	if not cold_store_error(who, port_id).is_empty():
		return
	var cost := int(setting("cold_store_cost", 1500000))
	_state._add_money(who, -cost)
	_state._record(null, "farms", cost, who)
	var store: Dictionary = who.farm_stores.get_or_add(port_id, {items = {}, cold = false})
	store.cold = true
	_changed()


## Sells a store item at its port's price (its freshness and breed in). Returns the money.
func sell_item(who: Company, port_id: String, item: String) -> int:
	var items: Dictionary = who.farm_stores.get(port_id, {}).get("items", {})
	if not items.has(item):
		return 0
	var held: Array = items[item]
	var units := floori(float(held[0]))
	if units <= 0:
		return 0
	var value := roundi(units * _value_at(port_id, item, who) * float(held[1]))
	items.erase(item)
	_state._add_money(who, value)
	_state._record(null, "farm_sales", value, who)
	_state._tally_port_trade(who, port_id, item_commodity(item), units, value, true)
	_changed()
	return value


# --- The store and the ships ------------------------------------------------------------------

## A company's farm store at a port: {item: [units, freshness]}.
func store_items(who: Company, port_id: String) -> Dictionary:
	return who.farm_stores.get(port_id, {}).get("items", {})


## What a company's farm store at a port is worth there.
func store_value(who: Company, port_id: String) -> int:
	var total := 0.0
	var items := store_items(who, port_id)
	for item: String in items:
		total += float(items[item][0]) * _value_at(port_id, item, who) * float(items[item][1])
	return roundi(total)


## A ship loading at a port where its company's farm store holds something it
## carries: it takes what pays most where it's going (its freshness and breed
## in), free (the farm's own, its worth here as the cargo's cost), up to its
## room. Sets the ship's cargo and returns [commodity, units], or [] for none.
func load_ship(ship: Ship, to: String) -> Array:
	var who: Company = _state.owner_of(ship)
	var items := store_items(who, ship.docked_at)
	if items.is_empty():
		return []
	var carries: Array = ship.model().get("cargo", [])
	var best := ""
	var best_gain := 0.0
	for item: String in items:
		var commodity := item_commodity(item)
		if not carries.has(commodity) or float(items[item][0]) < 1.0:
			continue
		var room := ship.capacity() / GameData.hold_of(commodity)
		var gain := minf(float(items[item][0]), room) * float(_state.company_sell_price(to, commodity, who)) * breed_value(item_breed(item)) * float(items[item][1])
		if gain > best_gain:
			best_gain = gain
			best = item
	if best.is_empty():
		return []
	var commodity := item_commodity(best)
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())) / GameData.hold_of(commodity))
	var held: Array = items[best]
	var quantity := mini(room, floori(float(held[0])))
	if quantity <= 0:
		return []
	held[0] = float(held[0]) - quantity
	if float(held[0]) < 1.0:
		items.erase(best)
	var cost := roundi(quantity * _value_at(ship.docked_at, best, who) * float(held[1]))
	_state._record(ship, "cargo", cost)
	ship.cargo_id = commodity
	ship.cargo_from = ship.docked_at
	ship.cargo_qty = quantity
	ship.cargo_cost = cost
	ship.cargo_breed = item_breed(best)
	ship.cargo_fresh = float(held[1])
	ship.cargo_since = _state.play_time
	ship.cargo_farm = true
	who.farm_tally.collected = float(who.farm_tally.get("collected", 0.0)) + cost
	_state.cargo_loaded.emit(ship, ship.docked_at, commodity, quantity, cost, to)
	_state.ship_changed.emit(ship)
	return [commodity, quantity]


# --- The rating's Farms part -----------------------------------------------------------------------

## The Farms part of a company's Agriculture rating (0 to 5) and its figures:
## plots farmed against what its level expects (1 + level / 10, up to 10),
## its crops' and herds' climate fit (what the land allows them), and the
## share of its harvests collected rather than spoiled.
func rating_part(who: Company) -> Dictionary:
	var keys := owned_by(who)
	var farmed := 0
	var fit := 0.0
	for key in keys:
		var entry := plot(key)
		if not str(entry.get("crop", "")).is_empty():
			farmed += 1
			fit += minf(effective_fit(key, entry.crop), 1.0)
		elif not str(entry.get("breed", "")).is_empty():
			farmed += 1
			fit += breed_fit(port_of(key), entry.breed)
	var expected := minf(1.0 + who.level() / 10.0, 10.0)
	var fits := fit / farmed if farmed > 0 else 0.0
	var harvested := float(who.farm_tally.get("harvested", 0.0))
	var spoiled := float(who.farm_tally.get("spoiled", 0.0))
	var collected := clampf(1.0 - spoiled / harvested, 0.0, 1.0) if harvested > 0.0 else (1.0 if farmed > 0 else 0.0)
	var stars := 0.0 if farmed == 0 else 5.0 * (0.4 * minf(farmed / expected, 1.0) + 0.3 * fits + 0.3 * collected)
	return {stars = clampf(stars, 0.0, 5.0), farmed = farmed, plots = keys.size(), expected_plots = expected, fit = fits, collected = collected}


# --- The map --------------------------------------------------------------------------------

## What a farm port's fields look like now, for the map: [[colour, owner
## colour or null, orchard?, pasture?], ...] a plot, and a key that changes
## when any of it does (season, crop, owner).
func look(port_id: String) -> Array:
	var fields := []
	var month := month_now()
	var south := float(GameData.get_port(port_id).get("lat", 0.0)) < 0.0
	var climate := climate_of(port_id)
	var winter_months := [6, 7, 8] if south else [12, 1, 2]
	var snowy := climate in ["cool", "continental"] and winter_months.has(month)
	for key in keys_at(port_id):
		var entry := plot(key)
		var who := owner_of(key)
		var crop_id := str(entry.get("crop", ""))
		var breed_id := str(entry.get("breed", ""))
		var colour := Color("#8a9a5a")  # Wild grass, unowned.
		var orchard := false
		if not crop_id.is_empty():
			orchard = bool(crop(crop_id).get("orchard", false))
			var months := harvest_months(port_id, crop_id)
			if months.has(month):
				colour = Color.from_string(str(crop(crop_id).get("color", "#c8a040")), Color.GOLDENROD)  # Ripe.
			elif months.has((month % 12) + 1) or orchard:
				colour = Color("#5e9a3a")  # Growing.
			else:
				colour = Color("#8a6a48")  # Bare earth.
		elif not breed_id.is_empty():
			colour = Color("#76a848")  # Pasture.
		elif who != null:
			colour = Color("#9a7a52")  # Owned, unplanted.
		if snowy and not orchard:
			colour = colour.lerp(Color("#eef2f6"), 0.8)
		fields.append([colour, _state.company_color_value(who.color) if who != null else null, orchard, not breed_id.is_empty(), Color.from_string(str(breed(breed_id).get("color", "#ffffff")), Color.WHITE)])
	return fields


# --- AI rivals ---------------------------------------------------------------------------------------

## A rival farming simply (RivalAI, now and then): with money to spare, a plot
## at a farm port in its regions where its ships can carry what it grows,
## planted with the crop that fits best of what its ships carry (or stocked
## with the best breed for its livestock carriers); and a listed plot it can
## afford. Returns news ("bought a farm at Valencia").
func run_rival(rival: Company, spare: int) -> Array:
	var news := []
	if not can_farm(rival) or rival.level() < 3:
		return news
	var carries := {}
	for ship: Ship in _state.fleet(rival):
		for commodity: String in ship.model().get("cargo", []):
			carries[commodity] = true
	if carries.is_empty():
		return news
	for key in owned_by(rival):
		var entry := plot(key)
		if str(entry.get("crop", "")).is_empty() and str(entry.get("breed", "")).is_empty():
			var choice := _best_use(key, carries)
			if choice.begins_with("breed:"):
				stock(rival, key, choice.substr(6))
			elif not choice.is_empty():
				plant(rival, key, choice)
	var most := mini(1 + rival.level() / 12, 6)
	if owned_by(rival).size() >= most:
		return news
	var best_key := ""
	var best_score := 0.0
	for key: String in plots:
		if int(plots[key].get("listing", 0)) > 0 and listing_error(rival, key).is_empty() and int(plots[key].listing) <= mini(spare, roundi(land_price(key) * 1.3)):
			best_key = key
			break
	if not best_key.is_empty():
		buy_listing(rival, best_key)
		news.append("bought a farm at %s" % GameData.port_name(port_of(best_key)))
		return news
	for port_id in port_ids():
		if not rival.regions.is_empty() and not rival.regions.has(str(GameData.port_region(port_id).get("id", ""))):
			continue
		for key in keys_at(port_id):
			if not buy_error(rival, key).is_empty() or land_price(key) > spare:
				continue
			var use := _best_use(key, carries)
			if use.is_empty():
				continue
			var score := fertility(key) * _use_fit(key, use) / land_price(key)
			if score > best_score:
				best_score = score
				best_key = key
	if best_key.is_empty():
		return news
	buy(rival, best_key)
	var choice := _best_use(best_key, carries)
	if choice.begins_with("breed:"):
		stock(rival, best_key, choice.substr(6))
	else:
		plant(rival, best_key, choice)
	news.append("bought a farm at %s" % GameData.port_name(port_of(best_key)))
	return news


## The best fitting crop (or "breed:id") for a plot among what a rival's ships carry.
func _best_use(key: String, carries: Dictionary) -> String:
	var best := ""
	var best_fit := 0.0
	for crop_id in crop_ids():
		if carries.has(crop_id) and crop_fit(port_of(key), crop_id) > best_fit:
			best_fit = crop_fit(port_of(key), crop_id)
			best = crop_id
	for each: Dictionary in data().get("breeds", []):
		if carries.has(str(each.species)) and breed_fit(port_of(key), each.id) * float(each.value) > best_fit:
			best_fit = breed_fit(port_of(key), each.id) * float(each.value)
			best = "breed:" + str(each.id)
	return best


func _use_fit(key: String, use: String) -> float:
	return breed_fit(port_of(key), use.substr(6)) if use.begins_with("breed:") else crop_fit(port_of(key), use)

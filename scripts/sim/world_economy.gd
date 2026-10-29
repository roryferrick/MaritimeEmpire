# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name WorldEconomy
extends RefCounted
## The living world's economy (data/economy.json; DESIGN_LIVING_WORLD.md M1).
##
## Markets are trade zones: a country, or a big country's coastline zone
## (data/countries.json), with its ports. Each zone keeps a stockpile of every
## good and a price for it. People live in places: each port's metro and each
## inland city (data/cities.json), with the country's countryside shared among
## them; an inland city buys and sells through its serving ports' zones. Every
## calendar day (step()) each zone makes what its plants make (Producers), its
## people use what their needs call for (by stratum, the cheapest goods of a
## need first) and its industry what its users call for, and ships' cargo moves
## stock between zones (take(), deliver()). A good's price follows its days of
## cover against cover_days. People grow at their country's real rate and drift
## into the cities; currencies drift with the trade balance.
##
## The world starts balanced: each good's world use is its world output, shared
## out by need, so each zone starts short or long, and that gap is the trade.

signal changed

## Loaded data files (data/<name>.json), kept once read.
static var _data := {}
static var _lines := {}
static var _cities := {}
static var _countries := {}

var _state: Node  # GameState
var producers := Producers.new()

## The goods (every commodity but the legacy plain Cars, Trucks and Boats).
var goods := PackedStringArray()
var _good_index := {}
var _base := PackedFloat64Array()
## The zones: [{id ("ESP/all"), country, name, ports, main (its biggest port)}].
var zones: Array = []
var _zone_of_port := {}
var _port_factor := {}  # Port id -> its local price factor in its zone.
## Places people live: [{kind ("port"/"city"), id, country, urban, rural, zones: [[zone index, share]]}].
var places: Array = []
var _place_index := {}  # "kind/id" -> index.

## Per zone x good (index zone * goods.size() + good): stock, capacity a day,
## the base use a day from needs and from users, use and output today, ships on
## their way in, and the price.
var stock := PackedFloat64Array()
var capacity := PackedFloat64Array()
var need_base := PackedFloat64Array()
var user_base := PackedFloat64Array()
var used := PackedFloat64Array()
var made := PackedFloat64Array()
var inbound := PackedFloat64Array()
var price := PackedFloat64Array()
## Per good: units a day per unit of need weight (fixed when the world is made).
var need_scale := PackedFloat64Array()
## Per need: its goods' indexes; per good: its need's index (-1 for none).
var _need_goods: Array = []
var _good_need := PackedInt32Array()
## Per country id: {strength, exports, imports}.
var currency := {}
## The calendar day last begun, and the zone the day's work is up to (-1: done;
## a day's zones are stepped ZONES_PER_STEP a call, so no frame stalls).
var day := -1
var _cursor := -1
const ZONES_PER_STEP := 12
## Zones of one country share by land: each day this share of the gap between
## a zone's stock and its fair share (by use) of the country's moves.
const INTERNAL_FLOW := 0.15
## How much of the cargo on its way to a zone its price counts as already there
## (half: a shortage with ships on their way is half a shortage).
const INBOUND_LOOK := 0.5
var seed := 0


func _init(state: Node) -> void:
	_state = state


# --- Data ------------------------------------------------------------------------

## A data file (data/<name>.json), read once.
static func data(name: String) -> Dictionary:
	if not _data.has(name):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % name))
		_data[name] = parsed if parsed is Dictionary else {}
	return _data[name]


static func settings(section: String) -> Variant:
	return data("economy").get(section, {})


## The ship line (ship_models.json category) that carries a good ("" if none).
static func line_of(good: String) -> String:
	if _lines.is_empty():
		for model: Dictionary in GameData.ship_models:
			for each: String in model.get("cargo", []):
				if not _lines.has(each):
					_lines[each] = str(model.get("category", ""))
	return str(_lines.get(good, ""))


## An inland city's entry (data/cities.json), or {}.
static func city(id: String) -> Dictionary:
	if _cities.is_empty():
		for each: Dictionary in data("cities").get("cities", []):
			_cities[each.id] = each
	return _cities.get(id, {})


static func country(id: String) -> Dictionary:
	if _countries.is_empty():
		for each: Dictionary in data("countries").get("countries", []):
			_countries[each.id] = each
	return _countries.get(id, {})


func has_good(good: String) -> bool:
	return _good_index.has(good)


func good_index(good: String) -> int:
	return int(_good_index.get(good, -1))


func zone_of_port(port_id: String) -> int:
	return int(_zone_of_port.get(port_id, -1))


func country_of_port(port_id: String) -> String:
	return str(data("countries").get("port_countries", {}).get(port_id, ""))


func ports_of_country(country_id: String) -> Array:
	var out := []
	var map: Dictionary = data("countries").get("port_countries", {})
	for port_id: String in map:
		if map[port_id] == country_id:
			out.append(port_id)
	return out


func cities_of_country(country_id: String) -> Array:
	return data("cities").get("cities", []).filter(func(each: Dictionary) -> bool: return each.country == country_id).map(func(each: Dictionary) -> String: return each.id)


## The people of a place now (urban and rural).
func place_people(kind: String, id: String) -> float:
	var at := int(_place_index.get("%s/%s" % [kind, id], -1))
	return float(places[at].urban) + float(places[at].rural) if at >= 0 else 0.0


## A real amount (production.json's unit) in the good's game units (markets.json unit).
func to_game_units(good: String, amount: float, unit: String) -> float:
	var units: Dictionary = settings("units")
	var game_unit := str(GameData.commodity(good).get("unit", "ton"))
	match unit:
		"t_metal", "t_oxide":
			return amount / maxf(float(units.get("grades", {}).get(good, 1.0)), 0.00001)
		"m3":
			return amount * float(units.get("timber_t_per_m3", 0.7))
		"share":
			return amount * float(units.get("container_totals", {}).get(good, 0.0))
		"t":
			if game_unit == "crate":
				return amount / float(units.get("crate_t", 0.025))
			if game_unit == "pallet":
				return amount / float(units.get("pallet_t", 1.0))
			return amount
	return amount


# --- Making the world ----------------------------------------------------------

## The tables every game shares (goods, zones, places), from the data.
func _build_tables() -> void:
	goods.clear()
	_good_index.clear()
	_base.clear()
	for commodity: Dictionary in GameData.commodities:
		if commodity.get("legacy", false) or line_of(commodity.id).is_empty():
			continue
		_good_index[commodity.id] = goods.size()
		goods.append(commodity.id)
		_base.append(float(commodity.get("base", 1.0)))
	zones.clear()
	_zone_of_port.clear()
	var countries: Dictionary = {}
	for each: Dictionary in data("countries").get("countries", []):
		countries[each.id] = each
	for country_id: String in countries:
		for zone: Dictionary in countries[country_id].get("zones", []):
			var ports: Array = (zone.ports as Array).filter(func(port_id: String) -> bool: return not GameData.get_port(port_id).is_empty())
			if ports.is_empty():
				continue
			ports.sort_custom(func(a: String, b: String) -> bool: return _state.port_sizes.size(a) > _state.port_sizes.size(b))
			for port_id: String in ports:
				_zone_of_port[port_id] = zones.size()
			for i in ports.size():
				_port_factor[ports[i]] = 1.0 if ports.size() == 1 else 1.0 + float(settings("prices").get("port_spread", 0.06)) * (2.0 * i / (ports.size() - 1) - 1.0)
			zones.append({id = "%s/%s" % [country_id, zone.id], country = country_id, name = str(zone.name), ports = ports, main = ports[0]})
	_build_needs()


func _build_needs() -> void:
	_need_goods.clear()
	_good_need = PackedInt32Array()
	_good_need.resize(goods.size())
	_good_need.fill(-1)
	var needs: Array = settings("needs")
	for n in needs.size():
		var list := []
		for each: String in needs[n].goods:
			for good in _expand(each):
				var g := good_index(good)
				if g >= 0:
					list.append(g)
					_good_need[g] = n
		_need_goods.append(list)


## A needs or users entry as goods: "@cars" is every maker of cars.
func _expand(each: String) -> Array:
	if not each.begins_with("@"):
		return [each]
	var kind := each.substr(1)
	return Manufacturers.makers().filter(func(maker: Dictionary) -> bool: return str(maker.get("kind", "")) == kind).map(func(maker: Dictionary) -> String: return maker.id)


## The people at the start: each port's metro and inland city as its 2016
## people (no more than 95% of its country between them), the country's
## countryside shared among its places by size.
func _build_places() -> void:
	places.clear()
	_place_index.clear()
	var cities: Dictionary = data("cities")
	var by_country := {}  # country -> [indexes]
	for port_id: String in cities.get("ports", {}):
		var entry: Dictionary = cities.ports[port_id]
		var zone := zone_of_port(port_id)
		if zone < 0:
			continue
		_add_place("port", port_id, str(entry.country), float(entry.population), [[zone, 1.0]], by_country)
	for each: Dictionary in cities.get("cities", []):
		var shares := []
		for served: Array in each.get("ports", []):
			var zone := zone_of_port(str(served[0]))
			if zone >= 0:
				shares.append([zone, float(served[1])])
		if not shares.is_empty():
			_add_place("city", each.id, str(each.country), float(each.population), shares, by_country)
	for country_id: String in by_country:
		var people := float(country(country_id).get("population", 0))
		var urban := 0.0
		for i: int in by_country[country_id]:
			urban += float(places[i].urban)
		var scale := minf(1.0, people * 0.95 / maxf(urban, 1.0))
		var rural := maxf(people - urban * scale, 0.0)
		for i: int in by_country[country_id]:
			places[i].urban = float(places[i].urban) * scale
			places[i].rural = rural * float(places[i].urban) / maxf(urban * scale, 1.0)


func _add_place(kind: String, id: String, country_id: String, people: float, shares: Array, by_country: Dictionary) -> void:
	_place_index["%s/%s" % [kind, id]] = places.size()
	by_country.get_or_add(country_id, []).append(places.size())
	places.append({kind = kind, id = id, country = country_id, urban = people, rural = 0.0, zones = shares,
		rate = pow(1.0 + float(country(country_id).get("growth", 0.01)), 1.0 / 365.25), split = _strata_split(country_id), wealth = _wealth(country_id)})


## Makes a new world: the tables, people, plants, the base use (balanced to
## the world's output) and stockpiles of start_cover days.
func make_world(new_seed: int) -> void:
	seed = new_seed
	_build_tables()
	_build_places()
	producers.generate(self, new_seed)
	var size := zones.size() * goods.size()
	for array: PackedFloat64Array in [stock, capacity, need_base, user_base, used, made, inbound, price]:
		array.resize(size)
		array.fill(0.0)
	_fill_capacity()
	_balance()
	var cover: Array = settings("prices").get("start_cover", [20, 45])
	var rng := RandomNumberGenerator.new()
	rng.seed = new_seed
	for i in size:
		var use := need_base[i] + user_base[i]
		var days := lerpf(float(cover[0]), float(cover[1]), rng.randf())
		if capacity[i] > use:
			days *= 1.5  # (A zone that makes it keeps more.)
		stock[i] = use * days
	currency.clear()
	for each: Dictionary in data("countries").get("countries", []):
		currency[each.id] = {strength = float(each.get("currency_strength", 1.0)), exports = 0.0, imports = 0.0}
	_update_prices()
	day = _today()


## Each zone's plants' capacity a day (a plant at an inland city split over its serving zones).
func _fill_capacity() -> void:
	capacity.fill(0.0)
	var g_count := goods.size()
	for plant: Dictionary in producers.plants:
		var g := good_index(plant.good)
		if g < 0:
			continue
		var per_day := float(plant.capacity) / 365.25
		for share: Array in _plant_zones(plant):
			capacity[int(share[0]) * g_count + g] += per_day * float(share[1])


func _plant_zones(plant: Dictionary) -> Array:
	if plant.site_kind == "port":
		var zone := zone_of_port(plant.site)
		return [[zone, 1.0]] if zone >= 0 else []
	var at := int(_place_index.get("city/%s" % plant.site, -1))
	return places[at].zones if at >= 0 else []


## Shares each good's world output out as use: its need's part by people (each
## stratum's want of it, lifted by their country's wealth), the rest by its
## users' drivers (economy.json users).
func _balance() -> void:
	var g_count := goods.size()
	var world := PackedFloat64Array()
	world.resize(g_count)
	for z in zones.size():
		for g in g_count:
			world[g] += capacity[z * g_count + g]
	var needs: Array = settings("needs")
	var weights := _need_weights()  # need -> PackedFloat64Array per zone
	need_scale.resize(g_count)
	need_scale.fill(0.0)
	var users: Dictionary = settings("users")
	var drivers := {}  # driver -> PackedFloat64Array per zone (cached)
	for g in g_count:
		var good := goods[g]
		var user_list: Array = users.get(good, [])
		var family := _family_key(good)
		if user_list.is_empty() and not family.is_empty():
			user_list = users.get(family, [])
		var user_share := 0.0
		for each: Array in user_list:
			user_share += float(each[1])
		var n := _good_need[g]
		var need_share := 0.0 if n < 0 else maxf(1.0 - user_share, 0.0)
		if n < 0 and user_share > 0.0:
			user_share = 1.0  # (No need: its users take all of it.)
		if need_share > 0.0:
			var total := 0.0
			for z in zones.size():
				total += float(weights[n][z])
			need_scale[g] = world[g] * need_share / maxf(total, 1.0)
			for z in zones.size():
				need_base[z * g_count + g] = need_scale[g] * float(weights[n][z])
		var scale := 1.0 if n < 0 else 1.0
		for each: Array in user_list:
			var driver := str(each[0])
			if not drivers.has(driver):
				drivers[driver] = _driver(driver)
			var per_zone: PackedFloat64Array = drivers[driver]
			var total := 0.0
			for z in zones.size():
				total += per_zone[z]
			if total <= 0.0:
				continue
			var share := float(each[1]) / maxf(user_share, 0.0001) * (1.0 - need_share) * scale
			for z in zones.size():
				user_base[z * g_count + g] += world[g] * share * per_zone[z] / total
	var unused := []
	for g in g_count:
		if world[g] > 0.0 and _good_need[g] < 0 and (users.get(goods[g], []) as Array).is_empty() and (users.get(_family_key(goods[g]), []) as Array).is_empty():
			unused.append(goods[g])
	if not unused.is_empty():
		push_warning("WorldEconomy: no one uses %s" % ", ".join(PackedStringArray(unused)))


## "@cars" for a maker of cars, else "".
func _family_key(good: String) -> String:
	var kind := str(Manufacturers.maker(good).get("kind", "")) if not Manufacturers.maker(good).is_empty() else ""
	return "@" + kind if not kind.is_empty() else ""


## Each need's weight in each zone: its places' people by stratum x the
## stratum's want x their country's wealth.
func _need_weights() -> Array:
	var needs: Array = settings("needs")
	var out := []  # (Arrays, not packed ones: a packed array taken out of an Array is a copy.)
	for n in needs.size():
		var per_zone := []
		per_zone.resize(zones.size())
		per_zone.fill(0.0)
		out.append(per_zone)
	for place: Dictionary in places:
		var strata := strata_of(place)
		var wealth := float(place.wealth)
		for n in needs.size():
			var want: Array = needs[n].strata
			var weight := (float(strata[0]) * float(want[0]) + float(strata[1]) * float(want[1]) + float(strata[2]) * float(want[2])) * wealth
			for share: Array in place.zones:
				out[n][int(share[0])] += weight * float(share[1])
	return out


## A place's people by stratum [lower, middle, upper]: its town and country
## people by their country's split (place.split, see _strata_split()).
func strata_of(place: Dictionary) -> Array:
	var split: Array = place.split
	var urban := float(place.urban)
	var rural := float(place.rural)
	return [urban * float(split[0][0]) + rural * float(split[1][0]), urban * float(split[0][1]) + rural * float(split[1][1]), urban * float(split[0][2]) + rural * float(split[1][2])]


## A country's people's split into strata, [[town lower, middle, upper], [country ...]], by its GDP a head.
func _strata_split(country_id: String) -> Array:
	var s: Dictionary = settings("strata")
	var gdp := float(country(country_id).get("gdp_per_head", 1000))
	var wealth := clampf(log(maxf(gdp, 1.0) / float(s.poor_gdp)) / log(float(s.rich_gdp) / float(s.poor_gdp)), 0.0, 1.0)
	var middle := lerpf(float(s.middle_min), float(s.middle_max), wealth)
	var upper := lerpf(float(s.upper_min), float(s.upper_max), wealth)
	var out := []
	for lean in [float(s.city_lean), float(s.rural_lean)]:
		var m := minf(middle * lean, 0.9)
		var u := minf(upper * lean, 0.5)
		out.append([maxf(1.0 - m - u, 0.0), m, u])
	return out


func _wealth(country_id: String) -> float:
	var s: Dictionary = settings("strata")
	var gdp := float(country(country_id).get("gdp_per_head", 1000))
	return pow(maxf(gdp, 300.0) / float(s.world_gdp_per_head), float(s.wealth_power))


## A users driver's weight in each zone: make:<good> (its capacity), gdp, people, farming.
func _driver(driver: String) -> PackedFloat64Array:
	var g_count := goods.size()
	var out := PackedFloat64Array()
	out.resize(zones.size())
	if driver.begins_with("make:"):
		for good in _expand(driver.substr(5)):
			var g := good_index(good)
			if g < 0:
				continue
			for z in zones.size():
				out[z] += capacity[z * g_count + g] * _base[g]
	elif driver == "farming":
		for g in g_count:
			if Producers.trade_of(goods[g]) == "farming":
				for z in zones.size():
					out[z] += capacity[z * g_count + g] * _base[g]
	else:
		for place: Dictionary in places:
			var people := float(place.urban) + float(place.rural)
			var weight := people if driver == "people" else people * float(country(str(place.country)).get("gdp_per_head", 0))
			for share: Array in place.zones:
				out[int(share[0])] += weight * float(share[1])
	return out


# --- Each day -------------------------------------------------------------------

func _today() -> int:
	return floori(float(_state.calendar_time() - _state.calendar_time_at(0.0)) / 86400.0)


## Steps the economy: a new calendar day begins when the clock reaches it,
## and its zones are stepped ZONES_PER_STEP a call until the day is done.
func step(_delta: float) -> void:
	if zones.is_empty():
		return
	if _cursor < 0 and day < _today():
		_begin_day()
	if _cursor >= 0:
		var end := mini(_cursor + ZONES_PER_STEP, zones.size())
		for z in range(_cursor, end):
			_step_zone(z)
		_cursor = end
		if _cursor >= zones.size():
			_end_day()


## A whole day at once (tests and probes).
func _step_day() -> void:
	_begin_day()
	for z in zones.size():
		_step_zone(z)
	_end_day()


func _begin_day() -> void:
	day += 1
	_cursor = 0
	_internal_flow()


func _end_day() -> void:
	_cursor = -1
	_grow_people()
	_drift_currencies()
	if _state.history != null:
		_state.history.sample(self, day)  # (The week's and month's price history, and the news in it.)
	changed.emit()


## Zones of one country even out by land: each good's stock moves towards each
## zone's share of the country's by its use, INTERNAL_FLOW of the gap a day.
func _internal_flow() -> void:
	var g_count := goods.size()
	for group: Array in _country_zones():
		for g in g_count:
			var total_stock := 0.0
			var total_use := 0.0
			for z: int in group:
				total_stock += stock[z * g_count + g]
				total_use += need_base[z * g_count + g] + user_base[z * g_count + g]
			if total_use <= 0.0:
				continue
			for z: int in group:
				var i := z * g_count + g
				var fair := total_stock * (need_base[i] + user_base[i]) / total_use
				stock[i] += (fair - stock[i]) * INTERNAL_FLOW


## The zones of each country with more than one, worked out once.
func _country_zones() -> Array:
	if _country_groups.is_empty():
		var by_country := {}
		for z in zones.size():
			by_country.get_or_add(zones[z].country, []).append(z)
		for country_id: String in by_country:
			if (by_country[country_id] as Array).size() > 1:
				_country_groups.append(by_country[country_id])
	return _country_groups
var _country_groups := []


## A zone's day: its people buy their needs (the cheapest goods of each first),
## its industry its inputs, its plants make, and its prices follow.
func _step_zone(z: int) -> void:
	var p: Dictionary = settings("prices")
	var g_count := goods.size()
	var dp := float(p.get("demand_power", 0.3))
	var sigma := float(p.get("substitution", 2.0))
	var sp := float(p.get("supply_power", 0.25))
	var floor_share := float(p.get("supply_floor", 0.6))
	var row := z * g_count
	var events: Events = _state.events  # (Disasters stop production, epidemics thin demand, famines double the hunger for grain: see Events.)
	var make_f: float = events.make_factor(z)
	var use_f: float = events.use_factor(z)
	var strength := float(currency.get(zones[z].country, {}).get("strength", 1.0))
	# Needs: the cheapest goods of each need first.
	for list: Array in _need_goods:
		var total := 0.0
		var weighed := 0.0
		var index := 0.0
		for g: int in list:
			var base := need_base[row + g]
			var r := price[row + g] / (_base[g] * strength)
			total += base
			weighed += base * pow(r, -sigma)
			index += base * r
		if total <= 0.0:
			continue
		var scale := total * pow(index / total, -dp) / weighed
		for g: int in list:
			var r := price[row + g] / (_base[g] * strength)
			used[row + g] = need_base[row + g] * pow(r, -sigma) * scale
	for g in g_count:
		var i := row + g
		var r := price[i] / (_base[g] * strength)
		if _good_need[g] < 0:
			used[i] = 0.0
		used[i] += user_base[i] * pow(r, -dp)
		if use_f != 1.0 or not events.active.is_empty():
			used[i] *= use_f * events.use_boost(z, goods[g])
		made[i] = capacity[i] * clampf(floor_share + (1.0 - floor_share) * pow(r, sp), floor_share, 1.1) * make_f
		stock[i] = maxf(stock[i] + made[i] - used[i], 0.0)
	_update_zone_prices(z)


## Every price from its zone's days of cover (stock and ships on their way in, against its base use).
func _update_prices() -> void:
	for z in zones.size():
		_update_zone_prices(z)


func _update_zone_prices(z: int) -> void:
	var p: Dictionary = settings("prices")
	var cover_days := float(p.get("cover_days", 30))
	var power := float(p.get("price_power", 0.6))
	var range_: Array = p.get("price_range", [0.3, 3.0])
	var g_count := goods.size()
	var strength := float(currency.get(zones[z].country, {}).get("strength", 1.0))
	for g in g_count:
		var i := z * g_count + g
		var use := use_for_price(i)
		var factor := 1.0  # (Neither used nor made here: the base price, and nothing to buy.)
		if use > 0.0:
			var cover := (stock[i] + inbound[i] * INBOUND_LOOK) / use
			factor = clampf(pow(cover_days / maxf(cover, 0.01), power), float(range_[0]), float(range_[1]))
		price[i] = _base[g] * factor * strength


## What a zone's stock of a good is measured against for its price and its
## days of cover: its use a day, or for a zone that makes more than it uses
## (a mine with no local use), its output a day.
func use_for_price(i: int) -> float:
	return maxf(need_base[i] + user_base[i], capacity[i])


## People grow at their country's real rate a day, and a little of the
## countryside moves to town. (Needs follow every few weeks: _refresh_needs().)
func _grow_people() -> void:
	var people: Dictionary = settings("people")
	var migration := float(people.get("migration_share", 0.004)) / 365.25
	for place: Dictionary in places:
		var rate := float(place.rate)
		var moving := float(place.rural) * migration
		place.urban = float(place.urban) * rate + moving
		place.rural = maxf(float(place.rural) * rate - moving, 0.0)
	if day % 30 == 0:
		_refresh_needs()


## The need part of each zone's base use, from its people now.
func _refresh_needs() -> void:
	var g_count := goods.size()
	var weights := _need_weights()
	for g in g_count:
		var n := _good_need[g]
		if n < 0 or need_scale[g] <= 0.0:
			continue
		for z in zones.size():
			need_base[z * g_count + g] = need_scale[g] * float(weights[n][z])


## Each currency drifts with its country's trade balance.
func _drift_currencies() -> void:
	var c: Dictionary = settings("currency")
	var fade := 1.0 - 1.0 / float(c.get("balance_days", 90))
	var rate := float(c.get("rate", 0.15)) / 365.25
	var range_: Array = c.get("range", [0.6, 1.6])
	for id: String in currency:
		var entry: Dictionary = currency[id]
		var trade := float(entry.exports) + float(entry.imports)
		if trade > 0.0:
			entry.strength = clampf(float(entry.strength) + rate * (float(entry.exports) - float(entry.imports)) / trade, float(range_[0]), float(range_[1]))
		entry.exports = float(entry.exports) * fade
		entry.imports = float(entry.imports) * fade


# --- Professions (DESIGN_LIVING_WORLD.md M1: the pops' trades, shown on the cards) ----------

## The professions, [name, colour], and the order they're shown in.
const PROFESSIONS := {dockers = ["dockers", "#c98f4a"], sailors = ["sailors", "#4a7fc9"], fishers = ["fishers", "#5ab4d6"], farmers = ["farmers", "#8fbf5a"],
	miners = ["miners", "#8a7a6a"], factory = ["factory hands", "#b05a5a"], clerks = ["clerks", "#a98fd0"], traders = ["traders", "#e0c060"]}
const PROFESSION_ORDER := ["farmers", "fishers", "miners", "factory", "dockers", "sailors", "clerks", "traders"]
## Weights: a plant's yearly output in US its trade's profession by this; a port's size (1-100) its dockers and sailors; the middle and upper strata their clerks and traders.
const PROFESSION_PER_DOLLAR := {farming = 1.0 / 18000.0, fishing = 1.0 / 25000.0, mining = 1.0 / 120000.0, energy = 1.0 / 300000.0, metals = 1.0 / 150000.0, chemicals = 1.0 / 200000.0, forestry = 1.0 / 60000.0, manufacturing = 1.0 / 90000.0}
const PROFESSION_OF_TRADE := {farming = "farmers", fishing = "fishers", mining = "miners", energy = "miners", metals = "factory", chemicals = "factory", forestry = "factory", manufacturing = "factory"}
const DOCKERS_PER_SIZE := 900.0
const SAILORS_PER_SIZE := 500.0
const CLERKS_OF_MIDDLE := 0.05
const TRADERS_OF_UPPER := 0.06
var _professions_cache := {}
var _professions_day := -1


## A zone's working people by profession, as shares: {id: share} (the rest of
## its people, in services and at home, aren't counted). From its plants by
## trade, its ports' sizes and its strata.
func professions_of_zone(z: int) -> Dictionary:
	if _professions_day != day:
		_professions_cache.clear()
		_professions_day = day
	var key := "zone/%d" % z
	if _professions_cache.has(key):
		return _professions_cache[key]
	var zone: Dictionary = zones[z]
	var counts := {}
	for port_id: String in zone.ports:
		var size := float(GameData.get_port(port_id).get("size", 10))
		counts.dockers = float(counts.get("dockers", 0.0)) + size * DOCKERS_PER_SIZE
		counts.sailors = float(counts.get("sailors", 0.0)) + size * SAILORS_PER_SIZE
		for index: int in producers.plants_at(port_id):
			_count_plant(producers.plants[index], counts)
	var strata := [0.0, 0.0, 0.0]
	for place: Dictionary in places:
		if place.country != zone.country:
			continue
		var share := 0.0
		for pair: Array in place.zones:
			if int(pair[0]) == z:
				share = float(pair[1])
		if share <= 0.0:
			continue
		var split: Array = strata_of(place)
		for k in 3:
			strata[k] += float(split[k]) * share
		if place.kind == "city":
			for index: int in producers.plants_at(str(place.id)):
				_count_plant(producers.plants[index], counts, share)
	counts.clerks = float(counts.get("clerks", 0.0)) + strata[1] * CLERKS_OF_MIDDLE
	counts.traders = float(counts.get("traders", 0.0)) + strata[2] * TRADERS_OF_UPPER
	var out := _shares(counts)
	_professions_cache[key] = out
	return out


## A country's, over its zones by their people.
func professions_of_country(country_id: String) -> Dictionary:
	var counts := {}
	for z in zones.size():
		if zones[z].country != country_id:
			continue
		var people := 0.0
		for place: Dictionary in places:
			if place.country == country_id:
				for pair: Array in place.zones:
					if int(pair[0]) == z:
						people += (float(place.urban) + float(place.rural)) * float(pair[1])
		var shares := professions_of_zone(z)
		for id: String in shares:
			counts[id] = float(counts.get(id, 0.0)) + float(shares[id]) * people
	return _shares(counts)


## An inland city's: its own plants and its strata.
func professions_of_city(city_id: String) -> Dictionary:
	var at := int(_place_index.get("city/%s" % city_id, -1))
	if at < 0:
		return {}
	var counts := {}
	for index: int in producers.plants_at(city_id):
		_count_plant(producers.plants[index], counts)
	var split: Array = strata_of(places[at])
	counts.clerks = float(split[1]) * CLERKS_OF_MIDDLE
	counts.traders = float(split[2]) * TRADERS_OF_UPPER
	return _shares(counts)


func _count_plant(plant: Dictionary, counts: Dictionary, share := 1.0) -> void:
	var trade := Producers.trade_of(str(plant.good))
	var id := str(PROFESSION_OF_TRADE.get(trade, "factory"))
	var value := float(plant.capacity) * float(GameData.commodity(str(plant.good)).get("base", 1.0))
	counts[id] = float(counts.get(id, 0.0)) + value * float(PROFESSION_PER_DOLLAR.get(trade, 1.0 / 100000.0)) * share


static func _shares(counts: Dictionary) -> Dictionary:
	var total := 0.0
	for id: String in counts:
		total += float(counts[id])
	var out := {}
	if total <= 0.0:
		return out
	for id: String in counts:
		out[id] = float(counts[id]) / total
	return out


# --- Keeping a joined game's world up to date (Net) ------------------------------------------

## The parts that move every day, small enough to send often: stocks, cargo on
## its way, prices and the currencies.
func light_dict() -> Dictionary:
	return {stock = stock.to_byte_array(), inbound = inbound.to_byte_array(), price = price.to_byte_array(), currency = currency, day = day}  # (Bytes: zstd packs them well.)


func apply_light(data: Dictionary) -> void:
	var size := zones.size() * goods.size()
	var got_stock: PackedFloat64Array = (data.get("stock", PackedByteArray()) as PackedByteArray).to_float64_array()
	if got_stock.size() != size:
		return
	stock = got_stock
	inbound = (data.get("inbound", PackedByteArray()) as PackedByteArray).to_float64_array()
	price = (data.get("price", PackedByteArray()) as PackedByteArray).to_float64_array()
	currency = data.get("currency", currency)
	day = int(data.get("day", day))
	changed.emit()


# --- Trading ---------------------------------------------------------------------

## What a port pays for a unit of a good now (0 for a port outside every zone).
func sell_price(port_id: String, good: String) -> float:
	var z := zone_of_port(port_id)
	var g := good_index(good)
	if z < 0 or g < 0:
		return GameData.base_price(port_id, good)
	return price[z * goods.size() + g] * float(_port_factor.get(port_id, 1.0))


## A zone's name for a sentence: its country's, or "coast (country)" for one of a split country's.
func zone_label(z: int) -> String:
	var zone: Dictionary = zones[z]
	if str(zone.id).ends_with("/all"):
		return str(zone.name)
	return "%s (%s)" % [str(zone.name), str(country(str(zone.country)).get("name", zone.country))]


func zone_price(z: int, g: int) -> float:
	return price[z * goods.size() + g]


func zone_stock(z: int, g: int) -> float:
	return stock[z * goods.size() + g]


## Days of use (or output) a zone's stockpile covers (INF where it's neither used nor made).
func cover(z: int, g: int) -> float:
	var i := z * goods.size() + g
	var use := use_for_price(i)
	return stock[i] / use if use > 0.0 else INF


## Takes up to `amount` from a zone's stockpile (a ship loading); returns what it got.
func take(z: int, g: int, amount: float, value := 0.0) -> float:
	var i := z * goods.size() + g
	var got := minf(amount, stock[i])
	stock[i] -= got
	if value > 0.0:
		var entry: Dictionary = currency.get(zones[z].country, {})
		if not entry.is_empty():
			entry.exports = float(entry.exports) + value * got / maxf(amount, 0.0001)
	return got


## Adds to a zone's stockpile (a ship unloading).
func deliver(z: int, g: int, amount: float, value := 0.0) -> void:
	stock[z * goods.size() + g] += amount
	if value > 0.0:
		var entry: Dictionary = currency.get(zones[z].country, {})
		if not entry.is_empty():
			entry.imports = float(entry.imports) + value


## A ship's cargo on its way in (positive) or arrived (negative), for the price's look ahead.
func add_inbound(z: int, g: int, amount: float) -> void:
	var i := z * goods.size() + g
	inbound[i] = maxf(inbound[i] + amount, 0.0)


# --- Saving ----------------------------------------------------------------------

## The plants and the base use are made again from the seed and the people on
## loading, so only what moves is saved.
func to_dict() -> Dictionary:
	var rounded := PackedFloat64Array()
	rounded.resize(stock.size())
	for i in stock.size():
		rounded[i] = snappedf(stock[i], 0.1)
	return {seed = seed, day = day, stock = Array(rounded), need_scale = Array(need_scale),
		people = places.map(func(place: Dictionary) -> Array: return [snappedf(float(place.urban), 1.0), snappedf(float(place.rural), 1.0)]),
		currency = currency}


func from_dict(data_in: Dictionary) -> void:
	if data_in.is_empty():
		return
	seed = int(data_in.get("seed", 0))
	_build_tables()
	_build_places()
	producers.generate(self, seed)
	var size := zones.size() * goods.size()
	for array: PackedFloat64Array in [capacity, need_base, user_base, used, made, inbound, price]:
		array.resize(size)
		array.fill(0.0)
	stock = PackedFloat64Array(data_in.get("stock", []))
	stock.resize(size)
	var people: Array = data_in.get("people", [])
	for i in mini(people.size(), places.size()):
		places[i].urban = float(people[i][0])
		places[i].rural = float(people[i][1])
	currency = data_in.get("currency", {})
	day = int(data_in.get("day", -1))
	_fill_capacity()
	_balance()  # (The users' base use again; the needs' scale is the one the world was made with.)
	need_scale = PackedFloat64Array(data_in.get("need_scale", []))
	need_scale.resize(goods.size())
	_refresh_needs()
	_update_prices()

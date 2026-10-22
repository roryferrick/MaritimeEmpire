# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Producers
extends RefCounted
## The world's AI producer companies and their plants (DESIGN_LIVING_WORLD.md
## M1): every country's real 2016 output of every good (data/production.json),
## in the game's units (WorldEconomy.to_game_units()), shared out among plants
## at real places: its ports (and, for farming, forestry and manufacturing, its
## inland cities), weighted towards where that industry really is (markets.json
## sources, the Cargo & Ore industry's mine ports, the farm ports, the ports by
## the oil and gas fields, the fishing ports) and concentrated as the real
## industry is (a few big mines, many growers). Vehicles and boats are made at
## the makers' own factories (data/manufacturers.json), the makers being the
## companies. Plants are grouped into companies by country and trade, about
## MULTINATIONALS of them global companies holding plants in many countries.
##
## Made once when a game is founded (generate(), from its seed) and saved
## (to_dict()); a plant's capacity is its full output a year, in game units.

## How many plants a country's output of a good goes to at most, by trade.
const PLANTS_BY_TRADE := {mining = 3, energy = 3, metals = 3, chemicals = 2, farming = 6, fishing = 4, forestry = 3, manufacturing = 5}
## Global companies, and the share of the biggest plants of their trades they hold.
const MULTINATIONALS := 30
const GLOBAL_TRADES := ["mining", "energy", "metals", "farming"]
const GLOBAL_SHARE := 0.45
## A national company holds at most this many plants before another is founded.
const PLANTS_PER_COMPANY := 40
## Weights for a plant site: a port that's a good's big source (markets.json
## sources), a mine port, a farm port, a port by an oil or gas field, a fishing port.
const SOURCE_WEIGHT := 8.0
const MINE_PORT_WEIGHT := 6.0
const FARM_PORT_WEIGHT := 3.0
const FIELD_PORT_WEIGHT := 6.0
const FISHING_PORT_WEIGHT := 3.0
const FIELD_PORT_NM := 400.0

## [{id, name, country ("" for a global one), trade, global, maker (a maker id, for a maker)}].
var companies: Array = []
## [{id, company (index), good, site, site_kind ("port" or "city"), country, capacity}].
var plants: Array = []
## Site id -> the plants there (indices into plants), biggest first (see plants_at()).
var _at_site := {}


## The trade a good belongs to.
static func trade_of(good: String) -> String:
	var line := WorldEconomy.line_of(good)
	if line == "ore":
		return "mining"
	if good in ["oil", "gas", "diesel", "gasoline", "jet_fuel", "lpg"]:
		return "energy"
	if good in ["fertilizer", "plastics", "ammonia", "hydrogen"]:
		return "chemicals"
	if good == "timber":
		return "forestry"
	if line == "breakbulk":
		return "metals"
	if line in ["grain", "produce", "livestock"]:
		return "farming"
	if line == "seafood":
		return "fishing"
	return "manufacturing"


func generate(economy: WorldEconomy, seed: int) -> void:
	companies.clear()
	plants.clear()
	_at_site.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var production: Dictionary = WorldEconomy.data("production").get("goods", {})
	var hints := _site_hints()
	for good: String in production:
		if not economy.has_good(good) or good in ["cars", "trucks", "boats"]:
			continue
		var entry: Dictionary = production[good]
		for country: String in entry.countries:
			var amount := economy.to_game_units(good, float(entry.countries[country]), str(entry.unit))
			if amount > 0.0:
				_place(economy, good, country, amount, hints)
	_place_makers(economy, production)
	_found_companies(rng)


## Shares a country's yearly output of a good among its best sites.
func _place(economy: WorldEconomy, good: String, country: String, amount: float, hints: Dictionary) -> void:
	var trade := trade_of(good)
	var sites := []  # [kind, id, weight]
	for port_id: String in economy.ports_of_country(country):
		var weight := 1.0
		if trade == "manufacturing":
			weight = sqrt(maxf(economy.place_people("port", port_id), 1.0))
		elif trade in ["farming", "forestry"]:
			weight = sqrt(maxf(economy.place_people("port", port_id), 1.0)) * 0.5
		weight *= float(hints.get("%s/%s" % [good, port_id], 1.0))
		sites.append(["port", port_id, weight])
	if trade in ["farming", "forestry", "manufacturing"] or sites.is_empty():
		for city_id: String in economy.cities_of_country(country):
			sites.append(["city", city_id, sqrt(maxf(economy.place_people("city", city_id), 1.0))])
	if sites.is_empty():
		return
	sites.sort_custom(func(a: Array, b: Array) -> bool: return float(a[2]) > float(b[2]))
	sites = sites.slice(0, int(PLANTS_BY_TRADE.get(trade, 3)))
	var total := 0.0
	for site: Array in sites:
		total += float(site[2])
	for site: Array in sites:
		plants.append({id = plants.size(), company = -1, good = good, site = site[1], site_kind = site[0], country = country,
			capacity = amount * float(site[2]) / total})


## Vehicles and boats: each country's output of a kind shared among the makers
## with factories there (by their size), else the makers with factories in the
## same market region; each factory a plant of its maker.
func _place_makers(economy: WorldEconomy, production: Dictionary) -> void:
	var makers: Array = Manufacturers.makers()
	var size_weight := {large = 4.0, medium = 2.0, small = 1.0}
	for kind: String in ["cars", "trucks", "boats"]:
		var entry: Dictionary = production.get(kind, {})
		for country: String in entry.get("countries", {}):
			var amount := float(entry.countries[country])
			var factories := []  # [maker, port, weight]
			for maker: Dictionary in makers:
				if str(maker.get("kind", "")) != kind:
					continue
				for port_id: String in maker.get("factories", []):
					if economy.country_of_port(port_id) == country:
						factories.append([maker.id, port_id, float(size_weight.get(str(maker.get("size", "medium")), 2.0))])
			if factories.is_empty():
				var region := ""
				var ports := economy.ports_of_country(country)
				if not ports.is_empty():
					region = str(GameData.port_region(ports[0]).get("id", ""))
				for maker: Dictionary in makers:
					if str(maker.get("kind", "")) != kind:
						continue
					for port_id: String in maker.get("factories", []):
						if not region.is_empty() and str(GameData.port_region(port_id).get("id", "")) == region:
							factories.append([maker.id, port_id, float(size_weight.get(str(maker.get("size", "medium")), 2.0))])
			if factories.is_empty():
				continue
			var total := 0.0
			for each: Array in factories:
				total += float(each[2])
			for each: Array in factories:
				if not economy.has_good(each[0]):
					continue
				plants.append({id = plants.size(), company = -1, good = each[0], site = each[1], site_kind = "port",
					country = economy.country_of_port(each[1]), capacity = amount * float(each[2]) / total, maker = each[0]})


## Where each good is really made: "good/port" -> weight.
func _site_hints() -> Dictionary:
	var out := {}
	var sources: Dictionary = GameData.markets.get("sources", {})
	for good: String in sources:
		for port_id: String in sources[good]:
			out["%s/%s" % [good, port_id]] = SOURCE_WEIGHT / maxf(float(sources[good][port_id]), 0.3)
	for building: Dictionary in Industry.buildings():
		if str(building.get("kind", "")) == "mine" or str(building.get("kind", "")) == "camp":
			for port_id: String in building.get("ports", {}):
				var key := "%s/%s" % [building.makes, port_id]
				out[key] = maxf(float(out.get(key, 1.0)), MINE_PORT_WEIGHT)
	for farm: Dictionary in WorldEconomy.data("farms").get("ports", []):
		for crop: String in farm.get("known", []):
			var key := "%s/%s" % [crop, farm.port]
			out[key] = maxf(float(out.get(key, 1.0)), FARM_PORT_WEIGHT)
	for field: Dictionary in WorldEconomy.data("energy").get("fields", []):
		var good := "oil" if str(field.get("kind", "")) == "oil" else "gas"
		for port: Dictionary in GameData.ports:
			if Geo.distance_nm(Vector2(float(port.lon), float(port.lat)), Vector2(float(field.lon), float(field.lat))) < FIELD_PORT_NM:
				var key := "%s/%s" % [good, port.id]
				out[key] = maxf(float(out.get(key, 1.0)), FIELD_PORT_WEIGHT)
	var fish := Fisheries.shared()
	for ground: String in fish.grounds:
		for port_id: String in fish.grounds[ground].get("ports", []):
			for family: String in ["tuna", "salmon", "whitefish", "flatfish", "small_pelagic", "mackerel", "game_fish", "billfish"]:
				var key := "%s/%s" % [family, port_id]
				out[key] = maxf(float(out.get(key, 1.0)), FISHING_PORT_WEIGHT)
	return out


## Groups the plants into companies: the makers' plants are theirs; about
## GLOBAL_SHARE of the biggest plants of the global trades go to MULTINATIONALS
## global companies; the rest to national companies by country and trade (a new
## one every PLANTS_PER_COMPANY plants).
func _found_companies(rng: RandomNumberGenerator) -> void:
	var taken := {}
	var maker_companies := {}
	for plant: Dictionary in plants:
		if plant.has("maker"):
			if not maker_companies.has(plant.maker):
				var maker := Manufacturers.maker(str(plant.maker))
				maker_companies[plant.maker] = companies.size()
				companies.append({id = companies.size(), name = str(maker.get("name", plant.maker)), country = "", trade = "manufacturing", global = true, maker = plant.maker})
				taken[str(maker.get("name", plant.maker))] = true
			plant.company = maker_companies[plant.maker]
	# The global companies, by trade.
	var globals := {}  # trade -> [company indexes]
	var per_trade := ceili(float(MULTINATIONALS) / GLOBAL_TRADES.size())
	for trade: String in GLOBAL_TRADES:
		for i in per_trade:
			globals.get_or_add(trade, []).append(companies.size())
			companies.append({id = companies.size(), name = CompanyNames.multinational(trade, rng, taken), country = "", trade = trade, global = true})
	var by_value := plants.filter(func(plant: Dictionary) -> bool: return int(plant.company) < 0 and trade_of(plant.good) in GLOBAL_TRADES)
	by_value.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _value(a) > _value(b))
	var global_count := roundi(by_value.size() * GLOBAL_SHARE * 0.5)  # (Half of the big half.)
	for i in mini(global_count, by_value.size()):
		var plant: Dictionary = by_value[i]
		if rng.randf() < GLOBAL_SHARE * 2.0:
			var choices: Array = globals[trade_of(plant.good)]
			plant.company = choices[rng.randi() % choices.size()]
	# National companies.
	var national := {}  # "country/trade" -> [company index, plants]
	for plant: Dictionary in plants:
		if int(plant.company) >= 0:
			continue
		var key := "%s/%s" % [plant.country, trade_of(plant.good)]
		var held: Array = national.get(key, [-1, 0])
		if int(held[0]) < 0 or int(held[1]) >= PLANTS_PER_COMPANY:
			held = [companies.size(), 0]
			companies.append({id = companies.size(), name = CompanyNames.producer(_place_word(plant), trade_of(plant.good), plant.country, rng, taken),
				country = plant.country, trade = trade_of(plant.good), global = false})
		plant.company = held[0]
		held[1] = int(held[1]) + 1
		national[key] = held


## A plant's yearly output at base prices.
func _value(plant: Dictionary) -> float:
	return float(plant.capacity) * float(GameData.commodity(plant.good).get("base", 0.0))


## The place word in a national company's name: its first plant's port or city.
func _place_word(plant: Dictionary) -> String:
	var name := GameData.port_name(plant.site) if plant.site_kind == "port" else str(WorldEconomy.city(plant.site).get("name", plant.site))
	var paren := name.find(" (")
	return name.substr(0, paren) if paren > 0 else name


func to_dict() -> Dictionary:
	return {companies = companies, plants = plants}


func from_dict(data: Dictionary) -> void:
	companies = data.get("companies", [])
	plants = data.get("plants", [])
	_at_site.clear()


## The plants at a site (a port id or a city id): indices into plants, the
## biggest first. Worked out once.
func plants_at(site: String) -> Array:
	if _at_site.is_empty() and not plants.is_empty():
		for i in plants.size():
			(_at_site.get_or_add(str(plants[i].site), []) as Array).append(i)
		for key: String in _at_site:
			(_at_site[key] as Array).sort_custom(func(a: int, b: int) -> bool: return float(plants[a].capacity) > float(plants[b].capacity))
	return _at_site.get(site, [])


## A plant's company.
func company_of(plant: Dictionary) -> Dictionary:
	var index := int(plant.get("company", -1))
	return companies[index] if index >= 0 and index < companies.size() else {}


## How many plants a company has.
func plant_count(company_index: int) -> int:
	var count := 0
	for plant: Dictionary in plants:
		if int(plant.company) == company_index:
			count += 1
	return count


## What kind of works a plant is, by its good: "Iron mine", "Wheat farm", "Steel mill"...
static func plant_title(plant: Dictionary) -> String:
	var good := str(plant.good)
	var name := str(GameData.commodity(good).get("name", good.capitalize()))
	var line := WorldEconomy.line_of(good)
	var kind := "works"
	match trade_of(good):
		"mining":
			kind = "mine"
		"energy":
			kind = "field" if good in ["oil", "gas"] else "refinery"
		"chemicals":
			kind = "plant"
		"forestry":
			kind = "sawmill"
		"metals":
			kind = "mill" if good == "steel" else "smelter"
		"farming":
			kind = "ranch" if line == "livestock" else ("orchard" if line == "produce" else "farm")
		"fishing":
			kind = "fishery"
		"manufacturing":
			kind = "factory"
	if good in ["cars", "trucks", "boats"] or Manufacturers.maker(good).size() > 0:
		kind = "factory"
	return "%s %s" % [name, kind]

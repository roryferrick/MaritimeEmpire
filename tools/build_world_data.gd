# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Builds data/countries.json and data/cities.json for the living world
## (DESIGN_LIVING_WORLD.md) from public datasets downloaded to a folder:
##   <raw>/naturalearth/ne_10m_populated_places_simple.dbf  (Natural Earth, public domain)
##   <raw>/worldbank/SP.POP.TOTL.json, NY.GDP.MKTP.CD.json, NY.GDP.PCAP.CD.json,
##     SP.URB.TOTL.IN.ZS.json (2016), tariff_2012_2019.json (TM.TAX.MRCH.WM.AR.ZS),
##     countries_meta.json  (World Bank API, CC BY 4.0)
##
##   Godot --headless --path . tools/build_world_data.tscn -- --raw <folder>
##
## Cities: every Natural Earth place whose name is in a port's name (within
## NAME_KM), else within PORT_KM of a port, joins that port's metro (its
## population); of the rest, every place over MIN_POP (and every capital over
## CAPITAL_MIN_POP) is an inland city, places within MERGE_KM of a bigger one
## merged into it. Each inland city is served by its nearest ports (its own
## country's first: CATCHMENT_PORTS of them, weighted by 1 / distance squared).
## Countries: every country with a port or an inland city, with 2016
## population, GDP, GDP a head, urban share and the average applied tariff of
## the year nearest 2016 (2012-2019), its trade bloc, and its internal trade
## zones (ZONES: big countries split by coastline; everyone else one zone).

const OUT_COUNTRIES := "res://data/countries.json"
const OUT_CITIES := "res://data/cities.json"
const MIN_POP := 750000
const CAPITAL_MIN_POP := 50000
const NAME_KM := 150.0
const PORT_KM := 50.0
const MERGE_KM := 25.0
const CATCHMENT_PORTS := 3
const CATCHMENT_KM := 2500.0
## A port with no Natural Earth place in reach: its town's people by size band.
const TOWN_BY_BAND := {small = 20000, medium = 60000, large = 150000, giant = 300000}
## Natural Earth spellings that differ from the ports' names.
const ALIASES := {"antwerpen": "antwerp", "bombay": "mumbai"}

## The ports' country names that aren't the World Bank's: name -> ISO3 ("" for none).
const COUNTRY_IDS := {
	"Antarctica": "ATA", "Azores": "PRT", "Bahamas": "BHS", "Brunei": "BRN", "Christmas Island": "AUS",
	"DR Congo": "COD", "Egypt": "EGY", "Galapagos": "ECU", "Gambia": "GMB", "Iran": "IRN", "Israel & Jordan": "ISR",
	"Ivory Coast": "CIV", "Madeira": "PRT", "North Korea": "PRK", "Puerto Rico": "PRI", "Republic of the Congo": "COG",
	"Russia": "RUS", "Somalia": "SOM", "South Korea": "KOR", "St Pierre and Miquelon": "FRA", "Svalbard": "NOR",
	"Syria": "SYR", "Taiwan": "TWN", "Turkey": "TUR", "Venezuela": "VEN", "Vietnam": "VNM", "Yemen": "YEM",
}
## Short names for the World Bank's long ones (ISO3 -> name).
const SHORT_NAMES := {
	"RUS": "Russia", "KOR": "South Korea", "PRK": "North Korea", "IRN": "Iran", "EGY": "Egypt", "VEN": "Venezuela",
	"VNM": "Vietnam", "YEM": "Yemen", "SYR": "Syria", "TUR": "Turkey", "COD": "DR Congo", "COG": "Republic of the Congo",
	"CIV": "Ivory Coast", "GMB": "Gambia", "BHS": "Bahamas", "BRN": "Brunei", "HKG": "Hong Kong", "MAC": "Macau",
	"LAO": "Laos", "KGZ": "Kyrgyzstan", "SVK": "Slovakia", "CZE": "Czechia", "MKD": "North Macedonia", "FSM": "Micronesia",
	"SOM": "Somalia", "PRI": "Puerto Rico", "LCA": "St Lucia", "VCT": "St Vincent", "KNA": "St Kitts and Nevis", "PSE": "Palestine", "USA": "United States",
}
## Places the World Bank doesn't cover: ISO3 -> {name, population, gdp_usd} (2016).
const EXTRA_COUNTRIES := {
	"TWN": {name = "Taiwan", population = 23540000, gdp_usd = 543000000000.0, urban = 78.0, tariff = 1.9},
	"ATA": {name = "Antarctica", population = 4000, gdp_usd = 0.0, urban = 0.0, tariff = 0.0},
}
## Natural Earth's country codes that differ from the World Bank's (ISO3).
const NE_CODES := {"SDS": "SSD", "KOS": "XKX", "SAH": "ESH", "PSX": "PSE", "CYN": "CYP", "SOL": "SOM", "KAS": "IND"}
## The European Union in 2016 (tariff-free inside; one outside tariff).
const EU := ["AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC", "HUN", "IRL", "ITA", "LVA",
	"LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE", "GBR"]
## Big countries' internal trade zones, split by coastline: ISO3 -> [[id, name, ports]].
const ZONES := {
	"USA": [["east", "East Coast", ["NYC", "SAV", "CHS", "ORF", "BOS", "MIA", "PWM", "BAL", "PHL", "JAX"]],
		["gulf", "Gulf Coast", ["HOU", "MSY", "MOB"]],
		["west", "West Coast, Alaska and Hawaii", ["LGB", "SEA", "OAK", "MRY", "ANC", "JNU", "DUT", "SCC", "HNL", "LIH", "ITO", "KWH", "MDY"]],
		["lakes", "Great Lakes", ["CHI", "DLH", "DET", "CLE", "MKE", "TOL", "GRY", "TWH", "MQT", "CAL", "BUF"]]],
	"CHN": [["north", "North China", ["TSN", "DLC", "YIK", "YNT", "TAO", "RZH", "LYG"]],
		["east", "East China", ["SHA", "NGB", "TAC", "FOC", "XMN", "QZJ"]],
		["south", "South China", ["SZX", "CAN", "QZH"]]],
	"RUS": [["west", "Baltic and Arctic", ["LED", "ULU", "MMK", "ARH", "SBT", "DUD"]],
		["south", "Black Sea", ["NVS"]],
		["east", "Far East", ["VVO", "KRS", "PKC", "GDX", "VYP", "VNN", "TIK", "PWE"]]],
	"BRA": [["south", "South and Southeast", ["SSZ", "PNG", "RIO", "ITJ", "RIG", "VIX"]],
		["north", "North and Northeast", ["SSA", "FOR", "SUA", "VDC"]]],
	"CAN": [["west", "Pacific", ["YVR"]],
		["central", "Great Lakes and Hudson Bay", ["TOR", "YHM", "YQT", "YYQ"]],
		["east", "Atlantic and Arctic", ["YHZ", "YDP", "YFB", "YRB"]]],
	"IND": [["west", "West Coast", ["MUN", "JNP", "HZR", "COK"]],
		["east", "East Coast", ["MAA", "CCU", "VTZ", "PRT"]]],
	"AUS": [["east", "East and South", ["MEL", "SYD", "BNE", "ADL", "XCH"]],
		["west", "West and North", ["FRE", "DRW"]]],
}
## Ports whose country is its own customs territory, not ports.json's country: port id -> ISO3.
const PORT_COUNTRY_OVERRIDES := {"HKG": "HKG"}

const OUT_PRODUCTION := "res://data/production.json"
## The hand-compiled figures (minerals, metals, energy, seafood, vehicles; manufacturing tilts).
const Sources := preload("res://tools/world_data_sources.gd")
## FAOSTAT's names that aren't the World Bank's: ISO3 -> FAO area. (FAO's
## "China" is mainland, Hong Kong, Macao and Taiwan together: not used.)
const FAO_AREAS := {
	"BOL": "Bolivia (Plurinational State of)", "COD": "Democratic Republic of the Congo", "COG": "Congo",
	"HKG": "China, Hong Kong SAR", "CHN": "China, mainland", "TWN": "China, Taiwan Province of", "MAC": "China, Macao SAR",
	"IRN": "Iran (Islamic Republic of)", "CIV": "Côte d'Ivoire", "LAO": "Lao People's Democratic Republic",
	"MDA": "Republic of Moldova", "NLD": "Netherlands (Kingdom of the)", "PRK": "Democratic People's Republic of Korea",
	"KOR": "Republic of Korea", "PRI": "Puerto Rico", "SOM": "Somalia", "TZA": "United Republic of Tanzania",
	"TUR": "Türkiye", "GBR": "United Kingdom of Great Britain and Northern Ireland", "USA": "United States of America",
	"VEN": "Venezuela (Bolivarian Republic of)", "VNM": "Viet Nam", "RUS": "Russian Federation", "SYR": "Syrian Arab Republic",
	"EGY": "Egypt", "YEM": "Yemen", "GMB": "Gambia", "BHS": "Bahamas", "BRN": "Brunei Darussalam", "CZE": "Czechia",
	"SVK": "Slovakia", "KGZ": "Kyrgyzstan", "FSM": "Micronesia (Federated States of)", "LCA": "Saint Lucia",
	"VCT": "Saint Vincent and the Grenadines", "KNA": "Saint Kitts and Nevis", "PSE": "Palestine",
}
## Each game good FAOSTAT counts (2016): good -> [FAO item, element code, unit].
## Element 5510: production in tonnes; 5111: live animals (stocks), head.
const FAO_GOODS := {
	"wheat": ["Wheat", 5510, "t"], "corn": ["Maize (corn)", 5510, "t"], "soybeans": ["Soya beans", 5510, "t"],
	"rice": ["Rice", 5510, "t"], "barley": ["Barley", 5510, "t"], "coffee": ["Coffee, green", 5510, "t"],
	"cocoa": ["Cocoa beans", 5510, "t"], "tea": ["Tea leaves", 5510, "t"], "sugarcane": ["Sugar cane", 5510, "t"],
	"pepper": ["Pepper (Piper spp.), raw", 5510, "t"], "vanilla": ["Vanilla, raw", 5510, "t"],
	"cinnamon": ["Cinnamon and cinnamon-tree flowers, raw", 5510, "t"], "almonds": ["Almonds, in shell", 5510, "t"],
	"olives": ["Olives", 5510, "t"], "dates": ["Dates", 5510, "t"], "cotton": ["Seed cotton, unginned", 5510, "t"],
	"rubber": ["Natural rubber in primary forms", 5510, "t"], "apples": ["Apples", 5510, "t"], "pears": ["Pears", 5510, "t"],
	"cherries": ["Cherries", 5510, "t"], "peaches": ["Peaches and nectarines", 5510, "t"], "strawberries": ["Strawberries", 5510, "t"],
	"blueberries": ["Blueberries", 5510, "t"], "raspberries": ["Raspberries", 5510, "t"],
	"blackberries": ["Other berries and fruits of the genus vaccinium n.e.c.", 5510, "t"], "cranberries": ["Cranberries", 5510, "t"],
	"oranges": ["Oranges", 5510, "t"], "lemons": ["Lemons and limes", 5510, "t"], "bananas": ["Bananas", 5510, "t"],
	"mangoes": ["Mangoes, guavas and mangosteens", 5510, "t"], "pineapples": ["Pineapples", 5510, "t"], "avocados": ["Avocados", 5510, "t"],
	"grapes": ["Grapes", 5510, "t"], "potatoes": ["Potatoes", 5510, "t"], "tomatoes": ["Tomatoes", 5510, "t"],
	"onions": ["Onions and shallots, dry (excluding dehydrated)", 5510, "t"], "lettuce": ["Lettuce and chicory", 5510, "t"],
	"peppers": ["Chillies and peppers, green (Capsicum spp. and Pimenta spp.)", 5510, "t"],
	"cows": ["Cattle", 5111, "head"], "sheep": ["Sheep", 5111, "head"], "pigs": ["Swine / pigs", 5111, "head"], "horses": ["Horses", 5111, "head"],
}

var _raw := ""


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var at := args.find("--raw")
	if at < 0 or at + 1 >= args.size():
		push_error("build_world_data: pass -- --raw <folder>")
		get_tree().quit(1)
		return
	_raw = args[at + 1]
	var meta := _wb_meta()
	var pop := _wb_values("SP.POP.TOTL.json")
	var gdp := _wb_values("NY.GDP.MKTP.CD.json")
	var per_head := _wb_values("NY.GDP.PCAP.CD.json")
	var urban := _wb_values("SP.URB.TOTL.IN.ZS.json")
	var tariff := _wb_nearest_2016("tariff_2012_2019.json")
	var wb_ids := {}  # World Bank name -> ISO3.
	for id: String in meta:
		wb_ids[str(meta[id].name)] = id
	# The ports, with their country's ISO3.
	var ports: Array = []
	for port: Dictionary in GameData.ports:
		var name := str(port.country)
		var id := str(COUNTRY_IDS.get(name, wb_ids.get(name, "")))
		id = str(PORT_COUNTRY_OVERRIDES.get(port.id, id))
		if id.is_empty():
			push_warning("No country id for %s (%s)" % [port.id, name])
		ports.append({id = str(port.id), name = str(port.name), country = id, lat = float(port.lat), lon = float(port.lon)})
	var places := _places()
	var split := _split(places, ports)
	var inland: Array = split.inland
	var metro: Dictionary = split.metro
	# The countries: every one with a port or an inland city.
	var used := {}
	for port: Dictionary in ports:
		used[port.country] = true
	for city: Dictionary in inland:
		used[city.country] = true
	used.erase("")
	var countries := []
	for id: String in used:
		var extra: Dictionary = EXTRA_COUNTRIES.get(id, {})
		if not meta.has(id) and extra.is_empty():
			push_warning("No figures for country %s" % id)
			continue
		var entry := {
			id = id,
			name = str(extra.get("name", SHORT_NAMES.get(id, meta.get(id, {}).get("name", id)))),
			population = int(extra.get("population", pop.get(id, 0))),
			gdp_usd = roundf(float(extra.get("gdp_usd", gdp.get(id, 0.0))) / 1e6) * 1e6,
			gdp_per_head = roundi(float(per_head.get(id, 0.0))) if extra.is_empty() else roundi(float(extra.gdp_usd) / maxf(float(extra.population), 1.0)),
			urban_share = snappedf(float(extra.get("urban", urban.get(id, 50.0))) / 100.0, 0.001),
			tariff = snappedf(float(extra.get("tariff", tariff.get(id, 5.0))) / 100.0, 0.0001),
			bloc = "EU" if EU.has(id) else "",
			region = str(meta.get(id, {}).get("region", "")),
			income = str(meta.get(id, {}).get("income", "")),
			currency_strength = 1.0,
		}
		var zones := []
		var zone_of_port := {}
		for zone: Array in ZONES.get(id, []):
			zones.append({id = zone[0], name = zone[1], ports = zone[2]})
			for port_id: String in zone[2]:
				zone_of_port[port_id] = zone[0]
		var own_ports := ports.filter(func(port: Dictionary) -> bool: return port.country == id)
		if zones.is_empty():
			zones.append({id = "all", name = entry.name, ports = own_ports.map(func(port: Dictionary) -> String: return port.id)})
		else:
			for port: Dictionary in own_ports:
				if not zone_of_port.has(port.id):
					push_warning("Port %s (%s) is in no zone" % [port.id, id])
		entry.zones = zones
		countries.append(entry)
	countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.name < b.name)
	var country_ids := {}
	for entry: Dictionary in countries:
		country_ids[entry.id] = entry
	# Each inland city's zone and catchment ports.
	for city: Dictionary in inland:
		var catchment := _catchment(city, ports)
		city.ports = catchment
		city.zone = _zone_of(country_ids.get(city.country, {}), catchment)
	var port_people := {}
	for port: Dictionary in ports:
		var people := int(metro.get(port.id, {}).get("population", 0))
		var places_of: Array = metro.get(port.id, {}).get("places", [])
		if people <= 0:
			people = int(TOWN_BY_BAND.get(GameState.port_sizes.band(port.id), 20000))
		port_people[port.id] = {country = port.country, population = people, places = places_of}
	_write(OUT_COUNTRIES, {
		_comment = "Countries for the living world (tools/build_world_data.gd; DESIGN_LIVING_WORLD.md). Every country with a port or an inland city: 2016 population, GDP (US$), GDP a head, urban share and average applied tariff (the year nearest 2016, 2012-2019) from the World Bank (CC BY 4.0), Taiwan's and Antarctica's by hand; bloc (EU: tariff-free inside); currency_strength (1 to start, moves with the economy); zones: its internal trade zones (goods move freely inside a zone; big countries split by coastline), each with its ports. port_countries: the ports' country ids (a port can be its own customs territory, like Hong Kong).",
		countries = countries,
		port_countries = _port_countries(ports),
	})
	_write(OUT_CITIES, {
		_comment = "People for the living world (tools/build_world_data.gd). cities: inland cities (Natural Earth populated places, public domain, over %d people, and every capital over %d, places within %d km merged into the bigger), each with its country, zone, and the ports that serve it (its own country's first, up to %d within %d km, weighted by 1 / distance squared) until land transport exists. ports: each port's own metro (the Natural Earth places whose name is in its name within %d km, or within %d km of it; a port with none, a town by its size band)." % [MIN_POP, CAPITAL_MIN_POP, MERGE_KM, CATCHMENT_PORTS, CATCHMENT_KM, NAME_KM, PORT_KM],
		cities = inland,
		ports = port_people,
	})
	print("%d countries, %d inland cities, %d ports with metros" % [countries.size(), inland.size(), metro.size()])
	_build_production(countries, meta)
	get_tree().quit()


# --- Production ---------------------------------------------------------------------

## data/production.json: each good's 2016 output by country, in its real unit.
func _build_production(countries: Array, meta: Dictionary) -> void:
	var goods := {}
	var fao := _fao(countries, meta)
	for good: String in FAO_GOODS:
		goods[good] = {unit = FAO_GOODS[good][2], source = "FAOSTAT 2016", countries = fao.get(good, {})}
	var missing := FAO_GOODS.keys().filter(func(good: String) -> bool: return (goods[good].countries as Dictionary).is_empty())
	if not missing.is_empty():
		push_warning("No FAO figures for: %s" % ", ".join(PackedStringArray(missing)))
	var ours := {}
	for entry: Dictionary in countries:
		ours[entry.id] = true
	var dropped := {}
	for good: String in Sources.GOODS:
		var source: Array = Sources.GOODS[good]
		goods[good] = {unit = source[0], source = "hand-compiled 2016 (tools/world_data_sources.gd)", countries = _ours(source[1], ours, dropped)}
	for good: String in Sources.REFINED_SHARES:
		var share := float(Sources.REFINED_SHARES[good])
		var amounts := {}
		for id: String in Sources.REFINING:
			amounts[id] = roundf(float(Sources.REFINING[id]) * share)
		goods[good] = {unit = "t", source = "2016 refinery runs x a typical product share", countries = _ours(amounts, ours, dropped)}
	var mva := _wb_values("NV.IND.MANF.CD.json")
	for good: String in Sources.SPECIALTIES:
		var tilt: Dictionary = Sources.SPECIALTIES[good]
		var weights := {}
		var total := 0.0
		for id: String in ours:
			var weight := float(mva.get(id, 0.0)) * float(tilt.get(id, Sources.OTHER_WEIGHT))
			if weight > 0.0:
				weights[id] = weight
				total += weight
		var shares := {}
		for id: String in weights:
			var share := float(weights[id]) / total
			if share >= 0.001:
				shares[id] = snappedf(share, 0.0001)
		goods[good] = {unit = "share", source = "2016 manufacturing value added (World Bank) tilted by specialty", countries = shares}
	if not dropped.is_empty():
		push_warning("Producers with no port or inland city, left out: %s" % ", ".join(PackedStringArray(dropped.keys())))
	var unknown := GameData.commodities.map(func(each: Dictionary) -> String: return str(each.id)).filter(func(id: String) -> bool:
		return not goods.has(id) and not GameData.commodity(id).get("maker", false))
	if not unknown.is_empty():
		push_warning("Goods with no production figures: %s" % ", ".join(PackedStringArray(unknown)))
	_write(OUT_PRODUCTION, {
		_comment = "Each good's 2016 output by country (tools/build_world_data.gd), in its real unit (t: tonnes; t_metal: tonnes of metal in the ore; t_oxide: tonnes of rare earth oxide; head: live animals; m3; units: vehicles and boats; share: of world output, for manufactured goods spread by manufacturing value added), for the living world's producers (DESIGN_LIVING_WORLD.md). Crops and livestock from FAOSTAT (FAO, CC BY 4.0); minerals, metals, energy, seafood and vehicles hand-compiled from published 2016 figures (tools/world_data_sources.gd); refined fuels from refinery runs; manufactured goods from the World Bank's manufacturing value added (CC BY 4.0).",
		goods = goods,
	})


## A good's amounts for our countries only, noting the producers left out.
func _ours(amounts: Dictionary, ours: Dictionary, dropped: Dictionary) -> Dictionary:
	var out := {}
	for id: String in amounts:
		if ours.has(id):
			out[id] = float(amounts[id])
		else:
			dropped[id] = true
	return out


## FAOSTAT's 2016 figures for FAO_GOODS: good -> {ISO3: amount}, our countries only.
func _fao(countries: Array, meta: Dictionary) -> Dictionary:
	var area_ids := {}  # FAO area name -> ISO3.
	for entry: Dictionary in countries:
		area_ids[str(FAO_AREAS.get(entry.id, meta.get(entry.id, {}).get("name", entry.name)))] = entry.id
		if not FAO_AREAS.has(entry.id):
			area_ids[str(entry.name)] = entry.id
	var wanted := {}  # "item|element" -> good.
	for good: String in FAO_GOODS:
		wanted["%s|%d" % [FAO_GOODS[good][0], FAO_GOODS[good][1]]] = good
	var file := FileAccess.open(_raw.path_join("fao").path_join("Production_Crops_Livestock_E_All_Data_NOFLAG.csv"), FileAccess.READ)
	if file == null:
		push_error("No FAOSTAT file")
		return {}
	var header := file.get_csv_line()
	var area_at := header.find("Area")
	var item_at := header.find("Item")
	var element_at := header.find("Element Code")
	var year_at := header.find("Y2016")
	var out := {}
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() <= year_at:
			continue
		var good: String = wanted.get("%s|%s" % [row[item_at], row[element_at]], "")
		var id: String = area_ids.get(row[area_at], "")
		if good.is_empty() or id.is_empty() or row[year_at].is_empty():
			continue
		(out.get_or_add(good, {}) as Dictionary)[id] = roundf(float(row[year_at]))
	return out


# --- Sources -------------------------------------------------------------------

## World Bank countries (not aggregates): ISO3 -> {name, region, income}.
func _wb_meta() -> Dictionary:
	var out := {}
	for row: Dictionary in _wb_rows("countries_meta.json"):
		if str(row.get("region", {}).get("value", "")) == "Aggregates":
			continue
		out[str(row.id)] = {name = str(row.name), region = str(row.region.value), income = str(row.get("incomeLevel", {}).get("value", ""))}
	return out


## An indicator's 2016 values: ISO3 -> value (countries with one).
func _wb_values(file: String) -> Dictionary:
	var out := {}
	for row: Dictionary in _wb_rows(file):
		if row.get("value") != null and not str(row.get("countryiso3code", "")).is_empty():
			out[str(row.countryiso3code)] = float(row.value)
	return out


## An indicator's value from the year nearest 2016 (later wins a tie): ISO3 -> value.
func _wb_nearest_2016(file: String) -> Dictionary:
	var best := {}  # ISO3 -> [distance, value]
	for row: Dictionary in _wb_rows(file):
		var id := str(row.get("countryiso3code", ""))
		if row.get("value") == null or id.is_empty():
			continue
		var year := int(row.date)
		var distance := absf(year - 2016) - (0.1 if year > 2016 else 0.0)
		if not best.has(id) or distance < float(best[id][0]):
			best[id] = [distance, float(row.value)]
	var out := {}
	for id: String in best:
		out[id] = best[id][1]
	return out


func _wb_rows(file: String) -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_raw.path_join("worldbank").path_join(file)))
	return data[1] if data is Array and (data as Array).size() > 1 and data[1] is Array else []


## Natural Earth's populated places: [{name, ascii, country (ISO3), adm1, lat, lon, population, capital}].
func _places() -> Array:
	var rows := _dbf(_raw.path_join("naturalearth").path_join("ne_10m_populated_places_simple.dbf"))
	var out := []
	for row: Dictionary in rows:
		var code := str(row.get("adm0_a3", ""))
		out.append({name = str(row.name), ascii = str(row.nameascii).to_lower(), country = str(NE_CODES.get(code, code)),
			adm1 = str(row.adm1name), lat = float(row.latitude), lon = float(row.longitude), population = int(float(row.pop_max)),
			capital = str(row.adm0cap) == "1"})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.population > b.population)
	return out


## A dBase III table's rows: [{field: text}].
func _dbf(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Can't read %s" % path)
		return []
	file.seek(4)
	var count := file.get_32()
	var header := file.get_16()
	var record := file.get_16()
	var fields := []
	file.seek(32)
	while true:
		var first := file.get_8()
		if first == 0x0D:
			break
		var rest := file.get_buffer(31)
		var name_bytes := PackedByteArray([first]) + rest.slice(0, 10)
		var end := name_bytes.find(0)
		fields.append([name_bytes.slice(0, end if end >= 0 else 11).get_string_from_ascii(), int(rest[15])])
	var out := []
	for i in count:
		file.seek(header + i * record)
		var data := file.get_buffer(record)
		if data[0] == 0x2A:
			continue  # Deleted.
		var row := {}
		var at := 1
		for field: Array in fields:
			row[field[0]] = data.slice(at, at + int(field[1])).get_string_from_utf8().strip_edges()
			at += int(field[1])
		out.append(row)
	return out


# --- Working it out --------------------------------------------------------------

## The places shared out: {inland: [cities], metro: {port id: {population, places}}}.
func _split(places: Array, ports: Array) -> Dictionary:
	var metro := {}
	var inland := []
	for place: Dictionary in places:
		var owner := _named_port(place, ports)
		if owner.is_empty():
			var nearest := ""
			var nearest_km := INF
			for port: Dictionary in ports:
				var km := _km(place.lat, place.lon, port.lat, port.lon)
				if km < nearest_km:
					nearest_km = km
					nearest = port.id
			if nearest_km < PORT_KM:
				owner = nearest
		if not owner.is_empty():
			var entry: Dictionary = metro.get_or_add(owner, {population = 0, places = []})
			entry.population = int(entry.population) + int(place.population)
			if int(place.population) >= 100000:
				(entry.places as Array).append(place.name)
			continue
		if int(place.population) < MIN_POP and not (place.capital and int(place.population) >= CAPITAL_MIN_POP):
			continue
		if inland.any(func(city: Dictionary) -> bool: return _km(place.lat, place.lon, city.lat, city.lon) < MERGE_KM):
			continue
		inland.append({id = _city_id(place, inland), name = place.name, country = place.country, region = place.adm1,
			lat = snappedf(place.lat, 0.0001), lon = snappedf(place.lon, 0.0001), population = place.population, capital = place.capital})
	return {inland = inland, metro = metro}


## The port whose name has this place's name in it, within NAME_KM, or "".
func _named_port(place: Dictionary, ports: Array) -> String:
	var names := [str(place.ascii), str(place.name).to_lower(), str(ALIASES.get(place.ascii, ""))].filter(func(each: String) -> bool: return each.length() > 2)
	for port: Dictionary in ports:
		var port_name := str(port.name).to_lower()
		for each: String in names:
			if _has_word(port_name, each) and _km(place.lat, place.lon, port.lat, port.lon) < NAME_KM:
				return port.id
	return ""


## True if a word (or words) appears in a text with no letter either side.
static func _has_word(text: String, word: String) -> bool:
	var at := text.find(word)
	while at >= 0:
		var before := text[at - 1] if at > 0 else " "
		var after := text[at + word.length()] if at + word.length() < text.length() else " "
		if not _is_letter(before) and not _is_letter(after):
			return true
		at = text.find(word, at + 1)
	return false


static func _is_letter(c: String) -> bool:
	return c.to_lower() != c.to_upper() or (c >= "0" and c <= "9")


## A city's serving ports: its own country's nearest within CATCHMENT_KM (else
## any country's), up to CATCHMENT_PORTS, [[port id, share]] summing to 1.
func _catchment(city: Dictionary, ports: Array) -> Array:
	var near := []
	for port: Dictionary in ports:
		var km := _km(city.lat, city.lon, port.lat, port.lon)
		if km < CATCHMENT_KM:
			near.append([port.id, km, port.country == city.country])
	var own := near.filter(func(each: Array) -> bool: return each[2])
	var pick := own if not own.is_empty() else near
	pick.sort_custom(func(a: Array, b: Array) -> bool: return a[1] < b[1])
	pick = pick.slice(0, CATCHMENT_PORTS)
	if pick.is_empty():
		return []
	var total := 0.0
	for each: Array in pick:
		total += 1.0 / pow(maxf(float(each[1]), 10.0), 2.0)
	return pick.map(func(each: Array) -> Array: return [each[0], snappedf(1.0 / pow(maxf(float(each[1]), 10.0), 2.0) / total, 0.001)])


## The zone of a city's country its nearest serving port is in ("all" for a country of one zone).
func _zone_of(country: Dictionary, catchment: Array) -> String:
	var zones: Array = country.get("zones", [])
	if zones.size() <= 1:
		return "all"
	for each: Array in catchment:
		for zone: Dictionary in zones:
			if (zone.ports as Array).has(each[0]):
				return zone.id
	return str(zones[0].id)


func _port_countries(ports: Array) -> Dictionary:
	var out := {}
	for port: Dictionary in ports:
		out[port.id] = port.country
	return out


## "madrid", or "madrid_es" where the name's taken.
func _city_id(place: Dictionary, cities: Array) -> String:
	var base := str(place.ascii).replace(" ", "_").replace("'", "").replace("-", "_").replace(".", "")
	var id := base
	var n := 2
	while cities.any(func(city: Dictionary) -> bool: return city.id == id):
		id = "%s_%s%s" % [base, str(place.country).to_lower(), "" if n == 2 else str(n)]
		n += 1
	return id


static func _km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
	var r := PI / 180.0
	var x := pow(sin((lat2 - lat1) * r / 2.0), 2.0) + cos(lat1 * r) * cos(lat2 * r) * pow(sin((lon2 - lon1) * r / 2.0), 2.0)
	return 12742.0 * atan2(sqrt(x), sqrt(1.0 - x))


func _write(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t", false))
	print("wrote ", path)

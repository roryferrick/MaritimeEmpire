# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Backstories
## Backstory starts (data/backstories.json; DESIGN_LIVING_WORLD.md): the New
## Company screen offers a start at each of a company type's recommended
## ports, each an archetype picked by the port (the same every game) and told
## in three or four sentences assembled from the archetype's parts. A start
## is {id, type, port, kind, archetype, money, debt, investors {stake, name},
## ships [{model, name, condition, age_hours}], relations {countries {id:
## value}, firm_value}, traits}; GameState.new_game() applies it (apply()).
## The player can also take a custom start (custom()): a port, a money preset
## and their own story, no traits or relations.

const PATH := "res://data/backstories.json"
## The custom start's money choices.
const CUSTOM_MONEY := [1000000, 2500000, 5000000]
## What the money was, in words, by the investors' kind.
const BACKERS := {investors = ["Harbourside Capital", "Meridian Partners", "the Quayside syndicate", "Northstar Holdings", "the Albatross fund"],
	foreign = ["a Singapore trading house", "a Hamburg trading house", "a Piraeus shipping family", "a Hong Kong trading house", "a Rotterdam commodities house"],
	fund = ["Blue Water Ventures", "the Tidewater fund", "Compass Ventures", "the Longitude fund"]}

static var _data := {}
static var _cache := {}  # type id -> starts


static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


static func archetype(id: String) -> Dictionary:
	for each: Dictionary in data().get("archetypes", []):
		if each.id == id:
			return each
	return {}


## Every start of a company type, by port: {port id: start}. The same each game.
static func for_type(type_id: String) -> Dictionary:
	if _cache.has(type_id):
		return _cache[type_id]
	var starts := {}
	var archetypes: Array = data().get("archetypes", [])
	var kinds: Dictionary = data().get("kind_money", {})
	var ports := []  # [port, kind]
	for kind: String in GameData.START_KINDS:
		for entry: Dictionary in GameData.start_list(kind, type_id):
			ports.append([str(entry.port), kind])
	for port_id: String in GameData.starts.get("great_lakes", {}).get("ports", []):
		ports.append([port_id, "great_lakes"])
	# Each port its archetype in turn (shuffled by the type), so every archetype
	# turns up and no two neighbours in the list share one.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(type_id) + 7
	var order := range(archetypes.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var kept: int = order[i]
		order[i] = order[j]
		order[j] = kept
	for k in ports.size():
		var port_id: String = ports[k][0]
		var kind: String = ports[k][1]
		var arch: Dictionary = archetypes[order[k % order.size()]]
		var seeded := RandomNumberGenerator.new()
		seeded.seed = hash("%s|%s|%s" % [type_id, port_id, arch.id])
		starts[port_id] = _make(type_id, port_id, kind, arch, float(kinds.get(kind, 1.0)), seeded)
	_cache[type_id] = starts
	return starts


static func _pick(span: Variant, rng: RandomNumberGenerator) -> float:
	if span is Array and (span as Array).size() == 2:
		return rng.randf_range(float(span[0]), float(span[1]))
	return float(span)


static func _make(type_id: String, port_id: String, kind: String, arch: Dictionary, scale: float, rng: RandomNumberGenerator) -> Dictionary:
	var start := {id = "%s|%s" % [type_id, port_id], type = type_id, port = port_id, kind = kind, archetype = str(arch.id), name = str(arch.name),
		money = _round_money(_pick(arch.get("money", 2500000), rng) * scale), debt = 0, investors = {}, ships = [], relations = {countries = {}, firm = 0}, traits = []}
	if arch.has("debt"):
		start.debt = _round_money(_pick(arch.debt, rng) * scale)
	if arch.has("investors"):
		var info: Dictionary = arch.investors
		var names: Array = BACKERS.get(str(info.get("backer", "investors")), ["investors"])
		start.investors = {stake = snappedf(_pick(info.get("stake", 0.3), rng), 0.01), name = str(names[rng.randi() % names.size()])}
	var models := first_models(type_id)
	for ship_info: Dictionary in arch.get("ships", []):
		var which := 1 if str(ship_info.get("model", "first")) == "second" and models.size() > 1 else 0
		if models.is_empty():
			break
		start.ships.append({model = str(models[which].id), name = _ship_name(str(ship_info.get("name", "own")), port_id, rng),
			condition = snappedf(_pick(ship_info.get("condition", [0.6, 0.8]), rng), 0.01), age_hours = roundi(_pick(ship_info.get("age_hours", [1000, 4000]), rng))})
	var relations: Dictionary = arch.get("relations", {})
	var country: String = GameState.world.country_of_port(port_id)
	if relations.has("home") and not country.is_empty():
		start.relations.countries[country] = int(relations.home)
	if relations.has("neighbours"):
		start.relations.neighbours = int(relations.neighbours)  # (Resolved to the countries round the home when the game begins.)
	if relations.has("firm"):
		start.relations.firm = int(relations.firm)
	var pool: Array = arch.get("traits", []).duplicate()
	var count := int(arch.get("traits_count", 2))
	while start.traits.size() < count and not pool.is_empty():
		var pick: String = pool[rng.randi() % pool.size()]
		pool.erase(pick)
		if start.traits.any(func(id: String) -> bool: return id in Traits.info(pick).get("opposites", []) or pick in Traits.info(id).get("opposites", [])):
			continue
		start.traits.append(pick)
	return start


static func _round_money(amount: float) -> int:
	return roundi(amount / 50000.0) * 50000


## A company type's first-tier models (the cheapest of each of its categories, cheapest first).
static func first_models(type_id: String) -> Array:
	var categories: Array = Progression.company_type(type_id).get("categories", [])
	var cheapest := {}
	for model: Dictionary in GameData.ship_models:
		var category := str(model.get("category", ""))
		if not category in categories or model.get("coming_soon", false) or model.get("legacy", false):
			continue
		if not cheapest.has(category) or int(model.get("price", 0)) < int(cheapest[category].get("price", 0)):
			cheapest[category] = model
	var out: Array = cheapest.values()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("price", 0)) < int(b.get("price", 0)))
	return out


static func _ship_name(kind: String, port_id: String, rng: RandomNumberGenerator) -> String:
	var port_name := GameData.port_name(port_id).get_slice(" (", 0).get_slice(",", 0)
	match kind:
		"family":
			return ["%s Pride" % port_name, "Old %s" % port_name, "%s Star" % port_name, "Spirit of %s" % port_name][rng.randi() % 4]
		"auction":
			return ["Lot %d" % (rng.randi() % 40 + 7), "Second Chance", "Creditor's Rest", "Bargain", "Hammer Price"][rng.randi() % 5]
		"yard":
			return ["Reprieve", "Not Yet", "Last Voyage", "Phoenix"][rng.randi() % 4]
		"partner":
			return ["Settlement", "Fair Share", "Quarter Moon", "Good Faith"][rng.randi() % 4]
	return ["%s Dawn" % port_name, "%s Trader" % port_name, "Sea Change", "First Light", "Long Haul"][rng.randi() % 5]


## A start's story, three or four sentences, with the CEO's name in it.
static func story(start: Dictionary, ceo_name: String) -> String:
	if str(start.get("archetype", "")).is_empty():
		return str(start.get("story", "A company of your own, with your own money, starting at %s." % GameData.port_name(str(start.port))))
	var arch := archetype(str(start.archetype))
	var port := GameData.get_port(str(start.port))
	var country := str(port.get("country", ""))
	var ships := PackedStringArray()
	for ship: Dictionary in start.ships:
		ships.append("%s (a %s)" % [str(ship.name), str(GameData.get_ship_model(str(ship.model)).get("name", ship.model))])
	var firm := _firm_name_for(str(start.port))
	var words := {ceo = ceo_name if not ceo_name.is_empty() else "the founder", port = GameData.port_name(str(start.port)), country = country if not country.is_empty() else "the country",
		money = Fmt.money(int(start.money)), debt = Fmt.money(int(start.get("debt", 0))), stake = "%d%%" % roundi(float((start.get("investors", {}) as Dictionary).get("stake", 0.0)) * 100.0),
		ship = ships[0] if not ships.is_empty() else "the ship", ships = " and ".join(ships) if not ships.is_empty() else "the ships",
		backer = str((start.get("investors", {}) as Dictionary).get("name", "the investors")), firm = firm,
		trait_line = Traits.story_line(str(start.traits[0]), ceo_name.get_slice(" ", 0) if not ceo_name.is_empty() else "The founder") if not (start.traits as Array).is_empty() else ""}
	var out := PackedStringArray()
	for sentence: String in arch.get("story", []):
		var text := sentence
		for key: String in words:
			if key != "ceo":
				text = text.replace("{%s}" % key, str(words[key]))
		text = text.replace("{trait}", str(words.trait_line))
		if not text.strip_edges().is_empty():
			out.append(text)
	# The founder's full name the first time, the first name after.
	var full := str(words.ceo)
	var first := full.get_slice(" ", 0)
	var surname := full.get_slice(" ", full.get_slice_count(" ") - 1)
	var joined := " ".join(out).replace("{surname}", surname)
	var at := joined.find("{ceo}")
	if at >= 0:
		joined = joined.substr(0, at) + full + joined.substr(at + 5)
	return joined.replace("{ceo}", first)


## The biggest paper firm based in a port's country (its name), or a made-up one before the world exists.
static func _firm_name_for(port_id: String) -> String:
	var country: String = GameState.world.country_of_port(port_id)
	var firms: ShippingFirms = GameState.firms
	var best := {}
	for firm: Dictionary in firms.firms:
		if firm.country == country and (best.is_empty() or float(firm.size) > float(best.size)):
			best = firm
	if not best.is_empty():
		return str(best.name)
	return "the port's biggest line"


## A custom start: the player's own port, money and story.
static func custom(type_id: String, port_id: String, money: int, text := "") -> Dictionary:
	return {id = "custom|%s" % port_id, type = type_id, port = port_id, kind = str(GameData.start_info(port_id, type_id).get("kind", "")), archetype = "", name = "Your own start",
		money = money, debt = 0, investors = {}, ships = [], relations = {countries = {}, firm = 0}, traits = [], story = text}


## What a start gives, in a few short lines (the picker's card).
static func summary(start: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("%s to start" % Fmt.money(int(start.money)))
	if int(start.get("debt", 0)) > 0:
		lines.append("%s of it owed to the bank" % Fmt.money(int(start.debt)))
	var investors: Dictionary = start.get("investors", {})
	if not investors.is_empty():
		lines.append("%s hold %d%% of the company" % [str(investors.name).capitalize() if str(investors.name).begins_with("the ") else str(investors.name), roundi(float(investors.stake) * 100.0)])
	for ship: Dictionary in start.ships:
		lines.append("%s, a %s at %d%% condition" % [str(ship.name), str(GameData.get_ship_model(str(ship.model)).get("name", ship.model)), roundi(float(ship.condition) * 100.0)])
	if not (start.traits as Array).is_empty():
		var names := PackedStringArray()
		for id: String in start.traits:
			names.append(Traits.trait_name(id))
		lines.append("CEO traits: " + ", ".join(names))
	return lines


## Gives a new company its start (GameState.new_game(), after the company is made).
static func apply(state: Node, start: Dictionary) -> void:
	var company: Company = state.company
	company.money = int(start.get("money", company.money))
	company.loan = int(start.get("debt", 0))
	company.start_debt = company.loan
	company.investors = (start.get("investors", {}) as Dictionary).duplicate()
	var relations: Dictionary = (start.get("relations", {}) as Dictionary).duplicate(true)
	var countries: Dictionary = relations.get_or_add("countries", {})
	if relations.has("neighbours"):
		var home: String = state.world.country_of_port(str(start.port))
		var value := int(relations.neighbours)
		relations.erase("neighbours")
		for port: Dictionary in GameData.ports:  # (The countries whose ports lie within reach of home: its neighbours.)
			var other: String = state.world.country_of_port(str(port.id))
			if other.is_empty() or other == home or countries.has(other):
				continue
			if GameData.distance_nm(str(start.port), str(port.id)) <= 1200.0:
				countries[other] = value
	var firm_value := int(relations.get("firm", 0))
	relations.erase("firm")
	if firm_value != 0:
		var name := _firm_name_for(str(start.port))
		for firm: Dictionary in (state.firms as ShippingFirms).firms:
			if firm.name == name:
				relations.get_or_add("firms", {})[str(firm.id)] = firm_value
	company.relations = relations
	if company.ceo is Dictionary and not (start.traits as Array).is_empty():
		company.ceo.traits = (start.traits as Array).duplicate()
	for ship_info: Dictionary in start.get("ships", []):
		var ship: Ship = state.grant_ship(str(ship_info.model), str(ship_info.name), str(start.port))
		if ship != null:
			ship.maintenance = clampf(float(ship_info.get("condition", 0.7)), 0.05, 1.0)
			ship.sea_time = float(ship_info.get("age_hours", 0)) * 3600.0

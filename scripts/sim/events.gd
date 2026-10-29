# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Events
extends RefCounted
## Politics and events (DESIGN_LIVING_WORLD.md, later stages). Every country
## has a nation (nations: government, stability, trade stance, mood) made from
## the seed and moved by elections and coups; its tariff now follows its
## stance and the tariff events on it (tariff_now()). Each month the world
## throws events (active: {id, kind, since, until, ...}) of four families:
## trade (tariff rises, trade deals, sanctions, export bans), strikes and
## closures (dock strikes, canal closures, port shutdowns), wars and piracy
## (a war closes the lanes between two countries and doubles port fees there;
## piracy zones where a leg through them risks capture for ransom, less with
## armed guards), disasters (earthquakes and floods stopping a port's plants
## and shutting it, epidemics cutting a region's demand, famines doubling a
## country's hunger for grain). Their hooks: Seasons.closures() (canals and
## ports shut), WorldEconomy._step_zone() (make_factor(), use_factor(),
## use_boost()), GameState (tariff_factor(), fee_factor(), port_stop_factor(),
## trade_blocked(), piracy on departure, captured ships), Market.best_cargo().
## An event that touches the player (touches(): their ships, routes, hubs,
## contracts, stakes) comes as a card with choices (touched; answer()); the
## rest are headlines. Pace FREQUENT: about one touching card a month.

signal changed
## An event touches the player's company: a card with choices.
signal touched(company: Company, event: Dictionary)

const GOVERNMENTS := {democracy = "Democracy", one_party = "One-party state", monarchy = "Monarchy", junta = "Military rule"}
const STANCES := {open = "Open", neutral = "Neutral", protectionist = "Protectionist"}
const STANCE_TARIFF := {open = -0.02, neutral = 0.0, protectionist = 0.03}
const MOODS := ["austerity", "steady", "spending"]
## The governments everyone knows; the rest by income and the seed.
const KNOWN_GOVERNMENTS := {SAU = "monarchy", ARE = "monarchy", QAT = "monarchy", KWT = "monarchy", BHR = "monarchy", OMN = "monarchy", JOR = "monarchy", MAR = "monarchy", BRN = "monarchy", SWZ = "monarchy",
	CHN = "one_party", VNM = "one_party", LAO = "one_party", CUB = "one_party", PRK = "one_party", ERI = "one_party", RUS = "one_party", IRN = "one_party", TKM = "one_party", UZB = "one_party", BLR = "one_party", VEN = "one_party", SYR = "one_party", AZE = "one_party", TJK = "one_party", EGY = "one_party",
	MMR = "junta", SDN = "junta", MLI = "junta", BFA = "junta", GIN = "junta", NER = "junta", TCD = "junta",
	USA = "democracy", GBR = "democracy", DEU = "democracy", FRA = "democracy", JPN = "democracy", IND = "democracy", BRA = "democracy", KOR = "democracy", NLD = "democracy", AUS = "democracy", CAN = "democracy", ITA = "democracy", ESP = "democracy", MEX = "democracy", IDN = "democracy", TUR = "democracy", ZAF = "democracy", NGA = "democracy", ARG = "democracy", NOR = "democracy", SWE = "democracy", DNK = "democracy", FIN = "democracy", POL = "democracy", GRC = "democracy", PRT = "democracy", BEL = "democracy", CHL = "democracy", PHL = "democracy", THA = "democracy", MYS = "democracy", SGP = "democracy", NZL = "democracy", ISR = "democracy", PAK = "democracy", BGD = "democracy", LKA = "democracy", KEN = "democracy", GHA = "democracy", PER = "democracy", COL = "democracy", ECU = "democracy", URY = "democracy", IRL = "democracy", ISL = "democracy"}
const WORLD_A_MONTH := 5.0  # Events a month, world-wide.
const PLAYER_BIAS := 0.35  # The share aimed where the player trades (about one touching card a month).
const DAY := 86400
const PIRACY_ZONES := [
	{id = "aden", name = "the Gulf of Aden", circles = [[46.0, 12.5, 420.0], [52.0, 13.5, 300.0]], base = 0.03},
	{id = "malacca", name = "the Malacca Strait", circles = [[101.0, 3.0, 260.0]], base = 0.02},
	{id = "guinea", name = "the Gulf of Guinea", circles = [[4.0, 3.5, 380.0]], base = 0.03},
]
const PIRACY_RAISED := 0.12
const RANSOM_SHARE := 0.1
const CAPTIVE_DAYS := 60
const GUARDS_A_MONTH := 20000
const GUARDS_FACTOR := 0.3
const RELIEF_SHARE := 0.002  # Of the company's value, for relief.
const WAR_FEES := 2.0
const STRIKE_STOPS := 3.0
const UNION_FEE := 150000

var _state: Node  # GameState
## country id -> {government, stability, stance, mood, next_election (calendar)}.
var nations := {}
## The events in play, oldest first.
var active: Array = []
var _next_id := 1
var _month := -1


func _init(state: Node) -> void:
	_state = state


func reset() -> void:
	nations = {}
	active = []
	_next_id = 1
	_month = -1


# --- Nations -------------------------------------------------------------------------------

func nation(country: String) -> Dictionary:
	if nations.is_empty():
		_make_nations()
	return nations.get(country, {government = "democracy", stability = 60.0, stance = "neutral", mood = "steady", next_election = 0})


func _make_nations() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_state.world.seed) + 404 if _state.world != null else 404
	var now: int = _state.calendar_time()
	for country: Dictionary in WorldEconomy.data("countries").get("countries", []):
		var id := str(country.id)
		var income := str(country.get("income", ""))
		var roll := rng.randf()
		var government := "democracy"
		if KNOWN_GOVERNMENTS.has(id):
			government = str(KNOWN_GOVERNMENTS[id])
		elif income.begins_with("Low"):
			government = "junta" if roll < 0.2 else ("one_party" if roll < 0.35 else "democracy")
		elif income.begins_with("Lower"):
			government = "one_party" if roll < 0.15 else ("junta" if roll < 0.22 else "democracy")
		else:
			government = "democracy"
		var tariff := float(country.get("tariff", 0.05))
		var stance := "protectionist" if tariff > 0.09 else ("open" if tariff < 0.03 else "neutral")
		var stability := clampf(rng.randf_range(35.0, 95.0) + (10.0 if income.begins_with("High") else 0.0) - (15.0 if government == "junta" else 0.0), 10.0, 98.0)
		nations[id] = {government = government, stability = snappedf(stability, 1.0), stance = stance, mood = MOODS[rng.randi() % 3],
			next_election = now + rng.randi_range(6, 48) * 30 * DAY if government == "democracy" else 0}


static func government_name(n: Dictionary) -> String:
	return str(GOVERNMENTS.get(str(n.get("government", "democracy")), "Democracy"))


static func stance_name(n: Dictionary) -> String:
	return str(STANCES.get(str(n.get("stance", "neutral")), "Neutral"))


## A country's tariff now: its base, its stance, and the tariff events on it.
func tariff_now(country: String) -> float:
	var base := float(WorldEconomy.country(country).get("tariff", 0.05))
	var out := base + float(STANCE_TARIFF.get(str(nation(country).stance), 0.0))
	for event: Dictionary in active:
		if str(event.kind) == "tariff_rise" and str(event.get("country", "")) == country:
			out += float(event.get("amount", 0.05))
		elif str(event.kind) == "trade_deal" and country in event.get("countries", []):
			out -= 0.03
	return clampf(out, 0.0, 0.5)


## Selling into a country pays less by the rise in its tariff over its base (and more by a fall).
func tariff_factor(port_id: String) -> float:
	var country: String = _state.world.country_of_port(port_id) if _state.world != null else ""
	if country.is_empty():
		return 1.0
	var base := float(WorldEconomy.country(country).get("tariff", 0.05))
	return clampf(1.0 - (tariff_now(country) - base), 0.5, 1.2)


## Elections and coups: each month, by government and stability.
func _monthly_nations(rng: RandomNumberGenerator) -> void:
	var now: int = _state.calendar_time()
	for id: String in nations:
		var n: Dictionary = nations[id]
		var name := str(WorldEconomy.country(id).get("name", id))
		n.stability = clampf(float(n.stability) + rng.randf_range(-1.5, 1.5), 5.0, 98.0)
		if str(n.government) == "democracy" and now >= int(n.next_election):
			n.next_election = now + rng.randi_range(36, 60) * 30 * DAY
			var old := str(n.stance)
			n.stance = ["open", "neutral", "protectionist"][rng.randi() % 3]
			n.mood = MOODS[rng.randi() % 3]
			n.stability = clampf(float(n.stability) + rng.randf_range(-5.0, 10.0), 5.0, 98.0)
			_add({kind = "election", country = id, months = 1, title = "%s votes" % name,
				text = "%s has elected a new government: trade %s%s, a mood of %s." % [name, stance_name(n).to_lower(), " (was %s)" % str(STANCES[old]).to_lower() if old != str(n.stance) else "", str(n.mood)]}, rng)
		elif str(n.government) != "democracy" and rng.randf() < (100.0 - float(n.stability)) / 4000.0:
			var old_gov := government_name(n)
			n.government = ["junta", "one_party", "democracy"][rng.randi() % 3]
			n.stance = ["open", "neutral", "protectionist"][rng.randi() % 3]
			n.stability = clampf(float(n.stability) - 15.0, 5.0, 98.0)
			if str(n.government) == "democracy":
				n.next_election = now + 12 * 30 * DAY
			_add({kind = "coup", country = id, months = 1, title = "Upheaval in %s" % name,
				text = "%s has fallen in %s; %s takes over. Trade %s, and the ports nervous." % [old_gov, name, government_name(n).to_lower(), stance_name(n).to_lower()]}, rng)


# --- Events ----------------------------------------------------------------------------------

func step(_delta: float) -> void:
	var month: int = _state.history.month_now() if _state.history != null else -1
	if month == _month:
		return
	var first := _month < 0
	_month = month
	if nations.is_empty():
		_make_nations()
	var now: int = _state.calendar_time()
	var ended := active.filter(func(e: Dictionary) -> bool: return now >= int(e.until))
	for event: Dictionary in ended:
		active.erase(event)
		_on_end(event)
	if first or _state.warm_up_left > 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_monthly_nations(rng)
	var count := roundi(WORLD_A_MONTH * rng.randf_range(0.6, 1.4))
	for k in count:
		_throw(rng)
	_charge_guards()
	changed.emit()


## A random event of a family, aimed at the player's ports PLAYER_BIAS of the time.
func _throw(rng: RandomNumberGenerator) -> void:
	var world: WorldEconomy = _state.world
	var port_id := _pick_port(rng)
	if port_id.is_empty():
		return
	var country := world.country_of_port(port_id)
	var name := str(WorldEconomy.country(country).get("name", country))
	var port_name := GameData.port_name(port_id)
	var roll := rng.randf()
	if roll < 0.28:  # Trade.
		var sub := rng.randf()
		if sub < 0.35:
			var amount := rng.randf_range(0.04, 0.15)
			_add({kind = "tariff_rise", country = country, amount = snappedf(amount, 0.01), months = rng.randi_range(12, 36), title = "%s raises tariffs" % name,
				text = "%s puts %d points on its import tariffs; what ships sell there pays less." % [name, roundi(amount * 100.0)]}, rng)
		elif sub < 0.6:
			var other := _other_country(country, rng)
			if other.is_empty():
				return
			_add({kind = "trade_deal", countries = [country, other], months = rng.randi_range(24, 60), title = "%s and %s sign a trade deal" % [name, str(WorldEconomy.country(other).get("name", other))],
				text = "Tariffs between %s and %s fall; cargo between them pays better." % [name, str(WorldEconomy.country(other).get("name", other))]}, rng)
		elif sub < 0.8:
			var other := _other_country(country, rng)
			if other.is_empty():
				return
			_add({kind = "sanctions", by = other, country = country, months = rng.randi_range(12, 48), title = "%s sanctions %s" % [str(WorldEconomy.country(other).get("name", other)), name],
				text = "%s has put %s under sanctions: a company trading at %s\'s ports loses standing with %s." % [str(WorldEconomy.country(other).get("name", other)), name, name, str(WorldEconomy.country(other).get("name", other))]}, rng)
		else:
			var good := _good_made_at(port_id, rng)
			if good.is_empty():
				return
			_add({kind = "export_ban", country = country, good = good, months = rng.randi_range(3, 12), title = "%s bans %s exports" % [name, str(GameData.commodity(good).get("name", good)).to_lower()],
				text = "%s keeps its %s at home: none can be bought at its ports for now." % [name, str(GameData.commodity(good).get("name", good)).to_lower()]}, rng)
	elif roll < 0.55:  # Strikes and closures.
		var sub := rng.randf()
		if sub < 0.55:
			_add({kind = "strike", port = port_id, country = country, months = 0, days = rng.randi_range(7, 21), title = "Dock strike at %s" % port_name,
				text = "The dockers of %s are out: every stop there takes three times as long till they settle." % port_name}, rng)
		elif sub < 0.8 and rng.randf() < 0.5:
			var canal: String = ["suez", "panama"][rng.randi() % 2]
			_add({kind = "canal_closure", canal = canal, months = 0, days = rng.randi_range(4, 14), title = "%s closed" % ("Suez Canal" if canal == "suez" else "Panama Canal"),
				text = "%s is shut%s; ships wait or go the long way round." % ["The Suez Canal" if canal == "suez" else "The Panama Canal", " after a grounding" if rng.randf() < 0.6 else " for emergency works"]}, rng)
		else:
			_add({kind = "port_shutdown", port = port_id, country = country, months = 0, days = rng.randi_range(3, 10), title = "%s shut" % port_name,
				text = "%s is closed to shipping%s." % [port_name, " by storm damage" if rng.randf() < 0.5 else " under quarantine"]}, rng)
	elif roll < 0.72:  # Wars and piracy.
		if rng.randf() < 0.4:
			var zone: Dictionary = PIRACY_ZONES[rng.randi() % PIRACY_ZONES.size()]
			_add({kind = "piracy", zone = str(zone.id), months = rng.randi_range(3, 9), title = "Piracy surges in %s" % str(zone.name),
				text = "Attacks in %s have multiplied: a ship through it risks capture for ransom. Armed guards cut the risk." % str(zone.name)}, rng)
		else:
			var other := _neighbour_country(country, rng)
			if other.is_empty() or _at_war(country, other):
				return
			_add({kind = "war", countries = [country, other], months = rng.randi_range(4, 18), title = "War between %s and %s" % [name, str(WorldEconomy.country(other).get("name", other))],
				text = "Fighting has closed the sea lanes between %s and %s, and port fees in both have doubled with the insurance." % [name, str(WorldEconomy.country(other).get("name", other))]}, rng)
	else:  # Disasters.
		var sub := rng.randf()
		if sub < 0.45:
			var quake := rng.randf() < 0.5
			_add({kind = "disaster", port = port_id, country = country, months = rng.randi_range(3, 9), title = "%s at %s" % ["Earthquake" if quake else "Floods", port_name],
				text = "%s has %s: its plants are down for months and the port shut for a fortnight." % [port_name, "been shaken by an earthquake" if quake else "flooded"]}, rng)
		elif sub < 0.75:
			var region := str(GameData.port_region(port_id).get("id", ""))
			_add({kind = "epidemic", region = region, port = port_id, country = country, months = rng.randi_range(2, 6), title = "Epidemic in %s" % str(GameData.port_region(port_id).get("name", region)),
				text = "Sickness is sweeping %s: markets thin, crews fall ill." % str(GameData.port_region(port_id).get("name", region))}, rng)
		else:
			_add({kind = "famine", country = country, months = rng.randi_range(4, 12), title = "Famine in %s" % name,
				text = "Harvests have failed in %s: it wants twice the grain, at any price." % name}, rng)


func _add(event: Dictionary, _rng: RandomNumberGenerator) -> void:
	var now: int = _state.calendar_time()
	event.id = _next_id
	_next_id += 1
	event.since = now
	event.until = now + (int(event.get("months", 1)) * 30 * DAY if int(event.get("months", 1)) > 0 else int(event.get("days", 7)) * DAY)
	active.append(event)
	_on_start(event)
	if _state.news != null:
		_state.news.add("world", str(event.title) + ": " + str(event.text), {country = str(event.get("country", "")), port = str(event.get("port", ""))})
	if _state.warm_up_left <= 0:
		for company: Company in _state.all_companies():
			if touches(company, event):
				touched.emit(company, event)


func _on_start(event: Dictionary) -> void:
	match str(event.kind):
		"disaster":
			event.port_shut_until = int(event.since) + 14 * DAY
	changed.emit()


func _on_end(event: Dictionary) -> void:
	if _state.news != null and str(event.kind) in ["war", "sanctions", "strike", "canal_closure", "piracy", "famine", "epidemic", "export_ban"]:
		_state.news.add("world", "%s: over" % str(event.title), {country = str(event.get("country", ""))})
	changed.emit()


# --- Picking targets --------------------------------------------------------------------------

## A port: one the player trades at PLAYER_BIAS of the time, else any.
func _pick_port(rng: RandomNumberGenerator) -> String:
	if rng.randf() < PLAYER_BIAS:
		var mine := player_ports(_state.company)
		if not mine.is_empty():
			return mine[rng.randi() % mine.size()]
	var port: Dictionary = GameData.ports[rng.randi() % GameData.ports.size()]
	return str(port.id)


## The ports a company works: its hubs, its ships' routes and where they are, its contracts.
static func player_ports(company: Company) -> Array:
	var out := {}
	for hub: Hub in company.hubs:
		out[hub.port_id] = true
	for ship: Ship in GameState.fleet(company):
		for port: String in ship.route:
			out[port] = true
		if not ship.docked_at.is_empty():
			out[ship.docked_at] = true
		if not ship.to_port.is_empty():
			out[ship.to_port] = true
	var contracts: Contracts = GameState.contracts
	for contract: Dictionary in contracts.contracts:
		if int(contract.company) == GameState.all_companies().find(company) and str(contract.status) == "active":
			out[str(contract.from)] = true
			out[str(contract.to)] = true
	return out.keys()


func _other_country(country: String, rng: RandomNumberGenerator) -> String:
	var all: Array = nations.keys().filter(func(id: String) -> bool: return id != country and not (_state.world as WorldEconomy).ports_of_country(id).is_empty())
	return all[rng.randi() % all.size()] if not all.is_empty() else ""


## A country within reach of one of its ports: a plausible enemy.
func _neighbour_country(country: String, rng: RandomNumberGenerator) -> String:
	var world: WorldEconomy = _state.world
	var mine: Array = world.ports_of_country(country)
	if mine.is_empty():
		return ""
	var near := {}
	var home: String = mine[rng.randi() % mine.size()]
	for port: Dictionary in GameData.ports:
		var other := world.country_of_port(str(port.id))
		if other.is_empty() or other == country:
			continue
		if GameData.distance_nm(home, str(port.id)) <= 1500.0:
			near[other] = true
	var list := near.keys()
	return list[rng.randi() % list.size()] if not list.is_empty() else ""


func _good_made_at(port_id: String, rng: RandomNumberGenerator) -> String:
	var world: WorldEconomy = _state.world
	var z := world.zone_of_port(port_id)
	if z < 0:
		return ""
	var made := []
	for g in world.goods.size():
		if world.capacity[z * world.goods.size() + g] > 0.0:
			made.append(world.goods[g])
	return made[rng.randi() % made.size()] if not made.is_empty() else ""


# --- Hooks the game asks ------------------------------------------------------------------------

func _at_war(a: String, b: String) -> bool:
	for event: Dictionary in active:
		if str(event.kind) == "war" and a in event.countries and b in event.countries:
			return true
	return false


## The closures events add to the seasonal ones (Seasons.closures()): canals shut, ports shut.
func closures() -> Array:
	var out := []
	for event: Dictionary in active:
		match str(event.kind):
			"canal_closure":
				out.append({id = "event_%d" % int(event.id), name = "the %s" % ("Suez Canal" if event.canal == "suez" else "Panama Canal"), why = "its closure", canal = str(event.canal), unix_from = int(event.since), unix_to = int(event.until)})
			"port_shutdown":
				out.append({id = "event_%d" % int(event.id), name = GameData.port_name(str(event.port)), why = "its closure", ports = [str(event.port)], unix_from = int(event.since), unix_to = int(event.until)})
			"disaster":
				out.append({id = "event_%d" % int(event.id), name = GameData.port_name(str(event.port)), why = str(event.title).to_lower(), ports = [str(event.port)], unix_from = int(event.since), unix_to = int(event.get("port_shut_until", event.since))})
	return out


## A leg between two warring countries is shut, unless the company runs the blockade (its choice on the card).
func war_blocks(company: Company, from: String, to: String) -> Dictionary:
	var world: WorldEconomy = _state.world
	var a := world.country_of_port(from)
	var b := world.country_of_port(to)
	if a.is_empty() or b.is_empty() or a == b:
		return {}
	for event: Dictionary in active:
		if str(event.kind) == "war" and a in event.countries and b in event.countries:
			if company != null and str(company.event_choices.get(str(event.id), "")) == "run":
				return {}
			return {id = "event_%d" % int(event.id), name = "the lanes between %s and %s" % [str(WorldEconomy.country(a).get("name", a)), str(WorldEconomy.country(b).get("name", b))], why = "the war"}
	return {}


## Port fees: doubled in a country at war (insurance).
func fee_factor(port_id: String) -> float:
	var country: String = _state.world.country_of_port(port_id) if _state.world != null else ""
	for event: Dictionary in active:
		if str(event.kind) == "war" and country in event.countries:
			return WAR_FEES
	return 1.0


## Port stops: three times as long at a port on strike, unless the company paid the union.
func port_stop_factor(port_id: String, company: Company) -> float:
	for event: Dictionary in active:
		if str(event.kind) == "strike" and str(event.port) == port_id:
			if company != null and str(company.event_choices.get(str(event.id), "")) == "paid":
				return 1.0
			return STRIKE_STOPS
	return 1.0


## Whether a good can't be bought at a port: its country's export ban, or sanctions the company honours.
func trade_blocked(port_id: String, good: String, company: Company) -> bool:
	var country: String = _state.world.country_of_port(port_id) if _state.world != null else ""
	for event: Dictionary in active:
		match str(event.kind):
			"export_ban":
				if str(event.country) == country and str(event.good) == good:
					return true
			"sanctions":
				if str(event.country) == country and company != null and str(company.event_choices.get(str(event.id), "")) == "honour":
					return true
	return false


## A trade at a sanctioned country's port by a company that trades on: standing with the sanctioner slips.
func note_trade(company: Company, port_id: String) -> void:
	var country: String = _state.world.country_of_port(port_id) if _state.world != null else ""
	for event: Dictionary in active:
		if str(event.kind) == "sanctions" and str(event.country) == country:
			_state.contracts.change_standing(company, -1, -2.0, str(event.by), 1.0)


## The economy's factors a zone: production stopped by a disaster at one of its ports; demand thinned by an epidemic in its region.
func make_factor(z: int) -> float:
	if active.is_empty():
		return 1.0
	var world: WorldEconomy = _state.world
	for event: Dictionary in active:
		if str(event.kind) == "disaster" and world.zone_of_port(str(event.port)) == z:
			return 0.0
	return 1.0


func use_factor(z: int) -> float:
	if active.is_empty():
		return 1.0
	var world: WorldEconomy = _state.world
	var out := 1.0
	for event: Dictionary in active:
		if str(event.kind) == "epidemic" and world.zone_of_port(str(event.port)) == z:
			out *= 0.7
	return out


## A famine doubles a country's need for the grain family.
func use_boost(z: int, good: String) -> float:
	if active.is_empty():
		return 1.0
	var world: WorldEconomy = _state.world
	var country := str(world.zones[z].country)
	for event: Dictionary in active:
		if str(event.kind) == "famine" and str(event.country) == country and WorldEconomy.line_of(good) == "grain":
			return 2.0
	return 1.0


## The piracy risk for a leg: the zones its lane passes through, raised by events, cut by guards.
func piracy_risk(company: Company, from: String, to: String) -> float:
	var risk := 0.0
	var seasons: Seasons = _state.seasonal
	for zone: Dictionary in PIRACY_ZONES:
		if not seasons.lane_enters(zone, from, to):
			continue
		var chance := float(zone.base)
		for event: Dictionary in active:
			if str(event.kind) == "piracy" and str(event.zone) == str(zone.id):
				chance = PIRACY_RAISED
		risk = maxf(risk, chance)
	if company != null and company.guards:
		risk *= GUARDS_FACTOR
	return risk


func piracy_zone_name(from: String, to: String) -> String:
	var seasons: Seasons = _state.seasonal
	for zone: Dictionary in PIRACY_ZONES:
		if seasons.lane_enters(zone, from, to):
			return str(zone.name)
	return "pirate waters"


## A ship taken: held CAPTIVE_DAYS unless the ransom is paid (a card: answer() "ransom").
func capture(ship: Ship) -> void:
	var company: Company = _state.owner_of(ship)
	var ransom := roundi(float(ship.model().get("price", 0)) * RANSOM_SHARE)
	ship.captured_until = _state.calendar_time() + CAPTIVE_DAYS * DAY
	var event := {id = _next_id, kind = "capture", ship = ship.id, ransom = ransom, since = _state.calendar_time(), until = ship.captured_until, title = "%s seized by pirates" % ship.name,
		text = "Pirates have boarded %s in %s and hold her and her crew. They want %s; unpaid, they will let her go in about %d days, worse for wear." % [ship.name, piracy_zone_name(ship.from_port, ship.to_port), Fmt.money(ransom), CAPTIVE_DAYS]}
	_next_id += 1
	active.append(event)
	if _state.news != null:
		_state.news.add("world", "%s: %s seized off %s" % [company.name, ship.name, piracy_zone_name(ship.from_port, ship.to_port)], {})
	touched.emit(company, event)
	changed.emit()


func _charge_guards() -> void:
	for company: Company in _state.all_companies():
		if not company.guards:
			continue
		var cost: int = GUARDS_A_MONTH * _state.fleet(company).size()
		if cost > 0:
			_state._add_money(company, -cost)
			_state._record(null, "wages", float(cost), company)


# --- The player -------------------------------------------------------------------------------

## Whether an event touches a company: its ports, countries, canals, lanes, stakes.
func touches(company: Company, event: Dictionary) -> bool:
	var world: WorldEconomy = _state.world
	var ports := player_ports(company)
	var countries := {}
	for port: String in ports:
		countries[world.country_of_port(port)] = true
	var firms: ShippingFirms = _state.firms
	for key: String in company.stakes:
		countries[str(firms.firms[int(key)].country)] = true
	match str(event.kind):
		"strike", "port_shutdown", "disaster", "epidemic":
			return str(event.port) in ports or (str(event.kind) == "epidemic" and ports.any(func(p: String) -> bool: return str(GameData.port_region(p).get("id", "")) == str(event.region)))
		"tariff_rise", "export_ban", "famine", "sanctions", "election", "coup":
			return countries.has(str(event.country))
		"trade_deal", "war":
			return (event.countries as Array).any(func(c: String) -> bool: return countries.has(c))
		"canal_closure":
			for ship: Ship in GameState.fleet(company):
				for i in ship.route.size():
					for crossing: Dictionary in GameData.canal_crossings(ship.route[i], ship.route[(i + 1) % ship.route.size()]):
						if str(crossing.canal.id) == str(event.canal):
							return true
			return false
		"piracy":
			var seasons: Seasons = _state.seasonal
			var zone: Dictionary = PIRACY_ZONES.filter(func(zn: Dictionary) -> bool: return str(zn.id) == str(event.zone))[0]
			for ship: Ship in GameState.fleet(company):
				for i in ship.route.size():
					if seasons.lane_enters(zone, ship.route[i], ship.route[(i + 1) % ship.route.size()]):
						return true
			return false
		"capture":
			return true
	return false


## The choices an event offers the player: [[id, label], ...].
func choices(company: Company, event: Dictionary) -> Array:
	match str(event.kind):
		"strike":
			return [["paid", "Pay the union %s: your ships worked" % Fmt.money(UNION_FEE)], ["wait", "Wait it out"]]
		"sanctions":
			return [["honour", "Honour them (no loading at %s\'s ports)" % str(WorldEconomy.country(str(event.country)).get("name", event.country))], ["trade", "Trade on (standing with %s suffers)" % str(WorldEconomy.country(str(event.by)).get("name", event.by))]]
		"war":
			return [["clear", "Keep clear of the lanes between them"], ["run", "Run the blockade (double fees, your risk)"]]
		"piracy":
			return [["guards", "Armed guards on every ship (%s a ship a month)" % Fmt.money(GUARDS_A_MONTH)], ["risk", "Take the risk"]]
		"capture":
			return [["ransom", "Pay the ransom (%s)" % Fmt.money(int(event.ransom))], ["wait", "Wait for her release"]]
		"disaster", "famine", "epidemic":
			var relief := roundi(_state.company_value(company) * RELIEF_SHARE)
			return [["relief", "Send relief (%s; standing +10 with %s)" % [Fmt.money(maxi(relief, 50000)), str(WorldEconomy.country(str(event.country)).get("name", event.country))]], ["nothing", "Nothing"]]
	return [["noted", "Noted"], ["intel", "Intelligence page"]]


## The player's answer (GameState.answer_event()).
func answer(company: Company, event_id: int, choice: String) -> void:
	var event := {}
	for each: Dictionary in active:
		if int(each.id) == event_id:
			event = each
	if event.is_empty():
		return
	company.event_choices[str(event_id)] = choice
	match choice:
		"paid":
			_state._add_money(company, -UNION_FEE)
			_state._record(null, "port_fees", float(UNION_FEE), company)
		"guards":
			company.guards = true
		"ransom":
			var ship: Ship = _state.ship_by_id(int(event.ship))
			_state._add_money(company, -int(event.ransom))
			_state._record(ship, "repair", float(event.ransom), company)
			if ship != null:
				ship.captured_until = _state.calendar_time() + 2 * DAY
				event.until = ship.captured_until
			if company == _state.company:
				ActivityLog.add("Paid %s in ransom; %s sails on in two days." % [Fmt.money(int(event.ransom)), ship.name if ship != null else "the ship"], ActivityLog.Kind.BAD)
		"relief":
			var relief := maxi(roundi(_state.company_value(company) * RELIEF_SHARE), 50000)
			_state._add_money(company, -relief)
			_state._record(null, "port_fees", float(relief), company)
			_state.contracts.change_standing(company, -1, 10.0, str(event.country), 1.0)
			if company == _state.company:
				ActivityLog.add("Sent %s in relief to %s; its producers remember." % [Fmt.money(relief), str(WorldEconomy.country(str(event.country)).get("name", event.country))], ActivityLog.Kind.GOOD)
	changed.emit()


func to_dict() -> Dictionary:
	return {nations = nations, active = active, next_id = _next_id, month = _month}


func from_dict(data: Dictionary) -> void:
	nations = data.get("nations", {}) if data.get("nations") is Dictionary else {}
	active = data.get("active", []) if data.get("active") is Array else []
	_next_id = int(data.get("next_id", 1))
	_month = int(data.get("month", -1))
	changed.emit()

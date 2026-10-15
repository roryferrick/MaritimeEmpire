# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Company
extends RefCounted
## A player's company: its money, HQ and hubs, XP, finances, upgrades and
## settings. The world (markets, ports, weather, the calendar) is shared by
## every company in a game; each ship belongs to one (Ship.company).
##
## In single player there's one. GameState.company is the one this player
## controls, and GameState's money, hubs, company_xp... are that company's.
##
## to_dict() uses the same keys saves used before there were companies, so an
## old save loads as its one company (from_dict() of the whole save).

var name := ""
## The company's color id (see game_config company_colors): its name in the
## top bar and the rings around its HQ and hubs.
var color := "purple"
## "" for a company a person plays; for an AI rival (see RivalAI), how well
## it plays: "easy", "normal" or "hard".
var ai := ""
## New ships are delivered here; the HQ.
var home_port := ""
var money := 0
## Units delivered of each commodity (id -> units, in its markets.json unit),
## counted when unloading finishes.
var delivered := {}
## Containers delivered before deliveries were counted by commodity (saves
## from before then only kept a container total).
var earlier_containers := 0
## Models whose first-purchase price (first_price in ship_models.json) has been used.
var first_prices_used: Array[String] = []
## Models with their mega upgrade (see GameState.mega_error()).
var mega_upgrades: Array[String] = []
## The hidden gems found (GameState.HIDDEN_GEMS ids), each paid out once.
var hidden_gems: Array[String] = []
## Total company XP from deliveries; see Progression for levels.
var xp := 0.0
## Its company types (game_config company_types), in the order taken: type id
## -> the company level it was taken at (1 for the type it was founded as).
## Empty for a company from before types, which has every type (all_types()).
var company_types := {}
## Its logo (CompanyLogo): {shape, layout, secondary (a company colour id), swap}.
var logo := {}
## The ports where it has built a cruise terminal (Cruises: a cruise ship may
## sail from its HQ, a hub, or one of these).
var terminals: Array[String] = []
## Its star rating's record in each company type (Ratings): type id ->
## {samples: [[condition, reliability, scale] a minute], ports: {port id: when
## last traded at}, star: the whole stars last announced}.
var ratings := {}
## True for a company loaded from a save from before ratings, till its first
## sample (which then fills its window: see Ratings.sample()). Not saved.
var ratings_seed := false
## Money cargo purchases leave in the bank (set on the Finances screen).
var bank_reserve := 0
## Money borrowed on the Finances screen and not yet paid back (see
## GameState.take_loan()).
var loan := 0
## The CEO (Characters: {name, look}), made on the New Company screen.
var ceo := {}
## What its people wear, line by line, where it's changed the defaults
## (CrewLooks: {line: {role: {part: name}}}, set on the Uniforms page).
var uniforms := {}
## The HQ (at the home port, first) and the hubs placed since.
var hubs: Array[Hub] = []
## The market regions unlocked (ids from markets.json regions): the home
## port's from the start, then one more every few company levels (see
## Progression.region_slots()). Empty in saves from before regions, until
## GameState fits it to the fleet.
var regions: Array[String] = []
## All-time totals for each of GameState.MONEY_KINDS.
var totals := {}
## The catch its fishing and crabbing boats left in the cold store at each
## port for its seafood carriers to take (see GameState._land_catch()):
## port id -> {family: crates}.
var cold_stores := {}
## Its farm stores (Farms): port id -> {items: {item ("apples", or a breed's
## young "cows:angus"): [units, freshness 0-1]}, cold (a cold store built)}.
var farm_stores := {}
## Its harvests' worth lately (fading a little each day: Farms), and what of
## it spoiled and was collected by its ships: {harvested, spoiled, collected}.
var farm_tally := {}
## The fishing grounds it has picked on the Fishing Grounds screen, and for each
## boat model sent there where its catch is landed and whether it goes in the
## freezer: {ground id: {model id: {port, freeze}}}. Which boats are sent is
## each boat's own (Ship.fish_area).
var fish_areas := {}
## What it has traded at each port (see GameState._tally_port_trade()): port id ->
## {since (play time it began keeping count there), goods: {commodity id:
## [units bought, money spent, units sold, money earned]}}.
var port_trade := {}
## Per canal id: {crossings, tolls, xp (the extra company XP its bonus gave)}.
var canal_stats := {}
## Recent money, oldest first: {start (play_time), fleet: {kind: amount},
## ships: {ship name: {kind: amount}}}.
var finance_window: Array = []
## Whether it has the tutorial (chosen when founded), the map's Tutorial
## switch, and the ids of the tips already seen (see TutorialCard).
var tutorials := false
var tutorials_on := true
var tutorial_done: Array[String] = []
## Achievements earned (Achievements: id -> stars, 1 for a badge), and the
## animals seen on the map (Achievements.discover(): the field guide's checks).
var achievements := {}
var discovered: Array[String] = []
## The map's Routes switch, the ship models muted in the activity log, and
## whether the activity log panel is folded away.
var show_active_routes := true
var muted_models: Array[String] = []
var activity_collapsed := false

## level(), and the XP it was worked out for.
var _level := 1
var _level_xp := -1.0
var _level_types := 0
## GameState.fuel_reserve() for this company, and when it was worked out.
var fuel_reserve := 0.0
var fuel_reserve_time := -1.0


func _init(company_name := "", company_color := "purple", home := "") -> void:
	name = company_name
	color = company_color
	home_port = home


## True for an AI rival (see RivalAI).
func is_ai() -> bool:
	return not ai.is_empty()


## Its company level, worked out again only when its XP changes (it walks
## the level costs, and the sim asks often).
func level() -> int:
	if xp != _level_xp or _level_types != company_types.size():
		_level_types = company_types.size()  # (Level costs follow the types: see Progression.company_level_cost().)
		_level_xp = xp
		_level = int(Progression.company_level(xp, self).level)
	return _level


## True for a company from before company types: every type is open.
func all_types() -> bool:
	return company_types.is_empty()


## The type it was founded as ("" for a company from before types).
func start_type() -> String:
	return "" if company_types.is_empty() else str(company_types.keys()[0])


## True if it has this company type (every type, for a company from before types).
func has_type(type_id: String) -> bool:
	return company_types.is_empty() or company_types.has(type_id)


## The company level it took a type at (-1 if it hasn't).
func type_level(type_id: String) -> int:
	return int(company_types.get(type_id, -1))


func hub_at(port_id: String) -> Hub:
	for hub in hubs:
		if hub.port_id == port_id:
			return hub
	return null


func hub_bonus(port_id: String, path: String) -> float:
	var hub := hub_at(port_id)
	return hub.bonus(path) if hub else 0.0


func has_mega(model_id: String) -> bool:
	return mega_upgrades.has(model_id)


func to_dict() -> Dictionary:
	return {
		"company_name": name,
		"company_color": color,
		"ai": ai,
		"home_port": home_port,
		"money": money,
		"company_xp": xp,
		"company_types": company_types,
		"logo": logo,
		"terminals": terminals,
		"ratings": ratings,
		"delivered": delivered,
		"earlier_containers": earlier_containers,
		"first_prices_used": first_prices_used,
		"mega_upgrades": mega_upgrades,
		"hidden_gems": hidden_gems,
		"bank_reserve": bank_reserve,
		"loan": loan,
		"ceo": ceo,
		"uniforms": uniforms,
		"hubs": hubs.map(func(hub: Hub) -> Dictionary: return hub.to_dict()),
		"regions": regions,
		"totals": totals,
		"cold_stores": cold_stores,
		"farm_stores": farm_stores,
		"farm_tally": farm_tally,
		"fish_areas": fish_areas,
		"port_trade": port_trade,
		"canal_stats": canal_stats,
		"finance_window": finance_window,
		"tutorials": tutorials,
		"tutorials_on": tutorials_on,
		"tutorial_done": tutorial_done,
		"achievements": achievements,
		"discovered": discovered,
		"show_active_routes": show_active_routes,
		"muted_models": muted_models,
		"activity_collapsed": activity_collapsed,
	}


static func from_dict(data: Dictionary) -> Company:
	var company := Company.new(str(data.get("company_name", "")), str(data.get("company_color", "purple")), str(data.get("home_port", "")))
	company.ai = str(data.get("ai", ""))
	company.money = int(data.get("money", 0))
	company.xp = float(data.get("company_xp", 0.0))
	company.ratings = data.get("ratings", {}) if data.get("ratings") is Dictionary else {}
	company.ratings_seed = not data.has("ratings")
	company.terminals.assign(data.get("terminals", []))
	company.logo = data.get("logo", {}) if data.get("logo") is Dictionary else {}
	if company.logo.is_empty():  # (Saves from before logos: one made up from its colour.)
		company.logo = CompanyLogo.default_logo(company.color)
	var types: Variant = data.get("company_types", {})  # (Saves from before types have none: every type open.)
	if types is Dictionary:
		for type_id: String in types:
			company.company_types[type_id] = int(types[type_id])
	for commodity_id: String in data.get("delivered", {}):
		var now := GameData.current_commodity(commodity_id)
		company.delivered[now] = int(company.delivered.get(now, 0)) + int(data.delivered[commodity_id])
	company.earlier_containers = int(data.get("earlier_containers", 0))
	if not data.has("delivered"):  # Saves from before per-commodity counts: their container total.
		company.earlier_containers = int(data.get("containers_delivered", 0))
	company.first_prices_used.assign(data.get("first_prices_used", []))
	company.mega_upgrades.assign(data.get("mega_upgrades", []))
	company.hidden_gems.assign(data.get("hidden_gems", []))
	company.bank_reserve = int(data.get("bank_reserve", 0))
	company.loan = int(data.get("loan", 0))
	company.ceo = data.get("ceo", {})
	company.uniforms = data.get("uniforms", {}) if data.get("uniforms") is Dictionary else {}
	if company.ceo.is_empty():  # Saves from before CEOs: made up, the same each load.
		company.ceo = Company.random_ceo(absi(company.name.hash()))
	company.regions.assign(data.get("regions", []))
	for hub_data: Dictionary in data.get("hubs", []):
		company.hubs.append(Hub.from_dict(hub_data))
	if company.hubs.is_empty():  # Saves from before hubs: the HQ at the home port.
		company.hubs.append(Hub.new(company.home_port, true))
	company.totals = data.get("totals", {})
	company.cold_stores = data.get("cold_stores", {})
	company.farm_stores = data.get("farm_stores", {}) if data.get("farm_stores") is Dictionary else {}
	company.farm_tally = data.get("farm_tally", {}) if data.get("farm_tally") is Dictionary else {}
	company.fish_areas = data.get("fish_areas", {}) if data.get("fish_areas") is Dictionary else {}
	company.port_trade = data.get("port_trade", {})
	company.canal_stats = data.get("canal_stats", {})
	company.finance_window = data.get("finance_window", [])
	company.tutorials = bool(data.get("tutorials", false))
	company.tutorials_on = bool(data.get("tutorials_on", true))
	company.tutorial_done.assign(data.get("tutorial_done", []))
	for id: String in data.get("achievements", {}):
		company.achievements[id] = int(data.achievements[id])
	company.achievements.erase("hidden_gem")  # (The old one-gem badge, now the Hidden gems line.)
	company.discovered.assign(data.get("discovered", []))
	company.show_active_routes = bool(data.get("show_active_routes", true))
	company.muted_models.assign(data.get("muted_models", []))
	company.activity_collapsed = bool(data.get("activity_collapsed", false))
	return company


## This player's own map and log settings: kept by each player's game, never
## overwritten by the host's copy (see apply_update()).
const PREF_KEYS: Array[String] = ["show_active_routes", "muted_models", "activity_collapsed", "tutorials_on", "tutorial_done", "achievements", "discovered"]


## Applies an update from the host in a multiplayer game: any of to_dict()'s
## keys. Hubs are updated in place (matched by port), so anything holding one
## keeps a live hub. keep_prefs leaves PREF_KEYS alone (this player's company).
func apply_update(data: Dictionary, keep_prefs := false) -> void:
	for key: String in data:
		if keep_prefs and key in PREF_KEYS:
			continue
		var value: Variant = data[key]
		match key:
			"company_name":
				name = value
			"company_color":
				color = value
			"company_xp":
				xp = value
			"company_types":
				company_types = {}
				for type_id: String in value:
					company_types[type_id] = int(value[type_id])
			"first_prices_used", "mega_upgrades", "tutorial_done", "muted_models", "regions", "discovered", "terminals":
				(get(key) as Array).assign(value)
			"hubs":
				var kept: Array[Hub] = []
				for hub_data: Dictionary in value:
					var hub := hub_at(str(hub_data.port_id))
					if hub == null:
						hub = Hub.from_dict(hub_data)
					else:
						for field: String in hub_data:
							hub.set(field, hub_data[field])
					kept.append(hub)
				hubs = kept
			_:
				set(key, value)


## A CEO made up at random (seed -1), or the same for the same seed.
static func random_ceo(seed := -1) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	return Characters.random_character(rng)

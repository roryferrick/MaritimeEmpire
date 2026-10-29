# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Company
extends RefCounted
## A player's company: its money, HQ and hubs, divisions, finances and
## settings. The world (markets, ports, weather, the calendar) is shared by
## every company in a game; each ship belongs to one (Ship.company).
##
## In single player there's one. GameState.company is the one this player
## controls, and GameState's money, hubs... are that company's.

var name := ""
## The company's color id (see game_config company_colors): its name in the
## top bar and the rings around its HQ and hubs.
var color := "purple"
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
## The hidden gems found (GameState.HIDDEN_GEMS ids), each paid out once.
var hidden_gems: Array[String] = []
## Its company types, its divisions (game_config company_types), in the order
## taken: type id -> the play time it was taken at (0 for the one it was founded as).
var company_types := {}
## Research points banked from its research ships' own expeditions (Research),
## for developing its own technology later (DESIGN_LIVING_WORLD.md M5).
var research_points := 0.0
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
## The backers' stake from the backstory start ({stake, name}), {} for none (the share market comes in M3).
var investors := {}
## The backstory's story (Backstories.story()), told again on the CEO's card.
var story := ""
## Standing from the backstory: {countries: {id: value}, firms: {firm index: value}} (used when reputation arrives in M2).
var relations := {}
## The executives by role (People.ROLES), the department heads by "group|region" and each head's budget of contracts (see People).
var executives := {}
var heads := {}
var head_budgets := {}
## The share register and all that goes with it (see Ownership.ensure()), and the stakes held in the paper firms (firm index -> shares).
var shares := {}
var stakes := {}
## The CEO's family (People._monthly_family()): {spouse, children, heir (an index into children or -1)}.
var family := {}
## Ships on order from the shipyards (Shipyards.place_order(): {id, model, name, yard, port, placed, due, price, deposit, late}).
var orders := []
## How the firms this company controls are run (Ownership.ensure_plan(): firm index -> {focus, groups, dividend, extra_fleet, orders}).
var firm_plans := {}
## Technology (Technology): the techs held (id -> {since, how, exclusive_until}), the company's own R&D ({tech, budget, progress}), what each R&D company thinks of it (id -> 0 to 100) and the early offers already made (tech id -> true).
var techs := {}
var rnd := {}
var rnd_likes := {}
var rnd_offers := {}
## Hiring: the job postings out ({id, kind, role, salary (a share of the going rate), since}), recruiters on retainer, and the losing quarters in a row (People).
var postings := []
var recruiters := 0
var loss_quarters := 0
## Agreements with the paper firms (FirmLife: firm index -> {kind "alliance"/"pool"/"rivalry", since, group}).
var agreements := {}
## The CEO (Characters: {name, look}), made on the New Company screen.
var ceo := {}
## What its people wear, line by line, where it's changed the defaults
## (CrewLooks: {line: {role: {part: name}}}, set on the Uniforms page).
var uniforms := {}
## The HQ (at the home port, first) and the hubs placed since.
var hubs: Array[Hub] = []
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
## Its standing with each vehicle and boat maker (Manufacturers): maker id ->
## likeness 0-100 (a maker not here: the start, 20).
var maker_likes := {}
## Its factories for makers (Manufacturers): [{maker, port, stock (units
## waiting), paid, day (the calendar day it last ran), made (units all time)}].
var factories: Array = []
## Its oil and gas (Energy): its stores at ports (port id -> {commodity:
## tons}: its buildings' tanks, its pipelines'), its storage at the fields
## (field id -> {commodity: tons}), its buildings (port id -> {building id:
## {upgrades, mode}}), and what its rigs made and lost and its buildings ran
## lately (fading a little each day): {made, lost, collected, processed, idle}.
var energy_stores := {}
var energy_sea := {}
var plants := {}
var energy_tally := {}
## The fishing grounds it has picked on the Fishing Grounds screen, and for each
## boat model sent there where its catch is landed and whether it goes in the
## freezer: {ground id: {model id: {port, freeze}}}. Which boats are sent is
## each boat's own (Ship.fish_area).
var fish_areas := {}
## Its research (Research): the sites done (site id -> {day, first, ship}),
## the hidden ones it knows of (site id -> true), and its rolling tallies for
## the rating (trips, dives, dive_fails, gear_lost, contracts, on_time, failed...).
var research := {}
## What it has traded at each port (see GameState._tally_port_trade()): port id ->
## {since (play time it began keeping count there), goods: {commodity id:
## [units bought, money spent, units sold, money earned]}}.
var port_trade := {}
## Per canal id: {crossings, tolls}.
var canal_stats := {}
## Recent money, oldest first: {start (play_time), fleet: {kind: amount},
## ships: {ship name: {kind: amount}}}.
var finance_window: Array = []
## Whether it has the tutorial (chosen when founded), the map's Tutorial
## switch, and the ids of the tips already seen (see TutorialCard).
var tutorials := false
var tutorials_on := true
var tutorial_done: Array[String] = []
## What the player has done, for the tutorial's pacing and the milestones (GameState.note_action()).
var actions_done: Array[String] = []
## Local sales made by its plants (GameState.sell_locally()), and the debt its backstory began with.
var local_sales := 0
var start_debt := 0
## Achievements earned (Achievements: id -> stars, 1 for a badge), and the
## animals seen on the map (Achievements.discover(): the field guide's checks).
var achievements := {}
var discovered: Array[String] = []
## The map's Routes switch, the ship models muted in the activity log, and
## whether the activity log panel is folded away.
var show_active_routes := true
var muted_models: Array[String] = []
var activity_collapsed := false

## GameState.fuel_reserve() for this company, and when it was worked out.
var fuel_reserve := 0.0
var fuel_reserve_time := -1.0


func _init(company_name := "", company_color := "purple", home := "") -> void:
	name = company_name
	color = company_color
	home_port = home


## The type it was founded as.
func start_type() -> String:
	return "" if company_types.is_empty() else str(company_types.keys()[0])


## True if it has this company type (a division).
func has_type(type_id: String) -> bool:
	return company_types.has(type_id)


## The play time it took a type at (INF if it hasn't).
func type_taken(type_id: String) -> float:
	return float(company_types.get(type_id, INF))


func hub_at(port_id: String) -> Hub:
	for hub in hubs:
		if hub.port_id == port_id:
			return hub
	return null


func to_dict() -> Dictionary:
	return {
		"company_name": name,
		"company_color": color,
		"home_port": home_port,
		"money": money,
		"research_points": research_points,
		"company_types": company_types,
		"logo": logo,
		"terminals": terminals,
		"ratings": ratings,
		"delivered": delivered,
		"earlier_containers": earlier_containers,
		"first_prices_used": first_prices_used,
		"hidden_gems": hidden_gems,
		"bank_reserve": bank_reserve,
		"loan": loan,
		"investors": investors,
		"story": story,
		"relations": relations,
		"executives": executives,
		"heads": heads,
		"head_budgets": head_budgets,
		"shares": shares,
		"stakes": stakes,
		"family": family,
		"orders": orders,
		"firm_plans": firm_plans,
		"techs": techs,
		"rnd": rnd,
		"rnd_likes": rnd_likes,
		"rnd_offers": rnd_offers,
		"postings": postings,
		"recruiters": recruiters,
		"loss_quarters": loss_quarters,
		"agreements": agreements,
		"ceo": ceo,
		"uniforms": uniforms,
		"hubs": hubs.map(func(hub: Hub) -> Dictionary: return hub.to_dict()),
		"totals": totals,
		"cold_stores": cold_stores,
		"farm_stores": farm_stores,
		"farm_tally": farm_tally,
		"maker_likes": maker_likes,
		"factories": factories,
		"energy_stores": energy_stores,
		"energy_sea": energy_sea,
		"plants": plants,
		"energy_tally": energy_tally,
		"fish_areas": fish_areas,
		"research": research,
		"port_trade": port_trade,
		"canal_stats": canal_stats,
		"finance_window": finance_window,
		"tutorials": tutorials,
		"tutorials_on": tutorials_on,
		"tutorial_done": tutorial_done,
		"actions_done": actions_done,
		"local_sales": local_sales,
		"start_debt": start_debt,
		"achievements": achievements,
		"discovered": discovered,
		"show_active_routes": show_active_routes,
		"muted_models": muted_models,
		"activity_collapsed": activity_collapsed,
	}


static func from_dict(data: Dictionary) -> Company:
	var company := Company.new(str(data.get("company_name", "")), str(data.get("company_color", "purple")), str(data.get("home_port", "")))
	company.money = int(data.get("money", 0))
	company.research_points = float(data.get("research_points", 0.0))
	company.ratings = data.get("ratings", {}) if data.get("ratings") is Dictionary else {}
	company.ratings_seed = not data.has("ratings")
	company.terminals.assign(data.get("terminals", []))
	company.logo = data.get("logo", {}) if data.get("logo") is Dictionary else {}
	if company.logo.is_empty():  # (Saves from before logos: one made up from its colour.)
		company.logo = CompanyLogo.default_logo(company.color)
	var types: Variant = data.get("company_types", {})
	if types is Dictionary:
		for type_id: String in types:
			company.company_types[type_id] = float(types[type_id])
	for commodity_id: String in data.get("delivered", {}):
		var now := GameData.current_commodity(commodity_id)
		company.delivered[now] = int(company.delivered.get(now, 0)) + int(data.delivered[commodity_id])
	company.earlier_containers = int(data.get("earlier_containers", 0))
	if not data.has("delivered"):  # Saves from before per-commodity counts: their container total.
		company.earlier_containers = int(data.get("containers_delivered", 0))
	company.first_prices_used.assign(data.get("first_prices_used", []))
	company.hidden_gems.assign(data.get("hidden_gems", []))
	company.bank_reserve = int(data.get("bank_reserve", 0))
	company.loan = int(data.get("loan", 0))
	company.investors = data.get("investors", {}) if data.get("investors") is Dictionary else {}
	company.story = str(data.get("story", ""))
	company.actions_done.assign(data.get("actions_done", []))
	company.local_sales = int(data.get("local_sales", 0))
	company.start_debt = int(data.get("start_debt", 0))
	company.relations = data.get("relations", {}) if data.get("relations") is Dictionary else {}
	company.executives = data.get("executives", {}) if data.get("executives") is Dictionary else {}
	company.heads = data.get("heads", {}) if data.get("heads") is Dictionary else {}
	company.head_budgets = data.get("head_budgets", {}) if data.get("head_budgets") is Dictionary else {}
	company.shares = data.get("shares", {}) if data.get("shares") is Dictionary else {}
	company.stakes = data.get("stakes", {}) if data.get("stakes") is Dictionary else {}
	company.family = data.get("family", {}) if data.get("family") is Dictionary else {}
	company.orders = data.get("orders", []) if data.get("orders") is Array else []
	company.firm_plans = data.get("firm_plans", {}) if data.get("firm_plans") is Dictionary else {}
	company.techs = data.get("techs", {}) if data.get("techs") is Dictionary else {}
	company.rnd = data.get("rnd", {}) if data.get("rnd") is Dictionary else {}
	company.rnd_likes = data.get("rnd_likes", {}) if data.get("rnd_likes") is Dictionary else {}
	company.rnd_offers = data.get("rnd_offers", {}) if data.get("rnd_offers") is Dictionary else {}
	company.postings = data.get("postings", []) if data.get("postings") is Array else []
	company.recruiters = int(data.get("recruiters", 0))
	company.loss_quarters = int(data.get("loss_quarters", 0))
	company.agreements = data.get("agreements", {}) if data.get("agreements") is Dictionary else {}
	company.ceo = data.get("ceo", {})
	company.uniforms = data.get("uniforms", {}) if data.get("uniforms") is Dictionary else {}
	if company.ceo.is_empty():  # Saves from before CEOs: made up, the same each load.
		company.ceo = Company.random_ceo(absi(company.name.hash()))
	for hub_data: Dictionary in data.get("hubs", []):
		company.hubs.append(Hub.from_dict(hub_data))
	if company.hubs.is_empty():  # Saves from before hubs: the HQ at the home port.
		company.hubs.append(Hub.new(company.home_port, true))
	company.totals = data.get("totals", {})
	company.cold_stores = data.get("cold_stores", {})
	company.farm_stores = data.get("farm_stores", {}) if data.get("farm_stores") is Dictionary else {}
	company.farm_tally = data.get("farm_tally", {}) if data.get("farm_tally") is Dictionary else {}
	company.maker_likes = data.get("maker_likes", {}) if data.get("maker_likes") is Dictionary else {}
	company.factories = data.get("factories", []) if data.get("factories") is Array else []
	company.energy_stores = data.get("energy_stores", {}) if data.get("energy_stores") is Dictionary else {}
	company.energy_sea = data.get("energy_sea", {}) if data.get("energy_sea") is Dictionary else {}
	company.plants = data.get("plants", {}) if data.get("plants") is Dictionary else {}
	company.energy_tally = data.get("energy_tally", {}) if data.get("energy_tally") is Dictionary else {}
	company.fish_areas = data.get("fish_areas", {}) if data.get("fish_areas") is Dictionary else {}
	company.research = data.get("research", {}) if data.get("research") is Dictionary else {}
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
			"company_types":
				company_types = {}
				for type_id: String in value:
					company_types[type_id] = float(value[type_id])
			"first_prices_used", "tutorial_done", "muted_models", "discovered", "terminals":
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

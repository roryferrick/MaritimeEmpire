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
## Whether the hidden gem has been claimed this run.
var hidden_gem_claimed := false
## Total company XP from deliveries; see Progression for levels.
var xp := 0.0
## Money cargo purchases leave in the bank (set on the Finances screen).
var bank_reserve := 0
## The HQ (at the home port, first) and the hubs placed since.
var hubs: Array[Hub] = []
## All-time totals for each of GameState.MONEY_KINDS.
var totals := {}
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
## The map's Routes switch, the ship models muted in the activity log, and
## whether the activity log panel is folded away.
var show_active_routes := true
var muted_models: Array[String] = []
var activity_collapsed := false

## level(), and the XP it was worked out for.
var _level := 1
var _level_xp := -1.0
## GameState.fuel_reserve() for this company, and when it was worked out.
var fuel_reserve := 0.0
var fuel_reserve_time := -1.0


func _init(company_name := "", company_color := "purple", home := "") -> void:
	name = company_name
	color = company_color
	home_port = home


## Its company level, worked out again only when its XP changes (it walks
## the level costs, and the sim asks often).
func level() -> int:
	if xp != _level_xp:
		_level_xp = xp
		_level = int(Progression.company_level(xp).level)
	return _level


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
		"home_port": home_port,
		"money": money,
		"company_xp": xp,
		"delivered": delivered,
		"earlier_containers": earlier_containers,
		"first_prices_used": first_prices_used,
		"mega_upgrades": mega_upgrades,
		"hidden_gem_claimed": hidden_gem_claimed,
		"bank_reserve": bank_reserve,
		"hubs": hubs.map(func(hub: Hub) -> Dictionary: return hub.to_dict()),
		"totals": totals,
		"canal_stats": canal_stats,
		"finance_window": finance_window,
		"tutorials": tutorials,
		"tutorials_on": tutorials_on,
		"tutorial_done": tutorial_done,
		"show_active_routes": show_active_routes,
		"muted_models": muted_models,
		"activity_collapsed": activity_collapsed,
	}


static func from_dict(data: Dictionary) -> Company:
	var company := Company.new(str(data.get("company_name", "")), str(data.get("company_color", "purple")), str(data.get("home_port", "")))
	company.money = int(data.get("money", 0))
	company.xp = float(data.get("company_xp", 0.0))
	for commodity_id: String in data.get("delivered", {}):
		company.delivered[commodity_id] = int(data.delivered[commodity_id])
	company.earlier_containers = int(data.get("earlier_containers", 0))
	if not data.has("delivered"):  # Saves from before per-commodity counts: their container total.
		company.earlier_containers = int(data.get("containers_delivered", 0))
	company.first_prices_used.assign(data.get("first_prices_used", []))
	company.mega_upgrades.assign(data.get("mega_upgrades", []))
	company.hidden_gem_claimed = bool(data.get("hidden_gem_claimed", false))
	company.bank_reserve = int(data.get("bank_reserve", 0))
	for hub_data: Dictionary in data.get("hubs", []):
		company.hubs.append(Hub.from_dict(hub_data))
	if company.hubs.is_empty():  # Saves from before hubs: the HQ at the home port.
		company.hubs.append(Hub.new(company.home_port, true))
	company.totals = data.get("totals", {})
	company.canal_stats = data.get("canal_stats", {})
	company.finance_window = data.get("finance_window", [])
	company.tutorials = bool(data.get("tutorials", false))
	company.tutorials_on = bool(data.get("tutorials_on", true))
	company.tutorial_done.assign(data.get("tutorial_done", []))
	company.show_active_routes = bool(data.get("show_active_routes", true))
	company.muted_models.assign(data.get("muted_models", []))
	company.activity_collapsed = bool(data.get("activity_collapsed", false))
	return company

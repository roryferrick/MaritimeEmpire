# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Technology
extends RefCounted
## Technology (data/technology.json; DESIGN_LIVING_WORLD.md M5): a tree of
## techs in six branches, published to the world over the years by the R&D
## companies (step()), each licensed for a fee scaled to the fleet
## (license()), or had early and cheaper from an R&D company that likes the
## company (Company.rnd_likes: liking from licences, fitting its upgrades,
## trading at its port and selling it research data). A company develops one
## tech at a time itself (set_rnd(): its banked research points and a monthly
## budget, faster with the CTO and a Technology centre); done before the
## world, it holds the tech alone for exclusive_years with royalties, and the
## world waits. A tech's perk applies to the whole fleet at once (factor());
## its upgrade is fitted ship by ship in drydock (ShipParts), and new ships
## ordered come with it (Shipyards).

signal changed
## A tech the company can now have: how = "licence" (published), "early" (an R&D company's early offer).
signal offered(company: Company, tech_id: String, how: String)
## The company's own R&D finished a tech (exclusive if the world hadn't published it).
signal developed(company: Company, tech_id: String, exclusive: bool)

const PATH := "res://data/technology.json"

static var _data := {}
static var _techs_by_id := {}
static var _rnd_by_id := {}

var _state: Node  # GameState
## Published techs: tech id -> calendar time.
var published := {}
## When each tech is due (calendar time), from its year and the seed.
var _due := {}
var _month := -1
var _factor_cache := {}


func _init(state: Node) -> void:
	_state = state


static func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		_data = JSON.parse_string(file.get_as_text()) if file != null else {techs = [], companies = []}
		for tech: Dictionary in _data.get("techs", []):
			_techs_by_id[tech.id] = tech
		for rnd: Dictionary in _data.get("companies", []):
			_rnd_by_id[rnd.id] = rnd
	return _data


static func setting(key: String, default: Variant = null) -> Variant:
	return (data().get("settings", {}) as Dictionary).get(key, default)


static func techs() -> Array:
	return data().get("techs", [])


static func tech(id: String) -> Dictionary:
	data()
	return _techs_by_id.get(id, {})


static func branches() -> Dictionary:
	return data().get("branches", {})


static func companies() -> Array:
	return data().get("companies", [])


static func rnd(id: String) -> Dictionary:
	data()
	return _rnd_by_id.get(id, {})


func reset() -> void:
	published = {}
	_due = {}
	_month = -1
	_factor_cache = {}


## The publication dates, from the seed: each tech in its year, some months in.
func _schedule() -> void:
	if not _due.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_state.world.seed) + 77 if _state.world != null else 77
	for each: Dictionary in techs():
		var date := Time.get_unix_time_from_datetime_dict({year = int(each.year), month = 1 + rng.randi() % 12, day = 1 + rng.randi() % 28, hour = 0, minute = 0, second = 0})
		_due[each.id] = int(date)


func due(tech_id: String) -> int:
	_schedule()
	return int(_due.get(tech_id, 0))


# --- Holding ---------------------------------------------------------------------------------

func holds(company: Company, tech_id: String) -> bool:
	return company.techs.has(tech_id)


## Whether a company is the only holder of a tech still (its own R&D, within exclusive_years).
func exclusive(company: Company, tech_id: String) -> bool:
	var entry: Dictionary = company.techs.get(tech_id, {})
	return not entry.is_empty() and int(entry.get("exclusive_until", 0)) > _state.calendar_time()


## Whether any player company holds a tech exclusively now (the world's publication waits).
func _exclusive_anywhere(tech_id: String) -> bool:
	for company: Company in _state.all_companies():
		if exclusive(company, tech_id):
			return true
	return false


func liking(company: Company, rnd_id: String) -> float:
	return float(company.rnd_likes.get(rnd_id, float(setting("like_start", 20))))


func _like(company: Company, rnd_id: String, amount: float) -> void:
	company.rnd_likes[rnd_id] = clampf(liking(company, rnd_id) + amount, 0.0, 100.0)


## The company's fleet at list price (the licence fee scales with it).
func fleet_value(company: Company) -> float:
	var total := 0.0
	for ship: Ship in _state.fleet(company):
		total += float(ship.model().get("price", 0))
	return total


## What a tech costs a company to license: the tier's share of its fleet, at least the tier's floor; early_price of that from an R&D company that likes it.
func licence_cost(company: Company, tech_id: String) -> int:
	var each := tech(tech_id)
	if each.is_empty():
		return 0
	var tier := clampi(int(each.tier), 1, 3)
	var shares: Array = setting("licence", [0.004, 0.008, 0.015])
	var floors: Array = setting("floor", [250000, 500000, 1000000])
	var cost := maxf(fleet_value(company) * float(shares[tier - 1]), float(floors[tier - 1]))
	if liking(company, str(each.by)) >= float(setting("early_at", 60)):
		cost *= float(setting("early_price", 0.7))
	return roundi(cost)


## How a company stands to a tech: "held", "licence" (published), "early" (offered early), "future" (not yet), with the price.
func standing(company: Company, tech_id: String) -> Dictionary:
	var each := tech(tech_id)
	if each.is_empty():
		return {how = "future", price = 0}
	if holds(company, tech_id):
		return {how = "held", price = 0}
	if published.has(tech_id):
		return {how = "licence", price = licence_cost(company, tech_id)}
	var now: int = _state.calendar_time()
	if liking(company, str(each.by)) >= float(setting("early_at", 60)) and now >= due(tech_id) - int(setting("early_months", 12)) * 2629800 and not _exclusive_anywhere(tech_id):
		return {how = "early", price = licence_cost(company, tech_id)}
	return {how = "future", price = licence_cost(company, tech_id)}


func license_error(company: Company, tech_id: String) -> String:
	var state := standing(company, tech_id)
	match str(state.how):
		"held":
			return "Held already"
		"future":
			return "Not published yet"
	if company.money < int(state.price) or _state.in_debt(company):
		return "Costs %s" % Fmt.money(int(state.price))
	return ""


func license(company: Company, tech_id: String) -> String:
	var error := license_error(company, tech_id)
	if not error.is_empty():
		return error
	var state := standing(company, tech_id)
	var each := tech(tech_id)
	_state._add_money(company, -int(state.price))
	_state._record(null, "technology", float(state.price), company)
	company.techs[tech_id] = {since = _state.calendar_time(), how = str(state.how), exclusive_until = 0}
	_like(company, str(each.by), float(setting("like_licence", 5)))
	_factor_cache.erase(company)
	if company == _state.company:
		ActivityLog.add("Licensed %s from %s for %s%s." % [str(each.name), str(rnd(str(each.by)).get("name", "")), Fmt.money(int(state.price)), " (early)" if str(state.how) == "early" else ""], ActivityLog.Kind.GOOD)
	_apply_perk_note(company, each)
	changed.emit()
	return ""


func _apply_perk_note(company: Company, each: Dictionary) -> void:
	for ship: Ship in _state.fleet(company):
		ship.invalidate_stats()
	if company == _state.company and each.has("upgrade"):
		ActivityLog.add("%s: fit the %s to your ships in drydock; new ships come with it." % [str(each.name), str((each.upgrade as Dictionary).name).to_lower()], ActivityLog.Kind.INFO)


# --- Own R&D -------------------------------------------------------------------------------

## Sets the tech the company works on itself and its monthly budget (Company.rnd: {tech, budget, progress}).
func set_rnd(company: Company, tech_id: String, budget: int) -> String:
	if not tech_id.is_empty() and (tech(tech_id).is_empty() or holds(company, tech_id)):
		return "Not that one"
	var plan: Dictionary = company.rnd
	if str(plan.get("tech", "")) != tech_id:
		plan.progress = 0.0  # (A change of tack: the work so far is lost.)
	plan.tech = tech_id
	plan.budget = maxi(budget, 0)
	changed.emit()
	return ""


## Points a month from the budget, with the CTO and a Technology centre.
func monthly_points(company: Company) -> float:
	var plan: Dictionary = company.rnd
	var budget := float(plan.get("budget", 0))
	var from_budget := budget / float(setting("point_cost", 20000))
	var centre := 0.0
	for hub: Hub in company.hubs:
		centre = maxf(centre, hub.effect_of("research"))
	return from_budget * People.factor(company, "research", true) * (1.0 + centre)


func rnd_cost(tech_id: String) -> float:
	var costs: Array = setting("cost", [400, 1000, 2500])
	return float(costs[clampi(int(tech(tech_id).get("tier", 1)), 1, 3) - 1])


func _monthly_rnd(company: Company) -> void:
	var plan: Dictionary = company.rnd
	var tech_id := str(plan.get("tech", ""))
	if tech_id.is_empty() or holds(company, tech_id):
		return
	var budget := int(plan.get("budget", 0))
	if budget > 0:
		if company.money < budget:
			if company == _state.company:
				ActivityLog.add("No money for this month's R&D budget (%s)." % Fmt.money(budget), ActivityLog.Kind.BAD)
			budget = 0
		else:
			_state._add_money(company, -budget)
			_state._record(null, "technology", float(budget), company)
	var points := budget / float(setting("point_cost", 20000)) * People.factor(company, "research", true)
	var centre := 0.0
	for hub: Hub in company.hubs:
		centre = maxf(centre, hub.effect_of("research"))
	points *= 1.0 + centre
	var draw := company.research_points * float(setting("points_draw", 0.25))
	company.research_points -= draw
	points += draw
	plan.progress = float(plan.get("progress", 0.0)) + points
	if float(plan.progress) >= rnd_cost(tech_id):
		var each := tech(tech_id)
		var first := not published.has(tech_id)
		company.techs[tech_id] = {since = _state.calendar_time(), how = "developed", exclusive_until = _state.calendar_time() + int(float(setting("exclusive_years", 2)) * 365.25 * 86400.0) if first else 0}
		plan.tech = ""
		plan.progress = 0.0
		_factor_cache.erase(company)
		_apply_perk_note(company, each)
		if company == _state.company:
			ActivityLog.add("Your R&D has finished %s%s." % [str(each.name), ": yours alone for two years; rivals pay royalties" if first else ""], ActivityLog.Kind.GOOD)
		if _state.news != null:
			_state.news.add("company", "%s develops %s%s" % [company.name, str(each.name), " ahead of the world" if first else ""], {})
		developed.emit(company, tech_id, first)
	changed.emit()


## Royalties from the rivals licensing a tech the company holds alone.
func _monthly_royalties(company: Company) -> void:
	var rates: Array = setting("royalty_a_month", [40000, 90000, 200000])
	for tech_id: String in company.techs:
		if exclusive(company, tech_id):
			var amount := int(rates[clampi(int(tech(tech_id).get("tier", 1)), 1, 3) - 1])
			_state._add_money(company, amount)
			_state._record(null, "technology", -float(amount), company)


# --- Selling research data ---------------------------------------------------------------------

func sell_data_error(company: Company, rnd_id: String) -> String:
	if rnd(rnd_id).is_empty():
		return "No such company"
	var points := float(setting("data_points", 100))
	if company.research_points < points:
		return "Needs %d research points (%d banked)" % [roundi(points), roundi(company.research_points)]
	return ""


## Sells a batch of research points to an R&D company: money and liking.
func sell_data(company: Company, rnd_id: String) -> String:
	var error := sell_data_error(company, rnd_id)
	if not error.is_empty():
		return error
	company.research_points -= float(setting("data_points", 100))
	var price := int(setting("data_price", 600000))
	_state._add_money(company, price)
	_state._record(null, "technology", -float(price), company)
	_like(company, rnd_id, float(setting("like_data", 10)))
	if company == _state.company:
		ActivityLog.add("Sold survey data to %s for %s; they think better of you." % [str(rnd(rnd_id).name), Fmt.money(price)], ActivityLog.Kind.GOOD)
	changed.emit()
	return ""


## An upgrade of an R&D company's tech fitted (GameState._advance_drydock()): it likes the company more.
func note_fitted(company: Company, upgrade_id: String) -> void:
	for each: Dictionary in techs():
		if each.has("upgrade") and str((each.upgrade as Dictionary).get("id", each.id)) == upgrade_id:
			_like(company, str(each.by), float(setting("like_fit", 3)))


# --- Perks -----------------------------------------------------------------------------------

## The held techs' perks on a stat ("fuel", "speed", "wear", "breakdowns", "dock") for a ship category, as a factor.
func factor(company: Company, stat: String, category: String) -> float:
	if company == null or company.techs.is_empty():
		return 1.0
	var cached: Dictionary = _factor_cache.get_or_add(company, {})
	var key := "%s|%s" % [stat, category]
	if cached.has(key):
		return float(cached[key])
	var out := 1.0
	for tech_id: String in company.techs:
		var perk: Dictionary = tech(tech_id).get("perk", {})
		if perk.is_empty() or str(perk.get("stat", "")) != stat:
			continue
		var categories: Array = perk.get("categories", [])
		if not categories.is_empty() and not category in categories:
			continue
		out *= float(perk.get("value", 1.0))
	cached[key] = out
	return out


## The upgrades (from held techs) for a part: [{id, part, name, cost, effects, tech}].
func upgrades_for_part(company: Company, part_id: String) -> Array:
	var out := []
	for tech_id: String in company.techs:
		var each := tech(tech_id)
		var upgrade: Dictionary = each.get("upgrade", {})
		if not upgrade.is_empty() and str(upgrade.part) == part_id:
			out.append({id = str(upgrade.get("id", tech_id)), part = part_id, name = str(upgrade.name), cost = float(upgrade.cost), effects = upgrade.get("effects", {}), tech = tech_id})
	return out


## An upgrade of any held-or-not tech by its id (ShipParts.upgrade_info()).
static func upgrade_by_id(upgrade_id: String) -> Dictionary:
	for each: Dictionary in techs():
		var upgrade: Dictionary = each.get("upgrade", {})
		if not upgrade.is_empty() and str(upgrade.get("id", each.id)) == upgrade_id:
			return {id = upgrade_id, part = str(upgrade.part), name = str(upgrade.name), cost = float(upgrade.cost), effects = upgrade.get("effects", {}), tech = str(each.id)}
	return {}


# --- Each month ----------------------------------------------------------------------------

func step(_delta: float) -> void:
	var month: int = _state.history.month_now() if _state.history != null else -1
	if month == _month:
		return
	var first := _month < 0
	_month = month
	_schedule()
	var now: int = _state.calendar_time()
	for each: Dictionary in techs():
		var id := str(each.id)
		if published.has(id) or now < int(_due[id]) or _exclusive_anywhere(id):
			continue
		published[id] = now
		if _state.news != null and _state.warm_up_left <= 0:
			_state.news.add("world", "%s publishes %s" % [str(rnd(str(each.by)).get("name", "")), str(each.name)], {})
		if not first:
			for company: Company in _state.all_companies():
				if not holds(company, id):
					offered.emit(company, id, "licence")
	if first:
		return
	for company: Company in _state.all_companies():
		_monthly_rnd(company)
		_monthly_royalties(company)
		_monthly_liking(company)
		for each: Dictionary in techs():
			var id := str(each.id)
			if published.has(id) or holds(company, id):
				continue
			var state := standing(company, id)
			if str(state.how) == "early" and not bool((company.rnd_offers as Dictionary).get(id, false)):
				company.rnd_offers[id] = true
				offered.emit(company, id, "early")
	changed.emit()


## Trading at an R&D company's port last month pleases it a little.
func _monthly_liking(company: Company) -> void:
	var month_s: float = 30.0 * 86400.0 / maxf(float(_state.calendar_seconds_per_second()), 1.0)  # (A calendar month of play seconds.)
	for info: Dictionary in companies():
		var trade: Dictionary = company.port_trade.get(str(info.port), {})
		if not trade.is_empty() and float(trade.get("last", -INF)) >= float(_state.play_time) - month_s:
			_like(company, str(info.id), float(setting("like_trade", 1)))


func to_dict() -> Dictionary:
	return {published = published, month = _month}


func from_dict(data_in: Dictionary) -> void:
	published = data_in.get("published", {}) if data_in.get("published") is Dictionary else {}
	_month = int(data_in.get("month", -1))
	_due = {}
	_factor_cache = {}
	changed.emit()

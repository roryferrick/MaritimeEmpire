# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name People
extends RefCounted
## The people (DESIGN_LIVING_WORLD.md M3): the company's executives (ROLES:
## CFO, COO, CTO, CCO, CPO and Legal, in Company.executives), its department
## heads (one per trade group and market region, Company.heads, each with a
## budget of contracts to take: run_heads()), and its ships' officers
## (Ship.captains), every one a character (Characters: name, look, traits,
## skills, age, nationality). Skills work for the company (factor(): about
## PER_POINT a point over Traits.BASE_SKILL on what a role touches, within
## CAP; captain_factor() for a ship's captain). A rolling job market of
## MARKET_SIZE candidates (candidates), a third replaced each calendar month;
## hiring, poaching from the paper firms (a premium; the firm remembers),
## promotion from a ship and the headhunter. Everyone ages a month at a time:
## retirement at RETIRE_AGE with notice, a small chance of sudden death rising
## with age, the CEO's going bringing succession. Saved with the game.

signal changed
## Someone left a company: role text, name, why ("retired", "died").
signal person_left(company: Company, role: String, name: String, why: String)
## A company's CEO retired or died: a successor is wanted (the card).
signal succession_needed(company: Company, why: String)

## The executive roles: id -> {name, skills (what the role draws on), effects
## {key: weight}: what a point of the role's skills over the base does}.
const ROLES := {
	cfo = {name = "Chief Financial Officer", short = "CFO", skills = ["finance"], effects = {interest = 1.0, fees = 0.5}},
	coo = {name = "Chief Operating Officer", short = "COO", skills = ["leadership", "seamanship"], effects = {dock = 1.0, wages = 0.5}},
	cto = {name = "Chief Technology Officer", short = "CTO", skills = ["engineering"], effects = {wear = 1.0, breakdowns = 1.0, research = 1.0}},
	cco = {name = "Chief Commercial Officer", short = "CCO", skills = ["negotiation"], effects = {rates = 1.0, standing = 1.0}},
	cpo = {name = "Chief People Officer", short = "CPO", skills = ["leadership"], effects = {wages = 1.0, hiring = 1.0}},
	legal = {name = "General Counsel", short = "Legal", skills = ["negotiation", "finance"], effects = {penalties = 1.0, fees = 0.5}},
}
const ROLE_ORDER := ["cfo", "coo", "cto", "cco", "cpo", "legal"]
const PER_POINT := 0.01
const CAP := 0.25
## Salaries a year by kind, x the candidate's quality.
const OFFICER_SALARY := 60000.0
const HEAD_SALARY := 150000.0
const EXEC_SALARY := 300000.0
const MARKET_SIZE := 20
const REFRESH_SHARE := 0.34
const POACH_PREMIUM := 0.3
const HEADHUNT_FEE := 0.1
const RETIRE_AGE := [62, 70]
const NOTICE_MONTHS := 3
## Yearly odds of sudden death at 40 and at 75 (between, a line).
const DEATH_AT_40 := 0.002
const DEATH_AT_75 := 0.03
const DAYS_A_YEAR := 365.25

var _state: Node  # GameState
## The job market: [{id, character, kind ("officer", "head", "exec"), role (an exec role for an exec, "" else), ask (a year), employer (a firm index, -1), min_tier}].
var candidates: Array = []
var _next_id := 1
var _month := -1


func _init(state: Node) -> void:
	_state = state


func reset() -> void:
	candidates.clear()
	_next_id = 1
	_month = -1


# --- Effects -----------------------------------------------------------------------------

## What a company's executives do for a key ("interest", "fees", "dock", "wages",
## "wear", "breakdowns", "research", "rates", "standing", "hiring",
## "penalties"): the sum over its roles of PER_POINT a point of the role's
## skills over the base, x the role's weight, within CAP.
static func bonus(company: Company, key: String) -> float:
	if company == null:
		return 0.0
	var total := 0.0
	for role: String in ROLE_ORDER:
		var person: Dictionary = company.executives.get(role, {})
		if person.is_empty():
			continue
		var info: Dictionary = ROLES[role]
		var weight := float((info.effects as Dictionary).get(key, 0.0))
		if weight == 0.0:
			continue
		var skills := Traits.skills_of(person)
		var points := 0.0
		for skill: String in info.skills:
			points += float(skills.get(skill, Traits.BASE_SKILL)) - Traits.BASE_SKILL
		total += PER_POINT * points / float((info.skills as Array).size()) * weight
	return clampf(total, -CAP, CAP)


## 1 + bonus (something that goes up: rates, research), or 1 - bonus (something that goes down: wear, fees).
static func factor(company: Company, key: String, up := false) -> float:
	var b := bonus(company, key)
	return maxf(1.0 + b if up else 1.0 - b, 0.0)


## A ship's captain's skill for a key ("speed", "fuel", "wear", "breakdowns", "wages"), as a factor.
static func captain_factor(ship: Ship, key: String, up := false) -> float:
	if ship.captains.is_empty():
		return 1.0
	var skills := Traits.skills_of(ship.captains[0])
	var skill := "seamanship" if key in ["speed", "fuel"] else ("engineering" if key in ["wear", "breakdowns"] else "leadership")
	var b := clampf(PER_POINT * (float(skills.get(skill, Traits.BASE_SKILL)) - Traits.BASE_SKILL), -CAP, CAP)
	return maxf(1.0 + b if up else 1.0 - b, 0.0)


# --- People of a company ------------------------------------------------------------------

## Every character a company employs: [{who, role (text), kind, key}].
func employees(company: Company) -> Array:
	var out := [{who = company.ceo, role = "Chief Executive", kind = "ceo", key = ""}]
	for role: String in ROLE_ORDER:
		var person: Dictionary = company.executives.get(role, {})
		if not person.is_empty():
			out.append({who = person, role = str(ROLES[role].name), kind = "exec", key = role})
	for key: String in company.heads:
		out.append({who = company.heads[key], role = head_title(key), kind = "head", key = key})
	for ship: Ship in _state.fleet(company):
		for i in ship.captains.size():
			out.append({who = ship.captains[i], role = "%s of %s" % [Characters.rank(i), ship.name], kind = "officer", key = "%d|%d" % [ship.id, i]})
	return out


## "Head of Container ships, Northern Europe & Atlantic".
static func head_title(key: String) -> String:
	var parts := key.split("|")
	if parts.size() != 2:
		return "Head of %s" % key
	return "Head of %s, %s" % [group_name(parts[0]), region_name(parts[1])]


static func group_name(category: String) -> String:
	for line: Array in PortPopup.MARKET_LINES:
		if line[1] == category:
			return str(line[0])
	return category.capitalize()


static func region_name(region_id: String) -> String:
	for region: Dictionary in GameData.markets.get("regions", []):
		if region.id == region_id:
			return str(region.name)
	return region_id.capitalize()


## The trade groups a company can head (the ship categories of its types that carry cargo).
static func groups_of(company: Company) -> Array:
	var out := []
	for type_id: String in company.company_types:
		for category: String in Progression.company_type(type_id).get("categories", []):
			if PortPopup.MARKET_LINES.any(func(line: Array) -> bool: return line[1] == category):
				out.append(category)
	return out


# --- The job market ------------------------------------------------------------------------

func step(_delta: float) -> void:
	var month: int = _state.history.month_now() if _state.history != null else -1
	if month == _month:
		return
	var first := _month < 0
	_month = month
	_refresh_market(first)
	if not first:
		_age_everyone()


## Fills the market (a third replaced each month).
func _refresh_market(fill_all: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%d" % [(_state.world as WorldEconomy).seed, _month])
	if not fill_all:
		var drop := roundi(candidates.size() * REFRESH_SHARE)
		for i in drop:
			if not candidates.is_empty():
				candidates.remove_at(rng.randi() % candidates.size())
	while candidates.size() < MARKET_SIZE:
		candidates.append(_candidate(rng, ["officer", "officer", "head", "exec"][rng.randi() % 4]))
	changed.emit()


## A candidate of a kind: a character of working age with role-leaning skills and a salary ask by quality.
func _candidate(rng: RandomNumberGenerator, kind: String, strong := false, role := "") -> Dictionary:
	var person := Characters.random_person(rng, kind, "")
	if role.is_empty() and kind == "exec":
		role = ROLE_ORDER[rng.randi() % ROLE_ORDER.size()]
	if not role.is_empty():
		for skill: String in ROLES[role].skills:
			person.skills[skill] = int(person.skills.get(skill, Traits.BASE_SKILL)) + 2 + (3 if strong else 0)
	elif kind == "officer":
		person.skills.seamanship = int(person.skills.get("seamanship", Traits.BASE_SKILL)) + 2 + (3 if strong else 0)
	elif strong:
		person.skills.negotiation = int(person.skills.get("negotiation", Traits.BASE_SKILL)) + 4
	var firms: ShippingFirms = _state.firms
	var employer := -1
	if rng.randf() < 0.3 and not firms.firms.is_empty():
		employer = rng.randi() % firms.firms.size()
		person.nationality = str(firms.firms[employer].country)
	var quality := _quality(person)
	var base := OFFICER_SALARY if kind == "officer" else (HEAD_SALARY if kind == "head" else EXEC_SALARY)
	var ask := roundi(base * quality * (1.0 + POACH_PREMIUM if employer >= 0 else 1.0) / 1000.0) * 1000
	var out := {id = _next_id, character = person, kind = kind, role = role, ask = ask, employer = employer, min_tier = "known" if quality > 1.3 and rng.randf() < 0.5 else ""}
	_next_id += 1
	return out


## A person's quality against the base: their skills' mean over the base, as a factor 0.6 to about 2.
static func _quality(person: Dictionary) -> float:
	var skills := Traits.skills_of(person)
	var total := 0.0
	for skill: String in Traits.SKILLS:
		total += float(skills.get(skill, Traits.BASE_SKILL))
	return clampf(0.6 + 0.4 * (total / Traits.SKILLS.size()) / Traits.BASE_SKILL, 0.6, 2.5)


func candidate_by_id(id: int) -> Dictionary:
	for each: Dictionary in candidates:
		if int(each.id) == id:
			return each
	return {}


## Why a company can't hire a candidate, or "".
func hire_error(company: Company, candidate: Dictionary) -> String:
	if candidate.is_empty():
		return "Gone"
	var tier := str(candidate.get("min_tier", ""))
	if not tier.is_empty():
		var country := str((candidate.character as Dictionary).get("nationality", ""))
		if not Contracts.tier_at_least(Contracts.tier_of(Contracts.country_standing(company, country)), tier):
			return "Only joins a company %s or better in %s" % [Contracts.tier_name(tier), str(WorldEconomy.country(country).get("name", country))]
	var cost := hiring_cost(company, candidate)
	if cost > 0 and (company.money < cost or _state.in_debt(company)):
		return "Signing costs %s" % Fmt.money(cost)
	return ""


## What hiring costs up front: a poached person's signing bonus (POACH_PREMIUM of a year), less with a good CPO.
func hiring_cost(company: Company, candidate: Dictionary) -> int:
	if int(candidate.get("employer", -1)) < 0:
		return 0
	return roundi(float(candidate.ask) * POACH_PREMIUM * factor(company, "hiring"))


## Hires a candidate into a place: kind "exec" (key the role), "head" (key
## "group|region", with a budget) or "officer" (key "ship id|index").
func hire(company: Company, candidate: Dictionary, kind: String, key: String, budget := 0) -> String:
	var error := hire_error(company, candidate)
	if not error.is_empty():
		return error
	var person: Dictionary = (candidate.character as Dictionary).duplicate(true)
	person.salary = int(candidate.ask)
	person.hired = _state.calendar_time()
	var placed := place(company, person, kind, key, budget)
	if not placed.is_empty():
		return placed
	var cost := hiring_cost(company, candidate)
	if cost > 0:
		_state._add_money(company, -cost)
		_state._record(null, "salaries", cost, company)
		var firms: ShippingFirms = _state.firms
		var firm: Dictionary = firms.firms[int(candidate.employer)]
		firm.poached = int(firm.get("poached", 0)) + 1  # (The firm remembers: M4.)
		if _state.news != null:
			_state.news.add("company", "%s poaches %s from %s" % [company.name, str(person.name), str(firm.name)], {firm = int(candidate.employer)})
	candidates.erase(candidate)
	changed.emit()
	return ""


## Puts a person in a place (hired, promoted or a successor's old post refilled).
func place(company: Company, person: Dictionary, kind: String, key: String, budget := 0) -> String:
	match kind:
		"exec":
			if not ROLES.has(key):
				return "No such role"
			company.executives[key] = person
		"head":
			if key.split("|").size() != 2:
				return "No such post"
			company.heads[key] = person
			company.head_budgets[key] = maxi(budget, int(company.head_budgets.get(key, 20000000)))
		"officer":
			var parts := key.split("|")
			var ship: Ship = _state.ship_by_id(int(parts[0])) if parts.size() == 2 else null
			if ship == null or _state.owner_of(ship) != company:
				return "No such ship"
			var index := clampi(int(parts[1]), 0, maxi(ship.captains.size() - 1, 0))
			if ship.captains.is_empty():
				ship.captains.append(person)
			else:
				ship.captains[index] = person
			ship.invalidate_stats()
		_:
			return "No such place"
	changed.emit()
	return ""


## Lets someone go (an executive's or head's post emptied; an officer replaced by a random one).
func dismiss(company: Company, kind: String, key: String) -> void:
	match kind:
		"exec":
			company.executives.erase(key)
		"head":
			company.heads.erase(key)
		"officer":
			var parts := key.split("|")
			var ship: Ship = _state.ship_by_id(int(parts[0])) if parts.size() == 2 else null
			if ship != null and int(parts[1]) < ship.captains.size():
				var rng := RandomNumberGenerator.new()
				rng.randomize()
				ship.captains[int(parts[1])] = Characters.random_person(rng, "officer", "")
				ship.invalidate_stats()
	changed.emit()


## Promotes a ship's officer to an executive role (free; a random officer takes the ship).
func promote(company: Company, ship: Ship, index: int, role: String) -> String:
	if index < 0 or index >= ship.captains.size() or not ROLES.has(role):
		return "No such person or role"
	var person: Dictionary = ship.captains[index]
	person.salary = roundi(EXEC_SALARY * _quality(person) / 1000.0) * 1000
	person.hired = _state.calendar_time()
	company.executives[role] = person
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	ship.captains[index] = Characters.random_person(rng, "officer", "")
	ship.invalidate_stats()
	changed.emit()
	return ""


## The headhunter: for a fee, a strong candidate for a role (or kind) joins the market now.
func headhunt(company: Company, kind: String, role: String) -> String:
	var base := OFFICER_SALARY if kind == "officer" else (HEAD_SALARY if kind == "head" else EXEC_SALARY)
	var fee := roundi(base * 1.5 * HEADHUNT_FEE)
	if company.money < fee or _state.in_debt(company):
		return "The headhunter wants %s" % Fmt.money(fee)
	_state._add_money(company, -fee)
	_state._record(null, "salaries", fee, company)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var found := _candidate(rng, kind, true, role)
	found.employer = -1
	found.min_tier = ""
	candidates.push_front(found)
	changed.emit()
	return ""


## The salaries a company owes for a pay period (its executives' and heads').
func salaries_due(company: Company) -> int:
	var days := float(GameData.config.get("crew", {}).get("period_days", 56))
	var total := 0.0
	for role: String in company.executives:
		total += float((company.executives[role] as Dictionary).get("salary", 0)) * days / DAYS_A_YEAR
	for key: String in company.heads:
		total += float((company.heads[key] as Dictionary).get("salary", 0)) * days / DAYS_A_YEAR
	return roundi(total)


# --- Ageing --------------------------------------------------------------------------------

func _age_everyone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for company: Company in _state.all_companies():
		for entry: Dictionary in employees(company):
			var person: Dictionary = entry.who
			if person.is_empty():
				continue
			person.age = float(person.get("age", 45.0)) + 1.0 / 12.0
			if not person.has("retire_at"):
				person.retire_at = rng.randf_range(float(RETIRE_AGE[0]), float(RETIRE_AGE[1]))
			var age := float(person.age)
			var death := lerpf(DEATH_AT_40, DEATH_AT_75, clampf((age - 40.0) / 35.0, 0.0, 1.0)) / 12.0
			if rng.randf() < death:
				_leaves(company, entry, "died")
				continue
			if age >= float(person.retire_at) - float(NOTICE_MONTHS) / 12.0 and not person.get("notice", false):
				person.notice = true
				if company == _state.company and str(entry.kind) != "officer":
					ActivityLog.add("%s, your %s, means to retire in %d months." % [str(person.name), str(entry.role).to_lower(), NOTICE_MONTHS], ActivityLog.Kind.INFO)
			if age >= float(person.retire_at):
				_leaves(company, entry, "retired")
	changed.emit()


func _leaves(company: Company, entry: Dictionary, why: String) -> void:
	var person: Dictionary = entry.who
	var name := str(person.get("name", ""))
	match str(entry.kind):
		"ceo":
			succession_needed.emit(company, why)
		"exec", "head":
			dismiss(company, str(entry.kind), str(entry.key))
		"officer":
			dismiss(company, "officer", str(entry.key))
	if company == _state.company:
		ActivityLog.add("%s, %s, has %s." % [name, str(entry.role), "died suddenly" if why == "died" else "retired"], ActivityLog.Kind.BAD if why == "died" else ActivityLog.Kind.INFO)
	person_left.emit(company, str(entry.role), name, why)


## A new CEO: an executive (role) steps up, or a hire from the market (candidate id), or a random one.
func succeed(company: Company, kind: String, key: String) -> void:
	var old: Dictionary = company.ceo
	var next := {}
	match kind:
		"exec":
			next = company.executives.get(key, {})
			if not next.is_empty():
				company.executives.erase(key)
		"candidate":
			var candidate := candidate_by_id(int(key))
			if not candidate.is_empty():
				next = (candidate.character as Dictionary).duplicate(true)
				candidates.erase(candidate)
	if next.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		next = Characters.random_person(rng, "exec", "")
	next.erase("notice")
	next.erase("retire_at")
	company.ceo = next
	company.story += " %s took over from %s in %d." % [str(next.name), str(old.get("name", "the founder")), Time.get_datetime_dict_from_unix_time(_state.calendar_time()).year]
	if _state.news != null:
		_state.news.add("company", "%s names %s chief executive" % [company.name, str(next.name)], {})
	_state.logo_changed.emit()  # (The headshot button follows.)
	changed.emit()


# --- Department heads taking offers (Contracts) -------------------------------------------------

## Each head takes offers of their group and region under their budget when an
## idle ship of the company's of the right line can reach the load port, and
## assigns it; their Negotiation nudges the rate (Contracts._refresh_offers()).
func run_heads(company: Company) -> void:
	if company.heads.is_empty():
		return
	var contracts: Contracts = _state.contracts
	for key: String in company.heads:
		var parts := key.split("|")
		if parts.size() != 2:
			continue
		var group := parts[0]
		var region := parts[1]
		var head: Dictionary = company.heads[key]
		var budget := int(company.head_budgets.get(key, 0)) - _taken_value(company, key)
		for offer: Dictionary in contracts.offers.duplicate():
			if not str(offer.kind) in ["voyage", "recurring"] or int(offer.value) > budget:
				continue
			if str(GameData.port_region(str(offer.from)).get("id", "")) != region or not _carried_by(str(offer.good), group):
				continue
			if not contracts.can_sign(company, offer).is_empty():
				continue
			var ship := _idle_ship_for(company, offer)
			if ship == null:
				continue
			var skills := Traits.skills_of(head)
			offer.rate = snappedf(float(offer.rate) * (1.0 + PER_POINT * (float(skills.get("negotiation", Traits.BASE_SKILL)) - Traits.BASE_SKILL)), 0.01)
			offer.value = roundi(float(offer.rate) * int(offer.units) * maxi(int(offer.get("quarters", 0)), 1))
			var contract := contracts.sign_offer(company, offer)
			contract.taken_by = key
			contracts.assign_ship(contract, ship)
			var route: Array[String] = [str(contract.from), str(contract.to)]
			if _state.route_error(route, ship).is_empty():
				_state.assign_route(ship, route)
			budget -= int(contract.value)
			if company == _state.company:
				ActivityLog.add("%s (%s) took %s for %s and put %s on it." % [str(head.name), head_title(key), _state.contract_summary(contract), contracts.party_name(contract), ship.name], ActivityLog.Kind.GOOD)


func _taken_value(company: Company, key: String) -> int:
	var total := 0
	var mine: int = _state.all_companies().find(company)
	for contract: Dictionary in (_state.contracts as Contracts).contracts:
		if str(contract.status) == "active" and int(contract.company) == mine and str(contract.get("taken_by", "")) == key:
			total += int(contract.value)
	return total


static func _carried_by(good: String, category: String) -> bool:
	for model: Dictionary in GameData.ship_models:
		if str(model.get("category", "")) == category and good in model.get("cargo", []):
			return true
	return false


## An idle ship of the company's that carries the offer's good and can reach its load port and make the leg.
func _idle_ship_for(company: Company, offer: Dictionary) -> Ship:
	for ship: Ship in _state.fleet(company):
		if ship.is_service() or ship.contract_id > 0 or not ship.is_docked() or ship.is_lost():
			continue
		if ship.has_route() and not ship.paused:
			continue
		if not str(offer.good) in ship.model().get("cargo", []):
			continue
		if not ship.can_sail(str(offer.from), str(offer.to)):
			continue
		if ship.docked_at != str(offer.from) and not ship.can_sail(ship.docked_at, str(offer.from)):
			continue
		return ship
	return null


# --- Saving --------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {candidates = candidates, next_id = _next_id, month = _month}


func from_dict(data: Dictionary) -> void:
	candidates = data.get("candidates", []) if data.get("candidates") is Array else []
	_next_id = int(data.get("next_id", 1))
	_month = int(data.get("month", -1))
	changed.emit()

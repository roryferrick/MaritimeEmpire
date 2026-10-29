# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name FirmLife
extends RefCounted
## The paper firms' lives (DESIGN_LIVING_WORLD.md, later stages): each month
## a firm with cash and good months orders ships (more hulls on its books),
## one with years of losses sells ships off, and one whose cash stays deep in
## the red goes bankrupt: its ships go to the second-hand market (the player
## has first refusal by card), its name retires and a new firm is founded to
## keep the world at about FIRMS. Now and then a rich firm buys a struggling
## one (a small target gets a rich price; a stubborn leadership never sells
## for less than STUBBORN_PRICE x its value, which no one pays); a player's
## stake in the target is sold at the deal's price or converted, by card.
## Each firm's CEO has a leaning from their traits (leaning(): Expansionist,
## Cautious, Cutthroat, Loyal) that sets how early it grows, how it bids and
## how it treats people, and the CEO changes now and then (succession).
## Everything a firm does to its books is journaled in ShippingFirms so a
## save brings the same firms back (ShippingFirms.journal).

signal changed
## A firm went bankrupt: its ships are on the second-hand market (count listings).
signal bankrupt(firm_index: int, listings: int)
## A merger where the player holds a stake in the target: sell at the price (for the stake) or convert into the buyer.
signal merger_stake(company: Company, buyer: int, target: int, price: float, stake: float)

const LEANINGS := {expansionist = "Expansionist", cautious = "Cautious", cutthroat = "Cutthroat", loyal = "Loyal"}
const LEANING_TEXT := {expansionist = "orders ships early and grows fast, and overreaches", cautious = "hoards cash and rides out the slumps", cutthroat = "underbids on tenders, poaches, and holds a grudge", loyal = "keeps its word and warms fast to friends"}
const ORDER_CASH := {expansionist = 2.0, cautious = 6.0, cutthroat = 3.0, loyal = 3.0}  # Cash in ships' worth before ordering one.
const LOSS_SELL := -0.1  # Cash under this share of the fleet's value, falling for LOSS_MONTHS: a ship sold.
const LOSS_MONTHS := 6
const BROKE := -0.5  # Cash under this share of the fleet's value for BROKE_MONTHS: bankrupt.
const BROKE_MONTHS := 3
const SELL_BACK := 0.6  # What a sold ship fetches, of list.
const BANKRUPT_LISTINGS := 6
const MERGER_CHANCE := 1.0 / 24.0  # A month, world-wide.
const SMALL_PREMIUM := 2.0  # A small target's price, of its value.
const BIG_PREMIUM := 1.3
const STUBBORN_SHARE := 0.3
const STUBBORN_PRICE := 5.0
const SUCCESSION_YEARLY := 0.04
const HISTORY := 12

var _state: Node  # GameState
var _month := -1


func _init(state: Node) -> void:
	_state = state


func reset() -> void:
	_month = -1


# --- Leanings -------------------------------------------------------------------------------

## A firm's CEO's leaning from their traits (kept on the firm; a new CEO brings a new one).
static func leaning(firm: Dictionary) -> String:
	if firm.has("leaning"):
		return str(firm.leaning)
	var traits := Traits.of(firm.get("ceo", {}))
	var score := {expansionist = 0, cautious = 0, cutthroat = 0, loyal = 0}
	for id: String in traits:
		match id:
			"gambler", "reckless", "lavish":
				score.expansionist += 2
			"cautious", "thrifty", "bookkeeper":
				score.cautious += 2
			"abrasive", "shrewd":
				score.cutthroat += 2
			"charismatic", "well_connected", "old_salt", "naive":
				score.loyal += 2
			"ex_navy":
				score.loyal += 1
			"engineer", "scholar":
				score.cautious += 1
	var best := "loyal"
	var best_score := -1
	for key: String in ["expansionist", "cautious", "cutthroat", "loyal"]:
		if int(score[key]) > best_score:
			best_score = int(score[key])
			best = key
	if best_score == 0:
		best = ["expansionist", "cautious", "cutthroat", "loyal"][hash(str(firm.get("name", ""))) % 4]
	firm.leaning = best
	return best


static func leaning_name(firm: Dictionary) -> String:
	return str(LEANINGS.get(leaning(firm), "Loyal"))


## A stubborn leadership (STUBBORN_SHARE of firms, cautious and loyal ones more) never sells for less than STUBBORN_PRICE x value.
static func stubborn(firm: Dictionary) -> bool:
	var roll := float(hash(str(firm.get("name", "")) + "stubborn") % 1000) / 1000.0
	var share := STUBBORN_SHARE * (1.5 if leaning(firm) in ["cautious", "loyal"] else 0.6)
	return roll < share


static func is_dead(firm: Dictionary) -> bool:
	return bool(firm.get("dead", false))


# --- Each month -------------------------------------------------------------------------------

func step(_delta: float) -> void:
	var month: int = _state.history.month_now() if _state.history != null else -1
	if month == _month:
		return
	var first := _month < 0
	_month = month
	if first or _state.warm_up_left > 0:
		return
	var firms: ShippingFirms = _state.firms
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var now: int = _state.calendar_time()
	for i in firms.firms.size():
		var firm: Dictionary = firms.firms[i]
		if is_dead(firm):
			continue
		_remember(firm)
		_deliver(firms, i, now)
		if _bankrupt_check(firms, i, rng):
			continue
		_decline(firms, i, rng)
		_grow(firms, i, now, rng)
		if rng.randf() < SUCCESSION_YEARLY / 12.0:
			_succession(firms, i, rng)
	if rng.randf() < MERGER_CHANCE:
		_merger(firms, rng)
	changed.emit()


## The last HISTORY months of cash, for trends.
static func _remember(firm: Dictionary) -> void:
	var history: Array = firm.get_or_add("money_history", [])
	history.append(snappedf(float(firm.money), 1.0))
	while history.size() > HISTORY:
		history.pop_front()


static func _falling(firm: Dictionary, months: int) -> bool:
	var history: Array = firm.get("money_history", [])
	if history.size() < months + 1:
		return false
	return float(history[-1]) < float(history[-1 - months])


## What a firm's fleet is worth at list price, and its favourite model.
static func fleet_value(firm: Dictionary) -> float:
	var total := 0.0
	for model_id: String in firm.fleet:
		total += float(GameData.get_ship_model(model_id).get("price", 0)) * int(firm.fleet[model_id])
	return total


static func favourite_model(firm: Dictionary) -> String:
	var best := ""
	var most := 0
	for model_id: String in firm.fleet:
		if int(firm.fleet[model_id]) > most:
			most = int(firm.fleet[model_id])
			best = model_id
	return best


## With the cash for a few ships (by leaning), a ship is ordered from a yard with a slot: delivered after its months.
func _grow(firms: ShippingFirms, i: int, now: int, rng: RandomNumberGenerator) -> void:
	var firm: Dictionary = firms.firms[i]
	if not (firm.get("order", {}) as Dictionary).is_empty():
		return
	var model_id := favourite_model(firm)
	if model_id.is_empty():
		return
	var model := GameData.get_ship_model(model_id)
	var price := float(model.get("price", 0)) * ShippingFirms.CONVOY
	if float(firm.money) < price * float(ORDER_CASH.get(leaning(firm), 3.0)) or _falling(firm, 3):
		return
	var yards: Shipyards = _state.shipyards
	var offers: Array = yards.yards_for(model).filter(func(o: Dictionary) -> bool: return int(o.free) > 0)
	if offers.is_empty():
		return
	var offer: Dictionary = offers[rng.randi() % mini(offers.size(), 3)]
	firm.money = float(firm.money) - float(offer.price) * ShippingFirms.CONVOY
	firm.order = {model = model_id, due = now + roundi(float(offer.months) * 30.4375 * 86400.0), yard = str(offer.yard)}
	if int(model.get("tier", 1)) >= 4 and _state.news != null:
		_state.news.add("company", "%s orders a %s from %s" % [str(firm.name), str(model.get("name", "")), str(yards.yard(str(offer.yard)).get("name", ""))], {firm = i})


func _deliver(firms: ShippingFirms, i: int, now: int) -> void:
	var firm: Dictionary = firms.firms[i]
	var order: Dictionary = firm.get("order", {})
	if order.is_empty() or now < int(order.due):
		return
	firm.order = {}
	firms.journal_fleet(i, str(order.model), 1)
	if _state.news != null:
		_state.news.add("company", "%s takes delivery of a %s" % [str(firm.name), str(GameData.get_ship_model(str(order.model)).get("name", ""))], {firm = i})


## Cash in the red and falling for LOSS_MONTHS: a ship sold (the most common model, at SELL_BACK of list).
func _decline(firms: ShippingFirms, i: int, _rng: RandomNumberGenerator) -> void:
	var firm: Dictionary = firms.firms[i]
	var value := fleet_value(firm)
	if value <= 0.0 or float(firm.money) > LOSS_SELL * value or not _falling(firm, LOSS_MONTHS):
		return
	var model_id := favourite_model(firm)
	if model_id.is_empty() or int(firm.fleet.get(model_id, 0)) <= 1:
		return
	firms.journal_fleet(i, model_id, -1)
	firm.money = float(firm.money) + float(GameData.get_ship_model(model_id).get("price", 0)) * ShippingFirms.CONVOY * SELL_BACK
	if _state.news != null:
		_state.news.add("company", "%s sells a %s to stay afloat" % [str(firm.name), str(GameData.get_ship_model(model_id).get("name", ""))], {firm = i})


## Cash under BROKE of the fleet's value for BROKE_MONTHS: bankrupt.
func _bankrupt_check(firms: ShippingFirms, i: int, rng: RandomNumberGenerator) -> bool:
	var firm: Dictionary = firms.firms[i]
	var value := fleet_value(firm)
	if value > 0.0 and float(firm.money) < BROKE * value:
		firm.broke_months = int(firm.get("broke_months", 0)) + 1
	else:
		firm.broke_months = 0
	if int(firm.broke_months) < BROKE_MONTHS:
		return false
	_go_bankrupt(firms, i, rng)
	return true


func _go_bankrupt(firms: ShippingFirms, i: int, rng: RandomNumberGenerator) -> void:
	var firm: Dictionary = firms.firms[i]
	var yards: Shipyards = _state.shipyards
	var listed: int = yards.list_fleet(i, BANKRUPT_LISTINGS, 0.5, rng)
	# Stakes in it are worthless; standing with it is moot.
	for company: Company in _state.all_companies():
		if company.stakes.has(str(i)):
			company.stakes.erase(str(i))
			company.firm_plans.erase(str(i))
			if company == _state.company:
				ActivityLog.add("%s is bankrupt: your stake in it is worthless." % str(firm.name), ActivityLog.Kind.BAD)
		(company.relations.get("firms", {}) as Dictionary).erase(str(i))
	firms.journal_dead(i, -1)
	if _state.news != null:
		_state.news.add("company", "%s goes bankrupt; its ships go under the hammer" % str(firm.name), {firm = i})
	bankrupt.emit(i, listed)
	_found(firms, rng, str(firm.country))


## A new firm, small, in a country (or any), to keep the world's count.
func _found(firms: ShippingFirms, rng: RandomNumberGenerator, country := "") -> void:
	var live := firms.firms.filter(func(f: Dictionary) -> bool: return not is_dead(f)).size()
	if live >= ShippingFirms.FIRMS:
		return
	var index: int = firms.journal_found(country, rng)
	if index >= 0 and _state.news != null:
		_state.news.add("company", "%s founded in %s" % [str(firms.firms[index].name), GameData.port_name(str(firms.firms[index].home))], {firm = index})


## A rich firm buys a struggling smaller one of its country or line; the stubborn refuse; stakes by card.
func _merger(firms: ShippingFirms, rng: RandomNumberGenerator) -> void:
	var live: Array = range(firms.firms.size()).filter(func(k: int) -> bool: return not is_dead(firms.firms[k]))
	if live.size() < 2:
		return
	var buyers: Array = live.filter(func(k: int) -> bool: return float(firms.firms[k].money) > 0.3 * fleet_value(firms.firms[k]) and fleet_value(firms.firms[k]) > 0.0)
	if buyers.is_empty():
		return
	var b: int = buyers[rng.randi() % buyers.size()]
	var buyer: Dictionary = firms.firms[b]
	var targets: Array = live.filter(func(k: int) -> bool:
		var f: Dictionary = firms.firms[k]
		return k != b and fleet_value(f) < fleet_value(buyer) * 0.6 and fleet_value(f) > 0.0 and _falling(f, 3) and (f.country == buyer.country or _shares_line(f, buyer)))
	if targets.is_empty():
		return
	var t: int = targets[rng.randi() % targets.size()]
	var target: Dictionary = firms.firms[t]
	var value: float = maxf(_state.ownership.firm_value(t), fleet_value(target))  # (Never under the ships' worth: a small firm gets a rich price, not a fire sale.)
	if stubborn(target):
		if _state.news != null:
			_state.news.add("company", "%s rebuffs %s: not for sale at any sane price" % [str(target.name), str(buyer.name)], {firm = t})
		return
	var premium := SMALL_PREMIUM if fleet_value(target) < fleet_value(buyer) * 0.25 else BIG_PREMIUM
	var price := value * premium
	if float(buyer.money) < price * 0.5:
		return
	buyer.money = float(buyer.money) - price
	target.money = 0.0
	for company: Company in _state.all_companies():
		var stake: float = _state.ownership.stake_in(company, t)
		if stake > 0.0:
			if company == _state.company:
				merger_stake.emit(company, b, t, price, stake)
			else:
				_state.ownership.convert_stake(company, t, b, price)
	for model_id: String in target.fleet.keys():
		var n := int(target.fleet[model_id])
		firms.journal_fleet(t, model_id, -n)
		firms.journal_fleet(b, model_id, n)
	firms.journal_dead(t, b)
	if _state.news != null:
		_state.news.add("company", "%s buys %s for %s" % [str(buyer.name), str(target.name), Fmt.money(roundi(price))], {firm = b})


static func _shares_line(a: Dictionary, b: Dictionary) -> bool:
	for model_id: String in a.fleet:
		var line := str(GameData.get_ship_model(model_id).get("category", ""))
		for other: String in b.fleet:
			if str(GameData.get_ship_model(other).get("category", "")) == line:
				return true
	return false


## A new CEO (the old one retired): new traits, a new leaning.
func _succession(firms: ShippingFirms, i: int, rng: RandomNumberGenerator) -> void:
	var firm: Dictionary = firms.firms[i]
	var old := str((firm.get("ceo", {}) as Dictionary).get("name", ""))
	firms.journal_ceo(i, ShippingFirms._ceo(rng))
	if _state.news != null:
		_state.news.add("company", "%s names %s chief executive after %s; the new chief is %s" % [str(firm.name), str(firm.ceo.name), old, leaning_name(firm).to_lower()], {firm = i})

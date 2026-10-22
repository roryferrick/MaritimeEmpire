# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Shipyards
extends RefCounted
## The shipyard companies and the second-hand market (data/shipyards.json;
## DESIGN_LIVING_WORLD.md M4). Ships of tier ORDER_TIER and up are ordered
## (place_order()): a yard that builds the category and size, with a slot, at
## its price and months (yards_for()); a deposit now, the rest on delivery at
## the yard's port (step()), the order on Company.orders. Tier-1 boats and
## tugs are bought outright as before (GameState.buy_ship()). The used market
## (listings) lists ships the paper firms are selling, refreshed each month:
## age, hours, a condition per part, a price by condition and age, lying at
## the firm's home port, where they're delivered (buy_used()).

signal changed
## An order was delivered: the ship, at the yard's port.
signal delivered(company: Company, ship: Ship, order: Dictionary)

const PATH := "res://data/shipyards.json"
const ORDER_TIER := 2
const USED_AGE := [3.0, 20.0]
const USED_CONDITION := [0.35, 0.95]
const LATE_CHANCE := 0.3  # A cheap yard's chance of running a month late (times 1 - quality).

var _state: Node  # GameState
var _data := {}
var _by_id := {}
## The ships for sale: [{id, model, firm, port, name, age, sea_time, parts, maintenance, price}].
var listings: Array = []
var _next_id := 1
var _month := -1


func _init(state: Node) -> void:
	_state = state


func data() -> Dictionary:
	if _data.is_empty():
		var file := FileAccess.open(PATH, FileAccess.READ)
		_data = JSON.parse_string(file.get_as_text()) if file != null else {yards = []}
		for yard: Dictionary in _data.get("yards", []):
			_by_id[yard.id] = yard
	return _data


func yards() -> Array:
	return data().get("yards", [])


func yard(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


func reset() -> void:
	listings = []
	_next_id = 1
	_month = -1


## Whether a model is ordered from a yard rather than bought outright.
static func is_ordered(model: Dictionary) -> bool:
	return int(model.get("tier", 1)) >= ORDER_TIER and not bool(model.get("tug", false))


func deposit_share() -> float:
	return float(data().get("deposit", 0.2))


## What a yard charges for a model and how long it takes: [price, months].
func quote(yard_info: Dictionary, model: Dictionary) -> Array:
	var months_by_tier: Array = data().get("months_by_tier", [0, 2, 4, 8, 14])
	var tier := clampi(int(model.get("tier", 1)), 1, months_by_tier.size())
	var price := roundi(float(model.get("price", 0)) * float(yard_info.get("price", 1.0)))
	var months := maxf(float(months_by_tier[tier - 1]) * float(yard_info.get("speed", 1.0)), 1.0)
	return [price, months]


## How many of a yard's slots are taken by every company's open orders.
func slots_taken(yard_id: String) -> int:
	var count := 0
	for company: Company in _state.all_companies():
		for order: Dictionary in company.orders:
			if str(order.yard) == yard_id:
				count += 1
	return count


## The yards that would build a model, cheapest first: [{yard (id), name, port, price, months, quality, free}].
func yards_for(model: Dictionary) -> Array:
	var out := []
	var category := str(model.get("category", ""))
	for info: Dictionary in yards():
		var builds: Array = info.get("builds", [])
		if not builds.is_empty() and not category in builds:
			continue
		if int(model.get("tier", 1)) > int(info.get("max_tier", 5)):
			continue
		var q := quote(info, model)
		out.append({yard = str(info.id), name = str(info.name), port = str(info.port), price = int(q[0]), months = float(q[1]), quality = float(info.get("quality", 0.8)), free = int(info.get("slots", 2)) - slots_taken(str(info.id))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.price) < int(b.price))
	return out


static func quality_word(quality: float) -> String:
	return "renowned" if quality >= 0.9 else ("sound" if quality >= 0.75 else ("workmanlike" if quality >= 0.65 else "cheap and cheerful"))


## Why a company can't order a model from a yard, or "".
func order_error(company: Company, model_id: String, yard_id: String) -> String:
	var model := GameData.get_ship_model(model_id)
	if model.is_empty() or not is_ordered(model):
		return "Bought outright, not ordered"
	if not Progression.can_buy_model(model, company):
		return _state.locked_type_note(Progression.type_of_model(model))
	var info := yard(yard_id)
	if info.is_empty():
		return "Pick a yard"
	var offers := yards_for(model).filter(func(o: Dictionary) -> bool: return str(o.yard) == yard_id)
	if offers.is_empty():
		return "%s doesn't build a %s" % [str(info.name), str(model.get("name", ""))]
	if int(offers[0].free) <= 0:
		return "%s has no slot free" % str(info.name)
	var deposit := roundi(int(offers[0].price) * deposit_share())
	if company.money < deposit or _state.in_debt(company):
		return "The deposit is %s" % Fmt.money(deposit)
	return ""


## Places an order: the deposit now, the rest on delivery (step()).
func place_order(company: Company, model_id: String, ship_name: String, yard_id: String) -> String:
	var error := order_error(company, model_id, yard_id)
	if not error.is_empty():
		return error
	var model := GameData.get_ship_model(model_id)
	var info := yard(yard_id)
	var q := quote(info, model)
	var price := int(q[0])
	var deposit := roundi(price * deposit_share())
	var now: int = _state.calendar_time()
	var order := {id = _next_id, model = model_id, name = ship_name, yard = yard_id, port = str(info.port), placed = now, due = now + roundi(float(q[1]) * 30.4375 * 86400.0), price = price, deposit = deposit, late = false}
	_next_id += 1
	company.orders.append(order)
	_state._add_money(company, -deposit)
	_state._record(null, "bought", deposit, company)
	if company == _state.company:
		ActivityLog.add("Ordered %s, a %s, from %s: %s down, %s on delivery at %s about %s." % [ship_name, str(model.get("name", "")), str(info.name), Fmt.money(deposit), Fmt.money(price - deposit), GameData.port_name(str(info.port)), Fmt.calendar_short(int(order.due))], ActivityLog.Kind.INFO)
	if _state.news != null and int(model.get("tier", 1)) >= 4:
		_state.news.add("company", "%s orders a %s from %s" % [company.name, str(model.get("name", "")), str(info.name)], {})
	changed.emit()
	return ""


## Cancels an order: cancel_refund of the deposit back.
func cancel_order(company: Company, order_id: int) -> void:
	for order: Dictionary in company.orders:
		if int(order.id) == order_id:
			company.orders.erase(order)
			var refund := roundi(int(order.deposit) * float(data().get("cancel_refund", 0.5)))
			_state._add_money(company, refund)
			_state._record(null, "bought", -refund, company)
			if company == _state.company:
				ActivityLog.add("Cancelled the order for %s; %s of the deposit back." % [str(order.name), Fmt.money(refund)], ActivityLog.Kind.INFO)
			changed.emit()
			return


func step(_delta: float) -> void:
	var now: int = _state.calendar_time()
	for company: Company in _state.all_companies():
		for order: Dictionary in company.orders.duplicate():
			if now >= int(order.due):
				_deliver(company, order)
	var month: int = _state.history.month_now() if _state.history != null else -1
	if month != _month or listings.is_empty():
		var first := _month < 0 or listings.is_empty()
		_month = month
		_refresh_listings(first)


## The rest of the price is paid and the ship launched at the yard's port; a cheap yard may run a month late first.
func _deliver(company: Company, order: Dictionary) -> void:
	var info := yard(str(order.yard))
	var quality := float(info.get("quality", 0.8))
	if not bool(order.get("late", false)) and randf() < LATE_CHANCE * (1.0 - quality):
		order.late = true
		order.due = int(order.due) + 30 * 86400
		if company == _state.company:
			ActivityLog.add("%s is running a month late with %s." % [str(info.name), str(order.name)], ActivityLog.Kind.BAD)
		return
	var rest := int(order.price) - int(order.deposit)
	if company.money < rest:
		if not bool(order.get("waiting", false)):
			order.waiting = true
			if company == _state.company:
				ActivityLog.add("%s is ready at %s: %s to pay before it's handed over." % [str(order.name), GameData.port_name(str(order.port)), Fmt.money(rest)], ActivityLog.Kind.BAD)
		return
	_state._add_money(company, -rest)
	_state._record(null, "bought", rest, company)
	company.orders.erase(order)
	var ship: Ship = _state.launch_ship(company, str(order.model), str(order.name), str(order.port), int(order.price))
	if ship == null:
		return
	ship.parts = ShipParts.new_conditions(ship.model(), lerpf(0.9, 1.0, clampf(quality, 0.0, 1.0)))
	ship.sync_maintenance(ShipParts.mean(ship))
	if company == _state.company:
		ActivityLog.add("%s delivered at %s by %s." % [ship.name, GameData.port_name(str(order.port)), str(info.name)], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))
	if _state.news != null and int(ship.model().get("tier", 1)) >= 4:
		_state.news.add("company", "%s takes delivery of %s, a %s" % [company.name, ship.name, str(ship.model().get("name", ""))], {})
	delivered.emit(company, ship, order)
	changed.emit()


# --- The second-hand market -------------------------------------------------------------------

## A third of the listings replaced each month (all of them at first).
func _refresh_listings(fill_all: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var want := int(data().get("used_listings", 12))
	if fill_all:
		listings = []
	else:
		var drop := mini(listings.size(), maxi(want / 3, 1))
		listings = listings.slice(drop)
	var firms: ShippingFirms = _state.firms
	var tries := 0
	while listings.size() < want and tries < 200:
		tries += 1
		var firm: Dictionary = firms.firms[rng.randi() % firms.firms.size()]
		var models: Array = (firm.fleet as Dictionary).keys().filter(func(id: String) -> bool: return is_ordered(GameData.get_ship_model(id)))
		if models.is_empty():
			continue
		var model_id: String = models[rng.randi() % models.size()]
		var model := GameData.get_ship_model(model_id)
		var age := rng.randf_range(float(USED_AGE[0]), float(USED_AGE[1]))
		var parts := {}
		var total := 0.0
		var sum := 0.0
		for each: Dictionary in ShipParts.for_model(model):
			var c := clampf(rng.randf_range(float(USED_CONDITION[0]), float(USED_CONDITION[1])) - age * 0.01, 0.1, 1.0)
			parts[each.id] = c
			total += float(each.weight)
			sum += float(each.weight) * c
		var mean := sum / total if total > 0.0 else 0.7
		var span: Array = data().get("used_price", [0.4, 0.8])
		var price := roundi(float(model.get("price", 0)) * lerpf(float(span[0]), float(span[1]), mean) * (1.0 - age / 40.0))
		listings.append({id = _next_id, model = model_id, firm = int(firm.id), port = str(firm.home), name = _state.suggest_ship_name(), age = snappedf(age, 0.1), sea_time = age * 1800.0, parts = parts, maintenance = snappedf(mean, 0.001), price = price})
		_next_id += 1
	changed.emit()


func listing(id: int) -> Dictionary:
	for each: Dictionary in listings:
		if int(each.id) == id:
			return each
	return {}


func used_error(company: Company, listing_id: int) -> String:
	var each := listing(listing_id)
	if each.is_empty():
		return "Sold"
	var model := GameData.get_ship_model(str(each.model))
	if not Progression.can_buy_model(model, company):
		return _state.locked_type_note(Progression.type_of_model(model))
	if company.money < int(each.price) or _state.in_debt(company):
		return "Costs %s" % Fmt.money(int(each.price))
	return ""


## Buys a listed ship: delivered where it lies, with its parts as they are.
func buy_used(company: Company, listing_id: int, ship_name: String) -> String:
	var error := used_error(company, listing_id)
	if not error.is_empty():
		return error
	var each := listing(listing_id)
	listings.erase(each)
	_state._add_money(company, -int(each.price))
	_state._record(null, "bought", int(each.price), company)
	var ship: Ship = _state.launch_ship(company, str(each.model), ship_name, str(each.port), int(each.price))
	if ship == null:
		return "Couldn't launch it"
	ship.parts = (each.parts as Dictionary).duplicate()
	ship.sync_maintenance(float(each.maintenance))
	ship.sea_time = float(each.sea_time)
	ship.invalidate_stats()
	var firms: ShippingFirms = _state.firms
	var firm: Dictionary = firms.firms[int(each.firm)]
	firm.money = float(firm.money) + float(each.price)
	if company == _state.company:
		ActivityLog.add("Bought %s second-hand from %s for %s; it's at %s, %d years old and %d%% sound." % [ship.name, str(firm.name), Fmt.money(int(each.price)), GameData.port_name(str(each.port)), roundi(float(each.age)), roundi(float(each.maintenance) * 100.0)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))
	changed.emit()
	return ""


func to_dict() -> Dictionary:
	return {listings = listings, next_id = _next_id, month = _month}


func from_dict(data_in: Dictionary) -> void:
	listings = data_in.get("listings", []) if data_in.get("listings") is Array else []
	_next_id = int(data_in.get("next_id", 1))
	_month = int(data_in.get("month", -1))
	changed.emit()

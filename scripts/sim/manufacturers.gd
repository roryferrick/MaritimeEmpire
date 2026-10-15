# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Manufacturers
extends RefCounted
## Vehicle and boat makers (data/manufacturers.json), for Vehicles companies:
## each maker's vehicles are their own market good (GameData adds them to the
## markets, cheapest at its factories); each company's likeness with each maker
## (Company.maker_likes), which trading its goods raises and carrying a
## rival's, or losing its goods at sea, lowers; the perks it brings; and the
## factories a company builds for a maker it's well liked by (Company.factories),
## which make the maker's vehicles into a stockpile there a day at a time, to
## sell there or load free (the maker takes its cut of what they sell for).
## GameState owns one (its makers) and calls it from its trading and its steps;
## its actions are GameState's (with their Net commands), which call these for
## a company.

const PATH := "res://data/manufacturers.json"
const DAY_S := 86400.0
## The likeness marks that bring a perk, in order (see perk_marks()).
const PERKS := ["cheaper_at", "first_pick_at", "factory_at", "second_factory_at"]

static var _data := {}
static var _makers := {}
static var _rivals := {}

var _state: Node


func _init(state: Node) -> void:
	_state = state


# --- The data ---------------------------------------------------------------------

static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {}
		for each: Dictionary in _data.get("makers", []):
			_makers[each.id] = each
	return _data


static func setting(key: String, default: Variant = 0.0) -> Variant:
	return data().get("settings", {}).get(key, default)


## Every maker, in the data's order (the car makers, then the boat makers).
static func makers() -> Array:
	return data().get("makers", [])


## A line's makers: "cars" (cars and trucks, on the car carriers) or "boats".
static func makers_of(line: String) -> Array:
	return makers().filter(func(each: Dictionary) -> bool: return each.line == line)


static func maker(id: String) -> Dictionary:
	data()
	return _makers.get(id, {})


static func is_maker(id: String) -> bool:
	data()
	return _makers.has(id)


## The maker's own factory ports.
static func factory_ports(id: String) -> Array:
	return maker(id).get("factories", [])


## The market region it's based in (its first factory's).
static func home_region(id: String) -> String:
	var ports: Array = factory_ports(id)
	return str(GameData.port_region(ports[0]).get("id", "")) if not ports.is_empty() else ""


static func class_name_of(class_id: String) -> String:
	for each: Dictionary in data().get("classes", []):
		if each.id == class_id:
			return str(each.name)
	return class_id.capitalize()


## "Luxury supercars" or "Budget dinghies and small fibreglass boats".
static func describe(id: String) -> String:
	var each := maker(id)
	return "%s %s" % [class_name_of(str(each.get("class", ""))), str(each.get("what", ""))]


## Its direct competitors: makers of the same kind (cars, trucks or boats) and class.
static func rivals_of(id: String) -> Array[String]:
	if not _rivals.has(id):
		var out: Array[String] = []
		var each := maker(id)
		for other: Dictionary in makers():
			if other.id != id and other.kind == each.get("kind") and other["class"] == each.get("class"):
				out.append(str(other.id))
		_rivals[id] = out
	return _rivals[id]


## A maker's good's base price: value_per_slot x its class's value x its hold.
static func base_price(each: Dictionary) -> float:
	return float(setting("value_per_slot", {}).get(each.line, 5000)) * float(setting("class_value", {}).get(each["class"], 1.0)) * float(each.get("hold", 1.0))


## What a maker's goods sell for in a market region (x base): its home
## region's home_price, elsewhere what its class sells for there (demand
## [poorest, richest] by the region's wealth).
static func region_price(each: Dictionary, region_id: String) -> float:
	if region_id == home_region(str(each.id)):
		return float(setting("home_price", 0.75))
	var demand: Array = setting("demand", {}).get(each["class"], [1.5, 1.5])
	var wealth := float(setting("wealth", {}).get(region_id, 0.5))
	return lerpf(float(demand[0]), float(demand[1]), wealth)


## The commodities GameData adds to the markets for the makers, and their
## prices: [commodity, {region id: multiplier}, {port: multiplier}] each.
static func market_goods() -> Array:
	var out := []
	for each: Dictionary in makers():
		var boat: bool = each.line == "boats"
		var goods := {id = each.id, name = each.name, unit = "boat" if boat else "vehicle", units = "boats" if boat else "vehicles",
			base = base_price(each), hold = float(each.get("hold", 1.0)), maker = true, family = each.kind}
		var regions := {}
		for region: Dictionary in GameData.markets.get("regions", []):
			regions[region.id] = region_price(each, str(region.id))
		var sources := {}
		for port_id: String in each.get("factories", []):
			sources[port_id] = float(setting("factory_price", 0.5))
		out.append([goods, regions, sources])
	return out


# --- Likeness ---------------------------------------------------------------------

## A company's likeness with a maker (0-100; the start if it's never traded).
static func likeness(who: Company, id: String) -> float:
	if who == null:
		return float(setting("start", 20))
	return float(who.maker_likes.get(id, setting("start", 20)))


## The likeness marks [mark, what it brings], in order.
static func perk_marks() -> Array:
	return [[int(setting("cheaper_at", 40)), "%d%% off at their factories" % roundi(float(setting("buy_discount", 0.1)) * 100.0)],
		[int(setting("first_pick_at", 55)), "first pick: buying at their factories doesn't push their price up"],
		[int(setting("factory_at", 70)), "build a factory for them"],
		[int(setting("second_factory_at", 90)), "build a second factory"]]


## Changes a company's likeness with a maker, telling this player of a perk won or lost.
func change(who: Company, id: String, amount: float) -> void:
	if who == null or not is_maker(id) or amount == 0.0:
		return
	var before := likeness(who, id)
	var after := clampf(before + amount, 0.0, 100.0)
	who.maker_likes[id] = after
	if who != _state.company or _state.ai_acting != null:
		return
	for mark: Array in perk_marks():
		if before < float(mark[0]) and after >= float(mark[0]):
			ActivityLog.add("%s likes you %d/100 now: %s." % [maker(id).name, int(mark[0]), mark[1]], ActivityLog.Kind.GOOD)
		elif before >= float(mark[0]) and after < float(mark[0]):
			ActivityLog.add("%s's likeness fell below %d: no more %s." % [maker(id).name, int(mark[0]), mark[1]], ActivityLog.Kind.BAD)


## A company traded a maker's goods worth `value` at a port (bought, or sold):
## its likeness with the maker rises (less as it gets high), and with the
## maker's rivals falls by rival_penalty of that.
func on_trade(who: Company, commodity_id: String, value: float, buying: bool) -> void:
	if who == null or value <= 0.0 or not is_maker(commodity_id):
		return
	var now := likeness(who, commodity_id)
	var taper := clampf((float(setting("taper_from", 120)) - now) / 100.0, float(setting("taper_floor", 0.2)), 1.0)
	var gain := float(setting("gain", 0.3)) * sqrt(value / float(setting("gain_ref_value", 1000000))) * (float(setting("buy_share", 0.4)) if buying else 1.0)
	change(who, commodity_id, gain * taper)
	var penalty := gain * float(setting("rival_penalty", 0.15))
	for other in rivals_of(commodity_id):
		change(who, other, -penalty)


## A ship broke down (or was lost) with a maker's goods aboard: its company's
## likeness with the maker falls.
func on_mishap(ship: Ship, lost: bool) -> void:
	if ship == null or ship.cargo_qty <= 0 or not is_maker(ship.cargo_id):
		return
	var who: Company = _state.owner_of(ship)
	change(who, ship.cargo_id, -float(setting("lost_penalty" if lost else "breakdown_penalty", 2)))
	if who == _state.company and _state.ai_acting == null:
		ActivityLog.add("%s isn't pleased: %s %s with its %s aboard." % [maker(ship.cargo_id).name, ship.name, "was lost" if lost else "broke down",
			GameData.commodity(ship.cargo_id).get("units", "vehicles")], ActivityLog.Kind.BAD)


# --- Perks ------------------------------------------------------------------------

## True if a port is one of a maker's own factories.
static func is_factory_port(id: String, port_id: String) -> bool:
	return factory_ports(id).has(port_id)


## What a company pays for a maker's goods at a port, x the market's: its
## buy_discount off at the maker's own factories once it likes it cheaper_at.
static func buy_factor(who: Company, port_id: String, commodity_id: String) -> float:
	if not is_maker(commodity_id) or not is_factory_port(commodity_id, port_id) or likeness(who, commodity_id) < float(setting("cheaper_at", 40)):
		return 1.0
	return 1.0 - float(setting("buy_discount", 0.1))


## True if a company's buying of a maker's goods at a port leaves the price
## alone: at the maker's own factories, once it likes it first_pick_at.
static func first_pick(who: Company, port_id: String, commodity_id: String) -> bool:
	return is_maker(commodity_id) and is_factory_port(commodity_id, port_id) and likeness(who, commodity_id) >= float(setting("first_pick_at", 55))


# --- Factories --------------------------------------------------------------------

## True if a company can deal with makers: a Vehicles company (or one from before types).
static func can_deal(who: Company) -> bool:
	return who != null and who.has_type("vehicles")


## How many factories a company may have for a maker now (0, 1 or 2).
static func factories_allowed(who: Company, id: String) -> int:
	var like := likeness(who, id)
	if like >= float(setting("second_factory_at", 90)):
		return 2
	return 1 if like >= float(setting("factory_at", 70)) else 0


## A company's factories for a maker ("" for all of them).
static func factories_of(who: Company, id := "") -> Array:
	if who == null:
		return []
	return who.factories.filter(func(each: Dictionary) -> bool: return id.is_empty() or each.maker == id)


## Every company's factories at a port: [[company, factory], ...].
func factories_at(port_id: String) -> Array:
	var out := []
	for who: Company in _state.all_companies():
		for each: Dictionary in who.factories:
			if each.port == port_id:
				out.append([who, each])
	return out


## The makers with a factory at a port, theirs or a company's.
func makers_at(port_id: String) -> Array[String]:
	var out: Array[String] = []
	for each: Dictionary in makers():
		if is_factory_port(each.id, port_id):
			out.append(str(each.id))
	for pair: Array in factories_at(port_id):
		if not out.has(str(pair[1].maker)):
			out.append(str(pair[1].maker))
	return out


## What a factory for a maker costs to build.
static func factory_cost(id: String) -> int:
	return int(setting("factory_cost", {}).get(maker(id).get("class", "mainstream"), 50000000))


## Its upkeep a calendar month.
static func upkeep_a_month(id: String) -> int:
	return roundi(factory_cost(id) * float(setting("upkeep_a_month", 0.01)))


## The units a factory makes a calendar day (output_slots_a_month of deck slots a month).
static func output_a_day(id: String) -> float:
	return float(setting("output_slots_a_month", 2000)) / maxf(float(maker(id).get("hold", 1.0)), 0.1) / (365.25 / 12.0)


## The most a factory's stockpile holds (stock_months of its output).
static func stock_cap(id: String) -> float:
	return output_a_day(id) * 365.25 / 12.0 * float(setting("stock_months", 3))


## The share of its factory goods' sales the maker takes: cut_high at
## factory_at likeness, falling to cut_low at 100 (cut_high below).
static func cut(who: Company, id: String) -> float:
	var low := float(setting("factory_at", 70))
	var share := clampf((likeness(who, id) - low) / maxf(100.0 - low, 1.0), 0.0, 1.0)
	return lerpf(float(setting("cut_high", 0.3)), float(setting("cut_low", 0.1)), share)


## Why a company can't build a factory for a maker at a port ("" if it can).
func build_error(who: Company, id: String, port_id: String) -> String:
	if not can_deal(who):
		return "Only Vehicles companies build for makers"
	var each := maker(id)
	if each.is_empty() or GameData.get_port(port_id).is_empty():
		return "No such maker or port"
	if factories_allowed(who, id) == 0:
		return "%s must like you %d/100 first (now %d)" % [each.name, int(setting("factory_at", 70)), floori(likeness(who, id))]
	if factories_of(who, id).size() >= factories_allowed(who, id):
		return "%s lets you build a second at %d/100" % [each.name, int(setting("second_factory_at", 90))] if factories_allowed(who, id) < 2 else "You have both your %s factories" % each.name
	if is_factory_port(id, port_id):
		return "%s already builds at %s" % [each.name, GameData.port_name(port_id)]
	for pair: Array in factories_at(port_id):
		if pair[1].maker == id:
			return "%s has a %s factory here already" % [(pair[0] as Company).name, each.name]
	if not who.regions.is_empty() and not who.regions.has(str(GameData.port_region(port_id).get("id", ""))):
		return "Unlock %s first" % GameData.port_region(port_id).get("name", "its region")
	if _state.in_debt(who) or who.money < factory_cost(id):
		return "Not enough money"
	return ""


func build(who: Company, id: String, port_id: String) -> void:
	if not build_error(who, id, port_id).is_empty():
		return
	var cost := factory_cost(id)
	_state._add_money(who, -cost)
	_state._record(null, "factories", cost, who)
	who.factories.append({maker = id, port = port_id, stock = 0.0, paid = cost, day = _today(), made = 0.0})
	_state.makers_changed.emit()


## Closes a company's factory: the maker buys it back for close_share of what was paid.
func close(who: Company, id: String, port_id: String) -> int:
	for each: Dictionary in factories_of(who, id):
		if each.port == port_id:
			var refund := roundi(float(each.get("paid", 0)) * float(setting("close_share", 0.25)))
			who.factories.erase(each)
			_state._add_money(who, refund)
			_state._record(null, "factories", -refund, who)
			_state.makers_changed.emit()
			return refund
	return 0


## A company's factory for a maker at a port, or {}.
static func factory(who: Company, id: String, port_id: String) -> Dictionary:
	for each: Dictionary in factories_of(who, id):
		if each.port == port_id:
			return each
	return {}


## What a company's stockpile at a factory would fetch sold there now (less the maker's cut).
func stock_value(who: Company, each: Dictionary) -> int:
	var units := floori(float(each.get("stock", 0.0)))
	return roundi(units * _state.company_sell_price(str(each.port), str(each.maker), who) * (1.0 - cut(who, str(each.maker))))


## Sells a factory's stockpile at its port. Returns the money (after the maker's cut).
func sell_stock(who: Company, id: String, port_id: String) -> int:
	var each := factory(who, id, port_id)
	var units := floori(float(each.get("stock", 0.0)))
	if units <= 0:
		return 0
	var gross := units * float(_state.company_sell_price(port_id, id, who))
	var value := roundi(gross * (1.0 - cut(who, id)))
	each.stock = float(each.stock) - units
	_state._add_money(who, value)
	_state._record(null, "factory_sales", value, who)
	_state._tally_port_trade(who, port_id, id, units, value, true)
	_state.market.trade(port_id, id, gross, false)
	on_trade(who, id, gross, false)
	_state.makers_changed.emit()
	return value


# --- The days ---------------------------------------------------------------------

func _today() -> int:
	return floori((_state.calendar_time() - _state.calendar_time_at(0.0)) / DAY_S)


## Runs each company's factories up to today, a few days a step at most when
## fast-forwarding (the rest the next steps): each day makes a day's output
## into the stockpile (up to its cap) and pays a day's upkeep.
func step(_delta: float) -> void:
	var now := _today()
	var changed := false
	for who: Company in _state.all_companies():
		for each: Dictionary in who.factories:
			var ran := 0
			while int(each.get("day", now)) < now and ran < 4:
				each.day = int(each.get("day", now)) + 1
				ran += 1
				_run_day(who, each)
			changed = changed or ran > 0
	if changed:
		_state.makers_changed.emit()


func _run_day(who: Company, each: Dictionary) -> void:
	var id := str(each.maker)
	var made := minf(output_a_day(id), maxf(stock_cap(id) - float(each.get("stock", 0.0)), 0.0))
	each.stock = float(each.get("stock", 0.0)) + made
	each.made = float(each.get("made", 0.0)) + made
	var upkeep := upkeep_a_month(id) / (365.25 / 12.0)
	_state._add_money(who, -roundi(upkeep))
	_state._record(null, "factories", roundi(upkeep), who)


# --- The ships --------------------------------------------------------------------

## A ship loading at a port where its company has a factory for a maker whose
## goods it carries: it takes the stockpile that pays most where it's going,
## free, up to its room (the maker's cut is taken when it's sold: see
## Ship.cargo_cut). Sets the ship's cargo and returns [commodity, units], or [] for none.
func load_ship(ship: Ship, to: String) -> Array:
	var who: Company = _state.owner_of(ship)
	var carries: Array = ship.model().get("cargo", [])
	var best := {}
	var best_gain := 0.0
	for each: Dictionary in who.factories:
		if each.port != ship.docked_at or not carries.has(each.maker) or float(each.get("stock", 0.0)) < 1.0:
			continue
		var hold := GameData.hold_of(str(each.maker))
		if hold > ship.capacity():
			continue
		var gain := minf(float(each.stock), ship.capacity() / hold) * float(_state.company_sell_price(to, str(each.maker), who)) * (1.0 - cut(who, str(each.maker)))
		if gain > best_gain:
			best_gain = gain
			best = each
	if best.is_empty():
		return []
	var id := str(best.maker)
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())) / GameData.hold_of(id))
	var quantity := mini(room, floori(float(best.stock)))
	if quantity <= 0:
		return []
	best.stock = float(best.stock) - quantity
	ship.cargo_id = id
	ship.cargo_from = ship.docked_at
	ship.cargo_qty = quantity
	ship.cargo_cost = 0  # (Free: the maker's cut is paid when it's sold.)
	ship.cargo_cut = cut(who, id)
	_state.cargo_loaded.emit(ship, ship.docked_at, id, quantity, 0, to)
	_state.ship_changed.emit(ship)
	_state.makers_changed.emit()
	return [id, quantity]


## Old saves' cars and trucks aboard (from before the makers) become a
## mainstream maker's of the same kind from the region they were loaded in (or
## the nearest such maker's), so far as they fit; their boats stay plain
## Boats, sold at the next port.
static func convert_old_cargo(ship: Ship) -> void:
	if not ship.cargo_id in ["cars", "trucks"] or ship.model().get("category", "") != "vehicles":
		return
	var region := str(GameData.port_region(ship.cargo_from).get("id", ""))
	var best := ""
	for each: Dictionary in makers():
		if each.kind != ship.cargo_id or each["class"] != "mainstream":
			continue
		if best.is_empty() or home_region(str(each.id)) == region:
			best = str(each.id)
			if home_region(best) == region:
				break
	if best.is_empty():
		return
	ship.cargo_id = best
	ship.cargo_qty = maxi(floori(ship.cargo_qty / GameData.hold_of(best)), 1)


# --- AI rivals ---------------------------------------------------------------------

## A rival building simply (RivalAI, now and then): a factory for the maker
## it's best liked by that allows one more, at the first of its HQ and hubs
## where it can, if it has the money to spare. Returns news.
func run_rival(rival: Company, spare: int) -> Array:
	var news := []
	if not can_deal(rival):
		return news
	var ids := makers().map(func(each: Dictionary) -> String: return str(each.id))
	ids.sort_custom(func(a: String, b: String) -> bool: return likeness(rival, a) > likeness(rival, b))
	for id: String in ids:
		if factories_allowed(rival, id) <= factories_of(rival, id).size():
			if factories_allowed(rival, id) == 0:
				break  # (Sorted: none after likes it enough.)
			continue
		if factory_cost(id) * 2 > spare:
			continue
		for hub: Hub in rival.hubs:
			if build_error(rival, id, hub.port_id).is_empty():
				build(rival, id, hub.port_id)
				news.append("built a %s factory at %s" % [maker(id).name, GameData.port_name(hub.port_id)])
				return news
	return news


## A rival's factories' stockpiles that have filled are sold where they are
## (its ships pass by now and then and load the rest).
func sell_rival_stock(rival: Company) -> void:
	for each: Dictionary in rival.factories.duplicate():
		if float(each.get("stock", 0.0)) >= stock_cap(str(each.maker)) * 0.95:
			sell_stock(rival, str(each.maker), str(each.port))

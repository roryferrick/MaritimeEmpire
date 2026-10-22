# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Contracts
extends RefCounted
## Contracts, the main way to earn (DESIGN_LIVING_WORLD.md M2). The world's
## producers (Producers) offer the player's company shipping work where the
## economy calls for it: a good their plants make in a zone long of it, bound
## for a zone short of it. Offers (offers): one-off voyages ("voyage": carry
## units from here to there by a date) and recurring volume ("recurring":
## units a quarter for N quarters at a rate fixed at signing); tenders come
## next. What a producer offers follows its opinion of the company (opinion():
## its country's standing plus its own memory, -100..100, in tiers: Unknown,
## Known, Trusted, Renowned), and how many are open scales with the best tier
## the company holds. Pay is a freight rate per unit (handling + distance, x
## a premium of PREMIUM_LOW to PREMIUM_HIGH by how short the destination is),
## paid on delivery; the cargo is the producer's, loaded free. Ships are
## assigned to a contract (assign_ship()): the game routes them from the load
## port to the delivery port and back and they load the contract's cargo
## first, spare hold for spot cargo. A quarter short costs a fee of the
## shortfall and standing; a contract done lifts standing with the producer and
## its country. Offers are remade every OFFER_DAYS; an offer worth
## IMPORTANT_SHARE of the company's value (over IMPORTANT_LEAST) pauses the
## game with a card (GameState.offer_arrived). Saved with the game.

signal offers_changed
signal contracts_changed
## An important offer for the player's company (the event card).
signal offer_arrived(offer: Dictionary)
## A tender closed that the player's company bid on: won or lost, and to whom at what rate.
signal tender_closed(offer: Dictionary, won: bool, winner: String, rate: float)

const TIERS := ["unknown", "known", "trusted", "renowned"]
const TIER_NAMES := {unknown = "Unknown", known = "Known", trusted = "Trusted", renowned = "Renowned"}
const TIER_FROM := {unknown = -100.0, known = 10.0, trusted = 40.0, renowned = 70.0}
## Open offers at a time by the company's best tier, and the spread of kinds.
const OFFERS_BY_TIER := {unknown = 5, known = 12, trusted = 20, renowned = 30}
const RECURRING_SHARE := 0.4
const OFFER_DAYS := 8
const EXPIRE_DAYS := [14, 28]
const QUARTER_DAYS := 91.3125
const PREMIUM_LOW := 1.3
const PREMIUM_HIGH := 2.0
## Plain freight: HANDLING of the base price plus the base price per FREIGHT_NM sailed (dearer than the paper firms' own freight: a contract pays like a good spot trade), and never under GAP_FLOOR of the spot gap between the two ports at signing.
const HANDLING := 0.1
const FREIGHT_NM := 8000.0
const GAP_FLOOR := 0.8
## A one-off's units: the company's biggest ship of the line's hold (x this); a recurring contract's a quarter: a few holds a month.
const VOYAGE_HOLDS := 1.0
const RECURRING_HOLDS_A_MONTH := [1.5, 4.0]
const QUARTERS := [2, 8]
## Standing: what a delivery, a quarter met, a contract done, a quarter short and a failure do.
const REP_DELIVERY := 0.5
const REP_QUARTER := 3.0
const REP_DONE := 8.0
const REP_SHORT := -6.0
const REP_FAILED := -12.0
const SHORTFALL_FEE := 0.5
const FAILED_FEE := 0.2
## Standing fades towards 0 by this share a month.
const REP_FADE := 0.02
const HOME_START := 20.0
const IMPORTANT_SHARE := 0.1
const IMPORTANT_LEAST := 500000.0
const KINDS := {voyage = "Voyage", recurring = "Recurring", tender = "Tender"}
## Tenders (from Trusted up): the share of new offers that are tenders, how long they take bids, how many firms bid, their bids' spread, how much standing weighs in the award (a bid / (1 + standing / STANDING_WEIGHT)), and the units beyond a recurring contract's.
const TENDER_SHARE := 0.3
const TENDER_DAYS := [14, 21]
const TENDER_BIDDERS := [3, 6]
const BID_SPREAD := [0.9, 1.15]
const STANDING_WEIGHT := 400.0
const TENDER_HOLDS := 2.5
const RENOWNED_VALUE := 50000000.0

var _state: Node  # GameState
## Open offers to the player's company: {id, kind, producer, good, from, to, nm, units, quarters, rate, premium, value, offered, expires, min_tier, country}.
var offers: Array = []
## Signed contracts: an offer's fields plus {company, signed, status, ships, delivered, quarter, quarter_delivered, quarter_end, quarters_done, due, fees}.
var contracts: Array = []
var _next_id := 1
var _offer_day := -1
var _month := -1


func _init(state: Node) -> void:
	_state = state


func clear() -> void:
	offers.clear()
	contracts.clear()
	_next_id = 1
	_offer_day = -1
	_month = -1


# --- Standing ----------------------------------------------------------------------------

## A company's standing with a country (-100..100).
static func country_standing(company: Company, country: String) -> float:
	return clampf(float((company.relations.get("countries", {}) as Dictionary).get(country, 0.0)), -100.0, 100.0)


## A company's standing with a producer: its country's plus the producer's own memory.
func opinion(company: Company, producer: int) -> float:
	var info := _producer(producer)
	var own := float((company.relations.get("producers", {}) as Dictionary).get(str(producer), 0.0))
	return clampf(country_standing(company, str(info.get("country", ""))) + own, -100.0, 100.0)


static func tier_of(value: float) -> String:
	var out := "unknown"
	for tier: String in TIERS:
		if value >= float(TIER_FROM[tier]):
			out = tier
	return out


static func tier_name(tier: String) -> String:
	return str(TIER_NAMES.get(tier, tier.capitalize()))


static func tier_at_least(tier: String, least: String) -> bool:
	return TIERS.find(tier) >= TIERS.find(least)


## The best tier a company holds with any country (what sets how many offers it sees).
func best_tier(company: Company) -> String:
	var best := -100.0
	for country: String in company.relations.get("countries", {}):
		best = maxf(best, country_standing(company, country))
	return tier_of(best)


## Moves a company's standing with a producer and its country.
func change_standing(company: Company, producer: int, amount: float, country_share := 0.5) -> void:
	var info := _producer(producer)
	var producers: Dictionary = company.relations.get_or_add("producers", {})
	producers[str(producer)] = clampf(float(producers.get(str(producer), 0.0)) + amount * (1.0 - country_share), -100.0, 100.0)
	var country := str(info.get("country", ""))
	if not country.is_empty():
		var countries: Dictionary = company.relations.get_or_add("countries", {})
		countries[country] = clampf(float(countries.get(country, 0.0)) + amount * country_share, -100.0, 100.0)


## A new company starts Known at home.
func start_standing(company: Company) -> void:
	var home: String = _state.world.country_of_port(company.home_port)
	if home.is_empty():
		return
	var countries: Dictionary = company.relations.get_or_add("countries", {})
	countries[home] = maxf(float(countries.get(home, 0.0)), HOME_START)


func _producer(index: int) -> Dictionary:
	var companies: Array = (_state.world as WorldEconomy).producers.companies
	return companies[index] if index >= 0 and index < companies.size() else {}


func producer_name(index: int) -> String:
	return str(_producer(index).get("name", "a producer"))


# --- Each day -----------------------------------------------------------------------------

func step(_delta: float) -> void:
	var world: WorldEconomy = _state.world
	if world.zones.is_empty():
		return
	var day := world.day
	if _offer_day < 0 or day - _offer_day >= OFFER_DAYS:
		_offer_day = day
		_refresh_offers()
	var now: int = _state.calendar_time()
	var month: int = _state.history.month_now() if _state.history != null else -1
	if month != _month:
		if _month >= 0:
			_fade_standing()
		_month = month
	_expire_offers(now)
	_run_contracts(now)


func _fade_standing() -> void:
	for company: Company in _state.all_companies():
		for key: String in ["countries", "producers"]:
			var table: Dictionary = company.relations.get(key, {})
			for id: String in table:
				table[id] = float(table[id]) * (1.0 - REP_FADE)


func _expire_offers(now: int) -> void:
	for offer: Dictionary in offers.duplicate():
		if str(offer.kind) == "tender" and now >= int(offer.closes):
			_close_tender(offer)
	var kept := offers.filter(func(offer: Dictionary) -> bool: return int(offer.expires) > now)
	if kept.size() != offers.size():
		offers = kept
		offers_changed.emit()


## Remakes the open offers: the ones still fresh stay, new ones fill the
## company's quota from where the economy calls for shipping.
func _refresh_offers() -> void:
	var company: Company = _state.company
	if company == null:
		return
	var world: WorldEconomy = _state.world
	var tier := best_tier(company)
	var quota := int(OFFERS_BY_TIER.get(tier, 5))
	if offers.size() >= quota:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|%d" % [world.seed, world.day])
	var wanted := quota - offers.size()
	var tries := 0
	var lanes := _lanes_in_need(world)
	lanes.shuffle()
	var home: String = world.country_of_port(company.home_port)
	var made := 0
	while made < wanted and tries < lanes.size():
		var lane: Dictionary = lanes[tries]
		tries += 1
		var producer := int(lane.producer)
		var standing := tier_of(opinion(company, producer))
		var recurring := rng.randf() < RECURRING_SHARE and tier_at_least(standing, "known")
		var tender := tier_at_least(standing, "trusted") and rng.randf() < TENDER_SHARE
		if tier == "unknown" and str(lane.country) != home:
			continue  # (Unknown everywhere: only home shows an interest.)
		var offer := _make_offer(company, lane, recurring or tender, rng, tender)
		if offer.is_empty():
			continue
		offers.append(offer)
		made += 1
		if _is_important(company, offer) or str(offer.kind) == "tender":
			offer_arrived.emit(offer)
	if made > 0:
		offers_changed.emit()


## Where the economy wants shipping now: [{producer, good, from, to, nm, urgency, country}],
## a producer's plant at a port of a zone long of its good, bound for a zone short of it.
func _lanes_in_need(world: WorldEconomy) -> Array:
	var out := []
	var g_count := world.goods.size()
	var producers := world.producers
	for g in g_count:
		var good := world.goods[g]
		var line := WorldEconomy.line_of(good)
		if line.is_empty():
			continue
		var exporters := []
		var importers := []
		for z in world.zones.size():
			var i := z * g_count + g
			var use := world.use_for_price(i)
			if use <= 0.0:
				continue
			var ratio := world.price[i] / maxf(world._base[g], 0.000001)
			if world.stock[i] > ShippingFirms.EXPORT_COVER * use and ratio < 0.95:
				exporters.append(z)
			elif ratio > 1.1 and world.need_base[i] + world.user_base[i] > 0.0:
				importers.append([z, ratio])
		if exporters.is_empty() or importers.is_empty():
			continue
		importers.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
		for z: int in exporters:
			var zone: Dictionary = world.zones[z]
			for port_id: String in zone.ports:
				for index: int in producers.plants_at(port_id):
					var plant: Dictionary = producers.plants[index]
					if plant.good != good:
						continue
					for importer: Array in importers.slice(0, 3):
						var to_zone: Dictionary = world.zones[int(importer[0])]
						var to_port := str(to_zone.main)
						var nm := GameData.distance_nm(port_id, to_port)
						if nm == INF or nm < 200.0:
							continue
						out.append({producer = int(plant.company), good = good, from = port_id, to = to_port, nm = nm,
							urgency = clampf((float(importer[1]) - 1.0) / 1.0, 0.0, 1.0), country = str(zone.country), line = line})
					break  # (One plant of the good at a port is enough.)
	return out


func _make_offer(company: Company, lane: Dictionary, recurring: bool, rng: RandomNumberGenerator, tender := false) -> Dictionary:
	var good := str(lane.good)
	var hold := _biggest_hold(company, str(lane.line), good)
	if hold <= 0.0:
		return {}
	if float(lane.nm) > _longest_leg(company, good) * 0.9:
		return {}  # (Beyond what any ship of the company, or the line's smallest, can sail on a tank.)
	var base := float(GameData.commodity(good).get("base", 1.0))
	var premium := lerpf(PREMIUM_LOW, PREMIUM_HIGH, float(lane.urgency))
	var rate := base * (HANDLING + float(lane.nm) / FREIGHT_NM) * premium
	var gap: float = _state.market.sell_price(str(lane.to), good) - _state.market.buy_price(str(lane.from), good)
	rate = maxf(rate, gap * GAP_FLOOR)
	var units: int
	var quarters := 0
	if recurring:
		units = roundi(hold * rng.randf_range(float(RECURRING_HOLDS_A_MONTH[0]), float(RECURRING_HOLDS_A_MONTH[1])) * 3.0 * (TENDER_HOLDS if tender else 1.0))
		quarters = rng.randi_range(int(QUARTERS[0]), int(QUARTERS[1])) + (2 if tender else 0)
	else:
		units = roundi(hold * VOYAGE_HOLDS)
	var value := rate * units * maxi(quarters, 1)
	var now: int = _state.calendar_time()
	var offer := {id = _next_id, kind = "recurring" if recurring else "voyage", producer = int(lane.producer), good = good, from = str(lane.from), to = str(lane.to), nm = float(lane.nm),
		units = units, quarters = quarters, rate = snappedf(rate, 0.01), premium = snappedf(premium, 0.01), value = roundi(value), offered = now,
		expires = now + rng.randi_range(int(EXPIRE_DAYS[0]), int(EXPIRE_DAYS[1])) * 86400, country = str(lane.country),
		min_tier = "known" if recurring or value > 2000000.0 else "unknown"}
	if tender:
		offer.kind = "tender"
		offer.min_tier = "renowned" if value > RENOWNED_VALUE else "trusted"
		offer.closes = now + rng.randi_range(int(TENDER_DAYS[0]), int(TENDER_DAYS[1])) * 86400
		offer.expires = int(offer.closes)
		offer.asking = offer.rate
		offer.plain = snappedf(base * (HANDLING + float(lane.nm) / FREIGHT_NM), 0.01)
		offer.my_bid = -1.0
		_pick_bidders(offer, rng)
	_next_id += 1
	return offer


## The firms bidding on a tender (those based in the load port's country first,
## then the biggest), each with its sealed bid: plain freight x its CEO's
## margin, with noise, a little more where the market is urgent.
func _pick_bidders(offer: Dictionary, rng: RandomNumberGenerator) -> void:
	var firms: ShippingFirms = _state.firms
	var order := range(firms.firms.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var fa: Dictionary = firms.firms[a]
		var fb: Dictionary = firms.firms[b]
		var ha: bool = fa.country == offer.country
		var hb: bool = fb.country == offer.country
		if ha != hb:
			return ha
		return float(fa.size) > float(fb.size))
	var count := rng.randi_range(int(TENDER_BIDDERS[0]), int(TENDER_BIDDERS[1]))
	var bidders := []
	var bids := {}
	for i: int in order.slice(0, count):
		var firm: Dictionary = firms.firms[i]
		bidders.append(i)
		bids[str(i)] = snappedf(float(offer.plain) * Traits.ai_margin(firm.get("ceo", {})) * rng.randf_range(float(BID_SPREAD[0]), float(BID_SPREAD[1])) * (1.0 + float(offer.premium) - PREMIUM_LOW), 0.01)
	offer.bidders = bidders
	offer.bids = bids


## A producer's standing with a paper firm: by the firm's size, more for one of its own country.
func ai_standing(offer: Dictionary, firm_index: int) -> float:
	var firms: ShippingFirms = _state.firms
	var firm: Dictionary = firms.firms[firm_index]
	var biggest := 0.0
	for each: Dictionary in firms.firms:
		biggest = maxf(biggest, float(each.size))
	return 25.0 + 40.0 * float(firm.size) / maxf(biggest, 0.0001) + (10.0 if firm.country == offer.country else 0.0)


## The player's company bids on a tender (GameState.bid_tender()).
func bid(offer: Dictionary, rate: float) -> void:
	offer.my_bid = snappedf(maxf(rate, 0.01), 0.01)
	offers_changed.emit()


## A tender closing: the lowest bid weighted by the producer's standing with the bidder wins.
func _close_tender(offer: Dictionary) -> void:
	var company: Company = _state.company
	var best_score := INF
	var winner := -2  # -1 the player, else a firm index, -2 nobody.
	var winning_rate := 0.0
	for key: String in offer.bids:
		var firm_index := int(key)
		var score := float(offer.bids[key]) / (1.0 + ai_standing(offer, firm_index) / STANDING_WEIGHT)
		if score < best_score:
			best_score = score
			winner = firm_index
			winning_rate = float(offer.bids[key])
	if float(offer.my_bid) > 0.0:
		var score := float(offer.my_bid) / (1.0 + opinion(company, int(offer.producer)) / STANDING_WEIGHT)
		if score < best_score:
			best_score = score
			winner = -1
			winning_rate = float(offer.my_bid)
	var producer := producer_name(int(offer.producer))
	var firms: ShippingFirms = _state.firms
	if winner == -1:
		offer.rate = winning_rate
		offer.value = roundi(winning_rate * int(offer.units) * maxi(int(offer.quarters), 1))
		offer.kind = "recurring"
		var contract := sign_offer(company, offer)
		change_standing(company, int(offer.producer), REP_QUARTER)
		if _state.news != null:
			_state.news.add("company", "%s wins %s's tender for %s at %s a unit" % [company.name, producer, _good_word(str(offer.good)), Fmt.money(roundi(winning_rate))], {port = offer.from})
		tender_closed.emit(contract, true, company.name, winning_rate)
		return
	offers.erase(offer)
	var winner_name := str(firms.firms[winner].name) if winner >= 0 else "nobody"
	if _state.news != null and winner >= 0:
		_state.news.add("company", "%s wins %s's tender for %s, %s to %s, at %s a unit" % [winner_name, producer, _good_word(str(offer.good)), GameData.port_name(str(offer.from)), GameData.port_name(str(offer.to)), Fmt.money(roundi(winning_rate))], {port = offer.from, firm = winner})
	if float(offer.my_bid) > 0.0:
		tender_closed.emit(offer, false, winner_name, winning_rate)
	offers_changed.emit()


## The longest leg (nm) a ship of the company carrying the good can sail on a tank, else the line's smallest model's.
func _longest_leg(company: Company, good: String) -> float:
	var best := 0.0
	for ship: Ship in _state.fleet(company):
		if good in ship.model().get("cargo", []):
			best = maxf(best, ship.range_nm())
	if best > 0.0:
		return best
	var smallest := {}
	for model: Dictionary in GameData.ship_models:
		if good in model.get("cargo", []) and not model.get("coming_soon", false) and (smallest.is_empty() or int(model.get("capacity", 0)) < int(smallest.get("capacity", 0))):
			smallest = model
	if smallest.is_empty():
		return 0.0
	return float(smallest.get("range_nm", 0))

## The hold (units of the good) of the company's biggest ship that carries the good, else the line's smallest model's.
func _biggest_hold(company: Company, line: String, good: String) -> float:
	var best := 0.0
	for ship: Ship in _state.fleet(company):
		if good in ship.model().get("cargo", []):
			best = maxf(best, float(ship.capacity()) / GameData.hold_of(good))
	if best > 0.0:
		return best
	var smallest := INF
	for model: Dictionary in GameData.ship_models:
		if good in model.get("cargo", []) and not model.get("coming_soon", false):
			smallest = minf(smallest, float(model.get("capacity", 0)) / GameData.hold_of(good))
	return smallest if smallest < INF else 0.0


func _is_important(company: Company, offer: Dictionary) -> bool:
	var value := float(offer.value)
	return value >= IMPORTANT_LEAST and value >= _state.company_value(company) * IMPORTANT_SHARE * float(Settings.offer_bar)


## Whether a company may take an offer: its standing with the producer reaches the offer's tier.
func can_sign(company: Company, offer: Dictionary) -> String:
	if str(offer.kind) == "tender":
		return "A tender: bid on it instead"
	var standing := tier_of(opinion(company, int(offer.producer)))
	if not tier_at_least(standing, str(offer.min_tier)):
		return "%s wants a %s company for this (you're %s with them: %d)" % [producer_name(int(offer.producer)), tier_name(str(offer.min_tier)), tier_name(standing), roundi(opinion(company, int(offer.producer)))]
	return ""


# --- Signing and sailing -------------------------------------------------------------------

func offer_by_id(id: int) -> Dictionary:
	for offer: Dictionary in offers:
		if int(offer.id) == id:
			return offer
	return {}


func contract_by_id(id: int) -> Dictionary:
	for contract: Dictionary in contracts:
		if int(contract.id) == id:
			return contract
	return {}


## Signs an offer for a company (GameState.sign_contract(); not `sign`: that is GDScript's own).
func sign_offer(company: Company, offer: Dictionary) -> Dictionary:
	offers.erase(offer)
	var now: int = _state.calendar_time()
	var contract := offer.duplicate(true)
	contract.company = _state.all_companies().find(company)
	contract.signed = now
	contract.status = "active"
	contract.ships = []
	contract.delivered = 0
	contract.quarter = 0
	contract.quarter_delivered = 0
	contract.quarters_done = 0
	contract.fees = 0
	if str(contract.kind) == "recurring":
		contract.quarter_end = now + int(QUARTER_DAYS * 86400.0)
	else:
		var days := float(contract.nm) / maxf(_slowest_speed(str(contract.good)) * 86400.0 / _state.calendar_seconds_per_second(), 1.0)
		contract.due = now + int((days * 3.0 + 30.0) * 86400.0)
	contracts.append(contract)
	offers_changed.emit()
	contracts_changed.emit()
	return contract


## The slowest model's speed (nm a play second) among those carrying a good.
func _slowest_speed(good: String) -> float:
	var slowest := INF
	for model: Dictionary in GameData.ship_models:
		if good in model.get("cargo", []):
			slowest = minf(slowest, float(model.get("speed_nm_per_s", 5.0)))
	return slowest if slowest < INF else 5.0


func decline(offer: Dictionary) -> void:
	offers.erase(offer)
	offers_changed.emit()


## A ship put to a contract: routed load port to delivery port (GameState.assign_contract_ship()).
func assign_ship(contract: Dictionary, ship: Ship) -> void:
	for other: Dictionary in contracts:
		(other.ships as Array).erase(ship.id)
	(contract.ships as Array).append(ship.id)
	ship.contract_id = int(contract.id)
	contracts_changed.emit()


func unassign_ship(ship: Ship) -> void:
	for other: Dictionary in contracts:
		(other.ships as Array).erase(ship.id)
	ship.contract_id = 0
	contracts_changed.emit()


## A ship's active contract, or {}.
func of_ship(ship: Ship) -> Dictionary:
	if ship.contract_id <= 0:
		return {}
	var contract := contract_by_id(ship.contract_id)
	return contract if not contract.is_empty() and str(contract.status) == "active" else {}


## What's still to carry this quarter (or in all, for a voyage).
static func units_left(contract: Dictionary) -> int:
	if str(contract.kind) == "recurring":
		return maxi(int(contract.units) - int(contract.quarter_delivered), 0)
	return maxi(int(contract.units) - int(contract.delivered), 0)


## A ship at its contract's load port, bound for the delivery port, loads the
## contract's cargo first (free: the producer's) up to its room and what's
## left to carry: [good, units] or [] (GameState._load_cargo()).
func load_ship(ship: Ship, to: String) -> Array:
	var contract := of_ship(ship)
	if contract.is_empty() or ship.docked_at != str(contract.from) or to != str(contract.to):
		return []
	var good := str(contract.good)
	var room := floori(ship.capacity() * (1.0 - GameData.leg_lightening(ship.docked_at, to, ship.model())) / GameData.hold_of(good))
	var units := mini(room, units_left(contract))
	if units <= 0:
		return []
	var world: WorldEconomy = _state.world
	var z := world.zone_of_port(ship.docked_at)
	var g := world.good_index(good)
	if z >= 0 and g >= 0:
		units = mini(units, floori(world.take(z, g, units)))  # (Out of the zone's stockpile, as any loading is.)
		if units <= 0:
			return []
		world.add_inbound(world.zone_of_port(to), g, units)
	ship.cargo_id = good
	ship.cargo_qty = units
	ship.cargo_cost = 0
	ship.cargo_from = ship.docked_at
	ship.cargo_contract = int(contract.id)
	ship.cargo_leg_nm = GameData.distance_nm(ship.docked_at, to)
	return [good, units]


## A ship with contract cargo arriving at the delivery port: what it's paid
## (GameState._arrive_timed()), or -1 for cargo not under contract here.
func payment_for(ship: Ship, port: String) -> int:
	if ship.cargo_contract <= 0:
		return -1
	var contract := contract_by_id(ship.cargo_contract)
	if contract.is_empty() or port != str(contract.to):
		return -1
	return roundi(ship.cargo_qty * float(contract.rate))


## A delivery under contract counted (GameState._sell_cargo()).
func delivered(ship: Ship, port: String) -> void:
	var contract := contract_by_id(ship.cargo_contract)
	ship.cargo_contract = 0
	if contract.is_empty() or port != str(contract.to) or str(contract.status) != "active":
		return
	var company: Company = _state.all_companies()[int(contract.company)]
	contract.delivered = int(contract.delivered) + ship.cargo_qty
	contract.quarter_delivered = int(contract.quarter_delivered) + ship.cargo_qty
	change_standing(company, int(contract.producer), REP_DELIVERY)
	if str(contract.kind) == "voyage" and int(contract.delivered) >= int(contract.units):
		_finish(contract, company, true)
	contracts_changed.emit()


## Quarters ending and voyages overdue.
func _run_contracts(now: int) -> void:
	var changed := false
	for contract: Dictionary in contracts:
		if str(contract.status) != "active":
			continue
		var company: Company = _state.all_companies()[int(contract.company)]
		if str(contract.kind) == "recurring":
			if now < int(contract.quarter_end):
				continue
			var short := units_left(contract)
			if short > 0:
				var fee := roundi(short * float(contract.rate) * SHORTFALL_FEE)
				_state._add_money(company, -fee)
				_state._record(null, "contract_fees", fee, company)
				contract.fees = int(contract.fees) + fee
				change_standing(company, int(contract.producer), REP_SHORT)
				if company == _state.company:
					ActivityLog.add("%s short on %s for %s this quarter: a %s fee." % [Fmt.thousands(short), _good_word(str(contract.good)), producer_name(int(contract.producer)), Fmt.money(fee)], ActivityLog.Kind.BAD)
			else:
				change_standing(company, int(contract.producer), REP_QUARTER)
				if company == _state.company:
					ActivityLog.add("Quarter met on the %s contract for %s." % [_good_word(str(contract.good)), producer_name(int(contract.producer))], ActivityLog.Kind.GOOD)
			contract.quarters_done = int(contract.quarters_done) + 1
			contract.quarter = int(contract.quarter) + 1
			contract.quarter_delivered = 0
			contract.quarter_end = int(contract.quarter_end) + int(QUARTER_DAYS * 86400.0)
			if int(contract.quarters_done) >= int(contract.quarters):
				_finish(contract, company, true)
			changed = true
		elif now > int(contract.due):
			var fee := roundi(float(contract.value) * FAILED_FEE)
			_state._add_money(company, -fee)
			_state._record(null, "contract_fees", fee, company)
			contract.fees = int(contract.fees) + fee
			_finish(contract, company, false)
			changed = true
	if changed:
		contracts_changed.emit()


func _finish(contract: Dictionary, company: Company, done: bool) -> void:
	contract.status = "done" if done else "failed"
	change_standing(company, int(contract.producer), REP_DONE if done else REP_FAILED)
	for ship: Ship in _state.fleet(company):
		if ship.contract_id == int(contract.id):
			ship.contract_id = 0
	if company == _state.company:
		if done:
			ActivityLog.add("Contract done: %s for %s, %s to %s. They think better of us." % [_good_word(str(contract.good)), producer_name(int(contract.producer)), GameData.port_name(str(contract.from)), GameData.port_name(str(contract.to))], ActivityLog.Kind.GOOD)
		else:
			ActivityLog.add("Contract failed: the %s for %s wasn't carried in time. A %s fee, and they'll remember." % [_good_word(str(contract.good)), producer_name(int(contract.producer)), Fmt.money(int(contract.fees))], ActivityLog.Kind.BAD)
	if _state.news != null:
		_state.news.add("company", "%s %s a %s contract for %s" % [company.name, "completes" if done else "fails", _good_word(str(contract.good)), producer_name(int(contract.producer))], {port = contract.to})


static func _good_word(good: String) -> String:
	var name := str(GameData.commodity(good).get("name", good))
	return name if name == name.to_upper() else name.to_lower()


## A contract's state in a line ("Quarter 2 of 4: 12,000 of 40,000 t · 61 days left").
func progress_text(contract: Dictionary) -> String:
	var units := str(GameData.commodity(str(contract.good)).get("units", "units"))
	var now: int = _state.calendar_time()
	match str(contract.status):
		"done":
			return "Done"
		"failed":
			return "Failed"
	if str(contract.kind) == "recurring":
		return "Quarter %d of %d: %s of %s %s · %d days left" % [int(contract.quarter) + 1, int(contract.quarters), Fmt.thousands(int(contract.quarter_delivered)), Fmt.thousands(int(contract.units)), units,
			maxi(roundi((int(contract.quarter_end) - now) / 86400.0), 0)]
	return "%s of %s %s · due in %d days" % [Fmt.thousands(int(contract.delivered)), Fmt.thousands(int(contract.units)), units, maxi(roundi((int(contract.due) - now) / 86400.0), 0)]


## What the ships assigned can carry a quarter (units), against the contract's.
func capacity_a_quarter(contract: Dictionary) -> float:
	var total := 0.0
	var good := str(contract.good)
	for id: int in contract.ships:
		var ship: Ship = _state.ship_by_id(id)
		if ship == null:
			continue
		var round_trip_s := 2.0 * float(contract.nm) / maxf(ship.top_speed(), 0.1) + 2.0 * ship.dock_seconds()
		var trips: float = QUARTER_DAYS * 86400.0 / _state.calendar_seconds_per_second() / maxf(round_trip_s, 1.0)
		total += trips * float(ship.capacity()) / GameData.hold_of(good)
	return total


# --- Saving ------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {offers = offers, contracts = contracts, next_id = _next_id, offer_day = _offer_day, month = _month}


func from_dict(data: Dictionary) -> void:
	offers = data.get("offers", []) if data.get("offers") is Array else []
	contracts = data.get("contracts", []) if data.get("contracts") is Array else []
	for contract: Dictionary in contracts:
		if contract.ships is Array:
			var ids := []
			for id in contract.ships:
				ids.append(int(id))
			contract.ships = ids
	_next_id = int(data.get("next_id", 1))
	_offer_day = int(data.get("offer_day", -1))
	_month = int(data.get("month", -1))
	offers_changed.emit()
	contracts_changed.emit()

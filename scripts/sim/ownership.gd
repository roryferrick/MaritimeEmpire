# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Ownership
extends RefCounted
## Who owns the companies (DESIGN_LIVING_WORLD.md M3): every company has
## TOTAL_SHARES shares (Company.shares: the holders, the founder with all but
## the backstory backers' stake; new shares when it lists), a share price (the
## company's value a share, x the market's sentiment once listed) with a
## monthly history, a dividend (a share of each quarter's profit to the
## holders; the founder's part stays in the company), and a board: the holders
## of BOARD_MIN or more, each a character with an opinion of the CEO, voting
## by shareholding on the big moves (propose(): buying into a firm, going
## public, issuing or buying back shares, the dividend) and, when enough of
## them have turned against the CEO, no confidence. The paper shipping firms
## can be bought into in BLOCK stakes at a rising premium (firm_value(): their
## fleet at list price plus FIRM_EARNINGS_YEARS of earnings); past CONTROL the
## firm is the company's (its traffic in the company's colour, a share of its
## earnings each month). Going public is a process (ipo): a bank (BANKS: fee,
## reach, prestige), its valuation, a price range and a share to sell, a
## roadshow of ROADSHOW_MEETINGS investor meetings whose answers and the CEO's
## traits move demand, listing day, then quarterly reports against
## expectations moving the price. Cards for all of it (GameRoot).

signal changed
## A motion was voted on: passed or not, with the tally (yes shares, all shares).
signal vote_result(company: Company, motion: Dictionary, passed: bool, yes: float, total: float)
## The board has removed the CEO (a no-confidence vote passed).
signal coup(company: Company)
## A step of the IPO wants the player: kind "meeting" (an investor's question) or "listing" (the day), info by kind.
signal ipo_event(company: Company, kind: String, info: Dictionary)
## A listed company's quarterly report.
signal quarterly(company: Company, report: Dictionary)
## A controlled firm wants to order a ship from its own cash (a card: GameState.answer_firm_order()). proposal: {firm, model, yard, price, months}.
signal firm_order_wanted(company: Company, proposal: Dictionary)

const TOTAL_SHARES := 1000000
const BOARD_MIN := 0.05
const BLOCK := 0.05
const BLOCK_PREMIUM := 0.1
const CONTROL := 0.5
const FIRM_EARNINGS_YEARS := 4.0
const VOTE_FREE_SHARE := 0.1  # A move worth less than this of the company's value needs no vote.
const NO_CONFIDENCE_OPINION := -40.0
## The paper firms buy into a listed player (_ai_stakes()): when the market is hot or the price cheap, a block at a time up to AI_CAP each, AI_CHANCE a month a firm with the cash.
const AI_CAP := 0.2
const AI_CHANCE := 0.06
const AI_HOT := 1.2
const AI_CHEAP := 0.8
const AI_BUYBACK_PREMIUM := 0.2
const QUARTER_DAYS := 91.3125
const ROADSHOW_MEETINGS := 4
const MEETING_DAYS := 7
const IPO_SHARE := [0.1, 0.49]
const RANGE_WIDTH := 0.15
## The investment banks: id -> {name, fee (of what's raised), reach (demand it brings), min_value (the companies it takes)}.
const BANKS := {
	harbour = {name = "Harbour & Keel", fee = 0.07, reach = 0.0, min_value = 0.0},
	meridian = {name = "Meridian Securities", fee = 0.06, reach = 0.05, min_value = 20000000.0},
	trident = {name = "Trident Capital Markets", fee = 0.05, reach = 0.1, min_value = 100000000.0},
	northstar = {name = "Northstar Brothers", fee = 0.045, reach = 0.15, min_value = 500000000.0},
	goldwater = {name = "Goldwater Sachs", fee = 0.04, reach = 0.2, min_value = 2000000000.0},
}
const BANK_ORDER := ["harbour", "meridian", "trident", "northstar", "goldwater"]
## The roadshow's investors and their questions: each with three answers and what each does to demand for that investor; the CEO's traits move it too.
const MEETINGS := [
	{who = "a pension fund", question = "We hold for decades. What do you promise our pensioners?", answers = [["A steady dividend from day one", 0.12], ["Growth first; dividends when we're bigger", -0.04], ["Safe ships and no surprises", 0.06]]},
	{who = "a hedge fund", question = "Shipping is cyclical. How do you beat the cycle?", answers = [["Long contracts with the producers", 0.1], ["We buy ships when they're cheap", 0.06], ["We don't; we ride it", -0.06]]},
	{who = "a sovereign wealth fund", question = "Why should our country's money sail under your flag?", answers = [["We'll hire and train in your ports", 0.1], ["Our standing with your producers", 0.08], ["Because we'll be the biggest", -0.02]]},
	{who = "the retail brokers", question = "What's the story a small investor can tell at dinner?", answers = [["A fleet you can watch on the map", 0.08], ["The numbers speak for themselves", -0.03], ["We're the people's shipping line", 0.1]]},
]
const EXCHANGES := {east_asia = "Hong Kong", southeast_asia = "Singapore", south_asia = "Mumbai", middle_east = "Dubai", east_africa = "Johannesburg", west_africa = "Lagos", mediterranean = "Milan",
	north_europe = "London", na_east = "New York", gulf_caribbean = "New York", na_west = "New York", great_lakes = "Toronto", south_america = "São Paulo", oceania = "Sydney", russia_far_east = "Tokyo", arctic = "Oslo", antarctica = "Sydney"}

var _state: Node  # GameState
var _month := -1


func _init(state: Node) -> void:
	_state = state


func reset() -> void:
	_month = -1


# --- The register ---------------------------------------------------------------------------

## A company's shares, made the first time they're asked for: the founder and the backstory's backers.
func ensure(company: Company) -> Dictionary:
	if not company.shares.is_empty():
		return company.shares
	var holders := []
	var backer_stake := float((company.investors as Dictionary).get("stake", 0.0)) if company.investors is Dictionary else 0.0
	var backer_count := roundi(TOTAL_SHARES * backer_stake)
	holders.append({kind = "founder", name = str(company.ceo.get("name", "The founder")), count = TOTAL_SHARES - backer_count, opinion = 100.0})
	if backer_count > 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(company.name)
		var manager := Characters.random_person(rng, "exec", "")
		holders.append({kind = "backer", name = str(company.investors.get("name", "the backers")), character = manager, count = backer_count, opinion = 15.0})
	company.shares = {holders = holders, total = TOTAL_SHARES, listed = false, sentiment = 1.0, history = [], dividend = 0.0, ipo = {}, snapshot = {}, last_profit = 0.0, expected = 0.0, quarter_end = 0, exchange = ""}
	company.shares.snapshot = company.totals.duplicate()
	company.shares.quarter_end = _state.calendar_time() + int(QUARTER_DAYS * 86400.0)
	return company.shares


func total_shares(company: Company) -> int:
	return int(ensure(company).total)


## The price a share: the company's value a share, x sentiment once listed.
func price(company: Company) -> float:
	var shares := ensure(company)
	var value: float = _state.company_value(company)
	return maxf(value / maxf(float(shares.total), 1.0), 0.01) * (float(shares.sentiment) if bool(shares.listed) else 1.0)


func share_of(company: Company, holder: Dictionary) -> float:
	return float(holder.count) / maxf(float(ensure(company).total), 1.0)


func founder(company: Company) -> Dictionary:
	for holder: Dictionary in ensure(company).holders:
		if holder.kind == "founder":
			return holder
	return {}


func founder_share(company: Company) -> float:
	var f := founder(company)
	return share_of(company, f) if not f.is_empty() else 0.0


## The board: the holders of BOARD_MIN or more.
func board(company: Company) -> Array:
	var out := []
	for holder: Dictionary in ensure(company).holders:
		if holder.kind == "founder" or share_of(company, holder) >= BOARD_MIN:
			out.append(holder)
	return out


# --- Votes --------------------------------------------------------------------------------

## A motion: {kind ("dividend", "buy_block", "issue", "buyback", "ipo"), args, text, worth}. A
## move worth under VOTE_FREE_SHARE of the company's value goes through
## without a vote (the IPO always votes). Returns whether it passed.
func propose(company: Company, motion: Dictionary) -> bool:
	var shares := ensure(company)
	var worth := float(motion.get("worth", 0.0))
	var needs_vote: bool = str(motion.kind) in ["ipo", "issue"] or worth >= _state.company_value(company) * VOTE_FREE_SHARE
	var yes := 0.0
	var total := float(shares.total)
	if needs_vote:
		for holder: Dictionary in shares.holders:
			if _votes_yes(company, holder, motion):
				yes += float(holder.count)
	else:
		yes = total
	var passed := yes > total * 0.5
	vote_result.emit(company, motion, passed, yes, total)
	if passed:
		_apply(company, motion)
	elif company == _state.company:
		ActivityLog.add("The board voted down: %s (%d%% for)." % [str(motion.text), roundi(100.0 * yes / total)], ActivityLog.Kind.BAD)
	return passed


func _votes_yes(company: Company, holder: Dictionary, motion: Dictionary) -> bool:
	match str(holder.kind):
		"founder":
			return true
		"public":
			return float(ensure(company).sentiment) >= 1.0 or str(motion.kind) == "dividend"
	var lean := float(holder.opinion)
	var person: Dictionary = holder.get("character", {})
	var traits := Traits.of(person)
	match str(motion.kind):
		"dividend":
			lean += 25.0 if float((motion.args as Dictionary).get("share", 0.0)) > float(ensure(company).dividend) else -10.0
		"buy_block":
			lean += -10.0 + (15.0 if "gambler" in traits else 0.0) - (15.0 if "cautious" in traits else 0.0)
		"issue":
			lean -= 20.0  # (Dilution.)
		"buyback":
			lean += 10.0
		"ipo":
			lean += 15.0 + (10.0 if "shrewd" in traits else 0.0)
	return lean >= 0.0


func _apply(company: Company, motion: Dictionary) -> void:
	var shares := ensure(company)
	var args: Dictionary = motion.get("args", {})
	match str(motion.kind):
		"dividend":
			shares.dividend = clampf(float(args.get("share", 0.0)), 0.0, 0.5)
		"buy_block":
			_buy_block(company, int(args.firm))
		"issue":
			_issue(company, float(args.get("share", 0.1)))
		"buyback":
			_buyback(company, float(args.get("share", 0.05)))
		"ipo":
			shares.ipo = {step = "bank"}
	if company == _state.company and str(motion.kind) != "buy_block":
		ActivityLog.add("Carried: %s." % str(motion.text), ActivityLog.Kind.GOOD)
	changed.emit()


## New shares sold to a fund at today's price (dilution; money in).
func _issue(company: Company, share: float) -> void:
	var shares := ensure(company)
	var count := roundi(float(shares.total) * share)
	var raised := roundi(count * price(company))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var fund := Characters.random_person(rng, "exec", "")
	shares.holders.append({kind = "fund", name = ["Tidewater Capital", "Halyard Partners", "the Compass fund", "Seaboard Investors", "the Mainsail fund"][rng.randi() % 5], character = fund, count = count, opinion = 10.0})
	shares.total = int(shares.total) + count
	_state._add_money(company, raised)
	_state._record(null, "shares", -raised, company)
	if _state.news != null:
		_state.news.add("company", "%s raises %s selling %d%% of itself to a fund" % [company.name, Fmt.money(raised), roundi(share * 100.0)], {})


## Shares bought back from the outside holders at today's price (money out), pro rata.
func _buyback(company: Company, share: float) -> void:
	var shares := ensure(company)
	var outside := 0
	for holder: Dictionary in shares.holders:
		if holder.kind != "founder":
			outside += int(holder.count)
	var count := mini(roundi(float(shares.total) * share), outside)
	if count <= 0:
		return
	var cost := 0
	for holder: Dictionary in shares.holders:
		if holder.kind != "founder":
			var part := roundi(count * float(holder.count) / outside)
			holder.count = int(holder.count) - part
			cost += roundi(part * price(company) * (1.0 + AI_BUYBACK_PREMIUM if holder.kind == "firm" else 1.0))  # (A firm sells back dear.)
	shares.holders = shares.holders.filter(func(holder: Dictionary) -> bool: return int(holder.count) > 0)
	shares.total = int(shares.total) - count
	_state._add_money(company, -cost)
	_state._record(null, "shares", cost, company)


# --- Each month and quarter -----------------------------------------------------------------

func step(_delta: float) -> void:
	var now: int = _state.calendar_time()
	var month: int = _state.history.month_now() if _state.history != null else -1
	for company: Company in _state.all_companies():
		var shares := ensure(company)
		if now >= int(shares.quarter_end):
			_close_quarter(company, now)
		_step_ipo(company, now)
		_step_plans(company, now)
	if month != _month:
		var first := _month < 0
		_month = month
		if not first:
			for company: Company in _state.all_companies():
				_monthly(company)


func _monthly(company: Company) -> void:
	var shares := ensure(company)
	(shares.history as Array).append(snappedf(price(company), 0.01))
	while (shares.history as Array).size() > 240:
		(shares.history as Array).pop_front()
	# The firms the company holds pay their share of the month's earnings.
	var firms: ShippingFirms = _state.firms
	for key: String in company.stakes:
		var firm: Dictionary = firms.firms[int(key)]
		var earned := float(firm.money) - float(firm.get("paid_out_from", firm.money))
		firm.paid_out_from = firm.money
		var share := float(company.stakes[key]) / TOTAL_SHARES
		if share >= CONTROL:  # (A firm the company runs pays the dividend set on its card: see plan_of().)
			share = float(ensure_plan(company, int(key)).dividend)
		firm.last_month_earned = earned
		var part := roundi(earned * share)
		if part > 0:
			_state._add_money(company, part)
			_state._record(null, "firm_earnings", -part, company)
	_firm_orders(company)
	# Opinions: a rising price pleases, a falling one grates; the board's patience with a CEO.
	var history: Array = shares.history
	if history.size() >= 2:
		var move := float(history[-1]) / maxf(float(history[-2]), 0.01) - 1.0
		for holder: Dictionary in shares.holders:
			if holder.kind != "founder":
				holder.opinion = clampf(float(holder.opinion) + move * 40.0 - 0.5, -100.0, 100.0)
	if bool(shares.listed) and company == _state.company:
		_ai_stakes(company)
	# No confidence: outside holders set against the CEO with more than half the shares.
	var against := 0.0
	for holder: Dictionary in shares.holders:
		if holder.kind != "founder" and holder.kind != "public" and float(holder.opinion) <= NO_CONFIDENCE_OPINION:
			against += float(holder.count)
	if against > float(shares.total) * 0.5 and company == _state.company:
		for holder: Dictionary in shares.holders:
			if holder.kind != "founder":
				holder.opinion = 0.0
		coup.emit(company)
	changed.emit()


## A firm with the cash buys a block of a listed player from the public when the market is hot (sentiment over AI_HOT) or cheap (under AI_CHEAP), up to AI_CAP each; it sits on the board as its CEO.
func _ai_stakes(company: Company) -> void:
	var shares := ensure(company)
	var sentiment := float(shares.sentiment)
	if sentiment < AI_HOT and sentiment > AI_CHEAP:
		return
	var public := {}
	for holder: Dictionary in shares.holders:
		if holder.kind == "public":
			public = holder
	var block := roundi(float(shares.total) * BLOCK)
	if public.is_empty() or int(public.count) < block * 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var firms: ShippingFirms = _state.firms
	var cost := block * price(company)
	for i in firms.firms.size():
		var firm: Dictionary = firms.firms[i]
		if float(firm.money) < cost * 3.0 or rng.randf() >= AI_CHANCE:
			continue
		var holder := {}
		for each: Dictionary in shares.holders:
			if each.kind == "firm" and int(each.get("firm", -1)) == i:
				holder = each
		if not holder.is_empty() and share_of(company, holder) + BLOCK > AI_CAP + 0.0001:
			continue
		if holder.is_empty():
			holder = {kind = "firm", firm = i, name = str(firm.name), character = firm.get("ceo", {}), count = 0, opinion = 5.0 if sentiment >= AI_HOT else -5.0}
			shares.holders.append(holder)
		holder.count = int(holder.count) + block
		public.count = int(public.count) - block
		firm.money = float(firm.money) - cost
		var stake := share_of(company, holder)
		ActivityLog.add("%s has bought %d%% of the company on the market and holds %d%%%s." % [str(firm.name), roundi(BLOCK * 100.0), roundi(stake * 100.0), "; it sits on your board" if stake >= BOARD_MIN else ""], ActivityLog.Kind.INFO)
		if _state.news != null:
			_state.news.add("company", "%s builds a %d%% stake in %s" % [str(firm.name), roundi(stake * 100.0), company.name], {firm = i})
		if int(public.count) < block * 2:
			break

## The quarter's profit, the dividend paid out of it, and a listed company's report against expectations.
func _close_quarter(company: Company, now: int) -> void:
	var shares := ensure(company)
	var profit := _profit_since(company, shares.snapshot)
	shares.snapshot = company.totals.duplicate()
	shares.quarter_end = now + int(QUARTER_DAYS * 86400.0)
	var paid := 0
	if float(shares.dividend) > 0.0 and profit > 0.0:
		paid = roundi(profit * float(shares.dividend) * (1.0 - founder_share(company)))
		if paid > 0:
			_state._add_money(company, -paid)
			_state._record(null, "dividends", paid, company)
		for holder: Dictionary in shares.holders:
			if holder.kind != "founder":
				holder.opinion = clampf(float(holder.opinion) + 8.0, -100.0, 100.0)
	else:
		for holder: Dictionary in shares.holders:
			if holder.kind != "founder" and profit < 0.0:
				holder.opinion = clampf(float(holder.opinion) - 10.0, -100.0, 100.0)
	if bool(shares.listed):
		var expected := float(shares.expected) if float(shares.expected) != 0.0 else maxf(float(shares.last_profit), _state.company_value(company) * 0.02)
		var ratio := (profit - expected) / maxf(absf(expected), 1.0)
		shares.sentiment = clampf(float(shares.sentiment) * (1.0 + clampf(ratio, -0.4, 0.4) * 0.5), 0.3, 3.0)
		var report := {profit = profit, expected = expected, dividend = paid, price = price(company), sentiment = float(shares.sentiment), beat = profit >= expected}
		shares.expected = maxf(profit, 0.0) * 1.05
		quarterly.emit(company, report)
		if _state.news != null:
			_state.news.add("company", "%s %s expectations: %s profit for the quarter" % [company.name, "beats" if report.beat else "misses", Fmt.money(roundi(profit))], {})
	shares.last_profit = profit
	changed.emit()


## Money made since a snapshot of the company's totals: income less every other kind (costs positive, incomes negative).
static func _profit_since(company: Company, snapshot: Dictionary) -> float:
	var profit := 0.0
	for kind: String in company.totals:
		if kind in ["shares", "dividends"]:  # (Capital moves, not the quarter's trading.)
			continue
		var delta := float(company.totals[kind]) - float(snapshot.get(kind, 0.0))
		profit += delta if kind == "income" else -delta
	return profit


# --- The paper firms --------------------------------------------------------------------------

## What a firm is worth: its fleet at list price, plus FIRM_EARNINGS_YEARS of its earnings a year so far.
func firm_value(firm_index: int) -> float:
	var firms: ShippingFirms = _state.firms
	var firm: Dictionary = firms.firms[firm_index]
	var fleet := 0.0
	for model_id: String in firm.fleet:
		fleet += float(GameData.get_ship_model(model_id).get("price", 0)) * int(firm.fleet[model_id])
	var years := maxf(float(_state.calendar_time() - _state.calendar_time_at(0.0)) / (365.25 * 86400.0), 0.25)
	return fleet + FIRM_EARNINGS_YEARS * float(firm.money) / years


## The company controlling a firm (a stake of CONTROL or more; see AmbientTraffic for its colour), or -1.
func controller_of(firm_index: int) -> int:
	var companies: Array = _state.all_companies()
	for i in companies.size():
		if stake_in(companies[i], firm_index) >= CONTROL:
			return i
	return -1


## A company's stake in a firm (0 to 1).
func stake_in(company: Company, firm_index: int) -> float:
	return float(company.stakes.get(str(firm_index), 0)) / TOTAL_SHARES


## What the next BLOCK of a firm costs: its value's share, at a premium rising with the blocks held.
func block_cost(company: Company, firm_index: int) -> int:
	var held := roundi(stake_in(company, firm_index) / BLOCK)
	return roundi(firm_value(firm_index) * BLOCK * (1.0 + BLOCK_PREMIUM * held) * (1.0 + People.soreness(company, firm_index)))  # (A firm you poached from charges more: see People.)


func buy_block_error(company: Company, firm_index: int) -> String:
	if stake_in(company, firm_index) >= 1.0 - 0.0001:
		return "You own all of it"
	var cost := block_cost(company, firm_index)
	if company.money < cost or _state.in_debt(company):
		return "Costs %s" % Fmt.money(cost)
	return ""


func _buy_block(company: Company, firm_index: int) -> void:
	if not buy_block_error(company, firm_index).is_empty():
		return
	var cost := block_cost(company, firm_index)
	_state._add_money(company, -cost)
	_state._record(null, "shares", cost, company)
	var key := str(firm_index)
	company.stakes[key] = int(company.stakes.get(key, 0)) + roundi(TOTAL_SHARES * BLOCK)
	var firms: ShippingFirms = _state.firms
	var firm: Dictionary = firms.firms[firm_index]
	_state._values_kept.erase(company)
	firm.paid_out_from = firm.money
	var took_control := stake_in(company, firm_index) >= CONTROL and stake_in(company, firm_index) - BLOCK < CONTROL
	if company == _state.company:
		ActivityLog.add("Bought %d%% of %s for %s%s." % [roundi(BLOCK * 100.0), str(firm.name), Fmt.money(cost), "; you control it now" if took_control else ""], ActivityLog.Kind.GOOD)
	if _state.news != null:
		_state.news.add("company", "%s %s %s" % [company.name, "takes control of" if took_control else "buys into", str(firm.name)], {firm = firm_index})
	changed.emit()


# --- Running the firms a company controls (DESIGN M4) --------------------------------------------

## The plan for a firm the company controls (Company.firm_plans): focus ("world" or "home": only voyages
## out of its home country), groups (the ship categories it takes; empty = all), dividend (the share
## of its month's earnings paid to the company; the rest stays its cash), extra_fleet (ships added
## by its orders: model -> count, put back on load), orders ([{model, yard, due, price}]).
func ensure_plan(company: Company, firm_index: int) -> Dictionary:
	var key := str(firm_index)
	if not company.firm_plans.has(key):
		company.firm_plans[key] = {focus = "world", groups = [], dividend = snappedf(stake_in(company, firm_index), 0.01), extra_fleet = {}, orders = [], asked = false}
	return company.firm_plans[key]


## The plan of whoever controls a firm, or {} (ShippingFirms._firm_for() asks for every lot).
func plan_of(firm_index: int) -> Dictionary:
	var key := str(firm_index)
	for company: Company in _state.all_companies():
		if company.firm_plans.has(key) and stake_in(company, firm_index) >= CONTROL:
			return company.firm_plans[key]
	return {}


func set_plan(company: Company, firm_index: int, key: String, value: Variant) -> void:
	if stake_in(company, firm_index) < CONTROL or not key in ["focus", "groups", "dividend"]:
		return
	var plan := ensure_plan(company, firm_index)
	match key:
		"dividend":
			plan.dividend = clampf(float(value), 0.0, 1.0)
		"focus":
			plan.focus = "home" if str(value) == "home" else "world"
		"groups":
			plan.groups = (value as Array).duplicate() if value is Array else []
	changed.emit()


## The ship a firm would order next: the model it has most of, from the cheapest yard with a slot.
func firm_proposal(firm_index: int) -> Dictionary:
	var firms: ShippingFirms = _state.firms
	var firm: Dictionary = firms.firms[firm_index]
	var best := ""
	var most := 0
	for model_id: String in firm.fleet:
		if int(firm.fleet[model_id]) > most:
			most = int(firm.fleet[model_id])
			best = model_id
	if best.is_empty():
		return {}
	var model := GameData.get_ship_model(best)
	var yards: Shipyards = _state.shipyards
	var offers: Array = yards.yards_for(model).filter(func(o: Dictionary) -> bool: return int(o.free) > 0)
	if offers.is_empty():
		return {}
	var offer: Dictionary = offers[0]
	return {firm = firm_index, model = best, yard = str(offer.yard), price = int(offer.price) * ShippingFirms.CONVOY, months = float(offer.months)}  # (One ship on the books is a convoy of hulls: the price follows.)


## Each month a controlled firm with the cash for a ship and no order out asks to order one (a card).
func _firm_orders(company: Company) -> void:
	if company != _state.company:
		return
	var firms: ShippingFirms = _state.firms
	for key: String in company.stakes:
		var i := int(key)
		if stake_in(company, i) < CONTROL:
			continue
		var plan := ensure_plan(company, i)
		if not (plan.orders as Array).is_empty() or bool(plan.get("asked", false)):
			continue
		var proposal := firm_proposal(i)
		if proposal.is_empty() or float(firms.firms[i].money) < float(proposal.price) * 3.0:
			continue
		plan.asked = true
		firm_order_wanted.emit(company, proposal)


## The player asks a firm to order now (its card).
func request_firm_order(company: Company, firm_index: int) -> String:
	if stake_in(company, firm_index) < CONTROL:
		return "Not yours to run"
	var proposal := firm_proposal(firm_index)
	if proposal.is_empty():
		return "No yard has a slot for its ships"
	var firms: ShippingFirms = _state.firms
	if float(firms.firms[firm_index].money) < float(proposal.price):
		return "It has %s; a ship costs %s" % [Fmt.money(roundi(float(firms.firms[firm_index].money))), Fmt.money(int(proposal.price))]
	ensure_plan(company, firm_index).asked = true
	firm_order_wanted.emit(company, proposal)
	return ""


## The answer to a firm's order card: approved, it pays the yard in full from its cash and the ship joins its books on delivery.
func answer_firm_order(company: Company, firm_index: int, approve: bool) -> void:
	var plan := ensure_plan(company, firm_index)
	plan.asked = false
	if not approve:
		return
	var proposal := firm_proposal(firm_index)
	var firms: ShippingFirms = _state.firms
	var firm: Dictionary = firms.firms[firm_index]
	if proposal.is_empty() or float(firm.money) < float(proposal.price):
		return
	firm.money = float(firm.money) - float(proposal.price)
	firm.paid_out_from = float(firm.get("paid_out_from", firm.money)) - float(proposal.price)  # (Spent on a ship, not earned less.)
	(plan.orders as Array).append({model = proposal.model, yard = proposal.yard, due = _state.calendar_time() + roundi(float(proposal.months) * 30.4375 * 86400.0), price = proposal.price})
	var yard: Dictionary = _state.shipyards.yard(str(proposal.yard))
	ActivityLog.add("%s has ordered a %s from %s for %s, due %s." % [str(firm.name), str(GameData.get_ship_model(str(proposal.model)).get("name", "")), str(yard.get("name", "")), Fmt.money(int(proposal.price)), Fmt.calendar_short(int((plan.orders as Array)[-1].due))], ActivityLog.Kind.INFO)
	if _state.news != null:
		_state.news.add("company", "%s orders a %s from %s" % [str(firm.name), str(GameData.get_ship_model(str(proposal.model)).get("name", "")), str(yard.get("name", ""))], {firm = firm_index})
	changed.emit()


## A firm's orders due are delivered onto its books (and remembered for the next load).
func _step_plans(company: Company, now: int) -> void:
	var firms: ShippingFirms = _state.firms
	for key: String in company.firm_plans:
		var plan: Dictionary = company.firm_plans[key]
		for order: Dictionary in (plan.orders as Array).duplicate():
			if now < int(order.due):
				continue
			(plan.orders as Array).erase(order)
			var model_id := str(order.model)
			(plan.extra_fleet as Dictionary)[model_id] = int((plan.extra_fleet as Dictionary).get(model_id, 0)) + 1
			firms.add_fleet(int(key), model_id, 1)
			if company == _state.company:
				ActivityLog.add("%s has taken delivery of a %s." % [str(firms.firms[int(key)].name), str(GameData.get_ship_model(model_id).get("name", ""))], ActivityLog.Kind.GOOD)
			changed.emit()


## After a load the firms are made again from the seed: the ships their orders added go back on their books.
func apply_plans() -> void:
	var firms: ShippingFirms = _state.firms
	for company: Company in _state.all_companies():
		for key: String in company.firm_plans:
			var extra: Dictionary = (company.firm_plans[key] as Dictionary).get("extra_fleet", {})
			for model_id: String in extra:
				firms.add_fleet(int(key), model_id, int(extra[model_id]))


# --- Going public --------------------------------------------------------------------------

func ipo(company: Company) -> Dictionary:
	return ensure(company).ipo


## The banks that would take the company.
func banks_for(company: Company) -> Array:
	var value: float = _state.company_value(company)
	return BANK_ORDER.filter(func(id: String) -> bool: return value >= float(BANKS[id].min_value))


func ipo_choose_bank(company: Company, bank_id: String) -> String:
	var state := ipo(company)
	if str(state.get("step", "")) != "bank" or not BANKS.has(bank_id) or not bank_id in banks_for(company):
		return "Not now"
	var bank: Dictionary = BANKS[bank_id]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_state._values_kept.erase(company)
	var valuation: float = _state.company_value(company) * rng.randf_range(0.95, 1.15) * (1.0 + float(bank.reach) * 0.5)
	state.bank = bank_id
	state.valuation = valuation
	state.step = "terms"
	state.exchange = str(EXCHANGES.get(str(GameData.port_region(company.home_port).get("id", "")), "New York"))
	changed.emit()
	return ""


## The price range (a share) round the bank's valuation and the share of the company to sell (new shares).
func ipo_set_terms(company: Company, low: float, high: float, share: float) -> String:
	var state := ipo(company)
	if str(state.get("step", "")) != "terms":
		return "Not now"
	var mid := float(state.valuation) / float(ensure(company).total)
	state.low = clampf(low, mid * (1.0 - RANGE_WIDTH * 2.0), mid)
	state.high = clampf(high, state.low, mid * (1.0 + RANGE_WIDTH * 2.0))
	state.share = clampf(share, float(IPO_SHARE[0]), float(IPO_SHARE[1]))
	state.demand = 1.0 + float(BANKS[state.bank].reach) - (state.high / mid - 1.0) * 0.5
	state.meetings = 0
	state.step = "roadshow"
	state.next_meeting = _state.calendar_time()
	if company == _state.company:
		ActivityLog.add("The roadshow begins: %d investor meetings over the next weeks." % ROADSHOW_MEETINGS, ActivityLog.Kind.INFO)
	changed.emit()
	return ""


func _step_ipo(company: Company, now: int) -> void:
	var state := ipo(company)
	if state.is_empty() or company != _state.company:
		return
	match str(state.get("step", "")):
		"roadshow":
			if now >= int(state.next_meeting) and not bool(state.get("asking", false)):
				state.asking = true
				var meeting: Dictionary = MEETINGS[int(state.meetings) % MEETINGS.size()]
				ipo_event.emit(company, "meeting", {who = meeting.who, question = meeting.question, answers = (meeting.answers as Array).map(func(a: Array) -> String: return str(a[0]))})
		"listing":
			if now >= int(state.get("listing_day", 0)):
				_list(company)


## The player's answer to a roadshow question (0 to 2): demand moves by the answer and the CEO's traits.
func ipo_answer(company: Company, choice: int) -> void:
	var state := ipo(company)
	if str(state.get("step", "")) != "roadshow" or not bool(state.get("asking", false)):
		return
	var meeting: Dictionary = MEETINGS[int(state.meetings) % MEETINGS.size()]
	var answer: Array = (meeting.answers as Array)[clampi(choice, 0, 2)]
	var traits := Traits.of(company.ceo)
	var move := float(answer[1]) + (0.04 if "charismatic" in traits else 0.0) - (0.04 if "abrasive" in traits else 0.0) + (0.02 if "shrewd" in traits else 0.0) - (0.03 if "naive" in traits else 0.0)
	state.demand = clampf(float(state.demand) + move, 0.3, 2.0)
	state.meetings = int(state.meetings) + 1
	state.asking = false
	state.next_meeting = _state.calendar_time() + MEETING_DAYS * 86400
	if company == _state.company:
		ActivityLog.add("Roadshow: %s %s (demand now %d%%)." % [str(meeting.who).capitalize(), "warmed to that" if move > 0.0 else "weren't moved", roundi(float(state.demand) * 100.0)], ActivityLog.Kind.GOOD if move > 0.0 else ActivityLog.Kind.INFO)
	if int(state.meetings) >= ROADSHOW_MEETINGS:
		state.step = "listing"
		state.listing_day = _state.calendar_time() + MEETING_DAYS * 86400
	changed.emit()


## Listing day: the price settles in the range by demand (a pop over it when demand is hot), the new shares go to the public, the money comes in less the bank's fee.
func _list(company: Company) -> void:
	var shares := ensure(company)
	var state := ipo(company)
	var demand := float(state.demand)
	var settled := lerpf(float(state.low), float(state.high), clampf((demand - 0.7) / 0.6, 0.0, 1.0))
	var sold := roundi(float(shares.total) * float(state.share))
	var bank: Dictionary = BANKS[state.bank]
	var raised := roundi(settled * sold * (1.0 - float(bank.fee)))
	shares.holders.append({kind = "public", name = "the public (%s)" % str(state.exchange), count = sold, opinion = 0.0})
	shares.total = int(shares.total) + sold
	shares.listed = true
	shares.exchange = str(state.exchange)
	_state._add_money(company, raised)
	_state._record(null, "shares", -raised, company)
	_state._values_kept.erase(company)
	# The first day: hot demand pops the price over the range, cold demand sinks it; the sentiment is set so the price a share reads that.
	var pop := clampf((demand - 1.0) * 0.4, -0.3, 0.5)
	var first_day := settled * (1.0 + pop)
	shares.sentiment = clampf(first_day * float(shares.total) / maxf(float(_state.company_value(company)), 1.0), 0.3, 3.0)
	shares.ipo = {}
	shares.expected = maxf(float(shares.last_profit), _state.company_value(company) * 0.02) * 1.05
	if _state.news != null:
		_state.news.add("company", "%s lists in %s at %s a share, %s %d%% on the day" % [company.name, str(state.exchange), Fmt.money(roundi(settled)), "up" if pop >= 0.0 else "down", roundi(absf(pop) * 100.0)], {})
	ipo_event.emit(company, "listing", {exchange = state.exchange, settled = settled, first_day = first_day, pop = pop, raised = raised, sold = sold, fee = roundi(settled * sold * float(bank.fee)), bank = bank.name})
	if company == _state.company:
		ActivityLog.add("Listed in %s: %s raised at %s a share." % [str(state.exchange), Fmt.money(raised), Fmt.money(roundi(settled))], ActivityLog.Kind.GOOD)
	changed.emit()

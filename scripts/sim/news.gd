# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name News
extends RefCounted
## The world's news (DESIGN_LIVING_WORLD.md M1: the Intelligence screen's News
## tab and the ticker over the map): what the economy and the companies did,
## as headlines. For now (before the events system) three kinds: "market"
## moves (a good crossing SCARCE or GLUT of its usual price in a zone, or
## swinging SWING in a week: found when the history takes its weekly sample),
## "company" doings (the biggest sailing of each dispatch: ShippingFirms) and
## "world" figures (a monthly digest: the currencies that moved most, the
## busiest ports, the month's sailings). The player's own doings stay in the
## activity log, shown beside the news. Keeps the newest MOST, saved with the game.

signal added(item: Dictionary)

const MOST := 400
const SCARCE := 1.5
const GLUT := 0.6
const SWING := 0.12
## A market too small to make news: under this of a good's value used a day (US$).
const MIN_VALUE_A_DAY := 2000000.0
const MOVES_A_WEEK := 8
const CURRENCY_MOVE := 0.02

var _state: Node  # GameState
## Oldest first: {time (calendar unix), kind, text, about: {port, zone, good, firm, country}}.
var items: Array = []


func _init(state: Node) -> void:
	_state = state


func clear() -> void:
	items.clear()


func add(kind: String, text: String, about := {}) -> void:
	var item := {time = _state.calendar_time(), kind = kind, text = text, about = about}
	items.append(item)
	if items.size() > MOST:
		items.pop_front()
	added.emit(item)
	if Net.is_host():
		sync_new.append([int(item.time), kind, text, about])


## The items added since the host last sent them (Net), as saved rows.
var sync_new: Array = []


func take_sync() -> Array:
	var out := sync_new
	sync_new = []
	return out


## A joined game: the host's new items.
func apply_rows(rows: Array) -> void:
	for row: Array in rows:
		if row.size() >= 4:
			var item := {time = int(row[0]), kind = str(row[1]), text = str(row[2]), about = row[3]}
			items.append(item)
			if items.size() > MOST:
				items.pop_front()
			added.emit(item)

## The newest first, of the kinds given (all with none).
func latest(count: int, kinds := []) -> Array:
	var out := []
	for k in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[k]
		if kinds.is_empty() or item.kind in kinds:
			out.append(item)
			if out.size() >= count:
				break
	return out


# --- Finding the news ------------------------------------------------------------------

## The week's biggest market moves, between the history's two weekly slots.
func market_moves(world: WorldEconomy, history: WorldHistory, before_slot: int, after_slot: int) -> void:
	var g_count := world.goods.size()
	var cells := world.zones.size() * g_count
	var moves := []  # [score, cell, before, after]
	var tight := []  # [ratio, cell]: the week's dearest markets, for the digest.
	var gluts := []
	for i in cells:
		var g := i % g_count
		var value := world.use_for_price(i) * world._base[g]
		if value < MIN_VALUE_A_DAY or _maker_good(world.goods[g]):
			continue
		var before := history.weekly[before_slot * cells + i]
		var after := history.weekly[after_slot * cells + i]
		if after >= SCARCE:
			tight.append([after, i])
		elif after <= GLUT:
			gluts.append([after, i])
		var score := 0.0
		if after >= SCARCE and before < SCARCE:
			score = after
		elif after <= GLUT and before > GLUT:
			score = 1.0 / maxf(after, 0.05)
		elif absf(after - before) >= SWING:
			score = absf(after - before)
		if score > 0.0:
			moves.append([score * log(value / MIN_VALUE_A_DAY + 1.0), i, before, after])  # (A big market's move beats a small one's.)
	_week_digest(world, tight, gluts)
	if moves.is_empty():
		return
	moves.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for move: Array in moves.slice(0, MOVES_A_WEEK):
		var i: int = move[1]
		var z := i / g_count
		var g := i % g_count
		var zone: Dictionary = world.zones[z]
		var where := world.zone_label(z)
		var good := _good_name(world.goods[g])
		var before: float = move[2]
		var after: float = move[3]
		var text: String
		if after >= SCARCE and before < SCARCE:
			text = "%s scarce in %s: x%s of its usual price" % [_cap(good), where, Fmt.decimal(after, 2)]
		elif after <= GLUT and before > GLUT:
			text = "%s glut in %s: prices at x%s of usual" % [_cap(good), where, Fmt.decimal(after, 2)]
		elif after > before:
			text = "%s up %d%% in a week in %s" % [_cap(good), roundi((after / maxf(before, 0.01) - 1.0) * 100.0), where]
		else:
			text = "%s down %d%% in a week in %s" % [_cap(good), roundi((1.0 - after / maxf(before, 0.01)) * 100.0), where]
		add("market", text, {port = zone.main, zone = z, good = world.goods[g], country = zone.country})


## The week's digest: the three dearest markets and the three deepest gluts (there's always news).
func _week_digest(world: WorldEconomy, tight: Array, gluts: Array) -> void:
	var g_count := world.goods.size()
	var name := func(entry: Array) -> String:
		var i: int = entry[1]
		return "%s in %s (x%s)" % [_good_name(world.goods[i % g_count]), world.zone_label(i / g_count), Fmt.decimal(float(entry[0]), 2)]
	if not tight.is_empty():
		tight.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		var first: int = tight[0][1]
		add("market", "Tightest markets this week: " + ", ".join(PackedStringArray(tight.slice(0, 3).map(name))), {port = world.zones[first / g_count].main, zone = first / g_count, good = world.goods[first % g_count]})
	if not gluts.is_empty():
		gluts.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var first: int = gluts[0][1]
		add("market", "Deepest gluts this week: " + ", ".join(PackedStringArray(gluts.slice(0, 3).map(name))), {port = world.zones[first / g_count].main, zone = first / g_count, good = world.goods[first % g_count]})


## The month's figures: the currencies that moved most, the busiest ports and the sailings.
func world_figures(world: WorldEconomy, history: WorldHistory) -> void:
	var count := history.currency_monthly.size()
	if count >= 2:
		var now: PackedFloat32Array = history.currency_monthly[count - 1]
		var before: PackedFloat32Array = history.currency_monthly[count - 2]
		var movers := []
		for i in history.currency_ids.size():
			var change := now[i] / maxf(before[i], 0.01) - 1.0
			if absf(change) >= CURRENCY_MOVE:
				movers.append([absf(change), i, change])
		movers.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
		for mover: Array in movers.slice(0, 3):
			var id := history.currency_ids[mover[1]]
			var change: float = mover[2]
			var name := str(WorldEconomy.country(id).get("name", id))
			var entry: Dictionary = world.currency.get(id, {})
			var why := "a trade surplus" if float(entry.get("exports", 0.0)) >= float(entry.get("imports", 0.0)) else "a trade deficit"
			add("world", "%s's currency %s %d%% this month on %s" % [name, "strengthens" if change > 0.0 else "weakens", roundi(absf(change) * 100.0), why], {country = id})
	var firms: ShippingFirms = _state.firms
	if firms.month_sailings > 0:
		var calls: Array = firms.month_calls.keys()
		calls.sort_custom(func(a: String, b: String) -> bool: return int(firms.month_calls[a]) > int(firms.month_calls[b]))
		var parts := PackedStringArray()
		for port_id: String in calls.slice(0, 3):
			parts.append("%s (%d)" % [GameData.port_name(port_id), int(firms.month_calls[port_id])])
		add("world", "%s sailings this month; busiest ports %s" % [Fmt.thousands(firms.month_sailings), ", ".join(parts)], {port = calls[0] if not calls.is_empty() else ""})
		firms.month_sailings = 0
		firms.month_calls.clear()


## A sentence's first word: "Iron ore", but "LNG" as it is.
static func _cap(text: String) -> String:
	return text if text.is_empty() or text == text.to_upper() else text[0].to_upper() + text.substr(1)


## A maker's good (one make of car or boat): too small a market for the news.
static func _maker_good(good: String) -> bool:
	return bool(GameData.commodity(good).get("maker", false))


## A good's name in a sentence ("LNG" and such stay as they are).
static func _good_name(good: String) -> String:
	var name := str(GameData.commodity(good).get("name", good))
	return name if name == name.to_upper() else name.to_lower()


# --- Saving ------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {items = items.map(func(item: Dictionary) -> Array: return [int(item.time), item.kind, item.text, item.about])}


func from_dict(data: Dictionary) -> void:
	items.clear()
	for row: Array in data.get("items", []):
		if row.size() >= 4:
			items.append({time = int(row[0]), kind = str(row[1]), text = str(row[2]), about = row[3]})

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name WorldHistory
extends RefCounted
## The living world's price history (DESIGN_LIVING_WORLD.md M1, the
## Intelligence screen's charts): every zone's price of every good as a ratio
## to its base, sampled once a calendar week for the last WEEKS weeks (a ring)
## and once a calendar month for the whole game (kept for good: a month of
## samples is about 90 KB), with each country's currency strength by the
## month. Sampled at the end of the world's day (WorldEconomy._end_day()), and
## the News told of each week's and month's samples to find the moves.
## Saved beside the save as its own binary file (to_bytes(): a few MB), not
## in the save's JSON.

const WEEKS := 52

var _state: Node  # GameState
## WEEKS x cells (zone x good) of price / base, a ring: the slot last written is weekly_cursor.
var weekly := PackedFloat32Array()
var weekly_cursor := -1
var weekly_count := 0
var weekly_day := -1000000
## A PackedFloat32Array of every cell per month sampled, oldest first, and each one's month (years x 12 + month).
var monthly: Array = []
var months := PackedInt32Array()
var last_month := -1
## Each country's currency strength per month sampled (in currency_ids' order).
var currency_monthly: Array = []
var currency_ids := PackedStringArray()
var _cells := 0


func _init(state: Node) -> void:
	_state = state


func clear() -> void:
	weekly = PackedFloat32Array()
	weekly_cursor = -1
	weekly_count = 0
	weekly_day = -1000000
	monthly = []
	months = PackedInt32Array()
	last_month = -1
	currency_monthly = []
	currency_ids = PackedStringArray()
	_cells = 0


## The month index now (years x 12 + month).
func month_now() -> int:
	var date := Time.get_datetime_dict_from_unix_time(_state.calendar_time())
	return int(date.year) * 12 + int(date.month) - 1


## A week's and a month's samples when their time comes (the world's day just ended).
func sample(world: WorldEconomy, day: int) -> void:
	var cells := world.zones.size() * world.goods.size()
	if cells == 0:
		return
	if cells != _cells:
		clear()
		_cells = cells
		weekly.resize(WEEKS * cells)
		weekly.fill(1.0)
	if day - weekly_day >= 7:
		weekly_day = day
		var before := weekly_cursor
		weekly_cursor = (weekly_cursor + 1) % WEEKS
		weekly_count = mini(weekly_count + 1, WEEKS)
		_fill(world, weekly, weekly_cursor * cells)
		if before >= 0 and _state.news != null:
			_state.news.market_moves(world, self, before, weekly_cursor)
	var m := month_now()
	if m != last_month:
		var had := last_month >= 0
		last_month = m
		var row := PackedFloat32Array()
		row.resize(cells)
		_fill(world, row, 0)
		monthly.append(row)
		months.append(m)
		if currency_ids.is_empty():
			currency_ids = PackedStringArray(world.currency.keys())
		var strengths := PackedFloat32Array()
		strengths.resize(currency_ids.size())
		for i in currency_ids.size():
			strengths[i] = float((world.currency.get(currency_ids[i], {}) as Dictionary).get("strength", 1.0))
		currency_monthly.append(strengths)
		if had and _state.news != null:
			_state.news.world_figures(world, self)


func _fill(world: WorldEconomy, into: PackedFloat32Array, at: int) -> void:
	var g_count := world.goods.size()
	for i in _cells:
		into[at + i] = world.price[i] / maxf(world._base[i % g_count], 0.000001)


# --- Reading it --------------------------------------------------------------------

## A cell's weekly ratios, oldest first (weekly_count of them).
func weekly_series(cell: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if weekly_count == 0 or _cells == 0:
		return out
	out.resize(weekly_count)
	for k in weekly_count:
		var slot := posmod(weekly_cursor - (weekly_count - 1) + k, WEEKS)
		out[k] = weekly[slot * _cells + cell]
	return out


## A cell's monthly ratios over the last `count` months (all with 0), oldest first.
func monthly_series(cell: int, count := 0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var first := maxi(monthly.size() - count, 0) if count > 0 else 0
	for k in range(first, monthly.size()):
		out.append((monthly[k] as PackedFloat32Array)[cell])
	return out


## The world's weekly ratio of a good: its zones' averaged by their use.
func world_weekly_series(world: WorldEconomy, g: int) -> PackedFloat32Array:
	return _world_series(world, g, weekly_series_rows())


func world_monthly_series(world: WorldEconomy, g: int, count := 0) -> PackedFloat32Array:
	var first := maxi(monthly.size() - count, 0) if count > 0 else 0
	return _world_series(world, g, monthly.slice(first))


## The weekly ring as rows oldest first (each a view of one week's cells: [row array, offset]).
func weekly_series_rows() -> Array:
	var rows := []
	for k in weekly_count:
		rows.append([weekly, posmod(weekly_cursor - (weekly_count - 1) + k, WEEKS) * _cells])
	return rows


func _world_series(world: WorldEconomy, g: int, rows: Array) -> PackedFloat32Array:
	var g_count := world.goods.size()
	var weights := PackedFloat64Array()
	var total := 0.0
	for z in world.zones.size():
		var w := world.use_for_price(z * g_count + g)
		weights.append(w)
		total += w
	var out := PackedFloat32Array()
	for row in rows:
		var array: PackedFloat32Array = row[0] if row is Array else row
		var offset: int = row[1] if row is Array else 0
		var sum := 0.0
		for z in weights.size():
			sum += array[offset + z * g_count + g] * weights[z]
		out.append(sum / total if total > 0.0 else 1.0)
	return out


## A country's currency strength by the month, oldest first.
func currency_series(country_id: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var at := currency_ids.find(country_id)
	if at < 0:
		return out
	for row: PackedFloat32Array in currency_monthly:
		out.append(row[at])
	return out


## The month labels of the monthly samples (the last `count`), "Jan 2016".
func month_labels(count := 0) -> PackedStringArray:
	var out := PackedStringArray()
	var first := maxi(months.size() - count, 0) if count > 0 else 0
	for k in range(first, months.size()):
		out.append("%s %d" % [Fmt.month_name(posmod(months[k], 12)).substr(0, 3), months[k] / 12])
	return out


# --- Saving -------------------------------------------------------------------------

func to_bytes() -> PackedByteArray:
	return var_to_bytes({weekly = weekly, cursor = weekly_cursor, count = weekly_count, day = weekly_day, monthly = monthly, months = months,
		last_month = last_month, currency = currency_monthly, currency_ids = currency_ids, cells = _cells})


func from_bytes(bytes: PackedByteArray, world: WorldEconomy) -> void:
	clear()
	if bytes.is_empty():
		return
	var data: Variant = bytes_to_var(bytes)
	if typeof(data) != TYPE_DICTIONARY:
		return
	var cells := world.zones.size() * world.goods.size()
	if int(data.get("cells", 0)) != cells:
		return  # (From another world: the goods or zones have changed.)
	_cells = cells
	weekly = data.get("weekly", PackedFloat32Array())
	weekly_cursor = int(data.get("cursor", -1))
	weekly_count = int(data.get("count", 0))
	weekly_day = int(data.get("day", -1000000))
	monthly = data.get("monthly", [])
	months = data.get("months", PackedInt32Array())
	last_month = int(data.get("last_month", -1))
	currency_monthly = data.get("currency", [])
	currency_ids = data.get("currency_ids", PackedStringArray())


## Writes the history beside a save (path: the save's, with HISTORY_SUFFIX).
const HISTORY_SUFFIX := ".history"


static func write(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)


func load(path: String, world: WorldEconomy) -> void:
	if FileAccess.file_exists(path):
		from_bytes(FileAccess.get_file_as_bytes(path), world)
	else:
		clear()

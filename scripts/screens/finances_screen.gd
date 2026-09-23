extends Control
## Company totals (last 10 minutes and all time) and a sortable table of each
## ship's lifetime profit. Refreshes once a second while visible.

const REFRESH_SECONDS := 1.0
## Table columns: [title, sort key]. Money columns sort biggest first.
const COLUMNS := [
	["Ship", "name"], ["Model", "model"], ["Income", "income"], ["Fuel", "fuel"],
	["Repairs", "repair"], ["Recoveries", "recovery"], ["Profit", "profit"], ["Last 10 min", "recent"],
]
## Totals rows: [title, money kind, is a cost].
const TOTAL_ROWS := [
	["Cargo income", "income", false], ["Fuel", "fuel", true], ["Repairs", "repair", true],
	["Recoveries", "recovery", true], ["Ships bought", "bought", true], ["Ships sold", "sold", false],
]

var _sort_key := "profit"
var _sort_descending := true
var _clock := 0.0


func _ready() -> void:
	visibility_changed.connect(_refresh)
	GameState.ships_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	var recent := GameState.recent_finances()
	_fill_totals(recent.fleet)
	_fill_ship_table(recent.ships)


func _fill_totals(recent: Dictionary) -> void:
	_clear(%Totals)
	for title: String in ["", "Last 10 min", "All time"]:
		_add_label(%Totals, title, &"DimLabel")
	for row: Array in TOTAL_ROWS:
		_add_label(%Totals, row[0])
		var sign := -1.0 if row[2] else 1.0
		for source: Dictionary in [recent, GameState.totals]:
			_add_label(%Totals, Fmt.money(roundi(sign * float(source.get(row[1], 0.0)))))
	_add_label(%Totals, "Operating profit", &"HeaderLabel")
	for source: Dictionary in [recent, GameState.totals]:
		var profit := _operating_profit(source)
		_add_label(%Totals, Fmt.money(roundi(profit)), &"GainLabel" if profit >= 0.0 else &"ErrorLabel")


## Income minus fuel, repairs and recoveries (not buying or selling ships).
static func _operating_profit(source: Dictionary) -> float:
	return float(source.get("income", 0.0)) - float(source.get("fuel", 0.0)) \
		- float(source.get("repair", 0.0)) - float(source.get("recovery", 0.0))


func _fill_ship_table(recent_profit: Dictionary) -> void:
	_clear(%ShipTable)
	for column: Array in COLUMNS:
		var header := Button.new()
		header.flat = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.text = column[0]
		if column[1] == _sort_key:
			header.text += " ▼" if _sort_descending else " ▲"
		header.pressed.connect(_sort_by.bind(column[1]))
		%ShipTable.add_child(header)
	var rows := GameState.ships.map(func(ship: Ship) -> Dictionary:
		return {
			ship = ship,
			name = ship.name,
			model = String(ship.model().get("name", ship.model_id)),
			income = ship.ledger.income,
			fuel = ship.ledger.fuel,
			repair = ship.ledger.repair,
			recovery = ship.ledger.recovery,
			profit = ship.profit(),
			recent = float(recent_profit.get(ship.name, 0.0)),
		})
	rows.sort_custom(_row_before)
	for row: Dictionary in rows:
		_add_label(%ShipTable, row.name)
		_add_label(%ShipTable, row.model, &"DimLabel")
		_add_label(%ShipTable, Fmt.money(roundi(row.income)))
		for key: String in ["fuel", "repair", "recovery"]:
			_add_label(%ShipTable, Fmt.money(-roundi(row[key])))
		for key: String in ["profit", "recent"]:
			_add_label(%ShipTable, Fmt.money(roundi(row[key])), &"GainLabel" if row[key] >= 0.0 else &"ErrorLabel")
	%EmptyLabel.visible = rows.is_empty()


func _row_before(a: Dictionary, b: Dictionary) -> bool:
	var x: Variant = a[_sort_key]
	var y: Variant = b[_sort_key]
	if x is String:
		x = x.to_lower()
		y = y.to_lower()
	if x == y:
		return a.name.to_lower() < b.name.to_lower()
	return (x > y) if _sort_descending else (x < y)


## Clicking the sorted column flips its direction; text columns start A to Z,
## money columns biggest first.
func _sort_by(key: String) -> void:
	if key == _sort_key:
		_sort_descending = not _sort_descending
	else:
		_sort_key = key
		_sort_descending = key not in ["name", "model"]
	_refresh()


func _add_label(parent: Node, text: String, variation := &"") -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	parent.add_child(label)


static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

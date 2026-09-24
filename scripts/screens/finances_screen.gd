extends Control
## The "Keep in the bank" setting (money cargo purchases leave alone), company
## totals (last 10 minutes and all time), a card per canal the fleet
## has used (crossings, tolls and bonus XP), and a sortable table of each
## ship's lifetime profit. Refreshes once a second while visible.

const REFRESH_SECONDS := 1.0
## Text size for the totals, canal and ship tables (smaller than the theme's, so
## the eight-column ship table fits beside the activity log).
const TABLE_FONT_SIZE := 14
## Table columns: [title, sort key]. Money columns sort biggest first.
const COLUMNS := [
	["Ship", "name"], ["Model", "model"], ["Sales", "income"], ["Cargo", "cargo"], ["Fuel", "fuel"],
	["Repairs", "repair"], ["Tolls", "tolls"], ["Profit", "profit"], ["Last 10 min", "recent"],
]
## Totals rows: [title, money kind, is a cost].
const TOTAL_ROWS := [
	["Cargo sales", "income", false], ["Cargo bought", "cargo", true], ["Fuel", "fuel", true], ["Repairs", "repair", true],
	["Canal tolls", "tolls", true],
	["Ships bought", "bought", true], ["Ships sold", "sold", false], ["Hub upgrades", "hubs", true],
]
## Choices for "Keep in the bank" (0 = spend everything on cargo).
const BANK_RESERVES: Array[int] = [0, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000, 25000000, 50000000, 100000000]

var _sort_key := "profit"
var _sort_descending := true
var _clock := 0.0
var _canal_card := PanelContainer.new()
var _canal_label := Label.new()
var _bank_picker := OptionButton.new()


func _ready() -> void:
	_canal_card.theme_type_variation = &"CardPanel"
	_canal_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_canal_label.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE)
	_canal_card.add_child(_canal_label)
	$Scroll/Margin/Content/TotalsCard.add_sibling(_canal_card)
	_add_bank_row()
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
	_show_bank_reserve()
	var recent := GameState.recent_finances()
	_fill_totals(recent.fleet)
	_fill_canals()
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


## Cargo sales minus cargo bought, fuel, repairs and canal tolls (not buying or
## selling ships).
static func _operating_profit(source: Dictionary) -> float:
	return (float(source.get("income", 0.0)) - float(source.get("cargo", 0.0)) - float(source.get("fuel", 0.0))
		- float(source.get("repair", 0.0)) - float(source.get("tolls", 0.0)))


## Crossings, tolls and bonus XP for each canal the fleet has been through.
func _fill_canals() -> void:
	var lines := PackedStringArray()
	for canal in GameData.canals:
		var stats: Dictionary = GameState.canal_stats.get(canal.id, {})
		if stats.is_empty():
			continue
		lines.append("%s: %s crossings · tolls %s · bonus XP %s" % [canal.name, Fmt.thousands(int(stats.get("crossings", 0))),
			Fmt.money(-roundi(float(stats.get("tolls", 0.0)))), Fmt.thousands(roundi(float(stats.get("xp", 0.0))))])
	_canal_label.text = "\n".join(lines)
	_canal_card.visible = not lines.is_empty()


func _fill_ship_table(recent_profit: Dictionary) -> void:
	_clear(%ShipTable)
	for column: Array in COLUMNS:
		var header := Button.new()
		header.flat = true
		header.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE)
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
			cargo = ship.ledger.cargo,
			fuel = ship.ledger.fuel,
			repair = ship.ledger.repair,
			tolls = ship.ledger.tolls,
			profit = ship.profit(),
			recent = float(recent_profit.get(ship.name, 0.0)),
		})
	rows.sort_custom(_row_before)
	for row: Dictionary in rows:
		_add_label(%ShipTable, row.name)
		_add_label(%ShipTable, row.model, &"DimLabel")
		_add_label(%ShipTable, Fmt.money(roundi(row.income)))
		for key: String in ["cargo", "fuel", "repair", "tolls"]:
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
	if variation != &"HeaderLabel":
		label.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE)
	parent.add_child(label)


static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## "Keep in the bank: [amount]" above the totals, with a note on what it does.
func _add_bank_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var title := Label.new()
	title.text = "Keep in the bank"
	row.add_child(title)
	for amount in BANK_RESERVES:
		_bank_picker.add_item("Nothing" if amount == 0 else Fmt.money(amount))
		_bank_picker.set_item_metadata(_bank_picker.item_count - 1, amount)
	_bank_picker.item_selected.connect(func(index: int) -> void:
		GameState.set_bank_reserve(int(_bank_picker.get_item_metadata(index))))
	row.add_child(_bank_picker)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "Ships won't spend this on cargo (fuel and repairs still can)."
	row.add_child(hint)
	$Scroll/Margin/Content.add_child(row)
	$Scroll/Margin/Content.move_child(row, 0)


## Shows the current setting (a saved amount not in the list is added to it).
func _show_bank_reserve() -> void:
	for i in _bank_picker.item_count:
		if int(_bank_picker.get_item_metadata(i)) == GameState.bank_reserve:
			_bank_picker.select(i)
			return
	_bank_picker.add_item(Fmt.money(GameState.bank_reserve))
	_bank_picker.set_item_metadata(_bank_picker.item_count - 1, GameState.bank_reserve)
	_bank_picker.select(_bank_picker.item_count - 1)

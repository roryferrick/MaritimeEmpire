extends Control
## The "Keep in the bank" setting (money cargo purchases leave alone), company
## totals (last 10 minutes and all time), a card per canal the fleet
## has used (crossings, tolls and bonus XP), and a sortable table of each
## ship's lifetime profit, grouped by ship line (each with a total row); click a
## ship's name to open its popup.
## Refreshes once a second while visible.

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
	["Ships bought", "bought", true], ["Ships sold", "sold", false], ["Hub upgrades", "hubs", true], ["Mega upgrades", "mega", true],
]
## Ship table groups, in shop order: [title, ship_models.json category].
const CATEGORIES := [["Container ships", "container"], ["Ore carriers", "ore"], ["Grain carriers", "grain"],
	["Livestock carriers", "livestock"], ["Tankers", "tanker"], ["Vehicle carriers", "vehicles"], ["Recovery boats", "recovery"]]
## Money columns summed in each group's total row.
const MONEY_COLUMNS: Array[String] = ["income", "cargo", "fuel", "repair", "tolls", "profit", "recent"]
## Each group's rows sit on a faint band of its ship line's color.
const BAND_TINT := 0.1
const BAND_MARGIN := 2.0
## Choices for "Keep in the bank" (0 = spend everything on cargo).
const BANK_RESERVES: Array[int] = [0, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000, 25000000, 50000000, 100000000]

var _sort_key := "profit"
var _sort_descending := true
var _clock := 0.0
var _canal_card := PanelContainer.new()
var _canal_label := Label.new()
var _bank_picker := OptionButton.new()
## Per ship line in the table: [its total row's first label, its last ship's
## first label, the line's color], for the tinted band drawn behind its rows.
var _bands: Array = []


func _ready() -> void:
	_canal_card.theme_type_variation = &"CardPanel"
	_canal_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_canal_label.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE)
	_canal_card.add_child(_canal_label)
	$Scroll/Margin/Content/TotalsCard.add_sibling(_canal_card)
	_add_bank_row()
	%ShipTable.draw.connect(_draw_bands)
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
	_bands.clear()
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
	for category: Array in CATEGORIES:
		var group := rows.filter(func(row: Dictionary) -> bool: return row.ship.model().get("category", "") == category[1])
		if group.is_empty():
			continue
		var total := {name = category[0], model = "%d ship%s" % [group.size(), "" if group.size() == 1 else "s"]}
		for key: String in MONEY_COLUMNS:
			total[key] = group.reduce(func(sum: float, row: Dictionary) -> float: return sum + float(row[key]), 0.0)
		var color := GameData.category_color(category[1])
		var first: Label = _add_row(total, color)[0]
		var last := first
		for row: Dictionary in group:
			last = _add_row(row)[0]
		_bands.append([first, last, color])
	%EmptyLabel.visible = rows.is_empty()
	%ShipTable.queue_redraw()


## One table row: name, model, sales, costs (as negatives), profit and last 10
## min. A category total row (title_color set) has its name in the line's color
## and its figures in a bigger font.
func _add_row(row: Dictionary, title_color := Color.TRANSPARENT) -> Array[Label]:
	var is_total := title_color.a > 0.0
	var cells: Array[Label] = []
	cells.append(_add_label(%ShipTable, row.name))
	cells.append(_add_label(%ShipTable, row.model, &"DimLabel"))
	cells.append(_add_label(%ShipTable, Fmt.money(roundi(row.income))))
	for key: String in ["cargo", "fuel", "repair", "tolls"]:
		cells.append(_add_label(%ShipTable, Fmt.money(-roundi(row[key]))))
	for key: String in ["profit", "recent"]:
		cells.append(_add_label(%ShipTable, Fmt.money(roundi(row[key])), &"GainLabel" if row[key] >= 0.0 else &"ErrorLabel"))
	if is_total:
		cells[0].add_theme_color_override(&"font_color", title_color)
		for cell in cells:
			cell.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE + 2)
	elif row.has("ship"):
		var name_cell := cells[0]
		name_cell.mouse_filter = Control.MOUSE_FILTER_STOP
		name_cell.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		name_cell.tooltip_text = "Open %s" % row.name
		name_cell.gui_input.connect(_on_ship_name_input.bind(row.ship, name_cell))
	return cells


## Clicking a ship's name opens its popup there (the table redraws every
## second, so it stays where the name was when clicked).
func _on_ship_name_input(event: InputEvent, ship: Ship, cell: Label) -> void:
	var click := event as InputEventMouseButton
	if not click or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var rect := cell.get_global_rect()
	var anchor := Vector2(rect.position.x + minf(rect.size.x, 120.0) / 2.0, rect.get_center().y)
	PopupHost.find(self).show_ship(ship, func() -> Vector2: return anchor, rect.size.y / 2.0 + 6.0)


## A faint band of each ship line's color behind its rows (its total row down to
## its last ship), drawn under the table's labels.
func _draw_bands() -> void:
	var table: GridContainer = %ShipTable
	for band: Array in _bands:
		var first: Label = band[0]
		var last: Label = band[1]
		if not is_instance_valid(first) or not is_instance_valid(last):
			continue
		var top := first.position.y - BAND_MARGIN
		var bottom := last.position.y + last.size.y + BAND_MARGIN
		table.draw_rect(Rect2(-BAND_MARGIN * 2.0, top, table.size.x + BAND_MARGIN * 4.0, bottom - top), Color(band[2], BAND_TINT))


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


func _add_label(parent: Node, text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if variation != &"HeaderLabel":
		label.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE)
	parent.add_child(label)
	return label


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

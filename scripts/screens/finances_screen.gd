# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## Two pages (tabs at the top): Compare companies (every company in the game
## side by side), and Your company: the "Keep in the bank" setting (money cargo purchases leave alone), company
## totals (last 10 minutes and all time), everything the fleet has delivered
## (by unit and commodity), a card for the canals the fleet has used
## (crossings, tolls and bonus XP), and a sortable table of each ship's
## lifetime profit, grouped by ship line (each with a total row); click a
## ship's name to open its popup.
## Refreshes once a second while visible.

const REFRESH_SECONDS := 1.0
## Text size for the totals, canal and ship tables (smaller than the theme's, so
## the eight-column ship table fits beside the activity log).
const TABLE_FONT_SIZE := 14
## The ship table's name and model columns (px; longer names are cut short with "...").
const NAME_WIDTH := 130.0
const MODEL_WIDTH := 110.0
## Space between the cards side by side (the same as between the rows of cards).
const CARD_GAP := 12
## Table columns: [title, sort key]. Money columns sort biggest first.
const COLUMNS := [
	["Ship", "name"], ["Model", "model"], ["Sales", "income"], ["Cargo", "cargo"], ["Fuel", "fuel"],
	["Repairs", "repair"], ["Tolls & fees", "tolls"], ["Wages", "wages"], ["Profit", "profit"], ["Last 10 min", "recent"],
]
## Totals rows: [title, money kind, is a cost].
const TOTAL_ROWS := [
	["Cargo sales", "income", false], ["Cargo bought", "cargo", true], ["Fuel", "fuel", true], ["Repairs", "repair", true],
	["Canal tolls", "tolls", true], ["Port fees", "port_fees", true], ["Crew wages", "wages", true], ["Loan interest", "interest", true],
	["Ships bought", "bought", true], ["Ships sold", "sold", false], ["Hub upgrades", "hubs", true], ["Ship upgrades", "upgrades", true], ["Mega upgrades", "mega", true], ["Logo changes", "logo", true], ["Cruise supplies", "supplies", true],
	["Farm land bought", "land", true], ["Farm land sold", "land_sold", false], ["Farm costs (planting, herds, wages, upgrades)", "farms", true], ["Farm store sales", "farm_sales", false],
	["Factories (building, upkeep)", "factories", true], ["Factory stock sales", "factory_sales", false],
]
## Ship table groups, in shop order: [title, ship_models.json category].
const CATEGORIES := [["Container ships", "container"], ["Ore carriers", "ore"], ["Grain carriers", "grain"],
	["Livestock carriers", "livestock"], ["Fresh produce carriers", "produce"], ["Tankers", "tanker"], ["Car carriers", "vehicles"], ["Boat carriers", "boat_carriers"], ["Recovery boats", "recovery"], ["Tugs", "tug"], ["Icebreakers", "icebreaker"], ["Fishing boats", "fishing"], ["Crabbing boats", "crabbing"], ["Seafood carriers", "seafood"]]
## Money columns summed in each group's total row.
const MONEY_COLUMNS: Array[String] = ["income", "cargo", "fuel", "repair", "tolls", "wages", "profit", "recent"]
## The Delivered card's heading for each markets.json unit.
const DELIVERED_UNITS := {container = "Containers", ton = "Tons", pallet = "Pallets", head = "Head of livestock", vehicle = "Vehicles", boat = "Boats"}
## Each group's rows sit on a faint band of its ship line's color.
const BAND_TINT := 0.1
const BAND_MARGIN := 2.0
## The Compare companies table's columns, and how big (px) each company's CEO's face is in it.
const COMPARE_COLUMNS: Array[String] = ["#", "Company", "Type", "Ratings", "Level", "Money", "Ships", "Hubs", "Profit (10 min)", "Profit (all) ▼", "Delivered"]
const CEO_FACE_SIZE := 34.0
## How big (px) the company type's icon is in the Type column (CompanyTypeIcon).
const TYPE_ICON_SIZE := 24.0
## How big (px) each company's logo is beside its name there (CompanyLogo).
const LOGO_SIZE := 26.0
## Choices for "Keep in the bank" (0 = spend everything on cargo).
const BANK_RESERVES: Array[int] = [0, 100000, 250000, 500000, 1000000, 2500000, 5000000, 10000000, 25000000, 50000000, 100000000]

var _sort_key := "profit"
var _sort_descending := true
var _clock := 0.0
var _delivered_card := PanelContainer.new()
var _delivered_grid := GridContainer.new()
var _canal_card := PanelContainer.new()
var _canal_label := Label.new()
var _bank_picker := OptionButton.new()
## The loan row (see _add_loan_row()).
var _loan_label := Label.new()
var _borrow_button := Button.new()
var _repay_button := Button.new()
## The Compare companies page (see _add_tabs()), and whether it's showing.
var _compare_card := PanelContainer.new()
var _compare_grid := GridContainer.new()
var _comparing := false
## Per ship line in the table: [its total row's first label, its last ship's
## first label, the line's color], for the tinted band drawn behind its rows.
var _bands: Array = []


func _ready() -> void:
	_canal_card.theme_type_variation = &"CardPanel"
	_canal_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_canal_label.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE)
	_canal_card.add_child(_canal_label)
	# The Delivered card sits beside the totals.
	var totals_card: Control = $Scroll/Margin/Content/TotalsCard
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", CARD_GAP)
	totals_card.add_sibling(row)
	totals_card.reparent(row)
	totals_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_delivered_card.theme_type_variation = &"CardPanel"
	_delivered_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_delivered_grid.columns = 2
	_delivered_grid.add_theme_constant_override(&"h_separation", 24)
	_delivered_card.add_child(_delivered_grid)
	row.add_child(_delivered_card)
	row.add_sibling(_canal_card)
	_add_bank_row()
	_add_loan_row()
	_add_logo_row()
	_add_tabs()
	%ShipTable.columns = COLUMNS.size()  # (One per column, however many there are.)
	%ShipTable.draw.connect(_draw_bands)
	visibility_changed.connect(_refresh)
	GameState.ships_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(delta)
	MapView._prof("proc.finances_screen", t_x)

func _process_timed(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	if _comparing:
		_fill_comparison()
		return
	_show_bank_reserve()
	_show_loan()
	var recent := GameState.recent_finances()
	_fill_totals(recent.fleet)
	_fill_delivered()
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


## Cargo sales minus cargo bought, fuel, repairs, canal tolls, port fees, crew wages and loan interest (not buying or
## selling ships).
static func _operating_profit(source: Dictionary) -> float:
	return (float(source.get("income", 0.0)) - float(source.get("cargo", 0.0)) - float(source.get("fuel", 0.0))
		- float(source.get("repair", 0.0)) - float(source.get("tolls", 0.0)) - float(source.get("port_fees", 0.0)) - float(source.get("wages", 0.0))
		- float(source.get("interest", 0.0)))


## Everything the fleet has delivered, all time: a total for each unit
## (containers, tons, head, vehicles) with each commodity carried in it under
## it (when there are several). Containers include those from before
## deliveries were counted by commodity (GameState.earlier_containers).
func _fill_delivered() -> void:
	_clear(_delivered_grid)
	_add_label(_delivered_grid, "Delivered", &"DimLabel")
	_add_label(_delivered_grid, "")
	var groups := {}  # unit -> [[commodity name, units], ...], in markets.json order
	for commodity: Dictionary in GameData.commodities:
		var units := int(GameState.delivered.get(commodity.id, 0))
		if units > 0:
			groups.get_or_add(commodity.unit, []).append([commodity.name, units])
	if GameState.earlier_containers > 0:
		groups.get_or_add("container", []).append(["Earlier, not split by cargo", GameState.earlier_containers])
	if groups.is_empty():
		_add_label(_delivered_grid, "Nothing yet")
		_add_label(_delivered_grid, "")
		return
	for unit: String in groups:
		var total := 0
		for entry: Array in groups[unit]:
			total += int(entry[1])
		_add_label(_delivered_grid, DELIVERED_UNITS.get(unit, unit.capitalize()))
		_add_label(_delivered_grid, Fmt.thousands(total)).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if groups[unit].size() < 2:
			continue  # One commodity: its total says it all.
		for entry: Array in groups[unit]:
			_add_label(_delivered_grid, "    %s" % entry[0], &"DimLabel")
			_add_label(_delivered_grid, Fmt.thousands(int(entry[1])), &"DimLabel").horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


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
		header.add_theme_font_override(&"font", get_theme_default_font())  # (In the text's font, like the table: Cinzel would widen its columns.)
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		header.text = column[0]
		if column[1] == _sort_key:
			header.text += " ▼" if _sort_descending else " ▲"
		header.pressed.connect(_sort_by.bind(column[1]))
		%ShipTable.add_child(header)
	var rows := GameState.fleet().map(func(ship: Ship) -> Dictionary:
		return {
			ship = ship,
			name = ship.name,
			model = String(ship.model().get("name", ship.model_id)),
			income = ship.ledger.income,
			cargo = ship.ledger.cargo,
			fuel = ship.ledger.fuel,
			repair = ship.ledger.repair,
			tolls = ship.ledger.tolls + ship.ledger.port_fees,
			wages = ship.ledger.wages,
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
	cells.append(_fit(_add_label(%ShipTable, row.name), NAME_WIDTH))
	cells.append(_fit(_add_label(%ShipTable, row.model, &"DimLabel"), MODEL_WIDTH))
	cells.append(_add_money(roundi(row.income)))
	for key: String in ["cargo", "fuel", "repair", "tolls", "wages"]:
		cells.append(_add_money(-roundi(row[key])))
	for key: String in ["profit", "recent"]:
		cells.append(_add_money(roundi(row[key]), &"GainLabel" if row[key] >= 0.0 else &"ErrorLabel"))
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


## A name cell kept to a width so the table fits the screen: a longer name ends
## in "..." (whole in its tooltip).
func _fit(label: Label, width: float) -> Label:
	label.custom_minimum_size.x = width
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if label.tooltip_text.is_empty():
		label.tooltip_text = label.text
	return label


func _add_label(parent: Node, text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if variation != &"HeaderLabel":
		label.add_theme_font_size_override(&"font_size", TABLE_FONT_SIZE)
	parent.add_child(label)
	return label


## A ship table money cell, shortened ("$23.1B") so the table fits the screen,
## with the exact amount on hover.
func _add_money(amount: int, variation := &"") -> Label:
	var label := _add_label(%ShipTable, Fmt.money_short(amount), variation)
	label.tooltip_text = Fmt.money(amount)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


## Two pages, picked by tabs at the top: Your company (everything below) and
## Compare companies (a table of every company in the game).
func _add_tabs() -> void:
	var content: Control = $Scroll/Margin/Content
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override(&"separation", 6)
	var group := ButtonGroup.new()
	for page: Array in [["Your company", false], ["Compare companies", true]]:
		var tab := Button.new()
		tab.text = page[0]
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = not page[1]
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_show_page.bind(page[1]))
		tabs.add_child(tab)
	content.add_child(tabs)
	content.move_child(tabs, 0)
	_compare_card.theme_type_variation = &"CardPanel"
	_compare_card.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	_compare_card.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Companies"
	box.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "Every company in this game. Operating profit is cargo sales less cargo, fuel, repairs, tolls, port fees and wages."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 160
	box.add_child(hint)
	_compare_grid.columns = COMPARE_COLUMNS.size()
	_compare_grid.add_theme_constant_override(&"h_separation", 20)
	_compare_grid.add_theme_constant_override(&"v_separation", 4)
	box.add_child(_compare_grid)
	content.add_child(_compare_card)


func _show_page(compare: bool) -> void:
	_comparing = compare
	for child: Control in $Scroll/Margin/Content.get_children():
		if child != _compare_card and child.get_index() > 0:
			child.visible = not compare
	_compare_card.visible = compare
	_refresh()


## A row per company, ranked by operating profit all time (the most first),
## numbered: its CEO's face (their name on hover), its logo and
## its name (in its color; this player's marked), the company type it started
## as (icon and name; every type it has on hover), level, money, ships, hubs,
## operating profit over the last 10 minutes and all time, and units
## delivered.
func _fill_comparison() -> void:
	_clear(_compare_grid)
	for column: String in COMPARE_COLUMNS:
		_add_label(_compare_grid, column, &"DimLabel")
	var companies := GameState.all_companies().duplicate()
	var all_time := {}
	for each: Company in companies:
		all_time[each] = _operating_profit(each.totals)
	companies.sort_custom(func(a: Company, b: Company) -> bool: return float(all_time[a]) > float(all_time[b]))
	for rank in companies.size():
		var each: Company = companies[rank]
		_add_label(_compare_grid, "%d" % (rank + 1), &"DimLabel")
		# Its CEO's face, then its name.
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override(&"separation", 8)
		_compare_grid.add_child(cell)
		var face := Portrait.new(each.ceo, true)
		face.custom_minimum_size = Vector2.ONE * CEO_FACE_SIZE
		face.tooltip_text = str(each.ceo.get("name", ""))
		cell.add_child(face)
		var logo := CompanyLogo.of(each)
		logo.custom_minimum_size = Vector2.ONE * LOGO_SIZE
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(logo)
		var name := _add_label(cell, each.name + ("  (you)" if each == GameState.company else "  (AI · %s)" % RivalAI.LEVEL_NAMES.get(each.ai, "") if each.is_ai() else ""))
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name.add_theme_color_override(&"font_color", GameState.company_color_value(each.color))
		_compare_grid.add_child(_type_cell(each))
		_compare_grid.add_child(_ratings_cell(each))
		_add_label(_compare_grid, str(each.level()))
		_add_label(_compare_grid, Fmt.money(each.money))
		_add_label(_compare_grid, str(GameState.fleet(each).size()))
		_add_label(_compare_grid, str(maxi(each.hubs.size() - 1, 0)))
		for source: Dictionary in [GameState.recent_finances(each).fleet, each.totals]:
			var profit := _operating_profit(source)
			_add_label(_compare_grid, Fmt.money(roundi(profit)), &"GainLabel" if profit >= 0.0 else &"ErrorLabel")
		var units := 0
		for commodity: String in each.delivered:
			units += int(each.delivered[commodity])
		_add_label(_compare_grid, Fmt.short(units + each.earlier_containers))


## A company's stars in each type it runs (Ratings): its icon and the stars,
## the full stars on hover.
func _ratings_cell(each: Company) -> Control:
	var cell := GridContainer.new()  # (Three types to a row, so six fit the table.)
	cell.columns = 6
	cell.add_theme_constant_override(&"h_separation", 4)
	var tips := PackedStringArray()
	for type_id: String in Ratings.rated_types(each):
		var stars := GameState.ratings.stars(each, type_id)
		var icon := CompanyTypeIcon.new(type_id)
		icon.custom_minimum_size = Vector2.ONE * 18.0
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(icon)
		var label := _add_label(cell, "%.1f★" % stars)
		label.add_theme_font_size_override(&"font_size", 13)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tips.append("%s: %.1f of 5 stars" % [Progression.type_name(type_id), stars])
	cell.tooltip_text = "\n".join(tips)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	return cell


## A company's starting type in the comparison: its icon and name, with every
## type it has (and the level it took each at) on hover.
func _type_cell(each: Company) -> Control:
	var cell := HBoxContainer.new()
	cell.add_theme_constant_override(&"separation", 6)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var icon := CompanyTypeIcon.new(each.start_type())
	icon.custom_minimum_size = Vector2.ONE * TYPE_ICON_SIZE
	cell.add_child(icon)
	var label := _add_label(cell, Progression.type_name(each.start_type()))
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override(&"font_color", CompanyTypeIcon.type_color(each.start_type()))
	var lines := PackedStringArray()
	for type_id: String in each.company_types:
		lines.append("%s (from level %d)" % [Progression.type_name(type_id), each.type_level(type_id)])
	cell.tooltip_text = "Every company type" if each.all_types() else "Company types: " + ", ".join(lines)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = cell.tooltip_text
	return cell


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
	_wrap(hint)
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


## The loan row, under Keep in the bank: what's owed, and buttons to borrow or
## pay back a step (game_config loans) at a time.
func _add_loan_row() -> void:
	var settings := GameState.loan_settings()
	var step := int(settings.get("step", 1000000))
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var title := Label.new()
	title.text = "Loan"
	row.add_child(title)
	row.add_child(_loan_label)
	_borrow_button.text = "Borrow %s" % Fmt.money(step)
	_borrow_button.pressed.connect(func() -> void:
		GameState.take_loan()
		_show_loan())
	row.add_child(_borrow_button)
	_repay_button.text = "Pay back %s" % Fmt.money(step)
	_repay_button.pressed.connect(func() -> void:
		GameState.repay_loan()
		_show_loan())
	row.add_child(_repay_button)
	var hint := Label.new()
	hint.theme_type_variation = &"DimLabel"
	hint.text = "Up to %s, at %s%% a year, paid every %d days with the crew's wages." % [Fmt.money(int(settings.get("max", 10000000))),
		str(snappedf(float(settings.get("yearly_interest", 0.08)) * 100.0, 0.1)).trim_suffix(".0"), int(GameData.config.get("crew", {}).get("period_days", 14))]
	_wrap(hint)
	row.add_child(hint)
	$Scroll/Margin/Content.add_child(row)
	$Scroll/Margin/Content.move_child(row, 1)


func _show_loan() -> void:
	var loan := GameState.company.loan
	_loan_label.text = "Nothing owed" if loan == 0 else "%s owed (%s interest a payday)" % [Fmt.money(loan), Fmt.money(GameState.loan_interest(loan))]
	var borrow_error := GameState.take_loan_error()
	_borrow_button.disabled = not borrow_error.is_empty()
	_borrow_button.tooltip_text = borrow_error
	var repay_error := GameState.repay_loan_error()
	_repay_button.disabled = not repay_error.is_empty()
	_repay_button.tooltip_text = repay_error


## A note beside a row's controls that wraps onto more lines rather than
## widening the page (which has no sideways scrolling: it must fit beside the
## activity log or chat).
static func _wrap(label: Label) -> void:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size.x = 160


## "Company logo" under the loan row: the logo, and Change logo (LogoDialog,
## for GameState.LOGO_CHANGE_COST).
func _add_logo_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var title := Label.new()
	title.text = "Company logo"
	row.add_child(title)
	var logo := CompanyLogo.of(GameState.company)
	logo.custom_minimum_size = Vector2.ONE * 40.0
	row.add_child(logo)
	var change := Button.new()
	change.text = "Change logo: %s" % Fmt.money(GameState.LOGO_CHANGE_COST)
	change.pressed.connect(func() -> void: GameRoot.find(self).add_child(LogoDialog.new()))
	row.add_child(change)
	GameState.logo_changed.connect(func() -> void:
		logo.logo = GameState.company.logo
		logo.queue_redraw())
	$Scroll/Margin/Content.add_child(row)
	$Scroll/Margin/Content.move_child(row, 2)

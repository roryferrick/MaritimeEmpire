# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name IntelligenceScreen
extends Control
## The Intelligence page over the map (DESIGN_LIVING_WORLD.md M1; it took the
## Markets page's place, 2026-10-22): what the living world is doing, in tabs.
## Countries: every country's people, GDP, currency, trade balance and tariff,
## sortable, each opening its page (zones and ports, people by stratum, what
## it makes and uses most, its currency's history, the firms based there).
## Companies: the shipping firms and the producers, sortable, each opening
## its page. Markets: a good at a time, the cheapest ports to buy it and the
## best to sell it and the best trades (as the Markets page had), and every
## zone's price of it with its days of cover and a year's sparkline. Charts: a
## good's price in a zone or the world over a year by the week, or 5 years, 10
## years or the whole game by the month (WorldHistory). News: the world's
## headlines (News) by kind, beside the player's own activity log. Refreshes
## every few seconds while open.

const REFRESH_SECONDS := 3.0
const LIST_SIZE := 10
## "Best short trades" only pairs ports at most this far apart by sea.
const SHORT_TRADE_NM := 800.0
const FONT_SIZE := 14
const SMALL_FONT := 12
const TABS := [["countries", "Countries"], ["companies", "Companies"], ["markets", "Markets"], ["charts", "Charts"], ["news", "News"]]
const COUNTRY_COLUMNS := [["name", "Country"], ["population", "People"], ["gdp_usd", "GDP"], ["gdp_per_head", "GDP a head"], ["currency", "Currency"], ["balance", "Trade balance"], ["tariff", "Tariff"], ["firms", "Firms"], ["plants", "Plants"]]
const FIRM_COLUMNS := [["name", "Firm"], ["country", "Based in"], ["home", "Home port"], ["ships", "Ships"], ["at_sea", "At sea"], ["money", "Earned"], ["carried", "Carried"]]
const PRODUCER_COLUMNS := [["name", "Company"], ["country", "From"], ["trade", "Trade"], ["plants", "Plants"], ["output", "Output a year"]]
const RANGES := [["year", "A year (weekly)", 0], ["five", "5 years", 60], ["ten", "10 years", 120], ["life", "The whole game", -1]]
const ZONE_ROWS := 40
const NEWS_SHOWN := 60

var _tab := "markets"
var _tabs := HBoxContainer.new()
var _body := VBoxContainer.new()
var _clock := 0.0
## What's picked on each tab.
var _country := ""
var _country_sort := "population"
var _country_descending := true
var _company_kind := "firms"
var _company := -1
var _company_sort := "ships"
var _good := ""
var _chart_good := ""
var _chart_zone := -1  # -1: the world.
var _chart_range := "year"
var _news_kinds := {market = true, company = true, world = true}
var _goods_picker: OptionButton = null
var _built_tab := ""


func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	scroll.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	margin.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 16)
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Intelligence"
	header.add_child(title)
	_tabs.add_theme_constant_override(&"separation", 6)
	header.add_child(_tabs)
	var group := ButtonGroup.new()
	for tab: Array in TABS:
		var button := Button.new()
		button.text = tab[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = tab[0] == _tab
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(show_tab.bind(tab[0]))
		_tabs.add_child(button)
	_body.add_theme_constant_override(&"separation", 12)
	content.add_child(_body)
	visibility_changed.connect(_refresh)
	_refresh()


## Opens a tab (from the ticker, the port popup...).
func show_tab(id: String) -> void:
	if id.is_empty() or not TABS.any(func(tab: Array) -> bool: return tab[0] == id):
		return
	_tab = id
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).button_pressed = TABS[i][0] == id
	_refresh()


## Opens the Charts tab on a good in a zone (-1 the world).
func show_chart(good: String, zone := -1) -> void:
	_chart_good = good
	_chart_zone = zone
	show_tab("charts")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_SECONDS and _tab in ["markets", "charts", "news"]:  # (The country and company tables are big: built when opened or sorted.)
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	var t_x := Time.get_ticks_usec()
	_clear(_body)
	match _tab:
		"countries":
			_build_countries()
		"companies":
			_build_companies()
		"markets":
			_build_markets()
		"charts":
			_build_charts()
		"news":
			_build_news()
	MapView._prof("proc.intelligence", t_x)


# --- Countries ------------------------------------------------------------------------

func _build_countries() -> void:
	var world: WorldEconomy = GameState.world
	if world.zones.is_empty():
		_body.add_child(_dim("The world is still being made."))
		return
	if not _country.is_empty():
		_body.add_child(_country_card(_country))
	var rows := []
	var firms_by_country := {}
	for firm: Dictionary in GameState.firms.firms:
		firms_by_country[firm.country] = int(firms_by_country.get(firm.country, 0)) + 1
	var plants_by_country := {}
	for plant: Dictionary in world.producers.plants:
		plants_by_country[plant.country] = int(plants_by_country.get(plant.country, 0)) + 1
	for country: Dictionary in WorldEconomy.data("countries").get("countries", []):
		var id := str(country.id)
		var entry: Dictionary = world.currency.get(id, {})
		var exports := float(entry.get("exports", 0.0))
		var imports := float(entry.get("imports", 0.0))
		rows.append({id = id, name = str(country.name), population = float(country.get("population", 0)), gdp_usd = float(country.get("gdp_usd", 0)),
			gdp_per_head = float(country.get("gdp_per_head", 0)), currency = float(entry.get("strength", 1.0)), balance = exports - imports,
			tariff = float(country.get("tariff", 0.0)), firms = int(firms_by_country.get(id, 0)), plants = int(plants_by_country.get(id, 0))})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var x: Variant = a[_country_sort]
		var y: Variant = b[_country_sort]
		if x is String:
			return (x.to_lower() > y.to_lower()) if _country_descending else (x.to_lower() < y.to_lower())
		if x == y:
			return a.name < b.name
		return (x > y) if _country_descending else (x < y))
	var grid := GridContainer.new()
	grid.columns = COUNTRY_COLUMNS.size()
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 2)
	for column: Array in COUNTRY_COLUMNS:
		var head := Button.new()
		head.flat = true
		head.text = column[1] + (" ▼" if column[0] == _country_sort and _country_descending else (" ▲" if column[0] == _country_sort else ""))
		head.add_theme_font_size_override(&"font_size", FONT_SIZE)
		head.pressed.connect(func() -> void:
			if _country_sort == column[0]:
				_country_descending = not _country_descending
			else:
				_country_sort = column[0]
				_country_descending = column[0] != "name"
			_refresh())
		grid.add_child(head)
	for row: Dictionary in rows:
		var name := Button.new()
		name.flat = true
		name.text = row.name
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.add_theme_font_size_override(&"font_size", FONT_SIZE)
		name.pressed.connect(func() -> void:
			_country = row.id
			_refresh())
		grid.add_child(name)
		grid.add_child(_cell(Fmt.short(row.population)))
		grid.add_child(_cell("$" + Fmt.short(row.gdp_usd)))
		grid.add_child(_cell("$" + Fmt.thousands(roundi(row.gdp_per_head))))
		grid.add_child(_cell("x%s" % Fmt.decimal(row.currency, 2), _trend_variation(row.currency - 1.0)))
		grid.add_child(_cell(("+" if row.balance >= 0.0 else "-") + "$" + Fmt.short(absf(row.balance)), _trend_variation(row.balance)))
		grid.add_child(_cell("%s%%" % Fmt.decimal(row.tariff * 100.0, 1)))
		grid.add_child(_cell(str(row.firms)))
		grid.add_child(_cell(str(row.plants)))
	_body.add_child(grid)


func _country_card(id: String) -> Control:
	var world: WorldEconomy = GameState.world
	var country := WorldEconomy.country(id)
	var box := _card(str(country.get("name", id)), func() -> void:
		_country = ""
		_refresh())
	var entry: Dictionary = world.currency.get(id, {})
	var lines := PackedStringArray()
	lines.append("%s · %s · %s people, %d%% in towns, growing %s%% a year" % [str(country.get("region", "")), str(country.get("income", "")), Fmt.short(float(country.get("population", 0))),
		roundi(float(country.get("urban_share", 0.0)) * 100.0), Fmt.decimal(float(country.get("growth", 0.0)) * 100.0, 1)])
	lines.append("GDP $%s ($%s a head) · tariff %s%%%s" % [Fmt.short(float(country.get("gdp_usd", 0))), Fmt.thousands(roundi(float(country.get("gdp_per_head", 0)))), Fmt.decimal(float(country.get("tariff", 0.0)) * 100.0, 1),
		"" if str(country.get("bloc", "")).is_empty() else " (none inside the %s)" % str(country.get("bloc"))])
	var exports := float(entry.get("exports", 0.0))
	var imports := float(entry.get("imports", 0.0))
	lines.append("Currency x%s of its start · exports $%s, imports $%s over the last three months (%s)" % [Fmt.decimal(float(entry.get("strength", 1.0)), 3), Fmt.short(exports), Fmt.short(imports),
		"a surplus" if exports >= imports else "a deficit"])
	box.add_child(_text("\n".join(lines)))
	# Its people by stratum, over its places.
	var strata := [0.0, 0.0, 0.0]
	for place: Dictionary in world.places:
		if place.country == id:
			var split: Array = world.strata_of(place)
			for k in 3:
				strata[k] += float(split[k])
	box.add_child(_dim("People: %s lower, %s middle, %s upper" % [Fmt.short(strata[0]), Fmt.short(strata[1]), Fmt.short(strata[2])]))
	# Its zones and their ports.
	var g_count := world.goods.size()
	var made := {}
	var used := {}
	for z in world.zones.size():
		var zone: Dictionary = world.zones[z]
		if zone.country != id:
			continue
		var ports := HFlowContainer.new()
		ports.add_theme_constant_override(&"h_separation", 4)
		ports.add_child(_dim("%s:" % str(zone.name)))
		for port_id: String in zone.ports:
			ports.add_child(_port_button(port_id))
		box.add_child(ports)
		for g in g_count:
			var i := z * g_count + g
			made[g] = float(made.get(g, 0.0)) + world.made[i] * world._base[g]
			used[g] = float(used.get(g, 0.0)) + world.used[i] * world._base[g]
	box.add_child(_dim("Makes most: %s" % _top_goods(made, world)))
	box.add_child(_dim("Uses most: %s" % _top_goods(used, world)))
	# The firms based there.
	var firms := HFlowContainer.new()
	firms.add_theme_constant_override(&"h_separation", 4)
	firms.add_child(_dim("Shipping firms:"))
	var any := false
	for firm: Dictionary in GameState.firms.firms:
		if firm.country == id:
			any = true
			var button := _flat_button(str(firm.name), func() -> void:
				_company_kind = "firms"
				_company = int(firm.id)
				show_tab("companies"))
			firms.add_child(button)
	if not any:
		firms.add_child(_dim("none"))
	box.add_child(firms)
	var chart := LineChart.new(120.0)
	chart.series = GameState.history.currency_series(id)
	chart.labels = GameState.history.month_labels()
	chart.line_color = Color(0.55, 0.85, 0.95)
	chart.tooltip_text = "Its currency's strength by the month."
	box.add_child(_dim("Currency over the game:"))
	box.add_child(chart)
	return box.get_parent()


func _top_goods(values: Dictionary, world: WorldEconomy) -> String:
	var keys: Array = values.keys()
	keys.sort_custom(func(a: int, b: int) -> bool: return float(values[a]) > float(values[b]))
	var parts := PackedStringArray()
	for g: int in keys.slice(0, 6):
		if float(values[g]) <= 0.0:
			break
		parts.append("%s $%s a day" % [str(GameData.commodity(world.goods[g]).get("name", world.goods[g])).to_lower(), Fmt.short(float(values[g]))])
	return ", ".join(parts) if not parts.is_empty() else "nothing yet"


# --- Companies --------------------------------------------------------------------------

func _build_companies() -> void:
	var picker := HBoxContainer.new()
	picker.add_theme_constant_override(&"separation", 6)
	var group := ButtonGroup.new()
	for kind: Array in [["firms", "Shipping firms"], ["producers", "Producers"]]:
		var button := Button.new()
		button.text = kind[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = kind[0] == _company_kind
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_company_kind = kind[0]
			_company = -1
			_company_sort = "ships" if kind[0] == "firms" else "plants"
			_refresh())
		picker.add_child(button)
	_body.add_child(picker)
	if _company_kind == "firms":
		_build_firms()
	else:
		_build_producers()


func _build_firms() -> void:
	var firms: ShippingFirms = GameState.firms
	if firms.firms.is_empty():
		_body.add_child(_dim("No firms yet."))
		return
	var at_sea := {}
	for v: Dictionary in firms.voyages:
		at_sea[int(v.firm)] = int(at_sea.get(int(v.firm), 0)) + int(v.ships)
	for home: Dictionary in firms.returning():
		at_sea[int(home.firm)] = int(at_sea.get(int(home.firm), 0)) + int(home.ships)
	if _company >= 0 and _company < firms.firms.size():
		_body.add_child(_firm_card(firms.firms[_company], int(at_sea.get(_company, 0))))
	var rows := []
	for firm: Dictionary in firms.firms:
		var ships := 0
		for model_id: String in firm.fleet:
			ships += int(firm.fleet[model_id])
		rows.append({id = int(firm.id), name = str(firm.name), country = str(WorldEconomy.country(str(firm.country)).get("name", firm.country)), home = GameData.port_name(str(firm.home)),
			ships = ships, at_sea = int(at_sea.get(int(firm.id), 0)), money = float(firm.money), carried = float(firm.carried)})
	_company_table(FIRM_COLUMNS, rows, func(row: Dictionary) -> Array:
		return [row.country, row.home, Fmt.thousands(row.ships), Fmt.thousands(row.at_sea), Fmt.money_short(roundi(row.money)), Fmt.short(row.carried) + " units"])


func _firm_card(firm: Dictionary, at_sea: int) -> Control:
	var box := _card(str(firm.name), func() -> void:
		_company = -1
		_refresh())
	var country := str(WorldEconomy.country(str(firm.country)).get("name", firm.country))
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 4)
	row.add_child(_text("A shipping firm of %s, based at" % country))
	row.add_child(_port_button(str(firm.home)))
	box.add_child(row)
	var fleet: Array = firm.fleet.keys()
	fleet.sort_custom(func(a: String, b: String) -> bool: return int(firm.fleet[a]) > int(firm.fleet[b]))
	var parts := PackedStringArray()
	var ships := 0
	for model_id: String in fleet:
		ships += int(firm.fleet[model_id])
		if parts.size() < 6:
			parts.append("%d %s" % [int(firm.fleet[model_id]), str(GameData.get_ship_model(model_id).get("name", model_id))])
	box.add_child(_text("%s ships (%s at sea now): %s%s" % [Fmt.thousands(ships), Fmt.thousands(at_sea), ", ".join(parts), "..." if fleet.size() > 6 else ""]))
	var ceo: Dictionary = firm.get("ceo", {})
	if not ceo.is_empty():
		box.add_child(_text("Run by %s: %s" % [str(ceo.get("name", "")), Traits.names_of(ceo) if not Traits.names_of(ceo).is_empty() else "no traits of note"]))
	box.add_child(_dim("Earned %s on %s units carried so far. Its ships sail where the world's stockpiles call for cargo; you'll see them on the map in its colour." % [Fmt.money(roundi(float(firm.money))), Fmt.short(float(firm.carried))]))
	return box.get_parent()


func _build_producers() -> void:
	var producers: Producers = GameState.world.producers
	if producers.companies.is_empty():
		_body.add_child(_dim("No producers yet."))
		return
	var plants_of := {}
	var output_of := {}
	for plant: Dictionary in producers.plants:
		var c := int(plant.company)
		plants_of[c] = int(plants_of.get(c, 0)) + 1
		output_of[c] = float(output_of.get(c, 0.0)) + float(plant.capacity) * float(GameData.commodity(str(plant.good)).get("base", 1.0))
	if _company >= 0 and _company < producers.companies.size():
		_body.add_child(_producer_card(producers.companies[_company], int(plants_of.get(_company, 0)), float(output_of.get(_company, 0.0))))
	var rows := []
	for company: Dictionary in producers.companies:
		var c := int(company.id)
		rows.append({id = c, name = str(company.name), country = "Global" if bool(company.get("global", false)) else str(WorldEconomy.country(str(company.get("country", ""))).get("name", company.get("country", ""))),
			trade = str(company.get("trade", "")).capitalize(), plants = int(plants_of.get(c, 0)), output = float(output_of.get(c, 0.0))})
	_company_table(PRODUCER_COLUMNS, rows, func(row: Dictionary) -> Array:
		return [row.country, row.trade, str(row.plants), "$" + Fmt.short(row.output)])


func _producer_card(company: Dictionary, plants: int, output: float) -> Control:
	var producers: Producers = GameState.world.producers
	var box := _card(str(company.name), func() -> void:
		_company = -1
		_refresh())
	var from := "a global company" if bool(company.get("global", false)) else "of %s" % str(WorldEconomy.country(str(company.get("country", ""))).get("name", company.get("country", "")))
	box.add_child(_text("%s, in %s: %d plants making $%s of goods a year at base prices." % [from.capitalize() if from.begins_with("a ") else "A %s producer %s" % [str(company.get("trade", "")), from], str(company.get("trade", "")), plants, Fmt.short(output)]))
	var mine: Array = []
	for i in producers.plants.size():
		if int(producers.plants[i].company) == int(company.id):
			mine.append(i)
	mine.sort_custom(func(a: int, b: int) -> bool: return float(producers.plants[a].capacity) > float(producers.plants[b].capacity))
	var list := HFlowContainer.new()
	list.add_theme_constant_override(&"h_separation", 4)
	list.add_theme_constant_override(&"v_separation", 2)
	for i: int in mine.slice(0, 16):
		var plant: Dictionary = producers.plants[i]
		var site := str(plant.site)
		var where := GameData.port_name(site) if str(plant.site_kind) == "port" else str(WorldEconomy.city(site).get("name", site))
		var button := _flat_button("%s at %s" % [Producers.plant_title(plant), where], func() -> void:
			if str(plant.site_kind) == "port":
				GameRoot.find(self).show_port_on_map(site)
			else:
				GameRoot.find(self).show_city_on_map(site))
		list.add_child(button)
	if mine.size() > 16:
		list.add_child(_dim("and %d more" % (mine.size() - 16)))
	box.add_child(list)
	return box.get_parent()


## A sortable table of companies: the columns, the rows (each with id and
## name, and the keys the columns sort on) and a function giving a row's cells after its name.
func _company_table(columns: Array, rows: Array, cells: Callable) -> void:
	if not rows.is_empty() and not rows[0].has(_company_sort):
		_company_sort = columns[-2][0]
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var x: Variant = a[_company_sort]
		var y: Variant = b[_company_sort]
		if x is String:
			return x.to_lower() < y.to_lower()
		if x == y:
			return a.name < b.name
		return x > y)
	var grid := GridContainer.new()
	grid.columns = columns.size()
	grid.add_theme_constant_override(&"h_separation", 18)
	grid.add_theme_constant_override(&"v_separation", 2)
	for column: Array in columns:
		var head := Button.new()
		head.flat = true
		head.text = column[1] + (" ▼" if column[0] == _company_sort else "")
		head.add_theme_font_size_override(&"font_size", FONT_SIZE)
		head.pressed.connect(func() -> void:
			_company_sort = column[0]
			_refresh())
		grid.add_child(head)
	for row: Dictionary in rows:
		var name := Button.new()
		name.flat = true
		name.text = row.name
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name.add_theme_font_size_override(&"font_size", FONT_SIZE)
		name.pressed.connect(func() -> void:
			_company = int(row.id)
			_refresh())
		grid.add_child(name)
		for text: String in cells.call(row):
			grid.add_child(_cell(text))
	_body.add_child(grid)


# --- Markets --------------------------------------------------------------------------

func _goods_options() -> OptionButton:
	var picker := OptionButton.new()
	for commodity: Dictionary in GameData.commodities:
		if commodity.get("maker", false) or commodity.get("legacy", false):
			continue
		picker.add_item("%s (per %s)" % [commodity.name, commodity.unit])
		picker.set_item_metadata(picker.item_count - 1, commodity.id)
	for line: Array in [["cars", "Car makers (per vehicle)"], ["boats", "Boat builders (per boat)"]]:
		picker.add_separator(line[1])
		for each: Dictionary in Manufacturers.makers_of(line[0]):
			picker.add_item("%s: %s" % [each.name, Manufacturers.describe(each.id).to_lower()])
			picker.set_item_metadata(picker.item_count - 1, each.id)
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return picker


func _select(picker: OptionButton, id: String) -> void:
	for i in picker.item_count:
		if picker.get_item_metadata(i) == id:
			picker.select(i)
			return


func _build_markets() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var picker := _goods_options()
	if _good.is_empty() and picker.item_count > 0:
		_good = str(picker.get_item_metadata(0))
	_select(picker, _good)
	picker.item_selected.connect(func(index: int) -> void:
		_good = str(picker.get_item_metadata(index))
		_refresh())
	header.add_child(picker)
	var hint := _dim("Buy prices include the %d%% spread. Prices follow each zone's days of cover: the living world's stockpiles, what its plants make and its people and industry use, and the ships on their way." % roundi(float(GameData.markets.get("spread", 0.0)) * 100.0))
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(hint)
	_body.add_child(header)
	var market := GameState.market
	var buys := {}
	var sells := {}
	for port: Dictionary in GameData.ports:
		buys[port.id] = market.buy_price(port.id, _good)
		sells[port.id] = market.sell_price(port.id, _good)
	var cheapest: Array = buys.keys()
	cheapest.sort_custom(func(a: String, b: String) -> bool: return buys[a] < buys[b])
	var most_expensive: Array = sells.keys()
	most_expensive.sort_custom(func(a: String, b: String) -> bool: return sells[a] > sells[b])
	var lists := GridContainer.new()
	lists.columns = 2
	lists.add_theme_constant_override(&"h_separation", 32)
	lists.add_theme_constant_override(&"v_separation", 16)
	_body.add_child(lists)
	_add_list(lists, "Cheapest to buy", cheapest.slice(0, LIST_SIZE).map(func(id: String) -> Array: return [[id], Fmt.money(roundi(buys[id]))]))
	_add_list(lists, "Most expensive to sell", most_expensive.slice(0, LIST_SIZE).map(func(id: String) -> Array: return [[id], Fmt.money(roundi(sells[id]))]))
	var best := []
	var best_short := []
	for from: String in cheapest.slice(0, 40):
		for to: String in sells:
			var margin: float = sells[to] - buys[from]
			if to != from and margin > 0.0:
				best.append([from, to, margin])
	for from: String in buys:
		for to: String in sells:
			var margin: float = sells[to] - buys[from]
			if to != from and margin > 0.0 and GameData.distance_nm(from, to) <= SHORT_TRADE_NM:
				best_short.append([from, to, margin])
	var by_margin := func(a: Array, b: Array) -> bool: return a[2] > b[2]
	best.sort_custom(by_margin)
	best_short.sort_custom(by_margin)
	_add_list(lists, "Best trades", best.slice(0, LIST_SIZE).map(_trade_row))
	_add_list(lists, "Best trades within %s nm" % Fmt.thousands(roundi(SHORT_TRADE_NM)), best_short.slice(0, LIST_SIZE).map(_trade_row))
	_add_zone_table()


## Every zone's price of the good: x its base, days of cover, stock and use, with a year's sparkline.
func _add_zone_table() -> void:
	var world: WorldEconomy = GameState.world
	var g := world.good_index(_good)
	if g < 0 or world.zones.is_empty():
		return
	var g_count := world.goods.size()
	var rows := []
	for z in world.zones.size():
		var i := z * g_count + g
		if world.use_for_price(i) <= 0.0:
			continue
		rows.append([z, world.price[i] / maxf(world._base[g], 0.000001), world.cover(z, g), world.stock[i], world.need_base[i] + world.user_base[i], world.capacity[i]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	var unit := str(GameData.commodity(_good).get("units", "units"))
	_body.add_child(_dim("Every market's price of %s now, dearest first: x its usual price, the days its stockpile covers, what it holds, uses and makes a day. Click a market for its chart." % str(GameData.commodity(_good).get("name", _good)).to_lower()))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override(&"h_separation", 16)
	grid.add_theme_constant_override(&"v_separation", 2)
	for head: String in ["Market", "Price", "Cover", "Stock", "Uses a day", "Makes a day", "Last year"]:
		grid.add_child(_cell(head, &"DimLabel"))
	var history: WorldHistory = GameState.history
	for row: Array in rows.slice(0, ZONE_ROWS):
		var z: int = row[0]
		var zone: Dictionary = world.zones[z]
		var name := _flat_button(world.zone_label(z), func() -> void: show_chart(_good, z))
		grid.add_child(name)
		var ratio: float = row[1]
		grid.add_child(_cell("x%s" % Fmt.decimal(ratio, 2), &"GainLabel" if ratio >= 1.25 else (&"ErrorLabel" if ratio <= 0.7 else &"")))
		grid.add_child(_cell("%s days" % Fmt.thousands(roundi(minf(float(row[2]), 9999.0))) if float(row[2]) != INF else "—"))
		grid.add_child(_cell("%s %s" % [Fmt.short(float(row[3])), unit]))
		grid.add_child(_cell(Fmt.short(float(row[4]))))
		grid.add_child(_cell(Fmt.short(float(row[5]))))
		var spark := LineChart.new(26.0)
		spark.small = true
		spark.custom_minimum_size.x = 110.0
		spark.series = history.weekly_series(z * g_count + g)
		spark.line_color = Color(0.98, 0.78, 0.35, 0.9)
		grid.add_child(spark)
	if rows.size() > ZONE_ROWS:
		grid.add_child(_dim("and %d more markets" % (rows.size() - ZONE_ROWS)))
	_body.add_child(grid)


func _trade_row(trade: Array) -> Array:
	var nm := GameData.distance_nm(trade[0], trade[1])
	return [[trade[0], trade[1]], "+%s a unit · %s nm" % [Fmt.money(roundi(trade[2])), Fmt.thousands(roundi(nm))]]


## A titled list of rows: [[port ids], text]. Each port is a button to it on the map.
func _add_list(into: Control, title: String, rows: Array) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_dim(title))
	if rows.is_empty():
		box.add_child(_dim("Nothing profitable right now"))
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 4)
		var ports: Array = row[0]
		for i in ports.size():
			if i > 0:
				line.add_child(_cell("→"))
			var button := _port_button(ports[i], ports.size() == 1)
			line.add_child(button)
		line.add_child(_cell(row[1], &"GainLabel" if ports.size() > 1 else &""))
		box.add_child(line)
	into.add_child(box)


# --- Charts ---------------------------------------------------------------------------

func _build_charts() -> void:
	var world: WorldEconomy = GameState.world
	var history: WorldHistory = GameState.history
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var picker := _goods_options()
	if _chart_good.is_empty() and picker.item_count > 0:
		_chart_good = _good if not _good.is_empty() else str(picker.get_item_metadata(0))
	_select(picker, _chart_good)
	picker.item_selected.connect(func(index: int) -> void:
		_chart_good = str(picker.get_item_metadata(index))
		_refresh())
	header.add_child(picker)
	var zones := OptionButton.new()
	zones.add_item("The world (by use)")
	zones.set_item_metadata(0, -1)
	var order := range(world.zones.size())
	order.sort_custom(func(a: int, b: int) -> bool: return world.zone_label(a) < world.zone_label(b))
	for z: int in order:
		zones.add_item(world.zone_label(z))
		zones.set_item_metadata(zones.item_count - 1, z)
		if z == _chart_zone:
			zones.select(zones.item_count - 1)
	zones.item_selected.connect(func(index: int) -> void:
		_chart_zone = int(zones.get_item_metadata(index))
		_refresh())
	header.add_child(zones)
	var group := ButtonGroup.new()
	for span: Array in RANGES:
		var button := Button.new()
		button.text = span[1]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = span[0] == _chart_range
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void:
			_chart_range = span[0]
			_refresh())
		header.add_child(button)
	_body.add_child(header)
	var g := world.good_index(_chart_good)
	var chart := LineChart.new(260.0)
	var what := "the world" if _chart_zone < 0 else world.zone_label(_chart_zone)
	if g >= 0 and not world.zones.is_empty():
		if _chart_range == "year":
			chart.series = history.world_weekly_series(world, g) if _chart_zone < 0 else history.weekly_series(_chart_zone * world.goods.size() + g)
			var labels := PackedStringArray()
			for k in chart.series.size():
				labels.append("%d wk" % (k - chart.series.size() + 1) if (chart.series.size() - 1 - k) % 8 == 0 else "")
			chart.labels = labels
		else:
			var count := 0
			for span: Array in RANGES:
				if span[0] == _chart_range:
					count = maxi(int(span[2]), 0)
			chart.series = history.world_monthly_series(world, g, count) if _chart_zone < 0 else history.monthly_series(_chart_zone * world.goods.size() + g, count)
			chart.labels = history.month_labels(count)
	_body.add_child(_text("%s in %s: price as x its usual (the dashed line), %s." % [str(GameData.commodity(_chart_good).get("name", _chart_good)), what,
		"by the week over the last year" if _chart_range == "year" else "by the month"]))
	_body.add_child(chart)
	if g >= 0 and _chart_zone >= 0:
		var i := _chart_zone * world.goods.size() + g
		_body.add_child(_dim("Now x%s · %s days of cover · %s %s in stock, uses %s and makes %s a day" % [Fmt.decimal(world.price[i] / maxf(world._base[g], 0.000001), 2),
			"∞" if world.cover(_chart_zone, g) == INF else Fmt.thousands(roundi(world.cover(_chart_zone, g))), Fmt.short(world.stock[i]), str(GameData.commodity(_chart_good).get("units", "units")),
			Fmt.short(world.need_base[i] + world.user_base[i]), Fmt.short(world.capacity[i])]))


# --- News -----------------------------------------------------------------------------

func _build_news() -> void:
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override(&"separation", 8)
	for kind: Array in [["market", "Markets"], ["company", "Companies"], ["world", "World"]]:
		var toggle := CheckButton.new()
		toggle.text = kind[1]
		toggle.button_pressed = bool(_news_kinds.get(kind[0], true))
		toggle.add_theme_font_size_override(&"font_size", FONT_SIZE)
		toggle.toggled.connect(func(on: bool) -> void:
			_news_kinds[kind[0]] = on
			_refresh())
		filters.add_child(toggle)
	_body.add_child(filters)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 32)
	_body.add_child(columns)
	var feed := VBoxContainer.new()
	feed.add_theme_constant_override(&"separation", 4)
	feed.size_flags_horizontal = SIZE_EXPAND_FILL
	feed.size_flags_stretch_ratio = 1.4
	columns.add_child(feed)
	feed.add_child(_heading("The world"))
	var kinds := []
	for kind: String in _news_kinds:
		if _news_kinds[kind]:
			kinds.append(kind)
	var items: Array = GameState.news.latest(NEWS_SHOWN, kinds) if not kinds.is_empty() else []
	if items.is_empty():
		feed.add_child(_dim("Nothing yet: the news comes with each week's markets and each month's figures."))
	for item: Dictionary in items:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		var when := _cell(Fmt.calendar_short(int(item.time)), &"DimLabel")
		when.custom_minimum_size.x = 92.0
		line.add_child(when)
		var text := _cell(str(item.text))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.add_theme_color_override(&"font_color", {market = Color(0.98, 0.85, 0.55), company = Color(0.75, 0.88, 1.0), world = Color(0.8, 0.95, 0.8)}.get(str(item.kind), Color.WHITE))
		line.add_child(text)
		var about: Dictionary = item.get("about", {})
		if not str(about.get("port", "")).is_empty():
			line.add_child(_port_button(str(about.port)))
		if not str(about.get("good", "")).is_empty():
			line.add_child(_flat_button("Chart", func() -> void: show_chart(str(about.good), int(about.get("zone", -1)))))
		feed.add_child(line)
	var you := VBoxContainer.new()
	you.add_theme_constant_override(&"separation", 4)
	you.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.add_child(you)
	you.add_child(_heading("You"))
	var entries := ActivityLog.entries.duplicate()
	entries.reverse()
	if entries.is_empty():
		you.add_child(_dim("Nothing in your log yet."))
	for entry: Dictionary in entries.slice(0, NEWS_SHOWN):
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 8)
		var when := _cell(Fmt.calendar_short(GameState.calendar_time_at(float(entry.time))), &"DimLabel")
		when.custom_minimum_size.x = 92.0
		line.add_child(when)
		var text := _cell(str(entry.text), &"GainLabel" if entry.kind == ActivityLog.Kind.GOOD else (&"ErrorLabel" if entry.kind == ActivityLog.Kind.BAD else &""))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		line.add_child(text)
		you.add_child(line)


# --- Bits ------------------------------------------------------------------------------

func _card(title_text: String, on_close: Callable) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = title_text
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(on_close)
	header.add_child(close)
	box.add_child(header)
	return box


func _heading(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"HeaderLabel"
	label.text = text
	return label


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	return label


func _cell(text: String, variation := &"") -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


static func _trend_variation(value: float) -> StringName:
	return &"GainLabel" if value > 0.0001 else (&"ErrorLabel" if value < -0.0001 else &"")


func _flat_button(text: String, then: Callable) -> Button:
	var button := Button.new()
	button.flat = true
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.pressed.connect(then)
	return button


func _port_button(port_id: String, with_region := false) -> Button:
	var text := "%s (%s)" % [GameData.port_name(port_id), GameData.port_region(port_id).get("name", "")] if with_region else GameData.port_name(port_id)
	return _flat_button(text, func() -> void: GameRoot.find(self).show_port_on_map(port_id))


static func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

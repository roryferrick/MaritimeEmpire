# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name PortPopup
extends AnchoredPopup
## Shows a port's name and size (how far through its band it is, which way
## it's going and what the size does), then tabs, one showing at a time: its
## market (each commodity's buy and sell price, green where it's cheap
## compared with the world average and red where expensive), its HQ or hub
## (level, XP and upgrade tree) or a button to found a hub there when one is
## available, the player's trade there (what it has bought and sold, each
## commodity ranked by what an industry building for it would be worth here:
## see GameState.port_trade_summary()), and the player's ships docked there
## with their bars.

const SHIP_BARS_WIDTH := 80.0
## Founding a hub takes a second click within this many seconds (it's permanent).
const BUILD_CONFIRM_SECONDS := 3.0
const REFRESH_SECONDS := 1.0
## The birds line's color: a soft sky blue.
const BIRDS_COLOR := Color(0.62, 0.8, 0.95)
## The market table: its text size, and how far below or above a commodity's
## world average price counts as cheap (green) or expensive (red).
const MARKET_FONT_SIZE := 15
const MARKET_CHEAP := 0.8
const MARKET_EXPENSIVE := 1.25

## The docked ships' list scrolls past this height (pixels).
const SHIP_LIST_MAX_HEIGHT := 300.0

## The tab picked last in any port popup ("market", "hub", "trade" or "ships").
static var _last_tab := "market"

## Set before adding to the tree.
var port_id := ""
var _tab_keys: Array[String] = []
var _ship_count := 0

var _build_confirm_until := 0.0
var _xp_label: Label = null
var _clock := 0.0
var _size_label := Label.new()
var _size_bar := ProgressBar.new()
var _size_effects := Label.new()
## The gulls over the port now (see Birds).
var _birds_label := Label.new()
## The trade tab (see _refresh_trade()).
var _trade_page := VBoxContainer.new()
var _trade_note := Label.new()
var _trade_grid := GridContainer.new()


func _ready() -> void:
	super()
	_build_size()
	%CloseButton.pressed.connect(queue_free)
	GameState.ships_changed.connect(_refresh_ships)
	GameState.ship_changed.connect(_refresh_ships.unbind(1))
	GameState.hubs_changed.connect(_refresh_hub)
	GameState.company_leveled.connect(_refresh_hub.unbind(2))
	%Tabs.tab_changed.connect(_on_tab_changed)
	_build_trade()
	_refresh_hub()
	_refresh_ships()
	_refresh_market()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_update_hub_xp()
		_update_size()
		_update_birds()
		_refresh_market()
		if _trade_page.visible:
			_refresh_trade()


## The port's size: how far through its band it is and which way it's going,
## what the size does here, and which ships are too big for it.
func _build_size() -> void:
	_size_label.theme_type_variation = &"DimLabel"
	%SizeBox.add_child(_size_label)
	_size_bar.show_percentage = false
	_size_bar.custom_minimum_size.y = 8.0
	_size_bar.max_value = 1.0
	%SizeBox.add_child(_size_bar)
	_size_effects.theme_type_variation = &"DimLabel"
	_size_effects.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	%SizeBox.add_child(_size_effects)
	_birds_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_birds_label.add_theme_color_override(&"font_color", BIRDS_COLOR)
	%SizeBox.add_child(_birds_label)
	# What the company's boats have left in the cold store here, for its seafood carriers.
	var store: Dictionary = GameState.company.cold_stores.get(port_id, {})
	if not store.is_empty():
		var cold := Label.new()
		cold.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cold.add_theme_color_override(&"font_color", Color(0.62, 0.82, 0.95))
		var parts := PackedStringArray()
		for family: String in store:
			parts.append("%s crates of %s" % [Fmt.thousands(floori(float(store[family]))), str(GameData.commodity(family).get("name", family)).to_lower()])
		cold.text = "Your cold store: %s, for your seafood carriers" % ", ".join(parts)
		%SizeBox.add_child(cold)
	_add_farm_line()
	_add_maker_line()
	_update_birds()
	_update_size()


## The vehicle and boat makers with a factory here (their own, or a company's
## for them): who they are, how much they like this player, its own factory's
## stock here, and a button to them on the Makers screen.
func _add_maker_line() -> void:
	var here := GameState.makers.makers_at(port_id)
	if here.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", Color(0.62, 0.74, 0.98))
	var parts := PackedStringArray()
	for id in here:
		var each := Manufacturers.maker(id)
		var whose := "" if Manufacturers.is_factory_port(id, port_id) else " (%s)" % ", ".join(PackedStringArray(GameState.makers.factories_at(port_id).filter(func(pair: Array) -> bool: return pair[1].maker == id).map(func(pair: Array) -> String: return (pair[0] as Company).name)))
		var text := "%s%s" % [each.name, whose]
		if Manufacturers.can_deal(GameState.company):
			text += " likes you %d" % floori(Manufacturers.likeness(GameState.company, id))
		var mine := Manufacturers.factory(GameState.company, id, port_id)
		if not mine.is_empty():
			text += ", your factory holds %s %s" % [Fmt.thousands(floori(float(mine.get("stock", 0.0)))), GameData.commodity(id).get("units", "vehicles")]
		parts.append(text)
	label.text = "Factories: %s" % " · ".join(parts)
	row.add_child(label)
	if Manufacturers.can_deal(GameState.company):
		var open := Button.new()
		open.text = "Makers"
		open.size_flags_vertical = SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void:
			GameRoot.find(self).show_maker(here[0])
			queue_free())
		row.add_child(open)
	%SizeBox.add_child(row)


## A farm port's line: its climate, its plots, the company's farm there, and a
## button to it on the Farms screen.
func _add_farm_line() -> void:
	if not Farms.is_farm_port(port_id):
		return
	var farms := GameState.farms
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.add_theme_color_override(&"font_color", Color(0.72, 0.86, 0.5))
	var total := int(Farms.port_info(port_id).get("plots", 0))
	var mine := farms.owned_by(GameState.company, port_id).size()
	label.text = "Farm port · %s climate · %d of %d plots free%s" % [Farms.climate_name(Farms.climate_of(port_id)), total - farms.taken_at(port_id), total,
		" · %d yours" % mine if mine > 0 else ""]
	var value := farms.store_value(GameState.company, port_id)
	if value > 0:
		label.text += " · your farm store holds %s" % Fmt.money(value)
	row.add_child(label)
	if Farms.can_farm(GameState.company):
		var open := Button.new()
		open.text = "Farms"
		open.size_flags_vertical = SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void:
			GameRoot.find(self).show_farm(port_id)
			queue_free())
		row.add_child(open)
	%SizeBox.add_child(row)


func _update_size() -> void:
	var sizes := GameState.port_sizes
	var here := sizes.size(port_id)
	var low := sizes.band_min(sizes.band(port_id))
	var high := sizes.next_band_min(port_id)
	%TitleLabel.text = "%s · %s" % [GameData.port_name(port_id), GameState.port_size_text(port_id)]
	var rate := sizes.rate(port_id)
	var trend := "steady"
	if rate > 0.0:
		trend = "growing (+%s an hour)" % Fmt.decimal(rate, 1)
	elif rate < 0.0:
		trend = "shrinking (%s an hour)" % Fmt.decimal(rate, 1)
	var next := sizes.band_of(high)
	var target := "%s at %d" % [next.capitalize(), roundi(high)] if not next.is_empty() and high <= 100.0 else "the largest size"
	_size_label.text = "Size %s of 100, %s · next: %s" % [Fmt.decimal(here, 1), trend, target]
	_size_bar.value = clampf((here - low) / (high - low), 0.0, 1.0)
	var costs := roundi((sizes.cost_factor(port_id) - 1.0) * 100.0)
	var lines := PackedStringArray([
		"Fuel & repairs %s%d%% · your trades move prices %sx" % ["+" if costs > 0 else "", costs, Fmt.decimal(sizes.impact_factor(port_id), 2)]])
	var too_big := PackedStringArray()
	for band: String in ["medium", "large"]:
		if here < sizes.band_min(band):
			too_big.append("ships needing %s ports" % band.capitalize())
	lines.append("Too small for %s" % " or ".join(too_big) if not too_big.is_empty() else "Every ship can dock here")
	# Seasonal closures (in saves with them) and a storm over the port.
	if GameState.seasons:
		for closure: Dictionary in GameState.seasonal.closures():
			if not closure.get("ports", []).has(port_id):
				continue
			if not GameState.seasonal.port_closure(port_id, GameState.calendar_time()).is_empty():
				if not GameState.icebreaking.lifting(closure).is_empty():
					lines.append("Iced in until %s: your icebreaker leads ships in and out" % Seasons.date_text(closure.to))
				else:
					lines.append("Closed by %s until %s" % [closure.why, Seasons.date_text(closure.to)])
			else:
				lines.append("Closes for %s from %s to %s" % [closure.why, Seasons.date_text(closure.from), Seasons.date_text(closure.to)])
	var storm := GameState.weather.closed_by(port_id)
	if not storm.is_empty():
		lines.append("Closed while %s passes" % Weather.title(storm))
	_size_effects.text = "\n".join(lines)


## The tabs under the size: Market, the HQ or hub (or "Build a hub" while one
## is available; no tab otherwise) and the ships docked here with their count.
## The one picked last (in any port popup) stays picked.
func _update_tabs() -> void:
	var tabs := [["market", "Market"]]
	var hub := GameState.hub_at(port_id)
	if hub:
		tabs.append(["hub", "Headquarters" if hub.is_hq else "Hub"])
	elif GameState.hubs_available() > 0:
		tabs.append(["hub", "Build a hub"])
	tabs.append(["trade", "Your trade"])
	tabs.append(["ships", "Ships (%d)" % _ship_count])
	_tab_keys.clear()
	%Tabs.tab_count = tabs.size()
	for i in tabs.size():
		_tab_keys.append(tabs[i][0])
		%Tabs.set_tab_title(i, tabs[i][1])
	var picked := _tab_keys.find(_last_tab)
	%Tabs.set_block_signals(true)
	%Tabs.current_tab = picked if picked >= 0 else 0
	%Tabs.set_block_signals(false)
	_show_page()


func _on_tab_changed(tab: int) -> void:
	_last_tab = _tab_keys[tab]
	_show_page()


func _show_page() -> void:
	var key: String = _tab_keys[%Tabs.current_tab]
	%MarketPage.visible = key == "market"
	%HubBox.visible = key == "hub"
	%ShipsPage.visible = key == "ships"
	_trade_page.visible = key == "trade"
	if _trade_page.visible:
		_refresh_trade()
	reset_size.call_deferred()


## The docked ships' list scrolls once it's taller than SHIP_LIST_MAX_HEIGHT.
func _fit_ship_list() -> void:
	%ShipScroll.custom_minimum_size.y = minf(%ShipList.get_combined_minimum_size().y, SHIP_LIST_MAX_HEIGHT)
	reset_size.call_deferred()


func _refresh_hub() -> void:
	for child in %HubBox.get_children():
		%HubBox.remove_child(child)
		child.queue_free()
	_xp_label = null
	var hub := GameState.hub_at(port_id)
	if hub:
		_show_hub(hub)
	elif GameState.hubs_available() > 0:
		var build := Button.new()
		build.text = "Build a hub here (%d available)" % GameState.hubs_available()
		build.tooltip_text = "Hubs level up from deliveries unloaded here and boost every ship that docks. It's permanent."
		build.pressed.connect(_on_build_pressed.bind(build))
		%HubBox.add_child(build)
	_update_tabs()


func _show_hub(hub: Hub) -> void:
	var title := Label.new()
	title.text = "%s · level %d" % ["Headquarters" if hub.is_hq else "Hub", hub.level]
	%HubBox.add_child(title)
	_xp_label = Label.new()
	_xp_label.theme_type_variation = &"DimLabel"
	%HubBox.add_child(_xp_label)
	_update_hub_xp()
	var company := Label.new()
	company.theme_type_variation = &"GainLabel"
	company.text = hub.company_xp_text()
	%HubBox.add_child(company)
	%HubBox.add_child(HubTree.new(hub))
	var points := hub.upgrade_points()
	if points > 0:
		var hint := Label.new()
		hint.theme_type_variation = &"GainLabel"
		hint.text = "%d upgrade point%s to spend" % [points, "" if points == 1 else "s"]
		%HubBox.add_child(hint)


func _update_hub_xp() -> void:
	if not is_instance_valid(_xp_label):
		return
	var hub := GameState.hub_at(port_id)
	var cost := GameState.hub_level_cost(hub)
	_xp_label.text = "Max level" if cost <= 0.0 else "%s / %s XP to level %d" % [
		Fmt.thousands(floori(hub.xp)), Fmt.thousands(ceili(cost)), hub.level + 1]


## First click asks for confirmation; a second click founds the hub.
func _on_build_pressed(button: Button) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _build_confirm_until:
		GameState.build_hub(port_id)
		return
	_build_confirm_until = now + BUILD_CONFIRM_SECONDS
	button.text = "Build a hub at %s? It's permanent" % GameData.port_name(port_id)
	reset_size.call_deferred()


func _refresh_ships() -> void:
	for child in %ShipList.get_children():
		%ShipList.remove_child(child)
		child.queue_free()
	var count := 0
	for ship in GameState.fleet():
		if ship.docked_at != port_id:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var button := Button.new()
		button.text = "%s · %s" % [ship.name, ship.model().get("name", ship.model_id)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_open_ship.bind(ship))
		row.add_child(button)
		var bars := ShipBars.new(ship, true)
		bars.custom_minimum_size.x = SHIP_BARS_WIDTH
		bars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bars)
		%ShipList.add_child(row)
		count += 1
	_ship_count = count
	%NoShipsLabel.visible = count == 0
	%ShipScroll.visible = count > 0
	_fit_ship_list.call_deferred()
	_update_tabs()


func _open_ship(ship: Ship) -> void:
	PopupHost.find(self).show_ship(ship, follow)


## Each commodity's buy and sell price here, colored against its world average,
## in two columns of commodities.
func _refresh_market() -> void:
	for child in %MarketGrid.get_children():
		%MarketGrid.remove_child(child)
		child.queue_free()
	for title: String in ["", "Buy", "Sell", "", "Buy", "Sell"]:
		_add_market_cell(title, &"DimLabel")
	# The plain goods, then the makers with a factory here (theirs or a company's:
	# their goods are cheapest here); the other makers' are on the Markets tab.
	var listed: Array = GameData.commodities.filter(func(commodity: Dictionary) -> bool: return not commodity.get("maker", false) and not commodity.get("legacy", false))
	for id in GameState.makers.makers_at(port_id):
		listed.append(GameData.commodity(id))
	for commodity: Dictionary in listed:
		var sell := GameState.market.sell_price(port_id, commodity.id)
		var ratio := sell / GameData.world_price(commodity.id)
		var variation := &"GainLabel" if ratio < MARKET_CHEAP else (&"ErrorLabel" if ratio > MARKET_EXPENSIVE else &"")
		_add_market_cell(commodity.name, &"")
		_add_market_cell(Fmt.money(roundi(GameState.market.buy_price(port_id, commodity.id))), variation)
		_add_market_cell(Fmt.money(roundi(sell)), variation)


func _add_market_cell(text: String, variation: StringName) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", MARKET_FONT_SIZE)
	%MarketGrid.add_child(label)


## "Gulls: Herring Gull (16), Yellow-legged Gull (8)": the gulls living at the
## port now, each species once with all its flocks added up, the most first.
func _update_birds() -> void:
	var totals := {}  # Species id -> birds, in the order first met.
	for entry: Dictionary in Wildlife.shared().birds_at(port_id, "gulls", float(GameState.calendar_time())):
		totals[entry.id] = int(totals.get(entry.id, 0)) + int(entry.count)
	var gulls := []
	for id: String in totals:
		gulls.append({id = id, count = totals[id]})
	gulls.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.count) > int(b.count))
	_birds_label.text = "Gulls: %s" % Birds.shared().counts_text(gulls) if not gulls.is_empty() else ""


# --- Your trade --------------------------------------------------------------

## The trade tab's page, under the others in the popup.
func _build_trade() -> void:
	_trade_page.add_theme_constant_override(&"separation", 6)
	_trade_page.visible = false
	_trade_note.theme_type_variation = &"DimLabel"
	_trade_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trade_note.custom_minimum_size.x = 420.0
	_trade_page.add_child(_trade_note)
	_trade_grid.columns = 4
	_trade_grid.add_theme_constant_override(&"h_separation", 18)
	_trade_grid.add_theme_constant_override(&"v_separation", 2)
	_trade_page.add_child(_trade_grid)
	%ShipsPage.add_sibling(_trade_page)


## What the company has bought and sold here (since it began keeping count),
## each commodity with what an industry building for it here would have been
## worth a month, the most first: the commodities best worth a building.
func _refresh_trade() -> void:
	for child in _trade_grid.get_children():
		_trade_grid.remove_child(child)
		child.queue_free()
	var summary := GameState.port_trade_summary(port_id)
	var rows: Array = summary.rows
	var settings := Hub.industry_settings()
	var hub := GameState.hub_at(port_id)
	var boost := float(Hub.settings().get("hq_multiplier", 1.5)) if hub != null and hub.is_hq else 1.0
	var terms := "An industry building here makes its commodity %d%% cheaper to buy and %d%% more expensive to sell here, and its deliveries earn %d%% more XP" % [
		roundi(float(settings.get("buy_discount", 0.2)) * boost * 100.0), roundi(float(settings.get("sell_bonus", 0.2)) * boost * 100.0), roundi(float(settings.get("xp_bonus", 0.5)) * boost * 100.0)]
	var where := " (built at your HQ or a hub)." if hub == null else "."
	if rows.is_empty():
		_trade_note.text = "Your ships haven't bought or sold anything here yet. %s%s" % [terms, where]
		reset_size.call_deferred()
		return
	_trade_note.text = "Your trade here over the last %s. %s%s The last column is what a building for each would have saved and added, a month." % [
		("%d days" % roundi(float(summary.days))) if float(summary.days) >= 1.5 else "day", terms, where]
	for title: String in ["", "Bought here", "Sold here", "Industry a month"]:
		_add_trade_cell(title, &"DimLabel")
	for row: Dictionary in rows:
		var commodity := GameData.commodity(str(row.id))
		var units := str(commodity.get("units", "units"))
		_add_trade_cell(str(commodity.get("name", row.id)), &"")
		_add_trade_cell("%s %s, %s" % [Fmt.short(int(row.bought)), units, Fmt.money_short(roundi(float(row.spent)))] if int(row.bought) > 0 else "-", &"")
		_add_trade_cell("%s %s, %s" % [Fmt.short(int(row.sold)), units, Fmt.money_short(roundi(float(row.earned)))] if int(row.sold) > 0 else "-", &"")
		_add_trade_cell("Built" if bool(row.built) else "+%s" % Fmt.money_short(roundi(float(row.industry))), &"DimLabel" if bool(row.built) else &"GainLabel")
	reset_size.call_deferred()


func _add_trade_cell(text: String, variation: StringName) -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", MARKET_FONT_SIZE)
	_trade_grid.add_child(label)

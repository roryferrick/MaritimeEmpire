# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## Lists purchasable ship models from data/ship_models.json, in tabs (a tab per
## company type, TYPE_ROWS, then Service) of sections by category, laid out in
## rows with the sections of a row side by side, each as wide as its models (up
## to 5 cards a row). A type the company lacks has a lock on its tab, its cards
## faded, and a note over them with its division's price and an Open a
## division button (CompanyTypeDialog); the Shop opens on the
## company's first type. A row too wide for the screen stacks its
## sections. Each section title runs through its models' map colors, smallest
## ship first, and each card's name is in its model's map color, above a
## picture of the ship as it looks on the map (see ShipPicture). Each card
## shows how many of the model the company owns (tugs: of the slots its route
## ports give). Each section sits on a faint tint of its
## ship line's color. A red dot marks every Buy button that can be used right
## now; hovering one the company can't afford shows a small note saying so.
## The Tugs section has Buy All Tugs (filling every free tug slot money allows).

## [title, ship_models.json category]
const SECTIONS := [["Container ships", "container"], ["Ore carriers", "ore"], ["Breakbulk carriers", "breakbulk"], ["Grain carriers", "grain"],
	["Livestock carriers", "livestock"], ["Fresh produce carriers", "produce"], ["Tankers", "tanker"], ["Gas carriers", "gas"], ["Car carriers", "vehicles"], ["Boat carriers", "boat_carriers"], ["Recovery boats", "recovery"], ["Fishing boats", "fishing"], ["Crabbing boats", "crabbing"], ["Tugs (two per route port)", "tug"],
	["Icebreakers (for seasonal ice)", "icebreaker"], ["Seafood carriers", "seafood"], ["Ocean cruisers", "cruise_ocean"], ["Expedition cruisers", "cruise_expedition"], ["Survey vessels", "survey"], ["Deep-sea motherships", "mothership"]]
## Each company type's tab (game_config company_types: tab is its title): its
## rows, each row its sections side by side (by category). The service boats
## have the last tab, SERVICE_ROWS.
const TYPE_ROWS := {
	cargo = [["container"], ["ore"], ["breakbulk"]],
	vehicles = [["vehicles"], ["boat_carriers"]],
	agriculture = [["grain"], ["livestock"], ["produce"]],
	tankers = [["tanker"], ["gas"]],
	seafood = [["fishing"], ["crabbing"], ["seafood"]],
	cruises = [["cruise_ocean"], ["cruise_expedition"]],
	research = [["survey"], ["mothership"]],
}
const SERVICE_ROWS := [["recovery", "tug"], ["icebreaker"]]
## Cards a section shows across, fewer if they don't fit. Six fit across a row
## beside the open activity log at the default window size: cards are
## CARD_WIDTH wide (plus padding), and long ship names and Buy button texts wrap.
const MAX_COLUMNS := 5
const CARD_GAP := 12
const SECTION_GAP := 12
const CARD_WIDTH := 128.0
const CARD_MAX_WIDTH := 175.0
const CARD_LABEL_WIDTH := 40.0
## Each card shows the model's map art under its name, in a strip this tall;
## see _picture_length() for how long each is.
const SHIP_PICTURE_HEIGHT := 40.0
const SHIP_PICTURE_MAX_LENGTH := 118.0
const SHIP_PICTURE_SIZE_POWER := 0.5
## Ship names and section titles use the models' map colors, brightened to at
## least this luminance.
const MIN_TEXT_LUMINANCE := 0.5
## Each section sits on a faint tint of its ship line's color, with this much
## padding inside.
const SECTION_TINT := 0.08
const SECTION_PADDING := 10

## What each ice class lets an Expedition cruiser reach (ship_models.json cruise ice).
const ICE_TEXT := {polar_light = "The Antarctic stations and icebound Arctic ports in their open season",
	polar = "Those, and the Arctic routes in their open season without an icebreaker",
	polar_long = "Those, with the longest polar season (3 weeks earlier and later)"}

const NamePopupScene := preload("res://scenes/popups/name_popup.tscn")

var _buy_buttons: Dictionary = {}  # model id -> Button
var _owned_labels: Dictionary = {}  # model id -> Label
var _price_labels: Dictionary = {}  # model id -> Label
var _buy_alerts: Dictionary = {}  # model id -> AlertDot, shown while it can be bought
var _grids: Array[GridContainer] = []
## Each row of sections ([its grid, its sections' card grids]), and the Buy All Tugs button.
var _rows: Array = []
var _buy_all_tugs := Button.new()
## The "can't afford" note shown above a hovered Buy button, and that model's id ("" when none is hovered).
var _hint := PanelContainer.new()
var _yard_bar := HBoxContainer.new()
var _orders_label := Label.new()
var _cancel_menu := MenuButton.new()
var _hint_label := Label.new()
var _hovered := ""
## Money or the fleet changed since the cards were last updated.
var _dirty := false
var _tabs: TabContainer = null
## Per company type: its tab's index, its rows of sections, and the note over
## them while the company lacks it ([panel, label, Choose button]).
var _type_tabs := {}
var _type_rows := {}
var _type_banners := {}
var _lock_icon: Texture2D = null


func _ready() -> void:
	var titles := {}
	for section: Array in SECTIONS:
		titles[section[1]] = section[0]
	_add_yard_bar()
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%Items.add_child(tabs)
	_tabs = tabs
	var tab_list := []  # [title, rows, company type id ("" for Service), and a coming-soon type's id]
	for type: Dictionary in Progression.company_types():
		tab_list.append([str(type.get("tab", type.name)), TYPE_ROWS.get(type.id, [type.categories]), str(type.id)])
	for type: Dictionary in Progression.upcoming_types():  # (Its ships to look at, not to buy yet.)
		tab_list.append(["%s (coming soon)" % type.get("tab", type.name), (type.categories as Array).map(func(category: String) -> Array: return [category]), "", type.id])
	tab_list.append(["Service", SERVICE_ROWS, ""])
	var row_tabs := []  # [row's categories, its tab's box, its company type id]
	for tab: Array in tab_list:
		var page := VBoxContainer.new()
		page.name = tab[0]
		page.add_theme_constant_override(&"separation", SECTION_GAP)
		tabs.add_child(page)
		if not str(tab[2]).is_empty():
			_type_tabs[tab[2]] = tabs.get_tab_count() - 1
			_type_rows[tab[2]] = []
			page.add_child(_type_banner(tab[2]))
		elif tab.size() > 3:
			page.add_child(_coming_banner(tab[3]))
		for row_categories: Array in tab[1]:
			row_tabs.append([row_categories, page, tab[2]])
	for pair: Array in row_tabs:
		var row_categories: Array = pair[0]
		var row := GridContainer.new()
		row.columns = row_categories.size()
		row.add_theme_constant_override(&"h_separation", SECTION_GAP)
		row.add_theme_constant_override(&"v_separation", SECTION_GAP)
		(pair[1] as Control).add_child(row)
		if _type_rows.has(pair[2]):
			(_type_rows[pair[2]] as Array).append(row)
		var row_grids: Array[GridContainer] = []
		for category: String in row_categories:
			var box := _section_box(category, row)
			var header := HBoxContainer.new()
			header.add_theme_constant_override(&"separation", 10)
			header.add_child(_section_title(titles[category], category))
			if category == "tug":
				_buy_all_tugs.theme_type_variation = &"ShopCardButton"
				_buy_all_tugs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				_buy_all_tugs.pressed.connect(GameState.buy_all_tugs)
				header.add_child(_buy_all_tugs)
			box.add_child(header)
			var grid := GridContainer.new()
			grid.add_theme_constant_override(&"h_separation", CARD_GAP)
			grid.add_theme_constant_override(&"v_separation", CARD_GAP)
			_grids.append(grid)
			row_grids.append(grid)
			box.add_child(grid)
			for model: Dictionary in GameData.ship_models + GameData.upcoming_models:
				if model.get("category", "container") == category:
					grid.add_child(_make_card(model, model.get("coming_soon", false)))
			grid.columns = clampi(grid.get_child_count(), 1, MAX_COLUMNS)
		_rows.append([row, row_grids])
	# Money changes many times a second while ships refuel; the cards catch up
	# once a frame, and only while the Shop is open.
	GameState.money_changed.connect(func(_money: int) -> void: _dirty = true)
	GameState.ships_changed.connect(func() -> void: _dirty = true)
	GameState.company_types_changed.connect(func() -> void: _dirty = true)
	GameState.company_types_changed.connect(func() -> void: _dirty = true)
	if _type_tabs.has(GameState.company.start_type()):
		tabs.current_tab = _type_tabs[GameState.company.start_type()]
	visibility_changed.connect(func() -> void:
		_dirty = true
		_fit_columns.call_deferred())
	resized.connect(_fit_columns)
	_hint.theme_type_variation = &"MapPopup"
	_hint.top_level = true
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_hint_label.add_theme_font_size_override(&"font_size", 13)
	_hint.add_child(_hint_label)
	add_child(_hint)
	_update_cards()


## Above the tabs: the ships on order (Shipyards) and the way into the second-hand market.
func _add_yard_bar() -> void:
	_yard_bar.add_theme_constant_override(&"separation", 12)
	%Items.add_child(_yard_bar)
	_orders_label.theme_type_variation = &"DimLabel"
	_orders_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_orders_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_yard_bar.add_child(_orders_label)
	_cancel_menu.text = "Cancel an order"
	_cancel_menu.get_popup().index_pressed.connect(func(index: int) -> void: GameState.cancel_order(int(_cancel_menu.get_popup().get_item_metadata(index))))
	_yard_bar.add_child(_cancel_menu)
	var used := Button.new()
	used.text = "Second-hand ships"
	used.tooltip_text = "Ready ships the shipping firms are selling, cheaper by age and condition."
	used.pressed.connect(func() -> void: PopupHost.find(self).open(UsedMarketPopup.new()))
	_yard_bar.add_child(used)
	GameState.shipyards.changed.connect(_update_yard_bar)
	_update_yard_bar()


func _update_yard_bar() -> void:
	var orders: Array = GameState.company.orders
	var parts := PackedStringArray()
	_cancel_menu.get_popup().clear()
	for order: Dictionary in orders:
		parts.append("%s (%s) from %s, %s%s" % [str(order.name), str(GameData.get_ship_model(str(order.model)).get("name", "")), str(GameState.shipyards.yard(str(order.yard)).get("name", "")), Fmt.calendar_short(int(order.due)), " (late)" if bool(order.get("late", false)) else ""])
		_cancel_menu.get_popup().add_item(str(order.name))
		_cancel_menu.get_popup().set_item_metadata(_cancel_menu.get_popup().item_count - 1, int(order.id))
	_orders_label.text = "Ships of Feeder size and up are ordered from a shipyard (a %d%% deposit, the rest on delivery at the yard) and built over months; small boats and tugs are bought outright. %s" % [roundi(GameState.shipyards.deposit_share() * 100.0), "On order: " + "; ".join(parts) + "." if not parts.is_empty() else "Nothing on order; %d second-hand ships for sale." % GameState.shipyards.listings.size()]
	_cancel_menu.visible = not orders.is_empty()


## Each row's sections side by side if they fit across, else one under
## another; each section as many cards across as it has (up to MAX_COLUMNS),
## fewer if even it alone doesn't fit.
func _fit_columns() -> void:
	var room := size.x - 60.0  # Page margins and the scrollbar.
	for entry: Array in _rows:
		var row: GridContainer = entry[0]
		var grids: Array = entry[1]
		# Cards widen (up to CARD_MAX_WIDTH) to share out a row with fewer ships.
		var cards := 0
		var fixed := SECTION_GAP * (grids.size() - 1)
		for grid: GridContainer in grids:
			var count := mini(grid.get_child_count(), MAX_COLUMNS)
			cards += count
			fixed += 2 * SECTION_PADDING + (count - 1) * CARD_GAP
		var width := clampf((room - fixed) / maxf(cards, 1.0), CARD_WIDTH, CARD_MAX_WIDTH)
		for grid: GridContainer in grids:
			var fits := floori((room - 2 * SECTION_PADDING + CARD_GAP) / (CARD_WIDTH + CARD_GAP))
			grid.columns = clampi(mini(grid.get_child_count(), fits), 1, MAX_COLUMNS)
			for card: Control in grid.get_children():
				card.custom_minimum_size.x = width
		# Side by side if the row (as laid out) fits across, else stacked (narrow cards again).
		row.columns = grids.size()
		if row.get_combined_minimum_size().x > room:
			row.columns = 1
			for grid: GridContainer in grids:
				for card: Control in grid.get_children():
					card.custom_minimum_size.x = CARD_WIDTH


## A section's panel, on a faint tint of its ship line's color (see
## GameData.category_color()), added to its row; returns the box inside it.
func _section_box(category: String, row: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GameData.category_color(category), SECTION_TINT)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(SECTION_PADDING)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.size_flags_vertical = Control.SIZE_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	panel.add_child(box)
	row.add_child(panel)
	return box

## A section title shaded letter by letter through the map colors of the
## category's models, from the smallest ship's (first letter) to the biggest's
## (last letter).
func _section_title(text: String, category: String) -> Control:
	var models := (GameData.ship_models + GameData.upcoming_models).filter(func(model: Dictionary) -> bool: return model.get("category", "container") == category)
	models.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("map_size", [0])[0]) < float(b.get("map_size", [0])[0]))
	var gradient := Gradient.new()
	gradient.remove_point(1)
	gradient.set_color(0, _map_color(models[0]) if not models.is_empty() else Color.WHITE)
	for i in range(1, models.size()):
		gradient.add_point(float(i) / (models.size() - 1), _map_color(models[i]))
	var letters := text.replace(" ", "").length()
	var bbcode := ""
	var n := 0
	for character in text:
		if character == " ":
			bbcode += character
			continue
		var color := gradient.sample(float(n) / maxi(letters - 1, 1))
		bbcode += "[color=#%s]%s[/color]" % [color.to_html(false), character]
		n += 1
	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.scroll_active = false
	title.add_theme_font_size_override(&"normal_font_size", get_theme_font_size(&"font_size", &"HeaderLabel"))
	title.text = bbcode
	return title


## A model's map color for text: dark ones (the Mammoth's brown, the
## Supertanker's blue) are lifted toward white until they reach
## MIN_TEXT_LUMINANCE, so they read on the dark cards.
static func _map_color(model: Dictionary) -> Color:
	var color := Color.from_string(model.get("map_color", "#ffffff"), Color.WHITE)
	var luminance := color.get_luminance()
	if luminance < MIN_TEXT_LUMINANCE:
		color = color.lerp(Color.WHITE, (MIN_TEXT_LUMINANCE - luminance) / (1.0 - luminance))
	return color


## How long (pixels) a model's picture is: SHIP_PICTURE_MAX_LENGTH for the
## longest model on the map, and the others by SHIP_PICTURE_SIZE_POWER of their
## share of that, so small ships stay a good size (a Scooter 20 is a quarter
## of a Mammoth's length on the map, half here).
static func _picture_length(model: Dictionary) -> float:
	var longest := 0.0
	for other: Dictionary in GameData.ship_models:
		longest = maxf(longest, _map_length(other))
	return SHIP_PICTURE_MAX_LENGTH * pow(_map_length(model) / longest, SHIP_PICTURE_SIZE_POWER)


## A model's length on the map (map_size length plus its bow).
static func _map_length(model: Dictionary) -> float:
	var dims: Array = model.get("map_size", [14, 6])
	return float(dims[0]) + float(dims[1]) * MapView.BOW_LENGTH_FACTOR


## A model's card; a coming-soon model's (coming) shows its price and a
## greyed Coming soon in place of Buy, and isn't counted by _update_cards().
func _make_card(model: Dictionary, coming := false) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ShopCard"
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)

	var title := Label.new()
	title.theme_type_variation = &"ShopCardTitle"
	title.text = model.get("name", model.id)
	title.add_theme_color_override(&"font_color", _map_color(model))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var picture := ShipPicture.new(model, _picture_length(model))
	picture.custom_minimum_size.y = SHIP_PICTURE_HEIGHT
	box.add_child(picture)

	var tank := float(model.get("fuel_tank", 0))
	var rows := [
		["Speed", "%s nm/s" % Fmt.decimal(float(model.get("speed_nm_per_s", 0)), 2)],
		["Hold", GameData.cargo_text(model)],
		["Carries", GameData.cargo_names(model)],
		["Range", "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))],
		["Tank", "%s · %s" % [Fmt.short(tank), Fmt.rough_duration(tank / float(model.get("fuel_per_s", 1)))]],
		["Stop", Fmt.duration(float(model.get("dock_s", 0)))],
		["Price", ""],
		["Owned", ""],
	]
	if model.has("cruise"):
		var cruise: Dictionary = model.cruise
		rows[1] = ["Guests", "%s (a balanced cabin mix)" % Fmt.thousands(int(cruise.get("guests", 0)))]
		rows[2] = ["Decks", "%d amenity slots%s" % [int(cruise.get("deck_slots", 0)), " and a helipad" if cruise.get("helipad", false) else ""]]
		if not str(cruise.get("ice", "")).is_empty():
			rows.insert(3, ["Ice", ICE_TEXT.get(str(cruise.ice), "")])
	elif model.has("research"):
		var reach := Research.depth_of(model)
		var sites := Research.site_ids().filter(func(id: String) -> bool: return int(Research.site(id).depth_m) <= reach).size()
		rows[1] = ["Dives to", "%s m: %d of the %d sites" % [Fmt.thousands(reach), sites, Research.site_ids().size()]]
		rows[2] = ["Gear", "%d slots for %s" % [Research.slots_of(model), ", ".join(PackedStringArray(Research.gear_list().filter(func(info: Dictionary) -> bool: return Research.can_fit(model, info.id)).map(func(info: Dictionary) -> String: return str(info.name).to_lower())))]]
	elif model.get("recovery", false):
		rows[1] = ["Carries", GameData.carries_text(model)]
		rows[2] = ["Job", "Recovers lost ships"]
		rows.remove_at(3)
	elif str(model.get("category", "")) == "seafood":
		rows[2] = ["Carries", "All %d kinds of seafood, crab and fish, in crates; your boats' catch from the cold stores" % (model.get("cargo", []) as Array).size()]
	elif model.has("fishing"):
		var gear: Dictionary = model.fishing
		rows[1] = ["Hold", "%s crates" % Fmt.thousands(int(model.get("capacity", 0)))]
		rows[2] = ["Gear", "%s · %d crew · %s" % [Fisheries.gear_text(gear), int(gear.get("crew", 0)), Fisheries.trip_text(gear)]]
		rows.insert(3, ["Works", " and ".join((gear.get("depth", []) as Array).map(func(depth: String) -> String: return {inshore = "inshore", offshore = "offshore", deep = "deep-water"}.get(depth, depth))) + " grounds, from any port"])
	elif model.get("tug", false):
		rows[1] = ["Job", "Pushes or drags your lost ships back into port"]
		rows[2] = ["Reach", "%d nm out from its port; two together tow twice as fast" % int(model.get("reach_nm", 0))]
		rows[3] = ["Based", "Two at each port on your routes, spread evenly"]
	elif not str(model.get("icebreaker", "")).is_empty():
		var areas: Array = GameState.icebreaking.areas().filter(func(item: Dictionary) -> bool:
			return (model.get("seaway", false) or item.id != "great_lakes") and (item.get("needs", "") != "nuclear" or model.icebreaker == "nuclear")).map(
				func(item: Dictionary) -> String: return item.name)
		rows[1] = ["Job", "Leads your ships through seasonal ice in convoys"]
		rows[2] = ["Needed", "Only in winter ice: %s" % ", ".join(areas)]
		rows.remove_at(3)
	# Its crew, by its tier, and their wages each period (see GameState.crew_wages()).
	var crew := GameState.crew_of(model)
	rows.insert(rows.size() - 2, ["Officers", "Captain" if int(crew[0]) <= 1 else "Captain + %d %s" % [int(crew[0]) - 1, "mate" if int(crew[0]) == 2 else "mates"]])
	rows.insert(rows.size() - 2, ["Crew", str(crew[1])])
	rows.insert(rows.size() - 2, ["Wages", "%s / %d days" % [Fmt.money_short(GameState.crew_wages(model)),
		int(GameData.config.get("crew", {}).get("period_days", 14))]])
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 6)
		box.add_child(line)
		var name_label := Label.new()
		name_label.theme_type_variation = &"ShopCardDim"
		name_label.custom_minimum_size.x = CARD_LABEL_WIDTH
		name_label.text = row[0]
		line.add_child(name_label)
		var value_label := Label.new()
		value_label.theme_type_variation = &"ShopCardText"
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.text = row[1]
		line.add_child(value_label)
		if row[0] == "Price":
			if coming:
				value_label.text = _price_text(int(model.get("price", 0)))
			else:
				_price_labels[model.id] = value_label
		if row[0] == "Owned":
			if coming:
				line.visible = false
			else:
				_owned_labels[model.id] = value_label

	var buy := Button.new()
	buy.theme_type_variation = &"ShopCardButton"
	buy.custom_minimum_size = Vector2(0, 34)
	buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	if coming:
		buy.text = "Coming soon"
		buy.disabled = true
		box.add_child(buy)
		return card
	buy.pressed.connect(_on_buy_pressed.bind(model.id))
	buy.mouse_entered.connect(_on_buy_hovered.bind(model.id))
	buy.mouse_exited.connect(_on_buy_hovered.bind(""))
	box.add_child(buy)
	_buy_buttons[model.id] = buy
	var alert := AlertDot.new(5.0, Vector2(9, 9))
	buy.add_child(alert)
	_buy_alerts[model.id] = alert
	return card



func _update_cards() -> void:
	for model_id: String in _buy_buttons:
		var model := GameData.get_ship_model(model_id)
		var owned := GameState.owned_count(model_id)
		var price := GameState.ship_price(model_id)
		_price_labels[model_id].text = _price_text(price)
		if model.get("tug", false):
			var off := roundi(GameState.tug_discount() * 100.0)
			_price_labels[model_id].text += " (%d%% off: animals seen)" % off if off > 0 else ""
			_price_labels[model_id].tooltip_text = "Tugs are %d%% cheaper for every third of the field guide's animals you've seen (click them on the map), up to %d%%." % [roundi(GameState.TUG_ANIMAL_DISCOUNT * 100.0), roundi(GameState.TUG_ANIMAL_DISCOUNT * 300.0)]
			_price_labels[model_id].mouse_filter = Control.MOUSE_FILTER_PASS
		elif price < int(model.get("price", 0)):
			_price_labels[model_id].text += " for your first, then %s" % _price_text(int(model.price))
		if model.get("tug", false):
			_owned_labels[model_id].text = "%d / %d (%d per route port)" % [owned, GameState.tug_slots(), GameState.tugs_per_port()]
		else:
			_owned_labels[model_id].text = "%d owned" % owned
		var button: Button = _buy_buttons[model_id]
		if not Progression.can_buy_model(model):
			button.text = "Comes with %s" % Progression.type_name(Progression.type_of_model(model))
		elif model.get("tug", false) and owned >= GameState.tug_slots():
			button.text = "Route to more ports for more"
		else:
			button.text = "Order…" if Shipyards.is_ordered(model) else "Buy"
		var error := GameState.buy_error(model_id)
		button.disabled = not error.is_empty()
		_buy_alerts[model_id].visible = error.is_empty()
		button.tooltip_text = "" if _short_of_money(model_id) > 0 else error
	_update_types()
	var tugs := GameState.tugs_to_buy()
	_buy_all_tugs.text ="Buy all tugs (%d)" % tugs if tugs > 0 else "Buy all tugs"
	_buy_all_tugs.disabled = tugs == 0
	var tug := GameState.tug_model_id()
	_buy_all_tugs.tooltip_text = "Fills every free tug slot your money allows, each named for you and based where it's needed." if tugs > 0 else (GameState.buy_error(tug) if not tug.is_empty() and not GameState.buy_error(tug).is_empty() else "Every tug slot is full.")
	_update_hint()


## The note over a company type's sections while the company lacks it: its
## icon, its price, and a button to open the division.
func _type_banner(type_id: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(CompanyTypeIcon.type_color(type_id), 0.12)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	panel.add_child(row)
	var icon := CompanyTypeIcon.new(type_id)
	icon.custom_minimum_size = Vector2(30, 30)
	row.add_child(icon)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var choose := Button.new()
	choose.text = "Open a division"
	choose.pressed.connect(func() -> void: CompanyTypeDialog.open(self))
	row.add_child(choose)
	_type_banners[type_id] = [panel, label, choose]
	return panel


## Each type's tab: a lock and faded cards under its note while the company
## lacks the type; plain once it has it.
func _update_types() -> void:
	for type_id: String in _type_tabs:
		var has := GameState.company.has_type(type_id)
		var banner: Array = _type_banners[type_id]
		(banner[0] as Control).visible = not has
		var name := Progression.type_name(type_id)
		(banner[1] as Label).text = "Your company isn't in %s. Open a %s division (%s) to buy its ships." % [name, name, Fmt.money(GameState.division_price())]
		for row: Control in _type_rows[type_id]:
			row.modulate.a = 1.0 if has else 0.5
		_tabs.set_tab_icon(_type_tabs[type_id], null if has else _lock())
		var tab_name := str(Progression.company_type(type_id).get("tab", name))
		_tabs.set_tab_title(_type_tabs[type_id], "%s %.1f★" % [tab_name, GameState.ratings.stars(GameState.company, type_id)] if has else tab_name)


## The note over a coming-soon type's ships (Cruises, until its voyages are built).
func _coming_banner(type_id: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(CompanyTypeIcon.type_color(type_id), 0.12)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override(&"panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	panel.add_child(row)
	var icon := CompanyTypeIcon.new(type_id)
	icon.custom_minimum_size = Vector2(30, 30)
	row.add_child(icon)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s are coming soon: here are the ships. %s" % [Progression.type_name(type_id), Progression.company_type(type_id).get("blurb", "")]
	row.add_child(label)
	return panel


## A small padlock for a locked type's tab.
func _lock() -> Texture2D:
	if _lock_icon == null:
		var image := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		var color := Color(0.85, 0.87, 0.9)
		for y in 16:
			for x in 16:
				var shackle := Vector2(x + 0.5, y + 0.5).distance_to(Vector2(8, 7))
				if (y >= 7 and y <= 14 and x >= 3 and x <= 12) or (y < 7 and shackle >= 3.0 and shackle <= 4.6):
					image.set_pixel(x, y, color)
		_lock_icon = ImageTexture.create_from_image(image)
	return _lock_icon


func _on_buy_pressed(model_id: String) -> void:
	var popup: NamePopup = NamePopupScene.instantiate()
	popup.model_id = model_id
	PopupHost.find(self).open(popup)


## How much more money buying this model needs, or 0 if money isn't what's
## stopping it (it's affordable, or locked).
func _short_of_money(model_id: String) -> int:
	var model := GameData.get_ship_model(model_id)
	if not Progression.can_buy_model(model) or model.get("tug", false) and GameState.owned_count(model_id) >= GameState.tug_slots():
		return 0
	if Shipyards.is_ordered(model):  # (The deposit, at the cheapest yard.)
		var offers: Array = GameState.shipyards.yards_for(model)
		return maxi(roundi(int(offers[0].price) * GameState.shipyards.deposit_share()) - GameState.money, 0) if not offers.is_empty() else 0
	return maxi(GameState.ship_price(model_id) - GameState.money, 0)


func _on_buy_hovered(model_id: String) -> void:
	_hovered = model_id
	_update_hint()


## Shows the note above the hovered Buy button if the company can't afford it.
func _update_hint() -> void:
	var short := _short_of_money(_hovered) if not _hovered.is_empty() else 0
	_hint.visible = short > 0 and is_visible_in_tree()
	if not _hint.visible:
		return
	_hint_label.text = "You can't afford this ship (%s short)." % Fmt.money(short)
	_hint.reset_size()
	var button: Button = _buy_buttons[_hovered]
	var hint_size := _hint.get_combined_minimum_size()
	_hint.global_position = button.global_position + Vector2((button.size.x - hint_size.x) / 2.0, -hint_size.y - 6.0)


func _process(_delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(_delta)
	MapView._prof("proc.shop_screen", t_x)

func _process_timed(_delta: float) -> void:
	if _dirty and is_visible_in_tree():
		_dirty = false
		_update_cards()
	elif _hint.visible:
		_update_hint()  # Follows the button if the list scrolls.


## A price short enough for a card: "$250,000", "$15M", "$1.5M".
static func _price_text(price: int) -> String:
	return Fmt.money(price) if price < 1000000 else "$" + Fmt.short(price)

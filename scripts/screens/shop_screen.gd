# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## Lists purchasable ship models from data/ship_models.json, in sections by
## category, laid out in rows (ROWS) with the sections of a row side by side,
## each as wide as its models (up to 6 cards a row): container ships; ore and
## grain carriers; livestock carriers and tankers; vehicle carriers and recovery
## boats; icebreakers and tugs. A row too wide for the screen stacks its
## sections. Each section title runs through its models' map colors, smallest
## ship first, and each card's name is in its model's map color, above a
## picture of the ship as it looks on the map (see ShipPicture). Each card
## shows how many of the model the company's level allows, and the level that
## unlocks the model or its next slot. Each section sits on a faint tint of its
## ship line's color. A red dot marks every Buy button that can be used right
## now; hovering one the company can't afford shows a small note saying so.
## The Tugs section has Buy All Tugs (filling every free slot money allows).

## [title, ship_models.json category]
const SECTIONS := [["Container ships", "container"], ["Ore carriers", "ore"], ["Grain carriers", "grain"],
	["Livestock carriers", "livestock"], ["Tankers", "tanker"], ["Vehicle carriers", "vehicles"], ["Recovery boats", "recovery"], ["Tugs (two per route port)", "tug"],
	["Icebreakers (for seasonal ice)", "icebreaker"], ["Fishing boats", "fishing"], ["Crabbing boats", "crabbing"], ["Seafood carriers", "seafood"]]
## The sections side by side on each row (by category).
const ROWS := [["container"], ["ore", "grain"], ["livestock", "tanker"], ["vehicles", "recovery"], ["icebreaker", "tug"], ["fishing", "crabbing"], ["seafood"]]
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
var _hint_label := Label.new()
var _hovered := ""
## Money, the fleet or the level changed since the cards were last updated.
var _dirty := false


func _ready() -> void:
	var titles := {}
	for section: Array in SECTIONS:
		titles[section[1]] = section[0]
	for row_categories: Array in ROWS:
		var row := GridContainer.new()
		row.columns = row_categories.size()
		row.add_theme_constant_override(&"h_separation", SECTION_GAP)
		row.add_theme_constant_override(&"v_separation", SECTION_GAP)
		%Items.add_child(row)
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
			for model: Dictionary in GameData.ship_models:
				if model.get("category", "container") == category:
					grid.add_child(_make_card(model))
			grid.columns = clampi(grid.get_child_count(), 1, MAX_COLUMNS)
		_rows.append([row, row_grids])
	# Money changes many times a second while ships refuel; the cards catch up
	# once a frame, and only while the Shop is open.
	GameState.money_changed.connect(func(_money: int) -> void: _dirty = true)
	GameState.ships_changed.connect(func() -> void: _dirty = true)
	GameState.company_leveled.connect(func(_level: int, _unlocks: Array[String]) -> void: _dirty = true)
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
	var models := GameData.ship_models.filter(func(model: Dictionary) -> bool: return model.get("category", "container") == category)
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


func _make_card(model: Dictionary) -> Control:
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
	if model.get("recovery", false):
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
			_price_labels[model.id] = value_label
		if row[0] == "Owned":
			_owned_labels[model.id] = value_label

	var buy := Button.new()
	buy.theme_type_variation = &"ShopCardButton"
	buy.custom_minimum_size = Vector2(0, 34)
	buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	buy.size_flags_vertical = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
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
	var level := GameState.company_level()
	for model_id: String in _buy_buttons:
		var model := GameData.get_ship_model(model_id)
		var slots := _slots(model)
		var max_owned := int(model.get("max_owned", 0))
		var owned := GameState.owned_count(model_id)
		var next := Progression.next_slot_level(model, level)
		var price := GameState.ship_price(model_id)
		_price_labels[model_id].text = _price_text(price)
		if price < int(model.get("price", 0)):
			_price_labels[model_id].text += " for your first, then %s" % _price_text(int(model.price))
		_owned_labels[model_id].text = "%d / %d" % [owned, slots]
		if model.get("tug", false):
			_owned_labels[model_id].text += " (2 per route port)"
		elif slots < max_owned and level >= Progression.unlock_level(model):
			_owned_labels[model_id].text += " (max %d)" % max_owned
		var button: Button = _buy_buttons[model_id]
		if level < Progression.unlock_level(model):
			button.text = "Unlocks at level %d" % next
		elif owned < slots:
			button.text = "Buy"
		else:
			button.text = "Route to more ports for more" if model.get("tug", false) else ("Limit reached" if next < 0 else "Next slot at level %d" % next)
		var error := GameState.buy_error(model_id)
		button.disabled = not error.is_empty()
		_buy_alerts[model_id].visible = error.is_empty()
		button.tooltip_text = "" if _short_of_money(model_id) > 0 else error
	var tugs := GameState.tugs_to_buy()
	_buy_all_tugs.text = "Buy all tugs (%d)" % tugs if tugs > 0 else "Buy all tugs"
	_buy_all_tugs.disabled = tugs == 0
	var tug := GameState.tug_model_id()
	_buy_all_tugs.tooltip_text = "Fills every free tug slot your money allows, each named for you and based where it's needed." if tugs > 0 else (GameState.buy_error(tug) if not tug.is_empty() and not GameState.buy_error(tug).is_empty() else "Every tug slot is full.")
	_update_hint()


func _on_buy_pressed(model_id: String) -> void:
	var popup: NamePopup = NamePopupScene.instantiate()
	popup.model_id = model_id
	PopupHost.find(self).open(popup)


## How much more money buying this model needs, or 0 if money isn't what's
## stopping it (it's affordable, locked or out of slots).
func _short_of_money(model_id: String) -> int:
	var model := GameData.get_ship_model(model_id)
	var slots := _slots(model)
	if GameState.owned_count(model_id) >= slots:
		return 0
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


## How many of a model the company can own now: its level's slots, or for
## tugs two for each port on its routes.
func _slots(model: Dictionary) -> int:
	if model.get("tug", false):
		return GameState.tug_slots() if GameState.company_level() >= Progression.unlock_level(model) else 0
	return Progression.model_slots(model, GameState.company_level())


## A price short enough for a card: "$250,000", "$15M", "$1.5M".
static func _price_text(price: int) -> String:
	return Fmt.money(price) if price < 1000000 else "$" + Fmt.short(price)

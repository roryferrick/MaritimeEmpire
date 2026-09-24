extends Control
## Lists purchasable ship models from data/ship_models.json, in sections by
## category: container ships, ore, grain and livestock carriers, tankers,
## vehicle carriers, then recovery boats. Each section
## title runs through its models' map colors, smallest ship first, and each
## card's name is in its model's map color. Each card shows how many of the
## model the company's level allows, and the level that unlocks the model or its
## next slot. Each section sits on a faint tint of its ship line's color. A red
## dot marks every Buy button that can be used right now;
## hovering one the company can't afford shows a small note saying so.

## [title, ship_models.json category]
const SECTIONS := [["Container ships", "container"], ["Ore carriers", "ore"], ["Grain carriers", "grain"],
	["Livestock carriers", "livestock"], ["Tankers", "tanker"], ["Vehicle carriers", "vehicles"], ["Recovery boats", "recovery"]]
## Cards per row, fewer if they don't fit. Five fit beside the activity log
## at the default window size.
const MAX_COLUMNS := 5
const CARD_GAP := 12
const CARD_WIDTH := 176.0
const CARD_LABEL_WIDTH := 44.0
## Ship names and section titles use the models' map colors, brightened to at
## least this luminance.
const MIN_TEXT_LUMINANCE := 0.5
## Each section sits on a faint tint of its ship line's color, with this much
## padding inside.
const SECTION_TINT := 0.08
const SECTION_PADDING := 12

const NamePopupScene := preload("res://scenes/popups/name_popup.tscn")

var _buy_buttons: Dictionary = {}  # model id -> Button
var _owned_labels: Dictionary = {}  # model id -> Label
var _price_labels: Dictionary = {}  # model id -> Label
var _buy_alerts: Dictionary = {}  # model id -> AlertDot, shown while it can be bought
var _grids: Array[GridContainer] = []
## The "can't afford" note shown above a hovered Buy button, and that model's id ("" when none is hovered).
var _hint := PanelContainer.new()
var _hint_label := Label.new()
var _hovered := ""


func _ready() -> void:
	for section: Array in SECTIONS:
		var box := _section_box(section[1])
		box.add_child(_section_title(section[0], section[1]))
		var grid := GridContainer.new()
		grid.columns = MAX_COLUMNS
		grid.add_theme_constant_override(&"h_separation", CARD_GAP)
		grid.add_theme_constant_override(&"v_separation", CARD_GAP)
		_grids.append(grid)
		box.add_child(grid)
		for model: Dictionary in GameData.ship_models:
			if model.get("category", "container") == section[1]:
				grid.add_child(_make_card(model))
	GameState.money_changed.connect(_update_cards.unbind(1))
	GameState.ships_changed.connect(_update_cards)
	GameState.company_leveled.connect(_update_cards.unbind(2))
	resized.connect(_fit_columns)
	_hint.theme_type_variation = &"MapPopup"
	_hint.top_level = true
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	_hint_label.add_theme_font_size_override(&"font_size", 13)
	_hint.add_child(_hint_label)
	add_child(_hint)
	_update_cards()


## As many columns (up to MAX_COLUMNS) as the widest card allows.
func _fit_columns() -> void:
	var card_width := 0.0
	for grid in _grids:
		for card: Control in grid.get_children():
			card_width = maxf(card_width, card.get_combined_minimum_size().x)
	var margins := 60.0 + 2.0 * SECTION_PADDING  # Page margins, the scrollbar and the section tint's padding.
	var columns := clampi(floori((size.x - margins + CARD_GAP) / (card_width + CARD_GAP)), 1, MAX_COLUMNS)
	for grid in _grids:
		grid.columns = columns


## A section's panel, on a faint tint of its ship line's color (see
## GameData.category_color()), added to the page; returns the box inside it.
func _section_box(category: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(GameData.category_color(category), SECTION_TINT)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(SECTION_PADDING)
	panel.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	panel.add_child(box)
	%Items.add_child(panel)
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
	box.add_child(title)

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
		var slots := Progression.model_slots(model, level)
		var max_owned := int(model.get("max_owned", 0))
		var owned := GameState.owned_count(model_id)
		var next := Progression.next_slot_level(model, level)
		var price := GameState.ship_price(model_id)
		_price_labels[model_id].text = Fmt.money(price)
		if price < int(model.get("price", 0)):
			_price_labels[model_id].text += " for your first, then %s" % Fmt.money(int(model.price))
		_owned_labels[model_id].text = "%d / %d" % [owned, slots]
		if slots < max_owned and level >= Progression.unlock_level(model):
			_owned_labels[model_id].text += " (max %d)" % max_owned
		var button: Button = _buy_buttons[model_id]
		if level < Progression.unlock_level(model):
			button.text = "Unlocks at level %d" % next
		elif owned < slots:
			button.text = "Buy"
		else:
			button.text = "Limit reached" if next < 0 else "Next slot at level %d" % next
		var error := GameState.buy_error(model_id)
		button.disabled = not error.is_empty()
		_buy_alerts[model_id].visible = error.is_empty()
		button.tooltip_text = "" if _short_of_money(model_id) > 0 else error
	_update_hint()


func _on_buy_pressed(model_id: String) -> void:
	var popup: NamePopup = NamePopupScene.instantiate()
	popup.model_id = model_id
	PopupHost.find(self).open(popup)


## How much more money buying this model needs, or 0 if money isn't what's
## stopping it (it's affordable, locked or out of slots).
func _short_of_money(model_id: String) -> int:
	var model := GameData.get_ship_model(model_id)
	var slots := Progression.model_slots(model, GameState.company_level())
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
	if _hint.visible:
		_update_hint()  # Follows the button if the list scrolls.

extends Control
## Lists purchasable ship models from data/ship_models.json, in sections:
## cargo ships (with the company's fleet slots), then recovery boats. Models
## above the company's level show the level that unlocks them.

const SECTIONS := [["Cargo ships", false], ["Recovery boats", true]]
## Cards per row, fewer if they don't fit.
const MAX_COLUMNS := 3
const CARD_GAP := 16

const NamePopupScene := preload("res://scenes/popups/name_popup.tscn")

var _buy_buttons: Dictionary = {}  # model id -> Button
var _owned_labels: Dictionary = {}  # model id -> Label
var _slots_label := Label.new()
var _grids: Array[GridContainer] = []


func _ready() -> void:
	for section: Array in SECTIONS:
		var title := Label.new()
		title.theme_type_variation = &"HeaderLabel"
		title.text = section[0]
		%Items.add_child(title)
		if not section[1]:
			_slots_label.theme_type_variation = &"DimLabel"
			%Items.add_child(_slots_label)
		var grid := GridContainer.new()
		grid.columns = MAX_COLUMNS
		grid.add_theme_constant_override(&"h_separation", CARD_GAP)
		grid.add_theme_constant_override(&"v_separation", CARD_GAP)
		_grids.append(grid)
		%Items.add_child(grid)
		for model: Dictionary in GameData.ship_models:
			if bool(model.get("recovery", false)) == section[1]:
				grid.add_child(_make_card(model))
	GameState.money_changed.connect(_update_cards.unbind(1))
	GameState.ships_changed.connect(_update_cards)
	GameState.company_leveled.connect(_update_cards.unbind(2))
	resized.connect(_fit_columns)
	_update_cards()


## As many columns (up to MAX_COLUMNS) as the widest card allows.
func _fit_columns() -> void:
	var card_width := 0.0
	for grid in _grids:
		for card: Control in grid.get_children():
			card_width = maxf(card_width, card.get_combined_minimum_size().x)
	var margins := 60.0  # Page margins plus the scrollbar.
	var columns := clampi(floori((size.x - margins + CARD_GAP) / (card_width + CARD_GAP)), 1, MAX_COLUMNS)
	for grid in _grids:
		grid.columns = columns


func _make_card(model: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(290, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 12)
	card.add_child(box)

	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = model.get("name", model.id)
	box.add_child(title)

	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override(&"h_separation", 24)
	box.add_child(stats)
	var rows := [
		["Top speed", "%s nm/s" % Fmt.decimal(float(model.get("speed_nm_per_s", 0)), 2)],
		["Capacity", "%s containers" % Fmt.thousands(int(model.get("capacity", 0)))],
		["Range", "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))],
		["Fuel tank", "%s (%s)" % [Fmt.thousands(int(model.get("fuel_tank", 0))),
			Fmt.duration(float(model.get("fuel_tank", 0)) / float(model.get("fuel_per_s", 1)))]],
		["Port stop", Fmt.duration(float(model.get("dock_s", 0)))],
		["Price", Fmt.money(int(model.get("price", 0)))],
		["Owned", ""],
	]
	if model.get("recovery", false):
		var carries: Array = model.get("carries", [])
		rows[1] = ["Carries", "Any 1 lost ship" if carries.is_empty()
			else "Up to %s" % GameData.get_ship_model(carries[-1]).get("name", "")]
		rows[2] = ["Job", "Recovers ships lost at sea"]
	for row: Array in rows:
		var name_label := Label.new()
		name_label.text = row[0]
		name_label.modulate = Color(1, 1, 1, 0.7)
		stats.add_child(name_label)
		var value_label := Label.new()
		value_label.text = row[1]
		stats.add_child(value_label)
		if row[0] == "Owned":
			_owned_labels[model.id] = value_label

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(0, 48)
	buy.pressed.connect(_on_buy_pressed.bind(model.id))
	box.add_child(buy)
	_buy_buttons[model.id] = buy
	return card


func _update_cards() -> void:
	var level := GameState.company_level()
	var slots := Progression.fleet_slots(level)
	var next := Progression.next_slots(level)
	_slots_label.text = "Fleet slots: %d / %d used%s. Recovery boats don't use slots." % [
		GameState.cargo_ship_count(), slots,
		" (%d at level %d)" % [next[1], next[0]] if not next.is_empty() else ""]
	for model_id: String in _buy_buttons:
		var limit := int(GameData.get_ship_model(model_id).get("max_owned", 0))
		var owned := GameState.owned_count(model_id)
		_owned_labels[model_id].text = "%d / %d" % [owned, limit] if limit > 0 else str(owned)
		var button: Button = _buy_buttons[model_id]
		var at_limit := limit > 0 and owned >= limit
		var unlock := Progression.unlock_level(GameData.get_ship_model(model_id))
		if level < unlock:
			button.text = "Unlocks at level %d" % unlock
		else:
			button.text = "Limit reached" if at_limit else "Buy"
		var error := GameState.buy_error(model_id)
		button.disabled = not error.is_empty()
		button.tooltip_text = error


func _on_buy_pressed(model_id: String) -> void:
	var popup: NamePopup = NamePopupScene.instantiate()
	popup.model_id = model_id
	PopupHost.find(self).open(popup)

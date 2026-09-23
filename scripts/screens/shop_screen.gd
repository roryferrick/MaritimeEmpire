extends Control
## Lists purchasable ship models from data/ship_models.json.

const NamePopupScene := preload("res://scenes/popups/name_popup.tscn")

var _buy_buttons: Dictionary = {}  # model id -> Button
var _owned_labels: Dictionary = {}  # model id -> Label


func _ready() -> void:
	for model: Dictionary in GameData.ship_models:
		%Items.add_child(_make_card(model))
	GameState.money_changed.connect(_update_cards.unbind(1))
	GameState.ships_changed.connect(_update_cards)
	_update_cards()


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
	for model_id: String in _buy_buttons:
		var limit := int(GameData.get_ship_model(model_id).get("max_owned", 0))
		var owned := GameState.owned_count(model_id)
		_owned_labels[model_id].text = "%d / %d" % [owned, limit] if limit > 0 else str(owned)
		var button: Button = _buy_buttons[model_id]
		var at_limit := limit > 0 and owned >= limit
		button.text = "Limit reached" if at_limit else "Buy"
		button.disabled = not GameState.buy_error(model_id).is_empty()


func _on_buy_pressed(model_id: String) -> void:
	var popup: NamePopup = NamePopupScene.instantiate()
	popup.model_id = model_id
	PopupHost.find(self).open(popup)

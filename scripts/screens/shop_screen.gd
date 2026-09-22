extends Control
## Lists purchasable ship models from data/ship_models.json.

var _buy_buttons: Dictionary = {}  # model id -> Button


func _ready() -> void:
	for model: Dictionary in GameData.ship_models:
		%Items.add_child(_make_card(model))
	GameState.money_changed.connect(_update_buttons)
	_update_buttons(GameState.money)


func _make_card(model: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(340, 0)
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
		["Top speed", "%s nm/s" % Fmt.thousands(int(model.get("speed_nm_per_s", 0)))],
		["Capacity", "%s containers" % Fmt.thousands(int(model.get("capacity", 0)))],
		["Range", "%s nm" % Fmt.thousands(int(model.get("range_nm", 0)))],
		["Price", Fmt.money(int(model.get("price", 0)))],
	]
	for row: Array in rows:
		var name_label := Label.new()
		name_label.text = row[0]
		name_label.modulate = Color(1, 1, 1, 0.7)
		stats.add_child(name_label)
		var value_label := Label.new()
		value_label.text = row[1]
		stats.add_child(value_label)

	var buy := Button.new()
	buy.text = "Buy"
	buy.custom_minimum_size = Vector2(0, 48)
	buy.pressed.connect(_on_buy_pressed.bind(model.id))
	box.add_child(buy)
	_buy_buttons[model.id] = buy
	return card


func _update_buttons(money: int) -> void:
	for model_id: String in _buy_buttons:
		var price := int(GameData.get_ship_model(model_id).get("price", 0))
		_buy_buttons[model_id].disabled = money < price


func _on_buy_pressed(_model_id: String) -> void:
	Toast.show_message("Buying ships comes in the next build.")

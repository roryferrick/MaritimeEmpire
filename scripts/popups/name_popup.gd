class_name NamePopup
extends PanelContainer
## Names and buys a new ship and picks where it launches: the HQ (the default)
## or any hub. Suggests a random unused name.

## Set before adding to the tree.
var model_id := ""

var _price := 0


func _ready() -> void:
	var model := GameData.get_ship_model(model_id)
	_price = GameState.ship_price(model_id)
	%TitleLabel.text = "Name your new %s" % model.get("name", model_id)
	%BuyButton.text = "Buy for %s" % Fmt.money(_price)
	%NameEdit.max_length = GameState.MAX_NAME_LENGTH
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_confirm.unbind(1))
	%RandomButton.pressed.connect(_suggest)
	%CancelButton.pressed.connect(queue_free)
	%BuyButton.pressed.connect(_confirm)
	# Only ports that fit the ship: big enough, and not on the Great Lakes for
	# ships too big for the St. Lawrence Seaway.
	for hub in GameState.hubs:
		if not GameState.can_launch_at(model_id, hub.port_id):
			continue
		%PortOption.add_item(hub.title())
		%PortOption.set_item_metadata(%PortOption.item_count - 1, hub.port_id)
	%PortOption.disabled = %PortOption.item_count < 2
	%PortOption.tooltip_text = "Build hubs to launch ships from more ports." if %PortOption.disabled else ""
	_suggest()


func _suggest() -> void:
	%NameEdit.text = GameState.suggest_ship_name()
	%NameEdit.grab_focus()
	%NameEdit.select_all()
	_validate()


func _validate() -> bool:
	var error := GameState.ship_name_error(%NameEdit.text)
	if error.is_empty():
		error = GameState.buy_error(model_id)
	if error.is_empty() and %PortOption.item_count == 0:
		error = "Too big for the St. Lawrence Seaway: found a hub on the open sea to launch it from."
	%ErrorLabel.text = error
	%BuyButton.disabled = not error.is_empty()
	return error.is_empty()


func _confirm() -> void:
	if not _validate():
		return
	var ship := GameState.buy_ship(model_id, %NameEdit.text, %PortOption.get_selected_metadata())
	if ship:
		ActivityLog.add("Bought %s. It's docked at %s." % [ship.name, GameData.port_name(ship.docked_at)],
			ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))
	queue_free()

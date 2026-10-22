# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name NamePopup
extends PanelContainer
## Names a new ship and buys it, orders it or takes a second-hand one: a tier-1
## boat or tug is bought outright and launched at the HQ or a hub; a bigger
## ship is ordered from a shipyard (Shipyards: the yard picked here, a deposit
## now, delivered at the yard's port months on); a listed used ship (listing_id)
## is bought where it lies. Suggests a random unused name.

## Set before adding to the tree.
var model_id := ""
## A second-hand listing to buy (Shipyards.listings), or -1.
var listing_id := -1

var _price := 0
var _ordering := false
var _offers: Array = []


func _ready() -> void:
	var model := GameData.get_ship_model(model_id)
	%NameEdit.max_length = GameState.MAX_NAME_LENGTH
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_confirm.unbind(1))
	%RandomButton.pressed.connect(_suggest)
	%CancelButton.pressed.connect(queue_free)
	%BuyButton.pressed.connect(_confirm)
	if listing_id >= 0:
		var each: Dictionary = GameState.shipyards.listing(listing_id)
		_price = int(each.get("price", 0))
		%TitleLabel.text = "Name your second-hand %s" % model.get("name", model_id)
		%BuyButton.text = "Buy for %s" % Fmt.money(_price)
		$Content/PortRow/PortLabel.text = "Lying at"
		%PortOption.add_item(GameData.port_name(str(each.get("port", ""))))
		%PortOption.disabled = true
		%PortOption.tooltip_text = "A second-hand ship is delivered where it lies."
		%NameEdit.text = str(each.get("name", ""))
		%NameEdit.grab_focus()
		%NameEdit.select_all()
		_validate()
		return
	_ordering = Shipyards.is_ordered(model)
	if _ordering:
		_offers = GameState.shipyards.yards_for(model)
		%TitleLabel.text = "Order a %s" % model.get("name", model_id)
		$Content/PortRow/PortLabel.text = "Built by"
		for offer: Dictionary in _offers:
			%PortOption.add_item("%s (%s) · %s · %d months · %s%s" % [str(offer.name), GameData.port_name(str(offer.port)), Fmt.money(int(offer.price)), roundi(float(offer.months)), Shipyards.quality_word(float(offer.quality)), "" if int(offer.free) > 0 else " · no slot free"])
			%PortOption.set_item_metadata(%PortOption.item_count - 1, str(offer.yard))
			%PortOption.set_item_disabled(%PortOption.item_count - 1, int(offer.free) <= 0)
		for i in %PortOption.item_count:  # (The first yard with a slot.)
			if not %PortOption.is_item_disabled(i):
				%PortOption.select(i)
				break
		%PortOption.item_selected.connect(func(_i: int) -> void: _validate())
		%PortOption.tooltip_text = "Yards differ in price, months and reputation: a fine yard delivers every part sound, a cheap one a little under and sometimes a month late."
		_suggest()
		return
	_price = GameState.ship_price(model_id)
	%TitleLabel.text = "Name your new %s" % model.get("name", model_id)
	%BuyButton.text = "Buy for %s" % Fmt.money(_price)
	# A tug goes to the route port that needs one most (see GameState.buy_ship()).
	if model.get("tug", false):
		var port := GameState.tug_port_for_new()
		if not port.is_empty():
			%PortOption.add_item(GameData.port_name(port))
			%PortOption.set_item_metadata(0, port)
		%PortOption.disabled = true
		%PortOption.tooltip_text = "Tugs are based two to a port across the ports on your routes, fewest first."
		_suggest()
		return
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
	if listing_id >= 0:
		if error.is_empty():
			error = GameState.shipyards.used_error(GameState.company, listing_id)
	elif _ordering:
		var yard_id := str(%PortOption.get_selected_metadata()) if %PortOption.selected >= 0 else ""
		if error.is_empty():
			error = GameState.shipyards.order_error(GameState.company, model_id, yard_id)
		if %PortOption.selected >= 0 and %PortOption.selected < _offers.size():
			var offer: Dictionary = _offers[%PortOption.selected]
			var deposit := roundi(int(offer.price) * GameState.shipyards.deposit_share())
			%BuyButton.text = "Order: %s now, %s on delivery" % [Fmt.money(deposit), Fmt.money(int(offer.price) - deposit)]
		else:
			%BuyButton.text = "Order"
	else:
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
	if listing_id >= 0:
		GameState.buy_used(listing_id, %NameEdit.text)
		queue_free()
		return
	if _ordering:
		GameState.place_order(model_id, %NameEdit.text, str(%PortOption.get_selected_metadata()))
		queue_free()
		return
	var ship := GameState.buy_ship(model_id, %NameEdit.text, %PortOption.get_selected_metadata())
	if ship:
		ActivityLog.add("Bought %s. It's docked at %s." % [ship.name, GameData.port_name(ship.docked_at)],
			ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))
	queue_free()

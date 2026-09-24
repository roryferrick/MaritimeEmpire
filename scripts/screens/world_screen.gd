extends Control
## The main map: ports, ships and canal locks, with their popups, and a switch
## in the top right for showing the fleet's route lanes faintly.

@onready var _map: MapView = $MapView


func _ready() -> void:
	_map.show_ships = true
	_map.show_active_lanes = GameState.show_active_routes
	_map.port_clicked.connect(_open_port_popup)
	_map.ship_clicked.connect(_open_ship_popup)
	_map.lock_clicked.connect(_open_lock_popup)
	_map.canal_clicked.connect(_open_convoy_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())
	%RoutesToggle.set_pressed_no_signal(GameState.show_active_routes)
	%RoutesToggle.toggled.connect(_on_routes_toggled)
	_add_price_picker()


func _on_routes_toggled(on: bool) -> void:
	GameState.show_active_routes = on
	_map.show_active_lanes = on


func _open_port_popup(port_id: String) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.port_screen_position(port_id)
	PopupHost.find(self).show_port(port_id, follow)


func _open_lock_popup(canal_id: String, lock_index: int) -> void:
	var popup := LockPopup.new()
	popup.canal_id = canal_id
	popup.lock_index = lock_index
	popup.follow = func() -> Vector2:
		return _map.get_global_transform() * _map.lock_screen_position(canal_id, lock_index)
	PopupHost.find(self).open(popup)


func _open_convoy_popup(canal_id: String) -> void:
	var popup := ConvoyPopup.new()
	popup.canal_id = canal_id
	popup.follow = func() -> Vector2:
		return _map.get_global_transform() * _map.canal_screen_position(canal_id)
	PopupHost.find(self).open(popup)


func _open_ship_popup(ship: Ship) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.ship_screen_position(ship)
	PopupHost.find(self).show_ship(ship, follow)


## "Prices: Toys" below the Routes switch: colors the ports by that commodity's
## price (see MapView.price_commodity), or "Prices: off".
func _add_price_picker() -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MapPopup"
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -210.0
	panel.offset_right = -12.0
	panel.offset_top = 60.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	var picker := OptionButton.new()
	picker.tooltip_text = "Color the ports by a commodity's price: green where it's cheap, red where it's dear."
	picker.add_item("Prices: off")
	picker.set_item_metadata(0, "")
	for commodity: Dictionary in GameData.commodities:
		picker.add_item("Prices: %s" % commodity.name)
		picker.set_item_metadata(picker.item_count - 1, commodity.id)
	picker.item_selected.connect(func(index: int) -> void: _map.price_commodity = picker.get_item_metadata(index))
	panel.add_child(picker)

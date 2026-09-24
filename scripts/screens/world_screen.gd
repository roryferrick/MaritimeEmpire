extends Control
## The main map: ports and ships, with their popups, and a switch in the top
## right for showing the fleet's route lanes faintly.

@onready var _map: MapView = $MapView


func _ready() -> void:
	_map.show_ships = true
	_map.show_active_lanes = GameState.show_active_routes
	_map.port_clicked.connect(_open_port_popup)
	_map.ship_clicked.connect(_open_ship_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())
	%RoutesToggle.set_pressed_no_signal(GameState.show_active_routes)
	%RoutesToggle.toggled.connect(_on_routes_toggled)


func _on_routes_toggled(on: bool) -> void:
	GameState.show_active_routes = on
	_map.show_active_lanes = on


func _open_port_popup(port_id: String) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.port_screen_position(port_id)
	PopupHost.find(self).show_port(port_id, follow)


func _open_ship_popup(ship: Ship) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.ship_screen_position(ship)
	PopupHost.find(self).show_ship(ship, follow)

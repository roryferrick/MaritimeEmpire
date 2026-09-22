extends Control
## The main map: ports and ships, with their popups.

@onready var _map: MapView = $MapView


func _ready() -> void:
	_map.show_ships = true
	_map.port_clicked.connect(_open_port_popup)
	_map.ship_clicked.connect(_open_ship_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())


func _open_port_popup(port_id: String) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.port_screen_position(port_id)
	PopupHost.find(self).show_port(port_id, follow)


func _open_ship_popup(ship: Ship) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.ship_screen_position(ship)
	PopupHost.find(self).show_ship(ship, follow)

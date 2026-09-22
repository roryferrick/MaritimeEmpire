extends Control
## The main map: ports (and later ships) with their popups.

const PortPopupScene := preload("res://scenes/popups/port_popup.tscn")

var _port_popup: PortPopup = null

@onready var _map: MapView = $MapView


func _ready() -> void:
	_map.port_clicked.connect(_open_port_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())
	_map.view_changed.connect(_update_popup_anchor)


func _open_port_popup(port_id: String) -> void:
	_port_popup = PortPopupScene.instantiate()
	_port_popup.port_id = port_id
	PopupHost.find(self).open(_port_popup)
	_update_popup_anchor()


## Keep the port popup attached to its port while the map pans and zooms.
func _update_popup_anchor() -> void:
	if not is_instance_valid(_port_popup) or not _port_popup.is_inside_tree():
		return
	var host := _port_popup.get_parent() as Control
	var global_point := _map.get_global_transform() * _map.port_screen_position(_port_popup.port_id)
	_port_popup.anchor_to(host.get_global_transform().affine_inverse() * global_point)

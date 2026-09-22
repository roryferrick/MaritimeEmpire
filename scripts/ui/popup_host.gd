class_name PopupHost
extends Control
## Holds the single open popup. Opening a new popup closes the old one.

const GROUP := &"popup_host"
const PORT_POPUP_PATH := "res://scenes/popups/port_popup.tscn"
const SHIP_POPUP_PATH := "res://scenes/popups/ship_popup.tscn"

var current: Control = null


static func find(from: Node) -> PopupHost:
	return from.get_tree().get_first_node_in_group(GROUP) as PopupHost


func _ready() -> void:
	add_to_group(GROUP)
	mouse_filter = MOUSE_FILTER_IGNORE


func open(popup: Control) -> void:
	close()
	current = popup
	add_child(popup)


func close() -> void:
	if is_instance_valid(current):
		current.queue_free()
	current = null


## follow returns the global point the popup should sit next to.
func show_port(port_id: String, follow: Callable) -> void:
	var popup: PortPopup = load(PORT_POPUP_PATH).instantiate()
	popup.port_id = port_id
	popup.follow = follow
	open(popup)


## follow returns the global point the popup should sit next to.
func show_ship(ship: Ship, follow: Callable, gap := 26.0) -> void:
	var popup: ShipPopup = load(SHIP_POPUP_PATH).instantiate()
	popup.ship = ship
	popup.follow = follow
	popup.gap = gap
	open(popup)


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(current) and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

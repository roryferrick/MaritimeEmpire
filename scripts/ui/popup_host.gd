class_name PopupHost
extends Control
## Holds the single open popup. Opening a new popup closes the old one.

const GROUP := &"popup_host"

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


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(current) and event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

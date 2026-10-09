# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name IndustryPopup
extends AnchoredPopup
## Opened by clicking one of a hub's industry plots on the map: the hub's
## industry (IndustryPanel), the plot clicked picked out. Follows the port.

## Set before adding to the tree.
var hub: Hub
var slot := -1


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "%s industry" % hub.title()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(IndustryPanel.new(hub, slot))
	GameState.hubs_changed.connect(func() -> void: reset_size.call_deferred())

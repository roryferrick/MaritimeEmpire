# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Labels in rows, game-wide. A wrapping Label (autowrap on) put in a row
## (HBoxContainer or HFlowContainer) with no width of its own gets the box's
## minimum width for it, which is nothing: the text comes out one letter a
## line, the row grows as tall as that column of letters, and every button
## and picker beside it is stretched to the row's height (the drydock popup's
## "Yard" and its picker, the People page's job row, the Ownership page's
## motions all did this). Rather than mend each of the hundred-odd rows by
## hand, every Label that enters the tree under a row is given a width to
## wrap in, at the end of the frame once its text is set: a short text stops
## wrapping (a label beside a picker or button), a long one takes the row's
## spare width and wraps in that. A label with a width of its own
## (custom_minimum_size.x) or one already set to expand is left alone, as is
## any with wrapping off.

## Texts this long or shorter stop wrapping; longer ones expand to wrap.
const SHORT := 40


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Label:
		_fit.call_deferred(node)  # (Once the frame's done configuring it.)


func _fit(label: Label) -> void:
	if not is_instance_valid(label) or not label.is_inside_tree():
		return
	var parent := label.get_parent()
	if not (parent is HBoxContainer or parent is HFlowContainer):
		return
	if label.autowrap_mode == TextServer.AUTOWRAP_OFF or label.custom_minimum_size.x > 0.0:
		return
	if label.size_flags_horizontal & Control.SIZE_EXPAND:
		return
	if label.text.length() <= SHORT:
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name MapPage
extends Control
## A page over the map (Markets, Hubs, Farms or Makers: see
## GameRoot.open_page()), dimming it: a card filling most of the map with
## the page's screen in it (its own heading names it) and an X in the
## corner. Esc, X or a click outside closes it; `closed` hands the screen back
## (GameRoot puts it away until it's opened again, so it keeps its state).

signal closed(screen: Control)

## The space left round the card (px).
const MARGIN := 10.0
const CLOSE_SIZE := 40.0

var screen: Control
var _body := ScrollContainer.new()


func _init(page_screen: Control = null) -> void:
	screen = page_screen


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(dim)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.set_anchors_and_offsets_preset(PRESET_FULL_RECT, PRESET_MODE_MINSIZE, int(MARGIN))
	add_child(card)
	# The screen fills the card's height (it scrolls itself) and its width, or
	# scrolls sideways where it's wider than the card.
	_body.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(_body)
	if screen != null:
		if screen.get_parent() != null:
			screen.reparent(_body, false)
		else:
			_body.add_child(screen)
		screen.size_flags_horizontal = SIZE_EXPAND_FILL
		screen.size_flags_vertical = SIZE_EXPAND_FILL
		screen.visible = true
	var close_button := Button.new()
	close_button.text = "X"
	close_button.tooltip_text = "Close (Esc)"
	close_button.focus_mode = FOCUS_NONE
	close_button.custom_minimum_size = Vector2.ONE * CLOSE_SIZE
	close_button.set_anchors_preset(PRESET_TOP_RIGHT)
	close_button.offset_left = -MARGIN - CLOSE_SIZE - 8.0
	close_button.offset_right = -MARGIN - 8.0
	close_button.offset_top = MARGIN + 8.0
	close_button.offset_bottom = MARGIN + 8.0 + CLOSE_SIZE
	close_button.pressed.connect(close)
	add_child(close_button)


## Closes the page, handing its screen back (see `closed`).
func close() -> void:
	if is_queued_for_deletion():
		return
	closed.emit(screen)
	queue_free()


func _input(event: InputEvent) -> void:
	# Esc with something on the page focused (a list, a picker), which would
	# take it for itself: let go of it, so it reaches _unhandled_input().
	if event.is_action_pressed(&"ui_cancel"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused != null and is_ancestor_of(focused) and not (focused is LineEdit or focused is TextEdit):
			focused.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

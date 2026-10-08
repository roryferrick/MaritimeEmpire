# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name EscapeMenu
extends Control
## Esc during a game: Continue, Save, Exit to Menu and Exit to Desktop (and
## the game's Licences: see Licences), over the dimmed game. In single player
## the game pauses while it's open (and carries on at its speed after
## Continue); in multiplayer it keeps going for everyone. A joined player
## can't save (the host's game holds every company) and leaving keeps their
## company going; a host leaving ends the game for everyone (saving first), as
## Leave Game does.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const BUTTON_SIZE := Vector2(300, 48)

var _status := Label.new()
## Single player: the speed to carry on at after Continue (-1 if the menu didn't pause it).
var _paused_from := -1


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP  # The game underneath can't be clicked meanwhile.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MapPopup"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Paused" if not Net.is_online() else "Menu"
	title.theme_type_variation = &"HeaderLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_button(box, "Continue", close).grab_focus.call_deferred()
	var save := _button(box, "Save", _save)
	if Net.is_client():
		save.disabled = true
		save.tooltip_text = "The host's game saves every company."
	_button(box, "Exit to Menu", _exit_to_menu)
	_button(box, "Exit to Desktop", _exit_to_desktop)
	_status.theme_type_variation = &"DimLabel"
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = BUTTON_SIZE.x
	if Net.is_host():
		_status.text = "Leaving saves the game and ends it for everyone."
	elif Net.is_client():
		_status.text = "Leaving keeps your company going in the host's game; join again to take it back."
	_status.visible = not _status.text.is_empty()
	box.add_child(_status)
	var copyright := Label.new()
	copyright.text = "© 2026 Rory Ferrick. All rights reserved."
	copyright.theme_type_variation = &"DimLabel"
	copyright.add_theme_font_size_override(&"font_size", 12)
	copyright.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(copyright)
	var licences := Button.new()
	licences.text = "Licences"
	licences.flat = true
	licences.size_flags_horizontal = SIZE_SHRINK_CENTER
	licences.add_theme_font_size_override(&"font_size", 12)
	licences.pressed.connect(func() -> void: add_child(Licences.new()))
	box.add_child(licences)
	if not Net.is_online() and GameState.time_speed > 0:
		_paused_from = GameState.time_speed
		GameState.time_speed = 0


func _button(box: VBoxContainer, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.pressed.connect(action)
	box.add_child(button)
	return button


## Esc again closes it, as Continue does.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


## Continue: closes the menu, and in single player carries on at the speed it paused.
func close() -> void:
	if _paused_from > 0 and GameState.time_speed == 0:
		GameState.time_speed = _paused_from
	queue_free()


func _save() -> void:
	GameState.save_game()
	_status.text = "Saved at %s." % Fmt.calendar(GameState.calendar_time())
	_status.visible = true


## Saves (unless joined), leaves any multiplayer game, and goes to the title screen.
func _exit_to_menu() -> void:
	_leave()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Saves (unless joined), leaves any multiplayer game, and quits.
func _exit_to_desktop() -> void:
	_leave()
	get_tree().quit()


func _leave() -> void:
	if not Net.is_client():
		GameState.save_game()
	Net.leave()
	GameState.in_session = false

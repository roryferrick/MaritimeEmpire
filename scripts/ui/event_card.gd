# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name EventCard
extends PanelContainer
## A card in the middle of the screen for the big moments: a company level
## reached (with what it unlocked) and an achievement earned. The game pauses
## while one shows and carries on at the speed it was at when Continue is
## pressed (Space or Enter too); more than one at once queue up, one card each.
## In multiplayer the host's clock runs for everyone, so the card shows without
## pausing and Continue just closes it.

const WIDTH := 480.0
const GOLD := Color(1.0, 0.8, 0.3)
const LEVEL_COLOR := Color(0.55, 0.85, 1.0)

var _kicker := Label.new()
var _title := Label.new()
var _body := Label.new()
var _button := Button.new()
var _queue: Array[Dictionary] = []  # [{kicker, title, body, color}]
## The speed the game ran at before the card paused it (0: it was paused already).
var _was_speed := 0


func _ready() -> void:
	theme_type_variation = &"MapPopup"
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 10)
	add_child(box)
	_kicker.theme_type_variation = &"DimLabel"
	_kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_kicker)
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override(&"font_size", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = WIDTH - 32.0
	box.add_child(_title)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.custom_minimum_size.x = WIDTH - 32.0
	box.add_child(_body)
	_button.text = "Continue"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.custom_minimum_size = Vector2(140, 38)
	_button.pressed.connect(_continue)
	box.add_child(_button)
	visible = false


## A company level reached: "Level 12" and what it unlocked.
func show_level(level: int, unlocks: Array[String]) -> void:
	var body := "Unlocked: %s" % ", ".join(unlocks) if not unlocks.is_empty() else "Keep trading to unlock more ships, ports and upgrades."
	if unlocks.has("a new company type to choose"):
		body += "\n\nBranch out: choose your new company type with the Choose a company type button on the World map or in the Shop."
	_enqueue({kicker = "COMPANY LEVEL UP", title = "Level %d" % level, body = body, color = LEVEL_COLOR})


## An achievement earned (stars 0 for a one-off badge), as Achievements.check() reports it.
func show_achievement(name: String, stars: int, unit := "") -> void:
	var title := name if stars == 0 else "%s %s" % [name, "★".repeat(stars)]
	var body := "Achievement earned." if stars == 0 else "%d of 3 stars%s." % [stars, (" for " + unit) if not unit.is_empty() else ""]
	_enqueue({kicker = "ACHIEVEMENT", title = title, body = body, color = GOLD})


func _enqueue(card: Dictionary) -> void:
	_queue.append(card)
	if not visible:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		visible = false
		return
	var card: Dictionary = _queue.pop_front()
	_kicker.text = card.kicker
	_title.text = card.title
	_title.add_theme_color_override(&"font_color", card.color)
	_body.text = card.body
	if not visible:
		visible = true
		if not Net.is_online():
			_was_speed = GameState.time_speed
			if _was_speed > 0:
				GameState.time_speed = 0
	_button.grab_focus()


func _continue() -> void:
	if not _queue.is_empty():
		_show_next()
		return
	visible = false
	if _was_speed > 0 and GameState.time_speed == 0:
		GameState.time_speed = _was_speed
	_was_speed = 0


## Space or Enter continues (before the game's own Space, which would unpause behind the card).
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_accept") or event.is_action_pressed(&"ui_cancel"):
		_continue()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_SPACE:
		_continue()
		get_viewport().set_input_as_handled()

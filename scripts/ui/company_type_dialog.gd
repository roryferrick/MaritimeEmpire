# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CompanyTypeDialog
extends Control
## Choosing another company type (from the World map's button, the Shop's
## locked tabs or the level-up card): the types as CompanyTypeCards, those the
## company has greyed; Choose, then Confirm, takes one
## (GameState.choose_company_type()). Over whatever opened it, dimming it;
## Esc, X or a click outside closes it.

var _note := Label.new()


## Opens it over the game (a no-op if no type can be chosen now).
static func open(from: Node) -> void:
	if GameState.company_types_available() <= 0:
		return
	GameRoot.find(from).add_child(CompanyTypeDialog.new())


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	center.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	panel.add_child(content)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Choose a new company type"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var has := PackedStringArray()
	for type_id: String in GameState.company.company_types:
		has.append(Progression.type_name(type_id))
	_note.theme_type_variation = &"DimLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 900
	_note.text = "Your company is in %s. Branch out into one more type: its smallest ships open now and the bigger ones follow as you level up (the next tiers 3, 8, 15 and 24 levels on). It's for good, so choose with care." % " and ".join(has)
	content.add_child(_note)
	var cards := CompanyTypeCards.new(true, GameState.company.company_types.keys())
	cards.chosen.connect(_choose)
	content.add_child(cards)


func _choose(type_id: String) -> void:
	var error := GameState.choose_company_type(type_id)
	if not error.is_empty():
		_note.text = error
		return
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

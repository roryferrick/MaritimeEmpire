# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name LogoDialog
extends Control
## Changing the company's logo after founding (Finances, Your company): the
## LogoEditor on the current logo, and Change logo for GameState.LOGO_CHANGE_COST
## (GameState.set_logo()). Over whatever opened it, dimming it; Esc, X or a
## click outside closes it.

var _editor: LogoEditor
var _note := Label.new()
var _confirm := Button.new()
var _logo := {}


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
	content.add_theme_constant_override(&"separation", 14)
	panel.add_child(content)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Company logo"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	_logo = GameState.company.logo.duplicate()
	_editor = LogoEditor.new(_logo, GameState.company.color, GameState.company.start_type())
	_editor.changed.connect(func(logo: Dictionary) -> void:
		_logo = logo
		_refresh())
	content.add_child(_editor)
	_note.theme_type_variation = &"DimLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 560
	content.add_child(_note)
	_confirm.text = "Change logo: %s" % Fmt.money(GameState.LOGO_CHANGE_COST)
	_confirm.size_flags_horizontal = SIZE_SHRINK_CENTER
	_confirm.custom_minimum_size = Vector2(280, 44)
	_confirm.pressed.connect(func() -> void:
		var error := GameState.set_logo(_logo)
		if error.is_empty():
			queue_free()
		else:
			_note.text = error)
	content.add_child(_confirm)
	_refresh()


func _refresh() -> void:
	var same := _logo == GameState.company.logo
	var error := GameState.set_logo_error(_logo)
	_confirm.disabled = same or not error.is_empty()
	_note.text = "Pick a new look, then change it. Your logo is on your HQ and hubs, in the company tables and on your cruise ships' funnels; changing it costs %s." % Fmt.money(GameState.LOGO_CHANGE_COST) if same or error.is_empty() else error


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

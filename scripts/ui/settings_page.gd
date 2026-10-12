# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SettingsPage
extends Control
## Settings (from the Esc menu), in two tabs. General: how ships far off are
## drawn (Settings.ship_look), the map's Routes switch (the fleet's lanes shown
## faintly) and, in a game with the tutorial, the Tutorial switch (its tips).
## Audio: a volume for everything and for each kind of sound (Settings'
## buses). Over whatever opened it, dimming it; Esc, X or a click outside
## closes it. Routes and the tutorial are the company's own (kept in its
## save); the rest are this computer's (see Settings).

const PANEL_SIZE := Vector2(560, 0)


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = PANEL_SIZE
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	card.add_child(content)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Settings"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(tabs)
	tabs.add_child(_general_tab())
	tabs.add_child(_audio_tab())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _general_tab() -> Control:
	var box := _tab_box("General")
	box.add_child(_heading("Ships seen from afar"))
	var group := ButtonGroup.new()
	var tips := {
		dot = "Ships are drawn their true size in the world: zoomed well out, each is a small dot in its colour.",
		big_dot = "As the default, but the dots are bigger, so ships far off are easier to see.",
		grow = "Ships never get smaller than a few pixels long: zoomed out they stand out over the map with their art showing, as they used to. They shrink back to their true size coming into port.",
	}
	for look: String in Settings.SHIP_LOOKS:
		var option := CheckBox.new()
		option.button_group = group
		option.text = str(Settings.SHIP_LOOK_NAMES[look])
		option.tooltip_text = str(tips[look])
		option.button_pressed = Settings.ship_look == look
		option.toggled.connect(func(on: bool) -> void:
			if on:
				Settings.ship_look = look)
		box.add_child(option)
	box.add_child(_heading("Map"))
	var routes := CheckButton.new()
	routes.text = "Routes"
	routes.tooltip_text = "Show the sea lanes your ships' routes use, as faint lines."
	routes.button_pressed = GameState.show_active_routes
	routes.toggled.connect(func(on: bool) -> void:
		GameState.show_active_routes = on
		Settings.changed.emit())
	box.add_child(routes)
	if GameState.tutorials:
		var tutorial := CheckButton.new()
		tutorial.text = "Tutorial"
		tutorial.tooltip_text = "Show tips that explain the basics as you play."
		tutorial.button_pressed = GameState.tutorials_on
		tutorial.toggled.connect(func(on: bool) -> void: GameState.tutorials_on = on)
		box.add_child(tutorial)
	return box


func _audio_tab() -> Control:
	var box := _tab_box("Audio")
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 14)
	grid.add_theme_constant_override(&"v_separation", 12)
	box.add_child(grid)
	for entry: Array in Settings.VOLUMES:
		var bus := str(entry[0])
		var label := Label.new()
		label.text = str(entry[1])
		grid.add_child(label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		slider.custom_minimum_size = Vector2(280, 0)
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.size_flags_vertical = SIZE_SHRINK_CENTER
		slider.value = Settings.volume(bus) * 100.0
		grid.add_child(slider)
		var amount := Label.new()
		amount.theme_type_variation = &"DimLabel"
		amount.custom_minimum_size = Vector2(48, 0)
		amount.text = "%d%%" % roundi(slider.value)
		grid.add_child(amount)
		slider.value_changed.connect(func(value: float) -> void:
			amount.text = "%d%%" % roundi(value)
			Settings.set_volume(bus, value / 100.0))
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Sea and weather: the waves, wind and rain. Wildlife: the birds' and animals' calls. Ship horns: ships setting off and the fog signal. All of it gets quieter the further out you zoom."
	box.add_child(note)
	return box


func _tab_box(tab_name: String) -> VBoxContainer:
	var margin := VBoxContainer.new()
	margin.name = tab_name
	margin.add_theme_constant_override(&"separation", 8)
	return margin


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 20)
	return label

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SettingsPage
extends Control
## Settings (from the Esc menu), in two tabs. General: three-step sliders for
## how ships far off are drawn (Settings.ship_look), the map's routes (none,
## only mine, all: GameState.show_active_routes and Settings.own_routes_only)
## the night (always day, half as dark, full: Settings.night) and antialiasing
## (off, low, medium, high: Settings.antialias), and the
## Birds switch (Settings) and, in a game with the tutorial, the Tutorial switch (its tips).
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
	var look_names: Array = Settings.SHIP_LOOKS.map(func(look: String) -> String: return str(Settings.SHIP_LOOK_NAMES[look]))
	box.add_child(_levels(look_names, Settings.SHIP_LOOKS.find(Settings.ship_look),
		"Ships are drawn their true size in the world: zoomed well out, each is a small dot in its colour; or bigger dots, easier to see far off; or ships never smaller than a few pixels long, their art showing over the map zoomed out (they shrink back to their true size coming into port).",
		func(level: int) -> void: Settings.ship_look = Settings.SHIP_LOOKS[level]))
	box.add_child(_heading("Other companies' ships"))
	var traffic_names: Array = Settings.TRAFFICS.map(func(level: String) -> String: return str(Settings.TRAFFIC_NAMES[level]))
	box.add_child(_levels(traffic_names, Settings.TRAFFICS.find(Settings.traffic),
		"The world's other shipping firms' ships, drawn where you look: none, or up to about 50, 150 or 400 at once (they sail their real voyages between the zones' ports and berth briefly; your ships always come first at a berth). Fewer costs less each frame.",
		func(level: int) -> void: Settings.traffic = Settings.TRAFFICS[level]))
	box.add_child(_heading("Routes"))
	var routes_level := 0 if not GameState.show_active_routes else (1 if Settings.own_routes_only else 2)
	box.add_child(_levels(["No routes", "Only my routes", "All routes"], routes_level,
		"The sea lanes ships' routes use, drawn as faint lines: none, only your own ships' routes, or every company's (other players' and the AI rivals' too).",
		func(level: int) -> void:
			GameState.show_active_routes = level > 0
			Settings.own_routes_only = level == 1  # (Saves and tells the map.)
			))
	box.add_child(_heading("Day and night"))
	var night_names: Array = Settings.NIGHTS.map(func(n: String) -> String: return str(Settings.NIGHT_NAMES[n]))
	box.add_child(_levels(night_names, Settings.NIGHTS.find(Settings.night),
		"The side of the world away from the sun goes dark, with ships', harbours' and towns' lights: always day, only half as dark, or the full night.",
		func(level: int) -> void: Settings.night = Settings.NIGHTS[level]))
	box.add_child(_heading("Antialiasing"))
	box.add_child(_levels(Settings.ANTIALIAS_NAMES, Settings.antialias,
		"Smooths the jagged edges of coasts, ships and lines on the map: off, or blending 3, 5 or 9 pixels along each edge. Only edge pixels are worked on, so even High costs little; Off costs nothing.",
		func(level: int) -> void: Settings.antialias = level))
	box.add_child(_heading("Map"))
	var birds := CheckButton.new()
	birds.text = "Birds"
	birds.tooltip_text = "The birds round the ports and following ships. Off, none are drawn (their calls still play: see Audio)."
	birds.button_pressed = Settings.birds
	birds.toggled.connect(func(on: bool) -> void: Settings.birds = on)
	box.add_child(birds)
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
		slider.max_value = Settings.volume_most(bus) * 100.0  # (Master to 200%: 100% is everything at its own level.)
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
	note.text = "Master goes up to 200%: 100% is everything at its own level. Sea and weather: the waves, wind and rain. Wildlife: the birds' and animals' calls. Ship horns: ships setting off and the fog signal. All of it gets quieter the further out you zoom."
	box.add_child(note)
	return box


## A three-step slider with the step's name beside it: `names` per level,
## `level` the one set now, `on_level` called with the new level as it's moved.
func _levels(names: Array, level: int, tip: String, on_level: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	row.tooltip_text = tip
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = names.size() - 1
	slider.step = 1.0
	slider.tick_count = names.size()
	slider.ticks_on_borders = true
	slider.custom_minimum_size = Vector2(220, 0)
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	slider.value = clampi(level, 0, names.size() - 1)
	slider.tooltip_text = tip
	row.add_child(slider)
	var label := Label.new()
	label.text = str(names[int(slider.value)])
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	slider.value_changed.connect(func(value: float) -> void:
		label.text = str(names[int(value)])
		on_level.call(int(value)))
	return row


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

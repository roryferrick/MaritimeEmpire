# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## New game setup: name the company, pick the home port new ships are delivered
## to on the globe (only the recommended great and harder starts from
## data/starts.json and the Great Lakes ports, colored by kind), choose the
## company's color, its fastest game speed, its storms (none, moderate or
## harsh), and whether to have seasonal closures and the tutorial; then make
## the CEO: their name and looks (Characters), part by part or at random.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DEFAULT_HOME_PORT := "ROM"
const DEFAULT_COLOR := "purple"
const DEFAULT_STORMS := "moderate"
const SWATCH_SIZE := Vector2(56, 36)
## The starting ports' colors on the map, by kind of start.
const START_COLORS := {great = Color(0.35, 0.85, 0.4), harder = Color(1.0, 0.75, 0.25), great_lakes = Color(0.45, 0.75, 1.0)}

var _home_port := DEFAULT_HOME_PORT
var _color := DEFAULT_COLOR
var _max_speed: int = GameState.TIME_SPEEDS[-1]
var _storms := DEFAULT_STORMS
## The CEO being made (Characters: {name, look}), and their page.
var _ceo := Company.random_ceo()
var _ceo_page := CenterContainer.new()
var _ceo_portrait := Portrait.new()
var _ceo_name := LineEdit.new()
var _part_labels := {}


func _ready() -> void:
	%NameEdit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	_add_ports()
	_add_color_swatches()
	_add_speed_choices()
	_add_storm_choices()
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_start.unbind(1))
	%StartButton.pressed.connect(_start)
	%StartButton.text = "Next: Your CEO"
	_add_ceo_page()
	%BackButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%NameEdit.grab_focus()
	_validate()


## The starting ports on the map: the recommended starts (great and harder,
## from data/starts.json) and the Great Lakes ports, each in its kind's color
## (START_COLORS); every other port is a faint dot that can't be picked.
func _add_ports() -> void:
	var map: MapView = %MapView
	var choices := {}
	for kind: String in ["great", "harder"]:
		for entry: Dictionary in GameData.starts.get(kind, []):
			choices[entry.port] = START_COLORS[kind]
	for port_id: String in GameData.starts.get("great_lakes", {}).get("ports", []):
		choices[port_id] = START_COLORS.great_lakes
	map.selectable_ports = choices
	map.opens_at_port = DEFAULT_HOME_PORT
	map.opens_whole_globe = true
	map.port_clicked.connect(_pick_port)
	_pick_port(DEFAULT_HOME_PORT)


func _pick_port(port_id: String) -> void:
	_home_port = port_id
	%MapView.selected_port = port_id
	var port := GameData.get_port(port_id)
	%PortName.text = "%s, %s" % [port.name, port.get("country", "")]
	_show_start_note()
	%StartNote.tooltip_text = %StartNote.text


func _selected_port() -> String:
	return _home_port


## What kind of start the chosen port is, and why.
func _show_start_note() -> void:
	var info := GameData.start_info(_selected_port())
	match info.get("kind", ""):
		"great":
			%StartNote.text = "Great start: %s" % info.note
		"harder":
			%StartNote.text = "Harder start: %s" % info.note
		"great_lakes":
			%StartNote.text = info.note
		_:
			%StartNote.text = ""


## One swatch per company color; the chosen one gets a white border (dark on
## the palest colors, so it shows).
func _add_color_swatches() -> void:
	var group := ButtonGroup.new()
	for entry: Array in GameData.config.get("company_colors", []):
		var swatch := Button.new()
		swatch.toggle_mode = true
		swatch.button_group = group
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.tooltip_text = entry[1]
		var color := Color.from_string(entry[2], Color.WHITE)
		for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"focus"]:
			swatch.add_theme_stylebox_override(style_name, _swatch_style(color, style_name in [&"pressed", &"hover_pressed"]))
		swatch.button_pressed = entry[0] == DEFAULT_COLOR
		swatch.pressed.connect(func() -> void: _color = entry[0])
		%ColorRow.add_child(swatch)


## A button per game speed (1x, 2x, 4x, 8x) for the fastest this company can
## run at; the fastest is picked to start with.
func _add_speed_choices() -> void:
	var group := ButtonGroup.new()
	for speed in GameState.TIME_SPEEDS:
		if speed == 0:
			continue
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(SWATCH_SIZE.x, 40)
		button.text = "%dx" % speed
		button.tooltip_text = "This company's game speed can go up to %dx." % speed
		button.button_pressed = speed == _max_speed
		button.pressed.connect(func() -> void: _max_speed = speed)
		%SpeedRow.add_child(button)


## A button per storm level (Weather.LEVELS: None, Moderate, Harsh); Moderate
## is picked to start with.
func _add_storm_choices() -> void:
	var group := ButtonGroup.new()
	var tips := {
		none = "No storms at all.",
		moderate = "Storms up to 40% slower and 2x wear at their core; only the strongest hurricane cores close ports.",
		harsh = "Storms up to 60% slower and 3x wear at their core, half as many again, and ports close more often.",
	}
	for level in Weather.LEVELS:
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(0, 40)
		button.text = " %s " % level.capitalize()
		button.tooltip_text = tips[level] + " Storms act on ships from company level 6."
		button.button_pressed = level == _storms
		button.pressed.connect(func() -> void: _storms = level)
		%StormRow.add_child(button)


static func _swatch_style(color: Color, chosen: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_border_width_all(3 if chosen else 0)
	style.border_color = Color(0.1, 0.12, 0.15) if color.get_luminance() > 0.8 else Color.WHITE
	return style


func _validate() -> bool:
	var error := GameState.company_name_error(%NameEdit.text)
	%StartButton.disabled = not error.is_empty()
	return error.is_empty()


## On to making the CEO (once the company's name will do).
func _start() -> void:
	if not _validate():
		return
	$Row.visible = false
	_ceo_page.visible = true
	_ceo_name.grab_focus()


# --- The CEO --------------------------------------------------------------------

## The CEO page, hidden till Next: the CEO standing on the left; their name
## (typed, or a random one), a row per part of their look (Characters.PARTS)
## to step through its options, Randomize, and Back or Found Company.
func _add_ceo_page() -> void:
	_ceo_page.visible = false
	_ceo_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ceo_page)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	_ceo_page.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 28)
	card.add_child(row)
	_ceo_portrait.custom_minimum_size = Vector2(250, 500)
	_ceo_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_ceo_portrait)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	row.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Your CEO"
	column.add_child(title)
	var name_row := HBoxContainer.new()
	_ceo_name.custom_minimum_size.x = 280
	_ceo_name.max_length = 32
	_ceo_name.placeholder_text = "Your CEO's name"
	_ceo_name.text_changed.connect(func(text: String) -> void:
		_ceo.name = text.strip_edges()
		_validate_ceo())
	name_row.add_child(_ceo_name)
	var random_name := Button.new()
	random_name.text = "Random name"
	random_name.pressed.connect(func() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_ceo.name = Characters.random_name(rng)
		_show_ceo())
	name_row.add_child(random_name)
	column.add_child(name_row)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 2)
	for part: Array in Characters.PARTS:
		var key: String = part[0]
		var title_label := Label.new()
		title_label.theme_type_variation = &"DimLabel"
		title_label.text = part[1]
		grid.add_child(title_label)
		grid.add_child(_step_button("<", key, -1))
		var value := Label.new()
		value.custom_minimum_size.x = 170
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_part_labels[key] = value
		grid.add_child(value)
		grid.add_child(_step_button(">", key, 1))
	column.add_child(grid)
	var randomize := Button.new()
	randomize.text = "Randomize looks"
	randomize.pressed.connect(func() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_ceo.look = Characters.random_look(rng)
		_show_ceo())
	column.add_child(randomize)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 8)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func() -> void:
		_ceo_page.visible = false
		$Row.visible = true)
	buttons.add_child(back)
	var found := Button.new()
	found.name = "FoundButton"
	found.text = "Found Company"
	found.custom_minimum_size = Vector2(0, 48)
	found.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	found.pressed.connect(_found)
	buttons.add_child(found)
	column.add_child(buttons)
	_show_ceo()


func _step_button(text: String, key: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(36, 0)
	button.pressed.connect(func() -> void:
		_ceo.look[key] = posmod(int(_ceo.look.get(key, 0)) + step, Characters.option_count(key))
		_show_ceo())
	return button


func _show_ceo() -> void:
	if _ceo_name.text.strip_edges() != _ceo.name:
		_ceo_name.text = _ceo.name
	for key: String in _part_labels:
		(_part_labels[key] as Label).text = Characters.option_name(key, int(_ceo.look.get(key, 0)))
	_ceo_portrait.character = _ceo
	_validate_ceo()


func _validate_ceo() -> void:
	var found: Button = _ceo_page.find_child("FoundButton", true, false)
	if found != null:
		found.disabled = str(_ceo.name).is_empty()


func _found() -> void:
	if str(_ceo.name).is_empty() or not _validate():
		return
	GameState.new_game(%NameEdit.text, _selected_port(), _color, {
		tutorials = %TutorialToggle.button_pressed,
		max_time_speed = _max_speed,
		storms = _storms,
		seasons = %SeasonsToggle.button_pressed,
		ceo = _ceo.duplicate(true),
	})
	if GameState.multiplayer_save:
		Net.host_error = Net.host(MainMenu.host_settings)  # Friends can join it; the game says if it couldn't.
	get_tree().change_scene_to_file(GAME_SCENE)

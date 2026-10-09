# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name NewCompany
extends Control
## New game setup: name the company, pick the home port new ships are delivered
## to on the globe (only the recommended starts from data/starts.json,
## excellent, great, fair and hard, and the Great Lakes ports, colored by kind,
## the excellent ones shining; the Great Lakes come with a warning), choose the
## company's color, its fastest game speed, its storms (none, moderate or
## harsh), and whether to have seasonal closures and the tutorial; then make
## the CEO: their name and looks (Characters), part by part or at random.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DEFAULT_HOME_PORT := "ROM"
const DEFAULT_COLOR := "purple"
const DEFAULT_STORMS := "moderate"
const SWATCH_SIZE := Vector2(56, 36)
## The starting ports' colors on the map (and their notes'), by kind of start:
## excellent a bright green (shining on the map), great green, fair yellow,
## hard red, the Great Lakes blue.
const START_COLORS := {excellent = Color(0.3, 1.0, 0.45), great = Color(0.3, 0.75, 0.35), fair = Color(1.0, 0.85, 0.25), hard = Color(0.95, 0.35, 0.3), great_lakes = Color(0.45, 0.75, 1.0)}
## What each kind of start is called in its note.
const START_TITLES := {excellent = "Excellent start", great = "Great start", fair = "Fair start", hard = "Hard start", great_lakes = "Great Lakes"}

var _home_port := DEFAULT_HOME_PORT
var _color := DEFAULT_COLOR
var _max_speed: int = GameState.TIME_SPEEDS[-1]
var _storms := DEFAULT_STORMS
## The CEO's page (see _add_ceo_page()).
var _ceo_page := CeoEditor.new()


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


## The starting ports on the map: the recommended starts (from
## data/starts.json) and the Great Lakes ports, each in its kind's color
## (START_COLORS); every other port is a faint dot that can't be picked.
func _add_ports() -> void:
	var map: MapView = %MapView
	map.selectable_ports = start_choices()
	map.shining_ports = shining_choices()
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
	%StartNote.text = start_note(_selected_port())
	%StartNote.add_theme_color_override(&"font_color", start_note_color(_selected_port()))


## The ports a company can start at, each in its kind of start's color
## (START_COLORS: MapView.selectable_ports), leaving out `taken` ones.
static func start_choices(taken: Array = []) -> Dictionary:
	var choices := {}
	for kind: String in GameData.START_KINDS:
		for entry: Dictionary in GameData.starts.get(kind, []):
			choices[entry.port] = START_COLORS[kind]
	for port_id: String in GameData.starts.get("great_lakes", {}).get("ports", []):
		choices[port_id] = START_COLORS.great_lakes
	for port_id: Variant in taken:
		choices.erase(port_id)
	return choices


## The excellent starts, which shine on the map (MapView.shining_ports).
static func shining_choices() -> Dictionary:
	var shining := {}
	for entry: Dictionary in GameData.starts.get("excellent", []):
		shining[entry.port] = true
	return shining


## "Great start: ..." (what kind of start a port is, and why), or "".
static func start_note(port_id: String) -> String:
	var info := GameData.start_info(port_id)
	if info.is_empty():
		return ""
	return "%s: %s" % [START_TITLES.get(info.kind, ""), info.note]


## The color of a port's start note: its kind's, lightened to read on the card.
static func start_note_color(port_id: String) -> Color:
	var kind: String = GameData.start_info(port_id).get("kind", "")
	return (START_COLORS[kind] as Color).lerp(Color.WHITE, 0.25) if START_COLORS.has(kind) else Color(0.75, 0.78, 0.82)


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
	_ceo_page.focus_name()


# --- The CEO --------------------------------------------------------------------

## The CEO page (CeoEditor), hidden till Next: Back returns to the company,
## Found Company starts the game.
func _add_ceo_page() -> void:
	_ceo_page.visible = false
	_ceo_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ceo_page.back_pressed.connect(func() -> void:
		_ceo_page.visible = false
		$Row.visible = true)
	_ceo_page.confirmed.connect(_found.unbind(1))
	add_child(_ceo_page)


func _found() -> void:
	if str(_ceo_page.ceo.name).is_empty() or not _validate():
		return
	GameState.new_game(%NameEdit.text, _selected_port(), _color, {
		tutorials = %TutorialToggle.button_pressed,
		max_time_speed = _max_speed,
		storms = _storms,
		seasons = %SeasonsToggle.button_pressed,
		ceo = _ceo_page.ceo.duplicate(true),
	})
	if GameState.multiplayer_save:
		Net.host_error = Net.host(MainMenu.host_settings)  # Friends can join it; the game says if it couldn't.
	get_tree().change_scene_to_file(GAME_SCENE)

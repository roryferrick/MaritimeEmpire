extends Control
## New game setup: name the company, pick the home port new ships are delivered
## to (recommended great and harder starts first, from data/starts.json, then
## every port), and choose the company's color.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DEFAULT_HOME_PORT := "ROM"
const DEFAULT_COLOR := "purple"
const SWATCH_SIZE := Vector2(56, 36)
const START_HEADINGS := {great = "Great starts", harder = "Harder starts"}

var _color := DEFAULT_COLOR


func _ready() -> void:
	%NameEdit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	_add_ports()
	%PortPicker.item_selected.connect(_show_start_note.unbind(1))
	_show_start_note()
	_add_color_swatches()
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_start.unbind(1))
	%StartButton.pressed.connect(_start)
	%BackButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%NameEdit.grab_focus()
	_validate()


## The recommended starts (great, then harder, each by name) and then every
## port a Scooter can start from (not starts.json's excluded ones) by name,
## under headings; each item's metadata is its port id.
func _add_ports() -> void:
	var picker: OptionButton = %PortPicker
	for kind: String in START_HEADINGS:
		var entries: Array = GameData.starts.get(kind, []).duplicate()
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return GameData.port_name(a.port) < GameData.port_name(b.port))
		picker.add_separator(START_HEADINGS[kind])
		for entry: Dictionary in entries:
			_add_port(GameData.get_port(entry.port))
	picker.add_separator("All ports")
	var excluded: Array = GameData.starts.get("excluded", [])
	for port in GameData.ports_by_name():
		if not excluded.has(port.id):
			_add_port(port)
	for i in picker.item_count:
		if picker.get_item_metadata(i) == DEFAULT_HOME_PORT:
			picker.select(i)
			return


func _add_port(port: Dictionary) -> void:
	var picker: OptionButton = %PortPicker
	picker.add_item("%s, %s" % [port.name, port.get("country", "")])
	picker.set_item_metadata(picker.item_count - 1, port.id)


func _selected_port() -> String:
	return str(%PortPicker.get_item_metadata(%PortPicker.selected))


## What kind of start the chosen port is, and why.
func _show_start_note() -> void:
	var info := GameData.start_info(_selected_port())
	match info.get("kind", ""):
		"great":
			%StartNote.text = "Great start: %s" % info.note
		"harder":
			%StartNote.text = "Harder start: %s" % info.note
		_:
			%StartNote.text = "Not a recommended start: Scooters find only thin trade in range."


## One swatch per company color; the chosen one gets a white border.
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


static func _swatch_style(color: Color, chosen: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.set_border_width_all(3 if chosen else 0)
	style.border_color = Color.WHITE
	return style


func _validate() -> bool:
	var error := GameState.company_name_error(%NameEdit.text)
	%StartButton.disabled = not error.is_empty()
	return error.is_empty()


func _start() -> void:
	if not _validate():
		return
	GameState.new_game(%NameEdit.text, _selected_port(), _color)
	get_tree().change_scene_to_file(GAME_SCENE)

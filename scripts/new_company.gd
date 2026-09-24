extends Control
## New game setup: name the company, pick the home port new ships are delivered
## to, and choose the company's color.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DEFAULT_HOME_PORT := "ROM"
const DEFAULT_COLOR := "purple"
const SWATCH_SIZE := Vector2(56, 36)

var _port_ids: Array[String] = []
var _color := DEFAULT_COLOR


func _ready() -> void:
	%NameEdit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	for port in GameData.ports_by_name():
		%PortPicker.add_item("%s, %s" % [port.name, port.get("country", "")])
		_port_ids.append(port.id)
	%PortPicker.select(maxi(0, _port_ids.find(DEFAULT_HOME_PORT)))
	_add_color_swatches()
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_start.unbind(1))
	%StartButton.pressed.connect(_start)
	%BackButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%NameEdit.grab_focus()
	_validate()


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
	GameState.new_game(%NameEdit.text, _port_ids[%PortPicker.selected], _color)
	get_tree().change_scene_to_file(GAME_SCENE)

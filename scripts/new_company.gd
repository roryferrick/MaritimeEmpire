extends Control
## New game setup: name the company and pick the home port new ships are delivered to.

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const DEFAULT_HOME_PORT := "ROM"

var _port_ids: Array[String] = []


func _ready() -> void:
	%NameEdit.max_length = GameState.MAX_COMPANY_NAME_LENGTH
	for port in GameData.ports_by_name():
		%PortPicker.add_item("%s, %s" % [port.name, port.get("country", "")])
		_port_ids.append(port.id)
	%PortPicker.select(maxi(0, _port_ids.find(DEFAULT_HOME_PORT)))
	%NameEdit.text_changed.connect(_validate.unbind(1))
	%NameEdit.text_submitted.connect(_start.unbind(1))
	%StartButton.pressed.connect(_start)
	%BackButton.pressed.connect(func() -> void: get_tree().change_scene_to_file(MAIN_MENU_SCENE))
	%NameEdit.grab_focus()
	_validate()


func _validate() -> bool:
	var error := GameState.company_name_error(%NameEdit.text)
	%StartButton.disabled = not error.is_empty()
	return error.is_empty()


func _start() -> void:
	if not _validate():
		return
	GameState.new_game(%NameEdit.text, _port_ids[%PortPicker.selected])
	get_tree().change_scene_to_file(GAME_SCENE)

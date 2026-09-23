extends Control

const GAME_SCENE := "res://scenes/game.tscn"
const NEW_COMPANY_SCENE := "res://scenes/new_company.tscn"


func _ready() -> void:
	%NewGameButton.pressed.connect(_on_new_game_pressed)
	%ContinueButton.pressed.connect(_on_continue_pressed)
	%QuitButton.pressed.connect(get_tree().quit)
	%OverwriteDialog.confirmed.connect(_start_new_game)
	%ContinueButton.disabled = not GameState.has_save()


func _on_new_game_pressed() -> void:
	if GameState.has_save():
		%OverwriteDialog.popup_centered()
	else:
		_start_new_game()


func _start_new_game() -> void:
	get_tree().change_scene_to_file(NEW_COMPANY_SCENE)


func _on_continue_pressed() -> void:
	var error := GameState.continue_game()
	if error.is_empty():
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		%ErrorDialog.dialog_text = error
		%ErrorDialog.popup_centered()

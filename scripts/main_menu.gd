extends Control
## Title screen: a row per save slot (Continue a company, or start a New Game
## in an empty slot, and Delete), and Quit.

const GAME_SCENE := "res://scenes/game.tscn"
const NEW_COMPANY_SCENE := "res://scenes/new_company.tscn"
const SLOT_BUTTON_SIZE := Vector2(420, 64)
const DELETE_BUTTON_SIZE := Vector2(96, 64)

## The slot DeleteDialog is asking about.
var _deleting := 0


func _ready() -> void:
	%QuitButton.pressed.connect(get_tree().quit)
	%DeleteDialog.confirmed.connect(_delete)
	_show_slots()


func _show_slots() -> void:
	for child in %Slots.get_children():
		child.queue_free()
	for slot in range(1, GameState.SAVE_SLOTS + 1):
		%Slots.add_child(_slot_row(slot))


## A slot's button (its company, money and date, or New Game when empty) and,
## when it holds a save, a Delete button.
func _slot_row(slot: int) -> HBoxContainer:
	var summary := GameState.save_summary(slot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var button := Button.new()
	button.custom_minimum_size = SLOT_BUTTON_SIZE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(button)
	if summary.is_empty():
		button.text = "Slot %d  ·  New Game" % slot
		button.pressed.connect(_start_new_game.bind(slot))
		return row
	if summary.has("error"):
		button.text = "Slot %d  ·  %s" % [slot, summary.error]
		button.disabled = true
	else:
		button.text = "Slot %d  ·  %s\n%s  ·  %s" % [slot, summary.company_name, Fmt.money(summary.money), Fmt.calendar(summary.date)]
		button.add_theme_color_override("font_color", GameState.company_color_value(summary.company_color))
		button.pressed.connect(_continue.bind(slot))
	var delete := Button.new()
	delete.custom_minimum_size = DELETE_BUTTON_SIZE
	delete.text = "Delete"
	delete.pressed.connect(_confirm_delete.bind(slot, summary.get("company_name", "")))
	row.add_child(delete)
	return row


func _start_new_game(slot: int) -> void:
	GameState.save_slot = slot
	get_tree().change_scene_to_file(NEW_COMPANY_SCENE)


func _continue(slot: int) -> void:
	var error := GameState.continue_game(slot)
	if error.is_empty():
		get_tree().change_scene_to_file(GAME_SCENE)
	else:
		%ErrorDialog.dialog_text = error
		%ErrorDialog.popup_centered()


func _confirm_delete(slot: int, company: String) -> void:
	_deleting = slot
	var what := company if not company.is_empty() else "this save"
	%DeleteDialog.dialog_text = "Delete %s in slot %d? This can't be undone." % [what, slot]
	%DeleteDialog.popup_centered()


func _delete() -> void:
	GameState.delete_save(_deleting)
	_show_slots()

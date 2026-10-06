extends Control
## Title screen: Single Player or Multiplayer, then that mode's save slots (a
## row per slot: Continue a company, or start a New Game in an empty slot, and
## Delete), with Back; and Quit. Multiplayer saves are kept apart from single
## player ones and played solo until hosting is built.

const GAME_SCENE := "res://scenes/game.tscn"
const NEW_COMPANY_SCENE := "res://scenes/new_company.tscn"
const SLOT_BUTTON_SIZE := Vector2(420, 92)
const DELETE_BUTTON_SIZE := Vector2(96, 92)
const MODE_BUTTON_SIZE := Vector2(420, 64)
const MODES := {false: "Single Player", true: "Multiplayer"}
const MULTIPLAYER_NOTE := "Played solo for now: hosting and joining friends' games are coming."

## The page shown when the menu opens: "" for the mode choice, or "single" or
## "multi" for that mode's slots (so Back from New Company returns to them).
static var page := ""

## The slot DeleteDialog is asking about.
var _deleting := 0


func _ready() -> void:
	%QuitButton.pressed.connect(get_tree().quit)
	%DeleteDialog.confirmed.connect(_delete)
	if page.is_empty():
		_show_modes()
	else:
		_show_slots(page == "multi")


func _clear() -> void:
	for child in %Slots.get_children():
		%Slots.remove_child(child)
		child.queue_free()


## Single Player and Multiplayer.
func _show_modes() -> void:
	page = ""
	_clear()
	for online: bool in MODES:
		var button := Button.new()
		button.custom_minimum_size = MODE_BUTTON_SIZE
		button.text = MODES[online]
		button.pressed.connect(_show_slots.bind(online))
		%Slots.add_child(button)


## A mode's heading, its save slots and Back.
func _show_slots(online: bool) -> void:
	page = "multi" if online else "single"
	GameState.multiplayer_save = online
	_clear()
	var heading := Label.new()
	heading.text = MODES[online]
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override(&"font_size", 22)
	%Slots.add_child(heading)
	if online:
		var note := Label.new()
		note.text = MULTIPLAYER_NOTE
		note.theme_type_variation = &"DimLabel"
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		%Slots.add_child(note)
	for slot in range(1, GameState.SAVE_SLOTS + 1):
		%Slots.add_child(_slot_row(slot))
	var back := Button.new()
	back.custom_minimum_size = Vector2(280, 48)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.text = "Back"
	back.pressed.connect(_show_modes)
	%Slots.add_child(back)


## A slot's button (its company; home port, money and date; storms, seasonal
## closures and fastest game speed; or New Game when empty) and, when it holds
## a save, a Delete button.
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
		button.text = "Slot %d  ·  %s\n%s  ·  %s  ·  %s\n%s  ·  %s  ·  up to %dx" % [slot, summary.company_name,
			GameData.port_name(summary.home_port), Fmt.money(summary.money), Fmt.calendar(summary.date),
			Weather.LEVEL_NAMES.get(summary.storms, "No storms"), "Seasonal closures" if summary.seasons else "No seasonal closures",
			summary.max_time_speed]
		GameState.apply_company_text_color(button, summary.company_color)
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
	%DeleteDialog.dialog_text = "Delete %s in %s slot %d? This can't be undone." % [what, MODES[GameState.multiplayer_save].to_lower(), slot]
	%DeleteDialog.popup_centered()


func _delete() -> void:
	GameState.delete_save(_deleting)
	_show_slots(GameState.multiplayer_save)

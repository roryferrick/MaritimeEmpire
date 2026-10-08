# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CeoEditor
extends CenterContainer
## Making a company's CEO (a new game's, or a joining player's): the CEO
## standing on the left; their name (typed, or a random one), a row per part
## of their look (Characters.PARTS) to step through its options, Randomize,
## and Back or the confirm button. Fills what it's put in.

## Back was pressed.
signal back_pressed
## The confirm button was pressed, with the CEO (Characters: {name, look}).
signal confirmed(ceo: Dictionary)

## The CEO being made (Characters: {name, look}).
var ceo := Company.random_ceo()

var _confirm_text := "Found Company"
var _portrait := Portrait.new()
var _name := LineEdit.new()
var _confirm := Button.new()
var _part_labels := {}


func _init(confirm_text := "Found Company") -> void:
	_confirm_text = confirm_text


func _ready() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 28)
	card.add_child(row)
	_portrait.custom_minimum_size = Vector2(250, 500)
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_portrait)
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 6)
	row.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Your CEO"
	column.add_child(title)
	var name_row := HBoxContainer.new()
	_name.custom_minimum_size.x = 280
	_name.max_length = Characters.MAX_NAME_LENGTH
	_name.placeholder_text = "Your CEO's name"
	_name.text_changed.connect(func(text: String) -> void:
		ceo.name = text.strip_edges()
		_validate())
	name_row.add_child(_name)
	var random_name := Button.new()
	random_name.text = "Random name"
	random_name.pressed.connect(func() -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		ceo.name = Characters.random_name(rng)
		_show())
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
		ceo.look = Characters.random_look(rng)
		_show())
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
	back.pressed.connect(back_pressed.emit)
	buttons.add_child(back)
	_confirm.text = _confirm_text
	_confirm.custom_minimum_size = Vector2(0, 48)
	_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm.pressed.connect(func() -> void:
		if not str(ceo.name).is_empty():
			confirmed.emit(ceo))
	buttons.add_child(_confirm)
	column.add_child(buttons)
	_show()


## Puts the cursor in the name box.
func focus_name() -> void:
	_name.grab_focus()


func _step_button(text: String, key: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(36, 0)
	button.pressed.connect(func() -> void:
		ceo.look[key] = posmod(int(ceo.look.get(key, 0)) + step, Characters.option_count(key))
		_show())
	return button


func _show() -> void:
	if _name.text.strip_edges() != ceo.name:
		_name.text = ceo.name
	for key: String in _part_labels:
		(_part_labels[key] as Label).text = Characters.option_name(key, int(ceo.look.get(key, 0)))
	_portrait.character = ceo
	_validate()


func _validate() -> void:
	_confirm.disabled = str(ceo.name).is_empty()

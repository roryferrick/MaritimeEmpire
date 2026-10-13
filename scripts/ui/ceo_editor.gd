# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CeoEditor
extends CenterContainer
## Making a company's CEO (a new game's, or a joining player's): the CEO
## standing on the left; their name (typed, or a random one), Male or Female,
## the Height and Build sliders, then the face parts in one column and the
## outfit in another (Characters.PARTS), each stepped through its options
## with < and >, Randomize, and Back or the confirm button. Fills what it's put in.

## Back was pressed.
signal back_pressed
## The confirm button was pressed, with the CEO (Characters: {name, look}).
signal confirmed(ceo: Dictionary)

## The parts listed under Face and under Outfit (the body is its own row).
const FACE_PARTS := ["skin", "eye_shape", "eye_color", "nose", "mouth", "hair", "hair_color", "facial_hair"]
const OUTFIT_PARTS := ["top", "bottoms", "shoes", "eyewear", "headwear"]

## The CEO being made (Characters: {name, look}).
var ceo := Company.random_ceo()

var _confirm_text := "Found Company"
var _portrait := Portrait.new()
var _name := LineEdit.new()
var _confirm := Button.new()
var _part_labels := {}
var _body_buttons: Array[Button] = []
var _sliders := {}


func _init(confirm_text := "Found Company") -> void:
	_confirm_text = confirm_text


func _ready() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
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
	# The name.
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 8)
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
	# The body: Male or Female, and the height and build sliders.
	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override(&"separation", 8)
	var body_label := Label.new()
	body_label.theme_type_variation = &"DimLabel"
	body_label.text = "Body"
	body_label.custom_minimum_size.x = 80
	body_row.add_child(body_label)
	var group := ButtonGroup.new()
	for index in Characters.option_count("body"):
		var button := Button.new()
		button.text = Characters.option_name("body", index)
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(96, 0)
		button.pressed.connect(func() -> void:
			ceo.look.body = index
			_show())
		_body_buttons.append(button)
		body_row.add_child(button)
	column.add_child(body_row)
	for slide: Array in Characters.SLIDERS:
		var key: String = slide[0]
		var slider_row := HBoxContainer.new()
		slider_row.add_theme_constant_override(&"separation", 8)
		var label := Label.new()
		label.theme_type_variation = &"DimLabel"
		label.text = str(slide[1])
		label.custom_minimum_size.x = 80
		slider_row.add_child(label)
		var low := Label.new()
		low.theme_type_variation = &"DimLabel"
		low.text = str(slide[2])
		slider_row.add_child(low)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.custom_minimum_size.x = 260
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(value: float) -> void:
			ceo.look[key] = int(value)
			_portrait.character = ceo)
		_sliders[key] = slider
		slider_row.add_child(slider)
		var high := Label.new()
		high.theme_type_variation = &"DimLabel"
		high.text = str(slide[3])
		slider_row.add_child(high)
		column.add_child(slider_row)
	# The face and the outfit, side by side.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 20)
	columns.add_child(_part_grid("Face", FACE_PARTS))
	columns.add_child(_part_grid("Outfit", OUTFIT_PARTS))
	column.add_child(columns)
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


## A titled grid of parts, each a row: its title, <, the option's name, >.
func _part_grid(title: String, keys: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	var heading := Label.new()
	heading.text = title
	box.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 2)
	for part: Array in Characters.PARTS:
		var key: String = part[0]
		if not keys.has(key):
			continue
		var title_label := Label.new()
		title_label.theme_type_variation = &"DimLabel"
		title_label.text = part[1]
		title_label.custom_minimum_size.x = 76
		grid.add_child(title_label)
		grid.add_child(_step_button("<", key, -1))
		var value := Label.new()
		value.custom_minimum_size.x = 150
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_part_labels[key] = value
		grid.add_child(value)
		grid.add_child(_step_button(">", key, 1))
	box.add_child(grid)
	return box


func _step_button(text: String, key: String, step: int) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(34, 0)
	button.pressed.connect(func() -> void:
		var count := Characters.option_count(key)
		var index := int(ceo.look.get(key, 0))
		for n in count:  # (A skin pack's options only once the pack is owned: see Cosmetics.)
			index = posmod(index + step, count)
			if Cosmetics.allowed(key, index):
				break
		ceo.look[key] = index
		_show())
	return button


func _show() -> void:
	if _name.text.strip_edges() != ceo.name:
		_name.text = ceo.name
	for key: String in _part_labels:
		(_part_labels[key] as Label).text = Characters.option_name(key, int(ceo.look.get(key, 0)))
	var body := clampi(int(ceo.look.get("body", 0)), 0, _body_buttons.size() - 1)
	for index in _body_buttons.size():
		_body_buttons[index].set_pressed_no_signal(index == body)
	for key: String in _sliders:
		(_sliders[key] as HSlider).set_value_no_signal(Characters.slider(ceo.look, key))
	_portrait.character = ceo
	_validate()


func _validate() -> void:
	_confirm.disabled = str(ceo.name).is_empty()

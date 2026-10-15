# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CompanyTypeCards
extends HBoxContainer
## The company types side by side, a card each (game_config company_types):
## its icon and name in its color, what it carries, a picture of each of its
## first ships, and its lines' ships tier by tier.
##
## Founding (picking = false), clicking a card selects it (selected(), the
## chosen card outlined in its color). Picking another type in a game
## (picking = true), the types the company has are greyed and each other card
## has a Choose button, pressed twice (the second time to confirm): chosen().

signal selected(type_id: String)
signal chosen(type_id: String)

## What each ship line is called on the cards.
const LINE_TITLES := {container = "Container ships", ore = "Ore carriers", grain = "Grain carriers", livestock = "Livestock carriers", produce = "Fresh produce carriers",
	tanker = "Tankers", vehicles = "Car carriers", boat_carriers = "Boat carriers", fishing = "Fishing boats", crabbing = "Crabbing boats", seafood = "Seafood carriers", cruise_ocean = "Ocean cruisers", cruise_expedition = "Expedition cruisers"}
const CARD_WIDTH := 196.0  # (Six across within the 1280 px screen.)
const ICON_SIZE := 40.0
const PICTURE_LENGTH := 78.0
const NAME_FONT_SIZE := 16

var picking := false
## The types the company has already (picking): greyed, not choosable.
var taken: Array = []
var selected_type := ""

var _cards := {}  # type id -> PanelContainer
var _buttons := {}  # type id -> its Choose button (picking)
var _armed := ""


func _init(for_picking := false, company_taken: Array = []) -> void:
	picking = for_picking
	taken = company_taken
	add_theme_constant_override(&"separation", 8)
	alignment = BoxContainer.ALIGNMENT_CENTER


func _ready() -> void:
	for type: Dictionary in Progression.company_types():
		var card := _card(type)
		_cards[type.id] = card
		add_child(card)
	_restyle()


## Selects a type's card (founding), as a click on it would.
func select(type_id: String) -> void:
	selected_type = type_id
	_restyle()
	selected.emit(type_id)


func _card(type: Dictionary) -> PanelContainer:
	var type_id := str(type.id)
	var color := CompanyTypeIcon.type_color(type_id)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.mouse_filter = MOUSE_FILTER_STOP
	if not picking:
		card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		card.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				select(type_id))
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	header.mouse_filter = MOUSE_FILTER_IGNORE
	var icon := CompanyTypeIcon.new(type_id)
	icon.custom_minimum_size = Vector2.ONE * ICON_SIZE
	header.add_child(icon)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = str(type.name)
	name_label.add_theme_color_override(&"font_color", color)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)  # (Small enough that "Agriculture" fits on one line.)
	header.add_child(name_label)
	box.add_child(header)
	var blurb := _text(str(type.get("blurb", "")), &"")
	blurb.add_theme_font_size_override(&"font_size", 14)
	box.add_child(blurb)
	box.add_child(_text("First ships" if not picking else "Its first ships", &"DimLabel"))
	var firsts := HBoxContainer.new()
	firsts.add_theme_constant_override(&"separation", 8)
	firsts.mouse_filter = MOUSE_FILTER_IGNORE
	var models := _line_models(type, 1)
	# The pictures share the card's width (up to PICTURE_LENGTH each).
	var length := minf(PICTURE_LENGTH, (CARD_WIDTH - 24.0 - 8.0 * (models.size() - 1)) / maxf(models.size(), 1.0))
	for model: Dictionary in models:
		var first := VBoxContainer.new()
		first.mouse_filter = MOUSE_FILTER_IGNORE
		var picture := ShipPicture.new(model, length)
		picture.custom_minimum_size = Vector2(length, 30)
		first.add_child(picture)
		var label := _text(str(model.name), &"DimLabel")
		label.custom_minimum_size.x = length
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override(&"font_size", 12)
		first.add_child(label)
		firsts.add_child(first)
	box.add_child(firsts)
	for category: String in type.categories:
		var names := GameData.ship_models.filter(func(model: Dictionary) -> bool: return model.get("category", "") == category)
		names.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("tier", 1)) < int(b.get("tier", 1)))
		var line := _text("%s: %s" % [LINE_TITLES.get(category, category), ", ".join(names.map(func(model: Dictionary) -> String: return str(model.name)))], &"DimLabel")
		line.add_theme_font_size_override(&"font_size", 11)
		box.add_child(line)
	if picking:
		var spacer := Control.new()
		spacer.size_flags_vertical = SIZE_EXPAND_FILL
		spacer.mouse_filter = MOUSE_FILTER_IGNORE
		box.add_child(spacer)
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 36)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = taken.has(type_id)
		button.text = "Your company has it" if taken.has(type_id) else "Choose %s" % type.name
		button.pressed.connect(_on_choose.bind(type_id))
		box.add_child(button)
		_buttons[type_id] = button
	return card


## The type's tier-N models, line by line.
static func _line_models(type: Dictionary, tier: int) -> Array:
	var models := []
	for category: String in type.categories:
		for model: Dictionary in GameData.ship_models:
			if model.get("category", "") == category and int(model.get("tier", 1)) == tier:
				models.append(model)
	return models


func _text(text: String, variation: StringName) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = CARD_WIDTH - 24.0
	label.mouse_filter = MOUSE_FILTER_IGNORE
	return label


## The first press arms a type's Choose button ("Confirm: ..."), the second chooses it.
func _on_choose(type_id: String) -> void:
	if _armed != type_id:
		_armed = type_id
		for each: String in _buttons:
			if not taken.has(each):
				(_buttons[each] as Button).text = ("Confirm: take %s" if each == type_id else "Choose %s") % Progression.type_name(each)
		return
	chosen.emit(type_id)


## Each card's panel: outlined in its type's color when selected, faded when taken.
func _restyle() -> void:
	for type_id: String in _cards:
		var card: PanelContainer = _cards[type_id]
		var color := CompanyTypeIcon.type_color(type_id)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.09, 0.13, 0.2, 0.96).lerp(color, 0.08)
		style.set_corner_radius_all(10)
		style.set_content_margin_all(12)
		style.set_border_width_all(3 if type_id == selected_type else 1)
		style.border_color = color if type_id == selected_type else Color(color, 0.35)
		card.add_theme_stylebox_override(&"panel", style)
		card.modulate.a = 0.5 if taken.has(type_id) else 1.0

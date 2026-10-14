# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SkinPicker
extends Control
## A ship's skin (the Skin button on its popup): the skins this player owns
## that fit its model (Cosmetics.skins_for_model()), each with its picture
## and name, and the base ship, and "as the Inventory" (the model's choice
## there, or the pack worn: Ship.skin ""). Picking one sets it (GameState.set_skin()) and closes.
## Over whatever opened it, dimming it; Esc, X or a click outside closes it.

const PICTURE := Vector2(144, 42)

var ship: Ship


func _init(for_ship: Ship) -> void:
	ship = for_ship


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	card.add_child(content)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Skins for %s" % ship.name
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "The %s skins you own. More are in the Shop on the title screen; the Inventory there sets what each model wears by default." % str(ship.model().get("name", ""))
	content.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 8)
	grid.add_theme_constant_override(&"v_separation", 8)
	content.add_child(grid)
	var choices := [["", "As the Inventory", null, "What the Inventory (on the title screen) sets for this model, or the pack worn"], ["base", "Base ship", null, "The ship as it is"]]
	for skin: Dictionary in Cosmetics.skins_for_model(ship.model_id):
		choices.append([Cosmetics.skin_key(str(skin.pack), str(skin.id)), str(skin.name), skin.texture, str(skin.pack_title)])
	for choice: Array in choices:
		grid.add_child(_choice(str(choice[0]), str(choice[1]), choice[2], str(choice[3])))


## One choice: its picture over its name, the current one marked.
func _choice(key: String, text: String, texture: Texture2D, tip: String) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(PICTURE.x + 24, PICTURE.y + 52)
	button.tooltip_text = tip
	button.focus_mode = FOCUS_NONE
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	box.mouse_filter = MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override(&"separation", 4)
	var picture: Control
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture = rect
	else:
		picture = BasePicture.new(ship.model(), key == "base")
	picture.custom_minimum_size = PICTURE
	picture.size_flags_horizontal = SIZE_SHRINK_CENTER
	picture.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(picture)
	var label := Label.new()
	label.text = ("✓ " if ship.skin == key else "") + text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 13)
	label.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(label)
	button.add_child(box)
	button.pressed.connect(func() -> void:
		GameState.set_skin(ship, key)
		queue_free())
	return button


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


## The ship as it is: its hull in its map colour with its details (and, for
## "as the Inventory", the same with a question mark over it).
class BasePicture extends Control:
	var model: Dictionary
	var plain: bool

	func _init(for_model: Dictionary, is_base: bool) -> void:
		model = for_model
		plain = is_base

	func _draw() -> void:
		var art := MapView.load_ship_art(str(model.get("art", model.get("category", ""))))
		if art.is_empty():
			return
		var hull: Texture2D = art.hull
		var fit := minf(size.x / hull.get_width(), size.y / hull.get_height())
		var drawn := Vector2(hull.get_size()) * fit
		var rect := Rect2((size - drawn) / 2.0, drawn)
		draw_texture_rect(hull, rect, false, Color.from_string(str(model.get("map_color", "#ffffff")), Color.WHITE))
		draw_texture_rect(art.details, rect, false)
		if not plain:
			draw_rect(rect, Color(0, 0, 0, 0.35))
			var font := get_theme_default_font()
			draw_string(font, Vector2(size.x / 2.0 - 6.0, size.y / 2.0 + 7.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

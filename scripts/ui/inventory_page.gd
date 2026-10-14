# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name InventoryPage
extends Control
## The Inventory (from the title screen, under the Shop): every skin this
## player owns, and where they're worn, in two tabs. Ship skins: a pack worn on
## all the ships it fits (Cosmetics.equip(), one at a time), then each model
## with skins owned for it, with its own choice over the pack (the pack worn,
## the base ship, or any owned skin that fits: Cosmetics.set_model_skin()),
## then every owned ship skin by pack, with its picture, who wears it and
## "Wear on its ships" (sets it for each of its models). Outfits: every owned
## outfit with its portrait and what it unlocks (chosen in Found Company and
## the CEO editor; hats and colours on the Uniforms page). A ship's own
## choice (its popup's Skin) still wins over all of these. Over whatever
## opened it, dimming it; Esc, X or a click outside closes it.

const PANEL_SIZE := Vector2(1120, 640)
const SKIN_COLUMNS := 4
const MODEL_PICTURE := Vector2(120, 36)

var _ships_box := VBoxContainer.new()
var _outfits_box := VBoxContainer.new()


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
	card.custom_minimum_size = PANEL_SIZE
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 12)
	card.add_child(content)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Inventory"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(tabs)
	tabs.add_child(_tab("Ship skins", _ships_box))
	tabs.add_child(_tab("Outfits", _outfits_box))
	Cosmetics.changed.connect(_show)
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _tab(tab_name: String, box: VBoxContainer) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 12)
	scroll.add_child(box)
	return scroll


func _show() -> void:
	for box: VBoxContainer in [_ships_box, _outfits_box]:
		for child in box.get_children():
			child.queue_free()
	_show_ships()
	_show_outfits()


# --- Ship skins ---------------------------------------------------------------------

func _show_ships() -> void:
	var packs := []  # Packs with an owned ship skin.
	for it: Dictionary in Cosmetics.catalog.get("packs", []):
		if Cosmetics.wearable(str(it.id)):
			packs.append(it)
	if packs.is_empty():
		_ships_box.add_child(_note("You don't own any ship skins yet: they're in the Shop, on the title screen."))
		return
	_ships_box.add_child(_note("What your ships wear by default. A ship's own choice (Skin, in its popup) still wins."))
	# A whole pack worn.
	var wear_row := HBoxContainer.new()
	wear_row.add_theme_constant_override(&"separation", 8)
	var wear_label := Label.new()
	wear_label.text = "Pack worn:"
	wear_row.add_child(wear_label)
	var packs_menu := OptionButton.new()
	packs_menu.add_item("None")
	packs_menu.set_item_metadata(0, "")
	for it: Dictionary in packs:
		packs_menu.add_item(str(it.title))
		packs_menu.set_item_metadata(packs_menu.item_count - 1, str(it.id))
		if Cosmetics.equipped == str(it.id):
			packs_menu.select(packs_menu.item_count - 1)
	packs_menu.tooltip_text = "Your ships wear this pack's skins you own, unless their model has its own choice below."
	packs_menu.item_selected.connect(func(index: int) -> void: Cosmetics.equip(str(packs_menu.get_item_metadata(index))))
	wear_row.add_child(packs_menu)
	_ships_box.add_child(wear_row)
	# Each model with skins owned for it, and its own choice.
	_ships_box.add_child(_heading("By ship"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 24)
	grid.add_theme_constant_override(&"v_separation", 8)
	for model: Dictionary in GameData.ship_models:
		var skins := Cosmetics.skins_for_model(str(model.id))
		if not skins.is_empty():
			grid.add_child(_model_row(model, skins))
	_ships_box.add_child(grid)
	# Every owned ship skin, by pack.
	for it: Dictionary in packs:
		var id := str(it.id)
		_ships_box.add_child(_heading(str(it.title)))
		var skins_grid := GridContainer.new()
		skins_grid.columns = SKIN_COLUMNS
		skins_grid.add_theme_constant_override(&"h_separation", 8)
		skins_grid.add_theme_constant_override(&"v_separation", 8)
		for skin: Dictionary in Cosmetics.ship_skins(id):
			if Cosmetics.owns_skin(id, str(skin.id)):
				skins_grid.add_child(_ship_skin_panel(id, skin))
		_ships_box.add_child(skins_grid)


## A model's row: its picture as it will look, its name, and its choice.
func _model_row(model: Dictionary, skins: Array) -> Control:
	var model_id := str(model.id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var picture := TextureRect.new()
	picture.custom_minimum_size = MODEL_PICTURE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var worn := Cosmetics.default_skin(model_id)
	if worn != null:
		picture.texture = worn
		row.add_child(picture)
	else:
		var base := ShipPicture.new(model, MODEL_PICTURE.x)
		base.custom_minimum_size = MODEL_PICTURE
		row.add_child(base)
	var name := Label.new()
	name.text = str(model.name)
	name.custom_minimum_size = Vector2(140, 0)
	name.clip_text = true
	name.add_theme_color_override(&"font_color", Color.from_string(str(model.get("map_color", "#ffffff")), Color.WHITE).lightened(0.2))
	row.add_child(name)
	var menu := OptionButton.new()
	menu.custom_minimum_size = Vector2(230, 0)
	menu.fit_to_longest_item = false  # (Long skin names would widen the page past the screen.)
	menu.clip_text = true
	var pack_title := str(Cosmetics.pack(Cosmetics.equipped).get("title", ""))
	var choices := [["", "Pack worn" if not pack_title.is_empty() else "Base ship (no pack worn)"], ["base", "Base ship"]]
	for skin: Dictionary in skins:
		choices.append([Cosmetics.skin_key(str(skin.pack), str(skin.id)), "%s (%s)" % [skin.name, skin.pack_title]])
	var now := str(Cosmetics.model_skins.get(model_id, ""))
	for choice: Array in choices:
		menu.add_item(str(choice[1]))
		menu.set_item_metadata(menu.item_count - 1, choice[0])
		if choice[0] == now:
			menu.select(menu.item_count - 1)
	menu.item_selected.connect(func(index: int) -> void: Cosmetics.set_model_skin(model_id, str(menu.get_item_metadata(index))))
	row.add_child(menu)
	return row


## An owned ship skin: its picture, name, who wears it, and Wear on its ships.
func _ship_skin_panel(pack_id: String, skin: Dictionary) -> Control:
	var key := Cosmetics.skin_key(pack_id, str(skin.id))
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"MapPopup"
	panel.custom_minimum_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	var picture := SkinShop._ship_picture(pack_id, skin)
	picture.custom_minimum_size = Vector2(0, 110)
	box.add_child(picture)
	var name := Label.new()
	name.text = str(skin.name)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var models: Array = skin.models
	var info := Label.new()
	info.theme_type_variation = &"DimLabel"
	info.add_theme_font_size_override(&"font_size", 12)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.text = SkinShop._models_text(models)
	box.add_child(info)
	var wearing := models.all(func(model_id: String) -> bool: return Cosmetics.model_skins.get(model_id, "") == key)
	var button := Button.new()
	button.add_theme_font_size_override(&"font_size", 13)
	button.text = "✓ Worn" if wearing else "Wear on its ships"
	button.disabled = wearing
	button.tooltip_text = "Every %s you own wears it (unless a ship has its own choice)." % ", ".join(models.map(func(model_id: String) -> String: return str(GameData.get_ship_model(model_id).get("name", model_id))))
	button.pressed.connect(func() -> void:
		for model_id: String in models:
			Cosmetics.set_model_skin(model_id, key))
	box.add_child(button)
	return panel


# --- Outfits ------------------------------------------------------------------------

func _show_outfits() -> void:
	var any := false
	for it: Dictionary in Cosmetics.catalog.get("packs", []):
		var id := str(it.id)
		var owned := Cosmetics.outfits(id).filter(func(outfit: Dictionary) -> bool: return Cosmetics.owns_skin(id, str(outfit.id)))
		if owned.is_empty():
			continue
		if not any:
			_outfits_box.add_child(_note("Your outfits' clothes are yours to choose for your CEO in Found Company and the CEO editor, and for your captains; their crew hats and colours are on the Uniforms page (the Ships tab in a game)."))
			any = true
		_outfits_box.add_child(_heading(str(it.title)))
		var grid := GridContainer.new()
		grid.columns = SKIN_COLUMNS
		grid.add_theme_constant_override(&"h_separation", 8)
		grid.add_theme_constant_override(&"v_separation", 8)
		for outfit: Dictionary in owned:
			var panel := PanelContainer.new()
			panel.theme_type_variation = &"MapPopup"
			panel.custom_minimum_size = Vector2(250, 0)
			var box := VBoxContainer.new()
			panel.add_child(box)
			box.add_child(SkinShop._outfit_picture(outfit))
			var name := Label.new()
			name.text = str(outfit.name)
			name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(name)
			var info := Label.new()
			info.theme_type_variation = &"DimLabel"
			info.add_theme_font_size_override(&"font_size", 12)
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.text = SkinShop._outfit_text(outfit)
			box.add_child(info)
			grid.add_child(panel)
		_outfits_box.add_child(grid)
	if not any:
		_outfits_box.add_child(_note("You don't own any outfits yet: they're in the Shop, on the title screen."))


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 18)
	return label


func _note(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SkinShop
extends Control
## The Shop (from the Esc menu), in two tabs. Skin packs: every pack on sale
## (Cosmetics.packs_for_sale()), each with its ship skins and its outfits
## sold one at a time (a Sand Dollar price each), or all its ship skins, all
## its outfits, or the whole pack at once (a bundle never charges for skins
## already owned); a pack with an owned ship skin can be worn (one pack at a
## time), and an owned outfit's options are in Found Company and on the
## Uniforms page. Sand Dollars: the balance and the bundles bought with Steam
## money (Cosmetics.buy_bundle()). Over whatever opened it, dimming it; Esc, X
## or a click outside closes it.

const PANEL_SIZE := Vector2(760, 0)

var _packs_box := VBoxContainer.new()
var _balance := Label.new()
var _balance_2 := Label.new()
var _status := Label.new()
var _status_packs := Label.new()


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
	title.text = "Shop"
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
	tabs.add_child(_packs_tab())
	tabs.add_child(_currency_tab())
	Cosmetics.changed.connect(_show)
	Cosmetics.message.connect(func(text: String) -> void:
		_status.text = text
		_status_packs.text = text)
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _packs_tab() -> Control:
	var box := _tab_box("Skin packs")
	var top := HBoxContainer.new()
	_balance.theme_type_variation = &"DimLabel"
	_balance.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(_balance)
	var prices := Label.new()
	prices.theme_type_variation = &"DimLabel"
	prices.add_theme_font_size_override(&"font_size", 12)
	prices.text = "Any skin %s · all ship skins of a pack %s · all outfits %s · a whole pack %s" % [
		Cosmetics.amount_money(Cosmetics.price("skin")), Cosmetics.amount_money(Cosmetics.price("all_ships")),
		Cosmetics.amount_money(Cosmetics.price("all_humans")), Cosmetics.amount_money(Cosmetics.price("pack"))]
	top.add_child(prices)
	box.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(scroll)
	_packs_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_packs_box.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_packs_box)
	_status_packs.theme_type_variation = &"DimLabel"
	_status_packs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_packs.custom_minimum_size = Vector2(0, 24)
	box.add_child(_status_packs)
	return box


func _currency_tab() -> Control:
	var box := _tab_box("Sand Dollars")
	_balance_2.theme_type_variation = &"HeaderLabel"
	box.add_child(_balance_2)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Sand Dollars buy skins. One Sand Dollar is one cent: bundles are bought with Steam money through Steam's checkout, and your Sand Dollars and skins stay with you in every game on this computer."
	box.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 8)
	for bundle: Dictionary in Cosmetics.bundles():
		var button := Button.new()
		button.text = "%s  %s" % [Cosmetics.amount(int(bundle.sand_dollars)), Cosmetics.bundle_price(bundle)]
		button.custom_minimum_size = Vector2(300, 40)
		button.tooltip_text = "Buy %s for %s through Steam." % [Cosmetics.amount(int(bundle.sand_dollars)), Cosmetics.bundle_price(bundle)]
		button.pressed.connect(func() -> void: Cosmetics.buy_bundle(bundle))
		grid.add_child(button)
	box.add_child(grid)
	_status.theme_type_variation = &"DimLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 44)
	if Net.steam == null:
		_status.text = "Steam isn't running, so Sand Dollars can't be bought right now. Start Steam and log in, then start the game again."
	box.add_child(_status)
	return box


func _show() -> void:
	_balance.text = "You have %s." % Cosmetics.amount(Cosmetics.sand_dollars)
	_balance_2.text = "You have %s" % Cosmetics.amount(Cosmetics.sand_dollars)
	for child in _packs_box.get_children():
		child.queue_free()
	var packs := Cosmetics.packs_for_sale()
	if packs.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"DimLabel"
		none.text = "No packs are on sale right now."
		_packs_box.add_child(none)
	for pack: Dictionary in packs:
		_packs_box.add_child(_pack_card(pack))


## A pack's card: its title and blurb, Wear / Take off, the whole-pack button,
## then its ship skins and its outfits, each with its own button and an
## all-of-them button.
func _pack_card(pack: Dictionary) -> Control:
	var id := str(pack.id)
	var card := PanelContainer.new()
	card.theme_type_variation = &"MapPopup"
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 8)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = str(pack.title)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	var count := Label.new()
	count.theme_type_variation = &"GainLabel" if Cosmetics.owns(id) else &"DimLabel"
	count.text = "All owned" if Cosmetics.owns(id) else "%d of %d owned" % [Cosmetics.owned_count(id), Cosmetics.skin_ids(id).size()]
	count.size_flags_vertical = SIZE_SHRINK_CENTER
	top.add_child(count)
	if Cosmetics.wearable(id):
		var wearing := Cosmetics.equipped == id
		var wear := Button.new()
		wear.text = "Take off" if wearing else "Wear on my ships"
		wear.tooltip_text = "Your ships wear this pack's skins you own (one pack at a time). Outfits are in Found Company; their hats and colours on the Uniforms page."
		wear.pressed.connect(func() -> void: Cosmetics.equip("" if wearing else id))
		top.add_child(wear)
	if not Cosmetics.owns(id):
		top.add_child(_bundle_button(id, "all", "Whole pack"))
	box.add_child(top)
	var blurb := Label.new()
	blurb.theme_type_variation = &"DimLabel"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override(&"font_size", 13)
	blurb.text = str(pack.get("blurb", ""))
	box.add_child(blurb)
	var ships := Cosmetics.ship_skins(id)
	box.add_child(_group(id, "Ship skins", "ships", ships.map(func(skin: Dictionary) -> Array: return [str(skin.id), str(skin.name), _models_text(skin.models)])))
	var outfits := Cosmetics.outfits(id)
	box.add_child(_group(id, "Outfits (CEO, captains and crew)", "humans", outfits.map(func(outfit: Dictionary) -> Array: return [str(outfit.id), str(outfit.name), _outfit_text(outfit)])))
	return card


## A group of a pack's skins: its heading with the all-of-them button, then a
## button per skin (Buy, or ticked when owned).
func _group(pack_id: String, heading_text: String, which: String, skins: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var heading := Label.new()
	heading.text = heading_text
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(heading)
	if not Cosmetics.missing(pack_id, which).is_empty():
		row.add_child(_bundle_button(pack_id, which, "All of these"))
	box.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 6)
	grid.add_theme_constant_override(&"v_separation", 4)
	for skin: Array in skins:
		var skin_id: String = skin[0]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 30)
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.add_theme_font_size_override(&"font_size", 13)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.clip_text = true
		button.tooltip_text = str(skin[2])
		if Cosmetics.owns_skin(pack_id, skin_id):
			button.text = "✓ %s" % skin[1]
			button.disabled = true
		else:
			button.text = "%s · %d" % [skin[1], Cosmetics.price("skin")]
			button.pressed.connect(func() -> void:
				var problem := Cosmetics.buy_skin(pack_id, skin_id)
				if not problem.is_empty():
					_status_packs.text = problem)
		grid.add_child(button)
	box.add_child(grid)
	return box


func _bundle_button(pack_id: String, which: String, text: String) -> Button:
	var button := Button.new()
	var cost := Cosmetics.bundle_cost(pack_id, which)
	button.text = "%s · %s" % [text, Cosmetics.amount_money(cost)]
	button.add_theme_font_size_override(&"font_size", 13)
	button.disabled = Cosmetics.sand_dollars < cost
	button.tooltip_text = "Buys every %s you don't own yet." % {all = "skin of the pack", ships = "ship skin of the pack", humans = "outfit of the pack"}[which] \
		if not button.disabled else "You need %s more: see the Sand Dollars tab." % Cosmetics.amount(cost - Cosmetics.sand_dollars)
	button.pressed.connect(func() -> void:
		var problem := Cosmetics.buy_bundle_of(pack_id, which)
		if not problem.is_empty():
			_status_packs.text = problem)
	return button


static func _models_text(models: Array) -> String:
	var names := []
	for model_id: String in models:
		names.append(str(GameData.get_ship_model(model_id).get("name", model_id)))
	return "Worn by: " + ", ".join(names)


static func _outfit_text(outfit: Dictionary) -> String:
	var parts := []
	for key: String in Cosmetics.OUTFIT_PARTS:
		parts.append_array(outfit.get(key, []))
	var text := "Unlocks: " + ", ".join(parts)
	var crew: Array = outfit.get("crew_hats", [])
	if not crew.is_empty():
		text += ". Crew hat: " + ", ".join(crew)
	var colors := []
	for pair: Array in outfit.get("shirts", []) + outfit.get("trousers", []):
		colors.append(str(pair[0]))
	if not colors.is_empty():
		text += ". Uniform colours: " + ", ".join(colors)
	return text


func _tab_box(tab_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = tab_name
	box.add_theme_constant_override(&"separation", 10)
	return box

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SkinShop
extends Control
## The Shop (from the Esc menu), in two tabs. Skin packs: the packs on sale
## now (Cosmetics.packs_for_sale()), each with what's in it and its price in
## Sand Dollars, bought with them; an owned pack's ship skins can be worn
## (equipped: one pack at a time) and its outfits, hats and colours are in
## Found Company and on the Uniforms page. Sand Dollars: the balance and the
## bundles bought with Steam money (Cosmetics.buy_bundle()). Over whatever
## opened it, dimming it; Esc, X or a click outside closes it.

const PANEL_SIZE := Vector2(640, 0)

var _packs_box := VBoxContainer.new()
var _balance := Label.new()
var _balance_2 := Label.new()
var _status := Label.new()


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
	Cosmetics.message.connect(func(text: String) -> void: _status.text = text)
	_show()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _packs_tab() -> Control:
	var box := _tab_box("Skin packs")
	_balance.theme_type_variation = &"DimLabel"
	box.add_child(_balance)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	box.add_child(scroll)
	_packs_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_packs_box.add_theme_constant_override(&"separation", 10)
	scroll.add_child(_packs_box)
	return box


func _currency_tab() -> Control:
	var box := _tab_box("Sand Dollars")
	_balance_2.theme_type_variation = &"HeaderLabel"
	box.add_child(_balance_2)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Sand Dollars buy skin packs. One Sand Dollar is one cent: bundles are bought with Steam money through Steam's checkout, and your Sand Dollars, packs and skins stay with you in every game on this computer."
	box.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 10)
	grid.add_theme_constant_override(&"v_separation", 8)
	for bundle: Dictionary in Cosmetics.bundles():
		var button := Button.new()
		button.text = "%s  %s" % [Cosmetics.amount(int(bundle.sand_dollars)), Cosmetics.bundle_price(bundle)]
		button.custom_minimum_size = Vector2(280, 40)
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


## A pack's card: its title, what's in it, and Buy, or Wear / Take off when owned.
func _pack_card(pack: Dictionary) -> Control:
	var id := str(pack.id)
	var card := PanelContainer.new()
	card.theme_type_variation = &"MapPopup"
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var top := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = str(pack.title)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	var price := Label.new()
	price.text = "Owned" if Cosmetics.owns(id) else Cosmetics.amount(int(pack.get("price", 0)))
	price.theme_type_variation = &"GainLabel" if Cosmetics.owns(id) else &"DimLabel"
	top.add_child(price)
	box.add_child(top)
	var blurb := Label.new()
	blurb.theme_type_variation = &"DimLabel"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.text = str(pack.get("blurb", ""))
	box.add_child(blurb)
	var contents := Label.new()
	contents.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	contents.add_theme_font_size_override(&"font_size", 12)
	contents.text = "%d ship skins, %d outfits, %d hats and %d uniform colours." % [(pack.get("ships", {}) as Dictionary).size(), (pack.get("top", []) as Array).size(),
		(pack.get("headwear", []) as Array).size(), (pack.get("shirts", []) as Array).size() + (pack.get("trousers", []) as Array).size()]
	box.add_child(contents)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	if Cosmetics.owns(id):
		var wearing := Cosmetics.equipped == id
		var wear := Button.new()
		wear.text = "Take off" if wearing else "Wear on my ships"
		wear.tooltip_text = "Your ships wear this pack's skins (one pack at a time). Its outfits are in Found Company; its hats and colours on the Uniforms page."
		wear.pressed.connect(func() -> void: Cosmetics.equip("" if wearing else id))
		row.add_child(wear)
		var hint := Label.new()
		hint.theme_type_variation = &"DimLabel"
		hint.add_theme_font_size_override(&"font_size", 12)
		hint.text = "Your ships are wearing it." if wearing else ""
		hint.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(hint)
	else:
		var buy := Button.new()
		var cost := int(pack.get("price", 0))
		buy.text = "Buy for %s" % Cosmetics.amount(cost)
		buy.disabled = Cosmetics.sand_dollars < cost
		buy.tooltip_text = "" if not buy.disabled else "You need %s more: see the Sand Dollars tab." % Cosmetics.amount(cost - Cosmetics.sand_dollars)
		buy.pressed.connect(func() -> void:
			var problem := Cosmetics.buy_pack(id)
			if not problem.is_empty():
				_status.text = problem)
		row.add_child(buy)
	box.add_child(row)
	return card


func _tab_box(tab_name: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = tab_name
	box.add_theme_constant_override(&"separation", 10)
	return box

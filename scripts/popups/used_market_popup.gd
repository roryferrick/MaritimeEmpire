# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name UsedMarketPopup
extends PanelContainer
## The second-hand market (Shipyards.listings): ships the paper firms are
## selling, with their age, condition and price, lying where they are. Buying
## one names it (NamePopup with a listing).

const WIDTH := 760.0

var _rows := VBoxContainer.new()


func _init() -> void:
	theme_type_variation = &"PopupPanel"


func _ready() -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = WIDTH
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Second-hand ships"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Ready ships the shipping firms are selling, at 40-80% of list by condition and age. Each is delivered where it lies, parts as they are: the major ones only come right in drydock. A third of the list changes each month."
	box.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 360.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 6)
	scroll.add_child(_rows)
	GameState.shipyards.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not is_inside_tree():
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var yards: Shipyards = GameState.shipyards
	var listings: Array = yards.listings.duplicate()
	listings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.price) < int(b.price))
	if listings.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"DimLabel"
		empty.text = "Nothing for sale this month."
		_rows.add_child(empty)
		return
	var firms: ShippingFirms = GameState.firms
	for each: Dictionary in listings:
		var model := GameData.get_ship_model(str(each.model))
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override(&"separation", 0)
		var name := Label.new()
		name.text = "%s — %s (%s)" % [str(each.name), str(model.get("name", "")), str(Progression.company_type(Progression.type_of_model(model)).get("name", "")) if not Progression.type_of_model(model).is_empty() else "Service"]
		text.add_child(name)
		var detail := Label.new()
		detail.theme_type_variation = &"DimLabel"
		detail.add_theme_font_size_override(&"font_size", 13)
		var firm: Dictionary = firms.firms[int(each.firm)]
		detail.text = "%d years old · %d%% sound · lying at %s · sold by %s · list %s" % [roundi(float(each.age)), roundi(float(each.maintenance) * 100.0), GameData.port_name(str(each.port)), str(firm.name), Fmt.money(int(model.get("price", 0)))]
		text.add_child(detail)
		row.add_child(text)
		var buy := Button.new()
		buy.text = "Buy for %s" % Fmt.money(int(each.price))
		var error := yards.used_error(GameState.company, int(each.id))
		buy.disabled = not error.is_empty()
		buy.tooltip_text = error
		var id := int(each.id)
		buy.pressed.connect(func() -> void:
			var popup: NamePopup = load("res://scenes/popups/name_popup.tscn").instantiate()
			popup.model_id = str(each.model)
			popup.listing_id = id
			PopupHost.find(self).open(popup))
		row.add_child(buy)
		_rows.add_child(row)

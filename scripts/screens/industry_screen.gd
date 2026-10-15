# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name IndustryScreen
extends Control
## The Industry page (over the map, for Cargo & Ore companies): every building
## the type can put up down the left (Mines & camps, Plants, Factories, or the
## ones the company has), and the one picked on the right: what it makes, from
## what, how much a month, what it costs; where its good sells cheapest and is
## most expensive; for a mine or camp its resource ports' claims (who holds
## them, Build, listed claims to buy); for a plant or factory Build at a port;
## and the company's own sites of it (stockpile, inputs in store, Sell, List,
## Close). See Industry.

const LIST_WIDTH := 340.0
const FONT_SIZE := 14
const CONFIRM_S := 3.0
const VIEWS := ["Mines & camps", "Plants", "Factories", "My buildings"]
const PORTS_NAMED := 4
const REFRESH_S := 5.0

var building_id := ""
var _view := 0
var _list := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _picker := OptionButton.new()
var _confirm := {}  # Site key -> when its Close was first clicked (ms).
var _dirty := true
var _clock := 0.0
var _port_picker: OptionButton = null
var _build_port := ""


func _ready() -> void:
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override(&"separation", 0)
	add_child(split)
	var left := PanelContainer.new()
	left.theme_type_variation = &"CardPanel"
	left.custom_minimum_size.x = LIST_WIDTH
	split.add_child(left)
	var left_box := VBoxContainer.new()
	left_box.add_theme_constant_override(&"separation", 8)
	left.add_child(left_box)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Industry"
	left_box.add_child(title)
	left_box.add_child(_dim("Mines dig ore on claims at their resource ports; plants turn ore into metals; factories turn materials into the container ships' goods. Your ships load what they make free, and unload what they need into them."))
	for each: String in VIEWS:
		_picker.add_item(each)
	_picker.item_selected.connect(func(index: int) -> void:
		_view = index
		_rebuild_list())
	left_box.add_child(_picker)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_box.add_child(scroll)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 2)
	scroll.add_child(_list)
	var right := ScrollContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	right.add_child(margin)
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.add_theme_constant_override(&"separation", 12)
	margin.add_child(_detail)
	GameState.industry_changed.connect(func() -> void: _dirty = true)
	visibility_changed.connect(func() -> void: _dirty = true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_S:
		_clock = 0.0
		_dirty = true
	var typing := get_viewport().gui_get_focus_owner() is LineEdit and _detail.is_ancestor_of(get_viewport().gui_get_focus_owner())
	if _dirty and not typing and not (_port_picker != null and is_instance_valid(_port_picker) and _port_picker.get_popup().visible):
		_dirty = false
		_rebuild_list()
		_rebuild_detail()


## Shows a building (from the port popup's Industry button).
func show_building(id: String) -> void:
	building_id = id
	_build_port = ""
	_view = 3 if not GameState.industry.owned_by(GameState.company, id).is_empty() else (0 if Industry.on_claims(id) else (1 if Industry.building(id).get("kind", "") == "plant" else 2))
	_picker.select(_view)
	_dirty = true


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var me := GameState.company
	var industry := GameState.industry
	for each: Dictionary in Industry.buildings():
		var id := str(each.id)
		var mine := industry.owned_by(me, id).size()
		var kind := str(each.kind)
		if _view == 0 and not kind in ["mine", "camp"] or _view == 1 and kind != "plant" or _view == 2 and kind != "factory" or _view == 3 and mine == 0:
			continue
		if building_id.is_empty():
			building_id = id
		var button := Button.new()
		button.theme_type_variation = &"TileButton"
		button.toggle_mode = true
		button.button_pressed = id == building_id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.x = 1.0
		button.add_theme_font_size_override(&"font_size", FONT_SIZE)
		var notes := PackedStringArray([str(GameData.commodity(str(each.makes)).get("name", "")), Fmt.money_short(Industry.cost(id))])
		if mine > 0:
			notes.append("%d yours" % mine)
		button.text = "%s\n%s" % [each.name, " · ".join(notes)]
		button.pressed.connect(func() -> void:
			building_id = id
			_build_port = ""
			_dirty = true)
		_list.add_child(button)


func _rebuild_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_port_picker = null
	var each := Industry.building(building_id)
	if each.is_empty():
		return
	var me := GameState.company
	var makes := str(each.makes)
	var good := GameData.commodity(makes)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = str(each.name)
	_detail.add_child(name_label)
	var inputs: Dictionary = each.get("inputs", {})
	var from := ""
	if not inputs.is_empty():
		from = " from %s a %s" % [FarmsScreen._and(inputs.keys().map(func(input: String) -> String:
			return "%s %s of %s" % [String.num(float(inputs[input]), 2),
				GameData.commodity(input).get("units", "units"), str(GameData.commodity(input).get("name", input)).to_lower()])), good.get("unit", "unit")]
	_detail.add_child(_text("Makes about %s %s of %s a month%s. Costs %s to build and %s a month to run; its stockpile holds %d months' output." % [
		Fmt.thousands(roundi(Industry.output_a_month(building_id))), good.get("units", "units"), str(good.get("name", makes)).to_lower(), from,
		Fmt.money(Industry.cost(building_id)), Fmt.money(Industry.upkeep_a_month(building_id)), int(Industry.setting("stock_months", 3))]))
	if not inputs.is_empty():
		_detail.add_child(_dim("Your ships unload its inputs into its store as they call (up to %d months' worth); when the store runs short it buys them at the port's price, so one your ships keep supplied (from your own mines best) earns more." % int(Industry.setting("stock_months", 3))))
	if not Industry.can_build(me):
		_detail.add_child(_error("Only Cargo & Ore companies build industry: choose Cargo & Ore as one of your company types."))
	_detail.add_child(_prices_card(makes, inputs))
	_detail.add_child(_claims_card(each) if Industry.on_claims(building_id) else _build_card(each))
	var mine := GameState.industry.owned_by(me, building_id)
	if not mine.is_empty():
		var box := _card("Yours")
		for key in mine:
			box.add_child(_site_row(key))
		_detail.add_child(box.get_parent())


## Where its good sells cheapest and is most expensive, and where its inputs are cheapest.
func _prices_card(makes: String, inputs: Dictionary) -> Control:
	var box := _card("Prices")
	box.add_child(_text("%s: cheapest %s; most expensive %s." % [GameData.commodity(makes).get("name", makes), _ports_text(makes, true), _ports_text(makes, false)]))
	for input: String in inputs:
		box.add_child(_dim("%s cheapest at %s." % [GameData.commodity(input).get("name", input), _ports_text(input, true)]))
	return box.get_parent()


func _ports_text(good_id: String, cheapest: bool) -> String:
	var ranked := GameData.ports.map(func(port: Dictionary) -> Array: return [GameState.market.sell_price(port.id, good_id), port.id])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]) if cheapest else float(a[0]) > float(b[0]))
	return ", ".join(PackedStringArray(ranked.slice(0, PORTS_NAMED).map(func(row: Array) -> String: return "%s %s" % [GameData.port_name(row[1]), Fmt.money(roundi(row[0]))])))


## A mine's or camp's resource ports: each with its claims (who holds them),
## a Build button while one's free, and any listed for sale.
func _claims_card(each: Dictionary) -> Control:
	var industry := GameState.industry
	var me := GameState.company
	var box := _card("Claims")
	box.add_child(_dim("Claims are shared by every company, first come first served; you may hold %d at a port." % int(Industry.setting("most_claims", 2))))
	var ports: Dictionary = each.get("ports", {})
	for port_id: String in ports:
		var holders := PackedStringArray()
		var listed := ""
		for n in int(ports[port_id]):
			var key := Industry.key_of(port_id, building_id, n)
			var owner := industry.owner_of(key)
			if owner != null:
				holders.append("you" if owner == me else owner.name)
				if owner != me and int(industry.site(key).get("listing", 0)) > 0:
					listed = key
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var where := _text("%s (%s): %d of %d claims taken%s" % [GameData.port_name(port_id), GameData.port_region(port_id).get("name", ""), holders.size(), int(ports[port_id]),
			(", by " + ", ".join(holders)) if not holders.is_empty() else ""])
		where.size_flags_horizontal = SIZE_EXPAND_FILL
		where.custom_minimum_size.x = 1.0
		row.add_child(where)
		var actions := HBoxContainer.new()
		actions.add_theme_constant_override(&"separation", 6)
		actions.add_child(_action("Build %s" % Fmt.money_short(Industry.cost(building_id)), industry.build_error(me, building_id, port_id), func() -> void: GameState.build_site(building_id, port_id)))
		if not listed.is_empty():
			actions.add_child(_action("Buy %s's for %s" % [industry.owner_of(listed).name, Fmt.money_short(int(industry.site(listed).listing))], industry.listing_error(me, listed), func() -> void: GameState.buy_listed_site(listed)))
		row.add_child(actions)
		box.add_child(row)
	return box.get_parent()


## A plant or factory: Build at a port (the HQ and hubs first, then every port
## it may go at by name), and other companies' of it.
func _build_card(each: Dictionary) -> Control:
	var industry := GameState.industry
	var me := GameState.company
	var box := _card("Build")
	var others := PackedStringArray()
	for key: String in industry.sites:
		if Industry.building_of(key) == building_id and industry.owner_of(key) != me and industry.owner_of(key) != null:
			others.append("%s at %s%s" % [industry.owner_of(key).name, GameData.port_name(Industry.port_of(key)),
				" (for sale, %s)" % Fmt.money_short(int(industry.site(key).listing)) if int(industry.site(key).get("listing", 0)) > 0 else ""])
	if not others.is_empty():
		box.add_child(_dim("Others': %s." % ", ".join(others)))
	if not Industry.can_build(me):
		return box.get_parent()
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	_port_picker = OptionButton.new()
	_port_picker.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_port_picker.fit_to_longest_item = false
	_port_picker.custom_minimum_size.x = 300
	var choices: Array[String] = []
	for hub: Hub in me.hubs:
		choices.append(hub.port_id)
	choices.append_array(GameData.ports_by_name().map(func(port: Dictionary) -> String: return str(port.id)).filter(func(id: String) -> bool: return not choices.has(id)))
	var usable := choices.filter(func(id: String) -> bool: return industry.build_error(me, building_id, id) in ["", "Not enough money"])
	for id: String in usable:
		var hub := me.hub_at(id)
		_port_picker.add_item("%s%s" % [GameData.port_name(id), " (%s)" % ("HQ" if hub.is_hq else "hub") if hub else ""])
		_port_picker.set_item_metadata(_port_picker.item_count - 1, id)
		if id == _build_port:
			_port_picker.select(_port_picker.item_count - 1)
	if _build_port.is_empty() and not usable.is_empty():
		_build_port = usable[0]
	_port_picker.item_selected.connect(func(index: int) -> void:
		_build_port = str(_port_picker.get_item_metadata(index))
		_dirty = true)
	var error := industry.build_error(me, building_id, _build_port) if not _build_port.is_empty() else "No port left to build at"
	if not usable.is_empty():
		row.add_child(_port_picker)
	row.add_child(_action("Build %s" % Fmt.money_short(Industry.cost(building_id)), error, func() -> void: GameState.build_site(building_id, _build_port)))
	box.add_child(row)
	return box.get_parent()


## One of the company's sites: where, its stockpile and inputs, Sell, List and Close.
func _site_row(key: String) -> Control:
	var industry := GameState.industry
	var entry := industry.site(key)
	var makes := str(Industry.building(building_id).makes)
	var units := str(GameData.commodity(makes).get("units", "units"))
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	var title := _text("At %s" % GameData.port_name(Industry.port_of(key)))
	title.add_theme_color_override(&"font_color", GameState.company_color_value(GameState.company.color).lightened(0.2))
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var stock := floori(float(entry.get("stock", 0.0)))
	head.add_child(_action("Sell %s" % Fmt.money_short(industry.stock_value(key)), "" if stock > 0 else "Nothing made yet", func() -> void: GameState.sell_site_stock(key)))
	if int(entry.get("listing", 0)) > 0:
		var off := Button.new()
		off.text = "Take off the list"
		off.pressed.connect(func() -> void: GameState.list_site(key, 0))
		head.add_child(off)
	else:
		var list := Button.new()
		list.text = "List for %s" % Fmt.money_short(int(entry.get("paid", 0)))
		list.tooltip_text = "Other Cargo & Ore companies can buy it, with its stock, for what you paid."
		list.pressed.connect(func() -> void: GameState.list_site(key, int(entry.get("paid", 0))))
		head.add_child(list)
	var close := Button.new()
	var confirming := Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0
	var refund := roundi(float(entry.get("paid", 0)) * float(Industry.setting("close_share", 0.25)))
	close.text = "Sure? %s back" % Fmt.money_short(refund) if confirming else "Close"
	close.tooltip_text = "Close it for %s (a quarter of what you paid); its stock and store go with it." % Fmt.money(refund)
	close.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0:
			_confirm.erase(key)
			GameState.close_site(key)
		else:
			_confirm[key] = Time.get_ticks_msec()
			_dirty = true)
	head.add_child(close)
	row.add_child(head)
	var parts := PackedStringArray(["%s of %s %s waiting" % [Fmt.thousands(stock), Fmt.thousands(floori(Industry.stock_cap(building_id))), units],
		"%s made so far" % Fmt.thousands(floori(float(entry.get("made", 0.0))))])
	var store: Dictionary = entry.get("inputs", {})
	for input: String in Industry.building(building_id).get("inputs", {}):
		parts.append("%s %s in store" % [Fmt.thousands(floori(float(store.get(input, 0.0)))), str(GameData.commodity(input).get("name", input)).to_lower()])
	row.add_child(_dim(" · ".join(parts)))
	return row


func _card(title_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override(&"font_size", 17)
	box.add_child(title)
	return box


func _action(text: String, error: String, then: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.disabled = not error.is_empty()
	button.tooltip_text = error
	button.pressed.connect(then)
	return button


func _text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	return label


func _dim(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"DimLabel"
	return label


func _error(text: String) -> Label:
	var label := _text(text)
	label.theme_type_variation = &"ErrorLabel"
	return label

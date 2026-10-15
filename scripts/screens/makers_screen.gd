# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name MakersScreen
extends Control
## The Makers screen (the Makers page over the map, for Vehicles companies):
## the vehicle and boat makers down the left (all, the car makers, the boat
## builders, or those the company has factories for), and the one picked on
## the right: what it makes and where, the company's likeness with it and the
## perks it brings, its rivals, other companies' standing with it, where its
## goods sell cheapest and most expensive, and the company's factories for it (their
## stockpile, upkeep and the maker's cut, Sell and Close) with Build a factory.
## See Manufacturers.

const LIST_WIDTH := 340.0
const FONT_SIZE := 14
## Closing a factory takes a second click within this many seconds.
const CONFIRM_S := 3.0
## The picker's views.
const VIEWS := ["All makers", "Car makers", "Boat builders", "My factories"]
## How many ports the goods card names as cheapest and most expensive.
const PORTS_NAMED := 4
const REFRESH_S := 5.0

var maker_id := ""
var _view := 0
var _list := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _picker := OptionButton.new()
var _confirm := {}  # Factory port -> when its Close was first clicked (ms).
var _dirty := true
var _clock := 0.0
## The build port picker (not rebuilt while it's open) and the port picked in it.
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
	title.text = "Makers"
	left_box.add_child(title)
	left_box.add_child(_dim("Carmakers and boatbuilders are wary of a new carrier: each starts liking you %d/100. Ship their goods and they warm to you; at %d they'll let you build a factory for them." % [
		int(Manufacturers.setting("start", 20)), int(Manufacturers.setting("factory_at", 70))]))
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
	GameState.makers_changed.connect(func() -> void: _dirty = true)
	visibility_changed.connect(func() -> void: _dirty = true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_S:
		_clock = 0.0
		_dirty = true
	if _dirty and not (_port_picker != null and is_instance_valid(_port_picker) and _port_picker.get_popup().visible):
		_dirty = false
		_rebuild_list()
		_rebuild_detail()


## Shows a maker (from the port popup's Makers button).
func show_maker(id: String) -> void:
	maker_id = id
	_build_port = ""
	_dirty = true


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var me := GameState.company
	for line: Array in [["cars", "Car makers"], ["boats", "Boat builders"]]:
		if _view == 1 and line[0] != "cars" or _view == 2 and line[0] != "boats":
			continue
		var makers := Manufacturers.makers_of(line[0]).filter(func(each: Dictionary) -> bool: return _view != 3 or not Manufacturers.factories_of(me, each.id).is_empty())
		if makers.is_empty():
			continue
		# The best liked first.
		makers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Manufacturers.likeness(me, a.id) > Manufacturers.likeness(me, b.id) if Manufacturers.likeness(me, a.id) != Manufacturers.likeness(me, b.id) else str(a.name) < str(b.name))
		var heading := _dim(line[1])
		_list.add_child(heading)
		for each: Dictionary in makers:
			if maker_id.is_empty():
				maker_id = each.id
			_list.add_child(_maker_button(each))


func _maker_button(each: Dictionary) -> Button:
	var me := GameState.company
	var button := Button.new()
	button.theme_type_variation = &"TileButton"
	button.toggle_mode = true
	button.button_pressed = each.id == maker_id
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # (Kept to the list's width.)
	button.custom_minimum_size.x = 1.0
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	var notes := PackedStringArray(["%s %s" % [Manufacturers.class_name_of(str(each["class"])), each.kind], str(each.home), "%d/100" % floori(Manufacturers.likeness(me, each.id))])
	var mine := Manufacturers.factories_of(me, each.id).size()
	if mine > 0:
		notes.append("%d factor%s" % [mine, "y" if mine == 1 else "ies"])
	elif Manufacturers.factories_allowed(me, each.id) > 0:
		notes.append("can build")
	button.text = "%s\n%s" % [each.name, " · ".join(notes)]
	button.icon = _swatch(Color.from_string(str(each.get("color", "#ffffff")), Color.WHITE))
	button.pressed.connect(func() -> void:
		maker_id = each.id
		_build_port = ""
		_dirty = true)
	return button


func _rebuild_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_port_picker = null
	var each := Manufacturers.maker(maker_id)
	if each.is_empty():
		return
	var me := GameState.company
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var swatch := TextureRect.new()
	swatch.texture = _swatch(Color.from_string(str(each.get("color", "#ffffff")), Color.WHITE), 22)
	swatch.size_flags_vertical = SIZE_SHRINK_CENTER
	header.add_child(swatch)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = each.name
	header.add_child(name_label)
	var ports: Array = each.get("factories", [])
	var map := Button.new()
	map.text = "Show on map"
	map.size_flags_vertical = SIZE_SHRINK_CENTER
	map.pressed.connect(func() -> void: GameRoot.find(self).show_port_on_map(str(ports[0])))
	header.add_child(map)
	_detail.add_child(header)
	var size_words := {small = "a small maker", mid = "a mid-sized maker", large = "a big maker"}
	_detail.add_child(_text("%s · %s · %s, building at %s" % [Manufacturers.describe(maker_id), each.home, size_words.get(each.get("size", ""), "a maker"),
		FarmsScreen._and(ports.map(func(id: String) -> String: return GameData.port_name(id)))]))
	_detail.add_child(_dim(str(each.get("blurb", ""))))
	if not Manufacturers.can_deal(me):
		_detail.add_child(_error("Only Vehicles companies deal with the makers: choose Vehicles as one of your company types to win their trust and build factories."))
	_detail.add_child(_likeness_card(each))
	_detail.add_child(_goods_card(each))
	_detail.add_child(_factories_card(each))


## The company's likeness with the maker, the perks on the way, how it moves,
## its rivals, and the other companies' standing with it.
func _likeness_card(each: Dictionary) -> Control:
	var me := GameState.company
	var box := _card("How much %s likes you" % each.name)
	var like := Manufacturers.likeness(me, maker_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = like
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, 14)
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(bar)
	var figure := _text("%d / 100" % floori(like))
	figure.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(figure)
	box.add_child(row)
	for mark: Array in Manufacturers.perk_marks():
		var reached := like >= float(mark[0])
		var label := _text("%s %d: %s" % ["✓" if reached else "·", int(mark[0]), mark[1]])
		label.theme_type_variation = &"GainLabel" if reached else &"DimLabel"
		box.add_child(label)
	box.add_child(_dim("Buying their %s raises it a little, selling them more (bigger loads more, though less the more they like you already). Carrying a rival's goods lowers it a little, and they don't forgive a ship breaking down (-%d) or lost (-%d) with their goods aboard." % [
		GameData.commodity(maker_id).get("units", "vehicles"), int(Manufacturers.setting("breakdown_penalty", 2)), int(Manufacturers.setting("lost_penalty", 5))]))
	var rivals := Manufacturers.rivals_of(maker_id)
	if not rivals.is_empty():
		box.add_child(_dim("Rivals (carrying their goods costs you a little here): %s." % FarmsScreen._and(rivals.map(func(id: String) -> String:
			return "%s (%d)" % [Manufacturers.maker(id).name, floori(Manufacturers.likeness(me, id))]))))
	var others := PackedStringArray()
	for who: Company in GameState.all_companies():
		if who != me and Manufacturers.can_deal(who):
			others.append("%s %d" % [who.name, floori(Manufacturers.likeness(who, maker_id))])
	if not others.is_empty():
		box.add_child(_dim("Other companies' standing: %s." % ", ".join(others)))
	return box.get_parent()


## What one of the maker's vehicles is, which ships carry it, and where it sells cheapest and most expensive.
func _goods_card(each: Dictionary) -> Control:
	var box := _card("Their %s" % GameData.commodity(maker_id).get("units", "vehicles"))
	var hold := GameData.hold_of(maker_id)
	var carriers := GameData.ship_models.filter(func(model: Dictionary) -> bool: return (model.get("cargo", []) as Array).has(maker_id) and float(model.get("capacity", 0)) >= hold)
	carriers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.capacity) < int(b.capacity))
	var fits := ""
	if not carriers.is_empty():
		fits = "; a %s carries %s, a %s %s" % [carriers[0].name, Fmt.thousands(floori(float(carriers[0].capacity) / hold)), carriers[-1].name, Fmt.thousands(floori(float(carriers[-1].capacity) / hold))]
	box.add_child(_text("Each takes %s deck slot%s and is worth about %s on average%s." % [Fmt.decimal(hold, 1) if hold != floorf(hold) else str(int(hold)), "" if hold == 1.0 else "s",
		Fmt.money(roundi(GameData.world_price(maker_id))), fits]))
	var ranked := GameData.ports.map(func(port: Dictionary) -> Array: return [GameState.market.sell_price(port.id, maker_id), port.id])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var named := func(rows: Array) -> String:
		return ", ".join(PackedStringArray(rows.map(func(row: Array) -> String: return "%s %s" % [GameData.port_name(row[1]), Fmt.money(roundi(row[0]))])))
	box.add_child(_text("Cheapest: %s" % named.call(ranked.slice(0, PORTS_NAMED))))
	var priciest := ranked.slice(-PORTS_NAMED)
	priciest.reverse()
	box.add_child(_text("Most expensive: %s" % named.call(priciest)))
	return box.get_parent()


## The company's factories for the maker, everyone else's, and Build a factory.
func _factories_card(each: Dictionary) -> Control:
	var me := GameState.company
	var makers := GameState.makers
	var box := _card("Factories")
	box.add_child(_dim("A factory costs %s to build and %s a month to run, and makes about %s %s a month into a stockpile (it holds %d months' worth). Sell them there, or your ships load them free and you sell them anywhere: %s takes %d%% of what they sell for at %d/100, falling to %d%% at 100." % [
		Fmt.money(Manufacturers.factory_cost(maker_id)), Fmt.money(Manufacturers.upkeep_a_month(maker_id)), Fmt.thousands(roundi(Manufacturers.output_a_day(maker_id) * 365.25 / 12.0)),
		GameData.commodity(maker_id).get("units", "vehicles"), int(Manufacturers.setting("stock_months", 3)), each.name,
		roundi(float(Manufacturers.setting("cut_high", 0.3)) * 100.0), int(Manufacturers.setting("factory_at", 70)), roundi(float(Manufacturers.setting("cut_low", 0.1)) * 100.0)]))
	for factory: Dictionary in Manufacturers.factories_of(me, maker_id):
		box.add_child(_factory_row(factory))
	for who: Company in GameState.all_companies():
		if who == me:
			continue
		for factory: Dictionary in Manufacturers.factories_of(who, maker_id):
			var label := _text("%s's factory at %s" % [who.name, GameData.port_name(str(factory.port))])
			label.add_theme_color_override(&"font_color", GameState.company_color_value(who.color).lightened(0.2))
			box.add_child(label)
	if not Manufacturers.can_deal(me):
		return box.get_parent()
	# Build a factory: the company's HQ and hubs first, then every other port it can, by name.
	var build := HBoxContainer.new()
	build.add_theme_constant_override(&"separation", 8)
	_port_picker = OptionButton.new()
	_port_picker.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_port_picker.fit_to_longest_item = false
	_port_picker.custom_minimum_size.x = 300
	var choices: Array[String] = []
	for hub: Hub in me.hubs:
		choices.append(hub.port_id)
	var rest := GameData.ports_by_name().map(func(port: Dictionary) -> String: return str(port.id)).filter(func(id: String) -> bool: return not choices.has(id))
	choices.append_array(rest)
	var usable := choices.filter(func(id: String) -> bool: return makers.build_error(me, maker_id, id) in ["", "Not enough money"])
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
	var error := makers.build_error(me, maker_id, _build_port if not _build_port.is_empty() else str(each.factories[0]))
	if usable.is_empty() and error.is_empty():
		error = "No port left to build at"
	if not usable.is_empty():
		build.add_child(_port_picker)
	build.add_child(_action("Build a factory %s" % Fmt.money_short(Manufacturers.factory_cost(maker_id)), error, func() -> void: GameState.build_factory(maker_id, _build_port)))
	box.add_child(build)
	if not error.is_empty():
		box.add_child(_error(error))
	return box.get_parent()


## One of the company's factories: its port, stockpile, what it'd fetch there, and Sell and Close.
func _factory_row(factory: Dictionary) -> Control:
	var me := GameState.company
	var port_id := str(factory.port)
	var row := VBoxContainer.new()
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 8)
	var title := _text("Your factory at %s" % GameData.port_name(port_id))
	title.add_theme_color_override(&"font_color", GameState.company_color_value(me.color).lightened(0.2))
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var stock := floori(float(factory.get("stock", 0.0)))
	var value := GameState.makers.stock_value(me, factory)
	head.add_child(_action("Sell %s" % Fmt.money_short(value), "" if stock > 0 else "Nothing made yet", func() -> void: GameState.sell_factory_stock(maker_id, port_id)))
	var close := Button.new()
	var confirming := Time.get_ticks_msec() - int(_confirm.get(port_id, -100000)) < CONFIRM_S * 1000.0
	var refund := roundi(float(factory.get("paid", 0)) * float(Manufacturers.setting("close_share", 0.25)))
	close.text = "Sure? %s back" % Fmt.money_short(refund) if confirming else "Close"
	close.tooltip_text = "%s buys it back for %s (a quarter of what you paid); its stock goes with it." % [Manufacturers.maker(maker_id).name, Fmt.money(refund)]
	close.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - int(_confirm.get(port_id, -100000)) < CONFIRM_S * 1000.0:
			_confirm.erase(port_id)
			GameState.close_factory(maker_id, port_id)
		else:
			_confirm[port_id] = Time.get_ticks_msec()
			_dirty = true)
	head.add_child(close)
	row.add_child(head)
	row.add_child(_dim("%s of %s %s waiting (they'd fetch %s here after the maker's %d%% cut) · %s made so far · upkeep %s a month" % [
		Fmt.thousands(stock), Fmt.thousands(floori(Manufacturers.stock_cap(maker_id))), GameData.commodity(maker_id).get("units", "vehicles"), Fmt.money(value),
		roundi(Manufacturers.cut(me, maker_id) * 100.0), Fmt.thousands(floori(float(factory.get("made", 0.0)))), Fmt.money(Manufacturers.upkeep_a_month(maker_id))]))
	return row


## A card with a title: returns its box (the card is its parent).
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


## A small square of a maker's colour, for its button.
static func _swatch(color: Color, side := 14) -> ImageTexture:
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	image.fill(color)
	for i in side:
		for edge in [Vector2i(i, 0), Vector2i(i, side - 1), Vector2i(0, i), Vector2i(side - 1, i)]:
			image.set_pixelv(edge, Color(0, 0, 0, 0.6))
	return ImageTexture.create_from_image(image)


## A button that does `then`, disabled with `error` as its tooltip if that isn't "".
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

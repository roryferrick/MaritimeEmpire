# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name FarmsScreen
extends Control
## The Farms screen (the bottom bar's Farms tab, for Agriculture companies):
## the farm ports down the left (all of them, the company's own, or those with
## plots for sale), and the one picked on the right: its climate, what it's
## known for and the weather this year and next; a card for each plot (who
## owns it, its soil, and for the company's own what it grows or grazes, its
## upgrades, listing and sale); and the company's farm store there, with
## what's in it, how fresh, and its worth. See Farms.

const LIST_WIDTH := 330.0
const CARD_WIDTH := 400.0
const FONT_SIZE := 14
## A sale back to the land takes a second click within this many seconds.
const CONFIRM_S := 3.0
## The picker's views.
const VIEWS := ["All farm ports", "My farms", "Plots for sale"]

var port_id := ""
var _view := 0
var _list := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _picker := OptionButton.new()
var _confirm := {}  # Plot key -> when its Sell to the land was first clicked (ms).
var _dirty := true
## The plots' pickers (not rebuilt under an open one), and the refresh clock
## (money changes what can be bought: looked at again every REFRESH_S).
var _pickers: Array[OptionButton] = []
var _clock := 0.0
const REFRESH_S := 5.0


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
	title.text = "Farms"
	left_box.add_child(title)
	var intro := _dim("Buy plots at the world's farm ports, grow crops or graze herds that suit the climate, and your ships collect the harvest free from your farm store there.")
	left_box.add_child(intro)
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
	GameState.farms_changed.connect(func() -> void: _dirty = true)
	visibility_changed.connect(func() -> void: _dirty = true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_S:
		_clock = 0.0
		_dirty = true
	var typing := get_viewport().gui_get_focus_owner() is LineEdit and _detail.is_ancestor_of(get_viewport().gui_get_focus_owner())  # (A listing price being typed.)
	if _dirty and not typing and not _pickers.any(func(picker: OptionButton) -> bool: return is_instance_valid(picker) and picker.get_popup().visible):
		_dirty = false
		_rebuild_list()
		_rebuild_detail()


## Shows a farm port (from the port popup's Farms button).
func show_port(id: String) -> void:
	port_id = id
	_dirty = true


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var farms := GameState.farms
	var ports := Farms.port_ids()
	# The company's own first, then the unlocked, then the rest; by name within.
	var rank := func(id: String) -> int:
		return (0 if not farms.owned_by(GameState.company, id).is_empty() else (1 if GameState.is_port_unlocked(id) else 2))
	ports.sort_custom(func(a: String, b: String) -> bool:
		return GameData.port_name(a) < GameData.port_name(b) if rank.call(a) == rank.call(b) else rank.call(a) < rank.call(b))
	for id in ports:
		var mine := farms.owned_by(GameState.company, id).size()
		var listed := Farms.keys_at(id).filter(func(key: String) -> bool: return int(farms.plot(key).get("listing", 0)) > 0 and farms.owner_of(key) != GameState.company).size()
		if _view == 1 and mine == 0 or _view == 2 and listed == 0:
			continue
		if port_id.is_empty():
			port_id = id
		var button := Button.new()
		button.theme_type_variation = &"TileButton"  # (The panels' navy, as the ship tiles.)
		button.toggle_mode = true
		button.button_pressed = id == port_id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override(&"font_size", FONT_SIZE)
		var total := int(Farms.port_info(id).get("plots", 0))
		var free := total - farms.taken_at(id)
		var weather := farms.outlook(id)
		var notes := PackedStringArray([Farms.climate_name(Farms.climate_of(id)), "%d of %d free" % [free, total]])
		if mine > 0:
			notes.append("%d yours" % mine)
		if listed > 0:
			notes.append("%d for sale" % listed)
		if not weather[0].is_empty():
			notes.append(Farms.event_text(weather[0]).to_lower())
		button.text = "%s\n%s" % [GameData.port_name(id), " · ".join(notes)]
		if not GameState.is_port_unlocked(id):
			button.modulate = Color(1, 1, 1, 0.55)
			button.tooltip_text = "In %s, a region you haven't unlocked" % GameData.port_region(id).get("name", "")
		button.pressed.connect(func() -> void:
			port_id = id
			_dirty = true)
		_list.add_child(button)


func _rebuild_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_pickers.clear()
	if port_id.is_empty():
		return
	var farms := GameState.farms
	var info := Farms.port_info(port_id)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = GameData.port_name(port_id)
	header.add_child(name_label)
	var map := Button.new()
	map.text = "Show on map"
	map.size_flags_vertical = SIZE_SHRINK_CENTER
	map.pressed.connect(func() -> void: GameRoot.find(self).show_port_on_map(port_id))
	header.add_child(map)
	_detail.add_child(header)
	var climate := Farms.climate_of(port_id)
	_detail.add_child(_text("%s · %s climate · %s" % [GameData.port_region(port_id).get("name", ""), Farms.climate_name(climate), info.get("blurb", "")]))
	var known := (info.get("known", []) as Array).map(func(id: String) -> String: return str(GameData.commodity(id).get("name", id)).to_lower())
	if not known.is_empty():
		_detail.add_child(_dim("Known for %s, which sell cheapest here." % _and(known)))
	var weather := farms.outlook(port_id)
	_detail.add_child(_dim("Weather: this year (%d) %s; next year %s." % [farms.year_now(),
		Farms.event_text(weather[0]).to_lower() if not weather[0].is_empty() else "a fair year", Farms.event_text(weather[1]).to_lower() if not weather[1].is_empty() else "a fair year"]))
	if not Farms.can_farm(GameState.company):
		_detail.add_child(_error("Only Agriculture companies farm: choose Agriculture as one of your company types to buy plots."))
	_detail.add_child(_text("Plots: you may own %d of the %d here. Each plot grows one crop or grazes one herd; farm workers cost %s a plot every two weeks." % [
		Farms.most_at(port_id), int(info.get("plots", 0)), Fmt.money(int(Farms.setting("wages_per_plot", 23000)))]))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	for key in Farms.keys_at(port_id):
		grid.add_child(_plot_card(key))
	_detail.add_child(grid)
	_detail.add_child(_store_card())


func _plot_card(key: String) -> Control:
	var farms := GameState.farms
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size.x = CARD_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Plot %d" % (Farms.index_of(key) + 1)
	title.add_theme_font_size_override(&"font_size", 17)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var soil := _dim("Soil %d%%" % roundi(Farms.fertility(key) * 100.0))
	soil.autowrap_mode = TextServer.AUTOWRAP_OFF
	soil.tooltip_text = "Its fertility: yields go with it."
	head.add_child(soil)
	box.add_child(head)
	var owner := farms.owner_of(key)
	var entry := farms.plot(key)
	if owner == null:
		box.add_child(_text("For sale by the land: %s" % Fmt.money(farms.land_price(key))))
		box.add_child(_action("Buy", farms.buy_error(GameState.company, key), func() -> void: GameState.buy_plot(key)))
		return card
	if owner != GameState.company:
		var label := _text("Owned by %s" % owner.name)
		label.add_theme_color_override(&"font_color", GameState.company_color_value(owner.color).lightened(0.2))
		box.add_child(label)
		box.add_child(_dim(_use_text(key)))
		if int(entry.get("listing", 0)) > 0:
			box.add_child(_text("For sale: %s" % Fmt.money(int(entry.listing))))
			box.add_child(_action("Buy from %s" % owner.name, farms.listing_error(GameState.company, key), func() -> void: GameState.buy_listed_plot(key)))
		return card
	# The company's own.
	var mine := _text("Yours")
	mine.add_theme_color_override(&"font_color", GameState.company_color_value(GameState.company.color).lightened(0.2))
	box.add_child(mine)
	box.add_child(_text(_use_text(key)))
	var crop_picker := OptionButton.new()
	crop_picker.add_theme_font_size_override(&"font_size", FONT_SIZE)
	crop_picker.add_item("Plant a crop...")
	var crops := Farms.crop_ids()
	crops.sort_custom(func(a: String, b: String) -> bool: return farms.effective_fit(key, a) > farms.effective_fit(key, b) if farms.effective_fit(key, a) != farms.effective_fit(key, b) else a < b)
	for crop_id in crops:
		var commodity := GameData.commodity(crop_id)
		crop_picker.add_item("%s · %s · %s a year · %s" % [commodity.get("name", crop_id), Farms.fit_text(farms.effective_fit(key, crop_id)),
			Fmt.short(farms.yield_a_year(key, crop_id)), Fmt.money_short(farms.planting_cost(key, crop_id))])
		crop_picker.set_item_metadata(crop_picker.item_count - 1, crop_id)
		crop_picker.set_item_tooltip(crop_picker.item_count - 1, "Harvests %s here%s. %s to plant%s." % [Farms.months_text(Farms.harvest_months(port_id, crop_id)),
			", bearing fully after %d years" % int(Farms.setting("orchard_years", 2)) if Farms.crop(crop_id).get("orchard", false) else "",
			Fmt.money(farms.planting_cost(key, crop_id)), " once" if Farms.crop(crop_id).get("orchard", false) else " each year"])
	crop_picker.item_selected.connect(func(index: int) -> void:
		if index > 0:
			GameState.plant_plot(key, str(crop_picker.get_item_metadata(index))))
	box.add_child(crop_picker)
	_pickers.append(crop_picker)
	var herd_picker := OptionButton.new()
	herd_picker.add_theme_font_size_override(&"font_size", FONT_SIZE)
	herd_picker.add_item("Graze a herd...")
	var breeds: Array = Farms.data().get("breeds", []).duplicate()
	breeds.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return Farms.breed_fit(port_id, a.id) > Farms.breed_fit(port_id, b.id) if Farms.breed_fit(port_id, a.id) != Farms.breed_fit(port_id, b.id) else str(a.name) < str(b.name))
	for each: Dictionary in breeds:
		herd_picker.add_item("%s %s · %s · %s young a year · %s" % [each.name, _species_word(each.species), Farms.fit_text(Farms.breed_fit(port_id, each.id)),
			Fmt.short(farms.young_a_year(key, each.id)), Fmt.money_short(farms.stock_cost(key, each.id))])
		herd_picker.set_item_metadata(herd_picker.item_count - 1, each.id)
		herd_picker.set_item_tooltip(herd_picker.item_count - 1, "From %s. Worth x%s a head. A herd of %s, growing %d%% a year. %s to stock." % [each.origin, Fmt.decimal(float(each.value), 1),
			Fmt.thousands(roundi(farms.head_room(key, each.id))), roundi(float(each.growth) * 100.0), Fmt.money(farms.stock_cost(key, each.id))])
	herd_picker.item_selected.connect(func(index: int) -> void:
		if index > 0:
			GameState.stock_plot(key, str(herd_picker.get_item_metadata(index))))
	box.add_child(herd_picker)
	_pickers.append(herd_picker)
	# Upgrades for what it's used for.
	var used := "pasture" if not str(entry.get("breed", "")).is_empty() else "crop"
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	for each: Dictionary in Farms.data().get("upgrades", []):
		var fits: bool = str(each.for) == used or (each.for == "fresh" and used == "crop" and Farms.is_fresh(str(entry.get("crop", ""))))
		var built: bool = (entry.get("upgrades", []) as Array).has(each.id)
		if not fits and not built:
			continue
		if built:
			var done := _dim("%s built" % each.name)
			done.tooltip_text = str(each.text)
			row.add_child(done)
			continue
		var button := _action("%s %s" % [each.name, Fmt.money_short(int(each.cost))], farms.upgrade_error(GameState.company, key, each.id), func() -> void: GameState.upgrade_plot(key, each.id))
		button.tooltip_text = str(each.text) + ("" if button.tooltip_text.is_empty() else "\n" + button.tooltip_text)
		row.add_child(button)
	box.add_child(row)
	# Listing it for other companies, or selling it back to the land.
	var sale := HBoxContainer.new()
	sale.add_theme_constant_override(&"separation", 6)
	if int(entry.get("listing", 0)) > 0:
		sale.add_child(_text("Listed at %s" % Fmt.money(int(entry.listing))))
		var off := Button.new()
		off.text = "Take off the list"
		off.pressed.connect(func() -> void: GameState.list_plot(key, 0))
		sale.add_child(off)
	else:
		var price := SpinBox.new()
		price.min_value = 100000
		price.max_value = 100000000
		price.step = 10000
		price.value = maxi(int(entry.get("paid", farms.land_price(key))), 100000)
		price.prefix = "$"
		price.custom_minimum_size.x = 130
		sale.add_child(price)
		var list := Button.new()
		list.text = "List for sale"
		list.tooltip_text = "Other Agriculture companies can buy it, with its crop or herd and upgrades, at this price."
		list.pressed.connect(func() -> void: GameState.list_plot(key, int(price.value)))
		sale.add_child(list)
	var land := Button.new()
	var confirming := Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0
	land.text = "Sure? %s" % Fmt.money_short(farms.land_sale_price(key)) if confirming else "Sell to the land"
	land.tooltip_text = "For %s (half the land's price); a herd goes into your store first." % Fmt.money(farms.land_sale_price(key))
	land.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0:
			_confirm.erase(key)
			GameState.sell_plot(key)
		else:
			_confirm[key] = Time.get_ticks_msec()
			_dirty = true)
	sale.add_child(land)
	box.add_child(sale)
	if not str(entry.get("crop", "")).is_empty() or not str(entry.get("breed", "")).is_empty():
		var bare := Button.new()
		bare.text = "Clear the plot"
		bare.tooltip_text = "Pull up the crop, or drive the herd into your store to ship or sell."
		bare.pressed.connect(func() -> void: GameState.clear_plot(key))
		box.add_child(bare)
	return card


## What a plot grows or grazes, in words.
func _use_text(key: String) -> String:
	var farms := GameState.farms
	var entry := farms.plot(key)
	var crop_id := str(entry.get("crop", ""))
	var breed_id := str(entry.get("breed", ""))
	var port := Farms.port_of(key)
	if not crop_id.is_empty():
		var name := str(GameData.commodity(crop_id).get("name", crop_id))
		var parts := PackedStringArray(["%s · %s fit (%d%%)" % [name, Farms.fit_text(farms.effective_fit(key, crop_id)), roundi(farms.effective_fit(key, crop_id) * 100.0)]])
		var bearing := farms.bearing(key)
		if Farms.crop(crop_id).get("orchard", false) and bearing < 1.0:
			parts.append("bearing %d%%" % roundi(bearing * 100.0))
		elif bearing <= 0.0:
			parts.append("growing: first harvest after %d days" % int(Farms.setting("grow_days", 90)))
		parts.append("harvests %s" % Farms.months_text(Farms.harvest_months(port, crop_id)))
		parts.append("about %s %s a year" % [Fmt.thousands(roundi(farms.yield_a_year(key, crop_id))), GameData.commodity(crop_id).get("units", "units")])
		return " · ".join(parts)
	if not breed_id.is_empty():
		var each := Farms.breed(breed_id)
		return "%s %s · %s fit · herd %s of %s · about %s young a year" % [each.name, _species_word(each.species), Farms.fit_text(Farms.breed_fit(port, breed_id)),
			Fmt.thousands(roundi(float(entry.get("head", 0.0)))), Fmt.thousands(roundi(farms.head_room(key, breed_id))), Fmt.thousands(roundi(farms.young_a_year(key, breed_id)))]
	return "Bare: plant a crop or graze a herd."


static func _species_word(species: String) -> String:
	return {cows = "cattle", sheep = "sheep", pigs = "pigs", horses = "horses"}.get(species, species)


## The company's farm store at the port: what's in it, how fresh, its worth, and a Sell button each.
func _store_card() -> Control:
	var farms := GameState.farms
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var title := Label.new()
	title.text = "Your farm store"
	title.add_theme_font_size_override(&"font_size", 17)
	box.add_child(title)
	box.add_child(_dim("Your harvest and young stock wait here for your ships: grain carriers take the dry crops, Fresh produce carriers the fruit, berries and vegetables, livestock carriers the stock, all free. Fresh crops lose value by the day; a cold store slows that to a quarter."))
	var items := farms.store_items(GameState.company, port_id)
	if items.is_empty():
		box.add_child(_dim("Empty."))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override(&"h_separation", 18)
	for item: String in items:
		var held: Array = items[item]
		if float(held[0]) < 1.0:
			continue
		grid.add_child(_text(Farms.item_name(item)))
		grid.add_child(_text("%s %s" % [Fmt.thousands(floori(float(held[0]))), GameData.commodity(Farms.item_commodity(item)).get("units", "units")]))
		grid.add_child(_text("" if not Farms.item_breed(item).is_empty() else "%d%% fresh" % roundi(float(held[1]) * 100.0)))
		grid.add_child(_text(Fmt.money(roundi(float(held[0]) * GameState.company_sell_price(port_id, Farms.item_commodity(item)) * Farms.breed_value(Farms.item_breed(item)) * float(held[1])))))
		var sell := Button.new()
		sell.text = "Sell here"
		sell.pressed.connect(func() -> void: GameState.sell_farm_item(port_id, item))
		grid.add_child(sell)
	box.add_child(grid)
	var cold := bool(GameState.company.farm_stores.get(port_id, {}).get("cold", false))
	if cold:
		box.add_child(_dim("Cold store built: fresh crops keep four times as long."))
	else:
		box.add_child(_action("Build a cold store %s" % Fmt.money_short(int(Farms.setting("cold_store_cost", 1500000))), farms.cold_store_error(GameState.company, port_id), func() -> void: GameState.build_cold_store(port_id)))
	return card


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


static func _and(words: Array) -> String:
	if words.size() <= 1:
		return "".join(words)
	return "%s and %s" % [", ".join(words.slice(0, -1)), words[-1]]

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name EnergyScreen
extends Control
## The Energy screen (the Energy page over the map, for Tankers companies):
## the oil and gas fields down the left (all, the company's own, those with
## slots for sale) or the ports with its buildings, and the one picked on the
## right. A field: what it is, the company's storage there, its ships on rig
## runs to it (and sending another), and a card for each slot (who owns it,
## and for the company's own its rig's output, damage, upgrades, pipeline,
## repairs, listing and sale). A port: the company's buildings there (and
## putting up others), what they make, and its store. See Energy.

const LIST_WIDTH := 330.0
const CARD_WIDTH := 400.0
const FONT_SIZE := 14
## A sale takes a second click within this many seconds.
const CONFIRM_S := 3.0
const VIEWS := ["All fields", "My rigs", "Slots for sale", "My refineries"]

## What's shown: "field:ID" or "port:ID".
var place := ""
var _view := 0
var _list := VBoxContainer.new()
var _detail := VBoxContainer.new()
var _picker := OptionButton.new()
var _confirm := {}  # Slot key or "port/building" -> when its sale was first clicked (ms).
var _dirty := true
var _pickers: Array[OptionButton] = []
var _clock := 0.0
const REFRESH_S := 5.0
## The ship and delivery port picked to send on rig runs to the field shown.
var _run_ship := 0
var _run_port := ""


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
	title.text = "Energy"
	left_box.add_child(title)
	left_box.add_child(_dim("Put up oil rigs and gas platforms on the world's offshore fields and send tankers and gas carriers out to collect, or lay a pipeline to a hub. Build refineries at any port to turn crude into diesel, gasoline and jet fuel."))
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
	GameState.energy_changed.connect(func() -> void: _dirty = true)
	visibility_changed.connect(func() -> void: _dirty = true)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_S:
		_clock = 0.0
		_dirty = true
	var focus := get_viewport().gui_get_focus_owner()
	var typing := (focus is LineEdit) and _detail.is_ancestor_of(focus)  # (A listing price being typed.)
	if _dirty and not typing and not _pickers.any(func(picker: OptionButton) -> bool: return is_instance_valid(picker) and picker.get_popup().visible):
		_dirty = false
		_rebuild_list()
		_rebuild_detail()


## Shows a field ("field:brent", or its lanes' end "@rig_brent") or a port ("port:RTM", or just "RTM").
func show_place(id: String) -> void:
	if Energy.is_field_end(id):
		id = "field:" + Energy.field_of_end(id)
	elif not id.contains(":"):
		id = "port:" + id
	place = id
	_view = 3 if id.begins_with("port:") else 0
	_picker.select(_view)
	_dirty = true


func _rebuild_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var energy := GameState.energy
	if _view == 3:
		var ports := energy.plant_ports(GameState.company)
		for hub in GameState.hubs:
			if not ports.has(hub.port_id):
				ports.append(hub.port_id)
		if place.begins_with("port:") and not ports.has(place.substr(5)):
			ports.push_front(place.substr(5))
		for port_id in ports:
			var built := energy.plants_at(GameState.company, port_id).keys().map(func(id: String) -> String: return str(Energy.building(id).get("name", id)))
			var notes := PackedStringArray([", ".join(built) if not built.is_empty() else "nothing built yet"])
			if GameState.hub_at(port_id) != null:
				notes.insert(0, GameState.hub_at(port_id).title().get_slice(" ", GameState.hub_at(port_id).title().get_slice_count(" ") - 1))
			_list.add_child(_list_button("port:" + port_id, "%s\n%s" % [GameData.port_name(port_id), " · ".join(notes)]))
		var note := _dim("Build at any other port from its popup on the map (Energy).")
		_list.add_child(note)
		if place.is_empty() and not ports.is_empty():
			place = "port:" + ports[0]
		return
	var fields := Energy.field_ids()
	var rank := func(id: String) -> int: return 0 if not energy.owned_by(GameState.company, id).is_empty() else 1
	fields.sort_custom(func(a: String, b: String) -> bool:
		return Energy.field_name(a) < Energy.field_name(b) if rank.call(a) == rank.call(b) else rank.call(a) < rank.call(b))
	for id in fields:
		var info := Energy.field(id)
		var mine := energy.owned_by(GameState.company, id).size()
		var listed := Energy.keys_at(id).filter(func(key: String) -> bool: return int(energy.slot(key).get("listing", 0)) > 0 and energy.owner_of(key) != GameState.company).size()
		if _view == 1 and mine == 0 or _view == 2 and listed == 0:
			continue
		if place.is_empty():
			place = "field:" + id
		var total := int(info.get("slots", 0))
		var notes := PackedStringArray(["Oil" if str(info.kind) == "oil" else "Gas", "richness %d%%" % roundi(float(info.richness) * 100.0), "%d of %d free" % [total - energy.taken_at(id), total]])
		if mine > 0:
			notes.append("%d yours" % mine)
		if listed > 0:
			notes.append("%d for sale" % listed)
		_list.add_child(_list_button("field:" + id, "%s\n%s" % [Energy.field_name(id), " · ".join(notes)]))


func _list_button(id: String, text: String) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"TileButton"
	button.toggle_mode = true
	button.button_pressed = id == place
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override(&"font_size", FONT_SIZE)
	button.text = text
	button.pressed.connect(func() -> void:
		place = id
		_dirty = true)
	return button


func _rebuild_detail() -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	_pickers.clear()
	if place.begins_with("field:"):
		_field_detail(place.substr(6))
	elif place.begins_with("port:"):
		_port_detail(place.substr(5))


func _header(text: String, map_place: String) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.text = text
	header.add_child(name_label)
	var map := Button.new()
	map.text = "Show on map"
	map.size_flags_vertical = SIZE_SHRINK_CENTER
	map.pressed.connect(func() -> void: GameRoot.find(self).show_port_on_map(map_place))
	header.add_child(map)
	_detail.add_child(header)


# --- A field -----------------------------------------------------------------------------------

func _field_detail(field_id: String) -> void:
	var energy := GameState.energy
	var info := Energy.field(field_id)
	if info.is_empty():
		return
	var kind := Energy.kind_on(field_id)
	var rig := Energy.rig_info(kind)
	_header(Energy.field_name(field_id), Energy.end_of(field_id))
	var ports := Energy.lane_ports(field_id).slice(0, 4).map(func(id: String) -> String: return GameData.port_name(id))
	_detail.add_child(_text("%s field · richness %d%% · %s" % ["An oil" if str(info.kind) == "oil" else "A gas", roundi(float(info.richness) * 100.0), info.get("known", "")]))
	_detail.add_child(_dim("Nearest ports: %s." % ", ".join(ports)))
	if not Energy.can_drill(GameState.company):
		_detail.add_child(_error("Only Tankers companies drill: open a Tankers division."))
	var gives := "crude oil, with a little LNG and LPG" if kind == "rig" else "LNG and LPG"
	_detail.add_child(_text("Slots: you may own %d of the %d here. %s costs %s and gives %s; its crew costs %s every pay period." % [Energy.most_at(field_id), int(info.get("slots", 0)),
		_a(str(rig.name).to_lower()).capitalize().get_slice(" ", 0) + " " + str(rig.name).to_lower(), Fmt.money(int(rig.cost)), gives, Fmt.money(int(rig.wages))]))
	var mine := energy.owned_by(GameState.company, field_id)
	if not mine.is_empty():
		_detail.add_child(_storage_card(field_id))
		_detail.add_child(_runs_card(field_id))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	for key in Energy.keys_at(field_id):
		grid.add_child(_slot_card(key))
	_detail.add_child(grid)


## The company's storage at a field: what its rigs there have made, waiting for its ships.
func _storage_card(field_id: String) -> Control:
	var energy := GameState.energy
	var box := _card("Your storage at %s" % Energy.field_name(field_id))
	var items := energy.sea_items(GameState.company, field_id)
	var room := energy.sea_room(GameState.company, field_id)
	if room <= 0.0:
		box.add_child(_dim("Your rigs here are all piped ashore: their output goes straight into your store at the port."))
		return box.get_parent()
	box.add_child(_text("%s of %s tons held. Full, your rigs here stop pumping, so send ships to collect." % [Fmt.thousands(roundi(energy.sea_total(GameState.company, field_id))), Fmt.thousands(roundi(room))]))
	var parts := PackedStringArray()
	for commodity: String in items:
		parts.append("%s tons of %s" % [Fmt.thousands(roundi(float(items[commodity]))), Energy.good_word(commodity)])
	if not parts.is_empty():
		box.add_child(_dim(", ".join(parts) + "."))
	return box.get_parent()


## The company's ships on rig runs to a field, and sending another.
func _runs_card(field_id: String) -> Control:
	var energy := GameState.energy
	var box := _card("Rig runs")
	box.add_child(_dim("A tanker or gas carrier on rig runs sails out to the field, loads what your rigs have stored (waiting up to %d days for a full hold), and brings it to its delivery port: sold there, or into your refinery's tanks if you have one there that takes it. It needs the fuel there and back on one tank." % int(Energy.setting("rig_wait_days", 3))))
	var running := GameState.fleet().filter(func(ship: Ship) -> bool: return ship.rig_field == field_id)
	for ship: Ship in running:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var label := _text("%s → %s: %s" % [ship.name, GameData.port_name(ship.rig_port), ship.status_text()])
		label.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(label)
		var stop := Button.new()
		stop.text = "Stop"
		stop.tooltip_text = "Off rig runs once it's back at %s." % GameData.port_name(ship.rig_port)
		stop.pressed.connect(func() -> void: GameState.set_rig_run(ship, "", ""))
		row.add_child(stop)
		box.add_child(row)
	var ships := GameState.fleet().filter(func(ship: Ship) -> bool:
		return not ship.is_service() and ship.rig_field != field_id and not Energy.carries_from(ship.model(), field_id).is_empty())
	if ships.is_empty():
		box.add_child(_dim("None of your other ships can carry what this field gives (%s)." % ("tankers for the crude, gas carriers for the gas" if Energy.kind_on(field_id) == "rig" else "gas carriers")))
		return box.get_parent()
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 8)
	var ship_picker := OptionButton.new()
	ship_picker.add_theme_font_size_override(&"font_size", FONT_SIZE)
	if not ships.any(func(ship: Ship) -> bool: return ship.id == _run_ship):
		_run_ship = (ships[0] as Ship).id
	for ship: Ship in ships:
		ship_picker.add_item("%s (%s)" % [ship.name, ship.model().get("name", "")])
		ship_picker.set_item_metadata(ship_picker.item_count - 1, ship.id)
		if ship.id == _run_ship:
			ship_picker.select(ship_picker.item_count - 1)
	ship_picker.item_selected.connect(func(index: int) -> void:
		_run_ship = int(ship_picker.get_item_metadata(index))
		_dirty = true)
	row.add_child(ship_picker)
	_pickers.append(ship_picker)
	var port_picker := OptionButton.new()
	port_picker.add_theme_font_size_override(&"font_size", FONT_SIZE)
	var choices := _delivery_ports(field_id)
	if not choices.has(_run_port):
		_run_port = choices[0] if not choices.is_empty() else ""
	for port_id: String in choices:
		var tags := PackedStringArray()
		if GameState.hub_at(port_id) != null:
			tags.append("your %s" % ("HQ" if GameState.hub_at(port_id).is_hq else "hub"))
		if not energy.plants_at(GameState.company, port_id).is_empty():
			tags.append("your refinery")
		port_picker.add_item("to %s · %s nm%s" % [GameData.port_name(port_id), Fmt.thousands(roundi(Energy.miles_to(port_id, field_id))), " · " + ", ".join(tags) if not tags.is_empty() else ""])
		port_picker.set_item_metadata(port_picker.item_count - 1, port_id)
		if port_id == _run_port:
			port_picker.select(port_picker.item_count - 1)
	port_picker.item_selected.connect(func(index: int) -> void:
		_run_port = str(port_picker.get_item_metadata(index))
		_dirty = true)
	row.add_child(port_picker)
	_pickers.append(port_picker)
	var chosen: Ship = null
	for ship: Ship in ships:
		if ship.id == _run_ship:
			chosen = ship
	var error := energy.run_error(GameState.company, chosen, field_id, _run_port) if chosen != null and not _run_port.is_empty() else "Pick a ship and a port"
	row.add_child(_action("Send on rig runs", error, func() -> void: GameState.set_rig_run(chosen, field_id, _run_port)))
	box.add_child(row)
	return box.get_parent()


## The ports a field's loads might go to: the company's HQ and hubs and ports
## with its buildings within reach of the field, then the field's own nearest ports; nearest first.
func _delivery_ports(field_id: String) -> Array:
	var out := []
	var candidates: Array = []
	for hub in GameState.hubs:
		candidates.append(hub.port_id)
	candidates.append_array(GameState.energy.plant_ports(GameState.company))
	candidates.append_array(Energy.lane_ports(field_id).slice(0, 6))
	for port_id: String in candidates:
		if not out.has(port_id) and Energy.miles_to(port_id, field_id) < 4500.0:
			out.append(port_id)
	out.sort_custom(func(a: String, b: String) -> bool: return Energy.miles_to(a, field_id) < Energy.miles_to(b, field_id))
	return out


func _slot_card(key: String) -> Control:
	var energy := GameState.energy
	var field_id := Energy.field_of(key)
	var kind := Energy.kind_on(field_id)
	var rig := Energy.rig_info(kind)
	var box := _card("Slot %d" % (Energy.index_of(key) + 1))
	var owner := energy.owner_of(key)
	var entry := energy.slot(key)
	if owner == null:
		box.add_child(_text("Free: %s %s" % [str(rig.name).to_lower(), Fmt.money(int(rig.cost))]))
		box.add_child(_dim("About %s tons a year." % Fmt.thousands(roundi(float(rig.output_t) * float(Energy.field(field_id).richness) * (1.0 + float(rig.get("gas_share", 0.0)))))))
		box.add_child(_action("Put up %s" % _a(str(rig.name).to_lower()), energy.buy_error(GameState.company, key), func() -> void: GameState.buy_rig(key)))
		return box.get_parent()
	if owner != GameState.company:
		var label := _text("%s of %s" % [rig.name, owner.name])
		label.add_theme_color_override(&"font_color", GameState.company_color_value(owner.color).lightened(0.2))
		box.add_child(label)
		box.add_child(_dim(_state_text(key)))
		if int(entry.get("listing", 0)) > 0:
			box.add_child(_text("For sale: %s" % Fmt.money(int(entry.listing))))
			box.add_child(_action("Buy from %s" % owner.name, energy.listing_error(GameState.company, key), func() -> void: GameState.buy_listed_rig(key)))
		return box.get_parent()
	var mine := _text("Your %s" % str(rig.name).to_lower())
	mine.add_theme_color_override(&"font_color", GameState.company_color_value(GameState.company.color).lightened(0.2))
	box.add_child(mine)
	box.add_child(_text(_state_text(key)))
	if int(entry.get("damage", 0)) > 0:
		if int(entry.get("tug", 0)) != 0:
			box.add_child(_dim("A tug is on its way to repair it."))
		else:
			var repair := _action("Send a tug to repair it %s" % Fmt.money_short(energy.repair_fee(key)), energy.repair_error(GameState.company, key), func() -> void: GameState.send_rig_tug(key))
			box.add_child(repair)
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	for each: Dictionary in Energy.data().get("rig_upgrades", []):
		if (entry.get("upgrades", []) as Array).has(each.id):
			var done := _dim("%s built" % each.name)
			done.autowrap_mode = TextServer.AUTOWRAP_OFF
			done.size_flags_vertical = SIZE_SHRINK_CENTER
			done.tooltip_text = str(each.text)
			row.add_child(done)
			continue
		var button := _action("%s %s" % [each.name, Fmt.money_short(int(each.cost))], energy.upgrade_error(GameState.company, key, each.id), func() -> void: GameState.upgrade_rig(key, each.id))
		button.tooltip_text = str(each.text) + ("" if button.tooltip_text.is_empty() else "\n" + button.tooltip_text)
		row.add_child(button)
	box.add_child(row)
	var pipe := str(entry.get("pipe", ""))
	if not pipe.is_empty():
		box.add_child(_dim("Piped to %s: its output goes into your store there." % GameData.port_name(pipe)))
	else:
		var target := energy.pipe_target(GameState.company, field_id)
		var label := "Lay a pipeline to %s %s" % [GameData.port_name(str(target[0])), Fmt.money_short(energy.pipe_cost(float(target[1])))] if not str(target[0]).is_empty() else "Lay a pipeline"
		var button := _action(label, energy.pipe_error(GameState.company, key), func() -> void: GameState.lay_pipeline(key))
		if button.tooltip_text.is_empty():
			button.tooltip_text = "Its output goes straight into your store at your %s, %s nm away, for your ships to load there (or your refinery there to run on)." % ["HQ or hub", Fmt.thousands(roundi(float(target[1])))]
		box.add_child(button)
	box.add_child(_sale_row(key, int(entry.get("listing", 0)), int(entry.get("paid", rig.cost)), energy.sale_price(key),
		func(price: int) -> void: GameState.list_rig(key, price), func() -> void: GameState.sell_rig(key)))
	return box.get_parent()


## A slot's state: working (its output a year), shut by a storm, damaged or stopped.
func _state_text(key: String) -> String:
	var energy := GameState.energy
	var entry := energy.slot(key)
	var parts := PackedStringArray()
	match int(entry.get("damage", 0)):
		1:
			parts.append("Damaged: half output")
		2:
			parts.append("Stopped by storm damage")
		_:
			parts.append("Working")
	if bool(entry.get("shut", false)):
		parts.append("shut while a storm passes")
	parts.append("about %s tons a year" % Fmt.thousands(roundi(energy.output_a_year(key))))
	return " · ".join(parts)


# --- A port --------------------------------------------------------------------------------------

func _port_detail(port_id: String) -> void:
	var energy := GameState.energy
	var who := GameState.company
	_header(GameData.port_name(port_id), port_id)
	_detail.add_child(_text("%s · your buildings here, and the tanks they share." % GameData.port_region(port_id).get("name", "")))
	if not Energy.can_drill(who):
		_detail.add_child(_error("Only Tankers companies build refineries: choose Tankers as one of your company types."))
	_detail.add_child(_dim("Each building runs on what your own ships bring: unloaded into its tanks here (from your rigs, or bought elsewhere on a route ending here), and your ships load what it makes free. Your ships fill up their fuel free from the diesel in your tanks here."))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override(&"h_separation", 12)
	grid.add_theme_constant_override(&"v_separation", 12)
	for building_id in Energy.building_ids():
		grid.add_child(_building_card(port_id, building_id))
	_detail.add_child(grid)
	_detail.add_child(_store_card(port_id))


func _building_card(port_id: String, building_id: String) -> Control:
	var energy := GameState.energy
	var who := GameState.company
	var info := Energy.building(building_id)
	var box := _card(str(info.name))
	var outputs: Dictionary = info.get("outputs", {})
	if not energy.plants_at(who, port_id).has(building_id):
		box.add_child(_dim("%s: %s tons a day. Workers %s every pay period." % [info.text, Fmt.thousands(int(info.rate)), Fmt.money(int(info.wages))]))
		box.add_child(_action("Build %s" % Fmt.money_short(int(info.cost)), energy.build_error(who, building_id, port_id), func() -> void: GameState.build_plant(building_id, port_id)))
		return box.get_parent()
	var input := str(info.input)
	var output := energy.output_of(who, port_id, building_id)
	box.add_child(_text("%s → %s · %s tons a day (%d%%)" % [GameData.commodity(input).get("name", input), GameData.commodity(output).get("name", output),
		Fmt.thousands(roundi(energy.rate_of(who, port_id, building_id))), roundi(float(outputs.get(output, 1.0)) * 100.0)]))
	box.add_child(_dim("Tanks of %s tons each for its %s and its %s." % [Fmt.thousands(roundi(energy.tank_of(who, port_id, building_id))), Energy.good_word(input),
		Energy.good_word(output)]))
	if outputs.size() > 1:
		var mode := OptionButton.new()
		mode.add_theme_font_size_override(&"font_size", FONT_SIZE)
		for each: String in outputs:
			mode.add_item("Make %s (%d%%)" % [Energy.good_word(each), roundi(float(outputs[each]) * 100.0)])
			mode.set_item_metadata(mode.item_count - 1, each)
			if each == output:
				mode.select(mode.item_count - 1)
		mode.item_selected.connect(func(index: int) -> void: GameState.set_plant_mode(building_id, port_id, str(mode.get_item_metadata(index))))
		box.add_child(mode)
		_pickers.append(mode)
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	for each: Dictionary in Energy.data().get("building_upgrades", []):
		if (energy.plants_at(who, port_id)[building_id].get("upgrades", []) as Array).has(each.id):
			var done := _dim("%s built" % each.name)
			done.autowrap_mode = TextServer.AUTOWRAP_OFF
			done.tooltip_text = str(each.text)
			row.add_child(done)
			continue
		var button := _action("%s %s" % [each.name, Fmt.money_short(energy.building_upgrade_cost(building_id, each.id))], energy.plant_upgrade_error(who, building_id, port_id, each.id),
			func() -> void: GameState.upgrade_plant(building_id, port_id, each.id))
		button.tooltip_text = str(each.text) + ("" if button.tooltip_text.is_empty() else "\n" + button.tooltip_text)
		row.add_child(button)
	box.add_child(row)
	var key := port_id + "/" + building_id
	var down := Button.new()
	var confirming := Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0
	var refund := roundi(int(info.cost) * float(Energy.setting("sale_share", 0.5)))
	down.text = "Sure? %s back" % Fmt.money_short(refund) if confirming else "Pull down"
	down.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0:
			_confirm.erase(key)
			GameState.demolish_plant(building_id, port_id)
		else:
			_confirm[key] = Time.get_ticks_msec()
			_dirty = true)
	box.add_child(down)
	return box.get_parent()


## The company's store at a port: each good, its tons against its tanks, its worth, and Sell.
func _store_card(port_id: String) -> Control:
	var energy := GameState.energy
	var who := GameState.company
	var box := _card("Your tanks here")
	var items := energy.store_items(who, port_id)
	if items.is_empty():
		box.add_child(_dim("Empty."))
		return box.get_parent()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 18)
	for commodity: String in items:
		if float(items[commodity]) < 1.0:
			continue
		grid.add_child(_text(str(GameData.commodity(commodity).get("name", commodity))))
		var cap := energy.store_cap(who, port_id, commodity)
		grid.add_child(_text("%s%s tons" % [Fmt.thousands(floori(float(items[commodity]))), " of %s" % Fmt.thousands(roundi(cap)) if cap > 0.0 else ""]))
		grid.add_child(_text(Fmt.money(roundi(float(items[commodity]) * GameState.company_sell_price(port_id, commodity)))))
		var sell := Button.new()
		sell.text = "Sell here"
		sell.pressed.connect(func() -> void: GameState.sell_energy_item(port_id, commodity))
		grid.add_child(sell)
	box.add_child(grid)
	return box.get_parent()


# --- Bits ---------------------------------------------------------------------------------------

## Listing a slot for other companies, or selling it back.
func _sale_row(key: String, listing: int, paid: int, back: int, list: Callable, sell: Callable) -> Control:
	var sale := HFlowContainer.new()
	sale.add_theme_constant_override(&"h_separation", 6)
	if listing > 0:
		sale.add_child(_text("Listed at %s" % Fmt.money(listing)))
		var off := Button.new()
		off.text = "Take off the list"
		off.pressed.connect(func() -> void: list.call(0))
		sale.add_child(off)
	else:
		var price := SpinBox.new()
		price.min_value = 1000000
		price.max_value = 1000000000
		price.step = 100000
		price.value = maxi(paid, 1000000)
		price.prefix = "$"
		price.custom_minimum_size.x = 150
		sale.add_child(price)
		var list_button := Button.new()
		list_button.text = "List for sale"
		list_button.tooltip_text = "Other Tankers companies can buy it, with its upgrades, at this price."
		list_button.pressed.connect(func() -> void: list.call(int(price.value)))
		sale.add_child(list_button)
	var button := Button.new()
	var confirming := Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0
	button.text = "Sure? %s" % Fmt.money_short(back) if confirming else "Sell it off"
	button.tooltip_text = "For %s (half its cost)." % Fmt.money(back)
	button.pressed.connect(func() -> void:
		if Time.get_ticks_msec() - int(_confirm.get(key, -100000)) < CONFIRM_S * 1000.0:
			_confirm.erase(key)
			sell.call()
		else:
			_confirm[key] = Time.get_ticks_msec()
			_dirty = true)
	sale.add_child(button)
	return sale


## A card with a title: returns its box (the card is its parent).
func _card(title_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size.x = CARD_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	card.add_child(box)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override(&"font_size", 17)
	box.add_child(title)
	return box


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


## "a rig", "an oil rig".
static func _a(word: String) -> String:
	return ("an " if word.left(1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + word

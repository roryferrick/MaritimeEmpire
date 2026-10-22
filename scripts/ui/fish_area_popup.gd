# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name FishAreaPopup
extends Control
## A picked fishing ground's boats (the Fishing Grounds screen, FishingScreen):
## a row for each boat model whose gear and depth can work something there
## (only those), with how many of the company's boats of it are sent there
## (+ on the left, the number, - on the right: GameState.assign_fish_boats(),
## the free boats nearest the ground first), the port they land their catch
## at (any of the HQ, the hubs and the ports by the ground), and whether it
## goes in the freezer for the seafood carriers (only at the HQ or a hub:
## GameState.set_fish_area_model()). Each row says how its boats get there:
## straight out on their trips, or to a port by the ground by way of refuel
## stops, named, fishing from there and coming back the same way with the catch.
## Over the screen, dimming it; Esc, X or a click outside closes it.

const PANEL_WIDTH := 640.0
const PICTURE_LENGTH := 64.0

var ground_id := ""
var _rows := VBoxContainer.new()


func _init(for_ground: String) -> void:
	ground_id = for_ground


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
	card.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	card.add_child(content)
	var fish := Fisheries.shared()
	var ground: Dictionary = fish.grounds.get(ground_id, {})
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = Fisheries.short_ground_name(ground_id)
	title.tooltip_text = Fisheries.ground_name(ground_id)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var about := Label.new()
	about.theme_type_variation = &"DimLabel"
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.text = "Send boats here by model. Each lands its catch at the port you choose: sold there, or kept in the freezer for your seafood carriers (freezers are at your HQ and hubs only). Boats whose port is beyond a trip from here sail to a port by the ground first, refuelling on the way, fish from there, and bring the catch back the same way."
	content.add_child(about)
	content.add_child(HSeparator.new())
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 360)
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_theme_constant_override(&"separation", 12)
	scroll.add_child(_rows)
	content.add_child(scroll)
	_fill()
	GameState.fish_areas_changed.connect(_refill)
	GameState.ships_changed.connect(_refill)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _refill() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_fill.call_deferred()


func _fill() -> void:
	var fish := Fisheries.shared()
	var any := false
	for model: Dictionary in GameData.ship_models:
		if not model.has("fishing") or not fish.model_works_ground(model, ground_id):
			continue  # (Only the models that can work something here.)
		any = true
		_rows.add_child(_model_row(model))
	if not any:
		var none := Label.new()
		none.text = "None of the boat models can work this ground."
		_rows.add_child(none)


func _model_row(model: Dictionary) -> Control:
	var fish := Fisheries.shared()
	var model_id := str(model.id)
	var sent := GameState.fish_area_boats(ground_id, model_id)
	var free := GameState.free_fish_boats(model_id)
	var owned := sent.size() + free.size()
	for ship in GameState.fleet():
		if ship.model_id == model_id and ship.is_fishing() and not ship.fish_area.is_empty() and ship.fish_area != ground_id:
			owned += 1
	var setting := GameState.fish_area_setting(ground_id, model_id)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	var top := HBoxContainer.new()
	top.add_theme_constant_override(&"separation", 10)
	box.add_child(top)
	var picture := ShipPicture.new(model, PICTURE_LENGTH)
	picture.custom_minimum_size = Vector2(PICTURE_LENGTH, 26)
	top.add_child(picture)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = SIZE_EXPAND_FILL
	names.add_theme_constant_override(&"separation", 0)
	var name_label := Label.new()
	name_label.text = str(model.name)
	name_label.add_theme_color_override(&"font_color", Color.from_string(str(model.get("map_color", "#ffffff")), Color.WHITE).lightened(0.2))
	names.add_child(name_label)
	var counts := Label.new()
	counts.theme_type_variation = &"DimLabel"
	counts.add_theme_font_size_override(&"font_size", 13)
	counts.text = "You own %d · %d free · %s" % [owned, free.size(), _catches(model)]
	counts.clip_text = true
	names.add_child(counts)
	top.add_child(names)
	# The count: + on the left, the number in the middle, - on the right.
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(36, 32)
	plus.disabled = free.is_empty()
	plus.tooltip_text = "Send one more %s here" % model.name if not free.is_empty() else ("Every %s you own is busy on another ground" % model.name if owned > 0 else "You own no %s: buy one in the Shop" % model.name)
	plus.pressed.connect(func() -> void: GameState.assign_fish_boats(ground_id, model_id, sent.size() + 1))
	top.add_child(plus)
	var number := Label.new()
	number.text = str(sent.size())
	number.custom_minimum_size = Vector2(34, 0)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override(&"font_size", 20)
	top.add_child(number)
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(36, 32)
	minus.disabled = sent.is_empty()
	minus.tooltip_text = "Call one %s off (it goes back to fishing the best within reach of its port)" % model.name
	minus.pressed.connect(func() -> void: GameState.assign_fish_boats(ground_id, model_id, sent.size() - 1))
	top.add_child(minus)
	# Where the catch lands, and the freezer.
	var landing := HBoxContainer.new()
	landing.add_theme_constant_override(&"separation", 10)
	box.add_child(landing)
	var lands := Label.new()
	lands.text = "Lands its catch at"
	landing.add_child(lands)
	var ports := OptionButton.new()
	ports.size_flags_horizontal = SIZE_EXPAND_FILL
	ports.fit_to_longest_item = false
	ports.clip_text = true
	for entry: Array in _port_choices(str(setting.port)):
		ports.add_item(entry[1])
		ports.set_item_metadata(ports.item_count - 1, entry[0])
		if entry[0] == setting.port:
			ports.select(ports.item_count - 1)
	landing.add_child(ports)
	var freezer := CheckBox.new()
	freezer.text = "Freezer"
	var has_freezer := GameState.hub_at(str(setting.port)) != null
	freezer.disabled = not has_freezer
	freezer.button_pressed = bool(setting.freeze)
	freezer.tooltip_text = "Keep the catch in the freezer there for your seafood carriers (Reefers) to take where it pays most, rather than selling it as it lands." if has_freezer \
		else "Freezers are at your HQ and hubs only: pick one of them to freeze the catch."
	landing.add_child(freezer)
	ports.item_selected.connect(func(index: int) -> void:
		var port := str(ports.get_item_metadata(index))
		GameState.set_fish_area_model(ground_id, model_id, port, freezer.button_pressed and GameState.hub_at(port) != null))
	freezer.toggled.connect(func(on: bool) -> void:
		GameState.set_fish_area_model(ground_id, model_id, str(ports.get_item_metadata(ports.selected)), on))
	# How its boats get here from that port.
	var way := Label.new()
	way.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	way.add_theme_font_size_override(&"font_size", 13)
	var sample: Ship = sent[0] if not sent.is_empty() else (free[0] if not free.is_empty() else null)
	if sample == null:
		way.theme_type_variation = &"DimLabel"
		way.text = "Range %s nm on a tank." % Fmt.thousands(roundi(float(model.get("range_nm", 0.0))))
	else:
		var port := str(setting.port)
		var stage := GameState.fishing_stage_from(sample, port, ground_id)
		if stage.is_empty():
			way.theme_type_variation = &"ErrorLabel"
			way.text = "A %s can't get here from %s, even refuelling on the way: choose another port." % [model.name, GameData.port_name(port)]
		elif stage == port:
			way.theme_type_variation = &"DimLabel"
			way.text = "Trips go straight out from %s (%s nm each way)." % [GameData.port_name(port), Fmt.thousands(roundi(fish.miles_to(port, ground_id)))]
		else:
			var stops := GameState.refuel_stops(sample, port, stage)
			way.add_theme_color_override(&"font_color", MapView.REFUEL_COLOR)
			way.text = "Beyond a trip from %s: its boats sail to %s and fish from there%s, then bring the catch back the same way to land it." % [
				GameData.port_name(port), GameData.port_name(stage), (", and " + GameState.refuel_text(stops) + " on the way each way") if not stops.is_empty() else ""]
	box.add_child(way)
	box.add_child(HSeparator.new())
	return box


## "Catches snow crab, king crab" for a model here.
func _catches(model: Dictionary) -> String:
	var fish := Fisheries.shared()
	var names := PackedStringArray()
	for species_id: String in fish.grounds[ground_id].species:
		if fish.can_work(model, ground_id, species_id):
			names.append(fish.species_word(species_id))
	return "catches " + ", ".join(names)


## The ports to land a catch at: the HQ and hubs (with their freezers), then
## the ports by the ground, nearest first; `current` too if it's none of those.
func _port_choices(current: String) -> Array:
	var fish := Fisheries.shared()
	var out := []
	var seen := {}
	for hub: Hub in GameState.company.hubs:
		var label := "%s (%s, freezer) · %s nm" % [GameData.port_name(hub.port_id), "HQ" if hub.is_hq else "hub", Fmt.thousands(roundi(fish.miles_to(hub.port_id, ground_id)))]
		out.append([hub.port_id, label])
		seen[hub.port_id] = true
	var near: Array = (fish.grounds[ground_id].get("ports", []) as Array).duplicate()
	near.sort_custom(func(a: String, b: String) -> bool: return fish.miles_to(a, ground_id) < fish.miles_to(b, ground_id))
	for port: String in near:
		if seen.has(port):
			continue
		out.append([port, "%s (by the ground) · %s nm" % [GameData.port_name(port), Fmt.thousands(roundi(fish.miles_to(port, ground_id)))]])
		seen[port] = true
	if not current.is_empty() and not seen.has(current):
		out.append([current, GameData.port_name(current)])
	return out

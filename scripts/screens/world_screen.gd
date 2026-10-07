# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## The main map: ports, ships, canal locks, storms and sea animals, with their popups, and the Routes switch,
## Tutorial switch (in saves with the tutorial) and price picker in one panel in
## the top right (the fleet's route lanes shown faintly; the tutorial's tips;
## ports colored by a commodity's price), with an Unlock a region button over
## them while a market region can be unlocked (see _add_region_choice()).

## Commodity colors (their ship line's) are brightened to at least this
## luminance so they read on the dark panel.
const LINE_MIN_LUMINANCE := 0.5
## How strongly each ship line's group is tinted in the price menu.
const PRICE_GROUP_TINT := 0.16

@onready var _map: MapView = $MapView
var _price_button := Button.new()
var _price_menu := PopupPanel.new()
## Unlocking a market region: a button at the top of the map panel while one
## can be unlocked opens the choice, where the map outlines the regions and
## lights up the locked one under the mouse, a banner says what to do, and each
## locked region has a button at its middle (click it, or the region, then
## again to unlock it: _armed is the one clicked once).
var _unlock_button := Button.new()
var _choose_layer := Control.new()
var _region_buttons := {}  # Region id -> its Button.
var _armed := ""


func _ready() -> void:
	_map.show_ships = true
	_map.show_active_lanes = GameState.show_active_routes
	_map.port_clicked.connect(_open_port_popup)
	_map.ship_clicked.connect(open_ship_popup)
	_map.lock_clicked.connect(_open_lock_popup)
	_map.canal_clicked.connect(_open_convoy_popup)
	_map.storm_clicked.connect(_open_storm_popup)
	_map.pod_clicked.connect(_open_pod_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())
	%RoutesToggle.set_pressed_no_signal(GameState.show_active_routes)
	%RoutesToggle.toggled.connect(_on_routes_toggled)
	if GameState.tutorials:
		_add_tutorial_toggle()
	_add_price_picker()
	_add_region_choice()


func _process(_delta: float) -> void:
	var available := GameState.regions_available()
	_unlock_button.visible = available > 0 and not _map.choosing_region
	_unlock_button.text = "Unlock a region (%d)" % available if available > 1 else "Unlock a region"
	if not _map.choosing_region:
		return
	if available <= 0:
		_stop_choosing()
		return
	var area := Rect2(Vector2.ZERO, _map.size)
	for region_id: String in _region_buttons:
		var button: Button = _region_buttons[region_id]
		var at := _map.region_screen_position(region_id)
		button.visible = not GameState.is_region_unlocked(region_id) and area.has_point(at)
		button.position = at - button.size / 2.0


func _unhandled_input(event: InputEvent) -> void:
	if _map.choosing_region and event.is_action_pressed(&"ui_cancel"):
		_stop_choosing()
		get_viewport().set_input_as_handled()


## The Unlock a region button (first in the map panel), the banner and the
## regions' buttons shown while choosing.
func _add_region_choice() -> void:
	_unlock_button.tooltip_text = "Pick a new market region on the map: its ports open to your ships."
	_unlock_button.pressed.connect(_start_choosing)
	%MapControls.add_child(_unlock_button)
	%MapControls.move_child(_unlock_button, 0)
	_choose_layer.set_anchors_preset(PRESET_FULL_RECT)
	_choose_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_choose_layer.visible = false
	add_child(_choose_layer)
	var banner := PanelContainer.new()
	banner.theme_type_variation = &"MapPopup"
	banner.set_anchors_and_offsets_preset(PRESET_CENTER_BOTTOM, PRESET_MODE_MINSIZE, 12)
	banner.grow_horizontal = GROW_DIRECTION_BOTH
	banner.grow_vertical = GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)
	var text := Label.new()
	text.text = "Choose a region to unlock: hover over the map to see each one,\nthen click it or its button, and click again to unlock it."
	row.add_child(text)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.size_flags_vertical = SIZE_SHRINK_CENTER
	cancel.pressed.connect(_stop_choosing)
	row.add_child(cancel)
	banner.add_child(row)
	_choose_layer.add_child(banner)
	_map.region_clicked.connect(_pick_region)
	for region: Dictionary in GameData.markets.get("regions", []):
		var region_id := str(region.id)
		var button := Button.new()
		button.mouse_entered.connect(func() -> void: _map.hovered_region = region_id)
		button.mouse_exited.connect(func() -> void:
			if _map.hovered_region == region_id and _armed != region_id:
				_map.hovered_region = "")
		button.pressed.connect(_pick_region.bind(region_id))
		_choose_layer.add_child(button)
		_region_buttons[region_id] = button


func _start_choosing() -> void:
	PopupHost.find(self).close()
	_armed = ""
	_label_region_buttons()
	_map.choosing_region = true
	_choose_layer.visible = true


func _stop_choosing() -> void:
	_map.choosing_region = false
	_choose_layer.visible = false
	_armed = ""


## A region's button (or area) clicked: the first time it's armed (lit up,
## its button asking to click again), the second it's unlocked.
func _pick_region(region_id: String) -> void:
	if _armed != region_id:
		_armed = region_id
		_map.hovered_region = region_id
		_label_region_buttons()
		return
	var error := GameState.unlock_region(region_id)
	if not error.is_empty():
		ActivityLog.add(error, ActivityLog.Kind.BAD)
	_stop_choosing()


func _label_region_buttons() -> void:
	for region: Dictionary in GameData.markets.get("regions", []):
		var button: Button = _region_buttons[str(region.id)]
		button.text = "Click again to unlock %s" % region.name if region.id == _armed else str(region.name)
		button.tooltip_text = "Unlock %s" % region.name
		button.reset_size()


## The Tutorial switch under Routes, only in saves started with the tutorial:
## shows or hides the tutorial's tips (see TutorialCard).
func _add_tutorial_toggle() -> void:
	var toggle := CheckButton.new()
	toggle.text = "Tutorial"
	toggle.tooltip_text = "Show tips that explain the basics as you play."
	toggle.set_pressed_no_signal(GameState.tutorials_on)
	toggle.toggled.connect(func(on: bool) -> void: GameState.tutorials_on = on)
	%MapControls.add_child(toggle)


func _on_routes_toggled(on: bool) -> void:
	GameState.show_active_routes = on
	_map.show_active_lanes = on


func _open_port_popup(port_id: String) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.port_screen_position(port_id)
	PopupHost.find(self).show_port(port_id, follow)


func _open_lock_popup(canal_id: String, lock_index: int) -> void:
	var popup := LockPopup.new()
	popup.canal_id = canal_id
	popup.lock_index = lock_index
	popup.follow = func() -> Vector2:
		return _map.get_global_transform() * _map.lock_screen_position(canal_id, lock_index)
	PopupHost.find(self).open(popup)


func _open_convoy_popup(canal_id: String) -> void:
	var popup := ConvoyPopup.new()
	popup.canal_id = canal_id
	popup.follow = func() -> Vector2:
		return _map.get_global_transform() * _map.canal_screen_position(canal_id)
	PopupHost.find(self).open(popup)


## A storm's popup, following its center; its track shows stronger meanwhile.
func _open_storm_popup(storm_key: String) -> void:
	var popup := StormPopup.new()
	popup.storm_key = storm_key
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := _map.storm_screen_position(storm_key)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	popup.tree_exited.connect(func() -> void:
		if _map.selected_storm == storm_key:
			_map.selected_storm = "")
	PopupHost.find(self).open(popup)
	_map.selected_storm = storm_key


## A pod of sea animals' popup, following it; its routes show meanwhile.
func _open_pod_popup(pod_index: int) -> void:
	var popup := SeaLifePopup.new()
	popup.pod_index = pod_index
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := _map.pod_screen_position(pod_index)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	popup.tree_exited.connect(func() -> void:
		if _map.selected_pod == pod_index:
			_map.selected_pod = -1)
	PopupHost.find(self).open(popup)
	_map.selected_pod = pod_index


## The ship's popup, following it on the map.
func open_ship_popup(ship: Ship) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.ship_screen_position(ship)
	PopupHost.find(self).show_ship(ship, follow)


## "Prices: Toys ▾" under the Routes switch, in the same panel: colors the ports
## by that commodity's price (see MapView.price_commodity), or "Prices: off". Its
## menu groups the commodities by the ship line that carries them, each group on
## a faint tint of the line's color, each commodity with a swatch in it; the
## chosen one's name is shown in that color too.
func _add_price_picker() -> void:
	_price_button.tooltip_text = "Color the ports by a commodity's price: green where it's cheap, red where it's expensive."
	_price_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_price_button.pressed.connect(_open_price_menu)
	%MapControls.add_child(_price_button)

	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 3)
	_price_menu.add_child(list)
	list.add_child(_price_item(""))
	var group: VBoxContainer = null
	var group_color := Color.TRANSPARENT
	for commodity: Dictionary in GameData.commodities:
		var color := _line_color(commodity.id)
		if group == null or color != group_color:
			group_color = color
			var tint := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color(color, PRICE_GROUP_TINT)
			style.set_corner_radius_all(4)
			tint.add_theme_stylebox_override(&"panel", style)
			list.add_child(tint)
			group = VBoxContainer.new()
			group.add_theme_constant_override(&"separation", 0)
			tint.add_child(group)
		group.add_child(_price_item(commodity.id))
	_price_menu.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"MapPopup"))
	add_child(_price_menu)
	_choose_price("")


## One entry in the price menu: "Prices: Toys" with its line's swatch.
func _price_item(commodity_id: String) -> Button:
	var item := Button.new()
	item.flat = true
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.text = _price_text(commodity_id)
	if not commodity_id.is_empty():
		item.icon = _swatch(_line_color(commodity_id))
	item.pressed.connect(_choose_price.bind(commodity_id))
	return item


func _price_text(commodity_id: String) -> String:
	return "Prices: off" if commodity_id.is_empty() else "Prices: %s" % GameData.commodity(commodity_id).get("name", commodity_id)


func _open_price_menu() -> void:
	var rect := _price_button.get_global_rect()
	_price_menu.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y + 4)), Vector2i(int(rect.size.x), 0)))


func _choose_price(commodity_id: String) -> void:
	_price_menu.hide()
	_map.price_commodity = commodity_id
	_price_button.text = _price_text(commodity_id) + "  ▾"
	_price_button.icon = null if commodity_id.is_empty() else _swatch(_line_color(commodity_id))
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		if commodity_id.is_empty():
			_price_button.remove_theme_color_override(color_name)
		else:
			_price_button.add_theme_color_override(color_name, _line_color(commodity_id))


## The color of the ship line that carries a commodity (see GameData.category_color()).
static func _line_color(commodity_id: String) -> Color:
	for model: Dictionary in GameData.ship_models:
		if not model.get("recovery", false) and model.get("cargo", []).has(commodity_id):
			return GameData.category_color(model.get("category", ""), LINE_MIN_LUMINANCE)
	return Color.WHITE


## A small square of solid color, for the price picker's items.
static func _swatch(color: Color) -> ImageTexture:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## The main map: ports, ships, canal locks, storms and sea animals, with their
## popups, the page buttons down its top left (Markets, Hubs, Farms, Makers:
## GameRoot.open_page()), and the price picker in the top right (a ship line's prices over the
## ports), with Open a division (CompanyTypeDialog) over it while there's a
## company type the company hasn't bought into (see _add_division_button()). The Routes and Tutorial switches are on
## the Settings page (Esc menu: see SettingsPage); the map follows them.

const ZOOM_BUTTON_SIZE := Vector2(44, 44)
const ZOOM_BUTTON_MARGIN := 14
const FIELD_GUIDE_BUTTON := 44.0
## Ship line colors are brightened to at least this luminance so they read on
## the dark panel.
const LINE_MIN_LUMINANCE := 0.5
## The price picker's ship lines: [name, ship_models.json category].
const PRICE_LINES := [["Container ships", "container"], ["Ore carriers", "ore"], ["Breakbulk carriers", "breakbulk"], ["Grain carriers", "grain"],
	["Livestock carriers", "livestock"], ["Fresh produce carriers", "produce"], ["Tankers", "tanker"], ["Gas carriers", "gas"], ["Car carriers", "vehicles"], ["Boat carriers", "boat_carriers"], ["Seafood carriers", "seafood"]]
## The box (px) a seafood family's picture is fitted in, in the price picker
## (see _catch_icon()); and the family whose picture marks the seafood line.
const CATCH_ICON_SIZE := Vector2i(30, 18)
const SEAFOOD_LINE_ICON := "tuna"

static var _catch_icons := {}  # Commodity id -> its picture (or null): see _catch_icon().

@onready var _map: MapView = $MapView
var _price_button := Button.new()
var _price_menu := PopupPanel.new()
## Buying into another company type (CompanyTypeDialog): shown while one is left.
var _type_button := Button.new()


func _ready() -> void:
	_map.show_ships = true
	_map.show_active_lanes = GameState.show_active_routes
	_map.port_clicked.connect(_open_port_popup)
	_map.ship_clicked.connect(open_ship_popup)
	_map.lock_clicked.connect(_open_lock_popup)
	_map.canal_clicked.connect(_open_convoy_popup)
	_map.storm_clicked.connect(_open_storm_popup)
	_map.pod_clicked.connect(_open_pod_popup)
	_map.birds_clicked.connect(_open_birds_popup)
	_map.animals_clicked.connect(_open_animals_popup)
	_map.industry_clicked.connect(_open_industry_popup)
	_map.plant_clicked.connect(_open_plant_popup)
	_map.city_clicked.connect(_open_city_popup)
	_map.field_clicked.connect(func(field_id: String) -> void:
		PopupHost.find(self).close()
		GameRoot.find(self).show_energy("field:" + field_id))  # (A field's rigs: the Energy page.)
	_map.site_clicked.connect(func(site_id: String) -> void:
		PopupHost.find(self).close()
		GameRoot.find(self).show_research_site(site_id))  # (A research site: its card on the Research page.)
	_map.wonder_clicked.connect(_open_wonder_popup)
	_map.gem_clicked.connect(func(gem_id: String, lon_lat: Vector2) -> void:
		_open_gem_popup(gem_id, _map.lon_lat_screen_position.bind(lon_lat)))
	_map.home_clicked.connect(_open_home_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())
	Settings.changed.connect(func() -> void: _map.show_active_lanes = GameState.show_active_routes)  # (Routes, on the Settings page.)
	_add_price_picker()
	_add_factories_switch()
	_add_research_switch()
	_add_division_button()
	_add_zoom_buttons()
	_add_side_buttons()
	_add_field_guide_button()
	_add_achievements_button()
	_add_ratings_button()
	if GameState.divine.on:
		_add_divine_button()
	_map.divine_target.connect(_on_divine_target)
	_add_page_buttons()
	_add_ticker()
	_add_ceo_button()
	if _map.ambience != null:  # The bird that's calling, top left (see SoundTracker), beside the page buttons.
		var tracker := SoundTracker.new(_map)
		add_child(tracker)
		tracker.offset_left = _page_column.offset_left + FIELD_GUIDE_BUTTON + 12.0
		_map.ambience.call_started.connect(tracker.show_call)


func _process(_delta: float) -> void:
	_step_ticker(_delta)
	var t_x := Time.get_ticks_usec()
	_process_timed(_delta)
	MapView._prof("proc.world_screen", t_x)

func _process_timed(_delta: float) -> void:
	_type_button.visible = GameState.company.company_types.size() < Progression.company_types().size()


func _unhandled_input(event: InputEvent) -> void:
	if not _map.choosing_divine.is_empty() and event.is_action_pressed(&"ui_cancel"):
		_stop_divine()
		get_viewport().set_input_as_handled()
		return


## The Industry switch in the map panel (Vehicles and Cargo & Ore companies:
## on to start with): the makers' factories and the Cargo & Ore mines, camps,
## plants and factories marked by their ports (MapView.show_factories).
func _add_factories_switch() -> void:
	var shown := func() -> bool: return Manufacturers.can_deal(GameState.company) or Industry.can_build(GameState.company)
	var switch := CheckButton.new()
	switch.text = "Industry"
	switch.tooltip_text = "Mark the mines, logging camps, plants and factories by their ports: the vehicle and boat makers' own, and companies' (outlined in the company's colour)."
	switch.button_pressed = shown.call()
	_map.show_factories = switch.button_pressed
	switch.toggled.connect(func(on: bool) -> void: _map.show_factories = on)
	switch.visible = shown.call()
	GameState.company_types_changed.connect(func() -> void: switch.visible = shown.call())
	var redraw := func() -> void:
		if _map.show_factories:
			_map.show_factories = true  # (Drawn again: a factory or site built or closed.)
	GameState.makers_changed.connect(redraw)
	GameState.industry_changed.connect(redraw)
	%MapControls.add_child(switch)


## Turns the map to a place (lon, lat) (GameRoot.show_on_map()).
func look_at_lon_lat(lon_lat: Vector2) -> void:
	_map.look_at_lon_lat(lon_lat)


## The Research switch in the map panel (Research companies: on to start
## with): the sites under the sea it knows of, and the search areas of the
## hidden ones (MapView.show_research).
func _add_research_switch() -> void:
	var shown := func() -> bool: return Research.can_research(GameState.company)
	var switch := CheckButton.new()
	switch.text = "Research"
	switch.tooltip_text = "Mark the research sites under the sea: the ones you know of (ticked once done) and the search areas where hidden ones may lie."
	switch.button_pressed = shown.call()
	_map.show_research = switch.button_pressed
	switch.toggled.connect(func(on: bool) -> void: _map.show_research = on)
	switch.visible = Research.can_research(GameState.company)
	GameState.company_types_changed.connect(func() -> void:
		switch.visible = Research.can_research(GameState.company)
		if shown.call() and not switch.button_pressed:
			switch.button_pressed = true)
	GameState.research.changed.connect(func() -> void:
		if _map.show_research:
			_map.show_research = true)  # (Drawn again: a site found or done.)
	%MapControls.add_child(switch)

## The Open a division button (first in the map panel).
func _add_division_button() -> void:
	_type_button.text = "Open a division"
	_type_button.tooltip_text = "Buy into another company type (%s): all its ships can be bought from then on." % Fmt.money(GameState.division_price())
	_type_button.visible = false
	_type_button.pressed.connect(func() -> void: CompanyTypeDialog.open(self))
	%MapControls.add_child(_type_button)
	%MapControls.move_child(_type_button, 0)


## The port's popup; while it's open the price boxes (if shown) are worked out
## from there: what each commodity would make carried from it to each port.
func _open_port_popup(port_id: String) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.port_screen_position(port_id)
	var popup := PopupHost.find(self).show_port(port_id, follow)
	_map.price_origin = port_id
	popup.tree_exiting.connect(func() -> void:
		if _map.price_origin == port_id and not _port_popup_open(port_id):
			_map.price_origin = "")


## Whether a popup for this port is open (another may have replaced the one closing).
func _port_popup_open(port_id: String) -> bool:
	var current: Variant = PopupHost.find(self).current
	return current is PortPopup and is_instance_valid(current) and not current.is_queued_for_deletion() and current.port_id == port_id


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
	if ship.is_ghost():  # One of the other firms' ships (the ambient traffic): its card.
		var card := TrafficPopup.new()
		card.ship = ship
		card.follow = follow
		PopupHost.find(self).open(card)
		return
	PopupHost.find(self).show_ship(ship, follow)


## "Prices: Grain carriers ▾" at the map's top right: puts a
## box over the ports with each of that ship line's commodities and its price
## there, or, while a port's popup is open, what it would make carried from
## that port (see MapView.price_line); or, picked from its second column,
## colors the ports by one commodity's price, green where cheap to red where
## expensive (MapView.price_commodity); or "Prices: off". Its menu has a swatch
## of each line's color (a fish or crab for the seafood), and the chosen line's (or commodity's) name is shown in that color.
func _add_price_picker() -> void:
	_price_button.tooltip_text = "Show a ship line's prices over the ports: blue where its cargo is cheap, orange where it's expensive.\nClick a port to see instead what each would make carried from there.\nOr color the ports by one commodity's price: green where it's cheap, red where it's expensive."
	_price_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_price_button.pressed.connect(_open_price_menu)
	%MapControls.add_child(_price_button)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override(&"separation", 18)
	_price_menu.add_child(columns)
	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 0)
	columns.add_child(list)
	list.add_child(_price_heading("Price boxes"))
	list.add_child(_price_item(""))
	for line: Array in PRICE_LINES:
		list.add_child(_price_item(line[1]))
	# Coloring the ports by one commodity's price: green where cheap, red where expensive.
	var colors := VBoxContainer.new()
	colors.add_theme_constant_override(&"separation", 0)
	columns.add_child(colors)
	colors.add_child(_price_heading("Port colors: green cheap, red expensive"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override(&"h_separation", 4)
	grid.add_theme_constant_override(&"v_separation", 0)
	colors.add_child(grid)
	for line: Array in PRICE_LINES:
		for commodity: Dictionary in GameData.commodities:
			if _line_of(commodity.id) == line[1]:
				grid.add_child(_color_item(commodity.id, line[1]))
	_price_menu.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"MapPopup"))
	add_child(_price_menu)
	_choose_price("")


## One entry in the price menu: "Prices: Grain carriers" with the line's
## swatch, and its cargo in the tooltip.
func _price_item(category: String) -> Button:
	var item := Button.new()
	item.flat = true
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.text = _price_text(category)
	if not category.is_empty():
		item.icon = _line_icon(category)
		var names := PackedStringArray()
		for commodity: Dictionary in GameData.commodities:
			for model: Dictionary in GameData.ship_models:
				if model.get("category", "") == category and model.get("cargo", []).has(commodity.id):
					names.append(commodity.name)
					break
		item.tooltip_text = ", ".join(names)
	item.pressed.connect(_choose_price.bind(category))
	return item


## A heading over one of the price menu's columns.
func _price_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"DimLabel"
	return label


## One entry in the price menu's port colors: a commodity, with its line's
## swatch, or its picture if it's seafood (see _commodity_icon()).
func _color_item(commodity_id: String, _category: String) -> Button:
	var item := Button.new()
	item.flat = true
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.text = str(GameData.commodity(commodity_id).get("name", commodity_id))
	item.icon = _commodity_icon(commodity_id)
	item.tooltip_text = "Color the ports by its price: green where it's cheap, white about its world average, red where it's expensive (full color at 1.4 times cheaper or more expensive)."
	item.pressed.connect(_choose_commodity.bind(commodity_id))
	return item


## The ship line (category) that carries a commodity, as the menu lists them; "" for none.
static func _line_of(commodity_id: String) -> String:
	for model: Dictionary in GameData.ship_models:
		if not model.get("recovery", false) and model.get("cargo", []).has(commodity_id):
			return str(model.get("category", ""))
	return ""


## A commodity picked in the price menu: the ports colored by its price, the boxes off.
func _choose_commodity(commodity_id: String) -> void:
	_choose_price("")
	_map.price_commodity = commodity_id
	var color := GameData.category_color(_line_of(commodity_id), LINE_MIN_LUMINANCE)
	_price_button.text = "Prices: %s  ▾" % GameData.commodity(commodity_id).get("name", commodity_id)
	_price_button.icon = _commodity_icon(commodity_id)
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		_price_button.add_theme_color_override(color_name, color)


func _price_text(category: String) -> String:
	for line: Array in PRICE_LINES:
		if line[1] == category:
			return "Prices: %s" % line[0]
	return "Prices: off"


func _open_price_menu() -> void:
	var rect := _price_button.get_global_rect()
	# (Wider than the button: lined up with its right edge, so it stays on screen.)
	var width := maxf(_price_menu.get_contents_minimum_size().x, rect.size.x)
	_price_menu.popup(Rect2i(Vector2i(Vector2(rect.end.x - width, rect.position.y + rect.size.y + 4)), Vector2i(int(width), 0)))


func _choose_price(category: String) -> void:
	_price_menu.hide()
	_map.price_line = category
	_map.price_commodity = ""
	_price_button.text = _price_text(category) + "  ▾"
	_price_button.icon = null if category.is_empty() else _line_icon(category)
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		if category.is_empty():
			_price_button.remove_theme_color_override(color_name)
		else:
			_price_button.add_theme_color_override(color_name, GameData.category_color(category, LINE_MIN_LUMINANCE))


## A small square of solid color, for the price picker's items.
static func _swatch(color: Color) -> ImageTexture:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)



## A ship line's mark in the price picker: its swatch, or the seafood line's
## picture (SEAFOOD_LINE_ICON).
static func _line_icon(category: String) -> Texture2D:
	var icon := _catch_icon(SEAFOOD_LINE_ICON) if category == "seafood" else null
	return icon if icon != null else _swatch(GameData.category_color(category, LINE_MIN_LUMINANCE))

## A commodity's mark in the price picker: a seafood family's picture (see
## _catch_icon()), else its line's swatch.
static func _commodity_icon(commodity_id: String) -> Texture2D:
	var icon := _catch_icon(commodity_id)
	return icon if icon != null else _swatch(GameData.category_color(_line_of(commodity_id), LINE_MIN_LUMINANCE))


## A seafood family's picture (Fisheries.family_art()) fitted in the middle of
## CATCH_ICON_SIZE, all the same size so the names beside them line up; null
## if it isn't seafood. Made once each.
static func _catch_icon(commodity_id: String) -> Texture2D:
	if _catch_icons.has(commodity_id):
		return _catch_icons[commodity_id]
	var icon: ImageTexture = null
	var art := Fisheries.shared().family_art(commodity_id)
	if art != null:
		var picture := art.get_image()
		picture.decompress()
		picture.convert(Image.FORMAT_RGBA8)
		var box := Vector2(CATCH_ICON_SIZE)
		var fit := minf(box.x / picture.get_width(), box.y / picture.get_height())
		var side := Vector2i((Vector2(picture.get_size()) * fit).round())
		picture.resize(maxi(side.x, 1), maxi(side.y, 1), Image.INTERPOLATE_LANCZOS)
		var image := Image.create(CATCH_ICON_SIZE.x, CATCH_ICON_SIZE.y, false, Image.FORMAT_RGBA8)
		image.blit_rect(picture, Rect2i(Vector2i.ZERO, picture.get_size()), (CATCH_ICON_SIZE - picture.get_size()) / 2)
		icon = ImageTexture.create_from_image(image)
	_catch_icons[commodity_id] = icon
	return icon


## + and - buttons at the map's bottom right, for zooming without a wheel or
## trackpad gestures (see also MapView's + and - keys).
func _add_zoom_buttons() -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 4)
	column.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, ZOOM_BUTTON_MARGIN)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	for entry: Array in [["+", "Zoom in (or pinch, or the + key)", MapView.ZOOM_STEP * MapView.ZOOM_STEP], ["−", "Zoom out (or pinch, or the - key)", 1.0 / (MapView.ZOOM_STEP * MapView.ZOOM_STEP)]]:
		var button := Button.new()
		button.text = entry[0]
		button.tooltip_text = entry[1]
		button.custom_minimum_size = ZOOM_BUTTON_SIZE
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override(&"font_size", 24)
		var factor: float = entry[2]
		button.pressed.connect(func() -> void: _map.zoom_by(factor))
		column.add_child(button)
	add_child(column)


## A flock of birds clicked: what birds are round what it's round, following it.
## A land animal group's popup, following its patch on the map.
func _open_animals_popup(key: String, kind: String) -> void:
	var popup := LandLifePopup.new()
	popup.key = key
	popup.kind = kind
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := _map.animal_group_screen_position(key)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)


func _open_birds_popup(about: Dictionary, _flock: Dictionary) -> void:
	var popup := BirdsPopup.new()
	popup.about = about
	popup.map = _map  # (Its Follow buttons follow a bird on it.)
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := Vector2.INF
		if about.has("port"):
			at = _map.port_screen_position(about.port)
		elif about.has("ship"):
			at = _map.ship_screen_position(about.ship)
		elif about.has("pod"):
			at = _map.pod_screen_position(int(about.pod))
		elif about.has("colony"):
			at = _map.colony_screen_position(int(about.colony))
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)


## The field guide, achievements and Divine Actions buttons: a column down the
## right side under the Routes panel, moved down as the panel grows (its
## tutorial row, the division button).
var _side_buttons := VBoxContainer.new()


func _add_side_buttons() -> void:
	_side_buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_side_buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_side_buttons.offset_right = $RoutesPanel.offset_right
	_side_buttons.offset_left = _side_buttons.offset_right - FIELD_GUIDE_BUTTON
	_side_buttons.add_theme_constant_override(&"separation", 8)
	add_child(_side_buttons)
	$RoutesPanel.resized.connect(_place_side_buttons)
	_place_side_buttons()


func _place_side_buttons() -> void:
	_side_buttons.offset_top = $RoutesPanel.offset_top + $RoutesPanel.size.y + 10.0

## The page buttons down the map's top left, each opening its page over the
## map (GameRoot.open_page()): Markets, Hubs, and for the company types that
## have them Farms (Agriculture), Makers (Vehicles) and Energy (Tankers). By id ("markets"...),
## for GameRoot's alert dot on Hubs.
var page_buttons := {}
var _page_column := VBoxContainer.new()
const PAGES := [["markets", "Intelligence: the countries, the companies, the markets and their history, and the news"], ["contracts", "Contracts: the producers' offers, the contracts you've signed and your standing with them"], ["people", "People: your executives, department heads, officers and the job market"], ["ownership", "Ownership: the shares, the board, the firms you hold and going public"], ["hubs", "Hubs: your HQ and hubs, their upgrades and warehouses"],
	["farms", "Farms: your plots at the farm ports and the farm store"], ["makers", "Makers: the car and boat makers, how much they like you, and your factories"],
	["energy", "Energy: the oil and gas fields, your rigs and platforms, and your refineries"], ["industry", "Industry: your mines, plants and factories, and the claims at the resource ports"],
	["research", "Research: the contracts board, your expeditions, the Atlas of the sites under the sea, and your ships' gear"]]


func _add_page_buttons() -> void:
	_page_column.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_page_column.offset_left = 12.0
	_page_column.offset_top = 12.0
	_page_column.add_theme_constant_override(&"separation", 8)
	add_child(_page_column)
	for entry: Array in PAGES:
		var id: String = entry[0]
		var button := Button.new()
		button.tooltip_text = entry[1]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2.ONE * FIELD_GUIDE_BUTTON
		var icon := PageIcon.new(id)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
		button.add_child(icon)
		button.pressed.connect(func() -> void:
			PopupHost.find(self).close()
			GameRoot.find(self).open_page(id))
		_page_column.add_child(button)
		page_buttons[id] = button
	_update_page_buttons()
	GameState.company_types_changed.connect(_update_page_buttons)


## The CEO's round headshot at the top of the page buttons: opens their card (CeoPopup).
const CEO_BUTTON := 56.0
var _ceo_button := Button.new()
var _ceo_portrait := Portrait.new(GameState.company.ceo if GameState.company else {}, true)


func _add_ceo_button() -> void:
	_ceo_button.flat = true
	_ceo_button.focus_mode = Control.FOCUS_NONE
	_ceo_button.custom_minimum_size = Vector2.ONE * CEO_BUTTON
	_ceo_button.tooltip_text = "Your CEO: traits, skills and the story so far."
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(0.09, 0.14, 0.26, 0.95)
	ring.set_corner_radius_all(int(CEO_BUTTON / 2.0))
	ring.border_color = Color(0.89, 0.71, 0.24)
	ring.set_border_width_all(2)
	for state: StringName in [&"normal", &"hover", &"pressed", &"focus"]:
		_ceo_button.add_theme_stylebox_override(state, ring)
	_ceo_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 4)
	_ceo_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ceo_button.add_child(_ceo_portrait)
	_ceo_button.pressed.connect(func() -> void:
		var popup := CeoPopup.new()
		var at := _ceo_button.get_global_rect()
		popup.follow = func() -> Vector2: return Vector2(at.end.x + 10.0, at.position.y + at.size.y / 2.0)
		popup.gap = 0.0
		PopupHost.find(self).open(popup))
	_page_column.add_child(_ceo_button)
	_page_column.move_child(_ceo_button, 0)
	GameState.logo_changed.connect(func() -> void: _ceo_portrait.character = GameState.company.ceo)

## The news ticker along the bottom of the map: the latest headlines (News)
## sliding by, each a click from the Intelligence page's News tab.
const TICKER_HEIGHT := 24.0
const TICKER_SPEED := 60.0
const TICKER_SHOWN := 8
var _ticker := PanelContainer.new()
var _ticker_text := Label.new()
var _ticker_x := 0.0


func _add_ticker() -> void:
	_ticker.theme_type_variation = &"BarPanel"
	_ticker.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_ticker.offset_top = -TICKER_HEIGHT
	_ticker.offset_bottom = 0.0
	_ticker.clip_contents = true
	_ticker.mouse_filter = Control.MOUSE_FILTER_STOP
	_ticker.tooltip_text = "The news. Click for the Intelligence page."
	_ticker.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			GameRoot.find(self).show_intelligence("news"))
	_ticker_text.add_theme_font_size_override(&"font_size", 13)
	_ticker_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ticker_text.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var paper := Button.new()
	paper.text = "Gazette"
	paper.flat = true
	paper.focus_mode = Control.FOCUS_NONE
	paper.tooltip_text = "Read this week's Maritime Gazette."
	paper.add_theme_font_size_override(&"font_size", 13)
	paper.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	paper.pressed.connect(func() -> void: GameRoot.find(self).open_gazette())
	_ticker.add_child(_ticker_text)
	_ticker.add_child(paper)
	add_child(_ticker)
	GameState.news.added.connect(func(_item: Dictionary) -> void: _refresh_ticker())
	_refresh_ticker()


func _refresh_ticker() -> void:
	var parts := PackedStringArray()
	for item: Dictionary in GameState.news.latest(TICKER_SHOWN):
		parts.append(str(item.text))
	_ticker.visible = not parts.is_empty()
	_ticker_text.text = "   ✦   ".join(parts) + "   ✦   "


func _step_ticker(delta: float) -> void:
	if not _ticker.visible or _ticker_text.text.is_empty():
		return
	_ticker_x -= TICKER_SPEED * delta
	var width := _ticker_text.size.x
	if width <= _ticker.size.x:
		_ticker_x = 0.0
	elif _ticker_x < -width:
		_ticker_x = _ticker.size.x
	_ticker_text.position.x = _ticker_x

## Farms, Makers and Energy show only for the types that have them.
func _update_page_buttons() -> void:
	page_buttons.farms.visible = Farms.can_farm(GameState.company)
	page_buttons.makers.visible = Manufacturers.can_deal(GameState.company)
	page_buttons.energy.visible = Energy.can_drill(GameState.company)
	page_buttons.industry.visible = Industry.can_build(GameState.company)
	page_buttons.research.visible = Research.can_research(GameState.company)


## The field guide's square paw button at the map's top right, first in the
## column under the Routes panel (see FieldGuide).
func _add_field_guide_button() -> void:
	var button := Button.new()
	button.tooltip_text = "Field guide: every bird, sea animal and land animal in the game"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2.ONE * FIELD_GUIDE_BUTTON
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var paw := PawIcon.new()
	paw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 5)
	button.add_child(paw)
	button.pressed.connect(func() -> void:
		PopupHost.find(self).close()
		add_child(FieldGuide.new()))
	_side_buttons.add_child(button)


## The achievements' trophy button, under the field guide's (see
## AchievementsPage), and newly earned ones looked for every
## Achievements.CHECK_S and told in the activity log.
func _add_achievements_button() -> void:
	var button := Button.new()
	button.tooltip_text = "Achievements"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2.ONE * FIELD_GUIDE_BUTTON
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var trophy := TrophyIcon.new()
	trophy.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
	button.add_child(trophy)
	button.pressed.connect(func() -> void:
		PopupHost.find(self).close()
		add_child(AchievementsPage.new()))
	_side_buttons.add_child(button)
	var timer := Timer.new()
	timer.wait_time = Achievements.CHECK_S
	timer.autostart = true
	timer.timeout.connect(_check_achievements)
	add_child(timer)


## The company's star ratings (RatingsPage): a star button under the trophy.
func _add_ratings_button() -> void:
	var button := Button.new()
	button.tooltip_text = "Company ratings"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2.ONE * FIELD_GUIDE_BUTTON
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var star := StarRating.new(1.0, FIELD_GUIDE_BUTTON - 14.0, 1)
	star.custom_minimum_size = Vector2.ONE * (FIELD_GUIDE_BUTTON - 14.0)
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	button.add_child(star)
	button.pressed.connect(func() -> void:
		PopupHost.find(self).close()
		add_child(RatingsPage.new()))
	_side_buttons.add_child(button)


## Divine Actions (Divine): the bolt button under the trophy (in the side column) opens the panel;
## a power with a target has the map pick it (choosing_divine), with a hint
## at the top saying what to click, then it's done (GameState.divine_act()).
var _divine_hint := Label.new()


func _add_divine_button() -> void:
	var button := Button.new()
	button.tooltip_text = "Divine Actions"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2.ONE * FIELD_GUIDE_BUTTON
	button.size_flags_horizontal = Control.SIZE_SHRINK_END
	var bolt := DivinePanel.BoltIcon.new()
	bolt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	button.add_child(bolt)
	button.pressed.connect(func() -> void:
		PopupHost.find(self).close()
		_stop_divine()
		var panel := DivinePanel.new()
		panel.pick.connect(_start_divine)
		add_child(panel))
	_side_buttons.add_child(button)
	_divine_hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_divine_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_divine_hint.offset_top = 12.0
	_divine_hint.theme_type_variation = &"HeaderLabel"
	_divine_hint.add_theme_color_override(&"font_color", MapView.DIVINE_GOLD)
	_divine_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_divine_hint.visible = false
	_divine_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_divine_hint)


func _start_divine(power: String) -> void:
	var target := str(Divine.POWERS[power].target)
	if target == "none":
		GameState.divine_act(power, null)
		return
	_map.choosing_divine = power
	_divine_hint.text = "%s: click %s on the map  (Esc to cancel)" % [Divine.POWERS[power].name,
		{point = "a point at sea", port = "a port", ship = "a rival's ship at sea"}[target]]
	_divine_hint.visible = true


func _stop_divine() -> void:
	_map.choosing_divine = ""
	_divine_hint.visible = false


func _on_divine_target(target: Variant) -> void:
	var power: String = _map.choosing_divine
	if power.is_empty():
		return
	if target == null or (target is String and (target as String).is_empty()):
		return  # Nothing there: keep choosing.
	if target is Ship:
		target = (target as Ship).id
	_stop_divine()
	GameState.divine_act(power, target)


## Whether the achievements have been checked once this session (see _check_achievements()).
var _achievements_primed := false


func _check_achievements() -> void:
	if not GameState.in_session:
		return
	# A save from before the achievements (or a reloaded one) earns everything it
	# already had in one go on its first check: logged, but no cards for those.
	var primed := _achievements_primed
	_achievements_primed = true
	if not primed:
		SteamAchievements.sync_company(GameState.company)  # (Everything the company had: set on Steam.)
	var news_list := Achievements.check(GameState.company)
	for news: Dictionary in news_list:
		SteamAchievements.earned_ingame(str(news.id), int(news.stars))
	news_list.append_array(SteamAchievements.check(GameState.company))  # (This player's own, across games: see SteamAchievements.)
	for news: Dictionary in news_list:
		var stars := int(news.stars)
		var text := "Achievement: %s" % news.name if stars == 0 \
			else "Achievement: %s %s (%d of 3 stars)" % [news.name, "★".repeat(stars), stars]
		ActivityLog.add(text, ActivityLog.Kind.GOOD, AchievementsPage.GOLD)
		var unit := ""
		for line: Dictionary in Achievements.lines():
			if line.id == news.id:
				unit = str(line.unit)
		var root := GameRoot.find(self)
		if root != null and primed:
			root.event_card.show_achievement(str(news.name), stars, unit)


## A hub's industry, from clicking one of its plots on the map (see IndustryPopup).
func _open_industry_popup(port_id: String, slot: int) -> void:
	var hub := GameState.hub_at(port_id)
	if hub == null:
		return
	var popup := IndustryPopup.new()
	popup.hub = hub
	popup.slot = slot
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := _map.port_screen_position(port_id)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)


## A wonder of the world clicked on the map: its popup, following it.
func _open_wonder_popup(id: String) -> void:
	for gem_id: String in GameState.HIDDEN_GEMS:  # A hidden gem in its picture: that first, then the wonder.
		if str(GameState.HIDDEN_GEMS[gem_id].get("wonder", "")) == id and not GameState.hidden_gem_found(gem_id):
			_open_gem_popup(gem_id, func() -> Vector2: return _map.wonder_screen_position(id), _show_wonder_popup.bind(id))
			return
	_show_wonder_popup(id)


func _show_wonder_popup(id: String) -> void:
	var popup := WonderPopup.new()
	popup.id = id
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := _map.wonder_screen_position(id)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)


## A hidden gem found on the map (GameState.HIDDEN_GEMS): its popup, following
## where it is on screen (where), then claimed() once it's claimed.
func _open_gem_popup(gem_id: String, where: Callable, claimed := Callable()) -> void:
	var popup := GemPopup.new()
	popup.gem_id = gem_id
	popup.claimed = claimed
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at: Vector2 = where.call()
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)


## A home of the wildlife clicked on the map: its popup, following it.
## One of the other producers' plants on a port's estate: its card, following the port.
func _open_plant_popup(port_id: String, plant: int) -> void:
	var popup := PlantPopup.new()
	popup.plant = plant
	var last := [Vector2.ZERO]
	popup.follow = func() -> Vector2:
		var at := _map.port_screen_position(port_id)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)


## An inland city: its card, following it.
func _open_city_popup(city_id: String) -> void:
	var popup := CityPopup.new()
	popup.city_id = city_id
	popup.map = _map
	var last := [Vector2.ZERO]
	popup.follow = func() -> Vector2:
		var at := _map.city_screen_position(city_id)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)

func _open_home_popup(kind: String, index: int) -> void:
	var popup := HomePopup.new()
	popup.kind = kind
	popup.index = index
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := _map.home_screen_position(kind, index)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)

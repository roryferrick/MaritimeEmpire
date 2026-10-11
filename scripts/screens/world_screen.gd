# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## The main map: ports, ships, canal locks, storms and sea animals, with their popups, and the Routes switch,
## Tutorial switch (in saves with the tutorial) and price picker in one panel in
## the top right (the fleet's route lanes shown faintly; the tutorial's tips;
## a ship line's prices over the ports), with an Unlock a region button over
## them while a market region can be unlocked (see _add_region_choice()).

const ZOOM_BUTTON_SIZE := Vector2(44, 44)
const ZOOM_BUTTON_MARGIN := 14
const FIELD_GUIDE_BUTTON := 44.0
## Ship line colors are brightened to at least this luminance so they read on
## the dark panel.
const LINE_MIN_LUMINANCE := 0.5
## The price picker's ship lines: [name, ship_models.json category].
const PRICE_LINES := [["Container ships", "container"], ["Ore carriers", "ore"], ["Grain carriers", "grain"],
	["Livestock carriers", "livestock"], ["Tankers", "tanker"], ["Vehicle carriers", "vehicles"], ["Seafood carriers", "seafood"]]

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
	_map.birds_clicked.connect(_open_birds_popup)
	_map.animals_clicked.connect(_open_animals_popup)
	_map.industry_clicked.connect(_open_industry_popup)
	_map.wonder_clicked.connect(_open_wonder_popup)
	_map.home_clicked.connect(_open_home_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())
	%RoutesToggle.set_pressed_no_signal(GameState.show_active_routes)
	%RoutesToggle.toggled.connect(_on_routes_toggled)
	if GameState.tutorials:
		_add_tutorial_toggle()
	_add_price_picker()
	_add_region_choice()
	_add_zoom_buttons()
	_add_side_buttons()
	_add_field_guide_button()
	_add_achievements_button()
	if GameState.divine.on:
		_add_divine_button()
	_map.divine_target.connect(_on_divine_target)
	if _map.ambience != null:  # The bird that's calling, top left (see SoundTracker).
		var tracker := SoundTracker.new(_map)
		add_child(tracker)
		_map.ambience.call_started.connect(tracker.show_call)


func _process(_delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(_delta)
	MapView._prof("proc.world_screen", t_x)

func _process_timed(_delta: float) -> void:
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
	if not _map.choosing_divine.is_empty() and event.is_action_pressed(&"ui_cancel"):
		_stop_divine()
		get_viewport().set_input_as_handled()
		return
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
	PopupHost.find(self).show_ship(ship, follow)


## "Prices: Grain carriers ▾" under the Routes switch, in the same panel: puts a
## box over the ports with each of that ship line's commodities and its price
## there, or, while a port's popup is open, what it would make carried from
## that port (see MapView.price_line); or "Prices: off". Its menu has a swatch
## of each line's color, and the chosen line's name is shown in that color.
func _add_price_picker() -> void:
	_price_button.tooltip_text = "Show a ship line's prices over the ports: blue where its cargo is cheap, orange where it's dear.\nClick a port to see instead what each would make carried from there."
	_price_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_price_button.pressed.connect(_open_price_menu)
	%MapControls.add_child(_price_button)

	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 0)
	_price_menu.add_child(list)
	list.add_child(_price_item(""))
	for line: Array in PRICE_LINES:
		list.add_child(_price_item(line[1]))
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
		item.icon = _swatch(GameData.category_color(category, LINE_MIN_LUMINANCE))
		var names := PackedStringArray()
		for commodity: Dictionary in GameData.commodities:
			for model: Dictionary in GameData.ship_models:
				if model.get("category", "") == category and model.get("cargo", []).has(commodity.id):
					names.append(commodity.name)
					break
		item.tooltip_text = ", ".join(names)
	item.pressed.connect(_choose_price.bind(category))
	return item


func _price_text(category: String) -> String:
	for line: Array in PRICE_LINES:
		if line[1] == category:
			return "Prices: %s" % line[0]
	return "Prices: off"


func _open_price_menu() -> void:
	var rect := _price_button.get_global_rect()
	_price_menu.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y + 4)), Vector2i(int(rect.size.x), 0)))


func _choose_price(category: String) -> void:
	_price_menu.hide()
	_map.price_line = category
	_price_button.text = _price_text(category) + "  ▾"
	_price_button.icon = null if category.is_empty() else _swatch(GameData.category_color(category, LINE_MIN_LUMINANCE))
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
## tutorial row, the region button).
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
	for news: Dictionary in Achievements.check(GameState.company):
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
	var popup := WonderPopup.new()
	popup.id = id
	var last := [Vector2.ZERO]  # Where it last was (lambdas capture by value: kept in an array).
	popup.follow = func() -> Vector2:
		var at := _map.wonder_screen_position(id)
		if at != Vector2.INF:
			last[0] = _map.get_global_transform() * at
		return last[0]
	PopupHost.find(self).open(popup)


## A home of the wildlife clicked on the map: its popup, following it.
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

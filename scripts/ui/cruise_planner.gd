# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name CruisePlanner
extends Control
## A cruise ship's planner (its popup's Cruise planner button; see Cruises),
## every figure with what goes into it:
## - Itinerary: its home port (and a cruise terminal to build if it needs one),
##   its ports of call with their sights, the voyage's nights and miles, how
##   appealing it is and its season; Edit itinerary opens the route screen;
## - Prices: the package, each cabin class's price beside its recommendation
##   (with the recommendation's factors), the monthly adjustments beside their
##   recommendations, and the bookings outlook (the home port's would-be
##   cruisers, the ship's share, each class's ceiling at its price);
## - Departures: the rule (after days, at a fill, or both) and how booking is going;
## - Ship: service levels (any time), and in a refit (at the HQ or a hub) the
##   cabin shares, amenities and looks, with the refit's cost and days and the
##   guest experience it makes;
## - Reviews: its last voyages' money and reviews.
## Settings apply as they change (GameState.set_cruise_settings()); the refit
## on its button (GameState.refit_cruise()). Over the game, dimming it; Esc,
## X or a click outside closes it.

const PANEL_SIZE := Vector2(980, 720)

var ship: Ship
var _tabs := TabContainer.new()
var _refit := {}  # The refit being planned: {cabins, amenities, looks}.
var _note := Label.new()


func _init(for_ship: Ship) -> void:
	ship = for_ship


func _ready() -> void:
	GameState.cruises.ensure(ship)
	_refit = {cabins = (ship.cruise.cabins as Dictionary).duplicate(), amenities = (ship.cruise.amenities as Array).duplicate(), looks = (ship.cruise.looks as Dictionary).duplicate()}
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
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
	card.custom_minimum_size = Vector2(PANEL_SIZE.x, minf(PANEL_SIZE.y, get_viewport_rect().size.y - 60.0))
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	card.add_child(content)
	var header := HBoxContainer.new()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "%s · %s" % [ship.name, ship.model().get("name", "")]
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	_note.theme_type_variation = &"DimLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_note)
	_tabs.size_flags_vertical = SIZE_EXPAND_FILL
	content.add_child(_tabs)
	for name: String in ["Itinerary", "Prices", "Departures", "Ship", "Reviews"]:
		var scroll := ScrollContainer.new()
		scroll.name = name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var page := VBoxContainer.new()
		page.size_flags_horizontal = SIZE_EXPAND_FILL
		page.add_theme_constant_override(&"separation", 8)
		scroll.add_child(page)
		_tabs.add_child(scroll)
	_tabs.tab_changed.connect(func(_tab: int) -> void: _rebuild())
	GameState.ship_changed.connect(_on_ship_changed)
	_rebuild()


func _on_ship_changed(changed: Ship) -> void:
	if changed == ship and is_inside_tree():
		_note.text = ship.status_text()


func _page() -> VBoxContainer:
	return (_tabs.get_current_tab_control() as ScrollContainer).get_child(0)


func _rebuild() -> void:
	_note.text = ship.status_text()
	var page := _page()
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	match _tabs.current_tab:
		0: _itinerary(page)
		1: _prices(page)
		2: _departures(page)
		3: _ship(page)
		4: _reviews(page)


# --- Itinerary ----------------------------------------------------------------------

func _itinerary(page: VBoxContainer) -> void:
	var cruises: Cruises = GameState.cruises
	if ship.route.size() < 2:
		page.add_child(_text("No itinerary yet. Its first port is its home port (your HQ, a hub, or a port with your cruise terminal), where guests board; the rest are its ports of call, and it sails back home after the last."))
	else:
		var home := Cruises.home_of(ship)
		var ok := cruises.can_be_home(GameState.company, home)
		page.add_child(_heading("Home port: %s" % GameData.port_name(home)))
		if ok:
			page.add_child(_text("Guests board here. %s" % ("Your HQ or hub." if GameState.company.hub_at(home) != null else "Your cruise terminal.")))
		else:
			page.add_child(_text("%s has no cruise terminal of yours: build one to sail from here (or start the itinerary at your HQ or a hub)." % GameData.port_name(home)))
			var build := Button.new()
			build.text = "Build a cruise terminal: %s" % Fmt.money(cruises.terminal_cost(GameState.company))
			build.size_flags_horizontal = SIZE_SHRINK_BEGIN
			build.pressed.connect(func() -> void:
				var error := GameState.buy_terminal(home)
				_note.text = error if not error.is_empty() else "Terminal built at %s." % GameData.port_name(home)
				_rebuild())
			page.add_child(build)
		page.add_child(_heading("Ports of call"))
		for port_id: String in Cruises.stops_of(ship):
			var near := Cruises.attractions(port_id)
			var sights: Array = near.wonders
			page.add_child(_text("%s%s: %s" % [GameData.port_name(port_id), " (polar)" if near.polar else "",
				", ".join(sights) if not sights.is_empty() else "no famous sights nearby"]))
		var trip := cruises.trip(ship)
		var appeal := cruises.attraction(ship)
		page.add_child(_heading("The voyage"))
		page.add_child(_text("%d nights · %s nm round trip · %d ports of call" % [cruises.nights(ship), Fmt.thousands(roundi(float(trip.nm))), Cruises.stops_of(ship).size()]))
		page.add_child(_text("How appealing it is: %d%%. %d ports of call (up to 4 count), %d sights near them, %d market regions%s." % [
			roundi(float(appeal.value) * 100.0), appeal.stops, appeal.sights, appeal.regions, ", %d polar ports (Expedition guests prize them)" % appeal.polar if Cruises.is_expedition(ship) else ""]))
		var area := cruises.season_area(ship)
		if not area.is_empty():
			var months := PackedStringArray()
			for m in 12:
				months.append("%s %d%%" % [Fmt.month_name(m).left(3), roundi(Cruises.season_factor(area, m) * 100.0)])
			page.add_child(_text("Season: %s. Demand by month: %s." % [area.name, ", ".join(months)]))
	var edit := Button.new()
	edit.text = "Edit itinerary"
	edit.size_flags_horizontal = SIZE_SHRINK_BEGIN
	edit.tooltip_text = "Pick the ports in order on the route screen: the first is its home port."
	edit.pressed.connect(func() -> void:
		GameRoot.find(self).open_route_screen(ship)
		queue_free())
	page.add_child(edit)


# --- Prices ------------------------------------------------------------------------

func _prices(page: VBoxContainer) -> void:
	var cruises: Cruises = GameState.cruises
	var packages: Dictionary = Cruises.settings().get("packages", {})
	var package_row := HBoxContainer.new()
	package_row.add_theme_constant_override(&"separation", 10)
	package_row.add_child(_text("Package"))
	var pick := OptionButton.new()
	for id: String in packages:
		pick.add_item(str(packages[id].name))
		pick.set_item_metadata(pick.item_count - 1, id)
		if id == str(ship.cruise.package):
			pick.select(pick.item_count - 1)
	pick.item_selected.connect(func(index: int) -> void: _change({package = pick.get_item_metadata(index)}))
	package_row.add_child(pick)
	package_row.add_child(_text("Inclusive packages put what guests would spend onboard or ashore in the ticket (and the recommendation)."))
	page.add_child(package_row)
	page.add_child(_heading("Prices per guest for the voyage (this month's adjustment applied on top)"))
	var capacity := cruises.capacity(ship)
	var names: Dictionary = Cruises.settings().get("cabin_names", {})
	for cls: String in Cruises.CLASSES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var label := Label.new()
		label.text = "%s (%d berths)" % [names.get(cls, cls), int(capacity.get(cls, 0))]
		label.custom_minimum_size.x = 210
		row.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = 1000000
		spin.step = 5
		spin.prefix = "$"
		spin.custom_minimum_size.x = 140
		spin.value = float(ship.cruise.prices.get(cls, 0))
		spin.value_changed.connect(func(value: float) -> void: _change({prices = {cls: roundi(value)}}, false))
		row.add_child(spin)
		var recommended := cruises.recommend(ship, cls, -1, false)
		row.add_child(_text("Recommended %s (this month %s)" % [Fmt.money(int(recommended.price)), Fmt.money(int(cruises.recommend(ship, cls).price))]))
		page.add_child(row)
		page.add_child(_parts(recommended.parts))
	var use := Button.new()
	use.text = "Use the recommended prices"
	use.size_flags_horizontal = SIZE_SHRINK_BEGIN
	use.tooltip_text = "They follow the recommendations from then on (a new itinerary, the rating) till you set one."
	use.pressed.connect(func() -> void: _change({auto_prices = true}))
	page.add_child(use)
	page.add_child(_heading("Monthly adjustments (% on the prices; recommended under each, from the season)"))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override(&"h_separation", 10)
	var monthly: Array = ship.cruise.monthly
	for m in 12:
		var cell := VBoxContainer.new()
		var spin := SpinBox.new()
		spin.min_value = -50
		spin.max_value = 50
		spin.step = 5
		spin.suffix = "%"
		spin.custom_minimum_size.x = 110
		cell.add_child(_text(Fmt.month_name(m)))
		spin.value = float(monthly[m])
		spin.value_changed.connect(func(value: float) -> void:
			var changed: Array = (ship.cruise.monthly as Array).duplicate()
			changed[m] = roundi(value)
			_change({monthly = changed}, false))
		cell.add_child(spin)
		cell.add_child(_text("advised %+d%%" % cruises.recommended_monthly(ship, m)))
		grid.add_child(cell)
	page.add_child(grid)
	var use_monthly := Button.new()
	use_monthly.text = "Use the recommended monthly adjustments"
	use_monthly.size_flags_horizontal = SIZE_SHRINK_BEGIN
	use_monthly.pressed.connect(func() -> void: _change({auto_monthly = true}))
	page.add_child(use_monthly)
	page.add_child(_heading("Bookings outlook"))
	var outlook := cruises.demand(ship)
	page.add_child(_text("%s: about %s would-be cruisers a day this month (its size x its season: %s, %d%%), shared by berths with %d other cruise ship%s booking there: this ship's share %d%%, about %s guests a day." % [
		GameData.port_name(Cruises.home_of(ship)) if not Cruises.home_of(ship).is_empty() else "No home port",
		Fmt.thousands(roundi(float(outlook.pool))), str(outlook.area) if not str(outlook.area).is_empty() else "no", roundi(float(outlook.season) * 100.0),
		int(outlook.others), "" if int(outlook.others) == 1 else "s", roundi(float(outlook.share) * 100.0), Fmt.thousands(roundi(float(outlook.per_day)))]))
	for cls: String in Cruises.CLASSES:
		var entry: Dictionary = outlook.classes[cls]
		page.add_child(_text("%s: %s is %d%% of the recommended %s, so at most %d%% of its berths book" % [names.get(cls, cls), Fmt.money(roundi(float(entry.price))),
			roundi(float(entry.ratio) * 100.0), Fmt.money(roundi(float(entry.recommended))), roundi(float(entry.ceiling) * 100.0)]))
	page.add_child(_text("At these prices it can fill at most %d%% of its berths. At the recommended price about 90%% book; 25%% over, about 60%%; 50%% over, about 30%%; double, hardly any." % roundi(float(outlook.ceiling) * 100.0)))


# --- Departures ----------------------------------------------------------------------

func _departures(page: VBoxContainer) -> void:
	var rule: Dictionary = ship.cruise.departure
	var choices: Dictionary = Cruises.settings().get("departures", {})
	page.add_child(_text("When it sails from its home port: after a number of days taking bookings, once it's a share full, or both (once it reaches the share it keeps taking bookings till the days are up or it's full, and at the days it sails however full it is)."))
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override(&"separation", 8)
	for mode: Array in [["time", "After the days"], ["fill", "At the fill"], ["both", "Both"]]:
		var button := Button.new()
		button.toggle_mode = true
		button.text = mode[1]
		button.button_pressed = str(rule.get("mode", "both")) == mode[0]
		button.pressed.connect(func() -> void: _change({departure = {mode = mode[0], days = rule.days, fill = rule.fill}}))
		modes.add_child(button)
	page.add_child(modes)
	for setting: Array in [["days", "Days in port", "%d days"], ["fill", "Fill", "%d%%"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var label := Label.new()
		label.text = setting[1]
		label.custom_minimum_size.x = 120
		row.add_child(label)
		var options: Array = choices.get(setting[0], [])
		for i in options.size():
			var button := Button.new()
			button.toggle_mode = true
			button.text = setting[2] % int(options[i])
			button.button_pressed = int(rule.get(setting[0], 0)) == i
			button.pressed.connect(func() -> void:
				var changed := rule.duplicate()
				changed[setting[0]] = i
				_change({departure = changed}))
			row.add_child(button)
		page.add_child(row)
	if str(rule.get("mode", "")) == "fill":
		var ceiling := float(GameState.cruises.demand(ship).ceiling)
		var goal := float(choices.fill[int(rule.fill)]) / 100.0
		if ceiling < goal:
			page.add_child(_text("At these prices it can fill at most %d%%, short of %d%%: it would wait in port. Lower the prices or choose Both." % [roundi(ceiling * 100.0), roundi(goal * 100.0)]))
	page.add_child(_text(ship.status_text()))


# --- Ship -------------------------------------------------------------------------

func _ship(page: VBoxContainer) -> void:
	var cruises: Cruises = GameState.cruises
	var model := ship.model()
	page.add_child(_heading("Service levels (any time; they cost per guest-night, and the Crew level sets its crew and wages)"))
	var levels: Array = Cruises.settings().get("service_levels", [])
	for dial: String in Cruises.SERVICES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var label := Label.new()
		label.text = Cruises.SERVICE_NAMES[dial]
		label.custom_minimum_size.x = 130
		row.add_child(label)
		for i in levels.size():
			var button := Button.new()
			button.toggle_mode = true
			button.text = str(levels[i])
			button.button_pressed = int(ship.cruise.service.get(dial, 1)) == i
			button.pressed.connect(func() -> void: _change({service = {dial: i}}))
			row.add_child(button)
		page.add_child(row)
	var preview := ship.cruise.duplicate()
	preview.cabins = _refit.cabins
	preview.amenities = _refit.amenities
	var shown := Ship.new(ship.name, ship.model_id, ship.docked_at)
	shown.cruise = preview
	var exp := cruises.experience(shown, 0.9)
	page.add_child(_text("Guest experience with this setup, full to 90%%: %.1f of 5 (amenities %d%%, premium cabins %d%%, service %d%%, crowding −%d%%)." % [
		float(exp.value), roundi(float(exp.amenities) * 100.0), roundi(float(exp.premium) * 100.0), roundi(float(exp.service) * 100.0), roundi(float(exp.crowded) * 100.0)]))
	page.add_child(_heading("Refit: cabins, amenities and looks (at your HQ or a hub; out of service while it's done)"))
	var capacity := Cruises.capacity_of(model, _refit.cabins)
	var names: Dictionary = Cruises.settings().get("cabin_names", {})
	var sum := 0
	for cls: String in Cruises.CLASSES:
		sum += int(_refit.cabins.get(cls, 0))
	page.add_child(_text("Cabin space: %d%% given out (it must come to 100%%); %d guests in all." % [sum, Cruises.total(capacity)]))
	for cls: String in Cruises.CLASSES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var label := Label.new()
		label.text = str(names.get(cls, cls))
		label.custom_minimum_size.x = 130
		row.add_child(label)
		var spin := SpinBox.new()
		spin.max_value = 100
		spin.step = int(Cruises.settings().get("share_step", 5))
		spin.suffix = "%"
		spin.value = float(_refit.cabins.get(cls, 0))
		spin.value_changed.connect(func(value: float) -> void:
			_refit.cabins[cls] = roundi(value)
			_rebuild.call_deferred())
		row.add_child(spin)
		row.add_child(_text("%d guests" % int(capacity.get(cls, 0))))
		page.add_child(row)
	var slots := int(model.get("cruise", {}).get("deck_slots", 2))
	page.add_child(_text("Amenities: %d of %d deck slots%s." % [(_refit.amenities as Array).size(), slots, ", and a helipad (free)" if model.get("cruise", {}).get("helipad", false) else ""]))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", 16)
	for each: Dictionary in Cruises.amenities_for(model):
		var box := CheckBox.new()
		box.text = "%s · %s" % [each.name, Fmt.money(roundi(float(each.cost) * float(model.get("price", 0))))]
		box.tooltip_text = "Upkeep %s a guest-night · +%d%% onboard spending · adds to guest experience" % [Fmt.money(roundi(float(each.upkeep))), roundi(float(each.spend) * 100.0)]
		box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.custom_minimum_size.x = 300
		box.button_pressed = (_refit.amenities as Array).has(each.id)
		box.toggled.connect(func(on: bool) -> void:
			if on and not (_refit.amenities as Array).has(each.id):
				(_refit.amenities as Array).append(each.id)
			elif not on:
				(_refit.amenities as Array).erase(each.id)
			_rebuild.call_deferred())
		grid.add_child(box)
	page.add_child(grid)
	for look: Array in [["hull", "Hull"], ["stripe", "Stripe"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 6)
		var label := Label.new()
		label.text = look[1]
		label.custom_minimum_size.x = 130
		row.add_child(label)
		for entry: Array in GameData.config.get("company_colors", []):
			var id := str(entry[0])
			var swatch := Button.new()
			swatch.custom_minimum_size = Vector2(26, 22)
			swatch.tooltip_text = id.capitalize()
			var style := StyleBoxFlat.new()
			style.bg_color = GameState.company_color_value(id)
			style.set_corner_radius_all(4)
			style.set_border_width_all(3 if str(_refit.looks.get(look[0], "")) == id else 0)
			style.border_color = Color.WHITE if style.bg_color.get_luminance() < 0.8 else Color.BLACK
			for state: StringName in [&"normal", &"hover", &"pressed"]:
				swatch.add_theme_stylebox_override(state, style)
			swatch.pressed.connect(func() -> void:
				_refit.looks[look[0]] = id
				_rebuild.call_deferred())
			row.add_child(swatch)
		page.add_child(row)
	var decks := HBoxContainer.new()
	decks.add_theme_constant_override(&"separation", 8)
	var deck_label := Label.new()
	deck_label.text = "Decks"
	deck_label.custom_minimum_size.x = 130
	decks.add_child(deck_label)
	for deck: String in Cruises.DECKS:
		var button := Button.new()
		button.toggle_mode = true
		button.text = deck.capitalize()
		button.button_pressed = str(_refit.looks.get("deck", "teak")) == deck
		button.pressed.connect(func() -> void:
			_refit.looks.deck = deck
			_rebuild.call_deferred())
		decks.add_child(button)
	page.add_child(decks)
	var quote := cruises.refit_quote(ship, _refit)
	var error := cruises.refit_error(ship, _refit)
	page.add_child(_text("This refit: %s, %s out of service." % [Fmt.money(int(quote.cost)), Fmt.duration(float(quote.days) * 86400.0 / GameState.calendar_seconds_per_second())] if int(quote.changes) > 0 else "Change the cabins, amenities or looks above to plan a refit."))
	var go := Button.new()
	go.text = "Refit"
	go.size_flags_horizontal = SIZE_SHRINK_BEGIN
	go.custom_minimum_size = Vector2(180, 40)
	go.disabled = not error.is_empty()
	go.tooltip_text = error
	go.pressed.connect(func() -> void:
		var result := GameState.refit_cruise(ship, _refit)
		_note.text = result if not result.is_empty() else "Refit under way."
		_rebuild())
	page.add_child(go)
	if not error.is_empty() and int(quote.changes) > 0:
		page.add_child(_text(error))


# --- Reviews -----------------------------------------------------------------------

func _reviews(page: VBoxContainer) -> void:
	var reviews: Array = ship.cruise.get("reviews", [])
	if reviews.is_empty():
		page.add_child(_text("No voyages back yet. Each returning voyage gets a review: guest experience 30%, the itinerary 25% (less any ports missed), value for money 25% (what they paid against the recommendation), and how smoothly it went 20%."))
	else:
		var average := 0.0
		for each: float in reviews:
			average += each
		average /= reviews.size()
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		row.add_child(_heading("Reviews: %.1f of 5 over its last %d voyages" % [average, reviews.size()]))
		row.add_child(StarRating.new(average, 20.0))
		page.add_child(row)
	for summary: Dictionary in (ship.cruise.get("history", []) as Array).duplicate():
		var parts: Dictionary = summary.get("parts", {})
		page.add_child(_text("%d guests, %d nights: tickets %s, onboard %s, excursions %s, port fees −%s, supplies −%s, refunds −%s · review %s (experience %.1f, itinerary %.1f, value %.1f, smooth %.1f)%s" % [
			int(summary.guests), int(summary.nights), Fmt.money(int(summary.tickets)), Fmt.money(int(summary.onboard)), Fmt.money(int(summary.excursions)),
			Fmt.money(int(summary.port_fees)), Fmt.money(int(summary.supplies)), Fmt.money(int(summary.refunds)),
			"%.1f★" % float(summary.review) if float(summary.review) >= 0.0 else "none", float(parts.get("experience", 0)), float(parts.get("itinerary", 0)),
			float(parts.get("value", 0)), float(parts.get("smooth", 0)), " · %d ports missed" % int(summary.skipped) if int(summary.skipped) > 0 else ""]))


# --- Bits -------------------------------------------------------------------------

func _change(changes: Dictionary, rebuild := true) -> void:
	var error := GameState.set_cruise_settings(ship, changes)
	if not error.is_empty():
		_note.text = error
	if rebuild:
		_rebuild.call_deferred()


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", CompanyTypeIcon.type_color("cruises"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _text(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	label.text = text
	return label


## A recommendation's factors on one line: "Balcony, 4 nights at $160 a night: $640 · Cruise rating (2.1★) x0.95 · ...".
func _parts(parts: Array) -> Label:
	var bits := PackedStringArray()
	for part: Array in parts:
		bits.append("%s %s" % [part[0], part[1]])
	var label := _text("   " + " · ".join(bits))
	label.add_theme_font_size_override(&"font_size", 12)
	return label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

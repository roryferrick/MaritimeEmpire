# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name RatingsPage
extends Control
## The company's star ratings (the stars button in the World map's side
## column: see Ratings): a card per company type it has, with its stars, what
## they do to its sale prices, port fees and XP, how much of the window is on
## record, and each part (Condition, Reliability, Scale & reach) with its own
## stars, the figures behind it and how to raise it. Refreshed every few
## seconds. Over the map, dimming it; Esc, X or a click outside closes it.

const PANEL_SIZE := Vector2(820, 720)
const REFRESH_S := 3.0
## How to raise each part.
const TIPS := [
	"Keep Repair on so ships sail well maintained, spend their upgrade points, and buy mega upgrades for the models you run.",
	"Give every ship a route and keep it running, plan loops with cargo both ways, and repair before breakdowns strike.",
	"Grow the fleet as your slots allow, trade at more ports, and found every hub your level gives.",
]

## How to raise Tankers' fourth part, its rigs and refineries.
const ENERGY_TIP := "Put up rigs and platforms on the fields and refineries at ports (the Energy page), keep tugs at hand for storm damage, and send ships to collect before the rigs fill up."
## How to raise Agriculture's fourth part, its farms.
const FARM_TIP := "Buy plots at the farm ports (the Farms screen), grow what suits each climate (or fit greenhouses and irrigation), and send ships to collect the harvest before it spoils."

## How to raise each of a cruise line's parts.
const CRUISE_TIPS := [
	"Fit amenities in every deck slot, give more space to Balconies and Suites, and raise the service levels (the Ship tab of the Cruise planner).",
	"Call at more ports, near wonders, across more regions (and for Expedition ships, the polar ports).",
	"Keep Repair on so nothing breaks down mid-voyage, and keep clear of storms that close ports of call.",
	"Charge near the recommended prices (or under) so guests feel it was worth it, and keep the voyages smooth.",
]

var _list := VBoxContainer.new()
var _clock := 0.0


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
	card.custom_minimum_size = Vector2(PANEL_SIZE.x, minf(PANEL_SIZE.y, get_viewport_rect().size.y - 80.0))
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	card.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	var star := StarRating.new(1.0, 26.0, 1)
	star.custom_minimum_size = Vector2(26, 26)
	header.add_child(star)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Company ratings"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "Each company type you run earns 0 to 5 stars from the last 2 hours of play, worked out every minute: a third each for its ships' condition, their reliability, and its scale and reach. At 2.5 stars nothing changes; above, its cargo sells for more, pays lower port fees and earns more XP, and below, the opposite. Agriculture has a fourth part, a quarter of its stars, for its farms, and Tankers one for its rigs and refineries. Cruises has four parts, a quarter each: guest experience, itinerary, reliability & safety, and value & reviews; its stars move what guests will pay."
	content.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_list.add_theme_constant_override(&"separation", 12)
	scroll.add_child(_list)
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= REFRESH_S:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var company: Company = GameState.company
	for type_id: String in Ratings.rated_types(company):
		_list.add_child(_type_card(company, type_id))


func _type_card(company: Company, type_id: String) -> Control:
	var ratings: Ratings = GameState.ratings
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(CompanyTypeIcon.type_color(type_id), 0.1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 10)
	var icon := CompanyTypeIcon.new(type_id)
	icon.custom_minimum_size = Vector2(32, 32)
	head.add_child(icon)
	var name := Label.new()
	name.theme_type_variation = &"HeaderLabel"
	name.text = Progression.type_name(type_id)
	name.add_theme_color_override(&"font_color", CompanyTypeIcon.type_color(type_id))
	head.add_child(name)
	var value := ratings.stars(company, type_id)
	var stars := StarRating.new(value, 24.0)
	stars.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(stars)
	var number := Label.new()
	number.text = "%.1f / 5" % value
	head.add_child(number)
	box.add_child(head)
	box.add_child(_dim(_effects_text(company, type_id)))
	var minutes := ratings.minutes_on_record(company, type_id)
	if minutes < Ratings.WINDOW:
		box.add_child(_dim("Building up: %d of %d minutes on record (the minutes not yet on record count as no stars)." % [minutes, Ratings.WINDOW]))
	var parts := ratings.part_stars(company, type_id)
	var figures: Dictionary = (ratings.details.get(company, {}) as Dictionary).get(type_id, {})
	var lines := _cruise_texts(figures) if type_id == "cruises" else _part_texts(figures, company.level())
	var tips: Array = CRUISE_TIPS if type_id == "cruises" else TIPS
	if type_id == "agriculture":
		tips = TIPS + [FARM_TIP]
		lines.append(_farm_text(figures))
	elif type_id == "tankers":
		tips = TIPS + [ENERGY_TIP]
		lines.append(_energy_text(figures))
	var names := Ratings.part_names(type_id)
	for i in names.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 10)
		var label := Label.new()
		label.text = names[i]
		label.custom_minimum_size.x = 130
		row.add_child(label)
		var part := StarRating.new(parts[i], 15.0)
		part.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(part)
		var text := _dim("%s\n%s" % [lines[i], tips[i]])
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(text)
		box.add_child(row)
	return panel


## "Sale prices +2%, port fees -8%, XP +4%" at these stars.
func _effects_text(company: Company, type_id: String) -> String:
	if type_id == "cruises":  # (Its stars move what guests will pay: Cruises.rating_factor().)
		var xp := roundi((GameState.ratings.factor(company, type_id, "xp") - 1.0) * 100.0)
		return "At these stars: recommended cruise prices x%.2f, XP %s%d%%." % [GameState.cruises.rating_factor(company), "+" if xp >= 0 else "−", absi(xp)]
	var parts := PackedStringArray()
	for effect: Array in [["price", "sale prices"], ["fees", "port fees"], ["xp", "XP"]]:
		var change := roundi((GameState.ratings.factor(company, type_id, effect[0]) - 1.0) * 100.0)
		parts.append("%s %s%d%%" % [effect[1], "+" if change >= 0 else "−", absi(change)])
	return "At these stars: " + ", ".join(parts) + "."


## A cruise line's figures from the latest minute.
func _cruise_texts(figures: Dictionary) -> Array:
	if figures.is_empty():
		return ["Worked out every minute of play.", "", "", ""]
	if int(figures.get("ships", 0)) == 0:
		return ["No cruise ships yet.", "No cruise ships yet.", "No cruise ships yet.", "No cruise ships yet: buy one in the Shop."]
	return [
		"Guest experience %.1f of 5 on average (amenities, cabins, service, crowding)" % float(figures.experience),
		"Itineraries %d%% appealing on average (ports of call, sights, regions)" % roundi(float(figures.attraction) * 100.0),
		"Maintenance %d%% on average · %d incidents and %d ports missed over the last %d voyages" % [roundi(float(figures.maintenance) * 100.0), int(figures.incidents), int(figures.skipped), int(figures.voyages)],
		"Reviews %.1f of 5 over the last %d voyages" % [float(figures.review), int(figures.reviews)] if int(figures.reviews) > 0 else "No reviews yet (2.5 till the first voyage is back)",
	]


## Agriculture's Farms part's figures from the latest minute.
## Tankers' Production part's figures from the latest minute.
func _energy_text(figures: Dictionary) -> String:
	if not figures.has("rigs"):
		return "Not worked out yet."
	if int(figures.rigs) == 0 and int(figures.plant_ports) == 0:
		return "No rigs or refineries yet: see the Energy page."
	return "%d rigs and %d refinery ports of about %d expected · %d%% of rigs working · refineries %d%% busy · %d%% of the output kept" % [
		int(figures.rigs), int(figures.plant_ports), roundi(float(figures.expected_rigs)), roundi(float(figures.rigs_sound) * 100.0),
		roundi(float(figures.plants_used) * 100.0), roundi(float(figures.output_kept) * 100.0)]


func _farm_text(figures: Dictionary) -> String:
	if not figures.has("farmed"):
		return "Worked out every minute of play."
	if int(figures.farmed) == 0:
		return "No farms yet: buy a plot on the Farms screen."
	return "%d plots farmed of about %d expected · climate fit %d%% · %d%% of the harvest collected, not spoiled" % [
		int(figures.farmed), roundi(float(figures.expected_plots)), roundi(float(figures.farm_fit) * 100.0), roundi(float(figures.collected) * 100.0)]


## Each part's figures from the latest minute (or a note before the first).
func _part_texts(figures: Dictionary, level: int) -> Array:
	if figures.is_empty():
		return ["Worked out every minute of play.", "Worked out every minute of play.", "Worked out every minute of play."]
	if int(figures.ships) == 0:
		return ["No ships of this type yet.", "No ships of this type yet.", "No ships yet: buy some in the Shop."]
	return [
		"Maintenance %d%% on average · %d%% of upgrade points spent · mega upgrades on %d of %d models" % [
			roundi(float(figures.maintenance) * 100.0), roundi(float(figures.upgrades) * 100.0), int(figures.megas), int(figures.models)],
		"%d of %d ships idle (paused, held, no route or lost) · %d of %d departures empty · %d breakdowns, %d losses in the last minute" % [
			int(figures.idle), int(figures.ships), int(figures.empty), int(figures.departures), int(figures.breakdowns), int(figures.losses)],
		"%d ships of about %d expected at level %d · %d ports traded at in the last 30 minutes of about %d · %d of %d hubs" % [
			int(figures.ships), roundi(float(figures.expected_ships)), level, int(figures.ports), roundi(float(figures.expected_ports)), int(figures.hubs), int(figures.hub_slots)],
	]


func _dim(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"DimLabel"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	return label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		queue_free()

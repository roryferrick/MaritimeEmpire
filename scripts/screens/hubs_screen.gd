# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## The HQ and every hub, one card each: its upkeep, warehouses and traffic.
## Then a card for founding the next hub (at its price).

const CARD_WIDTH := 460.0
const REFRESH_SECONDS := 1.0

## Hub -> [traffic label], updated every second.
var _live := {}
var _clock := 0.0


func _ready() -> void:
	GameState.hubs_changed.connect(_rebuild)
	visibility_changed.connect(_rebuild)
	resized.connect(_fit_columns)
	_rebuild()


func _process(delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(delta)
	MapView._prof("proc.hubs_screen", t_x)

func _process_timed(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_update_live()


func _rebuild() -> void:
	if not is_visible_in_tree():
		return
	for child in %Cards.get_children():
		%Cards.remove_child(child)
		child.queue_free()
	_live.clear()
	%Intro.text = "Your HQ and hubs launch new ships, take no port fee on your trade there and have plots for warehouses. Found a hub at any port: the next costs %s, each after twice the last, and each hub pays an upkeep by its port's size (the HQ pays none). Facilities to buy (berths, cranes, a fuel depot, a repair yard, offices) come soon." % Fmt.money(GameState.hub_price())
	for hub in GameState.hubs:
		%Cards.add_child(_hub_card(hub))
	%Cards.add_child(_note_card("Found a hub", "Your next hub costs %s. Click any port on the World map and choose \"Build a hub here\". Hubs are permanent, so pick a busy port." % Fmt.money(GameState.hub_price()), GameState.money >= GameState.hub_price()))
	_update_live()
	_fit_columns()


## Two cards across where two fit (the page over the map is narrower than
## the screen was), else one.
func _fit_columns() -> void:
	var widest := 0.0
	for child: Control in %Cards.get_children():
		widest = maxf(widest, child.get_combined_minimum_size().x)
	var room: float = $Scroll.size.x - 48.0 - 12.0  # (Its margins, and room for the scroll bar.)
	%Cards.columns = 2 if widest * 2.0 + float(%Cards.get_theme_constant(&"h_separation")) <= room else 1


func _hub_card(hub: Hub) -> Control:
	var box := _card()
	var header := HBoxContainer.new()
	box.add_child(header)
	var logo := CompanyLogo.of(GameState.company)  # (The company's sign, as on the map.)
	logo.custom_minimum_size = Vector2(28, 28)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(logo)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = GameData.port_name(hub.port_id)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var kind := Label.new()
	kind.theme_type_variation = &"GainLabel" if hub.is_hq else &"DimLabel"
	kind.text = "Headquarters" if hub.is_hq else "Hub"
	kind.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(kind)

	var upkeep := Label.new()
	upkeep.text = "No upkeep (headquarters)" if hub.is_hq else "Upkeep %s a month" % Fmt.money(hub.upkeep())
	box.add_child(upkeep)

	box.add_child(HSeparator.new())
	box.add_child(IndustryPanel.new(hub))
	box.add_child(HSeparator.new())
	box.add_child(_facilities(hub))

	box.add_child(HSeparator.new())
	var traffic := Label.new()
	traffic.theme_type_variation = &"DimLabel"
	traffic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(traffic)
	var show := Button.new()
	show.text = "Show on map"
	show.pressed.connect(func() -> void: GameRoot.find(self).show_port_on_map(hub.port_id))
	box.add_child(show)
	_live[hub] = [traffic]
	return box.get_parent()


## The hub's facilities (Hub.facility_list()): each built (its effect, its
## upkeep) or with a Build button and what it would do.
func _facilities(hub: Hub) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	var title := Label.new()
	title.text = "Facilities"
	box.add_child(title)
	var note := Label.new()
	note.theme_type_variation = &"DimLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = "One of each may be built here, each with its monthly upkeep%s." % (" (the HQ's work x%s as hard)" % Fmt.decimal(float(Hub.settings().get("hq_multiplier", 1.5)), 1) if hub.is_hq else "")
	box.add_child(note)
	for info: Dictionary in Hub.facility_list():
		var id := str(info.id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var name := Label.new()
		name.text = str(info.name)
		name.custom_minimum_size.x = 150.0
		name.tooltip_text = str(info.text)
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(name)
		var detail := Label.new()
		detail.theme_type_variation = &"DimLabel"
		detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		detail.add_theme_font_size_override(&"font_size", 13)
		if hub.has_facility(id):
			detail.text = "Built · %s · upkeep %s a month" % [_effect_text(hub, info), Fmt.money(int(info.get("upkeep_month", 0)))]
			detail.theme_type_variation = &"GainLabel"
			row.add_child(detail)
		else:
			detail.text = str(info.text)
			row.add_child(detail)
			var build := Button.new()
			build.text = "Build %s" % Fmt.money_short(int(info.get("price", 0)))
			build.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var error := GameState.build_facility_error(hub, id)
			build.disabled = not error.is_empty()
			build.tooltip_text = error if not error.is_empty() else "%s, then %s a month." % [Fmt.money(int(info.get("price", 0))), Fmt.money(int(info.get("upkeep_month", 0)))]
			build.pressed.connect(func() -> void: GameState.build_facility(hub, id))
			row.add_child(build)
		box.add_child(row)
	return box


static func _effect_text(hub: Hub, info: Dictionary) -> String:
	var value := hub.facility_effect(str(info.id))
	match str(info.get("effect", "")):
		"dock":
			return "stops %d%% shorter" % roundi(value * 100.0)
		"fuel":
			return "fuel %d%% cheaper" % roundi(value * 100.0)
		"repairs":
			return "repairs %d%% cheaper" % roundi(value * 100.0)
		"price":
			return "%s sells %d%% dearer" % [str(info.get("family", "")), roundi(value * 100.0)]
		"passengers":
			return "%d%% more guests book here" % roundi(value * 100.0)
		"cold":
			return "the store here keeps cold"
	return ""

func _note_card(title_text: String, body: String, highlight: bool) -> Control:
	var box := _card()
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = title_text
	box.add_child(title)
	var text := Label.new()
	text.theme_type_variation = &"GainLabel" if highlight else &"DimLabel"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.text = body
	box.add_child(text)
	if highlight:
		var go := Button.new()
		go.text = "Go to the map"
		go.pressed.connect(func() -> void: GameRoot.find(self).show_screen(GameRoot.Screen.WORLD))
		box.add_child(go)
	return box.get_parent()


## A card panel; returns the box to fill (the card is its parent).
func _card() -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size.x = CARD_WIDTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	card.add_child(box)
	return box


func _update_live() -> void:
	for hub: Hub in _live:
		var traffic: Label = _live[hub][0]
		var docked := GameState.fleet().filter(func(ship: Ship) -> bool: return ship.docked_at == hub.port_id).size()
		var boats := GameState.recovery_boats_at(hub.port_id).map(func(boat: Ship) -> String: return boat.name)
		traffic.text = "%d ship%s docked now · %s deliveries unloaded here · %s pay received here\nRecovery boats based here: %s" % [
			docked, "" if docked == 1 else "s", Fmt.thousands(hub.deliveries), Fmt.money(roundi(hub.income)),
			", ".join(PackedStringArray(boats)) if not boats.is_empty() else "none"]



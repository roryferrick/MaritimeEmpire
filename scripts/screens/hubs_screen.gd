extends Control
## The HQ and every hub, one card each: level and XP bar, the upgrade tree,
## the bonuses it gives ships docking there, and its traffic. Then a card for
## a hub waiting to be founded and one for when the next hub unlocks.

const CARD_WIDTH := 460.0
const REFRESH_SECONDS := 1.0

## Hub -> [XP bar, XP label, traffic label], updated every second.
var _live := {}
var _clock := 0.0


func _ready() -> void:
	GameState.hubs_changed.connect(_rebuild)
	GameState.company_leveled.connect(_rebuild.unbind(2))
	visibility_changed.connect(_rebuild)
	_rebuild()


func _process(delta: float) -> void:
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
	var settings := Hub.settings()
	%Intro.text = ("Your HQ and hubs level up from every delivery unloaded at their port. Each level is an upgrade "
		+ "point for bonuses that help every ship docking there; the HQ's bonuses are %d%% stronger. You get a new "
		+ "hub every %d company levels.") % [roundi((float(settings.get("hq_multiplier", 1.5)) - 1.0) * 100.0),
		int(settings.get("every_company_levels", 15))]
	for hub in GameState.hubs:
		%Cards.add_child(_hub_card(hub))
	if GameState.hubs_available() > 0:
		%Cards.add_child(_note_card("New hub available",
			"%d hub%s to found. Click any port on the World map and choose \"Build a hub here\". Hubs are permanent, so pick a busy port." % [
			GameState.hubs_available(), "" if GameState.hubs_available() == 1 else "s"], true))
	var next := _next_hub_level()
	if next > 0:
		%Cards.add_child(_note_card("Next hub", "Unlocks at company level %d." % next, false))
	_update_live()


func _hub_card(hub: Hub) -> Control:
	var box := _card()
	var header := HBoxContainer.new()
	box.add_child(header)
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

	var level := Label.new()
	level.text = "Level %d of %d" % [hub.level, Hub.max_level()]
	box.add_child(level)
	var bar := ProgressBar.new()
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.custom_minimum_size.y = 10
	box.add_child(bar)
	var xp := Label.new()
	xp.theme_type_variation = &"DimLabel"
	box.add_child(xp)

	box.add_child(HSeparator.new())
	var points := hub.upgrade_points()
	var upgrades := Label.new()
	upgrades.text = "Upgrades" if points == 0 else "Upgrades: %d point%s to spend" % [points, "" if points == 1 else "s"]
	upgrades.theme_type_variation = &"GainLabel" if points > 0 else &""
	box.add_child(upgrades)
	box.add_child(HubTree.new(hub))

	box.add_child(HSeparator.new())
	var traffic := Label.new()
	traffic.theme_type_variation = &"DimLabel"
	traffic.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(traffic)
	var show := Button.new()
	show.text = "Show on map"
	show.pressed.connect(func() -> void: GameRoot.find(self).show_port_on_map(hub.port_id))
	box.add_child(show)
	_live[hub] = [bar, xp, traffic]
	return box.get_parent()


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
		var bar: ProgressBar = _live[hub][0]
		var xp: Label = _live[hub][1]
		var traffic: Label = _live[hub][2]
		var cost := GameState.hub_level_cost(hub)
		bar.value = 1.0 if cost <= 0.0 else hub.xp / cost
		xp.text = "Max level" if cost <= 0.0 else "%s / %s XP to level %d" % [
			Fmt.thousands(floori(hub.xp)), Fmt.thousands(ceili(cost)), hub.level + 1]
		var docked := GameState.ships.filter(func(ship: Ship) -> bool: return ship.docked_at == hub.port_id).size()
		var boats := GameState.recovery_boats_at(hub.port_id).map(func(boat: Ship) -> String: return boat.name)
		traffic.text = "%d ship%s docked now · %s deliveries unloaded here · %s pay received here\nRecovery boats based here: %s" % [
			docked, "" if docked == 1 else "s", Fmt.thousands(hub.deliveries), Fmt.money(roundi(hub.income)),
			", ".join(PackedStringArray(boats)) if not boats.is_empty() else "none"]


## The company level that gives the next hub, or -1 if all are unlocked.
func _next_hub_level() -> int:
	var level := GameState.company_level()
	var slots := Progression.hub_slots(level)
	for next in range(level + 1, Progression.max_company_level() + 1):
		if Progression.hub_slots(next) > slots:
			return next
	return -1

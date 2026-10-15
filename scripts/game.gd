# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name GameRoot
extends Control
## Root of an active game: top bar, activity log, the six main screens, the
## bottom nav, the full-screen Route Assignment screen, and the Esc menu;
## Space pauses and T opens the chat.

enum Screen { WORLD, SHIPS, MARKETS, FINANCES, HUBS, SHOP }

const GROUP := &"game_root"
## How often to check whether any ship needs the player.
const ALERT_CHECK_SECONDS := 2.0  # (A look over every ship and model: a few ms.)
## Ships named per reason in the Ships tab's tooltip before "and 3 more".
const ALERT_NAMES_SHOWN := 3

var _current_screen := Screen.WORLD

@onready var _screens := {
	Screen.WORLD: %WorldScreen,
	Screen.SHIPS: %ShipsScreen,
	Screen.MARKETS: %MarketsScreen,
	Screen.FINANCES: %FinancesScreen,
	Screen.HUBS: %HubsScreen,
	Screen.SHOP: %ShopScreen,
}
@onready var _nav_buttons := {
	Screen.WORLD: %WorldButton,
	Screen.SHIPS: %ShipsButton,
	Screen.MARKETS: %MarketsButton,
	Screen.FINANCES: %FinancesButton,
	Screen.HUBS: %HubsButton,
	Screen.SHOP: %ShopButton,
}
@onready var _popup_host: PopupHost = %PopupHost

## Shown on the Ships tab while any ship needs the player (see
## Ship.attention_reason()), and on the Shop tab while any ship can be bought.
## The cards for the big moments (levels, achievements), over everything.
var event_card := EventCard.new()
var _ships_alert := AlertDot.new()
var _shop_alert := AlertDot.new()
## On the Hubs tab while a hub has upgrade points to spend or can be founded.
var _hubs_alert := AlertDot.new()
## On the World tab while a market region can be unlocked (on the map).
var _world_alert := AlertDot.new()
var _alert_clock := 0.0
## The Esc menu while it's open.
var _escape_menu: EscapeMenu = null


static func find(from: Node) -> GameRoot:
	return from.get_tree().get_first_node_in_group(GROUP) as GameRoot


func _ready() -> void:
	add_to_group(GROUP)
	var group := ButtonGroup.new()
	for screen: Screen in _nav_buttons:
		var button: Button = _nav_buttons[screen]
		button.theme_type_variation = &"PageButton"  # (In the headings' font: see ui/theme.tres.)
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(show_screen.bind(screen))
	%RouteScreen.finished.connect(_close_route_screen)
	GameState.cargo_sold.connect(_on_cargo_sold)
	GameState.cargo_loaded.connect(_on_cargo_loaded)
	GameState.catch_landed.connect(_on_catch_landed)
	GameState.trophy_caught.connect(_on_trophy_caught)
	GameState.canal_entered.connect(_on_canal_entered)
	GameState.ship_held.connect(_on_ship_held)
	GameState.ship_broke_down.connect(_on_ship_broke_down)
	GameState.ship_battered.connect(_on_ship_battered)
	GameState.wages_paid.connect(_on_wages_paid)
	GameState.ship_lost.connect(_on_ship_lost)
	GameState.ship_recovered.connect(_on_ship_recovered)
	GameState.tugs_handed.connect(_on_tugs_handed)
	GameState.recovery_sent.connect(_on_recovery_sent)
	GameState.ship_at_risk.connect(_on_ship_at_risk)
	GameState.ship_sold.connect(_on_ship_sold)
	GameState.company_leveled.connect(_on_company_leveled)
	GameState.rating_changed.connect(_on_rating_changed)
	GameState.ship_leveled.connect(_on_ship_leveled)
	%ShipsButton.add_child(_ships_alert)
	%ShopButton.add_child(_shop_alert)
	%HubsButton.add_child(_hubs_alert)
	%WorldButton.add_child(_world_alert)
	GameState.hub_leveled.connect(_on_hub_leveled)
	GameState.hub_built.connect(_on_hub_built)
	GameState.mega_upgraded.connect(_on_mega_upgraded)
	GameState.port_band_changed.connect(_on_port_band_changed)
	_alert_phase = 0  # (Worked out over the next frames: see _process().)
	Net.left.connect(_on_left_game)
	if not Net.host_error.is_empty():
		_tell(Net.host_error, "Couldn't host this game")
		Net.host_error = ""
	if GameState.tutorials:
		# Over the screens (and the Route Assignment map) but under the popups.
		var tutorial := TutorialCard.new()
		_popup_host.add_sibling(tutorial)
		_popup_host.get_parent().move_child(tutorial, _popup_host.get_index())
	# Over the popups and the tutorial: the last of the siblings.
	_popup_host.get_parent().add_child(event_card)
	show_screen(Screen.WORLD)


func _process(delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(delta)
	MapView._prof("proc.game", t_x)

func _process_timed(delta: float) -> void:
	_alert_clock += delta
	if _alert_clock >= ALERT_CHECK_SECONDS:
		_alert_clock = 0.0
		_alert_phase = 0
	if _alert_phase < 3:  # (One part a frame: each is a look over the hubs, the models or the fleet.)
		_update_alerts(_alert_phase)
		_alert_phase += 1


## Red dots on the Ships tab if any ship needs the player (the tooltip says
## why), and on the Shop tab if anything can be bought.
var _alert_phase := 3
func _update_alerts(phase: int) -> void:
	var t_a := Time.get_ticks_usec()
	if phase != 0:
		if phase == 1:
			_update_shop_alert()
		else:
			_update_ships_alert()
		return
	var hub_notes := PackedStringArray()
	for hub in GameState.hubs:
		if GameState.hub_can_upgrade(hub):
			hub_notes.append("%s has an upgrade you can buy" % hub.title())
	if GameState.hubs_available() > 0:
		hub_notes.append("a new hub can be founded (click a port)")
	_hubs_alert.visible = not hub_notes.is_empty()
	_world_alert.visible = GameState.regions_available() > 0
	%WorldButton.tooltip_text = "A new region can be unlocked: Unlock a region, on the map" if _world_alert.visible else ""
	%HubsButton.tooltip_text = "; ".join(hub_notes)
	MapView._prof("alerts.hubs", t_a)

func _update_shop_alert() -> void:
	var t_a := Time.get_ticks_usec()
	var buyable := PackedStringArray()
	for model: Dictionary in GameData.ship_models:
		if GameState.buy_error(model.id).is_empty():
			buyable.append(model.get("name", model.id))
	_shop_alert.visible = not buyable.is_empty() or GameState.company_types_available() > 0
	%ShopButton.tooltip_text = "You can buy: %s" % ", ".join(buyable) if not buyable.is_empty() else ""
	if GameState.company_types_available() > 0:  # (A new company type to choose: on a locked tab.)
		%ShopButton.tooltip_text = ("You can choose a new company type. " + %ShopButton.tooltip_text).strip_edges()
	MapView._prof("alerts.shop", t_a)

func _update_ships_alert() -> void:
	var t_a := Time.get_ticks_usec()
	var reasons := {}  # reason -> names of the ships it applies to
	for ship in GameState.fleet():
		var reason := ship.attention_reason()
		if not reason.is_empty():
			if not reasons.has(reason):
				reasons[reason] = PackedStringArray()
			reasons[reason].append(ship.name)
	_ships_alert.visible = not reasons.is_empty()
	MapView._prof("alerts.ships", t_a)
	var parts := PackedStringArray()
	for reason: String in reasons:
		var names: PackedStringArray = reasons[reason]
		var named := ", ".join(names.slice(0, ALERT_NAMES_SHOWN))
		if names.size() > ALERT_NAMES_SHOWN:
			named += " and %d more" % (names.size() - ALERT_NAMES_SHOWN)
		parts.append("%d %s (%s)" % [names.size(), reason, named])
	%ShipsButton.tooltip_text = "Ships needing you: %s" % ", ".join(parts) if not reasons.is_empty() else ""


## Switches to the World map, centered on a port.
func show_port_on_map(port_id: String) -> void:
	show_screen(Screen.WORLD)
	(%WorldScreen.find_child("MapView") as MapView).focus_port(port_id)


## Switches to the World map, centered on a ship, with its popup open.
func show_ship_on_map(ship: Ship) -> void:
	show_screen(Screen.WORLD)
	var map: MapView = %WorldScreen.find_child("MapView")
	map.follow_ship(ship)
	%WorldScreen.open_ship_popup(ship)


## True once the World map is warm (see MapView.is_warm(); the loading screen waits for it).
func is_warm() -> bool:
	return (%WorldScreen.find_child("MapView") as MapView).is_warm()

## The ship the World map is following (see MapView.follow_ship()), or null.
func followed_ship() -> Ship:
	return (%WorldScreen.find_child("MapView") as MapView).followed


func show_screen(screen: Screen) -> void:
	_current_screen = screen
	_popup_host.close()
	for s: Screen in _screens:
		_screens[s].visible = s == screen
	_nav_buttons[screen].button_pressed = true


## Full screen, with no top bar, nav or activity log. Returns to the current screen when done.
func open_route_screen(ship: Ship) -> void:
	_popup_host.close()
	for s: Screen in _screens:
		_screens[s].visible = false
	%TopBar.visible = false
	%BottomNav.visible = false
	%ActivityLogPanel.visible = false
	%RouteScreen.visible = true
	%RouteScreen.open(ship)


## The Fishing Grounds screen (FishingScreen), full screen like the Route
## Assignment one; made the first time it's opened.
var _fishing_screen: FishingScreen = null

func open_fishing_screen() -> void:
	_popup_host.close()
	if _fishing_screen == null:
		_fishing_screen = FishingScreen.new()
		_fishing_screen.visible = false
		%RouteScreen.add_sibling(_fishing_screen)
		_fishing_screen.finished.connect(_close_fishing_screen)
	for s: Screen in _screens:
		_screens[s].visible = false
	%TopBar.visible = false
	%BottomNav.visible = false
	%ActivityLogPanel.visible = false
	_fishing_screen.visible = true
	_fishing_screen.open()


func _close_fishing_screen() -> void:
	_fishing_screen.visible = false
	%TopBar.visible = true
	%BottomNav.visible = true
	%ActivityLogPanel.visible = true
	show_screen(_current_screen)


func is_route_screen_open() -> bool:
	return %RouteScreen.visible


func _close_route_screen() -> void:
	%RouteScreen.visible = false
	%TopBar.visible = true
	%BottomNav.visible = true
	%ActivityLogPanel.visible = true
	show_screen(_current_screen)


## "Sea Otter sold Toys at Rotterdam: +$2,300 profit (bought $1,200, sold $3,500)":
## the trade's profit after the canal tolls on the way; a loss is shown in red.
## A muted model's profitable sales are left out.
func _on_cargo_sold(ship: Ship, port_id: String, commodity_id: String, _quantity: int, cost: int, sale: int, tolls: int, fee: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	var profit := sale - cost - tolls - fee
	if profit >= 0 and GameState.muted_models.has(ship.model_id):
		return
	var text := "%s sold %s at %s: %s%s profit (bought %s, sold %s%s%s)" % [ship.name, GameData.commodity(commodity_id).get("name", commodity_id),
		GameData.port_name(port_id), "+" if profit >= 0 else "", Fmt.money(profit), Fmt.money(cost), Fmt.money(sale),
		", tolls %s" % Fmt.money(tolls) if tolls > 0 else "", ", port fee %s" % Fmt.money(fee) if fee > 0 else ""]
	ActivityLog.add(text, ActivityLog.Kind.INFO if profit >= 0 else ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


## "Pot Luck landed 6,000 crates of red king crab at Dutch Harbor: $28,800,000"
## (or "... put ... in the cold store at ...", for the company's carriers).
func _on_catch_landed(ship: Ship, port_id: String, species: String, crates: int, value: int, stored: bool) -> void:
	if not GameState.is_mine(ship) or GameState.muted_models.has(ship.model_id):
		return
	var what := Fisheries.shared().species_word(species)
	var text := "%s %s %s crates of %s %s %s: %s" % [ship.name, "put" if stored else "landed", Fmt.thousands(crates), what,
		"in the cold store at" if stored else "at", GameData.port_name(port_id), Fmt.money(value)]
	ActivityLog.add(text, ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


## "Reel Deal hooked a giant bluefin tuna: its hold's full, heading home".
func _on_trophy_caught(ship: Ship, species: String) -> void:
	if not GameState.is_mine(ship):
		return
	ActivityLog.add("%s hooked a giant %s: its hold's full, heading home" % [ship.name, Fisheries.shared().species_word(species)],
		ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


## "Sea Otter loaded 10 containers of Toys for Rotterdam ($1,200)".
func _on_cargo_loaded(ship: Ship, _port_id: String, commodity_id: String, quantity: int, cost: int, to_port: String) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	if GameState.muted_models.has(ship.model_id):
		return
	var commodity := GameData.commodity(commodity_id)
	ActivityLog.add("%s loaded %s %s of %s for %s (%s)" % [ship.name, Fmt.thousands(quantity), commodity.get("units", "units"),
		commodity.get("name", commodity_id), GameData.port_name(to_port), Fmt.money(cost)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


## "Ever Bright entered the Panama Canal: toll $4,200 (+50% XP on this delivery)";
## a convoy canal says the ship joined its convoy.
func _on_canal_entered(ship: Ship, canal: Dictionary, toll: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	if GameState.muted_models.has(ship.model_id):
		return
	var what := "joined the %s convoy" % canal.name if canal.get("type", "") == "convoy" else "entered the %s" % canal.name
	var parts := PackedStringArray()
	if toll > 0:
		parts.append("toll %s" % Fmt.money(toll))
	var bonus := roundi(float(canal.get("xp_bonus", 0.0)) * 100.0)
	if bonus > 0:
		parts.append("+%d%% XP on this delivery" % bonus)
	var text := "%s %s" % [ship.name, what]
	if not parts.is_empty():
		text += ": %s" % ", ".join(parts)
	ActivityLog.add(text, ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_ship_held(ship: Ship, reason: String) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s is held at %s: %s" % [ship.name, GameData.port_name(ship.docked_at), reason], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_wages_paid(ship: Ship, total: int, ship_count: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("Payday: %s in crew wages for %d ship%s%s" % [Fmt.money(total), ship_count, "" if ship_count == 1 else "s",
		" - you're in debt: your ships run on credit, but nothing can be bought until you're back above $0" if GameState.in_debt() else ""],
		ActivityLog.Kind.BAD if GameState.in_debt() else ActivityLog.Kind.INFO)


func _on_ship_battered(ship: Ship, storm: Dictionary) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s was battered at anchor off %s by %s: maintenance down to %d%%" % [ship.name, GameData.port_name(ship.docked_at),
		Weather.title(storm), floori(ship.maintenance * 100.0)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_broke_down(ship: Ship) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s broke down at sea! Maintenance now %d%%" % [ship.name, floori(ship.maintenance * 100.0)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_lost(ship: Ship) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s is lost at sea (%s)." % [ship.name, ship.lost_reason], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_recovered(ship: Ship, mammoth: Ship, port_id: String, to_destination: bool) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	var outcome := "" if to_destination else " (back where it came from, so no pay)"
	if mammoth.is_tug():
		ActivityLog.add("%s towed %s in to %s%s" % [mammoth.tug_crew_text(), ship.name, GameData.port_name(port_id), outcome], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))
		return
	ActivityLog.add("%s carried %s to %s%s" % [mammoth.name, ship.name, GameData.port_name(port_id), outcome], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


func _on_tugs_handed(ship: Ship, boat: Ship, port_id: String) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s brought %s within reach of %s's tugs" % [boat.name, ship.name, GameData.port_name(port_id)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_recovery_sent(ship: Ship, boat: Ship, cost: int, auto: bool) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	if auto:
		var sent := "%s sent" % boat.name
		if boat.is_tug():
			sent = "%s sent out from %s" % [boat.tug_crew_text(), GameData.port_name(boat.tow_port)]
		ActivityLog.add("Auto-recovery: %s for %s (about %s)" % [sent, ship.name, Fmt.money(cost)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_ship_at_risk(ship: Ship) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s won't make it to %s at this rate!" % [ship.name, GameData.port_name(ship.to_port)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_sold(ship: Ship, price: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("Sold %s for %s" % [ship.name, Fmt.money(price)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


## One of this player's company types reached a new whole star, or fell to one (Ratings).
func _on_rating_changed(who: Company, type_id: String, star: int, up: bool) -> void:
	if who != GameState.company:
		return
	var type_name := Progression.type_name(type_id)
	ActivityLog.add("%s %s to %d stars." % [type_name, "rose" if up else "fell", star], ActivityLog.Kind.GOOD if up else ActivityLog.Kind.BAD)
	event_card.show_rating(type_name, star, up)


func _on_company_leveled(level: int, unlocks: Array[String]) -> void:
	var text := "Company level %d!" % level
	if not unlocks.is_empty():
		text += " Unlocked: %s" % ", ".join(unlocks)
	ActivityLog.add(text, ActivityLog.Kind.GOOD)
	event_card.show_level(level, unlocks)


func _on_ship_leveled(ship: Ship, level: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s reached level %d: an upgrade to spend" % [ship.name, level], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


func _on_hub_leveled(hub: Hub, level: int) -> void:
	if not GameState.hubs.has(hub):
		return  # Another player's.
	ActivityLog.add("%s reached level %d: an upgrade to spend" % [hub.title(), level], ActivityLog.Kind.GOOD)


func _on_hub_built(hub: Hub) -> void:
	if not GameState.hubs.has(hub):
		return  # Another player's.
	ActivityLog.add("Founded a hub at %s" % GameData.port_name(hub.port_id), ActivityLog.Kind.GOOD)


func _on_mega_upgraded(model_id: String) -> void:
	if Net.acting_peer != 0:
		return  # A joined player's upgrade: theirs to hear about.
	var model_name: String = GameData.get_ship_model(model_id).get("name", model_id)
	ActivityLog.add("Mega upgrade: every %s now has %s" % [model_name, GameState.mega_effect(model_id)], ActivityLog.Kind.GOOD)


func _on_port_band_changed(port_id: String, band: String, grew: bool) -> void:
	if not GameState.is_port_unlocked(port_id):
		return  # Its region is locked: its name isn't known yet.
	ActivityLog.add("%s %s to %s" % [GameData.port_name(port_id), "grew" if grew else "shrank", band.capitalize()],
		ActivityLog.Kind.GOOD if grew else ActivityLog.Kind.INFO)


## Space pauses or carries on (see GameState.toggle_pause()) and T opens the
## chat (multiplayer), unless the player is typing or the Esc menu is open.
## Taken before the controls see them, so a focused button doesn't take Space.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo or is_instance_valid(_escape_menu):
		return
	# Esc with something on a tab focused (a list, a table, a picker), which
	# would take it for itself: the tab's popup closes, else the menu opens.
	if event.is_action_pressed(&"ui_cancel"):
		var focused := get_viewport().gui_get_focus_owner()
		var on_tab := focused != null and _current_screen != Screen.WORLD and (_screens[_current_screen] as Control).is_ancestor_of(focused)
		if on_tab:
			focused.release_focus()
			get_viewport().set_input_as_handled()
			if focused is LineEdit or focused is TextEdit:
				return  # (Typing: Esc just leaves the box.)
			if is_instance_valid(_popup_host.current):
				_popup_host.close()
			else:
				_escape_menu = EscapeMenu.new()
				add_child(_escape_menu)
			return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	match key.keycode:
		KEY_SPACE:
			GameState.toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_T:
			if Net.is_online():
				%ActivityLogPanel.open_chat()
				get_viewport().set_input_as_handled()


## Esc opens the menu (see EscapeMenu), once nothing else wanted it: an open
## popup or the Route Assignment screen close first.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not is_instance_valid(_escape_menu):
		get_viewport().set_input_as_handled()
		_popup_host.close()
		_escape_menu = EscapeMenu.new()
		add_child(_escape_menu)


## Multiplayer: the host left (or the connection dropped): back to the title
## screen, saying why.
func _on_left_game(reason: String) -> void:
	_tell(reason, "Left the game", func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))


## A message box over the game; then() runs once it's closed.
func _tell(text: String, title: String, then := Callable()) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	add_child(dialog)
	if then.is_valid():
		dialog.confirmed.connect(then)
		dialog.canceled.connect(then)
	dialog.popup_centered()

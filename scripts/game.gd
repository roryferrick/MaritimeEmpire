class_name GameRoot
extends Control
## Root of an active game: top bar, activity log, the six main screens, the
## bottom nav, and the full-screen Route Assignment screen.

enum Screen { WORLD, SHIPS, MARKETS, FINANCES, HUBS, SHOP }

const GROUP := &"game_root"
## How often to check whether any ship needs the player.
const ALERT_CHECK_SECONDS := 0.5
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
var _ships_alert := AlertDot.new()
var _shop_alert := AlertDot.new()
## On the Hubs tab while a hub has upgrade points to spend or can be founded.
var _hubs_alert := AlertDot.new()
var _alert_clock := 0.0


static func find(from: Node) -> GameRoot:
	return from.get_tree().get_first_node_in_group(GROUP) as GameRoot


func _ready() -> void:
	add_to_group(GROUP)
	var group := ButtonGroup.new()
	for screen: Screen in _nav_buttons:
		var button: Button = _nav_buttons[screen]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(show_screen.bind(screen))
	%RouteScreen.finished.connect(_close_route_screen)
	GameState.cargo_sold.connect(_on_cargo_sold)
	GameState.cargo_loaded.connect(_on_cargo_loaded)
	GameState.canal_entered.connect(_on_canal_entered)
	GameState.ship_held.connect(_on_ship_held)
	GameState.ship_broke_down.connect(_on_ship_broke_down)
	GameState.ship_lost.connect(_on_ship_lost)
	GameState.ship_recovered.connect(_on_ship_recovered)
	GameState.recovery_sent.connect(_on_recovery_sent)
	GameState.ship_at_risk.connect(_on_ship_at_risk)
	GameState.ship_sold.connect(_on_ship_sold)
	GameState.company_leveled.connect(_on_company_leveled)
	GameState.ship_leveled.connect(_on_ship_leveled)
	%ShipsButton.add_child(_ships_alert)
	%ShopButton.add_child(_shop_alert)
	%HubsButton.add_child(_hubs_alert)
	GameState.hub_leveled.connect(_on_hub_leveled)
	GameState.hub_built.connect(_on_hub_built)
	GameState.mega_upgraded.connect(_on_mega_upgraded)
	_update_alerts()
	show_screen(Screen.WORLD)


func _process(delta: float) -> void:
	_alert_clock += delta
	if _alert_clock >= ALERT_CHECK_SECONDS:
		_alert_clock = 0.0
		_update_alerts()


## Red dots on the Ships tab if any ship needs the player (the tooltip says
## why), and on the Shop tab if anything can be bought.
func _update_alerts() -> void:
	var hub_notes := PackedStringArray()
	for hub in GameState.hubs:
		if GameState.hub_can_upgrade(hub):
			hub_notes.append("%s has an upgrade you can buy" % hub.title())
	if GameState.hubs_available() > 0:
		hub_notes.append("a new hub can be founded (click a port)")
	_hubs_alert.visible = not hub_notes.is_empty()
	%HubsButton.tooltip_text = "; ".join(hub_notes)
	var buyable := PackedStringArray()
	for model: Dictionary in GameData.ship_models:
		if GameState.buy_error(model.id).is_empty():
			buyable.append(model.get("name", model.id))
	_shop_alert.visible = not buyable.is_empty()
	%ShopButton.tooltip_text = "You can buy: %s" % ", ".join(buyable) if not buyable.is_empty() else ""
	var reasons := {}  # reason -> names of the ships it applies to
	for ship in GameState.ships:
		var reason := ship.attention_reason()
		if not reason.is_empty():
			if not reasons.has(reason):
				reasons[reason] = PackedStringArray()
			reasons[reason].append(ship.name)
	_ships_alert.visible = not reasons.is_empty()
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
	map.focus_ship(ship, map.size.y * 0.3)
	%WorldScreen.open_ship_popup(ship)


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


func _close_route_screen() -> void:
	%RouteScreen.visible = false
	%TopBar.visible = true
	%BottomNav.visible = true
	%ActivityLogPanel.visible = true
	show_screen(_current_screen)


## "Sea Otter sold Toys at Rotterdam: +$2,300 profit (bought $1,200, sold $3,500)":
## the trade's profit after the canal tolls on the way; a loss is shown in red.
func _on_cargo_sold(ship: Ship, port_id: String, commodity_id: String, _quantity: int, cost: int, sale: int, tolls: int) -> void:
	var profit := sale - cost - tolls
	var text := "%s sold %s at %s: %s%s profit (bought %s, sold %s%s)" % [ship.name, GameData.commodity(commodity_id).get("name", commodity_id),
		GameData.port_name(port_id), "+" if profit >= 0 else "", Fmt.money(profit), Fmt.money(cost), Fmt.money(sale),
		", tolls %s" % Fmt.money(tolls) if tolls > 0 else ""]
	ActivityLog.add(text, ActivityLog.Kind.INFO if profit >= 0 else ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


## "Sea Otter loaded 10 containers of Toys for Rotterdam ($1,200)".
func _on_cargo_loaded(ship: Ship, _port_id: String, commodity_id: String, quantity: int, cost: int, to_port: String) -> void:
	var commodity := GameData.commodity(commodity_id)
	ActivityLog.add("%s loaded %s %s of %s for %s (%s)" % [ship.name, Fmt.thousands(quantity), commodity.get("units", "units"),
		commodity.get("name", commodity_id), GameData.port_name(to_port), Fmt.money(cost)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


## "Ever Bright entered the Panama Canal: toll $4,200 (+50% XP on this delivery)";
## a convoy canal says the ship joined its convoy.
func _on_canal_entered(ship: Ship, canal: Dictionary, toll: int) -> void:
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
	ActivityLog.add("%s is held at %s: %s" % [ship.name, GameData.port_name(ship.docked_at), reason], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_broke_down(ship: Ship) -> void:
	ActivityLog.add("%s broke down at sea! Maintenance now %d%%" % [ship.name, floori(ship.maintenance * 100.0)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_lost(ship: Ship) -> void:
	ActivityLog.add("%s is lost at sea (%s)." % [ship.name, ship.lost_reason], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_recovered(ship: Ship, mammoth: Ship, port_id: String, to_destination: bool) -> void:
	var outcome := "" if to_destination else " (back where it came from, so no pay)"
	ActivityLog.add("%s carried %s to %s%s" % [mammoth.name, ship.name, GameData.port_name(port_id), outcome], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


func _on_recovery_sent(ship: Ship, boat: Ship, cost: int, auto: bool) -> void:
	if auto:
		ActivityLog.add("Auto-recovery: %s sent for %s (about %s)" % [boat.name, ship.name, Fmt.money(cost)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_ship_at_risk(ship: Ship) -> void:
	ActivityLog.add("%s won't make it to %s at this rate!" % [ship.name, GameData.port_name(ship.to_port)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_sold(ship: Ship, price: int) -> void:
	ActivityLog.add("Sold %s for %s" % [ship.name, Fmt.money(price)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_company_leveled(level: int, unlocks: Array[String]) -> void:
	var text := "Company level %d!" % level
	if not unlocks.is_empty():
		text += " Unlocked: %s" % ", ".join(unlocks)
	ActivityLog.add(text, ActivityLog.Kind.GOOD)


func _on_ship_leveled(ship: Ship, level: int) -> void:
	ActivityLog.add("%s reached level %d: an upgrade to spend" % [ship.name, level], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


func _on_hub_leveled(hub: Hub, level: int) -> void:
	ActivityLog.add("%s reached level %d: an upgrade to spend" % [hub.title(), level], ActivityLog.Kind.GOOD)


func _on_hub_built(hub: Hub) -> void:
	ActivityLog.add("Founded a hub at %s" % GameData.port_name(hub.port_id), ActivityLog.Kind.GOOD)


func _on_mega_upgraded(model_id: String) -> void:
	var model_name: String = GameData.get_ship_model(model_id).get("name", model_id)
	ActivityLog.add("Mega upgrade: every %s is now 50%% faster and earns 50%% more profit" % model_name, ActivityLog.Kind.GOOD)

class_name GameRoot
extends Control
## Root of an active game: top bar, activity log, the four main screens, the
## bottom nav, and the full-screen Route Assignment screen.

enum Screen { WORLD, SHIPS, FINANCES, SHOP }

const GROUP := &"game_root"
## How often to check whether any ship needs the player.
const ALERT_CHECK_SECONDS := 0.5

var _current_screen := Screen.WORLD

@onready var _screens := {
	Screen.WORLD: %WorldScreen,
	Screen.SHIPS: %ShipsScreen,
	Screen.FINANCES: %FinancesScreen,
	Screen.SHOP: %ShopScreen,
}
@onready var _nav_buttons := {
	Screen.WORLD: %WorldButton,
	Screen.SHIPS: %ShipsButton,
	Screen.FINANCES: %FinancesButton,
	Screen.SHOP: %ShopButton,
}
@onready var _popup_host: PopupHost = %PopupHost

## Shown on the Ships tab while any ship needs the player (see
## Ship.attention_reason()), and on the Shop tab while any ship can be bought.
var _ships_alert := AlertDot.new()
var _shop_alert := AlertDot.new()
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
	GameState.ship_departed.connect(_on_ship_departed)
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
	var buyable := PackedStringArray()
	for model: Dictionary in GameData.ship_models:
		if GameState.buy_error(model.id).is_empty():
			buyable.append(model.get("name", model.id))
	_shop_alert.visible = not buyable.is_empty()
	%ShopButton.tooltip_text = "You can buy: %s" % ", ".join(buyable) if not buyable.is_empty() else ""
	var reasons := {}
	for ship in GameState.ships:
		var reason := ship.attention_reason()
		if not reason.is_empty():
			reasons[reason] = int(reasons.get(reason, 0)) + 1
	_ships_alert.visible = not reasons.is_empty()
	var parts := PackedStringArray()
	for reason: String in reasons:
		parts.append("%d %s" % [reasons[reason], reason])
	%ShipsButton.tooltip_text = "Ships needing you: %s" % ", ".join(parts) if not reasons.is_empty() else ""


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


func _on_ship_departed(ship: Ship, port_id: String, sale: int, fuel_cost: int, repair_cost: int) -> void:
	var port := GameData.port_name(port_id)
	var costs := fuel_cost + repair_cost
	if sale > 0:
		ActivityLog.add("%s left %s: sold %s, profit %s" % [ship.name, port, Fmt.money(sale), Fmt.money(sale - costs)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))
	else:
		ActivityLog.add("%s left %s: fuel and repairs %s" % [ship.name, port, Fmt.money(-costs)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


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

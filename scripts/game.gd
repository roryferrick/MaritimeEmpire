class_name GameRoot
extends Control
## Root of an active game: top bar, the three main screens, the bottom nav, and
## the full-screen Route Assignment screen.

enum Screen { WORLD, SHIPS, SHOP }

const GROUP := &"game_root"

var _current_screen := Screen.WORLD

@onready var _screens := {
	Screen.WORLD: %WorldScreen,
	Screen.SHIPS: %ShipsScreen,
	Screen.SHOP: %ShopScreen,
}
@onready var _nav_buttons := {
	Screen.WORLD: %WorldButton,
	Screen.SHIPS: %ShipsButton,
	Screen.SHOP: %ShopButton,
}
@onready var _popup_host: PopupHost = %PopupHost


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
	show_screen(Screen.WORLD)


func show_screen(screen: Screen) -> void:
	_current_screen = screen
	_popup_host.close()
	for s: Screen in _screens:
		_screens[s].visible = s == screen
	_nav_buttons[screen].button_pressed = true


## Full screen, with no top bar or nav. Returns to the current screen when done.
func open_route_screen(ship: Ship) -> void:
	_popup_host.close()
	for s: Screen in _screens:
		_screens[s].visible = false
	%TopBar.visible = false
	%BottomNav.visible = false
	%RouteScreen.visible = true
	%RouteScreen.open(ship)


func _close_route_screen() -> void:
	%RouteScreen.visible = false
	%TopBar.visible = true
	%BottomNav.visible = true
	show_screen(_current_screen)


func _on_ship_departed(ship: Ship, port_id: String, sale: int, fuel_cost: int, repair_cost: int) -> void:
	var port := GameData.port_name(port_id)
	var costs := fuel_cost + repair_cost
	if sale > 0:
		Toast.show_message("%s left %s: sold %s, profit %s" % [ship.name, port, Fmt.money(sale), Fmt.money(sale - costs)])
	else:
		Toast.show_message("%s left %s: fuel and repairs %s" % [ship.name, port, Fmt.money(-costs)])


func _on_ship_held(ship: Ship, reason: String) -> void:
	Toast.show_message("%s is held at %s: %s" % [ship.name, GameData.port_name(ship.docked_at), reason])


func _on_ship_broke_down(ship: Ship) -> void:
	Toast.show_message("%s broke down at sea! Maintenance now %d%%" % [ship.name, floori(ship.maintenance * 100.0)])


func _on_ship_lost(ship: Ship) -> void:
	Toast.show_message("%s is lost at sea (%s). Send a Mammoth from its popup." % [ship.name, ship.lost_reason])


func _on_ship_recovered(ship: Ship, mammoth: Ship, port_id: String, to_destination: bool) -> void:
	var outcome := "" if to_destination else " (back where it came from, so no pay)"
	Toast.show_message("%s carried %s to %s%s" % [mammoth.name, ship.name, GameData.port_name(port_id), outcome])

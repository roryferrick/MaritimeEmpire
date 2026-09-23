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
	GameState.ship_arrived.connect(_on_ship_arrived)
	GameState.ship_held.connect(_on_ship_held)
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


func _on_ship_arrived(ship: Ship, port_id: String, payment: int) -> void:
	Toast.show_message("%s delivered to %s (+%s)" % [ship.name, GameData.port_name(port_id), Fmt.money(payment)])


func _on_ship_held(ship: Ship, reason: String) -> void:
	Toast.show_message("%s is held at %s: %s" % [ship.name, GameData.port_name(ship.docked_at), reason])

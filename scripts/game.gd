extends Control
## Root of an active game: top bar, the three main screens, and the bottom nav.

enum Screen { WORLD, SHIPS, SHOP }

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


func _ready() -> void:
	var group := ButtonGroup.new()
	for screen: Screen in _nav_buttons:
		var button: Button = _nav_buttons[screen]
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(show_screen.bind(screen))
	show_screen(Screen.WORLD)


func show_screen(screen: Screen) -> void:
	_popup_host.close()
	for s: Screen in _screens:
		_screens[s].visible = s == screen
	_nav_buttons[screen].button_pressed = true

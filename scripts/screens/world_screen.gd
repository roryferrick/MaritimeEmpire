extends Control
## The main map: ports, ships and canal locks, with their popups, and the Routes switch
## and price picker in one panel in the top right (the fleet's route lanes shown
## faintly; ports colored by a commodity's price).

## Commodity colors (their ship line's) are brightened to at least this
## luminance so they read on the dark panel.
const LINE_MIN_LUMINANCE := 0.5
## How strongly each ship line's group is tinted in the price menu.
const PRICE_GROUP_TINT := 0.16

@onready var _map: MapView = $MapView
var _price_button := Button.new()
var _price_menu := PopupPanel.new()


func _ready() -> void:
	_map.show_ships = true
	_map.show_active_lanes = GameState.show_active_routes
	_map.port_clicked.connect(_open_port_popup)
	_map.ship_clicked.connect(open_ship_popup)
	_map.lock_clicked.connect(_open_lock_popup)
	_map.canal_clicked.connect(_open_convoy_popup)
	_map.empty_clicked.connect(func() -> void: PopupHost.find(self).close())
	%RoutesToggle.set_pressed_no_signal(GameState.show_active_routes)
	%RoutesToggle.toggled.connect(_on_routes_toggled)
	_add_price_picker()


func _on_routes_toggled(on: bool) -> void:
	GameState.show_active_routes = on
	_map.show_active_lanes = on


func _open_port_popup(port_id: String) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.port_screen_position(port_id)
	PopupHost.find(self).show_port(port_id, follow)


func _open_lock_popup(canal_id: String, lock_index: int) -> void:
	var popup := LockPopup.new()
	popup.canal_id = canal_id
	popup.lock_index = lock_index
	popup.follow = func() -> Vector2:
		return _map.get_global_transform() * _map.lock_screen_position(canal_id, lock_index)
	PopupHost.find(self).open(popup)


func _open_convoy_popup(canal_id: String) -> void:
	var popup := ConvoyPopup.new()
	popup.canal_id = canal_id
	popup.follow = func() -> Vector2:
		return _map.get_global_transform() * _map.canal_screen_position(canal_id)
	PopupHost.find(self).open(popup)


## The ship's popup, following it on the map.
func open_ship_popup(ship: Ship) -> void:
	var follow := func() -> Vector2:
		return _map.get_global_transform() * _map.ship_screen_position(ship)
	PopupHost.find(self).show_ship(ship, follow)


## "Prices: Toys ▾" under the Routes switch, in the same panel: colors the ports
## by that commodity's price (see MapView.price_commodity), or "Prices: off". Its
## menu groups the commodities by the ship line that carries them, each group on
## a faint tint of the line's color, each commodity with a swatch in it; the
## chosen one's name is shown in that color too.
func _add_price_picker() -> void:
	_price_button.tooltip_text = "Color the ports by a commodity's price: green where it's cheap, red where it's dear."
	_price_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_price_button.pressed.connect(_open_price_menu)
	%MapControls.add_child(_price_button)

	var list := VBoxContainer.new()
	list.add_theme_constant_override(&"separation", 3)
	_price_menu.add_child(list)
	list.add_child(_price_item(""))
	var group: VBoxContainer = null
	var group_color := Color.TRANSPARENT
	for commodity: Dictionary in GameData.commodities:
		var color := _line_color(commodity.id)
		if group == null or color != group_color:
			group_color = color
			var tint := PanelContainer.new()
			var style := StyleBoxFlat.new()
			style.bg_color = Color(color, PRICE_GROUP_TINT)
			style.set_corner_radius_all(4)
			tint.add_theme_stylebox_override(&"panel", style)
			list.add_child(tint)
			group = VBoxContainer.new()
			group.add_theme_constant_override(&"separation", 0)
			tint.add_child(group)
		group.add_child(_price_item(commodity.id))
	_price_menu.add_theme_stylebox_override(&"panel", get_theme_stylebox(&"panel", &"MapPopup"))
	add_child(_price_menu)
	_choose_price("")


## One entry in the price menu: "Prices: Toys" with its line's swatch.
func _price_item(commodity_id: String) -> Button:
	var item := Button.new()
	item.flat = true
	item.alignment = HORIZONTAL_ALIGNMENT_LEFT
	item.text = _price_text(commodity_id)
	if not commodity_id.is_empty():
		item.icon = _swatch(_line_color(commodity_id))
	item.pressed.connect(_choose_price.bind(commodity_id))
	return item


func _price_text(commodity_id: String) -> String:
	return "Prices: off" if commodity_id.is_empty() else "Prices: %s" % GameData.commodity(commodity_id).get("name", commodity_id)


func _open_price_menu() -> void:
	var rect := _price_button.get_global_rect()
	_price_menu.popup(Rect2i(Vector2i(rect.position + Vector2(0, rect.size.y + 4)), Vector2i(int(rect.size.x), 0)))


func _choose_price(commodity_id: String) -> void:
	_price_menu.hide()
	_map.price_commodity = commodity_id
	_price_button.text = _price_text(commodity_id) + "  ▾"
	_price_button.icon = null if commodity_id.is_empty() else _swatch(_line_color(commodity_id))
	for color_name: StringName in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		if commodity_id.is_empty():
			_price_button.remove_theme_color_override(color_name)
		else:
			_price_button.add_theme_color_override(color_name, _line_color(commodity_id))


## The color of the ship line that carries a commodity (see GameData.category_color()).
static func _line_color(commodity_id: String) -> Color:
	for model: Dictionary in GameData.ship_models:
		if not model.get("recovery", false) and model.get("cargo", []).has(commodity_id):
			return GameData.category_color(model.get("category", ""), LINE_MIN_LUMINANCE)
	return Color.WHITE


## A small square of solid color, for the price picker's items.
static func _swatch(color: Color) -> ImageTexture:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)

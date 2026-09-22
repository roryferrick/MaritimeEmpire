class_name MapView
extends Control
## Pannable, zoomable top-down map. Draws the ocean, ports, ships and an optional
## route, and reports clicks.
##
## World coordinates are nautical miles, x east / y north (see data/ports.json).
## Colors come from the "MapView" type in the project theme.

signal port_clicked(port_id: String)
signal ship_clicked(ship: Ship)
signal empty_clicked
## Emitted whenever the view pans or zooms, so overlays can follow.
signal view_changed

const THEME_TYPE := &"MapView"
const PORT_RADIUS := 16.0
const PORT_HIT_RADIUS := 24.0
const SHIP_SIZE := Vector2(20, 9)
const SHIP_HIT_RADIUS := 14.0
## Docked ships sit in rings around their port, this many per ring.
const DOCK_SLOTS := 8
const DOCK_RING_GAP := 14.0
const DRAG_THRESHOLD := 5.0
const ZOOM_STEP := 1.15
## Zoom limits, relative to the zoom that fits all ports on screen.
const MIN_ZOOM_FACTOR := 0.5
const MAX_ZOOM_FACTOR := 6.0
## Empty space around the ports when fitting them on screen, as a fraction of their extent.
const FIT_MARGIN := 0.25
const GRID_SPACING_NM := 300.0

const FALLBACK_COLORS := {
	&"ocean": Color(0.12, 0.33, 0.58),
	&"ocean_gray": Color(0.32, 0.33, 0.35),
	&"land": Color(0.25, 0.65, 0.3),
	&"land_gray": Color(0.62, 0.62, 0.62),
	&"outline": Color(0.1, 0.25, 0.12),
	&"outline_gray": Color(0.2, 0.2, 0.2),
	&"grid": Color(1, 1, 1, 0.06),
	&"label": Color.WHITE,
	&"ship": Color(0.98, 0.9, 0.55),
	&"ship_outline": Color(0.15, 0.12, 0.05),
	&"route": Color(1.0, 0.6, 0.15),
}

## Draw with the muted palette used by the Route Assignment screen.
@export var gray_mode := false:
	set(value):
		gray_mode = value
		queue_redraw()

## Draw the player's ships and let them be clicked.
@export var show_ships := false

## Port ids drawn as a looping route, with each stop numbered.
var route: Array[String] = []:
	set(value):
		route = value
		queue_redraw()

var _center := Vector2.ZERO  # World point (nm) shown at the middle of the view.
var _zoom := 1.0  # Screen pixels per nautical mile.
var _fit_zoom := 1.0
var _has_fit := false
var _pressed_button: MouseButton = MOUSE_BUTTON_NONE
var _press_pos := Vector2.ZERO
var _dragging := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(_on_resized)


func _process(_delta: float) -> void:
	if show_ships and is_visible_in_tree():
		queue_redraw()


func world_to_screen(world: Vector2) -> Vector2:
	return size / 2.0 + Vector2(world.x - _center.x, _center.y - world.y) * _zoom


func screen_to_world(screen: Vector2) -> Vector2:
	var offset := (screen - size / 2.0) / _zoom
	return Vector2(_center.x + offset.x, _center.y - offset.y)


## Port position in this control's local coordinates.
func port_screen_position(port_id: String) -> Vector2:
	return world_to_screen(GameData.port_position(port_id))


## Ship position in this control's local coordinates. Docked ships are spread
## around their port so they don't overlap it or each other.
func ship_screen_position(ship: Ship) -> Vector2:
	if not ship.is_docked():
		return world_to_screen(ship.world_position())
	var slot := 0
	for other in GameState.ships:
		if other == ship:
			break
		if other.docked_at == ship.docked_at:
			slot += 1
	@warning_ignore("integer_division")
	var ring := slot / DOCK_SLOTS
	var angle := -PI / 2.0 + TAU * (slot % DOCK_SLOTS) / DOCK_SLOTS
	var radius := PORT_RADIUS + DOCK_RING_GAP + ring * DOCK_RING_GAP
	return port_screen_position(ship.docked_at) + Vector2.from_angle(angle) * radius


func fit_to_ports() -> void:
	var bounds := _port_bounds()
	var extent := (bounds.size * (1.0 + FIT_MARGIN * 2.0)).max(Vector2(100, 100))
	_center = bounds.get_center()
	_fit_zoom = minf(size.x / extent.x, size.y / extent.y)
	_zoom = _fit_zoom
	_changed()


func _on_resized() -> void:
	if not _has_fit and size.x > 0 and size.y > 0:
		_has_fit = true
		fit_to_ports()
	else:
		_changed()


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					_zoom_at(button.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					_zoom_at(button.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				if button.pressed and _pressed_button == MOUSE_BUTTON_NONE:
					_pressed_button = button.button_index
					_press_pos = button.position
					_dragging = false
				elif not button.pressed and button.button_index == _pressed_button:
					if not _dragging and button.button_index == MOUSE_BUTTON_LEFT:
						_click(button.position)
					_pressed_button = MOUSE_BUTTON_NONE
					_dragging = false
		accept_event()
		return

	var motion := event as InputEventMouseMotion
	if motion and _pressed_button != MOUSE_BUTTON_NONE:
		if not _dragging and motion.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			_center += Vector2(-motion.relative.x, motion.relative.y) / _zoom
			_clamp_center()
			_changed()
		accept_event()


## Picks whichever port or ship is closest to the click, within its hit radius.
func _click(screen_pos: Vector2) -> void:
	var nearest_port := ""
	var nearest_ship: Ship = null
	var nearest_dist := INF
	for port: Dictionary in GameData.ports:
		var dist := port_screen_position(port.id).distance_to(screen_pos)
		if dist <= PORT_HIT_RADIUS and dist < nearest_dist:
			nearest_dist = dist
			nearest_port = port.id
	if show_ships:
		for ship in GameState.ships:
			var dist := ship_screen_position(ship).distance_to(screen_pos)
			if dist <= SHIP_HIT_RADIUS and dist < nearest_dist:
				nearest_dist = dist
				nearest_ship = ship
	if nearest_ship:
		ship_clicked.emit(nearest_ship)
	elif not nearest_port.is_empty():
		port_clicked.emit(nearest_port)
	else:
		empty_clicked.emit()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var anchor := screen_to_world(screen_pos)
	_zoom = clampf(_zoom * factor, _fit_zoom * MIN_ZOOM_FACTOR, _fit_zoom * MAX_ZOOM_FACTOR)
	# Keep the world point under the cursor fixed.
	_center += anchor - screen_to_world(screen_pos)
	_clamp_center()
	_changed()


## Stop the player from panning far away from the ports and getting lost.
func _clamp_center() -> void:
	var bounds := _port_bounds()
	bounds = bounds.grow(maxf(bounds.size.x, bounds.size.y) * 0.75 + 200.0)
	_center = _center.clamp(bounds.position, bounds.end)


func _port_bounds() -> Rect2:
	if GameData.ports.is_empty():
		return Rect2()
	var bounds := Rect2(GameData.port_position(GameData.ports[0].id), Vector2.ZERO)
	for port: Dictionary in GameData.ports:
		bounds = bounds.expand(GameData.port_position(port.id))
	return bounds


func _changed() -> void:
	queue_redraw()
	view_changed.emit()


func _color(color_name: StringName) -> Color:
	var gray_name := StringName(color_name + "_gray")
	if gray_mode and FALLBACK_COLORS.has(gray_name):
		color_name = gray_name
	if has_theme_color(color_name, THEME_TYPE):
		return get_theme_color(color_name, THEME_TYPE)
	return FALLBACK_COLORS.get(color_name, Color.MAGENTA)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _color(&"ocean"))
	_draw_grid()
	_draw_route()
	_draw_ports()
	if show_ships:
		_draw_ships()


func _draw_ports() -> void:
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var land := _color(&"land")
	var outline := _color(&"outline")
	var label := _color(&"label")
	var label_width := 160.0
	for port: Dictionary in GameData.ports:
		var pos := port_screen_position(port.id)
		draw_circle(pos, PORT_RADIUS, land)
		draw_arc(pos, PORT_RADIUS, 0.0, TAU, 32, outline, 2.0, true)
		draw_string(font, pos + Vector2(-label_width / 2.0, PORT_RADIUS + font_size + 2.0),
				port.get("name", port.id), HORIZONTAL_ALIGNMENT_CENTER, label_width, font_size, label)


## Legs as solid lines, the leg closing the loop dashed, and stop numbers above
## each port (a port visited twice shows both numbers).
func _draw_route() -> void:
	if route.is_empty():
		return
	var color := _color(&"route")
	for i in range(1, route.size()):
		draw_line(port_screen_position(route[i - 1]), port_screen_position(route[i]), color, 3.0, true)
	if route.size() >= 2 and route[-1] != route[0]:
		draw_dashed_line(port_screen_position(route[-1]), port_screen_position(route[0]), color, 3.0, 10.0)

	var stops := {}  # port id -> stop numbers
	for i in route.size():
		if not stops.has(route[i]):
			stops[route[i]] = []
		stops[route[i]].append(str(i + 1))
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	var label_width := 160.0
	for port_id: String in stops:
		var pos := port_screen_position(port_id) + Vector2(-label_width / 2.0, -PORT_RADIUS - 8.0)
		draw_string(font, pos, ", ".join(PackedStringArray(stops[port_id])),
				HORIZONTAL_ALIGNMENT_CENTER, label_width, font_size, color)


func _draw_ships() -> void:
	var fill := _color(&"ship")
	var outline := _color(&"ship_outline")
	var rect := Rect2(-SHIP_SIZE / 2.0, SHIP_SIZE)
	for ship in GameState.ships:
		var heading := 0.0
		if not ship.is_docked():
			heading = (port_screen_position(ship.to_port) - port_screen_position(ship.from_port)).angle()
		draw_set_transform(ship_screen_position(ship), heading)
		draw_rect(rect, fill)
		draw_rect(rect, outline, false, 1.5)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_grid() -> void:
	var color := _color(&"grid")
	var top_left := screen_to_world(Vector2.ZERO)
	var bottom_right := screen_to_world(size)
	var x := floorf(top_left.x / GRID_SPACING_NM) * GRID_SPACING_NM
	while x <= bottom_right.x:
		var sx := world_to_screen(Vector2(x, 0)).x
		draw_line(Vector2(sx, 0), Vector2(sx, size.y), color)
		x += GRID_SPACING_NM
	var y := floorf(bottom_right.y / GRID_SPACING_NM) * GRID_SPACING_NM
	while y <= top_left.y:
		var sy := world_to_screen(Vector2(0, y)).y
		draw_line(Vector2(0, sy), Vector2(size.x, sy), color)
		y += GRID_SPACING_NM

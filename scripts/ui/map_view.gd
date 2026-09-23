class_name MapView
extends Control
## Pannable, zoomable world map (Web Mercator, wraps east-west). Draws land,
## borders and country names, with ports, ships and an optional route on top,
## and reports clicks.
##
## Map coordinates are projected degrees (see Geo). Colors come from the
## "MapView" type in the project theme; gray_mode uses the "_gray" variants.

signal port_clicked(port_id: String)
signal ship_clicked(ship: Ship)
signal empty_clicked
## Emitted whenever the view pans or zooms.
signal view_changed

const THEME_TYPE := &"MapView"
const PORT_RADIUS := 6.0
const PORT_HIT_RADIUS := 14.0
const SHIP_HIT_RADIUS := 12.0
## Docked ships sit in rings around their port, this many per ring.
const DOCK_SLOTS := 8
const DOCK_RING_GAP := 11.0
## Docked recovery boats are small dots on a tight ring of their own around
## the port, inside the ring of docked cargo ships.
const RECOVERY_DOT_RADIUS := 3.5
const RECOVERY_RING_RADIUS := PORT_RADIUS + 6.0
const RECOVERY_DOT_SLOTS := 10
const DRAG_THRESHOLD := 5.0
const ZOOM_STEP := 1.15
## Closest zoom, in pixels per projected degree.
const MAX_ZOOM := 800.0
## Panning stops with the view centered at this latitude.
const MAX_VIEW_LAT := 75.0
const PORT_FONT_SIZE := 15
const COUNTRY_FONT_SIZE := 13
const LABEL_PADDING := 3.0
## A ship's pointed bow sticks out this many times its width.
const BOW_LENGTH_FACTOR := 0.6
const LOST_MARKER_SIZE := 26
## How far above a lost ship its "!" sits.
const LOST_MARKER_OFFSET := 12.0

const FALLBACK_COLORS := {
	&"ocean": Color(0.16, 0.36, 0.56),
	&"ocean_gray": Color(0.3, 0.31, 0.33),
	&"land": Color(0.78, 0.74, 0.6),
	&"land_gray": Color(0.5, 0.5, 0.5),
	&"coast": Color(0.35, 0.33, 0.25),
	&"coast_gray": Color(0.25, 0.25, 0.25),
	&"border": Color(0.5, 0.42, 0.35, 0.8),
	&"border_gray": Color(0.38, 0.38, 0.38),
	&"country_label": Color(0.3, 0.27, 0.2, 0.85),
	&"country_label_gray": Color(0.3, 0.3, 0.3),
	&"port": Color.WHITE,
	&"port_outline": Color(0.08, 0.12, 0.2),
	&"port_dimmed": Color(0.55, 0.55, 0.55, 0.6),
	&"label": Color.WHITE,
	&"label_shadow": Color(0, 0, 0, 0.7),
	&"ship_outline": Color(0.1, 0.08, 0.05),
	&"lost_marker": Color(0.95, 0.15, 0.12),
	&"lost_marker_outline": Color(1, 1, 1),
	&"at_risk_marker": Color(1.0, 0.7, 0.1),
	&"route": Color(1.0, 0.6, 0.15),
}

## Draw with the muted palette used by the Route Assignment screen.
@export var gray_mode := false:
	set(value):
		gray_mode = value
		for art in _art_copies:
			art.queue_redraw()
		queue_redraw()

## Draw the player's ships and let them be clicked.
@export var show_ships := false

## Port ids drawn as a looping route along its sea lanes, each stop numbered.
var route: Array[String] = []:
	set(value):
		route = value
		_overlay.queue_redraw()

## Port ids drawn grayed out, e.g. ports out of range in the route editor.
var dimmed_ports: Dictionary = {}:
	set(value):
		dimmed_ports = value
		_overlay.queue_redraw()

var _center := Vector2.ZERO  # Map point shown at the middle of the view.
var _zoom := 1.0  # Screen pixels per projected degree.
var _has_fit := false
var _pressed_button: MouseButton = MOUSE_BUTTON_NONE
var _press_pos := Vector2.ZERO
var _dragging := false

## Holds the land art; its transform does the panning and zooming.
var _art_root := Node2D.new()
## One copy of the world art per wrap-around: west, center and east.
var _art_copies: Array[WorldArt] = []
## Ports, ships, routes and labels, drawn in screen space every frame.
var _overlay := Control.new()
var _ports_by_rank: Array = []  # Label priority order, sorted on first draw.


## Land, coastline and borders for one copy of the world. Drawn once and cached;
## panning and zooming only move its parent.
class WorldArt:
	extends Node2D

	var view: MapView
	var land_mesh: ArrayMesh
	var water_mesh: ArrayMesh
	var white: Texture2D

	func _draw() -> void:
		var data := GameData.world_map
		draw_mesh(land_mesh, white, Transform2D.IDENTITY, view._color(&"land"))
		draw_mesh(water_mesh, white, Transform2D.IDENTITY, view._color(&"ocean"))
		draw_multiline(data.border_segments, view._color(&"border"), -1.0)
		draw_multiline(data.coast_segments, view._color(&"coast"), -1.0)


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(_on_resized)

	var data := GameData.world_map
	var land_mesh := _triangle_mesh(data.land_triangles)
	var water_mesh := _triangle_mesh(data.water_triangles)
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(image)
	add_child(_art_root)
	for copy in [-1, 0, 1]:
		var art := WorldArt.new()
		art.view = self
		art.land_mesh = land_mesh
		art.water_mesh = water_mesh
		art.white = white
		art.position.x = copy * Geo.WORLD_WIDTH
		_art_root.add_child(art)
		_art_copies.append(art)

	_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_overlay.set_anchors_preset(PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(_delta: float) -> void:
	if show_ships and is_visible_in_tree():
		_overlay.queue_redraw()


func _triangle_mesh(triangles: PackedVector2Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if triangles.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- View ----------------------------------------------------------------

## Screen position (local to this control) of a map point, using whichever
## east-west copy of the world is closest to the view's center.
func world_to_screen(world: Vector2) -> Vector2:
	world.x = _wrap_near(world.x, _center.x)
	return size / 2.0 + Vector2(world.x - _center.x, _center.y - world.y) * _zoom


func screen_to_world(screen: Vector2) -> Vector2:
	var offset := (screen - size / 2.0) / _zoom
	return Vector2(_center.x + offset.x, _center.y - offset.y)


func port_screen_position(port_id: String) -> Vector2:
	return world_to_screen(GameData.port_position(port_id))


## Docked ships are spread around their port so they don't cover it or each
## other; docked recovery boats get their own inner ring of dots.
func ship_screen_position(ship: Ship) -> Vector2:
	if not ship.is_docked():
		return world_to_screen(ship.world_position())
	var slot := 0
	for other in GameState.ships:
		if other == ship:
			break
		if other.docked_at == ship.docked_at and other.is_recovery() == ship.is_recovery():
			slot += 1
	if ship.is_recovery():
		var dot_angle := PI / 2.0 + TAU * (slot % RECOVERY_DOT_SLOTS) / RECOVERY_DOT_SLOTS
		return port_screen_position(ship.docked_at) + Vector2.from_angle(dot_angle) * RECOVERY_RING_RADIUS
	@warning_ignore("integer_division")
	var ring := slot / DOCK_SLOTS
	var angle := -PI / 2.0 + TAU * (slot % DOCK_SLOTS) / DOCK_SLOTS
	var radius := PORT_RADIUS + DOCK_RING_GAP + ring * DOCK_RING_GAP
	return port_screen_position(ship.docked_at) + Vector2.from_angle(angle) * radius


## Centers on a port (by default the company's home port), showing
## game_config.json's initial_view_width_deg degrees of longitude across.
func reset_view(center_port := "") -> void:
	if center_port.is_empty():
		center_port = GameState.home_port
	var width := float(GameData.config.get("initial_view_width_deg", 45.0))
	_center = GameData.port_position(center_port) if not center_port.is_empty() else Vector2.ZERO
	_zoom = clampf(size.x / width, _min_zoom(), MAX_ZOOM)
	_changed()


func _min_zoom() -> float:
	return size.x / Geo.WORLD_WIDTH


func _on_resized() -> void:
	if not _has_fit and size.x > 0 and size.y > 0:
		_has_fit = true
		reset_view()
	else:
		_zoom = maxf(_zoom, _min_zoom())
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
	_zoom = clampf(_zoom * factor, _min_zoom(), MAX_ZOOM)
	# Keep the map point under the cursor fixed.
	_center += anchor - screen_to_world(screen_pos)
	_changed()


func _changed() -> void:
	_center.x = wrapf(_center.x, -Geo.WORLD_WIDTH / 2.0, Geo.WORLD_WIDTH / 2.0)
	var max_y := Geo.project(Vector2(0, MAX_VIEW_LAT)).y
	_center.y = clampf(_center.y, -max_y, max_y)
	_art_root.position = size / 2.0 + Vector2(-_center.x, _center.y) * _zoom
	_art_root.scale = Vector2(_zoom, -_zoom)
	queue_redraw()
	_overlay.queue_redraw()
	view_changed.emit()


static func _wrap_near(x: float, near: float) -> float:
	return x + roundf((near - x) / Geo.WORLD_WIDTH) * Geo.WORLD_WIDTH


func _color(color_name: StringName) -> Color:
	var gray_name := StringName(color_name + "_gray")
	if gray_mode and FALLBACK_COLORS.has(gray_name):
		color_name = gray_name
	if has_theme_color(color_name, THEME_TYPE):
		return get_theme_color(color_name, THEME_TYPE)
	return FALLBACK_COLORS.get(color_name, Color.MAGENTA)


# --- Drawing -------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _color(&"ocean"))


func _draw_overlay() -> void:
	var placed_labels: Array[Rect2] = []
	var port_labels := _place_port_labels(placed_labels)
	_draw_country_labels(placed_labels)
	_draw_route()
	_draw_ports(port_labels)
	if show_ships:
		_draw_ships()


## Port labels in rank order, skipping any that would overlap one already placed.
## Returns [port id, label rect] pairs.
func _place_port_labels(placed: Array[Rect2]) -> Array:
	var font := get_theme_default_font()
	if _ports_by_rank.is_empty():
		_ports_by_rank = GameData.ports.duplicate()
		_ports_by_rank.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.get("rank", 999) < b.get("rank", 999))
	var ranked := _ports_by_rank
	var labels := []
	var bounds := Rect2(Vector2.ZERO, size)
	for port: Dictionary in ranked:
		var pos := port_screen_position(port.id)
		var text_size := font.get_string_size(port.name, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE)
		var rect := Rect2(pos + Vector2(-text_size.x / 2.0, PORT_RADIUS + 2.0), text_size)
		if not bounds.intersects(rect) or _overlaps(rect, placed):
			continue
		placed.append(rect.grow(LABEL_PADDING))
		labels.append([port.id, rect])
	return labels


func _draw_country_labels(placed: Array[Rect2]) -> void:
	var data := GameData.world_map
	var font := get_theme_default_font()
	var color := _color(&"country_label")
	var web_zoom := log(_zoom * Geo.WORLD_WIDTH / 256.0) / log(2.0)
	var bounds := Rect2(Vector2.ZERO, size)
	for i in data.label_names.size():
		if data.label_min_zoom[i] > web_zoom:
			continue
		var text := data.label_names[i]
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTRY_FONT_SIZE)
		var rect := Rect2(world_to_screen(data.label_positions[i]) - text_size / 2.0, text_size)
		if not bounds.encloses(rect) or _overlaps(rect, placed):
			continue
		placed.append(rect.grow(LABEL_PADDING))
		_overlay.draw_string(font, rect.position + Vector2(0, font.get_ascent(COUNTRY_FONT_SIZE)), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTRY_FONT_SIZE, color)


func _overlaps(rect: Rect2, placed: Array[Rect2]) -> bool:
	for other in placed:
		if rect.intersects(other):
			return true
	return false


func _draw_ports(labels: Array) -> void:
	var font := get_theme_default_font()
	var fill := _color(&"port")
	var dimmed := _color(&"port_dimmed")
	var outline := _color(&"port_outline")
	var label_color := _color(&"label")
	var shadow := _color(&"label_shadow")
	for port: Dictionary in GameData.ports:
		var pos := port_screen_position(port.id)
		var is_dimmed := dimmed_ports.has(port.id)
		_overlay.draw_circle(pos, PORT_RADIUS, dimmed if is_dimmed else fill)
		_overlay.draw_arc(pos, PORT_RADIUS, 0.0, TAU, 24, outline, 1.5, true)
	for label: Array in labels:
		var rect: Rect2 = label[1]
		var baseline := rect.position + Vector2(0, font.get_ascent(PORT_FONT_SIZE))
		var text: String = GameData.port_name(label[0])
		var color := dimmed if dimmed_ports.has(label[0]) else label_color
		_overlay.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, shadow)
		_overlay.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, color)


## Legs follow their sea lanes; the leg closing the loop is dashed. Stop
## numbers sit above each port (a port visited twice shows both numbers).
func _draw_route() -> void:
	if route.is_empty():
		return
	var color := _color(&"route")
	for i in range(1, route.size()):
		_draw_lane(route[i - 1], route[i], color, false)
	if route.size() >= 2 and route[-1] != route[0]:
		_draw_lane(route[-1], route[0], color, true)

	var stops := {}  # port id -> stop numbers
	for i in route.size():
		if not stops.has(route[i]):
			stops[route[i]] = []
		stops[route[i]].append(str(i + 1))
	var font := get_theme_default_font()
	var shadow := _color(&"label_shadow")
	for port_id: String in stops:
		var text := ", ".join(PackedStringArray(stops[port_id]))
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE).x
		var pos := port_screen_position(port_id) + Vector2(-width / 2.0, -PORT_RADIUS - 5.0)
		_overlay.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, shadow)
		_overlay.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, color)


func _draw_lane(from_port: String, to_port: String, color: Color, dashed: bool) -> void:
	var sea_lane = GameData.lane(from_port, to_port)
	if sea_lane == null:
		return
	# Shift the whole lane by one wrap offset so it doesn't split at the seam.
	var start: Vector2 = sea_lane.points[0]
	var shift := _wrap_near(start.x, _center.x) - start.x
	var points := PackedVector2Array()
	for p: Vector2 in sea_lane.points:
		points.append(size / 2.0 + Vector2(p.x + shift - _center.x, _center.y - p.y) * _zoom)
	if dashed:
		for i in range(1, points.size()):
			_overlay.draw_dashed_line(points[i - 1], points[i], color, 2.5, 8.0)
	else:
		_overlay.draw_polyline(points, color, 2.5, true)


## Ships are rectangles with a pointed bow (docked recovery boats: small dots).
## Ships riding on a recovery boat are drawn after it, so they sit in its
## middle. Lost ships get a red "!" above them, and ships that won't make it
## to port an amber one.
func _draw_ships() -> void:
	var outline := _color(&"ship_outline")
	for ship in GameState.ships:
		if not ship.is_carried():
			_draw_ship(ship, outline)
	for ship in GameState.ships:
		if ship.is_carried():
			_draw_ship(ship, outline)
	_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
	for ship in GameState.ships:
		if ship.is_lost() and not ship.is_carried():
			_draw_marker(ship_screen_position(ship), _color(&"lost_marker"))
		elif ship.at_risk:
			_draw_marker(ship_screen_position(ship), _color(&"at_risk_marker"))


func _draw_ship(ship: Ship, outline: Color) -> void:
	var model := ship.model()
	var color := Color.from_string(model.get("map_color", "#ffffff"), Color.WHITE)
	if ship.is_recovery() and ship.is_docked():
		_overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
		var at := ship_screen_position(ship)
		_overlay.draw_circle(at, RECOVERY_DOT_RADIUS, color, true, -1.0, true)
		_overlay.draw_circle(at, RECOVERY_DOT_RADIUS, outline, false, 1.0, true)
		return
	var dims: Array = model.get("map_size", [14, 6])
	var length := float(dims[0])
	var width := float(dims[1])
	var bow := width * BOW_LENGTH_FACTOR
	# Hull plus bow, centered on the ship's position.
	var back := -(length + bow) / 2.0
	var front := back + length
	var hull := PackedVector2Array([
		Vector2(back, -width / 2.0), Vector2(front, -width / 2.0), Vector2(front + bow, 0.0),
		Vector2(front, width / 2.0), Vector2(back, width / 2.0)])
	var direction := ship.heading()
	var angle := Vector2(direction.x, -direction.y).angle() if direction != Vector2.ZERO else 0.0
	_overlay.draw_set_transform(ship_screen_position(ship), angle)
	_overlay.draw_colored_polygon(hull, color)
	hull.append(hull[0])
	_overlay.draw_polyline(hull, outline, 1.0)


func _draw_marker(at: Vector2, color: Color) -> void:
	var font := get_theme_default_font()
	var baseline := at + Vector2(-LOST_MARKER_SIZE * 0.15, -LOST_MARKER_OFFSET)
	_overlay.draw_string_outline(font, baseline, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, LOST_MARKER_SIZE, 4,
		_color(&"lost_marker_outline"))
	_overlay.draw_string(font, baseline, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, LOST_MARKER_SIZE, color)

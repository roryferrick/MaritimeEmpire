class_name MapView
extends Control
## Pannable, zoomable world map (Web Mercator, wraps east-west). Draws land,
## borders and country names, canals and their locks, with ports, ships and an
## optional route on top, and reports clicks.
##
## Map coordinates are projected degrees (see Geo). Colors come from the
## "MapView" type in the project theme; gray_mode uses the "_gray" variants.

signal port_clicked(port_id: String)
signal ship_clicked(ship: Ship)
signal lock_clicked(canal_id: String, lock_index: int)
signal canal_clicked(canal_id: String)
signal empty_clicked
## Emitted whenever the view pans or zooms.
signal view_changed

const THEME_TYPE := &"MapView"
## A port's dot radius grows with its size (see PortSizes): PORT_RADIUS_MIN at
## size 1, PORT_RADIUS at PORT_RADIUS_SIZE (mid-Large, the size before port
## sizes), PORT_RADIUS_MAX at 100.
const PORT_RADIUS_MIN := 3.0
const PORT_RADIUS_MAX := 9.0
const PORT_RADIUS_SIZE := 63.0
const PORT_RADIUS := 6.0
const PORT_HIT_RADIUS := 14.0
const SHIP_HIT_RADIUS := 12.0
## Docked ships are small dots in their model's color, in rings around their
## port: the first ring DOCK_FIRST_RING_GAP outside the port's dot, each next
## ring DOCK_RING_GAP further, with dots about DOCK_DOT_SPACING apart (so outer
## rings hold more).
const DOCK_DOT_RADIUS := 2.75
const DOCK_FIRST_RING_GAP := 7.5
const DOCK_RING_GAP := 6.0
const DOCK_DOT_SPACING := 6.5
## Half the size of the docked-dot images: the dot plus room for its outline.
const DOCK_DOT_IMAGE_RADIUS := DOCK_DOT_RADIUS + 1.5
## How often (seconds) the static map layer (ports, labels, route lanes) is
## redrawn while ships are shown, besides whenever the view or settings change.
const STATIC_REFRESH_S := 0.25
const DRAG_THRESHOLD := 5.0
const ZOOM_STEP := 1.15
## Closest zoom, in pixels per projected degree.
const MAX_ZOOM := 800.0
## Panning stops with the view centered at this latitude.
const MAX_VIEW_LAT := 80.0
const PORT_FONT_SIZE := 15
const COUNTRY_FONT_SIZE := 13
const LABEL_PADDING := 3.0
## A ship's pointed bow sticks out this many times its width.
const BOW_LENGTH_FACTOR := 0.6
## Ship art, per model category: <category>_hull.svg (white, tinted with the
## model's map color), <category>_details.svg (drawn as is, over the cargo) and,
## for categories whose cargo shows, <category>_cargo.svg. Categories without
## art are drawn as plain shapes. The art is SHIP_ART_WIDTH wide, bow to the right.
const SHIP_ART_DIR := "res://art/ships/"
const SHIP_ART_WIDTH := 180.0
## Where the cargo sits along the art (x from the stern, in art units). It
## fills from the stern forward in CARGO_STEPS steps, so part loads show.
const CARGO_ZONES := {container = Vector2(34.0, 138.0), vehicles = Vector2(12.0, 147.4), livestock = Vector2(34.0, 138.0)}
const CARGO_STEPS := 4
## Ships keep their map_size until the zoom passes SHIP_GROW_FROM_ZOOM, then
## grow with the square root of the zoom, up to SHIP_MAX_SCALE times.
const SHIP_GROW_FROM_ZOOM := 60.0
const SHIP_MAX_SCALE := 3.0
## Where a ship being carried sits on its recovery boat: the middle of the
## open work deck aft (x from the stern, in art units), clear of the wheelhouse.
const CARRY_DECK_X := 58.0
## The land's real colors, made by tools/build_map_data.gd from Natural Earth II.
const LAND_COLORS := "res://data/land_colors.webp"
## How far each sea depth band is from the ocean color (shallow, the
## continental shelf) to ocean_deep: the shelf, then 200 m, 1,000 m, 2,000 m ...
## 10,000 m (see _depth_color()). The big steps come early, where most of the sea is.
const DEPTH_SHADES := [0.0, 0.22, 0.36, 0.46, 0.55, 0.63, 0.71, 0.79, 0.86, 0.92, 0.96, 1.0]
const LOST_MARKER_SIZE := 26
## How far above a lost ship its "!" sits.
const LOST_MARKER_OFFSET := 12.0
## The ring (in the company's color) around the HQ's and hubs' ports.
const HQ_RING_WIDTH := 3.0
const HUB_RING_WIDTH := 2.0
## The red dot on an HQ or hub with an upgrade to buy: its size and where it
## sits from the port's center (up and to the right, outside the first ring of
## docked ships).
const HUB_ALERT_RADIUS := 4.5
const HUB_ALERT_OFFSET := Vector2(15, -15)
## The faint route lanes drawn with show_active_lanes.
const ACTIVE_LANE_ALPHA := 0.3
## Ore carriers' lanes are their gray map colors taken this far towards white,
## and drawn this opaque, so they show on the dark deep sea (the ships keep
## their gray).
const ORE_LANE_WHITEN := 0.65
const ORE_LANE_ALPHA := 0.55
## Kinds of named geography (WorldMapData.feature_label_kinds).
enum FeatureKind { OCEAN, SEA, STRAIT, RANGE, DESERT, LAKE, RIVER }
## How each kind is labeled: [font size, color name, slanted, extra letter
## spacing, zoom offset (added to the label's own min zoom, to keep the map
## from filling up with small lakes and rivers)].
const FEATURE_STYLES := {
	FeatureKind.OCEAN: [17, &"ocean_label", true, 3, 0.0],
	FeatureKind.SEA: [14, &"sea_label", true, 1, 0.0],
	FeatureKind.STRAIT: [12, &"sea_label", true, 0, 0.0],
	FeatureKind.RANGE: [12, &"range_label", false, 2, 0.0],
	FeatureKind.DESERT: [12, &"desert_label", false, 2, 0.0],
	FeatureKind.LAKE: [11, &"lake_label", true, 0, 1.0],
	FeatureKind.RIVER: [11, &"lake_label", true, 0, 1.5],
}
## Which kinds get placed first when labels would overlap (after ports and
## countries).
const FEATURE_PRIORITY: Array[int] = [FeatureKind.OCEAN, FeatureKind.SEA, FeatureKind.RANGE, FeatureKind.DESERT,
	FeatureKind.STRAIT, FeatureKind.LAKE, FeatureKind.RIVER]
## How far slanted labels lean (negative leans them right, as glyphs go up in -y).
const FEATURE_SLANT := -0.2
## Where an area's label may go if its best spot is taken, in label sizes
## (widths across, heights up and down), tried in order.
const FEATURE_LABEL_NUDGES: Array[Vector2] = [Vector2.ZERO, Vector2(0, -1.5), Vector2(0, 1.5), Vector2(-0.6, 0),
	Vector2(0.6, 0), Vector2(0, -3), Vector2(0, 3), Vector2(-0.6, -1.5), Vector2(0.6, 1.5)]
const NO_NUDGE: Array[Vector2] = [Vector2.ZERO]
## Width of the dark edge round ocean, sea and strait names.
const SEA_LABEL_OUTLINE := 3
## Width of the dark edge round ocean, sea and strait names.
const ACTIVE_LANE_WIDTH := 1.5
## Canals (data/canals.json): the channel's width in projected degrees (at
## least CANAL_MIN_WIDTH px), and each lock chamber's length and the width of
## each of its two lanes (one per direction), drawn from LOCK_MIN_ZOOM (pixels
## per degree). Ships in a canal keep to the right-hand lane.
const CANAL_WIDTH := 0.012
const CANAL_MIN_WIDTH := 1.5
const CHAMBER_LENGTH := 0.021
const CHAMBER_LANE_WIDTH := 0.009
const LOCK_MIN_ZOOM := 120.0
const LOCK_HIT_RADIUS := 14.0
## Canal names show from this web zoom level, until lock names take over at
## LOCK_LABEL_ZOOM (pixels per degree).
const CANAL_LABEL_WEB_ZOOM := 6.0
const LOCK_LABEL_ZOOM := 350.0
const CANAL_FONT_SIZE := 13
## Lock chamber water runs from this much darker than the ocean (low) to this
## much lighter (high) as it fills.
const LOCK_WATER_SHADE := 0.3
## Port colors in the price overlay (see price_commodity).
const PRICE_CHEAP := Color(0.2, 0.85, 0.3)
const PRICE_EXPENSIVE := Color(0.95, 0.2, 0.15)
## A convoy canal's doubled stretches: how far apart its two channels are
## (projected degrees); how close a click must be to its channel (px) or an
## anchorage; and how far apart ships at anchor sit (px).
const DOUBLE_CHANNEL_GAP := 0.012
const CANAL_HIT_RADIUS := 8.0
const ANCHORAGE_RADIUS := 30.0
const ANCHORAGE_SPACING := 14.0

const FALLBACK_COLORS := {
	&"ocean": Color(0.36, 0.59, 0.77),
	&"ocean_deep": Color(0.05, 0.14, 0.3),
	&"ocean_gray": Color(0.3, 0.31, 0.33),
	&"land": Color(0.78, 0.74, 0.6),
	&"land_gray": Color(0.5, 0.5, 0.5),
	&"coast": Color(0.35, 0.33, 0.25),
	&"coast_gray": Color(0.25, 0.25, 0.25),
	&"border": Color(0.5, 0.42, 0.35, 0.8),
	&"border_gray": Color(0.38, 0.38, 0.38),
	&"country_label": Color(0.3, 0.27, 0.2, 0.85),
	&"ocean_label": Color(0.8, 0.9, 1.0, 0.7),
	&"sea_label": Color(0.82, 0.91, 1.0, 0.75),
	&"range_label": Color(0.33, 0.25, 0.17, 0.9),
	&"desert_label": Color(0.55, 0.35, 0.16, 0.9),
	&"lake_label": Color(0.1, 0.3, 0.55, 0.95),
	&"sea_label_outline": Color(0.04, 0.12, 0.25, 0.55),
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
	&"river": Color(0.3, 0.5, 0.72),
	&"equator": Color(1, 1, 1, 0.22),
	&"equator_gray": Color(1, 1, 1, 0.12),
	&"hub_ring_gray": Color(0.75, 0.75, 0.75),
	&"hub_alert": Color(0.92, 0.22, 0.2),
	&"hub_alert_outline": Color(1, 1, 1),
	&"river_gray": Color(0.34, 0.35, 0.38),
	&"route": Color(1.0, 0.6, 0.15),
	&"lock_gate": Color(0.12, 0.1, 0.08),
}

## Draw with the muted palette used by the Route Assignment screen.
@export var gray_mode := false:
	set(value):
		gray_mode = value
		for art in _art_copies:
			art.queue_redraw()
		for tier in _river_tiers:
			tier.queue_redraw()
		queue_redraw()
		_redraw_layers()

## Draw the player's ships and let them be clicked.
@export var show_ships := false
## With show_ships: draw every lane the fleet's routes use, faintly, in each
## ship's color.
var show_active_lanes := false:
	set(value):
		show_active_lanes = value
		_static_layer.queue_redraw()

## Port ids drawn as a looping route along its sea lanes, each stop numbered.
var route: Array[String] = []:
	set(value):
		route = value
		_static_layer.queue_redraw()

## A commodity id to color ports by (green where it's cheap, red where it's
## expensive, against its world average), or "" for plain white ports.
var price_commodity := "":
	set(value):
		price_commodity = value
		_static_layer.queue_redraw()

## Port ids drawn grayed out, e.g. ports out of range in the route editor.
var dimmed_ports: Dictionary = {}:
	set(value):
		dimmed_ports = value
		_static_layer.queue_redraw()

var _center := Vector2.ZERO  # Map point shown at the middle of the view.
## Ship drawing caches: each docked ship's ring slot (and the frame it was for),
## the draw order (redone when the fleet changes) and each model's look.
var _dock_slots := {}
var _dock_slots_frame := -1
var _draw_order: Array[Ship] = []
var _draw_order_dirty := true
var _model_looks := {}
## Docked-ship dot images (see _dot_image()).
var _dock_dot_fill := _dot_image(0.0)
var _dock_dot_ring := _dot_image(1.0)
## Label placement for the current view ([port id, rect] and [text, rect] pairs),
## redone when _labels_key (the view and the hubs) changes.
var _port_labels := []
var _country_labels := []
## Placed labels for named geography: [index into WorldMapData.feature_label_*, rect].
var _feature_labels := []
## Feature label indices in placement priority (see FEATURE_PRIORITY), and a
## font per kind (slanted and spaced per FEATURE_STYLES); made on first use.
var _feature_order := PackedInt32Array()
var _feature_fonts := {}
var _labels_key := []
var _zoom := 1.0  # Screen pixels per projected degree.
var _has_fit := false
var _pressed_button: MouseButton = MOUSE_BUTTON_NONE
var _press_pos := Vector2.ZERO
var _dragging := false

## Holds the land art; its transform does the panning and zooming.
var _art_root := Node2D.new()
## One copy of the world art per wrap-around: west, center and east.
var _art_copies: Array[WorldArt] = []
## Every copy's river tiers, shown or hidden by zoom.
var _river_tiers: Array[RiverTier] = []
## Drawn in screen space in three layers, bottom to top: canals (every frame,
## for locks and convoys), the rest that only changes with the view, routes,
## hubs or prices (ports, labels, route lanes; see STATIC_REFRESH_S), and ships
## (every frame). _canvas is the layer being drawn, which the draw helpers use.
var _canal_layer := Control.new()
var _static_layer := Control.new()
var _overlay := Control.new()
var _canvas: Control = _overlay
var _static_clock := 0.0
var _ports_by_rank: Array = []  # Label priority order, sorted on first draw.


## Land, coastline, borders and the equator for one copy of the world. Drawn
## once and cached; panning and zooming only move its parent.
class WorldArt:
	extends Node2D

	var view: MapView
	var land_mesh: ArrayMesh
	var water_mesh: ArrayMesh
	var lake_island_mesh: ArrayMesh
	## Per depth band (WorldMapData.depth_levels): its sea, and the shallower
	## patches inside it.
	var depth_meshes: Array[ArrayMesh] = []
	var depth_hole_meshes: Array[ArrayMesh] = []
	var white: Texture2D
	var land_colors: Texture2D

	func _draw() -> void:
		var data := GameData.world_map
		# The sea darkens band by band with depth (the view's own background is
		# the shallowest); the gray route map keeps one flat sea.
		if not view.gray_mode:
			for band in depth_meshes.size():
				draw_mesh(depth_meshes[band], white, Transform2D.IDENTITY, view._depth_color(band + 1))
				draw_mesh(depth_hole_meshes[band], white, Transform2D.IDENTITY, view._depth_color(band))
		# Land in its real colors (see MapView.LAND_COLORS), or flat gray.
		var land_texture := white if view.gray_mode else land_colors
		var land_tint := view._color(&"land") if view.gray_mode else Color.WHITE
		draw_mesh(land_mesh, land_texture, Transform2D.IDENTITY, land_tint)
		draw_mesh(water_mesh, white, Transform2D.IDENTITY, view._color(&"ocean"))
		draw_mesh(lake_island_mesh, land_texture, Transform2D.IDENTITY, land_tint)
		draw_multiline(data.border_segments, view._color(&"border"), -1.0)
		draw_multiline(data.coast_segments, view._color(&"coast"), -1.0)
		# The equator (y = 0 in the projection), faint, across this copy of the world.
		draw_line(Vector2(-Geo.WORLD_WIDTH / 2.0, 0.0), Vector2(Geo.WORLD_WIDTH / 2.0, 0.0), view._color(&"equator"), -1.0)


## One zoom tier of rivers for one copy of the world, shown once the view is
## zoomed in to its min_zoom (see _update_rivers()).
class RiverTier:
	extends Node2D

	var view: MapView
	var segments: PackedVector2Array
	var min_zoom := 0.0

	func _draw() -> void:
		draw_multiline(segments, view._color(&"river"), -1.0)


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	GameState.ships_changed.connect(func() -> void: _draw_order_dirty = true)

	var data := GameData.world_map
	var land_mesh := _triangle_mesh(data.land_triangles)
	var water_mesh := _triangle_mesh(data.water_triangles)
	var lake_island_mesh := _triangle_mesh(data.lake_island_triangles)
	var depth_meshes: Array[ArrayMesh] = []
	var depth_hole_meshes: Array[ArrayMesh] = []
	for band in data.depth_levels.size():
		depth_meshes.append(_triangle_mesh(data.depth_triangles[band]))
		depth_hole_meshes.append(_triangle_mesh(data.depth_hole_triangles[band]))
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(image)
	var land_colors: Texture2D = load(LAND_COLORS) if ResourceLoader.exists(LAND_COLORS) else white
	# The land colors are drawn far below their size when zoomed out.
	_art_root.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_art_root)
	for copy in [-1, 0, 1]:
		var art := WorldArt.new()
		art.view = self
		art.land_mesh = land_mesh
		art.water_mesh = water_mesh
		art.lake_island_mesh = lake_island_mesh
		art.depth_meshes = depth_meshes
		art.depth_hole_meshes = depth_hole_meshes
		art.white = white
		art.land_colors = land_colors
		art.position.x = copy * Geo.WORLD_WIDTH
		_art_root.add_child(art)
		_art_copies.append(art)
		for i in data.river_tiers.size():
			var tier := RiverTier.new()
			tier.view = self
			tier.segments = data.river_tiers[i]
			tier.min_zoom = data.river_tier_min_zoom[i]
			art.add_child(tier)
			_river_tiers.append(tier)

	for layer: Control in [_canal_layer, _static_layer, _overlay]:
		layer.mouse_filter = MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(PRESET_FULL_RECT)
		add_child(layer)
	_canal_layer.draw.connect(_draw_canal_layer)
	_static_layer.draw.connect(_draw_static_layer)
	_overlay.draw.connect(_draw_overlay)
	# Ship art is drawn well below its size at most zooms: mipmaps keep it smooth.
	_overlay.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(delta: float) -> void:
	if not show_ships or not is_visible_in_tree():
		return
	_canal_layer.queue_redraw()
	_overlay.queue_redraw()
	# Route lanes follow the ships' legs, hub rings the hubs and port colors the
	# drifting prices: a few times a second is plenty.
	_static_clock += delta
	if _static_clock >= STATIC_REFRESH_S:
		_static_clock = 0.0
		_static_layer.queue_redraw()


## A mesh of map triangles, with each point's place on LAND_COLORS as its UV
## (the texture spans x -180 to 180 and y Geo.MAX_LAT down to -Geo.MAX_LAT).
func _triangle_mesh(triangles: PackedVector2Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if triangles.is_empty():
		return mesh
	var top := Geo.project(Vector2(0.0, Geo.MAX_LAT)).y
	var uvs := PackedVector2Array()
	uvs.resize(triangles.size())
	for i in triangles.size():
		var p := triangles[i]
		uvs[i] = Vector2((p.x + Geo.WORLD_WIDTH / 2.0) / Geo.WORLD_WIDTH, (top - p.y) / (2.0 * top))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The sea's color for a depth band: 0 is the shallowest (the continental
## shelf, the view's background), then each of WorldMapData.depth_levels, darker
## by DEPTH_SHADES towards ocean_deep.
func _depth_color(band: int) -> Color:
	return _color(&"ocean").lerp(_color(&"ocean_deep"), DEPTH_SHADES[mini(band, DEPTH_SHADES.size() - 1)])


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


## Docked ships are dots spread in rings around their port, in fleet order,
## so they don't cover it or each other.
func ship_screen_position(ship: Ship) -> Vector2:
	if ship.is_carried():
		return _carried_screen_position(ship)
	if not ship.is_docked():
		if ship.canal_state in [Ship.CANAL_ANCHORED, Ship.CANAL_CONVOY, Ship.CANAL_TOLL]:
			var crossing := GameData.crossing_ahead(ship.from_port, ship.to_port, ship.traveled_nm)
			if not crossing.is_empty() and crossing.canal.get("type", "") == "convoy":
				return _anchorage_slot_position(ship, crossing)
		return world_to_screen(ship.world_position()) + _canal_lane_offset(ship)
	var slot := _dock_slot(ship)
	var radius := _port_radius(ship.docked_at) + DOCK_FIRST_RING_GAP
	var per_ring := floori(TAU * radius / DOCK_DOT_SPACING)
	while slot >= per_ring:
		slot -= per_ring
		radius += DOCK_RING_GAP
		per_ring = floori(TAU * radius / DOCK_DOT_SPACING)
	var angle := -PI / 2.0 + TAU * slot / per_ring
	return port_screen_position(ship.docked_at) + Vector2.from_angle(angle) * radius


## A carried ship rides on its recovery boat's work deck (CARRY_DECK_X), behind
## the boat's middle, so the wheelhouse stays in view.
func _carried_screen_position(ship: Ship) -> Vector2:
	var boat := ship.rescuer
	var rect: Rect2 = _model_look(boat.model_id)[7]
	var direction := boat.heading()
	var angle := Vector2(direction.x, -direction.y).angle() if direction != Vector2.ZERO else 0.0
	var along := rect.position.x + rect.size.x * CARRY_DECK_X / SHIP_ART_WIDTH
	return ship_screen_position(boat) + Vector2(along, 0.0).rotated(angle) * _ship_scale()


## A docked ship's place in its port's rings: how many of the fleet before it are
## docked there. Worked out for the whole fleet once a frame.
func _dock_slot(ship: Ship) -> int:
	var frame := Engine.get_process_frames()
	if frame != _dock_slots_frame:
		_dock_slots_frame = frame
		_dock_slots.clear()
		var counts := {}
		for other in GameState.ships:
			if other.is_docked():
				var count: int = counts.get(other.docked_at, 0)
				_dock_slots[other] = count
				counts[other.docked_at] = count + 1
	return _dock_slots.get(ship, 0)

## Centers the view on a port, keeping the zoom.
func focus_port(port_id: String) -> void:
	_center = GameData.port_position(port_id)
	_changed()


## Brings a ship (its port while docked) into view, keeping the zoom: centered
## across, and raised_px above the middle (to leave room for its popup below).
func focus_ship(ship: Ship, raised_px := 0.0) -> void:
	_center = GameData.port_position(ship.docked_at) if ship.is_docked() else ship.world_position()
	_center.y -= raised_px / _zoom
	_changed()


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


## Picks whichever port or ship is closest to the click, within its hit radius,
## or else a canal lock under it.
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
		for ship in _ships_topmost_first():
			var dist := ship_screen_position(ship).distance_to(screen_pos)
			if dist <= SHIP_HIT_RADIUS * _ship_scale() and dist < nearest_dist:
				nearest_dist = dist
				nearest_ship = ship
	if nearest_ship:
		ship_clicked.emit(nearest_ship)
	elif not nearest_port.is_empty():
		port_clicked.emit(nearest_port)
	elif not _lock_at(screen_pos).is_empty():
		var lock := _lock_at(screen_pos)
		lock_clicked.emit(lock[0], lock[1])
	elif not _convoy_canal_at(screen_pos).is_empty():
		canal_clicked.emit(_convoy_canal_at(screen_pos))
	else:
		empty_clicked.emit()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var anchor := screen_to_world(screen_pos)
	_zoom = clampf(_zoom * factor, _min_zoom(), MAX_ZOOM)
	# Keep the map point under the cursor fixed.
	_center += anchor - screen_to_world(screen_pos)
	_changed()


## Shows each river tier once the view is zoomed in to its min_zoom (in
## web-map zoom levels, like the country names).
func _update_rivers() -> void:
	var web_zoom := _web_zoom()
	for tier in _river_tiers:
		tier.visible = web_zoom >= tier.min_zoom


## The view's zoom as a web-map zoom level (0 = whole world in 256 px).
func _web_zoom() -> float:
	return log(_zoom * Geo.WORLD_WIDTH / 256.0) / log(2.0)


func _changed() -> void:
	_center.x = wrapf(_center.x, -Geo.WORLD_WIDTH / 2.0, Geo.WORLD_WIDTH / 2.0)
	var max_y := Geo.project(Vector2(0, MAX_VIEW_LAT)).y
	_center.y = clampf(_center.y, -max_y, max_y)
	_art_root.position = size / 2.0 + Vector2(-_center.x, _center.y) * _zoom
	_art_root.scale = Vector2(_zoom, -_zoom)
	_update_rivers()
	queue_redraw()
	_redraw_layers()
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


func _redraw_layers() -> void:
	_canal_layer.queue_redraw()
	_static_layer.queue_redraw()
	_overlay.queue_redraw()


func _draw_canal_layer() -> void:
	_canvas = _canal_layer
	_draw_canals()


func _draw_static_layer() -> void:
	_canvas = _static_layer
	# Where labels go only changes with the view (or the hubs), not every frame.
	var key := [_center, _zoom, size, GameState.hubs.map(func(hub: Hub) -> String: return hub.port_id)]
	if key != _labels_key:
		_labels_key = key
		var placed_labels: Array[Rect2] = []
		_port_labels = _place_port_labels(placed_labels)
		_country_labels = _place_country_labels(placed_labels)
		_feature_labels = [] if gray_mode else _place_feature_labels(placed_labels)
	_draw_feature_labels()
	_draw_country_labels()
	if show_ships and show_active_lanes:
		_draw_active_lanes()
	_draw_route()
	_draw_ports(_port_labels)


func _draw_overlay() -> void:
	_canvas = _overlay
	if show_ships:
		_draw_ships()
		_draw_hub_alerts()


## Port labels, the HQ's and hubs' first and then in rank order, skipping any
## that would overlap one already placed.
## Returns [port id, label rect] pairs.
func _place_port_labels(placed: Array[Rect2]) -> Array:
	var font := get_theme_default_font()
	if _ports_by_rank.is_empty():
		_ports_by_rank = GameData.ports.duplicate()
		_ports_by_rank.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.get("rank", 999) < b.get("rank", 999))
	# The HQ and hubs get their names placed first, then the rest by rank.
	var hub_ports := {}
	for hub in GameState.hubs:
		hub_ports[hub.port_id] = true
	var ranked := _ports_by_rank.filter(func(port: Dictionary) -> bool: return hub_ports.has(port.id))
	ranked.append_array(_ports_by_rank.filter(func(port: Dictionary) -> bool: return not hub_ports.has(port.id)))
	var labels := []
	var bounds := Rect2(Vector2.ZERO, size)
	for port: Dictionary in ranked:
		var pos := port_screen_position(port.id)
		var text_size := font.get_string_size(port.name, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE)
		var rect := Rect2(pos + Vector2(-text_size.x / 2.0, _port_radius(port.id) + 2.0), text_size)
		if not bounds.intersects(rect) or _overlaps(rect, placed):
			continue
		placed.append(rect.grow(LABEL_PADDING))
		labels.append([port.id, rect])
	return labels


## Country names that fit around the port labels already placed: [text, rect] pairs.
func _place_country_labels(placed: Array[Rect2]) -> Array:
	var data := GameData.world_map
	var font := get_theme_default_font()
	var web_zoom := _web_zoom()
	var labels := []
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
		labels.append([text, rect])
	return labels


## Named geography labels that fit around the ones already placed, most
## important kind first (FEATURE_PRIORITY): [index, rect] pairs. Each shows
## from its min zoom plus its kind's zoom offset (FEATURE_STYLES).
func _place_feature_labels(placed: Array[Rect2]) -> Array:
	var data := GameData.world_map
	if _feature_order.is_empty():
		var order := range(data.feature_label_names.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var rank_a := FEATURE_PRIORITY.find(data.feature_label_kinds[a])
			var rank_b := FEATURE_PRIORITY.find(data.feature_label_kinds[b])
			return rank_a < rank_b if rank_a != rank_b else data.feature_label_min_zoom[a] < data.feature_label_min_zoom[b])
		_feature_order = PackedInt32Array(order)
	var web_zoom := _web_zoom()
	var bounds := Rect2(Vector2.ZERO, size)
	var labels := []
	for i in _feature_order:
		var kind := data.feature_label_kinds[i]
		var style: Array = FEATURE_STYLES[kind]
		if data.feature_label_min_zoom[i] + style[4] > web_zoom:
			continue
		var text_size := _feature_font(kind).get_string_size(data.feature_label_names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, style[0])
		var center := world_to_screen(data.feature_label_positions[i])
		# Areas may shift a little if their best spot is taken (by
		# FEATURE_LABEL_NUDGES label sizes); a river label stays on its river.
		var nudges: Array[Vector2] = NO_NUDGE if kind == FeatureKind.RIVER else FEATURE_LABEL_NUDGES
		for nudge: Vector2 in nudges:
			var rect := Rect2(center + nudge * text_size - text_size / 2.0, text_size)
			if bounds.encloses(rect) and not _overlaps(rect, placed):
				placed.append(rect.grow(LABEL_PADDING))
				labels.append([i, rect])
				break
	return labels


func _draw_feature_labels() -> void:
	var data := GameData.world_map
	for label: Array in _feature_labels:
		var kind := data.feature_label_kinds[label[0]]
		var style: Array = FEATURE_STYLES[kind]
		var font := _feature_font(kind)
		var rect: Rect2 = label[1]
		var baseline := rect.position + Vector2(0, font.get_ascent(style[0]))
		var text: String = data.feature_label_names[label[0]]
		# Pale sea names get a dark edge, so they read over shallow (light) water too.
		if kind in [FeatureKind.OCEAN, FeatureKind.SEA, FeatureKind.STRAIT]:
			_canvas.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, style[0], SEA_LABEL_OUTLINE,
				_color(&"sea_label_outline"))
		_canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, style[0], _color(style[1]))


## The theme font, slanted (water, like an atlas) and letter-spaced as the
## kind's style says.
func _feature_font(kind: int) -> Font:
	if not _feature_fonts.has(kind):
		var style: Array = FEATURE_STYLES[kind]
		var font := FontVariation.new()
		font.base_font = get_theme_default_font()
		if style[2]:
			font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(FEATURE_SLANT, 1.0), Vector2.ZERO)
		font.spacing_glyph = style[3]
		_feature_fonts[kind] = font
	return _feature_fonts[kind]


func _draw_country_labels() -> void:
	var font := get_theme_default_font()
	var color := _color(&"country_label")
	var ascent := font.get_ascent(COUNTRY_FONT_SIZE)
	for label: Array in _country_labels:
		var rect: Rect2 = label[1]
		_canvas.draw_string(font, rect.position + Vector2(0, ascent), label[0], HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTRY_FONT_SIZE, color)


func _overlaps(rect: Rect2, placed: Array[Rect2]) -> bool:
	for other in placed:
		if rect.intersects(other):
			return true
	return false


## A port's color for price_commodity: green at half its world average price
## or less, white at the average, red at twice it or more.
func _price_color(port_id: String) -> Color:
	var ratio := GameState.market.sell_price(port_id, price_commodity) / GameData.world_price(price_commodity)
	var t := clampf(log(ratio) / log(2.0), -1.0, 1.0)
	return Color.WHITE.lerp(PRICE_CHEAP if t < 0.0 else PRICE_EXPENSIVE, absf(t))


func _port_radius(port_id: String) -> float:
	var port_size: float = GameState.port_sizes.size(port_id)
	if port_size <= PORT_RADIUS_SIZE:
		return lerpf(PORT_RADIUS_MIN, PORT_RADIUS, (port_size - 1.0) / (PORT_RADIUS_SIZE - 1.0))
	return lerpf(PORT_RADIUS, PORT_RADIUS_MAX, (port_size - PORT_RADIUS_SIZE) / (100.0 - PORT_RADIUS_SIZE))


func _draw_ports(labels: Array) -> void:
	var font := get_theme_default_font()
	var fill := _color(&"port")
	var dimmed := _color(&"port_dimmed")
	var outline := _color(&"port_outline")
	var label_color := _color(&"label")
	var shadow := _color(&"label_shadow")
	var visible_area := Rect2(Vector2.ZERO, size).grow(PORT_RADIUS_MAX + 4.0)
	var draw_port := func(port_id: String) -> void:
		var pos := port_screen_position(port_id)
		if not visible_area.has_point(pos):
			return
		var port_fill := fill if price_commodity.is_empty() else _price_color(port_id)
		var radius := _port_radius(port_id)
		_canvas.draw_circle(pos, radius, dimmed if dimmed_ports.has(port_id) else port_fill)
		_canvas.draw_arc(pos, radius, 0.0, TAU, 24, outline, 1.5, true)
	for port: Dictionary in GameData.ports:
		if not GameState.hub_at(port.id):
			draw_port.call(port.id)
	# The HQ and hubs go on top of the other ports, each with a ring in the
	# company's color (heavier for the HQ).
	var ring_color := _color(&"hub_ring_gray") if gray_mode else GameState.company_color_value()
	for hub in GameState.hubs:
		draw_port.call(hub.port_id)
		var width := HQ_RING_WIDTH if hub.is_hq else HUB_RING_WIDTH
		_canvas.draw_arc(port_screen_position(hub.port_id), _port_radius(hub.port_id) + 1.0 + width / 2.0, 0.0, TAU, 32, ring_color, width, true)
	for label: Array in labels:
		var rect: Rect2 = label[1]
		var baseline := rect.position + Vector2(0, font.get_ascent(PORT_FONT_SIZE))
		var text: String = GameData.port_name(label[0])
		var color := dimmed if dimmed_ports.has(label[0]) else label_color
		_canvas.draw_string(font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, shadow)
		_canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, color)


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
		var pos := port_screen_position(port_id) + Vector2(-width / 2.0, -_port_radius(port_id) - 5.0)
		_canvas.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, shadow)
		_canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, color)


## Every lane the fleet sails: each cargo ship's route loop, any route waiting
## to replace it, and the leg it's on now. A lane shared by several ships is
## drawn once, in the first one's color (see ORE_LANE_WHITEN).
func _draw_active_lanes() -> void:
	var lanes := {}  # "A-B" (sorted) -> [from, to, color]
	for ship in GameState.ships:
		if ship.is_recovery():
			continue
		var color := Color.from_string(ship.model().get("map_color", "#ffffff"), Color.WHITE)
		color.a = ACTIVE_LANE_ALPHA
		if ship.model().get("category", "") == "ore":
			color = color.lerp(Color.WHITE, ORE_LANE_WHITEN)
			color.a = ORE_LANE_ALPHA
		var legs: Array = []
		for stops: Array[String] in [ship.route, ship.pending_route]:
			for i in stops.size():
				if stops.size() >= 2:
					legs.append([stops[i], stops[(i + 1) % stops.size()]])
		if not ship.is_docked() and not ship.is_on_job():
			legs.append([ship.from_port, ship.to_port])
		for leg: Array in legs:
			var key := "%s-%s" % ([leg[0], leg[1]] if leg[0] < leg[1] else [leg[1], leg[0]])
			if not lanes.has(key):
				lanes[key] = [leg[0], leg[1], color]
	for lane: Array in lanes.values():
		_draw_lane(lane[0], lane[1], lane[2], false, ACTIVE_LANE_WIDTH)


func _draw_lane(from_port: String, to_port: String, color: Color, dashed: bool, width := 2.5) -> void:
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
			_canvas.draw_dashed_line(points[i - 1], points[i], color, width, 8.0)
	else:
		_canvas.draw_polyline(points, color, width, true)


## Each canal as a water channel across the land (a convoy canal doubled where
## it has two channels). Zoomed in, lock chambers too (one lane per slot, the
## water rising or falling with a ship inside), convoy anchorages with the time
## to the next convoy, and names: the canal's, then its locks' and places'.
func _draw_canals() -> void:
	var view := Rect2(Vector2.ZERO, size).grow(40.0)
	for canal in GameData.canals:
		var points := _canal_screen_path(canal)
		var bounds := Rect2(points[0], Vector2.ZERO)
		for p in points:
			bounds = bounds.expand(p)
		if not view.intersects(bounds.grow(1.0)):
			continue
		var width := maxf(CANAL_WIDTH * _zoom, CANAL_MIN_WIDTH)
		if canal.get("type", "") == "convoy":
			_draw_convoy_channel(canal, points, width)
		else:
			_canvas.draw_polyline(points, _color(&"ocean"), width, true)
		if _zoom >= LOCK_MIN_ZOOM:
			for chamber: Dictionary in canal.chambers:
				_draw_chamber(canal, chamber, points)
			if canal.get("type", "") == "convoy":
				_draw_anchorage_labels(canal)
		if _zoom >= LOCK_LABEL_ZOOM:
			for lock_index in canal.get("locks", []).size():
				var center := lock_screen_position(canal.id, lock_index)
				_draw_canal_label(canal.locks[lock_index].name, center + Vector2(CHAMBER_LANE_WIDTH * _zoom * 1.5 + 6.0, 4.0))
			for label: Array in canal.get("labels", []):
				_draw_canal_label(label[0], world_to_screen(Geo.project(Vector2(label[1], label[2]))))
		elif _web_zoom() >= CANAL_LABEL_WEB_ZOOM:
			_draw_canal_label(canal.name, points[floori(points.size() / 2.0)] + Vector2(8.0, 4.0))


## A convoy canal's channel: one line in the single-lane stretches, two side by
## side (DOUBLE_CHANNEL_GAP apart) in the doubled ones.
func _draw_convoy_channel(canal: Dictionary, points: PackedVector2Array, width: float) -> void:
	var water := _color(&"ocean")
	var gap := DOUBLE_CHANNEL_GAP * _zoom / 2.0
	var previous := 0
	for pair: Array in canal.get("double", []):
		var i := int(pair[0])
		var j := int(pair[1])
		if i > previous:
			_canvas.draw_polyline(points.slice(previous, i + 1), water, width, true)
		for side: float in [-1.0, 1.0]:
			var offset := PackedVector2Array()
			for k in range(i, j + 1):
				offset.append(points[k] + _path_normal(points, k) * gap * side)
			_canvas.draw_polyline(offset, water, width, true)
		previous = j
	if previous < points.size() - 1:
		_canvas.draw_polyline(points.slice(previous), water, width, true)


## Unit vector to the right of a path at point k (on screen).
static func _path_normal(points: PackedVector2Array, k: int) -> Vector2:
	var along := (points[mini(k + 1, points.size() - 1)] - points[maxi(k - 1, 0)]).normalized()
	return Vector2(-along.y, along.x)


## "Port Said anchorage · next convoy 45 s" by each anchorage.
func _draw_anchorage_labels(canal: Dictionary) -> void:
	var names: Array = canal.get("anchorage_names", [])
	var next := Fmt.duration(ceilf(GameState.canal_traffic.next_convoy_in(canal)))
	for i in canal.get("anchorages", []).size():
		var at := _anchorage_screen_position(canal, i == 0)
		_draw_canal_label("%s · next convoy %s" % [names[i] if i < names.size() else "Anchorage", next], at + Vector2(14.0, -10.0))


func _anchorage_screen_position(canal: Dictionary, forward: bool) -> Vector2:
	var point: Array = canal.anchorages[0 if forward else 1]
	return world_to_screen(Geo.project(Vector2(point[0], point[1])))


## A canal's path on screen, shifted as a whole to the copy of the world nearest the view.
func _canal_screen_path(canal: Dictionary) -> PackedVector2Array:
	var path: PackedVector2Array = canal.projected_path
	var shift := _wrap_near(path[0].x, _center.x) - path[0].x
	var points := PackedVector2Array()
	for p in path:
		points.append(size / 2.0 + Vector2(p.x + shift - _center.x, _center.y - p.y) * _zoom)
	return points


## One lock chamber: a lane per slot side by side (with a lane each way, ships
## keep right; shared chambers are one lane each), walled, with gates at both ends.
func _draw_chamber(canal: Dictionary, chamber: Dictionary, points: PackedVector2Array) -> void:
	var i: int = chamber.path_index
	var center := points[i]
	var across := _path_normal(points, i)  # Right of a ship sailing along the path.
	var along := Vector2(across.y, -across.x)
	var half := along * CHAMBER_LENGTH * _zoom / 2.0
	var lane := across * CHAMBER_LANE_WIDTH * _zoom
	var slots := GameData.chamber_slots(canal, chamber)
	var lanes := float(slots.size())
	for k in slots.size():
		var offset := lane * (float(k) - (lanes - 1.0) / 2.0)
		if slots[k] in ["f", "b"]:
			offset = lane * (0.5 if slots[k] == "f" else -0.5)
		var water := _color(&"ocean")
		var level := GameState.canal_traffic.slot_level(canal, chamber, slots[k])
		var color := water.darkened(LOCK_WATER_SHADE).lerp(water.lightened(LOCK_WATER_SHADE), level)
		var c := center + offset
		_canvas.draw_colored_polygon(PackedVector2Array([c - half - lane / 2.0, c + half - lane / 2.0,
			c + half + lane / 2.0, c - half + lane / 2.0]), color)
	var outer := lane * lanes / 2.0
	var wall := _color(&"coast")
	_canvas.draw_polyline(PackedVector2Array([center - half - outer, center + half - outer, center + half + outer,
		center - half + outer, center - half - outer]), wall, 1.0, true)
	for k in range(1, slots.size()):
		var divider := lane * (float(k) - lanes / 2.0)
		_canvas.draw_line(center - half + divider, center + half + divider, wall, 1.0, true)
	var gate := _color(&"lock_gate")
	for end: Vector2 in [center - half, center + half]:
		_canvas.draw_line(end - outer, end + outer, gate, 2.0, true)


func _draw_canal_label(text: String, at: Vector2) -> void:
	var font := get_theme_default_font()
	_canvas.draw_string(font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, CANAL_FONT_SIZE, _color(&"label_shadow"))
	_canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, CANAL_FONT_SIZE, _color(&"label"))


## The middle of a lock's chambers on screen.
func lock_screen_position(canal_id: String, lock_index: int) -> Vector2:
	var total := Vector2.ZERO
	var count := 0
	for chamber: Dictionary in GameData.get_canal(canal_id).get("chambers", []):
		if chamber.lock == lock_index:
			total += world_to_screen(chamber.position)
			count += 1
	return total / count if count > 0 else Vector2.ZERO


## Where a convoy canal's popup sits: the middle of its path.
func canal_screen_position(canal_id: String) -> Vector2:
	var points := _canal_screen_path(GameData.get_canal(canal_id))
	return points[floori(points.size() / 2.0)] if not points.is_empty() else Vector2.ZERO


## [canal id, lock index] of the lock under a screen point, or [] (only once
## the chambers are drawn).
func _lock_at(screen_pos: Vector2) -> Array:
	if _zoom < LOCK_MIN_ZOOM:
		return []
	for canal in GameData.canals:
		for lock_index in canal.get("locks", []).size():
			var center := lock_screen_position(canal.id, lock_index)
			var reach := LOCK_HIT_RADIUS
			for chamber: Dictionary in canal.chambers:
				if chamber.lock == lock_index:
					reach = maxf(reach, world_to_screen(chamber.position).distance_to(center) + CHAMBER_LENGTH * _zoom / 2.0)
			if center.distance_to(screen_pos) <= reach:
				return [canal.id, lock_index]
	return []


## The convoy canal whose channel or anchorages are under a screen point, or "".
func _convoy_canal_at(screen_pos: Vector2) -> String:
	for canal in GameData.canals:
		if canal.get("type", "") != "convoy":
			continue
		var points := _canal_screen_path(canal)
		for k in range(1, points.size()):
			var closest := Geometry2D.get_closest_point_to_segment(screen_pos, points[k - 1], points[k])
			if closest.distance_to(screen_pos) <= CANAL_HIT_RADIUS:
				return canal.id
		for forward: bool in [true, false]:
			if _anchorage_screen_position(canal, forward).distance_to(screen_pos) <= ANCHORAGE_RADIUS:
				return canal.id
	return ""


## Ships waiting for a convoy sit in a cluster round their anchorage, in rings.
func _anchorage_slot_position(ship: Ship, crossing: Dictionary) -> Vector2:
	var traffic := GameState.canal_traffic
	var waiting: Array = traffic.anchored_ships(crossing.canal, crossing.forward) + traffic.released_ships(crossing.canal, crossing.forward)
	var slot := maxi(waiting.find(ship), 0)
	var radius := ANCHORAGE_SPACING
	var per_ring := 6
	while slot >= per_ring:
		slot -= per_ring
		radius += ANCHORAGE_SPACING
		per_ring += 6
	var angle := TAU * slot / per_ring
	return _anchorage_screen_position(crossing.canal, crossing.forward) + Vector2.from_angle(angle) * radius


## How far a ship in a canal sits to the side of the path: in the right-hand
## lane of each-way locks and doubled convoy channels, in its own chamber of
## a shared lock, and in the middle of single-lane stretches (a ship riding on
## a recovery boat follows the boat).
func _canal_lane_offset(ship: Ship) -> Vector2:
	var sailing := ship.rescuer if ship.is_carried() else ship
	if sailing.is_docked() or sailing.from_port.is_empty():
		return Vector2.ZERO
	var crossing := GameData.crossing_at(sailing.from_port, sailing.to_port, sailing.traveled_nm)
	if crossing.is_empty():
		return Vector2.ZERO
	var direction := sailing.heading()
	if direction == Vector2.ZERO:
		return Vector2.ZERO
	var on_screen := Vector2(direction.x, -direction.y).normalized()
	var right := Vector2(-on_screen.y, on_screen.x)
	var canal: Dictionary = crossing.canal
	if canal.get("type", "") == "convoy":
		if GameData.in_single_stretch(canal, GameData.canal_s(crossing, sailing.traveled_nm)):
			return Vector2.ZERO
		return right * DOUBLE_CHANNEL_GAP * _zoom / 2.0
	var chamber := sailing.lock_chamber()
	if not chamber.is_empty() and chamber.canal.locks[chamber.lock].get("lanes", "each_way") == "shared":
		var slots := GameData.chamber_slots(chamber.canal, chamber)
		var offset := (float(slots.find(sailing.lock_slot)) - (slots.size() - 1) / 2.0) * CHAMBER_LANE_WIDTH * _zoom
		return right * (offset if chamber.forward else -offset)
	return right * CHAMBER_LANE_WIDTH * _zoom / 2.0


## A red dot (like the nav tabs') by each HQ or hub with an upgrade that can be
## bought now. Drawn after the ships so docked ships don't hide it.
func _draw_hub_alerts() -> void:
	for hub in GameState.hubs:
		if GameState.hub_can_upgrade(hub):
			var dot := port_screen_position(hub.port_id) + HUB_ALERT_OFFSET
			_canvas.draw_circle(dot, HUB_ALERT_RADIUS + 1.0, _color(&"hub_alert_outline"), true, -1.0, true)
			_canvas.draw_circle(dot, HUB_ALERT_RADIUS, _color(&"hub_alert"), true, -1.0, true)


## Ships at sea are rectangles with a pointed bow; docked ships are small dots.
## Smaller ships are drawn over bigger ones.
## Ships riding on a recovery boat are drawn after it, so they sit in its
## middle. Lost ships get a red "!" above them, and ships that won't make it
## to port an amber one.
func _draw_ships() -> void:
	var outline := _color(&"ship_outline")
	for ship in _ships_biggest_first():
		if not ship.is_carried():
			_draw_ship(ship, outline)
	for ship in GameState.ships:
		if ship.is_carried():
			_draw_ship(ship, outline)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	for ship in GameState.ships:
		if ship.is_lost() and not ship.is_carried():
			_draw_marker(ship_screen_position(ship), _color(&"lost_marker"))
		elif ship.at_risk:
			_draw_marker(ship_screen_position(ship), _color(&"at_risk_marker"))


## Ships top-drawn first, so a click on overlapping ships picks the one on top.
func _ships_topmost_first() -> Array[Ship]:
	var order := _ships_biggest_first().duplicate()
	order.reverse()
	return order


## Ships in drawing order: biggest (by map length) first, so smaller ships are
## drawn on top of bigger ones; same-sized ships keep their fleet order. Kept
## until the fleet changes.
func _ships_biggest_first() -> Array[Ship]:
	if _draw_order.size() == GameState.ships.size() and not _draw_order_dirty:
		return _draw_order
	_draw_order_dirty = false
	var order: Array[Ship] = GameState.ships.duplicate()
	var index := {}
	for i in order.size():
		index[order[i]] = i
	order.sort_custom(func(a: Ship, b: Ship) -> bool:
		var length_a := float(a.model().get("map_size", [0])[0])
		var length_b := float(b.model().get("map_size", [0])[0])
		return length_a > length_b if length_a != length_b else index[a] < index[b])
	_draw_order = order
	return order


func _draw_ship(ship: Ship, outline: Color) -> void:
	var look := _model_look(ship.model_id)
	var color: Color = look[0]
	if ship.is_docked():
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		var at := ship_screen_position(ship)
		# Stamped from two small images made once (antialiased circles are costly
		# to build each frame): the dot in the model's color, then its outline.
		var rect := Rect2(at - Vector2.ONE * DOCK_DOT_IMAGE_RADIUS, Vector2.ONE * DOCK_DOT_IMAGE_RADIUS * 2.0)
		_canvas.draw_texture_rect(_dock_dot_fill, rect, false, color)
		_canvas.draw_texture_rect(_dock_dot_ring, rect, false, outline)
		return
	var direction := ship.heading()
	var angle := Vector2(direction.x, -direction.y).angle() if direction != Vector2.ZERO else 0.0
	_canvas.draw_set_transform(ship_screen_position(ship), angle, Vector2.ONE * _ship_scale())
	var art: Dictionary = look[6]
	if not art.is_empty():
		_draw_ship_art(ship, art, look[7], color)
		return
	# The hull as a quad and the bow as a triangle: simple shapes Godot needn't
	# triangulate each frame, unlike a general polygon.
	var colors := PackedColorArray([color])
	_canvas.draw_primitive(look[3], colors, PackedVector2Array())
	_canvas.draw_primitive(look[4], colors, PackedVector2Array())
	_canvas.draw_polyline(look[5], outline, 1.0)


## The hull in the model's color, the cargo (cut off behind how full the hold
## is, in CARGO_STEPS steps, any cargo showing at least one) and the details.
func _draw_ship_art(ship: Ship, art: Dictionary, rect: Rect2, color: Color) -> void:
	_canvas.draw_texture_rect(art.hull, rect, false, color)
	var level := ship.cargo_level()
	if art.has("cargo") and level > 0.0:
		var zone: Vector2 = art.zone
		var fill := ceilf(level * CARGO_STEPS) / CARGO_STEPS
		var share := (zone.x + fill * (zone.y - zone.x)) / SHIP_ART_WIDTH
		var texture: Texture2D = art.cargo
		_canvas.draw_texture_rect_region(texture, Rect2(rect.position, Vector2(rect.size.x * share, rect.size.y)),
			Rect2(Vector2.ZERO, Vector2(texture.get_width() * share, texture.get_height())))
	_canvas.draw_texture_rect(art.details, rect, false)


## How many times its map_size a ship at sea is drawn at this zoom.
func _ship_scale() -> float:
	return clampf(sqrt(_zoom / SHIP_GROW_FROM_ZOOM), 1.0, SHIP_MAX_SCALE)


## A model category's art ({hull, details} plus {cargo, zone} if its cargo
## shows), or {} if it has none.
static func load_ship_art(category: String) -> Dictionary:
	var path := SHIP_ART_DIR + category + "_%s.svg"
	if not ResourceLoader.exists(path % "hull") or not ResourceLoader.exists(path % "details"):
		return {}
	var art := {hull = load(path % "hull"), details = load(path % "details")}
	if CARGO_ZONES.has(category) and ResourceLoader.exists(path % "cargo"):
		art.cargo = load(path % "cargo")
		art.zone = CARGO_ZONES[category]
	return art


## A white circle image for docked-ship dots: filled (ring_width 0) or just its
## outline, antialiased, 2 x DOCK_DOT_IMAGE_RADIUS across, and drawn
## at 4x resolution for smooth edges when scaled down.
static func _dot_image(ring_width: float) -> ImageTexture:
	var oversample := 4.0
	var pixels := int(ceilf(DOCK_DOT_IMAGE_RADIUS * 2.0 * oversample))
	var image := Image.create(pixels, pixels, false, Image.FORMAT_RGBA8)
	var center := Vector2.ONE * pixels / 2.0
	for y in pixels:
		for x in pixels:
			var d := (Vector2(x + 0.5, y + 0.5) - center).length() / oversample
			var alpha := clampf(DOCK_DOT_RADIUS + 0.5 - d, 0.0, 1.0) if ring_width <= 0.0 \
				else clampf(ring_width / 2.0 + 0.5 - absf(d - DOCK_DOT_RADIUS), 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(image)


## A model's look, worked out once: [map color, length, width, hull quad, bow
## triangle, closed outline, art (see load_ship_art()), art rect], the shapes
## centered on the ship's position.
func _model_look(model_id: String) -> Array:
	if not _model_looks.has(model_id):
		var model := GameData.get_ship_model(model_id)
		var dims: Array = model.get("map_size", [14, 6])
		var length := float(dims[0])
		var width := float(dims[1])
		var bow := width * BOW_LENGTH_FACTOR
		var back := -(length + bow) / 2.0
		var front := back + length
		var back_left := Vector2(back, -width / 2.0)
		var front_left := Vector2(front, -width / 2.0)
		var tip := Vector2(front + bow, 0.0)
		var front_right := Vector2(front, width / 2.0)
		var back_right := Vector2(back, width / 2.0)
		_model_looks[model_id] = [Color.from_string(model.get("map_color", "#ffffff"), Color.WHITE), length, width,
			PackedVector2Array([back_left, front_left, front_right, back_right]),
			PackedVector2Array([front_left, tip, front_right]),
			PackedVector2Array([back_left, front_left, tip, front_right, back_right, back_left]),
			load_ship_art(str(model.get("category", ""))),
			Rect2(back, -width / 2.0, length + bow, width)]
	return _model_looks[model_id]


func _draw_marker(at: Vector2, color: Color) -> void:
	var font := get_theme_default_font()
	var baseline := at + Vector2(-LOST_MARKER_SIZE * 0.15, -LOST_MARKER_OFFSET)
	_canvas.draw_string_outline(font, baseline, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, LOST_MARKER_SIZE, 4,
		_color(&"lost_marker_outline"))
	_canvas.draw_string(font, baseline, "!", HORIZONTAL_ALIGNMENT_LEFT, -1, LOST_MARKER_SIZE, color)

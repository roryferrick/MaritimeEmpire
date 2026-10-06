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
## A storm was clicked (by its Weather.key()).
signal storm_clicked(storm_key: String)
## A pod of sea animals was clicked (its index in SeaLife.pods).
signal pod_clicked(pod_index: int)
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
## However small ships are drawn, a click this close (px) still picks one.
const SHIP_HIT_MIN_PX := 7.0
## Storms (see _draw_storms()): dark cloud, pale rim and calm eye colors, the haze as [share of the
## radius, opacity] rings, the bands' opacity, how far each winds round
## (radians) and in how many pieces, how fast they turn (radians a second of
## play), how strong a tropical storm is before its eye shows, and from what
## on-screen radius its name is shown.
const STORM_CLOUD := Color(0.07, 0.07, 0.1)
const STORM_RIM := Color(0.7, 0.74, 0.8)
const STORM_EYE := Color(0.55, 0.62, 0.7, 0.55)
const STORM_HAZE := [[1.0, 0.2], [0.82, 0.2], [0.64, 0.24], [0.46, 0.3], [0.3, 0.36], [0.16, 0.3]]
const STORM_BAND_ALPHA := 0.8
## A thin pale edge along each band, so the dark clouds stand out on deep sea.
const STORM_RIM_ALPHA := 0.45
const STORM_ARM_WIND := 4.2
const STORM_ARM_STEPS := 28
const STORM_SPIN := 0.6
const STORM_EYE_FROM := 0.6
const STORM_LABEL_MIN_RADIUS := 26.0
const STORM_FONT_SIZE := 14
## Each storm's track (where it has been and where it's going, see
## _draw_storm_tracks()): a thick grey dashed line, stronger for the storm
## under the mouse or whose popup is open (which also gets a dashed ring at
## its edge and its core's edge). Hovering or clicking within
## STORM_HIT_SHARE of its radius (or STORM_HIT_MIN_PX) picks a storm.
const STORM_TRACK_COLOR := Color(0.78, 0.78, 0.8, 0.3)
const STORM_TRACK_HIGHLIGHT_ALPHA := 0.65
const STORM_TRACK_WIDTH := 3.5
const STORM_TRACK_DASH := Vector2(12.0, 8.0)
const STORM_HIT_SHARE := 0.5
const STORM_HIT_MIN_PX := 24.0
## Lightning in tropical storms (see _draw_lightning()): the bolt's core and glow
## colors, how long each flash slot lasts (seconds of play) and the share of it
## a flash is lit, how many spots in a storm may flash per slot and the chance
## each does at full strength, and the smallest on-screen storm radius with any.
const LIGHTNING_CORE := Color(1.0, 1.0, 0.92)
const LIGHTNING_GLOW := Color(0.8, 0.85, 1.0)
const LIGHTNING_SLOT_S := 0.35
const LIGHTNING_LIT := 0.45
const LIGHTNING_CELLS := 4
const LIGHTNING_CHANCE := 0.3
const LIGHTNING_MIN_RADIUS := 18.0
## Seasonal ice on ports and canals (see _draw_ice()): its color, a closed
## canal's frosted line width, and how far outside a closed port's dot its ice
## ring is.
const ICE_COLOR := Color(0.86, 0.95, 1.0)
const ICE_CANAL_WIDTH := 5.0
const ICE_RING_GAP := 5.0
## Land drawings (see _draw_decor()): where their art is, the bucket size
## (degrees) they're sorted into, how far apart on screen a tier must be to
## show, their sizes on screen ([plants and rocks, mountains, animals and waves] px at the
## reference zoom), and how much they grow or shrink with the zoom.
const DECOR_ART_DIR := "res://art/decor/"
const DECOR_BUCKET := 10.0
const DECOR_MIN_SPACING_PX := 32.0
const DECOR_SIZE_PX := Vector3(20.0, 34.0, 28.0)
const DECOR_ZOOM_REFERENCE := 30.0
const DECOR_SCALE_RANGE := Vector2(0.9, 1.5)
const DECOR_ANIMALS: Array[String] = ["penguin", "polar_bear", "camel", "elephant", "giraffe", "lion", "zebra", "kangaroo", "koala",
	"panda", "tiger", "bison", "moose", "brown_bear", "reindeer", "llama", "toucan", "gorilla", "orangutan", "kiwi", "lemur",
	"quetzal", "red_tailed_hawk", "bald_eagle", "osprey"]
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
## Docked tugs aren't dots but small upright ticks across the top of their
## port's outline, side by side TUG_TICK_GAP px apart, each reaching
## TUG_TICK_REACH px inside and out of it, TUG_TICK_WIDTH wide.
const TUG_TICK_REACH := 2.5
const TUG_TICK_WIDTH := 1.6
const TUG_TICK_GAP := 3.0
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
## Ships are drawn this share of their map_size (and of everything built on it).
const SHIP_SIZE := 0.7
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
## Ships and docks have a fixed size in the world: map_size (times SHIP_SIZE)
## pixels at SHIP_WORLD_ZOOM px a degree, so they grow and shrink with the map
## like the coast does (tiny zoomed right out). Sea animals keep their
## map_size until the zoom passes SHIP_GROW_FROM_ZOOM, then
## grow with the square root of the zoom, up to SHIP_MAX_SCALE times.
const SHIP_WORLD_ZOOM := 75.0
const SHIP_GROW_FROM_ZOOM := 60.0
const SHIP_MAX_SCALE := 3.0
## Where a ship being carried sits on its recovery boat: the middle of the
## open work deck aft (x from the stern, in art units), clear of the wheelhouse.
const CARRY_DECK_X := 58.0
## A recovery boat taking a ship aboard or floating it off (see
## _recovery_offset(), _draw_ballast()): how far (a share of its length) the
## ship slides over its stern, its work deck's stretch [from, to] in art units,
## and the sea over the deck when it's ballasted down, with its ripples.
const RECOVERY_SLIDE := 0.55
## How wide a turning circle icebreakers and tugs sail round (in their own
## lengths), so they never pivot on the spot. (Recovery boats spin on the spot
## with a ship aboard, see _turning_pose().)
const TURN_RADIUS_LENGTHS := 0.7
## How far clear ahead of a lost ship a recovery boat stops, stern to the
## ship's bow (in art units), before backing under it.
const RECOVERY_AHEAD_GAP := 6.0
## Tugs on a tow: how long the lead's tow line is on screen (px, before
## scaling up zoomed in), and its color.
const TOW_LINE_PX := 5.0
const TOW_LINE_COLOR := Color(0.92, 0.9, 0.82)
## Ships further than this (px, scaled up zoomed in) off screen aren't drawn.
const SHIP_CULL_MARGIN := 40.0
## How see-through other players' ships are drawn (multiplayer).
const OTHER_SHIP_ALPHA := 0.6
const BALLAST_DECK := Vector2(4.0, 104.0)
const BALLAST_WATER_ALPHA := 0.75
const BALLAST_RIPPLE := Color(0.85, 0.93, 1.0, 0.7)
## The land's colors: simplified biomes in flat colors, made by
## tools/build_map_data.gd from Natural Earth II.
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
const ACTIVE_LANE_ALPHA := 0.45
## Multiplayer: other players' lanes, all in their company's color (lifted to
## at least OTHER_LANE_MIN_LUMINANCE so black and brown show on the sea), a
## little fainter than this player's own.
const OTHER_LANE_ALPHA := 0.25
const OTHER_LANE_MIN_LUMINANCE := 0.5
## Ore carriers' lanes are their gray map colors taken this far towards white,
## and drawn this opaque, so they show on the dark deep sea (the ships keep
## their gray).
const ORE_LANE_WHITEN := 0.65
const ORE_LANE_ALPHA := 0.7
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
## countries); rivers before mountain ranges, so a river shows across a range.
const FEATURE_PRIORITY: Array[int] = [FeatureKind.OCEAN, FeatureKind.SEA, FeatureKind.RIVER, FeatureKind.RANGE,
	FeatureKind.DESERT, FeatureKind.STRAIT, FeatureKind.LAKE]
## Words that already mean "river" in a river's name ("Rio Grande", "Syr Darya",
## "Shishhid Gol"), so it isn't given another; the rest get " River" added.
const RIVER_WORDS: Array[String] = ["river", "rio", "río", "canal", "delta", "darya", "bahr", "gol"]
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
const CANAL_WIDTH := 0.02
const CANAL_MIN_WIDTH := 4.0
## Winter sea ice (see IceArt, _update_ice()): how often (s) where the ice is
## gets checked, its sheet, crack, broken-ice and open-channel colors, how
## many cracks each frozen circle has, an icebreaker channel's width
## (projected degrees, and at least ICE_CHANNEL_PX on screen), how far apart
## (projected degrees) its points are noted, and how long (s of play) a channel
## takes to freeze over again.
const ICE_REFRESH_S := 0.5
const ICE_SHEET := Color(0.9, 0.95, 0.98, 0.96)
const ICE_CRACK := Color(0.62, 0.74, 0.84, 0.8)
const ICE_BROKEN := Color(0.78, 0.86, 0.92)
const ICE_CHANNEL := Color(0.1, 0.24, 0.42)
const ICE_CRACKS := 7
const ICE_CHANNEL_WIDTH := 0.08
const ICE_CHANNEL_PX := 6.0
const ICE_TRACK_STEP := 0.02
const ICE_REFREEZE_S := 60.0
## Cell size (projected degrees) for telling whether ice reaches a lake.
const LAKE_CELL := 2.0
## Points round each frozen circle when they're merged into the sheet's outline.
const ICE_OUTLINE_POINTS := 48
## The Northern Sea Route and Northwest Passage labels (see _draw_route_labels()):
## their size, and the web-map zoom they show from.
const ROUTE_LABEL_FONT_SIZE := 16
const ROUTE_LABEL_WEB_ZOOM := 1.5
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
		for layer in _art_layers:
			layer.queue_redraw()
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
## Docked tugs: each one's place among the tugs at its port, and how many are there.
var _tug_slots := {}
var _tug_counts := {}
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
## Every copy's land and top art (see LandArt and TopArt).
var _art_layers: Array[Node2D] = []
## Winter sea ice (see IceArt): the ice and lake ice sheet of every copy, the
## frozen circles ([projected center, projected radius, seed]), what the
## circles were last worked out from, and the channels icebreakers have broken
## (ship -> [[projected point, play time], ...]).
var _ice_arts: Array[Node2D] = []
var _ice_circles := []
## The frozen circles merged into outlines, the sheet's fill (see _merge_circles()).
var _ice_outlines: Array[PackedVector2Array] = []
var _ice_key := []
var _ice_clock := 0.0
var _ice_tracks := {}
## The lakes' triangles by LAKE_CELL cell, and the frozen ones (see
## _build_lake_ice()).
var _lake_ice: ArrayMesh = null
var _lake_cells := {}
## Drawn in screen space in three layers, bottom to top: canals (every frame,
## for locks and convoys), the rest that only changes with the view, routes,
## hubs or prices (ports, labels, route lanes; see STATIC_REFRESH_S), and ships
## (every frame). _canvas is the layer being drawn, which the draw helpers use.
var _decor_layer := Control.new()
var _weather_layer := Control.new()
## The storm whose popup is open, and the one under the mouse (Weather.key()s; "" for none).
var selected_storm := ""
var _hovered_storm := ""
## The sea animals' pod whose popup is open, and the one under the mouse (-1 for none).
var selected_pod := -1
var _hovered_pod := -1
## The sea animals' art by name, each pod's facing on screen (eased round as
## it turns), and where each pod was last drawn: [pod index, center, radius].
var _sea_art := {}
var _pod_angles := {}
var _pod_hits: Array = []
## Until the sea animals' migration paths are all found (see SeaLife.start_warm_up()).
var _sea_warming := true
## Land drawings: a texture per kind (WorldMapData.decor_kind_names), and the
## drawings by DECOR_BUCKET-degree cell, so only those near the view are looked at.
var _decor_textures: Array[Texture2D] = []
var _decor_buckets := {}
var _canal_layer := Control.new()
var _static_layer := Control.new()
## Docked ships (dots in rings round their ports, tugs as ticks): drawn apart
## from the ships at sea, since they only move when the view does or a ship
## docks or leaves (redrawn then, and with the ports' slow size changes).
var _dock_layer := Control.new()
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
	## The lakes by color group (WorldMapData.lake_triangles), and each group's color.
	var lake_meshes: Array[ArrayMesh] = []
	var lake_colors := PackedColorArray()
	## Per depth band (WorldMapData.depth_levels): its sea, and the shallower
	## patches inside it.
	var depth_meshes: Array[ArrayMesh] = []
	var depth_hole_meshes: Array[ArrayMesh] = []
	var white: Texture2D
	var land_colors: Texture2D

	## The sea, darkening band by band with depth (the view's own background is
	## the shallowest); the gray route map keeps one flat sea. Its children draw
	## the rest over it (see MapView._ready()).
	func _draw() -> void:
		if not view.gray_mode:
			for band in depth_meshes.size():
				draw_mesh(depth_meshes[band], white, Transform2D.IDENTITY, view._depth_color(band + 1))
				draw_mesh(depth_hole_meshes[band], white, Transform2D.IDENTITY, view._depth_color(band))

	func land_texture() -> Texture2D:
		return white if view.gray_mode else land_colors

	func land_tint() -> Color:
		return view._color(&"land") if view.gray_mode else Color.WHITE


## The land in its biome colors (see MapView.LAND_COLORS) or flat gray, and the
## lakes in their simplified real colors (plain water on the gray map), over
## the sea and its ice.
class LandArt:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		draw_mesh(art.land_mesh, art.land_texture(), Transform2D.IDENTITY, art.land_tint())
		draw_mesh(art.water_mesh, art.white, Transform2D.IDENTITY, view._color(&"ocean"))
		for i in art.lake_meshes.size():
			if art.lake_meshes[i] != null:
				draw_mesh(art.lake_meshes[i], art.white, Transform2D.IDENTITY, view._color(&"ocean") if view.gray_mode else art.lake_colors[i])


## Over the land, lakes and lake ice: the lakes' islands, the borders, the
## coast, and the equator (y = 0 in the projection), faint.
class TopArt:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		var data := GameData.world_map
		draw_mesh(art.lake_island_mesh, art.land_texture(), Transform2D.IDENTITY, art.land_tint())
		draw_multiline(data.border_segments, view._color(&"border"), -1.0)
		draw_multiline(data.coast_segments, view._color(&"coast"), -1.0)
		draw_line(Vector2(-Geo.WORLD_WIDTH / 2.0, 0.0), Vector2(Geo.WORLD_WIDTH / 2.0, 0.0), view._color(&"equator"), -1.0)


## Winter sea ice for one copy of the world (see MapView._ice_circles and
## _ice_tracks): a solid sheet of white-blue ice with a soft edge and faint
## cracks over each frozen stretch of sea, cut by the channels icebreakers
## break through it (open water, edged with broken ice, slowly freezing over
## again). It lies between the sea and the land (LandArt), so it stops at the
## coast; lakes inside frozen areas freeze too (LakeIce).
class IceArt:
	extends Node2D

	var view: MapView

	func _draw() -> void:
		view._draw_ice_sheet(self)


## Lake ice: the bits of lake inside the frozen circles (MapView._lake_ice,
## picked out triangle by triangle when the ice changes), in the ice's color.
class LakeIce:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		if view._lake_ice != null:
			draw_mesh(view._lake_ice, art.white, Transform2D.IDENTITY, ICE_SHEET)


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
	var lake_meshes: Array[ArrayMesh] = []
	for triangles in data.lake_triangles:
		lake_meshes.append(_triangle_mesh(triangles) if not triangles.is_empty() else null)
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
		art.lake_meshes = lake_meshes
		art.lake_colors = data.lake_colors
		art.depth_meshes = depth_meshes
		art.depth_hole_meshes = depth_hole_meshes
		art.white = white
		art.land_colors = land_colors
		art.position.x = copy * Geo.WORLD_WIDTH
		_art_root.add_child(art)
		_art_copies.append(art)
		# Over the sea (drawn by the copy itself): the sea ice, then the land and
		# lakes, the lake ice (masked to the lakes), and the lake islands, borders
		# and coast on top. The ice layers are hidden while there's no ice.
		var ice := IceArt.new()
		ice.view = self
		ice.visible = false
		art.add_child(ice)
		var land := LandArt.new()
		land.view = self
		land.art = art
		art.add_child(land)
		var lake_ice := LakeIce.new()
		lake_ice.view = self
		lake_ice.art = art
		lake_ice.visible = false
		art.add_child(lake_ice)
		var top := TopArt.new()
		top.view = self
		top.art = art
		art.add_child(top)
		_art_layers.append_array([land, top])
		_ice_arts.append_array([ice, lake_ice])
		for i in data.river_tiers.size():
			var tier := RiverTier.new()
			tier.view = self
			tier.segments = data.river_tiers[i]
			tier.min_zoom = data.river_tier_min_zoom[i]
			art.add_child(tier)
			_river_tiers.append(tier)

	for layer: Control in [_decor_layer, _weather_layer, _canal_layer, _static_layer, _dock_layer, _overlay]:
		layer.mouse_filter = MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(PRESET_FULL_RECT)
		add_child(layer)
	_decor_layer.draw.connect(_draw_decor)
	_decor_layer.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_decor()
	_weather_layer.draw.connect(_draw_weather_layer)
	_canal_layer.draw.connect(_draw_canal_layer)
	_static_layer.draw.connect(_draw_static_layer)
	_overlay.draw.connect(_draw_overlay)
	_dock_layer.draw.connect(_draw_dock_layer)
	_dock_layer.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	GameState.ship_changed.connect(func(_ship: Ship) -> void: _dock_layer.queue_redraw())
	GameState.ships_changed.connect(_dock_layer.queue_redraw)
	# Ship art is drawn well below its size at most zooms: mipmaps keep it smooth.
	_overlay.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(delta: float) -> void:
	if not show_ships or not is_visible_in_tree():
		return
	_weather_layer.queue_redraw()
	_canal_layer.queue_redraw()
	_overlay.queue_redraw()
	if _sea_warming:
		SeaLife.shared().start_warm_up()  # Their paths are found off the main thread.
		_sea_warming = not SeaLife.shared().is_ready()
	_ice_clock += delta
	if _ice_clock >= ICE_REFRESH_S:
		_ice_clock = 0.0
		_update_ice()
	if _track_icebreakers():
		for node in _ice_arts:
			node.queue_redraw()
	# Route lanes follow the ships' legs, hub rings the hubs and port colors the
	# drifting prices: a few times a second is plenty.
	_static_clock += delta
	if _static_clock >= STATIC_REFRESH_S:
		_static_clock = 0.0
		_static_layer.queue_redraw()
		_dock_layer.queue_redraw()  # Ports grow and shrink, and their rings with them.


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
		var pose := _turning_pose(ship)
		if not pose.is_empty():
			return pose[0]
		if ship.is_tug() and ship.job_phase == Ship.JOB_TOW and ship.rescuing != null:
			return world_to_screen(ship.world_position()) + Vector2.from_angle(_heading_angle(ship.heading())) * _tug_offset(ship)
		return _harbour_blend(ship, world_to_screen(ship.world_position()) + _canal_lane_offset(ship))
	if docks_shown():
		return _docked_pose(ship)[0]
	if ship.is_tug():
		var tick := _tug_tick(ship)
		return (tick[0] + tick[1]) / 2.0
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
## the boat's middle, so the wheelhouse stays in view. Being floated off at
## port, it slides back off the stern (see Ship.float_progress()).
func _carried_screen_position(ship: Ship) -> Vector2:
	var boat := ship.rescuer
	var rect: Rect2 = _model_look(boat.model_id)[7]
	var along := _deck_along(rect)
	if boat.job_phase == Ship.JOB_UNLOAD:
		along -= rect.size.x * RECOVERY_SLIDE * maxf(boat.float_progress(), 0.0)
	return ship_screen_position(boat) + Vector2(along, 0.0).rotated(_screen_angle(boat)) * _ship_scale()


## Where a recovery boat's work deck is, ahead of its middle (negative: behind),
## in its art's units.
func _deck_along(rect: Rect2) -> float:
	return rect.position.x + rect.size.x * CARRY_DECK_X / SHIP_ART_WIDTH


## A ship's heading as an on-screen angle (0 when docked). A carried ship faces
## the way its recovery boat does, and a recovery boat or icebreaker that's
## turning faces along its turning circle (see _turning_pose()).
func _screen_angle(ship: Ship) -> float:
	if ship.is_carried():
		return _screen_angle(ship.rescuer) + (PI if ship.rescuer.carry_flipped() else 0.0)  # Met head on: aboard stern first.
	if ship.is_docked() and docks_shown():
		return _docked_pose(ship)[1]
	var pose := _turning_pose(ship)
	if not pose.is_empty():
		return pose[1]
	return _heading_angle(ship.heading())


static func _heading_angle(direction: Vector2) -> float:
	return Vector2(direction.x, -direction.y).angle() if direction != Vector2.ZERO else 0.0


## The on-screen angle of a lane's heading `mile` along it.
static func _lane_angle(from_port: String, to_port: String, mile: float) -> float:
	var lane = GameData.lane(from_port, to_port)
	return _heading_angle(lane.sample(mile)[1]) if lane else 0.0


## Where a recovery boat or icebreaker is drawn, and which way it faces,
## while it's maneuvering ([screen position, angle]), or [] when it's just
## sailing its lane. Ships don't pivot: a turn is sailed round a turning
## circle (_turn_pose()) - a recovery boat lining up with a lost ship (and
## pulling ahead of it) or turning round with it aboard, an icebreaker turning
## to lead its convoy or turning back from the ice edge - and a recovery boat
## loading a ship slides under it (_recovery_offset()).
func _turning_pose(ship: Ship) -> Array:
	if ship.is_docked() or ship.from_port.is_empty() or not (ship.is_recovery() or ship.is_icebreaker() or ship.is_tug()):
		return []
	var base := world_to_screen(ship.world_position()) + _canal_lane_offset(ship)
	var look_rect: Rect2 = _model_look(ship.model_id)[7]
	var radius := look_rect.size.x * TURN_RADIUS_LENGTHS * _ship_scale()
	var lane_angle := _heading_angle(ship.lane_heading())
	if ship.is_tug():
		# Out at the lost ship, it turns round to face home and takes its place
		# for the tow: ahead of the ship (the lead, on the tow line) or at its stern.
		if ship.job_phase != Ship.JOB_ALIGN or ship.rescuing == null:
			return []
		var home := lane_angle + PI
		return _turn_pose(base, lane_angle, base + Vector2.from_angle(home) * _tug_offset(ship), home, radius,
			clampf(ship.align_time / Ship.ALIGN_SECONDS, 0.0, 1.0))
	if ship.is_icebreaker():
		var t := clampf(ship.align_time / Ship.ALIGN_SECONDS, 0.0, 1.0)
		if ship.ice_phase == "turn_in":
			var leg := ship.escort_leg
			return _turn_pose(base, lane_angle, base, _lane_angle(leg[0], leg[1], leg[2]), radius, t)
		if ship.ice_phase == "turn_back":
			return _turn_pose(base, lane_angle, base, lane_angle + PI, radius, t)
		return []
	if ship.job_phase != Ship.JOB_ALIGN or ship.rescuing == null:
		return []
	# A recovery boat keeps the heading it came in on: it drives on past the
	# lost ship and stops in line clear ahead of it, ballasts down, backs under
	# it and rises, settling with the ship centered on it (see
	# _recovery_offset()). Then, if the port it's taking it to is back the way
	# it came, it spins round on the spot (heading() says which way it faces)
	# and sets off from there along the lane.
	if ship.align_time < Ship.ALIGN_SECONDS + Ship.LOAD_SECONDS:
		return [base + Vector2.from_angle(lane_angle) * _recovery_offset(ship) * _ship_scale(), lane_angle]
	return [base, _heading_angle(ship.heading())]


## Where a tug on a tow sits (screen px along the way it's towing, from the
## towed ship's middle): the lead ahead of the ship's bow on its tow line
## (TOW_LINE_PX), the other pushing at its stern.
func _tug_offset(tug: Ship) -> float:
	var tug_rect: Rect2 = _model_look(tug.model_id)[7]
	var ship_rect: Rect2 = _model_look(tug.rescuing.model_id)[7]
	var gap := (tug_rect.size.x + ship_rect.size.x) / 2.0
	return (gap + TOW_LINE_PX if tug.tug_lead else -gap) * _ship_scale()


## A point t (0 to 1) along a smooth turn from one screen pose (a, facing
## angle_a) to another (b, angle_b), as [position, facing angle], like a ship
## on its turning circle rather than pivoting: two curves through a point out
## ahead to the side it turns to, further out the sharper the turn (a U-turn
## loops out radius wide and comes back), eased in and out.
static func _turn_pose(a: Vector2, angle_a: float, b: Vector2, angle_b: float, radius: float, t: float) -> Array:
	var turn := wrapf(angle_b - angle_a, -PI, PI)
	if absf(turn) > PI - 0.01:
		turn = PI  # A U-turn: round to starboard.
	var middle_angle := angle_a + turn / 2.0
	var middle := (a + b) / 2.0 + Vector2.from_angle(middle_angle) * radius * absf(turn) / PI
	# Handles long enough to swing round a turn, but no longer than a third of
	# each half on a straight run (longer ones overshoot, so the ship lurches).
	var reach := maxf(radius * 0.6 * absf(turn) / PI, a.distance_to(b) / 6.0)
	t = smoothstep(0.0, 1.0, t)
	var curve := [a, a + Vector2.from_angle(angle_a) * reach, middle - Vector2.from_angle(middle_angle) * reach, middle]
	var u := t * 2.0
	if t >= 0.5:
		curve = [middle, middle + Vector2.from_angle(middle_angle) * reach, b - Vector2.from_angle(angle_a + turn) * reach, b]
		u = t * 2.0 - 1.0
	var point := _bezier(curve, u)
	var tangent := _bezier(curve, minf(u + 0.02, 1.0)) - _bezier(curve, maxf(u - 0.02, 0.0))
	var facing := tangent.angle() if tangent.length() > 0.001 else angle_a + turn * t
	return [point, facing]


static func _bezier(points: Array, u: float) -> Vector2:
	var p0: Vector2 = points[0]
	var p1: Vector2 = points[1]
	var p2: Vector2 = points[2]
	var p3: Vector2 = points[3]
	var v := 1.0 - u
	return p0 * v * v * v + p1 * 3.0 * v * v * u + p2 * 3.0 * v * u * u + p3 * u * u * u


## How far ahead of the lost ship (in art units, along the boat's heading) a
## recovery boat is drawn while it takes the ship aboard, like a real
## semi-submersible heavy-lift ship: it drives on past the ship and stops in
## line clear ahead of it (its stern RECOVERY_AHEAD_GAP past the ship's bow or
## stern, whichever way the ship faces), ballasts down there, backs under the
## ship (which floats in over its open stern) until the ship is over its deck,
## then rises, settling with the ship centered on it. 0 otherwise.
func _recovery_offset(boat: Ship) -> float:
	if boat.job_phase != Ship.JOB_ALIGN:
		return 0.0
	var rect: Rect2 = _model_look(boat.model_id)[7]
	var ship_rect: Rect2 = _model_look(boat.rescuing.model_id)[7]
	var under := -_deck_along(rect)  # The deck right under the ship.
	var ahead := (rect.size.x + ship_rect.size.x) / 2.0 + RECOVERY_AHEAD_GAP
	var t := boat.load_time()
	if t < 0.0 and boat.align_time < Ship.ALIGN_SECONDS:
		# Driving on past the ship from where it reached it, slowing to a stop.
		var x := boat.align_time / Ship.ALIGN_SECONDS
		return ahead * (1.0 - (1.0 - x) * (1.0 - x))
	if t < 0.0:
		return 0.0  # Spinning round after.
	var third := Ship.LOAD_SECONDS / 3.0
	if t < third:
		return ahead
	if t < third * 2.0:
		return lerpf(ahead, under, smoothstep(0.0, 1.0, (t - third) / third))
	return lerpf(under, 0.0, smoothstep(0.0, 1.0, (t - third * 2.0) / third))


## A recovery boat ballasted down (Ship.submerged()): the sea over its work
## deck, with a few ripples, the wheelhouse still above water. Drawn in the
## boat's own (art) coordinates.
func _draw_ballast(boat: Ship, rect: Rect2) -> void:
	var level := boat.submerged()
	if level <= 0.0:
		return
	var deck := Rect2(rect.position.x + rect.size.x * BALLAST_DECK.x / SHIP_ART_WIDTH, rect.position.y + rect.size.y * 0.08,
		rect.size.x * (BALLAST_DECK.y - BALLAST_DECK.x) / SHIP_ART_WIDTH, rect.size.y * 0.84)
	_canvas.draw_rect(deck, Color(_color(&"ocean"), BALLAST_WATER_ALPHA * level))
	var ripple := Color(BALLAST_RIPPLE, BALLAST_RIPPLE.a * level)
	var phase := GameState.play_time * 3.0
	for row in 3:
		var y := deck.position.y + deck.size.y * (row + 1) / 4.0
		var points := PackedVector2Array()
		for step in 9:
			var x := deck.position.x + deck.size.x * step / 8.0
			points.append(Vector2(x, y + sin(step * 1.6 + phase + row) * deck.size.y * 0.06))
		_canvas.draw_polyline(points, ripple, 0.8, true)


## A docked ship's place in its port's rings: how many of the fleet before it are
## docked there. Worked out for the whole fleet once a frame.
func _dock_slot(ship: Ship) -> int:
	var frame := Engine.get_process_frames()
	if frame != _dock_slots_frame:
		_dock_slots_frame = frame
		_dock_slots.clear()
		_tug_slots.clear()
		_tug_counts.clear()
		var counts := {}
		for other in GameState.ships:
			if other.is_docked() and other.is_tug():
				_tug_slots[other] = _tug_counts.get(other.docked_at, 0)
				_tug_counts[other.docked_at] = int(_tug_slots[other]) + 1
			elif other.is_docked():
				var count: int = counts.get(other.docked_at, 0)
				_dock_slots[other] = count
				counts[other.docked_at] = count + 1
	return _dock_slots.get(ship, 0)


## A docked tug's tick across the top of its port's outline: [lower end,
## upper end] on screen. Tugs at a port stand upright side by side,
## TUG_TICK_GAP apart, each crossing the outline where it is.
func _tug_tick(ship: Ship) -> PackedVector2Array:
	_dock_slot(ship)  # Brings the tug places up to date for this frame.
	var count := int(_tug_counts.get(ship.docked_at, 1))
	var radius := _port_radius(ship.docked_at)
	var across := clampf((int(_tug_slots.get(ship, 0)) - (count - 1) / 2.0) * TUG_TICK_GAP, -radius, radius)
	var at := port_screen_position(ship.docked_at) + Vector2(across, -sqrt(radius * radius - across * across))
	return PackedVector2Array([at + Vector2(0.0, TUG_TICK_REACH), at - Vector2(0.0, TUG_TICK_REACH)])

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
	elif motion:
		var pod := _pod_at(motion.position) if show_ships else -1
		_hover(pod, _storm_at(motion.position) if show_ships and pod < 0 else "")


## The sea animals' pod or storm under the mouse: a pod's route shows, a
## storm's track and edges show stronger, and the pointer shows either can be clicked.
func _hover(pod: int, storm_key: String) -> void:
	_hovered_pod = pod
	_hovered_storm = storm_key
	mouse_default_cursor_shape = CURSOR_POINTING_HAND if pod >= 0 or not storm_key.is_empty() else CURSOR_ARROW


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover(-1, "")


## Picks whichever port or ship is closest to the click, within its hit radius,
## or else a canal lock under it, or else a storm (see _storm_at()).
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
			if dist <= maxf(SHIP_HIT_RADIUS * _ship_scale(), SHIP_HIT_MIN_PX) and dist < nearest_dist:
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
	elif show_ships and _pod_at(screen_pos) >= 0:
		pod_clicked.emit(_pod_at(screen_pos))
	elif show_ships and not _storm_at(screen_pos).is_empty():
		storm_clicked.emit(_storm_at(screen_pos))
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
	if not _ice_circles.is_empty():
		for node in _ice_arts:
			node.queue_redraw()  # So do the cracks and channels.
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
	_decor_layer.queue_redraw()
	_weather_layer.queue_redraw()
	_canal_layer.queue_redraw()
	_static_layer.queue_redraw()
	_dock_layer.queue_redraw()
	_overlay.queue_redraw()


func _draw_weather_layer() -> void:
	_canvas = _weather_layer
	if show_ships:
		_draw_sea_life()  # Under the ice and storms: they swim beneath both.
		_draw_ice()
		_draw_route_labels()
		_draw_storms()


func _draw_canal_layer() -> void:
	_canvas = _canal_layer
	_draw_canals()
	_draw_ice_canals()


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


func _draw_dock_layer() -> void:
	if not show_ships:
		return
	_canvas = _dock_layer
	if docks_shown():
		_draw_docks()
	var outline := _color(&"ship_outline")
	for ship in GameState.ships:
		if ship.is_docked() and not docks_shown():  # (Shown, docked ships are drawn with the others: see _draw_ships().)
			_draw_ship(ship, outline)
	_canvas = _overlay


# --- Docks ---------------------------------------------------------------------------

## Each port has its docks (see Docks): piers pointing
## out to sea (where the sea is around it: _port_sea_angle()), a berth each
## side, as many as its size band has (Small one, Medium one and a quay, Large
## three, Giant four), the piers lengthening for a hub's extra berths;
## each long enough for the biggest ship that can dock there. Ships moor
## alongside facing the shore, lie at the anchorage further out (each keeping
## its spot in a fixed grid off to one side), and tugs tie up along
## the wharf. Ships glide between the mouth, the anchorage and their berth.
## Dock geometry is in "dock units", the ships' own map size, turned to face the
## sea and sized like the ships, in the world (_ship_scale()).
## Ships glide this long (seconds of play) from the harbour mouth to their spot
## at the anchorage or wharf; the anchorage is ANCHOR_COLUMNS spots across.
const ANCHOR_GLIDE_S := 2.0
const ANCHOR_COLUMNS := 4
## A port's docks smaller than this on screen (px, out to the mouth) aren't drawn.
const DOCK_MIN_PX := 3.0
## How far ahead (nm) a ship eased near a port looks to see which way it faces.
const HEADING_PROBE_NM := 1.5
## A port's sea direction comes from about this many of its lanes, this far out.
const SEA_ANGLE_LANES := 24
const SEA_ANGLE_MILES := 12.0
const PIER_WIDTH := 4.0
const BERTH_GAP := 1.0
const PIER_COLOR := Color(0.66, 0.6, 0.5)
const PIER_EDGE := Color(0.22, 0.2, 0.17)
## Bollards (the tie-down posts) every BOLLARD_STEP along both edges of each
## pier and quay, BOLLARD_INSET in from the edge; a moored ship is tied to them
## by four ropes (bow and stern lines and two springs).
const BOLLARD_STEP := 3.5
const BOLLARD_INSET := 0.7
const BOLLARD_RADIUS := 0.5
const BOLLARD_COLOR := Color(0.16, 0.15, 0.14)
const ROPE_COLOR := Color(0.95, 0.9, 0.74)
## Tugs tie up alongside the wharf this far apart (dock units, about a tug and a half).
const TUG_STEP := 9.0
## Stone blocks join the dock pieces where they meet: this wide, dressed grey stone.
const STONE_BLOCK := 6.5
const STONE_COLOR := Color(0.6, 0.6, 0.62)
const STONE_JOINT := Color(0.42, 0.42, 0.45)
const PIERS_BY_BAND := {small = 1, medium = 1, large = 3, giant = 4}
const BAND_RANK := {small = 0, medium = 1, large = 2, giant = 3}
## data/port_facing.json, and port id -> the sea's direction from it on screen (see _port_sea_angle()).
const PORT_FACING_PATH := "res://data/port_facing.json"
static var _port_facing := {}
var _sea_angles := {}
## Port id -> 1 or -1: which side of its piers its quay and tugs go (see _port_sea_angle()).
var _dock_flips := {}
## [band, berths] -> its layout (see _dock_layout()).
var _dock_layouts := {}
## Each lying ship's spot (see _update_spots()): [port, tug?] -> {slot: ship},
## ship -> its slot and that key, when it got to its port ([port, play time]),
## and where it last lay in port ([port, dock-units position, facing]).
var _spot_tables := {}
var _spot_slots := {}
var _spot_keys := {}
var _spots_frame := -1
var _dock_seen := {}
var _last_spot := {}


func docks_shown() -> bool:
	return show_ships and not gray_mode


## Which way the sea is from a port, as an on-screen angle (and which side its
## quay goes): from data/port_facing.json, or else the average
## way its sea lanes head out of it.
func _port_sea_angle(port_id: String) -> float:
	if _sea_angles.has(port_id):
		return _sea_angles[port_id]
	# Worked out from the coastline (data/port_facing.json; tools/port_facing.gd),
	# or set by hand there.
	if _port_facing.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PORT_FACING_PATH)) if FileAccess.file_exists(PORT_FACING_PATH) else null
		_port_facing = data if data is Dictionary else {facing = {}}
	var entry: Dictionary = _port_facing.get("manual", {}).get(port_id, _port_facing.get("facing", {}).get(port_id, {}))
	if entry.has("bearing"):
		var facing := deg_to_rad(float(entry.bearing) - 90.0)  # A compass bearing on screen (y down).
		_sea_angles[port_id] = facing
		_dock_flips[port_id] = 1.0 if str(entry.get("quay", "right")) == "right" else -1.0
		return facing
	# Otherwise (a port far up a river): the way its lanes leave, and the open sea.
	var port := GameData.get_port(port_id)
	var at := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	# The sea lanes leave it through real water: the way their first miles head,
	# to destinations all round the world, is the way out to sea.
	var root := GameData.port_position(port_id)
	var sum := Vector2.ZERO
	var stride := maxi(GameData.ports.size() / SEA_ANGLE_LANES, 1)
	for i in range(0, GameData.ports.size(), stride):
		var lane = GameData.lane(port_id, GameData.ports[i].id)
		if lane == null or lane.length() < SEA_ANGLE_MILES * 2.0:
			continue
		var out: Vector2 = lane.sample(SEA_ANGLE_MILES)[0] - root
		out.x = wrapf(out.x, -Geo.WORLD_WIDTH / 2.0, Geo.WORLD_WIDTH / 2.0)
		if out.length() > 0.0:
			sum += out.normalized()
	# On an open coast the open water itself says better (lanes follow the
	# traffic, along the coast): lean towards where the sea mask finds sea, in
	# rings a little way out (it's coarse right along the coast), the more of it
	# there is. In a river or a narrow sea it finds little, and the lanes rule.
	var sea := SeaLife.shared()
	var open := Vector2.ZERO
	var wet_count := 0
	var probes := 0
	for reach: float in [0.3, 0.6, 0.9]:
		for k in 32:
			var way := Vector2.from_angle(TAU * k / 32.0)
			probes += 1
			if sea.is_sea(_lon_lat_offset(at, way * reach)):
				open += way
				wet_count += 1
	var openness := clampf((float(wet_count) / probes - 0.15) / 0.3, 0.0, 1.0)
	if open.length() > 0.001:
		sum = (sum.normalized() if sum.length() > 0.001 else Vector2.ZERO) + open.normalized() * openness * 1.5
	var angle := Vector2(sum.x, -sum.y).angle() if sum.length() > 0.001 else PI / 2.0
	_sea_angles[port_id] = angle
	# Its docks' quay (and tugs) go on whichever side of the piers has more sea,
	# looking a little way offshore (the sea mask is coarse along the coast).
	var seaward := Vector2(sum.x, sum.y).normalized()
	var side := seaward.orthogonal()
	var wet := [0, 0]
	for reach: float in [0.25, 0.4, 0.55]:
		wet[0] += int(sea.is_sea(_lon_lat_offset(at, (seaward + side) * reach)))
		wet[1] += int(sea.is_sea(_lon_lat_offset(at, (seaward - side) * reach)))
	# Dock units' +y is a quarter turn clockwise on screen from the sea: flip the
	# layout if that isn't the wetter side.
	var plus_y := Vector2.from_angle(angle + PI / 2.0)  # On screen (y down).
	var side_screen := Vector2(side.x, -side.y)
	var plus_is_side := plus_y.dot(side_screen) > 0.0
	_dock_flips[port_id] = 1.0 if (wet[0] >= wet[1]) == plus_is_side else -1.0
	return angle


## A (lon, lat) point moved by degrees east and north (east scaled for the latitude).
static func _lon_lat_offset(at: Vector2, degrees: Vector2) -> Vector2:
	return at + Vector2(degrees.x / maxf(cos(deg_to_rad(at.y)), 0.1), degrees.y)


## The longest ship (dock units, bow included) that can dock at ports of a band,
## and the widest of any cargo ship (only cargo ships moor at berths).
static func _band_ship_length(band: String) -> float:
	var longest := 0.0
	for model: Dictionary in GameData.ship_models:
		if model.get("recovery", false) or model.get("tug", false) or not str(model.get("icebreaker", "")).is_empty():
			continue
		var needs := str(model.get("min_port", "small"))
		if int(BAND_RANK.get(needs, 0)) > int(BAND_RANK.get(band, 0)):
			continue
		var dims: Array = model.get("map_size", [14, 6])
		longest = maxf(longest, (float(dims[0]) + float(dims[1]) * BOW_LENGTH_FACTOR) * SHIP_SIZE)
	return longest


static func _widest_ship() -> float:
	var widest := 0.0
	for model: Dictionary in GameData.ship_models:
		if not (model.get("recovery", false) or model.get("tug", false) or not str(model.get("icebreaker", "")).is_empty()):
			widest = maxf(widest, float(model.get("map_size", [14, 6])[1]) * SHIP_SIZE)  # Cargo ships: only they moor.
	return widest


## A port's docks in dock units, from the shore end (0, 0) out to sea along +x:
## {piers: [[from, to]], quay: [from, to] or [] (Medium's), berths: [[position, facing,
## the way to its pier or quay]],
## length (the longest ship), width, mouth (where ships come in and leave) and
## tugs (where the first tug ties up, the next ones along -y)}.
func _dock_layout(band: String, berths: int) -> Dictionary:
	var key := [band, berths]
	if _dock_layouts.has(key):
		return _dock_layouts[key]
	var length := _band_ship_length(band)
	var width := _widest_ship()
	var base_length := length * 1.15 + 3.0
	var piers := int(PIERS_BY_BAND.get(band, 1))
	var spacing := 2.0 * (width + BERTH_GAP) + PIER_WIDTH + 3.0
	var layout := {piers = [], quay = [], berths = [], length = length, width = width}
	# The band's berths: a pair on each pier, and Medium's one on a quay across the
	# pier's root. A hub's extra berths lengthen the piers, a pair further out at a
	# time, round the piers in turn.
	var on_quay := 1 if band == "medium" else 0
	var extra := maxi(berths - 2 * piers - on_quay, 0)
	var rows := 1 + ceili(extra / (2.0 * piers))
	var step := length + 2.0
	for p in piers:
		var y := (p - (piers - 1) / 2.0) * spacing
		var pier_rows := 1 + ceili(maxf(extra - 2 * p, 0.0) / (2.0 * piers))
		layout.piers.append([Vector2(0.0, y), Vector2(base_length + (pier_rows - 1) * step, y)])
	for k in 2 * piers + extra:
		var p := (k / 2) % piers
		var row := k / (2 * piers)
		var y := (p - (piers - 1) / 2.0) * spacing
		var side := -1.0 if k % 2 == 0 else 1.0
		layout.berths.append([Vector2(base_length * 0.5 + 1.5 + row * step, y + side * (PIER_WIDTH / 2.0 + BERTH_GAP + width / 2.0)), PI, Vector2(0.0, -side)])
	if on_quay > 0:
		var y0 := spacing / 2.0
		layout.quay = [Vector2(1.0, y0), Vector2(1.0, y0 + step + 1.0)]
		layout.berths.insert(2, [Vector2(1.0 + PIER_WIDTH / 2.0 + BERTH_GAP + width / 2.0, y0 + 1.0 + step / 2.0), PI / 2.0, Vector2(-1.0, 0.0)])
	var reach := base_length + (rows - 1) * step
	layout.mouth = Vector2(reach + length * 0.9, 0.0)
	layout.tugs = Vector2(0.0, -(piers - 1) / 2.0 * spacing - spacing / 2.0 - TUG_STEP / 2.0)
	_dock_layouts[key] = layout
	return layout


## Where the slot-th tug lies tied up alongside the wharf (dock units, facing
## along it): one after another from the end by the piers, TUG_STEP apart.
static func _tug_mooring(layout: Dictionary, slot: int) -> Array:
	var tug_width := _tug_width()
	return [Vector2(PIER_WIDTH / 2.0 + BERTH_GAP * 0.6 + tug_width / 2.0, float(layout.tugs.y) - slot * TUG_STEP), -PI / 2.0]


static func _tug_width() -> float:
	for model: Dictionary in GameData.ship_models:
		if model.get("tug", false):
			return float(model.get("map_size", [7, 3.6])[1]) * SHIP_SIZE
	return 2.5


## A port's layout as it is now (its band and berths).
func _port_layout(port_id: String) -> Dictionary:
	return _dock_layout(GameState.port_sizes.band(port_id), GameState.docks.berth_count(port_id))


## A point of a port's docks (dock units) on screen.
func _dock_point(port_id: String, local: Vector2) -> Vector2:
	var angle := _port_sea_angle(port_id)  # (Works out the flip too.)
	return port_screen_position(port_id) + Vector2(local.x, local.y * float(_dock_flips.get(port_id, 1.0))).rotated(angle) * dock_scale(port_id)


## How big a port's docks (and the ships moored and anchored there) are drawn:
## always just like the ships at sea, so a ship keeps its size as it docks.
func dock_scale(_port_id: String) -> float:
	return _ship_scale()


## Every port's piers and quay on screen, a weathered wooden grey with a dark edge.
func _draw_docks() -> void:
	var view := Rect2(Vector2.ZERO, size).grow(80.0 * _ship_scale())
	_update_spots()
	var tugs := {}  # Port id -> how many tug spots its wharf needs (its highest kept slot + 1).
	for key: Array in _spot_tables:
		if key[1] and not (_spot_tables[key] as Dictionary).is_empty():
			tugs[key[0]] = (_spot_tables[key] as Dictionary).keys().max() + 1
	for port: Dictionary in GameData.ports:
		var root := port_screen_position(port.id)
		if not view.has_point(root):
			continue
		var layout := _port_layout(port.id)
		if float(layout.mouth.x) * _ship_scale() < DOCK_MIN_PX:
			continue  # Zoomed far out: too small to see.
		var wharf := _wharf(layout, int(tugs.get(port.id, 0)))
		var spans: Array = [wharf]
		spans.append_array(layout.piers)
		if not layout.quay.is_empty():
			spans.append(layout.quay)
		for span: Array in spans:
			_draw_pier(port.id, span[0], span[1])
		# Stone blocks where the pieces meet: each pier's root on the wharf, the
		# quay's, and the wharf's two ends.
		var joins: Array[Vector2] = [wharf[0], wharf[1]]
		for pier: Array in layout.piers:
			joins.append(pier[0])
		if not layout.quay.is_empty():
			joins.append(Vector2(0.0, float(layout.quay[0].y)))
		var placed: Array[Vector2] = []
		for join in joins:
			if placed.any(func(other: Vector2) -> bool: return other.distance_to(join) < STONE_BLOCK * 1.2):
				continue  # A pier's root at the wharf's end: one block does for both.
			placed.append(join)
			_draw_stone_block(port.id, join)


## The wharf along the shore through a port (dock units, along y): from past
## its tugs (tied up along it, TUG_STEP apart) to past its last pier.
static func _wharf(layout: Dictionary, tug_count: int) -> Array:
	var first: Vector2 = layout.piers[0][0]
	var last: Vector2 = layout.piers[-1][0]
	var tug_end := float(layout.tugs.y) - maxi(tug_count - 1, 0) * TUG_STEP - TUG_STEP / 2.0
	var quay_end: float = layout.quay[1].y if not layout.quay.is_empty() else last.y
	return [Vector2(0.0, minf(first.y, tug_end) - PIER_WIDTH), Vector2(0.0, maxf(maxf(last.y, quay_end), 0.0) + PIER_WIDTH)]


## A square block of dressed stone, split into four by its joints, where dock pieces meet.
func _draw_stone_block(port_id: String, center: Vector2) -> void:
	var half := STONE_BLOCK / 2.0
	var corners := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	var points := PackedVector2Array()
	for corner: Vector2 in corners:
		points.append(_dock_point(port_id, center + corner))
	_canvas.draw_colored_polygon(points, STONE_COLOR)
	_canvas.draw_line(_dock_point(port_id, center + Vector2(-half, 0.0)), _dock_point(port_id, center + Vector2(half, 0.0)), STONE_JOINT, 1.0, true)
	_canvas.draw_line(_dock_point(port_id, center + Vector2(0.0, -half)), _dock_point(port_id, center + Vector2(0.0, half)), STONE_JOINT, 1.0, true)
	points.append(points[0])
	_canvas.draw_polyline(points, PIER_EDGE, 1.0, true)


func _draw_pier(port_id: String, from: Vector2, to: Vector2) -> void:
	var across := (to - from).normalized().orthogonal() * PIER_WIDTH / 2.0
	var corners := PackedVector2Array([from - across, to - across, to + across, from + across])
	var points := PackedVector2Array()
	for corner in corners:
		points.append(_dock_point(port_id, corner))
	_canvas.draw_colored_polygon(points, PIER_COLOR)
	points.append(points[0])
	_canvas.draw_polyline(points, PIER_EDGE, 1.0, true)
	# Bollards along both edges, once they're far enough apart on screen to tell apart.
	var scale := dock_scale(port_id)
	if BOLLARD_STEP * scale < 4.0:
		return
	var along := (to - from).normalized()
	var axis := 0 if absf(along.x) > 0.5 else 1
	var inset := across.normalized() * (PIER_WIDTH / 2.0 - BOLLARD_INSET)
	var radius := maxf(BOLLARD_RADIUS * scale, 0.9)
	var low := minf(from[axis], to[axis])
	var high := maxf(from[axis], to[axis])
	var mark := _bollard_snap(low + BOLLARD_STEP * 0.5)
	while mark <= high - BOLLARD_STEP * 0.3:
		var on_line := from + along * (mark - from[axis]) / along[axis]
		for edge in [inset, -inset]:
			_canvas.draw_circle(_dock_point(port_id, on_line + edge), radius, BOLLARD_COLOR)
		mark += BOLLARD_STEP


## The bollard nearest a place along a pier or quay (they sit every BOLLARD_STEP
## from 0, the same on every pier and quay, so ropes always meet one).
static func _bollard_snap(along: float) -> float:
	return roundf(along / BOLLARD_STEP) * BOLLARD_STEP


## A moored ship's ropes to the bollards beside it: bow and stern lines out
## ahead and astern, and two springs crossing back along its side (a tug tied
## up at the wharf: just its bow and stern lines).
func _draw_mooring_ropes(ship: Ship) -> void:
	var port := ship.docked_at
	var layout := _port_layout(port)
	var rect: Rect2 = _model_look(ship.model_id)[7]
	var half_length := rect.size.x / 2.0
	var center: Vector2
	var ahead: Vector2
	var toward: Vector2  # Towards the pier, quay or wharf.
	var reach: float  # From its middle to the bollards.
	# [where on the hull, where along the pier (ahead of the middle)].
	var ropes := [[0.8, 0.8 * half_length + 3.0], [-0.8, -0.8 * half_length - 3.0]]
	if ship.is_tug():
		_update_spots()
		var pose := _tug_mooring(layout, int(_spot_slots.get(ship, 0)))
		center = pose[0]
		ahead = Vector2.from_angle(float(pose[1]))
		toward = Vector2(-1.0, 0.0)
		reach = center.x - PIER_WIDTH / 2.0 + BOLLARD_INSET
		ropes = [[0.7, 0.7 * half_length + 1.5], [-0.7, -0.7 * half_length - 1.5]]  # Bow and stern lines.
	else:
		if ship.berth < 0 or ship.berth >= layout.berths.size():
			return
		var berth: Array = layout.berths[ship.berth]
		center = berth[0]
		ahead = Vector2.from_angle(float(berth[1]))
		toward = berth[2]
		reach = float(layout.width) / 2.0 + BERTH_GAP + BOLLARD_INSET
		ropes.append_array([[0.35, -0.1 * half_length], [-0.35, 0.1 * half_length]])  # And springs.
	var hull := center + toward * rect.size.y / 2.0
	var edge := center + toward * reach
	var axis := 0 if absf(ahead.x) > 0.5 else 1
	var width := maxf(0.35 * dock_scale(port), 1.0)
	for rope: Array in ropes:
		var from := hull + ahead * float(rope[0]) * half_length
		var post := edge + ahead * float(rope[1])
		post[axis] = _bollard_snap(post[axis])
		_canvas.draw_line(_dock_point(port, from), _dock_point(port, post), ROPE_COLOR, width, true)


## Where a docked ship is on screen and which way it faces: moored at its
## berth (facing the shore), coming alongside from the harbour mouth, pulling
## out (backing off its berth, then turning for the sea), lying at the
## anchorage (queuing or idle; service ships too), or tied up with the tugs.
func _docked_pose(ship: Ship) -> Array:
	var port := ship.docked_at
	var layout := _port_layout(port)
	var local := _docked_local(ship, layout)  # [position, facing] in dock units.
	_last_spot[ship] = [port, local[0], local[1]]  # Where it sets off from when it sails.
	return [_dock_point(port, local[0]), _dock_angle(port, float(local[1]))]


## A dock-units facing on screen (mirrored with its port's layout).
func _dock_angle(port_id: String, facing: float) -> float:
	return _port_sea_angle(port_id) + facing * float(_dock_flips.get(port_id, 1.0))


## Where a docked ship is in dock units and which way it faces: moored at its
## berth; coming alongside (from its spot at the anchorage if it waited there,
## else from the harbour mouth); pulling out (backing off, then coming round
## for the mouth, or for its spot at the anchorage if it isn't leaving yet);
## or lying at its spot at the anchorage, or a tug's along the wharf, having
## glided there from the mouth.
func _docked_local(ship: Ship, layout: Dictionary) -> Array:
	_update_spots()
	var turn := float(layout.length) * 0.6
	if ship.berth >= 0 and ship.berth < layout.berths.size():
		var berth: Array = layout.berths[ship.berth]
		match ship.berth_phase:
			Ship.BERTH_IN:
				var t := clampf(ship.berth_time / float(Docks.settings().get("in_s", 2.5)), 0.0, 1.0)
				var start := _lying_local(ship, layout, GameState.play_time - ship.berth_time)
				return _turn_pose(start[0], start[1], berth[0], berth[1], turn, t)
			Ship.BERTH_OUT:
				var t := clampf(ship.berth_time / float(Docks.settings().get("out_s", 2.0)), 0.0, 1.0)
				var clear: Vector2 = berth[0] - Vector2.from_angle(berth[1]) * float(layout.length) * 0.9
				if t < 0.4:
					return [berth[0].lerp(clear, smoothstep(0.0, 1.0, t / 0.4)), berth[1]]  # Backing off.
				var to_anchor := ship.depart_to.is_empty()
				var goal: Vector2 = _spot_local(ship, layout) if to_anchor else layout.mouth
				var pose := _turn_pose(clear, berth[1] + PI, goal, PI if to_anchor else 0.0, turn, (t - 0.4) / 0.6)
				pose[1] = float(pose[1]) + PI * (1.0 - smoothstep(0.0, 1.0, (t - 0.4) / 0.6))  # Coming round from astern.
				return pose
		return [berth[0], berth[1]]
	return _lying_local(ship, layout, GameState.play_time)


## Where a ship lying in port (at the anchorage, or a tug at the wharf) is at a
## play time: gliding in from the harbour mouth for ANCHOR_GLIDE_S after it
## got there, then at its spot.
func _lying_local(ship: Ship, layout: Dictionary, at_time: float) -> Array:
	var spot := _spot_local(ship, layout)
	var facing := -PI / 2.0 if ship.is_tug() else PI
	var since: float = _dock_seen.get(ship, [ship.docked_at, -INF])[1]
	var t := (at_time - since) / ANCHOR_GLIDE_S
	if t >= 1.0 or ship.berth >= 0 and ship.berth_phase != Ship.BERTH_IN:
		return [spot, facing]
	return _turn_pose(layout.mouth, PI, spot, facing, float(layout.length) * 0.6, clampf(t, 0.0, 1.0))


## A ship's own spot at its port: its place in the anchorage's fixed grid (a
## tug's along the wharf), kept as long as it lies there.
func _spot_local(ship: Ship, layout: Dictionary) -> Vector2:
	_update_spots()
	var slot := int(_spot_slots.get(ship, 0))
	if ship.is_tug():
		return _tug_mooring(layout, slot)[0]
	return _anchor_spot(layout, slot)


## The slot-th spot of a port's anchorage (dock units): a fixed grid out
## beyond the harbour mouth, off to one side of the way in (the side the
## quay is, away from the tugs), ANCHOR_COLUMNS across.
static func _anchor_spot(layout: Dictionary, slot: int) -> Vector2:
	var cell := Vector2(float(layout.length) + 3.0, float(layout.width) * 2.4 + 1.0)
	var origin := Vector2(float(layout.mouth.x) + float(layout.length) * 0.6, float(layout.width) * 2.0 + cell.y / 2.0)
	return origin + Vector2(floori(slot / float(ANCHOR_COLUMNS)) * cell.x, (slot % ANCHOR_COLUMNS) * cell.y)


## Once a frame: every docked ship's spot in its port. A ship lying at the
## anchorage (or about to: coming in, or pulling out to anchor) or a tug keeps
## the slot it was given, the first free one, until it leaves; and when it
## arrived in port, for its glide in from the mouth.
func _update_spots() -> void:
	var frame := Engine.get_process_frames()
	if frame == _spots_frame:
		return
	var first := _spots_frame < 0
	_spots_frame = frame
	var alive := {}
	for ship in GameState.ships:
		if not ship.is_docked():
			continue
		alive[ship] = true
		var port := ship.docked_at
		var seen: Array = _dock_seen.get(ship, [])
		if seen.is_empty() or seen[0] != port:
			_dock_seen[ship] = [port, -INF if first else GameState.play_time]  # Already there when the map opened: no glide.
		var lies := ship.is_tug() or ship.berth < 0 or ship.berth_phase == Ship.BERTH_IN \
			or ship.berth_phase == Ship.BERTH_OUT and ship.depart_to.is_empty()
		var key := [port, ship.is_tug()]
		var taken: Dictionary = _spot_tables.get_or_add(key, {})
		if lies and not _spot_slots.has(ship):
			var slot := 0
			while taken.has(slot):
				slot += 1
			taken[slot] = ship
			_spot_slots[ship] = slot
			_spot_keys[ship] = key
		elif not lies and _spot_slots.has(ship):
			_free_spot(ship)
	for ship: Ship in _spot_slots.keys():
		if not alive.has(ship):
			_free_spot(ship)
	for ship: Ship in _dock_seen.keys():
		if not alive.has(ship):
			_dock_seen.erase(ship)


## Which way a ship eased near a port (see _harbour_blend()) faces: along the
## way it's really moving on screen, from where it is to where it'll be
## HEADING_PROBE_NM further on; its lane's heading otherwise.
func _blended_heading(ship: Ship, on_lane: Vector2, at: Vector2, lane_angle: float) -> float:
	if on_lane.distance_squared_to(at) < 0.01:
		return lane_angle  # Not near a port.
	var lane = GameData.lane(ship.from_port, ship.to_port)
	if lane == null or ship.traveled_nm + HEADING_PROBE_NM > lane.length():
		return lane_angle
	var ahead := _harbour_blend(ship, world_to_screen(lane.sample(ship.traveled_nm + HEADING_PROBE_NM)[0]))
	var way := ahead - at
	return way.angle() if way.length() > 0.2 else lane_angle


func _free_spot(ship: Ship) -> void:
	var taken: Dictionary = _spot_tables.get(_spot_keys.get(ship, []), {})
	taken.erase(_spot_slots[ship])
	_spot_slots.erase(ship)
	_spot_keys.erase(ship)


## A ship sailing near a port it's leaving or making for is drawn eased from
## where it lay there (its berth's mouth, or its spot at the anchorage) and
## towards that port's harbour mouth, so it meets its docks smoothly. The
## easing reaches 3 times the mouth's distance from the port, which (docks
## being sized in the world) is the same stretch of sea at every zoom.
func _harbour_blend(ship: Ship, at: Vector2) -> Vector2:
	if not docks_shown():
		return at
	for port: String in [ship.from_port, ship.to_port]:
		if port.is_empty():
			continue
		var layout := _port_layout(port)
		var root := port_screen_position(port)
		var mouth := _dock_point(port, layout.mouth)
		var target := mouth
		var last: Array = _last_spot.get(ship, [])
		if port == ship.from_port and not last.is_empty() and last[0] == port:
			target = _dock_point(port, last[1])
		var reach := root.distance_to(mouth) * 3.0
		var distance := at.distance_to(root)
		if distance < reach:
			at += (target - root) * (1.0 - smoothstep(0.0, reach, distance))
	return at


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
		var text_size := _feature_font(kind).get_string_size(_feature_text(i), HORIZONTAL_ALIGNMENT_LEFT, -1, style[0])
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
		var text := _feature_text(label[0])
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
	# Every company's HQ and hubs (other players' too, in multiplayer).
	var hub_ports := {}  # Port id -> [[hub, its company's ring color], ...]
	for each in GameState.all_companies():
		var each_color := _color(&"hub_ring_gray") if gray_mode else GameState.company_color_value(each.color)
		for hub in each.hubs:
			(hub_ports.get_or_add(hub.port_id, []) as Array).append([hub, each_color])
	for port: Dictionary in GameData.ports:
		if not hub_ports.has(port.id):
			draw_port.call(port.id)
	# The HQ and hubs go on top of the other ports, each with a ring in its
	# company's color (heavier for an HQ); companies sharing a port ring it in turn.
	for port_id: String in hub_ports:
		draw_port.call(port_id)
		var radius := _port_radius(port_id) + 1.0
		for entry: Array in hub_ports[port_id]:
			var width := HQ_RING_WIDTH if entry[0].is_hq else HUB_RING_WIDTH
			_canvas.draw_arc(port_screen_position(port_id), radius + width / 2.0, 0.0, TAU, 32, entry[1], width, true)
			radius += width
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
## drawn once, in the first one's color (see ORE_LANE_WHITEN). In multiplayer,
## other players' lanes go underneath, each company's once in its own color
## (see OTHER_LANE_ALPHA).
func _draw_active_lanes() -> void:
	var others := {}  # "A-B" (sorted) and company -> [from, to, color]
	var lanes := {}  # "A-B" (sorted) -> [from, to, color]
	for ship in GameState.ships:
		if ship.is_service():
			continue
		var mine := GameState.is_mine(ship)
		var color: Color
		if mine:
			color = Color.from_string(ship.model().get("map_color", "#ffffff"), Color.WHITE)
			color.a = ACTIVE_LANE_ALPHA
			if ship.model().get("category", "") == "ore":
				color = color.lerp(Color.WHITE, ORE_LANE_WHITEN)
				color.a = ORE_LANE_ALPHA
		else:
			color = GameState.company_color_value(GameState.owner_of(ship).color)
			var luminance := color.get_luminance()
			if luminance < OTHER_LANE_MIN_LUMINANCE:
				color = color.lerp(Color.WHITE, (OTHER_LANE_MIN_LUMINANCE - luminance) / (1.0 - luminance))
			color.a = OTHER_LANE_ALPHA
		var legs: Array = []
		for stops: Array[String] in [ship.route, ship.pending_route]:
			for i in stops.size():
				if stops.size() >= 2:
					legs.append([stops[i], stops[(i + 1) % stops.size()]])
		if not ship.is_docked() and not ship.is_on_job():
			legs.append([ship.from_port, ship.to_port])
		for leg: Array in legs:
			var key := "%s-%s" % ([leg[0], leg[1]] if leg[0] < leg[1] else [leg[1], leg[0]])
			if not mine:
				key += " " + GameState.owner_of(ship).name
			var into := lanes if mine else others
			if not into.has(key):
				into[key] = [leg[0], leg[1], color]
	for lane: Array in others.values() + lanes.values():
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
	if sailing.is_docked() or sailing.from_port.is_empty() or not sailing.leg_has_canal():
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
		if not ship.is_carried() and (not ship.is_docked() or docks_shown()):  # Docked ones as dots: see _draw_dock_layer().
			_draw_ship(ship, outline)
	for ship in GameState.ships:
		if ship.is_carried():
			_draw_ship(ship, outline)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_tow_lines()
	for ship in GameState.ships:
		if ship.is_towed() or not GameState.is_mine(ship):
			continue  # On its way in, or another player's: no marker.
		if ship.is_lost() and not ship.is_carried():
			_draw_marker(ship_screen_position(ship), _color(&"lost_marker"))
		elif ship.at_risk:
			_draw_marker(ship_screen_position(ship), _color(&"at_risk_marker"))


## The tow line from each lead tug's stern to the bow of the ship it's towing.
func _draw_tow_lines() -> void:
	for tug in GameState.ships:
		if not tug.is_tug() or not tug.tug_lead or tug.job_phase != Ship.JOB_TOW or tug.rescuing == null:
			continue
		var along := Vector2.from_angle(_heading_angle(tug.heading()))
		var tug_rect: Rect2 = _model_look(tug.model_id)[7]
		var ship_rect: Rect2 = _model_look(tug.rescuing.model_id)[7]
		var stern := ship_screen_position(tug) - along * tug_rect.size.x / 2.0 * _ship_scale()
		var bow := ship_screen_position(tug.rescuing) + along * ship_rect.size.x / 2.0 * _ship_scale()
		_canvas.draw_line(stern, bow, TOW_LINE_COLOR, 1.0, true)


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
	# Another player's ship (multiplayer): a little faded, with a flag in its
	# company's color at the stern.
	var fade := Color.WHITE if GameState.is_mine(ship) else Color(1, 1, 1, OTHER_SHIP_ALPHA)
	color *= fade
	outline *= fade
	if ship.is_docked() and not docks_shown():
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		if ship.is_tug():
			var tick := _tug_tick(ship)
			_canvas.draw_line(tick[0], tick[1], color, TUG_TICK_WIDTH, true)
			return
		var at := ship_screen_position(ship)
		# Stamped from two small images made once (antialiased circles are costly
		# to build each frame): the dot in the model's color, then its outline.
		var rect := Rect2(at - Vector2.ONE * DOCK_DOT_IMAGE_RADIUS, Vector2.ONE * DOCK_DOT_IMAGE_RADIUS * 2.0)
		_canvas.draw_texture_rect(_dock_dot_fill, rect, false, color)
		_canvas.draw_texture_rect(_dock_dot_ring, rect, false, outline)
		return
	var at: Vector2
	var angle: float
	if not ship.is_docked() and not ship.is_service() and ship.rescuer == null and not ship.canal_state in [Ship.CANAL_ANCHORED, Ship.CANAL_CONVOY, Ship.CANAL_TOLL]:
		# A cargo ship on its lane (most of them): where and which way from
		# one sample of the lane.
		var here := ship.lane_sample()
		if here.is_empty():
			return
		var on_lane := world_to_screen(here[0]) + _canal_lane_offset(ship)
		at = _harbour_blend(ship, on_lane)
		angle = _blended_heading(ship, on_lane, at, _heading_angle(here[1]))
	else:
		at = ship_screen_position(ship)
		angle = _screen_angle(ship)
	if not Rect2(Vector2.ZERO, size).grow(SHIP_CULL_MARGIN * _ship_scale()).has_point(at):
		return  # Off screen.
	if ship.is_docked() and docks_shown() and (ship.is_tug() or ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE):
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		_draw_mooring_ropes(ship)  # Moored: tied up to the bollards.
	_canvas.draw_set_transform(at, angle, Vector2.ONE * _ship_scale())
	var art: Dictionary = look[6]
	if not art.is_empty():
		_draw_ship_art(ship, art, look[7], color, fade)
		if fade.a < 1.0:
			var rect: Rect2 = look[7]
			_canvas.draw_circle(Vector2(rect.position.x + rect.size.y * 0.5, 0.0), rect.size.y * 0.42, GameState.company_color_value(GameState.owner_of(ship).color))
		if ship.is_recovery():
			_draw_ballast(ship, look[7])
		return
	# The hull as a quad and the bow as a triangle: simple shapes Godot needn't
	# triangulate each frame, unlike a general polygon.
	var colors := PackedColorArray([color])
	_canvas.draw_primitive(look[3], colors, PackedVector2Array())
	_canvas.draw_primitive(look[4], colors, PackedVector2Array())
	_canvas.draw_polyline(look[5], outline, 1.0)


## The hull in the model's color, the cargo (cut off behind how full the hold
## is, in CARGO_STEPS steps, any cargo showing at least one) and the details.
func _draw_ship_art(ship: Ship, art: Dictionary, rect: Rect2, color: Color, fade := Color.WHITE) -> void:
	_canvas.draw_texture_rect(art.hull, rect, false, color)
	var level := ship.cargo_level()
	if art.has("cargo") and level > 0.0:
		var zone: Vector2 = art.zone
		var fill := ceilf(level * CARGO_STEPS) / CARGO_STEPS
		var share := (zone.x + fill * (zone.y - zone.x)) / SHIP_ART_WIDTH
		var texture: Texture2D = art.cargo
		_canvas.draw_texture_rect_region(texture, Rect2(rect.position, Vector2(rect.size.x * share, rect.size.y)),
			Rect2(Vector2.ZERO, Vector2(texture.get_width() * share, texture.get_height())), fade)
	_canvas.draw_texture_rect(art.details, rect, false, fade)


## How many times its map_size a ship (and its docks) is drawn at this zoom:
## in step with the map, so a ship keeps its size in the world.
func _ship_scale() -> float:
	return _zoom / SHIP_WORLD_ZOOM


## How many times its length_px a sea animal is drawn: its size on screen until
## SHIP_GROW_FROM_ZOOM, growing a little closer in (they're too small to see
## at their real size).
func _animal_scale() -> float:
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
		var length := float(dims[0]) * SHIP_SIZE
		var width := float(dims[1]) * SHIP_SIZE
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


# --- Storms --------------------------------------------------------------

## Each storm (GameState.weather) as a soft, slowly turning cloud: a haze over
## its reach, spiral bands that wind into the core (turning anticlockwise in
## the north, clockwise in the south, as storms do), a clear eye once a
## tropical storm is strong, and its name under the core when there's room.
## The bands turn with play time, so they stop when the game is paused.
func _draw_storms() -> void:
	_draw_storm_tracks()
	var font := get_theme_default_font()
	for storm: Dictionary in GameState.weather.storms:
		var lat: float = storm.lat
		var circle := _storm_circle(storm)
		var center: Vector2 = circle[0]
		var radius: float = circle[1]
		if not Rect2(Vector2.ZERO, size).grow(radius).has_point(center):
			continue
		var strength := Weather.intensity(storm)
		var alpha := lerpf(0.35, 1.0, strength)
		var tropical := Weather.TROPICAL.has(storm.kind)
		var cloud := STORM_CLOUD
		for ring: Array in STORM_HAZE:
			_canvas.draw_circle(center, radius * float(ring[0]), Color(cloud, float(ring[1]) * alpha))
		# Map north is up on screen, so anticlockwise there is a falling angle.
		var spin := -1.0 if lat >= 0.0 else 1.0
		var turn := spin * GameState.play_time * STORM_SPIN
		var arms := 3 if tropical else 2
		for arm in arms:
			var previous := Vector2.INF
			for step in STORM_ARM_STEPS + 1:
				var t := float(step) / STORM_ARM_STEPS
				var angle := turn + TAU * arm / arms - spin * t * STORM_ARM_WIND
				var point := center + Vector2.from_angle(angle) * radius * lerpf(0.1, 0.95, t)
				if previous != Vector2.INF:
					var width := maxf(radius * lerpf(0.16, 0.04, t), 1.0)
					_canvas.draw_line(previous, point, Color(cloud, STORM_BAND_ALPHA * alpha * (1.0 - t * 0.7)), width, true)
					_canvas.draw_line(previous, point, Color(STORM_RIM, STORM_RIM_ALPHA * alpha * (1.0 - t)), maxf(width * 0.2, 1.0), true)
				previous = point
		if tropical and radius > LIGHTNING_MIN_RADIUS:
			_draw_lightning(storm, center, radius, strength)
		if tropical and strength > STORM_EYE_FROM and radius > 12.0:
			_canvas.draw_circle(center, maxf(radius * 0.045, 2.0), Color(STORM_EYE, STORM_EYE.a * alpha))
		if radius > STORM_LABEL_MIN_RADIUS:
			var text := Weather.title(storm)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE).x
			var baseline := center + Vector2(-width / 2.0, radius * 0.18 + STORM_FONT_SIZE)
			_canvas.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE, 4, Color(0, 0, 0, 0.6 * alpha))
			_canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE, Color(1, 1, 1, 0.9 * alpha))


## A storm's center on screen and its radius there (px): [center, radius].
func _storm_circle(storm: Dictionary) -> Array:
	var lat: float = storm.lat
	# Near the map's scale there, a projected degree is 60 nm x cos(latitude).
	var radius: float = float(storm.radius_nm) / (60.0 * maxf(cos(deg_to_rad(lat)), 0.1)) * _zoom
	return [world_to_screen(Geo.project(Vector2(storm.lon, lat))), radius]


## The storm with the given key, or {} if it has blown out.
static func storm_by_key(storm_key: String) -> Dictionary:
	for storm: Dictionary in GameState.weather.storms:
		if Weather.key(storm) == storm_key:
			return storm
	return {}


## Where a storm's center is on screen (local to this control), or
## Vector2.INF if it has blown out.
func storm_screen_position(storm_key: String) -> Vector2:
	var storm := storm_by_key(storm_key)
	return _storm_circle(storm)[0] if not storm.is_empty() else Vector2.INF


## The storm under a screen point (within STORM_HIT_SHARE of its radius, or
## STORM_HIT_MIN_PX of its center), the nearest if several: its key, or "".
func _storm_at(screen_pos: Vector2) -> String:
	var best := ""
	var best_share := INF
	for storm: Dictionary in GameState.weather.storms:
		var circle := _storm_circle(storm)
		var distance: float = (circle[0] as Vector2).distance_to(screen_pos)
		var reach := maxf(float(circle[1]) * STORM_HIT_SHARE, STORM_HIT_MIN_PX)
		if distance <= reach and distance / reach < best_share:
			best_share = distance / reach
			best = Weather.key(storm)
	return best


## Every storm's track: where it has been and where it will go (it keeps a
## fixed course; see Weather.track_ahead()), as one thick grey dashed line.
## The storm under the mouse or whose popup is open shows its track stronger,
## with dashed rings at its edge and at its core's edge (Weather.CORE).
func _draw_storm_tracks() -> void:
	var view := Rect2(Vector2.ZERO, size)
	for storm: Dictionary in GameState.weather.storms:
		var behind := Weather.track_behind(storm)
		var points := behind.duplicate()
		points.append_array(GameState.weather.track_ahead(storm).slice(1))
		var path := _storm_path_on_screen(points, behind.size() - 1)
		var storm_key := Weather.key(storm)
		var highlight := storm_key == _hovered_storm or storm_key == selected_storm
		var color := Color(STORM_TRACK_COLOR, STORM_TRACK_HIGHLIGHT_ALPHA if highlight else STORM_TRACK_COLOR.a)
		var bounds := Rect2(path[0], Vector2.ZERO)
		for p in path:
			bounds = bounds.expand(p)
		if view.intersects(bounds.grow(STORM_TRACK_WIDTH)):
			_draw_dashed_path(path, color, STORM_TRACK_WIDTH)
		if highlight:
			var circle := _storm_circle(storm)
			for share: float in [1.0, Weather.CORE]:
				_draw_dashed_path(_circle_points(circle[0], float(circle[1]) * share), color, 2.0)


## A storm's track points (lon, lat) on screen, unwrapped so it runs smoothly
## across the date line, placed so its point `now` (the storm's position)
## is where the storm itself is drawn.
func _storm_path_on_screen(points: PackedVector2Array, now: int) -> PackedVector2Array:
	var projected := PackedVector2Array()
	for i in points.size():
		var p := Geo.project(points[i])
		if i > 0:
			p.x = projected[i - 1].x + wrapf(p.x - projected[i - 1].x, -Geo.WORLD_WIDTH / 2.0, Geo.WORLD_WIDTH / 2.0)
		projected.append(p)
	var shift := _wrap_near(projected[now].x, _center.x) - projected[now].x
	var out := PackedVector2Array()
	for p in projected:
		out.append(size / 2.0 + Vector2(p.x + shift - _center.x, _center.y - p.y) * _zoom)
	return out


static func _circle_points(center: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var steps := clampi(int(radius / 4.0), 24, 160)
	for i in steps + 1:
		out.append(center + Vector2.from_angle(TAU * i / steps) * radius)
	return out


## A line through points, dashed along its whole length (STORM_TRACK_DASH:
## [dash, gap] px), each dash one polyline so its joins don't overlap.
func _draw_dashed_path(points: PackedVector2Array, color: Color, width: float) -> void:
	var on := true
	var left := STORM_TRACK_DASH.x
	var dash := PackedVector2Array()
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var length := a.distance_to(b)
		var at := 0.0
		while at < length:
			var step := minf(left, length - at)
			if on:
				if dash.is_empty():
					dash.append(a.lerp(b, at / length))
				dash.append(a.lerp(b, (at + step) / length))
			at += step
			left -= step
			if left <= 0.0:
				if on and dash.size() >= 2:
					_canvas.draw_polyline(dash, color, width, true)
				dash.clear()
				on = not on
				left = STORM_TRACK_DASH.x if on else STORM_TRACK_DASH.y
	if on and dash.size() >= 2:
		_canvas.draw_polyline(dash, color, width, true)


## Lightning in a tropical storm's bands (gales have little): every
## LIGHTNING_SLOT_S of play time, each of LIGHTNING_CELLS spots may flash, more
## often the stronger the storm, as a jagged bolt with a fork, a glow and a
## soft flash, lit for the first part of the slot. Where and whether is fixed
## by the storm, spot and slot, so a flash doesn't jump about between frames,
## and they stop when the game is paused.
func _draw_lightning(storm: Dictionary, center: Vector2, radius: float, strength: float) -> void:
	var slot := floori(GameState.play_time / LIGHTNING_SLOT_S)
	var into := fmod(GameState.play_time, LIGHTNING_SLOT_S) / LIGHTNING_SLOT_S
	if into > LIGHTNING_LIT:
		return
	var fade := 1.0 - into / LIGHTNING_LIT
	var rng := RandomNumberGenerator.new()
	for cell in LIGHTNING_CELLS:
		rng.seed = hash([storm.basin, storm.name, cell, slot])
		if rng.randf() > LIGHTNING_CHANCE * strength:
			continue
		# In the eyewall or out in the bands.
		var at := center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.12, 0.75)
		var length := clampf(radius * 0.32, 16.0, 70.0)
		var bolt := PackedVector2Array([at])
		var direction := Vector2.from_angle(rng.randf_range(0.9, 2.2))  # Mostly downward on screen.
		for k in 5:
			var step := direction.rotated(rng.randf_range(-0.7, 0.7)) * length / 5.0
			bolt.append(bolt[-1] + step)
		var fork := PackedVector2Array([bolt[2]])
		for k in 2:
			fork.append(fork[-1] + direction.rotated(rng.randf_range(0.4, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0)) * length / 6.0)
		# The cloud lit up around the bolt: a wide faint glow and a brighter middle.
		var middle := at.lerp(bolt[-1], 0.5)
		_canvas.draw_circle(middle, length * 0.85, Color(LIGHTNING_GLOW, 0.06 * fade))
		_canvas.draw_circle(middle, length * 0.45, Color(LIGHTNING_GLOW, 0.08 * fade))
		for line: PackedVector2Array in [bolt, fork]:
			_canvas.draw_polyline(line, Color(LIGHTNING_GLOW, 0.35 * fade), 6.0, true)
			_canvas.draw_polyline(line, Color(LIGHTNING_CORE, fade), 2.2, true)


# --- Seasonal ice --------------------------------------------------------

## The seasonal closures in force (GameState.seasonal, while active): each
## closed port ringed in ice (the frozen sea itself: IceArt; closed canals:
## _draw_ice_canals()).
func _draw_ice() -> void:
	var seasonal: Seasons = GameState.seasonal
	if not seasonal.active():
		return
	var now := GameState.calendar_time()
	for closure: Dictionary in seasonal.closures():
		if not Seasons.in_season(closure, now):
			continue
		for port_id: String in closure.get("ports", []):
			var at := port_screen_position(port_id)
			if Rect2(Vector2.ZERO, size).grow(20.0).has_point(at):
				_canvas.draw_circle(at, _port_radius(port_id) + ICE_RING_GAP, Color(ICE_COLOR, 0.35))
				_canvas.draw_arc(at, _port_radius(port_id) + ICE_RING_GAP, 0.0, TAU, 24, Color(ICE_COLOR, 0.95), 2.0, true)


## Each canal shut by a seasonal closure, frosted over along its path (drawn
## over the canal and its locks).
func _draw_ice_canals() -> void:
	var seasonal: Seasons = GameState.seasonal
	if not show_ships or not seasonal.active():
		return
	var now := GameState.calendar_time()
	for closure: Dictionary in seasonal.closures():
		if closure.has("canal") and Seasons.in_season(closure, now):
			var path := _canal_screen_path(GameData.get_canal(closure.canal))
			if path.size() >= 2:
				_canvas.draw_polyline(path, Color(ICE_COLOR, 0.8), ICE_CANAL_WIDTH, true)


## A feature label's text: its name, with " River" added to a river's unless
## the name already says river (see RIVER_WORDS): "Mississippi River".
func _feature_text(index: int) -> String:
	var data := GameData.world_map
	var text: String = data.feature_label_names[index]
	if data.feature_label_kinds[index] != FeatureKind.RIVER:
		return text
	for word in text.to_lower().split(" ", false):
		if RIVER_WORDS.has(word):
			return text
	return text + " River"


# --- Land drawings ---------------------------------------------------------

## Loads each kind of land drawing's art and sorts the drawings into
## DECOR_BUCKET-degree cells.
func _load_decor() -> void:
	var data := GameData.world_map
	for kind_name in data.decor_kind_names:
		var path := DECOR_ART_DIR + kind_name + ".svg"
		_decor_textures.append(load(path) if ResourceLoader.exists(path) else null)
	for i in data.decor_positions.size():
		var p := data.decor_positions[i]
		var cell := Vector2i(floori((p.x + 180.0) / DECOR_BUCKET), floori(p.y / DECOR_BUCKET))
		if not _decor_buckets.has(cell):
			_decor_buckets[cell] = PackedInt32Array()
		_decor_buckets[cell].append(i)


## The little drawings on the land (WorldMapData decor: mountains, trees,
## cacti, animals...), on the full-color map only. Every tier whose spacing is
## at least DECOR_MIN_SPACING_PX apart on screen shows, so more appear as the
## map zooms in; each is drawn standing on its spot, a fixed size on screen
## (a little bigger zoomed in), the lower ones in front.
func _draw_decor() -> void:
	_canvas = _decor_layer
	if gray_mode:
		return
	var data := GameData.world_map
	var max_tier := -1
	for tier in data.decor_tier_spacing.size():
		if data.decor_tier_spacing[tier] * _zoom >= DECOR_MIN_SPACING_PX:
			max_tier = tier
	if max_tier < 0:
		return
	var scale := clampf(sqrt(_zoom / DECOR_ZOOM_REFERENCE), DECOR_SCALE_RANGE.x, DECOR_SCALE_RANGE.y)
	var margin := Vector2.ONE * DECOR_SIZE_PX.y * scale / _zoom
	var a := screen_to_world(Vector2.ZERO)
	var b := screen_to_world(size)
	var low := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - margin
	var high := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + margin
	var columns := ceili(Geo.WORLD_WIDTH / DECOR_BUCKET)
	var shown := []  # [screen position, kind]
	var screen := Rect2(Vector2.ZERO, size).grow(DECOR_SIZE_PX.y * scale)
	var first_column := floori((low.x + 180.0) / DECOR_BUCKET)
	var last_column := mini(floori((high.x + 180.0) / DECOR_BUCKET), first_column + columns - 1)
	for column in range(first_column, last_column + 1):
		for row in range(floori(low.y / DECOR_BUCKET), floori(high.y / DECOR_BUCKET) + 1):
			for i: int in _decor_buckets.get(Vector2i(posmod(column, columns), row), PackedInt32Array()):
				if data.decor_tiers[i] > max_tier:
					continue
				var at := world_to_screen(data.decor_positions[i])
				if screen.has_point(at):
					shown.append([at, data.decor_kinds[i]])
	shown.sort_custom(func(p: Array, q: Array) -> bool: return p[0].y < q[0].y)
	for item: Array in shown:
		var texture := _decor_textures[item[1]]
		if texture == null:
			continue
		var kind_name := data.decor_kind_names[item[1]]
		var big := DECOR_ANIMALS.has(kind_name) or kind_name == "waves"
		var side: float = (DECOR_SIZE_PX.y if kind_name.begins_with("mountain") else (DECOR_SIZE_PX.z if big else DECOR_SIZE_PX.x)) * scale
		_canvas.draw_texture_rect(texture, Rect2(item[0] - Vector2(side / 2.0, side * 0.92), Vector2(side, side)), false)


# --- Sea animals -------------------------------------------------------------------

## Sea animals (SeaLife) show from this zoom in (px per degree), and their art
## is in SEA_ART_DIR (drawn head to the right, SEA_ART_ASPECT long for its
## width). Under water an animal is a pale blue-grey shape (SEA_SHADOW, as one looks through the sea); now and
## then a whale or orca comes up to breathe (SEA_SURFACE_S, with a blow) or
## breaches (SEA_BREACH_S, with a splash), and dolphins leap (SEA_LEAP_S).
## The selected or hovered pod's year of routes shows dashed (SEA_ROUTE_COLOR).
const SEA_LIFE_MIN_ZOOM := 10.0
const SEA_ART_DIR := "res://art/sea/"
const SEA_ART_ASPECT := 128.0 / 48.0
const SEA_SHADOW := Color(0.62, 0.78, 0.9, 0.5)
const SEA_SURFACE_S := 3.0
const SEA_BREACH_S := 2.4
const SEA_LEAP_S := 1.0
const SEA_SPLASH := Color(0.94, 0.98, 1.0)
const SEA_ROUTE_COLOR := Color(0.75, 0.95, 1.0, 0.45)
const SEA_HIT_MIN_PX := 12.0


## Every pod of sea animals in view (from the opening zoom in): a loose group
## swimming the way it's heading, each animal a shadow under the water unless
## it's up at the surface, breaching or leaping.
func _draw_sea_life() -> void:
	_pod_hits.clear()
	if gray_mode or _zoom < SEA_LIFE_MIN_ZOOM or _sea_warming:  # (They show once their paths are found.)
		return
	var sea := SeaLife.shared()
	var now := float(GameState.calendar_time())
	var view := Rect2(Vector2.ZERO, size).grow(80.0)
	var scale := _animal_scale()
	for highlight in [selected_pod, _hovered_pod]:
		if highlight >= 0 and highlight < sea.pods.size():
			_draw_pod_routes(sea, highlight)
	for i in sea.pods.size():
		var pod: Dictionary = sea.pods[i]
		var kind: Dictionary = sea.species[pod.species]
		var state := sea.state(i, now)
		var center := world_to_screen(Geo.project(state.pos))
		if not view.has_point(center):
			continue
		var heading: Vector2 = state.heading
		var target: float = Vector2(heading.x, -heading.y).angle() if heading != Vector2.ZERO else float(_pod_angles.get(i, 0.0))
		var angle := lerp_angle(float(_pod_angles.get(i, target)), target, 0.08)
		_pod_angles[i] = angle
		var shown := mini(int(pod.size), int(kind.shown))
		var spacing := float(kind.spacing_px) * scale
		var reach := spacing * sqrt(float(shown)) + float(kind.length_px) * scale * 0.5
		_pod_hits.append([i, center, maxf(reach, SEA_HIT_MIN_PX)])
		for j in shown:
			_draw_sea_animal(i, j, kind, center, angle, spacing, scale)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## One animal of a pod: its place in the group (spread round the middle,
## drifting a little), then its shadow and whatever it's doing at the surface.
func _draw_sea_animal(pod: int, j: int, kind: Dictionary, center: Vector2, angle: float, spacing: float, scale: float) -> void:
	var t := GameState.play_time
	var spot := Vector2.from_angle(j * 2.39996) * spacing * sqrt(float(j)) * 0.9
	spot += Vector2(sin(t * 0.7 + j * 1.3), cos(t * 0.5 + j * 0.9)) * spacing * 0.15
	var at := center + spot.rotated(angle)
	var facing := angle + sin(t * 1.4 + j * 2.1) * 0.12
	var length := float(kind.length_px) * scale
	var texture := _sea_texture(str(kind.art))
	if texture == null:
		return
	_draw_sea_sprite(_sea_silhouette(str(kind.art)), at, facing, length, 1.0, SEA_SHADOW)
	var dolphin: bool = kind.kind == "dolphin"
	var breach: Array = kind.get("breach", [])
	if not breach.is_empty():
		var up := _sea_event(pod, j, "breach", float(breach[0]), float(breach[1]), SEA_LEAP_S if dolphin else SEA_BREACH_S)
		if up >= 0.0:
			if dolphin:
				_draw_leap(texture, at, facing, length, up)
			else:
				_draw_breach(texture, at, facing, length, up)
			return
	var surface: Array = kind.get("surface", [])
	if not surface.is_empty():
		var up := _sea_event(pod, j, "surface", float(surface[0]), float(surface[1]), SEA_SURFACE_S)
		if up >= 0.0:
			_draw_sea_sprite(texture, at, facing, length, 1.0, Color(1, 1, 1, sin(PI * up) * 0.95))
			if up > 0.15 and up < 0.75:
				_draw_blow(at + Vector2.from_angle(facing) * length * 0.32, length, (up - 0.15) / 0.6)


## How far (0..1) an animal is through an event lasting `seconds`, or -1 if
## it isn't having one now. Play time is cut into `every`-second slots; in
## each, by the pod, animal and slot, it has the event with this chance, at a
## random moment.
static func _sea_event(pod: int, j: int, what: String, every: float, chance: float, seconds: float) -> float:
	var t := GameState.play_time
	var slot := floorf(t / every)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([pod, j, what, int(slot)])
	if rng.randf() >= chance:
		return -1.0
	var start := slot * every + rng.randf() * maxf(every - seconds, 0.0)
	var into := (t - start) / seconds
	return into if into >= 0.0 and into < 1.0 else -1.0


func _draw_sea_sprite(texture: Texture2D, at: Vector2, facing: float, length: float, grow: float, tint: Color) -> void:
	var size_px := Vector2(length, length / SEA_ART_ASPECT) * grow
	_canvas.draw_set_transform(at, facing, Vector2.ONE)
	_canvas.draw_texture_rect(texture, Rect2(-size_px / 2.0, size_px), false, tint)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A whale or orca breaching: it rises clear (bigger, lifted a little up the
## screen), then crashes back in a ring of splash and spray.
func _draw_breach(texture: Texture2D, at: Vector2, facing: float, length: float, up: float) -> void:
	var rise := sin(PI * minf(up / 0.7, 1.0))
	if up < 0.7:
		_draw_sea_sprite(texture, at - Vector2(0.0, rise * length * 0.25), facing, length, 1.0 + 0.6 * rise, Color.WHITE)
	if up > 0.55:
		_draw_splash(at, length * 0.9, (up - 0.55) / 0.45)


## A dolphin leaping: an arc ahead of its shadow, a small splash where it lands.
func _draw_leap(texture: Texture2D, at: Vector2, facing: float, length: float, up: float) -> void:
	var arc := minf(up / 0.8, 1.0)
	if up < 0.8:
		var ahead := Vector2.from_angle(facing) * (arc - 0.5) * length * 1.4
		_draw_sea_sprite(texture, at + ahead - Vector2(0.0, sin(PI * arc) * length * 0.7), facing - (arc - 0.5) * 0.5, length, 1.0 + 0.25 * sin(PI * arc), Color.WHITE)
	if up > 0.7:
		_draw_splash(at + Vector2.from_angle(facing) * length * 0.7, length * 0.6, (up - 0.7) / 0.3)


## A splash spreading out and fading (0..1): two white rings and a few drops.
func _draw_splash(at: Vector2, reach: float, t: float) -> void:
	var fade := 1.0 - t
	for ring in [1.0, 0.6]:
		_canvas.draw_arc(at, reach * (0.3 + t * 0.7) * ring, 0.0, TAU, 20, Color(SEA_SPLASH, 0.8 * fade), maxf(reach * 0.08, 1.0), true)
	for k in 6:
		var drop := at + Vector2.from_angle(k * TAU / 6.0 + 0.4) * reach * (0.4 + t * 0.9) - Vector2(0.0, sin(PI * t) * reach * 0.5)
		_canvas.draw_circle(drop, maxf(reach * 0.06, 0.8), Color(SEA_SPLASH, 0.9 * fade))


## A whale's blow: a puff of spray rising from its blowhole and fading (0..1).
func _draw_blow(at: Vector2, length: float, t: float) -> void:
	var fade := sin(PI * t)
	for k in 3:
		var puff := at - Vector2((k - 1) * length * 0.07, length * (0.1 + t * 0.35 + k * 0.05))
		_canvas.draw_circle(puff, length * (0.07 + t * 0.06), Color(SEA_SPLASH, 0.75 * fade))


func _sea_texture(art: String) -> Texture2D:
	if not _sea_art.has(art):
		var path := SEA_ART_DIR + art + ".svg"
		_sea_art[art] = load(path) if ResourceLoader.exists(path) else null
	return _sea_art[art]


## An animal's outline filled in one flat white (tinted SEA_SHADOW when drawn),
## for its shape under the water.
func _sea_silhouette(art: String) -> Texture2D:
	var key := art + "/silhouette"
	if not _sea_art.has(key):
		var texture := _sea_texture(art)
		if texture == null:
			_sea_art[key] = null
		else:
			var image := texture.get_image()
			image.decompress()
			image.convert(Image.FORMAT_RGBA8)
			image.clear_mipmaps()
			for y in image.get_height():
				for x in image.get_width():
					image.set_pixel(x, y, Color(1, 1, 1, image.get_pixel(x, y).a))
			image.generate_mipmaps()
			_sea_art[key] = ImageTexture.create_from_image(image)
	return _sea_art[key]


## A pod's year: its migration paths and the areas it stays in, dashed.
func _draw_pod_routes(sea: SeaLife, pod: int) -> void:
	for points in sea.pod_paths(pod):
		_draw_dashed_path(_storm_path_on_screen(points, 0), SEA_ROUTE_COLOR, 2.0)
	for stay: Dictionary in sea.pods[pod].stays:
		var area: Dictionary = sea.areas[stay.area]
		var lat := float(area.lat)
		var radius := float(area.radius_nm) / (60.0 * maxf(cos(deg_to_rad(lat)), 0.1)) * _zoom
		_draw_dashed_path(_circle_points(world_to_screen(Geo.project(Vector2(area.lon, lat))), radius), SEA_ROUTE_COLOR, 2.0)


## The pod under a screen point (as last drawn), the nearest if several, or -1.
func _pod_at(screen_pos: Vector2) -> int:
	var best := -1
	var best_share := INF
	for hit: Array in _pod_hits:
		var share := (hit[1] as Vector2).distance_to(screen_pos) / float(hit[2])
		if share <= 1.0 and share < best_share:
			best_share = share
			best = hit[0]
	return best


## Where a pod's middle is on screen (local to this control), as last drawn,
## or Vector2.INF if it isn't in view.
func pod_screen_position(pod: int) -> Vector2:
	for hit: Array in _pod_hits:
		if hit[0] == pod:
			return hit[1]
	return Vector2.INF


# --- Winter sea ice ----------------------------------------------------------

## Works out where the sea is frozen now (Seasons.ice_circles()); when that
## changes, the circles (projected), and shows or hides the ice.
func _update_ice() -> void:
	var circles: Array = GameState.seasonal.ice_circles() if not gray_mode else []
	if circles == _ice_key:
		return
	_ice_key = circles
	_ice_circles.clear()
	for i in circles.size():
		var circle: Array = circles[i]
		var center := Geo.project(Vector2(circle[0], circle[1]))
		var radius: float = float(circle[2]) / (60.0 * maxf(cos(deg_to_rad(circle[1])), 0.1))
		_ice_circles.append([center, radius, i * 7919 + 17])
	_ice_outlines = _merge_circles(_ice_circles)
	# With no ice, the ice layers are hidden.
	_lake_ice = _build_lake_ice()
	for k in range(0, _ice_arts.size(), 2):
		_ice_arts[k].visible = not _ice_circles.is_empty()
		_ice_arts[k + 1].visible = _lake_ice != null
	for node in _ice_arts:
		node.queue_redraw()


## Notes where each icebreaker in the ice has been (the channel it breaks) and
## forgets stretches older than ICE_REFREEZE_S (frozen over again). True while
## any channel shows (the ice needs redrawing each frame then).
func _track_icebreakers() -> bool:
	if _ice_circles.is_empty():
		if not _ice_tracks.is_empty():
			_ice_tracks.clear()
			return true
		return false
	var now := GameState.play_time
	for ship in GameState.ships:
		if not ship.is_icebreaker() or ship.is_docked() or ship.from_port.is_empty():
			continue
		var at := ship.world_position()
		if not _in_ice(at):
			continue
		var track: Array = _ice_tracks.get_or_add(ship, [])
		if track.is_empty() or (track[-1][0] as Vector2).distance_to(at) > ICE_TRACK_STEP:
			track.append([at, now])
	for ship: Ship in _ice_tracks.keys():
		var track: Array = _ice_tracks[ship]
		while not track.is_empty() and now - float(track[0][1]) > ICE_REFREEZE_S:
			track.pop_front()
		if track.is_empty() or not GameState.ships.has(ship):
			_ice_tracks.erase(ship)
	return not _ice_tracks.is_empty()


func _in_ice(at: Vector2) -> bool:
	for circle: Array in _ice_circles:
		if (circle[0] as Vector2).distance_to(at) <= circle[1]:
			return true
	return false


## Circles ([center, radius, ...]) merged into the outlines of their union
## (holes inside it are left filled).
static func _merge_circles(circles: Array) -> Array[PackedVector2Array]:
	var merged: Array[PackedVector2Array] = []
	for circle: Array in circles:
		var shape := PackedVector2Array()
		for i in ICE_OUTLINE_POINTS:
			shape.append(circle[0] + Vector2.from_angle(TAU * i / ICE_OUTLINE_POINTS) * float(circle[1]))
		# Join it with every outline it touches.
		var kept: Array[PackedVector2Array] = []
		for outline in merged:
			var joined := Geometry2D.merge_polygons(outline, shape)
			var outer := joined.filter(func(polygon: PackedVector2Array) -> bool: return not Geometry2D.is_polygon_clockwise(polygon))
			if outer.size() == 1:
				shape = outer[0]
			else:
				kept.append(outline)
		kept.append(shape)
		merged = kept
	return merged


## The lake triangles whose middles are inside the frozen circles, as one mesh
## (null if none): the frozen lakes. The lakes' triangles are sorted into
## LAKE_CELL cells by their middles once, so only those near the ice are looked at.
func _build_lake_ice() -> ArrayMesh:
	if _lake_cells.is_empty():
		for triangles in GameData.world_map.lake_triangles:
			for k in range(0, triangles.size() - 2, 3):
				var middle := (triangles[k] + triangles[k + 1] + triangles[k + 2]) / 3.0
				var cell := Vector2i(floori(middle.x / LAKE_CELL), floori(middle.y / LAKE_CELL))
				var list: PackedVector2Array = _lake_cells.get(cell, PackedVector2Array())
				list.append_array(PackedVector2Array([triangles[k], triangles[k + 1], triangles[k + 2]]))
				_lake_cells[cell] = list
	var out := PackedVector2Array()
	var taken := {}
	for circle: Array in _ice_circles:
		var center: Vector2 = circle[0]
		var radius: float = circle[1]
		for y in range(floori((center.y - radius) / LAKE_CELL), floori((center.y + radius) / LAKE_CELL) + 1):
			for x in range(floori((center.x - radius) / LAKE_CELL), floori((center.x + radius) / LAKE_CELL) + 1):
				var cell := Vector2i(x, y)
				if not _lake_cells.has(cell) or taken.has(cell):
					continue
				var triangles: PackedVector2Array = _lake_cells[cell]
				var all_in := true
				for k in range(0, triangles.size(), 3):
					if ((triangles[k] + triangles[k + 1] + triangles[k + 2]) / 3.0).distance_to(center) <= radius:
						out.append_array(PackedVector2Array([triangles[k], triangles[k + 1], triangles[k + 2]]))
					else:
						all_in = false
				if all_in:
					taken[cell] = true  # Already all in: another circle needn't add it again.
	return _triangle_mesh(out) if not out.is_empty() else null


## Draws the sea ice onto an ice node (in projected coordinates): soft edges,
## then the solid sheet, its cracks, and the channels icebreakers have broken
## (open water edged with broken ice, fading as it freezes over again).
func _draw_ice_sheet(canvas: CanvasItem) -> void:
	# Two faint rings just outside the sheet (rings rather than discs: the
	# sheet covers their middles anyway, and big see-through discs cost).
	for circle: Array in _ice_circles:
		var radius: float = circle[1]
		canvas.draw_arc(circle[0], radius * 1.085, 0.0, TAU, 64, Color(ICE_SHEET, 0.18), radius * 0.07)
		canvas.draw_arc(circle[0], radius * 1.025, 0.0, TAU, 64, Color(ICE_SHEET, 0.45), radius * 0.05)
	# The sheet: the circles merged into one outline (see _update_ice()), so
	# where they overlap it's still filled once.
	for outline in _ice_outlines:
		canvas.draw_colored_polygon(outline, ICE_SHEET)
	var rng := RandomNumberGenerator.new()
	for circle: Array in _ice_circles:
		rng.seed = circle[2]
		var center: Vector2 = circle[0]
		var radius: float = circle[1]
		for crack in ICE_CRACKS:
			var point := center + Vector2.from_angle(rng.randf() * TAU) * radius * rng.randf_range(0.0, 0.8)
			var heading := rng.randf() * TAU
			var line := PackedVector2Array([point])
			for step in 4:
				heading += rng.randf_range(-0.8, 0.8)
				point += Vector2.from_angle(heading) * radius * rng.randf_range(0.05, 0.14)
				line.append(point)
			canvas.draw_polyline(line, ICE_CRACK, -1.0)  # A hairline: antialiasing in map units costs dearly.
	var now := GameState.play_time
	var width := maxf(ICE_CHANNEL_PX / _zoom, ICE_CHANNEL_WIDTH)
	for track: Array in _ice_tracks.values():
		for k in range(1, track.size()):
			var a: Vector2 = track[k - 1][0]
			var b: Vector2 = track[k][0]
			if a.distance_to(b) > ICE_TRACK_STEP * 20.0:
				continue  # A jump (a new leg), not a channel.
			var open := 1.0 - clampf((now - float(track[k][1])) / ICE_REFREEZE_S, 0.0, 1.0)
			canvas.draw_line(a, b, Color(ICE_BROKEN, open), width * 1.8)
			canvas.draw_line(a, b, Color(ICE_CHANNEL, open), width)


## The named sea routes (seasonal closures with a label: the Northern Sea Route
## and the Northwest Passage), labeled all year at the middle of their stretch
## of sea, like the map's sea names (slanted, pale, with a dark edge), from
## ROUTE_LABEL_WEB_ZOOM in.
func _draw_route_labels() -> void:
	if gray_mode or _web_zoom() < ROUTE_LABEL_WEB_ZOOM:
		return
	var font := _feature_font(FeatureKind.SEA)
	for closure: Dictionary in GameState.seasonal.closures():
		var text := str(closure.get("label", ""))
		var circles: Array = closure.get("circles", [])
		if text.is_empty() or circles.is_empty():
			continue
		var middle := Vector2.ZERO
		for circle: Array in circles:
			middle += Geo.project(Vector2(circle[0], circle[1]))
		var at := world_to_screen(middle / circles.size())
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, ROUTE_LABEL_FONT_SIZE)
		if not Rect2(Vector2.ZERO, size).grow(text_size.x).has_point(at):
			continue
		var baseline := at + Vector2(-text_size.x / 2.0, font.get_ascent(ROUTE_LABEL_FONT_SIZE) / 2.0)
		_canvas.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ROUTE_LABEL_FONT_SIZE, SEA_LABEL_OUTLINE + 1,
			_color(&"sea_label_outline"))
		_canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, ROUTE_LABEL_FONT_SIZE, _color(&"sea_label"))

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
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
## While choosing a region to unlock (choosing_region): a locked region's
## area was clicked (its markets.json id).
signal region_clicked(region_id: String)

const THEME_TYPE := &"MapView"
## A port's dot radius grows with its size (see PortSizes): PORT_RADIUS_MIN at
## size 1, PORT_RADIUS at PORT_RADIUS_SIZE (mid-Large, the size before port
## sizes), PORT_RADIUS_MAX at 100.
const PORT_RADIUS_MIN := 3.0
const PORT_RADIUS_MAX := 9.0
const PORT_RADIUS_SIZE := 63.0
const PORT_RADIUS := 6.0
const PORT_HIT_RADIUS := 14.0
const SHIP_HIT_RADIUS := 6.0
## However small ships are drawn, a click this close (px) still picks one.
const SHIP_HIT_MIN_PX := 7.0
## Ships shorter than this on screen (px) are drawn as dots (see _draw_tiny_ship()).
const TINY_SHIP_PX := 2.5
## Storms (see _draw_storms(); their cloud is the sky's, globe.gdshader): how
## strong a tropical storm is before its eye clears (the shader's too), and
## from what on-screen radius its name is shown.
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
	"quetzal", "red_tailed_hawk", "bald_eagle", "osprey", "water_buffalo", "pizza"]
## Kinds of drawing hidden until the map is zoomed in this far (px per projected
## degree), whatever their tier: the pizza on Albuquerque is a close-up secret.
const DECOR_MIN_ZOOM := {pizza = 250.0}
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
## Closest zoom, in pixels per degree of the globe's surface.
const MAX_ZOOM := 800.0
## Furthest out, the whole globe fits the view, this share of its height across.
const GLOBE_FIT := 0.9
## The view's middle can turn right over the poles, but stops just short of
## them so north stays up.
const MAX_VIEW_LAT := 89.5
## Where a map point on the far side of the globe is "on screen": far off it,
## so whatever is drawn or hit-tested there is left out (see world_to_screen()).
const HIDDEN := Vector2(-1.0e5, -1.0e5)
## Wheel zoom eases to its goal at this rate (per second), and a flung globe
## keeps turning, slowing by this much per second (Google Earth style).
const ZOOM_EASE := 14.0
const FLING_DECAY := 4.0
## A flung globe's speed is the drag's over about its last this long (s); a
## drag that had stopped by then doesn't fling it. It's capped at this fast
## (px a second on screen).
const FLING_WINDOW_S := 0.1
const MAX_FLING_PX := 3000.0
const SPACE := Color(0.02, 0.03, 0.07)
const ATMOSPHERE := Color(0.45, 0.7, 1.0)
const GLOBE_SHADER := preload("res://scripts/ui/globe.gdshader")
## The polar caps beyond the map data (Geo.MAX_LAT) are made in cells this
## many degrees across; the Arctic one is sea at least this deep (m).
const BAND_STEP := 2.0
const ARCTIC_DEPTH := 3000
const ANTARCTIC_ICE := Color(0.93, 0.95, 0.97)
const NEVER_CULLED := Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6)
## The clouds fade out as the map zooms in between these (px a degree), and
## the storms thin to this much; the sky draws up to this many storms.
const CLOUD_ZOOM := Vector2(7.0, 24.0)
const STORM_CLOSE_ALPHA := 0.75
const MAX_SKY_STORMS := 16
## Gusts (see _draw_gusts()): one at most per this many px across, each
## blowing for this long (s of play); none in winds under GUST_STRENGTH.x,
## always one over .y; this long (px) in light wind to strong, this bright.
const GUST_CELL_PX := 90.0
const GUST_CYCLE_S := 1.6
const GUST_STRENGTH := Vector2(0.25, 1.0)
const GUST_LENGTH_PX := Vector2(10.0, 36.0)
const GUST_ALPHA := 0.55
const SELECTED_RING := Color(1.0, 0.8, 0.25)
const PORT_FONT_SIZE := 15
const COUNTRY_FONT_SIZE := 13
const LABEL_PADDING := 3.0
## A ship's pointed bow sticks out this many times its width.
const BOW_LENGTH_FACTOR := 0.6
## Ships are drawn this share of their map_size (and of everything built on it).
const SHIP_SIZE := 0.35
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
## like the coast does (tiny zoomed right out). Sea animals are sized in the
## world too, their length_px at ANIMAL_WORLD_ZOOM px a degree.
const SHIP_WORLD_ZOOM := 75.0
const ANIMAL_WORLD_ZOOM := 220.0
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
	&"port_locked": Color(0.75, 0.78, 0.85, 0.45),
	&"space": SPACE,
	&"space_gray": Color(0.12, 0.12, 0.13),
	&"atmosphere": ATMOSPHERE,
	&"atmosphere_gray": Color(0.6, 0.6, 0.62),
}

## Draw with the muted palette used by the Route Assignment screen.
@export var gray_mode := false:
	set(value):
		gray_mode = value
		_land_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED if gray_mode else SubViewport.UPDATE_ALWAYS
		if _art != null:
			_art.queue_redraw()
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

## Picking a port (the new company's home port): when not empty, only these
## port ids are named and can be clicked, each filled with its color here (the
## rest are faint dots, as in a locked region), and nothing of any company
## (region shading, HQ and hub rings) is drawn. selected_port gets a gold ring.
var selectable_ports: Dictionary = {}:
	set(value):
		selectable_ports = value
		_regions_key = []
		_labels_key = []
		_static_layer.queue_redraw()
var selected_port := "":
	set(value):
		selected_port = value
		_static_layer.queue_redraw()
## Where the view opens (when it's first given a size): centered on this port
## (by default the company's home port), zoomed right out to the whole globe if
## opens_whole_globe, else to game_config's initial_view_width_deg.
var opens_at_port := ""
var opens_whole_globe := false

## Choosing a region to unlock: every region is outlined, the locked one under
## the mouse (or hovered_region) lights up, and clicks pick regions
## (region_clicked) instead of ports and ships.
var choosing_region := false:
	set(value):
		choosing_region = value
		hovered_region = ""
		mouse_default_cursor_shape = CURSOR_ARROW
## The locked region lit up while choosing (its id), or "" (shown on the next frame).
var hovered_region := ""
## The market regions' overlay (locked ones shaded: see RegionShade), and what
## it was last set for ([image ready, unlocked regions, choosing, hovered]).
var _globe_regions := ShaderMaterial.new()
## The sky over the map: clouds and storms (see SkyArt), and its material.
var _sky := SkyArt.new()
var _globe_sky := ShaderMaterial.new()
var _regions_key := []
## Each land drawing's region (index + 1; 0 until the region map is ready), so
## those in locked regions are left out.
var _decor_regions := PackedByteArray()

## The globe: the (lon, lat) at the middle of the view, that map point
## (projected), and the view's axes on the unit sphere (see _orient()): right
## and up on screen, and out of it towards the viewer.
var _view_lon := 0.0
var _view_lat := 0.0
var _center := Vector2.ZERO
var _right := Vector3(0, 1, 0)
var _up := Vector3(0, 0, 1)
var _toward := Vector3(1, 0, 0)
## Wraps the map art round the globe (scripts/ui/globe.gdshader); the biomes'
## also cuts them to the land, drawn off screen into _land_mask at the map's
## size in real pixels (_land_mask_art, scaled up from the map's own).
var _globe := ShaderMaterial.new()
var _globe_masked := ShaderMaterial.new()
var _land_mask := SubViewport.new()
var _land_mask_art := LandMask.new()
## The wheel's zoom goal and the screen point it zooms about; the globe's spin
## after a fling ((lon, lat) degrees a second), and how far the drag has turned
## it, with where it had got to at each recent move ([msec, turned]).
var _zoom_goal := 1.0
var _zoom_about := Vector2.ZERO
var _fling := Vector2.ZERO
var _drag_turned := Vector2.ZERO
var _drag_samples: Array = []
## Each sea lane's points on the unit sphere, worked out once (see _draw_lane()).
var _lane_units := {}
## Port id -> its docks' turn on screen for the current view (see _dock_point()).
var _port_turns := {}
## Port id -> where it is on screen for the current view (see port_screen_position()).
var _port_screens := {}
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
var _zoom := 1.0  # Screen pixels per degree of the globe's surface.
var _has_fit := false
var _pressed_button: MouseButton = MOUSE_BUTTON_NONE
var _press_pos := Vector2.ZERO
var _dragging := false

## Holds the land art, drawn in projected map coordinates and wrapped round
## the globe by its material (_globe), which its children all share.
var _art_root := Node2D.new()
var _art: WorldArt = null
## The river tiers, shown or hidden by zoom.
var _river_tiers: Array[RiverTier] = []
## The land and top art (see LandArt and TopArt).
var _art_layers: Array[Node2D] = []
## Winter sea ice (see IceArt): the ice and lake ice sheet, the
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
static var _decor_textures: Array[Texture2D] = []
static var _decor_buckets := {}
var _canal_layer := Control.new()
var _static_layer := Control.new()
## The ports' marinas (see _draw_marinas()), over the land drawings and under
## the clouds, ports and labels; on the gray map, docked ships (dots in rings
## round their ports, tugs as ticks) instead. Redrawn when the view changes, a
## ship docks or leaves, and with the ports' slow size changes.
var _dock_layer := Control.new()
var _overlay := Control.new()
var _canvas: Control = _overlay
var _static_clock := 0.0
var _ports_by_rank: Array = []  # Label priority order, sorted on first draw.


## Land, coastline, borders and the equator, in projected map coordinates.
## Drawn once and cached; turning and zooming the globe only changes the
## shader (MapView._globe) that wraps it round the sphere.
class WorldArt:
	extends Node2D

	var view: MapView
	## The whole sphere's sea, poles and all, in the shallowest sea's color.
	var sea_mesh: ArrayMesh
	var land_mesh: ArrayMesh
	## Antarctica from the map data's edge to the pole, in ANTARCTIC_ICE.
	var south_cap_mesh: ArrayMesh
	var biome_mesh: ArrayMesh
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
	## The equator, a point a degree, so it curves round the globe.
	var equator := PackedVector2Array()

	## The sea, darkening band by band with depth from the shallowest; the gray
	## route map keeps one flat sea. Its children draw the rest over it (see
	## MapView._ready()).
	func _draw() -> void:
		draw_mesh(sea_mesh, white, Transform2D.IDENTITY, view._color(&"ocean"))
		if not view.gray_mode:
			for band in depth_meshes.size():
				draw_mesh(depth_meshes[band], white, Transform2D.IDENTITY, view._depth_color(band + 1))
				draw_mesh(depth_hole_meshes[band], white, Transform2D.IDENTITY, view._depth_color(band))

	func land_texture() -> Texture2D:
		return white if view.gray_mode else land_colors

	func land_tint() -> Color:
		return view._color(&"land") if view.gray_mode else Color.WHITE


## The land in its biome colors (see MapView.LAND_COLORS) or flat gray, over
## the sea and its ice. On the full-color map its child, the biomes
## (BiomeArt), are drawn over it, cut to the land.
class LandArt:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		draw_mesh(art.land_mesh, art.land_texture(), Transform2D.IDENTITY, art.land_tint())
		draw_mesh(art.south_cap_mesh, art.white, Transform2D.IDENTITY, view._color(&"land") if view.gray_mode else ANTARCTIC_ICE)


## The whole globe again, over the rest of the art, drawn by the regions'
## overlay (MapView._globe_regions): locked regions shaded, and while choosing
## one, the regions outlined and the hovered one lit up.
class RegionShade:
	extends Node2D

	var art: WorldArt

	func _draw() -> void:
		draw_mesh(art.sea_mesh, art.white)


## The whole globe once more, over the marinas, as the sky (MapView._globe_sky):
## clouds that clear as the map zooms in, and the storms. Only on the World map.
class SkyArt:
	extends Node2D

	var art: WorldArt

	func _draw() -> void:
		draw_mesh(art.sea_mesh, art.white)


## The land in plain white, into the land mask (MapView._land_mask) the
## biomes are cut to.
class LandMask:
	extends Node2D

	var art: WorldArt

	func _draw() -> void:
		draw_mesh(art.land_mesh, art.white)


## The biomes as flat-colored, straight-edged patches (WorldMapData
## biome_triangles), cut to the land by the land mask (MapView._land_mask:
## CanvasItem clip_children can't follow the globe's shader), so the edges
## between them stay sharp at any zoom. Not on the gray map.
class BiomeArt:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		if not view.gray_mode:
			draw_mesh(art.biome_mesh, art.white)


## Over the land: inland seas, and the lakes in their simplified real colors
## (plain water on the gray map).
class WaterArt:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		draw_mesh(art.water_mesh, art.white, Transform2D.IDENTITY, view._color(&"ocean"))
		for i in art.lake_meshes.size():
			if art.lake_meshes[i] != null:
				draw_mesh(art.lake_meshes[i], art.white, Transform2D.IDENTITY, view._color(&"ocean") if view.gray_mode else art.lake_colors[i])


## Over the land, lakes and lake ice: the lakes' islands, the borders, the
## coast, and the equator, faint.
class TopArt:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		var data := GameData.world_map
		draw_mesh(art.lake_island_mesh, art.land_texture(), Transform2D.IDENTITY, art.land_tint())
		draw_multiline(data.border_segments, view._color(&"border"), -1.0)
		draw_multiline(data.coast_segments, view._color(&"coast"), -1.0)
		draw_polyline(art.equator, view._color(&"equator"), -1.0)


## Winter sea ice (see MapView._ice_circles and
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


## One zoom tier of rivers, shown once the view is
## zoomed in to its min_zoom (see _update_rivers()).
class RiverTier:
	extends Node2D

	var view: MapView
	var segments: PackedVector2Array
	var min_zoom := 0.0

	func _draw() -> void:
		draw_multiline(segments, view._color(&"river"), -1.0)


func _exit_tree() -> void:
	if GameState.berth_route.get_object() == self:
		GameState.berth_route = Callable()


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	if not GameState.berth_route.is_valid():
		GameState.berth_route = berth_route_seconds  # (The first map open measures ships' ways in and out of port.)
	GameState.ships_changed.connect(func() -> void:
		_draw_order_dirty = true
		_spots_dirty = true)
	GameState.ship_changed.connect(func(_ship: Ship) -> void: _spots_dirty = true)

	var data := GameData.world_map
	var meshes := _world_meshes()
	var south_cap: ArrayMesh = meshes.south_cap
	var land_mesh: ArrayMesh = meshes.land
	var biome_mesh: ArrayMesh = meshes.biome
	var water_mesh: ArrayMesh = meshes.water
	var lake_island_mesh: ArrayMesh = meshes.lake_island
	var lake_meshes: Array[ArrayMesh] = meshes.lakes
	var depth_meshes: Array[ArrayMesh] = meshes.depths
	var depth_hole_meshes: Array[ArrayMesh] = meshes.depth_holes
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(image)
	var land_colors: Texture2D = land_colors_texture()
	if land_colors == null:
		land_colors = white
	# The land colors are drawn far below their size when zoomed out.
	_art_root.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_globe.shader = GLOBE_SHADER
	_art_root.material = _globe
	add_child(_art_root)
	var art := WorldArt.new()
	art.view = self
	art.sea_mesh = meshes.sea
	art.land_mesh = land_mesh
	art.south_cap_mesh = south_cap
	art.biome_mesh = biome_mesh
	art.water_mesh = water_mesh
	art.lake_island_mesh = lake_island_mesh
	art.lake_meshes = lake_meshes
	art.lake_colors = data.lake_colors
	art.depth_meshes = depth_meshes
	art.depth_hole_meshes = depth_hole_meshes
	art.white = white
	art.land_colors = land_colors
	for lon in range(-180, 181):
		art.equator.append(Vector2(lon, 0.0))
	_art_root.add_child(art)
	_art = art
	# Over the sea (drawn by the art itself): the sea ice, then the land and
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
	var biomes := BiomeArt.new()
	biomes.view = self
	biomes.art = art
	land.add_child(biomes)
	var water := WaterArt.new()
	water.view = self
	water.art = art
	art.add_child(water)
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
	var shade := RegionShade.new()
	shade.art = art
	art.add_child(shade)
	# Every piece of the art is wrapped round the globe by the same shader; the
	# biomes are cut to the land mask too, and the regions' overlay is its own.
	var pieces: Array[Node] = [art]
	while not pieces.is_empty():
		var piece: Node = pieces.pop_back()
		(piece as CanvasItem).use_parent_material = true
		# Its own rect (in projected degrees) says nothing about where the shader
		# puts it: never cull it.
		RenderingServer.canvas_item_set_custom_rect((piece as CanvasItem).get_canvas_item(), true, NEVER_CULLED)
		pieces.append_array(piece.get_children())
	_globe_masked.shader = GLOBE_SHADER
	_globe_masked.set_shader_parameter(&"masked", true)
	_globe_masked.set_shader_parameter(&"land_mask", _land_mask.get_texture())
	biomes.use_parent_material = false
	biomes.material = _globe_masked
	_globe_regions.shader = GLOBE_SHADER
	_globe_regions.set_shader_parameter(&"regions", true)
	shade.use_parent_material = false
	shade.material = _globe_regions
	RegionMap.build(self)
	_land_mask.transparent_bg = true
	_land_mask.disable_3d = true
	_land_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED if gray_mode else SubViewport.UPDATE_ALWAYS
	add_child(_land_mask)
	_land_mask_art.art = art
	_land_mask_art.material = _globe
	RenderingServer.canvas_item_set_custom_rect(_land_mask_art.get_canvas_item(), true, NEVER_CULLED)
	_land_mask.add_child(_land_mask_art)

	for layer: Control in [_decor_layer, _dock_layer]:
		layer.mouse_filter = MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(PRESET_FULL_RECT)
		add_child(layer)
	# The sky (clouds and storms) over the land and marinas, under the gusts, ports and ships.
	_globe_sky.shader = GLOBE_SHADER
	_globe_sky.set_shader_parameter(&"sky", true)
	_sky.art = art
	_sky.material = _globe_sky
	RenderingServer.canvas_item_set_custom_rect(_sky.get_canvas_item(), true, NEVER_CULLED)
	add_child(_sky)
	for layer: Control in [_weather_layer, _canal_layer, _static_layer, _overlay]:
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
	# Docked ships are drawn on the dock layer only on the gray map (as dots): redraw it for them only there.
	GameState.ship_changed.connect(func(_ship: Ship) -> void:
		if not docks_shown():
			_dock_layer.queue_redraw())
	GameState.ships_changed.connect(_dock_layer.queue_redraw)
	# Ship art is drawn well below its size at most zooms: mipmaps keep it smooth.
	_overlay.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_ease_view(delta)
	_update_regions()
	_update_sky()
	if not show_ships:
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


## The world art's meshes, made once and shared by every map (the World map's
## and the route screen's): {sea (the whole sphere), south_cap, land, biome,
## water, lake_island, lakes, depths, depth_holes}. The map data stops at
## Geo.MAX_LAT: the globe's caps round the poles are Antarctica's ice (flat
## ANTARCTIC_ICE: the land colors' last row, stretched to the pole, streaks)
## and the deep Arctic Ocean (added to the deep sea's bands).
static func _world_meshes() -> Dictionary:
	if not _shared_meshes.is_empty():
		return _shared_meshes
	var data := GameData.world_map
	var north_cap := _lat_band(Geo.MAX_LAT, 90.0)
	var lakes: Array[ArrayMesh] = []
	for triangles in data.lake_triangles:
		lakes.append(_triangle_mesh(triangles) if not triangles.is_empty() else null)
	var depths: Array[ArrayMesh] = []
	var depth_holes: Array[ArrayMesh] = []
	for band in data.depth_levels.size():
		var cap := north_cap if data.depth_levels[band] <= ARCTIC_DEPTH else PackedVector2Array()
		depths.append(_triangle_mesh(data.depth_triangles[band] + cap))
		depth_holes.append(_triangle_mesh(data.depth_hole_triangles[band]))
	_shared_meshes = {
		sea = _triangle_mesh(_lat_band(-90.0, 90.0)),
		south_cap = _triangle_mesh(_lat_band(-90.0, -Geo.MAX_LAT)),
		land = _triangle_mesh(data.land_triangles),
		biome = _triangle_mesh(data.biome_triangles, data.biome_colors),
		water = _triangle_mesh(data.water_triangles),
		lake_island = _triangle_mesh(data.lake_island_triangles),
		lakes = lakes,
		depths = depths,
		depth_holes = depth_holes,
	}
	return _shared_meshes


## A mesh of map triangles (already small enough to curve round the globe:
## see Geo.tessellate()), and their colors if any. Their place on LAND_COLORS
## (their UV) is worked out by the globe's shader from where they are.
static func _triangle_mesh(triangles: PackedVector2Array, colors := PackedColorArray()) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if triangles.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = triangles
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Triangles (projected) covering the globe between two latitudes, all the way
## round, in BAND_STEP-degree cells; the poles themselves are just short of
## them (Web Mercator can't reach them).
static func _lat_band(from_lat: float, to_lat: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rows := maxi(ceili((to_lat - from_lat) / BAND_STEP), 1)
	var columns := ceili(Geo.WORLD_WIDTH / BAND_STEP)
	for row in rows:
		var y0 := _mercator_y(lerpf(from_lat, to_lat, float(row) / rows))
		var y1 := _mercator_y(lerpf(from_lat, to_lat, float(row + 1) / rows))
		for column in columns:
			var x0 := -Geo.WORLD_WIDTH / 2.0 + column * Geo.WORLD_WIDTH / columns
			var x1 := x0 + Geo.WORLD_WIDTH / columns
			out.append_array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y0), Vector2(x1, y1), Vector2(x0, y1)])
	return out


## Web Mercator's northing (projected degrees) for a latitude, right up to
## (just short of) the poles, unlike Geo.project().
static func _mercator_y(lat: float) -> float:
	lat = deg_to_rad(clampf(lat, -89.99, 89.99))
	return rad_to_deg(log(tan(PI / 4.0 + lat / 2.0)))


## The sea's color for a depth band: 0 is the shallowest (the continental
## shelf, the view's background), then each of WorldMapData.depth_levels, darker
## by DEPTH_SHADES towards ocean_deep.
func _depth_color(band: int) -> Color:
	return _color(&"ocean").lerp(_color(&"ocean_deep"), DEPTH_SHADES[mini(band, DEPTH_SHADES.size() - 1)])


# --- View ----------------------------------------------------------------

## Screen position (local to this control) of a map point on the globe, seen
## straight on (an orthographic view), or HIDDEN if it's round the far side.
func world_to_screen(world: Vector2) -> Vector2:
	return _unit_to_screen(_unit(world))


func _unit_to_screen(p: Vector3) -> Vector2:
	if p.dot(_toward) < 0.0:
		return HIDDEN
	return size / 2.0 + Vector2(p.dot(_right), -p.dot(_up)) * _radius()


## The map point under a screen point (off the globe: the nearest point on its edge).
func screen_to_world(screen: Vector2) -> Vector2:
	return Geo.project(_screen_lon_lat(screen))


## The (lon, lat) under a screen point, poles and all (off the globe: the
## nearest point on its edge).
func _screen_lon_lat(screen: Vector2) -> Vector2:
	var p := _screen_unit(screen)
	return Vector2(rad_to_deg(atan2(p.y, p.x)), rad_to_deg(asin(clampf(p.z, -1.0, 1.0))))


## The point on the unit sphere (see _unit()) under a screen point (off the
## globe: the nearest point on its edge). Cheaper than screen_to_world().
func _screen_unit(screen: Vector2) -> Vector3:
	var q := (screen - size / 2.0) / _radius()
	q.y = -q.y
	var d := q.length_squared()
	if d > 1.0:
		q /= sqrt(d)
		d = 1.0
	return _right * q.x + _up * q.y + _toward * sqrt(1.0 - d)


## A map point (projected) on the unit sphere: x through (0, 0), z the north pole.
static func _unit(world: Vector2) -> Vector3:
	var lon := deg_to_rad(world.x)
	var m := deg_to_rad(world.y)
	var c := 1.0 / cosh(m)  # Web Mercator's northing back to the latitude's cos and sin.
	return Vector3(c * cos(lon), c * sin(lon), tanh(m))


## The globe's radius on screen (px): _zoom is px per degree of its surface.
func _radius() -> float:
	return _zoom * 180.0 / PI


## Pixels per projected degree at a map point (sizes in projected degrees, like
## the canals' widths, are drawn this big there): fewer towards the poles, which
## Web Mercator stretches.
func _local_zoom(world: Vector2) -> float:
	return _zoom / cosh(deg_to_rad(world.y))


## True if a screen point is round the far side of the globe (see world_to_screen()).
static func _is_hidden(screen: Vector2) -> bool:
	return screen.x <= HIDDEN.x / 2.0


## The view's axes on the unit sphere, from its middle's (lon, lat): right (east
## there), up (north there) and out towards the viewer.
func _orient() -> void:
	var lon := deg_to_rad(_view_lon)
	var lat := deg_to_rad(_view_lat)
	_toward = Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))
	_right = Vector3(-sin(lon), cos(lon), 0.0)
	_up = Vector3(-sin(lat) * cos(lon), -sin(lat) * sin(lon), cos(lat))


func port_screen_position(port_id: String) -> Vector2:
	# Asked for very often (every port, marina and docked ship, every frame), and
	# ports only move on screen when the view does: kept until it changes.
	if not _port_screens.has(port_id):
		_port_screens[port_id] = world_to_screen(GameData.port_position(port_id))
	return _port_screens[port_id]


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
			# At the ship it's towing, as that's drawn (eased into its harbour near port).
			return ship_screen_position(ship.rescuing) + Vector2.from_angle(_heading_angle(ship.heading(), ship.world_position())) * _tug_offset(ship)
		var harbour := _harbour_pose(ship)
		if not harbour.is_empty():
			return harbour[0]
		return world_to_screen(ship.world_position()) + _canal_lane_offset(ship)
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
	if not (ship.is_tug() and ship.job_phase == Ship.JOB_TOW):
		var harbour := _harbour_pose(ship)
		if not harbour.is_empty():
			return harbour[1]
	return _heading_angle(ship.heading(), ship.world_position())


## The on-screen angle of a heading (a direction in map coordinates, which keep
## compass angles) at a map point: turned with the globe's north there, and
## foreshortened towards its edge.
func _heading_angle(direction: Vector2, at: Vector2) -> float:
	if direction == Vector2.ZERO:
		return 0.0
	var way := _screen_way(at, direction.normalized())
	return way.angle() if way != Vector2.ZERO else Vector2(direction.x, -direction.y).angle()


## Which way on screen (unscaled) a direction (east, north) at a map point goes.
func _screen_way(at: Vector2, direction: Vector2) -> Vector2:
	var p := _unit(at)
	var lon := deg_to_rad(at.x)
	var east := Vector3(-sin(lon), cos(lon), 0.0)
	var along := east * direction.x + p.cross(east) * direction.y
	return Vector2(along.dot(_right), -along.dot(_up))


## How much the globe turns things drawn at a map point (radians): the screen
## angle of east there (0 at the view's middle, where north is straight up).
func _turn_at(at: Vector2) -> float:
	return _screen_way(at, Vector2.RIGHT).angle()


## The on-screen angle of a lane's heading `mile` along it.
func _lane_angle(from_port: String, to_port: String, mile: float) -> float:
	var lane = GameData.lane(from_port, to_port)
	if not lane:
		return 0.0
	var sample: Array = lane.sample(mile)
	return _heading_angle(sample[1], sample[0])


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
	var lane_angle := _heading_angle(ship.lane_heading(), ship.world_position())
	if ship.is_tug():
		# Out at the lost ship, it turns round to face home and takes its place
		# for the tow: ahead of the ship (the lead, on the tow line) or at its stern.
		if ship.job_phase != Ship.JOB_ALIGN or ship.rescuing == null:
			return []
		var home := lane_angle + PI
		var at := ship_screen_position(ship.rescuing)  # Turning round by the lost ship, where it's drawn.
		return _turn_pose(at, lane_angle, at + Vector2.from_angle(home) * _tug_offset(ship), home, radius,
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
	return [base, _heading_angle(ship.heading(), ship.world_position())]


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

## Turns the globe to center a port, keeping the zoom.
func focus_port(port_id: String) -> void:
	_look_at(GameData.port_position(port_id))
	_changed()


## Brings a ship (its port while docked) into view, keeping the zoom: centered
## across, and raised_px above the middle (to leave room for its popup below).
func focus_ship(ship: Ship, raised_px := 0.0) -> void:
	_look_at(GameData.port_position(ship.docked_at) if ship.is_docked() else ship.world_position())
	_look_at(screen_to_world(size / 2.0 + Vector2(0.0, raised_px)))
	_changed()


## Centers on a port (by default the company's home port), showing
## game_config.json's initial_view_width_deg degrees of the globe across.
func reset_view(center_port := "") -> void:
	if center_port.is_empty():
		center_port = GameState.home_port
	var width := float(GameData.config.get("initial_view_width_deg", 45.0))
	_look_at(GameData.port_position(center_port) if not center_port.is_empty() else Vector2.ZERO)
	_zoom = clampf(size.x / width, _min_zoom(), MAX_ZOOM)
	_zoom_goal = _zoom
	_changed()


## Turns the globe so a map point is in the middle of the view.
func _look_at(world: Vector2) -> void:
	var lon_lat := Geo.unproject(world)
	_view_lon = lon_lat.x
	_view_lat = lon_lat.y
	_fling = Vector2.ZERO
	_orient()


## Zoomed right out, the whole globe fits the view (GLOBE_FIT of its height
## or width across, whichever is less).
func _min_zoom() -> float:
	return minf(size.x, size.y) * GLOBE_FIT / 2.0 * PI / 180.0


func _on_resized() -> void:
	if not _has_fit and size.x > 0 and size.y > 0:
		_has_fit = true
		reset_view(opens_at_port)
		if opens_whole_globe:
			_zoom = _min_zoom()
			_zoom_goal = _zoom
			_changed()
	else:
		_zoom = maxf(_zoom, _min_zoom())
		_zoom_goal = maxf(_zoom_goal, _min_zoom())
		_changed()


## Drag to turn the globe (the map follows the mouse; let go while moving and
## it keeps turning, slowing to a stop), wheel to zoom in and out about the
## mouse (easing there: see _process()).
func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button:
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					var step := ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP
					_zoom_goal = clampf(_zoom_goal * step, _min_zoom(), MAX_ZOOM)
					_zoom_about = button.position
					_fling = Vector2.ZERO
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				if button.pressed and _pressed_button == MOUSE_BUTTON_NONE:
					_pressed_button = button.button_index
					_press_pos = button.position
					_dragging = false
					_fling = Vector2.ZERO
					_drag_turned = Vector2.ZERO
					_drag_samples.clear()
				elif not button.pressed and button.button_index == _pressed_button:
					if not _dragging and button.button_index == MOUSE_BUTTON_LEFT:
						_click(button.position)
					elif _dragging:
						_fling = _drag_fling()
					_pressed_button = MOUSE_BUTTON_NONE
					_dragging = false
		accept_event()
		return

	var motion := event as InputEventMouseMotion
	if motion and _pressed_button != MOUSE_BUTTON_NONE:
		if not _dragging and motion.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			var turn := _drag_turn(motion.position, motion.relative)
			_turn_by(turn)
			_drag_turned += turn
			var now := Time.get_ticks_msec()
			_drag_samples.append([now, _drag_turned])
			while now - int(_drag_samples[0][0]) > FLING_WINDOW_S * 2000.0:
				_drag_samples.pop_front()
			_changed()
		accept_event()
	elif motion and choosing_region:
		hovered_region = _locked_region_at(motion.position)
		mouse_default_cursor_shape = CURSOR_ARROW if hovered_region.is_empty() else CURSOR_POINTING_HAND
	elif motion:
		var pod := _pod_at(motion.position) if show_ships else -1
		_hover(pod, _storm_at(motion.position) if show_ships and pod < 0 else "")


## How far (lon, lat degrees) to turn the globe so the map under the mouse
## follows it as it moves by `moved` to `at`: up and down by the globe's
## radius, across by the size of the circle of latitude under the mouse
## (round the pole, a drag across spins the globe about it).
func _drag_turn(at: Vector2, moved: Vector2) -> Vector2:
	var degrees := 180.0 / PI / _radius()
	var lat := _view_lat
	if (at - size / 2.0).length() < _radius():
		lat = _screen_lon_lat(at).y
	return Vector2(-moved.x * degrees / maxf(cos(deg_to_rad(lat)), 0.2), moved.y * degrees)


## How fast to keep the globe turning as a drag lets go ((lon, lat) degrees
## a second): as fast as the drag turned it over its last FLING_WINDOW_S, or
## not at all if it had stopped by then.
func _drag_fling() -> Vector2:
	var now := Time.get_ticks_msec()
	var window := FLING_WINDOW_S * 1000.0
	if _drag_samples.is_empty() or now - int(_drag_samples[-1][0]) > window / 2.0:
		return Vector2.ZERO
	var from: Array = _drag_samples[-1]
	for sample: Array in _drag_samples:
		if now - int(sample[0]) <= window:
			from = sample
			break
	var seconds := maxf((now - int(from[0])) / 1000.0, 1.0 / 60.0)
	var speed: Vector2 = (_drag_turned - (from[1] as Vector2)) / seconds
	return speed.limit_length(MAX_FLING_PX / _zoom)


func _turn_by(turn: Vector2) -> void:
	_view_lon = wrapf(_view_lon + turn.x, -180.0, 180.0)
	_view_lat = clampf(_view_lat + turn.y, -MAX_VIEW_LAT, MAX_VIEW_LAT)
	_orient()


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
	if choosing_region:
		var region := _locked_region_at(screen_pos)
		if not region.is_empty():
			region_clicked.emit(region)
		return
	var nearest_port := ""
	var nearest_ship: Ship = null
	var nearest_dist := INF
	for port: Dictionary in GameData.ports:
		if _port_locked(port.id):
			continue
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


## Zooms by a factor, keeping the map point under a screen point there (if
## it's on the globe; else about the middle).
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var on_globe := (screen_pos - size / 2.0).length() < _radius() * 0.98
	var anchor := _screen_lon_lat(screen_pos)
	_zoom = clampf(_zoom * factor, _min_zoom(), MAX_ZOOM)
	if on_globe:
		# Turn the globe till the anchor is back under it (a few steps settle it).
		for i in 3:
			var now := _screen_lon_lat(screen_pos)
			_turn_by(Vector2(wrapf(anchor.x - now.x, -180.0, 180.0), anchor.y - now.y))
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
	_view_lon = wrapf(_view_lon, -180.0, 180.0)
	_view_lat = clampf(_view_lat, -MAX_VIEW_LAT, MAX_VIEW_LAT)
	_orient()
	_center = Geo.project(Vector2(_view_lon, _view_lat))
	for material in [_globe, _globe_masked, _globe_regions, _globe_sky]:
		material.set_shader_parameter(&"land_top", Geo.project(Vector2(0.0, Geo.MAX_LAT)).y)
		material.set_shader_parameter(&"east", _right)
		material.set_shader_parameter(&"north", _up)
		material.set_shader_parameter(&"toward", _toward)
		material.set_shader_parameter(&"center", size / 2.0)
		material.set_shader_parameter(&"radius", _radius())
	var pixels := get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0
	_land_mask.size = Vector2i((size * pixels).ceil()).max(Vector2i.ONE)
	_land_mask_art.scale = Vector2.ONE * pixels
	_port_turns.clear()
	_port_screens.clear()
	_update_rivers()
	if not _ice_circles.is_empty():
		for node in _ice_arts:
			node.queue_redraw()  # So do the cracks and channels.
	queue_redraw()
	_redraw_layers()
	view_changed.emit()


## Eases the zoom towards the wheel's goal, and keeps a flung globe turning,
## slowing to a stop.
func _ease_view(delta: float) -> void:
	if _dragging:
		return
	if _zooming():
		var ratio := _zoom_goal / _zoom
		_zoom_at(_zoom_about, ratio if absf(log(ratio)) < 0.01 else pow(ratio, clampf(delta * ZOOM_EASE, 0.0, 1.0)))
	if _fling != Vector2.ZERO:
		_turn_by(_fling * delta)
		_fling *= exp(-FLING_DECAY * delta)
		if _fling.length() * _zoom < 10.0:  # Under about 10 px a second: stopped.
			_fling = Vector2.ZERO
		_changed()


## The sky (World map only): its clouds fade out as the map zooms in from
## CLOUD_ZOOM.x to .y px a degree, so ships show, and the storms thin to
## STORM_CLOSE_ALPHA; and the storms, each with its strength, kind and turn.
func _update_sky() -> void:
	_sky.visible = show_ships and not gray_mode
	if not _sky.visible:
		return
	var fade := 1.0 - smoothstep(CLOUD_ZOOM.x, CLOUD_ZOOM.y, _zoom)
	_globe_sky.set_shader_parameter(&"time", GameState.play_time)
	_globe_sky.set_shader_parameter(&"cloud_alpha", fade)
	_globe_sky.set_shader_parameter(&"storm_alpha", lerpf(STORM_CLOSE_ALPHA, 1.0, fade))
	var shapes := PackedVector4Array()
	var looks := PackedVector4Array()
	shapes.resize(MAX_SKY_STORMS)
	looks.resize(MAX_SKY_STORMS)
	var count := 0
	for storm: Dictionary in GameState.weather.storms:
		if count >= MAX_SKY_STORMS:
			break
		var at := _unit(Geo.project(Vector2(storm.lon, storm.lat)))
		shapes[count] = Vector4(at.x, at.y, at.z, float(storm.radius_nm) / Geo.EARTH_RADIUS_NM)
		looks[count] = Vector4(Weather.intensity(storm), 1.0 if Weather.TROPICAL.has(storm.kind) else 0.0,
			1.0 if float(storm.lat) >= 0.0 else -1.0, float(hash(Weather.key(storm)) % 1000) / 37.0)
		count += 1
	_globe_sky.set_shader_parameter(&"storm_count", count)
	_globe_sky.set_shader_parameter(&"storm_a", shapes)
	_globe_sky.set_shader_parameter(&"storm_b", looks)


## Keeps the regions' overlay in step with the unlocked regions (which a
## joined player's game hears of from the host), and with choosing one; when
## they change, the ports, docks and land drawings are redrawn too.
func _update_regions() -> void:
	var key := [RegionMap.is_ready(), GameState.regions.duplicate(), choosing_region, hovered_region, selectable_ports.is_empty()]
	if key == _regions_key:
		return
	_regions_key = key
	var locked := 0
	var regions: Array = GameData.markets.get("regions", [])
	for i in regions.size():
		if selectable_ports.is_empty() and not GameState.is_region_unlocked(regions[i].id):
			locked |= 1 << i
	_globe_regions.set_shader_parameter(&"region_map", RegionMap.texture)
	_globe_regions.set_shader_parameter(&"region_ports", RegionMap.ports_texture)
	_globe_regions.set_shader_parameter(&"locked_mask", locked)
	_globe_regions.set_shader_parameter(&"choosing", choosing_region)
	_globe_regions.set_shader_parameter(&"hovered", RegionMap.index_of(hovered_region))
	_labels_key = []
	_redraw_layers()


## True if a port's region is locked (its name, dock and clicks are hidden).
func _port_locked(port_id: String) -> bool:
	if not selectable_ports.is_empty():
		return not selectable_ports.has(port_id)
	return not GameState.is_port_unlocked(port_id)


## The locked region at a screen point (its id), or "" (unlocked, or off the globe).
func _locked_region_at(screen_pos: Vector2) -> String:
	if (screen_pos - size / 2.0).length() >= _radius():
		return ""
	var region := RegionMap.region_id(RegionMap.region_at(_screen_lon_lat(screen_pos)))
	return region if not region.is_empty() and not GameState.is_region_unlocked(region) else ""


## Where a region's unlock button goes on screen (HIDDEN round the far side,
## or until the regions are worked out).
func region_screen_position(region_id: String) -> Vector2:
	var middle := RegionMap.center(RegionMap.index_of(region_id))
	return world_to_screen(Geo.project(middle)) if middle != Vector2.INF else HIDDEN


## True if a land drawing is in a locked region.
func _decor_locked(index: int) -> bool:
	if not RegionMap.is_ready() or not selectable_ports.is_empty():
		return false
	var data := GameData.world_map
	if _decor_regions.is_empty():
		_decor_regions.resize(data.decor_positions.size())
		for i in data.decor_positions.size():
			_decor_regions[i] = RegionMap.region_at(Geo.unproject(data.decor_positions[i])) + 1
	return not GameState.is_region_unlocked(RegionMap.region_id(_decor_regions[index] - 1))


## True while the wheel's zoom is still easing to its goal.
func _zooming() -> bool:
	return absf(log(_zoom_goal / _zoom)) > 0.001


func _color(color_name: StringName) -> Color:
	var gray_name := StringName(color_name + "_gray")
	if gray_mode and FALLBACK_COLORS.has(gray_name):
		color_name = gray_name
	if has_theme_color(color_name, THEME_TYPE):
		return get_theme_color(color_name, THEME_TYPE)
	return FALLBACK_COLORS.get(color_name, Color.MAGENTA)


# --- Drawing -------------------------------------------------------------

## Space round the globe, with a soft glow of air at its edge (the globe
## itself is the map art: see WorldArt). Zoomed in past the corners, all sea.
func _draw() -> void:
	var middle := size / 2.0
	var radius := _radius()
	if middle.length() < radius:
		draw_rect(Rect2(Vector2.ZERO, size), _color(&"ocean"))
		return
	draw_rect(Rect2(Vector2.ZERO, size), _color(&"space"))
	var glow := _color(&"atmosphere")
	for k in 8:
		var reach := 1.0 + 0.008 * (8 - k)
		draw_colored_polygon(_circle_points(middle, radius * reach).slice(0, -1), Color(glow, glow.a * 0.09))
	draw_colored_polygon(_circle_points(middle, radius).slice(0, -1), _color(&"ocean"))


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
		_draw_gusts()


## Gusts of wind (see Wind): short pale streaks blowing the way the wind does
## there, each drifting along and fading in and out over GUST_CYCLE_S of play,
## one now and then in each GUST_CELL_PX cell of the screen (somewhere new
## each time), more often, longer and brighter the stronger the wind. Gone in
## a calm, crowded in a gale or a storm.
func _draw_gusts() -> void:
	if gray_mode:
		return
	var t := GameState.play_time
	var storms := GameState.weather.storms
	var middle := size / 2.0
	var reach := _radius() * 0.97
	var rng := RandomNumberGenerator.new()
	for row in ceili(size.y / GUST_CELL_PX):
		for col in ceili(size.x / GUST_CELL_PX):
			rng.seed = hash([col, row])
			var cycle := t / GUST_CYCLE_S + rng.randf()
			rng.seed = hash([col, row, floori(cycle)])
			var at := Vector2(col + rng.randf(), row + rng.randf()) * GUST_CELL_PX
			if at.distance_to(middle) > reach:
				continue
			var lon_lat := _screen_lon_lat(at)
			var wind := Wind.at(lon_lat, t, storms)
			var strength := wind.length()
			if rng.randf() > smoothstep(GUST_STRENGTH.x, GUST_STRENGTH.y, strength):
				continue
			var way := _screen_way(Geo.project(lon_lat), wind / strength).normalized()
			var u := fposmod(cycle, 1.0)
			var length := lerpf(GUST_LENGTH_PX.x, GUST_LENGTH_PX.y, clampf(strength / 1.5, 0.0, 1.0))
			var head := at + way * length * u * 1.5
			var alpha := sin(PI * u) * clampf(strength, 0.0, 1.2) * GUST_ALPHA
			_canvas.draw_polyline_colors(PackedVector2Array([head - way * length, head - way * length * 0.4, head]),
				PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, alpha * 0.6), Color(1, 1, 1, alpha)]), 1.5, true)


func _draw_canal_layer() -> void:
	_canvas = _canal_layer
	_draw_canals()
	_draw_ice_canals()


func _draw_static_layer() -> void:
	_canvas = _static_layer
	# Where labels go only changes with the view (or the hubs), not every frame.
	var key := [_center, _zoom, size, GameState.hubs.map(func(hub: Hub) -> String: return hub.port_id), selected_port]
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
		_draw_marinas()
	var outline := _color(&"ship_outline")
	for ship in GameState.ships:
		if ship.is_docked() and not docks_shown():  # (Shown, docked ships are drawn with the others: see _draw_ships().)
			_draw_ship(ship, outline)
	_canvas = _overlay


# --- Marinas -------------------------------------------------------------------------

## Each port is a marina (see Docks), grown out of its circle on the map: the
## circle sits on the coast, facing the sea (_port_sea_angle()), cleared of
## any land and dug out to water. Its inland half is the berths, one per side
## of a half-polygon inside it (Small a half-square, 2 sides; Medium half a
## hexagon, 3; Large half an octagon, 4; Giant half a decagon, 5), each side
## long enough for the longest ship that can dock there, with a stone quay
## behind; a hub port (any company's HQ or hub) has 6 berths and, in the
## middle, a slip running inland with a big berth along each wall. Its seaward half is a
## jetty, a breakwater round the circle with the entrance in the middle (red
## and green lights on its ends). Ships waiting or idle in port, tugs and other
## service ships lie at the port's anchorage (data/anchorages.json; see
## _anchor_spots()), each at its own anchor, swung round to face into the wind.
## Geometry is in "dock units", the ships' own map size, turned to face the sea
## and sized like the ships, in the world (_ship_scale()); +x is out to sea.
## Ships in harbour sail at their own speed, as at sea (see _sailed_share()),
## but at least this (nm/s), so one at a standstill still gets in.
const MIN_HARBOUR_SPEED := 0.5
## A port's marina is drawn (and its dot not) once its radius on screen is this
## many px more than the dot's.
const MARINA_OVER_DOT_PX := 2.0
## No marina reaches further than this from its port (dock units, its slip and all).
const MARINA_MAX_REACH := 60.0
## Nor does a port's furthest anchor point (dock units: data/anchorages.json's
## 420 nm, plus the ship), for culling.
const PORT_MAX_REACH := 300.0
## A ship near a port curves between its lane and its harbour over at least
## this many times the harbour's distance from the port in lane (see
## _harbour_pose()).
const HARBOUR_REACH := 3.0
## The shortest stretch of lane (nm) a ship curves in or out of port over.
const HARBOUR_MIN_NM := 2.0
## How hard the curve leans into each end's heading (a share of its length):
## a little less than elsewhere, so ships don't swing too wide round a breakwater.
const HARBOUR_CURVE_HANDLE := 0.3
## How many straight pieces each curve of a ship's path in and out of port is drawn in.
const POSE_PATH_STEPS := 32
## A ship weighing (or dropping) anchor comes round from (or to) facing the
## wind over this share of its way out of (or to) its spot, but at least this
## long (s of play; see _anchor_turn()).
const ANCHOR_TURN_SHARE := 0.3
const ANCHOR_TURN_MIN_S := 3.0
## In harbour a ship slows for any bend tighter than this many of its lengths
## across (turning radius), and never below this share of its speed.
const HARBOUR_TURN_LENGTHS := 1.0
const HARBOUR_CRAWL := 0.15
## A port's sea direction comes from about this many of its lanes, this far out.
const SEA_ANGLE_LANES := 24
const SEA_ANGLE_MILES := 12.0
## The quay behind the berths and the jetty round the sea side (dock units
## wide), the gap between a moored ship and the quay, room to spare along each
## berth (past the ship's length and its corners' room: see _marina_layout()), and
## the entrance (this many times the widest ship that can come in).
const QUAY_WIDTH := 0.9
const JETTY_WIDTH := 0.8
const BERTH_GAP := 0.3
const BERTH_ROOM := 0.6
const ENTRANCE_WIDTHS := 3.0
## The slip at a hub port: as long as the longest of the biggest ships plus this,
## and this many times the widest across (one moored each side, room between).
const SLIP_ROOM := 3.0
const SLIP_WIDTHS := 3.8
## Points round the marina's circle, for drawing.
const MARINA_ARC_POINTS := 64
const QUAY_COLOR := Color(0.6, 0.58, 0.54)
const QUAY_EDGE := Color(0.25, 0.23, 0.2)
const JETTY_COLOR := Color(0.52, 0.53, 0.56)
const ENTRANCE_LIGHTS := [Color(0.9, 0.15, 0.12), Color(0.15, 0.85, 0.3)]
## Bollards (the tie-down posts) every BOLLARD_STEP along each berth's quay
## edge, BOLLARD_INSET back from it; a moored ship is tied to them by four
## ropes (bow and stern lines and two springs).
const BOLLARD_STEP := 1.75
const BOLLARD_INSET := 0.35
const BOLLARD_RADIUS := 0.25
const BOLLARD_COLOR := Color(0.16, 0.15, 0.14)
const ROPE_COLOR := Color(0.95, 0.9, 0.74)
## Coming in, how far off the berth (ship widths) a ship lies before it slides
## in sideways on its thrusters (and pulling out, slides off to).
const BERTH_OFF_WIDTHS := 1.6
## Ships keep to the right-hand side of a harbour entrance, this many widths
## (of the widest ship the marina takes) off its middle.
const KEEP_RIGHT_WIDTHS := 0.6
## A ship backing out of a berth it lies bow in to (a hub's slip) goes this
## share of its speed, then turns round in this long (s of play) on its
## thrusters before heading out (see _unberth_plan()).
const UNBERTH_REVERSE_SPEED := 0.5
const UNBERTH_TURN_S := 2.5
## At anchor in a storm, ships swing and pitch on their anchors, up to this
## far (radians) at full strength.
const STORM_SWING := 0.45
const BAND_RANK := {small = 0, medium = 1, large = 2, giant = 3}
## data/port_facing.json, and port id -> the sea's direction from it on screen (see _port_sea_angle()).
const PORT_FACING_PATH := "res://data/port_facing.json"
## data/anchorages.json (tools/build_anchorages.gd): each port's anchor points.
const ANCHORAGES_PATH := "res://data/anchorages.json"
static var _port_facing := {}
## The world art's meshes, shared by every map (see _world_meshes()).
static var _shared_meshes := {}
static var _anchorages := {}
var _sea_angles := {}
## Port id -> 1 or -1: which way its marina's local +y goes (see _port_sea_angle()).
var _dock_flips := {}
## [band, hub port] -> its marina's layout (see _marina_layout()).
var _marina_layouts := {}
## Port id -> its marina's layout this frame, and the frame (see _port_layout()).
var _port_layouts := {}
var _port_layouts_frame := -1
## Port id and anchorage -> [the marina radius they were for, its anchor points (lon, lat) clear of it] (see _anchor_spots()).
var _spot_cache := {}
## Each lying ship's spot (see _update_spots()): [port, "all" or "small"] ->
## {slot: ship}, ship -> its slot and that key, when it got to its port ([port,
## play time]), and where it last lay in port ([port, map point]).
var _spot_tables := {}
var _spot_slots := {}
var _spot_keys := {}
var _spots_frame := -1
## Set when any ship changes (docks, leaves, takes or gives up a berth): the
## spots are only looked at again then.
var _spots_dirty := true
var _dock_seen := {}
var _last_spot := {}
## Ship -> [its leg, how far it curves in and out of port] (see _harbour_reaches()).
var _harbour_reach_cache := {}
## Port id -> the way into the wind there on screen, worked out once a frame.
var _upwind := {}
## Port id -> the strongest storm's strength there, this frame (see _storm_strength_at_port()).
var _port_storms := {}
## Each docked ship's screen pose this frame, and the frame (see _docked_pose()).
var _poses := {}
var _poses_frame := -1
## Ship -> [port, anchorage, slot, marina radius, its anchor on the unit sphere] (see _anchor_screen_cached()).
var _anchor_units := {}
## Model id -> the anchorage its ships lie in (see _anchor_pool()).
var _anchor_pools := {}
## Port id -> _marina_shown() this frame, and the frame.
var _marinas_shown := {}
var _marinas_shown_frame := -1
var _upwind_frame := -1


func docks_shown() -> bool:
	return show_ships and not gray_mode


## Which way the sea is from a port, as an on-screen angle with north straight
## up (the globe turns it: _port_turn()), and which side is its marina's +y:
## from data/port_facing.json, or else the average way its sea lanes head out
## of it.
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
	_dock_flips[port_id] = 1.0
	return angle


## A (lon, lat) point moved by degrees east and north (east scaled for the latitude).
static func _lon_lat_offset(at: Vector2, degrees: Vector2) -> Vector2:
	return at + Vector2(degrees.x / maxf(cos(deg_to_rad(at.y)), 0.1), degrees.y)


## The longest ship (dock units, bow included) that can dock at ports of a band,
## and the widest that can dock there (only cargo ships moor at berths).
static func _band_ship_length(band: String) -> float:
	var longest := 0.0
	for model: Dictionary in GameData.ship_models:
		if model.get("recovery", false) or model.get("tug", false) or not str(model.get("icebreaker", "")).is_empty():
			continue
		var needs := str(model.get("min_port", "small"))
		if int(BAND_RANK.get(needs, 0)) > int(BAND_RANK.get(band, 0)):
			continue
		longest = maxf(longest, _model_length(model))
	return longest


static func _widest_ship(band: String) -> float:
	var widest := 0.0
	for model: Dictionary in GameData.ship_models:
		if model.get("recovery", false) or model.get("tug", false) or not str(model.get("icebreaker", "")).is_empty():
			continue  # Cargo ships: only they moor.
		if int(BAND_RANK.get(str(model.get("min_port", "small")), 0)) > int(BAND_RANK.get(band, 0)):
			continue
		widest = maxf(widest, float(model.get("map_size", [14, 6])[1]) * SHIP_SIZE)
	return widest


## A model's length and width in dock units (bow included).
static func _model_length(model: Dictionary) -> float:
	var dims: Array = model.get("map_size", [14, 6])
	return (float(dims[0]) + float(dims[1]) * BOW_LENGTH_FACTOR) * SHIP_SIZE


## The longest ship of any kind (dock units): what an anchorage leaves room to swing.
static func _longest_ship() -> float:
	var longest := 0.0
	for model: Dictionary in GameData.ship_models:
		longest = maxf(longest, _model_length(model))
	return longest


## A marina's layout in dock units, the port at (0, 0) and the sea along +x,
## for its berths' kinds (Docks.berth_kinds()): {radius (the circle: the
## jetty's middle), inner (the half-polygon's corners' distance), corners (the
## half-polygon's, from +y round the land side to -y), berths (one per kind:
## [where the middle of a ship moored there is, on the quay's edge; the way
## along the quay; the way in off it; the quay's length; its middle; its
## kind]), slip ([mouth middle, length, width] at a hub port, its berth along
## the slip's wall; or []), gap (the entrance's half-angle), mouth (where
## ships come in and leave, just outside), inside (just inside the entrance),
## length and width (the longest and widest ship that docks)}.
## Each side is as long as the longest ship its berth takes, plus room at each
## corner it shares with the next berth (none at the coast) for the ships
## there to clear each other: a ship's width at a right angle, less the more
## open the corner; the ship lies against its side's coast end.
func _marina_layout(kinds: String, hub: bool) -> Dictionary:
	var key := [kinds, hub]
	if _marina_layouts.has(key):
		return _marina_layouts[key]
	# The half-polygon's sides: [kind, the berths along it]; at a hub port, its
	# big berths share one side, the slip's mouth.
	var polygon := []
	for i in kinds.length():
		if hub and kinds[i] == "B" and not polygon.is_empty() and polygon[-1][0] == "slip":
			(polygon[-1][1] as Array).append(i)
		else:
			polygon.append(["slip" if hub and kinds[i] == "B" else kinds[i], [i]])
	var count := polygon.size()
	var spread := 1.0 / tan((PI - PI / count) / 2.0)  # A corner's room per width (see above).
	var sides := PackedFloat32Array()
	var length := 0.0
	var width := 0.0
	for j in count:
		var ship := _berth_ship("B" if polygon[j][0] == "slip" else polygon[j][0])
		length = maxf(length, ship.x)
		width = maxf(width, ship.y)
		if polygon[j][0] == "slip":
			sides.append(ship.y * SLIP_WIDTHS + 1.0)  # The slip's mouth: room for a ship moored each side and one between.
			continue
		var shared := (1.0 if j > 0 else 0.0) + (1.0 if j < count - 1 else 0.0)  # Corners shared with a neighbour.
		sides.append(ship.x + shared * (ship.y + BERTH_GAP) * spread + BERTH_ROOM)
	var inner := _inscribed_radius(sides)
	var radius := inner + QUAY_WIDTH
	var corners := PackedVector2Array([Vector2.from_angle(PI / 2.0) * inner])
	var angle := PI / 2.0
	for side in sides:
		angle += 2.0 * asin(minf(side / (2.0 * inner), 1.0))
		corners.append(Vector2.from_angle(angle) * inner)
	var berth_list := []
	berth_list.resize(kinds.length())
	var slip := []
	for j in count:
		var a := corners[j]
		var b := corners[j + 1]
		var along := (b - a).normalized()
		var middle := (a + b) / 2.0
		var inward := -middle.normalized()
		var berths: Array = polygon[j][1]
		if polygon[j][0] == "slip":
			# The slip runs inland from the side's middle, a berth along each wall.
			var slip_length := _berth_ship("B").x + SLIP_ROOM
			slip = [middle, slip_length, sides[j]]
			for k in berths.size():
				var wall_side := 1.0 if k == 0 else -1.0
				var wall := middle - inward * slip_length / 2.0 + along * wall_side * sides[j] / 2.0
				berth_list[berths[k]] = [wall, -inward, -along * wall_side, slip_length, wall, "B"]
			continue
		var ship := _berth_ship(polygon[j][0])
		# Against its coast end if it has one (the first and last sides), else
		# in the middle, clear of both corners.
		var from_a := sides[j] / 2.0
		if count > 1 and j == 0:
			from_a = BERTH_ROOM / 2.0 + ship.x / 2.0
		elif count > 1 and j == count - 1:
			from_a = sides[j] - BERTH_ROOM / 2.0 - ship.x / 2.0
		berth_list[berths[0]] = [a + along * from_a, along, inward, sides[j], middle, polygon[j][0]]
	var gap := asin(clampf(width * ENTRANCE_WIDTHS / 2.0 / radius, 0.05, 0.6))
	var layout := {radius = radius, inner = inner, corners = corners, berths = berth_list, slip = slip, gap = gap,
		mouth = Vector2(radius + length * 1.2, 0.0), inside = Vector2(radius * 0.45, 0.0), length = length, width = width}
	_marina_layouts[key] = layout
	return layout


## The longest and widest cargo ship (dock units) a berth of a kind takes (see
## Docks.berth_kinds()): the Small ports' ships, the Medium's, or the biggest.
static func _berth_ship(kind: String) -> Vector2:
	var band := "large" if kind == "B" else ("medium" if kind == "m" else "small")
	return Vector2(_band_ship_length(band), _widest_ship(band))


## The radius of the circle a run of chords (side lengths) spans exactly half
## of, round the land side.
static func _inscribed_radius(sides: PackedFloat32Array) -> float:
	var low := 0.0
	var high := 0.0
	for side in sides:
		low = maxf(low, side / 2.0)
		high += side
	for i in 50:
		var r := (low + high) / 2.0
		var spanned := 0.0
		for side in sides:
			spanned += 2.0 * asin(minf(side / (2.0 * r), 1.0))
		if spanned > PI:
			low = r
		else:
			high = r
	return high


## A port's marina as it is now (its berths, and whether it's a hub port).
func _port_layout(port_id: String) -> Dictionary:
	# Asked for very often (every port and docked ship, every frame): worked out
	# once a frame per port (a port's berths change only with its size and hubs).
	var frame := Engine.get_process_frames()
	if frame != _port_layouts_frame:
		_port_layouts_frame = frame
		_port_layouts.clear()
	if not _port_layouts.has(port_id):
		_port_layouts[port_id] = _marina_layout(GameState.docks.berth_kinds(port_id), GameState.docks.has_hub(port_id))
	return _port_layouts[port_id]


## A point of a port's marina (dock units) on screen.
func _dock_point(port_id: String, local: Vector2) -> Vector2:
	var angle := _port_sea_angle(port_id) + _port_turn(port_id)  # (Works out the flip too.)
	return port_screen_position(port_id) + Vector2(local.x, local.y * float(_dock_flips.get(port_id, 1.0))).rotated(angle) * dock_scale(port_id)


## How much the globe turns a port's marina on screen (see _turn_at()),
## worked out once per view.
func _port_turn(port_id: String) -> float:
	if not _port_turns.has(port_id):
		_port_turns[port_id] = _turn_at(GameData.port_position(port_id))
	return _port_turns[port_id]


## A dock-units facing on screen (mirrored with its port's layout).
func _dock_angle(port_id: String, facing: float) -> float:
	return _port_sea_angle(port_id) + _port_turn(port_id) + facing * float(_dock_flips.get(port_id, 1.0))


## How big a port's marina (and the ships moored and anchored there) is drawn:
## always just like the ships at sea, so a ship keeps its size as it docks.
func dock_scale(_port_id: String) -> float:
	return _ship_scale()


## True if a port's marina is big enough on screen to draw (instead of its dot).
func _marina_shown(port_id: String) -> bool:
	if not docks_shown():
		return false
	var frame := Engine.get_process_frames()
	if frame != _marinas_shown_frame:  # Asked for every ship there, every frame.
		_marinas_shown_frame = frame
		_marinas_shown.clear()
	if not _marinas_shown.has(port_id):
		_marinas_shown[port_id] = float(_port_layout(port_id).radius) * _ship_scale() >= _port_radius(port_id) + MARINA_OVER_DOT_PX
	return _marinas_shown[port_id]


## Every port's marina in view (see the section's description).
func _draw_marinas() -> void:
	var view := Rect2(Vector2.ZERO, size)
	var near := view.grow(MARINA_MAX_REACH * _ship_scale())
	for port: Dictionary in GameData.ports:
		var port_id: String = port.id
		var root := port_screen_position(port_id)
		if not near.has_point(root) or _port_locked(port_id) or not _marina_shown(port_id):
			continue  # (Cheapest first: most ports are well off screen.)
		var layout := _port_layout(port_id)
		var reach := (float(layout.radius) * 1.5 + float(layout.slip[1] if not layout.slip.is_empty() else 0.0)) * _ship_scale()  # (The quay's square corners.)
		if not view.grow(reach).has_point(root):
			continue
		_draw_marina(port_id, layout)


func _draw_marina(port_id: String, layout: Dictionary) -> void:
	var radius: float = layout.radius
	var inner: float = layout.inner
	var corners: PackedVector2Array = layout.corners
	var water := _color(&"ocean")
	var scale := _ship_scale()
	# The whole circle cleared to shallow water, then the land half's quay
	# (squared off inland, over all of the cleared circle there), the berths'
	# water and the slip dug out of it.
	var clear := radius + JETTY_WIDTH / 2.0
	_canvas.draw_colored_polygon(_marina_polygon(port_id, _arc(clear, -PI, PI).slice(0, -1)), water)
	var quay := PackedVector2Array([Vector2(0.0, clear), Vector2(-clear, clear), Vector2(-clear, -clear), Vector2(0.0, -clear)])
	_canvas.draw_colored_polygon(_marina_polygon(port_id, quay), QUAY_COLOR)
	if not layout.slip.is_empty():
		var slip: Array = layout.slip
		var mouth: Vector2 = slip[0]
		var slip_length: float = slip[1]
		var half: float = slip[2] / 2.0
		_canvas.draw_colored_polygon(_marina_polygon(port_id, _rect(mouth + Vector2(0.5, 0.0), mouth - Vector2(slip_length + QUAY_WIDTH, 0.0), half + QUAY_WIDTH)), QUAY_COLOR)
		_canvas.draw_colored_polygon(_marina_polygon(port_id, _rect(mouth + Vector2(0.5, 0.0), mouth - Vector2(slip_length, 0.0), half)), water)
		var wall := _marina_polygon(port_id, _rect(mouth, mouth - Vector2(slip_length, 0.0), half))
		wall.append(wall[0])
		_canvas.draw_polyline(wall, QUAY_EDGE, 1.0, true)
	var basin := PackedVector2Array(corners)
	basin.append_array(_arc(inner, -PI / 2.0, PI / 2.0).slice(1, -1))
	_canvas.draw_colored_polygon(_marina_polygon(port_id, basin), water)
	# The quay's edge along the berths, and the marina's edge on land.
	var edge := _marina_polygon(port_id, corners)
	_canvas.draw_polyline(edge, QUAY_EDGE, 1.0, true)
	_canvas.draw_polyline(_marina_polygon(port_id, quay), QUAY_EDGE, 1.0, true)
	# The jetty: round the sea half, each side of the entrance, lit at its ends.
	var gap: float = layout.gap
	for side: float in [-1.0, 1.0]:
		var arm := _arc(radius, gap * side, PI / 2.0 * side)
		var points := _marina_polygon(port_id, arm)
		_canvas.draw_polyline(points, QUAY_EDGE, JETTY_WIDTH * scale + 2.0, true)
		_canvas.draw_polyline(points, JETTY_COLOR, JETTY_WIDTH * scale, true)
		_canvas.draw_circle(points[0], maxf(JETTY_WIDTH * scale * 0.45, 1.2), ENTRANCE_LIGHTS[0 if side < 0.0 else 1])
	# Bollards along every berth's quay edge, once they're far enough apart to tell apart.
	if BOLLARD_STEP * scale < 4.0:
		return
	var bollard := maxf(BOLLARD_RADIUS * scale, 0.9)
	for berth: Array in layout.berths:
		for post in _bollards(berth):
			_canvas.draw_circle(_dock_point(port_id, post), bollard, BOLLARD_COLOR)


## Points round a circle (dock units) from one angle to another.
static func _arc(radius: float, from: float, to: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(ceili(absf(to - from) / TAU * MARINA_ARC_POINTS), 2)
	for i in steps + 1:
		points.append(Vector2.from_angle(lerpf(from, to, float(i) / steps)) * radius)
	return points


## A rectangle (dock units) along x from one point to another, half_width either side.
static func _rect(from: Vector2, to: Vector2, half_width: float) -> PackedVector2Array:
	var across := (to - from).normalized().orthogonal() * half_width
	return PackedVector2Array([from - across, to - across, to + across, from + across])


func _marina_polygon(port_id: String, local: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in local:
		points.append(_dock_point(port_id, p))
	return points


## A berth's bollards (dock units): every BOLLARD_STEP along its quay edge,
## BOLLARD_INSET back on the quay.
static func _bollards(berth: Array) -> PackedVector2Array:
	var middle: Vector2 = berth[4]
	var along: Vector2 = berth[1]
	var inward: Vector2 = berth[2]
	var half: float = float(berth[3]) / 2.0
	var posts := PackedVector2Array()
	var s := -half + BOLLARD_STEP * 0.5
	while s <= half - BOLLARD_STEP * 0.3:
		posts.append(middle + along * s - inward * BOLLARD_INSET)
		s += BOLLARD_STEP
	return posts


## Where a ship moored at a berth lies (dock units): [its middle, facing],
## alongside the quay, in the middle of the berth (or its end of a shared one).
func _berth_pose(berth: Array, ship: Ship) -> Array:
	var width := (_model_look(ship.model_id)[7] as Rect2).size.y
	var along: Vector2 = berth[1]
	return [_berth_spot(berth, ship) + (berth[2] as Vector2) * (width / 2.0 + BERTH_GAP), along.angle()]


## Where the middle of a ship moored at a berth is on the quay's edge (dock
## units): the berth's middle, or sharing a big berth with another smaller ship
## (Ship.berth_half), towards its end of it.
func _berth_spot(berth: Array, ship: Ship) -> Vector2:
	if ship.berth_half < 0:
		return berth[0]
	var shift := (_berth_ship("B").x - (_model_look(ship.model_id)[7] as Rect2).size.x) / 2.0
	return (berth[0] as Vector2) + (berth[1] as Vector2) * shift * (-1.0 if ship.berth_half == 0 else 1.0)


## A moored ship's ropes to the bollards on its quay: bow and stern lines out
## ahead and astern, and two springs crossing back along its side.
func _draw_mooring_ropes(ship: Ship) -> void:
	var port := ship.docked_at
	var layout := _port_layout(port)
	if ship.berth < 0 or ship.berth >= layout.berths.size():
		return
	var berth: Array = layout.berths[ship.berth]
	var moored := _berth_spot(berth, ship)
	var along: Vector2 = berth[1]
	var inward: Vector2 = berth[2]
	var quay: Vector2 = berth[4]
	var half_length: float = (_model_look(ship.model_id)[7] as Rect2).size.x / 2.0
	var half_berth := float(berth[3]) / 2.0
	var offset := (moored - quay).dot(along)  # Where the ship's middle is along its quay.
	var width := maxf(0.35 * dock_scale(port), 1.0)
	# [where on the hull (share of half its length), where along the quay from the ship's middle].
	for rope: Array in [[0.8, 0.8 * half_length + 2.5], [-0.8, -0.8 * half_length - 2.5], [0.35, -0.1 * half_length], [-0.35, 0.1 * half_length]]:
		var hull := moored + inward * BERTH_GAP + along * float(rope[0]) * half_length
		# To a bollard that's really on its quay.
		var mark := clampf(roundf((offset + float(rope[1]) + half_berth - BOLLARD_STEP * 0.5) / BOLLARD_STEP), 0.0,
			floorf((2.0 * half_berth - BOLLARD_STEP * 0.8) / BOLLARD_STEP))
		var post := quay + along * (-half_berth + BOLLARD_STEP * (0.5 + mark)) - inward * BOLLARD_INSET
		_canvas.draw_line(_dock_point(port, hull), _dock_point(port, post), ROPE_COLOR, width, true)


## Where a docked ship is on screen and which way it faces: moored at its
## berth, coming in and alongside, pulling out, lying at the anchorage (or a
## recovery boat in its hub's slip), or gliding out to it.
func _docked_pose(ship: Ship) -> Array:
	# Asked for twice a frame (where, and which way): worked out once.
	var frame := Engine.get_process_frames()
	if frame != _poses_frame:
		_poses_frame = frame
		_poses.clear()
	if _poses.has(ship):
		return _poses[ship]
	var pose := _docked_screen_pose(ship)
	_poses[ship] = pose
	_last_spot[ship] = [ship.docked_at, _screen_unit(pose[0]), pose[1]]  # Where it sets off from when it sails (on the unit sphere), and its heading.
	return pose


func _docked_screen_pose(ship: Ship) -> Array:
	var port := ship.docked_at
	var layout := _port_layout(port)
	_update_spots()
	if ship.berth >= 0 and ship.berth < layout.berths.size():
		var berth: Array = layout.berths[ship.berth]
		var moored := _berth_pose(berth, ship)
		var at := [_dock_point(port, moored[0]), _dock_angle(port, float(moored[1]))]
		var width := (_model_look(ship.model_id)[7] as Rect2).size.y
		var off := [_dock_point(port, moored[0] + (berth[2] as Vector2) * width * BERTH_OFF_WIDTHS), at[1]]
		var settings := Docks.settings()
		var slide_s := float(settings.get("slide_s", 1.5))
		var length := (_model_look(ship.model_id)[7] as Rect2).size.x * dock_scale(port)
		match ship.berth_phase:
			Ship.BERTH_IN:
				# Sailing in at its own speed, round through the entrance on its
				# right-hand side (turning in smoothly where it already is),
				# slowing only over its last length to lie off the berth, then
				# sliding sideways onto it on its thrusters (see
				# GameState._berth_seconds()).
				var total := ship.berth_duration if ship.berth_duration > 0.0 else float(settings.get("in_s", 6.0))
				var sail := maxf(total - slide_s, 0.01)
				if ship.berth_time < sail:
					var start := _lying_pose(ship, GameState.play_time - ship.berth_time)
					# Through the mouth heading in, then one long curve round to lie off
					# its berth (room for the biggest ships to turn). Not by the mouth
					# when it's there already (coming in from sea), as near as makes no
					# odds; from an anchor right by it, through just inside the entrance.
					var weighing := (start[0] as Vector2).distance_to(_rest_pose(ship)[0]) < 1.0  # (Lying at anchor, facing the wind.)
					var poses := [start]
					var mouth := _keep_right(port, _entrance_pose(port, false, true))
					var mouth_room := ((layout.mouth as Vector2) - (layout.inside as Vector2)).length() * dock_scale(port) * 0.5
					if (start[0] as Vector2).distance_to(mouth[0]) > maxf(length, mouth_room):
						poses.append(mouth)
					elif weighing:
						poses.append(_keep_right(port, _entrance_pose(port, true, true)))
					poses.append(off)
					var shaped := _loosen(poses, weighing, false)
					var path := _pose_path(shaped)
					return _follow(poses, shaped, path, _timed_share(path, _path_times(path, _sea_speed_px(ship), length, length, false, true), ship.berth_time / sail), ship.berth_time / _anchor_turn(sail) if weighing else 1.0)
				return _slide(off, at, (ship.berth_time - sail) / slide_s)
			Ship.BERTH_OUT:
				# Sliding off the berth; if it lies bow away from the way out (in
				# a hub's slip), backing out stern first to the middle of the
				# marina and turning there on its thrusters; then getting going,
				# out at its own speed through the entrance on its right-hand side
				# to sea (or to its spot at the anchorage, slowing to anchor).
				if ship.berth_time < slide_s:
					return _slide(at, off, ship.berth_time / slide_s)
				var total := ship.berth_duration if ship.berth_duration > 0.0 else float(settings.get("out_s", 5.0))
				var t := ship.berth_time - slide_s
				var plan := _unberth_plan(ship)
				var start := off
				if plan.reverse:
					var back := [_dock_point(port, plan.back), at[1]]
					if t < plan.reverse_s:
						var share := _sailed_share(t / plan.reverse_s, float(plan.reverse_units), float(plan.ease), true, true)
						return [(off[0] as Vector2).lerp(back[0], share), at[1]]
					t -= plan.reverse_s
					var turned := _dock_angle(port, float(plan.out_angle))
					if t < UNBERTH_TURN_S:
						return [back[0], lerp_angle(float(at[1]), turned, smoothstep(0.0, 1.0, t / UNBERTH_TURN_S))]
					t -= UNBERTH_TURN_S
					start = [back[0], turned]
				var anchoring := ship.depart_to.is_empty()
				var poses := [start, _keep_right(port, _entrance_pose(port, false, false))]  # (One long curve out through the mouth.)
				if anchoring:
					var rest := _rest_pose(ship)
					var mouth_room := ((layout.mouth as Vector2) - (layout.inside as Vector2)).length() * dock_scale(port) * 0.5
					if (rest[0] as Vector2).distance_to(poses[-1][0]) < maxf(length, mouth_room):
						poses.pop_back()  # (Its spot's right by the mouth: straight there.)
					poses.append(rest)
				var shaped := _loosen(poses, false, anchoring)
				var path := _pose_path(shaped)
				var before := slide_s + (float(plan.reverse_s) + UNBERTH_TURN_S if plan.reverse else 0.0)
				var u := t / maxf(total - before, 0.01)
				var sail_s := maxf(total - before, 0.01)
				var turn := _anchor_turn(sail_s)
				return _follow(poses, shaped, path, _timed_share(path, _path_times(path, _sea_speed_px(ship), length, length, true, anchoring), u), 1.0, (t - sail_s + turn) / turn if anchoring else 0.0)
		return at
	return _lying_pose(ship, GameState.play_time)


## A pose (screen) moved over to its right-hand side of its port's harbour
## entrance, as ships keep to starboard: in and out pass each other.
func _keep_right(port_id: String, pose: Array) -> Array:
	var side := float(_port_layout(port_id).width) * KEEP_RIGHT_WIDTHS * dock_scale(port_id)
	return [(pose[0] as Vector2) + Vector2.from_angle(float(pose[1]) + PI / 2.0) * side, pose[1]]


## How a moored ship gets clear of its berth to head out (dock units): if it
## lies bow away from the way out (in a hub's slip), it backs out stern first
## from off its berth until it's abreast the middle of the marina (back), at
## UNBERTH_REVERSE_SPEED of its speed, taking reverse_s (getting going and
## stopping over ease), then turns there to out_angle. {reverse, back,
## out_angle, reverse_units, reverse_s, ease}.
func _unberth_plan(ship: Ship) -> Dictionary:
	var plan := {reverse = false, back = Vector2.ZERO, out_angle = 0.0, reverse_units = 0.0, reverse_s = 0.0, ease = 0.0}
	var layout := _port_layout(ship.docked_at)
	if ship.berth < 0 or ship.berth >= layout.berths.size():
		return plan
	var berth: Array = layout.berths[ship.berth]
	var rect: Rect2 = _model_look(ship.model_id)[7]
	var moored := _berth_pose(berth, ship)
	var off: Vector2 = (moored[0] as Vector2) + (berth[2] as Vector2) * rect.size.y * BERTH_OFF_WIDTHS
	var facing := Vector2.from_angle(float(moored[1]))
	var way_out: Vector2 = (layout.inside as Vector2) - off
	if way_out.length() < 0.001 or facing.dot(way_out.normalized()) > -0.2:
		return plan  # Pointing the way out already, near enough: it turns as it goes.
	var units := maxf(facing.dot(off), rect.size.x * 0.5)  # Back till it's abreast the marina's middle.
	plan.reverse = true
	plan.back = off - facing * units
	plan.out_angle = ((layout.inside as Vector2) - plan.back).angle()
	plan.reverse_units = units
	plan.ease = minf(rect.size.x * 0.5, units / 3.0)
	var speed := maxf(ship.speed(), MIN_HARBOUR_SPEED) * SHIP_WORLD_ZOOM / 60.0 * UNBERTH_REVERSE_SPEED
	plan.reverse_s = (units + 2.0 * plan.ease) / speed
	return plan


## Sliding sideways (on its thrusters) from one screen pose to another, eased.
static func _slide(from: Array, to: Array, t: float) -> Array:
	t = smoothstep(0.0, 1.0, t)
	return [(from[0] as Vector2).lerp(to[0], t), lerp_angle(float(from[1]), float(to[1]), t)]


## The entrance of a port's marina as a screen pose: just outside it (or just
## inside), facing in (or out); `out` pushes the outside point further out
## (times the mouth's distance).
func _entrance_pose(port_id: String, inside: bool, facing_in: bool, out := 1.0) -> Array:
	var layout := _port_layout(port_id)
	var local: Vector2 = layout.inside if inside else (layout.mouth as Vector2) * out
	return [_dock_point(port_id, local), _dock_angle(port_id, PI if facing_in else 0.0)]


## Where a ship lying in port is at a play time (screen pose): sailing on in
## from the harbour mouth, the way it came, at its own speed after it got
## there, slowing over its last length to its spot, then at its spot.
func _lying_pose(ship: Ship, at_time: float) -> Array:
	var rest := _rest_pose(ship)
	var seen: Array = _dock_seen.get(ship, [])
	var since: float = float(seen[1]) if not seen.is_empty() else -INF
	if since == -INF or seen.size() > 2 and at_time >= float(seen[2]) or ship.berth >= 0 and ship.berth_phase != Ship.BERTH_IN:
		return rest
	var poses := [_keep_right(ship.docked_at, _entrance_pose(ship.docked_at, false, true)), rest]
	var shaped := _loosen(poses, false, true)  # (Coming round to face the wind as it anchors.)
	var path := _pose_path(shaped)
	var length := (_model_look(ship.model_id)[7] as Rect2).size.x * dock_scale(ship.docked_at)
	var distance := _path_length(path)
	var ease := minf(length, distance / 3.0)
	var takes := (distance + ease) / maxf(_sea_speed_px(ship), 0.001)
	# Coming round to face the wind over the end of its way, and on at its
	# spot if that's too short for it (see _anchor_turn()).
	var turn := maxf(ANCHOR_TURN_SHARE * takes, ANCHOR_TURN_MIN_S)
	var turn_from := maxf(takes - ANCHOR_TURN_SHARE * takes, 0.0)
	if seen.size() < 3:
		seen.append(since + maxf(takes, turn_from + turn))  # When it's settled (kept, so the glide's end is cheap to check).
	var elapsed := at_time - since
	if elapsed >= maxf(takes, turn_from + turn):
		return rest
	if distance < length * 2.0:
		# Its spot's just by the mouth: too little way to follow round, so it
		# drifts there coming steadily round from heading in to face the wind.
		var drift := _along_path(path, _sailed_share(clampf(elapsed / takes, 0.0, 1.0), distance, length, false, true))
		var settled := elapsed / maxf(takes, turn_from + turn)
		return [drift[0], lerp_angle(float(poses[0][1]), float(rest[1]), smoothstep(0.0, 1.0, settled))]
	return _follow(poses, shaped, path, _sailed_share(clampf(elapsed / takes, 0.0, 1.0), distance, length, false, true), 1.0, (elapsed - turn_from) / turn)


## A ship's speed at sea on screen (px per s of play), as it's drawn sailing.
func _sea_speed_px(ship: Ship) -> float:
	return maxf(ship.speed(), MIN_HARBOUR_SPEED) * SHIP_WORLD_ZOOM / 60.0 * _ship_scale()


static func _path_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	return total


## How far along (a share) a ship sailing a path of a length at a steady speed
## is, a share t of the way through the time it takes: getting going over the
## first ease of it from a stop (start), and slowing to a stop over the last
## ease (stop), at the same rate a ship slows to anchor; steady in between.
static func _sailed_share(t: float, length: float, ease: float, start: bool, stop: bool) -> float:
	if length <= 0.0:
		return 1.0
	ease = minf(ease, length / 3.0)
	var speeding := ease if start else 0.0
	var slowing := ease if stop else 0.0
	var cruise := length - speeding - slowing
	# In units of the time a length takes at speed: speeding up or slowing down over a distance takes twice as long.
	var time := clampf(t, 0.0, 1.0) * (2.0 * speeding + cruise + 2.0 * slowing)
	var gone := 0.0
	if time < 2.0 * speeding:
		gone = time * time / (4.0 * speeding)
	elif time < 2.0 * speeding + cruise:
		gone = speeding + time - 2.0 * speeding
	else:
		var late := time - 2.0 * speeding - cruise
		gone = speeding + cruise + late - late * late / (4.0 * slowing)
	return clampf(gone / length, 0.0, 1.0)


## How long (s of play) a ship takes to sail into its berth (coming_in) from
## where it lies, or out of it to sea or its spot at the anchorage, at its
## own speed, slowing for tight bends (see _path_times()), measured on the
## ground (so off screen too), along the curves the map draws it on:
## GameState.berth_route.
func berth_route_seconds(ship: Ship, coming_in: bool) -> float:
	# Its spot at the anchorage, as things are now (it may only just have
	# started pulling out to anchor).
	if _spots_frame >= 0:
		_spots_dirty = true
		_spots_frame = Engine.get_process_frames() - 1
	_update_spots()
	var port := ship.docked_at
	if port.is_empty() or ship.berth < 0:
		return 0.0
	var layout := _port_layout(port)
	if ship.berth >= layout.berths.size():
		return 0.0
	var berth: Array = layout.berths[ship.berth]
	var look_rect: Rect2 = _model_look(ship.model_id)[7]
	var moored := _berth_pose(berth, ship)
	var off := [(moored[0] as Vector2) + (berth[2] as Vector2) * look_rect.size.y * BERTH_OFF_WIDTHS, float(moored[1])]
	var mouth_in := [layout.mouth, PI]
	var mouth_room := ((layout.mouth as Vector2) - (layout.inside as Vector2)).length() * 0.5
	var length := look_rect.size.x
	var speed := maxf(ship.speed(), MIN_HARBOUR_SPEED) * SHIP_WORLD_ZOOM / 60.0
	# The same curves the map draws it along (_docked_screen_pose()), in dock units.
	if coming_in:
		var seen: Array = _dock_seen.get(ship, [])
		var gliding := not seen.is_empty() and float(seen[1]) > -INF and (seen.size() < 3 or GameState.play_time < float(seen[2]))
		var anchor := _anchor_local(ship)
		var weighing := not gliding and anchor.x == anchor.x  # (NAN when it has no spot.)
		var poses := [[anchor, 0.0] if weighing else mouth_in]
		if weighing and anchor.distance_to(layout.mouth) > maxf(length, mouth_room):
			poses.append(mouth_in)
		elif weighing:
			poses.append([layout.inside, PI])
		poses.append(off)
		var path := _pose_path(_loosen(poses, weighing, false))
		return _path_times(path, speed, length, length, false, true)[-1]
	var backing := 0.0  # Backing out and turning round first (s; see _unberth_plan()).
	var plan := _unberth_plan(ship)
	var start: Array = off
	if plan.reverse:
		backing = float(plan.reverse_s) + UNBERTH_TURN_S
		start = [plan.back, float(plan.out_angle)]
	var poses := [start, [layout.mouth, 0.0]]
	var anchoring := ship.depart_to.is_empty()
	var anchor := _anchor_local(ship) if anchoring else Vector2(NAN, NAN)
	if anchor.x == anchor.x:
		if anchor.distance_to(layout.mouth) < maxf(length, mouth_room):
			poses.pop_back()
		poses.append([anchor, 0.0])
	var path := _pose_path(_loosen(poses, false, anchoring and anchor.x == anchor.x))
	return backing + _path_times(path, speed, length, length, true, anchoring)[-1]


## A ship's anchor at its port's anchorage in its marina's dock units, or NAN
## if it has no spot there (yet).
func _anchor_local(ship: Ship) -> Vector2:
	if not _spot_slots.has(ship):
		return Vector2(NAN, NAN)
	var port := ship.docked_at
	var spots := _anchor_spots(port, _anchor_pool(ship))
	var slot := int(_spot_slots[ship])
	if slot >= spots.size():
		return Vector2(NAN, NAN)
	var info := GameData.get_port(port)
	var lat := float(info.get("lat", 0.0))
	# On the ground near the port: east and south (as the map shows it, north up), in dock units.
	var ground := Vector2((spots[slot].x - float(info.get("lon", 0.0))) * cos(deg_to_rad(lat)), -(spots[slot].y - lat)) * SHIP_WORLD_ZOOM
	var local := ground.rotated(-_port_sea_angle(port))
	local.y *= float(_dock_flips.get(port, 1.0))
	return local


## A lying ship's own spot (screen pose): its anchor at the anchorage, the
## ship swung round it to face into the wind, its bow at the anchor (and in a
## storm, swinging and pitching about it).
func _rest_pose(ship: Ship) -> Array:
	var port := ship.docked_at
	var key: Array = _spot_keys[ship] if _spot_keys.has(ship) else [port, _anchor_pool(ship)]
	var slot := int(_spot_slots.get(ship, 0))
	var half: float = (_model_look(ship.model_id)[7] as Rect2).size.x / 2.0
	var anchor := _anchor_screen_cached(ship, port, str(key[1]), slot)
	var facing := _upwind_angle(port)
	var storm := _storm_strength_at_port(port)
	if storm > 0.0:
		var t := GameState.play_time
		facing += (sin(t * 1.7 + ship.id * 1.3) * 0.7 + sin(t * 3.3 + ship.id * 0.7) * 0.3) * STORM_SWING * storm
	return [anchor - Vector2.from_angle(facing) * half * _ship_scale(), facing]


## A port's slot-th anchor on screen, in one of its two anchorages (see
## _anchor_spots()), or if there are too few, one further out to sea past the
## mouth.
func _anchor_screen(port_id: String, pool: String, slot: int) -> Vector2:
	var spots := _anchor_spots(port_id, pool)
	if slot < spots.size():
		return world_to_screen(Geo.project(spots[slot]))
	var layout := _port_layout(port_id)
	var spacing := _anchor_length(pool) * 1.1
	var extra := slot - spots.size()
	return _dock_point(port_id, Vector2(float(layout.radius) + spacing * (2 + extra / 3), spacing * (extra % 3 - 1)))


## A ship's anchor on screen (see _anchor_screen()): its point on the globe is
## kept until its spot (or its port's marina) changes, so only the turn of the
## view is worked out each frame.
func _anchor_screen_cached(ship: Ship, port_id: String, pool: String, slot: int) -> Vector2:
	var radius: float = _port_layout(port_id).radius
	var cached: Array = _anchor_units.get(ship, [])
	if cached.is_empty() or cached[0] != port_id or cached[1] != pool or cached[2] != slot or cached[3] != radius:
		var spots := _anchor_spots(port_id, pool)
		if slot >= spots.size():
			_anchor_units.erase(ship)
			return _anchor_screen(port_id, pool, slot)  # (Past the anchorage's points: placed off the mouth, not kept.)
		cached = [port_id, pool, slot, radius, _unit(Geo.project(spots[slot]))]
		_anchor_units[ship] = cached
	return _unit_to_screen(cached[4])


## Which of a port's anchorages (data/anchorages.json) a ship lies in: "small",
## closer in and denser, for ships up to its small_length; "all" (room for the
## longest ship) for the rest.
func _anchor_pool(ship: Ship) -> String:
	if not _anchor_pools.has(ship.model_id):
		_load_anchorages()
		_anchor_pools[ship.model_id] = "small" if (_model_look(ship.model_id)[7] as Rect2).size.x <= _anchor_length("small") else "all"
	return _anchor_pools[ship.model_id]


## The longest ship an anchorage has room to swing (dock units).
func _anchor_length(pool: String) -> float:
	return float(_anchorages.get("small_length", 9.0)) if pool == "small" else _longest_ship()


func _load_anchorages() -> void:
	if _anchorages.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(ANCHORAGES_PATH)) if FileAccess.file_exists(ANCHORAGES_PATH) else null
		_anchorages = data if data is Dictionary else {ports = {}}


## A port's anchor points (lon, lat) in an anchorage ("all" or "small"),
## nearest the sea first, leaving out those whose ships could swing into its
## marina as it is now.
func _anchor_spots(port_id: String, pool: String) -> PackedVector2Array:
	var layout := _port_layout(port_id)
	var key := port_id + pool
	var cached: Array = _spot_cache.get(key, [])
	if not cached.is_empty() and float(cached[0]) == float(layout.radius):
		return cached[1]
	_load_anchorages()
	var port := GameData.get_port(port_id)
	var at := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	# A dock unit is 1 / SHIP_WORLD_ZOOM degrees of the globe: 60 / SHIP_WORLD_ZOOM nm.
	var clear_nm := (float(layout.radius) + JETTY_WIDTH + _anchor_length(pool)) * 60.0 / SHIP_WORLD_ZOOM
	var spots := PackedVector2Array()
	for spot: Array in (_anchorages.get("ports", {}) as Dictionary).get(port_id, {}).get(pool, []):
		var point := Vector2(float(spot[0]), float(spot[1]))
		if Geo.distance_nm(at, point) >= clear_nm:
			spots.append(point)
	_spot_cache[key] = [layout.radius, spots]
	return spots


## The way into the wind at a port, on screen (ships at anchor face it).
func _upwind_angle(port_id: String) -> float:
	var frame := Engine.get_process_frames()
	if frame != _upwind_frame:
		_upwind_frame = frame
		_upwind.clear()
		_port_storms.clear()
	if not _upwind.has(port_id):
		var port := GameData.get_port(port_id)
		var at := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
		var wind := Wind.at(at, GameState.play_time, GameState.weather.storms)
		_upwind[port_id] = _heading_angle(-wind if wind.length() > 0.001 else Vector2.LEFT, GameData.port_position(port_id))
	return _upwind[port_id]


## The strongest storm's strength at a port (0..1).
func _storm_strength_at_port(port_id: String) -> float:
	if GameState.weather.storms.is_empty():
		return 0.0
	_upwind_angle(port_id)  # (Starts this frame's cache, which keeps this too.)
	if not _port_storms.has(port_id):
		var port := GameData.get_port(port_id)
		_port_storms[port_id] = float(GameState.weather.strongest_at(Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))))[1])
	return _port_storms[port_id]


## A smooth path through screen poses ([point, facing]): a curve from each to
## the next, leaving and arriving along their facings (handle: how hard, a
## share of the way), as points.
static func _pose_path(poses: Array, handle := 0.4) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(1, poses.size()):
		var a: Vector2 = poses[i - 1][0]
		var b: Vector2 = poses[i][0]
		var reach := a.distance_to(b) * handle
		var curve := [a, a + Vector2.from_angle(float(poses[i - 1][1])) * reach, b - Vector2.from_angle(float(poses[i][1])) * reach, b]
		for k in range(0 if i == 1 else 1, POSE_PATH_STEPS + 1):
			points.append(_bezier(curve, float(k) / POSE_PATH_STEPS))
	return points


## The point a share u (0..1) of the way along a path, and which way it heads
## there: [point, angle]. The heading turns smoothly through the path's
## corners (from halfway between one piece's way and the last's to halfway
## between it and the next's), so a ship rounding a curve never snaps round;
## start_angle and end_angle, if given, are the headings it starts and ends on.
static func _along_path(points: PackedVector2Array, u: float, start_angle := NAN, end_angle := NAN) -> Array:
	if points.size() < 2:
		return [points[0] if not points.is_empty() else Vector2.ZERO, 0.0]
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var goal := total * clampf(u, 0.0, 1.0)
	for i in range(1, points.size()):
		var step := points[i - 1].distance_to(points[i])
		if goal <= step or i == points.size() - 1:
			var t := clampf(goal / step, 0.0, 1.0) if step > 0.0 else 1.0
			var here := _piece_angle(points, i)
			var angle := here
			if t < 0.5:
				var before := _piece_angle(points, i - 1) if i > 1 else (start_angle if not is_nan(start_angle) else here)
				angle = lerp_angle(before if i == 1 else lerp_angle(before, here, 0.5), here, t * 2.0)
			else:
				var after := _piece_angle(points, i + 1) if i < points.size() - 1 else (end_angle if not is_nan(end_angle) else here)
				angle = lerp_angle(here, after if i == points.size() - 1 else lerp_angle(here, after, 0.5), t * 2.0 - 1.0)
			return [points[i - 1].lerp(points[i], t), angle]
		goal -= step
	return [points[0], _piece_angle(points, 1)]


## How long (cumulative, from the start, at each point) a ship takes along a
## path: `speed` (path units a second) on the straight, slower round any bend
## tighter than HARBOUR_TURN_LENGTHS of its length (so it never spins round),
## and getting going from a standstill over its first `ease` (start) or
## slowing to one over its last (stop), at a steady rate either way.
static func _path_times(points: PackedVector2Array, speed: float, ship_length: float, ease: float, start: bool, stop: bool) -> PackedFloat32Array:
	var times := PackedFloat32Array([0.0])
	var n := points.size()
	if n < 2:
		return times
	var lengths := PackedFloat32Array()
	var total := 0.0
	for i in range(1, n):
		var step := points[i - 1].distance_to(points[i])
		lengths.append(step)
		total += step
	ease = minf(ease, total / 3.0)
	var min_radius := maxf(ship_length * HARBOUR_TURN_LENGTHS, 0.0001)
	var gone := 0.0
	for i in range(1, n):
		var step: float = lengths[i - 1]
		var middle := gone + step / 2.0
		var limit := speed
		# Round a bend (the sharper of this piece's two corners): no faster
		# than takes it round min_radius.
		for corner: int in [i - 1, i]:
			if corner >= 1 and corner < n - 1:
				var bend := absf(angle_difference(_piece_angle(points, corner), _piece_angle(points, corner + 1)))
				var span := (lengths[corner - 1] + lengths[corner]) / 2.0
				if bend > 0.0001:
					limit = minf(limit, speed * clampf(span / bend / min_radius, 0.0, 1.0))
		if start and ease > 0.0:
			limit = minf(limit, speed * sqrt(clampf(middle / ease, 0.0, 1.0)))
		if stop and ease > 0.0:
			limit = minf(limit, speed * sqrt(clampf((total - middle) / ease, 0.0, 1.0)))
		times.append(times[-1] + step / maxf(limit, speed * HARBOUR_CRAWL))
		gone += step
	return times


## The share of a path's length a ship has gone (see _path_times()) a share t
## of the way through the time it takes.
static func _timed_share(points: PackedVector2Array, times: PackedFloat32Array, t: float) -> float:
	var n := mini(points.size(), times.size())
	if n < 2 or times[n - 1] <= 0.0:
		return clampf(t, 0.0, 1.0)
	var goal := clampf(t, 0.0, 1.0) * times[n - 1]
	var total := 0.0
	for i in range(1, n):
		total += points[i - 1].distance_to(points[i])
	var gone := 0.0
	for i in range(1, n):
		var step := points[i - 1].distance_to(points[i])
		if goal <= times[i] or i == n - 1:
			var piece := times[i] - times[i - 1]
			gone += step * (clampf((goal - times[i - 1]) / piece, 0.0, 1.0) if piece > 0.0 else 1.0)
			break
		gone += step
	return gone / total if total > 0.0 else 1.0


## Poses for _pose_path() with a loose first (or last) one, a ship at anchor
## facing the wind, set to head straight for the next (from the last), so it
## doesn't bend the path (see _follow()).
static func _loosen(poses: Array, loose_start: bool, loose_end: bool) -> Array:
	var shaped := poses.duplicate()
	if loose_start and poses.size() > 1:
		shaped[0] = [poses[0][0], ((poses[1][0] as Vector2) - (poses[0][0] as Vector2)).angle()]
	if loose_end and poses.size() > 1:
		shaped[-1] = [poses[-1][0], ((poses[-1][0] as Vector2) - (poses[-2][0] as Vector2)).angle()]
	return shaped


## A ship a share of the way (by distance) along a path through poses
## (shaped by _loosen()): [point, heading]. Weighing anchor from a loose first
## pose, it comes round from its own facing as `weighed` goes 0 to 1; dropping
## anchor at a loose last one, round to its facing as `anchoring` does (see
## _anchor_turn()).
static func _follow(poses: Array, shaped: Array, path: PackedVector2Array, share: float, weighed := 1.0, anchoring := 0.0) -> Array:
	var at := _along_path(path, share, float(shaped[0][1]), float(shaped[-1][1]))
	# Each turn goes the way it set out to (from its facing to the way it heads
	# off, or from the way it comes in to its facing), even when that's most of
	# the way round: so it never swaps sides halfway.
	if weighed < 1.0:
		at[1] = _turn_toward(float(poses[0][1]), float(at[1]), smoothstep(0.0, 1.0, weighed), angle_difference(float(poses[0][1]), float(shaped[0][1])))
	if anchoring > 0.0:
		at[1] = _turn_toward(float(at[1]), float(poses[-1][1]), smoothstep(0.0, 1.0, anchoring), angle_difference(float(shaped[-1][1]), float(poses[-1][1])))
	return at


## An angle a share w of the way from one to another, turning the way nearest
## `hint` (a signed turn from `from`): round the long way if that's the side
## the turn started on.
static func _turn_toward(from: float, to: float, w: float, hint: float) -> float:
	var turn := angle_difference(from, to)
	if absf(turn - hint) > PI:
		turn += TAU if turn < hint else -TAU
	return from + turn * w


## How long (s) a ship takes to come round from facing the wind as it weighs
## anchor, or round to face it as it anchors, on a way that takes `way_s`:
## ANCHOR_TURN_SHARE of it, but at least ANCHOR_TURN_MIN_S (so it never swings
## round on a short way), and no more than all of it.
static func _anchor_turn(way_s: float) -> float:
	return minf(maxf(ANCHOR_TURN_SHARE * way_s, ANCHOR_TURN_MIN_S), maxf(way_s, 0.001))


## Which way a path's piece (from point i - 1 to i) heads; for one too short to
## say, the nearest piece that isn't (before it first).
static func _piece_angle(points: PackedVector2Array, i: int) -> float:
	for k in points.size():
		for j: int in [i - k, i + k]:
			if j >= 1 and j < points.size():
				var way := points[j] - points[j - 1]
				if way.length_squared() > 0.000001:
					return way.angle()
	return 0.0


## Once a frame: every docked ship's spot in its port. A ship lying at the
## anchorage (or about to: coming in, or pulling out to anchor) keeps the anchor
## it was given, the first free one, until it leaves. And when it arrived in
## port, for its glide in from the mouth.
func _update_spots() -> void:
	var frame := Engine.get_process_frames()
	if frame == _spots_frame or not _spots_dirty and _spots_frame >= 0:
		return
	var first := _spots_frame < 0
	_spots_frame = frame
	_spots_dirty = false
	var alive := {}
	for ship in GameState.ships:
		if not ship.is_docked():
			continue
		alive[ship] = true
		_harbour_reach_cache.erase(ship)  # (Its next leg's curves are worked out when it sails.)
		var port := ship.docked_at
		var seen: Array = _dock_seen.get(ship, [])
		if seen.is_empty() or seen[0] != port:
			_dock_seen[ship] = [port, -INF if first else GameState.play_time]  # Already there when the map opened: no glide.
		var lies := ship.berth < 0 or ship.berth_phase == Ship.BERTH_IN \
			or ship.berth_phase == Ship.BERTH_OUT and ship.depart_to.is_empty()
		if lies and not _spot_slots.has(ship):
			var key := [port, _anchor_pool(ship)]
			var taken: Dictionary = _spot_tables.get_or_add(key, {})
			var slot := 0
			while taken.has(slot):
				slot += 1
			taken[slot] = ship
			_spot_slots[ship] = slot
			_spot_keys[ship] = key
		elif not lies and _spot_slots.has(ship):
			_free_spot(ship)
		elif _spot_slots.has(ship) and _spot_keys[ship][0] != port:
			_free_spot(ship)
	for ship: Ship in _spot_slots.keys():
		if not alive.has(ship):
			_free_spot(ship)
	for ship: Ship in _dock_seen.keys():
		if not alive.has(ship):
			_dock_seen.erase(ship)


func _free_spot(ship: Ship) -> void:
	var taken: Dictionary = _spot_tables.get(_spot_keys.get(ship, []), {})
	taken.erase(_spot_slots[ship])
	_spot_slots.erase(ship)
	_spot_keys.erase(ship)
	_anchor_units.erase(ship)


## A ship sailing near a port it's making for (or leaving) sails a curve
## between its lane and the harbour: leaving its lane along the lane's heading
## and coming round to the harbour mouth heading in (or from where it lay
## there, its spot at the anchorage or the mouth, round onto its lane). The
## curve takes the last (or first) HARBOUR_REACH times the harbour's distance
## from the port of its lane (more if the curve is longer, so it's never
## faster than at sea; the two ends share a short leg), gone along evenly.
## [screen point, angle], or [] when it isn't near a port.
func _harbour_pose(ship: Ship) -> Array:
	if not docks_shown() or ship.is_docked():
		return []
	var lane = GameData.lane(ship.from_port, ship.to_port)
	if lane == null:
		return []
	var length: float = lane.length()
	var reaches := _harbour_reaches(ship, lane, length)
	for i in 2:
		var arriving := i == 0
		var port := ship.to_port if arriving else ship.from_port
		var reach: float = reaches[i]
		var gone := length - ship.traveled_nm if arriving else ship.traveled_nm
		if port.is_empty() or reach <= 0.0 or gone >= reach:
			continue
		var curve := _harbour_curve(ship, lane, length, arriving, reach)
		if curve.is_empty():
			continue
		return _follow(curve[1], curve[2], curve[0], 1.0 - gone / reach if arriving else gone / reach, 1.0 if arriving else gone / reach / ANCHOR_TURN_SHARE)
	return []


## Where a ship near a port lay, or will come in: the harbour mouth heading in
## (arriving), or its spot at the anchorage or the mouth heading out (leaving).
func _harbour_end(ship: Ship, port: String, arriving: bool) -> Array:
	if arriving:
		return _keep_right(port, _entrance_pose(port, false, true))
	var last: Array = _last_spot.get(ship, [])
	if not last.is_empty() and last[0] == port and last.size() > 2:
		var spot := _unit_to_screen(last[1])
		if not _is_hidden(spot):
			return [spot, float(last[2])]
	return _keep_right(port, _entrance_pose(port, false, false))


## The curve between a ship's lane, `reach` nm from a port, and that port's
## harbour (see _harbour_pose()), from the lane in arriving and from the
## harbour out leaving (from where it lay, loose: it comes round from there as
## it gets going, see _follow()): [screen points, poses, shaped poses], or []
## if either end is round the far side.
func _harbour_curve(ship: Ship, lane, length: float, arriving: bool, reach: float) -> Array:
	var port := ship.to_port if arriving else ship.from_port
	if _is_hidden(port_screen_position(port)):
		return []
	var harbour := _harbour_end(ship, port, arriving)
	var mile := length - reach if arriving else reach
	var sample: Array = lane.sample(clampf(mile, 0.0, length))
	var edge := world_to_screen(sample[0])
	if _is_hidden(edge) or _is_hidden(harbour[0]):
		return []
	var on_lane := [edge, _heading_angle(sample[1], sample[0])]
	var poses := [on_lane, harbour] if arriving else [harbour, on_lane]
	var shaped := _loosen(poses, not arriving, false)
	return [_pose_path(shaped, HARBOUR_CURVE_HANDLE), poses, shaped]


## How far (nm of lane) from each end of its leg a ship sails its curve in or
## out of port: [arriving, leaving], worked out once a leg (0 for none).
func _harbour_reaches(ship: Ship, lane, length: float) -> PackedFloat32Array:
	var key := [ship.from_port, ship.to_port]
	var keep := true  # (Not while a port is round the far side: worked out again when it comes round.)
	var cached: Array = _harbour_reach_cache.get(ship, [])
	if not cached.is_empty() and cached[0] == key:
		return cached[1]
	var px_per_nm := _zoom / 60.0
	var reaches := PackedFloat32Array([0.0, 0.0])
	for i in 2:
		var arriving := i == 0
		var port := ship.to_port if arriving else ship.from_port
		if port.is_empty():
			continue
		if _is_hidden(port_screen_position(port)):
			keep = false
			continue
		var harbour := _harbour_end(ship, port, arriving)
		var reach := maxf((harbour[0] as Vector2).distance_to(port_screen_position(port)) / px_per_nm * HARBOUR_REACH, HARBOUR_MIN_NM)
		# A longer curve than its stretch of lane would be faster than at sea:
		# give it as much lane as it's long.
		for k in 3:
			var curve := _harbour_curve(ship, lane, length, arriving, minf(reach, length))
			if curve.is_empty():
				break
			var curve_nm := _path_length(curve[0]) / px_per_nm
			if curve_nm <= reach:
				break
			reach = curve_nm * 1.05
		reaches[i] = reach
	# A short leg: the two ends share it.
	if reaches[0] + reaches[1] > length and reaches[0] + reaches[1] > 0.0:
		var fit := length / (reaches[0] + reaches[1])
		reaches[0] *= fit
		reaches[1] *= fit
	if keep:
		_harbour_reach_cache[ship] = [key, reaches]
	return reaches


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
	# The HQ and hubs get their names placed first (picking a port: the picked
	# one), then the rest by rank.
	var hub_ports := {}
	for hub in GameState.hubs if selectable_ports.is_empty() else []:
		hub_ports[hub.port_id] = true
	if not selected_port.is_empty():
		hub_ports[selected_port] = true
	var ranked := _ports_by_rank.filter(func(port: Dictionary) -> bool: return hub_ports.has(port.id))
	ranked.append_array(_ports_by_rank.filter(func(port: Dictionary) -> bool: return not hub_ports.has(port.id)))
	var labels := []
	var bounds := Rect2(Vector2.ZERO, size)
	for port: Dictionary in ranked:
		if _port_locked(port.id):
			continue  # Its name is hidden till its region is unlocked.
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
	var locked_fill := _color(&"port_locked")
	var draw_port := func(port_id: String) -> void:
		var pos := port_screen_position(port_id)
		if not visible_area.has_point(pos):
			return
		if _port_locked(port_id):
			# In a locked region: a small faint dot, no more.
			_canvas.draw_circle(pos, PORT_RADIUS_MIN, locked_fill)
			return
		if _marina_shown(port_id):
			return  # Grown into its marina (see _draw_marinas()).
		var port_fill := fill if price_commodity.is_empty() else _price_color(port_id)
		if selectable_ports.get(port_id) is Color:
			port_fill = selectable_ports[port_id]
		var radius := _port_radius(port_id)
		_canvas.draw_circle(pos, radius, dimmed if dimmed_ports.has(port_id) else port_fill)
		_canvas.draw_arc(pos, radius, 0.0, TAU, 24, outline, 1.5, true)
		if port_id == selected_port:
			_canvas.draw_arc(pos, radius + 4.0, 0.0, TAU, 32, SELECTED_RING, 3.0, true)
	# Every company's HQ and hubs (other players' too, in multiplayer; none while
	# picking a port, before there's a company).
	var hub_ports := {}  # Port id -> [[hub, its company's ring color], ...]
	for each in GameState.all_companies() if selectable_ports.is_empty() else []:
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
		if _marina_shown(port_id):
			radius = (float(_port_layout(port_id).radius) + JETTY_WIDTH) * _ship_scale() + 1.0  # Round its marina.
		for entry: Array in hub_ports[port_id]:
			var width := HQ_RING_WIDTH if entry[0].is_hq else HUB_RING_WIDTH
			_canvas.draw_arc(port_screen_position(port_id), radius + width / 2.0, 0.0, TAU, clampi(int(radius), 32, 128), entry[1], width, true)
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
	# Its points on the sphere are worked out once; on screen, it's cut where
	# it goes round the far side of the globe.
	var units: PackedVector3Array = _lane_units.get(sea_lane, PackedVector3Array())
	if units.is_empty():
		for p: Vector2 in sea_lane.points:
			units.append(_unit(p))
		_lane_units[sea_lane] = units
	var points := PackedVector2Array()
	for p in units:
		points.append(_unit_to_screen(p))
	for part in _visible_runs(points):
		if dashed:
			for i in range(1, part.size()):
				_canvas.draw_dashed_line(part[i - 1], part[i], color, width, 8.0)
		else:
			_canvas.draw_polyline(part, color, width, true)


## A line's points on screen cut into the runs on the near side of the globe
## (each at least two points long), leaving out the HIDDEN ones.
static func _visible_runs(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for p in points:
		if _is_hidden(p):
			if run.size() >= 2:
				runs.append(run)
			run = PackedVector2Array()
		else:
			run.append(p)
	if run.size() >= 2:
		runs.append(run)
	return runs


## Each canal as a water channel across the land (a convoy canal doubled where
## it has two channels). Zoomed in, lock chambers too (one lane per slot, the
## water rising or falling with a ship inside), convoy anchorages with the time
## to the next convoy, and names: the canal's, then its locks' and places'.
func _draw_canals() -> void:
	var view := Rect2(Vector2.ZERO, size).grow(40.0)
	for canal in GameData.canals:
		var points := _canal_screen_path(canal)
		if points.size() < 2:
			continue
		var bounds := Rect2(points[0], Vector2.ZERO)
		for p in points:
			bounds = bounds.expand(p)
		if not view.intersects(bounds.grow(1.0)):
			continue
		var zoom := _canal_zoom(canal)
		var width := maxf(CANAL_WIDTH * zoom, CANAL_MIN_WIDTH)
		if canal.get("type", "") == "convoy":
			_draw_convoy_channel(canal, points, width)
		else:
			_canvas.draw_polyline(points, _color(&"ocean"), width, true)
		if zoom >= LOCK_MIN_ZOOM:
			for chamber: Dictionary in canal.chambers:
				_draw_chamber(canal, chamber, points)
			if canal.get("type", "") == "convoy":
				_draw_anchorage_labels(canal)
		if zoom >= LOCK_LABEL_ZOOM:
			for lock_index in canal.get("locks", []).size():
				var center := lock_screen_position(canal.id, lock_index)
				_draw_canal_label(canal.locks[lock_index].name, center + Vector2(CHAMBER_LANE_WIDTH * zoom * 1.5 + 6.0, 4.0))
			for label: Array in canal.get("labels", []):
				_draw_canal_label(label[0], world_to_screen(Geo.project(Vector2(label[1], label[2]))))
		elif _web_zoom() >= CANAL_LABEL_WEB_ZOOM:
			_draw_canal_label(canal.name, points[floori(points.size() / 2.0)] + Vector2(8.0, 4.0))


## A convoy canal's channel: one line in the single-lane stretches, two side by
## side (DOUBLE_CHANNEL_GAP apart) in the doubled ones.
func _draw_convoy_channel(canal: Dictionary, points: PackedVector2Array, width: float) -> void:
	var water := _color(&"ocean")
	var gap := DOUBLE_CHANNEL_GAP * _canal_zoom(canal) / 2.0
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


## A canal's path on screen, or none while any of it is round the far side of
## the globe (canals are short: it's only ever just at the edge).
func _canal_screen_path(canal: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p: Vector2 in canal.projected_path:
		var at := world_to_screen(p)
		if _is_hidden(at):
			return PackedVector2Array()
		points.append(at)
	return points


## Pixels per projected degree where a canal is (its widths and locks are
## sized in projected degrees).
func _canal_zoom(canal: Dictionary) -> float:
	return _local_zoom((canal.projected_path as PackedVector2Array)[0])


## One lock chamber: a lane per slot side by side (with a lane each way, ships
## keep right; shared chambers are one lane each), walled, with gates at both ends.
func _draw_chamber(canal: Dictionary, chamber: Dictionary, points: PackedVector2Array) -> void:
	var i: int = chamber.path_index
	var center := points[i]
	var across := _path_normal(points, i)  # Right of a ship sailing along the path.
	var along := Vector2(across.y, -across.x)
	var zoom := _canal_zoom(canal)
	var half := along * CHAMBER_LENGTH * zoom / 2.0
	var lane := across * CHAMBER_LANE_WIDTH * zoom
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
			var at := world_to_screen(chamber.position)
			if _is_hidden(at):
				return HIDDEN
			total += at
			count += 1
	return total / count if count > 0 else Vector2.ZERO


## Where a convoy canal's popup sits: the middle of its path.
func canal_screen_position(canal_id: String) -> Vector2:
	var points := _canal_screen_path(GameData.get_canal(canal_id))
	return points[floori(points.size() / 2.0)] if not points.is_empty() else HIDDEN


## [canal id, lock index] of the lock under a screen point, or [] (only once
## the chambers are drawn).
func _lock_at(screen_pos: Vector2) -> Array:
	for canal in GameData.canals:
		var zoom := _canal_zoom(canal)
		if zoom < LOCK_MIN_ZOOM:
			continue
		for lock_index in canal.get("locks", []).size():
			var center := lock_screen_position(canal.id, lock_index)
			var reach := LOCK_HIT_RADIUS
			for chamber: Dictionary in canal.chambers:
				if chamber.lock == lock_index:
					reach = maxf(reach, world_to_screen(chamber.position).distance_to(center) + CHAMBER_LENGTH * zoom / 2.0)
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
	var on_screen := Vector2.from_angle(_heading_angle(direction, sailing.world_position()))
	var right := Vector2(-on_screen.y, on_screen.x)
	var canal: Dictionary = crossing.canal
	if canal.get("type", "") == "convoy":
		if GameData.in_single_stretch(canal, GameData.canal_s(crossing, sailing.traveled_nm)):
			return Vector2.ZERO
		return right * DOUBLE_CHANNEL_GAP * _canal_zoom(canal) / 2.0
	var chamber := sailing.lock_chamber()
	if not chamber.is_empty() and chamber.canal.locks[chamber.lock].get("lanes", "each_way") == "shared":
		var slots := GameData.chamber_slots(chamber.canal, chamber)
		var offset := (float(slots.find(sailing.lock_slot)) - (slots.size() - 1) / 2.0) * CHAMBER_LANE_WIDTH * _canal_zoom(chamber.canal)
		return right * (offset if chamber.forward else -offset)
	return right * CHAMBER_LANE_WIDTH * _canal_zoom(canal) / 2.0


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
		var along := Vector2.from_angle(_heading_angle(tug.heading(), tug.world_position()))
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
	# Far off screen (most of a big fleet, most of the time): skipped before
	# working out just where (anchored ships lie up to PORT_MAX_REACH from their
	# port, and ships near a port are eased towards it by about as much).
	var near := Rect2(Vector2.ZERO, size).grow((SHIP_CULL_MARGIN + PORT_MAX_REACH) * _ship_scale())
	if ship.is_docked() and not near.has_point(port_screen_position(ship.docked_at)):
		return
	# In port while its marina is too small to show, its port's dot stands for it.
	if ship.is_docked() and not _marina_shown(ship.docked_at):
		return
	# Too small to make out (zoomed well out): a dot in its color, where it is.
	var tiny := (look[7] as Rect2).size.x * _ship_scale() < TINY_SHIP_PX
	if not ship.is_docked() and not ship.is_service() and ship.rescuer == null and not ship.canal_state in [Ship.CANAL_ANCHORED, Ship.CANAL_CONVOY, Ship.CANAL_TOLL]:
		# A cargo ship on its lane (most of them): where and which way from
		# one sample of the lane.
		var here := ship.lane_sample()
		if here.is_empty():
			return
		var on_lane := world_to_screen(here[0])
		if not near.has_point(on_lane):
			return
		if tiny:
			_draw_tiny_ship(on_lane, color)
			return
		var harbour := _harbour_pose(ship)
		if harbour.is_empty():
			at = on_lane + _canal_lane_offset(ship)
			angle = _heading_angle(here[1], here[0])
		else:
			at = harbour[0]
			angle = harbour[1]
	else:
		at = ship_screen_position(ship)
		if tiny:
			_draw_tiny_ship(at, color)
			return
		angle = _screen_angle(ship)
	if not Rect2(Vector2.ZERO, size).grow(SHIP_CULL_MARGIN * _ship_scale()).has_point(at):
		return  # Off screen.
	if ship.is_docked() and docks_shown() and not ship.is_tug() and ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
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


## A ship too small on screen to make out (see TINY_SHIP_PX): a dot in its color.
func _draw_tiny_ship(at: Vector2, color: Color) -> void:
	if Rect2(Vector2.ZERO, size).has_point(at):
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		_canvas.draw_rect(Rect2(at - Vector2.ONE, Vector2.ONE * 2.0), color)


## The hull in the model's color, the cargo (cut off behind how full the hold
## is, in CARGO_STEPS steps, any cargo showing at least one) and the details.
func _draw_ship_art(ship: Ship, art: Dictionary, rect: Rect2, color: Color, fade := Color.WHITE) -> void:
	_canvas.draw_texture_rect(art.hull, rect, false, color)
	var level := ship.cargo_level()
	if art.has("cargo") and level > 0.0:
		var zone: Vector2 = art.zone
		var fill := ceilf(level * CARGO_STEPS) / CARGO_STEPS
		var share := (zone.x + fill * (zone.y - zone.x)) / SHIP_ART_WIDTH
		var texture: Texture2D = (art.get("skins", {}) as Dictionary).get(ship.cargo_id, art.cargo)  # What it carries, shown.
		_canvas.draw_texture_rect_region(texture, Rect2(rect.position, Vector2(rect.size.x * share, rect.size.y)),
			Rect2(Vector2.ZERO, Vector2(texture.get_width() * share, texture.get_height())), fade)
	_canvas.draw_texture_rect(art.details, rect, false, fade)


## How many times its map_size a ship (and its docks) is drawn at this zoom:
## in step with the map, so a ship keeps its size in the world.
func _ship_scale() -> float:
	return _zoom / SHIP_WORLD_ZOOM


## How many times its length_px a sea animal is drawn: sized in the world like
## the ships (smaller zoomed out, bigger zoomed in), length_px at
## ANIMAL_WORLD_ZOOM px a degree.
func _animal_scale() -> float:
	return _zoom / ANIMAL_WORLD_ZOOM


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
		# A skin per commodity where there is one (livestock and vehicle carriers:
		# tools/make_cargo_skins.gd), so a ship shows which of its goods it carries.
		art.skins = {}
		for model: Dictionary in GameData.ship_models:
			if model.get("category", "") == category:
				for commodity: String in model.get("cargo", []):
					var skin := SHIP_ART_DIR + "%s_cargo_%s.svg" % [category, commodity]
					if ResourceLoader.exists(skin):
						art.skins[commodity] = load(skin)
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

## Each storm (GameState.weather): its cloud is the sky's (globe.gdshader:
## dark spiral bands for tropical storms, ragged rain cloud for the rest), and
## over it, its track, lightning in a tropical storm's bands, and its name
## under the core when there's room.
func _draw_storms() -> void:
	_draw_storm_tracks()
	var font := get_theme_default_font()
	for storm: Dictionary in GameState.weather.storms:
		var circle := _storm_circle(storm)
		var center: Vector2 = circle[0]
		var radius: float = circle[1]
		if not Rect2(Vector2.ZERO, size).grow(radius).has_point(center):
			continue
		var strength := Weather.intensity(storm)
		var alpha := lerpf(0.35, 1.0, strength)
		if Weather.TROPICAL.has(storm.kind) and radius > LIGHTNING_MIN_RADIUS:
			_draw_lightning(storm, center, radius, strength)
		if radius > STORM_LABEL_MIN_RADIUS:
			var text := Weather.title(storm)
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE).x
			var baseline := center + Vector2(-width / 2.0, radius * 0.18 + STORM_FONT_SIZE)
			_canvas.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE, 4, Color(0, 0, 0, 0.6 * alpha))
			_canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE, Color(1, 1, 1, 0.9 * alpha))


## A storm's center on screen and its radius there (px): [center, radius].
func _storm_circle(storm: Dictionary) -> Array:
	# A degree of the globe's surface is 60 nm.
	var radius: float = float(storm.radius_nm) / 60.0 * _zoom
	return [world_to_screen(Geo.project(Vector2(storm.lon, storm.lat))), radius]


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
		var path := _track_on_screen(points)
		var storm_key := Weather.key(storm)
		var highlight := storm_key == _hovered_storm or storm_key == selected_storm
		var color := Color(STORM_TRACK_COLOR, STORM_TRACK_HIGHLIGHT_ALPHA if highlight else STORM_TRACK_COLOR.a)
		for part in _visible_runs(path):
			var bounds := Rect2(part[0], Vector2.ZERO)
			for p in part:
				bounds = bounds.expand(p)
			if view.intersects(bounds.grow(STORM_TRACK_WIDTH)):
				_draw_dashed_path(part, color, STORM_TRACK_WIDTH)
		if highlight:
			var circle := _storm_circle(storm)
			for share: float in [1.0, Weather.CORE]:
				_draw_dashed_path(_circle_points(circle[0], float(circle[1]) * share), color, 2.0)


## A track's points (lon, lat) on screen (HIDDEN round the far side of the globe).
func _track_on_screen(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(world_to_screen(Geo.project(p)))
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
## DECOR_BUCKET-degree cells, once for every map view.
static func _load_decor() -> void:
	if not _decor_textures.is_empty():
		return
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
	var center_zoom := _local_zoom(_center)
	for tier in data.decor_tier_spacing.size():
		if data.decor_tier_spacing[tier] * center_zoom >= DECOR_MIN_SPACING_PX:
			max_tier = tier
	if max_tier < 0:
		return
	var scale := clampf(sqrt(_zoom / DECOR_ZOOM_REFERENCE), DECOR_SCALE_RANGE.x, DECOR_SCALE_RANGE.y)
	# The cells that can be in view: those within the stretch of globe the
	# view's corners reach (all of the near side, zoomed right out).
	var reach := rad_to_deg(asin(minf(size.length() / 2.0 / _radius(), 1.0))) + DECOR_SIZE_PX.y * scale / _zoom
	var across := 180.0
	if absf(_view_lat) + reach < 89.0:
		across = rad_to_deg(asin(minf(sin(deg_to_rad(minf(reach, 90.0))) / cos(deg_to_rad(_view_lat)), 1.0)))
		if reach >= 90.0:
			across = 180.0
	var low := Vector2(_view_lon - across, _mercator_y(_view_lat - reach))
	var high := Vector2(_view_lon + across, _mercator_y(_view_lat + reach))
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
				if _decor_locked(i):
					continue  # Its region is locked: shaded, bare.
				if center_zoom < float(DECOR_MIN_ZOOM.get(data.decor_kind_names[data.decor_kinds[i]], 0.0)):
					continue  # Not yet: it shows only from closer in.
				var at := world_to_screen(data.decor_positions[i])
				if not screen.has_point(at):
					continue
				# Only while all of it fits clear of the water (land drawings on land, waves
				# on the sea): its corners reach about its size from its spot.
				if i < data.decor_clearance.size() and data.decor_clearance[i] * _local_zoom(data.decor_positions[i]) < _decor_side(data.decor_kind_names[data.decor_kinds[i]], scale) * 1.05:
					continue
				shown.append([at, data.decor_kinds[i]])
	shown.sort_custom(func(p: Array, q: Array) -> bool: return p[0].y < q[0].y)
	for item: Array in shown:
		var texture := _decor_textures[item[1]]
		if texture == null:
			continue
		var side := _decor_side(data.decor_kind_names[item[1]], scale)
		_canvas.draw_texture_rect(texture, Rect2(item[0] - Vector2(side / 2.0, side * 0.92), Vector2(side, side)), false)


## How big a kind of drawing is on screen (px): mountains biggest, then
## animals (and waves), then plants and rocks.
static func _decor_side(kind_name: String, scale: float) -> float:
	var big := DECOR_ANIMALS.has(kind_name) or kind_name == "waves"
	return (DECOR_SIZE_PX.y if kind_name.begins_with("mountain") else (DECOR_SIZE_PX.z if big else DECOR_SIZE_PX.x)) * scale


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
		var target: float = _heading_angle(heading, Geo.project(state.pos)) if heading != Vector2.ZERO else float(_pod_angles.get(i, 0.0))
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
	if texture == null or not _on_water(at, facing, length):
		return  # Never drawn over land, even partly.
	_draw_sea_sprite(_sea_silhouette(str(kind.art)), at, facing, length, 1.0, SEA_SHADOW)
	var dolphin: bool = kind.kind == "dolphin"
	var breach: Array = kind.get("breach", [])
	if not breach.is_empty():
		var up := _sea_event(pod, j, "breach", float(breach[0]), float(breach[1]), SEA_LEAP_S if dolphin else SEA_BREACH_S)
		# A leap or breach reaches out ahead and up the screen (and splashes round
		# it): only where all that is water too.
		var reach := at + Vector2.from_angle(facing) * length * (0.7 if dolphin else 0.0) - Vector2(0.0, length * (0.7 if dolphin else 0.25))
		if up >= 0.0 and _on_water(reach, facing, length * 1.6):
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


## True if a sea animal `length` long (screen px) at a screen point, facing
## that way, lies wholly over water: its middle, nose, tail and both sides, by
## the sea mask (which counts the cells along the coast as land, so this errs
## towards keeping them out to sea).
func _on_water(at: Vector2, facing: float, length: float) -> bool:
	var along := Vector2.from_angle(facing) * length * 0.55
	var across := along.orthogonal() * (1.0 / SEA_ART_ASPECT)
	var sea := SeaLife.shared()
	for point: Vector2 in [at, at + along, at - along, at + across, at - across]:
		if not sea.is_sea(Geo.unproject(screen_to_world(point))):
			return false
	return true


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
		for part in _visible_runs(_track_on_screen(points)):
			_draw_dashed_path(part, SEA_ROUTE_COLOR, 2.0)
	for stay: Dictionary in sea.pods[pod].stays:
		var area: Dictionary = sea.areas[stay.area]
		var at := world_to_screen(Geo.project(Vector2(area.lon, area.lat)))
		if not _is_hidden(at):
			_draw_dashed_path(_circle_points(at, float(area.radius_nm) / 60.0 * _zoom), SEA_ROUTE_COLOR, 2.0)


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


## The land's biome colors (LAND_COLORS), from the load GameData starts in the
## background at boot, or null if there are none.
static func land_colors_texture() -> Texture2D:
	if ResourceLoader.load_threaded_get_status(LAND_COLORS) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		return ResourceLoader.load_threaded_get(LAND_COLORS) as Texture2D
	return load(LAND_COLORS) as Texture2D if ResourceLoader.exists(LAND_COLORS) else null

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
## A flock of birds was clicked: what it's round ({port}, {ship} or {pod}) and
## the flock ({count, species}: see Birds).
signal birds_clicked(about: Dictionary, flock: Dictionary)
## A group of land animals was clicked: its patch's key and species (see
## LandLife and _draw_fauna()).
signal animals_clicked(key: String, kind: String)
## One of this player's hubs' industry plots was clicked (see _industry_plots()).
signal industry_clicked(port_id: String, slot: int)
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
## Once its marina shows, a click anywhere on it (within this many of its
## radii of its middle: the basin, jetty and quay) picks the port; birds over
## it only when clicked right on (this share of their usual reach).
const MARINA_HIT_RADII := 1.45
const MARINA_BIRD_REACH := 0.5
## How long (s) a ship's birds take to go from wheeling round it to flying
## along with it (or back) as it gets going or stops (see _under_way()).
const UNDER_WAY_EASE_S := 2.0
## The most birds in one V (see _v_spot()): a bigger flock flies in several.
const V_SIZE := 9
## About how often (s) a port's cormorants fly past (see _draw_cormorants()).
const CORMORANT_PASS_S := 60.0
## About how often (s) a port's migrating cranes pass over (see _draw_waders()).
const CRANE_PASS_S := 90.0
## A port's shore beside its marina (see _shore_spots()): how far out either
## side it's looked for (marina radii), at how many places, and how far in
## from the sea and out to it.
const SHORE_REACH := 3.2
const SHORE_SAMPLES := 24
const SHORE_INLAND := 2.6
const SHORE_SEAWARD := 3.0
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
	"quetzal", "water_buffalo", "pizza"]
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
## A two-finger swipe on a trackpad zooms this many wheel steps per unit it moves.
const SWIPE_ZOOM_RATE := 0.35
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
## A shining port's glow (see shining_ports): rings round it, [px out, alpha].
const SHINE_RINGS := [[12.0, 0.1], [8.0, 0.18], [4.0, 0.32]]
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
## Each commodity's industry building (see _draw_industry()).
const INDUSTRY_ART_DIR := "res://art/industry/"
const SHIP_ART_WIDTH := 180.0
## Where the cargo sits along the art (x from the stern, in art units). It
## fills from the stern forward in CARGO_STEPS steps, so part loads show.
const CARGO_ZONES := {container = Vector2(34.0, 138.0), vehicles = Vector2(12.0, 147.4), livestock = Vector2(34.0, 138.0)}
const CARGO_STEPS := 4
## Bulk carriers' hatch covers (art units, as their <category>_details.svg draws
## them shut; <category>_details_open.svg is the same without them): where
## each hatch starts along the ship, how wide it is, its stretch across, which
## way its two covers part ("y": rolling off to either side, "x": folding fore
## and aft) and their colors. Moored for a stop they fold open over HATCH_S
## (see _hatch_open()), showing the hold (its cargo, HOLD_COLORS, filling
## and emptying with the stop), and fold shut before it leaves.
const HATCHES := {
	ore = {starts = [36.0, 52.0, 68.0, 84.0, 100.0, 116.0, 132.0], width = 13.0, across = Vector2(12.0, 40.0), part = "y", fill = "#7c8288", edge = "#3a3e42"},
	grain = {starts = [36.0, 57.0, 78.0, 99.0, 120.0], width = 15.0, across = Vector2(13.0, 39.0), part = "x", fill = "#4f7a52", edge = "#2e4a30"},
}
const HATCH_S := 3.0
const HOLD_COLORS := {iron = "#8a4a32", coal = "#262626", gold = "#b8963c", wheat = "#d9b45a", corn = "#e6c03a",
	soybeans = "#c9b27a", rice = "#ece4cc", barley = "#c8a65c"}
const EMPTY_HOLD := Color("#3a332c")
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
## Tugs on a tow pull from ahead of the ship's bow, on tow lines this many of
## their own lengths long; two side by side in a tight Y, this many of their
## widths out to either side of the way (their lines the same length); and the
## line's color. A towed ship comes round from the way it lay to the way it's
## towed over its first TOW_SWING_NM.
const TOW_LINE_TUGS := 1.2
const TOW_Y_WIDTHS := 0.7
const TOW_LINE_COLOR := Color(0.92, 0.9, 0.82)
const TOW_SWING_NM := 3.0
## Tugs working a ship in at port (see _tug_work()): how tight they turn (a
## radius, in their own lengths), how fast they go round the harbour, push and
## back off (shares of their own speed), how far their bows stay off the hull
## (dock units), where along the ship they push (a share of its length either
## side of its middle), and how long (in tug lengths) a ship must be for a
## lone tug to push it in twice, stern half then bow half.
const TUG_TURN_TUGS := 0.7
const TUG_HARBOUR_SHARE := 0.6
const TUG_PUSH_SHARE := 0.2
const TUG_BACK_SHARE := 0.35
const TUG_HULL_GAP := 0.3
const TUG_PUSH_STATION := 0.3
const TUG_TWO_PUSHES_TUGS := 2.5
## A lone tug pushing a ship in comes in on a slant (see _plan_tug_work()):
## how far ahead of the other its end comes in through a push (a share of the
## way in), and how far ahead its end is left after a first push of two.
const LONE_PUSH_LEAD := 0.35
const LONE_PUSH_SLANT := 0.55
## Tugs moor along the inside of their marina's breakwater (see _jetty_pose()):
## the first this far (radians) round from where it meets the quay, each the
## next this far (dock units) on from the last.
const TUG_MOOR_END := 0.12
const TUG_MOOR_GAP := 0.6
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
## How far off screen (px) a label's spot can be and the label still show
## (a long one, nudged): further out, it isn't even measured.
const LABEL_REACH_PX := 400.0
## Feature labels are sorted into cells of the globe this many degrees square,
## so only those near the view are looked at (see _ranks_near_view()).
const LABEL_CELL_DEG := 10.0
## Route lines are looked at in chunks of this many points, so the parts that
## can't be in view are skipped (see _chunk_caps()).
const LANE_CHUNK := 32
## Lanes bend round the harbours of ports they pass but aren't sailing to (see
## _bent_lane()): each port's keep-out zone reaches this many times its mouth's
## distance from it (round its marina and approach curves), filled in every
## ZONE_STEP_DEG where a lane bends; zones checked again every ZONE_CHECK_S; a
## ship's heading there taken over ZONE_HEADING_NM either side of it.
const ZONE_MOUTHS := 1.8
const ZONE_STEP_DEG := 0.04
const ZONE_CHECK_S := 5.0
const ZONE_HEADING_NM := 2.0
## How far along a lane (points) how far it may bend is smoothed (see _bent_lane()).
const ZONE_SMOOTH_POINTS := 8
## A push this small (degrees) is let be even onto the land (see _bent_lane()).
const ZONE_FREE_DEG := 0.08
## The land's triangles are sorted into cells this big (projected degrees) to
## tell if a point's on the land (see _on_land()).
const LAND_CELL_DEG := 1.0
## How far (projected degrees) the view moves before route lines' harbour curves
## are worked out again (see _lane_pieces()): the globe's turn changes them
## by a hair over that.
const LANE_CURVE_DRIFT := 1.0
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
		_land_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED if gray_mode else SubViewport.UPDATE_ONCE
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
## Picking a port: the choices (port id -> true) that shine, with a soft glow
## of their color round them and a glint (the excellent starts).
var shining_ports: Dictionary = {}:
	set(value):
		shining_ports = value
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
## Each lane's chunks (see _chunk_caps()), worked out with its points.
var _lane_caps := {}
## Canals' boxes (lon, lat), where lanes don't bend (see _in_canal()).
var _canal_boxes: Array[Rect2] = []
## The land's triangles by cell (see _on_land()), and the task sorting them.
static var _land_cells := {}
static var _land_task := -1
## The fleet's lanes (see _active_lanes()), and when (ms) they were worked out.
var _active_lanes_cache := []
var _active_lanes_time := -1
## Gust cells' steady offsets and their spots this cycle (see _draw_gusts()).
var _gust_offsets := {}
var _gust_spots := {}
## Each ship's last place and how much it's under way (see _under_way()).
var _ship_motion := {}
## Each cormorant species' colors for drawing it swimming (see _cormorant_swimmer()).
var _cormorant_swimmers := {}
## Port id -> its shore beside its marina, found once (see _shore_spots()).
var _shores := {}
var _shore_neighbours := {}  # Port id -> the ports near it (see _local_on_land()).
## Port id -> its docks' turn on screen for the current view (see _dock_point()).
var _port_turns := {}
## Port id -> where it is on screen for the current view (see port_screen_position()).
var _port_screens := {}
## Each port on the unit sphere (see port_screen_position()).
static var _port_units := {}
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
## Label text sizes, measured once (see _label_size()).
var _label_sizes := {}
## Country and feature labels' spots on the unit sphere, worked out once.
var _country_units := PackedVector3Array()
var _feature_units := PackedVector3Array()
## The feature labels that show at a web zoom (in priority order), and how many
## of the zooms they show from (_feature_thresholds, sorted) it was past.
var _features_shown := PackedInt32Array()
var _features_level := -1
var _feature_thresholds := PackedFloat64Array()
## Those labels' places in _features_shown, by cell of the globe (see _label_cell()).
var _feature_cells := {}
## The ports by cell of the globe, and those near the view (see _ports_near_view()).
static var _port_cells := {}
var _near_ports := PackedInt32Array()
var _near_ports_valid := false
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
## The land animals roaming over the land drawings (every frame while any show;
## see _draw_fauna()), the groups _draw_decor() found in view: [patch key,
## art, its spot on screen, art side (px), how much of its patch fits on land,
## species info, tree art, species], and their goings on.
var _fauna_layer := Control.new()
var _fauna := []
var _land_life := LandLife.new()
## Where each land animal was last drawn, for clicking: [screen point, reach
## (px), patch key, species].
var _fauna_hits := []
## Route lines' curves' reaches along their lanes (see _lane_pieces()), for one zoom.
var _lane_reach_memo := {}
var _lane_reach_zoom := -1.0
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
## Land animals' other drawings by "<kind>_<frame>" (see _animal_frame()).
static var _animal_frames := {}
## Industry buildings' art by commodity (see _industry_texture()).
static var _industry_art := {}
static var _decor_buckets := {}
## Each land drawing on the unit sphere, and its clearance (see
## _load_decor()) over its spot's cosh: times the zoom, its room on screen in px.
static var _decor_units := PackedVector3Array()
static var _decor_room := PackedFloat64Array()
## Birds' shapes a unit across (see _bird_shape()), and their bodies and a raptor's bill.
static var _bird_shapes := {}
static var _bird_body := PackedVector2Array([Vector2(0.16, 0.0), Vector2(0.04, 0.06), Vector2(-0.22, 0.05), Vector2(-0.3, 0.0), Vector2(-0.22, -0.05), Vector2(0.04, -0.06)])
static var _raptor_bill := PackedVector2Array([Vector2(0.21, -0.025), Vector2(0.27, 0.0), Vector2(0.21, 0.025)])
var _canal_layer := Control.new()
var _static_layer := Control.new()
## The ports' marinas (see _update_marinas()), over the land drawings and under
## the clouds, ports and labels; on the gray map, docked ships (dots in rings
## round their ports, tugs as ticks) instead. Redrawn when the view changes, a
## ship docks or leaves, and with the ports' slow size changes.
var _dock_layer := Control.new()
var _overlay := Control.new()
var _canvas: Control = _overlay
var _static_clock := 0.0
var _ports_by_rank: Array = []  # Label priority order, sorted on first draw.
## The ports in label order with the HQ, hubs and picked port first, and those ports.
var _ranked_ports: Array = []
var _ranked_ports_key := {"": false}


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
	if GameState.anchor_route.get_object() == self:
		GameState.anchor_route = Callable()
	if GameState.berth_route.get_object() == self:
		GameState.berth_route = Callable()


func _ready() -> void:
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	if not GameState.berth_route.is_valid():
		GameState.berth_route = berth_route_seconds  # (The first map open measures ships' ways in and out of port.)
	if not GameState.anchor_route.is_valid():
		GameState.anchor_route = anchor_tow_seconds
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
	_land_mask.render_target_update_mode = SubViewport.UPDATE_DISABLED if gray_mode else SubViewport.UPDATE_ONCE
	add_child(_land_mask)
	_land_mask_art.art = art
	_land_mask_art.material = _globe
	RenderingServer.canvas_item_set_custom_rect(_land_mask_art.get_canvas_item(), true, NEVER_CULLED)
	_land_mask.add_child(_land_mask_art)

	for layer: Control in [_decor_layer, _fauna_layer, _dock_layer]:
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
	_fauna_layer.draw.connect(_draw_fauna)
	_fauna_layer.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_decor()
	_start_land_cells()  # (For bending lanes round harbours: see _bent_lane().)
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
	# Already its size (made in code with a minimum size, say): it won't be
	# resized, so fit the view now (once whoever made it has set it up).
	if size.x > 0.0 and size.y > 0.0:
		_on_resized.call_deferred()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_ease_view(delta)
	_update_regions()
	_update_sky()
	if _layers_stale:
		_flush_layers()  # (After the view eased: see _redraw_layers().)
	if not _fauna.is_empty():
		_fauna_layer.queue_redraw()  # The land animals going about their day.
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
		_update_marinas()


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
		if not _port_units.has(port_id):
			_port_units[port_id] = _unit(GameData.port_position(port_id))  # (Worked out once: ports don't move.)
		_port_screens[port_id] = _unit_to_screen(_port_units[port_id])
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
		var towing := _towing_pose(ship)
		if not towing.is_empty():
			return towing[0]
		var pose := _turning_pose(ship)
		if not pose.is_empty():
			return pose[0]
		var harbour := _harbour_pose(ship)
		if not harbour.is_empty():
			return harbour[0]
		return world_to_screen(_ship_world(ship)) + _canal_lane_offset(ship)
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
	var towing := _towing_pose(ship)
	if not towing.is_empty():
		return towing[1]
	var pose := _turning_pose(ship)
	if not pose.is_empty():
		return pose[1]
	var harbour := _harbour_pose(ship)
	if not harbour.is_empty():
		return harbour[1]
	return _heading_angle(_ship_heading(ship), _ship_world(ship))


## Where a tug on a tow job and the ship it's towing are drawn, and which way
## they face, [screen point, angle], or [] for any other ship (or off the
## map): heading out (stopping short ahead of the lost ship, see
## _tug_out_pose()), towing it at sea (_tow_place(), _towed_pose()), and
## working it in at port (_tug_work()).
func _towing_pose(ship: Ship) -> Array:
	if ship.is_towed():
		return _towed_pose(ship)
	if not ship.is_tug() or ship.rescuing == null:
		return []
	match ship.job_phase:
		Ship.JOB_APPROACH:
			return _tug_out_pose(ship)
		Ship.JOB_TOW:
			return _tow_place(ship)
		Ship.JOB_BERTH:
			return _tug_work_pose(ship)
	return []


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
	var base := world_to_screen(_ship_world(ship)) + _canal_lane_offset(ship)
	var look_rect: Rect2 = _model_look(ship.model_id)[7]
	var radius := look_rect.size.x * TURN_RADIUS_LENGTHS * _ship_scale()
	var on_lane := _ship_bent(ship)
	var lane_angle := _heading_angle(on_lane[1], on_lane[0]) if not on_lane.is_empty() else _heading_angle(ship.lane_heading(), ship.world_position())
	if ship.is_tug():
		# Stopped short ahead of the lost ship, it turns round on its turning
		# circle to face home and comes to its place for the tow, ahead of the
		# ship's bow on its line (two side by side).
		if ship.job_phase != Ship.JOB_ALIGN or ship.rescuing == null:
			return []
		var stopped := _tug_out_pose(ship)
		var place := _tow_place(ship)
		if stopped.is_empty() or place.is_empty():
			return []
		return _turn_pose(stopped[0], float(stopped[1]), place[0], float(place[1]), radius,
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
	return [base, _heading_angle(_ship_heading(ship), _ship_world(ship))]


# --- Tugs working a ship in at port ------------------------------------------------

## The lead tug working a ship in at port (bringing it alongside its berth, or
## to its spot at the anchorage, after towing it in), or null.
static func _assist_lead(ship: Ship) -> Ship:
	var lead := ship.rescuer
	return lead if lead != null and lead.is_tug() and lead.job_phase == Ship.JOB_BERTH else null


## How far (s) into working their ship in a tug's team is: as far as the ship
## is through coming alongside, or (taking it to the anchorage) the tug's own
## time at it.
static func _work_time(tug: Ship) -> float:
	var ship := tug.rescuing
	if ship != null and ship.is_docked() and ship.berth >= 0 and ship.berth_phase == Ship.BERTH_IN:
		return ship.berth_time
	return tug.align_time


## A screen pose ([point, angle]) as its port's marina's dock units, and back.
func _screen_to_local(port_id: String, pose: Array) -> Array:
	var turn := _port_sea_angle(port_id) + _port_turn(port_id)
	var flip := float(_dock_flips.get(port_id, 1.0))
	var local := ((pose[0] as Vector2) - port_screen_position(port_id)).rotated(-turn) / dock_scale(port_id)
	local.y *= flip
	return [local, (float(pose[1]) - turn) * flip]


func _local_to_screen(port_id: String, pose: Array) -> Array:
	return [_dock_point(port_id, pose[0]), _dock_angle(port_id, float(pose[1]))]


## How a team of tugs works the ship they towed in at port, in their marina's
## dock units, worked out once (and again if the ship's berth or spot changes).
## Every tug goes the way it faces (round smooth turns, TUG_TURN_TUGS of its
## length; backing straight off at most), never sideways:
## - Pulling: they tow it in on their lines, ahead of its bow (two in a tight
##   Y), through the mouth and round to lie off its berth. With no berth free
##   they cast off at the mouth instead and go; it glides on to its spot at
##   the anchorage to wait, as any ship coming in to wait does.
## - Peeling off: as it comes up to its berth, each swerves out to its open
##   side and eases to a stop there, just short of where it'll push (two: one
##   either side of its middle; a lone tug: the bow half of a ship long enough
##   to want two pushes, else its middle), the ship gliding on past them.
## - Pushing: each turns in to lay its bow on the hull, and they push it
##   sideways onto the berth, going with it. A lone tug on a long ship then
##   backs off, comes round along it to the stern half and pushes again.
## - Backing off: they back off clear of it once it's moored (then, docked,
##   turn away and go to their moorings on the jetty; see _lying_pose()).
## {total (s), team, ship: its segments, tugs: each tug's segments, finish:
## each tug's way off when it lets go}, or {} if there's nothing to work out.
## Each segment is {kind, t0, t1, ...}: "path" (along points, as timed),
## "hold" (a pose), "slide" (pushed in, bow and stern each from one share of
## the way to another), "follow" (pulling,
## `ahead` along the ship's path, `side` out from it, peeling off to `side_to`
## `past` along from where it stops), "attached" (pushing:
## at `x` along the ship and `out` from it, facing in) and "reverse" (backing
## from one point to another).
func _tug_work(tug: Ship) -> Dictionary:
	var team := tug.tug_team()
	if team.is_empty() or team[0].rescuing == null:
		return {}
	var lead: Ship = team[0]
	var ship := lead.rescuing
	var port := lead.tow_port
	if ship.docked_at != port:
		return {}
	var layout := _port_layout(port)
	var anchoring: bool = ship.berth < 0 or ship.berth >= (layout.berths as Array).size()
	var anchor := _anchor_local(ship) if anchoring else Vector2.ZERO
	var key := [port, ship.berth, ship.berth_half, team.map(func(each: Ship) -> int: return each.id), float(layout.radius), anchoring, str(anchor)]
	var kept: Array = _tug_works.get(lead, [])
	if not kept.is_empty() and kept[0] == key:
		return kept[1]
	var work := _plan_tug_work(lead, team, ship, port, layout, anchoring)
	_tug_works[lead] = [key, work]
	for i in team.size():
		_tug_finish[team[i]] = [port, work.finish[i]] if not work.is_empty() else []
	return work


func _plan_tug_work(lead: Ship, team: Array[Ship], ship: Ship, port: String, layout: Dictionary, anchoring: bool) -> Dictionary:
	var look: Rect2 = _model_look(ship.model_id)[7]
	var tug_look: Rect2 = _model_look(lead.model_id)[7]
	var length := look.size.x
	var width := look.size.y
	var tug_length := tug_look.size.x
	var tug_width := tug_look.size.y
	var units_per_nm := SHIP_WORLD_ZOOM / 60.0
	var tow_speed := 0.0
	for each in team:
		tow_speed += GameState._tow_speed(each)
	tow_speed = maxf(tow_speed, MIN_HARBOUR_SPEED) * units_per_nm
	var tug_speed := maxf(lead.speed(), MIN_HARBOUR_SPEED) * units_per_nm
	var mouth := _screen_to_local(port, _keep_right(port, _entrance_pose(port, false, true)))
	# Pulling it in: through the mouth and round to lie off its berth, or out to its spot.
	# Straight in through the mouth as far as the tugs are ahead (just as they
	# were coming in from sea: see _tow_track()), then round.
	var ahead := length / 2.0 + tug_length * (TOW_LINE_TUGS + 0.5)
	var lead_in := [(mouth[0] as Vector2) + Vector2.from_angle(float(mouth[1])) * ahead, mouth[1]]
	if anchoring:
		# No berth free: they cast off at the mouth, where their tow ends, and go
		# to their spots; it glides on to its own, as any ship coming in to wait does.
		var at_mouth := {kind = "path", t0 = 0.0, t1 = 0.0, points = PackedVector2Array([mouth[0], lead_in[0]]), times = PackedFloat32Array([0.0, 0.0]), start = float(mouth[1]), end = float(mouth[1])}
		var cast_off := {total = 0.0, team = team, ship = [at_mouth], tugs = [], finish = []}
		for i in team.size():
			var side := 0.0 if team.size() == 1 else (1.0 if i == 0 else -1.0) * tug_width * TOW_Y_WIDTHS
			cast_off.tugs.append([{kind = "follow", t0 = 0.0, t1 = 0.0, ahead = ahead, side = side, side_to = side, past = 1.0e9, swing = tug_length}])
			cast_off.finish.append([_work_pose(cast_off, cast_off.tugs[i], 0.0)])
		return cast_off
	var berth: Array = layout.berths[ship.berth]
	var moored: Array = _berth_pose(berth, ship)
	var out: Vector2 = berth[2]
	var end_pose := [(moored[0] as Vector2) + out * width * BERTH_OFF_WIDTHS, moored[1]]
	var poses := [mouth, lead_in, end_pose]
	var shaped := _loosen(poses, false, false)
	var path := _pose_path(shaped)
	var times := _path_times(path, tow_speed, length, length, false, true)
	var pulled := times[-1]
	var ship_segments: Array = [{kind = "path", t0 = 0.0, t1 = pulled, points = path, times = times, start = float(mouth[1]), end = float(end_pose[1])}]
	# Where along the ship each tug will push (the first push), and the ship's
	# open side (away from the quay), as the way it's pulled sees it.
	var middle: Vector2 = end_pose[0]
	var forward := Vector2.from_angle(float(end_pose[1]))
	var stand := width / 2.0 + tug_length / 2.0 + TUG_HULL_GAP
	var station := maxf(length * TUG_PUSH_STATION, tug_width * 0.7)
	var radius := tug_length * TUG_TURN_TUGS
	var pushes: Array = []  # Each push: [the share of the way it goes, each tug's station along the ship].
	if team.size() > 1:
		pushes = [[1.0, [station, -station]]]
	elif length >= tug_length * TUG_TWO_PUSHES_TUGS:
		pushes = [[0.55, [station]], [1.0, [-station]]]
	else:
		pushes = [[1.0, [station * 0.5]]]  # A little to the bow, so it comes in bow first.
	var open_side := signf(out.dot(Vector2.from_angle(float(end_pose[1]) + PI / 2.0)))
	var tug_segments: Array = []
	for i in team.size():
		var side := 0.0 if team.size() == 1 else (1.0 if i == 0 else -1.0) * tug_width * TOW_Y_WIDTHS
		# Peeling off to its open side as it comes up to its berth, they ease to
		# a stop there, out from where they'll push; it glides on past them.
		var x: float = pushes[0][1][i]
		tug_segments.append([{kind = "follow", t0 = 0.0, t1 = pulled, ahead = ahead, side = side, side_to = open_side * (stand + radius), past = x - radius, swing = tug_length}])
	var work := {total = pulled, team = team, ship = ship_segments, tugs = tug_segments, finish = []}
	# Turning in to lay their bows on the hull at their stations.
	var harbour_speed := tug_speed * TUG_HARBOUR_SHARE
	var t := pulled
	var arrived := t
	for i in team.size():
		var start := _work_pose(work, tug_segments[i], pulled)
		var x: float = pushes[0][1][i]
		var turn_in := _pose_path([start, [middle + forward * x + out * stand, (-out).angle()]])
		var turn_times := _path_times(turn_in, harbour_speed, tug_length, tug_length * 0.5, true, true)
		tug_segments[i].append({kind = "path", t0 = t, t1 = t + turn_times[-1], points = turn_in, times = turn_times, start = float(start[1]), end = (-out).angle()})
		arrived = maxf(arrived, t + turn_times[-1])
	for i in team.size():
		var there: PackedVector2Array = (tug_segments[i][-1] as Dictionary).points
		tug_segments[i].append({kind = "hold", t0 = (tug_segments[i][-1] as Dictionary).t1, t1 = arrived, pose = [there[-1], (-out).angle()]})
	ship_segments.append({kind = "hold", t0 = pulled, t1 = arrived, pose = end_pose})
	t = arrived
	# Pushing it on (and, a lone tug on a long ship, coming round between pushes).
	# A lone tug brings in its end of the ship first, so it comes in on a slant
	# (pushed at its bow half, it's left lying slanted till the stern half's
	# pushed). Each push takes its two ends, bow and stern, from how far in
	# they are (shares of the way) to how far in after it (see "slide").
	var push_speed := tug_speed * TUG_PUSH_SHARE
	var back_speed := tug_speed * TUG_BACK_SHARE
	var back_by := tug_length * TUG_TURN_TUGS * 2.0
	var ends_in := [0.0, 0.0]
	var gone := 0.0
	for p in pushes.size():
		var share: float = pushes[p][0]
		var to_in := [share, share]
		var leading := 0.0  # Which end the tug's on, and comes in first: 1 the bow, -1 the stern.
		if team.size() == 1:
			leading = signf(float(pushes[p][1][0]))
			if share < 1.0:
				to_in = [share + (1.0 - share) * LONE_PUSH_SLANT, share - (1.0 - share) * LONE_PUSH_SLANT]
				if leading < 0.0:
					to_in.reverse()
		var push_s := maxf((share - gone) * width * BERTH_OFF_WIDTHS / push_speed * 1.5, 0.5)
		ship_segments.append({kind = "slide", t0 = t, t1 = t + push_s, from_pose = end_pose, to_pose = moored, length = length, ends_from = ends_in.duplicate(), ends_to = to_in, lead = leading})
		for i in team.size():
			tug_segments[i].append({kind = "attached", t0 = t, t1 = t + push_s, x = pushes[p][1][i], out = out, stand = stand, angle = float(moored[1])})
		t += push_s
		# Backing off it, square to it however it lies.
		var lying := _work_pose(work, ship_segments, t)
		var ship_at: Vector2 = lying[0]
		var along_ship := Vector2.from_angle(float(lying[1]))
		var out_now := out.rotated(angle_difference(float(moored[1]), float(lying[1])))
		var back_s := back_by / back_speed * 1.4
		for i in team.size():
			var at: Vector2 = ship_at + along_ship * float(pushes[p][1][i]) + out_now * stand
			tug_segments[i].append({kind = "reverse", t0 = t, t1 = t + back_s, from = at, to = at + out_now * back_by, angle = (-out_now).angle()})
		ship_segments.append({kind = "hold", t0 = t, t1 = t + back_s, pose = lying})
		t += back_s
		if p + 1 < pushes.size():
			# A lone tug: forward and round along the ship to its next station (the
			# stern half), turning in there.
			var along := along_ship * signf(float(pushes[p + 1][1][0]) - float(pushes[p][1][0]))
			var backed: Vector2 = (tug_segments[0][-1] as Dictionary).to
			var next_x: float = pushes[p + 1][1][0]
			var way := [[backed, (-out_now).angle()], [backed - out_now * radius + along * radius, along.angle()]]
			var run := ship_at + along_ship * next_x - along * radius + out_now * (stand + radius)
			if (run - (way[1][0] as Vector2)).dot(along) > tug_length * 0.5:
				way.append([run, along.angle()])
			way.append([ship_at + along_ship * next_x + out_now * stand, (-out_now).angle()])
			var round_path := _pose_path(way)
			var round_times := _path_times(round_path, harbour_speed, tug_length, tug_length, true, true)
			tug_segments[0].append({kind = "path", t0 = t, t1 = t + round_times[-1], points = round_path, times = round_times, start = (-out_now).angle(), end = (-out_now).angle()})
			ship_segments.append({kind = "hold", t0 = t, t1 = t + round_times[-1], pose = lying})
			t += round_times[-1]
		ends_in = to_in
		gone = share
	work.total = t
	# Letting go: backed off, they turn away (towards the harbour mouth) and go.
	var away := forward if ((mouth[0] as Vector2) - middle).dot(forward) >= 0.0 else -forward
	for i in team.size():
		var backed: Vector2 = (tug_segments[i][-1] as Dictionary).to
		work.finish.append([[backed, (-out).angle()], [backed - out * radius + away * radius, away.angle()]])
	return work


## A tug's point pulling a ship in (see "follow" in _work_pose()), `d` along
## the ship's way in (a path of `length`, straight on past its end), out to its
## side as far as it's peeling off by then.
static func _follow_point(points: PackedVector2Array, length: float, pulled: Dictionary, segment: Dictionary, d: float) -> Vector2:
	var pose: Array
	if d <= length and length > 0.0:
		pose = _along_path(points, d / length, float(pulled.start), float(pulled.end))
	else:
		var last := _along_path(points, 1.0, float(pulled.start), float(pulled.end))
		pose = [(last[0] as Vector2) + Vector2.from_angle(float(last[1])) * (d - length), last[1]]
	var cap := length + float(segment.past)
	var begin := maxf(cap - float(segment.swing) * 3.0, float(segment.ahead))
	var peel := smoothstep(begin, maxf(cap - float(segment.swing) * 0.5, begin + float(segment.swing)), d)
	var side := lerpf(float(segment.side), float(segment.side_to), peel)
	return (pose[0] as Vector2) + Vector2.from_angle(float(pose[1]) + PI / 2.0) * side


## The segment of a tug's (or the ship's) work going on at a time (the last
## once it's all done).
static func _work_segment(segments: Array, t: float) -> Dictionary:
	for segment: Dictionary in segments:
		if t < float(segment.t1):
			return segment
	return segments[-1]


## Where the ship or a tug (its segments) is at a time in its team's work,
## in dock units: [point, angle].
func _work_pose(work: Dictionary, segments: Array, t: float) -> Array:
	var segment := _work_segment(segments, t)
	var span := float(segment.t1) - float(segment.t0)
	var u := clampf((t - float(segment.t0)) / span, 0.0, 1.0) if span > 0.0 else 1.0
	match str(segment.kind):
		"path":
			var points: PackedVector2Array = segment.points
			return _along_path(points, _timed_share(points, segment.times, u), float(segment.start), float(segment.end))
		"hold":
			return segment.pose
		"slide":
			# Pushed in: its bow and stern each from how far in they were to how far
			# in they'll be (shares of the way from from_pose to to_pose), the end
			# that `lead`s (1 the bow, -1 the stern) coming first, so it slants.
			var timing := func(end: float) -> float:
				var first := float(segment.lead) * end > 0.0
				var last := float(segment.lead) * end < 0.0
				return smoothstep(LONE_PUSH_LEAD if last else 0.0, 1.0 - LONE_PUSH_LEAD if first else 1.0, u)
			var from_pose: Array = segment.from_pose
			var way: Vector2 = (segment.to_pose[0] as Vector2) - (from_pose[0] as Vector2)
			var half := Vector2.from_angle(float(from_pose[1])) * float(segment.length) / 2.0
			var bow: Vector2 = (from_pose[0] as Vector2) + half + way * lerpf(segment.ends_from[0], segment.ends_to[0], timing.call(1.0))
			var stern: Vector2 = (from_pose[0] as Vector2) - half + way * lerpf(segment.ends_from[1], segment.ends_to[1], timing.call(-1.0))
			return [(bow + stern) / 2.0, (bow - stern).angle()]
		"reverse":
			return [(segment.from as Vector2).lerp(segment.to, smoothstep(0.0, 1.0, u)), float(segment.angle)]
		"follow":
			# On its line ahead of the ship, along the way the ship's being pulled
			# (and straight on past its end); as it comes up to where it's going,
			# easing to a stop out to its side (`past` along from where the ship
			# stops, `side_to` out), so the ship glides on past it. It faces the way
			# its own track goes, so it swerves out the way a boat does.
			var pulled: Dictionary = work.ship[0]
			var points: PackedVector2Array = pulled.points
			var length := _path_length(points)
			var ship_u := clampf((t - float(pulled.t0)) / maxf(float(pulled.t1) - float(pulled.t0), 0.001), 0.0, 1.0)
			var raw := _timed_share(points, pulled.times, ship_u) * length + float(segment.ahead)
			var cap := length + float(segment.past)
			var soft := float(segment.swing) * 0.4
			var over := (cap - raw) / soft
			var d := raw if over > 30.0 else cap - soft * log(1.0 + exp(over))
			var at := _follow_point(points, length, pulled, segment, d)
			var next := _follow_point(points, length, pulled, segment, d + 0.05)
			return [at, (next - at).angle()]
		"attached":
			# Its bow on the hull at its station, pushing: going with the ship.
			# (Square to the hull however it's slanting.)
			var at := _work_pose(work, work.ship, t)
			var outward: Vector2 = (segment.out as Vector2).rotated(angle_difference(float(segment.angle), float(at[1])))
			return [(at[0] as Vector2) + Vector2.from_angle(float(at[1])) * float(segment.x) + outward * float(segment.stand), (-outward).angle()]
	return [Vector2.ZERO, 0.0]


## Where a tug working its ship in at port is drawn, [screen point, angle]
## (at the port, when its marina isn't shown).
func _tug_work_pose(tug: Ship) -> Array:
	if not docks_shown():
		return [port_screen_position(tug.tow_port), 0.0]
	var work := _tug_work(tug)
	if work.is_empty():
		return []
	var index: int = (work.team as Array).find(tug)
	return _local_to_screen(tug.tow_port, _work_pose(work, work.tugs[index], minf(_work_time(tug), float(work.total))))


## Where a ship tugs are working in at port is drawn, [screen point, angle],
## or [] if none are.
func _worked_pose(ship: Ship) -> Array:
	var lead := _assist_lead(ship)
	if lead == null:
		return []
	var work := _tug_work(lead)
	if work.is_empty():
		return []
	return _local_to_screen(ship.docked_at, _work_pose(work, work.ship, minf(_work_time(lead), float(work.total))))


## How long (s of play) a team of tugs takes to work its ship in (see
## _tug_work()), for GameState: coming alongside (less its slide, which
## GameState adds), or to its spot at the anchorage.
func _tug_work_seconds(ship: Ship) -> float:
	var lead := _assist_lead(ship)
	if lead == null:
		return 0.0
	var work := _tug_work(lead)
	return float(work.get("total", 0.0))


## GameState.anchor_route: how long tugs stay with a ship that has to wait at
## the anchorage (s of play): none, they cast off at the harbour mouth.
func anchor_tow_seconds(ship: Ship) -> float:
	_refresh_spots()
	if _assist_lead(ship) == null or _tug_work(_assist_lead(ship)).is_empty():
		return GameState.TUG_ANCHOR_S
	return _tug_work_seconds(ship)  # (They cast off at the mouth: see _tug_work().)


# --- Tugs towing at sea -------------------------------------------------------

## The way a tow goes on screen, round where its ship is: the lane it's towed
## along (bent as drawn), the curve into its port's harbour (as a ship
## arriving sails it, see _harbour_pose()) and on in through the mouth: points
## a step apart from `back` px behind the ship to `ahead` px in front, with the
## way the tow goes at each, and how far along them the ship is. The tug that
## leads it (`lead`) says where: its tow (out at the lost ship, turning to take
## it in tow, the start of the leg it'll tow it along). [points, angles,
## distances along, the ship's distance], or [] off the map. Each tug, the
## ship and its tow lines are placed along this, so they all go the way they
## face, round every bend (none of them crabs sideways).
func _tow_track(lead: Ship, back: float, ahead: float) -> Array:
	var tow: Array = [lead.from_port, lead.to_port, lead.traveled_nm] if lead.job_phase == Ship.JOB_TOW else lead.job_segments[0]
	var from_port: String = tow[0]
	var to_port: String = tow[1]
	var lane = GameData.lane(from_port, to_port)
	if lane == null:
		return []
	var length: float = lane.length()
	var mile := float(tow[2])
	var px_per_nm := _zoom / 60.0
	# The curve into the harbour, worked out once a frame.
	var frame := Engine.get_process_frames()
	var kept: Array = _tow_curves.get(lead, [])
	if kept.is_empty() or kept[0] != frame:
		var harbour := _keep_right(to_port, _entrance_pose(to_port, false, true))
		var reach := 0.0
		var curve := []
		if docks_shown() and not _is_hidden(port_screen_position(to_port)):
			reach = minf(float(_lane_reaches(lane, length, to_port, "", [harbour, []])[0][0]), length)
			if reach > 0.0:
				curve = _lane_curve(lane, from_port, to_port, length, true, reach, harbour)
		kept = [frame, reach, curve, harbour]
		_tow_curves[lead] = kept
	var reach: float = kept[1]
	var curve: Array = kept[2]
	var harbour: Array = kept[3]
	var points := PackedVector2Array()
	var angles := PackedFloat32Array()
	var along := PackedFloat32Array()
	var step := maxf((back + ahead) / px_per_nm / 24.0, 0.0005)
	var m := mile - back / px_per_nm
	while m <= mile + ahead / px_per_nm + step:
		var pose: Array
		if m > length and not curve.is_empty():
			pose = [(harbour[0] as Vector2) + Vector2.from_angle(float(harbour[1])) * (m - length) * px_per_nm, harbour[1]]
		elif not curve.is_empty() and length - m < reach:
			pose = _follow(curve[1], curve[2], curve[0], 1.0 - (length - m) / reach)
		else:
			var sample: Array = _bent_sample(lane, from_port, to_port, clampf(m, 0.0, length))
			pose = [world_to_screen(sample[0]), _heading_angle(sample[1], sample[0])]
		if _is_hidden(pose[0]):
			return []
		along.append(0.0 if points.is_empty() else along[-1] + points[-1].distance_to(pose[0]))
		points.append(pose[0])
		angles.append(float(pose[1]))
		m += step
	# The ship: as far along the samples as its mile is.
	var k := (mile - (mile - back / px_per_nm)) / step
	var i := clampi(floori(k), 0, points.size() - 2)
	return [points, angles, along, lerpf(along[i], along[i + 1], clampf(k - i, 0.0, 1.0))]


## The pose [screen point, angle] a distance (px; negative: behind) along a
## tow's track (_tow_track()) from its ship.
static func _on_track(track: Array, distance: float) -> Array:
	var points: PackedVector2Array = track[0]
	var angles: PackedFloat32Array = track[1]
	var along: PackedFloat32Array = track[2]
	var d := clampf(float(track[3]) + distance, 0.0, along[-1])
	var i := clampi(along.bsearch(d), 1, points.size() - 1)
	var span := along[i] - along[i - 1]
	var t := (d - along[i - 1]) / span if span > 0.0 else 1.0
	return [points[i - 1].lerp(points[i], t), lerp_angle(angles[i - 1], angles[i], t)]


## How far ahead of its ship's middle (px) a tug on its tow pulls: past the
## bow, its tow line and half itself.
func _tow_ahead(tug: Ship) -> float:
	var ship_rect: Rect2 = _model_look(tug.rescuing.model_id)[7]
	var tug_rect: Rect2 = _model_look(tug.model_id)[7]
	return (ship_rect.size.x / 2.0 + tug_rect.size.x * (TOW_LINE_TUGS + 0.5)) * _ship_scale()


## Where a tug pulls its ship from on a tow (and turns round to take it in
## tow), [screen point, angle]: ahead of its bow on its tow line, along the
## way the tow goes; two side by side in a tight Y (the lead on the right),
## their lines from the bow the same length. [] off the map.
func _tow_place(tug: Ship) -> Array:
	var team := tug.tug_team()
	if team.is_empty():
		return []
	var ahead := _tow_ahead(tug)
	var track := _tow_track(team[0], ahead, ahead * 1.2)
	if track.is_empty():
		return []
	var place := _on_track(track, ahead)
	if team.size() > 1:
		var side := 1.0 if tug == team[0] else -1.0
		var width := (_model_look(tug.model_id)[7] as Rect2).size.y * TOW_Y_WIDTHS * _ship_scale()
		place[0] = (place[0] as Vector2) + Vector2.from_angle(float(place[1]) + PI / 2.0) * width * side
	return place


## Where a ship being towed in at sea is, [screen point, angle]: on its tow's
## track, coming round from the way it lay to the way it's towed over the
## first TOW_SWING_NM. [] off the map.
func _towed_pose(ship: Ship) -> Array:
	var lead := ship.rescuer
	var track := _tow_track(lead, 1.0, 1.0)
	if track.is_empty():
		return []
	var pose := _on_track(track, 0.0)
	var start := float(lead.job_segments[0][2]) if not lead.job_segments.is_empty() else lead.traveled_nm
	var swing := smoothstep(0.0, TOW_SWING_NM, lead.traveled_nm - start)
	var own := _ship_bent(ship)  # (Where it lay, the way it lay: its own leg.)
	if swing < 1.0 and not own.is_empty():
		pose[1] = lerp_angle(_heading_angle(own[1], own[0]), float(pose[1]), swing)
	return pose


## Where a tug heading out to a lost ship is drawn on its lane: as it sails,
## but stopping short of the ship, ahead of its bow, so it turns round there
## (see _turning_pose()) rather than over it. [] if it isn't near yet.
func _tug_out_pose(tug: Ship) -> Array:
	if not tug.job_phase in [Ship.JOB_APPROACH, Ship.JOB_ALIGN] or tug.is_docked() or tug.rescuing == null:
		return []
	var short := _tow_ahead(tug) / (_zoom / 60.0)
	if tug.traveled_nm < tug.segment_end - short:
		return []
	# Where it'd be drawn sailing there (on its way out of the harbour, if it's still that near).
	var sailed := tug.traveled_nm
	tug.traveled_nm = maxf(tug.segment_end - short, 0.0)
	var pose := _harbour_pose(tug)
	if pose.is_empty():
		var here := _ship_bent(tug)
		pose = [world_to_screen(here[0]), _heading_angle(here[1], here[0])] if not here.is_empty() else []
	tug.traveled_nm = sailed
	return pose


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
	_look_at(GameData.port_position(ship.docked_at) if ship.is_docked() else _ship_world(ship))
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


## Zooms in (factor above 1) or out about a point on screen (the middle by
## default), easing there like the wheel.
func zoom_by(factor: float, about := Vector2(-1.0, -1.0)) -> void:
	if factor <= 0.0:
		return
	_zoom_goal = clampf(_zoom_goal * factor, _min_zoom(), MAX_ZOOM)
	_zoom_about = about if about.x >= 0.0 else size / 2.0
	_fling = Vector2.ZERO


## The + and - keys zoom about the middle (for trackpads without gestures).
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_pressed():
		return
	var key := event as InputEventKey
	if key == null or key.ctrl_pressed or key.meta_pressed or key.alt_pressed:
		return
	match key.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			zoom_by(ZOOM_STEP * ZOOM_STEP)
			get_viewport().set_input_as_handled()
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_by(1.0 / (ZOOM_STEP * ZOOM_STEP))
			get_viewport().set_input_as_handled()


## Drag to turn the globe (the map follows the mouse; let go while moving and
## it keeps turning, slowing to a stop), wheel to zoom in and out about the
## mouse (easing there: see _process()). On a trackpad, pinch to zoom about
## the fingers, or swipe two fingers up and down to zoom like the wheel.
func _gui_input(event: InputEvent) -> void:
	var pinch := event as InputEventMagnifyGesture
	if pinch:
		zoom_by(pinch.factor, pinch.position)
		accept_event()
		return
	var swipe := event as InputEventPanGesture
	if swipe:
		zoom_by(pow(ZOOM_STEP, -swipe.delta.y * SWIPE_ZOOM_RATE), swipe.position)
		accept_event()
		return
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
	var marina_port := ""  # The marina the click's on (the nearest middle), if any.
	var marina_dist := INF
	for port: Dictionary in GameData.ports:
		if _port_locked(port.id):
			continue
		var dist := port_screen_position(port.id).distance_to(screen_pos)
		if dist <= PORT_HIT_RADIUS and dist < nearest_dist:
			nearest_dist = dist
			nearest_port = port.id
		elif dist < marina_dist and _marina_shown(port.id) and dist <= float(_port_layout(port.id).radius) * MARINA_HIT_RADII * _ship_scale():
			marina_dist = dist
			marina_port = port.id
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
	elif show_ships and not _birds_at(screen_pos, 1.0 if marina_port.is_empty() else MARINA_BIRD_REACH).is_empty():
		# (Over a marina, only right on a bird: its gulls are always there.)
		var birds := _birds_at(screen_pos, 1.0 if marina_port.is_empty() else MARINA_BIRD_REACH)
		birds_clicked.emit(birds[0], birds[1])
	elif not _animals_at(screen_pos).is_empty():
		var group := _animals_at(screen_pos)
		animals_clicked.emit(group[0], group[1])
	elif not _industry_at(screen_pos).is_empty():
		var plot := _industry_at(screen_pos)
		industry_clicked.emit(plot[0], plot[1])
	elif not marina_port.is_empty():
		port_clicked.emit(marina_port)  # Anywhere on its marina.
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
	if not gray_mode:
		_land_mask.render_target_update_mode = SubViewport.UPDATE_ONCE  # (Only the view changes it: drawn again only then.)
	_port_turns.clear()
	_near_ports_valid = false
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


## True if a port's region is locked (it can't be clicked, and its name is
## dimmed; its marina shows like any other).
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


## Has every layer drawn again (the view's moved, say): in this frame's
## _process(), so a layer queued again there (the ships, the weather...) still
## draws once a frame. Asked for straight away, from input, a layer would draw
## twice in a frame while the map's dragged.
func _redraw_layers() -> void:
	_layers_stale = true


func _flush_layers() -> void:
	_layers_stale = false
	_update_marinas()
	_decor_layer.queue_redraw()
	_fauna_layer.queue_redraw()
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
	for row in ceili(size.y / GUST_CELL_PX):
		for col in ceili(size.x / GUST_CELL_PX):
			var cycle := t / GUST_CYCLE_S + _gust_offset(col, row)
			var spot := _gust_spot(col, row, floori(cycle))
			var at := Vector2(col + spot.x, row + spot.y) * GUST_CELL_PX
			if at.distance_to(middle) > reach:
				continue
			var lon_lat := _screen_lon_lat(at)
			var wind := Wind.at(lon_lat, t, storms)
			var strength := wind.length()
			if spot.z > smoothstep(GUST_STRENGTH.x, GUST_STRENGTH.y, strength):
				continue
			var way := _screen_way(Geo.project(lon_lat), wind / strength).normalized()
			var u := fposmod(cycle, 1.0)
			var length := lerpf(GUST_LENGTH_PX.x, GUST_LENGTH_PX.y, clampf(strength / 1.5, 0.0, 1.0))
			var head := at + way * length * u * 1.5
			var alpha := sin(PI * u) * clampf(strength, 0.0, 1.2) * GUST_ALPHA
			_canvas.draw_polyline_colors(PackedVector2Array([head - way * length, head - way * length * 0.4, head]),
				PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, alpha * 0.6), Color(1, 1, 1, alpha)]), 1.5, true)


## A gust cell's steady offset into the gust cycle (0..1), worked out once.
func _gust_offset(col: int, row: int) -> float:
	var cell := Vector2i(col, row)
	if not _gust_offsets.has(cell):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([col, row])
		_gust_offsets[cell] = rng.randf()
	return _gust_offsets[cell]


## Where in its cell (x, y: 0..1) a gust cell's gust is in a cycle, and the roll
## (z) against its chance of blowing; kept till its next cycle.
func _gust_spot(col: int, row: int, cycle: int) -> Vector3:
	var cell := Vector2i(col, row)
	var kept: Array = _gust_spots.get(cell, [])
	if kept.is_empty() or kept[0] != cycle:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([col, row, cycle])
		var x := rng.randf()
		var y := rng.randf()
		kept = [cycle, Vector3(x, y, rng.randf())]
		_gust_spots[cell] = kept
	return kept[1]


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
## How far (nm) past its swing a ship dropping anchor keeps off a drawn lane
## (see _anchors_in_lanes()).
const ANCHOR_LANE_MARGIN_NM := 1.5
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
## A ship weighing anchor (or coming to anchor, or leaving its moorings on the
## jetty) comes round on a turning circle this many of its own lengths across
## rather than swinging round on the spot, unless it faces within
## TURN_FREE_ANGLE of the way it's going (see _loosen()).
const ANCHOR_TURN_LENGTHS := 0.8
const TURN_FREE_ANGLE := 0.4
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
## HQ buildings (_draw_hq_building()): how many levels, one more every this
## many company levels, and how far (dock units) they stand back from the quay's edges.
const HQ_LEVELS := 10
const HQ_LEVEL_EVERY := 10
const HQ_MARGIN := 0.6
## Canal ports (_is_canal_port()): the berthless side the canal comes in by
## (dock units), the cut through the quay (as wide), and how far along its canal
## (degrees) to look for where it leaves.
const CANAL_SIDE := 5.0
const CANAL_CUT_WIDTH := 3.0
const CANAL_EXIT_DEG := 0.25
## Ships keep to the right-hand side of a harbour entrance, this many widths
## (of the widest ship the marina takes) off its middle.
const KEEP_RIGHT_WIDTHS := 0.6
## A ship backing out of a berth it lies bow in to (a hub's slip) goes this
## share of its speed, then turns round in this long (s of play) on its
## thrusters before heading out (see _unberth_plan()).
const UNBERTH_REVERSE_SPEED := 0.5
const UNBERTH_TURN_S := 2.5
## Driving off a berth, a ship is clear of the quay this many of its lengths
## ahead, this many of its widths out from it, heading away from it at this
## slope (see _peel_pose()).
const PEEL_AHEAD := 0.9
const PEEL_OUT_WIDTHS := 1.6
const PEEL_ANGLE := 0.45
## Birds show once a gull's wings would be this many px across (and never draw
## smaller), and a click this near one picks its flock.
const BIRD_MIN_PX := 5.0
const BIRD_HIT_MIN_PX := 6.0
## Birds are drawn this many times their span (in dock units), to read clearly.
const BIRD_SCALE := 1.4
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
## Birds drawn this frame, for clicks: [screen point, reach, what they're round, flock] (see _draw_birds()).
var _bird_hits: Array = []
## Flock key -> each bird's steady numbers (see _bird_traits()).
var _bird_trait_cache := {}
## [marina radius, slip] -> where an HQ building may stand (see _hq_region()).
var _hq_regions := {}
## Each port's marina's canvas item (see _update_marinas()), and the port
## whose marina is being drawn into its item (its dock points come out in dock
## units, unturned; see _dock_point()), or "".
var _marina_items := {}
## True once the view's changed this frame and the layers are to draw again
## (see _redraw_layers()).
var _layers_stale := false
var _recording_marina := ""
## Canal ports: port id -> which way its canal leaves (screen, north up), and
## -> [its layout's canal angle, the turn that lines it up] (see _canal_turn()).
var _canal_exits := {}
var _canal_turns := {}
## Port id -> the way into the wind there on screen, worked out once a frame.
var _upwind := {}
## Port id -> the strongest storm's strength there, this frame (see _storm_strength_at_port()).
var _port_storms := {}
## Each docked ship's screen pose this frame, and the frame (see _docked_pose()).
var _poses := {}
var _poses_frame := -1
## Ship -> [port, anchorage, slot, marina radius, its anchor on the unit sphere] (see _anchor_screen_cached()).
var _anchor_units := {}
## Port id and anchorage -> [the drawn lanes and anchor points it was worked
## out for, 1 for each anchor point a drawn lane passes within its ship's
## swing of] (see _anchors_in_lanes()).
var _anchor_lanes := {}
## Each lead tug's tow's curve into its harbour this frame (see _tow_track()).
var _tow_curves := {}
## Each lead tug's team's work bringing its ship in at port, and what it was
## worked out for (see _tug_work()); each tug's way off when it lets go
## ([port, dock-unit poses]); and a tug that's let go gliding off from there
## ([when it docked, those poses]; see _lying_pose()).
var _tug_works := {}
var _tug_finish := {}
var _glide_from := {}
## Model id -> the anchorage its ships lie in (see _anchor_pool()).
var _anchor_pools := {}
## Port id -> _marina_shown() this frame, and the frame.
var _marinas_shown := {}
var _marinas_shown_frame := -1
var _upwind_frame := -1


func docks_shown() -> bool:
	return show_ships and not gray_mode


## Which way the sea is from a port on screen (north up), turned at a canal
## port so its canal side faces where its canal leaves (see _canal_turn()).
func _port_sea_angle(port_id: String) -> float:
	return _port_bearing_angle(port_id) + _canal_turn(port_id)


## True for a port a canal runs through (data/canals.json ports: Port Said
## and Port Tewfik on the Suez Canal, Colon and Balboa on the Panama Canal):
## its marina has a canal side, with no berth, where the canal comes into its
## basin through a cut in the quay (at a hub, its slip leads on into the canal).
static func _is_canal_port(port_id: String) -> bool:
	return not _canal_of(port_id).is_empty()


static func _canal_of(port_id: String) -> Dictionary:
	for canal: Dictionary in GameData.canals:
		if (canal.get("ports", []) as Array).has(port_id):
			return canal
	return {}


## Which way (on screen, north up) a canal port's canal leaves it inland:
## along its path to the first point CANAL_EXIT_DEG away, whichever way is
## furthest from the sea.
func _canal_exit_angle(port_id: String) -> float:
	if _canal_exits.has(port_id):
		return _canal_exits[port_id]
	var canal := _canal_of(port_id)
	var port := GameData.get_port(port_id)
	var at := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	var squash := cos(deg_to_rad(at.y))
	var screen := func(point: Array) -> Vector2: return Vector2((float(point[0]) - at.x) * squash, -(float(point[1]) - at.y))
	var path: Array = canal.get("path", [])
	var nearest := 0
	for i in path.size():
		if (screen.call(path[i]) as Vector2).length() < (screen.call(path[nearest]) as Vector2).length():
			nearest = i
	var sea := Vector2.from_angle(_port_bearing_angle(port_id))
	var best := Vector2.ZERO
	for step: int in [1, -1]:
		var i := nearest
		while i + step >= 0 and i + step < path.size() and (screen.call(path[i]) as Vector2).length() < CANAL_EXIT_DEG:
			i += step
		var way: Vector2 = screen.call(path[i])
		if way.length() > 0.0 and (best == Vector2.ZERO or way.normalized().dot(sea) < best.normalized().dot(sea)):
			best = way
	_canal_exits[port_id] = best.angle() if best != Vector2.ZERO else _port_bearing_angle(port_id) + PI
	return _canal_exits[port_id]


## How far a canal port's marina is turned from its facing so its canal side
## (or a hub's slip) points where its canal leaves (0 for other ports).
func _canal_turn(port_id: String) -> float:
	if not _is_canal_port(port_id):
		return 0.0
	var layout := _port_layout(port_id)
	var cached: Array = _canal_turns.get(port_id, [])
	if cached.is_empty() or cached[0] != layout.get("canal_angle", PI):
		var flip := float(_dock_flips.get(port_id, 1.0))
		var turn := wrapf(_canal_exit_angle(port_id) - _port_bearing_angle(port_id) - flip * float(layout.get("canal_angle", PI)), -PI, PI)
		cached = [layout.get("canal_angle", PI), turn]
		_canal_turns[port_id] = cached
	return float(cached[1])


## A canal port's cut through its quay (dock units): water from its basin (or
## a hub's slip end) out past the square quay's edge where the canal goes on,
## lined with quay edges. [] for other marinas.
static func _canal_cut(layout: Dictionary) -> PackedVector2Array:
	if not layout.has("canal"):
		return PackedVector2Array()
	var side: Array = layout.canal
	var from: Vector2
	var way: Vector2
	var reach: float
	if side.is_empty():  # A hub: on from the slip's inland end.
		var slip: Array = layout.slip
		from = (slip[0] as Vector2) - Vector2(float(slip[1]) - 0.5, 0.0)
		way = Vector2.LEFT
		reach = absf(_quay_inland(layout) - from.x) + 1.0
	else:
		var middle: Vector2 = ((side[0] as Vector2) + (side[1] as Vector2)) / 2.0
		way = middle.normalized()
		from = middle - way * 0.5
		reach = (float(layout.radius) + JETTY_WIDTH) * 1.5
	return _rect(from, from + way * reach, CANAL_CUT_WIDTH / 2.0)


## Which way the sea is from a port, as an on-screen angle with north straight
## up (the globe turns it: _port_turn()), and which side is its marina's +y:
## from data/port_facing.json, or else the average way its sea lanes head out
## of it.
func _port_bearing_angle(port_id: String) -> float:
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
func _marina_layout(kinds: String, hub: bool, canal := false) -> Dictionary:
	var key := [kinds, hub, canal]
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
	# A canal port (see _is_canal_port()): a side in the middle of the land half
	# with no berth, where the canal comes in (at a hub, its slip leads to it).
	if canal and not hub:
		polygon.insert(polygon.size() / 2, ["canal", []])
	var count := polygon.size()
	var spread := 1.0 / tan((PI - PI / count) / 2.0)  # A corner's room per width (see above).
	var sides := PackedFloat32Array()
	var length := 0.0
	var width := 0.0
	for j in count:
		if polygon[j][0] == "canal":
			sides.append(CANAL_SIDE)
			continue
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
	var canal_side := []  # [corner, corner] of a canal port's canal side.
	for j in count:
		var a := corners[j]
		var b := corners[j + 1]
		var along := (b - a).normalized()
		var middle := (a + b) / 2.0
		var inward := -middle.normalized()
		var berths: Array = polygon[j][1]
		if polygon[j][0] == "canal":
			canal_side = [a, b]
			continue
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
	if canal:
		# Where the canal comes in: its side, or a hub's slip (straight inland).
		layout.canal = canal_side
		layout.canal_angle = ((canal_side[0] + canal_side[1]) / 2.0).angle() if not canal_side.is_empty() else PI
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
		_port_layouts[port_id] = _marina_layout(GameState.docks.berth_kinds(port_id), GameState.docks.has_hub(port_id), _is_canal_port(port_id))
	return _port_layouts[port_id]


## A point of a port's marina (dock units) on screen.
func _dock_point(port_id: String, local: Vector2) -> Vector2:
	if port_id == _recording_marina:
		return Vector2(local.x, local.y * float(_dock_flips.get(port_id, 1.0))) * dock_scale(port_id)  # (Into its own item: see _record_marina().)
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


## Every port's marina in view (see the section's description). Each is drawn
## once into its own canvas item (_marina_items), in dock units at the zoom
## it's drawn at, and then only moved and turned with the view: dragging the
## map doesn't draw them again, only zooming (so lines keep their width in px),
## a port changing size or becoming a hub, or its HQ building growing.
func _update_marinas() -> void:
	var shown := {}
	if show_ships and docks_shown():
		var view := Rect2(Vector2.ZERO, size)
		var near := view.grow(MARINA_MAX_REACH * _ship_scale())
		for i in _ports_near_view():
			var port_id: String = GameData.ports[i].id
			var root := port_screen_position(port_id)
			if not near.has_point(root) or not _marina_shown(port_id):
				continue  # (Cheapest first: most ports are well off screen.)
			var layout := _port_layout(port_id)
			var reach := (float(layout.radius) * 1.5 + float(layout.slip[1] if not layout.slip.is_empty() else 0.0)) * _ship_scale()  # (The quay's square corners.)
			if not view.grow(reach).has_point(root):
				continue
			shown[port_id] = true
			var item := _marina_item(port_id, i)
			var key := [_ship_scale(), _dock_flips.get(port_id, 1.0), _hq_look(port_id)]
			if not is_same(item.get_meta(&"layout"), layout) or item.get_meta(&"key") != key:
				item.set_meta(&"layout", layout)
				item.set_meta(&"key", key)
				item.queue_redraw()
			item.position = root
			item.rotation = _port_sea_angle(port_id) + _port_turn(port_id)
			item.visible = true
	for port_id: String in _marina_items:
		if not shown.has(port_id):
			(_marina_items[port_id] as Control).visible = false


## A port's marina's canvas item (see _update_marinas()), made the first time,
## among the others in the ports' order (so where two overlap, the same one's on top).
func _marina_item(port_id: String, order: int) -> Control:
	if _marina_items.has(port_id):
		return _marina_items[port_id]
	var item := Control.new()
	item.mouse_filter = MOUSE_FILTER_IGNORE
	item.set_meta(&"order", order)
	item.set_meta(&"layout", {})
	item.set_meta(&"key", [])
	item.draw.connect(_record_marina.bind(port_id, item))
	var at := 0
	for child in _dock_layer.get_children():
		if int(child.get_meta(&"order", -1)) < order:
			at += 1
	_dock_layer.add_child(item)
	_dock_layer.move_child(item, at)
	_marina_items[port_id] = item
	return item


## Draws a port's marina into its canvas item, in dock units (mirrored with its
## layout) at the zoom now, unturned: the item turns and moves it into place.
func _record_marina(port_id: String, item: Control) -> void:
	var canvas := _canvas
	_canvas = item
	_recording_marina = port_id
	_draw_marina(port_id, _port_layout(port_id))
	_recording_marina = ""
	_canvas = canvas


## What a port's HQ building and industry look like ([] for none): its HQ
## owner's name, color and HQ level, and its industry hub's buildings and open
## plots (see _industry_hub()).
func _hq_look(port_id: String) -> Array:
	var look := []
	for each in GameState.all_companies():
		var hub := each.hub_at(port_id)
		if hub != null and hub.is_hq:
			look = [each.name, each.color, hq_level(each)]
			break
	var industry := _industry_hub(port_id)
	if industry != null:
		look.append_array([industry.industries.duplicate(), industry.industry_slots(), industry == GameState.hub_at(port_id)])
	return look


# --- Industry -------------------------------------------------------------------

## The hub whose industry a port's marina shows: this player's there if they
## have one, else the first company's with any buildings; or null.
static func _industry_hub(port_id: String) -> Hub:
	var mine := GameState.hub_at(port_id)
	if mine != null:
		return mine
	for each in GameState.all_companies():
		var hub := each.hub_at(port_id)
		if hub != null and hub.industries.any(func(id: String) -> bool: return not id.is_empty()):
			return hub
	return null


## Where a hub's industry buildings stand (dock units): Hub.INDUSTRY_SLOTS
## plots on the quay corner the other side of its slip from the HQ's (see
## _hq_region()), equal squares as big as all of them fit. [Rect2...], or []
## for a marina without a slip.
func _industry_plots(layout: Dictionary) -> Array:
	var key := [layout.radius, layout.slip, "industry"]
	if _hq_regions.has(key):
		return _hq_regions[key]
	var plots := []
	var slip: Array = layout.slip
	if not slip.is_empty():
		var clear := float(layout.radius) + JETTY_WIDTH / 2.0
		var high := (slip[0] as Vector2).y - float(slip[2]) / 2.0 - QUAY_WIDTH - HQ_MARGIN
		var inland := _quay_inland(layout) + HQ_MARGIN
		var corner := PackedVector2Array([Vector2(inland, high), Vector2(-HQ_MARGIN, high), Vector2(-HQ_MARGIN, -clear + HQ_MARGIN), Vector2(inland, -clear + HQ_MARGIN)])
		var basin := _arc(float(layout.inner) + QUAY_WIDTH + HQ_MARGIN, 0.0, TAU).slice(0, -1)
		var region := PackedVector2Array()
		for piece in Geometry2D.clip_polygons(corner, basin):
			if absf(_area(piece)) > absf(_area(region)):
				region = piece
		if region.size() >= 3:
			# The biggest squares, all the same, that fit Hub.INDUSTRY_SLOTS of on the
			# quay without touching: tried from as big as could be down, each placed
			# as far inland and from the slip as it'll go (so they line up).
			var area := _bounds(region)
			var side := minf(maxf(area.size.x, area.size.y) / Hub.INDUSTRY_SLOTS, minf(area.size.x, area.size.y)) * 0.95
			var gap := HQ_MARGIN * 0.6
			var fits := func(square: Rect2) -> bool:
				return Array(_rect_points(square)).all(func(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, region))
			while side > 0.5 and plots.size() < Hub.INDUSTRY_SLOTS:
				plots.clear()
				var step := side * 0.2
				var y := area.position.y
				while y + side <= area.end.y + 0.001 and plots.size() < Hub.INDUSTRY_SLOTS:
					var x := area.position.x
					while x + side <= area.end.x + 0.001 and plots.size() < Hub.INDUSTRY_SLOTS:
						var square := Rect2(Vector2(x, y), Vector2.ONE * side)
						if fits.call(square) and plots.all(func(other: Rect2) -> bool: return not other.grow(gap).intersects(square)):
							plots.append(square)
							x += side + gap
						else:
							x += step
					y += step
				side *= 0.92
			if plots.size() < Hub.INDUSTRY_SLOTS:
				plots.clear()
	_hq_regions[key] = plots
	return plots


## A hub's industry on its marina's quay (see _industry_plots()): each
## building's art on its plot with its shadow; an open plot with nothing on it
## yet marked out (dashed, for this player's own hub), a closed one bare.
func _draw_industry(port_id: String, layout: Dictionary) -> void:
	var hub := _industry_hub(port_id)
	if hub == null:
		return
	var plots := _industry_plots(layout)
	var mine := hub == GameState.hub_at(port_id)
	var scale := dock_scale(port_id)
	var flip := float(_dock_flips.get(port_id, 1.0))
	var turn := 0.0 if port_id == _recording_marina else _port_sea_angle(port_id) + _port_turn(port_id)
	for slot in mini(plots.size(), Hub.INDUSTRY_SLOTS):
		var plot: Rect2 = plots[slot]
		var commodity: String = hub.industries[slot]
		if commodity.is_empty():
			if mine and slot < hub.industry_slots():
				var corners := _marina_polygon(port_id, _rect_points(plot.grow(-plot.size.x * 0.06)))
				corners.append(corners[0])
				for i in 4:
					_dashed_line(corners[i], corners[i + 1], Color(1, 1, 1, 0.55), maxf(0.12 * scale, 1.0), maxf(0.5 * scale, 3.0))
			continue
		var texture := _industry_texture(commodity)
		if texture == null:
			continue
		var shadow := _marina_polygon(port_id, _rect_points(plot.grow(-plot.size.x * 0.04)))
		var drop := Vector2(0.5, 0.5) * scale
		if port_id == _recording_marina:
			drop = drop.rotated(-(_port_sea_angle(port_id) + _port_turn(port_id)))
		for i in shadow.size():
			shadow[i] += drop
		_canvas.draw_colored_polygon(shadow, Color(0, 0, 0, 0.22))
		_canvas.draw_set_transform(_dock_point(port_id, plot.get_center()), turn, Vector2(scale, scale * flip))
		_canvas.draw_texture_rect(texture, Rect2(-plot.size / 2.0, plot.size), false)
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A dashed line between two screen points.
func _dashed_line(from: Vector2, to: Vector2, color: Color, width: float, dash: float) -> void:
	var length := from.distance_to(to)
	var steps := maxi(floori(length / (dash * 2.0)), 1)
	for i in steps:
		var a := from.lerp(to, float(i * 2) / (steps * 2))
		var b := from.lerp(to, float(i * 2 + 1) / (steps * 2))
		_canvas.draw_line(a, b, color, width, true)


## A commodity's industry building's art (art/industry/<commodity>.svg), loaded once.
static func _industry_texture(commodity_id: String) -> Texture2D:
	if not _industry_art.has(commodity_id):
		var path := INDUSTRY_ART_DIR + commodity_id + ".svg"
		_industry_art[commodity_id] = load(path) if ResourceLoader.exists(path) else null
	return _industry_art[commodity_id]


## The industry plot under a screen point at a hub of this player's: [port id,
## slot], or [].
func _industry_at(screen_pos: Vector2) -> Array:
	if not docks_shown():
		return []
	for hub in GameState.hubs:
		if not _marina_shown(hub.port_id):
			continue
		var local: Vector2 = _screen_to_local(hub.port_id, [screen_pos, 0.0])[0]
		var plots := _industry_plots(_port_layout(hub.port_id))
		for slot in plots.size():
			if (plots[slot] as Rect2).has_point(local):
				return [hub.port_id, slot]
	return []


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
	var quay := PackedVector2Array([Vector2(0.0, clear), Vector2(_quay_inland(layout), clear), Vector2(_quay_inland(layout), -clear), Vector2(0.0, -clear)])
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
	# A canal port's cut through the quay, where its canal comes in.
	var cut := _canal_cut(layout)
	if not cut.is_empty():
		var cut_screen := _marina_polygon(port_id, cut)
		_canvas.draw_colored_polygon(cut_screen, water)
		_canvas.draw_line(cut_screen[0], cut_screen[1], QUAY_EDGE, 1.0, true)
		_canvas.draw_line(cut_screen[2], cut_screen[3], QUAY_EDGE, 1.0, true)
	var basin := PackedVector2Array(corners)
	basin.append_array(_arc(inner, -PI / 2.0, PI / 2.0).slice(1, -1))
	_canvas.draw_colored_polygon(_marina_polygon(port_id, basin), water)
	# The quay's edge along the berths, and the marina's edge on land.
	var edge := _marina_polygon(port_id, corners)
	_canvas.draw_polyline(edge, QUAY_EDGE, 1.0, true)
	_canvas.draw_polyline(_marina_polygon(port_id, quay), QUAY_EDGE, 1.0, true)
	_draw_hq_building(port_id, layout)
	_draw_industry(port_id, layout)
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


## How far inland (dock units, -x) a marina's square quay reaches: its cleared
## circle's edge, or past the inland end of a hub's slip.
static func _quay_inland(layout: Dictionary) -> float:
	var inland := -(float(layout.radius) + JETTY_WIDTH / 2.0)
	var slip: Array = layout.slip
	if not slip.is_empty():
		inland = minf(inland, (slip[0] as Vector2).x - float(slip[1]) - QUAY_WIDTH * 2.0)
	return inland


# --- HQ buildings ---------------------------------------------------------------

## A company's HQ building's level (1 to HQ_LEVELS): one more every
## HQ_LEVEL_EVERY company levels.
static func hq_level(company: Company) -> int:
	return clampi(1 + company.level() / HQ_LEVEL_EVERY, 1, HQ_LEVELS)


## Where an HQ's building may stand (dock units): the square quay's corner on
## one side of its slip, from the slip's wall to the square's edge and from its
## inland end round to the marina's basin, which its front follows. [] for a
## marina without a slip.
func _hq_region(layout: Dictionary) -> PackedVector2Array:
	var key := [layout.radius, layout.slip]
	if _hq_regions.has(key):
		return _hq_regions[key]
	var region := PackedVector2Array()
	var slip: Array = layout.slip
	if not slip.is_empty():
		var clear := float(layout.radius) + JETTY_WIDTH / 2.0
		var low := (slip[0] as Vector2).y + float(slip[2]) / 2.0 + QUAY_WIDTH + HQ_MARGIN
		var inland := _quay_inland(layout) + HQ_MARGIN
		var corner := PackedVector2Array([Vector2(inland, low), Vector2(-HQ_MARGIN, low), Vector2(-HQ_MARGIN, clear - HQ_MARGIN), Vector2(inland, clear - HQ_MARGIN)])
		var basin := _arc(float(layout.inner) + QUAY_WIDTH + HQ_MARGIN, 0.0, TAU).slice(0, -1)
		for piece in Geometry2D.clip_polygons(corner, basin):
			if absf(_area(piece)) > absf(_area(region)):
				region = piece
	_hq_regions[key] = region
	return region


static func _area(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size():
		total += points[i].cross(points[(i + 1) % points.size()])
	return total / 2.0


static func _rect_points(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


static func _bounds(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	return box


## The biggest piece of a polygon inside another (dock units), or [].
static func _clip_inside(shape: PackedVector2Array, within: PackedVector2Array) -> PackedVector2Array:
	var best := PackedVector2Array()
	for piece in Geometry2D.intersect_polygons(shape, within):
		if absf(_area(piece)) > absf(_area(best)):
			best = piece
	return best


## A polygon (dock units) pulled in towards its middle by about `by`.
static func _shrink(points: PackedVector2Array, by: float) -> PackedVector2Array:
	var best := PackedVector2Array()
	for piece in Geometry2D.offset_polygon(points, -by):
		if absf(_area(piece)) > absf(_area(best)):
			best = piece
	return best


## The company's HQ building beside its port's slip, growing with it through
## HQ_LEVELS levels (see hq_level()), seen from above: from a little wooden
## hut with its company's flag (1) through a wooden house, a stone lodge, a
## brick office and concrete offices with roof gardens, to glass offices with
## roof terraces, and a tech campus filling its corner (10), its front curving
## round the basin, a terrace on its roof and a helicopter pad.
func _draw_hq_building(port_id: String, layout: Dictionary) -> void:
	var owner: Company = null
	for each in GameState.all_companies():
		var hub := each.hub_at(port_id)
		if hub != null and hub.is_hq:
			owner = each
			break
	var region := _hq_region(layout)
	if owner == null or region.size() < 3:
		return
	var level := hq_level(owner)
	var tint := GameState.company_color_value(owner.color)
	var area := _bounds(region)
	# Its footprint: from the corner furthest inland and from the slip, growing
	# towards the basin; all of its corner at the top level.
	var foot := region
	if level < HQ_LEVELS:
		var share := lerpf(0.22, 0.92, pow(float(level - 1) / float(HQ_LEVELS - 2), 1.1))
		var size := area.size * share
		foot = _clip_inside(_rect_points(Rect2(Vector2(area.position.x, area.end.y - size.y), size)), region)
	if foot.size() < 3:
		return
	var box := _bounds(foot)
	# Its shadow, the taller the longer.
	var height := 0.3 + 0.22 * level
	var drop := Vector2(0.7, 0.7) * height * dock_scale(port_id)  # (Down and to the right on screen.)
	if port_id == _recording_marina:
		drop = drop.rotated(-(_port_sea_angle(port_id) + _port_turn(port_id)))  # (Its item turns it into place.)
	var shadow := _marina_polygon(port_id, foot)
	for i in shadow.size():
		shadow[i] += drop
	_canvas.draw_colored_polygon(shadow, Color(0, 0, 0, 0.28))
	if level <= 3:
		_draw_hq_house(port_id, level, box, tint)
	else:
		_draw_hq_block(port_id, level, foot, box, tint)


## Levels 1 to 3: a wooden hut, a wooden house and a stone lodge, pitched roofs
## with their ridge along the long side, the company's flag at a corner (and
## its color along the eaves from level 2).
func _draw_hq_house(port_id: String, level: int, box: Rect2, tint: Color) -> void:
	var roofs: Array = [[Color("#9a6a3c"), Color("#7d5330")], [Color("#8a5a32"), Color("#6c4426")], [Color("#77726c"), Color("#5f5b56")]]
	var light: Color = roofs[level - 1][0]
	var dark: Color = roofs[level - 1][1]
	var along := box.size.x >= box.size.y
	var first := Rect2(box.position, Vector2(box.size.x, box.size.y / 2.0) if along else Vector2(box.size.x / 2.0, box.size.y))
	var second := Rect2(box.position + (Vector2(0, box.size.y / 2.0) if along else Vector2(box.size.x / 2.0, 0)), first.size)
	_hq_poly(port_id, _rect_points(first), light)
	_hq_poly(port_id, _rect_points(second), dark)
	# Shingles (planks, on the hut) running along the ridge, and the ridge.
	var lines := Color(0, 0, 0, 0.18)
	var step := 0.45
	var ridge := dark.darkened(0.4) if level > 1 else tint
	if along:
		var y := box.position.y + step
		while y < box.end.y - 0.05:
			_hq_line(port_id, Vector2(box.position.x, y), Vector2(box.end.x, y), lines, 0.06)
			y += step
		_hq_line(port_id, Vector2(box.position.x, box.get_center().y), Vector2(box.end.x, box.get_center().y), ridge, 0.14)
	else:
		var x := box.position.x + step
		while x < box.end.x - 0.05:
			_hq_line(port_id, Vector2(x, box.position.y), Vector2(x, box.end.y), lines, 0.06)
			x += step
		_hq_line(port_id, Vector2(box.get_center().x, box.position.y), Vector2(box.get_center().x, box.end.y), ridge, 0.14)
	if level >= 2:
		_hq_outline(port_id, _rect_points(box), tint, 0.16)  # Painted eaves.
		_hq_poly(port_id, _rect_points(Rect2(box.position + box.size * Vector2(0.72, 0.18), Vector2.ONE * minf(box.size.x, box.size.y) * 0.14)), Color("#4a3a32"))  # The chimney.
	if level == 3:
		# A flat-roofed annex beside it.
		var annex := Rect2(Vector2(box.end.x + 0.2, box.position.y + box.size.y * 0.35), Vector2(box.size.x * 0.35, box.size.y * 0.65))
		_hq_poly(port_id, _rect_points(annex), Color("#8d8a84"))
		_hq_outline(port_id, _rect_points(annex), tint, 0.12)
	# The flag at its corner nearest the slip and the sea: a pole and its pennant.
	var pole := Vector2(box.end.x + 0.35, box.position.y - 0.35)
	_hq_dot(port_id, pole, 0.12, Color("#2a2a2a"))
	_hq_poly(port_id, PackedVector2Array([pole, pole + Vector2(0.9, -0.25), pole + Vector2(0.15, -0.55)]), tint)


## Levels 4 to 10: flat-roofed offices, brick, then concrete, then glass, each
## with its company's sign along the front; roof gear, then planters, then a
## deck with sunshades, a lawn, solar panels and a pool, and at the top level
## a helicopter pad.
func _draw_hq_block(port_id: String, level: int, foot: PackedVector2Array, box: Rect2, tint: Color) -> void:
	var wall := Color("#9c4a3a")
	var roof := Color("#5f5a55")  # (Tar and gravel: darker than the quay.)
	if level >= 5 and level <= 6:
		wall = Color("#c3c0b8")
		roof = Color("#dcd8ce")
	elif level >= 7:
		wall = Color("#5d9cc4").lerp(tint, 0.12)
		roof = Color("#c9ccd0")
	_hq_poly(port_id, foot, wall)
	# The roof inside its parapet (a glass curtain wall shows as a band round it).
	var inset := 0.35 if level < 7 else 0.55
	var top := _shrink(foot, inset)
	if top.size() < 3:
		return
	_hq_poly(port_id, top, roof)
	if level >= 7:
		_hq_outline(port_id, top, Color(1, 1, 1, 0.35), 0.05)
		# Mullions in the glass band along the front and back.
		var x := box.position.x + 0.8
		while x < box.end.x:
			for edge: Array in [[box.position.y, box.position.y + inset], [box.end.y - inset, box.end.y]]:
				var from := Vector2(x, edge[0])
				var to := Vector2(x, edge[1])
				if Geometry2D.is_point_in_polygon((from + to) / 2.0, foot) and not Geometry2D.is_point_in_polygon((from + to) / 2.0, top):
					_hq_line(port_id, from, to, Color(1, 1, 1, 0.35), 0.05)
			x += 0.8
	var roof_box := _bounds(top)
	# The company's sign along the front (the side facing the slip).
	_hq_poly(port_id, _clip_inside(_rect_points(Rect2(box.position + Vector2(box.size.x * 0.2, -0.05), Vector2(box.size.x * 0.6, 0.3))), foot), tint)
	# Roof gear on the lower levels.
	if level <= 6:
		for k in 3:
			var at := roof_box.position + roof_box.size * Vector2(0.12 + 0.12 * k, 0.62)
			_hq_poly(port_id, _clip_inside(_rect_points(Rect2(at, Vector2(0.6, 0.45))), top), Color("#7a7c80"))
	# Solar panels from level 8, in rows at the inland end.
	if level >= 8:
		var panels := Rect2(roof_box.position + Vector2(0.3, roof_box.size.y * 0.55), Vector2(roof_box.size.x * 0.3, roof_box.size.y * 0.38))
		var y := panels.position.y
		while y < panels.end.y - 0.3:
			_hq_poly(port_id, _clip_inside(_rect_points(Rect2(Vector2(panels.position.x, y), Vector2(panels.size.x, 0.35))), top), Color("#2c3e66"))
			y += 0.55
	# The roof terrace: planters from level 5, a deck with sunshades from 6, a
	# lawn from 7 and a pool from 9, growing towards the water.
	if level >= 5:
		var deck_share := clampf(0.18 + 0.07 * (level - 5), 0.18, 0.5)
		if level >= 6:
			var deck := _clip_inside(_rect_points(Rect2(Vector2(roof_box.end.x - roof_box.size.x * deck_share - 0.2, roof_box.position.y + 0.3), Vector2(roof_box.size.x * deck_share, roof_box.size.y * 0.6))), top)
			if deck.size() >= 3:
				_hq_poly(port_id, deck, Color("#c79a66"))
				var deck_box := _bounds(deck)
				var shades := clampi(level - 4, 2, 6)
				for k in shades:
					var at := deck_box.position + deck_box.size * Vector2((k + 0.5) / shades, 0.3 + 0.35 * (k % 2))
					if Geometry2D.is_point_in_polygon(at, deck):
						_draw_sunshade(port_id, at, 0.42, tint)
		if level >= 7:
			_hq_poly(port_id, _clip_inside(_rect_points(Rect2(roof_box.position + roof_box.size * Vector2(0.38, 0.55), roof_box.size * Vector2(0.3, 0.35))), top), Color("#6aa84f"))
		if level >= 9:
			var water := _clip_inside(_rect_points(Rect2(roof_box.position + roof_box.size * Vector2(0.4, 0.1), roof_box.size * Vector2(0.18, 0.3))), top)
			if water.size() >= 3:
				_hq_poly(port_id, water, Color("#7fd3e8"))
				_hq_outline(port_id, water, Color.WHITE, 0.08)
		var planters := 4 + level
		for k in planters:
			var at := Vector2(lerpf(roof_box.position.x + 0.3, roof_box.end.x - 0.3, float(k) / maxf(planters - 1, 1)), roof_box.position.y + 0.2)
			if Geometry2D.is_point_in_polygon(at, top):
				_hq_dot(port_id, at, 0.16, Color("#3f8a3f"))
	# The company's logo on the roof; at the top level, by its helicopter pad.
	var spot := roof_box.position + roof_box.size * Vector2(0.18, 0.3)
	if level >= 6 and level < HQ_LEVELS:
		_hq_dot(port_id, spot, minf(roof_box.size.x, roof_box.size.y) * 0.12, tint)
	if level >= HQ_LEVELS:
		var pad_r := minf(roof_box.size.x, roof_box.size.y) * 0.17
		_hq_dot(port_id, spot, pad_r, Color("#3a3d42"))
		_hq_ring(port_id, spot, pad_r * 0.82, Color("#f2c230"), pad_r * 0.08)
		var h := pad_r * 0.38
		for x: float in [-h * 0.6, h * 0.6]:
			_hq_line(port_id, spot + Vector2(x, -h), spot + Vector2(x, h), Color.WHITE, pad_r * 0.12)
		_hq_line(port_id, spot + Vector2(-h * 0.6, 0), spot + Vector2(h * 0.6, 0), Color.WHITE, pad_r * 0.12)
		_hq_dot(port_id, spot + Vector2(pad_r * 1.6, 0), pad_r * 0.35, tint)


## A round sunshade in the company's color seen from above, with its ribs.
func _draw_sunshade(port_id: String, at: Vector2, radius: float, tint: Color) -> void:
	_hq_dot(port_id, at + Vector2(0.12, 0.12), radius, Color(0, 0, 0, 0.2))
	_hq_dot(port_id, at, radius, tint)
	for k in 4:
		var way := Vector2.from_angle(PI / 4.0 + k * PI / 2.0) * radius
		_hq_line(port_id, at - way, at + way, tint.darkened(0.3), 0.04)
	_hq_dot(port_id, at, radius * 0.18, Color.WHITE)


func _hq_poly(port_id: String, points: PackedVector2Array, color: Color) -> void:
	if points.size() >= 3:
		_canvas.draw_colored_polygon(_marina_polygon(port_id, points), color)


func _hq_outline(port_id: String, points: PackedVector2Array, color: Color, width: float) -> void:
	if points.size() < 2:
		return
	var screen := _marina_polygon(port_id, points)
	screen.append(screen[0])
	_canvas.draw_polyline(screen, color, maxf(width * dock_scale(port_id), 1.0), true)


func _hq_line(port_id: String, from: Vector2, to: Vector2, color: Color, width: float) -> void:
	_canvas.draw_line(_dock_point(port_id, from), _dock_point(port_id, to), color, maxf(width * dock_scale(port_id), 1.0), true)


func _hq_dot(port_id: String, at: Vector2, radius: float, color: Color) -> void:
	_canvas.draw_circle(_dock_point(port_id, at), maxf(radius * dock_scale(port_id), 0.8), color, true, -1.0, true)


func _hq_ring(port_id: String, at: Vector2, radius: float, color: Color, width: float) -> void:
	_canvas.draw_arc(_dock_point(port_id, at), radius * dock_scale(port_id), 0.0, TAU, 32, color, maxf(width * dock_scale(port_id), 1.0), true)


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
	# Where it sets off from when it sails (on the unit sphere), its heading, and
	# whether it was lying at anchor, facing the wind (not heading out already).
	_last_spot[ship] = [ship.docked_at, _screen_unit(pose[0]), pose[1], ship.berth < 0 and ship.berth_phase == Ship.BERTH_NONE]
	return pose


func _docked_screen_pose(ship: Ship) -> Array:
	var port := ship.docked_at
	var layout := _port_layout(port)
	_update_spots()
	var worked := _worked_pose(ship)  # (Brought in by tugs.)
	if not worked.is_empty():
		return worked
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
					var shaped := _loosen(poses, weighing, false, length * ANCHOR_TURN_LENGTHS)
					var path := _pose_path(shaped)
					return _follow(poses, shaped, path, _timed_share(path, _path_times(path, _sea_speed_px(ship), length, length, weighing, true), ship.berth_time / sail))
				return _slide(off, at, (ship.berth_time - sail) / slide_s)
			Ship.BERTH_OUT:
				# Driving off its berth: getting going ahead along the quay and
				# peeling away from it in a smooth curve, as a ship would, then on
				# round and out through the entrance on its right-hand side to sea
				# (or to its spot at the anchorage, slowing to anchor). If it lies
				# bow away from the way out (in a hub's slip), it first backs
				# straight out stern first to the middle of the marina and turns
				# there on its thrusters.
				var total := ship.berth_duration if ship.berth_duration > 0.0 else float(settings.get("out_s", 5.0))
				var t := ship.berth_time
				var plan := _unberth_plan(ship)
				var poses := [at]
				if plan.reverse:
					var back := [_dock_point(port, plan.back), at[1]]
					if t < plan.reverse_s:
						var share := _sailed_share(t / plan.reverse_s, float(plan.reverse_units), float(plan.ease), true, true)
						return [(at[0] as Vector2).lerp(back[0], share), at[1]]
					t -= plan.reverse_s
					var turned := _dock_angle(port, float(plan.out_angle))
					if t < UNBERTH_TURN_S:
						return [back[0], lerp_angle(float(at[1]), turned, smoothstep(0.0, 1.0, t / UNBERTH_TURN_S))]
					t -= UNBERTH_TURN_S
					poses = [[back[0], turned]]
				else:
					var peel := _peel_pose(berth, ship)
					poses.append([_dock_point(port, peel[0]), _dock_angle(port, float(peel[1]))])
				poses.append(_keep_right(port, _entrance_pose(port, false, false)))
				var anchoring := ship.depart_to.is_empty()
				if anchoring:
					var rest := _rest_pose(ship)
					var mouth_room := ((layout.mouth as Vector2) - (layout.inside as Vector2)).length() * dock_scale(port) * 0.5
					if (rest[0] as Vector2).distance_to(poses[-1][0]) < maxf(length, mouth_room):
						poses.pop_back()  # (Its spot's right by the mouth: straight there.)
					poses.append(rest)
				var shaped := _loosen(poses, false, anchoring, length * ANCHOR_TURN_LENGTHS)
				var path := _pose_path(shaped)
				var before := float(plan.reverse_s) + UNBERTH_TURN_S if plan.reverse else 0.0
				var sail_s := maxf(total - before, 0.01)
				return _follow(poses, shaped, path, _timed_share(path, _path_times(path, _sea_speed_px(ship), length, length, true, anchoring), t / sail_s))
		return at
	return _lying_pose(ship, GameState.play_time)


## A pose (screen) moved over to its right-hand side of its port's harbour
## entrance, as ships keep to starboard: in and out pass each other.
func _keep_right(port_id: String, pose: Array) -> Array:
	var side := float(_port_layout(port_id).width) * KEEP_RIGHT_WIDTHS * dock_scale(port_id)
	return [(pose[0] as Vector2) + Vector2.from_angle(float(pose[1]) + PI / 2.0) * side, pose[1]]


## Where a ship driving off its berth has got clear of the quay (dock units):
## about a length ahead and a little out from it, angled away (see
## _docked_screen_pose()). [point, facing].
func _peel_pose(berth: Array, ship: Ship) -> Array:
	var rect: Rect2 = _model_look(ship.model_id)[7]
	var moored := _berth_pose(berth, ship)
	var along := Vector2.from_angle(float(moored[1]))
	var out: Vector2 = berth[2]
	var away := (along + out * PEEL_ANGLE).normalized()
	return [(moored[0] as Vector2) + along * rect.size.x * PEEL_AHEAD + out * rect.size.y * PEEL_OUT_WIDTHS, away.angle()]


## How a moored ship gets clear of its berth to head out (dock units): if it
## lies bow away from the way out (in a hub's slip), it backs straight out
## stern first along its berth until it's abreast the middle of the marina (back), at
## UNBERTH_REVERSE_SPEED of its speed, taking reverse_s (getting going and
## stopping over ease), then turns there to out_angle. {reverse, back,
## out_angle, reverse_units, reverse_s, ease}.
func _unberth_plan(ship: Ship) -> Dictionary:
	var plan := {reverse = false, back = Vector2.ZERO, out_angle = 0.0, reverse_units = 0.0, reverse_s = 0.0, ease = 0.0}
	var layout := _port_layout(ship.docked_at)
	if ship.berth < 0 or ship.berth >= layout.berths.size():
		return plan
	var berth: Array = layout.berths[ship.berth]
	if (layout.slip as Array).is_empty() or str(berth[5]) != "B":
		return plan  # Only out of a slip: from any other berth it drives off ahead and round.
	var rect: Rect2 = _model_look(ship.model_id)[7]
	var moored := _berth_pose(berth, ship)
	var off: Vector2 = moored[0]  # (Backing straight off the berth, along the wall.)
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
	var off: Array = _glide_from.get(ship, [])
	if not off.is_empty() and float(off[0]) == since:
		# A tug that's just let go of the ship it brought in: from there.
		poses = (off[1] as Array).map(func(pose: Array) -> Array: return _local_to_screen(ship.docked_at, pose)) + [rest]
	# Coming round to face the wind on a turning circle as it comes up to its
	# spot, slowing to a stop there (see _loosen()).
	var length := (_model_look(ship.model_id)[7] as Rect2).size.x * dock_scale(ship.docked_at)
	var shaped := _loosen(poses, false, true, length * ANCHOR_TURN_LENGTHS)
	var path := _pose_path(shaped)
	var distance := _path_length(path)
	var ease := minf(length, distance / 3.0)
	var takes := (distance + ease) / maxf(_sea_speed_px(ship), 0.001)
	if seen.size() < 3:
		seen.append(since + takes)  # When it's settled (kept, so the glide's end is cheap to check).
	var elapsed := at_time - since
	if elapsed >= takes:
		return rest
	return _follow(poses, shaped, path, _sailed_share(clampf(elapsed / takes, 0.0, 1.0), distance, length, false, true))


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
	_refresh_spots()
	if coming_in and _assist_lead(ship) != null:
		# Tugs working it in (see _tug_work()), less the slide GameState adds.
		return maxf(_tug_work_seconds(ship) - float(Docks.settings().get("slide_s", 1.5)), 0.01)
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
		var poses := [_screen_to_local(port, _rest_pose(ship)) if weighing else mouth_in]
		if weighing and anchor.distance_to(layout.mouth) > maxf(length, mouth_room):
			poses.append(mouth_in)
		elif weighing:
			poses.append([layout.inside, PI])
		poses.append(off)
		var path := _pose_path(_loosen(poses, weighing, false, length * ANCHOR_TURN_LENGTHS))
		return _path_times(path, speed, length, length, weighing, true)[-1]
	var backing := 0.0  # Backing out and turning round first (s; see _unberth_plan()).
	var plan := _unberth_plan(ship)
	var poses := [[moored[0], float(moored[1])], _peel_pose(berth, ship)]
	if plan.reverse:
		backing = float(plan.reverse_s) + UNBERTH_TURN_S
		poses = [[plan.back, float(plan.out_angle)]]
	poses.append([layout.mouth, 0.0])
	var anchoring := ship.depart_to.is_empty()
	var anchor := _anchor_local(ship) if anchoring else Vector2(NAN, NAN)
	if anchor.x == anchor.x:
		if anchor.distance_to(layout.mouth) < maxf(length, mouth_room):
			poses.pop_back()
		poses.append(_screen_to_local(port, _rest_pose(ship)))
	var path := _pose_path(_loosen(poses, false, anchoring and anchor.x == anchor.x, length * ANCHOR_TURN_LENGTHS))
	return backing + _path_times(path, speed, length, length, true, anchoring)[-1]


## Every ship's spot in port as things are now (one may only just have
## started pulling out to anchor, or been brought in by tugs).
func _refresh_spots() -> void:
	if _spots_frame >= 0:
		_spots_dirty = true
		_spots_frame = Engine.get_process_frames() - 1
	_update_spots()


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
	var slot := int(_spot_slots.get(ship, 0))
	if ship.is_tug():
		return _local_to_screen(port, _jetty_pose(port, slot, ship))
	var key: Array = _spot_keys[ship] if _spot_keys.has(ship) else [port, _anchor_pool(ship)]
	var half: float = (_model_look(ship.model_id)[7] as Rect2).size.x / 2.0
	var anchor := _anchor_screen_cached(ship, port, str(key[1]), slot)
	var facing := _upwind_angle(port)
	var storm := _storm_strength_at_port(port)
	if storm > 0.0:
		var t := GameState.play_time
		facing += (sin(t * 1.7 + ship.id * 1.3) * 0.7 + sin(t * 3.3 + ship.id * 0.7) * 0.3) * STORM_SWING * storm
	return [anchor - Vector2.from_angle(facing) * half * _ship_scale(), facing]


## Where a tug moors in its port (dock units, [middle, facing]): alongside
## the inside of its marina's breakwater, by its slot (the first free one,
## kept till it leaves: see _update_spots()), the arms taken by turns, from
## the quay end of each towards the entrance, bow pointing out towards it,
## TUG_MOOR_GAP between one and the next.
func _jetty_pose(port_id: String, slot: int, tug: Ship) -> Array:
	var layout := _port_layout(port_id)
	var look: Rect2 = _model_look(tug.model_id)[7]
	var off := float(layout.radius) - JETTY_WIDTH / 2.0 - look.size.y / 2.0 - TUG_HULL_GAP
	var side := 1.0 if slot % 2 == 0 else -1.0
	var along := PI / 2.0 - TUG_MOOR_END - (floorf(slot / 2.0) + 0.5) * (look.size.x + TUG_MOOR_GAP) / off
	along = maxf(along, float(layout.gap) + 0.1)
	var at := Vector2.from_angle(along * side) * off
	return [at, along * side - side * PI / 2.0]


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
	if ship.is_tug():
		return "jetty"  # (Tugs moor along the inside of the breakwater: see _jetty_pose().)
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


## Poses for _pose_path() with a ship at anchor (facing the wind) at its
## start (weighing anchor) or end (coming to anchor): it keeps the way it
## faces, as a ship does, and where that isn't the way it's going, comes
## round on a turning circle `radius` across (its own length's worth, see
## HARBOUR_TURN_LENGTHS): through extra poses round the circle from its
## facing to heading for the next pose (or, coming to anchor, round from the
## way it comes in to face the wind). It never swings round on the spot or
## slips sideways (see _follow()).
static func _loosen(poses: Array, loose_start: bool, loose_end: bool, radius := 0.0) -> Array:
	if poses.size() < 2:
		return poses.duplicate()
	var shaped := poses.duplicate()
	if loose_start:
		shaped = [poses[0]] + _turning_round(poses[0], poses[1][0], radius) + poses.slice(1)
	if loose_end:
		# The same, sailed backwards: out from facing away from the wind to the
		# pose before, then turned round.
		var last: Array = shaped[-1]
		var back := _turning_round([last[0], float(last[1]) + PI], shaped[-2][0], radius)
		back.reverse()
		shaped = shaped.slice(0, -1) + back.map(func(pose: Array) -> Array: return [pose[0], float(pose[1]) + PI]) + [last]
	return shaped


## The poses round a turning circle (`radius`) from a pose to heading for a
## point: a quarter turn apart at most, so the path through them stays round.
## [] if it heads near enough that way already.
static func _turning_round(pose: Array, toward: Vector2, radius: float) -> Array:
	var from: Vector2 = pose[0]
	var facing := float(pose[1])
	if radius <= 0.0 or from.distance_to(toward) < 0.001:
		return []
	var turn := angle_difference(facing, (toward - from).angle())
	if absf(turn) < TURN_FREE_ANGLE:
		return []
	var side := signf(turn)
	var center := from + Vector2.from_angle(facing + side * PI / 2.0) * radius
	var steps := ceili(absf(turn) / (PI / 2.0))
	var out := []
	for k in range(1, steps + 1):
		var swung := absf(turn) * k / steps
		out.append([center + Vector2.from_angle(facing - side * PI / 2.0 + side * swung) * radius, facing + side * swung])
	return out


## A ship a share of the way (by distance) along a path through poses
## (shaped by _loosen()): [point, heading], facing the way the path goes (it
## starts and ends on the shaped poses' facings, which _loosen() keeps the
## ship's own).
static func _follow(_poses: Array, shaped: Array, path: PackedVector2Array, share: float, _weighed := 1.0, _anchoring := 0.0) -> Array:
	return _along_path(path, share, float(shaped[0][1]), float(shaped[-1][1]))


## An angle a share w of the way from one to another, turning the way nearest
## `hint` (a signed turn from `from`): round the long way if that's the side
## the turn started on.
static func _turn_toward(from: float, to: float, w: float, hint: float) -> float:
	var turn := angle_difference(from, to)
	if absf(turn - hint) > PI:
		turn += TAU if turn < hint else -TAU
	return from + turn * w



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
			var finish: Array = _tug_finish.get(ship, [])
			if not finish.is_empty() and finish[0] == port and not first:
				_glide_from[ship] = [GameState.play_time, finish[1]]  # (A tug letting go of the ship it brought in.)
			_tug_finish.erase(ship)
		var lies := ship.berth < 0 or ship.berth_phase == Ship.BERTH_IN \
			or ship.berth_phase == Ship.BERTH_OUT and ship.depart_to.is_empty()
		if lies and not _spot_slots.has(ship):
			var key := [port, _anchor_pool(ship)]
			var taken: Dictionary = _spot_tables.get_or_add(key, {})
			var slot := _free_anchor(port, key[1], taken)
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


## The anchor a ship dropping anchor at a port takes (a slot in its
## anchorage, see _anchor_spots(); `taken`: those lain at now): the first
## free one out of the shipping lanes drawn now (see _anchors_in_lanes()),
## or if they're all in a lane, the first free one.
func _free_anchor(port_id: String, pool: String, taken: Dictionary) -> int:
	var in_lanes := _anchors_in_lanes(port_id, pool) if pool != "jetty" else PackedByteArray()
	for slot in in_lanes.size():
		if in_lanes[slot] == 0 and not taken.has(slot):
			return slot
	var slot := 0
	while taken.has(slot):
		slot += 1
	return slot


## Which of a port's anchor points (_anchor_spots()) are in the shipping
## lanes: 1 for each one a lane the map draws (_active_lanes(): every
## company's routes, bent round other ports' harbours as drawn) passes within
## its ship's swing of, and ANCHOR_LANE_MARGIN_NM more. Worked out again when
## the drawn lanes change; ships already lying there stay put.
func _anchors_in_lanes(port_id: String, pool: String) -> PackedByteArray:
	var spots := _anchor_spots(port_id, pool)
	var legs := PackedStringArray()
	var lanes := []
	for lane: Array in _active_lanes():
		var leg := "%s-%s" % ([lane[0], lane[1]] if lane[0] < lane[1] else [lane[1], lane[0]])
		if not legs.has(leg):
			legs.append(leg)
			lanes.append(lane)
	legs.sort()
	var key := [",".join(legs), spots]
	var cached: Array = _anchor_lanes.get(port_id + pool, [])
	if not cached.is_empty() and cached[0] == key:
		return cached[1]
	var flags := PackedByteArray()
	flags.resize(spots.size())
	var port := GameData.port_position(port_id)
	# Projected units a nm here, and how near a lane must come to a spot.
	var per_nm := 1.0 / (60.0 * maxf(cos(deg_to_rad(float(GameData.get_port(port_id).get("lat", 0.0)))), 0.05))
	var swing := (_anchor_length(pool) * 60.0 / SHIP_WORLD_ZOOM + ANCHOR_LANE_MARGIN_NM) * per_nm
	var points := PackedVector2Array()
	var reach := 0.0
	for spot in spots:
		var at := Geo.project(spot)
		at.x = port.x + wrapf(at.x - port.x, -180.0, 180.0)
		points.append(at)
		reach = maxf(reach, at.distance_to(port) + swing)
	var near := Rect2(port, Vector2.ZERO).grow(reach)
	for lane: Array in lanes:
		var sea_lane = GameData.lane(lane[0], lane[1])
		if sea_lane == null:
			continue
		var bent: PackedVector2Array = _bent_lane(sea_lane, lane[0], lane[1]).points
		for i in range(1, bent.size()):
			var a := bent[i - 1]
			var b := bent[i]
			a.x = port.x + wrapf(a.x - port.x, -180.0, 180.0)
			b.x = a.x + (b.x - bent[i - 1].x)
			if not near.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				continue
			for k in points.size():
				if flags[k] == 0 and Geometry2D.get_closest_point_to_segment(points[k], a, b).distance_to(points[k]) < swing:
					flags[k] = 1
	_anchor_lanes[port_id + pool] = [key, flags]
	return flags


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
		return _follow(curve[1], curve[2], curve[0], 1.0 - gone / reach if arriving else gone / reach)
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


## True if a ship sailing from port set off straight from its spot (at the
## anchorage, facing the wind; a tug from its moorings on the jetty), not
## out of its marina's mouth already heading out.
func _left_from_anchor(ship: Ship) -> bool:
	var last: Array = _last_spot.get(ship, [])
	return last.size() > 3 and bool(last[3])


## How tight (screen px, a radius) a ship sailing from port comes round from
## facing where it lay to its way out (see _loosen()), or 0 if it came out of
## its marina's mouth already heading out.
func _leaving_turn(ship: Ship) -> float:
	if not _left_from_anchor(ship):
		return 0.0
	return (_model_look(ship.model_id)[7] as Rect2).size.x * _ship_scale() * ANCHOR_TURN_LENGTHS


## The poses a ship sailing from port goes through between where it lay and
## its lane: for a tug from its moorings on the jetty, out through its
## marina's mouth (on its right-hand side, heading out).
func _leaving_via(ship: Ship) -> Array:
	if not ship.is_tug() or not _left_from_anchor(ship) or ship.from_port.is_empty():
		return []
	return [_keep_right(ship.from_port, _entrance_pose(ship.from_port, false, false))]


## The curve between a ship's lane, `reach` nm from a port, and that port's
## harbour (see _harbour_pose()), from the lane in arriving and from the
## harbour out leaving (from where it lay, coming round from there on a turning
## it gets going, see _follow()): [screen points, poses, shaped poses], or []
## if either end is round the far side.
func _harbour_curve(ship: Ship, lane, length: float, arriving: bool, reach: float) -> Array:
	var port := ship.to_port if arriving else ship.from_port
	if _is_hidden(port_screen_position(port)):
		return []
	return _lane_curve(lane, ship.from_port, ship.to_port, length, arriving, reach, _harbour_end(ship, port, arriving), 0.0 if arriving else _leaving_turn(ship), [] if arriving else _leaving_via(ship))


## The curve between a lane, `reach` nm from its end (arriving) or start, and
## a harbour pose (screen), from_port and to_port the lane's ports: [screen
## points, poses, shaped poses], or [] if either end is round the far side.
## `turn`: leaving from where it lay, how tight it comes round from there (see
## _loosen()); `via`: poses on the way between the harbour end and the lane.
func _lane_curve(lane, from_port: String, to_port: String, length: float, arriving: bool, reach: float, harbour: Array, turn := 0.0, via := []) -> Array:
	var mile := length - reach if arriving else reach
	var sample: Array = _bent_sample(lane, from_port, to_port, clampf(mile, 0.0, length))  # (Bent round other harbours.)
	var edge := world_to_screen(sample[0])
	if _is_hidden(edge) or _is_hidden(harbour[0]):
		return []
	var on_lane := [edge, _heading_angle(sample[1], sample[0])]
	var poses := [on_lane] + via + [harbour] if arriving else [harbour] + via + [on_lane]
	var shaped := _loosen(poses, turn > 0.0, false, turn)
	return [_pose_path(shaped, HARBOUR_CURVE_HANDLE), poses, shaped]


## How far (nm of lane) from each end of its leg a ship sails its curve in or
## out of port: [arriving, leaving], worked out once a leg (0 for none).
func _harbour_reaches(ship: Ship, lane, length: float) -> PackedFloat32Array:
	var key := [ship.from_port, ship.to_port]
	var cached: Array = _harbour_reach_cache.get(ship, [])
	if not cached.is_empty() and cached[0] == key:
		return cached[1]
	var ends := []
	for i in 2:
		var port := ship.to_port if i == 0 else ship.from_port
		ends.append([] if port.is_empty() or _is_hidden(port_screen_position(port)) else _harbour_end(ship, port, i == 0))
	var found := _lane_reaches(lane, length, ship.to_port, ship.from_port, ends, _leaving_turn(ship), _leaving_via(ship))
	if found[1]:  # (Not while a port is round the far side: worked out again when it comes round.)
		_harbour_reach_cache[ship] = [key, found[0]]
	return found[0]


## How far (nm of lane) from each end of a lane the curves to its harbours
## take, [arriving, leaving], for the harbour poses `ends` (screen; [] for
## none): HARBOUR_REACH times the harbour's distance from its port, at least
## HARBOUR_MIN_NM, more if the curve is longer (so it's never faster than at
## sea), the two sharing a short lane. [reaches, true if both ports showed].
func _lane_reaches(lane, length: float, to_port: String, from_port: String, ends: Array, turn := 0.0, via := []) -> Array:
	var px_per_nm := _zoom / 60.0
	var reaches := PackedFloat32Array([0.0, 0.0])
	var shown := true
	for i in 2:
		var arriving := i == 0
		var port := to_port if arriving else from_port
		if port.is_empty():
			continue
		var harbour: Array = ends[i]
		if harbour.is_empty() or _is_hidden(port_screen_position(port)):
			shown = false
			continue
		var reach := maxf((harbour[0] as Vector2).distance_to(port_screen_position(port)) / px_per_nm * HARBOUR_REACH, HARBOUR_MIN_NM)
		# A longer curve than its stretch of lane would be faster than at sea:
		# give it as much lane as it's long.
		for k in 3:
			var curve := _lane_curve(lane, from_port, to_port, length, arriving, minf(reach, length), harbour, 0.0 if arriving else turn, [] if arriving else via)
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
	return [reaches, shown]


func _draw_overlay() -> void:
	_canvas = _overlay
	if show_ships:
		_draw_ships()
		_draw_birds()
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
	# (Kept till the hubs or the picked port change: placed every frame the view moves.)
	if _ranked_ports_key != hub_ports:
		_ranked_ports_key = hub_ports
		_ranked_ports = _ports_by_rank.filter(func(port: Dictionary) -> bool: return hub_ports.has(port.id))
		_ranked_ports.append_array(_ports_by_rank.filter(func(port: Dictionary) -> bool: return not hub_ports.has(port.id)))
	var near_ids := {}
	for i in _ports_near_view():
		near_ids[GameData.ports[i].id] = true
	var labels := []
	var bounds := Rect2(Vector2.ZERO, size)
	var near := bounds.grow(LABEL_REACH_PX)
	for port: Dictionary in _ranked_ports:
		if not near_ids.has(port.id):
			continue  # (Cheapest first: most are well off screen.)
		if not selectable_ports.is_empty() and not selectable_ports.has(port.id):
			continue  # Picking a port: only the choices are named.
		var pos := port_screen_position(port.id)
		if not near.has_point(pos):
			continue  # (Cheapest first: most are well off screen.)
		var text_size := _label_size(font, port.name, PORT_FONT_SIZE)
		var rect := Rect2(pos + Vector2(-text_size.x / 2.0, _port_radius(port.id) + 2.0), text_size)
		if not bounds.intersects(rect) or _overlaps(rect, placed):
			continue
		placed.append(rect.grow(LABEL_PADDING))
		labels.append([port.id, rect])
	return labels


## The ports near enough the view to show there (a port, its label, its
## marina or its birds): their places in GameData.ports, in order. Worked out
## once a view, so the loops over the ports each frame skip the rest of the
## world.
func _ports_near_view() -> PackedInt32Array:
	if _near_ports_valid:
		return _near_ports
	if _port_cells.is_empty():
		for i in GameData.ports.size():
			var port: Dictionary = GameData.ports[i]
			var cell := _label_cell(Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))))
			if not _port_cells.has(cell):
				_port_cells[cell] = PackedInt32Array()
			_port_cells[cell].append(i)
	_near_ports = _ranks_near_view(_port_cells, maxf(LABEL_REACH_PX, MARINA_MAX_REACH * 2.0 * _ship_scale()))
	_near_ports.sort()
	_near_ports_valid = true
	return _near_ports


## A (lon, lat) point's cell of the globe, LABEL_CELL_DEG square (see _ranks_near_view()).
static func _label_cell(lon_lat: Vector2) -> Vector2i:
	return Vector2i(floori((lon_lat.x + 180.0) / LABEL_CELL_DEG), floori((lon_lat.y + 90.0) / LABEL_CELL_DEG))


## Everything in the cells of the globe (see _label_cell()) that can be in
## view, or within margin_px of it (for a label, LABEL_REACH_PX): all of them zoomed
## out, a few cells' worth zoomed in.
func _ranks_near_view(cells: Dictionary, margin_px := LABEL_REACH_PX) -> PackedInt32Array:
	var out := PackedInt32Array()
	var reach := rad_to_deg(asin(minf((size.length() / 2.0 + margin_px) / _radius(), 1.0)))
	var top := absf(_view_lat) + reach
	if reach >= 60.0 or top >= 85.0:
		for ranks: PackedInt32Array in cells.values():
			out.append_array(ranks)
		return out
	var across := reach / cos(deg_to_rad(top))
	var columns := ceili(360.0 / LABEL_CELL_DEG)
	var first := floori((_view_lon - across + 180.0) / LABEL_CELL_DEG)
	var last := mini(floori((_view_lon + across + 180.0) / LABEL_CELL_DEG), first + columns - 1)
	for row in range(floori((_view_lat - reach + 90.0) / LABEL_CELL_DEG), floori((_view_lat + reach + 90.0) / LABEL_CELL_DEG) + 1):
		for column in range(first, last + 1):
			out.append_array(cells.get(Vector2i(posmod(column, columns), row), PackedInt32Array()))
	return out


## How big a label's text is (px) in a font at a size, measured once (shaping
## text is slow, and labels are placed again every frame the view moves).
func _label_size(font: Font, text: String, font_size: int) -> Vector2:
	var key := "%d %d %s" % [font.get_instance_id(), font_size, text]
	if not _label_sizes.has(key):
		_label_sizes[key] = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	return _label_sizes[key]


## Country names that fit around the port labels already placed: [text, rect] pairs.
func _place_country_labels(placed: Array[Rect2]) -> Array:
	var data := GameData.world_map
	if _country_units.is_empty():
		for p in data.label_positions:
			_country_units.append(_unit(p))  # (Worked out once: they never move.)
	var font := get_theme_default_font()
	var web_zoom := _web_zoom()
	var labels := []
	var bounds := Rect2(Vector2.ZERO, size)
	var near := bounds.grow(LABEL_REACH_PX)
	for i in data.label_names.size():
		if data.label_min_zoom[i] > web_zoom:
			continue
		var at := _unit_to_screen(_country_units[i])
		if not near.has_point(at):
			continue
		var text := data.label_names[i]
		var text_size := _label_size(font, text, COUNTRY_FONT_SIZE)
		var rect := Rect2(at - text_size / 2.0, text_size)
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
	if _feature_units.is_empty():
		for p in data.feature_label_positions:
			_feature_units.append(_unit(p))  # (Worked out once: they never move.)
	if _feature_order.is_empty():
		var order := range(data.feature_label_names.size())
		order.sort_custom(func(a: int, b: int) -> bool:
			var rank_a := FEATURE_PRIORITY.find(data.feature_label_kinds[a])
			var rank_b := FEATURE_PRIORITY.find(data.feature_label_kinds[b])
			return rank_a < rank_b if rank_a != rank_b else data.feature_label_min_zoom[a] < data.feature_label_min_zoom[b])
		_feature_order = PackedInt32Array(order)
	var web_zoom := _web_zoom()
	if _feature_thresholds.is_empty():
		var zooms := {}
		for i in data.feature_label_names.size():
			zooms[data.feature_label_min_zoom[i] + float(FEATURE_STYLES[data.feature_label_kinds[i]][4])] = true
		_feature_thresholds = PackedFloat64Array(zooms.keys())
		_feature_thresholds.sort()
	# How many of the zooms they show from it's past: only when that changes do
	# the ones that show change (dragging, or zooming between them, the same ones).
	var level := _feature_thresholds.bsearch(web_zoom, false)
	if level != _features_level:
		_features_level = level
		_features_shown = PackedInt32Array()
		for i in _feature_order:
			if data.feature_label_min_zoom[i] + float(FEATURE_STYLES[data.feature_label_kinds[i]][4]) <= web_zoom:
				_features_shown.append(i)
		# Sorted into cells of the globe, so only those near the view are looked at.
		_feature_cells.clear()
		for rank in _features_shown.size():
			var cell := _label_cell(Geo.unproject(data.feature_label_positions[_features_shown[rank]]))
			if not _feature_cells.has(cell):
				_feature_cells[cell] = PackedInt32Array()
			_feature_cells[cell].append(rank)
	var ranks := _ranks_near_view(_feature_cells)
	ranks.sort()  # (Back in priority order.)
	var bounds := Rect2(Vector2.ZERO, size)
	var near := bounds.grow(LABEL_REACH_PX)
	var labels := []
	for rank in ranks:
		var i := _features_shown[rank]
		var kind := data.feature_label_kinds[i]
		var style: Array = FEATURE_STYLES[kind]
		var center := _unit_to_screen(_feature_units[i])
		if not near.has_point(center):
			continue  # (Cheapest first: most are well off screen.)
		var text_size := _label_size(_feature_font(kind), _feature_text(i), style[0])
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
		if _marina_shown(port_id):
			return  # Grown into its marina (see _update_marinas()), locked or not.
		if _port_locked(port_id):
			# In a locked region: a small faint dot, no more.
			_canvas.draw_circle(pos, PORT_RADIUS_MIN, locked_fill)
			return
		var port_fill := fill if price_commodity.is_empty() else _price_color(port_id)
		if selectable_ports.get(port_id) is Color:
			port_fill = selectable_ports[port_id]
		var radius := _port_radius(port_id)
		var shining := shining_ports.has(port_id)
		if shining:
			for ring in SHINE_RINGS:
				_canvas.draw_circle(pos, radius + float(ring[0]), Color(port_fill, float(ring[1])))
		_canvas.draw_circle(pos, radius, dimmed if dimmed_ports.has(port_id) else port_fill)
		_canvas.draw_arc(pos, radius, 0.0, TAU, 24, outline, 1.5, true)
		if shining:
			_canvas.draw_circle(pos + Vector2(-0.35, -0.35) * radius, radius * 0.3, Color(1.0, 1.0, 1.0, 0.85))
		if port_id == selected_port:
			_canvas.draw_arc(pos, radius + 4.0, 0.0, TAU, 32, SELECTED_RING, 3.0, true)
	# Every company's HQ and hubs (other players' too, in multiplayer; none while
	# picking a port, before there's a company).
	var hub_ports := {}  # Port id -> [[hub, its company's ring color], ...]
	for each in GameState.all_companies() if selectable_ports.is_empty() else []:
		var each_color := _color(&"hub_ring_gray") if gray_mode else GameState.company_color_value(each.color)
		for hub in each.hubs:
			(hub_ports.get_or_add(hub.port_id, []) as Array).append([hub, each_color])
	for i in _ports_near_view():
		var port: Dictionary = GameData.ports[i]
		if not hub_ports.has(port.id):
			draw_port.call(port.id)
	# The HQ and hubs go on top of the other ports, each with a ring in its
	# company's color (heavier for an HQ); companies sharing a port ring it in
	# turn. Not once its marina shows: that has its slip (and an HQ building).
	for port_id: String in hub_ports:
		draw_port.call(port_id)
		if _marina_shown(port_id):
			continue
		var radius := _port_radius(port_id) + 1.0
		for entry: Array in hub_ports[port_id]:
			var width := HQ_RING_WIDTH if entry[0].is_hq else HUB_RING_WIDTH
			_canvas.draw_arc(port_screen_position(port_id), radius + width / 2.0, 0.0, TAU, clampi(int(radius), 32, 128), entry[1], width, true)
			radius += width
	for label: Array in labels:
		var rect: Rect2 = label[1]
		var baseline := rect.position + Vector2(0, font.get_ascent(PORT_FONT_SIZE))
		var text: String = GameData.port_name(label[0])
		var color := dimmed if dimmed_ports.has(label[0]) or _port_locked(label[0]) else label_color  # (Locked regions' ports named, but dimmed.)
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
	for lane: Array in _active_lanes():
		_draw_lane(lane[0], lane[1], lane[2], false, ACTIVE_LANE_WIDTH, lane[3])


## The lanes _draw_active_lanes() draws: [from, to, color, sailed both ways],
## other players' first. Kept for half a STATIC_REFRESH_S (so each redraw while
## the view's still works them out afresh), not every frame it's dragged.
func _active_lanes() -> Array:
	var now := Time.get_ticks_msec()
	if now - _active_lanes_time < STATIC_REFRESH_S * 500.0 and _active_lanes_time >= 0:
		return _active_lanes_cache
	_active_lanes_time = now
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
				into[key] = [leg[0], leg[1], color, false]
			elif into[key][0] != leg[0]:
				into[key][3] = true  # (Sailed both ways: the way back's harbour curves too.)
	_active_lanes_cache = others.values() + lanes.values()
	return _active_lanes_cache


## A lane from one port to another as ships sail it: where a port's marina
## shows, off the lane and round to its harbour mouth on the right-hand side
## (the ships' own curves, see _harbour_pose()) and in through its entrance,
## stopping there, where they part for their berths. `both_ways`: the way
## back too, its curves only (sharing this one's middle).
func _draw_lane(from_port: String, to_port: String, color: Color, dashed: bool, width := 2.5, both_ways := false) -> void:
	var sea_lane = GameData.lane(from_port, to_port)
	if sea_lane == null:
		return
	var pieces := _lane_pieces(sea_lane, from_port, to_port)
	var line := PackedVector2Array()
	for piece: PackedVector2Array in pieces:
		line.append_array(piece)
	_draw_line_runs(line, color, dashed, width)
	if both_ways:
		var back = GameData.lane(to_port, from_port)
		if back != null:
			var back_pieces := _lane_pieces(back, to_port, from_port)
			_draw_line_runs(back_pieces[0], color, dashed, width)
			_draw_line_runs(back_pieces[2], color, dashed, width)


## A lane on screen in three pieces: the curve out of its first port's
## harbour, the lane between, and the curve into its last port's (the curves
## empty where a port's marina doesn't show, the lane then running on to it).
func _lane_pieces(sea_lane, from_port: String, to_port: String) -> Array[PackedVector2Array]:
	# Its points (bent round other ports' harbours: see _bent_lane()) on the
	# sphere are worked out once.
	var bent := _bent_lane(sea_lane, from_port, to_port)
	var lane_miles: PackedFloat64Array = bent.miles
	var units: PackedVector3Array = _lane_units.get(sea_lane, PackedVector3Array())
	if units.is_empty():
		for p: Vector2 in bent.points:
			units.append(_unit(p))
		_lane_units[sea_lane] = units
		_lane_caps[sea_lane] = _chunk_caps(units)
	var length: float = sea_lane.length()
	var near := Rect2(Vector2.ZERO, size).grow(size.length() / 2.0)
	var shows := [false, false]  # (Arriving, leaving: where its port's marina shows, it curves in.)
	var curved := false
	for i in 2:
		var port := to_port if i == 0 else from_port
		var root := port_screen_position(port)
		shows[i] = not _is_hidden(root) and near.has_point(root) and _marina_shown(port)
		curved = curved or shows[i]
	var curves: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]  # [in, out]
	var reaches := PackedFloat32Array([0.0, 0.0])
	if curved:
		# The curves only change with the zoom, not as the map's dragged: worked
		# out once a zoom (and again once the view's moved a degree), kept on the
		# globe and only put on screen each frame.
		if _lane_reach_zoom != _zoom:
			_lane_reach_zoom = _zoom
			_lane_reach_memo.clear()
		var memo_key := "%s>%s %s %s" % [from_port, to_port, shows[0], shows[1]]
		var memo: Array = _lane_reach_memo.get(memo_key, [])
		if memo.is_empty() or (_center - (memo[2] as Vector2)).length() > LANE_CURVE_DRIFT:
			var ends := []
			for i in 2:
				var port := to_port if i == 0 else from_port
				ends.append(_keep_right(port, _entrance_pose(port, false, i == 0)) if shows[i] else [])
			memo = [_lane_reaches(sea_lane, length, to_port, from_port, ends)[0].duplicate(), [PackedVector3Array(), PackedVector3Array()], _center]
			for i in 2:
				if memo[0][i] <= 0.0:
					continue
				var curve := _lane_curve(sea_lane, from_port, to_port, length, i == 0, memo[0][i], ends[i])
				if curve.is_empty():
					memo[0][i] = 0.0  # (Round the far side: straight in.)
					continue
				var points: PackedVector2Array = curve[0]
				# On in through the entrance itself (from just outside the mouth), where
				# ships part for their berths.
				var port := to_port if i == 0 else from_port
				var layout := _port_layout(port)
				var gate := _keep_right(port, _entrance_pose(port, false, i == 0, float(layout.radius) / (layout.mouth as Vector2).x))
				if i == 0:
					points.append(gate[0])
				else:
					points.insert(0, gate[0])
				var on_globe := PackedVector3Array()
				for p in points:
					on_globe.append(_screen_unit(p))
				memo[1][i] = on_globe
			_lane_reach_memo[memo_key] = memo
		reaches = memo[0]
		for i in 2:
			for p: Vector3 in memo[1][i]:
				curves[i].append(_unit_to_screen(p))
	var middle := PackedVector2Array()
	var start := reaches[1]
	var stop := length - reaches[0]
	if start > 0.0:
		middle.append(world_to_screen(_bent_sample(sea_lane, from_port, to_port, start)[0]))
	# A chunk of it that can't be in view (all of it, and the way on to the next,
	# round the far side or off the edge) isn't worked out, just broken off.
	if not _lane_caps.has(sea_lane):
		_lane_caps[sea_lane] = _chunk_caps(units)
	var caps: Array = _lane_caps[sea_lane]
	var centers: PackedVector3Array = caps[0]
	var spans: PackedFloat64Array = caps[1]
	var view_angle := asin(minf((size.length() / 2.0 + 8.0) / _radius(), 1.0))
	for c in centers.size():
		var first := c * LANE_CHUNK
		if centers[c].dot(_toward) < cos(minf(view_angle + spans[c], PI)):
			if not middle.is_empty() and not _is_hidden(middle[-1]):
				middle.append(HIDDEN)
			continue
		for k in range(first, mini(first + LANE_CHUNK, units.size())):
			var mile: float = lane_miles[k]
			if (mile > start or start <= 0.0 and k == 0) and (mile < stop or reaches[0] <= 0.0 and k == units.size() - 1):
				middle.append(_unit_to_screen(units[k]))
	if reaches[0] > 0.0:
		middle.append(world_to_screen(_bent_sample(sea_lane, from_port, to_port, stop)[0]))
	return [curves[1], middle, curves[0]]


# --- Lanes bent round other ports' harbours --------------------------------------

## Each port's keep-out zone (see _port_zones()) and the bent lanes made with
## them (see _bent_lane()); and when the zones were last checked (ms).
var _zones: Array = []
var _zone_cells := {}
var _bent_lanes := {}
var _zones_checked := -1


## Every port's keep-out zone, round its marina and its approach curves: [(lon,
## lat), radius (degrees), port id], those of ports on a canal left out (a
## canal's lanes stay in it). Marinas are a fixed size in the world, so the
## zones are too; checked again every ZONE_CHECK_S, as ports grow and hubs
## come and go, and the bent lanes made again if they've changed.
func _port_zones() -> Array:
	var now := Time.get_ticks_msec()
	if _zones_checked >= 0 and now - _zones_checked < ZONE_CHECK_S * 1000.0:
		return _zones
	_zones_checked = now
	var zones := []
	for port: Dictionary in GameData.ports:
		var port_id: String = port.id
		if _is_canal_port(port_id):
			continue
		var layout := _port_layout(port_id)
		var reach := (layout.mouth as Vector2).x * ZONE_MOUTHS / SHIP_WORLD_ZOOM
		zones.append([Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))), reach, port_id])
	if zones != _zones:
		_zones = zones
		_zone_cells.clear()
		for i in zones.size():
			var cell := _label_cell(zones[i][0])
			if not _zone_cells.has(cell):
				_zone_cells[cell] = PackedInt32Array()
			_zone_cells[cell].append(i)
		_bent_lanes.clear()
		_lane_units.clear()
		_lane_caps.clear()
		_lane_reach_memo.clear()
	return _zones


## The zones near a (lon, lat) point (within a cell of it).
func _zones_near(lon_lat: Vector2) -> PackedInt32Array:
	var out := PackedInt32Array()
	var cell := _label_cell(lon_lat)
	var columns := ceili(360.0 / LABEL_CELL_DEG)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			out.append_array(_zone_cells.get(Vector2i(posmod(cell.x + dx, columns), cell.y + dy), PackedInt32Array()))
	return out


## A lane as it's drawn and sailed on the map: bent out round the harbours of
## ports it passes but isn't sailing to, so it doesn't cut through their
## marinas, jetties or approach curves (the ships' way in and out), pushed out
## smoothly to the edge of each one's zone (ZONE_MOUTHS times its mouth's
## distance from the port). Not near its own ports, nor in a canal, nor onto
## the land (where the sea's too narrow, it doesn't bend). Its points are the
## lane's, with more where it bends, each at the same mile along it as before,
## so ships take just as long: {points (projected), miles, bent (1 where a
## point was moved)}. Made once.
func _bent_lane(sea_lane, from_port: String, to_port: String) -> Dictionary:
	_port_zones()
	if _bent_lanes.has(sea_lane):
		return _bent_lanes[sea_lane]
	var ends := []
	for port_id: String in [from_port, to_port]:
		var port := GameData.get_port(port_id)
		var reach := _zone_reach(port_id)
		ends.append([Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0))), reach])
	var points := PackedVector2Array()
	var miles := PackedFloat64Array()
	var bent := PackedByteArray()
	var from_points := PackedVector2Array()  # (lon, lat): as the lane goes, and pushed out.
	var to_points := PackedVector2Array()
	var lane_points: PackedVector2Array = sea_lane.points
	var lane_miles: PackedFloat64Array = sea_lane.miles
	for i in lane_points.size():
		# More points along a stretch passing near a zone, so it bends smoothly.
		var steps := 1
		if i > 0:
			var a := Geo.unproject(lane_points[i - 1])
			var b := Geo.unproject(lane_points[i])
			if _near_zone(a, b, from_port, to_port):
				steps = maxi(ceili(a.distance_to(b) / ZONE_STEP_DEG), 1)
		for s in range(1 if i > 0 else 0, steps + 1):
			var share := float(s) / steps
			var at := lane_points[i] if i == 0 or s == steps else lane_points[i - 1].lerp(lane_points[i], share)
			var mile := lane_miles[i] if i == 0 or s == steps else lerpf(lane_miles[i - 1], lane_miles[i], share)
			var lon_lat := Geo.unproject(at)
			from_points.append(lon_lat)
			to_points.append(_bend(lon_lat, from_port, to_port, ends))
			points.append(at)
			miles.append(mile)
	# How far each point may go before it reaches the land (the map's own land,
	# islands and all: see _on_land()), smoothed along the lane so it bends
	# smoothly and stays off the land: where the sea's too narrow (a strait),
	# hardly at all. A small push is let be.
	_land_ready()
	var room := PackedFloat32Array()
	for k in points.size():
		var share := 1.0
		if from_points[k].distance_to(to_points[k]) > ZONE_FREE_DEG and _on_land(to_points[k]):
			var low := 0.0
			var high := 1.0
			for step in 5:
				var mid := (low + high) / 2.0
				if _on_land(from_points[k].lerp(to_points[k], mid)):
					high = mid
				else:
					low = mid
			share = low
		room.append(share)
	room = _smoothed(_least_near(room, ZONE_SMOOTH_POINTS / 2), ZONE_SMOOTH_POINTS)
	for k in points.size():
		if from_points[k] != to_points[k] and room[k] > 0.0:
			points[k] = Geo.project(from_points[k].lerp(to_points[k], room[k]))
			bent.append(1)
		else:
			bent.append(0)
	var made := {points = points, miles = miles, bent = bent}
	_bent_lanes[sea_lane] = made
	return made


## True if a (lon, lat) point is on the land, as the map draws it (islands
## and all): in one of its land triangles, looked up by LAND_CELL_DEG cell.
static func _on_land(lon_lat: Vector2) -> bool:
	var p := Geo.project(Vector2(wrapf(lon_lat.x, -180.0, 180.0), lon_lat.y))
	var triangles := GameData.world_map.land_triangles
	for i: int in _land_cells.get(Vector2i(floori(p.x / LAND_CELL_DEG), floori(p.y / LAND_CELL_DEG)), PackedInt32Array()):
		if Geometry2D.point_is_inside_triangle(p, triangles[i], triangles[i + 1], triangles[i + 2]):
			return true
	return false


## Starts sorting the land's triangles into cells (see _on_land()) off the
## main thread, once (it takes a moment: there are some 180,000).
static func _start_land_cells() -> void:
	if _land_task < 0 and _land_cells.is_empty():
		_land_task = WorkerThreadPool.add_task(_build_land_cells, false, "Land cells")


static func _build_land_cells() -> void:
	var cells := {}
	var triangles := GameData.world_map.land_triangles
	for i in range(0, triangles.size(), 3):
		var box := Rect2(triangles[i], Vector2.ZERO).expand(triangles[i + 1]).expand(triangles[i + 2])
		for x in range(floori(box.position.x / LAND_CELL_DEG), floori(box.end.x / LAND_CELL_DEG) + 1):
			for y in range(floori(box.position.y / LAND_CELL_DEG), floori(box.end.y / LAND_CELL_DEG) + 1):
				var cell := Vector2i(x, y)
				if not cells.has(cell):
					cells[cell] = PackedInt32Array()
				cells[cell].append(i)
	_land_cells = cells


## Waits for the land's cells (see _start_land_cells()), if they're still being made.
static func _land_ready() -> void:
	if _land_task < 0 and _land_cells.is_empty():
		_start_land_cells()
	if _land_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_land_task)
		_land_task = -1


## Each value as the least within `reach` places either side of it.
static func _least_near(values: PackedFloat32Array, reach: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	for i in values.size():
		var least := values[i]
		for j in range(maxi(i - reach, 0), mini(i + reach + 1, values.size())):
			least = minf(least, values[j])
		out[i] = least
	return out


## Each value as the average of those within `reach` places either side of it.
static func _smoothed(values: PackedFloat32Array, reach: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	for i in values.size():
		var total := 0.0
		var count := 0
		for j in range(maxi(i - reach, 0), mini(i + reach + 1, values.size())):
			total += values[j]
			count += 1
		out[i] = total / count
	return out


## A port's keep-out zone's radius (degrees), or 0 for one without (on a canal).
func _zone_reach(port_id: String) -> float:
	for zone: Array in _port_zones():
		if zone[2] == port_id:
			return zone[1]
	return 0.0


## True if a stretch of lane from a to b (lon, lat) comes within reach of a
## zone it bends round.
func _near_zone(a: Vector2, b: Vector2, from_port: String, to_port: String) -> bool:
	var indices := _zones_near(a)
	indices.append_array(_zones_near(b))
	for i in indices:
		var zone: Array = _zones[i]
		if zone[2] == from_port or zone[2] == to_port:
			continue
		var center: Vector2 = zone[0]
		var squash := cos(deg_to_rad(center.y))
		var pa := Vector2(wrapf(a.x - center.x, -180.0, 180.0) * squash, a.y - center.y)
		var pb := Vector2(wrapf(b.x - center.x, -180.0, 180.0) * squash, b.y - center.y)
		if Geometry2D.get_closest_point_to_segment(Vector2.ZERO, pa, pb).length() < float(zone[1]) * 2.0 + ZONE_STEP_DEG:
			return true
	return false


## A lane's (lon, lat) point bent out of the zones of the ports near it it
## isn't sailing to (`ends`: its own two ports' [(lon, lat), zone radius]):
## inside twice a zone's radius, pushed out from its port, by the radius right
## at the port and less and less further out, reaching nothing at twice the
## radius (smoothly, so the lane curves round it). The push fades out near its
## own ports (it comes in to them as it was) and in canals.
func _bend(lon_lat: Vector2, from_port: String, to_port: String, ends: Array) -> Vector2:
	var out := lon_lat
	for i in _zones_near(lon_lat):
		var zone: Array = _zones[i]
		if zone[2] == from_port or zone[2] == to_port:
			continue
		var center: Vector2 = zone[0]
		var reach: float = zone[1]
		var squash := maxf(cos(deg_to_rad(center.y)), 0.05)
		var off := Vector2(wrapf(out.x - center.x, -180.0, 180.0) * squash, out.y - center.y)
		var d := off.length()
		if d >= reach * 2.0:
			continue
		var push := (reach * 2.0 - d) * (reach * 2.0 - d) / (4.0 * reach)
		var way := off / d if d > 0.000001 else Vector2.RIGHT
		out += Vector2(way.x * push / squash, way.y * push)
	if out == lon_lat:
		return lon_lat
	# Fading out near its own ports and in canals.
	var weight := 1.0
	for end: Array in ends:
		var center: Vector2 = end[0]
		var squash := cos(deg_to_rad(center.y))
		var d := Vector2(wrapf(lon_lat.x - center.x, -180.0, 180.0) * squash, lon_lat.y - center.y).length()
		var own := maxf(float(end[1]), 0.05)
		weight = minf(weight, smoothstep(own * 0.25, own * 0.6, d))
	if weight <= 0.0 or _in_canal(lon_lat):
		return lon_lat
	# (Pushed away from a port on the coast, a lane goes out to sea: no check
	# against the land, which on the coarse sea map would leave it jagged.)
	return lon_lat.lerp(out, weight)


## True if a (lon, lat) point is in or by a canal (its path's box, a little grown).
func _in_canal(lon_lat: Vector2) -> bool:
	if _canal_boxes.is_empty():
		for canal: Dictionary in GameData.canals:
			var path: Array = canal.get("path", [])
			if path.is_empty():
				continue
			var box := Rect2(Vector2(path[0][0], path[0][1]), Vector2.ZERO)
			for point: Array in path:
				box = box.expand(Vector2(point[0], point[1]))
			_canal_boxes.append(box.grow(0.5))
	for box: Rect2 in _canal_boxes:
		if box.has_point(lon_lat):
			return true
	return false


## Where along a bent lane (_bent_lane()) a ship `mile` along it is, and which
## way it's heading: [projected position, direction], as the lane's own
## sample() where it isn't bent.
func _bent_sample(sea_lane, from_port: String, to_port: String, mile: float) -> Array:
	var made := _bent_lane(sea_lane, from_port, to_port)
	var miles: PackedFloat64Array = made.miles
	var points: PackedVector2Array = made.points
	var bent: PackedByteArray = made.bent
	mile = clampf(mile, 0.0, sea_lane.length())
	var i := clampi(miles.bsearch(mile), 1, points.size() - 1)
	if bent[i] == 0 and bent[i - 1] == 0:
		return sea_lane.sample(mile)
	var span := miles[i] - miles[i - 1]
	var t := (mile - miles[i - 1]) / span if span > 0.0 else 1.0
	var at := points[i - 1].lerp(points[i], t)
	# Its heading: the way the bent lane goes a little either side of it.
	var ahead := _bent_point(made, minf(mile + ZONE_HEADING_NM, sea_lane.length()))
	var behind := _bent_point(made, maxf(mile - ZONE_HEADING_NM, 0.0))
	var way := ahead - behind
	return [at, way.normalized() if way.length() > 0.000001 else sea_lane.sample(mile)[1]]


static func _bent_point(made: Dictionary, mile: float) -> Vector2:
	var miles: PackedFloat64Array = made.miles
	var points: PackedVector2Array = made.points
	var i := clampi(miles.bsearch(mile), 1, points.size() - 1)
	var span := miles[i] - miles[i - 1]
	return points[i - 1].lerp(points[i], (mile - miles[i - 1]) / span if span > 0.0 else 1.0)


## Where a ship is on the map (projected), as drawn: on its lane bent round
## other ports' harbours (see _bent_lane()); a carried or towed one with its
## rescuer; docked, at its port.
func _ship_world(ship: Ship) -> Vector2:
	if ship.is_carried() or ship.is_towed():
		return _ship_world(ship.rescuer)
	var here := _ship_bent(ship)
	return here[0] if not here.is_empty() else ship.world_position()


## Which way a ship's heading on the map (projected), as drawn: along its bent
## lane (see _ship_world()), unless it's turning about (Ship.heading()).
func _ship_heading(ship: Ship) -> Vector2:
	if ship.is_carried():
		return -_ship_heading(ship.rescuer) if ship.rescuer.carry_flipped() else _ship_heading(ship.rescuer)
	if ship.is_towed():
		return _ship_heading(ship.rescuer)
	if ship.job_phase == Ship.JOB_ALIGN:
		return ship.heading()
	var here := _ship_bent(ship)
	return here[1] if not here.is_empty() else ship.heading()


## A ship's place on its bent lane ([position, direction]), or [] off a lane.
func _ship_bent(ship: Ship) -> Array:
	if ship.is_docked() or ship.from_port.is_empty() or ship.to_port.is_empty():
		return []
	var sea_lane = GameData.lane(ship.from_port, ship.to_port)
	if sea_lane == null:
		return []
	return _bent_sample(sea_lane, ship.from_port, ship.to_port, ship.traveled_nm)


## A line's points on the sphere in chunks of LANE_CHUNK (each with the next
## chunk's first point too, so it covers the way on): [each chunk's middle,
## how far (radians) its furthest point is from it].
static func _chunk_caps(units: PackedVector3Array) -> Array:
	var centers := PackedVector3Array()
	var spans := PackedFloat64Array()
	for first in range(0, units.size(), LANE_CHUNK):
		var last := mini(first + LANE_CHUNK, units.size() - 1)
		var middle := Vector3.ZERO
		for k in range(first, last + 1):
			middle += units[k]
		middle = middle.normalized() if middle.length() > 0.000001 else units[first]
		var furthest := 0.0
		for k in range(first, last + 1):
			furthest = maxf(furthest, middle.angle_to(units[k]))
		centers.append(middle)
		spans.append(furthest)
	return [centers, spans]


## A line on screen, drawn on the near side of the globe only.
func _draw_line_runs(points: PackedVector2Array, color: Color, dashed: bool, width: float) -> void:
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


## The tow lines from each tug pulling a ship (at sea, or in to its berth) to
## the ship's bow: two in a Y.
func _draw_tow_lines() -> void:
	for tug in GameState.ships:
		if not tug.is_tug() or tug.rescuing == null or not _tug_pulling(tug):
			continue
		var ship := tug.rescuing
		var tug_rect: Rect2 = _model_look(tug.model_id)[7]
		var ship_rect: Rect2 = _model_look(ship.model_id)[7]
		var stern := ship_screen_position(tug) - Vector2.from_angle(_screen_angle(tug)) * tug_rect.size.x / 2.0 * _ship_scale()
		var bow := ship_screen_position(ship) + Vector2.from_angle(_screen_angle(ship)) * ship_rect.size.x / 2.0 * _ship_scale()
		_canvas.draw_line(stern, bow, TOW_LINE_COLOR, maxf(0.25 * _ship_scale(), 1.0), true)


## True if a tug has its ship on its tow line now: towing it at sea, or
## pulling it in through its harbour (see _tug_work()).
func _tug_pulling(tug: Ship) -> bool:
	if tug.job_phase == Ship.JOB_TOW:
		return true
	if tug.job_phase != Ship.JOB_BERTH or not docks_shown():
		return false
	var work := _tug_work(tug)
	if work.is_empty():
		return false
	var index: int = (work.team as Array).find(tug)
	var seg := _work_segment(work.tugs[index], _work_time(tug))
	return seg.kind == "follow"

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
		var here := _ship_bent(ship)
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
	var open := _hatch_open(ship) if art.has("hatches") else 0.0
	if open > 0.0:
		_draw_hatches(ship, art.hatches, rect, open, fade)
		_canvas.draw_texture_rect(art.open_details, rect, false, fade)
		return
	_canvas.draw_texture_rect(art.details, rect, false, fade)


## How far open a bulk carrier's hatches are (0 shut to 1 open): moored for
## its stop, they fold open over its first HATCH_S and shut over its last
## (a fifth of a short stop each), shut otherwise.
static func _hatch_open(ship: Ship) -> float:
	if not ship.is_docking() or ship.berth < 0 or ship.berth_phase != Ship.BERTH_NONE:
		return 0.0
	var stop := ship.dock_seconds()
	var takes := minf(HATCH_S, stop * 0.2)
	if takes <= 0.0:
		return 0.0
	return minf(smoothstep(0.0, takes, ship.dock_time), smoothstep(0.0, takes, stop - ship.dock_time))


## A bulk carrier's hatches `open` of the way open (see HATCHES), on its art
## (`rect`): each hold, its cargo showing as full as it is (dark empty), and
## its two covers folding away from over it to either side (or fore and aft),
## stacking up narrower as they go.
func _draw_hatches(ship: Ship, hatches: Dictionary, rect: Rect2, open: float, fade: Color) -> void:
	var to_rect := rect.size / Vector2(SHIP_ART_WIDTH, 52.0)
	var place := func(box: Rect2) -> Rect2: return Rect2(rect.position + box.position * to_rect, box.size * to_rect)
	var cargo := Color.from_string(str(HOLD_COLORS.get(ship.cargo_id, "")), EMPTY_HOLD)
	var hold := EMPTY_HOLD.lerp(cargo, clampf(ship.cargo_level() * 1.4, 0.0, 1.0)) * fade
	var fill := Color.from_string(str(hatches.fill), Color.GRAY) * fade
	var edge := Color.from_string(str(hatches.edge), Color.BLACK) * fade
	var width := float(hatches.width)
	var across: Vector2 = hatches.across
	var line := maxf(0.6 * to_rect.y, 0.4)
	for start: float in hatches.starts:
		_canvas.draw_rect(place.call(Rect2(start + 0.6, across.x + 0.6, width - 1.2, across.y - across.x - 1.2)), hold)
		var covers: Array[Rect2] = []
		if str(hatches.part) == "y":
			# Rolling off to either side, onto the deck.
			var half := (across.y - across.x) / 2.0
			var tall := lerpf(half, half * 0.3, open)
			var top := lerpf(across.x, 4.6, open)
			var bottom := lerpf(across.y, 47.4, open)
			covers = [Rect2(start, top, width, tall), Rect2(start, bottom - tall, width, tall)]
		else:
			# Folding fore and aft into the gaps between the hatches.
			var half := width / 2.0
			var wide := lerpf(half, half * 0.3, open)
			var aft := lerpf(start, start - 2.6, open)
			var fore := lerpf(start + width, start + width + 2.6, open)
			covers = [Rect2(aft, across.x, wide, across.y - across.x), Rect2(fore - wide, across.x, wide, across.y - across.x)]
		for cover in covers:
			var box: Rect2 = place.call(cover)
			_canvas.draw_rect(box, fill)
			_canvas.draw_rect(box, edge, false, line)
			if open > 0.25:
				# Folded: its panels stacked, a line between each.
				var mid := box.get_center()
				var along_y := str(hatches.part) == "y"
				var from := Vector2(box.position.x, mid.y) if along_y else Vector2(mid.x, box.position.y)
				var to := Vector2(box.end.x, mid.y) if along_y else Vector2(mid.x, box.end.y)
				_canvas.draw_line(from, to, edge, line * 0.8)


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
	if HATCHES.has(category) and ResourceLoader.exists(path % "details_open"):
		art.open_details = load(path % "details_open")  # (Its hatch covers drawn as they open: see _draw_hatches().)
		art.hatches = HATCHES[category]
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
		# On the unit sphere, and its clearance over its spot's cosh (see
		# _local_zoom()), worked out once: they never move, and there are many.
		_decor_units.append(_unit(p))
		_decor_room.append(data.decor_clearance[i] / cosh(deg_to_rad(p.y)) if i < data.decor_clearance.size() else INF)


## The little drawings on the land (WorldMapData decor: mountains, trees,
## cacti, animals...), on the full-color map only. Every tier whose spacing is
## at least DECOR_MIN_SPACING_PX apart on screen shows, so more appear as the
## map zooms in; each is drawn standing on its spot, a fixed size on screen
## (a little bigger zoomed in), the lower ones in front.
func _draw_decor() -> void:
	_canvas = _decor_layer
	_fauna.clear()
	if gray_mode:
		return
	var animals := Birds.shared().land_animals
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
	# Each kind's size, the zoom it shows from and (an animal's) its species, and
	# each region's lock, worked out once here: there are thousands of drawings.
	var kind_sides := PackedFloat64Array()
	var kind_min_zooms := PackedFloat64Array()
	var kind_infos := []
	for kind_name in data.decor_kind_names:
		kind_sides.append(_decor_side(kind_name, scale))
		kind_min_zooms.append(float(DECOR_MIN_ZOOM.get(kind_name, 0.0)))
		kind_infos.append(animals.get(kind_name, {}))
	var check_locks := RegionMap.is_ready() and selectable_ports.is_empty()
	var locks := {}  # Region (as _decor_regions has it) -> locked.
	if check_locks:
		_decor_locked(0)  # (Sorts the drawings into their regions, the first time.)
	for column in range(first_column, last_column + 1):
		for row in range(floori(low.y / DECOR_BUCKET), floori(high.y / DECOR_BUCKET) + 1):
			for i: int in _decor_buckets.get(Vector2i(posmod(column, columns), row), PackedInt32Array()):
				if data.decor_tiers[i] > max_tier:
					continue
				if check_locks:
					var region: int = _decor_regions[i]
					if not locks.has(region):
						locks[region] = _decor_locked(i)
					if locks[region]:
						continue  # Its region is locked: shaded, bare.
				var kind := data.decor_kinds[i]
				if center_zoom < kind_min_zooms[kind]:
					continue  # Not yet: it shows only from closer in.
				var at := _unit_to_screen(_decor_units[i])
				if not screen.has_point(at):
					continue
				# Only while all of it fits clear of the water (land drawings on land, waves
				# on the sea): its corners reach about its size from its spot.
				var side := kind_sides[kind]
				var room := _decor_room[i] * _zoom
				if room < side * 1.05:
					continue
				var info: Dictionary = kind_infos[kind]
				if info.has("group"):
					var kind_name := data.decor_kind_names[kind]
					# A group roaming its patch (see _draw_fauna()), as much of it as
					# keeps it on land.
					var roam := float(info.get("roam", 2.0)) * side
					var fit := clampf(maxf(room - side * 1.05, side * 1.2) / roam, 0.0, 1.0)
					_fauna.append(["%d" % i, _decor_textures[data.decor_kinds[i]], at, side, fit, info, _decor_texture(str(info.get("tree", ""))), kind_name])
					continue
				shown.append([at, data.decor_kinds[i]])
	shown.sort_custom(func(p: Array, q: Array) -> bool: return p[0].y < q[0].y)
	for item: Array in shown:
		var texture := _decor_textures[item[1]]
		if texture == null:
			continue
		var side := kind_sides[item[1]]
		_canvas.draw_texture_rect(texture, Rect2(item[0] - Vector2(side / 2.0, side * 0.92), Vector2(side, side)), false)


## How big a kind of drawing is on screen (px): mountains biggest, then
## animals (and waves), then plants and rocks.
static func _decor_side(kind_name: String, scale: float) -> float:
	var big := DECOR_ANIMALS.has(kind_name) or kind_name == "waves"
	return (DECOR_SIZE_PX.y if kind_name.begins_with("mountain") else (DECOR_SIZE_PX.z if big else DECOR_SIZE_PX.x)) * scale


## A land drawing's art by its name (as _load_decor() loaded it), or null.
static func _decor_texture(kind_name: String) -> Texture2D:
	var index := GameData.world_map.decor_kind_names.find(kind_name)
	return _decor_textures[index] if index >= 0 and index < _decor_textures.size() else null


## The land animals in view (_fauna, found by _draw_decor()), each group
## roaming its patch and going about its day (LandLife): drawn standing on
## their feet, the nearer ones in front, a bear's rubbing tree behind it, with
## whatever goes with what they're doing (sleepers' z's, an elephant's spray,
## a roar...). They keep going while the game's paused, like the birds.
func _draw_fauna() -> void:
	_canvas = _fauna_layer
	var now := Time.get_ticks_msec() / 1000.0
	_fauna_hits.clear()
	var items := []  # [feet y, texture, pose, feet (screen), art side (px), info]
	for group: Array in _fauna:
		var key: String = group[0]
		var texture: Texture2D = group[1]
		var home: Vector2 = group[2]
		var side: float = group[3]
		var fit: float = group[4]
		var info: Dictionary = group[5]
		if texture == null:
			continue
		var tree: Variant = LandLife.tree_spot(key, info)
		if tree != null and group[6] != null:
			var foot := home + (tree as Vector2) * side * fit
			items.append([foot.y - 0.01, group[6], null, foot, side, info])
		for pose: Dictionary in _land_life.poses(key, info, now):
			var feet := home + (pose.at as Vector2) * side * fit
			items.append([feet.y, texture, pose, feet, side, info, group[7]])
			var art := side * float(pose.size)
			_fauna_hits.append([feet - Vector2(0.0, art * 0.45), maxf(art * 0.5, BIRD_HIT_MIN_PX), key, group[7]])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for item: Array in items:
		var side: float = item[4]
		if item[2] == null:
			_canvas.draw_texture_rect(item[1], Rect2(item[3] - Vector2(side / 2.0, side * LandLife.FEET), Vector2(side, side)), false)
			continue
		_draw_land_animal(_animal_frame(str(item[6]), str((item[2] as Dictionary).get("frame", "")), item[1]), item[2], item[3], side, item[5])
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A land animal's drawing for a frame of its pose (LandLife: "step", its
## legs swung, or "fly", wings out; art/decor/<kind>_<frame>.svg), or its
## own (`texture`) for "" or one it hasn't. Loaded once.
static func _animal_frame(kind_name: String, frame: String, texture: Texture2D) -> Texture2D:
	if frame.is_empty():
		return texture
	var key := kind_name + "_" + frame
	if not _animal_frames.has(key):
		var path := DECOR_ART_DIR + key + ".svg"
		_animal_frames[key] = load(path) if ResourceLoader.exists(path) else null
	var found: Texture2D = _animal_frames[key]
	return found if found != null else texture


## The land animal group drawn under a screen point (the nearest one in
## front): [patch key, species], or [].
func _animals_at(screen_pos: Vector2) -> Array:
	for i in range(_fauna_hits.size() - 1, -1, -1):
		var hit: Array = _fauna_hits[i]
		if (hit[0] as Vector2).distance_to(screen_pos) <= float(hit[1]):
			return [hit[2], hit[3]]
	return []


## Where a land animal group's patch is on screen, or Vector2.INF while it isn't drawn.
func animal_group_screen_position(key: String) -> Vector2:
	for group: Array in _fauna:
		if group[0] == key:
			return group[2]
	return Vector2.INF


## One animal in its pose (LandLife.poses()), its feet at a screen point, its
## art `side` px for a full-sized one: turned the way it faces, about its
## pivot, then what goes with its act.
func _draw_land_animal(texture: Texture2D, pose: Dictionary, feet: Vector2, side: float, info: Dictionary) -> void:
	var art := side * float(pose.size)
	var faces := str(info.get("faces", "left"))
	var f := float(pose.facing)
	var flip := -f if faces == "left" else (f if faces == "right" else 1.0)
	var pivot: Vector2 = pose.pivot
	var scale: Vector2 = pose.scale
	var origin := feet + Vector2((pivot.x - 0.5) * flip, pivot.y - LandLife.FEET) * art
	var rot := float(pose.rot)
	_canvas.draw_set_transform(origin, rot, Vector2(flip * scale.x, scale.y))
	_canvas.draw_texture_rect(texture, Rect2(-pivot * art, Vector2(art, art)), false)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	var act := str(pose.act)
	if act == "rest":
		return
	var head_local := ((pose.head as Vector2) - pivot) * art
	var head := origin + (Vector2(head_local.x * flip * scale.x, head_local.y * scale.y)).rotated(rot)
	var u := float(pose.u)
	var t := float(pose.t)
	match act:
		"nap", "sleep":
			# Z's drifting up from its head.
			var font := get_theme_default_font()
			var font_size := maxi(int(art * 0.32), 8)
			for k in 2:
				var rise := fmod(t * 0.45 + k * 0.5, 1.0)
				var at := head + Vector2(f * art * (0.1 + 0.25 * rise), -art * (0.2 + 0.5 * rise))
				_canvas.draw_string(font, at, "z", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 1, 1, 0.85 * sin(rise * PI)))
		"spray", "dust", "wallow":
			# Water (or dust) thrown up over its back from its trunk.
			var color := Color(0.62, 0.82, 1.0) if act == "spray" else Color(0.74, 0.6, 0.42)
			for k in 7:
				var s := fmod(t * 1.1 + k / 7.0, 1.0)
				var at := head + Vector2(-f * s * art * 0.8, -sin(s * PI) * art * 0.55)
				if act == "wallow":
					at = feet + Vector2((k - 3) * art * 0.12, -art * 0.1 - s * art * 0.35)
				var radius := art * (0.035 if act == "spray" else 0.05 + 0.05 * s)
				_canvas.draw_circle(at, radius, Color(color, (0.9 if act == "spray" else 0.55) * (1.0 - s)))
		"roar":
			# Its roar rolling out ahead of it.
			for k in 3:
				var s := fmod(t * 1.4 + k / 3.0, 1.0)
				var middle := head + Vector2(f * art * 0.12, 0.0)
				var facing_angle := 0.0 if f > 0.0 else PI
				_canvas.draw_arc(middle, art * (0.15 + 0.45 * s), facing_angle - 0.6, facing_angle + 0.6, 10, Color(1, 1, 1, 0.8 * (1.0 - s)), maxf(art * 0.04, 1.0), true)
		"spit":
			if u > 0.3:
				var s := (u - 0.3) / 0.7
				_canvas.draw_circle(head + Vector2(f * s * art * 0.9, s * s * art * 0.3), art * 0.04, Color(1, 1, 1, 0.9 * (1.0 - s)))
		"chest":
			# Thumping its chest: little bursts either side.
			var burst := absf(sin(t * 20.0))
			var chest := feet - Vector2(0.0, art * 0.5 * float((pose.scale as Vector2).y))
			for side_sign: float in [-1.0, 1.0]:
				for k in 3:
					var angle := (0.0 if side_sign > 0.0 else PI) + (k - 1) * 0.5
					var from := chest + Vector2(side_sign * art * 0.42, 0.0) + Vector2.from_angle(angle) * art * 0.05
					_canvas.draw_line(from, from + Vector2.from_angle(angle) * art * 0.12 * burst, Color(1, 1, 1, 0.8), maxf(art * 0.03, 1.0), true)


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
		var at := _ship_world(ship)
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


# --- Birds ---------------------------------------------------------------------

## Birds (Birds: gulls round ports, ships and sea animals; raptors along the
## shore and sea ducks rafting off ports; seabirds following ships), drawn
## from above over everything once zoomed in far enough that a gull's wings
## are BIRD_MIN_PX across: each a little silhouette in its species' colors,
## flapping (or gliding), with a faint shadow on the water. Each bird's way
## round its flock is its own (steady from the flock's key); they keep
## flying while the game's paused.
func _draw_birds() -> void:
	_bird_hits.clear()
	if gray_mode or not show_ships or _ship_scale() < BIRD_MIN_PX:
		return
	var birds := Birds.shared()
	var scale := _ship_scale()
	var now := Time.get_ticks_msec() / 1000.0
	var view := Rect2(Vector2.ZERO, size)
	# Gulls round each port's marina.
	var near := view.grow(MARINA_MAX_REACH * scale)
	for i in _ports_near_view():
		var port: Dictionary = GameData.ports[i]
		var port_id: String = port.id
		var root := port_screen_position(port_id)
		if not near.has_point(root) or not _marina_shown(port_id):
			continue
		var radius := float(_port_layout(port_id).radius) * scale
		var flock := birds.port_flock(port_id)
		_draw_gulls(flock, root, radius * 0.35, radius * 1.15, now, {port = port_id})
		_draw_raptors(port_id, root, radius, now)
		_draw_sea_ducks(port_id, root, radius, now)
		_draw_cormorants(port_id, root, radius, now)
		_draw_waders(port_id, root, radius, now)
	# Round ships (gulls, and the seabirds following ships at sea).
	var reach := view.grow(SHIP_CULL_MARGIN * scale)
	for ship in GameState.ships:
		if ship.is_carried():
			continue
		var at := ship_screen_position(ship)
		if not reach.has_point(at) or ship.is_docked() and not _marina_shown(ship.docked_at):
			continue
		var length := (_model_look(ship.model_id)[7] as Rect2).size.x * scale
		var under_way := _under_way(ship, now)
		var flock := birds.ship_flock(ship)
		if not flock.is_empty():
			_draw_gulls(flock, at, length * 0.35, length * 0.9, now, {ship = ship}, _screen_angle(ship), under_way, length)
		for entry: Dictionary in birds.followers(ship):
			_draw_followers(ship, entry, at, _screen_angle(ship), length, now, under_way)
	# Round pods of sea animals (where they're drawn: see _draw_sea_life()).
	for hit: Array in _pod_hits:
		var pod_index: int = hit[0]
		var center: Vector2 = hit[1]
		var pod_reach: float = hit[2]
		var pod := SeaLife.shared().state(pod_index, float(GameState.calendar_time()))
		var flock := birds.pod_flock(pod_index, pod.pos)
		if not flock.is_empty():
			_draw_gulls(flock, center, pod_reach * 0.6, pod_reach * 1.4, now, {pod = pod_index})
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## True if a screen point is out on the sea (SeaLife's sea mask, 0.25 degree
## cells), for birds on or over the water.
func _on_sea(screen: Vector2) -> bool:
	return not _is_hidden(screen) and SeaLife.shared().is_sea(_screen_lon_lat(screen))


## How much a ship's under way (0 still to 1 sailing), for its birds: they
## fly along with a ship that's moving and wheel round one that isn't
## (docked, at anchor, waiting at a canal, a tug standing by). Eased over a
## couple of seconds as it gets going or stops; kept as it was while the
## game's paused.
func _under_way(ship: Ship, now: float) -> float:
	var where := ship.world_position()
	var kept: Array = _ship_motion.get(ship, [])
	if kept.is_empty():
		kept = [where, now, 0.0 if ship.is_docked() else 1.0, now]  # [last place, last time, under way, last moved]
		_ship_motion[ship] = kept
		return kept[2]
	var seconds := clampf(now - float(kept[1]), 0.0, 0.5)
	kept[1] = now
	if GameState.time_speed > 0:
		if not ship.is_docked() and (where - (kept[0] as Vector2)).length_squared() > 0.0:
			kept[3] = now
		# (Moving if it's moved in the last half second: it needn't move every frame.)
		var moving := not ship.is_docked() and now - float(kept[3]) < 0.5
		kept[2] = move_toward(float(kept[2]), 1.0 if moving else 0.0, seconds / UNDER_WAY_EASE_S)
	else:
		kept[3] = now  # (Paused: as it was.)
	kept[0] = where
	return kept[2]


## Where a bird of a V (pelicans, cormorants, migrating sea ducks) flies:
## `place` 0 the leader at `lead`, then back along either arm by turns,
## flying `way` (a unit vector), birds `span` px across.
static func _v_spot(lead: Vector2, way: Vector2, place: int, span: float) -> Vector2:
	var rank := (place + 1) / 2
	var arm := 0.0 if place == 0 else (1.0 if place % 2 == 1 else -1.0)
	var spacing := span * 0.8
	return lead - way * rank * spacing * 0.8 + way.orthogonal() * arm * rank * spacing * 0.75


## A flock of gulls wheeling round a point on screen, between two radii (px),
## each bird one of its species in turn. `about` says what it's round, for
## clicking it (see bird_clicked). Over a ship under way (under_way, `way` its
## heading on screen, `length` its length in px) they fly along with it instead.
func _draw_gulls(flock: Dictionary, center: Vector2, inner: float, outer: float, now: float, about: Dictionary, way := 0.0, under_way := 0.0, length := 0.0) -> void:
	var birds := Birds.shared()
	var count := int(flock.count)
	var kinds: Array = flock.species
	var traits := _bird_traits(str(flock.key), count)
	for k in count:
		var info := birds.species(str(kinds[k % kinds.size()]))
		var t: PackedFloat32Array = traits[k]
		var turn := 1.0 if t[3] < 0.5 else -1.0
		var angle := t[0] * TAU + turn * (0.35 + 0.4 * t[1]) * now
		var radius := lerpf(inner, outer, t[2]) * (1.0 + 0.15 * sin(now * 0.7 + t[4] * TAU))
		var at := center + Vector2.from_angle(angle) * radius
		var heading := angle + turn * PI / 2.0
		if under_way > 0.0:
			# Over a ship under way, flying along with it, the way it's going: spread
			# round and behind it, drifting about a little, wheeling no more.
			var ahead := Vector2.from_angle(way)
			var along := -length * (0.25 + 0.9 * t[2]) + sin(now * 0.5 + t[0] * TAU) * length * 0.15
			var across := (t[3] - 0.5) * 2.0 * length * 0.6 + sin(now * 0.7 + t[4] * TAU) * length * 0.12
			var alongside := center + ahead * along + ahead.orthogonal() * across
			at = at.lerp(alongside, under_way)
			heading = lerp_angle(heading, way + 0.25 * sin(now * 0.8 + t[0] * TAU), under_way)
		# Flapping, with spells of gliding.
		var gliding := sin(now * 0.45 + t[4] * TAU) > 0.35
		var wings := 1.0 if gliding else 0.78 + 0.22 * cos(now * (6.0 + 3.0 * t[1]) + t[0] * TAU)
		_draw_bird(at, heading, info, wings)
		_bird_hits.append([at, maxf(float(info.get("span", 1.0)) * BIRD_SCALE * _ship_scale() * 0.6, BIRD_HIT_MIN_PX), about, flock])


## Seabirds following a ship, going its way, each kind its own way:
## albatrosses glide in sweeping arcs behind, condors drift high and slow
## behind and off to a side, terns flit about round it and ahead, pelicans
## fly in a V off to one side, shearwaters skim low weaving behind. While it's
## stopped (under_way 0: see _under_way()), they wheel round it instead.
func _draw_followers(ship: Ship, entry: Dictionary, at: Vector2, heading: float, length: float, now: float, under_way := 1.0) -> void:
	var birds := Birds.shared()
	var id: String = entry.id
	var info := birds.species(id)
	var behavior := str(info.get("behavior", "glide"))
	var ahead := Vector2.from_angle(heading)
	var side := ahead.orthogonal()
	var count := int(entry.count)
	var traits := _bird_traits("follow/%d/%s" % [ship.id, id], count)
	var flock := {count = count, species = [id], key = id}
	for k in count:
		var t: PackedFloat32Array = traits[k]
		var phase := t[0] * TAU
		var pos := at
		var facing := heading
		var wings := 1.0
		match behavior:
			"glide":
				var sweep := sin(now * 0.55 + phase)
				pos = at - ahead * length * (1.0 + 0.5 * k + 0.2 * cos(now * 0.4 + phase)) + side * length * 1.1 * sweep
				facing = heading + 0.7 * cos(now * 0.55 + phase)
			"soar":
				# High and slow, behind and off to a side, drifting, going its way.
				pos = at - ahead * length * (0.9 + 0.7 * t[2]) + side * length * (t[3] - 0.5) * 2.6 + Vector2(sin(now * 0.3 + phase), cos(now * 0.25 + phase)) * length * 0.2
				facing = heading + 0.15 * sin(now * 0.3 + phase)
			"dart":
				# Flitting about round it and ahead, zigzagging, going its way.
				pos = at + ahead * length * (0.1 + 0.6 * sin(now * 0.9 + phase)) + side * length * 0.7 * sin(now * 1.3 + phase * 2.0) + Vector2(sin(now * 9.0 + phase), cos(now * 7.0 + phase)) * length * 0.04
				facing = heading + 0.5 * cos(now * 1.3 + phase * 2.0)
				wings = 0.6 + 0.4 * absf(sin(now * 14.0 + phase))
			"line":
				# A V off to one side of the ship (the flock's side), the leader ahead
				# and the rest back along either arm by turns; all flapping a few beats
				# and gliding together, the flaps rippling back down the arms.
				var flock_side := 1.0 if Birds.chance([ship.id, id, "side"]) < 0.5 else -1.0
				var rank := (k + 1) / 2  # (How far back along its arm.)
				var lead := at + side * length * 1.1 * flock_side + ahead * length * 0.1 + side * sin(now * 0.4 + float(ship.id)) * length * 0.05
				pos = _v_spot(lead, ahead, k, _bird_span(info))
				var flapping := sin(now * 0.7 + float(ship.id)) > 0.4
				wings = 0.8 + 0.2 * cos(now * 5.0 - rank * 0.7) if flapping else 1.0
			"skim":
				var weave := sin(now * 1.3 + phase)
				pos = at - ahead * length * (1.2 + 0.35 * k) + side * length * 0.8 * weave
				facing = heading + 0.6 * cos(now * 1.3 + phase)
		if under_way < 1.0:
			# Its ship stopped (waiting, at anchor): wheeling round it instead.
			var turn := 1.0 if t[3] < 0.5 else -1.0
			var round := phase + now * (0.25 + 0.15 * t[1]) * turn
			var circling := at + Vector2.from_angle(round) * length * (1.0 + 0.8 * t[2])
			pos = circling.lerp(pos, under_way)
			facing = lerp_angle(round + PI / 2.0 * turn, facing, under_way)
		_draw_bird(pos, facing, info, wings)
		_bird_hits.append([pos, maxf(float(info.get("span", 1.0)) * BIRD_SCALE * _ship_scale() * 0.6, BIRD_HIT_MIN_PX), {ship = ship}, flock])


## The raptors about a port (Birds.port_raptors()), each going about its day
## as it really does along a shore, round a marina `radius` px across, its
## sea out one way and the land the other: sea eagles sit on their perch on
## the shore, now and then flying out to swoop and snatch a fish off the water
## and carrying it back; the osprey circles over the water, hovers, plunges
## feet first with a splash and carries its fish head forward to a perch to
## eat; golden and wedge-tailed eagles soar high over the land and stoop;
## buzzards and the like circle on thermals over the land and hang on the
## wind, hunting below; Swainson's hawks pass over in a kettle, circling up
## and streaming off; Harris's hawks sit together, then hunt low over the land
## in a line, taking turns to lead; goshawks and Cooper's hawks sit hidden on
## the shore and dash off low, flap-flap-glide.
func _draw_raptors(port_id: String, root: Vector2, radius: float, now: float) -> void:
	var birds := Birds.shared()
	var sea := Vector2.from_angle(_port_sea_angle(port_id))
	var across := sea.orthogonal()
	var land := -sea
	for entry: Dictionary in birds.port_raptors(port_id):
		var id: String = entry.id
		var info := birds.species(id)
		var behavior := str(info.get("behavior", "kite"))
		var count := int(entry.count)
		var traits := _bird_traits("raptor/%s/%s" % [port_id, id], count)
		var flock := {count = count, species = [id], key = id}
		var span := _bird_span(info)
		# Where it perches on the shore, where it fishes and where it soars over
		# the land: its own, either side of the marina.
		var wind := Birds.chance([port_id, "wind"]) * TAU  # Where the wind blows from (hawks hang facing into it).
		for k in count:
			var t: PackedFloat32Array = traits[k]
			var phase := t[0] * TAU
			var turn := 1.0 if t[3] < 0.5 else -1.0
			var flank := across * turn
			var perch := root + land * radius * (1.75 + 0.3 * t[2]) + flank * radius * (0.6 + 0.6 * t[1])
			var water := root + sea * radius * (1.5 + 0.6 * t[2]) + flank * radius * (0.4 + 0.6 * t[1])
			if not _on_sea(water):
				water = root + flank * radius * 0.3  # (Up a river, its sea far off: fishing in the marina.)
			var over_land := root + land * radius * (2.6 + 0.8 * t[2]) + flank * radius * 0.6 * t[1]
			var pos := perch
			var facing := sea.angle()  # Perched looking out to sea.
			var wings := 0.24  # Folded.
			var height := 0.05
			var fish := false
			var splash := -1.0
			match behavior:
				"snatch":
					var cycle := 34.0 + 10.0 * t[1]
					var c := fmod(now / cycle + t[0], 1.0)
					if c >= 0.55 and c < 0.75:
						# Out low over the water, dropping to it, and up with a fish.
						var s := (c - 0.55) / 0.2
						var out := perch.lerp(water, smoothstep(0.0, 0.7, s))
						var back := water.lerp(perch, smoothstep(0.7, 1.0, s))
						pos = out if s < 0.7 else back
						facing = (water - perch).angle() if s < 0.6 else (perch - water).angle()
						height = 1.3 - 1.15 * sin(clampf((s - 0.3) / 0.4, 0.0, 1.0) * PI)
						wings = 0.9 + 0.1 * cos(now * 5.0 + phase)
						if absf(s - 0.5) < 0.08:
							splash = (s - 0.42) / 0.16
							wings = 0.7
						fish = s > 0.55
					elif c >= 0.75:
						# Back on its perch, tearing at its fish.
						fish = true
						facing = sea.angle() + 0.3 * sin(now * 3.0 + phase) * turn
				"plunge":
					var cycle := 26.0 + 8.0 * t[1]
					var c := fmod(now / cycle + t[0], 1.0)
					var round := phase + now * 0.2 * turn
					var circling := water + Vector2.from_angle(round) * radius * 0.5
					height = 1.8
					wings = 1.0
					if c < 0.3:
						pos = circling
						facing = round + PI / 2.0 * turn
					elif c < 0.36:
						pos = circling.lerp(water, smoothstep(0.0, 1.0, (c - 0.3) / 0.06))
						facing = wind
					elif c < 0.44:
						pos = water  # Hovering into the wind, looking down.
						facing = wind
						wings = 0.65 + 0.35 * absf(sin(now * 16.0 + phase))
						height = 1.6
					elif c < 0.47:
						pos = water
						facing = wind
						wings = 0.3
						height = lerpf(1.6, 0.0, (c - 0.44) / 0.03)
					elif c < 0.5:
						pos = water
						facing = wind
						wings = 0.45
						height = 0.0
						splash = (c - 0.47) / 0.03
					elif c < 0.66:
						var s := smoothstep(0.0, 1.0, (c - 0.5) / 0.16)
						pos = water.lerp(perch, s)
						facing = (perch - water).angle()
						height = 0.2 + 1.2 * sin(s * PI)
						wings = 0.8 + 0.2 * cos(now * 7.0 + phase)
						fish = true
					else:
						fish = c < 0.9  # Eating it on its perch.
						facing = land.angle() + 0.3 * sin(now * 3.0 + phase)
				"stoop":
					var cycle := 40.0 + 10.0 * t[1]
					var c := fmod(now / cycle + t[0], 1.0)
					var round := phase + now * (0.07 + 0.03 * t[1]) * turn
					var circling := over_land + Vector2.from_angle(round) * radius * (0.9 + 0.4 * t[2])
					pos = circling
					facing = round + PI / 2.0 * turn
					wings = 1.0
					height = 3.2
					if c >= 0.8 and c < 0.92:
						var s := (c - 0.8) / 0.12
						var ground := over_land + flank * radius * 0.3
						var dip := smoothstep(0.0, 0.45, s) * (1.0 - smoothstep(0.55, 1.0, s))
						pos = circling.lerp(ground, dip)
						height = lerpf(3.2, 0.1, dip)
						wings = lerpf(1.0, 0.3, dip)
						facing = (ground - circling).angle() if s < 0.5 else (circling - ground).angle()
				"kite":
					var cycle := 24.0 + 8.0 * t[1]
					var c := fmod(now / cycle + t[0], 1.0)
					var round := phase + now * 0.16 * turn
					var circling := over_land + Vector2.from_angle(round) * radius * (0.6 + 0.3 * t[2])
					wings = 1.0
					height = 1.8
					if c < 0.5:
						pos = circling  # Circling on a thermal.
						facing = round + PI / 2.0 * turn
					elif c < 0.56:
						pos = circling.lerp(over_land, smoothstep(0.0, 1.0, (c - 0.5) / 0.06))
						facing = wind
					elif c < 0.8:
						pos = over_land + Vector2(sin(now * 1.7 + phase), cos(now * 1.3 + phase)) * span * 0.05
						facing = wind  # Hanging on the wind, wings trembling.
						wings = 0.9 + 0.1 * sin(now * 12.0 + phase)
						height = 1.5
					elif c < 0.86:
						var s := (c - 0.8) / 0.06
						pos = over_land.lerp(perch, smoothstep(0.0, 1.0, s))
						facing = (perch - over_land).angle()
						height = lerpf(1.5, 0.05, s)
					else:
						pos = perch  # On a post, watching the ground.
						facing = land.angle()
						wings = 0.24
						height = 0.05
				"kettle":
					# Circling up together on a thermal over the land, then
					# streaming off one after another on their way.
					var cycle := 60.0
					var c := fmod(now / cycle, 1.0)
					var round := phase + now * 0.4
					var thermal := root + land * radius * 3.0
					pos = thermal + Vector2.from_angle(round) * radius * (0.3 + 0.6 * t[2])
					facing = round + PI / 2.0
					wings = 1.0
					height = 1.2 + 2.0 * c
					var leave := 0.7 + 0.25 * t[1]
					if c > leave:
						var s := (c - leave) / (1.0 - leave)
						var way := Vector2.from_angle(Birds.chance([port_id, "kettle"]) * TAU)
						pos = pos.lerp(thermal + way * radius * 5.0, s)
						facing = way.angle()
				"pack":
					# Perched together, then off hunting low over the land in a
					# line, taking turns to lead.
					var cycle := 30.0
					var c := fmod(now / cycle, 1.0)
					var lead := posmod(floori(now / cycle) + k, count)
					pos = root + land * radius * 1.8 + across * radius * (0.8 + 0.18 * k)
					facing = land.angle()
					if c > 0.6:
						var s := (c - 0.6) / 0.4
						var loop := over_land + Vector2.from_angle(s * TAU + PI) * radius * 0.9
						var trail := s - 0.04 * lead
						var at_trail := over_land + Vector2.from_angle(trail * TAU + PI) * radius * 0.9
						pos = pos.lerp(at_trail, sin(s * PI))
						facing = (loop - pos).angle() if loop.distance_to(pos) > 0.5 else facing + PI / 2.0
						wings = 0.85 + 0.15 * cos(now * 9.0 + phase)
						height = lerpf(0.05, 0.5, sin(s * PI))
				"perch":
					var cycle := 28.0 + 8.0 * t[1]
					var c := fmod(now / cycle + t[0], 1.0)
					facing = land.angle() + 0.4 * turn
					if c >= 0.8:
						# A dash low along the shore and back: flap-flap-glide.
						var s := (c - 0.8) / 0.2
						var far := perch + flank * radius * 1.4 + land * radius * 0.4
						pos = perch.lerp(far, sin(s * PI))
						facing = (far - perch).angle() if s < 0.5 else (perch - far).angle()
						wings = 1.0 if fmod(now * 2.5, 1.0) > 0.6 else 0.7 + 0.3 * absf(cos(now * 18.0))
						height = lerpf(0.05, 0.4, sin(s * PI))
			if splash >= 0.0:
				for ring in 2:
					var r := clampf(splash - ring * 0.3, 0.0, 1.0)
					if r > 0.0:
						_canvas.draw_arc(pos, span * (0.15 + 0.35 * r), 0.0, TAU, 16, Color(1, 1, 1, 0.75 * (1.0 - r)), maxf(span * 0.04, 1.0), true)
			_draw_bird(pos, facing, info, wings, height)
			if fish:
				# Held head forward under it, its tail showing behind the bird's.
				var back := Vector2.from_angle(facing)
				_canvas.draw_line(pos - back * span * 0.26, pos - back * span * 0.44, Color(0.78, 0.82, 0.86), maxf(span * 0.07, 1.5), true)
			_bird_hits.append([pos, maxf(span * 0.6, BIRD_HIT_MIN_PX), {port = port_id}, flock])


## The cormorants about a port (Birds.port_cormorants()), round its marina
## `radius` px across: some stand on its breakwater looking out to sea, now and
## then holding their wings out to dry; some swim low off it, making long
## dives for fish (a ripple as each goes down and comes up); and every minute
## or so the rest fly past low over the water in a V. By night (by the sun)
## they all roost on the breakwater.
func _draw_cormorants(port_id: String, root: Vector2, radius: float, now: float) -> void:
	var entries := Birds.shared().port_cormorants(port_id)
	if entries.is_empty():
		return
	var birds := Birds.shared()
	var layout := _port_layout(port_id)
	var sea := Vector2.from_angle(_port_sea_angle(port_id))
	var across := sea.orthogonal()
	var wind := Birds.chance([port_id, "wind"]) * TAU
	var port := GameData.get_port(port_id)
	var hour := Birds.local_hour(float(port.get("lon", 0.0)), float(GameState.calendar_time()))
	var night := hour < Birds.RAPTOR_DAY.x or hour > Birds.RAPTOR_DAY.y
	var gap := float(layout.gap)
	for entry: Dictionary in entries:
		var id: String = entry.id
		var info := birds.species(id)
		var count := int(entry.count)
		var traits := _bird_traits("cormorants/%s/%s" % [port_id, id], count)
		var flock := {count = count, species = [id], key = id}
		var span := _bird_span(info)
		var swimmer := _cormorant_swimmer(info)
		# Their pass: every CORMORANT_PASS_S or so, across the sea off the port.
		var cycle := CORMORANT_PASS_S * (0.8 + 0.4 * Birds.chance([port_id, id, "cycle"]))
		var flying := fmod(now / cycle + Birds.chance([port_id, id, "pass"]), 1.0)
		var way := Vector2.from_angle(Birds.chance([port_id, id, "way"]) * TAU)
		var lead := root + sea * radius * 2.2 + way * radius * (12.0 * flying / 0.35 - 6.0)
		var flyers := 0
		for k in count:
			var t: PackedFloat32Array = traits[k]
			var phase := t[4] * TAU
			var role := 0 if night or t[0] < 0.35 else (1 if t[0] < 0.6 else 2)  # Perched, swimming, flying past.
			if role == 1:
				var spot := root + sea * radius * (1.4 + 0.8 * t[2]) + across * radius * (t[1] - 0.5) * 2.2 + Vector2(sin(now * 0.2 + phase), cos(now * 0.17 + phase)) * span * 0.3
				if not _on_sea(spot):
					role = 0
				else:
					var dive := fmod(now / (25.0 + 10.0 * t[1]) + t[3], 1.0)
					if dive > 0.5 and dive < 0.95:  # Down a long while.
						var ripple := (dive - 0.5) / 0.45
						for edge: float in [0.0, 1.0]:
							var r := 1.0 - absf(ripple - edge) * 8.0
							if r > 0.0:
								_canvas.draw_arc(spot, span * (0.1 + 0.2 * (1.0 - r)), 0.0, TAU, 12, Color(1, 1, 1, 0.6 * r), maxf(span * 0.03, 1.0), true)
						continue
					draw_duck(_canvas, spot, wind + 0.3 * (t[3] - 0.5), swimmer, span * 1.2, false)
					_bird_hits.append([spot, maxf(span * 0.5, BIRD_HIT_MIN_PX), {port = port_id}, flock])
					continue
			if role == 2:
				if flying < 0.35:
					var pos := _v_spot(lead, way, flyers, span)
					flyers += 1
					_draw_bird(pos, way.angle(), info, 0.75 + 0.25 * absf(sin(now * 9.0 - flyers * 0.6)), 0.5)
					_bird_hits.append([pos, maxf(span * 0.6, BIRD_HIT_MIN_PX), {port = port_id}, flock])
				continue
			# On the breakwater, along either arm, looking out to sea.
			var arm_side := 1.0 if t[3] < 0.5 else -1.0
			var along := lerpf(gap + 0.1, PI / 2.0 - 0.05, t[1]) * arm_side
			var perch := _dock_point(port_id, Vector2.from_angle(along) * float(layout.radius))
			var drying := not night and sin(now * 0.12 + phase) > 0.55
			_draw_bird(perch, _dock_angle(port_id, along) + 0.2 * (t[2] - 0.5), info, 0.7 if drying else 0.2, 0.03)
			_bird_hits.append([perch, maxf(span * 0.5, BIRD_HIT_MIN_PX), {port = port_id}, flock])


## A cormorant's colors for drawing it swimming low (see draw_duck()): all
## its back's dark color, its head and bill. Made once a species.
func _cormorant_swimmer(info: Dictionary) -> Dictionary:
	var id := str(info.get("latin", ""))
	if not _cormorant_swimmers.has(id):
		var colors: Dictionary = info.get("colors", {})
		_cormorant_swimmers[id] = {colors = {mantle = colors.get("mantle", "#1e1e1e"), sides = colors.get("mantle", "#1e1e1e"),
			head = colors.get("head", "#141414"), cap = colors.get("head", "#141414"), bill = colors.get("bill", "#d8b040"), patch = colors.get("cheek", colors.get("throat", ""))}}
		if str(_cormorant_swimmers[id].colors.patch).is_empty():
			(_cormorant_swimmers[id].colors as Dictionary).erase("patch")
	return _cormorant_swimmers[id]


## A port's shore either side of its marina, found once from the land as
## the map draws it (_on_land()): [[the water's edge, a spot a little inland
## (or Vector2.INF where that isn't land)]] in dock units, from one side to
## the other; or made up just off the breakwater's ends where there's none
## (up a river, say). [] until the land's ready.
func _shore_spots(port_id: String) -> Array:
	if _shores.has(port_id):
		return _shores[port_id]
	if _land_cells.is_empty():
		_start_land_cells()
		return []
	var radius := float(_port_layout(port_id).radius)
	var out := []
	for i in SHORE_SAMPLES:
		var y := lerpf(-SHORE_REACH, SHORE_REACH, (i + 0.5) / SHORE_SAMPLES) * radius
		if absf(y) < radius * 1.05:
			continue  # The marina's own.
		# In from out at sea to the first land, then narrowed down.
		var sea_x := SHORE_SEAWARD * radius
		if _local_on_land(port_id, Vector2(sea_x, y), true):
			continue
		var land_x := INF
		for s in range(1, 23):
			var x := lerpf(SHORE_SEAWARD, -SHORE_INLAND, s / 22.0) * radius
			if _local_on_land(port_id, Vector2(x, y), true):
				land_x = x
				break
			sea_x = x
		if land_x == INF:
			continue
		for n in 6:
			var mid := (sea_x + land_x) / 2.0
			if _local_on_land(port_id, Vector2(mid, y), true):
				land_x = mid
			else:
				sea_x = mid
		if not _local_on_land(port_id, Vector2(land_x, y)):
			continue  # (Up against a marina, not the shore.)
		var inland := Vector2(land_x - radius * 0.9, y)
		out.append([Vector2((sea_x + land_x) / 2.0, y), inland if _local_on_land(port_id, inland) else Vector2.INF])
	if out.is_empty():
		for y: float in [-1.9, -1.4, 1.4, 1.9]:
			out.append([Vector2(radius * 0.3, y * radius), Vector2(-radius * 0.8, y * radius)])
	_shores[port_id] = out
	return out


## True if a point of a port's marina (dock units) is on the land and clear
## of every marina near it (a quay's no place for a heron); or, `blocked`,
## if it's on the land or a marina either way (the shore's looked for from
## the sea in to the first of either).
func _local_on_land(port_id: String, local: Vector2, blocked := false) -> bool:
	var screen := _dock_point(port_id, local)
	if _is_hidden(screen):
		return false
	var land := _on_land(_screen_lon_lat(screen))
	if land and blocked:
		return true
	if not land and not blocked:
		return false
	if not _shore_neighbours.has(port_id):
		var here := GameData.port_position(port_id)
		var near: Array[String] = [port_id]
		for port: Dictionary in GameData.ports:
			if port.id != port_id and GameData.port_position(port.id).distance_to(here) < 3.0:
				near.append(port.id)
		_shore_neighbours[port_id] = near
	for other: String in _shore_neighbours[port_id]:
		if _in_marina(other, screen):
			return blocked
	return not blocked


## True if a screen point's on a port's marina: its cleared circle or its
## square quay (a little grown).
func _in_marina(port_id: String, screen: Vector2) -> bool:
	var layout := _port_layout(port_id)
	var angle := _port_sea_angle(port_id) + _port_turn(port_id)
	var local := (screen - port_screen_position(port_id)).rotated(-angle) / dock_scale(port_id)
	var clear := float(layout.radius) + JETTY_WIDTH / 2.0
	var margin := clear * 0.1
	return local.length() < clear + margin or (local.x <= margin and local.x >= _quay_inland(layout) - margin and absf(local.y) <= clear + margin)


## A place along a port's shore (see _shore_spots()): `along` from 0 at one
## end to its last spot, between spots smoothly (though not across the
## marina); `out` dock units out from the water's edge (less: inland).
## [the place (dock units), which way the shore runs (a unit vector)].
static func _shore_at(shore: Array, along: float, out: float) -> Array:
	var last := shore.size() - 1
	along = pingpong(along, float(last)) if last > 0 else 0.0  # (Turned back at either end.)
	var i := mini(floori(along), maxi(last - 1, 0))
	var a: Vector2 = shore[i][0]
	var b: Vector2 = shore[mini(i + 1, last)][0]
	if a.distance_to(b) > absf(b.y - a.y) * 3.0 + 1.0 or (a.y < 0.0) != (b.y < 0.0):
		b = a + Vector2(0.0, signf(b.y - a.y) if b.y != a.y else 1.0)  # (Not across the marina.)
	var run := (b - a).normalized() if a != b else Vector2.DOWN
	var at := a.lerp(b, along - i) if (a.y < 0.0) == (b.y < 0.0) else a
	return [at + Vector2(out, 0.0), run]


## The waders about a port (Birds.port_waders()), along its shore either side
## of its marina `radius` px across, each its own way. Herons stand stock
## still at the water's edge, neck poised, now and then taking a slow step or
## striking (sometimes coming up with a fish), and every few minutes one
## flaps slowly off and round; by night they stand hunched. Night herons roost
## hunched together inland by day and come down to the water at dusk. Egrets
## walk the shallows steadily in loose groups, stabbing as they go (little
## and snowy egrets stirring the mud with their yellow feet, ripples round
## them), and roost inland by night. Cattle egrets work the fields inland,
## heads bobbing, the ones at the back hopping over to the front. The reddish
## egret lurches and spins through the shallows with its wings held out over
## the water. A bittern stands in the reeds at the water's edge, bill to the
## sky, swaying with them; in spring at dawn it booms. Cranes forage over the
## fields in family groups, and in spring pairs dance, leaping with wings
## spread and bowing; on migration they pass high over in Vs instead.
func _draw_waders(port_id: String, root: Vector2, radius: float, now: float) -> void:
	var entries := Birds.shared().port_waders(port_id)
	if entries.is_empty():
		return
	var shore := _shore_spots(port_id)
	if shore.is_empty():
		return
	var birds := Birds.shared()
	var dock := dock_scale(port_id)
	var unit := radius / dock  # The marina's radius in dock units.
	var port := GameData.get_port(port_id)
	var unix := float(GameState.calendar_time())
	var hour := Birds.local_hour(float(port.get("lon", 0.0)), unix)
	var night := hour < Birds.RAPTOR_DAY.x or hour > Birds.RAPTOR_DAY.y
	var dusk := hour > Birds.RAPTOR_DAY.y - 1.5 or hour < Birds.RAPTOR_DAY.x + 0.5
	var month := Birds.month_of(unix)
	var spring := month in ([2, 3, 4, 5] if float(port.get("lat", 0.0)) >= 0.0 else [8, 9, 10, 11])
	var wind := Birds.chance([port_id, "wind"]) * TAU
	var last := float(shore.size() - 1)
	for entry: Dictionary in entries:
		var id: String = entry.id
		var info := birds.species(id)
		var behavior := str(info.get("behavior", "stalk"))
		var count := int(entry.count)
		var traits := _bird_traits("waders/%s/%s" % [port_id, id], count)
		var flock := {count = count, species = [id], key = id}
		var span := _bird_span(info)
		var hit := {port = port_id}
		if bool(entry.get("moving", false)):
			_draw_crane_pass(port_id, root, radius, now, info, count, flock)
			continue
		# Where along the shore this species keeps to (a group together).
		var home := Birds.chance([port_id, id, "home"]) * last
		for k in count:
			var t: PackedFloat32Array = traits[k]
			var phase := t[4] * TAU
			var along := home
			var out := unit * 0.06
			var facing := 0.0  # Dock units: 0 out to sea.
			var neck := 0.5
			var wings := 0.0
			var bill_up := false
			var lift := 0.0
			var ripple := -1.0
			var fish := false
			var flying := false
			var place := Vector2.ZERO
			match behavior:
				"stalk", "night":
					var roosting := behavior == "night" and not dusk and not night
					along = home + (float(k) - (count - 1) / 2.0) * (1.6 if behavior == "stalk" else 0.25)
					if roosting:
						# Roosting hunched together in the trees inland.
						out = -unit * (0.7 + 0.3 * t[2])
						facing = PI + (t[3] - 0.5) * 2.0
						neck = 0.0
					else:
						var cycle := 45.0 + 25.0 * t[2]
						var c := fmod(now / cycle + t[0], 1.0)
						var turn_no := floori(now / cycle + t[0])
						var way := 1.0 if (turn_no + k) % 2 == 0 else -1.0
						along += 0.25 * way * smoothstep(0.0, 0.12, c) - 0.125 * way
						facing = (t[3] - 0.5) * 1.2
						neck = 0.1 if night and behavior == "stalk" else 0.55
						if c < 0.12:
							facing = PI / 2.0 * way  # A slow step along the shore.
						elif c >= 0.6 and c < 0.7 and not (night and behavior == "stalk"):
							var s := (c - 0.6) / 0.1
							neck = 1.0 if s < 0.12 else lerpf(1.0, 0.55, clampf((s - 0.12) / 0.2, 0.0, 1.0))
							ripple = s * 4.0 if s < 0.25 else -1.0
							fish = s > 0.1 and s < 0.7 and t[1] < 0.45
						elif c >= 0.8 and turn_no % 3 == k % 3 and behavior == "stalk" and not night:
							# Off and round over the water with slow deep beats, then back.
							flying = true
							var s := (c - 0.8) / 0.2
							var edge: Array = _shore_at(shore, along, out)
							var loop := Vector2(sin(s * PI) * unit * 1.4, (1.0 - cos(s * TAU)) * 0.5 * unit * 1.2 * way)
							var from: Vector2 = _dock_point(port_id, (edge[0] as Vector2) + loop)
							var next: Vector2 = _dock_point(port_id, (edge[0] as Vector2) + Vector2(sin(minf(s + 0.02, 1.0) * PI) * unit * 1.4, (1.0 - cos(minf(s + 0.02, 1.0) * TAU)) * 0.5 * unit * 1.2 * way))
							var angle := (next - from).angle() if next != from else _dock_angle(port_id, 0.0)
							_draw_bird(from, angle, info, 0.55 + 0.45 * absf(sin(now * 2.4 + phase)), 0.15 + 0.6 * sin(s * PI))
							_bird_hits.append([from, maxf(span * 0.6, BIRD_HIT_MIN_PX), hit, flock])
				"wade":
					if night:
						along = home + (t[1] - 0.5) * 0.6
						out = -unit * (0.5 + 0.4 * t[2])
						facing = t[3] * TAU
						neck = 0.0
					else:
						var pace := 0.035 * (0.7 + 0.6 * t[2])
						along = home + (t[1] - 0.5) * 1.4 + 0.45 * sin(now * pace + phase)
						out = unit * (0.05 + 0.08 * t[3])
						facing = PI / 2.0 if cos(now * pace + phase) >= 0.0 else -PI / 2.0
						facing += 0.4 * sin(now * 0.7 + phase)
						var c := fmod(now / (5.0 + 4.0 * t[3]) + t[0], 1.0)
						neck = 1.0 if c < 0.05 else 0.6
						ripple = c * 12.0 if c < 0.08 else -1.0
				"graze":
					along = home + (t[1] - 0.5) * 0.9 + 0.3 * sin(now * 0.015 + Birds.chance([port_id, id, "drift"]) * TAU)
					out = -unit * (0.35 + 0.5 * t[2])
					facing = PI / 2.0 if cos(now * 0.015) >= 0.0 else -PI / 2.0
					neck = 0.0 if night else 0.35 + 0.25 * absf(sin(now * 2.2 + phase))
					var c := fmod(now / (16.0 + 8.0 * t[3]) + t[0], 1.0)
					if not night and c < 0.08:
						# Hopping over the others to the front.
						lift = sin(c / 0.08 * PI) * 0.4
						wings = 0.8
						along += (c / 0.08 - 0.5) * 0.4 * (1.0 if facing > 0.0 else -1.0)
				"dance":
					along = home + (t[1] - 0.5) * 0.8 + 0.18 * sin(now * 0.35 + phase) + 0.07 * sin(now * 1.6 + phase)
					out = unit * (0.1 + 0.06 * sin(now * 0.5 + phase))
					var c := fmod(now / 11.0 + t[0], 1.0)
					facing = PI / 2.0 * signf(cos(now * 0.35 + phase)) + (c * TAU * 2.0 if c > 0.85 else 0.0)
					if night:
						neck = 0.0
					else:
						wings = 0.55 if c > 0.4 and c < 0.85 else 0.0  # Canopy: wings out as a shade.
						neck = 1.0 if fmod(c * 5.0, 1.0) < 0.1 else 0.6
						ripple = fmod(c * 5.0, 1.0) * 6.0 if fmod(c * 5.0, 1.0) < 0.16 else -1.0
				"hide":
					along = home
					out = -unit * 0.04
					var c := fmod(now / 40.0 + t[0], 1.0)
					var sway := 0.12 * sin(now * 0.9 + wind)
					facing = (t[3] - 0.5) * 0.6 + sway
					bill_up = not (c > 0.7 and c < 0.74)  # Bill to the sky, but for the odd strike.
					neck = 0.15 if bill_up else 0.9
					var edge: Array = _shore_at(shore, along, out)
					var reed_at: Vector2 = _dock_point(port_id, edge[0])
					_draw_reeds(reed_at, span, now, wind, t[0])
					if spring and hour > 3.5 and hour < 7.5:
						# Booming: rings rolling out across the marsh every few seconds.
						var b := fmod(now / 3.0 + t[1], 1.0)
						_canvas.draw_arc(reed_at, span * (0.2 + b * 1.2), 0.0, TAU, 24, Color(1, 1, 1, 0.35 * (1.0 - b)), maxf(span * 0.02, 1.0), true)
				"crane":
					along = home + (t[1] - 0.5) * 1.6
					out = -unit * (0.4 + 0.7 * t[2])
					var drift := 0.12 * sin(now * 0.02 + phase)
					along += drift
					facing = PI / 2.0 * signf(cos(now * 0.02 + phase)) + 0.5 * sin(now * 0.1 + phase)
					if night:
						neck = 0.05
					else:
						neck = 0.45 + 0.4 * maxf(sin(now * 0.8 + phase), 0.0)  # Pecking about.
						if (spring and t[3] < 0.6) or t[3] < 0.1:
							var c := fmod(now / 12.0 + t[0], 1.0)
							if c < 0.35:
								# Dancing: leaps with wings spread, then a bow.
								var s := c / 0.35
								lift = absf(sin(s * PI * 3.0)) * 0.8 if s < 0.7 else 0.0
								wings = 0.9 if s < 0.7 else 0.3
								neck = 0.3 if s < 0.7 else 1.0
								facing += sin(s * TAU) * 0.8
			if flying:
				continue
			along = pingpong(along, last) if last > 0.0 else 0.0
			var spot: Array = _shore_at(shore, along, out)
			var local: Vector2 = spot[0]
			if out < 0.0:
				out = maxf(out, -unit * 0.9)
				spot = _shore_at(shore, along, out)
			if behavior in ["graze", "crane"] or out < 0.0:
				# Inland: on the land behind the shore, where there is some.
				var inland: Vector2 = shore[clampi(roundi(along), 0, shore.size() - 1)][1]
				if inland == Vector2.INF:
					local = (spot[0] as Vector2) + Vector2(-unit * 0.05, 0.0)
			place = _dock_point(port_id, local)
			var angle := _dock_angle(port_id, facing)
			if ripple >= 0.0 and ripple <= 1.0:
				_canvas.draw_arc(place + Vector2.from_angle(angle) * span * 0.3, span * (0.05 + 0.2 * ripple), 0.0, TAU, 12, Color(1, 1, 1, 0.55 * (1.0 - ripple)), maxf(span * 0.025, 1.0), true)
			if (info.get("colors", {}) as Dictionary).has("feet") and behavior == "wade" and not night:
				# Stirring the mud with its yellow feet.
				var stir := fmod(now * 0.8 + t[2], 1.0)
				_canvas.draw_arc(place, span * (0.04 + 0.12 * stir), 0.0, TAU, 10, Color(1, 1, 1, 0.35 * (1.0 - stir)), maxf(span * 0.02, 1.0), true)
			draw_wader(_canvas, place, angle, info, span, neck, wings, bill_up, lift, fish)
			_bird_hits.append([place, maxf(span * 0.45, BIRD_HIT_MIN_PX), hit, flock])


## A port's migrating cranes passing high over (every CRANE_PASS_S or so), in
## Vs of up to V_SIZE, necks out and legs trailing, calling as they go.
func _draw_crane_pass(port_id: String, root: Vector2, radius: float, now: float, info: Dictionary, count: int, flock: Dictionary) -> void:
	var id := str(info.get("latin", ""))
	var cycle := CRANE_PASS_S * (0.8 + 0.4 * Birds.chance([port_id, id, "cycle"]))
	var flying := fmod(now / cycle + Birds.chance([port_id, id, "pass"]), 1.0)
	if flying > 0.45:
		return
	var span := _bird_span(info)
	var way := Vector2.from_angle(Birds.chance([port_id, id, "way"]) * TAU)
	var lead := root + way.orthogonal() * radius * (Birds.chance([port_id, id, "off"]) - 0.5) + way * radius * (14.0 * flying / 0.45 - 7.0)
	for k in count:
		var v := k / V_SIZE
		var pos := _v_spot(lead - way.orthogonal() * v * span * 5.0 - way * v * span * 3.0, way, k % V_SIZE, span * 1.3)
		_draw_bird(pos, way.angle(), info, 0.7 + 0.3 * absf(sin(now * 3.0 - k * 0.5)), 3.0)
		_bird_hits.append([pos, maxf(span * 0.6, BIRD_HIT_MIN_PX), {port = port_id}, flock])


## A clump of reeds (round a bittern), swaying with the wind.
func _draw_reeds(at: Vector2, span: float, now: float, wind: float, seed: float) -> void:
	var lean := Vector2.from_angle(wind) * span * 0.06 * (1.0 + sin(now * 0.9 + wind))
	for i in 11:
		var a := TAU * (i / 11.0 + seed)
		var r := span * (0.12 + 0.22 * fmod(seed * 7.0 + i * 0.37, 1.0))
		var base := at + Vector2.from_angle(a) * r
		var color := Color(0.62, 0.56, 0.32) if i % 3 == 0 else Color(0.42, 0.5, 0.26)
		_canvas.draw_line(base, base + lean + Vector2.from_angle(a + 0.6) * span * 0.1, color, maxf(span * 0.025, 1.0), true)
		if i % 4 == 0:
			_canvas.draw_circle(base + lean + Vector2.from_angle(a + 0.6) * span * 0.1, maxf(span * 0.022, 0.8), Color(0.45, 0.3, 0.18))


## A wader standing or walking, seen from above, on any canvas item: its
## shadow cast long to the side (it's tall: legs, body, neck and head), its
## body with its wings folded over it (dark tips), its neck out ahead as far
## as `neck` (0 drawn right in, hunched; 1 struck out full length), its head
## (a crown, a cheek) and dagger bill (pointed at the sky, for a bittern
## hiding: just its head showing), and its wings held out as far as `wings`
## (a crane dancing, an egret shading the water). `lift` raises it off the
## ground (a crane leaping, an egret hopping), its shadow further off; `fish`
## puts a fish crosswise in its bill. Leaves the transform reset.
static func draw_wader(canvas: CanvasItem, at: Vector2, heading: float, info: Dictionary, span: float, neck := 0.5, wings := 0.0, bill_up := false, lift := 0.0, fish := false) -> void:
	var colors: Dictionary = info.get("colors", {})
	var parsed: Array = colors.get("_wader", [])
	if parsed.is_empty():
		var mantle_color := Color.from_string(str(colors.get("mantle", "#9aa2aa")), Color.GRAY)
		parsed = [mantle_color, Color.from_string(str(colors.get("head", "#f0f0ec")), Color.WHITE),
			Color.from_string(str(colors.get("tip", "#2a2c30")), Color.BLACK), Color.from_string(str(colors.get("bill", "#e8c040")), Color.YELLOW),
			Color.from_string(str(colors.get("neck", colors.get("head", ""))), Color.WHITE), Color.from_string(str(colors.get("legs", "#3a3a3a")), Color.BLACK),
			Color.from_string(str(colors.get("crown", "")), Color.TRANSPARENT), Color.from_string(str(colors.get("cheek", "")), Color.TRANSPARENT)]
		if not colors.is_read_only():
			colors["_wader"] = parsed
	var mantle: Color = parsed[0]
	var head_color: Color = parsed[1]
	var crane := str(info.get("kind", "")) == "Crane"
	var fwd := Vector2.from_angle(heading)
	var body_len := span * 0.3
	var body_wide := span * 0.12
	var neck_len := span * (0.02 + 0.2 * neck)
	var upright := span * 0.22 * (1.0 - neck)  # How far up the neck stands (shows in the shadow).
	var legs := span * (0.32 if crane else 0.26)
	# Its shadow: legs down from the hips, then the body, neck and head, cast off to the side.
	var cast := Vector2(0.45, 0.55).normalized()
	var hips := at + cast * (legs + lift * span * 0.6)
	var dark := Color(0, 0, 0, 0.18)
	if lift < 0.05:
		for side: float in [-1.0, 1.0]:
			canvas.draw_line(at + fwd.orthogonal() * side * body_wide * 0.3, hips, dark, maxf(span * 0.012, 1.0), true)
	canvas.draw_set_transform(hips, heading, Vector2.ONE)
	canvas.draw_colored_polygon(_oval(Vector2.ZERO, Vector2(body_len * 0.5, body_wide * 0.5)), dark)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	var shadow_head := hips + fwd * (body_len * 0.45 + neck_len) + cast * upright
	canvas.draw_line(hips + fwd * body_len * 0.4, shadow_head, dark, maxf(span * 0.022, 1.0), true)
	canvas.draw_circle(shadow_head, span * 0.025, dark)
	if not bill_up:
		canvas.draw_line(shadow_head, shadow_head + fwd * span * (0.05 if crane else 0.075), dark, maxf(span * 0.012, 1.0), true)
	# Wings held out.
	if wings > 0.02:
		var shape := _bird_shape(true, false)
		canvas.draw_set_transform(at, heading, Vector2(span * 0.9, span * 0.9 * wings))
		canvas.draw_colored_polygon(shape.wing, mantle)
		canvas.draw_colored_polygon(shape.wing_mirrored, mantle)
		canvas.draw_colored_polygon(shape.tip, parsed[2])
		canvas.draw_colored_polygon(shape.tip_mirrored, parsed[2])
	# The body, wings folded over it, their dark tips at the back (a crane's bustle).
	canvas.draw_set_transform(at, heading, Vector2.ONE)
	canvas.draw_colored_polygon(_oval(Vector2.ZERO, Vector2(body_len * 0.5, body_wide * 0.5)), mantle)
	canvas.draw_colored_polygon(_oval(Vector2(-body_len * 0.38, 0.0), Vector2(body_len * (0.2 if crane else 0.14), body_wide * (0.42 if crane else 0.3))), parsed[2] if crane else mantle.darkened(0.12))
	if colors.has("shoulder"):
		canvas.draw_colored_polygon(_oval(Vector2(body_len * 0.1, 0.0), Vector2(body_len * 0.18, body_wide * 0.35)), Color.from_string(str(colors.shoulder), mantle))
	# Neck and head.
	var head := Vector2(body_len * 0.42 + neck_len, 0.0)
	canvas.draw_line(Vector2(body_len * 0.35, 0.0), head, parsed[4], maxf(span * 0.034, 1.0), true)
	var head_r := span * 0.032
	canvas.draw_circle(head, head_r, head_color)
	var cheek: Color = parsed[7]
	if cheek.a > 0.0:
		for side: float in [-1.0, 1.0]:
			canvas.draw_circle(head + Vector2(-head_r * 0.2, side * head_r * 0.55), head_r * 0.45, cheek)
	var crown: Color = parsed[6]
	if crown.a > 0.0:
		if str(info.get("kind", "")) == "Crane" and str(info.get("latin", "")).begins_with("Balearica"):
			for i in 7:  # A crowned crane's golden crest, fanned out.
				canvas.draw_line(head, head + Vector2.from_angle(PI + (i - 3) * 0.32) * head_r * 2.2, crown, maxf(span * 0.008, 0.8), true)
		else:
			canvas.draw_circle(head + Vector2(-head_r * 0.1, 0.0), head_r * 0.55, crown)
	if bill_up:
		canvas.draw_circle(head + Vector2(head_r * 0.6, 0.0), head_r * 0.35, parsed[3])
	else:
		var bill_end := head + Vector2(span * (0.05 if crane else 0.075), 0.0)
		canvas.draw_line(head, bill_end, parsed[3], maxf(span * 0.014, 1.0), true)
		if fish:
			canvas.draw_line(bill_end + Vector2(0.0, -span * 0.03), bill_end + Vector2(0.0, span * 0.03), Color(0.78, 0.82, 0.86), maxf(span * 0.02, 1.2), true)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## The sea ducks off a port (Birds.port_sea_ducks()), out on the sea beyond
## its marina `radius` px across: each species a raft, the ducks facing into
## the wind and bobbing, drakes in their pattern and hens brown. Eiders dive
## each in its own time for mussels, scoters all together (a ripple where
## each goes down and comes up); now and then the whole raft patters off the
## water and flies low to settle somewhere new. In high summer eider hens
## lead their pooled ducklings. On migration they don't stop: long low Vs
## pass over the sea, north in spring and south in autumn.
func _draw_sea_ducks(port_id: String, root: Vector2, radius: float, now: float) -> void:
	var birds := Birds.shared()
	var sea := Vector2.from_angle(_port_sea_angle(port_id))
	var across := sea.orthogonal()
	var wind := Birds.chance([port_id, "wind"]) * TAU
	var month := Birds.month_of(float(GameState.calendar_time()))
	var entries := birds.port_sea_ducks(port_id)
	for e in entries.size():
		var entry: Dictionary = entries[e]
		var id: String = entry.id
		var info := birds.species(id)
		var count := int(entry.count)
		var traits := _bird_traits("ducks/%s/%s" % [port_id, id], count)
		var flock := {count = count, species = [id], key = id}
		var span := _bird_span(info)
		var side := 1.0 if Birds.chance([port_id, id, "side"]) < 0.5 else -1.0
		# Out on the sea off the marina: its side first, then the other, nearer or
		# further out (none at a port up a river, its sea too far off).
		var home := Vector2.INF
		for out: float in [2.2, 1.6, 3.0]:
			for flank: float in [side, -side]:
				var spot := root + sea * radius * (out + 0.7 * e) + across * radius * 1.3 * flank
				if home == Vector2.INF and _on_sea(spot):
					home = spot
		if home == Vector2.INF:
			continue
		if entry.moving:
			# Passing on migration: low over the sea in Vs of up to V_SIZE, one
			# behind another, each a little to the side.
			var north := month <= 6
			var way := Vector2(0.0, -1.0 if north else 1.0).rotated(0.3 * side)
			var s := fmod(now / 40.0 + Birds.chance([port_id, id, "pass"]), 1.0)
			var lead := home + way * radius * (12.0 * s - 6.0)
			for k in count:
				var t: PackedFloat32Array = traits[k]
				var v := k / V_SIZE
				var v_lead := lead - way * v * span * 5.0 + way.orthogonal() * span * 2.5 * (1.0 if v % 2 == 0 else -1.0) * signf(float(v))
				var pos := _v_spot(v_lead, way, k % V_SIZE, span) + way.orthogonal() * sin(now * 0.8 + v) * span * 0.15
				_draw_bird(pos, way.angle(), _duck_flying(info, t[4] < 0.45), 0.7 + 0.3 * absf(sin(now * 14.0 + k)), 0.4)
				_bird_hits.append([pos, maxf(span * 0.6, BIRD_HIT_MIN_PX), {port = port_id}, flock])
			continue
		# The raft's spot, and now and then a flight to a new one.
		var cycle := 120.0 + 60.0 * Birds.chance([port_id, id, "cycle"])
		var clock := now / cycle + Birds.chance([port_id, id, "clock"])
		var spell := floori(clock)
		var c := clock - spell
		var spot := func(n: int) -> Vector2:
			return home + Vector2.from_angle(Birds.chance([port_id, id, n, "a"]) * TAU) * radius * 0.8 * Birds.chance([port_id, id, n, "r"])
		var here: Vector2 = spot.call(spell)
		var raft := span * 0.45 * sqrt(float(count))
		var flying := c > 0.92
		var next: Vector2 = spot.call(spell + 1) if flying else here
		var sync := bool(info.get("sync", false))
		var creche := bool(info.get("creche", false)) and (month == 6 or month == 7)
		for k in count:
			var t: PackedFloat32Array = traits[k]
			var hen := t[4] < 0.45
			var place := Vector2.from_angle(t[0] * TAU) * raft * sqrt(t[2])
			var pos: Vector2 = here + place + Vector2(sin(now * 0.3 + t[1] * TAU), cos(now * 0.25 + t[0] * TAU)) * span * 0.08
			if flying:
				var s := (c - 0.92) / 0.08
				var go := clampf(s * 1.2 - t[1] * 0.2, 0.0, 1.0)  # (They don't all go at once.)
				pos = (here + place).lerp(next + place, smoothstep(0.0, 1.0, go))
				if go > 0.0 and go < 1.0:
					var heading := (next - here).angle()
					_draw_bird(pos, heading, _duck_flying(info, hen), 0.7 + 0.3 * absf(sin(now * 14.0 + k)), 0.3 * sin(go * PI))
					_bird_hits.append([pos, maxf(span * 0.6, BIRD_HIT_MIN_PX), {port = port_id}, flock])
					continue
				if go >= 1.0:
					pos = next + place
			# Diving for mussels: under for a spell (a ripple as it goes and comes up).
			var dive := fmod(now / (16.0 if sync else 9.0 + 5.0 * t[1]) + (0.0 if sync else t[0]), 1.0)
			var down := 0.55 + (t[1] * 0.06 if sync else 0.0)
			var up := down + 0.28
			if not flying and dive > down and dive < up:
				var ripple := (dive - down) / (up - down)
				for edge: float in [0.0, 1.0]:
					var r := 1.0 - absf(ripple - edge) * 6.0
					if r > 0.0:
						_canvas.draw_arc(pos, span * (0.12 + 0.2 * (1.0 - r)), 0.0, TAU, 12, Color(1, 1, 1, 0.6 * r), maxf(span * 0.03, 1.0), true)
				continue
			var facing := wind + 0.25 * (t[3] - 0.5) + 0.1 * sin(now * 0.4 + t[0] * TAU)
			draw_duck(_canvas, pos, facing, info, span, hen)
			if creche and hen and k % 3 == 0:
				for chick in 3:
					var behind := pos - Vector2.from_angle(facing) * span * (0.35 + 0.18 * chick) + Vector2.from_angle(facing).orthogonal() * span * 0.08 * sin(now * 2.0 + chick)
					_canvas.draw_circle(behind, maxf(span * 0.06, 1.0), Color(0.3, 0.24, 0.18))
			_bird_hits.append([pos, maxf(span * 0.5, BIRD_HIT_MIN_PX), {port = port_id}, flock])


## A sea duck's colors for drawing it flying (see draw_bird()): its back on
## the wings, its sides on the tips; a hen all brown.
static func _duck_flying(info: Dictionary, hen: bool) -> Dictionary:
	var colors: Dictionary = info.get("colors", {})
	var brown := str(colors.get("hen", "#6a4a30"))
	return {span = info.get("span", 0.7), colors = {mantle = brown if hen else colors.get("mantle", "#141416"), head = brown if hen else colors.get("head", "#141416"),
		tip = brown if hen else colors.get("wing", colors.get("sides", "#141416")), belly = brown, bill = "#3a3a3a" if hen else colors.get("bill", "#e8c040")}}


## A sea duck swimming, seen from above, `span` px its wingspan: a low oval
## body (a drake's sides, back, breast and wing patch in its colors; a hen
## brown), its head (cap, nape and face patches), bill and a faint wake.
static func draw_duck(canvas: CanvasItem, at: Vector2, heading: float, info: Dictionary, span: float, hen: bool) -> void:
	var colors: Dictionary = info.get("colors", {})
	var color := func(key: String, fallback: String) -> Color:
		return Color.from_string(str(colors.get(key, fallback)), Color.BLACK)
	var brown: Color = color.call("hen", "#6a4a30")
	var length := span * 0.5
	var width := span * 0.22
	canvas.draw_set_transform(at, heading, Vector2.ONE)
	canvas.draw_colored_polygon(_oval(Vector2(-length * 0.1, 0.0), Vector2(length * 0.62, width * 0.7)), Color(1, 1, 1, 0.12))
	canvas.draw_colored_polygon(_oval(Vector2(-length * 0.05, 0.0), Vector2(length * 0.5, width * 0.5)), brown if hen else color.call("sides", "#141416"))
	if not hen:
		canvas.draw_colored_polygon(_oval(Vector2(-length * 0.08, 0.0), Vector2(length * 0.36, width * 0.3)), color.call("mantle", "#141416"))
		if colors.has("breast"):
			canvas.draw_circle(Vector2(length * 0.25, 0.0), width * 0.4, color.call("breast", "#ffffff"))
		if colors.has("wing"):
			for edge: float in [-1.0, 1.0]:
				canvas.draw_rect(Rect2(Vector2(-length * 0.32, edge * width * 0.36 - width * 0.06), Vector2(length * 0.2, width * 0.12)), color.call("wing", "#ffffff"))
	else:
		canvas.draw_colored_polygon(_oval(Vector2(-length * 0.08, 0.0), Vector2(length * 0.34, width * 0.26)), brown.darkened(0.2))
	var head_at := Vector2(length * 0.44, 0.0)
	var head_color: Color = brown if hen else color.call("head", "#141416")
	if not hen and colors.has("nape"):
		canvas.draw_circle(head_at - Vector2(width * 0.25, 0.0), width * 0.3, color.call("nape", "#ffffff"))
	canvas.draw_circle(head_at, width * 0.4, head_color)
	if not hen:
		canvas.draw_circle(head_at + Vector2(width * 0.05, 0.0), width * 0.22, color.call("cap", "#141416"))
		if colors.has("patch"):
			for edge: float in [-1.0, 1.0]:
				canvas.draw_circle(head_at + Vector2(width * 0.02, edge * width * 0.28), width * 0.11, color.call("patch", "#ffffff"))
	var bill: Color = Color(0.25, 0.25, 0.25) if hen else color.call("bill", "#e8c040")
	canvas.draw_colored_polygon(PackedVector2Array([head_at + Vector2(width * 0.3, -width * 0.14), head_at + Vector2(width * 0.75, 0.0), head_at + Vector2(width * 0.3, width * 0.14)]), bill)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## An oval's outline points round a middle, with these half sizes.
static func _oval(middle: Vector2, half: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 14:
		var a := TAU * i / 14.0
		points.append(middle + Vector2(cos(a) * half.x, sin(a) * half.y))
	return points


## Steady numbers for each bird of a flock (0 to 1: where it starts round,
## how fast, how far out, which way, its rhythm), made once per flock.
func _bird_traits(key: String, count: int) -> Array:
	var traits: Array = _bird_trait_cache.get(key, [])
	while traits.size() < count:
		var k := traits.size()
		var values := PackedFloat32Array()
		for n in 5:
			values.append(Birds.chance([key, k, n]))
		traits.append(values)
	_bird_trait_cache[key] = traits
	return traits

## One bird seen from above at a screen point, heading a way (see draw_bird()),
## `height` times as high as a gull's usual (its shadow that much further off).
func _draw_bird(at: Vector2, heading: float, info: Dictionary, wings: float, height := 1.0) -> void:
	draw_bird(_canvas, at, heading, info, wings, _bird_span(info), true, height)


## A bird's wingspan on screen (px).
func _bird_span(info: Dictionary) -> float:
	return maxf(float(info.get("span", 1.0)) * BIRD_SCALE * _ship_scale(), BIRD_MIN_PX)


## A bird seen from above on any canvas item, at a point, heading a way,
## `span` px from wingtip to wingtip: body and tail in its mantle color, its
## head and bill (a pelican's long), wings out to its span (times `wings`,
## shorter as they beat up and down or fold) with dark tips, and its shadow
## below (`height` times as far off as usual). A raptor (one with a tail
## color) has broad wings with fingered tips (an osprey's bent at the wrist),
## a fanned tail and a hooked bill; some have pale or chestnut shoulders.
## Leaves the canvas item's transform reset.
static func draw_bird(canvas: CanvasItem, at: Vector2, heading: float, info: Dictionary, wings: float, span: float, shadow := true, height := 1.0) -> void:
	var colors: Dictionary = info.get("colors", {})
	# Its colors read from their names once, and kept with them (every bird, every frame).
	var parsed: Array = colors.get("_parsed", [])
	if parsed.is_empty():
		var mantle_color := Color.from_string(str(colors.get("mantle", "#aab4bd")), Color.GRAY)
		parsed = [mantle_color, Color.from_string(str(colors.get("head", "#f4f4f2")), Color.WHITE),
			Color.from_string(str(colors.get("tip", "#1e1e1e")), Color.BLACK), Color.from_string(str(colors.get("bill", "#e8c440")), Color.YELLOW),
			Color.from_string(str(colors.get("tail", "")), mantle_color), Color.from_string(str(colors.get("belly", colors.get("mantle", ""))), mantle_color),
			Color.from_string(str(colors.get("shoulder", "")), mantle_color)]
		if not colors.is_read_only():
			colors["_parsed"] = parsed
	var mantle: Color = parsed[0]
	var head: Color = parsed[1]
	var tip: Color = parsed[2]
	var bill: Color = parsed[3]
	var raptor := colors.has("tail")
	var wader := colors.has("legs")
	var shape := _bird_shape(raptor or wader, raptor and str(info.get("behavior", "")) == "plunge")
	# The shapes are a bird a unit across: the wings (out to their beat) drawn
	# scaled by its span along and its span times the beat across, the rest by its span.
	var wingspan := Vector2(span, span * wings)
	var whole := Vector2(span, span)
	if shadow:
		# Down and to the side on the water (further off the higher it is).
		var off := Vector2(span * 0.45, span * 0.55) * height
		var dark := Color(0, 0, 0, 0.16 / sqrt(maxf(height, 0.5)))
		canvas.draw_set_transform(at + off, heading, wingspan)
		canvas.draw_colored_polygon(shape.wing, dark)
		canvas.draw_colored_polygon(shape.wing_mirrored, dark)
		if raptor:
			canvas.draw_set_transform(at + off, heading, whole)
			canvas.draw_colored_polygon(shape.tail, dark)
	if raptor:
		canvas.draw_set_transform(at, heading, whole)
		canvas.draw_colored_polygon(shape.tail, parsed[4])
	canvas.draw_set_transform(at, heading, wingspan)
	canvas.draw_colored_polygon(shape.wing, mantle)
	canvas.draw_colored_polygon(shape.wing_mirrored, mantle)
	if colors.has("shoulder"):
		canvas.draw_set_transform(at, heading, whole)
		var shoulder: Color = parsed[6]
		var patch := PackedVector2Array([Vector2(0.05, 0.05), Vector2(0.05, 0.5 * wings * 0.45), Vector2(-0.03, 0.5 * wings * 0.45), Vector2(-0.03, 0.05)])
		canvas.draw_colored_polygon(patch, shoulder)
		canvas.draw_colored_polygon(_mirror_y(patch), shoulder)
		canvas.draw_set_transform(at, heading, wingspan)
	canvas.draw_colored_polygon(shape.tip, tip)
	canvas.draw_colored_polygon(shape.tip_mirrored, tip)
	canvas.draw_set_transform(at, heading, whole)
	var long_bill := str(info.get("behavior", "")) == "line"
	var body := mantle.lerp(head, 0.25)
	if raptor:
		body = mantle.lerp(parsed[5], 0.2)
	canvas.draw_colored_polygon(_bird_body, body)
	if raptor:
		# A big head and a short hooked bill.
		canvas.draw_circle(Vector2(0.17, 0.0), 0.065, head)
		canvas.draw_colored_polygon(_raptor_bill, bill)
	elif wader:
		# Long legs trailing behind; a crane's neck stretched out ahead, a
		# heron's (an egret's, a bittern's) drawn back in an S, its head by its
		# shoulders and its bill out in front.
		var legs := Color.from_string(str(colors.get("legs", "#2a2a2a")), Color.BLACK)
		for side: float in [-1.0, 1.0]:
			canvas.draw_line(Vector2(-0.2, side * 0.012), Vector2(-0.44, side * 0.016), legs, maxf(span * 0.012, 0.8) / span)
		var neck := Color.from_string(str(colors.get("neck", colors.get("head", ""))), head)
		if str(info.get("kind", "")) == "Crane":
			canvas.draw_line(Vector2(0.12, 0.0), Vector2(0.32, 0.0), neck, 0.035)
			canvas.draw_circle(Vector2(0.33, 0.0), 0.03, head)
			if colors.has("crown"):
				canvas.draw_circle(Vector2(0.33, 0.0), 0.016, Color.from_string(str(colors.crown), head))
			canvas.draw_line(Vector2(0.36, 0.0), Vector2(0.42, 0.0), bill, maxf(span * 0.015, 1.0) / span)
		else:
			canvas.draw_circle(Vector2(0.15, 0.0), 0.045, neck)
			canvas.draw_circle(Vector2(0.17, 0.0), 0.035, head)
			canvas.draw_line(Vector2(0.2, 0.0), Vector2(0.3, 0.0), bill, maxf(span * 0.018, 1.0) / span)
	elif str(info.get("kind", "")) == "Cormorant":
		# A long neck stretched out ahead, a small head (a pale cheek or bright
		# throat on some) and a thin hooked bill.
		canvas.draw_line(Vector2(0.12, 0.0), Vector2(0.3, 0.0), head, 0.05)
		canvas.draw_circle(Vector2(0.31, 0.0), 0.04, head)
		if colors.has("cheek"):
			for edge: float in [-1.0, 1.0]:
				canvas.draw_circle(Vector2(0.31, 0.022 * edge), 0.016, Color.from_string(str(colors.cheek), head))
		if colors.has("throat"):
			canvas.draw_circle(Vector2(0.34, 0.0), 0.018, Color.from_string(str(colors.throat), head))
		canvas.draw_line(Vector2(0.34, 0.0), Vector2(0.42, 0.0), bill, maxf(span * 0.02, 1.0) / span)
	else:
		canvas.draw_circle(Vector2(0.17, 0.0), 0.055, head)
		canvas.draw_line(Vector2(0.21, 0.0), Vector2(0.36 if long_bill else 0.27, 0.0), bill, maxf(span * 0.03, 1.0) / span)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A bird's wings, wingtips and (a raptor's) tail a unit across, made once
## (see draw_bird()): {wing, wing_mirrored, tip, tip_mirrored, tail}. A gull or
## seabird's wings swept back to their tips; a raptor's broad and square (bent
## forward at the wrist for an osprey), the tips spread into fingers.
static func _bird_shape(raptor: bool, bent: bool) -> Dictionary:
	var key := 2 if bent else (1 if raptor else 0)
	if _bird_shapes.has(key):
		return _bird_shapes[key]
	var half := 0.5
	var wing: PackedVector2Array
	var tip_part: PackedVector2Array
	var tail := PackedVector2Array()
	if raptor:
		var wrist := Vector2(0.11 if bent else 0.07, half * 0.5)
		wing = PackedVector2Array([Vector2(0.07, 0.0), wrist, Vector2(0.03, half * 0.86), Vector2(-0.15, half * 0.86),
			Vector2(-(0.1 if bent else 0.17), half * 0.5), Vector2(-0.13, 0.0)])
		tip_part = PackedVector2Array([Vector2(0.03, half * 0.84)])
		for k in 5:
			var x := 0.03 - 0.045 * k
			tip_part.append(Vector2(x, half * (0.9 + 0.1 * sin(PI * (k + 0.5) / 5.0))))
			tip_part.append(Vector2(x - 0.022, half * 0.88))
		tip_part.append(Vector2(-0.16, half * 0.84))
		var fan := 0.07 if bent else 0.11
		tail = PackedVector2Array([Vector2(-0.18, 0.045), Vector2(-0.34, fan), Vector2(-0.36, 0.0), Vector2(-0.34, -fan), Vector2(-0.18, -0.045)])
	else:
		wing = PackedVector2Array([Vector2(0.06, 0.0), Vector2(-0.04, half), Vector2(-0.13, half * 0.96), Vector2(-0.1, 0.0)])
		tip_part = PackedVector2Array([Vector2(-0.01, half * 0.7), Vector2(-0.04, half), Vector2(-0.13, half * 0.96), Vector2(-0.11, half * 0.7)])
	_bird_shapes[key] = {wing = wing, wing_mirrored = _mirror_y(wing), tip = tip_part, tip_mirrored = _mirror_y(tip_part), tail = tail}
	return _bird_shapes[key]


static func _mirror_y(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p.x, -p.y))
	return out


## The flock of birds drawn under a screen point, if any: [what it's round
## ({port}, {ship} or {pod}), the flock ({count, species})], or []; `reach`
## times its usual reach (smaller: only right on a bird).
func _birds_at(screen_pos: Vector2, reach := 1.0) -> Array:
	for i in range(_bird_hits.size() - 1, -1, -1):
		var hit: Array = _bird_hits[i]
		if (hit[0] as Vector2).distance_to(screen_pos) <= float(hit[1]) * reach:
			return [hit[2], hit[3]]
	return []

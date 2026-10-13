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
## A group of land animals was clicked: its group (Wildlife.groups, its index as
## text) and species (see _draw_wildlife()).
signal animals_clicked(key: String, kind: String)
## A home was clicked: "colony" (a bird colony's, Wildlife.colonies) or "home"
## (a land group's, Wildlife.groups), and its index (see _draw_wildlife()).
signal home_clicked(kind: String, index: int)
## One of this player's hubs' industry plots was clicked (see _industry_plots()).
signal industry_clicked(port_id: String, slot: int)
## A wonder of the world clicked (see _draw_wonders()).
signal wonder_clicked(id: String)
## Emitted whenever the view pans or zooms.
signal view_changed
## While choosing a region to unlock (choosing_region): a locked region's
## area was clicked (its markets.json id).
signal region_clicked(region_id: String)
## While choosing a divine power's target (choosing_divine): the target picked,
## a (lon, lat) Vector2 for a point, a port id, a Ship, or null for nothing there.
signal divine_target(target: Variant)

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
## A port's shore beside its marina (see _shore_spots()): how far out either
## side it's looked for (marina radii), at how many places, and how far in
## from the sea and out to it.
const SHORE_REACH := 3.2
const SHORE_SAMPLES := 24
const SHORE_INLAND := 2.6
const SHORE_SEAWARD := 3.0
## Ships drawn full size are picked on their hulls (see _ship_on_hull()); the
## rest (dots) within this many dock units of their middle.
const SHIP_HIT_RADIUS := 6.0
## However small ships are drawn, a click this close (px) still picks one.
const SHIP_HIT_MIN_PX := 7.0
## Ships shorter than this on screen (px) are drawn as dots (see
## _draw_tiny_ship(); cargo ships plainly on their lanes by the native fleet
## pass, all in one batch: see _fleet_pass()).
const TINY_SHIP_PX := 4.0
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
## (degrees) they're sorted into, and each kind's size in the world (km
## across, exaggerated so they read): they grow and shrink with the map like
## the land. A drawing shows once it's DECOR_MIN_PX across; below
## DECOR_FULL_PX only some of them (by tier), so the land thins out zoomed out
## rather than turning to noise. The animals are the wildlife's (Wildlife:
## their spots are its home ranges) and the pizza on Albuquerque is a
## close-up secret, small as it is.
const DECOR_ART_DIR := "res://art/decor/"
const DECOR_BUCKET := 2.5
const DECOR_KM := {conifer = 17.0, deciduous = 17.0, rainforest = 19.0, palm = 14.0, acacia = 15.0, grass = 9.0, shrub = 10.0,
	birch = 15.0, oak = 18.0, cypress = 12.0, baobab = 16.0, mangrove = 11.0, cherry = 14.0,
	cactus = 9.0, dunes = 30.0, red_rock = 26.0, waves = 60.0, pizza = 7.0,
	mountain = 82.0, mountain_b = 74.0, mountain_c = 88.0, mountain_snow = 86.0, mountain_snow_b = 78.0, mountain_snow_c = 92.0}
const DECOR_MIN_PX := 5.0
const DECOR_FULL_PX := 16.0
const DECOR_ANIMALS: Array[String] = ["penguin", "polar_bear", "camel", "elephant", "giraffe", "lion", "zebra", "kangaroo", "koala",
	"panda", "tiger", "bison", "moose", "brown_bear", "reindeer", "llama", "toucan", "gorilla", "orangutan", "kiwi", "lemur",
	"quetzal", "water_buffalo"]
## The wildlife (see _draw_wildlife()): where its art is (each drawing 64
## units across), the smallest an animal or home is drawn (px), the biggest
## animal (km, so the map knows when none would show), and how long (life
## seconds: Wildlife) a walking animal's stride takes.
const WILDLIFE_ART_DIR := "res://art/wildlife/"
const WILDLIFE_MIN_PX := 3.0
const WILDLIFE_HOME_MIN_PX := 5.0
const WILDLIFE_LARGEST_KM := 13.5
const WILDLIFE_STRIDE_S := 500.0
## Kilometers in a degree of the globe's surface (px per km = _zoom / this).
const KM_PER_DEGREE := 111.32
## Birds perched on a breakwater stand this far apart (dock units), room for a
## cormorant to hold its wings out to dry.
const PERCH_SPACING := 1.2
## Perching spots on a rock (see _bird_spots()) are this far apart (dock units).
const ROCK_PERCH_SPACING := 0.7
## Wonders of the world (data/wonders.json, see _draw_wonders()): where their
## art is; how big (px) one must be to show, and for its name to show; how
## faded the lost ancient ones are; their names' size; how far (km) they're
## kept clear of a port's marina; and, for the ones along a course, the
## Great Wall's watchtowers' spacing, the Barrier Reef's reefs' spacing, the
## Northern Lights' height, and how long a stretch they count as for their
## names to show (all in km).
const WONDER_ART_DIR := "res://art/wonders/"
const WONDER_MIN_PX := 5.0
const WONDER_LABEL_PX := 42.0
const WONDER_LOST_ALPHA := 0.62
const WONDER_FONT_SIZE := 12
const WONDER_PORT_GAP_KM := 4.0
const WALL_TOWER_KM := 40.0
const REEF_SPACING_KM := 45.0
const AURORA_HEIGHT_KM := 260.0
const WONDER_LINE_LABEL_KM := 120.0
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
const MAX_ZOOM := 6000.0
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
## The globe art is cut into tiles this size (projected degrees: see _tiled()),
## each one's reach worked out from this many samples across it each way.
const TILE_DEG := 30.0
const TILE_SAMPLES := 8
## Zoomed in until the view reaches less than this far round the globe
## (radians from its middle), only the art's tiles in view are drawn.
const TILE_MAX_REACH := 1.0
## The tiles drawn reach this much (radians) beyond the view, so dragging
## only draws them again every few degrees.
const TILE_SLACK := 0.1
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
const SHIP_SIZE := 0.245
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
const SHIP_WORLD_ZOOM := 88.235  # (75 / 0.85: ships, marinas and all in dock units 15% smaller than before 2026-10-13.)
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
## How far (dock units) a tug moored along its marina's breakwater lies off its face.
const TUG_HULL_GAP := 0.3
## Tugs moor along the inside of their marina's breakwater (see _jetty_pose()):
## the first this far (radians) round from where it meets the quay, each the
## next this far (dock units) on from the last.
## The tugs' moorings along the inside of the jetty's arms run from this far
## round from the entrance (radians) towards it (see _marina_layout()).
const TUG_ARM_FROM := 0.95
## Where a tug coming home makes for first, the land end of its arm (shares of the jetty's radius, x and y).
const TUG_ARM_END := Vector2(0.33, 0.85)
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
enum FeatureKind { OCEAN, SEA, STRAIT, RANGE, DESERT, LAKE, RIVER, TRENCH }  # (TRENCH: GameData.TRENCH_KIND.)
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
	FeatureKind.TRENCH: [12, &"trench_label", true, 2, 0.0],
}
## Which kinds get placed first when labels would overlap (after ports and
## countries); rivers before mountain ranges, so a river shows across a range.
const FEATURE_PRIORITY: Array[int] = [FeatureKind.OCEAN, FeatureKind.SEA, FeatureKind.RIVER, FeatureKind.RANGE,
	FeatureKind.DESERT, FeatureKind.STRAIT, FeatureKind.TRENCH, FeatureKind.LAKE]
## The kinds over the sea, drawn with a dark edge so they read over shallow (light) water too.
const OUTLINED_FEATURES: Array[int] = [FeatureKind.OCEAN, FeatureKind.SEA, FeatureKind.STRAIT, FeatureKind.TRENCH]
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
## Solid lines on screen leave out points closer together than this (px): see _draw_line_runs().
const LINE_MIN_PX := 1.5
## The fleet's lanes are laid out for the passes ahead of time for up to this
## long a frame (ms): see _warm_lanes().
const LANE_WARM_MS := 3.0
## How often (s) the ports' marina sizes are looked at, for what depends on them (see _check_port_sizes()).
const PORT_SIZE_CHECK_S := 5.0
## The land's triangles are sorted into cells this big (projected degrees) to
## tell if a point's on the land (see _on_land()).
const LAND_CELL_DEG := 1.0
## How far (projected degrees) the view moves before route lines' harbour curves
## are worked out again (see _lane_pieces()): the globe's turn changes them
## by a hair over that.
const LANE_CURVE_DRIFT := 1.0
## How long (ms) a frame may spend working out harbour curves (see _lane_curve_memo()).
const LANE_CURVE_MS := 1.5
var _lane_curve_frame := -1
var _lane_curve_spent := 0.0
## Width of the dark edge round ocean, sea and strait names.
const SEA_LABEL_OUTLINE := 3
## Width of the dark edge round ocean, sea and strait names.
const ACTIVE_LANE_WIDTH := 1.5
## The native lane pass drops a lane's point while the line through its
## neighbours passes within this (px) of it: zoomed out, a great circle's many
## points go (the line never leaves its path by a third of a pixel); a bend
## round a coast stays.
const ACTIVE_LANE_MIN_PX := 0.35
## How often (s) the fleet's lanes are gathered again (a loop over every ship; a new leg's lane shows within this).
const ACTIVE_LANES_REFRESH_S := 1.0
## Canals (data/canals.json): the channel's width in projected degrees (at
## least CANAL_MIN_WIDTH px), and each lock chamber's length and the width of
## each of its two lanes (one per direction), drawn from LOCK_MIN_ZOOM (pixels
## per degree). Ships in a canal keep to the right-hand lane.
const CANAL_WIDTH := 0.028
const CANAL_MIN_WIDTH := 5.0
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
## Price boxes (see price_line): their text size, padding (px) and gap
## between a commodity's name and its figure; their background; how often
## (seconds) their figures are worked out again as prices drift; the colors
## for cheap and dear prices (against the world average, full at half or
## twice it) and for a good profit (full at PRICE_GOOD_MARGIN of the buy
## price), and a loss's.
const PRICE_FONT_SIZE := 12
const PRICE_PADDING := Vector2(6.0, 3.0)
const PRICE_GAP := 10.0
const PRICE_BACKGROUND := Color(0.05, 0.07, 0.11, 0.85)
const PRICE_REFRESH_S := 1.0
const PRICE_CHEAP := Color(0.45, 0.75, 1.0)
const PRICE_DEAR := Color(1.0, 0.62, 0.25)
const PRICE_PROFIT := Color(0.35, 0.95, 0.45)
const PRICE_GOOD_MARGIN := 0.5
const PRICE_LOSS := Color(0.9, 0.45, 0.4)
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
	&"trench_label": Color(0.55, 0.86, 0.9, 0.8),
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

## A ship line (ship_models.json category, e.g. "grain") whose cargo gets a
## box over each port with room for one (see _place_price_boxes()): each
## commodity's price there, or with price_origin its profit carried there from
## the origin; "" for none.
var price_line := "":
	set(value):
		price_line = value
		_prices_changed()
## A commodity id to color the ports by (green where it's cheap, white about
## its world average, red where it's dear: see _price_color()), or "" for none.
var price_commodity := "":
	set(value):
		price_commodity = value
		_static_layer.queue_redraw()
## The ports' colors by price (see price_commodity): full green at its world
## average price over PORT_PRICE_SPAN or less, white at the average, full red at
## PORT_PRICE_SPAN times it or more (most prices run from about half to one
## and a half times the average).
const PORT_PRICE_CHEAP := Color(0.2, 0.85, 0.3)
const PORT_PRICE_DEAR := Color(0.95, 0.2, 0.15)
const PORT_PRICE_SPAN := 1.4
## Where the cargo would be loaded, for price_line's boxes: its own box shows
## what each commodity costs to buy there, every other port's the profit per
## unit (per load with price_ship) of carrying it there. "" for plain prices.
var price_origin := "":
	set(value):
		price_origin = value
		_prices_changed()
## The ship a route is being built for, or null: the boxes show only its cargo,
## its owner's prices and bonuses, and profits per load of it.
var price_ship: Ship = null:
	set(value):
		price_ship = value
		_prices_changed()

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
## The divine power whose target is being chosen on the map (Divine.POWERS),
## or "": clicks then pick a point, a port or a ship (divine_target) instead.
var choosing_divine := "":
	set(value):
		choosing_divine = value
		mouse_default_cursor_shape = CURSOR_CROSS if not value.is_empty() else CURSOR_ARROW
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
## The land drawings picked and drawn natively (DecorSim), when the library's
## there, and whether it has their regions yet.
static var _decor_native: Object = null
static var _decor_regions_native := false

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
## Each sea lane's chunks a ship can be seen on (1) or not (see _on_lane_in_view()), till the view changes.
var _lanes_in_view := {}
## Goes up each time the view changes (for what's kept till it does: see _fleet_pass()).
var _view_epoch := 0
## The native fleet pass (ShipCuller), when the native library's loaded; null otherwise.
var _ship_culler: Object = null
## The native lane pass (LanePainter), when the native library's loaded; null otherwise.
var _lane_painter: Object = null
## Lanes put on screen natively (LaneMath.lane_on_screen() and visible_runs()), if the library has them.
var _native_lane_screen := ClassDB.class_has_method(&"LaneMath", &"lane_on_screen")
## How far round the globe (radians from its middle) the view reaches (with a
## few px to spare); whether the art was last drawn tile by tile, and if so,
## round which middle and how far (see _tile_in_view()).
var _tile_reach := PI
var _art_tiled := false
var _art_toward := Vector3.ZERO
var _art_reach := PI
## The land's triangles by cell (see _on_land()), and the task sorting them.
static var _land_cells := {}
## The same land test natively (LandTest), when the library's there (see _on_land()).
static var _land_test: Object = null
static var _land_task := -1
## The fleet's lanes (see _active_lanes()), and when (ms) they were worked out.
var _active_lanes_cache := []
var _active_lanes_epoch := 0  # (Up each time they change: see _draw_active_lanes().)
## True once every active lane is bent both ways (see _warm_lanes()).
var _lanes_warm := false
var _active_lanes_time := -1
## Gust cells' steady offsets and their spots this cycle (see _draw_gusts()).
var _gust_offsets := {}
var _gust_spots := {}
## Each cormorant species' colors for drawing it swimming (see _cormorant_swimmer()).
var _cormorant_swimmers := {}
## Port id -> its shore beside its marina, found once (see _shore_spots()).
var _shores := {}
var _shore_neighbours := {}  # Port id -> the ports near it (see _local_on_land()).
## Port ids by 3-degree cell of the map (see _local_on_land()).
static var _port_grid := {}
## Tests: work the shore out in GDScript even with the native library there.
var native_shores_off := false
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
## Where each ship's hull was last drawn, for clicks (see _ship_on_hull()):
## ship -> [where, angle]. Ships drawn as dots aren't in it.
var _ship_hulls := {}
var _draw_order_dirty := true
## Each ship's length (dock units) and dot colour by its place in _draw_order (see _fleet_pass()).
var _order_lengths := PackedFloat32Array()
var _order_colors := PackedColorArray()
var _order_colors_gray := false
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
var _port_text_sizes := {}  # Port id -> its name's size (px) at PORT_FONT_SIZE.
## The frame the labels were last placed afresh: dragging or zooming, they're
## placed again every LABEL_REPLACE_FRAMES, and between those each stays with
## its anchor (see _shift_labels()).
var _labels_placed_frame := -100
const LABEL_REPLACE_FRAMES := 4
## The labels' atlas (see LabelAtlas) and the layer over _static_layer they're
## drawn from it on, all of a frame's in one batch (see _draw_label_layer()).
var _label_atlas: LabelAtlas = null
var _label_layer := Control.new()
var _label_batch := PolyBatch.new()
## Placed price boxes: [port id, rect, rows], rows being [name, figure, color,
## figure width]; each port's box worked out for the current prices (port id ->
## {rows, size, score}, or null for no box), when that was (msec), and a count
## of the times it was, for _labels_key.
var _price_boxes := []
var _price_rows := {}
var _price_time := -INF
var _price_epoch := 0
## The ports' dots drawn natively (PortPainter), when the library's there, and
## what their looks were last worked out for (see _update_port_styles()).
var _port_painter: Object = null
var _port_styles_key := []
var _port_styles_radii := PackedFloat32Array()  # (Each port's dot's radius, to a quarter px, as last looked at.)
var _port_bands := PackedStringArray()  # Each port's size band as its marina's radius was last worked out...
var _port_layout_radii := PackedFloat32Array()  # ...and that radius.
var _port_styles_key_hubs := []
var _port_styles_time := -1000000
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
## The wildlife over the land drawings (see _draw_wildlife(): every frame while
## any shows), and whether any did.
var _fauna_layer := Control.new()
## The wonders of the world (see _draw_wonders()), over the land animals, and
## their art (in GameData.wonders order).
var _wonder_layer := Control.new()
static var _wonder_textures: Array[Texture2D] = []
## Each wonder's spot (see _wonder_spot()), by index, and the marinas they were worked out for.
var _wonder_spots := {}
var _wonder_spots_key := -1
## Where each wonder was drawn: [middle, reach (px), id, course (screen points, for one along a course)].
var _wonder_hits := []
## Wonders along a course: their boxes of (lon, lat) (see _wonder_line_box()).
var _wonder_line_boxes := {}
var _wildlife_shown := false
## The land animals worked out and drawn natively (LandSim), when the library's there.
var _land_sim: Object = null
## What wildlife was drawn where, for clicking: [screen point, reach (px),
## "group", "colony" or "home", index]. And its art by name.
var _fauna_hits := []
## Route lines' curves' reaches along their lanes (see _lane_pieces()), for one zoom.
var _lane_reach_memo := {}
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
## Pod -> the box (lon, lat) it keeps to till it leaves its area, and when (see _draw_sea_life()).
var _pod_bounds := {}
## Each sea animal's breach or surfacing this slot: [pod, animal, what, slot] -> when it starts, or NAN for none (see _sea_event()).
static var _sea_events := {}
## The wind's gusts drawn natively (GustPainter), when the library's there.
var _gust_painter: Object = null
## The sea animals drawn natively (SeaPainter), when the library's there, and their
## species as it draws them (see _sea_kind_index()).
var _sea_painter: Object = null
var _sea_kinds := []
var _sea_kind_indices := {}
const NO_POD_BOUND := [Rect2(), -INF]
## Until the sea animals' migration paths are all found (see SeaLife.start_warm_up()).
var _sea_warming := true
## Land drawings: a texture per kind (WorldMapData.decor_kind_names), and the
## drawings by DECOR_BUCKET-degree cell, so only those near the view are looked at.
static var _decor_textures: Array[Texture2D] = []
## All of them in one texture, and where each is in it (see _build_decor_atlas()).
static var _decor_atlas: ImageTexture = null
static var _decor_atlas_regions: Array = []
static var _wildlife_art := {}
## The rocks' art (see _rock_texture()).
static var _rock_art: Array[Texture2D] = []
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
## Birds keeping still a while (see _draw_still_birds()), under the ships and
## the birds on the move; which birds it shows, where they were drawn (for
## clicks), when it's to be drawn again (bird time), and Wildlife.where_changes then.
var _still_birds := Control.new()
var _still_drawn := {}
var _still_hits: Array = []
var _still_redraw_at := -INF
var _still_epoch := -1
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
		var tiles := view._art_tiles()
		if not view.gray_mode:
			for band in depth_meshes.size():
				view._draw_tiled(self, depth_meshes[band], tiles.depths[band] if tiles else [], white, view._depth_color(band + 1))
				view._draw_tiled(self, depth_hole_meshes[band], tiles.depth_holes[band] if tiles else [], white, view._depth_color(band))

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
		view._draw_tiled(self, art.land_mesh, view._art_tiles().get("land", []), art.land_texture(), art.land_tint())
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
	var view: MapView

	func _draw() -> void:
		view._draw_tiled(self, art.land_mesh, view._art_tiles().get("land", []), art.white)

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
			view._draw_tiled(self, art.biome_mesh, view._art_tiles().get("biome", []), art.white)

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
				view._draw_tiled(self, art.lake_meshes[i], view._art_tiles().lakes[i] if view._art_tiles() else [], art.white, view._color(&"ocean") if view.gray_mode else art.lake_colors[i])

## Over the land, lakes and lake ice: the lakes' islands, the borders, the
## coast, and the equator, faint.
class TopArt:
	extends Node2D

	var view: MapView
	var art: WorldArt

	func _draw() -> void:
		var data := GameData.world_map
		var tiles := view._art_tiles()
		view._draw_tiled(self, art.lake_island_mesh, tiles.get("lake_island", []), art.land_texture(), art.land_tint())
		view._draw_tiled_lines(self, data.border_segments, tiles.get("border", []), view._color(&"border"))
		view._draw_tiled_lines(self, data.coast_segments, tiles.get("coast", []), view._color(&"coast"))
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
	## Its place in WorldMapData.river_tiers (for its tiles: see MapView._tiled()).
	var tier := 0

	func _draw() -> void:
		view._draw_tiled_lines(self, segments, view._art_tiles().rivers[tier] if view._art_tiles() else [], view._color(&"river"))

func _exit_tree() -> void:
	if GameState.anchor_route.get_object() == self:
		GameState.anchor_route = Callable()
	if GameState.berth_route.get_object() == self:
		GameState.berth_route = Callable()

func _ready() -> void:
	ambience = Ambience.new(self)
	add_child(ambience)  # The World map's sound: sea, harbours, storms, horns and the animals in view (see Ambience).
	clip_contents = true
	mouse_filter = MOUSE_FILTER_STOP
	resized.connect(_on_resized)
	Settings.changed.connect(func() -> void:  # (Day and night or the birds switched: the layers kept between changes are drawn again.)
		if _still_birds != null:
			_still_birds.queue_redraw()
		if _lights_layer != null:
			_lights_layer.queue_redraw()
		_changed())
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
		tier.tier = i
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
	_land_mask_art.view = self
	_land_mask_art.material = _globe
	RenderingServer.canvas_item_set_custom_rect(_land_mask_art.get_canvas_item(), true, NEVER_CULLED)
	_land_mask.add_child(_land_mask_art)

	for layer: Control in [_decor_layer, _fauna_layer, _wonder_layer, _dock_layer]:
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
	for layer: Control in [_weather_layer, _canal_layer, _static_layer, _label_layer, _still_birds, _overlay]:
		layer.mouse_filter = MOUSE_FILTER_IGNORE
		layer.set_anchors_preset(PRESET_FULL_RECT)
		add_child(layer)
	_lane_material.shader = LANES_SHADER
	_lane_mesh_node.material = _lane_material
	_lane_mesh_node.visible = false
	_lane_mesh_node.draw.connect(func() -> void:
		if _lane_mesh != null:
			_lane_mesh_node.draw_mesh(_lane_mesh, null))
	add_child(_lane_mesh_node)
	move_child(_lane_mesh_node, _static_layer.get_index())  # (Under the ports and labels, over the weather and canals.)
	var label_material := ShaderMaterial.new()
	label_material.shader = LabelAtlas.LABEL_SHADER
	_label_layer.material = label_material
	_label_layer.draw.connect(_draw_label_layer)
	_label_atlas = LabelAtlas.new()
	add_child(_label_atlas)
	_preload_label_atlas()
	_decor_layer.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_decor()
		_prof("decor", t0))
	_decor_layer.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_fauna_layer.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_wildlife()
		_prof("wildlife", t0))
	_fauna_layer.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_wonder_layer.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_wonders()
		_prof("wonders", t0))
	_wonder_layer.texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_decor()
	_load_wildlife_art()
	_start_land_cells()  # (For the moorings and the harbour curves: see _on_land().)
	_weather_layer.draw.connect(_draw_weather_layer)
	_canal_layer.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_canal_layer()
		_prof("canals", t0))
	_static_layer.draw.connect(_draw_static_layer)
	_overlay.draw.connect(_draw_overlay)
	_still_birds.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_still_birds()
		_prof("still_birds", t0))
	_dock_layer.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_dock_layer()
		_prof("dock_layer", t0))
	_add_night_layers()
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
	var t_all := Time.get_ticks_usec()
	_process_timed(delta)
	_prof("process.total", t_all)

func _process_timed(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_ease_view(delta)
	_track_followed()
	_update_regions()
	_update_sky()
	_update_seasons()
	_update_night()
	_prof("process.view", t0)
	if _label_atlas != null:
		_label_atlas.render(get_viewport().get_final_transform().get_scale().x)  # (Once, and again if the window's scale changes.)
	if _layers_stale:
		_flush_layers()  # (After the view eased: see _redraw_layers().)
	if _marinas_pending:
		_update_marinas()  # (The marinas that waited their turn.)
	_warm_towns()
	t0 = Time.get_ticks_usec()
	Wildlife.shared().step(delta)
	_prof("process.wildlife", t0)
	if _wildlife_shown:
		_fauna_layer.queue_redraw()  # The wildlife going about its life.
	if not show_ships:
		if not price_line.is_empty() and Time.get_ticks_msec() - _price_time >= PRICE_REFRESH_S * 1000.0:
			_static_layer.queue_redraw()  # (The price boxes' figures, as prices drift.)
		return
	# Made ahead, off the main thread, so the first look at a port's birds
	# doesn't wait for them; and the lanes bent a few at a time (see _warm_lanes()).
	if not gray_mode:
		var t_b := Time.get_ticks_usec()
		BirdLife.shared().ensure_built()
		_prof("process.birds", t_b)
	t0 = Time.get_ticks_usec()
	_warm_lanes()
	_prof("process.warm_lanes", t0)
	t0 = Time.get_ticks_usec()
	_warm_moorings()
	_prof("process.warm_moorings", t0)
	_weather_layer.queue_redraw()
	_canal_layer.queue_redraw()
	_overlay.queue_redraw()
	if _sea_warming:
		SeaLife.shared().start_warm_up()  # Their paths are found off the main thread.
		_sea_warming = not SeaLife.shared().is_ready()
	_ice_clock += delta
	if _ice_clock >= ICE_REFRESH_S:
		_ice_clock = 0.0
		var t_i := Time.get_ticks_usec()
		_update_ice()
		_prof("process.ice", t_i)
	if _track_icebreakers():
		for node in _ice_arts:
			node.queue_redraw()
	# Route lanes follow the ships' legs, hub rings the hubs and price boxes the
	# drifting prices: a few times a second is plenty.
	_static_clock += delta
	if _static_clock >= STATIC_REFRESH_S:
		_static_clock = 0.0
		_static_layer.queue_redraw()
		_dock_layer.queue_redraw()  # Ports grow and shrink, and their rings with them.
		t0 = Time.get_ticks_usec()
		_update_marinas()
		_prof("process.marinas", t0)

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
	# The same cut into tiles (see _tiled()), for views zoomed in: natively, or not at all.
	if ClassDB.class_exists(&"GlobeTiles"):
		var depth_tiles := []
		var depth_hole_tiles := []
		for band in data.depth_levels.size():
			var cap := north_cap if data.depth_levels[band] <= ARCTIC_DEPTH else PackedVector2Array()
			depth_tiles.append(_tiled(data.depth_triangles[band] + cap))
			depth_hole_tiles.append(_tiled(data.depth_hole_triangles[band]))
		_shared_meshes.tiles = {
			land = _tiled(data.land_triangles),
			biome = _tiled(data.biome_triangles, data.biome_colors),
			lake_island = _tiled(data.lake_island_triangles),
			lakes = data.lake_triangles.map(func(triangles: PackedVector2Array) -> Array: return _tiled(triangles)),
			depths = depth_tiles,
			depth_holes = depth_hole_tiles,
			coast = _tiled(data.coast_segments, PackedColorArray(), 2),
			border = _tiled(data.border_segments, PackedColorArray(), 2),
			rivers = data.river_tiers.map(func(segments: PackedVector2Array) -> Array: return _tiled(segments, PackedColorArray(), 2)),
		}
	return _shared_meshes

## Map triangles (or, `per_shape` 2, line segments) cut into TILE_DEG tiles:
## [[a mesh of its triangles (or its segments), its middle on the unit sphere,
## how far (radians) its furthest point is from that], ...]. Zoomed in, only
## the tiles near the view are drawn (see _draw_tiled()): the art's hundreds
## of thousands of triangles are mostly round the far side or off screen.
static func _tiled(points: PackedVector2Array, colors := PackedColorArray(), per_shape := 3) -> Array:
	var out := []
	for tile: Dictionary in ClassDB.class_call_static(&"GlobeTiles", &"split", points, colors, per_shape, TILE_DEG):
		# Its reach from samples across its box (a lon, lat box on the globe), with
		# half a sample's step to spare.
		var box: Rect2 = tile.box
		var samples := PackedVector3Array()
		var middle := Vector3.ZERO
		for i in TILE_SAMPLES + 1:
			for j in TILE_SAMPLES + 1:
				var unit := _unit(box.position + box.size * Vector2(float(i), float(j)) / TILE_SAMPLES)
				samples.append(unit)
				middle += unit
		middle = middle.normalized() if middle.length() > 0.000001 else samples[0]
		var reach := 0.0
		for unit in samples:
			reach = maxf(reach, middle.angle_to(unit))
		reach += samples[0].angle_to(samples[TILE_SAMPLES + 2]) / 2.0
		var shapes: Variant = _triangle_mesh(tile.points, tile.colors) if per_shape == 3 else tile.points
		out.append([shapes, middle, reach])
	return out

## Whether a tile (see _tiled()) can be in view.
func _tile_in_view(tile: Array) -> bool:
	return (tile[1] as Vector3).dot(_art_toward) >= cos(minf(_art_reach + TILE_SLACK + float(tile[2]), PI))

## Whether the art is drawn tile by tile (only those in view): zoomed in far
## enough that most of the globe can't be seen. Zoomed out, the whole meshes
## (far fewer draw calls).
func _tiles_shown() -> bool:
	return _tile_reach < TILE_MAX_REACH and _shared_meshes.has("tiles")

## The art's mesh, or zoomed in, only its tiles in view (see _tiled()).
func _draw_tiled(canvas: CanvasItem, whole: ArrayMesh, tiles: Array, texture: Texture2D, modulate := Color.WHITE) -> void:
	var t_a := Time.get_ticks_usec()
	if not _art_tiled or tiles.is_empty():
		canvas.draw_mesh(whole, texture, Transform2D.IDENTITY, modulate)
	else:
		for tile: Array in tiles:
			if _tile_in_view(tile):
				canvas.draw_mesh(tile[0], texture, Transform2D.IDENTITY, modulate)
	_prof("art.tiled", t_a)

## The same for line segments (the coast, borders and rivers).
func _draw_tiled_lines(canvas: CanvasItem, whole: PackedVector2Array, tiles: Array, color: Color) -> void:
	var t_a := Time.get_ticks_usec()
	if not _art_tiled or tiles.is_empty():
		canvas.draw_multiline(whole, color, -1.0)
	else:
		# Each tile's lines as a mesh made once and kept with it (drawn by the
		# GPU from then on), not thousands of points sent again at every redraw.
		for tile: Array in tiles:
			if _tile_in_view(tile):
				if tile.size() < 4:
					tile.resize(4)
				if tile[3] == null:
					tile[3] = _line_mesh(tile[0])
				canvas.draw_mesh(tile[3], null, Transform2D.IDENTITY, color)
	_prof("art.lines", t_a)

## Line segments (pairs of points) as a mesh of lines (a pixel wide, like draw_multiline()).
static func _line_mesh(segments: PackedVector2Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if segments.size() < 2:
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = segments
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
	return mesh

## The art's tiles (see _shared_meshes), or {} if they weren't made.
func _art_tiles() -> Dictionary:
	return _shared_meshes.get("tiles", {})

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
		if _held_at_canal(ship):
			var crossing := GameData.crossing_ahead(ship.from_port, ship.to_port, ship.traveled_nm)
			if not crossing.is_empty() and crossing.canal.get("type", "") == "convoy":
				return _anchorage_slot_position(ship, crossing)
		var pose := _sea_pose(ship)
		if not pose.is_empty():
			return pose[0]
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
	var pose := _sea_pose(ship)
	if not pose.is_empty():
		return pose[1]
	return _heading_angle(_ship_heading(ship), _ship_world(ship))

## Where a ship at sea on a special footing is drawn and which way it faces,
## [screen point, angle]: on a tow (a tug or the ship it's towing), turning
## about (a recovery boat, icebreaker or tug), or on its curve in or out of
## a harbour; [] for a ship plainly on its lane. Asked for twice a frame
## (where, and which way): worked out once.
func _sea_pose(ship: Ship) -> Array:
	var frame := Engine.get_process_frames()
	if frame != _sea_poses_frame:
		_sea_poses_frame = frame
		_sea_poses.clear()
	var pose: Variant = _sea_poses.get(ship)
	if pose != null:
		return pose
	pose = _towing_pose(ship)
	if pose.is_empty():
		pose = _turning_pose(ship)
	if pose.is_empty():
		pose = _harbour_pose(ship)
	_sea_poses[ship] = pose
	return pose

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
	# (The cheap checks first: most service ships aren't turning, most of the time.)
	if ship.is_icebreaker():
		if ship.ice_phase != "turn_in" and ship.ice_phase != "turn_back":
			return []
	elif ship.job_phase != Ship.JOB_ALIGN or ship.rescuing == null:
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
## dock units, worked out once (and again if the ship's berth or spot changes):
## brought in to its berth by a series of tug manoeuvres (see
## _plan_berth_work()); with no berth free they cast off at the mouth and it
## glides on to its spot at the anchorage to wait. Docked, they go to their
## moorings (see _lying_pose()). {total (s), team, ship: its segments, tugs:
## each tug's segments, finish: each tug's way off when it's done}, or {} if
## there's nothing to work out. Each segment is {kind, t0, t1, ...}: the
## ship's "path" (towed in, along points, as timed), "pivot" (turned about
## `at`, its middle `reach` from it, from one heading to another) and "inch"
## (pushed straight in, a push at a time); a tug's "follow" (pulling, `ahead`
## along the ship's path, `side` out from it, easing to `side_to`, `past` along
## from where it stops), "trail" (made fast astern: see _trail_d()), "drive"
## (ahead or astern the way it faces, from one point to another), "spin"
## (turning on the spot) and "pinned" (its fender on the hull, pushing); and
## "hold" (a pose), for either.
func _tug_work(tug: Ship) -> Dictionary:
	var team := _team_of(tug)
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

## Plans a team of tugs working a ship in at port (dock units; see
## _tug_work()): {total (s of play), team, ship ([segments] of the ship's
## way), tugs ([[segments] each), finish ([where each tug ends up, as poses]
## each)}. Its berth chosen as any ship's is, the tugs bring it in by a
## series of real tug manoeuvres, worked out for its own pier (see
## _plan_berth_work()). With no berth free they cast off at the mouth, where
## their tow ends, and it glides on to its spot at the anchorage, as any ship
## coming in to wait does.
func _plan_tug_work(lead: Ship, team: Array[Ship], ship: Ship, port: String, layout: Dictionary, anchoring: bool) -> Dictionary:
	var look: Rect2 = _model_look(ship.model_id)[7]
	var tug_look: Rect2 = _model_look(lead.model_id)[7]
	var length := look.size.x
	var tug_length := tug_look.size.x
	var tug_width := tug_look.size.y
	var units_per_nm := SHIP_WORLD_ZOOM / 60.0
	var tow_speed := 0.0
	for each in team:
		tow_speed += GameState._tow_speed(each)
	tow_speed = maxf(tow_speed, MIN_HARBOUR_SPEED) * units_per_nm
	var mouth := _screen_to_local(port, _keep_right(port, _entrance_pose(port, false, true)))
	if anchoring:
		var ahead := length / 2.0 + tug_length * (TOW_LINE_TUGS + 0.5)
		var lead_in := [(mouth[0] as Vector2) + Vector2.from_angle(float(mouth[1])) * ahead, mouth[1]]
		var at_mouth := {kind = "path", t0 = 0.0, t1 = 0.0, points = PackedVector2Array([mouth[0], lead_in[0]]), times = PackedFloat32Array([0.0, 0.0]), start = float(mouth[1]), end = float(mouth[1])}
		var cast_off := {total = 0.0, team = team, ship = [at_mouth], tugs = [], finish = []}
		for i in team.size():
			var side := 0.0 if team.size() == 1 else (1.0 if i == 0 else -1.0) * tug_width * TOW_Y_WIDTHS
			cast_off.tugs.append([{kind = "follow", t0 = 0.0, t1 = 0.0, ahead = ahead, side = side, side_to = side, past = 1.0e9, swing = tug_length}])
			cast_off.finish.append([_work_pose(cast_off, cast_off.tugs[i], 0.0)])
		return cast_off
	var tug_speed := maxf(GameState._tow_speed(lead), MIN_HARBOUR_SPEED) * units_per_nm * TUG_MOVE_SHARE
	var inside := _right_side(port, layout.inside, true)
	var work := _plan_berth_work(layout, ship.berth, _berth_pose(layout.berths[ship.berth], ship), look.size, tug_look.size, team.size(), mouth, inside, tow_speed, tug_speed)
	work.team = team
	return work

## Tugs bringing a ship in to its berth (see _plan_berth_work()), in dock
## units: the gap between a pushing tug's bow and the hull; how fast a tug
## manoeuvres (a share of its tow speed) and turns on the spot (s a quarter
## turn: harbour tugs turn on their own length); how long the ship takes to be
## turned round to face its slot (s a quarter turn, for a ship 4 units long);
## how fast it's pushed in (a share of the team's tow speed), in how many
## pushes with how long a pause between; and the pause between one stage and
## the next.
const TUG_FENDER := 0.08
const TUG_MOVE_SHARE := 0.6
const TUG_SPIN_S := 1.1
const TUG_PIVOT_S := 4.0
const TUG_INCH_SHARE := 0.35
const TUG_INCH_PULSES := 3
const TUG_INCH_PAUSE_S := 0.7
const TUG_STAGE_PAUSE_S := 0.5
## How tight (a radius, in its own lengths) a tug steers round.
const TUG_TURN_LENGTHS := 0.7
## How many ways (see _plan_berth_work()) are tried in play for a pier the
## table hasn't got.
const TUG_PLAY_TRIES := 48
## How far (dock units) a tug keeps off the pier tips across the channel when it comes round astern of a ship.
const TUG_ROOM := 0.3
## Where a ship's turned round to face its slot, tried in this order for each
## pier until the turn and everything after it is clear: [how far (ship
## lengths) towards its stern from its middle it turns about, how far (ship
## lengths) towards its pier the turn's middle is from the channel's]; and
## where along the hull (ship lengths from its middle) the tugs push to turn it.
const TUG_PIVOT_SHIFTS := [[0.1, 0.0], [0.07, 0.03], [0.05, 0.05], [0.12, 0.0], [0.05, 0.0], [0.0, 0.05], [0.0, 0.0], [0.15, 0.0], [0.1, 0.05], [0.0, 0.1]]
const TUG_STATIONS := [0.38, 0.3, 0.22, 0.14]
## Towed round a curve on the hip instead (see _berth_plan_try()): [the
## curve's radius, how far towards its pier it starts (ship lengths)].
const TUG_CURVES := [[0.6, 0.0], [0.8, 0.0], [0.6, -0.08], [1.0, 0.0], [0.45, 0.0], [0.8, -0.08], [0.6, 0.08], [1.25, 0.0], [0.45, -0.08], [1.0, -0.08]]
## The manoeuvres chosen for each pier (see _plan_berth_work()), by marina,
## berth, ship and tug sizes and how many tugs: [p, shift, bow station,
## stern station, hip side, how it's turned, how the tugs turn, clashes left
## (0 when it's all clear)]: see _berth_plan_try().
static var _berth_plans := {}

## A team of tugs bringing a ship in to its berth at a marina (dock units:
## the berth's index, the pose it moors at, the ship's and a tug's size, how
## many tugs; the harbour mouth and just inside it on the right-hand side, as
## it comes in; the team's tow speed and a tug's manoeuvring speed, units a
## s), as a work plan (see _tug_work()). Every tug only ever goes the way it
## faces, backs straight, or turns on the spot, and the ship only turns about
## a point or goes straight along its length, so nothing slips sideways:
## 1. Towed in: the lead tug pulls on its line ahead; the other lets go,
##    waits beside the way in while the ship passes, then makes fast astern
##    on a line of its own to steady it. The ship comes to a stop in the
##    channel abreast of its slot.
## 2. To their stations: each lets go its line and goes round to push, the
##    lead on the bow and the other on the stern, from opposite sides: out
##    to the side, along, turned square to the hull and in until its fender's on it.
## 3. Turned: pushing bow and stern opposite ways they turn it about a point
##    near its middle until it faces straight into its slot.
## 4. Pushed in: one tug backs off, comes round astern and puts its bow on the
##    stern; then it pushes the ship straight in, a few lengths at a time,
##    easing off between pushes, until it lies at its berth. The other stands
##    off in the channel.
## 5. Clear: it backs straight out of the slot the way it came, and both come
##    round on the channel's middle facing the way out, for home.
## Which point it turns about and where the tugs push are chosen for its own
## pier (see TUG_PIVOT_SHIFTS, TUG_STATIONS) so the ship and the tugs keep
## clear of the piers, the basin's walls, the breakwater and the ships at the
## other berths (each taken to have the biggest ship it can) all the way
## (_berth_plan_clashes()): worked out once for each.
static func _plan_berth_work(layout: Dictionary, berth_index: int, moored: Array, size: Vector2, tug: Vector2, team_n: int, mouth: Array, inside: Array, tow_speed: float, tug_speed: float, thorough := false) -> Dictionary:
	var key := _berth_key(layout, berth_index, moored, size, tug, team_n)
	var chosen: Array = _berth_plans.get(key, [])
	if chosen.is_empty():
		chosen = _berth_table().get(key, [])
	if not chosen.is_empty():
		var kept := _berth_plan_try(layout, berth_index, moored, size, tug, team_n, mouth, inside, tow_speed, tug_speed, chosen)
		kept.clashes = int(chosen[7])
		return kept
	var obstacles := _berth_obstacles(layout, berth_index)
	var best := {}
	var best_bad := 1 << 30
	var best_params := []
	# Turned about a point first (but not where the ship can't lie along the
	# channel abreast of its slot: its bow at the basin's end), then round a curve.
	var candidates := []
	for shift: Array in TUG_PIVOT_SHIFTS:
		if (moored[0] as Vector2).x - float(shift[0]) * size.x - size.x / 2.0 < -float(layout.depth) + TUG_ROOM:
			continue
		for bow: float in TUG_STATIONS:
			for stern: float in (TUG_STATIONS if team_n > 1 else [0.0]):
				for hip_side: float in [1.0, -1.0]:
					candidates.append([float(shift[0]), float(shift[1]), bow, stern, hip_side, 0, 0])
	for curve: Array in TUG_CURVES:
		for hip_side: float in [1.0, -1.0]:
			candidates.append([float(curve[0]), float(curve[1]), 0.0, 0.0, hip_side, 1, 0])
	# (Tugs turning on the spot first, then all those again steering round.)
	for k in candidates.size():
		var steered: Array = candidates[k].duplicate()
		candidates[k][6] = 1
		steered[6] = 0
		candidates.append(steered)
	# (Thorough, as the check that writes the table does: every way, at many
	# moments. In play, for a pier the table hasn't got: the first few ways, more coarsely.)
	if not thorough:
		candidates = candidates.slice(0, TUG_PLAY_TRIES)
	for params: Array in candidates:
		var plan := _berth_plan_try(layout, berth_index, moored, size, tug, team_n, mouth, inside, tow_speed, tug_speed, params)
		var bad := _berth_plan_clashes(plan, layout, obstacles, size, tug, 200 if thorough else 60, best_bad)
		if bad < best_bad:
			best = plan
			best_bad = bad
			best_params = params
		if bad == 0:
			break
	_berth_plans[key] = best_params + [best_bad]
	best.clashes = best_bad
	return best

## The manoeuvres worked out ahead for every pier of every marina size, ship
## size and team (data/tug_berthing.json, written by the check that tries them
## all: _berth_key() -> as _berth_plans), so none has to be searched for in play.
## A pier's plan's key (see _berth_plans, _berth_table()): the marina, the
## berth, where the ship moors, its size, a tug's and how many, rounded so the
## same pier always gives the same key.
static func _berth_key(layout: Dictionary, berth_index: int, moored: Array, size: Vector2, tug: Vector2, team_n: int) -> String:
	var at: Vector2 = moored[0]
	return "%.2f/%.2f/%d/%d/%.3f,%.3f,%.2f/%.3f,%.3f/%.3f,%.3f/%d" % [float(layout.radius), float(layout.depth), (layout.berths as Array).size(), berth_index,
		at.x, at.y, float(moored[1]), size.x, size.y, tug.x, tug.y, team_n]

static func _berth_table() -> Dictionary:
	if _berth_table_cache == null:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BERTH_TABLE_PATH)) if FileAccess.file_exists(BERTH_TABLE_PATH) else null
		_berth_table_cache = parsed if parsed is Dictionary else {}
	return _berth_table_cache

const BERTH_TABLE_PATH := "res://data/tug_berthing.json"
static var _berth_table_cache: Variant = null

## One way of bringing a ship in (see _plan_berth_work()), params [a, b, the
## bow tug's station (ship lengths ahead of its middle), the stern tug's
## (astern of it), which side of the stern a tug made fast on the hip lies (1
## its pier's side, -1 the other), how it's turned (0 about a point, 1 round a
## curve), how the tugs turn (0 steering round, 1 on the spot)]: turned about a point, a its turning point (ship lengths astern of
## its middle) and b the turn's shift towards its pier (ship lengths); round a
## curve (towed on the hip, for a berth by the basin's end, where there's no
## room for it to lie along the channel abreast of its slot), a the curve's
## radius and b how far towards its pier it starts (ship lengths).
static func _berth_plan_try(layout: Dictionary, berth_index: int, moored: Array, size: Vector2, tug: Vector2, team_n: int, mouth: Array, inside: Array, tow_speed: float, tug_speed: float, params: Array) -> Dictionary:
	var berth: Array = layout.berths[berth_index]
	var s := signf((berth[1] as Vector2).y)
	var length := size.x
	var width := size.y
	var tug_length := tug.x
	var tug_width := tug.y
	var home: Vector2 = moored[0]
	var final_angle := float(moored[1])
	var axis := Vector2.from_angle(final_angle)
	var tips := float(layout.channel) / 2.0
	var round_curve := params.size() > 5 and int(params[5]) == 1
	var steer := params.size() <= 6 or int(params[6]) == 0  # (Tugs steering round, or turning on the spot.)
	var turn := tug.x * TUG_TURN_LENGTHS
	var reach := float(params[0]) * length
	var pivot := Vector2(home.x, s * float(params[1]) * length)
	var start := [pivot + Vector2(-reach, 0.0), PI]  # (Heading in, its middle `reach` ahead of where it turns about.)
	var turned := [pivot + Vector2(0.0, s * reach), final_angle]
	var turn_sign := signf(angle_difference(PI, final_angle))
	var centre := Vector2.ZERO
	if round_curve:
		# Round a quarter circle `reach` across, from heading in along the channel
		# to facing its slot, ending in line with it.
		start = [Vector2(home.x + reach, s * float(params[1]) * length), PI]
		centre = (start[0] as Vector2) + Vector2.from_angle(PI + turn_sign * PI / 2.0) * reach
		turned = [centre - Vector2.from_angle(final_angle + turn_sign * PI / 2.0) * reach, final_angle]
	var stand := width / 2.0 + tug_length / 2.0 + TUG_FENDER  # (A tug pushing square on the hull: its middle off the ship's side.)
	var beside := width / 2.0 + tug_width / 2.0 + TUG_FENDER  # (A tug alongside.)
	var spin := Vector2(tug_length, tug_width).length() / 2.0  # (Its corners turning on the spot.)
	var end_on := spin - tug_length / 2.0 + TUG_FENDER + 0.05  # (How far off a hull it turns square to it.)
	var alongside := tug_length / 2.0 + spin + TUG_ROOM  # (How far astern of where it'll lie alongside it turns to come up parallel.)
	var pause := TUG_STAGE_PAUSE_S
	var push_speed := maxf(tow_speed * TUG_INCH_SHARE, 0.01)
	# With no room astern of it once it's turned (a long ship in a narrow
	# channel: a tug there would be in the slot across the way), the ship's
	# first pushed in by a tug made fast alongside its stern quarter (on the
	# hip), there before it's turned, while there's room along the channel to
	# come up alongside: `need` how far in, till there's room astern.
	var stern_along := (turned[0] as Vector2).dot(axis) - length / 2.0  # (Along the slot's line from the channel's middle.)
	var need := maxf(0.0, -tips + TUG_ROOM + spin - (stern_along - TUG_FENDER - tug_length / 2.0 - end_on))
	need = minf(need, (turned[0] as Vector2).distance_to(home))
	var on_hip := need > 0.01
	var hip_side := float(params[4]) if params.size() > 4 else 1.0
	# (Heading in, the ship's left is -y: a tug on its pier's side, +s, lies at lat -s.)
	var hip := {kind = "pinned", fwd = -length / 2.0 + tug_length / 2.0, lat = -s * hip_side * beside, rel = 0.0}
	var pusher := 1 if team_n > 1 else 0
	# 1. Towed in to a stop in the channel abreast of its slot.
	var ahead := length / 2.0 + tug_length * (TOW_LINE_TUGS + 0.5)
	var lead_in := [(mouth[0] as Vector2) + Vector2.from_angle(float(mouth[1])) * ahead, mouth[1]]
	var path := _pose_path(_loosen([mouth, lead_in, inside, start], false, false), SLOT_PATH_HANDLE)
	var times := _path_times(path, tow_speed, length, length, false, true)
	var stopped := times[-1]
	var ship_segs: Array = [{kind = "path", t0 = 0.0, t1 = stopped, points = path, times = times, start = float(mouth[1]), end = PI}]
	var work := {total = 0.0, team = [], ship = ship_segs, tugs = [], finish = [], clashes = 0}
	var path_length := _path_length(path)
	# The lead eases out to the side (the side it'll push from) and to a stop
	# beside the bow, short of the basin's end. (Out is to the ship's left, -y heading
	# in: s times out is away from the slot.)
	var room_ahead := (start[0] as Vector2).x + float(layout.depth) - tug_length / 2.0 - TUG_ROOM
	var past := minf(room_ahead, ahead)  # (Beside the bow, if there's no room ahead of it.)
	# Where the other waits beside the way in while the ship passes it: inside the breakwater.
	var inside_d := path_length
	var ring := float(layout.radius) - JETTY_WIDTH - spin
	var gone := 0.0
	for k in range(1, path.size()):
		gone += path[k - 1].distance_to(path[k])
		if path[k].length() < ring and path[k].x < (inside[0] as Vector2).x + tug_length:
			inside_d = gone
			break
	var hold := clampf(inside_d + 2.0 * tug_length, ahead, maxf(path_length - length / 2.0 - tug_length * (TOW_LINE_TUGS + 0.5), ahead))
	for i in team_n:
		var side := 0.0 if team_n == 1 else (1.0 if i == 0 else -1.0) * tug_width * TOW_Y_WIDTHS
		var wide := (signf(side) if side != 0.0 else 1.0) * (width / 2.0 + spin + TUG_ROOM)
		if i == 0 and not (round_curve and team_n > 1):
			work.tugs.append([{kind = "follow", t0 = 0.0, t1 = stopped, ahead = ahead, side = side, side_to = s * (width / 2.0 + spin + TUG_ROOM), past = past, swing = tug_length}])
		elif i == 0:
			# Round a curve, the lead's not wanted once it's in: it lets go inside
			# the breakwater and stands by beside the way in, clear, while it passes.
			work.tugs.append([{kind = "trail", t0 = 0.0, t1 = stopped, ahead = ahead, behind = 1.0e9, hold = hold, side = side, wide = wide, swing = tug_length}])
		else:
			var behind := length / 2.0 + tug_length * (TOW_LINE_TUGS + 0.5)
			work.tugs.append([{kind = "trail", t0 = 0.0, t1 = stopped, ahead = ahead, behind = behind, hold = hold, side = side, wide = wide, swing = tug_length}])
	# 2. To their stations: the lead square on the bow, from the side away from
	# the slot (pushing it round towards it); the other square on the stern from
	# the slot's side, or (no room astern) alongside its stern quarter, made
	# fast on the hip. A lone tug: on the bow, or on the hip.
	# Round a curve, the one pushing it in tows it round on the hip and the
	# lead stands by where it let go.
	var pins := []
	var lashed := []  # (Which is made fast on the hip.)
	for i in team_n:
		lashed.append(i == pusher and (on_hip or round_curve))
		if lashed[i]:
			pins.append(hip)
		elif round_curve:
			pins.append({})
		elif i == 0:
			pins.append({kind = "pinned", fwd = float(params[2]) * length, lat = s * stand, rel = -s * PI / 2.0})
		else:
			pins.append({kind = "pinned", fwd = -float(params[3]) * length, lat = -s * stand, rel = s * PI / 2.0})
	var ready := stopped
	var arrive := []
	var waiting := []  # (Where each lies once at its station, or standing by.)
	for i in team_n:
		var segs: Array = work.tugs[i]
		var from := _work_pose(work, segs, stopped)
		if (pins[i] as Dictionary).is_empty():
			arrive.append(stopped)
			waiting.append(from)
			continue
		var station := _pinned_pose(start, pins[i])
		var t := _tug_route(segs, stopped + pause, from, station, tug_speed, alongside if lashed[i] else end_on, steer, turn)
		arrive.append(t)
		waiting.append(station)
		ready = maxf(ready, t)
	# 3. Turned to face its slot (the tug on the hip working with it): about a
	# point by the tugs pushing bow and stern, or towed round its curve on the hip.
	var turn_at := ready + pause
	var pivot_s := TUG_PIVOT_S * clampf(length / 4.0, 0.7, 1.8)
	if round_curve:
		pivot_s = maxf(reach * PI / 2.0 / push_speed * 1.3, pivot_s)
	var turned_at := turn_at + pivot_s
	ship_segs.append({kind = "hold", t0 = stopped, t1 = turn_at, pose = start})
	if round_curve:
		ship_segs.append({kind = "arc", t0 = turn_at, t1 = turned_at, centre = centre, radius = reach, from = PI, to = final_angle, sign = turn_sign})
	else:
		ship_segs.append({kind = "pivot", t0 = turn_at, t1 = turned_at, at = pivot, reach = reach, from = PI, to = final_angle})
	for i in team_n:
		var segs: Array = work.tugs[i]
		segs.append({kind = "hold", t0 = arrive[i], t1 = turn_at, pose = waiting[i]})
		if (pins[i] as Dictionary).is_empty():
			continue
		var pin: Dictionary = pins[i].duplicate()
		pin.t0 = turn_at
		pin.t1 = turned_at
		segs.append(pin)
	# 4. Pushed in: on the hip first if it must be, then from astern, its bow on
	# the stern, a push at a time. The lead (with two) backs off and stands by.
	var astern := {kind = "pinned", fwd = -(length / 2.0 + tug_length / 2.0 + TUG_FENDER), lat = 0.0, rel = 0.0}
	var ship_at := turned  # (Where the ship lies when it's pushed from astern.)
	var hip_from := -1.0
	var hip_to := -1.0
	var push_ready := turned_at
	var clear_t := []
	for i in team_n:
		var segs: Array = work.tugs[i]
		var on_hull: Array = waiting[i] if (pins[i] as Dictionary).is_empty() else _pinned_pose(turned, pins[i])
		var t := turned_at + pause
		segs.append({kind = "hold", t0 = turned_at, t1 = t, pose = on_hull})
		var from := on_hull
		if i == pusher and on_hip:
			hip_from = t
			hip_to = hip_from + need / push_speed * 1.5
			var made_fast: Dictionary = hip.duplicate()
			made_fast.t0 = hip_from
			made_fast.t1 = hip_to
			segs.append(made_fast)
			ship_at = [(turned[0] as Vector2) + axis * need, final_angle]
			from = _pinned_pose(ship_at, hip)
			t = hip_to + pause
			segs.append({kind = "hold", t0 = hip_to, t1 = t, pose = from})
		elif not lashed[i] and not (pins[i] as Dictionary).is_empty():
			# Backs straight off the hull, square to it.
			var off := [(on_hull[0] as Vector2) - Vector2.from_angle(float(on_hull[1])) * (end_on + 0.1), on_hull[1]]
			var back_s := (end_on + 0.1) / tug_speed + 0.4
			segs.append({kind = "drive", t0 = t, t1 = t + back_s, from = on_hull[0], to = off[0], angle = float(on_hull[1])})
			t += back_s
			from = off
		if i == pusher:
			t = _tug_route(segs, t, from, _pinned_pose(ship_at, astern), tug_speed, end_on, steer, turn)
			push_ready = t
		clear_t.append(t)
	var push_at := push_ready + pause
	var distance := (ship_at[0] as Vector2).distance_to(home)
	var pulses := TUG_INCH_PULSES if distance > length * 0.3 else 1
	var push_s := distance / push_speed * 1.5 + TUG_INCH_PAUSE_S * (pulses - 1)
	if on_hip:
		ship_segs.append({kind = "hold", t0 = turned_at, t1 = hip_from, pose = turned})
		ship_segs.append({kind = "inch", t0 = hip_from, t1 = hip_to, from = turned[0], to = ship_at[0], angle = final_angle, pulses = 1, pause = 0.0})
		ship_segs.append({kind = "hold", t0 = hip_to, t1 = push_at, pose = ship_at})
	else:
		ship_segs.append({kind = "hold", t0 = turned_at, t1 = push_at, pose = turned})
	ship_segs.append({kind = "inch", t0 = push_at, t1 = push_at + push_s, from = ship_at[0], to = home, angle = final_angle, pulses = pulses, pause = TUG_INCH_PAUSE_S})
	var pushed := push_at + push_s
	var pusher_segs: Array = work.tugs[pusher]
	pusher_segs.append({kind = "hold", t0 = push_ready, t1 = push_at, pose = _pinned_pose(ship_at, astern)})
	var pushing: Dictionary = astern.duplicate()
	pushing.t0 = push_at
	pushing.t1 = pushed
	pusher_segs.append(pushing)
	# 5. Clear: the pusher backs straight out of the slot to just past the
	# channel's middle and steers round there for the way out; the lead stays
	# where it stood by (both then go home: see _lying_pose()).
	var ends := []
	for i in team_n:
		var segs: Array = work.tugs[i]
		var t := pushed + pause if i == pusher else maxf(float(clear_t[i]), pushed)
		var from := _pinned_pose([home, final_angle], astern) if i == pusher else _work_pose(work, segs, float(clear_t[i]))
		if i == pusher:
			segs.append({kind = "hold", t0 = pushed, t1 = t, pose = from})
			var backed := Vector2(home.x, -s * turn / 2.0)
			var out_s := (from[0] as Vector2).distance_to(backed) / tug_speed + 0.4
			segs.append({kind = "drive", t0 = t, t1 = t + out_s, from = from[0], to = backed, angle = float(from[1])})
			t += out_s
			var round_out := _pose_path([[backed, float(from[1])], [Vector2(home.x + turn, 0.0), 0.0]], 0.4)
			var round_s := _path_length(round_out) / tug_speed + 0.6
			segs.append({kind = "course", t0 = t, t1 = t + round_s, points = round_out, start = float(from[1]), end = 0.0})
			t += round_s
		else:
			if t > float(clear_t[i]):
				segs.append({kind = "hold", t0 = clear_t[i], t1 = t, pose = from})
		ends.append(t)
	var total := pushed
	for t: float in ends:
		total = maxf(total, t)
	total += 0.2
	ship_segs.append({kind = "hold", t0 = pushed, t1 = total, pose = [home, final_angle]})
	work.total = total
	for i in team_n:
		var segs: Array = work.tugs[i]
		var last := _work_pose(work, segs, float(segs[-1].t1))
		segs.append({kind = "hold", t0 = float(segs[-1].t1), t1 = total, pose = last})
		work.finish.append([last, [Vector2((last[0] as Vector2).x + tug_length * 1.5, (last[0] as Vector2).y), 0.0]])
	return work

## A tug's pose pushing on a ship (a "pinned" segment: `fwd` along the ship
## from its middle, `lat` out to its left, facing `rel` off its heading) when
## the ship's at a pose.
static func _pinned_pose(ship: Array, pin: Dictionary) -> Array:
	var angle := float(ship[1])
	var at: Vector2 = (ship[0] as Vector2) + Vector2.from_angle(angle) * float(pin.fwd) + Vector2.from_angle(angle + PI / 2.0) * float(pin.lat)
	return [at, angle + float(pin.rel)]

## A tug's way from a pose to its station (a pose, its bow on a hull or where
## it's to lie), appended to its segments from time t: out to the side to the
## line its station's on, along that line to `room` short of it, round square
## to the hull there and in until it's on it. Steering (`steer`): a course
## through those turns on its turning circle (`turn` across), the way a boat
## comes round, heading the way it goes all along; else each leg in turn,
## turned on the spot first (harbour tugs can) and going the way it faces, or
## backing when its way's just astern and short. The time it gets there.
static func _tug_route(segs: Array, t: float, from: Array, to: Array, speed: float, room: float, steer := true, turn := 1.6) -> float:
	var goal: Vector2 = to[0]
	var facing := float(to[1])
	var short := goal - Vector2.from_angle(facing) * room
	var at: Vector2 = from[0]
	var angle := float(from[1])
	# Out to the side first (onto the line through `short` square to the station's facing), then along it.
	var across := Vector2.from_angle(facing)
	var offset := (short - at).dot(across)
	var waypoints := []
	if absf(offset) > 0.05:
		waypoints.append(at + across * offset)
	waypoints.append(short)
	if steer:
		var poses := [from]
		for point: Vector2 in waypoints:
			var last: Vector2 = poses[-1][0]
			if last.distance_to(point) > 0.3:
				poses.append([point, facing if point == short else (short - point).angle()])
		if poses.size() > 1:
			poses[-1] = [poses[-1][0], facing]
			var path := _pose_path(_loosen(poses, true, false, turn / 2.0), 0.4)
			var span := _path_length(path) / speed + 0.6
			segs.append({kind = "course", t0 = t, t1 = t + span, points = path, start = angle, end = facing})
			t += span
			at = poses[-1][0]
			angle = facing
	else:
		for point: Vector2 in waypoints:
			if at.distance_to(point) < 0.02:
				continue
			var way := (point - at).angle()
			var backing := absf(angle_difference(angle, way)) > PI * 0.6 and at.distance_to(point) < 3.0
			var heading := way + PI if backing else way
			t = _tug_spin(segs, t, at, angle, heading)
			angle = heading
			var span := at.distance_to(point) / speed + 0.4
			segs.append({kind = "drive", t0 = t, t1 = t + span, from = at, to = point, angle = angle})
			t += span
			at = point
	t = _tug_spin(segs, t, at, angle, facing)
	if room > 0.0:
		var span := at.distance_to(goal) / speed + 0.3
		segs.append({kind = "drive", t0 = t, t1 = t + span, from = at, to = goal, angle = facing})
		t += span
	return t

## Turning a tug on the spot from one heading to another (the shorter way),
## appended from time t: the time it's done.
static func _tug_spin(segs: Array, t: float, at: Vector2, from: float, to: float) -> float:
	var turn := angle_difference(from, to)
	if absf(turn) < 0.02:
		return t
	var span := maxf(TUG_SPIN_S * absf(turn) / (PI / 2.0), 0.3)
	segs.append({kind = "spin", t0 = t, t1 = t + span, at = at, from = from, turn = turn})
	return t + span

## What a berth's ship and tugs must keep clear of coming in (dock units): the
## piers (out from their walls to their tips at the channel's edge), the basin's
## walls, and the ship at each other berth (the biggest it takes).
static func _berth_obstacles(layout: Dictionary, berth_index: int) -> Array:
	var half := float(layout.inner)
	var depth := float(layout.depth)
	var tips := float(layout.channel) / 2.0
	var out := []
	for pier: Array in layout.piers:
		var x0 := minf(float(pier[1]), float(pier[2]))
		var x1 := maxf(float(pier[1]), float(pier[2]))
		out.append(Rect2(x0, tips, x1 - x0, half + 2.0 - tips) if float(pier[0]) > 0.0 else Rect2(x0, -half - 2.0, x1 - x0, half + 2.0 - tips))
	out.append(Rect2(-depth - 4.0, half, depth + 4.0, 4.0))
	out.append(Rect2(-depth - 4.0, -half - 4.0, depth + 4.0, 4.0))
	out.append(Rect2(-depth - 4.0, -half - 4.0, 4.0, 2.0 * half + 8.0))
	var berths: Array = layout.berths
	var size := Vector2(float(layout.width), float(layout.length))
	for j in berths.size():
		if j == berth_index:
			continue
		var middle := Vector2(float(berths[j][6]), (berths[j][0] as Vector2).y)
		out.append(Rect2(middle - size / 2.0, size))
	return out

## How many times (at `samples` moments through the work, from the start of
## the tow) the ship or a tug runs into something (see _berth_obstacles(); or
## the breakwater, but for its entrance), a tug into the ship (bar its
## fender) or the other tug, or a tug slips sideways (moving across the way
## it faces, but for pushing round a ship that's turning): 0 when all's clear.
## Stops counting at `cap`.
static func _berth_plan_clashes(work: Dictionary, layout: Dictionary, obstacles: Array, size: Vector2, tug: Vector2, samples: int, cap: int) -> int:
	var total := float(work.total)
	var bad := 0
	var last := []
	for k in samples + 1:
		var t := total * float(k) / samples
		var ship := _work_pose(work, work.ship, t)
		var ship_box := _box_corners(ship[0], float(ship[1]), size / 2.0 - Vector2(0.02, 0.02))
		bad += _box_clashes(ship_box, obstacles, layout)
		var boxes := []
		var poses := []
		for i in (work.tugs as Array).size():
			var segs: Array = work.tugs[i]
			var pose := _work_pose(work, segs, t)
			poses.append(pose)
			var box := _box_corners(pose[0], float(pose[1]), tug / 2.0)
			bad += _box_clashes(box, obstacles, layout)
			if _boxes_meet(box, ship_box):
				bad += 1
			for other: PackedVector2Array in boxes:
				if _boxes_meet(box, other):
					bad += 1
			boxes.append(box)
			if not last.is_empty():
				var moved: Vector2 = (pose[0] as Vector2) - (last[i][0] as Vector2)
				var seg := _work_segment(segs, t)
				var was_seg := _work_segment(segs, total * float(k - 1) / samples)
				if moved.length() > 0.02 and str(seg.kind) != "pinned" and str(was_seg.kind) != "pinned":
					# (Across its heading halfway, as a course round a curve goes along its chord.)
					var slip := absf(moved.dot(Vector2.from_angle(lerp_angle(float(last[i][1]), float(pose[1]), 0.5) + PI / 2.0)))
					if slip > moved.length() * 0.25:
						bad += 1
				if moved.length() > maxf(1.0, total / samples * 12.0) or absf(angle_difference(float(last[i][1]), float(pose[1]))) > maxf(0.6, total / samples * 3.0):
					bad += 1  # (A jump, or swinging round faster than a boat turns.)
		last = poses
		if bad >= cap:
			return bad
	return bad

## A box's corners (dock units): its middle, which way it faces, half its length and width.
static func _box_corners(middle: Vector2, angle: float, half: Vector2) -> PackedVector2Array:
	var along := Vector2.from_angle(angle) * half.x
	var across := Vector2.from_angle(angle + PI / 2.0) * half.y
	return PackedVector2Array([middle + along + across, middle + along - across, middle - along - across, middle - along + across])

## How many of a marina's obstacles (Rect2s) a box runs into, and 1 more if it
## crosses the breakwater (its arms round the sea side, but for the entrance).
static func _box_clashes(box: PackedVector2Array, obstacles: Array, layout: Dictionary) -> int:
	var count := 0
	for rect: Rect2 in obstacles:
		if _boxes_meet(box, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])):
			count += 1
	var ring := float(layout.radius)
	for k in 4:
		for share: float in [0.0, 0.5]:
			var p := box[k].lerp(box[(k + 1) % 4], share)
			var r := p.length()
			if p.x > 0.0 and r > ring - JETTY_WIDTH and r < ring + 0.1 and absf(p.angle()) > float(layout.gap):
				return count + 1
	return count

## True if two convex quads (corners in order) overlap (separating axes).
static func _boxes_meet(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	for shape: PackedVector2Array in [a, b]:
		for k in 4:
			var edge := shape[(k + 1) % 4] - shape[k]
			var axis := Vector2(-edge.y, edge.x)
			var a_min := INF
			var a_max := -INF
			var b_min := INF
			var b_max := -INF
			for p: Vector2 in a:
				var d := p.dot(axis)
				a_min = minf(a_min, d)
				a_max = maxf(a_max, d)
			for p: Vector2 in b:
				var d := p.dot(axis)
				b_min = minf(b_min, d)
				b_max = maxf(b_max, d)
			if a_max <= b_min or b_max <= a_min:
				return false
	return true

## A tug's point pulling a ship in (see "follow" in _work_pose()), `d` along
## the ship's way in (a path of `length`, straight on past its end), out to its
## side as far as it's peeling off by then.
static func _follow_point(points: PackedVector2Array, length: float, pulled: Dictionary, segment: Dictionary, d: float) -> Vector2:
	var pose := _tow_path_pose(points, length, pulled, d)
	var cap := length + float(segment.past)
	var begin := maxf(cap - float(segment.swing) * 3.0, float(segment.ahead))
	var peel := smoothstep(begin, maxf(cap - float(segment.swing) * 0.5, begin + float(segment.swing)), d)
	var side := lerpf(float(segment.side), float(segment.side_to), peel)
	return (pose[0] as Vector2) + Vector2.from_angle(float(pose[1]) + PI / 2.0) * side

## A point `d` along the ship's way in (a path of `length`), straight on past
## either end: [point, angle].
static func _tow_path_pose(points: PackedVector2Array, length: float, pulled: Dictionary, d: float) -> Array:
	if d >= 0.0 and d <= length and length > 0.0:
		return _along_path(points, d / length, float(pulled.start), float(pulled.end))
	var end := _along_path(points, 1.0 if d > 0.0 else 0.0, float(pulled.start), float(pulled.end))
	var past := d - length if d > 0.0 else d
	return [(end[0] as Vector2) + Vector2.from_angle(float(end[1])) * past, end[1]]

## How far along the way in the tug astern is (see "trail" in _work_pose())
## when the ship's `gone` along it: ahead of it to start with (its line to the
## bow, beside the lead), to where it waits beside the way (`hold`) while the
## ship passes, then `behind` it on its line astern. Never going back.
static func _trail_d(segment: Dictionary, gone: float) -> float:
	var lead := gone + float(segment.ahead)
	if lead < float(segment.hold):
		return lead
	return maxf(gone - float(segment.behind), float(segment.hold))

## The tug astern's point `d` along the way in (see _trail_d()): out to the
## side as it comes up to where it waits, back in behind the ship after.
static func _trail_point(points: PackedVector2Array, length: float, pulled: Dictionary, segment: Dictionary, d: float) -> Vector2:
	var pose := _tow_path_pose(points, length, pulled, d)
	var hold := float(segment.hold)
	var swing := float(segment.swing)
	var side: float
	if d <= hold:
		side = lerpf(float(segment.side), float(segment.wide), smoothstep(hold - 2.0 * swing, hold, d))
	else:
		side = lerpf(float(segment.wide), 0.0, smoothstep(hold, hold + 2.0 * swing, d))
	return (pose[0] as Vector2) + Vector2.from_angle(float(pose[1]) + PI / 2.0) * side

## The segment of a tug's (or the ship's) work going on at a time (the last
## once it's all done).
static func _work_segment(segments: Array, t: float) -> Dictionary:
	for segment: Dictionary in segments:
		if t < float(segment.t1):
			return segment
	return segments[-1]

## Which line a tug has on its ship at a time in its work: "bow" (pulling
## ahead, from its stern to the ship's bow), "stern" (astern of it, from its
## bow to the ship's stern) or "" (none).
static func _work_line(work: Dictionary, segments: Array, t: float) -> String:
	var segment := _work_segment(segments, t)
	match str(segment.kind):
		"follow":
			return "bow"
		"trail":
			var pulled: Dictionary = work.ship[0]
			var points: PackedVector2Array = pulled.points
			var ship_u := clampf((t - float(pulled.t0)) / maxf(float(pulled.t1) - float(pulled.t0), 0.001), 0.0, 1.0)
			var d := _trail_d(segment, _timed_share(points, pulled.times, ship_u) * _path_length(points))
			if d < float(segment.hold) - float(segment.swing):
				return "bow"
			if d > float(segment.hold) + float(segment.swing) * 0.5:
				return "stern"
	return ""

## Where the ship or a tug (its segments) is at a time in its team's work,
## in dock units: [point, angle].
static func _work_pose(work: Dictionary, segments: Array, t: float) -> Array:
	var segment := _work_segment(segments, t)
	var span := float(segment.t1) - float(segment.t0)
	var u := clampf((t - float(segment.t0)) / span, 0.0, 1.0) if span > 0.0 else 1.0
	match str(segment.kind):
		"path":
			var points: PackedVector2Array = segment.points
			return _along_path(points, _timed_share(points, segment.times, u), float(segment.start), float(segment.end))
		"hold":
			return segment.pose
		"pivot":
			# Turned about a point near its middle by its tugs.
			var angle := lerp_angle(float(segment.from), float(segment.to), smoothstep(0.0, 1.0, u))
			return [(segment.at as Vector2) + Vector2.from_angle(angle) * float(segment.reach), angle]
		"arc":
			# Towed round a quarter circle on the hip, its heading along it.
			var angle := lerp_angle(float(segment.from), float(segment.to), smoothstep(0.0, 1.0, u))
			return [(segment.centre as Vector2) - Vector2.from_angle(angle + float(segment.sign) * PI / 2.0) * float(segment.radius), angle]
		"inch":
			# Pushed straight in, a push at a time, easing off between.
			var pulses := int(segment.pulses)
			var pause := float(segment.pause)
			var each := maxf((span - pause * (pulses - 1)) / pulses, 0.001)
			var into := clampf(t - float(segment.t0), 0.0, span)
			var k := mini(int(into / (each + pause)), pulses - 1)
			var within := clampf((into - k * (each + pause)) / each, 0.0, 1.0)
			var share := (float(k) + smoothstep(0.0, 1.0, within)) / pulses
			return [(segment.from as Vector2).lerp(segment.to, share), float(segment.angle)]
		"course":
			# Steering round a course, heading the way it goes.
			var points: PackedVector2Array = segment.points
			return _along_path(points, smoothstep(0.0, 1.0, u), float(segment.start), float(segment.end))
		"drive":
			# Ahead or astern, the way it faces, getting going and easing to a stop.
			return [(segment.from as Vector2).lerp(segment.to, smoothstep(0.0, 1.0, u)), float(segment.angle)]
		"spin":
			return [segment.at, float(segment.from) + float(segment.turn) * smoothstep(0.0, 1.0, u)]
		"pinned":
			# Its fender on the hull, pushing: going with the ship.
			return _pinned_pose(_work_pose(work, work.ship, t), segment)
		"follow":
			# On its line ahead of the ship, along the way the ship's being pulled
			# (and straight on past its end); as it comes up to where it's going,
			# easing to a stop (`past` along from where the ship stops, `side_to`
			# out), so the ship comes to a stop behind it. It faces the way its own
			# track goes, so it swerves out the way a boat does.
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
		"trail":
			# The tug astern (see _trail_d()), facing the way its track goes.
			var pulled: Dictionary = work.ship[0]
			var points: PackedVector2Array = pulled.points
			var length := _path_length(points)
			var ship_u := clampf((t - float(pulled.t0)) / maxf(float(pulled.t1) - float(pulled.t0), 0.001), 0.0, 1.0)
			var d := _trail_d(segment, _timed_share(points, pulled.times, ship_u) * length)
			var at := _trail_point(points, length, pulled, segment, d)
			var next := _trail_point(points, length, pulled, segment, d + 0.05)
			return [at, (next - at).angle()]
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

## A tug's team on its job (Ship.tug_team(): the lead first), as of this frame:
## asked for a few times a frame for each tug, and each ask a loop over the fleet.
func _team_of(tug: Ship) -> Array[Ship]:
	var frame := Engine.get_process_frames()
	if frame != _teams_frame:
		_teams_frame = frame
		_teams.clear()
	var team: Variant = _teams.get(tug)
	if team == null:
		team = tug.tug_team()
		_teams[tug] = team
	return team

## Each tug's team this frame (see _team_of()).
var _teams := {}
var _teams_frame := -1

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
	var team := _team_of(tug)
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
	followed = null
	followed_bird = -1
	_look_at(GameData.port_position(port_id))
	_changed()

## Brings a ship (its port while docked) into view, keeping the zoom: centered
## across, and raised_px above the middle (to leave room for its popup below).
func focus_ship(ship: Ship, raised_px := 0.0) -> void:
	followed = null
	followed_bird = -1
	_look_at(GameData.port_position(ship.docked_at) if ship.is_docked() else _ship_world(ship))
	_look_at(screen_to_world(size / 2.0 + Vector2(0.0, raised_px)))
	_changed()

## How many frames the overlay has drawn (see is_warm()).
var _frames_drawn := 0

## True once the map is warm: its land sorted into cells, the sea animals'
## paths found, the wildlife and birds made, the fleet's lanes bent, the
## ports' towns laid out, the regions' map ready and a few frames drawn (the
## loading screen waits for this: LoadingScreen.open_game()).
func is_warm() -> bool:
	if _frames_drawn < 3 or _land_cells.is_empty() or _sea_warming or not _lanes_warm or not RegionMap.is_ready():
		return false
	if gray_mode:
		return true
	return _towns_warm and BirdLife.shared().ensure_built()

## The ship the view follows (see follow_ship()), or null.
var followed: Ship = null
## Following a ship, the view zooms to a little past where the birds just
## show (see _draw_bird_pass()): the ship and its gulls, as far out as they show.
const FOLLOW_ZOOM_MARGIN := 1.02

## The zoom (px a degree) at which the view follows a ship.
func follow_zoom() -> float:
	return BIRD_DOT_PX / (BIRD_SMALLEST_SPAN * BIRD_SCALE) * SHIP_WORLD_ZOOM * FOLLOW_ZOOM_MARGIN

## Follows a ship: the view keeps it in the middle as it goes (along its lane,
## into port and alongside), zooming to follow_zoom(). Zooming (the wheel, the
## + and - buttons and keys, pinching) keeps following, about the ship; a
## drag or a click on the map, another ship followed, or this called again
## for the same ship stops it.
func follow_ship(ship: Ship) -> void:
	followed_bird = -1
	if followed == ship:
		followed = null
		return
	followed = ship
	_zoom_goal = clampf(follow_zoom(), _min_zoom(), MAX_ZOOM)
	_zoom_about = size / 2.0
	_track_followed()

## The bird the view follows (a BirdLife bird; see follow_bird()), or -1.
var followed_bird := -1
## Following a bird, the view zooms in this many times follow_zoom(), so it's
## big enough to watch.
const BIRD_FOLLOW_ZOOM := 3.0

## True while the view follows a ship or a bird.
func _following() -> bool:
	return followed != null or followed_bird >= 0

## Follows a bird (a BirdLife bird): the view keeps it in the middle wherever
## it goes, zoomed in to BIRD_FOLLOW_ZOOM times follow_zoom(); stopped as
## following a ship is (see follow_ship()), or by following a ship.
func follow_bird(index: int) -> void:
	followed = null
	if followed_bird == index or index < 0:
		followed_bird = -1
		return
	followed_bird = index
	_zoom_goal = clampf(follow_zoom() * BIRD_FOLLOW_ZOOM, _min_zoom(), MAX_ZOOM)
	_zoom_about = size / 2.0
	_track_followed()

## Keeps the followed ship (or bird) in the middle of the view (every frame).
func _track_followed() -> void:
	if followed == null:
		if followed_bird >= 0:
			var life := BirdLife.shared()
			if not life.ensure_built() or followed_bird >= life.bird_count():
				followed_bird = -1
				return
			var state: Dictionary = life.bird_state(followed_bird, Wildlife.shared().bird_time, float(GameState.calendar_time()))
			_look_at(Geo.project(state.pos))
			_changed()
		return
	if not is_instance_valid(followed) or not GameState.ships.has(followed):
		followed = null
		return
	var world: Vector2
	if followed.is_docked() and not _marina_shown(followed.docked_at):
		world = GameData.port_position(followed.docked_at)
	else:
		var at := ship_screen_position(followed)
		world = _ship_world(followed) if at == HIDDEN or not followed.is_docked() else screen_to_world(at)
	_look_at(world)
	_changed()

## Centers on a port (by default the company's home port), showing
## game_config.json's initial_view_width_deg degrees of the globe across.
func reset_view(center_port := "") -> void:
	followed = null
	followed_bird = -1
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
	_zoom_about = about if about.x >= 0.0 and not _following() else size / 2.0  # (Following: about the ship or bird, in the middle.)
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
					_zoom_about = size / 2.0 if _following() else button.position  # (Following: about the ship or bird.)
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
						followed = null  # (A click anywhere lets the followed ship go.)
						followed_bird = -1
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
			followed = null
			followed_bird = -1
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
	if not choosing_divine.is_empty() and str(Divine.POWERS[choosing_divine].target) == "point":
		divine_target.emit(Geo.unproject(screen_to_world(screen_pos)))
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
		nearest_ship = _ship_on_hull(screen_pos)  # Right on one, the one on top.
		if nearest_ship == null:
			for ship in _ships_topmost_first():
				if _ship_hulls.has(ship):
					continue  # (Picked only on its hull, just above.)
				var dist := ship_screen_position(ship).distance_to(screen_pos)
				if dist <= maxf(SHIP_HIT_RADIUS * _ship_scale(), SHIP_HIT_MIN_PX) and dist < nearest_dist:
					nearest_dist = dist
					nearest_ship = ship
	if not choosing_divine.is_empty():
		match str(Divine.POWERS[choosing_divine].target):
			"ship":
				divine_target.emit(nearest_ship)
			"port":
				divine_target.emit(nearest_port if not nearest_port.is_empty() else marina_port)
		return
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
	elif not _wonder_at(screen_pos).is_empty():
		wonder_clicked.emit(_wonder_at(screen_pos))
	elif not _animals_at(screen_pos).is_empty():
		var group := _animals_at(screen_pos)
		animals_clicked.emit(group[0], group[1])
	elif not _home_at(screen_pos).is_empty():
		var home := _home_at(screen_pos)
		home_clicked.emit(home[0], home[1])
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

## The topmost ship whose hull, as drawn (_ship_hulls: its art's own rect,
## turned and scaled), is under a screen point, or null; one drawn under
## SHIP_HIT_MIN_PX across or long is picked within that.
func _ship_on_hull(screen_pos: Vector2) -> Ship:
	for ship in _ships_topmost_first():
		var hull: Array = _ship_hulls.get(ship, [])
		if hull.is_empty():
			continue
		var scale := float(hull[2])  # (As drawn: see _ship_draw_scale().)
		var rect: Rect2 = _model_look(ship.model_id)[7]
		var grow := (Vector2.ONE * SHIP_HIT_MIN_PX / scale - rect.size).max(Vector2.ZERO) / 2.0
		rect = rect.grow_individual(grow.x, grow.y, grow.x, grow.y)
		if rect.has_point((screen_pos - (hull[0] as Vector2)).rotated(-float(hull[1])) / scale):
			return ship
	return null

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
		var shown := web_zoom >= tier.min_zoom
		if shown and not tier.visible:
			tier.queue_redraw()  # (Its tiles may be from another view: see _tiled().)
		tier.visible = shown

## The view's zoom as a web-map zoom level (0 = whole world in 256 px).
func _web_zoom() -> float:
	return log(_zoom * Geo.WORLD_WIDTH / 256.0) / log(2.0)

func _changed() -> void:
	var t_c := Time.get_ticks_usec()
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
	_lane_material.set_shader_parameter(&"right", _right)
	_lane_material.set_shader_parameter(&"up", _up)
	_lane_material.set_shader_parameter(&"toward", _toward)
	_lane_material.set_shader_parameter(&"radius", _radius())
	_lane_material.set_shader_parameter(&"middle", size / 2.0)
	_lane_material.set_shader_parameter(&"half_px", ACTIVE_LANE_WIDTH / 2.0 + 1.0)
	var pixels := get_viewport().get_final_transform().get_scale().x if is_inside_tree() else 1.0
	_land_mask.size = Vector2i((size * pixels).ceil()).max(Vector2i.ONE)
	_land_mask_art.scale = Vector2.ONE * pixels
	if not gray_mode:
		_land_mask.render_target_update_mode = SubViewport.UPDATE_ONCE  # (Only the view changes it: drawn again only then.)
	_port_turns.clear()
	_near_ports_valid = false
	_port_screens.clear()
	_lanes_in_view.clear()
	_view_epoch += 1
	# Zoomed in, the art's drawn tile by tile (see _tiled()), TILE_SLACK beyond
	# the view: drawn again once the view's moved past that (only queuing its
	# few hundred meshes), and once more on zooming back out to the whole meshes.
	_tile_reach = asin(minf((size.length() / 2.0 + 8.0) / _radius(), 1.0))
	var tiled := _tiles_shown()
	if _art != null and (tiled != _art_tiled or tiled and _art_toward.angle_to(_toward) + _tile_reach - _art_reach > TILE_SLACK):
		_art_tiled = tiled
		_art_toward = _toward
		_art_reach = _tile_reach
		var pieces: Array[Node] = [_art, _land_mask_art]
		while not pieces.is_empty():
			var piece: Node = pieces.pop_back()
			if (piece as CanvasItem).visible:
				(piece as CanvasItem).queue_redraw()  # (A hidden one's drawn when it shows: see _update_rivers().)
			pieces.append_array(piece.get_children())
	_update_rivers()
	if not _ice_circles.is_empty():
		for node in _ice_arts:
			node.queue_redraw()  # So do the cracks and channels.
	queue_redraw()
	_redraw_layers()
	view_changed.emit()
	_prof("changed", t_c)

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
	_wonder_layer.queue_redraw()
	_weather_layer.queue_redraw()
	_canal_layer.queue_redraw()
	_static_layer.queue_redraw()
	_dock_layer.queue_redraw()
	_still_birds.queue_redraw()
	_overlay.queue_redraw()

func _draw_weather_layer() -> void:
	_canvas = _weather_layer
	if show_ships:
		var t0 := Time.get_ticks_usec()
		_draw_sea_life()  # Under the ice and storms: they swim beneath both.
		_prof("weather.sea_life", t0)
		t0 = Time.get_ticks_usec()
		_draw_currents()
		_prof("weather.currents", t0)
		t0 = Time.get_ticks_usec()
		_draw_ice()
		_draw_route_labels()
		_prof("weather.ice_labels", t0)
		t0 = Time.get_ticks_usec()
		_draw_storms()
		_prof("weather.storms", t0)
		t0 = Time.get_ticks_usec()
		_draw_gusts()
		_prof("weather.gusts", t0)


## The ocean currents (Currents) flowing on the map: dashes drifting along
## CURRENT_LINES lines across each current's width, the way the water runs
## (back the other way in the months it turns, as the Somali Current does),
## warm currents red-orange and cold ones blue, brighter the stronger the
## current runs this month. They fade in from a mid zoom and out again close
## in, where the harbours are. Worked out once: each line's points on the unit
## sphere with the miles along it; each frame only the dashes of currents
## whose box is in view.
const CURRENT_LINES: Array[float] = [-0.5, 0.0, 0.5]  # (Shares of the half width, across.)
const CURRENT_STEP_NM := 40.0
const CURRENT_CHUNK := 8  # (Points a stretch, for culling: see _build_current_lines().)
const CURRENT_ALL_LINES := 6.0  # (All a current's lines from this many times the least zoom.)
const CURRENT_DASH_NM := 260.0  # (One dash this far along from the last.)
const CURRENT_DASH_LONG := 0.32  # (A dash's length, a share of that.)
const CURRENT_DRIFT := 9.0  # (nm a second a knot of current: how fast the dashes drift.)
const CURRENT_WARM := Color(1.0, 0.5, 0.28)
const CURRENT_COLD := Color(0.5, 0.78, 1.0)
const CURRENT_ALPHA := 0.55
const CURRENT_ZOOM := Vector4(1.6, 3.2, 90.0, 220.0)  # (Fade in from x to y times the least zoom; out from z to w px a degree.)
var _current_lines := []  # [current index, units (PackedVector3Array), miles, box (lon, lat)] each line

func _draw_currents() -> void:
	if gray_mode:
		return
	var low := _min_zoom()
	var fade := smoothstep(low * CURRENT_ZOOM.x, low * CURRENT_ZOOM.y, _zoom) * (1.0 - smoothstep(CURRENT_ZOOM.z, CURRENT_ZOOM.w, _zoom))
	if fade <= 0.01:
		return
	var currents := Currents.shared()
	if _current_lines.is_empty():
		_build_current_lines(currents)
	var month := GameData.month
	var now := Time.get_ticks_msec() / 1000.0
	var screen := Rect2(Vector2.ZERO, size)
	var globe := _radius()
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var dash := CURRENT_DASH_NM * CURRENT_DASH_LONG
	var middles_only := _zoom < low * CURRENT_ALL_LINES  # (Far out, only each current's middle line: they'd run together.)
	for line: Array in _current_lines:
		if middles_only and float(line[5]) != 0.0:
			continue
		var item: Dictionary = currents.list[line[0]]
		var strength := float(item.strength[month])
		if absf(strength) < 0.05:
			continue
		var units: PackedVector3Array = line[1]
		var miles: PackedFloat64Array = line[2]
		var total := miles[miles.size() - 1]
		var tint: Color = CURRENT_WARM if item.warm else CURRENT_COLD
		var alpha := CURRENT_ALPHA * fade * clampf(absf(strength), 0.35, 1.2)
		var drift := fposmod(now * CURRENT_DRIFT * float(item.speed_kn) * signf(strength) + float(line[0]) * 97.0, CURRENT_DASH_NM)
		var tail_color := Color(tint, alpha * 0.35)
		var head_color := Color(tint, alpha)
		# Stretch by stretch (see _build_current_lines()), only those in view.
		for chunk: Array in line[4]:
			var middle: Vector3 = chunk[2]
			var reach: float = chunk[3]
			if middle.dot(_toward) < -sin(reach):
				continue  # Round the back of the globe.
			if middle.dot(_toward) > 0.0 and not screen.grow(reach * globe + 20.0).has_point(_unit_to_screen(middle)):
				continue  # Off the side of the screen.
			var from_mile: float = miles[chunk[0]]
			var to_mile: float = miles[chunk[1]] if chunk[1] < miles.size() - 1 else total
			# The dashes starting in this stretch (the first stretch takes those starting before the line).
			var s := drift + ceilf((from_mile - drift) / CURRENT_DASH_NM) * CURRENT_DASH_NM
			if chunk[0] == 0:
				s -= CURRENT_DASH_NM
			var k: int = chunk[0]
			while s < to_mile:
				var tail := maxf(s, 0.0)
				var head := minf(s + dash, total)
				s += CURRENT_DASH_NM
				if head <= tail:
					continue
				while k < miles.size() - 2 and miles[k + 1] < tail:
					k += 1
				var a := _current_point(units, miles, k, tail)
				var c := _current_point(units, miles, k, head)
				if a.dot(_toward) <= 0.0 or c.dot(_toward) <= 0.0:
					continue
				var pa := _unit_to_screen(a)
				var pc := _unit_to_screen(c)
				var pb := (pa + pc) / 2.0  # (Short: its middle on screen will do.)
				# Bright at the head the way it flows (its tail, against the flow).
				if strength > 0.0:
					points.append_array(PackedVector2Array([pa, pb, pb, pc]))
				else:
					points.append_array(PackedVector2Array([pc, pb, pb, pa]))
				colors.append(tail_color)  # (One colour a segment.)
				colors.append(head_color)
	if not points.is_empty():
		_canvas.draw_multiline_colors(points, colors, 2.0)

## A point `mile` along a current's line (on the unit sphere), from its point k on.
static func _current_point(units: PackedVector3Array, miles: PackedFloat64Array, k: int, mile: float) -> Vector3:
	var i := k
	while i < miles.size() - 2 and miles[i + 1] < mile:
		i += 1
	var span := maxf(miles[i + 1] - miles[i], 0.001)
	return units[i].lerp(units[i + 1], clampf((mile - miles[i]) / span, 0.0, 1.0))  # (Points CURRENT_STEP_NM apart: straight between is close enough.)

## Each current's lines (see _draw_currents()), worked out once.
func _build_current_lines(currents: Currents) -> void:
	for index in currents.list.size():
		var item := currents.list[index]
		var flow: PackedVector2Array = item.flow
		# Its path every CURRENT_STEP_NM, with the way it runs at each point.
		var path := PackedVector2Array([flow[0]])
		for k in range(1, flow.size()):
			var steps := maxi(ceili(Geo.distance_nm(flow[k - 1], flow[k]) / CURRENT_STEP_NM), 1)
			for s in range(1, steps + 1):
				path.append(flow[k - 1].lerp(flow[k], float(s) / steps))
		var half_deg := float(item.width_km) / KM_PER_DEGREE * 0.8
		for share: float in CURRENT_LINES:
			var units := PackedVector3Array()
			var miles := PackedFloat64Array()
			var box := Rect2()
			var previous := Vector2.INF
			for k in path.size():
				var before := path[maxi(k - 1, 0)]
				var after := path[mini(k + 1, path.size() - 1)]
				var c := cos(deg_to_rad(path[k].y))
				var way := Vector2((after.x - before.x) * c, after.y - before.y).normalized()
				var across := Vector2(-way.y, way.x) * half_deg * share
				var p := path[k] + Vector2(across.x / maxf(c, 0.1), across.y)
				units.append(_unit(Geo.project(Vector2(wrapf(p.x, -180.0, 180.0), p.y))))
				miles.append(0.0 if miles.is_empty() else miles[miles.size() - 1] + Geo.distance_nm(previous, p))
				box = Rect2(p, Vector2.ZERO) if k == 0 else box.expand(p)
				previous = p
			# Its stretches of CURRENT_CHUNK points, each with its middle and how far it reaches (radians), for culling.
			var chunks := []
			for first in range(0, units.size() - 1, CURRENT_CHUNK):
				var last := mini(first + CURRENT_CHUNK, units.size() - 1)
				var middle := Vector3.ZERO
				for i in range(first, last + 1):
					middle += units[i]
				middle = middle.normalized()
				var reach := 0.0
				for i in range(first, last + 1):
					reach = maxf(reach, middle.angle_to(units[i]))
				chunks.append([first, last, middle, reach + 0.01])
			_current_lines.append([index, units, miles, box.grow(1.0), chunks, share])

## Gusts of wind (see Wind): short pale streaks blowing the way the wind does
## there, each drifting along and fading in and out over GUST_CYCLE_S of play,
## one now and then in each GUST_CELL_PX cell of the screen (somewhere new
## each time), more often, longer and brighter the stronger the wind. Gone in
## a calm, crowded in a gale or a storm.
func _draw_gusts() -> void:
	if gray_mode:
		return
	var t := GameState.play_time
	if _gust_painter == null and ClassDB.class_exists(&"GustPainter"):
		_gust_painter = ClassDB.instantiate(&"GustPainter")
	if _gust_painter != null:
		# Natively (GustPainter: the same gusts), the storms' winds asked of Wind where they reach.
		var reaches := []
		for storm: Dictionary in GameState.weather.storms:
			reaches.append([float(storm.lon), float(storm.lat), float(storm.radius_nm)])
		_gust_painter.draw(_canvas.get_canvas_item(), {size = size, right = _right, up = _up, toward = _toward, radius = _radius(),
			play_time = t, noise = Wind._shared_noise(), storms = reaches, storm_wind = _gust_storm_wind, cell_px = GUST_CELL_PX,
			cycle_s = GUST_CYCLE_S, strength = GUST_STRENGTH, length_px = GUST_LENGTH_PX, alpha = GUST_ALPHA})
		return
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

## For the native gusts: what a storm (by its place in the weather's) adds to the wind at a (lon, lat).
func _gust_storm_wind(index: int, lon_lat: Vector2) -> Vector2:
	var storms := GameState.weather.storms
	return Wind.storm_wind(storms[index], lon_lat) if index < storms.size() else Vector2.ZERO

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
	if not price_line.is_empty() and Time.get_ticks_msec() - _price_time >= PRICE_REFRESH_S * 1000.0:
		_price_time = Time.get_ticks_msec()
		_price_rows.clear()  # (Prices drift: their figures worked out again.)
		_price_epoch += 1
	var key := [_center, _zoom, size, GameState.hubs.map(func(hub: Hub) -> String: return hub.port_id), selected_port, _price_epoch, dimmed_ports]
	if key != _labels_key:
		var frame := Engine.get_process_frames()
		# Dragging or zooming (only the view changed), the labels placed a few
		# frames ago stay, each moved with its anchor: placing them afresh
		# every frame is a loop over every port near the view.
		if not _labels_key.is_empty() and key.slice(2) == _labels_key.slice(2) and frame - _labels_placed_frame < LABEL_REPLACE_FRAMES:
			_labels_key = key
			_shift_labels()
		else:
			_labels_key = key
			_labels_placed_frame = frame
			var placed_labels: Array[Rect2] = []
			var tp := Time.get_ticks_usec()
			var boxed := _place_price_boxes(placed_labels)
			_price_boxes = boxed[0]
			_prof("place.prices", tp)
			tp = Time.get_ticks_usec()
			_port_labels = _place_port_labels(placed_labels, boxed[1])
			_prof("place.ports", tp)
			tp = Time.get_ticks_usec()
			_country_labels = _place_country_labels(placed_labels)
			_prof("place.countries", tp)
			tp = Time.get_ticks_usec()
			_feature_labels = [] if gray_mode else _place_feature_labels(placed_labels)
			_prof("place.features", tp)
	var t0 := Time.get_ticks_usec()
	_draw_feature_labels()
	_draw_country_labels()
	_prof("static.labels", t0)
	t0 = Time.get_ticks_usec()
	if show_ships and show_active_lanes:
		_draw_active_lanes()
	else:
		_lane_mesh_node.visible = false
	_prof("static.lanes", t0)
	t0 = Time.get_ticks_usec()
	_draw_route()
	_draw_ports(_port_labels)
	_prof("static.ports", t0)
	t0 = Time.get_ticks_usec()
	_draw_price_boxes()
	_prof("static.prices", t0)
	_label_layer.queue_redraw()  # (The labels from the atlas, over all that: see _draw_label_layer().)

## The labels placed last (see _draw_static_layer()) moved with their anchors
## (a port's under its dot, a country's or feature's on its spot) as the view
## moves: the same ones, till they're placed afresh.
func _shift_labels() -> void:
	var font := get_theme_default_font()
	for label: Array in _port_labels:
		label[1] = _port_label_rect(font, GameData.get_port(label[0]))
	for label: Array in _country_labels:
		var rect: Rect2 = label[1]
		label[1] = Rect2(_unit_to_screen(_country_units[label[2]]) - rect.size / 2.0, rect.size)
	for label: Array in _feature_labels:
		var rect: Rect2 = label[1]
		label[1] = Rect2(_unit_to_screen(_feature_units[label[0]]) + (label[2] as Vector2), rect.size)
	for box: Array in _price_boxes:
		var rect: Rect2 = box[1]
		box[1] = Rect2(port_screen_position(box[0]) + (box[3] as Vector2), rect.size)

## The font ports are named in on the map: the headings' (Cinzel, see ui/theme.tres).
func _port_font() -> Font:
	return get_theme_font(&"font", &"HeaderLabel")

## Every name the map can label (the ports', the countries', the features')
## into the atlas, once: rendered at the first frame (see LabelAtlas.render()).
func _preload_label_atlas() -> void:
	var font := get_theme_default_font()
	for port: Dictionary in GameData.ports:
		_label_atlas.add(_port_font(), PORT_FONT_SIZE, 0, GameData.port_name(port.id))
	var data := GameData.world_map
	for text: String in data.label_names:
		_label_atlas.add(font, COUNTRY_FONT_SIZE, 0, text)
	for i in data.feature_label_names.size():
		var kind := data.feature_label_kinds[i]
		var style: Array = FEATURE_STYLES[kind]
		if OUTLINED_FEATURES.has(kind):
			_label_atlas.add(_feature_font(kind), style[0], SEA_LABEL_OUTLINE, _feature_text(i))
		_label_atlas.add(_feature_font(kind), style[0], 0, _feature_text(i))

## Whether a label's in the atlas (drawn from it by _draw_label_layer(), not
## glyph by glyph where it's placed).
func _label_in_atlas(font: Font, font_size: int, text: String) -> bool:
	return _label_atlas != null and _label_atlas.cell(font, font_size, 0, text).size != Vector2.ZERO

## The labels placed this view (see _draw_static_layer()) as quads from the
## atlas, all in one batch: a sea name's outline under it, a drop shadow under
## a port's name. Rounded to the window's pixels, so each is as sharp as drawn
## directly. (Any not in the atlas was drawn with the static layer.)
func _draw_label_layer() -> void:
	if _label_atlas == null:
		return
	var t_l := Time.get_ticks_usec()
	var pixels := get_viewport().get_final_transform().get_scale().x
	_label_batch.clear()
	var bounds := Rect2(Vector2.ZERO, size)
	var data := GameData.world_map
	var outline_color := _color(&"sea_label_outline")
	for label: Array in _feature_labels:
		var rect: Rect2 = label[1]
		if not bounds.intersects(rect):
			continue
		var kind := data.feature_label_kinds[label[0]]
		var style: Array = FEATURE_STYLES[kind]
		var font := _feature_font(kind)
		var text := _feature_text(label[0])
		if OUTLINED_FEATURES.has(kind):
			_label_quad(font, style[0], SEA_LABEL_OUTLINE, text, rect.position, outline_color, pixels)
		_label_quad(font, style[0], 0, text, rect.position, _color(style[1]), pixels)
	var font := get_theme_default_font()
	var country := _color(&"country_label")
	for label: Array in _country_labels:
		var rect: Rect2 = label[1]
		if bounds.intersects(rect):
			_label_quad(font, COUNTRY_FONT_SIZE, 0, label[0], rect.position, country, pixels)
	var shadow := _color(&"label_shadow")
	var label_color := _color(&"label")
	var dimmed := _color(&"port_dimmed")
	var port_font := _port_font()
	for label: Array in _port_labels:
		var rect: Rect2 = label[1]
		if not bounds.intersects(rect):
			continue
		var text: String = GameData.port_name(label[0])
		var color := dimmed if dimmed_ports.has(label[0]) or _port_locked(label[0]) else label_color  # (Locked regions' ports named, but dimmed.)
		if _label_quad(port_font, PORT_FONT_SIZE, 0, text, rect.position + Vector2(1, 1), shadow, pixels):
			_label_quad(port_font, PORT_FONT_SIZE, 0, text, rect.position, color, pixels)
	_label_batch.flush(_label_layer, _label_atlas.get_texture())
	_prof("labels.layer", t_l)

## A label's quad from the atlas at `at` (its text's top left), or false if it isn't in.
func _label_quad(font: Font, font_size: int, outline: int, text: String, at: Vector2, color: Color, pixels: float) -> bool:
	var cell := _label_atlas.cell(font, font_size, outline, text)
	if cell.size == Vector2.ZERO:
		return false
	var pos := ((at - Vector2.ONE * (LabelAtlas.PAD + outline)) * pixels).round() / pixels
	_label_batch.textured_region(Rect2(pos, cell.size), color, _label_atlas.uv(cell))
	return true

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
## Each port is a marina (see Docks), grown out of its circle on the map: a
## rectangular basin dug into the land behind the coast, facing the sea
## (_port_sea_angle()), with piers reaching in from its two side walls like a
## rib cage, each as long as the longest ship that can dock there, and a
## channel between their tips from the entrance to the land end; the slot
## between one pier and the next is wide enough for two ships side by side,
## each coming straight in, bow to the wall, one along each pier (the top
## slot each side, open to the outer harbour, takes one): 6, 8, 10 or 14
## berths by the port's band (14 at any company's HQ or hub). Ships lying
## long term (idle, paused) moor at the port's pontoons (see the Towns note
## and _lay_moorings()), not at the piers. Behind the
## basin is a stone quay for the HQ building and the industry plots. Round
## the sea side is a jetty, a breakwater with the entrance in the middle (red
## and green lights on its ends). Tugs moor along the first piers; ships
## waiting for a berth and other service ships lie at the port's anchorage
## (data/anchorages.json; see _anchor_spots()), each at its own anchor, swung
## round to face into the wind.
## and sized like the ships, in the world (_ship_scale()); +x is out to sea.
## Ships in harbour sail at their own speed, as at sea (see _sailed_share()),
## but at least this (nm/s), so one at a standstill still gets in.
const MIN_HARBOUR_SPEED := 0.5
## A port's marina is drawn (and its dot not) once its radius on screen is this
## many px more than the dot's.
const MARINA_OVER_DOT_PX := 2.0
## No marina reaches further than this from its port (dock units, its quay, its
## town and all); kept drawn while its port is within this of the screen
## (generous, so a neighbour just off screen stays as the view zooms and drifts).
const MARINA_MAX_REACH := 150.0
## Nor does a port's furthest anchor point (dock units: data/anchorages.json's
## 420 nm, plus the ship), for culling.
const PORT_MAX_REACH := 300.0
## How far (nm) past its swing a ship dropping anchor keeps off a drawn lane
## and the ways in and out of its harbour (see _anchors_in_lanes()): room for
## a passing ship's own beam, and some to spare.
const ANCHOR_LANE_MARGIN_NM := 3.0
## How far out (nm) from its port a ship's way between the harbour mouth and
## a lane can reach (HARBOUR_REACH times the biggest marina's mouth's distance,
## and the curve's own bulge): for finding the ports whose ways reach an
## anchorage (see _anchors_in_lanes()).
const HARBOUR_CORRIDOR_NM := 90.0
## A ship near a port curves between its lane and its harbour over at least
## this many times the harbour's distance from the port in lane (see
## _harbour_pose()).
const HARBOUR_REACH := 3.0
const HARBOUR_APPROACH_OUT := 2.2  # The approach pose, in line with the mouth, this many mouths out (see _lane_curve()).
## The shortest stretch of lane (nm) a ship curves in or out of port over.
const HARBOUR_MIN_NM := 2.0
## How many times its reach a curve's stretch of lane may grow to match a
## longer curve (see _lane_reaches()).
const HARBOUR_REACH_GROW := 1.5
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
const BERTH_GAP := 0.7
const BERTH_ROOM := 0.6
## The piers (dock units wide), the channel between the pier tips (ship
## lengths, at least this many ship widths), and the quay behind the basin
## (ship lengths, at least QUAY_STRIP_MIN) for the HQ and industry.
## The rocks round a marina (see _marina_layout()), each [how far out (jetty
## radii), which way (degrees off the sea way), how big (jetty radii)]; the
## first ROCK_SPOTS entries a port has (3 to 5 by its berths).
const ROCK_SPOTS := [[1.18, 60.0, 0.12], [1.22, -66.0, 0.1], [1.32, 72.0, 0.09], [1.17, -46.0, 0.13], [1.3, -58.0, 0.11]]
const PIER_WIDTH := 0.6
const CHANNEL_LENGTHS := 1.2
const CHANNEL_WIDTHS := 4.0
## Open water past a marina's last pier (lengths of the longest ship it takes),
## for its tugs and ships to turn in coming in to the berths at that end.
const TURN_WATER_LENGTHS := 0.6
const QUAY_STRIP_LENGTHS := 0.9
const QUAY_STRIP_MIN := 8.0
## Coming into its slot: how far (dock units) inside the channel a ship's bow
## is as it enters the slot's mouth, how far along the channel (ship lengths)
## before its slot it starts to come round, which side of the channel (a
## share of its width) it keeps to on the way (across from its pier), how
## hard its curves lean (see _pose_path()).
const SLOT_ENTRY_CLEAR := 0.5
const SLOT_TURN_LENGTHS := 0.7
const CHANNEL_SIDE := 0.25
const SLOT_PATH_HANDLE := 0.35
## A lane that comes in to a port from behind or beside its jetty (nearer the
## port along the sea than JETTY_ROUND_FROM of the jetty's radius) rounds the
## jetty's end first, out past it by JETTY_ROUND of its radius each way (see _round_jetty()).
const JETTY_ROUND := 1.5
const JETTY_ROUND_FROM := 0.9
## A plain curve in that keeps this many of the jetty's radius off the port
## (and never behind the coast) needn't round it.
const JETTY_CLEAR := 1.15
const ENTRANCE_WIDTHS := 3.0
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
const BOLLARD_RADIUS := 0.07  # (About a person's width across: see DeckCrew.)
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
const CANAL_CUT_WIDTH := 4.0
const CANAL_EXIT_DEG := 0.25
## Ships keep to the right-hand side of a harbour entrance, this many widths
## (of the widest ship the marina takes) off its middle.
const KEEP_RIGHT_WIDTHS := 0.6
## A ship backing out of a berth it lies bow in to (its slot, bow to the wall) goes this
## share of its speed, then turns round in this long (s of play) on its
## thrusters before heading out (see _unberth_plan()).
const UNBERTH_REVERSE_SPEED := 0.5
const UNBERTH_TURN_S := 2.5
## A click this near a bird picks it (its colony).
const BIRD_HIT_MIN_PX := 6.0
## Birds are picked this many times further out than their own reach (their
## span and BIRD_HIT_MIN_PX), so they're easier to click.
const BIRD_HIT_REACH := 1.6
## Birds are drawn this many times their span (in dock units), to read clearly.
const BIRD_SCALE := 1.4
## The smallest bird's span (dock units: a sandpiper's), and how wide (px) a
## bird has to be to show as a dot, and to be drawn (smaller, it's a dot).
const BIRD_SMALLEST_SPAN := 0.6
const BIRD_DOT_PX := 1.6
const BIRD_FULL_PX := 4.0
## Birds' meshes are made for wings out in steps this big, at sizes this many
## times apart, and this many kept (see _draw_bird_mesh()).
const BIRD_WING_STEP := 0.05
const BIRD_SIZE_STEP := 1.12
const BIRD_MESHES_KEPT := 3000
const BIRD_SIZE_LOG := 1.0 / log(BIRD_SIZE_STEP)
## A bird's modes in the air (see BirdLife.bird_state()).
const FLYING_MODES := {fly = true, circle = true, soar = true, glide = true, hunt = true, follow = true}
## How far (km) a colony's birds ever get from it (gulls following ships
## furthest), and how far past the screen's edge (px) birds are looked for:
## colonies further off aren't worked out at all.
const BIRD_REACH_KM := {gulls = 80.0, other = 60.0}
const BIRD_VIEW_MARGIN_PX := 60.0
## Birds keeping still at least this long (s) are drawn on their own layer,
## drawn again this long before the first of them moves (see _draw_birds()).
const STILL_LAYER_S := 4.0
const STILL_LAYER_MARGIN_S := 0.5
## How many points along each screen edge _screen_lon_lat_box() traces.
const SCREEN_BOX_STEPS := 6
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
static var _marina_layouts := {}
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
## Whether the ports' moorings have been laid (they need the map's land): the
## ships lying at the anchorages before that are given their spots again.
var _moorings_ready := false
var _spots_frame := -1
## Set when any ship changes (docks, leaves, takes or gives up a berth): the
## spots are only looked at again then.
var _spots_dirty := true
var _dock_seen := {}
var _last_spot := {}
## Ship -> [its leg, how far it curves in and out of port] (see _harbour_reaches()).
var _harbour_reach_cache := {}
## Each ship's curve in or out of its harbour as last worked out, [key, curve] (see _harbour_pose()).
var _harbour_curves := {}
## Each moored ship's pose as last worked out, [key, pose] (see _docked_screen_pose()).
var _moored_poses := {}
## Ships at sea on a special footing this frame: ship -> [screen point, angle] or [] (see _sea_pose()).
var _sea_poses := {}
var _sea_poses_frame := -1
## Birds drawn this frame, for clicks: [screen point, reach, what they're round, flock] (see _draw_birds()).
var _bird_hits: Array = []
## Species name -> its color as a dot (see _bird_dot_color()).
var _bird_dot_colors := {}
## Each bird's and swimming duck's mesh as made (see _draw_bird_mesh()), and
## each sea duck's colors for flying.
var _bird_meshes := {}
var _duck_flyers := {}
var _bird_mesh_ids := 0
var _bucket_span := -1.0
var _bucket := 0
var _bucket_made := 1.0
## Bird index -> the box (lon, lat) it can be in till its spell ends, till when,
## and Wildlife.where_changes then (see _draw_birds()); a bird with no
## telling is anywhere for a second at a time.
const NO_BIRD_BOUND := [Rect2(), -INF, -1]
const EVERYWHERE := Rect2(-1.0e9, -1.0e9, 2.0e9, 2.0e9)
var _bird_bounds := {}
## [marina radius, depth, what] -> where an HQ building may stand, or its
## industry plots (see _hq_region(), _industry_plots()).
var _hq_regions := {}
## Each port's marina's canvas item (see _update_marinas()), and the port
## whose marina is being drawn into its item (its dock points come out in dock
## units, unturned; see _dock_point()), or "".
var _marina_items := {}
## The towns' triangles built natively (TownMesh), when the library's there.
var _town_mesher: Object = null
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
var _upwind_time := -1
const UPWIND_REFRESH_MS := 250

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

## A canal port's cut through its basin's land end (dock units): water from
## the channel's end straight on inland through the quay, where the canal
## goes on, lined with quay edges. [] for other marinas.
static func _canal_cut(layout: Dictionary) -> PackedVector2Array:
	if not layout.has("canal"):
		return PackedVector2Array()
	var from := Vector2(-float(layout.depth) + 0.5, 0.0)
	var reach := absf(_quay_inland(layout) - from.x) + 1.0
	return _rect(from, from + Vector2.LEFT * reach, CANAL_CUT_WIDTH / 2.0)

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

## The widest ship of any kind (dock units): what a mooring slip is pitched for (see _lay_moorings()).
static func _widest_any_ship() -> float:
	var widest := 0.0
	for model: Dictionary in GameData.ship_models:
		widest = maxf(widest, float(model.get("map_size", [14, 6])[1]) * SHIP_SIZE)
	return widest

## A marina's layout in dock units, the port at (0, 0) and the sea along +x:
## a basin dug into the land behind the coast, open to the sea, with piers
## reaching in from its two side walls like a rib cage, a channel between
## their tips from the entrance to the land end, and a breakwater (the jetty)
## curving out round the sea side with the entrance in its middle; behind the
## basin, on the land, the quay the HQ and industry stand on. Every pier's as
## long as the longest ship the port takes, and the port has one for each
## berth (Docks.berth_kinds(): 6, 8, 10 or 14 as ports grow, 14 at a hub),
## one fewer than its berths each side. A ship moors in the slot seaward of
## its pier's face, bow to the wall: the first each side along the first
## pier's seaward face, open to the outer harbour, the rest between a pier and
## the next, the last along the land end. Tugs moor along the inside of the
## jetty's arms (see _jetty_pose()).
## {radius (the jetty's: the walls' outer edges, where it starts), inner (half
## the basin's width), corners (the basin's, from its seaward +y corner round
## the land end to -y), berths (one per kind: [where the middle of a ship
## moored there is, on the pier's face; the way the ship faces; the way off
## the face into the slot; the face's length; its middle; its kind]), slip
## ([]: none now), gap (the entrance's half-angle), mouth (where ships come in
## and leave, just outside), inside (just inside the entrance), length and
## width (the longest and widest ship that docks), pier (how long the piers
## are), pier_width, pitch (from one pier to the next), top (the channel's
## room before the first pier), depth (the basin's, from the coast to its
## land end), channel (the width between the pier tips), strip (how deep the
## quay behind the basin is), piers ([side (1 +y, -1 -y), seaward face x,
## landward face x] each), tugs ([position, facing] a tug moored at each), rocks ([middle, radius, which art] each: see ROCK_SPOTS)}.
static func _marina_layout(kinds: String, hub: bool, canal := false) -> Dictionary:
	var key := [kinds, hub, canal]
	if _marina_layouts.has(key):
		return _marina_layouts[key]
	var length := 0.0
	var width := 0.0
	for i in kinds.length():
		var ship := _berth_ship(kinds[i])
		length = maxf(length, ship.x)
		width = maxf(width, ship.y)
	var count := kinds.length()
	@warning_ignore("integer_division")
	var per_side := PackedInt32Array([(count + 1) / 2, count / 2])  # +y side, -y side.
	var slot := width + 2.0 * BERTH_GAP  # The top slot each side: one ship, along the first pier's seaward face, open to the outer harbour.
	var double := 2.0 * width + 3.0 * BERTH_GAP  # Every other slot: two ships side by side, each straight in, bow to the wall.
	var pitch := double + PIER_WIDTH
	var top := slot
	var channel := maxf(length * CHANNEL_LENGTHS, width * CHANNEL_WIDTHS)
	var half := length + channel / 2.0
	var radius := half + QUAY_WIDTH
	@warning_ignore("integer_division")
	var deep := maxi(per_side[0], per_side[1]) / 2  # Double slots a side (the last one's land side its own pier, turning water beyond).
	# Past the last slot, its own pier and then open water for turning (TURN_WATER_LENGTHS):
	# no berth lies against the basin's end wall, where nothing could be turned in to it.
	var depth := top + deep * pitch + PIER_WIDTH + length * TURN_WATER_LENGTHS
	var strip := maxf(length * QUAY_STRIP_LENGTHS, QUAY_STRIP_MIN)
	var berth_list := []
	var piers := []
	for s in 2:
		var side := 1.0 if s == 0 else -1.0
		var count_here: int = per_side[s]
		@warning_ignore("integer_division")
		var piers_here: int = count_here / 2
		var y := side * (half - length / 2.0)
		# A berth: [its middle on its wall, along the wall, which way the ship lies
		# off it, its length, its middle again, its kind, and the x of the lane it
		# comes straight in along (and backs out along)]. The top berth lies along
		# pier 0's seaward face; then each double slot j (between pier j-1's
		# landward face and pier j's seaward face) takes two:
		# one along its land side, one along its sea side, side by side.
		var k := 0
		berth_list.append([Vector2(-top, y), Vector2(0.0, side), Vector2.RIGHT, length, Vector2(-top, y), kinds[s * per_side[0] + k], -top + BERTH_GAP + width / 2.0])
		k += 1
		piers.append([side, -top, -top - PIER_WIDTH])
		for j in range(1, piers_here + 1):
			var sea_edge := -top - PIER_WIDTH - (j - 1) * pitch
			var land_edge := sea_edge - double
			piers.append([side, land_edge, land_edge - PIER_WIDTH])  # (The last one's too: turning water beyond it.)
			if k < count_here:
				berth_list.append([Vector2(land_edge, y), Vector2(0.0, side), Vector2.RIGHT, length, Vector2(land_edge, y), kinds[s * per_side[0] + k], land_edge + BERTH_GAP + width / 2.0])
				k += 1
			if k < count_here:
				berth_list.append([Vector2(sea_edge, y), Vector2(0.0, side), Vector2.LEFT, length, Vector2(sea_edge, y), kinds[s * per_side[0] + k], sea_edge - BERTH_GAP - width / 2.0])
				k += 1
	# Tugs along the inside of the jetty's arms (see _jetty_pose()): the two arms
	# by turns, from TUG_ARM_FROM round towards the entrance, TUG_MOOR_GAP apart,
	# bow to the entrance.
	var gap := asin(clampf(width * ENTRANCE_WIDTHS / 2.0 / radius, 0.05, 0.6))
	var tug := _berth_ship("tug")
	var tugs := []
	var off := radius - JETTY_WIDTH / 2.0 - tug.y / 2.0 - TUG_HULL_GAP
	var step := (tug.x + TUG_MOOR_GAP) / off
	var angles := PackedFloat32Array()
	var a := TUG_ARM_FROM - step / 2.0
	while a >= gap + TUG_MOOR_END + step / 2.0:
		angles.append(a)
		a -= step
	if angles.is_empty():
		angles.append(maxf(TUG_ARM_FROM - step / 2.0, gap + TUG_MOOR_END))
	for k in angles.size():
		for side: float in [1.0, -1.0]:
			tugs.append([Vector2.from_angle(angles[k] * side) * off, angles[k] * side - side * PI / 2.0])
	# The rocks the birds perch on: outside the jetty's arms, off to either side
	# (skipped where that's land), more and bigger at a bigger port, a ship's
	# width or more across.
	var rocks := []
	var rock_count := 3 if count <= 6 else (4 if count <= 8 else 5)
	for k in rock_count:
		var spot: Array = ROCK_SPOTS[k]
		rocks.append([Vector2.from_angle(deg_to_rad(float(spot[1]))) * float(spot[0]) * radius, float(spot[2]) * radius, k % 3])
	var corners := PackedVector2Array([Vector2(0.0, half), Vector2(-depth, half), Vector2(-depth, -half), Vector2(0.0, -half)])
	var layout := {radius = radius, inner = half, corners = corners, berths = berth_list, slip = [], gap = gap,
		mouth = Vector2(radius + length * 1.2, 0.0), inside = Vector2(radius * 0.45, 0.0), length = length, width = width,
		pier = length, pier_width = PIER_WIDTH, pitch = pitch, top = top, depth = depth, channel = channel, strip = strip, piers = piers, tugs = tugs, rocks = rocks}
	if canal:
		# Where the canal comes in: straight on inland from the channel's land end.
		layout.canal = []
		layout.canal_angle = PI
	_marina_layouts[key] = layout
	return layout


## The longest and widest cargo ship (dock units) a berth of a kind takes (see
## Docks.berth_kinds()): the Small ports' ships ("s"), the Medium's ("m"), or
## the biggest ("B", "L"); or ("tug") the tugs.
static func _berth_ship(kind: String) -> Vector2:
	if kind == "tug":
		var tug := Vector2.ZERO
		for model: Dictionary in GameData.ship_models:
			if model.get("tug", false):
				tug = Vector2(maxf(tug.x, _model_length(model)), maxf(tug.y, float(model.get("map_size", [7, 3.6])[1]) * SHIP_SIZE))
		return tug
	var band := "large" if kind == "B" or kind == "L" else ("medium" if kind == "m" else "small")
	return Vector2(_band_ship_length(band), _widest_ship(band))

## A port's marina as it is now (its berths, and whether it's a hub port).
func _port_layout(port_id: String) -> Dictionary:
	# Asked for very often (every port and docked ship, every frame): kept
	# while what it's made of stays (its berths, by the port's size and hubs,
	# and whether a canal runs through), looked at again once a frame per port.
	var frame := Engine.get_process_frames()
	var kept: Array = _port_layouts.get(port_id, [])
	if not kept.is_empty() and kept[0] == frame:
		return kept[2]
	var key := [GameState.docks.berth_kinds(port_id), GameState.docks.has_hub(port_id), _is_canal_port(port_id)]
	if not kept.is_empty() and kept[1] == key:
		kept[0] = frame
		return kept[2]
	var t_l := Time.get_ticks_usec()
	var layout := _marina_layout(key[0], key[1], key[2])
	_prof("layout", t_l)
	_port_layouts[port_id] = [frame, key, layout]
	return layout

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
## False while the map's zoomed too far out for any port's marina to show (even
## the biggest marina's reach smaller than the smallest dot): nothing to look at.
func _any_marina_shown() -> bool:
	return MARINA_MAX_REACH * _ship_scale() >= PORT_RADIUS_MIN + MARINA_OVER_DOT_PX

func _marina_shown(port_id: String) -> bool:
	if not docks_shown() or not _any_marina_shown():
		return false
	var frame := Engine.get_process_frames()
	if frame != _marinas_shown_frame:  # Asked for every ship there, every frame.
		_marinas_shown_frame = frame
		_marinas_shown.clear()
	if not _marinas_shown.has(port_id):
		_marinas_shown[port_id] = float(_port_layout(port_id).radius) * _ship_scale() >= _port_radius(port_id) + MARINA_OVER_DOT_PX
	return _marinas_shown[port_id]

## How many marinas are drawn into their items in one frame (the rest wait a frame: see _update_marinas()).
const MARINA_RECORDS_PER_FRAME := 1
## Zooming, a marina drawn at a zoom this far off (the log of the ratio: log 2,
## twice or half) is drawn again even before the zoom settles (see _update_marinas()).
const MARINA_RESCALE_LOG := 0.6931
var _marinas_pending := false

## Every port's marina in view (see the section's description). Each is drawn
## once into its own canvas item (_marina_items), in dock units at the zoom
## it's drawn at, and then only moved and turned with the view: dragging the
## map doesn't draw them again, only zooming (so lines keep their width in px),
## a port changing size or becoming a hub, or its HQ building growing.
## The ports near the view whose marinas may show (natively narrowed by the
## dots' looks, once those are known): their places in GameData.ports.
func marinas_in_view(near: Rect2) -> PackedInt32Array:
	if _port_painter == null or _port_styles_key.is_empty():
		return _ports_near_view()
	return _port_painter.marinas(_ports_near_view(), {right = _right, up = _up, toward = _toward, radius = _radius(),
		middle = size / 2.0, near = near, scale = _ship_scale(), over_dot_px = MARINA_OVER_DOT_PX})

func _update_marinas() -> void:
	var shown := {}
	var recorded := 0
	_marinas_pending = false
	if show_ships and docks_shown() and _any_marina_shown():
		var view := Rect2(Vector2.ZERO, size)
		var near := view.grow(MARINA_MAX_REACH * _ship_scale())
		# (Natively narrowed to the ports whose marinas may show, once the dots' looks are known.)
		var ports := marinas_in_view(near)
		var kept := _kept_marina_ports()  # (Drawn however far off screen they are.)
		for i in kept:
			if not ports.has(i):
				ports.append(i)
		for i in ports:
			var port_id: String = GameData.ports[i].id
			var root := port_screen_position(port_id)
			var keep := kept.has(i)
			if not keep and not near.has_point(root) or not _marina_shown(port_id):
				continue  # (Cheapest first: most ports are well off screen.)
			var layout := _port_layout(port_id)
			var reach := MARINA_MAX_REACH * _ship_scale()  # (The quay's square corners and the town behind.)
			if not keep and not view.grow(reach).has_point(root):
				continue
			shown[port_id] = true
			var item := _marina_item(port_id, i)
			var key := [_dock_flips.get(port_id, 1.0), _hq_look(port_id), _land_cells.is_empty(), _shadow_key()]  # (The town needs the land; the shadows the sun.)
			var pivot := item.get_parent() as Node2D  # (Moved and turned, not the item: a Control turned draws again.)
			var scale := _ship_scale()
			var recorded_scale := float(item.get_meta(&"scale", 0.0))
			var stale: bool = not is_same(item.get_meta(&"layout"), layout) or item.get_meta(&"key") != key
			# Zooming, a marina drawn at another zoom is stretched to this one by
			# its pivot, and drawn again once the zoom settles (or when it's
			# twice as far off): drawing every marina in view again every frame
			# of a zoom was most of the frame.
			var rescale: bool = not stale and recorded_scale > 0.0 and recorded_scale != scale
			if stale or (rescale and (not _zooming() or absf(log(scale / recorded_scale)) > MARINA_RESCALE_LOG)):
				if recorded >= MARINA_RECORDS_PER_FRAME:
					_marinas_pending = true  # (Drawn next frame: a town is a lot to draw at once.)
					if item.get_meta(&"layout").is_empty():
						_show_marina_item(item, false)  # (Nothing drawn in it yet: nothing to show.)
						continue
					if recorded_scale > 0.0:
						pivot.scale = Vector2.ONE * (scale / recorded_scale)  # (As it was, stretched, till its turn.)
				else:
					recorded += 1
					item.set_meta(&"layout", layout)
					item.set_meta(&"key", key)
					item.set_meta(&"scale", scale)
					item.queue_redraw()
					pivot.scale = Vector2.ONE
			elif rescale:
				pivot.scale = Vector2.ONE * (scale / recorded_scale)
			pivot.position = root
			pivot.rotation = _port_sea_angle(port_id) + _port_turn(port_id)
			_show_marina_item(item, true)
	for port_id: String in _marina_items:
		if not shown.has(port_id):
			_show_marina_item(_marina_items[port_id], false)

## The marinas kept drawn however far off screen they are (see
## _update_marinas()): those of the ports nearest the middle of the view with
## their marinas on screen (up to KEPT_MARINA_CENTRES; the port nearest the
## middle if none is), and of the KEPT_MARINA_NEIGHBOURS ports nearest each
## of them, so zoomed right in on a port, the marinas beside it never vanish
## for being off screen (the MARINA_MAX_REACH cull). Their places in GameData.ports.
const KEPT_MARINA_CENTRES := 2
const KEPT_MARINA_NEIGHBOURS := 2
var _port_neighbours := {}
func _kept_marina_ports() -> PackedInt32Array:
	var out := PackedInt32Array()
	var view := Rect2(Vector2.ZERO, size)
	var middle := size / 2.0
	var scale := _ship_scale()
	var centres := []  # [distance from the middle (px), place in GameData.ports]
	var nearest := [INF, -1]
	for i in _ports_near_view():
		var port_id: String = GameData.ports[i].id
		var at := port_screen_position(port_id)
		if _is_hidden(at):
			continue
		var d := at.distance_to(middle)
		if d < float(nearest[0]):
			nearest = [d, i]
		if view.grow(float(_port_layout(port_id).radius) * scale).has_point(at):
			centres.append([d, i])
	if centres.is_empty() and int(nearest[1]) >= 0:
		centres.append(nearest)
	centres.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in mini(centres.size(), KEPT_MARINA_CENTRES):
		var i: int = centres[k][1]
		if not out.has(i):
			out.append(i)
		for j in _port_neighbours_of(i):
			if not out.has(j):
				out.append(j)
	return out

## The KEPT_MARINA_NEIGHBOURS ports nearest a port (their places in
## GameData.ports, nearest first), worked out once.
func _port_neighbours_of(index: int) -> PackedInt32Array:
	if not _port_neighbours.has(index):
		var port: Dictionary = GameData.ports[index]
		var here := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
		var others := []  # [nm, place]
		for j in GameData.ports.size():
			if j == index:
				continue
			var other: Dictionary = GameData.ports[j]
			others.append([Geo.distance_nm(here, Vector2(float(other.get("lon", 0.0)), float(other.get("lat", 0.0)))), j])
		others.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		var near := PackedInt32Array()
		for k in mini(others.size(), KEPT_MARINA_NEIGHBOURS):
			near.append(int(others[k][1]))
		_port_neighbours[index] = near
	return _port_neighbours[index]

## Shows or hides a marina's canvas item as the view moves. (Through the
## rendering server: hiding a Control and showing it again draws it again,
## and its drawing hasn't changed.)
func _show_marina_item(item: Control, shown: bool) -> void:
	if bool(item.get_meta(&"shown", true)) != shown:
		item.set_meta(&"shown", shown)
		RenderingServer.canvas_item_set_visible(item.get_canvas_item(), shown)
	if not shown:
		# Parked far off screen too: should anything show it again, it isn't left
		# where it was, drawn at the zoom it was (put back when shown).
		(item.get_parent() as Node2D).position = HIDDEN


## A port's marina's canvas item (see _update_marinas()), made the first time,
## among the others in the ports' order (so where two overlap, the same one's on top).
func _marina_item(port_id: String, order: int) -> Control:
	if _marina_items.has(port_id):
		return _marina_items[port_id]
	var item := Control.new()
	item.mouse_filter = MOUSE_FILTER_IGNORE
	item.set_meta(&"layout", {})
	item.set_meta(&"key", [])
	item.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		var _lay := _town(port_id, _port_layout(port_id))
		_prof("marina_lay", t0)
		t0 = Time.get_ticks_usec()
		_record_marina(port_id, item)
		_prof("marina_record", t0))
	var at := 0
	for child in _dock_layer.get_children():
		if int(child.get_meta(&"order", -1)) < order:
			at += 1
	# On a Node2D that moves and turns it with the view (see _update_marinas()),
	# among the others in the ports' order.
	var pivot := Node2D.new()
	pivot.set_meta(&"order", order)
	pivot.add_child(item)
	_dock_layer.add_child(pivot)
	_dock_layer.move_child(pivot, at)
	_marina_items[port_id] = item
	return item

## Lays out every port's town (see _town()) under the loading screen (the map
## isn't warm till they're laid: see is_warm()), TOWN_WARM_MS of them a frame,
## so the first look at a port's marina draws it at once, not after laying its
## town out (a few ms: a hitch as a port scrolls in).
const TOWN_WARM_MS := 8.0
var _towns_warm := false
var _town_warm_cursor := 0
func _warm_towns() -> void:
	if _towns_warm or _land_cells.is_empty() or _dragging or _zooming() or _marinas_pending or _layers_stale:
		return
	var start := Time.get_ticks_usec()
	var ports := GameData.ports
	while _town_warm_cursor < ports.size():
		var port_id: String = ports[_town_warm_cursor].id
		_town_warm_cursor += 1
		var layout := _port_layout(port_id)
		if not (_towns.has(port_id) and _towns[port_id].key == [port_id, layout.radius, layout.depth]):
			_town(port_id, layout)
			if Time.get_ticks_usec() - start >= TOWN_WARM_MS * 1000.0:
				return
	_towns_warm = true

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
## plots in a row along the +y half of the quay behind the basin (the HQ has
## the -y half), equal squares as big as fit, nearest the basin. [Rect2...].
func _industry_plots(layout: Dictionary) -> Array:
	var key := [layout.radius, layout.depth, "industry"]
	if _hq_regions.has(key):
		return _hq_regions[key]
	var near := -(float(layout.depth) + QUAY_WIDTH) - HQ_MARGIN
	var far := _quay_inland(layout) + HQ_MARGIN
	var gap := HQ_MARGIN * 0.6
	var room := float(layout.radius) - 2.0 * HQ_MARGIN
	var side := minf(near - far, (room - (Hub.INDUSTRY_SLOTS - 1) * gap) / Hub.INDUSTRY_SLOTS)
	var plots := []
	if side > 0.5:
		for slot in Hub.INDUSTRY_SLOTS:
			plots.append(Rect2(Vector2(near - side, HQ_MARGIN + slot * (side + gap)), Vector2.ONE * side))
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
		var drop := _shadow_drop(port_id, 0.7)
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

## A port's marina drawn (see _marina_layout()): the water cleared round it
## (the outer harbour inside the jetty), the land it's dug into (the walls
## either side, the land end and the quay behind), its basin, the piers from
## the walls, the quay edges, the HQ and industry on the quay, a canal port's
## cut, the jetty round the sea side either side of the entrance (lit at its
## ends) and the bollards along the piers' faces.
func _draw_marina(port_id: String, layout: Dictionary) -> void:
	var radius: float = layout.radius
	var half: float = layout.inner
	var depth: float = layout.depth
	var water := _color(&"ocean")
	var scale := _ship_scale()
	var clear := radius + JETTY_WIDTH / 2.0
	_batch.clear()
	_batch.poly(_marina_polygon(port_id, _arc(clear, -PI, PI).slice(0, -1)), water)  # (Convex: a fan, not a triangulation.)
	_batch.flush(_canvas)
	var inland := _quay_inland(layout)
	# The land: the quay behind the basin, with the lighthouse's pad behind the industry.
	var land := PackedVector2Array([Vector2(0.0, radius), Vector2(inland, radius), Vector2(inland, radius * 0.8), Vector2(inland - LIGHTHOUSE_ROOM, radius * 0.8),
		Vector2(inland - LIGHTHOUSE_ROOM, radius * 0.3), Vector2(inland, radius * 0.3), Vector2(inland, -radius), Vector2(0.0, -radius)])
	_canvas.draw_colored_polygon(_marina_polygon(port_id, land), QUAY_COLOR)
	var basin := PackedVector2Array([Vector2(0.5, half), Vector2(-depth, half), Vector2(-depth, -half), Vector2(0.5, -half)])
	_canvas.draw_colored_polygon(_marina_polygon(port_id, basin), water)
	# A canal port's cut through the land end, where its canal comes in.
	var cut := _canal_cut(layout)
	if not cut.is_empty():
		var cut_screen := _marina_polygon(port_id, cut)
		_canvas.draw_colored_polygon(cut_screen, water)
		_canvas.draw_line(cut_screen[0], cut_screen[1], QUAY_EDGE, 1.0, true)
		_canvas.draw_line(cut_screen[2], cut_screen[3], QUAY_EDGE, 1.0, true)
	# The piers, each from its wall in.
	var pier_length: float = layout.pier
	var pier_edges: Array[PackedVector2Array] = []
	for pier: Array in layout.piers:
		var side: float = pier[0]
		var rect := PackedVector2Array([Vector2(pier[1], side * half), Vector2(pier[1], side * (half - pier_length)), Vector2(pier[2], side * (half - pier_length)), Vector2(pier[2], side * half)])
		var points := _marina_polygon(port_id, rect)
		_batch.poly(points, QUAY_COLOR)
		points.append(points[0])
		pier_edges.append(points)
	_batch.flush(_canvas)
	for points: PackedVector2Array in pier_edges:
		_canvas.draw_polyline(points, QUAY_EDGE, 1.0, true)
	# The basin's edge (its three walls), and the land's outer edge.
	_canvas.draw_polyline(_marina_polygon(port_id, PackedVector2Array([Vector2(0.0, half), Vector2(-depth, half), Vector2(-depth, -half), Vector2(0.0, -half)])), QUAY_EDGE, 1.0, true)
	_canvas.draw_polyline(_marina_polygon(port_id, land), QUAY_EDGE, 1.0, true)
	var t_m := Time.get_ticks_usec()
	_draw_hq_building(port_id, layout)
	_draw_industry(port_id, layout)
	_prof("marina.hq_industry", t_m)
	t_m = Time.get_ticks_usec()
	_draw_lighthouse(port_id, layout, scale)
	_prof("marina.lighthouse", t_m)
	t_m = Time.get_ticks_usec()
	_draw_town(port_id, layout, scale)
	_prof("marina.town", t_m)
	t_m = Time.get_ticks_usec()
	# The jetty: round the sea half, each side of the entrance, lit at its ends.
	var gap: float = layout.gap
	for side: float in [-1.0, 1.0]:
		var arm := _arc(radius, gap * side, PI / 2.0 * side)
		var points := _marina_polygon(port_id, arm)
		_canvas.draw_polyline(points, QUAY_EDGE, JETTY_WIDTH * scale + 2.0, true)
		_canvas.draw_polyline(points, JETTY_COLOR, JETTY_WIDTH * scale, true)
		_disc(points[0], maxf(JETTY_WIDTH * scale * 0.45, 1.2), ENTRANCE_LIGHTS[0 if side < 0.0 else 1])
	_prof("marina.jetty", t_m)
	t_m = Time.get_ticks_usec()
	# The rocks the birds perch on (see ROCK_SPOTS), foam round each.
	for rock: Array in layout.rocks:
		var texture := _rock_texture(int(rock[2]))
		if texture == null or not _rock_shown(port_id, rock):
			continue
		var across := float(rock[1]) * 2.0 * scale
		_canvas.draw_texture_rect(texture, Rect2(_dock_point(port_id, rock[0]) - Vector2.ONE * across / 2.0, Vector2.ONE * across), false)
	# Bollards along every berth's face, once they're far enough apart to tell apart.
	if BOLLARD_STEP * scale < 4.0:
		return
	var bollard := maxf(BOLLARD_RADIUS * scale, 0.9)
	_batch.clear()  # (All of them as one batch: a big port has over a hundred.)
	for berth: Array in layout.berths:
		for post in _bollards(berth):
			_batch.disc(_dock_point(port_id, post), bollard, BOLLARD_COLOR, 12)
	_batch.flush(_canvas)
	_prof("marina.bollards", t_m)

## A rock's art (see ROCK_SPOTS): rock_a, rock_b or rock_c in SEA_ART_DIR.
static func _rock_texture(which: int) -> Texture2D:
	if _rock_art.is_empty():
		for name in ["rock_a", "rock_b", "rock_c"]:
			var path: String = SEA_ART_DIR + name + ".svg"
			_rock_art.append(load(path) if ResourceLoader.exists(path) else null)
	return _rock_art[posmod(which, _rock_art.size())]

## True if a port's rock shows: those outside the jetty only where that's water.
func _rock_shown(port_id: String, rock: Array) -> bool:
	var layout := _port_layout(port_id)
	return (rock[0] as Vector2).length() <= float(layout.radius) or not _on_land(_dock_lon_lat(port_id, rock[0]))

## How far inland (dock units, -x) a marina's land reaches: past its basin's
## land end and the quay behind it.
static func _quay_inland(layout: Dictionary) -> float:
	return -(float(layout.depth) + QUAY_WIDTH + float(layout.strip))

# --- HQ buildings ---------------------------------------------------------------

## A company's HQ building's level (1 to HQ_LEVELS): one more every
## HQ_LEVEL_EVERY company levels.
static func hq_level(company: Company) -> int:
	return clampi(1 + company.level() / HQ_LEVEL_EVERY, 1, HQ_LEVELS)

## Where a port's HQ building can stand (dock units): the -y half of the quay
## behind the basin, HQ_MARGIN in from its edges (the industry has the +y half).
func _hq_region(layout: Dictionary) -> PackedVector2Array:
	var key := [layout.radius, layout.depth, "hq"]
	if _hq_regions.has(key):
		return _hq_regions[key]
	var near := -(float(layout.depth) + QUAY_WIDTH) - HQ_MARGIN
	var far := _quay_inland(layout) + HQ_MARGIN
	var region := PackedVector2Array([Vector2(near, -HQ_MARGIN), Vector2(far, -HQ_MARGIN), Vector2(far, -float(layout.radius) + HQ_MARGIN), Vector2(near, -float(layout.radius) + HQ_MARGIN)])
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

## The company's HQ building on the quay behind its port's basin, growing with it through
## HQ_LEVELS levels (see hq_level()), seen from above: from a little wooden
## hut with its company's flag (1) through a wooden house, a stone lodge, a
## brick office and concrete offices with roof gardens, to glass offices with
## roof terraces, and a tech campus filling its half of the quay (10),
## a terrace on its roof and a helicopter pad.
func _draw_hq_building(port_id: String, layout: Dictionary) -> void:
	var owner: Company = null
	for each in GameState.all_companies():
		var hub := each.hub_at(port_id)
		if hub != null and hub.is_hq:
			owner = each
			break
	if owner == null:
		return
	var level := hq_level(owner)
	var tint := GameState.company_color_value(owner.color)
	var foot := _hq_foot(layout, level)
	if foot.size() < 3:
		return
	var box := _bounds(foot)
	# Its shadow, the taller the longer.
	var height := 0.3 + 0.22 * level
	var drop := _shadow_drop(port_id, height)  # (Away from the sun: see _update_shadow_dir().)
	var shadow := _marina_polygon(port_id, foot)
	for i in shadow.size():
		shadow[i] += drop
	_canvas.draw_colored_polygon(shadow, Color(0, 0, 0, 0.28))
	if level <= 3:
		_draw_hq_house(port_id, level, box, tint)
	else:
		_draw_hq_block(port_id, level, foot, box, tint)

## An HQ building's footprint at a level (dock units): from the corner of its
## half of the quay furthest inland and from the channel, growing towards the
## basin; all of its half at the top level. [] if there's no room.
func _hq_foot(layout: Dictionary, level: int) -> PackedVector2Array:
	var region := _hq_region(layout)
	if region.size() < 3:
		return PackedVector2Array()
	if level >= HQ_LEVELS:
		return region
	var area := _bounds(region)
	var share := lerpf(0.22, 0.92, pow(float(level - 1) / float(HQ_LEVELS - 2), 1.1))
	var size := area.size * share
	return _clip_inside(_rect_points(Rect2(Vector2(area.position.x, area.end.y - size.y), size)), region)

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
	# The flag at its corner nearest the basin, on its outer side: a pole and its pennant.
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
	# The company's sign along the front.
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
## tug at its moorings), or gliding out to it.
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
	return pose

## Where a docked ship sets off from when it sails (on the unit sphere), its
## heading, whether it was lying at anchor facing the wind (not heading out
## already) and its mooring's slot (or -1): noted as it's drawn (see
## _harbour_end()). Only as drawn: a pose asked for in the instant between its
## berth's release and its setting off (berth gone, phase none, still in port)
## would put it at the anchorage, and it would set off from there.
func _note_last_spot(ship: Ship, at: Vector2, angle: float) -> void:
	var at_moor := str((_spot_keys.get(ship, ["", ""]) as Array)[1]) == "moor"
	_last_spot[ship] = [ship.docked_at, _screen_unit(at), angle, ship.berth < 0 and ship.berth_phase == Ship.BERTH_NONE, int(_spot_slots.get(ship, -1)) if at_moor else -1]

## Where a docked ship is on screen and which way it faces: moored at its
## berth, coming in and into its slot, backing out and away, lying at the
## anchorage, or gliding out to it.
func _docked_screen_pose(ship: Ship) -> Array:
	var port := ship.docked_at
	var layout := _port_layout(port)
	_update_spots()
	var worked := _worked_pose(ship)  # (Brought in by tugs.)
	if not worked.is_empty():
		return worked
	if ship.berth >= 0 and ship.berth < layout.berths.size():
		var berth: Array = layout.berths[ship.berth]
		if ship.berth_phase != Ship.BERTH_IN and ship.berth_phase != Ship.BERTH_OUT:
			# Moored (most ships in port, most of the time): where its berth puts
			# it, which only changes with the view or the port's layout.
			var key := [port, ship.berth, ship.berth_half, ship.model_id, layout.berths.size(), float(layout.radius), _view_epoch]
			var kept: Array = _moored_poses.get(ship, [])
			if not kept.is_empty() and kept[0] == key:
				return kept[1]
			var lies := _berth_pose(berth, ship)
			var pose := [_dock_point(port, lies[0]), _dock_angle(port, float(lies[1]))]
			_moored_poses[ship] = [key, pose]
			return pose
		var moored := _berth_pose(berth, ship)
		var at := [_dock_point(port, moored[0]), _dock_angle(port, float(moored[1]))]
		var off := _local_to_screen(port, _berth_off(berth, ship))
		var settings := Docks.settings()
		var slide_s := float(settings.get("slide_s", 1.5))
		var length := (_model_look(ship.model_id)[7] as Rect2).size.x * dock_scale(port)
		match ship.berth_phase:
			Ship.BERTH_IN:
				# Sailing in at its own speed, through the entrance on its right-hand
				# side (turning in smoothly where it already is), down the channel
				# and round into its slot (_slot_approach()), slowing over its last
				# length, then the last little slide onto the pier on its thrusters
				# (see GameState._berth_seconds()).
				var total := ship.berth_duration if ship.berth_duration > 0.0 else float(settings.get("in_s", 6.0))
				var sail := maxf(total - slide_s, 0.01)
				if ship.berth_time < sail:
					var start := _lying_pose(ship, GameState.play_time - ship.berth_time)
					var rest := _rest_pose(ship)
					var weighing := (start[0] as Vector2).distance_to(rest[0]) < 1.0  # (Lying at anchor, facing the wind, or at its mooring.)
					# From its mooring: backing out of its slip and turning there first
					# (see _mooring_leave_plan()), then the way it went there, backwards.
					var leave := _mooring_leave_plan(ship) if weighing else {}
					var t := ship.berth_time
					var before := 0.0
					var turned := 0.0
					var back := Vector2.ZERO
					if not leave.is_empty():
						back = _dock_point(port, leave.back)
						if t < float(leave.reverse_s):
							var share := _sailed_share(t / float(leave.reverse_s), float(leave.reverse_units), float(leave.ease), true, true)
							return [(rest[0] as Vector2).lerp(back, share), rest[1]]
						t -= float(leave.reverse_s)
						turned = _dock_angle(port, float(leave.out_angle))
						if t < UNBERTH_TURN_S:
							return [back, lerp_angle(float(rest[1]), turned, smoothstep(0.0, 1.0, t / UNBERTH_TURN_S))]
						t -= UNBERTH_TURN_S
						before = float(leave.reverse_s) + UNBERTH_TURN_S
					# Its way in only changes with the view (or the berth): worked out
					# once, and only how far along it it is each frame.
					var key := [port, ship.berth, ship.berth_half, ship.model_id, "in", snappedf(GameState.play_time - ship.berth_time, 0.01), float(layout.radius), _view_epoch, leave.is_empty()]
					var way := _berth_way(ship, key)
					if way.is_empty():
						var poses := [start]
						if not leave.is_empty():
							poses = [[back, turned]]
							for pose: Array in leave.poses:
								poses.append(_local_to_screen(port, pose))
						# Through the mouth heading in, unless it's there already (coming in
						# from sea), as near as makes no odds.
						var mouth := _keep_right(port, _entrance_pose(port, false, true))
						var mouth_room := ((layout.mouth as Vector2) - (layout.inside as Vector2)).length() * dock_scale(port) * 0.5
						if not leave.is_empty() or (start[0] as Vector2).distance_to(mouth[0]) > maxf(length, mouth_room):
							poses.append(mouth)
						for pose: Array in _slot_approach(port, berth, ship):
							poses.append(_local_to_screen(port, pose))
						# (Coming round on a turning circle from however it lies: at anchor
						# facing the wind, or part way to its spot when a berth came free.)
						var shaped := _loosen(poses, leave.is_empty(), false, length * ANCHOR_TURN_LENGTHS)
						var path := _pose_path(shaped, SLOT_PATH_HANDLE)
						way = [poses, shaped, path, _path_times(path, _sea_speed_px(ship), length, length, weighing, true)]
						_berth_ways[ship] = [key, way]
					return _follow(way[0], way[1], way[2], _timed_share(way[2], way[3], t / maxf(sail - before, 0.01)))
				return _slide(off, at, (ship.berth_time - sail) / slide_s)
			Ship.BERTH_OUT:
				# Backing straight out of its slot stern first to the channel, turning
				# there on its thrusters to face the way out (_unberth_plan()), then
				# on out through the entrance on its right-hand side to sea (or to
				# its spot at the anchorage, slowing to anchor).
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
				poses.append(_local_to_screen(port, _right_side(port, layout.inside, false)))
				poses.append(_keep_right(port, _entrance_pose(port, false, false)))
				var anchoring := ship.depart_to.is_empty()
				if anchoring:
					var rest := _rest_pose(ship)
					var moorings := _moorings(port) if str((_spot_keys.get(ship, ["", ""]) as Array)[1]) == "moor" else []
					var at_moor := int(_spot_slots.get(ship, 0))
					if at_moor < moorings.size():
						# To its pontoon: round the jetty and in to its slip (see _mooring_way()).
						for pose: Array in _mooring_way(port, moorings[at_moor]):
							poses.append(_local_to_screen(port, pose))
					else:
						var mouth_room := ((layout.mouth as Vector2) - (layout.inside as Vector2)).length() * dock_scale(port) * 0.5
						if (rest[0] as Vector2).distance_to(poses[-1][0]) < maxf(length, mouth_room):
							poses.pop_back()  # (Its spot's right by the mouth: straight there.)
					poses.append(rest)
				# (Its way out kept like its way in, above, till the view or the wind changes.)
				var key := [port, ship.berth, ship.berth_half, ship.model_id, "out", anchoring, plan.reverse, _upwind_time, float(layout.radius), _view_epoch]
				var way := _berth_way(ship, key)
				if way.is_empty():
					var shaped := _loosen(poses, false, anchoring, length * ANCHOR_TURN_LENGTHS)
					var path := _pose_path(shaped, SLOT_PATH_HANDLE)
					way = [poses, shaped, path, _path_times(path, _sea_speed_px(ship), length, length, true, anchoring)]
					_berth_ways[ship] = [key, way]
				var before := float(plan.reverse_s) + UNBERTH_TURN_S if plan.reverse else 0.0
				var sail_s := maxf(total - before, 0.01)
				return _follow(way[0], way[1], way[2], _timed_share(way[2], way[3], t / sail_s))
		return at
	return _lying_pose(ship, GameState.play_time)

## A ship's way in to its berth or out of it as last worked out (see
## _docked_screen_pose()), [poses, shaped poses, path, times along it], if it
## was for `key`; else [].
func _berth_way(ship: Ship, key: Array) -> Array:
	var kept: Array = _berth_ways.get(ship, [])
	return kept[1] if not kept.is_empty() and kept[0] == key else []

## Each ship's way in to its berth or out of it, [key, way] (see _berth_way()).
var _berth_ways := {}

## A pose (screen) moved over to its right-hand side of its port's harbour
## entrance, as ships keep to starboard: in and out pass each other.
func _keep_right(port_id: String, pose: Array) -> Array:
	var side := float(_port_layout(port_id).width) * KEEP_RIGHT_WIDTHS * dock_scale(port_id)
	return [(pose[0] as Vector2) + Vector2.from_angle(float(pose[1]) + PI / 2.0) * side, pose[1]]

## Where a ship lies in its slot before the last slide onto its pier's face
## (dock units, [middle, facing]): along the slot's middle line, bow to the
## wall, right where it's moored along the pier (see _slot_approach()).
func _berth_off(berth: Array, ship: Ship) -> Array:
	var moored := _berth_pose(berth, ship)
	return [Vector2(float(berth[6]), (moored[0] as Vector2).y), moored[1]]


## A ship's way in from just inside the entrance to its slot (dock units, as
## poses [point, facing]): in through the outer harbour, down the channel on
## the side across from its pier (room to come round), round into the slot's
## mouth bow first, and straight on in along the slot's middle line to where
## it lies before the last slide onto the pier (_berth_off()). Ships in
## reverse: pulling out, they back out along the slot to the channel and turn
## there (see _unberth_plan()).
func _slot_approach(port_id: String, berth: Array, ship: Ship) -> Array:
	var layout := _port_layout(port_id)
	var look: Rect2 = _model_look(ship.model_id)[7]
	var length := look.size.x
	var off := _berth_off(berth, ship)
	var lane: Vector2 = off[0]
	var side := signf(lane.y)
	var along: Vector2 = berth[1]
	var channel: float = layout.channel
	var entry := [Vector2(lane.x, side * (channel / 2.0 - SLOT_ENTRY_CLEAR)), along.angle()]
	var abreast := [Vector2(lane.x + maxf(length * SLOT_TURN_LENGTHS, float(layout.pitch)), -side * channel * CHANNEL_SIDE), PI]
	var inside := _right_side(port_id, layout.inside, true)
	if (abreast[0] as Vector2).x > (layout.inside as Vector2).x - length * 0.5:
		# The first slot by the entrance: no room to come abreast of it first (a
		# jog of a few units sideways and the ship wriggled and crawled round it):
		# straight from inside the entrance round into the slot.
		return [inside, entry, off]
	return [inside, abreast, entry, off]

## A point by a port's entrance (dock units, on the line through the mouth:
## layout.inside or layout.mouth) as a pose on a ship's right-hand side there,
## heading in or out: where _keep_right() puts it at the mouth, so a ship
## comes through the entrance on its own side in a straight line. (From the
## mouth on its right to the middle just inside was a sideways hop the curve
## took in a few pixels: ships jolted left coming in, and right going out.)
func _right_side(port_id: String, point: Vector2, coming_in: bool) -> Array:
	var flip := float(_dock_flips.get(port_id, 1.0))
	var side := float(_port_layout(port_id).width) * KEEP_RIGHT_WIDTHS * (-flip if coming_in else flip)
	return [point + Vector2(0.0, side), PI if coming_in else 0.0]

## How a moored ship gets clear of its slot to head out (dock units): it backs
## straight out stern first along the slot's middle line until its bow is
## clear of the pier tips, in the channel (back), at UNBERTH_REVERSE_SPEED of
## its speed, taking reverse_s (getting going and stopping over ease), then
## turns there on its thrusters to out_angle, towards the entrance. {reverse,
## back, out_angle, reverse_units, reverse_s, ease}.
func _unberth_plan(ship: Ship) -> Dictionary:
	var plan := {reverse = false, back = Vector2.ZERO, out_angle = 0.0, reverse_units = 0.0, reverse_s = 0.0, ease = 0.0}
	var layout := _port_layout(ship.docked_at)
	if ship.berth < 0 or ship.berth >= layout.berths.size():
		return plan
	var berth: Array = layout.berths[ship.berth]
	var rect: Rect2 = _model_look(ship.model_id)[7]
	var off := _berth_off(berth, ship)
	var lane: Vector2 = off[0]
	var side := signf(lane.y)
	var clear := side * maxf(float(layout.channel) / 2.0 - rect.size.x / 2.0 - SLOT_ENTRY_CLEAR, 0.0)
	var units := absf(lane.y - clear)
	plan.reverse = true
	plan.back = Vector2(lane.x, clear)
	plan.out_angle = ((_right_side(ship.docked_at, layout.inside, false)[0] as Vector2) - plan.back).angle()
	plan.reverse_units = units
	plan.ease = minf(rect.size.x * 0.5, units / 3.0)
	var speed := maxf(ship.speed(), MIN_HARBOUR_SPEED) * SHIP_WORLD_ZOOM / 60.0 * UNBERTH_REVERSE_SPEED
	plan.reverse_s = (units + 2.0 * plan.ease) / speed
	return plan

## How a ship lying at its long-term mooring gets back out to its harbour's
## mouth (dock units): it backs straight out of its slip stern first to the
## slip's mouth (back), like a ship out of its berth (see _unberth_plan()),
## turns there on its thrusters to out_angle, then sails its way to the
## mooring (_mooring_way()) the other way round, `poses` to just outside the
## entrance. {} if it isn't at a mooring (or its way isn't known yet).
## {back, out_angle, poses, reverse_units, reverse_s, ease}.
func _mooring_leave_plan(ship: Ship) -> Dictionary:
	var port := ship.docked_at
	if str((_spot_keys.get(ship, ["", ""]) as Array)[1]) != "moor":
		return {}
	var moorings := _moorings(port)
	var at := int(_spot_slots.get(ship, 0))
	if at >= moorings.size():
		return {}
	var way := _mooring_way(port, moorings[at])
	if way.size() < 2:
		return {}
	var middle: Vector2 = moorings[at][0]
	var back: Vector2 = way[-1][0]
	var poses := []
	for k in range(way.size() - 2, -1, -1):
		poses.append([way[k][0], float(way[k][1]) + PI])
	var rect: Rect2 = _model_look(ship.model_id)[7]
	var units := middle.distance_to(back)
	var ease := minf(rect.size.x * 0.5, units / 3.0)
	var speed := maxf(ship.speed(), MIN_HARBOUR_SPEED) * SHIP_WORLD_ZOOM / 60.0 * UNBERTH_REVERSE_SPEED
	return {back = back, out_angle = ((poses[0][0] as Vector2) - back).angle(), poses = poses,
		reverse_units = units, reverse_s = (units + 2.0 * ease) / speed, ease = ease}

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
	var home := []  # A tug: to its moorings by way of its arm's land end (see _tug_home_way()).
	if ship.is_tug():
		home = _tug_home_way(ship.docked_at, _jetty_pose(ship.docked_at, int(_spot_slots.get(ship, 0)), ship)[0]).map(func(pose: Array) -> Array: return _local_to_screen(ship.docked_at, pose))
	elif str((_spot_keys.get(ship, ["", ""]) as Array)[1]) == "moor":
		var moorings := _moorings(ship.docked_at)
		var at := int(_spot_slots.get(ship, 0))
		if at < moorings.size():  # To its pontoon: round the jetty and in to its slip (see _mooring_way()).
			home = _mooring_way(ship.docked_at, moorings[at]).map(func(pose: Array) -> Array: return _local_to_screen(ship.docked_at, pose))
	var poses := [_keep_right(ship.docked_at, _entrance_pose(ship.docked_at, false, true))] + home + [rest]
	var off: Array = _glide_from.get(ship, [])
	if not off.is_empty() and float(off[0]) == since:
		# A tug that's just let go of the ship it brought in, or a ship moving
		# from its anchor to a slip at the moorings (see _retry_moorings()): from there.
		poses = (off[1] as Array).map(func(pose: Array) -> Array: return _local_to_screen(ship.docked_at, pose)) + home + [rest]
	# Turning off for its spot on a turning circle (it came in heading into the
	# harbour, and its spot may be back out past the jetty: never a snap round),
	# and coming round to face the wind on another as it comes up to its spot,
	# slowing to a stop there (see _loosen()).
	var length := (_model_look(ship.model_id)[7] as Rect2).size.x * dock_scale(ship.docked_at)
	var shaped := _loosen(poses, true, true, length * ANCHOR_TURN_LENGTHS)
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

## How long (s of play) a ship's way in through its marina to its slot (or
## out of it) takes at its own speed, slowing only at the end (or getting
## going at the start): GameState's berth_route, the same ways the map draws
## it along (_docked_screen_pose()), in dock units. Tugs working it in: their
## work's time (less the slide GameState adds).
func berth_route_seconds(ship: Ship, coming_in: bool) -> float:
	var t_r := Time.get_ticks_usec()
	_refresh_spots()
	_prof("br.spots", t_r)
	t_r = Time.get_ticks_usec()
	var lead := _assist_lead(ship) if coming_in else null
	_prof("br.lead", t_r)
	if coming_in and lead != null:
		t_r = Time.get_ticks_usec()
		var work := maxf(_tug_work_seconds(ship) - float(Docks.settings().get("slide_s", 1.5)), 0.01)
		_prof("br.tug_work", t_r)
		return work
	var port := ship.docked_at
	if port.is_empty() or ship.berth < 0:
		return 0.0
	var layout := _port_layout(port)
	if ship.berth >= layout.berths.size():
		return 0.0
	var berth: Array = layout.berths[ship.berth]
	var look_rect: Rect2 = _model_look(ship.model_id)[7]
	var mouth_in := _right_side(port, layout.mouth, true)  # (As drawn: on its right-hand side.)
	var mouth_room := ((layout.mouth as Vector2) - (layout.inside as Vector2)).length() * 0.5
	var length := look_rect.size.x
	var speed := maxf(ship.speed(), MIN_HARBOUR_SPEED) * SHIP_WORLD_ZOOM / 60.0
	var t_bl := Time.get_ticks_usec()
	if coming_in:
		var seen: Array = _dock_seen.get(ship, [])
		var gliding := not seen.is_empty() and float(seen[1]) > -INF and (seen.size() < 3 or GameState.play_time < float(seen[2]))
		var t_an := Time.get_ticks_usec()
		var anchor := _anchor_local(ship)
		var weighing := not gliding and anchor.x == anchor.x  # (NAN when it has no spot.)
		var poses := [_screen_to_local(port, _rest_pose(ship)) if weighing else mouth_in]
		_prof("br.anchor", t_an)
		# From its mooring: out of its slip backwards, turned, and its way there backwards.
		var leave := _mooring_leave_plan(ship) if weighing else {}
		_prof("br.leave", t_bl)
		var before := 0.0
		if not leave.is_empty():
			before = float(leave.reverse_s) + UNBERTH_TURN_S
			poses = [[leave.back, float(leave.out_angle)]] + leave.poses + [mouth_in]
		elif weighing and anchor.distance_to(layout.mouth) > maxf(length, mouth_room):
			poses.append(mouth_in)
		poses.append_array(_slot_approach(port, berth, ship))
		var t_bp := Time.get_ticks_usec()
		var path := _pose_path(_loosen(poses, leave.is_empty(), false, length * ANCHOR_TURN_LENGTHS), SLOT_PATH_HANDLE)
		_prof("br.path", t_bp)
		t_bp = Time.get_ticks_usec()
		var seconds := before + _path_times(path, speed, length, length, weighing, true)[-1]
		_prof("br.times", t_bp)
		return seconds
	# Backing out and turning round first (see _unberth_plan()), then out.
	var plan := _unberth_plan(ship)
	var backing := float(plan.reverse_s) + UNBERTH_TURN_S
	var poses := [[plan.back, float(plan.out_angle)], _right_side(port, layout.inside, false), _right_side(port, layout.mouth, false)]
	var anchoring := ship.depart_to.is_empty()
	var anchor := _anchor_local(ship) if anchoring else Vector2(NAN, NAN)
	if anchor.x == anchor.x:
		var moorings := _moorings(port) if str((_spot_keys.get(ship, ["", ""]) as Array)[1]) == "moor" else []
		var at_moor := int(_spot_slots.get(ship, 0))
		if at_moor < moorings.size():
			poses.append_array(_mooring_way(port, moorings[at_moor]))  # (Round the jetty to its slip, as drawn.)
		elif anchor.distance_to(layout.mouth) < maxf(length, mouth_room):
			poses.pop_back()
		poses.append(_screen_to_local(port, _rest_pose(ship)))
	var path := _pose_path(_loosen(poses, false, anchoring and anchor.x == anchor.x, length * ANCHOR_TURN_LENGTHS), SLOT_PATH_HANDLE)
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
	if str((_spot_keys.get(ship, ["", ""]) as Array)[1]) == "moor":
		var moorings := _moorings(port)
		var at := int(_spot_slots[ship])
		return (moorings[at][0] as Vector2) if at < moorings.size() else Vector2(NAN, NAN)
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
	if str(key[1]) == "moor":
		var moorings := _moorings(port)
		if slot < moorings.size():
			var mooring: Array = moorings[slot]
			return _local_to_screen(port, [mooring[0], mooring[1]])
	var half: float = (_model_look(ship.model_id)[7] as Rect2).size.x / 2.0
	var anchor := _anchor_screen_cached(ship, port, str(key[1]), slot)
	var facing := _upwind_angle(port)
	var storm := _storm_strength_at_port(port)
	if storm > 0.0:
		var t := GameState.play_time
		facing += (sin(t * 1.7 + ship.id * 1.3) * 0.7 + sin(t * 3.3 + ship.id * 0.7) * 0.3) * STORM_SWING * storm
	return [anchor - Vector2.from_angle(facing) * half * _ship_scale(), facing]

## Where a tug moors in its port (dock units, [middle, facing]): along the
## inside of the jetty's arms, the two by turns, from TUG_ARM_FROM round
## towards the entrance, bow towards it, TUG_MOOR_GAP between one and the next
## (_marina_layout()'s tugs), by its slot (the first free one, kept till it
## leaves: see _update_spots()); with those all taken, on round towards the
## arms' land ends.
func _jetty_pose(port_id: String, slot: int, tug: Ship) -> Array:
	var layout := _port_layout(port_id)
	var moorings: Array = layout.tugs
	if slot < moorings.size():
		return moorings[slot]
	var look: Rect2 = _model_look(tug.model_id)[7]
	var spare := slot - moorings.size()
	var off := float(layout.radius) - JETTY_WIDTH / 2.0 - look.size.y / 2.0 - TUG_HULL_GAP
	var side := 1.0 if spare % 2 == 0 else -1.0
	var along := minf(TUG_ARM_FROM + (floorf(spare / 2.0) + 0.5) * (look.size.x + TUG_MOOR_GAP) / off, PI / 2.0 - TUG_MOOR_END)
	var at := Vector2.from_angle(along * side) * off
	return [at, along * side - side * PI / 2.0]

## A tug's way to its moorings from just inside the entrance (dock poses): across
## the outer harbour to the land end of its own arm, then along the arm to
## its slot, bow to the entrance, so it never crosses the jetty, the basin's
## corners or the pier tips (and leaves the same way back: _leaving_via()).
func _tug_home_way(port_id: String, mooring: Vector2) -> Array:
	var layout := _port_layout(port_id)
	var radius := float(layout.radius)
	var side := -1.0 if mooring.y < 0.0 else 1.0
	var arm_end := Vector2(radius * TUG_ARM_END.x, side * radius * TUG_ARM_END.y)
	var inside: Vector2 = layout.inside
	return [[inside, (arm_end - inside).angle()], [arm_end, atan2(TUG_ARM_END.y, TUG_ARM_END.x) * side - side * PI / 2.0]]

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
	# The wind turns over minutes: a few times a second is plenty (the noise
	# behind it costs, asked for every ship at anchor otherwise).
	var now := Time.get_ticks_msec()
	if now - _upwind_time >= UPWIND_REFRESH_MS or _upwind_time < 0:
		_upwind_time = now
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
	var retry := GameState.play_time - _moor_retry_at >= MOOR_RETRY_S or GameState.play_time < _moor_retry_at
	if frame == _spots_frame or not _spots_dirty and not retry and _spots_frame >= 0:
		return
	var first := _spots_frame < 0
	_spots_frame = frame
	_spots_dirty = false
	if not _moorings_ready and not _land_cells.is_empty():
		_moorings_ready = true
		for ship: Ship in _spot_slots.keys():
			if not ship.is_tug():
				_free_spot(ship)  # (Given a mooring below if it fits one, and put there without a glide.)
				if _dock_seen.has(ship):
					_dock_seen[ship] = [_dock_seen[ship][0], -INF]
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
			var slot := -1
			var t_s := Time.get_ticks_usec()
			if not ship.is_tug():
				slot = _free_mooring(port, ship)  # Its long-term moorings first (see _lay_moorings()).
				if slot >= 0:
					key = [port, "moor"]
			_prof("sp.mooring", t_s)
			var taken: Dictionary = _spot_tables.get_or_add(key, {})
			if slot < 0:
				t_s = Time.get_ticks_usec()
				slot = _free_anchor(port, key[1], taken)
				_prof("sp.anchor", t_s)
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
	if retry:
		_moor_retry_at = GameState.play_time
		_retry_moorings()

## How often (s of play) ships lying at the anchorages are looked at for a
## free slip at their port's moorings (see _retry_moorings()).
const MOOR_RETRY_S := 2.0
var _moor_retry_at := -INF

## A ship lying at anchor moves to its port's moorings once a slip it fits is
## free and the way to it known (its moorings weren't laid, or their ways not
## yet worked out, when it came in: see _free_mooring()): it sails there from
## its anchor, round the jetty and in to its slip (see _lying_pose()), so
## ships park in port and the anchorage is only the overflow.
func _retry_moorings() -> void:
	for ship: Ship in _spot_slots.keys():
		var key: Array = _spot_keys.get(ship, [])
		if key.size() < 2 or str(key[1]) == "moor" or str(key[1]) == "jetty" or ship.is_tug() or not ship.is_docked():
			continue
		var seen: Array = _dock_seen.get(ship, [])
		if seen.size() > 2 and GameState.play_time < float(seen[2]):
			continue  # (Still on its way to its anchor: let it get there.)
		var port := ship.docked_at
		var slot := _free_mooring(port, ship)
		if slot < 0:
			continue
		var from := _anchor_local(ship)
		_free_spot(ship)
		var taken: Dictionary = _spot_tables.get_or_add([port, "moor"], {})
		taken[slot] = ship
		_spot_slots[ship] = slot
		_spot_keys[ship] = [port, "moor"]
		if is_finite(from.x):
			var way := _mooring_way(port, _moorings(port)[slot])
			var heading := ((way[0][0] as Vector2) - from).angle() if not way.is_empty() else 0.0
			_dock_seen[ship] = [port, GameState.play_time]
			_glide_from[ship] = [GameState.play_time, [[from, heading]]]  # (From its anchor: see _lying_pose().)
		_spots_dirty = true

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
## company's routes, just as laid), or a ship's
## way between this port's harbour mouth and its lanes (_harbour_corridors()),
## passes within its ship's swing of, and ANCHOR_LANE_MARGIN_NM more. Worked out again when
## the drawn lanes change; ships already lying there stay put.
func _anchors_in_lanes(port_id: String, pool: String) -> PackedByteArray:
	var t_k := Time.get_ticks_usec()
	var spots := _anchor_spots(port_id, pool)
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
	var lines: Array[PackedVector2Array] = _lanes_reaching(port_id + pool, near)
	_prof("al.lanes", t_k)
	t_k = Time.get_ticks_usec()
	# And the ships' ways between the harbour mouths and the lanes: this
	# port's, and those of any port near enough for its ways to reach the anchorage.
	var here := GameData.get_port(port_id)
	var here_at := Vector2(float(here.get("lon", 0.0)), float(here.get("lat", 0.0)))
	for other: Dictionary in GameData.ports:
		if other.id == port_id or Geo.distance_nm(here_at, Vector2(float(other.get("lon", 0.0)), float(other.get("lat", 0.0)))) > reach / per_nm + HARBOUR_CORRIDOR_NM:
			continue
		lines.append_array(_harbour_corridors(other.id))
	lines.append_array(_harbour_corridors(port_id))
	_prof("al.corridors", t_k)
	t_k = Time.get_ticks_usec()
	# Tested again only when those lines (or the spots) have changed: a
	# ship's departure changes the fleet's lanes, but seldom any of these.
	var key := [lines.hash(), lines.size(), spots, swing]
	var cached: Array = _anchor_lanes.get(port_id + pool, [])
	if not cached.is_empty() and cached[0] == key:
		_prof("al.hit", t_k)
		return cached[1]
	_count("al.miss")
	if _lane_painter != null and _lane_painter.has_method(&"anchors_in_lines"):
		# (Natively: thousands of stretches against dozens of spots.)
		var found: PackedByteArray = _lane_painter.anchors_in_lines(points, lines, port.x, near, swing)
		_anchor_lanes[port_id + pool] = [key, found]
		_prof("al.test", t_k)
		return found
	var flags := PackedByteArray()
	flags.resize(spots.size())
	for line: PackedVector2Array in lines:
		for i in range(1, line.size()):
			var a := line[i - 1]
			var b := line[i]
			a.x = port.x + wrapf(a.x - port.x, -180.0, 180.0)
			b.x = a.x + (b.x - line[i - 1].x)
			if not near.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				continue
			for k in points.size():
				if flags[k] == 0 and Geometry2D.get_closest_point_to_segment(points[k], a, b).distance_to(points[k]) < swing:
					flags[k] = 1
	_anchor_lanes[port_id + pool] = [key, flags]
	_prof("al.test", t_k)
	return flags

## The drawn lanes (_active_lanes(), each leg once, bent as drawn) whose
## bounds reach a box on the projected map (as they lie or a world round),
## their points: kept per key while the lanes (and their bending) stay.
func _lanes_reaching(key: String, near: Rect2) -> Array[PackedVector2Array]:
	var epoch := [_active_lanes_epoch, _bent_epoch, _bent_lanes.size(), near]
	var cached: Array = _lanes_reaching_cache.get(key, [])
	if not cached.is_empty() and cached[0] == epoch:
		return cached[1]
	var legs := {}
	var lines: Array[PackedVector2Array] = []
	for lane: Array in _active_lanes():
		var leg := "%s-%s" % ([lane[0], lane[1]] if lane[0] < lane[1] else [lane[1], lane[0]])
		if legs.has(leg):
			continue
		legs[leg] = true
		var sea_lane = GameData.lane(lane[0], lane[1])
		if sea_lane == null:
			continue
		var made := _bent_lane(sea_lane, lane[0], lane[1])
		var box: Rect2 = made.get("box", Rect2())
		for shift: float in [-360.0, 0.0, 360.0]:
			if Rect2(box.position + Vector2(shift, 0.0), box.size).intersects(near):
				lines.append(made.points)
				break
	_lanes_reaching_cache[key] = [epoch, lines]
	return lines
var _lanes_reaching_cache := {}

## The ways ships sail between a port's harbour mouth and its lanes (the
## curves in and out drawn with the lanes: see _lane_pieces()), for the lanes
## drawn now that end at the port, as polylines on the ground (projected map
## coordinates): the same curves as on screen (the lane's point reach nm out,
## the harbour mouth on its right-hand side, the way in through the entrance),
## worked out about the port as if the view were on it, so they're known
## wherever it really is. Ships at anchor keep out of them (see
## _anchors_in_lanes()).
## `lanes`: the lanes to work them out for (as _active_lanes() lists them),
## in place of the fleet's (a probe's: every lane out of the port).
func _harbour_corridors(port_id: String, lanes: Array = []) -> Array[PackedVector2Array]:
	# Kept while the lanes ending at the port (and how they're bent), its
	# marina and its facing stay: worked out for every port near each berthing otherwise.
	var layout := _port_layout(port_id)
	var ends := []
	var listed: Array = lanes if not lanes.is_empty() else _active_lanes()
	for lane: Array in listed:
		if lane[0] == port_id or lane[1] == port_id:
			var sea_lane = GameData.lane(lane[0], lane[1])
			var back = GameData.lane(lane[1], lane[0]) if lane[3] else null
			ends.append([lane[0], lane[1], lane[3], _bent_lanes.has(sea_lane), _bent_lanes.has(back)])
	var key := [ends, float(layout.radius), float(layout.width), layout.mouth, _port_sea_angle(port_id), float(_dock_flips.get(port_id, 1.0)), _bent_epoch]
	var kept: Array = _corridor_cache.get(port_id, []) if lanes.is_empty() else []
	if not kept.is_empty() and kept[0] == key:
		return kept[1]
	var out: Array[PackedVector2Array] = []
	var port := GameData.get_port(port_id)
	var origin := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	var squash := maxf(cos(deg_to_rad(origin.y)), 0.05)
	var sea_angle := _port_sea_angle(port_id)
	var flip := float(_dock_flips.get(port_id, 1.0))
	var dock_nm := 60.0 / SHIP_WORLD_ZOOM
	# About the port on the ground as it is on screen with the port in the
	# middle (x east, y south, in nm): the marina's points and facings
	# (_dock_point(), _dock_angle()), the entrance and its right-hand side.
	var dock_point := func(local: Vector2) -> Vector2: return Vector2(local.x, local.y * flip).rotated(sea_angle) * dock_nm
	var dock_angle := func(facing: float) -> float: return sea_angle + facing * flip
	var side := float(layout.width) * KEEP_RIGHT_WIDTHS * dock_nm
	var keep_right := func(pose: Array) -> Array: return [(pose[0] as Vector2) + Vector2.from_angle(float(pose[1]) + PI / 2.0) * side, pose[1]]
	var entrance := func(facing_in: bool, out: float) -> Array: return [dock_point.call((layout.mouth as Vector2) * out), dock_angle.call(PI if facing_in else 0.0)]
	var to_local := func(lon_lat: Vector2) -> Vector2: return Vector2(wrapf(lon_lat.x - origin.x, -180.0, 180.0) * 60.0 * squash, -(lon_lat.y - origin.y) * 60.0)
	var to_ground := func(local: Vector2) -> Vector2: return Geo.project(Vector2(origin.x + local.x / (60.0 * squash), origin.y - local.y / 60.0))
	for lane: Array in listed:
		var ways := [[lane[0], lane[1]]]
		if lane[3]:
			ways.append([lane[1], lane[0]])
		for way: Array in ways:
			var from: String = way[0]
			var to: String = way[1]
			if from != port_id and to != port_id:
				continue
			var arriving := to == port_id
			var sea_lane = GameData.lane(from, to)
			if sea_lane == null:
				continue
			var length: float = sea_lane.length()
			var harbour: Array = keep_right.call(entrance.call(arriving, 1.0))
			# How far out the curve starts (see _lane_reaches()): never faster than at sea.
			var reach := minf(maxf((harbour[0] as Vector2).length() * HARBOUR_REACH, HARBOUR_MIN_NM), length)
			var most := reach * HARBOUR_REACH_GROW
			var curve := PackedVector2Array()
			for k in 3:
				var mile := length - reach if arriving else reach
				var sample: Array = _bent_sample(sea_lane, from, to, clampf(mile, 0.0, length))
				var edge: Vector2 = to_local.call(Geo.unproject(sample[0]))
				var heading := Vector2((sample[1] as Vector2).x, -(sample[1] as Vector2).y).angle()
				var approach: Array = keep_right.call(entrance.call(arriving, HARBOUR_APPROACH_OUT))  # (As _lane_curve() has it.)
				var poses := [[edge, heading], approach, harbour] if arriving else [harbour, approach, [edge, heading]]
				# From behind the jetty: round its end first (see _round_jetty()).
				var in_dock: Vector2 = edge.rotated(-sea_angle) / dock_nm
				in_dock.y *= flip
				var round_poses := _round_jetty(port_id, [in_dock, (heading - sea_angle) * flip], arriving)
				for r in round_poses.size():
					var pose: Array = round_poses[r]
					poses.insert((1 if arriving else 2) + r, [dock_point.call(pose[0]), dock_angle.call(float(pose[1]))])
				curve = _pose_path(poses, HARBOUR_CURVE_HANDLE)
				var curve_nm := _path_length(curve)
				if curve_nm <= reach or reach >= length or reach >= most:
					break
				reach = minf(minf(curve_nm * 1.05, length), most)
			# On in through the entrance itself (see _lane_curve_memo()).
			var gate: Array = keep_right.call(entrance.call(arriving, float(layout.radius) / (layout.mouth as Vector2).x))
			if arriving:
				curve.append(gate[0])
			else:
				curve.insert(0, gate[0])
			var on_ground := PackedVector2Array()
			for p: Vector2 in curve:
				on_ground.append(to_ground.call(p))
			out.append(on_ground)
	if lanes.is_empty():
		_corridor_cache[port_id] = [key, out]
	return out
var _corridor_cache := {}

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
	var lane = ship.leg_lane()
	if lane == null:
		return []
	var length: float = lane.length()
	var reaches := _harbour_reaches(ship, lane, length)
	for i in 2:
		var arriving := i == 0
		var port := ship.to_port if arriving else ship.from_port
		var reach: float = reaches[i]
		var gone := length - ship.traveled_nm if arriving else ship.traveled_nm
		if port.is_empty() or Fisheries.is_ground(port) or reach <= 0.0 or gone >= reach:
			continue  # (A fishing ground's end has no harbour: the boat's on its lane there.)
		# The curve only changes with the view (or the leg): kept till then, and
		# only the ship's place along it found each frame.
		var key := [ship.from_port, ship.to_port, arriving, reach, _view_epoch]
		var kept: Array = _harbour_curves.get(ship, [])
		var curve: Array
		if not kept.is_empty() and kept[0] == key:
			curve = kept[1]
		else:
			curve = _harbour_curve(ship, lane, length, arriving, reach)
			_harbour_curves[ship] = [key, curve]
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
		var way := _mooring_way_out(ship, port)
		if not way.is_empty():
			return _local_to_screen(port, way[0])  # (From its slip's mouth, facing out: see _leaving_via().)
		var spot := _unit_to_screen(last[1])
		if not _is_hidden(spot):
			return [spot, float(last[2])]
	return _keep_right(port, _entrance_pose(port, false, false))

## A ship that lay at a pontoon mooring (its slot noted with its last spot),
## its way out from there (dock poses): the slip's mouth facing out, then its
## mooring way the other way round to just outside the entrance; [] for a
## ship that didn't, or whose way isn't known.
func _mooring_way_out(ship: Ship, port: String) -> Array:
	var last: Array = _last_spot.get(ship, [])
	var at := int(last[4]) if last.size() > 4 else -1
	if at < 0 or not bool(last[3]):
		return []
	var moorings := _moorings(port)
	if at >= moorings.size():
		return []
	var way := _mooring_way(port, moorings[at])
	if way.size() < 2:
		return []
	var back: Vector2 = way[-1][0]
	var out := [[back, ((way[-2][0] as Vector2) - back).angle()]]
	for k in range(way.size() - 2, -1, -1):
		out.append([way[k][0], float(way[k][1]) + PI])
	return out

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
	if not _left_from_anchor(ship) or not _mooring_way_out(ship, ship.from_port).is_empty():
		return 0.0  # (From a mooring it's already facing its way out.)
	return (_model_look(ship.model_id)[7] as Rect2).size.x * _ship_scale() * ANCHOR_TURN_LENGTHS

## The poses a ship sailing from port goes through between where it lay and
## its lane: for a tug from its moorings on the jetty's arm, along the arm to
## just inside the entrance, then out through its marina's mouth (on its
## right-hand side, heading out); for a ship from its pontoon mooring, out of
## its slip and its way there the other way round (see _mooring_way()), then
## out through the mouth (a fishing boat setting out from the moorings on its
## next trip, an idle ship given a route: straight from its slip, it would
## cut across the marina).
func _leaving_via(ship: Ship) -> Array:
	if not _left_from_anchor(ship) or ship.from_port.is_empty():
		return []
	var port := ship.from_port
	if ship.is_tug():
		return [_local_to_screen(port, _right_side(port, _port_layout(port).inside, false)), _keep_right(port, _entrance_pose(port, false, false))]
	var way := _mooring_way_out(ship, port)
	if way.is_empty():
		return []
	var out := []
	for pose: Array in way.slice(1):  # (The slip's mouth is where it sets off from: _harbour_end().)
		out.append(_local_to_screen(port, pose))
	out.append(_keep_right(port, _entrance_pose(port, false, false)))
	return out

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
	var sample: Array = _bent_sample(lane, from_port, to_port, clampf(mile, 0.0, length))
	var edge := world_to_screen(sample[0])
	if _is_hidden(edge) or _is_hidden(harbour[0]):
		return []
	var on_lane := [edge, _heading_angle(sample[1], sample[0])]
	# From behind the jetty (a lane that comes in along the coast): round its end first.
	var port := to_port if arriving else from_port
	var round_poses := []
	for pose: Array in _round_jetty(port, _screen_to_local(port, on_lane), arriving):
		round_poses.append(_local_to_screen(port, pose))
	via = round_poses + via if arriving else via + round_poses
	# Lined up with the mouth from HARBOUR_APPROACH_OUT mouths out before the
	# last stretch in (and out to there before turning for the lane): a lane
	# coming in from the side made the curve hook round at the mouth.
	var approach := _keep_right(port, _entrance_pose(port, false, arriving, HARBOUR_APPROACH_OUT))
	var poses := [on_lane] + via + [approach, harbour] if arriving else [harbour, approach] + via + [on_lane]
	var shaped := _loosen(poses, turn > 0.0, false, turn)
	return [_pose_path(shaped, HARBOUR_CURVE_HANDLE), poses, shaped]

## Coming in to a port's harbour from behind or beside its jetty (a lane
## that comes in along the coast), or leaving that way: the poses to go by,
## round the jetty's end, out past it on the lane's side (dock units, [point,
## facing] each, in sailing order), or [] when the lane's out in front of the
## entrance already or a plain curve to the mouth clears the jetty anyway.
## lane_pose: where the ship leaves (or joins) its lane, [point, facing] in
## dock units. From behind the marina (level with the jetty's end or nearer)
## it first goes along past the marina's wall; from further along the coast
## it makes straight for the jetty's end (by the wall it would have to turn
## out to sea and back again, a loop: Shanghai's lanes from the north).
func _round_jetty(port_id: String, lane_pose: Array, arriving: bool) -> Array:
	var layout := _port_layout(port_id)
	var radius := float(layout.radius)
	var lane_local: Vector2 = lane_pose[0]
	if lane_local.x >= radius * JETTY_ROUND_FROM or _clears_jetty(layout, lane_pose, arriving):
		return []
	var side := 1.0 if lane_local.y >= 0.0 else -1.0
	var corner := Vector2(radius * JETTY_ROUND, side * radius * JETTY_ROUND)
	var mouth: Vector2 = layout.mouth
	var way := mouth - corner if arriving else corner - mouth
	var poses := [[corner, way.angle()]]
	if absf(lane_local.y) < radius * JETTY_ROUND:
		poses.push_front([Vector2(-radius * 0.3, side * radius * JETTY_ROUND), 0.0 if arriving else PI])
	if not arriving:
		poses.reverse()
	return poses

## True if the plain curve between a lane's pose (dock units) and a marina's
## mouth keeps outside its jetty (JETTY_CLEAR of its radius) and off the coast
## behind it (see _round_jetty()).
static func _clears_jetty(layout: Dictionary, lane_pose: Array, arriving: bool) -> bool:
	var radius := float(layout.radius)
	var mouth := [layout.mouth, PI if arriving else 0.0]
	for p: Vector2 in _pose_path([lane_pose, mouth] if arriving else [mouth, lane_pose], HARBOUR_CURVE_HANDLE):
		if p.length() < radius * JETTY_CLEAR or p.x < 0.0:
			return false
	return true

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
		# give it as much lane as it's long (up to HARBOUR_REACH_GROW times: round
		# the jetty from behind, a curve from further out is longer again).
		var most := reach * HARBOUR_REACH_GROW
		var curve := []
		for k in 3:
			curve = _lane_curve(lane, from_port, to_port, length, arriving, minf(reach, length), harbour, 0.0 if arriving else turn, [] if arriving else via)
			if curve.is_empty():
				break
			var curve_nm := _path_length(curve[0]) / px_per_nm
			if curve_nm <= reach or reach >= most:
				break
			reach = minf(curve_nm * 1.05, most)
		# A curve over the land (cutting a corner of the coast): shortened,
		# so it keeps to its lane (which is off the land) longer.
		for k in 4:
			if curve.is_empty() or reach <= HARBOUR_MIN_NM or not _curve_on_land(curve[0], port):
				break
			reach = maxf(reach * 0.6, HARBOUR_MIN_NM)
			curve = _lane_curve(lane, from_port, to_port, length, arriving, minf(reach, length), harbour, 0.0 if arriving else turn, [] if arriving else via)
		reaches[i] = reach
	# A short leg: the two ends share it.
	if reaches[0] + reaches[1] > length and reaches[0] + reaches[1] > 0.0:
		var fit := length / (reaches[0] + reaches[1])
		reaches[0] *= fit
		reaches[1] *= fit
	return [reaches, shown]

## True if a harbour curve (screen points) runs over the land as drawn, outside
## its port's marina (whose basin and harbour are painted over whatever's there).
const CURVE_LAND_STEP_PX := 12.0
func _curve_on_land(path: PackedVector2Array, port: String) -> bool:
	var layout := _port_layout(port)
	for i in range(1, path.size()):
		var a := path[i - 1]
		var b := path[i]
		var pieces := maxi(ceili(a.distance_to(b) / CURVE_LAND_STEP_PX), 1)
		for k in pieces + 1:
			var at := a.lerp(b, float(k) / pieces)
			if _marina_ground(layout, (_screen_to_local(port, [at, 0.0]) as Array)[0]):
				continue
			if _on_land(_screen_lon_lat(at)):
				return true
	return false

func _draw_overlay() -> void:
	_canvas = _overlay
	_frames_drawn += 1
	_lit_ships.clear()
	_draw_price_rings()
	if show_ships:
		var t0 := Time.get_ticks_usec()
		_draw_ships()
		_prof("overlay.ships", t0)
		t0 = Time.get_ticks_usec()
		_draw_birds()
		_prof("overlay.birds", t0)
		t0 = Time.get_ticks_usec()
		_draw_divine()
		_draw_hub_alerts()
		_prof("overlay.rest", t0)
	if _night_shown:
		_lights_layer.queue_redraw()  # (The ships' lights are drawn where the ships were drawn this frame: never a frame behind as the map drags.)

## Port labels, the HQ's and hubs' first and then in rank order, skipping any
## that would overlap one already placed, after `labels` (those of the ports
## with price boxes, already placed).
## Returns [port id, label rect] pairs.
func _place_port_labels(placed: Array[Rect2], labels := []) -> Array:
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
	var named := {}
	for label: Array in labels:
		named[label[0]] = true
	var bounds := Rect2(Vector2.ZERO, size)
	var near := bounds.grow(LABEL_REACH_PX)
	for port: Dictionary in _ranked_ports:
		if not near_ids.has(port.id) or named.has(port.id):
			continue  # (Cheapest first: most are well off screen.)
		if not selectable_ports.is_empty() and not selectable_ports.has(port.id):
			continue  # Picking a port: only the choices are named.
		var pos := port_screen_position(port.id)
		if not near.has_point(pos):
			continue  # (Cheapest first: most are well off screen.)
		var rect := _port_label_rect(font, port)
		if not bounds.intersects(rect) or _overlaps(rect, placed):
			continue
		placed.append(rect.grow(LABEL_PADDING))
		labels.append([port.id, rect])
	return labels

## Where a port's name goes: centered under its dot.
func _port_label_rect(_font: Font, port: Dictionary) -> Rect2:
	var text_size: Vector2 = _port_text_sizes.get(port.id, Vector2.INF)  # (Kept by port: measured, or even looked up by text, costs.)
	if text_size == Vector2.INF:
		text_size = _label_size(_port_font(), port.name, PORT_FONT_SIZE)
		_port_text_sizes[port.id] = text_size
	return Rect2(port_screen_position(port.id) + Vector2(-text_size.x / 2.0, _port_radius(port.id) + 2.0), text_size)

## Something about the price boxes changed: work them out and place them again.
func _prices_changed() -> void:
	_price_rows.clear()
	_price_time = -INF
	_labels_key = []
	_static_layer.queue_redraw()

## Price boxes (see price_line) over the ports in view, each with its port's
## name under it, placed before the other names: the origin's first, then the
## best profits from it (ports nothing pays at get none), or with no origin the
## ports whose prices are furthest from the average; skipping any that would
## overlap one placed already. Not for locked, dimmed (out of range) or, while
## picking a port, unpickable ports, nor ones too small for price_ship.
## Returns [[port id, box rect, rows], ...] and those ports' [port id, label rect] pairs.
func _place_price_boxes(placed: Array[Rect2]) -> Array:
	var boxes := []
	var labels := []
	if price_line.is_empty():
		return [boxes, labels]
	var font := get_theme_default_font()
	var bounds := Rect2(Vector2.ZERO, size)
	var candidates := []  # [score, port]
	for i in _ports_near_view():
		var port: Dictionary = GameData.ports[i]
		if _port_locked(port.id) or dimmed_ports.has(port.id) or (not selectable_ports.is_empty() and not selectable_ports.has(port.id)):
			continue
		if price_ship != null and not price_ship.fits_port(port.id):
			continue  # (Too small for it to dock.)
		if not bounds.has_point(port_screen_position(port.id)):
			continue
		var box: Variant = _price_box(port.id, font)
		if box != null:
			candidates.append([INF if port.id == price_origin else float(box.score), port])
	candidates.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for candidate: Array in candidates:
		var port: Dictionary = candidate[1]
		var box: Dictionary = _price_rows[port.id]
		var box_size: Vector2 = box.size
		var rect := Rect2(port_screen_position(port.id) + Vector2(-box_size.x / 2.0, -_port_radius(port.id) - 3.0 - box_size.y), box_size)
		var label := _port_label_rect(font, port)
		if not bounds.encloses(rect) or _overlaps(rect, placed) or _overlaps(label, placed):
			continue
		placed.append(rect.grow(LABEL_PADDING))
		placed.append(label.grow(LABEL_PADDING))
		boxes.append([port.id, rect, box.rows, rect.position - port_screen_position(port.id)])
		labels.append([port.id, label])
	return [boxes, labels]

## A port's price box for price_line, worked out once a PRICE_REFRESH_S:
## {rows: [[name, figure, color, figure width], ...], size, score (how much it
## matters, for placing)}, or null if it gets none (nothing pays there from
## the origin). The origin's own box is headed "Buy here".
func _price_box(port_id: String, font: Font) -> Variant:
	if _price_rows.has(port_id):
		return _price_rows[port_id]
	var of: Company = GameState.owner_of(price_ship) if price_ship != null else null
	var model_id := price_ship.model_id if price_ship != null else ""
	var rows := []
	var score := -INF
	var from := price_origin
	if from == port_id:
		rows.append(["Buy here", "", Color.WHITE, 0.0])
	for commodity_id: String in _price_cargo():
		var figure: String
		var color: Color
		if from.is_empty() or from == port_id:
			# Its price: what the port pays for it, or at the origin what it costs to buy there.
			var price: float = GameState.market.sell_price(port_id, commodity_id) if from.is_empty() else GameState.company_buy_price(port_id, commodity_id, of)
			var t := clampf(log(price / GameData.world_price(commodity_id)) / log(2.0), -1.0, 1.0)
			figure = Fmt.money(roundi(price))
			color = Color.WHITE.lerp(PRICE_CHEAP if t < 0.0 else PRICE_DEAR, absf(t))
			score = maxf(score, absf(t))
		else:
			var buy := GameState.company_buy_price(from, commodity_id, of)
			var profit: float = GameState.market.unit_profit(commodity_id, from, port_id, model_id, of)
			var share := profit / buy
			if price_ship != null:  # Per load of this ship, less the port fee.
				var quantity := floori(price_ship.capacity() * (1.0 - GameData.leg_lightening(from, port_id, price_ship.model())))
				var margin := (GameState.company_sell_price(port_id, commodity_id, of) - buy) * quantity
				profit = profit * quantity - GameState.port_fee(port_id, margin, of)
			figure = ("+" if profit > 0.0 else "") + Fmt.money_short(roundi(profit))
			color = PRICE_LOSS if profit <= 0.0 else Color.WHITE.lerp(PRICE_PROFIT, clampf(0.35 + share / PRICE_GOOD_MARGIN, 0.0, 1.0))
			if profit > 0.0:
				score = maxf(score, share)
		var name: String = GameData.commodity(commodity_id).get("name", commodity_id)
		rows.append([name, figure, color, font.get_string_size(figure, HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_FONT_SIZE).x])
	if score == -INF:
		_price_rows[port_id] = null
		return null
	var name_width := 0.0
	var figure_width := 0.0
	for row: Array in rows:
		name_width = maxf(name_width, _label_size(font, row[0], PRICE_FONT_SIZE).x)
		figure_width = maxf(figure_width, row[3])
	var box := {rows = rows, score = score,
		size = Vector2(name_width + PRICE_GAP + figure_width, font.get_height(PRICE_FONT_SIZE) * rows.size()) + PRICE_PADDING * 2.0}
	_price_rows[port_id] = box
	return box

## The commodities price_line's boxes list: price_ship's cargo, or all its line carries.
func _price_cargo() -> Array:
	if price_ship != null:
		return price_ship.model().get("cargo", [])
	var cargo := []
	for commodity: Dictionary in GameData.commodities:
		for model: Dictionary in GameData.ship_models:
			if model.get("category", "") == price_line and model.get("cargo", []).has(commodity.id):
				cargo.append(commodity.id)
				break
	return cargo

## The placed price boxes (see _place_price_boxes()): a dark rounded panel
## edged in the line's color, each commodity's name on the left and its figure,
## in its color, on the right.
func _draw_price_boxes() -> void:
	if _price_boxes.is_empty():
		return
	var font := get_theme_default_font()
	var style := StyleBoxFlat.new()
	style.bg_color = PRICE_BACKGROUND
	style.border_color = GameData.category_color(price_line)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	var row_height := font.get_height(PRICE_FONT_SIZE)
	var ascent := font.get_ascent(PRICE_FONT_SIZE)
	var name_color := _color(&"label")
	for box: Array in _price_boxes:
		var rect: Rect2 = box[1]
		_canvas.draw_style_box(style, rect)
		var y := rect.position.y + PRICE_PADDING.y + ascent
		for row: Array in box[2]:
			_canvas.draw_string(font, Vector2(rect.position.x + PRICE_PADDING.x, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_FONT_SIZE, name_color)
			_canvas.draw_string(font, Vector2(rect.end.x - PRICE_PADDING.x - float(row[3]), y), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, PRICE_FONT_SIZE, row[2])
			y += row_height

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

## Country names that fit around the port labels already placed: [text, rect, index].
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
		labels.append([text, rect, i])
	return labels

## Named geography labels that fit around the ones already placed, most
## important kind first (FEATURE_PRIORITY): [index, rect, offset from its spot]. Each shows
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
				labels.append([i, rect, rect.position - center])
				break
	return labels

func _draw_feature_labels() -> void:
	var data := GameData.world_map
	var bounds := Rect2(Vector2.ZERO, size)
	for label: Array in _feature_labels:
		var kind := data.feature_label_kinds[label[0]]
		var style: Array = FEATURE_STYLES[kind]
		var font := _feature_font(kind)
		var rect: Rect2 = label[1]
		var text := _feature_text(label[0])
		if not bounds.intersects(rect) or _label_in_atlas(font, style[0], text):
			continue  # (Off screen since it was placed, or drawn from the atlas: see _draw_label_layer().)
		var baseline := rect.position + Vector2(0, font.get_ascent(style[0]))
		# Pale sea names get a dark edge, so they read over shallow (light) water too.
		if OUTLINED_FEATURES.has(kind):
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
	var bounds := Rect2(Vector2.ZERO, size)
	for label: Array in _country_labels:
		var rect: Rect2 = label[1]
		if not bounds.intersects(rect) or _label_in_atlas(font, COUNTRY_FONT_SIZE, label[0]):
			continue  # (Off screen since it was placed, or drawn from the atlas: see _draw_label_layer().)
		_canvas.draw_string(font, rect.position + Vector2(0, ascent), label[0], HORIZONTAL_ALIGNMENT_LEFT, -1, COUNTRY_FONT_SIZE, color)

## True if a label's rect overlaps any placed so far. The placed rects are
## sorted into PLACED_CELL_PX cells of the screen as they come (the array is
## only ever appended to while one round of placing runs), so each test looks
## at a few cells, not every rect: hundreds of labels a frame while the map
## drags were a hundred thousand rect tests.
const PLACED_CELL_PX := 96.0
var _placed_cells := {}  # Vector2i cell -> PackedInt32Array of indices into the placed array.
var _placed_for: Array[Rect2] = []  # The array the cells were built for.
var _placed_indexed := 0

func _overlaps(rect: Rect2, placed: Array[Rect2]) -> bool:
	if not is_same(placed, _placed_for) or placed.size() < _placed_indexed:
		_placed_for = placed
		_placed_cells.clear()
		_placed_indexed = 0
	while _placed_indexed < placed.size():
		var other := placed[_placed_indexed]
		for cx in range(floori(other.position.x / PLACED_CELL_PX), floori(other.end.x / PLACED_CELL_PX) + 1):
			for cy in range(floori(other.position.y / PLACED_CELL_PX), floori(other.end.y / PLACED_CELL_PX) + 1):
				var cell := Vector2i(cx, cy)
				if not _placed_cells.has(cell):
					_placed_cells[cell] = PackedInt32Array()
				_placed_cells[cell].append(_placed_indexed)
		_placed_indexed += 1
	for cx in range(floori(rect.position.x / PLACED_CELL_PX), floori(rect.end.x / PLACED_CELL_PX) + 1):
		for cy in range(floori(rect.position.y / PLACED_CELL_PX), floori(rect.end.y / PLACED_CELL_PX) + 1):
			for index: int in _placed_cells.get(Vector2i(cx, cy), PackedInt32Array()):
				if rect.intersects(placed[index]):
					return true
	return false

## Coloring the ports by a price (price_commodity): a port grown into its
## marina has no dot to color, so a ring in its color goes round the marina
## (just outside its jetty) instead.
const PRICE_RING_WIDTH := 4.0
func _draw_price_rings() -> void:
	if price_commodity.is_empty() or not _any_marina_shown():
		return
	var area := Rect2(Vector2.ZERO, size)
	for index in _ports_near_view():
		var port_id := str((GameData.ports[index] as Dictionary).id)
		if not _marina_shown(port_id) or _port_locked(port_id):
			continue
		var at := port_screen_position(port_id)
		var radius := (float(_port_layout(port_id).radius) + JETTY_WIDTH * 2.0) * _ship_scale()
		if _is_hidden(at) or not area.grow(radius).has_point(at):
			continue
		_canvas.draw_arc(at, radius, 0.0, TAU, 64, Color(_price_color(port_id), 0.85), PRICE_RING_WIDTH, true)

## A port's color for price_commodity (see PORT_PRICE_CHEAP).
func _price_color(port_id: String) -> Color:
	var ratio := GameState.market.sell_price(port_id, price_commodity) / maxf(GameData.world_price(price_commodity), 0.001)
	var t := clampf(log(maxf(ratio, 0.001)) / log(PORT_PRICE_SPAN), -1.0, 1.0)
	return Color.WHITE.lerp(PORT_PRICE_CHEAP if t < 0.0 else PORT_PRICE_DEAR, absf(t))

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
		var port_fill := fill
		if selectable_ports.get(port_id) is Color:
			port_fill = selectable_ports[port_id]
		elif not price_commodity.is_empty():
			port_fill = _price_color(port_id)
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
	if _port_painter == null and ClassDB.class_exists(&"PortPainter"):
		_port_painter = ClassDB.instantiate(&"PortPainter")
		var units := PackedVector3Array()
		for port: Dictionary in GameData.ports:
			units.append(_unit(GameData.port_position(port.id)))
		_port_painter.set_units(units)
	if _port_painter != null:
		# The others natively (PortPainter: the same dots), their looks kept till they change.
		_update_port_styles(hub_ports, fill, dimmed, locked_fill)
		_port_painter.draw(_canvas.get_canvas_item(), _ports_near_view(), {right = _right, up = _up, toward = _toward,
			radius = _radius(), middle = size / 2.0, area = visible_area, outline = outline, locked_fill = locked_fill, dimmed = dimmed,
			locked_radius = PORT_RADIUS_MIN, shine = SHINE_RINGS, selected = GameData.ports.find(GameData.get_port(selected_port)) if not selected_port.is_empty() else -1,
			selected_ring = SELECTED_RING, docks = docks_shown() and _any_marina_shown(), scale = _ship_scale(), over_dot_px = MARINA_OVER_DOT_PX})
	else:
		for i in _ports_near_view():
			var port: Dictionary = GameData.ports[i]
			if not hub_ports.has(port.id):
				draw_port.call(port.id)
	# The HQ and hubs go on top of the other ports, each with a ring in its
	# company's color (heavier for an HQ); companies sharing a port ring it in
	# turn. Not once its marina shows: that has its quay (and an HQ building).
	for port_id: String in hub_ports:
		draw_port.call(port_id)
		if _marina_shown(port_id):
			continue
		var radius := _port_radius(port_id) + 1.0
		for entry: Array in hub_ports[port_id]:
			var width := HQ_RING_WIDTH if entry[0].is_hq else HUB_RING_WIDTH
			_canvas.draw_arc(port_screen_position(port_id), radius + width / 2.0, 0.0, TAU, clampi(int(radius), 32, 128), entry[1], width, true)
			radius += width
	var bounds := Rect2(Vector2.ZERO, size)
	for label: Array in labels:
		var rect: Rect2 = label[1]
		var text: String = GameData.port_name(label[0])
		var port_font := _port_font()
		if not bounds.intersects(rect) or _label_in_atlas(port_font, PORT_FONT_SIZE, text):
			continue  # (Off screen since it was placed, or drawn from the atlas: see _draw_label_layer().)
		var baseline := rect.position + Vector2(0, port_font.get_ascent(PORT_FONT_SIZE))
		var color := dimmed if dimmed_ports.has(label[0]) or _port_locked(label[0]) else label_color  # (Locked regions' ports named, but dimmed.)
		_canvas.draw_string(port_font, baseline + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, shadow)
		_canvas.draw_string(port_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, PORT_FONT_SIZE, color)

## Works out every port's look for the native dots (PortPainter) again when
## anything that sets it has changed: a port picked, dimmed or shining, the regions open, the
## hubs, the ports' sizes, the colors. Dragging the map doesn't change them.
func _update_port_styles(hub_ports: Dictionary, fill: Color, dimmed: Color, locked_fill: Color) -> void:
	var key := [selectable_ports, dimmed_ports, shining_ports, GameState.regions.duplicate(), hub_ports.keys(), fill, dimmed, locked_fill, price_commodity,
		-1 if price_commodity.is_empty() else floori(Time.get_ticks_msec() / (PRICE_REFRESH_S * 1000.0))]  # (Colored by price: looked at again as prices drift.)
	var now := Time.get_ticks_msec()
	# (Ports grow a little all the time: their dots' sizes are looked at again
	# as often as the ports are drawn when the view's still, to a tenth of a
	# px; the looks are worked out again only when one's changed.)
	var seen := _port_styles_radii
	if key != _port_styles_key or now - _port_styles_time >= STATIC_REFRESH_S * 1000.0:
		_port_styles_time = now
		seen = PackedFloat32Array()
		seen.resize(GameData.ports.size())
		for i in GameData.ports.size():
			seen[i] = snappedf(_port_radius(GameData.ports[i].id), 0.25)
	if key == _port_styles_key and seen == _port_styles_radii:
		return
	_port_styles_key = key
	_port_styles_radii = seen
	var count := GameData.ports.size()
	var radii := PackedFloat32Array()
	var layout_radii := PackedFloat32Array()
	var fills := PackedColorArray()
	var flags := PackedByteArray()
	radii.resize(count)
	layout_radii.resize(count)
	fills.resize(count)
	flags.resize(count)
	# (A marina's radius follows its port's size band, and the hubs: worked out
	# again only when one of those has changed; a layout is a lot to work out, and there are hundreds.)
	var same_hubs: bool = key.size() == _port_styles_key_hubs.size() and key[4] == _port_styles_key_hubs[4] and key[0] == _port_styles_key_hubs[0]
	if _port_bands.size() != count or _port_layout_radii.size() != count or not same_hubs:
		_port_bands.resize(count)
		_port_bands.fill("")
		_port_layout_radii.resize(count)
	_port_styles_key_hubs = key
	for i in count:
		var port_id: String = GameData.ports[i].id
		radii[i] = _port_radius(port_id)
		var band := GameState.port_sizes.band(port_id)
		if band != _port_bands[i]:
			_port_bands[i] = band
			_port_layout_radii[i] = float(_port_layout(port_id).radius)
		layout_radii[i] = _port_layout_radii[i]
		var port_fill := fill
		if selectable_ports.get(port_id) is Color:
			port_fill = selectable_ports[port_id]
		elif not price_commodity.is_empty():
			port_fill = _price_color(port_id)
		fills[i] = port_fill
		flags[i] = (1 if _port_locked(port_id) else 0) | (2 if shining_ports.has(port_id) else 0) | (4 if hub_ports.has(port_id) else 0) | (8 if dimmed_ports.has(port_id) else 0)
	_port_painter.set_styles(radii, layout_radii, fills, flags)


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
## drawn once, in the first one's color (see ORE_LANE_WHITEN). Other
## companies' lanes (other players', the AI rivals') go underneath, each
## company's once in its own color (see OTHER_LANE_ALPHA), unless Settings'
## own routes only is on.
func _draw_active_lanes() -> void:
	var lanes := _active_lanes()
	# Only this player's own with Settings' own routes only (the others still
	# keep anchored ships off their lanes: see _anchors_in_lanes()).
	var own_only: bool = Settings.own_routes_only
	if own_only:
		lanes = _own_lanes_cache
	if _lane_painter == null and ClassDB.class_exists(&"LanePainter"):
		_lane_painter = ClassDB.instantiate(&"LanePainter")
		_lane_painter.setup({chunk = LANE_CHUNK, min_px = ACTIVE_LANE_MIN_PX, hidden = HIDDEN})
		_lane_painter.set_providers(_lane_chunks, _lane_ends)
	if _lane_painter != null:
		var epoch := _active_lanes_epoch * 2 + (1 if own_only else 0)
		if lane_mesh and _lane_painter.has_method(&"build_mitred_mesh"):  # (Not in an older library: its mesh doesn't suit scripts/ui/lanes.gdshader.)
			# The lanes with neither port's marina showing (no harbour curves, which
			# are worked out on screen) as the mesh on the globe; the rest, few, by
			# the native pass each frame. Which show depends on the zoom alone, so
			# the split (and the mesh) holds while the map drags.
			# (Zooming, the split made last stands till the zoom settles: marinas
			# come and go at every zoom step, and the mesh is a few ms to build.)
			if _zooming() and _lane_mesh != null and not _lane_mesh_epoch.is_empty() and _lane_mesh_epoch[0] == epoch:
				_lane_mesh_node.visible = true
				if _lane_mesh_curved.is_empty():
					return
				lanes = _lane_mesh_curved
			else:
				var curved := []
				var straight := []
				var curves := docks_shown() and _any_marina_shown()
				for lane: Array in lanes:
					if curves and (_marina_shown(lane[0]) or _marina_shown(lane[1])):
						curved.append(lane)
					else:
						straight.append(lane)
				_lane_mesh_curved = curved
				_show_lane_mesh(straight, [epoch, curved.hash()])
				if curved.is_empty():
					return
				lanes = curved
		else:
			_lane_mesh_node.visible = false
		# (All of them natively, as one batch of triangles: a big fleet's are
		# drawn again every frame the map's dragged. Harbour curves only while
		# marinas can show, for lanes with a port on or near the screen: see
		# _lane_curve_ends().)
		_lane_painter.draw(_canvas.get_canvas_item(), lanes, {toward = _toward, right = _right, up = _up, radius = _radius(), middle = size / 2.0,
			view_angle = asin(minf((size.length() / 2.0 + 8.0) / _radius(), 1.0)), width = ACTIVE_LANE_WIDTH, epoch = epoch,
			curves = docks_shown() and _any_marina_shown(), near = Rect2(Vector2.ZERO, size).grow(size.length() / 2.0)})
		return
	for lane: Array in lanes:
		_draw_lane(lane[0], lane[1], lane[2], false, ACTIVE_LANE_WIDTH, lane[3])

## This player's own lanes of those (see _active_lanes()).
var _own_lanes_cache := []

## The fleet's lanes as one mesh on the globe (LanePainter.build_mesh(),
## drawn through scripts/ui/lanes.gdshader on a node of their own just under
## the static layer) while no marina can show (the harbour curves are worked
## out on screen, so the native pass draws the lanes then): the globe's turn
## costs them a few uniforms, not a pass over every lane each frame. Built
## again when the lanes change (their epoch), when they're bent afresh, and
## LANE_MESH_RETRY_FRAMES after a build that left out a lane not yet bent.
const LANES_SHADER := preload("res://scripts/ui/lanes.gdshader")
static var lane_mesh := true  # (Off: the native pass draws them at every zoom; for comparing.)
const LANE_MESH_STEP_NM := 150.0  # A stretch longer than this is cut into pieces along the way the ships sail (25 px at zoom 10).
const LANE_MESH_RETRY_FRAMES := 30
var _lane_mesh_node := Node2D.new()
var _lane_mesh: ArrayMesh = null
var _lane_mesh_epoch := []  # ([the lanes' epoch, a hash of the lanes drawn by the pass instead].)
var _lane_mesh_curved := []  # The lanes the native pass draws (harbour curves), as split last.
var _lane_mesh_retry := -1
var _lane_material := ShaderMaterial.new()

func _show_lane_mesh(lanes: Array, epoch: Array) -> void:
	var frame := Engine.get_process_frames()
	if _lane_mesh == null or epoch != _lane_mesh_epoch or (_lane_mesh_retry >= 0 and frame >= _lane_mesh_retry):
		var t0 := Time.get_ticks_usec()
		var built: Dictionary = _lane_painter.build_mitred_mesh(lanes, LANE_MESH_STEP_NM)
		var mesh := ArrayMesh.new()
		if not (built.indices as PackedInt32Array).is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = built.points
			arrays[Mesh.ARRAY_TEX_UV] = built.uvs
			arrays[Mesh.ARRAY_COLOR] = built.colors
			arrays[Mesh.ARRAY_INDEX] = built.indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
		_lane_mesh = mesh
		_lane_mesh_epoch = epoch
		_lane_mesh_retry = -1 if bool(built.complete) else frame + LANE_MESH_RETRY_FRAMES
		_lane_mesh_node.queue_redraw()
		_prof("lanes.mesh", t0)
	_lane_mesh_node.visible = true

## The lanes _draw_active_lanes() draws: [from, to, color, sailed both ways],
## other players' first. Kept for half a STATIC_REFRESH_S (so each redraw while
## the view's still works them out afresh), not every frame it's dragged.
func _active_lanes() -> Array:
	var now := Time.get_ticks_msec()
	if now - _active_lanes_time < ACTIVE_LANES_REFRESH_S * 1000.0 and _active_lanes_time >= 0:
		return _active_lanes_cache
	_active_lanes_time = now
	var t_a := Time.get_ticks_usec()
	_lanes_warm = false  # (New legs may want bending: see _warm_lanes().)
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
	_own_lanes_cache = lanes.values()  # (Drawn alone with Settings' own routes only: see _draw_active_lanes().)
	var fresh: Array = others.values() + lanes.values()
	if fresh != _active_lanes_cache:
		_active_lanes_cache = fresh
		_active_lanes_epoch += 1  # (The native pass resolves the lanes again: see LanePainter.)
	_prof("lanes.active", t_a)
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
	if both_ways and _lane_curve_ends(from_port, to_port) != [false, false]:  # (Without a marina showing, the way back has no curves.)
		var back = GameData.lane(to_port, from_port)
		if back != null:
			var back_pieces := _lane_pieces(back, to_port, from_port)
			_draw_line_runs(back_pieces[0], color, dashed, width)
			_draw_line_runs(back_pieces[2], color, dashed, width)

## A bent lane's (see _bent_lane()) points on the sphere, and its chunks (see
## _chunk_caps()), worked out once.
func _bent_units(sea_lane, bent: Dictionary) -> PackedVector3Array:
	var units: PackedVector3Array = _lane_units.get(sea_lane, PackedVector3Array())
	if units.is_empty():
		for p: Vector2 in bent.points:
			units.append(_unit(p))
		_lane_units[sea_lane] = units
		_lane_caps[sea_lane] = _chunk_caps(units)
	return units

## Whether a ship `mile` along a lane could be in view: the lane's chunk
## there (see _chunk_caps()) is near enough the view for a ship on it (eased
## into its harbour, or in a canal's other channel) to show. Zoomed in, most of
## a big fleet isn't: skipped before working out just where each one is.
func _on_lane_in_view(sea_lane, from_port: String, to_port: String, mile: float) -> bool:
	var bent := _bent_lane(sea_lane, from_port, to_port)
	var units := _bent_units(sea_lane, bent)
	var chunks: PackedByteArray = _lanes_in_view.get(sea_lane, PackedByteArray())
	if chunks.is_empty():
		var caps: Array = _lane_caps[sea_lane]
		var centers: PackedVector3Array = caps[0]
		var spans: PackedFloat64Array = caps[1]
		var margin := (SHIP_CULL_MARGIN + PORT_MAX_REACH) * _ship_scale()
		var view_angle := asin(minf((size.length() / 2.0 + margin) / _radius(), 1.0))
		chunks.resize(centers.size())
		for c in centers.size():
			chunks[c] = 1 if centers[c].dot(_toward) >= cos(minf(view_angle + spans[c], PI)) else 0
		_lanes_in_view[sea_lane] = chunks
	# Between points i - 1 and i (as _bent_sample() finds them): in the chunk with i - 1.
	var miles: PackedFloat64Array = bent.miles
	var i := clampi(miles.bsearch(clampf(mile, 0.0, sea_lane.length())), 1, units.size() - 1)
	return chunks[mini((i - 1) / LANE_CHUNK, chunks.size() - 1)] == 1

## Whether a ship at sea could be in view (see _on_lane_in_view()); true if
## it's not on a lane.
func _ship_maybe_in_view(ship: Ship) -> bool:
	if ship.is_docked() or ship.from_port.is_empty() or ship.to_port.is_empty():
		return true
	var sea_lane = ship.leg_lane()
	return sea_lane == null or _on_lane_in_view(sea_lane, ship.from_port, ship.to_port, ship.traveled_nm)

## Which ends of a lane curve in to their harbours: [arriving, leaving], each
## where its port's marina shows near the view.
func _lane_curve_ends(from_port: String, to_port: String) -> Array:
	var near := Rect2(Vector2.ZERO, size).grow(size.length() / 2.0)
	var shows := [false, false]
	for i in 2:
		var port := to_port if i == 0 else from_port
		var root := port_screen_position(port)
		shows[i] = not _is_hidden(root) and near.has_point(root) and _marina_shown(port)
	return shows

## A lane's curves into and out of its ports' harbours (those that show:
## `shows`, see _lane_curve_ends()): [how far (nm) from each end they take,
## [in, out]; the curves, [in, out], each as points on the unit sphere; the
## view's middle they were worked out at]. The curves only change with the
## zoom, not as the map's dragged: worked out once a zoom (and again once
## the view's moved a degree), kept on the globe and only put on screen
## each frame.
func _lane_curve_memo(sea_lane, from_port: String, to_port: String, shows: Array) -> Array:
	var length: float = sea_lane.length()
	var memo_key := "%s>%s %s %s" % [from_port, to_port, shows[0], shows[1]]
	var memo: Array = _lane_reach_memo.get(memo_key, [])
	if memo.is_empty() or (_center - (memo[2] as Vector2)).length() > LANE_CURVE_DRIFT:
		# Only LANE_CURVE_MS of them a frame (when marinas first show, every
		# lane near wants its curves at once): the rest straight in till the
		# next frame (the static layer's drawn again then).
		var frame := Engine.get_process_frames()
		if frame != _lane_curve_frame:
			_lane_curve_frame = frame
			_lane_curve_spent = 0.0
		if _lane_curve_spent >= LANE_CURVE_MS:
			_static_layer.queue_redraw()
			return [PackedFloat32Array([0.0, 0.0]), [PackedVector3Array(), PackedVector3Array()], _center]
		var t_c := Time.get_ticks_usec()
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
		_lane_curve_spent += (Time.get_ticks_usec() - t_c) / 1000.0
		_prof("lanes.curves", t_c)
	return memo

## A lane's harbour curves for the native lane pass (LanePainter's ends
## provider): [reaches (nm from each end, [in, out]), the curve in, the curve
## out (points on the unit sphere)], or [] where neither port's marina shows.
func _lane_ends(from_port: String, to_port: String) -> Array:
	var sea_lane = GameData.lane(from_port, to_port)
	if sea_lane == null:
		return []
	var shows := _lane_curve_ends(from_port, to_port)
	if not (shows[0] or shows[1]):
		return []
	var memo := _lane_curve_memo(sea_lane, from_port, to_port, shows)
	return [PackedFloat32Array(memo[0]), memo[1][0], memo[1][1]]

## A lane on screen in three pieces: the curve out of its first port's
## harbour, the lane between, and the curve into its last port's (the curves
## empty where a port's marina doesn't show, the lane then running on to it).
func _lane_pieces(sea_lane, from_port: String, to_port: String) -> Array[PackedVector2Array]:
	# Its points (as laid: see _bent_lane()) on the
	# sphere are worked out once.
	var bent := _bent_lane(sea_lane, from_port, to_port)
	var lane_miles: PackedFloat64Array = bent.miles
	var units := _bent_units(sea_lane, bent)
	var length: float = sea_lane.length()
	var shows := _lane_curve_ends(from_port, to_port)
	var curved: bool = shows[0] or shows[1]
	var curves: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array()]  # [in, out]
	var reaches := PackedFloat32Array([0.0, 0.0])
	if curved:
		var memo := _lane_curve_memo(sea_lane, from_port, to_port, shows)
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
	if _native_lane_screen:
		# (The same, natively: a big fleet's lanes have many thousands of points.)
		middle = ClassDB.class_call_static(&"LaneMath", &"lane_on_screen", middle, units, lane_miles, centers, spans, LANE_CHUNK, {toward = _toward, right = _right, up = _up,
			radius = _radius(), middle = size / 2.0, view_angle = view_angle, hidden = HIDDEN}, start, stop, reaches[0] > 0.0)
		if reaches[0] > 0.0:
			middle.append(world_to_screen(_bent_sample(sea_lane, from_port, to_port, stop)[0]))
		return [curves[1], middle, curves[0]]
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

# --- The fleet's lanes as the passes take them ----------------------------------

## Each lane the fleet sails as the native passes and the anchorage test take
## it (see _bent_lane()), and the ports' marina sizes as last seen (see
## _check_port_sizes()).
var _port_sizes_seen: Array = []
var _bent_lanes := {}
## Up each time the laid lanes are thrown away (see _check_port_sizes()): what was
## worked out from them is worked out again (_harbour_corridors(), _anchors_in_lanes()).
var _bent_epoch := 0
## Lanes a frame that drew wanted laid out (sea lane -> [from, to]): done by the next frames (see _warm_lanes()).
var _lanes_wanted := {}

## A lane as laid out for the passes (see _bent_lane()) if it has been already,
## else {} (and it's done over the next frames, not in a frame that draws; the
## ships on it sail the lane's own sample() meanwhile, the same line).
func _bent_lane_if_ready(sea_lane, from_port: String, to_port: String) -> Dictionary:
	_check_port_sizes()  # (Throws the laid lanes away when the ports' sizes have changed.)
	if _bent_lanes.has(sea_lane):
		return _bent_lanes[sea_lane]
	if not _lanes_wanted.has(sea_lane):
		_lanes_wanted[sea_lane] = [from_port, to_port]
	return {}
var _port_sizes_checked := -1

## Looks every PORT_SIZE_CHECK_S at every port's marina size (its mouth's
## distance from it), as ports grow and hubs come and go: the harbour curves
## and what's worked out from the laid lanes (the lanes in view, their caps
## and units, the corridors and the anchor spots in lanes) are made again
## when any has changed. Lanes used to be bent out round the harbours of the
## ports they passed (a keep-out zone round each, to leave quiet water for
## ships at anchor); since 2026-10-13 they're drawn and sailed just as laid,
## and ships lie in port instead (see _lay_moorings()).
func _check_port_sizes() -> void:
	var now := Time.get_ticks_msec()
	if _port_sizes_checked >= 0 and now - _port_sizes_checked < PORT_SIZE_CHECK_S * 1000.0:
		return
	_port_sizes_checked = now
	var sizes := []
	for port: Dictionary in GameData.ports:
		var port_id: String = port.id
		sizes.append([port_id, (_port_layout(port_id).mouth as Vector2).x])
	if sizes != _port_sizes_seen:
		_port_sizes_seen = sizes
		_bent_lanes.clear()
		_bent_epoch += 1
		_lanes_warm = false
		_lane_units.clear()
		_lane_caps.clear()
		_lanes_in_view.clear()
		if _ship_culler != null:
			_ship_culler.forget_lanes()
		if _lane_painter != null:
			_lane_painter.forget_lanes()
			_lane_mesh_epoch = []  # (The mesh is built again with the harbour curves afresh.)
		_lane_reach_memo.clear()

## A lane as the passes and the anchorage test take it: its points
## (projected) and miles just as laid, and its box (projected), for skipping
## it where it can't reach (see _anchors_in_lanes()). Made once. (`bent` is
## what the passes expect: all 0, no point is moved.)
func _bent_lane(sea_lane, _from_port: String, _to_port: String) -> Dictionary:
	_check_port_sizes()
	if _bent_lanes.has(sea_lane):
		return _bent_lanes[sea_lane]
	var points: PackedVector2Array = sea_lane.points
	var miles: PackedFloat64Array = sea_lane.miles
	var bent := PackedByteArray()
	bent.resize(points.size())
	var box := Rect2(points[0], Vector2.ZERO) if not points.is_empty() else Rect2()
	for p in points:
		box = box.expand(p)
	var made := {points = points, miles = miles, bent = bent, box = box}
	_bent_lanes[sea_lane] = made
	return made

## True if a (lon, lat) point is on the land, as the map draws it (islands
## and all): in one of its land triangles, looked up by LAND_CELL_DEG cell.
static func _on_land(lon_lat: Vector2) -> bool:
	var p := Geo.project(Vector2(wrapf(lon_lat.x, -180.0, 180.0), lon_lat.y))
	if _land_test != null:
		return _land_test.contains(p)  # (The same test, natively.)
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
	if ClassDB.class_exists(&"LandTest"):
		var mask: Object = ClassDB.instantiate(&"LandTest")
		mask.build(GameData.world_map.land_triangles, LAND_CELL_DEG)
		_land_test = mask
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

## Lays out (_bent_lane()) the fleet's lanes both ways for the passes ahead
## of their being drawn, LANE_WARM_MS' worth a frame.
func _warm_lanes() -> void:
	var start := Time.get_ticks_usec()
	# The lanes a frame that drew asked for first (see _bent_lane_if_ready()).
	while not _lanes_wanted.is_empty():
		var sea_lane: Variant = _lanes_wanted.keys()[0]
		var way: Array = _lanes_wanted[sea_lane]
		_lanes_wanted.erase(sea_lane)
		if not _bent_lanes.has(sea_lane):
			_bent_lane(sea_lane, way[0], way[1])
			_count("n.bent")
			if Time.get_ticks_usec() - start >= LANE_WARM_MS * 1000.0:
				return
	if _lanes_warm:
		return  # (All bent already.)
	for lane: Array in _active_lanes():
		for way: Array in [[lane[0], lane[1]], [lane[1], lane[0]]]:
			var sea_lane = GameData.lane(way[0], way[1])
			if sea_lane == null or _bent_lanes.has(sea_lane):
				continue
			_bent_lane(sea_lane, way[0], way[1])
			if Time.get_ticks_usec() - start >= LANE_WARM_MS * 1000.0:
				return
	_lanes_warm = true  # (Till the active lanes are looked at again.)

## Where along a lane a ship `mile` along it is, and which way it's heading:
## [projected position, direction], the lane's own sample() (lanes are drawn
## and sailed just as laid: see _check_port_sizes()).
func _bent_sample(sea_lane, from_port: String, to_port: String, mile: float) -> Array:
	_bent_lane_if_ready(sea_lane, from_port, to_port)  # (Laid out for the passes over the next frames, if it isn't yet.)
	return sea_lane.sample(mile)

## Where a ship is on the map (projected), as drawn: on its lane as laid
## (see _bent_lane()); a carried or towed one with its
## rescuer; docked, at its port.
func _ship_world(ship: Ship) -> Vector2:
	if ship.is_carried() or ship.is_towed():
		return _ship_world(ship.rescuer)
	if ship.job_phase == Ship.JOB_FISH:
		var fishing := _fishing_pose(ship)
		if not fishing.is_empty():
			return fishing[0]
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
	if ship.job_phase == Ship.JOB_FISH:
		var fishing := _fishing_pose(ship)
		if not fishing.is_empty():
			return fishing[1]
	var here := _ship_bent(ship)
	return here[1] if not here.is_empty() else ship.heading()

## Fishing boats spread out (so a ground's boats, and boats on one lane, don't
## sit on top of each other): sailing, each keeps its own way off to one side
## of the lane (up to FISH_LANE_SPREAD_NM, eased in over FISH_LANE_EASE_NM from
## a port, never onto land); at the ground each has its own spot
## (Ship.fish_slot: one of GameState.GROUND_BOATS round its middle, on the
## water), easing out to it over the last FISH_APPROACH_NM of the way and back
## in over the first going home. Working, a troller or trawler works slow
## loops round its spot (FISH_LOOP_NM across, one every FISH_LOOP_S); a
## crabber or netter lies at its spot by its gear.
const FISH_LANE_SPREAD_NM := 1.6
const FISH_LANE_EASE_NM := 6.0
const FISH_APPROACH_NM := 12.0
const FISH_SPOT_SHARE := 0.4
const FISH_LOOP_NM := 1.2
const FISH_LOOP_S := 80.0
const FISH_TROLL_TURN_NM := 0.25  # A troller's turn at the end of its run (radius).
var _fish_spots := {}  # [ground, slot] -> its spot (projected), found once.
var _fish_poses := {}  # ship -> [frame, [position, heading]].

## A fishing boat on its trip: [position (projected), heading (projected,
## normalised)] as spread out, or [] off its lane.
func _fishing_pose(ship: Ship) -> Array:
	var frame := Engine.get_process_frames()
	var kept: Array = _fish_poses.get(ship, [])
	if not kept.is_empty() and kept[0] == frame:
		return kept[1]
	var pose := _fishing_pose_now(ship)
	_fish_poses[ship] = [frame, pose]
	return pose

func _fishing_pose_now(ship: Ship) -> Array:
	var ground := ship.fish_ground
	if ship.is_working_ground() and not ground.is_empty():
		return _fish_work_pose(ship, GameState.play_time)
	var here := _ship_bent(ship)
	if here.is_empty():
		return []
	var length := 0.0
	var lane = ship.leg_lane()
	if lane != null:
		length = lane.length()
	var from_start := ship.traveled_nm
	var to_end := length - ship.traveled_nm
	# Out to its spot on the ground, or back in from it: sailed, on a curve
	# between its way along the lane and its spot (see _fish_approach()).
	if not ground.is_empty():
		var end := Fisheries.end_of(ground)
		if ship.to_port == end or ship.from_port == end:
			var arriving := ship.to_port == end
			var approach := _fish_approach_nm(ship, ground, length)
			var gone := to_end if arriving else from_start
			if gone < approach:
				var curve := _fish_approach(ship, ground, lane, length, approach, arriving)
				if not curve.is_empty():
					var on: Array = _along_path(curve, 1.0 - gone / approach if arriving else gone / approach)
					return [on[0], Vector2.from_angle(float(on[1]))]
			else:
				_fish_left.erase(ship)
	return [_fish_lane_point(ship, here, from_start, to_end), here[1]]

## Where a fishing boat sailing its lane is drawn (projected): off to its own
## side of the lane, eased in from either end of the leg, never onto land.
func _fish_lane_point(ship: Ship, here: Array, from_start: float, to_end: float) -> Vector2:
	var at: Vector2 = here[0]
	var side := (float(ship.id * 7919 % 1000) / 1000.0 * 2.0 - 1.0) * FISH_LANE_SPREAD_NM
	var ease := smoothstep(0.0, FISH_LANE_EASE_NM, minf(from_start, to_end))
	var offset := (here[1] as Vector2).orthogonal() * side * ease * _units_per_nm(at)
	if offset != Vector2.ZERO and _on_land(Geo.unproject(at + offset)):
		offset = Vector2.ZERO
	return at + offset

## A fishing boat at work at a play time: [position, heading] (projected): a
## troller or trawler on its slow loop round its spot, a crabber or netter
## lying at it.
func _fish_work_pose(ship: Ship, at_time: float) -> Array:
	var spot := _fish_spot(ship.fish_ground, ship.fish_slot)
	var gear := _fishing_gear_kind(ship)
	if gear == "troll":
		# A troller runs its lines up and back along a line through its spot:
		# one leg out, a tight turn, the other leg home a turn's width over, and
		# round again (a stadium), its heading along the leg or round the turn.
		var per_nm := _units_per_nm(spot)
		var leg := FISH_LOOP_NM * 2.0 * per_nm
		var r := FISH_TROLL_TURN_NM * per_nm
		var round := 2.0 * leg + TAU * r
		var s := fposmod((at_time / FISH_LOOP_S + float(ship.id % 17) / 17.0) * round, round)
		var heading := float(ship.fish_slot) * TAU / GameState.GROUND_BOATS + float(ship.id % 7) * 0.4
		var ahead := Vector2.from_angle(heading)
		var side := ahead.orthogonal()
		var local: Vector2
		var facing: Vector2
		if s < leg:  # Out, on the right-hand leg.
			local = ahead * (s - leg / 2.0) + side * r
			facing = ahead
		elif s < leg + PI * r:  # Round the far turn.
			var a := (s - leg) / r
			local = ahead * (leg / 2.0) + side * r * cos(a) + ahead * r * sin(a)
			facing = (ahead * cos(a) - side * sin(a))
		elif s < 2.0 * leg + PI * r:  # Back, on the left-hand leg.
			var back := s - leg - PI * r
			local = ahead * (leg / 2.0 - back) - side * r
			facing = -ahead
		else:  # Round the near turn.
			var a := (s - 2.0 * leg - PI * r) / r
			local = -ahead * (leg / 2.0) - side * r * cos(a) - ahead * r * sin(a)
			facing = (-ahead * cos(a) + side * sin(a))
		return [spot + local, facing.normalized()]
	if gear == "trawl":
		var turn := TAU * fposmod(at_time / FISH_LOOP_S + float(ship.id % 17) / 17.0, 1.0)
		var loop := Vector2(cos(turn), sin(turn)) * FISH_LOOP_NM * _units_per_nm(spot)
		return [spot + loop, Vector2(-sin(turn), cos(turn))]
	var lying := float(ship.fish_slot) * TAU / GameState.GROUND_BOATS + PI / 2.0
	return [spot, Vector2.from_angle(lying)]

## How much of its lane (nm, from the ground's end) a fishing boat sails its
## curve to or from its spot over: as long as the curve itself (so it's never
## faster than at sea), at least FISH_APPROACH_NM, at most the leg up to its
## port end's harbour curve (half the leg if that isn't known). Worked out
## once a leg.
func _fish_approach_nm(ship: Ship, ground: String, length: float) -> float:
	var key := [ship.from_port, ship.to_port, ship.fish_slot]
	var kept: Array = _fish_approaches.get(ship, [])
	if not kept.is_empty() and kept[0] == key:
		return kept[1]
	var arriving := ship.to_port == Fisheries.end_of(ground)
	var middle := GameData.port_position(Fisheries.end_of(ground))
	var per_nm := maxf(_units_per_nm(middle), 0.000001)
	var off := middle.distance_to(_fish_spot(ground, ship.fish_slot)) / per_nm
	var lane = ship.leg_lane()
	var port_reach := 0.0
	if lane != null:
		var reaches := _harbour_reaches(ship, lane, length)
		port_reach = reaches[1] if arriving else reaches[0]
	var most := length * 0.5 if port_reach <= 0.0 else maxf(length * 0.5, length - port_reach - 1.0)
	var approach := minf(FISH_APPROACH_NM + off + FISH_LOOP_NM, most)
	for k in 3:
		var curve := _fish_approach(ship, ground, lane, length, approach, arriving)
		if curve.is_empty():
			break
		var curve_nm := _path_length(curve) / per_nm
		if curve_nm <= approach * 1.02 or approach >= most:
			break
		approach = minf(curve_nm * 1.05, most)
	_fish_approaches[ship] = [key, approach]
	return approach

var _fish_approaches := {}  # ship -> [leg, nm]

## Each fishing boat's way home from its spot, [leg, pose it set off from].
var _fish_left := {}

## A fishing boat's curve (projected points) between where it leaves (or
## joins) its lane `approach` nm from the ground's end and its spot: out, from
## the lane's way to where its work starts (a troller's loop where it is now,
## so it sails straight on into it); home, from where it was working when it
## set off (kept for the leg) round onto the lane, heading the way it goes all
## along (it never slips sideways). Through the ground's middle (where its
## lane ends, always water) if the plain curve would cross land. [] if the
## lane can't be sampled.
func _fish_approach(ship: Ship, ground: String, lane, length: float, approach: float, arriving: bool) -> PackedVector2Array:
	if lane == null:
		return PackedVector2Array()
	var mile := length - approach if arriving else approach
	var sample: Array = _bent_sample(lane, ship.from_port, ship.to_port, clampf(mile, 0.0, length))
	var join := [_fish_lane_point(ship, sample, mile, length - mile), (sample[1] as Vector2).angle()]
	var work: Array
	if arriving:
		work = _fish_work_pose(ship, GameState.play_time)
	else:
		var key := [ship.from_port, ship.to_port]
		var left: Array = _fish_left.get(ship, [])
		if left.is_empty() or left[0] != key:
			# Where it was when it stopped work: as near as the time it's sailed since tells.
			var since := ship.traveled_nm / maxf(ship.speed(), 0.1)
			left = [key, _fish_work_pose(ship, GameState.play_time - since)]
			_fish_left[ship] = left
		work = left[1]
	var spot := [work[0], (work[1] as Vector2).angle()]
	var poses := [join, spot] if arriving else [spot, join]
	var curve := _pose_path(poses)
	for k in range(0, curve.size(), 4):
		if _on_land(Geo.unproject(curve[k])):
			var middle := GameData.port_position(Fisheries.end_of(ground))
			var through := [middle, ((spot[0] as Vector2) - middle).angle() if arriving else (middle - (spot[0] as Vector2)).angle()]
			poses = [join, through, spot] if arriving else [spot, through, join]
			curve = _pose_path(poses)
			break
	return curve

## A ground's spot for a slot (projected): round its middle, FISH_SPOT_SHARE
## of its radius out (each slot its own way round), pulled in till it and its
## loop are on the water and clear of every marina (with its lines out, a
## boat never works inside a harbour); further out if it must.
const FISH_MARINA_CLEAR_NM := 2.0
func _fish_spot(ground: String, slot: int) -> Vector2:
	var key := [ground, slot]
	if _fish_spots.has(key):
		return _fish_spots[key]
	var middle := GameData.port_position(Fisheries.end_of(ground))
	var radius := float(Fisheries.shared().grounds.get(ground, {}).get("radius_nm", 20.0)) * FISH_SPOT_SHARE
	var units := _units_per_nm(middle)
	var first := float(absi(hash(ground)) % 360) * PI / 180.0
	var spot := middle
	for turn in 8:  # (Its own way round first, then the ways either side of it.)
		var angle := first + float(slot) * TAU / GameState.GROUND_BOATS + float((turn + 1) / 2) * (0.3 if turn % 2 == 1 else -0.3)
		for share: float in [1.0, 0.75, 0.5, 0.3, 0.15, 1.5, 2.0]:
			var at := middle + Vector2.from_angle(angle) * radius * share * units
			if not _clear_of_marinas(at, (FISH_LOOP_NM + FISH_MARINA_CLEAR_NM) * units):
				continue
			var wet := true
			for k in 5:
				var check := at if k == 4 else at + Vector2.from_angle(k * PI / 2.0) * (FISH_LOOP_NM + 0.3) * units
				if _on_land(Geo.unproject(check)):
					wet = false
					break
			if wet:
				spot = at
				break
		if spot != middle:
			break
	_fish_spots[key] = spot
	return spot

## True if a point (projected) is further than `margin` (projected units)
## outside every marina near it (its jetty's radius round its port: dock units,
## 1/SHIP_WORLD_ZOOM of a projected degree each).
func _clear_of_marinas(at: Vector2, margin: float) -> bool:
	for port: Dictionary in GameData.ports:
		var spot := GameData.port_position(port.id)
		if absf(spot.y - at.y) > 3.0 or absf(fposmod(spot.x - at.x + 180.0, 360.0) - 180.0) > 3.0:
			continue
		var reach := float(_port_layout(port.id).radius) / SHIP_WORLD_ZOOM + margin
		if spot.distance_to(at) < reach:
			return false
	return true

## Projected map units in a nautical mile there (Web Mercator degrees: 1/60 of
## a degree, stretched by the latitude).
static func _units_per_nm(at: Vector2) -> float:
	return 1.0 / (60.0 * maxf(cos(deg_to_rad(Geo.unproject(at).y)), 0.05))

## What a fishing boat's working now: the gear for its species, if its model
## has it, else its model's first.
static func _fishing_gear_kind(ship: Ship) -> String:
	var gear: Array = ship.model().get("fishing", {}).get("gear", [])
	var kind := str(Fisheries.shared().species.get(ship.fish_species, {}).get("gear", "troll"))
	if not gear.has(kind):
		kind = str(gear[0]) if not gear.is_empty() else "troll"
	return kind

## A ship's place on its bent lane ([position, direction]), or [] off a lane.
func _ship_bent(ship: Ship) -> Array:
	if ship.is_docked() or ship.from_port.is_empty() or ship.to_port.is_empty():
		return []
	# Asked for a few times a frame for a ship (where it is, which way it
	# heads, its turning...): worked out once, for where it is.
	var frame := Engine.get_process_frames()
	if frame != _bent_frame:
		_bent_frame = frame
		_bent_cache.clear()
	var kept: Array = _bent_cache.get(ship, [])
	if not kept.is_empty() and kept[0] == ship.traveled_nm and kept[1] == ship.from_port and kept[2] == ship.to_port:
		return kept[3]
	var here := []
	var sea_lane = ship.leg_lane()
	if sea_lane != null:
		here = _bent_sample(sea_lane, ship.from_port, ship.to_port, ship.traveled_nm)
	_bent_cache[ship] = [ship.traveled_nm, ship.from_port, ship.to_port, here]
	return here

## Each ship's place on its bent lane this frame: ship -> [traveled_nm,
## from_port, to_port, [position, direction]] (see _ship_bent()).
var _bent_cache := {}
var _bent_frame := -1

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
	# Solid lines natively, without points closer than LINE_MIN_PX (zoomed out,
	# a lane has far more points than pixels, each costly to draw smoothly).
	var runs: Array = ClassDB.class_call_static(&"LaneMath", &"visible_runs", points, 0.0 if dashed else LINE_MIN_PX, HIDDEN) if _native_lane_screen else _visible_runs(points)
	for part: PackedVector2Array in runs:
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
	# Which hubs can be upgraded is asked a few times a second (it costs, every
	# hub's every path), like the nav's own alert dots.
	var now := Time.get_ticks_msec()
	if now - _hub_alerts_time >= HUB_ALERTS_REFRESH_MS or _hub_alerts_time < 0:
		_hub_alerts_time = now
		_hub_alerts.clear()
		for hub in GameState.hubs:
			if GameState.hub_can_upgrade(hub):
				_hub_alerts.append(hub.port_id)
	for port_id: String in _hub_alerts:
		var dot := port_screen_position(port_id) + HUB_ALERT_OFFSET
		_canvas.draw_circle(dot, HUB_ALERT_RADIUS + 1.0, _color(&"hub_alert_outline"), true, -1.0, true)
		_canvas.draw_circle(dot, HUB_ALERT_RADIUS, _color(&"hub_alert"), true, -1.0, true)

## The ports of the hubs with an upgrade to buy, as last looked at, and when (ms).
var _hub_alerts: Array[String] = []
var _hub_alerts_time := -1
const HUB_ALERTS_REFRESH_MS := 500

## Ships at sea are rectangles with a pointed bow; docked ships are small dots.
## Smaller ships are drawn over bigger ones.
## Ships riding on a recovery boat are drawn after it, so they sit in its
## middle. Lost ships get a red "!" above them, and ships that won't make it
## to port an amber one.
func _draw_ships() -> void:
	_ship_hulls.clear()
	var outline := _color(&"ship_outline")
	var order := _ships_biggest_first()
	var fleet := _fleet_pass(order)
	var draw: PackedInt32Array = fleet.draw
	var plain: PackedByteArray = fleet.plain
	if profiling:
		profile["n.dotted"] = float(profile.get("n.dotted", 0.0)) + float(fleet.get("dots", 0))
		profile["n.plain_drawn"] = float(profile.get("n.plain_drawn", 0.0)) + float(plain.count(1))
	for k in draw.size():
		var ship: Ship = order[draw[k]]
		_draw_ship(ship, outline, plain[k] == 1)
	for i: int in fleet.carried:
		_draw_ship(order[i], outline)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_draw_tow_lines(order, fleet.tugs)
	for i: int in fleet.markers:
		var ship: Ship = order[i]
		if ship.is_towed():
			continue  # On its way in: no marker.
		if ship.is_lost() and not ship.is_carried():
			_draw_marker(ship_screen_position(ship), _color(&"lost_marker"))
		elif ship.at_risk:
			_draw_marker(ship_screen_position(ship), _color(&"at_risk_marker"))

## The fleet sorted for drawing, once a frame (ShipCuller, natively; the same
## here without it): {draw: the places in `order` of the ships to draw (docked
## at a port whose marina shows near the view, service ships and any carried,
## towed or held at a canal, and cargo ships plainly sailing whose stretch of
## lane could be in view), plain: a byte for each, 1 for a cargo ship plainly
## on its lane (nothing more to check), carried: those riding on a recovery
## boat (drawn after it), markers: the player's lost or at-risk ships that could
## be in view, tugs: those with a ship on their line}. A big fleet's few ships
## on screen needn't cost a loop over every ship in GDScript.
func _fleet_pass(order: Array[Ship]) -> Dictionary:
	if _ship_culler == null and ClassDB.class_exists(&"ShipCuller"):
		_ship_culler = ClassDB.instantiate(&"ShipCuller")
		_ship_culler.setup({kind_cargo = Ship.KIND_CARGO, kind_tug = Ship.KIND_TUG, chunk = LANE_CHUNK,
			held_states = [Ship.CANAL_ANCHORED, Ship.CANAL_CONVOY, Ship.CANAL_TOLL]})
		_ship_culler.set_lane_provider(_lane_chunks)
	if _ship_culler != null:
		var margin := (SHIP_CULL_MARGIN + PORT_MAX_REACH) * _ship_scale()
		var tight := SHIP_CULL_MARGIN * _ship_scale() + 8.0
		# Each ship's length and its dot's colour (by its place in `order`), for
		# the dots the pass draws itself: worked out when the order's made.
		if _order_colors.size() != order.size() or _order_colors_gray != gray_mode:
			_order_colors_gray = gray_mode
			_order_colors.resize(order.size())
			_order_lengths.resize(order.size())
			for i in order.size():
				var look := _model_look(order[i].model_id)
				_order_colors[i] = (look[0] as Color) * _ship_fade(order[i])
				_order_lengths[i] = (look[7] as Rect2).size.x
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		return _ship_culler.sort(order, {view_epoch = _view_epoch, toward = _toward, view_angle = asin(minf((size.length() / 2.0 + margin) / _radius(), 1.0)),
			tight_angle = asin(minf((size.length() / 2.0 + tight) / _radius(), 1.0)), end_zone_nm = HARBOUR_END_ZONE_NM,
			end_slack_angle = asin(minf(MARINA_MAX_REACH * 2.0 * _ship_scale() / _radius(), 1.0)),
			docks_shown = docks_shown(), mine = GameState.company, port_shown = _port_ships_shown,
			dots = Settings.ship_look != "grow", dot_half_px = _ship_dot_half(), dots_canvas = _canvas.get_canvas_item(), right = _right, up = _up, radius = _radius(), middle = size / 2.0,
			screen = Rect2(Vector2.ZERO, size), near = Rect2(Vector2.ZERO, size).grow(margin), scale = _ship_scale(), dot_px = TINY_SHIP_PX, lengths = _order_lengths, colors = _order_colors})
	var draw := PackedInt32Array()
	var plain := PackedByteArray()
	var carried := PackedInt32Array()
	var markers := PackedInt32Array()
	var tugs := PackedInt32Array()
	var ports_shown := {}  # (Looked at once a port rather than for every ship there.)
	for i in order.size():
		var ship := order[i]
		if ship.is_carried():
			carried.append(i)
		elif ship.is_docked():
			if docks_shown():  # (Otherwise as dots: see _draw_dock_layer().)
				var shown = ports_shown.get(ship.docked_at)
				if shown == null:
					shown = _port_ships_shown(ship.docked_at)
					ports_shown[ship.docked_at] = shown
				if shown:
					draw.append(i)
					plain.append(0)
		else:
			var plain_sailing := not ship.is_service() and ship.rescuer == null and not _held_at_canal(ship)
			# (A service ship with nothing on is plainly on its lane too.)
			var idle_service := ship.is_service() and ship.rescuer == null and not _held_at_canal(ship) and not ship.is_on_job() and ship.rescuing == null and ship.ice_phase.is_empty()
			if not (plain_sailing or idle_service) or _ship_maybe_in_view(ship):
				draw.append(i)
				plain.append(1 if plain_sailing else 0)
		if ship.is_tug() and ship.rescuing != null:
			tugs.append(i)
		if GameState.is_mine(ship) and (ship.is_lost() and not ship.is_carried() or ship.at_risk):
			if _held_at_canal(ship) or _ship_maybe_in_view(ship):
				markers.append(i)
	return {draw = draw, plain = plain, carried = carried, markers = markers, tugs = tugs}

## Whether the ships in port at a port show: it's near the view and its marina's drawn.
func _port_ships_shown(port_id: String) -> bool:
	var near := Rect2(Vector2.ZERO, size).grow((SHIP_CULL_MARGIN + PORT_MAX_REACH) * _ship_scale())
	return near.has_point(port_screen_position(port_id)) and _marina_shown(port_id)

## True while a ship's held off its lane at a canal (at its anchorage, in a
## convoy or paying its toll), drawn where that puts it.
static func _held_at_canal(ship: Ship) -> bool:
	return ship.canal_state == Ship.CANAL_ANCHORED or ship.canal_state == Ship.CANAL_CONVOY or ship.canal_state == Ship.CANAL_TOLL

## A lane's chunks for the native fleet pass (ShipCuller's lane provider):
## [the bent lane's miles, its chunks' middles, their spans] (see
## _chunk_caps()), or [] for no lane.
func _lane_chunks(from_port: String, to_port: String) -> Array:
	var sea_lane = GameData.lane(from_port, to_port)
	if sea_lane == null:
		_count("n.lane_none")
		return []
	var bent := _bent_lane_if_ready(sea_lane, from_port, to_port)
	if bent.is_empty():
		_count("n.lane_unbent")
		return []  # (Asked again next pass, once it's bent: see _warm_lanes().)
	var units := _bent_units(sea_lane, bent)  # (Makes its caps.)
	var caps: Array = _lane_caps[sea_lane]
	return [bent.miles, caps[0], caps[1], units]

## Further than this (nm of lane) from either of its ports, a cargo ship's
## drawn right on its lane: no curve in or out of a harbour reaches it (the
## curves take at most HARBOUR_REACH times a harbour's distance from its
## port, under 150 nm, and the harbour's within MARINA_MAX_REACH of the
## port), so the fleet pass can skip it by its own point (see _fleet_pass()).
const HARBOUR_END_ZONE_NM := 220.0

## The tow lines from each tug with a ship on its line (at sea, or in to its
## berth): pulling ahead, from its stern to the ship's bow (two in a Y at
## sea); made fast astern, from its bow to the ship's stern. `tugs`: the
## places in `order` of the tugs with a ship on their line.
func _draw_tow_lines(order: Array[Ship], tugs: PackedInt32Array) -> void:
	for i: int in tugs:
		var tug: Ship = order[i]
		var line := _tug_line(tug)
		if line.is_empty():
			continue
		var ship := tug.rescuing
		var tug_rect: Rect2 = _model_look(tug.model_id)[7]
		var ship_rect: Rect2 = _model_look(ship.model_id)[7]
		var ends := -1.0 if line == "bow" else 1.0  # (Its stern to the ship's bow, or its bow to the ship's stern.)
		var on_tug := ship_screen_position(tug) + Vector2.from_angle(_screen_angle(tug)) * ends * tug_rect.size.x / 2.0 * _ship_scale()
		var on_ship := ship_screen_position(ship) - Vector2.from_angle(_screen_angle(ship)) * ends * ship_rect.size.x / 2.0 * _ship_scale()
		_canvas.draw_line(on_tug, on_ship, TOW_LINE_COLOR, maxf(0.25 * _ship_scale(), 1.0), true)

## The line a tug has on its ship now (see _work_line()): "bow" towing it at
## sea or pulling it in through its harbour, "stern" made fast astern of it
## coming in, else "".
func _tug_line(tug: Ship) -> String:
	if tug.job_phase == Ship.JOB_TOW:
		return "bow"
	if tug.job_phase != Ship.JOB_BERTH or not docks_shown():
		return ""
	var work := _tug_work(tug)
	if work.is_empty():
		return ""
	var index: int = (work.team as Array).find(tug)
	return _work_line(work, work.tugs[index], _work_time(tug))

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
	_order_colors.clear()  # (Worked out again for the new order: see _fleet_pass().)
	# (Sorted on keys worked out once: a comparison asking each ship's model costs.)
	var keys := []
	for i in GameState.ships.size():
		keys.append([-float((GameState.ships[i] as Ship).model().get("map_size", [0])[0]), i])
	keys.sort()
	var order: Array[Ship] = []
	for key: Array in keys:
		order.append(GameState.ships[key[1]])
	_draw_order = order
	return order

## `plain`: a cargo ship plainly on its lane whose stretch of lane is known to
## be in view (see _fleet_pass()), so nothing more need be checked.
func _draw_ship(ship: Ship, outline: Color, plain := false) -> void:
	var look := _model_look(ship.model_id)
	_count("n.ships")
	if ship.is_service():
		_count("n.service")
	elif ship.is_docked():
		_count("n.docked")
	var color: Color = look[0]
	# Another player's ship (multiplayer): a little faded, with a flag in its
	# company's color at the stern (worked out once it's known to be drawn).
	var fade := Color.WHITE
	if ship.is_docked() and not docks_shown():
		fade = _ship_fade(ship)
		color *= fade
		outline *= fade
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
	# Too small to make out (zoomed well out): a dot in its color, where it is
	# (drawn at its size for how ships are shown far off: _ship_draw_scale()).
	var length := (look[7] as Rect2).size.x
	var scale := _ship_scale()
	if not ship.is_docked() and not ship.is_service() and ship.rescuer == null and not _held_at_canal(ship):
		# A cargo ship on its lane (most of them): where and which way from
		# one sample of the lane.
		if not plain and not _ship_maybe_in_view(ship):
			return  # (Its stretch of lane is well out of view.)
		var t_sb := Time.get_ticks_usec()
		var here := _ship_bent(ship)
		if here.is_empty():
			return
		_prof("ship.bent", t_sb)
		var on_lane := world_to_screen(here[0])
		if not near.has_point(on_lane):
			return
		scale = _ship_draw_scale(ship, on_lane)
		if length * scale < TINY_SHIP_PX:
			_count("n.tiny_lane")
			if ship.is_fishing():
				_count("n.tiny_fishing")
			_draw_tiny_ship(on_lane, color * _ship_fade(ship))
			return
		var t_sh := Time.get_ticks_usec()
		var harbour := _harbour_pose(ship)
		_prof("ship.harbour", t_sh)
		if harbour.is_empty():
			at = on_lane + _canal_lane_offset(ship)
			angle = _heading_angle(here[1], here[0])
		else:
			at = harbour[0]
			angle = harbour[1]
	else:
		at = ship_screen_position(ship)
		scale = _ship_draw_scale(ship, at)
		angle = _screen_angle(ship)
		if ship.is_docked():
			_note_last_spot(ship, at, angle)
		if length * scale < TINY_SHIP_PX:
			_count("n.tiny_other")
			_draw_tiny_ship(at, color * _ship_fade(ship))
			return
	if not Rect2(Vector2.ZERO, size).grow(SHIP_CULL_MARGIN * scale).has_point(at):
		return  # Off screen.
	fade = _ship_fade(ship)
	color *= fade
	outline *= fade
	_count("n.full")
	_note_lit_ship(at, angle, look, scale)
	if ship.is_docked() and docks_shown() and not ship.is_tug() and ship.berth >= 0 and ship.berth_phase == Ship.BERTH_NONE:
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		_draw_mooring_ropes(ship)  # Moored: tied up to the bollards.
	if ship.is_docked() and docks_shown() and not ship.is_tug() and ship.berth >= 0:
		_draw_dock_workers(ship)  # (On the quay beside it, under it.)
	_ship_hulls[ship] = [at, angle, scale]
	var rect7: Rect2 = look[7]
	# Its wake on the water, under everything of it: longer and brighter the
	# faster it's going, along the track it's just sailed (so it bends as it turns).
	var way := _wake_share(ship)
	if way > 0.0 and rect7.size.x * scale >= WAKE_MIN_PX:
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		draw_wake(_canvas, at, angle, rect7.size.x * scale, rect7.size.y * scale, way, fade.a, _wake_trail(ship, at, angle, rect7.size.x, scale))
	elif _wake_trails.has(ship):
		_wake_trails.erase(ship)
	# Its shadow on the water, away from the sun (the hull's shape, dark), then
	# the ship rolling with the sea (see _ship_roll()): narrower as it heels,
	# shifted a little to the side it leans, its superstructure more.
	var roll := _ship_roll(ship, at)
	var lean := sin(roll)
	var skin := _ship_skin(ship)  # (A skin pack's art on the player's own ships: see Cosmetics.)
	if rect7.size.y * scale >= SHADOW_MIN_PX:
		_canvas.draw_set_transform(at + _shadow_dir * rect7.size.y * scale * SHIP_SHADOW_WIDTHS + Vector2.from_angle(angle + PI / 2.0) * lean * rect7.size.y * scale * 0.3, angle, Vector2.ONE * scale)
		var hull_art: Dictionary = look[6]
		if skin != null:
			_canvas.draw_texture_rect(skin, rect7, false, Color(0, 0, 0, SHIP_SHADOW_ALPHA * fade.a))  # (The skin's shape.)
		elif not hull_art.is_empty():
			# The hull's own outline, dark (it matches the ship close up).
			_canvas.draw_texture_rect(hull_art.hull, rect7, false, Color(0, 0, 0, SHIP_SHADOW_ALPHA * fade.a))
		else:
			var dark := PackedColorArray([Color(0, 0, 0, SHIP_SHADOW_ALPHA * fade.a)])
			_canvas.draw_primitive(look[3], dark, PackedVector2Array())
			_canvas.draw_primitive(look[4], dark, PackedVector2Array())
	var sideways := Vector2.from_angle(angle + PI / 2.0) * lean * rect7.size.y * scale * ROLL_SHIFT
	_canvas.draw_set_transform(at + sideways, angle, Vector2(scale, scale * (1.0 - ROLL_NARROW * absf(lean))))
	var art: Dictionary = look[6]
	if skin != null or not art.is_empty():
		if skin != null:
			_draw_ship_skin(skin, look[7], fade, lean)
		else:
			_draw_ship_art(ship, art, look[7], color, fade, lean)
		if fade.a < 1.0:
			var rect: Rect2 = look[7]
			_canvas.draw_circle(Vector2(rect.position.x + rect.size.y * 0.5, 0.0), rect.size.y * 0.42, GameState.company_color_value(GameState.owner_of(ship).color))
		_draw_deck_crew(ship, look, fade, lean, at, angle)
		if ship.is_recovery():
			_draw_ballast(ship, look[7])
		if ship.is_working_ground():
			_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
			_draw_fishing_gear(ship, at, angle, rect7.size.x * scale, fade)
		return
	# The hull as a quad and the bow as a triangle: simple shapes Godot needn't
	# triangulate each frame, unlike a general polygon.
	var colors := PackedColorArray([color])
	_canvas.draw_primitive(look[3], colors, PackedVector2Array())
	_canvas.draw_primitive(look[4], colors, PackedVector2Array())
	_canvas.draw_polyline(look[5], outline, 1.0)

## A ship's track astern for its wake (see draw_wake()): where its stern has
## been, on the map (projected), a point every WAKE_TRAIL_STEP of its length,
## the last WAKE_TRAIL_POINTS kept; dropped and begun again where it's jumped
## (a new leg, a save loaded). Given back on screen, the newest first, for
## the wake to run along.
const WAKE_TRAIL_STEP := 0.15
const WAKE_TRAIL_POINTS := 40
var _wake_trails := {}
func _wake_trail(ship: Ship, at: Vector2, angle: float, length_units: float, scale: float) -> PackedVector2Array:
	var length_px := length_units * scale
	var width_px := length_px * 0.3
	var stern_screen := at - Vector2.from_angle(angle) * (length_px * 0.5 - width_px * 0.3)
	var stern := screen_to_world(stern_screen)
	var step := length_units / SHIP_WORLD_ZOOM * WAKE_TRAIL_STEP  # (Projected degrees.)
	var trail: PackedVector2Array = _wake_trails.get(ship, PackedVector2Array())
	if not trail.is_empty():
		var gap := trail[-1].distance_to(stern)
		var ahead_world := screen_to_world(at) - stern  # (Which way the ship points, on the map.)
		if gap > step * 2.0 / WAKE_TRAIL_STEP * 1.5 or (gap >= step and (stern - trail[-1]).dot(ahead_world) < 0.0):
			trail = PackedVector2Array([stern])  # (Jumped, or put onto a new course facing another way: a fresh wake.)
		elif gap < step:
			pass  # (Not far enough on for a new point.)
		else:
			trail.append(stern)
	else:
		trail.append(stern)
	if trail.size() > WAKE_TRAIL_POINTS:
		trail = trail.slice(trail.size() - WAKE_TRAIL_POINTS)
	_wake_trails[ship] = trail
	var on_screen := PackedVector2Array()
	for i in range(trail.size() - 1, -1, -1):
		on_screen.append(world_to_screen(trail[i]))
	return on_screen

## How fast a ship is going for its wake (see draw_wake()): its speed now as
## a share of its top speed at sea (slowed by its wear, a harbour's speed
## zone or a storm); a ship coming alongside, pulling out or gliding to its
## spot in port moves at harbour speed; one lying in port, lost adrift,
## carried or towed (its tug's wake does) leaves none.
const WAKE_MIN_PX := 7.0  # A ship drawn smaller than this (px long) has no wake.
const WAKE_HARBOUR_SHARE := 0.25
func _wake_share(ship: Ship) -> float:
	if ship.is_lost() or ship.is_carried() or ship.is_towed():
		return 0.0
	if ship.is_docked():
		if ship.is_tug():
			return 0.0  # (Working a ship in, it goes sideways with it, bow on the hull: no wake of its own.)
		if ship.berth_phase == Ship.BERTH_IN or ship.berth_phase == Ship.BERTH_OUT:
			return WAKE_HARBOUR_SHARE
		var seen: Array = _dock_seen.get(ship, [])
		if seen.size() > 2 and float(seen[1]) > -INF and GameState.play_time < float(seen[2]):
			return WAKE_HARBOUR_SHARE  # (Gliding in to its spot.)
		return 0.0
	if ship.lock_time >= 0.0 or not ship.weather_wait.is_empty() or ship.escort != null:
		return 0.0 if ship.escort == null else WAKE_HARBOUR_SHARE  # (Held at a lock or by the weather; in a convoy, at its icebreaker's pace.)
	var top := ship.top_speed()
	if top <= 0.0:
		return 0.0
	var share := ship.speed() / top
	if ship.is_service() and not ship.is_fishing():
		share = maxf(share, GameState.MIN_RECOVERY_SPEED_FACTOR)
	var zone := ship.zone_at(ship.traveled_nm)
	return clampf(share * float(zone[1]) * float(ship.storm_factors[0]), 0.0, 1.0)

## A ship's wake on the water (screen px): two arms of foam spreading astern
## from its quarters at the wake's angle (WAKE_HALF_ANGLE, as a ship's really
## does) and the wash of its screws between them, a ribbon of foam tapering
## and fading away astern. Longer and brighter the faster it's going (`way`,
## 0..1 of its top speed: WAKE_LENGTHS of its length at full speed, a third
## of that at a crawl), its foam faded with the ship (`alpha`). Drawn by the
## map and the loading screens alike.
const WAKE_HALF_ANGLE := 0.34  # Radians: 19.5°, the Kelvin angle.
const WAKE_LENGTHS := Vector2(0.5, 3.5)  # How far astern it trails at a crawl and at full speed, in lengths.
const WAKE_FOAM := Color(0.85, 0.93, 1.0)
const WAKE_ARM_POINTS := 10
const WAKE_WASH_POINTS := 8
## `trail`: the track the stern has sailed (screen), the newest point first;
## the wake runs back along it (and straight on past its end), so it bends
## with the ship's turns. Empty: straight astern.
static func draw_wake(canvas: CanvasItem, at: Vector2, angle: float, length: float, width: float, way: float, alpha := 1.0, trail := PackedVector2Array()) -> void:
	var ahead := Vector2.from_angle(angle)
	var back := -ahead
	var reach := length * lerpf(WAKE_LENGTHS.x, WAKE_LENGTHS.y, way)
	var strength := (0.35 + 0.65 * way) * alpha
	var stern := at + back * (length * 0.5 - width * 0.3)
	var arm_width := maxf(width * 0.07, 1.0) * (0.8 + 0.6 * way)
	var spread := tan(WAKE_HALF_ANGLE)
	# The wake's middle line: the stern, then the track astern (dropping any
	# point ahead of the stern), going straight on where the track runs out.
	var line := PackedVector2Array([stern])
	var run := 0.0
	var last_way := back
	for p: Vector2 in trail:
		var step := p - line[-1]
		var far := step.length()
		if far < width * 0.3:
			continue  # (Too close to the last to say which way.)
		if step.dot(last_way) < far * 0.5:
			break  # (The track turns back on itself, or runs ahead: a swing onto a new course. The wake ends here.)
		run += far
		line.append(p)
		last_way = step / far
		if run >= reach:
			break
	if run < reach:
		var tail := (line[-1] - line[-2]).normalized() if line.size() >= 2 else back
		line.append(line[-1] + tail * (reach - run + 1.0))
	for s: float in [-1.0, 1.0]:
		var points := PackedVector2Array()
		var colors := PackedColorArray()
		for i in WAKE_ARM_POINTS + 1:
			var t := float(i) / WAKE_ARM_POINTS
			var d := reach * 0.85 * t
			var here := _wake_at(line, d)
			points.append((here[0] as Vector2) + (here[1] as Vector2).orthogonal() * s * (width * 0.35 + spread * d))
			colors.append(Color(WAKE_FOAM, 0.55 * strength * (1.0 - t) * (1.0 - t)))
		canvas.draw_polyline_colors(points, colors, arm_width, true)
	# The wash: one polygon, its far end faded right out.
	var wash := reach * 0.6
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var shades := PackedColorArray()
	for i in WAKE_WASH_POINTS + 1:
		var t := float(i) / WAKE_WASH_POINTS
		var half := lerpf(width * 0.75, width * 0.2, t) * 0.5
		var here := _wake_at(line, wash * t)
		var middle: Vector2 = here[0]
		var side: Vector2 = (here[1] as Vector2).orthogonal()
		left.append(middle - side * half)
		right.append(middle + side * half)
		shades.append(Color(WAKE_FOAM, 0.3 * strength * (1.0 - t)))
	var polygon := left
	var colors := shades.duplicate()
	for i in range(WAKE_WASH_POINTS, -1, -1):
		polygon.append(right[i])
		colors.append(shades[i])
	canvas.draw_polygon(polygon, colors)

## A point a distance along a wake's middle line, and the way the line runs
## there (astern): [point, direction].
static func _wake_at(line: PackedVector2Array, d: float) -> Array:
	for i in range(1, line.size()):
		var step := line[i - 1].distance_to(line[i])
		if d <= step or i == line.size() - 1:
			var dir := (line[i] - line[i - 1]) / step if step > 0.0 else Vector2.RIGHT
			return [line[i - 1] + dir * minf(d, step), dir]
		d -= step
	return [line[-1], Vector2.RIGHT]

## A fishing boat at work, its gear in the water round it (screen px, `long`
## its length on screen): a crabber's string of pot buoys laid out beside it,
## bobbing, orange and yellow by turns, each with a little flag; a trolling
## boat's lines streaming astern with their lures wriggling; a netter's purse
## seine ringed with floats; a trawler's warps out to the net behind it.
func _draw_fishing_gear(ship: Ship, at: Vector2, angle: float, long: float, fade: Color) -> void:
	if long < 6.0:
		return  # (Too small to see.)
	var t := GameState.play_time
	var ahead := Vector2.from_angle(angle)
	var side := ahead.orthogonal()
	var kind := _fishing_gear_kind(ship)
	var line := Color(0.12, 0.12, 0.12, 0.55 * fade.a)
	match kind:
		"trap":
			var count := clampi(int(ship.model().fishing.get("traps", 30)) / 12, 3, 14)
			var seed := ship.id * 7919
			for k in count:
				var along := (float(k) - count * 0.5) * long * 0.55
				var off := long * (0.9 + 0.25 * sin(float(seed + k * 31)))
				var spot := at + ahead * along + side * off * (1.0 if k % 2 == 0 else 1.15)
				var bob := 1.0 + 0.12 * sin(t * 2.3 + k * 1.7)
				var r := maxf(long * 0.045, 1.2) * bob
				var tint := Color(0.94, 0.42, 0.14) if k % 3 != 1 else Color(0.95, 0.82, 0.16)
				_canvas.draw_circle(spot + Vector2(r * 0.4, r * 0.4), r, Color(0, 0, 0, 0.25 * fade.a))
				_canvas.draw_circle(spot, r, tint * fade)
				_canvas.draw_line(spot, spot + Vector2(0.0, -r * 3.0), line, maxf(r * 0.25, 0.6))
				_canvas.draw_rect(Rect2(spot + Vector2(0.0, -r * 3.0), Vector2(r * 1.4, r * 0.9)), tint.darkened(0.2) * fade)
		"troll":
			for k in 4:
				var spread := (float(k) - 1.5) * 0.18
				var points := PackedVector2Array()
				for j in 7:
					var f := float(j) / 6.0
					var wiggle := sin(t * 3.0 + j * 0.9 + k) * long * 0.04 * f
					points.append(at - ahead * long * (0.5 + f * 1.6) + side * (spread * long * (0.4 + f * 1.4) + wiggle))
				_canvas.draw_polyline(points, line, maxf(long * 0.012, 0.6), true)
				_canvas.draw_circle(points[points.size() - 1], maxf(long * 0.025, 0.8), Color(0.9, 0.85, 0.3, fade.a))
		"net":
			# A purse seine: a ring of floats beside the boat, closing slowly.
			var middle := at + side * long * 0.9
			var radius := long * (0.75 + 0.1 * sin(t * 0.4))
			var floats := PackedVector2Array()
			for j in 25:
				floats.append(middle + Vector2.from_angle(TAU * j / 24.0) * radius)
			_canvas.draw_polyline(floats, Color(0.95, 0.95, 0.9, 0.6 * fade.a), maxf(long * 0.015, 0.7), true)
			for j in 24:
				if j % 2 == 0:
					_canvas.draw_circle(floats[j], maxf(long * 0.025, 0.8), Color(0.95, 0.75, 0.2, fade.a))
			_canvas.draw_circle(middle, radius * 0.92, Color(0.75, 0.85, 0.9, 0.12 * fade.a))
		"trawl":
			# Two warps out astern to the net, its bag streaming behind.
			var mouth := at - ahead * long * 2.2
			for sign: float in [-1.0, 1.0]:
				_canvas.draw_line(at - ahead * long * 0.5, mouth + side * sign * long * 0.35, line, maxf(long * 0.01, 0.6), true)
			var bag := PackedVector2Array([mouth + side * long * 0.35, mouth - ahead * long * 0.9 + side * long * 0.12, mouth - ahead * long * 1.15,
				mouth - ahead * long * 0.9 - side * long * 0.12, mouth - side * long * 0.35])
			_canvas.draw_colored_polygon(bag, Color(0.25, 0.45, 0.3, 0.45 * fade.a))
			_canvas.draw_polyline(bag, Color(0.2, 0.35, 0.25, 0.7 * fade.a), maxf(long * 0.01, 0.6), true)


## The people (DeckCrew, CrewLooks): their sprites, seen from above, in one
## atlas (art/people/deck_people.svg, 64 px cells, 8 across: shadow,
## shoulders, leg, head, hair, crab pot, reel, then the hats from DECK_HAT_CELL
## + 1), drawn as one batch of quads a ship. The shoulders are this share of a
## cell across; a stride (legs swinging from one forward to the other) is this
## many shoulder widths; a person's shadow falls this many widths from them.
const DECK_ATLAS_PATH := "res://art/people/deck_people.svg"
const DECK_ATLAS_CELLS := Vector2(8, 5)
const DECK_SHOULDER_SHARE := 0.75
const DECK_STRIDE := 1.3
const DECK_SHADOW_WIDTHS := 0.4
const DECK_SHADOW_ALPHA := 0.3
const DECK_HAT_CELL := 7
## Dock workers on the quay beside a ship in port: line handlers at the
## bollards as it comes alongside and pulls out, and a gang working its cargo
## through its stop (DOCK_GANGS: [at least, more a tier] by its line).
const DOCK_GANGS := {container = [2, 2], ore = [2, 1], grain = [2, 1], livestock = [2, 1], tanker = [2, 0], vehicles = [3, 1],
	seafood = [3, 1], fishing = [1, 0], crabbing = [1, 1]}
## How far in from the quay's edge (dock units) the line handlers stand, and
## the band the gang works in: on the near half of a pier (PIER_WIDTH), its
## far half another berth's.
const DOCK_WORKER_INSET := 0.17
const DOCK_WORKER_BAND := Vector2(0.08, 0.26)
var _deck_atlas: Texture2D = null

## Whether people are big enough on screen to draw.
func _people_shown() -> bool:
	var settings := CrewLooks.settings()
	return float(settings.size) * _ship_scale() >= float(settings.min_px)

## A ship's people on deck (see DeckCrew), drawn in its frame (the transform
## _draw_ship() set: its art's rect `rect`, `lean` as it rolls). `at`: where it
## is on screen, `angle`: which way it faces there.
func _draw_deck_crew(ship: Ship, look: Array, fade: Color, lean: float, at: Vector2, angle: float) -> void:
	if not _people_shown():
		return
	var model := ship.model()
	var art := str(model.get("art", model.get("category", "")))
	var plan := DeckCrew.layout(art)
	if plan.is_empty():
		return
	var rect: Rect2 = look[7]
	rect.position.y += lean * rect.size.y * ROLL_TOWER * 0.5  # (They stand on deck, leaning a little with it.)
	var art_h := float(plan.get("h", 52.0))
	var to_local := Vector2(rect.size.x / SHIP_ART_WIDTH, rect.size.y / art_h)
	# Its own clock: the calendar's time of day where it is.
	var lon := Geo.unproject(screen_to_world(at)).x
	var hour := fposmod(fposmod(float(GameState.calendar_time()), 86400.0) / 3600.0 + (lon - GameState.clock_longitude()) / 15.0, 24.0)
	var now := Time.get_ticks_msec() / 1000.0
	var figures := DeckCrew.figures(ship, art, rect.size.x, now, hour)
	if figures.is_empty():
		return
	var outfits := [CrewLooks.ship_outfit(ship, "captain"), CrewLooks.ship_outfit(ship, "crew")]
	var people := []
	for figure: Array in figures:
		var where: Vector2 = rect.position + (figure[0] as Vector2) * to_local
		var facing := atan2(sin(float(figure[1])) * to_local.y, cos(float(figure[1])) * to_local.x)
		var walk := float(figure[3]) * to_local.x if float(figure[3]) >= 0.0 else -1.0
		people.append([where, facing, outfits[int(figure[2])], walk, int(figure[4]), int(figure[5])])
	var shadow := _shadow_dir.rotated(-angle)
	_draw_people(people, shadow, fade, Vector2(rect.position.x - rect.size.x * 0.4, 0.0))

## People (a list of [where, facing, outfit, walk (distance walked, or -1
## standing), tool, seed]) in the canvas's current frame, as one batch: each
## its shadow, its legs walking, its shoulders, head, and hat or hair; then the
## things in their hands. `shadow`: the way shadows fall in that frame;
## `astern`: where a fought fish's line runs to.
func _draw_people(people: Array, shadow: Vector2, fade: Color, astern := Vector2.ZERO) -> void:
	if _deck_atlas == null:
		_deck_atlas = load(DECK_ATLAS_PATH)
	var width := float(CrewLooks.settings().size)  # (Shoulders across.)
	var cell := width / DECK_SHOULDER_SHARE
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var dark := Color(0, 0, 0, DECK_SHADOW_ALPHA * fade.a)
	var lines := []  # [from, to, color, width] drawn after.
	for person: Array in people:
		var where: Vector2 = person[0]
		var facing: float = person[1]
		var outfit: Dictionary = person[2]
		var walk: float = person[3]
		var tool: int = person[4]
		var seed: int = person[5]
		var hat := CrewLooks.hat_index(str(outfit.hat))
		var ahead := Vector2.from_angle(facing)
		_people_quad(points, colors, uvs, where + shadow * width * DECK_SHADOW_WIDTHS, facing, cell, 0, dark)
		if walk >= 0.0:
			var swing := sin(walk / (width * DECK_STRIDE) * TAU) * cell * 0.2
			var legs := CrewLooks.trouser_color(str(outfit.trousers)) * fade
			var side := ahead.orthogonal() * cell * 0.11
			_people_quad(points, colors, uvs, where + ahead * swing - side, facing, cell, 2, legs)
			_people_quad(points, colors, uvs, where - ahead * swing + side, facing, cell, 2, legs)
		_people_quad(points, colors, uvs, where, facing, cell, 1, CrewLooks.shirt_color(str(outfit.shirt)) * fade)
		_people_quad(points, colors, uvs, where, facing, cell, 3, Portrait.SKINS[seed % Portrait.SKINS.size()] * fade)
		if hat == 0:
			_people_quad(points, colors, uvs, where, facing, cell, 4, Portrait.HAIR_COLORS[(seed / 7) % 11] * fade)
		else:
			_people_quad(points, colors, uvs, where, facing, cell, DECK_HAT_CELL + hat, fade)
		match tool:
			DeckCrew.TOOL_POT:
				_people_quad(points, colors, uvs, where + ahead * cell * 0.45, facing, cell * 0.75, 5, fade)
			DeckCrew.TOOL_LINE:
				lines.append([where + ahead * width * 0.5, where + ahead * width * 1.6, ROPE_COLOR * fade, width * 0.09])
			DeckCrew.TOOL_ROD, DeckCrew.TOOL_FIGHT:
				var tip := where + ahead.rotated(0.3 * sin(Time.get_ticks_msec() / 260.0)) * width * 2.2
				lines.append([where + ahead * width * 0.3, tip, Color(0.15, 0.13, 0.12, fade.a), width * 0.07])
				if tool == DeckCrew.TOOL_FIGHT:
					lines.append([tip, astern + Vector2(0.0, sin(Time.get_ticks_msec() / 700.0) * width * 4.0), Color(0.95, 0.95, 0.95, 0.7 * fade.a), width * 0.035])
	if points.is_empty():
		return
	var indices := PackedInt32Array()
	indices.resize(points.size() / 4 * 6)
	for q in points.size() / 4:
		var v := q * 4
		indices[q * 6] = v
		indices[q * 6 + 1] = v + 1
		indices[q * 6 + 2] = v + 2
		indices[q * 6 + 3] = v
		indices[q * 6 + 4] = v + 2
		indices[q * 6 + 5] = v + 3
	RenderingServer.canvas_item_add_triangle_array(_canvas.get_canvas_item(), indices, points, colors, uvs, PackedInt32Array(), PackedFloat32Array(), _deck_atlas.get_rid())
	for line: Array in lines:
		_canvas.draw_line(line[0], line[1], line[2], line[3], true)

## One sprite of the people atlas (cell `index`) as a quad, `size` across, turned to `facing`.
static func _people_quad(points: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array, at: Vector2, facing: float, size: float, index: int, color: Color) -> void:
	var x := Vector2.from_angle(facing) * size * 0.5
	var y := x.orthogonal()
	points.append(at - x - y)
	points.append(at + x - y)
	points.append(at + x + y)
	points.append(at - x + y)
	var cell := Vector2(index % int(DECK_ATLAS_CELLS.x), index / int(DECK_ATLAS_CELLS.x)) / DECK_ATLAS_CELLS
	var span := Vector2.ONE / DECK_ATLAS_CELLS
	uvs.append(cell)
	uvs.append(cell + Vector2(span.x, 0.0))
	uvs.append(cell + span)
	uvs.append(cell + Vector2(0.0, span.y))
	for k in 4:
		colors.append(color)

## The dock workers beside a ship in port (in screen space): line handlers at
## the bollards fore and aft while it comes alongside, lies there its first
## and last moments, and pulls out; a gang about the quay alongside it,
## as many as its cargo needs, through its stop.
func _draw_dock_workers(ship: Ship) -> void:
	if not _people_shown() or ship.berth < 0 or ship.is_service() and not ship.is_fishing():
		return
	var gang: Array = DOCK_GANGS.get(CrewLooks.line_of(ship.model()), [])
	if gang.is_empty():
		return
	var port := ship.docked_at
	var layout := _port_layout(port)
	if ship.berth >= layout.berths.size():
		return
	var berth: Array = layout.berths[ship.berth]
	var along: Vector2 = berth[1]
	var inward: Vector2 = berth[2]
	var quay: Vector2 = berth[4]
	var moored := _berth_spot(berth, ship)
	var half_length: float = (_model_look(ship.model_id)[7] as Rect2).size.x / 2.0
	var half_berth := float(berth[3]) / 2.0
	var offset := (moored - quay).dot(along)
	var stop := maxf(ship.dock_seconds(), 1.0)
	var lines := ship.berth_phase == Ship.BERTH_IN or ship.berth_phase == Ship.BERTH_OUT
	lines = lines or ship.is_docking() and (ship.dock_time < stop * DeckCrew.LINES_SHARE or ship.dock_time > stop * (1.0 - DeckCrew.LINES_SHARE))
	var people := []
	var facing_ship := _dock_angle(port, inward.angle())
	var now := Time.get_ticks_msec() / 1000.0
	if lines:
		for k in 4:
			var reach := (0.8 * half_length + 2.5) * (1.0 if k % 2 == 0 else -1.0) + (0.0 if k < 2 else (-1.5 if k % 2 == 0 else 1.5))
			var mark := clampf(roundf((offset + reach + half_berth - BOLLARD_STEP * 0.5) / BOLLARD_STEP), 0.0,
				floorf((2.0 * half_berth - BOLLARD_STEP * 0.8) / BOLLARD_STEP))
			var post := quay + along * (-half_berth + BOLLARD_STEP * (0.5 + mark)) - inward * DOCK_WORKER_INSET
			var seed := absi(hash([ship.id, "lines", k]))
			people.append([_dock_point(port, post + along * (0.25 if k >= 2 else -0.25)), facing_ship, CrewLooks.dock_outfit(seed), -1.0, DeckCrew.TOOL_LINE, seed])
	elif ship.is_docking():
		var tier := clampi(int(ship.model().get("tier", 1)), 1, 5)
		var count := int(gang[0]) + int(gang[1]) * (tier - 1)
		# Their stretch of quay: alongside the ship, from the edge back a little.
		var plan := {h = DOCK_WORKER_BAND.y - DOCK_WORKER_BAND.x, walk = [[0.0, 0.0, half_length * 2.0, DOCK_WORKER_BAND.y - DOCK_WORKER_BAND.x]]}
		var start := quay + along * (offset - half_length) - inward * DOCK_WORKER_BAND.x
		for k in count:
			var seed := absi(hash([ship.id, "gang", k]))
			var walking := DeckCrew._wander(plan, seed, now, float(CrewLooks.settings().walk_speed))
			var spot: Vector2 = walking[0]
			var dock_spot := start + along * spot.x - inward * spot.y
			var heading := along.rotated(float(walking[1]))
			people.append([_dock_point(port, dock_spot), _dock_angle(port, heading.angle()), CrewLooks.dock_outfit(seed), float(walking[3]), DeckCrew.TOOL_NONE, seed])
	if people.is_empty():
		return
	var scale := dock_scale(port)
	# (Drawn in screen px: the people's sizes are in ship units, so scaled to match.)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * scale)
	for person: Array in people:
		person[0] = (person[0] as Vector2) / scale
	_draw_people(people, _shadow_dir, Color.WHITE)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## A ship's shadow: cast this many of its widths away from the sun, this
## dark, once the ship is this wide on screen; and its roll: how far it shifts
## sideways (widths) and narrows as it heels, how much further its
## superstructure goes, and how the sea rolls it (radians): a calm swell
## always, more in a wind and much more in a storm.
const SHADOW_MIN_PX := 3.0
const SHIP_SHADOW_WIDTHS := 0.35
const SHIP_SHADOW_ALPHA := 0.28
const ROLL_SHIFT := 0.08
const ROLL_NARROW := 0.14
const ROLL_TOWER := 0.12
const ROLL_CALM := 0.06
const ROLL_DOCKED := 0.025
const ROLL_WIND := 0.22
const ROLL_STORM := 0.7
const ROLL_WIND_FULL := 22.0
const SEA_STATE_REFRESH_S := 2.0
var _sea_states := {}  # Ship -> [until (ticks msec), roll amplitude].

## How far a ship rolls now (radians, signed): two swells at its own phase,
## their size from the sea where it is (the wind, the storms), looked at
## again every SEA_STATE_REFRESH_S; at its berth or anchor just a ripple.
func _ship_roll(ship: Ship, at: Vector2) -> float:
	var now := Time.get_ticks_msec()
	var kept: Array = _sea_states.get(ship, [])
	var amplitude: float
	if not kept.is_empty() and now < int(kept[0]):
		amplitude = float(kept[1])
	else:
		if ship.is_docked():
			amplitude = ROLL_DOCKED + ROLL_STORM * 0.3 * _storm_strength_at_port(ship.docked_at)
		else:
			var lon_lat := Geo.unproject(screen_to_world(at))
			var wind := Wind.at(lon_lat, GameState.play_time, GameState.weather.storms).length()
			var storm := float(GameState.weather.strongest_at(lon_lat)[1]) if not GameState.weather.storms.is_empty() else 0.0
			amplitude = ROLL_CALM + ROLL_WIND * clampf(wind / ROLL_WIND_FULL, 0.0, 1.0) + ROLL_STORM * storm
		_sea_states[ship] = [now + int(SEA_STATE_REFRESH_S * 1000.0), amplitude]
	var t := now / 1000.0
	var phase := float(ship.id) * 1.7
	return amplitude * (0.7 * sin(t * 1.3 + phase) + 0.3 * sin(t * 2.9 + phase * 0.6))

## How a ship's drawing is faded: not at all for the player's own, a little
## for another player's (multiplayer).
func _ship_fade(ship: Ship) -> Color:
	return Color.WHITE if GameState.is_mine(ship) else Color(1, 1, 1, OTHER_SHIP_ALPHA)

## A ship too small on screen to make out (see TINY_SHIP_PX): a dot in its color.
func _draw_tiny_ship(at: Vector2, color: Color) -> void:
	if Rect2(Vector2.ZERO, size).has_point(at):
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		var half := _ship_dot_half()
		_canvas.draw_rect(Rect2(at - Vector2.ONE * half, Vector2.ONE * half * 2.0), color)

## Half a far-off ship's dot (px): bigger with Settings' "big_dot".
const SHIP_DOT_HALF_PX := 1.0
const SHIP_BIG_DOT_HALF_PX := 2.5
func _ship_dot_half() -> float:
	return SHIP_BIG_DOT_HALF_PX if Settings.ship_look == "big_dot" else SHIP_DOT_HALF_PX

## With Settings' "grow" ships far off never get smaller than this many px a
## dock unit: the size ships used to keep zoomed out (their map_size at 0.7),
## so their art shows; from SHIP_GROW_PORT_RADII of their marina's radius in
## to the mouth they shrink back to their true size (_ship_scale()), so they
## fit their harbour.
const SHIP_GROW_MIN_SCALE := 0.7 / SHIP_SIZE
const SHIP_GROW_PORT_RADII := Vector2(1.2, 5.0)

## How big (px a dock unit) a ship at a screen point is drawn: its true size
## (_ship_scale()), or with Settings' "grow" at least SHIP_GROW_MIN_SCALE out
## at sea, easing back to its true size near the ports at its leg's ends.
func _ship_draw_scale(ship: Ship, at: Vector2) -> float:
	var scale := _ship_scale()
	if Settings.ship_look != "grow" or scale >= SHIP_GROW_MIN_SCALE:
		return scale
	if ship.is_docked() or ship.is_carried():
		return scale if ship.is_docked() else _ship_draw_scale(ship.rescuer, at)
	var near := INF
	for port_id: String in [ship.from_port, ship.to_port]:
		if not port_id.is_empty() and not Fisheries.is_ground(port_id):
			near = minf(near, at.distance_to(port_screen_position(port_id)))
	var reach := float(_marina_layout(str(Docks.settings().get("hub_berths", "LLLLLLLLLLLLLL")), true).radius) * scale
	var t := smoothstep(reach * SHIP_GROW_PORT_RADII.x, reach * SHIP_GROW_PORT_RADII.y, near) if near < INF else 1.0
	return lerpf(scale, SHIP_GROW_MIN_SCALE, t)

## The hull in the model's color, the cargo (cut off behind how full the hold
## is, in CARGO_STEPS steps, any cargo showing at least one) and the details.
func _draw_ship_art(ship: Ship, art: Dictionary, rect: Rect2, color: Color, fade := Color.WHITE, lean := 0.0) -> void:
	_canvas.draw_texture_rect(art.hull, rect, false, color)
	# Its superstructure and details lean further than the hull as it rolls (they stand up).
	rect = Rect2(rect.position + Vector2(0.0, lean * rect.size.y * ROLL_TOWER), rect.size)
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
	# A fishing boat at work has its gear rigged (rods out, outriggers spread:
	# <art>_details_fishing.svg); otherwise it's stowed.
	var rigged: bool = art.has("fishing_details") and ship != null and ship.is_working_ground()
	_canvas.draw_texture_rect(art.fishing_details if rigged else art.details, rect, false, fade)

## The skin the player's ships of a model wear (the equipped skin pack's: see
## Cosmetics.ship_skin()), or null: other players' and the rivals' ships are
## drawn as they are.
func _ship_skin(ship: Ship) -> Texture2D:
	if Cosmetics.equipped.is_empty() or GameState.owner_of(ship) != GameState.company:
		return null
	return Cosmetics.ship_skin(ship.model_id)

## A skin in place of a ship's art: the one picture, in its own colours (no
## hull tint, cargo or details), leaning a little with the roll like a superstructure.
func _draw_ship_skin(skin: Texture2D, rect: Rect2, fade: Color, lean: float) -> void:
	_canvas.draw_texture_rect(skin, Rect2(rect.position + Vector2(0.0, lean * rect.size.y * ROLL_TOWER * 0.5), rect.size), false, fade)

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
	if ResourceLoader.exists(path % "details_fishing"):
		art.fishing_details = load(path % "details_fishing")  # (Its gear rigged, fishing: see _draw_ship_art().)
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
			load_ship_art(str(model.get("art", model.get("category", "")))),  # (A model with its own art names it: the fishing boats.)
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
			if storm.has("sender"):
				var sent := "sent by %s" % storm.sender
				var sent_width := font.get_string_size(sent, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE - 3).x
				var under := baseline + Vector2((width - sent_width) / 2.0, STORM_FONT_SIZE)
				_canvas.draw_string_outline(font, under, sent, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE - 3, 4, Color(0, 0, 0, 0.6 * alpha))
				_canvas.draw_string(font, under, sent, HORIZONTAL_ALIGNMENT_LEFT, -1, STORM_FONT_SIZE - 3, DIVINE_GOLD * Color(1, 1, 1, 0.9 * alpha))

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

# --- Divine Actions -----------------------------------------------------------

const DIVINE_GOLD := Color(1.0, 0.85, 0.3)
## A plague of gulls: this many gulls wheel over the port, this wide (marina radii).
const PLAGUE_GULLS := 36
const PLAGUE_REACH := 1.6
## A deluge: this many rain streaks over the port each frame.
const DELUGE_STREAKS := 40
## The Kraken: its arms.
const KRAKEN_ARMS := 7
## A comet crossing the sky over its day (off one side to off the other), and its tail (px).
const COMET_TAIL := 160.0

## The effects of divine acts (GameState.divine.effects) over the map: gulls
## wheeling over a plagued port, rain over a deluged one, a great flock's ring
## over a sea-changed one, the Kraken's arms round a taken ship, lightning on
## a struck hub, and the comet on its day.
func _draw_divine() -> void:
	var divine: Divine = GameState.divine
	if not divine.on:
		return
	var t := GameState.play_time
	var area := Rect2(Vector2.ZERO, size).grow(200.0)
	for effect: Dictionary in divine.effects:
		var kind := str(effect.kind)
		if kind == "fair_winds":
			continue
		var center: Vector2
		if kind == "kraken":
			var ship := GameState.ship_by_id(int(effect.ship))
			if ship == null:
				continue
			center = ship_screen_position(ship)
		else:
			center = port_screen_position(str(effect.port))
		if not area.has_point(center):
			continue
		var reach := float(_port_layout(str(effect.port)).radius) * _ship_scale() if kind != "kraken" else 0.0
		var since := t - float(effect.since)
		match kind:
			"plague":
				_draw_gull_mob(center, maxf(reach * PLAGUE_REACH, 24.0), t, PLAGUE_GULLS, Color(0.95, 0.95, 0.95, 0.9))
			"sea_change":
				_draw_gull_mob(center, maxf(reach * 1.2, 18.0), t * 0.5, 20, DIVINE_GOLD * Color(1, 1, 1, 0.8))
			"deluge":
				_draw_rain(center, maxf(reach * 1.5, 24.0), t)
			"kraken":
				_draw_kraken(center, since, float(effect.until) - t)
			"lightning":
				_draw_strike(center, since, float(effect.until) - float(effect.since))
	if divine.comet_up():
		_lights_layer.queue_redraw()  # (The comet is drawn there, above the night: see _draw_lights().)


## Gulls wheeling in a ring (each on its own circle, bobbing), as a mob of
## small bent-wing marks.
func _draw_gull_mob(center: Vector2, reach: float, t: float, count: int, color: Color) -> void:
	var span := clampf(reach * 0.12, 4.0, 9.0)
	for i in count:
		var seed := float(i) * 1.618
		var angle := t * (0.5 + fmod(seed, 0.5)) * (1.0 if i % 2 == 0 else -1.0) + seed * TAU
		var r := reach * (0.4 + fmod(seed * 0.37, 0.6))
		var at := center + Vector2.from_angle(angle) * r + Vector2(0.0, sin(t * 3.0 + seed) * 3.0)
		var flap := sin(t * 10.0 + seed * 7.0) * 0.5
		var wing := Vector2.from_angle(angle + PI / 2.0) * span
		var lift := Vector2(0.0, -span * (0.35 + flap * 0.3))
		_canvas.draw_polyline(PackedVector2Array([at - wing + lift, at, at + wing + lift]), color, 1.5, true)


## Rain over a port: slanting streaks falling through a dark cloud.
func _draw_rain(center: Vector2, reach: float, t: float) -> void:
	_canvas.draw_circle(center, reach, Color(0.1, 0.12, 0.18, 0.35))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fall := Vector2(-0.3, 1.0).normalized()
	for i in DELUGE_STREAKS:
		var where := center + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * reach
		if where.distance_to(center) > reach:
			continue
		var phase := fmod(t * 2.5 + rng.randf(), 1.0)
		var at := where + fall * (phase - 0.5) * reach * 0.6
		_canvas.draw_line(at, at + fall * clampf(reach * 0.12, 4.0, 12.0), Color(0.7, 0.8, 1.0, 0.6), 1.2, true)


## The Kraken's arms rising round a ship and sinking back as the effect ends.
func _draw_kraken(center: Vector2, since: float, left: float) -> void:
	var rise := minf(since / 2.0, 1.0) * minf(left / 3.0, 1.0)
	if rise <= 0.0:
		return
	var length := clampf(_ship_scale() * 44.0, 26.0, 120.0) * rise
	var ink := Color(0.25, 0.12, 0.3, 0.95)
	_canvas.draw_circle(center, length * 0.45, Color(0.1, 0.05, 0.15, 0.35 * rise))
	for i in KRAKEN_ARMS:
		var base := TAU * i / KRAKEN_ARMS + since * 0.3
		var arm := PackedVector2Array([center + Vector2.from_angle(base) * length * 0.25])
		for k in range(1, 7):
			var s := float(k) / 6.0
			var bend := sin(since * 2.0 + i * 1.3 + s * 4.0) * 0.6 * s
			arm.append(center + Vector2.from_angle(base + bend) * length * (0.25 + s * 0.75))
		_canvas.draw_polyline(arm, ink, maxf(length * 0.12 * (1.0 - 0.5 * rise), 2.0), true)
		for k in range(2, 7, 2):
			_canvas.draw_circle(arm[k], maxf(length * 0.04, 1.5), Color(0.9, 0.75, 0.8, 0.8))


## A lightning strike on a hub: a bolt down from above, and a flash that fades.
func _draw_strike(center: Vector2, since: float, length_s: float) -> void:
	var fade := 1.0 - clampf(since / length_s, 0.0, 1.0)
	if fade <= 0.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(floor(since * 8.0))
	var top := center + Vector2(rng.randf_range(-30.0, 30.0), -220.0)
	var bolt := PackedVector2Array([top])
	for k in range(1, 9):
		bolt.append(top.lerp(center, float(k) / 8.0) + Vector2(rng.randf_range(-18.0, 18.0), 0.0) * (1.0 if k < 8 else 0.0))
	_canvas.draw_circle(center, 60.0 * fade, Color(1.0, 0.95, 0.7, 0.25 * fade))
	_canvas.draw_polyline(bolt, Color(1.0, 0.9, 0.5, 0.5 * fade), 7.0, true)
	_canvas.draw_polyline(bolt, Color(1.0, 1.0, 1.0, fade), 2.5, true)


## The comet: a bright head with a long tail, crossing the top of the screen
## over its day, left to right by the calendar's time of day (on screen, not on the globe).
func _draw_comet(_t: float) -> void:
	var across := fposmod(float(GameState.calendar_time()), 86400.0) / 86400.0 * 1.4 - 0.2
	var head := Vector2(size.x * across, size.y * (0.08 + 0.08 * across))
	var tail := head + Vector2(-COMET_TAIL, -COMET_TAIL * 0.35)
	for i in 6:
		var s := float(i) / 6.0
		_canvas.draw_line(head.lerp(tail, s), head.lerp(tail, s + 1.0 / 6.0), Color(0.8, 0.9, 1.0, 0.5 * (1.0 - s)), 6.0 * (1.0 - s) + 1.0, true)
	_canvas.draw_circle(head, 5.0, Color(1.0, 1.0, 0.9, 0.9))
	_canvas.draw_circle(head, 11.0, Color(0.8, 0.9, 1.0, 0.25))

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
	# Each kind's seasonal versions (see _update_seasons()), after all the kinds.
	for kind in data.decor_kind_names.size():
		for suffix: String in SEASON_SUFFIXES:
			var path: String = DECOR_ART_DIR + data.decor_kind_names[kind] + "_" + suffix + ".svg"
			if ResourceLoader.exists(path):
				if not _decor_variants.has(kind):
					_decor_variants[kind] = {}
				_decor_variants[kind][suffix] = _decor_textures.size()
				_decor_textures.append(load(path))
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
	_build_decor_atlas()

## The land drawings' art in one texture (for DecorSim.set_atlas()): drawn
## from it, all the drawings in view go down as one draw call, not one a
## drawing (sorted by depth, they come one art after another). Each sits in
## DECOR_ATLAS_PAD px of clear space, so its smaller mipmaps never pick up a
## neighbour. Rows, tallest first.
const DECOR_ATLAS_WIDTH := 2048
const DECOR_ATLAS_MAX_HEIGHT := 4096
const DECOR_ATLAS_PAD := 16
static func _build_decor_atlas() -> void:
	var images := []
	for texture in _decor_textures:
		var image: Image = texture.get_image() if texture != null else null
		if image != null:
			if image.is_compressed():
				image.decompress()
			image.convert(Image.FORMAT_RGBA8)
		images.append(image)
	var order := range(images.size()).filter(func(i: int) -> bool: return images[i] != null)
	order.sort_custom(func(a: int, b: int) -> bool: return (images[a] as Image).get_height() > (images[b] as Image).get_height())
	var places := {}
	var x := 0
	var y := 0
	var row_h := 0
	for i: int in order:
		var image: Image = images[i]
		var w := image.get_width() + 2 * DECOR_ATLAS_PAD
		var h := image.get_height() + 2 * DECOR_ATLAS_PAD
		if x + w > DECOR_ATLAS_WIDTH:
			y += row_h
			x = 0
			row_h = 0
		places[i] = Vector2i(x, y)
		x += w
		row_h = maxi(row_h, h)
	var height := y + row_h
	if places.is_empty() or height > DECOR_ATLAS_MAX_HEIGHT:
		return  # (Drawn from their own textures.)
	var atlas := Image.create_empty(DECOR_ATLAS_WIDTH, height, false, Image.FORMAT_RGBA8)
	var regions := []
	regions.resize(images.size())
	regions.fill(Rect2())
	for i: int in places:
		var image: Image = images[i]
		var at: Vector2i = places[i] + Vector2i.ONE * DECOR_ATLAS_PAD
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		regions[i] = Rect2(Vector2(at), Vector2(image.get_size()))
	atlas.generate_mipmaps()
	_decor_atlas = ImageTexture.create_from_image(atlas)
	_decor_atlas_regions = regions

## The drawings on the land (WorldMapData decor: mountains, stands of trees,
## grass, scrub, cacti, rocks, dunes, polar waves), on the full-color map
## only, each its size in the world (DECOR_KM) standing on its spot, the
## nearer ones (lower on screen) in front. Only while all of it fits clear of
## the water (land drawings on land, waves on the sea): its distance to the
## nearest shore (decor_clearance, worked out by the map tool) at least half
## its size. Not in locked regions (shaded, bare).
func _draw_decor() -> void:
	_canvas = _decor_layer
	if gray_mode:
		return
	var data := GameData.world_map
	var km := _zoom / KM_PER_DEGREE
	var kind_sides := PackedFloat64Array()
	var largest := 0.0
	for kind_name in data.decor_kind_names:
		var side := float(DECOR_KM.get(kind_name, 0.0)) * km
		kind_sides.append(side)
		largest = maxf(largest, side)
	if largest < DECOR_MIN_PX:
		return
	# The cells that can be in view: those within the stretch of globe the
	# view's corners reach (all of the near side, zoomed right out).
	var reach := rad_to_deg(asin(minf(size.length() / 2.0 / _radius(), 1.0))) + largest / _zoom + _decor_reach_pad()
	var across := 180.0
	if absf(_view_lat) + reach < 89.0:
		across = rad_to_deg(asin(minf(sin(deg_to_rad(minf(reach, 90.0))) / cos(deg_to_rad(_view_lat)), 1.0)))
		if reach >= 90.0:
			across = 180.0
	var low := Vector2(_view_lon - across, _mercator_y(_view_lat - reach))
	var high := Vector2(_view_lon + across, _mercator_y(_view_lat + reach))
	var columns := ceili(Geo.WORLD_WIDTH / DECOR_BUCKET)
	var shown := []  # [screen position, kind, side]
	var screen := Rect2(Vector2.ZERO, size).grow(largest)
	var first_column := floori((low.x + 180.0) / DECOR_BUCKET)
	var last_column := mini(floori((high.x + 180.0) / DECOR_BUCKET), first_column + columns - 1)
	# How many of the four tiers each kind shows at this size (all from DECOR_FULL_PX).
	var kind_tiers := PackedInt32Array()
	for side in kind_sides:
		kind_tiers.append(0 if side < DECOR_MIN_PX else clampi(1 + floori((side - DECOR_MIN_PX) / (DECOR_FULL_PX - DECOR_MIN_PX) * 3.0), 1, 4))
	var check_locks := RegionMap.is_ready() and selectable_ports.is_empty()
	var locks := {}  # Region (as _decor_regions has it) -> locked.
	if check_locks:
		_decor_locked(0)  # (Sorts the drawings into their regions, the first time.)
	# Natively (DecorSim: the same drawings, places and order) where the library's there.
	if _decor_native == null and ClassDB.class_exists(&"DecorSim"):
		var textures := []
		for texture in _decor_textures:
			textures.append(texture.get_rid() if texture != null else RID())
		_decor_native = ClassDB.instantiate(&"DecorSim")
		_decor_native.setup(data.decor_positions, _decor_units, PackedInt32Array(Array(data.decor_kinds)), PackedInt32Array(Array(data.decor_tiers)),
			_decor_room, textures, DECOR_BUCKET)
		if _decor_atlas != null and _decor_native.has_method(&"set_atlas"):
			_decor_native.set_atlas(_decor_atlas.get_rid(), _decor_atlas_regions, Vector2(_decor_atlas.get_size()))
		if not _season.is_empty() and _decor_native.has_method(&"set_seasons"):
			_decor_native.set_seasons(_season[0], _season[1])
	if _decor_native != null:
		var locked := PackedByteArray()
		if check_locks:
			if not _decor_regions_native:
				_decor_native.set_regions(_decor_regions)
				_decor_regions_native = true
			var regions: Array = GameData.markets.get("regions", [])
			locked.resize(regions.size() + 1)
			for r in regions.size():
				locked[r + 1] = 0 if GameState.is_region_unlocked(RegionMap.region_id(r)) else 1
		_decor_native.draw(_canvas.get_canvas_item(), {right = _right, up = _up, toward = _toward, radius = _radius(), middle = size / 2.0,
			screen = screen, zoom = _zoom, sides = kind_sides, tiers = kind_tiers, columns = Vector2i(first_column, last_column),
			rows = Vector2i(floori(low.y / DECOR_BUCKET), floori(high.y / DECOR_BUCKET)), locked = locked, rescan = _decor_rescan()})
		return
	for column in range(first_column, last_column + 1):
		for row in range(floori(low.y / DECOR_BUCKET), floori(high.y / DECOR_BUCKET) + 1):
			for i: int in _decor_buckets.get(Vector2i(posmod(column, columns), row), PackedInt32Array()):
				var kind := data.decor_kinds[i]
				if data.decor_tiers[i] >= kind_tiers[kind]:
					continue  # Too small to show (or thinned out at this size), or an animal.
				var side := kind_sides[kind]
				if _decor_room[i] * _zoom < side * 0.5:
					continue  # Would reach into the water (or onto the land).
				if check_locks:
					var region: int = _decor_regions[i]
					if not locks.has(region):
						locks[region] = _decor_locked(i)
					if locks[region]:
						continue  # Its region is locked: shaded, bare.
				var at := _unit_to_screen(_decor_units[i])
				if not screen.has_point(at):
					continue
				shown.append([at, kind, side, _decor_texture_now(i, kind)])
	shown.sort_custom(func(p: Array, q: Array) -> bool: return p[0].y < q[0].y)
	for item: Array in shown:
		var texture := _decor_textures[item[3]]
		if texture == null:
			continue
		var side: float = item[2]
		_canvas.draw_texture_rect(texture, Rect2(item[0] - Vector2(side / 2.0, side * 0.92), Vector2(side, side)), false)

## Whether the native decor pass scans its cells again this frame (see
## DecorSim.draw()): zooming, or every DECOR_RESCAN_FRAMES as the map moves;
## between, the last scan's drawings are put on screen again. The scan
## reaches DECOR_RESCAN_FRAMES of the view's last move further
## (_decor_reach_pad()), so nothing pops in at the edge meanwhile.
const DECOR_RESCAN_FRAMES := 4
var _decor_scan_frame := -100
var _decor_scan_zoom := -1.0
var _decor_scan_toward := Vector3.ZERO
var _decor_scan_pad := 0.0
func _decor_rescan() -> bool:
	var frame := Engine.get_process_frames()
	if _zoom != _decor_scan_zoom or frame - _decor_scan_frame >= DECOR_RESCAN_FRAMES or _decor_scan_frame > frame:
		var moved := rad_to_deg(_toward.angle_to(_decor_scan_toward)) if _decor_scan_toward != Vector3.ZERO else 0.0
		var frames := maxi(frame - _decor_scan_frame, 1)
		_decor_scan_pad = moved / frames * DECOR_RESCAN_FRAMES
		_decor_scan_frame = frame
		_decor_scan_zoom = _zoom
		_decor_scan_toward = _toward
		return true
	return false

func _decor_reach_pad() -> float:
	return _decor_scan_pad

## A land drawing's art by its name (as _load_decor() loaded it), or null.
static func _decor_texture(kind_name: String) -> Texture2D:
	var index := GameData.world_map.decor_kind_names.find(kind_name)
	return _decor_textures[index] if index >= 0 and index < _decor_textures.size() else null

## The wildlife (Wildlife) in view, at its size in the world (it grows and
## shrinks with the map, like the ships): the birds' homes along the shore
## either side of each port (a gull colony or cormorant colony at the water's
## edge, an eyrie or heronry in the trees inland...), and the land animals'
## homes (dens, caves, burrows, nests, rookeries, waterholes...) with each
## animal of each group drawn from above, turned the way it's heading, stepping
## as it walks, dimmed asleep; a den with its family asleep inside gets its
## z's. Not in locked regions. Remembers what's where for clicks
## (_animals_at(), _home_at()). Drawn every frame while any shows.
func _draw_wildlife() -> void:
	_canvas = _fauna_layer
	_fauna_hits.clear()
	_wildlife_shown = false
	if gray_mode:
		return
	var km := _zoom / KM_PER_DEGREE
	var wildlife := Wildlife.shared()
	var home_km := float(wildlife.birds_data.get("home_km", 5.0))
	if WILDLIFE_LARGEST_KM * km < WILDLIFE_MIN_PX:
		return
	_wildlife_shown = true
	var cal := float(GameState.calendar_time())
	var reach := Rect2(Vector2.ZERO, size).grow(60.0)
	var check_locks := RegionMap.is_ready() and selectable_ports.is_empty()
	# The birds' homes, port by port.
	var home_side := home_km * km
	if home_side >= WILDLIFE_HOME_MIN_PX:
		for i in _ports_near_view():
			var port_id: String = GameData.ports[i].id
			if _port_locked(port_id) or not reach.has_point(port_screen_position(port_id)):
				continue
			var colonies := wildlife.colonies_at(port_id)
			for k in colonies.size():
				var index: int = colonies[k]
				var colony: Dictionary = wildlife.colonies[index]
				var at := _colony_home_screen(port_id, colony)
				if not reach.has_point(at):
					continue
				var texture := _wildlife_texture("home_" + str(colony.home_kind))
				if texture != null:
					_canvas.draw_texture_rect(texture, Rect2(at - Vector2.ONE * home_side / 2.0, Vector2.ONE * home_side), false)
				_fauna_hits.append([at, maxf(home_side * 0.5, BIRD_HIT_MIN_PX), "colony", index])
	# The land animals and their homes: natively (LandSim) where the library's there.
	if _land_sim == null and ClassDB.class_exists(&"LandSim"):
		_land_sim = ClassDB.instantiate(&"LandSim")
		_land_sim.setup(wildlife.groups, wildlife.land, wildlife.migrate_days, _land_texture, _land_region)
	if _land_sim != null:
		var unlocked: Variant = null
		if check_locks:
			unlocked = {"": true}  # (GameState.is_region_unlocked().)
			for region: String in GameState.regions:
				unlocked[region] = true
		_fauna_hits.append_array(_land_sim.draw(_canvas.get_canvas_item(), {box = _view_lon_lat_box(), reach = reach,
			right = _right, up = _up, toward = _toward, radius = _radius(), middle = size / 2.0, km = km, home_side = home_side,
			home_min_px = WILDLIFE_HOME_MIN_PX, min_px = WILDLIFE_MIN_PX, stride_s = WILDLIFE_STRIDE_S, cal = cal,
			life_time = wildlife.life_time, unlocked = unlocked, font = get_theme_default_font()}))
		return
	var items := []  # [y, texture, middle, angle, side, tint]
	for gi: int in wildlife.groups_in(_view_lon_lat_box()):
		var group: Dictionary = wildlife.groups[gi]
		if check_locks and not GameState.is_region_unlocked(RegionMap.region_id(RegionMap.region_at(group.home))):
			continue
		var in_den := false
		if group.home_kind != "none" and home_side >= WILDLIFE_HOME_MIN_PX:
			var home_at := world_to_screen(Geo.project(group.home))
			if not _is_hidden(home_at) and reach.has_point(home_at):
				var side := home_side * 1.3
				var texture := _wildlife_texture("home_" + str(group.home_kind))
				if texture != null:
					items.append([home_at.y - side, texture, home_at, 0.0, side, Color.WHITE])
				_fauna_hits.append([home_at, maxf(side * 0.5, BIRD_HIT_MIN_PX), "home", gi])
		for m in int(group.members):
			var state := wildlife.land_state(group, m, cal)
			if state.mode == "den":
				in_den = true
				continue
			var at := world_to_screen(Geo.project(state.pos))
			if _is_hidden(at) or not reach.has_point(at):
				continue
			var side := float(state.size) * km
			if side < WILDLIFE_MIN_PX:
				continue
			# Its heading on screen: a step that way on the map.
			var heading := float(state.heading)
			var ahead := world_to_screen(Geo.project(Vector2(state.pos.x + cos(heading) * 0.01 / maxf(cos(deg_to_rad(state.pos.y)), 0.1), state.pos.y + sin(heading) * 0.01)))
			var angle := (ahead - at).angle() if not _is_hidden(ahead) else 0.0
			var walking: bool = state.mode == "walk"
			var stepping := walking and fmod(wildlife.life_time / WILDLIFE_STRIDE_S + m * 0.37, 1.0) < 0.5
			var texture := _wildlife_texture(str(group.species) + ("_step" if stepping else ""))
			if texture == null:
				continue
			var tint := Color(0.78, 0.8, 0.88) if state.mode == "sleep" else Color.WHITE
			items.append([at.y, texture, at, angle, side, tint])
			_fauna_hits.append([at, maxf(side * 0.6, BIRD_HIT_MIN_PX), "group", gi])
		if in_den and home_side >= WILDLIFE_HOME_MIN_PX:
			var home_at := world_to_screen(Geo.project(group.home))
			if not _is_hidden(home_at):
				items.append([home_at.y + 1.0, null, home_at, 0.0, home_side, Color.WHITE])
	items.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var font := get_theme_default_font()
	for item: Array in items:
		var at: Vector2 = item[2]
		var side: float = item[4]
		if item[1] == null:
			# A den with its family asleep inside: z's rising.
			var z := maxf(side * 0.3, 8.0)
			_canvas.draw_string(font, at + Vector2(side * 0.2, -side * 0.3), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(z), Color(1, 1, 1, 0.85))
			_canvas.draw_string(font, at + Vector2(side * 0.35, -side * 0.55), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(z * 0.75), Color(1, 1, 1, 0.7))
			continue
		_canvas.draw_set_transform(at, float(item[3]), Vector2.ONE * side / 64.0)
		_canvas.draw_texture_rect(item[1], Rect2(-32.0, -32.0, 64.0, 64.0), false, item[5])
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## Where a bird colony's home is on screen: one of the spots along the shore
## either side of its port (_shore_spots()), picked by the colony: at the
## water's edge for gulls, cormorants and seabirds, inland (in the trees or
## the reeds) for the rest when there's land there.
func _colony_home_screen(port_id: String, colony: Dictionary) -> Vector2:
	return _dock_point(port_id, _colony_home_local(port_id, colony))


## Where a bird colony's home is round its port (dock units: see _colony_home_screen()).
func _colony_home_local(port_id: String, colony: Dictionary) -> Vector2:
	var shores := _shore_spots(port_id)
	var radius := float(_port_layout(port_id).radius)
	if shores.is_empty():
		var side := 1.0 if Birds.chance([colony.key, "side"]) < 0.5 else -1.0
		return Vector2(radius * 0.3, side * radius * (1.4 + 0.6 * Birds.chance([colony.key, "far"])))
	var spot: Array = shores[floori(Birds.chance([colony.key, "home"]) * shores.size()) % shores.size()]
	var shore_kinds := ["gull_colony", "cormorant_colony", "seabird_colony", "burrow"]
	return spot[0] if shore_kinds.has(colony.home_kind) or spot[1] == Vector2.INF else spot[1]

## The box of (lon, lat) the screen itself shows, `margin` px past its edges
## (traced round them): much tighter than _view_lon_lat_box() zoomed in. That
## box instead when the globe's edge or a pole is in view.
func _screen_lon_lat_box(margin: float) -> Rect2:
	var rect := Rect2(Vector2.ZERO, size).grow(margin)
	var middle := size / 2.0
	var reach := _radius() * 0.95
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for corner: Vector2 in corners:
		if corner.distance_to(middle) >= reach:
			return _view_lon_lat_box(margin / maxf(_zoom, 0.01))
	for pole: float in [1.0, -1.0]:
		if rect.has_point(_unit_to_screen(Vector3(0.0, 0.0, pole))):
			return _view_lon_lat_box(margin / maxf(_zoom, 0.01))
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for s in SCREEN_BOX_STEPS:
			var spot := _screen_lon_lat(a.lerp(b, float(s) / SCREEN_BOX_STEPS))
			spot.x = wrapf(spot.x - _view_lon, -180.0, 180.0) + _view_lon  # (Round the back of the date line, near the view.)
			low = low.min(spot)
			high = high.max(spot)
	var box := Rect2(low, high - low)
	return box.grow_individual(box.size.x * 0.02, box.size.y * 0.02, box.size.x * 0.02, box.size.y * 0.02)


## The box of (lon, lat) the view can show (all of the near side, zoomed right
## out), and `margin` degrees round it.
func _view_lon_lat_box(margin := 1.0) -> Rect2:
	var reach := rad_to_deg(asin(minf(size.length() / 2.0 / _radius(), 1.0))) + margin
	var across := 180.0
	if absf(_view_lat) + reach < 89.0 and reach < 90.0:
		across = rad_to_deg(asin(minf(sin(deg_to_rad(reach)) / cos(deg_to_rad(_view_lat)), 1.0)))
	return Rect2(Vector2(_view_lon - across, _view_lat - reach), Vector2(across * 2.0, reach * 2.0))

## For the native land animals (LandSim): a wildlife drawing's texture, by name.
func _land_texture(name: String) -> RID:
	var texture := _wildlife_texture(name)
	return texture.get_rid() if texture != null else RID()


## For the native land animals: the region a spot is in (its id), or null till the regions are ready.
func _land_region(spot: Vector2) -> Variant:
	if not RegionMap.is_ready():
		return null
	return RegionMap.region_id(RegionMap.region_at(spot))


## A wildlife drawing (art/wildlife/<name>.svg), loaded once, or null.
## Every wildlife drawing loaded at the start (a load on first sight was a hitch of tens of ms).
static func _load_wildlife_art() -> void:
	for file: String in DirAccess.get_files_at(WILDLIFE_ART_DIR):
		var name := file
		if name.get_extension() in ["import", "remap"]:
			name = name.get_basename()
		if name.get_extension() == "svg":
			_wildlife_texture(name.get_basename())

static func _wildlife_texture(name: String) -> Texture2D:
	if not _wildlife_art.has(name):
		var path := WILDLIFE_ART_DIR + name + ".svg"
		_wildlife_art[name] = load(path) if ResourceLoader.exists(path) else null
	return _wildlife_art[name]

## The land animal group drawn under a screen point (the nearest one in
## front): [group (its index, as text), species], or [].
func _animals_at(screen_pos: Vector2) -> Array:
	for i in range(_fauna_hits.size() - 1, -1, -1):
		var hit: Array = _fauna_hits[i]
		if hit[2] == "group" and (hit[0] as Vector2).distance_to(screen_pos) <= float(hit[1]):
			return [str(hit[3]), str(Wildlife.shared().groups[hit[3]].species)]
	return []

## The home drawn under a screen point: ["colony" or "home", index (of the
## colony or land group)], or [].
func _home_at(screen_pos: Vector2) -> Array:
	for i in range(_fauna_hits.size() - 1, -1, -1):
		var hit: Array = _fauna_hits[i]
		if hit[2] != "group" and (hit[0] as Vector2).distance_to(screen_pos) <= float(hit[1]):
			return [hit[2], hit[3]]
	return []

## Where a land animal group is on screen (its first member), or Vector2.INF
## while it's round the far side.
func animal_group_screen_position(key: String) -> Vector2:
	var wildlife := Wildlife.shared()
	var index := int(key)
	if index < 0 or index >= wildlife.groups.size():
		return Vector2.INF
	var state := wildlife.land_state(wildlife.groups[index], 0, float(GameState.calendar_time()))
	var at := world_to_screen(Geo.project(state.pos))
	return Vector2.INF if _is_hidden(at) else at

## Where a home is on screen (see _home_at()), or Vector2.INF.
func home_screen_position(kind: String, index: int) -> Vector2:
	var wildlife := Wildlife.shared()
	var at := Vector2.INF
	if kind == "colony":
		var colony: Dictionary = wildlife.colonies[index]
		at = _colony_home_screen(colony.port, colony)
	else:
		at = world_to_screen(Geo.project(wildlife.groups[index].home))
	return Vector2.INF if _is_hidden(at) else at

# --- Sea animals -------------------------------------------------------------------

## Sea animals (SeaLife) show from this zoom in (px per degree), and their art
## is in SEA_ART_DIR (drawn head to the right, SEA_ART_ASPECT long for its
## width). Under water an animal is a pale blue-grey shape (SEA_SHADOW, as one looks through the sea); now and
## then a whale or orca comes up to breathe (SEA_SURFACE_S, with a blow) or
## breaches (SEA_BREACH_S, with a splash), and dolphins leap (SEA_LEAP_S); the
## fish, sharks, seals, sea lions and otters do the same by their kind (see
## _sea_leaps(), _sea_blows()).
## The selected or hovered pod's year of routes shows dashed (SEA_ROUTE_COLOR).
const SEA_LIFE_MIN_ZOOM := 10.0
## How long (s of play) a pod's worked-out state is kept (see _draw_sea_life()).
const POD_STATE_S := 0.4
var _pod_states := {}  # Pod index -> [calendar time it's stale at near the view, when its stay ends, state].
## How many pods are looked at a frame for a stay that's ended, and how many
## of those are worked out afresh (see _draw_sea_life()).
const POD_SCAN_PER_FRAME := 48
const POD_MOVES_PER_FRAME := 6
var _pod_cursor := 0
## The pods the library drew this frame: [index, x, y, reach] each (see _pod_hit_list()).
var _pod_hit_data := PackedFloat32Array()
var _sea_longest := 0.0
## No sea life while even the longest animal is under this (px): nothing to see.
const SEA_LIFE_MIN_PX := 3.0
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
	_pod_hit_data = PackedFloat32Array()
	if gray_mode or _zoom < SEA_LIFE_MIN_ZOOM or _sea_warming:  # (They show once their paths are found.)
		return
	var sea := SeaLife.shared()
	var scale := _animal_scale()
	if _sea_longest_px(sea) * scale < SEA_LIFE_MIN_PX:
		return  # (Even the biggest animal's too small to make out.)
	var now := float(GameState.calendar_time())
	for highlight in [selected_pod, _hovered_pod]:
		if highlight >= 0 and highlight < sea.pods.size():
			_draw_pod_routes(sea, highlight)
	if _sea_painter == null and ClassDB.class_exists(&"SeaPainter"):
		_sea_painter = ClassDB.instantiate(&"SeaPainter")
	if _sea_painter == null:
		_draw_sea_life_in_gdscript(sea, now, scale)
		return
	# The pods natively (SeaPainter: the same ones, the same ways). Each is
	# worked out here (where it is, which way: sea.state()) when it's near the
	# view and its last state is POD_STATE_S old, and wherever it is once its
	# stay in an area ends (looked at a few a frame, in turn); the library
	# keeps them, finds the ones in view and draws them.
	_sea_painter.set_count(sea.pods.size())
	var params := {right = _right, up = _up, toward = _toward, radius = _radius(), middle = size / 2.0,
		view_angle = asin(minf((size.length() / 2.0 + 80.0) / _radius(), 1.0)), view = Rect2(Vector2.ZERO, size).grow(80.0),
		play_time = GameState.play_time, scale = scale, mask = sea._mask, mask_size = sea._mask_size, hit_min_px = SEA_HIT_MIN_PX}
	for i: int in _sea_painter.near(params):
		var kept: Array = _pod_states.get(i, [])
		if kept.is_empty() or now >= float(kept[0]):
			_refresh_pod(sea, i, now)
	var scanned := 0
	var moved := 0
	while scanned < POD_SCAN_PER_FRAME and moved < POD_MOVES_PER_FRAME and not sea.pods.is_empty():
		_pod_cursor = (_pod_cursor + 1) % sea.pods.size()
		scanned += 1
		var kept: Array = _pod_states.get(_pod_cursor, [])
		if not kept.is_empty() and now >= float(kept[1]):
			_refresh_pod(sea, _pod_cursor, now)
			moved += 1
	_pod_hit_data = _sea_painter.draw_pods(_canvas.get_canvas_item(), _sea_kinds, params)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## A pod worked out afresh (see _draw_sea_life()): its state kept till it's
## POD_STATE_S old (for while it's near the view) and till its stay ends
## (wherever it is), and given to the library with the cap it stays within
## meanwhile (its area while it stays there; just its spot on the move).
func _refresh_pod(sea: SeaLife, i: int, now: float) -> void:
	var pod: Dictionary = sea.pods[i]
	var kind: Dictionary = sea.species[pod.species]
	var state := sea.state(i, now)
	var refresh_at := now + POD_STATE_S * float(GameState.calendar_seconds_per_second())
	var unit := _unit(Geo.project(state.pos))
	var cap := unit
	var margin := 0.0
	var until := refresh_at
	if not state.migrating:
		var area: Dictionary = sea.areas[state.area]
		cap = _unit(Geo.project(Vector2(float(area.lon), float(area.lat))))
		margin = deg_to_rad(float(area.radius_nm) / 60.0 + 0.1)
		until = float(state.until)
	_pod_states[i] = [refresh_at, until, state]
	_sea_painter.set_pod(i, unit, cap, margin, state.heading, _sea_kind_index(pod.species, kind), mini(int(pod.size), int(kind.shown)))

## The longest any sea animal is drawn (length_px), for skipping them all when
## even that's under SEA_LIFE_MIN_PX.
func _sea_longest_px(sea: SeaLife) -> float:
	if _sea_longest <= 0.0:
		for kind: Dictionary in sea.species.values():
			_sea_longest = maxf(_sea_longest, float(kind.get("length_px", 0.0)))
	return _sea_longest

## The pods drawn this frame, for clicks: [index, middle on screen, reach px] each
## (from the library's hits, when it drew them).
func _pod_hit_list() -> Array:
	if _pod_hits.is_empty() and not _pod_hit_data.is_empty():
		for k in range(0, _pod_hit_data.size() - 3, 4):
			_pod_hits.append([int(_pod_hit_data[k]), Vector2(_pod_hit_data[k + 1], _pod_hit_data[k + 2]), float(_pod_hit_data[k + 3])])
	return _pod_hits

## The sea life drawn in GDScript, without the library: every pod looked at,
## its animals drawn one by one (see _draw_sea_animal()).
func _draw_sea_life_in_gdscript(sea: SeaLife, now: float, scale: float) -> void:
	var view := Rect2(Vector2.ZERO, size).grow(80.0)
	# A pod staying in an area is within its radius till it leaves (its state's
	# until): skipped till then while that area's out of view.
	var box := _screen_lon_lat_box(80.0)
	for i in sea.pods.size():
		var bound: Array = _pod_bounds.get(i, NO_POD_BOUND)
		if now < float(bound[1]):
			var area_box: Rect2 = bound[0]
			if not area_box.intersects(box) and not area_box.intersects(Rect2(box.position + Vector2(360.0, 0.0), box.size)) and not area_box.intersects(Rect2(box.position - Vector2(360.0, 0.0), box.size)):
				continue
		var pod: Dictionary = sea.pods[i]
		var kind: Dictionary = sea.species[pod.species]
		# Its state (where it is, which way) kept for POD_STATE_S: pods crawl, and
		# working it out means walking its path.
		var kept: Array = _pod_states.get(i, [])
		var state: Dictionary
		if not kept.is_empty() and now < float(kept[0]):
			state = kept[2]
		else:
			state = sea.state(i, now)
			var refresh_at := now + POD_STATE_S * float(GameState.calendar_seconds_per_second())
			_pod_states[i] = [refresh_at, refresh_at, state]
		if state.migrating:
			_pod_bounds.erase(i)
		else:
			var area: Dictionary = sea.areas[state.area]
			_pod_bounds[i] = [_lon_lat_rect(Vector2(float(area.lon), float(area.lat)), float(area.radius_nm) / 60.0 + 0.1), float(state.until)]
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

## A sea animal species' place in _sea_kinds (what SeaPainter draws it with), added the first time.
func _sea_kind_index(species: String, kind: Dictionary) -> int:
	if not _sea_kind_indices.has(species):
		var texture := _sea_texture(str(kind.art))
		var silhouette := _sea_silhouette(str(kind.art))
		_sea_kind_indices[species] = _sea_kinds.size()
		_sea_kinds.append({texture = texture.get_rid() if texture != null else RID(), silhouette = silhouette.get_rid() if silhouette != null else RID(),
			length_px = float(kind.length_px), spacing_px = float(kind.spacing_px), leap = _sea_leaps(kind), blow = _sea_blows(kind),
			breach = kind.get("breach", []), surface = kind.get("surface", [])})
	return _sea_kind_indices[species]

## Which sea animals leap clear in an arc (dolphins, fish, sea lions) rather
## than breach straight up (whales, orcas, sharks), and which blow when they
## surface (whales and orcas; sharks show their fin, seals bob up, otters float).
static func _sea_leaps(kind: Dictionary) -> bool:
	return kind.kind in ["dolphin", "fish", "sea_lion"]

static func _sea_blows(kind: Dictionary) -> bool:
	return kind.kind in ["whale", "orca"]

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
	var dolphin := _sea_leaps(kind)  # (A leap, as a dolphin's; else a breach.)
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
			if up > 0.15 and up < 0.75 and _sea_blows(kind):
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
	# When in its slot it happens (or that it doesn't), kept for the slot: the
	# same rolls every frame till the next.
	var key := Vector4i(pod, j, what.hash(), int(slot))
	var start: float
	if _sea_events.has(key):
		start = _sea_events[key]
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([pod, j, what, int(slot)])
		start = NAN
		if rng.randf() < chance:
			start = slot * every + rng.randf() * maxf(every - seconds, 0.0)
		if _sea_events.size() > 4096:
			_sea_events.clear()
		_sea_events[key] = start
	if is_nan(start):
		return -1.0
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
	for hit: Array in _pod_hit_list():
		var share := (hit[1] as Vector2).distance_to(screen_pos) / float(hit[2])
		if share <= 1.0 and share < best_share:
			best_share = share
			best = hit[0]
	return best

## Where a pod's middle is on screen (local to this control), as last drawn,
## or Vector2.INF if it isn't in view.
func pod_screen_position(pod: int) -> Vector2:
	for hit: Array in _pod_hit_list():
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

## Every bird (BirdLife) in view, each where it is and doing what it's doing,
## at its size in the world (with the ships: _ship_scale()). It's always
## somewhere: no bird is ever made up or taken away, they fly from place to
## place. Far out, where a bird would be under BIRD_FULL_PX across, it's a dot
## of its color (down to BIRD_DOT_PX); closer, its drawing: flying (circling,
## soaring, gliding, hunting, following a ship) from above with its shadow
## below; perched, resting or asleep with its wings folded; swimming on the
## water (sea ducks and cormorants low in it, from draw_duck()); a diver just
## a dark shape under a ripple; waders standing or stalking from above with
## their long shadows (a bittern in its reeds, bill to the sky). A hunter
## plunging in makes a splash. Clicking one opens its colony's popup.
##
## Birds keeping still for a while yet (BirdLife.still_until()) are drawn on
## their own layer (_draw_still_birds()), only again when the view changes or
## the first of them is about to move: the rest every frame, here.
func _draw_birds() -> void:
	_bird_hits.clear()
	var now := Wildlife.shared().bird_time
	var cal := float(GameState.calendar_time())
	var native: Object = BirdLife.shared().native
	if native != null:
		if now >= float(native.still_redraw_at()) or native.where_changes() != native.still_epoch():
			_still_birds.queue_redraw()
	elif now >= _still_redraw_at or Wildlife.shared().where_changes != _still_epoch:
		_still_redraw_at = INF
		_still_birds.queue_redraw()
	_draw_bird_pass(false, now, cal)


## The birds keeping still for a while yet (see _draw_birds()), on their own layer.
func _draw_still_birds() -> void:
	_canvas = _still_birds
	_still_drawn.clear()
	_still_hits.clear()
	var now := Wildlife.shared().bird_time
	var cal := float(GameState.calendar_time())
	_still_epoch = Wildlife.shared().where_changes
	_still_redraw_at = INF
	_draw_bird_pass(true, now, cal)
	_canvas = _overlay


## One pass over the birds in view (see _draw_birds()): those keeping still
## for STILL_LAYER_S or more (marked in _still_drawn), or all the others.
func _draw_bird_pass(still: bool, now: float, cal: float) -> void:
	if gray_mode or not show_ships or not Settings.birds:
		return  # (Nor with the birds switched off in Settings.)
	var scale := _ship_scale()
	if BIRD_SMALLEST_SPAN * BIRD_SCALE * scale < BIRD_DOT_PX:
		return
	var life := BirdLife.shared()
	if not life.spots_provider.is_valid():
		life.set_map_providers(_bird_spots, _native_bird_shape)
	if not life.ensure_built():
		return
	var wildlife := Wildlife.shared()
	if life.native != null:
		life.native.draw(_canvas.get_canvas_item(), still, {box = _screen_lon_lat_box(BIRD_VIEW_MARGIN_PX), view = Rect2(Vector2.ZERO, size).grow(40.0),
			right = _right, up = _up, toward = _toward, radius = _radius(), middle = size / 2.0, now = now, cal = cal,
			scale = BIRD_SCALE * scale, dot_px = BIRD_DOT_PX, full_px = BIRD_FULL_PX, reach_gulls_km = BIRD_REACH_KM.gulls,
			reach_other_km = BIRD_REACH_KM.other, view_lat = _view_lat, still_s = STILL_LAYER_S, still_margin_s = STILL_LAYER_MARGIN_S})
		return
	var hits: Array = _still_hits if still else _bird_hits
	var view := Rect2(Vector2.ZERO, size).grow(40.0)
	var box := _screen_lon_lat_box(BIRD_VIEW_MARGIN_PX)
	var wide_by := 1.0 / maxf(cos(deg_to_rad(clampf(_view_lat, -80.0, 80.0))), 0.1)
	# The colonies whose birds could be in view: those of the ports near it (and
	# visiting them; no further from their port than BIRD_REACH_KM), the seabirds
	# whose range reaches it, and those on the wing.
	var colonies := {}
	var most := float(BIRD_REACH_KM.gulls) / Wildlife.KM_PER_DEGREE
	for index: int in wildlife.colonies_near(box.grow_individual(most * wide_by, most, most * wide_by, most)):
		var colony: Dictionary = wildlife.colonies[index]
		if colony.cls == "seabirds":
			continue
		var where: String = wildlife.colony_where(colony, cal)[0]
		if where.begins_with("to_"):
			continue  # (On the wing: below.)
		var reach := float(BIRD_REACH_KM.get(colony.cls, BIRD_REACH_KM.other)) / Wildlife.KM_PER_DEGREE
		if box.grow_individual(reach * wide_by, reach, reach * wide_by, reach).has_point(colony.away_spot if where == "away" else colony.spot):
			colonies[index] = true
	for index: int in wildlife.seabird_colonies_in(box):
		var colony: Dictionary = wildlife.colonies[index]
		var reach := float(colony.get("range_km", 500.0)) / Wildlife.KM_PER_DEGREE
		var spot: Vector2 = colony.spot
		var wide := reach / maxf(cos(deg_to_rad(spot.y)), 0.1)
		if box.grow_individual(wide, reach, wide, reach).has_point(spot) or box.grow_individual(wide, reach, wide, reach).has_point(colony.away_spot):
			colonies[index] = true
	if not still:
		for entry: Array in wildlife.migrating(cal):
			colonies[entry[0]] = true
	var epoch := wildlife.where_changes
	# (The box round the back of the date line too, when it reaches past it.)
	var wraps := box.position.x < -180.0 or box.end.x > 180.0
	var box_east := Rect2(box.position + Vector2(360.0, 0.0), box.size)
	var box_west := Rect2(box.position - Vector2(360.0, 0.0), box.size)
	var flyers := []  # (Birds in the air, drawn after those on the water and the ground: over them.)
	for index: int in colonies:
		var colony: Dictionary = wildlife.colonies[index]
		var info := Birds.shared().species(colony.species)
		var span := float(info.get("span", 1.0)) * BIRD_SCALE * scale
		if span < BIRD_DOT_PX:
			continue
		var about := []  # (What a click on one of them opens: made once a colony.)
		# Which way east and north are on screen about its birds, for their headings:
		# worked out at the first one drawn (they're never far apart; a seabird's each).
		var basis := Transform2D(Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		var each_own: bool = colony.cls == "seabirds"
		for b: int in life.birds_of(index):
			if not still and _still_drawn.has(b):
				continue  # (On the still birds' layer.)
			# Skipped while all it can do till its spell ends is out of view (see BirdLife.bird_bounds()).
			var bound: Array = _bird_bounds.get(b, NO_BIRD_BOUND)
			if now >= float(bound[1]) or int(bound[2]) != epoch:
				var reach := life.bird_bounds(b, now, cal)
				bound = [_lon_lat_rect(reach[0], float(reach[1]) / Wildlife.KM_PER_DEGREE), reach[2], epoch] if not reach.is_empty() else [EVERYWHERE, now + 1.0, epoch]
				_bird_bounds[b] = bound
			var area: Rect2 = bound[0]
			if not area.intersects(box) and not (wraps and (area.intersects(box_east) or area.intersects(box_west))):
				continue
			var state := life.bird_state(b, now, cal)
			if still:
				var until := life.still_until(b)
				if until < now + STILL_LAYER_S:
					continue
				_still_drawn[b] = true
				_still_redraw_at = minf(_still_redraw_at, until - STILL_LAYER_MARGIN_S)
			var pos: Vector2 = state.pos
			var at := world_to_screen(Geo.project(pos))
			if _is_hidden(at) or not view.has_point(at):
				continue
			if span >= BIRD_FULL_PX and (each_own or basis.x == Vector2.ZERO):
				basis = _screen_basis(pos, at)
			if about.is_empty():
				about = [{colony = index}, {count = int(colony.count), species = [colony.species]}]
			if not still and FLYING_MODES.has(state.mode):
				flyers.append([life.birds[b], colony, info, state, at, span, basis, about, b])
				continue
			_draw_one_bird(life.birds[b], colony, info, state, at, span, now, basis)
			hits.append([at, maxf(span * 0.6, BIRD_HIT_MIN_PX), about[0], about[1], b])
	for flyer: Array in flyers:
		_draw_one_bird(flyer[0], flyer[1], flyer[2], flyer[3], flyer[4], flyer[5], now, flyer[6])
		hits.append([flyer[4], maxf(float(flyer[5]) * 0.6, BIRD_HIT_MIN_PX), flyer[7][0], flyer[7][1], flyer[8]])
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)


## Which way (and how far: px a degree) east and north go on screen at a
## (lon, lat) spot, at its screen point: [east, north] as a transform's axes
## (zero where the globe turns away).
func _screen_basis(spot: Vector2, at: Vector2) -> Transform2D:
	var east := world_to_screen(Geo.project(spot + Vector2(0.01 / maxf(cos(deg_to_rad(spot.y)), 0.1), 0.0)))
	var north := world_to_screen(Geo.project(spot + Vector2(0.0, 0.01)))
	if _is_hidden(east) or _is_hidden(north):
		return Transform2D(Vector2.RIGHT, Vector2.UP, Vector2.ZERO)
	return Transform2D(east - at, north - at, Vector2.ZERO)


## The box of (lon, lat) within `reach` degrees (of latitude) of a spot.
static func _lon_lat_rect(spot: Vector2, reach: float) -> Rect2:
	var wide := reach / maxf(cos(deg_to_rad(clampf(absf(spot.y) + reach, 0.0, 89.0))), 0.05)
	return Rect2(spot - Vector2(wide, reach), Vector2(wide, reach) * 2.0)


## One bird on screen, as it is now (see _draw_birds()).
func _draw_one_bird(bird: Dictionary, colony: Dictionary, info: Dictionary, state: Dictionary, at: Vector2, span: float, now: float, basis: Transform2D) -> void:
	if span < BIRD_FULL_PX:
		_canvas.draw_circle(at, maxf(span * 0.22, 0.7), _bird_dot_color(info))
		return
	var heading := float(state.heading)
	var angle := (basis.x * cos(heading) + basis.y * sin(heading)).angle()
	var mode: String = state.mode
	var cls: String = colony.cls
	var wings := float(state.wings)
	var height := float(state.height)
	var flying := FLYING_MODES.has(mode)
	if mode == "dive":
		# Under the water: a dark shape and a ripple over it.
		_canvas.draw_set_transform(at, angle, Vector2.ONE)
		_canvas.draw_colored_polygon(_oval(Vector2.ZERO, Vector2(span * 0.3, span * 0.1)), Color(0.08, 0.12, 0.18, 0.35))
		_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
		var ripple := fmod(now * 0.7 + float(bird.seed % 10), 1.0)
		_canvas.draw_arc(at, span * (0.15 + 0.25 * ripple), 0.0, TAU, 14, Color(1, 1, 1, 0.5 * (1.0 - ripple)), maxf(span * 0.03, 1.0), true)
		return
	match cls:
		"sea_ducks":
			if flying:
				_draw_bird_mesh(at, angle, _duck_flyer(info, bool(bird.hen)), wings, span, height)
			else:
				_draw_duck_mesh(at, angle, info, span, bool(bird.hen))
		"waders":
			if flying:
				_draw_bird_mesh(at, angle, info, wings, span, height)
			else:
				var hiding := str(info.get("behavior", "")) == "hide" and mode == "stand"
				if hiding:
					_draw_reeds(at, span, now, 0.0, float(bird.seed % 100))
				var neck: float = {stand = 0.55, stalk = 0.85, sleep = 0.1, rest = 0.3, perch = 0.3}.get(mode, 0.5)
				_draw_wader_mesh(at, angle, info, span, neck, hiding)
		"cormorants":
			if mode == "swim":
				_draw_duck_mesh(at, angle, _cormorant_swimmer(info), span * 1.2, false)
			else:
				_draw_bird_mesh(at, angle, info, wings, span, height if flying else 0.03)
		_:
			if mode == "swim":
				_draw_bird_mesh(at, angle, info, 0.2, span, -1.0)
			else:
				_draw_bird_mesh(at, angle, info, wings, span, height if flying else 0.03)
	if float(state.splash) > 0.0:
		var s := float(state.splash)
		_canvas.draw_arc(at, span * (0.2 + 0.4 * (1.0 - s)), 0.0, TAU, 16, Color(1, 1, 1, 0.8 * s), maxf(span * 0.05, 1.0), true)


## A bird drawn from above (draw_bird()) as one mesh: made once for its
## species, how far its wings are out (to BIRD_WING_STEP) and about its size
## (to BIRD_SIZE_STEP times), then just placed, turned and scaled; its shadow
## the same mesh in the dark, `height` times as far off as a gull's usual (none
## when `height` is below 0).
func _draw_bird_mesh(at: Vector2, heading: float, info: Dictionary, wings: float, span: float, height: float) -> void:
	var step := roundi(clampf(wings, 0.0, 1.5) / BIRD_WING_STEP)
	var bucket := _mesh_bucket(span)
	var key := ((_bird_mesh_id(info) * 64 + step) * 256 + bucket) * 4
	var mesh: ArrayMesh = _bird_meshes.get(key)
	var made := _bucket_made
	if mesh == null:
		var recorder := ShapeRecorder.new()
		draw_bird(recorder, Vector2.ZERO, 0.0, info, step * BIRD_WING_STEP, made, false)
		mesh = _keep_bird_mesh(key, recorder)
	var scale := Vector2.ONE * (span / made)
	if height >= 0.0 and bird_shadows:
		var off := Vector2(span * 0.45, span * 0.55) * height
		_canvas.draw_mesh(mesh, null, Transform2D(heading, scale, 0.0, at + off), Color(0, 0, 0, 0.16 / sqrt(maxf(height, 0.5))))
	_canvas.draw_mesh(mesh, null, Transform2D(heading, scale, 0.0, at))


## A sea duck (or a cormorant) swimming (draw_duck()) as one mesh, the same way
## as _draw_bird_mesh().
func _draw_duck_mesh(at: Vector2, heading: float, info: Dictionary, span: float, hen: bool) -> void:
	var bucket := _mesh_bucket(span)
	var key := (_bird_mesh_id(info) * 64 * 256 + bucket) * 4 + (2 if hen else 1)
	var mesh: ArrayMesh = _bird_meshes.get(key)
	var made := _bucket_made
	if mesh == null:
		var recorder := ShapeRecorder.new()
		draw_duck(recorder, Vector2.ZERO, 0.0, info, made, hen)
		mesh = _keep_bird_mesh(key, recorder)
	_canvas.draw_mesh(mesh, null, Transform2D(heading, Vector2.ONE * (span / made), 0.0, at))


## A wader on the ground (draw_wader()): its long shadow drawn as it falls,
## the bird itself as one mesh, the same way as _draw_bird_mesh().
var bird_shadows := true  # (Off while the sound tracker draws its bird: a shadow there falls apart from it.)
func _draw_wader_mesh(at: Vector2, heading: float, info: Dictionary, span: float, neck: float, bill_up: bool) -> void:
	if bird_shadows:
		draw_wader(_canvas, at, heading, info, span, neck, 0.0, bill_up, 0.0, false, true, false)
	var bucket := _mesh_bucket(span)
	var shape := roundi(clampf(neck, 0.0, 1.0) * 20.0) * 2 + (1 if bill_up else 0)
	var key := ((_bird_mesh_id(info) * 64 + shape) * 256 + bucket) * 4 + 3
	var mesh: ArrayMesh = _bird_meshes.get(key)
	var made := _bucket_made
	if mesh == null:
		var recorder := ShapeRecorder.new()
		draw_wader(recorder, Vector2.ZERO, 0.0, info, made, neck, 0.0, bill_up, 0.0, false, false, true)
		mesh = _keep_bird_mesh(key, recorder)
	_canvas.draw_mesh(mesh, null, Transform2D(heading, Vector2.ONE * (span / made), 0.0, at))


## Which size of mesh a bird `span` px across is drawn from (and that size,
## px: _bucket_made); the same for a run of birds the same size.
func _mesh_bucket(span: float) -> int:
	if span != _bucket_span:
		_bucket_span = span
		_bucket = clampi(roundi(log(maxf(span, 1.0)) * BIRD_SIZE_LOG), 0, 255)
		_bucket_made = pow(BIRD_SIZE_STEP, _bucket)
	return _bucket


## A number for a species' (or its colors') meshes, given it the first time.
func _bird_mesh_id(info: Dictionary) -> int:
	var id: int = info.get("_mesh_id", -1)
	if id < 0:
		id = _bird_mesh_ids
		_bird_mesh_ids += 1
		info["_mesh_id"] = id
	return id


func _keep_bird_mesh(key: int, recorder: ShapeRecorder) -> ArrayMesh:
	if _bird_meshes.size() >= BIRD_MESHES_KEPT:
		_bird_meshes.clear()  # (Zoomed through a lot of sizes: start again.)
	var mesh := recorder.mesh()
	_bird_meshes[key] = mesh
	return mesh


## A sea duck's colors for flying (_duck_flying()), made once a species and sex.
func _duck_flyer(info: Dictionary, hen: bool) -> Dictionary:
	var key := "%s|%s" % [info.get("latin", ""), hen]
	if not _duck_flyers.has(key):
		var flyer := _duck_flying(info, hen)
		flyer.latin = info.get("latin", "")
		flyer._key = "flying hen" if hen else "flying drake"
		_duck_flyers[key] = flyer
	return _duck_flyers[key]


## Takes down what draw_bird() and draw_duck() draw (as a canvas item would)
## as triangles, to make one mesh of them.
class ShapeRecorder:
	extends RefCounted
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var _xform := Transform2D.IDENTITY

	func draw_set_transform(position: Vector2, rotation := 0.0, scale := Vector2.ONE) -> void:
		_xform = Transform2D(rotation, scale, 0.0, position)

	func draw_set_transform_matrix(xform: Transform2D) -> void:
		_xform = xform

	func draw_colored_polygon(polygon: PackedVector2Array, color: Color, _uvs := PackedVector2Array(), _texture: Texture2D = null) -> void:
		var placed := _xform * polygon
		for i in Geometry2D.triangulate_polygon(polygon):
			points.append(placed[i])
			colors.append(color)

	func draw_circle(center: Vector2, radius: float, color: Color, _filled := true, _width := -1.0, _antialiased := false) -> void:
		var ring := PackedVector2Array()
		for i in 12:
			ring.append(center + Vector2.from_angle(TAU * i / 12.0) * radius)
		draw_colored_polygon(ring, color)

	func draw_line(from: Vector2, to: Vector2, color: Color, width := -1.0, _antialiased := false) -> void:
		if from == to:
			return
		var side := (to - from).normalized().orthogonal() * maxf(width, 0.02) * 0.5
		draw_colored_polygon(PackedVector2Array([from + side, to + side, to - side, from - side]), color)

	func draw_rect(rect: Rect2, color: Color, _filled := true, _width := -1.0, _antialiased := false) -> void:
		draw_colored_polygon(PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), color)

	func mesh() -> ArrayMesh:
		var out := ArrayMesh.new()
		if points.is_empty():
			return out
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_COLOR] = colors
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out


## A shape for the native birds (BirdSim, which asks once for each), as the
## triangles of one mesh, [points, colors]: `kind` 0 a bird from above (draw_bird(): wings out `step` x BIRD_WING_STEP), 1 a sea
## duck flying (the same, in its colors), 2 a sea duck swimming
## (draw_duck()), 3 a cormorant swimming, 4 a wader on the ground
## (draw_wader()'s body: its neck out `step` / 20, bill up if `hen`); `bucket`
## sizes it (BIRD_SIZE_STEP to the power of it, px across).
func _native_bird_shape(kind: int, species_id: String, hen: bool, step: int, bucket: int) -> Array:
	var info := Birds.shared().species(species_id)
	var made := pow(BIRD_SIZE_STEP, bucket)
	var recorder := ShapeRecorder.new()
	match kind:
		0:
			draw_bird(recorder, Vector2.ZERO, 0.0, info, step * BIRD_WING_STEP, made, false)
		1:
			draw_bird(recorder, Vector2.ZERO, 0.0, _duck_flyer(info, hen), step * BIRD_WING_STEP, made, false)
		2:
			draw_duck(recorder, Vector2.ZERO, 0.0, info, made, hen)
		3:
			draw_duck(recorder, Vector2.ZERO, 0.0, _cormorant_swimmer(info), made, false)
		4:
			draw_wader(recorder, Vector2.ZERO, 0.0, info, made, step / 20.0, 0.0, hen, 0.0, false, false, true)
	return [recorder.points, recorder.colors]


## A bird's color as a dot (its back's), read once a species.
func _bird_dot_color(info: Dictionary) -> Color:
	var key := str(info.get("name", ""))
	if not _bird_dot_colors.has(key):
		_bird_dot_colors[key] = Color.from_string(str((info.get("colors", {}) as Dictionary).get("mantle", "#aab4bd")), Color.GRAY)
	return _bird_dot_colors[key]


## A port's spots for its birds (BirdLife's spots provider), in (lon, lat):
## the marina's middle and how wide it is (km), on its rocks (rocks) and along
## the breakwater's arms (and both together, rocks first: perches),
## the water's edge either side and the land just behind it (_shore_spots()),
## the sea off it, and its colonies' homes (by colony index); {} till the
## map's land is ready.
func _bird_spots(port_id: String) -> Dictionary:
	if _land_cells.is_empty():
		_start_land_cells()
		return {}
	var layout := _port_layout(port_id)
	var radius := float(layout.radius)
	var gap := float(layout.get("gap", 0.4))
	var out := {center = _dock_lon_lat(port_id, Vector2.ZERO), radius_km = radius * KM_PER_DEGREE / SHIP_WORLD_ZOOM}
	# Perching spots along both arms of the breakwater, PERCH_SPACING apart (each
	# perching bird has its own: see BirdLife._perch()).
	var breakwater := []
	var slots := maxi(floori((PI / 2.0 - 0.05 - gap - 0.1) * radius / PERCH_SPACING), 1)
	for side: float in [1.0, -1.0]:
		for i in slots:
			var along := lerpf(gap + 0.1, PI / 2.0 - 0.05, (i + 0.5) / slots) * side
			breakwater.append(_dock_lon_lat(port_id, Vector2.from_angle(along) * radius))
	out.breakwater = breakwater
	# Perching spots on the rocks (see ROCK_SPOTS): a grid over each rock's
	# top, ROCK_PERCH_SPACING apart (at least its middle); the birds take these
	# first, then the breakwater (perches).
	var perches := []
	for rock: Array in layout.rocks:
		if not _rock_shown(port_id, rock):
			continue
		var middle: Vector2 = rock[0]
		var top := float(rock[1]) * 0.55
		var before := perches.size()
		var y := -top
		while y <= top + 0.001:
			var x := -top
			while x <= top + 0.001:
				if Vector2(x, y).length() <= top:
					perches.append(_dock_lon_lat(port_id, middle + Vector2(x, y)))
				x += ROCK_PERCH_SPACING
			y += ROCK_PERCH_SPACING
		if perches.size() == before:
			perches.append(_dock_lon_lat(port_id, middle))
	out.rocks = perches
	out.perches = perches + breakwater
	var shore := []
	var inland := []
	for spot: Array in _shore_spots(port_id):
		shore.append(_dock_lon_lat(port_id, spot[0]))
		if spot[1] != Vector2.INF:
			inland.append(_dock_lon_lat(port_id, spot[1]))
	out.shore = shore if not shore.is_empty() else breakwater
	out.inland = inland if not inland.is_empty() else out.shore
	var sea := []
	for x: float in [1.5, 2.0, 2.6]:
		for y: float in [-1.2, -0.6, 0.0, 0.6, 1.2]:
			var there := _dock_lon_lat(port_id, Vector2(x, y) * radius)
			if not _on_land(there):
				sea.append(there)
	out.sea = sea if not sea.is_empty() else [_dock_lon_lat(port_id, Vector2(2.0, 0.0) * radius)]
	var homes := {}
	for index: int in Wildlife.shared().colonies_at(port_id):
		homes[index] = _dock_lon_lat(port_id, _colony_home_local(port_id, Wildlife.shared().colonies[index]))
	out.homes = homes
	out.roost = (out.shore as Array)[0]
	return out


## A point of a port's marina (dock units) as (lon, lat): dock units are
## 1 / SHIP_WORLD_ZOOM of a degree, turned the way the port faces the sea.
func _dock_lon_lat(port_id: String, local: Vector2) -> Vector2:
	var port := GameData.get_port(port_id)
	var off := Vector2(local.x, local.y * float(_dock_flips.get(port_id, 1.0))).rotated(_port_sea_angle(port_id)) / SHIP_WORLD_ZOOM
	var lat := float(port.get("lat", 0.0))
	return Vector2(float(port.get("lon", 0.0)) + off.x / maxf(cos(deg_to_rad(lat)), 0.05), lat - off.y)


## True if a screen point is out on the sea (SeaLife's sea mask, 0.25 degree
## cells), for birds on or over the water.
func _on_sea(screen: Vector2) -> bool:
	return not _is_hidden(screen) and SeaLife.shared().is_sea(_screen_lon_lat(screen))

## Where a bird of a V (pelicans, cormorants, migrating sea ducks) flies:
## `place` 0 the leader at `lead`, then back along either arm by turns,
## flying `way` (a unit vector), birds `span` px across.
static func _v_spot(lead: Vector2, way: Vector2, place: int, span: float) -> Vector2:
	var rank := (place + 1) / 2
	var arm := 0.0 if place == 0 else (1.0 if place % 2 == 1 else -1.0)
	var spacing := span * 0.8
	return lead - way * rank * spacing * 0.8 + way.orthogonal() * arm * rank * spacing * 0.75

## A cormorant's colors for drawing it swimming low (see draw_duck()): all
## its back's dark color, its head and bill. Made once a species.
func _cormorant_swimmer(info: Dictionary) -> Dictionary:
	var id := str(info.get("latin", ""))
	if not _cormorant_swimmers.has(id):
		var colors: Dictionary = info.get("colors", {})
		_cormorant_swimmers[id] = {latin = id, _key = "swimmer", colors = {mantle = colors.get("mantle", "#1e1e1e"), sides = colors.get("mantle", "#1e1e1e"),
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
	if _land_test != null:
		# The search natively (LandTest: the same, a lot quicker).
		var marinas := []
		for other: String in _shore_neighbours_of(port_id):
			var layout := _port_layout(other)
			var there := GameData.get_port(other)
			marinas.append({lon = float(there.get("lon", 0.0)), lat = float(there.get("lat", 0.0)), angle = _port_sea_angle(other),
				clear = float(layout.radius) + JETTY_WIDTH / 2.0, quay_inland = _quay_inland(layout)})
		var port := GameData.get_port(port_id)
		var angle := _port_sea_angle(port_id)  # (Works out its flip too.)
		var found: Array = _land_test.shore_spots({lon = float(port.get("lon", 0.0)), lat = float(port.get("lat", 0.0)), angle = angle,
			flip = float(_dock_flips.get(port_id, 1.0)), radius = radius}, marinas, SHORE_SAMPLES, SHORE_REACH, SHORE_SEAWARD, SHORE_INLAND)
		if not native_shores_off:
			if found.is_empty():
				for y: float in [-1.9, -1.4, 1.4, 1.9]:
					found.append([Vector2(radius * 0.3, y * radius), Vector2(-radius * 0.8, y * radius)])
			_shores[port_id] = found
			return found
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
## the sea in to the first of either). Worked out on the map in (lon, lat)
## (_dock_lon_lat()), the same whatever the view.
func _local_on_land(port_id: String, local: Vector2, blocked := false) -> bool:
	var spot := _dock_lon_lat(port_id, local)
	var land := _on_land(spot)
	if land and blocked:
		return true
	if not land and not blocked:
		return false
	for other: String in _shore_neighbours_of(port_id):
		if _in_marina_at(other, spot):
			return blocked
	return not blocked

## A port and the ports within 3 degrees of it (whose marinas its shore keeps
## clear of), from the ports filed by 3-degree cell; worked out once.
func _shore_neighbours_of(port_id: String) -> Array[String]:
	if not _shore_neighbours.has(port_id):
		var here := GameData.port_position(port_id)
		var near: Array[String] = [port_id]
		if _port_grid.is_empty():
			for port: Dictionary in GameData.ports:
				var at := GameData.port_position(port.id)
				(_port_grid.get_or_add(Vector2i(floori(at.x / 3.0), floori(at.y / 3.0)), []) as Array).append(port.id)
		var cell := Vector2i(floori(here.x / 3.0), floori(here.y / 3.0))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for other: String in _port_grid.get(Vector2i(posmod(cell.x + dx + 60, 120) - 60, cell.y + dy), []):
					if other != port_id and GameData.port_position(other).distance_to(here) < 3.0:
						near.append(other)
		_shore_neighbours[port_id] = near
	return _shore_neighbours[port_id]

## True if a (lon, lat) spot's on a port's marina: its cleared circle or its
## square quay (a little grown), in its dock units (_dock_lon_lat() backwards).
func _in_marina_at(port_id: String, spot: Vector2) -> bool:
	var layout := _port_layout(port_id)
	var port := GameData.get_port(port_id)
	var lat := float(port.get("lat", 0.0))
	var off := Vector2(wrapf(spot.x - float(port.get("lon", 0.0)), -180.0, 180.0) * maxf(cos(deg_to_rad(lat)), 0.05), lat - spot.y) * SHIP_WORLD_ZOOM
	var local := off.rotated(-_port_sea_angle(port_id))
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
static func draw_wader(canvas: Object, at: Vector2, heading: float, info: Dictionary, span: float, neck := 0.5, wings := 0.0, bill_up := false, lift := 0.0, fish := false, with_shadow := true, with_body := true) -> void:
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
	if with_shadow:
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
	if not with_body:
		return
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
static func draw_duck(canvas: Object, at: Vector2, heading: float, info: Dictionary, span: float, hen: bool) -> void:
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

## A bird seen from above on any canvas item, at a point, heading a way,
## `span` px from wingtip to wingtip: body and tail in its mantle color, its
## head and bill (a pelican's long), wings out to its span (times `wings`,
## shorter as they beat up and down or fold) with dark tips, and its shadow
## below (`height` times as far off as usual). A raptor (one with a tail
## color) has broad wings with fingered tips (an osprey's bent at the wrist),
## a fanned tail and a hooked bill; some have pale or chestnut shoulders. A
## falcon has swept pointed wings and a long narrow tail, a frigatebird long, narrow
## angular wings, a forked tail and a scarlet throat.
## Leaves the canvas item's transform reset.
static func draw_bird(canvas: Object, at: Vector2, heading: float, info: Dictionary, wings: float, span: float, shadow := true, height := 1.0) -> void:
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
	var kind := str(info.get("kind", ""))
	var frigate := kind == "Frigatebird"
	var owl := kind == "Owl"
	var shape := _bird_shape(raptor or wader, raptor and str(info.get("behavior", "")) == "plunge", 3 if frigate else (4 if kind == "Falcon" else (5 if owl else 0)))
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
		if raptor or frigate:
			canvas.draw_set_transform(at + off, heading, whole)
			canvas.draw_colored_polygon(shape.tail, dark)
	if raptor or frigate:
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
	if frigate:
		canvas.draw_set_transform(at, heading, Vector2(span, span * 0.5))  # A slim body, as in life.
		canvas.draw_colored_polygon(_bird_body, body)
		canvas.draw_set_transform(at, heading, whole)
		canvas.draw_circle(Vector2(0.1, 0.0), 0.028, Color(0.85, 0.12, 0.16))  # The male's scarlet throat pouch.
	else:
		canvas.draw_colored_polygon(_bird_body, body)
	if owl:
		_draw_owl_head(canvas, colors, head, bill)
	elif raptor:
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
		canvas.draw_circle(Vector2(0.17, 0.0), 0.04 if frigate else 0.055, head)  # (A frigatebird: a small head and a long hooked bill.)
		canvas.draw_line(Vector2(0.21, 0.0), Vector2(0.36 if long_bill or frigate else 0.27, 0.0), bill, maxf(span * (0.02 if frigate else 0.03), 1.0) / span)
	canvas.draw_set_transform_matrix(Transform2D.IDENTITY)

## A bird's wings, wingtips and (a raptor's) tail a unit across, made once
## (see draw_bird()): {wing, wing_mirrored, tip, tip_mirrored, tail}. A gull or
## seabird's wings swept back to their tips; a raptor's broad and square (bent
## forward at the wrist for an osprey), the tips spread into fingers.
## `special`: 3 a frigatebird (long angular wings, a long forked tail), 4 a
## falcon (swept pointed wings, a long narrow tail), 5 an owl (broad rounded
## wings, a short round tail).
static func _bird_shape(raptor: bool, bent: bool, special := 0) -> Dictionary:
	var key := special if special > 0 else (2 if bent else (1 if raptor else 0))
	if _bird_shapes.has(key):
		return _bird_shapes[key]
	var half := 0.5
	var wing: PackedVector2Array
	var tip_part: PackedVector2Array
	var tail := PackedVector2Array()
	if special == 3:
		# A frigatebird's wings: long and narrow, sharply angled at the wrist (a W
		# in the sky), as in life: the hand swept back about 40 degrees off the arm.
		wing = PackedVector2Array([Vector2(0.03, 0.0), Vector2(0.07, half * 0.42), Vector2(-0.106, half), Vector2(-0.061, half * 0.442), Vector2(-0.035, 0.0)])
		tip_part = PackedVector2Array([Vector2(-0.036, half * 0.689), Vector2(-0.106, half), Vector2(-0.088, half * 0.685)])
		tail = PackedVector2Array([Vector2(-0.12, 0.018), Vector2(-0.44, 0.075), Vector2(-0.42, 0.045), Vector2(-0.3, 0.0), Vector2(-0.42, -0.045), Vector2(-0.44, -0.075), Vector2(-0.12, -0.018)])
	elif special == 5:
		# An owl's wings: broad and rounded at the end, soft-edged, the
		# fingers barely parted; a short, rounded tail.
		wing = PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.09, half * 0.45), Vector2(0.06, half * 0.85), Vector2(0.0, half), Vector2(-0.09, half * 0.96),
			Vector2(-0.15, half * 0.7), Vector2(-0.14, 0.0)])
		tip_part = PackedVector2Array([Vector2(0.05, half * 0.86), Vector2(0.0, half), Vector2(-0.09, half * 0.96), Vector2(-0.07, half * 0.82)])
		tail = PackedVector2Array([Vector2(-0.16, 0.05), Vector2(-0.27, 0.07), Vector2(-0.3, 0.0), Vector2(-0.27, -0.07), Vector2(-0.16, -0.05)])
	elif special == 4:
		wing = PackedVector2Array([Vector2(0.08, 0.0), Vector2(0.1, half * 0.4), Vector2(-0.06, half), Vector2(-0.13, half * 0.5), Vector2(-0.13, 0.0)])
		tip_part = PackedVector2Array([Vector2(0.0, half * 0.7), Vector2(-0.06, half), Vector2(-0.11, half * 0.72)])
		tail = PackedVector2Array([Vector2(-0.18, 0.045), Vector2(-0.4, 0.06), Vector2(-0.4, -0.06), Vector2(-0.18, -0.045)])
	elif raptor:
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

## An owl's big round head from above (see draw_bird()): its pale facial
## disc forward, two big eyes in it (colors face, eyes), a small hooked bill
## between them, and ear tufts at the back for the horned owls (colors tufts).
static func _draw_owl_head(canvas: Object, colors: Dictionary, head: Color, bill: Color) -> void:
	if colors.has("tufts"):
		var tufts := Color.from_string(str(colors.tufts), head)
		for side: float in [-1.0, 1.0]:
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(0.1, side * 0.05), Vector2(0.06, side * 0.1), Vector2(0.14, side * 0.07)]), tufts)
	canvas.draw_circle(Vector2(0.12, 0.0), 0.085, head)
	canvas.draw_circle(Vector2(0.15, 0.0), 0.062, Color.from_string(str(colors.get("face", "")), head.lightened(0.3)))
	var eyes := Color.from_string(str(colors.get("eyes", "")), Color(0.95, 0.75, 0.12))
	for side: float in [-1.0, 1.0]:
		canvas.draw_circle(Vector2(0.17, side * 0.026), 0.017, eyes)
		canvas.draw_circle(Vector2(0.175, side * 0.026), 0.008, Color(0.05, 0.05, 0.05))
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(0.19, -0.008), Vector2(0.215, 0.0), Vector2(0.19, 0.008)]), bill)

static func _mirror_y(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p.x, -p.y))
	return out

## The bird drawn under a screen point, if any (moving ones over still ones):
## [what it's round ({colony, bird: the one clicked}), its colony ({count, species})], or []; `reach`
## times its usual reach (smaller: only right on a bird).
func _birds_at(screen_pos: Vector2, reach := 1.0) -> Array:
	if not Settings.birds:
		return []  # (None drawn: none to click.)
	reach *= BIRD_HIT_REACH
	var native: Object = BirdLife.shared().native
	if native != null:
		# (bird_hit_at: the bird itself too; hit_at, its colony only, in an older library.)
		var hit: Vector2i = native.bird_hit_at(screen_pos, reach) if native.has_method(&"bird_hit_at") else Vector2i(native.hit_at(screen_pos, reach), -1)
		if hit.x < 0:
			return []
		var colony: Dictionary = Wildlife.shared().colonies[hit.x]
		var about := {colony = hit.x}
		if hit.y >= 0:
			about.bird = hit.y
		return [about, {count = int(colony.count), species = [colony.species]}]
	for hits: Array in [_bird_hits, _still_hits]:
		for i in range(hits.size() - 1, -1, -1):
			var hit: Array = hits[i]
			if (hit[0] as Vector2).distance_to(screen_pos) <= float(hit[1]) * reach:
				var about: Dictionary = (hit[2] as Dictionary).duplicate()
				about.bird = hit[4]  # (The one clicked: its Follow follows it.)
				return [about, hit[3]]
	return []

# --- Wonders of the world ------------------------------------------------------

## The wonders of the world (GameData.wonders) on the full-color map, each its
## size in the world (wonders.json km, exaggerated so it reads), growing and
## shrinking with the map like the land; shown once WONDER_MIN_PX across.
## Most are their picture, centered on their spot (_wonder_spot(): moved just
## far enough that it never covers a port's marina, even zoomed right in); the
## lost ancient wonders faded. Four follow their real course (wonders.json
## line): the Great Wall as a strip of grey brick wall with battlements and
## watchtowers, the Grand Canyon as a layered gorge with the Colorado at its
## bottom, the Great Barrier Reef as reefs strung along Queensland's coast
## out to sea, and the Northern Lights as shimmering curtains over Lapland,
## brightest at night. Names show under them once they're WONDER_LABEL_PX
## across, clear of the ports' names. Remembers where each was drawn, for
## clicks (_wonder_at()). Shown in locked regions too: they're world-famous.
func _draw_wonders() -> void:
	_canvas = _wonder_layer
	_wonder_hits.clear()
	if gray_mode:
		return
	if _wonder_textures.is_empty():
		for item: Dictionary in GameData.wonders:
			var path: String = WONDER_ART_DIR + str(item.id) + ".svg"
			_wonder_textures.append(load(path) if ResourceLoader.exists(path) else null)
	var km := _zoom / KM_PER_DEGREE
	var screen := Rect2(Vector2.ZERO, size)
	var font := get_theme_default_font()
	var labels: Array[Rect2] = []
	for port_label: Array in _port_labels:
		labels.append((port_label[1] as Rect2).grow(LABEL_PADDING))
	var pictures := []  # [middle, side, index]
	var view_box := _view_lon_lat_box()
	for i in GameData.wonders.size():
		var item: Dictionary = GameData.wonders[i]
		if item.has("line"):
			var line_box := _wonder_line_box(i)
			if not line_box.intersects(view_box) and not line_box.intersects(Rect2(view_box.position + Vector2(360.0, 0.0), view_box.size)) and not line_box.intersects(Rect2(view_box.position - Vector2(360.0, 0.0), view_box.size)):
				continue  # (Its whole course, and a good way round it, out of view.)
			var t_w := Time.get_ticks_usec()
			match str(item.id):
				"great_wall":
					_draw_great_wall(item, km)
				"grand_canyon":
					_draw_grand_canyon(item, km)
				"great_barrier_reef":
					_draw_barrier_reef(item, km)
				"aurora_borealis":
					_draw_aurora(item, km)
			_prof("wonders.lines", t_w)
			continue
		var side := float(item.get("km", 25.0)) * km
		if side < WONDER_MIN_PX:
			continue
		var middle := world_to_screen(Geo.project(_wonder_spot(i)))
		if _is_hidden(middle) or not screen.grow(side).has_point(middle):
			continue
		pictures.append([middle, side, i])
	pictures.sort_custom(func(a: Array, b: Array) -> bool: return a[0].y + a[1] * 0.5 < b[0].y + b[1] * 0.5)  # Nearer the bottom in front.
	for entry: Array in pictures:
		var middle: Vector2 = entry[0]
		var side: float = entry[1]
		var i: int = entry[2]
		var item: Dictionary = GameData.wonders[i]
		var rect := Rect2(middle - Vector2.ONE * side / 2.0, Vector2.ONE * side)
		if _wonder_textures[i] != null:
			var tint := Color(1, 1, 1, WONDER_LOST_ALPHA) if item.get("kind", "") == "ancient" else Color.WHITE
			_canvas.draw_texture_rect(_wonder_textures[i], rect, false, tint)
		_wonder_hits.append([middle, side * 0.5, str(item.id), []])
		if side >= WONDER_LABEL_PX:
			_wonder_label(str(item.name), Vector2(middle.x, rect.end.y + 1.0), rect.position.y, font, labels)

## The box of (lon, lat) a wonder along a course (wonders.json line) draws
## within, and 5 degrees round it (worked out once; for skipping it).
func _wonder_line_box(index: int) -> Rect2:
	if not _wonder_line_boxes.has(index):
		var line: Array = GameData.wonders[index].get("line", [])
		var box := Rect2(Vector2(float(line[0][0]), float(line[0][1])), Vector2.ZERO)
		for point: Array in line:
			box = box.expand(Vector2(float(point[0]), float(point[1])))
		_wonder_line_boxes[index] = box.grow(5.0)
	return _wonder_line_boxes[index]

## A wonder's name centered at a point (its top), or over `above` if that
## spot's taken; not at all if both are (labels: what's already there).
func _wonder_label(text: String, under: Vector2, above: float, font: Font, labels: Array[Rect2]) -> void:
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, WONDER_FONT_SIZE)
	var label := Rect2(Vector2(under.x - text_size.x / 2.0, under.y), text_size)
	if labels.any(func(other: Rect2) -> bool: return other.intersects(label)):
		label.position.y = above - text_size.y - 1.0
		if labels.any(func(other: Rect2) -> bool: return other.intersects(label)):
			return
	labels.append(label)
	var baseline := label.position + Vector2(0, font.get_ascent(WONDER_FONT_SIZE))
	_canvas.draw_string_outline(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, WONDER_FONT_SIZE, 3, Color(1, 1, 1, 0.85))
	_canvas.draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, WONDER_FONT_SIZE, Color(0.23, 0.19, 0.16))

## Where a wonder's picture stands (lon, lat): its own spot, moved
## away from any port whose marina (at its size now: a hub's is bigger) it
## would reach over, till it's WONDER_PORT_GAP_KM clear (straight away, or the
## nearest way round that's still on land). Worked out again when
## the ports' marinas change (a hub founded).
func _wonder_spot(i: int) -> Vector2:
	var key := 0
	for each in GameState.all_companies():
		key += each.hubs.size()
	if key != _wonder_spots_key:
		_wonder_spots_key = key
		_wonder_spots.clear()
	if _wonder_spots.has(i):
		return _wonder_spots[i]
	var item: Dictionary = GameData.wonders[i]
	var spot := Vector2(float(item.lon), float(item.lat))
	var half := float(item.get("km", 25.0)) / 2.0
	_land_ready()
	for attempt in 4:
		var moved := false
		for port: Dictionary in GameData.ports:
			var port_spot := Vector2(float(port.lon), float(port.lat))
			var clear := half + float(_port_layout(port.id).radius) * KM_PER_DEGREE / SHIP_WORLD_ZOOM + WONDER_PORT_GAP_KM
			var gap := Geo.distance_nm(port_spot, spot) * 1.852
			if gap >= clear:
				continue
			var away := Vector2((spot.x - port_spot.x) * cos(deg_to_rad(spot.y)), spot.y - port_spot.y)
			if away.length() < 0.0001:
				away = Vector2(1.0, 0.0)
			away = away.normalized() * (clear + 0.5) / KM_PER_DEGREE
			# Straight away from the port, or (if that's out at sea and the wonder
			# isn't a sea one) the nearest way round from it that's on land.
			var on_land: bool = item.get("kind", "") != "natural" or _on_land(spot)
			var best := port_spot + Vector2(away.x / maxf(cos(deg_to_rad(spot.y)), 0.1), away.y)
			if on_land:
				for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.0, -2.0, 2.6, -2.6, PI]:
					var way := away.rotated(turn)
					var there := port_spot + Vector2(way.x / maxf(cos(deg_to_rad(spot.y)), 0.1), way.y)
					if _on_land(there):
						best = there
						break
			spot = best
			moved = true
		if not moved:
			break
	_wonder_spots[i] = spot
	return spot

## A line wonder's course on screen: its points (lon, lat) as screen points,
## in runs broken where it goes round the far side.
func _wonder_runs(item: Dictionary) -> Array:
	var runs := []
	var run := PackedVector2Array()
	for point: Array in item.line:
		var at := world_to_screen(Geo.project(Vector2(float(point[0]), float(point[1]))))
		if _is_hidden(at):
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array()
			continue
		run.append(at)
	if run.size() > 1:
		runs.append(run)
	return runs

## The Great Wall: a strip of grey brick wall along its course, its battlements
## along the north side and a watchtower every WALL_TOWER_KM; brick courses
## and a walkway once it's wide enough to see them.
func _draw_great_wall(item: Dictionary, km: float) -> void:
	var width := maxf(float(item.km) * km, 1.6)
	var stone := Color(0.66, 0.66, 0.63)
	var dark := Color(0.23, 0.19, 0.16)
	for run: PackedVector2Array in _wonder_runs(item):
		_canvas.draw_polyline(run, dark, width + 2.0, true)
		_canvas.draw_polyline(run, stone, width, true)
		if width >= 5.0:
			_canvas.draw_polyline(run, Color(0.76, 0.75, 0.71), width * 0.45, true)  # The walkway.
		# Along it: battlements, brick courses and towers, spaced in the world.
		var crenel := maxf(width * 0.9, 3.0)
		var tower_every := WALL_TOWER_KM * km
		var since_tower := tower_every * 0.5
		var towers := tower_every > width * 2.5
		var step := crenel if width >= 6.0 else maxf(tower_every * 0.25, 2.0)
		# Only the stretches on screen are drawn piece by piece: zoomed in, most
		# of it's well off it (thousands of pieces otherwise, drawn every frame).
		var screen_near := Rect2(Vector2.ZERO, size).grow(maxf(width * 2.0, 8.0))
		for s in range(run.size() - 1):
			var a := run[s]
			var b := run[s + 1]
			var length := a.distance_to(b)
			if length < 0.5:
				continue
			if not screen_near.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				since_tower = _wall_towers_skipped(since_tower, ceili(length / step), step, tower_every, towers)
				continue
			var way := (b - a) / length
			var north := way.orthogonal()
			if north.y > 0.0:
				north = -north  # (The battlements face north: up the screen.)
			var d := 0.0
			while d < length:
				var at := a + way * d
				if width >= 6.0:
					_canvas.draw_rect(Rect2(at + north * (width * 0.5) - Vector2.ONE * crenel * 0.25, Vector2.ONE * crenel * 0.5), dark)
					_canvas.draw_line(at + north * width * 0.45, at - north * width * 0.45, Color(0.55, 0.55, 0.52), 1.0)
				if since_tower >= tower_every and towers:
					since_tower = 0.0
					var tower := maxf(width * 1.7, 3.0)
					_canvas.draw_rect(Rect2(at - Vector2.ONE * tower / 2.0, Vector2.ONE * tower), dark)
					_canvas.draw_rect(Rect2(at - Vector2.ONE * (tower / 2.0 - 1.0), Vector2.ONE * (tower - 2.0)), Color(0.72, 0.71, 0.67))
				d += step
				since_tower += step
		_wonder_line_hit(item, run, width)
	_wonder_line_label(item, km)

## How far along the wall since its last tower (`since`) it'd be after `steps`
## more pieces of `step` px (a tower, and the count starting again, whenever
## it reaches `tower_every`): the same as stepping along a stretch skipped
## (see _draw_great_wall()), so the towers keep their places along the wall.
static func _wall_towers_skipped(since: float, steps: int, step: float, tower_every: float, towers: bool) -> float:
	if steps <= 0:
		return since
	if not towers:
		return since + steps * step
	# The first piece with a tower (where since has reached tower_every), then
	# one every `period` pieces; after the last, the count's run on from 0.
	var first := maxi(ceili((tower_every - since) / step), 0)
	if first >= steps:
		return since + steps * step
	var period := maxi(ceili(tower_every / step), 1)
	return ((steps - 1 - first) % period + 1) * step

## The Grand Canyon: a gorge along the Colorado, its rims red-orange, its
## walls in layered bands, the river blue at the bottom.
func _draw_grand_canyon(item: Dictionary, km: float) -> void:
	var width := maxf(float(item.km) * km, 1.8)
	for run: PackedVector2Array in _wonder_runs(item):
		_canvas.draw_polyline(run, Color(0.23, 0.19, 0.16), width + 2.0, true)
		_canvas.draw_polyline(run, Color(0.85, 0.5, 0.3), width, true)
		_canvas.draw_polyline(run, Color(0.72, 0.36, 0.2), width * 0.72, true)
		_canvas.draw_polyline(run, Color(0.9, 0.62, 0.38), width * 0.5, true)
		_canvas.draw_polyline(run, Color(0.6, 0.27, 0.15), width * 0.3, true)
		_canvas.draw_polyline(run, Color(0.37, 0.62, 0.82), maxf(width * 0.1, 1.0), true)
		_wonder_line_hit(item, run, width)
	_wonder_line_label(item, km)

## The Great Barrier Reef: reefs strung along its course out to sea from the
## coast, every REEF_SPACING_KM, each a pale lagoon in a ring of coral (dots
## of pink, orange, purple and yellow), staggered in and out.
func _draw_barrier_reef(item: Dictionary, km: float) -> void:
	var patch := float(item.km) * km
	if patch < 2.0:
		return
	var corals := [Color(0.95, 0.42, 0.42), Color(0.95, 0.64, 0.24), Color(0.69, 0.42, 0.84), Color(0.95, 0.82, 0.29)]
	var line: Array = item.line
	var reach := patch * 0.6
	for s in range(line.size() - 1):
		var a := Vector2(float(line[s][0]), float(line[s][1]))
		var b := Vector2(float(line[s + 1][0]), float(line[s + 1][1]))
		var seaward := Vector2(b.y - a.y, -(b.x - a.x)).normalized() * -1.0  # (The coast is to the west.)
		var leg_km := Geo.distance_nm(a, b) * 1.852
		var count := maxi(roundi(leg_km / REEF_SPACING_KM), 1)
		for k in count:
			var t := (k + 0.5) / count
			var out := 0.1 + 0.25 * fposmod(sin(float(s * 7 + k) * 12.9898) * 43758.5453, 1.0)
			var spot := a.lerp(b, t) + seaward * out
			var at := world_to_screen(Geo.project(spot))
			if _is_hidden(at) or not Rect2(Vector2.ZERO, self.size).grow(reach).has_point(at):
				continue
			_canvas.draw_circle(at, patch * 0.5, Color(0.55, 0.88, 0.86, 0.85))
			_canvas.draw_circle(at, patch * 0.32, Color(0.75, 0.95, 0.92, 0.9))
			if patch >= 8.0:
				for c in 8:
					var angle := TAU * c / 8.0 + s + k
					_canvas.draw_circle(at + Vector2.from_angle(angle) * patch * 0.42, patch * 0.08, corals[(c + k) % corals.size()])
			_wonder_hits.append([at, maxf(patch * 0.5, 6.0), str(item.id), []])
	_wonder_line_label(item, km)

## The Northern Lights: soft curtains of green (purple at their tops) rising
## from their course over Lapland, in folds; brightest in the dark, faint
## by day (by the sun there).
func _draw_aurora(item: Dictionary, km: float) -> void:
	var height := AURORA_HEIGHT_KM * km
	if height < 6.0:
		return
	var hour := Birds.local_hour(23.0, float(GameState.calendar_time()))
	var dark := 1.0 - Birds.daylight(hour)
	var strength := lerpf(0.18, 0.75, dark)
	var screen_near := Rect2(Vector2.ZERO, size).grow(height * 1.2)  # (Only the stretches on screen: see _draw_great_wall().)
	for run: PackedVector2Array in _wonder_runs(item):
		for s in range(run.size() - 1):
			var a := run[s]
			var b := run[s + 1]
			if not screen_near.intersects(Rect2(a, Vector2.ZERO).expand(b)):
				continue
			var length := a.distance_to(b)
			var strips := maxi(int(length / maxf(height * 0.08, 2.0)), 1)
			for k in strips:
				var t := float(k) / strips
				var base := a.lerp(b, t)
				var sway := sin((s * strips + k) * 0.35) * height * 0.06
				var tall := height * (0.7 + 0.3 * sin((s * strips + k) * 0.2))
				var top := base + Vector2(sway, -tall)
				var step := (b - a) / strips
				var green := Color(0.25, 0.88, 0.54, 0.45 * strength)
				var purple := Color(0.69, 0.42, 0.84, 0.0)
				_canvas.draw_polygon(PackedVector2Array([base, base + step, top + step, top]),
					PackedColorArray([green, green, purple, purple]))
	_wonder_line_label(item, km)

## Clicking near a line wonder's course opens it (see _wonder_at()).
func _wonder_line_hit(item: Dictionary, run: PackedVector2Array, width: float) -> void:
	_wonder_hits.append([Vector2.INF, maxf(width, 8.0), str(item.id), run])

## A line wonder's name, at its spot (wonders.json lon, lat) once it's zoomed in enough.
func _wonder_line_label(item: Dictionary, km: float) -> void:
	if WONDER_LINE_LABEL_KM * km < WONDER_LABEL_PX:
		return
	var at := world_to_screen(Geo.project(Vector2(float(item.lon), float(item.lat))))
	if _is_hidden(at) or not Rect2(Vector2.ZERO, size).has_point(at):
		return
	var labels: Array[Rect2] = []
	for port_label: Array in _port_labels:
		labels.append((port_label[1] as Rect2).grow(LABEL_PADDING))
	_wonder_label(str(item.name), at + Vector2(0.0, 6.0), at.y - 6.0, get_theme_default_font(), labels)

## The wonder drawn under a screen point (the nearest if two are close), or "".
func _wonder_at(screen_pos: Vector2) -> String:
	var best := ""
	var best_dist := INF
	for hit: Array in _wonder_hits:
		var dist := INF
		var run: PackedVector2Array = hit[3] if not (hit[3] as Array).is_empty() else PackedVector2Array()
		if run.is_empty():
			dist = (hit[0] as Vector2).distance_to(screen_pos)
		else:
			for s in range(run.size() - 1):
				dist = minf(dist, Geometry2D.get_closest_point_to_segment(screen_pos, run[s], run[s + 1]).distance_to(screen_pos))
		if dist <= float(hit[1]) and dist < best_dist:
			best_dist = dist
			best = hit[2]
	return best

## Where a wonder stands on screen, or Vector2.INF round the far side.
func wonder_screen_position(id: String) -> Vector2:
	for i in GameData.wonders.size():
		if GameData.wonders[i].id == id:
			var at := world_to_screen(Geo.project(_wonder_spot(i)))
			return Vector2.INF if _is_hidden(at) else at
	return Vector2.INF


## Where a bird colony away from its home is on screen (the leader of its V
## on the wing, or the first of its seabirds out at sea: BirdLife), else its
## home; Vector2.INF round the far side.
func colony_screen_position(index: int) -> Vector2:
	var wildlife := Wildlife.shared()
	var colony: Dictionary = wildlife.colonies[index]
	var cal := float(GameState.calendar_time())
	var where: String = wildlife.colony_where(colony, cal)[0]
	var birds := BirdLife.shared().birds_of(index)
	if (colony.cls == "seabirds" or where.begins_with("to_")) and not birds.is_empty():
		var at := world_to_screen(Geo.project(BirdLife.shared().bird_state(birds[0], wildlife.bird_time, cal).pos))
		return Vector2.INF if _is_hidden(at) else at
	return home_screen_position("colony", index)

# --- Seasons -------------------------------------------------------------------------

## The land drawings change with the seasons: a kind's art can have a spring
## (<kind>_blossom.svg), autumn (_autumn), winter (_bare) and snow (_snow)
## version in DECOR_ART_DIR (see _load_decor()), shown by the calendar
## (game_config calendar) for each drawing's hemisphere (the south's seasons
## six months on): spring March to May, summer June to August, autumn
## September to November, winter December to February (_season_of()). Each
## drawing changes over at its own moment in the season's first
## SEASON_CHANGE_DAYS days. Snow lies (the ground white in the globe shader,
## the trees their snow versions) beyond the snow line, SNOW_LAT_BY_MONTH
## degrees from the equator (January first; the south six months on), eased
## from each month to the next. Worked out once a calendar hour
## (_update_seasons()) for DecorSim (set_seasons()) and the shader.
const SEASON_SUFFIXES := ["blossom", "autumn", "bare", "snow"]
const SEASON_CHANGE_DAYS := 24.0
const SNOW_LAT_BY_MONTH := [42.0, 42.0, 48.0, 58.0, 66.0, 72.0, 72.0, 72.0, 66.0, 58.0, 50.0, 44.0]
enum { SEASON_WINTER, SEASON_SPRING, SEASON_SUMMER, SEASON_AUTUMN }
## Each kind's seasonal art: kind index -> {suffix: index into _decor_textures}.
static var _decor_variants := {}
## The season as last worked out: its key (the calendar hour) and [north,
## south], each {before, now, snow (PackedInt32Array: a texture by kind), mix,
## snow_lat}; [] till then.
var _season_key := -1
var _season: Array = []

## The season in a month (1 to 12) in a hemisphere (SEASON_*).
static func _season_of(month: int, north: bool) -> int:
	var m := month if north else (month + 5) % 12 + 1
	@warning_ignore("integer_division")
	return (m / 3) % 4

## A kind's texture (an index into _decor_textures) in a season, or in the
## snow (its snow version, else its bare one, else itself).
static func _season_texture(kind: int, season: int, snowy: bool) -> int:
	var variants: Dictionary = _decor_variants.get(kind, {})
	if snowy:
		return int(variants.get("snow", variants.get("bare", kind)))
	match season:
		SEASON_SPRING:
			return int(variants.get("blossom", kind))
		SEASON_AUTUMN:
			return int(variants.get("autumn", kind))
		SEASON_WINTER:
			return int(variants.get("bare", kind))
	return kind

## A drawing's own moment (0 to 1) in a season's change (see _season): as DecorSim.
static func _decor_moment(i: int) -> float:
	var x := (i * 2654435761) & 0xffffffff
	x ^= x >> 15
	x = (x * 2246822519) & 0xffffffff
	x ^= x >> 13
	return float(x & 0xffffff) / 16777216.0

## The seasons now, for the drawings and the snow on the land (see _season).
func _update_seasons() -> void:
	if gray_mode:
		return
	var date := Time.get_datetime_dict_from_unix_time(GameState.calendar_time())
	var key := (int(date.year) * 12 + int(date.month)) * 31 * 24 + int(date.day) * 24 + int(date.hour)
	if key == _season_key:
		return
	_season_key = key
	_load_decor()
	var kinds := GameData.world_map.decor_kind_names.size()
	var into_month := (int(date.day) - 1 + int(date.hour) / 24.0)
	_season = []
	for north: bool in [true, false]:
		var m: int = int(date.month) if north else (int(date.month) + 5) % 12 + 1
		var season := _season_of(int(date.month), north)
		var before_season := (season + 3) % 4
		var mix := 1.0 if m % 3 != 0 else clampf(into_month / SEASON_CHANGE_DAYS, 0.0, 1.0)
		var snow_lat := lerpf(float(SNOW_LAT_BY_MONTH[m - 1]), float(SNOW_LAT_BY_MONTH[m % 12]), clampf(into_month / 30.0, 0.0, 1.0))
		var before := PackedInt32Array()
		var now := PackedInt32Array()
		var snow := PackedInt32Array()
		for kind in kinds:
			before.append(_season_texture(kind, before_season, false))
			now.append(_season_texture(kind, season, false))
			snow.append(_season_texture(kind, season, true))
		_season.append({before = before, now = now, snow = snow, mix = mix, snow_lat = snow_lat})
	if _decor_native != null and _decor_native.has_method(&"set_seasons"):  # (An older library: the trees keep their summer art.)
		_decor_native.set_seasons(_season[0], _season[1])
	_globe_masked.set_shader_parameter(&"snow_lat_north", _season[0].snow_lat)
	_globe_masked.set_shader_parameter(&"snow_lat_south", _season[1].snow_lat)
	_decor_layer.queue_redraw()

## A drawing's texture now (see _season): in the snow beyond its hemisphere's
## snow line, else changing over at its own moment.
func _decor_texture_now(i: int, kind: int) -> int:
	if _season.is_empty():
		return kind
	var p := _decor_units[i]
	var side: Dictionary = _season[1 if p.z < 0.0 else 0]
	if absf(rad_to_deg(asin(clampf(p.z, -1.0, 1.0)))) >= float(side.snow_lat):
		return side.snow[kind]
	return side.now[kind] if _decor_moment(i) < float(side.mix) else side.before[kind]

# --- Night ---------------------------------------------------------------------------

## Night and day (World map only; see _update_night()): the side of the globe
## turned from the sun is darkened (scripts/ui/night.gdshader), with dusk and
## dawn a soft band between. The sun stands over the sub-solar point of the
## calendar's moment (game_config calendar: 20 calendar minutes a second of
## play, so a day is 72 s at 1x; the calendar being Greenwich time,
## GameState.clock_longitude(), it is noon at Greenwich at 12:00 GMT), tilted with the seasons (SUN_TILT_DEG). Two
## darkenings: NIGHT_DARKNESS of the map art, land drawings, marinas and
## weather is lost at the darkest, and NIGHT_OVER_DARKNESS more of the lanes,
## ports, labels, birds and ships over them (so the names still read), and
## over it all the lights (_draw_lights()): ships' navigation lights (red to
## port, green to starboard, white at the masthead and stern) and the glow of
## their decks, the marinas' entrance lights and quay lamps, each port's
## lighthouse (on a pad of quay behind the industry, LIGHTHOUSE_ROOM inland,
## sweeping its beam round once every LIGHTHOUSE_TURN_S of play) and, zoomed
## out, the ports' towns as warm glows. The ships' and the marinas' lights come on
## under a storm's cloud too, by day (_dark_at(), STORM_LIGHTS_DARK).
const NIGHT_DARKNESS := 0.9
const NIGHT_OVER_DARKNESS := 0.6
const NIGHT_SHADER := preload("res://scripts/ui/night.gdshader")
const SUN_TILT_DEG := 23.44
const LIGHT_WARM := Color(1.0, 0.86, 0.55)
const LIGHT_RED := Color(1.0, 0.22, 0.15)
const LIGHT_GREEN := Color(0.25, 1.0, 0.4)
const LIGHT_WHITE := Color(1.0, 0.98, 0.9)
const LIGHTHOUSE_ROOM := 3.0
const LIGHTHOUSE_RADIUS := 0.9
const LIGHTHOUSE_BEAM_RADII := 2.6
const LIGHTHOUSE_TURN_S := 6.0
## Under a storm's cloud the lights come on too, this dark at its thickest (see _dark_at()).
const STORM_LIGHTS_DARK := 0.85
const LIGHTHOUSE_RED := Color("#c8364a")
const TOWN_GLOW_PX := {small = 7.0, medium = 10.0, large = 14.0, giant = 18.0}
var _night := ColorRect.new()
var _night_over := ColorRect.new()
var _night_material := ShaderMaterial.new()
var _night_over_material := ShaderMaterial.new()
var _lights_layer := Control.new()
## Towards the sun (the sub-solar point on the unit sphere), and whether the night shows at all.
var _sun := Vector3(1.0, 0.0, 0.0)
var _night_shown := false
## Each port's night (0 day to 1), kept while the sun stands still enough (see _draw_lights()).
var _port_nights := PackedFloat32Array()
var _port_nights_sun := Vector3.ZERO

## True if any of the view (its middle and corners) is in the night.
func _any_night_in_view() -> bool:
	for corner: Vector2 in [size / 2.0, Vector2.ZERO, Vector2(size.x, 0.0), size, Vector2(0.0, size.y)]:
		if _night_at(_unit(screen_to_world(corner))) >= 0.03:
			return true
	return false
## Which way shadows fall on screen (a unit vector times their length for a
## unit of height: longer with the sun low), from the sun's place over the
## view's middle (see _update_shadow_dir()); down and to the right by default.
var _shadow_dir := Vector2(0.7, 0.7)
var _last_shadow_key := []
## The storms this frame, for the lights: [where on the unit sphere, radius (radians), strength] each.
var _storm_shade := []
## The ships drawn this frame where it's dark: [at, angle, length px, width px, how dark] each.
var _lit_ships := []
## A soft round glow (white, fading out), for the lights.
static var _glow_texture: Texture2D = null

## The night's layers: the dark over the map art and the marinas, the lighter
## dark over the lanes, ports and ships, and the lights over it all.
func _add_night_layers() -> void:
	for pair: Array in [[_night, _night_material, NIGHT_DARKNESS], [_night_over, _night_over_material, NIGHT_OVER_DARKNESS]]:
		var rect: ColorRect = pair[0]
		var material: ShaderMaterial = pair[1]
		material.shader = NIGHT_SHADER
		material.set_shader_parameter(&"darkness", float(pair[2]))
		rect.material = material
		rect.color = Color.WHITE
		rect.mouse_filter = MOUSE_FILTER_IGNORE
		rect.set_anchors_preset(PRESET_FULL_RECT)
		rect.visible = false
	_lights_layer.mouse_filter = MOUSE_FILTER_IGNORE
	_lights_layer.set_anchors_preset(PRESET_FULL_RECT)
	_lights_layer.draw.connect(func() -> void:
		var t0 := Time.get_ticks_usec()
		_draw_lights()
		_prof("lights", t0))
	# The first dark under the lanes and ports (before _static_layer), the
	# second and the lights over everything.
	add_child(_night)
	move_child(_night, _static_layer.get_index())
	add_child(_night_over)
	add_child(_lights_layer)

## Where the sun stands now, and the night's shaders with it (every frame).
## With day and night off (Settings.night "off") it's always day: no dark, no
## lights, and the sun stands still over the view's north-west at
## FIXED_SUN_ELEVATION, so the shadows fall south-east and stay put.
const FIXED_SUN_ELEVATION := 0.6
func _update_night() -> void:
	var on := show_ships and not gray_mode
	_night_shown = on and Settings.day_night
	_night.visible = _night_shown
	_night_over.visible = _night_shown
	if not on:
		return
	if not Settings.day_night:
		var center := _unit(screen_to_world(size / 2.0))
		var north_west := (_up - _right).normalized()
		_sun = (center * FIXED_SUN_ELEVATION + north_west * sqrt(1.0 - FIXED_SUN_ELEVATION * FIXED_SUN_ELEVATION)).normalized()
		_update_shadow_dir()
		return
	var unix := GameState.calendar_time()
	var date := Time.get_datetime_dict_from_unix_time(unix)
	var day_of_year := int([0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334][int(date.month) - 1]) + int(date.day)
	var tilt := deg_to_rad(SUN_TILT_DEG) * sin(TAU * (day_of_year - 81) / 365.0)
	var hours := fposmod(float(unix), 86400.0) / 3600.0
	var lon := deg_to_rad((12.0 - hours) * 15.0 + GameState.clock_longitude())  # (The calendar is Greenwich time.)
	_sun = Vector3(cos(tilt) * cos(lon), cos(tilt) * sin(lon), sin(tilt))
	_update_shadow_dir()
	_storm_shade.clear()
	for storm: Dictionary in GameState.weather.storms:
		_storm_shade.append([_unit(Geo.project(Vector2(storm.lon, storm.lat))), float(storm.radius_nm) / Geo.EARTH_RADIUS_NM, Weather.intensity(storm)])
	# (Half as dark, if that's the setting: the darkness scaled, the lights the same.)
	var share := Settings.night_share()
	for pair: Array in [[_night_material, NIGHT_DARKNESS], [_night_over_material, NIGHT_OVER_DARKNESS]]:
		var material: ShaderMaterial = pair[0]
		material.set_shader_parameter(&"east", _right)
		material.set_shader_parameter(&"north", _up)
		material.set_shader_parameter(&"toward", _toward)
		material.set_shader_parameter(&"center", size / 2.0)
		material.set_shader_parameter(&"radius", _radius())
		material.set_shader_parameter(&"sun", _sun)
		material.set_shader_parameter(&"darkness", float(pair[1]) * share)
	_lights_layer.queue_redraw()

## Shadows fall away from the sun: its direction on screen from the view's
## middle (the sun's unit vector's part along the ground there), their length
## by its height (long at dawn and dusk, short at noon; by night a soft
## moonlight length).
func _update_shadow_dir() -> void:
	var center := _unit(screen_to_world(size / 2.0))
	var elevation := center.dot(_sun)
	var along := _sun - center * elevation
	if along.length() < 0.001:
		_shadow_dir = Vector2(0.7, 0.7)
		return
	var screen_sun := (_unit_to_screen((center + along.normalized() * 0.002).normalized()) - _unit_to_screen(center)).normalized()
	var length := 1.2 if elevation <= 0.05 else clampf(sqrt(1.0 - elevation * elevation) / elevation * 0.45, 0.25, 2.2)
	_shadow_dir = -screen_sun * length
	var key := _shadow_key()
	if key != _last_shadow_key:  # (The marinas are drawn again with their shadows moved.)
		_last_shadow_key = key
		_update_marinas()

## A building's shadow offset in a marina's item (dock units times the dock
## scale, in screen px): the sun's direction, turned back if the marina is being
## recorded (its item turns it into place).
func _shadow_drop(port_id: String, height: float) -> Vector2:
	var drop := _shadow_dir * height * dock_scale(port_id)
	if port_id == _recording_marina:
		drop = drop.rotated(-(_port_sea_angle(port_id) + _port_turn(port_id)))
	return drop

## The shadows' direction, coarsely, for the marina items' keys (they're drawn again when it changes enough).
func _shadow_key() -> Array:
	return [roundi(_shadow_dir.angle() / 0.2), roundi(_shadow_dir.length() * 3.0)]

## How dark it is at a point on the unit sphere (0 day, 1 the dead of night): as the shader.
func _night_at(unit: Vector3) -> float:
	return 1.0 - smoothstep(-0.14, 0.1, unit.dot(_sun))

## How dark a storm's cloud makes it at a point on the unit sphere (0 clear, STORM_LIGHTS_DARK
## under the thickest), as the sky draws it: thick out to a third of its radius, thinning to its edge.
func _storm_dark_at(unit: Vector3) -> float:
	var dark := 0.0
	for storm: Array in _storm_shade:
		var d := (unit - (storm[0] as Vector3)).length() / float(storm[1])
		if d < 1.0:
			dark = maxf(dark, (1.0 - smoothstep(0.35, 1.0, d)) * lerpf(0.6, 1.0, float(storm[2])) * STORM_LIGHTS_DARK)
	return dark

## How dark it is at a point, by night or under a storm: when the ships' and the marinas' lights come on.
func _dark_at(unit: Vector3) -> float:
	return maxf(_night_at(unit), _storm_dark_at(unit))

## Notes a ship drawn where it's dark, for its lights (see _draw_lights()).
func _note_lit_ship(at: Vector2, angle: float, look: Array, scale: float) -> void:
	if not _night_shown:
		return
	var night := _dark_at(_unit(screen_to_world(at)))
	if night > 0.03:
		var size_px: Vector2 = (look[7] as Rect2).size * scale
		_lit_ships.append([at, angle, size_px.x, size_px.y, night])

## A marina smaller than this on screen (its jetty's radius, px) shows a town's glow at night, not its lamps.
const MARINA_LIGHTS_MIN_PX := 40.0
## The towns' glows at night: one quad of the glow texture per lit port, as one multimesh (see _draw_lights()).
static var _glow_mm: MultiMesh = null
static var _town_glow_texture: Texture2D = null

static func _glow_multimesh() -> MultiMesh:
	if _glow_mm == null:
		var mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_glow_mm = MultiMesh.new()
		_glow_mm.transform_format = MultiMesh.TRANSFORM_2D
		_glow_mm.use_colors = true
		_glow_mm.mesh = mesh
		_glow_mm.instance_count = 400
	return _glow_mm

## A town's glow from afar: the glow with a bright core (the lamps' dot in the same picture).
static func _town_glow() -> Texture2D:
	if _town_glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.16, 0.2, 0.5, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.75), Color(1.0, 1.0, 1.0, 0.25), Color(1.0, 1.0, 1.0, 0.0)])
		var texture := GradientTexture2D.new()
		texture.width = 64
		texture.height = 64
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.gradient = gradient
		_town_glow_texture = texture
	return _town_glow_texture

static func _glow() -> Texture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
		gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.3), Color(1.0, 1.0, 1.0, 0.0)])
		var texture := GradientTexture2D.new()
		texture.width = 64
		texture.height = 64
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.gradient = gradient
		_glow_texture = texture
	return _glow_texture

## Where a port's lighthouse stands (dock units): on its pad of quay behind the industry.
static func _lighthouse_spot(layout: Dictionary) -> Vector2:
	return Vector2(_quay_inland(layout) - LIGHTHOUSE_ROOM * 0.5, float(layout.radius) * 0.55)

## A port's lighthouse by day (see _draw_marina()): a round tower seen from
## above, white with a red band and its lantern on top, its shadow beside it.
func _draw_lighthouse(port_id: String, layout: Dictionary, scale: float) -> void:
	var at := _dock_point(port_id, _lighthouse_spot(layout))
	var r := maxf(LIGHTHOUSE_RADIUS * scale, 1.5)
	_disc(at + Vector2(r * 0.5, r * 0.5), r * 1.05, Color(0.0, 0.0, 0.0, 0.22))
	_disc(at, r, Color(0.96, 0.96, 0.95))
	_canvas.draw_arc(at, r, 0.0, TAU, 24, QUAY_EDGE, 1.0, true)
	_disc(at, r * 0.64, LIGHTHOUSE_RED)
	_disc(at, r * 0.4, Color(0.96, 0.96, 0.95))
	_disc(at, r * 0.24, Color(0.16, 0.17, 0.2))

## The lights in the dark (see _update_night()), over everything, drawn every frame.
func _draw_lights() -> void:
	_canvas = _lights_layer
	if GameState.divine.comet_up():
		_draw_comet(GameState.play_time)
	var t_ships := Time.get_ticks_usec()
	if not _night_shown:
		_lit_ships.clear()
		_hide_marina_lights({})
		return
	var glow := _glow()
	# The ships: their decks' glow, their navigation lights, a few deck lamps.
	for lit: Array in _lit_ships:
		var at: Vector2 = lit[0]
		var length: float = lit[2]
		var width: float = lit[3]
		var night: float = lit[4]
		_canvas.draw_set_transform(at, float(lit[1]), Vector2.ONE)
		_canvas.draw_texture_rect(glow, Rect2(-length * 0.75, -width * 1.3, length * 1.5, width * 2.6), false, Color(LIGHT_WARM, 0.45 * night))
		var dot := maxf(width * 0.14, 1.0)
		var halo := dot * 3.0
		for light: Array in [[Vector2(length * 0.36, 0.0), LIGHT_WHITE], [Vector2(-length * 0.46, 0.0), LIGHT_WHITE], [Vector2(0.0, -width * 0.5), LIGHT_RED], [Vector2(0.0, width * 0.5), LIGHT_GREEN]]:
			var p: Vector2 = light[0]
			var tint: Color = light[1]
			_canvas.draw_texture_rect(glow, Rect2(p - Vector2.ONE * halo, Vector2.ONE * halo * 2.0), false, Color(tint, 0.6 * night))
			_canvas.draw_circle(p, dot, Color(tint, night))
		var lamps := clampi(int(length / 6.0), 1, 6)
		for k in lamps:
			_canvas.draw_circle(Vector2(lerpf(-length * 0.3, length * 0.3, (k + 0.5) / lamps), 0.0), dot * 0.7, Color(LIGHT_WARM, 0.9 * night))
	_prof("lights.ships", t_ships)
	_canvas.draw_set_transform_matrix(Transform2D.IDENTITY)
	_lit_ships.clear()
	_draw_wonder_lights(glow)
	# The ports: their marinas' lights, or their towns' glow from afar. By day
	# over the whole view with no storm, nothing to do; else each port's night
	# is kept while the sun stands still enough (_port_nights), and the towns'
	# glows and dots go down as two triangle batches, not two calls a port.
	if _storm_shade.is_empty() and not _any_night_in_view():
		_hide_marina_lights({})
		return
	_marina_lights_shown.clear()
	_marina_light_records = 0
	if _port_nights.size() != GameData.ports.size() or _sun.angle_to(_port_nights_sun) > 0.03:
		_port_nights.resize(GameData.ports.size())
		for i in GameData.ports.size():
			_port_nights[i] = _night_at(_unit(GameData.port_position(str((GameData.ports[i] as Dictionary).id))))
		_port_nights_sun = _sun
	var marinas := _any_marina_shown() and float(_marina_layout(str(Docks.settings().get("hub_berths", "LLLLLLLLLLLLLL")), true).radius) * _ship_scale() >= MARINA_LIGHTS_MIN_PX  # (Too small for lamps to show: a glow, like a town afar.)
	var lit := 0
	var mm := _glow_multimesh()
	for index in _ports_near_view():
		var night := _port_nights[index]
		if night < 0.03 and not marinas:
			continue
		var port_id := str((GameData.ports[index] as Dictionary).id)
		if marinas and _marina_shown(port_id):
			var at := port_screen_position(port_id)
			if _is_hidden(at):
				continue
			var dark := maxf(night, _storm_dark_at(_unit(GameData.port_position(port_id))))  # (Its lights come on under a storm too.)
			if dark >= 0.03:
				var t_m := Time.get_ticks_usec()
				_draw_marina_lights(port_id, dark, glow)
				_prof("lights.marinas", t_m)
		elif night >= 0.03:
			var at := port_screen_position(port_id)
			if _is_hidden(at):
				continue
			var r := float(TOWN_GLOW_PX.get(GameState.port_sizes.band(port_id), 10.0))
			if lit >= mm.instance_count:
				mm.instance_count = lit + 64
			mm.set_instance_transform_2d(lit, Transform2D(0.0, Vector2.ONE * r * 2.0, 0.0, at))
			# (Coloring the ports by a price: the glow takes the port's color, so it shows by night.)
			mm.set_instance_color(lit, Color(LIGHT_WARM if price_commodity.is_empty() else _price_color(port_id), 0.8 * night))
			lit += 1
	mm.visible_instance_count = lit
	if lit > 0:
		_canvas.draw_multimesh(mm, _town_glow())
	_hide_marina_lights(_marina_lights_shown)

## The wonders' own lights at night (wonders.json night_lights: the Golden
## Gate's deck lamps and aircraft lights, the junks' lanterns in Ha Long Bay),
## over their pictures where they were last drawn (_wonder_hits), as dark there is.
func _draw_wonder_lights(glow: Texture2D) -> void:
	for hit: Array in _wonder_hits:
		var middle: Vector2 = hit[0]
		if middle == Vector2.INF:
			continue  # (A wonder along a course: none of these have lamps.)
		var item := GameData.wonder(str(hit[2]))
		var lamps: Array = item.get("night_lights", [])
		if lamps.is_empty():
			continue
		var night := _night_at(_unit(Geo.project(_screen_lon_lat(middle))))
		if night < 0.03:
			continue
		var side := float(hit[1]) * 2.0
		var corner := middle - Vector2.ONE * side / 2.0
		for lamp: Array in lamps:
			var at := corner + Vector2(float(lamp[0]), float(lamp[1])) * side
			var r := float(lamp[2]) * side  # (Its size in the picture, kept to a lamp's few px close in.)
			var halo := clampf(r * 2.5, 2.5, 16.0)
			var tint := Color(str(lamp[3]))
			_canvas.draw_texture_rect(glow, Rect2(at - Vector2.ONE * halo, Vector2.ONE * halo * 2.0), false, Color(tint, 0.5 * float(lamp[4]) * night))
			_canvas.draw_circle(at, clampf(r * 0.3, 0.7, 2.0), Color(tint.lightened(0.3), float(lamp[4]) * night))

## A marina's lights at night: the entrance's red and green, lamps along the
## quay (over the HQ and the industry), and the lighthouse's beam sweeping round.
func _draw_marina_lights(port_id: String, night: float, glow: Texture2D) -> void:
	var layout := _port_layout(port_id)
	var scale := _ship_scale()
	var t_l := Time.get_ticks_usec()
	_show_marina_lights(port_id, layout, night, glow, scale)
	_prof("lights.item", t_l)
	t_l = Time.get_ticks_usec()
	# The lighthouse's beam sweeping round (two beams, opposite), each frame.
	var tower := _dock_point(port_id, _lighthouse_spot(layout))
	var turn := TAU * fposmod(GameState.play_time / LIGHTHOUSE_TURN_S, 1.0)
	var reach := float(layout.radius) * LIGHTHOUSE_BEAM_RADII * scale
	var colors := PackedColorArray([Color(LIGHT_WHITE, 0.55 * night), Color(LIGHT_WHITE, 0.0), Color(LIGHT_WHITE, 0.0), Color(LIGHT_WHITE, 0.0)])
	for k in 2:
		var dir := Vector2.from_angle(_dock_angle(port_id, turn + k * PI))
		_canvas.draw_primitive(PackedVector2Array([tower, tower + dir.rotated(-0.1) * reach, tower + dir * reach * 1.06, tower + dir.rotated(0.1) * reach]), colors, PackedVector2Array())
	_prof("lights.beams", t_l)

## A marina's steady lights (the entrance's red and green, the lamps along the
## quay, the lighthouse's halo and lantern, the town's glow and its windows)
## as a canvas item of its own over the lights layer: drawn once in dock
## units, moved, turned and scaled into place each frame by its pivot and
## faded by the night through modulate, so a big port's thousand lamps and
## windows aren't set again every frame (circles and polygons are costly to
## set). Drawn again when its town's laid out again or the zoom's moved a
## step of MARINA_LIGHTS_ZOOM_STEP (the lamps' least sizes are px); one
## marina's a frame. Hidden with the rest of a port's lights (see _hide_marina_lights()).
var _marina_light_items := {}
var _marina_lights_shown := {}
var _marina_light_records := 0
const MARINA_LIGHTS_ZOOM_STEP := 1.5
func _show_marina_lights(port_id: String, layout: Dictionary, night: float, glow: Texture2D, scale: float) -> void:
	var item: Control = _marina_light_items.get(port_id)
	if item == null:
		item = Control.new()
		item.mouse_filter = MOUSE_FILTER_IGNORE
		item.use_parent_material = true
		item.draw.connect(func() -> void: _record_marina_lights(item))
		var pivot := Node2D.new()
		pivot.add_child(item)
		_lights_layer.add_child(pivot)
		_marina_light_items[port_id] = item
		if not _lights_layer.visibility_changed.is_connected(_lights_visibility_changed):
			_lights_layer.visibility_changed.connect(_lights_visibility_changed)
	var town := _town(port_id, layout)
	var key := [port_id, roundi(log(scale) / log(MARINA_LIGHTS_ZOOM_STEP)), _dock_flips.get(port_id, 1.0), layout.radius, layout.depth, town.is_empty(), _hq_look(port_id)]  # (The HQ's and industry's lights change with them.)
	var recorded := item.has_meta(&"key")
	if not recorded or item.get_meta(&"key") != key:
		if _marina_light_records >= 1:
			if not recorded:
				_set_marina_lights_shown(item, false)  # (Nothing drawn in it yet: its turn next frame.)
				return
		else:
			_marina_light_records += 1
			item.set_meta(&"key", key)
			item.set_meta(&"scale", scale)
			item.set_meta(&"glow", glow)
			item.queue_redraw()
	var pivot := item.get_parent() as Node2D
	pivot.position = port_screen_position(port_id)
	pivot.rotation = _port_sea_angle(port_id) + _port_turn(port_id)
	pivot.scale = Vector2(scale, scale * float(_dock_flips.get(port_id, 1.0)))
	item.modulate = Color(1.0, 1.0, 1.0, night)
	_set_marina_lights_shown(item, true)
	_marina_lights_shown[port_id] = true

func _record_marina_lights(item: Control) -> void:
	if not item.has_meta(&"key"):
		return
	var t0 := Time.get_ticks_usec()
	var key: Array = item.get_meta(&"key")
	var port_id: String = key[0]
	var scale := float(item.get_meta(&"scale", 1.0))
	var glow: Texture2D = item.get_meta(&"glow")
	var layout := _port_layout(port_id)
	var radius: float = layout.radius
	var gap: float = layout.gap
	# (Everything in dock units: the pivot scales and flips it. What has a
	# least size in px is sized for the zoom it's drawn at.)
	for side: float in [-1.0, 1.0]:
		var p := Vector2.from_angle(gap * side) * radius
		var tint: Color = ENTRANCE_LIGHTS[0 if side < 0.0 else 1]
		var halo := maxf(JETTY_WIDTH * 1.8, 5.0 / scale)
		item.draw_texture_rect(glow, Rect2(p - Vector2.ONE * halo, Vector2.ONE * halo * 2.0), false, Color(tint, 0.7))
		item.draw_circle(p, maxf(JETTY_WIDTH * 0.45, 1.2 / scale), tint)
	# The quay's lamps: a warm glow the length of the quay behind the basin.
	var inland := _quay_inland(layout)
	var depth := float(layout.depth) + QUAY_WIDTH
	var along := radius * 2.2
	var across := (-inland - depth) * 2.0
	item.draw_texture_rect(glow, Rect2((inland - depth) / 2.0 - across / 2.0, -along / 2.0, across, along), false, Color(LIGHT_WARM, 0.4))
	_record_harbour_lamps(item, layout, glow, scale)
	_record_hq_lights(item, port_id, layout, glow, scale)
	_record_industry_lights(item, port_id, layout, glow, scale)
	# The lighthouse's halo and lantern (its beam is drawn each frame: see _draw_marina_lights()).
	var tower := _lighthouse_spot(layout)
	var halo := maxf(LIGHTHOUSE_RADIUS * 4.0, 8.0 / scale)
	item.draw_texture_rect(glow, Rect2(tower - Vector2.ONE * halo, Vector2.ONE * halo * 2.0), false, Color(LIGHT_WHITE, 0.8))
	item.draw_circle(tower, maxf(LIGHTHOUSE_RADIUS * 0.3, 1.5 / scale), LIGHT_WHITE)
	# The town: one glow, and all its windows as one run of dashes in its style's warmth.
	var town := _town(port_id, layout)
	if not town.is_empty():
		var reach: float = town.reach
		var tint: Color = town.light
		var town_across := (reach + inland) * 1.6
		var town_along := radius * TOWN_HALF_RADII * 2.4
		item.draw_texture_rect(glow, Rect2(-(reach - inland) / 2.0 - town_across / 2.0, -town_along / 2.0, town_across, town_along), false, Color(tint, 0.35))
		if scale >= TOWN_LIGHTS_MIN_SCALE and not (town.segments as PackedVector2Array).is_empty():
			item.draw_multiline(town.segments, Color(tint, 0.9), maxf(0.22, 1.2 / scale))
	_prof("lights.record", t0)

## A lamp in a marina's lights item (dock units): a soft halo and its bright
## point, each kept to a least size in px at the zoom it's drawn at.
static func _record_lamp(item: Control, glow: Texture2D, at: Vector2, tint: Color, scale: float, size := 1.0) -> void:
	var halo := maxf(HARBOUR_LAMP_HALO * size, 3.5 / scale)
	item.draw_texture_rect(glow, Rect2(at - Vector2.ONE * halo, Vector2.ONE * halo * 2.0), false, Color(tint, 0.55))
	item.draw_circle(at, maxf(HARBOUR_LAMP_DOT * size, 0.8 / scale), tint.lightened(0.35))

## Lamps every HARBOUR_LAMP_STEP between two points (dock units), not at either end.
static func _lamp_points(from: Vector2, to: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := floori(from.distance_to(to) / HARBOUR_LAMP_STEP)
	for k in count:
		points.append(from.lerp(to, (k + 0.5) / count))
	return points

## The harbour's own lamps at night: down every pier to a lamp at its tip,
## along the basin's walls, and round the jetty's arms.
const HARBOUR_LAMP_STEP := 5.0
const HARBOUR_LAMP_HALO := 1.3
const HARBOUR_LAMP_DOT := 0.22
func _record_harbour_lamps(item: Control, layout: Dictionary, glow: Texture2D, scale: float) -> void:
	var half: float = layout.inner
	var depth: float = layout.depth
	var radius: float = layout.radius
	var pier_length: float = layout.pier
	for pier: Array in layout.piers:
		var side: float = pier[0]
		var x := (float(pier[1]) + float(pier[2])) / 2.0
		var root := Vector2(x, side * half)
		var tip := Vector2(x, side * (half - pier_length + 0.4))
		for at in _lamp_points(root, tip):
			_record_lamp(item, glow, at, LIGHT_WARM, scale, 0.8)
		_record_lamp(item, glow, tip, LIGHT_WHITE, scale)
	for wall: Array in [[Vector2(-depth, half), Vector2(-depth, -half)], [Vector2(-0.4, half), Vector2(-depth, half)], [Vector2(-0.4, -half), Vector2(-depth, -half)]]:
		for at in _lamp_points(wall[0], wall[1]):
			_record_lamp(item, glow, at, LIGHT_WARM, scale, 0.8)
	var gap: float = layout.gap
	for side: float in [-1.0, 1.0]:
		var sweep := PI / 2.0 - gap
		var count := maxi(floori(radius * sweep / (HARBOUR_LAMP_STEP * 1.4)), 1)
		for k in count:
			var angle := side * (gap + sweep * (k + 0.5) / count)
			_record_lamp(item, glow, Vector2.from_angle(angle) * radius, LIGHT_WHITE, scale, 0.7)

## An HQ's lights at night: the building's glow in its company's colour and
## warm light, its lit windows (more, and cooler, the bigger it's grown: a
## glass tower's whole face), and red aircraft lights on its corners from
## level HQ_TALL_LEVEL.
const HQ_TALL_LEVEL := 6
func _record_hq_lights(item: Control, port_id: String, layout: Dictionary, glow: Texture2D, scale: float) -> void:
	var owner: Company = null
	for each in GameState.all_companies():
		var hub := each.hub_at(port_id)
		if hub != null and hub.is_hq:
			owner = each
			break
	if owner == null:
		return
	var level := hq_level(owner)
	var foot := _hq_foot(layout, level)
	if foot.size() < 3:
		return
	var box := _bounds(foot)
	var tint := GameState.company_color_value(owner.color)
	item.draw_texture_rect(glow, box.grow(box.size.length() * 0.35), false, Color(LIGHT_WARM.lerp(tint, 0.35), 0.5))
	var window := LIGHT_WARM.lerp(LIGHT_WHITE, clampf(float(level - 3) / 6.0, 0.0, 1.0))
	var step := lerpf(1.6, 0.8, float(level - 1) / float(HQ_LEVELS - 1))
	var dot := maxf(0.1 + 0.012 * level, 0.5 / scale)
	var rows := floori(box.size.x / step)
	var cols := floori(box.size.y / step)
	for r in rows:
		for c in cols:
			var at := box.position + Vector2((r + 0.5) * box.size.x / rows, (c + 0.5) * box.size.y / cols)
			if absi(hash([port_id, r, c, level])) % 5 == 0 or not Geometry2D.is_point_in_polygon(at, foot):
				continue  # (A few windows dark.)
			item.draw_rect(Rect2(at - Vector2.ONE * dot, Vector2.ONE * dot * 2.0), Color(window, 0.6))
	if level >= HQ_TALL_LEVEL:
		for corner: Vector2 in [box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)]:
			_record_lamp(item, glow, corner.lerp(box.get_center(), 0.08), LIGHT_RED, scale, 0.6)

## A hub's industry lit at night: each building (not an empty plot) under a
## sodium floodlight's orange glow, a lamp at each corner of its yard and a
## few lit windows.
const LIGHT_SODIUM := Color(1.0, 0.68, 0.32)
func _record_industry_lights(item: Control, port_id: String, layout: Dictionary, glow: Texture2D, scale: float) -> void:
	var hub := _industry_hub(port_id)
	if hub == null:
		return
	var plots := _industry_plots(layout)
	for slot in mini(plots.size(), Hub.INDUSTRY_SLOTS):
		if str(hub.industries[slot]).is_empty():
			continue
		var plot: Rect2 = plots[slot]
		item.draw_texture_rect(glow, plot.grow(plot.size.x * 0.45), false, Color(LIGHT_SODIUM, 0.5))
		var yard := plot.grow(-plot.size.x * 0.08)
		for corner: Vector2 in [yard.position, Vector2(yard.end.x, yard.position.y), yard.end, Vector2(yard.position.x, yard.end.y)]:
			_record_lamp(item, glow, corner, LIGHT_SODIUM, scale, 0.75)
		var dot := maxf(0.16, 0.6 / scale)
		for k in 6:
			var h := absi(hash([port_id, slot, k]))
			var at := plot.position + plot.size * Vector2(0.25 + 0.5 * float(h % 97) / 97.0, 0.25 + 0.5 * float(h / 97 % 89) / 89.0)
			item.draw_rect(Rect2(at - Vector2.ONE * dot, Vector2.ONE * dot * 2.0), Color(LIGHT_WARM, 0.85))

func _set_marina_lights_shown(item: Control, shown: bool) -> void:
	if bool(item.get_meta(&"shown", true)) != shown:
		item.set_meta(&"shown", shown)
		RenderingServer.canvas_item_set_visible(item.get_canvas_item(), shown)

## Showing or hiding the map (another tab and back) sets every light item's
## visibility on the server to the map's, whatever _set_marina_lights_shown()
## set it to: so their record of it follows, and the next frame hides those
## not in view (else they stay shown where they last were).
func _lights_visibility_changed() -> void:
	var shown := _lights_layer.is_visible_in_tree()
	for item: Control in _marina_light_items.values():
		item.set_meta(&"shown", shown)
	_lights_layer.queue_redraw()

## Hides every marina's lights but those shown this frame.
func _hide_marina_lights(shown: Dictionary) -> void:
	for port_id: String in _marina_light_items:
		if not shown.has(port_id):
			_set_marina_lights_shown(_marina_light_items[port_id], false)

# --- Towns ---------------------------------------------------------------------------

## Every port has its town round its marina, just to look at: blocks of
## buildings on a street grid behind the quay (inland of the lighthouse's
## pad) and along the shore either side of the basin, as many as its size
## band allows (TOWN_ROWS deep, the marina's width and more across), each
## block only where the map's land is (so a town hugs its coast), a cross
## street every few blocks, some blocks two cells long (halls and terraces;
## grey warehouses along the waterfront). Seen from
## above: each building its walls' color with its roof inset, pitched roofs
## with a ridge (the sunny side lighter), flat roofs with a parapet and roof
## gear, East Asian roofs stacked in tiers; a few tall buildings with long
## shadows (more in the Americas and East Asia), parks between, and a landmark
## near the waterfront in the local manner: a church tower, a minaret and
## dome, a pagoda, a skyscraper, onion domes or a stupa. The look comes from
## the port's market region and country (TOWN_STYLES, _town_style()): the
## Mediterranean's pale walls and terracotta, the north's painted wood and
## dark roofs, East Asia's grey tiles, the Middle East's and Africa's flat
## sand-colored roofs, the Caribbean's pastels, North America's grid of grey
## towers... Laid out once per port by a seed of its id (_town()), drawn into
## its marina's item (_draw_town()); at night (and under storms) its windows
## light up in the style's warmth over a glow (_record_marina_lights()). Roads
## tie it together: a quay road behind the quay with a spine to the basin, a
## spur to the HQ and a cross road past the industry plots, an avenue inland
## through the middle of the town (a dashed line down it), a road along each
## wide street and cross street, walkways along the narrow streets, and a
## shore road along each side of the basin; street lamps line the quay road
## and the avenue at night.
const TOWN_CELL := 3.2
const TOWN_GAP := 0.6
const TOWN_STREET_EVERY := 4
const TOWN_ROWS := {6: 4, 8: 5, 10: 7, 14: 9}
const TOWN_SIDE_COLS := 2
const TOWN_HALF_RADII := 1.6
const TOWN_PARK_SHARE := 0.1
const TOWN_SHADOW := Color(0.0, 0.0, 0.0, 0.22)
const TOWN_PARK := Color(0.47, 0.62, 0.36)
const TOWN_ROAD := Color(0.4, 0.4, 0.39)
const TOWN_LANE := Color(0.85, 0.83, 0.78, 0.7)
const TOWN_WALK := Color(0.78, 0.75, 0.68)
const TOWN_LIGHTS_MIN_SCALE := 1.6
## The long-term moorings (see _lay_moorings()): a pontoon's width and a
## finger's (dock units), the water between two fingers beyond the ship's
## beam, how much longer than the port's longest ship a finger is, how far
## apart two pontoons must be (beyond their fingers), how often a street is
## sampled for water, and the fewest slips a pontoon is worth.
const MOOR_PONTOON_WIDTH := 0.8
const MOOR_FINGER_WIDTH := 0.35
const MOOR_SLIP_GAP := 0.9
const MOOR_FINGER_EXTRA := 0.6
const MOOR_ROW_CLEAR := 1.2
const MOOR_SAMPLE := 0.5
const MOOR_MIN_SLIPS := 2
const MOOR_ATTACH := 5.5
const MOOR_LANE_MARGIN := 2.5
const MOOR_NEAR := 14.0
const MOOR_WOOD := Color(0.8, 0.72, 0.58)
const MOOR_CONCRETE := Color(0.74, 0.74, 0.72)
const MOOR_EDGE := Color(0.3, 0.27, 0.22)
const MOOR_FLOAT := Color(0.42, 0.4, 0.36)
const MOOR_CLEAT := Color(0.2, 0.2, 0.2)
const TOWN_STYLES := {
	mediterranean = {walls = ["#e8dcc4", "#f0e6d2", "#e2cfae", "#d9c9a8", "#eadfca"], roofs = ["#c0603a", "#b8563a", "#c86a44", "#a84e32"], roof = "pitched", towers = 0.04, landmark = "church", lights = Color(1.0, 0.85, 0.55)},
	north_europe = {walls = ["#c9b79c", "#b0433b", "#d9c28f", "#e8e0d0", "#8a6a4a", "#5a7a9a"], roofs = ["#5a4a44", "#4a3f3a", "#6b4a3a", "#3e3a44"], roof = "pitched", towers = 0.08, landmark = "church", lights = Color(1.0, 0.88, 0.62)},
	east_asia = {walls = ["#d8d2c8", "#cfc8bc", "#e6e0d4", "#c8c4bc"], roofs = ["#5a6670", "#4c5660", "#6c3a34", "#3f4a52"], roof = "pagoda", towers = 0.18, landmark = "pagoda", lights = Color(1.0, 0.92, 0.65)},
	japan = {walls = ["#e8e4dc", "#d6d0c6", "#dcd8d0"], roofs = ["#4e5a66", "#3c4650", "#6a4a3a", "#56606a"], roof = "pagoda", towers = 0.16, landmark = "pagoda", lights = Color(1.0, 0.93, 0.7)},
	southeast_asia = {walls = ["#e6d9b8", "#d8c8a0", "#f0e8d0", "#c8d8c0"], roofs = ["#b8502e", "#9c4a2c", "#6a7a5a", "#8a5a3a"], roof = "pitched", towers = 0.12, landmark = "stupa", lights = Color(1.0, 0.86, 0.55)},
	south_asia = {walls = ["#e8c8a0", "#f0d8b0", "#d8b890", "#c8d8e8", "#e8e0c0"], roofs = ["#c8b090", "#b89a7a", "#d0b8a0", "#a89880"], roof = "flat", towers = 0.1, landmark = "dome", lights = Color(1.0, 0.84, 0.5)},
	middle_east = {walls = ["#e6d4b0", "#dcc8a2", "#efe0c0", "#d8c8a8"], roofs = ["#d8c6a0", "#cdb890", "#c4b088"], roof = "flat", towers = 0.14, landmark = "minaret", lights = Color(1.0, 0.86, 0.55)},
	africa = {walls = ["#d8b890", "#c8a070", "#e0c8a0", "#b89a78", "#e8d8b8"], roofs = ["#b89060", "#a07850", "#8a6a48", "#c0a070"], roof = "flat", towers = 0.05, landmark = "dome", lights = Color(1.0, 0.82, 0.5)},
	north_america = {walls = ["#b8b4ae", "#a8a4a0", "#c8c4bc", "#9a8a7a", "#8a9aa8"], roofs = ["#6a6a70", "#55555c", "#7a6a5a", "#5a6a74"], roof = "flat", towers = 0.3, landmark = "skyscraper", lights = Color(1.0, 0.9, 0.7)},
	caribbean = {walls = ["#f2c6a8", "#a8d8e8", "#f0e48c", "#c8e8b0", "#f4a8b8", "#f8f0d8"], roofs = ["#c86a4a", "#8a6a4a", "#6a8aa0", "#a8603a"], roof = "pitched", towers = 0.04, landmark = "church", lights = Color(1.0, 0.86, 0.6)},
	south_america = {walls = ["#e8c890", "#f0d8b8", "#d8a888", "#c8c8d8", "#e8e0c8"], roofs = ["#b85a3a", "#a04e32", "#c87048", "#8a4a3a"], roof = "pitched", towers = 0.12, landmark = "church", lights = Color(1.0, 0.86, 0.58)},
	oceania = {walls = ["#e8e4dc", "#d8d4cc", "#c8b89c", "#b8c8d0"], roofs = ["#8a8a90", "#a0a0a6", "#6a7a8a", "#b85a3a"], roof = "pitched", towers = 0.1, landmark = "skyscraper", lights = Color(1.0, 0.9, 0.66)},
	russia = {walls = ["#c8c0b0", "#b8b0a8", "#d8c8a8", "#9ab0c0", "#e0d8c8"], roofs = ["#4a5a6a", "#5a6a7a", "#6a4a3a", "#3a4a5a"], roof = "pitched", towers = 0.08, landmark = "onion", lights = Color(1.0, 0.88, 0.6)},
	arctic = {walls = ["#b0433b", "#d9c28f", "#e8e0d0", "#4a7a9a", "#8a9a60"], roofs = ["#3e3a44", "#5a4a44", "#4a5a6a"], roof = "pitched", towers = 0.0, landmark = "none", lights = Color(1.0, 0.9, 0.66)},
	antarctica = {walls = ["#e0603a", "#4a8ab0", "#e8e8e8"], roofs = ["#c0c8d0", "#b0b8c0"], roof = "flat", towers = 0.0, landmark = "none", lights = Color(1.0, 0.95, 0.8)},
}
const TOWN_REGION_STYLES := {east_asia = "east_asia", southeast_asia = "southeast_asia", south_asia = "south_asia", middle_east = "middle_east",
	east_africa = "africa", west_africa = "africa", mediterranean = "mediterranean", north_europe = "north_europe", na_east = "north_america",
	na_west = "north_america", great_lakes = "north_america", gulf_caribbean = "caribbean", south_america = "south_america", oceania = "oceania",
	russia_far_east = "russia", arctic = "arctic", antarctica = "antarctica"}
const TOWN_COUNTRY_STYLES := {"Japan": "japan", "United States": "north_america", "Canada": "north_america", "Egypt": "middle_east", "Libya": "middle_east",
	"Tunisia": "middle_east", "Algeria": "middle_east", "Morocco": "middle_east", "Israel": "middle_east", "Lebanon": "middle_east", "Syria": "middle_east",
	"Turkey": "middle_east", "Russia": "russia", "Norway": "north_europe", "Iceland": "north_europe", "Greenland": "arctic"}
## Each port's town as laid out (see _town()): port id -> {key, buildings
## ([rect (dock units), wall, roof, height (1 low, 2+ tall), kind, salt]),
## parks ([middle, radius]), lights (PackedVector2Array), light (Color),
## style (name), reach (dock units inland)}.
var _towns := {}

## A port's architecture (a TOWN_STYLES key): by its country where that
## tells, else its market region.
static func _town_style(port_id: String) -> String:
	var country := str(GameData.get_port(port_id).get("country", ""))
	if TOWN_COUNTRY_STYLES.has(country):
		return TOWN_COUNTRY_STYLES[country]
	return str(TOWN_REGION_STYLES.get(str(GameData.port_region(port_id).get("id", "")), "mediterranean"))

## How far inland (dock units, past the quay) a port's town can reach.
static func _town_rows(layout: Dictionary) -> int:
	return int(TOWN_ROWS.get((layout.berths as Array).size(), 7))

## A port's town, laid out once (and again if its marina changes size): see
## the Towns note above. Needs the map's land (empty till it's sorted).
func _town(port_id: String, layout: Dictionary) -> Dictionary:
	var claims := _town_claims(port_id)
	var key := [port_id, layout.radius, layout.depth]
	for other: String in claims:
		var theirs := _port_layout(other)
		key.append([theirs.radius, theirs.depth])
	if _towns.has(port_id) and _towns[port_id].key == key:
		return _towns[port_id]
	if _land_cells.is_empty():
		return {}
	var t_t := Time.get_ticks_usec()
	# Bigger neighbours' towns first: this one keeps off their ground (see _town_claims()).
	for other: String in claims:
		if _town(other, _port_layout(other)).is_empty():
			return {}
	var style_name := _town_style(port_id)
	var style: Dictionary = TOWN_STYLES[style_name]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(port_id)
	var radius := float(layout.radius)
	var half := float(layout.inner)
	var depth := float(layout.depth)
	var inland := _quay_inland(layout)
	var rows := _town_rows(layout)
	var cells := []  # [middle, size (Vector2), waterfront (bool)]
	# Behind the quay: rows of blocks the town's width across, a street between
	# each and a wider one every TOWN_STREET_EVERY.
	var wide := radius * TOWN_HALF_RADII
	var x := inland - LIGHTHOUSE_ROOM - 1.5 - TOWN_CELL / 2.0
	for r in rows:
		var columns := maxi(floori(wide * 2.0 / TOWN_CELL), 1)
		var c := 0
		while c < columns:
			if (c + 1) % (TOWN_STREET_EVERY + 1) == 0:
				c += 1  # A cross street.
				continue
			var y := -wide + TOWN_CELL * (c + 0.5)
			# Now and then two cells make one long block (a hall, a terrace, a warehouse on the waterfront).
			var long := c + 1 < columns and (c + 2) % (TOWN_STREET_EVERY + 1) != 0 and rng.randf() < (0.5 if r == 0 else 0.2)
			if long:
				cells.append([Vector2(x, y + TOWN_CELL / 2.0), Vector2(TOWN_CELL, TOWN_CELL * 2.0), r == 0])
				c += 2
			else:
				cells.append([Vector2(x, y), Vector2.ONE * TOWN_CELL, r == 0])
				c += 1
		x -= TOWN_CELL + (TOWN_GAP if (r + 1) % TOWN_STREET_EVERY != 0 else TOWN_GAP * 2.0)
	# Along the shore either side of the basin, back from the walls.
	for side: float in [-1.0, 1.0]:
		for c in TOWN_SIDE_COLS:
			var y := side * (half + 1.5 + TOWN_CELL * (c + 0.5) + (TOWN_GAP if c > 0 else 0.0))
			var cx := -depth + TOWN_CELL / 2.0
			while cx < -1.0:
				cells.append([Vector2(cx, y), Vector2.ONE * TOWN_CELL, c == 0])
				cx += TOWN_CELL + TOWN_GAP
	var buildings := []
	var parks := []
	var lights := PackedVector2Array()
	var reach := 0.0
	var roads := []  # [rect (dock units), kind: "road", "avenue" or "walk"]
	var landmark_at := -1
	var waterfront := []
	for i in cells.size():
		var middle: Vector2 = cells[i][0]
		if not _on_land(_dock_lon_lat(port_id, middle)) or _on_other_marina(port_id, middle) or _cell_on_other_town(port_id, middle, cells[i][1], claims):
			continue  # In the water (the town keeps to its coast), on a neighbouring port's quay, or on a bigger neighbour's town.
		reach = maxf(reach, -middle.x + TOWN_CELL / 2.0)
		if rng.randf() < TOWN_PARK_SHARE:
			parks.append([middle, TOWN_CELL * rng.randf_range(0.25, 0.4)])
			continue
		if cells[i][2]:
			waterfront.append(buildings.size())
		var room: Vector2 = (cells[i][1] as Vector2) - Vector2.ONE * TOWN_GAP
		var warehouse: bool = cells[i][2] and room.y > room.x * 1.5 and rng.randf() < 0.7
		var size := Vector2(room.x * rng.randf_range(0.62, 1.0), room.y * rng.randf_range(0.62, 1.0)) if not warehouse else room * Vector2(0.9, 0.96)
		var rect := Rect2(middle - size / 2.0, size)
		var tall := not warehouse and room.y <= room.x * 1.5 and rng.randf() < float(style.towers)
		var height := rng.randf_range(2.0, 3.2) if tall else (0.7 if warehouse else rng.randf_range(0.8, 1.3))
		var wall := Color.from_string(str((style.walls as Array)[rng.randi() % (style.walls as Array).size()]), Color.GRAY)
		var roof := Color.from_string(str((style.roofs as Array)[rng.randi() % (style.roofs as Array).size()]), Color.DIM_GRAY)
		if tall:
			roof = roof.darkened(0.15)
		if warehouse:
			wall = Color("#9a9690")
			roof = Color("#8a8c90").lerp(roof, 0.25)
		buildings.append([rect, wall, roof, height, "tall" if tall else ("warehouse" if warehouse else str(style.roof)), rng.randf()])
		var windows := 3 if tall else rng.randi_range(1, 2)
		for w in windows:
			lights.append(Vector2(rng.randf_range(rect.position.x + 0.3, rect.end.x - 0.3), rng.randf_range(rect.position.y + 0.3, rect.end.y - 0.3)))
	# The landmark: on the waterfront, near the middle, in place of a block.
	if str(style.landmark) != "none" and not waterfront.is_empty():
		var best := -1
		var nearest := INF
		for index: int in waterfront:
			var y: float = absf((buildings[index][0] as Rect2).get_center().y - rng.randf_range(-radius * 0.5, radius * 0.5))
			if y < nearest:
				nearest = y
				best = index
		if best >= 0:
			landmark_at = best
			var block: Array = buildings[best]
			var rect: Rect2 = block[0]
			var size := Vector2.ONE * (TOWN_CELL - TOWN_GAP)
			buildings[best] = [Rect2(rect.get_center() - size / 2.0, size), block[1], block[2], 2.6 if str(style.landmark) == "skyscraper" else 1.8, "landmark:" + str(style.landmark), block[5]]
			lights.append(rect.get_center())
	# The roads: the quay road along the back of the quay (behind the lighthouse's
	# pad), with a spine across the quay strip to the basin, a spur to the HQ and
	# a cross road past the industry plots; the avenue from the quay road inland
	# through the middle of the town to its back; a road along each wide street
	# and each cross street, walkways along the narrow ones; and a shore road
	# along each side of the basin's walls, back to the quay road.
	var quay_road_x := inland - LIGHTHOUSE_ROOM - 1.3
	var back := -reach - 0.5
	var near := -(depth + QUAY_WIDTH)
	var far := inland
	roads.append([Rect2(quay_road_x, -wide, 1.0, wide * 2.0), "road"])
	roads.append([Rect2(quay_road_x, -0.4, near - quay_road_x, 0.8), "road"])
	roads.append([Rect2(quay_road_x, -radius * 0.5 - 0.35, far + HQ_MARGIN - quay_road_x, 0.7), "road"])
	roads.append([Rect2(far + HQ_MARGIN * 0.6, 0.4, 0.7, radius - HQ_MARGIN - 0.4), "road"])
	roads.append([Rect2(back, -0.6, quay_road_x - back, 1.2), "avenue"])
	var sx := inland - LIGHTHOUSE_ROOM - 1.5 - TOWN_CELL / 2.0
	for r in rows:
		var street_gap := TOWN_GAP if (r + 1) % TOWN_STREET_EVERY != 0 else TOWN_GAP * 2.0
		var street_x := sx - TOWN_CELL / 2.0 - street_gap
		if r < rows - 1:
			if street_gap > TOWN_GAP:
				roads.append([Rect2(street_x + 0.1, -wide, street_gap - 0.2, wide * 2.0), "road"])
			else:
				roads.append([Rect2(street_x + street_gap / 2.0 - 0.15, -wide, 0.3, wide * 2.0), "walk"])
		sx -= TOWN_CELL + street_gap
	var columns := maxi(floori(wide * 2.0 / TOWN_CELL), 1)
	for c in columns:
		if (c + 1) % (TOWN_STREET_EVERY + 1) == 0:
			var y := -wide + TOWN_CELL * (c + 0.5)
			roads.append([Rect2(back, y - 0.45, quay_road_x - back, 0.9), "road"])
	for side: float in [-1.0, 1.0]:
		var y := side * (half + 0.75)
		roads.append([Rect2(-depth, y - 0.35, depth - 0.5, 0.7), "road"])
		roads.append([Rect2(quay_road_x, minf(y, 0.0) - 0.35, -depth - quay_road_x, absf(y) + 0.7), "walk"])
	# Street lamps along the quay road and the avenue.
	var lamp_y := -wide + 1.0
	while lamp_y < wide:
		lights.append(Vector2(quay_road_x + 1.15, lamp_y))
		lamp_y += 3.0
	var lamp_x := quay_road_x - 1.5
	while lamp_x > back:
		lights.append(Vector2(lamp_x, 0.8))
		lamp_x -= 3.0
	# The streets that sit on the water (where the coast runs through the town's
	# grid) become the port's long-term moorings: pontoons with finger slips,
	# a lamp at each end (see _lay_moorings()); the roads keep to the land.
	var moored := _lay_moorings(port_id, layout, roads)
	roads = moored.roads
	var t_j := Time.get_ticks_usec()
	var joined := _join_neighbour_towns(port_id, roads, claims)
	_prof("town.join", t_j)
	roads = joined.roads
	for pontoon: Array in moored.pontoons:
		lights.append(pontoon[0])
		lights.append(pontoon[1])
	var segments := PackedVector2Array()
	for light: Vector2 in lights:
		segments.append(light - Vector2(0.11, 0.0))
		segments.append(light + Vector2(0.11, 0.0))
	var town := {key = key, buildings = buildings, parks = parks, lights = lights, light = style.lights, style = style_name, reach = reach, landmark = landmark_at, roads = roads,
		pontoons = moored.pontoons, moorings = moored.moorings, links = joined.links}
	town.segments = segments
	town.ground = _town_ground(town, layout)
	_towns[port_id] = town
	_prof("town.build", t_t)
	_clear_decor_off_town(port_id, town)
	return town

## True where a marina draws its own ground: the quay (the land behind the
## basin, HQ and industry and all), the basin, and the harbour inside the
## jetty (water, but the ships' way in and out).
static func _marina_ground(layout: Dictionary, p: Vector2) -> bool:
	var radius := float(layout.radius)
	if p.x >= _quay_inland(layout) - 0.5 and p.x <= 0.5 and absf(p.y) <= radius + 0.5:
		return true
	return p.x > -0.5 and p.length() <= radius + JETTY_WIDTH + 1.0

## The port's long-term moorings, from its town's streets that sit on the water
## (the coast runs through the town's grid at a port on a headland, a spit or
## an island): each such run of street, if it's long enough, becomes a pontoon
## (a floating walkway along the street's line) with finger piers out from
## both sides, a slip between each finger and the next for a ship to come
## straight in, bow to the pontoon, as long as the port's longest ship, every
## finger and slip only where the water really is and clear of the marina's
## own ground; pontoons keep clear of each other's fingers (the quay road and
## the cross roads first, then the avenue and the streets). The roads are cut
## down to their runs on land. Returns {roads, pontoons: [[a, b, fingers:
## [[root, tip]...]]...], moorings: [[middle, facing, length]...]} in dock units.
func _lay_moorings(port_id: String, layout: Dictionary, roads: Array) -> Dictionary:
	# Every slip takes the longest and widest ship of any kind (the Mammoth):
	# the moorings are every ship's long-term parking, the recovery boats' too.
	var length := _longest_ship()
	var width := _widest_any_ship()
	var finger := length + MOOR_FINGER_EXTRA
	var pitch := width + MOOR_SLIP_GAP + MOOR_FINGER_WIDTH
	var kept_roads := []
	var lines := []  # [a, b, priority]
	var water := func(p: Vector2) -> bool:
		return not _marina_ground(layout, p) and not _on_land(_dock_lon_lat(port_id, p))
	for road: Array in roads:
		var rect: Rect2 = road[0]
		var kind: String = road[1]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		var along_x := rect.size.x >= rect.size.y
		var start := rect.position.x if along_x else rect.position.y
		var end := rect.end.x if along_x else rect.end.y
		var mid := rect.get_center().y if along_x else rect.get_center().x
		var runs := []  # [from, to, on water]
		var s := start
		var state := -1
		var run_from := start
		while s < end:
			var wet: bool = water.call(Vector2(s, mid) if along_x else Vector2(mid, s))
			var w := 1 if wet else 0
			if w != state:
				if state >= 0:
					runs.append([run_from, s, state == 1])
				state = w
				run_from = s
			s += MOOR_SAMPLE
		runs.append([run_from, end, state == 1])
		for run: Array in runs:
			var from: float = run[0]
			var to: float = run[1]
			if not run[2]:
				if to - from > 0.2:
					kept_roads.append([Rect2(from, rect.position.y, to - from, rect.size.y) if along_x else Rect2(rect.position.x, from, rect.size.x, to - from), kind])
			elif to - from >= pitch * MOOR_MIN_SLIPS + MOOR_FINGER_WIDTH:
				var priority := 0 if kind == "road" and not along_x else (1 if kind == "road" else (2 if kind == "avenue" else 3))
				lines.append([Vector2(from, mid) if along_x else Vector2(mid, from), Vector2(to, mid) if along_x else Vector2(mid, to), priority])
	# And the side streets' lines along either side of the harbour, just outside
	# the quay land (their fingers reaching back to it): where the water runs
	# beside the marina (a port on a spit or a river mouth: Shanghai, say), a
	# mooring field flanks it.
	var radius := float(layout.radius)
	var depth := float(layout.depth)
	var rows := 1 if (layout.berths as Array).size() <= 8 else (2 if (layout.berths as Array).size() <= 10 else 3)
	for row in rows:
		for side: float in [-1.0, 1.0]:
			# The first row's fingers reach back to the quay land, but never into the
			# way ships round the jetty's end (JETTY_ROUND out: see _round_jetty()).
			var y := side * (maxf(radius + 1.0, radius * JETTY_ROUND + MOOR_LANE_MARGIN) + finger + MOOR_PONTOON_WIDTH / 2.0 + row * (2.0 * finger + MOOR_PONTOON_WIDTH + MOOR_ROW_CLEAR))
			var s := -depth - 1.0
			var run_from := s
			var state := -1
			while s < -0.5:
				var w := 1 if water.call(Vector2(s, y)) else 0
				if w != state:
					if state == 1 and s - run_from >= pitch * MOOR_MIN_SLIPS + MOOR_FINGER_WIDTH:
						lines.append([Vector2(run_from, y), Vector2(s, y), 4, side, row])
					state = w
					run_from = s
				s += MOOR_SAMPLE
			if state == 1 and s - run_from >= pitch * MOOR_MIN_SLIPS + MOOR_FINGER_WIDTH:
				lines.append([Vector2(run_from, y), Vector2(s, y), 4, side, row])
	lines.sort_custom(func(a: Array, b: Array) -> bool:
		if int(a[2]) != int(b[2]):
			return int(a[2]) < int(b[2])
		var row_a := int(a[4]) if a.size() > 4 else 0
		var row_b := int(b[4]) if b.size() > 4 else 0
		if row_a != row_b:
			return row_a < row_b
		return (a[0] as Vector2).distance_to(a[1]) > (b[0] as Vector2).distance_to(b[1]))
	var side_rows := {}  # Side (+1/-1) -> the rows built so far (a row needs the one nearer the quay).
	var pontoons := []
	var moorings := []
	var footprints: Array[Rect2] = []
	var reach := MOOR_PONTOON_WIDTH / 2.0 + finger + MOOR_ROW_CLEAR
	for line: Array in lines:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var footprint := Rect2(a, Vector2.ZERO).expand(b).grow(reach)
		if int(line[2]) <= 3 and Geometry2D.get_closest_point_to_segment(Vector2.ZERO, a, b).length() > absf(_quay_inland(layout)) + MOOR_NEAR:
			continue  # A street out by some other shore, far from the port.
		if line.size() > 4 and int(line[4]) > 0 and int(side_rows.get(float(line[3]), 0)) < int(line[4]):
			continue  # A side row only beyond a built row nearer the quay (no field floating off by itself).
		var crowded := false
		for other: Rect2 in footprints:
			if other.intersects(footprint):
				crowded = true
				break
		if crowded:
			continue
		var d := (b - a).normalized()
		var normal := Vector2(-d.y, d.x)
		var span := a.distance_to(b)
		# Attached: land or the quay within MOOR_ATTACH to one side somewhere
		# along it, or at an end (no pontoon floats off by itself out at sea).
		var attached: bool = not water.call(a - d * 1.0) or not water.call(b + d * 1.0)
		var s_check := 0.0
		while not attached and s_check <= span:
			var at := a + d * s_check
			if not water.call(at + normal * MOOR_ATTACH) or not water.call(at - normal * MOOR_ATTACH):
				attached = true
			s_check += MOOR_SAMPLE * 2.0
		if not attached:
			continue
		var fingers := []
		var slips := []
		for sign: float in [1.0, -1.0]:
			var side := normal * sign
			var roots := []  # [s, root] of each finger that stands in water.
			var s := MOOR_FINGER_WIDTH / 2.0
			while s <= span - MOOR_FINGER_WIDTH / 2.0:
				var root := a + d * s + side * (MOOR_PONTOON_WIDTH / 2.0)
				var tip := root + side * finger
				if water.call(tip) and water.call(root + side * finger * 0.5):
					roots.append([s, root])
				else:
					roots.append([s, Vector2.INF])
				s += pitch
			for i in range(1, roots.size()):
				if (roots[i - 1][1] as Vector2) == Vector2.INF or (roots[i][1] as Vector2) == Vector2.INF:
					continue
				var middle := a + d * (float(roots[i - 1][0]) + pitch / 2.0) + side * (MOOR_PONTOON_WIDTH / 2.0 + 0.3 + length / 2.0)
				if not water.call(middle) or not water.call(middle + side * length / 2.0):
					continue
				slips.append([middle, (-side).angle(), length, roots[i - 1][1], roots[i][1]])
		if slips.size() < MOOR_MIN_SLIPS:
			continue
		# Only the fingers that bound a slip are built.
		var used := {}
		for slip: Array in slips:
			for root: Vector2 in [slip[3], slip[4]]:
				if not used.has(root):
					used[root] = true
					var side := (root - a).dot(normal)
					fingers.append([root, root + normal * signf(side) * finger])
			moorings.append([slip[0], slip[1], slip[2]])
		pontoons.append([a, b, fingers])
		footprints.append(footprint)
		if line.size() > 4:
			side_rows[float(line[3])] = maxi(int(side_rows.get(float(line[3]), 0)), int(line[4]) + 1)
	return {roads = kept_roads, pontoons = pontoons, moorings = moorings}


## A point of a port's marina (dock units) as another port's dock units.
func _local_of(other_id: String, lon_lat: Vector2) -> Vector2:
	var info := GameData.get_port(other_id)
	var lat := float(info.get("lat", 0.0))
	var ground := Vector2(wrapf(lon_lat.x - float(info.get("lon", 0.0)), -180.0, 180.0) * cos(deg_to_rad(lat)), -(lon_lat.y - lat)) * SHIP_WORLD_ZOOM
	var local := ground.rotated(-_port_sea_angle(other_id))
	local.y *= float(_dock_flips.get(other_id, 1.0))
	return local

## True if a point of a port's marina (dock units) lies on a neighbouring
## port's own ground (its quay, basin or harbour: see _marina_ground()), so
## Rijeka's town never stands on Koper's quay.
func _on_other_marina(port_id: String, local: Vector2) -> bool:
	var lon_lat := _dock_lon_lat(port_id, local)
	if not _marina_neighbours.has(port_id):
		var here := GameData.get_port(port_id)
		var at := Vector2(float(here.get("lon", 0.0)), float(here.get("lat", 0.0)))
		var near := PackedStringArray()
		for other: Dictionary in GameData.ports:
			if other.id != port_id and Geo.distance_nm(at, Vector2(float(other.get("lon", 0.0)), float(other.get("lat", 0.0)))) < 2.0 * MARINA_MAX_REACH * 60.0 / SHIP_WORLD_ZOOM:
				near.append(str(other.id))
		_marina_neighbours[port_id] = near
	for other: String in _marina_neighbours[port_id]:
		if _marina_ground(_port_layout(other), _local_of(other, lon_lat)):
			return true
	return false

## Each port's neighbours near enough for their marinas to meet (see _on_other_marina()).
var _marina_neighbours := {}

## Neighbouring towns share the land between them: the bigger port's (by
## rank) is laid out first and the smaller one keeps off its ground (its
## blocks, parks, roads, quay and basin: _town_ground()), its roads stopping
## at the edge and joined on to the bigger town's nearest road by a link
## road at whatever angle the two grids meet (_join_neighbour_towns()), so
## two towns grown together read as one, with no block on another. And no
## tree or mountain stands on a town (_clear_decor_off_town()).
const TOWN_GROUND_CELL := 1.6
## How far (dock units) a road cut at a neighbour's town may be joined to its roads, and the link road's width.
const TOWN_LINK_REACH := 9.0
const TOWN_LINK_WIDTH := 0.9

## The neighbours (see _on_other_marina()) whose towns this port's keeps
## off: the bigger ports (lower rank; the same rank, the lower id).
func _town_claims(port_id: String) -> PackedStringArray:
	if _town_claim_lists.has(port_id):
		return _town_claim_lists[port_id]
	_on_other_marina(port_id, Vector2.ZERO)  # (Fills _marina_neighbours for it.)
	var mine := GameData.get_port(port_id)
	var out := PackedStringArray()
	for other: String in _marina_neighbours[port_id]:
		var theirs := GameData.get_port(other)
		var rank_a := int(theirs.get("rank", 9999))
		var rank_b := int(mine.get("rank", 9999))
		if rank_a < rank_b or (rank_a == rank_b and other < port_id):
			out.append(other)
	_town_claim_lists[port_id] = out
	return out
var _town_claim_lists := {}

## A town's ground as TOWN_GROUND_CELL cells of its own dock units: its
## blocks, parks and roads, its link roads, and its marina's quay and basin.
static func _town_ground(town: Dictionary, layout: Dictionary) -> Dictionary:
	var ground := {}
	for block: Array in town.buildings:
		_mark_ground(ground, block[0])
	for park: Array in town.parks:
		var r := float(park[1])
		_mark_ground(ground, Rect2(park[0] - Vector2.ONE * r, Vector2.ONE * r * 2.0))
	for road: Array in town.roads:
		_mark_ground(ground, road[0])
	for link: Array in town.get("links", []):
		var a: Vector2 = link[0]
		var b: Vector2 = link[1]
		var steps := maxi(ceili(a.distance_to(b) / (TOWN_GROUND_CELL * 0.5)), 1)
		for k in steps + 1:
			var p := a.lerp(b, float(k) / steps)
			ground[Vector2i(floori(p.x / TOWN_GROUND_CELL), floori(p.y / TOWN_GROUND_CELL))] = true
	var radius := float(layout.radius)
	_mark_ground(ground, Rect2(_quay_inland(layout), -radius, -_quay_inland(layout) + radius, radius * 2.0))
	return ground

static func _mark_ground(ground: Dictionary, rect: Rect2) -> void:
	for x in range(floori(rect.position.x / TOWN_GROUND_CELL), floori(rect.end.x / TOWN_GROUND_CELL) + 1):
		for y in range(floori(rect.position.y / TOWN_GROUND_CELL), floori(rect.end.y / TOWN_GROUND_CELL) + 1):
			ground[Vector2i(x, y)] = true

## The bigger neighbour (of `claims`) whose town's ground a point of this
## port's (dock units) is on, or "".
func _on_other_town(port_id: String, local: Vector2, claims: PackedStringArray) -> String:
	if claims.is_empty():
		return ""
	var lon_lat := _dock_lon_lat(port_id, local)
	for other: String in claims:
		var town: Dictionary = _towns.get(other, {})
		if town.is_empty():
			continue
		var q := _local_of(other, lon_lat)
		if (town.ground as Dictionary).has(Vector2i(floori(q.x / TOWN_GROUND_CELL), floori(q.y / TOWN_GROUND_CELL))):
			return other
	return ""

## True if a block's cell (middle, size) would touch a bigger neighbour's town.
func _cell_on_other_town(port_id: String, middle: Vector2, cell_size: Vector2, claims: PackedStringArray) -> bool:
	if claims.is_empty():
		return false
	var half := cell_size / 2.0
	for corner: Vector2 in [Vector2.ZERO, Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		if not _on_other_town(port_id, middle + corner, claims).is_empty():
			return true
	return false

## A town's roads cut where they run onto a bigger neighbour's town, and each
## cut end joined to that town's nearest road (within TOWN_LINK_REACH, over
## land) by a link road: {roads, links: [[from, to], ...] (dock units)}.
func _join_neighbour_towns(port_id: String, roads: Array, claims: PackedStringArray) -> Dictionary:
	if claims.is_empty():
		return {roads = roads, links = []}
	var kept := []
	var ends := []  # [the cut end (dock units), the neighbour]
	for road: Array in roads:
		var rect: Rect2 = road[0]
		var along_x := rect.size.x >= rect.size.y
		var start := rect.position.x if along_x else rect.position.y
		var end := rect.end.x if along_x else rect.end.y
		var mid := rect.get_center().y if along_x else rect.get_center().x
		var run_from := start
		var inside := ""
		var s := start
		while s <= end:
			var here := _on_other_town(port_id, Vector2(s, mid) if along_x else Vector2(mid, s), claims)
			if here != inside:
				if inside.is_empty():
					if s - run_from > 0.2:  # A run of ours ends at their edge: keep it, and join it on.
						kept.append([Rect2(run_from, rect.position.y, s - run_from, rect.size.y) if along_x else Rect2(rect.position.x, run_from, rect.size.x, s - run_from), road[1]])
					if s > start:
						ends.append([Vector2(s, mid) if along_x else Vector2(mid, s), here])
				else:
					run_from = s  # Back on our own ground: a new run starts here, joined on too.
					ends.append([Vector2(s, mid) if along_x else Vector2(mid, s), inside])
				inside = here
			s += MOOR_SAMPLE
		if inside.is_empty() and end - run_from > 0.2:
			kept.append([Rect2(run_from, rect.position.y, end - run_from, rect.size.y) if along_x else Rect2(rect.position.x, run_from, rect.size.x, end - run_from), road[1]])
	var links := []
	for cut: Array in ends:
		var from: Vector2 = cut[0]
		var other: String = cut[1]
		var to := _nearest_town_road(other, _dock_lon_lat(port_id, from))
		if to == Vector2.INF:
			continue
		var target := _local_of(port_id, _dock_lon_lat(other, to))
		if from.distance_to(target) > TOWN_LINK_REACH or not _on_land(_dock_lon_lat(port_id, from.lerp(target, 0.5))):
			continue
		links.append([from, target])
	return {roads = kept, links = links}

## The nearest point (that port's dock units) on a town's roads to a place
## (lon, lat), or Vector2.INF if it has none.
func _nearest_town_road(port_id: String, lon_lat: Vector2) -> Vector2:
	var town: Dictionary = _towns.get(port_id, {})
	var q := _local_of(port_id, lon_lat)
	var best := Vector2.INF
	for road: Array in town.get("roads", []):
		var rect: Rect2 = road[0]
		var along_x := rect.size.x >= rect.size.y
		var p := Vector2(clampf(q.x, rect.position.x, rect.end.x), rect.get_center().y) if along_x else Vector2(rect.get_center().x, clampf(q.y, rect.position.y, rect.end.y))
		if best == Vector2.INF or p.distance_squared_to(q) < best.distance_squared_to(q):
			best = p
	return best

## Hides the trees and mountains (any land drawing but the animals) whose
## picture would reach onto a town's ground (see _town_ground()): a drawing
## stands on its spot reaching up (north) its size, about half its size across.
func _clear_decor_off_town(port_id: String, town: Dictionary) -> void:
	var t_c := Time.get_ticks_usec()
	_load_decor()
	var data := GameData.world_map
	var port := GameData.get_port(port_id)
	var at := Vector2(float(port.get("lon", 0.0)), float(port.get("lat", 0.0)))
	var reach_deg := (MARINA_MAX_REACH + float(DECOR_KM.mountain_c) / KM_PER_DEGREE * SHIP_WORLD_ZOOM) / SHIP_WORLD_ZOOM
	var ground: Dictionary = town.ground
	var hidden := PackedInt32Array()
	var wide := reach_deg / maxf(cos(deg_to_rad(at.y)), 0.1)
	var py := Geo.project(at).y  # (The drawings are sorted by their projected spots.)
	for column in range(floori((at.x - wide + 180.0) / DECOR_BUCKET), floori((at.x + wide + 180.0) / DECOR_BUCKET) + 1):
		for row in range(floori((py - wide) / DECOR_BUCKET), floori((py + wide) / DECOR_BUCKET) + 1):
			for i: int in _decor_buckets.get(Vector2i(posmod(column, roundi(360.0 / DECOR_BUCKET)), row), PackedInt32Array()):
				if _decor_room[i] <= 0.0:
					continue
				var kind_name: String = data.decor_kind_names[data.decor_kinds[i]]
				var km := float(DECOR_KM.get(kind_name, 0.0))
				if km <= 0.0 or kind_name == "pizza" or kind_name == "waves":
					continue  # An animal, the pizza or the polar waves: they keep their spots.
				var r := km / 2.0 / KM_PER_DEGREE * SHIP_WORLD_ZOOM  # (Dock units.)
				var middle := _local_of(port_id, Geo.unproject(data.decor_positions[i]) + Vector2(0.0, km * 0.42 / KM_PER_DEGREE))
				if _circle_on_ground(ground, middle, r):
					hidden.append(i)
	_prof("town.decor", t_c)
	if hidden.is_empty():
		return
	for i in hidden:
		_decor_room[i] = 0.0
	if _decor_native != null:
		if _decor_native.has_method(&"hide"):
			_decor_native.hide(hidden)
		else:
			_decor_native = null  # (An older library: set up again, with the room as it is now.)

static func _circle_on_ground(ground: Dictionary, middle: Vector2, r: float) -> bool:
	for x in range(floori((middle.x - r) / TOWN_GROUND_CELL), floori((middle.x + r) / TOWN_GROUND_CELL) + 1):
		for y in range(floori((middle.y - r) / TOWN_GROUND_CELL), floori((middle.y + r) / TOWN_GROUND_CELL) + 1):
			if ground.has(Vector2i(x, y)):
				var nearest := Vector2(clampf(middle.x, x * TOWN_GROUND_CELL, (x + 1) * TOWN_GROUND_CELL), clampf(middle.y, y * TOWN_GROUND_CELL, (y + 1) * TOWN_GROUND_CELL))
				if nearest.distance_to(middle) <= r:
					return true
	return false
## Many small flat shapes drawn as one triangle array (one draw call, and one
## call into the rendering server, instead of hundreds): a town's blocks, a
## pontoon's fingers, the ports' lights at night. Shapes are convex (fans).
class PolyBatch:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	func clear() -> void:
		points.clear()
		colors.clear()
		uvs.clear()
		indices.clear()

	## A convex polygon in one colour.
	func poly(p: PackedVector2Array, color: Color) -> void:
		var base := points.size()
		var n := p.size()
		points.append_array(p)
		var fill := PackedColorArray()
		fill.resize(n)
		fill.fill(color)
		colors.append_array(fill)
		uvs.resize(base + n)
		if n == 4:
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
			return
		for i in range(1, n - 1):
			indices.append(base)
			indices.append(base + i)
			indices.append(base + i + 1)

	## Everything so far as a mesh (2D, coloured triangles), for drawing again and again.
	func to_mesh() -> ArrayMesh:
		var mesh := ArrayMesh.new()
		if indices.is_empty():
			return mesh
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = points
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_2D_VERTICES)
		return mesh

	## A line as a thin quad.
	func line(a: Vector2, b: Vector2, color: Color, width: float) -> void:
		var n := (b - a).normalized().orthogonal() * width / 2.0
		poly(PackedVector2Array([a + n, b + n, b - n, a - n]), color)

	## A filled circle as a fan.
	func disc(center: Vector2, r: float, color: Color, steps := 8) -> void:
		var p := PackedVector2Array()
		for i in steps:
			p.append(center + Vector2.from_angle(TAU * i / steps) * r)
		poly(p, color)

	## A textured quad (the whole texture over the rect).
	func textured(rect: Rect2, color: Color) -> void:
		var base := points.size()
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			points.append(corner)
			colors.append(color)
		uvs.append_array(PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## A quad showing the part of the texture `region` (0 to 1 each way) covers.
	func textured_region(rect: Rect2, color: Color, region: Rect2) -> void:
		var base := points.size()
		for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
			points.append(corner)
			colors.append(color)
		uvs.append_array(PackedVector2Array([region.position, Vector2(region.end.x, region.position.y), region.end, Vector2(region.position.x, region.end.y)]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## Draws everything so far on a canvas item (as one command) and clears.
	func flush(canvas: CanvasItem, texture: Texture2D = null) -> void:
		if indices.is_empty():
			return
		RenderingServer.canvas_item_add_triangle_array(canvas.get_canvas_item(), indices, points, colors, uvs, PackedInt32Array(), PackedFloat32Array(), texture.get_rid() if texture != null else RID())
		clear()

var _batch := PolyBatch.new()

## How long (ms) each part of the map's frame work took since last cleared (for probes: MapView.profile).
static var profile := {}
## Set to time the map and game parts into `profile` (ms summed per part).
static var profiling := false
static func _prof(name: String, start_usec: int) -> void:
	if not profiling:
		return
	profile[name] = float(profile.get(name, 0.0)) + (Time.get_ticks_usec() - start_usec) / 1000.0
static func _count(name: String) -> void:
	if profiling:
		profile[name] = float(profile.get(name, 0.0)) + 1.0
## The World map's sound (see Ambience).
var ambience: Ambience = null

## The ways to the moorings at the ports the fleet is making for, worked out
## ahead (see _mooring_way(): a search over the port's water each, a few ms
## for a port's first), one or two a frame (MOORING_WARM_MS), so a ship
## coming in finds its mooring's way known rather than working it out in
## the frame it berths. A port is looked at once per lot of moorings, and
## only MOORING_WARM_SHIPS ships' ports a frame (round the fleet in turn).
const MOORING_WARM_MS := 1.0
const MOORING_WARM_SHIPS := 6
var _moorings_warm := {}  # Port id -> [how many moorings, the marina's radius] it was warmed for.
var _warm_moorings_at := 0
func _warm_moorings() -> void:
	if _land_cells.is_empty():
		return
	var start := Time.get_ticks_usec()
	var ships: Array = GameState.ships
	if ships.is_empty():
		return
	for n in mini(MOORING_WARM_SHIPS, ships.size()):
		var ship: Ship = ships[(_warm_moorings_at + n) % ships.size()]
		var port: String = ship.docked_at if ship.is_docked() else ship.to_port
		if port.is_empty() or ship.is_tug() or Fisheries.is_ground(port):
			continue
		var layout := _port_layout(port)
		var warm: Array = _moorings_warm.get(port, [])
		if not warm.is_empty() and warm[1] == layout.radius and warm[0] == int(_towns.get(port, {}).get("moorings", []).size()):
			continue  # (Known: its town laid, and every mooring's way worked out.)
		var moorings := _moorings(port)
		if moorings.is_empty():
			continue
		var all_known := true
		for mooring: Array in moorings:
			var way_key := [port, mooring[0], _port_layout(port).radius]
			if not _mooring_ways.has(way_key):
				_mooring_way(port, mooring)
				if not _mooring_ways.has(way_key):
					all_known = false  # (Its water still being mapped: back to it.)
				if Time.get_ticks_usec() - start >= MOORING_WARM_MS * 1000.0:
					_warm_moorings_at = (_warm_moorings_at + n) % ships.size()
					return
		if all_known:
			_moorings_warm[port] = [moorings.size(), layout.radius]
	_warm_moorings_at = (_warm_moorings_at + MOORING_WARM_SHIPS) % ships.size()

## A port's long-term moorings (see _lay_moorings()), or [] until its town is laid.
func _moorings(port_id: String) -> Array:
	var town := _town(port_id, _port_layout(port_id))
	return town.get("moorings", []) if not town.is_empty() else []

## The first free mooring at a port a ship fits (its index), or -1.
func _free_mooring(port_id: String, ship: Ship) -> int:
	var moorings := _moorings(port_id)
	if moorings.is_empty():
		return -1
	var taken: Dictionary = _spot_tables.get([port_id, "moor"], {})
	var length := (_model_look(ship.model_id)[7] as Rect2).size.x
	for i in moorings.size():
		if not taken.has(i) and length <= float(moorings[i][2]) and _mooring_way_known(port_id, moorings[i]) and not _mooring_way(port_id, moorings[i]).is_empty():
			return i  # (One with a way to it by water: see _mooring_way(); while that's being worked out, the anchorage.)
	return -1

## A ship's way from just outside its port's entrance to its mooring (dock
## poses): out round the jetty's end on the mooring's side, round the back of
## the quay if the mooring is behind it, up to the slip's mouth and straight in.
## Where any leg of that would cross land (a mooring field behind a spit or
## a headland: Surabaya's), the way out to the slip's staging point goes round
## by water instead (_water_way()). Worked out once per mooring.
func _mooring_way(port_id: String, mooring: Array) -> Array:
	var key := [port_id, mooring[0], _port_layout(port_id).radius]
	if not _mooring_ways.has(key):
		var way: Variant = _mooring_way_fresh(port_id, mooring)
		if way == null:
			return []  # (Its port's water still being mapped: see _port_water_grid().)
		_mooring_ways[key] = way
	return _mooring_ways[key]

## True once a mooring's way is known (see _mooring_way()), whether or not there is one.
func _mooring_way_known(port_id: String, mooring: Array) -> bool:
	_mooring_way(port_id, mooring)
	return _mooring_ways.has([port_id, mooring[0], _port_layout(port_id).radius])
var _mooring_ways := {}

func _mooring_way_fresh(port_id: String, mooring: Array) -> Variant:
	var poses := _mooring_way_plain(port_id, mooring)
	var dry := false
	for k in range(1, poses.size() - 1):  # (The last leg, into the slip, is the slip's own: always water.)
		if not _water_leg(port_id, poses[k - 1][0], poses[k][0]):
			dry = true
			break
	if not dry:
		return poses
	var layout := _port_layout(port_id)
	var radius := float(layout.radius)
	var stage: Array = poses[poses.size() - 2]
	# Set off from the water outside the entrance: beside the jetty's end on
	# the mooring's side if that's water, else straight out from the entrance.
	var start: Vector2 = poses[0][0]
	for spot: Vector2 in [poses[0][0], layout.mouth, Vector2(radius * 1.5, 0.0), Vector2(radius * 2.0, 0.0)]:
		if not _on_land(_dock_lon_lat(port_id, spot)):
			start = spot
			break
	if _port_water_grid(port_id).is_empty():
		return null  # (Not mapped yet.)
	var way := _water_way(port_id, start, stage[0])
	if way.size() < 2:
		return []  # (No way to it by water: not a mooring ships can use. See _free_mooring().)
	var out := []
	for k in way.size() - 1:
		out.append([way[k], (way[k + 1] - way[k]).angle()])
	out.append(stage)
	out.append(poses[poses.size() - 1])
	return out

## True if a straight leg (dock units) keeps to the water.
func _water_leg(port_id: String, a: Vector2, b: Vector2) -> bool:
	var steps := maxi(ceili(a.distance_to(b) / 0.8), 1)
	for s in range(1, steps):
		if _on_land(_dock_lon_lat(port_id, a.lerp(b, float(s) / steps))):
			return false
	return true

## A way by water between two points of a port's marina (dock units), round
## any land between: a search over the port's water grid (_port_water_grid()),
## then cut down to the corners it needs. [] if there's none.
const WATER_WAY_CELL := 1.5
func _water_way(port_id: String, from: Vector2, to: Vector2) -> PackedVector2Array:
	var water := _port_water_grid(port_id)
	var grid: AStarGrid2D = water.grid
	var origin: Vector2 = water.origin
	var n: int = water.n
	var cell_of := func(p: Vector2) -> Vector2i: return Vector2i(clampi(floori((p.x - origin.x) / WATER_WAY_CELL), 0, n - 1), clampi(floori((p.y - origin.y) / WATER_WAY_CELL), 0, n - 1))
	var start: Vector2i = cell_of.call(from)
	var goal: Vector2i = cell_of.call(to)
	var was_start := grid.is_point_solid(start)
	var was_goal := grid.is_point_solid(goal)
	grid.set_point_solid(start, false)
	grid.set_point_solid(goal, false)
	var cells := grid.get_id_path(start, goal)
	grid.set_point_solid(start, was_start)
	grid.set_point_solid(goal, was_goal)
	if cells.is_empty():
		return PackedVector2Array()
	var points := PackedVector2Array([from])
	for k in range(1, cells.size() - 1):
		points.append(origin + (Vector2(cells[k]) + Vector2(0.5, 0.5)) * WATER_WAY_CELL)
	points.append(to)
	# Cut down to the corners: from each kept point, as far on as the water runs straight.
	var out := PackedVector2Array([points[0]])
	var at := 0
	while at < points.size() - 1:
		var far := at + 1
		for k in range(points.size() - 1, at + 1, -1):
			if _water_leg(port_id, points[at], points[k]):
				far = k
				break
		out.append(points[far])
		at = far
	return out

## A port's water round its marina as a search grid of WATER_WAY_CELL cells
## (dock units), land and the marina itself (quay, basin and harbour: moored
## ships go round the jetty) solid, out as far as its moorings: made once.
func _port_water_grid(port_id: String) -> Dictionary:
	var layout := _port_layout(port_id)
	var key := [port_id, layout.radius]
	if _water_grids.has(key):
		return _water_grids[key]
	var task: Array = _water_tasks.get(key, [])
	if task.is_empty():
		var reach := float(layout.radius) * 2.5
		for mooring: Array in _moorings(port_id):
			reach = maxf(reach, (mooring[0] as Vector2).length() + float(mooring[2]) * 2.0 + float(layout.radius))
		var port := GameData.get_port(port_id)
		var job := {n = ceili(reach * 2.0 / WATER_WAY_CELL), origin = -Vector2.ONE * reach, layout = layout.duplicate(),
			lon = float(port.get("lon", 0.0)), lat = float(port.get("lat", 0.0)), angle = _port_sea_angle(port_id), flip = float(_dock_flips.get(port_id, 1.0)),
			solid = PackedByteArray()}
		_water_tasks[key] = [WorkerThreadPool.add_task(_map_water.bind(job), false, "Port water"), job]
		return {}
	if not WorkerThreadPool.is_task_completed(task[0]):
		return {}
	WorkerThreadPool.wait_for_task_completion(task[0])
	_water_tasks.erase(key)
	var job: Dictionary = task[1]
	var n: int = job.n
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, n, n)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	var solid: PackedByteArray = job.solid
	for i in solid.size():
		if solid[i]:
			grid.set_point_solid(Vector2i(i % n, i / n))
	var water := {grid = grid, origin = job.origin, n = n}
	_water_grids[key] = water
	return water
var _water_grids := {}
var _water_tasks := {}

## A port's water mapped (on a worker thread: see _port_water_grid()): each
## cell solid where it's land or the marina's own ground. Only plain numbers
## and the static land test, as _dock_lon_lat() works them out.
static func _map_water(job: Dictionary) -> void:
	var n: int = job.n
	var origin: Vector2 = job.origin
	var layout: Dictionary = job.layout
	var lon: float = job.lon
	var lat: float = job.lat
	var angle: float = job.angle
	var flip: float = job.flip
	var stretch := maxf(cos(deg_to_rad(lat)), 0.05)
	var solid := PackedByteArray()
	solid.resize(n * n)
	for y in n:
		for x in n:
			var p := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * WATER_WAY_CELL
			if _marina_ground(layout, p):
				solid[y * n + x] = 1
				continue
			var off := Vector2(p.x, p.y * flip).rotated(angle) / SHIP_WORLD_ZOOM
			if _on_land(Vector2(lon + off.x / stretch, lat - off.y)):
				solid[y * n + x] = 1
	job.solid = solid

## The plain way (see _mooring_way()), without looking at the land: the
## slip's staging point pulled back along the slip to the last of the water.
func _mooring_way_plain(port_id: String, mooring: Array) -> Array:
	var layout := _port_layout(port_id)
	var radius := float(layout.radius)
	var middle: Vector2 = mooring[0]
	var facing := float(mooring[1])
	var away := -Vector2.from_angle(facing)
	var mouth := middle + away * (float(mooring[2]) / 2.0 + 1.5)
	var out := maxf(float(mooring[2]) * 0.8, 4.0)
	while out > 1.0 and _on_land(_dock_lon_lat(port_id, mouth + away * out)):
		out -= 1.0
	var stage := mouth + away * out
	var side := 1.0 if stage.y >= 0.0 else -1.0
	var poses := [[Vector2(radius * 1.25, side * radius * 0.8), PI / 2.0 * side]]
	var corner := Vector2(radius * 0.3, side * radius * 1.45)
	var next := stage
	if stage.x < _quay_inland(layout) - 1.0:
		next = Vector2(_quay_inland(layout) - 2.0, side * (radius + 2.0))
	poses.append([corner, (next - corner).angle()])
	if next != stage:
		poses.append([next, (stage - next).angle()])
	poses.append([stage, (mouth - stage).angle()])
	poses.append([mouth, facing])
	return poses


## A port's town by day (see _draw_marina()): every block's shadow, then its
## walls, roof and rooftop in its style, and the parks' trees.
func _draw_town(port_id: String, layout: Dictionary, scale: float) -> void:
	var town := _town(port_id, layout)
	if town.is_empty():
		return
	_batch.clear()
	var t_p := Time.get_ticks_usec()
	_draw_pontoons(port_id, layout, town, scale)
	_prof("marina.pontoons", t_p)
	# The town itself: its mesh (see _town_mesh()) scaled into the item.
	var flip := float(_dock_flips.get(port_id, 1.0))
	var dock := dock_scale(port_id)
	_canvas.draw_mesh(_town_mesh(port_id, town, flip), null, Transform2D(0.0, Vector2(dock, dock * flip), 0.0, Vector2.ZERO))

## A town's blocks, roads, parks and landmark as one mesh in dock units (see
## PolyBatch), built once and kept with the town (its buildings never move;
## the shadows go with the sun, so it's built again when that's moved enough:
## _shadow_key()), so drawing the marina again (at a new zoom, or as it
## scrolls in) costs one call, not thousands.
func _town_mesh(port_id: String, town: Dictionary, flip: float) -> ArrayMesh:
	var turn := _port_sea_angle(port_id) + _port_turn(port_id)
	var key := [flip, _shadow_key(), roundi(turn / 0.3)]
	if town.has("mesh") and town.mesh_key == key:
		return town.mesh
	var t0 := Time.get_ticks_usec()
	var batch := PolyBatch.new()
	var drop := (_shadow_dir * 0.4).rotated(-turn)  # (Per unit of height, in the item's frame.)
	drop.y *= flip
	if _town_mesher == null and ClassDB.class_exists(&"TownMesh"):
		_town_mesher = ClassDB.instantiate(&"TownMesh")
	if _town_mesher != null:
		# Natively (TownMesh: the same shapes in the same order), each landmark's
		# details spliced into the triangles' order right after its walls.
		var built: Dictionary = _town_mesher.build(town.get("roads", []), town.buildings, town.parks, drop,
			{walk = TOWN_WALK, road = TOWN_ROAD, lane = TOWN_LANE, shadow = TOWN_SHADOW, park = TOWN_PARK})
		batch.points = built.points
		batch.colors = built.colors
		batch.uvs.resize(batch.points.size())
		var native_indices: PackedInt32Array = built.indices
		var landmark_at: PackedInt32Array = built.get("landmark_at", PackedInt32Array())
		if landmark_at.size() != (built.landmarks as PackedInt32Array).size():  # (An older library: details last.)
			landmark_at.resize((built.landmarks as PackedInt32Array).size())
			landmark_at.fill(native_indices.size())
		var indices := PackedInt32Array()
		var cursor := 0
		for k in (built.landmarks as PackedInt32Array).size():
			indices.append_array(native_indices.slice(cursor, landmark_at[k]))
			cursor = landmark_at[k]
			var block: Array = town.buildings[built.landmarks[k]]
			batch.indices = PackedInt32Array()
			_draw_landmark(batch, str(block[4]).trim_prefix("landmark:"), block[0], block[1], block[2])
			indices.append_array(batch.indices)
		indices.append_array(native_indices.slice(cursor))
		batch.indices = indices
	else:
		_build_town_batch(batch, town, drop)
	# The link roads to a neighbouring town (see _join_neighbour_towns()), under everything.
	var links: Array = town.get("links", [])
	if not links.is_empty():
		var base := batch.points.size()
		var link_batch := PolyBatch.new()
		for link: Array in links:
			link_batch.line(link[0], link[1], TOWN_ROAD, TOWN_LINK_WIDTH)
			link_batch.disc(link[0], TOWN_LINK_WIDTH / 2.0, TOWN_ROAD)
			link_batch.disc(link[1], TOWN_LINK_WIDTH / 2.0, TOWN_ROAD)
		batch.points.append_array(link_batch.points)
		batch.colors.append_array(link_batch.colors)
		batch.uvs.resize(batch.points.size())
		var first := PackedInt32Array()
		for index in link_batch.indices:
			first.append(index + base)
		first.append_array(batch.indices)
		batch.indices = first
	var mesh := batch.to_mesh()
	town.mesh = mesh
	town.mesh_key = key
	_prof("marina.town_mesh", t0)
	return mesh

## The town's triangles in GDScript (without the library): see TownMesh.
func _build_town_batch(batch: PolyBatch, town: Dictionary, drop: Vector2) -> void:
	for road: Array in town.get("roads", []):
		var rect: Rect2 = road[0]
		var kind: String = road[1]
		if rect.size.x <= 0.0 or rect.size.y <= 0.0:
			continue
		batch.poly(_rect_points(rect), TOWN_WALK if kind == "walk" else TOWN_ROAD)
		if kind == "avenue":
			var x := rect.position.x + 0.5
			while x < rect.end.x - 0.8:
				batch.poly(_rect_points(Rect2(x, rect.get_center().y - 0.05, 0.8, 0.1)), TOWN_LANE)
				x += 1.6
	# Shadows first (every building's, so no block's shadow lies over another's roof).
	for block: Array in town.buildings:
		var rect: Rect2 = block[0]
		var height: float = block[3]
		var shadow := _rect_points(rect)
		for i in shadow.size():
			shadow[i] += drop * height
		batch.poly(shadow, TOWN_SHADOW)
	for park: Array in town.parks:
		var at: Vector2 = park[0]
		var r := float(park[1])
		batch.disc(at, r, TOWN_PARK, 20)
		batch.disc(at + Vector2(r * 0.4, -r * 0.3), r * 0.55, TOWN_PARK.lightened(0.12), 20)
	for block: Array in town.buildings:
		var rect: Rect2 = block[0]
		var wall: Color = block[1]
		var roof: Color = block[2]
		var kind: String = block[4]
		var salt: float = block[5]
		batch.poly(_rect_points(rect), wall)
		var top := rect.grow(-0.14)
		if kind.begins_with("landmark:"):
			_draw_landmark(batch, kind.trim_prefix("landmark:"), rect, wall, roof)
			continue
		match kind:
			"pitched":
				# Two slopes either side of a ridge along the longer way, the sunny one lighter.
				var along_x := top.size.x >= top.size.y
				var a := Rect2(top.position, Vector2(top.size.x, top.size.y / 2.0) if along_x else Vector2(top.size.x / 2.0, top.size.y))
				var b := Rect2(top.position + (Vector2(0.0, top.size.y / 2.0) if along_x else Vector2(top.size.x / 2.0, 0.0)), a.size)
				batch.poly(_rect_points(a), roof.lightened(0.12))
				batch.poly(_rect_points(b), roof.darkened(0.1))
			"pagoda":
				batch.poly(_rect_points(top), roof)
				batch.poly(_rect_points(top.grow(-0.35)), roof.lightened(0.18))
				batch.poly(_rect_points(top.grow(-0.6)), roof)
			"warehouse":
				batch.poly(_rect_points(top), roof)
				var ribs := maxi(int(top.size.y / 0.7), 2)
				for k in ribs:
					var y := top.position.y + top.size.y * (k + 0.5) / ribs
					batch.poly(_rect_points(Rect2(top.position.x + 0.1, y - 0.08, top.size.x - 0.2, 0.16)), roof.darkened(0.18))
			"tall":
				batch.poly(_rect_points(top), roof)
				batch.poly(_rect_points(top.grow(-0.3)), roof.lightened(0.14))
				batch.poly(_rect_points(Rect2(top.get_center() - Vector2(0.18, 0.18), Vector2(0.36, 0.36))), roof.darkened(0.3))
			_:
				batch.poly(_rect_points(top), roof)
				batch.poly(_rect_points(top.grow(-0.22)), roof.lightened(0.07))
				if salt > 0.4:  # Roof gear: a tank or an air unit.
					var at := top.position + Vector2(top.size.x * (0.25 + salt * 0.5), top.size.y * 0.3)
					batch.poly(_rect_points(Rect2(at - Vector2(0.14, 0.14), Vector2(0.28, 0.28))), roof.darkened(0.35))

## A filled circle as a fan of triangles (draw_circle() triangulates a 64-gon each call: slow in a marina record).
func _disc(center: Vector2, r: float, color: Color) -> void:
	_batch.clear()
	_batch.disc(center, r, color, 32)
	_batch.flush(_canvas)

## A port's pontoons (see _lay_moorings()): each a floating walkway with dark
## floats under it, its finger piers with a cleat at each root, in wood at the
## smaller ports and concrete at the bigger.
func _draw_pontoons(port_id: String, layout: Dictionary, town: Dictionary, scale: float) -> void:
	var deck := MOOR_WOOD if (layout.berths as Array).size() <= 8 else MOOR_CONCRETE
	var pontoon_px := maxf(MOOR_PONTOON_WIDTH * scale, 1.5)
	var finger_px := maxf(MOOR_FINGER_WIDTH * scale, 1.0)
	for pontoon: Array in town.get("pontoons", []):
		var a: Vector2 = pontoon[0]
		var b: Vector2 = pontoon[1]
		for finger: Array in pontoon[2]:
			var root := _dock_point(port_id, finger[0])
			var tip := _dock_point(port_id, finger[1])
			_batch.line(root, tip, MOOR_EDGE, finger_px + 1.6)
			_batch.line(root, tip, deck, finger_px)
			if scale >= 3.0:
				_batch.disc(root.lerp(tip, 0.08), maxf(0.12 * scale, 1.0), MOOR_CLEAT)
				_batch.disc(root.lerp(tip, 0.92), maxf(0.12 * scale, 1.0), MOOR_CLEAT)
		var pa := _dock_point(port_id, a)
		var pb := _dock_point(port_id, b)
		if scale >= 2.5:
			var d := (b - a).normalized()
			var s := 1.0
			while s < a.distance_to(b) - 0.5:
				var at := _dock_point(port_id, a + d * s)
				_batch.disc(at, maxf(0.32 * scale, 1.2), MOOR_FLOAT)
				s += 2.2
		_batch.line(pa, pb, MOOR_EDGE, pontoon_px + 2.0)
		_batch.line(pa, pb, deck, pontoon_px)
		if scale >= 4.0:  # The planks' seams.
			var d := (b - a).normalized()
			var s := 0.6
			while s < a.distance_to(b):
				var at := a + d * s
				var across := Vector2(-d.y, d.x) * MOOR_PONTOON_WIDTH * 0.45
				_batch.line(_dock_point(port_id, at - across), _dock_point(port_id, at + across), MOOR_EDGE * Color(1, 1, 1, 0.35), 1.0)
				s += 1.2
	_batch.flush(_canvas)

## A town's landmark (see TOWN_STYLES landmark), on its block.
func _draw_landmark(batch: PolyBatch, what: String, rect: Rect2, wall: Color, roof: Color) -> void:
	var middle := rect.get_center()
	match what:
		"church":
			# A nave with a pitched roof and a square tower at its inland end.
			var nave := Rect2(rect.position + Vector2(rect.size.x * 0.1, rect.size.y * 0.3), Vector2(rect.size.x * 0.8, rect.size.y * 0.4))
			batch.poly(_rect_points(Rect2(nave.position, Vector2(nave.size.x, nave.size.y / 2.0))), roof.lightened(0.12))
			batch.poly(_rect_points(Rect2(nave.position + Vector2(0.0, nave.size.y / 2.0), Vector2(nave.size.x, nave.size.y / 2.0))), roof.darkened(0.1))
			var tower := Rect2(rect.position + Vector2(rect.size.x * 0.08, rect.size.y * 0.25), Vector2.ONE * rect.size.y * 0.5)
			batch.poly(_rect_points(Rect2(tower.position + Vector2(0.4, 0.4), tower.size)), TOWN_SHADOW)
			batch.poly(_rect_points(tower), wall.lightened(0.1))
			batch.poly(_rect_points(tower.grow(-0.2)), roof.darkened(0.2))
		"minaret":
			var dome := Rect2(middle - Vector2(0.75, 0.75), Vector2(1.5, 1.5))
			batch.poly(_rect_points(dome.grow(0.15)), wall.lightened(0.08))
			batch.disc(middle, 0.72, Color("#3f8f7a"), 20)
			batch.disc(middle + Vector2(-0.2, -0.2), 0.3, Color("#6fb8a0"), 20)
			var at := rect.position + Vector2(0.45, 0.45)
			batch.disc(at + Vector2(0.4, 0.4), 0.34, TOWN_SHADOW, 20)
			batch.disc(at, 0.3, wall.lightened(0.15), 20)
			batch.disc(at, 0.14, roof.darkened(0.3), 20)
		"pagoda":
			for tier in 3:
				var size := rect.size * (0.9 - tier * 0.26)
				var box := Rect2(middle - size / 2.0, size)
				batch.poly(_rect_points(box), roof.darkened(0.1 + tier * 0.08) if tier % 2 == 0 else wall)
			batch.disc(middle, 0.12, Color("#c8a040"), 20)
		"skyscraper":
			batch.poly(_rect_points(Rect2(rect.position + Vector2(0.9, 0.9), rect.size)), TOWN_SHADOW)
			for tier in 3:
				var box := rect.grow(-0.12 - tier * 0.32)
				batch.poly(_rect_points(box), (Color("#6a7a8a") if tier % 2 == 0 else Color("#8a9aaa")).lightened(tier * 0.05))
			batch.disc(middle, 0.1, Color(1.0, 0.3, 0.2), 20)
		"onion":
			batch.poly(_rect_points(rect.grow(-0.14)), wall.lightened(0.1))
			for k in 4:
				var at := middle + Vector2.from_angle(k * TAU / 4.0 + PI / 4.0) * rect.size.x * 0.28
				batch.disc(at, 0.26, Color("#2f6ab0") if k % 2 == 0 else Color("#c8a040"), 20)
			batch.disc(middle, 0.4, Color("#c8a040"), 20)
			batch.disc(middle + Vector2(-0.1, -0.1), 0.16, Color("#e8d080"), 20)
		"stupa":
			batch.poly(_rect_points(rect.grow(-0.14)), wall.lightened(0.1))
			batch.disc(middle, 0.8, Color("#e8e2d0"), 20)
			batch.disc(middle, 0.5, Color("#d8b050"), 20)
			batch.disc(middle, 0.18, Color("#f0d070"), 20)
		"dome":
			batch.poly(_rect_points(rect.grow(-0.14)), wall.lightened(0.1))
			batch.disc(middle, 0.7, Color("#e8e8ee"), 20)
			batch.disc(middle + Vector2(-0.18, -0.18), 0.3, Color("#ffffff"), 20)
		_:
			batch.poly(_rect_points(rect.grow(-0.14)), roof)
## A town's lights at night (see _draw_marina_lights()): a warm glow over
## the whole town, and its windows lit (once they're big enough to see).

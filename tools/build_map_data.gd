# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends SceneTree
## Builds the game's map data from Natural Earth downloads:
##   data/world_map.res  land, coastline, borders and country labels, for drawing
##   data/sea_lanes.res  a sea route and its distance between every pair of ports
##
## Rerun after changing data/ports.json (takes several minutes; add
## "-- --lanes-only" to skip rebuilding the map art, or "-- --map-only" to
## rebuild only the map art: land, lakes, rivers, borders and labels). After
## changing only data/canals.json, "-- --canals-only" lays the canals into the
## existing lanes again in seconds (without rounding the corners where they
## join; see _round_corners(), which needs the land grid of a lanes run):
##   Godot --headless --path . -s tools/build_map_data.gd
## "-- --channels-only" lays every port's approach channels into the existing
## lanes again (see _lay_channels(); a lanes run doesn't: run it after one).
## "-- --currents-only" plans the lanes' second ways round on the currents
## (see _plan_current_ways(); after a lanes or channels run, which drop them).
## "-- --fishing-only" routes the fishing grounds' lanes (see _plan_fishing_lanes(); last of all).
## "-- --biomes-only" redraws just the biome patches into the existing
## data/world_map.res (after changing BIOME_SIMPLIFY, say), in about a minute.
## "-- --decor-only" rebuilds just the land drawings (and their clearance) in
## the existing map, from the biomes worked out again.
## "-- --animals-only" puts the animals (ANIMALS) into the existing map's
## land drawings again and works out every drawing's clearance (in seconds);
## add "--nudge" to have it suggest a spot further inland for any animal too
## near the water to show (see ANIMAL_ROOM).
## While working on the routing, "-- --lanes-only --pairs PUS-YOK,DXB-HKG" (or
## "--ports CPH,GDN" for every lane to or from those ports)
## re-routes just those lanes into the existing data/sea_lanes.res (in under a
## minute), and "-- --lanes-only --audit" lists lanes with pointless detours
## (see _audit_lanes(); add "--from res://build/old_sea_lanes.res" to audit another
## lanes file).
##
## Source files (public domain, https://www.naturalearthdata.com), in tools/source_data/:
##   ne_10m_land.geojson, ne_50m_admin_0_countries.geojson,
##   ne_10m_lakes.geojson, ne_10m_rivers_lake_centerlines.geojson
## from https://github.com/nvkelso/natural-earth-vector/tree/master/geojson

const LAND_PATH := "res://tools/source_data/ne_10m_land.geojson"
const COUNTRIES_PATH := "res://tools/source_data/ne_50m_admin_0_countries.geojson"
const LAKES_PATH := "res://tools/source_data/ne_10m_lakes.geojson"
const RIVERS_PATH := "res://tools/source_data/ne_10m_rivers_lake_centerlines.geojson"
## Sea depth bands (nested: each is all the sea deeper than its depth), from
## shallowest to deepest, as [depth in m, file].
const DEPTHS_PATH := "res://tools/source_data/ne_10m_bathymetry_%s.geojson"
const DEPTH_BANDS := [[200, "K_200"], [1000, "J_1000"], [2000, "I_2000"], [3000, "H_3000"], [4000, "G_4000"],
	[5000, "F_5000"], [6000, "E_6000"], [7000, "D_7000"], [8000, "C_8000"], [9000, "B_9000"], [10000, "A_10000"]]
## Natural Earth II (1:50m, shaded relief, no water), converted from its TIFF to
## PNG: idealized land cover, in plain longitude/latitude, 30 pixels a degree.
const LAND_COLORS_PATH := "res://tools/source_data/NE2_50M_SR.png"
## Its sea color: pixels this exact color are sea (and floating ice shelves).
const LAND_COLORS_SEA := Color8(251, 251, 251)
## Depth bands are simplified more than the coast (projected degrees).
const DEPTH_SIMPLIFY_TOLERANCE := 0.04
## Named geography to label (see _add_feature_labels()): marine areas and land
## regions from Natural Earth, and the kinds (MapView.FeatureKind order: ocean,
## sea, strait, range, desert, lake, river) each of their classes becomes.
const MARINE_PATH := "res://tools/source_data/ne_10m_geography_marine_polys.geojson"
const REGIONS_PATH := "res://tools/source_data/ne_10m_geography_regions_polys.geojson"
const MARINE_KINDS := {ocean = 0, sea = 1, gulf = 1, bay = 1, sound = 1, strait = 2, channel = 2}
const REGION_KINDS := {"Range/mtn": 3, "Desert": 4}
const LAKE_KIND := 5
const RIVER_KIND := 6
## The label spot search: a grid this many points across, refined this many times.
const LABEL_GRID := 16
const LABEL_REFINE_ROUNDS := 3
const PORTS_PATH := "res://data/ports.json"
const CANALS_PATH := "res://data/canals.json"
const MAP_OUT := "res://data/world_map.res"
## The land colors (see _build_land_texture()), and its size in pixels.
const LAND_TEXTURE_OUT := "res://data/land_colors.webp"
const LAND_TEXTURE_SIZE := 4096
## How many pixels in from the coast the land texture's sea is filled with the
## nearest land's color (about 1 degree).
const LAND_FILL_RINGS := 12
## Biomes (see _build_biomes()): forest north of BOREAL_LAT is boreal, land
## north of TUNDRA_LAT that isn't forest is tundra.
const BOREAL_LAT := 52.0
const TUNDRA_LAT := 62.0
## Each majority pass's radius (cells), widest first, so specks go and edges settle.
const BIOME_SMOOTHING_RADII: Array[int] = [2, 2, 1, 1]
## Land drawings (see _add_decor()): the land's cover is placed on a grid this
## far apart (real degrees, jittered), each spot its biome's drawing (or none).
const VEGETATION_SPACING := 0.2
## Mangroves (see _plant_mangroves()): how near the equator (degrees), how near
## the water (projected degrees), which drawings, and what share of those.
const MANGROVE_LAT := 28.0
const MANGROVE_SHORE := 0.3
const MANGROVE_SHARE := 0.45
const MANGROVE_FROM := {rainforest = true, palm = true, acacia = true, grass = true}
## The mountains along the ranges, this far apart (real degrees), so their
## peaks (MapView DECOR_KM) overlap into ridges; and the ranges that are
## snow-capped all along, whatever their latitude (Natural Earth names).
const MOUNTAIN_SPACING := 0.42
const SNOWY_RANGES := ["HIMALAYAS", "ANDES", "ALPS", "KARAKORAM RANGE", "HINDU KUSH", "PAMIRS", "TIAN SHAN", "KUNLUN MOUNTAINS", "CAUCASUS", "ROCKY MOUNTAINS", "SIERRA NEVADA", "CASCADE RANGE", "ALASKA RANGE", "SOUTHERN ALPS", "ZAGROS MOUNTAINS", "PYRENEES"]
## Natural Earth's "ranges" that get no mountains and no label: everything
## smaller than Spain's Sierra Nevada (22,400 km2 by its polygon: the Vosges,
## the Jura, Calabria, the Black Hills, the Australian Alps...), and the bigger
## ones that aren't really mountains (plateaus, escarpments, low hills: the
## Hadhramaut, the Witwatersrand, Uruguay's Cuchilla Grande, Alberta's Birch
## and Caribou hills, the Brazilian serras of the shield, the Mogollon Rim...).
const DROPPED_RANGES := ["SHACKLETON RANGE", "AHMAR MTS.", "FLOOD RANGE", "MOYEN ATLAS", "FORD RANGES", "CENTRAL BRUHUI RANGE", "LEBOMBO MTS.", "MBANG MTS.",
	"WASATCH RANGE", "HAMERSLEY RA.", "YAM ALIN’ RANGE", "SELWYN RA.", "AL JABAL AL AKHDAR", "AUSTRALIAN ALPS", "CALABRIA", "BLACK HILLS", "BUREINSKIY RA.",
	"NAPIER MOUNTAINS", "VOSGES", "SUDETES MTS.", "ARDENNES", "CAMBRIAN MTS.", "JURA", "MAYA MTS.", "TORNGAT MTS.", "BÖHMERWALD", "ADMIRALTY MOUNTAINS", "HARZ",
	"VATNAJÖKULL", "GREGORY RA.", "GRAMPIAN MTS.", "PRINCE ALBERT MOUNTAINS", "EXECUTIVE COMMITTEE RANGE", "QUEEN ALEXANDRA RANGE", "RUWENZORI RANGE", "ERZGEBIRGE",
	"JONES MOUNTAINS", "LEBANON MTS.", "BLUE MTS.", "SCOTT MOUNTAINS",
	"HADHRAMAUT", "WITWATERSRAND", "CUCHILLA GRANDE", "BIRCH MTS.", "CARIBOU MTS.", "DARLING RANGE", "S. DO CACHIMBO", "S. DOS GRADAÚS", "S. DOURADA",
	"HARDANGER-VIDDA", "MOGOLLON RIM", "TUWAYQ MTS.", "SIWALIK HILLS", "SERRA DA IBIAPABA", "S. DO PIAUI", "SERRA ACARAÍ", "SERRA DE CURUPIRA", "TUMUC-HUMAC MTS.",
	"WILHELMINA GEBERGTE", "CENTRAL HIGHLANDS", "JABAL BIN GHUNAYMAH", "GROOT KARASBERGE", "MUCHINGA MTS.", "CHAÎNE DES MONGOS", "KHASI HILLS"]
## Waves dot the sea beyond this latitude, north and south (the Southern
## Ocean's rough seas, game_config rough_seas, start at 60°S), this far apart
## (real degrees), at this share of the spots.
const WAVES_LAT := 60.0
const WAVES_CHANCE := 0.6
const WAVES_SPACING := 2.2
## Animals where they live: [art name, lon, lat, tier].
const ANIMALS := [
	["penguin", 42.39, -69.57, 1], ["penguin", -60.29, -64.16, 2], ["penguin", 170.80, -76.60, 2], ["penguin", -69.01, -52.42, 3], ["penguin", 18.62, -34.23, 3],
	["polar_bear", -92.86, 67.52, 1], ["polar_bear", -149.81, 69.51, 2], ["polar_bear", 18.22, 78.80, 2], ["polar_bear", -40.00, 73.00, 2], ["polar_bear", 140.34, 70.56, 3],
	["camel", 12.0, 25.0, 1], ["camel", 46.0, 22.0, 2], ["camel", 105.0, 43.0, 2], ["camel", 28.0, 21.0, 3],
	["elephant", 37.51, -2.65, 1], ["elephant", 24.0, -19.0, 2], ["elephant", 76.80, 11.51, 2],
	["giraffe", 35.35, -4.59, 2], ["giraffe", 20.0, -21.0, 3],
	["lion", 34.8, -2.3, 2], ["lion", 25.0, -23.5, 3],
	["zebra", 36.5, -6.5, 3], ["zebra", 26.41, -17.11, 3],
	["kangaroo", 134.0, -25.0, 1], ["kangaroo", 145.5, -28.0, 2], ["kangaroo", 121.0, -28.0, 2],
	["koala", 150.5, -29.5, 2],
	["panda", 103.5, 30.5, 1],
	["tiger", 80.0, 22.0, 2], ["tiger", 135.5, 46.0, 2], ["tiger", 88.97, 23.08, 3],
	["bison", -101.32, 43.68, 1], ["bison", -110.24, 45.52, 3],
	["moose", -98.34, 55.99, 2], ["moose", -73.39, 49.13, 2], ["moose", 17.94, 63.91, 2], ["moose", 128.0, 61.0, 3],
	["brown_bear", -152.0, 62.0, 2], ["brown_bear", 45.0, 62.0, 2], ["brown_bear", 159.0, 56.5, 2],
	["reindeer", 24.23, 68.71, 1], ["reindeer", 100.0, 68.0, 2], ["reindeer", -118.15, 63.99, 2],
	["llama", -68.06, -17.08, 1], ["llama", -72.0, -13.8, 3],
	["toucan", -62.0, -4.0, 1], ["toucan", -71.0, 0.0, 2], ["toucan", -52.0, -9.0, 3],
	["gorilla", 13.0, 0.5, 2], ["gorilla", 29.33, -1.16, 3],
	["orangutan", 114.0, 1.0, 2], ["orangutan", 98.03, 3.44, 3],
	["kiwi", 175.12, -39.25, 2], ["kiwi", 169.69, -43.93, 3],
	["lemur", 46.5, -20.0, 2],
	# Water buffalo on the floodplains of Australia's Top End, and a pizza on Albuquerque.
	["water_buffalo", 132.82, -13.23, 2], ["water_buffalo", 131.29, -13.52, 3],
	["pizza", -106.65, 35.08, 2],
	# The resplendent quetzal (perched) in the cloud forests of Guatemala and
	# Costa Rica. (Eagles, hawks and ospreys fly with the seabirds: Birds.)
	["quetzal", -90.4, 15.4, 2], ["quetzal", -84.33, 10.57, 2],
]
const LANES_OUT := "res://data/sea_lanes.res"
## Approach channels (see _lay_channels()): a port's lanes share their last
## CHANNEL_NM nm, each leaving its own way CHANNEL_JOIN_NM out to join; lanes
## coming in within CHANNEL_SPREAD_DEG of bearing of each other share one;
## lanes shorter than CHANNEL_MIN_LANE_NM keep their own ways.
const CHANNEL_NM := 80.0
const CHANNEL_JOIN_NM := 105.0
const CHANNEL_SPREAD_DEG := 30.0
const CHANNEL_MIN_LANE_NM := 260.0

## Coastline simplification, in projected degrees (~0.7 nm at the equator).
const SIMPLIFY_TOLERANCE := 0.012
## Land is cut into tiles this size before triangulating, to keep polygons small.
const TILE_SIZE := 5.0

## Pathfinding grid in projected coordinates. It runs past 180 degrees east so
## routes across the Pacific have no seam: the Americas appear twice, once at
## their real longitude and once 360 degrees further east.
const GRID_WEST := -180.0
const GRID_EAST := 320.0
const GRID_SOUTH_LAT := -79.0
const GRID_NORTH_LAT := 80.5
## Only lanes to or from an Arctic port (ports.json arctic: true) may go north
## of this: between two other ports the Arctic counts as land (see
## _block_arctic), so their lanes are as they were before the Arctic was added.
const ARCTIC_LAT := 66.0
## Latitude where the pathfinder's distance weights stop growing (see _build_coarse_graph()).
const WEIGHT_MAX_LAT := 66.0
const GRID_CELL := 0.1
## Routes whose ends are further apart than this (in longitude) are not tried
## with that pairing of the two copies of the Americas.
const MAX_ROUTE_SPAN := 270.0
## Ports closer than this in longitude are only routed at their real
## longitudes; further apart, the way across the Pacific is tried too.
const MIN_WRAP_SPAN := 150.0
## Coarse search grid: this many fine cells per side.
const COARSE := 5
## Extra cost for coarse cells that touch land, so lanes keep off the coast.
const COAST_PENALTY := 1.3
## How far (in cells) a port may be from the water cell its lanes start from.
const SNAP_RADIUS := 30
## Great-circle legs are split into pieces about this long (nm) where open water allows.
const GREAT_CIRCLE_STEP_NM := 100.0
## How closely (nm) a great-circle shortcut is checked for land, and how near
## a port end it may pass the coast (see _great_circle_shortcuts()).
const ARC_CHECK_NM := 25.0
const ARC_PORT_NM := 30.0
## Lane corners are rounded into arcs this wide (see _round_corners()), drawn
## in steps of at most ARC_STEP_DEG of turn; turns under MIN_TURN_DEG are left
## alone, and an arc that hits land is tightened up to CORNER_TRIES times.
const TURN_RADIUS_NM := 60.0
const ARC_STEP_DEG := 12.0
const MIN_TURN_DEG := 4.0
const CORNER_TRIES := 5
## Canals (data/canals.json) are laid into the lanes that cross them, so ships
## follow the centerline and its locks exactly (see _splice_canal()). Lane
## points within this many degrees of a centerline count as on it.
const CANAL_SNAP_DEG := 0.2
## "--audit" flags a lane that could save this much (nm), and this share of the
## way it goes, by cutting straight across open water (see _audit_lanes()).
const AUDIT_MIN_SAVING_NM := 100.0
const AUDIT_MIN_RATIO := 1.3
## A detour is looked for within this many lane points of where it starts.
const AUDIT_WINDOW := 80
const AUDIT_OUT := "res://build/lane_audit.tsv"
## Lakes that are part of the sea lanes (the Great Lakes, reached up the St.
## Lawrence Seaway). The land data covers every lake, so these are cut back
## out of it as water, from their outlines in the lakes data.
const SEA_LAKES: Array[String] = ["Lake Superior", "Lake Michigan", "Lake Huron", "Lake Erie", "Lake Ontario", "Lake Saint Clair"]
## Lakes (see _add_lakes()): each group's simplified real color, the named
## lakes that aren't plain fresh water (a lake not named here is "saline" if
## Natural Earth calls it alkaline, else "fresh"), and the dry salt lakes.
const LAKE_GROUPS := {
	"fresh": "#5c9fd4",  # Clear fresh water.
	"deep": "#3b7cc0",  # Deep, very clear lakes.
	"green": "#5f9f8a",  # Shallow, plant-rich lakes.
	"muddy": "#9a9a70",  # Silty, shallow lakes.
	"glacial": "#46bcc6",  # Glacial meltwater turquoise.
	"saline": "#5fc4bd",  # Salt lakes: aqua.
	"jade": "#5fae8a",  # Lake Turkana, the Jade Sea.
	"pink": "#d39088",  # Red-algae salt lakes.
	"salt_pan": "#ece0d4",  # Dry salt lakes, mostly a white crust.
}
const LAKE_NAMES := {
	"Lake Baikal": "deep", "Lake Tanganyika": "deep", "Lake Malawi": "deep", "Lago Titicaca": "deep", "Lake Superior": "deep",
	"Lake Michigan": "deep", "Lake Huron": "deep", "Georgian Bay": "deep", "North Channel": "deep", "Whitefish Bay": "deep",
	"Lake Tahoe": "deep", "Issyk-Kul": "deep", "Great Bear Lake": "deep", "Great Slave Lake": "deep", "McLeod Bay": "deep",
	"Lake Ladoga": "deep", "Lake Onega": "deep", "Khövsgöl Nuur": "deep", "Lake Ontario": "deep", "Lago Llanquihue": "deep",
	"Lake Victoria": "green", "Lake Okeechobee": "green", "Lake Winnipeg": "green", "Lake Erie": "green", "Lake Saint Clair": "green",
	"Lago de Nicaragua": "green", "Hongze Hu": "green", "Lake Manitoba": "green", "Lake Winnipegosis": "green", "Lake Albert": "green",
	"Salton Sea": "green", "IJsselmeer": "green", "Kaliningradskiy Zaliv": "green", "Zalew Wislany": "green",
	"Lake Chad": "muddy", "Tonlé Sap": "muddy",
	"Lago Buenos Aires": "glacial", "Lago Argentino": "glacial", "Lago Viedma": "glacial", "Lake Pukaki": "glacial", "Lake Tekapo": "glacial",
	"Dead Sea": "saline", "Qinghai Hu": "saline", "Great Salt Lake": "saline", "South Aral Sea": "saline",
	"Lake Turkana": "jade",
	"Syvash": "pink", "Lake Natron": "pink", "Lake Urmia": "pink", "Lake Hillier": "pink",
}
## Where salt lakes not named in LAKE_NAMES are taken as dry salt pans: inland
## Australia (lon, lat).
const LAKE_DRY_SALT_REGION := Rect2(110.0, -40.0, 45.0, 26.0)
const LAKE_SALT_PANS: Array[String] = ["Lake Eyre North", "Lake Eyre South", "Lake Disappointment", "Lake Mackay", "Lake Gairdner",
	"Lake Torrens", "Lake Frome", "Lake Amadeus", "Lake Carnegie", "Chott el Djerid", "Chott Melrhir"]
## Rivers and straits too narrow for the grid to see. Carved as water, like
## the canals in data/canals.json. Each is a list of [lon, lat] points.
## Passages dredged out of the land itself (not just the lane grid): each a
## course (lon, lat) and a width (nm) cut from every land polygon it crosses,
## so the coast as drawn, the sea grid and the lanes all leave room for two
## of the biggest ships abreast through the Strait of Messina, the Bosporus
## and the Dardanelles, and the St. Lawrence between Quebec and Lake Ontario
## (see _dredge()). The real channels are far narrower; the ships are far bigger than life.
const DREDGES := [
	["Strait of Messina", [[15.74, 38.38], [15.68, 38.31], [15.66, 38.25], [15.62, 38.18], [15.60, 38.10], [15.57, 38.00], [15.60, 37.92]], 13.0],
	["Bosporus", [[29.16, 41.26], [29.12, 41.21], [29.08, 41.16], [29.05, 41.11], [29.02, 41.06], [28.99, 41.01], [28.97, 40.96]], 13.0],
	["Dardanelles", [[26.10, 39.98], [26.15, 40.00], [26.27, 40.07], [26.40, 40.15], [26.45, 40.22], [26.55, 40.30], [26.68, 40.41], [26.80, 40.48]], 13.0],
	["St. Lawrence", [[-71.10, 46.86], [-71.40, 46.76], [-71.90, 46.56], [-72.30, 46.40], [-72.70, 46.27], [-73.15, 46.02], [-73.30, 45.74], [-73.50, 45.56], [-73.70, 45.43], [-74.10, 45.31], [-74.50, 45.12], [-74.85, 45.03], [-75.20, 44.82], [-75.55, 44.63], [-75.90, 44.46], [-76.20, 44.29], [-76.50, 44.19], [-76.80, 44.12]], 13.0],
]
const CHANNELS := {
	"Strait of Gibraltar": [[-6.2, 35.95], [-5.6, 35.97], [-5.2, 36.0]],
	"Dardanelles": [[26.15, 40.00], [26.27, 40.07], [26.40, 40.15], [26.45, 40.22], [26.55, 40.30], [26.68, 40.41], [26.80, 40.48]],
	"Strait of Messina": [[15.68, 38.31], [15.66, 38.25], [15.62, 38.18], [15.60, 38.10], [15.57, 38.00]],
	"Strait of Bonifacio": [[9.0, 41.33], [9.25, 41.32], [9.5, 41.30]],
	"Singapore Strait": [[103.5, 1.20], [103.8, 1.20], [104.1, 1.25], [104.4, 1.30]],
	"Great Belt": [[11.0, 56.10], [10.95, 55.70], [11.0, 55.35], [11.05, 55.05], [11.2, 54.70], [11.5, 54.55]],
	"Oresund (Copenhagen)": [[12.55, 56.15], [12.62, 56.04], [12.68, 55.96], [12.72, 55.86], [12.70, 55.76], [12.68, 55.68], [12.72, 55.58], [12.80, 55.48], [12.85, 55.38]],
	"Elbe (Hamburg)": [[8.3, 53.95], [8.7, 53.88], [9.0, 53.85], [9.35, 53.72], [9.55, 53.60], [9.8, 53.54], [9.95, 53.54]],
	"Western Scheldt (Antwerp)": [[3.3, 51.45], [3.6, 51.42], [3.9, 51.40], [4.1, 51.38], [4.25, 51.33], [4.33, 51.28]],
	"The Narrows (New York)": [[-74.05, 40.66], [-74.045, 40.63], [-74.04, 40.605], [-74.03, 40.58], [-74.00, 40.53]],
	"Savannah River": [[-80.80, 32.02], [-80.95, 32.05], [-81.10, 32.08]],
	"Galveston Bay (Houston)": [[-94.65, 29.30], [-94.75, 29.36], [-94.85, 29.45], [-94.95, 29.55], [-94.98, 29.60]],
	"Golden Gate (Oakland)": [[-122.65, 37.78], [-122.50, 37.81], [-122.40, 37.81], [-122.32, 37.80]],
	"Admiralty Inlet (Seattle)": [[-122.75, 48.20], [-122.65, 48.05], [-122.50, 47.85], [-122.40, 47.65], [-122.35, 47.60]],
	"Port Phillip Heads (Melbourne)": [[144.60, -38.32], [144.64, -38.28], [144.75, -38.15], [144.90, -37.90]],
	"Santos channel": [[-46.30, -24.05], [-46.30, -23.98]],
	"Paranagua Bay": [[-48.30, -25.57], [-48.40, -25.52], [-48.52, -25.50]],
	"Lagos harbor": [[3.40, 6.35], [3.39, 6.44]],
	"Vridi Canal (Abidjan)": [[-4.02, 5.20], [-4.00, 5.25]],
	"Kilindini (Mombasa)": [[39.70, -4.10], [39.67, -4.05]],
	"Durban harbor": [[31.10, -29.88], [31.03, -29.87]],
	"Bosphorus (Black Sea)": [[28.98, 41.00], [29.01, 41.04], [29.04, 41.08], [29.06, 41.12], [29.08, 41.17], [29.12, 41.22], [29.15, 41.26], [29.20, 41.30]],
	"Mississippi River (New Orleans)": [[-89.42, 28.93], [-89.33, 29.05], [-89.30, 29.15], [-89.38, 29.28], [-89.55, 29.40], [-89.70, 29.50], [-89.85, 29.65], [-89.98, 29.82], [-90.05, 29.95]],
	"Icy Strait to Juneau": [[-136.60, 58.18], [-136.10, 58.25], [-135.60, 58.27], [-135.00, 58.35], [-134.75, 58.30], [-134.55, 58.28], [-134.42, 58.30]],
	"Oslofjord": [[10.55, 59.00], [10.58, 59.30], [10.60, 59.50], [10.62, 59.66], [10.68, 59.80], [10.74, 59.90]],
	"Columbia River (Portland, Oregon)": [[-124.10, 46.24], [-123.90, 46.20], [-123.65, 46.22], [-123.40, 46.20], [-123.20, 46.15], [-123.05, 46.10], [-122.90, 45.95], [-122.82, 45.80], [-122.77, 45.63], [-122.73, 45.56]],
	"Strait of Magellan (Punta Arenas)": [[-68.35, -52.40], [-68.80, -52.45], [-69.30, -52.52], [-69.65, -52.60], [-70.10, -52.80], [-70.50, -53.00], [-70.90, -53.16]],
	"St. Lawrence River (estuary to Lake Ontario)": [[-69.30, 48.05], [-69.55, 47.88], [-69.80, 47.70], [-70.10, 47.45], [-70.40, 47.25], [-70.70, 47.05], [-70.95, 46.92], [-71.20, 46.81], [-71.45, 46.70], [-71.75, 46.62], [-72.05, 46.47], [-72.35, 46.37], [-72.55, 46.33], [-72.80, 46.22], [-73.05, 46.08], [-73.20, 45.90], [-73.40, 45.72], [-73.52, 45.55], [-73.65, 45.43], [-73.85, 45.38], [-74.05, 45.30], [-74.35, 45.15], [-74.70, 45.02], [-75.00, 44.92], [-75.30, 44.80], [-75.55, 44.66], [-75.80, 44.50], [-76.05, 44.33], [-76.30, 44.22], [-76.50, 44.15]],
	"Welland Canal (Lake Ontario to Lake Erie)": [[-79.22, 43.27], [-79.21, 43.15], [-79.23, 43.00], [-79.25, 42.87]],
	"Detroit and St. Clair rivers (Lake Erie to Lake Huron)": [[-83.12, 41.98], [-83.12, 42.10], [-83.10, 42.25], [-83.00, 42.33], [-82.90, 42.36], [-82.75, 42.45], [-82.60, 42.55], [-82.52, 42.62], [-82.47, 42.78], [-82.42, 42.95], [-82.42, 43.08]],
	"St. Marys River (Lake Huron to Lake Superior)": [[-83.75, 45.98], [-83.95, 46.05], [-84.10, 46.18], [-84.20, 46.35], [-84.30, 46.48], [-84.38, 46.50], [-84.55, 46.50], [-84.70, 46.55]],
	"Straits of Mackinac (Lake Michigan to Lake Huron)": [[-85.10, 45.80], [-84.73, 45.82], [-84.40, 45.90]],
	"Yenisei River (Dudinka)": [[80.60, 73.30], [81.60, 72.60], [82.40, 71.90], [82.90, 71.20], [83.30, 70.60], [83.80, 70.10], [84.60, 69.75], [85.60, 69.50], [86.18, 69.40]],
}

var _cols := 0
var _rows := 0
var _grid_origin := Vector2.ZERO  # Projected coords of cell (0, 0)'s corner.
var _land := PackedByteArray()  # 1 = land
var _near_land := PackedByteArray()  # 1 = land or next to land
## The first grid row (a whole coarse cell) north of ARCTIC_LAT, and whether
## those rows count as land (while routing lanes between non-Arctic ports).
var _arctic_row := 0
var _block_arctic := false
## 1 = water connected to the open ocean. Ports snap to these cells, so every
## pair of ports has a route (and no search is wasted on an enclosed pocket).
var _ocean := PackedByteArray()
## Per fine cell, the coarse graph piece of water it's in (-1 if not ocean; see
## _build_coarse_graph()), and per piece, the fine cell routes pass through and
## its coarse cell.
var _fine_piece := PackedInt32Array()
var _piece_rep := PackedInt32Array()
var _piece_cell := PackedInt32Array()
## Each canal from data/canals.json: {path (its centerline), divide}, as [lon, lat] points.
var _canals: Array[Dictionary] = []


func _init() -> void:
	var started := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	for canal: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(CANALS_PATH)).canals:
		var path := _to_points(canal.path)
		var bounds := Rect2(path[0], Vector2.ZERO)
		for p in path:
			bounds = bounds.expand(p)
		_canals.append({path = path, divide = _to_points(canal.divide), bounds = bounds.grow(0.01)})
	if "--canals-only" in args:
		_resplice_lanes()
		quit()
		return
	if "--fishing-only" in args:
		_plan_fishing_lanes()
		quit()
		return
	if "--currents-only" in args:
		_plan_current_ways()
		quit()
		return
	if "--channels-only" in args:
		_rechannel_lanes()
		print("Done in %.1f min" % ((Time.get_ticks_msec() - started) / 60000.0))
		quit()
		return
	if "--animals-only" in args:
		_replace_animals("--nudge" in args)
		quit()
		return
	if "--decor-only" in args:
		_rebuild_decor()
		quit()
		return
	if "--biomes-only" in args:
		_rebuild_biomes("--dry" in args)
		quit()
		return
	var land_rings := _read_land_rings()
	print("Land: %d rings" % land_rings.size())
	if not "--lanes-only" in args:
		_build_map(land_rings)
	if not "--map-only" in args:
		_build_grid(land_rings)
		land_rings.clear()
		if "--audit" in args:
			_audit_lanes()
		else:
			_build_lanes()
	print("Done in %.1f min" % ((Time.get_ticks_msec() - started) / 60000.0))
	quit()


# --- Source data ---------------------------------------------------------


func _read_geojson(path: String) -> Array:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(typeof(data) == TYPE_DICTIONARY, "Can't read %s" % path)
	return data.features


## Each feature's polygons as arrays of rings; ring 0 is the outline, the rest are holes.
func _feature_polygons(feature: Dictionary) -> Array:
	var geometry: Dictionary = feature.geometry
	if geometry.type == "Polygon":
		return [geometry.coordinates]
	return geometry.coordinates


## Land polygons as {outline, holes} in lon/lat.
func _read_land_rings() -> Array:
	var polygons := []
	for feature: Dictionary in _read_geojson(LAND_PATH):
		if feature.properties.get("featurecla", "") != "Land":
			continue
		for polygon: Array in _feature_polygons(feature):
			var holes := []
			for i in range(1, polygon.size()):
				holes.append(_to_points(polygon[i]))
			polygons.append({"outline": _to_points(polygon[0]), "holes": holes})
	# _dredge(polygons) is off: the cut Eurasia polygon lost its land north of about 46 N in the
	# tiled triangulation (Germany, France, Quebec drew as water). The straits are widened
	# instead by moving their shores (_widen()); the DREDGES still carve the lanes' grid (see _build_grid()).
	return _widen(polygons)


## Widens the DREDGES in the land outlines (lon, lat) without cutting them:
## every outline (or hole) vertex within half a dredge's width of its course
## is pushed out, square to the course, to that distance (in the map's
## projection), so the drawn coast, the sea grid and the lanes agree on an
## open passage. The outlines keep their points' order and winding, so the
## triangulation is untouched (see _dredge()). Only a strait the data already
## has open gets wider: where there's no shore point, nothing is pushed.
func _widen(polygons: Array) -> Array:
	for dredge: Array in DREDGES:
		var course := _project_all(_to_points(dredge[1]))
		var lat := 0.0
		for p: Array in dredge[1]:
			lat += float(p[1]) / (dredge[1] as Array).size()
		var radius := float(dredge[2]) / 60.0 / 2.0 / maxf(cos(deg_to_rad(lat)), 0.1)
		var box := Rect2(course[0], Vector2.ZERO)
		for p in course:
			box = box.expand(p)
		box = box.grow(radius * 1.5)
		var pushed := 0
		for polygon: Dictionary in polygons:
			var rings: Array = [polygon.outline] + polygon.holes
			for r in rings.size():
				var ring: PackedVector2Array = rings[r]
				var changed := false
				for i in ring.size():
					var p := Geo.project(ring[i])
					if not box.has_point(p):
						continue
					var nearest := Vector2.INF
					var best := INF
					for k in range(1, course.size()):
						var q := Geometry2D.get_closest_point_to_segment(p, course[k - 1], course[k])
						var d := q.distance_to(p)
						if d < best:
							best = d
							nearest = q
					if best >= radius or best < 0.000001:
						continue
					ring[i] = Geo.unproject(nearest + (p - nearest) / best * radius)
					changed = true
					pushed += 1
				if changed:
					if r == 0:
						polygon.outline = ring
					else:
						polygon.holes[r - 1] = ring
		print("%s widened to %.0f nm: %d shore points moved" % [dredge[0], float(dredge[2]), pushed])
	return polygons


## Cuts the DREDGES out of the land polygons (lon, lat): each course buffered
## to its width (round ends) in the map's projection, clipped out of every
## outline it meets; an outline cut in two becomes two polygons, each
## keeping the holes inside it.
func _dredge(polygons: Array) -> Array:
	for dredge: Array in DREDGES:
		var course := _project_all(_to_points(dredge[1]))
		var lat := 0.0
		for p: Array in dredge[1]:
			lat += float(p[1]) / (dredge[1] as Array).size()
		var radius := float(dredge[2]) / 60.0 / 2.0 / maxf(cos(deg_to_rad(lat)), 0.1)
		var corridors := Geometry2D.offset_polyline(course, radius, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		var box := Rect2(course[0], Vector2.ZERO)
		for p in course:
			box = box.expand(p)
		box = box.grow(radius * 2.0)
		var out := []
		var cut := 0
		for polygon: Dictionary in polygons:
			var outline := _project_all(polygon.outline)
			var touches := false
			for p in outline:
				if box.has_point(p):
					touches = true
					break
			if not touches:
				out.append(polygon)
				continue
			var pieces := [outline]
			for corridor: PackedVector2Array in corridors:
				var next := []
				for piece: PackedVector2Array in pieces:
					next.append_array(Geometry2D.clip_polygons(piece, corridor))
				pieces = next
			# The clipper winds its output its own way (outers one way, holes the
			# other, whatever the input): the biggest piece is an outer, and every
			# piece wound like it is too.
			var outers := []
			var inners := []
			var biggest := PackedVector2Array()
			var biggest_area := -1.0
			for piece: PackedVector2Array in pieces:
				if piece.size() < 3:
					continue
				var area := _bounds(piece).get_area()
				if area > biggest_area:
					biggest_area = area
					biggest = piece
			var outer_wound := Geometry2D.is_polygon_clockwise(biggest) if not biggest.is_empty() else false
			for piece: PackedVector2Array in pieces:
				if piece.size() < 3:
					continue
				if Geometry2D.is_polygon_clockwise(piece) == outer_wound:
					outers.append(piece)
				else:
					inners.append(piece)
			if outers.size() == 1 and inners.is_empty() and outers[0].size() == outline.size():
				out.append(polygon)
				continue
			cut += 1
			for outer: PackedVector2Array in outers:
				var holes := []
				for hole: PackedVector2Array in polygon.holes:
					if Geometry2D.is_point_in_polygon(Geo.project(hole[0]), outer):
						holes.append(hole)
				for inner: PackedVector2Array in inners:
					if Geometry2D.is_point_in_polygon(inner[0], outer):
						holes.append(_unproject_all(inner))
				out.append({"outline": _unproject_all(outer), "holes": holes})
		print("Dredged %s: %d land polygons cut" % [dredge[0], cut])
		polygons = out
	return polygons


func _unproject_all(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = Geo.unproject(points[i])
	return out


func _to_points(ring: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for coord: Array in ring:
		points.append(Vector2(coord[0], coord[1]))
	if points.size() > 1 and points[0] == points[-1]:
		points.remove_at(points.size() - 1)
	return points


func _project_all(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = Geo.project(points[i])
	return out


# --- Map art -------------------------------------------------------------

func _build_map(land_polygons: Array) -> void:
	var map := WorldMapData.new()
	for polygon: Dictionary in land_polygons:
		var outline := _simplify(_project_all(polygon.outline))
		if outline.size() < 3:
			continue
		_add_coast(map, outline)
		_triangulate_tiled(outline, map.land_triangles, map.water_triangles)
		for hole: PackedVector2Array in polygon.holes:
			var hole_points := _simplify(_project_all(hole))
			if hole_points.size() >= 3:
				_add_coast(map, hole_points)
				_triangulate_tiled(hole_points, map.water_triangles, map.land_triangles)
	print("Map: %d land triangles, %d coast segments" % [map.land_triangles.size() / 3, map.coast_segments.size() / 2])

	_add_lakes(map)
	_add_rivers(map)
	_add_countries(map)
	_add_depths(map)
	_add_feature_labels(map)
	var biomes := _build_biomes()
	_build_land_texture(biomes)
	_add_decor(map, biomes)
	_drop_wet_decor(map)
	_add_sea_mask(map, biomes)
	_add_biome_polygons(map, biomes)
	_add_decor_clearance(map)
	_plant_mangroves(map)
	# Split small enough to curve round the globe (the map is drawn on one).
	Geo.tessellate_map(map)
	var err := ResourceSaver.save(map, MAP_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % MAP_OUT)


## The animals (ANIMALS) again, into the existing map's land drawings (see
## --animals-only): they're its first drawings, in order; any after them that
## were animals once (in the map, not in ANIMALS any more) go. Then every
## drawing's clearance again. With nudge, an animal too near the water to show
## (less than ANIMAL_ROOM of real distance from it) is walked inland, away
## from the nearest shore, till it has that room, and the spot is printed to
## go into ANIMALS (the map gets it too).
func _replace_animals(nudge: bool) -> void:
	var map: WorldMapData = load(MAP_OUT)
	var count := ANIMALS.size()
	for k in count:
		assert(map.decor_kind_names[map.decor_kinds[k]] == ANIMALS[k][0], "Drawing %d isn't a %s" % [k, ANIMALS[k][0]])
		map.decor_positions[k] = Geo.project(Vector2(ANIMALS[k][1], ANIMALS[k][2]))
		map.decor_tiers[k] = int(ANIMALS[k][3])
	var animal_names := {}
	for animal: Array in ANIMALS:
		animal_names[animal[0]] = true
	var plants := ["acacia", "baobab", "birch", "cactus", "cherry", "conifer", "cypress", "deciduous", "dunes", "grass", "mangrove", "mountain", "mountain_b", "mountain_c", "mountain_snow", "mountain_snow_b", "mountain_snow_c", "oak", "palm", "rainforest", "red_rock", "shrub", "waves"]
	while count < map.decor_positions.size() and not plants.has(map.decor_kind_names[map.decor_kinds[count]]) and not animal_names.has(map.decor_kind_names[map.decor_kinds[count]]):
		print("  Dropped a %s" % map.decor_kind_names[map.decor_kinds[count]])
		map.decor_positions.remove_at(count)
		map.decor_kinds.remove_at(count)
		map.decor_tiers.remove_at(count)
	_add_decor_clearance(map)
	if nudge:
		var shores := map.coast_segments.duplicate()
		for triangles in map.lake_triangles:
			shores.append_array(_outline_edges(triangles))
		for k in ANIMALS.size():
			var p := map.decor_positions[k]
			var want := ANIMAL_ROOM * cosh(deg_to_rad(p.y))  # (Projected degrees shrink on the globe away from the equator.)
			if map.decor_clearance[k] >= want:
				continue
			var start := p
			for step in 80:
				var nearest := _nearest_on(shores, p)
				var room := nearest.distance_to(p)
				if room >= want:
					break
				p += (p - nearest).normalized() * 0.05 * cosh(deg_to_rad(p.y))
			map.decor_positions[k] = p
			var at := Geo.unproject(p)
			print("  %s at (%s, %s): to (%.2f, %.2f)" % [ANIMALS[k][0], ANIMALS[k][1], ANIMALS[k][2], at.x, at.y])
		_add_decor_clearance(map)
	var err := ResourceSaver.save(map, MAP_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % MAP_OUT)


## The nearest point to p on any of the shore segments (pairs of points).
static func _nearest_on(shores: PackedVector2Array, p: Vector2) -> Vector2:
	var best := Vector2.INF
	for i in range(0, shores.size(), 2):
		var a := shores[i]
		var b := shores[i + 1]
		if absf(a.x - p.x) > 4.0 or absf(a.y - p.y) > 8.0:
			continue
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		if q.distance_squared_to(p) < best.distance_squared_to(p):
			best = q
	return best


## The biome patches again, into the existing map (see --biomes-only); dry, only
## counting their outlines' points.
func _rebuild_biomes(dry: bool) -> void:
	var map: WorldMapData = load(MAP_OUT)
	map.biome_triangles = PackedVector2Array()
	map.biome_colors = PackedColorArray()
	_add_biome_polygons(map, _build_biomes())
	if dry:
		return
	var biomes := Geo.tessellate(map.biome_triangles, map.biome_colors)
	map.biome_triangles = biomes[0]
	map.biome_colors = biomes[1]
	var err := ResourceSaver.save(map, MAP_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % MAP_OUT)


## Sea depth bands from Natural Earth's bathymetry (DEPTH_BANDS): each band's
## sea as triangles, and the shallower patches inside it as its holes.
func _add_depths(map: WorldMapData) -> void:
	for band: Array in DEPTH_BANDS:
		var triangles := PackedVector2Array()
		var holes := PackedVector2Array()
		for feature: Dictionary in _read_geojson(DEPTHS_PATH % band[1]):
			for polygon: Array in _feature_polygons(feature):
				for i in polygon.size():
					var ring := _simplify(_project_all(_to_points(polygon[i])), DEPTH_SIMPLIFY_TOLERANCE)
					if ring.size() < 3:
						continue
					if i == 0:
						_triangulate_tiled(ring, triangles, holes)
					else:
						_triangulate_tiled(ring, holes, triangles)
		map.depth_levels.append(band[0])
		map.depth_triangles.append(triangles)
		map.depth_hole_triangles.append(holes)
		print("  Depth %d m: %d triangles, %d in shallower patches" % [band[0], triangles.size() / 3, holes.size() / 3])


## Labels for named geography: oceans, seas (with gulfs, bays and sounds),
## straits (with channels), mountain ranges, deserts, lakes and rivers, each
## with Natural Earth's min_label (the web-map zoom it's labeled from). Areas
## are labeled at the point furthest inside their biggest part; a river on the
## middle of its longest named stretch.
func _add_feature_labels(map: WorldMapData) -> void:
	var count := map.feature_label_names.size()
	for feature: Dictionary in _read_geojson(MARINE_PATH):
		var props: Dictionary = feature.properties
		var kind: Variant = MARINE_KINDS.get(str(props.get("featurecla", "")))
		if kind != null and props.get("name") != null:
			var text := str(props.get("label")) if kind == 0 and props.get("label") != null else str(props.name)
			_add_area_label(map, feature, text, kind, float(props.get("min_label", 5.0)))
	for feature: Dictionary in _read_geojson(REGIONS_PATH):
		var props: Dictionary = feature.properties
		var kind: Variant = REGION_KINDS.get(str(props.get("FEATURECLA", "")))
		if kind == REGION_KINDS["Range/mtn"] and not _range_kept(str(props.get("NAME", ""))):
			continue
		if kind != null and props.get("NAME") != null:
			_add_area_label(map, feature, str(props.NAME).to_upper(), kind, float(props.get("MIN_LABEL", 5.0)))
	for feature: Dictionary in _read_geojson(LAKES_PATH):
		var props: Dictionary = feature.properties
		if props.get("name") != null:
			_add_area_label(map, feature, str(props.name), LAKE_KIND, float(props.get("min_label", 7.0)))
	# A river is many stretches; label it once, on its longest.
	var rivers := {}  # name -> [longest stretch's points, its length, lowest min_label]
	for feature: Dictionary in _read_geojson(RIVERS_PATH):
		var props: Dictionary = feature.properties
		if props.get("name") == null or str(props.get("featurecla", "")) == "Lake Centerline":
			continue
		var geometry: Dictionary = feature.geometry
		var lines: Array = [geometry.coordinates] if geometry.type == "LineString" else geometry.coordinates
		for line: Array in lines:
			var points := _project_all(_to_points(line))
			var length := 0.0
			for k in range(1, points.size()):
				length += points[k - 1].distance_to(points[k])
			var entry: Array = rivers.get(props.name, [PackedVector2Array(), 0.0, INF])
			if length > entry[1]:
				entry[0] = points
				entry[1] = length
			entry[2] = minf(entry[2], float(props.get("min_label", 7.0)))
			rivers[props.name] = entry
	for river_name: String in rivers:
		var entry: Array = rivers[river_name]
		_add_label(map, river_name, _point_along(entry[0], entry[1] / 2.0), RIVER_KIND, entry[2])
	print("Feature labels: %d" % (map.feature_label_names.size() - count))


func _add_label(map: WorldMapData, text: String, position: Vector2, kind: int, min_zoom: float) -> void:
	map.feature_label_names.append(text)
	map.feature_label_positions.append(position)
	map.feature_label_kinds.append(kind)
	map.feature_label_min_zoom.append(min_zoom)


## Labels a feature's biggest polygon (by its bounding box) at the point
## furthest inside it.
func _add_area_label(map: WorldMapData, feature: Dictionary, text: String, kind: int, min_zoom: float) -> void:
	var best_rings := []
	var best_area := -1.0
	for polygon: Array in _feature_polygons(feature):
		var rings := []
		for ring: Array in polygon:
			var points := _simplify(_project_all(_to_points(ring)), DEPTH_SIMPLIFY_TOLERANCE)
			if points.size() >= 3:
				rings.append(points)
		if rings.is_empty():
			continue
		var area := _bounds(rings[0]).get_area()
		if area > best_area:
			best_area = area
			best_rings = rings
	if not best_rings.is_empty():
		_add_label(map, text, _inside_point(best_rings), kind, min_zoom)


## Roughly the point inside a polygon (outline, then holes) furthest from its
## edges: the best of a grid over it, then of finer grids around the best so far.
func _inside_point(rings: Array) -> Vector2:
	var box := _bounds(rings[0])
	var best := box.get_center()
	var best_room := -1.0
	var step := maxf(box.size.x, box.size.y) / LABEL_GRID
	var center := box.get_center()
	@warning_ignore("integer_division")
	var half := LABEL_GRID / 2
	for pass_index in LABEL_REFINE_ROUNDS:
		for gy in range(-half, half + 1):
			for gx in range(-half, half + 1):
				var p := center + Vector2(gx, gy) * step
				var room := _room_at(rings, p)
				if room > best_room:
					best_room = room
					best = p
		center = best
		step /= 4.0
	return best


## How far a point is from a polygon's nearest edge, or -1 if it's outside.
static func _room_at(rings: Array, p: Vector2) -> float:
	if not Geometry2D.is_point_in_polygon(p, rings[0]):
		return -1.0
	for h in range(1, rings.size()):
		if Geometry2D.is_point_in_polygon(p, rings[h]):
			return -1.0
	var room := INF
	for ring: PackedVector2Array in rings:
		for k in ring.size():
			room = minf(room, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ring[k - 1], ring[k])))
	return room


static func _bounds(points: PackedVector2Array) -> Rect2:
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	return box


## The point `distance` along a line.
static func _point_along(points: PackedVector2Array, distance: float) -> Vector2:
	for k in range(1, points.size()):
		var piece := points[k - 1].distance_to(points[k])
		if distance <= piece:
			return points[k - 1].lerp(points[k], distance / piece)
		distance -= piece
	return points[-1]


## Each biome (BIOME_*) of the simplified land: its flat color.
const BIOME_COLORS: Array[Color] = [
	Color("#eef3f8"),  # Ice
	Color("#c3c9b0"),  # Tundra (and cold high plateaus)
	Color("#4f8a5c"),  # Boreal forest
	Color("#78ad62"),  # Temperate forest
	Color("#3d9150"),  # Tropical rainforest
	Color("#b4cf7a"),  # Grassland and steppe
	Color("#d8c776"),  # Savanna and dry scrub
	Color("#ecd49a"),  # Desert
]
enum { BIOME_ICE, BIOME_TUNDRA, BIOME_BOREAL, BIOME_TEMPERATE, BIOME_RAINFOREST, BIOME_GRASSLAND, BIOME_SAVANNA, BIOME_DESERT }
const BIOME_SEA := 255
## The biome grid, in plain longitude/latitude (a quarter degree a cell).
const BIOME_COLS := 1440
const BIOME_ROWS := 720
## How many times finer than the biome grid its edges are smoothed (see
## _build_land_texture()).
const BIOME_EDGE_UPSCALE := 3
## The biome polygons (_add_biome_polygons()): how far (projected degrees)
## their outlines may stray from the cell edges when straightened, and the
## smallest patch kept (projected square degrees).
const BIOME_SIMPLIFY := 0.18
const BIOME_MIN_AREA := 0.12
## Drawings' distance to the shore is looked for this far (projected degrees), in
## buckets this size.
const DECOR_CLEARANCE_MAX := 3.0
## How far (real degrees) an animal's spot should be from the water so it
## shows from mid zoom in (see --animals-only --nudge): a little more than its size on
## screen at 50 px a degree.
const ANIMAL_ROOM := 0.9
const CLEARANCE_BUCKET := 0.5


## The land as biomes (BIOME_*, BIOME_SEA for sea), a BIOME_COLS x BIOME_ROWS
## grid in plain longitude/latitude from the north. Each cell is classified from
## Natural Earth II's color (its land cover) and latitude: very bright blue-white
## is ice; gray is tundra (and cold high plateaus like Tibet); dark and green is
## forest (rainforest in the tropics, boreal north of BOREAL_LAT, else
## temperate); pale but green is grassland (savanna in the tropics); and barely
## green is desert. Then a few majority passes smooth it into simple patches,
## with cells along the coast (whose color the sea washes out) taking their
## neighbors' biome.
func _build_biomes() -> PackedByteArray:
	var source := Image.load_from_file(LAND_COLORS_PATH)
	source.convert(Image.FORMAT_RGB8)
	var mask := source.duplicate() as Image
	mask.resize(BIOME_COLS, BIOME_ROWS, Image.INTERPOLATE_NEAREST)
	source.resize(BIOME_COLS, BIOME_ROWS, Image.INTERPOLATE_CUBIC)
	var colors := source.get_data()
	var sea_colors := mask.get_data()
	var sea_r := LAND_COLORS_SEA.r8
	var cells := BIOME_COLS * BIOME_ROWS
	var biomes := PackedByteArray()
	biomes.resize(cells)
	var coastal := PackedByteArray()
	coastal.resize(cells)
	for i in cells:
		if sea_colors[i * 3] == sea_r and sea_colors[i * 3 + 1] == sea_r and sea_colors[i * 3 + 2] == sea_r:
			biomes[i] = BIOME_SEA
			continue
		var lat := 90.0 - (floorf(float(i) / BIOME_COLS) + 0.5) * 180.0 / BIOME_ROWS
		var lon := (float(i % BIOME_COLS) + 0.5) * 360.0 / BIOME_COLS - 180.0
		biomes[i] = _biome(colors[i * 3], colors[i * 3 + 1], colors[i * 3 + 2], lat + _lat_wobble(lon))
	for i in cells:
		if biomes[i] != BIOME_SEA:
			for n in _biome_neighbors(i):
				if biomes[n] == BIOME_SEA:
					coastal[i] = 1
					break
	for radius: int in BIOME_SMOOTHING_RADII:
		var next := biomes.duplicate()
		for i in cells:
			if biomes[i] == BIOME_SEA:
				continue
			var votes := PackedInt32Array()
			votes.resize(8)
			votes[biomes[i]] += 0 if coastal[i] else 2
			for n in _biome_neighbors(i, radius):
				if biomes[n] != BIOME_SEA and not coastal[n]:
					votes[biomes[n]] += 1
			var best := biomes[i]
			for b in 8:
				if votes[b] > votes[best]:
					best = b
			next[i] = best
		biomes = next
		coastal.fill(0)  # After a pass the coast has taken its neighbors' biomes.
	return biomes


## How far (degrees) the latitude lines between biomes (the tropics, the
## boreal forest, the tundra) are pushed north or south at a longitude: a few
## smooth waves, so they wander like real climate boundaries.
static func _lat_wobble(lon: float) -> float:
	var x := deg_to_rad(lon)
	return 2.5 * sin(x * 11.0 + 0.7) + 1.6 * sin(x * 23.0 + 2.1) + 0.9 * sin(x * 47.0 + 4.0)


## A biome from a Natural Earth II color (0-255) and latitude (see
## _build_biomes()); the latitude is wobbled (see _lat_wobble()) so the climate
## lines between biomes wander rather than run dead straight.
static func _biome(r: int, g: int, b: int, lat: float) -> int:
	var bright := r + g + b
	var green := g - (r + b) / 2.0
	if b >= r + 4 and bright > 680:
		return BIOME_ICE
	if green >= 22.0 and bright < 570:
		if absf(lat) < 23.5:
			return BIOME_RAINFOREST
		return BIOME_BOREAL if lat > BOREAL_LAT else BIOME_TEMPERATE
	if maxi(r, maxi(g, b)) - mini(r, mini(g, b)) < 12 or lat > TUNDRA_LAT:
		return BIOME_TUNDRA
	if green < 11.0:
		return BIOME_DESERT
	return BIOME_SAVANNA if absf(lat) < 24.0 else BIOME_GRASSLAND


## The cells within radius of a biome cell (not wrapping at the top and
## bottom; wrapping east-west).
static func _biome_neighbors(i: int, radius := 1) -> PackedInt32Array:
	@warning_ignore("integer_division")
	var row := i / BIOME_COLS
	var col := i % BIOME_COLS
	var out := PackedInt32Array()
	for dy in range(-radius, radius + 1):
		var r: int = row + dy
		if r < 0 or r >= BIOME_ROWS:
			continue
		for dx in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			out.append(r * BIOME_COLS + posmod(col + dx, BIOME_COLS))
	return out


## Drawings on the land for the map (art/decor), each a fixed size in the
## world (MapView DECOR_KM): first the animals (ANIMALS) where they live (the
## wildlife's home ranges: see Wildlife), then the mountains along the real
## ranges (MOUNTAIN_SPACING apart, overlapping into ridges; snow-capped in cold
## places and on the great snowy ranges, SNOWY_RANGES), then the land's cover
## by biome on a grid VEGETATION_SPACING apart (in real degrees, so it's as
## dense near the poles as at the equator), jittered: dense stands of trees in
## the forests, scattered grass, acacias and scrub on grassland, savanna and
## tundra, and cacti, red rock or dunes in the deserts (see
## _decor_for_biome()); kept only on land outside the big lakes. Each gets a
## tier 0-3 at random: zoomed out, where they'd be tiny, the map thins them
## out by it. Then waves on the rough polar seas.
func _add_decor(map: WorldMapData, biomes: PackedByteArray) -> void:
	var ranges := []  # [bounds, polygon (lon/lat outline), snowy]
	for feature: Dictionary in _read_geojson(REGIONS_PATH):
		if str(feature.properties.get("FEATURECLA", "")) != "Range/mtn" or not _range_kept(str(feature.properties.get("NAME", ""))):
			continue
		var snowy := SNOWY_RANGES.has(str(feature.properties.get("NAME", "")).to_upper())
		for polygon: Array in _feature_polygons(feature):
			var outline := _to_points(polygon[0])
			ranges.append([_bounds(outline), outline, snowy])
	var lakes := []
	for feature: Dictionary in _read_geojson(LAKES_PATH):
		if float(feature.properties.get("scalerank", 99)) > 2.0:
			continue
		for polygon: Array in _feature_polygons(feature):
			var outline := _to_points(polygon[0])
			lakes.append([_bounds(outline), outline])
	var kinds := {}  # Name -> index in map.decor_kind_names.
	var add := func(name: String, lon_lat: Vector2, tier: int) -> void:
		if not kinds.has(name):
			kinds[name] = map.decor_kind_names.size()
			map.decor_kind_names.append(name)
		map.decor_positions.append(Geo.project(lon_lat))
		map.decor_kinds.append(kinds[name])
		map.decor_tiers.append(tier)
	map.decor_tier_spacing = PackedFloat32Array([VEGETATION_SPACING])
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	for animal: Array in ANIMALS:
		add.call(animal[0], Vector2(animal[1], animal[2]), int(animal[3]))
	# The mountains, along the ranges.
	var lat := -60.0
	while lat < 80.0:
		var step := MOUNTAIN_SPACING / maxf(cos(deg_to_rad(lat)), 0.15)
		var lon := -180.0
		while lon < 180.0:
			var spot := Vector2(lon, lat) + Vector2(rng.randf_range(-0.35, 0.35) * step, rng.randf_range(-0.35, 0.35) * MOUNTAIN_SPACING)
			lon += step
			var range_item := _range_at(ranges, spot)
			if range_item.is_empty() or rng.randf() > 0.92:
				continue
			var biome := _biome_at(biomes, spot)
			if biome == BIOME_SEA or _in_any(lakes, spot):
				continue
			var snow: bool = range_item[2] or absf(spot.y) > 42.0 or biome == BIOME_ICE or biome == BIOME_TUNDRA
			add.call(("mountain_snow" if snow else "mountain") + ["", "_b", "_c"][rng.randi() % 3], spot, rng.randi() % 4)
		lat += MOUNTAIN_SPACING
	# The land's cover.
	lat = -60.0
	while lat < 80.0:
		var step := VEGETATION_SPACING / maxf(cos(deg_to_rad(lat)), 0.15)
		var lon := -180.0
		while lon < 180.0:
			var spot := Vector2(lon, lat) + Vector2(rng.randf_range(-0.45, 0.45) * step, rng.randf_range(-0.45, 0.45) * VEGETATION_SPACING)
			lon += step
			var biome := _biome_at(biomes, spot)
			if biome == BIOME_SEA or biome == BIOME_ICE or _in_any(lakes, spot):
				continue
			if not _range_at(ranges, spot).is_empty() and rng.randf() < 0.8:
				continue  # The mountains have it.
			var kind := _decor_for_biome(biome, spot, rng)
			if not kind.is_empty():
				add.call(kind, spot, rng.randi() % 4)
		lat += VEGETATION_SPACING
	_add_polar_waves(map, biomes, add)
	print("Decor: %d drawings of %d kinds" % [map.decor_positions.size(), map.decor_kind_names.size()])


## Whether a Natural Earth range gets mountains and a label (see DROPPED_RANGES).
static func _range_kept(name: String) -> bool:
	return not DROPPED_RANGES.has(name.strip_edges().to_upper())


## The range ([bounds, outline, snowy]) a (lon, lat) is in, or [].
static func _range_at(ranges: Array, lon_lat: Vector2) -> Array:
	for item: Array in ranges:
		if (item[0] as Rect2).has_point(lon_lat) and Geometry2D.is_point_in_polygon(lon_lat, item[1]):
			return item
	return []


## Waves on the sea beyond WAVES_LAT north and south (the rough polar waters),
## WAVES_SPACING apart (in real degrees), at WAVES_CHANCE of the spots.
func _add_polar_waves(_map: WorldMapData, biomes: PackedByteArray, add: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261006
	for band: Vector2 in [Vector2(WAVES_LAT, 80.0), Vector2(-80.0, -WAVES_LAT)]:
		var lat := band.x
		while lat < band.y:
			var step := WAVES_SPACING / maxf(cos(deg_to_rad(lat)), 0.15)
			var lon := -180.0
			while lon < 180.0:
				var spot := Vector2(lon, lat) + Vector2(rng.randf_range(-0.4, 0.4) * step, rng.randf_range(-0.4, 0.4) * WAVES_SPACING)
				lon += step
				if rng.randf() < WAVES_CHANCE and _biome_at(biomes, spot) == BIOME_SEA:
					add.call("waves", spot, rng.randi() % 4)
			lat += WAVES_SPACING


## The drawing for a spot in a biome (or "" for none): a stand of conifers
## (and birches) in the boreal forest, of round trees, oaks and some conifers
## and birches in temperate forests (cherry trees in Japan and Korea, cypresses
## round the Mediterranean), of big leafy trees (and palms) in the rainforest;
## grass on the grassland; acacias and grass (and baobabs in Africa and the
## north of Australia) on the savanna; scrub on the tundra; and in the deserts
## cacti in the Americas (not in cold deserts), red rock in Australia and dunes
## elsewhere. Forests are nearly every spot; open country a few. Mangroves come
## after (see _plant_mangroves()).
static func _decor_for_biome(biome: int, lon_lat: Vector2, rng: RandomNumberGenerator) -> String:
	var roll := rng.randf()
	match biome:
		BIOME_BOREAL:
			return "conifer" if roll < 0.68 else ("birch" if roll < 0.9 else "")
		BIOME_TEMPERATE:
			if lon_lat.x > 122.0 and lon_lat.x < 146.0 and lon_lat.y > 30.0 and lon_lat.y < 46.0:
				return "cherry" if roll < 0.24 else ("deciduous" if roll < 0.5 else ("oak" if roll < 0.62 else ("conifer" if roll < 0.85 else "")))  # Japan and Korea: cherry trees.
			if lon_lat.x > -10.0 and lon_lat.x < 42.0 and lon_lat.y > 30.0 and lon_lat.y < 46.0:
				return "cypress" if roll < 0.16 else ("oak" if roll < 0.4 else ("deciduous" if roll < 0.62 else ("conifer" if roll < 0.85 else "")))  # The Mediterranean: cypresses.
			return "deciduous" if roll < 0.34 else ("oak" if roll < 0.52 else ("conifer" if roll < 0.78 else ("birch" if roll < 0.83 else ("cherry" if roll < 0.85 else ""))))
		BIOME_RAINFOREST:
			return "rainforest" if roll < 0.82 else ("palm" if roll < 0.95 else "")
		BIOME_GRASSLAND:
			return "grass" if roll < 0.22 else ("shrub" if roll < 0.27 else "")
		BIOME_SAVANNA:
			var baobabs: bool = (lon_lat.x > -18.0 and lon_lat.x < 52.0 and lon_lat.y > -26.0 and lon_lat.y < 16.0) or (lon_lat.x > 120.0 and lon_lat.x < 150.0 and lon_lat.y > -20.0 and lon_lat.y < -10.0)
			if baobabs and roll < 0.06:
				return "baobab"  # Africa, Madagascar and the north of Australia.
			return "acacia" if roll < 0.2 else ("grass" if roll < 0.32 else "")
		BIOME_TUNDRA:
			return "shrub" if roll < 0.16 else ""
		BIOME_DESERT:
			if lon_lat.x < -30.0 and absf(lon_lat.y) > 45.0:
				return ""  # A cold desert (Greenland, Patagonia's south): no cacti.
			if lon_lat.x < -30.0:
				return "cactus" if roll < 0.1 else ""
			if lon_lat.x > 110.0 and lon_lat.y < -10.0:
				return "red_rock" if roll < 0.08 else ""
			return "dunes" if roll < 0.07 else ""
	return ""


## Mangroves: in the tropics (within MANGROVE_LAT of the equator), the trees
## nearest the water (clearance under MANGROVE_SHORE projected degrees) become
## mangroves, MANGROVE_SHARE of them, and stand right at the water's edge
## (their clearance is left as the most, so the map never holds them back).
func _plant_mangroves(map: WorldMapData) -> void:
	var kinds := {}
	for i in map.decor_kind_names.size():
		kinds[map.decor_kind_names[i]] = i
	if not kinds.has("mangrove"):
		kinds["mangrove"] = map.decor_kind_names.size()
		map.decor_kind_names.append("mangrove")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261010
	var count := 0
	for i in map.decor_positions.size():
		var name := map.decor_kind_names[map.decor_kinds[i]]
		if not MANGROVE_FROM.has(name) or i >= map.decor_clearance.size():
			continue
		if absf(Geo.unproject(map.decor_positions[i]).y) > MANGROVE_LAT or map.decor_clearance[i] > MANGROVE_SHORE:
			continue
		if rng.randf() < MANGROVE_SHARE:
			map.decor_kinds[i] = kinds["mangrove"]
			map.decor_clearance[i] = DECOR_CLEARANCE_MAX
			count += 1
	print("Mangroves: %d" % count)


## Rebuilds just the land drawings (see _add_decor()) and their clearance in
## the existing map (--decor-only), from the biomes worked out again.
func _rebuild_decor() -> void:
	var map: WorldMapData = load(MAP_OUT)
	map.decor_kind_names = PackedStringArray()
	map.decor_positions = PackedVector2Array()
	map.decor_kinds = PackedByteArray()
	map.decor_tiers = PackedByteArray()
	_add_decor(map, _build_biomes())
	_drop_wet_decor(map)
	_add_decor_clearance(map)
	_plant_mangroves(map)


## Takes out every land drawing whose spot isn't on the map's own land (the
## biomes are coarser than the coast: a stand of trees could stand in the sea
## off a headland, or in a lake), by the land triangles as drawn (and the
## lakes', and the islands' in them). Waves (the sea's) and the animals (placed
## by hand; see --animals-only --nudge) are left.
func _drop_wet_decor(map: WorldMapData) -> void:
	var cells := {}  # 1-degree cell -> the land triangles starting there.
	var index := func(triangles: PackedVector2Array, into: Dictionary) -> void:
		for t in range(0, triangles.size() - 2, 3):
			var box := Rect2(triangles[t], Vector2.ZERO).expand(triangles[t + 1]).expand(triangles[t + 2])
			for x in range(floori(box.position.x), floori(box.end.x) + 1):
				for y in range(floori(box.position.y), floori(box.end.y) + 1):
					var cell := Vector2i(x, y)
					if not into.has(cell):
						into[cell] = PackedInt32Array()
					into[cell].append(t)
	index.call(map.land_triangles, cells)
	var lake_cells := {}
	var lakes := PackedVector2Array()
	for triangles: PackedVector2Array in map.lake_triangles:
		lakes.append_array(triangles)
	index.call(lakes, lake_cells)
	var island_cells := {}
	index.call(map.lake_island_triangles, island_cells)
	var inside := func(triangles: PackedVector2Array, into: Dictionary, p: Vector2) -> bool:
		for t: int in into.get(Vector2i(floori(p.x), floori(p.y)), PackedInt32Array()):
			if Geometry2D.point_is_inside_triangle(p, triangles[t], triangles[t + 1], triangles[t + 2]):
				return true
		return false
	var animals := {}
	for animal: Array in ANIMALS:
		animals[animal[0]] = true
	var kept_positions := PackedVector2Array()
	var kept_kinds := PackedByteArray()
	var kept_tiers := PackedByteArray()
	var dropped := 0
	for i in map.decor_positions.size():
		var name := map.decor_kind_names[map.decor_kinds[i]]
		var p := map.decor_positions[i]
		var wet := false
		if name != "waves" and not animals.has(name):
			wet = not inside.call(map.land_triangles, cells, p) or (inside.call(lakes, lake_cells, p) and not inside.call(map.lake_island_triangles, island_cells, p))
		if wet:
			dropped += 1
			continue
		kept_positions.append(p)
		kept_kinds.append(map.decor_kinds[i])
		kept_tiers.append(map.decor_tiers[i])
	map.decor_positions = kept_positions
	map.decor_kinds = kept_kinds
	map.decor_tiers = kept_tiers
	print("Decor in the water taken out: %d (%d left)" % [dropped, kept_positions.size()])
	var err := ResourceSaver.save(map, MAP_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % MAP_OUT)

## True if no spot already placed is within 0.7 spacings of a point.
static func _decor_clear(taken: Dictionary, p: Vector2, spacing: float) -> bool:
	var cell := Vector2i(floori(p.x / spacing), floori(p.y / spacing))
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			for q: Vector2 in taken.get(cell + Vector2i(dx, dy), []):
				if q.distance_to(p) < spacing * 0.7:
					return false
	return true


## True if a (lon, lat) is inside any of [bounds, outline] polygons.
static func _in_any(polygons: Array, lon_lat: Vector2) -> bool:
	for item: Array in polygons:
		if (item[0] as Rect2).has_point(lon_lat) and Geometry2D.is_point_in_polygon(lon_lat, item[1]):
			return true
	return false


## The biome at a (lon, lat), or BIOME_SEA.
## How far each drawing (decor) is from the nearest shore (the coast, and the
## lakes' shores), in projected degrees, up to DECOR_CLEARANCE_MAX: the map
## shows a drawing only while all of it fits that side of the water at the
## zoom (land drawings on land, waves on the sea).
func _add_decor_clearance(map: WorldMapData) -> void:
	var shores := map.coast_segments.duplicate()
	for triangles in map.lake_triangles:
		shores.append_array(_outline_edges(triangles))
	var buckets := {}
	for i in range(0, shores.size(), 2):
		var cell := Vector2i(floori(shores[i].x / CLEARANCE_BUCKET), floori(shores[i].y / CLEARANCE_BUCKET))
		var list: PackedInt32Array = buckets.get(cell, PackedInt32Array())
		list.append(i)
		buckets[cell] = list
	var reach := ceili(DECOR_CLEARANCE_MAX / CLEARANCE_BUCKET)
	map.decor_clearance.resize(map.decor_positions.size())
	for d in map.decor_positions.size():
		var p := map.decor_positions[d]
		var cell := Vector2i(floori(p.x / CLEARANCE_BUCKET), floori(p.y / CLEARANCE_BUCKET))
		var best := DECOR_CLEARANCE_MAX
		for ring in reach + 1:
			if best < (ring - 1) * CLEARANCE_BUCKET:
				break  # Nothing further out can be nearer.
			for dx in range(-ring, ring + 1):
				for dy in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dy)) != ring:
						continue
					for i: int in buckets.get(cell + Vector2i(dx, dy), PackedInt32Array()):
						best = minf(best, Geometry2D.get_closest_point_to_segment(p, shores[i], shores[i + 1]).distance_to(p))
		map.decor_clearance[d] = best
	print("Decor clearance: %d drawings" % map.decor_clearance.size())


## A triangle list's outline: the edges only one triangle has, as segment pairs.
static func _outline_edges(triangles: PackedVector2Array) -> PackedVector2Array:
	var count := {}
	for t in range(0, triangles.size(), 3):
		for k in 3:
			var a := triangles[t + k]
			var b := triangles[t + (k + 1) % 3]
			var key := [a, b] if a < b else [b, a]
			count[key] = int(count.get(key, 0)) + 1
	var out := PackedVector2Array()
	for key: Array in count:
		if count[key] == 1:
			out.append(key[0])
			out.append(key[1])
	return out


## Where the sea is, for the sea animals (SeaLife): the biome grid's sea
## cells, a bit each (row by row from the north, west to east).
func _add_sea_mask(map: WorldMapData, biomes: PackedByteArray) -> void:
	var bits := PackedByteArray()
	bits.resize(ceili(BIOME_COLS * BIOME_ROWS / 8.0))
	var count := 0
	for i in BIOME_COLS * BIOME_ROWS:
		if biomes[i] == BIOME_SEA:
			bits[i >> 3] |= 1 << (i & 7)
			count += 1
	map.sea_mask = bits
	map.sea_mask_size = Vector2i(BIOME_COLS, BIOME_ROWS)
	print("Sea mask: %d of %d cells are sea" % [count, BIOME_COLS * BIOME_ROWS])


## The biomes as flat-colored, straight-edged polygons (the map draws them
## clipped to the land, so their edges stay sharp at any zoom): the sea's cells
## take their nearest land biome (so the polygons run past the coast, which
## clips them), each biome's patches are traced round their cell edges, the
## outlines simplified to straight runs (BIOME_SIMPLIFY projected degrees) and
## triangulated. Patches inside others are drawn after them (largest first),
## so holes need no cutting.
func _add_biome_polygons(map: WorldMapData, biomes: PackedByteArray) -> void:
	var cols := BIOME_COLS
	var rows := BIOME_ROWS
	var grid := biomes.duplicate()
	# The sea takes its nearest land biome, a ring at a time.
	var frontier := PackedInt32Array()
	for i in grid.size():
		if grid[i] != BIOME_SEA:
			frontier.append(i)
	while not frontier.is_empty():
		var next := PackedInt32Array()
		for i in frontier:
			var col := i % cols
			for n: int in [i - 1 if col > 0 else -1, i + 1 if col < cols - 1 else -1, i - cols, i + cols]:
				if n >= 0 and n < grid.size() and grid[n] == BIOME_SEA:
					grid[n] = grid[i]
					next.append(n)
		frontier = next
	# Each cell's edges against a different biome (or the grid's edge), running
	# with the cell's biome on the left: per biome, vertex -> the vertices its edges go to.
	var vertex_cols := cols + 1
	var edges := {}  # biome -> {from vertex: PackedInt32Array of to vertices}
	for r in rows:
		for c in cols:
			var b := grid[r * cols + c]
			var out: Dictionary = edges.get_or_add(b, {})
			var top_left := r * vertex_cols + c
			var top_right := top_left + 1
			var bottom_left := top_left + vertex_cols
			var bottom_right := bottom_left + 1
			if r == 0 or grid[(r - 1) * cols + c] != b:
				_add_edge(out, top_right, top_left)  # Westward along the top.
			if r == rows - 1 or grid[(r + 1) * cols + c] != b:
				_add_edge(out, bottom_left, bottom_right)  # Eastward along the bottom.
			if c == 0 or grid[r * cols + c - 1] != b:
				_add_edge(out, top_left, bottom_left)  # Down the west side.
			if c == cols - 1 or grid[r * cols + c + 1] != b:
				_add_edge(out, bottom_right, top_right)  # Up the east side.
	# Trace each biome's outlines; keep the outer ones (anticlockwise, the patch
	# on the left), simplified, with their area for the drawing order.
	var shapes := []  # [area, biome, outline]
	for b: int in edges:
		var out: Dictionary = edges[b]
		while not out.is_empty():
			var start: int = out.keys()[0]
			var ring := PackedVector2Array()
			var at := start
			var guard := 0
			while guard < 4000000:
				guard += 1
				var ends: PackedInt32Array = out[at]
				var to := ends[ends.size() - 1]
				ends.resize(ends.size() - 1)
				if ends.is_empty():
					out.erase(at)
				else:
					out[at] = ends
				ring.append(Geo.project(Vector2(-180.0 + (at % vertex_cols) * 360.0 / cols, 90.0 - floori(at / float(vertex_cols)) * 180.0 / rows)))
				at = to
				if at == start or not out.has(at):
					break
			if ring.size() < 4:
				continue
			var area := _signed_area(ring)
			if area <= BIOME_MIN_AREA:
				continue  # A hole (its inside is another patch, drawn over it), or a speck.
			var simple := _simplify_ring(ring, _biome_simplify())
			if simple.size() >= 3:
				shapes.append([area, b, simple, ring])
	shapes.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	for shape: Array in shapes:
		var color := BIOME_COLORS[shape[1]]
		var points: PackedVector2Array = shape[2]
		var indices := Geometry2D.triangulate_polygon(points)
		if indices.is_empty():  # Simplifying made it cross itself: the traced outline instead.
			points = shape[3]
			indices = Geometry2D.triangulate_polygon(points)
		for i in indices:
			map.biome_triangles.append(points[i])
			map.biome_colors.append(color)
	var outline_points := 0
	for shape: Array in shapes:
		outline_points += (shape[2] as PackedVector2Array).size()
	print("Biome polygons: %d patches, %d outline points, %d triangles" % [shapes.size(), outline_points, map.biome_triangles.size() / 3])


static func _add_edge(out: Dictionary, from: int, to: int) -> void:
	var ends: PackedInt32Array = out.get(from, PackedInt32Array())
	ends.append(to)
	out[from] = ends  # (Packed arrays are copied, so put it back.)


## A closed outline simplified (Douglas-Peucker, between its two farthest-apart
## points) so the cell edges' staircases become straight runs.
static func _simplify_ring(ring: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	var far := 0
	var far_d := 0.0
	for i in ring.size():
		var d := ring[i].distance_squared_to(ring[0])
		if d > far_d:
			far_d = d
			far = i
	var first := _simplify_line(ring.slice(0, far + 1), tolerance)
	var second_part := ring.slice(far)
	second_part.append(ring[0])
	var second := _simplify_line(second_part, tolerance)
	var out := first.slice(0, first.size() - 1)
	out.append_array(second.slice(0, second.size() - 1))
	return out


static func _simplify_line(points: PackedVector2Array, tolerance: float) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var keep := PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size() - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var worst := -1
		var worst_d := tolerance
		for i in range(span.x + 1, span.y):
			var d := Geometry2D.get_closest_point_to_segment(points[i], points[span.x], points[span.y]).distance_to(points[i])
			if d > worst_d:
				worst_d = d
				worst = i
		if worst >= 0:
			keep[worst] = 1
			stack.append(Vector2i(span.x, worst))
			stack.append(Vector2i(worst, span.y))
	var out := PackedVector2Array()
	for i in points.size():
		if keep[i]:
			out.append(points[i])
	return out


static func _biome_at(biomes: PackedByteArray, lon_lat: Vector2) -> int:
	var col := posmod(floori((lon_lat.x + 180.0) / 360.0 * BIOME_COLS), BIOME_COLS)
	var row := clampi(floori((90.0 - lon_lat.y) / 180.0 * BIOME_ROWS), 0, BIOME_ROWS - 1)
	return biomes[row * BIOME_COLS + col]


## The land colors as a LAND_TEXTURE_SIZE square texture in the map's
## projection (x -180 to 180, y from Geo.MAX_LAT down to -Geo.MAX_LAT): each
## biome (see _build_biomes()) in its flat color, softly blended where biomes
## meet. The map draws the land triangles with it, so the coast stays as sharp
## as the land data; only the color comes from here. Its sea is filled in from
## the nearest land first, so no sea color shows along a coast.
func _build_land_texture(biomes: PackedByteArray) -> void:
	var size := LAND_TEXTURE_SIZE
	@warning_ignore("integer_division")
	var rows := size / 2  # Still in plain longitude/latitude: 2 degrees wide per degree high.
	# Smooth biome edges: each biome's mask is blown up BIOME_EDGE_UPSCALE times
	# with cubic smoothing, and each pixel takes the biome strongest there, so
	# patches get rounded outlines instead of blocky cells. (Pixels out at sea
	# just take the nearest biome; only the land shows.)
	var up_cols := BIOME_COLS * BIOME_EDGE_UPSCALE
	var up_rows := BIOME_ROWS * BIOME_EDGE_UPSCALE
	var masks: Array[PackedByteArray] = []
	for biome in BIOME_COLORS.size():
		var one := PackedByteArray()
		one.resize(biomes.size())
		for i in biomes.size():
			one[i] = 255 if biomes[i] == biome else 0
		var image := Image.create_from_data(BIOME_COLS, BIOME_ROWS, false, Image.FORMAT_L8, one)
		image.resize(up_cols, up_rows, Image.INTERPOLATE_CUBIC)
		masks.append(image.get_data())
	var palette := PackedByteArray()
	for color in BIOME_COLORS:
		palette.append_array([color.r8, color.g8, color.b8])
	var flat_colors := PackedByteArray()
	flat_colors.resize(up_cols * up_rows * 3)
	for i in up_cols * up_rows:
		var best := 0
		var best_value := -1
		for biome in masks.size():
			var value := masks[biome][i]
			if value > best_value:
				best_value = value
				best = biome
		flat_colors[i * 3] = palette[best * 3]
		flat_colors[i * 3 + 1] = palette[best * 3 + 1]
		flat_colors[i * 3 + 2] = palette[best * 3 + 2]
	var source := Image.create_from_data(up_cols, up_rows, false, Image.FORMAT_RGB8, flat_colors)
	var mask := Image.load_from_file(LAND_COLORS_PATH)
	mask.convert(Image.FORMAT_RGB8)
	mask.resize(size, rows, Image.INTERPOLATE_NEAREST)
	source.resize(size, rows, Image.INTERPOLATE_BILINEAR)
	var colors := source.get_data()
	var mask_colors := mask.get_data()
	var sea_r := LAND_COLORS_SEA.r8
	# Sea, and anything next to it (the resize blends sea into the coast), is
	# filled from the land around it, a ring at a time.
	var fill := PackedByteArray()
	fill.resize(size * rows)
	for i in size * rows:
		if mask_colors[i * 3] == sea_r and mask_colors[i * 3 + 1] == sea_r and mask_colors[i * 3 + 2] == sea_r:
			fill[i] = 1
	var sea := fill.duplicate()
	for i in size * rows:
		if sea[i]:
			var col := i % size
			for n: int in [i - 1 if col > 0 else -1, i + 1 if col < size - 1 else -1, i - size, i + size]:
				if n >= 0 and n < size * rows:
					fill[n] = 1
	var frontier := PackedInt32Array()
	for i in size * rows:
		if fill[i] and _has_land_neighbor(fill, i, size, rows):
			frontier.append(i)
	for ring in LAND_FILL_RINGS:
		var next := PackedInt32Array()
		var done := PackedInt32Array()
		for i in frontier:
			if not fill[i]:
				continue
			var total := Vector3i.ZERO
			var count := 0
			var col := i % size
			for n: int in [i - 1 if col > 0 else -1, i + 1 if col < size - 1 else -1, i - size, i + size]:
				if n >= 0 and n < size * rows:
					if not fill[n]:
						total += Vector3i(colors[n * 3], colors[n * 3 + 1], colors[n * 3 + 2])
						count += 1
					else:
						next.append(n)
			if count > 0:
				colors[i * 3] = total.x / count
				colors[i * 3 + 1] = total.y / count
				colors[i * 3 + 2] = total.z / count
				done.append(i)
			else:
				next.append(i)
		for i in done:
			fill[i] = 0
		frontier = next
	var flat := Image.create_from_data(size, rows, false, Image.FORMAT_RGB8, colors)
	# Into the map's projection, a row at a time (Mercator only stretches north-south).
	var out := Image.create(size, size, false, Image.FORMAT_RGB8)
	var top := Geo.project(Vector2(0.0, Geo.MAX_LAT)).y
	for row in size:
		var y := top - (row + 0.5) / size * 2.0 * top
		var lat := Geo.unproject(Vector2(0.0, y)).y
		var source_row := clampi(floori((90.0 - lat) / 180.0 * rows), 0, rows - 1)
		out.blit_rect(flat, Rect2i(0, source_row, size, 1), Vector2i(0, row))
	var err := out.save_webp(LAND_TEXTURE_OUT, true, 0.9)
	assert(err == OK, "Couldn't save %s" % LAND_TEXTURE_OUT)
	print("Land colors: %d x %d" % [size, size])


static func _has_land_neighbor(fill: PackedByteArray, i: int, size: int, rows: int) -> bool:
	var col := i % size
	return (col > 0 and not fill[i - 1]) or (col < size - 1 and not fill[i + 1]) \
		or (i >= size and not fill[i - size]) or (i + size < size * rows and not fill[i + size])


## Douglas-Peucker simplification of a closed ring.
func _simplify(points: PackedVector2Array, tolerance := SIMPLIFY_TOLERANCE) -> PackedVector2Array:
	var n := points.size()
	if n < 4:
		return points
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack := [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var span: Vector2i = stack.pop_back()
		var a := points[span.x]
		var b := points[span.y]
		var worst := -1
		var worst_dist := tolerance
		for i in range(span.x + 1, span.y):
			var d := Geometry2D.get_closest_point_to_segment(points[i], a, b).distance_to(points[i])
			if d > worst_dist:
				worst_dist = d
				worst = i
		if worst >= 0:
			keep[worst] = 1
			stack.append(Vector2i(span.x, worst))
			stack.append(Vector2i(worst, span.y))
	var out := PackedVector2Array()
	for i in n:
		if keep[i]:
			out.append(points[i])
	return out


## Coastline segments, skipping the artificial edges Natural Earth adds along
## the antimeridian and the bottom of Antarctica.
## Lakes as water with a shoreline, each in its group's simplified real color
## (LAKE_GROUPS); islands in them go back in as land.
func _add_lakes(map: WorldMapData) -> void:
	var count := 0
	var groups: Array = LAKE_GROUPS.keys()
	for group: String in groups:
		map.lake_triangles.append(PackedVector2Array())
		map.lake_colors.append(Color(LAKE_GROUPS[group]))
	for feature: Dictionary in _read_geojson(LAKES_PATH):
		var props: Dictionary = feature.properties
		var name := str(props.get("name", "")) if props.get("name") != null else ""
		var group: String = LAKE_NAMES.get(name, "salt_pan" if name in LAKE_SALT_PANS else
			("saline" if str(props.get("featurecla", "")) == "Alkaline Lake" else "fresh"))
		# Australia's inland salt lakes are nearly always dry white crusts.
		if group == "saline" and not LAKE_NAMES.has(name) and LAKE_DRY_SALT_REGION.has_point(_first_point(feature)):
			group = "salt_pan"
		var triangles: PackedVector2Array = map.lake_triangles[groups.find(group)]
		for polygon: Array in _feature_polygons(feature):
			var outline := _simplify(_project_all(_to_points(polygon[0])))
			if outline.size() < 3:
				continue
			_add_coast(map, outline)
			_triangulate_tiled(outline, triangles, PackedVector2Array())
			map.lake_triangles[groups.find(group)] = triangles  # Packed arrays copy: store it back.
			count += 1
			for i in range(1, polygon.size()):
				var island := _simplify(_project_all(_to_points(polygon[i])))
				if island.size() >= 3:
					_add_coast(map, island)
					_triangulate_tiled(island, map.lake_island_triangles, PackedVector2Array())
	print("Lakes: %d" % count)


## The first (lon, lat) point of a feature's first polygon.
func _first_point(feature: Dictionary) -> Vector2:
	var polygons := _feature_polygons(feature)
	if polygons.is_empty() or polygons[0].is_empty() or polygons[0][0].is_empty():
		return Vector2.INF
	var point: Array = polygons[0][0][0]
	return Vector2(point[0], point[1])


## Rivers as line segments, in tiers by the web-map zoom they show from (the
## data's min_zoom). Lake centerlines are skipped: the lakes are drawn.
func _add_rivers(map: WorldMapData) -> void:
	var tiers := {}  # min zoom -> PackedVector2Array of segments
	for feature: Dictionary in _read_geojson(RIVERS_PATH):
		var props: Dictionary = feature.properties
		if props.get("featurecla", "") != "River" or feature.geometry == null:
			continue
		var lines: Array = [feature.geometry.coordinates] if feature.geometry.type == "LineString" else feature.geometry.coordinates
		var min_zoom := float(props.get("min_zoom", 7.0))
		var segments: PackedVector2Array = tiers.get(min_zoom, PackedVector2Array())
		for line: Array in lines:
			var points := _simplify(_project_all(_to_points(line)))
			for i in range(1, points.size()):
				segments.append(points[i - 1])
				segments.append(points[i])
		tiers[min_zoom] = segments
	var zooms := tiers.keys()
	zooms.sort()
	for zoom: float in zooms:
		map.river_tiers.append(tiers[zoom])
		map.river_tier_min_zoom.append(zoom)
	print("Rivers: %d tiers" % zooms.size())


func _add_coast(map: WorldMapData, ring: PackedVector2Array) -> void:
	var bottom := Geo.project(Vector2(0, -Geo.MAX_LAT)).y + 0.01
	for i in ring.size():
		var a := ring[i]
		var b := ring[(i + 1) % ring.size()]
		if absf(a.x) > 179.99 and absf(b.x) > 179.99:
			continue
		if a.y < bottom and b.y < bottom:
			continue
		map.coast_segments.append(a)
		map.coast_segments.append(b)


## Cuts a polygon into tiles and triangulates each piece. Pieces that come out
## as holes (from self-intersections after simplifying) go to hole_out.
func _triangulate_tiled(polygon: PackedVector2Array, out: PackedVector2Array, hole_out: PackedVector2Array) -> void:
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for p in polygon:
		bounds = bounds.expand(p)
	var x0 := floorf(bounds.position.x / TILE_SIZE) * TILE_SIZE
	var y0 := floorf(bounds.position.y / TILE_SIZE) * TILE_SIZE
	var x := x0
	while x < bounds.end.x:
		var y := y0
		while y < bounds.end.y:
			var tile := PackedVector2Array([Vector2(x, y), Vector2(x + TILE_SIZE, y),
					Vector2(x + TILE_SIZE, y + TILE_SIZE), Vector2(x, y + TILE_SIZE)])
			var pieces := Geometry2D.intersect_polygons(polygon, tile)
			var outer_clockwise := _largest_is_clockwise(pieces)
			for piece: PackedVector2Array in pieces:
				var target := out if Geometry2D.is_polygon_clockwise(piece) == outer_clockwise else hole_out
				_triangulate(piece, target)
			y += TILE_SIZE
		x += TILE_SIZE


func _largest_is_clockwise(pieces: Array) -> bool:
	var best := 0.0
	var clockwise := false
	for piece: PackedVector2Array in pieces:
		var area := absf(_signed_area(piece))
		if area > best:
			best = area
			clockwise = Geometry2D.is_polygon_clockwise(piece)
	return clockwise


func _signed_area(points: PackedVector2Array) -> float:
	var area := 0.0
	for i in points.size():
		area += points[i].cross(points[(i + 1) % points.size()])
	return area / 2.0


func _triangulate(piece: PackedVector2Array, out: PackedVector2Array) -> void:
	var indices := Geometry2D.triangulate_polygon(piece)
	if indices.is_empty():
		# Ear clipping fails on some degenerate pieces; fall back to Delaunay,
		# keeping the triangles whose centers are inside the piece.
		var all := Geometry2D.triangulate_delaunay(piece)
		for i in range(0, all.size(), 3):
			var center := (piece[all[i]] + piece[all[i + 1]] + piece[all[i + 2]]) / 3.0
			if Geometry2D.is_point_in_polygon(center, piece):
				indices.append_array([all[i], all[i + 1], all[i + 2]])
	for i in indices:
		out.append(piece[i])


## Borders are the country outline edges shared by two countries; edges only
## one country has are coastline, which the land data already draws.
func _add_countries(map: WorldMapData) -> void:
	var edge_counts := {}
	for feature: Dictionary in _read_geojson(COUNTRIES_PATH):
		var props: Dictionary = feature.properties
		map.label_names.append(props.get("NAME", ""))
		map.label_positions.append(Geo.project(Vector2(props.get("LABEL_X", 0.0), props.get("LABEL_Y", 0.0))))
		map.label_min_zoom.append(float(props.get("MIN_LABEL", 10.0)))
		for polygon: Array in _feature_polygons(feature):
			for ring: Array in polygon:
				var points := _to_points(ring)
				for i in points.size():
					var key := _edge_key(points[i], points[(i + 1) % points.size()])
					edge_counts[key] = edge_counts.get(key, 0) + 1
	for key: Array in edge_counts:
		if edge_counts[key] >= 2:
			map.border_segments.append(Geo.project(key[0]))
			map.border_segments.append(Geo.project(key[1]))
	print("Countries: %d labels, %d border segments" % [map.label_names.size(), map.border_segments.size() / 2])


func _edge_key(a: Vector2, b: Vector2) -> Array:
	a = a.snappedf(0.0001)
	b = b.snappedf(0.0001)
	return [a, b] if (a.x < b.x or (a.x == b.x and a.y < b.y)) else [b, a]


# --- Pathfinding grid ----------------------------------------------------

func _build_grid(land_polygons: Array) -> void:
	var south := Geo.project(Vector2(0, GRID_SOUTH_LAT)).y
	var north := Geo.project(Vector2(0, GRID_NORTH_LAT)).y
	_grid_origin = Vector2(GRID_WEST, south)
	_cols = ceili((GRID_EAST - GRID_WEST) / GRID_CELL)
	_rows = ceili((north - south) / GRID_CELL)
	_arctic_row = ceili((Geo.project(Vector2(0, ARCTIC_LAT)).y - south) / GRID_CELL / COARSE) * COARSE
	_land.resize(_cols * _rows)

	# Scanline-fill every land polygon (outline and holes, even-odd) into the
	# grid, plus a second copy 360 degrees east for the part past 180.
	for polygon: Dictionary in land_polygons:
		var rings := [_project_all(polygon.outline)]
		for hole: PackedVector2Array in polygon.holes:
			rings.append(_project_all(hole))
		_fill_rings(rings, 0.0)
		_fill_rings(rings, Geo.WORLD_WIDTH)

	# Cut the sea lakes back out of the land (even-odd, so their islands stay land).
	for feature: Dictionary in _read_geojson(LAKES_PATH):
		if not str(feature.properties.get("name", "")) in SEA_LAKES:
			continue
		for polygon: Array in _feature_polygons(feature):
			var lake_rings := []
			for ring: Array in polygon:
				lake_rings.append(_project_all(_to_points(ring)))
			_fill_rings(lake_rings, 0.0)
			_fill_rings(lake_rings, Geo.WORLD_WIDTH)

	var channels: Array = CHANNELS.values().map(_to_points)
	for dredge: Array in DREDGES:
		channels.append(_to_points(dredge[1]))  # (The dredged passages, at least in the lanes' grid.)
	for canal in _canals:
		channels.append(canal.path)
	for channel: PackedVector2Array in channels:
		for i in range(1, channel.size()):
			var a := Geo.project(channel[i - 1])
			var b := Geo.project(channel[i])
			_carve(a, b)
			_carve(a + Vector2(Geo.WORLD_WIDTH, 0), b + Vector2(Geo.WORLD_WIDTH, 0))

	_near_land = _land.duplicate()
	for row in _rows:
		var base := row * _cols
		for col in _cols:
			if not _land[base + col]:
				continue
			for dy in range(-1, 2):
				var r := row + dy
				if r < 0 or r >= _rows:
					continue
				var rbase := r * _cols
				for dx in range(-1, 2):
					var c := col + dx
					if c >= 0 and c < _cols:
						_near_land[rbase + c] = 1
	_mark_ocean()
	print("Grid: %d x %d cells" % [_cols, _rows])


## Flood-fills the water reachable from the middle of the Pacific. Moves are
## 4-way, matching the pathfinder (it only cuts corners when both sides are water).
func _mark_ocean() -> void:
	_ocean.resize(_land.size())
	var start := _cell_of(Geo.project(Vector2(-150.0, 0.0)))
	var queue := PackedInt32Array([start.y * _cols + start.x])
	_ocean[queue[0]] = 1
	var total := _land.size()
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var col := index % _cols
		if col > 0 and not _land[index - 1] and not _ocean[index - 1]:
			_ocean[index - 1] = 1
			queue.append(index - 1)
		if col < _cols - 1 and not _land[index + 1] and not _ocean[index + 1]:
			_ocean[index + 1] = 1
			queue.append(index + 1)
		if index >= _cols and not _land[index - _cols] and not _ocean[index - _cols]:
			_ocean[index - _cols] = 1
			queue.append(index - _cols)
		if index + _cols < total and not _land[index + _cols] and not _ocean[index + _cols]:
			_ocean[index + _cols] = 1
			queue.append(index + _cols)
	print("Ocean: %d connected water cells" % queue.size())


func _fill_rings(rings: Array, x_offset: float) -> void:
	var crossings := {}  # row -> x positions where an edge crosses the row's center line
	var origin := _grid_origin - Vector2(x_offset, 0)
	for ring: PackedVector2Array in rings:
		for i in ring.size():
			var a := (ring[i] - origin) / GRID_CELL
			var b := (ring[(i + 1) % ring.size()] - origin) / GRID_CELL
			if a.y == b.y:
				continue
			var lo := minf(a.y, b.y)
			var hi := maxf(a.y, b.y)
			var first_row := maxi(0, ceili(lo - 0.5))
			var last_row := mini(_rows - 1, ceili(hi - 0.5) - 1)
			for row in range(first_row, last_row + 1):
				var t := (row + 0.5 - a.y) / (b.y - a.y)
				if not crossings.has(row):
					crossings[row] = PackedFloat32Array()
				crossings[row].append(a.x + t * (b.x - a.x))
	for row: int in crossings:
		var xs: PackedFloat32Array = crossings[row]
		xs.sort()
		for i in range(0, xs.size() - 1, 2):
			var c0 := maxi(0, ceili(xs[i] - 0.5))
			var c1 := mini(_cols - 1, ceili(xs[i + 1] - 0.5) - 1)
			for col in range(c0, c1 + 1):
				_land[row * _cols + col] ^= 1


func _carve(a: Vector2, b: Vector2) -> void:
	var steps := maxi(1, ceili(a.distance_to(b) / (GRID_CELL * 0.25)))
	for s in steps + 1:
		var cell := _cell_of(a.lerp(b, float(s) / steps))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := cell + Vector2i(dx, dy)
				if _in_grid(c):
					_land[c.y * _cols + c.x] = 0


func _cell_of(point: Vector2) -> Vector2i:
	var p := (point - _grid_origin) / GRID_CELL
	return Vector2i(floori(p.x), floori(p.y))


func _cell_center(cell: Vector2i) -> Vector2:
	return _grid_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * GRID_CELL


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < _cols and cell.y >= 0 and cell.y < _rows


func _is_land(cell: Vector2i) -> bool:
	return not _in_grid(cell) or _land[cell.y * _cols + cell.x] == 1 or (_block_arctic and cell.y >= _arctic_row)


func _is_near_land(cell: Vector2i) -> bool:
	return not _in_grid(cell) or _near_land[cell.y * _cols + cell.x] == 1 or (_block_arctic and cell.y >= _arctic_row)


# --- Sea lanes -----------------------------------------------------------

func _build_lanes() -> void:
	# Routes are found on a coarse graph of pieces of water (fast, and weighted
	# so they follow real distances and keep off the coast; see
	# _build_coarse_graph()), then fitted to the fine grid; the fine grid is
	# only searched for short hops the coarse route can't see across.
	var coarse := _build_coarse_graph()
	var astar := _fine_astar()
	print("Pathfinding grid ready")

	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string(PORTS_PATH)).ports
	ports.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	# Each port's starting water cell, at its real longitude and (if it fits in
	# the grid) 360 degrees east: [[lon offset, cell], ...]
	var starts := {}
	for port: Dictionary in ports:
		var options := []
		for offset in [0.0, Geo.WORLD_WIDTH]:
			var p := Geo.project(Vector2(port.lon + offset, port.lat))
			if p.x < GRID_EAST - 1.0:
				var cell := _nearest_water(_cell_of(p))
				if cell.x >= 0:
					options.append([offset, cell])
					var snap := Vector2(cell - _cell_of(p)).length()
					if snap > 12 and offset == 0.0:
						print("  note: %s is %.0f cells from open water" % [port.id, snap])
		if options.is_empty():
			push_error("%s is not near any water" % port.id)
		starts[port.id] = options
	if "--check" in OS.get_cmdline_user_args():
		_print_water_check()
		return

	var data := SeaLaneData.new()
	var started := Time.get_ticks_msec()
	@warning_ignore("integer_division")
	var pairs := ports.size() * (ports.size() - 1) / 2
	var done := 0
	var search_usec := 0
	var shape_usec := 0
	var args := OS.get_cmdline_user_args()
	var limit := int(args[args.find("--limit") + 1]) if "--limit" in args else pairs
	var only := _pairs_arg(ports)
	# Lanes between two ports that aren't in the Arctic first, with the Arctic
	# blocked (see ARCTIC_LAT), then those to or from an Arctic port, with it open.
	var pair_list := []
	for i in ports.size():
		for j in range(i + 1, ports.size()):
			if only.is_empty() or only.has("%s-%s" % [ports[i].id, ports[j].id]):
				pair_list.append([ports[i], ports[j]])
	var arctic_pairs := pair_list.filter(_is_arctic_pair)
	pair_list = pair_list.filter(func(pair: Array) -> bool: return not _is_arctic_pair(pair)) + arctic_pairs
	_set_arctic_blocked(coarse, astar, true)
	for pair: Array in pair_list:
		if done >= limit:
			break
		var a: Dictionary = pair[0]
		var b: Dictionary = pair[1]
		if _block_arctic and _is_arctic_pair(pair):
			_set_arctic_blocked(coarse, astar, false)
		var best := PackedVector2Array()
		var best_distance := INF
		var span: float = absf(a.lon - b.lon)
		for option_a: Array in starts[a.id]:
			for option_b: Array in starts[b.id]:
				if option_a[0] > 0.0 and option_b[0] > 0.0:
					continue  # Same as both at their real longitude.
				var shifted: bool = option_a[0] > 0.0 or option_b[0] > 0.0
				if shifted and span <= MIN_WRAP_SPAN:
					continue  # Close enough that the short way can't cross the Pacific seam.
				var lon_a: float = a.lon + option_a[0]
				var lon_b: float = b.lon + option_b[0]
				if absf(lon_a - lon_b) > MAX_ROUTE_SPAN:
					continue
				var t0 := Time.get_ticks_usec()
				var cells := _route(coarse, astar, option_a[1], option_b[1])
				var t1 := Time.get_ticks_usec()
				search_usec += t1 - t0
				if cells.is_empty():
					continue
				var points := _lane_points(Vector2(lon_a, a.lat), cells, Vector2(lon_b, b.lat))
				points = _splice_canals(points)
				shape_usec += Time.get_ticks_usec() - t1
				var distance := _length_nm(points)
				if distance < best_distance:
					best_distance = distance
					best = points
		if not best.is_empty():
			best = _round_corners(best)
			best_distance = _length_nm(best)
		if best.is_empty():
			push_error("No sea route from %s to %s" % [a.id, b.id])
		else:
			# Shift the lane so it starts at the first port's real longitude.
			var shift: float = a.lon - best[0].x
			data.keys.append("%s-%s" % [a.id, b.id])
			data.starts.append(data.points.size())
			for p in best:
				data.points.append(Vector2(snappedf(p.x + shift, 0.0001), snappedf(p.y, 0.0001)))
			data.distances.append(best_distance)
		done += 1
		if done % 50 == 0:
			var elapsed := (Time.get_ticks_msec() - started) / 1000.0
			print("  %d / %d lanes (%.0f s, ~%.0f s left; search %.0f s, shaping %.0f s)" % [done, pairs, elapsed, elapsed / done * (pairs - done), search_usec / 1e6, shape_usec / 1e6])
	data.starts.append(data.points.size())
	if not only.is_empty():
		data = _patch_lanes(data)

	var err := ResourceSaver.save(data, LANES_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % LANES_OUT)
	print("Lanes: %d, %d points" % [data.keys.size(), data.points.size()])
	_print_stats(data)


## The fine pathfinder over the grid (land solid), for short hops the coarse
## graph can't see across (see _route()).
func _fine_astar() -> AStarGrid2D:
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, _cols, _rows)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.jumping_enabled = true
	astar.update()
	for row in _rows:
		var col := 0
		while col < _cols:
			if not _land[row * _cols + col]:
				col += 1
				continue
			var run_start := col
			while col < _cols and _land[row * _cols + col]:
				col += 1
			astar.fill_solid_region(Rect2i(run_start, row, col - run_start, 1))
	return astar


## True if either port of a [port, port] pair is in the Arctic (ports.json
## arctic: true): only their lanes may sail north of ARCTIC_LAT.
static func _is_arctic_pair(pair: Array) -> bool:
	return bool(pair[0].get("arctic", false)) or bool(pair[1].get("arctic", false))


## Makes the grid north of ARCTIC_LAT count as land (blocked) or water again,
## in the coarse graph (its pieces there disabled), the fine pathfinder (its
## water there solid) and the land checks (_is_land(), _is_near_land()).
func _set_arctic_blocked(coarse: AStar2D, fine: AStarGrid2D, blocked: bool) -> void:
	if _block_arctic == blocked or _arctic_row >= _rows:
		_block_arctic = blocked
		return
	_block_arctic = blocked
	var coarse_cols := ceili(float(_cols) / COARSE)
	@warning_ignore("integer_division")
	var first_coarse_row := _arctic_row / COARSE
	for piece in _piece_rep.size():
		@warning_ignore("integer_division")
		if _piece_cell[piece] / coarse_cols >= first_coarse_row:
			coarse.set_point_disabled(piece, blocked)
	var region := Rect2i(0, _arctic_row, _cols, _rows - _arctic_row)
	fine.fill_solid_region(region, blocked)
	if not blocked:
		for row in range(_arctic_row, _rows):
			var col := 0
			while col < _cols:
				if not _land[row * _cols + col]:
					col += 1
					continue
				var run_start := col
				while col < _cols and _land[row * _cols + col]:
					col += 1
				fine.fill_solid_region(Rect2i(run_start, row, col - run_start, 1))
	print("  the Arctic is %s" % ("blocked" if blocked else "open"))


## The lane keys to re-route (each "A-B" with the ids in alphabetical order, as
## stored), or {} to route every pair: "--pairs PUS-YOK,DXB-HKG" for those
## lanes, "--ports CPH,GDN" for every lane to or from those ports.
func _pairs_arg(ports: Array) -> Dictionary:
	var args := OS.get_cmdline_user_args()
	var only := {}
	if "--pairs" in args:
		for pair: String in args[args.find("--pairs") + 1].split(","):
			var ids := pair.strip_edges().split("-")
			ids.sort()
			only["%s-%s" % [ids[0], ids[1]]] = true
	if "--ports" in args:
		var chosen := args[args.find("--ports") + 1].split(",")
		for a: Dictionary in ports:
			for b: Dictionary in ports:
				if a.id < b.id and (a.id in chosen or b.id in chosen):
					only["%s-%s" % [a.id, b.id]] = true
	return only


## The lanes already in data/sea_lanes.res with the freshly routed ones in
## place of theirs (for "--pairs"), printing each one's old and new length, and
## any new ones (to or from a port added to ports.json) added.
func _patch_lanes(fresh: SeaLaneData) -> SeaLaneData:
	var old: SeaLaneData = load(LANES_OUT)
	var replaced := {}
	for i in fresh.keys.size():
		replaced[fresh.keys[i]] = i
	var out := SeaLaneData.new()
	for i in old.keys.size():
		var source := old
		var index := i
		if replaced.has(old.keys[i]):
			source = fresh
			index = replaced[old.keys[i]]
			print("  %s: %.0f nm -> %.0f nm" % [old.keys[i], old.distances[i], fresh.distances[index]])
		out.keys.append(old.keys[i])
		out.starts.append(out.points.size())
		out.points.append_array(source.points.slice(source.starts[index], source.starts[index + 1]))
		out.distances.append(source.distances[index])
	# Lanes to or from a newly added port aren't in the old file: add them.
	var had := {}
	for key in old.keys:
		had[key] = true
	var added := 0
	for i in fresh.keys.size():
		if had.has(fresh.keys[i]):
			continue
		out.keys.append(fresh.keys[i])
		out.starts.append(out.points.size())
		out.points.append_array(fresh.points.slice(fresh.starts[i], fresh.starts[i + 1]))
		out.distances.append(fresh.distances[i])
		added += 1
	if added > 0:
		print("  added %d new lanes" % added)
	out.starts.append(out.points.size())
	return out


## Coarse graph over the fine grid, for planning routes fast. Each coarse cell
## (COARSE x COARSE fine cells) is split into its separate pieces of open ocean
## (fine cells joined side to side within the cell), and each piece is a node,
## so water on two sides of a thin strip of land (an isthmus, a peninsula, a
## sandbar) is two nodes, not one. Pieces in side-by-side cells are linked
## where their fine cells touch across the shared edge, and pieces in
## corner-to-corner cells where both link to a piece in one of the two cells
## between, so a coarse route never plans a way the water doesn't go. Each
## piece passes routes through its ocean cell nearest the cell's center,
## preferring cells off the coast.
func _build_coarse_graph() -> AStar2D:
	var coarse_cols := ceili(float(_cols) / COARSE)
	var coarse_rows := ceili(float(_rows) / COARSE)
	var graph := AStar2D.new()
	# On a Mercator grid a cell spans cos(latitude) as much real distance at
	# every latitude. Weights are normalized to >= 1 so the heuristic stays
	# admissible; past WEIGHT_MAX_LAT (the far south, only reached going to
	# Antarctica) they're held at 1, so paths there run slightly long rather than
	# every search slowing down.
	var min_scale := cos(deg_to_rad(WEIGHT_MAX_LAT))
	_fine_piece.resize(_cols * _rows)
	_fine_piece.fill(-1)
	_piece_rep.clear()
	_piece_cell.clear()
	var stack := PackedInt32Array()
	for cy in coarse_rows:
		var lat := Geo.unproject(_cell_center(Vector2i(0, mini(cy * COARSE + COARSE / 2, _rows - 1)))).y
		var weight := maxf(cos(deg_to_rad(lat)) / min_scale, 1.0)
		var y0 := cy * COARSE
		var y1 := mini(y0 + COARSE, _rows)
		for cx in coarse_cols:
			var x0 := cx * COARSE
			var x1 := mini(x0 + COARSE, _cols)
			var center := Vector2((cx + 0.5) * COARSE, (cy + 0.5) * COARSE)
			var touches_land := false
			for fy in range(y0, y1):
				for fx in range(x0, x1):
					touches_land = touches_land or _land[fy * _cols + fx] == 1
			for fy in range(y0, y1):
				for fx in range(x0, x1):
					var seed := fy * _cols + fx
					if not _ocean[seed] or _fine_piece[seed] >= 0:
						continue
					# A new piece: flood it within this cell, keeping its best rep.
					var piece := _piece_rep.size()
					_fine_piece[seed] = piece
					stack.append(seed)
					var best := seed
					var best_score := INF
					while not stack.is_empty():
						var index := stack[-1]
						stack.remove_at(stack.size() - 1)
						var col := index % _cols
						var row := index / _cols
						var score := center.distance_to(Vector2(col + 0.5, row + 0.5)) + (100.0 if _near_land[index] else 0.0)
						if score < best_score:
							best_score = score
							best = index
						for next: int in [index - 1 if col > x0 else -1, index + 1 if col < x1 - 1 else -1,
								index - _cols if row > y0 else -1, index + _cols if row < y1 - 1 else -1]:
							if next >= 0 and _ocean[next] and _fine_piece[next] < 0:
								_fine_piece[next] = piece
								stack.append(next)
					_piece_rep.append(best)
					_piece_cell.append(cy * coarse_cols + cx)
					graph.add_point(piece, center / COARSE, weight * (COAST_PENALTY if touches_land else 1.0))
	# Side-by-side links, where fine ocean cells touch across a cell edge.
	for row in _rows:
		for col in range(COARSE - 1, _cols - 1, COARSE):
			_link_pieces(graph, row * _cols + col, row * _cols + col + 1)
	for row in range(COARSE - 1, _rows - 1, COARSE):
		for col in _cols:
			_link_pieces(graph, row * _cols + col, (row + 1) * _cols + col)
	# Corner-to-corner links, through a piece in one of the cells between.
	var corner_links := 0
	for piece in _piece_rep.size():
		var cell := _piece_cell[piece]
		for middle: int in graph.get_point_connections(piece):
			for far: int in graph.get_point_connections(middle):
				var far_cell := _piece_cell[far]
				var dx := absi(far_cell % coarse_cols - cell % coarse_cols)
				var dy := absi(far_cell / coarse_cols - cell / coarse_cols)
				if far > piece and dx == 1 and dy == 1 and not graph.are_points_connected(piece, far):
					graph.connect_points(piece, far)
					corner_links += 1
	print("Coarse graph: %d pieces of water in %d x %d cells (%d corner links)" % [_piece_rep.size(), coarse_cols, coarse_rows, corner_links])
	return graph


## Links the pieces two side-by-side fine cells belong to, if both are open ocean.
func _link_pieces(graph: AStar2D, a: int, b: int) -> void:
	var pa := _fine_piece[a]
	var pb := _fine_piece[b]
	if pa >= 0 and pb >= 0 and pa != pb and not graph.are_points_connected(pa, pb):
		graph.connect_points(pa, pb)


## A fine-grid path between two ocean cells: through the reps of the coarse
## route's pieces of water, with any hop that would cross land replaced by a
## short fine-grid search (always short, as linked pieces touch).
func _route(coarse: AStar2D, fine: AStarGrid2D, from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var coarse_path := coarse.get_id_path(_fine_piece[from.y * _cols + from.x], _fine_piece[to.y * _cols + to.x])
	var result: Array[Vector2i] = []
	if coarse_path.is_empty():
		return result
	var waypoints: Array[Vector2i] = [from]
	for k in range(1, coarse_path.size() - 1):
		var rep := _piece_rep[coarse_path[k]]
		waypoints.append(Vector2i(rep % _cols, rep / _cols))
	waypoints.append(to)

	result.append(from)
	for k in range(1, waypoints.size()):
		var a := waypoints[k - 1]
		var b := waypoints[k]
		if _clear_of_land(a, b):
			result.append(b)
			continue
		var hop := fine.get_id_path(a, b)
		if hop.is_empty():
			result.clear()
			return result
		for h in range(1, hop.size()):
			result.append(hop[h])
	return result


## True if the straight line between two cells crosses no land at all.
func _clear_of_land(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var steps := ceili(pa.distance_to(pb) * 2.0)
	for s in range(1, steps):
		var p := pa.lerp(pb, float(s) / steps)
		if _land[floori(p.y) * _cols + floori(p.x)]:
			return false
	return true


func _nearest_water(cell: Vector2i) -> Vector2i:
	for radius in SNAP_RADIUS + 1:
		var best := Vector2i(-1, -1)
		var best_dist := INF
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var c := cell + Vector2i(dx, dy)
				if _in_grid(c) and _ocean[c.y * _cols + c.x] and Vector2(dx, dy).length() < best_dist:
					best_dist = Vector2(dx, dy).length()
					best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Turns a grid path into a short list of (lon, lat) points: straightens it
## wherever there's clear water, then follows great circles on long open legs.
## Longitudes stay continuous (they may run past 180).
func _lane_points(start: Vector2, cells: Array[Vector2i], end: Vector2) -> PackedVector2Array:
	# The route is a list of turning points; fill in every cell along each hop.
	var path: Array[Vector2i] = [cells[0]]
	for k in range(1, cells.size()):
		var a := Vector2(cells[k - 1])
		var delta := Vector2(cells[k] - cells[k - 1])
		var steps := maxi(absi(cells[k].x - cells[k - 1].x), absi(cells[k].y - cells[k - 1].y))
		for s in range(1, steps + 1):
			path.append(Vector2i((a + delta * (float(s) / steps)).round()))

	# Straighten: keep a span as one line if it's clear, otherwise split it in
	# half and try again. Then drop any kept cell the line can skip over.
	var marks := PackedByteArray()
	marks.resize(path.size())
	marks[0] = 1
	marks[-1] = 1
	var spans := [Vector2i(0, path.size() - 1)]
	while not spans.is_empty():
		var span: Vector2i = spans.pop_back()
		if span.y - span.x < 2 or _clear_line(path[span.x], path[span.y]):
			continue
		@warning_ignore("integer_division")
		var mid := (span.x + span.y) / 2
		marks[mid] = 1
		spans.append(Vector2i(span.x, mid))
		spans.append(Vector2i(mid, span.y))
	var candidates: Array[Vector2i] = []
	for k in path.size():
		if marks[k]:
			candidates.append(path[k])
	var kept: Array[Vector2i] = [candidates[0]]
	var i := 0
	while i < candidates.size() - 1:
		var j := i + 1
		while j + 1 < candidates.size() and _clear_line(candidates[i], candidates[j + 1]):
			j += 1
		kept.append(candidates[j])
		i = j

	var points := PackedVector2Array([start])
	for cell in kept:
		points.append(Geo.unproject(_cell_center(cell)))
	points.append(end)
	points = _great_circle_shortcuts(points)

	var out := PackedVector2Array([points[0]])
	for k in range(1, points.size()):
		var a := points[k - 1]
		var b := points[k]
		var pieces := floori(Geo.distance_nm(a, b) / GREAT_CIRCLE_STEP_NM)
		if pieces >= 2 and _arc_clear(a, b, k == 1, k == points.size() - 1):
			var previous_lon := a.x
			for s in range(1, pieces):
				var p := Geo.great_circle_lerp(a, b, float(s) / pieces)
				p.x += roundf((previous_lon - p.x) / Geo.WORLD_WIDTH) * Geo.WORLD_WIDTH
				previous_lon = p.x
				out.append(p)
		out.append(b)
	return out


## Drops turning points a great circle can skip: from each kept point, on to
## the furthest of the next ones the great circle reaches clear of the coast
## (checked every ARC_CHECK_NM), so long ocean legs follow one smooth arc
## instead of bending at every island the grid path steered round.
func _great_circle_shortcuts(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([points[0]])
	var i := 0
	while i < points.size() - 1:
		var j := i + 1
		while j + 1 < points.size() and _arc_clear(points[i], points[j + 1], i == 0, j + 1 == points.size() - 1):
			j += 1
		out.append(points[j])
		i = j
	return out


## True if the great circle between two (lon, lat) points stays off the coast,
## apart from within ARC_PORT_NM of an end that's a port. The arc is followed
## in ARC_CHECK_NM pieces, each checked cell by cell, so no strip of land
## narrower than a piece slips through.
func _arc_clear(a: Vector2, b: Vector2, a_is_port: bool, b_is_port: bool) -> bool:
	# Lanes are stored from their first port's longitude, so a lane heading west
	# across the Pacific runs past -180; check that stretch on the copy of the
	# world 360 degrees east, which the grid also holds.
	if minf(a.x, b.x) < GRID_WEST:
		a.x += Geo.WORLD_WIDTH
		b.x += Geo.WORLD_WIDTH
	var length := Geo.distance_nm(a, b)
	var pieces := maxi(1, ceili(length / ARC_CHECK_NM))
	var previous := _grid_point(a)
	for s in range(1, pieces + 1):
		var t := float(s) / pieces
		var point := _grid_point(b if s == pieces else Geo.great_circle_lerp(a, b, t))
		# Keep the piece on the same copy of the world as the one before it.
		point.x += roundf((previous.x - point.x) / (Geo.WORLD_WIDTH / GRID_CELL)) * Geo.WORLD_WIDTH / GRID_CELL
		var steps := maxi(1, ceili(previous.distance_to(point) * 2.0))
		for k in range(1, steps + 1):
			var along := (t - 1.0 / pieces + float(k) / steps / pieces) * length
			if (a_is_port and along < ARC_PORT_NM) or (b_is_port and length - along < ARC_PORT_NM):
				continue
			var p := previous.lerp(point, float(k) / steps)
			if _is_near_land(Vector2i(floori(p.x), floori(p.y))):
				return false
		previous = point
	return true


## Lays each canal's centerline into a lane that crosses it (at either
## east-west copy of the world), in place of the lane's own grid-fitted points.
func _splice_canals(points: PackedVector2Array) -> PackedVector2Array:
	for canal: Dictionary in _canals:
		for offset in [0.0, Geo.WORLD_WIDTH]:
			var shift := Vector2(offset, 0.0)
			var path := PackedVector2Array()
			for p: Vector2 in canal.path:
				path.append(p + shift)
			var divide := PackedVector2Array()
			for p: Vector2 in canal.divide:
				divide.append(p + shift)
			points = _splice_canal(points, path, divide)
	return points


## Lays the canals into every lane already in data/sea_lanes.res and saves it
## again, for "--canals-only". Lanes already laid in come out unchanged.
func _resplice_lanes() -> void:
	var data: SeaLaneData = load(LANES_OUT)
	var out := SeaLaneData.new()
	var changed := 0
	for i in data.keys.size():
		var points := data.points.slice(data.starts[i], data.starts[i + 1])
		var spliced := _splice_canals(points)
		if spliced != points:
			changed += 1
		out.keys.append(data.keys[i])
		out.starts.append(out.points.size())
		for p in spliced:
			out.points.append(Vector2(snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)))
		out.distances.append(_length_nm(spliced))
	out.starts.append(out.points.size())
	var err := ResourceSaver.save(out, LANES_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % LANES_OUT)
	print("Canals laid into %d of %d lanes" % [changed, out.keys.size()])
	_print_stats(out)


## Lays each port's approach channels into the existing lanes, for
## "--channels-only" (see _lay_channels()).
func _rechannel_lanes() -> void:
	var land_rings := _read_land_rings()
	_build_grid(land_rings)
	land_rings.clear()
	var data: SeaLaneData = load(LANES_OUT)
	var out := _lay_channels(data)
	var err := ResourceSaver.save(out, LANES_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % LANES_OUT)
	_print_stats(out)


## Every port's lanes come in to it along a few shared approach channels
## (like a real port's traffic separation scheme) rather than each on its own
## way: its lanes' ends are gathered by the bearing they come in from (those
## within CHANNEL_SPREAD_DEG of each other together), and each group's last
## CHANNEL_NM nm are made one and the same, the way of the lane nearest the
## middle of the group; the rest leave their own way CHANNEL_JOIN_NM out and
## join the channel's outer end straight across (only where that join is
## clear of the coast; else the lane keeps its own way in). So ships bound
## for a port, from wherever, come in by one of a few known ways, and the
## water between the channels is quiet (for anchorages, and for keeping
## ships clear of each other). Lanes shorter than CHANNEL_MIN_LANE_NM, and
## the ends of lanes at ports on a canal or through one, keep their own ways.
func _lay_channels(data: SeaLaneData) -> SeaLaneData:
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string(PORTS_PATH)).ports
	var canal_ports := {}
	for canal: Dictionary in JSON.parse_string(FileAccess.get_file_as_string(CANALS_PATH)).canals:
		for id: String in canal.get("ports", []):
			canal_ports[id] = true
	var lanes: Array[PackedVector2Array] = []
	for i in data.keys.size():
		lanes.append(data.points.slice(data.starts[i], data.starts[i + 1]))
	# Each port's lane ends: port id -> [[lane index, end (0 at the first port, 1 at the second)], ...].
	var ends := {}
	for i in data.keys.size():
		var ids := data.keys[i].split("-")
		for end in 2:
			var port: String = ids[end]
			if not ends.has(port):
				ends[port] = []
			ends[port].append([i, end])
	var changed := {}
	var refused := 0
	var kept_short := 0
	var channel_counts := []
	for port: Dictionary in ports:
		var id: String = port.id
		if canal_ports.has(id) or not ends.has(id):
			continue
		# Where each of its lanes comes in: [bearing at CHANNEL_NM out, lane, end].
		var entries := []
		for entry: Array in ends[id]:
			var lane: PackedVector2Array = lanes[entry[0]]
			if data.distances[entry[0]] < CHANNEL_MIN_LANE_NM:
				kept_short += 1
				continue
			var inner := _inner_point(lane, entry[1], CHANNEL_JOIN_NM)
			if inner.is_empty():
				continue
			var on_canal := false
			var root: Vector2 = lane[0] if entry[1] == 0 else lane[-1]
			for k in _inner_range(lane, entry[1], int(inner[1])):
				if _on_canal(lane[k]):
					on_canal = true
					break
			if on_canal:
				continue
			var at: Vector2 = _inner_point(lane, entry[1], CHANNEL_NM)[0]
			var bearing := rad_to_deg(_local(root, at).angle())
			entries.append([bearing, entry[0], entry[1]])
		if entries.size() < 2:
			continue
		var groups := _bearing_groups(entries, CHANNEL_SPREAD_DEG)
		channel_counts.append(groups.size())
		for group: Array in groups:
			if group.size() < 2:
				continue
			# The channel: the way in of the lane nearest the group's middle.
			var middle := _mean_bearing(group)
			group.sort_custom(func(a: Array, b: Array) -> bool: return absf(wrapf(a[0] - middle, -180.0, 180.0)) < absf(wrapf(b[0] - middle, -180.0, 180.0)))
			var lead: Array = group[0]
			var lead_lane: PackedVector2Array = lanes[lead[1]]
			var lead_inner := _inner_point(lead_lane, lead[2], CHANNEL_NM)
			var channel := PackedVector2Array([lead_inner[0]])  # From its outer end in to the port.
			for k in _inner_range(lead_lane, lead[2], int(lead_inner[1])):
				channel.append(lead_lane[k])
			var lead_root: Vector2 = lead_lane[0] if lead[2] == 0 else lead_lane[-1]
			for member: Array in group.slice(1):
				var lane: PackedVector2Array = lanes[member[1]]
				var end: int = member[2]
				var join := _inner_point(lane, end, CHANNEL_JOIN_NM)
				var root: Vector2 = lane[0] if end == 0 else lane[-1]
				# The channel's points, on this lane's copy of the world.
				var shift := roundf((root.x - lead_root.x) / Geo.WORLD_WIDTH) * Geo.WORLD_WIDTH
				var way := PackedVector2Array()
				for p in channel:
					way.append(Vector2(p.x + shift, p.y))
				way[-1] = root  # (The same port, at this lane's longitude.)
				if not _arc_clear(join[0], way[0], false, false):
					refused += 1
					continue
				# The lane's own way out to the join, straight to the channel's
				# outer end, then the channel in; the two new corners rounded.
				var outer := PackedVector2Array()
				var corners := []
				if end == 1:
					for k in range(0, int(join[1]) + 1):
						outer.append(lane[k])
					corners = [outer.size(), outer.size() + 1]
					outer.append(join[0])
					outer.append_array(way)
				else:
					var back := way.duplicate()
					back.reverse()  # Port -> channel's outer end.
					outer.append_array(back)
					corners = [outer.size() - 1, outer.size()]
					outer.append(join[0])
					for k in range(int(join[1]), lane.size()):
						outer.append(lane[k])
				lanes[member[1]] = _round_joins(outer, corners)
				changed[member[1]] = true
	var out := SeaLaneData.new()
	for i in data.keys.size():
		out.keys.append(data.keys[i])
		out.starts.append(out.points.size())
		for p in lanes[i]:
			out.points.append(Vector2(snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)))
		out.distances.append(_length_nm(lanes[i]) if changed.has(i) else data.distances[i])
	out.starts.append(out.points.size())
	var most := 0
	var total := 0
	for n: int in channel_counts:
		most = maxi(most, n)
		total += n
	print("Approach channels laid into %d lane ends of %d lanes: %d ports with channels (%.1f each, at most %d); %d joins refused for the coast, %d lane ends of short lanes left alone" % [changed.size(), data.keys.size(), channel_counts.size(), float(total) / maxi(channel_counts.size(), 1), most, refused, kept_short])
	return out


## Where a lane is `nm` along it from one of its ends (0: its first point, 1:
## its last): [the point, the index of the first lane point further out
## than it from that end], or [] if the lane's too short.
func _inner_point(lane: PackedVector2Array, end: int, nm: float) -> Array:
	var along := 0.0
	var n := lane.size()
	for step in range(1, n):
		var i := step if end == 0 else n - 1 - step
		var previous := i - 1 if end == 0 else i + 1
		var piece := Geo.distance_nm(lane[previous], lane[i])
		if along + piece >= nm:
			var t := (nm - along) / maxf(piece, 0.0001)
			return [lane[previous].lerp(lane[i], t), i]
		along += piece
	return []


## The indices of a lane's points from one end (0: its first point, 1: its
## last) in to `outer` (exclusive), outer end first.
static func _inner_range(lane: PackedVector2Array, end: int, outer: int) -> Array:
	var indices := []
	if end == 0:
		for k in range(outer - 1, -1, -1):
			indices.append(k)
	else:
		for k in range(outer + 1, lane.size()):
			indices.append(k)
	return indices


## A (lon, lat) point as east and north nm of a root point.
static func _local(root: Vector2, point: Vector2) -> Vector2:
	return Vector2(wrapf(point.x - root.x, -180.0, 180.0) * 60.0 * maxf(cos(deg_to_rad(root.y)), 0.05), (point.y - root.y) * 60.0)


## Lane ends ([bearing, ...]) gathered into groups no wider than `spread`
## degrees of bearing: cut at the widest gaps round the circle, then any
## group still too wide cut into equal slices.
static func _bearing_groups(entries: Array, spread: float) -> Array:
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var n := entries.size()
	# Start after the widest gap round the circle.
	var widest := -1.0
	var first := 0
	for i in n:
		var gap := wrapf(entries[(i + 1) % n][0] - entries[i][0], 0.0, 360.0) if n > 1 else 360.0
		if gap > widest:
			widest = gap
			first = (i + 1) % n
	var groups := []
	var group := []
	for k in n:
		var entry: Array = entries[(first + k) % n]
		if group.is_empty() or wrapf(entry[0] - group[0][0], 0.0, 360.0) <= spread:
			group.append(entry)
		else:
			groups.append(group)
			group = [entry]
	if not group.is_empty():
		groups.append(group)
	return groups


## The middle bearing of a group of lane ends.
static func _mean_bearing(group: Array) -> float:
	var sum := Vector2.ZERO
	for entry: Array in group:
		sum += Vector2.from_angle(deg_to_rad(entry[0]))
	return rad_to_deg(sum.angle()) if sum.length() > 0.001 else float(group[0][0])


## Rounds the new corners (`corners`: their indices) where a lane joins its
## channel (see _lay_channels()): at the join point and at the channel's outer end.
func _round_joins(points: PackedVector2Array, corners: Array) -> PackedVector2Array:
	var projected := _project_all(points)
	var out := PackedVector2Array()
	var n := points.size()
	for i in n:
		var arc := PackedVector2Array()
		if i in corners and i > 0 and i < n - 1:
			arc = _corner_arc(projected, i)
		if arc.is_empty():
			out.append(points[i])
		else:
			for p in arc:
				var lon_lat := Geo.unproject(p)
				if out.is_empty() or lon_lat.distance_to(out[-1]) > 0.001:
					out.append(lon_lat)
	return out


## The grid is too coarse to follow a canal (lanes can slip through lakes
## beside it, or cut straight across), so lanes are judged by the canal's
## divide, a line along the land between the two seas. A lane that crosses it
## an odd number of times goes through the canal: the stretch from the last
## point before its first crossing to the first point after its last crossing
## (stepping further out past points on the centerline) is replaced by the
## whole centerline. A lane starting or ending at a port on the canal (its
## first or last point is on the centerline) joins it where that port is
## nearest instead of at the canal's end. A lane that crosses an even number
## of times only strays over the divide and back, so that detour is cut out.
func _splice_canal(points: PackedVector2Array, path: PackedVector2Array, divide: PackedVector2Array) -> PackedVector2Array:
	var crossings: Array[int] = []  # Lane segments (by end point) that cross the divide.
	for k in range(1, points.size()):
		for d in range(1, divide.size()):
			if Geometry2D.segment_intersects_segment(points[k - 1], points[k], divide[d - 1], divide[d]) != null:
				crossings.append(k)
				break
	if crossings.is_empty():
		return points
	var along_path := PackedFloat64Array([0.0])
	for k in range(1, path.size()):
		along_path.append(along_path[-1] + path[k - 1].distance_to(path[k]))
	var nearest := []  # Per lane point: [distance, how far along the path, closest path point]
	for p in points:
		var best := [INF, 0.0, Vector2.ZERO]
		for k in range(1, path.size()):
			var q := Geometry2D.get_closest_point_to_segment(p, path[k - 1], path[k])
			var distance := p.distance_to(q)
			if distance < best[0]:
				best = [distance, along_path[k - 1] + path[k - 1].distance_to(q), q]
		nearest.append(best)
	var before := crossings[0] - 1
	var after := crossings[-1]
	if crossings.size() % 2 == 0:
		var out := points.slice(0, before + 1)
		out.append_array(points.slice(after))
		return out
	# Which side it starts on: the side of the path's first end, if the point
	# before the crossing is on the same side of the divide as that end.
	var forward := _same_side(points[before], path[0], divide)
	return _lay_canal(points, path, along_path, nearest, before, after, forward)


## True if two points are on the same side of a divide: the segment between
## them crosses it an even number of times.
static func _same_side(a: Vector2, b: Vector2, divide: PackedVector2Array) -> bool:
	var count := 0
	for d in range(1, divide.size()):
		if Geometry2D.segment_intersects_segment(a, b, divide[d - 1], divide[d]) != null:
			count += 1
	return count % 2 == 0


## Replaces a lane's crossing (between points `before` and `after`, on either
## side) with the centerline, run forward (from its first end) or back; see
## _splice_canal().
func _lay_canal(points: PackedVector2Array, path: PackedVector2Array, along_path: PackedFloat64Array,
		nearest: Array, before: int, after: int, forward: bool) -> PackedVector2Array:
	var first := before
	while first > 0 and nearest[first][0] <= CANAL_SNAP_DEG:
		first -= 1
	var last := after
	while last < points.size() - 1 and nearest[last][0] <= CANAL_SNAP_DEG:
		last += 1
	var total := along_path[-1]
	var at_start: bool = first == 0 and nearest[0][0] <= CANAL_SNAP_DEG
	var at_end: bool = last == points.size() - 1 and nearest[last][0] <= CANAL_SNAP_DEG
	var start_along: float = nearest[first][1] if at_start else (0.0 if forward else total)
	var end_along: float = nearest[last][1] if at_end else (total if forward else 0.0)
	var out := points.slice(0, first + 1)
	out.append(nearest[first][2] if at_start else (path[0] if forward else path[-1]))
	var order := range(path.size()) if forward else range(path.size() - 1, -1, -1)
	for v: int in order:
		if along_path[v] > minf(start_along, end_along) and along_path[v] < maxf(start_along, end_along):
			out.append(path[v])
	out.append(nearest[last][2] if at_end else (path[-1] if forward else path[0]))
	out.append_array(points.slice(last))
	return out


## Turns every corner of a lane into a curve, so ships sweep round bends
## rather than snapping to a new heading: each turning point becomes a circular
## arc (on the map) of TURN_RADIUS_NM, tangent to the legs either side and
## using at most half of each, so neighbouring curves join smoothly. An arc
## that would cross land is tightened (halved, up to CORNER_TRIES times) and
## the corner is kept if none fits. Points on a canal's centerline are left
## as they are (canals and their locks are laid in exactly).
func _round_corners(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var projected := _project_all(points)
	var out := PackedVector2Array([points[0]])
	for i in range(1, points.size() - 1):
		var arc := PackedVector2Array()
		if not _on_canal(points[i]):
			arc = _corner_arc(projected, i)
		if arc.is_empty():
			out.append(points[i])
		else:
			for p in arc:
				# Neighbouring arcs can meet at the same point: keep one.
				var lon_lat := Geo.unproject(p)
				if lon_lat.distance_to(out[-1]) > 0.001:
					out.append(lon_lat)
	if points[-1].distance_to(out[-1]) <= 0.001:
		out.remove_at(out.size() - 1)
	out.append(points[-1])
	return out


## The arc (projected points, from where it leaves the leg in to where it
## joins the leg out) rounding lane point i, or [] to keep the corner.
func _corner_arc(projected: PackedVector2Array, i: int) -> PackedVector2Array:
	var a := projected[i - 1]
	var b := projected[i]
	var c := projected[i + 1]
	var leg_in := b - a
	var leg_out := c - b
	if leg_in.length() < 1e-6 or leg_out.length() < 1e-6:
		return PackedVector2Array()
	var turn := leg_in.angle_to(leg_out)
	if absf(turn) < deg_to_rad(MIN_TURN_DEG) or absf(turn) > PI - 0.01:
		return PackedVector2Array()
	# Near the map's scale there, a projected degree is 60 nm x cos(latitude).
	var nm_per_unit := 60.0 * cos(deg_to_rad(Geo.unproject(b).y))
	var tangent := minf(TURN_RADIUS_NM / nm_per_unit * tan(absf(turn) / 2.0), minf(leg_in.length(), leg_out.length()) * 0.48)
	var port_end := projected[0] if i == 1 else (projected[-1] if i == projected.size() - 2 else Vector2.INF)
	for attempt in CORNER_TRIES:
		var arc := _arc(b, leg_in.normalized(), leg_out.normalized(), tangent, turn)
		if _projected_on_water(arc, port_end):
			return arc
		tangent *= 0.5
	return PackedVector2Array()


## A circular arc round a corner at b, from the leg in (direction u1) to the
## leg out (u2), touching each `tangent` from the corner, in steps of at most
## ARC_STEP_DEG of turn.
static func _arc(b: Vector2, u1: Vector2, u2: Vector2, tangent: float, turn: float) -> PackedVector2Array:
	var start := b - u1 * tangent
	var radius := tangent / tan(absf(turn) / 2.0)
	var center := start + u1.rotated(signf(turn) * PI / 2.0) * radius
	var from_angle := (start - center).angle()
	var steps := maxi(2, ceili(absf(turn) / deg_to_rad(ARC_STEP_DEG)))
	var out := PackedVector2Array()
	for s in steps + 1:
		out.append(center + Vector2.from_angle(from_angle + turn * s / steps) * radius)
	out[-1] = b + u2 * tangent
	return out


## True if a projected polyline crosses no land, allowing land within a few
## cells of a port end (ports sit on the shore).
func _projected_on_water(line: PackedVector2Array, port_end: Vector2) -> bool:
	var port := Vector2.INF
	if port_end != Vector2.INF:
		port = _projected_grid_point(port_end)
	var previous := _projected_grid_point(line[0])
	for k in line.size():
		var point := _projected_grid_point(line[k])
		var steps := maxi(1, ceili(previous.distance_to(point) * 2.0))
		for s in steps + 1:
			var p := previous.lerp(point, float(s) / steps)
			if port != Vector2.INF and p.distance_to(port) < 3.0:
				continue
			if _is_land(Vector2i(floori(p.x), floori(p.y))):
				return false
		previous = point
	return true


## A projected point in fine-grid cell units (see _grid_point()).
func _projected_grid_point(p: Vector2) -> Vector2:
	if p.x < GRID_WEST:
		p.x += Geo.WORLD_WIDTH
	return (p - _grid_origin) / GRID_CELL


## True if a (lon, lat) lane point is on a canal's centerline (at either
## east-west copy of the world).
func _on_canal(p: Vector2) -> bool:
	for canal: Dictionary in _canals:
		for offset in [0.0, Geo.WORLD_WIDTH]:
			var q := p - Vector2(offset, 0.0)
			if not canal.bounds.has_point(q):
				continue
			var path: PackedVector2Array = canal.path
			for k in range(1, path.size()):
				if q.distance_to(Geometry2D.get_closest_point_to_segment(q, path[k - 1], path[k])) < 0.001:
					return true
	return false


## True if the straight (projected) line between two cells stays off the
## coast, apart from right next to either end.
func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	var pa := Vector2(a) + Vector2(0.5, 0.5)
	var pb := Vector2(b) + Vector2(0.5, 0.5)
	var steps := ceili(pa.distance_to(pb) * 2.0)
	for s in range(1, steps):
		var p := pa.lerp(pb, float(s) / steps)
		var cell := Vector2i(floori(p.x), floori(p.y))
		var near_end := p.distance_to(pa) < 2.5 or p.distance_to(pb) < 2.5
		if _is_land(cell) or (_is_near_land(cell) and not near_end):
			return false
	return true


func _length_nm(points: PackedVector2Array) -> float:
	var distance := 0.0
	for k in range(1, points.size()):
		distance += Geo.distance_nm(points[k - 1], points[k])
	return distance


func _print_stats(data: SeaLaneData) -> void:
	var by_key := {}
	for i in data.keys.size():
		by_key[data.keys[i]] = data.distances[i]
	var longest := 0.0
	var longest_key := ""
	var longest_med_us := 0.0
	var med := ["ALG", "ALY", "ASH", "BCN", "BIA", "CAG", "GIT", "GOA", "HFA", "IST", "IZM", "KOP", "LMS", "MER", "MLA", "MRS", "PIR", "PMI", "PMO", "PSD", "ROM", "SPE", "TNG", "TUN", "VLC"]
	var us_east := ["BOS", "NYC", "MIA"]
	for key: String in by_key:
		var ids := key.split("-")
		if by_key[key] > longest:
			longest = by_key[key]
			longest_key = key
		if ((ids[0] in med) and (ids[1] in us_east)) or ((ids[1] in med) and (ids[0] in us_east)):
			longest_med_us = maxf(longest_med_us, by_key[key])
	print("Rome-Tunis: %.1f nm" % by_key.get("ROM-TUN", -1.0))
	print("Longest Med-US East leg: %.1f nm" % longest_med_us)
	print("Longest leg overall: %s %.1f nm" % [longest_key, longest])
	for key: String in ["ALG-TNG", "ALG-NYC", "GIT-MLA", "IST-PIR", "BCN-VLC", "RTM-SHA", "LAX-SHA", "NYC-RTM", "HAM-SIN", "ANC-SEA", "BLB-CLN", "LAX-NYC", "PMO-TUN", "BIA-GOA"]:
		print("  %s: %.1f nm" % [key, by_key.get(key, -1.0)])


## "--check": whether some key spots are land, water, or water connected to the
## ocean, without building any lanes (the port snapping above reports ports
## that can't reach water).
func _print_water_check() -> void:
	var spots := {
		"Lake Superior": Vector2(-87.5, 47.6), "Lake Michigan": Vector2(-87.0, 43.5), "Lake Huron": Vector2(-82.5, 44.5),
		"Lake Erie": Vector2(-81.5, 42.2), "Lake Ontario": Vector2(-77.8, 43.6), "Lake St. Clair": Vector2(-82.7, 42.45),
		"St. Lawrence at Quebec": Vector2(-71.2, 46.81), "St. Lawrence at Montreal": Vector2(-73.52, 45.55),
		"St. Lawrence at Kingston": Vector2(-76.5, 44.15), "Welland mid": Vector2(-79.21, 43.15),
		"Detroit River": Vector2(-83.10, 42.25), "St. Marys River": Vector2(-84.30, 46.48),
		"McMurdo Sound": Vector2(166.4, -77.7), "Ross Sea": Vector2(175.0, -75.0),
	}
	for spot_name: String in spots:
		var cell := _cell_of(Geo.project(spots[spot_name]))
		var index := cell.y * _cols + cell.x
		var state := "outside grid" if not _in_grid(cell) else ("LAND" if _land[index] else ("ocean" if _ocean[index] else "water, NOT connected"))
		print("  %s: %s" % [spot_name, state])


## "--audit": finds lanes with pointless detours. A lane has one where two of
## its points could be joined by a straight line over open water that saves at
## least AUDIT_MIN_SAVING_NM and AUDIT_MIN_RATIO of the way the lane goes
## between them (an out-and-back spur into a bay, or a loop). Prints how many
## lanes have one, the worst, and where they cluster, and writes every one to
## AUDIT_OUT.
func _audit_lanes() -> void:
	var started := Time.get_ticks_msec()
	var args := OS.get_cmdline_user_args()
	var path := args[args.find("--from") + 1] if "--from" in args else LANES_OUT
	var data: SeaLaneData = load(path)
	var found := []  # [saving nm, key, detour start (lon, lat), detour end]
	var hotspots := {}  # 5-degree square -> [count, worst key, worst saving]
	for lane in data.keys.size():
		var points := data.points.slice(data.starts[lane], data.starts[lane + 1])
		var detour := _worst_detour(points)
		if detour.is_empty():
			continue
		found.append([detour[0], data.keys[lane], points[detour[1]], points[detour[2]]])
		var middle: Vector2 = (points[detour[1]] + points[detour[2]]) / 2.0
		var square := "%d,%d" % [floori(wrapf(middle.x, -180.0, 180.0) / 5.0) * 5, floori(middle.y / 5.0) * 5]
		var spot: Array = hotspots.get(square, [0, "", 0.0])
		spot[0] += 1
		if detour[0] > spot[2]:
			spot[1] = data.keys[lane]
			spot[2] = detour[0]
		hotspots[square] = spot
	found.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("Lanes with a detour of %d nm or more: %d of %d (%.0f s)" % [AUDIT_MIN_SAVING_NM, found.size(), data.keys.size(),
		(Time.get_ticks_msec() - started) / 1000.0])
	print("Worst:")
	for entry: Array in found.slice(0, 30):
		print("  %s: %d nm wasted, from %s to %s" % [entry[1], roundi(entry[0]), _lon_lat_text(entry[2]), _lon_lat_text(entry[3])])
	var squares := hotspots.keys()
	squares.sort_custom(func(a: String, b: String) -> bool: return hotspots[a][0] > hotspots[b][0])
	print("Hotspots (5-degree squares by lon,lat of the detour; lanes, worst):")
	for square: String in squares.slice(0, 25):
		var spot: Array = hotspots[square]
		print("  %s: %d lanes, worst %s (%d nm)" % [square, spot[0], spot[1], roundi(spot[2])])
	var file := FileAccess.open(AUDIT_OUT, FileAccess.WRITE)
	for entry: Array in found:
		file.store_line("%s\t%d\t%s\t%s" % [entry[1], roundi(entry[0]), _lon_lat_text(entry[2]), _lon_lat_text(entry[3])])
	print("All of them: %s" % ProjectSettings.globalize_path(AUDIT_OUT))


## A lane's worst detour: [nm it wastes, index of the point it leaves from,
## index of the point it could have gone straight to], or [] if it has none
## (see _audit_lanes(); add "--from res://build/old_sea_lanes.res" to audit another
## lanes file).
func _worst_detour(points: PackedVector2Array) -> Array:
	var along := PackedFloat64Array([0.0])
	for k in range(1, points.size()):
		along.append(along[-1] + Geo.distance_nm(points[k - 1], points[k]))
	var worst := []
	for i in points.size():
		for j in range(i + 2, mini(i + AUDIT_WINDOW, points.size())):
			var sailed := along[j] - along[i]
			if sailed < AUDIT_MIN_SAVING_NM:
				continue
			# A quick flat-earth distance first; the land check only for real candidates.
			var mid_lat := deg_to_rad((points[i].y + points[j].y) / 2.0)
			var direct := Vector2((points[j].x - points[i].x) * cos(mid_lat), points[j].y - points[i].y).length() * 60.0
			var saving := sailed - direct
			if saving < AUDIT_MIN_SAVING_NM or sailed < direct * AUDIT_MIN_RATIO:
				continue
			if not worst.is_empty() and saving <= worst[0]:
				continue
			if _open_water_between(points[i], points[j], i == 0, j == points.size() - 1):
				worst = [saving, i, j]
	return worst


## True if the straight (projected) line between two lane points crosses no
## land, allowing land right at a port end (ports sit on the shore).
func _open_water_between(a: Vector2, b: Vector2, a_is_port: bool, b_is_port: bool) -> bool:
	var pa := _grid_point(a)
	var pb := _grid_point(b)
	var steps := ceili(pa.distance_to(pb) * 2.0)
	for s in range(1, steps):
		var p := pa.lerp(pb, float(s) / steps)
		if (a_is_port and p.distance_to(pa) < 3.0) or (b_is_port and p.distance_to(pb) < 3.0):
			continue
		var cell := Vector2i(floori(p.x), floori(p.y))
		if _is_land(cell):
			return false
	return true


## A (lon, lat) lane point in fine-grid cell units, moved a world east if it's
## west of the grid (lanes are stored from their first port's real longitude).
func _grid_point(lon_lat: Vector2) -> Vector2:
	var lon := lon_lat.x + (Geo.WORLD_WIDTH if lon_lat.x < GRID_WEST else 0.0)
	return (Geo.project(Vector2(lon, lon_lat.y)) - _grid_origin) / GRID_CELL


static func _lon_lat_text(p: Vector2) -> String:
	var lon := wrapf(p.x, -180.0, 180.0)
	return "%.1f%s %.1f%s" % [absf(p.y), "N" if p.y >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"]


## BIOME_SIMPLIFY, or "-- --biome-simplify=0.2" to try another.
static func _biome_simplify() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--biome-simplify="):
			return float(arg.get_slice("=", 1))
	return BIOME_SIMPLIFY



# --- Currents' second ways round ------------------------------------------

## The currents' rides (see _plan_current_ways()): each current, with the
## ones it flows on into (one's end within CHAIN_NM of the next's start), cut
## into stretches RIDE_STEP_NM long.
const RIDE_STEP_NM := 25.0
const CHAIN_NM := 400.0
## Lanes are looked at in stretches at most this long (nm), and a ride
## counts as alongside a lane where it's within RIDE_REACH_NM of it (looked
## up on a grid of RIDE_CELL_DEG cells: per cell, each ride's nearest point).
const LANE_STEP_NM := 50.0
const RIDE_REACH_NM := 360.0
const RIDE_CELL_DEG := 1.0
## "--why" with --currents-only: each candidate and why it was or wasn't kept.
var _why_currents := false
## Per RIDE_CELL_DEG cell (see _ride_cells()): [[ride, point, nm], ...].
var _ride_near := {}


## Plans each lane's second ways round on the currents (game_config
## currents; "-- --currents-only", into the existing lanes). Where a current
## runs alongside a lane (within RIDE_REACH_NM, its points going the same way
## along it for at least ride_min_nm), a ship could leave the lane, ride the
## current and rejoin the lane further on: that way round is planned for each
## direction, at least cut_nm from either port (beyond the approach channels),
## and kept for a direction if it saves at least min_gain of the lane's time
## in some months, at most max_detour times as long as the stretch it leaves
## out. The months it's quicker in are kept with it, so ships take it then
## (GameData.lane()); a current that turns with the monsoon gives one way its
## summer route and the other its winter one. Lanes to or from the Arctic are
## left as they are. "--pairs A-B,C-D" plans just those lanes (dropping the
## rest's second ways); "--why" says what it found.
func _plan_current_ways() -> void:
	var started := Time.get_ticks_msec()
	var land_rings := _read_land_rings()
	_build_grid(land_rings)
	land_rings.clear()
	var coarse := _build_coarse_graph()
	var astar := _fine_astar()
	_set_arctic_blocked(coarse, astar, true)
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game_config.json")).currents
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string(PORTS_PATH)).ports
	var arctic := {}
	for port: Dictionary in ports:
		if bool(port.get("arctic", false)):
			arctic[port.id] = true
	var currents := Currents.shared()
	var rides := []
	for chain: Dictionary in _current_chains(currents):
		rides.append(_ride(currents, chain, float(settings.ref_speed_kn), float(settings.limit)))
	_ride_cells(rides)
	print("Rides: %d, near %d cells" % [rides.size(), _ride_near.size()])
	var data: SeaLaneData = load(LANES_OUT)
	data.variant_keys = PackedStringArray()
	data.variant_months = PackedInt32Array()
	data.variant_currents = PackedStringArray()
	data.variant_starts = PackedInt32Array()
	data.variant_points = PackedVector2Array()
	data.variant_distances = PackedFloat32Array()
	var args := OS.get_cmdline_user_args()
	_why_currents = "--why" in args
	var only := {}
	if "--pairs" in args:
		for pair: String in args[args.find("--pairs") + 1].split(","):
			only[pair] = true
	var tried := 0
	var by_current := {}
	var by_month := PackedInt32Array()
	by_month.resize(13)
	for i in data.keys.size():
		if data.keys[i].contains("@"):
			continue  # (A fishing ground's lane: see _plan_fishing_lanes().)
		var ids := data.keys[i].split("-")
		if arctic.has(ids[0]) or arctic.has(ids[1]):
			continue
		if not only.is_empty() and not only.has(data.keys[i]):
			continue
		if data.distances[i] < float(settings.cut_nm) * 2.0 + float(settings.ride_min_nm):
			continue
		var points := data.points.slice(data.starts[i], data.starts[i + 1])
		if _through_canal(points):
			continue  # (Lanes through a canal keep their one way: their canal crossings stay as they are.)
		if _why_currents:
			print("  %s" % data.keys[i])
		var found := _current_ways(points, rides, currents, settings, coarse, astar)
		for direction in 2:
			var way: Dictionary = found[direction]
			tried += int(way.get("tried", 0))
			if not way.has("points"):
				continue
			data.variant_keys.append("%s>%s" % [ids[direction], ids[1 - direction]])
			data.variant_months.append(way.months)
			data.variant_currents.append(way.current)
			data.variant_starts.append(data.variant_points.size())
			for p: Vector2 in way.points:
				data.variant_points.append(Vector2(snappedf(p.x, 0.0001), snappedf(p.y, 0.0001)))
			data.variant_distances.append(_length_nm(way.points))
			by_current[way.current] = int(by_current.get(way.current, 0)) + 1
			for m in 13:
				if int(way.months) & (1 << m):
					by_month[m] += 1
		if i % 2000 == 0:
			print("  %d / %d lanes, %d second ways (%.0f s)" % [i, data.keys.size(), data.variant_keys.size(), (Time.get_ticks_msec() - started) / 1000.0])
	data.variant_starts.append(data.variant_points.size())
	var err := ResourceSaver.save(data, LANES_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % LANES_OUT)
	var seasonal := 0
	for months: int in data.variant_months:
		if months & 0xfff != 0xfff:
			seasonal += 1
	print("Second ways: %d (%d routed), %d seasonal, the rest quicker all year" % [data.variant_keys.size(), tried, seasonal])
	print("  by month (Jan..Dec, average): %s" % [by_month])
	print("  by current: %s" % [by_current])
	print("Done in %.1f min" % ((Time.get_ticks_msec() - started) / 60000.0))


## Every current with the ones it flows on into (see CHAIN_NM), as
## {id ("gulf_stream+north_atlantic"), flow}.
func _current_chains(currents: Currents) -> Array:
	var chains := []
	for first in currents.list.size():
		var order := [first]
		var flow: PackedVector2Array = (currents.list[first].flow as PackedVector2Array).duplicate()
		while order.size() < 5:
			var end := flow[flow.size() - 1]
			var next := -1
			var next_shift := 0.0
			for j in currents.list.size():
				if order.has(j):
					continue
				var start: Vector2 = currents.list[j].flow[0]
				var shift := roundf((end.x - start.x) / 360.0) * 360.0
				if Geo.distance_nm(end, start + Vector2(shift, 0.0)) < CHAIN_NM:
					next = j
					next_shift = shift
					break
			if next < 0:
				break
			order.append(next)
			var more: PackedVector2Array = currents.list[next].flow
			for k in more.size():
				var p := more[k] + Vector2(next_shift, 0.0)
				if k > 0 or p.distance_to(end) > 0.01:
					flow.append(p)
		var ids := PackedStringArray()
		for index: int in order:
			ids.append(currents.list[index].id)
		chains.append({id = "+".join(ids), flow = flow})
	return chains


## A current's ride: {id, points, miles, hours (per month, 0-11 then the
## year's average: the hours to each point at the reference speed with the
## current)}.
func _ride(currents: Currents, item: Dictionary, ref_speed: float, limit: float) -> Dictionary:
	var flow: PackedVector2Array = item.flow
	var points := PackedVector2Array([flow[0]])
	for k in range(1, flow.size()):
		var steps := maxi(ceili(Geo.distance_nm(flow[k - 1], flow[k]) / RIDE_STEP_NM), 1)
		for s in range(1, steps + 1):
			points.append(flow[k - 1].lerp(flow[k], float(s) / steps))
	var miles := PackedFloat64Array([0.0])
	for k in range(1, points.size()):
		miles.append(miles[k - 1] + Geo.distance_nm(points[k - 1], points[k]))
	var hours := []
	for m in 13:
		var each := PackedFloat64Array([0.0])
		for k in range(1, points.size()):
			var a := points[k - 1]
			var b := points[k]
			var way := Vector2((b.x - a.x) * cos(deg_to_rad((a.y + b.y) / 2.0)), b.y - a.y).normalized()
			var push := currents.velocity(a.lerp(b, 0.5), m).dot(way)
			var factor := clampf((ref_speed + push) / ref_speed, 1.0 - limit, 1.0 + limit)
			each.append(each[k - 1] + (miles[k] - miles[k - 1]) / (ref_speed * factor))
		hours.append(each)
	return {id = item.id, points = points, miles = miles, hours = hours}


## Fills _ride_near: per RIDE_CELL_DEG cell within RIDE_REACH_NM of a ride,
## that ride's nearest point and how far it is from the cell's middle.
func _ride_cells(rides: Array) -> void:
	_ride_near.clear()
	var best := {}  # Vector3i(x, y, ride) -> [point, nm]
	var reach_deg := RIDE_REACH_NM / 60.0
	for r in rides.size():
		var points: PackedVector2Array = rides[r].points
		for k in points.size():
			var p := points[k]
			var wide := reach_deg / maxf(cos(deg_to_rad(p.y)), 0.2)
			for y in range(floori((p.y - reach_deg) / RIDE_CELL_DEG), floori((p.y + reach_deg) / RIDE_CELL_DEG) + 1):
				for x in range(floori((p.x - wide) / RIDE_CELL_DEG), floori((p.x + wide) / RIDE_CELL_DEG) + 1):
					var middle := Vector2((x + 0.5) * RIDE_CELL_DEG, (y + 0.5) * RIDE_CELL_DEG)
					var nm := Geo.distance_nm(middle, p)
					if nm > RIDE_REACH_NM:
						continue
					var key := Vector3i(posmod(x, roundi(360.0 / RIDE_CELL_DEG)), y, r)
					if not best.has(key) or nm < best[key][1]:
						best[key] = [k, nm]
	for key: Vector3i in best:
		var cell := Vector2i(key.x, key.y)
		if not _ride_near.has(cell):
			_ride_near[cell] = []
		_ride_near[cell].append([key.z, best[key][0], best[key][1]])


## A lane's points with none further apart than LANE_STEP_NM (straight in
## the projection between them, as the map draws them).
static func _dense_lane(lane: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array([lane[0]])
	for k in range(1, lane.size()):
		var steps := maxi(ceili(Geo.distance_nm(lane[k - 1], lane[k]) / LANE_STEP_NM), 1)
		var a := Geo.project(lane[k - 1])
		var b := Geo.project(lane[k])
		for s in range(1, steps + 1):
			out.append(Geo.unproject(a.lerp(b, float(s) / steps)) if s < steps else lane[k])
	return out


## The hours along a ride from its point `from` to `to` (either way along it)
## at the reference speed, in a month.
static func _ride_hours(ride: Dictionary, from: int, to: int, month: int, ref_speed: float, limit: float) -> float:
	var hours: PackedFloat64Array = ride.hours[month]
	if to >= from:
		return hours[to] - hours[from]
	# Against the way its path runs: the push the other way round.
	var total := 0.0
	var miles: PackedFloat64Array = ride.miles
	for k in range(to + 1, from + 1):
		var length := miles[k] - miles[k - 1]
		var forward := hours[k] - hours[k - 1]
		var factor := length / (ref_speed * forward) if forward > 0.0 else 1.0
		total += length / (ref_speed * clampf(2.0 - factor, 1.0 - limit, 1.0 + limit))
	return total


## The hours a stretch of points takes at the reference speed with its
## currents, in a month.
static func _way_hours(currents: Currents, points: PackedVector2Array, month: int, ref_speed: float, limit: float) -> float:
	var projected := PackedVector2Array([Geo.project(points[0])])
	var miles := PackedFloat64Array([0.0])
	for k in range(1, points.size()):
		projected.append(Geo.project(points[k]))
		miles.append(miles[k - 1] + Geo.distance_nm(points[k - 1], points[k]))
	return currents.lane_hours(projected, miles, month, ref_speed, limit)


## A lane's best second way round on a current each way (see
## _plan_current_ways()): [first port to second, second to first], each
## {points, months, current, tried} or just {tried}.
func _current_ways(lane: PackedVector2Array, rides: Array, currents: Currents, settings: Dictionary, coarse: AStar2D, astar: AStarGrid2D) -> Array:
	var ref_speed := float(settings.ref_speed_kn)
	var limit := float(settings.limit)
	var min_gain := float(settings.min_gain)
	var detour := float(settings.max_detour)
	var way := _dense_lane(lane)
	var count := way.size()
	var out := [{tried = 0}, {tried = 0}]
	var miles := PackedFloat64Array([0.0])
	for k in range(1, count):
		miles.append(miles[k - 1] + Geo.distance_nm(way[k - 1], way[k]))
	var total := miles[count - 1]
	# Which shift of 360 puts the lane in the grid (it runs GRID_WEST to GRID_EAST).
	var shift := INF
	for s: float in [0.0, 360.0, -360.0]:
		var fits := true
		for p in way:
			if p.x + s < GRID_WEST + 0.5 or p.x + s > GRID_EAST - 0.5:
				fits = false
				break
		if fits:
			shift = s
			break
	if shift == INF:
		return out
	# Each ride's nearest point to each of the lane's points (away from the ports), where near.
	var cut := float(settings.cut_nm)
	var near := {}  # ride -> [[lane point, ride point, nm], ...] in lane order
	for i in count:
		if miles[i] < cut or total - miles[i] < cut:
			continue
		var p := way[i]
		var cell := Vector2i(posmod(floori(p.x / RIDE_CELL_DEG), roundi(360.0 / RIDE_CELL_DEG)), floori(p.y / RIDE_CELL_DEG))
		for entry: Array in _ride_near.get(cell, []):
			if not near.has(entry[0]):
				near[entry[0]] = []
			near[entry[0]].append([i, entry[1], entry[2]])
	if near.is_empty():
		return out
	# The lane's hours to each point, each way, each month (see _cumulative_hours()).
	var reversed := way.duplicate()
	reversed.reverse()
	var lane_cum := [[], []]
	for m in 13:
		lane_cum[0].append(_cumulative_hours(currents, way, m, ref_speed, limit))
		lane_cum[1].append(_cumulative_hours(currents, reversed, m, ref_speed, limit))
	var threshold := total / ref_speed * min_gain  # (Hours: the least saving that counts.)
	var best_score := [0.0, 0.0]
	for r: int in near:
		var ride: Dictionary = rides[r]
		var ride_miles: PackedFloat64Array = ride.miles
		var ride_points: PackedVector2Array = ride.points
		var run := _steady_run(near[r])
		if run.size() < 2:
			continue
		var half := run.size() / 2
		var early := _spread(run.slice(0, half + 1), 8)
		var late := _spread(run.slice(half), 8)
		for direction in 2:
			# Leave the lane at one of the run's points and rejoin at a later one (going this way).
			var leaves := early if direction == 0 else late
			var joins := late if direction == 0 else early
			var cum: Array = lane_cum[direction]
			var best := {}
			var best_gain := 0.0
			for leave: Array in leaves:
				var off_nm := Geo.distance_nm(way[leave[0]], _near_copy(ride_points[leave[1]], way[leave[0]]))
				var at_leave: int = leave[0] if direction == 0 else count - 1 - leave[0]
				for join: Array in joins:
					var at_join: int = join[0] if direction == 0 else count - 1 - join[0]
					if at_join <= at_leave:
						continue
					var ride_nm := absf(ride_miles[join[1]] - ride_miles[leave[1]])
					if ride_nm < float(settings.ride_min_nm):
						continue
					var on_nm := Geo.distance_nm(_near_copy(ride_points[join[1]], way[join[0]]), way[join[0]])
					var stretch := absf(miles[join[0]] - miles[leave[0]])
					if off_nm + ride_nm + on_nm > stretch * detour:
						continue
					var gain := 0.0
					for m in 12:
						var part: float = cum[m][at_join] - cum[m][at_leave]
						var mine := (off_nm + on_nm) / ref_speed + _ride_hours(ride, leave[1], join[1], m, ref_speed, limit)
						gain += maxf(part - mine - threshold, 0.0)
					if gain > best_gain:
						best_gain = gain
						best = {leave = leave, join = join, at_leave = at_leave, at_join = at_join, off = off_nm, ride = ride_nm, on = on_nm}
			if best.is_empty():
				continue
			if _why_currents:
				print("    %s %s: off %.0f, ride %.0f, on %.0f nm; est. %.1f h over the threshold in a year" % [ride.id, ["there", "back"][direction], best.off, best.ride, best.on, best_gain])
			out[direction].tried = int(out[direction].tried) + 1
			var leave_pair: Array = best.leave
			var join_pair: Array = best.join
			var middle := _ride_way(way[leave_pair[0]] + Vector2(shift, 0.0), way[join_pair[0]] + Vector2(shift, 0.0), ride_points,
				leave_pair[1], join_pair[1], _near_shift(ride_points[leave_pair[1]], way[leave_pair[0]]) + shift, coarse, astar)
			if middle.is_empty():
				if _why_currents:
					print("      couldn't be sailed")
				continue
			# The whole way, in the grid's longitudes (rounding looks at the grid), then put back.
			var oriented := way if direction == 0 else reversed
			var whole := PackedVector2Array()
			for k in int(best.at_leave):
				whole.append(oriented[k] + Vector2(shift, 0.0))
			whole.append_array(middle)
			for k in range(int(best.at_join) + 1, count):
				whole.append(oriented[k] + Vector2(shift, 0.0))
			whole = _splice_canals(whole)
			whole = _round_corners(whole)
			for k in whole.size():
				whole[k].x -= shift
			var length := _length_nm(whole)
			if length - total > absf(miles[join_pair[0]] - miles[leave_pair[0]]) * (detour - 1.0):
				if _why_currents:
					print("      too long once sailed: %.0f nm vs %.0f" % [length, total])
				continue
			var months := 0
			var score := 0.0
			for m in 13:
				var lane_h: float = cum[m][count - 1]
				var mine := _way_hours(currents, whole, m, ref_speed, limit)
				if mine < lane_h - threshold:
					months |= 1 << m
					if m < 12:
						score += lane_h - mine
			if _why_currents:
				print("      routed: %.0f nm vs %.0f; months %s, %.1f h saved over the year" % [length, total, String.num_int64(months, 2).lpad(13, "0").reverse(), score])
			if months != 0 and score > best_score[direction]:
				best_score[direction] = score
				out[direction] = {points = whole, months = months, current = ride.id, tried = out[direction].tried}
	return out


## The hours to each of a way's points at the reference speed with its
## currents, in a month (each stretch between points at its middle's push).
static func _cumulative_hours(currents: Currents, points: PackedVector2Array, month: int, ref_speed: float, limit: float) -> PackedFloat64Array:
	var hours := PackedFloat64Array([0.0])
	for k in range(1, points.size()):
		var a := points[k - 1]
		var b := points[k]
		var nm := Geo.distance_nm(a, b)
		var way := Vector2((b.x - a.x) * cos(deg_to_rad((a.y + b.y) / 2.0)), b.y - a.y)
		var factor := 1.0
		if way.length_squared() > 0.0:
			var push := currents.velocity(a.lerp(b, 0.5), month).dot(way.normalized())
			factor = clampf((ref_speed + push) / ref_speed, 1.0 - limit, 1.0 + limit)
		hours.append(hours[k - 1] + nm / (ref_speed * factor))
	return hours


## At most `most` of a list's items, spread evenly over it (its ends kept).
static func _spread(items: Array, most: int) -> Array:
	if items.size() <= most:
		return items
	var out := []
	for k in most:
		out.append(items[roundi(float(k) * (items.size() - 1) / (most - 1))])
	return out


## The longest run of [lane point, ride point, nm] (in lane order) whose ride
## points go steadily one way (a ride doubling back, or coming near the lane
## twice, starts a new run).
static func _steady_run(pairs: Array) -> Array:
	var best := []
	var run := []
	var sign := 0
	for pair: Array in pairs:
		if run.is_empty():
			run = [pair]
			sign = 0
			continue
		var last: Array = run[run.size() - 1]
		var step: int = pair[1] - last[1]
		var gap: int = pair[0] - last[0]
		var going := signi(step)
		if gap <= 2 and (step == 0 or sign == 0 or going == sign):
			run.append(pair)
			if going != 0:
				sign = going
		else:
			if run.size() > best.size():
				best = run
			run = [pair]
			sign = 0
	if run.size() > best.size():
		best = run
	return best if best.size() >= 2 else []


## A ride's point moved by whole turns of the globe to be nearest `to` (lanes
## and rides keep their longitudes running on past 180 their own ways).
static func _near_copy(p: Vector2, to: Vector2) -> Vector2:
	return p + Vector2(_near_shift(p, to), 0.0)


static func _near_shift(p: Vector2, to: Vector2) -> float:
	return roundf((to.x - p.x) / 360.0) * 360.0


## The middle of a second way round (in the grid's longitudes): from the lane
## at `from` out to the ride's point `entry`, along the ride to `exit` (either
## way along it), and back to the lane at `to`. [] if it can't be sailed.
func _ride_way(from: Vector2, to: Vector2, points: PackedVector2Array, entry: int, exit: int, lon_shift: float, coarse: AStar2D, astar: AStarGrid2D) -> PackedVector2Array:
	var ride := PackedVector2Array()
	var step := 1 if exit >= entry else -1
	for k in range(entry, exit + step, step):
		ride.append(points[k] + Vector2(lon_shift, 0.0))
	for p in ride:
		if p.x < GRID_WEST + 0.5 or p.x > GRID_EAST - 0.5:
			return PackedVector2Array()
	var out := PackedVector2Array()
	# Out to the current, the way a lane is found.
	var start := _nearest_water(_cell_of(Geo.project(from)))
	var on := _nearest_water(_cell_of(Geo.project(ride[0])))
	if start.x < 0 or on.x < 0:
		return PackedVector2Array()
	var cells := _route(coarse, astar, start, on)
	if cells.is_empty():
		return PackedVector2Array()
	out.append_array(_lane_points(from, cells, ride[0]))
	# Along it, hop by hop (round any land between with the fine grid).
	for k in range(1, ride.size()):
		var a := _nearest_water(_cell_of(Geo.project(ride[k - 1])))
		var b := _nearest_water(_cell_of(Geo.project(ride[k])))
		if a.x < 0 or b.x < 0:
			return PackedVector2Array()
		if not _clear_of_land(a, b):
			var hop := astar.get_id_path(a, b)
			if hop.is_empty() or hop.size() > 400:
				return PackedVector2Array()
			for h in range(1, hop.size() - 1):
				out.append(Geo.unproject(_cell_center(hop[h])))
		out.append(ride[k])
	# And back in to the lane.
	var off := _nearest_water(_cell_of(Geo.project(ride[ride.size() - 1])))
	var end := _nearest_water(_cell_of(Geo.project(to)))
	if off.x < 0 or end.x < 0:
		return PackedVector2Array()
	cells = _route(coarse, astar, off, end)
	if cells.is_empty():
		return PackedVector2Array()
	out.append_array(_lane_points(ride[ride.size() - 1], cells, to).slice(1))
	return out


## True if a lane runs through one of data/canals.json's canals (it has a
## point on or right by a canal's course).
func _through_canal(points: PackedVector2Array) -> bool:
	for canal: Dictionary in _canals:
		var bounds: Rect2 = canal.bounds
		for p in points:
			if bounds.has_point(p) or bounds.has_point(p - Vector2(360.0, 0.0)) or bounds.has_point(p + Vector2(360.0, 0.0)):
				return true
	return false


# --- Fishing grounds' lanes -------------------------------------------------

## Fishing lanes ("-- --fishing-only", into the existing lanes; run last,
## after the lanes, channels and currents): from each of a fishing ground's
## nearest ports (data/fisheries.json grounds) a lane out to the ground,
## routed round the land like any lane, keyed "PORT-@ground" (the ground's
## end, its middle on the water). A boat's trip is its base's lane to one of
## those ports, then out along that lane (Fisheries.legs()).
const FISHING_PORTS := 4
const FISHING_MAX_NM := 2500.0
## And a fishing route straight out to it from every port within this (as the
## crow flies; the reach of the tier 3 boats), so a boat based there sails
## straight out to it and home, not by way of another port.
const FISHING_DIRECT_NM := 1600.0

func _plan_fishing_lanes() -> void:
	var started := Time.get_ticks_msec()
	var land_rings := _read_land_rings()
	_build_grid(land_rings)
	land_rings.clear()
	var coarse := _build_coarse_graph()
	var astar := _fine_astar()
	_set_arctic_blocked(coarse, astar, false)
	var fish: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fisheries.json"))
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string(PORTS_PATH)).ports
	var old: SeaLaneData = load(LANES_OUT)
	# Everything but the old fishing lanes, as it was.
	var data := SeaLaneData.new()
	for i in old.keys.size():
		if old.keys[i].contains("@"):
			continue
		data.keys.append(old.keys[i])
		data.starts.append(data.points.size())
		data.points.append_array(old.points.slice(old.starts[i], old.starts[i + 1]))
		data.distances.append(old.distances[i])
	for field: String in ["variant_keys", "variant_months", "variant_currents", "variant_starts", "variant_points", "variant_distances"]:
		data.set(field, old.get(field))
	var made := 0
	for ground: Dictionary in fish.grounds:
		var middle := Vector2(float(ground.lon), float(ground.lat))
		var near := ports.duplicate()
		near.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return Geo.distance_nm(middle, Vector2(a.lon, a.lat)) < Geo.distance_nm(middle, Vector2(b.lon, b.lat)))
		var count := 0
		for port: Dictionary in near:
			var away := Geo.distance_nm(middle, Vector2(port.lon, port.lat))
			if away > FISHING_MAX_NM or (count >= FISHING_PORTS and away > FISHING_DIRECT_NM):
				break
			var best := PackedVector2Array()
			var best_nm := INF
			# The ground's end at its own longitude, or a turn of the globe either way (the Pacific seam).
			for shift: float in [0.0, 360.0, -360.0]:
				var spot := middle + Vector2(shift, 0.0)
				var to := Geo.project(spot)
				if to.x < GRID_WEST + 0.5 or to.x > GRID_EAST - 0.5:
					continue
				for offset: float in [0.0, 360.0]:
					var from := Geo.project(Vector2(port.lon + offset, port.lat))
					if from.x > GRID_EAST - 1.0 or absf(from.x - to.x) > MAX_ROUTE_SPAN:
						continue
					var a := _nearest_water(_cell_of(from))
					var b := _nearest_water(_cell_of(to))
					if a.x < 0 or b.x < 0:
						continue
					var cells := _route(coarse, astar, a, b)
					if cells.is_empty():
						continue
					var points := _round_corners(_lane_points(Vector2(port.lon + offset, port.lat), cells, Geo.unproject(_cell_center(b))))
					var nm := _length_nm(points)
					if nm < best_nm:
						best_nm = nm
						best = points
			if best.is_empty():
				continue
			var shift_back: float = port.lon - best[0].x
			data.keys.append("%s-@%s" % [port.id, ground.id])
			data.starts.append(data.points.size())
			for p in best:
				data.points.append(Vector2(snappedf(p.x + shift_back, 0.0001), snappedf(p.y, 0.0001)))
			data.distances.append(best_nm)
			count += 1
			made += 1
		if count == 0:
			push_error("No fishing lane to %s" % ground.id)
	data.starts.append(data.points.size())
	var err := ResourceSaver.save(data, LANES_OUT, ResourceSaver.FLAG_COMPRESS)
	assert(err == OK, "Couldn't save %s" % LANES_OUT)
	print("Fishing lanes: %d to %d grounds (%.1f min)" % [made, fish.grounds.size(), (Time.get_ticks_msec() - started) / 60000.0])

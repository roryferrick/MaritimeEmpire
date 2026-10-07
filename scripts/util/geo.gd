# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Geo
## Earth geometry helpers.
##
## Map ("projected") coordinates are Web Mercator in degrees: x = longitude,
## y = Mercator northing scaled to degrees, north positive. The world is 360
## units wide and wraps east-west.

const EARTH_RADIUS_NM := 3440.065
const MAX_LAT := 85.0
const WORLD_WIDTH := 360.0
## The map art's triangles are split until no side is longer than this (degrees
## of the globe's surface), so they curve round the globe (see tessellate()).
const GLOBE_MAX_EDGE := 2.0


## (lon, lat) in degrees -> projected map coordinates.
static func project(lon_lat: Vector2) -> Vector2:
	var lat := deg_to_rad(clampf(lon_lat.y, -MAX_LAT, MAX_LAT))
	return Vector2(lon_lat.x, rad_to_deg(log(tan(PI / 4.0 + lat / 2.0))))


## Projected map coordinates -> (lon, lat) in degrees.
static func unproject(point: Vector2) -> Vector2:
	return Vector2(point.x, rad_to_deg(2.0 * atan(exp(deg_to_rad(point.y))) - PI / 2.0))


## Great-circle distance in nautical miles between two (lon, lat) points.
static func distance_nm(a: Vector2, b: Vector2) -> float:
	var lat1 := deg_to_rad(a.y)
	var lat2 := deg_to_rad(b.y)
	var dlat := lat2 - lat1
	var dlon := deg_to_rad(b.x - a.x)
	var h := sin(dlat / 2.0) ** 2 + cos(lat1) * cos(lat2) * sin(dlon / 2.0) ** 2
	return 2.0 * EARTH_RADIUS_NM * asin(minf(1.0, sqrt(h)))


## Point a fraction t of the way along the great circle from a to b (lon, lat).
static func great_circle_lerp(a: Vector2, b: Vector2, t: float) -> Vector2:
	var p1 := _to_unit(a)
	var p2 := _to_unit(b)
	var p := p1.slerp(p2, t)
	return Vector2(rad_to_deg(atan2(p.y, p.x)), rad_to_deg(asin(clampf(p.z, -1.0, 1.0))))


static func _to_unit(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	return Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))


## Map triangles (projected; and their points' colors, if any) with every one
## longer than max_edge (degrees on the globe: _arc_squared()) on a side halved
## across its longest side, again and again, until none is: [triangles,
## colors]. The globe's shader (scripts/ui/globe.gdshader) moves only their
## corners, so smaller triangles follow its curve.
static func tessellate(triangles: PackedVector2Array, colors := PackedColorArray(), max_edge := GLOBE_MAX_EDGE) -> Array:
	var limit := max_edge * max_edge
	var colored := not colors.is_empty()
	var out := PackedVector2Array()
	var out_colors := PackedColorArray()
	var points := PackedVector2Array()  # A stack of triangles still to split.
	var tints := PackedColorArray()
	for i in range(0, triangles.size() - 2, 3):
		points.append_array([triangles[i], triangles[i + 1], triangles[i + 2]])
		if colored:
			tints.append_array([colors[i], colors[i + 1], colors[i + 2]])
		while not points.is_empty():
			var n := points.size()
			var a := points[n - 3]
			var b := points[n - 2]
			var c := points[n - 1]
			var ab := _arc_squared(a, b)
			var bc := _arc_squared(b, c)
			var ca := _arc_squared(c, a)
			points.resize(n - 3)
			var ta := Color.WHITE
			var tb := Color.WHITE
			var tc := Color.WHITE
			if colored:
				ta = tints[n - 3]
				tb = tints[n - 2]
				tc = tints[n - 1]
				tints.resize(n - 3)
			if ab <= limit and bc <= limit and ca <= limit:
				out.append_array([a, b, c])
				if colored:
					out_colors.append_array([ta, tb, tc])
				continue
			# Turn it so a-b is the longest side, then split that at its middle.
			if bc >= ab and bc >= ca:
				var p := a
				a = b
				b = c
				c = p
				var t := ta
				ta = tb
				tb = tc
				tc = t
			elif ca >= ab and ca >= bc:
				var p := c
				c = b
				b = a
				a = p
				var t := tc
				tc = tb
				tb = ta
				ta = t
			var m := (a + b) / 2.0
			points.append_array([a, m, c, m, b, c])
			if colored:
				var tm := ta.lerp(tb, 0.5)
				tints.append_array([ta, tm, tc, tm, tb, tc])
	return [out, out_colors]


## Every triangle list of a world map, tessellated for the globe (see tessellate()).
static func tessellate_map(map: WorldMapData) -> void:
	map.land_triangles = tessellate(map.land_triangles)[0]
	map.water_triangles = tessellate(map.water_triangles)[0]
	map.lake_island_triangles = tessellate(map.lake_island_triangles)[0]
	var biomes := tessellate(map.biome_triangles, map.biome_colors)
	map.biome_triangles = biomes[0]
	map.biome_colors = biomes[1]
	for i in map.lake_triangles.size():
		map.lake_triangles[i] = tessellate(map.lake_triangles[i])[0]
	for i in map.depth_triangles.size():
		map.depth_triangles[i] = tessellate(map.depth_triangles[i])[0]
		map.depth_hole_triangles[i] = tessellate(map.depth_hole_triangles[i])[0]


## Roughly how long a side between two map points is on the globe, squared
## (in degrees of its surface): Web Mercator stretches it by 1 / cos(latitude),
## worked out at its middle.
static func _arc_squared(a: Vector2, b: Vector2) -> float:
	var stretch := cosh(deg_to_rad((a.y + b.y) / 2.0))
	return a.distance_squared_to(b) / (stretch * stretch)

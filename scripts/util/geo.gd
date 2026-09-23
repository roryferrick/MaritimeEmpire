class_name Geo
## Earth geometry helpers.
##
## Map ("projected") coordinates are Web Mercator in degrees: x = longitude,
## y = Mercator northing scaled to degrees, north positive. The world is 360
## units wide and wraps east-west.

const EARTH_RADIUS_NM := 3440.065
const MAX_LAT := 85.0
const WORLD_WIDTH := 360.0


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

# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Wind
extends RefCounted
## The wind anywhere, any time: the real prevailing winds by latitude (the
## easterly trade winds in the tropics, the westerlies of the middle latitudes,
## strongest in the Southern Ocean's roaring forties, and the polar easterlies;
## near calm in the doldrums and the horse latitudes), wandering in direction
## and strength with slow gusty variation, and wound round every storm (the
## way storms turn: anticlockwise in the north, clockwise in the south). The
## same for every player (it goes by play time). A wind is the way it blows
## TO, as (east, north), its length its strength: about 0.5 a fresh breeze, 1 a
## gale, more in a storm.

## How much a storm adds to the wind at its core, at full strength.
const STORM_WIND := 1.6
## The variation: its features this many degrees across (as a share of the
## globe's radius, for the noise), and how fast it changes (per second of play).
const GUST_SCALE := 3.2
const GUST_RATE := 0.012

static var _noise: FastNoiseLite = null


## The wind at a (lon, lat) at a play time (see the class description).
static func at(lon_lat: Vector2, play_time: float, storms: Array = []) -> Vector2:
	var wind := prevailing(lon_lat.y)
	# Its slow, gusty variation: a turn of up to about 45 degrees and a share
	# stronger or weaker, varying over a few thousand miles and minutes of play.
	var noise := _shared_noise()
	var p := _unit(lon_lat) * GUST_SCALE
	var drift := play_time * GUST_RATE
	var turn := noise.get_noise_3d(p.x + drift, p.y, p.z) * 0.9
	var gust := 1.0 + noise.get_noise_3d(p.x + 40.0, p.y - drift, p.z + 17.0) * 0.6
	wind = wind.rotated(turn) * maxf(gust, 0.2)
	for storm: Dictionary in storms:
		wind += storm_wind(storm, lon_lat)
	return wind


## The prevailing wind by latitude, with no variation (see the class description).
static func prevailing(lat: float) -> Vector2:
	var hemisphere := 1.0 if lat >= 0.0 else -1.0
	var a := absf(lat)
	# Each belt's share of the wind here, eased across the calms between them.
	var trades := smoothstep(2.0, 9.0, a) * (1.0 - smoothstep(24.0, 33.0, a))
	var westerlies := smoothstep(30.0, 38.0, a) * (1.0 - smoothstep(58.0, 66.0, a))
	var polar := smoothstep(62.0, 70.0, a)
	# Trade winds blow from the north-east (south-east in the south), toward
	# the equator; westerlies from the south-west (north-west); polar easterlies
	# from the north-east (south-east) again.
	var trade_wind := Vector2(-1.0, -0.45 * hemisphere).normalized() * 0.55
	var westerly_wind := Vector2(1.0, 0.3 * hemisphere).normalized() * (0.95 if hemisphere < 0.0 else 0.7)
	var polar_wind := Vector2(-1.0, -0.25 * hemisphere).normalized() * 0.45
	var calm := Vector2(-0.12, 0.0)  # The doldrums and horse latitudes: light airs.
	return calm + trade_wind * trades + westerly_wind * westerlies + polar_wind * polar


## What a storm adds to the wind at a (lon, lat): round its centre (turning
## anticlockwise in the north, clockwise in the south) and in a little, as
## strong as the storm is there.
static func storm_wind(storm: Dictionary, lon_lat: Vector2) -> Vector2:
	var strength := Weather.strength_at(storm, lon_lat)
	if strength <= 0.0:
		return Vector2.ZERO
	var out := Vector2((lon_lat.x - float(storm.lon)) * cos(deg_to_rad(lon_lat.y)), lon_lat.y - float(storm.lat))
	out.x = wrapf(out.x, -180.0, 180.0)
	if out.length() < 0.0001:
		return Vector2.ZERO
	out = out.normalized()
	var spin := Vector2(-out.y, out.x) if float(storm.lat) >= 0.0 else Vector2(out.y, -out.x)
	return (spin - out * 0.3).normalized() * STORM_WIND * strength


static func _shared_noise() -> FastNoiseLite:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.seed = 1871
		_noise.frequency = 1.0
	return _noise


static func _unit(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	return Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))

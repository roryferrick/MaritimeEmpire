# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name BirdLife
extends RefCounted
## Every bird of the wildlife's colonies (Wildlife) as a permanent map object:
## it's always somewhere, doing something, and never appears or vanishes. Its
## day goes in spells (each class its own length, each bird its own phase): at
## the start of each it picks what to do next, by its class and the hour
## (circling its port, perching on the breakwater, swimming and diving off it,
## standing or stalking at the water's edge, soaring and hunting over the
## land and sea, gliding at sea, following a ship that's near, resting at its
## home, asleep there by night), and flies there from wherever it was, smoothly,
## then does it. A colony on its migration flies the whole way together in a V,
## from wherever its birds were. Birds sleep at their homes at night (night
## herons by day); sea ducks and seabirds out at sea sleep on the water.
##
## Its places are real spots round its port (MapView gives them, in lon/lat:
## the breakwater's arms, the water's edge and the land behind it either side,
## the sea off it, the marina's middle) or out at sea. Times are real seconds
## (Wildlife.bird_time: the birds keep their own pace whatever the game's
## speed, and carry on while it's paused); the hour is the calendar's.
## Worked out natively (native/src/bird_sim.cpp, BirdSim) when the game's
## native library is there (see native/README.md); this GDScript does the
## same where it isn't.
##
## Each bird's spell is worked out from the time alone (where the last one left
## it, or where it really was when on screen), so it's always somewhere, the same
## whoever looks; nothing is saved.

## Each class's spell length (s: the fewest and most), and how fast it flies (km a second).
const SPELL_S := {gulls = Vector2(18, 40), raptors = Vector2(30, 70), cormorants = Vector2(25, 55), waders = Vector2(40, 90),
	sea_ducks = Vector2(45, 100), seabirds = Vector2(50, 130)}
const SPEED_KMS := {gulls = 2.4, raptors = 3.0, cormorants = 3.2, waders = 1.6, sea_ducks = 3.4, seabirds = 5.0}
## Flying somewhere takes at most this share of a spell (it flies faster if it must).
const TRAVEL_SHARE := 0.8
## How far (km) gulls and seabirds will go to follow a ship; how far a seabird
## wanders between spells; how far apart (spans) birds fly in a V.
const GULL_FOLLOW_KM := 60.0
const SEABIRD_FOLLOW_KM := 250.0
const SEABIRD_ROAM_KM := 120.0
const V_SPACING_KM := 4.5
## Night, for birds: before this hour and after the next (by the sun where they are).
const NIGHT := Vector2(5.5, 20.0)
## How fast (radians a second) and how high birds circle, soar, glide and hunt.
const CIRCLE_SPEED := {circle = 0.12, soar = 0.06, glide = 0.035, hunt = 0.09}
const CIRCLE_HEIGHT := {circle = 1.3, soar = 2.2, glide = 1.0, hunt = 1.6}
## What a bird does without moving (see _spell_state()).
const STILL := {stand = true, perch = true, rest = true, sleep = true}
## A bird's last place is trusted for this long (s) to fly on from; older, it
## starts its next spell where that spell is (it wasn't on screen to see).
const LAST_FRESH_S := 2.0
## How long (s) a bird takes to fly from where it was into its place in its colony's V.
const MIGRATION_JOIN_S := 25.0

static var _shared: BirdLife

## Every bird: {colony (index), n (its place in it), seed, hen (a sea duck hen),
## length (of its spells, s), phase (where in a spell it was at time 0: 0 to 1)}.
var birds: Array[Dictionary] = []
var _colony_birds := {}  # colony index -> [bird indices]
## Each bird's spell as worked out: bird index -> {k, act, place, from, start,
## travel, ...}, and where it was last: bird index -> [lon/lat, time].
var _plans := {}
var _last := {}
## Birds joining their colony's V: bird index -> [where it was, when it started].
var _joining := {}
## Birds keeping still: bird index -> [their state, till when, from when,
## Wildlife.where_changes then] (see bird_state()).
var _fixed := {}
const NO_FIX := [null, -INF, INF, -1]
## Each port's spots (MapView: the spots provider), by port id.
var _spots := {}
var spots_provider: Callable
var _built := false
## The native birds (BirdSim), when the native library's loaded; null otherwise.
var native: Object = null
## The map's meshes for the native birds (see MapView._native_bird_mesh()).
var mesh_provider: Callable
var _ships_at := []
var _ships_frame := -1


static func shared() -> BirdLife:
	if _shared == null:
		_shared = BirdLife.new()
	return _shared


## The birds, once the wildlife's colonies are built (or [] till then).
func ensure_built() -> bool:
	if _built:
		return true
	var wildlife := Wildlife.shared()
	if not wildlife.ensure_built():
		return false
	if ClassDB.class_exists(&"BirdSim"):
		native = ClassDB.instantiate(&"BirdSim")
		var species := {}
		var names := Birds.shared()
		for group: Dictionary in [names.gulls, names.seabirds, names.raptors, names.sea_ducks, names.cormorants, names.waders]:
			species.merge(group)
		native.setup(wildlife.colonies, species, wildlife.migrate_days)
		_hand_providers()
	for index in wildlife.colonies.size():
		var colony: Dictionary = wildlife.colonies[index]
		var list := []
		for n in int(colony.count):
			list.append(birds.size())
			var seed := int(colony.seed) * 977 + n * 131
			var cls: String = colony.cls
			birds.append({colony = index, n = n, seed = seed, hen = cls == "sea_ducks" and n % 2 == 1,
				length = lerpf(SPELL_S[cls].x, SPELL_S[cls].y, Wildlife._mix(seed)), phase = Wildlife._mix(seed + 1)})
		_colony_birds[index] = list
	# Perching order at each port (see _perch()): its own gulls and cormorants
	# first, then those spending their away months there.
	var perchers := {}
	for away: bool in [false, true]:
		for bird: Dictionary in birds:
			var colony: Dictionary = wildlife.colonies[bird.colony]
			var port: String = colony.away_port if away else colony.port
			if colony.cls in ["gulls", "cormorants"] and not port.is_empty():
				bird["perch_away" if away else "perch_home"] = int(perchers.get(port, 0))
				perchers[port] = int(perchers.get(port, 0)) + 1
	_built = true
	return true


## Gives the native birds the map's spots and meshes and the ships (again
## once the map's given them).
func _hand_providers() -> void:
	if native != null:
		native.set_providers(spots_provider, _ship_lists, mesh_provider)


## Sets the map's providers (MapView: its spots and its meshes for birds).
func set_map_providers(spots: Callable, meshes: Callable) -> void:
	spots_provider = spots
	mesh_provider = meshes
	_spots.clear()
	if native != null:
		native.forget_spots()
	_hand_providers()


## The ships birds can follow, for the native birds: [ids, (lon, lat)s].
func _ship_lists() -> Array:
	var ids := PackedInt64Array()
	var spots := PackedVector2Array()
	for entry: Array in _ships_now():
		ids.append((entry[0] as Ship).id)
		spots.append(entry[1])
	return [ids, spots]


## A colony's birds (indices into birds).
func birds_of(colony_index: int) -> Array:
	if not ensure_built():
		return []
	if native != null:
		return Array(native.birds_of(colony_index))
	return _colony_birds.get(colony_index, [])


## Where a bird is now and what it's doing: {pos (lon, lat), heading (radians:
## 0 east, counterclockwise towards north; or NAN to take it from its
## movement), mode (fly, circle, soar, glide, hunt, perch, rest, sleep, swim,
## dive, stand, stalk, follow), height (0 on the ground or water, 1 flying,
## more soaring), wings (how far out: 1 spread, 0.2 folded), splash (0 to 1 just
## after diving in)}.
func bird_state(index: int, now: float, cal: float) -> Dictionary:
	if native != null:
		return native.bird_state(index, now, cal)
	# Standing, perched, resting or asleep: just so till its spell ends (or a
	# colony sets off somewhere or arrives).
	var fixed: Array = _fixed.get(index, NO_FIX)
	if now < float(fixed[1]) and now >= float(fixed[2]) and int(fixed[3]) == Wildlife.shared().where_changes:
		return fixed[0]
	var bird: Dictionary = birds[index]
	var wildlife := Wildlife.shared()
	var colony: Dictionary = wildlife.colonies[bird.colony]
	var where := wildlife.colony_where(colony, cal)
	var state: Dictionary
	if where[0] == "to_home" or where[0] == "to_away":
		state = _migrating(index, bird, colony, where, cal, now)
	else:
		_joining.erase(index)
		state = _spell_state(index, bird, colony, str(where[0]) == "away", now, cal)
	# Its heading from how it moved since last time, when it's moving.
	var last: Array = _last.get(index, [])
	var pos: Vector2 = state.pos
	if is_nan(float(state.heading)):
		state.heading = 0.0
		if not last.is_empty():
			var moved: Vector2 = pos - (last[0] as Vector2)
			moved.x *= cos(deg_to_rad(pos.y))
			if moved.length() > 0.00001:
				state.heading = atan2(moved.y, moved.x)
			elif last.size() > 2:
				state.heading = last[2]
	if last.is_empty():
		_last[index] = [pos, now, state.heading]
	else:
		last[0] = pos
		last[1] = now
		last[2] = state.heading
	return state


## Till when (bird time) a bird keeps just as it is now (standing, perched,
## resting or asleep), as of its last bird_state(); -INF if it's moving.
func still_until(index: int) -> float:
	var fixed: Array = _fixed.get(index, NO_FIX)
	return float(fixed[1]) if int(fixed[3]) == Wildlife.shared().where_changes else -INF


## Where a bird can be till its spell ends, so a map can skip it while that's
## all out of view: [middle (lon, lat), how far from it (km), the spell's end
## (bird time)]; or [] when there's no telling (following a ship, or its colony
## on the wing).
func bird_bounds(index: int, now: float, cal: float) -> Array:
	var bird: Dictionary = birds[index]
	var colony: Dictionary = Wildlife.shared().colonies[bird.colony]
	var where := Wildlife.shared().colony_where(colony, cal)
	if where[0] == "to_home" or where[0] == "to_away":
		return []
	var cls: String = colony.cls
	var length := float(bird.length)
	var t := now + float(bird.phase) * length
	var k := floori(t / length)
	var away := str(where[0]) == "away"
	var plan: Dictionary = _plans.get(index, {})
	if plan.is_empty() or int(plan.k) != k or bool(plan.away) != away:
		plan = _plan(index, bird, colony, away, k, now - (t - k * length), cal, now)
		_plans[index] = plan
	if plan.act == "follow":
		return []
	var place: Vector2 = plan.place
	var reach := float(plan.get("radius", 0.0)) + 2.0
	if plan.act == "stalk":
		var to: Vector2 = plan.get("to", place)
		reach += Geo.distance_nm(place, to) * 1.852
	var middle := place
	if plan.from != null:
		var from: Vector2 = plan.from
		var gap := Geo.distance_nm(from, place) * 1.852
		middle = from.lerp(place, 0.5)
		reach += gap * 0.65  # (Half the way, and its bend.)
	return [middle, reach, float(plan.start) + length]


## A colony on its migration: in a V along the shortest way round the globe
## (the leader where it's got to by the calendar), each bird coming in from
## wherever it was over the first part of it.
func _migrating(index: int, bird: Dictionary, colony: Dictionary, where: Array, cal: float, now: float) -> Dictionary:
	var from: Vector2 = colony.away_spot if where[0] == "to_home" else colony.spot
	var to: Vector2 = colony.spot if where[0] == "to_home" else colony.away_spot
	var p: float = where[1]
	var a := _unit(from)
	var b := _unit(to)
	var lead := _lon_lat(a.slerp(b, p))
	var ahead := _lon_lat(a.slerp(b, minf(p + 0.001, 1.0)))
	var way := Vector2((ahead.x - lead.x) * cos(deg_to_rad(lead.y)), ahead.y - lead.y).normalized()
	if way == Vector2.ZERO:
		way = Vector2.RIGHT
	# Its place in the V: the leader at the point, the rest back along either arm by turns.
	var n: int = bird.n
	var rank := (n + 1) / 2
	var arm := 0.0 if n == 0 else (1.0 if n % 2 == 1 else -1.0)
	var back := -way * rank * V_SPACING_KM + way.orthogonal() * arm * rank * V_SPACING_KM * 0.9
	var pos := Wildlife._offset(lead, back)
	# Joining the V from wherever it was (if it was just seen), over MIGRATION_JOIN_S.
	if not _joining.has(index):
		var last: Array = _last.get(index, [])
		_joining[index] = [last[0] if not last.is_empty() and now - float(last[1]) < LAST_FRESH_S else pos, now]
	var join: Array = _joining[index]
	var u := smoothstep(0.0, MIGRATION_JOIN_S, now - float(join[1]))
	if u < 1.0:
		pos = (join[0] as Vector2).lerp(pos, u)
		return {pos = pos, heading = NAN, mode = "fly", height = 2.0, wings = 0.8 + 0.2 * sin(now * 5.0 + n * 0.7), splash = 0.0}
	return {pos = pos, heading = atan2(way.y, way.x), mode = "fly", height = 2.5, wings = 0.8 + 0.2 * sin(now * 5.0 + n * 0.7), splash = 0.0}


## Its spell now: what it's doing (worked out at the spell's start), flying
## there first from where it was.
func _spell_state(index: int, bird: Dictionary, colony: Dictionary, away: bool, now: float, cal: float) -> Dictionary:
	var cls: String = colony.cls
	var length := float(bird.length)
	var t := now + float(bird.phase) * length
	var k := floori(t / length)
	var into := t - k * length
	var plan: Dictionary = _plans.get(index, {})
	if plan.is_empty() or int(plan.k) != k or bool(plan.away) != away:
		plan = _plan(index, bird, colony, away, k, now - into, cal, now)
		_plans[index] = plan
	# Once there, a bird standing, perched, resting or asleep is just so (but a
	# cormorant drying its wings): kept, not worked out again every frame.
	var since := now - float(plan.start)
	if since >= float(plan.travel) and plan.has("still"):
		_fixed[index] = [plan.still, float(plan.start) + length, now, Wildlife.shared().where_changes]
		return plan.still
	var state := _doing(plan, bird, colony, since, now)
	if since >= float(plan.travel) and STILL.has(plan.act) and not (plan.act == "perch" and cls == "cormorants"):
		plan.still = state
	return state


## Works out a bird's next spell: what, where, and from where it flies there.
func _plan(index: int, bird: Dictionary, colony: Dictionary, away: bool, k: int, start: float, cal: float, now: float, with_from := true) -> Dictionary:
	var cls: String = colony.cls
	var port: String = colony.away_port if away else colony.port
	var spots := _port_spots(port)
	var center: Vector2 = spots.get("center", colony.away_spot if away else colony.spot)
	var home: Vector2 = spots.get("homes", {}).get(bird.colony, center) if not away else spots.get("roost", center)
	var hour := Birds.local_hour(center.x, cal)
	var info := Birds.shared().species(colony.species)
	var night := hour < NIGHT.x or hour > NIGHT.y
	if str(info.get("kind", "")) == "Night heron":
		night = not night
	var roll := Wildlife._mix(bird.seed + k * 7919)
	# Ducks and cormorants keep together: their colony picks for them.
	var group_roll := Wildlife._mix(int(colony.seed) + k * 7919)
	var plan := {k = k, away = away, start = start, act = "rest", place = home, cls = cls}
	var pick := func(list: Array, salt: int) -> Vector2:
		return list[int(Wildlife._mix(bird.seed + k * 31 + salt) * list.size()) % list.size()] if not list.is_empty() else center
	match cls:
		"gulls":
			if night:
				plan.act = "sleep" if roll < 0.85 else "swim"
				plan.place = home if plan.act == "sleep" else pick.call(spots.get("sea", []), 1)
			elif roll < 0.33:
				plan.act = "circle"
				plan.place = center
				plan.radius = float(spots.get("radius_km", 15.0)) * lerpf(0.5, 1.2, Wildlife._mix(bird.seed + k * 3))
			elif roll < 0.53:
				plan.act = "perch"
				plan.place = _perch(spots.get("breakwater", []), int(bird.get("perch_away" if away else "perch_home", 0)), center)
			elif roll < 0.68:
				plan.act = "swim"
				plan.place = pick.call(spots.get("sea", []), 3)
			elif roll < 0.88 and _ship_near(center, GULL_FOLLOW_KM, bird.seed + k) != null:
				plan.act = "follow"
				plan.ship = _ship_near(center, GULL_FOLLOW_KM, bird.seed + k)
			else:
				plan.act = "rest"
		"raptors":
			if night:
				plan.act = "sleep"
			elif roll < 0.35:
				plan.act = "perch"
				plan.place = pick.call(spots.get("inland", []), 4)
			elif roll < 0.65:
				plan.act = "soar"
				plan.place = pick.call(spots.get("inland", []), 5)
				plan.radius = lerpf(3.0, 7.0, Wildlife._mix(bird.seed + k * 5))
			elif roll < 0.9:
				plan.act = "hunt"
				plan.place = pick.call(spots.get("sea", []), 6)
				plan.radius = lerpf(2.0, 4.0, Wildlife._mix(bird.seed + k * 9))
		"cormorants":
			if night:
				plan.act = "sleep"
			elif group_roll < 0.4:
				plan.act = "perch"
				plan.place = _perch(spots.get("breakwater", []), int(bird.get("perch_away" if away else "perch_home", 0)), center)
			elif group_roll < 0.82:
				plan.act = "swim"
				plan.place = (spots.get("sea", [center]) as Array)[int(group_roll * 997) % maxi((spots.get("sea", [center]) as Array).size(), 1)]
				plan.dives = true
			else:
				plan.act = "circle"
				plan.place = center
				plan.radius = float(spots.get("radius_km", 15.0)) * 1.6
		"waders":
			if night:
				plan.act = "sleep"
			elif str(info.get("behavior", "")) == "hide" or roll < 0.5:
				plan.act = "stand"
				plan.place = pick.call(spots.get("shore", []), 8)
			elif roll < 0.85:
				plan.act = "stalk"
				plan.place = pick.call(spots.get("shore", []), 9)
				plan.to = pick.call(spots.get("shore", []), 10)
		"sea_ducks":
			# A raft off the port, day and night, now and then flying round together.
			var sea: Array = spots.get("sea", [center])
			if group_roll < 0.88 or night:
				plan.act = "swim"
				plan.place = Wildlife._offset(sea[int(Wildlife._mix(int(colony.seed) + k) * sea.size()) % maxi(sea.size(), 1)], Wildlife._disc_n(bird.seed) * (1.0 + 0.4 * int(colony.count)))
				plan.dives = not night
			else:
				plan.act = "circle"
				plan.place = center
				plan.radius = float(spots.get("radius_km", 15.0)) * 1.8
		"seabirds":
			var range_km := float(colony.get("range_km", 500.0))
			var base: Vector2 = colony.away_spot if away else colony.spot
			# Wandering out over the sea, a stretch at a time.
			var out := Wildlife._offset(base, Wildlife._disc_n(bird.seed + (k / 6) * 104729) * range_km * 0.6)
			var spot := Wildlife._offset(out, Wildlife._disc_n(bird.seed + k * 7) * SEABIRD_ROAM_KM)
			var ship: Ship = _ship_near(spot, SEABIRD_FOLLOW_KM, bird.seed + k)
			if night:
				plan.act = "swim"
				plan.place = spot
			elif roll < 0.35 and ship != null and Birds.chance(["follow", ship.id, colony.species]) < float(info.get("follow", [0.3])[0]) + 0.3:
				plan.act = "follow"
				plan.ship = ship
			elif roll < 0.8:
				plan.act = "glide"
				plan.place = spot
				plan.radius = lerpf(8.0, 25.0, Wildlife._mix(bird.seed + k * 11))
			else:
				plan.act = "swim"
				plan.place = spot
	plan.facing = Wildlife._mix(bird.seed + k * 13) * TAU
	# Worked out once a spell, not every frame: which way it circles and how
	# fast, where on its circle it starts, how high, its own rhythm for
	# hunting and diving, and which way its flight there bends.
	var seed: int = bird.seed
	plan.turn = 1.0 if seed % 2 == 0 else -1.0
	plan.speed = float(CIRCLE_SPEED.get(plan.act, 0.1)) * float(plan.turn)
	plan.angle0 = Wildlife._mix(seed + 5) * TAU
	plan.height = float(CIRCLE_HEIGHT.get(plan.act, 1.0))
	plan.hunt_phase = Wildlife._mix(seed + 9)
	plan.dive_phase = Wildlife._mix(seed + 2)
	plan.bend = 1.0 if Wildlife._mix(seed + k) < 0.5 else -1.0
	plan.from = null
	plan.travel = 0.0
	if not with_from:
		return plan
	# Where it flies from: where it really was, if it was just seen; else where
	# its last spell left it (worked out again), so it's never anywhere new.
	var length := float(bird.length)
	var last: Array = _last.get(index, [])
	if not last.is_empty() and now - float(last[1]) < LAST_FRESH_S:
		plan.from = last[0]
	else:
		var before := _plan(index, bird, colony, away, k - 1, start - length, cal, start, false)
		plan.from = _doing(before, bird, colony, length, start).pos
	# (To where it starts circling, on its circle, for the circling kinds.)
	var distance := Geo.distance_nm(plan.from, _doing(plan, bird, colony, 0.0, start).pos) * 1.852
	plan.travel = minf(distance / float(SPEED_KMS[cls]), length * TRAVEL_SHARE)
	return plan


## Where a spell's activity is at a time (the start of it, where it flies to).
## A perched bird's own slot (`order`: its place in its port's perching order)
## among a breakwater's evenly spaced slots, taken in a stride round them
## (about 0.618 of the way) so the first few are spread along both arms: each
## bird has its own while there are as many slots as perching birds. (As
## BirdSim._perch().)
static func _perch(slots: Array, order: int, fallback: Vector2) -> Vector2:
	var n := slots.size()
	if n == 0:
		return fallback
	var stride := maxi(roundi(n * 0.618), 1)
	while _gcd(stride, n) != 1:
		stride += 1
	return slots[(maxi(order, 0) * stride) % n]

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return a

func _target(plan: Dictionary, bird: Dictionary, now: float) -> Vector2:
	if plan.act == "follow":
		var ship: Ship = plan.ship
		if is_instance_valid(ship) and GameState.ships.has(ship):
			var at := Geo.unproject(GameData.port_position(ship.docked_at) if ship.is_docked() else ship.world_position())
			# Behind and off to a side of it, by the bird.
			return Wildlife._offset(at, Wildlife._disc_n(bird.seed + 3) * 8.0)
		return plan.place
	return plan.place


## What a bird's doing `into` seconds into its spell: flying there first, then the thing itself.
func _doing(plan: Dictionary, bird: Dictionary, colony: Dictionary, into: float, now: float) -> Dictionary:
	var target: Vector2 = plan.place if plan.act != "follow" else _target(plan, bird, now)
	var flap := 0.75 + 0.25 * absf(sin(now * 9.0 + bird.seed % 97))
	if plan.from != null and into < float(plan.travel):
		# Flying to just where the thing starts (so it carries straight on into it).
		# (Kept with the spell where that's fixed: not on the water, drifting, nor following a ship.)
		var arrive: Vector2 = plan.get("arrive", Vector2.INF)
		if arrive == Vector2.INF:
			arrive = _doing(plan, bird, colony, float(plan.travel), now).pos
			if plan.act != "swim" and plan.act != "follow":
				plan.arrive = arrive
		var u := into / maxf(float(plan.travel), 0.001)
		var from: Vector2 = plan.from
		var along := from.lerp(arrive, smoothstep(0.0, 1.0, u))
		# A gentle curve, not a ruler line.
		var gap := Vector2((arrive.x - from.x) * cos(deg_to_rad(along.y)), arrive.y - from.y)
		var bend := gap.orthogonal() * sin(u * PI) * 0.12 * float(plan.bend)
		along += Vector2(bend.x / maxf(cos(deg_to_rad(along.y)), 0.1), bend.y)
		return {pos = along, heading = NAN, mode = "fly", height = 1.2, wings = flap, splash = 0.0}
	var since := into - float(plan.travel)
	var seed: int = bird.seed
	match plan.act:
		"circle", "soar", "glide", "hunt":
			# At its full size from the start: its flight there ends just where it
			# joins its circle (not at the middle, flung out to it).
			var radius := float(plan.get("radius", 5.0))
			var turn := float(plan.turn)
			var angle := float(plan.angle0) + since * float(plan.speed)
			var pos := Wildlife._offset(target, Vector2.from_angle(angle) * radius)
			var height := float(plan.height)
			var splash := 0.0
			if plan.act == "hunt":
				# Now and then plunging in, then up again.
				var cycle := fmod(since / 14.0 + float(plan.hunt_phase), 1.0)
				if cycle > 0.8:
					var dip := sin((cycle - 0.8) / 0.2 * PI)
					height *= 1.0 - dip
					splash = dip if dip > 0.8 else 0.0
			return {pos = pos, heading = angle + PI / 2.0 * turn, mode = plan.act, height = height,
				wings = 1.0 if plan.act != "circle" else flap, splash = splash}
		"follow":
			return {pos = target, heading = NAN, mode = "follow", height = 1.2, wings = flap, splash = 0.0}
		"swim":
			var drift := Vector2(sin(now * 0.05 + seed % 13), cos(now * 0.04 + seed % 7)) * 0.4
			var pos := Wildlife._offset(target, drift)
			var mode := "swim"
			if plan.get("dives", false):
				var cycle := fmod(since / (20.0 + seed % 9) + float(plan.dive_phase), 1.0)
				if cycle > 0.6:
					mode = "dive"
			return {pos = pos, heading = float(plan.facing) + 0.2 * sin(now * 0.3 + seed % 5), mode = mode, height = 0.0, wings = 0.2, splash = 0.0}
		"stand":
			return {pos = target, heading = float(plan.facing), mode = "stand", height = 0.0, wings = 0.0, splash = 0.0}
		"stalk":
			var to: Vector2 = plan.get("to", target)
			var u := 0.5 - 0.5 * cos(since * 0.03 + seed % 11)
			return {pos = target.lerp(to, u), heading = NAN, mode = "stalk", height = 0.0, wings = 0.0, splash = 0.0}
		"perch":
			var drying: bool = colony.cls == "cormorants" and sin(now * 0.12 + seed % 17) > 0.55
			return {pos = target, heading = float(plan.facing), mode = "perch", height = 0.03, wings = 0.7 if drying else 0.2, splash = 0.0}
		"sleep":
			return {pos = Wildlife._offset(target, Wildlife._disc_n(seed) * 1.2), heading = float(plan.facing), mode = "sleep", height = 0.0, wings = 0.15, splash = 0.0}
	return {pos = Wildlife._offset(target, Wildlife._disc_n(seed) * 1.5), heading = float(plan.facing), mode = "rest", height = 0.0, wings = 0.2, splash = 0.0}


## A ship (not carried) within `km` of a place, picked steadily by the seed among
## those near; or null.
func _ship_near(spot: Vector2, km: float, seed: int) -> Ship:
	var near: Array[Ship] = []
	var reach := km / Wildlife.KM_PER_DEGREE
	for entry: Array in _ships_now():
		var at: Vector2 = entry[1]
		if absf(at.y - spot.y) > reach:
			continue
		if Geo.distance_nm(at, spot) * 1.852 <= km:
			near.append(entry[0])
	if near.is_empty():
		return null
	return near[int(Wildlife._mix(seed) * near.size()) % near.size()]


## The ships birds could follow and where they are (lon, lat): [[ship, spot]],
## worked out once a frame.
func _ships_now() -> Array:
	var frame := Engine.get_process_frames()
	if frame != _ships_frame:
		_ships_frame = frame
		_ships_at.clear()
		for ship in GameState.ships:
			if ship.is_carried() or ship.is_service():
				continue
			_ships_at.append([ship, Geo.unproject(GameData.port_position(ship.docked_at) if ship.is_docked() else ship.world_position())])
	return _ships_at


## The birds following a ship now, by species: [{id, count}], most first.
func following(ship: Ship) -> Array:
	if ship == null or not ensure_built():
		return []
	var wildlife := Wildlife.shared()
	var now := wildlife.bird_time
	var cal := float(GameState.calendar_time())
	var at := Geo.unproject(GameData.port_position(ship.docked_at) if ship.is_docked() else ship.world_position())
	if native != null:
		var found: Dictionary = native.following(ship.id, at, now, cal)
		var listed := []
		for id: String in found:
			listed.append({id = id, count = found[id]})
		listed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.count) > int(b.count))
		return listed
	var reach := GULL_FOLLOW_KM * 2.0 / Wildlife.KM_PER_DEGREE
	var wide := reach / maxf(cos(deg_to_rad(at.y)), 0.1)
	var box := Rect2(at - Vector2(wide, reach), Vector2(wide, reach) * 2.0)
	var near := {}
	for index: int in wildlife.colonies_near(box):
		near[index] = true
	for index: int in wildlife.seabird_colonies_in(box):
		near[index] = true
	var counts := {}
	for colony_index: int in near:
		var species: String = wildlife.colonies[colony_index].species
		for index: int in birds_of(colony_index):
			if bird_state(index, now, cal).mode != "follow":
				continue
			if (_plans.get(index, {}) as Dictionary).get("ship") == ship:
				counts[species] = int(counts.get(species, 0)) + 1
	var out := []
	for id: String in counts:
		out.append({id = id, count = counts[id]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.count) > int(b.count))
	return out


## A port's spots for its birds (from the map; {} till it gives them).
func _port_spots(port_id: String) -> Dictionary:
	if port_id.is_empty():
		return {}
	if not _spots.has(port_id):
		if not spots_provider.is_valid():
			return {}
		var spots: Dictionary = spots_provider.call(port_id)
		if spots.is_empty():
			return {}  # (Not ready yet: the map's land is still being sorted.)
		_spots[port_id] = spots
	return _spots[port_id]


## What a colony's birds are doing now, most first: ["5 circling the port", "3 asleep at the colony"...].
func doing_text(colony_index: int, now: float, cal: float) -> PackedStringArray:
	var words := {fly = "flying", circle = "circling the port", soar = "soaring over the land", glide = "gliding over the sea",
		hunt = "hunting over the sea", perch = "perched", rest = "resting at home", sleep = "asleep at home", swim = "on the water",
		dive = "diving", stand = "standing at the water's edge", stalk = "stalking the shallows", follow = "following a ship"}
	var counts: Dictionary = native.doing_counts(colony_index, now, cal) if native != null else {}
	if native == null:
		for index: int in birds_of(colony_index):
			var mode: String = bird_state(index, now, cal).mode
			counts[mode] = int(counts.get(mode, 0)) + 1
	var order := counts.keys()
	order.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	var out := PackedStringArray()
	for mode: String in order:
		out.append("%d %s" % [counts[mode], words.get(mode, mode)])
	return out


static func _unit(lon_lat: Vector2) -> Vector3:
	var lon := deg_to_rad(lon_lat.x)
	var lat := deg_to_rad(lon_lat.y)
	return Vector3(cos(lat) * cos(lon), cos(lat) * sin(lon), sin(lat))


static func _lon_lat(p: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(p.y, p.x)), rad_to_deg(asin(clampf(p.z, -1.0, 1.0))))

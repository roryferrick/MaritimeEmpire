# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name DeckCrew
extends RefCounted
## The people out on a ship's deck, seen from above (MapView draws them over
## the ship once they're big enough to make out): a hat (or hair) on a head,
## shoulders in the shirt's colour, legs in the trousers' showing as they walk,
## and a shadow. What they wear is the ship's line's uniform (CrewLooks).
##
## Who's out: a big crew keeps three 8-hour watches, a third of the crew on
## deck at once (uniforms.json crew), the watch changing at 00:00, 08:00 and
## 16:00 ship's time (the outgoing watch walking in to the house's door as the
## next comes out); a small crew works small_day_hours a day, each turning in
## at their own time so the boat never stops (one always up, at the helm).
## What they do: the officer of the watch keeps to the bridge wings (the helm
## on a small boat); the rest wander the open deck (data/deck_layouts.json),
## man the bow and stern for lines coming alongside and pulling out, keep an
## anchor watch, and at the fishing grounds work the gear: rods while trolling
## (a strike now and then, one fighting the fish, one beside them with the
## gaff), the net reel, the trawl winches, or the crab pot hauler with the
## others carrying pots between it and the stacks.
## Nothing here is saved: it all follows from the ship, its clock and the time.

## A figure: [where (the ship's art units), facing (radians, 0 towards the bow,
## in the ship's frame), role (0 an officer, 1 crew), walk phase (radians, or
## -1.0 standing), tool (TOOL_*), seed].
const TOOL_NONE := 0
const TOOL_ROD := 1  # A rod in hand, its line out astern.
const TOOL_FIGHT := 2  # A rod bent double, its line taut to a fish.
const TOOL_POT := 3  # Carrying a crab pot.
const TOOL_LINE := 4  # Hauling a line (pot hauler, mooring lines).

## Each wander leg takes this long (real seconds), walking then standing.
const WANDER_S := 9.0
## A watch change: how long the handover lasts (game hours).
const HANDOVER_H := 0.6
## Turning in and getting up (game hours), walking to and from the door.
const TURN_IN_H := 0.4
## Trolling: how often a fish strikes (real seconds) and how long the fight lasts.
const STRIKE_EVERY_S := 40.0
const STRIKE_S := 16.0
## Crab pots carried between the hauler and the stacks, there and back (real seconds).
const POT_TRIP_S := 11.0
## Lines: how long (shares of a port stop) the bow and stern are manned after
## coming alongside and before pulling out.
const LINES_SHARE := 0.12

static var _layouts := {}


## An art's layout (data/deck_layouts.json), {} if it has none.
static func layout(art: String) -> Dictionary:
	if _layouts.is_empty():
		_layouts = JSON.parse_string(FileAccess.get_file_as_string("res://data/deck_layouts.json"))
	var entry: Variant = _layouts.get(art, {})
	if entry is Dictionary and (entry as Dictionary).has("like"):
		entry = _layouts.get(str(entry.like), {})
	return entry if entry is Dictionary else {}


## The figures on a ship's deck now. `art`: its art's name; `length_units`: its
## length in ship units (for walking speed); `now`: real seconds; `hour`: its
## clock (0 to 24, game time).
static func figures(ship: Ship, art: String, length_units: float, now: float, hour: float) -> Array:
	var plan := layout(art)
	if plan.is_empty() or (plan.walk as Array).is_empty():
		return []
	var settings := CrewLooks.settings()
	var crew := GameState.crew_of(ship.model())
	var officers := maxi(int(crew[0]), 1)
	var total := officers + int(crew[1])
	var speed := float(settings.walk_speed) * 180.0 / maxf(length_units, 0.01)  # (Art units a second.)
	var people := _on_deck(ship, total, officers, hour, settings)  # [id, role, out (0 at the door to 1 at their post), going in].
	var jobs := _jobs(ship, plan, now)
	var out := []
	var hands := 0
	for person: Array in people:
		var id: int = person[0]
		var role: int = person[1]
		var seed := absi(hash([ship.id, id]))
		var figure: Array
		if role == 0:
			var spots: Array = plan.bridge
			var spot: Array = spots[int(now / 23.0 + seed % 7) % spots.size()]
			figure = [Vector2(spot[0], spot[1]), _outward(plan, Vector2(spot[0], spot[1])), 0, -1.0, TOOL_NONE, seed]
		elif hands < jobs.size():
			var job: Array = jobs[hands]
			figure = [job[0], job[1], 1, job[2], job[3], seed]
			hands += 1
		else:
			figure = _wander(plan, seed, now, speed)
			hands += 1
		# Coming out of the door to their post, or going back in.
		var progress: float = person[2]
		if progress < 1.0:
			var door := Vector2(plan.door[0], plan.door[1])
			var post: Vector2 = figure[0]
			var going_in: bool = person[3]
			var from := post if going_in else door
			var to := door if going_in else post
			var f := progress if not going_in else 1.0 - progress
			figure[0] = from.lerp(to, f)
			figure[1] = (to - from).angle() if from.distance_to(to) > 0.5 else figure[1]
			figure[3] = f * from.distance_to(to) * 0.9
			figure[4] = TOOL_NONE
		out.append(figure)
	return out


## Who's on deck: [id, role (0 an officer), how far out (1 at their post,
## less coming out of or going into the door), going in] for each.
static func _on_deck(ship: Ship, total: int, officers: int, hour: float, settings: Dictionary) -> Array:
	var people := []
	if total <= int(settings.small_crew):
		# A small crew: each up small_day_hours of the day, turning in at their
		# own hour, spread round the clock so someone's always up.
		var sleep := 24.0 - float(settings.small_day_hours)
		for k in total:
			var turn_in := fposmod(21.0 + k * 24.0 / total + float(ship.id % 5) * 0.3, 24.0)
			var since := fposmod(hour - turn_in, 24.0)  # Hours since they turned in.
			if since < sleep:
				continue  # Asleep.
			var up := since - sleep  # Hours since they got up.
			var left := 24.0 - since  # Hours till they turn in.
			if up < TURN_IN_H:
				people.append([k, 0 if k == 0 else 1, up / TURN_IN_H, false])
			elif left < TURN_IN_H:
				people.append([k, 0 if k == 0 else 1, left / TURN_IN_H, true])
			else:
				people.append([k, 0 if k == 0 else 1, 1.0, false])
		# The skipper asleep: whoever's up takes the helm.
		if not people.is_empty() and not people.any(func(p: Array) -> bool: return p[1] == 0):
			people[0][1] = 0
		return people
	# Three watches of 8 hours: a third out at once (an officer on the bridge).
	var on := clampi(roundi(total * float(settings.on_deck_share)), 1, int(settings.max_on_deck))
	var watch := int(hour / 8.0) % 3
	var into := fposmod(hour, 8.0)
	for j in on:
		people.append([watch * 1000 + j, 0 if j == 0 else 1, minf(into / HANDOVER_H, 1.0), false])
	if into < HANDOVER_H:
		var last := (watch + 2) % 3
		for j in on:
			if j == 0:
				continue  # (The officers hand over on the bridge.)
			people.append([last * 1000 + j, 1, 1.0 - into / HANDOVER_H, true])
	return people


## The jobs on deck now, for the hands in turn: [where, facing, walk phase, tool].
static func _jobs(ship: Ship, plan: Dictionary, now: float) -> Array:
	var jobs := []
	var bow: Array = plan.get("bow", [])
	var stern: Array = plan.get("stern", [])
	if ship.is_docked() and not ship.is_tug():
		var lines := false
		if ship.berth >= 0:
			lines = ship.berth_phase == Ship.BERTH_IN or ship.berth_phase == Ship.BERTH_OUT
			if ship.is_docking():
				var stop := maxf(ship.dock_seconds(), 1.0)
				lines = lines or ship.dock_time < stop * LINES_SHARE or ship.dock_time > stop * (1.0 - LINES_SHARE)
		if lines:
			# Lines fore and aft: two at the bow, two at the stern.
			for k in 4:
				var spots: Array = bow if k % 2 == 0 else stern
				if spots.is_empty():
					continue
				var spot: Array = spots[(k / 2) % spots.size()]
				var at := Vector2(spot[0], spot[1])
				jobs.append([at, _outward(plan, at), -1.0, TOOL_LINE])
		elif ship.berth < 0 and not bow.is_empty():
			# The anchor watch, at the windlass.
			var at := Vector2(bow[0][0] - 4.0, (bow[0][1] + bow[bow.size() - 1][1]) / 2.0)
			jobs.append([at, 0.0, -1.0, TOOL_NONE])
		return jobs
	if not ship.is_working_ground():
		return jobs
	var gear: Array = ship.model().get("fishing", {}).get("gear", [])
	var kind := str(Fisheries.shared().species.get(ship.fish_species, {}).get("gear", "troll"))
	if not gear.has(kind):
		kind = str(gear[0]) if not gear.is_empty() else "troll"
	var seed := ship.id * 7919
	match kind:
		"troll":
			var rods: Array = plan.get("rods", stern)
			if rods.is_empty():
				return jobs
			var cycle := fposmod(now + float(seed % 97), STRIKE_EVERY_S)
			if cycle < STRIKE_S:
				# Fish on! One fights it at the rod, one stands by with the gaff.
				var rod: Array = rods[int((now + float(seed % 97)) / STRIKE_EVERY_S) % rods.size()]
				var at := Vector2(rod[0] + 5.0, rod[1])
				jobs.append([at, PI + 0.25 * sin(now * 2.1), -1.0, TOOL_FIGHT])
				var side := 1.0 if at.y < float(plan.h) / 2.0 else -1.0
				jobs.append([at + Vector2(4.0, side * 7.0), PI * 0.85, -1.0, TOOL_NONE])
			else:
				# Watching the lines: one by the rods.
				var rod: Array = rods[0]
				jobs.append([Vector2(rod[0] + 7.0, rod[1] + (6.0 if rod[1] < float(plan.h) / 2.0 else -6.0)), PI, -1.0, TOOL_NONE])
		"net":
			for spot: Array in plan.get("reel", stern):
				jobs.append([Vector2(spot[0] + 7.0, spot[1]), PI, -1.0, TOOL_LINE])
		"trawl":
			for spot: Array in plan.get("winch", stern):
				jobs.append([Vector2(spot[0] + 5.0, spot[1]), PI, -1.0, TOOL_LINE])
		"trap":
			var haulers: Array = plan.get("hauler", [])
			var stacks: Array = plan.get("stack", [])
			for spot: Array in haulers:
				var at := Vector2(spot[0], spot[1])
				jobs.append([at + Vector2(-4.0, 4.0 if at.y < float(plan.h) / 2.0 else -4.0), _outward(plan, at), -1.0, TOOL_LINE])
			if haulers.is_empty() or stacks.is_empty():
				return jobs
			# The rest carry pots from the hauler to the stacks and come back for more.
			for k in 4:
				var trip := fposmod(now + k * POT_TRIP_S / 4.0 + float(seed % 13), POT_TRIP_S) / POT_TRIP_S
				var lap := int((now + k * POT_TRIP_S / 4.0 + float(seed % 13)) / POT_TRIP_S)
				var stack: Array = stacks[(lap * 3 + k) % stacks.size()]
				var hauler: Array = haulers[k % haulers.size()]
				var a := Vector2(hauler[0] - 8.0, hauler[1] + (8.0 if hauler[1] < float(plan.h) / 2.0 else -8.0))
				var b := Vector2(stack[0], stack[1])
				if trip < 0.45:
					var f := trip / 0.45
					jobs.append([a.lerp(b, f), (b - a).angle(), f * a.distance_to(b), TOOL_POT])
				elif trip < 0.55:
					jobs.append([b, (b - a).angle(), -1.0, TOOL_POT if trip < 0.5 else TOOL_NONE])
				else:
					var f := (trip - 0.55) / 0.45
					jobs.append([b.lerp(a, f), (a - b).angle(), f * a.distance_to(b), TOOL_NONE])
	return jobs


## A hand wandering the open deck: from one spot to the next each WANDER_S,
## walking there and standing about. Mostly about one stretch of deck, now and
## then another.
static func _wander(plan: Dictionary, seed: int, now: float, speed: float) -> Array:
	var t := now + float(seed % 1000) * 0.0137 * WANDER_S
	var leg := floori(t / WANDER_S)
	var into := (t - leg * WANDER_S)
	var from := _spot(plan, seed, leg - 1)
	var to := _spot(plan, seed, leg)
	var distance := from.distance_to(to)
	var takes := minf(distance / maxf(speed, 0.01), WANDER_S * 0.8)
	if into < takes and distance > 0.5:
		var f := into / takes
		return [from.lerp(to, f), (to - from).angle(), 1, f * distance, TOOL_NONE, seed]
	# Standing: looking out over the side now and then, or about.
	var look := (to - Vector2(90.0, float(plan.h) / 2.0)).angle() if (seed + leg) % 3 == 0 else float((seed + leg * 37) % 628) / 100.0
	return [to, look, 1, -1.0, TOOL_NONE, seed]


## A wanderer's spot for a leg: in a stretch of open deck (the same one for a
## few legs running), anywhere in it.
static func _spot(plan: Dictionary, seed: int, leg: int) -> Vector2:
	var boxes: Array = plan.walk
	var stretch := absi(hash([seed, floori(leg / 4.0)]))
	# (Weighted by size, so the wide decks have more people about.)
	var areas := 0.0
	for box: Array in boxes:
		areas += float(box[2]) * float(box[3])
	var pick := float(stretch % 10007) / 10007.0 * areas
	var chosen: Array = boxes[0]
	for box: Array in boxes:
		pick -= float(box[2]) * float(box[3])
		chosen = box
		if pick <= 0.0:
			break
	var h := absi(hash([seed, leg]))
	return Vector2(float(chosen[0]) + float(h % 1000) / 1000.0 * float(chosen[2]), float(chosen[1]) + float((h / 1000) % 1000) / 1000.0 * float(chosen[3]))


## Facing out from the middle of the deck towards a spot (over the side at the
## rails, ahead at the bow, astern at the stern).
static func _outward(plan: Dictionary, at: Vector2) -> float:
	var middle := Vector2(90.0, float(plan.h) / 2.0)
	var away := at - middle
	if absf(away.x) > 70.0:
		return 0.0 if away.x > 0.0 else PI
	return PI / 2.0 if away.y > 0.0 else -PI / 2.0

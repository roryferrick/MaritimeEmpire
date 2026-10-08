# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name LandLife
extends RefCounted
## The land animals (data/birds.json land_animals) going about their lives
## where the map draws them, just for looking at: each spot is a group's
## patch, and its group (a realistic number for the species: a lone tiger, a
## mother bear and cubs, a herd of bison) roams it together. Worked out from
## the clock alone, so nothing is saved.
##
## Time goes in spells of BEAT_S. In each, an animal either sets off
## somewhere new in the patch (by its gait: walking, hopping, waddling,
## flitting, swinging; a penguin may toboggan on its belly, a panda roll over
## a few times on the way), then stands about; or stays put, resting or doing
## one of its species' acts (a bear rubbing its back on its tree, a lion
## napping, an elephant spraying water...). The herd's middle drifts every
## PERIOD_BEATS spells and its members spread round it; young stay close by
## their mother and play.
##
## Everything is in art widths (the drawing's size on screen), from the
## patch's spot, so a group keeps its look at every zoom.

const BEAT_S := 7.0
const PERIOD_BEATS := 5
## How far back (spells) to look for where an animal last went.
const LOOK_BACK := 24
## Each act's length (s); others ACT_DEFAULT_S.
const ACT_S := {nap = 5.5, sleep = 6.0, rub = 5.0, roll = 2.4, spray = 3.0, dust = 3.0, wallow = 4.0, sprawl = 5.0, rear = 3.0,
	stretch = 2.5, graze = 5.0, chew = 4.0, sit = 5.0, hang = 5.0, sunbathe = 5.0, box = 2.5, kick = 1.2, spit = 1.5, chest = 2.0,
	roar = 2.2, toss = 1.5, peck = 3.0, hop = 2.0, preen = 3.0, flap = 2.0, kneel = 5.0, splay = 4.0, browse = 4.0, scratch = 1.5,
	wriggle = 3.5, nod = 2.0}
const ACT_DEFAULT_S := 3.0
## Acts that are a way of getting somewhere, not something done in place.
const TRAVEL_ACTS := ["slide", "roll"]
## How far (art widths) one step, hop or swing carries each gait.
const STRIDES := {walk = 0.25, waddle = 0.18, hop = 0.6, flit = 0.9, swing = 0.7, slide = 1.0, roll = 1.0}
## Where a bear stands to rub its back on its tree (art widths from the tree).
const RUB_OFFSET := Vector2(0.42, 0.0)
const YOUNG_SIZE := 0.55
## Where on the drawing its feet are (a share of its side, down).
const FEET := 0.92

## Whether each member set off in each spell (see _moves()), remembered, up
## to MEMO_MAX of them.
const MEMO_MAX := 20000
static var _moved := {}

## "patch/member" -> what it's doing this spell (see _spell()).
var _spells := {}


## How many are in a patch's group.
static func group_size(key: String, info: Dictionary) -> int:
	var group: Array = info.get("group", [1, 1])
	var fewest := int(group[0])
	var most := maxi(int(group[1]), fewest)
	return fewest + mini(floori(Birds.chance([key, "count"]) * (most - fewest + 1)), most - fewest)


## True if a group's member is young (drawn small, close by the first, its mother).
static func is_young(key: String, info: Dictionary, member: int) -> bool:
	return member > 0 and Birds.chance([key, member, "young"]) < float(info.get("young", 0.0))


## Where a bear's patch has its rubbing tree (art widths from the spot), or
## null for a species without one.
static func tree_spot(key: String, info: Dictionary) -> Variant:
	if not info.has("tree"):
		return null
	var roam := float(info.get("roam", 2.0))
	return _in_disc([key, "tree"], roam * 0.55) - RUB_OFFSET * 0.5


## Every member of a patch's group now: [{at (art widths from the spot, its
## feet), pivot (where on the drawing it turns, a share of its side), rot,
## scale, facing (1 right, -1 left on screen), size (of the art), act, moving
## (its gait or travel act while it's on its way, else ""), u (how
## far through it, 0 to 1), t (s into it)}].
func poses(key: String, info: Dictionary, now: float) -> Array:
	var out := []
	var count := group_size(key, info)
	var phase := Birds.chance([key, "phase"]) * BEAT_S * PERIOD_BEATS
	var clock := now + phase
	var n := floori(clock / BEAT_S)
	var into := clock - n * BEAT_S
	for member in count:
		var spell := _spell(key, info, member, n)
		out.append(_pose(info, spell, into, is_young(key, info, member)))
	return out


# --- What each is doing ---------------------------------------------------------

## What a member does in spell n: {start, end (art widths), moving, style
## (its gait, or a travel act), act (after it gets there, or in place),
## facing}. Kept till the spell changes.
func _spell(key: String, info: Dictionary, member: int, n: int) -> Dictionary:
	var id := "%s/%d" % [key, member]
	var kept: Dictionary = _spells.get(id, {})
	if kept.get("n", -1) == n:
		return kept
	var young := is_young(key, info, member)
	var mover := 0 if young else member  # Young go when their mother does.
	var moving := _moves(key, info, mover, n)
	var spell := {n = n, start = _spot_at(key, info, member, n - 1), end = _spot_at(key, info, member, n), moving = moving,
		style = str(info.get("gait", "walk")), act = "rest", facing = _facing(key, info, member, n)}
	var acts: Array = info.get("young_acts" if young else "acts", [])
	var roll := Birds.chance([key, member, n, "act"])
	if moving:
		var travel := acts.filter(func(a: String) -> bool: return TRAVEL_ACTS.has(a))
		if not young and not travel.is_empty() and Birds.chance([key, member, n, "style"]) < 0.4:
			spell.style = travel[floori(Birds.chance([key, member, n, "which"]) * travel.size()) % travel.size()]
		if _rubs(key, info, member, n):
			spell.act = "rub"
	else:
		var in_place := acts.filter(func(a: String) -> bool: return a != "rub" and (young or not TRAVEL_ACTS.has(a)))
		if not in_place.is_empty() and roll < float(info.get("busy", 0.6 if young else 0.5)):
			spell.act = in_place[floori(Birds.chance([key, member, n, "which"]) * in_place.size()) % in_place.size()]
		elif _rubs_now(key, info, member, n):
			spell.act = "rub"  # Still at its tree: rubbing on.
	_spells[id] = spell
	return spell


## True if a member sets off somewhere in spell n (always as the herd moves on).
static func _moves(key: String, info: Dictionary, member: int, n: int) -> bool:
	if posmod(n, PERIOD_BEATS) == 0:
		return true
	var id := "%s/%d/%d" % [key, member, n]
	if not _moved.has(id):
		if _moved.size() > MEMO_MAX:
			_moved.clear()
		_moved[id] = Birds.chance([key, member, n, "move"]) < float(info.get("moves", 0.45))
	return _moved[id]


## True if a bear goes to its tree in spell n.
static func _rubs(key: String, info: Dictionary, member: int, n: int) -> bool:
	return member == 0 and info.has("tree") and (info.get("acts", []) as Array).has("rub") \
		and _moves(key, info, member, n) and posmod(n, PERIOD_BEATS) != 0 and Birds.chance([key, member, n, "rub"]) < 0.35


## True if a bear is still standing at its tree in spell n (it went there and hasn't moved since).
static func _rubs_now(key: String, info: Dictionary, member: int, n: int) -> bool:
	var went := _last_move(key, info, member, n)
	return _rubs(key, info, member, went)


## The last spell, n or before, a member set off in.
static func _last_move(key: String, info: Dictionary, member: int, n: int) -> int:
	for j in range(n, n - LOOK_BACK, -1):
		if _moves(key, info, member, j):
			return j
	return n - LOOK_BACK


## Where a member is once it's got where it went by spell n (art widths).
static func _spot_at(key: String, info: Dictionary, member: int, n: int) -> Vector2:
	if is_young(key, info, member):
		# By its mother, a little way off (changing as she moves).
		var went := _last_move(key, info, 0, n)
		return _spot_at(key, info, 0, n) + _in_disc([key, member, went, "by"], 0.55) + Vector2(0.0, 0.08)
	return _target(key, info, member, _last_move(key, info, member, n))


## Where a member heads in a spell it sets off in: its tree (a bear going to
## rub), or its place round the herd's middle that period.
static func _target(key: String, info: Dictionary, member: int, n: int) -> Vector2:
	if _rubs(key, info, member, n):
		return (tree_spot(key, info) as Vector2) + RUB_OFFSET
	var roam := float(info.get("roam", 2.0))
	var count := group_size(key, info)
	var middle := _in_disc([key, floori(float(n) / PERIOD_BEATS), "herd"], roam * 0.6)
	var spread := (0.5 + 0.45 * sqrt(float(count))) * float(info.get("size", 0.8)) if count > 1 else 0.0
	var spot := middle + _in_disc([key, member, n, "place"], spread)
	return spot.limit_length(roam)


## Which way a member faces in spell n: the way it last went (a bear at its
## tree faces away from it), or its own way if it hasn't really moved.
static func _facing(key: String, info: Dictionary, member: int, n: int) -> float:
	var went := _last_move(key, info, 0 if is_young(key, info, member) else member, n)
	if not is_young(key, info, member) and _rubs(key, info, member, went):
		return 1.0
	var way := _spot_at(key, info, member, went).x - _spot_at(key, info, member, went - 1).x
	if absf(way) > 0.05:
		return signf(way)
	return 1.0 if Birds.chance([key, member, went, "face"]) < 0.5 else -1.0


## A steady point in a disc (radius r) for the parts given.
static func _in_disc(parts: Array, r: float) -> Vector2:
	var angle := Birds.chance(parts + ["a"]) * TAU
	return Vector2.from_angle(angle) * r * sqrt(Birds.chance(parts + ["r"]))


# --- How it looks ---------------------------------------------------------------

## A member's pose `into` seconds into its spell.
func _pose(info: Dictionary, spell: Dictionary, into: float, young: bool) -> Dictionary:
	var faces := str(info.get("faces", "left"))
	var head_x := 0.2 if faces == "left" else (0.8 if faces == "right" else 0.5)
	var pose := {at = spell.end, pivot = Vector2(0.5, FEET), rot = 0.0, scale = Vector2.ONE, facing = float(spell.facing),
		size = float(info.get("size", 0.8)) * (YOUNG_SIZE if young else 1.0), act = "rest", moving = "", u = 0.0, t = into, head = Vector2(head_x, 0.35)}
	var f := float(spell.facing)
	var start: Vector2 = spell.start
	var end: Vector2 = spell.end
	var act_from := 0.15 * BEAT_S
	if spell.moving:
		var distance := start.distance_to(end)
		var pace := float(info.get("pace", 0.3))
		var travel_s := clampf(distance / maxf(pace, 0.01), 0.6, BEAT_S * 0.8)
		if into < travel_s and distance > 0.01:
			var way := end.x - start.x
			if absf(way) > 0.02:
				pose.facing = signf(way)
				f = pose.facing
			# Easing off at the start and end.
			var u := into / travel_s
			var gone := lerpf(u, smoothstep(0.0, 1.0, u), 0.35)
			gone = clampf(gone, 0.0, 1.0)
			pose.at = start.lerp(end, gone)
			pose.moving = str(spell.style)
			_gait(pose, str(spell.style), gone * distance, u, f, head_x)
			return pose
		act_from = travel_s
	var act := str(spell.act)
	if act == "rest":
		pose.scale = Vector2(1.0, 1.0 + 0.012 * sin(into * 2.2))  # Breathing.
		return pose
	var length := float(ACT_S.get(act, ACT_DEFAULT_S))
	if act == "rub":
		length = BEAT_S - act_from  # On till the spell's out.
	var t := into - act_from
	if t < 0.0 or t > length:
		return pose
	pose.act = act
	pose.t = t
	pose.u = t / length
	_act(pose, act, t / length, t, f, head_x)
	return pose


## Moving by its gait (or a travel act), `gone` art widths along, u of the way.
static func _gait(pose: Dictionary, style: String, gone: float, u: float, f: float, head_x: float) -> void:
	var step := gone / float(STRIDES.get(style, 0.25)) * PI
	var lift := 0.0
	match style:
		"walk":
			lift = absf(sin(step)) * 0.025
			pose.rot = 0.035 * sin(step * 2.0)
		"waddle":
			lift = absf(sin(step)) * 0.03
			pose.rot = 0.16 * sin(step)
		"hop":
			lift = absf(sin(step)) * 0.35
			pose.rot = -f * 0.12 * cos(step)
		"flit":
			lift = absf(sin(step)) * 0.55
			pose.scale = Vector2(1.0, 1.0 - 0.08 * absf(cos(step)))
		"swing":
			lift = absf(sin(step)) * 0.12
			pose.pivot = Vector2(0.5, 0.08)
			pose.rot = 0.3 * sin(step)
		"slide":
			# Flopping down on its belly, head first, and tobogganing along.
			var lie := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))
			pose.pivot = Vector2(0.5, 0.62)
			pose.rot = f * PI / 2.0 * lie
			lift = -0.3 * lie
		"roll":
			# Rolling over and over (three times), the way it's going.
			pose.pivot = Vector2(0.5, 0.6)
			pose.rot = f * TAU * 3.0 * smoothstep(0.0, 1.0, u)
			lift = 0.05 * absf(sin(u * PI * 3.0))
	pose.at = (pose.at as Vector2) - Vector2(0.0, lift)


## Doing an act, u of the way through it (t s in).
static func _act(pose: Dictionary, act: String, u: float, t: float, f: float, head_x: float) -> void:
	var on := smoothstep(0.0, 0.15, u) * (1.0 - smoothstep(0.85, 1.0, u))
	var hind := Vector2(1.0 - head_x if head_x != 0.5 else 0.5, FEET)
	var front := Vector2(head_x, FEET)
	var lift := 0.0
	match act:
		"chew", "nod", "groom":
			if head_x == 0.5:
				pose.scale = Vector2(1.0, 1.0 - 0.04 * absf(sin(t * 6.0)) * on)
			else:
				pose.pivot = front
				pose.rot = f * 0.06 * absf(sin(t * 6.0)) * on
		"graze":
			pose.pivot = front
			pose.rot = f * (0.16 + 0.04 * sin(t * 6.0)) * on
		"peck":
			pose.pivot = front
			pose.rot = f * 0.28 * maxf(sin(t * 9.0), 0.0) * on
		"rear":
			pose.pivot = hind
			pose.rot = -f * (1.05 + 0.05 * sin(t * 5.0)) * on
		"rub":
			# Up on its hind legs, back to its tree, rubbing up and down.
			pose.pivot = hind
			pose.rot = -f * 1.3 * on
			lift = on * (0.04 + 0.04 * sin(t * 5.0))
		"sprawl", "nap", "sleep":
			pose.scale = Vector2(1.0 + 0.1 * on, 1.0 - 0.3 * on)
		"wriggle", "wallow":
			# Over onto its back, legs in the air, wriggling.
			pose.pivot = Vector2(0.5, 0.6)
			pose.rot = f * PI * on + 0.15 * sin(t * 9.0) * on
		"roll":
			pose.pivot = Vector2(0.5, 0.6)
			pose.rot = f * TAU * 2.0 * smoothstep(0.0, 1.0, u)
			lift = 0.1 * absf(sin(u * TAU))
		"spray", "dust":
			pose.pivot = hind
			pose.rot = -f * 0.06 * on
		"browse":
			pose.scale = Vector2(1.0, 1.0 + 0.12 * on)
		"splay":
			pose.pivot = front
			pose.scale = Vector2(1.0 + 0.18 * on, 1.0 - 0.22 * on)
			pose.rot = f * 0.15 * on
		"roar":
			var pulse := 1.0 + 0.06 * on * absf(sin(t * 4.0))
			pose.scale = Vector2(pulse, pulse)
		"kick":
			pose.pivot = front
			pose.rot = f * 0.45 * sin(u * PI)
			lift = 0.05 * sin(u * PI)
		"box":
			pose.pivot = hind
			pose.rot = -f * 0.55 * on
			pose.at = (pose.at as Vector2) + Vector2(f * 0.05 * sin(t * 14.0) * on, 0.0)
		"scratch":
			pose.at = (pose.at as Vector2) + Vector2(0.02 * sin(t * 30.0) * on, 0.0)
		"kneel":
			pose.scale = Vector2(1.0 + 0.05 * on, 1.0 - 0.3 * on)
		"toss":
			pose.pivot = Vector2(0.5, 0.6)
			pose.rot = -f * 0.2 * sin(u * TAU * 3.0) * on
		"spit":
			pose.pivot = hind
			pose.rot = -f * 0.08 * on
		"chest":
			pose.scale = Vector2(1.0 + 0.05 * sin(t * 40.0) * on, 1.0)
		"sit":
			pose.scale = Vector2(1.0, 1.0 - 0.12 * on)
		"hang":
			pose.pivot = Vector2(0.5, 0.08)
			pose.rot = 0.3 * sin(t * 2.2) * on
			lift = 0.1 * on
		"sunbathe":
			pose.scale = Vector2(1.0 + 0.08 * on, 1.0 + 0.04 * on)
		"flap":
			pose.scale = Vector2(1.0 + 0.12 * absf(sin(t * 10.0)) * on, 1.0)
		"stretch":
			pose.scale = Vector2(1.0 + 0.18 * on, 1.0 - 0.15 * on)
		"hop":
			lift = absf(sin(t * 6.0)) * 0.15 * on
		"preen":
			pose.rot = 0.08 * sin(t * 5.0) * on
	pose.at = (pose.at as Vector2) - Vector2(0.0, lift)

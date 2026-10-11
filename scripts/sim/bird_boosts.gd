# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name BirdBoosts
extends RefCounted
## The birds that follow a ship each give it a little something, every species
## its own mix (BOOSTS: the share of speed gained, wear and fuel saved, and
## the storm's slowing and wearing shrugged off), a species' once it has a
## bird or more aboard and a little more for a few more birds, all the
## species following added up and capped (CAPS). Gulls are small change; an
## albatross is the prize (speed and storm shelter), pelicans save fuel and
## wear, terns are quick, frigatebirds and shearwaters weather storms,
## condors keep a ship sound. GameState.bird_boosts() works them out from
## BirdLife.following() and GameState._storm_factors() applies them.

## Species id -> [speed %, wear saved %, fuel saved %, storm protection %].
const BOOSTS := {
	herring = [1, 1, 0, 0], great_black_backed = [0, 2, 0, 5], lesser_black_backed = [1, 1, 1, 0], yellow_legged = [2, 0, 0, 0],
	black_headed = [1, 0, 1, 0], ring_billed = [0, 1, 1, 0], laughing = [1, 0, 0, 5], california = [0, 0, 2, 0], western = [1, 1, 0, 0],
	glaucous_winged = [0, 2, 0, 5], black_tailed = [1, 0, 1, 0], heermanns = [2, 0, 0, 0], sooty = [0, 1, 0, 5], kelp = [0, 2, 1, 0], silver = [1, 0, 1, 0],
	magnificent_frigatebird = [3, 0, 0, 15], great_frigatebird = [2, 0, 1, 15],
	andean_condor = [0, 4, 0, 5], california_condor = [0, 3, 1, 5],
	wandering_albatross = [4, 0, 2, 25], black_browed_albatross = [3, 1, 1, 20], laysan_albatross = [2, 0, 3, 15],
	arctic_tern = [3, 0, 2, 0], common_tern = [2, 0, 2, 0], caspian_tern = [2, 1, 1, 0], royal_tern = [2, 0, 1, 5],
	brown_pelican = [0, 3, 3, 0], great_white_pelican = [0, 2, 4, 0], australian_pelican = [1, 2, 2, 0],
	sooty_shearwater = [1, 1, 1, 20], manx_shearwater = [1, 0, 2, 15],
}
## The most a ship gets all told (%), and how much more a few birds of a
## species give than one (a share per extra bird, up to EXTRA_BIRDS of them).
const CAPS := [12.0, 25.0, 15.0, 60.0]
const EXTRA_PER_BIRD := 0.15
const EXTRA_BIRDS := 3
const NAMES := ["speed", "wear", "fuel", "storm"]


## A species' boost ([speed, wear, fuel, storm] shares, 0..1) for `count` birds, or [] if it gives none.
static func of(species: String, count: int) -> Array:
	if not BOOSTS.has(species):
		return []
	var more := 1.0 + EXTRA_PER_BIRD * clampi(count - 1, 0, EXTRA_BIRDS)
	var out := []
	for value: int in BOOSTS[species]:
		out.append(float(value) / 100.0 * more)
	return out


## What a ship gets from the birds following it (BirdLife.following()):
## {speed, wear, fuel, storm} shares (0..1), capped.
static func total(following: Array) -> Dictionary:
	var sums := [0.0, 0.0, 0.0, 0.0]
	for entry: Dictionary in following:
		var boost := of(str(entry.id), int(entry.count))
		for i in 4:
			if not boost.is_empty():
				sums[i] += float(boost[i])
	var out := {}
	for i in 4:
		out[NAMES[i]] = minf(float(sums[i]), float(CAPS[i]) / 100.0)
	return out


## The boosts as a line for a popup ("+3% speed, 2% less wear, storm shelter 15%"), or "".
static func describe(boosts: Dictionary) -> String:
	var parts := PackedStringArray()
	if float(boosts.get("speed", 0.0)) > 0.0:
		parts.append("+%d%% speed" % roundi(float(boosts.speed) * 100.0))
	if float(boosts.get("wear", 0.0)) > 0.0:
		parts.append("%d%% less wear" % roundi(float(boosts.wear) * 100.0))
	if float(boosts.get("fuel", 0.0)) > 0.0:
		parts.append("%d%% less fuel" % roundi(float(boosts.fuel) * 100.0))
	if float(boosts.get("storm", 0.0)) > 0.0:
		parts.append("%d%% storm shelter" % roundi(float(boosts.storm) * 100.0))
	return ", ".join(parts)

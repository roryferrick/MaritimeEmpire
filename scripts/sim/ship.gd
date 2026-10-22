# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Ship
extends RefCounted
## A player-owned ship. Holds state only; GameState moves it.
##
## A ship is either docked (docked_at is set) or sailing a leg from_port -> to_port.
## Routes are loops of port ids; route_index is the route stop the ship is at or
## heading to.
##
## Maintenance (0..1) wears down while the ship runs at sea and slows it down
## (at 0% it stops); fuel burns at a constant rate per second at sea. After
## arriving, a ship docks for dock_seconds(): it unloads (and is paid), is
## repaired then refueled if those toggles are on, and loads again before it
## can leave.
##
## A ship that runs out of fuel or maintenance at sea is lost until a recovery
## boat (a Mammoth, or a Buffalo for small ships) tows it to the nearer
## end of its leg. A recovery boat has no route: it sails a job (a list of lane
## segments) to the lost ship, turns to line up with it, carries it to port,
## then sails home.

## How long a recovery boat takes to pull up in line clear ahead of a lost
## ship, and an icebreaker or tug to turn (round a turning circle on the map).
const ALIGN_SECONDS := 3.0
## How long a recovery boat with a ship aboard takes to spin round on the spot
## when the port it's taking it to is back the way it came.
const SPIN_SECONDS := 2.0

## Job phases for a Mammoth.
const JOB_NONE := ""
const JOB_APPROACH := "approach"
const JOB_ALIGN := "align"
const JOB_TOW := "tow"
const JOB_UNLOAD := "unload"
## Tug only: at its port after a tow, working the ship onto its berth (or to
## its spot at the anchorage) before it lets go (see GameState._advance_tug_job()).
const JOB_BERTH := "berth"
## How long a recovery boat takes to load a lost ship (ballast down, float it
## onto the deck, deballast and rise) and, at port, to float it off again.
const LOAD_SECONDS := 4.5

## A cargo ship in port (berth_phase; see Docks): moored at its berth (or, with
## no berth, lying at the anchorage), queuing at the anchorage for a berth,
## coming alongside, or pulling out.
const BERTH_NONE := ""
const BERTH_WAIT := "wait"
const BERTH_IN := "in"
const BERTH_OUT := "out"
## The zone of open sea, past a leg's last zone (see zone_at()).
const OPEN_SEA_ZONE := [INF, 1.0, 1.0]

## A ship sells for this fraction of its price, times its maintenance.
const SELL_FRACTION := 0.5
## Kinds of ship (see _kind()).
const KIND_CARGO := 0
const KIND_RECOVERY := 1
const KIND_ICEBREAKER := 2
const KIND_TUG := 3
const KIND_FISHING := 4
## A fishing or crabbing trip (see GameState._advance_fishing()): it's on a
## job the whole time it's away, out to its ground, working it and home.
const JOB_FISH := "fish"
## A rig run (see GameState._advance_rig()): a tanker or gas carrier out to its
## company's rigs at a field (rig_field) and back to its delivery port, on a
## job the whole time it's away; and a tug out to repair a damaged rig (its
## slot rig_slot) and home again.
const JOB_RIG := "rig"
const JOB_REPAIR := "repair"
## An expedition (see Research): a research ship out to a site (or a
## contract's field or ground), on station, and home to its base.
const JOB_RESEARCH := "research"

## Canal states (canal_state; see CanalTraffic): heading into a lock chamber
## it has reserved, waiting in line for one, waiting for toll money, at anchor
## for a convoy, or in a convoy that has left and waiting its turn to enter.
const CANAL_RESERVED := CanalTraffic.RESERVED
const CANAL_QUEUED := CanalTraffic.QUEUED
const CANAL_TOLL := CanalTraffic.TOLL
const CANAL_ANCHORED := CanalTraffic.ANCHORED
const CANAL_CONVOY := CanalTraffic.CONVOY

## A number no other ship in the game has (see GameState.next_ship_id); how
## multiplayer games refer to it.
var id := 0
var name := ""
## The company that owns it (see GameState.owner_of()); saved by its place in
## GameState.companies.
var company: Company = null
var model_id := ""
var route: Array[String] = []
## Replaces route when the ship reaches the end of its current leg.
var pending_route: Array[String] = []
var route_index := -1
## Bound for a port beyond one tank (GameState.refuel_path()): that port, while it
## steps there by way of refuel stops (to_port the next of them), "" otherwise.
## A port it stops at on the way is only a refuel stop: no trade, its cargo
## or catch stays aboard.
var hop_to := ""
## Where _try_depart() last meant it to end up (hop_to as it sets off). Not saved.
var bound_for := ""
## The leg _try_depart() meant bound_for for (its next stop then).
var bound_step := ""
var paused := false
## One of the world's other shipping firms' ships, drawn as ambient traffic
## (AmbientTraffic): not in GameState.ships, nothing of the player's.
var ghost := false
var docked_at := ""
var from_port := ""
var to_port := ""
var traveled_nm := 0.0

var fuel := 0.0
var maintenance := 1.0
## What the company paid for it (a first-purchase discount makes it less than
## the model's price); selling returns part of this.
var purchase_price := 0
var auto_refuel := true
var auto_repair := true
## Seconds since the ship docked at the end of a leg; -1 when not unloading/loading.
var dock_time := -1.0
## In port (cargo ships; see Docks): its berth (-1 at the anchorage), what
## it's doing about it (BERTH_*: moored or at anchor, queuing, coming
## alongside, pulling out), seconds into coming alongside or pulling out, when
## it joined the queue (play time), and the port it's pulling out to sail to
## ("" if it's going to the anchorage).
var berth := -1
## Which half of a big berth it shares with another smaller ship (see
## Docks.shares()): 0 the end nearer the coast, 1 the other; -1 the whole berth.
var berth_half := -1
## Its officers (Characters: {name, look}): the captain first, then its mates
## (GameState.crew_of()), made up when it was bought.
var captains: Array = []
var berth_phase := BERTH_NONE
var berth_time := 0.0
var berth_since := 0.0
## How long (s of play) its coming alongside or pulling out takes: the way in
## or out at its own speed, and the slide on or off the berth (see
## GameState._berth_seconds()); 0 for the fixed docks in_s and out_s.
var berth_duration := 0.0
var depart_to := ""
## The last storm to batter it at anchor (its Weather.key()), so each does
## only once (see GameState._batter_anchored()).
var storm_hit := ""
## Worked (sailed, did a job or a stop) since the last payday: its crew is
## paid then (see GameState._check_payday()).
var worked := false
## Queuing for a berth: its port's change count when it last tried, which
## port, and when it tries again anyway (see Docks.claim()). Not saved.
var claim_stamp := -1
var claim_port := ""
var claim_retry := 0.0
## How far into its stop (dock_time) its repairs and fuel have been done and
## paid for. Not saved: a stop carries on from where it was loaded.
var refill_billed := 0.0
## Cargo aboard (see Market): the commodity id ("" when empty), how many units,
## and what they cost to buy. On arrival, cargo_payment is what they sell for
## (paid when unloading finishes) and cargo_leg_nm the leg they came.
var cargo_id := ""
## Where the cargo aboard was bought.
var cargo_from := ""
var cargo_qty := 0
var cargo_cost := 0
var cargo_payment := 0
var cargo_leg_nm := 0.0
## A farm's livestock aboard: its breed ("" for plain stock and everything
## else), which its sale is worth more or less for (Farms.breed_value()).
var cargo_breed := ""
## Fresh cargo (fruit, berries, vegetables: Farms.is_fresh()): its freshness
## when loaded (1 from the market, less from a farm store) and when (play
## time); it loses Farms.loses_a_day() of its value a day aboard, keeps_fresh
## less on the bigger Fresh produce carriers (see cargo_value_factor()).
var cargo_fresh := 1.0
var cargo_since := 0.0
## True if the cargo aboard came from its company's farm store (Farms.load_ship()).
var cargo_farm := false
## Cargo from one of its company's factories (Manufacturers.load_ship()): the
## share of its sale the maker takes (0 for anything else).
var cargo_cut := 0.0
var unloaded := true
## Rates (per second) that refill what was missing on arrival within one refill phase.
var repair_rate := 0.0
var refuel_rate := 0.0
## Earned and spent at the current stop, for display (stop_cost: what the cargo
## sold here had cost to buy).
var stop_sale := 0
var stop_cost := 0
var stop_fuel_cost := 0.0
var stop_repair_cost := 0.0
## Fractions of a dollar spent but not yet taken from the player's money.
var bill := 0.0
## Why a running ship is stuck in port, or "".
var hold_reason := ""

## Going through canals (see CanalTraffic) on the current leg or job segment:
## how many of the lane's lock chambers (GameData.lane_chambers()) the ship has
## entered (-1 until worked out after loading an old save), seconds in the
## chamber it's in (-1 when not in one), which of a shared lock's parallel
## chambers it uses, CANAL_* or "", when it joined a line or anchorage, the
## canals it has entered (paying their tolls), and the tolls paid on this leg.
var canal_step := 0
var lock_time := -1.0
var lock_slot := ""
var canal_state := ""
var canal_queue_since := 0.0
var canals_entered: Array[String] = []
var leg_toll := 0
## Tolls paid on the leg that ended at this stop (counted in the stop's
## profit), and the canals the cargo being unloaded came through.
var stop_toll := 0
var delivery_canals: Array[String] = []

## Why this ship is stranded at sea ("out of fuel", "engine failure"), or "".
var lost_reason := ""
## Send the cheapest capable recovery boat automatically when lost.
var auto_recover := true
## Wait in port until it can buy a full hold before leaving (cargo ships).
var full_loads := true
## Its skin (Cosmetics): "" as the Shop (the pack worn there), "base" the ship
## as it is, or "pack/skin" (see GameState.set_skin(), SkinPicker).
var skin := ""
## Why it is waiting in port for a full load ("waiting for money for a full
## load"), or "". Not a problem, so not a hold.
var load_wait := ""
## Why weather is keeping it in port or off its next one ("waiting off Miami
## for Hurricane Ana to pass"), or "". Not a problem for the player either, and
## not saved: it's worked out again as the ship moves.
var weather_wait := ""
## When a ship waiting for a full load next looks for one (play_time); not saved.
var load_check_time := 0.0
## The money a full hold needed at its last look (see GameState._load_cargo()).
var load_need := 0
## Cached top_speed(), fuel_per_s() and wear_per_s() (see _refresh_stats()).
var _top_speed := 0.0
var _fuel_per_s := 0.0
var _wear_per_s := 0.0
var _stats_dirty := true
## The fuel the birds following it save (a share; see GameState.bird_boosts()).
var bird_fuel_saving := 0.0
## _kind(), once looked up (-1 until then).
var _kind_cache := -1
## The leg the cached length and zones are for (see _update_leg()).
var _leg_from := "?"
var _leg_to := "?"
var _leg_length := 0.0
var _leg_zones: Array = []
var _leg_has_canal := false
## The current leg's lane, and its sample() where the ship is ([position,
## heading]) with the mile it was taken at: the map asks for both every frame,
## so they're kept until the ship moves (see lane_sample()).
var _leg_lane: GameData.SeaLane = null
## The way it sails its leg, chosen as it sets off (GameData.way_now()) and
## kept to the end of the leg whatever the month does: leg_key ("FROM>TO")
## the leg it was chosen for, leg_current true if it rides the current's
## second way round, leg_month the month the currents push it by.
var leg_key := ""
var leg_current := false
var leg_month := Currents.MEAN
## Whole legs' seconds from full maintenance, for every ship (see
## leg_seconds()): [from, to, miles, top speed, wear a second] -> seconds.
static var _whole_legs := {}
## The last other leg's zones asked for (see leg_zones()): from, to, at what top speed.
var _zones_from := ""
var _zones_to := ""
var _zones_speed := -1.0
var _zones_month := -1
var _zones_asked: Array = []
var _here_cache: Array = []
var _here_mile := -1.0
## When it was lost, relative to other lost ships (lower = earlier), for the recovery queue.
var lost_order := 0
## At sea without the fuel (or maintenance) to reach the end of its leg.
var at_risk := false
## When it next checks whether it can make port (play_time; see
## GameState._check_at_risk()). Not saved.
var risk_check_time := 0.0
## The storm and ice [speed, wear] factors where it is (see
## GameState._storm_factors()) and when they're next looked at again. Not
## saved.
var storm_factors := [1.0, 1.0]
var storm_check_time := 0.0
## The ice area its leg runs into ({} if none) and the mile it enters it, kept
## until ice_check_time (see GameState._ice_hold()). Not saved.
var ice_area := {}
var ice_entry := -1.0
var ice_check_time := 0.0
## In port: the seasonal closure blocking its next leg ({} if none), for which
## port, kept until season_check_time (see GameState._try_depart()). Not saved.
var season_blocker := {}
var season_check_to := ""
var season_check_time := 0.0
## In port: held as beyond its reach for its next stop (reach_check_to), not
## looked at again till reach_check_time (see GameState._try_depart()). Not saved.
var reach_check_to := ""
var reach_check_time := 0.0
## Seconds spent sailing since it was bought; older ships break down more.
var sea_time := 0.0
## Lifetime money in (income: cargo sold) and out (cargo bought, fuel, repair
## and canal tolls), in dollars. A
## recovery boat's own running costs go on its own ledger.
var ledger := {"income": 0.0, "cargo": 0.0, "fuel": 0.0, "repair": 0.0, "tolls": 0.0, "port_fees": 0.0, "wages": 0.0}
## The Mammoth sent to recover this ship, if any.
var rescuer: Ship = null

## Mammoth only: the lost ship it's recovering, the job phase, where the
## current segment ends (nm along from_port -> to_port), the segments still to
## sail ([from, to, start_nm, end_nm]), seconds spent aligning, and the port
## it's towing to.
var rescuing: Ship = null
var job_phase := JOB_NONE
var segment_end := 0.0
var job_segments: Array = []
var align_time := 0.0
var tow_port := ""
## Recovery boat only: the current job's miles, all told and carrying the lost
## ship (see GameState._deliver()).
var job_nm := 0.0
var carry_nm := 0.0
## Recovery boat only: the HQ or hub port it's based at, returns to after a
## job, and sails to when the boats are rebalanced across hubs.
var base_port := ""
## Tug only: true for the tug that leads its job's tow; the other one pulls
## beside it (and pushes with it at port).
var tug_lead := false
## Tug only: seconds left before it leaves port on its job (the second tug
## follows the first out). Not saved: after loading it leaves at once.
var tug_wait := 0.0
## Tug only, in JOB_BERTH: how long (s) towing the ship to its spot at the
## anchorage takes, or -1 when it's bringing it alongside its berth instead.
var assist_s := -1.0
## Recovery boat only: the ship it's carrying faces the other way from it (it
## met the ship head on); set as it lines up.
var carry_reversed := false
## Fishing boat only: what it goes after (fish_target a species, fish_area
## the ground; both "" for the best this season, worked out each trip:
## Fisheries.options()); what it does with its catch landed (fish_landing:
## "auto" stores it for the company's seafood carriers where one calls at its
## base, else sells it; "sell"; "store"); its trip (fish_phase "out", "work"
## or "home"; the ground and species it's working; its catch in crates and
## their worth a crate's grade; the play seconds it's worked; why it's in
## port, if it can't go).
var fish_target := ""
var fish_area := ""
## On rig runs (Energy): the field it collects from and the port it delivers
## to (its route is just that port: see GameState._set_rig_run()); a tug sent
## to repair a rig, its slot. rig_phase "out", "load" (alongside the rigs) or
## "home" while away; rig_wait the play seconds it's waited at the field.
var rig_field := ""
var rig_port := ""
var rig_slot := ""
var rig_phase := ""
var rig_wait := 0.0
## Cruise ship only (is_cruise()): its cruise line's setup and state (Cruises):
## {cabins, amenities, service, looks, prices, monthly, package, departure,
## state, bookings, booking_since, voyage, reviews, refit_until, refit}.
var cruise := {}
## Research ship only (is_research()): its gear fitted (Research gear ids),
## the base it sets out from and comes home to, where it's going (a lane end:
## "@res_ID" for a site) and the contract it's for (0 for its own research);
## on an expedition its phase ("out", "work" on station, "home"), the play
## time on station so far, the time toward its next day's dives, and when it set out.
var research_gear: Array[String] = []
var research_base := ""
var research_target := ""
var research_contract := 0
var research_phase := ""
var research_work := 0.0
var research_roll := 0.0
var research_since := 0.0
var fish_landing := "auto"
var fish_phase := ""
var fish_ground := ""
var fish_species := ""
var catch := 0.0
var catch_grade := 1.0
var work_s := 0.0
var work_limit_s := 0.0
var fish_wait := ""
## Fishing boat only: the port its trip set out from and comes back to: its
## base, or, for a ground beyond a trip from its base, the port it went to
## first, by way of refuel stops, to fish from (see GameState.fishing_stage()).
var fish_home := ""
## Which of a ground's GameState.GROUND_BOATS spots it works (0 up), so boats on one ground spread out (MapView).
var fish_slot := 0
## Icebreaker only: the ice area (game_config icebreaking) it's stationed at,
## or ""; base_port is then the port there it waits at.
var station := ""
## Icebreaker only: the ships it's leading (or going to fetch) in its convoy.
## Not saved: a convoy under way when the game is saved forms again after.
var convoy: Array[Ship] = []
## Icebreaker only: "approach" (sailing to the convoy) or "escort" (leading
## it), and where the escort ends ([from, to, end mile]); not saved.
var ice_phase := ""
var escort_leg: Array = []
## A ship in an icebreaker's convoy: the icebreaker, and its place in line (0
## first). ice_wait: the ice area it's waiting at the edge of, or "".
var escort: Ship = null
var escort_place := 0
var ice_wait := ""
## When it started waiting (play time, for first come first served), and a
## docked ship's destination for the leg it's waiting to be led out on.
var ice_wait_since := 0.0
var ice_to := ""


func _init(ship_name := "", ship_model_id := "", start_port := "") -> void:
	name = ship_name
	model_id = ship_model_id
	docked_at = start_port
	fuel = fuel_tank()
	purchase_price = int(model().get("price", 0))


func model() -> Dictionary:
	return GameData.get_ship_model(model_id)


## A recovery boat (Mammoth or Buffalo): recovers lost ships instead of sailing routes.
func is_recovery() -> bool:
	return _kind() == KIND_RECOVERY


## An icebreaker (diesel or nuclear): stationed at an ice area, it leads
## convoys through its seasonal ice instead of sailing routes.
func is_icebreaker() -> bool:
	return _kind() == KIND_ICEBREAKER


## A tug: based at a port on the company's routes, it tows ships
## lost near there back in (see GameState.tug_plan()).
func is_tug() -> bool:
	return _kind() == KIND_TUG


## A fishing or crabbing boat: based at a port, it sails out to a fishing
## ground, works it and brings its catch home (see GameState._advance_fishing()).
func is_fishing() -> bool:
	return _kind() == KIND_FISHING


## True while a fishing boat is at work on its ground (on its trip, not in
## port): the only time its gear is out (lines, pots, nets; rods rigged, the
## crew at them).
func is_working_ground() -> bool:
	return is_fishing() and job_phase == JOB_FISH and fish_phase == "work" and docked_at.is_empty()


## Fishing boat only: "crabbing" or "fishing", by its gear.
func fishing_line() -> String:
	return "crabbing" if str(model().get("category", "")) == "crabbing" else "fishing"


## A service ship (a recovery boat, an icebreaker, a tug or a fishing boat):
## no route; pays its own fuel and repairs, and (but for a fishing boat) is
## never lost at sea.
## True for a cruise ship (its model has cruise: see Cruises).
func is_cruise() -> bool:
	return model().has("cruise")


## True for a research ship (a survey vessel or deep-sea mothership: see Research).
func is_research() -> bool:
	return model().has("research")


func is_service() -> bool:
	return _kind() != KIND_CARGO


## What kind of ship its model is (KIND_*), looked up once: the model never
## changes, and these are asked for every ship many times a step.
func _kind() -> int:
	if _kind_cache < 0:
		var data := model()
		if data.get("recovery", false):
			_kind_cache = KIND_RECOVERY
		elif not str(data.get("icebreaker", "")).is_empty():
			_kind_cache = KIND_ICEBREAKER
		elif data.get("tug", false):
			_kind_cache = KIND_TUG
		elif data.has("fishing"):
			_kind_cache = KIND_FISHING
		else:
			_kind_cache = KIND_CARGO
	return _kind_cache

## Tug only: how far along a lane from its port it fetches lost ships.
func reach_nm() -> float:
	return float(model().get("reach_nm", 0))


## Whether a full tank at full maintenance gets this ship from one port to
## another (with the departure margin to spare), and the port there is big
## enough for it.
func can_reach(from: String, to: String) -> bool:
	if not fits_lane(from, to) or not fits_port(to):
		return false
	var seconds := leg_seconds(from, to, 0.0, GameData.distance_nm(from, to), 1.0) + GameState.DEPARTURE_MARGIN_S
	return fuel_per_s() * seconds <= fuel_tank()


## False if the lane needs the St. Lawrence Seaway (a Great Lakes port) and the
## model is too big for it.
func fits_lane(from: String, to: String) -> bool:
	return bool(model().get("seaway", false)) or not GameData.needs_seaway(from, to)


## False if the port is too small for the model (ship_models.json min_port;
## see PortSizes). Recovery boats dock anywhere.
func fits_port(port_id: String) -> bool:
	return GameState.port_sizes.fits(model(), port_id)


## Recovery boat only: whether it can carry this ship (models listed in
## "carries", or any model if none are listed).
func can_carry(other: Ship) -> bool:
	var carries: Array = model().get("carries", [])
	return is_recovery() and (carries.is_empty() or carries.has(other.model_id))


## What the ship sells for: half what was paid for it, scaled by maintenance.
func sell_price() -> int:
	return floori(float(purchase_price) * SELL_FRACTION * clampf(maintenance, 0.0, 1.0))


## Docked and not busy recovering (or being recovered).
func can_sell() -> bool:
	return is_docked() and not is_on_job() and not is_lost()


func profit() -> float:
	return ledger.income - ledger.cargo - ledger.fuel - ledger.repair - ledger.tolls - ledger.port_fees - ledger.wages \
		+ float(ledger.get("research_pay", 0.0)) - float(ledger.get("research_gear", 0.0))  # (A research ship's contracts and gear: see Research.)


## Top speed, with its company's research perks.
func top_speed() -> float:
	if _stats_dirty:
		_refresh_stats()
	return _top_speed


## Current speed: top speed scaled by maintenance.
func speed() -> float:
	return top_speed() * clampf(maintenance, 0.0, 1.0)


func capacity() -> int:
	return int(model().get("capacity", 0))


## Longest single leg this ship can sail at full maintenance, in nautical miles.
func range_nm() -> float:
	return float(model().get("range_nm", 0))


func fuel_tank() -> float:
	return float(model().get("fuel_tank", 0))


## Fuel burned per second at sea.
func fuel_per_s() -> float:
	if _stats_dirty:
		_refresh_stats()
	return _fuel_per_s


## Maintenance lost per second of running at sea.
func wear_per_s() -> float:
	if _stats_dirty:
		_refresh_stats()
	return _wear_per_s


## Top speed, fuel burn and wear depend on the model, its company's research
## perks and the birds following it, which change rarely, so they're worked out
## once and kept until invalidate_stats().
func _refresh_stats() -> void:
	var data := model()
	var who := GameState.owner_of(self)  # (Its company's research perks too: see Research.perk().)
	_top_speed = float(data.get("speed_nm_per_s", 0)) * Research.perk(who, "speed")
	_fuel_per_s = float(data.get("fuel_per_s", 0)) * (1.0 - bird_fuel_saving) * Research.perk(who, "fuel") * Traits.factor(who, "fuel", false)  # (The CEO's traits too: see Traits.)
	_wear_per_s = float(data.get("wear_pct_per_min", 0)) / 100.0 / 60.0 * Research.perk(who, "wear") * Traits.factor(who, "wear", false)
	_stats_dirty = false


func invalidate_stats() -> void:
	_stats_dirty = true
	_leg_from = "?"  # The harbor speed zones follow the top speed.


## Chance of a random breakdown in one roll (see game_config breakdowns): higher
## the more worn the ship is, times the model's sturdiness (breakdown_factor)
## and the ship's age at sea.
func breakdown_chance() -> float:
	var settings: Dictionary = GameData.config.get("breakdowns", {})
	var worn := 1.0 - clampf(maintenance, 0.0, 1.0)
	var chance := lerpf(float(settings.get("chance_at_full", 0.0005)), float(settings.get("chance_at_empty", 0.005)), worn)
	var age := minf(1.0 + float(settings.get("age_per_hour_at_sea", 0.1)) * sea_time / 3600.0,
		float(settings.get("max_age_factor", 2.0)))
	return chance * float(model().get("breakdown_factor", 1.0)) * age * Research.perk(GameState.owner_of(self), "breakdowns") * Traits.factor(GameState.owner_of(self), "breakdowns", false)


## Cost of restoring 100% maintenance (from 0%).
func full_repair_cost() -> float:
	return float(model().get("repair_cost_per_pct", 0)) * 100.0


## How long a port stop takes, shorter at a hub with the port stops upgrade.
func dock_seconds() -> float:
	return float(model().get("dock_s", 0)) * _hub_stop_factor()


## How long the repair phase takes, and then the refuel phase, while docked.
func refill_phase_seconds() -> float:
	return float(model().get("refill_phase_s", 5)) * _hub_stop_factor()


## In a Divine Actions game, the port's blessings and
## curses (its birds, a plague of gulls, the lamps by night, the first snow).
func _hub_stop_factor() -> float:
	return GameState.divine.stop_factor(self) if is_docked() else 1.0


## A leg within the ship's range that it fits (the Seaway) and can sail on one
## tank (slow canal stretches and rough seas can make a leg in range too long).
func can_sail(from: String, to: String) -> bool:
	return from != to and GameData.distance_nm(from, to) <= range_nm() and can_reach(from, to)


## Seconds to sail a distance starting at a given maintenance, slowing as the
## ship wears. INF if it would wear down to a stop first.
func sailing_seconds(distance: float, start_maintenance: float) -> float:
	var v := top_speed()
	var w := wear_per_s()
	var m := start_maintenance
	if distance <= 0.0:
		return 0.0
	if v <= 0.0 or m <= 0.0:
		return INF
	if w <= 0.0:
		return distance / (v * m)
	var discriminant := m * m - 2.0 * w * distance / v
	if discriminant < 0.0:
		return INF
	return (m - sqrt(discriminant)) / w


## Seconds sailing a lane from one mile to another, starting at a given
## maintenance: sailing_seconds() over each of its zones (GameData.lane_zones():
## slower in convoy canals, faster wear in rough seas) in turn, carrying the
## wear over. Time held in locks, lines and anchorages doesn't count (engines off).
func leg_seconds(from: String, to: String, start_mile: float, end_mile: float, start_maintenance: float) -> float:
	# A whole leg from full maintenance (asked for again and again: can_reach(),
	# fuel_needed() in port, the AI rivals' loops) is kept, for any ship as fast
	# and wearing as fast: that's all it depends on (its zones' harbor speed too).
	var whole := start_mile == 0.0 and start_maintenance == 1.0
	var key: Array
	if whole:
		if _stats_dirty:
			_refresh_stats()
		key = [from, to, end_mile, _top_speed, _wear_per_s, GameData.month, GameData.way_now(from, to)]
		if _whole_legs.has(key):
			return _whole_legs[key]
	var seconds := _leg_seconds(from, to, start_mile, end_mile, start_maintenance)
	if whole:
		_whole_legs[key] = seconds
	return seconds


func _leg_seconds(from: String, to: String, start_mile: float, end_mile: float, start_maintenance: float) -> float:
	var seconds := 0.0
	var m := start_maintenance
	var mile := start_mile
	var zones := _current_zones()
	if from != from_port or to != to_port:
		zones = leg_zones(from, to)
	if GameData.native_lanes:
		return ClassDB.class_call_static(&"LaneMath", &"leg_seconds", zones, start_mile, end_mile, start_maintenance, top_speed(), wear_per_s())  # (The same, natively.)
	for zone: Array in zones:
		if mile >= end_mile - 0.0001:
			break
		if zone[0] <= mile:
			continue
		var piece := minf(float(zone[0]), end_mile) - mile
		var t := _seconds_at(piece, m, top_speed() * float(zone[1]), wear_per_s() * float(zone[2]))
		if t == INF:
			return INF
		seconds += t
		m -= wear_per_s() * float(zone[2]) * t
		mile += piece
	return seconds


## sailing_seconds() at a given top speed and wear rate.
static func _seconds_at(distance: float, m: float, v: float, w: float) -> float:
	if distance <= 0.0:
		return 0.0
	if v <= 0.0 or m <= 0.0:
		return INF
	if w <= 0.0:
		return distance / (v * m)
	var discriminant := m * m - 2.0 * w * distance / v
	if discriminant < 0.0:
		return INF
	return (m - sqrt(discriminant)) / w


## Fuel needed to sail between two ports, leaving at the current maintenance.
func fuel_needed(from: String, to: String) -> float:
	return fuel_per_s() * leg_seconds(from, to, 0.0, GameData.distance_nm(from, to), maintenance)


## The port a new route starts from: where it's docked, or where it's heading.
func reference_port() -> String:
	return docked_at if is_docked() else to_port


func is_docked() -> bool:
	return not docked_at.is_empty()


## An ambient-traffic ship of another firm (see ghost).
func is_ghost() -> bool:
	return ghost


## Unloading and loading after arriving at a port.
func is_docking() -> bool:
	return is_docked() and dock_time >= 0.0


func has_route() -> bool:
	return not route.is_empty()


## In port only to refuel on its way somewhere beyond one tank (see hop_to).
func is_refuel_stop() -> bool:
	return is_docked() and not hop_to.is_empty() and docked_at != hop_to


## On rig runs between a field and a port (Energy).
func is_rig_runner() -> bool:
	return not rig_field.is_empty()


## Green on the status dot: has a route and isn't paused.
func is_running() -> bool:
	return has_route() and not paused


## Running, but stuck in port (e.g. not enough fuel).
func is_held() -> bool:
	return not hold_reason.is_empty()


## Stranded at sea, waiting for (or being carried by) a Mammoth.
func is_lost() -> bool:
	return not lost_reason.is_empty()


## A Mammoth out on a job.
func is_on_job() -> bool:
	return job_phase != JOB_NONE


## Riding on a recovery boat (from when it's floated aboard until it's handed
## over at port).
func is_carried() -> bool:
	return rescuer != null and rescuer.is_carrying()


## Being pushed or dragged into port by tugs (rescuer is the lead tug).
func is_towed() -> bool:
	return rescuer != null and rescuer.is_tug() and rescuer.job_phase == JOB_TOW


## Tug on a job: done turning round, and waiting for the other tug (or about to tow).
func tug_ready() -> bool:
	return is_tug() and job_phase == JOB_ALIGN and align_time >= ALIGN_SECONDS


## Recovery boat only: has the lost ship aboard or alongside (from when it's floated onto
## the deck until it's handed over at port).
func is_carrying() -> bool:
	if is_tug():
		return false
	if job_phase == JOB_TOW:
		return true
	if job_phase == JOB_UNLOAD:
		return true  # Floated off its stern, it stays with it till handed over.
	return job_phase == JOB_ALIGN and align_time >= ALIGN_SECONDS + LOAD_SECONDS * 2.0 / 3.0


## Recovery boat only: seconds into taking a ship aboard (after lining up) or
## floating it off at port, or -1 when doing neither. Like a real
## semi-submersible heavy-lift ship, it ballasts down (its deck sinks under
## the water), the ship floats over the deck, and it deballasts and rises; a
## third of LOAD_SECONDS each.
func load_time() -> float:
	if is_tug():
		return -1.0
	if job_phase == JOB_UNLOAD:
		return align_time
	if job_phase == JOB_ALIGN and align_time >= ALIGN_SECONDS and align_time <= ALIGN_SECONDS + LOAD_SECONDS:
		return align_time - ALIGN_SECONDS
	return -1.0


## Recovery boat only: how far its deck is under water (0 up, 1 fully down).
func submerged() -> float:
	var t := load_time()
	if t < 0.0:
		return 0.0
	var third := LOAD_SECONDS / 3.0
	if t < third:
		return t / third
	if t < third * 2.0:
		return 1.0
	return clampf(1.0 - (t - third * 2.0) / third, 0.0, 1.0)


## Recovery boat only: how far the ship has floated onto its deck (or, at
## port, off it), 0 to 1, in the middle third of loading; -1 when it isn't
## loading or unloading.
func float_progress() -> float:
	var t := load_time()
	if t < 0.0:
		return -1.0
	var third := LOAD_SECONDS / 3.0
	return clampf((t - third) / third, 0.0, 1.0)


## Recovery boat only: turns round with the ship aboard, when the port it's
## carrying it to is back the way the boat came (its carry segment starts at
## the end of the lane the boat was sailing towards).
func tow_turns_around() -> bool:
	return rescuing != null and not is_tug() and not job_segments.is_empty() and str(job_segments[0][0]) == to_port


## Recovery boat only: true if the ship it's carrying faces the other way from
## it (the boat met it head on, so it floated aboard stern first).
func carry_flipped() -> bool:
	return rescuing != null and carry_reversed


## Recovery boat only: total seconds spent pulling up ahead, taking the ship
## aboard and (if needed) spinning round.
func align_seconds() -> float:
	return ALIGN_SECONDS + LOAD_SECONDS + (SPIN_SECONDS if tow_turns_around() else 0.0)


## What the player needs to do for this ship to run at its best, or "".
func attention_reason() -> String:
	if is_lost() and rescuer == null:
		return "lost at sea"
	if is_held():
		return "held in port"
	if canal_state == CANAL_TOLL:
		return "waiting for toll money"
	if not is_service() and is_docked() and not has_route():
		return "no expedition" if is_research() else "no route"
	if is_docked() and paused:
		return "paused"
	return ""


## Green on the status dot.
func is_active() -> bool:
	if is_fishing():  # Out on a trip, or in port with nothing keeping it there.
		return not is_docked() or (fish_wait.is_empty() and not paused) if not is_lost() else false
	if is_icebreaker():
		return not ice_phase.is_empty() or not is_docked()
	if is_recovery() or is_tug():
		return is_on_job() or not is_docked()
	return is_running() and not is_held() and not is_lost()


func fuel_level() -> float:
	var tank := fuel_tank()
	return clampf(fuel / tank, 0.0, 1.0) if tank > 0.0 else 0.0


## What the cargo aboard sells for against plain stock at its full value: its
## breed's value, times its freshness by now (what it was when loaded, a
## farm store's dry crops a little under 1; fresh cargo less its daily loss
## for the days aboard; never under a tenth).
func cargo_value_factor(play_time: float, days_per_second: float) -> float:
	var factor := Farms.breed_value(cargo_breed)
	var loss := Farms.loses_a_day(cargo_id)
	var days := maxf(play_time - cargo_since, 0.0) * days_per_second if loss > 0.0 else 0.0
	return factor * maxf(cargo_fresh - loss * (1.0 - float(model().get("keeps_fresh", 0.0))) * days, 0.1)


## How full the hold is (0..1): the cargo aboard, emptying over the first half
## of a stop as it's unloaded and filling over the second half with what it loaded.
func cargo_level() -> float:
	if is_fishing():
		return clampf(catch / capacity(), 0.0, 1.0) if capacity() > 0 else 0.0
	var full := clampf(float(cargo_qty) * GameData.hold_of(cargo_id) / capacity(), 0.0, 1.0) if capacity() > 0 else 0.0
	if not is_docking() or dock_seconds() <= 0.0:
		return full
	return full * clampf(absf(1.0 - 2.0 * dock_time / dock_seconds()), 0.0, 1.0)


func leg_length() -> float:
	_update_leg()
	return _leg_length


## True if the current leg goes through a canal.
func leg_has_canal() -> bool:
	_update_leg()
	return _leg_has_canal


func _current_zones() -> Array:
	_update_leg()
	return _leg_zones


## The zone at a mile of the current leg: [where it ends, speed factor, wear
## factor] (see GameData.zone_factors()). Read, not changed: it's the leg's own
## (no new array every step at sea).
func zone_at(mile: float) -> Array:
	_update_leg()
	for zone: Array in _leg_zones:
		if mile < zone[0]:
			return zone
	return OPEN_SEA_ZONE


## The current leg's length and zones, looked up once per leg rather than on
## every call (the lookups build text keys, which adds up at sea every step).
func _update_leg() -> void:
	if from_port == _leg_from and to_port == _leg_to:
		return
	_leg_from = from_port
	_leg_to = to_port
	var key := "%s>%s" % [from_port, to_port]
	if key != leg_key:  # A new leg: this month's way (see leg_key).
		leg_key = key
		leg_current = GameData.way_now(from_port, to_port) >= 0 and not is_on_job()  # (A job's segments are miles along the lane itself.)
		leg_month = GameData.month
	var way := GameData.variant_of(from_port, to_port) if leg_current else -1
	_leg_length = GameData.distance_nm(from_port, to_port, way)
	_leg_zones = _with_harbor_speed(GameData.lane_zones(from_port, to_port, way, leg_month), _leg_length)
	_leg_has_canal = not GameData.canal_crossings(from_port, to_port).is_empty()
	_leg_lane = GameData.lane(from_port, to_port, way)
	_here_cache = []


## The lane it sails its leg along (the way it chose as it set off: see leg_key).
func leg_lane() -> GameData.SeaLane:
	_update_leg()
	return _leg_lane


## The current lane's sample() where the ship is ([position, heading]), or []
## if it isn't on a lane; taken again only once it has moved.
func lane_sample() -> Array:
	_update_leg()
	if _leg_lane == null:
		return []
	if _here_cache.is_empty() or traveled_nm != _here_mile:
		_here_mile = traveled_nm
		_here_cache = _leg_lane.sample(traveled_nm)
	return _here_cache


## The heading of its lane where it is (zero off a lane).
func lane_heading() -> Vector2:
	var here := lane_sample()
	return here[1] if not here.is_empty() else Vector2.ZERO


## A leg's zones for this ship ([[end mile, speed factor, wear factor], ...]):
## the lane's (GameData.lane_zones()) with its harbor speed laid over each end.
func leg_zones(from: String, to: String) -> Array:
	# (Kept for the last leg asked about, at this top speed: a ship waiting in
	# port asks about its next leg every step.)
	var speed := top_speed()
	if from != _zones_from or to != _zones_to or speed != _zones_speed or GameData.month != _zones_month:
		_zones_from = from
		_zones_to = to
		_zones_speed = speed
		_zones_month = GameData.month
		_zones_asked = _with_harbor_speed(GameData.lane_zones(from, to), GameData.distance_nm(from, to))
	return _zones_asked


## A lane's zones with the ship's harbor speed (game_config harbor_speed) laid
## over each end: leaving port it builds up from start x its speed to full
## speed with steady acceleration over about `seconds`, and it slows the same
## way coming in, in `steps` pieces of speed each (at the speed halfway through
## the piece), multiplied into whatever the lane's own zone there is.
func _with_harbor_speed(zones: Array, length: float) -> Array:
	var settings: Dictionary = GameData.config.get("harbor_speed", {})
	if GameData.native_lanes:
		return ClassDB.class_call_static(&"LaneMath", &"with_harbor_speed", zones, length, top_speed(), settings)  # (The same, natively.)
	var start := float(settings.get("start", 1.0))
	var steps := int(settings.get("steps", 0))
	# Distance covered speeding up from start x top speed at a steady rate.
	var ramp := minf(top_speed() * float(settings.get("seconds", 0.0)) * (1.0 + start) / 2.0, length / 2.0)
	if zones.is_empty() or steps <= 0 or start >= 1.0 or ramp <= 0.0:
		return zones
	var breaks := PackedFloat64Array()
	for zone: Array in zones:
		breaks.append(zone[0])
	for k in range(1, steps + 1):
		breaks.append(ramp * k / steps)
		breaks.append(length - ramp * k / steps)
	breaks.sort()
	var out := []
	var previous := 0.0
	for mile in breaks:
		if mile <= previous + 0.0001:
			continue
		var middle := (previous + mile) / 2.0
		var lane_zone: Array = zones[-1]
		for zone: Array in zones:
			if middle < zone[0]:
				lane_zone = zone
				break
		var from_port_end := minf(middle, length - middle)
		var harbor := sqrt(start * start + (1.0 - start * start) * from_port_end / ramp) if from_port_end < ramp else 1.0
		out.append([mile, float(lane_zone[1]) * harbor, lane_zone[2]])
		previous = mile
	return out


func leg_progress() -> float:
	var length := leg_length()
	return clampf(traveled_nm / length, 0.0, 1.0) if length > 0.0 else 1.0


## Position in projected map coordinates.
func world_position() -> Vector2:
	if is_carried() or is_towed():
		return rescuer.world_position()
	if is_docked():
		return GameData.port_position(docked_at)
	var here := lane_sample()
	return here[0] if not here.is_empty() else GameData.port_position(from_port)


## Direction of travel in projected map coordinates (zero when docked).
func heading() -> Vector2:
	if is_carried():
		return -rescuer.heading() if rescuer.carry_flipped() else rescuer.heading()
	if is_towed():
		return rescuer.heading()
	if is_docked():
		return Vector2.ZERO
	if job_phase == JOB_ALIGN and is_tug():
		# Sailed out from its port: turns round to take the ship back there.
		var arrive := lane_heading().angle()
		return Vector2.from_angle(arrive + PI * clampf(align_time / ALIGN_SECONDS, 0.0, 1.0))
	if job_phase == JOB_ALIGN:
		return _align_heading()
	return lane_heading()


## Keeps the heading it arrived on (it pulls ahead past the ship and backs
## under it), then, if the port it's carrying the ship to is back the way it
## came, spins round on the spot.
func _align_heading() -> Vector2:
	var arrive := lane_heading().angle()
	var t := (align_time - ALIGN_SECONDS - LOAD_SECONDS) / SPIN_SECONDS if tow_turns_around() else 0.0
	return Vector2.from_angle(arrive + PI * smoothstep(0.0, 1.0, t))


## Index of the route stop to sail to next from the port the ship is docked at.
func next_route_index() -> int:
	# At a refuel stop on the way to its next stop: still bound for it.
	if not hop_to.is_empty() and docked_at != hop_to and route_index >= 0 and route_index < route.size() and route[route_index] == hop_to:
		return route_index
	if route_index >= 0 and route_index < route.size() and route[route_index] == docked_at:
		return (route_index + 1) % route.size()
	var here := route.find(docked_at)
	if here >= 0:
		return (here + 1) % route.size()
	return 0  # Not on the route yet: head to its first stop.


func status_text() -> String:
	var canal := canal_status_text()
	if is_cruise() and not is_lost() and not cruise.is_empty():  # (Booking, in a refit, or on a voyage: Cruises.)
		var voyage: Dictionary = cruise.get("voyage", {})
		var line := str(cruise.get("status", ""))
		if not voyage.is_empty() and str(cruise.get("state", "")) == "sailing":
			line = "On a %d-night cruise with %d guests (%d%% full), %d of %d ports of call so far" % [int(voyage.nights), int(voyage.total), roundi(float(voyage.fill) * 100.0), (voyage.stops as Array).size(), maxi(route.size() - 1, 0)]
		if not line.is_empty():
			return line if canal.is_empty() else "%s — %s" % [line, canal]
	if is_icebreaker():
		var duty := _icebreaker_status_text()
		return duty if canal.is_empty() else "%s — %s" % [duty, canal]
	if is_recovery():
		var job := _recovery_status_text()
		return job if canal.is_empty() else "%s — %s" % [job, canal]
	if is_tug() and job_phase == JOB_REPAIR:
		var job := _repair_status_text()
		return job if canal.is_empty() else "%s — %s" % [job, canal]
	if is_tug():
		var job := _tug_status_text()
		return job if canal.is_empty() else "%s — %s" % [job, canal]
	if is_fishing() and not is_lost():
		var trip := _fishing_status_text()
		if not trip.is_empty():
			return trip if canal.is_empty() else "%s — %s" % [trip, canal]
	if job_phase == JOB_RIG and not is_lost():
		var run := _rig_status_text()
		return run if canal.is_empty() else "%s — %s" % [run, canal]
	if is_lost():
		if rescuer == null:
			if auto_recover:
				return "Lost at sea (%s), waiting for a free recovery boat or tug" % lost_reason
			return "Lost at sea (%s)" % lost_reason
		if is_carried():
			return "Being carried to %s by %s" % [GameData.port_name(rescuer.tow_port), rescuer.name]
		if is_towed():
			return "Being towed to %s by %s" % [GameData.port_name(rescuer.tow_port), rescuer.tug_crew_text()]
		return "Lost at sea (%s), %s on the way" % [lost_reason, rescuer.tug_crew_text() if rescuer.is_tug() else rescuer.name]
	if is_docked():
		var port := GameData.port_name(docked_at)
		match berth_phase:
			BERTH_WAIT:
				var place := GameState.docks.queue_position(self)
				return "Waiting at anchor for a berth at %s%s" % [port, " (%s in line)" % Fmt.ordinal(place) if place > 0 else ""]
			BERTH_IN:
				return "Coming alongside at %s" % port
			BERTH_OUT:
				return "Pulling out of %s%s" % [port, " for %s" % GameData.port_name(depart_to) if not depart_to.is_empty() else " to anchor"]
		if is_refuel_stop():
			var onward := "Refuelling at %s on the way to %s" % [port, GameData.port_name(hop_to)]
			if not is_docking() and is_held():
				onward += " — %s" % hold_reason
			return onward
		if is_docking():
			return ("Unloading at %s" if dock_time < dock_seconds() / 2.0 else "Loading at %s") % port
		var text := "Docked at %s" % port
		if not has_route():
			text += " (no route)"
		elif paused:
			text += " (paused)"
		elif is_held():
			text += " — %s" % hold_reason
		elif not weather_wait.is_empty():
			text += " — %s" % weather_wait
		elif not load_wait.is_empty():
			text += " — %s" % load_wait
		return text
	var destination := GameData.port_name(to_port)
	if not weather_wait.is_empty():
		return weather_wait[0].to_upper() + weather_wait.substr(1)
	if not canal.is_empty():
		return "%s — to %s" % [canal, destination]
	if paused:
		return "Stopping at %s" % destination
	var text := "En route to %s — %d%% · arrives %s" % [destination, int(leg_progress() * 100.0), Fmt.calendar_short(arrival_time())]
	if not hop_to.is_empty() and hop_to != to_port:
		text = "En route to %s to refuel, then on to %s — %d%% · arrives %s" % [destination, GameData.port_name(hop_to), int(leg_progress() * 100.0), Fmt.calendar_short(arrival_time())]
	return text + " — won't make it!" if at_risk else text


## The lock chamber the ship is sitting in ({index, lock, mile, canal, forward}
## from GameData.lane_chambers()), or {} if it isn't in one.
func lock_chamber() -> Dictionary:
	if lock_time < 0.0 or canal_step <= 0 or from_port.is_empty():
		return {}
	var chambers := GameData.lane_chambers(from_port, to_port)
	return chambers[canal_step - 1] if canal_step <= chambers.size() else {}


## Where the ship is in a canal, e.g. "In Gatún Locks (chamber 2 of 3),
## rising", "Waiting for Pedro Miguel Locks (2nd in line)", "At anchor off Port
## Said, next southbound convoy in 45 s" or "Waiting for toll money at the
## Panama Canal"; "" when it isn't in or held up at one.
func canal_status_text() -> String:
	if is_docked() or is_lost() or from_port.is_empty():
		return ""
	var crossing := GameData.crossing_ahead(from_port, to_port, traveled_nm)
	if crossing.is_empty():
		return ""
	var canal: Dictionary = crossing.canal
	if canal.get("type", "") == "convoy":
		return _convoy_status_text(crossing)
	if canal_state == CANAL_TOLL:
		return "Waiting for toll money at the %s" % canal.name
	var chambers := GameData.lane_chambers(from_port, to_port)
	if lock_time >= 0.0 and canal_step > 0:
		var chamber: Dictionary = chambers[canal_step - 1]
		var lock: Dictionary = chamber.canal.locks[chamber.lock]
		var in_lock := chambers.filter(func(c: Dictionary) -> bool: return c.canal == chamber.canal and c.lock == chamber.lock)
		if lock_time >= float(chamber.canal.get("step_seconds", 3)) and canal_step < chambers.size():
			var next: Dictionary = chambers[canal_step]
			if next.canal == chamber.canal and next.lock == chamber.lock:
				return "In %s, waiting for the next chamber" % lock.name
			return "In %s, waiting for %s" % [lock.name, next.canal.locks[next.lock].name]
		var rising: bool = lock.rises_forward == chamber.forward
		var of := " (chamber %d of %d)" % [in_lock.find(chamber) + 1, in_lock.size()] if in_lock.size() > 1 else ""
		return "In %s%s, %s" % [lock.name, of, "rising" if rising else "lowering"]
	if canal_step < chambers.size():
		var next: Dictionary = chambers[canal_step]
		var lock_name: String = next.canal.locks[next.lock].name
		if canal_state == CANAL_QUEUED:
			return "Waiting for %s (%s in line)" % [lock_name, Fmt.ordinal(GameState.canal_traffic.line_position(self))]
		if canal_state == CANAL_RESERVED and GameState.canal_traffic.slot_turn(next.canal.id, next.index, lock_slot) > 0.0:
			return "Waiting for %s to be made ready" % lock_name
	return ""


func _convoy_status_text(crossing: Dictionary) -> String:
	var canal: Dictionary = crossing.canal
	var traffic: CanalTraffic = GameState.canal_traffic
	var way: String = ("southbound" if crossing.forward else "northbound") if canal.id == "suez" else ("forward" if crossing.forward else "return")
	var anchorage: String = canal.get("anchorage_names", ["the anchorage", "the anchorage"])[0 if crossing.forward else 1]
	match canal_state:
		CANAL_ANCHORED:
			return "At %s, next %s convoy in %s" % [anchorage, way, Fmt.duration(ceilf(traffic.next_convoy_in(canal)))]
		CANAL_TOLL:
			return "At %s, waiting for toll money for the next %s convoy" % [anchorage, way]
		CANAL_CONVOY:
			var place := traffic.released_ships(canal, crossing.forward).find(self) + 1
			return "Joining the %s %s convoy (%s in line to enter)" % [way, canal.name, Fmt.ordinal(place)]
	if not canals_entered.has(canal.id):
		return ""
	if not traffic.blocked_stretch(self).is_empty():
		return "Waiting in a passing stretch for the %s convoy to clear" % ("northbound" if crossing.forward else "southbound")
	var leader := traffic.convoy_leader(self)
	var ships := traffic.convoy_ships(canal, crossing.forward)
	var text := "In the %s %s convoy (%s of %d)" % [way, canal.name, Fmt.ordinal(ships.find(self) + 1), ships.size()]
	if leader != null and speed() * float(canal.get("speed_factor", 1.0)) > leader.speed() * float(canal.get("speed_factor", 1.0)):
		text += ", held behind %s" % leader.name
	return text


## When the ship should reach the end of its leg, as a calendar Unix time: the
## rest of the leg at its current wear, plus its remaining lock steps (not
## counting waits in line or for a convoy).
func arrival_time() -> int:
	var seconds := leg_seconds(from_port, to_port, traveled_nm, leg_length(), maintenance)
	var chambers := GameData.lane_chambers(from_port, to_port)
	for i in range(maxi(canal_step, 0), chambers.size()):
		seconds += float(chambers[i].canal.get("step_seconds", 3))
	return GameState.calendar_time_at(GameState.play_time + (seconds if seconds < INF else 0.0))


func _recovery_status_text() -> String:
	match job_phase:
		JOB_APPROACH:
			return "Heading to recover %s" % rescuing.name
		JOB_ALIGN:
			var third := LOAD_SECONDS / 3.0
			var t := load_time()
			if align_time < ALIGN_SECONDS:
				return "Pulling up ahead of %s" % rescuing.name
			if t >= 0.0 and t < third:
				return "Ballasting down to take %s aboard" % rescuing.name
			if t >= 0.0 and t < third * 2.0:
				return "Floating %s onto its deck" % rescuing.name
			if t >= 0.0:
				return "Rising with %s aboard" % rescuing.name
			return "Spinning round with %s aboard" % rescuing.name
		JOB_TOW:
			return "Carrying %s to %s" % [rescuing.name, GameData.port_name(tow_port)]
		JOB_UNLOAD:
			return "Floating %s off at %s" % [rescuing.name, GameData.port_name(tow_port)]
	if is_docked():
		var port := GameData.port_name(docked_at)
		if is_docking():
			return "Refueling at %s" % port
		if is_held():
			return "Docked at %s — %s" % [port, hold_reason]
		return "Standing by at %s" % port
	return "Heading to base at %s — %d%%" % [GameData.port_name(to_port), int(leg_progress() * 100.0)]


## A tug's job: "Heading out to tow Hauler", "Turning round to take Hauler in
## tow", "Waiting for Nudge to take Hauler in tow", "Towing Hauler to Vanino
## with Nudge", "Pushing Hauler to Vanino with Tugger".
func _tug_status_text() -> String:
	var partners := tug_team().filter(func(tug: Ship) -> bool: return tug != self)
	var with := " with %s" % partners[0].name if not partners.is_empty() else ""
	match job_phase:
		JOB_APPROACH:
			if is_docked():
				return "Following %s out to tow %s" % [partners[0].name if not partners.is_empty() else "the other tug", rescuing.name]
			return "Heading out to tow %s" % rescuing.name
		JOB_ALIGN:
			if align_time < ALIGN_SECONDS:
				return "Turning round to take %s in tow" % rescuing.name
			return "Waiting for %s to take %s in tow" % [partners[0].name if not partners.is_empty() else "the other tug", rescuing.name]
		JOB_TOW:
			return "Towing %s to %s%s" % [rescuing.name, GameData.port_name(tow_port), with]
		JOB_BERTH:
			if assist_s < 0.0:
				return "Bringing %s alongside at %s%s" % [rescuing.name, GameData.port_name(tow_port), with]
			return "Taking %s to the anchorage at %s%s" % [rescuing.name, GameData.port_name(tow_port), with]
	if is_docked():
		var port := GameData.port_name(docked_at)
		if is_docking():
			return "Refueling at %s" % port
		if is_held():
			return "Docked at %s — %s" % [port, hold_reason]
		if docked_at != base_port and not base_port.is_empty():
			return "At %s, heading to its base at %s" % [port, GameData.port_name(base_port)]
		return "Standing by at %s" % port
	return "Sailing to its base at %s — %d%%" % [GameData.port_name(to_port), int(leg_progress() * 100.0)]


## On a rig run: "Heading out to Brent", "Loading at Brent — 3,200 / 5,000
## tons of crude oil", "Bringing 5,000 tons of crude oil from Brent to Rotterdam".
func _rig_status_text() -> String:
	var where := Energy.field_name(rig_field)
	match rig_phase:
		"out":
			return "Heading out to the rigs at %s" % where
		"load":
			if cargo_qty <= 0:
				return "Alongside the rigs at %s, waiting for them to fill its hold" % where
			return "Loading at the rigs at %s — %s / %s tons of %s" % [where, Fmt.thousands(cargo_qty), Fmt.thousands(capacity()), Energy.good_word(cargo_id)]
		"home":
			if cargo_qty <= 0:
				return "Heading back to %s from %s" % [GameData.port_name(rig_port), where]
			return "Bringing %s tons of %s from %s to %s" % [Fmt.thousands(cargo_qty), Energy.good_word(cargo_id), where, GameData.port_name(rig_port)]
	return ""


## A tug sent to repair a rig: "Heading out to repair the oil rig at Brent", "Repairing...", "Heading home...".
func _repair_status_text() -> String:
	var where := Energy.field_name(Energy.field_of(rig_slot))
	match rig_phase:
		"out":
			return "Heading out to repair a rig at %s" % where
		"load":
			return "Repairing a rig at %s" % where
	return "Heading back to %s from the rigs at %s" % [GameData.port_name(base_port), where]


## Tug only: the tugs on its job (itself included, the lead first), or [].
func tug_team() -> Array[Ship]:
	var team: Array[Ship] = []
	if rescuing == null:
		return team
	for tug in GameState.ships:
		if tug.is_tug() and tug.rescuing == rescuing:
			if tug.tug_lead:
				team.push_front(tug)
			else:
				team.append(tug)
	return team


## Tug only: "Nudge" or "Nudge and Tugger".
func tug_crew_text() -> String:
	var names := tug_team().map(func(tug: Ship) -> String: return tug.name)
	return " and ".join(names) if not names.is_empty() else name


## "Heading out to Bristol Bay for red king crab", "Crabbing for red king
## crab in Bristol Bay — 3,200 / 6,000 crates", "Heading home to Dutch
## Harbor with 6,000 crates of red king crab", "At Dutch Harbor: no red king
## crab in season till October"; "" when it's just in port.
func _fishing_status_text() -> String:
	var what := Fisheries.shared().species_word(fish_species)
	var where := GameData.port_name(Fisheries.end_of(fish_ground))
	match fish_phase:
		"out":
			return "Heading out to %s for %s" % [where, what]
		"work":
			var doing := "Crabbing" if fishing_line() == "crabbing" else ("Trolling" if (model().get("fishing", {}).get("gear", []) as Array) == ["troll"] else "Fishing")
			return "%s for %s at %s — %s / %s crates" % [doing, what, where, Fmt.thousands(floori(catch)), Fmt.thousands(capacity())]
		"home":
			if catch <= 0.0:
				return "Heading back to %s" % GameData.port_name(fish_home if not fish_home.is_empty() else base_port)
			return "Heading back to %s with %s crates of %s" % [GameData.port_name(fish_home if not fish_home.is_empty() else base_port), Fmt.thousands(floori(catch)), what]
	if is_refuel_stop():
		return "Refuelling at %s on the way to %s%s" % [GameData.port_name(docked_at), GameData.port_name(hop_to), " with %s crates" % Fmt.thousands(floori(catch)) if catch >= 1.0 else ""]
	if is_docked() and not fish_wait.is_empty() and not is_docking():
		return "At %s: %s" % [GameData.port_name(docked_at), fish_wait]
	return ""


## "Leading 3 ships to Vanino", "Standing by at Helsinki for the Gulf of
## Finland", "Not stationed (only needed in seasonal ice)".
func _icebreaker_status_text() -> String:
	var area_name: String = GameState.icebreaking.area(station).get("name", "")
	match ice_phase:
		"approach":
			return "Heading out to lead %s" % _convoy_text()
		"turn_in":
			return "Turning to lead %s" % _convoy_text()
		"turn_back":
			return "Turning back"
		"escort":
			return "Leading %s through the %s ice" % [_convoy_text(), area_name]
		"return":
			return "Heading back to %s" % GameData.port_name(to_port)
	if is_docked():
		var port := GameData.port_name(docked_at)
		if is_docking():
			return "Refueling at %s" % port
		if station.is_empty():
			return "Not stationed at %s (only needed in seasonal ice)" % port
		if docked_at != base_port:
			return "At %s, heading to its station at %s" % [port, GameData.port_name(base_port)]
		if GameState.icebreaking.in_season(GameState.icebreaking.area(station)):
			return "Standing by at %s for the %s ice" % [port, area_name]
		return "Standing by at %s (the %s isn't frozen now)" % [port, area_name]
	var riding := GameData.way_current(GameData.variant_of(from_port, to_port)) if leg_current else ""
	if not riding.is_empty():  # (On the second way round, riding a current: see leg_key.)
		return "Sailing to %s on the %s — %d%%" % [GameData.port_name(to_port), riding, int(leg_progress() * 100.0)]
	return "Sailing to %s — %d%%" % [GameData.port_name(to_port), int(leg_progress() * 100.0)]


## "Hauler" or "3 ships".
func _convoy_text() -> String:
	if convoy.is_empty():
		return "a convoy"
	return convoy[0].name if convoy.size() == 1 else "%d ships" % convoy.size()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"model_id": model_id,
		"route": route,
		"pending_route": pending_route,
		"route_index": route_index,
		"hop_to": hop_to,
		"paused": paused,
		"docked_at": docked_at,
		"from_port": from_port,
		"to_port": to_port,
		"fish_target": fish_target,
		"fish_area": fish_area,
		"rig_field": rig_field,
		"rig_port": rig_port,
		"rig_slot": rig_slot,
		"rig_phase": rig_phase,
		"rig_wait": rig_wait,
		"cruise": cruise,
		"research_gear": research_gear,
		"research_base": research_base,
		"research_target": research_target,
		"research_contract": research_contract,
		"research_phase": research_phase,
		"research_work": research_work,
		"research_roll": research_roll,
		"research_since": research_since,
		"fish_home": fish_home,
		"fish_landing": fish_landing,
		"fish_phase": fish_phase,
		"fish_ground": fish_ground,
		"fish_species": fish_species,
		"catch": catch,
		"catch_grade": catch_grade,
		"work_s": work_s,
		"work_limit_s": work_limit_s,
		"fish_wait": fish_wait,
		"fish_slot": fish_slot,
		"leg_key": leg_key,
		"leg_current": leg_current,
		"leg_month": leg_month,
		"traveled_nm": traveled_nm,
		"fuel": fuel,
		"maintenance": maintenance,
		"purchase_price": purchase_price,
		"auto_refuel": auto_refuel,
		"auto_repair": auto_repair,
		"dock_time": dock_time,
		"berth": berth,
		"berth_half": berth_half,
		"captains": captains,
		"berth_phase": berth_phase,
		"berth_time": berth_time,
		"berth_duration": berth_duration,
		"berth_since": berth_since,
		"depart_to": depart_to,
		"storm_hit": storm_hit,
		"worked": worked,
		"cargo_id": cargo_id,
		"cargo_from": cargo_from,
		"cargo_qty": cargo_qty,
		"cargo_cost": cargo_cost,
		"cargo_payment": cargo_payment,
		"cargo_leg_nm": cargo_leg_nm,
		"cargo_breed": cargo_breed,
		"cargo_fresh": cargo_fresh,
		"cargo_since": cargo_since,
		"cargo_farm": cargo_farm,
		"cargo_cut": cargo_cut,
		"unloaded": unloaded,
		"repair_rate": repair_rate,
		"refuel_rate": refuel_rate,
		"stop_sale": stop_sale,
		"stop_cost": stop_cost,
		"stop_fuel_cost": stop_fuel_cost,
		"stop_repair_cost": stop_repair_cost,
		"bill": bill,
		"canal_step": canal_step,
		"lock_time": lock_time,
		"canal_state": canal_state,
		"canal_queue_since": canal_queue_since,
		"lock_slot": lock_slot,
		"canals_entered": canals_entered,
		"leg_toll": leg_toll,
		"stop_toll": stop_toll,
		"delivery_canals": delivery_canals,
		"lost_reason": lost_reason,
		"rescuing": rescuing.name if rescuing else "",
		"job_phase": job_phase,
		"segment_end": segment_end,
		"job_segments": job_segments,
		"align_time": align_time,
		"tow_port": tow_port,
		"job_nm": job_nm,
		"carry_nm": carry_nm,
		"base_port": base_port,
		"station": station,
		"tug_lead": tug_lead,
		"assist_s": assist_s,
		"carry_reversed": carry_reversed,
		"auto_recover": auto_recover,
		"full_loads": full_loads,
		"skin": skin,
		"lost_order": lost_order,
		"sea_time": sea_time,
		"ledger": ledger,
	}


## Saves from before fuel and maintenance load with full tanks, 100%
## maintenance and both toggles on. Call link_rescues() once every ship is loaded.
static func from_dict(data: Dictionary) -> Ship:
	var ship := Ship.new(data.get("name", ""), data.get("model_id", ""), data.get("docked_at", ""))
	ship.id = int(data.get("id", 0))
	ship.route.assign(data.get("route", []))
	ship.pending_route.assign(data.get("pending_route", []))
	ship.route_index = int(data.get("route_index", -1))
	ship.hop_to = str(data.get("hop_to", ""))
	ship.paused = bool(data.get("paused", false))
	ship.from_port = data.get("from_port", "")
	ship.to_port = data.get("to_port", "")
	ship.fish_target = str(data.get("fish_target", ""))
	ship.fish_area = str(data.get("fish_area", ""))
	ship.rig_field = str(data.get("rig_field", ""))
	ship.rig_port = str(data.get("rig_port", ""))
	ship.rig_slot = str(data.get("rig_slot", ""))
	ship.rig_phase = str(data.get("rig_phase", ""))
	ship.rig_wait = float(data.get("rig_wait", 0.0))
	ship.cruise = data.get("cruise", {}) if data.get("cruise") is Dictionary else {}
	ship.research_gear.assign(data.get("research_gear", []))
	ship.research_base = str(data.get("research_base", ""))
	ship.research_target = str(data.get("research_target", ""))
	ship.research_contract = int(data.get("research_contract", 0))
	ship.research_phase = str(data.get("research_phase", ""))
	ship.research_work = float(data.get("research_work", 0.0))
	ship.research_roll = float(data.get("research_roll", 0.0))
	ship.research_since = float(data.get("research_since", 0.0))
	ship.fish_home = str(data.get("fish_home", ""))
	ship.fish_landing = str(data.get("fish_landing", "auto"))
	ship.fish_phase = str(data.get("fish_phase", ""))
	ship.fish_ground = str(data.get("fish_ground", ""))
	ship.fish_species = str(data.get("fish_species", ""))
	ship.catch = float(data.get("catch", 0.0))
	ship.catch_grade = float(data.get("catch_grade", 1.0))
	ship.work_s = float(data.get("work_s", 0.0))
	ship.work_limit_s = float(data.get("work_limit_s", 0.0))
	ship.fish_wait = str(data.get("fish_wait", ""))
	ship.fish_slot = int(data.get("fish_slot", 0))
	ship.leg_key = str(data.get("leg_key", ""))
	ship.leg_current = bool(data.get("leg_current", false))
	ship.leg_month = int(data.get("leg_month", Currents.MEAN))
	ship.traveled_nm = float(data.get("traveled_nm", 0.0))
	ship.fuel = float(data.get("fuel", ship.fuel_tank()))
	ship.maintenance = float(data.get("maintenance", 1.0))
	ship.purchase_price = int(data.get("purchase_price", ship.model().get("price", 0)))
	ship.auto_refuel = bool(data.get("auto_refuel", true))
	ship.auto_repair = bool(data.get("auto_repair", true))
	ship.dock_time = float(data.get("dock_time", -1.0))
	ship.refill_billed = maxf(ship.dock_time, 0.0)
	ship.berth = int(data.get("berth", -1))
	ship.berth_half = int(data.get("berth_half", -1))
	ship.captains = data.get("captains", [])
	if ship.captains.is_empty():  # Saves from before officers: the same ones every time it loads.
		ship.captains = Characters.officers_for(ship.model(), ship.id * 7919 + 17)
	ship.berth_time = float(data.get("berth_time", 0.0))
	ship.berth_duration = float(data.get("berth_duration", 0.0))
	ship.berth_since = float(data.get("berth_since", 0.0))
	ship.depart_to = str(data.get("depart_to", ""))
	ship.storm_hit = str(data.get("storm_hit", ""))
	ship.worked = bool(data.get("worked", false))
	# A cargo ship from a save before berths that was mid-stop queues for a berth to finish it.
	var mid_stop := ship.dock_time >= 0.0 and not ship.is_service() and not str(data.get("docked_at", "")).is_empty()
	ship.berth_phase = str(data.get("berth_phase", BERTH_WAIT if mid_stop else BERTH_NONE))
	ship.cargo_id = GameData.current_commodity(str(data.get("cargo_id", "")))
	ship.cargo_from = str(data.get("cargo_from", ""))
	ship.cargo_qty = int(data.get("cargo_qty", 0))
	ship.cargo_cost = int(data.get("cargo_cost", 0))
	ship.cargo_payment = int(data.get("cargo_payment", 0))
	ship.cargo_leg_nm = float(data.get("cargo_leg_nm", 0.0))
	ship.cargo_breed = str(data.get("cargo_breed", ""))
	ship.cargo_fresh = float(data.get("cargo_fresh", 1.0))
	ship.cargo_since = float(data.get("cargo_since", 0.0))
	ship.cargo_farm = bool(data.get("cargo_farm", false))
	ship.cargo_cut = float(data.get("cargo_cut", 0.0))
	if ship.cargo_id == "coffee" and not (ship.model().get("cargo", []) as Array).has("coffee"):
		ship.cargo_qty = roundi(ship.cargo_qty * 2250.0 / 160.0)  # (A save from before coffee was a farm crop by the ton: its containers as tons of the same worth.)
	ship.unloaded = bool(data.get("unloaded", true))
	ship.repair_rate = float(data.get("repair_rate", 0.0))
	ship.refuel_rate = float(data.get("refuel_rate", 0.0))
	ship.stop_sale = int(data.get("stop_sale", 0))
	ship.stop_cost = int(data.get("stop_cost", 0))
	ship.stop_fuel_cost = float(data.get("stop_fuel_cost", 0.0))
	ship.stop_repair_cost = float(data.get("stop_repair_cost", 0.0))
	ship.bill = float(data.get("bill", 0.0))
	# Saves from before canals: worked out from where the ship is (CanalTraffic.rebuild()).
	ship.canal_step = int(data.get("canal_step", -1))
	ship.lock_time = float(data.get("lock_time", -1.0))
	ship.canal_state = data.get("canal_state", "")
	ship.canal_queue_since = float(data.get("canal_queue_since", 0.0))
	ship.lock_slot = str(data.get("lock_slot", ""))
	ship.canals_entered.assign(data.get("canals_entered", []))
	ship.leg_toll = int(data.get("leg_toll", 0))
	ship.stop_toll = int(data.get("stop_toll", 0))
	ship.delivery_canals.assign(data.get("delivery_canals", []))
	if not str(data.get("delivery_canal", "")).is_empty():  # Saves from before several canals.
		ship.delivery_canals.append(data.delivery_canal)
	ship.lost_reason = data.get("lost_reason", "")
	ship.job_phase = data.get("job_phase", JOB_NONE)
	if ship.job_phase != JOB_FISH:
		ship.fish_phase = ""  # (Only on a trip is it out, at work or coming home: its gear's out only then.)
	ship.segment_end = float(data.get("segment_end", 0.0))
	ship.job_segments = data.get("job_segments", [])
	ship.align_time = float(data.get("align_time", 0.0))
	ship.tow_port = data.get("tow_port", "")
	ship.job_nm = float(data.get("job_nm", 0.0))
	ship.carry_nm = float(data.get("carry_nm", 0.0))
	ship.base_port = data.get("base_port", "")
	ship.station = data.get("station", "")
	ship.tug_lead = bool(data.get("tug_lead", false))
	ship.assist_s = float(data.get("assist_s", -1.0))
	ship.carry_reversed = bool(data.get("carry_reversed", false))
	ship.auto_recover = bool(data.get("auto_recover", true))
	ship.full_loads = bool(data.get("full_loads", true))
	ship.skin = str(data.get("skin", ""))
	ship.lost_order = int(data.get("lost_order", 0))
	ship.sea_time = float(data.get("sea_time", 0.0))
	var saved_ledger: Dictionary = data.get("ledger", {})
	for key: String in ship.ledger:
		ship.ledger[key] = float(saved_ledger.get(key, 0.0))
	ship.set_meta(&"rescuing", data.get("rescuing", ""))
	return ship


## Reconnects recovery boats to the ships they're recovering after loading.
static func link_rescues(all: Array[Ship]) -> void:
	for mammoth in all:
		var target: String = mammoth.get_meta(&"rescuing", "")
		mammoth.remove_meta(&"rescuing")
		for ship in all:
			if not target.is_empty() and ship.name == target:
				mammoth.rescuing = ship
				if not mammoth.is_tug() or mammoth.tug_lead:  # A pair of tugs: the lead one.
					ship.rescuer = mammoth
		if mammoth.rescuing == null and mammoth.job_phase != JOB_FISH and mammoth.job_phase != JOB_RIG and mammoth.job_phase != JOB_REPAIR:
			# (A rescue or tow with no one left to bring in is over. Not a fishing
			# trip: that job needs no other ship, and clearing it left a boat at
			# work on its ground "arriving" there as if at a port, then sailing
			# home as a plain leg with its lines still out.)
			mammoth.job_phase = JOB_NONE


## Applies an update from the host in a multiplayer game: any of to_dict()'s
## keys (values as the host has them). "rescuing" is left to the caller, which
## knows the other ships.
func apply_update(data: Dictionary) -> void:
	for key: String in data:
		var value: Variant = data[key]
		match key:
			"rescuing", "company":
				pass
			"ledger":
				var target: Dictionary = get(key)
				for part: String in value:
					target[part] = value[part]
			"route", "pending_route", "canals_entered", "delivery_canals":
				(get(key) as Array).assign(value)
			"leg_key", "leg_current", "leg_month":
				set(key, value)
				_leg_from = "?"  # (The host's way for its leg: worked out again.)
			_:
				set(key, value)


## Its captain (Characters), or {} if it has none.
func captain() -> Dictionary:
	return captains[0] if not captains.is_empty() else {}

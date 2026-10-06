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

## How long a recovery boat (or an icebreaker) takes to turn: to line up with a
## lost ship, and to turn the pair around if it's taking it back the way it came.
## Ships don't pivot: the map sails them round a turning circle meanwhile.
const ALIGN_SECONDS := 3.0

## Job phases for a Mammoth.
const JOB_NONE := ""
const JOB_APPROACH := "approach"
const JOB_ALIGN := "align"
const JOB_TOW := "tow"
const JOB_UNLOAD := "unload"
## How long a recovery boat takes to load a lost ship (ballast down, float it
## onto the deck, deballast and rise) and, at port, to float it off again.
const LOAD_SECONDS := 4.5

## A ship sells for this fraction of its price, times its maintenance.
const SELL_FRACTION := 0.5
## attention_reason() for skill points to spend: the one reason that isn't a
## problem (Ship tiles show it as a green "+2", not a red warning).
const UPGRADES_REASON := "upgrades to spend"
## Kinds of ship (see _kind()).
const KIND_CARGO := 0
const KIND_RECOVERY := 1
const KIND_ICEBREAKER := 2
const KIND_TUG := 3

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
var paused := false
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
## How far into its stop (dock_time) its repairs and fuel have been done and
## paid for. Not saved: a stop carries on from where it was loaded.
var refill_billed := 0.0
## Cargo aboard (see Market): the commodity id ("" when empty), how many units,
## and what they cost to buy. On arrival, cargo_payment is what they sell for
## (paid when unloading finishes) and cargo_leg_nm the leg they came (for XP).
var cargo_id := ""
## Where the cargo aboard was bought.
var cargo_from := ""
var cargo_qty := 0
var cargo_cost := 0
var cargo_payment := 0
var cargo_leg_nm := 0.0
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
## profit), and the canals whose XP bonus the cargo being unloaded earns.
var stop_toll := 0
var delivery_canals: Array[String] = []

## Why this ship is stranded at sea ("out of fuel", "engine failure"), or "".
var lost_reason := ""
## Send the cheapest capable recovery boat automatically when lost.
var auto_recover := true
## Wait in port until it can buy a full hold before leaving (cargo ships).
var full_loads := true
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
## level_info(), and the XP it was worked out for.
var _level_info := {}
var _level_xp := -1.0
## Cached top_speed(), fuel_per_s() and wear_per_s() (see _refresh_stats()).
var _top_speed := 0.0
var _fuel_per_s := 0.0
var _wear_per_s := 0.0
var _stats_dirty := true
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
## Seconds spent sailing since it was bought; older ships break down more.
var sea_time := 0.0
## Lifetime money in (income: cargo sold) and out (cargo bought, fuel, repair
## and canal tolls), in dollars. A
## recovery boat's own running costs go on its own ledger.
var ledger := {"income": 0.0, "cargo": 0.0, "fuel": 0.0, "repair": 0.0, "tolls": 0.0}
## Total XP from deliveries (cargo ships only), and skill levels bought with
## the points its levels give: "speed", "durability", "efficiency".
var xp := 0.0
var skills := {"speed": 0, "durability": 0, "efficiency": 0, "range": 0}
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
## ship, for the XP it earns when it drops the ship off (see GameState._deliver()).
var job_nm := 0.0
var carry_nm := 0.0
## Recovery boat only: the HQ or hub port it's based at, returns to after a
## job, and sails to when the boats are rebalanced across hubs.
var base_port := ""
## Tug only: true for the tug that leads (drags) its job's tow; the other one
## pushes at the stern.
var tug_lead := false
## Tug only: seconds left before it leaves port on its job (the second tug
## follows the first out). Not saved: after loading it leaves at once.
var tug_wait := 0.0
## Recovery boat only: the ship it's carrying faces the other way from it (it
## met the ship head on); set as it lines up.
var carry_reversed := false
## Recovery boat only: it turned round with the ship aboard before setting
## off with it (the map eases it back onto the lane from its turning circle).
## Not saved.
var turned_round := false
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


## A tug: based at a port on the company's routes, it pushes or drags ships
## lost near there back in (see GameState.tug_plan()).
func is_tug() -> bool:
	return _kind() == KIND_TUG


## A service ship (a recovery boat, an icebreaker or a tug): no route or
## cargo, pays its own fuel and repairs, and is never lost at sea.
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
		else:
			_kind_cache = KIND_CARGO
	return _kind_cache

## The skill paths its upgrade points go on: a tug's range in place of
## durability (it never breaks down).
func skill_names() -> Array[String]:
	if is_tug():
		return ["speed", "range", "efficiency"]
	return ["speed", "efficiency", "durability"]


## Tug only: how far along a lane from its port it fetches lost ships, more
## with the range skill.
func reach_nm() -> float:
	return float(model().get("reach_nm", 0)) * (1.0 + _skill_bonus("range"))


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
	return ledger.income - ledger.cargo - ledger.fuel - ledger.repair - ledger.tolls


## Top speed, including the speed skill and the model's mega upgrade.
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


## Fuel burned per second at sea, less the efficiency skill (and a recovery
## boat's mega upgrade).
func fuel_per_s() -> float:
	if _stats_dirty:
		_refresh_stats()
	return _fuel_per_s


## Maintenance lost per second of running at sea, less the durability skill.
func wear_per_s() -> float:
	if _stats_dirty:
		_refresh_stats()
	return _wear_per_s


## Top speed, fuel burn and wear depend on the model, skills and mega upgrade,
## which change rarely, so they're worked out once and kept until
## invalidate_stats() (called when a skill is spent or a mega upgrade bought).
func _refresh_stats() -> void:
	var data := model()
	var settings: Dictionary = GameData.config.get("mega", {})
	var has_mega := GameState.owner_of(self).has_mega(model_id)
	var mega := 1.0 + (float(settings.get("speed_bonus", 0.5)) if has_mega else 0.0)
	# A recovery boat's mega upgrade also cuts its fuel burn (a cargo ship's
	# raises its profit instead; see GameState.trade_bonus()).
	var mega_fuel := 1.0 - (float(settings.get("recovery_fuel_saving", 0.5)) if has_mega and is_recovery() else 0.0)
	_top_speed = float(data.get("speed_nm_per_s", 0)) * (1.0 + _skill_bonus("speed")) * mega
	_fuel_per_s = float(data.get("fuel_per_s", 0)) * (1.0 - _skill_bonus("efficiency")) * mega_fuel
	_wear_per_s = float(data.get("wear_pct_per_min", 0)) / 100.0 / 60.0 * (1.0 - _skill_bonus("durability"))
	_stats_dirty = false


func invalidate_stats() -> void:
	_stats_dirty = true
	_leg_from = "?"  # The harbor speed zones follow the top speed.


## How much the durability skill cuts the chance of a random breakdown (0..1).
func breakdown_resistance() -> float:
	return _skill_bonus("durability")


## Chance of a random breakdown in one roll (see game_config breakdowns): higher
## the more worn the ship is, times the model's sturdiness (breakdown_factor)
## and the ship's age at sea, less its durability skill.
func breakdown_chance() -> float:
	var settings: Dictionary = GameData.config.get("breakdowns", {})
	var worn := 1.0 - clampf(maintenance, 0.0, 1.0)
	var chance := lerpf(float(settings.get("chance_at_full", 0.0005)), float(settings.get("chance_at_empty", 0.005)), worn)
	var age := minf(1.0 + float(settings.get("age_per_hour_at_sea", 0.1)) * sea_time / 3600.0,
		float(settings.get("max_age_factor", 2.0)))
	return chance * float(model().get("breakdown_factor", 1.0)) * age * (1.0 - breakdown_resistance())


## {level, xp (into the level), cost (of the level)}.
func level_info() -> Dictionary:
	if xp != _level_xp:  # Worked out again only when the XP changes.
		_level_info = Progression.ship_level(model(), xp)
		_level_xp = xp
	return _level_info


func level() -> int:
	return int(level_info().level)


func skill_points() -> int:
	return level() - int(skills.speed) - int(skills.durability) - int(skills.efficiency) - int(skills.range)


func _skill_bonus(skill: String) -> float:
	return int(skills.get(skill, 0)) * Progression.skill_step(skill)


## Cost of restoring 100% maintenance (from 0%).
func full_repair_cost() -> float:
	return float(model().get("repair_cost_per_pct", 0)) * 100.0


## How long a port stop takes, shorter at a hub with the port stops upgrade.
func dock_seconds() -> float:
	return float(model().get("dock_s", 0)) * _hub_stop_factor()


## How long the repair phase takes, and then the refuel phase, while docked.
func refill_phase_seconds() -> float:
	return float(model().get("refill_phase_s", 5)) * _hub_stop_factor()


func _hub_stop_factor() -> float:
	return 1.0 - GameState.owner_of(self).hub_bonus(docked_at, "speed") if is_docked() else 1.0


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
	var seconds := 0.0
	var m := start_maintenance
	var mile := start_mile
	var zones := _current_zones()
	if from != from_port or to != to_port:
		zones = leg_zones(from, to)
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


## Unloading and loading after arriving at a port.
func is_docking() -> bool:
	return is_docked() and dock_time >= 0.0


func has_route() -> bool:
	return not route.is_empty()


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


## Recovery boat only: total seconds spent lining up, taking the ship aboard
## and (if needed) turning around.
func align_seconds() -> float:
	return ALIGN_SECONDS * (2.0 if tow_turns_around() else 1.0) + LOAD_SECONDS


## What the player needs to do for this ship to run at its best, or "".
func attention_reason() -> String:
	if is_lost() and rescuer == null:
		return "lost at sea"
	if is_held():
		return "held in port"
	if canal_state == CANAL_TOLL:
		return "waiting for toll money"
	if not is_service() and is_docked() and not has_route():
		return "no route"
	if is_docked() and paused:
		return "paused"
	if skill_points() > 0:
		return UPGRADES_REASON
	return ""


## Green on the status dot.
func is_active() -> bool:
	if is_icebreaker():
		return not ice_phase.is_empty() or not is_docked()
	if is_recovery() or is_tug():
		return is_on_job() or not is_docked()
	return is_running() and not is_held() and not is_lost()


func fuel_level() -> float:
	var tank := fuel_tank()
	return clampf(fuel / tank, 0.0, 1.0) if tank > 0.0 else 0.0


## How full the hold is (0..1): the cargo aboard, emptying over the first half
## of a stop as it's unloaded and filling over the second half with what it loaded.
func cargo_level() -> float:
	var full := clampf(float(cargo_qty) / capacity(), 0.0, 1.0) if capacity() > 0 else 0.0
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


## Speed and wear factors ([speed, wear]) at a mile of the current leg (see
## GameData.zone_factors()).
func zone_factors(mile: float) -> Array:
	_update_leg()
	for zone: Array in _leg_zones:
		if mile < zone[0]:
			return [zone[1], zone[2]]
	return [1.0, 1.0]


## The current leg's length and zones, looked up once per leg rather than on
## every call (the lookups build text keys, which adds up at sea every step).
func _update_leg() -> void:
	if from_port == _leg_from and to_port == _leg_to:
		return
	_leg_from = from_port
	_leg_to = to_port
	_leg_length = GameData.distance_nm(from_port, to_port)
	_leg_zones = _with_harbor_speed(GameData.lane_zones(from_port, to_port), _leg_length)
	_leg_has_canal = not GameData.canal_crossings(from_port, to_port).is_empty()
	_leg_lane = GameData.lane(from_port, to_port)
	_here_cache = []


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
	return _with_harbor_speed(GameData.lane_zones(from, to), GameData.distance_nm(from, to))


## A lane's zones with the ship's harbor speed (game_config harbor_speed) laid
## over each end: leaving port it builds up from start x its speed to full
## speed with steady acceleration over about `seconds`, and it slows the same
## way coming in, in `steps` pieces of speed each (at the speed halfway through
## the piece), multiplied into whatever the lane's own zone there is.
func _with_harbor_speed(zones: Array, length: float) -> Array:
	var settings: Dictionary = GameData.config.get("harbor_speed", {})
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
## came, turns round.
func _align_heading() -> Vector2:
	var arrive := lane_heading().angle()
	var t := (align_time - ALIGN_SECONDS - LOAD_SECONDS) / ALIGN_SECONDS if tow_turns_around() else 0.0
	return Vector2.from_angle(arrive + PI * clampf(t, 0.0, 1.0))


## Index of the route stop to sail to next from the port the ship is docked at.
func next_route_index() -> int:
	if route_index >= 0 and route_index < route.size() and route[route_index] == docked_at:
		return (route_index + 1) % route.size()
	var here := route.find(docked_at)
	if here >= 0:
		return (here + 1) % route.size()
	return 0  # Not on the route yet: head to its first stop.


func status_text() -> String:
	var canal := canal_status_text()
	if is_icebreaker():
		var duty := _icebreaker_status_text()
		return duty if canal.is_empty() else "%s — %s" % [duty, canal]
	if is_recovery():
		var job := _recovery_status_text()
		return job if canal.is_empty() else "%s — %s" % [job, canal]
	if is_tug():
		var job := _tug_status_text()
		return job if canal.is_empty() else "%s — %s" % [job, canal]
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
			return "Turning round with %s aboard" % rescuing.name
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
			return "%s %s to %s%s" % ["Towing" if tug_lead else "Pushing", rescuing.name, GameData.port_name(tow_port), with]
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
		"paused": paused,
		"docked_at": docked_at,
		"from_port": from_port,
		"to_port": to_port,
		"traveled_nm": traveled_nm,
		"fuel": fuel,
		"maintenance": maintenance,
		"purchase_price": purchase_price,
		"auto_refuel": auto_refuel,
		"auto_repair": auto_repair,
		"dock_time": dock_time,
		"cargo_id": cargo_id,
		"cargo_from": cargo_from,
		"cargo_qty": cargo_qty,
		"cargo_cost": cargo_cost,
		"cargo_payment": cargo_payment,
		"cargo_leg_nm": cargo_leg_nm,
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
		"carry_reversed": carry_reversed,
		"auto_recover": auto_recover,
		"full_loads": full_loads,
		"lost_order": lost_order,
		"sea_time": sea_time,
		"ledger": ledger,
		"xp": xp,
		"skills": skills,
	}


## Saves from before fuel and maintenance load with full tanks, 100%
## maintenance and both toggles on. Call link_rescues() once every ship is loaded.
static func from_dict(data: Dictionary) -> Ship:
	var ship := Ship.new(data.get("name", ""), data.get("model_id", ""), data.get("docked_at", ""))
	ship.id = int(data.get("id", 0))
	ship.route.assign(data.get("route", []))
	ship.pending_route.assign(data.get("pending_route", []))
	ship.route_index = int(data.get("route_index", -1))
	ship.paused = bool(data.get("paused", false))
	ship.from_port = data.get("from_port", "")
	ship.to_port = data.get("to_port", "")
	ship.traveled_nm = float(data.get("traveled_nm", 0.0))
	ship.fuel = float(data.get("fuel", ship.fuel_tank()))
	ship.maintenance = float(data.get("maintenance", 1.0))
	ship.purchase_price = int(data.get("purchase_price", ship.model().get("price", 0)))
	ship.auto_refuel = bool(data.get("auto_refuel", true))
	ship.auto_repair = bool(data.get("auto_repair", true))
	ship.dock_time = float(data.get("dock_time", -1.0))
	ship.refill_billed = maxf(ship.dock_time, 0.0)
	ship.cargo_id = str(data.get("cargo_id", ""))
	ship.cargo_from = str(data.get("cargo_from", ""))
	ship.cargo_qty = int(data.get("cargo_qty", 0))
	ship.cargo_cost = int(data.get("cargo_cost", 0))
	ship.cargo_payment = int(data.get("cargo_payment", 0))
	ship.cargo_leg_nm = float(data.get("cargo_leg_nm", 0.0))
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
	ship.segment_end = float(data.get("segment_end", 0.0))
	ship.job_segments = data.get("job_segments", [])
	ship.align_time = float(data.get("align_time", 0.0))
	ship.tow_port = data.get("tow_port", "")
	ship.job_nm = float(data.get("job_nm", 0.0))
	ship.carry_nm = float(data.get("carry_nm", 0.0))
	ship.base_port = data.get("base_port", "")
	ship.station = data.get("station", "")
	ship.tug_lead = bool(data.get("tug_lead", false))
	ship.carry_reversed = bool(data.get("carry_reversed", false))
	ship.auto_recover = bool(data.get("auto_recover", true))
	ship.full_loads = bool(data.get("full_loads", true))
	ship.lost_order = int(data.get("lost_order", 0))
	ship.sea_time = float(data.get("sea_time", 0.0))
	var saved_ledger: Dictionary = data.get("ledger", {})
	for key: String in ship.ledger:
		ship.ledger[key] = float(saved_ledger.get(key, 0.0))
	ship.xp = float(data.get("xp", 0.0))
	var saved_skills: Dictionary = data.get("skills", {})
	for key: String in ship.skills:
		ship.skills[key] = int(saved_skills.get(key, 0))
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
		if mammoth.rescuing == null:
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
			"ledger", "skills":
				var target: Dictionary = get(key)
				for part: String in value:
					target[part] = value[part]
				if key == "skills":
					invalidate_stats()
			"route", "pending_route", "canals_entered", "delivery_canals":
				(get(key) as Array).assign(value)
			_:
				set(key, value)

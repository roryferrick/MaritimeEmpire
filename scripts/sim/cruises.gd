# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Cruises
extends RefCounted
## Cruise lines (game_config cruises): cruise ships (Ship.is_cruise()) sail
## round trips. A cruise ship's route is its itinerary: the first port its home
## port (the HQ, a hub, or a port with the company's cruise terminal), the rest
## its ports of call. In its home port it takes bookings (in_port()) till its
## departure rule says go; then its guests' tickets are paid and it sails. At
## each port of call it pays a port fee per guest and earns excursion
## commission (arrived()); a port of call a storm has closed is sailed past.
## Back home its guests' onboard spending comes in, its supplies, amenity upkeep
## and entertainment are paid, and the voyage gets a review; then it books its next voyage.
##
## Everything a player sees has its parts shown: recommend() returns the
## recommended price with each factor, demand() the booking ceiling and pool,
## experience() and attraction() theirs. Cabins, amenities and looks change in a
## refit (at the HQ or a hub, out of service for a while); prices, the monthly
## adjustments, the package and the departure rule change any time, free.

signal voyage_started(ship: Ship, guests: int, tickets: int)
signal voyage_finished(ship: Ship, summary: Dictionary)

const CLASSES: Array[String] = ["interior", "ocean", "balcony", "suite"]
const SERVICES: Array[String] = ["food", "crew", "entertainment"]
const SERVICE_NAMES := {food = "Food", crew = "Crew", entertainment = "Entertainment"}
const DECKS := ["teak", "white", "blue"]
const DECK_COLORS := {teak = Color("#b98a55"), white = Color("#f2f2ee"), blue = Color("#5d86b8")}
## How far (nm) from a port a wonder counts as one of its attractions.
const WONDER_NM := 350.0
## How many reviews (voyages) a ship keeps.
const REVIEWS_KEPT := 10
## How often (s of play) prices left to the recommendations are worked out again while booking.
const FOLLOW_S := 10.0

var _state: Node
static var _attractions := {}  # port id -> {wonders: [names], polar: bool}


func _init(state: Node) -> void:
	_state = state


static func settings() -> Dictionary:
	return GameData.config.get("cruises", {})


func connect_signals() -> void:
	_state.ship_broke_down.connect(_on_breakdown)
	_state.ship_lost.connect(_on_lost)
	_state.ship_recovered.connect(func(ship: Ship, _boat: Ship, _port: String, _to: bool) -> void: _on_recovered(ship))


# --- Setup ----------------------------------------------------------------------

## A new cruise ship's setup: the balanced cabin mix, no amenities yet,
## Standard service, white hull with a stripe in the company's colour on teak
## decks, cruise only, sailing at the days or when full (3 days, 90%).
static func default_setup(ship: Ship) -> Dictionary:
	var company: Company = ship.company if ship.company != null else GameState.company
	return {cabins = (settings().get("balanced_mix", {}) as Dictionary).duplicate(), amenities = [],
		service = {food = 1, crew = 1, entertainment = 1}, looks = {hull = "white", stripe = company.color, deck = "teak"},
		prices = {}, monthly = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], package = "none",
		departure = {mode = "both", days = 2, fill = 3}, state = "booking", bookings = {}, booking_since = -1.0,
		voyage = {}, reviews = [], history = [], refit_until = -1.0, auto_prices = true, auto_monthly = true}


## Gives a cruise ship its setup if it has none, its prices the recommended ones.
func ensure(ship: Ship) -> void:
	if not ship.is_cruise() or not ship.cruise.is_empty():
		return
	ship.cruise = default_setup(ship)
	follow_recommendations(ship)


## Prices and monthly adjustments the player hasn't set (auto_prices,
## auto_monthly) follow the recommendations: on a new itinerary and before
## each voyage books.
func follow_recommendations(ship: Ship) -> void:
	if ship.cruise.get("auto_prices", true):
		use_recommended(ship)
	if ship.cruise.get("auto_monthly", true):
		var monthly := []
		for m in 12:
			monthly.append(recommended_monthly(ship, m))
		ship.cruise.monthly = monthly


## Sets every cabin class's price to its recommendation (this month's, before the monthly adjustment).
func use_recommended(ship: Ship) -> void:
	var prices := {}
	for cls: String in CLASSES:
		prices[cls] = int(recommend(ship, cls, -1, false).price)
	ship.cruise.prices = prices


static func is_expedition(ship_or_model: Variant) -> bool:
	var model: Dictionary = ship_or_model.model() if ship_or_model is Ship else ship_or_model
	return str(model.get("category", "")) == "cruise_expedition"


# --- Cabins and capacity ----------------------------------------------------------

## A model's cabin space (in units: an Interior guest takes 1): what its
## guests take with the balanced mix.
static func space(model: Dictionary) -> float:
	var units: Dictionary = settings().get("cabin_units", {})
	var mix: Dictionary = settings().get("balanced_mix", {})
	var per := 0.0
	for cls: String in CLASSES:
		per += float(mix.get(cls, 0)) / 100.0 / float(units.get(cls, 1.0))
	return float(model.get("cruise", {}).get("guests", 0)) / maxf(per, 0.001)


## Guests each cabin class holds with these cabin shares (% of the space).
static func capacity_of(model: Dictionary, cabins: Dictionary) -> Dictionary:
	var units: Dictionary = settings().get("cabin_units", {})
	var room := space(model)
	var out := {}
	for cls: String in CLASSES:
		out[cls] = floori(room * float(cabins.get(cls, 0)) / 100.0 / float(units.get(cls, 1.0)))
	return out


func capacity(ship: Ship) -> Dictionary:
	return capacity_of(ship.model(), ship.cruise.get("cabins", {}))


static func total(by_class: Dictionary) -> int:
	var sum := 0
	for cls: String in CLASSES:
		sum += int(floor(float(by_class.get(cls, 0))))
	return sum


# --- The itinerary --------------------------------------------------------------

static func home_of(ship: Ship) -> String:
	return ship.route[0] if not ship.route.is_empty() else ""


static func stops_of(ship: Ship) -> Array:
	return ship.route.slice(1) if ship.route.size() > 1 else []


## True if a company may base cruises at a port: its HQ, a hub, or its cruise terminal.
func can_be_home(company: Company, port_id: String) -> bool:
	return company.hub_at(port_id) != null or company.terminals.has(port_id)


## The round trip's miles and how long it takes in play seconds (sailing at
## full speed plus each stop).
func trip(ship: Ship) -> Dictionary:
	var route := ship.route
	var nm := 0.0
	var seconds := 0.0
	for i in route.size():
		var a: String = route[i]
		var b: String = route[(i + 1) % route.size()]
		var miles := GameData.distance_nm(a, b)
		if not is_finite(miles):
			continue
		nm += miles
		seconds += ship.leg_seconds(a, b, 0.0, miles, 1.0) + float(ship.model().get("dock_s", 10))
	return {nm = nm, seconds = seconds}


## Nights the voyage takes (game days, at least 1).
func nights(ship: Ship) -> int:
	if ship.route.size() < 2:
		return 4
	var day_s: float = 86400.0 / _state.calendar_seconds_per_second()
	return maxi(1, roundi(float(trip(ship).seconds) / day_s))


## A port's attractions: the wonders within WONDER_NM and whether it's polar.
static func attractions(port_id: String) -> Dictionary:
	if _attractions.has(port_id):
		return _attractions[port_id]
	var port := GameData.get_port(port_id)
	var here := Vector2(float(port.get("lon", 0)), float(port.get("lat", 0)))
	var wonders := []
	for wonder: Dictionary in GameData.wonders:
		if _nm(here, Vector2(float(wonder.lon), float(wonder.lat))) <= WONDER_NM:
			wonders.append(str(wonder.name))
	var polar: bool = absf(here.y) >= 60.0
	for closure: Dictionary in GameData.config.get("seasons", {}).get("closures", []):
		if str(closure.get("id", "")) == "antarctic" and (closure.get("ports", []) as Array).has(port_id):
			polar = true
	_attractions[port_id] = {wonders = wonders, polar = polar}
	return _attractions[port_id]


static func _nm(a: Vector2, b: Vector2) -> float:
	var la := deg_to_rad(a.y)
	var lb := deg_to_rad(b.y)
	var d := sin((lb - la) / 2.0) ** 2 + cos(la) * cos(lb) * sin(deg_to_rad(b.x - a.x) / 2.0) ** 2
	return 2.0 * asin(sqrt(clampf(d, 0.0, 1.0))) * 3440.065


## How appealing an itinerary is (0 to 1), with its parts: stops (up to 4),
## sights (wonders near the ports of call), variety (market regions), and for
## an Expedition cruiser the polar ports.
func attraction(ship: Ship) -> Dictionary:
	var stops := stops_of(ship)
	var sights := 0
	var polar := 0
	var regions := {}
	for port_id: String in stops:
		var near := attractions(port_id)
		sights += (near.wonders as Array).size()
		if is_expedition(ship):  # (And the sites its company has surveyed near the port: see Research.)
			sights += Research.sights_near(ship.company if ship.company != null else GameState.company, port_id)
		polar += 1 if near.polar else 0
		regions[str(GameData.port_region(port_id).get("id", ""))] = true
	var stop_score := clampf(stops.size() / 4.0, 0.0, 1.0)
	var sight_score := clampf(sights / 6.0, 0.0, 1.0)
	var variety := clampf(regions.size() / 3.0, 0.0, 1.0)
	var polar_score := float(polar) / maxf(stops.size(), 1.0)
	var value := 0.35 * stop_score + 0.4 * sight_score + 0.25 * variety
	if is_expedition(ship):
		value = 0.2 * stop_score + 0.35 * sight_score + 0.15 * variety + 0.3 * polar_score
	return {value = value, stops = stops.size(), sights = sights, regions = regions.size(), polar = polar}


# --- Seasons --------------------------------------------------------------------

## The season area (game_config cruises seasons) an itinerary sails in: its
## port furthest from the equator decides.
func season_area(ship: Ship) -> Dictionary:
	var best := ""
	var best_lat := -1.0
	for port_id: String in ship.route:
		var lat := absf(float(GameData.get_port(port_id).get("lat", 0)))
		if lat > best_lat:
			best_lat = lat
			best = port_id
	return area_of(best)


static func area_of(port_id: String) -> Dictionary:
	var port := GameData.get_port(port_id)
	var lat := float(port.get("lat", 0))
	var lon := float(port.get("lon", 0))
	for area: Dictionary in settings().get("seasons", []):
		if lat >= float(area.lat[0]) and lat <= float(area.lat[1]) and lon >= float(area.lon[0]) and lon <= float(area.lon[1]):
			return area
	return {}


## A season area's demand factor in a month (0-11): 1 with no area.
static func season_factor(area: Dictionary, month: int) -> float:
	if area.is_empty():
		return 1.0
	return float((area.months as Array)[clampi(month, 0, 11)])


func month_now() -> int:
	return _state.fishing_month()


## The recommended monthly adjustment (%) for a month: the season against the
## year's average, to the nearest 5%.
func recommended_monthly(ship: Ship, month: int) -> int:
	var area := season_area(ship)
	if area.is_empty():
		return 0
	var average := 0.0
	for m in 12:
		average += season_factor(area, m) / 12.0
	return roundi((season_factor(area, month) / average - 1.0) * 20.0) * 5


# --- Prices -----------------------------------------------------------------------

## The company's Cruises stars as a price factor: 0.7 at none, 1 at 2.5, 1.3 at 5.
func rating_factor(company: Company) -> float:
	return 0.7 + 0.12 * _state.ratings.stars(company, "cruises")


## The ship's fit as a price factor: amenities and service lift it.
func ship_factor(ship: Ship) -> float:
	var points := 0.0
	for amenity: Dictionary in fitted(ship):
		points += float(amenity.get("points", 0.0))
	if ship.model().get("cruise", {}).get("helipad", false):
		points += 1.0
	var service: Dictionary = ship.cruise.get("service", {})
	var average := (float(service.get("food", 1)) + float(service.get("crew", 1)) + float(service.get("entertainment", 1))) / 3.0
	return 1.0 + 0.03 * points + 0.05 * (average - 1.0)


## A cabin class's recommended price per guest for the voyage, with its parts:
## {price, parts: [[what, factor text]]}. month -1 is this month; with
## with_season false the season is left out (the core price; the monthly
## adjustments carry the seasons).
func recommend(ship: Ship, cls: String, month := -1, with_season := true) -> Dictionary:
	var s := settings()
	var night := float((s.get("night_price", {}) as Dictionary).get(cls, 100)) * (float(s.get("expedition_price_factor", 4.0)) if is_expedition(ship) else 1.0)
	var count := nights(ship)
	var company: Company = _state.owner_of(ship)
	var rating := rating_factor(company)
	var appeal := attraction(ship)
	var route := 0.75 + 0.6 * float(appeal.value)
	var area := season_area(ship)
	var season := season_factor(area, month_now() if month < 0 else month) if with_season else 1.0
	var fit := ship_factor(ship)
	var price := night * count * rating * route * season * fit
	var parts := [["%s, %d nights at %s a night" % [str((s.get("cabin_names", {}) as Dictionary).get(cls, cls)), count, Fmt.money(roundi(night))], Fmt.money(roundi(night * count))],
		["Cruise rating (%.1f★)" % _state.ratings.stars(company, "cruises"), "x%.2f" % rating],
		["Itinerary (%d ports of call, %d sights%s)" % [appeal.stops, appeal.sights, ", %d polar" % appeal.polar if is_expedition(ship) else ""], "x%.2f" % route]]
	if with_season:
		parts.append(["Season (%s, %s)" % [str(area.get("name", "no season")), Fmt.month_name(month_now() if month < 0 else month)], "x%.2f" % season])
	parts.append(["Amenities and service", "x%.2f" % fit])
	var package := package_extra(ship)
	if package > 0.0:
		price += package
		parts.append(["%s (what guests would spend)" % package_name(ship), "+" + Fmt.money(roundi(package))])
	return {price = roundi(price / 5.0) * 5, parts = parts}


## What a guest pays in a class this voyage: its core price with this month's adjustment.
func price_now(ship: Ship, cls: String) -> int:
	var monthly: Array = ship.cruise.get("monthly", [])
	var adjust := float(monthly[month_now()]) if monthly.size() == 12 else 0.0
	return roundi(float(ship.cruise.get("prices", {}).get(cls, 0)) * (1.0 + adjust / 100.0))


static func package_name(ship: Ship) -> String:
	return str((settings().get("packages", {}) as Dictionary).get(str(ship.cruise.get("package", "none")), {}).get("name", "Cruise only"))


## What a guest would spend on what the package includes (onboard, excursions).
func package_extra(ship: Ship) -> float:
	var package: Dictionary = (settings().get("packages", {}) as Dictionary).get(str(ship.cruise.get("package", "none")), {})
	var extra := 0.0
	if package.get("onboard", false):
		extra += onboard_per_guest(ship)
	if package.get("excursions", false):
		extra += excursions_per_guest(ship)
	return extra


func onboard_per_guest(ship: Ship) -> float:
	var spend := 0.0
	for amenity: Dictionary in fitted(ship):
		spend += float(amenity.get("spend", 0.0))
	return float(settings().get("onboard_per_night", 35)) * nights(ship) * (1.0 + spend)


func excursions_per_guest(ship: Ship) -> float:
	var total := 0.0
	for port_id: String in stops_of(ship):
		total += _excursion(port_id)
	return total


static func _excursion(port_id: String) -> float:
	var s := settings()
	return float(s.get("excursion_per_guest", 20)) + float(s.get("excursion_per_attraction", 15)) * ((attractions(port_id).wonders as Array).size() + (2 if attractions(port_id).polar else 0))


# --- Amenities and service -------------------------------------------------------

static func amenity(id: String) -> Dictionary:
	for each: Dictionary in settings().get("amenities", []):
		if each.id == id:
			return each
	return {}


## The amenities a model's line can fit.
static func amenities_for(model: Dictionary) -> Array:
	return (settings().get("amenities", []) as Array).filter(func(each: Dictionary) -> bool: return (each.lines as Array).has(model.get("category", "")))


func fitted(ship: Ship) -> Array:
	return (ship.cruise.get("amenities", []) as Array).map(func(id: String) -> Dictionary: return amenity(id)).filter(func(each: Dictionary) -> bool: return not each.is_empty())


## Guest experience (0 to 5) with its parts: amenities for the deck slots,
## premium cabins, service levels, less crowding (only a ship packed with
## Interior and Ocean View guests is crowded; over half Suites never is).
func experience(ship: Ship, fill := -1.0) -> Dictionary:
	var model := ship.model()
	var slots := int(model.get("cruise", {}).get("deck_slots", 2))
	var points := 0.0
	for each: Dictionary in fitted(ship):
		points += float(each.get("points", 0.0))
	var helipad: bool = model.get("cruise", {}).get("helipad", false)
	var amenities := clampf((points + (1.0 if helipad else 0.0)) / maxf(slots, 1.0), 0.0, 1.0)
	var cabins: Dictionary = ship.cruise.get("cabins", {})
	var premium := clampf((float(cabins.get("balcony", 0)) + 2.0 * float(cabins.get("suite", 0))) / 80.0, 0.0, 1.0)
	var service: Dictionary = ship.cruise.get("service", {})
	var service_share := (float(service.get("food", 1)) + float(service.get("crew", 1)) + float(service.get("entertainment", 1))) / 12.0
	if fill < 0.0:
		var voyage: Dictionary = ship.cruise.get("voyage", {})
		fill = float(voyage.get("fill", 0.8))
	var crowded := 0.0
	if float(cabins.get("suite", 0)) <= 50.0:
		crowded = clampf((fill * (float(cabins.get("interior", 0)) + 0.5 * float(cabins.get("ocean", 0))) / 100.0 - 0.45) * 2.0, 0.0, 0.5)
	var value := 5.0 * clampf(0.35 * amenities + 0.25 * premium + 0.4 * service_share - crowded, 0.0, 1.0)
	return {value = value, amenities = amenities, premium = premium, service = service_share, crowded = crowded}


## The crew dial's factor on the model's crew (so on its wages).
func crew_factor(ship: Ship) -> float:
	var levels: Array = settings().get("crew_factor", [1.0])
	return float(levels[clampi(int(ship.cruise.get("service", {}).get("crew", 1)), 0, levels.size() - 1)])


# --- Demand and bookings ----------------------------------------------------------

## The share of a class's berths that will pay a price, against its
## recommendation (game_config cruises price_curve).
static func ceiling_at(ratio: float) -> float:
	var curve: Array = settings().get("price_curve", [[1.0, 0.9]])
	for i in range(1, curve.size()):
		var a: Array = curve[i - 1]
		var b: Array = curve[i]
		if ratio <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), clampf((ratio - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001), 0.0, 1.0))
	return float(curve[-1][1])


## The bookings outlook at the home port now: {pool (would-be cruisers a
## day), ships (cruise ships booking there), share (of the pool, by berths),
## per_day (guests a day this ship can expect), classes: {cls: {price,
## recommended, ratio, ceiling, berths}}, ceiling (the most it can fill, 0-1)}.
func demand(ship: Ship) -> Dictionary:
	var home := home_of(ship)
	var month := month_now()
	var area := area_of(home)
	var pool: float = float(settings().get("pool_per_size", 30)) * _state.port_sizes.size(home) * season_factor(area, month) if not home.is_empty() else 0.0
	var hub: Hub = _state.hub_at(home, _state.owner_of(ship)) if not home.is_empty() else null
	if hub != null:
		pool *= 1.0 + hub.effect_of("passengers")  # (A cruise terminal at the company's hub: see Hub.effect_of().)
	var berths := 0.0
	var mine := float(total(capacity(ship)))
	var others := 0
	for other: Ship in _state.ships:
		if other.is_cruise() and not other.cruise.is_empty() and home_of(other) == home and other.docked_at == home and str(other.cruise.get("state", "")) == "booking":
			berths += float(total(capacity(other)))
			others += 1 if other != ship else 0
	if not (ship.docked_at == home and str(ship.cruise.get("state", "")) == "booking"):
		berths += mine
	var share := mine / maxf(berths, 1.0)
	var classes := {}
	var fillable := 0.0
	for cls: String in CLASSES:
		var berths_in := float(capacity(ship).get(cls, 0))
		var recommended := float(recommend(ship, cls).price)
		var price := float(price_now(ship, cls))
		var ratio := price / maxf(recommended, 1.0)
		var ceiling := ceiling_at(ratio)
		classes[cls] = {price = price, recommended = recommended, ratio = ratio, ceiling = ceiling, berths = berths_in}
		fillable += ceiling * berths_in
	return {pool = pool, others = others, share = share, per_day = pool * share, classes = classes,
		ceiling = fillable / maxf(mine, 1.0), season = season_factor(area, month), area = str(area.get("name", "")), month = month}


## A cruise ship docked: true while it stays in port (in a refit, or at home
## taking bookings), false to sail on (GameState then does the rest). Sails
## past a port of call a storm has closed.
func in_port(ship: Ship, delta: float) -> bool:
	ensure(ship)
	var setup: Dictionary = ship.cruise
	if str(setup.get("state", "")) == "refit":
		if _state.play_time < float(setup.get("refit_until", 0.0)):
			setup.status = "In refit: back in service in %s" % Fmt.duration(float(setup.refit_until) - _state.play_time)
			return true
		setup.state = "booking"
		setup.booking_since = -1.0
		_state.ship_changed.emit(ship)
	if ship.route.size() < 2:
		setup.status = "Needs an itinerary: its home port and at least one port of call"
		return true
	var home := home_of(ship)
	var bound: String = ship.route[ship.next_route_index()]
	if ship.docked_at != home or bound == home:
		_skip_closed(ship)
		return false
	var who: Company = _state.owner_of(ship)
	if not can_be_home(who, home):
		setup.status = "%s needs a cruise terminal (or a hub) to sail from" % GameData.port_name(home)
		return true
	if str(setup.get("state", "")) == "sailing":
		return false
	if float(setup.get("booking_since", -1.0)) < 0.0:
		setup.booking_since = _state.play_time
		setup.bookings = {}
		follow_recommendations(ship)
	if _state.play_time - float(setup.get("followed", -999.0)) >= FOLLOW_S:  # (Prices left to the recommendations keep up with the rating and the month.)
		setup.followed = _state.play_time
		follow_recommendations(ship)
	_book(ship, delta)
	if _ready_to_sail(ship):
		_start_voyage(ship)
		_skip_closed(ship)
		return false
	return true


## Bookings coming in: the ship's share of the home port's would-be cruisers,
## each class filling toward its ceiling.
func _book(ship: Ship, delta: float) -> void:
	var outlook := demand(ship)
	var day_s: float = 86400.0 / _state.calendar_seconds_per_second()
	var arrivals: float = float(outlook.per_day) * delta / day_s
	var bookings: Dictionary = ship.cruise.bookings
	var room := {}
	var room_total := 0.0
	for cls: String in CLASSES:
		var entry: Dictionary = outlook.classes[cls]
		var left := maxf(float(entry.ceiling) * float(entry.berths) - float(bookings.get(cls, 0.0)), 0.0)
		room[cls] = left
		room_total += left
	if room_total > 0.0:
		for cls: String in CLASSES:
			bookings[cls] = float(bookings.get(cls, 0.0)) + minf(float(room[cls]), arrivals * float(room[cls]) / room_total)
	var booked := total(bookings)
	var berths := total(capacity(ship))
	var waited: float = (_state.play_time - float(ship.cruise.booking_since)) / day_s
	ship.cruise.status = "Booking at %s: %d of %d guests (%d%%), %.1f days in port; most it can fill at these prices %d%%" % [
		GameData.port_name(home_of(ship)), booked, berths, roundi(100.0 * booked / maxf(berths, 1.0)), waited, roundi(100.0 * float(outlook.ceiling))]


## Whether the departure rule says sail: after the days, at the fill, or both
## (once at the fill, booking on till the days are up or it's full; at the
## days, sailing anyway).
func _ready_to_sail(ship: Ship) -> bool:
	var rule: Dictionary = ship.cruise.get("departure", {})
	var choices: Dictionary = settings().get("departures", {})
	var days := float((choices.get("days", [3]) as Array)[clampi(int(rule.get("days", 2)), 0, 4)])
	var fill_goal := float((choices.get("fill", [90]) as Array)[clampi(int(rule.get("fill", 3)), 0, 4)]) / 100.0
	var day_s: float = 86400.0 / _state.calendar_seconds_per_second()
	var waited: float = (_state.play_time - float(ship.cruise.booking_since)) / day_s
	var berths := maxf(total(capacity(ship)), 1.0)
	var fill := total(ship.cruise.bookings) / berths
	match str(rule.get("mode", "both")):
		"time":
			return waited >= days
		"fill":
			return fill >= fill_goal - 0.0001
	return waited >= days or fill >= 0.9999


func _start_voyage(ship: Ship) -> void:
	var guests := {}
	var tickets := 0
	for cls: String in CLASSES:
		var count := int(floor(float(ship.cruise.bookings.get(cls, 0.0))))
		guests[cls] = count
		tickets += count * price_now(ship, cls)
	var count := total(guests)
	var who: Company = _state.owner_of(ship)
	# A group charter from this port (Contracts): its party fills empty berths at its rate.
	var charter: Array = _state.contracts.charter_voyage(who, home_of(ship), maxi(int(total(capacity(ship))) - count, 0))
	if int(charter[0]) > 0:
		guests["standard"] = int(guests.get("standard", 0)) + int(charter[0])
		count += int(charter[0])
		tickets += int(charter[1])
	var appeal := attraction(ship)
	var recommended := 0.0
	var paid := 0.0
	for cls: String in CLASSES:
		recommended += float(recommend(ship, cls).price) * int(guests[cls])
		paid += float(price_now(ship, cls)) * int(guests[cls])
	ship.cruise.voyage = {guests = guests, total = count, tickets = tickets, nights = nights(ship), start = _state.play_time,
		fill = count / maxf(total(capacity(ship)), 1.0), stops = [], skipped = [], incidents = 0, lost = false, refunds = 0,
		package = str(ship.cruise.get("package", "none")), attraction = float(appeal.value), nm = float(trip(ship).nm),
		value_ratio = paid / maxf(recommended, 1.0), excursions = 0, port_fees = 0}
	ship.cruise.state = "sailing"
	ship.cruise.bookings = {}
	ship.cruise.booking_since = -1.0
	ship.cruise.status = ""
	if tickets > 0:
		_state._add_money(who, tickets)
		_state._record(ship, "income", tickets)
	voyage_started.emit(ship, count, tickets)


## Sails past its next port of call while a storm has it closed.
func _skip_closed(ship: Ship) -> void:
	var voyage: Dictionary = ship.cruise.get("voyage", {})
	if voyage.is_empty():
		return
	for attempt in ship.route.size():
		var next := ship.next_route_index()
		var port: String = ship.route[next]
		if next == 0 or _state.weather.closed_by(port).is_empty():
			return
		(voyage.skipped as Array).append(port)
		ship.route_index = next  # (As if it had called there: on to the one after.)


## A cruise ship docking: at a port of call, its port fees and excursions; home, the voyage's end.
func arrived(ship: Ship, port_id: String) -> void:
	ensure(ship)
	var voyage: Dictionary = ship.cruise.get("voyage", {})
	if voyage.is_empty() or str(ship.cruise.get("state", "")) != "sailing":
		return
	var who: Company = _state.owner_of(ship)
	var guests := int(voyage.total)
	if port_id == home_of(ship):
		_finish_voyage(ship)
		return
	if not stops_of(ship).has(port_id) or (voyage.stops as Array).has(port_id):
		return
	(voyage.stops as Array).append(port_id)
	if who.hub_at(port_id) == null and guests > 0:
		var fee := roundi(guests * float(settings().get("port_fee_per_guest", 6)))
		_state._add_money(who, -fee)
		_state._record(ship, "port_fees", fee)
		voyage.port_fees = int(voyage.port_fees) + fee
	var package: Dictionary = (settings().get("packages", {}) as Dictionary).get(str(voyage.package), {})
	if not package.get("excursions", false) and guests > 0:
		var income := roundi(guests * _excursion(port_id) * 0.5)  # (About half the guests go ashore on one.)
		_state._add_money(who, income)
		_state._record(ship, "income", income)
		voyage.excursions = int(voyage.excursions) + income


func _finish_voyage(ship: Ship) -> void:
	var voyage: Dictionary = ship.cruise.voyage
	var who: Company = _state.owner_of(ship)
	var s := settings()
	var guests := int(voyage.total)
	var nights_sailed := maxi(1, roundi((_state.play_time - float(voyage.start)) / (86400.0 / _state.calendar_seconds_per_second())))
	var guest_nights := guests * nights_sailed
	var package: Dictionary = (s.get("packages", {}) as Dictionary).get(str(voyage.package), {})
	var onboard := 0
	if not package.get("onboard", false) and guests > 0:
		var spend := 0.0
		for each: Dictionary in fitted(ship):
			spend += float(each.get("spend", 0.0))
		onboard = roundi(guest_nights * float(s.get("onboard_per_night", 35)) * (1.0 + spend))
		_state._add_money(who, onboard)
		_state._record(ship, "income", onboard)
	var service: Dictionary = ship.cruise.get("service", {})
	var costs: Array = s.get("service_cost", [1.0])
	var food := float(costs[clampi(int(service.get("food", 1)), 0, costs.size() - 1)])
	var show := float(costs[clampi(int(service.get("entertainment", 1)), 0, costs.size() - 1)])
	var upkeep := 0.0
	for each: Dictionary in fitted(ship):
		upkeep += float(each.get("upkeep", 0.0))
	var supplies := roundi(guest_nights * (float(s.get("supplies_per_night", 22)) * food + float(s.get("entertainment_per_night", 6)) * show + upkeep))
	if supplies > 0:
		_state._add_money(who, -supplies)
		_state._record(ship, "supplies", supplies)
	# The review: experience, the itinerary (less the ports missed), value for money and how it went.
	var fill := float(voyage.fill)
	var exp := float(experience(ship, fill).value)
	var itinerary := 5.0 * clampf(float(voyage.attraction) - 0.15 * (voyage.skipped as Array).size(), 0.0, 1.0)
	var value := 5.0 * clampf(1.0 - (float(voyage.value_ratio) - 0.9) / 1.1, 0.0, 1.0)
	var smooth := clampf(5.0 - 1.5 * int(voyage.incidents) - 0.8 * (voyage.skipped as Array).size(), 0.0, 5.0)
	var review := snappedf(clampf(0.3 * exp + 0.25 * itinerary + 0.25 * value + 0.2 * smooth, 0.0, 5.0), 0.1) if guests > 0 else -1.0
	if review >= 0.0:
		var reviews: Array = ship.cruise.reviews
		reviews.append(review)
		while reviews.size() > REVIEWS_KEPT:
			reviews.pop_front()
	var summary := {guests = guests, nights = nights_sailed, tickets = int(voyage.tickets), onboard = onboard, excursions = int(voyage.excursions),
		port_fees = int(voyage.port_fees), supplies = supplies, refunds = int(voyage.refunds), review = review,
		skipped = (voyage.skipped as Array).size(), incidents = int(voyage.incidents), parts = {experience = exp, itinerary = itinerary, value = value, smooth = smooth}}
	var history: Array = ship.cruise.get_or_add("history", [])
	history.append(summary)
	while history.size() > 5:
		history.pop_front()
	ship.cruise.voyage = {}
	ship.cruise.state = "booking"
	ship.cruise.booking_since = -1.0
	voyage_finished.emit(ship, summary)


# --- Trouble ----------------------------------------------------------------------

func _refund(ship: Ship, share: float) -> void:
	var voyage: Dictionary = ship.cruise.get("voyage", {})
	var amount := roundi(float(voyage.get("tickets", 0)) * share)
	if amount <= 0:
		return
	var who: Company = _state.owner_of(ship)
	_state._add_money(who, -amount)
	_state._record(ship, "income", -amount)
	voyage.refunds = int(voyage.get("refunds", 0)) + amount


func _on_breakdown(ship: Ship) -> void:
	if ship.is_cruise() and not ship.cruise.get("voyage", {}).is_empty():
		ship.cruise.voyage.incidents = int(ship.cruise.voyage.incidents) + 1
		_refund(ship, float(settings().get("breakdown_refund", 0.15)))


func _on_lost(ship: Ship) -> void:
	if ship.is_cruise() and not ship.cruise.get("voyage", {}).is_empty() and not ship.cruise.voyage.get("lost", false):
		ship.cruise.voyage.lost = true
		ship.cruise.voyage.incidents = int(ship.cruise.voyage.incidents) + 3
		_refund(ship, float(settings().get("loss_refund", 0.75)))


## A rescue softens a loss: part of the refund comes back and it counts one incident less.
func _on_recovered(ship: Ship) -> void:
	if ship.is_cruise() and ship.cruise.get("voyage", {}).get("lost", false):
		var voyage: Dictionary = ship.cruise.voyage
		voyage.lost = false
		voyage.incidents = maxi(int(voyage.incidents) - 1, 0)
		var back := roundi(float(voyage.tickets) * (float(settings().get("loss_refund", 0.75)) - float(settings().get("rescue_refund", 0.4))))
		if back > 0:
			var who: Company = _state.owner_of(ship)
			_state._add_money(who, back)
			_state._record(ship, "income", back)
			voyage.refunds = int(voyage.refunds) - back


# --- Refits and terminals ---------------------------------------------------------

## What a refit to a new setup costs and how long it takes: {cost, days, changes}.
func refit_quote(ship: Ship, new_setup: Dictionary) -> Dictionary:
	var price := float(ship.model().get("price", 0))
	var s := settings()
	var cost := 0.0
	var changes := 0
	var old: Dictionary = ship.cruise
	for id: String in new_setup.get("amenities", []):
		if not (old.get("amenities", []) as Array).has(id):
			cost += float(amenity(id).get("cost", 0.0)) * price
			changes += 1
	for id: String in old.get("amenities", []):
		if not (new_setup.get("amenities", []) as Array).has(id):
			changes += 1
	var moved := 0.0
	for cls: String in CLASSES:
		moved += absf(float(new_setup.get("cabins", {}).get(cls, 0)) - float(old.get("cabins", {}).get(cls, 0)))
	if moved > 0.0:
		cost += float(s.get("refit_cost", {}).get("cabins", 0.05)) * price * moved / 2.0 / 10.0
		changes += 1
	if new_setup.get("looks", {}) != old.get("looks", {}):
		cost += float(s.get("refit_cost", {}).get("looks", 0.005)) * price
		changes += 1
	var days := 0.0 if changes == 0 else float(s.get("refit_days", 0.5)) + float(s.get("refit_days_per_change", 0.25)) * changes
	return {cost = roundi(cost), days = days, changes = changes}


func refit_error(ship: Ship, new_setup: Dictionary) -> String:
	var who: Company = _state.owner_of(ship)
	var model := ship.model()
	if not ship.is_docked() or who.hub_at(ship.docked_at) == null:
		return "Refits are done at your HQ or a hub: bring it there first."
	if str(ship.cruise.get("state", "")) == "sailing":
		return "It's on a voyage."
	var sum := 0
	for cls: String in CLASSES:
		var share := int(new_setup.get("cabins", {}).get(cls, 0))
		if share < 0 or share % int(settings().get("share_step", 5)) != 0:
			return "Cabin shares go in %d%% steps." % int(settings().get("share_step", 5))
		sum += share
	if sum != 100:
		return "The cabin shares must add up to 100% (they come to %d%%)." % sum
	if (new_setup.get("amenities", []) as Array).size() > int(model.get("cruise", {}).get("deck_slots", 2)):
		return "It has only %d deck slots." % int(model.get("cruise", {}).get("deck_slots", 2))
	var quote := refit_quote(ship, new_setup)
	if int(quote.changes) == 0:
		return "Nothing to change."
	if who.money < int(quote.cost):
		return "The refit costs %s." % Fmt.money(int(quote.cost))
	return ""


## Refits a cruise ship (cabins, amenities, looks): paid now, out of service
## for the refit's days, its bookings for the next voyage cancelled.
func refit(ship: Ship, new_setup: Dictionary) -> String:
	var error := refit_error(ship, new_setup)
	if not error.is_empty():
		return error
	var quote := refit_quote(ship, new_setup)
	var who: Company = _state.owner_of(ship)
	for key: String in ["cabins", "amenities", "looks"]:
		ship.cruise[key] = (new_setup[key] as Variant).duplicate(true) if new_setup.has(key) else ship.cruise[key]
	ship.cruise.state = "refit"
	ship.cruise.refit_until = _state.play_time + float(quote.days) * 86400.0 / _state.calendar_seconds_per_second()
	ship.cruise.bookings = {}
	ship.cruise.booking_since = -1.0
	_state._add_money(who, -int(quote.cost))
	_state._record(ship, "upgrades", int(quote.cost))
	return ""


## What a company's next cruise terminal costs (its first, then each after).
func terminal_cost(company: Company) -> int:
	var costs: Array = settings().get("terminal_costs", [2500000, 5000000])
	return int(costs[0 if company.terminals.is_empty() else mini(1, costs.size() - 1)])


func terminal_error(company: Company, port_id: String) -> String:
	if company.hub_at(port_id) != null:
		return "Your HQ and hubs need no terminal."
	if company.terminals.has(port_id):
		return "You have a terminal there already."
	if company.money < terminal_cost(company):
		return "A cruise terminal there costs %s." % Fmt.money(terminal_cost(company))
	return ""


# --- Ratings --------------------------------------------------------------------

## The Cruises type's sample parts for a company (each 0 to 5: guest
## experience, itinerary, reliability & safety, value & reviews), with figures.
func rating_parts(company: Company, ships: Array) -> Dictionary:
	if ships.is_empty():
		return {parts = [0.0, 0.0, 0.0, 0.0], figures = {ships = 0}}
	var exp := 0.0
	var appeal := 0.0
	var maintenance := 0.0
	var incidents := 0.0
	var skipped := 0.0
	var reviews := []
	var voyages := 0
	for ship: Ship in ships:
		ensure(ship)
		exp += float(experience(ship).value)
		appeal += float(attraction(ship).value) if ship.route.size() > 1 else 0.0
		maintenance += ship.maintenance
		for summary: Dictionary in ship.cruise.get("history", []):
			incidents += int(summary.get("incidents", 0))
			skipped += int(summary.get("skipped", 0))
			voyages += 1
		reviews.append_array(ship.cruise.get("reviews", []))
	var n := float(ships.size())
	var review_average := 0.0
	for each: float in reviews:
		review_average += each
	review_average = review_average / reviews.size() if not reviews.is_empty() else 2.5
	var safety := 5.0 * clampf(0.5 * clampf((maintenance / n - 0.4) / 0.55, 0.0, 1.0) + 0.5 * (1.0 - clampf((incidents + 0.5 * skipped) / maxf(voyages, 1.0), 0.0, 1.0)), 0.0, 1.0)
	return {parts = [exp / n, 5.0 * appeal / n, safety, review_average],
		figures = {ships = ships.size(), experience = exp / n, attraction = appeal / n, maintenance = maintenance / n,
			incidents = incidents, skipped = skipped, voyages = voyages, reviews = reviews.size(), review = review_average}}

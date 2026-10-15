# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name TutorialCard
extends PanelContainer
## The tutorial: tips on the basics, one at a time, in a card in the bottom left
## of the main screens (over the Route Assignment map too), each spoken by one
## of the story's people (Characters.STORY: Captain Mo B. Dick does the
## welcome and the birds, Sailor Sonny shipping, HQ Marissa the money and the
## achievements, Deckhand Joe sailing and the odd things about ships), their
## portrait beside it, and at least TIP_GAP_S of play between one tip and the
## next so they come at a digestible pace. Only in saves
## started with the tutorial (GameState.tutorials), and only while the map's
## Tutorial switch is on (GameState.tutorials_on).
##
## Each tip (see _tips()) shows once its moment comes, the first not yet seen in
## list order, and goes for good (GameState.tutorial_done) when the player
## clicks Got it or does what it asks.

const CHECK_SECONDS := 0.25
const WIDTH := 460.0
const MARGIN := 12.0
const TIP_GAP_S := 25.0
const PORTRAIT_PX := 76.0

var _title := Label.new()
var _body := Label.new()
var _button := Button.new()
var _tips: Array[Dictionary] = []
var _tip := {}  # The tip showing, or {}.
var _clock := CHECK_SECONDS
var _portrait := Portrait.new({}, true)
var _speaker := Label.new()
var _gap_until := 0.0  # Play time the next tip may come at.


func _ready() -> void:
	theme_type_variation = &"MapPopup"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override(&"separation", 12)
	box.add_child(head)
	_portrait.custom_minimum_size = Vector2.ONE * PORTRAIT_PX
	_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_portrait)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override(&"separation", 2)
	head.add_child(titles)
	_speaker.theme_type_variation = &"DimLabel"
	titles.add_child(_speaker)
	_title.theme_type_variation = &"HeaderLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_title)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size.x = WIDTH - 32.0
	box.add_child(_body)
	_button.text = "Got it"
	_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	_button.custom_minimum_size = Vector2(110, 36)
	_button.pressed.connect(_finish)
	box.add_child(_button)
	_tips = _tips_list()
	visible = false


func _process(delta: float) -> void:
	_clock += delta
	if _clock >= CHECK_SECONDS:
		_clock = 0.0
		_update_tip()
	visible = GameState.tutorials_on and not _tip.is_empty()
	if visible:
		# Sits in the bottom left corner, growing up as tall as its text; at the
		# top left over the Route Assignment map, which centers on the ship.
		size = Vector2(WIDTH, get_combined_minimum_size().y)
		var top := _route_screen_open()
		position = Vector2(MARGIN, MARGIN if top else get_parent_area_size().y - size.y - MARGIN)


## Retires the showing tip if the player has done what it asks, then shows the
## first tip not yet seen whose moment has come.
func _update_tip() -> void:
	if not _tip.is_empty() and _tip.has("done") and (_tip.done as Callable).call():
		_finish()
	var next := {}
	if _tip.is_empty() and GameState.play_time < _gap_until:
		return  # (A breather after the last tip.)
	for tip: Dictionary in _tips:
		if not GameState.tutorial_done.has(tip.id) and (tip.show as Callable).call():
			next = tip
			break
	if next.get("id", "") == _tip.get("id", ""):
		return
	_tip = next
	if not _tip.is_empty():
		_title.text = _tip.title
		_body.text = (_tip.text as Callable).call()
		var who: Dictionary = Characters.STORY.get(str(_tip.get("who", "sonny")), Characters.STORY.sonny)
		_portrait.character = {name = who.name, look = who.look}
		_speaker.text = str(who.name).to_upper()


func _finish() -> void:
	_gap_until = GameState.play_time + TIP_GAP_S
	if _tip.is_empty():
		return
	if not GameState.tutorial_done.has(_tip.id):
		GameState.tutorial_done.append(_tip.id)
	_tip = {}
	_clock = CHECK_SECONDS  # (Looked at again straight away; the next tip waits out TIP_GAP_S.)


## The tips, in order: {id, title, text (a Callable, so names and numbers are
## current), show (when its moment has come), and optionally done (it's
## finished without Got it once this is true)}.
func _tips_list() -> Array[Dictionary]:
	var seen := func(id: String) -> bool: return GameState.tutorial_done.has(id)
	var always := func() -> bool: return true
	var breakdown_level := int(GameData.config.get("breakdowns", {}).get("min_company_level", 6))
	return [
		{id = "welcome", who = "dick", title = "Welcome to %s" % GameState.company_name, show = always,
			text = func() -> String: return "Welcome aboard. I'm Captain Mo B. Dick, and this is your shipping company. %s\n\nYour headquarters is %s: the port with a ring in your color. Sonny, Marissa, Joe and I will chip in as you go; switch us off any time with the Tutorial switch in Settings (press Esc)." % [_type_welcome(), GameData.port_name(GameState.home_port)]},
		{id = "map", who = "sonny", title = "Getting around", show = func() -> bool: return seen.call("welcome"),
			text = func() -> String: return "Drag the globe to turn it and scroll to zoom. Click a port to see its prices, or a ship to see what it's doing.\n\nThe buttons at the top right of the screen set the game speed: pause, or speed up to 8x (F steps through them)."},
		# Shown over the Route Assignment map, so it comes before the tip that opens it.
		{id = "route_screen", who = "sonny", title = "Planning a route",
			show = func() -> bool: return seen.call("map") and _route_screen_open(),
			done = _any_route_assigned,
			text = func() -> String: return "Click ports in the order to visit them; the ship loops round them. Gray ports are out of range.\n\nGreen under a leg is the cargo and about what it makes; red means it sails empty. Two or three ports with green both ways make a good first loop. Then press Accept."},
		{id = "buy_ship", who = "sonny", title = "Buy your first ship",
			show = func() -> bool: return seen.call("map") and _cargo_ships().is_empty() and _fishing_boats().is_empty(),
			done = func() -> bool: return not _cargo_ships().is_empty() or not _fishing_boats().is_empty(),
			text = func() -> String: return "Open the Shop tab at the bottom of the screen and buy a ship. %s You'll give it a name, and it's launched at %s." % [
				_first_ship_advice(), GameData.port_name(GameState.home_port)]},
		{id = "assign_route", who = "sonny", title = "Give it a route",
			show = func() -> bool: return seen.call("map") and not _cargo_ships().is_empty() and not _any_route_assigned(),
			done = _any_route_assigned,
			text = func() -> String: return "A new ship waits in port until it has a route. Click it on the map (or in the Ships tab) and press Assign Route."},
		{id = "trading", who = "sonny", title = "Trading runs itself",
			show = func() -> bool: return (_any_route_assigned() or not _fishing_boats().is_empty()) and not _route_screen_open(),
			text = func() -> String: return "At each stop your ship sells its cargo, then buys the most profitable cargo it can carry to the next port, refuels and repairs, and sets off again.\n\nEvery sale shows up in the Activity list on the left, and your money is at the top left." if _any_route_assigned() else "Your boat runs itself: based at a port (Fishing base in its popup), it picks what's in season on the grounds nearby, goes out for a few days and sells the catch when it comes home.\n\nEvery sale shows up in the Activity list on the left, and your money is at the top left."},
		{id = "upkeep", who = "marissa", title = "Fuel and wear",
			show = func() -> bool: return seen.call("trading") and _has_sold(),
			text = func() -> String: return "Ships burn fuel and wear down at sea, and the more worn they are, the slower they go. The Refuel and Repair switches in a ship's popup top them up at every stop.\n\nA ship that can't make its next leg waits in port, and the Ships tab gets a red dot whenever a ship needs you; hover it to see why."},
		{id = "prices", who = "marissa", title = "Finding better trades", show = func() -> bool: return seen.call("upkeep"),
			text = func() -> String: return "The Prices picker in the top right of the map colors every port by a commodity's price: green where it's cheap to buy, red where it sells high.\n\nThe Markets tab lists the best trades, anywhere and close by, and a port's popup shows all its prices."},
		{id = "grow", who = "sonny", title = "Grow your fleet", show = func() -> bool: return seen.call("prices"),
			text = func() -> String: return "More ships, more profit. The Shop tab gets a red dot when you can afford another. Give each one its own route, or send several round a good loop.\n\nThe Finances tab shows where your money comes from and where it goes, and which ships earn the most."},
		{id = "levels", who = "marissa", title = "Company levels",
			show = func() -> bool: return seen.call("map") and GameState.company_level() >= 2,
			text = func() -> String: return "Every delivery earns your company XP. New levels unlock bigger ships and let you own more of each. At level %d you branch out into another company type, and again every %d levels.\n\nClick your level at the top left to see what's coming next." % [Progression.type_pick_every(), Progression.type_pick_every()]},
		{id = "ship_upgrades", who = "joe", title = "Ship upgrades",
			show = func() -> bool: return seen.call("map") and _cargo_ships().any(func(ship: Ship) -> bool: return ship.skill_points() > 0),
			text = func() -> String: return "Ships level up from their own deliveries, and each level gives an upgrade point. Spend them on speed, durability or gas efficiency with Upgrades in the ship's popup, or Upgrade all in the Ships tab. Each upgrade costs money too."},
		{id = "hubs", who = "sonny", title = "Hubs",
			show = func() -> bool: return seen.call("map") and GameState.hubs_available() > 0,
			text = func() -> String: return "You can found a hub. Click a port and open its Hub tab to build one there.\n\nHubs level up from deliveries unloaded at them, their upgrades help every ship that docks, and new ships can launch from them. A hub is permanent, so pick a busy port on your routes."},
		{id = "breakdowns", who = "joe", title = "Breakdowns",
			show = func() -> bool: return seen.call("map") and GameState.company_level() >= breakdown_level,
			text = func() -> String: return "From now on ships can break down at sea, more often the more worn they are, so keep Repair on.\n\nA ship that breaks down completely or runs out of fuel is lost at sea until a recovery boat carries it to port. Recovery boats are in the Shop, from company level %d." % _first_recovery_level()},
		{id = "storms", who = "joe", title = "Storms",
			show = func() -> bool: return seen.call("map") and GameState.weather.active() and not GameState.weather.storms.is_empty(),
			text = func() -> String: return "Storms now affect your ships. They form in their real seasons (hurricanes and typhoons in late summer, gales in winter), drift across the sea and fade.\n\nShips sail through them slower and wearing faster, and the strongest hurricane cores close ports while they pass; ships wait them out. The activity log warns you when one heads for your ports."},
		{id = "seasons", who = "joe", title = "Seasonal closures",
			show = func() -> bool: return seen.call("map") and GameState.seasonal.active(),
			text = func() -> String: return "From now on the seasons close some places, on their real dates: the Great Lakes locks and ports in winter, Antarctica outside its summer, and icebound ports like Nain and Magadan. Ice in the Gulf of Finland slows ships instead.\n\nShips won't start a leg they can't finish before a closure; they wait in port until it reopens. The activity log warns you 10 days ahead, and a port's popup and the route screen show its dates."},
		{id = "icebreakers", who = "joe", title = "Icebreakers",
			show = func() -> bool: return seen.call("seasons") and GameState.company_level() >= _first_icebreaker_level(),
			text = func() -> String: return "Icebreakers are in the Shop now. You only need one if your ships trade where winter ice closes ports: the Great Lakes, the Sea of Okhotsk, the White Sea, or the Gulf of Finland, where the ice just slows ships. A nuclear one can keep the Arctic routes open all winter.\n\nBuy one, then pick its Station in its popup. While the ice is in, it leads your ships through in small convoys (or keeps the Gulf of Finland's fairways open). The rest of the year it just waits."},
		{id = "lost", who = "joe", title = "Lost at sea",
			show = func() -> bool: return GameState.fleet().any(func(ship: Ship) -> bool: return ship.is_lost()),
			text = func() -> String: return "A ship is lost at sea. A recovery boat can carry it to the nearer end of its leg: press Send Recovery in the lost ship's popup. With its Rescue switch on (it is by default), one is sent automatically.\n\nNo recovery boat yet? Buy one in the Shop when it unlocks."},
		{id = "birds_follow", who = "dick", title = "Birds on your wake",
			show = func() -> bool: return seen.call("trading") and _followed_ship() != null,
			text = func() -> String:
				var ship := _followed_ship()
				var line := BirdBoosts.describe(GameState.bird_boosts(ship)) if ship != null else ""
				return "Birds have taken to %s. Gulls, terns, pelicans, albatrosses: every species that follows a ship gives it a little of its own. Terns are quick, pelicans save fuel and wear, frigatebirds and shearwaters shelter a ship from a storm, and an albatross is the prize.\n\n%sThe ship's popup lists its followers; zoom in and you'll see them wheeling astern." % [ship.name if ship != null else "one of your ships", ("Right now that's " + line + ". ") if not line.is_empty() else ""]},
		{id = "birds_sound", who = "dick", title = "Listen to the birds",
			show = func() -> bool: return seen.call("birds_follow"),
			text = func() -> String: return "Zoom in close and the world speaks up: the sea, the wind, the ships' horns, and the birds. When one calls, the panel at the top left of the map names it and shows you the very bird.\n\nEvery port has its own birds through the year, and the field guide (the paw button) keeps the ones you've met. Keep an eye out for an albatross on the Southern Ocean: a ship it follows wants for nothing."},
		{id = "nests", who = "joe", title = "Should I shoo them?",
			show = func() -> bool: return seen.call("birds_follow") and _flocked_ship() != null,
			text = func() -> String: return "A whole flock is riding on %s now: more than one species, nesting in the rigging and roosting on the hatches. Some skippers would clear them off. Don't: every species aboard adds its boost to the ship, up to a cap, and a flock that's settled stays with the ship port to port.\n\nThe only birds that cost you anything are frigatebirds in a Divine Actions game, and even they shelter the ship from storms." % _flocked_ship().name},
		{id = "fishing", who = "joe", title = "Fishing and crabbing",
			show = func() -> bool: return seen.call("trading") and GameState.company.has_type("seafood"),
			text = func() -> String: return "The Shop's Seafood tab has fishing and crabbing boats: a Sport Fisher 24 that trolls for salmon, tuna and the odd giant marlin, and a Crab Skiff 24 that sets pots for Dungeness and blue crab. Base one at any port in its popup and it works the grounds near there, out for a few days at a time, and sells its catch when it comes home.\n\nLeave its Target on 'Most timely and profitable' and it picks what's in season each trip. Later come 60-footers that run nets, Bering Sea crabbers that stay out all winter for king crab, and Reefers to carry the catch to Tokyo and Seattle, where it fetches most."},
		{id = "finance", who = "marissa", title = "Your first payday",
			show = func() -> bool: return seen.call("upkeep") and GameState.wage_period >= 1,
			text = func() -> String: return "Marissa here, from head office. Every two weeks the crews are paid: a captain and some hands on every ship that worked. It's in the Activity list each payday, and the Finances tab adds it up with the fuel, the repairs, the port fees and the tolls.\n\nWatch the profit per ship there, not just the sales: a ship that sails empty half the time is the one to re-route."},
		{id = "company_type", who = "dick", title = "Time to branch out",
			show = func() -> bool: return seen.call("map") and GameState.company_types_available() > 0,
			done = func() -> bool: return GameState.company_types_available() <= 0,
			text = func() -> String: return "We've grown enough to go into a second trade. Press Choose a company type at the top right of the map (or on a locked tab in the Shop) and pick one: its smallest ships open straight away and the bigger ones follow as we level up.\n\nIt's for good, so look at what each carries and which ports near our hubs trade it. Another choice comes every %d levels." % Progression.type_pick_every()},
		{id = "farms", who = "sonny", title = "Our own farms",
			show = func() -> bool: return seen.call("trading") and Farms.can_farm(GameState.company) and GameState.company.level() >= 3,
			done = func() -> bool: return not GameState.farms.owned_by(GameState.company).is_empty(),
			text = func() -> String: return "The Farms tab, down at the bottom: the world's farm ports, each with a few plots of land for sale. Buy one, plant a crop that suits the climate (or graze a herd), and the harvest comes in by the season to our farm store at that port, where our own ships load it free.

Grain carriers take the dry crops, Fresh produce carriers the fruit and vegetables (they lose a little value every day, so don't let them sit), livestock carriers the young stock. Watch the almanac: a drought or a frost can take most of a year's harvest."},
		{id = "cruise_plan", who = "dick", title = "Plan a cruise",
			show = func() -> bool: return seen.call("map") and GameState.fleet().any(func(ship: Ship) -> bool: return ship.is_cruise() and ship.route.size() < 2),
			done = func() -> bool: return not GameState.fleet().any(func(ship: Ship) -> bool: return ship.is_cruise() and ship.route.size() < 2),
			text = func() -> String: return "A cruise ship sails round trips. Click it and press Assign Route: its first port is its home port, where guests board (our HQ, a hub, or a port with our cruise terminal), and the rest are its ports of call. Ports near wonders, and for Expedition ships the polar ports, make the best cruises.\n\nIts popup's Cruise planner shows everything: how appealing the itinerary is, the recommended prices and why, and how bookings are going."},
		{id = "cruise_prices", who = "marissa", title = "Tickets and reviews",
			show = func() -> bool: return seen.call("cruise_plan") and GameState.fleet().any(func(ship: Ship) -> bool: return ship.is_cruise() and not ship.cruise.get("history", []).is_empty()),
			text = func() -> String: return "Our first cruise is back. Guests book in the home port till the ship sails (the Departures tab sets when), and price decides how many come: at the recommended price about nine in ten berths fill, half again over it about a third.\n\nEvery voyage gets a review, and the reviews, the itineraries, the guest experience and how smoothly things go make our Cruises rating: more stars, and guests will pay more."},
		{id = "achievements", who = "marissa", title = "A milestone",
			show = func() -> bool: return seen.call("map") and Achievements.score(GameState.company).x > 0,
			text = func() -> String: return "You've earned your first achievement star. The trophy button at the top right of the map keeps them all: stars for cargo delivered of each kind, for the fleet, the company level, the bank, the field guide, and badges for the rest.\n\nThey're the big milestones. Each one takes real work, so keep at it; the next is always listed with how far along we are."},
	]


## A cargo ship of the fleet with birds following it (the first), or null.
func _followed_ship() -> Ship:
	for ship in _cargo_ships():
		if not GameState.bird_boosts(ship).is_empty():
			return ship
	return null


## A cargo ship with two species or more following it, or null.
func _flocked_ship() -> Ship:
	for ship in _cargo_ships():
		if BirdLife.shared().following(ship).size() >= 2:
			return ship
	return null


func _cargo_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for ship in GameState.fleet():
		if not ship.is_service():
			out.append(ship)
	return out


func _fishing_boats() -> Array[Ship]:
	var out: Array[Ship] = []
	for ship in GameState.fleet():
		if ship.is_fishing():
			out.append(ship)
	return out


## What the company does, by the type it started as (the welcome's first lines).
static func _type_welcome() -> String:
	match GameState.company.start_type():
		"cargo":
			return "We're in Cargo & Ore: container ships with toys, clothing and furniture, and bulk carriers with iron ore, coal and gold. Buy ships, give them routes between ports, and they'll buy cargo where it's cheap and sell it where it's expensive."
		"vehicles":
			return "We're in Vehicles: car carriers taking cars, trucks and boats from the factories to the showrooms. Buy ships, give them routes between ports, and they'll buy vehicles where they're cheap and sell them where they're dear."
		"agriculture":
			return "We're in Agriculture: farms at the world's farm ports, grain carriers with grain, coffee, cocoa, sugar and spices, Fresh produce carriers with fruit and vegetables, and livestock carriers with cattle, sheep, pigs and horses. Buy ships, give them routes between ports, and they'll buy where the harvest is cheap and sell where it's wanted."
		"tankers":
			return "We're in Tankers: oil and gas. Buy tankers, give them routes between ports, and they'll fill up where oil is cheap and sell it where it's dear."
		"seafood":
			return "We're in Seafood: fishing and crabbing boats that work the grounds near their port and sell the catch, and fish tenders and reefers that carry seafood between ports."
		"cruises":
			return "We're in Cruises: ships full of guests on round trips from our home port. You set where they call, what the cabins and decks hold, and what tickets cost, and the guests decide whether it was worth it."
	return "Buy ships, give them routes between ports, and they'll buy cargo where it's cheap and sell it where it's expensive."


## Which ship to buy first: the company's first type's smallest ships.
static func _first_ship_advice() -> String:
	if GameState.company.start_type() == "seafood":
		return "A Sport Fisher 24 or a Crab Skiff 24 is the cheapest way in: base it at a port and it fishes on its own. A Fish Tender 40 trades seafood between ports like any cargo ship."
	var names := PackedStringArray()
	for model: Dictionary in GameData.ship_models:
		if Progression.type_of_model(model) == GameState.company.start_type() and int(model.get("tier", 1)) == 1:
			names.append(str(model.name))
	if names.is_empty():
		return "The cheapest is a good place to start."
	return "The %s %s cheap and a good place to start." % [" or the ".join(names), "is" if names.size() == 1 else "are each"]


func _any_route_assigned() -> bool:
	return GameState.fleet().any(func(ship: Ship) -> bool: return ship.has_route() or not ship.pending_route.is_empty())


func _has_sold() -> bool:
	return GameState.fleet().any(func(ship: Ship) -> bool: return float(ship.ledger.get("income", 0.0)) > 0.0)


func _route_screen_open() -> bool:
	var root := GameRoot.find(self)
	return root != null and root.is_route_screen_open()


## The lowest company level a recovery boat unlocks at.
static func _first_recovery_level() -> int:
	var level := 999
	for model: Dictionary in GameData.ship_models:
		if model.get("recovery", false):
			level = mini(level, int(model.get("unlock_level", 1)))
	return level


## The lowest company level an icebreaker unlocks at.
static func _first_icebreaker_level() -> int:
	var level := 999
	for model: Dictionary in GameData.ship_models:
		if not str(model.get("icebreaker", "")).is_empty():
			level = mini(level, int(model.get("unlock_level", 1)))
	return level

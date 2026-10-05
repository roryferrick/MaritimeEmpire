class_name TutorialCard
extends PanelContainer
## The tutorial: tips on the basics, one at a time, in a card in the bottom left
## of the main screens (over the Route Assignment map too). Only in saves
## started with the tutorial (GameState.tutorials), and only while the map's
## Tutorial switch is on (GameState.tutorials_on).
##
## Each tip (see _tips()) shows once its moment comes, the first not yet seen in
## list order, and goes for good (GameState.tutorial_done) when the player
## clicks Got it or does what it asks.

const CHECK_SECONDS := 0.25
const WIDTH := 460.0
const MARGIN := 12.0

var _title := Label.new()
var _body := Label.new()
var _button := Button.new()
var _tips: Array[Dictionary] = []
var _tip := {}  # The tip showing, or {}.
var _clock := CHECK_SECONDS


func _ready() -> void:
	theme_type_variation = &"MapPopup"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 8)
	add_child(box)
	var kicker := Label.new()
	kicker.text = "TUTORIAL"
	kicker.theme_type_variation = &"DimLabel"
	box.add_child(kicker)
	_title.theme_type_variation = &"HeaderLabel"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_title)
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


func _finish() -> void:
	if _tip.is_empty():
		return
	if not GameState.tutorial_done.has(_tip.id):
		GameState.tutorial_done.append(_tip.id)
	_tip = {}
	_clock = CHECK_SECONDS  # Show the next one straight away.


## The tips, in order: {id, title, text (a Callable, so names and numbers are
## current), show (when its moment has come), and optionally done (it's
## finished without Got it once this is true)}.
func _tips_list() -> Array[Dictionary]:
	var seen := func(id: String) -> bool: return GameState.tutorial_done.has(id)
	var always := func() -> bool: return true
	var first_model: Dictionary = GameData.ship_models[0] if not GameData.ship_models.is_empty() else {}
	var breakdown_level := int(GameData.config.get("breakdowns", {}).get("min_company_level", 6))
	return [
		{id = "welcome", title = "Welcome to %s" % GameState.company_name, show = always,
			text = func() -> String: return "You run a shipping company. Buy ships, give them routes between ports, and they'll buy cargo where it's cheap and sell it where it's dear.\n\nYour headquarters is %s: the port with a ring in your color. Tips like this one come up as you play; switch them off any time with the Tutorial switch in the top right of the map." % GameData.port_name(GameState.home_port)},
		{id = "map", title = "Getting around", show = func() -> bool: return seen.call("welcome"),
			text = func() -> String: return "Drag the map to move it and scroll to zoom. Click a port to see its prices, or a ship to see what it's doing.\n\nThe buttons at the top right of the screen set the game speed: pause, or speed up to 8x (F steps through them)."},
		# Shown over the Route Assignment map, so it comes before the tip that opens it.
		{id = "route_screen", title = "Planning a route",
			show = func() -> bool: return seen.call("map") and _route_screen_open(),
			done = _any_route_assigned,
			text = func() -> String: return "Click ports in the order to visit them; the ship loops round them. Gray ports are out of range.\n\nGreen under a leg is the cargo and about what it makes; red means it sails empty. Two or three ports with green both ways make a good first loop. Then press Accept."},
		{id = "buy_ship", title = "Buy your first ship",
			show = func() -> bool: return seen.call("map") and _cargo_ships().is_empty(),
			done = func() -> bool: return not _cargo_ships().is_empty(),
			text = func() -> String: return "Open the Shop tab at the bottom of the screen and buy a ship. The %s is cheap and a good place to start. You'll give it a name, and it's launched at %s." % [
				first_model.get("name", "first ship"), GameData.port_name(GameState.home_port)]},
		{id = "assign_route", title = "Give it a route",
			show = func() -> bool: return seen.call("map") and not _cargo_ships().is_empty() and not _any_route_assigned(),
			done = _any_route_assigned,
			text = func() -> String: return "A new ship waits in port until it has a route. Click it on the map (or in the Ships tab) and press Assign Route."},
		{id = "trading", title = "Trading runs itself",
			show = func() -> bool: return _any_route_assigned() and not _route_screen_open(),
			text = func() -> String: return "At each stop your ship sells its cargo, then buys the most profitable cargo it can carry to the next port, refuels and repairs, and sets off again.\n\nEvery sale shows up in the Activity list on the left, and your money is at the top left."},
		{id = "upkeep", title = "Fuel and wear",
			show = func() -> bool: return seen.call("trading") and _has_sold(),
			text = func() -> String: return "Ships burn fuel and wear down at sea, and the more worn they are, the slower they go. The Refuel and Repair switches in a ship's popup top them up at every stop.\n\nA ship that can't make its next leg waits in port, and the Ships tab gets a red dot whenever a ship needs you; hover it to see why."},
		{id = "prices", title = "Finding better trades", show = func() -> bool: return seen.call("upkeep"),
			text = func() -> String: return "The Prices picker in the top right of the map colors every port by a commodity's price: green where it's cheap to buy, red where it sells high.\n\nThe Markets tab lists the best trades, anywhere and close by, and a port's popup shows all its prices."},
		{id = "grow", title = "Grow your fleet", show = func() -> bool: return seen.call("prices"),
			text = func() -> String: return "More ships, more profit. The Shop tab gets a red dot when you can afford another. Give each one its own route, or send several round a good loop.\n\nThe Finances tab shows where your money comes from and where it goes, and which ships earn the most."},
		{id = "levels", title = "Company levels",
			show = func() -> bool: return seen.call("map") and GameState.company_level() >= 2,
			text = func() -> String: return "Every delivery earns your company XP. New levels unlock bigger ships and let you own more of each.\n\nClick your level at the top left to see what's coming next."},
		{id = "ship_upgrades", title = "Ship upgrades",
			show = func() -> bool: return seen.call("map") and _cargo_ships().any(func(ship: Ship) -> bool: return ship.skill_points() > 0),
			text = func() -> String: return "Ships level up from their own deliveries, and each level gives an upgrade point. Spend them on speed, durability or gas efficiency with Upgrades in the ship's popup, or Upgrade all in the Ships tab. Each upgrade costs money too."},
		{id = "hubs", title = "Hubs",
			show = func() -> bool: return seen.call("map") and GameState.hubs_available() > 0,
			text = func() -> String: return "You can found a hub. Click a port and open its Hub tab to build one there.\n\nHubs level up from deliveries unloaded at them, their upgrades help every ship that docks, and new ships can launch from them. A hub is permanent, so pick a busy port on your routes."},
		{id = "breakdowns", title = "Breakdowns",
			show = func() -> bool: return seen.call("map") and GameState.company_level() >= breakdown_level,
			text = func() -> String: return "From now on ships can break down at sea, more often the more worn they are, so keep Repair on.\n\nA ship that breaks down completely or runs out of fuel is lost at sea until a recovery boat carries it to port. Recovery boats are in the Shop, from company level %d." % _first_recovery_level()},
		{id = "storms", title = "Storms",
			show = func() -> bool: return seen.call("map") and GameState.weather.active() and not GameState.weather.storms.is_empty(),
			text = func() -> String: return "Storms now affect your ships. They form in their real seasons (hurricanes and typhoons in late summer, gales in winter), drift across the sea and fade.\n\nShips sail through them slower and wearing faster, and the strongest hurricane cores close ports while they pass; ships wait them out. The activity log warns you when one heads for your ports."},
		{id = "seasons", title = "Seasonal closures",
			show = func() -> bool: return seen.call("map") and GameState.seasonal.active(),
			text = func() -> String: return "From now on the seasons close some places, on their real dates: the Great Lakes locks and ports in winter, Antarctica outside its summer, and icebound ports like Nain and Magadan. Ice in the Gulf of Finland slows ships instead.\n\nShips won't start a leg they can't finish before a closure; they wait in port until it reopens. The activity log warns you 10 days ahead, and a port's popup and the route screen show its dates."},
		{id = "icebreakers", title = "Icebreakers",
			show = func() -> bool: return seen.call("seasons") and GameState.company_level() >= _first_icebreaker_level(),
			text = func() -> String: return "Icebreakers are in the Shop now. You only need one if your ships trade where winter ice closes ports: the Great Lakes, the Sea of Okhotsk, or the Gulf of Finland, where the ice just slows ships.\n\nBuy one, then pick its Station in its popup. While the ice is in, it leads your ships through in small convoys (or keeps the Gulf of Finland's fairways open). The rest of the year it just waits."},
		{id = "lost", title = "Lost at sea",
			show = func() -> bool: return GameState.ships.any(func(ship: Ship) -> bool: return ship.is_lost()),
			text = func() -> String: return "A ship is lost at sea. A recovery boat can carry it to the nearer end of its leg: press Send Recovery in the lost ship's popup. With its Rescue switch on (it is by default), one is sent automatically.\n\nNo recovery boat yet? Buy one in the Shop when it unlocks."},
	]


func _cargo_ships() -> Array[Ship]:
	var out: Array[Ship] = []
	for ship in GameState.ships:
		if not ship.is_service():
			out.append(ship)
	return out


func _any_route_assigned() -> bool:
	return GameState.ships.any(func(ship: Ship) -> bool: return ship.has_route() or not ship.pending_route.is_empty())


func _has_sold() -> bool:
	return GameState.ships.any(func(ship: Ship) -> bool: return float(ship.ledger.get("income", 0.0)) > 0.0)


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

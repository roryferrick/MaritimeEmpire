# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name GameRoot
extends Control
## Root of an active game: top bar, activity log, the main screens (World,
## Ships, Finances, Shop) with the bottom nav, the pages over the map
## (Markets, Hubs, Farms, Makers, Energy: see open_page()), the full-screen Route
## Assignment screen, and the Esc menu; Space pauses and T opens the chat.

enum Screen { WORLD, SHIPS, MARKETS, FINANCES, HUBS, SHOP, FARMS, MAKERS, ENERGY, INDUSTRY, RESEARCH, CONTRACTS, PEOPLE, OWNERSHIP }

const GROUP := &"game_root"
## How often to check whether any ship needs the player.
const ALERT_CHECK_SECONDS := 2.0  # (A look over every ship and model: a few ms.)
## Ships named per reason in the Ships tab's tooltip before "and 3 more".
const ALERT_NAMES_SHOWN := 3
## The pages over the map (MapPage), opened by the buttons down its top left
## (WorldScreen.page_buttons): page id -> its Screen.
const PAGE_SCREENS := {markets = Screen.MARKETS, contracts = Screen.CONTRACTS, people = Screen.PEOPLE, ownership = Screen.OWNERSHIP, hubs = Screen.HUBS, farms = Screen.FARMS, makers = Screen.MAKERS, energy = Screen.ENERGY, industry = Screen.INDUSTRY, research = Screen.RESEARCH}

var _current_screen := Screen.WORLD

@onready var _screens := {
	Screen.WORLD: %WorldScreen,
	Screen.SHIPS: %ShipsScreen,
	Screen.FINANCES: %FinancesScreen,
	Screen.SHOP: %ShopScreen,
}
@onready var _nav_buttons := {
	Screen.WORLD: %WorldButton,
	Screen.SHIPS: %ShipsButton,
	Screen.FINANCES: %FinancesButton,
	Screen.SHOP: %ShopButton,
}
@onready var _popup_host: PopupHost = %PopupHost
## The pages' screens, kept (hidden, with the main screens) while their page
## is shut, so they keep their state: page id -> Control. The Farms and Makers
## screens are made here (shown for Agriculture and Vehicles companies).
@onready var _pages := {markets = %MarketsScreen, hubs = %HubsScreen}
var _farms_screen := FarmsScreen.new()
var _makers_screen := MakersScreen.new()
var _energy_screen := EnergyScreen.new()
var _industry_screen := IndustryScreen.new()
var _research_screen := ResearchScreen.new()
var _contracts_screen := ContractsScreen.new()
var _people_screen := PeopleScreen.new()
var _ownership_screen := OwnershipScreen.new()
## The page open over the map, or null.
var _page: MapPage = null
## Where the pages' screens are kept while shut (with the main screens).
var _page_home: Node = null

## Shown on the Ships tab while any ship needs the player (see
## Ship.attention_reason()), and on the Shop tab while any ship can be bought.
## The cards for the big moments (achievements, ratings), over everything.
var event_card := EventCard.new()
var _ships_alert := AlertDot.new()
var _shop_alert := AlertDot.new()
var _alert_clock := 0.0
## The Esc menu while it's open.
var _escape_menu: EscapeMenu = null


static func find(from: Node) -> GameRoot:
	return from.get_tree().get_first_node_in_group(GROUP) as GameRoot


func _ready() -> void:
	add_to_group(GROUP)
	for each: Control in [_farms_screen, _makers_screen, _energy_screen, _industry_screen, _research_screen, _contracts_screen, _people_screen, _ownership_screen]:
		each.name = {_farms_screen: "FarmsScreen", _makers_screen: "MakersScreen", _industry_screen: "IndustryScreen", _research_screen: "ResearchScreen", _contracts_screen: "ContractsScreen", _people_screen: "PeopleScreen", _ownership_screen: "OwnershipScreen"}.get(each, "EnergyScreen")
		each.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		%MarketsScreen.add_sibling(each)
	_pages.farms = _farms_screen
	_pages.makers = _makers_screen
	_pages.energy = _energy_screen
	_pages.industry = _industry_screen
	_pages.research = _research_screen
	_pages.contracts = _contracts_screen
	_pages.people = _people_screen
	_pages.ownership = _ownership_screen
	_page_home = %MarketsScreen.get_parent()
	for id: String in _pages:
		(_pages[id] as Control).visible = false
	var group := ButtonGroup.new()
	for screen: Screen in _nav_buttons:
		var button: Button = _nav_buttons[screen]
		button.theme_type_variation = &"PageButton"  # (In the headings' font: see ui/theme.tres.)
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(show_screen.bind(screen))
	%RouteScreen.finished.connect(_close_route_screen)
	GameState.cargo_sold.connect(_on_cargo_sold)
	GameState.cargo_loaded.connect(_on_cargo_loaded)
	GameState.catch_landed.connect(_on_catch_landed)
	GameState.trophy_caught.connect(_on_trophy_caught)
	GameState.canal_entered.connect(_on_canal_entered)
	GameState.ship_held.connect(_on_ship_held)
	GameState.ship_broke_down.connect(_on_ship_broke_down)
	GameState.ship_battered.connect(_on_ship_battered)
	GameState.wages_paid.connect(_on_wages_paid)
	GameState.ship_lost.connect(_on_ship_lost)
	GameState.ship_recovered.connect(_on_ship_recovered)
	GameState.tugs_handed.connect(_on_tugs_handed)
	GameState.recovery_sent.connect(_on_recovery_sent)
	GameState.ship_at_risk.connect(_on_ship_at_risk)
	GameState.ship_sold.connect(_on_ship_sold)
	GameState.rating_changed.connect(_on_rating_changed)
	%ShipsButton.add_child(_ships_alert)
	%ShopButton.add_child(_shop_alert)
	GameState.hub_built.connect(_on_hub_built)
	GameState.port_band_changed.connect(_on_port_band_changed)
	GameState.research_discovered.connect(_on_research_discovered)
	GameState.research_mishap.connect(func(ship: Ship, what: String) -> void:
		if GameState.is_mine(ship):
			ActivityLog.add("%s %s at %s." % [ship.name, what, Research.target_name(ship.research_target)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship)))
	GameState.research.contract_finished.connect(_on_contract_finished)
	GameState.research.revealed.connect(func(who: Company, site_ids: Array) -> void:
		if who == GameState.company and not site_ids.is_empty():
			ActivityLog.add("New research site%s found nearby: %s. Look for %s on the map." % ["s" if site_ids.size() > 1 else "", ", ".join(PackedStringArray(site_ids.map(func(id: String) -> String: return str(Research.site(id).get("name", id))))), "them" if site_ids.size() > 1 else "it"], ActivityLog.Kind.GOOD))
	_alert_phase = 0  # (Worked out over the next frames: see _process().)
	Net.left.connect(_on_left_game)
	if not Net.host_error.is_empty():
		_tell(Net.host_error, "Couldn't host this game")
		Net.host_error = ""
	if GameState.tutorials:
		# Over the screens (and the Route Assignment map) but under the popups.
		var tutorial := TutorialCard.new()
		_popup_host.add_sibling(tutorial)
		_popup_host.get_parent().move_child(tutorial, _popup_host.get_index())
	# Over the popups and the tutorial: the last of the siblings.
	_popup_host.get_parent().add_child(event_card)
	add_child(HoverCards.new())  # (The nested hover cards, over everything: see HoverCards.)
	GameState.contracts.offer_arrived.connect(func(offer: Dictionary) -> void: event_card.show_offer(offer))  # (An important offer: the card, pausing.)
	GameState.contracts.tender_closed.connect(func(offer: Dictionary, won: bool, winner: String, rate: float) -> void: event_card.show_tender_result(offer, won, winner, rate))
	GameState.contracts.contract_event.connect(func(contract: Dictionary, kind: String, info: Dictionary) -> void: event_card.show_contract_event(contract, kind, info))
	GameState.people.succession_needed.connect(func(company: Company, why: String) -> void:
		if company == GameState.company:
			event_card.show_succession(company, why))
	GameState.technology.offered.connect(func(company: Company, tech_id: String, how: String) -> void:
		if company == GameState.company:
			event_card.show_tech_offer(tech_id, how))
	GameState.technology.developed.connect(func(company: Company, tech_id: String, exclusive: bool) -> void:
		if company == GameState.company:
			event_card.show_tech_developed(tech_id, exclusive))
	GameState.ownership.firm_order_wanted.connect(func(company: Company, proposal: Dictionary) -> void:
		if company == GameState.company:
			event_card.show_firm_order(proposal))
	GameState.shipyards.delivered.connect(func(company: Company, ship: Ship, order: Dictionary) -> void:
		if company == GameState.company:
			event_card.show_delivery(ship, order))
	GameState.firm_life.bankrupt.connect(func(firm_index: int, listings: int) -> void: event_card.show_bankruptcy(firm_index, listings))
	GameState.firm_life.merger_stake.connect(func(company: Company, buyer: int, target: int, price: float, stake: float) -> void:
		if company == GameState.company:
			event_card.show_merger(buyer, target, price, stake))
	GameState.people.notice_given.connect(func(company: Company, kind: String, key: String, person: Dictionary) -> void:
		if company == GameState.company:
			event_card.show_notice(kind, key, person))
	GameState.people.poach_offer.connect(func(company: Company, kind: String, key: String, person: Dictionary, firm_index: int, offer: int) -> void:
		if company == GameState.company:
			event_card.show_poach(kind, key, person, firm_index, offer))
	GameState.people.divert_wanted.connect(func(company: Company, offer: Dictionary, ship: Ship, head_key: String, pay_day: float, route_day: float) -> void:
		if company == GameState.company:
			event_card.show_divert(offer, ship, head_key, pay_day, route_day))
	GameState.people.captain_resigned.connect(func(company: Company, ship: Ship, name: String) -> void:
		if company == GameState.company:
			event_card.show_resignation(ship, name))
	GameState.ownership.vote_result.connect(func(company: Company, motion: Dictionary, passed: bool, yes: float, total: float) -> void:
		if company == GameState.company and yes < total:
			event_card.show_vote(motion, passed, yes, total))
	GameState.ownership.coup.connect(func(company: Company) -> void:
		if company == GameState.company:
			event_card.show_coup(company))
	GameState.ownership.ipo_event.connect(func(company: Company, kind: String, info: Dictionary) -> void:
		if company == GameState.company:
			event_card.show_ipo(kind, info))
	GameState.ownership.quarterly.connect(func(company: Company, report: Dictionary) -> void:
		if company == GameState.company:
			event_card.show_quarterly(report))
	show_screen(Screen.WORLD)


func _process(delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(delta)
	MapView._prof("proc.game", t_x)

func _process_timed(delta: float) -> void:
	_alert_clock += delta
	if _alert_clock >= ALERT_CHECK_SECONDS:
		_alert_clock = 0.0
		_alert_phase = 0
	if _alert_phase < 2:  # (One part a frame: each is a look over the models or the fleet.)
		_update_alerts(_alert_phase)
		_alert_phase += 1


## Red dots on the Ships tab if any ship needs the player (the tooltip says
## why), and on the Shop tab if anything can be bought.
var _alert_phase := 2
func _update_alerts(phase: int) -> void:
	if phase == 0:
		_update_shop_alert()
	else:
		_update_ships_alert()

func _update_shop_alert() -> void:
	var t_a := Time.get_ticks_usec()
	var buyable := PackedStringArray()
	for model: Dictionary in GameData.ship_models:
		if GameState.buy_error(model.id).is_empty():
			buyable.append(model.get("name", model.id))
	_shop_alert.visible = not buyable.is_empty()
	%ShopButton.tooltip_text = "You can buy: %s" % ", ".join(buyable) if not buyable.is_empty() else ""
	MapView._prof("alerts.shop", t_a)

func _update_ships_alert() -> void:
	var t_a := Time.get_ticks_usec()
	var reasons := {}  # reason -> names of the ships it applies to
	for ship in GameState.fleet():
		var reason := ship.attention_reason()
		if not reason.is_empty():
			if not reasons.has(reason):
				reasons[reason] = PackedStringArray()
			reasons[reason].append(ship.name)
	_ships_alert.visible = not reasons.is_empty()
	MapView._prof("alerts.ships", t_a)
	var parts := PackedStringArray()
	for reason: String in reasons:
		var names: PackedStringArray = reasons[reason]
		var named := ", ".join(names.slice(0, ALERT_NAMES_SHOWN))
		if names.size() > ALERT_NAMES_SHOWN:
			named += " and %d more" % (names.size() - ALERT_NAMES_SHOWN)
		parts.append("%d %s (%s)" % [names.size(), reason, named])
	%ShipsButton.tooltip_text = "Ships needing you: %s" % ", ".join(parts) if not reasons.is_empty() else ""


## Opens a page over the World map (Markets, Hubs, Farms or Makers, by id:
## see PAGE_SCREENS), shutting any other first; its screen goes into the
## page and comes back out, hidden, when it's shut.
func open_page(id: String) -> void:
	if not _pages.has(id):
		return
	show_screen(Screen.WORLD)  # (Shuts any page open.)
	var screen: Control = _pages[id]
	_page = MapPage.new(screen)
	_page.closed.connect(func(back: Control) -> void:
		back.visible = false
		back.reparent(_page_home, false)
		back.size_flags_horizontal = Control.SIZE_FILL
		back.size_flags_vertical = Control.SIZE_FILL
		back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_page = null)
	%WorldScreen.add_child(_page)


## Shuts the page open over the map, if one is.
func close_page() -> void:
	if is_instance_valid(_page):
		_page.close()


## Opens the Farms page at a farm port (the port popup's Farms button).
func show_farm(port_id: String) -> void:
	_farms_screen.show_port(port_id)
	open_page("farms")


## Shuts any page and turns the World map to a place (lon, lat).
func show_on_map(lon_lat: Vector2) -> void:
	show_screen(Screen.WORLD)
	%WorldScreen.look_at_lon_lat(lon_lat)


## Opens the Research page at one of this player's research ships (the ship popup's Expeditions button).
func show_research_ship(ship_id: int) -> void:
	_research_screen.show_ship(ship_id)
	open_page("research")


## Opens the Research page at a site's card (the map's site markers).
func show_research_site(site_id: String) -> void:
	_research_screen.show_site(site_id)
	open_page("research")


## Opens the Energy page at a port's buildings or a field (the port popup's
## Energy button, the map's rigs).
func show_energy(place: String) -> void:
	_energy_screen.show_place(place)
	open_page("energy")


## Opens the Industry page at a building (the port popup's Industry button).
func show_industry(building_id: String) -> void:
	_industry_screen.show_building(building_id)
	open_page("industry")


## Opens the Makers page at a maker (the port popup's Makers button).
func show_maker(maker_id: String) -> void:
	_makers_screen.show_maker(maker_id)
	open_page("makers")


## Switches to the World map, centered on a port.
func show_port_on_map(port_id: String) -> void:
	show_screen(Screen.WORLD)
	(%WorldScreen.find_child("MapView") as MapView).focus_port(port_id)


## Opens the Ownership page (the shares, the board, the firms, the IPO).
func show_ownership() -> void:
	open_page("ownership")


## Opens the People page (executives, heads, officers and the job market).
func show_people() -> void:
	open_page("people")


## Opens the Contracts page (the offers, the signed contracts, the standing).
func show_contracts() -> void:
	open_page("contracts")


## Opens the newspaper over the map (Gazette), at the latest issue or a week's.
func open_gazette(week := -1) -> void:
	show_screen(Screen.WORLD)
	var paper := Gazette.new()
	paper.week = week
	var page := MapPage.new(paper)
	page.closed.connect(func(back: Control) -> void: back.queue_free())
	%WorldScreen.add_child(page)

## Switches to the World map, centered on an inland city.
func show_city_on_map(city_id: String) -> void:
	show_screen(Screen.WORLD)
	(%WorldScreen.find_child("MapView") as MapView).focus_city(city_id)


## Opens the Intelligence page (the Markets page's place) at a tab: "countries", "companies", "markets", "charts" or "news".
func show_intelligence(tab := "") -> void:
	(_pages.markets as IntelligenceScreen).show_tab(tab)
	open_page("markets")


## Switches to the World map, centered on a ship, with its popup open.
func show_ship_on_map(ship: Ship) -> void:
	show_screen(Screen.WORLD)
	var map: MapView = %WorldScreen.find_child("MapView")
	map.follow_ship(ship)
	%WorldScreen.open_ship_popup(ship)


## True once the World map is warm (see MapView.is_warm()) and a new game's
## world has run up to its start (GameState.warm_up_left); the loading screen waits for it.
func is_warm() -> bool:
	return GameState.warm_up_left <= 0 and (%WorldScreen.find_child("MapView") as MapView).is_warm()

## The ship the World map is following (see MapView.follow_ship()), or null.
func followed_ship() -> Ship:
	return (%WorldScreen.find_child("MapView") as MapView).followed


func show_screen(screen: Screen) -> void:
	for id: String in PAGE_SCREENS:
		if PAGE_SCREENS[id] == screen:
			open_page(id)  # (A page over the map, not a screen of its own.)
			return
	close_page()
	_current_screen = screen
	_popup_host.close()
	for s: Screen in _screens:
		_screens[s].visible = s == screen
	_nav_buttons[screen].button_pressed = true


## Full screen, with no top bar, nav or activity log. Returns to the current screen when done.
func open_route_screen(ship: Ship) -> void:
	_popup_host.close()
	for s: Screen in _screens:
		_screens[s].visible = false
	%TopBar.visible = false
	%BottomNav.visible = false
	%ActivityLogPanel.visible = false
	%RouteScreen.visible = true
	%RouteScreen.open(ship)


## The Fishing Grounds screen (FishingScreen), full screen like the Route
## Assignment one; made the first time it's opened.
var _fishing_screen: FishingScreen = null

func open_fishing_screen() -> void:
	_popup_host.close()
	if _fishing_screen == null:
		_fishing_screen = FishingScreen.new()
		_fishing_screen.visible = false
		%RouteScreen.add_sibling(_fishing_screen)
		_fishing_screen.finished.connect(_close_fishing_screen)
	for s: Screen in _screens:
		_screens[s].visible = false
	%TopBar.visible = false
	%BottomNav.visible = false
	%ActivityLogPanel.visible = false
	_fishing_screen.visible = true
	_fishing_screen.open()


func _close_fishing_screen() -> void:
	_fishing_screen.visible = false
	%TopBar.visible = true
	%BottomNav.visible = true
	%ActivityLogPanel.visible = true
	show_screen(_current_screen)


func is_route_screen_open() -> bool:
	return %RouteScreen.visible


func _close_route_screen() -> void:
	%RouteScreen.visible = false
	%TopBar.visible = true
	%BottomNav.visible = true
	%ActivityLogPanel.visible = true
	show_screen(_current_screen)


## "Sea Otter sold Toys at Rotterdam: +$2,300 profit (bought $1,200, sold $3,500)":
## the trade's profit after the canal tolls on the way; a loss is shown in red.
## A muted model's profitable sales are left out.
func _on_cargo_sold(ship: Ship, port_id: String, commodity_id: String, _quantity: int, cost: int, sale: int, tolls: int, fee: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	var profit := sale - cost - tolls - fee
	if profit >= 0 and GameState.muted_models.has(ship.model_id):
		return
	var text := "%s sold %s at %s: %s%s profit (bought %s, sold %s%s%s)" % [ship.name, GameData.commodity(commodity_id).get("name", commodity_id),
		GameData.port_name(port_id), "+" if profit >= 0 else "", Fmt.money(profit), Fmt.money(cost), Fmt.money(sale),
		", tolls %s" % Fmt.money(tolls) if tolls > 0 else "", ", port fee %s" % Fmt.money(fee) if fee > 0 else ""]
	ActivityLog.add(text, ActivityLog.Kind.INFO if profit >= 0 else ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


## "Pot Luck landed 6,000 crates of red king crab at Dutch Harbor: $28,800,000"
## (or "... put ... in the cold store at ...", for the company's carriers).
func _on_catch_landed(ship: Ship, port_id: String, species: String, crates: int, value: int, stored: bool) -> void:
	if not GameState.is_mine(ship) or GameState.muted_models.has(ship.model_id):
		return
	var what := Fisheries.shared().species_word(species)
	var text := "%s %s %s crates of %s %s %s: %s" % [ship.name, "put" if stored else "landed", Fmt.thousands(crates), what,
		"in the cold store at" if stored else "at", GameData.port_name(port_id), Fmt.money(value)]
	ActivityLog.add(text, ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


## "Reel Deal hooked a giant bluefin tuna: its hold's full, heading home".
func _on_trophy_caught(ship: Ship, species: String) -> void:
	if not GameState.is_mine(ship):
		return
	ActivityLog.add("%s hooked a giant %s: its hold's full, heading home" % [ship.name, Fisheries.shared().species_word(species)],
		ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


## "Sea Otter loaded 10 containers of Toys for Rotterdam ($1,200)".
func _on_cargo_loaded(ship: Ship, _port_id: String, commodity_id: String, quantity: int, cost: int, to_port: String) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	if GameState.muted_models.has(ship.model_id):
		return
	var commodity := GameData.commodity(commodity_id)
	ActivityLog.add("%s loaded %s %s of %s for %s (%s)" % [ship.name, Fmt.thousands(quantity), commodity.get("units", "units"),
		commodity.get("name", commodity_id), GameData.port_name(to_port), Fmt.money(cost)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


## "Ever Bright entered the Panama Canal: toll $4,200 (+50% profit on this delivery)";
## a convoy canal says the ship joined its convoy.
func _on_canal_entered(ship: Ship, canal: Dictionary, toll: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	if GameState.muted_models.has(ship.model_id):
		return
	var what := "joined the %s convoy" % canal.name if canal.get("type", "") == "convoy" else "entered the %s" % canal.name
	var parts := PackedStringArray()
	if toll > 0:
		parts.append("toll %s" % Fmt.money(toll))
	var bonus := roundi(float(canal.get("profit_bonus", 0.0)) * 100.0)
	if bonus > 0:
		parts.append("+%d%% profit on this delivery" % bonus)
	var text := "%s %s" % [ship.name, what]
	if not parts.is_empty():
		text += ": %s" % ", ".join(parts)
	ActivityLog.add(text, ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_ship_held(ship: Ship, reason: String) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s is held at %s: %s" % [ship.name, GameData.port_name(ship.docked_at), reason], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_wages_paid(ship: Ship, total: int, ship_count: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("Payday: %s in crew wages for %d ship%s%s" % [Fmt.money(total), ship_count, "" if ship_count == 1 else "s",
		" - you're in debt: your ships run on credit, but nothing can be bought until you're back above $0" if GameState.in_debt() else ""],
		ActivityLog.Kind.BAD if GameState.in_debt() else ActivityLog.Kind.INFO)


func _on_ship_battered(ship: Ship, storm: Dictionary) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s was battered at anchor off %s by %s: maintenance down to %d%%" % [ship.name, GameData.port_name(ship.docked_at),
		Weather.title(storm), floori(ship.maintenance * 100.0)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_broke_down(ship: Ship) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s broke down at sea! Maintenance now %d%%" % [ship.name, floori(ship.maintenance * 100.0)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_lost(ship: Ship) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s is lost at sea (%s)." % [ship.name, ship.lost_reason], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_recovered(ship: Ship, mammoth: Ship, port_id: String, to_destination: bool) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	var outcome := "" if to_destination else " (back where it came from, so no pay)"
	if mammoth.is_tug():
		ActivityLog.add("%s towed %s in to %s%s" % [mammoth.tug_crew_text(), ship.name, GameData.port_name(port_id), outcome], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))
		return
	ActivityLog.add("%s carried %s to %s%s" % [mammoth.name, ship.name, GameData.port_name(port_id), outcome], ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))


func _on_tugs_handed(ship: Ship, boat: Ship, port_id: String) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s brought %s within reach of %s's tugs" % [boat.name, ship.name, GameData.port_name(port_id)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_recovery_sent(ship: Ship, boat: Ship, cost: int, auto: bool) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	if auto:
		var sent := "%s sent" % boat.name
		if boat.is_tug():
			sent = "%s sent out from %s" % [boat.tug_crew_text(), GameData.port_name(boat.tow_port)]
		ActivityLog.add("Auto-recovery: %s for %s (about %s)" % [sent, ship.name, Fmt.money(cost)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


func _on_ship_at_risk(ship: Ship) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("%s won't make it to %s at this rate!" % [ship.name, GameData.port_name(ship.to_port)], ActivityLog.Kind.BAD, ActivityLog.ship_color(ship))


func _on_ship_sold(ship: Ship, price: int) -> void:
	if not GameState.is_mine(ship):
		return  # Another player's (see Net).
	ActivityLog.add("Sold %s for %s" % [ship.name, Fmt.money(price)], ActivityLog.Kind.INFO, ActivityLog.ship_color(ship))


## One of this player's company types reached a new whole star, or fell to one (Ratings).
func _on_rating_changed(who: Company, type_id: String, star: int, up: bool) -> void:
	if who != GameState.company:
		return
	var type_name := Progression.type_name(type_id)
	ActivityLog.add("%s %s to %d stars." % [type_name, "rose" if up else "fell", star], ActivityLog.Kind.GOOD if up else ActivityLog.Kind.BAD)
	event_card.show_rating(type_name, star, up)


func _on_hub_built(hub: Hub) -> void:
	if not GameState.hubs.has(hub):
		return  # Another player's.
	ActivityLog.add("Founded a hub at %s" % GameData.port_name(hub.port_id), ActivityLog.Kind.GOOD)


func _on_port_band_changed(port_id: String, band: String, grew: bool) -> void:
	ActivityLog.add("%s %s to %s" % [GameData.port_name(port_id), "grew" if grew else "shrank", band.capitalize()],
		ActivityLog.Kind.GOOD if grew else ActivityLog.Kind.INFO)


## Space pauses or carries on (see GameState.toggle_pause()) and T opens the
## chat (multiplayer), unless the player is typing or the Esc menu is open.
## Taken before the controls see them, so a focused button doesn't take Space.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if not key or not key.pressed or key.echo or is_instance_valid(_escape_menu):
		return
	# Esc with something on a tab focused (a list, a table, a picker), which
	# would take it for itself: the tab's popup closes, else the menu opens.
	if event.is_action_pressed(&"ui_cancel"):
		var focused := get_viewport().gui_get_focus_owner()
		var on_tab := focused != null and _current_screen != Screen.WORLD and (_screens[_current_screen] as Control).is_ancestor_of(focused)
		if on_tab:
			focused.release_focus()
			get_viewport().set_input_as_handled()
			if focused is LineEdit or focused is TextEdit:
				return  # (Typing: Esc just leaves the box.)
			if is_instance_valid(_popup_host.current):
				_popup_host.close()
			else:
				_escape_menu = EscapeMenu.new()
				add_child(_escape_menu)
			return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	match key.keycode:
		KEY_SPACE:
			GameState.toggle_pause()
			get_viewport().set_input_as_handled()
		KEY_T:
			if Net.is_online():
				%ActivityLogPanel.open_chat()
				get_viewport().set_input_as_handled()


## Esc opens the menu (see EscapeMenu), once nothing else wanted it: an open
## popup or the Route Assignment screen close first.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not is_instance_valid(_escape_menu):
		get_viewport().set_input_as_handled()
		_popup_host.close()
		_escape_menu = EscapeMenu.new()
		add_child(_escape_menu)


## Multiplayer: the host left (or the connection dropped): back to the title
## screen, saying why.
func _on_left_game(reason: String) -> void:
	_tell(reason, "Left the game", func() -> void: get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))


## A message box over the game; then() runs once it's closed.
func _tell(text: String, title: String, then := Callable()) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	add_child(dialog)
	if then.is_valid():
		dialog.confirmed.connect(then)
		dialog.canceled.connect(then)
	dialog.popup_centered()


## One of this player's research ships finished a site (see Research): the log and its card.
func _on_research_discovered(ship: Ship, site_id: String, first: bool, points: float) -> void:
	if not GameState.is_mine(ship):
		return
	var site := Research.site(site_id)
	ActivityLog.add("%s surveyed %s%s (+%s research points)." % [ship.name, site.get("name", site_id), ", the first company ever" if first else "", Fmt.thousands(roundi(points))],
		ActivityLog.Kind.GOOD, ActivityLog.ship_color(ship))
	event_card.show_discovery(site_id, first, ship.name, points)


## A contract of this player's done (paid) or failed (its penalty).
func _on_contract_finished(who: Company, offer: Dictionary, ok: bool, paid: int) -> void:
	if who != GameState.company:
		return
	if ok:
		ActivityLog.add("Contract done: %s for %s, %s." % [offer.get("title", ""), offer.get("client", ""), Fmt.money(paid)], ActivityLog.Kind.GOOD)
	else:
		ActivityLog.add("Contract failed: %s (%s penalty)." % [offer.get("title", ""), Fmt.money(paid)], ActivityLog.Kind.BAD)

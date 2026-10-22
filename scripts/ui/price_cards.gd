# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name PriceCards
## The hover cards behind a price (HoverCards; DESIGN_LIVING_WORLD.md M1, the
## nested tooltips): price() builds a good's card at a port, with lines that
## open their own cards: its market's days of cover and how the price follows
## them, what the zone holds, makes and uses (and who makes and uses it), the
## ships on their way with it, a year's sparkline, and what this company would
## get for it and why. Attach with PriceCards.attach(control, port_id, good).

const FONT_SIZE := 13
const TITLE_SIZE := 15
const WIDTH := 300.0
const VOYAGES_SHOWN := 6
const PLANTS_SHOWN := 5


static func attach(control: Control, port_id: String, good: String) -> void:
	HoverCards.attach(control, func() -> Control: return price(port_id, good))


static func price(port_id: String, good: String) -> Control:
	var world: WorldEconomy = GameState.world
	GameState.note_action("hovered_price")
	var box := _box()
	var name := str(GameData.commodity(good).get("name", good))
	var unit := str(GameData.commodity(good).get("unit", "unit"))
	box.add_child(_title("%s at %s" % [name, GameData.port_name(port_id)]))
	var sell := GameState.market.sell_price(port_id, good)
	var base := float(GameData.commodity(good).get("base", 1.0))
	box.add_child(_line("Sells for %s a %s here: x%s of its usual %s" % [Fmt.money(roundi(sell)), unit, Fmt.decimal(sell / maxf(base, 0.0001), 2), Fmt.money(roundi(base))]))
	var z := world.zone_of_port(port_id)
	var g := world.good_index(good)
	if z < 0 or g < 0:
		box.add_child(_dim("Outside the living world's markets: a fixed price."))
		return box
	var i := z * world.goods.size() + g
	var cover := world.cover(z, g)
	var cover_line := _line("%s market: %s of cover ▸" % [world.zone_label(z), "no use" if cover == INF else "%s days" % Fmt.thousands(roundi(cover))])
	HoverCards.attach(cover_line, func() -> Control: return cover_card(port_id, z, g))
	box.add_child(cover_line)
	var units := str(GameData.commodity(good).get("units", "units"))
	var supply_line := _line("Holds %s %s · uses %s a day · makes %s a day ▸" % [Fmt.short(world.stock[i]), units, Fmt.short(world.need_base[i] + world.user_base[i]), Fmt.short(world.capacity[i])])
	HoverCards.attach(supply_line, func() -> Control: return supply_card(z, g))
	box.add_child(supply_line)
	var inbound := world.inbound[i]
	var sailings := _inbound_voyages(world, z, good)
	var inbound_line := _line("On its way: %s %s in %d sailings ▸" % [Fmt.short(inbound), units, sailings.size()])
	HoverCards.attach(inbound_line, func() -> Control: return voyages_card(z, good, sailings))
	box.add_child(inbound_line)
	var spark := LineChart.new(36.0)
	spark.small = true
	spark.custom_minimum_size.x = WIDTH
	spark.series = GameState.history.weekly_series(i)
	spark.tooltip_text = "The last year, by the week, as x the usual price."
	box.add_child(spark)
	var mine := GameState.company_sell_price(port_id, good)
	var yours := _line("You'd get %s a %s ▸" % [Fmt.money(roundi(mine)), unit])
	yours.theme_type_variation = &"GainLabel" if mine > sell * 1.001 else &""
	HoverCards.attach(yours, func() -> Control: return bonus_card(port_id, good))
	box.add_child(yours)
	return box


## How the price follows the cover.
static func cover_card(port_id: String, z: int, g: int) -> Control:
	var world: WorldEconomy = GameState.world
	var p: Dictionary = WorldEconomy.settings("prices")
	var box := _box()
	box.add_child(_title("Days of cover"))
	var i := z * world.goods.size() + g
	var cover := world.cover(z, g)
	var normal := float(p.get("cover_days", 40))
	box.add_child(_line("The zone's stockpile against what it uses a day (or makes, where it makes more): %s days now, %s is usual." % ["∞" if cover == INF else Fmt.thousands(roundi(cover)), Fmt.thousands(roundi(normal))]))
	box.add_child(_line("Price = usual x (%d / cover) ^ %s, held between x%s and x%s: short of cover it climbs, long of it it falls." % [roundi(normal), Fmt.decimal(float(p.get("price_power", 0.6)), 1),
		Fmt.decimal(float((p.get("price_range", [0.3, 3.0]) as Array)[0]), 1), Fmt.decimal(float((p.get("price_range", [0.3, 3.0]) as Array)[1]), 1)]))
	var country := str(world.zones[z].country)
	var strength := float((world.currency.get(country, {}) as Dictionary).get("strength", 1.0))
	box.add_child(_line("x%s for %s's currency (it drifts with the country's trade balance)." % [Fmt.decimal(strength, 3), str(WorldEconomy.country(country).get("name", country))]))
	var port_factor := float(world._port_factor.get(port_id, 1.0))
	box.add_child(_line("x%s for this port: the zone's biggest port sells cheapest, its smallest dearest." % Fmt.decimal(port_factor, 2)))
	box.add_child(_dim("Half the cargo on its way counts towards the cover, so prices ease as ships approach."))
	return box


## Who makes and uses it in the zone.
static func supply_card(z: int, g: int) -> Control:
	var world: WorldEconomy = GameState.world
	var good := world.goods[g]
	var box := _box()
	box.add_child(_title("%s in %s" % [str(GameData.commodity(good).get("name", good)), world.zone_label(z)]))
	var i := z * world.goods.size() + g
	box.add_child(_line("Made: %s a day of %s a day of capacity (plants make less when the price is low)." % [Fmt.short(world.made[i]), Fmt.short(world.capacity[i])]))
	var zone: Dictionary = world.zones[z]
	var makers := []
	for index: int in range(world.producers.plants.size()):
		var plant: Dictionary = world.producers.plants[index]
		if plant.good == good and str(plant.site_kind) == "port" and plant.site in zone.ports:
			makers.append(index)
	makers.sort_custom(func(a: int, b: int) -> bool: return float(world.producers.plants[a].capacity) > float(world.producers.plants[b].capacity))
	if makers.is_empty():
		box.add_child(_dim("No plants make it at the zone's ports (inland or elsewhere: it comes by sea)."))
	else:
		var parts := PackedStringArray()
		for index: int in makers.slice(0, PLANTS_SHOWN):
			var plant: Dictionary = world.producers.plants[index]
			parts.append("%s's %s at %s" % [str(world.producers.company_of(plant).get("name", "")), Producers.plant_title(plant).to_lower(), GameData.port_name(str(plant.site))])
		box.add_child(_line("Biggest makers: " + "; ".join(parts) + ("" if makers.size() <= PLANTS_SHOWN else " and %d more" % (makers.size() - PLANTS_SHOWN))))
	box.add_child(_line("Used: %s a day now (%s by people and %s by industry at usual prices; dearer, they use less)." % [Fmt.short(world.used[i]), Fmt.short(world.need_base[i]), Fmt.short(world.user_base[i])]))
	var users: Array = WorldEconomy.settings("users").get(good, [])
	if not users.is_empty():
		var parts := PackedStringArray()
		for pair: Array in users:
			var driver := str(pair[0])
			var what := driver
			if driver.begins_with("make:"):
				var made := driver.trim_prefix("make:")
				what = "making %s" % str(GameData.commodity(made).get("name", made)).to_lower()
			elif driver == "gdp":
				what = "industry at large"
			elif driver == "people":
				what = "households"
			elif driver == "farming":
				what = "farming"
			parts.append("%s %d%%" % [what, roundi(float(pair[1]) * 100.0)])
		box.add_child(_dim("Industry's share: " + ", ".join(parts) + "."))
	for need: Dictionary in WorldEconomy.settings("needs"):
		if good in need.get("goods", []):
			box.add_child(_dim("A %s good: people buy the cheapest of %s first." % [str(need.name).to_lower(), ", ".join(PackedStringArray((need.goods as Array).map(func(each: String) -> String: return str(GameData.commodity(each).get("name", each)).to_lower())))]))
			break
	return box


static func _inbound_voyages(world: WorldEconomy, z: int, good: String) -> Array:
	var out := []
	for v: Dictionary in (GameState.firms as ShippingFirms).voyages:
		if (v.goods as Dictionary).has(good) and world.zone_of_port(str(v.to)) == z:
			out.append(v)
	return out


static func voyages_card(z: int, good: String, sailings: Array) -> Control:
	var world: WorldEconomy = GameState.world
	var firms: ShippingFirms = GameState.firms
	var box := _box()
	box.add_child(_title("Bound for %s with %s" % [world.zone_label(z), str(GameData.commodity(good).get("name", good)).to_lower()]))
	if sailings.is_empty():
		box.add_child(_dim("Nothing at sea for it now."))
		return box
	for v: Dictionary in sailings.slice(0, VOYAGES_SHOWN):
		var model := GameData.get_ship_model(str(v.model))
		box.add_child(_line("%s: %d %s%s with %s from %s, due %s" % [str(firms.firms[int(v.firm)].name), int(v.ships), str(model.get("name", v.model)), "s" if int(v.ships) > 1 else "",
			Fmt.short(float(v.goods[good])), GameData.port_name(str(v.from)), Fmt.calendar_short(GameState.calendar_time_at(float(v.arrive)))]))
	if sailings.size() > VOYAGES_SHOWN:
		box.add_child(_dim("and %d more sailings" % (sailings.size() - VOYAGES_SHOWN)))
	return box


## What lifts this company's price over the port's.
static func bonus_card(port_id: String, good: String) -> Control:
	var who := GameState.company
	var box := _box()
	box.add_child(_title("Your price here"))
	var hub := GameState.hub_at(port_id, who)
	var hub_bonus := hub.industry_bonus(GameData.family_of(good), "sell") if hub else 0.0
	box.add_child(_line("Warehouse at your hub: %s" % ("+%d%%" % roundi(hub_bonus * 100.0) if hub_bonus > 0.0 else "none here")))
	var type_id := Progression.type_of_commodity(good)
	var stars := GameState.ratings.factor(who, type_id, "price")
	box.add_child(_line("Your %s stars: %s" % [Progression.type_name(type_id) if not type_id.is_empty() else "type", _percent(stars - 1.0)]))
	box.add_child(_line("Research perks: %s" % _percent(Research.perk(who, "price") - 1.0)))
	box.add_child(_line("Your CEO's traits (%s): %s" % [Traits.names_of(who.ceo) if not Traits.names_of(who.ceo).is_empty() else "none", _percent(Traits.factor(who, "price") - 1.0)]))
	var divine := GameState.divine.price_factor(port_id, true)
	if absf(divine - 1.0) > 0.001:
		box.add_child(_line("Blessings and omens here: %s" % _percent(divine - 1.0)))
	return box


static func _percent(share: float) -> String:
	if absf(share) < 0.0005:
		return "none"
	return "%s%d%%" % ["+" if share > 0.0 else "-", roundi(absf(share) * 100.0)]


# --- Bits ------------------------------------------------------------------------------

static func _box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 3)
	box.custom_minimum_size.x = WIDTH
	return box


static func _title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	label.add_theme_font_size_override(&"font_size", TITLE_SIZE)
	return label


static func _line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = WIDTH
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


static func _dim(text: String) -> Label:
	var label := _line(text)
	label.theme_type_variation = &"DimLabel"
	return label

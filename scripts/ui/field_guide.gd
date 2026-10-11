# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name FieldGuide
extends Control
## The field guide (the paw button at the map's top right): every bird, sea
## animal and land animal in the game, a tab each. Birds (data/birds.json):
## the gulls, the seabirds, the raptors, the cormorants, the herons, egrets,
## bitterns and cranes, and the sea ducks,
## each with its picture, Latin name, where and when to see it, and a fact.
## Sea animals (data/sea_life.json): each with its picture, size, the
## waters its pods visit, and a fact. Land animals (the groups roaming the
## map: data/birds.json land_animals): each with its picture, where it
## lives, its habits, and a fact. A green check marks each one this player has
## seen on the map (Achievements.discover()), and the header says how many.
## Wonders (data/wonders.json): the wonders of the world on the map, man-made,
## lost ancient and natural, each with its picture, country, when and a fact,
## checked once clicked on the map.
## Over the map, dimming it; Esc, X or a click
## outside closes it.

const PANEL_SIZE := Vector2(820, 640)
const TEXT_WIDTH := 600.0
const SMALL_FONT := 14
const ICON_SIZE := 56.0
const TABS := ["Birds", "Sea animals", "Land animals", "Catch", "Wonders"]
## The sea animals' groups: [heading, note, kinds (data/sea_life.json kind)].
const SEA_GROUPS := [
	["Whales, dolphins and orcas", "Pods that spend parts of the year in their waters and migrate between them; whales and orcas come up to breathe and breach, dolphins leap.", ["whale", "orca", "dolphin"]],
	["Seals, sea lions and otters", "Colonies along the coasts: seals and sea lions bob up to look about (sea lions porpoise along), otters float on their backs.", ["seal", "sea_lion", "otter"]],
	["Sharks", "Alone or in twos and threes (hammerheads school round seamounts), showing a fin now and then; makos and great whites breach.", ["shark"]],
	["Game fish", "Schools of the fish anglers chase: the salmon running in to their rivers, tuna, the billfish, mahi-mahi, tarpon and the rest, leaping clear now and then.", ["fish"]],
]

var _tabs := TabBar.new()
var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			queue_free())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardPanel"
	card.custom_minimum_size = Vector2(PANEL_SIZE.x, minf(PANEL_SIZE.y, get_viewport_rect().size.y - 80.0))
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 10)
	card.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 10)
	var paw := PawIcon.new()
	paw.custom_minimum_size = Vector2(30, 30)
	header.add_child(paw)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Field guide"
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(title)
	var seen := Label.new()
	seen.text = "%d of %d animals · %d of %d wonders seen" % [Achievements.seen_count(GameState.company), Achievements.animal_count(),
		Achievements.wonders_seen(GameState.company), GameData.wonders.size()]
	seen.tooltip_text = "Animals and wonders seen on the map (click a flock, pod, group or wonder to see what it is). A check marks each one."
	seen.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(seen)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(header)
	for tab: String in TABS:
		_tabs.add_tab(tab)
	_tabs.tab_changed.connect(_show)
	content.add_child(_tabs)
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(_scroll)
	_list.add_theme_constant_override(&"separation", 12)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_show(0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()


func _show(tab: int) -> void:
	for child in _list.get_children():
		child.queue_free()
	_scroll.scroll_vertical = 0
	match tab:
		0:
			var birds := Birds.shared()
			_heading("Gulls", "Over every port, over grain and livestock carriers, and now and then over other ships and sea animals: most at dawn and dusk, few at night, more in the breeding season and round ships loading or unloading.")
			for id: String in birds.gulls:
				_bird_entry(id, birds.gulls[id])
			_heading("Seabirds", "Out at sea they take up following ships for a few hours at a time, where they are that season: condors along the coasts, albatrosses and shearwaters over the open ocean, terns and pelicans nearer land, frigatebirds hanging high over tropical coasts (never settling on the water). Those that sit on the sea paddle about now and then.")
			for id: String in birds.seabirds:
				_bird_entry(id, birds.seabirds[id])
			_heading("Eagles, hawks, falcons and the osprey", "Along the shore at ports, by day, each hunting its own way: sea eagles sit on a perch and swoop out to snatch fish off the water, the osprey hovers and plunges in feet first, golden eagles and peregrines soar high and stoop, gyrfalcons and brown falcons hang on the wind, buzzards hang on the wind over the land, Harris's hawks hunt in packs, goshawks dash out from cover, and Swainson's hawks pass over in great circling kettles on their way to and from Argentina.")
			for id: String in birds.raptors:
				_bird_entry(id, birds.raptors[id])
			_heading("Cormorants", "About ports by day and night: standing on the breakwater (holding their wings out to dry), swimming low and diving long for fish, and flying past low over the water in Vs.")
			for id: String in birds.cormorants:
				_bird_entry(id, birds.cormorants[id])
			_heading("Herons, egrets, bitterns and cranes", "Along the shore either side of ports: herons stand stock still at the water's edge waiting to strike (night herons come out at dusk), egrets stride the shallows stabbing as they go, bitterns hide in the reeds with their bills to the sky, and cranes feed over the fields in family groups, dancing in spring and passing high over in Vs on migration.")
			for id: String in birds.waders:
				_bird_entry(id, birds.waders[id])
			_heading("Sea ducks", "Eiders and scoters raft on the sea off northern ports, day and night: bobbing into the wind and diving for mussels (scoters all together), now and then pattering off to settle somewhere new; eider hens lead their ducklings in high summer. On migration, in spring and autumn, they pass in long low Vs over the sea.")
			for id: String in birds.sea_ducks:
				_bird_entry(id, birds.sea_ducks[id])
		1:
			var sea := SeaLife.shared()
			for group: Array in SEA_GROUPS:
				_heading(group[0], group[1])
				for id: String in sea.species:
					if (group[2] as Array).has(str(sea.species[id].kind)):
						_sea_entry(sea, id)
		2:
			var land: Dictionary = Birds.shared().land_animals
			for id: String in land:
				_land_entry(id, land[id])
		3:
			_show_catch()
		4:
			for group: Array in [["Man-made wonders", "man_made", "The New 7 Wonders of the World, the Great Pyramid of Giza and other world-famous landmarks."],
					["Lost wonders of the ancient world", "ancient", "Six of the Seven Wonders of the Ancient World are long gone: drawn on the map as they were, faded, where they stood."],
					["Natural wonders", "natural", "The Seven Natural Wonders of the World, the New 7 Wonders of Nature and other famous sights."]]:
				_heading(group[0], group[2])
				for item: Dictionary in GameData.wonders:
					if item.get("kind", "") == group[1]:
						_wonder_entry(item)


## The Catch tab: every crab and fish the fishing and crabbing boats go
## after (Fisheries), family by family: where it's caught and in which months,
## how, and what a crate of it fetches.
func _show_catch() -> void:
	var fish := Fisheries.shared()
	var sea := SeaLife.shared()
	var gear_words := {trap = "Caught in crab pots", troll = "Caught on trolled lines", net = "Caught in nets (gillnets and purse seines)", trawl = "Caught in trawls"}
	for kind: String in ["crab", "fish"]:
		_heading("Crabs" if kind == "crab" else "Fish", "Every crab is caught in pots: small skiffs set a few dozen inshore, the big crabbers hundreds out in the Bering Sea." if kind == "crab" else "Caught by the fishing boats in the seasons on their grounds: small boats troll (and may hook a giant that fills the hold), bigger ones net and trawl.")
		for family_id: String in fish.family_order:
			var family: Dictionary = fish.families[family_id]
			if family.kind != kind:
				continue
			for species_id: String in fish.species:
				var info: Dictionary = fish.species[species_id]
				if info.family != family_id:
					continue
				var places := PackedStringArray()
				for ground_id: String in fish.ground_order:
					if (fish.grounds[ground_id].species as Dictionary).has(species_id):
						places.append("%s (%s)" % [str(fish.grounds[ground_id].name), fish.season_text(ground_id, species_id)])
				var lines: Array[String] = ["Where: %s." % ", ".join(places), "%s · %s, about %s a crate" % [gear_words.get(str(info.gear), ""), family.name, Fmt.money(roundi(float(GameData.commodity(family_id).get("base", 0.0)) * float(info.grade)))]]
				var fact := str(info.get("fact", (sea.species.get(species_id, {}) as Dictionary).get("fact", "")))
				if not fact.is_empty():
					lines.append(fact)
				var art := "res://art/catch/%s.svg" % species_id if kind == "crab" else MapView.SEA_ART_DIR + species_id + ".svg"
				var side := Vector2.ONE * ICON_SIZE if kind == "crab" else Vector2(ICON_SIZE * 1.6, ICON_SIZE * 0.6)
				_entry("catch:" + species_id, _picture(art, side), str(info.name), str(info.latin), lines)


func _heading(text: String, note: String) -> void:
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = text
	_list.add_child(title)
	_list.add_child(_text(note))


func _text(text: String, dim := true) -> Label:
	var label := Label.new()
	if dim:
		label.theme_type_variation = &"DimLabel"
	label.add_theme_font_size_override(&"font_size", SMALL_FONT)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = TEXT_WIDTH
	label.text = text
	return label


## An entry: a picture, then its name (with a check once this player has
## seen it on the map, see Achievements.discover()) and a line under it, and
## its lines.
func _entry(key: String, picture: Control, name: String, subtitle: String, lines: Array[String]) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 14)
	picture.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(picture)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", 1)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override(&"separation", 6)
	var title := Label.new()
	title.text = name
	name_row.add_child(title)
	if GameState.company.discovered.has(key):
		name_row.add_child(SeenCheck.new())
	text.add_child(name_row)
	if not subtitle.is_empty():
		var sub := _text(subtitle)
		text.add_child(sub)
	for line in lines:
		text.add_child(_text(line, false) if line.begins_with("Where") else _text(line))
	row.add_child(text)
	_list.add_child(row)


func _bird_entry(id: String, info: Dictionary) -> void:
	var subtitle := str(info.get("latin", ""))
	if info.has("kind"):
		subtitle = "%s · %s" % [info.kind, subtitle]
	_entry("bird:" + id, BirdIcon.new(info, ICON_SIZE), str(info.get("name", "")), subtitle,
		["Where: %s" % info.get("where", ""), str(info.get("fact", ""))])


func _sea_entry(sea: SeaLife, id: String) -> void:
	var kind: Dictionary = sea.species[id]
	# The waters its pods visit, in the order first met.
	var waters := PackedStringArray()
	for pod: Dictionary in sea.pods:
		if pod.species != id:
			continue
		for stay: Dictionary in pod.stays:
			var area_name := str(sea.areas.get(stay.area, {}).get("name", stay.area))
			if not waters.has(area_name):
				waters.append(area_name)
	var places := ", ".join(waters)
	var where := "Where: %s." % (places.left(1).to_upper() + places.substr(1)) if not places.is_empty() else "Where: the open ocean."
	_entry("sea:" + id, _picture(MapView.SEA_ART_DIR + str(kind.get("art", id)) + ".svg", Vector2(ICON_SIZE * 1.6, ICON_SIZE * 0.6)),
		str(kind.get("name", id)), "Up to %s m long" % kind.get("length_m", "?"), [where, str(kind.get("fact", ""))])


func _land_entry(id: String, info: Dictionary) -> void:
	var group: Array = info.get("group", [1, 1])
	var subtitle := "On its own" if int(group[1]) <= 1 else "In groups of %d to %d" % [int(group[0]), int(group[1])]
	if int(group[0]) <= 1 and int(group[1]) > 1:
		subtitle = "Alone, or up to %d together" % int(group[1])
	var lines: Array[String] = ["Where: %s" % info.get("where", "")]
	if info.has("habits"):
		lines.append(str(info.habits))
	lines.append(str(info.get("fact", "")))
	_entry("land:" + id, _picture(MapView.WILDLIFE_ART_DIR + id + ".svg", Vector2.ONE * ICON_SIZE), str(info.get("name", id)), subtitle, lines)


func _wonder_entry(item: Dictionary) -> void:
	var picture := _picture(MapView.WONDER_ART_DIR + str(item.id) + ".svg", Vector2.ONE * ICON_SIZE)
	if item.get("kind", "") == "ancient":
		picture.modulate.a = MapView.WONDER_LOST_ALPHA
	var lines: Array[String] = [str(item.get("when", "")), str(item.get("fact", ""))]
	_entry("wonder:" + str(item.id), picture, str(item.get("name", item.id)), str(item.get("country", "")), lines)


static func _picture(path: String, side: Vector2) -> Control:
	var picture := TextureRect.new()
	picture.custom_minimum_size = side
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if ResourceLoader.exists(path):
		picture.texture = load(path)
	return picture


## A green check: an animal seen on the map.
class SeenCheck extends Control:
	const SIDE := 18.0
	const GREEN := Color(0.45, 0.85, 0.45)

	func _init() -> void:
		custom_minimum_size = Vector2.ONE * SIDE
		size_flags_vertical = SIZE_SHRINK_CENTER
		tooltip_text = "Seen on the map"

	func _draw() -> void:
		draw_polyline(PackedVector2Array([Vector2(0.15, 0.55) * SIDE, Vector2(0.4, 0.8) * SIDE, Vector2(0.88, 0.22) * SIDE]), GREEN, 3.0, true)

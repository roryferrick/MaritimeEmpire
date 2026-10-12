# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name BirdsPopup
extends AnchoredPopup
## Opened by clicking a bird on the map (see BirdLife): what birds are round
## what was clicked (a port, with its gulls, raptors, cormorants, waders and
## sea ducks; a ship, with those following it; or a colony, where it lives or
## on the wing between its homes) and what they're doing now, each species
## with its picture, name, Latin name and how many (its fact on hovering), in
## a list that scrolls once it's long. Follows what it's about; looks again
## every couple of seconds. Each species has a Follow button at its right: the
## map follows one of its birds there (see MapView.follow_bird()), and the
## button says so (Following; pressed again, it lets it go).

const REFRESH_SECONDS := 2.0
const ICON_SIZE := 32.0
const NAME_FONT_SIZE := 15
## The list scrolls past this tall (px), with room for its scrollbar.
const MAX_LIST_HEIGHT := 340.0
const SCROLLBAR_ROOM := 14.0
const FONT_SIZE := 12
## How wide (px) the line of what a species is doing is, before it wraps.
const DOING_WIDTH := 260.0
## The classes of birds that live round ports, in the order they're listed.
const CLASSES := ["gulls", "raptors", "cormorants", "waders", "sea_ducks"]

## Set before adding to the tree: {port}, {ship} or {colony} (see MapView.birds_clicked).
var about: Dictionary
## The map, for following a bird (set by the world screen).
var map: MapView

var _title := Label.new()
var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _clock := 0.0
var _shown := ""  # What the list shows (so it's only rebuilt when that changes).
## Each row's Follow button and what shows its state: [[button, callable]].
var _follow_buttons := []


func _init() -> void:
	theme_type_variation = &"MapPopup"


func _ready() -> void:
	super()
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	_title.theme_type_variation = &"HeaderLabel"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	_list.add_theme_constant_override(&"separation", 4)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.add_child(_list)
	content.add_child(_scroll)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	for entry: Array in _follow_buttons:  # (Following, or let go by the map.)
		if is_instance_valid(entry[0]):
			(entry[1] as Callable).call()
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


## [title, [[species id, how many (words), its colony or -1 (following a ship)], ...]] for what it's about now.
func _birds_now() -> Array:
	var birds := Birds.shared()
	var life := BirdLife.shared()
	var wildlife := Wildlife.shared()
	var cal := float(GameState.calendar_time())
	var entries := []
	var title := "Birds"
	if about.has("port"):
		title = "Birds at %s" % GameData.port_name(about.port)
		for cls: String in CLASSES:
			for entry: Dictionary in wildlife.birds_at(about.port, cls, cal):
				entries.append([entry.id, _doing(int(entry.colony), cal), int(entry.colony)])
	elif about.has("ship"):
		var ship: Ship = about.ship
		title = "Birds round %s" % ship.name
		for entry: Dictionary in life.following(ship):
			entries.append([entry.id, "%d following" % int(entry.count), -1])
	elif about.has("colony"):
		var colony: Dictionary = wildlife.colonies[int(about.colony)]
		var name := str(birds.species(colony.species).get("name", colony.species))
		var where := wildlife.colony_where(colony, cal)
		var count := int(colony.count)
		if where[0] == "to_away" or where[0] == "to_home":
			var bound: String = colony.port if where[0] == "to_home" else colony.away_port
			title = "%s on the wing" % name
			entries.append([colony.species, "%d flying to %s" % [count, GameData.port_name(bound) if not bound.is_empty() else "their winter grounds"], int(about.colony)])
		else:
			var port: String = colony.away_port if where[0] == "away" else colony.port
			title = "%s at %s" % [name, GameData.port_name(port)] if not port.is_empty() else "%s at sea" % name
			entries.append([colony.species, _doing(int(about.colony), cal), int(about.colony)])
	return [title, entries]


## "12: 5 circling the port, 4 perched, 3 asleep at home" (a colony's birds now).
func _doing(colony_index: int, cal: float) -> String:
	var colony: Dictionary = Wildlife.shared().colonies[colony_index]
	return "%d: %s" % [int(colony.count), ", ".join(BirdLife.shared().doing_text(colony_index, Wildlife.shared().bird_time, cal))]


func _refresh() -> void:
	var now := _birds_now()
	_title.text = now[0]
	var key := str(now[1])
	if key == _shown:
		return
	_shown = key
	_follow_buttons.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if (now[1] as Array).is_empty():
		var gone := Label.new()
		gone.theme_type_variation = &"DimLabel"
		gone.text = "They've flown off."
		_list.add_child(gone)
	for entry: Array in now[1]:
		_list.add_child(_species_row(entry[0], entry[1], int(entry[2])))
	# Seen: checked in the field guide.
	Achievements.discover((now[1] as Array).map(func(entry: Array) -> String: return "bird:" + str(entry[0])))
	_fit_list.call_deferred()


## A species, in a line or two: its picture, its name and how many, and its
## Latin name under them (its fact on hovering); and at its right its Follow button.
func _species_row(id: String, count: String, colony: int) -> Control:
	var info := Birds.shared().species(id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.tooltip_text = str(info.get("fact", ""))
	var icon := BirdIcon.new(info, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override(&"separation", -2)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name := Label.new()
	name.add_theme_font_size_override(&"font_size", NAME_FONT_SIZE)
	# "12: 5 circling the port, 4 perched": how many by the name, what they're doing under it.
	var parts := count.split(": ", true, 1)
	name.text = "%s · %s" % [info.get("name", id), parts[0]]
	text.add_child(name)
	var latin := Label.new()
	latin.theme_type_variation = &"DimLabel"
	latin.add_theme_font_size_override(&"font_size", FONT_SIZE)
	latin.text = str(info.get("latin", ""))
	text.add_child(latin)
	if parts.size() > 1:
		var doing := Label.new()
		doing.add_theme_font_size_override(&"font_size", FONT_SIZE)
		doing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		doing.custom_minimum_size.x = DOING_WIDTH
		doing.text = parts[1]
		text.add_child(doing)
	row.add_child(text)
	if map != null:
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var follow := Button.new()
		follow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		follow.toggle_mode = true
		follow.add_theme_font_size_override(&"font_size", FONT_SIZE)
		follow.tooltip_text = "Follow one of these birds on the map (a click or a drag on the map lets it go)."
		var shown := func() -> void:
			var on := _row_followed(id, colony)
			follow.set_pressed_no_signal(on)
			follow.text = "Following" if on else "Follow"
		follow.toggled.connect(func(on: bool) -> void:
			if on:
				var bird := _bird_to_follow(id, colony)
				if bird < 0:
					follow.set_pressed_no_signal(false)
					follow.tooltip_text = "None of them to follow just now."
					return
				map.follow_bird(bird)
			elif map.followed_bird >= 0:
				map.follow_bird(-1)
			shown.call())
		_follow_buttons.append([follow, shown])
		shown.call()
		row.add_child(follow)
	return row


## True if the map follows one of this row's birds: of its colony, or (colony
## -1, following a ship) of its species.
func _row_followed(id: String, colony: int) -> bool:
	var life := BirdLife.shared()
	if map == null or map.followed_bird < 0 or map.followed_bird >= life.birds.size():
		return false
	var of := int(life.birds[map.followed_bird].colony)
	return of == colony if colony >= 0 else str(Wildlife.shared().colonies[of].species) == id


## One of a species' birds to follow (see BirdLife.bird_to_follow()): of
## its colony, or (following a ship: colony -1) one of those following it; -1 if none.
func _bird_to_follow(id: String, colony: int) -> int:
	var life := BirdLife.shared()
	var wildlife := Wildlife.shared()
	var now := wildlife.bird_time
	var cal := float(GameState.calendar_time())
	if colony >= 0:
		return life.bird_to_follow(colony, now, cal)
	if not about.has("ship"):
		return -1
	var ship: Ship = about.ship
	var at := Geo.unproject(GameData.port_position(ship.docked_at) if ship.is_docked() else ship.world_position())
	var reach := BirdLife.SEABIRD_FOLLOW_KM / Wildlife.KM_PER_DEGREE
	var wide := reach / maxf(cos(deg_to_rad(at.y)), 0.1)
	var box := Rect2(at - Vector2(wide, reach), Vector2(wide, reach) * 2.0)
	for index: int in wildlife.colonies_near(box) + wildlife.seabird_colonies_in(box):
		if str(wildlife.colonies[index].species) == id:
			var bird := life.bird_to_follow(index, now, cal, "follow")
			if bird >= 0:
				return bird
	return -1


## Fits the list's scroll to it, up to MAX_LIST_HEIGHT (or half the screen)
## tall: scrolled beyond that.
func _fit_list() -> void:
	var wanted := _list.get_combined_minimum_size()
	var tallest := minf(MAX_LIST_HEIGHT, get_viewport_rect().size.y * 0.5)
	var scrolls := wanted.y > tallest
	_scroll.custom_minimum_size = Vector2(wanted.x + (SCROLLBAR_ROOM if scrolls else 0.0), minf(wanted.y, tallest))
	reset_size()

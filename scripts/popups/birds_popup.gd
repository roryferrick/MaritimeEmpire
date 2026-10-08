# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name BirdsPopup
extends AnchoredPopup
## Opened by clicking a flock of birds on the map (see Birds): what birds are
## round what was clicked (a port, with its gulls, raptors, cormorants, waders and
## sea ducks; a ship; or a pod of sea animals) now, each species with its
## picture, name, Latin name and how many (its fact on hovering), in a list
## that scrolls once it's long. Follows what it's about;
## looks again every couple of seconds (flocks come and go with the time of
## day, and seabirds, raptors, cormorants and sea ducks with the hours).

const REFRESH_SECONDS := 2.0
const ICON_SIZE := 32.0
const NAME_FONT_SIZE := 15
## The list scrolls past this tall (px), with room for its scrollbar.
const MAX_LIST_HEIGHT := 340.0
const SCROLLBAR_ROOM := 14.0
const FONT_SIZE := 12

## Set before adding to the tree: {port}, {ship} or {pod} (see MapView.birds_clicked).
var about: Dictionary

var _title := Label.new()
var _list := VBoxContainer.new()
var _scroll := ScrollContainer.new()
var _clock := 0.0
var _shown := ""  # What the list shows (so it's only rebuilt when that changes).


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
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


## [title, [[species id, how many (words)], ...]] for what it's about now.
func _birds_now() -> Array:
	var birds := Birds.shared()
	var entries := []
	var title := "Birds"
	var flock := {}
	if about.has("port"):
		title = "Birds at %s" % GameData.port_name(about.port)
		flock = birds.port_flock(about.port)
		for entry: Dictionary in birds.port_raptors(about.port):
			entries.append([entry.id, "%d about" % int(entry.count)])
		for entry: Dictionary in birds.port_cormorants(about.port):
			entries.append([entry.id, "%d about" % int(entry.count)])
		for entry: Dictionary in birds.port_waders(about.port):
			var info := birds.species(entry.id)
			var words := "%d about" % int(entry.count)
			if entry.moving:
				words = "%d passing over" % int(entry.count)
			elif str(info.get("behavior", "")) == "hide":
				words = "hiding in the reeds"
			elif int(entry.count) == 1:
				words = "1 at the water's edge" if str(info.get("kind", "")) != "Crane" else "1 in the fields"
			entries.append([entry.id, words])
		for entry: Dictionary in birds.port_sea_ducks(about.port):
			entries.append([entry.id, ("%d passing" if entry.moving else "a raft of %d") % int(entry.count)])
	elif about.has("ship"):
		var ship: Ship = about.ship
		title = "Birds round %s" % ship.name
		flock = birds.ship_flock(ship)
		for entry: Dictionary in birds.followers(ship):
			entries.append([entry.id, "%d following" % int(entry.count)])
	elif about.has("pod"):
		var sea := SeaLife.shared()
		var pod: Dictionary = sea.pods[int(about.pod)]
		title = "Gulls over the %s" % str(sea.species[pod.species].get("plural", "animals")).to_lower()
		flock = birds.pod_flock(int(about.pod), sea.state(int(about.pod), float(GameState.calendar_time())).pos)
	if not flock.is_empty():
		var words := Birds.how_many(int(flock.count))
		var gulls := []
		for id: String in flock.species:
			gulls.append([id, words])
		entries = gulls + entries
	return [title, entries]


func _refresh() -> void:
	var now := _birds_now()
	_title.text = now[0]
	var key := str(now[1])
	if key == _shown:
		return
	_shown = key
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if (now[1] as Array).is_empty():
		var gone := Label.new()
		gone.theme_type_variation = &"DimLabel"
		gone.text = "They've flown off."
		_list.add_child(gone)
	for entry: Array in now[1]:
		_list.add_child(_species_row(entry[0], entry[1]))
	# Seen: checked in the field guide.
	Achievements.discover((now[1] as Array).map(func(entry: Array) -> String: return "bird:" + str(entry[0])))
	_fit_list.call_deferred()


## A species, in a line or two: its picture, its name and how many, and its
## Latin name under them; its fact on hovering.
static func _species_row(id: String, count: String) -> Control:
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
	name.text = "%s · %s" % [info.get("name", id), count]
	text.add_child(name)
	var latin := Label.new()
	latin.theme_type_variation = &"DimLabel"
	latin.add_theme_font_size_override(&"font_size", FONT_SIZE)
	latin.text = str(info.get("latin", ""))
	text.add_child(latin)
	row.add_child(text)
	return row


## Fits the list's scroll to it, up to MAX_LIST_HEIGHT (or half the screen)
## tall: scrolled beyond that.
func _fit_list() -> void:
	var wanted := _list.get_combined_minimum_size()
	var tallest := minf(MAX_LIST_HEIGHT, get_viewport_rect().size.y * 0.5)
	var scrolls := wanted.y > tallest
	_scroll.custom_minimum_size = Vector2(wanted.x + (SCROLLBAR_ROOM if scrolls else 0.0), minf(wanted.y, tallest))
	reset_size()

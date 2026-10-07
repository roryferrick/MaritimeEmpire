# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name SeaLifePopup
extends AnchoredPopup
## Opened by clicking a pod of sea animals on the map (see SeaLife): the
## species, how many in the pod (and how many the map shows), what it's doing
## now (staying in an area until when, or migrating, how far and when it
## arrives), its year (each area and its months), how big they get and a fact.
## Its routes show dashed on the map meanwhile. Follows the pod; refreshes a
## few times a second.

const REFRESH_SECONDS := 0.5
const FONT_SIZE := 14
const LABEL_WIDTH := 64.0
const VALUE_WIDTH := 380.0
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

## Set before adding to the tree (an index in SeaLife.pods).
var pod_index := -1

var _title := Label.new()
var _rows := GridContainer.new()
var _clock := 0.0


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
	_rows.columns = 2
	_rows.add_theme_constant_override(&"h_separation", 10)
	_rows.add_theme_constant_override(&"v_separation", 5)
	content.add_child(_rows)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	var sea := SeaLife.shared()
	var pod: Dictionary = sea.pods[pod_index]
	var kind: Dictionary = sea.species[pod.species]
	var state := sea.state(pod_index, float(GameState.calendar_time()))
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_title.text = kind.plural
	var shown := mini(int(pod.size), int(kind.shown))
	var count := "%d %s" % [pod.size, kind.word if int(pod.size) != 1 else str(kind.word).trim_suffix("s")]
	_row("Pod", "%s, the %s%s" % [count, pod.name, " (the map shows %d)" % shown if shown < int(pod.size) else ""])
	if state.migrating:
		_row("Now", "Migrating from %s to %s: %d%% of the way, arriving about %s" % [_area(state.from), _area(state.area),
			roundi(float(state.progress) * 100.0), _date(float(state.until))])
	else:
		_row("Now", "In %s until about %s, then migrating" % [_area(state.area), _date(float(state.until))])
	var year := PackedStringArray()
	for stay: Dictionary in pod.stays:
		var place := _area(stay.area)
		year.append("%s: %s to %s" % [place.left(1).to_upper() + place.substr(1), _month(stay.start), _month(stay.end)])
	_row("Year", "\n".join(year))
	var metres := float(kind.length_m)
	_row("Size", "Up to %s m long" % (str(roundi(metres)) if is_equal_approx(metres, roundf(metres)) else str(metres)))
	_row("Fact", str(kind.fact))
	_row("", "Just for looking at: they don't affect ships.", &"DimLabel")


func _row(label_text: String, text: String, variation := &"") -> void:
	var label := Label.new()
	label.text = label_text
	label.theme_type_variation = &"DimLabel"
	label.custom_minimum_size.x = LABEL_WIDTH
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_rows.add_child(label)
	var value := Label.new()
	value.text = text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.custom_minimum_size.x = VALUE_WIDTH
	if variation != &"":
		value.theme_type_variation = variation
	value.add_theme_font_size_override(&"font_size", FONT_SIZE)
	_rows.add_child(value)


static func _area(area_id: String) -> String:
	return str(SeaLife.shared().areas.get(area_id, {}).get("name", area_id))


## A calendar time as "20 Dec".
static func _date(unix: float) -> String:
	var date := Time.get_datetime_dict_from_unix_time(int(unix))
	return "%d %s" % [date.day, MONTHS[date.month - 1]]


## A day of the year as "early Jun", "mid Jun" or "late Jun".
static func _month(day: float) -> String:
	var month := 0
	for m in SeaLife.MONTH_STARTS.size():
		if day >= SeaLife.MONTH_STARTS[m]:
			month = m
	var into: float = day - SeaLife.MONTH_STARTS[month]
	return "%s %s" % ["early" if into < 10 else ("mid" if into < 20 else "late"), MONTHS[month]]

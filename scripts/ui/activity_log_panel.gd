class_name ActivityLogPanel
extends PanelContainer
## The activity log down the left of the game screen: ActivityLog's messages,
## newest at the top, in small text with the calendar time they happened at. Text
## takes the ship's color (lightened if too dark to read); good and bad news
## get a green or red highlight behind it. The « button folds it away to a thin
## strip (» opens it again), remembered with the game (GameState.activity_collapsed).

## Colors darker than this are lightened toward white so they read on the panel.
const MIN_TEXT_LUMINANCE := 0.55

const THEME_TYPE := &"ActivityLog"
## The panel's width open, and folded away to just its button.
const OPEN_WIDTH := 272.0
const FOLDED_WIDTH := 44.0

@onready var _list: VBoxContainer = %LogList


func _ready() -> void:
	ActivityLog.entry_added.connect(_add_row)
	ActivityLog.cleared.connect(_clear)
	%CollapseButton.pressed.connect(_toggle)
	for entry in ActivityLog.entries:
		_add_row(entry)
	_show_folded(GameState.activity_collapsed)


func _add_row(entry: Dictionary) -> void:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s  %s" % [_clock(entry.time), entry.text]
	label.theme_type_variation = THEME_TYPE
	var color: Color = entry.get("color", Color.TRANSPARENT)
	if color.a > 0.0:
		label.add_theme_color_override(&"font_color", _readable(color))
	match entry.kind:
		ActivityLog.Kind.INFO:
			label.add_theme_stylebox_override(&"normal", _highlight(Color.TRANSPARENT))
		ActivityLog.Kind.GOOD:
			label.add_theme_stylebox_override(&"normal", _highlight(_color(&"good_highlight", Color(0.2, 0.6, 0.3, 0.35))))
		ActivityLog.Kind.BAD:
			label.add_theme_stylebox_override(&"normal", _highlight(_color(&"bad_highlight", Color(0.75, 0.2, 0.2, 0.35))))
	_list.add_child(label)
	_list.move_child(label, 0)
	while _list.get_child_count() > ActivityLog.MAX_ENTRIES:
		var oldest := _list.get_child(-1)
		_list.remove_child(oldest)
		oldest.queue_free()
	%EmptyLabel.visible = false  # _show_folded() keeps it hidden from now on.


func _clear() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	%EmptyLabel.visible = not GameState.activity_collapsed


func _toggle() -> void:
	GameState.activity_collapsed = not GameState.activity_collapsed
	_show_folded(GameState.activity_collapsed)


## Folded: only the » button shows, in a thin strip. Open: the title, the
## messages (or the empty note) and the « button.
func _show_folded(folded: bool) -> void:
	custom_minimum_size.x = FOLDED_WIDTH if folded else OPEN_WIDTH
	%LogTitle.visible = not folded
	%LogScroll.visible = not folded
	%EmptyLabel.visible = not folded and _list.get_child_count() == 0
	%CollapseButton.text = "»" if folded else "«"
	%CollapseButton.tooltip_text = "Show the activity log" if folded else "Fold the activity log away"


static func _highlight(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(2.0)
	box.set_corner_radius_all(2)
	return box


static func _readable(color: Color) -> Color:
	var lightened := color
	while lightened.get_luminance() < MIN_TEXT_LUMINANCE:
		lightened = lightened.lerp(Color.WHITE, 0.1)
	return lightened


func _color(color_name: StringName, fallback: Color) -> Color:
	return get_theme_color(color_name, THEME_TYPE) if has_theme_color(color_name, THEME_TYPE) else fallback


## The calendar time at a play time, as "3 Jan 09:10".
static func _clock(play_time: float) -> String:
	return Fmt.calendar_short(GameState.calendar_time_at(play_time))

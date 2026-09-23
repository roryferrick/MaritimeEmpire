class_name ActivityLogPanel
extends PanelContainer
## The activity log down the left of the game screen: ActivityLog's messages,
## newest at the top, in small text with the play time they happened at.

const THEME_TYPE := &"ActivityLog"

@onready var _list: VBoxContainer = %LogList


func _ready() -> void:
	ActivityLog.entry_added.connect(_add_row)
	ActivityLog.cleared.connect(_clear)
	for entry in ActivityLog.entries:
		_add_row(entry)


func _add_row(entry: Dictionary) -> void:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s  %s" % [_clock(entry.time), entry.text]
	label.theme_type_variation = THEME_TYPE
	match entry.kind:
		ActivityLog.Kind.GOOD:
			label.add_theme_color_override(&"font_color", _color(&"good_color", Color(0.45, 0.9, 0.5)))
		ActivityLog.Kind.BAD:
			label.add_theme_color_override(&"font_color", _color(&"bad_color", Color(1, 0.45, 0.4)))
	_list.add_child(label)
	_list.move_child(label, 0)
	while _list.get_child_count() > ActivityLog.MAX_ENTRIES:
		var oldest := _list.get_child(-1)
		_list.remove_child(oldest)
		oldest.queue_free()
	%EmptyLabel.visible = false


func _clear() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	%EmptyLabel.visible = true


func _color(color_name: StringName, fallback: Color) -> Color:
	return get_theme_color(color_name, THEME_TYPE) if has_theme_color(color_name, THEME_TYPE) else fallback


## Play time as "12:34" or "1:02:34".
static func _clock(seconds: float) -> String:
	var total := floori(seconds)
	var hours := floori(total / 3600.0)
	var clock := "%02d:%02d" % [floori(total / 60.0) % 60, total % 60]
	return "%d:%s" % [hours, clock] if hours > 0 else clock

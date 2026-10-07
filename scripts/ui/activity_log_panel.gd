# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name ActivityLogPanel
extends PanelContainer
## The activity log down the left of the game screen: ActivityLog's messages,
## newest at the top, in small text with the calendar time they happened at. Text
## takes the ship's color (lightened if too dark to read); good and bad news
## get a green or red highlight behind it. The « button folds it away to a thin
## strip (» opens it again), remembered with the game (GameState.activity_collapsed).
## In multiplayer it has two tabs, Activity and Chat (Net.chat_log: "Name:
## text" in the speaker's company color, newest at the bottom, with a line to
## say something; the tab counts messages that came while it wasn't shown).
## T opens the chat (see open_chat()).

## Colors darker than this are lightened toward white so they read on the panel.
const MIN_TEXT_LUMINANCE := 0.55

const THEME_TYPE := &"ActivityLog"
## The panel's width open, and folded away to just its button.
const OPEN_WIDTH := 272.0
const FOLDED_WIDTH := 44.0

@onready var _list: VBoxContainer = %LogList
## Multiplayer: the Activity and Chat tabs, and the chat page: its messages
## and a line to say something to everyone (see Net.say()).
var _activity_tab: Button = null
var _chat_tab: Button = null
var _chat_page: VBoxContainer = null
var _chat_scroll: ScrollContainer = null
var _chat_list: VBoxContainer = null
var _chat: LineEdit = null
var _showing_chat := false
var _unread := 0


func _ready() -> void:
	ActivityLog.entry_added.connect(_add_row)
	ActivityLog.cleared.connect(_clear)
	%CollapseButton.pressed.connect(_toggle)
	for entry in ActivityLog.entries:
		_add_row(entry)
	if Net.is_online():
		_add_chat()
	_show_folded(GameState.activity_collapsed)


## The Activity and Chat tabs (in place of the Activity title) and the chat page.
func _add_chat() -> void:
	_activity_tab = Button.new()
	_chat_tab = Button.new()
	_chat_page = VBoxContainer.new()
	_chat_scroll = ScrollContainer.new()
	_chat_list = VBoxContainer.new()
	_chat = LineEdit.new()
	var group := ButtonGroup.new()
	for tab: Button in [_activity_tab, _chat_tab]:
		tab.toggle_mode = true
		tab.button_group = group
		tab.flat = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_color_override(&"font_color", Color(1, 1, 1, 0.55))  # The open tab is white, the other dim.
		tab.add_theme_color_override(&"font_pressed_color", Color.WHITE)
		tab.add_theme_color_override(&"font_hover_pressed_color", Color.WHITE)
		%CollapseButton.add_sibling(tab)
		%CollapseButton.get_parent().move_child(tab, %CollapseButton.get_index())
	_activity_tab.text = "Activity"
	_activity_tab.button_pressed = true
	_activity_tab.pressed.connect(_show_tab.bind(false))
	_chat_tab.pressed.connect(_show_tab.bind(true))
	_chat_tab.tooltip_text = "Chat to everyone in the game (T)"
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	%CollapseButton.add_sibling(spacer)
	%CollapseButton.get_parent().move_child(spacer, %CollapseButton.get_index())
	_chat_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_page.add_theme_constant_override(&"separation", 6)
	_chat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_chat_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_list.add_theme_constant_override(&"separation", 3)
	_chat_scroll.add_child(_chat_list)
	_chat_page.add_child(_chat_scroll)
	_chat.placeholder_text = "Say something (Enter)"
	_chat.max_length = Net.CHAT_MAX_LENGTH
	_chat.text_submitted.connect(func(text: String) -> void:
		Net.say(text)
		_chat.clear())
	_chat.gui_input.connect(func(event: InputEvent) -> void:
		var key := event as InputEventKey
		if key and key.pressed and key.keycode == KEY_ESCAPE:
			_chat.release_focus()  # Esc leaves the chat line (rather than opening the menu).
			_chat.accept_event())
	_chat_page.add_child(_chat)
	%LogScroll.add_sibling(_chat_page)
	for entry in Net.chat_log:
		_add_chat_row(entry)
	Net.chat_added.connect(func(entry: Dictionary) -> void:
		_add_chat_row(entry)
		if not _showing_chat or GameState.activity_collapsed:
			_unread += 1
		_update_chat_tab())
	_update_chat_tab()


## T: opens the panel on the Chat tab, ready to type (multiplayer only).
func open_chat() -> void:
	if _chat_tab == null:
		return
	if GameState.activity_collapsed:
		_toggle()
	_chat_tab.button_pressed = true
	_show_tab(true)
	_chat.grab_focus()


func _show_tab(chat: bool) -> void:
	_showing_chat = chat
	if chat:
		_unread = 0
		_update_chat_tab()
		_scroll_chat_to_end.call_deferred()
	_show_folded(GameState.activity_collapsed)


func _update_chat_tab() -> void:
	_chat_tab.text = "Chat (%d)" % _unread if _unread > 0 else "Chat"


func _add_chat_row(entry: Dictionary) -> void:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s  %s: %s" % [_clock(entry.time), entry.speaker, entry.text]
	label.theme_type_variation = THEME_TYPE
	label.add_theme_color_override(&"font_color", _readable(entry.color))
	_chat_list.add_child(label)
	while _chat_list.get_child_count() > Net.CHAT_KEPT:
		var oldest := _chat_list.get_child(0)
		_chat_list.remove_child(oldest)
		oldest.queue_free()
	_scroll_chat_to_end.call_deferred()


func _scroll_chat_to_end() -> void:
	await get_tree().process_frame  # Once the new line is laid out.
	_chat_scroll.scroll_vertical = int(_chat_scroll.get_v_scroll_bar().max_value)


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
	%EmptyLabel.visible = not GameState.activity_collapsed and not _showing_chat


func _toggle() -> void:
	GameState.activity_collapsed = not GameState.activity_collapsed
	_show_folded(GameState.activity_collapsed)


## Folded: only the » button shows, in a thin strip. Open: the title, the
## messages (or the empty note) and the « button.
func _show_folded(folded: bool) -> void:
	var tabs := _chat_tab != null
	custom_minimum_size.x = FOLDED_WIDTH if folded else OPEN_WIDTH
	%LogTitle.visible = not folded and not tabs
	%LogScroll.visible = not folded and not _showing_chat
	%EmptyLabel.visible = not folded and not _showing_chat and _list.get_child_count() == 0
	if tabs:
		_activity_tab.visible = not folded
		_chat_tab.visible = not folded
		_chat_page.visible = not folded and _showing_chat
		if not folded and _showing_chat:
			_unread = 0
			_update_chat_tab()
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

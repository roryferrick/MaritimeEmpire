class_name LevelPopup
extends AnchoredPopup
## Opened by clicking the level in the top bar: XP toward the next level, the
## XP rate over the last 10 minutes, and what the next few levels unlock with a
## time estimate for each at that rate. Refreshes once a second.

const REFRESH_SECONDS := 1.0
## Unlocks shown, looking at most this many levels ahead.
const MAX_UPCOMING := 6
const LOOKAHEAD_LEVELS := 25
const FONT_SIZE := 15

var _body := VBoxContainer.new()
var _clock := 0.0


func _init() -> void:
	theme_type_variation = &"MapPopup"
	custom_minimum_size = Vector2(440, 0)
	gap = 8.0


func _ready() -> void:
	super()
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Company level"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.pressed.connect(queue_free)
	header.add_child(close)
	content.add_child(HSeparator.new())
	_body.add_theme_constant_override(&"separation", 6)
	content.add_child(_body)
	_refresh()


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	if _clock >= REFRESH_SECONDS:
		_clock = 0.0
		_refresh()


func _refresh() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var info := Progression.company_level(GameState.company_xp)
	var level: int = info.level
	var rate := GameState.recent_xp_per_minute()
	if info.cost <= 0:
		_add("Level %d: the top level." % level)
		return
	_add("Level %d: %s / %s XP to level %d (%d%%)" % [level, Fmt.thousands(floori(info.xp)),
		Fmt.thousands(info.cost), level + 1, floori(100.0 * info.xp / info.cost)])
	if rate > 0.0:
		_add("Last 10 min: %s XP a minute" % Fmt.thousands(roundi(rate)), &"DimLabel")
	else:
		_add("No XP in the last 10 minutes, so no time estimates yet.", &"DimLabel")
	_body.add_child(HSeparator.new())
	_add("Coming up", &"DimLabel")
	var needed: float = info.cost - info.xp  # XP from now to the start of the next level.
	var shown := 0
	for next in range(level + 1, mini(level + LOOKAHEAD_LEVELS, Progression.max_company_level()) + 1):
		var unlocks := Progression.unlocks_at(next)
		if next == level + 1 or not unlocks.is_empty():
			var what := ", ".join(unlocks) if not unlocks.is_empty() else "no new unlocks"
			var eta := " · in about %s" % Fmt.rough_duration(needed / rate * 60.0) if rate > 0.0 else ""
			_add("Level %d: %s%s" % [next, what, eta])
			shown += 1
			if shown >= MAX_UPCOMING:
				break
		needed += Progression.company_level_cost(next)


func _add(text: String, variation := &"") -> void:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.add_theme_font_size_override(&"font_size", FONT_SIZE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)

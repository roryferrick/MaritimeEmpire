class_name HubTree
extends GridContainer
## An HQ's or hub's upgrade tree: one row per path with its name, point pips,
## the bonus so far and a button to buy the next point (showing its price).
## Rebuilds itself when hubs change. Used by the port popup and the Hubs screen.

const PIP_SIZE := Vector2(6, 10)

var hub: Hub


func _init(for_hub: Hub) -> void:
	hub = for_hub
	columns = 4
	add_theme_constant_override(&"h_separation", 10)


func _ready() -> void:
	GameState.hubs_changed.connect(_rebuild)
	GameState.money_changed.connect(_on_money_changed)
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for path: Array in Hub.PATHS:
		var points := int(hub.upgrades[path[0]])
		var name_label := Label.new()
		name_label.text = path[1]
		add_child(name_label)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override(&"separation", 2)
		pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in Hub.max_path_level():
			var pip := ColorRect.new()
			pip.custom_minimum_size = PIP_SIZE
			pip.color = _pip_color(i < points)
			pips.add_child(pip)
		add_child(pips)
		var effect := Label.new()
		effect.theme_type_variation = &"DimLabel"
		effect.text = path[2] % roundi(hub.bonus(path[0]) * 100.0)
		add_child(effect)
		var add := Button.new()
		var error := GameState.upgrade_hub_error(hub, path[0])
		add.text = "Max" if points >= Hub.max_path_level() else "+ $%s" % Fmt.short(hub.upgrade_cost(path[0]))
		add.disabled = not error.is_empty()
		add.tooltip_text = error if not error.is_empty() else "Spend a point and %s" % Fmt.money(hub.upgrade_cost(path[0]))
		add.pressed.connect(GameState.upgrade_hub.bind(hub, path[0]))
		add_child(add)


## Affordability changes the buttons; only rebuild if it flips.
func _on_money_changed(_money: int) -> void:
	for path: Array in Hub.PATHS:
		var index: int = Hub.PATHS.find(path) * 4 + 3
		if index < get_child_count() and (get_child(index) as Button).disabled != not GameState.upgrade_hub_error(hub, path[0]).is_empty():
			_rebuild()
			return


func _pip_color(filled: bool) -> Color:
	var color_name := &"filled" if filled else &"empty"
	if has_theme_color(color_name, &"SkillPip"):
		return get_theme_color(color_name, &"SkillPip")
	return Color(0.45, 0.9, 0.5) if filled else Color(1, 1, 1, 0.15)

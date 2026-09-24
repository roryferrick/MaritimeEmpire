extends Control
## The player's ships, grouped by model (in shop order), each group on a faint
## tint of its ship line's color under a title in that color, eight tiles wide,
## with sort (within each model) and filter options, and "Upgrade all" (with a
## red dot while any ship has points to spend).
## Tiles are re-sorted when the fleet or the sort changes, not live, so they
## don't jump around; the filter follows each ship's status as it changes.

enum Sort { NAME, STATUS, PROFIT }
enum Filter { ALL, ATTENTION, ACTIVE, STOPPED, LOST, RECOVERY }

const COLUMNS := 8
const TILE_GAP := 6
## Each model group sits on a faint tint of its ship line's color (see
## GameData.category_color()), with this much padding inside.
const GROUP_TINT := 0.1
const GROUP_PADDING := 8
## The mega upgrade button and badge beside each model's name.
const MEGA_FONT_SIZE := 13
const MEGA_COLOR := Color(1.0, 0.82, 0.3)
## "Upgrade all": its width, and the extra gap before it (on top of the header's own).
const UPGRADE_ALL_WIDTH := 200.0
const UPGRADE_ALL_GAP := 16.0
const SORT_NAMES := {Sort.NAME: "Name", Sort.STATUS: "Status (problems first)", Sort.PROFIT: "Profit"}
const FILTER_NAMES := {
	Filter.ALL: "All ships", Filter.ATTENTION: "Needs attention",
	Filter.ACTIVE: "Running (green)", Filter.STOPPED: "Stopped (red)",
	Filter.LOST: "Lost at sea", Filter.RECOVERY: "Recovery boats",
}

## Model id -> [group box, tile grid].
var _groups := {}
## Spends every ship's upgrade points (see GameState.upgrade_all()).
var _upgrade_all := Button.new()
## The red dot on "Upgrade all" while any ship has points to spend.
var _upgrade_all_alert := AlertDot.new(4.0, Vector2(5, 5))
## Model id -> [its "Mega upgrade" button, that button's red dot, its "★ Mega" badge].
var _megas := {}


func _ready() -> void:
	for sort: Sort in SORT_NAMES:
		%SortOption.add_item(SORT_NAMES[sort], sort)
	for filter: Filter in FILTER_NAMES:
		%FilterOption.add_item(FILTER_NAMES[filter], filter)
	%SortOption.item_selected.connect(_rebuild.unbind(1))
	%FilterOption.item_selected.connect(_apply_filter.unbind(1))
	GameState.ships_changed.connect(_rebuild)
	GameState.ship_changed.connect(_apply_filter.unbind(1))
	_upgrade_all.tooltip_text = "Spend every ship's upgrade points in turn: speed, efficiency, durability, speed..."
	_upgrade_all.pressed.connect(GameState.upgrade_all)
	_upgrade_all.custom_minimum_size.x = UPGRADE_ALL_WIDTH
	var gap := Control.new()  # Extra room between the Show filter and Upgrade all.
	gap.custom_minimum_size.x = UPGRADE_ALL_GAP
	%Header.add_child(gap)
	%Header.move_child(gap, %CountLabel.get_index())
	%Header.add_child(_upgrade_all)
	_upgrade_all.add_child(_upgrade_all_alert)
	%Header.move_child(_upgrade_all, %CountLabel.get_index())
	GameState.ship_changed.connect(_update_upgrade_all.unbind(1))
	GameState.ships_changed.connect(_update_upgrade_all)
	_update_upgrade_all()
	GameState.money_changed.connect(_update_megas.unbind(1))
	GameState.ship_changed.connect(_update_megas.unbind(1))
	GameState.mega_upgraded.connect(_update_megas.unbind(1))
	%Groups.resized.connect(_size_tiles)
	_rebuild()


func _rebuild() -> void:
	for child in %Groups.get_children():
		%Groups.remove_child(child)
		child.queue_free()
	_groups.clear()
	_megas.clear()
	var sorted := GameState.ships.duplicate()
	sorted.sort_custom(_ship_before)
	for model: Dictionary in GameData.ship_models:
		var model_ships := sorted.filter(func(ship: Ship) -> bool: return ship.model_id == model.id)
		if model_ships.is_empty():
			continue
		var grid := _add_group(model)
		for ship: Ship in model_ships:
			var tile := ShipTile.new(ship)
			tile.pressed.connect(_open_ship.bind(tile))
			grid.add_child(tile)
	%EmptyLabel.visible = GameState.ships.is_empty()
	%Header.visible = not GameState.ships.is_empty()
	_apply_filter()
	_size_tiles()
	_update_megas()


func _update_upgrade_all() -> void:
	var points := GameState.unspent_skill_points()
	_upgrade_all.text = "Upgrade all (%d)" % points if points > 0 else "Upgrade all"
	_upgrade_all.disabled = points == 0
	_upgrade_all_alert.visible = points > 0


## Shows each model's "Mega upgrade" button once it qualifies (all its ships
## owned, all at the top level; red dot if affordable, greyed with the reason if
## not), or its "★ Mega" badge once bought.
func _update_megas() -> void:
	for model_id: String in _megas:
		var entry: Array = _megas[model_id]
		var button: Button = entry[0]
		var error := GameState.mega_error(model_id)
		button.visible = GameState.mega_ready(model_id)
		button.disabled = not error.is_empty()
		button.tooltip_text = error if not error.is_empty() else "Every ship of this model gets 50% more speed and 50% more profit. Once per model."
		entry[1].visible = error.is_empty()
		entry[2].visible = GameState.has_mega(model_id)


## Every tile is an eighth of the row wide, so part-filled rows line up.
func _size_tiles() -> void:
	var width := floorf((%Groups.size.x - 2.0 * GROUP_PADDING - (COLUMNS - 1) * TILE_GAP) / COLUMNS)
	for entry: Array in _groups.values():
		for tile: ShipTile in entry[1].get_children():
			tile.custom_minimum_size.x = width


## A model's divider (name, then a rule) and its tile grid.
func _add_group(model: Dictionary) -> GridContainer:
	var color := GameData.category_color(model.get("category", ""))
	var group := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, GROUP_TINT)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(GROUP_PADDING)
	group.add_theme_stylebox_override(&"panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 4)
	group.add_child(box)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override(&"separation", 12)
	box.add_child(title_row)
	var title := Label.new()
	title.text = model.get("name", model.id)
	title.add_theme_color_override(&"font_color", color)
	title_row.add_child(title)
	var mega := Button.new()
	mega.add_theme_font_size_override(&"font_size", MEGA_FONT_SIZE)
	mega.text = "Mega upgrade: %s" % Fmt.money(GameState.mega_cost(model.id))
	mega.pressed.connect(GameState.buy_mega.bind(model.id))
	var mega_alert := AlertDot.new(4.0, Vector2(5, 5))
	mega.add_child(mega_alert)
	title_row.add_child(mega)
	var badge := Label.new()
	badge.text = "★ Mega: +50% speed and profit"
	badge.add_theme_font_size_override(&"font_size", MEGA_FONT_SIZE)
	badge.add_theme_color_override(&"font_color", MEGA_COLOR)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(badge)
	_megas[model.id] = [mega, mega_alert, badge]
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", TILE_GAP)
	grid.add_theme_constant_override(&"v_separation", TILE_GAP)
	box.add_child(grid)
	%Groups.add_child(group)
	_groups[model.id] = [group, grid]
	return grid


func _ship_before(a: Ship, b: Ship) -> bool:
	match %SortOption.get_selected_id():
		Sort.STATUS:
			if _status_rank(a) != _status_rank(b):
				return _status_rank(a) < _status_rank(b)
		Sort.PROFIT:
			if a.profit() != b.profit():
				return a.profit() > b.profit()
	return a.name.to_lower() < b.name.to_lower()


## Lost, then at risk, then held, then stopped, then running.
static func _status_rank(ship: Ship) -> int:
	if ship.is_lost():
		return 0
	if ship.at_risk:
		return 1
	if ship.is_held():
		return 2
	return 4 if ship.is_active() else 3


## Hides tiles that don't match the filter, and model groups left empty.
func _apply_filter() -> void:
	var filter: int = %FilterOption.get_selected_id()
	var shown := 0
	for model_id: String in _groups:
		var group: Control = _groups[model_id][0]
		var in_group := 0
		for tile: ShipTile in _groups[model_id][1].get_children():
			tile.visible = _matches(tile.ship, filter)
			in_group += 1 if tile.visible else 0
		group.visible = in_group > 0
		shown += in_group
	%CountLabel.text = "%d of %d ships" % [shown, GameState.ships.size()]


static func _matches(ship: Ship, filter: int) -> bool:
	match filter:
		Filter.ATTENTION:
			return not ship.attention_reason().is_empty()
		Filter.ACTIVE:
			return ship.is_active()
		Filter.STOPPED:
			return not ship.is_active()
		Filter.LOST:
			return ship.is_lost()
		Filter.RECOVERY:
			return ship.is_recovery()
	return true


func _open_ship(tile: ShipTile) -> void:
	var follow := func() -> Vector2:
		return tile.get_global_rect().get_center() if is_instance_valid(tile) else Vector2.ZERO
	PopupHost.find(self).show_ship(tile.ship, follow, tile.size.y / 2.0 + 8.0)

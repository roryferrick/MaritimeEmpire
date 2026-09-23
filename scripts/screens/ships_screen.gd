extends Control
## The player's ships, grouped by model (in shop order) under a labeled
## divider, five tiles wide, with sort (within each model) and filter options.
## Tiles are re-sorted when the fleet or the sort changes, not live, so they
## don't jump around; the filter follows each ship's status as it changes.

enum Sort { NAME, STATUS, PROFIT }
enum Filter { ALL, ACTIVE, STOPPED, LOST, RECOVERY }

const COLUMNS := 5
const TILE_GAP := 12
const SORT_NAMES := {Sort.NAME: "Name", Sort.STATUS: "Status (problems first)", Sort.PROFIT: "Profit"}
const FILTER_NAMES := {
	Filter.ALL: "All ships", Filter.ACTIVE: "Running (green)", Filter.STOPPED: "Stopped (red)",
	Filter.LOST: "Lost at sea", Filter.RECOVERY: "Recovery boats",
}

## Model id -> [group box, tile grid].
var _groups := {}


func _ready() -> void:
	for sort: Sort in SORT_NAMES:
		%SortOption.add_item(SORT_NAMES[sort], sort)
	for filter: Filter in FILTER_NAMES:
		%FilterOption.add_item(FILTER_NAMES[filter], filter)
	%SortOption.item_selected.connect(_rebuild.unbind(1))
	%FilterOption.item_selected.connect(_apply_filter.unbind(1))
	GameState.ships_changed.connect(_rebuild)
	GameState.ship_changed.connect(_apply_filter.unbind(1))
	%Groups.resized.connect(_size_tiles)
	_rebuild()


func _rebuild() -> void:
	for child in %Groups.get_children():
		%Groups.remove_child(child)
		child.queue_free()
	_groups.clear()
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


## Every tile is a fifth of the row wide, so part-filled rows line up.
func _size_tiles() -> void:
	var width := floorf((%Groups.size.x - (COLUMNS - 1) * TILE_GAP) / COLUMNS)
	for entry: Array in _groups.values():
		for tile: ShipTile in entry[1].get_children():
			tile.custom_minimum_size.x = width


## A model's divider (name, then a rule) and its tile grid.
func _add_group(model: Dictionary) -> GridContainer:
	var group := VBoxContainer.new()
	group.add_theme_constant_override(&"separation", 8)
	var title := Label.new()
	title.theme_type_variation = &"DimLabel"
	title.text = model.get("name", model.id)
	group.add_child(title)
	group.add_child(HSeparator.new())
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", TILE_GAP)
	grid.add_theme_constant_override(&"v_separation", TILE_GAP)
	group.add_child(grid)
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

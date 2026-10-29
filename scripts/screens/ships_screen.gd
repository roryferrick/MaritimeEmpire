# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Control
## The player's ships, grouped by model in the Shop's order under a heading per
## ship line, each group on a faint tint of its ship line's color under a title
## in that color, eight tiles wide, with sort (within each model) and filter
## options, and "Upgrade all" (with a red dot while any ship has points to
## spend). Tabs over the list, like the Shop's, show All, one company type
## (its lines) or the service ships, each with its count (a type the company
## has no ships or slots in is left out).
## Tiles are re-sorted when the fleet or the sort changes, not live, so they
## don't jump around; the filter follows each ship's status as it changes.

enum Sort { EARNINGS, NAME, STATUS, PROFIT }
enum Filter { ALL, ATTENTION, ACTIVE, STOPPED, LOST, RECOVERY, FISHING }

const COLUMNS := 8
## Fewer columns rather than tiles narrower than this (px).
const MIN_TILE_WIDTH := 100.0
## The picture of the model before each group's name (px): this long, and room
## for the widest model this tall.
const MODEL_PICTURE_SIZE := Vector2(72, 26)
## The page margins either side (see the scene), and room for the scrollbar.
const MARGIN := 24.0
const SCROLLBAR_ROOM := 12.0
const TILE_GAP := 6
## Each model group sits on a faint tint of its ship line's color (see
## GameData.category_color()), with this much padding inside.
const GROUP_TINT := 0.1
const GROUP_PADDING := 8
## The Mute button's text size, beside each model's name.
const MUTE_FONT_SIZE := 13
## The header's buttons' text size.
const HEADER_FONT_SIZE := 15
## The service ships' lines (the Service tab) and every line's heading.
const SERVICE_LINES := ["recovery", "tug", "icebreaker"]
const LINE_TITLES := {container = "Container ships", ore = "Ore carriers", breakbulk = "Breakbulk carriers", grain = "Grain carriers", livestock = "Livestock carriers", produce = "Fresh produce carriers",
	tanker = "Tankers", gas = "Gas carriers", vehicles = "Car carriers", boat_carriers = "Boat carriers", fishing = "Fishing boats", crabbing = "Crabbing boats", seafood = "Seafood carriers",
	recovery = "Recovery boats", tug = "Tugs", icebreaker = "Icebreakers", cruise_ocean = "Ocean cruisers", cruise_expedition = "Expedition cruisers", survey = "Survey vessels", mothership = "Deep-sea motherships"}
## The tabs' place under the header, and where the list starts below them (px).
const TABS_TOP := 60.0
const LIST_TOP := 100.0
const TAB_FONT_SIZE := 13
const SORT_NAMES := {Sort.EARNINGS: "Earnings", Sort.NAME: "Name", Sort.STATUS: "Status (problems first)", Sort.PROFIT: "Profit (all time)"}
## Sorted by earnings, the tiles re-sort this often (s) while the tab is open,
## and each time it opens.
const EARNINGS_RESORT_S := 30.0
const FILTER_NAMES := {
	Filter.ALL: "All ships", Filter.ATTENTION: "Needs attention",
	Filter.ACTIVE: "Running (green)", Filter.STOPPED: "Stopped (red)",
	Filter.LOST: "Lost at sea", Filter.RECOVERY: "Recovery boats and tugs", Filter.FISHING: "Fishing and crabbing boats",
}

## Model id -> [group box, tile grid].
var _groups := {}
## The tabs over the list: All, a tab per company type, Service; each tab's
## ship lines ([] for All), each line's heading, and each model group's line.
var _tabs := TabBar.new()
var _tab_names: Array[String] = []
var _tab_lines: Array = []
var _line_heads := {}
var _group_lines := {}
## The Fishing Grounds button: on the Seafood tab, and on All once the company fishes.
var _grounds := Button.new()
## Ship -> its tile.
var _tiles := {}
## Ships changed since the tab last caught up (as keys), and whether anything did.
var _changed_ships := {}
var _dirty := false
## The fleet changed (a ship bought or sold): rebuild the tiles when next shown.
var _needs_rebuild := false
## Each ship's profit over the last 30 days of game time (by name: GameState.recent_finances() over ship_window_seconds()),
## as of the last rebuild, and how long since it.
var _earnings := {}
var _resort_clock := 0.0


func _ready() -> void:
	for sort: Sort in SORT_NAMES:
		%SortOption.add_item(SORT_NAMES[sort], sort)
	%SortOption.tooltip_text = "Earnings: each ship's profit over the last %s of game time (%s of play), best first (left to right), re-sorted every 30 seconds." % [GameState.recent_window_text(), Fmt.duration(GameState.ship_window_seconds())]
	for filter: Filter in FILTER_NAMES:
		%FilterOption.add_item(FILTER_NAMES[filter], filter)
	%SortOption.item_selected.connect(_rebuild.unbind(1))
	%FilterOption.item_selected.connect(_apply_filter.unbind(1))
	GameState.ships_changed.connect(func() -> void: _needs_rebuild = true)
	GameState.ship_changed.connect(_on_ship_changed)
	GameState.company_types_changed.connect(func() -> void: _dirty = true)  # (A type taken shows its tab.)
	visibility_changed.connect(func() -> void:
		_dirty = true
		if is_visible_in_tree() and %SortOption.get_selected_id() == Sort.EARNINGS:
			_needs_rebuild = true)
	for control: Control in [%SortOption, %FilterOption]:
		control.add_theme_font_size_override(&"font_size", HEADER_FONT_SIZE)  # (Cinzel runs wide: a size down to fit the row.)
	_grounds.text = "Fishing Grounds"  # Where the fishing and crabbing boats go (FishingScreen): see _apply_filter().
	_grounds.add_theme_font_size_override(&"font_size", HEADER_FONT_SIZE)
	_grounds.tooltip_text = "Pick fishing grounds on the map and send your fishing and crabbing boats there by model."
	_grounds.pressed.connect(func() -> void: GameRoot.find(self).open_fishing_screen())
	%Header.add_child(_grounds)
	%Header.move_child(_grounds, %CountLabel.get_index())
	var uniforms := Button.new()  # What the crews wear (UniformsPage).
	uniforms.text = "Uniforms"
	uniforms.add_theme_font_size_override(&"font_size", HEADER_FONT_SIZE)
	uniforms.tooltip_text = "What your captains and crews wear on deck, ship by ship type."
	uniforms.pressed.connect(func() -> void: get_tree().root.add_child(UniformsPage.new()))
	%Header.add_child(uniforms)
	%Header.move_child(uniforms, %CountLabel.get_index())
	_add_tabs()
	$Scroll.resized.connect(_size_tiles)
	_rebuild()


## Ship changes are only noted as they come;
## the tab catches up once a frame, and only while it's open.
func _process(delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(delta)
	MapView._prof("proc.ships_screen", t_x)

func _process_timed(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_resort_clock += delta
	if %SortOption.get_selected_id() == Sort.EARNINGS and _resort_clock >= EARNINGS_RESORT_S:
		_needs_rebuild = true
	if _needs_rebuild:
		_rebuild()
	elif _dirty:
		for ship: Ship in _changed_ships:
			if _tiles.has(ship):
				_tiles[ship].refresh()
		_apply_filter()
	_changed_ships.clear()
	_dirty = false


func _on_ship_changed(ship: Ship) -> void:
	_changed_ships[ship] = true
	_dirty = true


func _rebuild() -> void:
	for child in %Groups.get_children():
		%Groups.remove_child(child)
		child.queue_free()
	_groups.clear()
	_line_heads.clear()
	_group_lines.clear()
	_tiles.clear()
	_needs_rebuild = false
	_earnings = GameState.recent_finances(null, GameState.ship_window_seconds()).ships
	_resort_clock = 0.0
	var sorted := GameState.fleet().duplicate()
	sorted.sort_custom(_ship_before)
	for model: Dictionary in _model_order():
		var model_ships := sorted.filter(func(ship: Ship) -> bool: return ship.model_id == model.id)
		if model_ships.is_empty():
			continue
		var line := str(model.get("category", ""))
		if not _line_heads.has(line):
			_line_heads[line] = _add_line_head(line)
		var grid := _add_group(model)
		_group_lines[model.id] = line
		for ship: Ship in model_ships:
			var tile := ShipTile.new(ship)
			_tiles[ship] = tile
			tile.pressed.connect(_open_ship.bind(tile))
			tile.show_earnings(float(_earnings.get(ship.name, 0.0)))
			grid.add_child(tile)
	%EmptyLabel.visible = GameState.fleet().is_empty()
	%Header.visible = not GameState.fleet().is_empty()
	_tabs.visible = %Header.visible
	_apply_filter()
	_size_tiles()


## Every tile is the same width, a row of up to COLUMNS (fewer if they'd be
## narrower than MIN_TILE_WIDTH), so part-filled rows line up. Worked out from
## the scroll area's width, which follows the screen (the activity log opening
## or closing, the window resizing), never from the tiles themselves.
func _size_tiles() -> void:
	var inner: float = $Scroll.size.x - MARGIN * 2.0 - SCROLLBAR_ROOM - 2.0 * GROUP_PADDING
	var columns := clampi(floori((inner + TILE_GAP) / (MIN_TILE_WIDTH + TILE_GAP)), 1, COLUMNS)
	var width := floorf((inner - (columns - 1) * TILE_GAP) / columns)
	for entry: Array in _groups.values():
		entry[1].columns = columns
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
	var picture := ShipPicture.new(model, MODEL_PICTURE_SIZE.x)  # The model, bow to the right, before its name.
	picture.custom_minimum_size = MODEL_PICTURE_SIZE
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(picture)
	var title := Label.new()
	title.text = model.get("name", model.id)
	title.add_theme_color_override(&"font_color", color)
	title_row.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(spacer)
	title_row.add_child(_mute_button(model.id))
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override(&"h_separation", TILE_GAP)
	grid.add_theme_constant_override(&"v_separation", TILE_GAP)
	box.add_child(grid)
	%Groups.add_child(group)
	_groups[model.id] = [group, grid]
	return grid


## Mutes a model's routine news in the activity log (its ships loading cargo,
## selling at a profit and entering canals; losses and trouble still show).
func _mute_button(model_id: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override(&"font_size", MUTE_FONT_SIZE)
	button.button_pressed = GameState.muted_models.has(model_id)
	var show_state := func(muted: bool) -> void:
		button.text = "Muted" if muted else "Mute"
		button.tooltip_text = ("Unmute: show these ships' loading, sales and canal entries in the activity log again." if muted
			else "Mute: leave these ships' loading, profitable sales and canal entries out of the activity log (losses and trouble still show).")
	show_state.call(button.button_pressed)
	button.toggled.connect(func(muted: bool) -> void:
		if muted and not GameState.muted_models.has(model_id):
			GameState.muted_models.append(model_id)
		elif not muted:
			GameState.muted_models.erase(model_id)
		show_state.call(muted))
	return button


func _ship_before(a: Ship, b: Ship) -> bool:
	match %SortOption.get_selected_id():
		Sort.EARNINGS:
			var earned_a := float(_earnings.get(a.name, 0.0))
			var earned_b := float(_earnings.get(b.name, 0.0))
			if earned_a != earned_b:
				return earned_a > earned_b
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


## Hides tiles that don't match the filter, model groups left empty or outside
## the tab, and line headings with nothing under them; counts each tab's ships
## (those the filter shows) on it, leaving out a company type's tab while the
## company has neither ships nor slots in it.
func _apply_filter() -> void:
	var filter: int = %FilterOption.get_selected_id()
	var lines: Array = _tab_lines[_tabs.current_tab] if _tabs.current_tab >= 0 else []
	var shown := 0
	var per_line := {}  # line -> ships the filter shows
	var owned := {}  # line -> ships owned
	for model_id: String in _groups:
		var group: Control = _groups[model_id][0]
		var line: String = _group_lines.get(model_id, "")
		var in_group := 0
		for tile: ShipTile in _groups[model_id][1].get_children():
			tile.visible = _matches(tile.ship, filter)
			in_group += 1 if tile.visible else 0
		per_line[line] = int(per_line.get(line, 0)) + in_group
		owned[line] = int(owned.get(line, 0)) + _groups[model_id][1].get_child_count()
		var in_tab := lines.is_empty() or lines.has(line)
		group.visible = in_group > 0 and in_tab
		shown += in_group if in_tab else 0
	for line: String in _line_heads:
		(_line_heads[line] as Control).visible = int(per_line.get(line, 0)) > 0 and (lines.is_empty() or lines.has(line))
	for tab in _tabs.tab_count:
		var count := 0
		var ships := 0
		for line: String in per_line:
			if (_tab_lines[tab] as Array).is_empty() or (_tab_lines[tab] as Array).has(line):
				count += int(per_line[line])
				ships += int(owned[line])
		var type_id :=Progression.type_of_category(str((_tab_lines[tab] as Array).front())) if not (_tab_lines[tab] as Array).is_empty() else ""
		var rated := not type_id.is_empty() and GameState.company.has_type(type_id)  # (Its stars beside its name: see Ratings.)
		_tabs.set_tab_title(tab, "%s%s (%d)" % [_tab_names[tab], " %.1f★" % GameState.ratings.stars(GameState.company, type_id) if rated else "", count])
		_tabs.set_tab_hidden(tab, tab > 0 and ships == 0 and (type_id.is_empty() or not GameState.company.has_type(type_id)))
	if _tabs.is_tab_hidden(_tabs.current_tab):
		_tabs.current_tab = 0
		return  # (tab_changed runs this again.)
	%CountLabel.text = "%d of %d ships" % [shown, GameState.fleet().size()]
	_grounds.visible = lines.has("fishing") or (lines.is_empty() and GameState.company.has_type("seafood"))


## The tabs over the list: All, each company type's (its Shop tab name), Service.
func _add_tabs() -> void:
	_tab_names.append("All")
	_tab_lines.append([])
	for type: Dictionary in Progression.company_types():
		_tab_names.append(str(type.get("tab", type.name)))
		_tab_lines.append(type.categories)
	_tab_names.append("Service")
	_tab_lines.append(SERVICE_LINES)
	for name: String in _tab_names:
		_tabs.add_tab(name)
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_tabs.offset_left = MARGIN
	_tabs.offset_right = -MARGIN
	_tabs.offset_top = TABS_TOP
	_tabs.offset_bottom = LIST_TOP - 4.0
	_tabs.clip_tabs = false
	UiFit.compact_tabs(_tabs, TAB_FONT_SIZE)  # (Nine tabs with their stars and counts fit across, beside the activity log.)
	_tabs.tab_changed.connect(_apply_filter.unbind(1))
	add_child(_tabs)
	$Scroll.offset_top = LIST_TOP


## Every model in the Shop's order: each company type's lines (as its tab
## lays them out), then the service ships', each line smallest first.
func _model_order() -> Array:
	var lines: Array = []
	for type: Dictionary in Progression.company_types():
		lines.append_array(type.categories)
	lines.append_array(SERVICE_LINES)
	var order: Array = []
	for line: String in lines:
		var models := GameData.ship_models.filter(func(model: Dictionary) -> bool: return model.get("category", "") == line)
		models.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("tier", 1)) < int(b.get("tier", 1)))
		order.append_array(models)
	for model: Dictionary in GameData.ship_models:  # (Any line not in a tab, last.)
		if not order.has(model):
			order.append(model)
	return order


## A ship line's heading over its model groups, in the line's color.
func _add_line_head(line: String) -> Label:
	var head := Label.new()
	head.theme_type_variation = &"HeaderLabel"
	head.text = str(LINE_TITLES.get(line, line.capitalize()))
	head.add_theme_color_override(&"font_color", GameData.category_color(line))
	%Groups.add_child(head)
	return head


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
			return ship.is_recovery() or ship.is_tug()
		Filter.FISHING:
			return ship.is_fishing()
	return true


func _open_ship(tile: ShipTile) -> void:
	var follow := func() -> Vector2:
		return tile.get_global_rect().get_center() if is_instance_valid(tile) else Vector2.ZERO
	PopupHost.find(self).show_ship(tile.ship, follow, tile.size.y / 2.0 + 8.0)

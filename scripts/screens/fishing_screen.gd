# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name FishingScreen
extends Control
## The Fishing Grounds screen (GameRoot.open_fishing_screen(), from the Ships
## tab and a fishing boat's popup): full screen, a gray map with every
## fishing ground the company's boats can get to (refuelling on the way:
## GameState.refuel_tree()) as a pie of the twelve months, January at the
## top going clockwise, each month's slice split between the colours of the
## species in season there then (Fisheries.species_color()), with pictures of
## the ground's species over it; hovering a picture says all about that
## species there, hovering a slice what's in season that month. On the right,
## the grounds picked (top: each opens FishAreaPopup to send boats there by
## model, where their catch lands and whether it's frozen) and the rest
## (below), best first by their quality over the year
## (Fisheries.ground_quality()). A ground is picked by clicking its pie or
## its row; picked ones are ringed in gold on the map with their boats.

signal finished

const SIDE_WIDTH := 440.0
## A pie's radius on screen (px): the ground's own size, kept between these.
const PIE_MIN_R := 9.0
const PIE_MAX_R := 72.0
## Pies smaller than this show no pictures (and no name unless picked).
const ICON_MIN_R := 24.0
const NAME_MIN_R := 20.0
const SELECTED_COLOR := Color(1.0, 0.8, 0.28)
const EMPTY_MONTH := Color(0.2, 0.22, 0.25, 0.9)
const PIE_EDGE := Color(0.05, 0.06, 0.08, 0.9)
const MONTH_NAMES := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
const MONTH_LETTERS := ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
const GEAR_WORDS := {troll = "trolled lines", net = "nets", trawl = "trawls", trap = "crab pots"}
const DEPTH_WORDS := {inshore = "Inshore", offshore = "Offshore", deep = "Deep water"}
## Rows in the lists: a little pie, the name, the quality bar.
const ROW_PIE := 30.0

var _map: MapView
var _pies := Control.new()
var _selected_box := VBoxContainer.new()
var _others_box := VBoxContainer.new()
var _note := Label.new()
var _tip := PanelContainer.new()
var _tip_text := RichTextLabel.new()
var _popup: FishAreaPopup = null
## The grounds the fleet can get to, best first, and their quality.
var _grounds: Array[String] = []
var _quality := {}
var _best_quality := 1.0
## Drawn this frame, for the mouse: ground -> [centre, radius, [[icon rect, species]...]].
var _drawn := {}
## What the mouse is over: {ground, species} or {ground, month}, or {}.
var _hover := {}
var _lists_dirty := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.add_theme_constant_override(&"separation", 0)
	add_child(row)
	_map = MapView.new()
	_map.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_map)
	_map.gray_mode = true
	_map.click_filter = _map_click
	_pies.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_pies.mouse_filter = MOUSE_FILTER_IGNORE
	_pies.texture_filter = TEXTURE_FILTER_LINEAR  # (The species art has no mipmaps: sampling them as if it had draws blank.)
	_pies.draw.connect(_draw_pies)
	_map.add_child(_pies)
	_map.view_changed.connect(_pies.queue_redraw)
	row.add_child(_side())
	_tip.theme_type_variation = &"MapPopup"
	_tip.top_level = true
	_tip.mouse_filter = MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.scroll_active = false
	_tip_text.custom_minimum_size = Vector2(320, 0)
	for font_size: StringName in [&"normal_font_size", &"bold_font_size", &"italics_font_size", &"bold_italics_font_size"]:
		_tip_text.add_theme_font_size_override(font_size, 15)
	_tip_text.mouse_filter = MOUSE_FILTER_IGNORE
	_tip.add_child(_tip_text)
	add_child(_tip)
	GameState.fish_areas_changed.connect(func() -> void: _lists_dirty = true)
	GameState.ships_changed.connect(func() -> void: _lists_dirty = true)


func _side() -> Control:
	var side := PanelContainer.new()
	side.theme_type_variation = &"BarPanel"
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	var content := VBoxContainer.new()
	content.add_theme_constant_override(&"separation", 8)
	side.add_child(content)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.text = "Fishing grounds"
	content.add_child(title)
	_note.theme_type_variation = &"DimLabel"
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_note)
	content.add_child(_heading("Your grounds"))
	content.add_child(_scroll(_selected_box, 0.8))
	content.add_child(HSeparator.new())
	content.add_child(_heading("All grounds your boats can reach, best first"))
	content.add_child(_scroll(_others_box, 1.2))
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 44)
	done.pressed.connect(_close)
	content.add_child(done)
	return side


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 17)
	return label


func _scroll(box: VBoxContainer, share: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.size_flags_stretch_ratio = share
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override(&"separation", 4)
	scroll.add_child(box)
	return scroll


func open() -> void:
	_find_grounds()
	_rebuild_lists()
	await get_tree().process_frame
	_map.reset_view(GameState.home_port)


func _close() -> void:
	if _popup != null:
		_popup.queue_free()
		_popup = null
	_tip.visible = false
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		if _popup != null:
			_popup.queue_free()
			_popup = null
		else:
			_close()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _lists_dirty:
		_lists_dirty = false
		_rebuild_lists()
		_pies.queue_redraw()
	var over := {}
	var mouse := _pies.get_local_mouse_position()
	if Rect2(Vector2.ZERO, _pies.size).has_point(mouse) and _popup == null:
		over = _hit(mouse)
	if over != _hover:
		_hover = over
		_pies.queue_redraw()
		_show_tip()
	if _tip.visible:
		var at := get_viewport().get_mouse_position() + Vector2(18, 14)
		var room := get_viewport_rect().size - _tip.size - Vector2(8, 8)
		_tip.position = at.clamp(Vector2(8, 8), room)


# --- Which grounds -----------------------------------------------------------

## Every ground some boat of the company can work (its gear and depth) from a
## port it can get to from its base, refuelling on the way, with a trip from
## that port reaching the ground; best first.
func _find_grounds() -> void:
	var fish := Fisheries.shared()
	var seen := {}
	var boats := {}  # [model, base] -> a boat
	for ship in GameState.fleet():
		if ship.is_fishing() and not ship.base_port.is_empty():
			boats[[ship.model_id, ship.base_port]] = ship
	for key: Array in boats:
		var ship: Ship = boats[key]
		var base := str(key[1])
		var model := ship.model()
		var reach := ship.range_nm()
		var tree := GameState.refuel_tree(ship, base)
		for ground_id: String in fish.ground_order:
			if seen.has(ground_id) or not fish.model_works_ground(model, ground_id):
				continue
			for port: String in fish.grounds[ground_id].get("ports", []):
				if (port == base or (tree.prev as Dictionary).has(port)) and fish.miles_to(port, ground_id) <= reach:
					seen[ground_id] = true
					break
	# Picked grounds stay listed even if no boat can get there now.
	for ground_id: String in GameState.company.fish_areas:
		seen[ground_id] = true
	_grounds.clear()
	_quality.clear()
	_best_quality = 0.0001
	for ground_id: String in seen:
		_grounds.append(ground_id)
		_quality[ground_id] = fish.ground_quality(ground_id)
		_best_quality = maxf(_best_quality, float(_quality[ground_id]))
	_grounds.sort_custom(func(a: String, b: String) -> bool: return float(_quality[a]) > float(_quality[b]))
	var owned := 0
	for ship in GameState.fleet():
		if ship.is_fishing():
			owned += 1
	if owned == 0:
		_note.text = "You have no fishing or crabbing boats yet: buy some in the Shop (the Seafood tab), and the grounds they can reach show here."
	else:
		_note.text = "The %d grounds your %d boats can reach, refuelling on the way where they must. Each pie is the year, January at the top going clockwise, coloured by what's in season each month. Click a ground to pick it, then send boats there." % [_grounds.size(), owned]


# --- The lists ------------------------------------------------------------------

func _rebuild_lists() -> void:
	for box: VBoxContainer in [_selected_box, _others_box]:
		for child in box.get_children():
			child.queue_free()
	var picked: Dictionary = GameState.company.fish_areas
	for ground_id: String in _grounds:
		if picked.has(ground_id):
			_selected_box.add_child(_row(ground_id, true))
	if picked.is_empty():
		var hint := Label.new()
		hint.theme_type_variation = &"DimLabel"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "None yet: click a ground on the map or in the list below."
		_selected_box.add_child(hint)
	for ground_id: String in _grounds:
		if not picked.has(ground_id):
			_others_box.add_child(_row(ground_id, false))


func _row(ground_id: String, picked: bool) -> Control:
	var fish := Fisheries.shared()
	var ground: Dictionary = fish.grounds[ground_id]
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel" if picked else &""
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	panel.add_child(row)
	var pie := Control.new()
	pie.custom_minimum_size = Vector2(ROW_PIE, ROW_PIE)
	pie.mouse_filter = MOUSE_FILTER_IGNORE
	pie.draw.connect(func() -> void: draw_pie(pie, ground_id, pie.size / 2.0, ROW_PIE / 2.0 - 1.0, -1))
	row.add_child(pie)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.add_theme_constant_override(&"separation", 0)
	row.add_child(words)
	var name_label := Label.new()  # (Click it to show the ground on the map.)
	name_label.text = Fisheries.short_ground_name(ground_id)
	name_label.clip_text = true
	name_label.mouse_filter = MOUSE_FILTER_STOP
	name_label.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var full := Fisheries.ground_name(ground_id)
	name_label.tooltip_text = "%s: click to show it on the map" % (full.substr(0, 1).to_upper() + full.substr(1))
	name_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_map.look_at_lon_lat(Vector2(float(ground.lon), float(ground.lat))))
	words.add_child(name_label)
	var detail := Label.new()
	detail.theme_type_variation = &"DimLabel"
	detail.add_theme_font_size_override(&"font_size", 13)
	detail.clip_text = true
	var boats := 0
	for ship in GameState.fleet():
		if ship.fish_area == ground_id and ship.is_fishing():
			boats += 1
	var share := float(_quality.get(ground_id, 0.0)) / _best_quality
	detail.text = "%s · %d species · quality %d%s" % [DEPTH_WORDS.get(str(ground.get("depth", "")), ""), (ground.species as Dictionary).size(),
		roundi(share * 100.0), (" · %d boat%s" % [boats, "" if boats == 1 else "s"]) if picked else ""]
	words.add_child(detail)
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(0, 4)
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	bar.draw.connect(func() -> void:
		bar.draw_rect(Rect2(Vector2.ZERO, bar.size), Color(1, 1, 1, 0.08))
		bar.draw_rect(Rect2(Vector2.ZERO, Vector2(bar.size.x * share, bar.size.y)), SELECTED_COLOR.lerp(Color(0.4, 0.8, 0.5), 1.0 - share)))
	words.add_child(bar)
	if picked:
		var boats_button := Button.new()
		boats_button.text = "Boats…"
		boats_button.tooltip_text = "Send boats here by model, and say where their catch lands"
		boats_button.pressed.connect(_open_popup.bind(ground_id))
		row.add_child(boats_button)
		var drop := Button.new()
		drop.text = "X"
		drop.flat = true
		drop.tooltip_text = "Drop this ground (its boats go back to fishing the best within reach of their ports)"
		drop.pressed.connect(func() -> void: GameState.select_fish_area(ground_id, false))
		row.add_child(drop)
	else:
		var pick := Button.new()
		pick.text = "Pick"
		pick.tooltip_text = "Add it to your grounds"
		pick.pressed.connect(_pick.bind(ground_id))
		row.add_child(pick)
	return panel


func _pick(ground_id: String) -> void:
	GameState.select_fish_area(ground_id, true)
	_open_popup(ground_id)


func _open_popup(ground_id: String) -> void:
	if _popup != null:
		_popup.queue_free()
	_tip.visible = false
	_popup = FishAreaPopup.new(ground_id)
	_popup.tree_exited.connect(func() -> void:
		_popup = null
		_lists_dirty = true)
	add_child(_popup)


# --- The map -------------------------------------------------------------------

func _map_click(at: Vector2) -> bool:
	var hit := _hit(at)
	if hit.is_empty():
		return false
	var ground_id := str(hit.ground)
	if GameState.company.fish_areas.has(ground_id):
		_open_popup(ground_id)
	else:
		_pick(ground_id)
	return true


## The ground (and the species picture or month slice) under a point on the map, or {}.
func _hit(at: Vector2) -> Dictionary:
	var best := {}
	var best_r := INF
	for ground_id: String in _drawn:
		var entry: Array = _drawn[ground_id]
		var center: Vector2 = entry[0]
		var r: float = entry[1]
		if at.distance_to(center) > r + 2.0:
			continue
		for icon: Array in entry[2]:
			if (icon[0] as Rect2).has_point(at):
				return {ground = ground_id, species = icon[1]}
		if r < best_r:  # (The smaller of overlapping pies: it's on top.)
			best_r = r
			var angle := fposmod((at - center).angle() + PI / 2.0, TAU)
			best = {ground = ground_id, month = clampi(int(angle / TAU * 12.0), 0, 11)}
	return best


func _draw_pies() -> void:
	_drawn.clear()
	var fish := Fisheries.shared()
	var picked: Dictionary = GameState.company.fish_areas
	var font := get_theme_default_font()
	var month := GameState.fishing_month()
	var view := Rect2(Vector2.ZERO, _pies.size)
	# Biggest first, so the small ones lie on top; the picked last of all.
	var order := []
	for ground_id: String in _grounds:
		var ground: Dictionary = fish.grounds[ground_id]
		var lon_lat := Vector2(float(ground.lon), float(ground.lat))
		var center := _map.lon_lat_screen_position(lon_lat)
		if center == Vector2.INF or not view.grow(PIE_MAX_R).has_point(center):
			continue
		var degrees := float(ground.get("radius_nm", 30.0)) / 60.0
		var edge := _map.lon_lat_screen_position(lon_lat + Vector2(degrees / maxf(cos(deg_to_rad(lon_lat.y)), 0.2), 0.0))
		var r := clampf(center.distance_to(edge) if edge != Vector2.INF else PIE_MIN_R, PIE_MIN_R, PIE_MAX_R)
		order.append([ground_id, center, r, picked.has(ground_id)])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[3] == b[3] and a[2] > b[2] or (not a[3] and b[3]))
	for item: Array in order:
		var ground_id: String = item[0]
		var center: Vector2 = item[1]
		var r: float = item[2]
		var is_picked: bool = item[3]
		var hovered := str(_hover.get("ground", "")) == ground_id
		draw_pie(_pies, ground_id, center, r, month, int(_hover.get("month", -1)) if hovered else -1)
		if is_picked:
			_pies.draw_arc(center, r + 3.0, 0.0, TAU, 48, SELECTED_COLOR, 3.0, true)
		elif hovered:
			_pies.draw_arc(center, r + 2.0, 0.0, TAU, 48, Color(1, 1, 1, 0.9), 2.0, true)
		var icons := []
		if r >= ICON_MIN_R:
			icons = _draw_icons(ground_id, center, r)
		_drawn[ground_id] = [center, r, icons]
		if is_picked or r >= NAME_MIN_R or hovered:
			var text := Fisheries.short_ground_name(ground_id)
			if is_picked:
				var boats := 0
				for ship in GameState.fleet():
					if ship.fish_area == ground_id and ship.is_fishing():
						boats += 1
				text += " · %d boat%s" % [boats, "" if boats == 1 else "s"]
			var font_size := 13
			var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var pos := center + Vector2(-width / 2.0, r + font_size + 4.0)
			_pies.draw_string(font, pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.8))
			_pies.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, SELECTED_COLOR if is_picked else Color.WHITE)


## A ground's year as a pie on `canvas`: twelve slices, January at the top
## going clockwise, each split between its in-season species' colours (dark
## when nothing's in season). `now` (0-11) gets a white edge, `lit` a brighter one.
static func draw_pie(canvas: CanvasItem, ground_id: String, center: Vector2, r: float, now := -1, lit := -1) -> void:
	var fish := Fisheries.shared()
	var steps := 3 if r < 16.0 else 6
	canvas.draw_circle(center, r + 1.0, PIE_EDGE)
	for month in 12:
		var start := -PI / 2.0 + month * TAU / 12.0
		var span := TAU / 12.0
		var here := fish.in_season_at(ground_id, month)
		var parts: Array = here if not here.is_empty() else [""]
		for i in parts.size():
			var a0 := start + span * i / parts.size()
			var a1 := start + span * (i + 1) / parts.size()
			var points := PackedVector2Array([center])
			for k in steps + 1:
				var a := lerpf(a0, a1, float(k) / steps)
				points.append(center + Vector2(cos(a), sin(a)) * r)
			var color: Color = EMPTY_MONTH if parts[i] == "" else fish.species_color(parts[i])
			if month == lit:
				color = color.lightened(0.3)
			canvas.draw_colored_polygon(points, color)
		# The slice's edges.
		canvas.draw_line(center, center + Vector2(cos(start), sin(start)) * r, PIE_EDGE, 1.0 if r >= 16.0 else 0.6, true)
	if now >= 0 and r >= 12.0:
		var a0 := -PI / 2.0 + now * TAU / 12.0
		canvas.draw_arc(center, r - 0.8, a0, a0 + TAU / 12.0, 6, Color(1, 1, 1, 0.95), 1.6, true)
	if r >= 46.0:  # Big enough: the months' letters round the rim.
		var font := ThemeDB.fallback_font
		for month in 12:
			var a := -PI / 2.0 + (month + 0.5) * TAU / 12.0
			var at := center + Vector2(cos(a), sin(a)) * (r + 9.0) - Vector2(4, -4)
			canvas.draw_string(font, at, MONTH_LETTERS[month], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))


## Each species' picture, kept: a texture loaded in a draw and let go is
## freed before it's drawn (it shows white).
var _arts := {}

func _art(species_id: String) -> Texture2D:
	if not _arts.has(species_id):
		_arts[species_id] = Fisheries.shared().species_art(species_id)
	return _arts[species_id]


## The ground's species' pictures over its pie, round its middle; their rects (for the mouse).
func _draw_icons(ground_id: String, center: Vector2, r: float) -> Array:
	var fish := Fisheries.shared()
	var species: Array = (fish.grounds[ground_id].species as Dictionary).keys()
	var n := species.size()
	var side := clampf(r * (0.62 if n <= 2 else 0.5), 14.0, 34.0)
	var ring := 0.0 if n == 1 else r * (0.42 if n <= 3 else 0.55)
	var out := []
	for i in n:
		var species_id: String = species[i]
		var a := -PI / 2.0 + i * TAU / n
		var at := center + Vector2(cos(a), sin(a)) * ring
		var hovered := str(_hover.get("species", "")) == species_id and str(_hover.get("ground", "")) == ground_id
		_pies.draw_circle(at, side * 0.6, Color(0.04, 0.06, 0.1, 0.78))
		_pies.draw_arc(at, side * 0.6, 0.0, TAU, 20, fish.species_color(species_id).lightened(0.2) if not hovered else Color.WHITE, 1.5 if not hovered else 2.5, true)
		var texture := _art(species_id)
		var box := Rect2(at - Vector2(side, side) / 2.0, Vector2(side, side))
		if texture != null:
			var aspect := float(texture.get_width()) / maxf(texture.get_height(), 1.0)
			# Long thin fish reach past the circle a little, so they read at this size.
			var size := Vector2(side * 1.35, side * 1.35 / aspect) if aspect >= 1.6 else (Vector2(side, side / aspect) if aspect >= 1.0 else Vector2(side * aspect, side)) * 0.95
			_pies.draw_texture_rect(texture, Rect2(at - size / 2.0, size), false)
		else:
			_pies.draw_circle(at, side * 0.3, fish.species_color(species_id))
		out.append([box, species_id])
	return out


# --- Hover details ---------------------------------------------------------------

func _show_tip() -> void:
	if _hover.is_empty():
		_tip.visible = false
		return
	var fish := Fisheries.shared()
	var ground_id := str(_hover.ground)
	var ground: Dictionary = fish.grounds[ground_id]
	var full := Fisheries.ground_name(ground_id)
	var text := "[b]%s[/b]\n" % (full.substr(0, 1).to_upper() + full.substr(1))
	if _hover.has("species"):
		var species_id := str(_hover.species)
		var species: Dictionary = fish.species[species_id]
		var at: Dictionary = ground.species[species_id]
		var density := float(at.get("density", 1.0))
		var family: Dictionary = fish.families.get(fish.family_of(species_id), {})
		text += "[color=#%s][b]%s[/b][/color]" % [fish.species_color(species_id).lightened(0.25).to_html(false), fish.species_name(species_id)]
		if not str(species.get("latin", "")).is_empty():
			text += "  [i]%s[/i]" % species.latin
		text += "\n%s, caught with %s" % [str(family.get("name", "")), GEAR_WORDS.get(str(species.get("gear", "")), str(species.get("gear", "")))]
		text += "\nIn season: %s" % fish.season_text(ground_id, species_id)
		text += "\nHere the catch is %s (%.1f)" % ["rich" if density >= 1.2 else ("fair" if density >= 0.6 else "thin"), density]
		var stock := float(GameState.fish_stocks.get("%s>%s" % [ground_id, species_id], 1.0))
		if stock < 0.99:
			text += ", the stock at %d%% (it grows back over the year)" % roundi(stock * 100.0)
		text += "\nAbout %s a crate (%s a ton landed, grade x%.2f)" % [Fmt.money(roundi(float(family.get("base", 0.0)) * float(species.get("grade", 1.0)) / 40.0)),
			Fmt.money(roundi(float(family.get("base", 0.0)) * float(species.get("grade", 1.0)))), float(species.get("grade", 1.0))]
		if bool(species.get("trophy", false)):
			text += "\nA trophy fish: now and then a small trolling boat lands one giant that fills its hold."
		var models := PackedStringArray()
		for model: Dictionary in GameData.ship_models:
			if fish.can_work(model, ground_id, species_id):
				models.append(str(model.name))
		text += "\n[color=#a8c8e8]Caught by: %s[/color]" % (", ".join(models) if not models.is_empty() else "none of the boats (wrong gear or depth)")
		if not str(species.get("fact", "")).is_empty():
			text += "\n\n[i]%s[/i]" % species.fact
	else:
		var month := int(_hover.month)
		var here := fish.in_season_at(ground_id, month)
		text += "%s · %s · quality %d%%\n" % [DEPTH_WORDS.get(str(ground.get("depth", "")), ""), MONTH_NAMES[month], roundi(float(_quality.get(ground_id, 0.0)) / _best_quality * 100.0)]
		if here.is_empty():
			text += "Nothing in season in %s." % MONTH_NAMES[month]
		for species_id in here:
			text += "[color=#%s]■[/color] %s\n" % [fish.species_color(species_id).to_html(false), fish.species_name(species_id)]
		if fish.rough(ground_id, month):
			text += "[color=#ff9a7a]Rough seas in %s: boats wear %.1fx as fast.[/color]\n" % [MONTH_NAMES[month], Fisheries.ROUGH_WEAR]
		text += "[color=#cccccc]Click to %s.[/color]" % ("send boats" if GameState.company.fish_areas.has(ground_id) else "pick this ground")
	_tip_text.text = text.strip_edges()
	_tip.reset_size()
	_tip.visible = true

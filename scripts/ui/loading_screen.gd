# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name LoadingScreen
extends CanvasLayer
## A loading screen over everything: a dark sea with ships of every kind
## sailing across it, in from off one side and out off another, each coming
## back on somewhere else (their hulls and details from art/ships, in their
## models' colors, with a wake), "Maritime Empire" and "Loading" with its dots.
## Shown when the game opens, till the title screen's scenes are loaded and
## the world's art is built (show_until()), and when a save is continued, a
## company founded or a game joined, till the game is up and its map warm
## (open_game(): the land sorted, the sea animals' paths found, the birds
## made, the lanes bent and a few frames drawn; see MapView.is_warm()). Stays
## at least MIN_S, then fades out over FADE_S. Lives under the tree's root, so
## it outlasts the change of scene it covers.

const MIN_S := 0.9
const FADE_S := 0.45
const SHIPS := 9
const GAME_SCENE := "res://scenes/game.tscn"
const SEA := Color("#10233a")
const SEA_DEEP := Color("#0a1726")
const WAKE := Color(0.85, 0.93, 1.0)
const WAVES := 40
## A ship's length on screen (px) for the longest model, and the least any is drawn.
const LONGEST_PX := 250.0
const SHORTEST_PX := 90.0
const SPEED_PX := Vector2(45.0, 120.0)
const TITLE_SIZE := 44
const NOTE_SIZE := 22

## Returns true once what the screen waits for is ready (checked every frame
## after MIN_S); not set, the screen just shows for MIN_S.
var until := Callable()
## Builds the world's art while up (the game's first map open then has it).
var warm_world := false

var _page := Control.new()
var _ships := []  # {art, color, at, heading, speed, length, width, seed}
var _waves := []  # {at, length, speed, alpha}
var _art := {}  # category -> MapView.load_ship_art()
var _elapsed := 0.0
var _fading := false
var _warmed := false
var _rng := RandomNumberGenerator.new()


## Shows a loading screen till `ready` says so (see until).
static func show_until(tree: SceneTree, ready: Callable, warm := false) -> LoadingScreen:
	var screen := LoadingScreen.new()
	screen.until = ready
	screen.warm_world = warm
	tree.root.add_child.call_deferred(screen)  # (Often asked for while the tree is busy adding a scene.)
	return screen


## Shows a loading screen and opens the game (scenes/game.tscn) under it: the
## screen stays till the game's map is warm (GameRoot.is_warm()). The scene
## changes once the screen has been drawn, so the stall of building the map
## happens behind it.
static func open_game(tree: SceneTree) -> void:
	show_until(tree, func() -> bool:
		var root := tree.get_first_node_in_group(GameRoot.GROUP)
		return root != null and root.is_warm())
	for i in 3:
		await tree.process_frame
	tree.change_scene_to_file(GAME_SCENE)


func _ready() -> void:
	layer = 100
	_rng.randomize()
	_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_page.mouse_filter = Control.MOUSE_FILTER_STOP
	_page.draw.connect(_draw_page)
	add_child(_page)
	var size := _page.get_viewport_rect().size
	for i in WAVES:
		_waves.append({at = Vector2(_rng.randf() * size.x, _rng.randf() * size.y), length = _rng.randf_range(10.0, 36.0),
			speed = _rng.randf_range(4.0, 12.0), alpha = _rng.randf_range(0.06, 0.16)})
	for i in SHIPS:
		var ship := _spawn(size)
		if i % 2 == 0:
			ship.at = Vector2(_rng.randf() * size.x, _rng.randf() * size.y)  # Already crossing.
		_ships.append(ship)
	_ships.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.length < b.length)


## A ship of a random model with art, coming on from off a random side, headed
## across to the far side (a little off straight), at its own speed.
func _spawn(size: Vector2) -> Dictionary:
	var models: Array = GameData.ship_models.filter(func(m: Dictionary) -> bool: return not _ship_art(str(m.get("art", m.get("category", "")))).is_empty())
	var longest := 1.0
	for m: Dictionary in models:
		longest = maxf(longest, float((m.get("map_size", [14, 6]) as Array)[0]))
	var model: Dictionary = models[_rng.randi() % models.size()] if not models.is_empty() else {}
	var dims: Array = model.get("map_size", [14, 6])
	var length := lerpf(SHORTEST_PX, LONGEST_PX, float(dims[0]) / longest)
	var art := _ship_art(str(model.get("art", model.get("category", ""))))
	var hull: Texture2D = art.get("hull")
	var width := length * (float(hull.get_height()) / float(hull.get_width()) if hull != null else 52.0 / 180.0)
	var side := _rng.randi() % 4  # 0 from the left, 1 the right, 2 the top, 3 the bottom.
	var heading: float = [0.0, PI, PI / 2.0, -PI / 2.0][side] + _rng.randf_range(-0.35, 0.35)
	var at: Vector2
	match side:
		0: at = Vector2(-length, _rng.randf_range(0.08, 0.92) * size.y)
		1: at = Vector2(size.x + length, _rng.randf_range(0.08, 0.92) * size.y)
		2: at = Vector2(_rng.randf_range(0.08, 0.92) * size.x, -length)
		_: at = Vector2(_rng.randf_range(0.08, 0.92) * size.x, size.y + length)
	return {art = art, color = Color.from_string(str(model.get("map_color", "#ffffff")), Color.WHITE), at = at, heading = heading,
		speed = _rng.randf_range(SPEED_PX.x, SPEED_PX.y), length = length, width = width, seed = _rng.randf() * TAU}


func _ship_art(category: String) -> Dictionary:
	if not _art.has(category):
		_art[category] = MapView.load_ship_art(category) if not category.is_empty() else {}
	return _art[category]


func _process(delta: float) -> void:
	_elapsed += delta
	var size := _page.get_viewport_rect().size
	for ship: Dictionary in _ships:
		var heading: float = ship.heading + sin(_elapsed * 0.6 + float(ship.seed)) * 0.06
		ship.at += Vector2.from_angle(heading) * float(ship.speed) * delta
		var margin: float = float(ship.length) * 1.3
		if ship.at.x < -margin or ship.at.x > size.x + margin or ship.at.y < -margin or ship.at.y > size.y + margin:
			var again := _spawn(size)
			for key in again:
				ship[key] = again[key]
	for wave: Dictionary in _waves:
		wave.at.x -= float(wave.speed) * delta
		if wave.at.x < -40.0:
			wave.at = Vector2(size.x + 40.0, _rng.randf() * size.y)
	_page.queue_redraw()
	# The world's art, once a frame of this has shown (it takes a moment).
	if warm_world and not _warmed and _elapsed > 0.1:
		_warmed = true
		MapView._world_meshes()
	if not _fading and _elapsed >= MIN_S and (not until.is_valid() or until.call()):
		_fading = true
		var tween := create_tween()
		tween.tween_property(_page, "modulate:a", 0.0, FADE_S)
		tween.tween_callback(queue_free)


func _draw_page() -> void:
	var size := _page.size
	_page.draw_rect(Rect2(Vector2.ZERO, size), SEA)
	# Deeper water in broad bands, and little waves drifting by.
	for k in 5:
		var y := size.y * (0.1 + k * 0.2)
		_page.draw_rect(Rect2(0.0, y, size.x, size.y * 0.09), Color(SEA_DEEP, 0.5))
	for wave: Dictionary in _waves:
		var at: Vector2 = wave.at
		_page.draw_line(at, at + Vector2(float(wave.length), 0.0), Color(WAKE, float(wave.alpha)), 2.0, true)
	for ship: Dictionary in _ships:
		_draw_ship(ship)
	var font := _page.get_theme_default_font()
	_page.draw_string(font, Vector2(0.0, size.y * 0.16), "Maritime Empire", HORIZONTAL_ALIGNMENT_CENTER, size.x, TITLE_SIZE, Color(1.0, 1.0, 1.0, 0.92))
	var dots := ".".repeat(1 + int(fmod(_elapsed * 2.0, 3.0)))
	_page.draw_string(font, Vector2(0.0, size.y * 0.9), "Loading" + dots, HORIZONTAL_ALIGNMENT_CENTER, size.x, NOTE_SIZE, Color(1.0, 1.0, 1.0, 0.7))


## A ship: its wake trailing astern, then its hull in its model's color and its details, bow the way it's going.
func _draw_ship(ship: Dictionary) -> void:
	var heading: float = ship.heading + sin(_elapsed * 0.6 + float(ship.seed)) * 0.06
	var length: float = ship.length
	var width: float = ship.width
	var at: Vector2 = ship.at
	var back := Vector2.from_angle(heading) * -1.0
	for k in 4:
		var from := at + back * length * (0.45 + k * 0.35)
		var to := at + back * length * (0.45 + (k + 1) * 0.35)
		_page.draw_line(from, to, Color(WAKE, 0.22 * (1.0 - k / 4.0)), width * (0.9 - k * 0.15), true)
	var art: Dictionary = ship.art
	if art.is_empty():
		return
	_page.draw_set_transform(at, heading, Vector2.ONE)
	var rect := Rect2(-length / 2.0, -width / 2.0, length, width)
	_page.draw_texture_rect(art.hull, rect, false, ship.color)
	_page.draw_texture_rect(art.details, rect, false)
	_page.draw_set_transform_matrix(Transform2D.IDENTITY)

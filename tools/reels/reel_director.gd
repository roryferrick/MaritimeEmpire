# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
extends Node
## Records the footage for the Instagram reels (marketing/reels/SCRIPTS.md,
## tools/reels/reels.json), frame by frame at 30 fps, as 1080x1920 JPGs, plus
## each reel's caption cards and end card as PNGs; tools/reels/build_reels.py
## puts them together with ffmpeg. Runs on a copy of a save in slot 8 (deleted
## after) and puts back the player's stats, settings and cosmetics files.
##
##   Godot --path . --fixed-fps 30 --audio-driver Dummy --resolution 540x960
##     res://tools/reels/reel_director.tscn -- --reel A [--shot name] [--cards-only]
##
## The game is drawn in an off-screen SubViewport (the monitor is too short for
## a portrait window): portrait 1080x1920 for map shots (bars hidden), or
## landscape 3840x2160 (the UI at 3x) for page shots, cropped round the part
## that matters and laid on the navy backdrop.

const FPS := 30
const OUT_W := 1080
const OUT_H := 1920
const NAVY := Color("#0e1f3d")
const UI_BASE := Vector2(1280, 720)
const LAND_SCALE := 3
## How wide the UI is laid out in portrait (px); the map's labels and buttons
## come out 1080 / this times their usual size.
const PORTRAIT_UI_W := 720
## Where a page crop's middle sits down the frame (the captions go above).
const CROP_CENTER_Y := 1040.0
const CROP_MAX_H := 1380.0
const SLOT := 8
const BACKED_UP := ["player_stats.json", "settings.cfg", "cosmetics.json"]
const OUT_ROOT := "res://marketing/reels/build/"

var vp: SubViewport
var game: GameRoot
var world: Node
var map: MapView
var plan: Dictionary
var _save_loaded := ""
## Unlock every market region on loading (no beige shading in the footage).
var unlock_all := true
## The game speed to hold (the level and achievement cards pause the game when they come up).
var _speed := 1
var _landscape := false
var _shot_seconds := {}


func _ready() -> void:
	Engine.max_fps = 0
	var reel := _arg("--reel", "A")  # (Several: "A,B,1".)
	var only := _arg("--shot", "")
	plan = JSON.parse_string(FileAccess.get_file_as_string("res://tools/reels/reels.json"))
	var reels := reel.split(",")
	for id in reels:
		if not plan.has(id):
			push_error("No reel " + id)
			get_tree().quit(1)
			return
	_backup_user_files()
	vp = SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.size = Vector2i(OUT_W, OUT_H)
	add_child(vp)
	var args := OS.get_cmdline_user_args()
	for id in reels:
		var beats: Array = plan[id].beats
		await _cards(id, beats)
		for beat: Dictionary in beats:
			for shot: Dictionary in beat.shots:
				var name := str(shot.shot)
				var seconds := float(shot.len) * float(shot.get("speed", 1.0)) + float(shot.get("from", 0.0)) + 0.4
				_shot_seconds[name] = maxf(seconds, float(_shot_seconds.get(name, 0.0)))
	if "--cards-only" not in args:
		for name: String in _shot_seconds:
			if not only.is_empty() and name not in only.split(","):
				continue
			# --missing: only shots not yet recorded long enough.
			var have := DirAccess.get_files_at(ProjectSettings.globalize_path(OUT_ROOT + "shots/" + name + "/")).size()
			if "--missing" in args and have >= ceili(float(_shot_seconds[name]) * FPS):
				continue
			if not has_method("shot_" + name):
				print("NO SHOT FUNCTION: ", name)
				continue
			print("shot ", name, " ", _shot_seconds[name], " s")
			await Callable(self, "shot_" + name).call(float(_shot_seconds[name]))
	await _unload()
	_restore_user_files()
	get_tree().quit()


func _arg(key: String, default: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(key)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else default


# --- The player's files, put back afterwards -------------------------------

## Copies of the player's files go to build/user_backup first (and a run
## killed halfway has them put back by the next run, before it copies afresh).
func _backup_user_files() -> void:
	var dir := ProjectSettings.globalize_path(OUT_ROOT + "user_backup/")
	if DirAccess.dir_exists_absolute(dir):
		_restore_user_files()
	DirAccess.make_dir_recursive_absolute(dir)
	for file: String in BACKED_UP:
		if FileAccess.file_exists("user://" + file):
			DirAccess.copy_absolute(ProjectSettings.globalize_path("user://" + file), dir + file)


func _restore_user_files() -> void:
	var dir := ProjectSettings.globalize_path(OUT_ROOT + "user_backup/")
	for file: String in BACKED_UP:
		var path := ProjectSettings.globalize_path("user://" + file)
		if FileAccess.file_exists(dir + file):
			DirAccess.copy_absolute(dir + file, path)
			DirAccess.remove_absolute(dir + file)
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save_%d.json" % SLOT))


# --- Loading a world ---------------------------------------------------------

## Loads a copy of a save (e.g. "save_2") into the game, unless it's loaded.
func use_save(save: String, fresh := false) -> void:
	var key := save + ("" if unlock_all else ":own regions")
	if _save_loaded == key and not fresh and is_instance_valid(game):
		return
	await _unload()
	var to := ProjectSettings.globalize_path("user://save_%d.json" % SLOT)
	DirAccess.copy_absolute(ProjectSettings.globalize_path("user://%s.json" % save), to)
	GameState.multiplayer_save = false
	var error := GameState.continue_game(SLOT)
	if not error.is_empty():
		push_error(error)
	GameState.company_name = "Harbour Line"  # (Not the save's own name on camera.)
	await _start_game()
	_save_loaded = key


## A brand new company (the intro's first ship), founded in slot 8.
func use_new_company(home: String) -> void:
	await _unload()
	GameState.multiplayer_save = false
	GameState.save_slot = SLOT
	GameState.new_game("Reel Shipping", home, "orange", {"storms": "moderate"})
	await _start_game()
	_save_loaded = "new:" + home


func _start_game() -> void:
	GameState.tutorials_on = false
	GameState.max_time_speed = 8
	game = load("res://scenes/game.tscn").instantiate()
	vp.add_child(game)
	world = game.find_child("WorldScreen")
	map = world.get_node("MapView")
	var waited := 0
	while not game.is_warm():
		await get_tree().process_frame
		waited += 1
		if waited % 600 == 0:
			print("  still warming: ", waited, " frames")
	Settings.night = "off"
	GameState.show_active_routes = true
	Settings.own_routes_only = false
	Cosmetics.equipped = ""  # The base ships, not the player's skin pack.
	for ship in GameState.ships:
		ship.skin = "base"
	GameState.time_speed = 1
	_quiet()


func _unload() -> void:
	if is_instance_valid(game):
		game.queue_free()
		game = null
		_save_loaded = ""
		for n in 3:
			await get_tree().process_frame


## No tutorial cards, level cards or bird cards over the footage.
func _quiet() -> void:
	GameState.time_speed = _speed
	if not is_instance_valid(game):
		return
	if not _cards_on:
		game.event_card.visible = false
	for node in game.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script == null:
			continue
		var path := script.resource_path
		if path.ends_with("tutorial_card.gd") or path.ends_with("sound_tracker.gd") or path.ends_with("event_card.gd") and not _cards_on:
			(node as CanvasItem).visible = false
	if not _landscape and world.get("_ticker") != null:
		(world.get("_ticker") as CanvasItem).visible = false  # (The news ticker re-shows itself as news comes in.)
	if is_instance_valid(map):
		map._night_shown = false  # (No quay lamps or town glows on camera, whatever the clock says at the port.)
	BirdLife.shared()._ships_frame = -1  # (The birds take the ships' places fresh each frame; on the wall clock they'd jump between slow frames.)


# --- Framing -----------------------------------------------------------------

## The map filling a portrait frame, no bars.
func portrait() -> void:
	_landscape = false
	if game.is_route_screen_open():
		game._close_route_screen()
	game.show_screen(GameRoot.Screen.WORLD)
	vp.size = Vector2i(OUT_W, OUT_H)
	vp.size_2d_override = Vector2i(PORTRAIT_UI_W, roundi(PORTRAIT_UI_W * float(OUT_H) / OUT_W))
	vp.size_2d_override_stretch = true
	_chrome(false)
	if world.get("_ticker") != null:
		(world.get("_ticker") as CanvasItem).modulate = Color(1, 1, 1, 0)  # (It re-shows itself as news comes in, after _quiet() has run.)


## The game as it's played (landscape, bars and all), cropped in rec().
func landscape() -> void:
	_landscape = true
	if is_instance_valid(game) and world.get("_ticker") != null:
		(world.get("_ticker") as CanvasItem).modulate = Color.WHITE
	vp.size = Vector2i(UI_BASE) * LAND_SCALE
	vp.size_2d_override = Vector2i(UI_BASE)
	vp.size_2d_override_stretch = true
	_chrome(true)


func _chrome(on: bool) -> void:
	for name in ["%TopBar", "%BottomNav", "%ActivityLogPanel"]:
		(game.get_node(name) as CanvasItem).visible = on
	for child in world.get_children():  # (The map's buttons and panels.)
		if child != map and child is CanvasItem:
			child.visible = on


func settle(frames := 20) -> void:
	for n in frames:
		_quiet()
		await get_tree().process_frame


## Runs the world on fast (not drawn) until done() or the seconds of play run out.
func warp(seconds: float, done := Callable(), speed := 8) -> bool:
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_speed = speed
	var start := GameState.play_time
	var ok := false
	var frames := 0
	while GameState.play_time - start < seconds:
		await get_tree().process_frame
		frames += 1
		GameState.time_speed = _speed
		if frames % 900 == 0:
			print("  warp: %.0f s of play" % (GameState.play_time - start))
		if done.is_valid() and done.call():
			ok = true
			break
	_speed = 1
	GameState.time_speed = 1
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return ok


func look(lon: float, lat: float, zoom: float) -> void:
	map.followed = null
	map._look_at(Geo.project(Vector2(lon, lat)))
	map._zoom = zoom
	map._zoom_goal = zoom
	map._changed()


## Follows a ship at a zoom of our own (follow_ship's own is for the birds).
func follow(ship: Ship, zoom: float) -> void:
	if map.followed != ship:
		map.follow_ship(ship)
	map._zoom = zoom
	map._zoom_goal = zoom
	map._changed()


func look_port(port_id: String, zoom: float) -> void:
	var port := GameData.get_port(port_id)
	look(float(port.lon), float(port.lat), zoom)


## Records a shot: per_frame(t) is called each frame (t in seconds from 0);
## in landscape the frame is cropped to crop(t), a Rect2 in the UI's 1280x720.
func rec(name: String, seconds: float, per_frame := Callable(), crop := Callable()) -> void:
	var dir := ProjectSettings.globalize_path(OUT_ROOT + "shots/" + name + "/")
	DirAccess.make_dir_recursive_absolute(dir)
	for old in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + old)
	var frames := ceili(seconds * FPS)
	var tasks: Array[int] = []
	for i in frames:
		var t := float(i) / FPS
		if per_frame.is_valid():
			per_frame.call(t)
		_quiet()
		await RenderingServer.frame_post_draw
		var image := vp.get_texture().get_image()
		if _landscape:
			var rect: Rect2 = crop.call(t) if crop.is_valid() else Rect2(Vector2.ZERO, UI_BASE)
			image = _compose(image, rect)
		elif image.get_format() != Image.FORMAT_RGB8:
			image.convert(Image.FORMAT_RGB8)
		var path := dir + "%04d.jpg" % i
		tasks.append(WorkerThreadPool.add_task(func() -> void: image.save_jpg(path, 0.93)))
	for task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	print("  recorded ", name, ": ", frames, " frames")


## A part of the landscape UI, scaled to the frame's width (or CROP_MAX_H
## high), on the navy backdrop.
func _compose(image: Image, rect: Rect2) -> Image:
	var scale := float(image.get_width()) / UI_BASE.x
	var px := Rect2i(Vector2i(rect.position * scale), Vector2i(rect.size * scale)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var part := image.get_region(px)
	part.convert(Image.FORMAT_RGB8)
	var fit := minf(float(OUT_W) / px.size.x, CROP_MAX_H / px.size.y)
	var size := Vector2i(roundi(px.size.x * fit), roundi(px.size.y * fit))
	part.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)
	var canvas := Image.create_empty(OUT_W, OUT_H, false, Image.FORMAT_RGB8)
	canvas.fill(NAVY)
	canvas.blit_rect(part, Rect2i(Vector2i.ZERO, size), Vector2i((OUT_W - size.x) / 2, roundi(CROP_CENTER_Y - size.y / 2.0)))
	return canvas


## A crop easing from one rect to another over the shot.
static func push(from: Rect2, to: Rect2, seconds: float) -> Callable:
	return func(t: float) -> Rect2:
		var k := ease(clampf(t / seconds, 0.0, 1.0), -2.0)
		return Rect2(from.position.lerp(to.position, k), from.size.lerp(to.size, k))


static func grow(rect: Rect2, by: float) -> Rect2:
	return rect.grow(by).intersection(Rect2(Vector2.ZERO, UI_BASE))


# --- Caption and end cards ---------------------------------------------------

func _cards(reel: String, beats: Array) -> void:
	var dir := ProjectSettings.globalize_path(OUT_ROOT + reel + "/cards/")
	DirAccess.make_dir_recursive_absolute(dir)
	var card_vp := SubViewport.new()
	card_vp.transparent_bg = true
	card_vp.size = Vector2i(OUT_W, 360)
	card_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(card_vp)
	var heading := FontVariation.new()
	heading.base_font = load("res://fonts/cinzel/Cinzel-Variable.ttf")
	heading.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	for i in beats.size():
		var beat: Dictionary = beats[i]
		if beat.get("caption", "") == "":
			continue
		var holder := CenterContainer.new()
		holder.size = Vector2(OUT_W, 360)
		card_vp.add_child(holder)
		var panel := PanelContainer.new()
		var box := StyleBoxFlat.new()
		box.bg_color = Color("#c8343a")
		box.border_color = Color("#7e1a1e")
		box.border_width_bottom = 10
		box.set_corner_radius_all(14)
		box.content_margin_left = 44
		box.content_margin_right = 44
		box.content_margin_top = 22
		box.content_margin_bottom = 26
		box.shadow_color = Color(0, 0, 0, 0.45)
		box.shadow_size = 18
		box.shadow_offset = Vector2(0, 8)
		panel.add_theme_stylebox_override(&"panel", box)
		holder.add_child(panel)
		var label := Label.new()
		label.text = str(beat.caption)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override(&"font", heading)
		label.add_theme_font_size_override(&"font_size", 66 if label.text.length() <= 18 else 54)
		label.add_theme_color_override(&"font_color", Color.WHITE)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = minf(900.0, 40.0 * label.text.length() + 60.0)
		panel.add_child(label)
		for n in 4:
			await RenderingServer.frame_post_draw
		var image := card_vp.get_texture().get_image()
		image.save_png(dir + "caption_%02d.png" % i)
		holder.queue_free()
		await get_tree().process_frame
	# The end card: the wordmark over a dimmed frame, and "Coming soon to Steam".
	card_vp.size = Vector2i(OUT_W, OUT_H)
	var end := Control.new()
	end.size = Vector2(OUT_W, OUT_H)
	card_vp.add_child(end)
	var shade := ColorRect.new()
	shade.color = Color(NAVY, 0.62)
	shade.size = end.size
	end.add_child(shade)
	# The game's name in the title screen's own font (the theme's TitleLabel: Cinzel at weight 700).
	var title_font := FontVariation.new()
	title_font.base_font = load("res://fonts/cinzel/Cinzel-Variable.ttf")
	title_font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	var mark := Label.new()
	mark.text = "MARITIME
EMPIRE"
	mark.add_theme_font_override(&"font", title_font)
	mark.add_theme_font_size_override(&"font_size", 170)
	mark.add_theme_color_override(&"font_color", Color.WHITE)
	mark.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.55))
	mark.add_theme_constant_override(&"shadow_offset_x", 0)
	mark.add_theme_constant_override(&"shadow_offset_y", 10)
	mark.add_theme_constant_override(&"shadow_outline_size", 6)
	mark.add_theme_constant_override(&"line_spacing", -10)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.position = Vector2(0, 640)
	mark.size = Vector2(OUT_W, 540)
	end.add_child(mark)
	var soon := Label.new()
	soon.text = "COMING SOON TO STEAM"
	soon.add_theme_font_override(&"font", heading)
	soon.add_theme_font_size_override(&"font_size", 58)
	soon.add_theme_color_override(&"font_color", Color("#f2c230"))
	soon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soon.position = Vector2(0, 1220)
	soon.size = Vector2(OUT_W, 90)
	end.add_child(soon)
	for n in 4:
		await RenderingServer.frame_post_draw
	card_vp.get_texture().get_image().save_png(dir + "endcard.png")
	card_vp.queue_free()
	print("cards written to ", dir)


# --- The shots -----------------------------------------------------------------

func shot_globe_spin(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	await settle(30)
	var low := map._min_zoom()
	await rec("globe_spin", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -1.6)
		look(lerpf(175.0, 128.0, k), lerpf(8.0, 28.0, k), lerpf(low, low * 3.2, k)))


func shot_end_globe(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	await settle(30)
	var low := map._min_zoom()
	await rec("end_globe", seconds, func(t: float) -> void:
		look(lerpf(-20.0, -34.0, t / seconds), 18.0, low * 1.05))


## A brand-new company's first ship, the Scooter, pulling out of Shanghai.
func shot_scooter_leaves(seconds: float) -> void:
	await use_new_company("SHA")
	portrait()
	var ship := GameState.buy_ship("model_1", "Little Mo", "SHA")
	var route: Array[String] = ["SHA", "NGB"]
	GameState.assign_route(ship, route)
	var ok := await warp(900.0, func() -> bool: return ship.berth_phase == Ship.BERTH_OUT, 4)
	print("  scooter out: ", ok, " phase ", ship.berth_phase, " docked ", ship.docked_at, " route ", ship.route)
	follow(ship, 3600.0)
	await settle(10)
	await rec("scooter_leaves", seconds)


## Shanghai's Market tab: what everything costs there.
func shot_market_popup(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 40.0)
	await settle(10)
	world._open_port_popup("SHA")
	await settle(10)
	var popup: Control = PopupHost.find(game).current
	var tabs := popup.find_children("*", "TabBar", true, false)
	var containers := popup.find_children("*", "TabContainer", true, false)
	for bar in tabs + containers:
		for i in bar.get_tab_count():
			if bar.get_tab_title(i).begins_with("Market"):
				bar.current_tab = i
	await settle(10)
	var rect := popup.get_global_rect()
	await rec("market_popup", seconds, Callable(), push(grow(rect, 70.0), grow(rect, 12.0), seconds))


## The Finances page's money by model: sales against fuel, repairs, tolls, wages.
func shot_finances_table(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	game.show_screen(GameRoot.Screen.FINANCES)
	await settle(20)
	await rec("finances_table", seconds, Callable(), push(Rect2(286, 236, 512, 372), Rect2(300, 262, 478, 178), seconds))


var _lost: Ship = null


## A Scooter or Feeder breaking down for good at sea, a recovery boat sent.
func _stage_loss() -> void:
	await use_save("save_2", true)
	for ship in GameState.fleet():
		if ship.model_id not in ["model_1", "model_2"] or ship.is_docked() or ship.is_lost() or ship.from_port.is_empty():
			continue
		if GameState.canal_traffic.in_canal(ship):
			continue
		ship.auto_recover = false
		ship.maintenance = 0.0
		GameState._lose(ship, "maintenance")
		var why := GameState.send_recovery(ship)
		if why.is_empty() and ship.rescuer != null:
			_lost = ship
			return
		ship.lost_reason = ""
		ship.maintenance = 0.6
	push_error("no ship could be rescued")


func shot_lost_ship(seconds: float) -> void:
	await _stage_loss()
	portrait()
	follow(_lost, 2600.0)
	await settle(15)
	await rec("lost_ship", seconds)


func shot_recovery_lift(seconds: float) -> void:
	await _stage_loss()
	portrait()
	var boat := _lost.rescuer
	await warp(3000.0, func() -> bool: return boat.job_phase == Ship.JOB_ALIGN or boat.job_phase == Ship.JOB_TOW, 8)
	follow(_lost, 3600.0)
	await settle(5)
	await rec("recovery_lift", seconds)


## The strongest storm out there, drifting.
func shot_storm(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	var best: Dictionary = {}
	for storm: Dictionary in GameState.weather.storms:
		if best.is_empty() or float(storm.radius_nm) < 300.0 and str(storm.kind) != "gale":
			best = storm
	await rec("storm", seconds, func(t: float) -> void:
		look(float(best.lon), float(best.lat), lerpf(64.0, 74.0, t / seconds)))


## Ships working up through the Gatún locks.
func shot_panama_locks(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	GameState.company.hubs.append(Hub.new("CLN", false))
	GameState.money += 5000000
	var ships: Array[Ship] = []
	for i in 5:
		var route: Array[String] = ["CLN", "BLB"]
		ships.append(stage_ship("model_2", "CLN", route))
		await warp(25.0, Callable(), 4)
	await warp(400.0, func() -> bool:
		var in_locks := 0
		for ship in ships:
			if GameState.canal_traffic.in_canal(ship):
				in_locks += 1
		return in_locks >= 3, 4)
	await rec("panama_locks", seconds, func(t: float) -> void:
		look(-79.80, 9.152, lerpf(1300.0, 1450.0, t / seconds)))


## A big fleet's routes (the 213-ship save, based at Apia), pulling out.
func shot_network_zoomout(seconds: float) -> void:
	await use_save("save_3")
	portrait()
	await settle(10)
	await rec("network_zoomout", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -1.8)
		look(lerpf(-171.8, -165.0, k), lerpf(-13.8, -8.0, k), exp(lerpf(log(160.0), log(9.0), k))))


func shot_compare_companies(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	game.show_screen(GameRoot.Screen.FINANCES)
	await settle(10)
	for button in game.find_children("*", "Button", true, false):
		if (button as Button).text.begins_with("Compare") and (button as Control).is_visible_in_tree():
			(button as Button).pressed.emit()
			(button as Button).button_pressed = true
	await settle(20)
	var heading := find_text("Companies", game.get_node("%FinancesScreen")).get_global_rect()
	var table := Rect2(heading.position.x - 14, heading.position.y - 12, minf(1268.0 - heading.position.x, 1000.0), 172)
	await rec("compare_companies", seconds, Callable(), push(grow(table, 50.0), grow(table, 2.0), seconds))


## Not a reel shot: full landscape screenshots of the pages, to pick crops from.
func shot_preview(_seconds: float) -> void:
	await use_save("save_2")
	landscape()
	var dir := ProjectSettings.globalize_path(OUT_ROOT + "preview/")
	DirAccess.make_dir_recursive_absolute(dir)
	for screen in [GameRoot.Screen.FINANCES, GameRoot.Screen.SHIPS, GameRoot.Screen.SHOP, GameRoot.Screen.HUBS]:
		game.show_screen(screen)
		await settle(20)
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_jpg(dir + "screen_%d.jpg" % screen, 0.9)
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 40.0)
	await settle(10)
	world._open_port_popup("SHA")
	await settle(20)
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_jpg(dir + "port_popup.jpg", 0.9)


## From the whole globe down into Shanghai's harbour.
func shot_globe_dive(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	await settle(30)
	var low := map._min_zoom()
	var port := GameData.get_port("SHA")
	await rec("globe_dive", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -2.2)
		look(lerpf(160.0, float(port.lon), minf(1.0, k * 1.4)), lerpf(15.0, float(port.lat), minf(1.0, k * 1.4)), exp(lerpf(log(low), log(1300.0), k))))


## A loaded container ship under way.
func shot_ship_at_sea(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	var pick: Ship = null
	for ship in GameState.fleet():
		if ship.model_id in ["model_2", "model_3", "model_1"] and not ship.is_docked() and ship.cargo_qty > 0 and not ship.is_lost():
			if pick == null or ship.model_id > pick.model_id:
				pick = ship
	follow(pick, 1400.0)
	await settle(15)
	await rec("ship_at_sea", seconds)


## The activity log as sales come in.
func shot_sale_log(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	game.show_screen(GameRoot.Screen.WORLD)
	await warp(90.0, Callable(), 4)
	await settle(10)
	await rec("sale_log", seconds, Callable(), push(Rect2(0, 40, 300, 300), Rect2(0, 44, 272, 220), seconds))


# --- Helpers for the feature reels -------------------------------------------

## The first visible Label or Button whose text starts with prefix.
func find_text(prefix: String, root: Node = null) -> Control:
	for node in (root if root != null else game).find_children("*", "", true, false):
		if (node is Label or node is Button) and (node as CanvasItem).is_visible_in_tree() and str(node.text).begins_with(prefix):
			return node
	return null


## The panel (card) holding a control.
func card_of(control: Control) -> Control:
	var node: Node = control
	while node != null and not (node is PanelContainer):
		node = node.get_parent()
	return node if node != null else control


func popup() -> Control:
	return PopupHost.find(game).current


## A ship's popup in landscape, the map on the ship (zoom), waited on.
func open_ship_popup(ship: Ship, zoom := 300.0) -> Control:
	game.show_screen(GameRoot.Screen.WORLD)
	follow(ship, zoom)
	await settle(5)
	world.open_ship_popup(ship)
	await settle(12)
	return popup()


func open_port_popup(port_id: String, tab := "", zoom := 40.0) -> Control:
	game.show_screen(GameRoot.Screen.WORLD)
	look_port(port_id, zoom)
	await settle(8)
	world._open_port_popup(port_id)
	await settle(8)
	if not tab.is_empty():
		for bar in popup().find_children("*", "TabBar", true, false) + popup().find_children("*", "TabContainer", true, false):
			for i in bar.get_tab_count():
				if bar.get_tab_title(i).begins_with(tab):
					bar.current_tab = i
	await settle(8)
	return popup()


## The player's first ship of these models (any, if empty) passing a test.
func pick_ship(models: Array, test: Callable) -> Ship:
	for ship in GameState.fleet():
		if (models.is_empty() or ship.model_id in models) and test.call(ship):
			return ship
	return null


func at_sea(ship: Ship) -> bool:
	return not ship.is_docked() and not ship.is_lost() and not GameState.canal_traffic.in_canal(ship) and not ship.from_port.is_empty()


## A ship of a model made outright (past the Shop's level and slot limits),
## for staging; docked at the port.
func stage_ship(model_id: String, port_id: String, route: Array[String] = []) -> Ship:
	var ship := Ship.new(GameState.suggest_ship_name(), model_id, port_id)
	ship.id = GameState.next_ship_id
	GameState.next_ship_id += 1
	ship.company = GameState.company
	ship.captains = Characters.officers_for(GameData.get_ship_model(model_id))
	GameState.ships.append(ship)
	if ship.is_service():
		ship.base_port = port_id
	GameState.ships_changed.emit()
	if not route.is_empty():
		GameState.assign_route(ship, route)
	return ship


func log_crop(seconds: float) -> Callable:
	return push(Rect2(0, 40, 300, 280), Rect2(0, 44, 272, 200), seconds)


func popup_crop(box: Control) -> Callable:
	return func(_t: float) -> Rect2: return grow(box.get_global_rect(), 10.0) if is_instance_valid(box) else Rect2(272, 40, 1008, 640)


# --- Feature reel shots: trading, first ship, routes, wear, recovery ---------

func shot_market_scroll(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	var box := await open_port_popup("SHA", "Market")
	var rect := box.get_global_rect()
	var table := Rect2(rect.position.x + 8, rect.position.y + rect.size.y * 0.45, rect.size.x * 0.56, rect.size.y * 0.4)
	await rec("market_scroll", seconds, Callable(), push(grow(rect, 6.0), table, seconds))


func _docked_cargo_ship() -> Ship:
	return pick_ship(["model_2", "model_3", "model_1"], func(s: Ship) -> bool: return s.is_docked() and s.berth >= 0)


func shot_ship_loading(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	var ship := _docked_cargo_ship()
	if ship == null:
		await warp(120.0, func() -> bool: return _docked_cargo_ship() != null, 4)
		ship = _docked_cargo_ship()
	var box := await open_ship_popup(ship, 2000.0)
	await rec("ship_loading", seconds, Callable(), popup_crop(box))


func shot_empty_ship_popup(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	var ship := pick_ship([], func(s: Ship) -> bool: return at_sea(s) and s.cargo_qty == 0 and not s.is_service())
	if ship == null:
		ship = pick_ship([], func(s: Ship) -> bool: return at_sea(s) and not s.is_service())
	var box := await open_ship_popup(ship, 600.0)
	await rec("empty_ship_popup", seconds, Callable(), popup_crop(box))


func _shop_card(model_name: String) -> Rect2:
	var title := find_text(model_name, game.get_node("%ShopScreen"))
	if title == null:
		return Rect2(272, 60, 600, 600)
	return card_of(title).get_global_rect()


func shot_shop_scooter(seconds: float) -> void:
	await use_new_company("SHA")
	landscape()
	game.show_screen(GameRoot.Screen.SHOP)
	await settle(20)
	var card := _shop_card("Scooter 20")
	await rec("shop_scooter", seconds, Callable(), push(grow(card, 120.0), grow(card, 8.0), seconds))


func shot_shop_dominator(seconds: float) -> void:
	await use_new_company("SHA")
	landscape()
	game.show_screen(GameRoot.Screen.SHOP)
	await settle(20)
	var scooter := _shop_card("Scooter 20")
	var dominator := _shop_card("Dominator")
	await rec("shop_dominator", seconds, Callable(), push(grow(scooter.merge(dominator), 10.0), grow(dominator, 8.0), seconds))


func shot_scooter_coast(seconds: float) -> void:
	await use_new_company("SHA")
	portrait()
	var ship := GameState.buy_ship("model_1", "Little Mo", "SHA")
	var route: Array[String] = ["SHA", "NGB"]
	GameState.assign_route(ship, route)
	await warp(1500.0, func() -> bool: return at_sea(ship) and ship.traveled_nm > 25.0, 8)
	follow(ship, 700.0)
	await settle(10)
	await rec("scooter_coast", seconds)


var _route_ship: Ship = null

func _open_route(stops: Array) -> Control:
	await use_save("save_2")
	landscape()
	_route_ship = pick_ship(["model_2"], func(s: Ship) -> bool: return s.is_docked())
	if _route_ship == null:
		_route_ship = pick_ship(["model_2", "model_1"], func(_s: Ship) -> bool: return true)
	game.open_route_screen(_route_ship)
	await settle(20)
	var screen: Control = game.get_node("%RouteScreen")
	for stop in stops:
		screen._add_waypoint(stop)
	await settle(5)
	return screen


func _route_side(screen: Control) -> Rect2:
	var side := find_text("Route for", screen)
	return card_of(side).get_global_rect() if side != null else Rect2(880, 0, 400, 720)


func shot_route_clicking(seconds: float) -> void:
	var screen := await _open_route([])
	var stops := ["NGB", "PUS", "QIN"]
	var side := _route_side(screen)
	var map_rect := Rect2(0, 0, side.position.x, 720)
	var tight := Rect2(map_rect.get_center() - Vector2(240, 290), Vector2(480, 580))
	await rec("route_clicking", seconds, func(t: float) -> void:
		var due := mini(int(t / (seconds / 3.2)) + 1, stops.size())
		while screen._waypoints.size() < due:
			screen._add_waypoint(stops[screen._waypoints.size()]), push(map_rect, tight, seconds))


func shot_route_list(seconds: float) -> void:
	var screen := await _open_route(["NGB", "PUS", "QIN"])
	var rect := _route_side(screen)
	await rec("route_list", seconds, Callable(), push(rect, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.7)), seconds))


func shot_route_greyed(seconds: float) -> void:
	var screen := await _open_route(["NGB"])
	await rec("route_greyed", seconds, func(t: float) -> void:
		if t > seconds * 0.35 and screen._message.is_empty():
			screen._add_waypoint("LGB"), push(Rect2(0, 0, 1280, 720), Rect2(140, 0, 900, 720), seconds))


func shot_ship_popup_bars(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	var ship := pick_ship(["model_2", "model_3"], func(s: Ship) -> bool: return at_sea(s))
	var box := await open_ship_popup(ship, 600.0)
	_speed = 8
	await rec("ship_popup_bars", seconds, Callable(), popup_crop(box))
	_speed = 1


func shot_worn_ship_popup(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	var ship := pick_ship(["model_2", "model_3"], func(s: Ship) -> bool: return at_sea(s))
	ship.auto_repair = false
	ship.maintenance = 0.62
	var box := await open_ship_popup(ship, 600.0)
	await rec("worn_ship_popup", seconds, func(t: float) -> void:
		ship.maintenance = lerpf(0.62, 0.31, t / seconds), popup_crop(box))


func shot_breakdown_log(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	var ship := pick_ship(["model_2", "model_3", "model_1"], func(s: Ship) -> bool: return at_sea(s))
	game.show_screen(GameRoot.Screen.WORLD)
	follow(ship, 900.0)
	await settle(10)
	await rec("breakdown_log", seconds, func(t: float) -> void:
		if t >= 0.6 and ship.maintenance > 0.45:
			ship.maintenance = maxf(ship.maintenance - 0.5, 0.05)
			ship.risk_check_time = 0.0
			GameState.ship_broke_down.emit(ship), func(_t: float) -> Rect2: return Rect2(0, 40, 980, 640))


func shot_recovery_estimate(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	var ship := pick_ship(["model_2", "model_1"], func(s: Ship) -> bool: return at_sea(s))
	ship.auto_recover = false
	ship.maintenance = 0.0
	GameState._lose(ship, "maintenance")
	var box := await open_ship_popup(ship, 900.0)
	var rect := box.get_global_rect()
	await rec("recovery_estimate", seconds, Callable(), push(grow(rect, 10.0), Rect2(rect.position.x, rect.position.y + rect.size.y * 0.45, rect.size.x, rect.size.y * 0.55), seconds))


## The Mammoth (staged at Shanghai) taking a lost Feeder aboard.
func shot_mammoth_lift(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	for ship in GameState.fleet():
		if ship.model_id == "model_7":
			ship.paused = true
	stage_ship("model_6", "SHA")
	GameState._rebalance_recovery_boats()
	await warp(20.0, Callable(), 4)
	var lost := pick_ship(["model_2", "model_3"], func(s: Ship) -> bool: return at_sea(s) and GameData.distance_nm(s.from_port, "SHA") < 1500.0)
	lost.auto_recover = false
	lost.maintenance = 0.0
	GameState._lose(lost, "maintenance")
	print("  mammoth job: '", GameState.send_recovery(lost), "' rescuer ", lost.rescuer.model_id if lost.rescuer != null else "none")
	var boat := lost.rescuer
	await warp(3000.0, func() -> bool: return boat.job_phase == Ship.JOB_ALIGN or boat.job_phase == Ship.JOB_TOW, 8)
	follow(lost, 3600.0)
	await settle(5)
	await rec("mammoth_lift", seconds)


# --- Feature reel shots: wages, loans, hubs, regions, canals -----------------

func shot_crew_view(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	var ship := pick_ship(["model_14", "model_11", "model_3", "model_2"], func(s: Ship) -> bool: return at_sea(s))
	var box := await open_ship_popup(ship, 600.0)
	box._crew_button.button_pressed = true
	await settle(10)
	await rec("crew_view", seconds, Callable(), popup_crop(box))


## Payday with almost nothing in the bank: the money goes red.
func shot_money_red(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 60.0)
	GameState.money = 60000
	var period := GameState.wage_period
	var paid := await warp(2400.0, func() -> bool: return GameState.wage_period != period and GameState.money < 0, 8)
	print("  in the red: ", paid, " money ", GameState.money)
	await settle(5)
	await rec("money_red", seconds, Callable(), push(Rect2(0, 0, 560, 330), Rect2(0, 0, 420, 250), seconds))


func shot_shop_in_debt(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	GameState.money = -184250
	game.show_screen(GameRoot.Screen.SHOP)
	await settle(20)
	var card := _shop_card("Feeder 100")
	await rec("shop_in_debt", seconds, Callable(), push(Rect2(0, 0, 900, 506), grow(card.merge(Rect2(0, 0, 420, 40)), 8.0), seconds))


func _finances() -> Control:
	game.show_screen(GameRoot.Screen.FINANCES)
	await settle(20)
	return game.get_node("%FinancesScreen")


func shot_loan_row(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	await _finances()
	await rec("loan_row", seconds, func(t: float) -> void:
		if t >= seconds * 0.4 and GameState.company.loan == 0:
			GameState.take_loan(), push(Rect2(286, 110, 720, 250), Rect2(286, 140, 560, 170), seconds))


func shot_loan_interest(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	for i in 10:
		GameState.take_loan()
	var period := GameState.wage_period
	await warp(2400.0, func() -> bool: return GameState.wage_period != period, 8)
	await _finances()
	await rec("loan_interest", seconds, Callable(), push(Rect2(300, 200, 478, 360), Rect2(300, 380, 478, 70), seconds))


func shot_bank_reserve(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	var screen := await _finances()
	var picker: OptionButton = screen._bank_picker
	await rec("bank_reserve", seconds, func(t: float) -> void:
		if t >= seconds * 0.4 and picker.selected != 4:
			picker.select(4)
			picker.item_selected.emit(4), push(Rect2(286, 110, 760, 200), Rect2(286, 130, 760, 90), seconds))


func shot_port_fee_log(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 60.0)
	await warp(240.0, Callable(), 8)
	await settle(5)
	await rec("port_fee_log", seconds, Callable(), log_crop(seconds))


func shot_build_hub(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	var box := await open_port_popup("PUS", "Build", 40.0)
	if find_text("Build a hub", box) == null:
		box = await open_port_popup("PUS", "Hub", 40.0)
	var presses := 0
	await rec("build_hub", seconds, func(t: float) -> void:
		var button := find_text("Build a hub", box) if is_instance_valid(box) else null
		if button == null:
			button = find_text("Click again", box) if is_instance_valid(box) else null
		if button is Button and t >= seconds * (0.35 + 0.25 * presses) and presses < 2:
			(button as Button).pressed.emit()
			presses += 1, popup_crop(box))


func shot_hub_ring(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	print("  hub: ", GameState.build_hub("PUS"))
	await settle(20)
	await rec("hub_ring", seconds, func(t: float) -> void:
		look(lerpf(125.5, 124.8, t / seconds), lerpf(33.2, 33.0, t / seconds), lerpf(70.0, 82.0, t / seconds)))


func shot_hubs_screen(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	game.show_screen(GameRoot.Screen.HUBS)
	await settle(20)
	var hq := find_text("Headquarters", game.get_node("%HubsScreen"))
	var rect := card_of(hq).get_global_rect() if hq != null else Rect2(272, 40, 1008, 640)
	await rec("hubs_screen", seconds, Callable(), push(grow(rect, 8.0), Rect2(rect.position + Vector2(0, rect.size.y * 0.2), rect.size * Vector2(1.0, 0.55)), seconds))


## Market regions as a new company sees them (only its own unlocked).
func shot_regions_locked(seconds: float) -> void:
	unlock_all = false
	await use_new_company("SHA")
	unlock_all = true
	portrait()
	await settle(20)
	var low := map._min_zoom()
	await rec("regions_locked", seconds, func(t: float) -> void:
		look(lerpf(140.0, 118.0, t / seconds), 22.0, low * lerpf(1.6, 2.1, t / seconds)))


func shot_ship_through_locked(seconds: float) -> void:
	unlock_all = false
	await use_save("save_2", true)
	unlock_all = true
	portrait()
	var ship := pick_ship([], func(s: Ship) -> bool:
		return at_sea(s) and GameData.distance_nm(s.from_port, s.to_port) > 1500.0)
	if ship == null:
		ship = pick_ship([], func(s: Ship) -> bool: return at_sea(s))
	follow(ship, 45.0)
	await settle(15)
	await rec("ship_through_locked", seconds)


## Five Feeders on the Colón-Balboa run (a hub staged at Colón), into the locks.
func _stage_panama() -> Array[Ship]:
	await use_save("save_2", true)
	GameState.company.hubs.append(Hub.new("CLN", false))
	var ships: Array[Ship] = []
	for i in 5:
		var route: Array[String] = ["CLN", "BLB"]
		ships.append(stage_ship("model_2", "CLN", route))
		await warp(25.0, Callable(), 4)
	await warp(400.0, func() -> bool:
		return ships.filter(func(s: Ship) -> bool: return GameState.canal_traffic.in_canal(s)).size() >= 3, 4)
	return ships


func shot_panama_zoom(seconds: float) -> void:
	await _stage_panama()
	portrait()
	await rec("panama_zoom", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -2.0)
		look(lerpf(-79.6, -79.80, k), lerpf(9.0, 9.152, k), exp(lerpf(log(40.0), log(1300.0), k))))


func shot_toll_log(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	GameState.company.hubs.append(Hub.new("CLN", false))
	for i in 4:
		var route: Array[String] = ["CLN", "BLB"]
		stage_ship("model_2", "CLN", route)
	game.show_screen(GameRoot.Screen.WORLD)
	look(-79.8, 9.15, 300.0)
	await warp(120.0, func() -> bool:
		return GameState.fleet().any(func(s: Ship) -> bool: return GameState.canal_traffic.in_canal(s)), 4)
	await settle(5)
	await rec("toll_log", seconds, Callable(), func(_t: float) -> Rect2: return Rect2(0, 40, 760, 600))


## Feeders on the Port Said - Jeddah run (a hub staged at Port Said).
func _stage_suez() -> Array[Ship]:
	await use_save("save_2", true)
	GameState.company.hubs.append(Hub.new("PSD", false))
	var ships: Array[Ship] = []
	for i in 6:
		var route: Array[String] = ["PSD", "JED"]
		ships.append(stage_ship("model_2", "PSD", route))
	await warp(600.0, func() -> bool:
		return ships.filter(func(s: Ship) -> bool: return s.canal_state == "anchored").size() >= 3, 4)
	return ships


func shot_suez_anchorage(seconds: float) -> void:
	await _stage_suez()
	portrait()
	await rec("suez_anchorage", seconds, func(t: float) -> void:
		look(32.36, 31.18, lerpf(500.0, 560.0, t / seconds)))


func shot_suez_convoy(seconds: float) -> void:
	var ships := await _stage_suez()
	portrait()
	await warp(200.0, func() -> bool:
		return ships.filter(func(s: Ship) -> bool: return s.canal_state == "convoy").size() >= 2, 4)
	var lead := ships.filter(func(s: Ship) -> bool: return s.canal_state == "convoy")
	follow(lead[0] if not lead.is_empty() else ships[0], 380.0)
	await settle(5)
	await rec("suez_convoy", seconds)


func shot_suez_route(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	GameState.company.hubs.append(Hub.new("PSD", false))
	var ship := stage_ship("model_2", "PSD")
	await settle(5)
	game.open_route_screen(ship)
	await settle(20)
	var screen: Control = game.get_node("%RouteScreen")
	screen._add_waypoint("JED")
	screen._add_waypoint("PSD")
	await settle(10)
	var rect := _route_side(screen)
	await rec("suez_route", seconds, Callable(), push(rect, Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.6)), seconds))


# --- Feature reel shots: lakes, storms, docks, tugs, fishing, levels ---------

func shot_stlawrence_zoom(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	await rec("stlawrence_zoom", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -1.6)
		look(lerpf(-64.0, -77.5, k), lerpf(48.5, 43.4, k), exp(lerpf(log(28.0), log(60.0), k))))


func shot_lakes_route_big(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	GameState.company.hubs.append(Hub.new("NYC", false))
	var ship := stage_ship("model_12", "NYC")
	await settle(5)
	game.open_route_screen(ship)
	await settle(20)
	var screen: Control = game.get_node("%RouteScreen")
	var map_view: MapView = screen.get_node("%MapView")
	map_view._look_at(Geo.project(Vector2(-80.0, 43.5)))
	map_view._zoom = 38.0
	map_view._zoom_goal = 38.0
	map_view._changed()
	await settle(10)
	await rec("lakes_route_big", seconds, func(t: float) -> void:
		if t >= seconds * 0.45 and screen._message.is_empty():
			screen._add_waypoint("CHI"), push(Rect2(0, 0, 1280, 720), Rect2(120, 60, 800, 620), seconds))


## February: the Seaway and Welland locks iced shut.
func shot_lakes_ice(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	await rec("lakes_ice", seconds, func(t: float) -> void:
		look(lerpf(-77.0, -79.0, t / seconds), 43.4, lerpf(90.0, 110.0, t / seconds)))


func _ship_into_storm(tier := "tempest") -> Ship:
	GameState.divine.on = true
	GameState.money += 2000000000
	var ship := pick_ship(["model_2", "model_3", "model_14", "model_11"], func(s: Ship) -> bool:
		return at_sea(s) and GameData.distance_nm(s.from_port, s.to_port) > 500.0)
	var at := Geo.unproject(map._ship_world(ship))
	GameState.weather.spawn_divine(tier, at, GameState.company.name)
	await warp(120.0, Callable(), 8)
	return ship


func shot_ship_in_storm(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	var ship := await _ship_into_storm()
	follow(ship, 260.0)
	await settle(10)
	await rec("ship_in_storm", seconds)


func shot_storm_warning(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	GameState.divine.on = true
	var port := GameData.get_port("NGB")
	GameState.weather.spawn_divine("tempest", Vector2(float(port.lon) + 3.0, float(port.lat) - 2.0), GameState.company.name)
	game.show_screen(GameRoot.Screen.WORLD)
	look(float(port.lon) + 1.5, float(port.lat) - 1.0, 70.0)
	await warp(200.0, Callable(), 8)
	look(float(port.lon) + 1.5, float(port.lat) - 1.0, 70.0)
	await settle(10)
	await rec("storm_warning", seconds, Callable(), func(_t: float) -> Rect2: return Rect2(0, 40, 900, 640))


func shot_marina_full(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	await rec("marina_full", seconds, func(t: float) -> void:
		look_port("SHA", lerpf(1500.0, 1700.0, t / seconds)))


## Twenty Scooters sent to Shanghai at once (staged): the rest wait at anchor.
func _stage_crowd() -> Array[Ship]:
	await use_save("save_2", true)
	var ships: Array[Ship] = []
	for i in 20:
		var route: Array[String] = ["NGB", "SHA"]
		ships.append(stage_ship("model_1", "NGB", route))
	await warp(400.0, func() -> bool:
		return ships.filter(func(s: Ship) -> bool: return s.berth_phase == Ship.BERTH_WAIT).size() >= 4, 4)
	return ships


func shot_anchor_wait(seconds: float) -> void:
	var ships := await _stage_crowd()
	portrait()
	var waiting := ships.filter(func(s: Ship) -> bool: return s.berth_phase == Ship.BERTH_WAIT)
	follow(waiting[0] if not waiting.is_empty() else ships[0], 1100.0)
	await settle(10)
	await rec("anchor_wait", seconds)


func shot_coming_alongside(seconds: float) -> void:
	var ships := await _stage_crowd()
	portrait()
	await warp(300.0, func() -> bool: return ships.any(func(s: Ship) -> bool: return s.berth_phase == Ship.BERTH_IN), 2)
	var coming := ships.filter(func(s: Ship) -> bool: return s.berth_phase == Ship.BERTH_IN)
	follow(coming[0] if not coming.is_empty() else ships[0], 2600.0)
	await settle(5)
	await rec("coming_alongside", seconds)


func shot_tugs_moored(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	var tug := pick_ship(["model_25"], func(s: Ship) -> bool: return s.is_docked())
	var port := tug.docked_at if tug != null else "SHA"
	await rec("tugs_moored", seconds, func(t: float) -> void:
		look_port(port, lerpf(2200.0, 2500.0, t / seconds)))


## A ship lost near a port its tugs work from, and the tugs sent for it.
func _stage_tow() -> Ship:
	await use_save("save_2", true)
	var tug_ports := GameState.tug_ports()
	var lost := pick_ship([], func(s: Ship) -> bool:
		return at_sea(s) and not s.is_service() and s.traveled_nm < 60.0 and s.from_port in tug_ports and not GameState.tugs_at(s.from_port).is_empty())
	if lost == null:
		await warp(300.0, func() -> bool:
			lost = pick_ship([], func(s: Ship) -> bool:
				return at_sea(s) and not s.is_service() and s.traveled_nm > 15.0 and s.traveled_nm < 60.0 and s.from_port in tug_ports)
			return lost != null, 2)
	lost.auto_recover = false
	lost.maintenance = 0.0
	GameState._lose(lost, "maintenance")
	print("  tow: '", GameState.send_recovery(lost), "' by ", lost.rescuer.model_id if lost.rescuer != null else "none")
	return lost


func shot_tug_tow(seconds: float) -> void:
	var lost := await _stage_tow()
	portrait()
	var boat := lost.rescuer
	if boat != null:
		await warp(1500.0, func() -> bool: return boat.job_phase == Ship.JOB_TOW, 4)
	follow(lost, 1800.0)
	await settle(5)
	await rec("tug_tow", seconds)


func shot_tug_berthing(seconds: float) -> void:
	var lost := await _stage_tow()
	portrait()
	var boat := lost.rescuer
	if boat != null:
		await warp(2000.0, func() -> bool: return boat.job_phase == Ship.JOB_BERTH, 4)
	follow(lost, 2600.0)
	await settle(5)
	await rec("tug_berthing", seconds)


func _fishing_boat(test: Callable) -> Ship:
	return pick_ship(["model_26", "model_27", "model_29", "model_30"], test)


func shot_fishing_leaves(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	var boat: Ship = null
	await warp(1200.0, func() -> bool:
		boat = _fishing_boat(func(s: Ship) -> bool: return s.berth_phase == Ship.BERTH_OUT)
		return boat != null, 4)
	if boat == null:
		boat = _fishing_boat(func(s: Ship) -> bool: return true)
	follow(boat, 2200.0)
	await settle(5)
	await rec("fishing_leaves", seconds)


func shot_fishing_base_list(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	var boat := _fishing_boat(func(s: Ship) -> bool: return true)
	var box := await open_ship_popup(boat, 600.0)
	var rect := box.get_global_rect()
	await rec("fishing_base_list", seconds, Callable(), push(grow(rect, 10.0), Rect2(rect.position + Vector2(0, rect.size.y * 0.4), rect.size * Vector2(1.0, 0.6)), seconds))


func shot_fishing_ground(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	var boat: Ship = null
	await warp(1500.0, func() -> bool:
		boat = _fishing_boat(func(s: Ship) -> bool: return s.job_phase == Ship.JOB_FISH and not s.is_docked())
		return boat != null, 8)
	if boat == null:
		boat = _fishing_boat(func(s: Ship) -> bool: return not s.is_docked())
	follow(boat, 2000.0)
	await settle(5)
	await rec("fishing_ground", seconds)


func shot_catch_log(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 60.0)
	var landed := [false]
	GameState.catch_landed.connect(func(_a, _b, _c, _d, _e, _f) -> void: landed[0] = true)
	await warp(2400.0, func() -> bool: return landed[0], 8)
	await settle(5)
	await rec("catch_log", seconds, Callable(), log_crop(seconds))


func shot_ships_tiles(seconds: float) -> void:
	await use_save("save_2")
	landscape()
	game.show_screen(GameRoot.Screen.SHIPS)
	await settle(20)
	var title := find_text("Scooter 20", game.get_node("%ShipsScreen"))
	var rect := Rect2(272, 60, 1008, 300)
	if title != null:
		var group := title.get_parent().get_parent() as Control
		rect = group.get_global_rect() if group != null else rect
	await rec("ships_tiles", seconds, Callable(), push(grow(rect, 6.0), Rect2(rect.position, Vector2(rect.size.x * 0.5, rect.size.y)), seconds))


func _skills_popup() -> Control:
	await use_save("save_2")
	landscape()
	var ship := pick_ship(["model_2", "model_3", "model_1"], func(s: Ship) -> bool: return at_sea(s))
	if ship == null:
		ship = pick_ship(["model_2", "model_3", "model_1"], func(s: Ship) -> bool: return at_sea(s))
	var box := await open_ship_popup(ship, 600.0)
	box.get_node("%SkillsButton").button_pressed = true
	await settle(10)
	return box


func shot_skills_view(seconds: float) -> void:
	var box := await _skills_popup()
	await rec("skills_view", seconds, Callable(), popup_crop(box))


func shot_skills_prices(seconds: float) -> void:
	var box := await _skills_popup()
	var skills: Control = box.get_node("%SkillsBox")
	var rect := skills.get_global_rect()
	await rec("skills_prices", seconds, Callable(), push(grow(box.get_global_rect(), 10.0), grow(rect, 10.0), seconds))


# --- Feature reel shots: rivals, multiplayer, Divine Actions, not idle -------

## A scene other than the game (the title screen, Found Company) in landscape.
func _other_scene(path: String) -> Control:
	await _unload()
	landscape_bare()
	var scene: Control = load(path).instantiate()
	vp.add_child(scene)
	await settle(30)
	return scene


func landscape_bare() -> void:
	_landscape = true
	vp.size = Vector2i(UI_BASE) * LAND_SCALE
	vp.size_2d_override = Vector2i(UI_BASE)
	vp.size_2d_override_stretch = true


## The title screen's Host Game dialog (its settings; nothing hosted).
func shot_host_dialog(seconds: float) -> void:
	MainMenu._booted = true
	var menu := await _other_scene("res://scenes/main_menu.tscn")
	menu._ask_host(func() -> void: pass)
	await settle(20)
	var rect := Rect2(390, 200, 500, 320)
	for window in menu.find_children("*", "ConfirmationDialog", true, false):
		var dialog := window as ConfirmationDialog
		rect = Rect2(Vector2(dialog.position), Vector2(dialog.size))
	await rec("host_dialog", seconds, Callable(), push(grow(rect, 120.0), grow(rect, 10.0), seconds))
	menu.queue_free()


func shot_mp_port(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	var rival_port := ""
	for ship in GameState.ships:
		if ship.company != GameState.company and ship.is_docked() and GameState.fleet().any(func(s: Ship) -> bool: return s.docked_at == ship.docked_at):
			rival_port = ship.docked_at
			break
	if rival_port.is_empty():
		rival_port = "SHA"
	print("  shared port: ", rival_port)
	await rec("mp_port", seconds, func(t: float) -> void:
		look_port(rival_port, lerpf(1400.0, 1600.0, t / seconds)))


func shot_mp_storm(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	var ship := await _ship_into_storm("squall")
	follow(ship, 160.0)
	await settle(10)
	await rec("mp_storm", seconds)


func shot_divine_panel(seconds: float) -> void:
	await use_save("save_2", true)
	landscape()
	GameState.money += 1500000000
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 30.0)
	var panel := DivinePanel.new()
	panel.pick.connect(world._start_divine)
	world.add_child(panel)
	await settle(20)
	var box := panel
	for child in panel.find_children("*", "PanelContainer", true, false):
		box = child
		break
	var rect := (box as Control).get_global_rect()
	await rec("divine_panel", seconds, Callable(), push(grow(rect, 60.0), grow(rect, 8.0), seconds))
	panel.queue_free()


## Wrath, the billion-dollar storm, dropped on a rival's lane.
func shot_divine_storm(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	GameState.money += 1500000000
	var rival: Ship = null
	for ship in GameState.ships:
		if ship.company != GameState.company and at_sea(ship) and not ship.is_service():
			rival = ship
			break
	var at := Geo.unproject(map._ship_world(rival))
	world._divine_hint.visible = true
	world._start_divine("wrath")
	look(at.x, at.y, 26.0)
	await settle(10)
	var done := [false]
	await rec("divine_storm", seconds, func(t: float) -> void:
		look(at.x, at.y, lerpf(26.0, 30.0, t / seconds))
		if t >= seconds * 0.3 and not done[0]:
			done[0] = true
			world._on_divine_target(at)
			print("  wrath: ", GameState.weather.storms.size(), " storms"))


func shot_divine_hits(seconds: float) -> void:
	await use_save("save_2", true)
	portrait()
	var ship := await _ship_into_storm("wrath")
	follow(ship, 200.0)
	await settle(10)
	await rec("divine_hits", seconds)


func shot_main_menu(seconds: float) -> void:
	MainMenu._booted = true
	var menu := await _other_scene("res://scenes/main_menu.tscn")
	await rec("main_menu", seconds, Callable(), push(Rect2(0, 0, 1280, 720), Rect2(300, 60, 680, 600), seconds))
	menu.queue_free()


## Paused: nothing moves (the world frozen as a closed game is), then on again.
func shot_frozen_ship(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	var ship := pick_ship(["model_2", "model_3"], func(s: Ship) -> bool: return at_sea(s))
	follow(ship, 1500.0)
	_speed = 0
	await settle(10)
	await rec("frozen_ship", seconds, func(t: float) -> void:
		_speed = 0 if t < seconds * 0.55 else 1)
	_speed = 1


func shot_fast_forward(seconds: float) -> void:
	await use_save("save_2")
	portrait()
	_speed = 8
	await rec("fast_forward", seconds, func(t: float) -> void:
		look_port("SHA", lerpf(260.0, 300.0, t / seconds)))
	_speed = 1


# --- The living-world intro (2026-10-29) ---------------------------------------
# The saves from before the living world can't be loaded any more, so the intro
# is staged in one freshly founded company at Shanghai (use_world()).

## Whether the event card (a contract offer, say) may show on camera.
var _cards_on := false

## One freshly founded company at Shanghai, the world's traffic on heavy and
## money to stage with, for every intro shot (founded once; the shots add to it).
func use_world() -> void:
	if _save_loaded == "world" and is_instance_valid(game):
		return
	await _unload()
	GameState.multiplayer_save = false
	GameState.save_slot = SLOT
	GameState.new_game("Harbour Line", "SHA", "orange", {"storms": "moderate", "seed": 20261029})
	await _start_game()
	Settings.traffic = "heavy"
	GameState.money += 30000000
	_save_loaded = "world"
	warm_traffic()


## Indexes every firm's voyage at once (the game does 60 a frame, so the other
## firms' ships take a few hundred frames to show otherwise); then a few
## frames of settle() put the ghosts in view.
func warm_traffic() -> void:
	var traffic: AmbientTraffic = GameState.traffic
	var firms: ShippingFirms = GameState.firms
	var records := firms.voyages.size() + firms.returning().size()
	for n in ceili(records / 60.0) + 2:
		traffic._index_slice(firms)
	print("  traffic indexed: ", records, " records")


func _snap(file: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path(OUT_ROOT + "preview/")
	DirAccess.make_dir_recursive_absolute(dir)
	vp.get_texture().get_image().save_jpg(dir + file, 0.9)
	print("  preview ", file)


## Not a reel shot: screenshots of the new pages, the contract card, the order
## popup and the traffic round Singapore, to pick crops from.
func shot_preview2(_seconds: float) -> void:
	await use_world()
	landscape()
	for screen in [GameRoot.Screen.PEOPLE, GameRoot.Screen.CONTRACTS, GameRoot.Screen.OWNERSHIP, GameRoot.Screen.SHOP, GameRoot.Screen.RESEARCH, GameRoot.Screen.FINANCES]:
		game.show_screen(screen)
		await settle(20)
		await _snap("page_%d.jpg" % screen)
	game.show_screen(GameRoot.Screen.SHOP)
	await settle(10)
	game.get_node("%ShopScreen")._on_buy_pressed("model_4")
	await settle(15)
	print("  order popup rect: ", popup().get_global_rect() if popup() != null else "none")
	await _snap("shop_order.jpg")
	if popup() != null:
		PopupHost.find(game).close()
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 40.0)
	await settle(10)
	GameState.contracts._refresh_offers()
	print("  offers: ", GameState.contracts.offers.size())
	if not GameState.contracts.offers.is_empty():
		_cards_on = true
		game.event_card.show_offer(GameState.contracts.offers[0])
		await settle(10)
		print("  card rect: ", game.event_card.get_global_rect())
		await _snap("contract_card.jpg")
		game.event_card._queue.clear()
		game.event_card.visible = false
		_cards_on = false
	portrait()
	look_port("SIN", 60.0)
	await settle(90)
	await _snap("sin_60.jpg")
	look_port("SIN", 120.0)
	await settle(60)
	await _snap("sin_120.jpg")
	look(104.0, 1.0, 30.0)
	await settle(60)
	await _snap("malacca_30.jpg")
	look_port("SHA", 60.0)
	await settle(60)
	await _snap("sha_60.jpg")


# --- Intro A shots, staged in use_world() --------------------------------------

## The People page's executives (the UI's 1280x720), picked from shot_preview2's screenshot.
const PEOPLE_CROP := Rect2(330, 228, 880, 300)


func shot_globe_spin2(seconds: float) -> void:
	await use_world()
	portrait()
	warm_traffic()
	await settle(40)
	var low := map._min_zoom()
	await rec("globe_spin2", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -1.6)
		look(lerpf(175.0, 128.0, k), lerpf(8.0, 28.0, k), lerpf(low, low * 3.2, k)))


func shot_end_globe2(seconds: float) -> void:
	await use_world()
	portrait()
	await settle(30)
	var low := map._min_zoom()
	await rec("end_globe2", seconds, func(t: float) -> void:
		look(lerpf(-20.0, -34.0, t / seconds), 18.0, low * 1.05))


## The other firms' ships through the Singapore Strait, a slow drift east.
## NOT USED YET: the ghosts aren't drawn in the director's viewport (not even
## followed, see shot_ghost_follow); _traffic_diag() is there to dig further.
func shot_busy_sea(seconds: float) -> void:
	await use_world()
	portrait()
	warm_traffic()
	look(103.95, 1.18, 380.0)
	await settle(60)  # (The traffic scan fills the view.)
	print("  ghosts in view: ", GameState.traffic.ghosts.size(), " ship scale ", map._ship_scale(), " size ", map.size)
	for ghost in GameState.traffic.ghosts.slice(0, 6):
		var about: Dictionary = ghost.get_meta(&"traffic")
		var at: Vector2 = GameData.port_position(ghost.docked_at) if ghost.is_docked() else (about.lane as GameData.SeaLane).point_at(ghost.traveled_nm)
		print("    ", ghost.name, " ", ghost.model_id, " docked=", ghost.docked_at, " ", ghost.from_port, "->", ghost.to_port, " nm ", ghost.traveled_nm, "/", about.length, " screen ", map.world_to_screen(at), " leg_lane ", ghost.leg_lane() != null, " look ", map._model_look(ghost.model_id).size())
	await rec("busy_sea", seconds, func(t: float) -> void:
		look(lerpf(103.95, 104.05, t / seconds), lerpf(1.18, 1.2, t / seconds), lerpf(380.0, 420.0, t / seconds)))


## The company's first ship, a Scooter, pulling out of Shanghai.
func shot_scooter_leaves2(seconds: float) -> void:
	await use_world()
	portrait()
	var ship := GameState.buy_ship("model_1", "Little Mo", "SHA")
	if ship == null:
		push_error("no scooter: " + GameState.buy_error("model_1"))
		return
	var route: Array[String] = ["SHA", "NGB"]
	GameState.assign_route(ship, route)
	var ok := await warp(900.0, func() -> bool: return ship.berth_phase == Ship.BERTH_OUT, 4)
	print("  scooter out: ", ok, " phase ", ship.berth_phase, " docked ", ship.docked_at)
	follow(ship, 3600.0)
	await settle(10)
	await rec("scooter_leaves2", seconds)


## A producer's contract offer, as the card that pauses the game.
func shot_contract_card(seconds: float) -> void:
	await use_world()
	landscape()
	game.show_screen(GameRoot.Screen.WORLD)
	look_port("SHA", 40.0)
	await settle(10)
	var contracts: Contracts = GameState.contracts
	if contracts.offers.is_empty():
		contracts._refresh_offers()
	var best: Dictionary = {}
	for offer: Dictionary in contracts.offers:
		if str(offer.kind) != "tender" and (best.is_empty() or int(offer.value) > int(best.value)):
			best = offer
	if best.is_empty():
		push_error("no contract offer")
		return
	_cards_on = true
	game.event_card.show_offer(best)
	await settle(12)
	var rect := game.event_card.get_global_rect()
	await rec("contract_card", seconds, Callable(), func(_t: float) -> Rect2: return grow(rect, 16.0))
	game.event_card._queue.clear()
	game.event_card.visible = false
	_cards_on = false


## A loaded Trans Atlantic under way for Singapore, well out to sea (past the
## harbour curves, where heading and track agree).
func shot_ship_at_sea2(seconds: float) -> void:
	await use_world()
	portrait()
	var route: Array[String] = ["SHA", "SIN"]
	var ship := stage_ship("model_4", "SHA", route)
	var ok := await warp(2500.0, func() -> bool: return at_sea(ship) and ship.traveled_nm > 500.0, 8)
	print("  at sea: ", ok, " cargo ", ship.cargo_qty)
	follow(ship, 1400.0)
	await settle(15)
	await rec("ship_at_sea2", seconds)


## Ordering a Trans Atlantic: the yards' quotes.
func shot_shop_order(seconds: float) -> void:
	await use_world()
	landscape()
	game.show_screen(GameRoot.Screen.SHOP)
	await settle(15)
	game.get_node("%ShopScreen")._on_buy_pressed("model_4")
	await settle(15)
	var box := popup()
	await rec("shop_order", seconds, Callable(), popup_crop(box))
	if popup() != null:
		PopupHost.find(game).close()
	game.show_screen(GameRoot.Screen.WORLD)


func shot_people_page(seconds: float) -> void:
	await use_world()
	landscape()
	game.show_screen(GameRoot.Screen.PEOPLE)
	await settle(20)
	await rec("people_page", seconds, Callable(), func(_t: float) -> Rect2: return PEOPLE_CROP)
	game.show_screen(GameRoot.Screen.WORLD)


## A Mammoth based at Qingdao and a Scooter lost between Qingdao and Dalian (a lane
## none of the other staged ships use, so nothing passes by on camera), the Mammoth sent.
func _stage_loss2() -> void:
	await use_world()
	if _lost != null and is_instance_valid(_lost) and _lost.is_lost() and _lost.rescuer != null:
		return
	if not GameState.fleet().any(func(s: Ship) -> bool: return s.is_recovery()):
		stage_ship("model_6", "TAO")
	var route: Array[String] = ["TAO", "DLC"]
	var ship := stage_ship("model_1", "TAO", route)
	ship.auto_recover = false
	var ok := await warp(1200.0, func() -> bool: return at_sea(ship) and ship.traveled_nm > 120.0, 8)
	print("  loss staged at sea: ", ok, " ", ship.from_port, "->", ship.to_port, " ", ship.traveled_nm)
	ship.maintenance = 0.0
	GameState._lose(ship, "maintenance")
	var why := GameState.send_recovery(ship)
	print("  recovery: [", why, "] rescuer ", ship.rescuer)
	_lost = ship


func shot_lost_ship2(seconds: float) -> void:
	await _stage_loss2()
	portrait()
	follow(_lost, 2600.0)
	await settle(15)
	await rec("lost_ship2", seconds)


func shot_recovery_lift2(seconds: float) -> void:
	await _stage_loss2()
	portrait()
	var boat := _lost.rescuer
	if boat == null:
		push_error("no rescuer")
		return
	var ok := await warp(4000.0, func() -> bool: return boat.job_phase == Ship.JOB_ALIGN or boat.job_phase == Ship.JOB_TOW, 8)
	print("  lift: ", ok, " phase ", boat.job_phase)
	follow(_lost, 3600.0)
	await settle(5)
	await rec("recovery_lift2", seconds)


## A tempest east of Taiwan (a Divine Action's, so there's one to film in January).
func shot_storm2(seconds: float) -> void:
	await use_world()
	portrait()
	GameState.divine.on = true
	var storm := GameState.weather.spawn_divine("tempest", Vector2(129.0, 22.0), GameState.company.name)
	await warp(30.0, Callable(), 8)
	if storm.is_empty() or not GameState.weather.storms.has(storm):
		storm = GameState.weather.storms[0] if not GameState.weather.storms.is_empty() else {}
	if storm.is_empty():
		push_error("no storm")
		return
	storm.erase("sender")  # (On camera a typhoon with a season's name, not a Divine Action's.)
	storm.name = "Nepartak"
	look(float(storm.lon), float(storm.lat), 64.0)
	await settle(10)
	await rec("storm2", seconds, func(t: float) -> void:
		look(float(storm.lon), float(storm.lat), lerpf(64.0, 74.0, t / seconds)))


## Feeders working up through the Gatún locks.
func shot_panama_locks2(seconds: float) -> void:
	await use_world()
	portrait()
	if not GameState.company.hubs.any(func(h: Hub) -> bool: return h.port_id == "CLN"):
		GameState.company.hubs.append(Hub.new("CLN", false))
	var ships: Array[Ship] = []
	for i in 5:
		var route: Array[String] = ["CLN", "BLB"]
		ships.append(stage_ship("model_2", "CLN", route))
		await warp(25.0, Callable(), 4)
	var ok := await warp(400.0, func() -> bool:
		var in_locks := 0
		for ship in ships:
			if GameState.canal_traffic.in_canal(ship):
				in_locks += 1
		return in_locks >= 3, 4)
	print("  locks: ", ok)
	await rec("panama_locks2", seconds, func(t: float) -> void:
		look(-79.80, 9.152, lerpf(1300.0, 1450.0, t / seconds)))


## A fleet of thirty on routes round the world, then the map pulled back from Shanghai.
func shot_fleet_zoomout(seconds: float) -> void:
	await use_world()
	portrait()
	var routes := [
		["SHA", "SIN"], ["NGB", "SZX"], ["SHA", "VVO"], ["SZX", "SIN"], ["SIN", "MUN"], ["MUN", "DXB"], ["DXB", "PIR"],
		["PIR", "VLC"], ["VLC", "TNG"], ["TNG", "RTM"], ["RTM", "HAM"], ["ANR", "NYC"], ["NYC", "HOU"], ["HOU", "SSZ"],
		["SSZ", "DUR"], ["DUR", "MUN"], ["SIN", "MEL"], ["MEL", "SYD"], ["SYD", "SHA"], ["SHA", "NYC"],
		["SIN", "DXB"], ["SHA", "DXB"], ["RTM", "NYC"], ["TNG", "SSZ"], ["SZX", "SYD"], ["NGB", "SIN"], ["HAM", "PIR"],
		["DXB", "TNG"], ["SIN", "VVO"], ["NYC", "SSZ"]]
	var staged := 0
	for pair: Array in routes:
		var route: Array[String] = []
		for id: String in pair:
			route.append(id)
		var model := "model_3" if GameData.distance_nm(route[0], route[1]) < 1100.0 else "model_4"
		var ship := stage_ship(model, route[0], route)
		if ship.route.is_empty():
			print("  no route ", pair, ": ", GameState.route_error(route, ship))
			continue
		staged += 1
		await warp(20.0, Callable(), 8)
	print("  fleet staged: ", staged)
	await warp(600.0, Callable(), 8)
	warm_traffic()
	look(121.5, 30.5, 90.0)
	await settle(40)
	await rec("fleet_zoomout", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -1.8)
		look(lerpf(121.5, 112.0, k), lerpf(30.5, 22.0, k), exp(lerpf(log(90.0), log(7.0), k))))


## Why the strait is empty: the records under the view, in their window, in view.
func _traffic_diag() -> void:
	var tr: AmbientTraffic = GameState.traffic
	var bounds: Rect2 = map._view_bounds()
	var x0 := clampi(floori((bounds.position.x + 180.0) / AmbientTraffic.CELL) - 2, 0, AmbientTraffic.COLS - 1)
	var x1 := clampi(floori((bounds.end.x + 180.0) / AmbientTraffic.CELL) + 2, 0, AmbientTraffic.COLS - 1)
	var y0 := clampi(floori((bounds.position.y + 180.0) / AmbientTraffic.CELL) - 2, 0, AmbientTraffic.COLS - 1)
	var y1 := clampi(floori((bounds.end.y + 180.0) / AmbientTraffic.CELL) + 2, 0, AmbientTraffic.COLS - 1)
	var total := 0
	var windowed := 0
	var ported := 0
	var seen := 0
	var keyed := 0
	var now: float = GameState.play_time
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			for record: Dictionary in tr._cells.get(cy * AmbientTraffic.COLS + cx, []):
				total += 1
				var home := bool(record.get("ghost_home", false))
				var window := tr._window(record, home)
				if now < float(window[0]) or now > float(window[1]):
					continue
				windowed += 1
				if tr._keys.has(record.ghost_key):
					keyed += 1
				var ports := tr._ports(record, record.ghost_key)
				if ports.is_empty():
					continue
				ported += 1
				var lane: GameData.SeaLane = ports[2]
				var mile: float = (now - float(window[0])) / (float(window[1]) - float(window[0])) * float(ports[3])
				if tr.view_test.call(lane.point_at(mile)):
					seen += 1
				elif windowed <= 5:
					print("    sample: ", record.get("from", "?"), "->", record.get("to", "?"), " at ", lane.point_at(mile), " screen ", map.world_to_screen(lane.point_at(mile)), " cell ", record.get("ghost_cell"), " lane ends ", lane.point_at(0.0), " ", lane.point_at(float(ports[3])))
	print("  diag: SIN projected ", Geo.project(Vector2(103.9, 1.15)), " screen ", map.world_to_screen(Geo.project(Vector2(103.9, 1.15))), " margin ", (map.SHIP_CULL_MARGIN + map.PORT_MAX_REACH) * map._ship_scale())
	print("  diag: bounds ", bounds, " cells ", x0, "-", x1, " x ", y0, "-", y1, " records ", total, " in window ", windowed, " keyed ", keyed, " with lane ", ported, " in view ", seen,
		" | cells indexed ", tr._cells.size(), " round_due ", tr._round_due, " view_cell ", tr._view_cell, " cap ", tr.cap(), " play ", now)


## Fallback for the strait: one of the other firms' ships under way, followed close.
func shot_ghost_follow(seconds: float) -> void:
	await use_world()
	portrait()
	warm_traffic()
	look(120.0, 20.0, map._min_zoom())
	await settle(60)
	var best: Ship = null
	for ghost in GameState.traffic.ghosts:
		if ghost.is_docked() or ghost.from_port.is_empty():
			continue
		var about: Dictionary = ghost.get_meta(&"traffic")
		if ghost.traveled_nm < 50.0 or ghost.traveled_nm > float(about.length) - 50.0:
			continue
		if best == null or float(ghost.model().get("map_size", [0])[0]) > float(best.model().get("map_size", [0])[0]):
			best = ghost
	if best == null:
		push_error("no ghost at sea")
		return
	print("  following ", best.name, " ", best.from_port, "->", best.to_port)
	follow(best, 900.0)
	await settle(20)
	await rec("ghost_follow", seconds, func(_t: float) -> void: follow(best, 900.0))


## From the whole globe down into Shanghai's harbour.
func shot_globe_dive2(seconds: float) -> void:
	await use_world()
	portrait()
	await settle(30)
	var low := map._min_zoom()
	var port := GameData.get_port("SHA")
	await rec("globe_dive2", seconds, func(t: float) -> void:
		var k := ease(t / seconds, -2.2)
		look(lerpf(160.0, float(port.lon), minf(1.0, k * 1.4)), lerpf(15.0, float(port.lat), minf(1.0, k * 1.4)), exp(lerpf(log(low), log(1300.0), k))))


## Why a port's marina is or isn't drawn at this view (the dive's end: Ningbo vanishing).
func _marina_diag(port_id: String) -> void:
	var index := -1
	for i in GameData.ports.size():
		if GameData.ports[i].id == port_id:
			index = i
	var near: Rect2 = Rect2(Vector2.ZERO, map.size).grow(map.MARINA_MAX_REACH * map._ship_scale())
	var item: Variant = map._marina_items.get(port_id)
	var pivot: Node2D = item.get_parent() if item != null else null
	print("  marina ", port_id, " pivot ", (pivot.position if pivot != null else Vector2.ZERO), " pivot scale ", (pivot.scale if pivot != null else Vector2.ZERO), " item scale meta ", (item.get_meta(&"scale", 0.0) if item != null else 0.0), " pending ", map._marinas_pending, ": at ", map.port_screen_position(port_id), " size ", map.size, " scale ", map._ship_scale(), " near ", near,
		" shown ", map._marina_shown(port_id), " kept ", map._kept_marina_ports().has(index), " candidate ", map.marinas_in_view(near).has(index),
		" near_ports ", map._ports_near_view().has(index), " item ", item != null, " item shown ", (item.get_meta(&"shown", true) if item != null else "-"),
		" layout radius ", map._port_layout(port_id).radius, " port radius ", map._port_radius(port_id))

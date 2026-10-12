# Copyright (c) 2026 Rory Ferrick. All rights reserved. Maritime Empire.
class_name Ambience
extends Node
## The World map's sound (a child of MapView): the sea's wash always, a
## harbour's bustle when a marina is on screen, wind and rain under a storm,
## ships' horns as they set off and a fog signal in foul weather, and the
## calls of the animals in view (the birds at the ports on screen, the whales,
## seals and otters, the lions, bears and elephants on the land), picked at
## random every few seconds. Everything is scaled by the zoom, as Crusader
## Kings does it: near silent with the whole world in view, full close in
## (ZOOM_SILENT_DB to 0 dB over the zoom's range, on a log scale). The sounds
## are in audio/ (see audio/CREDITS.md), named by the key they play for.

## The quietest the ambience gets, zoomed right out (dB), and how the zoom
## share is bent (over 1: quiet longer, loud only close in).
const ZOOM_SILENT_DB := -34.0
const ZOOM_CURVE := 1.3
## How often (s) the sounds in view are looked at again, and the animal calls'
## spacing (s, at random between), the longest a call plays (s) before it
## fades, and how many can play at once.
const TICK_S := 0.5
## How many of a colony's birds are looked at for the one shown calling (see _announce_bird()).
const ANNOUNCE_LOOKS := 12
const CALL_EVERY := Vector2(4.0, 9.0)
const CALL_MAX_S := 8.0
const CALL_FADE_S := 1.5
const CALL_VOICES := 3
## From this zoom share up the animals call (zoomed out they're dots) and the
## horns sound; a departing ship on screen sounds its horn this often.
const CALL_FROM_SHARE := 0.3
const HORN_CHANCE := 0.5
const FOGHORN_EVERY := Vector2(25.0, 60.0)
## How fast a loop's volume follows its target (dB/s).
const FOLLOW_DB_S := 24.0

## Each loop: its file key and its gain (dB) for balance.
const LOOPS := {waves = -4.0, wind = -6.0, rain = -8.0}
## Each call's gain (dB): the recordings vary a lot.
const GAINS := {gull = -6.0, tern = -8.0, pelican = -4.0, cormorant = -8.0, shearwater = -6.0, eider = -8.0, scoter = -6.0,
	heron = -6.0, egret = -8.0, bittern = -6.0, crane = -8.0, night_heron = -6.0, eagle = -8.0, hawk = -6.0, falcon = -10.0,
	osprey = -8.0, condor = -4.0, kiwi = -6.0, quetzal = -8.0, toucan = -8.0, penguin = -6.0,
	whale = -2.0, orca = -4.0, seal = -4.0, otter = -8.0,
	bison = -4.0, brown_bear = -4.0, elephant = -2.0, giraffe = -2.0, lemur = -6.0, lion = -2.0, orangutan = -6.0, tiger = -10.0,
	ship_horn = -8.0, ship_horn2 = -14.0, foghorn = -10.0}
## A bird's kind (Birds species "kind") to its call; gulls have no kind (their class is "gulls").
const BIRD_CALLS := {"Tern": "tern", "Pelican": "pelican", "Cormorant": "birds/great_cormorant", "Shearwater": "shearwater", "Eider": "eider",
	"Scoter": "scoter", "Heron": "heron", "Egret": "egret", "Bittern": "bittern", "Crane": "crane", "Night heron": "night_heron",
	"Eagle": "eagle", "Hawk": "hawk", "Falcon": "falcon", "Osprey": "osprey", "Condor": "condor"}
## Gains (dB) for a species' own recording, where it needs one (the grey heron's is loud).
const SPECIES_GAINS := {grey_heron = -14.0}
const BIRD_CLASSES := ["gulls", "seabirds", "cormorants", "sea_ducks", "raptors", "waders"]
## Species that call less often than their numbers would have it (a share of their weight).
const CALL_WEIGHTS := {grey_heron = 0.5}
## A sea animal's kind (SeaLife species "kind") to its call.
const SEA_CALLS := {whale = "whale", orca = "orca", seal = "seal", otter = "otter"}
## A land drawing's kind (WorldMapData decor: the animals) to its call.
const LAND_CALLS := {bison = "bison", brown_bear = "brown_bear", elephant = "elephant", giraffe = "giraffe", lemur = "lemur",
	lion = "lion", orangutan = "orangutan", tiger = "tiger", penguin = "penguin", kiwi = "kiwi", quetzal = "quetzal", toucan = "toucan"}
const AUDIO_DIR := "res://audio/"
const BIRD_DIR := "res://audio/birds/"

## A bird's call has started: the bird itself (BirdLife birds), its colony, its
## species and its state, and how long the call plays (for the SoundTracker).
signal call_started(bird: Dictionary, colony: Dictionary, info: Dictionary, state: Dictionary, seconds: float)

var _map: Control
var _streams := {}  # Key -> AudioStream (loaded once; missing files are left out).
var _loops := {}  # Key -> AudioStreamPlayer.
var _targets := {}  # Key -> the loop's target volume (dB).
var _voices: Array[AudioStreamPlayer] = []
var _horns: Array[AudioStreamPlayer] = []
var _tick := 0.0
var _next_call := 3.0
var _next_foghorn := 20.0
var _share := 0.0
var _rng := RandomNumberGenerator.new()
var _land_animals := []  # [kind key, projected point] of the land's animal drawings with a call.
var _land_scanned := false
var _last_colony := -1  # The colony the last pick came from (a bird call), or -1.


func _init(map: Control) -> void:
	_map = map
	_rng.randomize()


func _ready() -> void:
	for key: String in LOOPS:
		var stream := _stream(key, true, true)
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -80.0
		player.autoplay = false
		player.bus = &"Sea"  # (Its volume on the Settings page.)
		add_child(player)
		player.play(_rng.randf() * maxf(stream.get_length() - 1.0, 0.0))
		_loops[key] = player
		_targets[key] = -80.0
	for i in CALL_VOICES:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"Wildlife"
		add_child(voice)
		_voices.append(voice)
	for i in 2:
		var horn := AudioStreamPlayer.new()
		horn.bus = &"Ships"
		add_child(horn)
		_horns.append(horn)
	if GameState.has_signal(&"ship_departed"):
		GameState.ship_departed.connect(_on_ship_departed)
	_preload_sounds()


## A sound's stream, loaded once (ogg, mp3 or wav in AUDIO_DIR), looping if asked; null if the file isn't there.
func _stream(key: String, looping: bool, now := false) -> AudioStream:
	if _streams.has(key):
		return _streams[key]
	var path := _stream_path(key)
	if path.is_empty():
		_streams[key] = null
		return null
	var stream: AudioStream = null
	if now:
		stream = load(path)
	else:
		# In the background (see _preload_sounds()): a call never waits on a
		# load (a recording takes tens of ms to read), it just goes unplayed till it's in.
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				stream = ResourceLoader.load_threaded_get(path)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				return null
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(path)
				return null
			_:
				_streams[key] = null
				return null
	if stream != null and looping:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		elif stream is AudioStreamMP3:
			(stream as AudioStreamMP3).loop = true
		elif stream is AudioStreamWAV:
			var wav := stream as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
	_streams[key] = stream
	return stream


## A sound's file (ogg, mp3 or wav in AUDIO_DIR), or "" if there's none; looked up once.
var _paths := {}
func _stream_path(key: String) -> String:
	if _paths.has(key):
		return _paths[key]
	var found := ""
	for ext: String in ["ogg", "mp3", "wav"]:
		var path := AUDIO_DIR + key + "." + ext
		if ResourceLoader.exists(path):
			found = path
			break
	_paths[key] = found
	return found

## Asks for every recording in the background at the start (the kinds' and the
## birds' species'), so none is read on the main thread when its animal first calls.
func _preload_sounds() -> void:
	for dir_path: String in [AUDIO_DIR, AUDIO_DIR + "birds/"]:
		for file: String in DirAccess.get_files_at(dir_path):
			var key := file
			while key.get_extension() != "":  # (Exported, a file may be listed as .ogg.import.)
				key = key.get_basename()
			if dir_path != AUDIO_DIR:
				key = "birds/" + key
			var path := _stream_path(key)
			if not path.is_empty() and not _streams.has(key) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				ResourceLoader.load_threaded_request(path)

## The zoom's share of its range, 0 with the whole world in view to 1 close in (log scale, bent by ZOOM_CURVE).
func zoom_share() -> float:
	var low := log(maxf(_map._min_zoom(), 0.01))
	var high := log(MapView.MAX_ZOOM)
	return pow(clampf((log(maxf(_map._zoom, 0.01)) - low) / maxf(high - low, 0.001), 0.0, 1.0), ZOOM_CURVE)


## The ambience's volume at this zoom (dB).
func base_db() -> float:
	return lerpf(ZOOM_SILENT_DB, 0.0, _share)


func _process(delta: float) -> void:
	var t_x := Time.get_ticks_usec()
	_process_timed(delta)
	MapView._prof("proc.ambience", t_x)

func _process_timed(delta: float) -> void:
	# The loops follow their targets smoothly every frame.
	for key: String in _loops:
		var player: AudioStreamPlayer = _loops[key]
		player.volume_db = move_toward(player.volume_db, float(_targets[key]), FOLLOW_DB_S * delta)
	_tick += delta
	if _tick < TICK_S:
		return
	_tick = 0.0
	var on: bool = _map.show_ships and not _map.gray_mode and _map.is_visible_in_tree()
	if not on:
		for key: String in _targets:
			_targets[key] = -80.0
		return
	var t_a := Time.get_ticks_usec()
	_share = zoom_share()
	var base := base_db()
	var center_lon_lat: Vector2 = Geo.unproject(_map.screen_to_world(_map.size / 2.0))
	var at_sea: bool = SeaLife.shared().is_sea(center_lon_lat)
	var storm := 0.0
	if not GameState.weather.storms.is_empty():
		storm = float(GameState.weather.strongest_at(center_lon_lat)[1])
	# The sea's wash: everywhere, softer over the land close in.
	_targets["waves"] = base + float(LOOPS.waves) + (0.0 if at_sea or _share < 0.5 else -9.0)
	MapView._prof("amb.head", t_a)
	t_a = Time.get_ticks_usec()
	var marina := _marina_in_view()  # (A marina on screen: the fog signal sounds there in foul weather.)
	MapView._prof("amb.marina", t_a)
	t_a = Time.get_ticks_usec()
	# Wind and rain under a storm (the wind a little always, zoomed in).
	_targets["wind"] = base + float(LOOPS.wind) + lerpf(-18.0, 0.0, storm)
	_targets["rain"] = base + float(LOOPS.rain) + lerpf(-30.0, 0.0, storm) if storm > 0.25 else -80.0
	# The animals in view, now and then.
	_next_call -= TICK_S
	if _next_call <= 0.0 and _share >= CALL_FROM_SHARE:
		_next_call = _rng.randf_range(CALL_EVERY.x, CALL_EVERY.y) * lerpf(1.6, 0.8, _share)
		var t_p := Time.get_ticks_usec()
		var key := _pick_call()
		MapView._prof("amb.pick", t_p)
		if not key.is_empty():
			var gain := float(GAINS.get(key, SPECIES_GAINS.get(key.get_file(), GAINS.get(key.get_file(), -6.0))))
			t_p = Time.get_ticks_usec()
			var played := _play_call(key, base + gain + _rng.randf_range(-3.0, 0.0))
			MapView._prof("amb.play", t_p)
			if played and _last_colony >= 0:
				t_p = Time.get_ticks_usec()
				_announce_bird(_last_colony, key)
				MapView._prof("amb.announce", t_p)
	MapView._prof("amb.calls", t_a)
	# The fog signal, in foul weather with a port on screen.
	_next_foghorn -= TICK_S
	if _next_foghorn <= 0.0:
		_next_foghorn = _rng.randf_range(FOGHORN_EVERY.x, FOGHORN_EVERY.y)
		if storm > 0.5 and marina > 0.0 and _share >= CALL_FROM_SHARE:
			_play_horn("foghorn", base + float(GAINS.foghorn))


## How much of the screen the biggest marina in view takes (0: none shown).
func _marina_in_view() -> float:
	var best := 0.0
	if not _map._any_marina_shown():
		return 0.0
	var area := Rect2(Vector2.ZERO, _map.size).grow(100.0)
	for index: int in _map.marinas_in_view(area):  # (Not every port: a layout each is a lot.)
		var id: String = GameData.ports[index].id
		if not _map._marina_shown(id):
			continue
		var at: Vector2 = _map.port_screen_position(id)
		if not area.has_point(at):
			continue
		var radius: float = float(_map._port_layout(id).radius) * _map._ship_scale()
		best = maxf(best, clampf(radius / 250.0, 0.0, 1.0))
	return best


## A call from the animals in view: the birds at the ports on screen (each
## species by its numbers), the pods, and the land's animals; "" if none.
func _pick_call() -> String:
	var picks := []  # [key, weight]
	var area := Rect2(Vector2.ZERO, _map.size)
	var cal := float(GameState.calendar_time())
	var wildlife := Wildlife.shared()
	var birds := Birds.shared()
	for index: int in _map.marinas_in_view(area):
		var id: String = GameData.ports[index].id
		if not area.has_point(_map.port_screen_position(id)) or not _map._marina_shown(id):
			continue
		for cls: String in BIRD_CLASSES:
			for entry: Dictionary in wildlife.birds_at(id, cls, cal):
				var species := str(entry.id)
				var key := "birds/" + species
				if _stream_path(key).is_empty():  # No recording of the species itself: its kind's.
					key = "gull" if cls == "gulls" else str(BIRD_CALLS.get(str(birds.species(species).get("kind", "")), ""))
				if randf() < 0.5 and not _stream_path(key + "_2").is_empty():  # (A second take of it, some of the time.)
					key += "_2"
				if not key.is_empty() and not _stream_path(key).is_empty():
					picks.append([key, sqrt(float(entry.count)) * float(CALL_WEIGHTS.get(species, 1.0)), int(entry.colony)])
	var sea := SeaLife.shared()
	for hit: Array in _map._pod_hit_list():
		var pod: Dictionary = sea.pods[int(hit[0])]
		var kind := str((sea.species.get(pod.species, {}) as Dictionary).get("kind", ""))
		var key := str(SEA_CALLS.get(kind, ""))
		if not key.is_empty() and not _stream_path(key).is_empty():
			picks.append([key, 3.0])
	if not _land_scanned:
		_scan_land_animals()
	for animal: Array in _land_animals:
		if area.has_point(_map.world_to_screen(animal[1])):
			picks.append([animal[0], 3.0])
	if picks.is_empty():
		return ""
	var total := 0.0
	for pick: Array in picks:
		total += float(pick[1])
	var roll := _rng.randf() * total
	var chosen: Array = picks[-1]
	for pick: Array in picks:
		roll -= float(pick[1])
		if roll <= 0.0:
			chosen = pick
			break
	_last_colony = int(chosen[2]) if chosen.size() > 2 else -1
	return str(chosen[0])


## The land's animal drawings with a call (they're the first drawings of the map's decor).
func _scan_land_animals() -> void:
	_land_scanned = true
	var data: WorldMapData = GameData.world_map
	if data == null:
		return
	for i in mini(data.decor_positions.size(), 200):
		var kind := str(data.decor_kind_names[data.decor_kinds[i]])
		if LAND_CALLS.has(kind) and not _stream_path(str(LAND_CALLS[kind])).is_empty():
			_land_animals.append([str(LAND_CALLS[kind]), data.decor_positions[i]])


## Plays a call on a free voice (none free: skipped), from a random point in
## the recording, fading out after CALL_MAX_S. True if it played.
func _play_call(key: String, db: float) -> bool:
	var stream := _stream(key, false)
	if stream == null:
		return false
	for voice in _voices:
		if voice.playing:
			continue
		voice.stream = stream
		voice.volume_db = db
		var length := stream.get_length()
		var from := _rng.randf() * maxf(length - CALL_MAX_S, 0.0) if length > CALL_MAX_S + 2.0 else 0.0
		voice.play(from)
		if length - from > CALL_MAX_S:
			var tween := create_tween()
			tween.tween_interval(CALL_MAX_S - CALL_FADE_S)
			tween.tween_property(voice, "volume_db", -60.0, CALL_FADE_S)
			tween.tween_callback(voice.stop)
		_last_seconds = minf(length - from, CALL_MAX_S)
		return true
	return false


## How long the last call plays (s), for the tracker.
var _last_seconds := 0.0


## Tells the tracker which bird is calling: one of the colony's birds (the
## first that's awake and about, else the first), as the map draws it now.
func _announce_bird(colony_index: int, _key: String) -> void:
	var wildlife := Wildlife.shared()
	var life := BirdLife.shared()
	if colony_index < 0 or colony_index >= wildlife.colonies.size() or not life.ensure_built():
		return
	var colony: Dictionary = wildlife.colonies[colony_index]
	var indices: Array = life.birds_of(colony_index)
	if indices.is_empty():
		return
	var now := wildlife.bird_time
	var cal := float(GameState.calendar_time())
	var chosen := int(indices[0])
	var state: Dictionary = life.bird_state(chosen, now, cal)
	for index: int in indices.slice(0, ANNOUNCE_LOOKS):  # (A few of them: each is a look at a bird.)
		var each: Dictionary = life.bird_state(index, now, cal)
		if str(each.get("mode", "")) in ["fly", "circle", "soar", "glide", "stand", "swim", "walk", "stalk"]:
			chosen = index
			state = each
			break
	call_started.emit(life.birds[chosen], colony, Birds.shared().species(str(colony.species)), state, _last_seconds)


func _play_horn(key: String, db: float) -> void:
	var stream := _stream(key, false)
	if stream == null:
		return
	for horn in _horns:
		if horn.playing:
			continue
		horn.stream = stream
		horn.volume_db = db
		horn.play()
		if stream.get_length() > CALL_MAX_S:
			var tween := create_tween()
			tween.tween_interval(CALL_MAX_S - CALL_FADE_S)
			tween.tween_property(horn, "volume_db", -60.0, CALL_FADE_S)
			tween.tween_callback(horn.stop)
		return


## A ship setting off on screen sounds its horn (HORN_CHANCE), close in.
func _on_ship_departed(ship: Ship, _port_id: String, _sale: int, _fuel_cost: int, _repair_cost: int, _toll: int) -> void:
	if _share < CALL_FROM_SHARE + 0.1 or _rng.randf() > HORN_CHANCE:
		return
	if not Rect2(Vector2.ZERO, _map.size).has_point(_map.ship_screen_position(ship)):
		return
	var key := "ship_horn" if _rng.randf() < 0.7 else "ship_horn2"
	_play_horn(key, base_db() + float(GAINS.get(key, -8.0)))
